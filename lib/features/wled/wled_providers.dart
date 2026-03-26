import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/schedule/schedule_enforcement.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/ddp_service.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/mqtt_relay_repository.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/lumina_backend_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/services/bridge_health_service.dart';
import 'package:nexgen_command/services/reviewer_seed_service.dart';

/// Connectivity status stream that checks if user is on home network.
///
/// Polls every 10 seconds using the user's saved homeSsidHash from their
/// profile. Re-evaluates whenever the user profile changes (e.g. after
/// saving a new home SSID in Remote Access settings).
///
/// Also invalidated on app resume via [_connectivityRefreshProvider] so a
/// fresh SSID check runs immediately when the user opens the app.
final wledConnectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  // Watch the refresh counter — incrementing it restarts this stream,
  // which clears the SSID cache and forces a fresh network check.
  ref.watch(_connectivityRefreshProvider);

  final connectivityService = ref.watch(connectivityServiceProvider);
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );

  final homeSsidHash = userProfile?.homeSsidHash;

  // Clear cached SSID so the first emission uses a live value.
  connectivityService.clearCache();

  return connectivityService.watchConnectivity(homeSsidHash);
});

/// Counter that, when incremented, forces [wledConnectivityStatusProvider]
/// to restart its stream and re-check the network.
final _connectivityRefreshProvider = StateProvider<int>((ref) => 0);

/// Call this to force an immediate network re-check (e.g. on app resume).
void refreshConnectivityStatus(WidgetRef ref) {
  ref.read(connectivityServiceProvider).clearCache();
  ref.read(_connectivityRefreshProvider.notifier).state++;
}

/// Overload for use inside providers / notifiers (Ref instead of WidgetRef).
void refreshConnectivityStatusFromRef(Ref ref) {
  ref.read(connectivityServiceProvider).clearCache();
  ref.read(_connectivityRefreshProvider.notifier).state++;
}

/// Whether the app is currently in remote mode (cloud relay).
/// Returns false while the connectivity check is still loading.
final isRemoteModeProvider = Provider<bool>((ref) {
  final status = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (s) => s,
    orElse: () => null,
  );
  return status == ConnectivityStatus.remote;
});

/// Shared bridge reachability state.
///
/// Set to `true` by the Remote Access screen (or any future code) when a
/// Firestore round-trip through the ESP32 bridge succeeds. Set to `false`
/// when a bridge test fails or times out. `null` means "never tested yet."
///
/// The home-screen indicator reads this to decide whether to show
/// "bridge active" (green/teal) vs "offline" (red) when in remote mode.
final bridgeReachableProvider = StateProvider<bool?>((ref) => null);

/// One-time startup bridge health check.
///
/// Runs when the authenticated user has a registered controller. Writes a
/// ping document to Firestore and waits up to 15 s for the ESP32 bridge to
/// acknowledge it. The result is exposed as [BridgeHealth] for future UI use.
final bridgeHealthProvider = FutureProvider<BridgeHealth>((ref) async {
  final userId = ref.watch(authStateProvider).maybeWhen(
    data: (user) => user?.uid,
    orElse: () => null,
  );
  final controllerId = ref.watch(selectedControllerIdProvider);
  final ip = ref.watch(selectedDeviceIpProvider);

  // Can't run the check without auth + a registered controller.
  if (userId == null || controllerId == null || ip == null) {
    return BridgeHealth.unreachable;
  }

  final service = BridgeHealthService();
  return service.check(userId: userId, controllerIp: ip);
});

