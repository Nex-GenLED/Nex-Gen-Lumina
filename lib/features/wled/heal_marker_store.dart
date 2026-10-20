// Per-controller markers for the defaults healer's one-shot and backed-off
// heals (2026-10-20):
//
// - the target-frame-rate heal runs ONCE per controller (a controller found
//   in the unlimited mode gets one `{"hw":{"led":{"fps":60}}}` write when no
//   other heal is writing in that run; afterwards every cfg write carries the
//   rate anyway, so a second dedicated flash write would buy nothing);
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
  Future<DateTime?> audioReactiveLastAttempt(String controllerId) async =>
      arAttempts[controllerId];

  @override
  Future<void> markAudioReactiveAttempt(
      String controllerId, DateTime at) async {
    arAttempts[controllerId] = at;
  }
}
