// lib/features/schedule/calendar_lease_feature_flag.dart
//
// Item #61 Workstream B Prompt 5 — Firestore-backed feature flag
// gating live WLED writes from the lease manager.
//
// The flag lives at config/calendar_leases.liveWritesEnabled. It
// defaults to FALSE: lease writes are mocked (logged-only) until a
// human flips the flag via the Firestore console after Tyler's
// home-controller verification (Decision 7). Once flipped, the
// .snapshots() stream propagates the change without an app restart.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kCalendarLeaseFlagCollection = 'config';
const String kCalendarLeaseFlagDocId = 'calendar_leases';

/// Stream the live-writes feature flag. Defaults to `false` for any
/// degraded state — missing doc, missing field, non-boolean field,
/// Firestore error.
///
/// Consumers read this synchronously inside the lease manager via
/// `.maybeWhen(data: ..., orElse: () => false)`; the safe default
/// during the StreamProvider's initial loading window matches the
/// post-restart cold-start expectation.
final calendarLeaseLiveWritesEnabledProvider =
    StreamProvider<bool>((ref) async* {
  // ignore: avoid_print — debugPrint is the codebase convention for log
  // visibility in release builds via Logcat. Surface every flip so the
  // on-device verification session has a clear timeline.
  bool? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kCalendarLeaseFlagCollection)
        .doc(kCalendarLeaseFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final value = _extractLiveWritesEnabled(snap);
      if (value != lastEmitted) {
        debugPrint('CalendarLease: liveWritesEnabled = $value');
        lastEmitted = value;
      }
      yield value;
    }
  } catch (e) {
    debugPrint('CalendarLease: feature-flag stream error — $e '
        '(defaulting to false)');
    yield false;
  }
});

bool _extractLiveWritesEnabled(DocumentSnapshot<Map<String, dynamic>> snap) {
  if (!snap.exists) return false;
  final data = snap.data();
  if (data == null) return false;
  final raw = data['liveWritesEnabled'];
  if (raw is bool) return raw;
  return false;
}

/// One-time bootstrap. Creates the flag document with safe defaults
/// if it doesn't exist yet so the Firestore console has something to
/// edit. Safe to call on every cold launch — does nothing on the
/// repeat call.
///
/// Failures are logged but never rethrown — bootstrap is best-effort.
/// If Firestore is offline at boot, the next app launch retries.
Future<void> bootstrapCalendarLeaseFlagDoc() async {
  try {
    final doc = FirebaseFirestore.instance
        .collection(kCalendarLeaseFlagCollection)
        .doc(kCalendarLeaseFlagDocId);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set(<String, dynamic>{
      'liveWritesEnabled': false,
      'lastModified': FieldValue.serverTimestamp(),
      'modifiedBy': 'system_bootstrap',
      'notes': 'Auto-created. Set liveWritesEnabled=true to activate '
          'CalendarEntry lease writes against live WLED controllers.',
    });
    debugPrint('CalendarLease: bootstrapped config/calendar_leases doc '
        '(liveWritesEnabled=false)');
  } catch (e) {
    debugPrint('CalendarLease: bootstrap failed — $e '
        '(safe; next launch retries; flag defaults to false in-memory)');
  }
}
