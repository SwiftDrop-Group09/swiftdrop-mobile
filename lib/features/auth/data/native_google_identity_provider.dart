import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/errors/identity_exception.dart';
import '../domain/google_identity_provider.dart';

final class NativeGoogleIdentityProvider implements GoogleIdentityProvider {
  NativeGoogleIdentityProvider({this.serverClientId, this.iosClientId});
  final String? serverClientId;
  final String? iosClientId;
  static Future<void>? _initialization;
  static String? _configuredServer;
  static String? _configuredIos;

  Future<void> _initialize() async {
    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      throw const IdentityException('unsupported_platform');
    }
    if (serverClientId == null ||
        !serverClientId!.endsWith('.apps.googleusercontent.com') ||
        defaultTargetPlatform == TargetPlatform.iOS &&
            (iosClientId == null ||
                !iosClientId!.endsWith('.apps.googleusercontent.com'))) {
      throw const IdentityException('google_unavailable');
    }
    if (_initialization != null &&
        (_configuredServer != serverClientId ||
            _configuredIos != iosClientId)) {
      throw const IdentityException('google_unavailable');
    }
    if (_initialization == null) {
      _configuredServer = serverClientId;
      _configuredIos = iosClientId;
      // The native contract deliberately omits nonce until a trusted server
      // challenge-binding flow is agreed. Never reuse a browser nonce here.
      _initialization = GoogleSignIn.instance.initialize(
        serverClientId: serverClientId,
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? iosClientId
            : null,
      );
    }
    try {
      await _initialization;
    } on Exception {
      throw const IdentityException('google_unavailable');
    }
  }

  @override
  Future<String?> signInIdToken() async {
    await _initialize();
    try {
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const IdentityException('google_unavailable');
      }
      // Sign out first so every explicit attempt obtains a fresh provider token.
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty || token.length > 10000) {
        throw const IdentityException('google_unavailable');
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw const IdentityException('google_unavailable');
    } on IdentityException {
      rethrow;
    } on Exception {
      throw const IdentityException('google_unavailable');
    }
  }

  @override
  Future<void> signOut() async {
    if (_initialization == null) return;
    await _initialize();
    try {
      await GoogleSignIn.instance.signOut();
    } on Exception {
      throw const IdentityException('google_unavailable');
    }
  }
}
