import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/session/app_session.dart';
import '../data/tracking_api.dart';
import '../domain/tracking_models.dart';

final class CustomerHistoryController extends ChangeNotifier {
  CustomerHistoryController({required this.sessions, required this.api});

  final ValueListenable<AppSession> sessions;
  final TrackingApi api;

  List<CustomerParcelItem> items = const [];
  int totalCount = 0;
  int page = 1;
  static const int pageSize = 20;
  String? statusFilter;
  String searchQuery = '';
  bool loading = false;
  String? error;

  bool get hasMore => items.length < totalCount;

  Future<void> load({bool refresh = false}) async {
    if (!sessions.value.signedIn) {
      error = 'Sign in to view your delivery history.';
      notifyListeners();
      return;
    }
    if (refresh) page = 1;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.listParcels(
        status: statusFilter,
        search: searchQuery,
        page: page,
        pageSize: pageSize,
      );
      items = page == 1 ? result.items : [...items, ...result.items];
      totalCount = result.totalCount;
    } on TrackingApiFailure catch (e) {
      error = e.message ?? 'Unable to load deliveries (${e.code}).';
    } catch (_) {
      error = 'Unable to load deliveries.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setStatusFilter(String? status) async {
    statusFilter = status;
    await load(refresh: true);
  }

  Future<void> setSearch(String query) async {
    searchQuery = query;
    await load(refresh: true);
  }

  Future<void> loadNextPage() async {
    if (loading || !hasMore) return;
    page += 1;
    await load();
  }
}

final class CustomerParcelDetailController extends ChangeNotifier {
  CustomerParcelDetailController({required this.api, required this.parcelId});

  final TrackingApi api;
  final String parcelId;

  ParcelDetailModel? parcel;
  ProofOfDeliveryModel? proof;
  ParcelReceiptModel? receipt;
  bool loading = false;
  String? error;
  Timer? _liveTimer;

  Future<void> load({bool startLivePolling = true}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final detail = await api.getParcel(parcelId);
      parcel = detail;
      if (detail.status == 'Delivered') {
        try {
          proof = await api.getProof(parcelId);
        } catch (_) {}
        try {
          receipt = await api.getReceipt(parcelId);
        } catch (_) {}
        _liveTimer?.cancel();
      } else if (startLivePolling && !isTerminalParcelStatus(detail.status)) {
        _ensurePolling();
      }
    } on TrackingApiFailure catch (e) {
      error = e.message ?? 'Unable to load parcel (${e.code}).';
    } catch (_) {
      error = 'Unable to load parcel.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _ensurePolling() {
    _liveTimer ??= Timer.periodic(const Duration(seconds: 6), (_) async {
      try {
        final updated = await api.getParcel(parcelId);
        if (updated.version > (parcel?.version ?? 0)) {
          parcel = updated;
          if (updated.status == 'Delivered') {
            _liveTimer?.cancel();
            _liveTimer = null;
          }
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}
