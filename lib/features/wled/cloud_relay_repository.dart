import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/remote_command.dart';

/// WLED Repository implementation for remote (cloud relay) control.
///
/// When the user is away from their home network, this repository queues
/// commands to Firestore. The command can be executed by either:
///
/// **ESP32 Bridge Mode (recommended for commercial installs):**
/// - An ESP32 device on the customer's local network polls Firestore
/// - No webhook URL needed, no port forwarding required
/// - Customer just needs WiFi - completely plug-and-play
///
/// **Webhook Mode (for DIY users):**
/// - A Firebase Cloud Function forwards commands to a webhook URL
/// - Requires Dynamic DNS and port forwarding setup
///
/// The command flow is:
/// 1. App writes command to `/users/{uid}/commands/{commandId}`
/// 2a. (Bridge Mode) ESP32 Bridge picks up command and executes locally
/// 2b. (Webhook Mode) Cloud Function POSTs to user's webhook URL
/// 3. Command status updated in Firestore
/// 4. App polls/listens for status update
class CloudRelayRepository implements WledRepository {
  final String userId;
  final String controllerId;
  final String controllerIp;

  /// Webhook URL for DIY mode. Leave empty for ESP32 Bridge mode.
  final String webhookUrl;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Timeout for waiting for command execution.
  static const _commandTimeout = Duration(seconds: 30);

  /// Polling interval when waiting for command completion.
  static const _pollInterval = Duration(milliseconds: 500);

  CloudRelayRepository({
    required this.userId,
    required this.controllerId,
    required this.controllerIp,
    required this.webhookUrl,
  });

  /// Reference to the commands collection for this user.
  CollectionReference<Map<String, dynamic>> get _commandsRef =>
      _firestore.collection('users').doc(userId).collection('commands');

  /// Queue a command and wait for its execution result.
  Future<Map<String, dynamic>?> _executeCommand(String type, Map<String, dynamic> payload) async {
    try {
      // Create the command document
      final command = RemoteCommand.create(
        type: type,
        payload: payload,
        controllerId: controllerId,
        controllerIp: controllerIp,
        webhookUrl: webhookUrl,
      );

      debugPrint('☁️ CloudRelay: Queueing command: $type');
      debugPrint('   Payload: ${jsonEncode(payload)}');

      // Write to Firestore
      final docRef = await _commandsRef.add(command.toFirestore());
      final commandId = docRef.id;

      debugPrint('☁️ CloudRelay: Command queued with ID: $commandId');

      // Wait for the command to complete
      final result = await _waitForCompletion(commandId);

      if (result == null) {
        debugPrint('❌ CloudRelay: Command timed out');
        // Mark as timeout
        await docRef.update({'status': 'timeout'});
        return null;
      }

      if (result.status == CommandStatus.completed) {
        debugPrint('✅ CloudRelay: Command completed successfully');
        return result.result;
      } else {
        debugPrint('❌ CloudRelay: Command failed: ${result.error}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ CloudRelay: Error executing command: $e');
      return null;
    }
  }

  /// Wait for a command to complete by polling Firestore.
  Future<RemoteCommand?> _waitForCompletion(String commandId) async {
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < _commandTimeout) {
      try {
        final doc = await _commandsRef.doc(commandId).get();
        if (doc.exists) {
          final command = RemoteCommand.fromFirestore(doc);
          if (command.isComplete) {
            return command;
          }
        }
      } catch (e) {
        debugPrint('CloudRelay: Error polling command status: $e');
      }

      // Wait before polling again
      await Future.delayed(_pollInterval);
    }

    return null; // Timeout
  }

  /// Execute a command and return success/failure boolean.
  Future<bool> _executeBool(String type, Map<String, dynamic> payload) async {
    final result = await _executeCommand(type, payload);
    return result != null;
  }

  // ==================== WledRepository Implementation ====================

  @override
  Future<Map<String, dynamic>?> getState() async {
    // For getState, we need the actual response data
    return _executeCommand('getState', {});
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
    final Map<String, dynamic> payload = {};
    if (on != null) payload['on'] = on;
    if (brightness != null) payload['bri'] = brightness.clamp(0, 255);

    // Build segment update
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

    return _executeBool('setState', payload);
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    return _executeBool('applyJson', normalizeWledPayload(payload));
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    return _executeBool('applyConfig', cfg);
  }

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async {
    // LED map upload is complex - for now, return false (not supported remotely)
    debugPrint('☁️ CloudRelay: LED map upload not supported remotely');
    return false;
  }

  @override
  Future<bool> configureSyncReceiver() async {
    final payload = {
      'udpn': {'recv': true}
    };
    return _executeBool('configureSyncReceiver', payload);
  }

  @override
  Future<bool> configureSyncSender({List<String> targets = const [], int ddpPort = 4048}) async {
    final payload = {
      'udpn': {'send': true},
      'ddp': {
        'en': true,
        'port': ddpPort,
        if (targets.isNotEmpty) 'targets': targets,
      }
    };
    return _executeBool('configureSyncSender', payload);
  }

  @override
  Future<bool> supportsRgbw() async {
    // Query device info remotely
    final result = await _executeCommand('getInfo', {});
    if (result == null) return false;
    try {
      final leds = result['leds'];
      if (leds is Map) {
        final v = leds['rgbw'];
        if (v is bool) return v;
      }
    } catch (_) {}
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
      debugPrint('CloudRelay fetchSegments parse error: $e');
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
    return _executeBool('renameSegment', payload);
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
        final rgbw = rgbToRgbw(color.red, color.green, color.blue, explicitWhite: white);
        m['col'] = [rgbw];
      }
      segs.add(m);
    }
    return _executeBool('applyToSegments', {'seg': segs});
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

    return _executeBool('updateSegmentConfig', {'seg': [segUpdate]});
  }

  @override
  Future<int?> getTotalLedCount() async {
    // For cloud relay, we need to query the device info
    final result = await _executeCommand('getInfo', {});
    if (result != null) {
      final leds = result['leds'];
      if (leds is Map) {
        final count = leds['count'];
        if (count is int) return count;
        if (count is num) return count.toInt();
      }
    }
    return null;
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    if (presetId < 1 || presetId > 250) return false;
    // Save preset via cloud relay by sending the state with psave field
    final payload = <String, dynamic>{
      ...state,
      'psave': presetId,
    };
    if (presetName != null && presetName.isNotEmpty) {
      payload['n'] = presetName;
    }
    return _executeBool('savePreset', payload);
  }

  @override
  Future<bool> loadPreset(int presetId) async {
    if (presetId < 1 || presetId > 250) return false;
    return _executeBool('loadPreset', {'ps': presetId});
  }
}
