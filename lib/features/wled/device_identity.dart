// Pure-Dart device-identity check (#92 fix C). No flutter/dart:ui, no HTTP —
// so the canonicalization and the match rule are testable without a device.
//
// WHY THIS EXISTS. A controller is addressed by IP, but IP is not identity.
// DHCP reassigns, customers swap hardware, and `192.168.1.250` is a default
// router address that FOUR unrelated accounts in this fleet happen to use. The
// app's own model of "which controller is this" is a Firestore doc id derived
// from the MAC (`80_f3_da_b3_b8_20`), while the thing that actually answers at
// an address reports its own MAC in `GET /json/info` (`80f3dab3b820`). Until
// #92 nothing compared the two before writing, so a stale or reused IP meant
// the app would happily write someone else's lights — silently, and reporting
// success.
//
// This module holds only the comparison. The enforcement lives at the
// `WledService` write chokepoints; the relay path is deliberately untouched,
// because the bridge resolves its own target on the customer's own LAN and a
// command doc is already uid-scoped.

/// Reduce a MAC or controller id to a comparable form: lowercase, with every
/// non-alphanumeric character removed.
///
/// Handles the two shapes this app actually stores, and the several a device
/// might report:
///   `80_f3_da_b3_b8_20` → `80f3dab3b820`   (Firestore controller doc id)
///   `80:F3:DA:B3:B8:20` → `80f3dab3b820`   (colon-separated MAC)
///   `80-f3-da-b3-b8-20` → `80f3dab3b820`   (hyphen-separated)
///   `80f3dab3b820`      → `80f3dab3b820`   (WLED `/json/info` `mac`)
String canonicalDeviceId(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Whether the device that answered ([reportedMac], from `/json/info.mac`) is
/// the one the app meant to talk to ([expectedControllerId], the Firestore
/// controller doc id).
///
/// Returns false for a null/blank reported MAC: a device that will not say who
/// it is has not been verified. **Never treat "unknown" as "match"** — that is
/// the whole failure this guard exists to prevent, and it is why the caller
/// distinguishes a mismatch from an unverifiable read rather than folding both
/// into a bool at the call site.
bool deviceIdentityMatches({
  required String? reportedMac,
  required String expectedControllerId,
}) {
  if (reportedMac == null) return false;
  final got = canonicalDeviceId(reportedMac);
  final want = canonicalDeviceId(expectedControllerId);
  if (got.isEmpty || want.isEmpty) return false;
  return got == want;
}

/// Base class for a refused write. Carries the sentence the user should see —
/// defined once, here, so the three surfaces cannot drift into three different
/// explanations (the `kLanOnlyMessage` convention).
sealed class WledDeviceIdentityException implements Exception {
  /// Text safe to show a customer. No MACs, no IPs — it must be actionable,
  /// not forensic.
  String get userMessage;

  /// Detail for logs only.
  String get detail;

  @override
  String toString() => '$runtimeType: $detail';
}

/// A device answered, and it is NOT the expected controller.
///
/// This is a hard refusal, not a retry: the address is currently occupied by
/// different hardware, and writing would change someone else's lights.
class WledDeviceMismatchException extends WledDeviceIdentityException {
  final String baseUrl;
  final String expectedControllerId;
  final String reportedMac;

  WledDeviceMismatchException({
    required this.baseUrl,
    required this.expectedControllerId,
    required this.reportedMac,
  });

  @override
  String get userMessage =>
      'A different device answered at this address — check your network';

  @override
  String get detail => 'expected=${canonicalDeviceId(expectedControllerId)} '
      'got=${canonicalDeviceId(reportedMac)} at $baseUrl';
}

/// `/json/info` could not be read, so identity could not be established.
///
/// Deliberately a REFUSAL and not a pass. An unreachable info endpoint on the
/// path to a write means one of: the controller is off, the address is dead,
/// or something is there that does not speak WLED. None of those is a state in
/// which writing blind is correct.
class WledDeviceUnverifiableException extends WledDeviceIdentityException {
  final String baseUrl;
  final String expectedControllerId;

  WledDeviceUnverifiableException({
    required this.baseUrl,
    required this.expectedControllerId,
  });

  @override
  String get userMessage => "Can't reach your controller on this network";

  @override
  String get detail =>
      'GET /json/info unreadable at $baseUrl (expected $expectedControllerId)';
}

/// The whole guard DECISION, with no HTTP in it — so match / mismatch /
/// unverifiable are all testable without a device or a socket.
///
/// [info] is the decoded `/json/info` body, or null when the read failed.
/// Returns normally on a match; throws otherwise. The caller does exactly two
/// things around this: fetch the info, and cache on success.
///
/// A null [info] throws [WledDeviceUnverifiableException] rather than passing.
/// That asymmetry is the point of the function: there are three outcomes, not
/// two, and collapsing "could not ask" into "fine, proceed" is the failure
/// this guard exists to prevent.
void assertDeviceIdentity({
  required String baseUrl,
  required String expectedControllerId,
  required Map<String, dynamic>? info,
}) {
  if (info == null) {
    throw WledDeviceUnverifiableException(
      baseUrl: baseUrl,
      expectedControllerId: expectedControllerId,
    );
  }
  final reported = info['mac'];
  final mac = reported is String ? reported : null;
  if (!deviceIdentityMatches(
    reportedMac: mac,
    expectedControllerId: expectedControllerId,
  )) {
    throw WledDeviceMismatchException(
      baseUrl: baseUrl,
      expectedControllerId: expectedControllerId,
      reportedMac: mac ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Refusal hand-off (#92b)
// ---------------------------------------------------------------------------
//
// WHY THE EXCEPTION STOPS AT THE SERVICE. #92 let the guard throw out of the
// write doors. A caller sweep found 26 provider-sourced call sites with no
// swallowing try/catch — `_postUpdate`, the Design Studio apply, the geofence
// setState pair, the schedule-sync preset writes, hardware config — every one
// of which would have surfaced the refusal as an UNHANDLED ASYNC ERROR. On
// iOS that is a crash, which would have made a safety guard the second-largest
// crash source in the app.
//
// So the doors now convert: they catch the typed exception, park its message
// here, and return the EXISTING failure value (`false` / `PerPixelChunkResult
// .failed`). Every caller keeps the contract it already handled, and nothing
// needs wrapping. The typed exceptions still exist and are still thrown by
// `assertDeviceIdentity` — they are the tested decision — they simply no
// longer escape the repository boundary.
//
// TAKE-ONCE on purpose: a refusal consumed by one failure report must not be
// re-reported against an unrelated failure minutes later.

String? _lastRefusalMessage;

/// Park a refusal for the next failure report. Called by the write doors.
void recordIdentityRefusal(WledDeviceIdentityException e) {
  _lastRefusalMessage = e.userMessage;
}

/// Consume the parked refusal, if any. Returns null when the last failure was
/// an ordinary one (timeout, non-2xx) rather than an identity refusal.
String? takeIdentityRefusalMessage() {
  final m = _lastRefusalMessage;
  _lastRefusalMessage = null;
  return m;
}

/// Drop any parked refusal without reporting it (test hygiene / a successful
/// write clearing stale state).
void clearIdentityRefusal() => _lastRefusalMessage = null;
