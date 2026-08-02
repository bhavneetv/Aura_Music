import 'package:dio/dio.dart';
import '../storage/storage_service.dart';
import '../ai/ai_service.dart';

class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);

  Map<String, dynamic> toJson() => {
    'timeMs': time.inMilliseconds,
    'text': text,
  };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    Duration(milliseconds: (json['timeMs'] as num?)?.toInt() ?? 0),
    json['text']?.toString() ?? '',
  );
}

class LyricsCandidate {
  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final double duration;
  final bool instrumental;
  final String? syncedLyrics;
  final String? plainLyrics;
  final String languageLabel;

  LyricsCandidate({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    this.syncedLyrics,
    this.plainLyrics,
    this.languageLabel = 'Default',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'duration': duration,
    'instrumental': instrumental,
    'syncedLyrics': syncedLyrics,
    'plainLyrics': plainLyrics,
    'languageLabel': languageLabel,
  };

  factory LyricsCandidate.fromJson(Map<String, dynamic> json) => LyricsCandidate(
    id: (json['id'] as num?)?.toInt() ?? 0,
    trackName: json['trackName']?.toString() ?? '',
    artistName: json['artistName']?.toString() ?? '',
    albumName: json['albumName']?.toString() ?? '',
    duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
    instrumental: json['instrumental'] == true,
    syncedLyrics: json['syncedLyrics']?.toString(),
    plainLyrics: json['plainLyrics']?.toString(),
    languageLabel: json['languageLabel']?.toString() ?? 'Default',
  );
}

class LyricsResult {
  final List<LyricLine>? synced;
  final String? plain;
  final bool instrumental;
  final List<LyricsCandidate> candidates;

  bool get hasLyrics => (synced != null && synced!.isNotEmpty) || (plain != null && plain!.isNotEmpty);

  LyricsResult({
    this.synced,
    this.plain,
    this.instrumental = false,
    this.candidates = const [],
  });

  Map<String, dynamic> toJson() => {
    'synced': synced?.map((l) => l.toJson()).toList(),
    'plain': plain,
    'instrumental': instrumental,
    'candidates': candidates.map((c) => c.toJson()).toList(),
  };

  factory LyricsResult.fromJson(Map<String, dynamic> json) => LyricsResult(
    synced: json['synced'] != null && json['synced'] is List
        ? (json['synced'] as List).map((l) => LyricLine.fromJson(Map<String, dynamic>.from(l as Map))).toList()
        : null,
    plain: json['plain']?.toString(),
    instrumental: json['instrumental'] == true,
    candidates: json['candidates'] != null && json['candidates'] is List
        ? (json['candidates'] as List).map((c) => LyricsCandidate.fromJson(Map<String, dynamic>.from(c as Map))).toList()
        : [],
  );
}

List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
  for (final line in lrc.split('\n')) {
    final m = regex.firstMatch(line.trim());
    if (m == null) continue;
    final minutes = int.parse(m.group(1)!);
    final seconds = int.parse(m.group(2)!);
    final msStr = m.group(3)!.padRight(3, '0');
    final ms = int.parse(msStr);
    final text = m.group(4)!.trim();
    lines.add(LyricLine(
      Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
      text,
    ));
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

int currentLineIndex(List<LyricLine> lines, Duration position, {int offsetMs = -300}) {
  final calibratedPos = position + Duration(milliseconds: offsetMs);
  int idx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].time <= calibratedPos) {
      idx = i;
    } else {
      break;
    }
  }
  return idx;
}

class LyricsService {
  static final LyricsService instance = LyricsService._internal();
  LyricsService._internal();

  final Dio _dio = Dio();

  int _parseDurationSeconds(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 180;
  }

  /// Fetches lyrics for a track from LRCLIB with local Hive caching.
  Future<LyricsResult> fetchLyrics({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String durationStr,
    bool forceRefresh = false,
  }) async {
    // 1. Check local Hive cache
    if (!forceRefresh) {
      final cached = StorageService.getLyrics(trackId);
      if (cached != null) {
        return LyricsResult.fromJson(cached);
      }
    }

    final durationSec = _parseDurationSeconds(durationStr);
    final cleanTitle = title.split('(').first.split('-').first.trim();
    final cleanArtist = artist.split(',').first.trim();
    final cleanAlbum = album.trim();

    try {
      // 2. Try exact GET match
      final getUri = Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
        if (cleanAlbum.isNotEmpty && cleanAlbum != 'Single') 'album_name': cleanAlbum,
        'duration': durationSec.toString(),
      });

