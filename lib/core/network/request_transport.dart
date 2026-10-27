import 'package:http/http.dart' as http;

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
final class HttpRequestTransport implements RequestTransport {
  HttpRequestTransport(this.baseUri, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final uri = baseUri.resolve(path);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw ArgumentError('API base URL must use HTTP or HTTPS.');
    }
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = body;
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed)
        .timeout(const Duration(seconds: 20));
    return ApiReply(response.statusCode, response.body, response.headers);
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
  }) => Future.error(StateError('An authenticated session is required.'));
}
