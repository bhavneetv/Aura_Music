import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    print('Testing video ZeaqjybbzzM...');
    final manifest = await yt.videos.streamsClient.getManifest('ZeaqjybbzzM');
    print('Audio only streams count: ${manifest.audioOnly.length}');
    for (final s in manifest.audioOnly) {
      print('Stream: ${s.tag} | ${s.container.name} | ${s.codec.mimeType} | ${s.bitrate} | size: ${s.size}');
    }

    // Try fetching with different streams
    final audioStream = manifest.audioOnly.withHighestBitrate();
    print('\nHighest bitrate stream URL:\n${audioStream.url}');

    final dio = Dio();
    
    // Test 1: No headers
    try {
      final res = await dio.get(
        audioStream.url.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=0-1024'},
        ),
      );
      print('Test 1 (No headers) status: ${res.statusCode}');
    } catch (e) {
      print('Test 1 failed: $e');
    }

    // Test 2: Standard Android ExoPlayer user agent
    try {
      final res = await dio.get(
        audioStream.url.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'User-Agent': 'AndroidXMedia3/1.4.1 (ExoPlayerLib)',
            'Range': 'bytes=0-1024',
          },
        ),
      );
      print('Test 2 (ExoPlayer UA) status: ${res.statusCode}');
    } catch (e) {
      print('Test 2 failed: $e');
    }

    // Test 3: With jiosaavn referer
    try {
      final res = await dio.get(
        audioStream.url.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Referer': 'https://www.jiosaavn.com/',
            'Range': 'bytes=0-1024',
          },
        ),
      );
      print('Test 3 (JioSaavn Referer) status: ${res.statusCode}');
    } catch (e) {
      print('Test 3 failed: $e');
    }

    // Test 4: M4A / MP4 stream
    final mp4Streams = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
    if (mp4Streams.isNotEmpty) {
      final mp4Stream = mp4Streams.first;
      print('\nTesting MP4 stream: ${mp4Stream.tag} ${mp4Stream.container.name}...');
      try {
        final res = await dio.get(
          mp4Stream.url.toString(),
          options: Options(
            responseType: ResponseType.stream,
            headers: {'Range': 'bytes=0-1024'},
          ),
        );
        print('MP4 stream status: ${res.statusCode}');
      } catch (e) {
        print('MP4 stream failed: $e');
      }
    }
  } catch (e, st) {
    print('Error: $e\n$st');
  } finally {
    yt.close();
  }
}
