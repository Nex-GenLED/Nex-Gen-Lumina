import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/ddp_service.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/mock_wled_repository.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/mqtt_relay_repository.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/lumina_backend_providers.dart';
import 'package:nexgen_command/app_providers.dart';

/// Connectivity status provider that checks if user is on home network.
/// Uses the user's saved homeSsid from their profile.
final wledConnectivityStatusProvider = FutureProvider<ConnectivityStatus>((ref) async {
  final connectivityService = ref.watch(connectivityServiceProvider);
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );

  final homeSsid = userProfile?.homeSsid;
  final isHome = await connectivityService.isOnHomeNetwork(homeSsid);

  if (!await connectivityService.hasWifiConnection()) {
    return ConnectivityStatus.offline;
  }

  return isHome ? ConnectivityStatus.local : ConnectivityStatus.remote;
});

/// Whether the app is currently in remote mode (cloud relay).
final isRemoteModeProvider = Provider<bool>((ref) {
  final status = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (s) => s,
    orElse: () => ConnectivityStatus.local,
  );
  return status == ConnectivityStatus.remote;
});

/// Provides a WledRepository based on Demo Mode, network location, and selected device.
///
/// Priority:
/// 1. Demo Mode → MockWledRepository
/// 2. Local network (on home WiFi) → WledService (direct HTTP)
/// 3. Remote network (away from home) → CloudRelayRepository (via Firestore/webhook)
final wledRepositoryProvider = Provider<WledRepository?>((ref) {
  final isDemo = ref.watch(demoModeProvider);
  if (isDemo) return MockWledRepository();

  final ip = ref.watch(selectedDeviceIpProvider);
  if (ip == null) return null;

  // Get user profile for remote access configuration
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );

  // Check connectivity status
  final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (status) => status,
    orElse: () => ConnectivityStatus.local, // Default to local if unknown
  );

  // If on local network, use direct HTTP connection
  if (connectivityStatus == ConnectivityStatus.local) {
    debugPrint('🏠 WledRepository: Using LOCAL mode (direct HTTP)');
    return WledService('http://$ip');
  }

  // If remote and remote access is configured, use cloud relay
  if (connectivityStatus == ConnectivityStatus.remote) {
    if (userProfile?.remoteAccessEnabled == true) {
      // Get the user ID for Firestore operations
      final userId = ref.watch(authStateProvider).maybeWhen(
        data: (user) => user?.uid,
        orElse: () => null,
      );

      // Get the selected controller ID
      final controllerId = ref.watch(selectedControllerIdProvider);

      // Check if MQTT relay (Lumina Backend) is available and preferred
      final backendService = ref.watch(luminaBackendServiceProvider);
      final useMqttRelay = userProfile?.mqttRelayEnabled == true;

      if (useMqttRelay && backendService.isAuthenticated && controllerId != null) {
        debugPrint('📡 WledRepository: Using REMOTE mode (MQTT relay via Lumina Backend)');
        return MqttRelayRepository(
          backendService: backendService,
          deviceId: controllerId,
          deviceSerial: null, // Could be fetched from controller data
        );
      }

      if (userId != null && controllerId != null) {
        // Check which mode we're in
        final webhookUrl = userProfile?.webhookUrl;
        final hasWebhook = webhookUrl != null && webhookUrl.isNotEmpty;

        if (hasWebhook) {
          debugPrint('☁️ WledRepository: Using REMOTE mode (webhook relay)');
          debugPrint('   Webhook URL: $webhookUrl');
        } else {
          debugPrint('🔌 WledRepository: Using REMOTE mode (ESP32 bridge)');
          debugPrint('   Commands will be executed by the local ESP32 bridge');
        }

        return CloudRelayRepository(
          userId: userId,
          controllerId: controllerId,
          controllerIp: ip,
          webhookUrl: webhookUrl ?? '', // Empty = ESP32 Bridge mode
        );
      } else {
        debugPrint('⚠️ WledRepository: Remote mode but missing userId or controllerId');
      }
    } else {
      debugPrint('⚠️ WledRepository: Remote mode but remote access not enabled');
    }
  }

  // Fallback: If offline or remote access not configured, return null
  // The UI should show appropriate message
  if (connectivityStatus == ConnectivityStatus.offline) {
    debugPrint('📵 WledRepository: OFFLINE - no network connection');
    return null;
  }

  // Last resort: try local connection even if we think we're remote
  // This handles cases where home network detection fails
  debugPrint('🔄 WledRepository: Falling back to LOCAL mode');
  return WledService('http://$ip');
});

