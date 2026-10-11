import 'track.dart';

class PlaylistTrack {
  final String id;
  final String source; // "jiosaavn" | "youtube"
  final String trackId;
  final String title;
  final String artist;
  final String artworkUrl;
  final int durationMs;
  final String addedByUid;
  final String addedByName;
  final DateTime addedAt;

  const PlaylistTrack({
    required this.id,
    required this.source,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.durationMs,
    required this.addedByUid,
    required this.addedByName,
    required this.addedAt,
  });

  factory PlaylistTrack.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PlaylistTrack(
      id: map['id'] as String? ?? '',
      source: (map['source'] as String? ?? 'jiosaavn').toLowerCase(),
      trackId: map['trackId'] as String? ?? '',
      title: map['title'] as String? ?? 'Unknown Title',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      artworkUrl: map['artworkUrl'] as String? ?? '',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      addedByUid: map['addedByUid'] as String? ?? '',
      addedByName: map['addedByName'] as String? ?? 'Aura User',
      addedAt: parseDate(map['addedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source,
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'durationMs': durationMs,
      'addedByUid': addedByUid,
      'addedByName': addedByName,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  /// Converts this Firestore playlist track to the app's player [Track] model.
  Track toTrack() {
    final isYt = source == 'youtube';
    final actualId = isYt && !trackId.startsWith('yt_') ? 'yt_$trackId' : trackId;
    
    // Format duration string e.g. "3:45"
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final durationStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Track(
      id: actualId,
      title: title,
      artist: artist,
      album: '',
      duration: durationMs > 0 ? durationStr : '3:30',
      artworkUrl: artworkUrl,
      audioUrl: '', // Resloved on play by playback service
      genre: '',
      source: isYt ? 'youtube' : 'jiosaavn',
      youtubeVideoId: isYt ? trackId : null,
      addedBy: addedByName,
    );
  }

  /// Creates a [PlaylistTrack] from the app's [Track] model.
  factory PlaylistTrack.fromTrack(
    Track track, {
    required String addedByUid,
    required String addedByName,
    String? entryId,
  }) {
    final isYt = track.isYouTube;
    String cleanTrackId = track.youtubeVideoId ?? track.id;
    if (cleanTrackId.startsWith('yt_')) {
      cleanTrackId = cleanTrackId.substring(3);
    }

    // Parse duration string if available
    int parsedDurationMs = 0;
    try {
      final parts = track.duration.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        parsedDurationMs = (m * 60 + s) * 1000;
      }
    } catch (_) {}

    final finalAddedByName = (track.addedBy != null && track.addedBy!.trim().isNotEmpty)
        ? track.addedBy!.trim()
        : (addedByName.trim().isNotEmpty ? addedByName.trim() : 'Aura Listener');

    return PlaylistTrack(
      id: entryId ?? '${DateTime.now().millisecondsSinceEpoch}_${cleanTrackId.hashCode.abs()}',
      source: isYt ? 'youtube' : 'jiosaavn',
      trackId: cleanTrackId,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: parsedDurationMs,
      addedByUid: addedByUid,
      addedByName: finalAddedByName,
      addedAt: DateTime.now(),
    );
  }
}
