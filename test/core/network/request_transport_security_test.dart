import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';

void main() {
  for (final base in [
    'http://delivery.example.test',
    'https://user:fictional@delivery.example.test',
    'https://delivery.example.test/?key=fictional',
    'https://delivery.example.test/#fragment',
    'file:///not-an-api',
  ]) {
    for (final multipart in [false, true]) {
      test(
        '${multipart ? 'proof' : 'JSON'} rejects unsafe API configuration $base',
        () async {
          var calls = 0;
          final transport = HttpRequestTransport(
            Uri.parse(base),
            client: MockClient((_) async {
              calls++;
              return http.Response('{}', 200);
            }),
          );
          addTearDown(transport.close);
          await expectLater(
            multipart
                ? transport.sendMultipart(
                    '/api/v1/deliveries/00000000-0000-4000-8000-000000000011/pod',
                    {},
                    [],
                  )
                : transport.send('GET', '/api/v1/couriers/me/assignments'),
            throwsArgumentError,
          );
          expect(calls, 0);
        },
      );
    }
  }
  for (final path in [
    'https://foreign.example.test/collect',
    '//foreign.example.test/collect',
    '/api/v1/../auth',
    '/api/v1/%2e%2e/auth',
    r'/api\v1\collect',
    '/api/v1/collect#fragment',
  ]) {
    for (final multipart in [false, true]) {
      test(
        '${multipart ? 'proof' : 'JSON'} rejects unsafe target $path before sending',
        () async {
          var calls = 0;
          final transport = HttpRequestTransport(
            Uri.parse('https://delivery.example.test'),
            client: MockClient((_) async {
              calls++;
              return http.Response('{}', 200);
            }),
          );
          addTearDown(transport.close);
          final result = multipart
              ? transport.sendMultipart(
                  path,
                  {'expectedVersion': '5'},
                  [
                    UploadPart('photo', 'image/png', Uint8List.fromList([1])),
                  ],
                  headers: {
                    'Authorization': 'Bearer fictional-test-credential',
                  },
                )
              : transport.send(
                  'GET',
                  path,
                  headers: {
                    'Authorization': 'Bearer fictional-test-credential',
                  },
                );
          await expectLater(result, throwsArgumentError);
          expect(calls, 0);
        },
      );
    }
  }
  for (final multipart in [false, true]) {
    test(
      '${multipart ? 'proof' : 'JSON'} retains valid same-origin paths and query',
      () async {
        final path = multipart
            ? '/api/v1/deliveries/00000000-0000-4000-8000-000000000011/pod'
            : '/api/v1/couriers/me/assignments?date=2026-10-29&includeOverdue=true';
        final transport = HttpRequestTransport(
          Uri.parse('https://delivery.example.test'),
          client: MockClient((request) async {
            expect(
              request.url.toString(),
              'https://delivery.example.test$path',
            );
            return http.Response('{}', 200);
          }),
        );
        addTearDown(transport.close);
        final reply = multipart
            ? await transport.sendMultipart(path, {}, [])
            : await transport.send('GET', path);
        expect(reply.status, 200);
      },
    );
  }
  for (final method in ['GET', 'POST']) {
    test(
      'JSON $method does not follow a real redirect to another origin',
      () async {
        final destination = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var redirectedRequests = 0;
        destination.listen((request) async {
          redirectedRequests++;
          request.response.write('Unexpected redirected request');
          await request.response.close();
        });
        origin.listen((request) async {
          request.response.statusCode = method == 'GET' ? 302 : 303;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${destination.port}/collect',
          );
          await request.response.close();
        });
        final transport = HttpRequestTransport(
          Uri.parse('http://127.0.0.1:${origin.port}'),
        );
        try {
          await expectLater(
            transport.send(
              method,
              method == 'GET'
                  ? '/api/v1/couriers/me/assignments'
                  : '/api/v1/parcels',
              headers: {
                'Authorization': 'Bearer fictional-test-credential',
                'Idempotency-Key': 'original-key',
              },
            ),
            throwsA(isA<http.ClientException>()),
          );
          expect(redirectedRequests, 0);
        } finally {
          transport.close();
          await origin.close(force: true);
          await destination.close(force: true);
        }
      },
    );
  }
}
