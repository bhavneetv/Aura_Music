import 'dart:io';
import 'dart:ui';
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
import '../../services/storage/storage_service.dart';
import '../../widgets/network_status_banner.dart';
import '../../widgets/vinyl_refresh_indicator.dart';
import '../../widgets/adaptive_navigation_bar.dart';
import '../../services/update/update_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
      if (!StorageService.hasCompletedOnboarding()) {
        _showFirstLaunchOnboardingModal(context);
      }
    });
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

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: _buildBottomNavigationBar(context, customBranding.accentColor, customBranding.navBarStyle),
      body: SafeArea(
        bottom: false,
        child: NetworkStatusBanner(
          child: Stack(
            children: [
              tabBody,
              Positioned(
                left: 0,
                right: 0,
                bottom: (customBranding.navBarStyle == 'os_style' && PlatformInfo.isIOS)
                    ? 82.0
                    : (customBranding.navBarStyle == 'os_style' ? 70.0 : 76.0),
                child: const MiniPlayer(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HOME TAB REDESIGN
  // ---------------------------------------------------------------------
  Widget _buildHomeTab(BuildContext context) {
    final trendingAsync = ref.watch(trendingTracksProvider);
    final recommendedAsync = ref.watch(dynamicRecommendationsProvider);
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;
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

    final continueTracks = historyTracks.isNotEmpty ? historyTracks.take(10).toList() : Track.mockTracks.sublist(0, 4);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  accentColor.withValues(alpha: 0.15),
                  Colors.transparent,
                ]
              : [
                  accentColor.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
          stops: const [0.0, 0.40],
        ),
      ),
      child: VinylRefreshIndicator(
        onRefresh: () async {
          ref.invalidate(trendingTracksProvider);
          ref.invalidate(dynamicRecommendationsProvider);
          try {
            await Future.wait([
              ref.read(trendingTracksProvider.future),
              ref.read(dynamicRecommendationsProvider.future),
            ]);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 160, top: 12),
          children: [
            // 1. Personal Header & Greeting
            _buildHomeHeader(context, accentColor),
            const SizedBox(height: 20),

            // 2. Ultra Hero Feature Banner Card
            _buildHeroStationCard(context, continueTracks.first, accentColor),
            const SizedBox(height: 24),

            // 3. Quick Action Grid / Shortcuts
            _buildQuickActionGrid(context, accentColor),
            const SizedBox(height: 28),

            // 4. Continue Listening Rail
            _buildTrackRail(context, 'Continue Listening', continueTracks, accentColor, large: true),
            const SizedBox(height: 28),

            // 5. Trending Now Horizontal Rail
            trendingAsync.when(
              loading: () => const RailShimmer(),
              error: (err, stack) => _buildTrackRail(context, 'Trending Now', Track.mockTracks.sublist(3, 6), accentColor),
              data: (tracks) => _buildTrackRail(
                context,
                'Trending Now',
                tracks.isEmpty ? Track.mockTracks.sublist(3, 6) : tracks,
                accentColor,
              ),
            ),
            const SizedBox(height: 28),

            // 6. Quick Genre Moods Rail
            _buildQuickGenreMoodsRail(context, accentColor),
            const SizedBox(height: 32),

            // 7. Recommended For You List
            _buildSectionHeader(
              context,
              'Recommended For You',
              accentColor,
              onSeeAll: () {
                final recsData = recommendedAsync.value ?? Track.mockTracks;
                _showSeeAllTracksSheet(context, 'Recommended For You', recsData);
              },
            ),
            const SizedBox(height: 8),
            recommendedAsync.when(
              loading: () => const Column(
                children: [
                  TrackTileShimmer(),
                  TrackTileShimmer(),
                  TrackTileShimmer(),
                ],
              ),
              error: (err, stack) => _buildTrackList(Track.mockTracks, accentColor),
              data: (tracks) => _buildTrackList(tracks.isEmpty ? Track.mockTracks : tracks, accentColor),
            ),
          ],
        ),
      ),
    );
  }

  // Header & Personal Greeting Bar
  Widget _buildHomeHeader(BuildContext context, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: TextStyle(
                    color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      accentColor,
                    ],
                  ).createShader(bounds),
                  child: Text(
                    customBranding.appName,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _currentTab = 1;
              });
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_rounded, color: accentColor, size: 20),
            ),
            tooltip: 'Voice Search',
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04),
              shape: BoxShape.circle,
              border: Border.all(
                color: accentColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              customBranding.brandingIcon,
              color: accentColor,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // Hero Station Banner Card
  Widget _buildHeroStationCard(BuildContext context, Track heroTrack, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(playbackProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [accentColor.withValues(alpha: 0.35), const Color(0xFF1E1E22)]
              : [accentColor.withValues(alpha: 0.20), Colors.white],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AppArtworkImage(
              artworkUrl: heroTrack.artworkUrl,
              trackId: heroTrack.id,
              width: 90,
              height: 90,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 12, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'Daily Music Station ✨',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  heroTrack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Outfit'),
                ),
                const SizedBox(height: 2),
                Text(
                  heroTrack.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => notifier.playTrack(heroTrack),
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
                      label: const Text('Play Now', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded, size: 20, color: accentColor),
                      onPressed: () {
                        notifier.playCustomQueue(Track.mockTracks..shuffle(), initialIndex: 0);
                      },
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

  // Quick Action Pill Bar
  Widget _buildQuickActionGrid(BuildContext context, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final actions = [
      {'title': 'Favorites', 'icon': Icons.favorite_rounded, 'tab': 2},
      {'title': 'Downloads', 'icon': Icons.download_done_rounded, 'tab': 2},
      {'title': 'History', 'icon': Icons.history_rounded, 'tab': 2},
      {'title': 'AI Curator', 'icon': Icons.auto_awesome_rounded, 'tab': 1},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: actions.map((act) {
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _currentTab = act['tab'] as int;
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(act['icon'] as IconData, size: 20, color: accentColor),
                    const SizedBox(height: 6),
                    Text(
                      act['title'] as String,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Quick Genre Moods Horizontal Rail
  Widget _buildQuickGenreMoodsRail(BuildContext context, Color accentColor) {
    final genres = ['Punjabi Hits', 'Bollywood Romance', 'Lo-Fi Chill', 'Gym Workout', 'Haryanvi Mix', 'Retro 90s'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Explore Moods & Genres', accentColor),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(genre),
                  backgroundColor: accentColor.withValues(alpha: 0.12),
                  side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
                  labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onPressed: () {
                    setState(() {
                      _currentTab = 1;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Section Header
  Widget _buildSectionHeader(BuildContext context, String title, Color accentColor, {VoidCallback? onSeeAll}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See All',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: accentColor),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Horizontal Track Card Rail
  Widget _buildTrackRail(BuildContext context, String title, List<Track> tracks, Color accentColor, {bool large = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, title, accentColor),
        const SizedBox(height: 12),
        SizedBox(
          height: large ? 200 : 175,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildRailTrackCard(context, track, tracks, index, accentColor, large: large);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRailTrackCard(BuildContext context, Track track, List<Track> queue, int index, Color accentColor, {required bool large}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(playbackProvider.notifier);
    final cardWidth = large ? 150.0 : 130.0;
    final artworkHeight = large ? 130.0 : 110.0;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: () => notifier.playCustomQueue(queue, initialIndex: index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AppArtworkImage(
                    artworkUrl: track.artworkUrl,
                    trackId: track.id,
                    width: cardWidth,
                    height: artworkHeight,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList(List<Track> tracks, Color accentColor) {
    final notifier = ref.read(playbackProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: List.generate(tracks.length, (index) {
        final track = tracks[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => notifier.playTrack(track),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                ),
                child: Row(
                  children: [
                    AppArtworkImage(
                      artworkUrl: track.artworkUrl,
                      trackId: track.id,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(12),
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                      onPressed: () => notifier.playTrack(track),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.read(customizationProvider).accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF171717) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      leading: AppArtworkImage(
                        artworkUrl: track.artworkUrl,
                        trackId: track.id,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: IconButton(
                        icon: Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 32),
                        onPressed: () {
                          Navigator.pop(context);
                          ref.read(playbackProvider.notifier).playCustomQueue(tracks, initialIndex: index);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(playbackProvider.notifier).playCustomQueue(tracks, initialIndex: index);
                      },
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

  String _greeting() {
    final hour = DateTime.now().hour;
    String timeGreeting = 'Good morning';
    String emoji = '🌅';
    if (hour < 12) {
      timeGreeting = 'Good morning';
      emoji = '🌅';
    } else if (hour < 17) {
      timeGreeting = 'Good afternoon';
      emoji = '☀️';
    } else if (hour < 22) {
      timeGreeting = 'Good evening';
      emoji = '🌙';
    } else {
      timeGreeting = 'Good night';
      emoji = '✨';
    }
    final userName = StorageService.getUserName();
    if (userName.trim().isNotEmpty) {
      return '$timeGreeting, ${userName.trim()} $emoji';
    }
    return '$timeGreeting, Listener $emoji';
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF1B1B1E) : Colors.white).withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.6), width: 1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: activeColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.waving_hand_rounded, color: activeColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Welcome to Aura Music',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Let\'s personalize your music player! Tell us your name and pick a favorite theme accent color.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4),
                      ),
                      const SizedBox(height: 22),

                      const Text('What is your name?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Enter your name (e.g. Bhavneet)...',
                          filled: true,
                          fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: activeColor, width: 1.5),
                          ),
                          prefixIcon: Icon(Icons.person_rounded, color: activeColor),
                        ),
                      ),
                      const SizedBox(height: 22),

                      const Text('Pick Theme Accent Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: colorPresets.map((preset) {
                          final pColor = preset['color'] as Color;
                          final isSelected = selectedR == preset['r'] && selectedG == preset['g'] && selectedB == preset['b'];

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
                              child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 22) : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 26),

                      ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          if (name.isNotEmpty) {
                            await StorageService.setUserName(name);
                          }
                          await ref.read(customizationProvider.notifier).updateAccentColor(selectedR, selectedG, selectedB);
                          await StorageService.setCompletedOnboarding(true);

                          if (mounted) {
                            Navigator.pop(context);
                            setState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeColor,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('Save & Get Started ✨', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ],
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