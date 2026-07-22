import 'package:nexgen_command/features/site/connection_method.dart';

/// Per-controller verdict from the post-install verification sweep.
enum VerificationStatus { pending, pass, warn, fail }

/// Status + (for warn/fail) a human-readable reason. The reason renders
/// inline on the controller row and in the blocking dialog body.
class VerificationResult {
  const VerificationResult.pending()
      : status = VerificationStatus.pending,
        reason = null;

  const VerificationResult.pass()
      : status = VerificationStatus.pass,
        reason = null;

  const VerificationResult.warn(this.reason)
      : status = VerificationStatus.warn;

  const VerificationResult.fail(this.reason)
      : status = VerificationStatus.fail;

  final VerificationStatus status;
  final String? reason;

  bool get isAcceptable =>
      status == VerificationStatus.pass || status == VerificationStatus.warn;
}

/// Pure decision: given what the wizard recorded ([persisted], [isSkipped])
/// and what `/json/info` reports now ([observed], null = unreachable),
/// return the verification verdict.
///
/// Pass criteria mirror the prompt spec:
///   ethernet      + observed ethernet            → pass
///   wifi          + observed wifi                → pass
///   etherWifi     + skipped                      → pass
///   etherWifi     + !skipped                     → fail (resolution unfinished)
///   unknown / null persisted                     → warn (unverified)
///   observed == null                             → fail (offline)
///   persisted disagrees with observed            → fail (state drifted)
VerificationResult verifyController({
  required ConnectionMethod? persisted,
  required bool isSkipped,
  required ConnectionMethod? observed,
}) {
  if (observed == null) {
    return const VerificationResult.fail(
        'Controller offline at verification');
  }
  if (persisted == ConnectionMethod.ethernetWifiActive) {
    if (isSkipped) return const VerificationResult.pass();
    return const VerificationResult.fail(
      'Resolution went unfinished — controller is still dual-homed',
    );
  }
  if (persisted == null || persisted == ConnectionMethod.unknown) {
    return const VerificationResult.warn(
      'Connection method unverified — may need manual review',
    );
  }
  if (persisted == observed) return const VerificationResult.pass();
  return VerificationResult.fail(
    'Expected ${_humanize(persisted)} but observed ${_humanize(observed)}. '
    'Re-resolve on the connection method step.',
  );
}

/// True when every controller's verification has finished AND no result
/// is in the fail bucket. Pending or empty → false (the Continue button
/// stays disabled until every probe completes).
bool isAllVerifiedAcceptable(Iterable<VerificationResult> results) {
  final list = results.toList(growable: false);
  if (list.isEmpty) return false;
  for (final r in list) {
    if (r.status == VerificationStatus.pending) return false;
    if (r.status == VerificationStatus.fail) return false;
  }
  return true;
}

String _humanize(ConnectionMethod method) {
  switch (method) {
    case ConnectionMethod.ethernet:
      return 'Ethernet only';
    case ConnectionMethod.wifi:
      return 'WiFi only';
    case ConnectionMethod.ethernetWifiActive:
      return 'both interfaces active';
    case ConnectionMethod.unknown:
      return 'unknown state';
  }
}
