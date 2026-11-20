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

final class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
        role: (json['role'] as String?) ?? 'user',
        content: (json['content'] as String?) ?? '',
      );
}

final class AssistantChatRequest {
  const AssistantChatRequest({
    required this.message,
    this.conversationId,
    this.history = const [],
  });

  final String message;
  final String? conversationId;
  final List<ChatMessage> history;

  Map<String, Object?> toJson() {
    final map = <String, Object?>{
      'message': message,
      'history': history.map((e) => e.toJson()).toList(),
    };
    if (conversationId != null) map['conversationId'] = conversationId;
    return map;
  }
}

final class AssistantToolCallTrace {
  const AssistantToolCallTrace({
    required this.toolName,
    this.arguments,
    required this.status,
    required this.durationMs,
    required this.summary,
  });

  final String toolName;
  final Object? arguments;
  final String status;
  final int durationMs;
  final String summary;

  factory AssistantToolCallTrace.fromJson(Map<String, Object?> json) =>
      AssistantToolCallTrace(
        toolName: (json['toolName'] as String?) ?? '',
        arguments: json['arguments'],
        status: (json['status'] as String?) ?? 'success',
        durationMs: _asInt(json['durationMs']),
        summary: (json['summary'] as String?) ?? '',
      );
}

final class AssistantMilestoneStep {
  const AssistantMilestoneStep({
    required this.status,
    required this.label,
    this.timestamp,
    required this.completed,
    required this.current,
  });

  final String status;
  final String label;
  final DateTime? timestamp;
  final bool completed;
  final bool current;

  factory AssistantMilestoneStep.fromJson(Map<String, Object?> json) =>
      AssistantMilestoneStep(
        status: (json['status'] as String?) ?? 'Created',
        label: (json['label'] as String?) ?? '',
        timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? ''),
        completed: (json['completed'] as bool?) ?? false,
        current: (json['current'] as bool?) ?? false,
      );
}

final class TrackingCardData {
  const TrackingCardData({
    required this.trackingNumber,
    required this.status,
    required this.originCity,
    required this.destinationCity,
    required this.lastUpdatedAt,
    required this.steps,
    required this.canViewReceipt,
    this.parcelId,
    this.isPublic = false,
  });

  final String trackingNumber;
  final String status;
  final String originCity;
  final String destinationCity;
  final DateTime lastUpdatedAt;
  final List<AssistantMilestoneStep> steps;
  final bool canViewReceipt;
  final String? parcelId;
  final bool isPublic;

  int get currentMilestoneIndex {
    final idx = steps.indexWhere((s) => s.current);
    if (idx >= 0) return idx + 1;
    final lastCompleted = steps.lastIndexWhere((s) => s.completed);
    if (lastCompleted >= 0) return lastCompleted + 1;
    return 1;
  }

