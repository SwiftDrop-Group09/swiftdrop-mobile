import 'dart:convert';
import 'dart:typed_data';

import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/features/courier/courier_api.dart';

import 'fixture_context.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> args) async {
  final transport = HttpRequestTransport(
    fixtureBaseUri(
      args.isEmpty ? 'http://127.0.0.1:5088' : args.single,
      pageUri: Uri.base,
    ),
  );
  try {
    final context = await FixtureContext.fetch(transport);
    check(context.session.canCourier, 'Courier fixture required.');
    final api = CourierApi(transport),
        prefix = DateTime.now().microsecondsSinceEpoch.toString();
    final assigned = (await api.manifest()).items.firstWhere(
      (p) => p.parcel.summary.status == 'Assigned',
    );
    var parcel = await api.detail(assigned.parcel.summary.id);
    final first = CourierApi.statusAttempt(
      parcel,
      'PickedUp',
      'TESTDATA collected',
      '$prefix-pickup',
    );
    check(
      (await api.submit(first)).status == 'PickedUp',
      'Pickup confirmation.',
    );
    check(
      (await api.submit(first)).version.plain == '3',
      'Exact original replay.',
    );
    parcel = await api.detail(parcel.summary.id);
    await api.submit(
      CourierApi.statusAttempt(
        parcel,
        'InTransit',
        'TESTDATA in transit',
        '$prefix-transit',
      ),
    );
    parcel = await api.detail(parcel.summary.id);
    await api.submit(
      CourierApi.statusAttempt(
        parcel,
        'OutForDelivery',
        'TESTDATA out for delivery',
        '$prefix-out',
      ),
    );
    parcel = await api.detail(parcel.summary.id);
    final bytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAYAAAD+Bd/7AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAhSURBVBhXY2BIYfiPF2MIoGMMAXSMIYCOMQTQMYYAGgYAgZVCkckcricAAAAASUVORK5CYII=',
      ),
    );
    final proof = CourierApi.proofAttempt(
      parcel,
      'TESTDATA Recipient',
      '$prefix-proof',
      signature: UploadPart('signature', 'image/png', bytes),
    );
    var sent = 0, total = 0;
    check(
      (await api.submit(
            proof,
            onProgress: (s, t) {
              sent = s;
              total = t;
            },
          )).status ==
          'Delivered',
      'Proof confirmation.',
    );
    check(sent == total && total > 0, 'Multipart progress.');
    check(
      (await api.submit(proof)).status == 'Delivered',
      'Proof exact replay.',
    );
    try {
      await api.detail(parcel.summary.id);
      throw StateError('Closed detail must be denied.');
    } on CourierException catch (e) {
      check(e.status == 404, 'Closed detail 404.');
    }
    final failed = (await api.manifest()).items.firstWhere(
      (p) => p.parcel.summary.status == 'OutForDelivery',
    );
    await api.submit(
      CourierApi.statusAttempt(
        await api.detail(failed.parcel.summary.id),
        'Failed',
        'TESTDATA damaged',
        '$prefix-failed',
        failureReason: 'Damaged',
      ),
    );
    final history = await api.history();
    check(
      history.items.any(
        (p) => p.id == parcel.summary.id && p.status == 'Delivered',
      ),
      'Delivered history.',
    );
    check(
      history.items.any(
        (p) => p.id == failed.parcel.summary.id && p.status == 'Failed',
      ),
      'Failed history.',
    );
    // ignore: avoid_print -- Explicit command-line fixture check, never production.
    print(
      'PASS Flutter production adapter: real PostgreSQL manifest/details, stages, exact replay, signature multipart/progress/completion, Failed reason, terminal privacy/history. TESTDATA fixture storage only.',
    );
  } finally {
    transport.close();
  }
}
