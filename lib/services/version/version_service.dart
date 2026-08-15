import 'package:flutter/services.dart';

class AppVersionService {
  static String releaseTag = 'v4.0';
  static String versionName = '4.0.0';
  static String versionCode = '40';
  static String releaseName = 'Aura Music v4.0';

  static Future<void> init() async {
    try {
      final content = await rootBundle.loadString('version.properties');
      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final val = parts[1].trim();
          if (key == 'RELEASE_TAG') releaseTag = val;
          if (key == 'VERSION_NAME') versionName = val;
          if (key == 'VERSION_CODE') versionCode = val;
          if (key == 'RELEASE_NAME') releaseName = val;
        }
      }
    } catch (e) {
      print('[AURA-VERSION] Failed to load version.properties asset: $e');
    }
  }
}