  factory TrackingCardData.fromJson(Map<String, Object?> json) {
    final rawSteps = (json['steps'] as List<Object?>?) ?? const [];
    return TrackingCardData(
      trackingNumber: (json['trackingNumber'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'Created',
      originCity: (json['originCity'] as String?) ?? '',
      destinationCity: (json['destinationCity'] as String?) ?? '',
      lastUpdatedAt:
          DateTime.tryParse((json['lastUpdatedAt'] as String?) ?? '') ??
          DateTime.now(),
      steps: rawSteps
          .whereType<Map<String, Object?>>()
          .map(AssistantMilestoneStep.fromJson)
          .toList(growable: false),
      canViewReceipt: (json['canViewReceipt'] as bool?) ?? false,
      parcelId: json['parcelId'] as String?,
      isPublic: (json['isPublic'] as bool?) ?? false,
    );
  }
}

final class ParcelSummaryItem {
  const ParcelSummaryItem({
    required this.trackingNumber,
    required this.status,
    required this.route,
    required this.weightKg,
    required this.size,
    required this.createdAt,
    this.parcelId,
  });

  final String trackingNumber;
  final String status;
  final String route;
  final double weightKg;
  final String size;
  final DateTime createdAt;
  final String? parcelId;

  factory ParcelSummaryItem.fromJson(Map<String, Object?> json) =>
      ParcelSummaryItem(
        trackingNumber: (json['trackingNumber'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'Created',
        route: (json['route'] as String?) ?? '',
        weightKg: _asDouble(json['weightKg']),
        size: (json['size'] as String?) ?? 'Small',
        createdAt:
            DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.now(),
        parcelId: json['parcelId'] as String?,
      );
}

final class ParcelListCardData {
  const ParcelListCardData({
    required this.totalCount,
    required this.parcels,
  });

  final int totalCount;
  final List<ParcelSummaryItem> parcels;

  factory ParcelListCardData.fromJson(Map<String, Object?> json) {
    final rawList = (json['parcels'] as List<Object?>?) ?? const [];
    return ParcelListCardData(
      totalCount: _asInt(json['totalCount']),
      parcels: rawList
          .whereType<Map<String, Object?>>()
          .map(ParcelSummaryItem.fromJson)
          .toList(growable: false),
    );
  }
}

final class QuoteCardData {
  const QuoteCardData({
    this.quoteId,
    required this.total,
    required this.currency,
    required this.pricingVersion,
    this.expiresAt,
    required this.weightKg,
    required this.size,
    required this.pickupCity,
    required this.deliveryCity,
    required this.bookingDeepLink,
  });

  final String? quoteId;
  final double total;
  final String currency;
  final String pricingVersion;
  final DateTime? expiresAt;
  final double weightKg;
  final String size;
  final String pickupCity;
  final String deliveryCity;
  final String bookingDeepLink;

  factory QuoteCardData.fromJson(Map<String, Object?> json) => QuoteCardData(
        quoteId: json['quoteId']?.toString(),
        total: _asDouble(json['total']),
        currency: (json['currency'] as String?) ?? 'LKR',
        pricingVersion: (json['pricingVersion'] as String?) ?? '',
        expiresAt: DateTime.tryParse((json['expiresAt'] as String?) ?? ''),
        weightKg: _asDouble(json['weightKg']),
        size: (json['size'] as String?) ?? 'Small',
        pickupCity: (json['pickupCity'] as String?) ?? '',
        deliveryCity: (json['deliveryCity'] as String?) ?? '',
        bookingDeepLink: (json['bookingDeepLink'] as String?) ?? '',
      );
}

final class ZoneCoverageItem {
  const ZoneCoverageItem({
    required this.zoneId,
    required this.name,
    required this.cities,
    required this.active,
  });

  final String zoneId;
  final String name;
  final List<String> cities;
  final bool active;

  factory ZoneCoverageItem.fromJson(Map<String, Object?> json) {
    final rawCities = (json['cities'] as List<Object?>?) ?? const [];
    return ZoneCoverageItem(
      zoneId: (json['zoneId']?.toString()) ?? '',
      name: (json['name'] as String?) ?? '',
      cities: rawCities.whereType<String>().toList(growable: false),
      active: (json['active'] as bool?) ?? true,
    );
  }
}

final class ZonesCardData {
  const ZonesCardData({
    required this.zones,
    required this.supportedCities,
  });

  final List<ZoneCoverageItem> zones;
  final List<String> supportedCities;

  factory ZonesCardData.fromJson(Map<String, Object?> json) {
    final rawZones = (json['zones'] as List<Object?>?) ?? const [];
    final rawCities = (json['supportedCities'] as List<Object?>?) ?? const [];
    return ZonesCardData(
      zones: rawZones
          .whereType<Map<String, Object?>>()
          .map(ZoneCoverageItem.fromJson)
          .toList(growable: false),
      supportedCities: rawCities.whereType<String>().toList(growable: false),
    );
  }
}

final class DeliveryTimeEstimateCardData {
  const DeliveryTimeEstimateCardData({
    required this.pickupCity,
    required this.deliveryCity,
    required this.estimatedDuration,
    required this.estimatedDeliveryDate,
    required this.serviceSpeed,
    required this.cutoffTime,
    required this.minHours,
    required this.maxHours,
    required this.routeType,
    required this.summary,
  });

  final String pickupCity;
  final String deliveryCity;
  final String estimatedDuration;
  final String estimatedDeliveryDate;
  final String serviceSpeed;
  final String cutoffTime;
  final int minHours;
  final int maxHours;
  final String routeType;
  final String summary;

  factory DeliveryTimeEstimateCardData.fromJson(Map<String, Object?> json) {
    return DeliveryTimeEstimateCardData(
      pickupCity: json['pickupCity']?.toString() ?? '',
      deliveryCity: json['deliveryCity']?.toString() ?? '',
      estimatedDuration: json['estimatedDuration']?.toString() ?? '',
      estimatedDeliveryDate: json['estimatedDeliveryDate']?.toString() ?? '',
      serviceSpeed: json['serviceSpeed']?.toString() ?? 'Standard',
      cutoffTime: json['cutoffTime']?.toString() ?? '',
      minHours: (json['minHours'] as num?)?.toInt() ?? 24,
      maxHours: (json['maxHours'] as num?)?.toInt() ?? 48,
      routeType: json['routeType']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
    );
  }
}

final class AssistantCards {
  const AssistantCards({
    this.tracking,
    this.parcelList,
    this.quote,
    this.zones,
    this.deliveryTime,
  });

  final TrackingCardData? tracking;
  final ParcelListCardData? parcelList;
  final QuoteCardData? quote;
  final ZonesCardData? zones;
  final DeliveryTimeEstimateCardData? deliveryTime;

  factory AssistantCards.fromJson(Map<String, Object?> json) => AssistantCards(
        tracking: json['tracking'] != null
            ? TrackingCardData.fromJson(
                (json['tracking'] as Map).cast<String, Object?>(),
              )
            : null,
        parcelList: json['parcelList'] != null
            ? ParcelListCardData.fromJson(
                (json['parcelList'] as Map).cast<String, Object?>(),
              )
            : null,
        quote: json['quote'] != null
            ? QuoteCardData.fromJson(
                (json['quote'] as Map).cast<String, Object?>(),
              )
            : null,
        zones: json['zones'] != null
            ? ZonesCardData.fromJson(
                (json['zones'] as Map).cast<String, Object?>(),
              )
            : null,
        deliveryTime: json['deliveryTime'] != null
            ? DeliveryTimeEstimateCardData.fromJson(
                (json['deliveryTime'] as Map).cast<String, Object?>(),
              )
            : null,
      );
}

final class GuardrailResult {
  const GuardrailResult({required this.blocked, required this.reason});

  final bool blocked;
  final String reason;

  factory GuardrailResult.fromJson(Map<String, Object?> json) => GuardrailResult(
        blocked: (json['blocked'] as bool?) ?? false,
        reason: (json['reason'] as String?) ?? '',
      );
}

final class AssistantChatResponse {
  const AssistantChatResponse({
    required this.reply,
    required this.mode,
    required this.toolCalls,
    this.cards,
    this.suggestedPrompts = const [],
    this.guardrail,
  });

  final String reply;
  final String mode;
  final List<AssistantToolCallTrace> toolCalls;
  final AssistantCards? cards;
  final List<String> suggestedPrompts;
  final GuardrailResult? guardrail;

  factory AssistantChatResponse.fromJson(Map<String, Object?> json) {
    final rawTools = (json['toolCalls'] as List<Object?>?) ?? const [];
    final rawPrompts = (json['suggestedPrompts'] as List<Object?>?) ?? const [];

    return AssistantChatResponse(
      reply: (json['reply'] as String?) ?? '',
      mode: (json['mode'] as String?) ?? 'Standard',
      toolCalls: rawTools
          .whereType<Map<String, Object?>>()
          .map(AssistantToolCallTrace.fromJson)
          .toList(growable: false),
      cards: json['cards'] != null
          ? AssistantCards.fromJson(
              (json['cards'] as Map).cast<String, Object?>(),
            )
          : null,
      suggestedPrompts: rawPrompts.whereType<String>().toList(growable: false),
      guardrail: json['guardrail'] != null
          ? GuardrailResult.fromJson(
              (json['guardrail'] as Map).cast<String, Object?>(),
            )
          : null,
    );
  }
}

final class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    this.inputSchema = const {},
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  factory McpToolDefinition.fromJson(Map<String, Object?> json) =>
      McpToolDefinition(
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        inputSchema:
            (json['inputSchema'] as Map<String, Object?>?) ?? const {},
      );
}

final class AssistantMessageItem {
  AssistantMessageItem({
    required this.role,
    required this.content,
    this.toolCalls = const [],
    this.cards,
    this.guardrail,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String role;
  final String content;
  final List<AssistantToolCallTrace> toolCalls;
  final AssistantCards? cards;
  final GuardrailResult? guardrail;
  final DateTime timestamp;

  bool get isUser => role == 'user';
}
