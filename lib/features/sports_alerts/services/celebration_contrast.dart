// lib/features/sports_alerts/services/celebration_contrast.dart
//
// AUTOMATIC RUNTIME CONTRAST CHECK.
//
// A celebration exists to interrupt. If it happens to be the same thing the
// house is ALREADY showing, it is invisible and the feature silently does
// nothing. The old code could not even notice: `buildAnimationSteps` took only
// `(eventType, team)`, so it was structurally incapable of consulting the
// current state, and the state that WAS fetched (`_captureZoneState`) went
// straight to the restore path and nowhere else
// (audit/GAME_DAY_SPEC_AUDIT.md §2.4).
//
// The check runs at TRIGGER TIME against LIVE house state — not against the
// stored base-design config — because what the house is doing at that moment is
// the thing the celebration has to stand out from. Autopilot may have rotated
// the design, a schedule may have taken over, or the user may have applied
// something by hand since the base design was chosen.

import 'package:flutter/foundation.dart';

import '../../wled/wled_effects_catalog.dart';

/// The always-safe fallback: a full-brightness WHITE strobe.
///
/// WHY WHITE. The fallback has to be distinct from a base look that already
/// clashed on motion — and if the clash was "both are strobes", another strobe
/// in team colours would clash exactly the same way. Colour is the one axis
/// guaranteed to differ from a team-coloured base, so the fallback drops team
/// colour entirely and floods white at maximum brightness. It is deliberately
/// ONE fixed thing: Tyler's decision was a single user choice, and this exists
/// so the automatic check has somewhere to go, not to become a second pick.
const int kFallbackCelebrationEffectId = 23; // 'Strobe'
const int kFallbackCelebrationSpeed = 255;
const int kFallbackCelebrationIntensity = 255;

/// White, full RGBW.
const List<int> kFallbackCelebrationColor = [255, 255, 255, 255];

/// The celebration to actually fire, after the contrast check.
@immutable
class CelebrationResolution {
  /// WLED effect id every animation stage should use.
  final int effectId;
  final int speed;
  final int intensity;

  /// True when the user's choice clashed and the safe fallback was
  /// substituted. Drives the white-colour override — a fallback that kept team
  /// colours would clash on exactly the axis it was substituted to avoid.
  final bool usedFallback;

  const CelebrationResolution({
    required this.effectId,
    required this.speed,
    required this.intensity,
    this.usedFallback = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelebrationResolution &&
          effectId == other.effectId &&
          speed == other.speed &&
          intensity == other.intensity &&
          usedFallback == other.usedFallback;

  @override
  int get hashCode => Object.hash(effectId, speed, intensity, usedFallback);

  @override
  String toString() => 'CelebrationResolution(fx: $effectId, sx: $speed, '
      'ix: $intensity, fallback: $usedFallback)';
}

/// Read the currently-running effect id out of a WLED `/json/state` snapshot.
///
/// Returns null when the state says nothing useful — no segments, or no `fx`.
///
/// `seg` is a List on most firmware and a Map on some — a documented
/// variability in this codebase (CLAUDE.md, "WLED JSON API Variability"), and
/// getting it wrong here would silently disable the contrast check on whichever
/// firmware took the other branch.
int? currentEffectId(Map<String, dynamic>? state) {
  if (state == null || state.isEmpty) return null;
  final seg = state['seg'];

  Map? first;
  if (seg is List) {
    if (seg.isEmpty) return null;
    // Prefer the first segment that is actually on; a disabled seg 0 would
    // otherwise report an effect nothing is displaying.
    for (final s in seg) {
      if (s is Map && (s['on'] as bool? ?? true)) {
        first = s;
        break;
      }
    }
    first ??= seg.first is Map ? seg.first as Map : null;
  } else if (seg is Map) {
    if (seg.isEmpty) return null;
    final v = seg.values.first;
    first = v is Map ? v : seg;
  }

  if (first == null) return null;
  return (first['fx'] as num?)?.toInt();
}

/// Decide which effect the celebration should actually use.
///
/// Returns null when [chosenEffectId] is null — the user has picked nothing, so
/// the caller keeps the legacy hardcoded per-event sequences verbatim. That is
/// what makes this change inert for every config in the fleet that predates it.
///
/// "TOO SIMILAR" is [WledEffectsCatalog.effectsTooSimilar]:
///   • the same effect id; OR
///   • both in the `Strobe` category — two different strobes read as one; OR
///   • both [MotionType.pulse].
///
/// FAIL-OPEN on missing information. If the captured state carries no readable
/// effect id — controller unreachable, empty snapshot, unexpected shape — the
/// user's choice fires unmodified. Substituting the fallback on "we don't know"
/// would replace a good celebration with a white flood on every transient read
/// failure, which is worse than the invisibility it guards against.
CelebrationResolution? resolveCelebration({
  required int? chosenEffectId,
  required int chosenSpeed,
  required int chosenIntensity,
  required Map<String, dynamic>? capturedState,
}) {
  if (chosenEffectId == null) return null; // legacy path

  final chosen = CelebrationResolution(
    effectId: chosenEffectId,
    speed: chosenSpeed,
    intensity: chosenIntensity,
  );

  final baseFx = currentEffectId(capturedState);
  if (baseFx == null) return chosen; // fail-open

  if (!WledEffectsCatalog.effectsTooSimilar(chosenEffectId, baseFx)) {
    return chosen;
  }

  return const CelebrationResolution(
    effectId: kFallbackCelebrationEffectId,
    speed: kFallbackCelebrationSpeed,
    intensity: kFallbackCelebrationIntensity,
    usedFallback: true,
  );
}
