import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../version/version_service.dart';

class UpdateService {
  /// Configure your GitHub Username and Repository Name here
  static const String githubOwner = 'bhavneetv';
  static const String githubRepo = 'Aura_Music';

  /// Native MethodChannel for in-app APK installer on Android
  static const MethodChannel _installerChannel =
      MethodChannel('com.example.music_app/app_installer');

  /// Current App Version (Dynamically read from version.properties via AppVersionService)
  static String get currentVersion => AppVersionService.versionName;

  /// GitHub Releases API URL for latest release
  static String get _apiUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Invokes the native Android Package Installer for the downloaded APK file.
  static Future<bool> installApk(String filePath) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final canInstall =
          await _installerChannel.invokeMethod<bool>('canRequestPackageInstalls') ?? true;
      if (!canInstall) {
        await _installerChannel.invokeMethod('openInstallPermissionSettings');
      }
      final result =
          await _installerChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return result ?? false;
    } catch (e) {
      debugPrint('Error triggering native APK install: $e');
      return false;
    }
  }

  /// Checks GitHub for new releases and shows a dialog if an update is found.
  /// Set [silentIfLatest] to true if manually triggering from Settings.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool silentIfLatest = false,
  }) async {
    if (kIsWeb) return;

    // Network connectivity check
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offline mode active: Cannot check for updates.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline mode active: Cannot check for updates.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final response = await Dio().get(
        _apiUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;

        // Extract raw tag version (e.g., "v7.1" or "7.1")
        final rawTagName = data['tag_name']?.toString() ?? '';
        final latestVersion = rawTagName.replaceAll(RegExp(r'[^0-9.]'), '');

        final releaseName = data['name']?.toString() ?? 'v$latestVersion';
        final releaseNotes = data['body']?.toString() ?? 'New features and bug fixes.';
        final releasePageUrl = data['html_url']?.toString() ??
            'https://github.com/$githubOwner/$githubRepo/releases/latest';

        // Check if there is an APK asset attached to the release
        String downloadUrl = releasePageUrl;
        final assets = data['assets'] as List?;
        if (assets != null && assets.isNotEmpty) {
          final apkAsset = assets.firstWhere(
            (asset) => asset['name']?.toString().endsWith('.apk') ?? false,
            orElse: () => null,
          );
          if (apkAsset != null && apkAsset['browser_download_url'] != null) {
            downloadUrl = apkAsset['browser_download_url'].toString();
          }
        }

        // Compare current app version with latest GitHub release version
        if (_isVersionGreater(latestVersion, currentVersion)) {
          if (context.mounted) {
            _showUpdateDialog(
              context,
              latestVersion: latestVersion,
              releaseName: releaseName,
              releaseNotes: releaseNotes,
              downloadUrl: downloadUrl,
            );
          }
        } else if (silentIfLatest) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You are already on the latest version!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('GitHub Release update check failed: $e');
      if (silentIfLatest && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not check for updates: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Helper to compare two semantic version strings (e.g. "7.1" > "7.0")
  static bool _isVersionGreater(String latest, String current) {
    if (latest.isEmpty || current.isEmpty) return false;

    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      final latestPart = i < latestParts.length ? latestParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  /// Displays the custom update dialog popup
  static void _showUpdateDialog(
    BuildContext context, {
    required String latestVersion,
    required String releaseName,
    required String releaseNotes,
    required String downloadUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final accentColor = theme.colorScheme.primary;
        final isAndroid = !kIsWeb && Platform.isAndroid;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {},
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: theme.colorScheme.surface,
            contentPadding: const EdgeInsets.all(24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: accentColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Update Required',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Version $latestVersion is required to continue',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    releaseName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      releaseNotes.trim(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(
                    isAndroid ? Icons.download_for_offline_rounded : Icons.open_in_browser_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: Text(
                    isAndroid ? 'Download & Install Update' : 'Update Now',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    if (isAndroid) {
                      Navigator.pop(ctx);
                      _showDownloadProgressDialog(
                        context,
                        downloadUrl: downloadUrl,
                        latestVersion: latestVersion,
                        releaseName: releaseName,
                      );
                    } else {
                      final uri = Uri.parse(downloadUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays the interactive download progress popup on Android
  static void _showDownloadProgressDialog(
    BuildContext context, {
    required String downloadUrl,
    required String latestVersion,
    required String releaseName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        downloadUrl: downloadUrl,
        latestVersion: latestVersion,
        releaseName: releaseName,
      ),
    );
  }
}

/// A stateful dialog that manages downloading the APK and showing real-time progress
class _DownloadProgressDialog extends StatefulWidget {
  final String downloadUrl;
  final String latestVersion;
  final String releaseName;

  const _DownloadProgressDialog({
    required this.downloadUrl,
    required this.latestVersion,
    required this.releaseName,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  bool _isDownloading = true;
  bool _isCompleted = false;
  String? _errorMessage;
  String? _savedFilePath;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog dismissed');
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _isCompleted = false;
      _errorMessage = null;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
    });

    _cancelToken = CancelToken();

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/Aura_v${widget.latestVersion}.apk';
      _savedFilePath = savePath;

      // Clean up previous partial or existing file
      final file = File(savePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final dio = Dio();
      await dio.download(
        widget.downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
        ),
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            if (total > 0) {
              _progress = (received / total).clamp(0.0, 1.0);
            }
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _isCompleted = true;
        _progress = 1.0;
      });

      // Automatically launch the Android APK install prompt
      await _triggerInstall(savePath);
    } catch (e) {
      if (CancelToken.isCancel(e as dynamic)) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _triggerInstall(String filePath) async {
    final success = await UpdateService.installApk(filePath);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Installation launched. If prompted, please allow installing apps from Aura.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {},
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.all(24),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isCompleted
                    ? Colors.green.withValues(alpha: 0.15)
                    : (_errorMessage != null
                        ? Colors.red.withValues(alpha: 0.15)
                        : accentColor.withValues(alpha: 0.15)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isCompleted
                    ? Icons.check_circle_rounded
                    : (_errorMessage != null
                        ? Icons.error_outline_rounded
                        : Icons.downloading_rounded),
                color: _isCompleted
                    ? Colors.green
                    : (_errorMessage != null ? Colors.red : accentColor),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCompleted
                        ? 'Download Complete'
                        : (_errorMessage != null
                            ? 'Download Failed'
                            : 'Downloading Update'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Aura v${widget.latestVersion}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _totalBytes > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _totalBytes > 0
                        ? '${(_receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                        : 'Connecting...',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _totalBytes > 0 ? '${(_progress * 100).toInt()}%' : '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ] else if (_isCompleted) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security_update_good_rounded, color: Colors.green, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ready to install! Tap "Install Update Now" to proceed.',
                        style: TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Error: $_errorMessage',
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_isCompleted) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.install_mobile_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Install Update Now',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (_savedFilePath != null) {
                    _triggerInstall(_savedFilePath!);
                  }
                },
              ),
            ),
          ] else if (_errorMessage != null) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: const Text('Browser'),
                    onPressed: () async {
                      final uri = Uri.parse(widget.downloadUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                    label: const Text('Retry', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      elevation: 0,
                    ),
                    onPressed: _startDownload,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
