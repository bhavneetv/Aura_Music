import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../themes/app_theme.dart';
import '../../services/storage/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _onboardingStep = 0; // 0: Slides, 1: Languages, 2: Genres, 3: Artists, 4: Permissions
  
  // Slide Carousel State
  final PageController _pageController = PageController();
  int _currentSlide = 0;

  final List<OnboardingSlideData> _slides = [
    OnboardingSlideData(
      title: 'Stream Free Music',
      subtitle: 'Access millions of songs from our high-speed, dynamic server networks with no sign-ups or subscription fees.',
      icon: Icons.music_note_rounded,
    ),
    OnboardingSlideData(
      title: 'Offline Library',
      subtitle: 'Download songs directly to your device and stream offline, saving data and battery on-the-go.',
      icon: Icons.download_done_rounded,
    ),
    OnboardingSlideData(
      title: 'Apple & Spotify Styled',
      subtitle: 'Enjoy premium features like smart queues, custom playlists, recently played trackers, and sleep timers.',
      icon: Icons.album_rounded,
    ),
  ];

  // Selection States
  final List<String> _languages = [
    'English', 'Hindi', 'Punjabi', 'Tamil', 'Telugu', 'Malayalam', 
    'Kannada', 'Gujarati', 'Marathi', 'Bengali', 'Urdu', 'Spanish', 
    'French', 'Japanese', 'Korean'
  ];
  final Set<String> _selectedLanguages = {'English', 'Hindi'};

  final List<String> _genres = [
    'Pop', 'Rock', 'Hip Hop', 'Classical', 'LoFi', 'Electronic', 'EDM', 
    'Bollywood', 'Punjabi', 'Devotional', 'Jazz', 'Instrumental', 
    'Country', 'Folk', 'Podcast'
  ];
  final Set<String> _selectedGenres = {};

  final List<String> _artists = [
    'Arijit Singh', 'Karan Aujla', 'Diljit Dosanjh', 'Taylor Swift', 
    'Drake', 'Shreya Ghoshal', 'Anirudh Ravichander', 'Sid Sriram', 
    'Pritam', 'A.R. Rahman', 'Justin Bieber', 'The Weeknd', 'Billie Eilish'
  ];
  final Set<String> _selectedArtists = {};

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
    // Save to Hive
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
    // Request storage or media permissions depending on Android version
    final status = await Permission.storage.request();
    setState(() {
      _storageGranted = status.isGranted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Step indicator or Back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_onboardingStep > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      onPressed: _prevStep,
                    )
                  else
                    Text(
                      'AURA',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: AppTheme.goldAccent,
                          ),
                    ),
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Skip All',
                      style: TextStyle(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Step Body
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _buildStepBody(isDark),
              ),
            ),

            // Bottom Navigation Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators (only for steps)
                  Text(
                    'Step ${_onboardingStep + 1} of 5',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),

                  // Next Button
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
                      backgroundColor: AppTheme.goldAccent,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Text(
                      _onboardingStep == 4 
                          ? 'Finish' 
                          : (_onboardingStep == 0 && _currentSlide < _slides.length - 1 ? 'Next' : 'Continue'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
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

  Widget _buildStepBody(bool isDark) {
    switch (_onboardingStep) {
      case 0:
        return _buildSlidesStep(isDark);
      case 1:
        return _buildLanguagesStep(isDark);
      case 2:
        return _buildGenresStep(isDark);
      case 3:
        return _buildArtistsStep(isDark);
      case 4:
        return _buildPermissionsStep(isDark);
      default:
        return Container();
    }
  }

  // ── 0: Slides Step ──────────────────────────────────────────

  Widget _buildSlidesStep(bool isDark) {
    return Column(
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
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 130,
                      height: 130,
                      decoration: AppTheme.glassDecoration(
                        context: context,
                        opacity: isDark ? 0.05 : 0.04,
                        radius: 65,
                      ),
                      child: Center(
                        child: Icon(
                          slide.icon,
                          size: 56,
                          color: AppTheme.goldAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      slide.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.grey),
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
              width: isSelected ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: isSelected ? AppTheme.goldAccent : (isDark ? Colors.white24 : Colors.black12),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── 1: Languages Step ───────────────────────────────────────

  Widget _buildLanguagesStep(bool isDark) {
    return _buildSelectionGrid(
      title: 'Choose Languages',
      subtitle: 'We will recommend songs and playlists matching these preferences.',
      items: _languages,
      selectedItems: _selectedLanguages,
      isDark: isDark,
    );
  }

  // ── 2: Genres Step ──────────────────────────────────────────

  Widget _buildGenresStep(bool isDark) {
    return _buildSelectionGrid(
      title: 'Favorite Genres',
      subtitle: 'Pick genres you enjoy listening to.',
      items: _genres,
      selectedItems: _selectedGenres,
      isDark: isDark,
    );
  }

  // ── 3: Artists Step ─────────────────────────────────────────

  Widget _buildArtistsStep(bool isDark) {
    return _buildSelectionGrid(
      title: 'Favorite Artists',
      subtitle: 'Select artists you want recommendations for.',
      items: _artists,
      selectedItems: _selectedArtists,
      isDark: isDark,
    );
  }

  Widget _buildSelectionGrid({
    required String title,
    required String subtitle,
    required List<String> items,
    required Set<String> selectedItems,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items.map((item) {
                  final isSelected = selectedItems.contains(item);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          selectedItems.remove(item);
                        } else {
                          selectedItems.add(item);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? AppTheme.goldAccent.withOpacity(0.18) 
                            : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
                        border: Border.all(
                          color: isSelected ? AppTheme.goldAccent : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          color: isSelected ? AppTheme.goldAccent : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4: Permissions Step ─────────────────────────────────────

  Widget _buildPermissionsStep(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.security_rounded, size: 64, color: AppTheme.goldAccent),
          const SizedBox(height: 24),
          const Text(
            'Permissions Needed',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Aura needs notification permissions for audio widgets, and storage permissions for offline caching.',
            style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          
          // Notifications Row
          _buildPermissionTile(
            title: 'Notifications',
            subtitle: 'Enables lock-screen widgets & active playback bars.',
            isGranted: _notificationGranted,
            onRequest: _requestNotificationPermission,
          ),
          const SizedBox(height: 16),
          
          // Storage Row
          _buildPermissionTile(
            title: 'Storage / Library',
            subtitle: 'Allows downloading songs for offline playback.',
            isGranted: _storageGranted,
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
    required VoidCallback onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassDecoration(
        context: context,
        opacity: 0.05,
        radius: 16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isGranted ? null : onRequest,
            style: ElevatedButton.styleFrom(
              backgroundColor: isGranted ? Colors.green.withOpacity(0.2) : AppTheme.goldAccent,
              foregroundColor: isGranted ? Colors.green : Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              isGranted ? 'Granted' : 'Grant',
              style: const TextStyle(fontWeight: FontWeight.bold),
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

  OnboardingSlideData({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
