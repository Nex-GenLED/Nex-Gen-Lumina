# GAMMA_FIX — stop triggering the WLED cfg-deserialiser defect

**Date:** 2026-08-07 · **Rig:** `.150` (WLED 0.15.1, vid 2507300) · **Diagnosis:** [audit/GAMMA_BUG.md](GAMMA_BUG.md)
**Status:** IMPLEMENTED · analyze clean · **1945 passed / 3 skipped / 1 pre-existing failure** · **9/9 on hardware**
**Release-affecting.** Rig left healthy: `light.gc {"bri":1,"col":2.8,"val":2.8}`, `no-gc:false`, AR off, timers + NTP intact.

---

## What was wrong

On WLED 0.15.1 a `POST /json/cfg` that omits `light.gc` resets `gammaCorrectCol`/`gammaCorrectBri` to false and `serializeConfig()` persists that to `cfg.json` on LittleFS — it survives reboot. `gc.val` is preserved by a separate firmware path, so the readback signature is `col: 2.8 → 1` with `val` still `2.8`.

This is a **firmware deserialiser defect**. The app cannot fix the firmware; it can stop handing it a payload that triggers it. All eight of Lumina's cfg writers omitted `light.gc`.

---

## Fix 1 — the chokepoint

### Is there a shared cfg payload builder, the way `normalizeWledPayload` is shared for state?

