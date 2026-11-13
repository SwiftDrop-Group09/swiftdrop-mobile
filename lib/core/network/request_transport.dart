import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../errors/identity_exception.dart';

final class UploadPart {
  UploadPart(this.field, this.mimeType, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String field;
  final String mimeType;
  final Uint8List bytes;
}

/// Optional capability on the same IAM-authenticated transport.
abstract interface class MultipartRequestTransport {
  Future<ApiReply> sendMultipart(
    String path,
    Map<String, String> fields,
    List<UploadPart> files, {
    Map<String, String> headers = const {},
    void Function(int sent, int total)? onProgress,
  });
}

class _ProgressRequest extends http.MultipartRequest with http.Abortable {
  _ProgressRequest(super.method, super.url, this.onProgress, this.abortTrigger);
  final void Function(int sent, int total)? onProgress;
  @override
  final Future<void>? abortTrigger;
  @override
  http.ByteStream finalize() {
    var sent = 0;
    final total = contentLength;
    return http.ByteStream(
      super.finalize().map((bytes) {
        sent += bytes.length;
        onProgress?.call(sent, total);
        return bytes;
      }),
    );
  }
}

final class ApiReply {
  const ApiReply(this.status, this.body, [this.headers = const {}]);
  final int status;
  final String body;
  final Map<String, String> headers;
}

/// The IAM integration supplies an authenticated implementation of this port.
abstract interface class RequestTransport {
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  });
}

/// Ordinary HTTP transport; credentials, when needed, belong to the host's
/// authenticated client. This class never creates or stores a user identity.
final class HttpRequestTransport
    implements RequestTransport, MultipartRequestTransport {
  HttpRequestTransport(this.baseUri, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;
  static const _allowedHeaders = {
    'authorization',
    'content-type',
    'accept',
    'idempotency-key',
    'x-correlation-id',
    'if-match',
  };

  void _validateHeaders(Map<String, String> headers) {
    if (headers.keys.any(
          (key) => !_allowedHeaders.contains(key.toLowerCase()),
        ) ||
        headers.values.any(
          (value) => value.contains('\r') || value.contains('\n'),
        )) {
      throw const IdentityException('invalid_request');
    }
  }

  Uri _resolve(String path) {
    bool unsafeSegment(String segment) {
      try {
        final decoded = Uri.decodeComponent(segment);
        return decoded == '.' ||
            decoded == '..' ||
            decoded.contains('/') ||
            decoded.contains(r'\') ||
            decoded.contains('%');
      } on FormatException {
        return true;
      }
    }

    if (!baseUri.isAbsolute ||
        !baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        !const ['https', 'http'].contains(baseUri.scheme) ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.scheme == 'http' &&
            !const ['localhost', '127.0.0.1', '::1'].contains(baseUri.host))) {
      throw const IdentityException('invalid_configuration');
    }
    // Check before Uri parsing normalizes literal/encoded dot segments away.
    if (path.split(RegExp(r'[?#]')).first.split('/').any(unsafeSegment)) {
      throw const IdentityException('invalid_request');
    }
    final reference = Uri.tryParse(path);
    if (reference == null ||
        reference.hasScheme ||
        reference.hasAuthority ||
        reference.hasFragment ||
        (!reference.path.startsWith('/api/v1/') &&
            !(const ['localhost', '127.0.0.1', '::1'].contains(baseUri.host) &&
                reference.path.startsWith('/__test/'))) ||
        path.contains(r'\') ||
        reference.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains(r'\') ||
              part.contains('%'),
        )) {
      throw const IdentityException('invalid_request');
    }
    final uri = baseUri.resolveUri(reference);
    if (uri.origin != baseUri.origin) {
      throw const IdentityException('invalid_request');
    }
    return uri;
  }

  Future<ApiReply> _readResponse(http.StreamedResponse response) async {
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.listen((_) {}).cancel();
      throw const IdentityException('network_error');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 1048576) {
        throw const IdentityException('invalid_response');
      }
      bytes.addAll(chunk);
    }
    return ApiReply(
      response.statusCode,
      utf8.decode(bytes),
      Map.unmodifiable(response.headers),
    );
  }

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final uri = _resolve(path);
    _validateHeaders(headers);
    if (!const {'GET', 'POST', 'PUT', 'DELETE'}.contains(method) ||
        (body != null && utf8.encode(body).length > 16384)) {
      throw const IdentityException('invalid_request');
    }
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..headers.addAll(headers)
          ..followRedirects = false;
    if (body != null) request.body = body;
    try {
      return await (() async {
        final streamed = await _client.send(request);
        return _readResponse(streamed);
      })().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw const IdentityException('network_error');
        },
      );
    } on IdentityException {
      rethrow;
    } on Exception {
      throw const IdentityException('network_error');
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  void close() => _client.close();

  @override
  Future<ApiReply> sendMultipart(
    String path,
    Map<String, String> fields,
    List<UploadPart> files, {
    Map<String, String> headers = const {},
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = _resolve(path);
    _validateHeaders(headers);
    final abort = Completer<void>();
    final request = _ProgressRequest('POST', uri, onProgress, abort.future)
      ..headers.addAll(headers)
      ..fields.addAll(fields)
      ..followRedirects = false;
    for (final file in files) {
      final type = file.mimeType.split('/');
      request.files.add(
        http.MultipartFile.fromBytes(
          file.field,
          file.bytes,
          filename: '${file.field}.${type.last == 'jpeg' ? 'jpg' : 'png'}',
          contentType: http.MediaType(type.first, type.last),
        ),
      );
    }
    try {
      return await (() async {
        final streamed = await _client.send(request);
        return _readResponse(streamed);
      })().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('Proof confirmation timed out.');
        },
      );
    } on IdentityException {
      rethrow;
    } on Exception {
      throw const IdentityException('network_error');
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }
}

final class UnavailableTransport implements RequestTransport {
  const UnavailableTransport();

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) => Future.error(const IdentityException('invalid_credentials'));
}
