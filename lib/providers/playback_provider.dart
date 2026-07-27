import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import '../models/track.dart';
import '../services/storage/storage_service.dart';
import '../services/audio/audio_handler.dart';
import '../services/recommendation/recommendation_engine.dart';
import '../services/music_sources/jamendo_source.dart';
import '../providers/music_provider.dart';
import '../main.dart';

enum HapticFeedbackType { light, medium, heavy, selection }

void triggerHaptic([HapticFeedbackType type = HapticFeedbackType.light]) {
  if (StorageService.isHapticsEnabled()) {
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
    }
  }
}

// Repeat modes
enum RepeatMode { off, all, one }

class PlaybackState {
  final Track? currentTrack;
  final bool isPlaying;
  final double progress; // Between 0.0 and 1.0
  final Duration currentPosition;
  final Duration totalDuration;
  
  // Smart Queue states
  final List<Track> queue;
  final int currentIndex;
  final bool isShuffle;
  final RepeatMode repeatMode;
  
  // Customizations & Player modes
  final String playerSkin; // 'vinyl', 'cd', 'cassette', 'minimal'
  final bool volumeNormalization;
  final bool gaplessPlayback;
  final double playbackSpeed;
  final int? sleepTimerMinutes;
  final Duration? sleepTimerTimeRemaining;

  PlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.progress = 0.0,
    this.currentPosition = Duration.zero,
    this.totalDuration = const Duration(minutes: 3, seconds: 45),
    this.queue = const [],
    this.currentIndex = -1,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.off,
    this.playerSkin = 'vinyl',
    this.volumeNormalization = false,
    this.gaplessPlayback = true,
    this.playbackSpeed = 1.0,
    this.sleepTimerMinutes,
    this.sleepTimerTimeRemaining,
  });

  Duration get queueDuration {
    int totalMs = 0;
    for (final track in queue) {
      totalMs += _parseDurationMs(track.duration);
    }
    return Duration(milliseconds: totalMs);
  }

  int _parseDurationMs(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return (int.parse(parts[0]) * 60 + int.parse(parts[1])) * 1000;
      }
    } catch (_) {}
    return 180000; // Default 3 mins
  }

  PlaybackState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    double? progress,
    Duration? currentPosition,
    Duration? totalDuration,
    List<Track>? queue,
    int? currentIndex,
    bool? isShuffle,
    RepeatMode? repeatMode,
    String? playerSkin,
    bool? volumeNormalization,
    bool? gaplessPlayback,
    double? playbackSpeed,
    int? sleepTimerMinutes,
    Duration? sleepTimerTimeRemaining,
  }) {
    return PlaybackState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      progress: progress ?? this.progress,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      playerSkin: playerSkin ?? this.playerSkin,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      sleepTimerMinutes: sleepTimerMinutes ?? this.sleepTimerMinutes,
      sleepTimerTimeRemaining: sleepTimerTimeRemaining ?? this.sleepTimerTimeRemaining,
    );
  }
}

class PlaybackNotifier extends Notifier<PlaybackState> {
  late MyAudioHandler _handler;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  Timer? _sleepTimer;
  bool _isCrossfading = false;

