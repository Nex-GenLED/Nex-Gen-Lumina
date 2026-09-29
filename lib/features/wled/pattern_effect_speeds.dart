// Curated DEFAULT SPEEDS for a roofline — the `sx` an effect starts at when a
// customer selects it.
//
// Pure Dart (no flutter / dart:ui) so the bench CLI can import the real table:
// `dart run bench/bin/effect_speed_preview.dart`.
//
// ─── WHY THIS EXISTS ───────────────────────────────────────────────────────
// WLED's own default is `sx: 128` for almost every effect, tuned for a strip
// on a desk a metre away. On a roofline viewed from the street the same value
// reads as frantic: the owner reported Juggle, Bouncing Balls, Chunchun,
// Strobe, Fireworks, Fireworks 1D, Fireworks Starburst, Dancing Shadows and
// Strobe Mega as too fast (2026-09-29).
//
// The app had TWO disagreeing answers before this table: Explore's catalog
// cards used `128 × WledEffectsCatalog.speedMultipliers` (Bouncing Balls,
// Chunchun, Strobe, Dancing Shadows all went out at 128), while the palette
// tuner started from `EffectSpeedProfile.rawDefault`. The Home Tune panel's
// effect menu sent no speed at all, so an effect inherited whatever the last
// one ran at. This table is the one answer all three now read.
//
// ─── THE RULE ──────────────────────────────────────────────────────────────
// Selecting an effect sets its speed to the value here. It is a STARTING
// point, not a limit: the speed slider stays free above and below it (every
// value sits strictly inside its effect's slider range — a test holds that).
//
// Effects whose `sx` is not a pace ([kSpeedIsNotPace]) are left out of the
// pace table on purpose: for them `sx` is a size, a fill step, a flame height
// or a duration, and "a slower default" would change something else. Selecting
// one of those leaves the current speed alone.
//
// Values are PROPOSALS until seen on hardware. Each entry's trailing comment
// says where the number came from:
//   too fast (owner 09-29)   lowered from the reported value; firmware maths
//                            from WLED 0.15.1 FX.cpp quoted where it matters
//   FLASH                    full-field flashing — photosensitivity; see
//                            [kPhotosensitiveFlashEffectIds]
//   roofline pace            the hand-tuned `EffectSpeedProfile.rawDefault`,
//                            unchanged (already well under WLED's 128)
//   2D / audio               kept for completeness; not offered on a 1D
//                            roofline / speed means reactivity
//
// ─── EDITING ───────────────────────────────────────────────────────────────
// Keyed by WLED effect id. Tune on the bench with
// `dart run bench/bin/effect_speed_preview.dart` (spare controller .173 only),
// then edit here. test/features/wled/pattern_effect_speeds_test.dart fails if
// a catalog effect has no entry in either table, or if a default leaves its
// slider no room to move one way.

/// The speed an effect starts at when selected, or null when [effectId]'s
/// `sx` is not a pace ([kSpeedIsNotPace]) or the effect is not in the table
/// (a custom Lumina effect id). Null means: leave the current speed alone.
int? effectDefaultSpeed(int effectId) => kEffectDefaultSpeed[effectId];

/// [effectDefaultSpeed], or [current] when there is no default to apply.
int effectDefaultSpeedOr(int effectId, int current) =>
    kEffectDefaultSpeed[effectId] ?? current;

/// The default for [effectId] inside a catalog folder whose own pace is
/// [nodeSpeed] (LibraryNode.defaultSpeed, 128 = neutral). A calm folder
/// (60) slows every effect proportionally, a party folder (150) quickens it;
/// 0 is a static folder and stays 0. An effect with no pace default keeps
/// [nodeSpeed], exactly as before this table.
int scaledEffectDefaultSpeed(int effectId, int nodeSpeed) {
  if (nodeSpeed <= 0) return 0;
  final base = kEffectDefaultSpeed[effectId];
  if (base == null) return nodeSpeed.clamp(1, 255);
  return (base * nodeSpeed / 128).round().clamp(1, 255);
}

/// The ONE exception to "speed is the pace knob": effects whose firmware
/// ignores `sx` and takes its rate from intensity. Selecting one sets this
/// intensity as well; the intensity slider stays free.
///
///   42 Fireworks — `width/20` tries per frame, each firing with chance
///     1 in `129 - ix/2`. On a 300-LED run at 42 fps: ix 192 (firmware
///     default) → 13 sparks/s, ix 128 (what the app sent) → 9.7/s,
///     ix 32 → 5.6/s, ix 0 → 4.9/s (the floor).
const Map<int, int> kEffectDefaultIntensity = <int, int>{
  42: 32, // too fast (owner 09-29) · rate is intensity, not speed · Fireworks
};

