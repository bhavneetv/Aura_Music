import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/track.dart';
import '../services/storage/storage_service.dart';
import '../services/audio/audio_handler.dart';
import '../services/audio/audio_url_resolver.dart';
import '../services/recommendation/recommendation_engine.dart';
import '../services/music_sources/jamendo_source.dart';
import '../services/voice/voice_assistant_service.dart';
import '../services/quick_actions/quick_actions_service.dart';
import '../services/sync/multi_device_sync_service.dart';
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

// Queue item origin tagging
enum QueueSource { user, recommendation }

class PlaybackState {
  final Track? currentTrack;
  final bool isPlaying;
  final double progress; // Between 0.0 and 1.0
  final Duration currentPosition;
  final Duration totalDuration;
  
  // Smart Queue states
  final List<Track> queue;
  final Map<String, QueueSource> queueSources;
  final int currentIndex;
  final bool isShuffle;
  final RepeatMode repeatMode;
  
  // Customizations & Player modes
  final String playerSkin; // 'vinyl', 'cd', 'cassette', 'minimal'
  final String playerScreenTheme; // 'normal' or 'minimal_theme'
  final bool volumeNormalization;
  final bool gaplessPlayback;
  final double playbackSpeed;
  final int? sleepTimerMinutes;
  final Duration? sleepTimerTimeRemaining;
  final bool isSleepTimerEndOfTrack;

  // State machine fields
  final PlaybackStatus status;
  final bool playRequested;

  PlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.progress = 0.0,
    this.currentPosition = Duration.zero,
    this.totalDuration = const Duration(minutes: 3, seconds: 45),
    this.queue = const [],
    this.queueSources = const {},
    this.currentIndex = -1,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.off,
    this.playerSkin = 'minimal',
    this.playerScreenTheme = 'normal',
    this.volumeNormalization = false,
    this.gaplessPlayback = true,
    this.playbackSpeed = 1.0,
    this.sleepTimerMinutes,
    this.sleepTimerTimeRemaining,
    this.isSleepTimerEndOfTrack = false,
    this.status = PlaybackStatus.idle,
    this.playRequested = false,
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
    Map<String, QueueSource>? queueSources,
    int? currentIndex,
    bool? isShuffle,
    RepeatMode? repeatMode,
    String? playerSkin,
    String? playerScreenTheme,
    bool? volumeNormalization,
    bool? gaplessPlayback,
    double? playbackSpeed,
    int? sleepTimerMinutes,
    Duration? sleepTimerTimeRemaining,
    bool? isSleepTimerEndOfTrack,
    PlaybackStatus? status,
    bool? playRequested,
  }) {
    return PlaybackState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      progress: progress ?? this.progress,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      queue: queue ?? this.queue,
      queueSources: queueSources ?? this.queueSources,
      currentIndex: currentIndex ?? this.currentIndex,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      playerSkin: playerSkin ?? this.playerSkin,
      playerScreenTheme: playerScreenTheme ?? this.playerScreenTheme,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      sleepTimerMinutes: sleepTimerMinutes ?? this.sleepTimerMinutes,
      sleepTimerTimeRemaining: sleepTimerTimeRemaining ?? this.sleepTimerTimeRemaining,
      isSleepTimerEndOfTrack: isSleepTimerEndOfTrack ?? this.isSleepTimerEndOfTrack,
      status: status ?? this.status,
      playRequested: playRequested ?? this.playRequested,
    );
  }
}

enum PlaybackStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  completed,
  error,
}

class _TransitionLock {
  bool _isLocked = false;
  Completer<void>? _completer;

  Future<void> acquire() async {
    final stopwatch = Stopwatch()..start();
    while (_isLocked) {
      if (stopwatch.elapsedMilliseconds > 3000) {
        print('[AURA-PLAY] Lock acquire timeout, breaking lock');
        _isLocked = false; // Break deadlock
        break;
      }
      _completer ??= Completer<void>();
      await Future.any([
        _completer!.future,
        Future.delayed(const Duration(milliseconds: 500)), // periodic check
      ]);
    }
    _isLocked = true;
  }

  void release() {
    _isLocked = false;
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
      _completer = null;
    }
  }
}

class PlaybackNotifier extends Notifier<PlaybackState> {
  late MyAudioHandler _handler;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  Timer? _sleepTimer;
  Timer? _watchdogTimer;

  bool _isCrossfading = false;
  bool _isTransitioning = false;
  bool _isNextTrackPreloaded = false;
  int _playbackNonce = 0;
  // Nonce snapshot at the time the last completed event fired,
  // used to deduplicate multiple completed events for the same track.
  int _lastCompletedNonce = -1;
  int _trackLoadRetries = 0;

  final _TransitionLock _lock = _TransitionLock();

  Duration? _lastPosition;
  DateTime? _lastPositionChangeTime;