      final response = await _dio.get(
        getUri.toString(),
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final result = _parseLrclibObject(response.data);
        if (result != null && result.hasLyrics) {
          await StorageService.saveLyrics(trackId, result.toJson());
          return result;
        }
      }
    } catch (_) {}

    try {
      // 3. Try search endpoint fallback
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      });

      final response = await _dio.get(
        searchUri.toString(),
        options: Options(
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final rawList = response.data as List;
        final candidates = <LyricsCandidate>[];

        for (var i = 0; i < rawList.length; i++) {
          final item = rawList[i];
          if (item is Map) {
            final syncedStr = item['syncedLyrics']?.toString();
            final plainStr = item['plainLyrics']?.toString();
            final isInstrumental = item['instrumental'] == true;

            if (isInstrumental || (syncedStr != null && syncedStr.isNotEmpty) || (plainStr != null && plainStr.isNotEmpty)) {
              String label = 'Option ${candidates.length + 1}';
              final albumName = item['albumName']?.toString() ?? '';
              if (albumName.isNotEmpty) {
                label = '$albumName (${candidates.length + 1})';
              }
              candidates.add(LyricsCandidate(
                id: (item['id'] as num?)?.toInt() ?? i,
                trackName: item['trackName']?.toString() ?? '',
                artistName: item['artistName']?.toString() ?? '',
                albumName: albumName,
                duration: (item['duration'] as num?)?.toDouble() ?? 0.0,
                instrumental: isInstrumental,
                syncedLyrics: syncedStr,
                plainLyrics: plainStr,
                languageLabel: label,
              ));
            }
          }
        }

        if (candidates.isNotEmpty) {
          // Sort candidates by closest duration match
          candidates.sort((a, b) {
            final diffA = (a.duration - durationSec).abs();
            final diffB = (b.duration - durationSec).abs();
            return diffA.compareTo(diffB);
          });

          final best = candidates.first;
          List<LyricLine>? syncedLines;
          if (best.syncedLyrics != null && best.syncedLyrics!.isNotEmpty) {
            syncedLines = parseLrc(best.syncedLyrics!);
          }

          final result = LyricsResult(
            synced: syncedLines,
            plain: best.plainLyrics,
            instrumental: best.instrumental,
            candidates: candidates,
          );

          await StorageService.saveLyrics(trackId, result.toJson());
          return result;
        }
      }
    } catch (_) {}

    // 4. Return empty result if nothing found
    final emptyResult = LyricsResult();
    await StorageService.saveLyrics(trackId, emptyResult.toJson());
    return emptyResult;
  }

  LyricsResult? _parseLrclibObject(dynamic data) {
    if (data is! Map) return null;
    final syncedStr = data['syncedLyrics']?.toString();
    final plainStr = data['plainLyrics']?.toString();
    final isInstrumental = data['instrumental'] == true;

    List<LyricLine>? syncedLines;
    if (syncedStr != null && syncedStr.isNotEmpty) {
      syncedLines = parseLrc(syncedStr);
    }

    return LyricsResult(
      synced: syncedLines,
      plain: plainStr,
      instrumental: isInstrumental,
      candidates: [
        LyricsCandidate(
          id: (data['id'] as num?)?.toInt() ?? 0,
          trackName: data['trackName']?.toString() ?? '',
          artistName: data['artistName']?.toString() ?? '',
          albumName: data['albumName']?.toString() ?? '',
          duration: (data['duration'] as num?)?.toDouble() ?? 0.0,
          instrumental: isInstrumental,
          syncedLyrics: syncedStr,
          plainLyrics: plainStr,
          languageLabel: 'Default',
        )
      ],
    );
  }

  /// Translates lyrics to the requested target language using AiService with local Hive caching.
  Future<String> translateLyrics({
    required String trackId,
    required String lyricsText,
    required String targetLanguage,
  }) async {
    final cacheKey = 'translated_lyrics_${trackId}_$targetLanguage';
    final cached = StorageService.getSetting(cacheKey, defaultValue: null);
    if (cached != null && cached.toString().isNotEmpty) {
      return cached.toString();
    }

    final String languageInstruction = targetLanguage.toLowerCase() == 'hinglish'
        ? 'Romanized Hinglish (Hindi language written using English/Roman alphabet script)'
        : targetLanguage;

    final prompt = '''
Translate/transliterate the following song lyrics into $languageInstruction.
Preserve the line structure and line count exactly. Output ONLY the translated/transliterated lyrics without introductory text, titles, or notes:

$lyricsText
''';

    try {
      final (translatedText, _) = await AiService.instance.generate(prompt);
      if (translatedText.isNotEmpty) {
        await StorageService.saveSetting(cacheKey, translatedText);
        return translatedText;
      }
    } catch (_) {}

    return lyricsText;
  }
}
