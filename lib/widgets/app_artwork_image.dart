import 'dart:io';
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

    // If targetUrl is local or empty, but we have a trackId, check if a remote HTTP artwork URL exists
    if ((targetUrl.isEmpty || (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://'))) &&
        trackId != null &&
        trackId!.isNotEmpty) {
      final remoteUrl = StorageService.getRemoteArtworkUrl(trackId!);
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        targetUrl = remoteUrl;
      }
    }

    // 1. If HTTP/HTTPS network URL is available, try Image.network
    if (targetUrl.startsWith('http://') || targetUrl.startsWith('https://')) {
      Widget netImage = Image.network(
        targetUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) {
          // Network image failed (e.g. device is offline). Try rendering local downloaded cover art file.
          if (trackId != null && trackId!.isNotEmpty) {
            final offlineArt = StorageService.getDownloadedArtworkPath(trackId!);
            if (offlineArt != null) {
              final file = File(offlineArt);
              if (file.existsSync() && file.lengthSync() > 0) {
                return Image.file(
                  file,
                  width: width,
                  height: height,
                  fit: fit,
                  errorBuilder: (_, __, ___) => fallback,
                );
              }
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

    // 2. Check local file path or downloaded artwork file
    String localPath = targetUrl;
    if (localPath.startsWith('file://')) {
      localPath = Uri.parse(localPath).toFilePath();
    }

    if (localPath.isEmpty && trackId != null && trackId!.isNotEmpty) {
      final downloadedArt = StorageService.getDownloadedArtworkPath(trackId!);
      if (downloadedArt != null) {
        localPath = downloadedArt;
      }
    }

    if (localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        Widget fileImage = Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => fallback,
        );
        if (borderRadius != null) {
          return ClipRRect(borderRadius: borderRadius!, child: fileImage);
        }
        return fileImage;
      }
    }

    // 3. Fallback gradient
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: fallback);
    }
    return fallback;
  }
}
