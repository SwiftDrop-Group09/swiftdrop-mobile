import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
      throw ArgumentError('Use a credential-free HTTP or HTTPS API base.');
    }
    // Check before Uri parsing normalizes literal/encoded dot segments away.
    if (path.split(RegExp(r'[?#]')).first.split('/').any(unsafeSegment)) {
      throw ArgumentError('Use an API path on the configured origin.');
    }
    final reference = Uri.tryParse(path);
    if (reference == null ||
        reference.hasScheme ||
        reference.hasAuthority ||
        reference.hasFragment ||
        path.contains(r'\') ||
        reference.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains(r'\') ||
              part.contains('%'),
        )) {
      throw ArgumentError('Use an API path on the configured origin.');
    }
    final uri = baseUri.resolveUri(reference);
    if (uri.origin != baseUri.origin) {
      throw ArgumentError('Use an API path on the configured origin.');
    }
    return uri;
  }

  Future<ApiReply> _readResponse(http.StreamedResponse response) async {
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.listen((_) {}).cancel();
      throw http.ClientException('API redirects are not allowed.');
    }
    final reply = await http.Response.fromStream(response);
    return ApiReply(reply.statusCode, reply.body, reply.headers);
  }

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final uri = _resolve(path);
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..followRedirects = false;
    if (body != null) request.body = body;
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    return _readResponse(streamed).timeout(const Duration(seconds: 20));
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
  }) => Future.error(StateError('An authenticated session is required.'));
}
