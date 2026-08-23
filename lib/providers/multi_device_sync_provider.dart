import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync/multi_device_discovery_service.dart';
import '../services/sync/multi_device_sync_service.dart';
import 'playback_provider.dart';

class MultiDeviceSyncState {
  final List<DiscoveredDevice> discoveredDevices;
  final SyncGroupSession session;
  final bool isDiscovering;
  final String localDeviceId;
  final String localDeviceName;

  const MultiDeviceSyncState({
    this.discoveredDevices = const [],
    this.session = const SyncGroupSession(),
    this.isDiscovering = false,
    this.localDeviceId = '',
    this.localDeviceName = '',
  });

  MultiDeviceSyncState copyWith({
    List<DiscoveredDevice>? discoveredDevices,
    SyncGroupSession? session,
    bool? isDiscovering,
    String? localDeviceId,
    String? localDeviceName,
  }) {
    return MultiDeviceSyncState(
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      session: session ?? this.session,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      localDeviceId: localDeviceId ?? this.localDeviceId,
      localDeviceName: localDeviceName ?? this.localDeviceName,
    );
  }
}

class MultiDeviceSyncNotifier extends Notifier<MultiDeviceSyncState> {
  final MultiDeviceDiscoveryService _discoveryService = MultiDeviceDiscoveryService();
  final MultiDeviceSyncService _syncService = MultiDeviceSyncService.instance;

  StreamSubscription<List<DiscoveredDevice>>? _discoverySub;
  StreamSubscription<SyncGroupSession>? _sessionSub;

  @override
  MultiDeviceSyncState build() {
    final deviceId = 'aura_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final deviceName = 'Aura ${Platform.operatingSystem.toUpperCase()} (${Platform.localHostname})';

    _discoverySub = _discoveryService.onDiscoveredDevicesChanged.listen((devices) {
      state = state.copyWith(discoveredDevices: devices);
    });

    _sessionSub = _syncService.onSessionChanged.listen((session) {
      state = state.copyWith(session: session);
    });

    // Wire up follower callbacks to PlaybackProvider
    _syncService.onFollowerPlayRequested = (track, position) async {
      final notifier = ref.read(playbackProvider.notifier);
      final currentState = ref.read(playbackProvider);

      if (currentState.currentTrack?.id == track.id) {
        final diff = (currentState.currentPosition - position).inMilliseconds.abs();
        if (diff > 2500) {
          notifier.seekToDuration(position);
        }
        if (!currentState.isPlaying) {
          notifier.resumePlayback();
        }
      } else {
        notifier.playTrack(track);
        Future.delayed(const Duration(milliseconds: 300), () {
          notifier.seekToDuration(position);
        });
      }
    };

    _syncService.onFollowerPauseRequested = () async {
      ref.read(playbackProvider.notifier).pause();
    };

    _syncService.onFollowerSeekRequested = (position) async {
      final currentState = ref.read(playbackProvider);
      final diff = (currentState.currentPosition - position).inMilliseconds.abs();
      if (diff > 1500) {
        ref.read(playbackProvider.notifier).seekToDuration(position);
      }
    };

    _syncService.onFollowerSpeedNudgeRequested = (speed) async {
      ref.read(playbackProvider.notifier).setPlaybackSpeed(speed);
    };

    ref.onDispose(() {
      _discoverySub?.cancel();
      _sessionSub?.cancel();
      _discoveryService.stopDiscovery();
    });

    return MultiDeviceSyncState(
      localDeviceId: deviceId,
      localDeviceName: deviceName,
    );
  }

  Future<void> startDiscovery() async {
    state = state.copyWith(isDiscovering: true);
    await _discoveryService.startDiscovery(
      deviceId: state.localDeviceId,
      deviceName: state.localDeviceName,
      tcpPort: MultiDeviceDiscoveryService.defaultTcpPort,
    );
  }

  void stopDiscovery() {
    _discoveryService.stopDiscovery();
    state = state.copyWith(isDiscovering: false);
  }

  Future<void> startHostSession() async {
    await startDiscovery();
    await _syncService.startHostSession(
      localDeviceId: state.localDeviceId,
      localDeviceName: state.localDeviceName,
      port: MultiDeviceDiscoveryService.defaultTcpPort,
    );
  }

  Future<bool> joinGroup(DiscoveredDevice device) async {
    final success = await _syncService.joinHostSession(
      hostIp: device.ipAddress,
      hostPort: device.tcpPort,
      localDeviceId: state.localDeviceId,
      localDeviceName: state.localDeviceName,
    );
    return success;
  }

  Future<void> leaveGroup() async {
    await _syncService.stopSession();
  }
}

final multiDeviceSyncProvider =
    NotifierProvider<MultiDeviceSyncNotifier, MultiDeviceSyncState>(
  MultiDeviceSyncNotifier.new,
);
