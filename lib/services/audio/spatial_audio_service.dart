import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../storage/storage_service.dart';

class Spatial3dPreset {
  final String name;
  final String description;
  final double defaultIntensity;
  final IconData icon;

  const Spatial3dPreset({
    required this.name,
    required this.description,
    required this.defaultIntensity,
    required this.icon,
  });
}

class SpatialAudioService {
  static const MethodChannel _channel = MethodChannel('com.example.music_app/audio_routing');

  static bool _isEnabled = false;
  static String _currentMode = 'Wide Room';
  static double _intensity = 0.65;
  static bool _initialized = false;

  static bool get isEnabled => _isEnabled;
  static String get currentMode => _currentMode;
  static double get intensity => _intensity;

  static const Map<String, Spatial3dPreset> presets = {
    'Wide Room': Spatial3dPreset(
      name: 'Wide Room',
      description: 'Expansive studio soundstage with natural binaural acoustic ambience',
      defaultIntensity: 0.65,
      icon: Icons.meeting_room_rounded,
    ),
    'Concert Hall': Spatial3dPreset(
      name: 'Concert Hall',
      description: 'Maximum panoramic width simulating an open auditorium concert',
      defaultIntensity: 0.95,
      icon: Icons.stadium_rounded,
    ),
    'Subtle Headstage': Spatial3dPreset(
      name: 'Subtle Headstage',
      description: 'Gentle crossfeed to reduce in-head fatigue during long headphone sessions',
      defaultIntensity: 0.40,
      icon: Icons.headphones_rounded,
    ),
    'Bass Surround 3D': Spatial3dPreset(
      name: 'Bass Surround 3D',
      description: 'Deep 3D spatial field with low-end resonance for electronic & hip-hop',
      defaultIntensity: 0.80,
      icon: Icons.speaker_group_rounded,
    ),
  };

  /// Initializes Spatial 3D Audio from saved preferences
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _isEnabled = StorageService.is3dSoundEnabled();
      _currentMode = StorageService.get3dSoundMode();
      _intensity = StorageService.get3dSoundIntensity();
      _initialized = true;
      if (_isEnabled) {
        await apply();
      }
    } catch (e) {
      debugPrint('SpatialAudioService init failed: $e');
    }
  }

  /// Toggles 3D Virtual Sound on/off
  static Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await StorageService.set3dSoundEnabled(enabled);
    await apply();
  }

  /// Changes the 3D Spatial Audio preset
  static Future<void> setMode(String mode) async {
    if (!presets.containsKey(mode)) return;
    _currentMode = mode;
    final preset = presets[mode]!;
    _intensity = preset.defaultIntensity;
    await StorageService.set3dSoundMode(mode);
    await StorageService.set3dSoundIntensity(_intensity);
    await apply();
  }

  /// Adjusts the 3D Virtual Sound intensity / soundstage width (0.0 to 1.0)
  static Future<void> setIntensity(double value) async {
    _intensity = value.clamp(0.0, 1.0);
    await StorageService.set3dSoundIntensity(_intensity);
    await apply();
  }

  /// Applies the 3D Virtualizer settings to the native hardware audio pipeline
  static Future<void> apply() async {
    try {
      await _channel.invokeMethod('setVirtual3dSound', {
        'enabled': _isEnabled,
        'strength': _intensity,
        'mode': _currentMode,
      });
    } catch (e) {
      debugPrint('Failed to apply 3D Spatial Audio: $e');
    }
  }
}
