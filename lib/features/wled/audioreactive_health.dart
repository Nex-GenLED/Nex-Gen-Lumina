// lib/features/wled/audioreactive_health.dart
//
// AUDIOREACTIVE_ON — the fleet-wide effect-stall cause, confirmed on hardware
// (Tyler's bench .250 and the Blue Line Bar install, 417 LEDs). Both carried
// `um.AudioReactive.enabled = true` with a digital mic configured on GPIO 32/15
// that does not physically exist on our controllers. The usermod's I2S read +
// FFT task contends with the LED show task and freezes motion/effects.
//
// NOT app-caused: nothing in this repo has ever written a `um` key. It is the
// flash image default — our controllers are flashed with the AudioReactive
// build variant (cfg `id.name: "Dig-Octa-ESP32-8L-Eth-AR"`), which upstream
// builds with `-D UM_AUDIOREACTIVE_ENABLE` ("makes usermod default enabled").
// The dealer flash SOP now disables it at the bench; this heal covers the
// already-shipped fleet. See docs/dealer_preinstall_setup.md §2.5.
//
// ── Why the payload is a partial block, and why there is NO reboot ──────────
// Verified against upstream usermods/audioreactive/audio_reactive.cpp:
//
//  • SURGICAL IS SAFE. AudioReactive::readFromConfig() reads every field with
//    the TWO-arg getJsonValue(element, destination), which returns false and
//    leaves the destination UNTOUCHED when the key is absent — it does not
//    reset to a default (the three-arg defaulting overload is not used here).
//    So mic type/pins, squelch, gain, AGC, dynamics and sync all survive a
//    partial POST. WLED then self-persists it: deserializeConfig() does
//    `needsSave = !UsermodManager::readFromConfig(um)`, and an incomplete block
//    makes configComplete false → needsSave → the whole cfg is re-serialized
//    from RAM via addToConfig(), writing the intact block back with only
//    `enabled` flipped. Sending the FULL block is unnecessary and would risk
//    clobbering deliberate per-site mic config.
//
//  • NO REBOOT. loop() opens with
//        if (!enabled) { disableSoundProcessing = true; ...; return; }
//    and the FFT task gates on that same flag, so contention stops on the very
//    next loop iteration. readFromConfig() raises ERR_REBOOT_NEEDED ONLY when
//    the mic TYPE or the I2S PINS change — fields this payload never sends, so
//    oldDMType == dmType and no reboot flag fires. Upstream readme agrees:
//    "All parameters are runtime configurable. Some may require a hard reset
//    after changing them (I2S microphone or selected GPIOs)." Field-confirmed:
//    disabling it by hand on the customer controller cleared the freeze
//    immediately, with no restart.
//
//  • CFG, NOT STATE. /json/state also accepts {"AudioReactive":{"enabled":..}}
//    (readFromJsonState), but that is RUNTIME-ONLY and reverts on the next
//    boot. The durable fix must go through /json/cfg.
//
// LAN-ONLY. Reading `um` requires GET /json/cfg, which the bridge cannot do —
// its command dispatch maps only getState → /json/state and getInfo →
// /json/info. Same gating as the tz/coords heals.
//
// CAVEAT — Audio Mode. This heal keys off `enabled == true` alone; it does not
// check whether a microphone is physically attached, because nothing in cfg or
// /json/info reliably says so — the block advertises mic pins either way, which
// is precisely why the phantom-mic stall went unnoticed for so long. On a
// controller that genuinely has a working mic, this would disable Audio Mode on
// every connect. No controller shipped to date has one; revisit this if a
// mic-equipped SKU ever ships.

/// Capability interface for repositories that can read a controller's usermod
/// config. Kept OFF [WledRepository] on purpose — like [ClockInfoSource] and
/// PerPixelWriter — so the many repository implementations (and their test
/// fakes) don't all have to implement it. Only WledService opts in;
/// CloudRelayRepository deliberately does NOT, which makes the LAN-only gating
/// structural rather than a flag the caller can forget.
abstract class AudioReactiveConfigSource {
  /// Reads `cfg.um.AudioReactive.enabled` via GET /json/cfg. Read-only.
  ///
  /// Returns null when the value can't be determined — unreachable, cfg
  /// unreadable, or (legitimately) a firmware build with no AudioReactive
  /// usermod at all, where the `um.AudioReactive` block simply doesn't exist.
  /// Null is NOT "enabled"; see [audioReactiveNeedsHeal].
  Future<bool?> readAudioReactiveEnabled();
}

/// True when the AudioReactive usermod is ON and should be healed to off.
///
/// HEAL-ONLY-BROKEN: only an explicit `true` warrants a write. `false` (already
/// healed / correctly flashed) and null (no AudioReactive in this build, or cfg
/// unreadable) both mean "leave the controller alone" — a non-AR firmware must
/// never receive a `um` POST that would create the block from nothing.
bool audioReactiveNeedsHeal(bool? enabled) => enabled == true;

/// The surgical disable payload — `enabled` only, never the full block.
/// See the file header for why a partial block is safe and self-persisting.
Map<String, dynamic> audioReactiveHealPayload() => {
      'um': {
        'AudioReactive': {'enabled': false},
      },
    };

/// Extracts `um.AudioReactive.enabled` from a raw GET /json/cfg map.
///
/// Returns null when any link in the chain is missing or not a bool, so a
/// non-AR build (no `um.AudioReactive`) is indistinguishable from "unreadable"
/// — both are correctly treated as "don't heal". Pure; never throws.
bool? audioReactiveEnabledFromCfg(Map<String, dynamic>? cfg) {
  final um = cfg?['um'];
  if (um is! Map) return null;
  final ar = um['AudioReactive'];
  if (ar is! Map) return null;
  final enabled = ar['enabled'];
  return enabled is bool ? enabled : null;
}
