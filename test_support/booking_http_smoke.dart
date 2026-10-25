import 'dart:io';
import 'dart:math';

import 'package:swiftdrop_mobile/core/network/exact_json.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/features/customer/booking/data/booking_api.dart';
import 'package:swiftdrop_mobile/features/customer/booking/domain/booking_models.dart';

import 'fixture_context.dart';

Future<void> main(List<String> arguments) async {
  final base = fixtureBaseUri(
    arguments.isEmpty ? 'http://127.0.0.1:5088' : arguments.single,
    pageUri: Uri.base,
  );
  final transport = HttpRequestTransport(base);
  try {
    final context = await FixtureContext.fetch(transport);
    if (!context.session.canBook || context.zones.isEmpty) {
      throw StateError('A Customer fixture with service zones is required.');
    }
    final api = BookingApi(transport);
    final pickup = context.zones.first.id;
    final delivery = context.zones.last.id;
    final draft = BookingDraft(
      pickup: BookingAddress(
        street: 'Fictional smoke pickup',
        city: 'Test city',
        postalCode: '00000',
        zoneId: pickup,
      ),
      delivery: BookingAddress(
        street: 'Fictional smoke delivery',
        city: 'Test city',
        postalCode: '00000',
        zoneId: delivery,
      ),
      recipientName: 'Fictional Smoke Recipient',
      recipientPhone: '0000000000',
      weight: '2.5',
      size: 'Small',
    );
    final quote = await api.estimate(draft);
    final body = encodeExactJson({
      'quoteId': quote.id,
      'acceptTotal': quote.total,
    });
    final random = Random.secure();
    final key =
        'flutter-smoke-${List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join()}';
    final first = await api.confirm(body, key);
    final replay = await api.confirm(body, key);
    if (first.id != replay.id ||
        first.trackingNumber != replay.trackingNumber ||
        first.total.compareTo(quote.total) != 0 ||
        replay.total.compareTo(first.total) != 0) {
      throw StateError('The committed response or replay differed.');
    }
    stdout.writeln(
      'PASS: Flutter HTTP adapter estimated, confirmed and replayed one server-issued booking.',
    );
  } finally {
    transport.close();
  }
}
