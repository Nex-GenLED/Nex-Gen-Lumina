// test/features/wled/gamma_cfg_chokepoint_test.dart
//
// GAMMA WIPED BY EVERY CFG WRITE — audit/GAMMA_BUG.md, audit/GAMMA_FIX.md.
//
// BENCH-PROVEN on 192.168.1.150 (WLED 0.15.1, vid 2507300): a POST /json/cfg
// whose body omits `light.gc` resets gammaCorrectCol/gammaCorrectBri to false
// and serializeConfig() persists that to cfg.json on LittleFS — it survives
// reboot. `gc.val` is preserved by a separate firmware code path, which is why
// the readback shows col:2.8→1 while val stays 2.8. That asymmetry is the
// fingerprint. Verified against the LittleFS FILE (/cfg.json), not the live
// serialise (/json/cfg).
//
// Lumina had EIGHT cfg writers and none carried light.gc, so every schedule
// sync, lease sweep, healer heal and installer hardware push silently disabled
// colour gamma. It presented as "gamma turns off on some effects and not
// others" only because the GammaWatchdog repaired it within ≤2 min.
//
// FIX — normalizeWledCfgPayload injects light.gc at the WRITE BOUNDARY, the
// same shape as normalizeWledPayload/frz for state. Three boundaries funnel
// through it: WledService._postConfig (LAN), wled_config_pusher._postConfig
// (install-time raw HTTP), CloudRelayRepository.applyConfig (webhook). Not the
// eight call sites — that pattern does not survive (P1-51).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

void main() {
  Map<String, dynamic> gcOf(Map<String, dynamic> cfg) =>
      ((cfg['light'] as Map)['gc'] as Map).cast<String, dynamic>();

  group('normalizeWledCfgPayload — injects the NGL gamma standard', () {
    test('the schedule-sync timers payload gains light.gc', () {
      // The exact shape from cfg_payload_builder.dart — writer #1, the highest
      // frequency one. Bench Test C: this wiped gamma even when the timers were
      // byte-identical to what was already on the device.
      final out = normalizeWledCfgPayload({
        'timers': {
          'ins': [
            {'en': 1, 'hour': 20, 'min': 49, 'macro': 10, 'dow': 127},
          ],
        },
      });

      expect(gcOf(out), {'bri': 1, 'col': 2.8, 'val': 2.8});
      // The caller's own payload must survive untouched.
      expect(((out['timers'] as Map)['ins'] as List).length, 1);
    });

    test('the healer ntp/coords payloads gain light.gc', () {
      // Bench Test A — writers #3–5.
      final tz = normalizeWledCfgPayload({
        'if': {
          'ntp': {'tz': 5},
        },
      });
      expect(gcOf(tz)['col'], 2.8);
      expect(((tz['if'] as Map)['ntp'] as Map)['tz'], 5);

      final coords = normalizeWledCfgPayload({
        'if': {
          'ntp': {'lt': 38.99346, 'ln': -94.2527},
        },
      });
      expect(gcOf(coords)['col'], 2.8);
      expect(((coords['if'] as Map)['ntp'] as Map)['lt'], 38.99346);
    });

    test('the AudioReactive heal payload gains light.gc', () {
      // Writer #6 — the one that used to wipe the gamma the healer had just
      // asserted one step earlier.
      final out = normalizeWledCfgPayload({
        'um': {
          'AudioReactive': {'enabled': false},
        },
      });
      expect(gcOf(out)['col'], 2.8);
      expect(((out['um'] as Map)['AudioReactive'] as Map)['enabled'], false);
    });

    test('the installer hw.led bus payload gains light.gc', () {
      // Writer #7. hw.led and light.gc are independent cfg families; a bus
      // rebuild does not carry gamma and never did.
      final out = normalizeWledCfgPayload({
        'hw': {
          'led': {'total': 290, 'maxpwr': 20000, 'ins': []},
        },
      });
      expect(gcOf(out)['col'], 2.8);
      expect(((out['hw'] as Map)['led'] as Map)['total'], 290);
    });
  });

  group('non-destructive — the caller stays authoritative', () {
    test('an explicit light.gc passes through UNCHANGED', () {
      // pushGammaConfig's own payload, and any future user-facing gamma
      // control. Injecting over the top would make a deliberate setting
      // unwritable.
      final out = normalizeWledCfgPayload({
        'light': {
          'gc': {'bri': 2.2, 'col': 2.2, 'val': 2.2},
        },
        'if': {
          'live': {'no-gc': false},
        },
      });
      expect(gcOf(out), {'bri': 2.2, 'col': 2.2, 'val': 2.2});
    });

    test('a partial light object keeps its other keys and GAINS gc', () {
      // Bench Test B: {"light":{"scale-bri":100}} wiped gamma just as
      // thoroughly as a payload with no light key at all. Nesting a partial
      // light object is NOT protection — so the merge must go one level in.
      final out = normalizeWledCfgPayload({
        'light': {'scale-bri': 100, 'pal-mode': 0},
      });
      final light = out['light'] as Map;
      expect(light['scale-bri'], 100);
      expect(light['pal-mode'], 0);
      expect(gcOf(out)['col'], 2.8);
    });

    test('an empty gc map is treated as absent, not as authoritative', () {
      final out = normalizeWledCfgPayload({
        'light': {'gc': <String, dynamic>{}},
      });
      expect(gcOf(out)['col'], 2.8);
    });

    test('does not mutate the caller\'s map', () {
      final original = <String, dynamic>{
        'timers': {'ins': []},
      };
      normalizeWledCfgPayload(original);
      expect(original.containsKey('light'), isFalse);
    });

    test('an empty payload still asserts gamma', () {
      expect(gcOf(normalizeWledCfgPayload({}))['col'], 2.8);
    });
  });

  group('the asserted value is the NGL standard', () {
    test('matches kNglLightGammaConfig exactly — one definition', () {
      // bri:1 (brightness gamma OFF), col:2.8 (colour gamma ON), val:2.8.
      // col:1 is what the firmware defect writes; asserting 2.8 here is the
      // regression guard.
      expect(kNglLightGammaConfig, {'bri': 1, 'col': 2.8, 'val': 2.8});
      expect(gcOf(normalizeWledCfgPayload({'timers': {}})),
          kNglLightGammaConfig);
    });

    test('col is never 1 — the exact value the firmware defect writes', () {
      expect(gcOf(normalizeWledCfgPayload({'if': {}}))['col'], isNot(1));
    });
  });
}
