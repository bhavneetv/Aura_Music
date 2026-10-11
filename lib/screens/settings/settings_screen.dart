import 'dart:io' show Platform;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/settings_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/audio/spatial_audio_service.dart';
import '../equalizer/equalizer_screen.dart';
import '../../services/update/update_service.dart';
import '../../services/version/version_service.dart';
import '../../models/source_mode.dart';
import '../../providers/music_source_mode_provider.dart';
import 'widgets/firebase_settings_widgets.dart';
import 'widgets/storage_usage_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Settings screen
//
// Layout (top to bottom):
//   Header → Branding card → Account → Listening stats → Appearance →
//   Playback → Sound → Downloads & offline → General → Storage → About
//
// Every group is a rounded card of rows. Every picker is a bottom sheet built
// from the same pieces (_SheetFrame + _OptionTile), so the whole page behaves
// the same way wherever you tap.
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _offlineOnly = false;
  String _audioQuality = 'HQ Stream (256kbps)';
  bool _crossfadeEnabled = false;
  double _crossfadeDuration = 5.0;
  bool _hapticsEnabled = true;
  String _progressBarStyle = 'normal';
  String _summaryLanguage = 'en';
  bool _is3dSoundEnabled = false;
  String _3dSoundMode = 'Wide Room';
  double _3dSoundIntensity = 0.65;

  // ── Option catalogues (single source for row labels + picker sheets) ──────

  static const List<_Option<String>> _skinOptions = [
    _Option('vinyl', 'Rotating Vinyl Disc'),
    _Option('cd', 'Modern Compact CD'),
    _Option('cassette', 'Classic Cassette Tape'),
    _Option('neon', 'Neon Cyberpunk Disc'),
    _Option('amber', 'Glassmorphic Amber Glow'),
    _Option('minimal', 'Ultra Minimal Artwork'),
  ];

  static const List<_Option<String>> _screenThemeOptions = [
    _Option('normal', 'Normal (Classic)',
        description: 'Full player with top centered title & controls'),
    _Option('android_11_theme', 'Android 11',
        description: 'Classic Android 11 media card layout with circle knob'),
    _Option('android_16_theme', 'Android 16',
        description: 'Minimalist layout with uppercase top title & dynamic palette'),
    _Option('apple_music_theme', 'Apple Music',
        description: 'Full-screen blurred backdrop with sleek glass cards'),
    _Option('minimal_theme', 'Minimal',
        description: 'Clean gradient layout with circular artwork & ring progress'),
  ];

  static const List<_Option<String>> _navBarOptions = [
    _Option('os_style', 'OS Native Style',
        description: 'iOS 26 Liquid Glass on iOS / Android 16 Material 3 on Android',
        icon: Icons.smartphone_rounded),
    _Option('default', 'Floating Glass Capsule',
        description: 'Custom sleek floating curved glass bar',
        icon: Icons.auto_awesome_rounded),
  ];

  static const List<_Option<String>> _progressBarOptions = [
    _Option('waveform', 'Waveform', description: 'Voice note style'),
    _Option('android16', 'Android 16 Wave', description: 'Stock squiggly'),
    _Option('normal', 'Normal', description: 'Material rounded'),
    _Option('snake', 'Snake', description: 'Wavy sine wave'),
    _Option('zigzag', 'Zigzag', description: 'Sawtooth wave'),
    _Option('neon', 'Neon Glow', description: 'Pulse shader'),
  ];

  static const List<_Option<double>> _speedOptions = [
    _Option(0.5, '0.5x'),
    _Option(0.75, '0.75x'),
    _Option(1.0, '1.0x', description: 'Normal'),
    _Option(1.25, '1.25x'),
    _Option(1.5, '1.5x'),
    _Option(2.0, '2.0x'),
  ];

  // 0 means "off".
  static const List<_Option<int>> _sleepTimerOptions = [
    _Option(5, '5 minutes'),
    _Option(15, '15 minutes'),
    _Option(30, '30 minutes'),
    _Option(60, '60 minutes'),
    _Option(0, 'Off', description: 'Cancel the running timer'),
  ];

  static const List<_Option<String>> _qualityOptions = [
    _Option('Eco Stream (96kbps)', 'Eco Stream', description: '96 kbps · saves data'),
    _Option('Standard (160kbps)', 'Standard', description: '160 kbps · balanced'),
    _Option('HQ Stream (320kbps)', 'HQ Stream', description: '320 kbps · best quality'),
  ];

  static const List<_Option<String>> _languageOptions = [
    _Option('en', 'English 🌐', description: 'Full English story & lyric analysis'),
    _Option('hi', 'Hindi (हिंदी) 🇮🇳', description: 'Pure Devanagari Hindi story & analysis'),
    _Option('hinglish', 'Hinglish (Hindi + English) 🔤',
        description: 'Casual Hindi written in English script'),
  ];

  static const List<_Option<int>> _brandIconOptions = [
    _Option(0xe056, 'Vinyl', icon: Icons.album_rounded),
    _Option(0xe410, 'Note', icon: Icons.music_note_rounded),
    _Option(0xe3a1, 'Library', icon: Icons.library_music_rounded),
    _Option(0xe25b, 'Heart', icon: Icons.favorite_rounded),
    _Option(0xe229, 'EQ', icon: Icons.equalizer_rounded),
  ];

  static const List<_AccentPreset> _accentPresets = [
    _AccentPreset('Aura Gold', 255, 199, 44),
    _AccentPreset('Cyberpunk', 0, 240, 255),
    _AccentPreset('Emerald', 16, 185, 129),
    _AccentPreset('Purple', 168, 85, 247),
    _AccentPreset('Crimson', 239, 68, 68),
  ];

  @override
  void initState() {
    super.initState();
    _offlineOnly = StorageService.getSetting('offline_mode_only', defaultValue: false) as bool;
    _audioQuality = StorageService.getSetting('download_quality_label', defaultValue: 'HQ Stream (256kbps)') as String;
    _crossfadeEnabled = StorageService.isCrossfadeEnabled();
    _crossfadeDuration = StorageService.getCrossfadeDuration().toDouble();
    _hapticsEnabled = StorageService.isHapticsEnabled();
    _progressBarStyle = StorageService.getProgressBarStyle();
    _summaryLanguage = StorageService.getSetting('summary_language', defaultValue: 'en') as String;
    _is3dSoundEnabled = SpatialAudioService.isEnabled;
    _3dSoundMode = SpatialAudioService.currentMode;
    _3dSoundIntensity = SpatialAudioService.intensity;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final branding = ref.watch(customizationProvider);
    final sourceMode = ref.watch(sourceModeProvider);
    final playback = ref.watch(playbackProvider);
    final playbackNotifier = ref.read(playbackProvider.notifier);
    final accent = branding.accentColor;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 150),
      children: [
        _buildHeader(branding.appName),
        _buildBrandingCard(branding),

        // Admin portal (the widget hides itself for non-admin accounts)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: FirebaseAdminPortalTile(),
        ),

        // ── Account ────────────────────────────────────────────
        _sectionLabel('Account'),
        const FirebaseAccountSection(),

        // ── Appearance ─────────────────────────────────────────
        _sectionLabel('Appearance'),
        _SettingsGroup(
          children: [
            _buildThemeRow(themeMode, accent),
            _SettingsRow(
              icon: Icons.call_to_action_rounded,
              title: 'Navigation bar',
              value: _labelFor(
                _navBarOptions,
                branding.navBarStyle == 'default' ? 'default' : 'os_style',
              ),
              accent: accent,
              onTap: _showNavigationBarStyleSheet,
            ),
            _SettingsRow(
              icon: Icons.album_rounded,
              title: 'Player skin',
              value: _labelFor(_skinOptions, playback.playerSkin),
              accent: accent,
              onTap: _showSkinSheet,
            ),
            _SettingsRow(
              icon: Icons.style_rounded,
              title: 'Player screen theme',
              value: _labelFor(
                _screenThemeOptions,
                playback.playerScreenTheme,
                fallback: 'Normal (Classic)',
              ),
              accent: accent,
              onTap: _showScreenThemeSheet,
            ),
            _SettingsRow(
              icon: Icons.linear_scale_rounded,
              title: 'Progress bar style',
              value: _labelFor(_progressBarOptions, _progressBarStyle),
              accent: accent,
              onTap: _showProgressBarStyleSheet,
            ),
          ],
        ),

        // ── Playback ───────────────────────────────────────────
        _sectionLabel('Playback'),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.library_music_rounded,
              title: 'Music source',
              value: sourceMode.label,
              accent: accent,
              onTap: _showMusicSourceSheet,
            ),
            _SettingsRow(
              icon: Icons.speed_rounded,
              title: 'Playback speed',
              value: '${playback.playbackSpeed}x',
              accent: accent,
              onTap: _showPlaybackSpeedSheet,
            ),
            _switchRow(
              icon: Icons.all_inclusive_rounded,
              title: 'Gapless playback',
              subtitle: 'Start the next track immediately, without delay',
              value: playback.gaplessPlayback,
              accent: accent,
              onChanged: (val) {
                playbackNotifier.toggleGaplessPlayback();
              },
            ),
            _withDependent(
              show: _crossfadeEnabled,
              parent: _switchRow(
                icon: Icons.compare_arrows_rounded,
                title: 'Crossfade',
                subtitle: 'Smooth equal-power overlap between songs',
                value: _crossfadeEnabled,
                accent: accent,
                onChanged: (val) async {
                  setState(() {
                    _crossfadeEnabled = val;
                  });
                  await StorageService.setCrossfadeEnabled(val);
                },
              ),
              dependent: _SettingsRow(
                icon: Icons.timelapse_rounded,
                title: 'Crossfade duration',
                value: '${_crossfadeDuration.toInt()} seconds',
                accent: accent,
                onTap: _showCrossfadeDurationSheet,
              ),
            ),
            _switchRow(
              icon: Icons.volume_up_rounded,
              title: 'Volume normalization',
              subtitle: 'Dampen spikes for a balanced sound',
              value: playback.volumeNormalization,
              accent: accent,
              onChanged: (val) {
                playbackNotifier.toggleVolumeNormalization();
              },
            ),
            _SettingsRow(
              icon: Icons.bedtime_rounded,
              title: 'Sleep timer',
              value: playback.sleepTimerMinutes != null
                  ? '${playback.sleepTimerMinutes} min · ${_formatDurationRemaining(playback.sleepTimerTimeRemaining)} left'
                  : 'Off',
              accent: accent,
              onTap: _showSleepTimerSheet,
            ),
          ],
        ),

        // ── Sound ──────────────────────────────────────────────
        _sectionLabel('Sound'),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.equalizer_rounded,
              title: 'Equalizer & presets',
              subtitle: 'Fine-tune the 5-band frequency spectrum and gains',
              accent: accent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EqualizerScreen()),
                );
              },
            ),
            _withDependent(
              show: _is3dSoundEnabled,
              parent: _switchRow(
                icon: Icons.headphones_rounded,
                title: 'Virtual 3D sound',
                subtitle: 'Binaural 360° spatial audio for headphones',
                value: _is3dSoundEnabled,
                accent: accent,
                onChanged: (val) async {
                  setState(() {
                    _is3dSoundEnabled = val;
                  });
                  await SpatialAudioService.setEnabled(val);
                },
              ),
              dependent: _SettingsRow(
                icon: Icons.tune_rounded,
                title: 'Spatial preset & width',
                value: '$_3dSoundMode · ${(_3dSoundIntensity * 100).toInt()}%',
                accent: accent,
                onTap: () => _show3dSoundSheet(accent),
              ),
            ),
          ],
        ),

        // ── Downloads & offline ────────────────────────────────
        _sectionLabel('Downloads & offline'),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.high_quality_rounded,
              title: 'Download quality',
              value: _audioQuality,
              accent: accent,
              onTap: _showAudioQualitySheet,
            ),
            _switchRow(
              icon: Icons.wifi_off_rounded,
              title: 'Offline mode only',
              subtitle: 'Only play downloaded library files',
              value: _offlineOnly,
              accent: accent,
              onChanged: (val) {
                setState(() {
                  _offlineOnly = val;
                });
                StorageService.saveSetting('offline_mode_only', val);
              },
            ),
          ],
        ),

        // ── General ────────────────────────────────────────────
        _sectionLabel('General'),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.translate_rounded,
              title: 'AI summary language',
              value: _labelFor(_languageOptions, _summaryLanguage, fallback: 'English 🌐'),
              accent: accent,
              onTap: _showSummaryLanguageSheet,
            ),
            _switchRow(
              icon: Icons.vibration_rounded,
              title: 'Haptic feedback',
              subtitle: 'Vibrate on buttons, gestures and playback controls',
              value: _hapticsEnabled,
              accent: accent,
              onChanged: (val) async {
                setState(() {
                  _hapticsEnabled = val;
                });
                await StorageService.setHapticsEnabled(val);
              },
            ),
          ],
        ),

        // ── Storage ────────────────────────────────────────────
        _sectionLabel('Storage'),
        const AuraStorageUsageCard(),
        const SizedBox(height: 12),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.cleaning_services_rounded,
              title: 'Clear search history',
              subtitle: 'Remove all recent searches',
              accent: accent,
              destructive: true,
              showChevron: false,
              onTap: () => _confirmAndClear(
                title: 'Clear search history?',
                message: 'All of your recent searches will be removed.',
                doneMessage: 'Search history cleared successfully!',
                action: () async {
                  await StorageService.clearSearchHistory();
                },
              ),
            ),
            _SettingsRow(
              icon: Icons.delete_sweep_rounded,
              title: 'Clear listening history',
              subtitle: 'Remove your listening history records',
              accent: accent,
              destructive: true,
              showChevron: false,
              onTap: () => _confirmAndClear(
                title: 'Clear listening history?',
                message: 'Your listening history records will be removed.',
                doneMessage: 'Listening history cleared successfully!',
                action: () async {
                  await StorageService.clearListeningHistory();
                },
              ),
            ),
          ],
        ),

        // ── About ──────────────────────────────────────────────
        _sectionLabel('About'),
        _SettingsGroup(
          children: [
            _SettingsRow(
              icon: Icons.system_update_rounded,
              title: 'Check for updates',
              subtitle: 'Check GitHub for the latest release',
              accent: accent,
              onTap: () => UpdateService.checkForUpdates(context, silentIfLatest: true),
            ),
            _SettingsRow(
              icon: Icons.qr_code_2_rounded,
              title: 'Share app',
              subtitle: 'Download link & QR code',
              accent: accent,
              onTap: () => _showShareAppSheet(accent),
            ),
            _SettingsRow(
              icon: Icons.info_outline_rounded,
              title: 'App version',
              accent: accent,
              trailing: _buildPill('${AppVersionService.releaseTag} (Premium)'),
            ),
            _SettingsRow(
              icon: Icons.description_rounded,
              title: 'Developer license',
              subtitle: 'Creative Commons & JioSaavn API',
              accent: accent,
            ),
          ],
        ),

        const SizedBox(height: 24),
        _buildFooter(accent),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE PIECES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(String appName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Outfit',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tune how $appName looks, sounds and plays',
            style: TextStyle(fontSize: 13.5, color: _muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandingCard(CustomizationState branding) {
    final accent = branding.accentColor;

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: 0.28)),
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.26),
              accent.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: InkWell(
          onTap: () => _showCustomizerBottomSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(branding.brandingIcon, color: _onColor(accent), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branding.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Name, icon and accent color',
                        style: TextStyle(fontSize: 12.5, color: _muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Customize',
                    style: TextStyle(
                      color: _onColor(accent),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: _muted(context),
        ),
      ),
    );
  }

  /// Theme row: one System / Light / Dark control instead of two switches.
  Widget _buildThemeRow(ThemeMode mode, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.brightness_6_rounded, color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Theme', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                      'Dark uses AMOLED charcoal styling',
                      style: TextStyle(fontSize: 12.5, color: _muted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildThemeSegments(mode, accent),
        ],
      ),
    );
  }

  Widget _buildThemeSegments(ThemeMode current, Color accent) {
    final notifier = ref.read(themeModeProvider.notifier);

    Widget segment(ThemeMode mode, IconData icon, String label) {
      final selected = current == mode;
      final foreground = selected ? _onColor(accent) : _muted(context);

      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            triggerHaptic(HapticFeedbackType.light);
            switch (mode) {
              case ThemeMode.system:
                notifier.setSystemMode();
                break;
              case ThemeMode.light:
                notifier.toggleTheme(false);
                break;
              case ThemeMode.dark:
                notifier.toggleTheme(true);
                break;
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _tint(context, 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          segment(ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
          segment(ThemeMode.light, Icons.light_mode_rounded, 'Light'),
          segment(ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
        ],
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Color accent,
    required ValueChanged<bool> onChanged,
  }) {
    void handle(bool val) {
      triggerHaptic(HapticFeedbackType.light);
      onChanged(val);
    }

    return _SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accent: accent,
      onTap: () => handle(!value),
      trailing: Switch(
        value: value,
        onChanged: handle,
        activeTrackColor: accent,
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected) ? _onColor(accent) : null,
        ),
      ),
    );
  }

  /// A row plus a second row that slides in underneath while [show] is true.
  Widget _withDependent({
    required bool show,
    required Widget parent,
    required Widget dependent,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        parent,
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: show
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [const _RowDivider(), dependent],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _tint(context, 0.06),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _muted(context)),
      ),
    );
  }

  Widget _buildFooter(Color accent) {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final Uri url = Uri.parse('https://www.linkedin.com/in/bhavneet-verma/');
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Made with ',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Text('❤️', style: TextStyle(fontSize: 14)),
              Text(
                ' by ',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Bhavneet Verma',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatDurationRemaining(Duration? dur) {
    if (dur == null) return '0:00';
    final m = dur.inMinutes;
    final s = dur.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _labelFor<T>(List<_Option<T>> options, T value, {String? fallback}) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return fallback ?? value.toString();
  }

  String _hex(int channel) => channel.toRadixString(16).padLeft(2, '0').toUpperCase();

  Widget _accentSlider({required Color color, required Widget child}) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: color,
        inactiveTrackColor: color.withValues(alpha: 0.18),
        thumbColor: color,
        overlayColor: color.withValues(alpha: 0.15),
      ),
      child: child,
    );
  }

  Widget _primaryButton({
    required String label,
    required Color accent,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: _onColor(accent),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      child: Text(label),
    );
  }

  Widget _secondaryButton({required String label, required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: _tint(context, 0.18)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      child: Text(label),
    );
  }

  Future<void> _confirmAndClear({
    required String title,
    required String message,
    required String doneMessage,
    required Future<void> Function() action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Clear',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await action();
    messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PICKER SHEETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// One picker for every "choose one of these" setting.
  void _showOptionSheet<T>({
    required String title,
    String? subtitle,
    IconData? icon,
    required List<_Option<T>> options,
    required T? selected,
    required ValueChanged<T> onSelected,
  }) {
    final accent = ref.read(customizationProvider).accentColor;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _SheetFrame(
          title: title,
          subtitle: subtitle,
          icon: icon,
          accent: accent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                _OptionTile(
                  label: option.label,
                  description: option.description,
                  icon: option.icon,
                  selected: option.value == selected,
                  accent: accent,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSelected(option.value);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSkinSheet() {
    final notifier = ref.read(playbackProvider.notifier);
    _showOptionSheet<String>(
      title: 'Player Skin',
      subtitle: 'How the artwork is presented while a song plays',
      icon: Icons.album_rounded,
      options: _skinOptions,
      selected: ref.read(playbackProvider).playerSkin,
      onSelected: (skin) {
        notifier.setPlayerSkin(skin);
      },
    );
  }

  void _showScreenThemeSheet() {
    final notifier = ref.read(playbackProvider.notifier);
    _showOptionSheet<String>(
      title: 'Player Screen Theme',
      subtitle: 'Layout of the full-screen player',
      icon: Icons.style_rounded,
      options: _screenThemeOptions,
      selected: ref.read(playbackProvider).playerScreenTheme,
      onSelected: (theme) {
        notifier.setPlayerScreenTheme(theme);
      },
    );
  }

  void _showNavigationBarStyleSheet() {
    final notifier = ref.read(customizationProvider.notifier);
    final currentStyle = ref.read(customizationProvider).navBarStyle;
    _showOptionSheet<String>(
      title: 'Navigation Bar Style',
      icon: Icons.call_to_action_rounded,
      options: _navBarOptions,
      selected: currentStyle == 'default' ? 'default' : 'os_style',
      onSelected: (style) {
        notifier.updateNavigationBarStyle(style);
      },
    );
  }

  void _showProgressBarStyleSheet() {
    _showOptionSheet<String>(
      title: 'Progress Bar Style',
      subtitle: 'The seek bar shown in the player',
      icon: Icons.linear_scale_rounded,
      options: _progressBarOptions,
      selected: _progressBarStyle,
      onSelected: (key) async {
        setState(() {
          _progressBarStyle = key;
        });
        await StorageService.setProgressBarStyle(key);
      },
    );
  }

  void _showMusicSourceSheet() {
    _showOptionSheet<SourceMode>(
      title: 'Music Source',
      subtitle: 'Choose where Aura searches and streams your tracks from',
      icon: Icons.library_music_rounded,
      options: [
        for (final mode in SourceMode.values)
          _Option<SourceMode>(
            mode,
            mode.label,
            description: mode.description,
            icon: _sourceIcon(mode),
          ),
      ],
      selected: ref.read(sourceModeProvider),
      onSelected: (mode) {
        ref.read(sourceModeProvider.notifier).setMode(mode);
      },
    );
  }

  IconData _sourceIcon(SourceMode mode) {
    switch (mode) {
      case SourceMode.hybrid:
        return Icons.auto_awesome_rounded;
      case SourceMode.jiosaavn:
        return Icons.music_note_rounded;
      case SourceMode.youtube:
        return Icons.play_circle_filled_rounded;
    }
  }

  void _showPlaybackSpeedSheet() {
    final notifier = ref.read(playbackProvider.notifier);
    _showOptionSheet<double>(
      title: 'Playback Speed',
      icon: Icons.speed_rounded,
      options: _speedOptions,
      selected: ref.read(playbackProvider).playbackSpeed.toDouble(),
      onSelected: (speed) {
        notifier.setPlaybackSpeed(speed);
      },
    );
  }

  void _showSleepTimerSheet() {
    final notifier = ref.read(playbackProvider.notifier);
    _showOptionSheet<int>(
      title: 'Sleep Timer',
      subtitle: 'Stop playback automatically after a while',
      icon: Icons.bedtime_rounded,
      options: _sleepTimerOptions,
      selected: ref.read(playbackProvider).sleepTimerMinutes ?? 0,
      onSelected: (minutes) {
        if (minutes == 0) {
          notifier.cancelSleepTimer();
        } else {
          notifier.startSleepTimer(minutes);
        }
      },
    );
  }

  void _showAudioQualitySheet() {
    _showOptionSheet<String>(
      title: 'Download Quality',
      subtitle: 'Higher quality uses more storage and data',
      icon: Icons.high_quality_rounded,
      options: _qualityOptions,
      selected: _audioQuality,
      onSelected: (option) {
        setState(() {
          _audioQuality = option;
        });
        StorageService.saveSetting('download_quality_label', option);
      },
    );
  }

  void _showSummaryLanguageSheet() {
    _showOptionSheet<String>(
      title: 'AI Summary Language',
      subtitle: 'Used for AI song stories and lyric analysis',
      icon: Icons.translate_rounded,
      options: _languageOptions,
      selected: _summaryLanguage,
      onSelected: (code) async {
        setState(() => _summaryLanguage = code);
        await StorageService.saveSetting('summary_language', code);
      },
    );
  }

  void _showCrossfadeDurationSheet() {
    final accent = ref.read(customizationProvider).accentColor;
    double tempDuration = _crossfadeDuration.clamp(1, 12).toDouble();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return _SheetFrame(
              title: 'Crossfade Duration',
              subtitle: 'How long two songs overlap while changing',
              icon: Icons.timelapse_rounded,
              accent: accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    '${tempDuration.toInt()} seconds',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _accentSlider(
                    color: accent,
                    child: Slider(
                      value: tempDuration,
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '${tempDuration.toInt()}s',
                      onChanged: (val) {
                        setSheetState(() {
                          tempDuration = val;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1s', style: TextStyle(fontSize: 12, color: _muted(sheetContext))),
                        Text('12s', style: TextStyle(fontSize: 12, color: _muted(sheetContext))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _secondaryButton(
                            label: 'Cancel',
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _primaryButton(
                            label: 'Save',
                            accent: accent,
                            onPressed: () async {
                              setState(() {
                                _crossfadeDuration = tempDuration;
                              });
                              await StorageService.setCrossfadeDuration(tempDuration.toInt());
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _show3dSoundSheet(Color accent) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return _SheetFrame(
              title: '3D Spatial Audio',
              subtitle: 'Binaural 360° virtual soundstage for headphones',
              icon: Icons.headphones_rounded,
              accent: accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetLabel('Spatial presets'),
                  for (final entry in SpatialAudioService.presets.entries)
                    _OptionTile(
                      label: entry.value.name,
                      description: entry.value.description,
                      icon: entry.value.icon,
                      selected: _3dSoundMode == entry.key,
                      accent: accent,
                      onTap: () async {
                        setState(() {
                          _3dSoundMode = entry.key;
                          _3dSoundIntensity = entry.value.defaultIntensity;
                        });
                        setModalState(() {});
                        await SpatialAudioService.setMode(entry.key);
                      },
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(child: _SheetLabel('Soundstage width & intensity')),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${(_3dSoundIntensity * 100).toInt()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: accent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _accentSlider(
                    color: accent,
                    child: Slider(
                      value: _3dSoundIntensity.clamp(0.1, 1.0).toDouble(),
                      min: 0.1,
                      max: 1.0,
                      divisions: 18,
                      onChanged: (val) async {
                        setState(() {
                          _3dSoundIntensity = val;
                        });
                        setModalState(() {});
                        await SpatialAudioService.setIntensity(val);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: _primaryButton(
                        label: 'Done',
                        accent: accent,
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showShareAppSheet(Color accent) {
    const shareUrl = String.fromEnvironment(
      'APP_DOWNLOAD_URL',
      defaultValue: String.fromEnvironment(
        'APP_SHARE_URL',
        defaultValue: 'https://github.com/bhavneetv/Aura_Music/releases',
      ),
    );

    Future<void> launchAppUrl() async {
      try {
        final uri = Uri.parse(shareUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      } catch (e) {
        try {
          final uri = Uri.parse(shareUrl);
          await launchUrl(uri, mode: LaunchMode.inAppWebView);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opening $shareUrl')),
            );
          }
        }
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _SheetFrame(
          title: 'Share Aura',
          subtitle: 'Scan the QR code or open the download page',
          icon: Icons.qr_code_2_rounded,
          accent: accent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              GestureDetector(
                onTap: launchAppUrl,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: shareUrl,
                    version: QrVersions.auto,
                    size: 190.0,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: launchAppUrl,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    shareUrl,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: _primaryButton(
                    label: 'Open download page',
                    accent: accent,
                    onPressed: launchAppUrl,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANDING CUSTOMIZER
  // ═══════════════════════════════════════════════════════════════════════════

  void _showCustomizerBottomSheet(BuildContext context) {
    _nameController.text = ref.read(customizationProvider).appName;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // Consumer keeps the sheet in sync with the provider on its own, so
        // every tap repaints the preview without manual setState calls.
        return Consumer(
          builder: (sheetContext, ref, _) {
            final state = ref.watch(customizationProvider);
            final notifier = ref.read(customizationProvider.notifier);
            final accent = state.accentColor;
            final hex = '#${_hex(state.red)}${_hex(state.green)}${_hex(state.blue)}';

            return _SheetFrame(
              title: 'Customize Aura',
              subtitle: 'Changes apply instantly across the app',
              icon: Icons.palette_rounded,
              accent: accent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App name
                    const _SheetLabel('App name'),
                    TextField(
                      controller: _nameController,
                      onChanged: (val) {
                        notifier.updateAppName(val);
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter brand name...',
                        filled: true,
                        fillColor: _tint(sheetContext, 0.05),
                        prefixIcon: Icon(state.brandingIcon, color: accent, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: accent, width: 1.5),
                        ),
                      ),
                    ),

                    // Branding icon
                    const _SheetLabel('App icon'),
                    Row(
                      children: [
                        for (final item in _brandIconOptions)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: _buildIconChoice(
                                sheetContext,
                                item: item,
                                selected: state.brandingIconCode == item.value,
                                accent: accent,
                                onTap: () {
                                  notifier.updateBrandingIcon(item.value);
                                },
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Preset palettes
                    const _SheetLabel('Accent color'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final preset in _accentPresets)
                          Expanded(
                            child: _buildPresetSwatch(
                              sheetContext,
                              preset: preset,
                              selected: state.red == preset.r &&
                                  state.green == preset.g &&
                                  state.blue == preset.b,
                              onTap: () {
                                notifier.updateAccentColor(preset.r, preset.g, preset.b);
                              },
                            ),
                          ),
                      ],
                    ),

                    if (Platform.isAndroid) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(sheetContext);
                            String message;
                            try {
                              final corePalette = await DynamicColorPlugin.getCorePalette();
                              if (corePalette != null) {
                                final argb = corePalette.primary.get(40);
                                notifier.updateAccentColor(
                                  (argb >> 16) & 0xFF,
                                  (argb >> 8) & 0xFF,
                                  argb & 0xFF,
                                );
                                message = 'Phone theme synced successfully!';
                              } else {
                                message = 'Dynamic color not supported on this device.';
                              }
                            } catch (e) {
                              message = 'Failed to get phone theme color.';
                            }
                            // Close the sheet so the change is visible.
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                            messenger.showSnackBar(SnackBar(content: Text(message)));
                          },
                          icon: const Icon(Icons.sync_rounded, size: 20),
                          label: const Text(
                            'Sync phone theme',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: accent.withValues(alpha: 0.5)),
                            foregroundColor: accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],

                    // Custom RGB
                    Row(
                      children: [
                        const Expanded(child: _SheetLabel('Custom color (RGB)')),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _tint(sheetContext, 0.06),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  hex,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildRGBSlider(
                      label: 'R',
                      value: state.red,
                      color: Colors.redAccent,
                      onChanged: (val) {
                        notifier.updateAccentColor(val.toInt(), state.green, state.blue);
                      },
                    ),
                    _buildRGBSlider(
                      label: 'G',
                      value: state.green,
                      color: Colors.greenAccent,
                      onChanged: (val) {
                        notifier.updateAccentColor(state.red, val.toInt(), state.blue);
                      },
                    ),
                    _buildRGBSlider(
                      label: 'B',
                      value: state.blue,
                      color: Colors.blueAccent,
                      onChanged: (val) {
                        notifier.updateAccentColor(state.red, state.green, val.toInt());
                      },
                    ),
                    const SizedBox(height: 10),

                    // Gradient preview
                    Container(
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            accent,
                            accent.withValues(alpha: 0.5),
                            accent.withValues(alpha: 0.1),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: _secondaryButton(
                            label: 'Reset',
                            onPressed: () {
                              notifier.resetToDefault();
                              _nameController.text = 'Aura Vinyl';
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _primaryButton(
                            label: 'Done',
                            accent: accent,
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIconChoice(
    BuildContext sheetContext, {
    required _Option<int> item,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : _tint(sheetContext, 0.04),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? accent : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 24, color: selected ? accent : _muted(sheetContext)),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? null : _muted(sheetContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetSwatch(
    BuildContext sheetContext, {
    required _AccentPreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? preset.color : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: preset.color, shape: BoxShape.circle),
              child: selected
                  ? Center(
                      child: Icon(Icons.check_rounded, size: 18, color: _onColor(preset.color)),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preset.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? null : _muted(sheetContext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRGBSlider({
    required String label,
    required int value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        Expanded(
          child: _accentSlider(
            color: color,
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // Kept from the original file (it was not wired to any row there either).
  // ignore: unused_element
  void _showEditUserNameDialog(BuildContext context) {
    final controller = TextEditingController(text: StorageService.getUserName());
    final accent = ref.read(customizationProvider).accentColor;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Edit Your Display Name'),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Enter your name (e.g. Bhavneet)...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                await StorageService.setUserName(name);
                if (context.mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: _onColor(accent),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED BUILDING BLOCKS
// ═════════════════════════════════════════════════════════════════════════════

/// One choice in a picker (and the label shown for it on the settings row).
class _Option<T> {
  const _Option(this.value, this.label, {this.description, this.icon});

  final T value;
  final String label;
  final String? description;
  final IconData? icon;
}

class _AccentPreset {
  const _AccentPreset(this.label, this.r, this.g, this.b);

  final String label;
  final int r;
  final int g;
  final int b;

  Color get color => Color.fromARGB(255, r, g, b);
}

/// White in dark mode, black in light mode, at the given opacity. Used for
/// card fills and hairlines so they sit on any background.
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

/// Rounded card that stacks rows with hairline dividers between them.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const _RowDivider());
      rows.add(children[i]);
    }

    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    // Indent lines the divider up with the row text (16 + 36 badge + 14 gap).
    return Divider(height: 1, thickness: 1, indent: 66, color: _tint(context, 0.06));
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color, this.size = 36});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

/// A single settings row: icon badge, title, optional current value /
/// description, and either a custom trailing widget or a chevron.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.accent,
    this.value,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final Color accent;

  /// Current selection, shown in the accent color under the title.
  final String? value;

  /// Explanatory text, shown muted under the title.
  final String? subtitle;

  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final badgeColor = destructive ? Colors.redAccent : accent;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _IconBadge(icon: icon, color: badgeColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: destructive ? Colors.redAccent : null,
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: _muted(context)),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (onTap != null && showChevron) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 22, color: _tint(context, 0.35)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared chrome for every bottom sheet: grab handle, icon, title, subtitle,
/// and a scrollable body that never grows taller than the screen.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final badgeColor = accent ?? Theme.of(context).colorScheme.primary;

    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        child: Material(
          color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        _IconBadge(icon: icon!, color: badgeColor, size: 42),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle!,
                                style: TextStyle(fontSize: 12.5, color: _muted(context)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    child: child,
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

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: _muted(context),
        ),
      ),
    );
  }
}

/// A selectable card inside a picker sheet.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.description,
    this.icon,
  });

  final String label;
  final String? description;
  final IconData? icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.12) : _tint(context, 0.04),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: selected ? accent : _muted(context)),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          description!,
                          style: TextStyle(fontSize: 12, color: _muted(context)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? accent : _tint(context, 0.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}