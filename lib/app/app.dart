import 'package:flutter/material.dart';

import '../core/config/identity_config.dart';
import '../core/errors/identity_exception.dart';
import '../core/session/customer_session.dart';
import '../features/customer/booking/data/booking_api.dart';
import '../features/auth/presentation/identity_controller.dart';
import '../features/auth/presentation/identity_screens.dart';
import 'delivery_app.dart';

export 'delivery_app.dart' show MyApp;

class SwiftDropApp extends StatefulWidget {
  const SwiftDropApp({
    super.key,
    required this.controller,
    required this.mode,
    this.googleEnabled = true,
    this.disposeController = false,
    this.onDispose,
    this.workspaceEnabled = true,
  });

  final IdentityController controller;
  final IdentityAppMode mode;
  final bool googleEnabled;
  final bool disposeController;
  final VoidCallback? onDispose;
  final bool workspaceEnabled;

  @override
  State<SwiftDropApp> createState() => _SwiftDropAppState();
}

class _SwiftDropAppState extends State<SwiftDropApp> {
  String? _restorationMessage;
  late final ValueNotifier<CustomerSession> _sessions;
  late final IdentityAuthenticatedTransport _transport;

  @override
  void initState() {
    super.initState();
    _sessions = ValueNotifier(widget.controller.customerSession);
    _transport = IdentityAuthenticatedTransport(widget.controller);
    widget.controller.addListener(_syncSession);
    _restore();
  }

  void _syncSession() {
    final session = widget.controller.customerSession;
    if (_sessions.value.scope != session.scope) _sessions.value = session;
  }

  Future<void> _restore() async {
    try {
      await widget.controller.restore();
    } catch (error) {
      if (mounted) {
        setState(() {
          _restorationMessage = error is IdentityException
              ? error.message
              : 'Your session could not be restored. Please sign in again.';
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSession);
    _sessions.dispose();
    if (widget.disposeController) widget.controller.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final courierMode = widget.mode == IdentityAppMode.courier;
      final session = widget.controller.customerSession;
      if (widget.workspaceEnabled && !widget.controller.restoring &&
          (courierMode ? session.canCourier : session.canBook)) {
        return MyApp(
          key: ValueKey(session.scope),
          sessions: _sessions,
          transport: _transport,
          zoneCatalog: ApiZoneCatalog(_transport),
          courierMode: courierMode,
          profileBuilder: (_) => IdentityProfileScreen(
            controller: widget.controller,
            mode: widget.mode,
            googleEnabled: widget.googleEnabled,
          ),
        );
      }
      return _identityApp();
    },
  );

  Widget _identityApp() => MaterialApp(
    title: widget.mode == IdentityAppMode.courier
        ? 'SwiftDrop Courier'
        : 'SwiftDrop Customer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b56)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      useMaterial3: true,
    ),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.restoring) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Restoring your session…'),
                ],
              ),
            ),
          );
        }
        if (widget.controller.user == null) {
          return IdentitySignInScreen(
            controller: widget.controller,
            mode: widget.mode,
            googleEnabled: widget.googleEnabled,
            initialNotice: _restorationMessage ?? widget.controller.message,
          );
        }
        return IdentityProfileScreen(
          controller: widget.controller,
          mode: widget.mode,
          googleEnabled: widget.googleEnabled,
        );
      },
    ),
  );
}
