import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/app/app.dart';
import 'package:swiftdrop_mobile/core/config/identity_config.dart';
import 'package:swiftdrop_mobile/core/errors/identity_exception.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/storage/refresh_token_store.dart';
import 'package:swiftdrop_mobile/features/auth/data/identity_api.dart';
import 'package:swiftdrop_mobile/features/auth/domain/google_identity_provider.dart';
import 'package:swiftdrop_mobile/features/auth/presentation/identity_controller.dart';

void main() {
  testWidgets('Pending profile mutation disables duplicate actions', (
    tester,
  ) async {
    final fixture = await _signedIn(tester);
    final pending = Completer<ApiReply>();
    fixture.transport.interceptor = (call) =>
        call.method == 'PUT' ? pending.future : null;
    await tester.enterText(
      find.byKey(const Key('profile-full-name')),
      'Pending Name',
    );
    await tester.ensureVisible(find.byKey(const Key('save-profile')));
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save-profile')))
          .onPressed,
      isNull,
    );
    expect(_field(tester, 'profile-full-name').enabled, isFalse);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('sign-out'))).onPressed,
      isNull,
    );
    pending.complete(
      ApiReply(
        200,
        jsonEncode({...fixture.transport.profile, 'fullName': 'Pending Name'}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your profile was saved.'), findsOneWidget);
    expect(
      fixture.transport.calls.where((call) => call.method == 'PUT'),
      hasLength(1),
    );
  });

  testWidgets('Storage restoration failure presents safe sign-in guidance', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.controller.dispose);
    fixture.tokens.pendingRead = Completer<String?>();
    await tester.pumpWidget(fixture.app());
    fixture.tokens.pendingRead!.completeError(
      const IdentityException('storage_unavailable'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Session restoration is unavailable. You can sign in again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
    expect(fixture.controller.user, isNull);
  });

  testWidgets(
    'Restoration waits without exposing a signed-out form or private data',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      fixture.tokens.pendingRead = Completer<String?>();
      await tester.pumpWidget(fixture.app());
      expect(find.text('Restoring your session…'), findsOneWidget);
      expect(find.byKey(const Key('sign-in-email')), findsNothing);
      expect(find.text('My profile'), findsNothing);
      fixture.tokens.pendingRead!.complete(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
    },
  );

  testWidgets('Local validation rejects invalid email without an API request', (
    tester,
  ) async {
    final fixture = await _signedOut(tester);
    await tester.enterText(find.byKey(const Key('sign-in-email')), 'invalid');
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'password',
    );
    await _tap(tester, find.byKey(const Key('local-sign-in-submit')));
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(fixture.transport.calls, isEmpty);
  });

  testWidgets(
    'Registration creates Customer account and returns to sign-in without auto-login',
    (tester) async {
      final fixture = await _signedOut(tester);
      await _tap(tester, find.text('Create a Customer account'));
      expect(
        find.textContaining('New accounts start as Customers.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('registration-name')),
        'Mobile Customer',
      );
      await tester.enterText(find.byKey(const Key('sign-in-email')), _email);
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        _password,
      );
      await _tap(tester, find.byKey(const Key('local-sign-in-submit')));
      expect(
        find.text('Your account was created. Sign in to continue.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('registration-name')), findsNothing);
      expect(fixture.controller.user, isNull);
      final call = fixture.transport.calls.single;
      expect(call.path, '/api/v1/auth/register');
      expect(call.json!.keys.toSet(), {'email', 'password', 'fullName'});
      expect(call.json!['fullName'], 'Mobile Customer');
      expect(_field(tester, 'sign-in-password').controller!.text, isEmpty);
    },
  );

  testWidgets(
    'Registration requires twelve characters and never submits privileged roles',
    (tester) async {
      final fixture = await _signedOut(tester);
      await _tap(tester, find.text('Create a Customer account'));
      await tester.enterText(
        find.byKey(const Key('registration-name')),
        'Mobile Customer',
      );
      await tester.enterText(find.byKey(const Key('sign-in-email')), _email);
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        'short',
      );
      await _tap(tester, find.byKey(const Key('local-sign-in-submit')));
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      expect(fixture.transport.calls, isEmpty);
      expect(find.byType(DropdownButton<String>), findsNothing);
    },
  );

  testWidgets('Login clears password while pending then displays own profile', (
    tester,
  ) async {
    final fixture = await _signedOut(tester);
    final pending = Completer<ApiReply>();
    fixture.transport.interceptor = (call) =>
        call.path == '/api/v1/auth/login' ? pending.future : null;
    await tester.enterText(find.byKey(const Key('sign-in-email')), _email);
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      _password,
    );
    await tester.ensureVisible(find.byKey(const Key('local-sign-in-submit')));
    await tester.tap(find.byKey(const Key('local-sign-in-submit')));
    await tester.pump();
    expect(_field(tester, 'sign-in-password').controller!.text, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('local-sign-in-submit')))
          .onPressed,
      isNull,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(fixture.transport.tokens());
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text(_email), findsOneWidget);
    expect(find.byKey(const Key('sign-in-email')), findsNothing);
    expect(fixture.tokens.value, isNotNull);
  });

  testWidgets(
    'Invalid credentials use fixed safe error and keep password cleared',
    (tester) async {
      final fixture = await _signedOut(tester);
      fixture.transport.interceptor = (call) =>
          call.path == '/api/v1/auth/login'
          ? Future.value(
              const ApiReply(
                401,
                '{"code":"invalid_credentials","detail":"private-token-secret"}',
              ),
            )
          : null;
      await tester.enterText(find.byKey(const Key('sign-in-email')), _email);
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        _password,
      );
      await _tap(tester, find.byKey(const Key('local-sign-in-submit')));
      expect(
        find.text(const IdentityException('invalid_credentials').message),
        findsOneWidget,
      );
      expect(find.textContaining('private-token-secret'), findsNothing);
      expect(_field(tester, 'sign-in-password').controller!.text, isEmpty);
      expect(fixture.controller.user, isNull);
    },
  );

  testWidgets('Google cancellation makes no Identity API call', (tester) async {
    final fixture = await _signedOut(tester);
    fixture.google.token = null;
    await _tap(tester, find.byKey(const Key('google-sign-in')));
    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
    expect(fixture.google.attempts, 1);
    expect(fixture.transport.calls, isEmpty);
    expect(fixture.tokens.value, isNull);
  });

  testWidgets(
    'Google email collision explains explicit linking without exposing token',
    (tester) async {
      final fixture = await _signedOut(tester);
      fixture.transport.interceptor = (call) =>
          call.path == '/api/v1/auth/google'
          ? Future.value(
              const ApiReply(409, '{"code":"account_link_required"}'),
            )
          : null;
      await _tap(tester, find.byKey(const Key('google-sign-in')));
      expect(
        find.text(const IdentityException('account_link_required').message),
        findsOneWidget,
      );
      expect(find.textContaining('fictional-google-id-token'), findsNothing);
      expect(fixture.transport.calls.single.json, {
        'idToken': 'fictional-google-id-token',
      });
    },
  );

  testWidgets('Profile form sends only documented editable fields', (
    tester,
  ) async {
    final fixture = await _signedIn(tester);
    await tester.enterText(
      find.byKey(const Key('profile-full-name')),
      ' Updated Mobile ',
    );
    await tester.enterText(
      find.byKey(const Key('profile-phone')),
      '0771234567',
    );
    await tester.enterText(
      find.byKey(const Key('profile-address')),
      'New address',
    );
    await _tap(tester, find.byKey(const Key('save-profile')));
    final update = fixture.transport.calls.lastWhere(
      (call) => call.method == 'PUT',
    );
    expect(update.path, '/api/v1/users/me');
    expect(update.json, {
      'fullName': 'Updated Mobile',
      'phoneNumber': '0771234567',
      'address': 'New address',
    });
    expect(find.text('Your profile was saved.'), findsOneWidget);
    expect(fixture.controller.user!.fullName, 'Updated Mobile');
    expect(find.byKey(const Key('profile-email')), findsOneWidget);
  });

  testWidgets('Courier mode cannot grant Courier access to a Customer', (
    tester,
  ) async {
    final fixture = await _signedIn(tester, mode: IdentityAppMode.courier);
    expect(find.text('SwiftDrop Courier'), findsOneWidget);
    expect(find.text('Courier access unavailable'), findsOneWidget);
    expect(
      find.textContaining('does not have an authorized Courier role'),
      findsOneWidget,
    );
    expect(fixture.controller.user!.roles, ['Customer']);
    expect(find.text('Courier role verified'), findsNothing);
  });

  testWidgets(
    'Authorized Courier and zero-role users share safe own-profile flow',
    (tester) async {
      final fixture = await _signedIn(
        tester,
        mode: IdentityAppMode.courier,
        roles: ['Courier'],
      );
      expect(find.text('Courier role verified'), findsOneWidget);
      expect(find.byKey(const Key('profile-full-name')), findsOneWidget);
      fixture.transport.profile['roles'] = <String>[];
      await _tap(tester, find.byKey(const Key('reload-profile')));
      expect(find.text('Courier access unavailable'), findsOneWidget);
      expect(find.text('No application roles assigned'), findsOneWidget);
      expect(find.text('My profile'), findsOneWidget);
    },
  );

  testWidgets(
    'Explicit Google link sends freshly supplied password and clears it',
    (tester) async {
      final fixture = await _signedIn(tester);
      await tester.ensureVisible(
        find.byKey(const Key('link-current-password')),
      );
      await tester.enterText(
        find.byKey(const Key('link-current-password')),
        _password,
      );
      await _tap(tester, find.byKey(const Key('link-google')));
      expect(find.text('Google was linked to your account.'), findsOneWidget);
      final call = fixture.transport.calls.lastWhere(
        (call) => call.path.endsWith('/google/link'),
      );
      expect(call.json, {
        'idToken': 'fictional-google-id-token',
        'currentPassword': _password,
      });
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('link-current-password')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Missing Google configuration disables linking without native channel access',
    (tester) async {
      final fixture = await _signedIn(tester, googleEnabled: false);
      await tester.ensureVisible(find.byKey(const Key('link-google')));
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('link-google')))
            .onPressed,
        isNull,
      );
      expect(
        find.text('Google linking is unavailable for this deployment.'),
        findsOneWidget,
      );
      expect(fixture.google.attempts, 0);
    },
  );

  testWidgets('Logout clears private profile and returns to local sign-in', (
    tester,
  ) async {
    final fixture = await _signedIn(tester);
    await _tap(tester, find.byKey(const Key('sign-out')));
    expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
    expect(find.text('My profile'), findsNothing);
    expect(find.text(_email), findsNothing);
    expect(fixture.tokens.value, isNull);
    expect(fixture.controller.user, isNull);
    expect(
      fixture.transport.calls.any((call) => call.path.endsWith('/logout')),
      isTrue,
    );
  });

  testWidgets(
    'Unconfirmed logout still clears private state and reports safe outcome',
    (tester) async {
      final fixture = await _signedIn(tester);
      fixture.transport.interceptor = (call) => call.path.endsWith('/logout')
          ? Future.value(const ApiReply(503, '{"detail":"private-credential"}'))
          : null;
      await _tap(tester, find.byKey(const Key('sign-out')));
      expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
      expect(
        find.text(const IdentityException('logout_unconfirmed').message),
        findsOneWidget,
      );
      expect(find.textContaining('private-credential'), findsNothing);
      expect(fixture.tokens.value, isNull);
      expect(fixture.controller.user, isNull);
    },
  );
}

