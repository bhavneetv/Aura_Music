import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../storage/storage_service.dart';
import 'ai_service.dart';

class LyricLineExplanation {
  final String line;
  final String explanation;

  LyricLineExplanation({required this.line, required this.explanation});

  Map<String, dynamic> toJson() => {
    'line': line,
    'explanation': explanation,
  };

  factory LyricLineExplanation.fromJson(Map<String, dynamic> json) => LyricLineExplanation(
    line: json['line']?.toString() ?? '',
    explanation: json['explanation']?.toString() ?? '',
  );
}

class SongSummary {
  final String theme;
  final String emotions;
  final String message;
  final String culturalNotes;
  final String language;
  final List<LyricLineExplanation> lineByLineExplanations;

  SongSummary({
    required this.theme,
    required this.emotions,
    required this.message,
    this.culturalNotes = '',
    this.language = 'English',
    this.lineByLineExplanations = const [],
  });

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'emotions': emotions,
    'message': message,
    'culturalNotes': culturalNotes,
    'language': language,
    'lineByLineExplanations': lineByLineExplanations.map((e) => e.toJson()).toList(),
    'generatedAt': DateTime.now().toIso8601String(),
  };

  factory SongSummary.fromJson(Map<String, dynamic> json) => SongSummary(
    theme: json['theme']?.toString() ?? '',
    emotions: json['emotions']?.toString() ?? '',
    message: json['message']?.toString() ?? '',
    culturalNotes: json['culturalNotes']?.toString() ?? '',
    language: json['language']?.toString() ?? 'English',
    lineByLineExplanations: json['lineByLineExplanations'] != null && json['lineByLineExplanations'] is List
        ? (json['lineByLineExplanations'] as List).map((e) => LyricLineExplanation.fromJson(Map<String, dynamic>.from(e as Map))).toList()
        : [],
  );
}

class SongSummaryService {
  static final SongSummaryService instance = SongSummaryService._internal();
  SongSummaryService._internal();

  /// Get song summary — returns cached version if available, otherwise generates via AiService
  Future<SongSummary> getSummary({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String genre,
    String? lyricsText,
    bool forceRefresh = false,
  }) async {
    // Read user's summary language preference ('en' -> English, 'hi' -> Hindi, 'hinglish' -> Hinglish)
    final langCode = (StorageService.getSetting('summary_language', defaultValue: 'en') as String).toLowerCase();
    
    String summaryLangName = 'English';
    if (langCode == 'hi' || langCode == 'hindi') {
      summaryLangName = 'Hindi';
    } else if (langCode == 'hinglish' || langCode == 'hi_en') {
      summaryLangName = 'Hinglish (Casual conversational mix of Hindi and English written in Latin/English script, e.g., "Iss song mein singer apne heartbreak and feelings express kar raha hai...")';
    }

    final cacheKey = '${trackId}_$langCode';

    // Check cache first
    if (!forceRefresh) {
      final cached = StorageService.getSongSummary(cacheKey);
      if (cached != null) {
        final parsed = SongSummary.fromJson(cached);
        if (parsed.theme.isNotEmpty) {
          return parsed;
        }
      }
    }

    try {
      final summary = await _generateAISummary(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        lyricsText: lyricsText,
        outputLanguage: summaryLangName,
      );

      if (summary != null && summary.theme.isNotEmpty) {
        await StorageService.saveSongSummary(cacheKey, summary.toJson());
        return summary;
      }
    } catch (e) {
      debugPrint('[SongSummaryService] AI generation failed: $e');
    }

    // Metadata-based fallback
    final fallback = _generateMetadataFallback(
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      language: summaryLangName,
    );
    await StorageService.saveSongSummary(cacheKey, fallback.toJson());
    return fallback;
  }

