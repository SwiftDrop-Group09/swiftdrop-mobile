import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/errors/identity_exception.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/storage/refresh_token_store.dart';
import 'package:swiftdrop_mobile/features/auth/data/identity_api.dart';
import 'package:swiftdrop_mobile/features/auth/domain/google_identity_provider.dart';
import 'package:swiftdrop_mobile/features/auth/presentation/identity_controller.dart';

const principal = '11111111-1111-1111-1111-111111111111';
const otherPrincipal = '22222222-2222-2222-2222-222222222222';
final refreshA = List.filled(43, 'a').join();
final refreshB = List.filled(43, 'b').join();

Map<String, Object?> profile({
  String id = principal,
  List<String> roles = const ['Customer'],
  String name = 'Customer',
}) => {
  'id': id,
  'email': 'fictional@example.test',
  'fullName': name,
  'phoneNumber': null,
  'address': null,
  'roles': roles,
  'isActive': true,
};
ApiReply pair({
  String refresh = '',
  String id = principal,
  List<String> roles = const ['Customer'],
}) => ApiReply(
  200,
  jsonEncode({
    'accessToken': 'test-access-$id',
    'tokenType': 'Bearer',
    'expiresInSeconds': 900,
    'refreshToken': refresh.isEmpty ? refreshA : refresh,
    'user': profile(id: id, roles: roles),
  }),
);

