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
      extendBody: true,
      bottomNavigationBar: _buildBottomNavigationBar(context, customBranding.accentColor, customBranding.navBarStyle),
      body: SafeArea(
        bottom: false,
        child: NetworkStatusBanner(
          child: Stack(
            children: [
              // Render active tab body
              tabBody,

              // Persistent Mini Player above bottom nav bar
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
  // HOME TAB
  // ---------------------------------------------------------------------
  Widget _buildHomeTab(BuildContext context) {
    final trendingAsync = ref.watch(trendingTracksProvider);
    final recommendedAsync = ref.watch(dynamicRecommendationsProvider);
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    return DecoratedBox(
      // Subtle ambient background wash behind the whole tab — gives the
      // screen depth instead of a flat single-color canvas.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  customBranding.accentColor.withOpacity(0.10),
                  Colors.transparent,
                ]
              : [
                  customBranding.accentColor.withOpacity(0.06),
                  Colors.transparent,
                ],
          stops: const [0.0, 0.35],
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
          padding: const EdgeInsets.only(bottom: 150, top: 12),
          children: [
            // welcome header
            _buildHomeHeader(context),
            const SizedBox(height: 28),

            // Continue Listening (Actual History)
            _buildTrackRail(context, 'Continue Listening', continueTracks, large: true),
            const SizedBox(height: 28),

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
            const SizedBox(height: 28),

            // Genres & Moods gradient cards
            _buildGenreSection(context),
            const SizedBox(height: 32),

            // Recommended
            _buildSectionHeader(
              context,
              'Recommended For You',
              onSeeAll: () {
                final recsData = recommendedAsync.value ?? Track.mockTracks;
                _showSeeAllTracksSheet(context, 'Recommended For You', recsData);
              },
            ),
            const SizedBox(height: 4),
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
      ),
    );
  }

  // Reusable "Title ---- See all" row so every section matches.
  Widget _buildSectionHeader(BuildContext context, String title, {VoidCallback? onSeeAll}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

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
                  color: customBranding.accentColor,
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
                  color: customBranding.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See All',
                      style: TextStyle(
                        color: customBranding.accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: customBranding.accentColor),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackList(List<Track> tracks) {
    final notifier = ref.read(playbackProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: List.generate(tracks.length, (index) {
        final track = tracks[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => notifier.playTrack(track),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
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
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_border_rounded, size: 20, color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),
          ),
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
                    color: (isDark ? const Color(0xFF1B1B1E) : Colors.white).withOpacity(0.92),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(isDark ? 0.08 : 0.6), width: 1),
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
                              color: activeColor.withOpacity(0.15),
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

                      // 1. Name Input
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

  // ---------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------
  Widget _buildHomeHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                        color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.55),
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
                          customBranding.accentColor,
                        ],
                      ).createShader(bounds),
                      child: Text(
                        customBranding.appName,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Branding icon presented as a soft glass badge instead of a
              // plain small icon floating next to text.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: customBranding.accentColor.withOpacity(0.14),
                  border: Border.all(color: customBranding.accentColor.withOpacity(0.25), width: 1),
                ),
                child: Icon(customBranding.brandingIcon, color: customBranding.accentColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildLanguageFilterChips(context),
          const SizedBox(height: 16),
          _buildSearchBar(context),
        ],
      ),
    );
  }

  Widget _buildLanguageFilterChips(BuildContext context) {
    final activeLangs = StorageService.getPreferredLanguages();
    final allLangs = ['Punjabi', 'Hindi', 'English', 'Bhangra', 'Bollywood', 'LoFi'];
    final customBranding = ref.watch(customizationProvider);

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: allLangs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final lang = allLangs[i];
          final isSelected = activeLangs.contains(lang);
          return GestureDetector(
            onTap: () async {
              List<String> updated = List.from(activeLangs);
              if (!isSelected) {
                updated = [lang];
              } else {
                updated.remove(lang);
              }
              await StorageService.savePreferredLanguages(updated);
              ref.invalidate(trendingTracksProvider);
              ref.invalidate(dynamicRecommendationsProvider);
              setState(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: isSelected
                    ? LinearGradient(colors: [
                        customBranding.accentColor,
                        customBranding.accentColor.withOpacity(0.7),
                      ])
                    : null,
                color: isSelected ? null : Colors.white12.withOpacity(0.06),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white24.withOpacity(0.15),
                ),
              ),
              child: Text(
                lang,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.grey.shade500,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Search Input UI
  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 50,
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
            color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.45),
            size: 22,
          ),
          suffixIcon: Icon(
            Icons.tune_rounded,
            color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.3),
            size: 18,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // TRACK RAIL
  // ---------------------------------------------------------------------
  Widget _buildTrackRail(BuildContext context, String title, List<Track> tracks, {bool large = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double artSize = large ? 132 : 116;
    final double cardWidth = large ? 142 : 126;
    final double railHeight = artSize + 68;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, title, onSeeAll: () => _showSeeAllTracksSheet(context, title, tracks)),
        SizedBox(
          height: railHeight,
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
                    onTap: () => notifier.playTrack(track),
                    child: Container(
                      width: cardWidth,
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: artSize,
                                height: artSize,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.45 : 0.18),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      AppArtworkImage(
                                        artworkUrl: track.artworkUrl,
                                        trackId: track.id,
                                        fit: BoxFit.cover,
                                      ),
                                      // Soft bottom scrim so a small play glyph
                                      // always reads clearly over any artwork.
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withOpacity(0.35),
                                            ],
                                            stops: const [0.6, 1.0],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 8,
                                        bottom: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withOpacity(0.85),
                                          ),
                                          child: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.black),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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

  // ---------------------------------------------------------------------
  // GENRES
  // ---------------------------------------------------------------------
  Widget _buildGenreSection(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final List<Map<String, dynamic>> genres = [
      {
        'name': 'Jazz & Calm',
        'icon': Icons.piano_rounded,
        'colors': [customBranding.accentColor, customBranding.accentColor.withOpacity(0.55)],
      },
      {
        'name': 'Retro Synth',
        'icon': Icons.graphic_eq_rounded,
        'colors': [const Color(0xFFE040FB), const Color(0xFF651FFF)],
      },
      {
        'name': 'Acoustic Study',
        'icon': Icons.music_note_rounded,
        'colors': [const Color(0xFF26A69A), const Color(0xFF00796B)],
      },
      {
        'name': 'Lo-Fi Chill',
        'icon': Icons.nightlight_round,
        'colors': [const Color(0xFF42A5F5), const Color(0xFF1565C0)],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Genres & Moods'),
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 24, right: 8),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              final colors = genre['colors'] as List<Color>;
              return Container(
                width: 152,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Faint oversized icon watermark in the corner adds
                    // texture instead of a flat gradient block.
                    Positioned(
                      right: -10,
                      bottom: -10,
                      child: Icon(
                        genre['icon'] as IconData,
                        size: 64,
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(genre['icon'] as IconData, color: Colors.white, size: 20),
                          Text(
                            genre['name'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Bottom Navigation Bar Widget - Supporting Default Floating Glass Capsule & OS Native Style (iOS Liquid Glass on iOS / Android 16 M3 on Android)
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