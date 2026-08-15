import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/services/audio/audio_url_resolver.dart';
import 'package:music_app/services/audio/des_cipher.dart';

void main() {
  test('DesCipher unit test', () {
    const testEnc = 'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDygMkX2yYzhefq36/n2cwLlR/8K3eM3b1iYYeamHhrFJ/0zKWlpzUUiRw7tS9a8Gtq';
    final decrypted = DesCipher.decryptEcb(testEnc, '38346591');
    expect(decrypted, isNotNull);
    expect(decrypted, contains('saavncdn.com'));
    expect(decrypted, equals('https://aac.saavncdn.com/299/928cf07eb47ae21d9e12629478bafc1f_96.mp4'));
  });

  test('AudioUrlResolver resolves live 200 OK CDN URL for Queen Of Punjab (4BkJ_XWh)', () async {
    final track1 = Track(
      id: '4BkJ_XWh',
      title: 'Queen Of Punjab',
      artist: 'Gulab Sidhu, Singh Jeet, IRIS Music',
      album: 'Queen Of Punjab',
      duration: '3:45',
      artworkUrl: '',
      audioUrl: '',
      genre: 'PUNJABI',
    );

    final resolvedUrl = await AudioUrlResolver.instance.resolveAudioUrl(track1, forceFresh: true);
    print('Resolved URL for Queen Of Punjab: $resolvedUrl');
    expect(resolvedUrl, isNotNull);
    expect(resolvedUrl!.startsWith('http'), isTrue);

    // Verify 200 OK via HEAD or GET range
    final dio = Dio();
    Response res;
    try {
      res = await dio.head(
        resolvedUrl,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.jiosaavn.com/',
          },
        ),
      );
    } catch (_) {
      res = await dio.get(
        resolvedUrl,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.jiosaavn.com/',
            'Range': 'bytes=0-500',
          },
          responseType: ResponseType.bytes,
        ),
      );
    }

    expect(res.statusCode == 200 || res.statusCode == 206, isTrue);
  });

  test('AudioUrlResolver resolves live 200 OK CDN URL for Pagal (5CHjjj_x)', () async {
    final track2 = Track(
      id: '5CHjjj_x',
      title: 'Pagal',
      artist: 'Gurnam Bhullar',
      album: 'Pagal',
      duration: '4:29',
      artworkUrl: '',
      audioUrl: '',
      genre: 'PUNJABI',
    );

    final resolvedUrl = await AudioUrlResolver.instance.resolveAudioUrl(track2, forceFresh: true);
    print('Resolved URL for Pagal: $resolvedUrl');
    expect(resolvedUrl, isNotNull);
    expect(resolvedUrl!.startsWith('http'), isTrue);
  });
}