/// Provider for the currently selected controller's Firestore document ID.
/// Needed for cloud relay to identify which controller to target.
final selectedControllerIdProvider = Provider<String?>((ref) {
  final controllers = ref.watch(controllersStreamProvider).maybeWhen(
    data: (list) => list,
    orElse: () => <dynamic>[],
  );
  final selectedIp = ref.watch(selectedDeviceIpProvider);

  if (selectedIp == null || controllers.isEmpty) return null;

  // Find the controller with matching IP
  for (final controller in controllers) {
    if (controller.ip == selectedIp) {
      return controller.id;
    }
  }

  return null;
});

/// Provider that fetches the total LED count from the connected WLED device.
/// Returns null if no device is connected or if the count cannot be fetched.
final deviceTotalLedCountProvider = FutureProvider<int?>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  if (repo == null) return null;

  try {
    return await repo.getTotalLedCount();
  } catch (e) {
    debugPrint('Error fetching device LED count: $e');
    return null;
  }
});

/// Provider for updating segment configuration on the WLED device.
/// Returns a function that can be called to update a segment's boundaries.
final updateSegmentConfigProvider = Provider<Future<bool> Function({
  required int segmentId,
  int? start,
  int? stop,
})>((ref) {
  return ({required int segmentId, int? start, int? stop}) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return false;

    try {
      return await repo.updateSegmentConfig(
        segmentId: segmentId,
        start: start,
        stop: stop,
      );
    } catch (e) {
      debugPrint('Error updating segment config: $e');
      return false;
    }
  };
});

class WledNotifier extends Notifier<WledStateModel> {
  Timer? _poller;
  Timer? _reconnectTimer;
  bool _posting = false;
  bool _infoQueried = false;

  @override
  WledStateModel build() {
    final s = WledStateModel.initial();
    _startPolling();
    ref.onDispose(() {
      _poller?.cancel();
    });
    return s;
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      final service = ref.read(wledRepositoryProvider);
      if (service == null) return;
      if (_posting) return; // avoid fighting with user updates
      final data = await service.getState();
      if (data == null) {
        if (state.connected) {
          state = state.copyWith(connected: false);
        }
        _ensureReconnectTimer();
        return;
      }
      _cancelReconnectTimer();
      try {
        final isOn = (data['on'] as bool?) ?? (data['bri'] != null ? (data['bri'] as int) > 0 : state.isOn);
        final bri = (data['bri'] as int?) ?? state.brightness;
        int speed = state.speed;
        int intensity = state.intensity;

        // WLED 'seg' in /json/state can be either a List or a single Map depending on build.
        final dynamic segAny = data['seg'];
        Map<dynamic, dynamic>? firstSeg;
        if (segAny is List && segAny.isNotEmpty) {
          final s0 = segAny.first;
          if (s0 is Map) firstSeg = s0;
        } else if (segAny is Map) {
          firstSeg = segAny;
        }

        int effectId = state.effectId;
        int paletteId = state.paletteId;

        if (firstSeg != null) {
          final sx = firstSeg['sx'];
          if (sx is int) speed = sx;

          // Parse intensity (ix)
          final ix = firstSeg['ix'];
          if (ix is int) intensity = ix;

          // Parse effect ID (fx)
          final fx = firstSeg['fx'];
          if (fx is int) effectId = fx;

          // Parse palette ID (pal)
          final pal = firstSeg['pal'];
          if (pal is int) paletteId = pal;

          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty && cols.first is List) {
            final c = cols.first as List;
            if (c.length >= 3) {
              final rr = (c[0] as num).toInt();
              final gg = (c[1] as num).toInt();
              final bb = (c[2] as num).toInt();
              int ww = state.warmWhite;
              if (c.length >= 4) {
                ww = (c[3] as num).toInt().clamp(0, 255);
              }
              state = state.copyWith(color: Color.fromARGB(255, rr, gg, bb), warmWhite: ww);
            }
          }
        }

        state = state.copyWith(isOn: isOn, brightness: bri, speed: speed, intensity: intensity, effectId: effectId, paletteId: paletteId, connected: true);
      } catch (e) {
        debugPrint('WLED parse state error: $e');
      }

