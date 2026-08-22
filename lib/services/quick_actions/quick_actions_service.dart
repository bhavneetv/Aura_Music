import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';
import '../../providers/playback_provider.dart';
import '../storage/storage_service.dart';

class QuickActionsService {
  QuickActionsService._();
  static final QuickActionsService instance = QuickActionsService._();

  final QuickActions _quickActions = const QuickActions();
  ProviderContainer? _container;
  bool _initialized = false;

  Future<void> init(ProviderContainer container) async {
    _container = container;

    try {
      _quickActions.initialize((String shortcutType) {
        debugPrint('[QuickActions] Triggered shortcut: $shortcutType');
        _handleShortcut(shortcutType);
      });
      _initialized = true;
      await updateShortcuts();
    } catch (e) {
      debugPrint('[QuickActions] Failed to initialize quick actions: $e');
    }
  }

  void _handleShortcut(String shortcutType) {
    if (_container == null) return;
    final notifier = _container!.read(playbackProvider.notifier);

    switch (shortcutType) {
      case 'action_resume':
        notifier.resumePlayback();
        break;
      case 'action_shuffle':
        notifier.shuffleAll();
        break;
      case 'action_recent_playlist':
        notifier.playRecentPlaylist();
        break;
      default:
        debugPrint('[QuickActions] Unknown shortcut type: $shortcutType');
        break;
    }
  }

  Future<void> updateShortcuts({String? recentPlaylistTitle}) async {
    if (!_initialized) return;

    try {
      final playlistName = recentPlaylistTitle ?? _getMostRecentPlaylistName();

      await _quickActions.setShortcutItems(<ShortcutItem>[
        const ShortcutItem(
          type: 'action_resume',
          localizedTitle: 'Resume playback',
          icon: 'play_arrow',
        ),
        const ShortcutItem(
          type: 'action_shuffle',
          localizedTitle: 'Shuffle all',
          icon: 'shuffle',
        ),
        ShortcutItem(
          type: 'action_recent_playlist',
          localizedTitle: 'Play $playlistName',
          icon: 'playlist_play',
        ),
      ]);
      debugPrint('[QuickActions] Dynamic shortcuts updated: Play $playlistName');
    } catch (e) {
      debugPrint('[QuickActions] Error updating shortcut items: $e');
    }
  }

  String _getMostRecentPlaylistName() {
    final playlists = StorageService.getPlaylists();
    if (playlists.isNotEmpty) {
      final first = playlists.first;
      final name = first['name']?.toString() ?? '';
      if (name.isNotEmpty) return name;
    }

    final downloadedPlaylists = StorageService.getDownloadedPlaylists();
    if (downloadedPlaylists.isNotEmpty) {
      final name = downloadedPlaylists.first['name']?.toString() ?? '';
      if (name.isNotEmpty) return name;
    }

    final favs = StorageService.getFavoriteTracks();
    if (favs.isNotEmpty) {
      return 'Favorites';
    }

    return 'Recent Queue';
  }
}