void main() {
  late TestTransport transport;
  late TestStore store;
  late TestGoogle google;
  late IdentityController controller;
  late DateTime now;
  late int clearCalls;
  setUp(() {
    transport = TestTransport();
    store = TestStore();
    google = TestGoogle();
    now = DateTime.utc(2026, 10, 27);
    clearCalls = 0;
    controller = IdentityController(
      api: IdentityApi(transport),
      tokens: store,
      google: google,
      now: () => now,
      clearPrivateData: () => clearCalls++,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'empty secure storage restores signed out without contacting API or Google',
    () async {
      await controller.restore();
      expect(controller.restoring, isFalse);
      expect(controller.user, isNull);
      expect(controller.message, isNull);
      expect(transport.calls, isEmpty);
      expect(google.signIns, 0);
    },
  );

  test(
    'restore rotates stored token then reads current server profile',
    () async {
      store.value = refreshA;
      transport.handler = (request) async => request.path.endsWith('/refresh')
          ? pair(refresh: refreshB)
          : ApiReply(200, jsonEncode(profile(name: 'Fresh server name')));
      await controller.restore();
      expect(store.value, refreshB);
      expect(controller.user!.fullName, 'Fresh server name');
      expect(transport.calls.map((call) => call.path), [
        '/api/v1/auth/refresh',
        '/api/v1/users/me',
      ]);
      expect(controller.customerSession.principalId, principal);
      expect(controller.customerSession.canBook, isTrue);
    },
  );

  test(
    'restore is single-flight and rejected refresh clears secure storage',
    () async {
      store.value = refreshA;
      transport.handler = (_) async =>
          const ApiReply(401, '{"code":"invalid_credentials"}');
      await Future.wait([controller.restore(), controller.restore()]);
      expect(transport.calls, hasLength(1));
      expect(store.value, isNull);
      expect(controller.user, isNull);
      expect(controller.message, isNull);
    },
  );

  test('login publishes identity only after successful secure write', () async {
    final pending = Completer<void>();
    store.beforeWrite = (_) => pending.future;
    final login = controller.login(
      'fictional@example.test',
      'Fictional password 42!',
    );
    await pumpEventQueue();
    expect(controller.busy, isTrue);
    expect(controller.user, isNull);
    pending.complete();
    await login;
    expect(controller.user!.id, principal);
    expect(store.value, refreshA);
    expect(await controller.accessToken(), 'test-access-$principal');
    expect(controller.busy, isFalse);
  });

  test(
    'failed secure write revokes new family and leaves no authenticated state',
    () async {
      store.failWrite = true;
      await expectLater(
        controller.login('fictional@example.test', 'Fictional password 42!'),
        throwsA(
          isA<IdentityException>().having(
            (error) => error.code,
            'code',
            'storage_unavailable',
          ),
        ),
      );
      expect(controller.user, isNull);
      expect(store.value, isNull);
      expect(transport.calls.map((call) => call.path), [
        '/api/v1/auth/login',
        '/api/v1/auth/logout',
      ]);
      expect(transport.calls.last.json['refreshToken'], refreshA);
    },
  );

  test('storage read failure fails closed with safe restore state', () async {
    store.value = refreshA;
    store.failRead = true;
    await controller.restore();
    expect(controller.user, isNull);
    expect(transport.calls, isEmpty);
    expect(controller.message, contains('restoration is unavailable'));
  });

  test('cannot start application login when prior secure credentials cannot be deleted', () async {
    store.failDelete = true;
    await expectLater(
      controller.login('fictional@example.test', 'Fictional password 42!'),
      throwsA(isA<IdentityException>()),
    );
    expect(controller.user, isNull);
    expect(transport.calls, isEmpty);
  });

  test(
    'registration does not manufacture session or persist a password',
    () async {
      transport.handler = (_) async => ApiReply(201, jsonEncode(profile()));
      await controller.register(
        'fictional@example.test',
        'Fictional password 42!',
        'Customer',
      );
      expect(controller.user, isNull);
      expect(store.value, isNull);
      expect(transport.calls.single.json.keys.toSet(), {
        'email',
        'password',
        'fullName',
      });
    },
  );

  test(
    'Google cancellation creates no application request or stored session',
    () async {
      google.token = null;
      expect(await controller.googleLogin(), isFalse);
      expect(transport.calls, isEmpty);
      expect(store.value, isNull);
      expect(controller.user, isNull);
    },
  );

  test('Google account collision propagates safe link-required outcome without session', () async {
    google.token = 'fictional-provider-token';
    transport.handler = (_) async =>
        const ApiReply(409, '{"code":"account_link_required"}');
    await expectLater(
      controller.googleLogin(),
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'account_link_required',
        ),
      ),
    );
    expect(store.value, isNull);
    expect(controller.user, isNull);
  });

  test('concurrent expiry refresh calls share one rotation and persist replacement', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    now = now.add(const Duration(minutes: 15));
    final pending = Completer<ApiReply>();
    transport.handler = (_) => pending.future;
    final first = controller.accessToken();
    final second = controller.accessToken();
    await pumpEventQueue();
    expect(
      transport.calls.where((call) => call.path.endsWith('/refresh')),
      hasLength(1),
    );
    pending.complete(pair(refresh: refreshB));
    expect(
      await Future.wait([first, second]),
      everyElement('test-access-$principal'),
    );
    expect(store.value, refreshB);
  });

  test('logout clears memory immediately and stored token even on ambiguous network error', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    transport.handler = (_) async =>
        throw const IdentityException('network_error');
    final logout = controller.logout();
    expect(controller.user, isNull);
    await expectLater(
      logout,
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'logout_unconfirmed',
        ),
      ),
    );
    expect(store.value, isNull);
    expect(google.signOuts, 1);
    expect(clearCalls, greaterThan(0));
  });

  test('expired-token logout refreshes once then revokes replacement without persisting it', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    now = now.add(const Duration(minutes: 20));
    transport.handler = (request) async => request.path.endsWith('/refresh')
        ? pair(refresh: refreshB)
        : const ApiReply(204, '');
    await controller.logout();
    expect(store.value, isNull);
    expect(transport.calls.last.json['refreshToken'], refreshB);
    expect(store.writes, [refreshA]);
  });

  test(
    'profile update submits editable fields and preserves verified subject',
    () async {
      await controller.login(
        'fictional@example.test',
        'Fictional password 42!',
      );
      transport.handler = (_) async =>
          ApiReply(200, jsonEncode(profile(name: 'Updated')));
      await controller.updateProfile(
        fullName: 'Updated',
        phoneNumber: null,
        address: 'Address',
      );
      expect(transport.calls.last.json.keys.toSet(), {
        'fullName',
        'phoneNumber',
        'address',
      });
      expect(
        transport.calls.last.headers['Authorization'],
        'Bearer test-access-$principal',
      );
      expect(controller.user!.fullName, 'Updated');
    },
  );

  test('late profile result cannot cross logout boundary', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    final pending = Completer<ApiReply>();
    transport.handler = (request) => request.path.endsWith('/users/me')
        ? pending.future
        : Future.value(const ApiReply(204, ''));
    final request = controller.refreshProfile();
    final denial = expectLater(
      request,
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'session_changed',
        ),
      ),
    );
    await pumpEventQueue();
    await controller.logout();
    pending.complete(ApiReply(200, jsonEncode(profile())));
    await denial;
    expect(controller.user, isNull);
  });

  test(
    'superseded login is never published and its new family is revoked',
    () async {
      final pending = Completer<ApiReply>();
      transport.handler = (request) => request.path.endsWith('/login')
          ? pending.future
          : Future.value(const ApiReply(204, ''));
      final first = controller.login(
        'fictional@example.test',
        'Fictional password 42!',
      );
      final denial = expectLater(first, throwsA(isA<IdentityException>()));
      await pumpEventQueue();
      final logout = controller.logout();
      pending.complete(pair());
      await denial;
      await logout;
      expect(controller.user, isNull);
      expect(store.value, isNull);
      expect(
        transport.calls.any((call) => call.path.endsWith('/logout')),
        isTrue,
      );
    },
  );

  test('wrong fresh linking password retains local session', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    google.token = 'fictional-provider-token';
    transport.handler = (_) async =>
        const ApiReply(401, '{"code":"invalid_credentials"}');
    await expectLater(
      controller.linkGoogle('Wrong password'),
      throwsA(isA<IdentityException>()),
    );
    expect(controller.user!.id, principal);
    expect(store.value, refreshA);
  });

  test(
    'Google linking cancellation does not call API or alter local session',
    () async {
      await controller.login(
        'fictional@example.test',
        'Fictional password 42!',
      );
      google.token = null;
      expect(await controller.linkGoogle('Fictional password 42!'), isFalse);
      expect(transport.calls, hasLength(1));
      expect(controller.user!.id, principal);
    },
  );

  test('disabled profile boundary clears credentials', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    transport.handler = (_) async =>
        const ApiReply(403, '{"code":"forbidden"}');
    await expectLater(
      controller.refreshProfile(),
      throwsA(isA<IdentityException>()),
    );
    expect(controller.user, isNull);
    expect(store.value, isNull);
  });

  test(
    'a Customer-only Google result cannot manufacture Courier authorization',
    () async {
      google.token = 'fictional-provider-token';
      await controller.googleLogin();
      expect(controller.user!.roles, ['Customer']);
      expect(controller.user!.roles.contains('Courier'), isFalse);
    },
  );

  test('authenticated GET retries once after refresh; mutations are never replayed', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    var reads = 0;
    transport.handler = (request) async {
      if (request.path.endsWith('/refresh')) return pair(refresh: refreshB);
      if (request.method == 'GET') {
        return ++reads == 1
            ? const ApiReply(401, '')
            : const ApiReply(200, '{}');
      }
      return const ApiReply(401, '');
    };
    expect(
      (await controller.authorizedRequest('GET', '/api/v1/parcels')).status,
      200,
    );
    expect(reads, 2);
    await expectLater(
      controller.authorizedRequest(
        'POST',
        '/api/v1/parcels',
        body: '{}',
        headers: {'Idempotency-Key': 'test-key'},
      ),
      throwsA(isA<IdentityException>()),
    );
    expect(
      transport.calls.where(
        (call) => call.method == 'POST' && call.path.endsWith('/parcels'),
      ),
      hasLength(1),
    );
    expect(transport.calls.last.headers['Idempotency-Key'], 'test-key');
    expect(controller.user, isNull);
  });

  test('failed secure deletion never claims complete logout or reuses retained token', () async {
    await controller.login('fictional@example.test', 'Fictional password 42!');
    store.failDelete = true;
    transport.handler = (_) async => const ApiReply(204, '');
    await expectLater(
      controller.logout(),
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'logout_unconfirmed',
        ),
      ),
    );
    expect(controller.user, isNull);
    expect(store.value, refreshA);
    expect(
      const IdentityException('logout_unconfirmed').message,
      isNot(contains('Signed out on this device')),
    );
    await expectLater(
      controller.accessToken(),
      throwsA(isA<IdentityException>()),
    );
    expect(
      transport.calls.where((call) => call.path.endsWith('/refresh')),
      isEmpty,
    );
  });

  test(
    'logout during first login reports failed abandoned-family revocation',
    () async {
      final pending = Completer<ApiReply>();
      transport.handler = (request) => request.path.endsWith('/login')
          ? pending.future
          : Future.error(const IdentityException('network_error'));
      final login = controller.login(
        'fictional@example.test',
        'Fictional password 42!',
      );
      final loginFailure = expectLater(
        login,
        throwsA(isA<IdentityException>()),
      );
      await pumpEventQueue();
      final logout = controller.logout();
      final logoutFailure = expectLater(
        logout,
        throwsA(
          isA<IdentityException>().having(
            (error) => error.code,
            'code',
            'logout_unconfirmed',
          ),
        ),
      );
      pending.complete(pair());
      await loginFailure;
      await logoutFailure;
      expect(controller.user, isNull);
      expect(store.value, isNull);
    },
  );

  for (final header in [
    'Authorization',
    'Cookie',
    'Origin',
    'X-API-Key',
    'X-User-Roles',
  ]) {
    test(
      'authenticated transport refuses caller credential/identity header $header',
      () async {
        await expectLater(
          controller.authorizedRequest(
            'GET',
            '/api/v1/parcels',
            headers: {header: 'forged'},
          ),
          throwsA(isA<IdentityException>()),
        );
        expect(transport.calls, isEmpty);
      },
    );
  }
}

class Call {
  Call(this.method, this.path, this.body, this.headers);
  final String method;
  final String path;
  final String? body;
  final Map<String, String> headers;
  Map<String, dynamic> get json => jsonDecode(body!) as Map<String, dynamic>;
}

class TestTransport implements RequestTransport {
  final calls = <Call>[];
  Future<ApiReply> Function(Call) handler = (_) async => pair();
  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) {
    final call = Call(method, path, body, headers);
    calls.add(call);
    return handler(call);
  }
}

class TestStore implements RefreshTokenStore {
  String? value;
  bool failRead = false, failWrite = false, failDelete = false;
  Future<void> Function(String)? beforeWrite;
  final writes = <String>[];
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Fictional private storage detail');
    return value;
  }

  @override
  Future<void> write(String token) async {
    await beforeWrite?.call(token);
    if (failWrite) throw StateError('Fictional private storage detail');
    value = token;
    writes.add(token);
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('Fictional private storage detail');
    value = null;
  }
}

class TestGoogle implements GoogleIdentityProvider {
  String? token;
  int signIns = 0, signOuts = 0;
  @override
  Future<String?> signInIdToken() async {
    signIns++;
    return token;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }
}
