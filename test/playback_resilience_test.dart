import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/providers/playback_provider.dart';

void main() {
  group('PlaybackState State Machine & Enum Tests', () {
    test('PlaybackStatus enum has all required states', () {
      expect(PlaybackStatus.values, contains(PlaybackStatus.idle));
      expect(PlaybackStatus.values, contains(PlaybackStatus.loading));
      expect(PlaybackStatus.values, contains(PlaybackStatus.ready));
      expect(PlaybackStatus.values, contains(PlaybackStatus.playing));
      expect(PlaybackStatus.values, contains(PlaybackStatus.paused));
      expect(PlaybackStatus.values, contains(PlaybackStatus.buffering));
      expect(PlaybackStatus.values, contains(PlaybackStatus.completed));
      expect(PlaybackStatus.values, contains(PlaybackStatus.error));
    });

    test('PlaybackState initializes with default idle state', () {
      final state = PlaybackState();
      expect(state.status, PlaybackStatus.idle);
      expect(state.playRequested, false);
      expect(state.isPlaying, false);
      expect(state.progress, 0.0);
    });

    test('PlaybackState copyWith correctly updates status and playRequested', () {
      final state = PlaybackState();
      final updated = state.copyWith(
        status: PlaybackStatus.playing,
        playRequested: true,
      );
      expect(updated.status, PlaybackStatus.playing);
      expect(updated.playRequested, true);
    });
  });
}
