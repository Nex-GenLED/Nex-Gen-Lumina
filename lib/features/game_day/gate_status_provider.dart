// Streams the planner's readiness verdict for the signed-in account.
//
// ONE FIELD ON A DOC THE APP ALREADY OWNS. `users/{uid}.gameday_gate_blocking`
// is written by the planner (and only on change), and `users/{userId}` is
// already owner-readable — so this costs one listener and no rules change.
//
// The client REFLECTS. Nothing here re-derives the checks: see gate_status.dart
// for why a second implementation of the rules would be worse than none.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gate_status.dart';

/// Field name written by `planGameDayFires`. A wire contract with the server.
const String kGateBlockingField = 'gameday_gate_blocking';

/// The account's current gate verdict, live.
///
/// Errors and the signed-out state both resolve to [GateStatus.unknown] —
/// armed. A transient read failure must never manufacture a warning that the
/// server did not issue; the worst outcome of this provider being wrong should
/// be showing nothing, never showing a block that does not exist.
final gateStatusProvider = StreamProvider<GateStatus>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) {
    return Stream<GateStatus>.value(GateStatus.unknown);
  }
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) => GateStatus.fromUserDoc(snap.data()?[kGateBlockingField]))
      .handleError((_) => GateStatus.unknown);
});
