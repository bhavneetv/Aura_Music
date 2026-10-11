import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NetworkStatusBanner extends StatefulWidget {
  final Widget child;

  const NetworkStatusBanner({
    super.key,
    required this.child,
  });

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _checkInitialConnectivity();
      _subscription = Connectivity().onConnectivityChanged.listen((results) {
        final isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        if (_isOffline != isOffline) {
          setState(() {
            _isOffline = isOffline;
          });
        }
      });
    }
  }

  Future<void> _checkInitialConnectivity() async {
    if (kIsWeb) return;
    try {
      final results = await Connectivity().checkConnectivity();
      final isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      if (mounted && _isOffline != isOffline) {
        setState(() {
          _isOffline = isOffline;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isOffline ? 36.0 : 0.0,
          color: Colors.amber.shade900,
          child: _isOffline
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'No Network Connection — Playing Offline Music',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