  @override
  PlaybackState build() {
    _handler = ref.watch(audioHandlerProvider) as MyAudioHandler;

    // Bind stock notification and remote control action callbacks
    _handler.onNextRequested = () => nextTrack();
    _handler.onPreviousRequested = () => previousTrack();

    // Load saved settings from Hive (default to minimal cover art skin)
    final savedSkin = StorageService.getSetting('player_skin', defaultValue: 'minimal') as String;
    final savedScreenTheme = StorageService.getSetting('player_screen_theme', defaultValue: 'normal') as String;
    final savedNorm = StorageService.getSetting('volume_normalization', defaultValue: false) as bool;
    final savedGapless = StorageService.getSetting('gapless_playback', defaultValue: true) as bool;
    final savedSpeed = StorageService.getSetting('playback_speed', defaultValue: 1.0) as double;

    // 1. Listen to position changes
    _posSub = _handler.activePositionStream.listen((pos) {
      final dur = state.totalDuration;
      final double progress = dur.inMilliseconds > 0
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      state = state.copyWith(
        currentPosition: pos,
        progress: progress,
      );

      // Notify multi-device sync host position beacon
      try {
        final syncService = MultiDeviceSyncService.instance;
        if (syncService.role == SyncRole.host) {
          syncService.notifyHostPosition(
            position: pos,
            isPlaying: state.isPlaying,
            currentTrack: state.currentTrack,
          );
        } else if (syncService.role == SyncRole.follower) {
          syncService.updateFollowerLocalPosition(pos.inMilliseconds);
        }
      } catch (_) {}
      
      // Save play position periodically in Hive
      if (state.currentTrack != null) {
        StorageService.saveSetting('playback_pos_${state.currentTrack!.id}', pos.inMilliseconds);
      }

      // Preload next track audio immediately as soon as track starts playing for zero-latency gapless & crossfade playback
      if (state.isPlaying && !_isTransitioning && pos.inSeconds >= 2 && !_isNextTrackPreloaded) {
        final nextIdx = state.currentIndex + 1;
        if (nextIdx < state.queue.length) {
          final nextTrack = state.queue[nextIdx];
          if (nextTrack.audioUrl.isNotEmpty && 
              (nextTrack.audioUrl.startsWith('http') || File(nextTrack.audioUrl).existsSync())) {
            _isNextTrackPreloaded = true;
            _handler.preloadNextTrack(nextTrack);
          }
        }
      }

      // Crossfade handling with equal-power overlapping transition.
      // The _isCrossfading flag is only reset when the crossfade completes
      // inside nextTrack(), not via an arbitrary timer.
      if (StorageService.isCrossfadeEnabled() && state.isPlaying && !_isTransitioning && dur.inMilliseconds > 0 && !_isCrossfading) {
        final crossfadeSec = StorageService.getCrossfadeDuration();
        final durSec = dur.inSeconds;
        final maxCrossfadeForTrack = math.max(1, (durSec / 2).floor());
        final effectiveCrossfadeSec = math.min(crossfadeSec, maxCrossfadeForTrack);

        final remainingMs = dur.inMilliseconds - pos.inMilliseconds;
        if (durSec > 2 && remainingMs > 0 && remainingMs <= (effectiveCrossfadeSec * 1000)) {
          _isCrossfading = true;
          nextTrack(isCrossfade: true);
        }
      }
    });

    // 2. Listen to duration changes
    _durSub = _handler.activeDurationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(totalDuration: dur);
      }
    });

    // 3. Listen to player state
    _stateSub = _handler.activePlayerStateStream.listen((playerState) {
      final status = _mapPlayerState(playerState);
      final isPlaying = playerState.playing;

      state = state.copyWith(
        isPlaying: isPlaying,
        status: status,
        playRequested: isPlaying ? true : state.playRequested,
      );
      
      _handler.logPlaybackEvent(
        eventName: 'PLAYER_STATE_CHANGE_EVENT',
        error: 'playing=$isPlaying, state=${playerState.processingState.toString()}, nonce=$_playbackNonce',
      );

      // Auto-play next track on completion.
      // Uses _lastCompletedNonce to deduplicate: only fires if the current
      // nonce hasn't already triggered a completion handler.
      if (playerState.processingState == ProcessingState.completed) {
        final currentNonce = _playbackNonce;
        if (currentNonce != _lastCompletedNonce) {
          _lastCompletedNonce = currentNonce;
          _isCrossfading = false; // Reset crossfade flag when a track reaches completion
          _handler.logPlaybackEvent(
            eventName: 'AUTO_ADVANCE_TRIGGERED',
            error: 'nonce=$currentNonce, _isTransitioning=$_isTransitioning',
          );
          nextTrack(isAutoAdvance: true);
        }
      }
    });

    // 4. Setup Playback Health Watchdog Timer (diagnostic logging only)
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkPlaybackHealth();
    });

    // Load saved Queue State from Hive
    _loadSavedQueue(savedSkin, savedNorm, savedGapless, savedSpeed);

    // Clean up
    ref.onDispose(() {
      _posSub?.cancel();
      _durSub?.cancel();
      _stateSub?.cancel();
      _sleepTimer?.cancel();
      _watchdogTimer?.cancel();
    });

    return PlaybackState(
      playerSkin: savedSkin,
      playerScreenTheme: savedScreenTheme,
      volumeNormalization: savedNorm,
      gaplessPlayback: savedGapless,
      playbackSpeed: savedSpeed,
    );
  }

  PlaybackStatus _mapPlayerState(PlayerState playerState) {
    switch (playerState.processingState) {
      case ProcessingState.idle:
        return PlaybackStatus.idle;
      case ProcessingState.loading:
        return PlaybackStatus.loading;
      case ProcessingState.buffering:
        return PlaybackStatus.buffering;
      case ProcessingState.ready:
        return playerState.playing ? PlaybackStatus.playing : PlaybackStatus.ready;
      case ProcessingState.completed:
        return PlaybackStatus.completed;
    }
  }

  /// Diagnostic-only watchdog: logs warnings if playback appears stuck.
  /// Does NOT auto-recover or auto-skip — the root cause fixes in the
  /// transition logic should prevent stuck states from occurring.
  void _checkPlaybackHealth() {
    final track = state.currentTrack;
    if (track == null) return;

    final now = DateTime.now();
    
    if (state.playRequested && state.isPlaying) {
      final currentPos = state.currentPosition;
      if (_lastPosition != null && _lastPosition == currentPos) {
        final stuckDuration = now.difference(_lastPositionChangeTime ?? now);
        if (stuckDuration.inSeconds >= 8) {
          _handler.logPlaybackEvent(
            eventName: 'WATCHDOG_STUCK_DETECTED',
            currentTrackId: track.id,
            error: 'Position stuck at ${currentPos.inMilliseconds}ms for ${stuckDuration.inSeconds}s. _isTransitioning=$_isTransitioning, _isCrossfading=$_isCrossfading, nonce=$_playbackNonce',
          );
          // Reset the timer so we don't spam logs
          _lastPositionChangeTime = now;
        }
      } else {
        _lastPosition = currentPos;
        _lastPositionChangeTime = now;
      }
    } else {
      _lastPosition = null;
      _lastPositionChangeTime = null;
    }
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
          
          final posMs = StorageService.getSetting('playback_pos_${curr.id}', defaultValue: 0) as int;
          _handler.player.seek(Duration(milliseconds: posMs));
        }

        _handler.player.setSpeed(speed);

        state = PlaybackState(
          currentTrack: curr,
          totalDuration: curr != null ? _parseDuration(curr.duration) : const Duration(minutes: 3),
          queue: tracks,
          currentIndex: idx,
          isShuffle: shuffle,
          repeatMode: repeat,
          playerSkin: skin,
          volumeNormalization: norm,
          gaplessPlayback: gapless,
          playbackSpeed: speed,
          status: PlaybackStatus.idle,
          playRequested: false,
        );
        _handler.syncQueue(tracks);
        if (curr != null) {
          _handler.updateTrackMediaItem(curr);
        }
        ensureUpcomingRecommendations();
      } catch (e) {
        print('Failed to restore saved queue: $e');
      }
    } else {
      Future.microtask(() async {
        try {
          final source = ref.read(musicSourceProvider);
          final recs = await source.getDynamicRecommendations();
          if (recs.isNotEmpty) {
            final seedTrack = recs.first;
            state = PlaybackState(
              currentTrack: seedTrack,
              totalDuration: _parseDuration(seedTrack.duration),
              queue: recs,
              currentIndex: 0,
              playerSkin: skin,
              volumeNormalization: norm,
              gaplessPlayback: gapless,
              playbackSpeed: speed,
              status: PlaybackStatus.idle,
              playRequested: false,
            );
            _handler.syncQueue(recs);
            _handler.updateTrackMediaItem(seedTrack);
            _saveQueue();
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _saveQueue() async {
    await StorageService.saveQueueState(
      tracks: state.queue,
      currentIndex: state.currentIndex,
      isShuffle: state.isShuffle,
      repeatMode: state.repeatMode.index,
    );
    _handler.syncQueue(state.queue);
    if (state.currentTrack != null) {
      _handler.updateTrackMediaItem(state.currentTrack!);
    }
    QuickActionsService.instance.updateShortcuts();
  }

  void resumePlayback() {
    if (state.isPlaying) return;
    if (state.currentTrack != null) {
      _handler.updateTrackMediaItem(state.currentTrack!);
      _handler.syncQueue(state.queue);
      if (state.status == PlaybackStatus.paused || state.status == PlaybackStatus.ready) {
        _handler.play();
        state = state.copyWith(isPlaying: true, status: PlaybackStatus.playing);
      } else {
        playTrack(state.currentTrack!);
      }
    } else if (state.queue.isNotEmpty) {
      jumpToQueueIndex(state.currentIndex >= 0 ? state.currentIndex : 0);
    } else {
      shuffleAll();
    }
  }

  void shuffleAll() async {
    List<Track> pool = StorageService.getFavoriteTracks();
    if (pool.isEmpty) {
      pool = StorageService.getFullDownloadedTracks();
    }
    if (pool.isEmpty) {
      try {
        final source = ref.read(musicSourceProvider);
        pool = await source.getDynamicRecommendations();
      } catch (_) {}
    }
    if (pool.isEmpty) {
      pool = List.from(Track.mockTracks);
    }
    pool.shuffle();
    playCustomQueue(pool, initialIndex: 0);
    if (!state.isShuffle) {
      state = state.copyWith(isShuffle: true);
    }
  }

  void playRecentPlaylist() async {
    final playlists = StorageService.getPlaylists();
    if (playlists.isNotEmpty) {
      final first = playlists.first;
      final rawTracks = first['tracks'] as List? ?? [];
      if (rawTracks.isNotEmpty) {
        final tracks = rawTracks.map((item) => Track(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? 'Track',
          artist: item['artist']?.toString() ?? 'Unknown Artist',
          album: item['album']?.toString() ?? 'Album',
          duration: item['duration']?.toString() ?? '3:30',
          artworkUrl: item['artworkUrl']?.toString() ?? '',
          audioUrl: item['audioUrl']?.toString() ?? '',
          genre: item['genre']?.toString() ?? '',
        )).toList();
        playCustomQueue(tracks, initialIndex: 0);
        return;
      }
    }

    final downloadedPlaylists = StorageService.getDownloadedPlaylists();
    if (downloadedPlaylists.isNotEmpty) {
      final first = downloadedPlaylists.first;
      final rawTracks = first['tracks'] as List? ?? [];
      if (rawTracks.isNotEmpty) {
        final tracks = rawTracks.map((item) => Track(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? 'Track',
          artist: item['artist']?.toString() ?? 'Unknown Artist',
          album: item['album']?.toString() ?? 'Album',
          duration: item['duration']?.toString() ?? '3:30',
          artworkUrl: item['artworkUrl']?.toString() ?? '',
          audioUrl: item['audioUrl']?.toString() ?? '',
          genre: item['genre']?.toString() ?? '',
        )).toList();
        playCustomQueue(tracks, initialIndex: 0);
        return;
      }
    }

    final favs = StorageService.getFavoriteTracks();
    if (favs.isNotEmpty) {
      playCustomQueue(favs, initialIndex: 0);
      return;
    }

    shuffleAll();
  }

  bool _isLocalTrack(Track track) {
    if (track.audioUrl.isNotEmpty && !track.audioUrl.startsWith('http')) {
      final file = File(track.audioUrl);
      if (file.existsSync() && file.lengthSync() > 0) return true;
    }
    final downloadedPath = StorageService.getDownloadedTrackPath(track.id);
    if (downloadedPath != null && downloadedPath.isNotEmpty) {
      final file = File(downloadedPath);
      if (file.existsSync() && file.lengthSync() > 0) return true;
    }
    return false;
  }

  Track _resolveSingleTrackWithLocalDownload(Track track) {
    final downloadedAudio = StorageService.getDownloadedTrackPath(track.id);
    final downloadedArt = StorageService.getDownloadedArtworkPath(track.id);

    String audioUrl = track.audioUrl;
    if (downloadedAudio != null && File(downloadedAudio).existsSync() && File(downloadedAudio).lengthSync() > 0) {
      audioUrl = downloadedAudio;
    }

    String artworkUrl = track.artworkUrl;
    if (downloadedArt != null && File(downloadedArt).existsSync() && File(downloadedArt).lengthSync() > 0) {
      artworkUrl = downloadedArt;
    }

    if (audioUrl != track.audioUrl || artworkUrl != track.artworkUrl) {
      return track.copyWith(audioUrl: audioUrl, artworkUrl: artworkUrl);
    }
    return track;
  }

  List<Track> _resolveTracksWithLocalDownloads(List<Track> tracks) {
    return tracks.map((t) => _resolveSingleTrackWithLocalDownload(t)).toList();
  }

  Future<bool> _checkIsOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none) || results.isEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  void playCustomQueue(List<Track> tracks, {int initialIndex = 0}) async {
    if (tracks.isEmpty) return;

    final resolvedTracks = _resolveTracksWithLocalDownloads(tracks);
    final offline = await _checkIsOffline();

    List<Track> finalQueue = resolvedTracks;
    if (offline) {
      final downloadedOnly = resolvedTracks.where((t) => _isLocalTrack(t)).toList();
      if (downloadedOnly.isNotEmpty) {
        finalQueue = downloadedOnly;
      } else {
        finalQueue = StorageService.getFullDownloadedTracks();
      }
    }

    if (finalQueue.isEmpty) return;

    final targetTrackCandidate = resolvedTracks[initialIndex.clamp(0, resolvedTracks.length - 1)];
    int safeIndex = finalQueue.indexWhere((t) => t.id == targetTrackCandidate.id);
    if (safeIndex == -1) safeIndex = 0;

    final targetTrack = finalQueue[safeIndex];

    final newSources = <String, QueueSource>{};
    for (final track in finalQueue) {
      newSources[track.id] = QueueSource.user;
    }

    _isTransitioning = true;
    final myNonce = ++_playbackNonce;

    state = state.copyWith(
      queue: List<Track>.from(finalQueue),
      currentIndex: safeIndex,
      currentTrack: targetTrack,
      totalDuration: _parseDuration(targetTrack.duration),
      queueSources: newSources,
      playRequested: true,
      status: PlaybackStatus.loading,
    );
    await _saveQueue();

    try {
      await _streamTrack(targetTrack, nonce: myNonce);
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> jumpToQueueIndex(int index, {int? nonce}) async {
    if (index < 0 || index >= state.queue.length) return;
    
    final myNonce = nonce ?? ++_playbackNonce;
    if (nonce == null) {
      _isTransitioning = true;
    }
    
    final targetTrack = _resolveSingleTrackWithLocalDownload(state.queue[index]);
    
    state = state.copyWith(
      currentIndex: index,
      currentTrack: targetTrack,
      totalDuration: _parseDuration(targetTrack.duration),
      playRequested: true,
      status: PlaybackStatus.loading,
    );
    await _saveQueue();
    
    try {
      await _streamTrack(targetTrack, nonce: myNonce);
    } finally {
      if (nonce == null) {
        _isTransitioning = false;
      }
    }
  }

  void playTrack(Track track) async {
    final resolvedTrack = _resolveSingleTrackWithLocalDownload(track);
    final offline = await _checkIsOffline();

    if (offline && !_isLocalTrack(resolvedTrack)) {
      final downloadedTracks = StorageService.getFullDownloadedTracks();
      if (downloadedTracks.isNotEmpty) {
        playCustomQueue(downloadedTracks, initialIndex: 0);
        return;
      }
    }

    List<Track> currentQueue = _resolveTracksWithLocalDownloads(state.queue);
    int idx = currentQueue.indexWhere((t) => t.id == resolvedTrack.id || (t.title.trim().toLowerCase() == resolvedTrack.title.trim().toLowerCase() && t.artist.trim().toLowerCase() == resolvedTrack.artist.trim().toLowerCase()));

    if (idx != -1) {
      currentQueue[idx] = resolvedTrack;
      if (offline) {
        currentQueue = currentQueue.where((t) => _isLocalTrack(t)).toList();
        idx = currentQueue.indexWhere((t) => t.id == resolvedTrack.id);
        if (idx == -1) idx = 0;
      }
      jumpToQueueIndex(idx);
      return;
    }

    final prevContext = StorageService.getSessionContext();
    final newGenre = resolvedTrack.genre.trim().toUpperCase();

    bool contextPivoted = false;
    if (newGenre.isNotEmpty && prevContext['genre'] != null && prevContext['genre']!.isNotEmpty && prevContext['genre'] != newGenre) {
      contextPivoted = true;
    }

    if (contextPivoted || currentQueue.isEmpty) {
      currentQueue = [resolvedTrack];
      idx = 0;
    } else {
      final insertPosition = (state.currentIndex >= 0 && state.currentIndex < currentQueue.length)
          ? state.currentIndex + 1
          : currentQueue.length;
      currentQueue.insert(insertPosition, resolvedTrack);
      idx = insertPosition;
    }

    if (offline) {
      currentQueue = currentQueue.where((t) => _isLocalTrack(t)).toList();
      idx = currentQueue.indexWhere((t) => t.id == resolvedTrack.id);
      if (idx == -1) {
        currentQueue.insert(0, resolvedTrack);
        idx = 0;
      }
    }
    
    final newSources = Map<String, QueueSource>.from(state.queueSources);
    newSources[resolvedTrack.id] = QueueSource.user;
    
    _isTransitioning = true;
    final myNonce = ++_playbackNonce;

    state = state.copyWith(
      queue: currentQueue,
      currentIndex: idx,
      currentTrack: resolvedTrack,
      totalDuration: _parseDuration(resolvedTrack.duration),
      queueSources: newSources,
      playRequested: true,
      status: PlaybackStatus.loading,
    );
    await _saveQueue();

    try {
      await _streamTrack(resolvedTrack, nonce: myNonce);
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _streamTrack(Track track, {required int nonce}) async {
    _trackLoadRetries = 0;
    _isNextTrackPreloaded = false; // Reset preload state for the new track
    triggerHaptic(HapticFeedbackType.selection);
    RecommendationEngine.instance.recordTrackStarted(track);

    final resolvedTrack = _resolveSingleTrackWithLocalDownload(track);
    track = resolvedTrack;
    _handler.updateTrackMediaItem(track);
    _handler.syncQueue(state.queue);
    String audioUrl = track.audioUrl;
    if (audioUrl.contains('saavncdn.com') && audioUrl.contains('_320.')) {
      audioUrl = audioUrl.replaceAll('_320.', '_160.');
    }

    final downloadedPath = StorageService.getDownloadedTrackPath(track.id);
    if (downloadedPath != null && File(downloadedPath).existsSync() && File(downloadedPath).lengthSync() > 0) {
      audioUrl = downloadedPath;
    }

    if (nonce != _playbackNonce) {
      print('[AURA-PLAY] Aborting playback for "${track.title}" before resolution (nonce mismatch)');
      return;
    }

    // Only resolve fresh working URL if audioUrl is completely empty or invalid
    if (audioUrl.isEmpty || (!audioUrl.startsWith('http') && !File(audioUrl).existsSync())) {
      print('[AURA-PLAY] Resolving audioUrl for "${track.title}" (id: ${track.id})...');
      final resolved = await AudioUrlResolver.instance.resolveAudioUrl(track, forceFresh: false);
      
      if (nonce != _playbackNonce) {
        print('[AURA-PLAY] Stale resolution for "${track.title}" (user changed song), discarding');
        return;
      }

      if (resolved != null && resolved.isNotEmpty) {
        audioUrl = resolved;
        track = track.copyWith(audioUrl: audioUrl);
        final updatedQueue = List<Track>.from(state.queue);
        if (state.currentIndex >= 0 && state.currentIndex < updatedQueue.length) {
          updatedQueue[state.currentIndex] = track;
        }
        state = state.copyWith(queue: updatedQueue, currentTrack: track);
        await _saveQueue();
      }
    }

    if (audioUrl.isNotEmpty) {
      try {
        await StorageService.addListeningHistory(track, state.currentPosition.inSeconds.toDouble());
        
        if (nonce != _playbackNonce) {
          print('[AURA-PLAY] Stale playback for "${track.title}" (user changed song), discarding');
          return;
        }

        state = state.copyWith(status: PlaybackStatus.loading);
        await _handler.playTrack(track.copyWith(audioUrl: audioUrl));

        if (nonce != _playbackNonce) {
          print('[AURA-PLAY] Playback started but nonce changed, letting it be handled by the new transition');
          return;
        }

        _trackLoadRetries = 0;
        state = state.copyWith(
          status: PlaybackStatus.playing,
          isPlaying: true,
        );

        VoiceAssistantService.instance.donateTrack(track);
        VoiceAssistantService.instance.syncLibraryIndexToPlatform();

        _preloadUpcomingTracks();
        ensureUpcomingRecommendations();
      } catch (e) {
        print('[AURA-PLAY] Initial playback failed for "${track.title}": $e');
        if (e.toString().contains('Loading interrupted')) return;
        if (nonce != _playbackNonce) return;

        _trackLoadRetries++;
        if (_trackLoadRetries > 2) {
          _handler.logPlaybackEvent(
            eventName: 'PLAYBACK_MAX_RETRIES_EXCEEDED',
            currentTrackId: track.id,
            error: 'Failed 3 times. Skipping track.',
          );
          _trackLoadRetries = 0;
          nextTrack();
          return;
        }

        try {
          final resolvedUrl = await AudioUrlResolver.instance.resolveAudioUrl(track, forceFresh: true);
          if (nonce != _playbackNonce) return;
          
          if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
            print('[AURA-PLAY] Retrying with resolved URL: $resolvedUrl');
            final resolvedTrack = track.copyWith(audioUrl: resolvedUrl);
            
            await _handler.playTrack(resolvedTrack);
            
            if (nonce != _playbackNonce) return;

            final updatedQueue = List<Track>.from(state.queue);
            if (state.currentIndex >= 0 && state.currentIndex < updatedQueue.length) {
              updatedQueue[state.currentIndex] = resolvedTrack;
            }
            state = state.copyWith(
              queue: updatedQueue, 
              currentTrack: resolvedTrack,
              status: PlaybackStatus.playing,
              isPlaying: true,
            );
            await _saveQueue();
            _preloadUpcomingTracks();
            ensureUpcomingRecommendations();
            return;
          }
        } catch (resolveErr) {
          print('[AURA-PLAY] AudioUrlResolver fallback also failed: $resolveErr');
        }

        if (nonce != _playbackNonce) return;
        state = state.copyWith(
          status: PlaybackStatus.error,
          isPlaying: false,
        );
        // Automatically skip unplayable track
        if (nonce == _playbackNonce && state.status == PlaybackStatus.error) {
          nextTrack(isAutoAdvance: true);
        }
      }
    } else {
      print('[AURA-PLAY] Could not resolve playable audioUrl for "${track.title}"');
      if (nonce != _playbackNonce) return;

      _trackLoadRetries++;
      if (_trackLoadRetries > 2) {
        _handler.logPlaybackEvent(
          eventName: 'PLAYBACK_RESOLVE_MAX_RETRIES_EXCEEDED',
          currentTrackId: track.id,
          error: 'Failed 3 times resolving URL. Skipping.',
        );
        _trackLoadRetries = 0;
        nextTrack();
        return;
      }

      state = state.copyWith(
        status: PlaybackStatus.error,
        isPlaying: false,
      );
      // Automatically skip unplayable track
      if (nonce == _playbackNonce && state.status == PlaybackStatus.error) {
        nextTrack(isAutoAdvance: true);
      }
    }
  }

  Future<void> ensureUpcomingRecommendations() async {
    if (state.currentTrack == null) return;
    
    int remainingUpcoming = state.queue.length - (state.currentIndex + 1);
    if (remainingUpcoming >= 5) return;

    final offline = await _checkIsOffline();
    if (offline) {
      final fullDownloads = StorageService.getFullDownloadedTracks();
      if (fullDownloads.isNotEmpty) {
        final currentQueueIds = state.queue.map((t) => t.id).toSet();
        final unplayedOffline = fullDownloads.where((t) => !currentQueueIds.contains(t.id)).toList();

        if (unplayedOffline.isNotEmpty) {
          final needed = 5 - remainingUpcoming;
          final toAdd = unplayedOffline.take(needed).toList();
          final updatedQueue = List<Track>.from(state.queue)..addAll(toAdd);

          final updatedSources = Map<String, QueueSource>.from(state.queueSources);
          for (final track in toAdd) {
            updatedSources[track.id] = QueueSource.recommendation;
          }

          state = state.copyWith(queue: updatedQueue, queueSources: updatedSources);
          await _saveQueue();
        }
      }
      return;
    }

    try {
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

      final Set<String> currentQueueTitles = state.queue.map((t) => t.title.trim().toLowerCase()).toSet();
      final Set<String> existingTitles = Set<String>.from(currentQueueTitles);

      final history = StorageService.getListeningHistory();
      for (var item in history) {
        if (item['title'] != null) {
          existingTitles.add(item['title'].toString().trim().toLowerCase());
        }
      }

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
        
        if (ranked.isEmpty) {
           ranked = RecommendationEngine.instance.rankRecommendations(
             freshBatch.isNotEmpty ? freshBatch : recommendations,
             currentTrack: state.currentTrack,
             excludeIds: currentQueueTitles,
           );
        }
      }

      if (ranked.isNotEmpty) {
        final needed = 5 - remainingUpcoming;
        final toAdd = ranked.take(needed).toList();
        final updatedQueue = List<Track>.from(state.queue)..addAll(toAdd);

        final updatedSources = Map<String, QueueSource>.from(state.queueSources);
        for (final track in toAdd) {
          updatedSources[track.id] = QueueSource.recommendation;
        }

        state = state.copyWith(queue: updatedQueue, queueSources: updatedSources);
        await _saveQueue();
      }
    } catch (e) {
      print('Error filling upcoming recommendations: $e');
    }
  }

  Future<void> _preloadUpcomingTracks() async {
    final curIdx = state.currentIndex;
    if (curIdx < 0) return;
    final endIdx = math.min(state.queue.length, curIdx + 4);

    for (int nextIdx = curIdx + 1; nextIdx < endIdx; nextIdx++) {
      final nextTrackItem = state.queue[nextIdx];
      final localPath = StorageService.getDownloadedTrackPath(nextTrackItem.id);
      if (localPath == null || !File(localPath).existsSync()) {
        try {
          final freshUrl = await AudioUrlResolver.instance.resolveAudioUrl(nextTrackItem, forceFresh: false);
          if (freshUrl != null && freshUrl.isNotEmpty && freshUrl != nextTrackItem.audioUrl) {
            final List<Track> updatedQueue = List.from(state.queue);
            if (nextIdx < updatedQueue.length) {
              updatedQueue[nextIdx] = nextTrackItem.copyWith(audioUrl: freshUrl);
              state = state.copyWith(queue: updatedQueue);
              _saveQueue();
            }
          }
        } catch (_) {}
      }
    }
  }

  void addToQueue(Track track, {QueueSource source = QueueSource.user}) {
    List<Track> updated = List.from(state.queue);
    final titleKey = track.title.trim().toLowerCase();
    updated.removeWhere((t) => t.id == track.id || t.title.trim().toLowerCase() == titleKey);
    final insertIdx = (state.currentIndex >= 0 && state.currentIndex < updated.length)
        ? state.currentIndex + 1
        : updated.length;
    updated.insert(insertIdx, track);

    final updatedSources = Map<String, QueueSource>.from(state.queueSources);
    updatedSources[track.id] = source;

    state = state.copyWith(queue: updated, queueSources: updatedSources);
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
    
    if (newIndex == 0 || newIndex == updated.length - 1) {
      _triggerTripleLightHaptic();
    } else {
      triggerHaptic(HapticFeedbackType.light);
    }

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

  Duration _parseDuration(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      } else if (parts.length == 3) {
        return Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]), seconds: int.parse(parts[2]));
      }
    } catch (_) {}
    return const Duration(minutes: 3);
  }

  void _triggerTripleLightHaptic() async {
    for (int i = 0; i < 3; i++) {
      triggerHaptic(HapticFeedbackType.light);
      await Future.delayed(const Duration(milliseconds: 40));
    }
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

  Future<void> _autoPlayNextRecommended({required int nonce}) async {
    final current = state.currentTrack;
    if (current == null) return;

    if (nonce != _playbackNonce) return;

    final offline = await _checkIsOffline();
    if (offline) {
      final fullDownloads = StorageService.getFullDownloadedTracks();
      if (fullDownloads.isNotEmpty) {
        final currentQueueIds = state.queue.map((t) => t.id).toSet();
        List<Track> unplayedOffline = fullDownloads.where((t) => !currentQueueIds.contains(t.id)).toList();

        if (unplayedOffline.isEmpty) {
          unplayedOffline = List.from(fullDownloads)..shuffle();
        }

        if (unplayedOffline.isNotEmpty) {
          final nextOfflineTrack = unplayedOffline.first;
          final updatedQueue = List<Track>.from(state.queue)..add(nextOfflineTrack);
          final nextIdx = updatedQueue.length - 1;

          final updatedSources = Map<String, QueueSource>.from(state.queueSources);
          updatedSources[nextOfflineTrack.id] = QueueSource.recommendation;

          state = state.copyWith(
            queue: updatedQueue,
            currentIndex: nextIdx,
            currentTrack: nextOfflineTrack,
            queueSources: updatedSources,
          );
          await _saveQueue();
          await _streamTrack(nextOfflineTrack, nonce: nonce);
          return;
        }
      }
    }

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

      if (nonce != _playbackNonce) return;

      final Set<String> currentQueueTitles = workingQueue.map((t) => t.title.trim().toLowerCase()).toSet();
      final Set<String> existingTitles = Set<String>.from(currentQueueTitles);

      final history = StorageService.getListeningHistory();
      for (var item in history) {
        if (item['title'] != null) {
          existingTitles.add(item['title'].toString().trim().toLowerCase());
        }
      }

      List<Track> ranked = RecommendationEngine.instance.rankRecommendations(
        recommendations,
        currentTrack: current,
        excludeIds: existingTitles,
      );

      if (ranked.isEmpty) {
        final freshBatch = await source.getDynamicRecommendations();
        if (nonce != _playbackNonce) return;
        freshBatch.shuffle();
        ranked = RecommendationEngine.instance.rankRecommendations(
          freshBatch,
          currentTrack: current,
          excludeIds: existingTitles,
        );

        if (ranked.isEmpty && freshBatch.isNotEmpty) {
          ranked = freshBatch.where((t) => !existingTitles.contains(t.title.trim().toLowerCase())).toList();
        }

        if (ranked.isEmpty) {
           ranked = RecommendationEngine.instance.rankRecommendations(
             freshBatch.isNotEmpty ? freshBatch : recommendations,
             currentTrack: current,
             excludeIds: currentQueueTitles,
           );
           if (ranked.isEmpty && freshBatch.isNotEmpty) {
             ranked = freshBatch.where((t) => !currentQueueTitles.contains(t.title.trim().toLowerCase())).toList();
           }
        }
      }

      Track? nextTrackToPlay;
      if (ranked.isNotEmpty) {
        nextTrackToPlay = ranked.first;
      } else if (recommendations.isNotEmpty) {
        final unplayed = recommendations.where((t) => !currentQueueTitles.contains(t.title.trim().toLowerCase())).toList();
        if (unplayed.isNotEmpty) {
          unplayed.shuffle();
          nextTrackToPlay = unplayed.first;
        } else {
          final sample = (List.from(recommendations)..shuffle()).first;
          nextTrackToPlay = sample.copyWith(
            id: '${sample.id}_${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      }

      if (nextTrackToPlay != null) {
        if (nonce != _playbackNonce) return;

        final updatedQueue = List<Track>.from(state.queue)..add(nextTrackToPlay);
        final nextIdx = updatedQueue.length - 1;

        final updatedSources = Map<String, QueueSource>.from(state.queueSources);
        updatedSources[nextTrackToPlay.id] = QueueSource.recommendation;

        state = state.copyWith(
          queue: updatedQueue,
          currentIndex: nextIdx,
          currentTrack: nextTrackToPlay,
          queueSources: updatedSources,
        );
        await _saveQueue();
        await _streamTrack(nextTrackToPlay, nonce: nonce);
      }
    } catch (e) {
      print('Error auto-playing next recommended: $e');
    }
  }

  Future<void> nextTrack({bool isCrossfade = false, bool isAutoAdvance = false}) async {
    if (state.queue.isEmpty) return;
    
    _isTransitioning = true;
    final myNonce = ++_playbackNonce;
    
    _handler.logPlaybackEvent(
      eventName: 'NEXT_TRACK_REQUESTED',
      queueIndex: state.currentIndex,
      error: 'isCrossfade=$isCrossfade, isAutoAdvance=$isAutoAdvance, nonce=$myNonce',
    );

    if (state.isSleepTimerEndOfTrack) {
      triggerHaptic(HapticFeedbackType.medium);
      await _handler.pause();
      cancelSleepTimer();
      _isTransitioning = false;
      return;
    }
    
    await _lock.acquire();
    try {
      if (_playbackNonce != myNonce) return;

      if (state.currentTrack != null) {
        final skippedTrack = state.currentTrack!;
        final playedSec = state.currentPosition.inSeconds;

        RecommendationEngine.instance.recordTrackEnded(
          skippedTrack,
          state.currentPosition,
          state.totalDuration,
        );

        if (playedSec < 30) {
          final skippedGenre = skippedTrack.genre.trim().toUpperCase();
          final skippedArtist = skippedTrack.artist.split(',').first.trim();

          final sessionCtx = StorageService.getSessionContext();
          final activeGenre = sessionCtx['genre'] ?? '';

          if (skippedGenre.isNotEmpty && activeGenre.isNotEmpty && skippedGenre != activeGenre) {
            if (state.currentIndex + 1 < state.queue.length) {
              List<Track> cleanedQueue = List.from(state.queue);
              final upcoming = cleanedQueue.sublist(state.currentIndex + 1);
              upcoming.removeWhere((t) => t.genre.trim().toUpperCase() == skippedGenre);
              cleanedQueue = cleanedQueue.sublist(0, state.currentIndex + 1)..addAll(upcoming);
              state = state.copyWith(queue: cleanedQueue);
            }
          } else if (skippedGenre.isNotEmpty && state.currentIndex + 1 < state.queue.length) {
            List<Track> cleanedQueue = List.from(state.queue);
            final upcoming = cleanedQueue.sublist(state.currentIndex + 1);
            upcoming.removeWhere((t) => t.artist.split(',').first.trim().toLowerCase() == skippedArtist.toLowerCase());
            cleanedQueue = cleanedQueue.sublist(0, state.currentIndex + 1)..addAll(upcoming);
            state = state.copyWith(queue: cleanedQueue);
          }
        }
      }

      if (state.repeatMode == RepeatMode.one && state.currentTrack != null && isAutoAdvance) {
        await _streamTrack(state.currentTrack!, nonce: myNonce);
        return;
      }

      int nextIdx = state.currentIndex + 1;
      if (nextIdx >= state.queue.length) {
        if (state.repeatMode == RepeatMode.all) {
          nextIdx = 0;
        } else {
          await _autoPlayNextRecommended(nonce: myNonce);
          return;
        }
      }

      final nextTrackItem = state.queue[nextIdx];

      if (isCrossfade && StorageService.isCrossfadeEnabled()) {
        var targetTrack = nextTrackItem;
        String audioUrl = targetTrack.audioUrl;
        if (audioUrl.contains('saavncdn.com') && audioUrl.contains('_320.')) {
          audioUrl = audioUrl.replaceAll('_320.', '_160.');
        }
        final downloadedPath = StorageService.getDownloadedTrackPath(targetTrack.id);
        if (downloadedPath != null && File(downloadedPath).existsSync() && File(downloadedPath).lengthSync() > 0) {
          audioUrl = downloadedPath;
        }

        if (audioUrl.isEmpty || (!audioUrl.startsWith('http') && !File(audioUrl).existsSync())) {
          _handler.logPlaybackEvent(
            eventName: 'CROSSFADE_RESOLVING_URL',
            currentTrackId: targetTrack.id,
          );
          final resolved = await AudioUrlResolver.instance.resolveAudioUrl(targetTrack, forceFresh: true);
          if (myNonce != _playbackNonce) return; // aborted by a newer transition request
          if (resolved != null && resolved.isNotEmpty) {
            audioUrl = resolved;
            targetTrack = targetTrack.copyWith(audioUrl: audioUrl);
            final updatedQueue = List<Track>.from(state.queue);
            if (nextIdx >= 0 && nextIdx < updatedQueue.length) {
              updatedQueue[nextIdx] = targetTrack;
            }
            state = state.copyWith(queue: updatedQueue, currentTrack: targetTrack);
            await _saveQueue();
          }
        }

        if (audioUrl.isNotEmpty) {
          final crossfadeSec = StorageService.getCrossfadeDuration();
          final durSec = state.totalDuration.inSeconds;
          final effectiveCrossfadeSec = math.min(crossfadeSec, math.max(1, (durSec / 2).floor()));

          final success = await _handler.crossfadeToTrack(
            targetTrack.copyWith(audioUrl: audioUrl),
            effectiveCrossfadeSec,
            onSwapped: () {
              if (myNonce == _playbackNonce) {
                state = state.copyWith(
                  currentIndex: nextIdx,
                  currentTrack: targetTrack,
                  totalDuration: _parseDuration(targetTrack.duration),
                  currentPosition: Duration.zero,
                  progress: 0.0,
                  isPlaying: true,
                  status: PlaybackStatus.playing,
                  playRequested: true,
                );
                _saveQueue();
              }
            },
          );
          _isCrossfading = false;
          if (success) {
            _preloadUpcomingTracks();
            ensureUpcomingRecommendations();
          } else {
            // Fallback to normal jump if crossfade failed
            await jumpToQueueIndex(nextIdx, nonce: myNonce);
          }
        } else {
          _isCrossfading = false;
          // Fallback to normal jump on URL resolution failure
          await jumpToQueueIndex(nextIdx, nonce: myNonce);
        }
      } else {
        await jumpToQueueIndex(nextIdx, nonce: myNonce);
      }
    } finally {
      _lock.release();
      _isTransitioning = false;
      // If crossfade was requested but failed or wasn't taken, ensure flag is reset
      if (isCrossfade) _isCrossfading = false;
    }
  }

  Future<void> previousTrack() async {
    if (state.queue.isEmpty) return;
    
    _isTransitioning = true;
    final myNonce = ++_playbackNonce;
    
    _handler.logPlaybackEvent(
      eventName: 'PREVIOUS_TRACK_REQUESTED',
      queueIndex: state.currentIndex,
      error: 'nonce=$myNonce',
    );

    await _lock.acquire();
    try {
      if (_playbackNonce != myNonce) return;
      
      int prevIdx = state.currentIndex - 1;
      if (prevIdx < 0) {
        if (state.repeatMode == RepeatMode.all) {
          prevIdx = state.queue.length - 1;
        } else {
          prevIdx = 0;
        }
      }
      await jumpToQueueIndex(prevIdx, nonce: myNonce);
    } finally {
      _lock.release();
      _isTransitioning = false;
    }
  }

  Future<void> pause() async {
    state = state.copyWith(playRequested: false, isPlaying: false);
    await _handler.pause();
    if (MultiDeviceSyncService.instance.role == SyncRole.host) {
      MultiDeviceSyncService.instance.broadcastPause(state.currentPosition);
    }
  }

  void togglePlay() {
    final playReq = !_handler.player.playing;
    state = state.copyWith(playRequested: playReq);
    if (playReq) {
      _handler.play();
      if (MultiDeviceSyncService.instance.role == SyncRole.host && state.currentTrack != null) {
        MultiDeviceSyncService.instance.broadcastPlay(state.currentTrack!, state.currentPosition);
      }
    } else {
      pause();
    }
  }

  void seek(double progress) {
    final dur = state.totalDuration;
    final double clampedProgress = progress.clamp(0.0, 1.0);
    final targetMs = (clampedProgress * dur.inMilliseconds).round();
    final targetPos = Duration(milliseconds: targetMs);
    state = state.copyWith(currentPosition: targetPos, progress: clampedProgress);
    _handler.seek(targetPos);
    if (MultiDeviceSyncService.instance.role == SyncRole.host) {
      MultiDeviceSyncService.instance.broadcastSeek(targetPos);
    }
  }

  void seekToDuration(Duration position) {
    _handler.seek(position);
    final dur = state.totalDuration;
    final double progress = dur.inMilliseconds > 0
        ? (position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    state = state.copyWith(currentPosition: position, progress: progress);
    if (MultiDeviceSyncService.instance.role == SyncRole.host) {
      MultiDeviceSyncService.instance.broadcastSeek(position);
    }
  }

  void setPlaybackSpeed(double speed) {
    state = state.copyWith(playbackSpeed: speed);
    _handler.player.setSpeed(speed);
    StorageService.saveSetting('playback_speed', speed);
  }

  void toggleVolumeNormalization() {
    final next = !state.volumeNormalization;
    state = state.copyWith(volumeNormalization: next);
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

  void setPlayerScreenTheme(String theme) {
    state = state.copyWith(playerScreenTheme: theme);
    StorageService.saveSetting('player_screen_theme', theme);
  }

  void startSleepTimerTillEndOfTrack() {
    _sleepTimer?.cancel();
    state = state.copyWith(
      isSleepTimerEndOfTrack: true,
      sleepTimerMinutes: -1,
      sleepTimerTimeRemaining: null,
    );
  }

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    state = state.copyWith(
      isSleepTimerEndOfTrack: false,
      sleepTimerMinutes: minutes,
      sleepTimerTimeRemaining: Duration(minutes: minutes),
    );
    
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.sleepTimerTimeRemaining;
      if (remaining == null || remaining.inSeconds <= 1) {
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
      isSleepTimerEndOfTrack: false,
      sleepTimerMinutes: null,
      sleepTimerTimeRemaining: null,
    );
  }

  void onTrackLiked(Track track) {
    RecommendationEngine.instance.recordTrackLiked(track);

    if (state.currentTrack != null && state.currentIndex + 1 < state.queue.length) {
      final upcoming = List<Track>.from(state.queue.sublist(state.currentIndex + 1));
      final reranked = RecommendationEngine.instance.rerankUpcomingQueue(upcoming, state.currentTrack!);
      final updatedQueue = List<Track>.from(state.queue.sublist(0, state.currentIndex + 1))..addAll(reranked);
      state = state.copyWith(queue: updatedQueue);
      _saveQueue();
    }

    ensureUpcomingRecommendations();
  }
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(() {
  return PlaybackNotifier();
});
