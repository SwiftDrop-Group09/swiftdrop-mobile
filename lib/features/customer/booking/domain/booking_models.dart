import '../../../../core/network/exact_json.dart';

final class BookingZone {
  const BookingZone(this.id, this.name);
  final String id;
  final String name;
}

abstract interface class ZoneCatalog {
  Future<List<BookingZone>> load();
}

final class UnavailableZoneCatalog implements ZoneCatalog {
  const UnavailableZoneCatalog();
  @override
  Future<List<BookingZone>> load() =>
      Future.error(StateError('Address coverage is unavailable.'));
}

final class BookingAddress {
  const BookingAddress({
    required this.street,
    required this.city,
    required this.postalCode,
    required this.zoneId,
  });
  final String street;
  final String city;
  final String postalCode;
  final String zoneId;

  Map<String, Object?> toJson() => {
    'street': street.trim(),
    'city': city.trim(),
    'postalCode': postalCode.trim(),
    'zoneId': zoneId,
  };
}

final class BookingDraft {
  const BookingDraft({
    required this.pickup,
    required this.delivery,
    required this.recipientName,
    required this.recipientPhone,
    required this.weight,
    required this.size,
  });
  final BookingAddress pickup;
  final BookingAddress delivery;
  final String recipientName;
  final String recipientPhone;
  final String weight;
  final String size;

  Map<String, String> validate(List<BookingZone> zones) {
    final errors = <String, String>{};
    for (final entry in {'pickup': pickup, 'delivery': delivery}.entries) {
      for (final field in {
        'street': entry.value.street,
        'city': entry.value.city,
        'postalCode': entry.value.postalCode,
      }.entries) {
        final error = requiredText(field.value);
        if (error != null) errors['${entry.key}.${field.key}'] = error;
      }
      if (!zones.any((zone) => zone.id == entry.value.zoneId)) {
        errors['${entry.key}.zoneId'] = 'Choose an available service zone.';
      }
    }
    final nameError = requiredText(recipientName);
    final phoneError = requiredText(recipientPhone);
    if (nameError != null) errors['recipient.name'] = nameError;
    if (phoneError != null) errors['recipient.phoneNumber'] = phoneError;
    if (!(ExactNumber.tryParse(weight)?.isWeight ?? false)) {
      errors['packageDetails.weightKg'] =
          'Enter an exact weight greater than 0 and at most 30 kg.';
    }
    if (!const ['Small', 'Medium', 'Large'].contains(size)) {
      errors['packageDetails.size'] = 'Choose Small, Medium or Large.';
    }
    return errors;
  }

  String encode() => encodeExactJson({
    'pickupAddress': pickup.toJson(),
    'deliveryAddress': delivery.toJson(),
    'packageDetails': {'weightKg': ExactNumber(weight), 'size': size},
    'recipient': {
      'name': recipientName.trim(),
      'phoneNumber': recipientPhone.trim(),
    },
  });
}

String? requiredText(String? value) => value == null || value.trim().isEmpty
    ? 'This field is required.'
    : value.contains('\u0000')
    ? 'Remove the unsupported null character.'
    : null;

final class DeliveryQuote {
  const DeliveryQuote({
    required this.id,
    required this.total,
    required this.currency,
    required this.pricingVersion,
    required this.expiresAt,
    required this.fingerprint,
  });
  final String id;
  final ExactNumber total;
  final String currency;
  final String pricingVersion;
  final DateTime expiresAt;
  final String fingerprint;

  factory DeliveryQuote.fromJson(Map<String, Object?> json) => DeliveryQuote(
    id: uuid(json, 'quoteId'),
    total: money(json['total']),
    currency: text(json, 'currency'),
    pricingVersion: text(json, 'pricingVersion'),
    expiresAt: DateTime.parse(text(json, 'expiresAt')).toUtc(),
    fingerprint: text(json, 'fingerprint'),
  );
}

final class BookingReceipt {
  const BookingReceipt({
    required this.id,
    required this.trackingNumber,
    required this.status,
    required this.version,
    required this.total,
    required this.currency,
    required this.pricingVersion,
    required this.createdAt,
  });
  final String id;
  final String trackingNumber;
  final String status;
  final String version;
  final ExactNumber total;
  final String currency;
  final String pricingVersion;
  final DateTime createdAt;

  factory BookingReceipt.fromJson(Map<String, Object?> json) {
    final snapshot = jsonObject(json['priceSnapshot']);
    final version = json['version'];
    if (version is! ExactNumber ||
        !version.isInteger ||
        version.compareTo(ExactNumber('1')) != 0 ||
        text(json, 'status') != 'Created') {
      throw const FormatException('Invalid booking response.');
    }
    return BookingReceipt(
      id: uuid(json, 'id'),
      trackingNumber: text(json, 'trackingNumber'),
      status: text(json, 'status'),
      version: version.plain,
      total: money(snapshot['total']),
      currency: text(snapshot, 'currency'),
      pricingVersion: text(snapshot, 'pricingVersion'),
      createdAt: DateTime.parse(text(json, 'createdAt')).toUtc(),
    );
  }
}

Map<String, Object?> jsonObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

String text(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing response field.');
  }
  return value;
}

String uuid(Map<String, Object?> object, String key) {
  final value = text(object, key);
  if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) ||
      value == '00000000-0000-0000-0000-000000000000') {
    throw const FormatException('Invalid response identifier.');
  }
  return value;
}

ExactNumber money(Object? value) {
  if (value is! ExactNumber || !value.isMoney) {
    throw const FormatException('Invalid monetary response.');
  }
  return value;
}
