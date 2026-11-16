import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/app_session.dart';
import 'package:swiftdrop_mobile/features/customer/tracking/data/tracking_api.dart';
import 'package:swiftdrop_mobile/features/customer/tracking/domain/tracking_models.dart';
import 'package:swiftdrop_mobile/features/customer/tracking/presentation/tracking_controller.dart';

final class _FakeTransport implements RequestTransport {
  String? lastPath;
  Map<String, String>? lastHeaders;
  Map<String, ApiReply> responses = {};

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    lastPath = path;
    lastHeaders = headers;
    for (final entry in responses.entries) {
      if (path.startsWith(entry.key)) return entry.value;
    }
    return const ApiReply(404, '{"code":"not_found"}');
  }
}

void main() {
  test('parcelStatusLabel maps all documented canonical statuses', () {
    expect(parcelStatusLabel('Created'), 'Booked');
    expect(parcelStatusLabel('Assigned'), 'Assigned');
    expect(parcelStatusLabel('PickedUp'), 'Collected');
    expect(parcelStatusLabel('InTransit'), 'In transit');
    expect(parcelStatusLabel('OutForDelivery'), 'Out for delivery');
    expect(parcelStatusLabel('Delivered'), 'Delivered');
    expect(parcelStatusLabel('Failed'), 'Delivery unsuccessful');
    expect(parcelStatusLabel('Cancelled'), 'Cancelled');
  });

  test(
    'CustomerHistoryController loads paginated parcels and applies filters',
    () async {
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
        const AppSession(principalId: 'cust-1', roles: ['Customer']),
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

      await controller.setDateRange(
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 11, 16),
      );
      expect(transport.lastPath, contains('from=2026-11-01'));
      expect(transport.lastPath, contains('to=2026-11-16'));
    },
  );

  test('CustomerParcelDetailController 4-second polling lifecycle', () async {
    final transport = _FakeTransport();
    final parcelJson = jsonEncode({
      'id': '22222222-2222-2222-2222-222222222222',
      'trackingNumber': 'TRK-IN-TRANSIT',
      'status': 'InTransit',
      'version': 1,
      'createdAt': '2026-11-16T00:00:00Z',
      'pickupAddress': {
        'street': 'Galle Rd',
        'city': 'Colombo',
        'postalCode': '00300',
        'zoneId': 'z1',
      },
      'deliveryAddress': {
        'street': 'Peradeniya Rd',
        'city': 'Kandy',
        'postalCode': '20000',
        'zoneId': 'z2',
      },
      'packageDetails': {'weightKg': 2.0, 'size': 'Small'},
      'recipient': {'name': 'Kasun Perera', 'phoneNumber': '0771234567'},
      'priceSnapshot': {'total': 560.0, 'currency': 'LKR', 'pricingVersion': 'v1'},
      'history': [],
    });

    transport.responses['/api/v1/parcels/22222222-2222-2222-2222-222222222222'] =
        ApiReply(200, parcelJson);

    final controller = CustomerParcelDetailController(
      api: TrackingApi(transport),
      parcelId: '22222222-2222-2222-2222-222222222222',
    );

    await controller.load(startLivePolling: true);
    expect(controller.parcel?.status, 'InTransit');
    expect(controller.isLivePollingActive, isTrue);

    controller.dispose();
    expect(controller.isLivePollingActive, isFalse);
  });

  test('TrackingApi downloads receipt PDF bytes with correct headers', () async {
    final transport = _FakeTransport();
    final fakePdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
    transport.responses['/api/v1/parcels/p-1/receipt'] = ApiReply(
      200,
      '%PDF',
      {'content-type': 'application/pdf'},
      fakePdfBytes,
    );

    final api = TrackingApi(transport);
    final bytes = await api.downloadReceiptPdf('p-1');

    expect(bytes, fakePdfBytes);
    expect(transport.lastPath, '/api/v1/parcels/p-1/receipt?format=pdf');
    expect(transport.lastHeaders?['Accept'], 'application/pdf');
  });
}
