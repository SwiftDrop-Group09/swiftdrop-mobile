import 'identity_role.dart';

/// IAM owns authentication; features consume the same injected session snapshot.
final class AppSession {
  const AppSession({this.principalId, this.roles = const []});
  const AppSession.signedOut() : principalId = null, roles = const [];
  final String? principalId;
  final List<String> roles;
  bool get _signedIn =>
      principalId != null && principalId!.isNotEmpty && role != null;
  IdentityRole? get role => roles.length == 1
      ? IdentityRole.values
            .where((role) => role.wireValue == roles.single)
            .firstOrNull
      : null;
  bool get signedIn => _signedIn;
  bool get canBook => _signedIn && role == IdentityRole.customer;
  bool get canCourier => _signedIn && role == IdentityRole.courier;
  String get scope =>
      '${principalId ?? ''}:${(List.of(roles)..sort()).join(',')}';
}
