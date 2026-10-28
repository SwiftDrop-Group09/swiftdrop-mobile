import '../../core/network/exact_json.dart';
import '../../core/network/request_transport.dart';

const courierStates = [
  'Created',
  'Assigned',
  'PickedUp',
  'InTransit',
  'OutForDelivery',
  'Delivered',
  'Failed',
  'Cancelled',
];
const failureReasons = [
  'RecipientUnavailable',
  'AddressUnreachable',
  'Damaged',
  'Other',
];
const nextStages = {
  'Assigned': 'PickedUp',
  'PickedUp': 'InTransit',
  'InTransit': 'OutForDelivery',
};
Map<String, Object?> object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid response.');
  }
  return value;
}

String text(Map<String, Object?> map, String key) {
  final v = map[key];
  if (v is! String) throw const FormatException('Invalid response.');
  return v;
}

String identifier(Map<String, Object?> map, String key) {
  final s = text(map, key);
  if (!RegExp(r'^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$')
      .hasMatch(s)) {
    throw const FormatException('Invalid identifier.');
  }
  return s;
}

ExactNumber number(Map<String, Object?> map, String key) {
  final v = map[key];
  if (v is! ExactNumber) throw const FormatException('Invalid number.');
  return v;
}

int integer(Map<String, Object?> map, String key) {
  final v = number(map, key);
  if (!v.isInteger) throw const FormatException('Invalid integer.');
  return int.parse(v.plain);
}

String state(Map<String, Object?> map, String key) {
  final s = text(map, key);
  if (!courierStates.contains(s)) throw const FormatException('Invalid state.');
  return s;
}

final class ParcelSummary {
  ParcelSummary.fromJson(Map<String, Object?> json)
    : id = identifier(json, 'id'),
      trackingNumber = text(json, 'trackingNumber'),
      status = state(json, 'status'),
      version = number(json, 'version'),
      createdAt = DateTime.parse(text(json, 'createdAt')),
      total = number(object(json['priceSnapshot']), 'total'),
      currency = text(object(json['priceSnapshot']), 'currency'),
      pricingVersion = text(object(json['priceSnapshot']), 'pricingVersion') {
    if (!version.isInteger ||
        BigInt.parse(version.plain) < BigInt.one ||
        BigInt.parse(version.plain) > BigInt.parse('9223372036854775807') ||
        !total.isMoney ||
        currency != 'LKR') {
      throw const FormatException('Invalid summary.');
    }
  }
  final String id, trackingNumber, status, currency, pricingVersion;
  final ExactNumber version, total;
  final DateTime createdAt;
  bool get active => const [
    'Assigned',
    'PickedUp',
    'InTransit',
    'OutForDelivery',
  ].contains(status);
}

final class CourierAddress {
  CourierAddress.fromJson(Map<String, Object?> json)
    : street = text(json, 'street'),
      city = text(json, 'city'),
      postalCode = text(json, 'postalCode'),
      zoneId = identifier(json, 'zoneId');
  final String street, city, postalCode, zoneId;
  String get display => '$street\n$city $postalCode';
}

final class ParcelPrivate {
  ParcelPrivate.fromJson(Map<String, Object?> json)
    : summary = ParcelSummary.fromJson(json),
      pickup = CourierAddress.fromJson(object(json['pickupAddress'])),
      delivery = CourierAddress.fromJson(object(json['deliveryAddress'])),
      recipientName = text(object(json['recipient']), 'name'),
      phone = text(object(json['recipient']), 'phoneNumber'),
      weight = number(object(json['packageDetails']), 'weightKg'),
      size = text(object(json['packageDetails']), 'size');
  final ParcelSummary summary;
  final CourierAddress pickup, delivery;
  final String recipientName, phone, size;
  final ExactNumber weight;
}

final class AssignedParcel {
  AssignedParcel.fromJson(Map<String, Object?> json)
    : parcel = ParcelPrivate.fromJson(json),
      serviceDate = text(json, 'serviceDate'),
      isOverdue = json['isOverdue'] as bool;
  final ParcelPrivate parcel;
  final String serviceDate;
  final bool isOverdue;
}

final class HistoryEntry {
  HistoryEntry.fromJson(Map<String, Object?> json)
    : from = json['fromStatus'] as String?,
      to = state(json, 'toStatus'),
      reason = json['changeReason'] as String?,
      note = json['deliveryNote'] as String?,
      timestamp = DateTime.parse(text(json, 'timestamp'));
  final String? from, reason, note;
  final String to;
  final DateTime timestamp;
}

final class ParcelDetail {
  ParcelDetail.fromJson(Map<String, Object?> json)
    : parcel = ParcelPrivate.fromJson(json),
      serviceDate = json['assignment'] == null
          ? null
          : text(object(json['assignment']), 'serviceDate'),
      history = List.unmodifiable(
        (json['history'] as List).map((v) => HistoryEntry.fromJson(object(v))),
      );
  final ParcelPrivate parcel;
  final String? serviceDate;
  final List<HistoryEntry> history;
  ParcelSummary get summary => parcel.summary;
}

final class CourierPage<T> {
  CourierPage.fromJson(
    Map<String, Object?> json,
    T Function(Map<String, Object?>) decode,
  ) : items = List.unmodifiable(
        (json['items'] as List).map((v) => decode(object(v))),
      ),
      total = integer(json, 'totalCount'),
      page = integer(json, 'page'),
      pageSize = integer(json, 'pageSize') {
    if (total < 0 || page < 1 || pageSize < 1 || pageSize > 100) {
      throw const FormatException('Invalid page.');
    }
  }
  final List<T> items;
  final int total, page, pageSize;
}

final class CourierAttempt {
  const CourierAttempt({
    required this.id,
    required this.version,
    required this.status,
    required this.key,
    this.body,
    this.recipientName,
    this.photo,
    this.signature,
  });
  final String id, status, key;
  final ExactNumber version;
  final String? body, recipientName;
  final UploadPart? photo, signature;
}
