/// Safe errors intended for presentation. Raw provider/network errors and
/// response bodies must never be included in these messages.
final class IdentityException implements Exception {
  const IdentityException(this.code, [this.status = 0]);

  final String code;
  final int status;

  String get message => switch (code) {
    'invalid_credentials' =>
      'Sign-in failed or the session expired. Please sign in again.',
    'account_link_required' =>
      'Sign in with your local password, then link Google from your profile.',
    'registration_conflict' => 'Registration could not be completed. Try signing in to the existing account.',
    'account_link_rejected' || 'google_identity_conflict' => 'The Google account could not be linked. Use the same verified email and your current local password.',
    'validation' ||
    'invalid_request' => 'Check the supplied information and try again.',
    'forbidden' =>
      'This account does not have permission to perform that action.',
    'session_changed' => 'The session changed. Please sign in again.',
    'logout_unconfirmed' => 'Session memory was cleared. Complete sign-out could not be confirmed. Try again when secure storage and the service are available.',
    'storage_unavailable' => 'Secure session storage is unavailable. Please try again on a supported device.',
    'google_unavailable' =>
      'Google sign-in is unavailable. You can use your local password.',
    'invalid_configuration' =>
      'The app requires a configured HTTPS API origin.',
    'unsupported_platform' => 'Use the Android or iOS app for mobile sign-in.',
    'invalid_response' =>
      'The server response could not be verified. Please sign in again.',
    _ => 'The request could not be completed. Check your connection before trying again.',
  };

  @override
  String toString() => message;
}