      // Query RGBW support once after connection
      if (!_infoQueried) {
        _infoQueried = true;
        try {
          final rgbw = await service.supportsRgbw();
          state = state.copyWith(supportsRgbw: rgbw);
        } catch (e) {
          debugPrint('supportsRgbw check failed: $e');
        }
      }
    });
  }

  void _ensureReconnectTimer() {
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final service = ref.read(wledRepositoryProvider);
      if (service == null) return;
      try {
        final data = await service.getState();
        if (data != null) {
          _cancelReconnectTimer();
          // Mark reconnected; next poll will refresh values
          state = state.copyWith(connected: true);
        }
      } catch (e) {
        debugPrint('Reconnect ping failed: $e');
      }
    });
  }

  void _cancelReconnectTimer() {
    if (_reconnectTimer != null) {
      _reconnectTimer!.cancel();
      _reconnectTimer = null;
    }
  }

  /// Force refresh connection state - call when app resumes from background
  Future<void> refreshConnection() async {
    debugPrint('🔄 WledNotifier: Refreshing connection...');
    final service = ref.read(wledRepositoryProvider);
    if (service == null) {
      debugPrint('🔄 WledNotifier: No repository available');
      return;
    }

    try {
      final data = await service.getState();
      if (data != null) {
        debugPrint('🔄 WledNotifier: Connection restored');
        _cancelReconnectTimer();
        // Parse and update state immediately
        final isOn = (data['on'] as bool?) ?? state.isOn;
        final bri = (data['bri'] as int?) ?? state.brightness;
        state = state.copyWith(isOn: isOn, brightness: bri, connected: true);
        // Restart polling to ensure fresh data
        _startPolling();
      } else {
        debugPrint('🔄 WledNotifier: Connection failed, starting reconnect timer');
        state = state.copyWith(connected: false);
        _ensureReconnectTimer();
      }
    } catch (e) {
      debugPrint('🔄 WledNotifier: Refresh failed: $e');
      state = state.copyWith(connected: false);
      _ensureReconnectTimer();
    }
  }

  Future<void> togglePower(bool value) async {
    debugPrint('🔌 togglePower called: $value');
    state = state.copyWith(isOn: value);
    // Only send power state - don't include brightness when turning off
    await _postUpdate(on: value);
  }

  Future<void> setBrightness(int bri) async {
    state = state.copyWith(brightness: bri);
    // Always send power state with brightness to ensure WLED interprets correctly
    await _postUpdate(on: state.isOn, brightness: bri);
  }

  Future<void> setSpeed(int sx) async {
    state = state.copyWith(speed: sx);
    await _postUpdate(speed: sx);
  }

  Future<void> setColor(Color color) async {
    state = state.copyWith(color: color);
    // For RGBW strips, explicitly set white to 0 for pure RGB color accuracy
    // This prevents WLED's auto-white from mixing in white LED and distorting colors
    await _postUpdate(color: color, forceRgbwZeroWhite: state.supportsRgbw);
  }

  Future<void> setWarmWhite(int white) async {
    final clamped = white.clamp(0, 255);
    state = state.copyWith(warmWhite: clamped);
    // Send an update including current color and the updated white channel
    await _postUpdate(color: state.color, white: state.supportsRgbw ? clamped : null);
  }

  Future<void> _postUpdate({bool? on, int? brightness, int? speed, Color? color, int? white, bool? forceRgbwZeroWhite}) async {
    // If DDP streaming is active, avoid HTTP state updates to prevent conflicts.
    final ddpStreaming = ref.read(ddpStreamingProvider);
    if (ddpStreaming) {
      debugPrint('Skipping HTTP update because DDP streaming is active');
      return;
    }
    final service = ref.read(wledRepositoryProvider);
    if (service == null) return;
    _posting = true;
    try {
      final ok = await service.setState(
        on: on,
        brightness: brightness,
        speed: speed,
        // Only send color if explicitly provided; otherwise avoid overriding effect params.
        color: color,
        white: white,
        forceRgbwZeroWhite: forceRgbwZeroWhite,
      );
      if (!ok && state.connected) {
        state = state.copyWith(connected: false);
        _ensureReconnectTimer();
      }
      // Wait a bit before allowing poller to read back state
      // This prevents the poller from reading stale data before WLED updates
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      _posting = false;
    }
  }

  void _registerDispose() {
    ref.onDispose(() {
      _poller?.cancel();
      _reconnectTimer?.cancel();
    });
  }
}

final wledStateProvider = NotifierProvider<WledNotifier, WledStateModel>(WledNotifier.new);
