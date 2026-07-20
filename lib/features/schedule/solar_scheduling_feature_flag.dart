// lib/features/schedule/solar_scheduling_feature_flag.dart
//
// Firestore-backed feature flag gating CORRECTLY-ENCODED sunrise/sunset
// scheduling on WLED 0.15.1.
//
// When OFF (default), schedule_sync keeps the a75f504 refuse-and-warn: any
// solar schedule is refused (never armed), because the app's OLD hour:24/25
// encoding never fired. When ON, solar boundaries route through the real
// 0.15.1 positional encoding (hour:255 marker at timers.ins slot 8 = sunrise /
// slot 9 = sunset, minute field = offset) and can actually fire.
//
// BENCH GATE: this flag must NOT be flipped ON until a real controller is
// observed firing at ACTUAL sunrise AND sunset (nonzero offset confirmed) on
// WLED 0.15.1. No unit test substitutes — the whole point is that the firmware
// contract was wrong in code and only hardware proves the fix. See
// memory/project_solar_schedules_never_fire.
//
// Mirrors sync_fanout_feature_flag.dart. Lives at config/solar_scheduling,
// field `enabled`, DEFAULTS FALSE for every degraded state.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kSolarSchedulingFlagCollection = 'config';
const String kSolarSchedulingFlagDocId = 'solar_scheduling';

/// Stream the solar-scheduling feature flag. Defaults to `false` for any
/// degraded state — missing doc, missing/non-boolean field, Firestore error.
final solarSchedulingEnabledProvider = StreamProvider<bool>((ref) async* {
  bool? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kSolarSchedulingFlagCollection)
        .doc(kSolarSchedulingFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final value = _extractEnabled(snap);
      if (value != lastEmitted) {
        debugPrint('SolarScheduling: enabled = $value');
        lastEmitted = value;
      }
      yield value;
    }
  } catch (e) {
    debugPrint(
        'SolarScheduling: feature-flag stream error — $e (defaulting to false)');
    yield false;
  }
});

bool _extractEnabled(DocumentSnapshot<Map<String, dynamic>> snap) {
  if (!snap.exists) return false;
  final data = snap.data();
  if (data == null) return false;
  final raw = data['enabled'];
  if (raw is bool) return raw;
  return false;
}

/// Synchronous read for call sites that can't await the stream (schedule sync,
/// the AI solar path). Defaults to `false` during the loading window or any
/// error — the safe default (solar stays refused, production behavior).
final solarSchedulingEnabledSyncProvider = Provider<bool>((ref) {
  return ref.watch(solarSchedulingEnabledProvider).maybeWhen(
        data: (v) => v,
        orElse: () => false,
      );
});

/// One-time bootstrap so the Firestore console has a doc to edit. Creates the
/// flag with `enabled:false` if absent. Best-effort; failures are logged, never
/// rethrown. Safe to call on every launch (no-op once the doc exists).
Future<void> bootstrapSolarSchedulingFlagDoc() async {
  try {
    final doc = FirebaseFirestore.instance
        .collection(kSolarSchedulingFlagCollection)
        .doc(kSolarSchedulingFlagDocId);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set(<String, dynamic>{
      'enabled': false,
      'lastModified': FieldValue.serverTimestamp(),
      'modifiedBy': 'system_bootstrap',
      'notes': 'Auto-created. Set enabled=true ONLY after a real WLED 0.15.1 '
          'controller is observed firing at actual sunrise AND sunset with a '
          'nonzero offset (the bench gate). Until then the a75f504 refuse '
          'stays in force.',
    });
    debugPrint(
        'SolarScheduling: bootstrapped config/solar_scheduling (enabled=false)');
  } catch (e) {
    debugPrint('SolarScheduling: bootstrap failed — $e (safe; defaults false)');
  }
}