/// Provides a WledRepository based on Demo Mode, network location, and
/// controller registration.
///
/// Priority:
/// 1.  Demo / reviewer mode                         → DemoWledRepository
/// 2.  No selected device IP                        → null
/// 3.  Connectivity loading                         → null (wait for check)
/// 4.  Offline                                      → null
/// 5.  Local WiFi                                   → WledService (direct HTTP, fastest)
/// 6.  Remote + MQTT configured + authenticated     → MqttRelayRepository
/// 7.  Remote + userId + controllerId               → CloudRelayRepository (bridge relay)
/// 8.  Everything else                              → null
final wledRepositoryProvider = Provider<WledRepository?>((ref) {
  // ── 1. Demo / reviewer mode ───────────────────────────────────────────────
  final isDemo = ref.watch(demoModeProvider);
  if (isDemo) {
    debugPrint('RepositoryInit: selected=DemoWledRepository, network=n/a, hasControllerId=n/a');
    return DemoWledRepository();
  }

  final userId = ref.watch(authStateProvider).maybeWhen(
    data: (user) => user?.uid,
    orElse: () => null,
  );
  if (userId == ReviewerSeedService.reviewerUserId) {
    debugPrint('RepositoryInit: selected=DemoWledRepository, network=n/a, hasControllerId=n/a');
    return DemoWledRepository();
  }

  // ── 2. Require a selected device ─────────────────────────────────────────
  final ip = ref.watch(selectedDeviceIpProvider);
  if (ip == null) {
    debugPrint('RepositoryInit: selected=null, network=n/a, hasControllerId=n/a');
    return null;
  }

  // ── 3. Network location ──────────────────────────────────────────────────
  final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (status) => status,
    orElse: () => null,
  );

  if (connectivityStatus == null) {
    debugPrint('RepositoryInit: selected=null, network=null (loading), hasControllerId=n/a');
    return null;
  }

  // ── 4. Offline → no repository ───────────────────────────────────────────
  if (connectivityStatus == ConnectivityStatus.offline) {
    debugPrint('RepositoryInit: selected=null, network=offline, hasControllerId=n/a');
    return null;
  }

  // ── Shared lookups for steps 5-7 ─────────────────────────────────────────
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );
  final controllerId = ref.watch(selectedControllerIdProvider);
  final webhookUrl = userProfile?.webhookUrl;

  // ── 5. Local WiFi → always use direct HTTP ───────────────────────────────
  //
  // Direct HTTP to the controller is faster and more reliable than any relay.
  // The bridge/cloud relay paths are for remote access only.
  if (connectivityStatus == ConnectivityStatus.local) {
    debugPrint('RepositoryInit: selected=WledService, '
        'network=${connectivityStatus.name}, hasControllerId=$controllerId');
    return WledService('http://$ip');
  }

  // ── 6. Remote + MQTT relay (highest-priority remote path) ────────────────
  if (userProfile?.remoteAccessEnabled == true) {
    final backendService = ref.watch(luminaBackendServiceProvider);
    if (userProfile?.mqttRelayEnabled == true &&
        backendService.isAuthenticated &&
        controllerId != null) {
      debugPrint('RepositoryInit: selected=MqttRelayRepository, '
          'network=${connectivityStatus.name}, hasControllerId=$controllerId');
      return MqttRelayRepository(
        backendService: backendService,
        deviceId: controllerId,
        deviceSerial: null,
      );
    }
  }

  // ── 7. Remote + Firestore bridge relay ───────────────────────────────────
  if (userId != null && controllerId != null) {
    final hasWebhook = webhookUrl != null && webhookUrl.isNotEmpty;
    final mode = hasWebhook ? 'Webhook relay' : 'ESP32 Bridge';
    final bridgeTarget = hasWebhook ? webhookUrl : 'firestore://$userId/commands';
    debugPrint('🏠 BridgeRouter: routing via BRIDGE, url=$bridgeTarget ($mode)');
    debugPrint('RepositoryInit: selected=CloudRelayRepository, '
        'network=${connectivityStatus.name}, hasControllerId=$controllerId');
    return CloudRelayRepository(
      userId: userId,
      controllerId: controllerId,
      controllerIp: ip,
      webhookUrl: webhookUrl ?? '',
    );
  }

  // ── 8. Remote but no relay path available ────────────────────────────────
  debugPrint('RepositoryInit: selected=null, '
      'network=${connectivityStatus.name}, hasControllerId=$controllerId');
  return null;
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