const _email = 'mobile-fixture@example.test';
const _password = 'Test-only private password 7!';
final _refresh = List.filled(43, 'A').join();

Future<_Fixture> _signedOut(WidgetTester tester) async {
  final fixture = _Fixture();
  addTearDown(fixture.controller.dispose);
  await tester.pumpWidget(fixture.app());
  await tester.pumpAndSettle();
  return fixture;
}

Future<_Fixture> _signedIn(
  WidgetTester tester, {
  IdentityAppMode mode = IdentityAppMode.customer,
  List<String> roles = const ['Customer'],
  bool googleEnabled = true,
}) async {
  final fixture = _Fixture();
  addTearDown(fixture.controller.dispose);
  fixture.transport.profile['roles'] = roles;
  fixture.tokens.value = _refresh;
  await tester.pumpWidget(
    fixture.app(mode: mode, googleEnabled: googleEnabled),
  );
  await tester.pumpAndSettle();
  expect(fixture.controller.user, isNotNull);
  return fixture;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

TextFormField _field(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key)));

class _Fixture {
  final transport = _Transport();
  final tokens = _Tokens();
  final google = _Google();
  late final controller = IdentityController(
    api: IdentityApi(transport),
    tokens: tokens,
    google: google,
  );

  Widget app({
    IdentityAppMode mode = IdentityAppMode.customer,
    bool googleEnabled = true,
  }) => SwiftDropApp(
    controller: controller,
    mode: mode,
    googleEnabled: googleEnabled,
  );
}

