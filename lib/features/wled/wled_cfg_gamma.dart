// Pure-Dart (no flutter / dart:ui) home of the NGL gamma standard and the
// cfg-payload gamma chokepoint, extracted from wled_payload_utils.dart so the
// bench/ CLI can route its own `/json/cfg` writes through the SAME normaliser
// the app uses (`dart run` cannot load dart:ui; wled_payload_utils imports
// flutter/foundation). wled_payload_utils.dart re-exports these, so every
// existing importer is unaffected — same pattern as timer_landing.dart and
// cfg_payload_builder.dart (200e9e3).
//
// Why the bench needs it (2026-09-22): every harness cfg POST was timers-only,
// and WLED 0.15.x recomputes the gamma flags from the body on EVERY cfg
// deserialise, so each restore/scratch write silently reset `light.gc.col`
// 2.8→1 on the live controller. The app's three write boundaries were already
// protected; the harness was a fourth boundary with no protection.

/// The NGL color-gamma standard, written to `cfg.light.gc`.
///
/// Matches the WLED firmware default that renders saturated colors correctly
/// on the Lumina SK6812/WS2814 RGBW strip: brightness gamma OFF (`bri:1`),
/// color gamma ON (`col:2.8`), exponent 2.8 (`val:2.8`). WLED stores gamma
/// here — NOT under `hw.led`. A `2.8`/`1`/`2.8` triple is what makes orange
/// render vivid instead of washed amber (gamma darkens the green midtone).
///
/// Lives HERE, not in wled_config_pusher, purely for the import graph:
/// [normalizeWledCfgPayload] needs it, and every cfg write boundary must reach
/// that function. wled_config_pusher imports wled_service imports this file, so
/// defining it in the pusher and importing it back would close a cycle. This is
/// still the ONE definition — the pusher imports it from here.
const Map<String, dynamic> kNglLightGammaConfig = <String, dynamic>{
  'bri': 1,
  'col': 2.8,
  'val': 2.8,
};

