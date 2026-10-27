import 'package:flutter/foundation.dart';

import '../../../core/errors/identity_exception.dart';
import '../../../core/network/request_transport.dart';
import '../../../core/session/customer_session.dart';
import '../../../core/storage/refresh_token_store.dart';
import '../data/identity_api.dart';
import '../domain/google_identity_provider.dart';
import '../domain/identity_models.dart';

/// One native session owner. Passwords and provider credentials never enter
/// published session state or preferences.
class IdentityController extends ChangeNotifier {
  IdentityController({
    required this._api,
    required this._tokens,
    required this._google,
    DateTime Function()? now,
    VoidCallback? clearPrivateData,
  }) : _now = now ?? DateTime.now,
       _clearPrivateData = clearPrivateData ?? _noop;

  final IdentityApi _api;
  final RefreshTokenStore _tokens;
  final GoogleIdentityProvider _google;
  final DateTime Function() _now;
  final VoidCallback _clearPrivateData;
  IdentityProfile? _user;
  String? _access;
  DateTime? _expires;
  String? _message;
  bool _restoring = true;
  bool _disposed = false;
  bool _storageBlocked = false;
  bool _abandonedRevocationUnconfirmed = false;
  int _generation = 0;
  int _pending = 0;
  Future<void> _tail = Future.value();
  Future<void>? _restoreFlight;
  Future<String>? _refreshFlight;

  IdentityProfile? get user => _user;
  bool get restoring => _restoring;
  bool get busy => _pending > 0;
  String? get message => _message;
  CustomerSession get customerSession => _user == null
      ? const CustomerSession.signedOut()
      : CustomerSession(principalId: _user!.id, roles: _user!.roles);

  static void _noop() {}
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw IdentityException('session_changed');
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _credentialAction<T>(Future<T> Function() operation) {
    _pending++;
    _publish();
    return _serial(operation).whenComplete(() {
      _pending--;
      _publish();
    });
  }

  void _clearMemory() {
    _user = null;
    _access = null;
    _expires = null;
    _clearPrivateData();
    _publish();
  }

  Future<void> _deleteStored() async {
    try {
      await _tokens.delete();
      _storageBlocked = false;
    } catch (_) {
      _storageBlocked = true;
      throw IdentityException('storage_unavailable');
    }
  }

  Future<String?> _readStored() async {
    if (_storageBlocked) throw IdentityException('storage_unavailable');
    try {
      return await _tokens.read();
    } catch (_) {
      _storageBlocked = true;
      throw IdentityException('storage_unavailable');
    }
  }

  Future<void> _revokeQuietly(IdentityTokenPair pair) async {
    try {
      await _api.logout(pair.accessToken, pair.refreshToken);
    } catch (_) {
      // An abandoned result is never published or retried as a login.
      _abandonedRevocationUnconfirmed = true;
    }
  }

  Future<String> _accept(IdentityTokenPair pair, int generation) async {
    try {
      _check(generation);
      await _tokens.write(pair.refreshToken);
      _check(generation);
    } catch (error) {
      await _revokeQuietly(pair);
      try {
        await _deleteStored();
      } catch (_) {
        // The caller still receives a safe failure and no authenticated state.
      }
      if (error is IdentityException && error.code == 'session_changed') {
        rethrow;
      }
      throw IdentityException('storage_unavailable');
    }
    _access = pair.accessToken;
    // Refresh early; the response's nominal lifetime includes network transit.
    _expires = _now().add(Duration(seconds: pair.expiresInSeconds - 30));
    _setUser(pair.user);
    _message = null;
    _restoring = false;
    _publish();
    return pair.accessToken;
  }

  void _setUser(IdentityProfile profile) {
    if (_user?.id != profile.id || !listEquals(_user?.roles, profile.roles)) {
      _clearPrivateData();
    }
    _user = profile;
  }

  Future<void> restore() => _restoreFlight ??= () async {
    final generation = _generation;
    try {
      await _refresh();
      _check(generation);
      await refreshProfile();
    } catch (error) {
      if (!_disposed && _user == null) {
        _message =
            error is IdentityException && error.code == 'invalid_credentials'
            ? null
            : 'Session restoration is unavailable. You can sign in again.';
      }
    } finally {
      _restoring = false;
      _publish();
    }
  }();

  Future<void> login(String email, String password) {
    final generation = ++_generation;
    _clearMemory();
    return _credentialAction(() async {
      _check(generation);
      await _deleteStored();
      _check(generation);
      await _accept(await _api.login(email, password), generation);
    });
  }

  Future<void> register(String email, String password, String fullName) {
    final generation = _generation;
    return _credentialAction(() async {
      _check(generation);
      await _api.register(email, password, fullName);
      _check(generation);
    });
  }

  Future<bool> googleLogin() {
    final generation = ++_generation;
    return _credentialAction(() async {
      _check(generation);
      final idToken = await _google.signInIdToken();
      _check(generation);
      if (idToken == null) return false;
      _clearMemory();
      await _deleteStored();
      _check(generation);
      await _accept(await _api.google(idToken), generation);
      return true;
    });
  }

