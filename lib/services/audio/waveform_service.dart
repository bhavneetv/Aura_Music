import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';

class WaveformService {
  WaveformService._();
  static final WaveformService instance = WaveformService._();

  final Map<String, List<double>> _memoryCache = {};
  final Map<String, Future<List<double>>> _inFlightRequests = {};
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 10)));

  /// Get or compute on-device waveform data for [track].
  /// Returns a list of normalized amplitude values (0.15 to 1.0) of length [barCount].
  Future<List<double>> getWaveform(Track track, {int barCount = 70}) async {
    final cacheKey = '${track.id}_$barCount';

    // 1. In-memory cache check
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    // 2. Persistent Hive cache check
    final cached = StorageService.getWaveformData(cacheKey);
    if (cached != null && cached.length == barCount) {
      _memoryCache[cacheKey] = cached;
      return cached;
    }

    // Deduplicate in-flight generation requests
    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey]!;
    }

    final future = _generateWaveform(track, barCount).then((data) {
      _memoryCache[cacheKey] = data;
      StorageService.saveWaveformData(cacheKey, data);
      _inFlightRequests.remove(cacheKey);
      return data;
    }).catchError((e) {
      _inFlightRequests.remove(cacheKey);
      final fallback = _generateFallbackWaveform(track.id, barCount);
      _memoryCache[cacheKey] = fallback;
      return fallback;
    });

    _inFlightRequests[cacheKey] = future;
    return future;
  }

  /// Internal generator: tries reading local file or downloading audio buffer chunks,
  /// with deterministic audio contour fallback.
  Future<List<double>> _generateWaveform(Track track, int barCount) async {
    final localPath = StorageService.getDownloadedTrackPath(track.id);
    final audioUrl = localPath ?? track.audioUrl;

    if (audioUrl.isNotEmpty) {
      // 1. Try local disk file
      final file = File(audioUrl);
      if (await file.exists()) {
        try {
          final length = await file.length();
          if (length > 1024) {
            final samples = await _extractAmplitudesFromFile(file, length, barCount);
            if (samples.isNotEmpty) return samples;
          }
        } catch (_) {}
      }

      // 2. Try network audio buffer chunk sampling (first 128KB - 256KB)
      if (audioUrl.startsWith('http://') || audioUrl.startsWith('https://')) {
        try {
          final response = await _dio.get<List<int>>(
            audioUrl,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'Range': 'bytes=0-262144', // Read first 256 KB
                'User-Agent': 'Mozilla/5.0 (Linux; Android 13)',
              },
            ),
          );
          if (response.data != null && response.data!.length > 1024) {
            final samples = _extractAmplitudesFromBytes(Uint8List.fromList(response.data!), barCount);
            if (samples.isNotEmpty) return samples;
          }
        } catch (_) {}
      }
    }

    // 3. Fallback to deterministic on-device acoustic contour generator
    return _generateFallbackWaveform(track.id, barCount);
  }

  /// Extracts amplitude RMS energy levels across audio file chunks
  Future<List<double>> _extractAmplitudesFromFile(File file, int fileLength, int barCount) async {
    final Uint8List bytes = await file.readAsBytes();
    return _extractAmplitudesFromBytes(bytes, barCount);
  }

  /// Calculates chunk RMS energy variance from raw audio byte buffers
  List<double> _extractAmplitudesFromBytes(Uint8List bytes, int barCount) {
    if (bytes.length < barCount * 16) return [];

    final rawAmplitudes = <double>[];
    final chunkSize = (bytes.length / barCount).floor();

    for (int i = 0; i < barCount; i++) {
      final start = i * chunkSize;
      final end = math.min(start + chunkSize, bytes.length);
      if (start >= end) break;

      double sumSq = 0.0;
      int sampleCount = 0;

      // Sample byte pairs as 16-bit PCM / audio frame energy indicators
      for (int j = start; j < end - 1; j += 4) {
        // Combine 2 bytes into int16
        final val = (bytes[j + 1] << 8) | bytes[j];
        final signedVal = val > 32767 ? val - 65536 : val;
        final normalized = signedVal / 32768.0;
        sumSq += normalized * normalized;
        sampleCount++;
      }

      final rms = sampleCount > 0 ? math.sqrt(sumSq / sampleCount) : 0.1;
      rawAmplitudes.add(rms);
    }

    if (rawAmplitudes.isEmpty) return [];

    // Find max value for normalization
    final maxAmp = rawAmplitudes.reduce(math.max);
    if (maxAmp <= 0.001) return [];

    // Normalize values between 0.18 and 1.0 with subtle dynamic smoothing
    final normalized = rawAmplitudes.map((val) {
      final norm = (val / maxAmp).clamp(0.0, 1.0);
      return (0.18 + (norm * 0.82)).clamp(0.18, 1.0);
    }).toList();

    return _smoothWaveform(normalized);
  }

  /// Smooths raw amplitude spikes into natural voice-note contours
  List<double> _smoothWaveform(List<double> amplitudes) {
    if (amplitudes.length < 3) return amplitudes;
    final result = List<double>.from(amplitudes);

    for (int i = 1; i < amplitudes.length - 1; i++) {
      result[i] = (amplitudes[i - 1] * 0.25) + (amplitudes[i] * 0.50) + (amplitudes[i + 1] * 0.25);
    }
    return result;
  }

  /// Deterministic acoustic frequency contour generator (fallback)
  /// Generates organic voice-note style wave bars based on track ID hash.
  List<double> _generateFallbackWaveform(String seedString, int barCount) {
    int hash = 0;
    for (int i = 0; i < seedString.length; i++) {
      hash = (hash * 31 + seedString.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    final rng = math.Random(hash);

    final amplitudes = <double>[];
    double current = 0.3 + (rng.nextDouble() * 0.4);

    for (int i = 0; i < barCount; i++) {
      // Intro and outro fade-in/fade-out
      final positionFactor = math.sin((i / (barCount - 1)) * math.pi);
      
      // Dynamic random walk with sine modulation
      final step = (rng.nextDouble() - 0.48) * 0.35;
      final sineMod = math.sin(i * 0.35) * 0.15;
      
      current = (current + step + sineMod).clamp(0.15, 1.0);
      final finalAmp = (current * (0.4 + (0.6 * positionFactor))).clamp(0.18, 1.0);
      amplitudes.add(double.parse(finalAmp.toStringAsFixed(3)));
    }

    return amplitudes;
  }
}
