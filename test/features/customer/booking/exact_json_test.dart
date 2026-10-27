import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/network/exact_json.dart';
import 'package:swiftdrop_mobile/features/customer/booking/domain/booking_models.dart';

import 'booking_fixtures.dart';

void main() {
  test('large money survives decode and numeric serialization before double conversion', () {
    final value = decodeExactJson(
      '{"total":9999999999999999.99}',
    ) as Map<String, Object?>;
    final total = value['total']! as ExactNumber;
    expect(total.moneyDisplay, '9999999999999999.99');
    expect(
      encodeExactJson({'acceptTotal': total}),
      '{"acceptTotal":9999999999999999.99}',
    );
    expect(ExactNumber('90071992547409.93').moneyDisplay, '90071992547409.93');
  });
  test('nested numbers, strings, escapes and literals retain their types', () {
    final source =
        r'{"items":[1.25,"001.20",{"escaped":"say \"hello\" \\ world","ok":true,"none":null}]}';
    final decoded = decodeExactJson(source) as Map<String, Object?>;
    expect(encodeExactJson(decoded), source);
  });
  test('exponent representation compares exactly without floating point', () {
    expect(ExactNumber('5.400e2').compareTo(ExactNumber('540.00')), 0);
    expect(
      ExactNumber('2.5000833333333333333333333334').plain,
      '2.5000833333333333333333333334',
    );
    expect(ExactNumber('0.0001').isWeight, isTrue);
    expect(ExactNumber('30').isWeight, isTrue);
  });
  for (final source in [
    '{"x":01}',
    '{"x":1,}',
    '{"x":1,"x":2}',
    '[1,,2]',
    'true false',
    '"bad\ntext"',
    '1e1001',
  ]) {
    test('reject malformed/ambiguous numeric JSON: $source', () {
      expect(() => decodeExactJson(source), throwsFormatException);
    });
  }
  for (final weight in [
    '0',
    '-0.1',
    '30.0001',
    '0.00000000000000000000000000001',
    '2.50008333333333333333333333335',
  ]) {
    test('invalid weight is rejected without rounding: $weight', () {
      expect(
        draft(weight: weight).validate(zones),
        contains('packageDetails.weightKg'),
      );
    });
  }
  test('form requires every field, known zones, recipient and exact size', () {
    expect(draft().validate(zones), isEmpty);
    expect(
      draft(size: 'small', recipient: '  ').validate(zones).keys,
      containsAll(['packageDetails.size', 'recipient.name']),
    );
    expect(
      draft().validate([]).keys,
      containsAll(['pickup.zoneId', 'delivery.zoneId']),
    );
    expect(requiredText('Fictional\u0000name'), isNotNull);
  });
  test(
    'request schema contains only actual QuoteInput with exact numeric weight',
    () {
      final encoded = draft(weight: '2.5000833333333333333333333334').encode();
      final object = decodeExactJson(encoded) as Map<String, Object?>;
      expect(object.keys, [
        'pickupAddress',
        'deliveryAddress',
        'packageDetails',
        'recipient',
      ]);
      expect(encoded, contains('"weightKg":2.5000833333333333333333333334'));
      expect(encoded, isNot(contains('userId')));
    },
  );
  test(
    'receipt rejects numeric strings, missing tracking and noninitial version',
    () {
      expect(
        () => BookingReceipt.fromJson(
          jsonObject(decodeExactJson(receiptJson(total: '"540"'))),
        ),
        throwsFormatException,
      );
      expect(
        () => BookingReceipt.fromJson(
          jsonObject(decodeExactJson(receiptJson(version: '2'))),
        ),
        throwsFormatException,
      );
      expect(
        () => BookingReceipt.fromJson(
          jsonObject(decodeExactJson(receiptJson(tracking: ''))),
        ),
        throwsFormatException,
      );
    },
  );
}
