import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../services/playlist/playlist_repository.dart';
import 'auth_provider.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository();
});

/// Streams all playlists that the current user owns or is a member of.
final userPlaylistsStreamProvider = StreamProvider<List<Playlist>>((ref) {
  final authUserAsync = ref.watch(authStateStreamProvider);
  final user = authUserAsync.value;
  if (user == null) {
    return Stream.value([]);
  }
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.watchUserPlaylists(user.uid);
});

/// Streams a single active playlist by id in real-time.
final activePlaylistStreamProvider = StreamProvider.family<Playlist?, String>((ref, playlistId) {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.watchPlaylist(playlistId);
});

/// Provides the current user's favorites / liked songs playlist.
final favoritesPlaylistProvider = FutureProvider<Playlist?>((ref) async {
  final authUserAsync = ref.watch(authStateStreamProvider);
  final user = authUserAsync.value;
  if (user == null) return null;

  final appUser = ref.watch(currentAppUserStreamProvider).value;
  final userName = appUser?.displayName ?? user.displayName ?? 'Aura Listener';
  
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.getOrCreateFavorites(user.uid, userName);
});
