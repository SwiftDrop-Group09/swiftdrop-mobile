import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/network/request_transport.dart';
import '../core/session/customer_session.dart';
import '../features/customer/booking/data/booking_api.dart';
import '../features/customer/booking/domain/booking_models.dart';
import '../features/customer/booking/presentation/booking_controller.dart';
import '../features/customer/booking/presentation/booking_screen.dart';
import '../features/courier/courier_api.dart';
import '../features/courier/courier_controller.dart';
import '../features/courier/courier_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.controller,
    this.courierController,
    this.sessions,
    this.transport,
    this.zoneCatalog,
  });
  final BookingController? controller;
  final CourierController? courierController;
  final ValueListenable<AppSession>? sessions;
  final RequestTransport? transport;
  final ZoneCatalog? zoneCatalog;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ValueNotifier<CustomerSession>? _ownedSessions;
  late final BookingController _controller;
  late final CourierController _courier;
  @override
  void initState() {
    super.initState();
    _ownedSessions = widget.sessions == null
        ? ValueNotifier(const CustomerSession.signedOut())
        : null;
    _controller =
        widget.controller ??
        BookingController(
          sessions: widget.sessions ?? _ownedSessions!,
          api: BookingApi(widget.transport ?? const UnavailableTransport()),
          zoneCatalog: widget.zoneCatalog ?? const UnavailableZoneCatalog(),
        );
    _courier =
        widget.courierController ??
        CourierController(
          sessions: widget.sessions ?? _ownedSessions!,
          api: CourierApi(widget.transport ?? const UnavailableTransport()),
        );
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    if (widget.courierController == null) _courier.dispose();
    _ownedSessions?.dispose();
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
    routes: {
      '/book': (_) => BookingScreen(controller: _controller),
      '/courier': (_) => CourierScreen(controller: _courier),
    },
  );
}
