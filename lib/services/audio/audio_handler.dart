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
    _activePlayer.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  AudioPlayer get player => _activePlayer;

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
    await playbackState.firstWhere((state) => state.processingState == AudioProcessingState.idle);
  }

  @override
  Future<void> skipToNext() async {
    customAction('next');
  }

  @override
  Future<void> skipToPrevious() async {
    customAction('previous');
  }

  // ── Track Handling ──────────────────────────────────────────

  Future<void> playTrack(Track track) async {
    final mediaItem = MediaItem(
      id: track.id,
      album: track.album,
      title: track.title,
      artist: track.artist,
      duration: _parseDuration(track.duration),
      artUri: Uri.parse(track.artworkUrl),
      extras: {
        'audioUrl': track.audioUrl,
        'genre': track.genre,
      },
    );
    
    this.mediaItem.add(mediaItem);
    
    // Set source
    await _activePlayer.setUrl(track.audioUrl);
    await _activePlayer.setVolume(1.0);
    _activePlayer.play();
  }

  Future<void> crossfadeToTrack(Track nextTrack, int crossfadeSeconds) async {
    final mediaItem = MediaItem(
      id: nextTrack.id,
      album: nextTrack.album,
      title: nextTrack.title,
      artist: nextTrack.artist,
      duration: _parseDuration(nextTrack.duration),
      artUri: Uri.parse(nextTrack.artworkUrl),
      extras: {
        'audioUrl': nextTrack.audioUrl,
        'genre': nextTrack.genre,
      },
    );
    this.mediaItem.add(mediaItem);

    final outgoingPlayer = _activePlayer;
    final incomingPlayer = _fadePlayer;

    try {
      await incomingPlayer.setUrl(nextTrack.audioUrl);
      await incomingPlayer.setVolume(0.0);
      incomingPlayer.play();

      final steps = (crossfadeSeconds * 10).clamp(10, 100);
      final stepMs = (crossfadeSeconds * 1000 / steps).round();

      for (int i = 1; i <= steps; i++) {
        await Future.delayed(Duration(milliseconds: stepMs));
        final double progress = i / steps;
        await outgoingPlayer.setVolume((1.0 - progress).clamp(0.0, 1.0));
        await incomingPlayer.setVolume(progress.clamp(0.0, 1.0));
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
