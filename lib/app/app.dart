import 'package:flutter/material.dart';

import '../core/network/request_transport.dart';
import '../core/session/customer_session.dart';
import '../features/customer/booking/data/booking_api.dart';
import '../features/customer/booking/domain/booking_models.dart';
import '../features/customer/booking/presentation/booking_controller.dart';
import '../features/customer/booking/presentation/booking_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.controller});
  final BookingController? controller;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ValueNotifier<CustomerSession>? _ownedSessions;
  late final BookingController _controller;
  @override
  void initState() {
    super.initState();
    _ownedSessions = widget.controller == null
        ? ValueNotifier(const CustomerSession.signedOut())
        : null;
    _controller =
        widget.controller ??
        BookingController(
          sessions: _ownedSessions!,
          api: const BookingApi(UnavailableTransport()),
          zoneCatalog: const UnavailableZoneCatalog(),
        );
  }

  @override
  void dispose() {
    if (_ownedSessions != null) {
      _controller.dispose();
      _ownedSessions.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SwiftDrop',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b56)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    ),
    home: BookingScreen(controller: _controller),
    routes: {'/book': (_) => BookingScreen(controller: _controller)},
  );
}
