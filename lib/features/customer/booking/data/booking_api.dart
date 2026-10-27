import '../../../../core/network/exact_json.dart';
import '../../../../core/network/request_transport.dart';
import '../domain/booking_models.dart';

final class BookingApiFailure implements Exception {
  const BookingApiFailure(
    this.status,
    this.code, {
    this.retryAfter = 1,
    this.errors = const {},
  });
  final int status;
  final String code;
  final int retryAfter;
  final Map<String, String> errors;
}

final class BookingApi {
  const BookingApi(this.transport);
  final RequestTransport transport;

  Future<DeliveryQuote> estimate(BookingDraft draft) async {
    final reply = await transport.send(
      'POST',
      '/api/v1/quotes',
      body: draft.encode(),
      headers: const {'Content-Type': 'application/json'},
    );
    if (reply.status != 200) throw _problem(reply);
    return DeliveryQuote.fromJson(jsonObject(decodeExactJson(reply.body)));
  }

  Future<BookingReceipt> confirm(String body, String key) async {
    final reply = await transport.send(
      'POST',
      '/api/v1/parcels',
      body: body,
      headers: {'Content-Type': 'application/json', 'Idempotency-Key': key},
    );
    if (reply.status != 201) throw _problem(reply);
    return BookingReceipt.fromJson(jsonObject(decodeExactJson(reply.body)));
  }

  BookingApiFailure _problem(ApiReply reply) {
    var code = 'request_failed';
    final errors = <String, String>{};
    try {
      final payload = jsonObject(decodeExactJson(reply.body));
      if (payload['code'] is String) code = payload['code']! as String;
      final fields = payload['errors'];
      if (fields is Map<String, Object?>) {
        for (final field in fields.entries) {
          if (!const [
            'pickupAddress.street',
            'pickupAddress.city',
            'pickupAddress.postalCode',
            'pickupAddress.zoneId',
            'deliveryAddress.street',
            'deliveryAddress.city',
            'deliveryAddress.postalCode',
            'deliveryAddress.zoneId',
            'recipient.name',
            'recipient.phoneNumber',
            'packageDetails.weightKg',
            'packageDetails.size',
          ].contains(field.key)) {
            continue;
          }
          if (field.value is List) {
            final messages = (field.value! as List).whereType<String>();
            if (messages.isNotEmpty) errors[field.key] = messages.first;
          }
        }
      }
    } on FormatException {
      // Never display raw upstream bodies or parser details.
    }
    final delay = int.tryParse(reply.headers['retry-after'] ?? '') ?? 1;
    return BookingApiFailure(
      reply.status,
      code,
      retryAfter: delay.clamp(1, 3600),
      errors: Map.unmodifiable(errors),
    );
  }
}
