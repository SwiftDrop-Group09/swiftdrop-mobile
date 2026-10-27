import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/app/app.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/customer_session.dart';
import 'package:swiftdrop_mobile/features/customer/booking/presentation/booking_screen.dart';

import 'booking_fixtures.dart';

Future<void> enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> choose(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  for (final prefix in ['pickup', 'delivery']) {
    await enter(tester, '${prefix}Street', 'Fictional $prefix street');
    await enter(tester, '${prefix}City', 'Fictional city');
    await enter(tester, '${prefix}PostalCode', '00000');
    await choose(
      tester,
      '${prefix}Zone',
      prefix == 'pickup' ? 'Test pickup zone' : 'Test delivery zone',
    );
  }
  await enter(tester, 'recipientName', 'Fictional Recipient');
  await enter(tester, 'recipientPhone', '0000000000');
  await choose(tester, 'size', 'Small');
  await enter(tester, 'weight', '2.5');
}

Future<void> press(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

String? selection(WidgetTester tester, String key) => tester
    .widget<DropdownButtonFormField<String>>(find.byKey(Key(key)))
    .initialValue;

void main() {
  late Scenario scenario;
  setUp(() => scenario = Scenario());
  tearDown(() => scenario.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BookingScreen(controller: scenario.controller)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('labelled validation errors prevent requests', (tester) async {
    await mount(tester);
    await press(tester, 'estimateFee');
    expect(find.text('This field is required.'), findsWidgets);
    expect(find.text('Choose a service zone.'), findsWidgets);
    expect(scenario.transport.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('form preview and decline never submit a booking', (
    tester,
  ) async {
    await mount(tester);
    await fill(tester);
    scenario.transport.reply(ApiReply(200, quoteJson()));
    await press(tester, 'estimateFee');
    expect(find.text('LKR 540.00'), findsOneWidget);
    expect(find.text('Accept fee and confirm booking'), findsOneWidget);
    await press(tester, 'declineQuote');
    expect(find.text('LKR 540.00'), findsNothing);
    expect(scenario.transport.requests.single.path, '/api/v1/quotes');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit confirmation shows only server returned tracking', (
    tester,
  ) async {
    await mount(tester);
    await fill(tester);
    scenario.transport.reply(ApiReply(200, quoteJson()));
    await press(tester, 'estimateFee');
    expect(find.text('Booking confirmed'), findsNothing);
    scenario.transport.reply(ApiReply(201, receiptJson()));
    await press(tester, 'confirmBooking');
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('TRK-server-returned-test-code'), findsOneWidget);
    expect(scenario.transport.requests.map((request) => request.path), [
      '/api/v1/quotes',
      '/api/v1/parcels',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'root and book routes show the same quoted details after push and pop',
    (tester) async {
      await tester.pumpWidget(MyApp(controller: scenario.controller));
      await tester.pumpAndSettle();
      await fill(tester);
      scenario.transport.reply(ApiReply(200, quoteJson()));
      await press(tester, 'estimateFee');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.pushNamed<void>('/book'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'pickupStreet'), 'Fictional pickup street');
      expect(fieldText(tester, 'deliveryStreet'), 'Fictional delivery street');
      expect(fieldText(tester, 'recipientName'), 'Fictional Recipient');
      expect(fieldText(tester, 'recipientPhone'), '0000000000');
      expect(fieldText(tester, 'weight'), '2.5');
      expect(selection(tester, 'pickupZone'), pickupId);
      expect(selection(tester, 'deliveryZone'), deliveryId);
      expect(selection(tester, 'size'), 'Small');
      expect(find.text('LKR 540.00'), findsOneWidget);

      await enter(tester, 'recipientName', 'Updated Fictional Recipient');
      await enter(tester, 'weight', '6');
      await choose(tester, 'pickupZone', 'Test delivery zone');
      await choose(tester, 'deliveryZone', 'Test pickup zone');
      await choose(tester, 'size', 'Large');
      expect(find.text('LKR 540.00'), findsNothing);
      scenario.transport.reply(ApiReply(200, quoteJson(total: '800')));
      await press(tester, 'estimateFee');
      navigator.pop();
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'pickupStreet'), 'Fictional pickup street');
      expect(fieldText(tester, 'pickupCity'), 'Fictional city');
      expect(fieldText(tester, 'pickupPostalCode'), '00000');
      expect(fieldText(tester, 'deliveryStreet'), 'Fictional delivery street');
      expect(fieldText(tester, 'deliveryCity'), 'Fictional city');
      expect(fieldText(tester, 'deliveryPostalCode'), '00000');
      expect(fieldText(tester, 'recipientName'), 'Updated Fictional Recipient');
      expect(fieldText(tester, 'recipientPhone'), '0000000000');
      expect(fieldText(tester, 'weight'), '6');
      expect(selection(tester, 'pickupZone'), deliveryId);
      expect(selection(tester, 'deliveryZone'), pickupId);
      expect(selection(tester, 'size'), 'Large');
      expect(find.text('LKR 800.00'), findsOneWidget);
      expect(scenario.transport.requests.last.body, contains('"weightKg":6'));
      expect(
        scenario.transport.requests.last.body,
        contains('"name":"Updated Fictional Recipient"'),
      );

      scenario.transport.reply(ApiReply(201, receiptJson(total: '800')));
      await press(tester, 'confirmBooking');
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(
        scenario.transport.requests.last.body,
        contains('"acceptTotal":800'),
      );
      expect(scenario.keys, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unmount and remount preserve an uncertain attempt in the host controller',
    (tester) async {
      await scenario.preview();
      scenario.transport.fail();
      await scenario.controller.confirm();
      final original = scenario.transport.requests.last;
      await mount(tester);
      expect(find.text('Retry this confirmation'), findsOneWidget);
      expect(fieldText(tester, 'pickupStreet'), 'Fictional pickup');
      expect(fieldText(tester, 'deliveryStreet'), 'Fictional delivery');
      expect(fieldText(tester, 'recipientName'), 'Fictional Recipient');
      expect(fieldText(tester, 'weight'), '2.5');
      expect(selection(tester, 'pickupZone'), pickupId);
      expect(selection(tester, 'deliveryZone'), deliveryId);
      expect(selection(tester, 'size'), 'Small');
      await tester.pumpWidget(const SizedBox.shrink());
      scenario.time = now.add(const Duration(minutes: 11));
      await mount(tester);
      expect(fieldText(tester, 'recipientName'), 'Fictional Recipient');
      expect(selection(tester, 'size'), 'Small');
      scenario.transport.reply(ApiReply(201, receiptJson()));
      await press(tester, 'retryConfirmation');
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(scenario.transport.requests.last.body, original.body);
      expect(
        scenario.transport.requests.last.headers['Idempotency-Key'],
        original.headers['Idempotency-Key'],
      );
      expect(scenario.keys, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'tracking result is announced and copied with the exact server value',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        String? copied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await scenario.preview();
        scenario.transport.reply(ApiReply(201, receiptJson()));
        await scenario.controller.confirm();
        await mount(tester);
        expect(
          find.bySemanticsLabel(
            'Tracking number: TRK-server-returned-test-code',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Copy tracking number'));
        await tester.pumpAndSettle();
        expect(copied, 'TRK-server-returned-test-code');
        expect(find.text('Tracking number copied.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('principal changes clear form fields and private preview', (
    tester,
  ) async {
    await mount(tester);
    await fill(tester);
    scenario.transport.reply(ApiReply(200, quoteJson()));
    await press(tester, 'estimateFee');
    scenario.sessions.value = const CustomerSession(
      principalId: otherOwnerId,
      roles: ['Customer'],
    );
    await tester.pumpAndSettle();
    expect(find.text('LKR 540.00'), findsNothing);
    expect(find.text('Fictional Recipient'), findsNothing);
    expect(find.text('Fictional pickup street'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
