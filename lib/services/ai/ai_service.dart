import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AiService {
  static final AiService instance = AiService._internal();
  AiService._internal();

  final Dio _dio = Dio();

  String get groqKey1 => dotenv.env['GROQ_KEY'] ?? '';
  String get groqKey2 => dotenv.env['GROQ_KEY_2'] ?? groqKey1;
  String get geminiKey => dotenv.env['GEMINI_KEY'] ?? '';

  /// Generates AI text, trying Groq Key 1 first, Groq Key 2 second,
  /// and falling back to Gemini on any failure.
  /// Returns a tuple `(String content, String provider)` indicating which provider served the call.
  Future<(String text, String provider)> generate(String prompt) async {
    // 1. Try Groq Key 1
    if (groqKey1.isNotEmpty && groqKey1 != 'your_groq_api_key_here') {
      try {
        final content = await _callGroq(prompt, groqKey1).timeout(const Duration(seconds: 8));
        if (content.isNotEmpty) {
          debugPrint('[AiService] Served by Groq Key 1 (llama-3.3-70b-versatile)');
          return (content, 'Groq (Key 1)');
        }
      } catch (e) {
        debugPrint('[AiService] Groq Key 1 failed ($e). Retrying immediately with Groq Key 2...');
      }
    }

    // 2. Try Groq Key 2
    if (groqKey2.isNotEmpty && groqKey2 != 'your_groq_api_key_here' && groqKey2 != 'your_second_groq_api_key_here') {
      try {
        final content = await _callGroq(prompt, groqKey2).timeout(const Duration(seconds: 8));
        if (content.isNotEmpty) {
          debugPrint('[AiService] Served by Groq Key 2 (llama-3.3-70b-versatile)');
          return (content, 'Groq (Key 2)');
        }
      } catch (e) {
        debugPrint('[AiService] Groq Key 2 failed ($e). Falling back to Gemini...');
      }
    }

    // 3. Fallback to Gemini
    if (geminiKey.isNotEmpty && geminiKey != 'your_gemini_api_key_here') {
      try {
        final content = await _callGemini(prompt);
        if (content.isNotEmpty) {
          debugPrint('[AiService] Served by Gemini (gemini-2.5-flash)');
          return (content, 'Gemini');
        }
      } catch (e) {
        debugPrint('[AiService] Gemini failed: $e');
      }
    } else {
      debugPrint('[AiService] Gemini key missing/placeholder.');
    }

    throw Exception('All AI providers (Groq Key 1, Groq Key 2, Gemini) failed or keys not configured.');
  }

  Future<String> _callGroq(String prompt, String apiKey) async {
    final response = await _dio.post(
      'https://api.groq.com/openai/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 5),
      ),
      data: {
        'model': 'llama-3.3-70b-versatile',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final choices = response.data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        if (message != null && message['content'] != null) {
          return message['content'].toString();
        }
      }
    }
    throw Exception('Groq API returned invalid response (Status ${response.statusCode})');
  }

  Future<String> _callGemini(String prompt) async {
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiKey';
    final response = await _dio.post(
      url,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 5),
      ),
      data: {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.75,
          'maxOutputTokens': 1000,
        }
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final candidates = response.data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString() ?? '';
        }
      }
    }
    throw Exception('Gemini API returned invalid response (Status ${response.statusCode})');
  }
}
