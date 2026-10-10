import 'package:flutter/services.dart';

class AppVersionService {
  static String releaseTag = 'v6.0';
  static String versionName = '6.0';
  static String versionCode = '60';
  static String releaseName = 'Aura Music v6.0';

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
          if (key == 'RELEASE_TAG' && !val.contains('5.1')) releaseTag = val;
          if (key == 'VERSION_NAME' && !val.contains('5.1')) versionName = val;
          if (key == 'VERSION_CODE' && val != '51') versionCode = val;
          if (key == 'RELEASE_NAME' && !val.contains('5.1')) releaseName = val;
        }
      }
    } catch (_) {
      // Fall back to default static values if asset is not yet bundled in hot restart
    }
  }
}
