import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import '../models/track.dart';
import '../services/storage/storage_service.dart';
import '../services/audio/audio_handler.dart';
import '../main.dart';

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

  @override
  PlaybackState build() {
    _handler = ref.watch(audioHandlerProvider) as MyAudioHandler;

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
      } catch (_) {}
    } else {
      // Default initial state
      if (Track.mockTracks.isNotEmpty) {
        state = PlaybackState(
          currentTrack: Track.mockTracks[0],
          queue: List.from(Track.mockTracks),
          currentIndex: 0,
          playerSkin: skin,
          volumeNormalization: norm,
          gaplessPlayback: gapless,
          playbackSpeed: speed,
        );
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
    // Add to queue if not present, and update index
    List<Track> currentQueue = List.from(state.queue);
    int idx = currentQueue.indexWhere((t) => t.id == track.id);
    if (idx == -1) {
      currentQueue.add(track);
      idx = currentQueue.length - 1;
    }
    
    state = state.copyWith(
      queue: currentQueue,
      currentIndex: idx,
      currentTrack: track,
    );
    await _saveQueue();

    // Verify & Stream audio URL
    String audioUrl = track.audioUrl;
    bool urlIsWorking = false;
    if (audioUrl.isNotEmpty) {
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

    if (!urlIsWorking) {
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

    if (audioUrl.isNotEmpty) {
      try {
        // Track stats for History/Recently Played Box
        await StorageService.addListeningHistory(track, state.currentPosition.inSeconds.toDouble());
        
        await _handler.playTrack(track.copyWith(audioUrl: audioUrl));
      } catch (e) {
        print('ExoPlayer play failed: $e');
      }
    }
  }

  void addToQueue(Track track) {
    if (state.queue.any((t) => t.id == track.id)) return;
    final List<Track> updated = List.from(state.queue)..add(track);
    state = state.copyWith(queue: updated);
    _saveQueue();
  }

  void playNext(Track track) {
    List<Track> updated = List.from(state.queue);
    updated.removeWhere((t) => t.id == track.id);
    final insertIdx = state.currentIndex + 1;
    if (insertIdx >= updated.length) {
      updated.add(track);
    } else {
      updated.insert(insertIdx, track);
    }
    state = state.copyWith(queue: updated);
    _saveQueue();
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

  void nextTrack() {
    if (state.queue.isEmpty) return;
    
    if (state.repeatMode == RepeatMode.one && state.currentTrack != null) {
      // Repeat one
      playTrack(state.currentTrack!);
      return;
    }

    int nextIdx = state.currentIndex + 1;
    if (nextIdx >= state.queue.length) {
      if (state.repeatMode == RepeatMode.all) {
        nextIdx = 0;
      } else {
        return; // End of playback
      }
    }
    
    playTrack(state.queue[nextIdx]);
  }

  void previousTrack() {
    if (state.queue.isEmpty) return;
    int prevIdx = state.currentIndex - 1;
    if (prevIdx < 0) {
      if (state.repeatMode == RepeatMode.all) {
        prevIdx = state.queue.length - 1;
      } else {
        prevIdx = 0;
      }
    }
    playTrack(state.queue[prevIdx]);
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
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(() {
  return PlaybackNotifier();
});
