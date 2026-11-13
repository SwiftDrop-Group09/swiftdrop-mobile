import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/network/request_transport.dart';
import '../core/session/customer_session.dart';
import '../features/customer/booking/data/booking_api.dart';
import '../features/customer/booking/domain/booking_models.dart';
import '../features/customer/booking/presentation/booking_controller.dart';
import '../features/customer/booking/presentation/booking_screen.dart';
import '../features/customer/tracking/data/tracking_api.dart';
import '../features/customer/tracking/presentation/history_screen.dart';
import '../features/customer/tracking/presentation/receipt_screen.dart';
import '../features/customer/tracking/presentation/tracking_controller.dart';
import '../features/customer/tracking/presentation/tracking_screen.dart';
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
    this.courierMode = false,
    this.profileBuilder,
  });
  final BookingController? controller;
  final CourierController? courierController;
  final ValueListenable<AppSession>? sessions;
  final RequestTransport? transport;
  final ZoneCatalog? zoneCatalog;
  final bool courierMode;
  final WidgetBuilder? profileBuilder;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ValueNotifier<CustomerSession>? _ownedSessions;
  late final BookingController _controller;
  late final CourierController _courier;
  late final TrackingApi _trackingApi;
  late final CustomerHistoryController _history;
  @override
  void initState() {
    super.initState();
    _ownedSessions = widget.sessions == null
        ? ValueNotifier(const CustomerSession.signedOut())
        : null;
    final transport = widget.transport ?? const UnavailableTransport();
    _trackingApi = TrackingApi(transport);
    _controller =
        widget.controller ??
        BookingController(
          sessions: widget.sessions ?? _ownedSessions!,
          api: BookingApi(transport),
          zoneCatalog: widget.zoneCatalog ?? const UnavailableZoneCatalog(),
        );
    _courier =
        widget.courierController ??
        CourierController(
          sessions: widget.sessions ?? _ownedSessions!,
          api: CourierApi(transport),
        );
    _history = CustomerHistoryController(
      sessions: widget.sessions ?? _ownedSessions!,
      api: _trackingApi,
    );
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    if (widget.courierController == null) _courier.dispose();
    _history.dispose();
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
    home: widget.courierMode
        ? CourierScreen(
            controller: _courier,
            showProfile: widget.profileBuilder != null,
          )
        : BookingScreen(
            controller: _controller,
            showProfile: widget.profileBuilder != null,
          ),
    routes: {
      if (widget.profileBuilder != null) '/profile': widget.profileBuilder!,
      '/book': (_) => BookingScreen(
        controller: _controller,
        showProfile: widget.profileBuilder != null,
      ),
      '/history': (_) => CustomerHistoryScreen(controller: _history),
      '/tracking': (context) {
        final parcelId =
            (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
        return CustomerTrackingScreen(
          controller: CustomerParcelDetailController(
            api: _trackingApi,
            parcelId: parcelId,
          ),
        );
      },
      '/receipt': (context) {
        final parcelId =
            (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
        return CustomerReceiptScreen(api: _trackingApi, parcelId: parcelId);
      },
      '/courier': (_) => CourierScreen(
        controller: _courier,
        showProfile: widget.profileBuilder != null,
      ),
    },
  );
}
