import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AiService {
  static final AiService instance = AiService._internal();
  AiService._internal();

  final Dio _dio = Dio();

  String get groqKey1 {
    const envKey = String.fromEnvironment('GROQ_KEY');
    if (envKey.isNotEmpty) return envKey;
    return dotenv.env['GROQ_KEY'] ?? '';
  }

  String get groqKey2 {
    const envKey = String.fromEnvironment('GROQ_KEY_2');
    if (envKey.isNotEmpty) return envKey;
    return dotenv.env['GROQ_KEY_2'] ?? groqKey1;
  }

  String get geminiKey {
    const envKey = String.fromEnvironment('GEMINI_KEY');
    if (envKey.isNotEmpty) return envKey;
    return dotenv.env['GEMINI_KEY'] ?? '';
  }

  static const List<String> _groqModels = [
    'openai/gpt-oss-20b',
    'groq/compound-mini',
    'qwen/qwen3.6-27b',
  ];

  static const List<String> _geminiModels = [
    'gemini-3.6-flash',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
  ];

  /// Cleans raw output text by stripping reasoning (`<think>...</think>`) tags if present.
  String _cleanResponseText(String rawText) {
    return rawText.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  }

  /// Generates AI text, trying Groq Key 1 first, Groq Key 2 second,
  /// and falling back to Gemini on any failure.
  /// Returns a tuple `(String content, String provider)` indicating which provider served the call.
  Future<(String text, String provider)> generate(String prompt) async {
    // 1. Try Groq Key 1
    if (groqKey1.isNotEmpty && groqKey1 != 'your_groq_api_key_here') {
      try {
        final content = await _callGroq(prompt, groqKey1);
        if (content.isNotEmpty) {
          debugPrint('[AiService] Served by Groq Key 1');
          return (content, 'Groq (Key 1)');
        }
      } catch (e) {
        debugPrint('[AiService] Groq Key 1 failed ($e). Retrying immediately with Groq Key 2...');
      }
    }

    // 2. Try Groq Key 2
    if (groqKey2.isNotEmpty && groqKey2 != 'your_groq_api_key_here' && groqKey2 != 'your_second_groq_api_key_here') {
      try {
        final content = await _callGroq(prompt, groqKey2);
        if (content.isNotEmpty) {
          debugPrint('[AiService] Served by Groq Key 2');
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
          debugPrint('[AiService] Served by Gemini');
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
    Object? lastException;
    for (final model in _groqModels) {
      try {
        final response = await _dio.post(
          'https://api.groq.com/openai/v1/chat/completions',
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AuraMusic/1.0',
            },
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 5),
          ),
          data: {
            'model': model,
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
              final raw = message['content'].toString();
              final cleaned = _cleanResponseText(raw);
              if (cleaned.isNotEmpty) {
                debugPrint('[AiService] Groq model $model succeeded.');
                return cleaned;
              }
            }
          }
        }
      } catch (e) {
        lastException = e;
        debugPrint('[AiService] Groq model $model failed ($e). Trying next model...');
      }
    }
    throw Exception('Groq API error across all models: $lastException');
  }

  Future<String> _callGemini(String prompt) async {
    Object? lastException;
    for (final model in _geminiModels) {
      try {
        final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey';
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
              'maxOutputTokens': 1200,
            }
          },
        );

        if (response.statusCode == 200 && response.data != null) {
          final candidates = response.data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final parts = content['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final raw = parts[0]['text']?.toString() ?? '';
              final cleaned = _cleanResponseText(raw);
              if (cleaned.isNotEmpty) {
                debugPrint('[AiService] Gemini model $model succeeded.');
                return cleaned;
              }
            }
          }
        }
      } catch (e) {
        lastException = e;
        debugPrint('[AiService] Gemini model $model failed ($e). Trying next model...');
      }
    }
    throw Exception('Gemini API error across all models: $lastException');
  }
}

