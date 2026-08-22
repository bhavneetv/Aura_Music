import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../models/track.dart';

enum SyncRole {
  standalone,
  host,
  follower,
}

class ConnectedFollower {
  final Socket socket;
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  int pingMs;
  DateTime lastHeartbeat;

  ConnectedFollower({
    required this.socket,
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    this.pingMs = 0,
    required this.lastHeartbeat,
  });
}

class SyncGroupSession {
  final SyncRole role;
  final String hostDeviceId;
  final String hostDeviceName;
  final List<String> connectedDeviceNames;
  final int syncedCount;
  final double currentSpeedNudge;
  final int lastDriftMs;

  const SyncGroupSession({
    this.role = SyncRole.standalone,
    this.hostDeviceId = '',
    this.hostDeviceName = '',
    this.connectedDeviceNames = const [],
    this.syncedCount = 0,
    this.currentSpeedNudge = 1.0,
    this.lastDriftMs = 0,
  });

  bool get isHost => role == SyncRole.host;
  bool get isFollower => role == SyncRole.follower;
  bool get isInGroup => role != SyncRole.standalone;
}

class MultiDeviceSyncService {
  MultiDeviceSyncService._internal();
  static final MultiDeviceSyncService instance = MultiDeviceSyncService._internal();

  SyncRole _role = SyncRole.standalone;
  SyncRole get role => _role;

  ServerSocket? _hostServer;
  final Map<String, ConnectedFollower> _connectedFollowers = {};

  Socket? _followerSocket;
  Timer? _beaconTimer;
  Timer? _pingTimer;

  // Follower drift state
  double _currentSpeedFactor = 1.0;
  int _lastDriftMs = 0;
  String _hostDeviceId = '';
  String _hostDeviceName = '';

  // Callbacks injected by playback handler / provider
  Future<void> Function(Track track, Duration position)? onFollowerPlayRequested;
  Future<void> Function()? onFollowerPauseRequested;
  Future<void> Function(Duration position)? onFollowerSeekRequested;
  Future<void> Function(double speed)? onFollowerSpeedNudgeRequested;

  final StreamController<SyncGroupSession> _sessionController =
      StreamController<SyncGroupSession>.broadcast();
  Stream<SyncGroupSession> get onSessionChanged => _sessionController.stream;

  SyncGroupSession _currentSession = const SyncGroupSession();
  SyncGroupSession get currentSession => _currentSession;

  // ── Host Methods ─────────────────────────────────────────────

  Future<void> startHostSession({
    required String localDeviceId,
    required String localDeviceName,
    required int port,
  }) async {
    if (_role == SyncRole.host) return;

    await stopSession();

    _role = SyncRole.host;
    _hostDeviceId = localDeviceId;
    _hostDeviceName = localDeviceName;

    try {
      _hostServer = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _hostServer?.listen(_handleIncomingFollowerConnection);

      // Start periodic position beaconing every 1.5 seconds for low-latency sync
      _beaconTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        _sendHostPositionBeacon();
      });

