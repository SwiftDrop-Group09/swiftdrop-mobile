import '../../../core/errors/identity_exception.dart';

const identityRoles = {
  'Customer',
  'Courier',
  'Merchant',
  'Dispatcher',
  'Admin',
};
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _refresh = RegExp(r'^[A-Za-z0-9_-]{43}$');

bool isRefreshToken(String value) => _refresh.hasMatch(value);

final class IdentityProfile {
  IdentityProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    required this.address,
    required List<String> roles,
    required this.isActive,
  }) : roles = List.unmodifiable(roles);

  factory IdentityProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final email = json['email'];
    final name = json['fullName'];
    final phone = json['phoneNumber'];
    final address = json['address'];
    final roles = json['roles'];
    final active = json['isActive'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        id == '00000000-0000-0000-0000-000000000000' ||
        email is! String ||
        email.isEmpty ||
        email.length > 254 ||
        name is! String ||
        (phone != null && phone is! String) ||
        (address != null && address is! String) ||
        !json.containsKey('phoneNumber') ||
        !json.containsKey('address') ||
        roles is! List ||
        roles.length > 5 ||
        roles.any((role) => role is! String || !identityRoles.contains(role)) ||
        roles.toSet().length != roles.length ||
        active is! bool) {
      throw const IdentityException('invalid_response');
    }
    return IdentityProfile(
      id: id,
      email: email,
      fullName: name,
      phoneNumber: phone as String?,
      address: address as String?,
      roles: roles.cast<String>(),
      isActive: active,
    );
  }

  final String id;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final String? address;
  final List<String> roles;
  final bool isActive;
}

final class IdentityTokenPair {
  const IdentityTokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
    required this.user,
  });

  factory IdentityTokenPair.fromJson(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expires = json['expiresInSeconds'];
    final user = json['user'];
    if (access is! String ||
        access.isEmpty ||
        access.length > 16384 ||
        json['tokenType'] != 'Bearer' ||
        refresh is! String ||
        !isRefreshToken(refresh) ||
        expires is! int ||
        expires < 1 ||
        expires > 900 ||
        user is! Map<String, dynamic>) {
      throw const IdentityException('invalid_response');
    }
    final profile = IdentityProfile.fromJson(user);
    if (!profile.isActive) throw const IdentityException('invalid_response');
    return IdentityTokenPair(
      accessToken: access,
      refreshToken: refresh,
      expiresInSeconds: expires,
      user: profile,
    );
  }

  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;
  final IdentityProfile user;
}
