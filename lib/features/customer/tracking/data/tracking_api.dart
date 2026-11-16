import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/network/request_transport.dart';
import '../domain/tracking_models.dart';

final class TrackingApiFailure implements Exception {
  const TrackingApiFailure(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;
}

final class TrackingApi {
  const TrackingApi(this.transport);
  final RequestTransport transport;

  Future<CustomerParcelPage> listParcels({
    String? status,
    String? search,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, String>{'page': '$page', 'pageSize': '$pageSize'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }
    if (from != null) params['from'] = from.toUtc().toIso8601String();
    if (to != null) params['to'] = to.toUtc().toIso8601String();
    final query = Uri(queryParameters: params).query;
    final reply = await transport.send('GET', '/api/v1/parcels?$query');
    if (reply.status != 200) throw _failure(reply);
    return CustomerParcelPage.fromJson(decodeJsonObject(reply.body));
  }

  Future<ParcelDetailModel> getParcel(String parcelId) async {
    final reply = await transport.send(
      'GET',
      '/api/v1/parcels/${Uri.encodeComponent(parcelId)}',
    );
    if (reply.status != 200) throw _failure(reply);
    return ParcelDetailModel.fromJson(decodeJsonObject(reply.body));
  }

  Future<ParcelReceiptModel> getReceipt(String parcelId) async {
    final reply = await transport.send(
      'GET',
      '/api/v1/parcels/${Uri.encodeComponent(parcelId)}/receipt?format=json',
      headers: const {'Accept': 'application/json'},
    );
    if (reply.status != 200) throw _failure(reply);
    return ParcelReceiptModel.fromJson(decodeJsonObject(reply.body));
  }

  Future<Uint8List> downloadReceiptPdf(String parcelId) async {
    final reply = await transport.send(
      'GET',
      '/api/v1/parcels/${Uri.encodeComponent(parcelId)}/receipt?format=pdf',
      headers: const {'Accept': 'application/pdf'},
    );
    if (reply.status != 200) throw _failure(reply);
    return reply.bodyBytes ?? Uint8List.fromList(utf8.encode(reply.body));
  }

  Future<ProofOfDeliveryModel> getProof(String parcelId) async {
    final reply = await transport.send(
      'GET',
      '/api/v1/parcels/${Uri.encodeComponent(parcelId)}/pod?format=json',
      headers: const {'Accept': 'application/json'},
    );
    if (reply.status != 200) throw _failure(reply);
    return ProofOfDeliveryModel.fromJson(decodeJsonObject(reply.body));
  }

  TrackingApiFailure _failure(ApiReply reply) {
    try {
      final json = decodeJsonObject(reply.body);
      return TrackingApiFailure(
        reply.status,
        (json['code'] as String?) ?? 'request_failed',
        json['title'] as String?,
      );
    } catch (_) {
      return TrackingApiFailure(reply.status, 'request_failed');
    }
  }
}
