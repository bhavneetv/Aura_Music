import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage/storage_service.dart';

// Accent theme state containing customization choices
class CustomizationState {
  final String appName;
  final int brandingIconCode; // IconData codePoint
  final int red;
  final int green;
  final int blue;

  CustomizationState({
    required this.appName,
    required this.brandingIconCode,
    required this.red,
    required this.green,
    required this.blue,
  });

  CustomizationState copyWith({
    String? appName,
    int? brandingIconCode,
    int? red,
    int? green,
    int? blue,
  }) {
    return CustomizationState(
      appName: appName ?? this.appName,
      brandingIconCode: brandingIconCode ?? this.brandingIconCode,
      red: red ?? this.red,
      green: green ?? this.green,
      blue: blue ?? this.blue,
    );
  }

  Color get accentColor => Color.fromARGB(255, red, green, blue);

  IconData get brandingIcon => IconData(brandingIconCode, fontFamily: 'MaterialIcons');
}

class CustomizationNotifier extends Notifier<CustomizationState> {
  // Original defaults
  static const String _defaultAppName = 'Aura Vinyl';
  static const int _defaultIconCode = 0xe056; // album_rounded
  static const int _defaultR = 212; // Gold accent R
  static const int _defaultG = 175; // Gold accent G
  static const int _defaultB = 55;  // Gold accent B

  @override
  CustomizationState build() {
    // Load from Hive
    final String savedName = StorageService.getSetting('custom_app_name', defaultValue: _defaultAppName) as String;
    final int savedIcon = StorageService.getSetting('custom_app_icon_code', defaultValue: _defaultIconCode) as int;
    final int savedR = StorageService.getSetting('custom_theme_r', defaultValue: _defaultR) as int;
    final int savedG = StorageService.getSetting('custom_theme_g', defaultValue: _defaultG) as int;
    final int savedB = StorageService.getSetting('custom_theme_b', defaultValue: _defaultB) as int;

    return CustomizationState(
      appName: savedName,
      brandingIconCode: savedIcon,
      red: savedR,
      green: savedG,
      blue: savedB,
    );
  }

  Future<void> updateAppName(String name) async {
    state = state.copyWith(appName: name);
    await StorageService.saveSetting('custom_app_name', name);
  }

  Future<void> updateBrandingIcon(int codePoint) async {
    state = state.copyWith(brandingIconCode: codePoint);
    await StorageService.saveSetting('custom_app_icon_code', codePoint);
  }

  Future<void> updateAccentColor(int r, int g, int b) async {
    state = state.copyWith(red: r, green: g, blue: b);
    await StorageService.saveSetting('custom_theme_r', r);
    await StorageService.saveSetting('custom_theme_g', g);
    await StorageService.saveSetting('custom_theme_b', b);
  }

  Future<void> resetToDefault() async {
    state = CustomizationState(
      appName: _defaultAppName,
      brandingIconCode: _defaultIconCode,
      red: _defaultR,
      green: _defaultG,
      blue: _defaultB,
    );
    await StorageService.saveSetting('custom_app_name', _defaultAppName);
    await StorageService.saveSetting('custom_app_icon_code', _defaultIconCode);
    await StorageService.saveSetting('custom_theme_r', _defaultR);
    await StorageService.saveSetting('custom_theme_g', _defaultG);
    await StorageService.saveSetting('custom_theme_b', _defaultB);
  }
}

final customizationProvider = NotifierProvider<CustomizationNotifier, CustomizationState>(() {
  return CustomizationNotifier();
});
