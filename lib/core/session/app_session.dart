/// IAM owns authentication; features consume the same injected session snapshot.
final class AppSession {
  const AppSession({this.principalId, this.roles = const []});
  const AppSession.signedOut() : principalId = null, roles = const [];
  final String? principalId;
  final List<String> roles;
  bool get _signedIn => principalId != null && principalId!.isNotEmpty;
  bool get canBook => _signedIn && roles.contains('Customer');
  bool get canCourier => _signedIn && roles.contains('Courier');
  String get scope =>
      '${principalId ?? ''}:${(List.of(roles)..sort()).join(',')}';
}
