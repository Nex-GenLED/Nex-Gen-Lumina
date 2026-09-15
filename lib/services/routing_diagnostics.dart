import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// #114 routing diagnostics — READ-ONLY instrumentation of the local-vs-bridge
/// decision.
///
/// Nothing in this file influences which path a command takes. It records:
///  - what the most recent connectivity check saw (Wi-Fi reported? home
///    network name readable? matched the saved fingerprint?), published by
///    `ConnectivityService._checkConnectivity`;
///  - which path every ROUTED command actually took — `direct` from the
///    [wledRepositoryProvider]'s `WledService`, `bridge` from
///    `CloudRelayRepository._executeCommand`.
///
/// Records drive the dashboard's Direct / Via Bridge badge and are persisted
/// in batches to `users/{uid}/debug_errors` (context `routing_decisions`) —
/// the one owner-writable diagnostics path that needs no rules deploy, pruned
/// after 30 days by `scheduledDataCleanup`. No SSID and no IP is ever stored.
///
/// Deliberately NOT recorded: the Remote Access screen's bridge check and the
/// startup `bridgeHealthProvider` ping. Both write to the relay queue whatever
/// the routing is, so counting them would paint the badge "Via Bridge" while
/// commands go direct (the 2026-09-15 live-test finding).

enum RoutePath { direct, bridge }

String routePathWireName(RoutePath path) =>
    path == RoutePath.direct ? 'direct' : 'bridge';

/// Why a connectivity check produced its outcome. One code per branch of
/// `ConnectivityService._checkConnectivity` / `isOnHomeNetwork`.
class ConnectivityCheckReason {
  const ConnectivityCheckReason._();

  static const noConnection = 'no_connection';
  static const wifiNotReported = 'wifi_not_reported';
  static const noHomeFingerprint = 'no_home_fingerprint';
  static const ssidUnreadableAssumedLocal = 'ssid_unreadable_assumed_local';
  static const ssidMatched = 'ssid_matched';
  static const ssidMismatch = 'ssid_mismatch';
  static const compareErrorAssumedLocal = 'compare_error_assumed_local';
}

/// Mutable capture that `ConnectivityService.isOnHomeNetwork` fills in when a
/// caller passes one. Assignments only — the evaluation itself is unchanged.
class HomeNetworkEvaluation {
  bool? fingerprintConfigured;
  bool? ssidReadable;
  bool? ssidMatched;
  String? ssidFailureReason;
  String? reason;
}

/// Reduce a `ConnectivityService.lastSsidFailureReason` to its leading code.
/// Reasons can carry an exception message after a colon; only the code before
/// it is kept, so nothing environment-specific reaches Firestore.
String? sanitizeSsidFailureReason(String? reason) {
  if (reason == null || reason.isEmpty) return null;
  final colon = reason.indexOf(':');
  return colon < 0 ? reason : reason.substring(0, colon);
}

/// What one connectivity check saw and decided.
@immutable
class ConnectivityCheckSnapshot {
  const ConnectivityCheckSnapshot({
    required this.checkedAt,
    required this.reportedTypes,
    required this.wifiReported,
    required this.outcome,
    required this.reason,
    this.homeFingerprintConfigured,
    this.ssidReadable,
    this.ssidMatched,
    this.ssidFailureReason,
  });

  final DateTime checkedAt;

  /// `ConnectivityResult` names as the plugin reported them (e.g. `wifi`,
  /// `other`, `mobile`).
  final List<String> reportedTypes;
  final bool wifiReported;

  /// Null when the check never reached the home-network comparison.
  final bool? homeFingerprintConfigured;

  /// Null when the network name was never read.
  final bool? ssidReadable;

  /// Null unless a readable name was compared.
  final bool? ssidMatched;
  final String? ssidFailureReason;

  /// `local`, `remote` or `offline`.
  final String outcome;
  final String reason;
}

/// The path one routed command took, with the connectivity check in force.
@immutable
class RoutingDecisionRecord {
  const RoutingDecisionRecord({
    required this.at,
    required this.path,
    required this.command,
    this.check,
  });

  final DateTime at;
  final RoutePath path;

  /// Relay command type (`getState`, `applyJson`, …) or LAN request path
  /// (`/json/state`, …).
  final String command;
  final ConnectivityCheckSnapshot? check;

  int? get checkAgeMs =>
      check == null ? null : at.difference(check!.checkedAt).inMilliseconds;

  Map<String, dynamic> toJson() => {
        'at': Timestamp.fromDate(at),
        'path': routePathWireName(path),
        'command': command,
        'wifi_reported': check?.wifiReported,
        'ssid_readable': check?.ssidReadable,
        'ssid_matched': check?.ssidMatched,
        'home_fingerprint_configured': check?.homeFingerprintConfigured,
        'ssid_failure_reason': check?.ssidFailureReason,
        'reported_types': check?.reportedTypes,
        'check_outcome': check?.outcome,
        'check_reason': check?.reason,
        'check_age_ms': checkAgeMs,
      };
}