      _updateSessionState();
    } catch (e) {
      print('[MULTI-DEVICE-SYNC] Host server error: $e');
      await stopSession();
    }
  }

  void _handleIncomingFollowerConnection(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true); // Low latency TCP

    String? followerId;

    socket.listen(
      (data) {
        try {
          final rawMsg = utf8.decode(data);
          final lines = rawMsg.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            final json = jsonDecode(line.trim());
            if (json is Map<String, dynamic>) {
              final type = json['type'] as String?;
              if (type == 'JOIN_GROUP') {
                followerId = json['deviceId'] as String? ?? socket.remoteAddress.address;
                final name = json['deviceName'] as String? ?? 'Follower';
                _connectedFollowers[followerId!] = ConnectedFollower(
                  socket: socket,
                  deviceId: followerId!,
                  deviceName: name,
                  ipAddress: socket.remoteAddress.address,
                  lastHeartbeat: DateTime.now(),
                );
                _updateSessionState();
              } else if (type == 'PONG') {
                if (followerId != null && _connectedFollowers.containsKey(followerId)) {
                  final sentTime = json['sentTimestamp'] as int?;
                  if (sentTime != null) {
                    final rtt = DateTime.now().millisecondsSinceEpoch - sentTime;
                    _connectedFollowers[followerId!]?.pingMs = (rtt / 2).round();
                  }
                }
              }
            }
          }
        } catch (_) {}
      },
      onError: (_) {
        if (followerId != null) {
          _connectedFollowers.remove(followerId);
          _updateSessionState();
        }
      },
      onDone: () {
        if (followerId != null) {
          _connectedFollowers.remove(followerId);
          _updateSessionState();
        }
      },
    );
  }

  void broadcastPlay(Track track, Duration position) {
    if (_role != SyncRole.host) return;

    final payload = jsonEncode({
      'type': 'SYNC_PLAY',
      'track': track.toJson(),
      'positionMs': position.inMilliseconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }) + '\n';

    _sendToAllFollowers(payload);
  }

  void broadcastPause(Duration position) {
    if (_role != SyncRole.host) return;

    final payload = jsonEncode({
      'type': 'SYNC_PAUSE',
      'positionMs': position.inMilliseconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }) + '\n';

    _sendToAllFollowers(payload);
  }

  void broadcastSeek(Duration position) {
    if (_role != SyncRole.host) return;

    final payload = jsonEncode({
      'type': 'SYNC_SEEK',
      'positionMs': position.inMilliseconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }) + '\n';

    _sendToAllFollowers(payload);
  }

  void _sendHostPositionBeacon() {
    if (_role != SyncRole.host || _connectedFollowers.isEmpty) return;

    // This will be called with updated info via notifyHostPosition
  }

  void notifyHostPosition({
    required Duration position,
    required bool isPlaying,
    required Track? currentTrack,
  }) {
    if (_role != SyncRole.host || _connectedFollowers.isEmpty) return;

    final payload = jsonEncode({
      'type': 'POSITION_BEACON',
      'positionMs': position.inMilliseconds,
      'isPlaying': isPlaying,
      'trackId': currentTrack?.id,
      'hostTimestamp': DateTime.now().millisecondsSinceEpoch,
    }) + '\n';

    _sendToAllFollowers(payload);
  }

  void _sendToAllFollowers(String payload) {
    final bytes = utf8.encode(payload);
    _connectedFollowers.forEach((id, follower) {
      try {
        follower.socket.add(bytes);
      } catch (_) {
        _connectedFollowers.remove(id);
      }
    });
  }

  // ── Follower Methods ─────────────────────────────────────────

  Future<bool> joinHostSession({
    required String hostIp,
    required int hostPort,
    required String localDeviceId,
    required String localDeviceName,
  }) async {
    await stopSession();

    try {
      _followerSocket = await Socket.connect(hostIp, hostPort, timeout: const Duration(seconds: 4));
      _followerSocket?.setOption(SocketOption.tcpNoDelay, true); // Low latency TCP

      _role = SyncRole.follower;

      // Send JOIN payload
      final joinPayload = jsonEncode({
        'type': 'JOIN_GROUP',
        'deviceId': localDeviceId,
        'deviceName': localDeviceName,
      }) + '\n';

      _followerSocket?.add(utf8.encode(joinPayload));

      _followerSocket?.listen(
        _handleIncomingHostMessage,
        onError: (_) => stopSession(),
        onDone: () => stopSession(),
      );

      _updateSessionState();
      return true;
    } catch (e) {
      print('[MULTI-DEVICE-SYNC] Follower connection failed: $e');
      await stopSession();
      return false;
    }
  }

  void _handleIncomingHostMessage(List<int> data) {
    try {
      final raw = utf8.decode(data);
      final lines = raw.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final json = jsonDecode(line.trim());
        if (json is Map<String, dynamic>) {
          final type = json['type'] as String?;

          switch (type) {
            case 'SYNC_PLAY':
              _handleSyncPlay(json);
              break;
            case 'SYNC_PAUSE':
              onFollowerPauseRequested?.call();
              break;
            case 'SYNC_SEEK':
              final posMs = json['positionMs'] as int? ?? 0;
              onFollowerSeekRequested?.call(Duration(milliseconds: posMs));
              break;
            case 'POSITION_BEACON':
              _handlePositionBeacon(json);
              break;
          }
        }
      }
    } catch (e) {
      print('[MULTI-DEVICE-SYNC] Follower msg decode error: $e');
    }
  }

  void _handleSyncPlay(Map<String, dynamic> json) {
    try {
      final trackMap = json['track'] as Map<String, dynamic>?;
      final posMs = json['positionMs'] as int? ?? 0;
      final hostTime = json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      if (trackMap != null) {
        final track = Track.fromJson(trackMap);
        final elapsedSinceHostSend = DateTime.now().millisecondsSinceEpoch - hostTime;
        final adjustedPos = Duration(milliseconds: posMs + elapsedSinceHostSend.clamp(0, 500));

        onFollowerPlayRequested?.call(track, adjustedPos);
      }
    } catch (e) {
      print('[MULTI-DEVICE-SYNC] Error handling SYNC_PLAY: $e');
    }
  }

  /// Ultra-low latency micro-drift calculation and speed nudging
  void _handlePositionBeacon(Map<String, dynamic> json) {
    final hostPosMs = json['positionMs'] as int? ?? 0;
    final isPlaying = json['isPlaying'] as bool? ?? false;
    final hostTimestamp = json['hostTimestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    if (!isPlaying) {
      _currentSpeedFactor = 1.0;
      onFollowerSpeedNudgeRequested?.call(1.0);
      return;
    }

    final localNow = DateTime.now().millisecondsSinceEpoch;
    final latency = (localNow - hostTimestamp).clamp(0, 300);
    final estimatedHostPos = hostPosMs + latency;

    // Call drift calculator logic
    onFollowerPositionBeaconReceived(estimatedHostPos);
  }

  void onFollowerPositionBeaconReceived(int estimatedHostPosMs, {int currentFollowerPosMs = 0}) {
    if (_role != SyncRole.follower) return;

    final driftMs = estimatedHostPosMs - currentFollowerPosMs;
    _lastDriftMs = driftMs;

    double targetSpeed = 1.0;

    if (driftMs.abs() > 1500) {
      // Large drift: Hard seek to host position
      onFollowerSeekRequested?.call(Duration(milliseconds: estimatedHostPosMs));
      targetSpeed = 1.0;
    } else if (driftMs > 80) {
      // Follower is behind: micro speed up (1.02x)
      targetSpeed = 1.02;
    } else if (driftMs < -80) {
      // Follower is ahead: micro slow down (0.98x)
      targetSpeed = 0.98;
    } else {
      // In tight sync (< 80ms difference)
      targetSpeed = 1.0;
    }

    if (_currentSpeedFactor != targetSpeed) {
      _currentSpeedFactor = targetSpeed;
      onFollowerSpeedNudgeRequested?.call(targetSpeed);
    }

    _updateSessionState();
  }

  // ── Session Control ──────────────────────────────────────────

  Future<void> stopSession() async {
    _beaconTimer?.cancel();
    _pingTimer?.cancel();
    _beaconTimer = null;
    _pingTimer = null;

    _connectedFollowers.forEach((_, follower) {
      try {
        follower.socket.close();
      } catch (_) {}
    });
    _connectedFollowers.clear();

    try {
      await _hostServer?.close();
    } catch (_) {}
    _hostServer = null;

    try {
      await _followerSocket?.close();
    } catch (_) {}
    _followerSocket = null;

    _role = SyncRole.standalone;
    _currentSpeedFactor = 1.0;
    _lastDriftMs = 0;

    _updateSessionState();
  }

  void _updateSessionState() {
    final names = _connectedFollowers.values.map((f) => f.deviceName).toList();
    _currentSession = SyncGroupSession(
      role: _role,
      hostDeviceId: _hostDeviceId,
      hostDeviceName: _hostDeviceName,
      connectedDeviceNames: names,
      syncedCount: _role == SyncRole.host ? _connectedFollowers.length : (_role == SyncRole.follower ? 1 : 0),
      currentSpeedNudge: _currentSpeedFactor,
      lastDriftMs: _lastDriftMs,
    );

    _sessionController.add(_currentSession);
  }
}
