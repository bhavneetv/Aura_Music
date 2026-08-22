import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/audio_routing_provider.dart';
import '../providers/multi_device_sync_provider.dart';
import '../providers/customization_provider.dart';
import '../services/audio/audio_routing_service.dart';

void showAudioOutputPickerModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AudioOutputPickerModal(),
  );
}

class AudioOutputPickerModal extends ConsumerStatefulWidget {
  const AudioOutputPickerModal({super.key});

  @override
  ConsumerState<AudioOutputPickerModal> createState() => _AudioOutputPickerModalState();
}

class _AudioOutputPickerModalState extends ConsumerState<AudioOutputPickerModal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(multiDeviceSyncProvider.notifier).startDiscovery();
      ref.read(audioRoutingProvider.notifier).refreshDevices();
    });
  }

  IconData _getDeviceIcon(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.speaker:
        return Icons.volume_up_rounded;
      case AudioDeviceType.earpiece:
        return Icons.phone_in_talk_rounded;
      case AudioDeviceType.wiredHeadset:
        return Icons.headphones_rounded;
      case AudioDeviceType.bluetooth:
        return Icons.bluetooth_audio_rounded;
      case AudioDeviceType.airplay:
        return Icons.airplay_rounded;
      case AudioDeviceType.chromecast:
        return Icons.cast_rounded;
      default:
        return Icons.speaker_group_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final routingState = ref.watch(audioRoutingProvider);
    final syncState = ref.watch(multiDeviceSyncProvider);
    final syncNotifier = ref.read(multiDeviceSyncProvider.notifier);
    final routingNotifier = ref.read(audioRoutingProvider.notifier);
    final accentColor = ref.watch(customizationProvider).accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeDevice = routingState.activeDevice;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E22).withOpacity(0.92) : Colors.white.withOpacity(0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.devices_other_rounded, color: accentColor, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Audio Output & Multi-Room',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 1: Local Device Routing
            Text(
              'LOCAL OUTPUT ROUTE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 10),

            if (routingState.isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else
              Column(
                children: [
                  ...routingState.availableDevices.map((dev) {
                    final isActive = dev.isActive || (activeDevice?.id == dev.id);
                    return InkWell(
                      onTap: () {
                        routingNotifier.selectDevice(dev);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? accentColor.withOpacity(0.15)
                              : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive ? accentColor : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(_getDeviceIcon(dev.type), color: isActive ? accentColor : Colors.grey),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                dev.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            if (isActive)
                              Icon(Icons.check_circle_rounded, color: accentColor, size: 20)
                          ],
                        ),
                      ),
                    );
                  }),

                  // iOS Native AVRoutePickerView Embedded Control
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: accentColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.airplay_rounded, size: 20, color: accentColor),
                          const SizedBox(width: 8),
                          Text(
                            'AirPlay / Bluetooth System Picker',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accentColor),
                          ),
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: UiKitView(
                              viewType: 'com.example.music_app/av_route_picker_view',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Section 2: Multi-Device Synced Playback ("Play on Multiple Devices")
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLAY ON MULTIPLE DEVICES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ultra-Low Latency Peer-to-Peer Sync',
                      style: TextStyle(
                        fontSize: 11,
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                if (!syncState.session.isInGroup)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: const Text('Host Sync Group', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () {
                      syncNotifier.startHostSession();
                    },
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.exit_to_app_rounded, size: 16, color: Colors.redAccent),
                    label: const Text('Leave Group', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    onPressed: () {
                      syncNotifier.leaveGroup();
                    },
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Active Group Banner
            if (syncState.session.isInGroup) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(
                      syncState.session.isHost ? Icons.podcasts_rounded : Icons.sync_rounded,
                      color: accentColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            syncState.session.isHost
                                ? 'Hosting Sync Group (${syncState.session.syncedCount} followers)'
                                : 'Synced with Host (${syncState.session.hostDeviceName})',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                          ),
                          Text(
                            syncState.session.isHost
                                ? 'Followers: ${syncState.session.connectedDeviceNames.join(", ")}'
                                : 'Low latency drift: ${syncState.session.lastDriftMs}ms (${syncState.session.currentSpeedNudge}x speed)',
                            style: TextStyle(fontSize: 11, color: (isDark ? Colors.white : Colors.black).withOpacity(0.7)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Discovered Nearby Devices List
            Text(
              'Discovered Nearby Devices on Wi-Fi:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 8),

            if (syncState.discoveredDevices.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Searching for nearby Aura devices on same Wi-Fi...',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: syncState.discoveredDevices.map((device) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          device.platform.contains('ios') ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                          color: accentColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.deviceName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                '${device.ipAddress}:${device.tcpPort}',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor.withOpacity(0.2),
                            foregroundColor: accentColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            syncNotifier.joinGroup(device);
                          },
                          child: const Text('Connect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
