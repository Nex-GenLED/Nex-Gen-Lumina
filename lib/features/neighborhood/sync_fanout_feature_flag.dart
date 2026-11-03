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
//
// HOW START READS IT (Sync Start window, 2026-11-02). The flag used to be
// read synchronously (`maybeWhen(orElse: false)`) by the only code that
// cared, broadcastSync, and nothing watched the stream before that read. The
// first Start of every app session therefore CREATED the stream, saw it
// loading, and read `false`: the fan-out never fired from a first tap, on
// any build since the client shipped. Start now awaits the stream's real
// value (`syncFanoutEnabledProvider.future`) under a short timeout. A stream
// ERROR is no longer folded into `false`: "off by policy" (doc absent, field
// absent or not a bool) still reads false, but "cannot be read" (permission,
// no app, timeout) surfaces to Start as a visible failure instead of a silent
// app-open-only sync.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firestore document path holding the flag.
const String kSyncFanoutFlagCollection = 'config';
const String kSyncFanoutFlagDocId = 'sync_fanout';

/// Stream the fanout feature flag. `false` for "off by policy" — missing doc,
/// missing/non-boolean field. A Firestore error is NOT folded into `false`:
/// it propagates as the provider's error state so a caller can tell "off"
/// from "unreadable" (see the file header).
final syncFanoutEnabledProvider = StreamProvider<bool>((ref) async* {
  bool? lastEmitted;
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
});

bool _extractEnabled(DocumentSnapshot<Map<String, dynamic>> snap) {
  if (!snap.exists) return false;
  final data = snap.data();
  if (data == null) return false;
  final raw = data['enabled'];
  if (raw is bool) return raw;
  return false;
}

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
