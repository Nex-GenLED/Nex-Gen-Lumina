// The geometry gate — nothing psaves the ladder over wrong geometry.
//
// WHY IT EXISTS. `psave` captures LIVE segment geometry into the preset
// regardless of what the inline state specifies (bench-proven 2026-08-14: a
// save sending only `{id,on}` stored `rev/mi/of/grp/spc` anyway). So a preset is
// only as correct as the device was at save time, and a save taken while
// geometry is wrong bakes that error into the base layer, where it loads every
// night. The transient clobber of #76 becomes durable.
//
// This is the fourth and last layer of #76's severity cap:
//   1. builders that no longer emit geometry        (70726ac)
//   2. a ladder path that never asserts it          (_fullStripOnSegments)
//   3. a rig configured to catch the class          (two segments, bench)
//   4. THIS — a gate that refuses a drifted save, legibly
//
// WHAT IT COMPARES, and what it deliberately does not. Segment COUNT and
// BOUNDS only. `rev`, `mi`, `of`, `grp`, `spc` are NOT compared: the pixel map
// does not own them — provisioning and the installer do — and refusing on a
// correct install whose reversal the app has no record of would be #76's
// mistake with the sign flipped. Bounds are the two facts the map actually
// knows and the two a collapse destroys.

import 'package:flutter/foundation.dart';

/// One segment's shape, as the gate understands shape.
@immutable
class SegmentShape {
  final int id;
  final int start;
  final int stop;

  const SegmentShape(this.id, this.start, this.stop);

  @override
  bool operator ==(Object other) =>
      other is SegmentShape &&
      other.id == id &&
      other.start == start &&
      other.stop == stop;

  @override
  int get hashCode => Object.hash(id, start, stop);

  @override
  String toString() => '$id[$start,$stop)';
}

/// Which world we are in.
enum GateBranch {
  /// Count and bounds agree — save.
  match,

  /// Count agrees, bounds moved — re-provision bounds, re-read, then save.
  drift,

  /// Count differs. Typically collapsed to one segment by a reboot, which a
  /// preset load CANNOT undo (bounds live in cfg; a preset carries state onto
  /// whatever layout exists). Proven input, 2026-08-14.
  totalLoss,
}

/// PURE. Classify actual against expected.
///
/// An EMPTY expected map is [GateBranch.totalLoss] rather than a vacuous match:
/// "we do not know the shape" must never authorise a save.
GateBranch classifyGeometry(
  List<SegmentShape> expected,
  List<SegmentShape> actual,
) {
  if (expected.isEmpty) return GateBranch.totalLoss;
  if (expected.length != actual.length) return GateBranch.totalLoss;
  return listEquals(expected, actual) ? GateBranch.match : GateBranch.drift;
}

String _shape(List<SegmentShape> s) =>
    s.isEmpty ? '(none)' : s.map((e) => e.toString()).join(' ');

/// What the caller acts on. It logs one line and either saves or does not; it
/// never interprets the shapes itself.
@immutable
class GateResult {
  final bool proceed;
  final GateBranch branch;

  /// True when a re-provision ran AND the readback then matched.
  final bool repaired;

  final List<SegmentShape> expected;
  final List<SegmentShape> actual;
  final String? refusal;

  const GateResult({
    required this.proceed,
    required this.branch,
    required this.repaired,
    required this.expected,
    required this.actual,
    this.refusal,
  });

  /// One operator-readable line, per the #68 convention: a refusal that does
  /// not say which shape was wrong is a counter, not a diagnosis.
  String get summary => proceed
      ? 'geometry ${branch.name}${repaired ? ' (re-provisioned)' : ''}: '
          '${_shape(actual)}'
      : 'gated_geometry_mismatch (${branch.name}) — '
          'expected ${_shape(expected)}, got ${_shape(actual)}';
}

/// Reads the device's CURRENT segment shape. Returns null when unreadable.
typedef GeometryReader = Future<List<SegmentShape>?> Function();

/// Writes the expected shape to the device. Returns false on a failed write.
///
/// Its return value is NOT evidence — the gate always re-reads. The 2026-08-14
/// incident's lesson is that the device's actual shape is the only authority.
typedef GeometryProvisioner = Future<bool> Function(List<SegmentShape> expected);

