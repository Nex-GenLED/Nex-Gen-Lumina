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
import 'package:nexgen_command/services/reviewer_seed_service.dart';

/// Connectivity status provider that checks if user is on home network.
/// Uses the user's saved homeSsid from their profile.
final wledConnectivityStatusProvider = FutureProvider<ConnectivityStatus>((ref) async {
  final connectivityService = ref.watch(connectivityServiceProvider);
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );

  final homeSsidHash = userProfile?.homeSsidHash;
  final isHome = await connectivityService.isOnHomeNetwork(homeSsidHash);

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

/// Provides a WledRepository based on Demo Mode, network location, and
/// webhook configuration.
///
/// Priority:
/// 1. Demo Mode              → DemoWledRepository
/// 2. On home WiFi (local)   → WledService (direct HTTP — fastest, always preferred)
/// 3. Remote + webhook saved → CloudRelayRepository / MqttRelayRepository
/// 4. Remote, no webhook     → null (commands blocked)
/// 5. Offline                → null
final wledRepositoryProvider = Provider<WledRepository?>((ref) {
  // ── 1. Demo / reviewer mode ───────────────────────────────────────────────
  final isDemo = ref.watch(demoModeProvider);
  if (isDemo) return DemoWledRepository();

  final userId = ref.watch(authStateProvider).maybeWhen(
    data: (user) => user?.uid,
    orElse: () => null,
  );
  if (userId == ReviewerSeedService.reviewerUserId) {
    return DemoWledRepository();
  }

  // ── 2. Require a selected device ─────────────────────────────────────────
  final ip = ref.watch(selectedDeviceIpProvider);
  if (ip == null) return null;

  // ── 3. User profile ───────────────────────────────────────────────────────
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );

  // ── 4. Determine network location ────────────────────────────────────────
  final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (status) => status,
    orElse: () => ConnectivityStatus.local,
  );

  // ── 5. LOCAL NETWORK → always use direct HTTP ──────────────────────────
  //
  // When the user is on the same WiFi as the controller, direct HTTP is
  // faster and more reliable than any relay. Use it regardless of whether
  // a webhook is configured — the webhook is for remote access, not local.
  if (connectivityStatus == ConnectivityStatus.local) {
    debugPrint('🏠 WledRepository: Local mode — direct HTTP to $ip');
    return WledService('http://$ip');
  }

  // ── 6. REMOTE / OFFLINE → use webhook relay if configured ──────────────
  final webhookUrl = userProfile?.webhookUrl;
  final hasWebhook = webhookUrl != null && webhookUrl.isNotEmpty;

  if (connectivityStatus == ConnectivityStatus.offline) {
    debugPrint('📵 WledRepository: Offline — no repository');
    return null;
  }

  // Remote network with webhook configured and enabled
  if (hasWebhook && userProfile?.remoteAccessEnabled == true) {
    final controllerId = ref.watch(selectedControllerIdProvider);

    // MQTT relay takes priority over webhook if configured and authenticated.
    final backendService = ref.watch(luminaBackendServiceProvider);
    if (userProfile?.mqttRelayEnabled == true &&
        backendService.isAuthenticated &&
        controllerId != null) {
      debugPrint('📡 WledRepository: MQTT relay (remote mode)');
      return MqttRelayRepository(
        backendService: backendService,
        deviceId: controllerId,
        deviceSerial: null,
      );
    }

    if (userId != null && controllerId != null) {
      debugPrint('☁️ WledRepository: Webhook relay — remote access');
      debugPrint('   Webhook URL: $webhookUrl');
      return CloudRelayRepository(
        userId: userId,
        controllerId: controllerId,
        controllerIp: ip,
        webhookUrl: webhookUrl,
      );
    }

    // Webhook configured but userId/controllerId temporarily unavailable.
    debugPrint('⚠️ WledRepository: Webhook configured but userId/controllerId '
        'unavailable — blocking commands');
    return null;
  }

  // Remote network, no webhook configured — cannot route commands.
  debugPrint('⚠️ WledRepository: Remote network but no webhook URL saved — '
      'commands blocked. Configure a webhook URL in Remote Access settings.');
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
            // Extract the full color sequence (all colors in segment)
            final List<Color> colorSequence = [];
            Color? primaryColor;
            int ww = state.warmWhite;

            for (final c in cols) {
              if (c is List && c.length >= 3) {
                final rr = (c[0] as num).toInt().clamp(0, 255);
                final gg = (c[1] as num).toInt().clamp(0, 255);
                final bb = (c[2] as num).toInt().clamp(0, 255);

                // Skip black/off colors in the sequence display
                if (rr > 0 || gg > 0 || bb > 0) {
                  colorSequence.add(Color.fromARGB(255, rr, gg, bb));
                }

                // First color becomes primary
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
    if (service == null) return;

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
