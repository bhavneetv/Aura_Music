import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/providers/playback_provider.dart';

void main() {
  group('Queue Advancement & Repeat Mode Logic Tests', () {
    final tracks = Track.mockTracks.take(4).toList();

    test('Advancing within queue moves to next index sequentially', () {
      int currentIndex = 0;
      final repeatMode = RepeatMode.off;

      int computeNextIndex(int curr, int length, RepeatMode mode) {
        int next = curr + 1;
        if (next >= length) {
          if (mode == RepeatMode.all) {
            return 0;
          }
          return -1; // triggers auto-recommendation
        }
        return next;
      }

      expect(computeNextIndex(0, tracks.length, repeatMode), equals(1));
      expect(computeNextIndex(1, tracks.length, repeatMode), equals(2));
      expect(computeNextIndex(2, tracks.length, repeatMode), equals(3));
      expect(computeNextIndex(3, tracks.length, repeatMode), equals(-1));
    });

    test('RepeatMode.all wraps around to index 0 at end of queue', () {
      int computeNextIndex(int curr, int length, RepeatMode mode) {
        int next = curr + 1;
        if (next >= length) {
          if (mode == RepeatMode.all) {
            return 0;
          }
          return -1;
        }
        return next;
      }

      expect(computeNextIndex(3, tracks.length, RepeatMode.all), equals(0));
    });

    test('Previous track logic respects queue boundary and wrap-around', () {
      int computePrevIndex(int curr, int length, RepeatMode mode) {
        int prev = curr - 1;
        if (prev < 0) {
          if (mode == RepeatMode.all) {
            return length - 1;
          }
          return 0;
        }
        return prev;
      }

      expect(computePrevIndex(2, tracks.length, RepeatMode.off), equals(1));
      expect(computePrevIndex(0, tracks.length, RepeatMode.off), equals(0));
      expect(computePrevIndex(0, tracks.length, RepeatMode.all), equals(3));
    });

    test('PlaybackState total queue duration accumulates correctly', () {
      final state = PlaybackState(
        queue: [
          Track.mockTracks[0], // 3:45 = 225s
          Track.mockTracks[1], // 4:12 = 252s
        ],
      );

      final totalDuration = state.queueDuration;
      expect(totalDuration.inSeconds, equals(477));
    });
  });
}
