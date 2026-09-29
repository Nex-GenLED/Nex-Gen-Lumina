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
// 31 of the app's 117 one-dimensional, non-audio catalog effects read at least
// one of the six. The common one is "Overlay", read by 18 of them (Scan, Two
// Dots, ICU, the Sparkle family, Glitter, Spots, Ripple, Lightning, Drip, the
// ball effects, Popcorn, Fireworks Starburst, Halloween Eyes): with it set, the
// effect stops painting
// its background and the segment keeps showing whatever was there before,
// motionless, under the moving part. Effects that read none of them — most
// twinkles, fades and chases — are unaffected whatever the segment holds.
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

/// Fills in, on [seg], every field an EFFECT statement leaves to inheritance.
/// Mutates and returns [seg]. A field the caller stated is never overwritten.
///
/// Applies to a segment that names an effect (`fx`) and is not a per-pixel
/// paint (`i`, which sets pixels directly and runs no effect):
///
///  * always: `c1`,`c2`,`c3`,`o1`,`o2`,`o3` and the segment's own `bri`.
///    Naming an effect is what makes the previous effect's options stale, so
///    this holds for an effect-only change too.
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
Map<String, dynamic> completeEffectSegment(
  Map<String, dynamic> seg, {
  required int Function(int effectId) paletteFor,
}) {
  final fx = seg['fx'];
  if (fx is! int || seg.containsKey('i')) return seg;

  seg.putIfAbsent('c1', () => kSegDefaultC1);
  seg.putIfAbsent('c2', () => kSegDefaultC2);
  seg.putIfAbsent('c3', () => kSegDefaultC3);
  seg.putIfAbsent('o1', () => kSegDefaultOption);
  seg.putIfAbsent('o2', () => kSegDefaultOption);
  seg.putIfAbsent('o3', () => kSegDefaultOption);
  seg.putIfAbsent('bri', () => kSegDefaultBri);

  if (seg.containsKey('col')) {
    seg.putIfAbsent('sx', () => kSegDefaultSpeed);
    seg.putIfAbsent('ix', () => kSegDefaultIntensity);
    seg.putIfAbsent('pal', () => paletteFor(fx));
  }
  return seg;
}
