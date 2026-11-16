import 'package:flutter/foundation.dart';

import '../../../../core/session/app_session.dart';
import '../data/assistant_api.dart';
import '../domain/assistant_models.dart';

class AssistantController extends ChangeNotifier {
  AssistantController({
    required this.api,
    required this.sessions,
  });

  final AssistantApi api;
  final ValueListenable<AppSession> sessions;

  final List<AssistantMessageItem> _messages = [];
  List<AssistantMessageItem> get messages => List.unmodifiable(_messages);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  List<String> _suggestedPrompts = const [
    'Where is my parcel?',
    'How much to send 2 kg to Kandy?',
    'What delivery zones do you cover?',
  ];
  List<String> get suggestedPrompts => _suggestedPrompts;

  String? _conversationId;
  String? get conversationId => _conversationId;

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;

    _error = null;
    final userMessage = AssistantMessageItem(
      role: 'user',
      content: trimmed,
    );
    _messages.add(userMessage);
    _loading = true;
    notifyListeners();

    try {
      final history = _messages
          .map((m) => ChatMessage(role: m.role, content: m.content))
          .toList();

      final request = AssistantChatRequest(
        message: trimmed,
        conversationId: _conversationId,
        history: history,
      );

      final response = await api.chat(request);

      final assistantMessage = AssistantMessageItem(
        role: 'assistant',
        content: response.reply,
        toolCalls: response.toolCalls,
        cards: response.cards,
        guardrail: response.guardrail,
      );

      _messages.add(assistantMessage);

      if (response.suggestedPrompts.isNotEmpty) {
        _suggestedPrompts = response.suggestedPrompts.take(3).toList();
      }
    } on AssistantApiFailure catch (e) {
      _error = e.message ?? 'Assistant could not process request (${e.code}).';
    } catch (_) {
      _error = 'Unable to connect to delivery assistant.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearChat() {
    _messages.clear();
    _error = null;
    _conversationId = null;
    _suggestedPrompts = const [
      'Where is my parcel?',
      'How much to send 2 kg to Kandy?',
      'What delivery zones do you cover?',
    ];
    notifyListeners();
  }
}
