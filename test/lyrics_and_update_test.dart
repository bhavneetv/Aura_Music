import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/lyrics/lyrics_service.dart';
import 'package:music_app/services/version/version_service.dart';

void main() {
  group('Version and Update Logic Tests', () {
    test('AppVersionService default version is 7.1 with code 71', () {
      expect(AppVersionService.versionName, equals('7.1'));
      expect(AppVersionService.versionCode, equals('71'));
      expect(AppVersionService.releaseTag, equals('v7.1'));
      expect(AppVersionService.releaseName, contains('7.1'));
    });
  });

  group('Lyrics Title and Artist Sanitization Tests', () {
    test('cleanTrackTitle removes video, lyric, and remaster tags', () {
      expect(
        LyricsService.cleanTrackTitle('Shape of You (Official Music Video)'),
        equals('Shape of You'),
      );
      expect(
        LyricsService.cleanTrackTitle('Starboy (feat. Daft Punk)'),
        equals('Starboy'),
      );
      expect(
        LyricsService.cleanTrackTitle('Kesariya (From "Brahmastra")'),
        equals('Kesariya'),
      );
      expect(
        LyricsService.cleanTrackTitle('In The End [Official Video]'),
        equals('In The End'),
      );
      expect(
        LyricsService.cleanTrackTitle('Blinding Lights - Remastered 2020'),
        equals('Blinding Lights'),
      );
    });

    test('cleanTrackTitle does not collapse titles that start with parentheses', () {
      final res = LyricsService.cleanTrackTitle('(Don\'t Fear) The Reaper');
      expect(res.isNotEmpty, isTrue);
      expect(res, equals('(Don\'t Fear) The Reaper'));
    });

    test('cleanArtistName extracts primary artist', () {
      expect(
        LyricsService.cleanArtistName('Pritam, Arijit Singh, Amitabh Bhattacharya'),
        equals('Pritam'),
      );
      expect(
        LyricsService.cleanArtistName('The Weeknd feat. Daft Punk'),
        equals('The Weeknd'),
      );
      expect(
        LyricsService.cleanArtistName('Ed Sheeran & Justin Bieber'),
        equals('Ed Sheeran'),
      );
      expect(
        LyricsService.cleanArtistName('David Guetta / Bebe Rexha'),
        equals('David Guetta'),
      );
    });
  });

  group('Lyrics LRC Parser Tests', () {
    test('parseLrc correctly parses standard LRC timestamps and text', () {
      const lrcData = '''
[00:12.50]Line one text
[00:15.80]Line two text
[01:02.100]Line three after one minute
''';
      final parsed = parseLrc(lrcData);
      expect(parsed.length, equals(3));
      expect(parsed[0].text, equals('Line one text'));
      expect(parsed[0].time, equals(const Duration(seconds: 12, milliseconds: 500)));
      expect(parsed[1].text, equals('Line two text'));
      expect(parsed[1].time, equals(const Duration(seconds: 15, milliseconds: 800)));
      expect(parsed[2].text, equals('Line three after one minute'));
      expect(parsed[2].time, equals(const Duration(minutes: 1, seconds: 2, milliseconds: 100)));
    });

    test('currentLineIndex correctly identifies active line with offset', () {
      final lines = [
        const LyricLine(Duration(seconds: 0), 'Intro'),
        const LyricLine(Duration(seconds: 10), 'Verse 1'),
        const LyricLine(Duration(seconds: 25), 'Chorus'),
      ];

      expect(currentLineIndex(lines, const Duration(seconds: 5), offsetMs: 0), equals(0));
      expect(currentLineIndex(lines, const Duration(seconds: 12), offsetMs: 0), equals(1));
      expect(currentLineIndex(lines, const Duration(seconds: 30), offsetMs: 0), equals(2));
    });
  });
}
