import '../../core/network/exact_json.dart';
import '../../core/network/request_transport.dart';
import 'courier_models.dart';

final class CourierException implements Exception {
  const CourierException(this.code, {this.status = 0, this.retryAfter = 1});
  final String code;
  final int status, retryAfter;
  bool get uncertain =>
      status == 0 || status >= 500 || code == 'operation_in_progress';
  String get message => switch (code) {
    'stale_version' || 'invalid_transition' =>
      'This parcel changed. Current state is reloaded; choose a new action.',
    'unauthorized' => 'Sign in again to continue.',
    'forbidden' => 'A Courier account is required.',
    'not_found' => 'This parcel is no longer available to your account.',
    'proof_unavailable' =>
      'Proof upload is unavailable. Please reconnect and try again.',
    'validation_error' => 'Check the required fields, failure reason and JPEG/PNG proof (up to 5 MiB each).',
    'operation_in_progress' => 'The original request is still processing. Retry the original request shortly.',
    'idempotency_conflict' || 'key_expired' => 'This retained request cannot be reused. Reload before choosing another action.',
    _ => 'Delivery could not confirm the request. Check your connection and retry the original request.',
  };
}

final class CourierApi {
  const CourierApi(this.transport);
  final RequestTransport transport;
  Object? _decode(ApiReply r) {
    if (r.status != 200) {
      var code = switch (r.status) {
        401 => 'unauthorized',
        403 => 'forbidden',
        404 => 'not_found',
        _ => 'delivery_unavailable',
      };
      try {
        final v = object(decodeExactJson(r.body));
        if (v['code'] is String) code = v['code'] as String;
      } catch (_) {
        /* Static fallback. */
      }
      throw CourierException(
        code,
        status: r.status,
        retryAfter: (int.tryParse(r.headers['retry-after'] ?? '') ?? 1).clamp(
          1,
          60,
        ),
      );
    }
    try {
      return decodeExactJson(r.body);
    } catch (_) {
      throw const CourierException('invalid_response');
    }
  }

  Future<T> _read<T>(
    String path,
    T Function(Map<String, Object?>) decode,
  ) async {
    try {
      return decode(object(_decode(await transport.send('GET', path))));
    } on CourierException {
      rethrow;
    } catch (_) {
      throw const CourierException('network');
    }
  }

  Future<CourierPage<AssignedParcel>> manifest({
    String? date,
    bool includeOverdue = true,
    int page = 1,
  }) {
    final query = Uri(
      queryParameters: {
        'date': ?date,
        'includeOverdue': '$includeOverdue',
        'page': '$page',
        'pageSize': '20',
      },
    ).query;
    return _read(
      '/api/v1/couriers/me/assignments?$query',
      (v) => CourierPage.fromJson(v, AssignedParcel.fromJson),
    );
  }

  Future<CourierPage<ParcelSummary>> history({int page = 1}) => _read(
    '/api/v1/couriers/me/history?page=$page&pageSize=20',
    (v) => CourierPage.fromJson(v, ParcelSummary.fromJson),
  );
  Future<ParcelDetail> detail(String id) {
    identifier({'id': id}, 'id');
    return _read('/api/v1/parcels/$id', ParcelDetail.fromJson);
  }

  Future<ParcelSummary> submit(
    CourierAttempt a, {
    void Function(int, int)? onProgress,
  }) async {
    try {
      final ApiReply reply;
      if (a.body != null) {
        reply = await transport.send(
          'PUT',
          '/api/v1/deliveries/${a.id}/status',
          body: a.body,
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': a.key,
          },
        );
      } else {
        final port = transport;
        if (port is! MultipartRequestTransport) {
          throw const CourierException('proof_unavailable', status: 400);
        }
        reply = await (port as MultipartRequestTransport).sendMultipart(
          '/api/v1/deliveries/${a.id}/pod',
          {
            'expectedVersion': a.version.plain,
            'recipientName': a.recipientName!,
          },
          [?a.photo, ?a.signature],
          headers: {'Idempotency-Key': a.key},
          onProgress: onProgress,
        );
      }
      final result = ParcelSummary.fromJson(object(_decode(reply)));
      if (result.id != a.id ||
          result.status != a.status ||
          BigInt.parse(result.version.plain) !=
              BigInt.parse(a.version.plain) + BigInt.one) {
        throw const CourierException('invalid_response');
      }
      return result;
    } on CourierException {
      rethrow;
    } catch (_) {
      throw const CourierException('network');
    }
  }

  static CourierAttempt statusAttempt(
    ParcelDetail d,
    String status,
    String notes,
    String key, {
    String? failureReason,
  }) {
    if (!d.summary.active ||
        (status == 'Failed'
            ? !failureReasons.contains(failureReason)
            : nextStages[d.summary.status] != status) ||
        notes.length > 500 ||
        (status != 'Failed' && notes.trim().isEmpty)) {
      throw const CourierException('validation_error', status: 400);
    }
    return CourierAttempt(
      id: d.summary.id,
      version: d.summary.version,
      status: status,
      key: key,
      body: encodeExactJson({
        'status': status,
        'expectedVersion': d.summary.version,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        if (status == 'Failed') 'failureReason': failureReason,
      }),
    );
  }

  static CourierAttempt proofAttempt(
    ParcelDetail d,
    String name,
    String key, {
    UploadPart? photo,
    UploadPart? signature,
  }) {
    if (d.summary.status != 'OutForDelivery' ||
        name.trim().isEmpty ||
        name.length > 120 ||
        (photo == null && signature == null)) {
      throw const CourierException('validation_error', status: 400);
    }
    for (final f in [?photo, ?signature]) {
      if (!const ['image/jpeg', 'image/png'].contains(f.mimeType) ||
          f.bytes.isEmpty ||
          f.bytes.length > 5 * 1024 * 1024) {
        throw const CourierException('validation_error', status: 400);
      }
    }
    return CourierAttempt(
      id: d.summary.id,
      version: d.summary.version,
      status: 'Delivered',
      key: key,
      recipientName: name.trim(),
      photo: photo,
      signature: signature,
    );
  }
}
