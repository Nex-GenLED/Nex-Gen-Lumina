// Streams `users/{uid}.gameday_server` for the signed-in account.
//
// Cloned from gate_status_provider.dart: one listener on a doc the app already
// owns (owner-readable, no rules change), and every degraded state — signed
// out, no Firebase, a stream error — resolves to NOT SERVED, which is the safe
// direction (the phone runs Game Day as build 112 did). See
// game_day_server_status.dart for why the parser only errs that way.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_day_server_status.dart';

/// The account's server status, live from the user document.
final gameDayServerStatusProvider =
    StreamProvider<GameDayServerStatus>((ref) {
  String? uid;
  try {
    uid = FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    uid = null; // no Firebase app (tests, a broken native config) → not served
  }
  if (uid == null || uid.isEmpty) {
    return Stream<GameDayServerStatus>.value(GameDayServerStatus.notServed);
  }
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) =>
          GameDayServerStatus.fromUserDoc(snap.data()?[kGameDayServerField]))
      .handleError((_) => GameDayServerStatus.notServed);
});

/// Synchronous read for the lease manager and the engine. Loading and error
/// both read as NOT SERVED — a decision taken before the first snapshot falls
/// back to the phone path, never to silence.
final gameDayServerStatusSyncProvider = Provider<GameDayServerStatus>((ref) {
  return ref.watch(gameDayServerStatusProvider).valueOrNull ??
      GameDayServerStatus.notServed;
});

/// The clock the Game Day surfaces read "now" from, at build or call time.
///
/// A plain function, deliberately NOT a periodic stream: a timer-backed
/// provider outlives widget-test trees, and the surfaces already rebuild on
/// every status snapshot (every planner tick while served) and on every visit
/// to the screen. Decisions (lease, engine) read the time at decision time
/// anyway. Overridden in tests to pin the date.
final gameDayNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
