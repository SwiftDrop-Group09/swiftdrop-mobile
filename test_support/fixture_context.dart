import 'package:swiftdrop_mobile/core/network/exact_json.dart';
import 'package:swiftdrop_mobile/core/network/request_transport.dart';
import 'package:swiftdrop_mobile/core/session/customer_session.dart';
import 'package:swiftdrop_mobile/features/customer/booking/domain/booking_models.dart';

/// Fixture identities and catalogs are supplied only by the isolated test host.
final class FixtureContext implements ZoneCatalog {
  FixtureContext._(this.session, this.zones);
  final CustomerSession session;
  final List<BookingZone> zones;

  static Future<FixtureContext> fetch(RequestTransport transport) async {
    final response = await transport.send('GET', '/__test/booking-context');
    if (response.status != 200) {
      throw StateError('The isolated booking test host is unavailable.');
    }
    final value = jsonObject(decodeExactJson(response.body));
    final rawRoles = value['roles'];
    final rawZones = value['zones'];
    if (rawRoles is! List || rawZones is! List) {
      throw const FormatException('Invalid fixture context.');
    }
    final roles = rawRoles
        .map((role) {
          if (role is! String) {
            throw const FormatException('Invalid fixture role.');
          }
          return role;
        })
        .toList(growable: false);
    final zones = rawZones
        .map((zone) {
          final object = jsonObject(zone);
          return BookingZone(uuid(object, 'id'), text(object, 'name'));
        })
        .toList(growable: false);
    return FixtureContext._(
      CustomerSession(principalId: uuid(value, 'actorId'), roles: roles),
      List.unmodifiable(zones),
    );
  }

  @override
  Future<List<BookingZone>> load() async => zones;
}

Uri fixtureBaseUri(String configured, {required Uri pageUri}) {
  final base = configured.isEmpty
      ? (pageUri.scheme == 'http' || pageUri.scheme == 'https'
            ? pageUri.resolve('/')
            : Uri.parse('http://127.0.0.1:5088'))
      : Uri.parse(configured);
  if (!const ['http', 'https'].contains(base.scheme) ||
      !const ['localhost', '127.0.0.1', '::1'].contains(base.host) ||
      base.userInfo.isNotEmpty) {
    throw ArgumentError(
      'The fixture harness requires a loopback HTTP address.',
    );
  }
  return base;
}
