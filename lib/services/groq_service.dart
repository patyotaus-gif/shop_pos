import 'dart:convert';
import 'package:http/http.dart' as http;

class GroqMessage {
  final String role;
  final String content;
  const GroqMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class GroqService {
  static const _url = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.1-8b-instant';

  static String? _apiKey;
  static void setApiKey(String key) => _apiKey = key;

  static Future<String> chat(
    List<GroqMessage> history, {
    String? shopContext,
  }) async {
    if (_apiKey == null) throw Exception('Groq API key not set');

    final systemPrompt = '''คุณเป็นผู้ช่วย AI สำหรับร้านค้าปลีกที่ใช้ระบบ Pokpok POS
ตอบเป็นภาษาไทย กระชับ ตรงประเด็น ช่วยวิเคราะห์ยอดขาย แนะนำการจัดการร้าน
${shopContext != null ? '\nข้อมูลร้านวันนี้:\n$shopContext' : ''}''';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => m.toJson()),
    ];

    final res = await http.post(
      Uri.parse(_url),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': messages,
        'max_tokens': 1024,
        'temperature': 0.7,
      }),
    );

    if (res.statusCode != 200) throw Exception('Groq error: ${res.body}');
    final data = jsonDecode(res.body);
    return data['choices'][0]['message']['content'] as String;
  }
}
