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

/// Whether [raw] canonicalises to something that could BE a MAC — twelve hex
/// digits — as opposed to a legacy doc id that was keyed by something else.
///
/// #94. Controller docs created before the claim-fix were keyed by IP
/// (`192_168_1_150` → `1921681150`) or by a Firestore auto-id
/// (`g6YTg5yhRXOaUvfdM6qL` → `g6ytg5yhrxoauvfdm6ql`). Neither can ever equal a
/// reported MAC, so #93's guard refused **every** write on those accounts —
/// four live customers, told to check their connection while the controller sat
/// there healthy. Such an id is not a wrong expectation; it is the ABSENCE of
/// one, and the correct response is to learn the identity, not to refuse.
bool isMacShapedId(String raw) =>
    RegExp(r'^[0-9a-f]{12}$').hasMatch(canonicalDeviceId(raw));

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

/// What the guard concluded. Returned rather than thrown when the write may
/// proceed, so the caller can act on an ADOPTION without a second code path.
class DeviceIdentityResult {
  /// True when [expectedControllerId] was not MAC-shaped and the device was
  /// reachable — the app had no identity to check against and has now learned
  /// one. The caller should persist [adoptedMac] onto the controller document.
  final bool adopted;

  /// Canonical MAC the device reported, when it reported one. Null on a plain
  /// verification (nothing to learn) or when an adopted device did not name
  /// itself (nothing to write).
  final String? adoptedMac;

  const DeviceIdentityResult.verified()
      : adopted = false,
        adoptedMac = null;

  const DeviceIdentityResult.adopted(this.adoptedMac) : adopted = true;
}

/// The whole guard DECISION, with no HTTP in it — so match / mismatch /
/// adoption / unverifiable are all testable without a device or a socket.
///
/// [info] is the decoded `/json/info` body, or null when the read failed.
/// Returns on a match or an adoption; throws otherwise.
///
/// FOUR outcomes, not two:
///   • info == null                  → throw [WledDeviceUnverifiableException].
///     "I could not ask" is never "it is the right device".
///   • expected id not MAC-shaped    → **adopt** (#94). A legacy IP-keyed or
///     auto-id doc carries no identity claim, so there is nothing for the
///     device to contradict. Pre-#93 these accounts wrote freely; refusing them
///     was a regression, not a protection.
///   • MAC-shaped and equal          → verified.
///   • MAC-shaped and different      → throw [WledDeviceMismatchException].
///     UNCHANGED: a real expectation was violated and writing would change
///     someone else's lights.
DeviceIdentityResult assertDeviceIdentity({
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

  // #94 — legacy doc id: no expectation to violate. Adopt what the device says.
  if (!isMacShapedId(expectedControllerId)) {
    final canonical = mac == null ? '' : canonicalDeviceId(mac);
    return DeviceIdentityResult.adopted(canonical.isEmpty ? null : canonical);
  }

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
  return const DeviceIdentityResult.verified();
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
//
// #94 — TAKE-ONCE WAS NOT ENOUGH. Three failure reporters never consumed the
// park, so a refusal they dropped stayed parked indefinitely and the NEXT
// reporter — a timeout, an unrelated non-2xx, minutes or hours later — popped
// it and told the user "a different device answered". A stale park does not
// just fail to inform; it actively misattributes. So the park is now bound to
// the write attempt that produced it by a timestamp, and expires.

/// How long a parked refusal stays claimable. Long enough for the failure
/// reporter on the same write attempt to run (it is the very next await),
/// short enough that no later, unrelated failure can inherit it.
const Duration kIdentityRefusalTtl = Duration(seconds: 10);

/// Clock seam so TTL expiry is testable without waiting. Tests assign this and
/// restore it; production never touches it.
///
/// Deliberately NOT annotated `@visibleForTesting`: this file's whole point is
/// that it imports no flutter and no meta (see the header), so the annotation
/// would cost the property the header promises. The name carries the contract.
DateTime Function() identityRefusalClock = DateTime.now;

String? _lastRefusalMessage;
DateTime? _lastRefusalAt;

/// Park a refusal for the failure report of THIS write attempt. Called by the
/// write doors.
void recordIdentityRefusal(WledDeviceIdentityException e) {
  _lastRefusalMessage = e.userMessage;
  _lastRefusalAt = identityRefusalClock();
}

/// Consume the parked refusal, if any and if still fresh.
///
/// Returns null when the last failure was an ordinary one (timeout, non-2xx)
/// rather than an identity refusal, AND when a refusal was parked but has aged
/// past [kIdentityRefusalTtl] — an expired park belongs to a write attempt that
/// is over, and attributing it to this one would be a lie.
String? takeIdentityRefusalMessage() {
  final m = _lastRefusalMessage;
  final at = _lastRefusalAt;
  _lastRefusalMessage = null;
  _lastRefusalAt = null;
  if (m == null || at == null) return null;
  if (identityRefusalClock().difference(at) > kIdentityRefusalTtl) return null;
  return m;
}

/// Drop any parked refusal without reporting it (test hygiene / a successful
/// write clearing stale state).
void clearIdentityRefusal() {
  _lastRefusalMessage = null;
  _lastRefusalAt = null;
}
