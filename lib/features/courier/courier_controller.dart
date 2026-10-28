import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/network/request_transport.dart';
import '../../core/session/app_session.dart';
import 'courier_api.dart';
import 'courier_models.dart';

/// Feature state only. The host owns the shared authenticated transport/session.
final class CourierController extends ChangeNotifier {
  CourierController({
    required this.sessions,
    required this.api,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _scope = sessions.value.scope;
    sessions.addListener(_sessionChanged);
  }
  final ValueListenable<AppSession> sessions;
  final CourierApi api;
  final DateTime Function() _now;
  late String _scope;
  int _revision = 0, _manifestRead = 0, _detailRead = 0, _historyRead = 0;
  bool _disposed = false;
  bool get authorized => sessions.value.canCourier;
  String get scope => _scope;
  CourierPage<AssignedParcel>? manifest;
  CourierPage<ParcelSummary>? history;
  ParcelDetail? detail;
  ParcelSummary? receipt;
  CourierAttempt? pending;
  String? manifestError, historyError, detailError, notice;
  bool manifestLoading = false,
      historyLoading = false,
      detailLoading = false,
      busy = false,
      blocked = false;
  double? uploadProgress;
  DateTime? retryAt;
  String? date;
  bool includeOverdue = true;
  int manifestPage = 1, historyPage = 1;
  bool get locked => busy || pending != null || blocked;
  bool get canRetry =>
      pending != null &&
      !busy &&
      (retryAt == null || !_now().isBefore(retryAt!));
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int rev) => !_disposed && rev == _revision && authorized;
  void _sessionChanged() {
    if (_scope == sessions.value.scope) return;
    _scope = sessions.value.scope;
    _revision++;
    _clear();
    _emit();
  }

  void _clear() {
    manifest = null;
    history = null;
    detail = null;
    receipt = null;
    pending = null;
    manifestError = null;
    historyError = null;
    detailError = null;
    notice = null;
    manifestLoading = false;
    historyLoading = false;
    detailLoading = false;
    busy = false;
    blocked = false;
    retryAt = null;
    uploadProgress = null;
    date = null;
    includeOverdue = true;
    manifestPage = 1;
    historyPage = 1;
  }

  void _deny(CourierException e) {
    if (const [401, 403].contains(e.status)) {
      _revision++;
      manifest = null;
      history = null;
      detail = null;
      pending = null;
      receipt = null;
      busy = false;
      manifestLoading = false;
      historyLoading = false;
      detailLoading = false;
      uploadProgress = null;
      blocked = true;
      _emit();
    }
  }

  Future<void> loadManifest() async {
    if (!authorized || blocked) return;
    final rev = _revision, read = ++_manifestRead;
    manifestLoading = true;
    manifest = null;
    manifestError = null;
    _emit();
    try {
      final result = await api.manifest(
        date: date,
        includeOverdue: includeOverdue,
        page: manifestPage,
      );
      if (_current(rev) && read == _manifestRead) manifest = result;
    } on CourierException catch (e) {
      if (_current(rev) && read == _manifestRead) {
        manifestError = e.message;
        _deny(e);
      }
    } finally {
      if (_current(rev) && read == _manifestRead) {
        manifestLoading = false;
        _emit();
      }
    }
  }

  Future<void> loadHistory() async {
    if (!authorized || blocked) return;
    final rev = _revision, read = ++_historyRead;
    historyLoading = true;
    history = null;
    historyError = null;
    _emit();
    try {
      final result = await api.history(page: historyPage);
      if (_current(rev) && read == _historyRead) history = result;
    } on CourierException catch (e) {
      if (_current(rev) && read == _historyRead) {
        historyError = e.message;
        _deny(e);
      }
    } finally {
      if (_current(rev) && read == _historyRead) {
        historyLoading = false;
        _emit();
      }
    }
  }

  Future<void> loadDetail(String id) async {
    if (!authorized || blocked) return;
    final rev = _revision, read = ++_detailRead;
    detailLoading = true;
    detail = null;
    detailError = null;
    _emit();
    try {
      final result = await api.detail(id);
      if (_current(rev) && read == _detailRead) detail = result;
    } on CourierException catch (e) {
      if (_current(rev) && read == _detailRead) {
        detailError = e.message;
        _deny(e);
      }
    } finally {
      if (_current(rev) && read == _detailRead) {
        detailLoading = false;
        _emit();
      }
    }
  }

  static String _key() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> status(String target, String notes, {String? reason}) async {
    if (locked || detail == null) return;
    try {
      await _submit(
        CourierApi.statusAttempt(
          detail!,
          target,
          notes,
          _key(),
          failureReason: reason,
        ),
      );
    } on CourierException catch (e) {
      notice = e.message;
      _emit();
    }
  }

  Future<void> proof(
    String name, {
    UploadPart? photo,
    UploadPart? signature,
  }) async {
    if (locked || detail == null) return;
    try {
      await _submit(
        CourierApi.proofAttempt(
          detail!,
          name,
          _key(),
          photo: photo,
          signature: signature,
        ),
      );
    } on CourierException catch (e) {
      notice = e.message;
      _emit();
    }
  }

  Future<void> retry() async {
    if (canRetry) await _submit(pending!);
  }

  Future<void> _submit(CourierAttempt original) async {
    if (!authorized || blocked || busy) return;
    final rev = _revision;
    pending = original;
    busy = true;
    receipt = null;
    uploadProgress = null;
    notice = 'Waiting for backend confirmation…';
    _emit();
    try {
      final result = await api.submit(
        original,
        onProgress: (sent, total) {
          if (_current(rev)) {
            uploadProgress = total > 0 ? sent / total : null;
            _emit();
          }
        },
      );
      if (!_current(rev)) return;
      pending = null;
      busy = false;
      retryAt = null;
      uploadProgress = null;
      receipt = result;
      notice = '${result.status} confirmed by Delivery.';
      detail = null;
      _emit();
      if (result.active) await loadDetail(result.id);
      await loadManifest();
      await loadHistory();
    } on CourierException catch (e) {
      if (!_current(rev)) return;
      busy = false;
      uploadProgress = null;
      notice = e.message;
      if (e.uncertain) {
        pending = original;
        retryAt = _now().add(Duration(seconds: e.retryAfter));
        _emit();
        return;
      }
      pending = null;
      detail = null;
      retryAt = null;
      _deny(e);
      _emit();
      if (!blocked && e.status != 404) await loadDetail(original.id);
      if (e.status == 404) {
        detailError = e.message;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    sessions.removeListener(_sessionChanged);
    _clear();
    super.dispose();
  }
}
