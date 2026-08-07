# GAMMA_BUG — colour gamma flips OFF durably on any `/json/cfg` write

**Date:** 2026-08-07 · **Rig:** `.150` (`Kōsen`, WLED **0.15.1**, vid 2507300, ESP32_Ethernet, mac `80f3daae6f04`)
**App under observation:** 2.5.10+64 · **Status:** ROOT CAUSE FOUND, bench-reproduced 4× · **Read-only — no fix applied**
**Rig left restored:** `light.gc = {"bri":1,"col":2.8,"val":2.8}`, `if.live.no-gc = false` (verified against the LittleFS file, last line of §5)

---

## TL;DR

It has nothing to do with effects.

**Any `POST /json/cfg` whose body omits `light.gc` silently resets colour gamma to OFF on WLED 0.15.1**, and the reset is written straight through to `cfg.json` on LittleFS — it survives reboot. Every one of Lumina's eight cfg writers omits `light.gc`.

Applying an effect/design does *not* do it (that path is `/json/state`, proven safe). What the user is actually watching is the **`GammaWatchdog`'s 2-minute repair cycle** racing the app's own cfg writes. Check the toggle inside the window → OFF. Check after the next tick → ON. That reads as "varies by effect, intermittent" but the correlation is with *timing*, not with the effect.

There is also a **self-defeating ordering defect inside the healer**: it asserts gamma at step (d), then performs an AudioReactive cfg POST at step (e) that wipes the gamma it just set.

---

## 1. Where gamma lives — confirmed on the rig, not inferred

`GET http://192.168.1.150/cfg.json`:

```json
"light": {"scale-bri":100,"pal-mode":0,"aseg":false,
          "gc":{"bri":1,"col":2.8,"val":2.8},
          "tr":{...},"nl":{...}}
```

**Path: `cfg.light.gc`.** Three fields.

`hw.led` is *not* involved. Its complete key set on this firmware — no `gc` anywhere:

```
total, maxpwr, ledma, cct, cr, ic, cb, fps, rgbwm, ld, prl, ins
```

`def` is `{"ps":0,"on":true,"bri":128}` — also not involved.

### Field encoding (this is what makes the bug legible)

| Field | Meaning | OFF | ON |
|---|---|---|---|
| `gc.bri` | brightness-gamma | `1` | `2.8` |
| `gc.col` | **colour-gamma — the toggle Tyler is watching** | `1` | `2.8` |
| `gc.val` | raw exponent, stored independently | `2.8` | `2.8` |

`bri` and `col` are *not* booleans — they are "exponent-or-1" flags. `1` means the correction is disabled. WLED's LED-preferences checkbox "Color gamma correction" is exactly `light.gc.col > 1`.

The rig's healthy baseline is `bri:1` (brightness-gamma intentionally off) / `col:2.8` (colour-gamma on) — which matches `kNglLightGammaConfig` in [wled_config_pusher.dart:433](lib/services/wled_config_pusher.dart#L433).

**The observed failure is `col: 2.8 → 1`, with `val` left at `2.8`.** That asymmetry is the fingerprint: `val` surviving while `col` resets proves the firmware is *recomputing the flags from an absent `light.gc` object* on every cfg deserialise, not resetting the block wholesale.

---

## 2. Who writes it

### The only writer that sets gamma correctly

[`lib/services/wled_config_pusher.dart`](lib/services/wled_config_pusher.dart) — one function, two callers.

```dart
// :433  buildGammaPayload()
{'light': {'gc': {'bri':1, 'col':2.8, 'val':2.8}},
 'if': {'live': {'no-gc': false}}}
```