class _Tokens implements RefreshTokenStore {
  String? value;
  Completer<String?>? pendingRead;
  @override
  Future<String?> read() async => pendingRead?.future ?? value;
  @override
  Future<void> write(String refreshToken) async {
    value = refreshToken;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _Google implements GoogleIdentityProvider {
  String? token = 'fictional-google-id-token';
  int attempts = 0;
  @override
  Future<String?> signInIdToken() async {
    attempts++;
    return token;
  }

  @override
  Future<void> signOut() async {}
}

class _Call {
  _Call(this.method, this.path, String? body, this.headers)
    : json = body == null ? null : jsonDecode(body) as Map<String, dynamic>;
  final String method;
  final String path;
  final Map<String, dynamic>? json;
  final Map<String, String> headers;
}

class _Transport implements RequestTransport {
  final calls = <_Call>[];
  Future<ApiReply>? Function(_Call call)? interceptor;
  final profile = <String, dynamic>{
    'id': 'aaaaaaaa-1111-2222-3333-123456789abc',
    'email': _email,
    'fullName': 'Mobile Fixture',
    'phoneNumber': null,
    'address': null,
    'roles': ['Customer'],
    'isActive': true,
  };

  ApiReply tokens() => ApiReply(
    200,
    jsonEncode({
      'accessToken': 'fictional-application-access',
      'refreshToken': _refresh,
      'tokenType': 'Bearer',
      'expiresInSeconds': 900,
      'user': profile,
    }),
  );

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final call = _Call(method, path, body, headers);
    calls.add(call);
    final intercepted = interceptor?.call(call);
    if (intercepted != null) return intercepted;
    if (path == '/api/v1/auth/logout') return const ApiReply(204, '');
    if (path == '/api/v1/auth/register') {
      return ApiReply(201, jsonEncode(profile));
    }
    if (path == '/api/v1/auth/google/link') {
      return ApiReply(200, jsonEncode(profile));
    }
    if (path.startsWith('/api/v1/auth/')) return tokens();
    if (path == '/api/v1/users/me') {
      if (method == 'PUT') profile.addAll(call.json!);
      return ApiReply(200, jsonEncode(profile));
    }
    throw StateError('Unexpected isolated API request.');
  }
}
