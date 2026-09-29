// Pure Dart (no flutter / dart:ui), like design_spacing_defaults.dart, so the
// bench CLI and every payload builder can reach it.
//
// THE RULE (#67, extended): *unstated design state is inherited design state,
// and inherited state is a bug.* `grp`/`spc` were the first fields brought
// under it (#88). These are the rest.
//
// WHY THESE FIELDS, from the firmware rather than from memory (WLED 0.15.1,
// `json.cpp` deserializeSegment + `FX_fcn.cpp` Segment::setMode):
//
//   * A segment has three effect sliders (`c1`,`c2`,`c3`) and three effect
//     checkboxes (`o1`,`o2`,`o3`). What they MEAN is per effect — "Overlay",
//     "Animate Shift", "Dual", "Gradient", "One color"…
//   * WLED's own UI sends `fxdef:true` when you pick an effect, which resets
//     all six. A JSON write without `fxdef` — every write this app makes —
//     changes the effect and leaves all six exactly as the segment's previous
//     effect, preset or web-UI session left them.
//   * So two segments given the SAME design can render it differently, and
//     the difference survives every later apply, because nothing states it.
//
// 33 of the app's 117 one-dimensional, non-audio catalog effects read at least
// one of the six ([kWledEffectOptionKeys]). The common one is "Overlay", which
// 18 of them expose (Scan, Two Dots, ICU, the Sparkle family, Glitter, Spots,
// Ripple, Lightning, Drip, the ball effects, Popcorn, Fireworks Starburst,
// Halloween Eyes): with it set, the effect stops painting its background and
// the segment keeps showing whatever was there before, motionless, under the
// moving part. Effects that read none of them are unaffected whatever the
// segment holds — so for those nothing is stated, which keeps payloads small.
//
// THE VALUES are the ones a segment is BORN with (`FX.h`: DEFAULT_C1 128,
// DEFAULT_C2 128, DEFAULT_C3 16, checks false). On a controller that has only
// ever been driven by this app those are already the values in place, so
// stating them changes nothing there; on a segment that drifted, stating them
// brings it back to what every other segment has been showing.

/// `c1` — first effect slider.
const int kSegDefaultC1 = 128;

/// `c2` — second effect slider.
const int kSegDefaultC2 = 128;

/// `c3` — third effect slider. 5 bits on the wire (0–31).
const int kSegDefaultC3 = 16;

/// `o1`/`o2`/`o3` — effect checkboxes.
const bool kSegDefaultOption = false;

/// Per-segment `bri`: the segment's OWN brightness, multiplied into the
/// master. Full, so a channel is never left dimmer than its neighbour by a
/// write the customer has long forgotten.
const int kSegDefaultBri = 255;

/// `sx` / `ix` when a complete design states neither.
const int kSegDefaultSpeed = 128;
const int kSegDefaultIntensity = 128;

/// The effect-option fields, in wire order.
const List<String> kSegEffectOptionKeys = ['c1', 'c2', 'c3', 'o1', 'o2', 'o3'];

/// Effects at or above this id are not in WLED 0.15.1. For those nothing is
/// known about which options they read, so all six are stated.
const int kWledKnownEffectIdCeiling = 187;

