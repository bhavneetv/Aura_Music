import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:home_widget/home_widget.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';

class HomeWidgetService {
  static const String appGroupId = 'group.com.example.musicApp';
  static const String androidWidgetName = 'AuraMusicWidgetProvider';
  static const String iOSWidgetName = 'AuraWidget';

  static bool _initialized = false;
  static String? _cachedTrackId;
  static String? _cachedArtPath;
  static bool _isResolvingArtwork = false;
  static String? _targetTrackId;
  static Track? _targetTrack;
  static String? _targetExplicitPath;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  /// Initializes App Group ID for iOS WidgetKit communication
  static Future<void> init() async {
    if (kIsWeb) return;
    if (_initialized) return;
    try {
      if (Platform.isIOS) {
        await HomeWidget.setAppGroupId(appGroupId);
      }
      _initialized = true;
    } catch (e) {
      debugPrint('HomeWidgetService init failed: $e');
    }
  }

  /// Updates the Material You (Android) and WidgetKit (iOS) home screen widgets
  static Future<void> updatePlaybackState({
    required Track? track,
    required bool isPlaying,
    String? localArtPath,
  }) async {
    if (kIsWeb) return;
    try {
      if (track == null) {
        _cachedTrackId = null;
        _cachedArtPath = null;
        _targetTrackId = null;
        _targetTrack = null;
        await Future.wait([
          HomeWidget.saveWidgetData<String>('track_title', 'Aura Music'),
          HomeWidget.saveWidgetData<String>('track_artist', 'Tap to play music'),
          HomeWidget.saveWidgetData<bool>('is_playing', false),
          HomeWidget.saveWidgetData<String>('track_art_path', ''),
        ]);
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          androidName: androidWidgetName,
          iOSName: iOSWidgetName,
        );
        return;
      }

      final title = track.title.trim().isNotEmpty ? track.title.trim() : 'Aura Music';
      final artist = track.artist.trim().isNotEmpty ? track.artist.trim() : 'Aura Music';

      // 1. Fast path: update text & playback state immediately
      await Future.wait([
        HomeWidget.saveWidgetData<String>('track_title', title),
        HomeWidget.saveWidgetData<String>('track_artist', artist),
        HomeWidget.saveWidgetData<bool>('is_playing', isPlaying),
      ]);

      // If artwork is already cached for this exact track, ensure it's saved
      if (_cachedTrackId == track.id && _cachedArtPath != null) {
        await HomeWidget.saveWidgetData<String>('track_art_path', _cachedArtPath!);
      }

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

      // 2. If track changed or artwork not yet cached, resolve in background
      _targetTrackId = track.id;
      _targetTrack = track;
      _targetExplicitPath = localArtPath;

      if (_cachedTrackId != track.id && !_isResolvingArtwork) {
        _processArtworkQueue();
      }
    } catch (e) {
      debugPrint('Error updating HomeWidget: $e');
    }
  }

  static Future<void> _processArtworkQueue() async {
    if (_isResolvingArtwork) return;
    _isResolvingArtwork = true;

    try {
      while (_targetTrackId != null && _targetTrackId != _cachedTrackId) {
        final track = _targetTrack;
        final explicitPath = _targetExplicitPath;
        final currentTargetId = _targetTrackId;

        if (track == null || currentTargetId == null) break;

        Uint8List? artBytes;

        // Check explicit local path
        if (explicitPath != null && explicitPath.isNotEmpty) {
          final f = File(explicitPath);
          if (f.existsSync() && f.lengthSync() > 0) {
            artBytes = await f.readAsBytes();
          }
        }

        // Check StorageService downloaded artwork
        if (artBytes == null) {
          try {
            final downloadedPath = StorageService.getDownloadedArtworkPath(track.id, title: track.title);
            if (downloadedPath != null && downloadedPath.isNotEmpty) {
              final f = File(downloadedPath);
              if (f.existsSync() && f.lengthSync() > 0) {
                artBytes = await f.readAsBytes();
              }
            }
          } catch (_) {}
        }

        // Check if track.artworkUrl is local file
        if (artBytes == null && track.artworkUrl.isNotEmpty) {
          if (!track.artworkUrl.startsWith('http://') && !track.artworkUrl.startsWith('https://')) {
            final clean = track.artworkUrl.startsWith('file://')
                ? Uri.parse(track.artworkUrl).toFilePath()
                : track.artworkUrl;
            final f = File(clean);
            if (f.existsSync() && f.lengthSync() > 0) {
              artBytes = await f.readAsBytes();
            }
          }
        }

        // Fetch remote artwork via Dio
        if (artBytes == null && track.artworkUrl.isNotEmpty) {
          if (track.artworkUrl.startsWith('http://') || track.artworkUrl.startsWith('https://')) {
            try {
              final response = await _dio.get<List<int>>(
                track.artworkUrl,
                options: Options(responseType: ResponseType.bytes),
              );
              if (response.data != null && response.data!.isNotEmpty) {
                artBytes = Uint8List.fromList(response.data!);
              }
            } catch (e) {
              debugPrint('Failed to download widget artwork: $e');
            }
          }
        }

        // If target track changed while downloading, continue loop for the newer track
        if (_targetTrackId != currentTargetId) {
          continue;
        }

        if (artBytes != null && artBytes.isNotEmpty) {
          try {
            final savedPath = await HomeWidget.saveFile(
              'track_art_path',
              artBytes,
              extension: 'jpg',
              appGroupId: Platform.isIOS ? appGroupId : null,
            );
            _cachedTrackId = currentTargetId;
            _cachedArtPath = savedPath;
            await HomeWidget.saveWidgetData<String>('track_art_path', savedPath);
          } catch (saveErr) {
            debugPrint('Error saving widget artwork file: $saveErr');
            _cachedTrackId = currentTargetId;
            _cachedArtPath = '';
            await HomeWidget.saveWidgetData<String>('track_art_path', '');
          }
        } else {
          _cachedTrackId = currentTargetId;
          _cachedArtPath = '';
          await HomeWidget.saveWidgetData<String>('track_art_path', '');
        }

        await HomeWidget.updateWidget(
          name: androidWidgetName,
          androidName: androidWidgetName,
          iOSName: iOSWidgetName,
        );
      }
    } catch (e) {
      debugPrint('Error in _processArtworkQueue: $e');
    } finally {
      _isResolvingArtwork = false;
    }
  }
}
