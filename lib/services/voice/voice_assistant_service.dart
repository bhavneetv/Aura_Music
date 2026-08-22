import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../sharing/playlist_link_share_service.dart';
import '../storage/storage_service.dart';
import 'voice_search_service.dart';

class VoiceAssistantService {
  static final VoiceAssistantService instance = VoiceAssistantService._internal();
  VoiceAssistantService._internal();

  static const MethodChannel _channel = MethodChannel('com.example.music_app/voice_assistant');
  ProviderContainer? _container;

  /// Initializes the voice assistant service with Riverpod container context.
  Future<void> init(ProviderContainer container) async {
    _container = container;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onVoiceQuery':
          final String? query = call.arguments is Map ? call.arguments['query']?.toString() : call.arguments?.toString();
          if (query != null) {
            return await handleVoiceQuery(query);
          }
          return false;

        case 'onDeepLink':
          final String? link = call.arguments is Map ? call.arguments['link']?.toString() : call.arguments?.toString();
          if (link != null && link.isNotEmpty) {
            await _handleIncomingDeepLink(link);
            return true;
          }
          return false;

        case 'getLibraryIndex':
          return getLibraryIndexJson();

        default:
          throw MissingPluginException('Not implemented: ${call.method}');
      }
    });

    // Initial sync of local library index to platform (App Group container for iOS SiriKit)
    await syncLibraryIndexToPlatform();
  }

  Future<void> _handleIncomingDeepLink(String link) async {
    try {
      final decoded = await PlaylistLinkShareService.instance.decodeShareableLinkAsync(link);
      if (decoded != null && decoded.tracks.isNotEmpty) {
        final newPl = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': decoded.title,
          'description': decoded.description.isNotEmpty ? decoded.description : 'Imported via Link',
          'trackIds': decoded.tracks.map((t) => t.id).toList(),
          'tracks': decoded.tracks.map((t) => {
            'id': t.id,
            'title': t.title,
            'artist': t.artist,
            'album': t.album,
            'duration': t.duration,
            'artworkUrl': t.artworkUrl,
            'audioUrl': t.audioUrl,
            'genre': t.genre,
          }).toList(),
        };
        final playlists = StorageService.getPlaylists();
        playlists.insert(0, newPl);
        await StorageService.savePlaylists(playlists);
        debugPrint('[DeepLink] Automatically imported playlist: ${decoded.title}');
      }
    } catch (e) {
      debugPrint('[DeepLink] Error handling incoming deep link: $e');
    }
  }

  /// Processes incoming voice query from native platform (Siri / Google Assistant).
  Future<Map<String, dynamic>> handleVoiceQuery(String rawQuery) async {
    final result = VoiceSearchService.instance.resolveVoiceQuery(rawQuery);
    
    if (_container != null) {
      final notifier = _container!.read(playbackProvider.notifier);
      switch (result.type) {
        case VoiceSearchResultType.resume:
          if (result.queue.isNotEmpty) {
            notifier.playCustomQueue(result.queue, initialIndex: 0);
          } else {
            final curr = _container!.read(playbackProvider).currentTrack;
            if (curr != null) notifier.playTrack(curr);
          }
          break;

        case VoiceSearchResultType.track:
          if (result.matchedTrack != null) {
            notifier.playTrack(result.matchedTrack!);
          }
          break;

        case VoiceSearchResultType.playlist:
        case VoiceSearchResultType.artist:
          if (result.queue.isNotEmpty) {
            notifier.playCustomQueue(result.queue, initialIndex: 0);
          }
          break;

        case VoiceSearchResultType.noMatch:
          // Handled gracefully below
          break;
      }
    }

    return {
      'success': result.isSuccess,
      'type': result.type.name,
      'query': rawQuery,
      'matchedName': result.matchedTrack?.title ?? result.playlistName ?? result.artistName ?? '',
      'message': result.message ?? '',
    };
  }

  /// Generates JSON index of local songs, playlists, and artists for offline Siri resolution.
  String getLibraryIndexJson() {
    final tracks = VoiceSearchService.instance.getLocalLibraryTracks();
    final items = tracks.map((t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'genre': t.genre,
      'artworkUrl': t.artworkUrl,
      'audioUrl': t.audioUrl,
      'type': 'song',
    }).toList();

    return jsonEncode({
      'updatedAt': DateTime.now().toIso8601String(),
      'items': items,
    });
  }

  /// Exports library index to platform native layer (iOS App Group shared container).
  Future<void> syncLibraryIndexToPlatform() async {
    try {
      final jsonStr = getLibraryIndexJson();
      await _channel.invokeMethod('syncLibraryIndex', {'json': jsonStr});
    } catch (e) {
      debugPrint('[VOICE-ASSISTANT] Failed to sync library index to platform: $e');
    }
  }

  /// Donates media activity (NSUserActivity / INPlayMediaIntent) to iOS Siri system.
  Future<void> donateTrack(Track track) async {
    try {
      await _channel.invokeMethod('donateMediaItem', {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'artworkUrl': track.artworkUrl,
        'genre': track.genre,
      });
    } catch (e) {
      debugPrint('[VOICE-ASSISTANT] Failed to donate media item: $e');
    }
  }
}
