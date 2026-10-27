import 'package:flutter/material.dart';

import '../core/config/identity_config.dart';
import '../core/errors/identity_exception.dart';
import '../features/auth/presentation/identity_controller.dart';
import '../features/auth/presentation/identity_screens.dart';

class SwiftDropApp extends StatefulWidget {
  const SwiftDropApp({
    super.key,
    required this.controller,
    required this.mode,
    this.googleEnabled = true,
    this.disposeController = false,
    this.onDispose,
  });

  final IdentityController controller;
  final IdentityAppMode mode;
  final bool googleEnabled;
  final bool disposeController;
  final VoidCallback? onDispose;

  @override
  State<SwiftDropApp> createState() => _SwiftDropAppState();
}

class _SwiftDropAppState extends State<SwiftDropApp> {
  String? _restorationMessage;

  @override
  void initState() {
    super.initState();
    _restore();
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
    if (widget.disposeController) widget.controller.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
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