**No.** There is no cfg-side equivalent — and `normalizeWledPayload` is not itself a single builder either. It is a *normaliser applied at the write boundary*: `WledService.applyJson` ([wled_service.dart:471](../lib/features/wled/wled_service.dart#L471)) calls it immediately before `_postJson`, and `CloudRelayRepository` calls it before its own transport. That boundary placement — not a builder — is what makes the frozen-segment fix cover ~66 call sites.

So the cfg side gets the same shape. **There are exactly three network boundaries** through which a cfg payload can leave the app:

| # | Boundary | Reaches | Serves |
|---|---|---|---|
| 1 | `WledService._postConfig` — [wled_service.dart:543](../lib/features/wled/wled_service.dart#L543) | LAN HTTP | `applyConfig` (schedule sync, lease sweeps, healer, hardware screen) + `clearWifiCredentials` |
| 2 | `_postConfig` — [wled_config_pusher.dart:540](../lib/services/wled_config_pusher.dart#L540) | install-time raw HTTP | `hw.led` bus build, mDNS rename, NTP/location, gamma itself |
| 3 | `CloudRelayRepository.applyConfig` — [cloud_relay_repository.dart:437](../lib/features/wled/cloud_relay_repository.dart#L437) | webhook relay | off-LAN cfg writes (Bridge Mode already throws) |

Two, not one, because the pusher runs at install time with no repository and its own raw `HttpClient`; three because the relay is a different transport entirely. `DemoWledRepository.applyConfig` is a `debugPrint` and touches no device.

Injecting at the eight *call sites* was rejected for the reason the task states: eight sites is eight chances to forget, and the ninth writer added later inherits the bug silently. P1-51 is the standing evidence.

### The normaliser

New in [wled_payload_utils.dart](../lib/features/wled/wled_payload_utils.dart), directly above its state-side twin:

```dart
Map<String, dynamic> normalizeWledCfgPayload(Map<String, dynamic> cfg) {
  final light = cfg['light'];
  final existingGc = light is Map ? light['gc'] : null;
  if (existingGc is Map && existingGc.isNotEmpty) {
    return Map<String, dynamic>.from(cfg);   // caller is authoritative
  }
  final out = Map<String, dynamic>.from(cfg);
  final mergedLight =
      light is Map ? Map<String, dynamic>.from(light) : <String, dynamic>{};
  mergedLight['gc'] = Map<String, dynamic>.from(kNglLightGammaConfig);
  out['light'] = mergedLight;
  return out;
}
```

Three properties that matter:

- **Merges one level into `light`.** Bench Test B proved `{"light":{"scale-bri":100}}` wipes gamma just as thoroughly as a payload with no `light` key — a partial `light` object is not protection. Other `light.*` keys are preserved.
- **Non-destructive.** A caller that supplies `light.gc` passes through untouched. That is how `pushGammaConfig`'s own payload keeps working, and how a future user-facing gamma control stays writable.
- **Does not mutate the caller's map.**

### On `kNglLightGammaConfig` — one definition, moved

The task asked to reuse the canonical value rather than create a second one. That required **moving** it, because of the import graph:

```
wled_config_pusher  →  wled_service  →  wled_payload_utils
```

Defining the normaliser in the pusher and importing it back from `wled_service` would close a cycle. So the constant now lives in `wled_payload_utils.dart` alongside the function that needs it, and `wled_config_pusher.dart` **re-exports** it:

```dart
export 'package:nexgen_command/features/wled/wled_payload_utils.dart'
    show kNglLightGammaConfig;
```

Still one definition. Every existing importer of `wled_config_pusher` resolves it unchanged — no call-site churn.

### Wiring

| Boundary | Change |
|---|---|
| [wled_service.dart:543](../lib/features/wled/wled_service.dart#L543) | `data = normalizeWledCfgPayload(data);` — before the `_simulate` branch, so tests observe the real wire payload |
| [wled_config_pusher.dart:540](../lib/services/wled_config_pusher.dart#L540) | same, first statement in the `try` |
| [cloud_relay_repository.dart:445](../lib/features/wled/cloud_relay_repository.dart#L445) | `_executeBool('applyConfig', normalizeWledCfgPayload(cfg))` |

The relay one matters most for severity: `GammaWatchdog` and the defaults healer are both LAN-only, so an off-LAN cfg write that wiped gamma went **unrepaired until the phone came home**.

---

## Fix 2 — healer ordering and reporting

Two independent defects at [controller_defaults_healer.dart](../lib/features/wled/controller_defaults_healer.dart).

### Ordering

Gamma ran at step (d), *before* the AudioReactive cfg POST at step (e) — which wiped it. The healer undid its own work on every run where AR needed healing.

Step order is now **(a) ntp-host → (b) tz → (c) coords → (d) audioreactive → (e) ON-preset master power → (f) GAMMA → (g) reboot**. Gamma is the last cfg write, and deliberately *before* the reboot: (g) may POST `{'rb':true}`, and a cfg write racing a reboot is not guaranteed to reach flash. The file-header comment now records the order and why it must not be changed.

Fix 1 makes this moot mechanically. It is kept because "assert the invariant after every write that could disturb it" is correct regardless, and it stops the next cfg writer added above from reopening the hole if the chokepoint is ever bypassed.

### Reporting — the defect class, independent of this bug

```dart
if (g.success && !g.noChange) report.gammaHealed = true;   // OLD
```

`WledConfigPushResult.warning` carries `success: true` ([wled_config_pusher.dart:37](../lib/services/wled_config_pusher.dart#L37)), and `pushGammaConfig` returns a warning precisely when its **readback disagrees**. So the flag was set true on a run that had just failed to confirm the write — asserting an outcome it could not verify. A hard failure (`success:false`) was swallowed entirely and logged nothing at all.

Now three outcomes with three meanings, `noChange` tested first because `skipped()` *also* carries a warning ("already correct") and a healthy device must stay silent:

```dart
if (g.noChange) {
  // already correct — the healthy path, zero writes, zero log
} else if (g.success && g.warnings.isEmpty) {
  report.gammaHealed = true;                       // VERIFIED
} else if (g.success) {
  report.log.add('gamma heal unverified: ...');    // wrote, readback disagreed
} else {
  report.log.add('gamma heal failed: ...');        // was silently swallowed
}
```

`gammaHealed` now means *verified healed*, not *the POST returned 2xx*.

---

## Fix 3 — the dead `loc` write, deleted

[edit_profile_screen.dart:221](../lib/features/site/edit_profile_screen.dart) POSTed `{'loc':{'lat','lon'}}`. `loc` is not a WLED cfg key — coordinates live at `if.ntp.lt`/`ln`. The write never set coordinates, on LAN or off; its only effect was triggering the cfg deserialiser and wiping gamma. Pure loss (F-8, already logged; the in-file `FIXME(coords)` had documented it as a known no-op).

Deleted along with its now-dead `repoCanWriteCfg` / repository plumbing and two orphaned imports. Nothing replaces it — the on-connect healer's `coordHealPayload()` writes the correct `if.ntp` path and always has, so this **restores intended behaviour rather than removing a capability**.

---

## Rig verification

`scripts/_verify_gamma_chokepoint.dart` — a hardware harness that drives the **real `WledService` boundary**, not a mock. Every assertion reads `/cfg.json`, the LittleFS **file**, not `/json/cfg` (the live serialise); the defect persists to flash, so the file is the only readback that proves durability. Every payload is written with the device's own current values, so a pass leaves the controller functionally untouched.

```
flutter test scripts/_verify_gamma_chokepoint.dart --dart-define=RIG=192.168.1.150
```

```
RIG 192.168.1.150 — baseline light.gc = {"bri":1,"col":2.8,"val":2.8}
+1: 0. PRE-STATE — colour gamma is ON before we start
+2: 1. the DEFECT still exists in firmware (raw POST, app bypassed)
+3: 2. schedule sync through WledService.applyConfig KEEPS gamma
+4: 3. the timers actually landed — no cfg regression
+5: 4. lease-sweep shaped write KEEPS gamma
+6: 5. NTP + coords writes KEEP gamma and still land
+7: 6. AudioReactive heal payload KEEPS gamma (the healer self-wipe)
+8: 7. FULL HEALER RUN with AudioReactive ENABLED — gamma survives
        healer report: audioReactiveHealed=true gammaHealed=false rebooted=false log=[]
+9: 8. FINAL — rig left healthy
        FINAL /cfg.json light.gc = {"bri":1,"col":2.8,"val":2.8}
All tests passed!
```

Against the task's five checks:

1. **Pre-state** — test 0: `col:2.8` before anything runs.
2. **Real schedule sync, `/cfg.json` FILE readback** — test 2. This is the test that failed before. Gamma goes in *wiped* (test 1 leaves it that way), so it proves the injection both **preserves and repairs**.
3. **Lease sweep + healer run with AR enabled** — tests 4 and 7. Test 7 enables AudioReactive, wipes gamma, then runs the **real `ControllerDefaultsHealer`** and confirms it disables AR *and* leaves gamma ON.
4. **Visual rendering** — see "Outstanding" below.
5. **No cfg regression** — test 3 asserts all four timer rows land with matching `hour`/`min`/`macro`/`dow`; test 5 asserts `lt`/`ln` land and `tz`/`host` are untouched; test 8 asserts the final timer count, `no-gc:false` and AR off.

### Test 1 is the control

It POSTs raw, bypassing the app, and **asserts gamma still gets wiped**. Without it the suite could pass on a firmware that had been patched, proving nothing. If test 1 ever fails, the firmware changed and this fix can be revisited.

### One result worth reading carefully

Test 7 reports `gammaHealed=false` — and that is the **correct post-fix outcome, not a miss**. Gamma went into that run wiped. The AR heal at step (d) now carries `light.gc` through the chokepoint, so it repaired gamma *on its way past*; by the time step (f) evaluated, the device was already correct and `pushGammaConfig` skipped (`noChange` → not "healed").

Pre-fix, that same run ended with gamma **OFF** and `gammaHealed` **TRUE**. That inversion — the flag asserting the opposite of the device state — is exactly what fixes 1 and 2 together eliminate. My first draft of the assertion expected `true` and failed; the code was right and the assertion was wrong.

### A note on the harness

Early runs failed with `FormatException: Unexpected end of input` on `/cfg.json`. Not a gamma result: a cfg POST triggers a LittleFS flash save, and while that is in flight the controller answers GETs with an **empty body** — the same post-commit stall `schedule_sync` already models. The harness now settles 1500 ms after every write and retries an empty read up to 5×, and distinguishes that failure from a gamma failure in its message.

---

## Regression coverage

`test/features/wled/gamma_cfg_chokepoint_test.dart` — 11 unit tests, no hardware:

- each real writer's payload shape (timers, `if.ntp` tz, `if.ntp` coords, `um.AudioReactive`, `hw.led`) gains `light.gc` while its own content survives
- an explicit `light.gc` passes through unchanged (caller authoritative)
- a partial `light` object keeps its other keys and gains `gc` (Bench Test B)
- an empty `gc` map counts as absent; empty payload still asserts gamma; caller's map not mutated
- the asserted value equals `kNglLightGammaConfig`, and `col` is never `1` — the exact value the firmware defect writes

---

## Test results

| | |
|---|---|
| `flutter analyze lib/` | **0 errors, 0 warnings.** 375 pre-existing `info` lints, none in touched files |
| `flutter test` | **1945 passed, 3 skipped, 1 failed** |
| Failure | `cloud_ai_processor_normalize_test` — the known stale test (`Expected: 'Sunset' / Actual: ''`). Pre-existing, unrelated, expected |
| Rig | **9/9** |

One test needed adjusting during the work: `controller_defaults_healer_test` → *"audioreactive heal (LAN) ENABLED → exactly one surgical POST"* asserts an empty report log for a healthy device. My first reporting fix logged "gamma heal unverified: already correct" on a healthy **skip**, because `skipped()` carries a warning too. Fixed by testing `noChange` first — the test was right.

---

## Files changed

```
lib/features/wled/wled_payload_utils.dart         +68   normalizeWledCfgPayload + kNglLightGammaConfig (moved)
lib/features/wled/wled_service.dart                +7   boundary 1
lib/services/wled_config_pusher.dart              ~30   boundary 2, constant moved + re-exported
lib/features/wled/cloud_relay_repository.dart      +6   boundary 3
lib/features/wled/controller_defaults_healer.dart +73   ordering (f) + verified reporting
lib/features/site/edit_profile_screen.dart        -31   dead loc write removed
test/features/wled/gamma_cfg_chokepoint_test.dart  new  11 regression tests
scripts/_verify_gamma_chokepoint.dart              new  hardware harness (not in the unit suite)
```

---

## Outstanding

**Visual confirmation on the strip is Tyler's to make** — I can verify the flag on flash, not the render. The signature to look for is the one from the original gamma fix: a saturated orange (`[255,160,0,0]`) reads **vivid** with gamma on and **washed amber** with it off. Toggling `light.gc.col` in WLED's own LED-preferences page snaps between the two. Everything else in the five-point checklist is verified above.

**Not addressed (out of scope, worth logging):**

- `_healAudioReactive`'s post-write readback can log *"readback: audioreactive still enabled"* when it reads back too fast — AR takes effect on the controller's next `loop()`. Cosmetic log noise, pre-existing, unrelated to gamma. Seen once during these runs; the device was correctly disabled.
- The **`GammaWatchdog` is now expected to be silent.** It shipped (`29198bc`) to mitigate an assumed device-side revert and was in fact masking this app-side one. Its `correctiveWrites` counter should sit at **0** on a healthy board from here. If it starts incrementing in the field again, there is a *fourth* cfg boundary that bypasses the chokepoint — that counter is now a live regression detector, and worth watching rather than removing.
