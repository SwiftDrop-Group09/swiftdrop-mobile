import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/app_session.dart';
import 'package:swiftdrop_mobile/features/customer/tracking/data/tracking_api.dart';
import 'package:swiftdrop_mobile/features/customer/tracking/domain/tracking_models.dart';
import 'package:swiftdrop_mobile/features/customer/tracking/presentation/tracking_controller.dart';

final class _FakeTransport implements RequestTransport {
  String? lastPath;
  Map<String, ApiReply> responses = {};

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    lastPath = path;
    for (final entry in responses.entries) {
      if (path.startsWith(entry.key)) return entry.value;
    }
    return const ApiReply(404, '{"code":"not_found"}');
  }
}

void main() {
  test('parcelStatusLabel maps documented statuses', () {
    expect(parcelStatusLabel('Created'), 'Booked');
    expect(parcelStatusLabel('PickedUp'), 'Collected');
    expect(parcelStatusLabel('InTransit'), 'In transit');
    expect(parcelStatusLabel('Delivered'), 'Delivered');
  });

  test('CustomerHistoryController loads paginated parcels and applies filters', () async {
    final transport = _FakeTransport();
    transport.responses['/api/v1/parcels'] = ApiReply(
      200,
      jsonEncode({
        'items': [
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'trackingNumber': 'TRK-001',
            'status': 'Delivered',
            'version': 4,
            'priceSnapshot': {
              'total': 540.0,
              'currency': 'LKR',
              'pricingVersion': 'v1',
            },
            'createdAt': '2026-10-16T08:00:00Z',
            'updatedAt': '2026-10-16T12:00:00Z',
            'pickupCity': 'Colombo',
            'deliveryCity': 'Kandy',
            'recipientName': 'Nimali Perera',
            'packageDetails': {'weightKg': 2.5, 'size': 'Medium'},
            'hasProof': true,
          },
        ],
        'totalCount': 1,
        'page': 1,
        'pageSize': 20,
      }),
    );

    final sessions = ValueNotifier(
      const AppSession(
        principalId: 'cust-1',
        roles: ['Customer'],
      ),
    );
    final controller = CustomerHistoryController(
      sessions: sessions,
      api: TrackingApi(transport),
    );

    await controller.setStatusFilter('Delivered');

    expect(controller.error, isNull);
    expect(controller.items, hasLength(1));
    expect(controller.items.first.trackingNumber, 'TRK-001');
    expect(transport.lastPath, contains('status=Delivered'));
  });
}

