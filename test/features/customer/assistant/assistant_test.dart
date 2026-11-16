import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/app_session.dart';
import 'package:swiftdrop_mobile/features/customer/assistant/data/assistant_api.dart';
import 'package:swiftdrop_mobile/features/customer/assistant/domain/assistant_models.dart';
import 'package:swiftdrop_mobile/features/customer/assistant/presentation/assistant_cards.dart';
import 'package:swiftdrop_mobile/features/customer/assistant/presentation/assistant_controller.dart';

final class _AssistantMockTransport implements RequestTransport {
  String? lastPath;
  String? lastBody;
  Map<String, ApiReply> responses = {};

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    lastPath = path;
    lastBody = body;
    for (final entry in responses.entries) {
      if (path.startsWith(entry.key)) return entry.value;
    }
    return const ApiReply(404, '{"code":"not_found"}');
  }
}

void main() {
  group('FormattedAssistantText', () {
    testWidgets('strips raw markdown syntax and formats text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormattedAssistantText(
              text: '### Fee Calculation\nParcel is **Created**.\n- Item 1\n[Book](http://example.com)',
              hasRichCards: true,
            ),
          ),
        ),
      );

      // '### Fee Calculation' stripped when hasRichCards is true
      expect(find.text('Fee Calculation'), findsNothing);
      // 'Created' replaced with 'Booked'
      expect(find.textContaining('Booked'), findsOneWidget);
      expect(find.textContaining('Created'), findsNothing);
      // Link markdown stripped to plain label 'Book'
      expect(find.textContaining('http://example.com'), findsNothing);
    });
  });

  group('Assistant Models & API', () {
    test('AssistantChatResponse parses all cards and tool traces', () {
      final json = {
        'reply': 'Here is the rate for Colombo to Kandy.',
        'mode': 'McpDirect',
        'toolCalls': [
          {
            'toolName': 'estimate_delivery_fee',
            'arguments': {'weightKg': 2.0, 'size': 'Small'},
            'status': 'success',
            'durationMs': 24,
            'summary': 'Estimated fee LKR 560.00',
          }
        ],
        'cards': {
          'quote': {
            'quoteId': '33333333-3333-3333-3333-333333333333',
            'total': 560.0,
            'currency': 'LKR',
            'pricingVersion': 'LK-2026-11',
            'expiresAt': '2026-11-16T12:00:00Z',
            'weightKg': 2.0,
            'size': 'Small',
            'pickupCity': 'Colombo',
            'deliveryCity': 'Kandy',
            'bookingDeepLink': '/customer/book?quoteId=33333333',
          },
          'tracking': {
            'trackingNumber': 'TRK-9D399481A78E',
            'status': 'InTransit',
            'originCity': 'Colombo',
            'destinationCity': 'Kandy',
            'lastUpdatedAt': '2026-11-16T08:00:00Z',
            'steps': [
              {
                'status': 'Created',
                'label': 'Booked',
                'completed': true,
                'current': false,
              },
              {
                'status': 'InTransit',
                'label': 'In transit',
                'completed': true,
                'current': true,
              },
            ],
            'canViewReceipt': false,
            'isPublic': false,
          },
        },
        'suggestedPrompts': ['How much to send 25 kg?', 'Where is my parcel?'],
        'guardrail': {'blocked': false, 'reason': ''},
      };

      final response = AssistantChatResponse.fromJson(json);

      expect(response.reply, contains('Colombo to Kandy'));
      expect(response.mode, 'McpDirect');
      expect(response.toolCalls, hasLength(1));
      expect(response.toolCalls.first.toolName, 'estimate_delivery_fee');
      expect(response.cards?.quote?.total, 560.0);
      expect(response.cards?.tracking?.trackingNumber, 'TRK-9D399481A78E');
      expect(response.cards?.tracking?.currentMilestoneIndex, 2);
      expect(response.suggestedPrompts, hasLength(2));
      expect(response.guardrail?.blocked, isFalse);
    });

    test('AssistantController sends message and records assistant reply', () async {
      final transport = _AssistantMockTransport();
      transport.responses['/api/v1/assistant/chat'] = ApiReply(
        200,
        jsonEncode({
          'reply': 'Your parcel TRK-100 is in transit to Kandy.',
          'mode': 'McpDirect',
          'toolCalls': [],
          'suggestedPrompts': ['Where is my parcel?'],
        }),
      );

      final sessions = ValueNotifier(
        const AppSession(principalId: 'cust-1', roles: ['Customer']),
      );
      final controller = AssistantController(
        api: AssistantApi(transport),
        sessions: sessions,
      );

      await controller.sendMessage('Where is my parcel?');

      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.role, 'user');
      expect(controller.messages.first.content, 'Where is my parcel?');
      expect(controller.messages.last.role, 'assistant');
      expect(controller.messages.last.content, contains('TRK-100'));

      controller.clearChat();
      expect(controller.messages, isEmpty);
    });
  });

  group('Result Card Widgets', () {
    testWidgets('MobileTrackingResultCard displays monospace tracking code and milestone', (tester) async {
      final cardData = TrackingCardData(
        trackingNumber: 'TRK-TEST-999',
        status: 'InTransit',
        originCity: 'Colombo',
        destinationCity: 'Galle',
        lastUpdatedAt: DateTime.utc(2026, 11, 16, 10, 30),
        steps: const [
          AssistantMilestoneStep(
            status: 'Created',
            label: 'Booked',
            completed: true,
            current: false,
          ),
          AssistantMilestoneStep(
            status: 'InTransit',
            label: 'In transit',
            completed: true,
            current: true,
          ),
        ],
        canViewReceipt: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileTrackingResultCard(
              tracking: cardData,
              onOpenTracker: () {},
            ),
          ),
        ),
      );

      expect(find.text('TRK-TEST-999'), findsOneWidget);
      expect(find.text('In transit'), findsWidgets);
      expect(find.text('Colombo → Galle'), findsOneWidget);
      expect(find.text('Milestone 2 of 6'), findsOneWidget);
      expect(find.text('Open live tracker'), findsOneWidget);
    });

    testWidgets('MobileQuoteResultCard displays route, price, and Book button', (tester) async {
      var booked = false;
      final quoteData = QuoteCardData(
        quoteId: 'quote-123',
        total: 740.0,
        currency: 'LKR',
        pricingVersion: 'LK-2026-11',
        weightKg: 2.0,
        size: 'Small',
        pickupCity: 'Kandy',
        deliveryCity: 'Jaffna',
        bookingDeepLink: '/customer/book?quoteId=quote-123',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileQuoteResultCard(
              quote: quoteData,
              onBook: () => booked = true,
            ),
          ),
        ),
      );

      expect(find.text('Kandy → Jaffna'), findsOneWidget);
      expect(find.text('2 kg · Small'), findsOneWidget);
      expect(find.text('LKR 740.00'), findsOneWidget);
      expect(find.text('Tariff LK-2026-11'), findsOneWidget);
      expect(find.text('Book this delivery'), findsOneWidget);

      await tester.tap(find.text('Book this delivery'));
      expect(booked, isTrue);
    });
  });
}
