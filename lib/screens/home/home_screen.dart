import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/customization_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/app_artwork_image.dart';
import '../../widgets/shimmer_placeholders/shimmer_placeholder.dart';
import '../search/search_screen.dart';
import '../library/library_screen.dart';
import '../queue/queue_screen.dart';
import '../settings/settings_screen.dart';
import '../handoff/nearby_share_screen.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/network_status_banner.dart';
// The home tab now draws its own pull-to-refresh (see _VinylRefreshHeader),
// so VinylRefreshIndicator is no longer used here. The import is kept only in
// case other helpers used in this file come from it; delete it if the
// analyzer agrees it is unused.
// ignore: unused_import
import '../../widgets/vinyl_refresh_indicator.dart';
import '../../widgets/adaptive_navigation_bar.dart';
import '../../widgets/audio_output_picker_modal.dart';
import '../../providers/multi_device_sync_provider.dart';
import '../../services/update/update_service.dart';
import '../../services/music_sources/source_manager.dart';
import '../../services/sharing/playlist_link_share_service.dart';
import '../../widgets/playlist_imported_dialog.dart';
import '../../routes/app_routes.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;
  String _selectedLanguage = 'All';

  static const List<String> _languages = ['All', 'Punjabi', 'Hindi', 'English', 'Haryanvi'];

  static const List<_QuickAction> _quickActions = [
    _QuickAction('Sync Audio', Icons.speaker_group_rounded, opensOutputPicker: true),
    _QuickAction('Favorites', Icons.favorite_rounded, tab: 2),
    _QuickAction('Downloads', Icons.download_done_rounded, tab: 2),
    _QuickAction('AI Curator', Icons.auto_awesome_rounded, tab: 1),
  ];

  static const List<_Mood> _moods = [
    _Mood('Punjabi Hits', Icons.celebration_rounded, Color(0xFFF59E0B), Color(0xFFB45309)),
    _Mood('Bollywood Romance', Icons.favorite_rounded, Color(0xFFEC4899), Color(0xFF9D174D)),
    _Mood('Lo-Fi Chill', Icons.nights_stay_rounded, Color(0xFF8B5CF6), Color(0xFF4C1D95)),
    _Mood('Gym Workout', Icons.fitness_center_rounded, Color(0xFFEF4444), Color(0xFF991B1B)),
    _Mood('Haryanvi Mix', Icons.bolt_rounded, Color(0xFF10B981), Color(0xFF065F46)),
    _Mood('Retro 90s', Icons.album_rounded, Color(0xFF3B82F6), Color(0xFF1E3A8A)),
  ];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = StorageService.getLastSelectedHomeLanguage();
    SourceManager.fallbackNotifier.addListener(_handleSourceFallback);
    PlaylistLinkShareService.importEventNotifier.addListener(_handlePlaylistImportEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
      final hasPendingImport = PlaylistLinkShareService.pendingImportEvent != null ||
          PlaylistLinkShareService.importEventNotifier.value != null;
      if (!hasPendingImport && !StorageService.hasCompletedOnboarding()) {
        _showFirstLaunchOnboardingModal(context);
      }
      _checkPendingPlaylistImport();
    });
  }

  @override
  void dispose() {
    SourceManager.fallbackNotifier.removeListener(_handleSourceFallback);
    PlaylistLinkShareService.importEventNotifier.removeListener(_handlePlaylistImportEvent);
    super.dispose();
  }

  void _checkPendingPlaylistImport() {
    final event = PlaylistLinkShareService.consumePendingEvent();
    if (event != null && mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          final targetContext = rootNavigatorKey.currentContext ?? context;
          PlaylistImportSuccessDialog.show(targetContext, event, ref);
        }
      });
    }
  }

  void _handlePlaylistImportEvent() {
    final event = PlaylistLinkShareService.consumePendingEvent();
    if (event == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final targetContext = rootNavigatorKey.currentContext ?? context;
        PlaylistImportSuccessDialog.show(targetContext, event, ref);
      }
    });
  }

  void _handleSourceFallback() {
    final event = SourceManager.fallbackNotifier.value;
    if (event == null || !mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Playing via YouTube fallback (JioSaavn unavailable)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);

    Widget tabBody;
    switch (_currentTab) {
      case 0:
        tabBody = _buildHomeTab(context);
        break;
      case 1:
        tabBody = const SearchScreen();
        break;
      case 2:
        tabBody = const LibraryScreen();
        break;
      case 3:
        tabBody = const QueueScreen();
        break;
      case 4:
        tabBody = const SettingsScreen();
        break;
      default:
        tabBody = Container();
    }

    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;

    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double bottomMargin = bottomInset > 0 ? bottomInset + 8.0 : 16.0;
    final double miniPlayerBottom = isKeyboardOpen
        ? 6.0
        : ((customBranding.navBarStyle == 'os_style')
            ? (PlatformInfo.isIOS ? bottomInset + 70.0 : (bottomInset > 0 ? bottomInset + 70.0 : 70.0))
            : (bottomMargin + 54.0));

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: RepaintBoundary(
        child: _buildBottomNavigationBar(context, customBranding.accentColor, customBranding.navBarStyle),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: NetworkStatusBanner(
          child: Stack(
            children: [
              RepaintBoundary(child: tabBody),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: miniPlayerBottom,
                child: const RepaintBoundary(
                  child: MiniPlayer(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOME TAB
  //
  //   Fixed top row    language filter  +  [ output | share ] capsule
  //   Scrolling body   pull-to-refresh, hero, shortcuts, rails, moods, list
  //
  // The top row sits below the status bar / notch and does not scroll, so
  // nothing is ever drawn under the device's top bezel.
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHomeTab(BuildContext context) {
    final trendingAsync = ref.watch(trendingTracksProvider);
    final recommendedAsync = ref.watch(dynamicRecommendationsProvider);
    final accentColor = ref.watch(customizationProvider).accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final historyList = StorageService.getListeningHistory();
    final List<Track> historyTracks = [];
    for (final item in historyList) {
      if (item['track_id'] != null) {
        historyTracks.add(
          Track(
            id: item['track_id'].toString(),
            title: item['title']?.toString() ?? 'Track',
            artist: item['artist']?.toString() ?? 'Unknown Artist',
            album: item['album']?.toString() ?? 'Album',
            duration: item['duration']?.toString() ?? '3:30',
            artworkUrl: item['artworkUrl']?.toString() ?? '',
            audioUrl: item['audioUrl']?.toString() ?? '',
            genre: item['genre']?.toString() ?? '',
          ),
        );
      }
    }

    final continueTracks =
        historyTracks.isNotEmpty ? historyTracks.take(10).toList() : Track.mockTracks.sublist(0, 4);

    // Space for the status bar / notch, with a little extra breathing room
    // (and a minimum, for devices that report no inset).
    final topSpace = math.max(MediaQuery.of(context).padding.top, 12.0) + 8.0;
    final glowAlpha = isDark ? 0.15 : 0.08;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withValues(alpha: glowAlpha),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topSpace),
          _buildTopBar(context, accentColor),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomScrollView(
                  // Bouncing physics on every platform: the pull-to-refresh
                  // header lives in the overscroll area.
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    CupertinoSliverRefreshControl(
                      refreshTriggerPullDistance: 96,
                      refreshIndicatorExtent: 76,
                      onRefresh: _refreshHome,
                      builder: (context, mode, pulledExtent, triggerDistance, indicatorExtent) {
                        return _VinylRefreshHeader(
                          mode: mode,
                          pulledExtent: pulledExtent,
                          triggerDistance: triggerDistance,
                          accent: accentColor,
                        );
                      },
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 10, bottom: 160),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // 1. Tracks for the selected language (when a filter is active)
                          if (_selectedLanguage != 'All')
                            _buildLanguageTracksSection(context, _selectedLanguage, accentColor),

                          // 2. Hero card
                          _buildHeroStationCard(context, continueTracks.first, accentColor),
                          const SizedBox(height: 16),

                          // 3. Shortcuts
                          _buildQuickActionGrid(context, accentColor),
                          const SizedBox(height: 30),

                          // 4. Continue listening
                          _buildTrackRail(context, 'Continue Listening', continueTracks, accentColor, large: true),
                          const SizedBox(height: 30),

                          // 5. Trending
                          trendingAsync.when(
                            loading: () => const RailShimmer(),
                            error: (err, stack) => _buildTrackRail(
                              context,
                              'Trending Now',
                              Track.mockTracks.sublist(3, 6),
                              accentColor,
                            ),
                            data: (tracks) => _buildTrackRail(
                              context,
                              'Trending Now',
                              tracks.isEmpty ? Track.mockTracks.sublist(3, 6) : tracks,
                              accentColor,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // 6. Moods
                          _buildQuickGenreMoodsRail(context, accentColor),
                          const SizedBox(height: 30),

                          // 7. Recommended
                          _buildSectionHeader(
                            context,
                            'Recommended For You',
                            accentColor,
                            onSeeAll: () {
                              final recsData = recommendedAsync.value ?? Track.mockTracks;
                              _showSeeAllTracksSheet(context, 'Recommended For You', recsData);
                            },
                          ),
                          const SizedBox(height: 10),
                          recommendedAsync.when(
                            loading: () => const Column(
                              children: [
                                TrackTileShimmer(),
                                TrackTileShimmer(),
                                TrackTileShimmer(),
                              ],
                            ),
                            error: (err, stack) => _buildTrackList(Track.mockTracks, accentColor),
                            data: (tracks) =>
                                _buildTrackList(tracks.isEmpty ? Track.mockTracks : tracks, accentColor),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),

                // Soft edge where the list slides under the fixed top row
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 14,
                  child: IgnorePointer(
                    child: _buildTopFade(context, accentColor, glowAlpha),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopFade(BuildContext context, Color accentColor, double glowAlpha) {
    // Roughly the page color at this height: scaffold background plus what
    // is left of the accent glow.
    final edge = Color.alphaBlend(
      accentColor.withValues(alpha: glowAlpha * 0.7),
      Theme.of(context).scaffoldBackgroundColor,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [edge, edge.withValues(alpha: 0)],
        ),
      ),
    );
  }

  Future<void> _refreshHome() async {
    ref.invalidate(trendingTracksProvider);
    ref.invalidate(dynamicRecommendationsProvider);
    try {
      await Future.wait([
        ref.read(trendingTracksProvider.future),
        ref.read(dynamicRecommendationsProvider.future),
        // Let the record make at least a turn, even when data is instant.
        Future<void>.delayed(const Duration(milliseconds: 900)),
      ]);
    } catch (_) {}
    // Pick up anything played since the last build (Continue Listening).
    if (mounted) setState(() {});
  }

  // ── Fixed top row ──────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 10),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(child: _buildLanguageCategoryBar(context, accentColor)),
            const SizedBox(width: 8),
            _buildActionCapsule(context, accentColor),
          ],
        ),
      ),
    );
  }

  /// The only two buttons at the top: audio output and share, in one capsule.
  Widget _buildActionCapsule(BuildContext context, Color accentColor) {
    final isInGroup = ref.watch(multiDeviceSyncProvider).session.isInGroup;
    final iconColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9);

    Widget button({
      required String tooltip,
      required VoidCallback onPressed,
      required Widget icon,
      required BorderRadius radius,
    }) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: SizedBox(width: 48, height: 44, child: Center(child: icon)),
        ),
      );
    }

    return Material(
      color: _tint(context, 0.07),
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(side: BorderSide(color: _tint(context, 0.08))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            tooltip: 'Sync Audio & Multi-Device',
            onPressed: () => showAudioOutputPickerModal(context),
            radius: const BorderRadius.horizontal(left: Radius.circular(22)),
            // Lights up while this device is in a sync group.
            icon: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isInGroup ? accentColor : accentColor.withValues(alpha: 0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.speaker_group_rounded,
                size: 20,
                color: isInGroup ? _onColor(accentColor) : iconColor,
              ),
            ),
          ),
          Container(width: 1, height: 18, color: _tint(context, 0.12)),
          button(
            tooltip: 'Nearby Share & Handoff',
            onPressed: () => NearbyShareScreen.showHandoffModal(context),
            radius: const BorderRadius.horizontal(right: Radius.circular(22)),
            icon: Icon(Icons.share_rounded, size: 20, color: iconColor),
          ),
        ],
      ),
    );
  }

  // Language filter (All, Punjabi, Hindi, English, Haryanvi)
  Widget _buildLanguageCategoryBar(BuildContext context, Color accentColor) {
    return ShaderMask(
      // Chips fade out as they slide toward the capsule.
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.9, 1.0],
        ).createShader(bounds);
      },
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 20, right: 20),
        itemCount: _languages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final name = _languages[index];
          final isSelected = _selectedLanguage.toLowerCase() == name.toLowerCase();

          return Center(
            child: GestureDetector(
              onTap: () {
                triggerHaptic(HapticFeedbackType.selection);
                setState(() {
                  _selectedLanguage = name;
                });
                StorageService.saveLastSelectedHomeLanguage(name);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: 38,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : _tint(context, 0.07),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: isSelected ? accentColor : _tint(context, 0.08),
                  ),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? _onColor(accentColor)
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _buildLanguageTracksSection(BuildContext context, String lang, Color accentColor) {
    final genreAsync = ref.watch(genreTracksProvider('$lang Hits'));

    return genreAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(bottom: 30),
        child: RailShimmer(),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (tracks) {
        final liveTracks = tracks.where((t) => !t.id.startsWith('mock_')).toList();
        final displayTracks = liveTracks.isNotEmpty ? liveTracks : tracks;
        if (displayTracks.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: _buildTrackRail(
            context,
            '$lang Top Hits',
            displayTracks,
            accentColor,
            large: true,
            onSeeAll: () => _showSeeAllTracksSheet(context, '$lang Hits', displayTracks),
          ),
        );
      },
    );
  }

  // Hero card
  Widget _buildHeroStationCard(BuildContext context, Track heroTrack, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(playbackProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [accentColor.withValues(alpha: 0.34), const Color(0xFF1C1C20)]
              : [accentColor.withValues(alpha: 0.24), Colors.white],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.14 : 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AppArtworkImage(
              artworkUrl: heroTrack.artworkUrl,
              trackId: heroTrack.id,
              width: 104,
              height: 104,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 13, color: _muted(context)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'DAILY MUSIC STATION',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: _muted(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  heroTrack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    fontFamily: 'Outfit',
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  heroTrack.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _muted(context)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: () => notifier.playTrack(heroTrack),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play', maxLines: 1),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: _onColor(accentColor),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.fromLTRB(14, 0, 20, 0),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: _tint(context, 0.09),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        tooltip: 'Shuffle',
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        onPressed: () {
                          // Shuffle a copy; the shared list stays in order.
                          notifier.playCustomQueue([...Track.mockTracks]..shuffle(), initialIndex: 0);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Shortcuts
  Widget _buildQuickActionGrid(BuildContext context, Color accentColor) {
    final isInGroup = ref.watch(multiDeviceSyncProvider).session.isInGroup;

    Widget tile(_QuickAction action) {
      final isActive = action.opensOutputPicker && isInGroup;

      return Material(
        color: isActive ? accentColor.withValues(alpha: 0.16) : _tint(context, 0.055),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isActive ? accentColor : _tint(context, 0.07)),
        ),
        child: InkWell(
          onTap: () {
            if (action.opensOutputPicker) {
              showAudioOutputPickerModal(context);
            } else if (action.tab != null) {
              setState(() {
                _currentTab = action.tab!;
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isActive ? accentColor : accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    action.icon,
                    size: 20,
                    color: isActive ? _onColor(accentColor) : accentColor,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    action.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two per row on phones, all four in one row on wide screens.
          final columns = constraints.maxWidth >= 600 ? 4 : 2;
          final rows = <Widget>[];

          for (var start = 0; start < _quickActions.length; start += columns) {
            if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
            rows.add(
              Row(
                children: [
                  for (var i = start; i < start + columns; i++) ...[
                    if (i > start) const SizedBox(width: 10),
                    Expanded(
                      child: i < _quickActions.length ? tile(_quickActions[i]) : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          }

          return Column(children: rows);
        },
      ),
    );
  }

  // Moods rail
  Widget _buildQuickGenreMoodsRail(BuildContext context, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Explore Moods & Genres', accentColor),
        const SizedBox(height: 12),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _moods.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final mood = _moods[index];

              return Material(
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Ink(
                  width: 144,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [mood.light, mood.deep],
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _currentTab = 1;
                      });
                    },
                    child: Stack(
                      children: [
                        Positioned(
                          right: -8,
                          top: -8,
                          child: Icon(
                            mood.icon,
                            size: 60,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 12,
                          child: Text(
                            mood.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Section header
  Widget _buildSectionHeader(BuildContext context, String title, Color accentColor, {VoidCallback? onSeeAll}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: _muted(context),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.only(left: 12, right: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See all', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            )
          else
            const SizedBox(width: 12, height: 36),
        ],
      ),
    );
  }

  // Horizontal track rail
  Widget _buildTrackRail(
    BuildContext context,
    String title,
    List<Track> tracks,
    Color accentColor, {
    bool large = false,
    VoidCallback? onSeeAll,
  }) {
    final artworkSize = large ? 148.0 : 128.0;
    // Rail height follows the system font size so titles are never clipped.
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final railHeight = artworkSize + 10 + 40 * textScale + 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, title, accentColor, onSeeAll: onSeeAll),
        const SizedBox(height: 10),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              return _buildRailTrackCard(context, tracks[index], tracks, index, accentColor, size: artworkSize);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRailTrackCard(
    BuildContext context,
    Track track,
    List<Track> queue,
    int index,
    Color accentColor, {
    required double size,
  }) {
    final notifier = ref.read(playbackProvider.notifier);

    return SizedBox(
      width: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => notifier.playCustomQueue(queue, initialIndex: index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AppArtworkImage(
                  artworkUrl: track.artworkUrl,
                  trackId: track.id,
                  width: size,
                  height: size,
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
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _muted(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList(List<Track> tracks, Color accentColor) {
    final notifier = ref.read(playbackProvider.notifier);

    return Column(
      children: List.generate(tracks.length, (index) {
        final track = tracks[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Material(
            color: _tint(context, 0.045),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _tint(context, 0.06)),
            ),
            child: InkWell(
              onTap: () => notifier.playTrack(track),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    AppArtworkImage(
                      artworkUrl: track.artworkUrl,
                      trackId: track.id,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: _muted(context)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Play',
                      onPressed: () => notifier.playTrack(track),
                      icon: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.play_arrow_rounded, size: 22, color: accentColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showSeeAllTracksSheet(BuildContext context, String title, List<Track> tracks) {
    final accentColor = ref.read(customizationProvider).accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;

        void play(int index) {
          Navigator.pop(sheetContext);
          ref.read(playbackProvider.notifier).playCustomQueue(tracks, initialIndex: index);
        }

        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.78,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _tint(sheetContext, 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
                            style: TextStyle(fontSize: 12.5, color: _muted(sheetContext)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(8, 4, 8, MediaQuery.of(sheetContext).padding.bottom + 16),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: AppArtworkImage(
                        artworkUrl: track.artworkUrl,
                        trackId: track.id,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: _muted(context)),
                      ),
                      trailing: IconButton(
                        tooltip: 'Play',
                        icon: Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 32),
                        onPressed: () => play(index),
                      ),
                      onTap: () => play(index),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context, Color accentColor, String navBarStyle) {
    return AdaptiveNavigationBar(
      selectedIndex: _currentTab,
      onDestinationSelected: (index) => setState(() => _currentTab = index),
      destinations: const [
        AdaptiveNavigationDestination(icon: Icons.home_rounded, selectedIcon: Icons.home_rounded, label: 'Home'),
        AdaptiveNavigationDestination(icon: Icons.search_rounded, selectedIcon: Icons.search_rounded, label: 'Search', isSearch: true),
        AdaptiveNavigationDestination(icon: Icons.library_music_rounded, selectedIcon: Icons.library_music_rounded, label: 'Library'),
        AdaptiveNavigationDestination(icon: Icons.queue_music_rounded, selectedIcon: Icons.queue_music_rounded, label: 'Queue'),
        AdaptiveNavigationDestination(icon: Icons.settings_rounded, selectedIcon: Icons.settings_rounded, label: 'Settings'),
      ],
      navBarStyle: navBarStyle,
      accentColor: accentColor,
    );
  }

  void _showFirstLaunchOnboardingModal(BuildContext context) {
    final nameController = TextEditingController(text: StorageService.getUserName());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    int selectedR = 255, selectedG = 199, selectedB = 44;

    final colorPresets = [
      {'name': 'Gold', 'r': 255, 'g': 199, 'b': 44, 'color': const Color(0xFFFFC72C)},
      {'name': 'Cyan', 'r': 6, 'g': 182, 'b': 212, 'color': const Color(0xFF06B6D4)},
      {'name': 'Emerald', 'r': 16, 'g': 185, 'b': 129, 'color': const Color(0xFF10B981)},
      {'name': 'Purple', 'r': 168, 'g': 85, 'b': 247, 'color': const Color(0xFFA855F7)},
      {'name': 'Sunset', 'r': 249, 'g': 115, 'b': 22, 'color': const Color(0xFFF97316)},
      {'name': 'Crimson', 'r': 239, 'g': 68, 'b': 68, 'color': const Color(0xFFEF4444)},
    ];

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final activeColor = Color.fromARGB(255, selectedR, selectedG, selectedB);

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom +
                        math.max(MediaQuery.of(context).padding.bottom, 24.0),
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF1B1B1E) : Colors.white).withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.6), width: 1),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: activeColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(Icons.waving_hand_rounded, color: activeColor, size: 23),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Welcome to Aura Music',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Let\'s personalize your music player. Tell us your name and pick an accent color.',
                          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500, height: 1.45),
                        ),
                        const SizedBox(height: 24),

                        const Text('Your name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'Enter your name',
                            filled: true,
                            fillColor:
                                isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: activeColor, width: 1.5),
                            ),
                            prefixIcon: Icon(Icons.person_rounded, color: activeColor),
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text('Accent color', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: colorPresets.map((preset) {
                            final pColor = preset['color'] as Color;
                            final isSelected =
                                selectedR == preset['r'] && selectedG == preset['g'] && selectedB == preset['b'];

                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  selectedR = preset['r'] as int;
                                  selectedG = preset['g'] as int;
                                  selectedB = preset['b'] as int;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: pColor,
                                  border: Border.all(
                                    color: isSelected ? (isDark ? Colors.white : Colors.black) : Colors.transparent,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: pColor.withValues(alpha: 0.4),
                                      blurRadius: isSelected ? 12 : 4,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? Icon(Icons.check_rounded, color: _onColor(pColor), size: 22)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 28),

                        FilledButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isNotEmpty) {
                              await StorageService.setUserName(name);
                            }
                            await ref
                                .read(customizationProvider.notifier)
                                .updateAccentColor(selectedR, selectedG, selectedB);
                            await StorageService.setCompletedOnboarding(true);

                            if (mounted) {
                              Navigator.pop(context);
                              setState(() {});
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: activeColor,
                            foregroundColor: _onColor(activeColor),
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                          ),
                          child: const Text('Save & get started'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA
// ═════════════════════════════════════════════════════════════════════════════

class _QuickAction {
  const _QuickAction(this.title, this.icon, {this.tab, this.opensOutputPicker = false});

  final String title;
  final IconData icon;

  /// Bottom-navigation tab to switch to.
  final int? tab;

  /// Opens the audio output / multi-device sheet instead of switching tabs.
  final bool opensOutputPicker;
}

class _Mood {
  const _Mood(this.label, this.icon, this.light, this.deep);

  final String label;
  final IconData icon;
  final Color light;
  final Color deep;
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

// ═════════════════════════════════════════════════════════════════════════════
// PULL TO REFRESH
//
// Pulling opens a gap above the content. A small record rises into it,
// turning with your finger while a ring around it fills up. Past the trigger
// point the ring closes (with a haptic tick), then the record spins on its
// own until the new data has arrived and the gap closes again.
// ═════════════════════════════════════════════════════════════════════════════

class _VinylRefreshHeader extends StatefulWidget {
  const _VinylRefreshHeader({
    required this.mode,
    required this.pulledExtent,
    required this.triggerDistance,
    required this.accent,
  });

  final RefreshIndicatorMode mode;

  /// Current height of the gap.
  final double pulledExtent;

  /// How far to pull before a refresh starts.
  final double triggerDistance;
  final Color accent;

  @override
  State<_VinylRefreshHeader> createState() => _VinylRefreshHeaderState();
}

class _VinylRefreshHeaderState extends State<_VinylRefreshHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  /// Past the trigger point: the refresh is running or just finished.
  bool get _isLive {
    return widget.mode == RefreshIndicatorMode.armed ||
        widget.mode == RefreshIndicatorMode.refresh ||
        widget.mode == RefreshIndicatorMode.done;
  }

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _VinylRefreshHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == RefreshIndicatorMode.drag && widget.mode == RefreshIndicatorMode.armed) {
      triggerHaptic(HapticFeedbackType.selection);
    }
    _syncSpin();
  }

  void _syncSpin() {
    if (_isLive) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = (widget.pulledExtent / widget.triggerDistance).clamp(0.0, 1.0).toDouble();
    final opacity = (widget.pulledExtent / 40).clamp(0.0, 1.0).toDouble();
    final scale = _isLive ? 1.0 : 0.6 + 0.4 * Curves.easeOut.transform(progress);
    // The record turns with the pull, like dragging it with a finger.
    final dragAngle = widget.pulledExtent / widget.triggerDistance * math.pi * 1.5;

    return ClipRect(
      child: SizedBox(
        height: widget.pulledExtent,
        child: OverflowBox(
          // Keep the record full size while the gap is still small.
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.center,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: AnimatedBuilder(
                animation: _spin,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size.square(58),
                    painter: _RefreshVinylPainter(
                      accent: widget.accent,
                      ringTrack: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                      rotation: dragAngle + _spin.value * math.pi * 2,
                      pullProgress: progress,
                      // While live, the ring becomes a chasing arc.
                      chaseAngle: _isLive ? _spin.value * math.pi * 2 * 2 : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshVinylPainter extends CustomPainter {
  const _RefreshVinylPainter({
    required this.accent,
    required this.ringTrack,
    required this.rotation,
    required this.pullProgress,
    required this.chaseAngle,
  });

  final Color accent;
  final Color ringTrack;
  final double rotation;

  /// 0–1, how close the pull is to the trigger point.
  final double pullProgress;

  /// Start angle of the chasing arc, or null while still pulling.
  final double? chaseAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.shortestSide / 2 - 2;
    final discRadius = ringRadius - 6;
    final ringBounds = Rect.fromCircle(center: center, radius: ringRadius);

    // Ring
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = ringTrack,
    );
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = accent;
    final chase = chaseAngle;
    if (chase != null) {
      canvas.drawArc(ringBounds, chase, math.pi * 0.8, false, arcPaint);
    } else if (pullProgress > 0) {
      canvas.drawArc(ringBounds, -math.pi / 2, math.pi * 2 * pullProgress, false, arcPaint);
    }

    // Record (rotates)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    canvas.drawCircle(Offset.zero, discRadius, Paint()..color = const Color(0xFF101010));
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.10);
    for (final fraction in const [0.9, 0.76, 0.62, 0.5]) {
      canvas.drawCircle(Offset.zero, discRadius * fraction, groovePaint);
    }

    final labelRadius = discRadius * 0.38;
    canvas.drawCircle(Offset.zero, labelRadius, Paint()..color = accent);

    // Off-center marks on the label make the spin visible.
    final ink = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: labelRadius * 0.64),
      -math.pi * 0.85,
      math.pi * 0.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3
        ..color = ink.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(labelRadius * 0.45, labelRadius * 0.45),
      1.1,
      Paint()..color = ink.withValues(alpha: 0.55),
    );
    canvas.drawCircle(Offset.zero, labelRadius * 0.24, Paint()..color = const Color(0xFF0A0A0A));
    canvas.restore();

    // Light reflection (does not rotate)
    final sheen = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.16),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: 0.16),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [0.0, 0.08, 0.16, 0.5, 0.58, 0.66, 1.0],
        transform: const GradientRotation(math.pi * 0.2),
      ).createShader(Rect.fromCircle(center: center, radius: discRadius));
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: discRadius))
      ..addOval(Rect.fromCircle(center: center, radius: discRadius * 0.38));
    canvas.drawPath(ring, sheen);
  }

  @override
  bool shouldRepaint(covariant _RefreshVinylPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.pullProgress != pullProgress ||
        oldDelegate.chaseAngle != chaseAngle ||
        oldDelegate.accent != accent ||
        oldDelegate.ringTrack != ringTrack;
  }
}