/// Fleet telemetry for the installer wizard's staff-auth path.
///
/// WHY THIS EXISTS — S-5 / D4 GATE
/// ────────────────────────────────
/// `firestore.rules` carries a broad `|| request.auth != null` grant on
/// `/users/{userId}/controllers` (:383-396). That grant exists for exactly one
/// reason: when the installer wizard's staff-token restore failed, it fell back
/// to `signInAnonymously()` and every remaining write ran with no claims.
///
/// D4 narrows that grant. Rules deploys are ATOMIC AND GLOBAL — they cannot
/// distinguish app versions. Tightening `/controllers` while any installer is
/// still running an older build denies controller migration mid-install, in a
/// customer's driveway, with no client error path. So the deploy is gated on an
/// OBSERVATION, not an assumption: this recorder must read ZERO across the
/// fleet before the rules move.
///
/// DESTINATION: `/demo_analytics` — justified in audit/TOKEN_REFRESH_REPORT.md.
/// The short version: it is the only existing top-level collection whose rule
/// (`allow create: if true`, firestore.rules:1354-1358) accepts a write from an
/// ANONYMOUS caller — which is precisely the caller we need to hear from — and
/// this change is forbidden from touching firestore.rules. A brand-new
/// collection would be denied by the default-deny catch-all, the write would
/// fail, and the counter would read zero for the WRONG REASON: a false all-clear
/// that unblocks a global rules deploy. That failure mode is worse than the
/// semantic overload of reusing this collection, so the overload is deliberate.
/// Rows are namespaced by [kAnonFallbackEventType] so they never collide with
/// genuine demo-funnel rows.
///
/// LOAD-BEARING: NO. Every entry point here swallows all errors and is bounded
/// by [_writeTimeout]. Telemetry must never fail, block, or slow an install —
/// see [recordAnonymousFallback].
library;

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Collection that receives fallback records. See the library doc for why this
/// collection and not a purpose-built one.
const String kStaffAuthTelemetryCollection = 'demo_analytics';

/// Discriminator written into every row this file produces. This is the field
/// Tyler filters on in the console; it keeps installer rows separate from the
/// demo-funnel rows that otherwise populate this collection.
const String kAnonFallbackEventType = 'installer_anon_fallback';

/// App version stamped onto every telemetry row.
///
/// MUST BE BUMPED WITH `pubspec.yaml` ON EVERY RELEASE. There is no runtime
/// source for this — the project does not depend on `package_info_plus`, and
/// adding a plugin (with its native config) to a release candidate is a bigger
/// risk than a one-line constant. The whole point of the S-5 gate is telling
/// ADOPTED builds from STALE ones, so a stale value here defeats the metric.
/// Logged as debt in docs/BUGS_AND_DEBT.md.
const String kStaffAuthTelemetryAppVersion = '2.5.10+71';

/// Discriminator for commissioning-step failures that leave an install
/// incomplete — see [recordCommissioningFailure]. Separate from
/// [kAnonFallbackEventType] so the S-5 adoption count is not polluted, but the
/// same collection and the same never-load-bearing contract.
const String kCommissioningFailureEventType = 'installer_commissioning_failure';

/// SharedPreferences key holding this install's stable device identifier.
const String _deviceIdKey = 'lumina_staff_auth_device_id';

/// Telemetry writes are capped so a dead network can never stall an install.
const Duration _writeTimeout = Duration(seconds: 5);

/// Where in the wizard the anonymous fallback was reached. Recorded so a
/// non-zero counter points at a code path, not just a device.
enum AnonFallbackStage {
  /// Pre-flight refresh at the top of `_completeSetup`, BEFORE any Firebase
  /// write. A fallback here is safe — nothing has committed.
  preflightRefresh,

  /// Restore after `createUserWithEmailAndPassword` clobbered the session.
  /// This is the historical `_restoreInstallerAuth` :756 call site and the one
  /// that forced the broad rules grant to exist.
  restoreAfterAccountCreation,
}

extension AnonFallbackStageWire on AnonFallbackStage {
  String get wire => switch (this) {
        AnonFallbackStage.preflightRefresh => 'preflight_refresh',
        AnonFallbackStage.restoreAfterAccountCreation =>
          'restore_after_account_creation',
      };
}

