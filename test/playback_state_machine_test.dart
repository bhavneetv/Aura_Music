import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/providers/playback_provider.dart';

void main() {
  group('PlaybackStatus Transition State Machine Tests', () {
    test('Idempotent self-transitions are always permitted', () {
      for (final status in PlaybackStatus.values) {
        expect(status.canTransitionTo(status), isTrue,
            reason: '$status should transition to itself');
      }
    });

    test('Idle state allows valid transitions only', () {
      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.loading), isTrue);
      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.ready), isTrue);
      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.error), isTrue);

      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.playing), isFalse);
      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.buffering), isFalse);
      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.completed), isFalse);
      expect(PlaybackStatus.idle.canTransitionTo(PlaybackStatus.paused), isFalse);
    });

    test('Loading state allows transitions to active or recovery states', () {
      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.playing), isTrue);
      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.ready), isTrue);
      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.buffering), isTrue);
      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.paused), isTrue);
      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.error), isTrue);
      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.idle), isTrue);

      expect(PlaybackStatus.loading.canTransitionTo(PlaybackStatus.completed), isFalse);
    });

    test('Playing state allows controls and playback lifecycle events', () {
      expect(PlaybackStatus.playing.canTransitionTo(PlaybackStatus.paused), isTrue);
      expect(PlaybackStatus.playing.canTransitionTo(PlaybackStatus.buffering), isTrue);
      expect(PlaybackStatus.playing.canTransitionTo(PlaybackStatus.completed), isTrue);
      expect(PlaybackStatus.playing.canTransitionTo(PlaybackStatus.loading), isTrue);
      expect(PlaybackStatus.playing.canTransitionTo(PlaybackStatus.error), isTrue);
      expect(PlaybackStatus.playing.canTransitionTo(PlaybackStatus.idle), isTrue);
    });

    test('Completed state requires reloading or restarting before playing', () {
      expect(PlaybackStatus.completed.canTransitionTo(PlaybackStatus.loading), isTrue);
      expect(PlaybackStatus.completed.canTransitionTo(PlaybackStatus.idle), isTrue);
      expect(PlaybackStatus.completed.canTransitionTo(PlaybackStatus.playing), isTrue);

      expect(PlaybackStatus.completed.canTransitionTo(PlaybackStatus.paused), isFalse);
      expect(PlaybackStatus.completed.canTransitionTo(PlaybackStatus.buffering), isFalse);
    });

    test('Error state requires reloading before playback can resume', () {
      expect(PlaybackStatus.error.canTransitionTo(PlaybackStatus.loading), isTrue);
      expect(PlaybackStatus.error.canTransitionTo(PlaybackStatus.idle), isTrue);

      expect(PlaybackStatus.error.canTransitionTo(PlaybackStatus.playing), isFalse);
      expect(PlaybackStatus.error.canTransitionTo(PlaybackStatus.paused), isFalse);
      expect(PlaybackStatus.error.canTransitionTo(PlaybackStatus.buffering), isFalse);
      expect(PlaybackStatus.error.canTransitionTo(PlaybackStatus.completed), isFalse);
    });
  });
}