  /// Generate AI summary using unified AiService (Groq -> Gemini 2.5 Flash fallback)
  Future<SongSummary?> _generateAISummary({
    required String title,
    required String artist,
    required String album,
    required String genre,
    String? lyricsText,
    required String outputLanguage,
  }) async {
    String lyricsBlock = '';
    if (lyricsText != null && lyricsText.trim().isNotEmpty) {
      lyricsBlock = '\nFULL LYRICS OF THE SONG:\n$lyricsText\n';
    }

    final prompt = '''You are a master music critic and cultural storyteller.
Analyze the song "$title" by $artist (Album: "$album", Genre/Language: "$genre").
$lyricsBlock
Provide a comprehensive, complete narrative summary of the ENTIRE song from beginning to end in $outputLanguage.

CRITICAL INSTRUCTIONS:
- Explain the FULL story of the song from the opening verses through the middle build-up to the climax and conclusion. Do NOT summarize only half the song or stop mid-way!
- Provide a detailed 5-8 sentence complete narrative summary covering all parts and emotional shifts of the full lyrics.
- Explain what the artist/singer is communicating to the listener across the whole track.
- If language is Hinglish, write the entire response in casual Hinglish (Hindi written in Roman/English script like: "Iss song mein singer apni feelings and journey explain kar raha hai...").

Provide:
1. **Theme**: Full complete narrative summary covering the entire song's story, verses, chorus, and ending (5-8 detailed sentences).
2. **Emotions**: 4-6 specific emotional progression tones across the song (e.g. Nostalgic, Melancholic, Passionate, Triumphant).
3. **Message**: Deep core philosophy or message of the full song (2-3 sentences).
4. **Cultural Notes**: Cinematic context, lyrical metaphors, album, or musical style notes (2 sentences).

Format your response EXACTLY as:
THEME: [your full complete 5-8 sentence narrative summary of the entire song]
EMOTIONS: [comma-separated emotions list]
MESSAGE: [your deep message text]
CULTURAL: [cultural/cinematic context]''';

    final (text, _) = await AiService.instance.generate(prompt);
    return _parseAIResponse(text, outputLanguage);
  }

  /// Parse structured AI response into SongSummary
  SongSummary? _parseAIResponse(String text, String language) {
    if (text.trim().isEmpty) return null;

    final cleanText = text.replaceAll('**', '').replaceAll('##', '');
    String theme = '';
    String emotions = '';
    String message = '';
    String cultural = '';

    final themeMatch = RegExp(r'THEME:\s*([\s\S]*?)(?=EMOTIONS:|MESSAGE:|CULTURAL:|$)', caseSensitive: false).firstMatch(cleanText);
    final emotionsMatch = RegExp(r'EMOTIONS:\s*([\s\S]*?)(?=MESSAGE:|CULTURAL:|THEME:|$)', caseSensitive: false).firstMatch(cleanText);
    final messageMatch = RegExp(r'MESSAGE:\s*([\s\S]*?)(?=CULTURAL:|THEME:|EMOTIONS:|$)', caseSensitive: false).firstMatch(cleanText);
    final culturalMatch = RegExp(r'CULTURAL:\s*([\s\S]*?)(?=$)', caseSensitive: false).firstMatch(cleanText);

    if (themeMatch != null) theme = themeMatch.group(1)?.trim() ?? '';
    if (emotionsMatch != null) emotions = emotionsMatch.group(1)?.trim() ?? '';
    if (messageMatch != null) message = messageMatch.group(1)?.trim() ?? '';
    if (culturalMatch != null) cultural = culturalMatch.group(1)?.trim() ?? '';

    if (cultural.toLowerCase() == 'none') cultural = '';

    if (theme.isEmpty) {
      theme = cleanText.length > 250 ? '${cleanText.substring(0, 250)}...' : cleanText;
    }

    if (emotions.isEmpty) emotions = 'Melody, Passion, Rhythm, Storytelling';
    if (message.isEmpty) message = 'Reflects the core musical theme and emotional narrative of the track.';

    return SongSummary(
      theme: theme,
      emotions: emotions,
      message: message,
      culturalNotes: cultural,
      language: language,
    );
  }

