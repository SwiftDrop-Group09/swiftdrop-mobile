import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:swiftdrop_mobile/core/network/exact_json.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/features/customer/booking/data/booking_api.dart';

import '../../../../test_support/fixture_context.dart';
import 'booking_fixtures.dart';

void main() {
  test('portable HTTP adapter preserves path/body/key without deriving identity headers', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://127.0.0.1:5088/api/v1/parcels');
      expect(
        request.body,
        '{"quoteId":"$quoteId","acceptTotal":90071992547409.93}',
      );
      expect(request.headers['Idempotency-Key'], 'retained-attempt-key');
      expect(
        request.headers.keys.any(
          (key) => key.toLowerCase().startsWith('x-user'),
        ),
        isFalse,
      );
      return http.Response(receiptJson(total: '90071992547409.93'), 201);
    });
    final transport = HttpRequestTransport(
      Uri.parse('http://127.0.0.1:5088'),
      client: client,
    );
    final response = await BookingApi(transport).confirm(
      encodeExactJson({
        'quoteId': quoteId,
        'acceptTotal': ExactNumber('90071992547409.93'),
      }),
      'retained-attempt-key',
    );
    expect(response.total.moneyDisplay, '90071992547409.93');
    transport.close();
  });
  test('fixture context uses the server actor/roles/zones and rejects non-loopback targets', () async {
    final transport = ScriptedTransport()
      ..reply(
        const ApiReply(
          200,
          '{"actorId":"$ownerId","roles":["Customer"],"zones":[{"id":"$pickupId","name":"Test zone"}]}',
        ),
      );
    final context = await FixtureContext.fetch(transport);
    expect(context.session.principalId, ownerId);
    expect(context.session.canBook, isTrue);
    expect((await context.load()).single.id, pickupId);
    expect(
      fixtureBaseUri(
        '',
        pageUri: Uri.parse('http://localhost:5181/'),
      ).toString(),
      'http://localhost:5181/',
    );
    expect(
      () => fixtureBaseUri('https://api.example.invalid', pageUri: Uri.base),
      throwsArgumentError,
    );
  });
}
