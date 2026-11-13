import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop_mobile/core/session/app_session.dart';
import 'package:swiftdrop_mobile/core/session/identity_role.dart';

void main() {
  for (final role in IdentityRole.values) {
    test('one ${role.wireValue} role grants only its client workspace', () {
      final session = AppSession(principalId: 'actor', roles: [role.wireValue]);
      expect(session.role, role);
      expect(session.signedIn, isTrue);
      expect(session.canBook, role == IdentityRole.customer);
      expect(session.canCourier, role == IdentityRole.courier);
    });
  }
  test(
    'ambiguous, missing and unknown roles never grant session authority',
    () {
      for (final roles in <List<String>>[
        [],
        ['Customer', 'Courier'],
        ['Admin', 'Customer'],
        ['Unknown'],
      ]) {
        final session = AppSession(principalId: 'actor', roles: roles);
        expect(session.role, isNull);
        expect(session.signedIn, isFalse);
        expect(session.canBook, isFalse);
        expect(session.canCourier, isFalse);
      }
    },
  );
}
