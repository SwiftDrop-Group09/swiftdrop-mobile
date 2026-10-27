import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/errors/identity_exception.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/features/auth/data/identity_api.dart';
import 'package:swiftdrop_mobile/features/auth/domain/identity_models.dart';

const profile = {
  'id': '11111111-1111-1111-1111-111111111111',
  'email': 'fixture@example.test',
  'fullName': 'Fixture',
  'phoneNumber': null,
  'address': null,
  'roles': ['Customer'],
  'isActive': true,
};
Map<String, dynamic> pair() => {
  'accessToken': 'signed-app-token-fixture',
  'tokenType': 'Bearer',
  'expiresInSeconds': 900,
  'refreshToken': 'A' * 43,
  'user': profile,
};

final class FixtureTransport implements RequestTransport {
  FixtureTransport(this.respond);
  final ApiReply Function(
    String method,
    String path,
    Map<String, dynamic>? body,
    Map<String, String> headers,
  )
  respond;
  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async => respond(
    method,
    path,
    body == null ? null : jsonDecode(body) as Map<String, dynamic>,
    headers,
  );
}

void main() {
  test(
    'native login sends only local credentials and accepts application tokens',
    () async {
      final api = IdentityApi(
        FixtureTransport((method, path, body, headers) {
          expect(method, 'POST');
          expect(path, '/api/v1/auth/login');
          expect(body, {
            'email': 'fixture@example.test',
            'password': 'private-password',
          });
          expect(
            headers.keys.any(
              (key) =>
                  key.toLowerCase() == 'cookie' ||
                  key.toLowerCase() == 'origin',
            ),
            false,
          );
          return ApiReply(200, jsonEncode(pair()));
        }),
      );
      final tokens = await api.login(
        'fixture@example.test',
        'private-password',
      );
      expect(tokens.user.roles, ['Customer']);
      expect(tokens.refreshToken.length, 43);
      expect(tokens.toString(), isNot(contains(tokens.refreshToken)));
      expect(tokens.toString(), isNot(contains(tokens.accessToken)));
    },
  );
  test(
    'registration has no privileged role field and returns a safe profile',
    () async {
      final api = IdentityApi(
        FixtureTransport((method, path, body, headers) {
          expect(path, '/api/v1/auth/register');
          expect(body!.keys.toSet(), {'email', 'password', 'fullName'});
          return ApiReply(201, jsonEncode(profile));
        }),
      );
      expect(
        (await api.register(
          'fixture@example.test',
          'private-password',
          'Fixture',
        )).id,
        profile['id'],
      );
    },
  );
  test(
    'Google exchanges ID token without a caller-selected identity or role',
    () async {
      final api = IdentityApi(
        FixtureTransport((method, path, body, headers) {
          expect(path, '/api/v1/auth/google');
          expect(body, {'idToken': 'signed-google-fixture'});
          return ApiReply(200, jsonEncode(pair()));
        }),
      );
      await api.google('signed-google-fixture');
    },
  );
  test(
    'native refresh/logout use the body token and logout app bearer',
    () async {
      final calls = <String>[];
      final api = IdentityApi(
        FixtureTransport((method, path, body, headers) {
          calls.add(path);
          expect(body, {'refreshToken': 'A' * 43});
          if (path.endsWith('logout')) {
            expect(headers['Authorization'], 'Bearer app-fixture');
            return const ApiReply(204, '');
          }
          expect(headers.containsKey('Authorization'), false);
          return ApiReply(200, jsonEncode(pair()));
        }),
      );
      await api.refresh('A' * 43);
      await api.logout('app-fixture', 'A' * 43);
      expect(calls, ['/api/v1/auth/refresh', '/api/v1/auth/logout']);
    },
  );
  test(
    'profile update always includes nullable phone and no authority fields',
    () async {
      final api = IdentityApi(
        FixtureTransport((method, path, body, headers) {
          expect(method, 'PUT');
          expect(path, '/api/v1/users/me');
          expect(body, {
            'fullName': 'Changed',
            'phoneNumber': null,
            'address': null,
          });
          expect(headers['Authorization'], 'Bearer app-fixture');
          return ApiReply(200, jsonEncode({...profile, 'fullName': 'Changed'}));
        }),
      );
      expect(
        (await api.updateProfile(
          'app-fixture',
          'Changed',
          null,
          null,
        )).fullName,
        'Changed',
      );
    },
  );
  test(
    'explicit linking includes fresh password and existing app bearer',
    () async {
      final api = IdentityApi(
        FixtureTransport((method, path, body, headers) {
          expect(path, '/api/v1/auth/google/link');
          expect(body, {
            'idToken': 'google-fixture',
            'currentPassword': 'private-password',
          });
          expect(headers['Authorization'], 'Bearer app-fixture');
          return ApiReply(200, jsonEncode(profile));
        }),
      );
      await api.linkGoogle('app-fixture', 'google-fixture', 'private-password');
    },
  );
  for (final status in [401, 403, 409, 429, 503]) {
    test(
      'safe HTTP $status errors never expose arbitrary server fields',
      () async {
        final api = IdentityApi(
          FixtureTransport(
            (method, path, body, headers) => ApiReply(
              status,
              '{"code":"private-password","title":"private-token","detail":"raw-database-credentials"}',
            ),
          ),
        );
        try {
          await api.login('fixture@example.test', 'private-password');
          fail('Expected safe failure.');
        } on IdentityException catch (error) {
          expect(error.status, status);
          expect(error.toString(), isNot(contains('private-')));
          expect(error.toString(), isNot(contains('database')));
        }
      },
    );
  }
  test('account collision remains a link-required outcome', () async {
    final api = IdentityApi(
      FixtureTransport(
        (method, path, body, headers) =>
            const ApiReply(409, '{"code":"account_link_required"}'),
      ),
    );
    await expectLater(
      api.google('google-fixture'),
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'account_link_required',
        ),
      ),
    );
  });
  for (final modification in <String, dynamic>{
    'tokenType': 'Google',
    'expiresInSeconds': 901,
    'refreshToken': 'short',
    'accessToken': '',
    'user': {...profile, 'isActive': false},
  }.entries) {
    test('rejects unsafe token envelope ${modification.key}', () async {
      final api = IdentityApi(
        FixtureTransport(
          (method, path, body, headers) => ApiReply(
            200,
            jsonEncode({...pair(), modification.key: modification.value}),
          ),
        ),
      );
      await expectLater(
        api.login('fixture@example.test', 'private-password'),
        throwsA(
          isA<IdentityException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });
  }
  for (final badRoles in <dynamic>[
    'Admin',
    ['Unknown'],
    ['Admin', 1],
    ['Admin', 'Admin'],
  ]) {
    test('rejects malformed or duplicate role data $badRoles', () {
      expect(
        () => IdentityProfile.fromJson({...profile, 'roles': badRoles}),
        throwsA(isA<IdentityException>()),
      );
    });
  }
  test('zero roles are valid profile data but grant no authority', () {
    final value = IdentityProfile.fromJson({...profile, 'roles': <String>[]});
    expect(value.roles, isEmpty);
    expect(() => value.roles.add('Admin'), throwsUnsupportedError);
  });
  test('rejects malformed response JSON without reflecting it', () async {
    final api = IdentityApi(
      FixtureTransport(
        (method, path, body, headers) =>
            const ApiReply(200, 'private-response-not-json'),
      ),
    );
    await expectLater(
      api.profile('app-fixture'),
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });
}
