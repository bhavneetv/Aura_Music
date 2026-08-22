import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredDevice {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final int tcpPort;
  final String platform;
  final DateTime lastSeen;

  DiscoveredDevice({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.tcpPort,
    required this.platform,
    required this.lastSeen,
  });

  DiscoveredDevice copyWith({DateTime? lastSeen}) {
    return DiscoveredDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      ipAddress: ipAddress,
      tcpPort: tcpPort,
      platform: platform,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'ipAddress': ipAddress,
        'tcpPort': tcpPort,
        'platform': platform,
      };

  factory DiscoveredDevice.fromJson(Map<String, dynamic> json, String senderIp) {
    return DiscoveredDevice(
      deviceId: json['deviceId'] as String? ?? 'unknown',
      deviceName: json['deviceName'] as String? ?? 'Nearby Aura Device',
      ipAddress: senderIp,
      tcpPort: json['tcpPort'] as int? ?? 8766,
      platform: json['platform'] as String? ?? Platform.operatingSystem,
      lastSeen: DateTime.now(),
    );
  }
}

class MultiDeviceDiscoveryService {
  static const int udpPort = 8765;
  static const int defaultTcpPort = 8766;

  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  final Map<String, DiscoveredDevice> _discoveredMap = {};
  final StreamController<List<DiscoveredDevice>> _deviceStreamController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  Stream<List<DiscoveredDevice>> get onDiscoveredDevicesChanged =>
      _deviceStreamController.stream;

  List<DiscoveredDevice> get currentDiscoveredDevices =>
      _discoveredMap.values.toList();

  String _localDeviceId = '';
  String _localDeviceName = '';
  int _localTcpPort = defaultTcpPort;
  bool _isListening = false;

  Future<void> startDiscovery({
    required String deviceId,
    required String deviceName,
    required int tcpPort,
  }) async {
    if (_isListening) return;

    _localDeviceId = deviceId;
    _localDeviceName = deviceName;
    _localTcpPort = tcpPort;

    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true, reusePort: true);
      _udpSocket?.broadcastEnabled = true;
      _isListening = true;

      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram);
          }
        }
      });

      // Send initial announcement
      _broadcastPresence();

      // Periodic broadcast beacon every 2.5 seconds
      _beaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        _broadcastPresence();
      });

      // Cleanup stale devices (> 8s TTL)
      _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _pruneStaleDevices();
      });
    } catch (e) {
      print('[MULTI-DEVICE-DISCOVERY] Failed to bind UDP socket: $e');
    }
  }

  void stopDiscovery() {
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
    _isListening = false;
    _discoveredMap.clear();
    _deviceStreamController.add([]);
  }

  Future<void> _broadcastPresence() async {
    if (_udpSocket == null || !_isListening) return;

    try {
      final payload = jsonEncode({
        'type': 'AURA_DISCOVERY_BEACON',
        'deviceId': _localDeviceId,
        'deviceName': _localDeviceName,
        'tcpPort': _localTcpPort,
        'platform': Platform.operatingSystem,
      });

      final bytes = utf8.encode(payload);

      final Set<String> targetIps = {'255.255.255.255', '224.0.0.1', '10.0.2.255'};

      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              targetIps.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
            }
          }
        }
      } catch (_) {}

      for (final ip in targetIps) {
        try {
          _udpSocket?.send(bytes, InternetAddress(ip), udpPort);
        } catch (_) {}
      }
    } catch (e) {
      print('[MULTI-DEVICE-DISCOVERY] Error sending beacon: $e');
    }
  }

  void _handleIncomingDatagram(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message);

      if (json is Map<String, dynamic> &&
          json['type'] == 'AURA_DISCOVERY_BEACON') {
        final senderId = json['deviceId'] as String?;
        if (senderId != null && senderId != _localDeviceId) {
          final device = DiscoveredDevice.fromJson(json, datagram.address.address);
          _discoveredMap[senderId] = device;
          _deviceStreamController.add(_discoveredMap.values.toList());
        }
      }
    } catch (_) {
      // Ignore malformed packets
    }
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    final initialCount = _discoveredMap.length;
    _discoveredMap.removeWhere(
      (_, dev) => now.difference(dev.lastSeen).inSeconds > 8,
    );

    if (_discoveredMap.length != initialCount) {
      _deviceStreamController.add(_discoveredMap.values.toList());
    }
  }
}
