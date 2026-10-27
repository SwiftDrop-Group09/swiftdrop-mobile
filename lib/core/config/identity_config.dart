import '../errors/identity_exception.dart';

enum IdentityAppMode { customer, courier }

final class IdentityConfig {
  IdentityConfig({
    required this.apiOrigin,
    this.googleServerClientId,
    this.googleIosClientId,
    this.appMode = IdentityAppMode.customer,
  }) {
    validateApiOrigin(apiOrigin);
  }

  factory IdentityConfig.fromEnvironment() {
    const origin = String.fromEnvironment('API_BASE_URL');
    const mode = String.fromEnvironment('APP_MODE', defaultValue: 'customer');
    const server = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    const ios = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    final uri = Uri.tryParse(origin);
    if (uri == null || (mode != 'customer' && mode != 'courier')) {
      throw const IdentityException('invalid_configuration');
    }
    return IdentityConfig(
      apiOrigin: uri,
      googleServerClientId: server.isEmpty ? null : server,
      googleIosClientId: ios.isEmpty ? null : ios,
      appMode: mode == 'courier'
          ? IdentityAppMode.courier
          : IdentityAppMode.customer,
    );
  }

  final Uri apiOrigin;
  final String? googleServerClientId;
  final String? googleIosClientId;
  final IdentityAppMode appMode;
}

void validateApiOrigin(Uri origin) {
  if (origin.scheme != 'https' ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    throw const IdentityException('invalid_configuration');
  }
}
