abstract interface class GoogleIdentityProvider {
  /// Null means the user canceled; no application login request should follow.
  Future<String?> signInIdToken();
  Future<void> signOut();
}
