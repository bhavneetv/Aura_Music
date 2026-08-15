import 'dart:ui';
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
      bottomNavigationBar: _buildBottomNavigationBar(context, customBranding.accentColor, customBranding.navBarStyle),
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
                GestureDetector(
                  onTap: () {
                    final recsData = recommendedAsync.value ?? Track.mockTracks;
                    _showSeeAllTracksSheet(context, 'Recommended For You', recsData);
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      color: customBranding.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
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

    int selectedR = 255, selectedG = 199, selectedB = 44; // Gold default

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

            return Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
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
                      Icon(Icons.waving_hand_rounded, color: activeColor, size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        'Welcome to Aura Music 🎵',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Let\'s personalize your music player! Tell us your name and pick a favorite theme accent color.',
                    style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // 1. Name Input
                  const Text('What is your name?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Enter your name (e.g. Bhavneet)...',
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      prefixIcon: Icon(Icons.person_rounded, color: activeColor),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2. Theme Color Selection
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
                                blurRadius: isSelected ? 10 : 4,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 22) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Save & Continue Button
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
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    child: const Text('Save & Get Started ✨', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            );
          },
        );
      },
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
                _greeting(),
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
          const SizedBox(height: 14),
          _buildLanguageFilterChips(context),
          const SizedBox(height: 14),
          _buildSearchBar(context),
        ],
      ),
    );
  }

  Widget _buildLanguageFilterChips(BuildContext context) {
    final activeLangs = StorageService.getPreferredLanguages();
    final allLangs = ['Punjabi', 'Hindi', 'English', 'Bhangra', 'Bollywood', 'LoFi'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: allLangs.map((lang) {
          final isSelected = activeLangs.contains(lang);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(lang),
              selected: isSelected,
              selectedColor: AppTheme.goldAccent.withOpacity(0.2),
              checkmarkColor: AppTheme.goldAccent,
              side: BorderSide(
                color: isSelected ? AppTheme.goldAccent : Colors.white12,
              ),
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.goldAccent : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              onSelected: (val) async {
                List<String> updated = List.from(activeLangs);
                if (val) {
                  updated = [lang];
                } else {
                  updated.remove(lang);
                }
                await StorageService.savePreferredLanguages(updated);
                ref.invalidate(trendingTracksProvider);
                ref.invalidate(dynamicRecommendationsProvider);
                setState(() {});
              },
            ),
          );
        }).toList(),
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
              GestureDetector(
                onTap: () => _showSeeAllTracksSheet(context, title, tracks),
                child: Text(
                  'See All',
                  style: TextStyle(
                    color: customBranding.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
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

  // Bottom Navigation Bar Widget - Supporting Default Floating Glass & OS Style (iOS Liquid Glass / Android M3)
  Widget _buildBottomNavigationBar(BuildContext context, Color accentColor, String navBarStyle) {
    return AdaptiveNavigationBar(
      selectedIndex: _currentTab,
      navBarStyle: navBarStyle,
      accentColor: accentColor,
      onDestinationSelected: (index) {
        setState(() {
          _currentTab = index;
        });
      },
      destinations: const [
        AdaptiveNavigationDestination(
          icon: 'house',
          selectedIcon: 'house.fill',
          label: 'Home',
        ),
        AdaptiveNavigationDestination(
          icon: 'search',
          selectedIcon: 'search',
          label: 'Search',
          isSearch: true,
        ),
        AdaptiveNavigationDestination(
          icon: Icons.library_music_outlined,
          selectedIcon: Icons.library_music_rounded,
          label: 'Library',
        ),
        AdaptiveNavigationDestination(
          icon: Icons.queue_music_outlined,
          selectedIcon: Icons.queue_music_rounded,
          label: 'Queue',
        ),
        AdaptiveNavigationDestination(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: 'Settings',
        ),
      ],
    );
  }
  void _showSeeAllTracksSheet(BuildContext context, String sectionTitle, List<Track> existingTracks) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Expand list up to 15-25 tracks
    List<Track> fullList = List.from(existingTracks);
    if (fullList.length < 15) {
      try {
        final more = await ref.read(musicSourceProvider).getDynamicRecommendations();
        final Map<String, Track> unique = {};
        for (final t in [...fullList, ...more]) {
          unique[t.id] = t;
        }
        fullList = unique.values.toList();
      } catch (_) {}
    }
    final displayList = fullList.take(25).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141416) : const Color(0xFFFAF7F2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$sectionTitle (${displayList.length})',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer(
                  builder: (context, ref, child) {
                    final notifier = ref.read(playbackProvider.notifier);
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: displayList.length,
                      itemBuilder: (context, index) {
                        final track = displayList[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              track.artworkUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 48,
                                height: 48,
                                color: Colors.grey.shade800,
                                child: const Icon(Icons.music_note_rounded),
                              ),
                            ),
                          ),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${track.artist} • ${track.genre}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.play_arrow_rounded, size: 20),
                          onTap: () {
                            notifier.playTrack(track);
                            Navigator.pop(context);
                          },
                        );
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
}
