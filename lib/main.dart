import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/identity_config.dart';
import 'core/network/request_transport.dart';
import 'core/storage/refresh_token_store.dart';
import 'features/auth/data/identity_api.dart';
import 'features/auth/data/native_google_identity_provider.dart';
import 'features/auth/presentation/identity_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    runApp(
      const _StartupMessage(
        'SwiftDrop mobile sign-in requires an Android or iOS device.',
      ),
    );
    return;
  }

  HttpRequestTransport? transport;
  try {
    final config = IdentityConfig.fromEnvironment();
    transport = HttpRequestTransport(config.apiOrigin);
    final controller = IdentityController(
      api: IdentityApi(transport),
      tokens: NativeRefreshTokenStore(),
      google: NativeGoogleIdentityProvider(
        serverClientId: config.googleServerClientId,
        iosClientId: config.googleIosClientId,
      ),
    );
    final googleEnabled =
        config.googleServerClientId?.isNotEmpty == true &&
        (defaultTargetPlatform != TargetPlatform.iOS ||
            config.googleIosClientId?.isNotEmpty == true);
    runApp(
      SwiftDropApp(
        controller: controller,
        mode: config.appMode,
        googleEnabled: googleEnabled,
        disposeController: true,
        onDispose: transport.close,
      ),
    );
  } catch (_) {
    transport?.close();
    runApp(
      const _StartupMessage(
        'SwiftDrop could not start. Please contact your app administrator to check this deployment.',
      ),
    );
  }
}

class _StartupMessage extends StatelessWidget {
  const _StartupMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SwiftDrop',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
}
