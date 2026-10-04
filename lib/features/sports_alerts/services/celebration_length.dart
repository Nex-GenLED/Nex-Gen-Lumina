// #169 — how long a score celebration plays: the team's Short / Medium / Long.
//
// Owner decision 2026-10-04. Each preset is a MULTIPLIER of the event's own
// length (so a touchdown still plays longer than a field goal): Short x0.5,
// Medium x1 (today's lengths — and what an unset team gets), Long x2. Every
// celebration is held between [kCelebrationMinLength] and
// [kCelebrationMaxLength], whatever the setting or the multiplier: there is no
// open-ended celebration. This is separate from Speed, which sets how fast the
// effect animates.

import 'dart:math' as math;

enum CelebrationLength {
  short(0.5, 'short', 'Short'),
  medium(1.0, 'medium', 'Medium'),
  long(2.0, 'long', 'Long');

  const CelebrationLength(this.multiplier, this.wire, this.label);

  /// How many times the event's medium (today's) length this preset plays.
  final double multiplier;

  /// The value stored as `celebration_length` on the team doc.
  final String wire;

  /// What the picker shows.
  final String label;

  /// The stored value read back. Absent, unknown or malformed is [medium]:
  /// an account that never chose plays exactly what it played before.
  static CelebrationLength fromWire(Object? value) {
    for (final l in values) {
      if (l.wire == value) return l;
    }
    return medium;
  }
}

/// No celebration plays shorter than this — shorter reads as a glitch, and
/// away from home it can end before the bridge has delivered it.
const Duration kCelebrationMinLength = Duration(seconds: 5);

/// No celebration plays longer than this, whatever the setting. The win at
/// Long is exactly this.
const Duration kCelebrationMaxLength = Duration(seconds: 60);

int _roundHalfUp(double x) => (x + 0.5).floor();

/// PURE. The holds of a staged celebration at [length].
///
/// Each stage is scaled and rounded to whole seconds (at least 1 s); the LAST
/// stage absorbs the rounding so the total is the medium total x multiplier,
/// rounded half up, then clamped to [kCelebrationMinLength] ..
/// [kCelebrationMaxLength]. An event with no stages stays empty.
///
/// [multiplier] overrides the preset's (tests prove the clamp holds for any
/// value).
List<Duration> scaleCelebrationHolds(
  List<Duration> medium,
  CelebrationLength length, {
  double? multiplier,
}) {
  if (medium.isEmpty) return const [];
  final m = multiplier ?? length.multiplier;
  final secs = [for (final d in medium) d.inMilliseconds / 1000.0];
  final total = secs.fold<double>(0, (a, b) => a + b);
  final target = math.max(
    secs.length,
    _roundHalfUp(total * m).clamp(
      kCelebrationMinLength.inSeconds,
      kCelebrationMaxLength.inSeconds,
    ),
  );
  final scaled = [for (final s in secs) math.max(1, _roundHalfUp(s * m))];
  var diff = target - scaled.fold<int>(0, (a, b) => a + b);
  for (var i = scaled.length - 1; i >= 0 && diff != 0; i--) {
    final next = math.max(1, scaled[i] + diff);
    diff -= next - scaled[i];
    scaled[i] = next;
  }
  return [for (final s in scaled) Duration(seconds: s)];
}

/// PURE. The total of [holds].
Duration totalOf(List<Duration> holds) =>
    holds.fold(Duration.zero, (a, b) => a + b);

/// The seconds a touchdown plays at [length] (its medium stages are
/// 2 + 5 + 8 s).
int touchdownSecondsAt(CelebrationLength length) => totalOf(
        scaleCelebrationHolds(const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 8),
    ], length))
    .inSeconds;

/// The helper line under the Length control: a touchdown's seconds at each
/// setting, from the same scaling the celebrations use.
String celebrationLengthHelper() =>
    'A touchdown plays ${touchdownSecondsAt(CelebrationLength.short)} '
    'seconds on Short, ${touchdownSecondsAt(CelebrationLength.medium)} on '
    'Medium and ${touchdownSecondsAt(CelebrationLength.long)} on Long. '
    'Every celebration ends on its own.';
