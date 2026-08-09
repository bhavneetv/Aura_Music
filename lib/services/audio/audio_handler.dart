import 'dart:async';
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
      androidNotificationOngoing: false,
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler, WidgetsBindingObserver {
  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final AudioPlayer _playerA = AudioPlayer(userAgent: _browserUserAgent);
  final AudioPlayer _playerB = AudioPlayer(userAgent: _browserUserAgent);
  late AudioPlayer _activePlayer;
  late AudioPlayer _fadePlayer;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();

  String _audioFocusState = 'focused';
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

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

  void Function()? onNextRequested;
  void Function()? onPreviousRequested;

  // ── Audio Controls ─────────────────────────────────────────

  @override
  Future<void> play() async {
    await _activePlayer.play();
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
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (onNextRequested != null) {
      onNextRequested!();
    } else {
      await customAction('next');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPreviousRequested != null) {
      onPreviousRequested!();
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
      logPlaybackEvent(
        eventName: 'PLAY_TRACK_START',
        currentTrackId: track.id,
        overrideAudioSource: track.audioUrl,
      );

      // Hard stop secondary fade player to prevent dual overlapping audio playback
      await _fadePlayer.stop();
      await _fadePlayer.setVolume(0.0);

      // Stop and reset active player state before setting new audio source
      await _activePlayer.stop();
      await _activePlayer.seek(Duration.zero);

      String url = track.audioUrl.trim();
      if (url.startsWith('https:/') && !url.startsWith('https://')) {
        url = url.replaceFirst('https:/', 'https://');
      } else if (url.startsWith('http:/') && !url.startsWith('http://')) {
        url = url.replaceFirst('http:/', 'http://');
      }

      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _activePlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
      } else {
        await _activePlayer.setFilePath(url);
      }
      await _activePlayer.setVolume(1.0);
      await _activePlayer.play();
      
      logPlaybackEvent(
        eventName: 'PLAY_TRACK_SUCCESS',
        currentTrackId: track.id,
        overrideAudioSource: url,
      );
    } catch (e) {
      logPlaybackEvent(
        eventName: 'PLAY_TRACK_FAILED',
        currentTrackId: track.id,
        overrideAudioSource: track.audioUrl,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> crossfadeToTrack(Track nextTrack, int crossfadeSeconds) async {
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

    final outgoingPlayer = _activePlayer;
    final incomingPlayer = _fadePlayer;

    // Swap active players IMMEDIATELY at the start of crossfade,
    // so that all duration and position events emitted during load/preparation
    // are successfully captured by the active streams.
    _activePlayer = incomingPlayer;
    _fadePlayer = outgoingPlayer;

    // Broadcast new state so media session / notifications are synced
    _positionController.add(_activePlayer.position);
    _durationController.add(_activePlayer.duration);
    _playerStateController.add(_activePlayer.playerState);
    _broadcastState();

    try {
      String url = nextTrack.audioUrl.trim();
      if (url.startsWith('https:/') && !url.startsWith('https://')) {
        url = url.replaceFirst('https:/', 'https://');
      } else if (url.startsWith('http:/') && !url.startsWith('http://')) {
        url = url.replaceFirst('http:/', 'http://');
      }

      logPlaybackEvent(
        eventName: 'CROSSFADE_START',
        currentTrackId: nextTrack.id,
        overrideAudioSource: url,
      );

      // 1. Load incoming track on the active player in background
      await _activePlayer.setVolume(0.0);
      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _activePlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
      } else {
        await _activePlayer.setFilePath(url);
      }
      
      // 2. Start playback on the new active player
      await _activePlayer.play();

      // 3. Perform crossfade loop
      final steps = (crossfadeSeconds * 10).clamp(10, 100);
      final stepMs = (crossfadeSeconds * 1000 / steps).round();

      for (int i = 1; i <= steps; i++) {
        await Future.delayed(Duration(milliseconds: stepMs));
        final double progress = i / steps;
        final double outVol = math.cos(progress * math.pi / 2);
        final double inVol = math.sin(progress * math.pi / 2);
        
        // Use try-catch to ignore errors if players are stopped/disposed during loop
        try {
          await _fadePlayer.setVolume(outVol.clamp(0.0, 1.0));
          await _activePlayer.setVolume(inVol.clamp(0.0, 1.0));
        } catch (_) {}
      }

      // 4. Hard stop and reset volume of outgoing player
      try {
        await _fadePlayer.stop();
        await _fadePlayer.setVolume(1.0);
      } catch (_) {}

      logPlaybackEvent(
        eventName: 'CROSSFADE_COMPLETE',
        currentTrackId: nextTrack.id,
        overrideAudioSource: url,
      );
    } catch (e) {
      logPlaybackEvent(
        eventName: 'CROSSFADE_FAILED',
        currentTrackId: nextTrack.id,
        error: e.toString(),
      );
      // Ensure fade player is stopped on failure
      try {
        await _fadePlayer.stop();
        await _fadePlayer.setVolume(1.0);
      } catch (_) {}
      await playTrack(nextTrack);
    }
  }

  Future<void> prepareAndResume(Track track, Duration position) async {
    try {
      logPlaybackEvent(
        eventName: 'PREPARE_AND_RESUME_START',
        currentTrackId: track.id,
        error: 'Resuming at ${position.inMilliseconds}ms',
      );

      await _fadePlayer.stop();
      await _fadePlayer.setVolume(0.0);

      await _activePlayer.stop();
      
      String url = track.audioUrl.trim();
      if (url.startsWith('https:/') && !url.startsWith('https://')) {
        url = url.replaceFirst('https:/', 'https://');
      } else if (url.startsWith('http:/') && !url.startsWith('http://')) {
        url = url.replaceFirst('http:/', 'http://');
      }

      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _activePlayer.setAudioSource(AudioSource.uri(Uri.parse(url), headers: _cdnHeaders));
      } else {
        await _activePlayer.setFilePath(url);
      }
      
      await _activePlayer.seek(position);
      await _activePlayer.setVolume(1.0);
      await _activePlayer.play();

      logPlaybackEvent(
        eventName: 'PREPARE_AND_RESUME_SUCCESS',
        currentTrackId: track.id,
      );
    } catch (e) {
      logPlaybackEvent(
        eventName: 'PREPARE_AND_RESUME_FAILED',
        currentTrackId: track.id,
        error: e.toString(),
      );
      rethrow;
    }
  }

  // ── AudioSession / App Lifecycle ──────────────────────────────

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      session.interruptionEventStream.listen((event) {
        _audioFocusState = 'interrupted: ${event.type} (begin: ${event.begin})';
        logPlaybackEvent(
          eventName: 'AUDIO_FOCUS_INTERRUPTION',
          error: 'Type: ${event.type}, Begin: ${event.begin}',
        );
      });
      session.becomingNoisyEventStream.listen((_) {
        _audioFocusState = 'becoming_noisy';
        logPlaybackEvent(eventName: 'AUDIO_BECOMING_NOISY');
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

    final isPlaying = _activePlayer.playing;

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
      processingState: stateMap[_activePlayer.processingState] ?? AudioProcessingState.idle,
      playing: isPlaying,
      updatePosition: _activePlayer.position,
      bufferedPosition: _activePlayer.bufferedPosition,
      speed: _activePlayer.speed,
    ));
  }
}
