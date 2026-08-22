import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/sync/multi_device_discovery_service.dart';
import 'package:music_app/services/sync/multi_device_sync_service.dart';
import 'package:music_app/services/audio/audio_routing_service.dart';

void main() {
  group('MultiDeviceDiscoveryService Tests', () {
    test('DiscoveredDevice JSON serialization and deserialization works correctly', () {
      final json = {
        'deviceId': 'aura_test_123',
        'deviceName': 'Living Room Phone',
        'tcpPort': 8766,
        'platform': 'android',
      };

      final device = DiscoveredDevice.fromJson(json, '192.168.1.105');

      expect(device.deviceId, equals('aura_test_123'));
      expect(device.deviceName, equals('Living Room Phone'));
      expect(device.ipAddress, equals('192.168.1.105'));
      expect(device.tcpPort, equals(8766));
      expect(device.platform, equals('android'));
    });
  });

  group('SyncGroupSession Tests', () {
    test('Default SyncGroupSession starts in standalone mode', () {
      const session = SyncGroupSession();
      expect(session.role, equals(SyncRole.standalone));
      expect(session.isHost, isFalse);
      expect(session.isFollower, isFalse);
      expect(session.isInGroup, isFalse);
      expect(session.syncedCount, equals(0));
    });

    test('Host session properties resolve correctly', () {
      const session = SyncGroupSession(
        role: SyncRole.host,
        hostDeviceId: 'aura_host_1',
        hostDeviceName: 'My iPad',
        connectedDeviceNames: ['Phone A', 'Speaker B'],
        syncedCount: 2,
      );

      expect(session.isHost, isTrue);
      expect(session.isInGroup, isTrue);
      expect(session.syncedCount, equals(2));
      expect(session.connectedDeviceNames.length, equals(2));
    });
  });

  group('AudioRoutingService Model Tests', () {
    test('AudioOutputDevice maps device types properly', () {
      final bluetoothMap = {
        'id': 'bt_headset_1',
        'name': 'AirPods Pro',
        'type': 'bluetooth',
        'isActive': true,
      };

      final device = AudioOutputDevice.fromMap(bluetoothMap);

      expect(device.id, equals('bt_headset_1'));
      expect(device.name, equals('AirPods Pro'));
      expect(device.type, equals(AudioDeviceType.bluetooth));
      expect(device.isActive, isTrue);
    });
  });
}