/// Returns a stable per-install device identifier, creating one on first call.
///
/// Deliberately NOT a hardware identifier: the project has no `device_info_plus`
/// dependency, and a random-but-persisted id answers the only question being
/// asked ("how many distinct devices still hit this?") without collecting
/// anything new from the handset — which also keeps it clear of the privacy
/// nutrition-label mismatch already tracked as F-6.
Future<String> staffAuthDeviceId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final rand = Random.secure();
    final id = List.generate(
      16,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();
    await prefs.setString(_deviceIdKey, id);
    return id;
  } catch (e) {
    // Storage unavailable — still emit the row, just without a stable id.
    debugPrint('StaffAuthTelemetry: device-id lookup failed: $e');
    return 'unknown';
  }
}

/// Record that the installer wizard reached the anonymous fallback.
///
/// CANNOT FAIL THE INSTALL. Every failure mode — offline, rules denial, plugin
/// error, timeout — is caught and swallowed here. Callers do not need their own
/// try/catch and must not await this in a way that gates install work.
///
/// [reason] should carry the underlying error/cause so a non-zero counter is
/// actionable (expired token vs revoked claim vs no signal).
Future<void> recordAnonymousFallback({
  required AnonFallbackStage stage,
  required String reason,
  String? dealerCode,
  String? installerCode,
  String? authUid,
  FirebaseFirestore? firestore,
}) async {
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    final deviceId = await staffAuthDeviceId();

    await db.collection(kStaffAuthTelemetryCollection).doc().set({
      'event_type': kAnonFallbackEventType,
      'device_id': deviceId,
      'app_version': kStaffAuthTelemetryAppVersion,
      'stage': stage.wire,
      // Truncated: reason is an error string of unbounded length.
      'reason': reason.length > 300 ? reason.substring(0, 300) : reason,
      'dealer_code': dealerCode ?? '',
      'installer_code': installerCode ?? '',
      'auth_uid': authUid ?? '',
      // Server clock — a handset with a wrong clock must not be able to hide a
      // fallback outside the "last N days" query window.
      'created_at': FieldValue.serverTimestamp(),
      // Client clock kept alongside purely for skew diagnosis.
      'client_time': DateTime.now().toUtc().toIso8601String(),
    }).timeout(_writeTimeout);

    debugPrint('StaffAuthTelemetry: recorded anon fallback '
        '(stage=${stage.wire}, reason=$reason)');
  } catch (e) {
    // Intentionally terminal. See the "LOAD-BEARING: NO" note above.
    debugPrint('StaffAuthTelemetry: record FAILED (non-blocking): $e');
  }
}

/// Record that a commissioning step failed in a way that leaves the install
/// incomplete — e.g. the controller migration (P0-6), which runs after the
/// customer's account exists and, when it fails, leaves them with no lights.
///
/// WHY THIS EXISTS: the installer is told and offered a retry, but if they stop
/// (or the app dies) the only trace was a `debugPrint` on a phone nobody will
/// read. This makes "a customer was left without controllers" answerable from
/// the console instead of depending on who was standing in the driveway.
///
/// CANNOT FAIL THE INSTALL. Same contract as [recordAnonymousFallback]: every
/// error is swallowed, bounded by the same write timeout. Telemetry is never
/// load-bearing for an install.
Future<void> recordCommissioningFailure({
  required String stage,
  required String reason,
  String? customerUid,
  String? sourceUid,
  FirebaseFirestore? firestore,
}) async {
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    final deviceId = await staffAuthDeviceId();

    await db.collection(kStaffAuthTelemetryCollection).doc().set({
      'event_type': kCommissioningFailureEventType,
      'device_id': deviceId,
      'app_version': kStaffAuthTelemetryAppVersion,
      'stage': stage,
      'reason': reason.length > 300 ? reason.substring(0, 300) : reason,
      'customer_uid': customerUid ?? '',
      'source_uid': sourceUid ?? '',
      'created_at': FieldValue.serverTimestamp(),
      'client_time': DateTime.now().toUtc().toIso8601String(),
    }).timeout(_writeTimeout);

    debugPrint('StaffAuthTelemetry: recorded commissioning failure '
        '(stage=$stage)');
  } catch (e) {
    debugPrint('StaffAuthTelemetry: commissioning-failure record FAILED '
        '(non-blocking): $e');
  }
}
