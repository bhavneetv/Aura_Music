import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/voice/voice_search_service.dart';

void main() {
  group('VoiceSearchService Query Normalization', () {
    test('strips voice prefixes and app suffixes correctly', () {
      final service = VoiceSearchService.instance;

      expect(service.normalizeQuery('play Shape of You in Aura'), equals('shape of you'));
      expect(service.normalizeQuery('Hey Siri play Taylor Swift on Aura'), equals('taylor swift'));
      expect(service.normalizeQuery('play the song Blinding Lights in Aura'), equals('blinding lights'));
      expect(service.normalizeQuery('play me Punjabi Hits using Aura'), equals('punjabi hits'));
    });

    test('handles empty and general playback queries', () {
      final service = VoiceSearchService.instance;

      expect(service.normalizeQuery('play music on Aura'), equals('music'));
      expect(service.normalizeQuery('play in Aura'), equals(''));
    });
  });

  group('VoiceSearchService Voice Query Resolution', () {
    test('returns resume state for general music request', () {
      final service = VoiceSearchService.instance;
      final result = service.resolveVoiceQuery('play music on Aura');

      expect(result.type, equals(VoiceSearchResultType.resume));
      expect(result.isSuccess, isTrue);
    });

    test('gracefully returns noMatch for unknown tracks', () {
      final service = VoiceSearchService.instance;
      final result = service.resolveVoiceQuery('play xyzunexistingtrack123999 in Aura');

      expect(result.type, equals(VoiceSearchResultType.noMatch));
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Couldn\'t find'));
    });
  });
}
