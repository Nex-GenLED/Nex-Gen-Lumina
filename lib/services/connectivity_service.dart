import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
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

  /// Last reason getCurrentSsid returned null / failed. The UI reads this
  /// after a null result to surface the specific failure to the user — Tyler
  /// has no Mac/Xcode console, so the reason MUST be visible in-app. Set on
  /// every branch of getCurrentSsid (including success → null). Stable until
  /// the next getCurrentSsid call.
  String? _lastSsidFailureReason;
  String? get lastSsidFailureReason => _lastSsidFailureReason;

  /// Get the current WiFi SSID (network name).
  /// Returns null if not connected to WiFi or permission denied.
  Future<String?> getCurrentSsid() async {
    // Reset reason at the top of every call — stale values would lie.
    _lastSsidFailureReason = null;

    // Return cached value if still valid
    if (_cachedSsid != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedSsid;
      }
    }

    // iOS-only: NEHotspotNetwork.fetchCurrent (the API network_info_plus
    // uses under the hood on iOS 14+) returns nil unless Core Location
    // has an active session — even with the wifi-info entitlement AND
    // location permission granted. permission_handler only READS / GRANTS
    // the permission; it doesn't activate a CLLocationManager session.
    //
    // Two-stage warm-up:
    //   1. getLastKnownPosition — returns the cached fix INSTANTLY (no GPS
    //      wait). May be enough on its own to mark Core Location as
    //      recently-active. Returns null indoors with no prior fix.
    //   2. getCurrentPosition — belt-and-suspenders. Waits for a fresh fix,
    //      can time out indoors (the leading theory for why the 6d28e40
    //      warm-up alone wasn't enough).
    //
    // Both outcomes are intentionally non-fatal — every failure mode falls
    // through to the SSID attempt below, which then propagates a specific
    // reason via _lastSsidFailureReason.
    if (Platform.isIOS) {
      debugPrint('SSID: warmup START');
      try {
        final last = await Geolocator.getLastKnownPosition();
        debugPrint(
            'SSID: getLastKnownPosition -> ${last == null ? "null" : "position"}');
      } catch (e) {
        debugPrint('SSID: getLastKnownPosition threw $e');
      }
      try {
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 3),
          ),
        );
        debugPrint('SSID: getCurrentPosition -> position');
      } on TimeoutException catch (_) {
        debugPrint('SSID: getCurrentPosition -> timeout');
      } catch (e) {
        debugPrint('SSID: getCurrentPosition -> error:$e');
      }
    }

    try {
      // On some platforms, SSID may include quotes - strip them
      String? ssid = await _networkInfo.getWifiName();
      if (ssid == null) {
        debugPrint('SSID: getWifiName -> null');
        _lastSsidFailureReason = 'getwifiname_null';
        _cachedSsid = null;
        _cacheTime = DateTime.now();
        return null;
      }
      // Remove surrounding quotes if present (common on Android)
      if (ssid.startsWith('"') && ssid.endsWith('"')) {
        ssid = ssid.substring(1, ssid.length - 1);
      }
      if (ssid.isEmpty) {
        debugPrint('SSID: getWifiName -> empty');
        _lastSsidFailureReason = 'getwifiname_empty';
        _cachedSsid = ssid;
        _cacheTime = DateTime.now();
        return ssid;
      }
      debugPrint('SSID: getWifiName -> "$ssid"');
      _cachedSsid = ssid;
      _cacheTime = DateTime.now();
      return ssid;
    } catch (e) {
      debugPrint('SSID: getWifiName threw $e');
      _lastSsidFailureReason = 'getwifiname_exception:$e';
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
    // not granted), assume LOCAL. Direct HTTP to the controller is the
    // primary control path — defaulting to remote when SSID is unavailable
    // breaks local control for users without location permission.
    if (currentSsid == null || currentSsid.isEmpty) {
      debugPrint('ConnectivityService: Cannot determine current SSID, assuming local');
      return true;
    }

    // SECURITY: Compare using hashed SSID
    try {
      final isHome = EncryptionService.compareSsid(currentSsid, homeSsidHash);
      debugPrint('ConnectivityService: Current SSID hashed, Home SSID hash present, isHome=$isHome');
      return isHome;
    } catch (e) {
      debugPrint('ConnectivityService: SSID comparison failed ($e), assuming local');
      return true;
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