/// Which of the six options each WLED 0.15.1 effect READS, for every effect
/// that reads at least one. An effect not listed reads none.
///
/// Generated from the firmware source, not typed from memory: the UNION of
/// (a) the controls each effect's metadata string declares (`_data_FX_MODE_*`
/// in `FX.cpp`) and (b) the `custom1..3` / `check1..3` references reachable
/// from the effect's function. The union is deliberate — where the two
/// disagree (8 effects), stating an option the effect ignores costs a few
/// bytes, and missing one it reads is the bug this file exists for.
const Map<int, Set<String>> kWledEffectOptionKeys = {
  7: {'o1'}, // Dynamic
  10: {'o2'}, // Scan
  11: {'o2'}, // Scan Dual
  18: {'o1'}, // Dissolve
  20: {'o2'}, // Sparkle
  21: {'o2'}, // Sparkle Dark
  22: {'o2'}, // Sparkle+
  40: {'c1', 'o1', 'o2'}, // Scanner
  44: {'o1'}, // Tetrix
  48: {'o1', 'o2', 'o3'}, // Rolling Balls
  50: {'o2'}, // Two Dots
  57: {'o2'}, // Lightning
  58: {'o2'}, // ICU
  60: {'c1', 'o1', 'o2'}, // Scanner Dual
  65: {'c1', 'o1', 'o2', 'o3'}, // Palette
  66: {'c2', 'c3'}, // Fire 2012
  76: {'o1'}, // Meteor
  77: {'o1'}, // Meteor Smooth
  79: {'o2'}, // Ripple
  80: {'o1'}, // Twinklefox
  81: {'o1'}, // Twinklecat
  82: {'o2'}, // Halloween Eyes
  85: {'o2'}, // Spots
  86: {'o2'}, // Spots Fade
  87: {'o2'}, // Glitter
  89: {'o2'}, // Fireworks Starburst
  90: {'c1', 'c2', 'c3', 'o1', 'o2', 'o3'}, // Fireworks 1D
  91: {'o2'}, // Bouncing Balls
  95: {'o2'}, // Popcorn
  96: {'o2'}, // Drip
  98: {'o1'}, // Percent
  107: {'c1', 'c2', 'c3', 'o1', 'o2', 'o3'}, // Noise Pal
  114: {'o1'}, // Rotozoomer
  117: {'o1'}, // Dynamic Smooth
  121: {'c1', 'c2'}, // Blobs
  122: {'c1', 'c2', 'c3', 'o1', 'o2', 'o3'}, // Scrolling Text
  125: {'c1', 'c2'}, // Soap
  126: {'c1', 'c2', 'c3', 'o1'}, // Octopus
  127: {'c1', 'c2', 'c3'}, // Waving Cell
  137: {'c1', 'c2', 'c3'}, // Freqwave
  138: {'c1', 'c2', 'c3'}, // Freqmatrix
  139: {'c1', 'o1'}, // GEQ
  140: {'c1', 'c2'}, // Waterfall
  144: {'c1', 'c2'}, // Puddlepeak
  147: {'c1'}, // Perlin Move
  148: {'c1', 'c2'}, // Ripple Peak
  149: {'o1'}, // Firenoise
  150: {'c3'}, // Squared Swirl
  153: {'c1', 'o1'}, // Matrix
  160: {'c1'}, // Funky Plank
  164: {'o1'}, // Drift
  165: {'o2', 'o3'}, // Waverly
  167: {'c3', 'o1', 'o3'}, // Colored Bursts
  168: {'c1', 'c2', 'c3'}, // Julia
  173: {'c3'}, // Tartan
  174: {'c1'}, // Polar Lights
  175: {'c1'}, // Swirl
  176: {'c1', 'c2', 'c3', 'o1', 'o2', 'o3'}, // Lissajous
  177: {'c1'}, // Frizzles
  178: {'c1', 'c2'}, // Plasma Ball
  180: {'c3'}, // Hiphotic
  181: {'c1', 'c2'}, // Sindots
  183: {'c1', 'c2', 'c3', 'o1', 'o3'}, // Black Hole
  184: {'c1', 'c2', 'c3'}, // Wavesins
};

/// The options [effectId] reads, per [kWledEffectOptionKeys], in wire order.
Iterable<String> optionKeysReadBy(int effectId) {
  if (effectId < 0 || effectId >= kWledKnownEffectIdCeiling) {
    return kSegEffectOptionKeys;
  }
  final keys = kWledEffectOptionKeys[effectId];
  if (keys == null) return const <String>[];
  return kSegEffectOptionKeys.where(keys.contains);
}

/// The born-with value of option [key].
Object _optionDefault(String key) => switch (key) {
      'c1' => kSegDefaultC1,
      'c2' => kSegDefaultC2,
      'c3' => kSegDefaultC3,
      _ => kSegDefaultOption,
    };

/// Fills in, on [seg], every field an EFFECT statement leaves to inheritance.
/// Mutates and returns [seg]. A field the caller stated is never overwritten.
///
/// Applies to a segment that names an effect (`fx`) and is not a per-pixel
/// paint (`i`, which sets pixels directly and runs no effect):
///
///  * always: the segment's own `bri`, and each option the effect READS
///    ([optionKeysReadBy]). Naming an effect is what makes the previous
///    effect's options stale, so this holds for an effect-only change too.
///  * additionally, when the segment also states colours (`col`) — a COMPLETE
///    design rather than a one-field tweak — `sx`, `ix` and `pal`. An
///    effect-only or colour-only change keeps the speed, intensity and palette
///    the customer already tuned.
///
/// [paletteFor] supplies `pal` for an effect id when the design states none.
///
/// DELIBERATELY NOT STATED, with the reason for each:
///  * `start`,`stop`,`rev`,`mi`,`of` — where and which way the segment lies on
///    the house. Set when the controller is installed; an apply never states
///    them, and the wire strips the first four if one tries.
///  * `m12` — how a strip effect is laid onto a 2D matrix. Same family.
///  * `si` — sound simulation, owned by Audio Mode.
///  * `sel`,`cct`,`set` — change no pixel on an RGB(W) strip.
///  * an option the effect does not read — it cannot change the picture.
Map<String, dynamic> completeEffectSegment(
  Map<String, dynamic> seg, {
  required int Function(int effectId) paletteFor,
}) {
  final fx = seg['fx'];
  if (fx is! int || seg.containsKey('i')) return seg;

  for (final key in optionKeysReadBy(fx)) {
    seg.putIfAbsent(key, () => _optionDefault(key));
  }
  seg.putIfAbsent('bri', () => kSegDefaultBri);

  if (seg.containsKey('col')) {
    seg.putIfAbsent('sx', () => kSegDefaultSpeed);
    seg.putIfAbsent('ix', () => kSegDefaultIntensity);
    seg.putIfAbsent('pal', () => paletteFor(fx));
  }
  return seg;
}
