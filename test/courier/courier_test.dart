import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:swiftdrop_mobile/core/network/exact_json.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/app_session.dart';
import 'package:swiftdrop_mobile/features/courier/courier_api.dart';
import 'package:swiftdrop_mobile/features/courier/courier_models.dart';
import 'package:swiftdrop_mobile/features/courier/courier_controller.dart';
import 'package:swiftdrop_mobile/features/courier/courier_screen.dart';
import 'package:swiftdrop_mobile/features/courier/proof_capture.dart';

const parcelId = '00000000-0000-4000-8000-000000000011';
Map<String, Object?> raw([String status = 'Assigned', int version = 2]) => {
  'id': parcelId,
  'trackingNumber': 'SD-TEST',
  'status': status,
  'version': version,
  'priceSnapshot': {
    'total': 540,
    'currency': 'LKR',
    'pricingVersion': 'test-v1',
  },
  'createdAt': '2026-10-28T10:00:00Z',
};
Map<String, Object?> privateRaw([
  String status = 'Assigned',
  int version = 2,
]) => {
  ...raw(status, version),
  'pickupAddress': {
    'street': 'Pickup street',
    'city': 'Colombo',
    'postalCode': '00100',
    'zoneId': parcelId,
  },
  'deliveryAddress': {
    'street': 'Delivery street',
    'city': 'Galle',
    'postalCode': '80000',
    'zoneId': parcelId,
  },
  'recipient': {'name': 'Test Recipient', 'phoneNumber': '0000000000'},
  'packageDetails': {'weightKg': ExactNumber('2.5'), 'size': 'Small'},
  'assignment': {
    'status': 'Active',
    'serviceDate': '2026-10-29',
    'assignedAt': '2026-10-28T11:00:00Z',
    'pickedUpAt': null,
    'deliveredAt': null,
  },
  'history': [
    {
      'fromStatus': 'Created',
      'toStatus': 'Assigned',
      'changeReason': 'Assigned by dispatcher',
      'deliveryNote': null,
      'timestamp': '2026-10-28T11:00:00Z',
    },
  ],
  'serviceDate': '2026-10-29',
  'isOverdue': false,
};
ParcelDetail detail([String status = 'Assigned', int version = 2]) =>
    ParcelDetail.fromJson(
      object(decodeExactJson(encodeExactJson(privateRaw(status, version)))),
    );
Map<String, Object?> page(List<Object?> items) => {
  'items': items,
  'totalCount': items.length,
  'page': 1,
  'pageSize': 20,
};
ApiReply reply(Object? body, [int status = 200]) =>
    ApiReply(status, encodeExactJson(body));

class FakeTransport implements RequestTransport, MultipartRequestTransport {
  final calls =
      <
        ({
          String method,
          String path,
          String? body,
          Map<String, String> headers,
        })
      >[];
  String status = 'Assigned';
  int version = 2;
  Future<ApiReply> Function()? write;
  List<UploadPart>? files;
  Map<String, String>? fields;
  @override
  Future<ApiReply> send(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    calls.add((method: method, path: path, body: body, headers: headers));
    if (method != 'GET') {
      return write == null ? reply(raw('PickedUp', 3)) : await write!();
    }
    if (path.contains('/parcels/')) return reply(privateRaw(status, version));
    if (path.contains('/history')) return reply(page([raw('Failed', 3)]));
    return reply(page([privateRaw(status, version)]));
  }

  @override
  Future<ApiReply> sendMultipart(
    String path,
    Map<String, String> fields,
    List<UploadPart> files, {
    Map<String, String> headers = const {},
    void Function(int, int)? onProgress,
  }) async {
    this.files = files;
    this.fields = fields;
    calls.add((method: 'POST', path: path, body: null, headers: headers));
    onProgress?.call(100, 100);
    return write == null ? reply(raw('Delivered', 6)) : await write!();
  }
}

class Capture implements ProofCapture {
  @override
  Future<UploadPart?> pick({required bool camera}) async => UploadPart(
    'photo',
    'image/png',
    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  );
  @override
  Future<void> discardLost() async {}
}

