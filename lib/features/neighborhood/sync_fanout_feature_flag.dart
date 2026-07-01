// lib/features/neighborhood/sync_fanout_feature_flag.dart
//
// Slice 1 — Firestore-backed feature flag gating the server-side ad-hoc
// neighborhood-sync FANOUT.
//
// When OFF (default), applySyncPattern keeps its self-only behavior and the
// foreground "Start" tap only writes the existing neighborhoods/{groupId}/
// commands broadcast — byte-identical to pre-Slice-1. When ON, the initiator's
// tap ALSO calls applySyncPattern, which fans the command out to every
// consenting crew member's own command queue (admin SDK) so only the initiator
// needs the app open.
//
// Mirrors calendar_lease_feature_flag.dart. The flag lives at
// config/sync_fanout.enabled and DEFAULTS FALSE. It is flipped via the
// Firestore console only AFTER Slice 1 Commit 2 (rate limit) ships and a
// real-crew test passes — never in Commit 1.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kSyncFanoutFlagCollection = 'config';
const String kSyncFanoutFlagDocId = 'sync_fanout';

/// Stream the fanout feature flag. Defaults to `false` for any degraded
/// state — missing doc, missing/non-boolean field, Firestore error.
final syncFanoutEnabledProvider = StreamProvider<bool>((ref) async* {
  bool? lastEmitted;
  try {
    final docStream = FirebaseFirestore.instance
        .collection(kSyncFanoutFlagCollection)
        .doc(kSyncFanoutFlagDocId)
        .snapshots();
    await for (final snap in docStream) {
      final value = _extractEnabled(snap);
      if (value != lastEmitted) {
        debugPrint('SyncFanout: enabled = $value');
        lastEmitted = value;
      }
      yield value;
    }
  } catch (e) {
    debugPrint('SyncFanout: feature-flag stream error — $e (defaulting to false)');
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
/// broadcast trigger). Defaults to `false` during the StreamProvider's loading
/// window or any error — the safe default (no fanout).
final syncFanoutEnabledSyncProvider = Provider<bool>((ref) {
  return ref.watch(syncFanoutEnabledProvider).maybeWhen(
        data: (v) => v,
        orElse: () => false,
      );
});

/// One-time bootstrap so the Firestore console has a doc to edit. Creates the
/// flag with `enabled:false` if absent. Best-effort; failures are logged, never
/// rethrown. Safe to call on every launch (no-op once the doc exists).
Future<void> bootstrapSyncFanoutFlagDoc() async {
  try {
    final doc = FirebaseFirestore.instance
        .collection(kSyncFanoutFlagCollection)
        .doc(kSyncFanoutFlagDocId);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set(<String, dynamic>{
      'enabled': false,
      'lastModified': FieldValue.serverTimestamp(),
      'modifiedBy': 'system_bootstrap',
      'notes': 'Auto-created. Set enabled=true to activate server-side ad-hoc '
          'neighborhood-sync fanout (Slice 1). Do NOT enable before the rate '
          'limit (Commit 2) is deployed and a real-crew test passes.',
    });
    debugPrint('SyncFanout: bootstrapped config/sync_fanout (enabled=false)');
  } catch (e) {
    debugPrint('SyncFanout: bootstrap failed — $e (safe; defaults false)');
  }
}
