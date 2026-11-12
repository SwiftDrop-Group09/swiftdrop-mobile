import 'dart:convert';

String parcelStatusLabel(String status) => switch (status) {
  'Created' => 'Booked',
  'Assigned' => 'Assigned',
  'PickedUp' => 'Collected',
  'InTransit' => 'In transit',
  'OutForDelivery' => 'Out for delivery',
  'Delivered' => 'Delivered',
  'Failed' => 'Delivery unsuccessful',
  'Cancelled' => 'Cancelled',
  _ => status,
};

bool isTerminalParcelStatus(String status) =>
    status == 'Delivered' || status == 'Failed' || status == 'Cancelled';

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

final class TrackingAddress {
  const TrackingAddress({
    required this.street,
    required this.city,
    required this.postalCode,
    required this.zoneId,
  });

  final String street;
  final String city;
  final String postalCode;
  final String zoneId;

  factory TrackingAddress.fromJson(Map<String, Object?> json) =>
      TrackingAddress(
        street: (json['street'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        postalCode: (json['postalCode'] as String?) ?? '',
        zoneId: (json['zoneId'] as String?) ?? '',
      );
}

final class TrackingRecipient {
  const TrackingRecipient({required this.name, required this.phoneNumber});

  final String name;
  final String phoneNumber;

  factory TrackingRecipient.fromJson(Map<String, Object?> json) =>
      TrackingRecipient(
        name: (json['name'] as String?) ?? '',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
      );
}

final class TrackingPackageDetails {
  const TrackingPackageDetails({required this.weightKg, required this.size});

  final double weightKg;
  final String size;

  factory TrackingPackageDetails.fromJson(Map<String, Object?> json) =>
      TrackingPackageDetails(
        weightKg: _asDouble(json['weightKg']),
        size: (json['size'] as String?) ?? 'Small',
      );
}

final class TrackingPriceSnapshot {
  const TrackingPriceSnapshot({
    required this.total,
    required this.currency,
    required this.pricingVersion,
  });

  final double total;
  final String currency;
  final String pricingVersion;

  factory TrackingPriceSnapshot.fromJson(Map<String, Object?> json) =>
      TrackingPriceSnapshot(
        total: _asDouble(json['total']),
        currency: (json['currency'] as String?) ?? 'LKR',
        pricingVersion: (json['pricingVersion'] as String?) ?? '',
      );
}

final class CustomerParcelItem {
  const CustomerParcelItem({
    required this.id,
    required this.trackingNumber,
    required this.status,
    required this.version,
    required this.priceSnapshot,
    required this.createdAt,
    required this.updatedAt,
    required this.pickupCity,
    required this.deliveryCity,
    required this.recipientName,
    required this.packageDetails,
    required this.hasProof,
  });

  final String id;
  final String trackingNumber;
  final String status;
  final int version;
  final TrackingPriceSnapshot priceSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String pickupCity;
  final String deliveryCity;
  final String recipientName;
  final TrackingPackageDetails packageDetails;
  final bool hasProof;

  factory CustomerParcelItem.fromJson(Map<String, Object?> json) =>
      CustomerParcelItem(
        id: (json['id'] as String?) ?? '',
        trackingNumber: (json['trackingNumber'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'Created',
        version: _asInt(json['version']),
        priceSnapshot: TrackingPriceSnapshot.fromJson(
          (json['priceSnapshot'] as Map<String, Object?>?) ?? const {},
        ),
        createdAt:
            DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt:
            DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        pickupCity: (json['pickupCity'] as String?) ?? '',
        deliveryCity: (json['deliveryCity'] as String?) ?? '',
        recipientName: (json['recipientName'] as String?) ?? '',
        packageDetails: TrackingPackageDetails.fromJson(
          (json['packageDetails'] as Map<String, Object?>?) ?? const {},
        ),
        hasProof: (json['hasProof'] as bool?) ?? false,
      );
}

final class CustomerParcelPage {
  const CustomerParcelPage({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<CustomerParcelItem> items;
  final int totalCount;
  final int page;
  final int pageSize;

  factory CustomerParcelPage.fromJson(Map<String, Object?> json) {
    final rawItems = (json['items'] as List<Object?>?) ?? const [];
    return CustomerParcelPage(
      items: rawItems
          .whereType<Map<String, Object?>>()
          .map(CustomerParcelItem.fromJson)
          .toList(growable: false),
      totalCount: _asInt(json['totalCount']),
      page: _asInt(json['page']),
      pageSize: _asInt(json['pageSize']),
    );
  }
}

final class ParcelHistoryItem {
  const ParcelHistoryItem({
    required this.fromStatus,
    required this.toStatus,
    required this.changeReason,
    required this.timestamp,
  });

  final String? fromStatus;
  final String toStatus;
  final String? changeReason;
  final DateTime timestamp;

  factory ParcelHistoryItem.fromJson(Map<String, Object?> json) =>
      ParcelHistoryItem(
        fromStatus: json['fromStatus'] as String?,
        toStatus: (json['toStatus'] as String?) ?? 'Created',
        changeReason: json['changeReason'] as String?,
        timestamp:
            DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

final class ParcelDetailModel {
  const ParcelDetailModel({
    required this.id,
    required this.trackingNumber,
    required this.status,
    required this.version,
    required this.priceSnapshot,
    required this.createdAt,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.packageDetails,
    required this.recipient,
    required this.history,
  });

  final String id;
  final String trackingNumber;
  final String status;
  final int version;
  final TrackingPriceSnapshot priceSnapshot;
  final DateTime createdAt;
  final TrackingAddress pickupAddress;
  final TrackingAddress deliveryAddress;
  final TrackingPackageDetails packageDetails;
  final TrackingRecipient recipient;
  final List<ParcelHistoryItem> history;

  factory ParcelDetailModel.fromJson(Map<String, Object?> json) {
    final rawHistory = (json['history'] as List<Object?>?) ?? const [];
    return ParcelDetailModel(
      id: (json['id'] as String?) ?? '',
      trackingNumber: (json['trackingNumber'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'Created',
      version: _asInt(json['version']),
      priceSnapshot: TrackingPriceSnapshot.fromJson(
        (json['priceSnapshot'] as Map<String, Object?>?) ?? const {},
      ),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      pickupAddress: TrackingAddress.fromJson(
        (json['pickupAddress'] as Map<String, Object?>?) ?? const {},
      ),
      deliveryAddress: TrackingAddress.fromJson(
        (json['deliveryAddress'] as Map<String, Object?>?) ?? const {},
      ),
      packageDetails: TrackingPackageDetails.fromJson(
        (json['packageDetails'] as Map<String, Object?>?) ?? const {},
      ),
      recipient: TrackingRecipient.fromJson(
        (json['recipient'] as Map<String, Object?>?) ?? const {},
      ),
      history: rawHistory
          .whereType<Map<String, Object?>>()
          .map(ParcelHistoryItem.fromJson)
          .toList(growable: false),
    );
  }
}

final class ParcelReceiptModel {
  const ParcelReceiptModel({
    required this.receiptNumber,
    required this.parcelId,
    required this.trackingNumber,
    required this.status,
    required this.createdAt,
    required this.deliveredAt,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.recipient,
    required this.packageDetails,
    required this.baseFee,
    required this.weightFee,
    required this.total,
    required this.currency,
    required this.pricingVersion,
    required this.calculatedAt,
  });

  final String receiptNumber;
  final String parcelId;
  final String trackingNumber;
  final String status;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final TrackingAddress pickupAddress;
  final TrackingAddress deliveryAddress;
  final TrackingRecipient recipient;
  final TrackingPackageDetails packageDetails;
  final double baseFee;
  final double weightFee;
  final double total;
  final String currency;
  final String pricingVersion;
  final DateTime calculatedAt;

  String toShareableText() =>
      'SwiftDrop Official Receipt\n'
      'Receipt: $receiptNumber\n'
      'Tracking: $trackingNumber\n'
      'Recipient: ${recipient.name}\n'
      'Route: ${pickupAddress.city} -> ${deliveryAddress.city}\n'
      'Base Fee: $currency ${baseFee.toStringAsFixed(2)}\n'
      'Weight Fee: $currency ${weightFee.toStringAsFixed(2)}\n'
      'Total: $currency ${total.toStringAsFixed(2)}\n';

  factory ParcelReceiptModel.fromJson(Map<String, Object?> json) =>
      ParcelReceiptModel(
        receiptNumber: (json['receiptNumber'] as String?) ?? '',
        parcelId: (json['parcelId'] as String?) ?? '',
        trackingNumber: (json['trackingNumber'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'Delivered',
        createdAt:
            DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        deliveredAt: DateTime.tryParse((json['deliveredAt'] as String?) ?? ''),
        pickupAddress: TrackingAddress.fromJson(
          (json['pickupAddress'] as Map<String, Object?>?) ?? const {},
        ),
        deliveryAddress: TrackingAddress.fromJson(
          (json['deliveryAddress'] as Map<String, Object?>?) ?? const {},
        ),
        recipient: TrackingRecipient.fromJson(
          (json['recipient'] as Map<String, Object?>?) ?? const {},
        ),
        packageDetails: TrackingPackageDetails.fromJson(
          (json['packageDetails'] as Map<String, Object?>?) ?? const {},
        ),
        baseFee: _asDouble(json['baseFee']),
        weightFee: _asDouble(json['weightFee']),
        total: _asDouble(json['total']),
        currency: (json['currency'] as String?) ?? 'LKR',
        pricingVersion: (json['pricingVersion'] as String?) ?? '',
        calculatedAt:
            DateTime.tryParse((json['calculatedAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

final class ProofOfDeliveryModel {
  const ProofOfDeliveryModel({
    required this.parcelId,
    required this.trackingNumber,
    required this.proofType,
    required this.recipientName,
    required this.uploadedAt,
    required this.hasImage,
  });

  final String parcelId;
  final String trackingNumber;
  final String proofType;
  final String recipientName;
  final DateTime uploadedAt;
  final bool hasImage;

  factory ProofOfDeliveryModel.fromJson(Map<String, Object?> json) =>
      ProofOfDeliveryModel(
        parcelId: (json['parcelId'] as String?) ?? '',
        trackingNumber: (json['trackingNumber'] as String?) ?? '',
        proofType: (json['proofType'] as String?) ?? 'Photo',
        recipientName: (json['recipientName'] as String?) ?? '',
        uploadedAt:
            DateTime.tryParse((json['uploadedAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        hasImage: (json['hasImage'] as bool?) ?? false,
      );
}

Map<String, Object?> decodeJsonObject(String raw) =>
    (jsonDecode(raw) as Map).cast<String, Object?>();

