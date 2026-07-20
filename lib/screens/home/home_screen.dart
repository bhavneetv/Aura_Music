import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/customization_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/shimmer_placeholders/shimmer_placeholder.dart';
import '../search/search_screen.dart';
import '../library/library_screen.dart';
import '../queue/queue_screen.dart';
import '../settings/settings_screen.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/network_status_banner.dart';
import '../../widgets/vinyl_refresh_indicator.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);

    // Determine which widget builds the tab body
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
      bottomNavigationBar: _buildBottomNavigationBar(context, customBranding.accentColor),
      body: SafeArea(
        bottom: false,
        child: NetworkStatusBanner(
          child: Stack(
            children: [
              // Render active tab body
              tabBody,

              // Persistent Mini Player above bottom nav bar
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Home Tab Content
  Widget _buildHomeTab(BuildContext context) {
    final trendingAsync = ref.watch(trendingTracksProvider);
    final recommendedAsync = ref.watch(dynamicRecommendationsProvider);
    final customBranding = ref.watch(customizationProvider);

    // Get actual listening history from Hive
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

    return VinylRefreshIndicator(
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
        padding: const EdgeInsets.only(bottom: 96, top: 16),
        children: [
          // welcome header
          _buildHomeHeader(context),
          const SizedBox(height: 24),

          // Continue Listening (Actual History)
          _buildTrackRail(context, 'Continue Listening', continueTracks),
          const SizedBox(height: 12),

          // Trending
          trendingAsync.when(
            loading: () => const RailShimmer(),
            error: (err, stack) => _buildTrackRail(context, 'Trending Now', Track.mockTracks.sublist(3, 6)),
            data: (tracks) => _buildTrackRail(
              context,
              'Trending Now',
              tracks.isEmpty ? Track.mockTracks.sublist(3, 6) : tracks,
            ),
          ),
          const SizedBox(height: 12),

          // Genres & Moods gradient cards
          _buildGenreSection(context),
          const SizedBox(height: 24),

          // Recommended
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recommended For You',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: 'Outfit',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  'See All',
                  style: TextStyle(
                    color: customBranding.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          recommendedAsync.when(
            loading: () => const Column(
              children: [
                TrackTileShimmer(),
                TrackTileShimmer(),
                TrackTileShimmer(),
              ],
            ),
            error: (err, stack) => _buildTrackList(Track.mockTracks),
            data: (tracks) => _buildTrackList(tracks.isEmpty ? Track.mockTracks : tracks),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList(List<Track> tracks) {
    final notifier = ref.read(playbackProvider.notifier);
    return Column(
      children: List.generate(tracks.length, (index) {
        final track = tracks[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          leading: SizedBox(
            width: 50,
            height: 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                track.artworkUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 50,
                  height: 50,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.music_note_rounded),
                ),
              ),
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.favorite_border_rounded, size: 20),
          onTap: () {
            notifier.playTrack(track);
          },
        );
      }),
    );
  }

  // Home Header widget (greeting, title, and search bar)
  Widget _buildHomeHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(customBranding.brandingIcon, color: customBranding.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Good Afternoon, Listener',
                style: TextStyle(
                  color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Welcome to ${customBranding.appName}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: 'Outfit',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
          ),
          const SizedBox(height: 18),
          _buildSearchBar(context),
        ],
      ),
    );
  }

  // Search Input UI
  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      decoration: AppTheme.glassDecoration(
        context: context,
        opacity: isDark ? 0.06 : 0.05,
        radius: AppTheme.pillRadius,
      ),
      child: TextField(
        readOnly: true,
        onTap: () {
          setState(() {
            _currentTab = 1;
          });
        },
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Search songs, artists, playlists...',
          hintStyle: TextStyle(
            color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.4),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.4),
            size: 20,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  // Horizontal Track rail builder
  Widget _buildTrackRail(BuildContext context, String title, List<Track> tracks) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'Outfit',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                'See All',
                style: TextStyle(
                  color: customBranding.accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: Consumer(
            builder: (context, ref, child) {
              final notifier = ref.read(playbackProvider.notifier);
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 24, right: 8),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return GestureDetector(
                    onTap: () {
                      notifier.playTrack(track);
                    },
                    child: Container(
                      width: 130,
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                              child: Image.network(
                                  track.artworkUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.grey.shade800,
                                    child: const Icon(Icons.music_note_rounded),
                                  ),
                                ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGenreSection(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final List<Map<String, dynamic>> genres = [
      {'name': 'Jazz & Calm', 'colors': [customBranding.accentColor, customBranding.accentColor.withOpacity(0.6)]},
      {'name': 'Retro Synth', 'colors': [const Color(0xFFE040FB), const Color(0xFF651FFF)]},
      {'name': 'Acoustic Study', 'colors': [const Color(0xFF26A69A), const Color(0xFF00796B)]},
      {'name': 'Lo-Fi Chill', 'colors': [const Color(0xFF42A5F5), const Color(0xFF1565C0)]},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'Genres & Moods',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Outfit',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 24, right: 8),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              return Container(
                width: 140,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: genre['colors'] as List<Color>,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (genre['colors'] as List<Color>)[0].withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      genre['name'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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

  // Bottom Navigation Bar Widget
  Widget _buildBottomNavigationBar(BuildContext context, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return NavigationBarTheme(
      data: NavigationBarThemeData(
        indicatorColor: accentColor.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _currentTab,
        height: 72,
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF3EFE9),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_rounded),
            selectedIcon: Icon(Icons.home_rounded, color: accentColor),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: accentColor),
            label: 'Search',
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_music_rounded),
            selectedIcon: Icon(Icons.library_music_rounded, color: accentColor),
            label: 'Library',
          ),
          NavigationDestination(
            icon: const Icon(Icons.queue_music_rounded),
            selectedIcon: Icon(Icons.queue_music_rounded, color: accentColor),
            label: 'Queue',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_rounded),
            selectedIcon: Icon(Icons.settings_rounded, color: accentColor),
            label: 'Settings',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _currentTab = index;
          });
        },
      ),
    );
  }
}
