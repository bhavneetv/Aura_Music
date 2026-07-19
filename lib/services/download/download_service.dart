import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../storage/storage_service.dart';
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
    final Map<String, String> mapped = StorageService.getDownloadedTracks();
    final List<Track> tracks = [];
    final allPlaylists = StorageService.getPlaylists();
    
    // Scan standard mock tracks first
    for (final track in Track.mockTracks) {
      if (mapped.containsKey(track.id)) {
        tracks.add(track.copyWith(audioUrl: mapped[track.id]!));
      }
    }



    return tracks;
  }

  bool isDownloaded(String trackId) {
    final mapped = StorageService.getDownloadedTracks();
    if (!mapped.containsKey(trackId)) return false;
    final file = File(mapped[trackId]!);
    return file.existsSync();
  }

  String? getLocalPath(String trackId) {
    final mapped = StorageService.getDownloadedTracks();
    if (!mapped.containsKey(trackId)) return null;
    final file = File(mapped[trackId]!);
    if (file.existsSync()) {
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

      // Download audio URL
      String url = track.audioUrl;
      if (url.isEmpty) {
        // Recover first
        final res = await _dio.get('https://saavn.sumit.co/api/search/songs?query=${Uri.encodeComponent("${track.title} ${track.artist}")}');
        final results = res.data['data']?['results'] as List?;
        if (results != null && results.isNotEmpty) {
          url = results.first['downloadUrl']?.last['url']?.toString() ?? '';
        }
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

      // Register complete
      _tasks[track.id] = task.copyWith(status: 'completed', progress: 1.0);
      await StorageService.registerDownload(track.id, localPath);
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
      await StorageService.deleteDownloadRecord(trackId);
      notifyListeners();
    }
  }
}
