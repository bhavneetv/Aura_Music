import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Theme mode provider for manual Dark/Light toggling using modern Notifier
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ThemeMode.dark; // Default to Dark mode
  }

  void toggleTheme(bool isDark) {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  void setSystemMode() {
    state = ThemeMode.system;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});

// 2. Player settings model
class PlayerSettings {
  final bool showVinyl;
  final bool hapticFeedback;

  PlayerSettings({
    this.showVinyl = true,
    this.hapticFeedback = true,
  });

  PlayerSettings copyWith({
    bool? showVinyl,
    bool? hapticFeedback,
  }) {
    return PlayerSettings(
      showVinyl: showVinyl ?? this.showVinyl,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
    );
  }
}

// 3. Settings provider for vinyl removal and haptics using modern Notifier
class SettingsNotifier extends Notifier<PlayerSettings> {
  @override
  PlayerSettings build() {
    return PlayerSettings();
  }

  void toggleVinyl(bool show) {
    state = state.copyWith(showVinyl: show);
  }

  void toggleHaptics(bool enabled) {
    state = state.copyWith(hapticFeedback: enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, PlayerSettings>(() {
  return SettingsNotifier();
});
