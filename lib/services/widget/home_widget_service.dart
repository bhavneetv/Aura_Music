import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../../models/track.dart';

class HomeWidgetService {
  static const String appGroupId = 'group.com.example.musicApp';
  static const String androidWidgetName = 'AuraMusicWidgetProvider';
  static const String iOSWidgetName = 'AuraWidget';

  static bool _initialized = false;

  /// Initializes App Group ID for iOS WidgetKit communication
  static Future<void> init() async {
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
    try {
      final title = track?.title ?? 'Aura Music';
      final artist = track?.artist ?? 'Tap to play music';

      await Future.wait([
        HomeWidget.saveWidgetData<String>('track_title', title),
        HomeWidget.saveWidgetData<String>('track_artist', artist),
        HomeWidget.saveWidgetData<bool>('is_playing', isPlaying),
        if (localArtPath != null && localArtPath.isNotEmpty)
          HomeWidget.saveWidgetData<String>('track_art_path', localArtPath),
      ]);

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
    } catch (e) {
      debugPrint('Error updating HomeWidget: $e');
    }
  }
}