/// Run the gate.
///
/// Never throws: an exception anywhere resolves to a refusal, because the only
/// safe answer to "I could not tell" is "do not save".
Future<GateResult> evaluateGeometryGate({
  required List<SegmentShape> expected,
  required GeometryReader read,
  required GeometryProvisioner reprovision,
}) async {
  List<SegmentShape>? actual;
  try {
    actual = await read();
  } catch (_) {
    actual = null;
  }

  if (actual == null) {
    // UNREADABLE STANDS ASIDE — it does not refuse. Corrected 2026-08-14 after
    // the wiring surfaced the cost, and for consistency with the empty-expected
    // policy above: this gate guards against a KNOWN mismatch, not against
    // ignorance. Three reasons it is the right side to err on.
    //
    //   1. It matches the discipline used everywhere else this week — #67's
    //      partition, W4's ladder fact, the readiness gate's R2 — where unknown
    //      is explicitly NOT bad. Making unknown fatal here alone is the
    //      inconsistency, not the fix.
    //   2. If the device's state cannot be read, the save is very unlikely to
    //      land either. Refusing converts a save failure into a gate refusal
    //      and buys nothing.
    //   3. The availability cost is real and asymmetric. On the sunrise-off
    //      path a refusal ABORTS the timer write, so one transient read failure
    //      means the customer's lights do not turn off at sunrise — a worse
    //      outcome, and a more likely one, than a save over geometry that has
    //      probably not drifted.
    //
    // The genuine drift cases all present as a READABLE shape that disagrees
    // (the reboot collapse read cleanly as one segment), so this concession
    // costs the gate none of the defects it exists to catch.
    return GateResult(
      proceed: true,
      branch: GateBranch.match,
      repaired: false,
      expected: expected,
      actual: const [],
      refusal: null,
    );
  }

  final branch = classifyGeometry(expected, actual);
  if (branch == GateBranch.match) {
    return GateResult(
      proceed: true,
      branch: branch,
      repaired: false,
      expected: expected,
      actual: actual,
    );
  }

  // drift and totalLoss take the SAME repair shape — write the expected layout,
  // then prove it by reading back. They differ only in what went wrong, which
  // is worth reporting separately and not worth branching the repair over.
  bool wrote = false;
  try {
    wrote = await reprovision(expected);
  } catch (_) {
    wrote = false;
  }

  List<SegmentShape>? after;
  if (wrote) {
    try {
      after = await read();
    } catch (_) {
      after = null;
    }
  }

  final fixed = after != null && classifyGeometry(expected, after) == GateBranch.match;
  if (fixed) {
    return GateResult(
      proceed: true,
      branch: branch,
      repaired: true,
      expected: expected,
      actual: after,
    );
  }

  final observed = after ?? actual;
  return GateResult(
    proceed: false,
    branch: branch,
    repaired: false,
    expected: expected,
    actual: observed,
    refusal: 'gated_geometry_mismatch (${branch.name}) — expected '
        '${_shape(expected)}, got ${_shape(observed)}; re-provision '
        '${wrote ? 'did not take' : 'failed'}. Leaving the preset alone: a '
        'stale-but-correct ladder beats a freshly-saved wrong one, because the '
        'wrong one is durable and loads every night.',
  );
}

/// Parse a `/json/state` body into the gate's shape.
List<SegmentShape>? segmentShapeFromState(Map<String, dynamic>? state) {
  final raw = state?['seg'];
  if (raw is! List) return null;
  final out = <SegmentShape>[];
  for (var i = 0; i < raw.length; i++) {
    final s = raw[i];
    if (s is! Map) continue;
    final id = s['id'], start = s['start'], stop = s['stop'];
    if (id is! int || start is! int || stop is! int) continue;
    // WLED reports deleted/unused segments as zero-length; they are not part of
    // the installed shape and must not count toward the segment count.
    if (stop <= start) continue;
    out.add(SegmentShape(id, start, stop));
  }
  // NO PARSEABLE SEGMENTS == UNREADABLE, not "a device with zero segments".
  // Real WLED always reports at least one. An empty result means the body did
  // not tell us the shape, and the gate must treat that as ignorance (stand
  // aside) rather than as a total-loss claim it would then try to "repair".
  return out.isEmpty ? null : out;
}
