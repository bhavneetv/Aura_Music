import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../storage/storage_service.dart';
import '../audio/audio_url_resolver.dart';
import '../../models/track.dart';

class DownloadTask {
  final Track track;
  final double progress; // 0.0 to 1.0
  final String status; // 'pending', 'downloading', 'paused', 'completed', 'failed'
  final CancelToken cancelToken;

  DownloadTask({
    required this.track,
    this.progress = 0.0,
    this.status = 'pending',
    required this.cancelToken,
  });

  DownloadTask copyWith({
    double? progress,
    String? status,
  }) {
    return DownloadTask(
      track: track,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      cancelToken: cancelToken,
    );
  }
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal();

  final Map<String, DownloadTask> _tasks = {};
  final Dio _dio = Dio();

  Map<String, DownloadTask> get tasks => _tasks;

  List<Track> getDownloadedTracksList() {
    return StorageService.getFullDownloadedTracks();
  }

  bool isDownloaded(String trackId) {
    final localPath = getLocalPath(trackId);
    if (localPath == null) return false;
    final file = File(localPath);
    return file.existsSync() && file.lengthSync() > 0;
  }

  String? getLocalPath(String trackId) {
    final mapped = StorageService.getDownloadedTracks();
    if (!mapped.containsKey(trackId)) return null;
    final file = File(mapped[trackId]!);
    if (file.existsSync() && file.lengthSync() > 0) {
      return file.path;
    }
    return null;
  }

  // ── Download Actions ────────────────────────────────────────

  Future<void> startDownload(Track track) async {
    if (isDownloaded(track.id)) return;
    if (_tasks.containsKey(track.id)) return;

    final cancelToken = CancelToken();
    final task = DownloadTask(track: track, status: 'downloading', cancelToken: cancelToken);
    _tasks[track.id] = task;
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/downloads');
      if (!folder.existsSync()) {
        await folder.create(recursive: true);
      }

      final localPath = '${folder.path}/${track.id}.mp4';
      final artworkLocalPath = '${folder.path}/${track.id}_cover.jpg';

      // Download cover art image if URL is valid remote HTTP/HTTPS
      if (track.artworkUrl.isNotEmpty && (track.artworkUrl.startsWith('http://') || track.artworkUrl.startsWith('https://'))) {
        try {
          await _dio.download(
            track.artworkUrl,
            artworkLocalPath,
            cancelToken: cancelToken,
          );
        } catch (e) {
          print('[DOWNLOAD] Failed downloading cover art for "${track.title}": $e');
        }
      }

      // Download audio URL
      String url = track.audioUrl;
      if (url.isEmpty || url.startsWith('file://') || url.contains('saavncdn.com')) {
        try {
          final resolved = await AudioUrlResolver.instance.resolveAudioUrl(track, forceFresh: false);
          if (resolved != null && resolved.isNotEmpty) {
            url = resolved;
          }
        } catch (_) {}
      }

      if (url.isEmpty) {
        try {
          final resolvedFresh = await AudioUrlResolver.instance.resolveAudioUrl(track, forceFresh: true);
          if (resolvedFresh != null && resolvedFresh.isNotEmpty) {
            url = resolvedFresh;
          }
        } catch (_) {}
      }

      if (url.isEmpty) {
        throw Exception('Audio URL not available');
      }

      await _dio.download(
        url,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total).clamp(0.0, 1.0);
            _tasks[track.id] = task.copyWith(progress: progress);
            notifyListeners();
          }
        },
      );

      final String? artPath = File(artworkLocalPath).existsSync() && File(artworkLocalPath).lengthSync() > 0
          ? artworkLocalPath
          : null;

      // Register complete with full track metadata and local artwork path
      _tasks[track.id] = task.copyWith(status: 'completed', progress: 1.0);
      await StorageService.registerDownloadTrack(track, localPath, artworkLocalPath: artPath);
      notifyListeners();
      
      // Remove from active task tracker after a delay
      Future.delayed(const Duration(seconds: 3), () {
        _tasks.remove(track.id);
        notifyListeners();
      });
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _tasks.remove(track.id);
      } else {
        _tasks[track.id] = task.copyWith(status: 'failed');
      }
      notifyListeners();
    }
  }

  void cancelDownload(String trackId) {
    if (_tasks.containsKey(trackId)) {
      _tasks[trackId]!.cancelToken.cancel();
      _tasks.remove(trackId);
      notifyListeners();
    }
  }

  Future<void> deleteDownload(String trackId) async {
    final localPath = getLocalPath(trackId);
    if (localPath != null) {
      final file = File(localPath);
      if (file.existsSync()) {
        await file.delete();
      }
    }
    final artworkPath = StorageService.getDownloadedArtworkPath(trackId);
    if (artworkPath != null) {
      final artFile = File(artworkPath);
      if (artFile.existsSync()) {
        await artFile.delete();
      }
    }
    await StorageService.deleteDownloadRecord(trackId);
    notifyListeners();
  }

  Future<void> downloadPlaylist(List<Track> tracks, {Function(int completed, int total)? onProgress}) async {
    int completed = 0;
    final total = tracks.length;
    onProgress?.call(completed, total);

    for (final track in tracks) {
      if (!isDownloaded(track.id)) {
        await startDownload(track);
      }
      completed++;
      onProgress?.call(completed, total);
    }
  }
}
