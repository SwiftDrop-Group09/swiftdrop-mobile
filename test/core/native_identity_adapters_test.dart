import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/errors/identity_exception.dart';
import 'package:swiftdrop_mobile/core/storage/refresh_token_store.dart';
import 'package:swiftdrop_mobile/features/auth/data/native_google_identity_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'native adapter writes, replaces and deletes only the refresh secret',
    () async {
      const otherKey = 'unrelated_feature_key';
      const direct = FlutterSecureStorage();
      await direct.write(key: otherKey, value: 'keep-me');
      final store = NativeRefreshTokenStore();
      expect(await store.read(), null);
      await store.write('A' * 43);
      expect(await store.read(), 'A' * 43);
      await store.write('B' * 43);
      expect(await store.read(), 'B' * 43);
      await store.delete();
      expect(await store.read(), null);
      expect(await direct.read(key: otherKey), 'keep-me');
    },
  );
  test('malformed stored credentials are removed rather than used', () async {
    const direct = FlutterSecureStorage();
    await direct.write(
      key: 'swiftdrop_identity_refresh_token',
      value: 'not-a-refresh-token',
    );
    final store = NativeRefreshTokenStore();
    await expectLater(
      store.read(),
      throwsA(
        isA<IdentityException>().having(
          (error) => error.code,
          'code',
          'invalid_credentials',
        ),
      ),
    );
    expect(await direct.read(key: 'swiftdrop_identity_refresh_token'), null);
  });
  test('rejects invalid refresh writes before storage', () async {
    final store = NativeRefreshTokenStore();
    await expectLater(store.write('short'), throwsA(isA<IdentityException>()));
    expect(await store.read(), null);
  });
  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    test(
      'unsupported $platform never falls back to plain credential storage',
      () {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          () => NativeRefreshTokenStore(),
          throwsA(
            isA<IdentityException>().having(
              (error) => error.code,
              'code',
              'unsupported_platform',
            ),
          ),
        );
      },
    );
  }
  test(
    'Google without a configured audience fails before provider interaction',
    () async {
      await expectLater(
        NativeGoogleIdentityProvider().signInIdToken(),
        throwsA(
          isA<IdentityException>().having(
            (error) => error.code,
            'code',
            'google_unavailable',
          ),
        ),
      );
    },
  );
  test(
    'Google desktop invocation is rejected before SDK initialization',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await expectLater(
        NativeGoogleIdentityProvider(
          serverClientId: 'fixture.apps.googleusercontent.com',
        ).signInIdToken(),
        throwsA(
          isA<IdentityException>().having(
            (error) => error.code,
            'code',
            'unsupported_platform',
          ),
        ),
      );
    },
  );
}
