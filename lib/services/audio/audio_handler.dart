import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';
import '../widget/home_widget_service.dart';

Future<AudioHandler> initAudioHandler() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_app.channel.audio',
      androidNotificationChannelName: 'Aura Vinyl Playback',
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler, WidgetsBindingObserver {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final AudioPlayer _playerA = AudioPlayer(
    userAgent: _browserUserAgent,
    handleAudioSessionActivation: false,
    handleInterruptions: false,
  );
  final AudioPlayer _playerB = AudioPlayer(
    userAgent: _browserUserAgent,
    handleAudioSessionActivation: false,
    handleInterruptions: false,
  );
  late AudioPlayer _activePlayer;
  late AudioPlayer _fadePlayer;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();

  String _audioFocusState = 'focused';
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  // Track whether playback was interrupted so we can auto-resume
  bool _wasPlayingBeforeInterruption = false;

  // CRITICAL iOS FIX: Flag that keeps the system notification reporting
  // playing=true during the ENTIRE gap between two songs (from completed
  // through loading/buffering until the next track's play() succeeds).
  // Without this, iOS suspends the app during the loading phase because
  // the player reports playing=false while setAudioSource() is loading.
  bool _isTrackTransitioning = false;

  // Track active crossfade state and timer so it can be controlled or cancelled
  Timer? _crossfadeTimer;
  bool _isCrossfadeActive = false;
  Completer<void>? _crossfadeCompleter;

  // Track the currently preloaded next song to allow instant gapless switching
  Track? _preloadedTrack;

  Stream<Duration> get activePositionStream => _positionController.stream;
  Stream<Duration?> get activeDurationStream => _durationController.stream;
  Stream<PlayerState> get activePlayerStateStream => _playerStateController.stream;

  MyAudioHandler() {
    _activePlayer = _playerA;
    _fadePlayer = _playerB;

    WidgetsBinding.instance.addObserver(this);
    _initAudioSession();

    // Emit an initial idle playback state so Android MediaSession
    // registers available actions (play, pause, next, prev, seek, stop)
    // BEFORE any song is loaded. Without this, notification controls
    // are invisible / non-functional until the first playbackEvent fires.
    _broadcastState();

    _playerA.playbackEventStream.listen((_) {
      if (_activePlayer == _playerA) _broadcastState();
    });
    _playerB.playbackEventStream.listen((_) {
      if (_activePlayer == _playerB) _broadcastState();
    });

    _playerA.positionStream.listen((pos) {
      if (_activePlayer == _playerA) _positionController.add(pos);
    });
    _playerB.positionStream.listen((pos) {
      if (_activePlayer == _playerB) _positionController.add(pos);
    });

    _playerA.durationStream.listen((dur) {
      if (_activePlayer == _playerA) _durationController.add(dur);
    });
    _playerB.durationStream.listen((dur) {
      if (_activePlayer == _playerB) _durationController.add(dur);
    });

    _playerA.playerStateStream.listen((ps) {
      if (_activePlayer == _playerA) {
        _playerStateController.add(ps);
        _broadcastState();
      }
    });
    _playerB.playerStateStream.listen((ps) {
      if (_activePlayer == _playerB) {
        _playerStateController.add(ps);
        _broadcastState();
      }
    });
  }

  AudioPlayer get player => _activePlayer;

  Future<void> Function()? onNextRequested;
  Future<void> Function()? onPreviousRequested;
  Future<void> Function(int index)? onSkipToQueueItemRequested;
  Future<void> Function(String mediaId)? onPlayFromMediaIdRequested;

  @override
  Future<void> skipToQueueItem(int index) async {
    if (onSkipToQueueItemRequested != null) {
      await onSkipToQueueItemRequested!(index);
    }
  }

  // ── Audio Controls ─────────────────────────────────────────

  @override
  Future<void> play() async {
    await _ensureAudioSessionActive();
    _activePlayer.play(); // don't await, it blocks until song ends
    if (_isCrossfadeActive) {
      _fadePlayer.play();
    }
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _activePlayer.pause();
    if (_isCrossfadeActive) {
      await _fadePlayer.pause();
    }
    _broadcastState();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _activePlayer.setSpeed(speed);
    if (_isCrossfadeActive) {
      await _fadePlayer.setSpeed(speed);
    }
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isCrossfadeActive) {
      cancelCrossfade();
    }
    _positionController.add(position);
    await _activePlayer.seek(position);
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    cancelCrossfade();
    await _activePlayer.stop();
    await _fadePlayer.stop();
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (_isCrossfadeActive) {
      cancelCrossfade();
    }
    if (onNextRequested != null) {
      await onNextRequested!();
    } else {
      await customAction('next');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_isCrossfadeActive) {
      cancelCrossfade();
    }
    if (onPreviousRequested != null) {
      await onPreviousRequested!();
    } else {
      await customAction('previous');
    }
  }

  @override
  Future<void> fastForward() async {
    final current = _activePlayer.position;
    seek(current + const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    final current = _activePlayer.position;
    seek(current - const Duration(seconds: 10));
  }

  // Standard browser headers required by JioSaavn CDN to return 200 OK
  static const Map<String, String> _cdnHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
    'Accept-Encoding': 'identity;q=1, *;q=0',
    'Referer': 'https://www.jiosaavn.com/',
  };

  /// Safely cancels any ongoing crossfade, resets volume levels and stops the fade player.
  void cancelCrossfade({bool snapActiveVolume = true}) {
    if (_crossfadeTimer != null) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
    }
    _isCrossfadeActive = false;
    
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
      _crossfadeCompleter = null;
    }

    try {
      _fadePlayer.pause();
      _fadePlayer.seek(Duration.zero);
      _fadePlayer.setVolume(1.0);
    } catch (_) {}

    if (snapActiveVolume) {
      try {
        _activePlayer.setVolume(1.0);
      } catch (_) {}
    }
  }

  /// Resets fade player and volumes without stopping active player to preserve iOS AVAudioSession in background.
  Future<void> resetForNewTrack() async {
    cancelCrossfade();

    // CRITICAL iOS FIX: Use pause() instead of stop() for the outgoing player.
    // Calling stop() on an AVPlayer in the background can cause iOS to aggressively
    // throttle network privileges or drop the audio session, causing the newly
    // started player to stall after playing its initial 1-second buffer.
    // The player will naturally release resources when setAudioSource is called next.
    try { await _fadePlayer.pause(); } catch (_) {}
    try { await _fadePlayer.seek(Duration.zero); } catch (_) {}
    try { await _fadePlayer.setVolume(1.0); } catch (_) {}
    try { await _activePlayer.setVolume(1.0); } catch (_) {}
  }

  /// Silently buffers the audio of the upcoming track into the inactive player to eliminate load times.
  Future<void> preloadNextTrack(Track nextTrack) async {
    if (_preloadedTrack?.id == nextTrack.id) return; // Already preloaded

    try {
      String url = _normalizeUrl(nextTrack.audioUrl);
      
      // Stop anything currently on the fade player and mute it just in case
      await _fadePlayer.stop();
      await _fadePlayer.setVolume(0.0); 

      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _fadePlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
      } else {
        await _fadePlayer.setFilePath(url);
      }
      
      _preloadedTrack = nextTrack;
      logPlaybackEvent(eventName: 'PRELOAD_TRACK_SUCCESS', currentTrackId: nextTrack.id);
    } catch (e) {
      _preloadedTrack = null;
      logPlaybackEvent(eventName: 'PRELOAD_TRACK_FAILED', currentTrackId: nextTrack.id, error: e.toString());
    }
  }

  MediaItem _trackToMediaItem(Track track) {
    return MediaItem(
      id: track.id,
      album: track.album,
      title: track.title,
      artist: track.artist,
      duration: _parseDuration(track.duration),
      artUri: Uri.tryParse(track.artworkUrl),
      extras: {
        'audioUrl': track.audioUrl,
        'genre': track.genre,
      },
    );
  }

  void updateTrackMediaItem(Track track) {
    final item = _trackToMediaItem(track);
    final cur = mediaItem.value;
    if (cur?.id != item.id ||
        cur?.title != item.title ||
        cur?.artist != item.artist ||
        cur?.album != item.album ||
        cur?.duration != item.duration ||
        cur?.artUri != item.artUri) {
      mediaItem.add(item);
    }
  }

  void syncQueue(List<Track> tracks) {
    final items = tracks.map(_trackToMediaItem).toList();
    queue.add(items);
  }

  Future<void> playTrack(Track track) async {
    updateTrackMediaItem(track);
    
    try {
      // CRITICAL: Mark transition BEFORE any async work so _broadcastState()
      // keeps reporting playing=true to iOS throughout the load.
      _isTrackTransitioning = true;
      _broadcastState(); // Immediately tell iOS we're still playing

      logPlaybackEvent(
        eventName: 'PLAY_TRACK_START',
        currentTrackId: track.id,
        overrideAudioSource: track.audioUrl,
      );

      await _ensureAudioSessionActive();

      String url = _normalizeUrl(track.audioUrl);

      if (_preloadedTrack?.id == track.id) {
        logPlaybackEvent(
          eventName: 'USING_PRELOADED_PLAYER', 
          currentTrackId: track.id,
          overrideAudioSource: url,
        );
        
        // Swap players for instant playback
        final outgoingPlayer = _activePlayer;
        _activePlayer = _fadePlayer;
        _fadePlayer = outgoingPlayer;
        
        await _activePlayer.setVolume(1.0);

        // CRITICAL iOS FIX: Re-verify & reactivate audio session AFTER player swap
        // immediately before calling play() on the new active player.
        await _ensureAudioSessionActive();

        _activePlayer.play(); // DON'T AWAIT: it blocks until song finishes!
        _preloadedTrack = null;

        // Clean up the old player asynchronously
        resetForNewTrack(); 
        
        // Broadcast state with new active player
        _positionController.add(_activePlayer.position);
        _durationController.add(_activePlayer.duration);
        _playerStateController.add(_activePlayer.playerState);
        _isTrackTransitioning = false;
        _broadcastState();
      } else {
        // Cold start (track wasn't preloaded)
        await resetForNewTrack();
        _preloadedTrack = null;

        logPlaybackEvent(
          eventName: 'SET_AUDIO_SOURCE_START',
          currentTrackId: track.id,
          overrideAudioSource: url,
        );

        if (url.startsWith('http://') || url.startsWith('https://')) {
          await _activePlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
        } else {
          await _activePlayer.setFilePath(url);
        }
        await _activePlayer.setVolume(1.0);

        logPlaybackEvent(
          eventName: 'SET_AUDIO_SOURCE_DONE',
          currentTrackId: track.id,
        );

        // CRITICAL iOS FIX: Reactivate audio session IMMEDIATELY BEFORE play(),
        // AFTER setAudioSource has finished loading/buffering.
        // During setAudioSource's network load (which can take 500ms-2000ms in background),
        // iOS CoreAudio deactivates the app's audio session due to the silent gap.
        await _ensureAudioSessionActive();

        _activePlayer.play(); // DON'T AWAIT
        _isTrackTransitioning = false;
        _broadcastState();
      }
      
      logPlaybackEvent(
        eventName: 'PLAY_TRACK_SUCCESS',
        currentTrackId: track.id,
        overrideAudioSource: url,
      );
    } catch (e) {
      _isTrackTransitioning = false;
      logPlaybackEvent(
        eventName: 'PLAY_TRACK_FAILED',
        currentTrackId: track.id,
        overrideAudioSource: track.audioUrl,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<bool> crossfadeToTrack(
    Track nextTrack,
    int crossfadeSeconds, {
    void Function()? onSwapped,
  }) async {
    cancelCrossfade();

    final outgoingPlayer = _activePlayer;
    final incomingPlayer = _fadePlayer;

    try {
      _isTrackTransitioning = true;
      _broadcastState();

      await _ensureAudioSessionActive();
      String url = _normalizeUrl(nextTrack.audioUrl);

      logPlaybackEvent(
        eventName: 'CROSSFADE_START',
        currentTrackId: nextTrack.id,
        overrideAudioSource: url,
      );

      // Check if incoming player is already loaded with preloadedTrack
      if (_preloadedTrack?.id == nextTrack.id) {
        logPlaybackEvent(
          eventName: 'CROSSFADE_USING_PRELOADED',
          currentTrackId: nextTrack.id,
        );
        await incomingPlayer.setVolume(0.0);
      } else {
        // Load incoming track on the fade player
        await incomingPlayer.stop();
        await incomingPlayer.setVolume(0.0);
        if (url.startsWith('http://') || url.startsWith('https://')) {
          await incomingPlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
        } else {
          await incomingPlayer.setFilePath(url);
        }
      }

      // Start playback on incoming player at volume 0
      await _ensureAudioSessionActive();
      incomingPlayer.play(); // DON'T AWAIT

      // Swap active player references — incoming is now active, outgoing is fade player
      _activePlayer = incomingPlayer;
      _fadePlayer = outgoingPlayer;
      _preloadedTrack = null;
      _isCrossfadeActive = true;

      // Broadcast new MediaItem to system notification & lockscreen at exact swap time
      updateTrackMediaItem(nextTrack);

      onSwapped?.call();

      _isTrackTransitioning = false;
      _positionController.add(_activePlayer.position);
      _durationController.add(_activePlayer.duration);
      _playerStateController.add(_activePlayer.playerState);
      _broadcastState();

      // Equal-power volume automation curve:
      // vol_out = cos(progress * pi / 2)
      // vol_in = sin(progress * pi / 2)
      _crossfadeCompleter = Completer<void>();
      final steps = (crossfadeSeconds * 20).clamp(20, 200); // 20 updates per sec (50ms interval)
      final stepMs = (crossfadeSeconds * 1000 / steps).round();
      int currentStep = 0;

      _crossfadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
        if (!_isCrossfadeActive) {
          timer.cancel();
          return;
        }

        currentStep++;
        final double progress = (currentStep / steps).clamp(0.0, 1.0);
        final double outVol = math.cos(progress * math.pi / 2);
        final double inVol = math.sin(progress * math.pi / 2);

        try {
          _fadePlayer.setVolume(outVol.clamp(0.0, 1.0));
          _activePlayer.setVolume(inVol.clamp(0.0, 1.0));
        } catch (_) {}

        if (currentStep >= steps) {
          timer.cancel();
          _crossfadeTimer = null;
          _isCrossfadeActive = false;
          if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
            _crossfadeCompleter!.complete();
            _crossfadeCompleter = null;
          }
        }
      });

      await _crossfadeCompleter!.future;

      // Clean up outgoing player after crossfade finishes
      try {
        await _fadePlayer.pause();
        await _fadePlayer.seek(Duration.zero);
        await _fadePlayer.setVolume(1.0);
      } catch (_) {}

      try {
        await _activePlayer.setVolume(1.0);
      } catch (_) {}

      logPlaybackEvent(
        eventName: 'CROSSFADE_COMPLETE',
        currentTrackId: nextTrack.id,
        overrideAudioSource: url,
      );

      return true;
    } catch (e) {
      _isTrackTransitioning = false;
      logPlaybackEvent(
        eventName: 'CROSSFADE_FAILED',
        currentTrackId: nextTrack.id,
        error: e.toString(),
      );
      cancelCrossfade();
      return false;
    }
  }

  Future<void> prepareAndResume(Track track, Duration position) async {
    try {
      _isTrackTransitioning = true;
      _broadcastState();

      await _ensureAudioSessionActive();
      logPlaybackEvent(
        eventName: 'PREPARE_AND_RESUME_START',
        currentTrackId: track.id,
        error: 'Resuming at ${position.inMilliseconds}ms',
      );

      await resetForNewTrack();

      String url = _normalizeUrl(track.audioUrl);

      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _activePlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
      } else {
        await _activePlayer.setFilePath(url);
      }
      
      await _activePlayer.seek(position);
      await _activePlayer.setVolume(1.0);
      await _ensureAudioSessionActive();
      _activePlayer.play(); // DON'T AWAIT
      _isTrackTransitioning = false;

      logPlaybackEvent(
        eventName: 'PREPARE_AND_RESUME_SUCCESS',
        currentTrackId: track.id,
      );
    } catch (e) {
      _isTrackTransitioning = false;
      logPlaybackEvent(
        eventName: 'PREPARE_AND_RESUME_FAILED',
        currentTrackId: track.id,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Normalizes audio URL formatting (fixes malformed scheme separators)
  String _normalizeUrl(String rawUrl) {
    String url = rawUrl.trim();
    if (url.startsWith('https:/') && !url.startsWith('https://')) {
      url = url.replaceFirst('https:/', 'https://');
    } else if (url.startsWith('http:/') && !url.startsWith('http://')) {
      url = url.replaceFirst('http:/', 'http://');
    }
    return url;
  }

  // ── AudioSession / App Lifecycle ──────────────────────────────

  Future<void> _ensureAudioSessionActive() async {
    try {
      final session = await AudioSession.instance;
      final success = await session.setActive(true);
      if (!success) {
        logPlaybackEvent(
          eventName: 'AUDIO_SESSION_SET_ACTIVE_RETURNED_FALSE',
          error: 'session.setActive(true) returned false, retrying after 50ms...',
        );
        await Future.delayed(const Duration(milliseconds: 50));
        final retrySuccess = await session.setActive(true);
        logPlaybackEvent(
          eventName: 'AUDIO_SESSION_RETRY_RESULT',
          error: 'retrySuccess=$retrySuccess',
        );
      } else {
        logPlaybackEvent(eventName: 'AUDIO_SESSION_ACTIVATED_SUCCESS');
      }
    } catch (e) {
      logPlaybackEvent(eventName: 'AUDIO_SESSION_REACTIVATION_FAILED', error: e.toString());
    }
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;

      // Configure as a music app so Android properly grants audio focus,
      // especially critical for background playback with screen off.
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        _audioFocusState = 'interrupted: ${event.type} (begin: ${event.begin})';
        logPlaybackEvent(
          eventName: 'AUDIO_FOCUS_INTERRUPTION',
          error: 'Type: ${event.type}, Begin: ${event.begin}',
        );

        if (event.begin) {
          // Interruption started (e.g. phone call) — pause playback
          _wasPlayingBeforeInterruption = _activePlayer.playing;
          if (_wasPlayingBeforeInterruption) {
            _activePlayer.pause();
          }
        } else {
          // Interruption ended — resume if we were playing before
          _audioFocusState = 'focused';
          if (_wasPlayingBeforeInterruption) {
            switch (event.type) {
              case AudioInterruptionType.pause:
              case AudioInterruptionType.duck:
                _ensureAudioSessionActive();
                _activePlayer.play();
                break;
              case AudioInterruptionType.unknown:
                // Don't auto-resume on unknown interruptions
                break;
            }
            _wasPlayingBeforeInterruption = false;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        _audioFocusState = 'becoming_noisy';
        logPlaybackEvent(eventName: 'AUDIO_BECOMING_NOISY');
        // Headphones unplugged — pause playback
        _activePlayer.pause();
      });
    } catch (e) {
      print('[AURA-HANDLER] Failed to initialize AudioSession monitoring: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    logPlaybackEvent(eventName: 'APP_LIFECYCLE_CHANGE');
  }

  void logPlaybackEvent({
    required String eventName,
    String? currentTrackId,
    String? previousTrackId,
    int? queueIndex,
    String? error,
    String? overrideAudioSource,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final pState = _activePlayer.processingState.toString().split('.').last;
    final isPlaying = _activePlayer.playing;
    final position = _activePlayer.position.inMilliseconds;
    final duration = _activePlayer.duration?.inMilliseconds ?? 0;
    final audioSource = overrideAudioSource ?? mediaItem.value?.extras?['audioUrl'] ?? 'unknown';

    print('[PLAYBACK-LOG] $timestamp | Event: $eventName '
        '| currentTrackId: ${currentTrackId ?? mediaItem.value?.id} '
        '| previousTrackId: $previousTrackId '
        '| queueIndex: $queueIndex '
        '| playerState: $pState '
        '| isPlaying: $isPlaying '
        '| position: ${position}ms | duration: ${duration}ms '
        '| audioSource: $audioSource | error: $error '
        '| appLifecycleState: ${_lifecycleState.toString().split('.').last} '
        '| audioFocusState: $_audioFocusState');
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

  // ── State Mapping ───────────────────────────────────────────

  /// Single source-of-truth for emitting PlaybackState to the system.
  /// Called from the constructor (initial idle state), every playback
  /// event, every playerState change, and after every user action
  /// (play/pause/seek/stop). This ensures the Android MediaSession
  /// always has the correct set of controls and playing state.
  void _broadcastState() {
    const stateMap = {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    };

    final pState = _activePlayer.processingState;
    // CRITICAL iOS FIX: Keep reporting playing=true to the system during
    // the ENTIRE window between songs.
    final isPlaying = (_isTrackTransitioning || pState == ProcessingState.completed)
        ? true
        : _activePlayer.playing;

    var mappedState = stateMap[pState] ?? AudioProcessingState.idle;

    // CRITICAL iOS FIX: Never broadcast 'completed' or 'idle' to the system
    // if we are transitioning to the next track, as audio_service will drop
    // the background assertion. Broadcast 'buffering' instead.
    if (_isTrackTransitioning || pState == ProcessingState.completed) {
      if (mappedState == AudioProcessingState.completed || mappedState == AudioProcessingState.idle) {
        mappedState = AudioProcessingState.buffering;
      }
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: mappedState,
      playing: isPlaying,
      updatePosition: _activePlayer.position,
      bufferedPosition: _activePlayer.bufferedPosition,
      speed: _activePlayer.speed,
    ));

    // Synchronize Material You (Android) and WidgetKit (iOS) home screen widgets
    _syncHomeWidget(isPlaying);
  }

  void _syncHomeWidget(bool isPlaying) {
    try {
      final item = mediaItem.value;
      if (item != null) {
        final t = Track(
          id: item.id,
          title: item.title,
          artist: item.artist ?? 'Aura Music',
          album: item.album ?? 'Aura Vinyl',
          duration: '',
          artworkUrl: item.artUri?.toString() ?? '',
          audioUrl: '',
          genre: '',
        );
        HomeWidgetService.updatePlaybackState(track: t, isPlaying: isPlaying);
      }
    } catch (_) {}
  }

  // ── Android Auto & MediaBrowserService Hierarchy ────────────────

  static const String _autoRootRecent = 'root_recent';
  static const String _autoRootQueue = 'root_queue';
  static const String _autoRootPlaylists = 'root_playlists';
  static const String _autoRootDownloads = 'root_downloads';

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    // 1. Root level tabs for Android Auto dashboard
    if (parentMediaId == 'root' || parentMediaId == '/' || parentMediaId.isEmpty) {
      return [
        const MediaItem(
          id: _autoRootQueue,
          title: 'Current Queue',
          album: 'Aura Music',
          playable: false,
        ),
        const MediaItem(
          id: _autoRootRecent,
          title: 'Recently Played',
          album: 'Aura Music',
          playable: false,
        ),
        const MediaItem(
          id: _autoRootPlaylists,
          title: 'Your Playlists',
          album: 'Aura Music',
          playable: false,
        ),
        const MediaItem(
          id: _autoRootDownloads,
          title: 'Downloaded Music',
          album: 'Aura Music',
          playable: false,
        ),
      ];
    }

    // 2. Queue tracks
    if (parentMediaId == _autoRootQueue) {
      return queue.value;
    }

    // 3. Recently Played tracks from StorageService
    if (parentMediaId == _autoRootRecent) {
      try {
        final history = StorageService.getListeningHistory();
        return history.map((item) {
          return MediaItem(
            id: item['track_id']?.toString() ?? '',
            title: item['title']?.toString() ?? 'Track',
            artist: item['artist']?.toString() ?? 'Aura Music',
            album: item['album']?.toString() ?? 'Recent',
            duration: _parseDuration(item['duration']?.toString() ?? ''),
            artUri: Uri.tryParse(item['artworkUrl']?.toString() ?? ''),
            playable: true,
            extras: {
              'audioUrl': item['audioUrl'],
              'genre': item['genre'],
            },
          );
        }).toList();
      } catch (_) {
        return [];
      }
    }

    // 4. Downloaded Offline tracks from StorageService
    if (parentMediaId == _autoRootDownloads) {
      try {
        final downloaded = StorageService.getFullDownloadedTracks();
        return downloaded.map(_trackToMediaItem).toList();
      } catch (_) {
        return [];
      }
    }

    // 5. Playlists list
    if (parentMediaId == _autoRootPlaylists) {
      try {
        final playlists = StorageService.getPlaylists();
        return playlists.map((pl) {
          final pId = pl['id']?.toString() ?? '';
          return MediaItem(
            id: 'playlist_$pId',
            title: pl['name']?.toString() ?? 'Playlist',
            album: 'Aura Music',
            playable: false,
          );
        }).toList();
      } catch (_) {
        return [];
      }
    }

    // 6. Tracks inside a specific playlist
    if (parentMediaId.startsWith('playlist_')) {
      final pId = parentMediaId.replaceFirst('playlist_', '');
      final playlists = StorageService.getPlaylists();
      final pl = playlists.firstWhere((p) => p['id']?.toString() == pId, orElse: () => {});
      final tracksRaw = pl['tracks'] as List?;
      if (tracksRaw != null) {
        return tracksRaw.map((t) {
          final map = Map<String, dynamic>.from(t as Map);
          return _trackToMediaItem(Track.fromJson(map));
        }).toList();
      }
    }

    return [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final cur = mediaItem.value;
    if (cur?.id == mediaId) return cur;
    try {
      final inQueue = queue.value.firstWhere((it) => it.id == mediaId);
      return inQueue;
    } catch (_) {}
    return null;
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    if (onPlayFromMediaIdRequested != null) {
      await onPlayFromMediaIdRequested!(mediaId);
      return;
    }

    // Fallback: check current queue
    try {
      final inQueue = queue.value.firstWhere((it) => it.id == mediaId);
      final idx = queue.value.indexOf(inQueue);
      if (idx != -1) {
        await skipToQueueItem(idx);
        return;
      }
    } catch (_) {}

    // Fallback: check recently played
    try {
      final history = StorageService.getListeningHistory();
      final hMatch = history.firstWhere((item) => item['track_id'] == mediaId, orElse: () => {});
      if (hMatch.isNotEmpty) {
        final track = Track(
          id: hMatch['track_id']?.toString() ?? '',
          title: hMatch['title']?.toString() ?? '',
          artist: hMatch['artist']?.toString() ?? '',
          album: hMatch['album']?.toString() ?? '',
          duration: hMatch['duration']?.toString() ?? '',
          artworkUrl: hMatch['artworkUrl']?.toString() ?? '',
          audioUrl: hMatch['audioUrl']?.toString() ?? '',
          genre: hMatch['genre']?.toString() ?? '',
        );
        await playTrack(track);
      }
    } catch (_) {}
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return [];
    final qLower = query.toLowerCase();

    final matches = queue.value.where((item) =>
      item.title.toLowerCase().contains(qLower) ||
      (item.artist?.toLowerCase().contains(qLower) ?? false)
    ).toList();

    return matches;
  }
}
