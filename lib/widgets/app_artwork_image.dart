import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/storage/storage_service.dart';

class AppArtworkImage extends StatelessWidget {
  final String artworkUrl;
  final String? trackId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const AppArtworkImage({
    super.key,
    required this.artworkUrl,
    this.trackId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final Widget defaultPlaceholder = Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF231942), Color(0xFF0F0E17)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: (width != null && width! < 40) ? 18 : 24,
          color: Colors.white70,
        ),
      ),
    );

    final Widget fallback = placeholder ?? defaultPlaceholder;

    String targetUrl = artworkUrl.trim();

    final int? cacheW = width != null ? (width! * 2.5).round().clamp(48, 1200) : null;
    final int? cacheH = height != null ? (height! * 2.5).round().clamp(48, 1200) : null;

    // 1. Prioritize local downloaded cover art if available in cache (0ms latency, 100% offline - Non-web only)
    if (!kIsWeb) {
      String? localPath;
      if (targetUrl.isNotEmpty && (targetUrl.startsWith('/') || targetUrl.startsWith('file://'))) {
        try {
          localPath = targetUrl.startsWith('file://') ? Uri.parse(targetUrl).toFilePath() : targetUrl;
        } catch (_) {}
      } else if (trackId != null && trackId!.isNotEmpty) {
        localPath = StorageService.getDownloadedArtworkPath(trackId!);
      }

      if (localPath != null && localPath.isNotEmpty) {
        Widget fileImage = Image.file(
          File(localPath),
          width: width,
          height: height,
          fit: fit,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          errorBuilder: (_, __, ___) => fallback,
        );
        if (borderRadius != null) {
          return ClipRRect(borderRadius: borderRadius!, child: fileImage);
        }
        return fileImage;
      }
    }

    // 2. If targetUrl is empty but we have a trackId, check if remote HTTP URL is recorded
    if ((targetUrl.isEmpty || (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://'))) &&
        trackId != null &&
        trackId!.isNotEmpty) {
      final remoteUrl = StorageService.getRemoteArtworkUrl(trackId!);
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        targetUrl = remoteUrl;
      }
    }

    // 3. Render remote HTTP/HTTPS network image if available
    if (targetUrl.startsWith('http://') || targetUrl.startsWith('https://')) {
      Widget netImage = Image.network(
        targetUrl,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        errorBuilder: (_, __, ___) {
          // If offline and remote fails, try fallback to downloaded art
          if (!kIsWeb && trackId != null && trackId!.isNotEmpty) {
            final offlineArt = StorageService.getDownloadedArtworkPath(trackId!);
            if (offlineArt != null && offlineArt.isNotEmpty) {
              return Image.file(
                File(offlineArt),
                width: width,
                height: height,
                fit: fit,
                cacheWidth: cacheW,
                cacheHeight: cacheH,
                errorBuilder: (_, __, ___) => fallback,
              );
            }
          }
          return fallback;
        },
      );

      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: netImage);
      }
      return netImage;
    }

    // 4. Fallback gradient
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: fallback);
    }
    return fallback;
  }
}
