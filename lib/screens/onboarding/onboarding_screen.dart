import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/auth/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding
//
// Five steps, one job each:
//   0 Welcome → 1 Languages → 2 Genres → 3 Artists → 4 Permissions
//
// Layout is the same on every step: back / skip row, a segmented progress
// bar, the step body, then one full-width button with a status line above it.
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _PermissionState { notGranted, granted, blocked }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with WidgetsBindingObserver {
  static const int _stepCount = 5;
  static const int _lastStep = _stepCount - 1;

  int _onboardingStep = 0; // 0: Welcome, 1: Languages, 2: Genres, 3: Artists, 4: Permissions
  bool _movingForward = true;
  bool _finishing = false;

  final TextEditingController _artistSearchController = TextEditingController();
  String _artistSearchQuery = '';

  // ── Content ────────────────────────────────────────────────────────────────

  static const List<OnboardingSlideData> _features = [
    OnboardingSlideData(
      title: 'Free high-quality streaming',
      subtitle: 'Millions of songs with no subscription fees.',
      icon: Icons.graphic_eq_rounded,
    ),
    OnboardingSlideData(
      title: 'Offline downloads',
      subtitle: 'Save tracks and playlists and play them anywhere, without using data.',
      icon: Icons.download_done_rounded,
    ),
    OnboardingSlideData(
      title: 'Smart playlists & handoff',
      subtitle: 'AI queue suggestions, cross-device handoff, custom themes and sleep timers.',
      icon: Icons.auto_awesome_rounded,
    ),
  ];

  // `name` is what gets saved, so those values are unchanged.
  static const List<_Language> _languages = [
    _Language('English', 'English', 'A'),
    _Language('Hindi', 'हिंदी', 'हि'),
    _Language('Punjabi', 'ਪੰਜਾਬੀ', 'ਪੰ'),
    _Language('Tamil', 'தமிழ்', 'த'),
    _Language('Telugu', 'తెలుగు', 'తె'),
    _Language('Malayalam', 'മലയാളം', 'മ'),
    _Language('Kannada', 'ಕನ್ನಡ', 'ಕ'),
    _Language('Gujarati', 'ગુજરાતી', 'ગુ'),
    _Language('Marathi', 'मराठी', 'म'),
    _Language('Bengali', 'বাংলা', 'বা'),
    _Language('Urdu', 'اردو', 'ا'),
  ];
  final Set<String> _selectedLanguages = {'English', 'Hindi'};

  static const List<_Genre> _genres = [
    _Genre('Pop', Icons.star_rounded, Color(0xFFFF4081)),
    _Genre('Bollywood', Icons.movie_filter_rounded, Color(0xFFFF9100)),
    _Genre('Punjabi', Icons.audiotrack_rounded, Color(0xFFFFD600)),
    _Genre('Hip Hop', Icons.mic_external_on_rounded, Color(0xFF00E676)),
    _Genre('Rock', Icons.electric_bolt_rounded, Color(0xFFFF3D00)),
    _Genre('LoFi & Chill', Icons.headset_rounded, Color(0xFF7C4DFF)),
    _Genre('EDM & Party', Icons.nightlife_rounded, Color(0xFF00E5FF)),
    _Genre('Devotional', Icons.self_improvement_rounded, Color(0xFFFFAB00)),
    _Genre('Classical', Icons.piano_rounded, Color(0xFFA1887F)),
    _Genre('Romance', Icons.favorite_rounded, Color(0xFFE91E63)),
    _Genre('Jazz & Blues', Icons.queue_music_rounded, Color(0xFF3F51B5)),
    _Genre('Acoustic', Icons.music_note_rounded, Color(0xFF8BC34A)),
  ];
  final Set<String> _selectedGenres = {'Pop', 'Bollywood'};

  static const List<_Artist> _artists = [
    _Artist('Arijit Singh', 'Bollywood • Romance', 'AS'),
    _Artist('Karan Aujla', 'Punjabi • Hip Hop', 'KA'),
    _Artist('Diljit Dosanjh', 'Punjabi • Pop', 'DD'),
    _Artist('Taylor Swift', 'Pop • Country', 'TS'),
    _Artist('Drake', 'Hip Hop • Rap', 'DR'),
    _Artist('Shreya Ghoshal', 'Melodic • Bollywood', 'SG'),
    _Artist('Anirudh Ravichander', 'Tamil • EDM', 'AR'),
    _Artist('Sid Sriram', 'Telugu • Classical', 'SS'),
    _Artist('Pritam', 'Composer • Bollywood', 'PR'),
    _Artist('A.R. Rahman', 'Maestro • Fusion', 'ARR'),
    _Artist('Justin Bieber', 'Pop • R&B', 'JB'),
    _Artist('The Weeknd', 'Synthpop • R&B', 'TW'),
    _Artist('Billie Eilish', 'Alternative • Pop', 'BE'),
    _Artist('Badshah', 'Hip Hop • Party', 'BD'),
    _Artist('AP Dhillon', 'Punjabi • Wave', 'AP'),
    _Artist('Guru Randhawa', 'Dance • Pop', 'GR'),
    _Artist('Divine', 'Gully Rap • Hip Hop', 'DV'),
  ];
  final Set<String> _selectedArtists = {'Arijit Singh', 'Diljit Dosanjh'};

  // ── Permissions ────────────────────────────────────────────────────────────

  _PermissionState _notificationState = _PermissionState.notGranted;
  _PermissionState _storageState = _PermissionState.notGranted;
  bool _requestingPermission = false;

  /// Android 13+ replaced the storage permission with per-media ones, so
  /// `Permission.storage` alone is always refused there. Asking for both
  /// covers old and new Android; whichever applies decides the result.
  List<Permission> get _storagePermissions {
    return defaultTargetPlatform == TargetPlatform.android
        ? [Permission.storage, Permission.audio]
        : [Permission.storage];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _artistSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from system settings: pick up anything the user changed.
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
    }
  }

  /// Reads the current status without showing any system prompt.
  Future<void> _refreshPermissions() async {
    _PermissionState merge(_PermissionState current, List<PermissionStatus> statuses) {
      if (statuses.any(_isUsable)) return _PermissionState.granted;
      // Revoked while we were away.
      if (current == _PermissionState.granted) return _PermissionState.notGranted;
      return current;
    }

    try {
      final notification = [await Permission.notification.status];
      final storage = [
        for (final permission in _storagePermissions) await permission.status,
      ];
      if (!mounted) return;
      setState(() {
        _notificationState = merge(_notificationState, notification);
        _storageState = merge(_storageState, storage);
      });
    } catch (_) {
      // Only a pre-check so already-granted permissions show as allowed.
      // The Allow buttons still work if it is unavailable.
    }
  }

  static bool _isUsable(PermissionStatus status) => status.isGranted || status.isLimited;

  _PermissionState _stateAfterRequest(Iterable<PermissionStatus> statuses) {
    if (statuses.any(_isUsable)) return _PermissionState.granted;
    // The system will not show its prompt again; only settings can change it.
    if (statuses.any((status) => status.isPermanentlyDenied)) return _PermissionState.blocked;
    return _PermissionState.notGranted;
  }

  Future<void> _requestNotificationPermission() async {
    if (_requestingPermission) return;
    _requestingPermission = true;
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      setState(() {
        _notificationState = _stateAfterRequest([status]);
      });
    } finally {
      _requestingPermission = false;
    }
  }

  Future<void> _requestStoragePermission() async {
    if (_requestingPermission) return;
    _requestingPermission = true;
    try {
      final statuses = await _storagePermissions.request();
      if (!mounted) return;
      setState(() {
        _storageState = _stateAfterRequest(statuses.values);
      });
    } finally {
      _requestingPermission = false;
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _haptic() {
    if (StorageService.isHapticsEnabled()) {
      HapticFeedback.selectionClick();
    }
  }

  void _nextStep() {
    if (_finishing) return;
    if (_onboardingStep >= _lastStep) {
      _finishOnboarding();
      return;
    }
    _haptic();
    FocusScope.of(context).unfocus();
    setState(() {
      _movingForward = true;
      _onboardingStep++;
    });
  }

  void _prevStep() {
    if (_finishing || _onboardingStep == 0) return;
    _haptic();
    FocusScope.of(context).unfocus();
    setState(() {
      _movingForward = false;
      _onboardingStep--;
    });
  }

  Future<void> _finishOnboarding() async {
    if (_finishing) return; // ignore double taps
    setState(() {
      _finishing = true;
    });

    try {
      await StorageService.savePreferredLanguages(_selectedLanguages.toList());
      await StorageService.savePreferredGenres(_selectedGenres.toList());
      await StorageService.savePreferredArtists(_selectedArtists.toList());
      await StorageService.completeOnboarding();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your preferences. Please try again.')),
      );
      return;
    }

    if (mounted) {
      if (!AuthService.instance.isLoggedIn) {
        context.go('/login');
      } else {
        context.go('/home');
      }
    }
  }

  void _toggle(Set<String> selection, String name, {int minimum = 0}) {
    _haptic();
    setState(() {
      if (selection.contains(name)) {
        if (selection.length > minimum) selection.remove(name);
      } else {
        selection.add(name);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    return PopScope<Object?>(
      // System back walks back through the steps instead of leaving.
      canPop: _onboardingStep == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _prevStep();
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFFAF9F6),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Soft accent glow behind the top of the screen
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.25),
                    radius: 0.95,
                    colors: [
                      accentColor.withValues(alpha: isDark ? 0.20 : 0.16),
                      accentColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(accentColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: _ProgressSegments(
                      count: _stepCount,
                      current: _onboardingStep,
                      color: accentColor,
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      // New step slides in from the side you are heading to;
                      // the old one leaves the other way.
                      transitionBuilder: (child, animation) {
                        final isIncoming = child.key == ValueKey<int>(_onboardingStep);
                        final direction =
                            (_movingForward ? 1.0 : -1.0) * (isIncoming ? 1.0 : -1.0);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: Offset(0.06 * direction, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _buildStepBody(accentColor),
                    ),
                  ),
                  _buildFooter(accentColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _onboardingStep > 0
                  ? IconButton(
                      key: const ValueKey('back'),
                      tooltip: 'Back',
                      onPressed: _prevStep,
                      icon: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _tint(context, 0.07),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                      ),
                    )
                  : Padding(
                      key: const ValueKey('brand'),
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                    ),
            ),
            const Spacer(),
            // The last step's button already finishes, so Skip goes away there.
            if (_onboardingStep < _lastStep)
              TextButton(
                onPressed: _finishOnboarding,
                style: TextButton.styleFrom(foregroundColor: _muted(context)),
                child: const Text(
                  'Skip',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(Color accentColor) {
    final hint = _stepHint(_onboardingStep);
    final String label;
    if (_onboardingStep == _lastStep) {
      label = 'Start listening';
    } else if (_onboardingStep == 0) {
      label = 'Get started';
    } else {
      label = 'Continue';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              hint,
              key: ValueKey(hint),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: _muted(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _nextStep,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: _onColor(accentColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: _finishing
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _onColor(accentColor),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepHint(int step) {
    String counted(int count, String noun) => '$count $noun${count == 1 ? '' : 's'} selected';

    switch (step) {
      case 0:
        return 'Four quick steps to set up your music';
      case 1:
        return _selectedLanguages.length == 1
            ? '1 language selected · keep at least one'
            : counted(_selectedLanguages.length, 'language');
      case 2:
        return _selectedGenres.isEmpty
            ? 'Pick a few, or continue without any'
            : counted(_selectedGenres.length, 'genre');
      case 3:
        return _selectedArtists.isEmpty
            ? 'Pick a few, or continue without any'
            : counted(_selectedArtists.length, 'artist');
      case 4:
        return 'You can change these any time in system settings';
      default:
        return '';
    }
  }

  Widget _buildStepBody(Color accentColor) {
    switch (_onboardingStep) {
      case 0:
        return _buildWelcomeStep(accentColor);
      case 1:
        return _buildLanguagesStep(accentColor);
      case 2:
        return _buildGenresStep();
      case 3:
        return _buildArtistsStep(accentColor);
      case 4:
        return _buildPermissionsStep(accentColor);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── 0: Welcome ──────────────────────────────────────────────────────────────

  Widget _buildWelcomeStep(Color accentColor) {
    return _CenteredScroll(
      key: const ValueKey<int>(0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseHero(color: accentColor, icon: Icons.graphic_eq_rounded),
          const SizedBox(height: 20),
          const Text(
            'Welcome to Aura',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              fontFamily: 'Outfit',
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your music, your way. Here is what you get.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.45, color: _muted(context)),
          ),
          const SizedBox(height: 26),
          Container(
            decoration: BoxDecoration(
              color: _tint(context, 0.045),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _tint(context, 0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _features.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 70, color: _tint(context, 0.06)),
                  _buildFeatureRow(_features[i], accentColor),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(OnboardingSlideData feature, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(feature.icon, size: 22, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  feature.subtitle,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: _muted(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 1: Languages ────────────────────────────────────────────────────────────

  static const SliverGridDelegate _cardGrid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    mainAxisExtent: 110,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
  );

  /// Card grids have fixed-height cells, so cap how far system font scaling
  /// can stretch the text inside them.
  Widget _cardGridView({required int itemCount, required NullableIndexedWidgetBuilder itemBuilder}) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        gridDelegate: _cardGrid,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }

  Widget _buildLanguagesStep(Color accentColor) {
    return Padding(
      key: const ValueKey<int>(1),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Choose your languages',
            subtitle: 'Songs and stations are picked to match the languages you listen in.',
          ),
          Expanded(
            child: _cardGridView(
              itemCount: _languages.length,
              itemBuilder: (context, index) {
                final language = _languages[index];
                final isSelected = _selectedLanguages.contains(language.name);

                return _ChoiceCard(
                  title: language.name,
                  subtitle: language.native == language.name ? null : language.native,
                  selected: isSelected,
                  color: accentColor,
                  badge: _ChoiceBadge(
                    selected: isSelected,
                    color: accentColor,
                    glyph: language.glyph,
                  ),
                  onTap: () => _toggle(_selectedLanguages, language.name, minimum: 1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 2: Genres ───────────────────────────────────────────────────────────────

  Widget _buildGenresStep() {
    return Padding(
      key: const ValueKey<int>(2),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Pick your genres',
            subtitle: 'These shape your recommendations and your home feed.',
          ),
          Expanded(
            child: _cardGridView(
              itemCount: _genres.length,
              itemBuilder: (context, index) {
                final genre = _genres[index];
                final isSelected = _selectedGenres.contains(genre.name);

                return _ChoiceCard(
                  title: genre.name,
                  selected: isSelected,
                  color: genre.color,
                  badge: _ChoiceBadge(
                    selected: isSelected,
                    color: genre.color,
                    icon: genre.icon,
                    tinted: true,
                  ),
                  onTap: () => _toggle(_selectedGenres, genre.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 3: Artists ──────────────────────────────────────────────────────────────

  Widget _buildArtistsStep(Color accentColor) {
    final query = _artistSearchQuery.trim().toLowerCase();
    final filteredArtists = _artists.where((artist) {
      return artist.name.toLowerCase().contains(query) ||
          artist.genre.toLowerCase().contains(query);
    }).toList();

    return Padding(
      key: const ValueKey<int>(3),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            title: 'Pick your favorite artists',
            subtitle: 'You get quick-access tiles and artist radio stations for them.',
          ),
          TextField(
            controller: _artistSearchController,
            textInputAction: TextInputAction.search,
            onChanged: (val) {
              setState(() {
                _artistSearchQuery = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search by artist or genre',
              hintStyle: TextStyle(fontSize: 14, color: _muted(context)),
              prefixIcon: Icon(Icons.search_rounded, size: 21, color: _muted(context)),
              suffixIcon: _artistSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: Icon(Icons.close_rounded, size: 19, color: _muted(context)),
                      onPressed: () {
                        _artistSearchController.clear();
                        setState(() {
                          _artistSearchQuery = '';
                        });
                      },
                    ),
              filled: true,
              fillColor: _tint(context, 0.055),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredArtists.isEmpty
                ? _buildNoArtistsFound()
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: [
                          for (final artist in filteredArtists)
                            _ArtistChip(
                              name: artist.name,
                              initials: artist.tag,
                              selected: _selectedArtists.contains(artist.name),
                              accent: accentColor,
                              onTap: () => _toggle(_selectedArtists, artist.name),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoArtistsFound() {
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 36, color: _tint(context, 0.3)),
          const SizedBox(height: 10),
          Text(
            'No artists match "${_artistSearchQuery.trim()}"',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'You can find anyone later from search.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: _muted(context)),
          ),
        ],
      ),
    );
  }

  // ── 4: Permissions ──────────────────────────────────────────────────────────

  Widget _buildPermissionsStep(Color accentColor) {
    return _CenteredScroll(
      key: const ValueKey<int>(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_rounded, size: 40, color: accentColor),
          ),
          const SizedBox(height: 20),
          const Text(
            'Two quick permissions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              fontFamily: 'Outfit',
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Notifications give you lock-screen controls, and storage lets you download music for offline listening.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: _muted(context)),
          ),
          const SizedBox(height: 28),
          _PermissionTile(
            icon: Icons.notifications_active_rounded,
            title: 'Playback notifications',
            subtitle: 'Player controls in the notification bar and on the lock screen.',
            state: _notificationState,
            accent: accentColor,
            onRequest: _requestNotificationPermission,
          ),
          const SizedBox(height: 12),
          _PermissionTile(
            icon: Icons.folder_rounded,
            title: 'Storage & media',
            subtitle: 'Caches artwork and saves tracks for offline listening.',
            state: _storageState,
            accent: accentColor,
            onRequest: _requestStoragePermission,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA
// ═════════════════════════════════════════════════════════════════════════════

/// One feature shown on the welcome step.
class OnboardingSlideData {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;

  const OnboardingSlideData({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge = '',
  });
}

class _Language {
  const _Language(this.name, this.native, this.glyph);

  final String name;
  final String native;

  /// A letter in the language's own script, shown on its card.
  final String glyph;
}

class _Genre {
  const _Genre(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

class _Artist {
  const _Artist(this.name, this.genre, this.tag);

  final String name;
  final String genre;
  final String tag;
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED PIECES
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

/// Instagram-stories style progress: one bar per step.
class _ProgressSegments extends StatelessWidget {
  const _ProgressSegments({required this.count, required this.current, required this.color});

  final int count;
  final int current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? color : _tint(context, 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              fontFamily: 'Outfit',
              letterSpacing: -0.3,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: _muted(context)),
          ),
        ],
      ),
    );
  }
}

/// Centers its child when there is room and scrolls when there isn't, so the
/// step never overflows on small screens or with large text.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - 32),
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// The leading tile on a choice card: an icon or a script letter.
class _ChoiceBadge extends StatelessWidget {
  const _ChoiceBadge({
    required this.selected,
    required this.color,
    this.icon,
    this.glyph,
    this.tinted = false,
  });

  final bool selected;
  final Color color;
  final IconData? icon;
  final String? glyph;

  /// Show a wash of [color] even when not selected (used for genres).
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? _onColor(color)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85);
    final Color background;
    if (selected) {
      background = color;
    } else if (tinted) {
      background = color.withValues(alpha: 0.18);
    } else {
      background = _tint(context, 0.07);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: icon != null
          ? Icon(icon, size: 22, color: foreground)
          : Text(
              glyph ?? '',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: foreground,
              ),
            ),
    );
  }
}

/// A selectable card used for languages and genres.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.badge,
    required this.title,
    required this.selected,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  final Widget badge;
  final String title;
  final String? subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : _tint(context, 0.045),
          borderRadius: radius,
          border: Border.all(
            color: selected ? color : _tint(context, 0.07),
            width: 1.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        badge,
                        const SizedBox(height: 8),
                        Text(
                          title,
                          maxLines: subtitle == null ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, height: 1.2, color: _muted(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 7,
                  right: 7,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, size: 13, color: _onColor(color)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill for one artist. The avatar turns into a check mark when selected,
/// so the pill keeps its width and the layout never jumps.
class _ArtistChip extends StatelessWidget {
  const _ArtistChip({
    required this.name,
    required this.initials,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String name;
  final String initials;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  /// A stable hue per artist so the avatars are not all one color.
  double get _hue {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash % 360).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarBackground =
        HSLColor.fromAHSL(1, _hue, isDark ? 0.42 : 0.62, isDark ? 0.30 : 0.86).toColor();
    final avatarForeground =
        HSLColor.fromAHSL(1, _hue, isDark ? 0.75 : 0.55, isDark ? 0.86 : 0.30).toColor();
    final radius = BorderRadius.circular(100);

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : _tint(context, 0.05),
          borderRadius: radius,
          border: Border.all(
            color: selected ? accent : _tint(context, 0.08),
            width: 1.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? accent : avatarBackground,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: selected
                          ? Icon(
                              Icons.check_rounded,
                              key: const ValueKey('check'),
                              size: 18,
                              color: _onColor(accent),
                            )
                          : Text(
                              initials,
                              key: const ValueKey('initials'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: avatarForeground,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.accent,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _PermissionState state;
  final Color accent;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    final isGranted = state == _PermissionState.granted;
    final isBlocked = state == _PermissionState.blocked;

    final Widget action;
    if (isGranted) {
      action = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: green),
            const SizedBox(width: 5),
            Text(
              'Allowed',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: green),
            ),
          ],
        ),
      );
    } else if (isBlocked) {
      action = OutlinedButton(
        onPressed: openAppSettings,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          side: BorderSide(color: _tint(context, 0.2)),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: const Text('Settings'),
      );
    } else {
      action = FilledButton(
        onPressed: onRequest,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _onColor(accent),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: const Text('Allow'),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _tint(context, 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGranted ? green.withValues(alpha: 0.5) : _tint(context, 0.06),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  isBlocked ? 'Turned off for this app. Switch it on in system settings.' : subtitle,
                  style: TextStyle(fontSize: 12, height: 1.35, color: _muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

/// The welcome artwork: an accent disc with slow rings pulsing outward.
class _PulseHero extends StatefulWidget {
  const _PulseHero({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  State<_PulseHero> createState() => _PulseHeroState();
}

class _PulseHeroState extends State<_PulseHero> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold still when the system asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.35;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: CustomPaint(
        painter: _PulseRingsPainter(progress: _controller, color: widget.color),
        child: Center(
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(widget.icon, size: 38, color: _onColor(widget.color)),
          ),
        ),
      ),
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  _PulseRingsPainter({required this.progress, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  static const int _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;
    const minRadius = 39.0; // edge of the center disc

    for (var i = 0; i < _rings; i++) {
      final t = (progress.value + i / _rings) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.38 * (1 - t));
      canvas.drawCircle(center, minRadius + (maxRadius - minRadius) * t, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingsPainter oldDelegate) => oldDelegate.color != color;
}