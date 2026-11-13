import '../errors/identity_exception.dart';

enum IdentityRole {
  customer('Customer'),
  courier('Courier'),
  merchant('Merchant'),
  dispatcher('Dispatcher'),
  admin('Admin');

  const IdentityRole(this.wireValue);
  final String wireValue;
  static IdentityRole single(List<String> values) {
    if (values.length != 1) throw const IdentityException('invalid_response');
    return IdentityRole.values.firstWhere(
      (role) => role.wireValue == values.single,
      orElse: () => throw const IdentityException('invalid_response'),
    );
  }
}

final identityRoles = IdentityRole.values.map((role) => role.wireValue).toSet();
