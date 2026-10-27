import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/identity_models.dart';
import '../errors/identity_exception.dart';

abstract interface class RefreshTokenStore {
  Future<String?> read();
  Future<void> write(String refreshToken);
  Future<void> delete();
}

/// No web/desktop/plain-preferences fallback is allowed for native credentials.
final class NativeRefreshTokenStore implements RefreshTokenStore {
  NativeRefreshTokenStore() {
    _requireNative();
  }
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'swiftdrop_identity'),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _key = 'swiftdrop_identity_refresh_token';

  @override
  Future<String?> read() async {
    _requireNative();
    try {
      final token = await _storage.read(key: _key);
      if (token != null && !isRefreshToken(token)) {
        await _storage.delete(key: _key);
        throw const IdentityException('invalid_credentials');
      }
      return token;
    } on IdentityException {
      rethrow;
    } on Exception {
      throw const IdentityException('storage_unavailable');
    }
  }

  @override
  Future<void> write(String refreshToken) async {
    _requireNative();
    if (!isRefreshToken(refreshToken)) {
      throw const IdentityException('invalid_response');
    }
    try {
      await _storage.write(key: _key, value: refreshToken);
    } on Exception {
      throw const IdentityException('storage_unavailable');
    }
  }

  @override
  Future<void> delete() async {
    _requireNative();
    try {
      await _storage.delete(key: _key);
    } on Exception {
      throw const IdentityException('storage_unavailable');
    }
  }

  static void _requireNative() {
    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      throw const IdentityException('unsupported_platform');
    }
  }
}
