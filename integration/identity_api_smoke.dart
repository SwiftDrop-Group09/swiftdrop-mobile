// Opt-in only: the backend HTTPS harness supplies its owned origin and public
// certificate. No deployed credentials or native platform storage are used.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:swiftdrop_mobile/core/errors/identity_exception.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/storage/refresh_token_store.dart';
import 'package:swiftdrop_mobile/features/auth/data/identity_api.dart';
import 'package:swiftdrop_mobile/features/auth/domain/google_identity_provider.dart';
import 'package:swiftdrop_mobile/features/auth/presentation/identity_controller.dart';

void main() {
  test('Native Identity client uses trusted HTTPS and real session transactions', () async {
    const originValue = String.fromEnvironment('IDENTITY_TEST_ORIGIN');
    const certificate = String.fromEnvironment('IDENTITY_TEST_CERT');
    if (originValue.isEmpty || certificate.isEmpty) {
      fail(
        'Run this opt-in test through IdentityBrowserHarness with --mobile-project.',
      );
    }
    final origin = Uri.parse(originValue);
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(certificate);
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = IOClient(HttpClient(context: context));
      final transport = HttpRequestTransport(origin, client: client);
      final api = IdentityApi(transport);
      final storage = _FixtureStore();
      var now = DateTime.now();
      final controller = IdentityController(
        api: api,
        tokens: storage,
        google: _NoProvider(),
        now: () => now,
      );
      try {
        final random = Random.secure();
        String secret(int length) =>
            base64UrlEncode(List.generate(length, (_) => random.nextInt(256)));
        final email = 'native-${secret(12)}@example.test';
        final password = secret(32);
        await controller.register(email, password, 'Native fixture');
        expect(controller.user == null, isTrue);
        await controller.login(email, password);
        final id = controller.user!.id;
        expect(controller.customerSession.canBook, isTrue);
        expect(controller.user!.roles.contains('Courier'), isFalse);
        final initialRefresh = storage.value!;
        await controller.updateProfile(
          fullName: 'Native updated',
          phoneNumber: null,
          address: 'Fixture address',
        );
        await controller.refreshProfile();
        expect(controller.user!.id == id, isTrue);
        expect(controller.user!.fullName, 'Native updated');
        now = now.add(const Duration(minutes: 15));
        await controller.accessToken();
        final rotatedRefresh = storage.value!;
        expect(rotatedRefresh != initialRefresh, isTrue);
        await controller.logout();
        expect(storage.value == null && controller.user == null, isTrue);
        await expectLater(
          api.refresh(rotatedRefresh),
          throwsA(
            isA<IdentityException>().having(
              (error) => error.status,
              'HTTP status',
              401,
            ),
          ),
        );

        // A new family is independent of the explicitly revoked logout family.
        await controller.login(email, password);
        final consumedRefresh = storage.value!;
        now = now.add(const Duration(minutes: 15));
        await controller.accessToken();
        expect(storage.value != consumedRefresh, isTrue);
        await expectLater(
          api.refresh(consumedRefresh),
          throwsA(
            isA<IdentityException>().having(
              (error) => error.status,
              'HTTP status',
              401,
            ),
          ),
        );
        now = now.add(const Duration(minutes: 15));
        await expectLater(
          controller.accessToken(),
          throwsA(
            isA<IdentityException>().having(
              (error) => error.status,
              'HTTP status',
              401,
            ),
          ),
        );
        expect(storage.value == null && controller.user == null, isTrue);
      } finally {
        controller.dispose();
        transport.close();
      }
    }, _RealNetwork());
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// Flutter widget-test bindings intentionally reject network requests by default.
// This standalone opt-in test restores the real client with a narrow trust root;
// it never uses badCertificateCallback or changes production transport behavior.
class _RealNetwork extends HttpOverrides {}

class _FixtureStore implements RefreshTokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _NoProvider implements GoogleIdentityProvider {
  @override
  Future<String?> signInIdToken() =>
      throw StateError('Provider is outside this smoke test.');
  @override
  Future<void> signOut() async {}
}
