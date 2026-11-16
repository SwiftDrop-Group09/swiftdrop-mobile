import 'dart:convert';

import '../../../../core/network/request_transport.dart';
import '../../tracking/domain/tracking_models.dart';
import '../domain/assistant_models.dart';

final class AssistantApiFailure implements Exception {
  const AssistantApiFailure(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;

  @override
  String toString() => message ?? 'AssistantApiFailure($status, $code)';
}

final class AssistantApi {
  const AssistantApi(this.transport);
  final RequestTransport transport;

  Future<AssistantChatResponse> chat(AssistantChatRequest request) async {
    final payload = jsonEncode(request.toJson());
    final reply = await transport.send(
      'POST',
      '/api/v1/assistant/chat',
      body: payload,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );

    if (reply.status != 200) {
      throw _failure(reply);
    }

    final json = decodeJsonObject(reply.body);
    return AssistantChatResponse.fromJson(json);
  }

  Future<List<McpToolDefinition>> getMcpTools() async {
    final reply = await transport.send(
      'GET',
      '/api/v1/mcp/tools',
      headers: const {'Accept': 'application/json'},
    );

    if (reply.status != 200) {
      throw _failure(reply);
    }

    final json = decodeJsonObject(reply.body);
    final rawTools = (json['tools'] as List<Object?>?) ?? const [];
    return rawTools
        .whereType<Map<String, Object?>>()
        .map(McpToolDefinition.fromJson)
        .toList(growable: false);
  }

  Future<Map<String, Object?>> callMcpTool(
    String toolName, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': toolName,
        'arguments': arguments,
      },
    });

    final reply = await transport.send(
      'POST',
      '/api/v1/mcp',
      body: payload,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );

    if (reply.status != 200) {
      throw _failure(reply);
    }

    return decodeJsonObject(reply.body);
  }

  AssistantApiFailure _failure(ApiReply reply) {
    try {
      final json = decodeJsonObject(reply.body);
      return AssistantApiFailure(
        reply.status,
        (json['code'] as String?) ?? 'assistant_failed',
        json['title'] as String? ?? json['message'] as String?,
      );
    } catch (_) {
      return AssistantApiFailure(reply.status, 'assistant_failed');
    }
  }
}