ValueNotifier<AppSession> sessions() => ValueNotifier(
  const AppSession(principalId: 'courier-test', roles: ['Courier']),
);
void main() {
  testWidgets('drawn signature exports a PNG and completes without a photo', (
    tester,
  ) async {
    final port = FakeTransport()
      ..status = 'OutForDelivery'
      ..version = 5;
    final s = sessions();
    final c = CourierController(sessions: s, api: CourierApi(port));
    // One host session owns this screen throughout signature capture.
    addTearDown(c.dispose);
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CourierDetailScreen(
          controller: c,
          id: parcelId,
          capture: Capture(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pad = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Draw recipient signature',
    );
    await tester.ensureVisible(pad);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(pad));
    await gesture.moveBy(const Offset(25, 0));
    await gesture.moveBy(const Offset(25, 10));
    await gesture.moveBy(const Offset(25, 10));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use signature'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Use signature'));
      // PNG encoding completes on the engine's real asynchronous queue.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Signature selected.'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'Recipient name'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Recipient name'),
      'Recipient',
    );
    await tester.ensureVisible(find.text('Submit proof and complete delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit proof and complete delivery'));
    await tester.pumpAndSettle();
    expect(port.files!.single.field, 'signature');
    expect(imageMime(port.files!.single.bytes), 'image/png');
    expect(c.receipt!.status, 'Delivered');
    await tester.pumpWidget(const SizedBox());
  });
  group('Courier contract', () {
    test('uses canonical read routes and exact versions/prices', () async {
      final port = FakeTransport(), api = CourierApi(FakeTransport());
      expect(
        (await api.manifest(
          date: '2026-10-29',
          includeOverdue: false,
          page: 2,
        )).items.single.parcel.summary.version.plain,
        '2',
      );
      await CourierApi(port).history();
      await CourierApi(port).detail(parcelId);
      expect(
        port.calls[0].path,
        '/api/v1/couriers/me/history?page=1&pageSize=20',
      );
      expect(port.calls[1].path, '/api/v1/parcels/$parcelId');
      final d = ParcelSummary.fromJson(
        object(
          decodeExactJson(
            encodeExactJson(raw())
                .replaceFirst('"version":2', '"version":9007199254740993')
                .replaceFirst('"total":540', '"total":9999999999999999.99'),
          ),
        ),
      );
      expect(d.version.plain, '9007199254740993');
      expect(d.total.moneyDisplay, '9999999999999999.99');
    });
    for (final e in nextStages.entries) {
      test('${e.key} advances only to ${e.value} with note', () {
        final a = CourierApi.statusAttempt(
          detail(e.key),
          e.value,
          ' Collected ',
          'key',
        );
        expect(a.body, contains('"notes":"Collected"'));
        expect(a.body, contains('"expectedVersion":2'));
      });
    }
    for (final status in ['Created', 'Delivered', 'Failed', 'Cancelled']) {
      test('$status has no actions', () {
        expect(
          () => CourierApi.statusAttempt(
            detail(status),
            'Failed',
            '',
            'key',
            failureReason: 'Other',
          ),
          throwsA(isA<CourierException>()),
        );
      });
    }
    test(
      'rejects skipped stage, blank note, excessive note and direct Delivered',
      () {
        for (final e in [
          ('InTransit', 'note'),
          ('PickedUp', ' '),
          ('PickedUp', 'x' * 501),
          ('Delivered', 'note'),
        ]) {
          expect(
            () => CourierApi.statusAttempt(detail(), e.$1, e.$2, 'key'),
            throwsA(isA<CourierException>()),
          );
        }
      },
    );
    test('failure requires explicit reason and retains notes', () {
      expect(
        () => CourierApi.statusAttempt(detail(), 'Failed', '', 'key'),
        throwsA(isA<CourierException>()),
      );
      expect(
        CourierApi.statusAttempt(
          detail(),
          'Failed',
          'Door closed',
          'key',
          failureReason: 'RecipientUnavailable',
        ).body,
        contains('"failureReason":"RecipientUnavailable"'),
      );
    });
    for (final kind in ['photo', 'signature', 'both']) {
      test('$kind proof uses multipart and backend receipt', () async {
        final port = FakeTransport();
        final file = UploadPart(
          'photo',
          'image/png',
          Uint8List.fromList([1, 2, 3]),
        );
        final a = CourierApi.proofAttempt(
          detail('OutForDelivery', 5),
          ' Recipient ',
          'key',
          photo: kind != 'signature' ? file : null,
          signature: kind != 'photo'
              ? UploadPart('signature', 'image/png', file.bytes)
              : null,
        );
        final r = await CourierApi(port).submit(a);
        expect(r.status, 'Delivered');
        expect(port.fields, {
          'expectedVersion': '5',
          'recipientName': 'Recipient',
        });
        expect(port.files!.length, kind == 'both' ? 2 : 1);
        expect(port.calls.single.headers, {'Idempotency-Key': 'key'});
      });
    }
    test('missing proof, blank recipient, wrong state and unsupported file are rejected', () {
      final f = UploadPart('photo', 'text/plain', Uint8List.fromList([1]));
      expect(
        () => CourierApi.proofAttempt(
          detail('OutForDelivery'),
          'Recipient',
          'key',
        ),
        throwsA(isA<CourierException>()),
      );
      expect(
        () => CourierApi.proofAttempt(
          detail('OutForDelivery'),
          ' ',
          'key',
          photo: f,
        ),
        throwsA(isA<CourierException>()),
      );
      expect(
        () => CourierApi.proofAttempt(detail(), 'Recipient', 'key', photo: f),
        throwsA(isA<CourierException>()),
      );
      expect(
        () => CourierApi.proofAttempt(
          detail('OutForDelivery'),
          'Recipient',
          'key',
          photo: f,
        ),
        throwsA(isA<CourierException>()),
      );
    });
    test('photo bytes are copied and immutable', () {
      final source = Uint8List.fromList([1]);
      final p = UploadPart('photo', 'image/png', source);
      source[0] = 2;
      expect(p.bytes[0], 1);
      expect(() => p.bytes[0] = 3, throwsUnsupportedError);
    });
    test('transport sends valid multipart through the existing client, with progress', () async {
      var sent = 0, total = 0;
      final transport = HttpRequestTransport(
        Uri.parse('https://delivery.example.test'),
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/deliveries/$parcelId/pod');
          expect(
            r.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          expect(r.body, contains('name="expectedVersion"'));
          expect(r.body, contains('name="signature"'));
          expect(r.headers['Idempotency-Key'], 'original');
          return http.Response('{}', 200);
        }),
      );
      await transport.sendMultipart(
        '/api/v1/deliveries/$parcelId/pod',
        {'expectedVersion': '5', 'recipientName': 'Recipient'},
        [
          UploadPart('signature', 'image/png', Uint8List.fromList([1, 2])),
        ],
        headers: {'Idempotency-Key': 'original'},
        onProgress: (s, t) {
          sent = s;
          total = t;
        },
      );
      expect(sent, total);
      expect(total, greaterThan(0));
      transport.close();
    });
    test('capture recognizes JPEG/PNG and rejects unsupported bytes', () {
      expect(imageMime(Uint8List.fromList([255, 216, 255])), 'image/jpeg');
      expect(
        imageMime(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
        'image/png',
      );
      expect(() => imageMime(Uint8List.fromList([1])), throwsFormatException);
    });
  });
  group('Courier concurrency and privacy', () {
    for (final code in [201, 202]) {
      test(
        'unconfirmed HTTP $code retains the original request for explicit retry',
        () async {
          final port = FakeTransport(), s = sessions();
          var now = DateTime(2026);
          final c = CourierController(
            sessions: s,
            api: CourierApi(port),
            now: () => now,
          );
          addTearDown(c.dispose);
          addTearDown(s.dispose);
          await c.loadDetail(parcelId);
          port.write = () async => reply(raw('PickedUp', 3), code);
          await c.status('PickedUp', 'Collected');
          expect(c.pending, isNotNull);
          expect(c.receipt, isNull);
          final original = c.pending;
          await c.status('Failed', '', reason: 'Other');
          expect(identical(c.pending, original), true);
          port.write = () async => reply(raw('PickedUp', 3));
          port.status = 'PickedUp';
          port.version = 3;
          now = now.add(const Duration(seconds: 1));
          await c.retry();
          final writes = port.calls.where((r) => r.method == 'PUT').toList();
          expect(writes.length, 2);
          expect(writes[0].body, writes[1].body);
          expect(writes[0].headers, writes[1].headers);
          expect(c.receipt!.status, 'PickedUp');
          expect(c.pending, isNull);
        },
      );
    }
    test(
      'uncertain write retries identical payload/key and prevents new action',
      () async {
        final port = FakeTransport(), s = sessions();
        var time = DateTime(2026);
        final c = CourierController(
          sessions: s,
          api: CourierApi(port),
          now: () => time,
        );
        addTearDown(c.dispose);
        addTearDown(s.dispose);
        await c.loadDetail(parcelId);
        port.write = () async => throw Exception('offline');
        await c.status('PickedUp', 'Collected');
        final original = c.pending;
        expect(original, isNotNull);
        await c.status('Failed', '', reason: 'Other');
        expect(identical(c.pending, original), true);
        port.write = () async => reply(raw('PickedUp', 3));
        port.status = 'PickedUp';
        port.version = 3;
        time = time.add(const Duration(seconds: 1));
        await c.retry();
        final calls = port.calls.where((r) => r.method == 'PUT').toList();
        expect(calls.length, 2);
        expect(calls[0].body, calls[1].body);
        expect(calls[0].headers, calls[1].headers);
        expect(c.pending, isNull);
        expect(c.receipt!.status, 'PickedUp');
      },
    );
    for (final code in ['stale_version', 'invalid_transition']) {
      test('$code reloads state and requires new action', () async {
        final port = FakeTransport(), s = sessions();
        final c = CourierController(sessions: s, api: CourierApi(port));
        addTearDown(c.dispose);
        addTearDown(s.dispose);
        await c.loadDetail(parcelId);
        port.write = () async => reply({'code': code, 'detail': 'SECRET'}, 409);
        port.status = 'PickedUp';
        port.version = 3;
        await c.status('PickedUp', 'Collected');
        expect(c.pending, isNull);
        expect(c.detail!.summary.version.plain, '3');
        expect(c.notice, contains('choose a new action'));
        expect(c.notice, isNot(contains('SECRET')));
        await c.retry();
        expect(port.calls.where((r) => r.method == 'PUT').length, 1);
      });
    }
    test('proof upload reaching 100% does not confirm delivery until server response', () async {
      final port = FakeTransport()
        ..status = 'OutForDelivery'
        ..version = 5;
      final s = sessions();
      final c = CourierController(sessions: s, api: CourierApi(port));
      addTearDown(c.dispose);
      addTearDown(s.dispose);
      await c.loadDetail(parcelId);
      final completion = Completer<ApiReply>();
      port.write = () => completion.future;
      final future = c.proof(
        'Recipient',
        photo: UploadPart('photo', 'image/png', Uint8List.fromList([1])),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.uploadProgress, 1);
      expect(c.receipt, isNull);
      expect(c.busy, true);
      completion.complete(reply(raw('Delivered', 6)));
      await future;
      expect(c.receipt!.status, 'Delivered');
      expect(c.pending, isNull);
      expect(c.detail, isNull);
    });
    test(
      'session switch clears private state and ignores late completion',
      () async {
        final port = FakeTransport(), s = sessions();
        final c = CourierController(sessions: s, api: CourierApi(port));
        addTearDown(c.dispose);
        addTearDown(s.dispose);
        await c.loadDetail(parcelId);
        final completion = Completer<ApiReply>();
        port.write = () => completion.future;
        final future = c.status('PickedUp', 'Collected');
        s.value = const AppSession.signedOut();
        expect(c.detail, isNull);
        expect(c.pending, isNull);
        completion.complete(reply(raw('PickedUp', 3)));
        await future;
        expect(c.receipt, isNull);
        expect(c.manifest, isNull);
      },
    );
    test('wrong role never makes an API call', () async {
      final port = FakeTransport(),
          s = ValueNotifier(
            const AppSession(principalId: 'customer-test', roles: ['Customer']),
          );
      final c = CourierController(sessions: s, api: CourierApi(port));
      addTearDown(c.dispose);
      addTearDown(s.dispose);
      await c.loadManifest();
      await c.loadDetail(parcelId);
      expect(port.calls, isEmpty);
    });
    for (final status in [401, 403, 404]) {
      test(
        '$status hides private detail and does not retry mutation',
        () async {
          final port = FakeTransport(), s = sessions();
          final c = CourierController(sessions: s, api: CourierApi(port));
          addTearDown(c.dispose);
          addTearDown(s.dispose);
          await c.loadDetail(parcelId);
          port.write = () async => reply(<String, Object?>{}, status);
          await c.status('PickedUp', 'Collected');
          expect(c.detail, isNull);
          expect(c.pending, isNull);
          expect(c.blocked, status != 404);
          await c.retry();
          expect(port.calls.where((r) => r.method == 'PUT').length, 1);
        },
      );
    }
  });
  testWidgets(
    'manifest, details, note validation and terminal summary history render',
    (tester) async {
      final port = FakeTransport(), s = sessions();
      final c = CourierController(sessions: s, api: CourierApi(port));
      addTearDown(c.dispose);
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CourierScreen(controller: c, capture: Capture()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SD-TEST'), findsOneWidget);
      await tester.tap(find.text('SD-TEST'));
      await tester.pumpAndSettle();
      expect(find.text('Pickup street\nColombo 00100'), findsOneWidget);
      expect(find.text('Mark PickedUp'), findsOneWidget);
      expect(find.text('Submit proof and complete delivery'), findsNothing);
      await tester.ensureVisible(find.text('Mark PickedUp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark PickedUp'));
      await tester.pumpAndSettle();
      expect(c.pending, isNull);
      expect(c.notice, contains('Check the required'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delivery history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Failed · LKR'), findsOneWidget);
      expect(find.textContaining('Private recipient details'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'OutForDelivery captures photo, rejects missing recipient/proof, and waits for confirmation',
    (tester) async {
      final port = FakeTransport()
        ..status = 'OutForDelivery'
        ..version = 5;
      final s = sessions();
      final c = CourierController(sessions: s, api: CourierApi(port));
      addTearDown(c.dispose);
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CourierDetailScreen(
            controller: c,
            id: parcelId,
            capture: Capture(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Submit proof and complete delivery'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit proof and complete delivery'));
      await tester.pumpAndSettle();
      expect(c.notice, contains('Check the required'));
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Recipient name'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Recipient name'),
        'Recipient',
      );
      await tester.ensureVisible(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Photo selected'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Submit proof and complete delivery'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit proof and complete delivery'));
      await tester.pumpAndSettle();
      expect(c.receipt!.status, 'Delivered');
      expect(c.pending, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