  Future<String> _refresh() {
    if (_refreshFlight != null) return _refreshFlight!;
    final generation = _generation;
    _refreshFlight = _credentialAction(() async {
      try {
        _check(generation);
        final refresh = await _readStored();
        if (refresh == null) {
          throw IdentityException('invalid_credentials', 401);
        }
        _check(generation);
        return await _accept(await _api.refresh(refresh), generation);
      } catch (error) {
        if (!_disposed && generation == _generation) {
          _generation++;
          _clearMemory();
          try {
            await _deleteStored();
          } catch (_) {
            throw IdentityException('storage_unavailable');
          }
        }
        rethrow;
      }
    }).whenComplete(() => _refreshFlight = null);
    return _refreshFlight!;
  }

  Future<String> accessToken() {
    if (_disposed) return Future.error(IdentityException('session_changed'));
    if (_access != null && _expires!.isAfter(_now())) {
      return Future.value(_access);
    }
    return _refresh();
  }

  Future<T> _protected<T>(
    Future<T> Function(String token) operation, {
    bool signOutOnDenied = true,
  }) async {
    final generation = _generation;
    try {
      final token = await accessToken();
      _check(generation);
      final result = await operation(token);
      _check(generation);
      return result;
    } on IdentityException catch (error) {
      if (signOutOnDenied &&
          generation == _generation &&
          (error.status == 401 || error.status == 403)) {
        _generation++;
        _clearMemory();
        await _serial(_deleteStored);
      }
      rethrow;
    }
  }

  Future<void> refreshProfile() async {
    final generation = _generation;
    final profile = await _protected(_api.profile);
    _check(generation);
    if (!profile.isActive || profile.id != _user?.id) {
      _generation++;
      _clearMemory();
      await _serial(_deleteStored);
      throw IdentityException('invalid_credentials', 401);
    }
    _setUser(profile);
    _publish();
  }

  Future<void> updateProfile({
    required String fullName,
    required String? phoneNumber,
    String? address,
  }) async {
    final generation = _generation;
    final result = await _protected(
      (access) => _api.updateProfile(access, fullName, phoneNumber, address),
    );
    _check(generation);
    if (result.id != _user?.id || !result.isActive) {
      throw IdentityException('invalid_response');
    }
    _setUser(result);
    _publish();
  }

  Future<bool> linkGoogle(String currentPassword) async {
    final generation = _generation;
    final idToken = await _google.signInIdToken();
    _check(generation);
    if (idToken == null) return false;
    final result = await _protected(
      (access) => _api.linkGoogle(access, idToken, currentPassword),
      signOutOnDenied: false,
    );
    _check(generation);
    if (result.id != _user?.id || !result.isActive) {
      throw IdentityException('invalid_response');
    }
    _setUser(result);
    _publish();
    return true;
  }

  Future<void> logout() {
    final access = _access;
    final expires = _expires;
    _generation++;
    _clearMemory();
    return _credentialAction(() async {
      var confirmed = !_abandonedRevocationUnconfirmed;
      try {
        final raw = await _readStored();
        if (raw != null) {
          if (access != null && expires != null && expires.isAfter(_now())) {
            await _api.logout(access, raw);
          } else {
            final pair = await _api.refresh(raw);
            await _api.logout(pair.accessToken, pair.refreshToken);
          }
        } else if (access != null) {
          confirmed = false;
        }
      } catch (_) {
        confirmed = false;
      } finally {
        try {
          await _deleteStored();
        } catch (_) {
          confirmed = false;
        }
        try {
          await _google.signOut();
        } catch (_) {
          confirmed = false;
        }
      }
      if (!confirmed) throw IdentityException('logout_unconfirmed');
    });
  }

  Future<ApiReply> authorizedRequest(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    if (headers.keys.any((key) {
      final name = key.toLowerCase();
      return name == 'authorization' ||
          name == 'cookie' ||
          name == 'origin' ||
          name == 'x-api-key' ||
          name.startsWith('x-user-');
    })) {
      throw IdentityException('invalid_input');
    }
    final generation = _generation;
    var token = await accessToken();
    _check(generation);
    Future<ApiReply> send() => _api.transport.send(
      method,
      path,
      body: body,
      headers: {...headers, 'Authorization': 'Bearer $token'},
    );
    var response = await send();
    _check(generation);
    if (response.status == 401 && method.toUpperCase() == 'GET') {
      token = await _refresh();
      _check(generation);
      response = await send();
      _check(generation);
    }
    if (response.status == 401) {
      _generation++;
      _clearMemory();
      await _serial(_deleteStored);
      throw IdentityException('invalid_credentials', 401);
    }
    return response;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _access = null;
    _user = null;
    super.dispose();
  }
}

/// Supplies the existing booking RequestTransport seam without storing identity.
final class IdentityAuthenticatedTransport implements RequestTransport {
  IdentityAuthenticatedTransport(this.controller);
  final IdentityController controller;
  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) =>
      controller.authorizedRequest(method, path, body: body, headers: headers);
}