/// [kEffectDefaultIntensity] for [effectId], or null to leave intensity alone.
int? effectDefaultIntensity(int effectId) => kEffectDefaultIntensity[effectId];

/// True when [effectId] flashes the whole field on and off — a
/// photosensitive-epilepsy trigger on an exterior-mounted product once the
/// flash rate passes ~3 Hz (WCAG 2.3.1's general flash threshold).
///
/// From WLED 0.15.1 FX.cpp:
///   23 Strobe, 24 Strobe Rainbow — `blink()`: one flash per
///     `(255-sx)*20 + 2*FRAMETIME` ms. At 42 fps: sx 128 → 0.39 Hz,
///     sx 240 → 2.9 Hz, sx 241 → 3.1 Hz, sx 255 → ~21 Hz.
///   25 Strobe Mega — bursts of `intensity/10 + 1` flashes at ~11–15 Hz
///     (15 ms on / 50 ms off, frame-quantised) WHATEVER the speed; speed only
///     sets the pause between bursts (`50 + 20*(255-sx)` ms). A speed floor
///     cannot make it safe; only `ix < 10` (one flash per burst) does.
///
/// Flagged for the owner's decision; nothing here restricts them.
const Set<int> kPhotosensitiveFlashEffectIds = {23, 24, 25};

