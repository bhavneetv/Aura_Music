import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

enum AudioDeviceType {
  speaker,
  earpiece,
  wiredHeadset,
  bluetooth,
  airplay,
  chromecast,
  unknown,
}

class AudioOutputDevice {
  final dynamic id;
  final String name;
  final AudioDeviceType type;
  final bool isActive;
  final int? rawType;

  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isActive = false,
    this.rawType,
  });

  factory AudioOutputDevice.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = (map['type'] as String?)?.toLowerCase() ?? 'unknown';
    AudioDeviceType resolvedType;
    switch (typeStr) {
      case 'speaker':
        resolvedType = AudioDeviceType.speaker;
        break;
      case 'earpiece':
        resolvedType = AudioDeviceType.earpiece;
        break;
      case 'headset':
      case 'wired_headset':
        resolvedType = AudioDeviceType.wiredHeadset;
        break;
      case 'bluetooth':
        resolvedType = AudioDeviceType.bluetooth;
        break;
      case 'airplay':
        resolvedType = AudioDeviceType.airplay;
        break;
      case 'chromecast':
        resolvedType = AudioDeviceType.chromecast;
        break;
      default:
        resolvedType = AudioDeviceType.unknown;
    }

    return AudioOutputDevice(
      id: map['id'],
      name: map['name'] as String? ?? 'Audio Output',
      type: resolvedType,
      isActive: map['isActive'] as bool? ?? false,
      rawType: map['rawType'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'isActive': isActive,
      'rawType': rawType,
    };
  }
}

class AudioRoutingService {
  AudioRoutingService._internal() {
    _initEventStream();
  }
  static final AudioRoutingService instance = AudioRoutingService._internal();

  static const MethodChannel _methodChannel =
      MethodChannel('com.example.music_app/audio_routing');
  static const EventChannel _eventChannel =
      EventChannel('com.example.music_app/audio_routing_events');

  final StreamController<List<AudioOutputDevice>> _routeController =
      StreamController<List<AudioOutputDevice>>.broadcast();

  Stream<List<AudioOutputDevice>> get onRouteChanged => _routeController.stream;

  List<AudioOutputDevice> _cachedDevices = [];
  List<AudioOutputDevice> get cachedDevices => List.unmodifiable(_cachedDevices);

  void _initEventStream() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is List) {
          final devices = data
              .whereType<Map<dynamic, dynamic>>()
              .map((map) => AudioOutputDevice.fromMap(map))
              .toList();
          _cachedDevices = devices;
          _routeController.add(devices);
        }
      },
      onError: (dynamic error) {
        print('[AUDIO-ROUTING-SERVICE] Stream error: $error');
      },
    );
  }

  Future<List<AudioOutputDevice>> getAvailableAudioOutputs() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return [
        const AudioOutputDevice(
          id: 'default_speaker',
          name: 'System Audio Speaker',
          type: AudioDeviceType.speaker,
          isActive: true,
        )
      ];
    }

    try {
      final List<dynamic>? res =
          await _methodChannel.invokeMethod('getAvailableAudioOutputs');
      if (res != null) {
        final devices = res
            .whereType<Map<dynamic, dynamic>>()
            .map((map) => AudioOutputDevice.fromMap(map))
            .toList();
        _cachedDevices = devices;
        return devices;
      }
    } on PlatformException catch (e) {
      print('[AUDIO-ROUTING-SERVICE] getAvailableAudioOutputs error: $e');
    }
    return _cachedDevices;
  }

  Future<bool> selectAudioOutput(AudioOutputDevice device) async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    try {
      final bool? success = await _methodChannel.invokeMethod('selectAudioOutput', {
        'id': device.id,
        'type': device.type.name,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      print('[AUDIO-ROUTING-SERVICE] selectAudioOutput error: $e');
      return false;
    }
  }

  Future<bool> resetToDefaultRoute() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    try {
      final bool? success = await _methodChannel.invokeMethod('resetToDefaultRoute');
      return success ?? false;
    } on PlatformException catch (e) {
      print('[AUDIO-ROUTING-SERVICE] resetToDefaultRoute error: $e');
      return false;
    }
  }
}