/// Persists one batch. Returns true when the batch may be dropped from the
/// buffer (written, or deliberately discarded), false to keep it for retry.
typedef RoutingBatchSink = Future<bool> Function(
  List<Map<String, dynamic>> records,
  int dropped,
);

/// Process-wide recorder. Never throws, never starts a timer.
class RoutingDiagnostics {
  RoutingDiagnostics({RoutingBatchSink? sink, DateTime Function()? clock})
      : _sink = sink ?? firestoreRoutingBatchSink,
        _clock = clock ?? DateTime.now;

  static RoutingDiagnostics instance = RoutingDiagnostics();

  /// Replace [instance] with a fresh recorder whose sink discards by default.
  @visibleForTesting
  static void resetForTest({
    RoutingBatchSink? sink,
    DateTime Function()? clock,
  }) {
    instance = RoutingDiagnostics(sink: sink ?? _discardSink, clock: clock);
  }

  static Future<bool> _discardSink(List<Map<String, dynamic>> _, int __) async =>
      true;

  /// A batch is written once the oldest buffered record is this old…
  static const flushInterval = Duration(seconds: 60);

  /// …or once this many records are buffered, whichever comes first.
  static const maxRecordsPerBatch = 100;

  /// Hard cap while a write is failing or in flight; oldest records drop.
  static const maxPending = 300;

  /// Kept in memory for the dashboard's routing sheet.
  static const recentCapacity = 50;

  final RoutingBatchSink _sink;
  final DateTime Function() _clock;

  ConnectivityCheckSnapshot? _lastCheck;

  /// The path of the most recent routed command; null until one is sent.
  final ValueNotifier<RoutePath?> currentPath = ValueNotifier<RoutePath?>(null);

  final List<RoutingDecisionRecord> _recent = <RoutingDecisionRecord>[];
  final List<RoutingDecisionRecord> _pending = <RoutingDecisionRecord>[];
  int _dropped = 0;
  DateTime? _windowStart;
  bool _flushing = false;

  ConnectivityCheckSnapshot? get lastCheck => _lastCheck;

  /// Newest first.
  List<RoutingDecisionRecord> get recent =>
      List<RoutingDecisionRecord>.unmodifiable(_recent.reversed);

  @visibleForTesting
  int get pendingCount => _pending.length;

  void recordConnectivityCheck(ConnectivityCheckSnapshot snapshot) {
    _lastCheck = snapshot;
  }

  void record(RoutePath path, String command) {
    try {
      final now = _clock();
      final entry = RoutingDecisionRecord(
        at: now,
        path: path,
        command: command,
        check: _lastCheck,
      );
      _recent.add(entry);
      if (_recent.length > recentCapacity) _recent.removeAt(0);
      _pending.add(entry);
      if (_pending.length > maxPending) {
        _pending.removeAt(0);
        _dropped++;
      }

      // Deferred: record() runs inside repository calls that can happen while
      // a provider or widget is building, and a synchronous notify would
      // rebuild the badge mid-build.
      scheduleMicrotask(() {
        if (currentPath.value != path) currentPath.value = path;
      });

      final windowStart = _windowStart ??= now;
      if (now.difference(windowStart) >= flushInterval ||
          _pending.length >= maxRecordsPerBatch) {
        unawaited(flush());
      }
    } catch (_) {
      // Diagnostics must never break a command.
    }
  }

  /// Write the oldest buffered records as one batch. Safe to call at any time.
  Future<void> flush() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    final batch = _pending.take(maxRecordsPerBatch).toList();
    try {
      final done = await _sink(
        batch.map((r) => r.toJson()).toList(),
        _dropped,
      );
      if (done) {
        final sent = Set<RoutingDecisionRecord>.identity()..addAll(batch);
        _pending.removeWhere(sent.contains);
        _dropped = 0;
      }
    } catch (_) {
      // Keep the batch; the next flush retries it.
    } finally {
      _windowStart = _pending.isEmpty ? null : _clock();
      _flushing = false;
    }
  }
}

/// Default sink: one `users/{uid}/debug_errors` document per batch.
Future<bool> firestoreRoutingBatchSink(
  List<Map<String, dynamic>> records,
  int dropped,
) async {
  // No Firebase in this isolate (background service, tests) or nobody signed
  // in: there is no owner to write under, so discard rather than grow.
  if (Firebase.apps.isEmpty) return true;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return true;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('debug_errors')
      .add({
    'timestamp': FieldValue.serverTimestamp(),
    'context': 'routing_decisions',
    'error_type': 'RoutingDecisionBatch',
    'error': '#114 routing diagnostics: ${records.length} records'
        '${dropped > 0 ? ', $dropped dropped' : ''}',
    'stack': '',
    'platform': Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'other',
    'record_count': records.length,
    'dropped': dropped,
    'records': records,
  });
  return true;
}
