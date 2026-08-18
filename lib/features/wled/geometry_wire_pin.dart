// Pure-Dart (no flutter / dart:ui) geometry pin for the WLED wire exit.
//
// THE RULE, one sentence: **an apply never states geometry.** Segment bounds
// (`start`/`stop`) are provisioning's, sourced from the controller's own
// hardware buses. Everything else — designs, colours, effects, power, scenes,
// Game Day, Sync — states LOOK, never SHAPE.
//
// WHY THIS LIVES AT THE WIRE AND NOT IN THE BUILDERS
// --------------------------------------------------
// Four censuses have now under-counted this family:
//
//   #76  fenced seven design builders.
//   #88  found more, and recorded the lesson: "an emitter census must be a grep
//        of the FIELD NAMES across lib/, not a walk of the builders you already
//        know about."
//   #89  fenced `applyChannelFilter`.
//   #95  fenced `buildChannelPowerPayload` — which #76, #88 and #89 had all
//        missed, because it was in nobody's list of "design builders".
//
// Each fence was correct and each census was incomplete, because a census of
// builders is a list you maintain by hand and the compiler cannot check. This
// pin is at the SINGLE EXIT instead: every `/json/state` apply passes through
// one function, so the pin cannot under-count by construction. A new builder
// added tomorrow is covered the day it is written, by nobody remembering
// anything.
//
// FAIL-SAFE, NOT FAIL-LOUD-ONLY. In debug/test the assert fires and the test
// dies. In RELEASE — where the fleet lives and where an assert is stripped —
// the bounds are STRIPPED from the payload and the violation is logged. The
// apply still lands, minus the geometry it had no business stating. Same shape
// as `normalizeWledCfgPayload`, which strips-and-proceeds at the `/json/cfg`
// boundary for the gamma-revert class rather than refusing the write.
//
// THE ALLOWLIST IS A SEPARATE DOOR, NOT A FLAG ON THIS ONE. Provisioning paths
// that legitimately state geometry (healer re-provision, schedule gate
// re-provision, sunrise-off, lease manager) call the geometry-specific entry
// point, which is a different method with a name that says so. A boolean
// parameter on the ordinary path would be one typo away from disabling the pin
// at the call site that needed it most.

/// One violation: which seg entry carried bounds, and which keys.
class GeometryViolation {
  const GeometryViolation({
    required this.index,
    required this.segId,
    required this.keys,
  });

  /// Position in the `seg` array (always known).
  final int index;

  /// `id` field if present, else null — an id-less seg is itself a smell.
  final int? segId;

  /// The offending keys actually present, e.g. `['start', 'stop']`.
  final List<String> keys;

  @override
  String toString() => 'seg[$index]${segId == null ? '' : '(id=$segId)'}'
      ':${keys.join('+')}';
}

/// The bound-stating keys. `start`/`stop` are the segment RANGE.
///
/// Deliberately NOT included: `len`. WLED reports `len` in `/json/state`
/// readbacks as a derived convenience, so a payload echoing a readback would
/// trip on it constantly while stating nothing new — and `len` alone cannot
/// move a boundary. `start`/`stop` are the two that re-bound a segment.
const List<String> kGeometryKeys = ['start', 'stop'];

/// Find every `seg` entry that states geometry. Pure; no side effects.
///
/// Returns an empty list for any payload shape that cannot carry bounds
/// (no `seg`, `seg` not a List, entries not Maps) — this is a pin, not a
/// schema validator, and it must never invent a violation from a shape it
/// does not understand.
List<GeometryViolation> findGeometryViolations(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  if (seg is! List) return const [];

  final out = <GeometryViolation>[];
  for (var i = 0; i < seg.length; i++) {
    final s = seg[i];
    if (s is! Map) continue;
    final keys = <String>[
      for (final k in kGeometryKeys)
        if (s.containsKey(k)) k,
    ];
    if (keys.isEmpty) continue;
    final rawId = s['id'];
    out.add(GeometryViolation(
      index: i,
      segId: rawId is int ? rawId : (rawId is num ? rawId.toInt() : null),
      keys: keys,
    ));
  }
  return out;
}

/// Return a copy of [payload] with every `start`/`stop` removed from `seg`
/// entries. Structure, order, ids and every other field are preserved — this
/// removes the two keys and changes nothing else.
///
/// Returns the SAME instance when there is nothing to strip, so the hot path
/// (which is every ordinary apply) pays no copy.
Map<String, dynamic> stripGeometry(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  if (seg is! List) return payload;

  var touched = false;
  final cleaned = <dynamic>[];
  for (final s in seg) {
    if (s is! Map) {
      cleaned.add(s);
      continue;
    }
    final hasBounds = kGeometryKeys.any(s.containsKey);
    if (!hasBounds) {
      cleaned.add(s);
      continue;
    }
    touched = true;
    final copy = Map<String, dynamic>.from(s);
    for (final k in kGeometryKeys) {
      copy.remove(k);
    }
    cleaned.add(copy);
  }
  if (!touched) return payload;

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = cleaned;
  return result;
}

/// The wire pin. Call immediately before POSTing an apply.
///
/// [caller] names the exit for the log line — `'local'` / `'relay'`.
/// [onViolation] receives a one-line human-readable report; wire it to
/// `debugPrint` at the call site (this file stays flutter-free).
///
/// Returns the payload to actually send: unchanged when clean, bounds-stripped
/// when not.
Map<String, dynamic> pinNoGeometryOnWire(
  Map<String, dynamic> payload, {
  required String caller,
  void Function(String message)? onViolation,
}) {
  final violations = findGeometryViolations(payload);
  if (violations.isEmpty) return payload;

  final report = 'GEOMETRY ON THE WIRE ($caller): an apply tried to state '
      'segment bounds — ${violations.join(', ')}. Bounds are provisioning\'s '
      '(#76/#88/#89/#95). STRIPPED; the rest of the apply proceeds. If this '
      'caller legitimately provisions geometry it must use the geometry entry '
      'point, not applyJson.';
  onViolation?.call(report);

  // Debug/test: die here, loudly, at the exact wire exit. Stripped in release,
  // where the strip below is the protection instead.
  assert(false, report);

  return stripGeometry(payload);
}
