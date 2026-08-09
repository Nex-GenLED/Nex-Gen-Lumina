// lib/features/schedule/base_ladder_repair_feature_flag.dart
//
// Firestore-backed KILL SWITCH for the base-ladder segment repair.
//
// WHAT IT GATES: whether `isNglOnPresetSatisfied` asserts SEGMENT state on the
// NGL ON ladder (presets 1/3/4/5). With it ON (the default), a stored ON preset
// whose segments are all off is treated as UNSATISFIED and re-psaved with every
// segment on — repairing damage caused by the ambient-capture defect
// (audit/BASE_LADDER.md). With it OFF, the predicate falls back to the
// pre-repair behaviour (name + root `on` only) and damaged presets are skipped
// exactly as they were before.
//
// ⚠️ DEFAULTS **TRUE** — the opposite of solar_scheduling, deliberately.
//
// This is a REPAIR for a defect that leaves houses permanently dark at sunset,
// not a new capability being eased in. A degraded flag read (missing doc,
// Firestore error, offline, loading window) must not silently withhold the fix
// the way the solar flag's false-default silently withheld solar for the whole
// fleet (memory/project_solar_schedules_never_fire). So every degraded state
// yields TRUE and the repair proceeds.
//
// WHY A KILL SWITCH EXISTS AT ALL — the one risk we cannot see:
// the app has no way to record a deliberate channel exclusion (audit/
// BASE_LADDER.md §4d: per-channel power is live-state only, DeviceChannel has
// no enabled field, participation is show-scoped). So in the app's own model,
// every all-segments-off ON preset is damage. But a channel could have been
// excluded OUTSIDE the app — WLED's own web UI, a dealer's manual setup, a
// physically disconnected run — and the repair would relight it. That is
// invisible to us and unknowable remotely (the fleet sweep cannot run, §5b).
// If a customer reports a channel coming back that they had turned off, set
// `enabled: false` here to stop the repair fleet-wide without a release.
//
// Lives at config/base_ladder_repair, field `enabled`.
// NOTE: firestore.rules needs a matching `match /config/base_ladder_repair`
// block with public read, or the client 403s. Because this flag fails OPEN the
// consequence of a missing rule is a kill switch that cannot be pulled, not a
// withheld fix — but it still must be deployed. See audit/BASE_LADDER.md §6.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kBaseLadderRepairFlagCollection = 'config';
const String kBaseLadderRepairFlagDocId = 'base_ladder_repair';

/// Stream the base-ladder-repair kill switch. Defaults to `true` for every
/// degraded state — missing doc, missing/non-boolean field, Firestore error.
/// Only an explicit `enabled: false` disables the repair.
final baseLadderRepairEnabledProvider = StreamProvider<bool>((ref) async* {
  bool? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kBaseLadderRepairFlagCollection)
        .doc(kBaseLadderRepairFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final value = _extractEnabled(snap);
      if (value != lastEmitted) {
        debugPrint('BaseLadderRepair: enabled = $value');
        lastEmitted = value;
      }
      yield value;
    }
  } catch (e) {
    debugPrint(
        'BaseLadderRepair: feature-flag stream error — $e (defaulting to TRUE)');
    yield true;
  }
});

/// Only an explicit `enabled: false` turns the repair off. Anything else —
/// absent doc, null data, non-boolean field — leaves it ON.
bool _extractEnabled(DocumentSnapshot<Map<String, dynamic>> snap) {
  if (!snap.exists) return true;
  final data = snap.data();
  if (data == null) return true;
  final raw = data['enabled'];
  if (raw is bool) return raw;
  return true;
}

/// Synchronous read for call sites that can't await the stream (schedule sync).
/// Defaults to `true` during the loading window and on any error.
final baseLadderRepairEnabledSyncProvider = Provider<bool>((ref) {
  return ref.watch(baseLadderRepairEnabledProvider).maybeWhen(
        data: (v) => v,
        orElse: () => true,
      );
});

/// One-time bootstrap so the Firestore console has a doc to edit. Creates the
/// flag with `enabled:true` if absent. Best-effort; failures are logged, never
/// rethrown. Safe to call on every launch (no-op once the doc exists).
Future<void> bootstrapBaseLadderRepairFlagDoc() async {
  try {
    final doc = FirebaseFirestore.instance
        .collection(kBaseLadderRepairFlagCollection)
        .doc(kBaseLadderRepairFlagDocId);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set(<String, dynamic>{
      'enabled': true,
      'lastModified': FieldValue.serverTimestamp(),
      'modifiedBy': 'system_bootstrap',
      'notes': 'Auto-created ENABLED. Kill switch for the base-ladder segment '
          'repair (audit/BASE_LADDER.md). Set enabled=false ONLY if a customer '
          'reports a channel relighting that they had deliberately turned off '
          'outside the app (WLED web UI, dealer setup, disconnected run) — the '
          'one case the repair cannot distinguish from damage.',
    });
    debugPrint(
        'BaseLadderRepair: bootstrapped config/base_ladder_repair (enabled=true)');
  } catch (e) {
    debugPrint('BaseLadderRepair: bootstrap failed — $e (safe; defaults TRUE)');
  }
}
