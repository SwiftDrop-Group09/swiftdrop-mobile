import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/customer_session.dart';
import 'package:swiftdrop_mobile/features/customer/booking/domain/booking_models.dart';
import 'package:swiftdrop_mobile/features/customer/booking/presentation/booking_controller.dart';

import 'booking_fixtures.dart';

void main() {
  late Scenario scenario;
  setUp(() => scenario = Scenario());
  tearDown(() => scenario.dispose());

  test('preview and declined confirmation never create a parcel', () async {
    await scenario.preview();
    expect(scenario.controller.stage, BookingStage.preview);
    expect(scenario.controller.quote!.total.moneyDisplay, '540.00');
    scenario.controller.decline();
    expect(scenario.controller.quote, isNull);
    expect(scenario.transport.requests.map((r) => r.path), ['/api/v1/quotes']);
  });
  test('invalid input does not call estimate or book', () async {
    await scenario.controller.loadZones();
    await scenario.controller.estimate(draft(weight: '0'));
    expect(scenario.transport.requests, isEmpty);
    expect(
      scenario.controller.fieldErrors,
      contains('packageDetails.weightKg'),
    );
  });
  test('explicit confirm posts the exact amount and shows server tracking only after 201', () async {
    await scenario.preview(total: '90071992547409.93');
    final pending = scenario.transport.defer();
    final first = scenario.controller.confirm();
    final duplicate = scenario.controller.confirm();
    expect(scenario.controller.stage, BookingStage.confirming);
    expect(scenario.controller.receipt, isNull);
    expect(scenario.transport.requests.length, 2);
    expect(
      scenario.transport.requests.last.body,
      '{"quoteId":"$quoteId","acceptTotal":90071992547409.93}',
    );
    pending.complete(ApiReply(201, receiptJson(total: '90071992547409.93')));
    await Future.wait([first, duplicate]);
    expect(scenario.controller.stage, BookingStage.success);
    expect(
      scenario.controller.receipt!.trackingNumber,
      'TRK-server-returned-test-code',
    );
    expect(scenario.keys, 1);
  });
  test(
    'lost response retries immutable body/key even after local quote expiry',
    () async {
      await scenario.preview();
      scenario.transport.fail();
      await scenario.controller.confirm();
      final original = scenario.transport.requests.last;
      scenario.controller.inputChanged();
      scenario.controller.decline();
      scenario.time = now.add(const Duration(minutes: 11));
      scenario.transport.reply(ApiReply(201, receiptJson()));
      await scenario.controller.confirm();
      final replay = scenario.transport.requests.last;
      expect(replay.body, original.body);
      expect(
        replay.headers['Idempotency-Key'],
        original.headers['Idempotency-Key'],
      );
      expect(scenario.keys, 1);
      expect(scenario.controller.stage, BookingStage.success);
    },
  );
  test('503 and unreadable 201 keep an uncertain attempt instead of showing success', () async {
    await scenario.preview();
    scenario.transport.reply(problem(503, 'delivery_unavailable'));
    await scenario.controller.confirm();
    final key = scenario.controller.attempt!.key;
    scenario.transport.reply(
      const ApiReply(201, '{"private":"invalid response"}'),
    );
    await scenario.controller.confirm();
    expect(scenario.controller.stage, BookingStage.uncertain);
    expect(scenario.controller.receipt, isNull);
    expect(scenario.controller.attempt!.key, key);
  });
  test('Retry-After is respected before same-key recovery', () async {
    await scenario.preview();
    scenario.transport.reply(
      problem(409, 'operation_in_progress', headers: {'retry-after': '3'}),
    );
    await scenario.controller.confirm();
    final original = scenario.controller.attempt!;
    expect(scenario.controller.canRetry, isFalse);
    await scenario.controller.confirm();
    expect(scenario.transport.requests.length, 2);
    scenario.time = now.add(const Duration(seconds: 3));
    scenario.transport.reply(ApiReply(201, receiptJson()));
    await scenario.controller.confirm();
    expect(scenario.transport.requests.last.body, original.body);
    expect(
      scenario.transport.requests.last.headers['Idempotency-Key'],
      original.key,
    );
  });
  for (final code in ['quote_expired', 'price_mismatch']) {
    test('$code requires a fresh quote and explicit new acceptance', () async {
      await scenario.preview();
      scenario.transport.reply(problem(409, code));
      await scenario.controller.confirm();
      expect(scenario.controller.quote, isNull);
      expect(scenario.controller.attempt, isNull);
      expect(scenario.controller.stage, BookingStage.editing);
      await scenario.controller.confirm();
      expect(scenario.transport.requests.length, 2);
      scenario.transport.reply(ApiReply(200, quoteJson(total: '600')));
      await scenario.controller.estimate(draft());
      expect(scenario.transport.requests.length, 3);
      expect(scenario.controller.quote!.total.moneyDisplay, '600.00');
    });
  }
  test('unsubmitted local expiry does not send a confirmation', () async {
    await scenario.preview();
    scenario.time = now.add(const Duration(minutes: 10));
    await scenario.controller.confirm();
    expect(scenario.transport.requests.length, 1);
    expect(scenario.controller.attempt, isNull);
    expect(scenario.controller.quote, isNull);
  });
  for (final status in [0, 408, 429]) {
    test(
      'ambiguous transport status $status retains the original confirmation',
      () async {
        await scenario.preview();
        scenario.transport.reply(problem(status, 'request_failed'));
        await scenario.controller.confirm();
        expect(scenario.controller.stage, BookingStage.uncertain);
        expect(scenario.controller.attempt!.key, 'key-1');
        expect(scenario.controller.receipt, isNull);
      },
    );
  }
  test(
    'safe server validation fields are mapped without rendering private bodies',
    () async {
      await scenario.controller.loadZones();
      scenario.transport.reply(
        const ApiReply(
          400,
          '{"code":"validation","errors":{"recipient.name":["Enter the recipient name."],"privateField":["private secret value"]}}',
        ),
      );
      await scenario.controller.estimate(draft());
      expect(scenario.controller.fieldErrors, {
        'recipient.name': 'Enter the recipient name.',
      });
      expect(scenario.controller.error, isNot(contains('private secret')));
    },
  );
  test('an unexpected committed price remains uncertain until the original replay is valid', () async {
    await scenario.preview();
    scenario.transport.reply(ApiReply(201, receiptJson(total: '541')));
    await scenario.controller.confirm();
    expect(scenario.controller.stage, BookingStage.uncertain);
    expect(scenario.controller.receipt, isNull);
    final attempt = scenario.controller.attempt!;
    scenario.transport.reply(ApiReply(201, receiptJson()));
    await scenario.controller.confirm();
    expect(scenario.transport.requests.last.body, attempt.body);
    expect(scenario.controller.stage, BookingStage.success);
  });
  for (final code in [
    'idempotency_conflict',
    'key_expired',
    'quote_consumed',
    'quote_conflict',
  ]) {
    test('$code blocks a new automatic key or attempt', () async {
      await scenario.preview();
      scenario.transport.reply(problem(409, code));
      await scenario.controller.confirm();
      final key = scenario.controller.attempt!.key;
      await scenario.controller.confirm();
      await scenario.controller.estimate(draft());
      expect(scenario.controller.stage, BookingStage.blocked);
      expect(scenario.controller.attempt!.key, key);
      expect(scenario.transport.requests.length, 2);
    });
  }
  test('stale estimate is ignored after input edit', () async {
    await scenario.controller.loadZones();
    final pending = scenario.transport.defer();
    final request = scenario.controller.estimate(draft());
    scenario.controller.inputChanged();
    pending.complete(ApiReply(200, quoteJson()));
    await request;
    expect(scenario.controller.quote, isNull);
    expect(scenario.controller.stage, BookingStage.editing);
  });
  test(
    'zone loading survives draft edits and clears its loading state',
    () async {
      scenario.dispose();
      final pending = Completer<List<BookingZone>>();
      scenario = Scenario(catalog: TestCatalog(pending: pending));
      final load = scenario.controller.loadZones();
      scenario.controller.inputChanged();
      pending.complete(zones);
      await load;
      expect(scenario.controller.zones, zones);
      expect(scenario.controller.zonesLoading, isFalse);
    },
  );
  test(
    'stale zone results and confirmation do not leak across principal changes',
    () async {
      await scenario.preview();
      final pending = scenario.transport.defer();
      final confirmation = scenario.controller.confirm();
      scenario.sessions.value = const CustomerSession(
        principalId: otherOwnerId,
        roles: ['Customer'],
      );
      pending.complete(ApiReply(201, receiptJson()));
      await confirmation;
      expect(scenario.controller.receipt, isNull);
      expect(scenario.controller.attempt, isNull);
      expect(scenario.controller.quote, isNull);
      expect(scenario.controller.zones, isEmpty);
    },
  );
  test('pending zone load cannot repopulate a signed-out session', () async {
    scenario.dispose();
    final pending = Completer<List<BookingZone>>();
    scenario = Scenario(catalog: TestCatalog(pending: pending));
    final load = scenario.controller.loadZones();
    scenario.sessions.value = const CustomerSession.signedOut();
    pending.complete(zones);
    await load;
    expect(scenario.controller.zones, isEmpty);
    expect(scenario.controller.zonesLoading, isFalse);
  });
  test('same-owner token refresh keeps the pending attempt', () async {
    await scenario.preview();
    scenario.transport.fail();
    await scenario.controller.confirm();
    final attempt = scenario.controller.attempt;
    scenario.sessions.value = const CustomerSession(
      principalId: ownerId,
      roles: ['Customer'],
    );
    expect(scenario.controller.attempt, same(attempt));
  });
  for (final code in [
    'unsupported_zone',
    'pricing_unavailable',
    'validation',
    'unauthorized',
    'forbidden',
  ]) {
    test(
      'estimate safely handles $code without booking side effects',
      () async {
        await scenario.controller.loadZones();
        scenario.transport.reply(problem(422, code));
        await scenario.controller.estimate(draft());
        expect(scenario.controller.error, isNotNull);
        expect(scenario.controller.quote, isNull);
        expect(scenario.controller.attempt, isNull);
        expect(scenario.transport.requests.single.path, '/api/v1/quotes');
      },
    );
  }
}
