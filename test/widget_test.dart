import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/main.dart' as app;

void main() {
  testWidgets('Native sign-in fails closed on an unsupported platform', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      app.main();
      await tester.pump();
      expect(
        find.text(
          'SwiftDrop mobile sign-in requires an Android or iOS device.',
        ),
        findsOneWidget,
      );
      expect(find.text('Flutter Demo Home Page'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
