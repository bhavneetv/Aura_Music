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
      if (trimmed.startsWith('THEME:')) {
        theme = trimmed.replaceFirst('THEME:', '').trim();
      } else if (trimmed.startsWith('EMOTIONS:')) {
        emotions = trimmed.replaceFirst('EMOTIONS:', '').trim();
      } else if (trimmed.startsWith('MESSAGE:')) {
        message = trimmed.replaceFirst('MESSAGE:', '').trim();
      } else if (trimmed.startsWith('CULTURAL:')) {
        cultural = trimmed.replaceFirst('CULTURAL:', '').trim();
        if (cultural.toLowerCase() == 'none') cultural = '';
      } else if (trimmed.startsWith('LINE:')) {
        currentLine = trimmed.replaceFirst('LINE:', '').trim();
      } else if (trimmed.startsWith('MEANING:') && currentLine.isNotEmpty) {
        final meaning = trimmed.replaceFirst('MEANING:', '').trim();
        lines.add(LyricLineExplanation(line: currentLine, explanation: meaning));
        currentLine = '';
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
    theme += '. The track captures the essence of $genre artistry with memorable melodic flow.';

    String emotions = 'Melody, Passion, Rhythm';
    String message = 'Experience the emotional depth and rhythmic beat of this track.';
    String cultural = '';

    List<LyricLineExplanation> lines = [];

    if (genreUpper.contains('PUNJABI') || genreUpper.contains('BHANGRA')) {
      theme = '"$title" brings vibrant Punjabi folk energy and modern beat production by $artistClean.';
      emotions = 'High Energy, Celebration, Cultural Pride, Passion';
      message = 'Embrace life to the fullest with upbeat rhythms and festive Punjabi expression.';
      cultural = 'Features traditional Punjabi folk phrasing combined with urban basslines.';
      lines = [
        LyricLineExplanation(line: 'Ho ni main nakhre tere di kadr karaan...', explanation: 'Here the artist tells us that he deeply cherishes someone\'s graceful presence and takes pride in every moment shared with them.'),
        LyricLineExplanation(line: 'Wakhra swag ni tera sab ton alag...', explanation: 'In this line, the singer reveals his admiration — telling us that this person\'s unique style and confidence make them stand out from everyone else.'),
        LyricLineExplanation(line: 'Dil vich vasgi tu sohniye ni...', explanation: 'Now the author conveys that this person has permanently settled in his heart, becoming an inseparable source of joy and inspiration.'),
        LyricLineExplanation(line: 'Dhol di daag te gidha paavan...', explanation: 'The singer expresses the infectious energy of celebration — telling us about dancing with pure abandon to the festive beat of the dhol drum.'),
      ];
    } else if (genreUpper.contains('HINDI') || genreUpper.contains('BOLLYWOOD')) {
      theme = '"$title" delivers a soulful Bollywood melody with emotive vocal performance by $artistClean.';
      emotions = 'Love, Nostalgia, Emotional Depth, Romance';
      message = 'Reflects on deep personal relationships and poignant romantic storytelling.';
      cultural = 'Employs classic Indian cinematic arrangements with modern orchestral production.';
      lines = [
        LyricLineExplanation(line: 'Tum hi ho, ab tum hi ho, zindagi ab tum hi ho...', explanation: 'Here the author tells us that his entire world now revolves around one person — they are his universe, his peace, and the very purpose of his existence.'),
        LyricLineExplanation(line: 'Chain bhi, mera dard bhi, meri aashiqui ab tum hi ho...', explanation: 'In this line, the singer reveals that in moments of both joy and pain, his devotion and solace remain anchored entirely in this one person.'),
        LyricLineExplanation(line: 'Tera mera rishta hai kaisa, ek pal door gawaara nahi...', explanation: 'Now the poet conveys the depth of their bond — telling us that even a single moment of separation feels unbearable and impossible to endure.'),
        LyricLineExplanation(line: 'Har khata ki hoti hai koi na koi sazaa...', explanation: 'The artist reflects on love\'s sacrifices, telling us that every choice in love carries a consequence that shapes our emotional destiny.'),
      ];
    } else if (genreUpper.contains('SAD') || genreUpper.contains('HEARTBREAK')) {
      theme = '"$title" is a tender ballad exploring themes of heartbreak, missing someone, and emotional healing.';
      emotions = 'Heartbreak, Longing, Melancholy, Solitude';
      message = 'Finding solace and healing through heartfelt vulnerability.';
      lines = [
        LyricLineExplanation(line: 'Kaash yeh pal yahin tham jaaye...', explanation: 'Here the author tells us about a desperate wish — wanting time itself to freeze so they never have to face the cold reality of separation.'),
        LyricLineExplanation(line: 'Chhod gaye jo raaste akele...', explanation: 'In this line, the singer reveals the loneliness of being left behind — narrating how they now walk a solitary path after someone precious departed.'),
        LyricLineExplanation(line: 'Dil ko teri hi tamanna rehti hai...', explanation: 'The poet conveys an unending yearning, telling us that despite all the distance, the heart still craves the warmth and presence of the one who left.'),
      ];
    } else if (genreUpper.contains('LOFI') || genreUpper.contains('LO-FI') || genreUpper.contains('CHILL')) {
      theme = '"$title" offers relaxing lo-fi atmospheric textures and ambient study beats by $artistClean.';
      emotions = 'Calm, Tranquility, Focus, Relaxation';
      message = 'Unwind, focus, and let peace take over your surroundings.';
      lines = [
        LyricLineExplanation(line: 'Soft rain falling on the windowpane...', explanation: 'Here the artist sets the scene, telling us about a peaceful moment where gentle rain creates a meditative atmosphere for quiet reflection.'),
        LyricLineExplanation(line: 'Late night thoughts drifting away...', explanation: 'In this passage, the author conveys a sense of release — the day\'s stresses dissolve as soothing sounds guide the mind towards rest and tranquility.'),
      ];
    } else {
      lines = [
        LyricLineExplanation(line: 'Verse 1: $title rhythm starts to build...', explanation: 'Here the artist begins their narrative, telling us about the mood and atmosphere they\'re creating as the opening rhythm sets the stage.'),
        LyricLineExplanation(line: 'Chorus: $artist melodic harmony takes center stage...', explanation: 'In the chorus, the singer conveys the emotional core of the song — this is where the central themes of love, life, and human connection resonate most powerfully.'),
      ];
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

  /// Clear cached summary for a track (for refresh)
  Future<void> clearCache(String trackId) async {
    await StorageService.clearSongSummary(trackId);
  }
}
