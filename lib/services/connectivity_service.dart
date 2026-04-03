import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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

    // If we can't determine current SSID (e.g. Android location permission
    // not granted), assume REMOTE. Direct HTTP only works on the home LAN,
    // but the cloud relay works everywhere — so remote is the safe default.
    if (currentSsid == null || currentSsid.isEmpty) {
      debugPrint('ConnectivityService: Cannot determine current SSID, assuming remote');
      return false;
    }

    // SECURITY: Compare using hashed SSID
    try {
      final isHome = EncryptionService.compareSsid(currentSsid, homeSsidHash);
      debugPrint('ConnectivityService: Current SSID hashed, Home SSID hash present, isHome=$isHome');
      return isHome;
    } catch (e) {
      debugPrint('ConnectivityService: SSID comparison failed ($e), assuming remote');
      return false;
    }
  }

  /// Check the device's active connection type using connectivity_plus.
  ///
  /// Returns the set of active connectivity results (wifi, mobile, etc.)
  /// so callers can distinguish WiFi from cellular.
  Future<List<ConnectivityResult>> getConnectivityTypes() async {
    try {
      return await Connectivity().checkConnectivity();
    } catch (e) {
      debugPrint('ConnectivityService: checkConnectivity failed ($e)');
      return [];
    }
  }

  /// Clear the cached SSID (useful when user changes networks).
  void clearCache() {
    _cachedSsid = null;
    _cacheTime = null;
  }

  /// Stream that emits connectivity status changes.
  /// Emits immediately on subscription, then polls every 10 seconds.
  Stream<ConnectivityStatus> watchConnectivity(String? homeSsid) async* {
    // Emit immediately so callers don't wait 10s for the first value.
    yield await _checkConnectivity(homeSsid);

    // Then poll every 10 seconds.
    await for (final status in Stream.periodic(
      const Duration(seconds: 10),
      (_) => _checkConnectivity(homeSsid),
    ).asyncMap((future) => future)) {
      yield status;
    }
  }

  /// Single connectivity check (shared by initial + periodic emissions).
  ///
  /// Uses connectivity_plus to distinguish WiFi from cellular:
  /// - No connection → offline
  /// - Cellular (no WiFi) → remote (cellular is never the home LAN)
  /// - WiFi → check home SSID hash to decide local vs remote
  Future<ConnectivityStatus> _checkConnectivity(String? homeSsid) async {
    final sw = Stopwatch()..start();
    final types = await getConnectivityTypes();

    // No active connection at all
    if (types.isEmpty || types.every((t) => t == ConnectivityResult.none)) {
      sw.stop();
      debugPrint('🔍 BridgeRouter: isOnHomeNetwork=N/A (no connection), '
          'source=connectivity_plus, age=${sw.elapsedMilliseconds}ms');
      return ConnectivityStatus.offline;
    }

    final hasWifi = types.contains(ConnectivityResult.wifi);

    // Cellular / mobile data only (no WiFi) → always remote
    if (!hasWifi) {
      sw.stop();
      debugPrint('🔍 BridgeRouter: isOnHomeNetwork=false (cellular only), '
          'source=connectivity_plus, age=${sw.elapsedMilliseconds}ms');
      return ConnectivityStatus.remote;
    }

    // WiFi is active → check if it's the home network
    final isHome = await isOnHomeNetwork(homeSsid);
    sw.stop();
    final checkMethod = (homeSsid == null || homeSsid.isEmpty)
        ? 'no-hash-configured(assume-local)'
        : 'ssid-hash-compare';
    debugPrint('🔍 BridgeRouter: isOnHomeNetwork=$isHome, '
        'source=$checkMethod, age=${sw.elapsedMilliseconds}ms');
    return isHome ? ConnectivityStatus.local : ConnectivityStatus.remote;
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
