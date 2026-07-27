import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/track.dart';

Future<AudioHandler> initAudioHandler() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_app.channel.audio',
      androidNotificationChannelName: 'Aura Vinyl Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  late AudioPlayer _activePlayer;
  late AudioPlayer _fadePlayer;

  MyAudioHandler() {
    _activePlayer = _playerA;
    _fadePlayer = _playerB;
    _activePlayer.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });
    _fadePlayer.playbackEventStream.listen((event) {
      if (_fadePlayer.playing) {
        playbackState.add(_transformEvent(event));
      }
    });
  }

  AudioPlayer get player => _activePlayer;

  void Function()? onNextRequested;
  void Function()? onPreviousRequested;

  // ── Audio Controls ─────────────────────────────────────────

  @override
  Future<void> play() => _activePlayer.play();

  @override
  Future<void> pause() => _activePlayer.pause();

  @override
  Future<void> seek(Duration position) => _activePlayer.seek(position);

  @override
  Future<void> stop() async {
    await _activePlayer.stop();
    await _fadePlayer.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
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

  // ── Track Handling ──────────────────────────────────────────

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
      // Hard stop secondary fade player to prevent dual overlapping audio playback
      await _fadePlayer.stop();
      await _fadePlayer.setVolume(0.0);

      String url = track.audioUrl.trim();
      if (url.startsWith('https:/') && !url.startsWith('https://')) {
        url = url.replaceFirst('https:/', 'https://');
      } else if (url.startsWith('http:/') && !url.startsWith('http://')) {
        url = url.replaceFirst('http:/', 'http://');
      }

      if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('http')) {
        await _activePlayer.setUrl(url);
      } else {
        await _activePlayer.setFilePath(url);
      }
      await _activePlayer.setVolume(1.0);
      _activePlayer.play();
    } catch (e) {
      print('Error playing audio source: $e');
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

    try {
      String url = nextTrack.audioUrl.trim();
      if (url.startsWith('https:/') && !url.startsWith('https://')) {
        url = url.replaceFirst('https:/', 'https://');
      } else if (url.startsWith('http:/') && !url.startsWith('http://')) {
        url = url.replaceFirst('http:/', 'http://');
      }

      if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('http')) {
        await incomingPlayer.setUrl(url);
      } else {
        await incomingPlayer.setFilePath(url);
      }
      await incomingPlayer.setVolume(0.0);
      incomingPlayer.play();

      final steps = (crossfadeSeconds * 10).clamp(10, 100);
      final stepMs = (crossfadeSeconds * 1000 / steps).round();

      for (int i = 1; i <= steps; i++) {
        await Future.delayed(Duration(milliseconds: stepMs));
        final double progress = i / steps;
        // Equal-power crossfade curve for seamless overlapping audio
        final double outVol = math.cos(progress * math.pi / 2);
        final double inVol = math.sin(progress * math.pi / 2);
        await outgoingPlayer.setVolume(outVol.clamp(0.0, 1.0));
        await incomingPlayer.setVolume(inVol.clamp(0.0, 1.0));
      }

      await outgoingPlayer.stop();
      await outgoingPlayer.setVolume(1.0);

      _activePlayer = incomingPlayer;
      _fadePlayer = outgoingPlayer;
    } catch (e) {
      print('Crossfade failed fallback to normal play: $e');
      await playTrack(nextTrack);
    }
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

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_activePlayer.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_activePlayer.processingState]!,
      playing: _activePlayer.playing,
      updatePosition: _activePlayer.position,
      bufferedPosition: _activePlayer.bufferedPosition,
      speed: _activePlayer.speed,
      queueIndex: event.currentIndex,
    );
  }
}
