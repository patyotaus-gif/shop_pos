import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';

class AiMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final Map<String, dynamic>? analysis;
  final bool isError;
  const AiMessage(
      {required this.role,
      required this.content,
      this.analysis,
      this.isError = false});
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
    int days = 30,
  }) async {
    try {
      final callable = _functions.httpsCallable('aiChat',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)));
      final messages = history.where((m) => !m.isError).toList();
      final recent = messages.length > 19
          ? messages.sublist(messages.length - 19)
          : messages;
      while (recent.isNotEmpty && recent.first.role != 'user') {
        recent.removeAt(0);
      }
      final res = await callable.call<Map<Object?, Object?>>({
        'history': recent
            .map((m) => {
                  'role': m.role,
                  'content': m.content.length > 4000
                      ? m.content.substring(0, 4000)
                      : m.content
                })
            .toList(),
        'days': days,
      });
      final data = res.data;
      final reply = data['reply'] as String? ?? '';
      final usage = data['usage'] as Map<Object?, Object?>?;
      return AiChatResult(
        reply: reply,
        analysis: data['analysis'] == null
            ? null
            : jsonDecode(jsonEncode(data['analysis'])) as Map<String, dynamic>,
        dailyCount: (usage?['dailyCount'] as num?)?.toInt(),
        dailyLimit: (usage?['dailyLimit'] as num?)?.toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      // Surface the server's localized message (subscription expired,
      // quota hit, etc.) directly to the chat UI.
      throw AiServiceException(e.message ?? 'AI ใช้ไม่ได้ในตอนนี้');
    }
  }

  static Future<Map<String, dynamic>> analysis(int days) async {
    final result = await _functions
        .httpsCallable('getSalesAnalysis',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 120)))
        .call({'days': days});
    return jsonDecode(jsonEncode(result.data)) as Map<String, dynamic>;
  }

  static Future<void> saveContext(Map<String, dynamic> data) async {
    await _functions.httpsCallable('saveAnalysisContext').call(data);
  }
}

class AiChatResult {
  final String reply;
  final Map<String, dynamic>? analysis;
  final int? dailyCount;
  final int? dailyLimit;
  const AiChatResult({
    required this.reply,
    this.analysis,
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