`pushGammaConfig()` ([:473](lib/services/wled_config_pusher.dart#L473)) reads `/json/cfg` first and **skips the POST** when `gammaConfigSatisfied()` ([:444](lib/services/wled_config_pusher.dart#L444)) passes — `col≈2.8 && bri≈1 && val≈2.8 && no-gc==false`, 1e-3 epsilon. Then readback-verifies `col` with one 300 ms retry.

Its two callers:

| Caller | Cadence | Scope |
|---|---|---|
| `ControllerDefaultsHealer` step (d) — [controller_defaults_healer.dart:435](lib/features/wled/controller_defaults_healer.dart#L435) | once per **new controller connect** | LAN only |
| `GammaWatchdog` — [controller_defaults_healer.dart:762](lib/features/wled/controller_defaults_healer.dart#L762), started at [wled_providers.dart:528](lib/features/wled/wled_providers.dart#L528) | `Timer.periodic`, **2 min** (`kGammaWatchdogInterval`, floored at 60 s) | LAN only; no-ops off-LAN |

Value asserted: `{bri:1, col:2.8, val:2.8}` + `no-gc:false`, unconditionally, whenever the readback gate fails.

### Every writer that DESTROYS it

Complete census of `applyConfig(...)` call sites in `lib/`. **None of the eight carries a `light` key**, so every one of them wipes `gc.col`:

| # | Call site | Payload top-level | Fires when |
|---|---|---|---|
| 1 | [schedule_sync.dart:208](lib/features/schedule/schedule_sync.dart#L208) / [:264](lib/features/schedule/schedule_sync.dart#L264) | `{'timers':{'ins':[…]}}` — built at [cfg_payload_builder.dart:196](lib/features/schedule/cfg_payload_builder.dart#L196), assembled at [schedule_sync.dart:1298](lib/features/schedule/schedule_sync.dart#L1298) | **every schedule mutation**, 800 ms debounce ([schedule_providers.dart:165](lib/features/schedule/schedule_providers.dart#L165)) + manual Sync |
| 2 | [calendar_entry_lease_manager.dart:1213](lib/features/schedule/calendar_entry_lease_manager.dart#L1213) | `{'timers':…}` | lease arm/clear sweeps — **unattended** |
| 3 | healer (a) [:395](lib/features/wled/controller_defaults_healer.dart#L395) | `{'if':{'ntp':{'host','en'}}}` | NTP host broken |
| 4 | healer (b) [:408](lib/features/wled/controller_defaults_healer.dart#L408) | `{'if':{'ntp':{'tz'}}}` | tz is UTC |
| 5 | healer (c) [:427](lib/features/wled/controller_defaults_healer.dart#L427) | `{'if':{'ntp':{'lt','ln'}}}` | coords 0,0 |
| 6 | healer (e) [:615](lib/features/wled/controller_defaults_healer.dart#L615) | `{'um':{'AudioReactive':{'enabled':false}}}` | AR enabled — **runs AFTER gamma step (d)** |
| 7 | [hardware_config_screen.dart:300](lib/features/wled/hardware_config_screen.dart#L300) / [:358](lib/features/wled/hardware_config_screen.dart#L358) | `{'hw':{'led':{'total','maxpwr','ins'}}}` | installer LED/bus setup |
| 8 | [edit_profile_screen.dart:221](lib/features/site/edit_profile_screen.dart#L221) | `{'loc':{'lat','lon'}}` | profile address save |

Two of these deserve a note in their own right:

- **#6 is self-defeating.** The healer sets gamma at (d), then at (e) POSTs the AudioReactive payload — which wipes it. One healer run leaves the controller with gamma OFF whenever AR needed healing. The step-(d) comment even claims the ordering is safe.
- **#8 is pure loss.** `loc` is not a WLED cfg key — location lives at `if.ntp.lt`/`ln`. That write accomplishes nothing at all *except* wiping gamma.

### Paths that DO NOT write gamma (checked, cleared)

- **Design Studio** — `applyBaseAndSpans` ([design_apply.dart:25](lib/features/design/manual_editor/design_apply.dart#L25)), `_apply`, live preview. `grep` for `applyConfig|hw'\]|'ins'|buildLedConfig` across all of `lib/features/design/` returns **zero hits**. State-only.
- **Colour picker / effect selection / quick presets** — [colorway_effect_selector.dart:445](lib/features/wled/colorway_effect_selector.dart#L445): the selection-mode exit does `applyJson` preview + `_restoreCapturedLook()`. `/json/state` only.
- **Schedule pattern picker** — [my_schedule_page.dart:4269](lib/features/schedule/my_schedule_page.dart#L4269) `onDesignSelected` only does `setState`. No device write on selection. *(But saving the schedule entry afterwards trips writer #1.)*

---

## 3. Is it captured by `psave`? — **No.** Not the frozen-segment class.

Gamma is **config** (`cfg.json` / `serializeConfig`); presets are **state** (`presets.json` / `serializeState`). They cannot cross. Bench-proven:

```
POST /json/state {"psave":42,"n":"gammatest"}   → gc = {"bri":1,"col":2.8,"val":2.8}   (unchanged)
```

So the `frz:true` failure mode — *a preset saved during a bad window fires dark forever* — **does not apply**. Loading any preset cannot restore `gamma:off`, and no preset needs re-saving.

**But the damage is durable by a different route**, and it is just as permanent:

`POST /json/cfg` calls `serializeConfig()`, which writes LittleFS immediately. I verified this by reading `/cfg.json` — the **file**, not the `/json/cfg` live serialise:

```
FILE /cfg.json  light.gc: {"bri":1,"col":1,"val":2.8}
```

The wipe is on flash. It survives reboot, power cycle, and every preset load. Only an explicit `light.gc` write repairs it.

---

## 4. Why does it vary by effect? — **It doesn't.**

This was the load-bearing clue and it points somewhere other than where it appears to.

The effect-apply path is `/json/state` and is provably immune (§5, Test D). No builder, no segment shape, no "fuller payload" variant reaches `/json/cfg`. Design Studio has no cfg write at all.

What actually varies is **timing against the `GammaWatchdog`**:

```
t+0s     user action trips a cfg write (schedule save, lease sweep, healer, profile save)
         → light.gc.col : 2.8 → 1        [gamma OFF, on flash]
t+0-120s user opens the WLED UI  → toggle reads OFF   ← "this effect broke it"
t+≤120s  GammaWatchdog tick → readback fails → corrective POST
         → light.gc.col : 1 → 2.8        [gamma ON]
t+120s+  user opens the WLED UI  → toggle reads ON    ← "this effect is fine"
```

Same effect, either observation, depending purely on where in the 2-minute cycle you looked. Two independent sources of jitter stack on top:

1. **Which actions write cfg is invisible from the UI.** Selecting a pattern is free; *saving* the schedule that contains it costs a cfg write 800 ms later. Lease sweeps (#2) fire unattended with no user action at all.
2. **The watchdog is LAN-only.** `tickOnce()` returns immediately when `_lanIp()` is null. Off-LAN there is no repair.

The "some effects and not others" observation is real, but it is an artifact of the observation window — not a property of the effects.

---

## 5. Deliberate reproduction — verbatim

All on `.150`, 2026-08-07. Every payload chosen to be functionally inert (identical values re-written) so the *only* variable is the shape of the cfg body.

### Test A — cfg POST with **no `light` key** (healer's coord/tz shape, writer #3–5)

```
PAYLOAD  POST /json/cfg
         {"if":{"ntp":{"tz":5,"lt":38.99346,"ln":-94.2527}}}
RESPONSE {"success":true}

BEFORE   light.gc = {"bri":1,"col":2.8,"val":2.8}
AFTER    light.gc = {"bri":1,"col":1,"val":2.8}      ← WIPED
         if.live.no-gc = false                       ← untouched
```

### Test A′ — durability (read the LittleFS **file**, not the live serialise)

```
GET /cfg.json  →  light.gc = {"bri":1,"col":1,"val":2.8}     ← persisted to flash
```

### Test B — cfg POST with `light` present but `gc` absent

```
PAYLOAD  {"light":{"scale-bri":100}}
RESPONSE {"success":true}
BEFORE   light.gc = {"bri":1,"col":2.8,"val":2.8}
AFTER    light.gc = {"bri":1,"col":1,"val":2.8}      ← WIPED
```

The trigger is the **absence of `light.gc`**, not the absence of `light`. Nesting a partial `light` object does not protect it.

### Test C — the real schedule-sync payload ([schedule_sync.dart:1298](lib/features/schedule/schedule_sync.dart#L1298) shape, writer #1)

```
PAYLOAD  {"timers":{"ins":[
           {"en":1,"hour":20,"min":49,"macro":10,"dow":127,"start":{"mon":1,"day":1},"end":{"mon":12,"day":31}},
           {"en":1,"hour":18,"min":0, "macro":33,"dow":8,  "start":{"mon":1,"day":1},"end":{"mon":12,"day":31}},
           {"en":1,"hour":18,"min":40,"macro":29,"dow":16, "start":{"mon":1,"day":1},"end":{"mon":12,"day":31}},
           {"en":1,"hour":255,"min":0,"macro":2, "dow":127}]}}
RESPONSE {"success":true}

BEFORE   light.gc = {"bri":1,"col":2.8,"val":2.8}
AFTER    light.gc = {"bri":1,"col":1,"val":2.8}      ← WIPED
```

Timers identical to what was already on the device. **A no-op schedule sync still destroys gamma.**

### Test D — effect apply via `/json/state` (the path the report blamed)

```
PAYLOAD  POST /json/state {"seg":[{"id":0,"fx":57,"sx":128,"ix":128,"pal":5}]}
BEFORE   light.gc = {"bri":1,"col":2.8,"val":2.8}
AFTER    light.gc = {"bri":1,"col":2.8,"val":2.8}    ← SAFE
```

### Test E — `psave`

```
PAYLOAD  POST /json/state {"psave":42,"n":"gammatest"}
BEFORE   light.gc = {"bri":1,"col":2.8,"val":2.8}
AFTER    light.gc = {"bri":1,"col":2.8,"val":2.8}    ← SAFE
```
*(scratch preset 42 subsequently deleted via `{"pdel":42}`)*

### Test F — repair via the app's own payload ([wled_config_pusher.dart:433](lib/services/wled_config_pusher.dart#L433))

```
PAYLOAD  {"light":{"gc":{"bri":1,"col":2.8,"val":2.8}},"if":{"live":{"no-gc":false}}}
BEFORE   light.gc = {"bri":1,"col":1,"val":2.8}
AFTER    light.gc = {"bri":1,"col":2.8,"val":2.8}    ← REPAIRED
```

### Result matrix

| Write | `light.gc` present? | `gc.col` after |
|---|---|---|
| `POST /json/cfg {"if":{"ntp":…}}` | no | **2.8 → 1** |
| `POST /json/cfg {"light":{"scale-bri":100}}` | no | **2.8 → 1** |
| `POST /json/cfg {"timers":{"ins":[…]}}` | no | **2.8 → 1** |
| `POST /json/cfg {"light":{"gc":…},…}` | yes | 1 → 2.8 |
| `POST /json/state {seg:[{fx…}]}` | n/a | 2.8 (unchanged) |
| `POST /json/state {"psave":42}` | n/a | 2.8 (unchanged) |
| `GET /json/cfg`, `GET /cfg.json` | n/a | 2.8 (unchanged) |

**The rule is exact: on WLED 0.15.1, a `/json/cfg` POST that omits `light.gc` sets `gammaCorrectCol`/`gammaCorrectBri` false and persists it. `gc.val` is preserved by a separate code path, which is why the exponent survives while the flags don't.**

Contrast with `if.live.no-gc`, which held `false` across every wipe — it is deep-merged normally. So this is a defect specific to the `light.gc` deserialiser, not general cfg behaviour, and the pusher's comment at [wled_config_pusher.dart:426](lib/services/wled_config_pusher.dart#L426) — *"WLED deep-merges individual cfg keys"* — is true for every key **except** this one.

---

## 6. Does the healer fix it? How long is a customer dark?

**Yes, both repair paths work** (Test F is exactly what they POST). But coverage is uneven and one of them shoots itself.

| Condition | Time with gamma OFF |
|---|---|
| On LAN, dashboard alive (`WledNotifier` mounted) | **≤ 120 s** per incident, watchdog tick |
| On LAN, healer runs and AR needs healing | **wiped again immediately by step (e)** — persists to the next watchdog tick |
| Off LAN (bridge/relay) | **UNBOUNDED.** `tickOnce()` no-ops without a LAN IP; healer is LAN-only. Cfg writes still land via webhook mode. Nothing repairs it until the phone comes home. |
| App backgrounded / `WledNotifier` disposed | **UNBOUNDED.** `ref.onDispose` stops the watchdog ([wled_providers.dart:539](lib/features/wled/wled_providers.dart#L539)). |
| App never opened again | **UNBOUNDED.** State is on flash; nothing device-side self-heals. |

The healer ordering defect, concretely:

```
(d) :435  pushGammaConfig  → light.gc.col = 2.8   ✅
(e) :615  {"um":{"AudioReactive":{"enabled":false}}}  → light.gc.col = 1   ❌  wiped
(f) :465  optional reboot
```

`report.gammaHealed` is set true at step (d) and never re-checked, so **the healer reports a successful gamma heal on a run that ends with gamma off**. This is the "success reported for work not done" shape already catalogued elsewhere in this codebase.

### Severity

**High, but not catastrophic — and materially better than the `frz` class.**

- The visible harm is the washed/amber render documented in `project_gamma_light_gc_fix` — every colour renders wrong, on every effect, until repair. Not dark, not dead; wrong.
- It is **self-limiting on LAN** at ≤2 min, which is why it took this long to characterise and why it presents as intermittent.
- It is **not self-limiting off-LAN or in the background**, and it is on flash, so a customer who edits a schedule from work can sit with wrong colour indefinitely.
- **No preset poisoning.** Unlike `frz`, nothing needs re-saving and no stored artifact carries the defect forward. Repair is one POST.
- Every controller in the fleet is exposed: schedule sync (#1) and lease sweeps (#2) are the highest-frequency cfg writers and both run without user awareness.

The `GammaWatchdog` shipped in `29198bc` was written as a mitigation for an assumed *device-side* revert. It is in fact masking an **app-side** one — which is why the healthy-board write count was never zero in the field, and why the revert always looked "action-driven, after a few uses."

---

## Open thread (not chased — read-only)

`project_gamma_revert_open_seg_gc_phantom` recorded the leading hypothesis as *LittleFS wear triggering a firmware-side cfg reset*. That hypothesis is now **superseded** — this mechanism explains action-driven timing, the exact `col`-only field signature, and flash persistence, with no wear involved. Worth updating that memory once a fix lands.

---

## Appendix — rig baseline

```
/json/info : ver 0.15.1 · vid 2507300 · ESP32_Ethernet · Kōsen · mac 80f3daae6f04
             leds.count 290 · seglc [3,3] · rgbw true · wv 2 · fxcount 187 · palcount 71
/cfg.json  : light.gc     {"bri":1,"col":2.8,"val":2.8}
             if.live.no-gc false
             if.ntp       {"en":true,"host":"time.google.com","tz":5,"offset":0,
                           "ln":-94.2527,"lt":38.99346}
             hw.led keys  total maxpwr ledma cct cr ic cb fps rgbwm ld prl ins   (no gc)
             def          {"ps":0,"on":true,"bri":128}
```
