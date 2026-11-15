import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  final Map<String, LyricsResult> _memCache = {};
  final Map<String, Future<LyricsResult>> _inFlight = {};

  int _parseDurationSeconds(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 180;
  }

  /// Cleans track title by stripping visualizer/video/remaster/feature noise
  static String cleanTrackTitle(String title) {
    var t = title.trim();
    t = t.replaceAll(
      RegExp(
        r'\s*[\(\[](?:from\s+.*?|official\s*(?:video|audio|music\s*video|lyric\s*video)?|lyrics?|remastered(?:\s*\d+)?|live|radio\s*edit|slowed\s*\+?\s*reverb|lofi\s*mix|acoustic|audio|visualizer)[\)\]]',
        caseSensitive: false,
      ),
      '',
    );
    t = t.replaceAll(RegExp(r'\s*[\(\[](?:feat\.|ft\.|featuring).*?[\)\]]', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+(?:feat\.|ft\.|featuring)\s+.*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+-\s+(?:remix|remastered|live|radio edit|original motion picture soundtrack|soundtrack).*$', caseSensitive: false), '');
    t = t.trim();
    if (t.isEmpty) {
      final firstPart = title.split('(').first.trim();
      t = firstPart.isNotEmpty ? firstPart : title.trim();
    }
    return t;
  }

  /// Cleans artist name by extracting primary artist
  static String cleanArtistName(String artist) {
    var a = artist.trim();
    final first = a.split(RegExp(r'[,/&]|(?:\s+feat\.?\s+)|\s+ft\.?\s+', caseSensitive: false)).first.trim();
    return first.isNotEmpty ? first : a;
  }

  /// Fetches lyrics for a track from LRCLIB with tiered fast search and local Hive caching.
  Future<LyricsResult> fetchLyrics({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String durationStr,
    bool forceRefresh = false,
  }) async {
    // 1. Fast in-memory check
    if (!forceRefresh) {
      final inMemory = _memCache[trackId];
      if (inMemory != null && inMemory.hasLyrics) {
        return inMemory;
      }
    }

    // 2. In-flight request deduplication
    if (!forceRefresh && _inFlight.containsKey(trackId)) {
      return _inFlight[trackId]!;
    }

    final future = _doFetchLyrics(
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      durationStr: durationStr,
      forceRefresh: forceRefresh,
    );

    _inFlight[trackId] = future;
    try {
      final res = await future;
      return res;
    } finally {
      _inFlight.remove(trackId);
    }
  }

  Future<LyricsResult> _doFetchLyrics({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    required String durationStr,
    required bool forceRefresh,
  }) async {
    // Check local Hive cache
    if (!forceRefresh) {
      final cached = StorageService.getLyrics(trackId);
      if (cached != null) {
        final res = LyricsResult.fromJson(cached);
        if (res.hasLyrics) {
          _memCache[trackId] = res;
          return res;
        }
      }
    }

    final durationSec = _parseDurationSeconds(durationStr);
    final cleanTitle = cleanTrackTitle(title);
    final cleanArtist = cleanArtistName(artist);

    // Tier 1: Try exact GET match without forcing album_name (albums often mismatch across providers)
    try {
      final getUri = Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
        if (durationSec > 0) 'duration': durationSec.toString(),
      });

      final response = await _dio.get(
        getUri.toString(),
        options: Options(
          receiveTimeout: const Duration(milliseconds: 2500),
          sendTimeout: const Duration(milliseconds: 2000),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final result = _parseLrclibObject(response.data);
        if (result != null && result.hasLyrics) {
          _memCache[trackId] = result;
          await StorageService.saveLyrics(trackId, result.toJson());
          return result;
        }
      }
    } catch (_) {}

    // Tier 2: Try fast full-text search with title + artist
    try {
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'q': '$cleanTitle $cleanArtist'.trim(),
      });

      final response = await _dio.get(
        searchUri.toString(),
        options: Options(
          receiveTimeout: const Duration(milliseconds: 3000),
          sendTimeout: const Duration(milliseconds: 2000),
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final result = _parseCandidateList(response.data as List, durationSec);
        if (result != null && result.hasLyrics) {
          _memCache[trackId] = result;
          await StorageService.saveLyrics(trackId, result.toJson());
          return result;
        }
      }
    } catch (_) {}

    // Tier 3: Try search with just clean title if title was modified or artist had special credits
    try {
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'q': cleanTitle,
      });

      final response = await _dio.get(
        searchUri.toString(),
        options: Options(
          receiveTimeout: const Duration(milliseconds: 2500),
          sendTimeout: const Duration(milliseconds: 2000),
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final result = _parseCandidateList(response.data as List, durationSec);
        if (result != null && result.hasLyrics) {
          _memCache[trackId] = result;
          await StorageService.saveLyrics(trackId, result.toJson());
          return result;
        }
      }
    } catch (_) {}

    // Return empty result without corrupting Hive cache with an empty entry
    final emptyResult = LyricsResult();
    return emptyResult;
  }

  LyricsResult? _parseCandidateList(List rawList, int durationSec) {
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

    if (candidates.isEmpty) return null;

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

    return LyricsResult(
      synced: syncedLines,
      plain: best.plainLyrics,
      instrumental: best.instrumental,
      candidates: candidates,
    );
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
    if (lyricsText.trim().isEmpty) return lyricsText;

    final cacheKey = 'translated_lyrics_${trackId}_$targetLanguage';
    final cached = StorageService.getSetting(cacheKey, defaultValue: null);
    if (cached != null && cached.toString().trim().isNotEmpty) {
      final cachedStr = cached.toString().trim();
      final originalClean = lyricsText.trim();
      final cachedLower = cachedStr.toLowerCase();
      // DO NOT return cache if it matches original untranslated lyrics or contains prompt leaks
      if (cachedStr != originalClean &&
          !cachedLower.contains('understand the source') &&
          !cachedLower.contains('role:') &&
          !cachedLower.contains('meaning:') &&
          !cachedLower.contains('explanation:') &&
          !cachedLower.contains('summary:') &&
          !cachedLower.contains('note:') &&
          !cachedLower.contains('here is the translation') &&
          !cachedLower.contains('here are the translated')) {
        return cachedStr;
      }
    }

    final String languageInstruction = targetLanguage.toLowerCase() == 'hinglish'
        ? 'Romanized Hinglish (transliterate into English/Latin alphabet, e.g. "Tere bina dil mera lagda nahi...")'
        : (targetLanguage.toLowerCase() == 'hindi' ? 'Hindi Devanagari (हिंदी)' : targetLanguage);

    final prompt = '''You are Google Translate. Translate the following song lyrics into $languageInstruction.

RULES:
- Translate EVERY line. One translated line per original line.
- Output ONLY raw translated lyric lines, nothing else.
- Do NOT add any notes, explanations, meanings, summaries, headers, bullet points, numbering, or commentary.
- Do NOT explain what the lyrics mean. Just translate the words.
- If target is Hinglish, write all lines in Latin/English script (romanized). Do NOT use Gurmukhi or Devanagari script.
- Keep the same number of lines as input.

$lyricsText''';

    try {
      final (response, _) = await AiService.instance.generate(prompt);
      if (response.trim().isNotEmpty) {
        String clean = response.trim();

        // Remove markdown code blocks if AI wrapped output in ```
        if (clean.startsWith('```')) {
          final lines = clean.split('\n');
          if (lines.length > 2 && lines.last.trim().startsWith('```')) {
            clean = lines.sublist(1, lines.length - 1).join('\n');
          } else if (lines.length > 1) {
            clean = lines.sublist(1).join('\n');
          }
        }

        final lines = clean.split('\n');
        final filteredLines = <String>[];
        for (final line in lines) {
          final l = line.trim();
          final lower = l.toLowerCase();
          if (lower.startsWith('**understand') ||
              lower.startsWith('**task') ||
              lower.startsWith('**role') ||
              lower.startsWith('**translation') ||
              lower.startsWith('**note') ||
              lower.startsWith('here is') ||
              lower.startsWith('here are') ||
              lower.startsWith('below is') ||
              lower.startsWith('the following') ||
              lower.startsWith('translation:') ||
              lower.startsWith('translated lyrics:') ||
              lower.startsWith('note:') ||
              lower.startsWith('meaning:') ||
              lower.startsWith('explanation:') ||
              lower.startsWith('summary:')) {
            continue;
          }
          final unnumbered = l.replaceFirst(RegExp(r'^\d+[\.\\)]\s*'), '');
          filteredLines.add(unnumbered);
        }

        final resultText = filteredLines.join('\n').trim();
        if (resultText.isNotEmpty && resultText != lyricsText.trim()) {
          await StorageService.saveSetting(cacheKey, resultText);
          return resultText;
        }
      }
    } catch (e) {
      debugPrint('[LyricsService] Translation failed: $e');
    }

    return lyricsText;
  }
}
