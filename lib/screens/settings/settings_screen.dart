import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../equalizer/equalizer_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _offlineOnly = false;
  String _audioQuality = 'HQ Stream (256kbps)';

  @override
  void initState() {
    super.initState();
    _offlineOnly = StorageService.getSetting('offline_mode_only', defaultValue: false) as bool;
    _audioQuality = StorageService.getSetting('download_quality_label', defaultValue: 'HQ Stream (256kbps)') as String;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Show Customizer dialog/sheet ─────────────────────────────

  void _showCustomizerBottomSheet(BuildContext context) {
    final customState = ref.watch(customizationProvider);
    final customNotifier = ref.read(customizationProvider.notifier);
    _nameController.text = customState.appName;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final icons = [
      {'code': 0xe056, 'icon': Icons.album_rounded, 'name': 'Vinyl'},
      {'code': 0xe410, 'icon': Icons.music_note_rounded, 'name': 'Note'},
      {'code': 0xe3a1, 'icon': Icons.library_music_rounded, 'name': 'Library'},
      {'code': 0xe25b, 'icon': Icons.favorite_rounded, 'name': 'Heart'},
      {'code': 0xe229, 'icon': Icons.equalizer_rounded, 'name': 'EQ'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeCustomState = ref.watch(customizationProvider);
            
            return Container(
              padding: EdgeInsets.only(
                left: 24, 
                right: 24, 
                top: 24, 
                bottom: MediaQuery.of(context).viewInsets.bottom + 24
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161616) : const Color(0xFFFAF8F5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Customize Aura App',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // App Name field
                  const Text('App Name / Brand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    onChanged: (val) {
                      customNotifier.updateAppName(val);
                    },
                    decoration: InputDecoration(
                      hintText: 'Enter brand name...',
                      filled: true,
                      fillColor: isDark ? Colors.white54.withOpacity(0.04) : Colors.black54.withOpacity(0.04),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Alternate Icon Picker
                  const Text('App Branding Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: icons.map((item) {
                      final isSelected = activeCustomState.brandingIconCode == item['code'];
                      return GestureDetector(
                        onTap: () {
                          customNotifier.updateBrandingIcon(item['code'] as int);
                          setDialogState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected 
                                ? activeCustomState.accentColor.withOpacity(0.15) 
                                : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? activeCustomState.accentColor : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            color: isSelected ? activeCustomState.accentColor : Colors.grey,
                            size: 24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // RGB Accent color sliders
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Theme Accent Color (RGB)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        'R: ${activeCustomState.red} G: ${activeCustomState.green} B: ${activeCustomState.blue}',
                        style: TextStyle(color: activeCustomState.accentColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Red Slider
                  _buildRGBSlider(
                    label: 'Red',
                    value: activeCustomState.red,
                    color: Colors.redAccent,
                    onChanged: (val) {
                      customNotifier.updateAccentColor(val.toInt(), activeCustomState.green, activeCustomState.blue);
                      setDialogState(() {});
                    },
                  ),
                  
                  // Green Slider
                  _buildRGBSlider(
                    label: 'Green',
                    value: activeCustomState.green,
                    color: Colors.greenAccent,
                    onChanged: (val) {
                      customNotifier.updateAccentColor(activeCustomState.red, val.toInt(), activeCustomState.blue);
                      setDialogState(() {});
                    },
                  ),
                  
                  // Blue Slider
                  _buildRGBSlider(
                    label: 'Blue',
                    value: activeCustomState.blue,
                    color: Colors.blueAccent,
                    onChanged: (val) {
                      customNotifier.updateAccentColor(activeCustomState.red, activeCustomState.green, val.toInt());
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),

                  // Gradient color preview bar
                  const Text('Accent Gradient Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          activeCustomState.accentColor,
                          activeCustomState.accentColor.withOpacity(0.5),
                          activeCustomState.accentColor.withOpacity(0.1),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Reset Default Button & Apply Button
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            customNotifier.resetToDefault();
                            _nameController.text = 'Aura Vinyl';
                            setDialogState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.grey),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Reset to Default', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: activeCustomState.accentColor,
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Apply Details', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
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
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: color,
            inactiveColor: color.withOpacity(0.2),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final playerSettings = ref.watch(settingsProvider);
    final customBranding = ref.watch(customizationProvider);
    
    final playbackState = ref.watch(playbackProvider);
    final playbackNotifier = ref.read(playbackProvider.notifier);
    
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final themeNotifier = ref.read(themeModeProvider.notifier);

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 16),
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 20),
          child: Text(
            'Settings',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Outfit',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),

        // 0. Custom branding card
        _buildSectionHeader('BRANDING CUSTOMIZER', customBranding.accentColor),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: Icon(customBranding.brandingIcon, color: customBranding.accentColor),
          title: const Text('Customize App Visuals', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: Text('Change app name: "${customBranding.appName}" and RGB colors'),
          trailing: const Icon(Icons.palette_outlined, color: Colors.grey),
          onTap: () => _showCustomizerBottomSheet(context),
        ),
        const Divider(indent: 24, endIndent: 24, height: 1),

        // 1. Group: Appearance
        const SizedBox(height: 12),
        _buildSectionHeader('APPEARANCE', customBranding.accentColor),
        _buildSwitchTile(
          'Dark Mode Theme',
          'Use AMOLED charcoal visual styling',
          themeMode == ThemeMode.dark,
          customBranding.accentColor,
          (val) {
            themeNotifier.toggleTheme(val);
          },
        ),
        _buildSwitchTile(
          'System Theme Matching',
          'Follow your device settings',
          themeMode == ThemeMode.system,
          customBranding.accentColor,
          (val) {
            if (val) {
              themeNotifier.setSystemMode();
            } else {
              themeNotifier.toggleTheme(isDark);
            }
          },
        ),
        const Divider(indent: 24, endIndent: 24, height: 1),

        // 2. Group: Audio Player Settings
        const SizedBox(height: 12),
        _buildSectionHeader('PLAYER SKIN & CONTROLS', customBranding.accentColor),
        _buildSelectionTile(
          'Active Player Skin',
          playbackState.playerSkin.toUpperCase(),
          () => _showSkinSelectionDialog(playbackNotifier),
        ),
        _buildSelectionTile(
          'Playback Speed',
          '${playbackState.playbackSpeed}x',
          () => _showPlaybackSpeedDialog(playbackNotifier),
        ),
        _buildSwitchTile(
          'Volume Normalization',
          'Dampen spikes for a balanced sound',
          playbackState.volumeNormalization,
          customBranding.accentColor,
          (val) {
            playbackNotifier.toggleVolumeNormalization();
          },
        ),
        _buildSwitchTile(
          'Gapless Playback',
          'Transition next tracks immediately without delay',
          playbackState.gaplessPlayback,
          customBranding.accentColor,
          (val) {
            playbackNotifier.toggleGaplessPlayback();
          },
        ),
        _buildSwitchTile(
          'Haptic Feedback',
          'Vibrate on buttons and slider events',
          playerSettings.hapticFeedback,
          customBranding.accentColor,
          (val) {
            settingsNotifier.toggleHaptics(val);
          },
        ),
        const Divider(indent: 24, endIndent: 24, height: 1),

        // 3. Group: Sleep Timer
        const SizedBox(height: 12),
        _buildSectionHeader('SLEEP TIMER', customBranding.accentColor),
        _buildSelectionTile(
          'Timer Settings',
          playbackState.sleepTimerMinutes != null 
              ? '${playbackState.sleepTimerMinutes} mins (${_formatDurationRemaining(playbackState.sleepTimerTimeRemaining)})'
              : 'OFF',
          () => _showSleepTimerDialog(playbackNotifier),
        ),
        const Divider(indent: 24, endIndent: 24, height: 1),

        // 4. Group: Audio & Equalizer
        const SizedBox(height: 12),
        _buildSectionHeader('AUDIO EFFECTS', customBranding.accentColor),
        _buildNavigationTile(
          context,
          'Equalizer & Effects',
          'Customize frequency bands and presets',
          const EqualizerScreen(),
        ),
        _buildSelectionTile(
          'Download Stream Quality',
          _audioQuality,
          () => _showAudioQualityDialog(),
        ),
        _buildSwitchTile(
          'Offline Mode Only',
          'Only play local downloaded library files',
          _offlineOnly,
          customBranding.accentColor,
          (val) {
            setState(() {
              _offlineOnly = val;
            });
            StorageService.saveSetting('offline_mode_only', val);
          },
        ),
        const Divider(indent: 24, endIndent: 24, height: 1),

        // 5. Group: Storage Clean
        const SizedBox(height: 12),
        _buildSectionHeader('STORAGE MANAGEMENT', customBranding.accentColor),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          title: const Text('Clear Search History', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: const Text('Wipes all recent searches cache'),
          trailing: const Icon(Icons.cleaning_services_rounded, color: Colors.grey),
          onTap: () async {
            await StorageService.clearSearchHistory();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search history cleared successfully!'))
            );
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          title: const Text('Clear Listening Cache', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: const Text('Wipes your list history records'),
          trailing: const Icon(Icons.delete_sweep_rounded, color: Colors.grey),
          onTap: () async {
            await StorageService.clearListeningHistory();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Listening history cleared successfully!'))
            );
          },
        ),
        const Divider(indent: 24, endIndent: 24, height: 1),

        // 6. Group: About
        const SizedBox(height: 12),
        _buildSectionHeader('ABOUT', customBranding.accentColor),
        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 24),
          title: Text('App Version', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          trailing: Text('v2.0.0 (Premium)', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 24),
          title: Text('Developer License', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          trailing: Text('Creative Commons & JioSaavn API', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      ],
    );
  }

  String _formatDurationRemaining(Duration? dur) {
    if (dur == null) return '0:00';
    final m = dur.inMinutes;
    final s = dur.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 12, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Color activeColor, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      activeColor: activeColor,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildNavigationTile(BuildContext context, String title, String subtitle, Widget screen) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      },
    );
  }

  Widget _buildSelectionTile(String title, String valuePreview, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(valuePreview, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }

  // ── Dialog Selectors ────────────────────────────────────────

  void _showSkinSelectionDialog(PlaybackNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Choose Skin Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Rotating Vinyl Disc'),
                onTap: () {
                  notifier.setPlayerSkin('vinyl');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Modern Compact CD'),
                onTap: () {
                  notifier.setPlayerSkin('cd');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Classic Cassette Tape'),
                onTap: () {
                  notifier.setPlayerSkin('cassette');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Ultra Minimal Artwork'),
                onTap: () {
                  notifier.setPlayerSkin('minimal');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaybackSpeedDialog(PlaybackNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Playback Speed', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
              return ListTile(
                title: Text('${speed}x'),
                onTap: () {
                  notifier.setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showSleepTimerDialog(PlaybackNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Sleep Timer', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('5 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(5);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('15 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(15);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('30 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(30);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('60 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(60);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Turn Timer Off', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  notifier.cancelSleepTimer();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAudioQualityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Stream Quality', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogOption('Eco Stream (96kbps)'),
              _buildDialogOption('Standard (160kbps)'),
              _buildDialogOption('HQ Stream (320kbps)'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDialogOption(String option) {
    return ListTile(
      title: Text(option),
      onTap: () {
        setState(() {
          _audioQuality = option;
        });
        StorageService.saveSetting('download_quality_label', option);
        Navigator.pop(context);
      },
    );
  }
}
