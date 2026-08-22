import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/handoff/nearby_handoff_service.dart';
import '../../services/storage/storage_service.dart';
import '../../themes/app_theme.dart';

class NearbyShareScreen extends ConsumerStatefulWidget {
  final List<Track>? customTracks;
  final String? customTitle;

  const NearbyShareScreen({
    super.key,
    this.customTracks,
    this.customTitle,
  });

  static Future<void> showHandoffModal(BuildContext context, {List<Track>? tracks, String? title}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NearbyShareScreen(
        customTracks: tracks,
        customTitle: title,
      ),
    );
  }

  @override
  ConsumerState<NearbyShareScreen> createState() => _NearbyShareScreenState();
}

class _NearbyShareScreenState extends ConsumerState<NearbyShareScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<List<DiscoveredDevice>>? _discoveredSub;
  List<DiscoveredDevice> _discoveredDevices = [];
  bool _isBroadcasting = false;
  final TextEditingController _qrUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _initHandoff();
  }

  Future<void> _initHandoff() async {
    await NearbyHandoffService.instance.startDiscovery();
    _discoveredSub = NearbyHandoffService.instance.discoveredDevicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _discoveredDevices = devices;
        });
      }
    });

    final playback = ref.read(playbackProvider);
    final tracksToShare = widget.customTracks ?? playback.queue;
    final titleToShare = widget.customTitle ??
        (playback.currentTrack != null ? 'Current Queue (${playback.currentTrack!.title})' : 'Aura Queue');

    if (tracksToShare.isNotEmpty) {
      final payload = HandoffPayload(
        senderName: NearbyHandoffService.instance.deviceName,
        title: titleToShare,
        currentIndex: playback.currentIndex.clamp(0, tracksToShare.length - 1),
        tracks: tracksToShare,
        timestamp: DateTime.now().toIso8601String(),
      );

      await NearbyHandoffService.instance.startBroadcasting(payload);
      if (mounted) {
        setState(() {
          _isBroadcasting = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _discoveredSub?.cancel();
    NearbyHandoffService.instance.stopDiscovery();
    _tabController.dispose();
    _qrUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;
    final playback = ref.watch(playbackProvider);

    final tracksToShare = widget.customTracks ?? playback.queue;
    final titleToShare = widget.customTitle ??
        (playback.currentTrack != null ? 'Current Queue (${playback.currentTrack!.title})' : 'Aura Queue');

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle Bar
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),

          // Header Title & Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.share_rounded, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby Share & Handoff',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Serverless P2P Wi-Fi / Bluetooth Queue Transfer',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tab Selector Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.all(4),
              indicator: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.black,
              unselectedLabelColor: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Outfit'),
              tabs: const [
                Tab(
                  height: 38,
                  child: Center(
                    child: Text(
                      'Broadcast & QR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Tab(
                  height: 38,
                  child: Center(
                    child: Text(
                      'Discover Nearby',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBroadcastTab(context, tracksToShare, titleToShare, accentColor, isDark),
                _buildDiscoverTab(context, accentColor, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Broadcast & QR Tab ──────────────────────────────────────────────────
  Widget _buildBroadcastTab(
    BuildContext context,
    List<Track> tracks,
    String title,
    Color accentColor,
    bool isDark,
  ) {
    final qrUrl = NearbyHandoffService.instance.getQrConnectionUrl();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        // Active Status Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                _isBroadcasting ? Icons.wifi_tethering_rounded : Icons.portable_wifi_off_rounded,
                color: accentColor,
                size: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isBroadcasting ? 'Broadcasting Queue on Wi-Fi' : 'Broadcasting Paused',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tracks.length} tracks • "$title"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isBroadcasting,
                activeThumbColor: accentColor,
                onChanged: (val) async {
                  if (val) {
                    final payload = HandoffPayload(
                      senderName: NearbyHandoffService.instance.deviceName,
                      title: title,
                      currentIndex: 0,
                      tracks: tracks,
                      timestamp: DateTime.now().toIso8601String(),
                    );
                    await NearbyHandoffService.instance.startBroadcasting(payload);
                  } else {
                    await NearbyHandoffService.instance.stopBroadcasting();
                  }
                  setState(() {
                    _isBroadcasting = val;
                  });
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // QR Code Container
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: QrImageView(
              data: qrUrl,
              version: QrVersions.auto,
              size: 180.0,
              backgroundColor: Colors.white,
            ),
          ),
        ),

        const SizedBox(height: 14),
        Center(
          child: Text(
            'Scan with another device camera or Aura scanner',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Preview Tracks Header
        Text(
          'Queue Payload Content (${tracks.length} Songs)',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 8),

        ...tracks.take(4).map((track) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  track.artworkUrl,
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 38,
                    height: 38,
                    color: accentColor.withValues(alpha: 0.2),
                    child: Icon(Icons.music_note_rounded, size: 18, color: accentColor),
                  ),
                ),
              ),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            )),

        if (tracks.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${tracks.length - 4} more tracks ready for handoff',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: accentColor),
            ),
          ),
      ],
    );
  }

  // ── Discover Tab ────────────────────────────────────────────────────────
  Widget _buildDiscoverTab(BuildContext context, Color accentColor, bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        // Scanner Radar Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scanning for nearby Aura devices...',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Make sure both devices are on the same Wi-Fi network',
                      style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.black54),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.qr_code_scanner_rounded, color: accentColor),
                onPressed: () => _showManualQrDialog(context, accentColor, isDark),
                tooltip: 'Enter Connection Code / URL',
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Discovered Senders (${_discoveredDevices.length})',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () {
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_discoveredDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.wifi_find_rounded, size: 48, color: accentColor.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text(
                  'No nearby senders detected yet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start broadcasting on sender device or tap top-right icon to connect directly',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                ),
              ],
            ),
          )
        else
          ..._discoveredDevices.map((device) => _buildDiscoveredDeviceTile(device, accentColor, isDark)),
      ],
    );
  }

  Widget _buildDiscoveredDeviceTile(DiscoveredDevice device, Color accentColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.devices_rounded, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Queue: "${device.title}" • ${device.trackCount} tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: accentColor),
                ),
                Text(
                  'IP: ${device.ip}:${device.port}',
                  style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white38 : Colors.black38),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _handleFetchAndPrompt(device.ip, device.port),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text(
              'Receive',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleFetchAndPrompt(String ip, int port) async {
    final payload = await NearbyHandoffService.instance.fetchPayloadFromAddress(ip, port);

    if (payload == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect to sender device.')),
        );
      }
      return;
    }

    if (mounted) {
      _showIncomingHandoffConfirmation(payload);
    }
  }

  void _showIncomingHandoffConfirmation(HandoffPayload payload) {
    final accentColor = ref.read(customizationProvider).accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C22) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.downloading_rounded, color: accentColor, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Incoming Handoff Payload',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Sender: ${payload.senderName}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                'Title: "${payload.title}" • ${payload.tracks.length} tracks',
                style: TextStyle(fontSize: 13, color: accentColor),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        // Save as Playlist
                        final playlistMap = {
                          'name': '${payload.title} (${payload.senderName})',
                          'description': 'Received via Nearby Handoff from ${payload.senderName}',
                          'tracks': payload.tracks.map((t) => {
                            'id': t.id,
                            'title': t.title,
                            'artist': t.artist,
                            'album': t.album,
                            'duration': t.duration,
                            'artworkUrl': t.artworkUrl,
                            'audioUrl': t.audioUrl,
                            'genre': t.genre,
                          }).toList(),
                        };
                        final current = StorageService.getPlaylists();
                        current.insert(0, playlistMap);
                        await StorageService.savePlaylists(current);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Saved "${payload.title}" to Playlists!')),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accentColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Save Playlist', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(playbackProvider.notifier).playCustomQueue(
                              payload.tracks,
                              initialIndex: payload.currentIndex,
                            );
                        Navigator.pop(this.context); // close handoff sheet
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Playing queue from ${payload.senderName}!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Accept & Play', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showManualQrDialog(BuildContext context, Color accentColor, bool isDark) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF22222A) : Colors.white,
          title: const Text('Manual Connection Code', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _qrUrlController,
            decoration: InputDecoration(
              hintText: 'aura-handoff://192.168.1.X:8899/payload',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = _qrUrlController.text.trim();
                Navigator.pop(context);
                if (text.startsWith('aura-handoff://')) {
                  final clean = text.replaceAll('aura-handoff://', '');
                  final parts = clean.split('/')[0].split(':');
                  if (parts.length == 2) {
                    final ip = parts[0];
                    final port = int.tryParse(parts[1]) ?? 8899;
                    await _handleFetchAndPrompt(ip, port);
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: accentColor),
              child: const Text('Connect', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
