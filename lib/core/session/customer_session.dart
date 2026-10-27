final class CustomerSession {
  const CustomerSession({this.principalId, this.roles = const []});
  const CustomerSession.signedOut() : principalId = null, roles = const [];

  final String? principalId;
  final List<String> roles;
  bool get canBook =>
      principalId != null &&
      principalId!.isNotEmpty &&
      roles.contains('Customer');
}
