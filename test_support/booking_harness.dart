import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:swiftdrop_mobile/app/app.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/features/customer/booking/data/booking_api.dart';
import 'package:swiftdrop_mobile/features/customer/booking/presentation/booking_controller.dart';

import 'fixture_context.dart';

/// Explicit test target only. The normal lib/main.dart never imports this file.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    throw StateError('The booking fixture target cannot run in release mode.');
  }
  const configured = String.fromEnvironment('API_BASE_URL');
  final transport = HttpRequestTransport(
    fixtureBaseUri(configured, pageUri: Uri.base),
  );
  try {
    final context = await FixtureContext.fetch(transport);
    final sessions = ValueNotifier(context.session);
    final controller = BookingController(
      sessions: sessions,
      api: BookingApi(transport),
      zoneCatalog: context,
    );
    runApp(
      Banner(
        message: 'TEST DATA',
        location: BannerLocation.topEnd,
        textDirection: TextDirection.ltr,
        layoutDirection: TextDirection.ltr,
        child: MyApp(controller: controller),
      ),
    );
  } catch (_) {
    transport.close();
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Start the isolated booking test host and reload this test target.',
            ),
          ),
        ),
      ),
    );
  }
}
