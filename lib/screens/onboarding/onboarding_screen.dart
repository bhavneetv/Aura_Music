import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../themes/app_theme.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _onboardingStep = 0; // 0: Slides, 1: Languages, 2: Genres, 3: Artists, 4: Permissions
  
  final PageController _pageController = PageController();
  int _currentSlide = 0;
  String _artistSearchQuery = '';

  final List<OnboardingSlideData> _slides = [
    OnboardingSlideData(
      title: 'Stream Free High-Quality Audio 🎧',
      subtitle: 'Access millions of songs from ultra-fast server networks with zero sign-ups or subscription fees.',
      icon: Icons.graphic_eq_rounded,
      badge: 'UNLIMITED STREAMING',
    ),
    OnboardingSlideData(
      title: 'Seamless Offline Downloads ⚡',
      subtitle: 'Download your favorite tracks & playlists directly to local storage to enjoy anywhere without data usage.',
      icon: Icons.download_done_rounded,
      badge: 'OFFLINE MODE',
    ),
    OnboardingSlideData(
      title: 'AI Smart Playlists & Handoff 🪄',
      subtitle: 'Experience smart queue recommendations, cross-device playback handoff, custom themes, and sleep timers.',
      icon: Icons.auto_awesome_rounded,
      badge: 'POWERFUL AI',
    ),
  ];

  // Enhanced Languages with Native Display Names
  final List<Map<String, String>> _languages = [
    {'name': 'English', 'native': 'English', 'flag': '🌐'},
    {'name': 'Hindi', 'native': 'हिंदी', 'flag': '🇮🇳'},
    {'name': 'Punjabi', 'native': 'ਪੰਜਾਬੀ', 'flag': '🪘'},
    {'name': 'Tamil', 'native': 'தமிழ்', 'flag': '🌴'},
    {'name': 'Telugu', 'native': 'తెలుగు', 'flag': '🏛️'},
    {'name': 'Malayalam', 'native': 'മലയാളം', 'flag': '🛶'},
    {'name': 'Kannada', 'native': 'ಕನ್ನಡ', 'flag': '🏰'},
    {'name': 'Gujarati', 'native': 'ગુજરાતી', 'flag': '🪁'},
    {'name': 'Marathi', 'native': 'मराठी', 'flag': '🚩'},
    {'name': 'Bengali', 'native': 'বাংলা', 'flag': '🐯'},
    {'name': 'Urdu', 'native': 'اردو', 'flag': '🌙'},

  ];
  final Set<String> _selectedLanguages = {'English', 'Hindi'};

  // Enhanced Genres with Icon Badges
  final List<Map<String, dynamic>> _genres = [
    {'name': 'Pop', 'icon': Icons.favorite_rounded, 'color': const Color(0xFFFF4081)},
    {'name': 'Bollywood', 'icon': Icons.movie_filter_rounded, 'color': const Color(0xFFFF9100)},
    {'name': 'Punjabi', 'icon': Icons.audiotrack_rounded, 'color': const Color(0xFFFFD600)},
    {'name': 'Hip Hop', 'icon': Icons.mic_external_on_rounded, 'color': const Color(0xFF00E676)},
    {'name': 'Rock', 'icon': Icons.electric_bolt_rounded, 'color': const Color(0xFFFF3D00)},
    {'name': 'LoFi & Chill', 'icon': Icons.headset_rounded, 'color': const Color(0xFF7C4DFF)},
    {'name': 'EDM & Party', 'icon': Icons.nightlife_rounded, 'color': const Color(0xFF00E5FF)},
    {'name': 'Devotional', 'icon': Icons.self_improvement_rounded, 'color': const Color(0xFFFFAB00)},
    {'name': 'Classical', 'icon': Icons.piano_rounded, 'color': const Color(0xFFA1887F)},
    {'name': 'Romance', 'icon': Icons.heart_broken_rounded, 'color': const Color(0xFFE91E63)},
    {'name': 'Jazz & Blues', 'icon': Icons.queue_music_rounded, 'color': const Color(0xFF3F51B5)},
    {'name': 'Acoustic', 'icon': Icons.music_note_rounded, 'color': const Color(0xFF8BC34A)},
  ];
  final Set<String> _selectedGenres = {'Pop', 'Bollywood'};

  // Enhanced Singers & Artists List
  final List<Map<String, String>> _artists = [
    {'name': 'Arijit Singh', 'genre': 'Bollywood • Romance', 'tag': 'AS'},
    {'name': 'Karan Aujla', 'genre': 'Punjabi • Hip Hop', 'tag': 'KA'},
    {'name': 'Diljit Dosanjh', 'genre': 'Punjabi • Pop', 'tag': 'DD'},
    {'name': 'Taylor Swift', 'genre': 'Pop • Country', 'tag': 'TS'},
    {'name': 'Drake', 'genre': 'Hip Hop • Rap', 'tag': 'DR'},
    {'name': 'Shreya Ghoshal', 'genre': 'Melodic • Bollywood', 'tag': 'SG'},
    {'name': 'Anirudh Ravichander', 'genre': 'Tamil • EDM', 'tag': 'AR'},
    {'name': 'Sid Sriram', 'genre': 'Telugu • Classical', 'tag': 'SS'},
    {'name': 'Pritam', 'genre': 'Composer • Bollywood', 'tag': 'PR'},
    {'name': 'A.R. Rahman', 'genre': 'Maestro • Fusion', 'tag': 'ARR'},
    {'name': 'Justin Bieber', 'genre': 'Pop • R&B', 'tag': 'JB'},
    {'name': 'The Weeknd', 'genre': 'Synthpop • R&B', 'tag': 'TW'},
    {'name': 'Billie Eilish', 'genre': 'Alternative • Pop', 'tag': 'BE'},
    {'name': 'Badshah', 'genre': 'Hip Hop • Party', 'tag': 'BD'},
    {'name': 'AP Dhillon', 'genre': 'Punjabi • Wave', 'tag': 'AP'},
    {'name': 'Guru Randhawa', 'genre': 'Dance • Pop', 'tag': 'GR'},
    {'name': 'Divine', 'genre': 'Gully Rap • Hip Hop', 'tag': 'DV'},
  ];
  final Set<String> _selectedArtists = {'Arijit Singh', 'Diljit Dosanjh'};

  // Permissions State
  bool _notificationGranted = false;
  bool _storageGranted = false;

  void _nextStep() {
    setState(() {
      if (_onboardingStep < 4) {
        _onboardingStep++;
      } else {
        _finishOnboarding();
      }
    });
  }

  void _prevStep() {
    if (_onboardingStep > 0) {
      setState(() {
        _onboardingStep--;
      });
    }
  }

  void _finishOnboarding() async {
    await StorageService.savePreferredLanguages(_selectedLanguages.toList());
    await StorageService.savePreferredGenres(_selectedGenres.toList());
    await StorageService.savePreferredArtists(_selectedArtists.toList());
    await StorageService.completeOnboarding();
    
    if (mounted) {
      context.go('/home');
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    setState(() {
      _notificationGranted = status.isGranted;
    });
  }

  Future<void> _requestStoragePermission() async {
    final status = await Permission.storage.request();
    setState(() {
      _storageGranted = status.isGranted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFFAF9F6),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Bar & Stepper Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_onboardingStep > 0)
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                      ),
                      onPressed: _prevStep,
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: accentColor, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'AURA',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: accentColor,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ],
                    ),

                  // Progress Step Caps
                  Row(
                    children: List.generate(5, (index) {
                      final isActive = index <= _onboardingStep;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: index == _onboardingStep ? 24 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? accentColor : (isDark ? Colors.white24 : Colors.black12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Skip All',
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Animated Body Content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _buildStepBody(isDark, accentColor),
              ),
            ),

            // 3. Bottom Action Footer Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141418) : Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'STEP ${_onboardingStep + 1} OF 5',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getStepTitleHint(_onboardingStep),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),

                  ElevatedButton(
                    onPressed: () {
                      if (_onboardingStep == 0 && _currentSlide < _slides.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _nextStep();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _onboardingStep == 4 
                              ? 'Get Started 🚀' 
                              : (_onboardingStep == 0 && _currentSlide < _slides.length - 1 ? 'Next' : 'Continue'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStepTitleHint(int step) {
    switch (step) {
      case 0:
        return 'Features Overview';
      case 1:
        return '${_selectedLanguages.length} Languages Selected';
      case 2:
        return '${_selectedGenres.length} Genres Selected';
      case 3:
        return '${_selectedArtists.length} Artists Picked';
      case 4:
        return 'App Permissions';
      default:
        return '';
    }
  }

  Widget _buildStepBody(bool isDark, Color accentColor) {
    switch (_onboardingStep) {
      case 0:
        return _buildSlidesStep(isDark, accentColor);
      case 1:
        return _buildLanguagesStep(isDark, accentColor);
      case 2:
        return _buildGenresStep(isDark, accentColor);
      case 3:
        return _buildArtistsStep(isDark, accentColor);
      case 4:
        return _buildPermissionsStep(isDark, accentColor);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 0: Feature Carousel Step ──────────────────────────

  Widget _buildSlidesStep(bool isDark, Color accentColor) {
    return Column(
      key: const ValueKey('step_0_slides'),
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (index) {
              setState(() {
                _currentSlide = index;
              });
            },
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [accentColor.withValues(alpha: 0.3), accentColor.withValues(alpha: 0.05)],
                          radius: 0.8,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 2),
                      ),
                      child: Center(
                        child: Icon(
                          slide.icon,
                          size: 64,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        slide.badge,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: accentColor, letterSpacing: 1.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 1.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (index) {
            final isSelected = _currentSlide == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 6),
              width: isSelected ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: isSelected ? accentColor : (isDark ? Colors.white24 : Colors.black12),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── 1: Languages Selection Step ───────────────────────

  Widget _buildLanguagesStep(bool isDark, Color accentColor) {
    return Padding(
      key: const ValueKey('step_1_languages'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text('Select Your Languages 🌐', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
          const SizedBox(height: 6),
          const Text('We will curate songs & personalized station recommendations matching these languages.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _languages.length,
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final name = lang['name']!;
                final native = lang['native']!;
                final flag = lang['flag']!;
                final isSelected = _selectedLanguages.contains(name);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        if (_selectedLanguages.length > 1) _selectedLanguages.remove(name);
                      } else {
                        _selectedLanguages.add(name);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? accentColor.withValues(alpha: 0.18) 
                          : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                      border: Border.all(
                        color: isSelected ? accentColor : Colors.transparent,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Text(flag, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isSelected ? accentColor : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                              Text(
                                native,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: accentColor, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 2: Favorite Genres Step ───────────────────────────

  Widget _buildGenresStep(bool isDark, Color accentColor) {
    return Padding(
      key: const ValueKey('step_2_genres'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text('Pick Favorite Genres 🎧', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
          const SizedBox(height: 6),
          const Text('Select music genres to customize your smart AI recommendations & home feed.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _genres.length,
              itemBuilder: (context, index) {
                final genre = _genres[index];
                final String name = genre['name'];
                final IconData icon = genre['icon'];
                final Color themeColor = genre['color'];
                final isSelected = _selectedGenres.contains(name);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedGenres.remove(name);
                      } else {
                        _selectedGenres.add(name);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isSelected
                            ? [themeColor.withValues(alpha: 0.3), themeColor.withValues(alpha: 0.1)]
                            : (isDark
                                ? [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.02)]
                                : [Colors.black.withValues(alpha: 0.04), Colors.black.withValues(alpha: 0.02)]),
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? themeColor : Colors.transparent,
                        width: 1.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 20, color: isSelected ? themeColor : (isDark ? Colors.white70 : Colors.black87)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSelected ? themeColor : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: themeColor, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 3: Favorite Singers / Artists Step ────────────────

  Widget _buildArtistsStep(bool isDark, Color accentColor) {
    final filteredArtists = _artists.where((artist) {
      final name = artist['name']!.toLowerCase();
      final genre = artist['genre']!.toLowerCase();
      final query = _artistSearchQuery.toLowerCase();
      return name.contains(query) || genre.contains(query);
    }).toList();

    return Padding(
      key: const ValueKey('step_3_artists'),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text('Pick Favorite Singers 🎤', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit')),
          const SizedBox(height: 6),
          const Text('Choose artists to get instant quick-access tiles & artist radio stations.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 14),

          // Artist Search Input
          TextField(
            onChanged: (val) {
              setState(() {
                _artistSearchQuery = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search singers (e.g. Arijit, Diljit, Taylor)...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),

          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: filteredArtists.length,
              itemBuilder: (context, index) {
                final artist = filteredArtists[index];
                final name = artist['name']!;
                final genre = artist['genre']!;
                final tag = artist['tag']!;
                final isSelected = _selectedArtists.contains(name);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? accentColor.withValues(alpha: 0.15) 
                        : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? accentColor : Colors.transparent),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: CircleAvatar(
                      backgroundColor: accentColor.withValues(alpha: 0.2),
                      child: Text(
                        tag,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: accentColor),
                      ),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(genre, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: accentColor,
                      checkColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedArtists.add(name);
                          } else {
                            _selectedArtists.remove(name);
                          }
                        });
                      },
                    ),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedArtists.remove(name);
                        } else {
                          _selectedArtists.add(name);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 4: Permissions Step ─────────────────────────────

  Widget _buildPermissionsStep(bool isDark, Color accentColor) {
    return Padding(
      key: const ValueKey('step_4_permissions'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_rounded, size: 56, color: accentColor),
          ),
          const SizedBox(height: 20),
          const Text(
            'Permissions & Readiness',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'Outfit'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Grant notification permissions for lock-screen controls and storage permissions to download offline music.',
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          _buildPermissionTile(
            title: 'Playback Notifications',
            subtitle: 'Enables media notification bar & lock-screen widgets.',
            isGranted: _notificationGranted,
            accentColor: accentColor,
            isDark: isDark,
            onRequest: _requestNotificationPermission,
          ),
          const SizedBox(height: 12),
          
          _buildPermissionTile(
            title: 'Storage / Media Access',
            subtitle: 'Allows caching artwork & downloading offline tracks.',
            isGranted: _storageGranted,
            accentColor: accentColor,
            isDark: isDark,
            onRequest: _requestStoragePermission,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool isGranted,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isGranted ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isGranted ? null : onRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: isGranted ? Colors.greenAccent.withValues(alpha: 0.2) : accentColor,
              foregroundColor: isGranted ? Colors.greenAccent : Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isGranted ? 'Granted ✓' : 'Grant',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingSlideData {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;

  OnboardingSlideData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
  });
}
