import 'dart:convert';

import '../../../core/errors/identity_exception.dart';
import '../../../core/network/request_transport.dart';
import '../domain/identity_models.dart';

final class IdentityApi {
  IdentityApi(this.transport);
  final RequestTransport transport;

  Future<IdentityProfile> register(
    String email,
    String password,
    String fullName,
  ) async => IdentityProfile.fromJson(
    await _request(
      'POST',
      '/api/v1/auth/register',
      body: {'email': email, 'password': password, 'fullName': fullName},
    ),
  );
  Future<IdentityTokenPair> login(String email, String password) async =>
      IdentityTokenPair.fromJson(
        await _request(
          'POST',
          '/api/v1/auth/login',
          body: {'email': email, 'password': password},
        ),
      );
  Future<IdentityTokenPair> google(String idToken) async =>
      IdentityTokenPair.fromJson(
        await _request(
          'POST',
          '/api/v1/auth/google',
          body: {'idToken': idToken},
        ),
      );
  Future<IdentityTokenPair> refresh(String refreshToken) async =>
      IdentityTokenPair.fromJson(
        await _request(
          'POST',
          '/api/v1/auth/refresh',
          body: {'refreshToken': refreshToken},
        ),
      );
  Future<void> logout(String accessToken, String refreshToken) async {
    await _request(
      'POST',
      '/api/v1/auth/logout',
      body: {'refreshToken': refreshToken},
      access: accessToken,
      empty: true,
    );
  }

  Future<IdentityProfile> profile(String accessToken) async =>
      IdentityProfile.fromJson(
        await _request('GET', '/api/v1/users/me', access: accessToken),
      );
  Future<IdentityProfile> updateProfile(
    String accessToken,
    String fullName,
    String? phoneNumber,
    String? address,
  ) async => IdentityProfile.fromJson(
    await _request(
      'PUT',
      '/api/v1/users/me',
      access: accessToken,
      body: {
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'address': address,
      },
    ),
  );
  Future<IdentityProfile> linkGoogle(
    String accessToken,
    String idToken,
    String currentPassword,
  ) async => IdentityProfile.fromJson(
    await _request(
      'POST',
      '/api/v1/auth/google/link',
      access: accessToken,
      body: {'idToken': idToken, 'currentPassword': currentPassword},
    ),
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? access,
    bool empty = false,
  }) async {
    final ApiReply reply;
    try {
      reply = await transport.send(
        method,
        path,
        body: body == null ? null : jsonEncode(body),
        headers: {
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json; charset=utf-8',
          if (access != null) 'Authorization': 'Bearer $access',
        },
      );
    } on IdentityException {
      rethrow;
    } on Exception {
      throw const IdentityException('network_error');
    }
    if (reply.status < 200 || reply.status >= 300) {
      var code = reply.status == 401
          ? 'invalid_credentials'
          : reply.status == 403
          ? 'forbidden'
          : 'request_failed';
      try {
        final failure = jsonDecode(reply.body);
        if (failure is Map<String, dynamic> &&
            const {
              'invalid_credentials',
              'forbidden',
              'account_link_required',
              'registration_conflict',
              'account_link_rejected',
              'google_identity_conflict',
              'validation',
              'identity_unavailable',
            }.contains(failure['code'])) {
          code = failure['code'] as String;
        }
      } on FormatException {
        // Ignore untrusted response text; only fixed error messages are exposed.
      }
      throw IdentityException(code, reply.status);
    }
    if (empty) {
      if (reply.status != 204) {
        throw const IdentityException('invalid_response');
      }
      return {};
    }
    try {
      final json = jsonDecode(reply.body);
      if (json is! Map<String, dynamic>) {
        throw const IdentityException('invalid_response');
      }
      return json;
    } on FormatException {
      throw const IdentityException('invalid_response');
    }
  }
}
