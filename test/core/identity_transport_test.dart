import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:swiftdrop_mobile/core/config/identity_config.dart';
import 'package:swiftdrop_mobile/core/errors/identity_exception.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';

void main() {
  group('HTTPS configuration', () {
    for (final origin in [
      '',
      'http://localhost:5000',
      'http://10.0.2.2:5000',
      'https://user:secret@example.test',
      'https://example.test/api',
      'https://example.test?token=private',
      'https://example.test#fragment',
    ]) {
      test('rejects $origin', () {
        expect(
          () => IdentityConfig(apiOrigin: Uri.parse(origin)),
          throwsA(
            isA<IdentityException>().having(
              (error) => error.code,
              'code',
              'invalid_configuration',
            ),
          ),
        );
      });
    }
    test(
      'supports a configured public HTTPS origin and explicit Courier mode',
      () {
        final config = IdentityConfig(
          apiOrigin: Uri.parse('https://gateway.example.test:8443'),
          appMode: IdentityAppMode.courier,
        );
        expect(config.appMode, IdentityAppMode.courier);
        expect(config.apiOrigin.host, 'gateway.example.test');
      },
    );
  });

  group('Native transport', () {
    for (final path in [
      'https://attacker.example.test/api/v1/users/me',
      '//attacker.example.test/api/v1/users/me',
      '/unrelated',
      '/api/v1/../auth',
      '/api/v1/%2e%2e/auth',
      '/api/v1/%2fauth',
      '/api/v1/%252fauth',
      '/api/v1/users#fragment',
    ]) {
      test(
        'rejects an unsafe credential destination $path before HTTP',
        () async {
          var calls = 0;
          final transport = HttpRequestTransport(
            Uri.parse('https://gateway.example.test'),
            client: MockClient((request) async {
              calls++;
              return http.Response('{}', 200);
            }),
          );
          addTearDown(transport.close);
          await expectLater(
            transport.send(
              'GET',
              path,
              headers: {'Authorization': 'Bearer private-fixture'},
            ),
            throwsA(
              isA<IdentityException>().having(
                (error) => error.code,
                'code',
                'invalid_request',
              ),
            ),
          );
          expect(calls, 0);
        },
      );
    }
    for (final header in [
      'Origin',
      'Cookie',
      'X-User-Id',
      'X-User-Roles',
      'X-API-Key',
    ]) {
      test(
        'rejects $header instead of switching native credential contracts',
        () async {
          final transport = HttpRequestTransport(
            Uri.parse('https://gateway.example.test'),
            client: MockClient((request) async {
              fail('Invalid headers must not be sent.');
            }),
          );
          addTearDown(transport.close);
          await expectLater(
            transport.send(
              'GET',
              '/api/v1/users/me',
              headers: {header: 'untrusted'},
            ),
            throwsA(isA<IdentityException>()),
          );
        },
      );
    }
    test(
      'retains legitimate bearer, content type and idempotency headers',
      () async {
        final transport = HttpRequestTransport(
          Uri.parse('https://gateway.example.test'),
          client: MockClient((request) async {
            expect(
              request.url.toString(),
              'https://gateway.example.test/api/v1/parcels',
            );
            expect(request.headers['Authorization'], 'Bearer private-fixture');
            expect(request.headers['Idempotency-Key'], 'booking-attempt-id');
            expect(request.followRedirects, false);
            expect(jsonDecode(request.body), {'quoteId': 'fixture'});
            return http.Response(
              '{"id":"safe"}',
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(transport.close);
        final reply = await transport.send(
          'POST',
          '/api/v1/parcels',
          body: '{"quoteId":"fixture"}',
          headers: {
            'Authorization': 'Bearer private-fixture',
            'Idempotency-Key': 'booking-attempt-id',
            'Content-Type': 'application/json',
          },
        );
        expect(reply.status, 201);
        expect(reply.body, '{"id":"safe"}');
      },
    );
    test('does not follow redirects with credentials', () async {
      var calls = 0;
      final transport = HttpRequestTransport(
        Uri.parse('https://gateway.example.test'),
        client: MockClient((request) async {
          calls++;
          return http.Response(
            '',
            302,
            headers: {'location': 'https://attacker.example.test/collect'},
          );
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.send(
          'GET',
          '/api/v1/users/me',
          headers: {'Authorization': 'Bearer private-fixture'},
        ),
        throwsA(isA<IdentityException>()),
      );
      expect(calls, 1);
    });
    test('bounds request size in UTF8 bytes before sending', () async {
      var calls = 0;
      final transport = HttpRequestTransport(
        Uri.parse('https://gateway.example.test'),
        client: MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.send('POST', '/api/v1/auth/login', body: '界' * 6000),
        throwsA(isA<IdentityException>()),
      );
      expect(calls, 0);
    });
    test('bounds response size before parsing', () async {
      final transport = HttpRequestTransport(
        Uri.parse('https://gateway.example.test'),
        client: MockClient(
          (request) async => http.Response('a' * 1048577, 200),
        ),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.send('GET', '/api/v1/users/me'),
        throwsA(
          isA<IdentityException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });
    test('does not expose raw client errors or credentials', () async {
      final transport = HttpRequestTransport(
        Uri.parse('https://gateway.example.test'),
        client: MockClient(
          (request) async =>
              throw http.ClientException('private-fixture-token'),
        ),
      );
      addTearDown(transport.close);
      try {
        await transport.send('GET', '/api/v1/users/me');
        fail('Expected safe failure.');
      } on IdentityException catch (error) {
        expect(error.code, 'network_error');
        expect(error.toString(), isNot(contains('private-fixture-token')));
      }
    });
    testWidgets(
      'deadline aborts an unfinished request without exposing a URL',
      (tester) async {
        final client = PendingClient();
        final transport = HttpRequestTransport(
          Uri.parse('https://gateway.example.test'),
          client: client,
        );
        addTearDown(transport.close);
        final pending = transport.send('GET', '/api/v1/users/me');
        final result = expectLater(
          pending,
          throwsA(
            isA<IdentityException>().having(
              (error) => error.code,
              'code',
              'network_error',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 21));
        await result;
        expect(client.aborted, true);
      },
    );
  });
}

final class PendingClient extends http.BaseClient {
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final result = Completer<http.StreamedResponse>();
    (request as http.Abortable).abortTrigger!.then((_) {
      aborted = true;
      if (!result.isCompleted) {
        result.completeError(http.RequestAbortedException());
      }
    });
    return result.future;
  }
}
