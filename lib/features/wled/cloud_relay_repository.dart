import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
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

  final FirebaseFirestore _firestore;

  /// Timeout for waiting for command execution.
  ///
  /// Sized to cover the worst-case tail observed in production: under
  /// queue pressure (poller backpressure + serial bridge processing)
  /// individual setState commands have been measured at 30-32s. 45s
  /// keeps the snackbar from firing while the bridge is still completing
  /// the command. Pair-tuned with the 3s remote poll cadence in
  /// WledNotifier (Item #76 latency fix).
  ///
  /// Instance field (defaulting to [_kDefaultCommandTimeout]) so tests can
  /// inject a short window; production behaviour is unchanged at 45s.
  static const _kDefaultCommandTimeout = Duration(seconds: 45);
  final Duration _commandTimeout;

  /// Polling interval — retained as a fallback knob, but the primary
  /// completion path is a Firestore `snapshots()` listener now. The poll
  /// was a 500 ms `.get()` loop that added ~250 ms avg of needless lag
  /// per command (BRIDGE_LATENCY_AUDIT_2026-05.md §2).
  // ignore: unused_field
  static const _pollInterval = Duration(milliseconds: 500);

  CloudRelayRepository({
    required this.userId,
    required this.controllerId,
    required this.controllerIp,
    required this.webhookUrl,
    FirebaseFirestore? firestore,
    Duration? commandTimeout,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _commandTimeout = commandTimeout ?? _kDefaultCommandTimeout;

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

      // ── BEGIN BridgeDiag ──────────────────────────────────────────
      final diagSw = Stopwatch()..start();
      debugPrint('BridgeDiag: command written → docId=$commandId, controllerIp=$controllerIp');
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? diagSub;
      diagSub = _commandsRef.doc(commandId).snapshots().listen((snap) {
        final data = snap.data();
        final status = data?['status'] ?? 'unknown';
        final elapsed = diagSw.elapsedMilliseconds;
        debugPrint('BridgeDiag: doc status changed → $status at ${elapsed}ms');
      }, onError: (e) {
        debugPrint('BridgeDiag: snapshot listener error → $e');
      });
      // Auto-cancel after the command timeout window
      Future.delayed(_commandTimeout, () {
        if (diagSw.isRunning) {
          debugPrint('BridgeDiag: ${_commandTimeout.inSeconds}s timeout — document never acknowledged by bridge');
          diagSw.stop();
        }
        diagSub?.cancel();
      });
      // ── END BridgeDiag ────────────────────────────────────────────

      // Wait for the command to complete
      final result = await _waitForCompletion(commandId);

      // Stop diag stopwatch so the auto-cancel timeout message won't fire
      diagSw.stop();
      diagSub?.cancel();

      if (result == null) {
        // The watchdog elapsed without the listener observing a terminal
        // status. DO NOT blind-overwrite status:'timeout' (#52) — the bridge
        // may have completed the command while our snapshots() listener
        // silently died (swallowed onError / parse throw), leaving a
        // populated `result` we never saw. Do ONE authoritative,
        // transactional read: a late result MUST win. Only stamp 'timeout'
        // when the doc genuinely has no result and is still non-terminal.
        final reconciled = await _reconcileAfterWatchdog(docRef, type, commandId);
        if (reconciled != null) {
          debugPrint('🔍 BridgeRouter: send result=completed (late, post-watchdog reconcile), error=none');
          return reconciled.result;
        }
        debugPrint('❌ CloudRelay: genuine timeout — no result after ${_commandTimeout.inSeconds}s '
            '(type=$type, docId=$commandId)');
        return null;
      }

      // Result-derived success: treat the command as succeeded when the doc
      // is marked completed OR carries a populated result, regardless of the
      // status label (defense-in-depth against a stale/raced status field).
      if (result.status == CommandStatus.completed || _hasResult(result)) {
        // End-to-end latency from Firestore createdAt to completedAt. Both
        // are server timestamps, so this is independent of client clock skew.
        final completedAt = result.completedAt;
        if (completedAt != null) {
          final latencyMs = completedAt.difference(result.createdAt).inMilliseconds;
          debugPrint('BridgeDiag: command latency=${latencyMs}ms, type=$type, controllerId=$controllerId');
        }
        debugPrint('🔍 BridgeRouter: send result=completed, error=none');
        return result.result;
      } else {
        debugPrint('🔍 BridgeRouter: send result=failed, error=${result.error}');
        return null;
      }
    } catch (e) {
      debugPrint('🔍 BridgeRouter: send result=EXCEPTION, error=$e');
      return null;
    }
  }

  /// Wait for a command to complete via a Firestore `snapshots()` listener.
  ///
  /// Replaces the previous 500 ms `.get()` poll loop. Returns the terminal
  /// [RemoteCommand] when the doc's status flips to completed/failed/timeout
  /// (i.e. `isComplete`), or `null` if [_commandTimeout] elapses first —
  /// same contract callers depend on.
  ///
  /// The diag block in [_executeCommand] already proves this path:
  /// `_commandsRef.doc(commandId).snapshots()` delivers status changes
  /// promptly. Snapshots fire immediately with the current state and on
  /// every subsequent update, so a status that flips while the listener
  /// is being set up is still observed on the first delivery.
  ///
  /// Cleanup: the subscription and timeout timer are cancelled exactly
  /// once via [complete]; the Completer guard prevents double-resolution
  /// when the timeout and a real status update race.
  Future<RemoteCommand?> _waitForCompletion(String commandId) async {
    final completer = Completer<RemoteCommand?>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
    Timer? timeoutTimer;

    void resolve(RemoteCommand? value) {
      if (completer.isCompleted) return;
      sub?.cancel();
      timeoutTimer?.cancel();
      completer.complete(value);
    }

    sub = _commandsRef.doc(commandId).snapshots().listen(
      (snap) {
        if (!snap.exists) return;
        try {
          final command = RemoteCommand.fromFirestore(snap);
          // Resolve on a terminal status OR a populated result — a parse-safe
          // success is detected even if the status label lags. The catch
          // below keeps a parse throw from ending detection (the stream stays
          // subscribed; the watchdog reconcile is the final backstop).
          if (command.isComplete || _hasResult(command)) {
            resolve(command);
          }
        } catch (e) {
          debugPrint('CloudRelay: snapshot parse error: $e');
        }
      },
      onError: (e) async {
        // A stream error must NOT silently kill detection (#52): the prior
        // code only debugPrinted, so a transient error left the listener dead
        // while the bridge later completed the command into a `result` we
        // never observed. Do a one-shot fallback get(); resolve if the doc is
        // already terminal/has a result, otherwise let the watchdog + reconcile
        // transaction make the final call.
        debugPrint('CloudRelay: snapshot listener error: $e — fallback get()');
        try {
          final snap = await _commandsRef.doc(commandId).get();
          if (snap.exists) {
            final command = RemoteCommand.fromFirestore(snap);
            if (command.isComplete || _hasResult(command)) {
              resolve(command);
            }
          }
        } catch (e2) {
          debugPrint('CloudRelay: fallback get() after listener error failed: $e2');
        }
      },
    );

    timeoutTimer = Timer(_commandTimeout, () => resolve(null));

    return completer.future;
  }

  /// True when the command doc carries a populated WLED result payload —
  /// the authoritative "this command actually succeeded" signal (#52). A
  /// command that returned valid state SUCCEEDED regardless of how long it
  /// took or what the status field happens to read.
  static bool _hasResult(RemoteCommand c) =>
      c.result != null && c.result!.isNotEmpty;

  /// Authoritative post-watchdog reconciliation (#52).
  ///
  /// Called only when [_waitForCompletion] elapsed without observing a
  /// terminal status. Reads the doc and decides the final outcome ATOMICALLY
  /// so a late bridge result can never be clobbered by a blind timeout write:
  ///
  ///   • result populated (or status already `completed`) → SUCCESS; returns
  ///     the [RemoteCommand]. No write — never stamp 'timeout' over a result.
  ///   • status already `failed`                          → terminal failure;
  ///     returns null. No timeout write.
  ///   • still `pending`/`executing` with no result        → genuine timeout;
  ///     stamps status:'timeout' inside the SAME transaction and returns null.
  ///
  /// Doing the read + conditional write in one transaction (rather than
  /// get()-then-update()) closes the smaller race the naive fix would
  /// reintroduce: between a separate get and update, the bridge could write a
  /// result that the update would then overwrite. Within the transaction the
  /// decision is consistent, and any bridge write that lands after commit
  /// (completed + result) wins on the persisted doc anyway.
  Future<RemoteCommand?> _reconcileAfterWatchdog(
    DocumentReference<Map<String, dynamic>> docRef,
    String type,
    String commandId,
  ) async {
    try {
      return await _firestore.runTransaction<RemoteCommand?>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return null;
        final cmd = RemoteCommand.fromFirestore(snap);

        // Late success — the listener missed it but the result is here.
        if (_hasResult(cmd) || cmd.status == CommandStatus.completed) {
          return cmd;
        }
        // Bridge explicitly failed — honor it; do not relabel as timeout.
        if (cmd.status == CommandStatus.failed) {
          return null;
        }
        // Genuine no-response: only NOW is 'timeout' correct, and only while
        // the doc is still non-terminal and result-less.
        if (cmd.status == CommandStatus.pending ||
            cmd.status == CommandStatus.executing) {
          tx.update(docRef, {'status': 'timeout'});
        }
        return null;
      });
    } catch (e) {
      // Transaction failure (offline, contention exhaustion) — fall back to
      // treating this as a timeout for the caller. We deliberately do NOT
      // blind-write status here; leaving the doc as-is lets a later bridge
      // write still land correctly.
      debugPrint('CloudRelay: watchdog reconcile txn failed for $commandId: $e — treating as timeout');
      return null;
    }
  }

  /// Test-only hook to drive [_reconcileAfterWatchdog] against a known doc
  /// state (the reconcile success-branch is otherwise hard to reach when the
  /// snapshots() listener resolves normally). Not used in production.
  @visibleForTesting
  Future<RemoteCommand?> debugReconcileAfterWatchdog(
          DocumentReference<Map<String, dynamic>> docRef) =>
      _reconcileAfterWatchdog(docRef, 'getState', docRef.id);

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

    // Route through applyJson so normalizeWledPayload pads col[] to 3 slots.
    // Mirrors the WledService.setState fix; the bridge dispatches all
    // non-getState/getInfo commands identically (POST /json/state) so the
    // command-name change from 'setState' to 'applyJson' is a no-op for
    // the controller. expandForParticipation pass-through (Rule 5: seg
    // has explicit id) preserves the targeted-single-seg shape.
    return applyJson(payload);
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    // Audit #4 chokepoint — same shape as WledService.applyJson. See
    // its docstring for the two-step pipeline (normalize then expand
    // for participation). Both repos MUST behave identically so local
    // and relay paths produce the same per-channel result.
    final participating = await getCachedParticipatingChannels();
    final normalized = normalizeWledPayload(payload);
    final expanded = expandForParticipation(normalized, participating);
    return _executeBool('applyJson', expanded);
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
  Future<WledHardwareConfig?> getConfig() async => null;

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
    } catch (e) {
      debugPrint('Error in CloudRelayRepository parsing RGBW support: $e');
    }
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
  Future<Map<int, String>> fetchPresetNames() async => const {};

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
    // Pre-normalize caller state so the preset persists with all 3 col
    // slots populated; mirrors the WledService.savePreset fix so local +
    // relay paths produce identical preset shapes on the controller.
    final normalizedState = normalizeWledPayload(state);
    // Save preset via cloud relay by sending the state with psave field
    final payload = <String, dynamic>{
      ...normalizedState,
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

  @override
  void invalidatePresetCache() {}

  @override
  void reset() {}
}
