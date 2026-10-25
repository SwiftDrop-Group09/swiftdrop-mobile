import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/network/exact_json.dart';
import '../../../../core/session/customer_session.dart';
import '../data/booking_api.dart';
import '../domain/booking_models.dart';

enum BookingStage {
  editing,
  estimating,
  preview,
  confirming,
  uncertain,
  blocked,
  success,
}

final class ConfirmationAttempt {
  ConfirmationAttempt(this.owner, DeliveryQuote quote, this.key)
    : quoteId = quote.id,
      total = quote.total,
      body = encodeExactJson({'quoteId': quote.id, 'acceptTotal': quote.total});

  final String owner;
  final String quoteId;
  final ExactNumber total;
  final String key;
  final String body;
}

final class BookingController extends ChangeNotifier {
  BookingController({
    required this.sessions,
    required this.api,
    required this.zoneCatalog,
    DateTime Function()? now,
    String Function()? newKey,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _newKey = newKey ?? _randomKey,
       _sessionOwner = sessions.value.principalId,
       _sessionCanBook = sessions.value.canBook {
    sessions.addListener(_sessionChanged);
  }

  final ValueListenable<CustomerSession> sessions;
  final BookingApi api;
  final ZoneCatalog zoneCatalog;
  final DateTime Function() _now;
  final String Function() _newKey;
  String? _sessionOwner;
  bool _sessionCanBook;
  int _revision = 0;
  int sessionRevision = 0;
  bool _disposed = false;
  bool zonesLoading = false;
  List<BookingZone> zones = const [];
  BookingStage stage = BookingStage.editing;
  DeliveryQuote? quote;
  BookingDraft? _quotedDraft;

  /// Details submitted for the current quote, retained across app navigation.
  BookingDraft? get quotedDraft => _quotedDraft;
  BookingReceipt? receipt;
  ConfirmationAttempt? attempt;
  DateTime? retryAt;
  String? error;
  Map<String, String> fieldErrors = const {};

  bool get canBook => sessions.value.canBook;
  bool get isBusy =>
      stage == BookingStage.estimating || stage == BookingStage.confirming;
  bool get locked => attempt != null && stage != BookingStage.success;
  bool get quoteExpired => quote != null && !_now().isBefore(quote!.expiresAt);
  bool get canRetry =>
      stage == BookingStage.uncertain &&
      canBook &&
      (retryAt == null || !_now().isBefore(retryAt!));

  void refreshTime() {
    if (!_disposed && (quote != null || retryAt != null)) notifyListeners();
  }

  Future<void> loadZones() async {
    if (!canBook || zonesLoading || zones.isNotEmpty) return;
    final revision = sessionRevision;
    zonesLoading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await zoneCatalog.load();
      if (_disposed || revision != sessionRevision) return;
      zones = List.unmodifiable(loaded);
      if (zones.isEmpty) error = 'Address coverage is currently unavailable.';
    } catch (_) {
      if (!_disposed && revision == sessionRevision) {
        error = 'Unable to load address coverage. Try again.';
      }
    } finally {
      if (!_disposed && revision == sessionRevision) {
        zonesLoading = false;
        notifyListeners();
      }
    }
  }

  void inputChanged() {
    if (locked || stage == BookingStage.success) return;
    _revision++;
    quote = null;
    _quotedDraft = null;
    error = null;
    fieldErrors = const {};
    stage = BookingStage.editing;
    notifyListeners();
  }

  void decline() {
    if (attempt != null || isBusy) return;
    _revision++;
    quote = null;
    _quotedDraft = null;
    error = null;
    stage = BookingStage.editing;
    notifyListeners();
  }

  Future<void> estimate(BookingDraft draft) async {
    if (!canBook ||
        isBusy ||
        attempt != null ||
        stage == BookingStage.success) {
      return;
    }
    fieldErrors = draft.validate(zones);
    if (fieldErrors.isNotEmpty) {
      error = 'Check the highlighted delivery details.';
      notifyListeners();
      return;
    }
    final revision = ++_revision;
    stage = BookingStage.estimating;
    error = null;
    quote = null;
    _quotedDraft = null;
    notifyListeners();
    try {
      final received = await api.estimate(draft);
      if (!_current(revision)) return;
      quote = received;
      _quotedDraft = draft;
      stage = BookingStage.preview;
    } on BookingApiFailure catch (failure) {
      if (!_current(revision)) return;
      stage = BookingStage.editing;
      error = _message(failure);
      fieldErrors = failure.errors;
    } catch (_) {
      if (!_current(revision)) return;
      stage = BookingStage.editing;
      error = 'Unable to estimate the delivery fee. Check your connection and try again.';
    }
    if (_current(revision)) notifyListeners();
  }

  Future<void> confirm() async {
    if (!canBook ||
        isBusy ||
        stage == BookingStage.success ||
        stage == BookingStage.blocked) {
      return;
    }
    if (attempt == null) {
      if (quote == null) return;
      if (quoteExpired) {
        quote = null;
        _quotedDraft = null;
        stage = BookingStage.editing;
        error = 'This quote has expired. Request a new fee before confirming.';
        notifyListeners();
        return;
      }
      attempt = ConfirmationAttempt(
        sessions.value.principalId!,
        quote!,
        _newKey(),
      );
    } else if (!canRetry || attempt!.owner != sessions.value.principalId) {
      return;
    }
    final currentAttempt = attempt!;
    final revision = _revision;
    stage = BookingStage.confirming;
    error = null;
    retryAt = null;
    notifyListeners();
    try {
      final result = await api.confirm(currentAttempt.body, currentAttempt.key);
      if (!_current(revision) ||
          currentAttempt.owner != sessions.value.principalId) {
        return;
      }
      if (result.total.compareTo(currentAttempt.total) != 0 ||
          result.currency != quote!.currency ||
          result.pricingVersion != quote!.pricingVersion) {
        throw const FormatException('Unexpected committed price snapshot.');
      }
      receipt = result;
      stage = BookingStage.success;
    } on BookingApiFailure catch (failure) {
      if (!_current(revision)) return;
      error = _message(failure);
      if (failure.code == 'quote_expired' || failure.code == 'price_mismatch') {
        attempt = null;
        quote = null;
        _quotedDraft = null;
        stage = BookingStage.editing;
      } else if (failure.code == 'operation_in_progress') {
        stage = BookingStage.uncertain;
        retryAt = _now().add(Duration(seconds: failure.retryAfter));
      } else if (failure.status <= 0 ||
          failure.status >= 500 ||
          failure.status == 401 ||
          failure.status == 408 ||
          failure.status == 429) {
        stage = BookingStage.uncertain;
      } else {
        stage = BookingStage.blocked;
      }
    } catch (_) {
      if (!_current(revision)) return;
      stage = BookingStage.uncertain;
      error = 'The booking outcome is unknown. Retry this same confirmation to recover it.';
    }
    if (_current(revision)) notifyListeners();
  }

  void startAnother() {
    if (stage != BookingStage.success) return;
    _revision++;
    stage = BookingStage.editing;
    quote = null;
    _quotedDraft = null;
    receipt = null;
    attempt = null;
    retryAt = null;
    error = null;
    fieldErrors = const {};
    notifyListeners();
  }

  bool _current(int revision) => !_disposed && revision == _revision;

  void _sessionChanged() {
    final session = sessions.value;
    if (session.principalId == _sessionOwner &&
        session.canBook == _sessionCanBook) {
      return;
    }
    _sessionOwner = session.principalId;
    _sessionCanBook = session.canBook;
    _revision++;
    sessionRevision++;
    stage = BookingStage.editing;
    quote = null;
    _quotedDraft = null;
    receipt = null;
    attempt = null;
    retryAt = null;
    error = null;
    zones = const [];
    zonesLoading = false;
    fieldErrors = const {};
    notifyListeners();
  }

  static String _randomKey() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _message(BookingApiFailure failure) => switch (failure.code) {
    'unauthorized' =>
      'Sign in again with the same account to continue this confirmation.',
    'forbidden' => 'A Customer account is required to book a delivery.',
    'unsupported_zone' => 'Choose available service zones for both addresses.',
    'validation' => 'The delivery details were not accepted. Check your input.',
    'pricing_unavailable' =>
      'Delivery pricing is currently unavailable. Try again later.',
    'quote_expired' => 'This quote has expired. Request and accept a new fee.',
    'price_mismatch' =>
      'The accepted price did not match. Request and accept a new fee.',
    'operation_in_progress' =>
      'This confirmation is still processing. Wait briefly, then retry it.',
    'idempotency_conflict' => 'This confirmation conflicts with an earlier attempt. Do not submit a new booking.',
    'key_expired' => 'This confirmation can no longer be replayed. Resolve its outcome before booking again.',
    'quote_consumed' || 'quote_conflict' || 'not_found' => 'This quote cannot be confirmed. Resolve this attempt before booking again.',
    _ =>
      failure.status >= 500
          ? 'The service is unavailable. If confirming, retry this same confirmation to recover its outcome.'
          : 'The request could not be completed. Please check your account and delivery details.',
  };

  @override
  void dispose() {
    _disposed = true;
    sessions.removeListener(_sessionChanged);
    super.dispose();
  }
}
