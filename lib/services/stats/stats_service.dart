import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/track.dart';
import '../auth/auth_service.dart';

class StatsService {
  static final StatsService instance = StatsService._();
  StatsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Local in-memory buffer
  int _pendingListens = 0;
  final Map<String, int> _pendingArtists = {};
  final Map<String, int> _pendingDaily = {};

  // Track progress guard to count a song at most once per playback session
  String? _currentlyTrackedSongId;
  bool _countedCurrentSong = false;

  // Keys for persistence across app restarts
  static const String _kPendingListensKey = 'pending_stats_listens_count';
  static const String _kPendingArtistsKey = 'pending_stats_artists_map';
  static const String _kPendingDailyKey = 'pending_stats_daily_map';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingListens = prefs.getInt(_kPendingListensKey) ?? 0;
      
      final artistsJson = prefs.getString(_kPendingArtistsKey);
      if (artistsJson != null) {
        final decoded = jsonDecode(artistsJson) as Map<String, dynamic>;
        decoded.forEach((k, v) => _pendingArtists[k] = (v as num).toInt());
      }

      final dailyJson = prefs.getString(_kPendingDailyKey);
      if (dailyJson != null) {
        final decoded = jsonDecode(dailyJson) as Map<String, dynamic>;
        decoded.forEach((k, v) => _pendingDaily[k] = (v as num).toInt());
      }
    } catch (e) {
      debugPrint('Error loading buffered stats: $e');
    }
  }

  /// Evaluates whether the currently playing song meets the listen threshold
  /// (at least 30 seconds OR 50% of duration, whichever comes first).
  void onPlaybackProgress(Track track, Duration position, Duration? totalDuration) {
    if (_currentlyTrackedSongId != track.id) {
      _currentlyTrackedSongId = track.id;
      _countedCurrentSong = false;
    }

    if (_countedCurrentSong) return;

    final seconds = position.inSeconds;
    final totalSec = totalDuration?.inSeconds ?? 0;

    final met30Sec = seconds >= 30;
    final met50Percent = totalSec > 0 && (position.inMilliseconds >= (totalDuration!.inMilliseconds / 2));

    if (met30Sec || met50Percent) {
      _countedCurrentSong = true;
      _recordListen(track);
    }
  }

  void onSongCompleted(Track track) {
    if (!_countedCurrentSong && _currentlyTrackedSongId == track.id) {
      _countedCurrentSong = true;
      _recordListen(track);
    }
  }

  void _recordListen(Track track) {
    _pendingListens += 1;

    // Record artist
    final artist = track.artist.trim();
    if (artist.isNotEmpty && artist.toLowerCase() != 'unknown artist') {
      _pendingArtists[artist] = (_pendingArtists[artist] ?? 0) + 1;
    }

    // Record daily listen under YYYY-MM-DD
    final now = DateTime.now();
    final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _pendingDaily[dateKey] = (_pendingDaily[dateKey] ?? 0) + 1;

    _persistBufferLocally();

    // Flush every 10 listens
    if (_pendingListens >= 10) {
      flushPendingStats();
    }
  }

  Future<void> _persistBufferLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPendingListensKey, _pendingListens);
      await prefs.setString(_kPendingArtistsKey, jsonEncode(_pendingArtists));
      await prefs.setString(_kPendingDailyKey, jsonEncode(_pendingDaily));
    } catch (_) {}
  }

  /// Flushes pending stats to Firestore.
  /// Cost: 1 read + 1 write.
  Future<void> flushPendingStats() async {
    final uid = AuthService.instance.currentUserId;
    if (uid.isEmpty || _pendingListens <= 0) return;

    final listensToFlush = _pendingListens;
    final artistsToFlush = Map<String, int>.from(_pendingArtists);
    final dailyToFlush = Map<String, int>.from(_pendingDaily);

    // Reset local buffers
    _pendingListens = 0;
    _pendingArtists.clear();
    _pendingDaily.clear();
    await _persistBufferLocally();

    try {
      final docRef = _firestore.collection('users').doc(uid);
      // Cost: 1 read
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final existingStats = data['stats'] as Map<String, dynamic>? ?? {};

      // Merge total listens
      final existingTotal = (existingStats['totalSongsPlayed'] as num?)?.toInt() ?? 0;
      final newTotal = existingTotal + listensToFlush;

      // Merge and cap top artists at 20
      final existingArtistsRaw = existingStats['topArtists'] as Map<dynamic, dynamic>? ?? {};
      final mergedArtists = <String, int>{};
      existingArtistsRaw.forEach((k, v) {
        if (k != null && v is num) mergedArtists[k.toString()] = v.toInt();
      });

      artistsToFlush.forEach((artist, count) {
        mergedArtists[artist] = (mergedArtists[artist] ?? 0) + count;
      });

      // Sort by play count descending and cap to top 20
      final sortedArtistEntries = mergedArtists.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final cappedArtists = <String, int>{};
      for (var i = 0; i < sortedArtistEntries.length && i < 20; i++) {
        cappedArtists[sortedArtistEntries[i].key] = sortedArtistEntries[i].value;
      }

      final favoriteArtist = cappedArtists.isNotEmpty ? cappedArtists.keys.first : null;

      // Merge and prune daily listens (keep last 30 days only)
      final existingDailyRaw = existingStats['dailyListens'] as Map<dynamic, dynamic>? ?? {};
      final mergedDaily = <String, int>{};
      existingDailyRaw.forEach((k, v) {
        if (k != null && v is num) mergedDaily[k.toString()] = v.toInt();
      });

      dailyToFlush.forEach((date, count) {
        mergedDaily[date] = (mergedDaily[date] ?? 0) + count;
      });

      // Prune keys older than 30 days
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      mergedDaily.removeWhere((dateStr, _) {
        try {
          final parsed = DateTime.parse(dateStr);
          return parsed.isBefore(cutoffDate);
        } catch (_) {
          return true;
        }
      });

      // Cost: 1 write
      await docRef.update({
        'stats.totalSongsPlayed': newTotal,
        'stats.topArtists': cappedArtists,
        'stats.favoriteArtist': favoriteArtist,
        'stats.dailyListens': mergedDaily,
      });

      debugPrint('StatsService: Flushed $listensToFlush listens to Firestore.');
    } catch (e) {
      debugPrint('StatsService: Error flushing stats, restoring buffer: $e');
      // Restore buffer on failure so no listens are lost
      _pendingListens += listensToFlush;
      artistsToFlush.forEach((k, v) => _pendingArtists[k] = (_pendingArtists[k] ?? 0) + v);
      dailyToFlush.forEach((k, v) => _pendingDaily[k] = (_pendingDaily[k] ?? 0) + v);
      await _persistBufferLocally();
    }
  }
}
