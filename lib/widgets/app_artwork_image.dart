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
      color: Colors.grey.shade800,
      child: Icon(
        Icons.music_note_rounded,
        size: (width != null && width! < 40) ? 18 : 24,
        color: Colors.white54,
      ),
    );

    final Widget fallback = placeholder ?? defaultPlaceholder;

    String targetPath = artworkUrl.trim();

    // Check if there is a downloaded offline cover art file for this track ID
    if (trackId != null && trackId!.isNotEmpty) {
      final downloadedArt = StorageService.getDownloadedArtworkPath(trackId!);
      if (downloadedArt != null && File(downloadedArt).existsSync()) {
        targetPath = downloadedArt;
      }
    }

    if (targetPath.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: fallback,
      );
    }

    // Fix file:// scheme if present
    if (targetPath.startsWith('file://')) {
      targetPath = Uri.parse(targetPath).toFilePath();
    }

    final isLocalFile = !targetPath.startsWith('http://') && !targetPath.startsWith('https://');

    Widget imageWidget;

    if (isLocalFile) {
      final file = File(targetPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        imageWidget = Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => fallback,
        );
      } else {
        imageWidget = fallback;
      }
    } else {
      imageWidget = Image.network(
        targetPath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) {
          // If network image fails (offline mode), attempt to render downloaded local cover art file
          if (trackId != null && trackId!.isNotEmpty) {
            final offlineArt = StorageService.getDownloadedArtworkPath(trackId!);
            if (offlineArt != null && File(offlineArt).existsSync()) {
              return Image.file(
                File(offlineArt),
                width: width,
                height: height,
                fit: fit,
                errorBuilder: (_, __, ___) => fallback,
              );
            }
          }
          return fallback;
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