/// Asserts [kNglLightGammaConfig] at `light.gc` on EVERY outbound `/json/cfg`
/// payload. The cfg-side twin of [normalizeWledPayload] — same role, same
/// reason: a firmware defect that must be neutralised at the write boundary
/// rather than at each call site.
///
/// **The firmware defect** (WLED 0.15.1, bench-proven 4× — audit/GAMMA_BUG.md):
/// a `POST /json/cfg` whose body omits `light.gc` resets `gammaCorrectCol` and
/// `gammaCorrectBri` to false and `serializeConfig()` persists that to
/// `cfg.json` on LittleFS, so it survives reboot. `gc.val` is preserved by a
/// separate code path — that `col`-resets-while-`val`-survives asymmetry is the
/// fingerprint. Every unrelated cfg key deep-merges correctly; only `light.gc`
/// is recomputed from an absent object. Nesting a partial `light` does NOT
/// protect it: `{"light":{"scale-bri":100}}` wipes gamma just as thoroughly.
///
/// Lumina had EIGHT cfg writers (schedule timers, calendar-lease sweeps, four
/// healer heals, the installer hardware screen, the profile location push) and
/// none carried `light.gc`, so every one of them silently disabled colour
/// gamma. The symptom read as "gamma turns off on some effects and not others"
/// because the GammaWatchdog repaired it within ≤2 min — the apparent
/// effect-correlation was an artifact of the observation window.
///
/// **Why the boundary and not the call sites:** eight sites is eight chances to
/// forget, and the ninth writer added later inherits the bug silently. P1-51 is
/// the standing evidence that per-call-site discipline does not survive contact
/// with this codebase. Injecting here means a cfg payload cannot leave the app
/// without gamma, whatever it is for and whoever wrote it.
///
/// Non-destructive: a caller that already supplies `light.gc` is authoritative
/// and passes through untouched (that is how [pushGammaConfig]'s own payload,
/// and any future user-facing gamma control, keep working). Other `light.*`
/// keys are preserved — the merge is one level deep into `light`, adding only
/// the missing `gc`.
///
/// **Second firmware defect, same boundary (2026-10-20, source read of WLED
/// v0.15.1, v0.15.4 and v16.0.1):** `deserializeConfig` reads the target frame
/// rate as `strip.setTargetFps(hw_led["fps"])` (0.15.x `cfg.cpp:119`). A body
/// without `hw.led.fps` yields 0, and 0.15.x's `setTargetFps` accepts 0 as
/// UNLIMITED (`FX_fcn.cpp:1488-1491`, `FPS_UNLIMITED 0`), so every partial cfg
/// write the app ever made set the render loop free-running and starved the
/// web server. 16.0.1 defaults a missing key to 42 (`cfg.cpp:181`), so there
/// the injection is harmless and merely explicit. The fix is the same shape as
/// gamma: carry `hw.led.fps` on every body. [currentFps] is the device's own
/// value from the cfg the caller last read; it is kept when it is a real rate
/// (1–250), otherwise [kDefaultTargetFps] goes out. A body that already names a
/// usable `hw.led.fps` is authoritative. A partial `hw.led` object is safe on
/// all three firmwares: the bus list is only touched when `ins` is present,
/// and total/maxpwr default to the device's current values.
Map<String, dynamic> normalizeWledCfgPayload(
  Map<String, dynamic> cfg, {
  int? currentFps,
}) {
  final out = Map<String, dynamic>.from(cfg);

  final light = cfg['light'];
  final existingGc = light is Map ? light['gc'] : null;
  // Caller supplied gamma explicitly — it wins, unconditionally.
  if (!(existingGc is Map && existingGc.isNotEmpty)) {
    final mergedLight = light is Map
        ? Map<String, dynamic>.from(light)
        : <String, dynamic>{};
    mergedLight['gc'] = Map<String, dynamic>.from(kNglLightGammaConfig);
    out['light'] = mergedLight;
  }

  final hw = cfg['hw'];
  final led = hw is Map ? hw['led'] : null;
  final existingFps = led is Map ? led['fps'] : null;
  if (!(existingFps is num && isUsableTargetFps(existingFps.toInt()))) {
    final mergedHw =
        hw is Map ? Map<String, dynamic>.from(hw) : <String, dynamic>{};
    final mergedLed =
        led is Map ? Map<String, dynamic>.from(led) : <String, dynamic>{};
    mergedLed['fps'] = resolveTargetFps(currentFps);
    mergedHw['led'] = mergedLed;
    out['hw'] = mergedHw;
  }
  return out;
}

/// The frame rate written to `cfg.hw.led.fps` when the device's own value is
/// unknown or unusable (0 = the unlimited mode this fix exists to undo).
/// Owner decision 2026-10-20: 60, not WLED's 42.
const int kDefaultTargetFps = 60;

/// WLED's accepted range for `hw.led.fps` (`setTargetFps`: `fps <= 250`,
/// 0 meaning unlimited). 1–250 is a real rate; anything else is replaced.
const int kMinTargetFps = 1;
const int kMaxTargetFps = 250;

bool isUsableTargetFps(int? fps) =>
    fps != null && fps >= kMinTargetFps && fps <= kMaxTargetFps;

/// The rate to carry: the device's own when usable, else the default.
int resolveTargetFps(int? currentFps) =>
    isUsableTargetFps(currentFps) ? currentFps! : kDefaultTargetFps;

/// `cfg.hw.led.fps` from a raw `/json/cfg` map, or null when absent or not a
/// number. 0 is returned as 0 (the caller decides what unusable means).
int? targetFpsFromCfg(Map<String, dynamic>? cfg) {
  final hw = cfg?['hw'];
  final led = hw is Map ? hw['led'] : null;
  final fps = led is Map ? led['fps'] : null;
  return fps is num ? fps.toInt() : null;
}
