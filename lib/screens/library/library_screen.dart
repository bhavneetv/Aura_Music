import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../services/import/spotify_import_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/app_artwork_image.dart';
import 'playlist_detail_screen.dart';
import 'recently_played_screen.dart';
import 'spotify_import_preview_screen.dart';
import 'package:flutter/services.dart';
import '../../services/sharing/playlist_link_share_service.dart';
import '../sharing/remote_link_share_modal.dart';
import '../../widgets/playlist_imported_dialog.dart';
import 'explore_playlists_screen.dart';
import '../../services/playlist/playlist_repository.dart';
import '../../services/sync/playlist_cloud_sync_service.dart';
import '../../services/auth/auth_service.dart';
import '../../widgets/auth_dialog.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _playlists = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPlaylists();
    AuthService.instance.playlistsChangedNotifier.addListener(_loadPlaylists);
    PlaylistLinkShareService.importEventNotifier.addListener(_loadPlaylists);
  }

  @override
  void dispose() {
    AuthService.instance.playlistsChangedNotifier.removeListener(_loadPlaylists);
    PlaylistLinkShareService.importEventNotifier.removeListener(_loadPlaylists);
    _tabController.dispose();
    super.dispose();
  }

  void _loadPlaylists() {
    setState(() {
      _playlists = StorageService.getPlaylists();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADD / IMPORT PLAYLIST SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAddPlaylistModal({int initialTab = 0}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => _AddPlaylistBottomSheet(
        initialTab: initialTab,
        onPlaylistsChanged: _loadPlaylists,
      ),
    );
  }

  /// Opens the share options for a playlist (original logic, unchanged).
  void _sharePlaylist(Map<String, dynamic> playlist) {
    final List rawTracks = playlist['tracks'] ?? [];
    final List<Track> playlistTracks = [];
    if (rawTracks.isNotEmpty) {
      for (final item in rawTracks) {
        if (item is Map) {
          playlistTracks.add(Track(
            id: item['id']?.toString() ?? '',
            title: item['title']?.toString() ?? 'Track',
            artist: item['artist']?.toString() ?? 'Unknown Artist',
            album: item['album']?.toString() ?? 'Album',
            duration: item['duration']?.toString() ?? '3:30',
            artworkUrl: item['artworkUrl']?.toString() ?? '',
            audioUrl: item['audioUrl']?.toString() ?? '',
            genre: item['genre']?.toString() ?? '',
          ));
        }
      }
    }
    ShareOptionsModal.show(
      context,
      tracks: playlistTracks,
      title: playlist['name']?.toString() ?? 'Custom Playlist',
      description: playlist['description']?.toString() ?? '',
    );
  }

  void _openPlaylist(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaylistDetailScreen(
          playlistIndex: index,
          initialPlaylist: _playlists[index],
        ),
      ),
    ).then((_) => _loadPlaylists());
  }

  void _openExplore() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExplorePlaylistsScreen()),
    ).then((_) => _loadPlaylists());
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecentlyPlayedScreen()),
    ).then((_) => _loadPlaylists());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN
  //
  //   Phones   header · shortcut rail · tabs · list
  //   Wide     header + shortcuts in a side panel, tabs and list beside it
  //
  // Lists go from one card per row to two or three as the screen widens, and
  // the album grid adds columns the same way.
  // ═══════════════════════════════════════════════════════════════════════════

  /// From this width up, the header and shortcuts move into a side panel.
  static const double _wideBreakpoint = 840;

  /// Content never grows wider than this; extra space becomes side margins.
  static const double _maxContentWidth = 1160;

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(customizationProvider).accentColor;

    final favTracks = StorageService.getFavoriteTracks();
    final downloadedTracks = DownloadService.instance.getDownloadedTracksList();
    final historyList = StorageService.getListeningHistory();

    final shortcuts = [
      _Shortcut('History', '${historyList.length} played', Icons.history_rounded, _openHistory),
      _Shortcut('Global', 'Community', Icons.public_rounded, _openExplore),
      _Shortcut('Favorites', _countLabel(favTracks.length, 'song'), Icons.favorite_rounded, () {
        _tabController.animateTo(1);
      }),
      _Shortcut('Offline', '${downloadedTracks.length} saved', Icons.download_done_rounded, () {
        _tabController.animateTo(3);
      }),
    ];

    final subtitle = '${_countLabel(_playlists.length, 'playlist')} · ${favTracks.length} liked · '
        '${downloadedTracks.length} offline';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        final side = math.max(20.0, (constraints.maxWidth - _maxContentWidth) / 2);
        final topInset = MediaQuery.of(context).padding.top + 14;

        Widget tabViews(EdgeInsets listPadding) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildPlaylistsTab(accentColor, listPadding),
              _buildLikedSongsTab(favTracks, accentColor, listPadding),
              _buildAlbumsTab(favTracks, accentColor, listPadding),
              _buildDownloadedTab(downloadedTracks, accentColor, listPadding),
            ],
          );
        }

        if (isWide) {
          return Padding(
            padding: EdgeInsets.only(left: side, top: topInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Side panel
                SizedBox(
                  width: 300,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context, accentColor, subtitle, stacked: true),
                        const SizedBox(height: 20),
                        for (final shortcut in shortcuts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ShortcutCard(shortcut: shortcut, accent: accentColor),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                // Tabs + content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: side),
                        child: _buildTabBar(accentColor),
                      ),
                      Expanded(child: tabViews(EdgeInsets.only(right: side))),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(side, topInset, side, 0),
              child: _buildHeader(context, accentColor, subtitle, stacked: false),
            ),
            const SizedBox(height: 16),
            // Shortcut rail
            SizedBox(
              height: math.max(58.0, 22 + 36 * textScale),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: side),
                itemCount: shortcuts.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 158,
                    child: _ShortcutCard(shortcut: shortcuts[index], accent: accentColor),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: _buildTabBar(accentColor),
            ),
            Expanded(child: tabViews(EdgeInsets.symmetric(horizontal: side))),
          ],
        );
      },
    );
  }

  String _countLabel(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

  /// Cards per row for a list that is [width] wide.
  int _columnsFor(double width) {
    if (width >= 980) return 3;
    if (width >= 620) return 2;
    return 1;
  }

  Widget _buildHeader(BuildContext context, Color accentColor, String subtitle, {required bool stacked}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoggedIn = AuthService.instance.isLoggedIn;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Library',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.1,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: stacked ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: _muted(context)),
        ),
      ],
    );

    final actions = _ActionCapsule(
      actions: [
        _CapsuleAction(
          icon: Icons.add_rounded,
          tooltip: 'New Playlist',
          onPressed: () => _showAddPlaylistModal(initialTab: 1),
        ),
        _CapsuleAction(
          icon: Icons.download_rounded,
          tooltip: 'Import Playlist',
          onPressed: () => _showAddPlaylistModal(initialTab: 0),
        ),
        _CapsuleAction(
          icon: isLoggedIn ? Icons.cloud_done_rounded : Icons.account_circle_outlined,
          tooltip: isLoggedIn ? 'Cloud Account Active' : 'Sign In / Account',
          highlightColor: isLoggedIn ? accentColor : null,
          onPressed: () async {
            await AuthModalDialog.show(context, onLoggedIn: () {
              if (mounted) _loadPlaylists();
            });
            if (mounted) _loadPlaylists();
          },
        ),
      ],
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 16), actions],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 12),
        actions,
      ],
    );
  }

  Widget _buildTabBar(Color accentColor) {
    Widget tab(String label) {
      // Shrinks the label instead of clipping it on narrow phones.
      return Tab(
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      );
    }

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _tint(context, 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.32),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        labelColor: _onColor(accentColor),
        unselectedLabelColor: _muted(context),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
        dividerColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        tabs: [tab('Playlists'), tab('Liked'), tab('Albums'), tab('Downloads')],
      ),
    );
  }

  // ── Playlists ──────────────────────────────────────────────────────────────

  Widget _buildPlaylistsTab(Color accentColor, EdgeInsets listPadding) {
    if (_playlists.isEmpty) {
      return _EmptyState(
        padding: listPadding,
        icon: Icons.playlist_add_rounded,
        accent: accentColor,
        title: 'No playlists yet',
        message: 'Create one, import it from a link or Spotify, or browse what others have shared.',
        actions: [
          FilledButton.icon(
            onPressed: () => _showAddPlaylistModal(initialTab: 0),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add or import playlist'),
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: _onColor(accentColor),
              minimumSize: const Size(0, 48),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _openExplore,
            icon: const Icon(Icons.public_rounded, size: 19),
            label: const Text('Explore global playlists'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(color: _tint(context, 0.18)),
              minimumSize: const Size(0, 48),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth - listPadding.horizontal);
        final rows = (_playlists.length / columns).ceil();

        return ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: listPadding.copyWith(top: 14, bottom: 150),
          itemCount: rows + 1,
          itemBuilder: (context, row) {
            if (row == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DiscoverBanner(accent: accentColor, onTap: _openExplore),
              );
            }
            return _cardRow(
              columns: columns,
              first: (row - 1) * columns,
              itemCount: _playlists.length,
              // In a grid, keep every card the same height.
              itemBuilder: (index) => _buildPlaylistCard(index, accentColor, uniformHeight: columns > 1),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistCard(int index, Color accentColor, {required bool uniformHeight}) {
    final playlist = _playlists[index];
    final List rawTracks = playlist['tracks'] as List? ?? [];
    final List trackIds = playlist['trackIds'] as List? ?? [];
    final int songCount = rawTracks.isNotEmpty ? rawTracks.length : trackIds.length;
    final author = playlist['authorName']?.toString();
    final isPublic = playlist['isPublic'] == true;
    final isSync = playlist['isSyncEnabled'] == true;
    final isImported = playlist['isImported'] == true;
    final shareCode = playlist['shareCode']?.toString() ?? '';

    // Cover: artwork of the first song, when the playlist has one.
    String coverUrl = '';
    String coverId = '';
    if (rawTracks.isNotEmpty && rawTracks.first is Map) {
      final first = rawTracks.first as Map;
      coverUrl = first['artworkUrl']?.toString() ?? '';
      coverId = first['id']?.toString() ?? '';
    }

    final meta = author != null && author.isNotEmpty
        ? '${_countLabel(songCount, 'song')} · By $author'
        : '${_countLabel(songCount, 'song')} · ${playlist['description'] ?? 'Custom playlist'}';

    final hasBadges = shareCode.isNotEmpty || isImported;

    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: InkWell(
        onTap: () => _openPlaylist(index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              coverUrl.isNotEmpty
                  ? AppArtworkImage(
                      artworkUrl: coverUrl,
                      trackId: coverId,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(16),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accentColor.withValues(alpha: 0.34),
                            accentColor.withValues(alpha: 0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.queue_music_rounded, color: accentColor, size: 28),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            playlist['name']?.toString() ?? 'Playlist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                          ),
                        ),
                        if (isPublic) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.public_rounded, size: 14, color: _muted(context), semanticLabel: 'Public'),
                        ],
                        if (isSync) ...[
                          const SizedBox(width: 5),
                          Icon(Icons.sync_rounded, size: 14, color: _muted(context), semanticLabel: 'Sync on'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: _muted(context)),
                    ),
                    if (hasBadges || uniformHeight) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 20,
                        child: Row(
                          children: [
                            if (shareCode.isNotEmpty)
                              _Pill(icon: Icons.tag_rounded, label: shareCode, color: accentColor),
                            if (shareCode.isNotEmpty && isImported) const SizedBox(width: 6),
                            if (isImported) const _Pill(icon: Icons.download_done_rounded, label: 'Imported'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Share Playlist',
                icon: Icon(Icons.share_rounded, size: 20, color: _tint(context, 0.6)),
                onPressed: () => _sharePlaylist(playlist),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: _tint(context, 0.3)),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Liked songs ────────────────────────────────────────────────────────────

  Widget _buildLikedSongsTab(List<Track> tracks, Color accentColor, EdgeInsets listPadding) {
    if (tracks.isEmpty) {
      return _EmptyState(
        padding: listPadding,
        icon: Icons.favorite_border_rounded,
        accent: accentColor,
        title: 'No liked songs yet',
        message: 'Tap the heart on any song that is playing to keep it here.',
      );
    }

    final notifier = ref.read(playbackProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth - listPadding.horizontal);
        final rows = (tracks.length / columns).ceil();

        return ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: listPadding.copyWith(top: 14, bottom: 150),
          itemCount: rows + 1,
          itemBuilder: (context, row) {
            if (row == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PlayBar(
                  accent: accentColor,
                  onPlay: () => notifier.playCustomQueue(tracks, initialIndex: 0),
                  onShuffle: () => notifier.playCustomQueue(List<Track>.from(tracks)..shuffle(), initialIndex: 0),
                ),
              );
            }
            return _cardRow(
              columns: columns,
              first: (row - 1) * columns,
              itemCount: tracks.length,
              itemBuilder: (index) {
                final track = tracks[index];
                final isFav = StorageService.isFavorite('trackIds', track.id);

                return _TrackCard(
                  artwork: _artwork(track, 52),
                  title: track.title,
                  subtitle: '${track.artist} • ${track.album}',
                  onTap: () => notifier.playTrack(track),
                  trailing: [
                    IconButton(
                      tooltip: isFav ? 'Remove from liked songs' : 'Like',
                      icon: Icon(
                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFav ? Colors.redAccent : _tint(context, 0.45),
                        size: 21,
                      ),
                      onPressed: () async {
                        await StorageService.toggleFavoriteTrack(track);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _artwork(Track track, double size) {
    return AppArtworkImage(
      artworkUrl: track.artworkUrl,
      trackId: track.id,
      width: size,
      height: size,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(size * 0.26),
    );
  }

  // ── Albums ─────────────────────────────────────────────────────────────────

  Widget _buildAlbumsTab(List<Track> tracks, Color accentColor, EdgeInsets listPadding) {
    final Map<String, List<Track>> albumsMap = {};
    for (final track in tracks) {
      final albumName = track.album.trim().isNotEmpty ? track.album.trim() : 'Singles';
      albumsMap.putIfAbsent(albumName, () => []).add(track);
    }

    if (albumsMap.isEmpty) {
      return _EmptyState(
        padding: listPadding,
        icon: Icons.album_rounded,
        accent: accentColor,
        title: 'No albums yet',
        message: 'Albums are built from your liked songs.',
      );
    }

    final albumNames = albumsMap.keys.toList();
    final notifier = ref.read(playbackProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final width = constraints.maxWidth - listPadding.horizontal;
        // As many columns as fit at about 170px each: 2 on phones, more on tablets.
        final columns = (width / 170).floor().clamp(2, 6).toInt();
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;

        return GridView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: listPadding.copyWith(top: 16, bottom: 150),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 18,
            // Square artwork plus two lines of text at the current font size.
            mainAxisExtent: tileWidth + 10 + 40 * textScale,
          ),
          itemCount: albumNames.length,
          itemBuilder: (context, index) {
            final albumName = albumNames[index];
            final albumTracks = albumsMap[albumName]!;
            final firstTrack = albumTracks.first;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => notifier.playCustomQueue(albumTracks, initialIndex: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      AppArtworkImage(
                        artworkUrl: firstTrack.artworkUrl,
                        trackId: firstTrack.id,
                        width: tileWidth,
                        height: tileWidth,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
                          ),
                          child: Icon(Icons.play_arrow_rounded, color: _onColor(accentColor), size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    albumName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${firstTrack.artist} · ${_countLabel(albumTracks.length, 'song')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: _muted(context)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Downloads ──────────────────────────────────────────────────────────────

  Widget _buildDownloadedTab(List<Track> downloadedTracks, Color accentColor, EdgeInsets listPadding) {
    final downloadedPlaylists = StorageService.getDownloadedPlaylists();

    if (downloadedTracks.isEmpty && downloadedPlaylists.isEmpty) {
      return _EmptyState(
        padding: listPadding,
        icon: Icons.download_done_rounded,
        accent: accentColor,
        title: 'No downloads yet',
        message: 'Download songs to listen offline any time.',
      );
    }

    final notifier = ref.read(playbackProvider.notifier);

    Widget deleteButton(String tooltip, Future<void> Function() onDelete) {
      return IconButton(
        tooltip: tooltip,
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 21),
        onPressed: () async {
          await onDelete();
          if (mounted) setState(() {});
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth - listPadding.horizontal);

        return ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: listPadding.copyWith(top: 6, bottom: 150),
          children: [
            if (downloadedPlaylists.isNotEmpty) ...[
              _SectionLabel(label: 'Playlists', trailing: '${downloadedPlaylists.length}'),
              for (var first = 0; first < downloadedPlaylists.length; first += columns)
                _cardRow(
                  columns: columns,
                  first: first,
                  itemCount: downloadedPlaylists.length,
                  itemBuilder: (index) {
                    final pl = downloadedPlaylists[index];
                    final List rawTracks = pl['tracks'] ?? [];

                    return _TrackCard(
                      artwork: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.download_done_rounded, color: accentColor, size: 25),
                      ),
                      title: pl['name']?.toString() ?? 'Playlist',
                      subtitle: '${_countLabel(rawTracks.length, 'song')} saved offline',
                      trailing: [
                        deleteButton('Delete download', () async {
                          await StorageService.deleteDownloadedPlaylist(pl['name']);
                        }),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
            if (downloadedTracks.isNotEmpty) ...[
              _SectionLabel(label: 'Songs', trailing: '${downloadedTracks.length}'),
              for (var first = 0; first < downloadedTracks.length; first += columns)
                _cardRow(
                  columns: columns,
                  first: first,
                  itemCount: downloadedTracks.length,
                  itemBuilder: (index) {
                    final track = downloadedTracks[index];

                    return _TrackCard(
                      artwork: _artwork(track, 52),
                      title: track.title,
                      subtitle: track.artist,
                      onTap: () => notifier.playTrack(track),
                      trailing: [
                        deleteButton('Delete download', () async {
                          await DownloadService.instance.deleteDownload(track.id);
                        }),
                      ],
                    );
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════════

/// White in dark mode, black in light mode, at the given opacity.
Color _tint(BuildContext context, double alpha) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

Color _muted(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
}

/// Readable text/icon color on top of [background] (any accent the user picks).
Color _onColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

/// One row of up to [columns] cards, starting at item [first]. No fixed
/// heights, so cards grow with the system font size.
Widget _cardRow({
  required int columns,
  required int first,
  required int itemCount,
  required Widget Function(int index) itemBuilder,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: columns == 1
        ? itemBuilder(first)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 10),
                Expanded(
                  child: first + column < itemCount ? itemBuilder(first + column) : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

class _Shortcut {
  const _Shortcut(this.title, this.subtitle, this.icon, this.onTap);

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.shortcut, required this.accent});

  final _Shortcut shortcut;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tint(context, 0.055),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _tint(context, 0.07)),
      ),
      child: InkWell(
        onTap: shortcut.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(shortcut.icon, size: 20, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortcut.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shortcut.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, height: 1.2, color: _muted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapsuleAction {
  const _CapsuleAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlightColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Draws the icon in this color instead of the normal one.
  final Color? highlightColor;
}

/// A row of icon buttons inside one rounded capsule, split by hairlines.
class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({required this.actions});

  final List<_CapsuleAction> actions;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: _tint(context, 0.07),
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(side: BorderSide(color: _tint(context, 0.08))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Container(width: 1, height: 18, color: _tint(context, 0.12)),
            Tooltip(
              message: actions[i].tooltip,
              child: InkWell(
                onTap: actions[i].onPressed,
                child: SizedBox(
                  width: 46,
                  height: 44,
                  child: Icon(
                    actions[i].icon,
                    size: 21,
                    color: actions[i].highlightColor ?? onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small rounded label, used for the share code and the "Imported" mark.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;

  /// Accent for the pill; neutral grey when left out.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? _muted(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color != null ? color!.withValues(alpha: 0.14) : _tint(context, 0.07),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1, color: foreground),
          ),
        ],
      ),
    );
  }
}

class _DiscoverBanner extends StatelessWidget {
  const _DiscoverBanner({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: 0.28)),
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.26), accent.withValues(alpha: 0.05)],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(Icons.public_rounded, color: _onColor(accent), size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Discover global playlists',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Browse public playlists from the community',
                        style: TextStyle(fontSize: 12.5, color: _muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 20, color: _tint(context, 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Play all / Shuffle, shown above a list of songs.
class _PlayBar extends StatelessWidget {
  const _PlayBar({required this.accent, required this.onPlay, required this.onShuffle});

  final Color accent;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        // Full width on phones, a sensible size on tablets.
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text('Play all'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: _onColor(accent),
                  minimumSize: const Size(0, 48),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded, size: 20),
                label: const Text('Shuffle'),
                style: FilledButton.styleFrom(
                  backgroundColor: _tint(context, 0.09),
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size(0, 48),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A song (or downloaded playlist) as a card: picture, two lines, buttons.
class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.artwork,
    required this.title,
    required this.subtitle,
    this.trailing = const [],
    this.onTap,
  });

  final Widget artwork;
  final String title;
  final String subtitle;
  final List<Widget> trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              artwork,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: _muted(context)),
                    ),
                  ],
                ),
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w800),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _tint(context, 0.08),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                trailing!,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted(context)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Centered message for an empty tab. Scrolls, so it never overflows on
/// short screens or in landscape.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.padding,
    required this.icon,
    required this.accent,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final EdgeInsets padding;
  final IconData icon;
  final Color accent;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: padding.copyWith(top: 24, bottom: 150),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0.0, constraints.maxHeight - 174)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: Icon(icon, size: 36, color: accent),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Outfit', fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, height: 1.45, color: _muted(context)),
                    ),
                    for (var i = 0; i < actions.length; i++) ...[
                      SizedBox(height: i == 0 ? 20 : 10),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A switch with a title and explanation, as one card.
class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? accent.withValues(alpha: 0.10) : _tint(context, 0.04),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: value ? accent.withValues(alpha: 0.45) : _tint(context, 0.07)),
      ),
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 21, color: value ? accent : _muted(context)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.35, color: _muted(context))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: accent,
                thumbColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => states.contains(WidgetState.selected) ? _onColor(accent) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control whose highlight pill slides between the options.
class _SlidingSelector extends StatelessWidget {
  const _SlidingSelector({
    required this.labels,
    required this.icons,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = _onColor(accent);
    final last = labels.length - 1;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _tint(context, 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment(last == 0 ? 0 : -1 + 2 * selected / last, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icons[i], size: 17, color: i == selected ? on : _muted(context)),
                              const SizedBox(width: 6),
                              Text(
                                labels[i],
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontFamily: 'Outfit',
                                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                                  color: i == selected ? on : _muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ADD / IMPORT PLAYLIST SHEET WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class _AddPlaylistBottomSheet extends ConsumerStatefulWidget {
  final int initialTab;
  final VoidCallback onPlaylistsChanged;

  const _AddPlaylistBottomSheet({
    required this.initialTab,
    required this.onPlaylistsChanged,
  });

  @override
  ConsumerState<_AddPlaylistBottomSheet> createState() => _AddPlaylistBottomSheetState();
}

class _AddPlaylistBottomSheetState extends ConsumerState<_AddPlaylistBottomSheet> {
  late int _selectedTab;
  String? _inlineError;
  String? _titleError;
  bool _isLoading = false;
  bool _newPlaylistIsPublic = false;
  bool _newPlaylistIsSyncEnabled = true;

  late final TextEditingController _spotifyUrlController;
  late final TextEditingController _playlistNameController;
  late final TextEditingController _playlistDescController;
  late final TextEditingController _authorController;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _spotifyUrlController = TextEditingController();
    _playlistNameController = TextEditingController();
    _playlistDescController = TextEditingController();
    final accountName = AuthService.instance.currentUserName.isNotEmpty
        ? AuthService.instance.currentUserName
        : StorageService.getUserAuthorName();
    _authorController = TextEditingController(text: accountName);
  }

  @override
  void dispose() {
    _spotifyUrlController.dispose();
    _playlistNameController.dispose();
    _playlistDescController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _runImport(Color accentColor) async {
    final input = _spotifyUrlController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _inlineError = 'Please enter a playlist code or paste a link.';
        _selectedTab = 0;
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _inlineError = null;
      _selectedTab = 0; // Strictly stays on Import tab!
    });

    try {
      // 0. Attempt Firestore Collaborative Invite Code join
      if (AuthService.instance.isLoggedIn) {
        try {
          final repo = PlaylistRepository();
          final joinedPl = await repo.joinByInviteCode(
            input,
            AuthService.instance.currentUserId,
            AuthService.instance.currentUserName,
          );
          await AuthService.instance.restoreUserPlaylists();
          if (mounted) {
            Navigator.pop(context);
            widget.onPlaylistsChanged();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF2E7D32),
                content: Text('Joined collaborative playlist "${joinedPl.name}"! 🎵'),
              ),
            );
          }
          return;
        } catch (e) {
          // If code wasn't a valid invite code, fallback to legacy/links below
        }
      }

      // 1. Attempt Cloud Share Code lookup (e.g. AURA-7K9X2B or bare code)
      final cloudByCode = await PlaylistCloudSyncService.instance.fetchPlaylistByShareCode(input);
      if (cloudByCode != null) {
        final List<Track> tracks = List<Track>.from(cloudByCode['tracks'] as List? ?? []);
        final currentUserId = AuthService.instance.currentUserId;
        final currentUserEmail = (AuthService.instance.currentUserEmail ?? '').trim().toLowerCase();
        final currentUserName = AuthService.instance.currentUserName.trim().toLowerCase();

        final codeOwnerId = cloudByCode['ownerId']?.toString() ?? '';
        final codeOwnerEmail = (cloudByCode['ownerEmail']?.toString() ?? '').trim().toLowerCase();
        final codeAuthor = (cloudByCode['authorName']?.toString() ?? '').trim().toLowerCase();

        final isMyOwnPlaylist = AuthService.instance.isLoggedIn && (
          (codeOwnerId.isNotEmpty && codeOwnerId == currentUserId) ||
          (codeOwnerEmail.isNotEmpty && codeOwnerEmail == currentUserEmail) ||
          (codeAuthor.isNotEmpty && codeAuthor == currentUserName && (codeOwnerId.isEmpty || codeOwnerId == currentUserId))
        );

        final newPl = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': cloudByCode['name']?.toString() ?? 'Shared Playlist',
          'description': cloudByCode['description']?.toString() ?? 'Imported via Playlist Code',
          'authorName': cloudByCode['authorName']?.toString() ?? 'Community Member',
          'ownerId': isMyOwnPlaylist ? currentUserId : codeOwnerId,
          'ownerEmail': isMyOwnPlaylist ? (AuthService.instance.currentUserEmail ?? codeOwnerEmail) : codeOwnerEmail,
          'ownerName': cloudByCode['authorName']?.toString() ?? '',
          'isImported': !isMyOwnPlaylist,
          'isPublic': cloudByCode['isPublic'] == true,
          'isSyncEnabled': cloudByCode['isSyncEnabled'] == true,
          'shareCode': cloudByCode['shareCode']?.toString() ?? input.toUpperCase(),
          'syncId': cloudByCode['syncId']?.toString(),
          'trackIds': tracks.map((t) => t.id).toList(),
          'syncedTrackIds': tracks.map((t) => t.id).toList(),
          'tracks': tracks.map((t) => t.toJson()).toList(),
        };
        final playlists = StorageService.getPlaylists();
        playlists.insert(0, newPl);
        await StorageService.savePlaylists(playlists);

        final importEvent = PlaylistImportEvent(
          title: newPl['name'].toString(),
          description: newPl['description'].toString(),
          trackCount: tracks.length,
          tracks: tracks,
          fromQrScan: false,
        );

        if (!mounted) return;
        final navigator = Navigator.of(context);
        navigator.pop();
        widget.onPlaylistsChanged();

        final rootContext = navigator.context;
        if (rootContext.mounted) {
          PlaylistImportSuccessDialog.show(rootContext, importEvent, ref);
        }
        return;
      }

      // 2. Attempt Aura Link or code decode
      final decodedAura = await PlaylistLinkShareService.instance.decodeShareableLinkAsync(input);
      if (decodedAura != null && decodedAura.tracks.isNotEmpty) {
        final newPl = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': decodedAura.title,
          'description': decodedAura.description.isNotEmpty
              ? decodedAura.description
              : 'Imported via Shared Code / Link',
          'trackIds': decodedAura.tracks.map((t) => t.id).toList(),
          'tracks': decodedAura.tracks.map((t) => t.toJson()).toList(),
        };
        final playlists = StorageService.getPlaylists();
        playlists.insert(0, newPl);
        await StorageService.savePlaylists(playlists);

        final importEvent = PlaylistImportEvent(
          title: decodedAura.title,
          description: decodedAura.description,
          trackCount: decodedAura.tracks.length,
          tracks: decodedAura.tracks,
          fromQrScan: false,
        );

        if (!mounted) return;
        final navigator = Navigator.of(context);
        navigator.pop();
        widget.onPlaylistsChanged();

        final rootContext = navigator.context;
        if (rootContext.mounted) {
          PlaylistImportSuccessDialog.show(rootContext, importEvent, ref);
        }
        return;
      }

      // 3. Attempt Spotify URL import
      final playlistId = SpotifyImportService.instance.validateAndExtractPlaylistId(input);
      if (playlistId != null) {
        final preview = await SpotifyImportService.instance.fetchPlaylistPreview(input);
        if (!mounted) return;
        final navigator = Navigator.of(context);
        navigator.pop();
        final rootContext = navigator.context;
        if (rootContext.mounted) {
          Navigator.push(
            rootContext,
            MaterialPageRoute(
              builder: (context) => SpotifyImportPreviewScreen(preview: preview),
            ),
          ).then((_) => widget.onPlaylistsChanged());
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _inlineError = 'Could not find or decode playlist. Please check your code or link.';
          _selectedTab = 0; // Strictly stays on Import tab!
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _inlineError = 'Failed to load playlist: $e';
          _selectedTab = 0; // Strictly stays on Import tab!
        });
      }
    }
  }

  Future<void> _runCreate(Color accentColor) async {
    final name = _playlistNameController.text.trim();
    final desc = _playlistDescController.text.trim();
    final author = _authorController.text.trim().isEmpty ? StorageService.getUserAuthorName() : _authorController.text.trim();

    if (name.isNotEmpty) {
      setState(() => _isLoading = true);
      await StorageService.setUserAuthorName(author);

      String plId = DateTime.now().millisecondsSinceEpoch.toString();
      String shareCode = '';
      final ownerId = AuthService.instance.currentUserId;
      final ownerEmail = AuthService.instance.currentUserEmail ?? '';
      String? syncId;

      // Create in Cloud Firestore (for Explore screen and Collaboration)
      if (AuthService.instance.isLoggedIn) {
        try {
          final repo = PlaylistRepository();
          final firestorePlaylist = await repo.createPlaylist(
            id: plId,
            name: name,
            description: desc,
            ownerUid: ownerId,
            ownerName: author,
            visibility: _newPlaylistIsPublic ? 'public' : 'private',
            collabEnabled: _newPlaylistIsSyncEnabled,
          );
          plId = firestorePlaylist.id;
          if (_newPlaylistIsSyncEnabled) {
            try {
              shareCode = firestorePlaylist.shareCode ?? await repo.enableCollaboration(plId, ownerId);
            } catch (ce) {
              debugPrint('Collaboration code notice: $ce');
            }
          }
        } catch (e) {
          debugPrint('Firestore playlist create error: $e');
        }
      }

      if (_newPlaylistIsPublic || _newPlaylistIsSyncEnabled) {
        try {
          syncId = await PlaylistCloudSyncService.instance.createCloudSyncSlot(
            localId: plId,
            name: name,
            description: desc,
            authorName: author,
            isPublic: _newPlaylistIsPublic,
            isSyncEnabled: _newPlaylistIsSyncEnabled,
            tracks: [],
            shareCode: shareCode,
            ownerId: ownerId,
            ownerEmail: ownerEmail,
          );
        } catch (dioE) {
          debugPrint('Legacy createCloudSyncSlot notice (safe): $dioE');
        }
      }

      final playlists = StorageService.getPlaylists();
      final newPl = {
        'id': plId,
        'name': name,
        'description': desc.isNotEmpty ? desc : 'A custom playlist',
        'authorName': author,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'ownerName': author,
        'isImported': false,
        'isPublic': _newPlaylistIsPublic,
        'isSyncEnabled': _newPlaylistIsSyncEnabled,
        'shareCode': shareCode,
        if (syncId != null) 'syncId': syncId,
        'trackIds': <String>[],
        'tracks': <Map<String, dynamic>>[],
      };
      playlists.add(newPl);
      await StorageService.savePlaylists(playlists);

      widget.onPlaylistsChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created playlist "$name"! 🎉'),
            backgroundColor: accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(customizationProvider).accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    InputDecoration fieldDecoration({
      String? labelText,
      String? hintText,
      String? errorText,
      String? helperText,
      Widget? prefixIcon,
      Widget? suffixIcon,
    }) {
      OutlineInputBorder outline(Color color, [double width = 1]) {
        return OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
      }

      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 13, color: _tint(context, 0.38)),
        errorText: errorText,
        errorMaxLines: 3,
        helperText: helperText,
        helperStyle: TextStyle(fontSize: 11.5, color: _muted(context)),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _tint(context, 0.05),
        border: outline(Colors.transparent),
        enabledBorder: outline(_tint(context, 0.08)),
        disabledBorder: outline(_tint(context, 0.05)),
        focusedBorder: outline(accentColor, 1.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
    }

    Widget submitButton(String label, VoidCallback onPressed) {
      final onAccent = _onColor(accentColor);
      return SizedBox(
        height: 54,
        child: FilledButton(
          onPressed: _isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: onAccent,
            disabledBackgroundColor: accentColor.withValues(alpha: 0.65),
            disabledForegroundColor: onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
          ),
          child: _isLoading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(onAccent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedTab == 0 ? 'Importing playlist...' : 'Creating playlist...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: onAccent,
                      ),
                    ),
                  ],
                )
              : Text(label),
        ),
      );
    }

    final List<Widget> tabContent;
    if (_selectedTab == 0) {
      // --- IMPORT ---
      tabContent = [
        Text(
          'Paste an Aura shared link, a playlist code or a Spotify URL.',
          style: TextStyle(fontSize: 13, height: 1.4, color: _muted(context)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _spotifyUrlController,
          enabled: !_isLoading,
          autofocus: true,
          style: const TextStyle(fontSize: 14.5),
          decoration: fieldDecoration(
            hintText: 'e.g. 7KX9Y2, aura://share?dpc=... or a Spotify URL',
            errorText: _inlineError,
            prefixIcon: Icon(Icons.link_rounded, color: accentColor, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_spotifyUrlController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _spotifyUrlController.clear();
                      setState(() {
                        _inlineError = null;
                      });
                    },
                  ),
                TextButton(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && data!.text!.trim().isNotEmpty) {
                      _spotifyUrlController.text = data.text!.trim();
                      setState(() {
                        _inlineError = null;
                      });
                    }
                  },
                  child: Text(
                    'PASTE',
                    style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          onChanged: (_) {
            setState(() {
              _inlineError = null;
            });
          },
        ),
        const SizedBox(height: 22),
        submitButton('Import playlist', () => _runImport(accentColor)),
      ];
    } else {
      // --- CREATE ---
      tabContent = [
        TextField(
          controller: _playlistNameController,
          enabled: !_isLoading,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration(labelText: 'Playlist title', errorText: _titleError),
          onChanged: (_) {
            if (_titleError != null) {
              setState(() {
                _titleError = null;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _playlistDescController,
          enabled: !_isLoading,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration(labelText: 'Description (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _authorController,
          readOnly: true,
          decoration: fieldDecoration(
            labelText: 'Owner',
            helperText: 'Taken from your account name',
            prefixIcon: Icon(Icons.verified_user_rounded, color: accentColor, size: 20),
            suffixIcon: Icon(Icons.lock_rounded, size: 18, color: _tint(context, 0.4)),
          ),
        ),
        const SizedBox(height: 14),
        _ToggleCard(
          icon: _newPlaylistIsPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
          title: _newPlaylistIsPublic ? 'Public' : 'Private',
          subtitle: _newPlaylistIsPublic
              ? 'Discoverable in the Global Playlists screen'
              : 'Only people with your direct link can open it',
          value: _newPlaylistIsPublic,
          accent: accentColor,
          onChanged: (val) async {
            if (val && !AuthService.instance.isLoggedIn) {
              final loggedIn = await AuthModalDialog.show(
                context,
                featurePrompt: 'Please sign in or create a free account to make playlists public!',
              );
              if (loggedIn) {
                setState(() => _newPlaylistIsPublic = true);
              }
              return;
            }
            setState(() => _newPlaylistIsPublic = val);
          },
        ),
        const SizedBox(height: 10),
        _ToggleCard(
          icon: Icons.sync_rounded,
          title: _newPlaylistIsSyncEnabled ? 'Collaborative sync on' : 'Read-only (no sync)',
          subtitle: _newPlaylistIsSyncEnabled
              ? 'Others can add songs and sync updates'
              : 'Collaborators cannot add songs to this playlist',
          value: _newPlaylistIsSyncEnabled,
          accent: accentColor,
          onChanged: (val) async {
            if (val && !AuthService.instance.isLoggedIn) {
              final loggedIn = await AuthModalDialog.show(
                context,
                featurePrompt: 'Please sign in or create a free account to enable collaborative sync!',
              );
              if (loggedIn) {
                setState(() => _newPlaylistIsSyncEnabled = true);
              }
              return;
            }
            setState(() => _newPlaylistIsSyncEnabled = val);
          },
        ),
        const SizedBox(height: 22),
        submitButton('Create playlist', () {
          if (_playlistNameController.text.trim().isEmpty) {
            setState(() {
              _titleError = 'Give your playlist a title.';
            });
            return;
          }
          _runCreate(accentColor);
        }),
      ];
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _tint(context, 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _selectedTab == 0 ? Icons.download_rounded : Icons.playlist_add_rounded,
                        color: accentColor,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _selectedTab == 0 ? 'Import playlist' : 'New playlist',
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SlidingSelector(
                  labels: const ['Import', 'Create'],
                  icons: const [Icons.download_rounded, Icons.add_rounded],
                  selected: _selectedTab,
                  accent: accentColor,
                  onChanged: (index) {
                    if (_isLoading) return;
                    setState(() {
                      _selectedTab = index;
                      _inlineError = null;
                      _titleError = null;
                    });
                  },
                ),
                const SizedBox(height: 18),
                ...tabContent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}