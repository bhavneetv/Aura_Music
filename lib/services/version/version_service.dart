import 'package:flutter/services.dart';

class AppVersionService {
  static String releaseTag = 'v7.0';
  static String versionName = '7.0';
  static String versionCode = '70';
  static String releaseName = 'Aura Music v7.0';

  static Future<void> init() async {
    try {
      final content = await rootBundle.loadString('version.properties');
      final lines = content.split('\n');
      String? parsedTag;
      String? parsedName;
      String? parsedCode;
      String? parsedReleaseName;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final val = parts[1].trim();
          if (key == 'RELEASE_TAG') parsedTag = val;
          if (key == 'VERSION_NAME') parsedName = val;
          if (key == 'VERSION_CODE') parsedCode = val;
          if (key == 'RELEASE_NAME') parsedReleaseName = val;
        }
      }

      final parsedCodeInt = int.tryParse(parsedCode ?? '') ?? 0;
      final currentCodeInt = int.tryParse(versionCode) ?? 70;
      if (parsedCodeInt >= currentCodeInt) {
        if (parsedTag != null && parsedTag.isNotEmpty) releaseTag = parsedTag;
        if (parsedName != null && parsedName.isNotEmpty) versionName = parsedName;
        if (parsedCode != null && parsedCode.isNotEmpty) versionCode = parsedCode;
        if (parsedReleaseName != null && parsedReleaseName.isNotEmpty) releaseName = parsedReleaseName;
      }
    } catch (_) {
      // Fall back to default static values if asset is not yet bundled in hot restart
    }
  }
}
