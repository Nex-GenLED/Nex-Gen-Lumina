import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time backfill that translates the legacy `connectionType` field on
/// `/users/{uid}/controllers/{cid}` docs into the new `connectionMethod`
/// field. Old field is left in place — a later cleanup release will drop it
/// after telemetry confirms 100% of clients have migrated.
///
/// Translation rules:
///   `ethernet_wifi` (legacy dual-homed inference) → `ethernet_wifi_active`
///   `wifi`                                         → `wifi`
///   anything else / missing                        → `unknown`
///
/// Docs already carrying a `connectionMethod` value are skipped — the
/// installer wizard now writes both fields on add, so re-running the
/// migration over a fresh doc must not clobber its accurate value.
class ConnectionMethodMigration {
  ConnectionMethodMigration._();

  /// SharedPreferences key for the one-shot guard.
  static const prefsKey = 'connection_method_migrated_v1';

  /// Pure decision function: given the current Firestore data for one
  /// controller doc, return the patch to merge in, or `null` if no write
  /// is needed.
  ///
  /// Public for unit testing — the production runner calls this for each
  /// doc and forwards the result to Firestore.
  @visibleForTesting
  static Map<String, dynamic>? migrationPatchFor(Map<String, dynamic> data) {
    final existing = data['connectionMethod'];
    if (existing is String && connectionMethodFromJson(existing) != null) {
      // Already migrated (or written fresh by the new installer flow).
      return null;
    }
    final legacy = data['connectionType'];
    final ConnectionMethod resolved;
    if (legacy == 'ethernet_wifi') {
      resolved = ConnectionMethod.ethernetWifiActive;
    } else if (legacy == 'wifi') {
      resolved = ConnectionMethod.wifi;
    } else {
      // Missing or unrecognised — record `unknown` so subsequent reads
      // produce a value rather than null, and so we never re-process this
      // doc on a later run.
      resolved = ConnectionMethod.unknown;
    }
    return {'connectionMethod': connectionMethodToJson(resolved)};
  }

  /// Runs the migration for [uid] exactly once across all client sessions.
  /// Subsequent invocations are no-ops thanks to the SharedPreferences flag.
  ///
  /// Failures are logged and swallowed — the migration is best-effort; a
  /// missed run just means the legacy field stays in force until the next
  /// app launch.
  static Future<void> runOnce(String uid) async {
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefsKey) == true) return;

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('controllers');
      final snap = await col.get();
      final batch = FirebaseFirestore.instance.batch();
      var writes = 0;
      for (final doc in snap.docs) {
        final patch = migrationPatchFor(doc.data());
        if (patch == null) continue;
        batch.set(doc.reference, patch, SetOptions(merge: true));
        writes++;
      }
      if (writes > 0) {
        await batch.commit();
        debugPrint('ConnectionMethodMigration: migrated $writes controller(s)');
      }
      await prefs.setBool(prefsKey, true);
    } catch (e) {
      debugPrint('ConnectionMethodMigration: failed (non-blocking): $e');
    }
  }

  /// Auth-listener entry point. Filters out null/empty uids and anonymous
  /// sessions, then fires [runner] with the resolved uid. Failures inside
  /// [runner] are caught here so the app's auth-state listener never sees
  /// an exception from the migration.
  ///
  /// Takes the two fields off Firebase Auth's `User` rather than the full
  /// object so callers (and tests) don't have to construct one.
  /// Production wiring: `tryRunForUid(uid: user?.uid, isAnonymous: user?.isAnonymous ?? true, runner: runOnce)`.
  static Future<void> tryRunForUid({
    required String? uid,
    required bool isAnonymous,
    required Future<void> Function(String uid) runner,
  }) async {
    if (uid == null || uid.isEmpty) return;
    if (isAnonymous) {
      debugPrint('ConnectionMethodMigration: skipping anonymous session');
      return;
    }
    try {
      await runner(uid);
    } catch (e) {
      debugPrint(
          'ConnectionMethodMigration: runner threw (non-blocking): $e');
    }
  }
}
