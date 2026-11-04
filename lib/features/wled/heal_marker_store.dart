// Per-controller markers for the defaults healer's one-shot and backed-off
// heals (2026-10-20):
//
// - the target-frame-rate heal runs ONCE per EPISODE of the unlimited mode (a
//   controller found in that mode gets one `{"hw":{"led":{"fps":42}}}` write
//   when no other heal is writing in that run). The marker means "written, not
//   yet seen usable": a usable rate — on a later connect or on the same run's
//   read-back — spends it (+122 item 3), so a LATER cfg write that carried no
//   rate and put the device back into the unlimited mode is healed again. A
//   device that never takes the write keeps its marker and is never written
//   twice;
// - the AudioReactive disable is a flash write that, on some units, never
//   takes (the readback still says enabled). After one such failure the heal
//   backs off for [kAudioReactiveHealBackoff] instead of re-writing flash on
//   every connect.
//
// Pure Dart; the SharedPreferences implementation is the production store,
// the in-memory one is for tests. Keys carry the controller id, never an
// address.

import 'package:shared_preferences/shared_preferences.dart';

/// How long the AudioReactive heal waits after a readback that still says
/// enabled before it tries again on that controller.
const Duration kAudioReactiveHealBackoff = Duration(days: 7);

abstract class HealMarkerStore {
  Future<bool> targetFpsHealDone(String controllerId);
  Future<void> markTargetFpsHealDone(String controllerId);

  /// +122 item 3: the rate has been seen usable — the marker is spent.
  Future<void> clearTargetFpsHealDone(String controllerId);
  Future<DateTime?> audioReactiveLastAttempt(String controllerId);
  Future<void> markAudioReactiveAttempt(String controllerId, DateTime at);
}

class SharedPrefsHealMarkerStore implements HealMarkerStore {
  const SharedPrefsHealMarkerStore();

  static String fpsKey(String id) => 'heal.target_fps.done.$id';
  static String arKey(String id) => 'heal.audioreactive.attempt_ms.$id';

  @override
  Future<bool> targetFpsHealDone(String controllerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(fpsKey(controllerId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markTargetFpsHealDone(String controllerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(fpsKey(controllerId), true);
    } catch (_) {
      // A lost marker costs at most one repeated single write later.
    }
  }

  @override
  Future<void> clearTargetFpsHealDone(String controllerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(fpsKey(controllerId));
    } catch (_) {
      // A marker that will not clear costs at most one missed re-heal until
      // the next usable read clears it.
    }
  }

  @override
  Future<DateTime?> audioReactiveLastAttempt(String controllerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(arKey(controllerId));
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> markAudioReactiveAttempt(
      String controllerId, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(arKey(controllerId), at.millisecondsSinceEpoch);
    } catch (_) {
      // A lost marker means one more attempt on the next connect.
    }
  }
}

/// Test double: markers live for the life of the object.
class InMemoryHealMarkerStore implements HealMarkerStore {
  final Set<String> fpsDone = {};
  final Map<String, DateTime> arAttempts = {};

  @override
  Future<bool> targetFpsHealDone(String controllerId) async =>
      fpsDone.contains(controllerId);

  @override
  Future<void> markTargetFpsHealDone(String controllerId) async {
    fpsDone.add(controllerId);
  }

  @override
  Future<void> clearTargetFpsHealDone(String controllerId) async {
    fpsDone.remove(controllerId);
  }

  @override
  Future<DateTime?> audioReactiveLastAttempt(String controllerId) async =>
      arAttempts[controllerId];

  @override
  Future<void> markAudioReactiveAttempt(
      String controllerId, DateTime at) async {
    arAttempts[controllerId] = at;
  }
}
