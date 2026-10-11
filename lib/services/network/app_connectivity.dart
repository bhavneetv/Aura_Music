import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class AppConnectivity {
  /// Checks whether device is offline. Returns false on Web (browser manages networking).
  static Future<bool> isOffline() async {
    if (kIsWeb) return false;
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.none) || results.isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether device is online. Returns true on Web.
  static Future<bool> isOnline() async {
    return !(await isOffline());
  }
}