  SongSummary _generateMetadataFallback({
    required String title,
    required String artist,
    required String album,
    required String genre,
    String language = 'English',
  }) {
    final genreUpper = genre.toUpperCase();
    final artistClean = artist.split(',').first.trim();

    String theme = '"$title" is an expressive $genre musical release by $artistClean';
    if (album.isNotEmpty && album != 'Single') {
      theme += ' from the album "$album"';
    }
    theme += '. The track captures the essence of $genre musical storytelling with emotive vocal delivery.';

    String emotions = 'Melody, Emotion, Passion, Rhythm';
    String message = 'Reflects on the personal storytelling and feelings embedded within "$title".';
    String cultural = '';

    if (language.toLowerCase().contains('hinglish')) {
      theme = '"$title" ek expressive $genre release hai by $artistClean. Iss song mein artist ne deep emotions and story express ki hai.';
      emotions = 'Melody, Emotion, Passion, Beats';
      message = 'Is song ka main message heart-touching emotional experience share karna hai.';
    } else if (genreUpper.contains('PUNJABI') || genreUpper.contains('BHANGRA')) {
      theme = '"$title" brings vibrant Punjabi folk energy and modern beat production by $artistClean.';
      emotions = 'High Energy, Celebration, Cultural Expression, Passion';
      message = 'Embrace life with upbeat rhythms and festive expression in "$title".';
      cultural = 'Features traditional Punjabi folk phrasing combined with urban basslines.';
    } else if (genreUpper.contains('HINDI') || genreUpper.contains('BOLLYWOOD')) {
      theme = '"$title" delivers a soulful melody with emotive vocal performance by $artistClean.';
      emotions = 'Love, Nostalgia, Emotional Depth, Romance';
      message = 'Reflects on deep personal relationships and poignant romantic storytelling in "$title".';
      cultural = 'Employs classic Indian cinematic arrangements with modern orchestral production.';
    }

    final List<LyricLineExplanation> lines = [
      LyricLineExplanation(
        line: 'Opening verse of "$title"',
        explanation: 'Here $artistClean sets the scene, introducing the central mood and emotional atmosphere of the song.',
      ),
      LyricLineExplanation(
        line: 'Melodic progression in "$title"',
        explanation: 'In this section, the singer conveys deep feelings of $emotions, building towards the core story.',
      ),
      LyricLineExplanation(
        line: 'Chorus / Core Refrain',
        explanation: 'Now the author expresses the main message of the track, telling us how love, life, and personal passion intertwine.',
      ),
    ];

    return SongSummary(
      theme: theme,
      emotions: emotions,
      message: message,
      culturalNotes: cultural,
      language: language,
      lineByLineExplanations: lines,
    );
  }

  Future<void> clearCache(String trackId) async {
    final langCode = (StorageService.getSetting('summary_language', defaultValue: 'en') as String).toLowerCase();
    await StorageService.clearSongSummary('${trackId}_$langCode');
    await StorageService.clearSongSummary(trackId);
  }

  /// Generate line-by-line AI explanations for a list of lyric lines
  Future<Map<int, String>> getLineExplanations({
    required String title,
    required String artist,
    required List<String> lyricLines,
  }) async {
    if (lyricLines.isEmpty) return {};

    final cleanLines = lyricLines.take(30).toList();
    final langCode = (StorageService.getSetting('summary_language', defaultValue: 'en') as String).toLowerCase();
    String outputLang = 'English';
    if (langCode == 'hi' || langCode == 'hindi') {
      outputLang = 'Hindi';
    } else if (langCode == 'hinglish') {
      outputLang = 'Hinglish (casual Hindi written in Latin/English script)';
    }

    final prompt = '''You are a master music lyricist and cultural translator.
Analyze the song "$title" by $artist and provide short 1-sentence explanations for each of the following lyric lines in $outputLang.
Explain what the author/artist is expressing or implying in each line (hidden meaning, mood, or metaphor).

Lyric lines:
${cleanLines.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

Output format MUST be valid JSON array of objects:
[
  {"index": 1, "explanation": "Short 1-sentence explanation of what author means in line 1"}
]
OUTPUT ONLY JSON:''';

    try {
      final (response, _) = await AiService.instance.generate(prompt);
      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart != -1 && jsonEnd != -1) {
        final cleanJson = response.substring(jsonStart, jsonEnd + 1);
        final List decoded = jsonDecode(cleanJson) as List;
        final Map<int, String> map = {};
        for (final item in decoded) {
          if (item is Map) {
            final idx = (int.tryParse(item['index']?.toString() ?? '') ?? 0) - 1;
            final exp = item['explanation']?.toString().trim() ?? '';
            if (idx >= 0 && idx < lyricLines.length && exp.isNotEmpty) {
              map[idx] = exp;
            }
          }
        }
        if (map.isNotEmpty) return map;
      }
    } catch (e) {
      debugPrint('[SongSummaryService] line-by-line generation error: $e');
    }

    final Map<int, String> fallback = {};
    for (var i = 0; i < lyricLines.length; i++) {
      final line = lyricLines[i].trim();
      if (line.isNotEmpty) {
        fallback[i] = 'Author conveys emotional narrative and deep vocal expression in this line.';
      }
    }
    return fallback;
  }
}
