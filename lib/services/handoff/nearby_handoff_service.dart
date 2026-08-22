import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';

class DiscoveredDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String title;
  final int trackCount;
  final DateTime lastSeen;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.title,
    required this.trackCount,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
    'title': title,
    'trackCount': trackCount,
    'lastSeen': lastSeen.toIso8601String(),
  };
}

class HandoffPayload {
  final String senderName;
  final String title;
  final int currentIndex;
  final List<Track> tracks;
  final String timestamp;

  HandoffPayload({
    required this.senderName,
    required this.title,
    required this.currentIndex,
    required this.tracks,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'senderName': senderName,
    'title': title,
    'currentIndex': currentIndex,
    'tracks': tracks.map((t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'duration': t.duration,
      'artworkUrl': t.artworkUrl,
      'audioUrl': t.audioUrl,
      'genre': t.genre,
    }).toList(),
    'timestamp': timestamp,
  };

  factory HandoffPayload.fromJson(Map<String, dynamic> json) {
    final rawList = json['tracks'] as List? ?? [];
    final tracksList = rawList.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return Track(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Track',
        artist: map['artist']?.toString() ?? 'Unknown Artist',
        album: map['album']?.toString() ?? 'Album',
        duration: map['duration']?.toString() ?? '3:30',
        artworkUrl: map['artworkUrl']?.toString() ?? '',
        audioUrl: map['audioUrl']?.toString() ?? '',
        genre: map['genre']?.toString() ?? '',
      );
    }).toList();

    return HandoffPayload(
      senderName: json['senderName']?.toString() ?? 'Nearby Device',
      title: json['title']?.toString() ?? 'Queue Handoff',
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      tracks: tracksList,
      timestamp: json['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}

class NearbyHandoffService {
  NearbyHandoffService._();
  static final NearbyHandoffService instance = NearbyHandoffService._();

  static const int udpDiscoveryPort = 8898;
  static const int defaultHttpPort = 8899;

  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  Timer? _pruneTimer;

  bool _isBroadcasting = false;
  HandoffPayload? _activePayload;
  String? _localIp;

  final Map<String, DiscoveredDevice> _discoveredMap = {};
  final StreamController<List<DiscoveredDevice>> _discoveredController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  Stream<List<DiscoveredDevice>> get discoveredDevicesStream =>
      _discoveredController.stream;

  bool get isBroadcasting => _isBroadcasting;
  HandoffPayload? get activePayload => _activePayload;
  String? get localIp => _localIp;
  int get serverPort => _server?.port ?? defaultHttpPort;

  String get deviceName {
    final stored = StorageService.getUserName();
    if (stored.isNotEmpty) return stored;
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Aura Device';
    }
  }

  /// Start P2P Receiver Listening (Discovery)
  Future<void> startDiscovery() async {
    _localIp = await _getLocalIpAddress();
    await _initUdpDiscoveryListener();
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pruneStaleDevices();
    });
  }

  /// Stop P2P Receiver Listening
  void stopDiscovery() {
    _pruneTimer?.cancel();
    _discoveredMap.clear();
    _discoveredController.add([]);
  }

  /// Start P2P Sender Broadcasting
  Future<void> startBroadcasting(HandoffPayload payload) async {
    _activePayload = payload;
    _localIp = await _getLocalIpAddress();

    await _startHttpServer();
    await _initUdpDiscoveryListener();

    _isBroadcasting = true;
    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendUdpBeacon();
    });

    _sendUdpBeacon();
    debugPrint('[NearbyHandoff] Broadcasting active: "${payload.title}" on port $serverPort');
  }

  /// Stop P2P Sender Broadcasting
  Future<void> stopBroadcasting() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _isBroadcasting = false;
    _activePayload = null;

    await _server?.close(force: true);
    _server = null;
    debugPrint('[NearbyHandoff] Stopped broadcasting');
  }

  /// Generate QR Code payload string for camera scanner fallback
  String getQrConnectionUrl() {
    final ip = _localIp ?? '127.0.0.1';
    final port = serverPort;
    return 'aura-handoff://$ip:$port/payload';
  }

  /// Fetch handoff payload directly from a sender IP/port
  Future<HandoffPayload?> fetchPayloadFromAddress(String ip, int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('http://$ip:$port/handoff/payload'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        return HandoffPayload.fromJson(jsonMap);
      }
    } catch (e) {
      debugPrint('[NearbyHandoff] Error fetching payload from $ip:$port -> $e');
    }
    return null;
  }

  /// Start HTTP server to serve payload to receivers
  Future<void> _startHttpServer() async {
    await _server?.close(force: true);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, defaultHttpPort);
    } catch (_) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0); // Dynamic fallback port
    }

    _server?.listen((HttpRequest request) async {
      final path = request.uri.path;
      if (path == '/handoff/payload' || path == '/payload') {
        request.response.headers.contentType = ContentType.json;
        if (_activePayload != null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode(_activePayload!.toJson()));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'error': 'No active handoff payload'}));
        }
      } else if (path == '/handoff/ping') {
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({'status': 'online', 'device': deviceName}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  }

  /// Init UDP Socket for broadcast beacon sending & listening
  Future<void> _initUdpDiscoveryListener() async {
    if (_udpSocket != null) return;
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram);
          }
        }
      });
    } catch (e) {
      debugPrint('[NearbyHandoff] Error setting up UDP socket: $e');
    }
  }

  /// Broadcast UDP Datagram to local network
  void _sendUdpBeacon() {
    if (_udpSocket == null || _activePayload == null) return;

    final ip = _localIp ?? '127.0.0.1';
    final beaconStr = [
      'AURA_HANDOFF_BEACON',
      deviceName,
      ip,
      serverPort.toString(),
      _activePayload!.title,
      _activePayload!.tracks.length.toString(),
      DateTime.now().millisecondsSinceEpoch.toString(),
    ].join('|');

    final data = utf8.encode(beaconStr);

    try {
      _udpSocket!.send(data, InternetAddress('255.255.255.255'), udpDiscoveryPort);
    } catch (e) {
      debugPrint('[NearbyHandoff] Error sending broadcast beacon: $e');
    }
  }

  /// Handle incoming UDP datagram from another device
  void _handleIncomingDatagram(Datagram datagram) {
    try {
      final msg = utf8.decode(datagram.data);
      if (!msg.startsWith('AURA_HANDOFF_BEACON')) return;

      final parts = msg.split('|');
      if (parts.length < 6) return;

      final name = parts[1];
      final ip = parts[2];
      final port = int.tryParse(parts[3]) ?? defaultHttpPort;
      final title = parts[4];
      final count = int.tryParse(parts[5]) ?? 0;

      // Ignore self beacon
      if (ip == _localIp) return;

      final id = '$ip:$port';
      final device = DiscoveredDevice(
        id: id,
        name: name,
        ip: ip,
        port: port,
        title: title,
        trackCount: count,
        lastSeen: DateTime.now(),
      );

      _discoveredMap[id] = device;
      _discoveredController.add(_discoveredMap.values.toList());
    } catch (e) {
      debugPrint('[NearbyHandoff] Error handling datagram: $e');
    }
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    bool changed = false;
    _discoveredMap.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen).inSeconds > 8;
      if (isStale) changed = true;
      return isStale;
    });
    if (changed) {
      _discoveredController.add(_discoveredMap.values.toList());
    }
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('[NearbyHandoff] Error finding IP: $e');
    }
    return '127.0.0.1';
  }

  void dispose() {
    stopBroadcasting();
    stopDiscovery();
    _udpSocket?.close();
    _udpSocket = null;
    _discoveredController.close();
  }
}
