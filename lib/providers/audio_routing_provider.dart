import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio/audio_routing_service.dart';

class AudioRoutingState {
  final List<AudioOutputDevice> availableDevices;
  final AudioOutputDevice? activeDevice;
  final bool isLoading;

  const AudioRoutingState({
    this.availableDevices = const [],
    this.activeDevice,
    this.isLoading = false,
  });

  AudioRoutingState copyWith({
    List<AudioOutputDevice>? availableDevices,
    AudioOutputDevice? activeDevice,
    bool? isLoading,
  }) {
    return AudioRoutingState(
      availableDevices: availableDevices ?? this.availableDevices,
      activeDevice: activeDevice ?? this.activeDevice,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AudioRoutingNotifier extends Notifier<AudioRoutingState> {
  StreamSubscription<List<AudioOutputDevice>>? _routeSubscription;

  @override
  AudioRoutingState build() {
    _init();

    ref.onDispose(() {
      _routeSubscription?.cancel();
    });

    return const AudioRoutingState(isLoading: true);
  }

  Future<void> _init() async {
    final devices = await AudioRoutingService.instance.getAvailableAudioOutputs();
    final active = devices.firstWhere(
      (d) => d.isActive,
      orElse: () => devices.isNotEmpty
          ? devices.first
          : const AudioOutputDevice(
              id: 'default',
              name: 'Default Output',
              type: AudioDeviceType.speaker,
              isActive: true,
            ),
    );

    state = state.copyWith(
      availableDevices: devices,
      activeDevice: active,
      isLoading: false,
    );

    _routeSubscription = AudioRoutingService.instance.onRouteChanged.listen((devices) {
      final activeDev = devices.firstWhere(
        (d) => d.isActive,
        orElse: () => devices.isNotEmpty ? devices.first : active,
      );

      state = state.copyWith(
        availableDevices: devices,
        activeDevice: activeDev,
      );
    });
  }

  Future<void> refreshDevices() async {
    final devices = await AudioRoutingService.instance.getAvailableAudioOutputs();
    final active = devices.firstWhere(
      (d) => d.isActive,
      orElse: () => state.activeDevice ?? devices.first,
    );
    state = state.copyWith(
      availableDevices: devices,
      activeDevice: active,
    );
  }

  Future<bool> selectDevice(AudioOutputDevice device) async {
    state = state.copyWith(isLoading: true);
    final success = await AudioRoutingService.instance.selectAudioOutput(device);
    await refreshDevices();
    state = state.copyWith(isLoading: false);
    return success;
  }
}

final audioRoutingProvider =
    NotifierProvider<AudioRoutingNotifier, AudioRoutingState>(
  AudioRoutingNotifier.new,
);
