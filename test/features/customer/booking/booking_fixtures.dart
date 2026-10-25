import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/customer_session.dart';
import 'package:swiftdrop_mobile/features/customer/booking/data/booking_api.dart';
import 'package:swiftdrop_mobile/features/customer/booking/domain/booking_models.dart';
import 'package:swiftdrop_mobile/features/customer/booking/presentation/booking_controller.dart';

const ownerId = '11111111-1111-4111-8111-111111111111';
const otherOwnerId = '22222222-2222-4222-8222-222222222222';
const pickupId = '33333333-3333-4333-8333-333333333333';
const deliveryId = '44444444-4444-4444-8444-444444444444';
const quoteId = '55555555-5555-4555-8555-555555555555';
const parcelId = '66666666-6666-4666-8666-666666666666';
final now = DateTime.utc(2026, 10, 24, 12);
const zones = [
  BookingZone(pickupId, 'Test pickup zone'),
  BookingZone(deliveryId, 'Test delivery zone'),
];

BookingDraft draft({
  String weight = '2.5',
  String size = 'Small',
  String recipient = 'Fictional Recipient',
}) => BookingDraft(
  pickup: const BookingAddress(
    street: 'Fictional pickup',
    city: 'Fictional city',
    postalCode: '00000',
    zoneId: pickupId,
  ),
  delivery: const BookingAddress(
    street: 'Fictional delivery',
    city: 'Fictional city',
    postalCode: '00000',
    zoneId: deliveryId,
  ),
  recipientName: recipient,
  recipientPhone: '0000000000',
  weight: weight,
  size: size,
);

String quoteJson({String total = '540', DateTime? expires}) =>
    '{"quoteId":"$quoteId","total":$total,"currency":"LKR","pricingVersion":"test-v1",'
    '"expiresAt":"${(expires ?? now.add(const Duration(minutes: 10))).toIso8601String()}","fingerprint":"opaque-test-fingerprint"}';

String receiptJson({
  String total = '540',
  String version = '1',
  String tracking = 'TRK-server-returned-test-code',
}) =>
    '{"id":"$parcelId","trackingNumber":"$tracking","status":"Created","version":$version,'
    '"priceSnapshot":{"total":$total,"currency":"LKR","pricingVersion":"test-v1"},'
    '"createdAt":"${now.toIso8601String()}"}';

ApiReply problem(
  int status,
  String code, {
  Map<String, String> headers = const {},
}) => ApiReply(status, '{"code":"$code"}', headers);

final class RecordedRequest {
  RecordedRequest(this.method, this.path, this.body, this.headers);
  final String method;
  final String path;
  final String? body;
  final Map<String, String> headers;
}

final class ScriptedTransport implements RequestTransport {
  final requests = <RecordedRequest>[];
  final steps = <Future<ApiReply> Function()>[];
  void reply(ApiReply reply) => steps.add(() async => reply);
  void fail() =>
      steps.add(() => Future.error(StateError('Fictional connection loss')));
  Completer<ApiReply> defer() {
    final completer = Completer<ApiReply>();
    steps.add(() => completer.future);
    return completer;
  }

  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) {
    requests.add(
      RecordedRequest(method, path, body, Map.unmodifiable(headers)),
    );
    if (steps.isEmpty) throw StateError('Unexpected test request');
    return steps.removeAt(0)();
  }
}

final class TestCatalog implements ZoneCatalog {
  TestCatalog({this.pending});
  final Completer<List<BookingZone>>? pending;
  @override
  Future<List<BookingZone>> load() async =>
      pending == null ? zones : pending!.future;
}

final class Scenario {
  Scenario({ZoneCatalog? catalog}) {
    controller = BookingController(
      sessions: sessions,
      api: BookingApi(transport),
      zoneCatalog: catalog ?? TestCatalog(),
      now: () => time,
      newKey: () => 'key-${++keys}',
    );
  }
  final sessions = ValueNotifier(
    const CustomerSession(principalId: ownerId, roles: ['Customer']),
  );
  final transport = ScriptedTransport();
  DateTime time = now;
  int keys = 0;
  late final BookingController controller;
  Future<void> preview({String total = '540'}) async {
    await controller.loadZones();
    transport.reply(ApiReply(200, quoteJson(total: total)));
    await controller.estimate(draft());
  }

  void dispose() {
    controller.dispose();
    sessions.dispose();
  }
}
