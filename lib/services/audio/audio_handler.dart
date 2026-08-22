import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/track.dart';

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

  // Track active crossfade timer so it can be cancelled
  Timer? _crossfadeTimer;

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

  // ── Audio Controls ─────────────────────────────────────────

  @override
  Future<void> play() async {
    await _ensureAudioSessionActive();
    _activePlayer.play(); // don't await, it blocks until song ends
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _activePlayer.pause();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
    await _activePlayer.seek(position);
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    await _activePlayer.stop();
    await _fadePlayer.stop();
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (onNextRequested != null) {
      await onNextRequested!();
    } else {
      await customAction('next');
    }
  }

  @override
  Future<void> skipToPrevious() async {
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

  /// Resets fade player and volumes without stopping active player to preserve iOS AVAudioSession in background.
  Future<void> resetForNewTrack() async {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;

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

  Future<void> playTrack(Track track) async {
    final mediaItem = MediaItem(
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
    
    this.mediaItem.add(mediaItem);
    
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
    // Cancel any existing crossfade timer
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;

    // Capture references BEFORE any swap
    final outgoingPlayer = _activePlayer;
    final incomingPlayer = _fadePlayer;

    try {
      // Mark transitioning so iOS keeps us alive during the load
      _isTrackTransitioning = true;
      _broadcastState();

      await _ensureAudioSessionActive();
      String url = _normalizeUrl(nextTrack.audioUrl);

      logPlaybackEvent(
        eventName: 'CROSSFADE_START',
        currentTrackId: nextTrack.id,
        overrideAudioSource: url,
      );

      // 1. Load incoming track on the fade player (DON'T swap yet)
      await incomingPlayer.stop();
      await incomingPlayer.setVolume(0.0);
      if (url.startsWith('http://') || url.startsWith('https://')) {
        await incomingPlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
      } else {
        await incomingPlayer.setFilePath(url);
      }
      
      // 2. Start playback on the incoming player at volume 0
      await _ensureAudioSessionActive();
      incomingPlayer.play(); // DON'T AWAIT

      // 3. NOW swap active players — incoming is loaded and playing
      _activePlayer = incomingPlayer;
      _fadePlayer = outgoingPlayer;

      // Broadcast new MediaItem to system notification at exact swap time
      final mediaItem = MediaItem(
        id: nextTrack.id,
        album: nextTrack.album,
        title: nextTrack.title,
        artist: nextTrack.artist,
        duration: _parseDuration(nextTrack.duration),
        artUri: Uri.tryParse(nextTrack.artworkUrl),
        extras: {
          'audioUrl': nextTrack.audioUrl,
          'genre': nextTrack.genre,
        },
      );
      this.mediaItem.add(mediaItem);

      // Notify caller that player swap has completed
      onSwapped?.call();

      // Broadcast updated state with the new active player
      _isTrackTransitioning = false; // Crossfade swap done, real audio is playing
      _positionController.add(_activePlayer.position);
      _durationController.add(_activePlayer.duration);
      _playerStateController.add(_activePlayer.playerState);
      _broadcastState();

      // 4. Perform smooth crossfade using Timer.periodic (non-blocking)
      final completer = Completer<void>();
      final steps = (crossfadeSeconds * 10).clamp(10, 100);
      final stepMs = (crossfadeSeconds * 1000 / steps).round();
      int currentStep = 0;

      _crossfadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
        currentStep++;
        final double progress = currentStep / steps;
        final double outVol = math.cos(progress * math.pi / 2);
        final double inVol = math.sin(progress * math.pi / 2);

        try {
          _fadePlayer.setVolume(outVol.clamp(0.0, 1.0));
          _activePlayer.setVolume(inVol.clamp(0.0, 1.0));
        } catch (_) {}

        if (currentStep >= steps) {
          timer.cancel();
          _crossfadeTimer = null;
          completer.complete();
        }
      });

      await completer.future;

      // 5. Pause and reset volume of outgoing player instead of hard stop
      try {
        await _fadePlayer.pause();
        await _fadePlayer.seek(Duration.zero);
        await _fadePlayer.setVolume(1.0);
      } catch (_) {}

      // Ensure active player is at full volume
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
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      // Ensure fade player is paused on failure
      try {
        await _fadePlayer.pause();
        await _fadePlayer.setVolume(1.0);
      } catch (_) {}
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
  }
}
