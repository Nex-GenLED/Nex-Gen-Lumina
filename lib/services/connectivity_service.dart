import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:nexgen_command/services/encryption_service.dart';

/// Service for detecting network connectivity and determining if user
/// is on their home (local) network vs. remote.
class ConnectivityService {
  final NetworkInfo _networkInfo = NetworkInfo();

  /// Cached SSID to avoid repeated async calls
  String? _cachedSsid;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(seconds: 30);

  /// Get the current WiFi SSID (network name).
  /// Returns null if not connected to WiFi or permission denied.
  Future<String?> getCurrentSsid() async {
    // Return cached value if still valid
    if (_cachedSsid != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedSsid;
      }
    }

    try {
      // On some platforms, SSID may include quotes - strip them
      String? ssid = await _networkInfo.getWifiName();
      if (ssid != null) {
        // Remove surrounding quotes if present (common on Android)
        if (ssid.startsWith('"') && ssid.endsWith('"')) {
          ssid = ssid.substring(1, ssid.length - 1);
        }
      }
      _cachedSsid = ssid;
      _cacheTime = DateTime.now();
      return ssid;
    } catch (e) {
      debugPrint('ConnectivityService: Failed to get WiFi SSID: $e');
      return null;
    }
  }

  /// Get the device's current local IP address.
  Future<String?> getCurrentIp() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      debugPrint('ConnectivityService: Failed to get WiFi IP: $e');
      return null;
    }
  }

  /// Check if the device is currently on the home network.
  ///
  /// [homeSsidHash] is the stored hash of the user's home network SSID.
  /// Returns true if current SSID hash matches home SSID hash.
  /// Returns true (assumes local) if homeSsidHash is null/empty (not configured).
  ///
  /// SECURITY: Uses hashed SSID comparison to avoid storing network name in plain text
  Future<bool> isOnHomeNetwork(String? homeSsidHash) async {
    // If no home SSID configured, assume local (backwards compatibility)
    if (homeSsidHash == null || homeSsidHash.isEmpty) {
      debugPrint('ConnectivityService: No home SSID hash configured, assuming local');
      return true;
    }

    final currentSsid = await getCurrentSsid();

    // If we can't determine current SSID, assume local to avoid breaking
    // existing functionality
    if (currentSsid == null || currentSsid.isEmpty) {
      debugPrint('ConnectivityService: Cannot determine current SSID, assuming local');
      return true;
    }

    // SECURITY: Compare using hashed SSID
    final isHome = EncryptionService.compareSsid(currentSsid, homeSsidHash);
    debugPrint('ConnectivityService: Current SSID hashed, Home SSID hash present, isHome=$isHome');
    return isHome;
  }

  /// Check if device appears to have any network connectivity.
  /// Note: This checks WiFi specifically, not cellular.
  Future<bool> hasWifiConnection() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      return ip != null && ip.isNotEmpty && ip != '0.0.0.0';
    } catch (e) {
      return false;
    }
  }

  /// Clear the cached SSID (useful when user changes networks).
  void clearCache() {
    _cachedSsid = null;
    _cacheTime = null;
  }

  /// Stream that emits connectivity status changes.
  /// Polls every 10 seconds to detect network changes.
  Stream<ConnectivityStatus> watchConnectivity(String? homeSsid) {
    return Stream.periodic(const Duration(seconds: 10), (_) async {
      final hasWifi = await hasWifiConnection();
      if (!hasWifi) {
        return ConnectivityStatus.offline;
      }
      final isHome = await isOnHomeNetwork(homeSsid);
      return isHome ? ConnectivityStatus.local : ConnectivityStatus.remote;
    }).asyncMap((future) => future);
  }
}

/// Network connectivity status for the app.
enum ConnectivityStatus {
  /// Connected to home WiFi - use direct HTTP to WLED
  local,

  /// Connected to different network - use cloud relay
  remote,

  /// No network connection
  offline,
}

/// Configuration for remote access.
class RemoteAccessConfig {
  final String webhookUrl;
  final String? apiKey; // Optional API key for webhook authentication

  const RemoteAccessConfig({
    required this.webhookUrl,
    this.apiKey,
  });
}
