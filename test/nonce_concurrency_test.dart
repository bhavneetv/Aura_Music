import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nonce-Based Concurrency & Rapid Track Switching Tests', () {
    test('Rapid consecutive track requests increment nonce and discard stale resolutions', () async {
      int activeNonce = 0;
      String currentPlayingId = '';
      final List<String> discardedResolutions = [];

      Future<void> simulateStreamTrack(String trackId, int requestNonce) async {
        // Simulates async URL resolution delay
        await Future.delayed(const Duration(milliseconds: 50));

        if (requestNonce != activeNonce) {
          discardedResolutions.add(trackId);
          return;
        }

        currentPlayingId = trackId;
      }

      // User rapidly selects Song 1, Song 2, Song 3
      final nonce1 = ++activeNonce;
      final f1 = simulateStreamTrack('track_1', nonce1);

      final nonce2 = ++activeNonce;
      final f2 = simulateStreamTrack('track_2', nonce2);

      final nonce3 = ++activeNonce;
      final f3 = simulateStreamTrack('track_3', nonce3);

      await Future.wait([f1, f2, f3]);

      // Only Song 3 should have actually started playing
      expect(currentPlayingId, equals('track_3'));
      expect(discardedResolutions, contains('track_1'));
      expect(discardedResolutions, contains('track_2'));
      expect(discardedResolutions.length, equals(2));
    });

    test('Stale completion does not advance queue if newer nonce is active', () {
      int activeNonce = 10;
      int lastCompletedNonce = -1;
      bool nextTrackTriggered = false;

      void onPlayerCompleted(int incomingNonce) {
        if (incomingNonce == activeNonce && incomingNonce != lastCompletedNonce) {
          lastCompletedNonce = incomingNonce;
          nextTrackTriggered = true;
        }
      }

      // Stale completion event from an old player
      onPlayerCompleted(8);
      expect(nextTrackTriggered, isFalse);

      // Current completion event
      onPlayerCompleted(10);
      expect(nextTrackTriggered, isTrue);

      // Duplicate completion event for same track
      nextTrackTriggered = false;
      onPlayerCompleted(10);
      expect(nextTrackTriggered, isFalse);
    });
  });
}
