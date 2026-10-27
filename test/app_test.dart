import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/main.dart';

void main() {
  testWidgets(
    'normal app requires a Customer session and never enables fixture identity',
    (tester) async {
      await tester.pumpWidget(const MyApp());
      expect(find.text('Book a delivery'), findsOneWidget);
      expect(
        find.text('Sign in with a Customer account to book a delivery.'),
        findsOneWidget,
      );
      expect(find.text('Estimate delivery fee'), findsNothing);
      expect(find.text('TEST DATA'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
