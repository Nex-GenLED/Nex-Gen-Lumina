import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/lumina_backend_service.dart';

/// WLED Repository implementation for remote control via Lumina MQTT backend.
///
/// This repository sends commands to the Lumina backend server, which then
/// relays them to WLED devices via MQTT through HiveMQ Cloud.
///
/// Benefits over Firestore relay:
/// - Lower latency (direct MQTT vs Firestore polling)
/// - Works when device is on cellular network
/// - More reliable real-time communication
///
/// The command flow is:
/// 1. App sends HTTP request to Lumina Backend
/// 2. Backend publishes MQTT message to `lumina/{deviceId}/command`
/// 3. WLED device (subscribed to topic) receives and applies the command
/// 4. Device publishes status to `lumina/{deviceId}/status`
/// 5. Backend updates device state in PostgreSQL
class MqttRelayRepository implements WledRepository {
  final LuminaBackendService _backendService;
  final String deviceId;
  final String? deviceSerial;

  /// Cached state from last successful fetch
  Map<String, dynamic>? _cachedState;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(seconds: 2);

  MqttRelayRepository({
    required LuminaBackendService backendService,
    required this.deviceId,
    this.deviceSerial,
  }) : _backendService = backendService;

  /// Check if the backend service is ready for use.
  bool get isReady => _backendService.isAuthenticated;

  @override
  Future<Map<String, dynamic>?> getState() async {
    // Return cached state if still valid (avoids excessive API calls)
    if (_cachedState != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedState;
      }
    }

    // For now, we don't have a real-time state endpoint
    // The backend stores `current_state` from device status messages
    // We could add a GET /api/devices/:id endpoint that returns full state
    //
    // For MVP: return cached state or empty map
    // The poller will still work, just won't get live updates
    debugPrint('🌐 MqttRelay: getState() - returning cached/empty state');
    return _cachedState ?? {};
  }

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async {
    debugPrint('🌐 MqttRelay: setState(on=$on, bri=$brightness, speed=$speed)');

    final Map<String, dynamic> payload = {};
    if (on != null) payload['on'] = on;
    if (brightness != null) payload['bri'] = brightness.clamp(0, 255);

    // Build segment update for color/speed
    final Map<String, dynamic> segUpdate = {'id': 0};
    if (speed != null) segUpdate['sx'] = speed.clamp(0, 255);
    if (color != null || white != null) {
      final rgbw = rgbToRgbw(
        color?.red ?? 0,
        color?.green ?? 0,
        color?.blue ?? 0,
        explicitWhite: white,
        forceZeroWhite: forceRgbwZeroWhite == true,
      );
      segUpdate['col'] = [rgbw];
    }
    if (segUpdate.length > 1) {
      payload['seg'] = [segUpdate];
    }

    final result = await _backendService.sendWledState(deviceId, payload);

    if (result.success) {
      // Update local cache with the state we just sent
      _updateCache(payload);
    }

    return result.success;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    debugPrint('🌐 MqttRelay: applyJson');
    final result = await _backendService.sendWledState(deviceId, payload);
    if (result.success) {
      _updateCache(payload);
    }
    return result.success;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    debugPrint('🌐 MqttRelay: applyConfig');
    // Config updates go to /json/cfg endpoint on WLED
    // We send them as a special command type
    final result = await _backendService.sendCommand(
      deviceId,
      action: 'setConfig',
      payload: cfg,
    );
    return result.success;
  }

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async {
    // LED map upload requires file upload, not supported via MQTT
    debugPrint('🌐 MqttRelay: LED map upload not supported remotely');
    return false;
  }

  @override
  Future<bool> configureSyncReceiver() async {
    final payload = {
      'udpn': {'recv': true}
    };
    return applyConfig(payload);
  }

  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async {
    final payload = {
      'udpn': {'send': true},
      'ddp': {
        'en': true,
        'port': ddpPort,
        if (targets.isNotEmpty) 'targets': targets,
      }
    };
    return applyConfig(payload);
  }

  @override
  Future<bool> supportsRgbw() async {
    // Query device info - for now return false as default
    // TODO: Add getInfo command to backend and parse leds.rgbw
    debugPrint('🌐 MqttRelay: supportsRgbw() - defaulting to false');
    return false;
  }

  @override
  Future<List<WledSegment>> fetchSegments() async {
    final data = await getState();
    final List<WledSegment> result = [];
    if (data == null) return result;
    try {
      final seg = data['seg'];
      if (seg is List) {
        for (var i = 0; i < seg.length; i++) {
          final m = seg[i];
          if (m is Map) result.add(WledSegment.fromMap(m, i));
        }
      } else if (seg is Map) {
        result.add(WledSegment.fromMap(seg, 0));
      }
    } catch (e) {
      debugPrint('MqttRelay fetchSegments parse error: $e');
    }
    return result;
  }

  @override
  Future<bool> renameSegment({required int id, required String name}) async {
    final payload = {
      'seg': [
        {'id': id, 'n': name}
      ]
    };
    return applyJson(payload);
  }

  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async {
    if (ids.isEmpty) return true;
    final List<Map<String, dynamic>> segs = [];
    for (final id in ids) {
      final m = <String, dynamic>{'id': id};
      if (fx != null) m['fx'] = fx;
      if (speed != null) m['sx'] = speed.clamp(0, 255);
      if (intensity != null) m['ix'] = intensity.clamp(0, 255);
      if (color != null) {
        final rgbw = rgbToRgbw(
          color.red,
          color.green,
          color.blue,
          explicitWhite: white,
        );
        m['col'] = [rgbw];
      }
      segs.add(m);
    }
    return applyJson({'seg': segs});
  }

  @override
  List<WledPreset> getPresets() => const [];

  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async {
    final Map<String, dynamic> segUpdate = {'id': segmentId};
    if (start != null) segUpdate['start'] = start;
    if (stop != null) segUpdate['stop'] = stop;

    if (segUpdate.length <= 1) return true;

    return applyJson({'seg': [segUpdate]});
  }

  @override
  Future<int?> getTotalLedCount() async {
    // For MQTT relay, we rely on cached state or need to query
    // Since we don't have a direct info endpoint, return null for now
    // The backend would need to support a getInfo command
    debugPrint('🌐 MqttRelay: getTotalLedCount() - not yet supported via MQTT');
    return null;
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    if (presetId < 1 || presetId > 250) return false;
    // Save preset via MQTT relay by sending the state with psave field
    final payload = <String, dynamic>{
      ...state,
      'psave': presetId,
    };
    if (presetName != null && presetName.isNotEmpty) {
      payload['n'] = presetName;
    }
    debugPrint('🌐 MqttRelay: savePreset($presetId)');
    return applyJson(payload);
  }

  @override
  Future<bool> loadPreset(int presetId) async {
    if (presetId < 1 || presetId > 250) return false;
    debugPrint('🌐 MqttRelay: loadPreset($presetId)');
    return applyJson({'ps': presetId});
  }

  /// Update the local cache with sent state.
  void _updateCache(Map<String, dynamic> sentPayload) {
    _cachedState ??= {};
    _cachedState!.addAll(sentPayload);
    _cacheTime = DateTime.now();
  }
}