  @override
  PlaybackState build() {
    _handler = ref.watch(audioHandlerProvider) as MyAudioHandler;

    // Bind stock notification and remote control action callbacks
    _handler.onNextRequested = () => nextTrack();
    _handler.onPreviousRequested = () => previousTrack();

    // Load saved settings from Hive
    final savedSkin = StorageService.getSetting('player_skin', defaultValue: 'vinyl') as String;
    final savedNorm = StorageService.getSetting('volume_normalization', defaultValue: false) as bool;
    final savedGapless = StorageService.getSetting('gapless_playback', defaultValue: true) as bool;
    final savedSpeed = StorageService.getSetting('playback_speed', defaultValue: 1.0) as double;

    // 1. Listen to position changes
    _posSub = _handler.player.positionStream.listen((pos) {
      final dur = state.totalDuration;
      final double progress = dur.inMilliseconds > 0
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      state = state.copyWith(
        currentPosition: pos,
        progress: progress,
      );
      
      // Save play position periodically in Hive
      if (state.currentTrack != null) {
        StorageService.saveSetting('playback_pos_${state.currentTrack!.id}', pos.inMilliseconds);
      }

      // Crossfade handling with equal-power overlapping transition
      if (StorageService.isCrossfadeEnabled() && dur.inMilliseconds > 0) {
        final crossfadeSec = StorageService.getCrossfadeDuration();
        final remainingMs = dur.inMilliseconds - pos.inMilliseconds;
        if (remainingMs > 0 && remainingMs <= (crossfadeSec * 1000) && !_isCrossfading) {
          _isCrossfading = true;
          nextTrack(isCrossfade: true);
          Future.delayed(Duration(seconds: crossfadeSec + 1), () {
            _isCrossfading = false;
          });
        }
      }
    });

    // 2. Listen to duration changes
    _durSub = _handler.player.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(totalDuration: dur);
      }
    });

    // 3. Listen to player state
    _stateSub = _handler.player.playerStateStream.listen((playerState) {
      state = state.copyWith(isPlaying: playerState.playing);
      
      // Auto-play next track on completion
      if (playerState.processingState == ProcessingState.completed) {
        nextTrack();
      }
    });

    // Load saved Queue State from Hive
    _loadSavedQueue(savedSkin, savedNorm, savedGapless, savedSpeed);

    // Clean up
    ref.onDispose(() {
      _posSub?.cancel();
      _durSub?.cancel();
      _stateSub?.cancel();
      _sleepTimer?.cancel();
    });

    return PlaybackState(
      playerSkin: savedSkin,
      volumeNormalization: savedNorm,
      gaplessPlayback: savedGapless,
      playbackSpeed: savedSpeed,
    );
  }

  void _loadSavedQueue(String skin, bool norm, bool gapless, double speed) {
    final saved = StorageService.getSavedQueueState();
    if (saved != null) {
      try {
        final List rawTracks = saved['tracks'] as List;
        final tracks = rawTracks.map((item) => Track(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? '',
          artist: item['artist']?.toString() ?? '',
          album: item['album']?.toString() ?? '',
          duration: item['duration']?.toString() ?? '',
          artworkUrl: item['artworkUrl']?.toString() ?? '',
          audioUrl: item['audioUrl']?.toString() ?? '',
          genre: item['genre']?.toString() ?? '',
        )).toList();
        
        final idx = saved['currentIndex'] as int? ?? -1;
        final shuffle = saved['isShuffle'] as bool? ?? false;
        final repeatVal = saved['repeatMode'] as int? ?? 0;
        final RepeatMode repeat = RepeatMode.values[repeatVal.clamp(0, 2)];

        Track? curr;
        if (tracks.isNotEmpty && idx >= 0 && idx < tracks.length) {
          curr = tracks[idx];
          
          // Restore position
          final posMs = StorageService.getSetting('playback_pos_${curr.id}', defaultValue: 0) as int;
          _handler.player.seek(Duration(milliseconds: posMs));
        }

        // Apply saved speed
        _handler.player.setSpeed(speed);

        state = PlaybackState(
          currentTrack: curr,
          queue: tracks,
          currentIndex: idx,
          isShuffle: shuffle,
          repeatMode: repeat,
          playerSkin: skin,
          volumeNormalization: norm,
          gaplessPlayback: gapless,
          playbackSpeed: speed,
        );
        ensureUpcomingRecommendations();
      } catch (e) {
        print('Failed to restore saved queue: $e');
      }
    } else {
      // Dynamic non-static initial state
      if (Track.mockTracks.isNotEmpty) {
        final pool = List<Track>.from(Track.mockTracks)..shuffle();
        final seedTrack = pool.first;
        state = PlaybackState(
          currentTrack: seedTrack,
          queue: [seedTrack],
          currentIndex: 0,
          playerSkin: skin,
          volumeNormalization: norm,
          gaplessPlayback: gapless,
          playbackSpeed: speed,
        );
        ensureUpcomingRecommendations();
      }
    }
  }

  Future<void> _saveQueue() async {
    await StorageService.saveQueueState(
      tracks: state.queue,
      currentIndex: state.currentIndex,
      isShuffle: state.isShuffle,
      repeatMode: state.repeatMode.index,
    );
  }

  // ── Smart Queue Controls ────────────────────────────────────

  void playTrack(Track track) async {
    triggerHaptic(HapticFeedbackType.selection);

    // Check if session context changed (e.g. user selected a song from a different genre)
    final prevContext = StorageService.getSessionContext();
    final newGenre = track.genre.trim().toUpperCase();
    final newArtist = track.artist.split(',').first.trim();

    bool contextPivoted = false;
    if (newGenre.isNotEmpty && prevContext['genre'] != null && prevContext['genre']!.isNotEmpty && prevContext['genre'] != newGenre) {
      contextPivoted = true;
    }

    // Record real-time telemetry and update session context in Hive DB
    RecommendationEngine.instance.recordTrackStarted(track);

    List<Track> currentQueue;
    int idx;

    if (contextPivoted) {
      // Rebuild clean queue starting with the new genre seed track
      currentQueue = [track];
      idx = 0;
    } else {
      currentQueue = List.from(state.queue);
      final titleKey = track.title.trim().toLowerCase();
      currentQueue.removeWhere((t) => t.id == track.id || t.title.trim().toLowerCase() == titleKey);

      idx = currentQueue.indexWhere((t) => t.id == track.id);
      if (idx == -1) {
        currentQueue.add(track);
        idx = currentQueue.length - 1;
      }

      // Re-rank upcoming tracks against the new current track context
      if (idx + 1 < currentQueue.length) {
        final upcoming = currentQueue.sublist(idx + 1);
        final reranked = RecommendationEngine.instance.rerankUpcomingQueue(upcoming, track);
        currentQueue = currentQueue.sublist(0, idx + 1)..addAll(reranked);
      }
    }
    
    state = state.copyWith(
      queue: currentQueue,
      currentIndex: idx,
      currentTrack: track,
    );
    await _saveQueue();

    String audioUrl = track.audioUrl;

    // Check if downloaded locally first
    final downloadedPath = StorageService.getDownloadedTrackPath(track.id);
    if (downloadedPath != null && File(downloadedPath).existsSync() && File(downloadedPath).lengthSync() > 0) {
      audioUrl = downloadedPath;
    } else {
      bool urlIsWorking = false;
      if (audioUrl.isNotEmpty && audioUrl.startsWith('http')) {
        try {
          final dio = Dio();
          final response = await dio.head(
            audioUrl,
            options: Options(validateStatus: (s) => s != null && s < 400),
          );
          if (response.statusCode == 200) {
            urlIsWorking = true;
          }
        } catch (_) {}
      }

      if (!urlIsWorking && !audioUrl.startsWith('/')) {
        print('🚨 Stale URL detected. Recovering fresh stream for ${track.title}...');
        try {
          final dio = Dio();
          final response = await dio.get('https://saavn.sumit.co/api/search/songs?query=${Uri.encodeComponent("${track.title} ${track.artist}")}');
          final results = response.data['data']?['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final freshUrl = results.first['downloadUrl']?.last['url']?.toString() ?? '';
            if (freshUrl.isNotEmpty) {
              audioUrl = freshUrl;
              
              // Healed track update
              final healed = Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                artworkUrl: track.artworkUrl,
                audioUrl: freshUrl,
                genre: track.genre,
              );
              currentQueue[idx] = healed;
              state = state.copyWith(queue: currentQueue, currentTrack: healed);
              await _saveQueue();
            }
          }
        } catch (_) {}
      }
    }

    if (audioUrl.isNotEmpty) {
      try {
        // Track stats for History/Recently Played Box
        await StorageService.addListeningHistory(track, state.currentPosition.inSeconds.toDouble());
        
        await _handler.playTrack(track.copyWith(audioUrl: audioUrl));

        // Preload next track in queue & ensure upcoming recommendations filled
        _preloadNextTrack();
        ensureUpcomingRecommendations();
      } catch (e) {
        print('ExoPlayer play failed: $e');
      }
    }
  }

  Future<void> ensureUpcomingRecommendations() async {
    if (state.currentTrack == null) return;
    
    int remainingUpcoming = state.queue.length - (state.currentIndex + 1);
    if (remainingUpcoming >= 5) return;

    try {
      // Use contextual recommendations anchored to the current track
      final source = ref.read(musicSourceProvider);
      List<Track> recommendations;
      if (source is JamendoSource) {
        recommendations = await source.getContextualRecommendations(state.currentTrack!);
      } else {
        recommendations = await source.getDynamicRecommendations();
      }

      if (recommendations.isEmpty) {
        String genreQuery = state.currentTrack!.genre.trim();
        if (genreQuery.isEmpty) genreQuery = 'PUNJABI';
        recommendations = await source.getTracksByGenre(genreQuery);
      }

      final Set<String> existingTitles = state.queue.map((t) => t.title.trim().toLowerCase()).toSet();
      List<Track> ranked = RecommendationEngine.instance.rankRecommendations(
        recommendations,
        currentTrack: state.currentTrack,
        excludeIds: existingTitles,
      );

      if (ranked.isEmpty) {
        final freshBatch = await source.getDynamicRecommendations();
        ranked = RecommendationEngine.instance.rankRecommendations(
          freshBatch,
          currentTrack: state.currentTrack,
          excludeIds: existingTitles,
        );
      }

      if (ranked.isNotEmpty) {
        final needed = 5 - remainingUpcoming;
        final toAdd = ranked.take(needed).toList();
        final updatedQueue = List<Track>.from(state.queue)..addAll(toAdd);
        state = state.copyWith(queue: updatedQueue);
        await _saveQueue();
      }
    } catch (e) {
      print('Error filling upcoming recommendations: $e');
    }
  }

  Future<void> _preloadNextTrack() async {
    final nextIdx = state.currentIndex + 1;
    if (nextIdx < state.queue.length) {
      final nextTrackItem = state.queue[nextIdx];
      final localPath = StorageService.getDownloadedTrackPath(nextTrackItem.id);
      if (localPath == null || !File(localPath).existsSync()) {
        try {
          if (nextTrackItem.audioUrl.isEmpty) {
            final dio = Dio();
            final response = await dio.get('https://saavn.sumit.co/api/search/songs?query=${Uri.encodeComponent("${nextTrackItem.title} ${nextTrackItem.artist}")}');
            final results = response.data['data']?['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final freshUrl = results.first['downloadUrl']?.last['url']?.toString() ?? '';
              if (freshUrl.isNotEmpty) {
                final List<Track> updatedQueue = List.from(state.queue);
                updatedQueue[nextIdx] = nextTrackItem.copyWith(audioUrl: freshUrl);
                state = state.copyWith(queue: updatedQueue);
                _saveQueue();
              }
            }
          }
        } catch (_) {}
      }
    }
  }

  void addToQueue(Track track) {
    List<Track> updated = List.from(state.queue);
    final titleKey = track.title.trim().toLowerCase();
    updated.removeWhere((t) => t.id == track.id || t.title.trim().toLowerCase() == titleKey);
    final insertIdx = (state.currentIndex >= 0 && state.currentIndex < updated.length)
        ? state.currentIndex + 1
        : updated.length;
    updated.insert(insertIdx, track);
    state = state.copyWith(queue: updated);
    _saveQueue();
  }

  void playNext(Track track) {
    addToQueue(track);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;
    List<Track> updated = List.from(state.queue);
    updated.removeAt(index);
    
    int newIdx = state.currentIndex;
    if (index == state.currentIndex) {
      newIdx = updated.isEmpty ? -1 : (index < updated.length ? index : updated.length - 1);
    } else if (index < state.currentIndex) {
      newIdx--;
    }
    
    state = state.copyWith(
      queue: updated,
      currentIndex: newIdx,
      currentTrack: newIdx != -1 ? updated[newIdx] : null,
    );
    _saveQueue();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    List<Track> updated = List.from(state.queue);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    
    // Adjust current index
    int newIdx = state.currentIndex;
    if (oldIndex == state.currentIndex) {
      newIdx = newIndex;
    } else if (oldIndex < state.currentIndex && newIndex >= state.currentIndex) {
      newIdx--;
    } else if (oldIndex > state.currentIndex && newIndex <= state.currentIndex) {
      newIdx++;
    }

    state = state.copyWith(queue: updated, currentIndex: newIdx);
    _saveQueue();
  }

  void clearQueue() {
    state = state.copyWith(
      queue: state.currentTrack != null ? [state.currentTrack!] : [],
      currentIndex: state.currentTrack != null ? 0 : -1,
    );
    _saveQueue();
  }

  void toggleShuffle() {
    final nextShuffle = !state.isShuffle;
    state = state.copyWith(isShuffle: nextShuffle);
    
    if (nextShuffle && state.queue.isNotEmpty) {
      // Shuffle the queue list, keeping current track at index 0 or preserving index
      List<Track> shuffled = List.from(state.queue);
      final current = state.currentTrack;
      if (current != null) {
        shuffled.removeWhere((t) => t.id == current.id);
        shuffled.shuffle();
        shuffled.insert(0, current);
        state = state.copyWith(queue: shuffled, currentIndex: 0);
      }
    }
    _saveQueue();
  }

  void setRepeatMode(RepeatMode mode) {
    state = state.copyWith(repeatMode: mode);
    _saveQueue();
  }

  Future<void> _autoPlayNextRecommended() async {
    final current = state.currentTrack;
    if (current == null) return;

    // Prune queue if too long to maintain responsive state
    List<Track> workingQueue = List.from(state.queue);
    int workingIdx = state.currentIndex;
    if (workingIdx > 5) {
      workingQueue = workingQueue.sublist(workingIdx - 5);
      workingIdx = 5;
      state = state.copyWith(queue: workingQueue, currentIndex: workingIdx);
    }

    try {
      final source = ref.read(musicSourceProvider);
      List<Track> recommendations = await source.getDynamicRecommendations();

      final Set<String> existingIds = workingQueue.map((t) => t.id).toSet();
      final Set<String> existingTitles = workingQueue.map((t) => t.title.trim().toLowerCase()).toSet();

      List<Track> ranked = RecommendationEngine.instance.rankRecommendations(
        recommendations,
        currentTrack: current,
        excludeIds: existingTitles,
      );

      // If all candidates in current batch were excluded, query fresh dynamic recommendations again
      if (ranked.isEmpty) {
        final freshBatch = await source.getDynamicRecommendations();
        freshBatch.shuffle();
        ranked = RecommendationEngine.instance.rankRecommendations(
          freshBatch,
          currentTrack: current,
          excludeIds: existingTitles,
        );

        if (ranked.isEmpty && freshBatch.isNotEmpty) {
          ranked = freshBatch.where((t) => !existingTitles.contains(t.title.trim().toLowerCase())).toList();
        }
      }

      Track? nextTrackToPlay;
      if (ranked.isNotEmpty) {
        nextTrackToPlay = ranked.first;
      } else if (recommendations.isNotEmpty) {
        final unplayed = recommendations.where((t) => !existingTitles.contains(t.title.trim().toLowerCase())).toList();
        if (unplayed.isNotEmpty) {
          unplayed.shuffle();
          nextTrackToPlay = unplayed.first;
        } else {
          // Generate dynamic variation if all songs have been played
          final sample = (List.from(recommendations)..shuffle()).first;
          nextTrackToPlay = sample.copyWith(
            id: '${sample.id}_${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      }

      if (nextTrackToPlay != null) {
        final updatedQueue = List<Track>.from(state.queue)..add(nextTrackToPlay);
        final nextIdx = updatedQueue.length - 1;
        state = state.copyWith(
          queue: updatedQueue,
          currentIndex: nextIdx,
          currentTrack: nextTrackToPlay,
        );
        await _saveQueue();
        playTrack(nextTrackToPlay);
      }
    } catch (e) {
      print('Error auto-playing next recommended: $e');
    }
  }

  bool _isSwitchingTrack = false;

  void nextTrack({bool isCrossfade = false}) async {
    if (state.queue.isEmpty || _isSwitchingTrack) return;
    _isSwitchingTrack = true;
    
    try {
      // Log previous track telemetry and handle skip realignments
      if (state.currentTrack != null) {
        final skippedTrack = state.currentTrack!;
        final playedSec = state.currentPosition.inSeconds;

        RecommendationEngine.instance.recordTrackEnded(
          skippedTrack,
          state.currentPosition,
          state.totalDuration,
        );

        // If skipped early (< 30s), treat as negative feedback
        if (playedSec < 30) {
          final skippedGenre = skippedTrack.genre.trim().toUpperCase();
          final skippedArtist = skippedTrack.artist.split(',').first.trim();

          // Check if the skipped song's genre differs from the active session
          final sessionCtx = StorageService.getSessionContext();
          final activeGenre = sessionCtx['genre'] ?? '';

          if (skippedGenre.isNotEmpty && activeGenre.isNotEmpty && skippedGenre != activeGenre) {
            // Skipped a mismatched genre — purge all tracks of that genre from upcoming queue
            if (state.currentIndex + 1 < state.queue.length) {
              List<Track> cleanedQueue = List.from(state.queue);
              final upcoming = cleanedQueue.sublist(state.currentIndex + 1);
              upcoming.removeWhere((t) => t.genre.trim().toUpperCase() == skippedGenre);
              cleanedQueue = cleanedQueue.sublist(0, state.currentIndex + 1)..addAll(upcoming);
              state = state.copyWith(queue: cleanedQueue);
            }
          } else if (skippedGenre.isNotEmpty && state.currentIndex + 1 < state.queue.length) {
            // Skipped within same genre — re-rank upcoming to deprioritize similar tracks
            List<Track> cleanedQueue = List.from(state.queue);
            final upcoming = cleanedQueue.sublist(state.currentIndex + 1);
            // Remove tracks by the same skipped artist
            upcoming.removeWhere((t) => t.artist.split(',').first.trim().toLowerCase() == skippedArtist.toLowerCase());
            cleanedQueue = cleanedQueue.sublist(0, state.currentIndex + 1)..addAll(upcoming);
            state = state.copyWith(queue: cleanedQueue);
          }
        }
      }

      if (state.repeatMode == RepeatMode.one && state.currentTrack != null) {
        playTrack(state.currentTrack!);
        return;
      }

      int nextIdx = state.currentIndex + 1;
      if (nextIdx >= state.queue.length) {
        if (state.repeatMode == RepeatMode.all) {
          nextIdx = 0;
        } else {
          await _autoPlayNextRecommended();
          return;
        }
      }

      final nextTrackItem = state.queue[nextIdx];

      if (isCrossfade && StorageService.isCrossfadeEnabled()) {
        state = state.copyWith(
          currentIndex: nextIdx,
          currentTrack: nextTrackItem,
        );
        await _saveQueue();
        final crossfadeSec = StorageService.getCrossfadeDuration();
        await _handler.crossfadeToTrack(nextTrackItem, crossfadeSec);
        _preloadNextTrack();
        ensureUpcomingRecommendations();
      } else {
        playTrack(nextTrackItem);
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 350), () {
        _isSwitchingTrack = false;
      });
    }
  }

  void previousTrack() {
    if (state.queue.isEmpty || _isSwitchingTrack) return;
    _isSwitchingTrack = true;
    
    try {
      int prevIdx = state.currentIndex - 1;
      if (prevIdx < 0) {
        if (state.repeatMode == RepeatMode.all) {
          prevIdx = state.queue.length - 1;
        } else {
          prevIdx = 0;
        }
      }
      playTrack(state.queue[prevIdx]);
    } finally {
      Future.delayed(const Duration(milliseconds: 350), () {
        _isSwitchingTrack = false;
      });
    }
  }

  // ── Audio Core Modifiers ────────────────────────────────────

  void togglePlay() {
    _handler.player.playing ? _handler.pause() : _handler.play();
  }

  void seek(double progress) {
    final totalMs = state.totalDuration.inMilliseconds;
    final targetMs = (totalMs * progress).toInt();
    _handler.seek(Duration(milliseconds: targetMs));
  }

  void setPlaybackSpeed(double speed) {
    state = state.copyWith(playbackSpeed: speed);
    _handler.player.setSpeed(speed);
    StorageService.saveSetting('playback_speed', speed);
  }

  void toggleVolumeNormalization() {
    final next = !state.volumeNormalization;
    state = state.copyWith(volumeNormalization: next);
    // Standard volume normalization by applying a peak limit or lowering base volume
    _handler.player.setVolume(next ? 0.75 : 1.0);
    StorageService.saveSetting('volume_normalization', next);
  }

  void toggleGaplessPlayback() {
    final next = !state.gaplessPlayback;
    state = state.copyWith(gaplessPlayback: next);
    StorageService.saveSetting('gapless_playback', next);
  }

  void setPlayerSkin(String skin) {
    state = state.copyWith(playerSkin: skin);
    StorageService.saveSetting('player_skin', skin);
  }

  // ── Sleep Timer ─────────────────────────────────────────────

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    state = state.copyWith(
      sleepTimerMinutes: minutes,
      sleepTimerTimeRemaining: Duration(minutes: minutes),
    );
    
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.sleepTimerTimeRemaining;
      if (remaining == null || remaining.inSeconds <= 1) {
        // Timer fired! Stop player
        _handler.pause();
        cancelSleepTimer();
      } else {
        state = state.copyWith(
          sleepTimerTimeRemaining: remaining - const Duration(seconds: 1),
        );
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    state = state.copyWith(
      sleepTimerMinutes: null,
      sleepTimerTimeRemaining: null,
    );
  }

  /// Called when user likes/favorites a track — boosts affinity and re-ranks queue
  void onTrackLiked(Track track) {
    RecommendationEngine.instance.recordTrackLiked(track);

    // Re-rank upcoming queue with boosted affinities
    if (state.currentTrack != null && state.currentIndex + 1 < state.queue.length) {
      final upcoming = List<Track>.from(state.queue.sublist(state.currentIndex + 1));
      final reranked = RecommendationEngine.instance.rerankUpcomingQueue(upcoming, state.currentTrack!);
      final updatedQueue = List<Track>.from(state.queue.sublist(0, state.currentIndex + 1))..addAll(reranked);
      state = state.copyWith(queue: updatedQueue);
      _saveQueue();
    }

    // Trigger fresh recommendations to fill queue with similar content
    ensureUpcomingRecommendations();
  }
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(() {
  return PlaybackNotifier();
});
