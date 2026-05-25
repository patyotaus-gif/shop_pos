import 'package:cloud_functions/cloud_functions.dart';

class AiMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  const AiMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Client-side wrapper around the [`aiChat`](functions/index.js) Cloud
/// Function, which proxies to Google Gemini with a server-held API key.
///
/// We don't talk to any LLM provider from the client anymore — the key
/// never leaves the function instance, subscription gating + per-shop
/// daily quota are enforced server-side, and we can swap providers
/// (Gemini ↔ OpenAI ↔ Anthropic) without touching the app.
class AiService {
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<AiChatResult> chat(
    List<AiMessage> history, {
    String? shopContext,
  }) async {
    try {
      final callable = _functions.httpsCallable('aiChat');
      final res = await callable.call<Map<Object?, Object?>>({
        'history': history.map((m) => m.toJson()).toList(),
        'shopContext': shopContext ?? '',
      });
      final data = res.data;
      final reply = data['reply'] as String? ?? '';
      final usage = data['usage'] as Map<Object?, Object?>?;
      return AiChatResult(
        reply: reply,
        dailyCount: (usage?['dailyCount'] as num?)?.toInt(),
        dailyLimit: (usage?['dailyLimit'] as num?)?.toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      // Surface the server's localized message (subscription expired,
      // quota hit, etc.) directly to the chat UI.
      throw AiServiceException(e.message ?? 'AI ใช้ไม่ได้ในตอนนี้');
    }
  }
}

class AiChatResult {
  final String reply;
  final int? dailyCount;
  final int? dailyLimit;
  const AiChatResult({
    required this.reply,
    this.dailyCount,
    this.dailyLimit,
  });
}

class AiServiceException implements Exception {
  final String message;
  const AiServiceException(this.message);
  @override
  String toString() => message;
}