/// Provider that fetches the full hardware LED configuration (buses, power, etc.)
/// from the connected WLED device via GET /json/cfg.
final deviceHardwareConfigProvider = FutureProvider<WledHardwareConfig?>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  if (repo == null) return null;

  try {
    return await repo.getConfig();
  } catch (e) {
    debugPrint('Error fetching device hardware config: $e');
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

  /// Consecutive remote poll failures. After 3, bridge is marked unreachable
  /// even if it was previously confirmed — prevents stale "Connected" status.
  int _consecutiveRemoteFailures = 0;
  static const _maxRemoteFailuresBeforeDowngrade = 3;

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
      final isRemote = ref.read(isRemoteModeProvider);
      if (data == null) {
        if (state.connected) {
          state = state.copyWith(connected: false);
        }
        // Track consecutive failures in remote mode. Downgrade bridge status
        // after repeated failures to prevent stale "Connected" indicator.
        if (isRemote) {
          _consecutiveRemoteFailures++;
          if (_consecutiveRemoteFailures >= _maxRemoteFailuresBeforeDowngrade) {
            ref.read(bridgeReachableProvider.notifier).state = false;
          }
        }
        _ensureReconnectTimer();
        return;
      }
      _cancelReconnectTimer();
      // Successful poll in remote mode confirms bridge is working.
      if (isRemote) {
        _consecutiveRemoteFailures = 0;
        ref.read(bridgeReachableProvider.notifier).state = true;
      }
      try {
        _applyStateData(data);
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

  /// Parse a full /json/state response and update all state fields.
  /// Used by both polling and refreshConnection to avoid duplication.
  void _applyStateData(Map<String, dynamic> data) {
    final prevEffectId = state.effectId;
    final prevPresetId = state.presetId;
    final isOn = (data['on'] as bool?) ?? (data['bri'] != null ? (data['bri'] as int) > 0 : state.isOn);
    final bri = (data['bri'] as int?) ?? state.brightness;
    int speed = state.speed;
    int intensity = state.intensity;

    // Parse active preset ID from WLED state (0 = no preset active)
    final ps = (data['ps'] is num) ? (data['ps'] as num).toInt() : state.presetId;

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
    bool reverse = state.reverse;

    if (firstSeg != null) {
      final sx = firstSeg['sx'];
      if (sx is int) speed = sx;

      final ix = firstSeg['ix'];
      if (ix is int) intensity = ix;

      final fx = firstSeg['fx'];
      if (fx is int) effectId = fx;

      final pal = firstSeg['pal'];
      if (pal is int) paletteId = pal;

      final rev = firstSeg['rev'];
      if (rev is bool) reverse = rev;

      final cols = firstSeg['col'];
      if (cols is List && cols.isNotEmpty && cols.first is List) {
        final List<Color> colorSequence = [];
        Color? primaryColor;
        int ww = state.warmWhite;

        for (final c in cols) {
          if (c is List && c.length >= 3) {
            final rr = (c[0] as num).toInt().clamp(0, 255);
            final gg = (c[1] as num).toInt().clamp(0, 255);
            final bb = (c[2] as num).toInt().clamp(0, 255);

            if (rr > 0 || gg > 0 || bb > 0) {
              colorSequence.add(Color.fromARGB(255, rr, gg, bb));
            }

            if (primaryColor == null) {
              primaryColor = Color.fromARGB(255, rr, gg, bb);
              if (c.length >= 4) {
                ww = (c[3] as num).toInt().clamp(0, 255);
              }
            }
          }
        }

        if (primaryColor != null) {
          state = state.copyWith(
            color: primaryColor,
            warmWhite: ww,
            colorSequence: colorSequence,
          );
        }
      }
    }

    state = state.copyWith(
      isOn: isOn,
      brightness: bri,
      speed: speed,
      intensity: intensity,
      effectId: effectId,
      paletteId: paletteId,
      presetId: ps,
      reverse: reverse,
      connected: true,
    );

    // Mark that we have received a live fetch
    ref.read(wledStateFreshProvider.notifier).state = true;

    // Resolve preset name from WLED when ps > 0 and preset changed or label
    // is empty. This is Priority 1 in the label hierarchy — the authoritative
    // name straight from the controller.
    if (ps > 0 && (ps != prevPresetId || ref.read(activePresetLabelProvider) == null)) {
      _resolvePresetName(ps);
    }

    // Clear stale preset label when the live effect diverges from what was
    // cached in SharedPreferences AND no WLED preset is active.
    // When ps > 0, the preset lookup above will set the correct label.
    if (effectId != prevEffectId && ps <= 0) {
      try {
        ref.read(activePresetLabelProvider.notifier).clear();
      } catch (_) {}
    }
  }

  /// Fetches preset names from the WLED controller and sets the active label.
  Future<void> _resolvePresetName(int presetId) async {
    final service = ref.read(wledRepositoryProvider);
    if (service == null) return;

    try {
      final presetNames = await service.fetchPresetNames();
      final name = presetNames[presetId];
      if (name != null && name.isNotEmpty) {
        ref.read(activePresetLabelProvider.notifier).state = name;
        debugPrint('🏷️ Resolved WLED preset $presetId → "$name"');
      }
    } catch (e) {
      debugPrint('🏷️ Preset name lookup failed for $presetId: $e');
    }
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
          _applyStateData(data);
          _startPolling();
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
    // Mark state as stale until fresh data arrives
    ref.read(wledStateFreshProvider.notifier).state = false;
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
        // Full state parse — colors, effect, speed, reverse, etc.
        _applyStateData(data);
        // Query RGBW support if not yet done
        if (!_infoQueried) {
          _infoQueried = true;
          try {
            final rgbw = await service.supportsRgbw();
            state = state.copyWith(supportsRgbw: rgbw);
          } catch (_) {}
        }
        // Restart polling to keep state fresh
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

  Future<void> togglePower(bool value, {bool isManualChange = true}) async {
    debugPrint('🔌 togglePower called: $value (manual: $isManualChange)');
    state = state.copyWith(isOn: value);
    // Only send power state - don't include brightness when turning off
    await _postUpdate(on: value, isManualChange: isManualChange);
  }

  Future<void> setBrightness(int bri, {bool isManualChange = true}) async {
    state = state.copyWith(brightness: bri);
    // Always send power state with brightness to ensure WLED interprets correctly
    await _postUpdate(on: state.isOn, brightness: bri, isManualChange: isManualChange);
  }

  Future<void> setSpeed(int sx, {bool isManualChange = true}) async {
    state = state.copyWith(speed: sx);
    await _postUpdate(speed: sx, isManualChange: isManualChange);
  }

  Future<void> setColor(Color color, {bool isManualChange = true}) async {
    state = state.copyWith(color: color);
    // For RGBW strips, explicitly set white to 0 for pure RGB color accuracy
    // This prevents WLED's auto-white from mixing in white LED and distorting colors
    await _postUpdate(color: color, forceRgbwZeroWhite: state.supportsRgbw, isManualChange: isManualChange);
  }

  Future<void> setWarmWhite(int white, {bool isManualChange = true}) async {
    final clamped = white.clamp(0, 255);
    state = state.copyWith(warmWhite: clamped);
    // Send an update including current color and the updated white channel
    await _postUpdate(color: state.color, white: state.supportsRgbw ? clamped : null, isManualChange: isManualChange);
  }

  /// Sets Lumina pattern metadata (colors, effect name) when a pattern is applied.
  /// This preserves the rich information from Lumina's AI response so it displays
  /// correctly on the home screen even after device polling overwrites raw values.
  void setLuminaPatternMetadata({
    List<Color>? colorSequence,
    List<String>? colorNames,
    String? effectName,
  }) {
    state = state.copyWith(
      colorSequence: colorSequence,
      colorNames: colorNames,
      customEffectName: effectName,
    );
    debugPrint('🎨 Set Lumina pattern metadata: ${colorSequence?.length ?? 0} colors, effect: $effectName');
  }

  /// Applies a pattern to the local preview state without requiring device connection.
  /// This allows users to see the roofline LED preview on the house image even when
  /// the WLED controller is offline. The next successful device poll will sync with
  /// actual device state.
  void applyLocalPreview({
    required List<Color> colors,
    required int effectId,
    int speed = 128,
    int intensity = 128,
    int brightness = 255,
    String? effectName,
  }) {
    state = state.copyWith(
      isOn: true,
      colorSequence: colors,
      color: colors.isNotEmpty ? colors.first : Colors.white,
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
      customEffectName: effectName,
    );
    debugPrint('🎨 Applied local preview: ${colors.length} colors, effect: $effectName (offline OK)');
  }

  /// Clears custom Lumina pattern metadata (e.g., when user manually adjusts pattern).
  /// The next poll will restore device-reported values.
  void clearLuminaPatternMetadata() {
    state = state.copyWith(
      colorNames: [],
      clearCustomEffectName: true,
    );
    debugPrint('🗑️ Cleared Lumina pattern metadata');
  }

  Future<void> _postUpdate({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
    bool isManualChange = false,
  }) async {
    // If DDP streaming is active, avoid HTTP state updates to prevent conflicts.
    final ddpStreaming = ref.read(ddpStreamingProvider);
    if (ddpStreaming) {
      debugPrint('Skipping HTTP update because DDP streaming is active');
      return;
    }
    final service = ref.read(wledRepositoryProvider);
    if (service == null) {
      // Surface the reason so the UI can react (red dot + message).
      final connStatus = ref.read(wledConnectivityStatusProvider).maybeWhen(
        data: (s) => s,
        orElse: () => null,
      );
      if (connStatus == ConnectivityStatus.remote) {
        debugPrint('❌ Command blocked: on remote network but remote access '
            'not configured or userId/controllerId unavailable');
      } else if (connStatus == null) {
        debugPrint('⏳ Command blocked: connectivity check still in progress');
      } else {
        debugPrint('❌ Command blocked: no repository (offline or no device selected)');
      }
      // Mark disconnected so the UI shows the red dot immediately
      // rather than waiting for a poll timeout.
      if (state.connected) {
        state = state.copyWith(connected: false);
      }
      return;
    }

    // Record manual override for schedule enforcement
    if (isManualChange) {
      try {
        ref.read(scheduleEnforcementServiceProvider).recordManualOverride();
      } catch (e) {
        // Ignore errors if enforcement service not available
        debugPrint('Could not record manual override: $e');
      }

      // Auto-pause Neighborhood Sync — user's local action always takes priority.
      // This runs fire-and-forget so it never delays the user's command.
      SyncWarningDialog.autoPauseIfInSync(ref);
    }

    _posting = true;
    try {
      // Check if a channel filter is active (user selected specific channels).
      final effectiveChannels = ref.read(effectiveChannelIdsProvider);

      bool ok;
      if (effectiveChannels.isEmpty) {
        // No segment info available yet — fall back to legacy single-segment.
        ok = await service.setState(
          on: on,
          brightness: brightness,
          speed: speed,
          color: color,
          white: white,
          forceRgbwZeroWhite: forceRgbwZeroWhite,
        );
      } else {
        // Target ALL effective channels (all segments, or filtered subset).
        final Map<String, dynamic> payload = {};
        // Device-level properties always apply globally.
        if (on != null) payload['on'] = on;
        if (brightness != null) payload['bri'] = brightness.clamp(0, 255);

        // Segment-specific properties go to each effective channel.
        final Map<String, dynamic> segTemplate = {};
        if (speed != null) segTemplate['sx'] = speed.clamp(0, 255);
        if (color != null || white != null) {
          final rgbw = rgbToRgbw(
            color?.red ?? 0,
            color?.green ?? 0,
            color?.blue ?? 0,
            explicitWhite: white,
            forceZeroWhite: forceRgbwZeroWhite == true,
          );
          segTemplate['col'] = [rgbw];
        }

        if (segTemplate.isNotEmpty) {
          final deviceCh = ref.read(deviceChannelsProvider);
          payload['seg'] = effectiveChannels.map((id) {
            final s = <String, dynamic>{'id': id, ...segTemplate};
            for (final ch in deviceCh) {
              if (ch.id == id) {
                s['start'] = ch.start;
                s['stop'] = ch.stop;
                break;
              }
            }
            return s;
          }).toList();
        }

        ok = await service.applyJson(payload);
      }

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

}

final wledStateProvider = NotifierProvider<WledNotifier, WledStateModel>(WledNotifier.new);

/// Whether the WLED state has been fetched live from the controller at least
/// once since launch or the most recent app resume. Reset to false on resume
/// so the dashboard can show a "Last Known State" indicator until fresh data
/// arrives.
final wledStateFreshProvider = StateProvider<bool>((ref) => false);
