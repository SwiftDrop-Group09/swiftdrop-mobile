import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/identity_config.dart';
import '../errors/identity_exception.dart';

final class ApiReply {
  const ApiReply(this.status, this.body, [this.headers = const {}]);
  final int status;
  final String body;
  final Map<String, String> headers;
}

/// Compatible with the independently owned booking transport port.
abstract interface class RequestTransport {
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  });
}

final class HttpRequestTransport implements RequestTransport {
  HttpRequestTransport(this.baseUri, {http.Client? client})
    : _client = client ?? http.Client() {
    validateApiOrigin(baseUri);
  }

  final Uri baseUri;
  final http.Client _client;
  static const _requestLimit = 16384;
  static const _responseLimit = 1048576;
  static const _timeout = Duration(seconds: 20);
  static const _allowedHeaders = {
    'authorization',
    'content-type',
    'accept',
    'idempotency-key',
    'x-correlation-id',
    'if-match',
  };

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final reference = Uri.tryParse(path);
    if (reference == null ||
        reference.hasScheme ||
        reference.hasAuthority ||
        reference.hasFragment ||
        !reference.path.startsWith('/api/v1/') ||
        path.contains('\\') ||
        reference.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\') ||
              part.contains('%'),
        ) ||
        !const {'GET', 'POST', 'PUT', 'DELETE'}.contains(method) ||
        headers.keys.any(
          (key) => !_allowedHeaders.contains(key.toLowerCase()),
        ) ||
        headers.values.any(
          (value) => value.contains('\r') || value.contains('\n'),
        ) ||
        (body != null && utf8.encode(body).length > _requestLimit)) {
      throw const IdentityException('invalid_request');
    }
    final uri = baseUri.resolveUri(reference);
    if (uri.origin != baseUri.origin) {
      throw const IdentityException('invalid_request');
    }
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.body = body;
    try {
      return await (() async {
        final response = await _client.send(request);
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen((_) {}).cancel();
          throw const IdentityException('network_error');
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > _responseLimit) {
            throw const IdentityException('invalid_response');
          }
          bytes.addAll(chunk);
        }
        return ApiReply(
          response.statusCode,
          utf8.decode(bytes),
          Map.unmodifiable(response.headers),
        );
      })().timeout(
        _timeout,
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