/// Effect id → default roofline speed (`sx`).
const Map<int, int> kEffectDefaultSpeed = <int, int>{
  1: 80, // roofline pace · Blink
  2: 40, // roofline pace · Breathe
  5: 60, // roofline pace · Random Colors
  7: 70, // roofline pace · Dynamic
  8: 40, // roofline pace · Colorloop
  12: 40, // roofline pace · Fade
  18: 50, // roofline pace · Dissolve
  19: 50, // roofline pace · Dissolve Rnd
  26: 80, // roofline pace · Blink Rainbow
  34: 50, // roofline pace · Colorful
  35: 60, // roofline pace · Traffic Light
  46: 35, // roofline pace · Gradient
  47: 60, // roofline pace · Loading
  56: 40, // roofline pace · Tri Fade
  62: 60, // roofline pace · Oscillate
  65: 45, // roofline pace · Palette
  68: 80, // roofline pace · Bpm
  86: 40, // roofline pace · Spots Fade
  100: 45, // roofline pace · Heartbeat
  108: 45, // roofline pace · Sine
  113: 60, // roofline pace · Washing Machine
  117: 60, // roofline pace · Dynamic Smooth
  128: 60, // roofline pace · Pixels
  3: 50, // roofline pace · Wipe
  4: 50, // roofline pace · Wipe Random
  6: 50, // roofline pace · Sweep
  36: 50, // roofline pace · Sweep Random
  55: 50, // roofline pace · Tri Wipe
  13: 55, // roofline pace · Theater
  14: 55, // roofline pace · Theater Rainbow
  15: 55, // roofline pace · Running
  16: 55, // roofline pace · Saw
  27: 55, // roofline pace · Android
  28: 60, // roofline pace · Chase
  29: 60, // roofline pace · Chase Random
  30: 60, // roofline pace · Chase Rainbow
  31: 60, // roofline pace · Chase Flash
  32: 60, // roofline pace · Chase Flash Rnd
  37: 60, // roofline pace · Chase 2
  50: 55, // roofline pace · Two Dots
  52: 55, // roofline pace · Running Dual
  54: 60, // roofline pace · Chase 3
  64: 32, // too fast (owner 09-29) · beatsin88((16+sx)*(i+7)): firmware default 64 · Juggle
  78: 55, // roofline pace · Railway
  92: 55, // roofline pace · Sinelon
  93: 55, // roofline pace · Sinelon Dual
  94: 55, // roofline pace · Sinelon Rainbow
  111: 16, // too fast (owner 09-29) · counter = now*(6+(sx>>4)): 16 → 7, 128 → 14, floor 6 · Chunchun
  10: 45, // roofline pace · Scan
  11: 45, // roofline pace · Scan Dual
  40: 45, // roofline pace · Scanner
  41: 45, // roofline pace · Lighthouse
  58: 50, // roofline pace · ICU
  60: 45, // roofline pace · Scanner Dual
  17: 200, // roofline pace · Twinkle
  20: 45, // roofline pace · Sparkle
  21: 45, // roofline pace · Sparkle Dark
  22: 45, // roofline pace · Sparkle+
  49: 35, // roofline pace · Fairy
  51: 35, // roofline pace · Fairytwinkle
  74: 35, // roofline pace · Colortwinkles
  80: 35, // roofline pace · Twinklefox
  81: 35, // roofline pace · Twinklecat
  87: 40, // roofline pace · Glitter
  106: 35, // roofline pace · Twinkleup
  59: 40, // roofline pace · Multi Comet
  76: 40, // roofline pace · Meteor
  77: 40, // roofline pace · Meteor Smooth
  45: 30, // roofline pace · Fire Flicker
  88: 25, // roofline pace · Candle
  102: 25, // roofline pace · Candle Multi
  89: 20, // too fast (owner 09-29) · "Chance": 1-in-(144-sx/2) per frame per star · Fireworks Starburst
  90: 32, // too fast (owner 09-29) · "Gravity": -0.0004-sx/800000 m/s/s · Fireworks 1D
  79: 35, // roofline pace · Ripple
  99: 35, // roofline pace · Ripple Rainbow
  9: 40, // roofline pace · Rainbow
  33: 55, // roofline pace · Rainbow Runner
  63: 40, // roofline pace · Pride 2015
  23: 48, // too fast (owner 09-29) · FLASH — see kPhotosensitiveFlashEffectIds · Strobe
  24: 48, // FLASH — same blink() as Strobe; matched to Strobe · Strobe Rainbow
  25: 40, // too fast (owner 09-29) · FLASH — see kPhotosensitiveFlashEffectIds · Strobe Mega
  57: 60, // roofline pace · Lightning
  38: 30, // roofline pace · Aurora
  39: 30, // roofline pace · Stream
  43: 35, // roofline pace · Rain
  61: 30, // roofline pace · Stream 2
  67: 30, // roofline pace · Colorwaves
  75: 25, // roofline pace · Lake
  96: 35, // roofline pace · Drip
  97: 30, // roofline pace · Plasma
  101: 25, // roofline pace · Pacifica
  105: 30, // roofline pace · Phased
  110: 30, // roofline pace · Flow
  112: 20, // too fast (owner 09-29) · spotlight speed x(1+sx)/100: 20 → x0.21, 128 → x1.29 · Dancing Shadows
  115: 30, // roofline pace · Blends
  116: 60, // roofline pace · TV Simulator
  69: 30, // roofline pace · Fill Noise
  70: 30, // roofline pace · Noise 1
  71: 30, // roofline pace · Noise 2
  72: 30, // roofline pace · Noise 3
  73: 30, // roofline pace · Noise 4
  107: 30, // roofline pace · Noise Pal
  109: 30, // roofline pace · Phased Noise
  44: 60, // roofline pace · Tetrix
  48: 60, // no profile existed (WLED 128); halved for a roofline · Rolling Balls
  91: 32, // too fast (owner 09-29) · "Gravity"; firmware time ÷((255-sx)/64+1) has 4 steps, 0–63 is the slowest · Bouncing Balls
  95: 55, // roofline pace · Popcorn
  82: 40, // INVERTED: sx is eye OFF time (sx*128 ms); higher = calmer · Halloween Eyes
  114: 128, // 2D — not offered on a 1D roofline · Rotozoomer
  118: 60, // 2D — not offered on a 1D roofline · Spaceships
  119: 60, // 2D — not offered on a 1D roofline · Crazy Bees
  120: 60, // 2D — not offered on a 1D roofline · Ghost Rider
  121: 60, // 2D — not offered on a 1D roofline · Blobs
  122: 60, // 2D — not offered on a 1D roofline · Scrolling Text
  123: 60, // 2D — not offered on a 1D roofline · Drift Rose
  124: 60, // 2D — not offered on a 1D roofline · Distortion Waves
  125: 60, // 2D — not offered on a 1D roofline · Soap
  126: 60, // 2D — not offered on a 1D roofline · Octopus
  127: 60, // 2D — not offered on a 1D roofline · Waving Cell
  146: 60, // 2D — not offered on a 1D roofline · Noise2D
  149: 60, // 2D — not offered on a 1D roofline · Firenoise
  150: 60, // 2D — not offered on a 1D roofline · Squared Swirl
  152: 60, // 2D — not offered on a 1D roofline · DNA
  153: 60, // 2D — not offered on a 1D roofline · Matrix
  154: 60, // 2D — not offered on a 1D roofline · Metaballs
  162: 60, // 2D — not offered on a 1D roofline · Pulser
  164: 60, // 2D — not offered on a 1D roofline · Drift
  166: 60, // 2D — not offered on a 1D roofline · Sun Radiation
  167: 60, // 2D — not offered on a 1D roofline · Colored Bursts
  168: 60, // 2D — not offered on a 1D roofline · Julia
  172: 60, // 2D — not offered on a 1D roofline · Game Of Life
  173: 60, // 2D — not offered on a 1D roofline · Tartan
  174: 60, // 2D — not offered on a 1D roofline · Polar Lights
  176: 60, // 2D — not offered on a 1D roofline · Lissajous
  177: 60, // 2D — not offered on a 1D roofline · Frizzles
  178: 60, // 2D — not offered on a 1D roofline · Plasma Ball
  179: 60, // 2D — not offered on a 1D roofline · Flow Stripe
  180: 60, // 2D — not offered on a 1D roofline · Hiphotic
  181: 60, // 2D — not offered on a 1D roofline · Sindots
  182: 60, // 2D — not offered on a 1D roofline · DNA Spiral
  183: 60, // 2D — not offered on a 1D roofline · Black Hole
  184: 60, // 2D — not offered on a 1D roofline · Wavesins
  186: 60, // 2D — not offered on a 1D roofline · Akemi
  129: 80, // audio — speed is reactivity, not pace · Pixelwave
  130: 80, // audio — speed is reactivity, not pace · Juggles
  131: 80, // audio — speed is reactivity, not pace · Matripix
  132: 80, // audio — speed is reactivity, not pace · Gravimeter
  133: 80, // audio — speed is reactivity, not pace · Plasmoid
  134: 80, // audio — speed is reactivity, not pace · Puddles
  135: 80, // audio — speed is reactivity, not pace · Midnoise
  136: 80, // audio — speed is reactivity, not pace · Noisemeter
  137: 80, // audio — speed is reactivity, not pace · Freqwave
  138: 80, // audio — speed is reactivity, not pace · Freqmatrix
  139: 80, // audio — speed is reactivity, not pace · GEQ
  140: 80, // audio — speed is reactivity, not pace · Waterfall
  141: 80, // audio — speed is reactivity, not pace · Freqpixels
  143: 80, // audio — speed is reactivity, not pace · Noisefire
  144: 80, // audio — speed is reactivity, not pace · Puddlepeak
  145: 80, // audio — speed is reactivity, not pace · Noisemove
  147: 80, // audio — speed is reactivity, not pace · Perlin Move
  148: 80, // audio — speed is reactivity, not pace · Ripple Peak
  155: 80, // audio — speed is reactivity, not pace · Freqmap
  156: 80, // audio — speed is reactivity, not pace · Gravcenter
  157: 80, // audio — speed is reactivity, not pace · Gravcentric
  158: 80, // audio — speed is reactivity, not pace · Gravfreq
  159: 80, // audio — speed is reactivity, not pace · DJ Light
  160: 80, // audio — speed is reactivity, not pace · Funky Plank
  163: 80, // audio — speed is reactivity, not pace · Blurz
  165: 80, // audio — speed is reactivity, not pace · Waverly
  175: 80, // audio — speed is reactivity, not pace · Swirl
  185: 80, // audio — speed is reactivity, not pace · Rocktaves
};

/// Effects whose `sx` is not a pace. Selecting one leaves the speed alone.
const Set<int> kSpeedIsNotPace = <int>{
  0, // Solid does not animate · Solid
  83, // speed is foreground size; the Solid layout helper owns it · Solid Pattern
  84, // firmware ignores speed · Solid Pattern Tri
  85, // speed is spread (a static size), not pace · Spots
  98, // speed is fill-step size, not pace · Percent
  103, // firmware ignores speed · Solid Glitter
  66, // speed is "Cooling" (flame height), not pace · Fire 2012
  42, // firmware ignores speed; launch rate is intensity ("Frequency") · Fireworks
  104, // speed is the sunrise DURATION in minutes, not pace · Sunrise
};
