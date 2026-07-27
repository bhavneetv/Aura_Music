import 'package:dio/dio.dart';
import '../storage/storage_service.dart';

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

  final Dio _dio = Dio();
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  /// Get song summary — returns cached version if available, otherwise generates via AI or fallback
  Future<SongSummary> getSummary({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String genre,
    bool forceRefresh = false,
  }) async {
    // Check cache first
    if (!forceRefresh) {
      final cached = StorageService.getSongSummary(trackId);
      if (cached != null) {
        final parsed = SongSummary.fromJson(cached);
        if (parsed.theme.isNotEmpty) {
          return parsed;
        }
      }
    }

    // Determine user's preferred language for the summary
    final preferredLangs = StorageService.getPreferredLanguages();
    final summaryLang = preferredLangs.isNotEmpty ? preferredLangs.first : 'English';

    try {
      final summary = await _generateAISummary(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        outputLanguage: summaryLang,
      );

      if (summary != null && summary.theme.isNotEmpty) {
        await StorageService.saveSongSummary(trackId, summary.toJson());
        return summary;
      }
    } catch (_) {}

    // Rich metadata-based fallback (guaranteed to succeed offline or on API key fallback)
    final fallback = _generateMetadataFallback(
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      language: summaryLang,
    );
    await StorageService.saveSongSummary(trackId, fallback.toJson());
    return fallback;
  }

  /// Generate AI summary with line-by-line lyric explanations using Gemini 2.0 Flash
  Future<SongSummary?> _generateAISummary({
    required String title,
    required String artist,
    required String album,
    required String genre,
    required String outputLanguage,
  }) async {
    final prompt = '''You are a music storyteller. For the song "$title" by $artist (Album: $album, Language/Genre: $genre), create a narrative summary and a line-by-line storytelling breakdown.

For each lyric line, write a narrative explanation in $outputLanguage that tells the listener what the author is about to express — like a narrator guiding someone through the song's journey. Use phrases like "Here the artist tells us...", "In this line, the author reveals...", "The singer expresses...", "Now the poet conveys..." etc.

Provide:
1. **Theme**: What story is this song telling? (1-2 sentences, narrative tone)
2. **Emotions**: What feelings does the listener experience? (comma-separated list)
3. **Message**: What is the author trying to tell the listener? (1-2 sentences)
4. **Cultural Notes**: Any cultural references the listener should know? (1 sentence or None)
5. **Line-by-Line Story**: Pick 5-7 key lyric lines and narrate what the author is telling the listener in each line.

Format your response EXACTLY like this:
THEME: [your theme text]
EMOTIONS: [your emotions list]
MESSAGE: [your message text]
CULTURAL: [your cultural notes or None]
LINE: [Lyric Line 1]
MEANING: [Narrative of what the author tells us in this line]
LINE: [Lyric Line 2]
MEANING: [Narrative of what the author tells us in this line]
LINE: [Lyric Line 3]
MEANING: [Narrative of what the author tells us in this line]
LINE: [Lyric Line 4]
MEANING: [Narrative of what the author tells us in this line]
LINE: [Lyric Line 5]
MEANING: [Narrative of what the author tells us in this line]''';

    try {
      final response = await _dio.post(
        '$_baseUrl?key=$_apiKey',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 15),
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
            'maxOutputTokens': 800,
          }
        },
      );

      final candidates = response.data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = parts[0]['text']?.toString() ?? '';
          return _parseAIResponse(text, outputLanguage);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Parse structured AI response into SongSummary
  SongSummary? _parseAIResponse(String text, String language) {
    if (text.isEmpty) return null;

    String theme = '';
    String emotions = '';
    String message = '';
    String cultural = '';
    final List<LyricLineExplanation> lines = [];

    String currentLine = '';

    for (final rawLine in text.split('\n')) {
      final trimmed = rawLine.trim();
      final upper = trimmed.toUpperCase();

      if (upper.contains('THEME:')) {
        theme = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (upper.contains('EMOTIONS:')) {
        emotions = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (upper.contains('MESSAGE:')) {
        message = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (upper.contains('CULTURAL:')) {
        cultural = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        if (cultural.toLowerCase() == 'none') cultural = '';
      } else if (upper.contains('LINE:') || upper.startsWith('LINE ')) {
        currentLine = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        currentLine = currentLine.replaceAll(RegExp(r'^[\s\x22\x27]+|[\s\x22\x27]+$'), '');
      } else if (upper.contains('MEANING:') || upper.contains('EXPLANATION:')) {
        final meaning = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        if (currentLine.isNotEmpty && meaning.isNotEmpty) {
          lines.add(LyricLineExplanation(line: currentLine, explanation: meaning));
          currentLine = '';
        }
      }
    }

    if (theme.isEmpty && emotions.isEmpty && message.isEmpty) {
      theme = text.length > 200 ? '${text.substring(0, 200)}...' : text;
    }

    return SongSummary(
      theme: theme,
      emotions: emotions,
      message: message,
      culturalNotes: cultural,
      language: language,
      lineByLineExplanations: lines,
    );
  }

  /// Generate a rich summary with line-by-line lyric breakdowns from metadata
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

    if (genreUpper.contains('PUNJABI') || genreUpper.contains('BHANGRA')) {
      theme = '"$title" brings vibrant Punjabi folk energy and modern beat production by $artistClean.';
      emotions = 'High Energy, Celebration, Cultural Expression, Passion';
      message = 'Embrace life with upbeat rhythms and festive expression in "$title".';
      cultural = 'Features traditional Punjabi folk phrasing combined with urban basslines.';
    } else if (genreUpper.contains('HINDI') || genreUpper.contains('BOLLYWOOD')) {
      theme = '"$title" delivers a soulful melody with emotive vocal performance by $artistClean.';
      emotions = 'Love, Nostalgia, Emotional Depth, Romance';
      message = 'Reflects on deep personal relationships and poignant romantic storytelling in "$title".';
      cultural = 'Employs classic Indian cinematic arrangements with modern orchestral production.';
    } else if (genreUpper.contains('SAD') || genreUpper.contains('HEARTBREAK')) {
      theme = '"$title" is a tender ballad by $artistClean exploring themes of heartbreak and emotional healing.';
      emotions = 'Heartbreak, Longing, Melancholy, Solitude';
      message = 'Finding solace and healing through heartfelt vulnerability in "$title".';
    } else if (genreUpper.contains('LOFI') || genreUpper.contains('LO-FI') || genreUpper.contains('CHILL')) {
      theme = '"$title" offers relaxing lo-fi atmospheric textures and ambient beats by $artistClean.';
      emotions = 'Calm, Tranquility, Focus, Relaxation';
      message = 'Unwind, focus, and let peace take over your surroundings with "$title".';
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
      LyricLineExplanation(
        line: 'Concluding movement of "$title"',
        explanation: 'The artist resolves the musical journey, leaving the listener with a resonant message of emotional connection.',
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

  /// Clear cached summary for a track (for refresh)
  Future<void> clearCache(String trackId) async {
    await StorageService.clearSongSummary(trackId);
  }
}
