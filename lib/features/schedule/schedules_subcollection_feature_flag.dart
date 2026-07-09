// lib/features/schedule/schedules_subcollection_feature_flag.dart
//
// Foundation flag gating the storage backend for the user's schedules.
//
// When OFF (default), schedules are persisted as the `schedules` array field
// on the /users/{uid} document — byte-identical to every prior release
// (LegacyArrayScheduleRepository). When ON, schedules are persisted as
// documents under /users/{uid}/schedules/{id} (SubcollectionScheduleRepository).
//
// Mirrors sync_fanout_feature_flag.dart exactly: the flag lives at
// config/schedules_subcollection and DEFAULTS FALSE. Every degraded state
// (missing doc, missing/non-boolean field, Firestore error, provider loading)
// collapses to `false` so a flaky read can never silently switch backends.
//
// This is a foundation-only introduction — nothing flips the flag and no
// migration/backfill is wired. Do NOT enable before a backfill + Firestore
// subcollection rules ship.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kSchedulesSubcollectionFlagCollection = 'config';
const String kSchedulesSubcollectionFlagDocId = 'schedules_subcollection';

/// Stream the schedules-subcollection feature flag. Defaults to `false` for
/// any degraded state — missing doc, missing/non-boolean field, Firestore
/// error.
final schedulesSubcollectionEnabledProvider = StreamProvider<bool>((ref) async* {
  bool? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kSchedulesSubcollectionFlagCollection)
        .doc(kSchedulesSubcollectionFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final value = _extractEnabled(snap);
      if (value != lastEmitted) {
        debugPrint('SchedulesSubcollection: enabled = $value');
        lastEmitted = value;
      }
      yield value;
    }
  } catch (e) {
    debugPrint(
        'SchedulesSubcollection: feature-flag stream error — $e (defaulting to false)');
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

/// Synchronous read for call sites that can't await the stream (e.g. the
/// repository selector). Defaults to `false` during the StreamProvider's
/// loading window or any error — the safe default (legacy array backend).
final schedulesSubcollectionEnabledSyncProvider = Provider<bool>((ref) {
  return ref.watch(schedulesSubcollectionEnabledProvider).maybeWhen(
        data: (v) => v,
        orElse: () => false,
      );
});

/// One-time bootstrap so the Firestore console has a doc to edit. Creates the
/// flag with `enabled:false` if absent. Best-effort; failures are logged, never
/// rethrown.
///
/// NOTE: This foundation change deliberately does NOT call this anywhere — the
/// task enables no new writes. Wire it into startup only when the subcollection
/// backend is ready to be seeded.
Future<void> bootstrapSchedulesSubcollectionFlagDoc() async {
  try {
    final doc = FirebaseFirestore.instance
        .collection(kSchedulesSubcollectionFlagCollection)
        .doc(kSchedulesSubcollectionFlagDocId);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set(<String, dynamic>{
      'enabled': false,
      'lastModified': FieldValue.serverTimestamp(),
      'modifiedBy': 'system_bootstrap',
      'notes': 'Auto-created. Set enabled=true to persist schedules under '
          '/users/{uid}/schedules/{id} instead of the user-doc array. Do NOT '
          'enable before a backfill + subcollection Firestore rules ship.',
    });
    debugPrint(
        'SchedulesSubcollection: bootstrapped config/schedules_subcollection (enabled=false)');
  } catch (e) {
    debugPrint(
        'SchedulesSubcollection: bootstrap failed — $e (safe; defaults false)');
  }
}
