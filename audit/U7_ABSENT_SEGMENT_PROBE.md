# U-7 — ON `{"ps":N}`, WHAT HAPPENS TO A SEGMENT THAT IS ABSENT FROM THE PRESET?

# **UNTOUCHED.**

An absent segment keeps its colour, its `on` state, its effect — everything. The
preset load writes only the segments it names.

**But the finding that actually decides D2 is a different one, discovered on the
way:**

> ## ⚠️ `psave` CANNOT PRODUCE A SEGMENT-ABSENT PRESET.
> It snapshots the controller's **full live state**, so every preset the app can
> create through `WledService.savePreset` names **every** segment — whether or
> not the caller mentions it, and whether or not it is selected.

So "leave the other channels untouched" is **unreachable through the app's
preset path**, regardless of what the firmware does with absence. D2 must scope
channels with explicit `on:false`, which [U-6](U6_PSAVE_PROBE.md) proved is
stored and asserted.

---

**Date:** 2026-08-24 · **Controller:** `192.168.1.150` · **Firmware:** WLED
`0.15.1`, `vid 2507300` · 290 LEDs, 2 segments `[0,128) [128,290)`, `maxseg 32`
**Scope:** `/json/state` + `/presets.json` reads and POSTs. One scratch preset
(250), deleted. **No preset-file upload** — see "Blocked step".

---

## 0a — Baseline, and quiescence

```
/json/info   ver 0.15.1 · vid 2507300 · live=false · lm='' · lip=''
/json/state  on=true bri=128 ps=-1
             seg 0 [0,128)   on=true bri=255 fx=0 sel=true col0=[0,70,135,0]
             seg 1 [128,290) on=true bri=255 fx=0 sel=true col0=[0,70,135,0]
```

**No app session active**, verified rather than assumed: two reads 12 s apart
with no writes from me were byte-identical on `(on, bri, ps, per-seg on/col/fx)`,
and `live:false` with empty `lm`/`lip` rules out a realtime source. A running app
polls every 1.5 s and would have shown drift.

## 0b — Distinct colours, both on

```
seg 0  on=true  col0=[255,0,0,0]     (red)
seg 1  on=true  col0=[0,0,255,0]     (blue)
```

## 0c — Attempt a seg[1]-absent preset by omission → **FAILED, and that is the finding**

First, a correction to the brief: **slot 251 does not exist.** WLED's preset
range is 1–250, and a `psave` to 251 returns `{"success":true}` and stores
**nothing** — `presets.json["251"]` was `null` afterwards. Silent no-op. The
probe moved to slot 250 (verified free).

```json
POST {"seg":[{"id":0,"col":[[255,0,255,0]]}],"psave":250,"n":"U7_PROBE"}
→ {"success":true}
```

Only seg[0] was named. What was stored:

```
PRESET 250  name=U7_PROBE  seg entries=2  with-id=2
   seg 0 on=true sel=true col0=[255,0,255,0]     ← the change I asked for
   seg 1 on=true sel=true col0=[0,0,255,0]       ← CAPTURED ANYWAY, from live state
```

**seg[1] was never mentioned and was stored regardless.** `psave` is an
apply-then-snapshot of the whole device, not a save of the submitted payload.
This is the same mechanism as the ambient-capture defect in
[BASE_LADDER.md](BASE_LADDER.md) — there it captured segments that were *off*;
here it captures segments that were merely *unmentioned*.

## 0e — Does `sel:false` exclude it? → **No**

```json
POST {"seg":[{"id":0,"sel":true,…},{"id":1,"sel":false,…}]}   // deselect seg 1
POST {"psave":250,"n":"U7_SEL"}
```

```
PRESET 250  name=U7_SEL  with-id segs=2
   seg 0 on=true sel=true  col0=[255,0,255,0]
   seg 1 on=true sel=false col0=[0,0,255,0]     ← STORED, with sel:false recorded
```

Deselection is *persisted as a field*, not honoured as an exclusion. There is no
psave flag on this firmware that drops a segment.

## 0d — The literal question, answered from presets that already lack a segment

Since `psave` cannot mint one, the probe used the **segment-absent presets
already on the rig**. Enumerating `presets.json` showed seven of them:

| Preset | Name | segs | root `on` |
|---|---|---|---|
| 2 | NGL Off | **1** (id 0) | `false` |
| 3 | NGL Dim | **1** (id 0) | `true` |
| 4 | NGL Low | **1** (id 0) | `true` |
| 5 | NGL Medium | **1** (id 0) | `true` |
| 10 | Pattern: 1 On… | **1** (id 0) | `true` |
| 11 | Kansas City Ro… | **1** (id 0) | `true` |
| 30 | Lease 2026-07-… | **1** (id 0) | absent |
| 1, 26–41, 160 | NGL On, leases, user pattern | 2 | — |

These are naturally occurring, not crafted. Three loads, each from a state where
seg[1] held a distinctive colour it could not have inherited:

**Test 1 — preset 11 (pattern, root on)**

```
before   seg 0 on=true col0=[255,0,0,0]      seg 1 on=true col0=[0,255,0,0]  (green)
{"ps":11}
after    master on=true bri=217
         seg 0 on=true col0=[0,51,160,0]     ← took the preset
         seg 1 on=true col0=[0,255,0,0]      ← UNTOUCHED, still green
```

**Test 2 — preset 30 (lease, no root on)**

```
before   seg 1 col0=[255,0,255,0]  (magenta)
{"ps":30}
after    seg 0 on=true col0=[0,70,135,0]     seg 1 on=true col0=[255,0,255,0]  ← UNTOUCHED
```

**Test 3 — preset 2, `NGL Off` (root `on:false`) — the informative one**

```
before   seg 0 on=true col0=[255,0,0,0]      seg 1 on=true col0=[0,255,0,0]
{"ps":2}
after    master on=FALSE  bri=128
         seg 0 on=false col0=[255,160,0,0]   ← named by the preset, turned off
         seg 1 on=TRUE   col0=[0,255,0,0]    ← UNTOUCHED — still ON
```

**Not reset. Not turned off. Untouched, in all three.**

### What Test 3 exposes about the shipped OFF preset

`NGL Off` darkens the house by asserting **root `on:false`**. It turns seg[0] off
explicitly and **never touches seg[1], which remains `on:true`.** The strip is
dark only because the master is off. Anything that turns the master back on —
another preset, a manual tap, `def.on` after a reboot — relights seg[1]
immediately, at whatever colour it was last holding.

That is the "partial façade" / segments-only class recorded against Ellie's
two-segment controller in `memory/project_solar_schedules_never_fire`, now
demonstrated directly on the bench. **It is not caused by this work and is not
fixed by it** — filed here because a per-channel OFF (D2) lands squarely on it.

The same shape applies to the whole Dim/Low/Medium ladder (3/4/5) and to pattern
presets 10 and 11: each names only seg[0], so on this 2-segment rig **they have
never controlled seg[1] at all.**

## 0f — Cleanup verified

```
POST {"pdel":250}                    → {"success":true}
POST <0a state restored explicitly>  → {"success":true}

/json/state   on=true bri=128 ps=-1
              seg 0 [0,128)   on=true bri=255 fx=0 sel=true col0=[0,70,135,0]
              seg 1 [128,290) on=true bri=255 fx=0 sel=true col0=[0,70,135,0]
/presets.json 250 = null
              slots: 1 2 3 4 5 10 11 26 27 28 29 30 31 33 36 37 38 40 41 160
              ladder: NGL On / NGL Off / NGL Dim / NGL Low / NGL Medium
```

Identical to 0a. All 20 pre-existing presets intact, ladder names verified.

## Blocked step, stated rather than glossed

To answer 0d by the brief's own route I would have crafted a `presets.json`
containing a genuinely seg-absent preset and uploaded it via `POST /edit`. I
took a byte-exact backup first (`sha256 f5dbad6d…`, 15 415 bytes, 20 real
presets) and built the modified file — **the upload was blocked by the sandbox
classifier.** I did not attempt to work around it.

It did not cost the answer: the seven segment-absent presets already on the
device gave three independent confirmations from reads plus ordinary preset
loads, which is *stronger* evidence than a synthetic file, because those presets
are the ones the fleet actually runs. If a future run needs the synthetic case
(e.g. a segment absent that has *never* existed in a preset), `/edit` upload
permission is the thing to grant.

---

## WHAT THIS MEANS FOR D2

**1. The "leave others untouched" semantic is unavailable to timer-fired
presets.** `buildParticipatingSegArray`'s policy — *"a patio left on by the user
stays on; the show only touches the channels the user opted in"*
([wled_payload_utils.dart:175-192](../lib/features/wled/wled_payload_utils.dart))
— works for a **live apply**, because that POSTs exactly the seg array it built.
It cannot survive a `psave`: the snapshot re-adds every segment. A channel-scoped
**timer** must therefore use `applyChannelFilter`'s semantic — target the chosen
channels, and write the rest `{id, on:false}` — which U-6 proved is stored and
asserted on load.

That is a real product decision, not just an implementation detail: **a
channel-scoped schedule will DARKEN the channels it excludes, not leave them
alone.** It should be worded that way in the editor.

**2. The OFF side needs the same treatment, and today it does not have it.**
`NGL Off` relies on master power and leaves seg[1] `on:true` (Test 3). A
channel-scoped OFF cannot use master power at all — master is global — so it has
to assert `on:false` per targeted segment and leave the others `on:true`. That is
achievable (U-6), but it is a different preset body from today's
`_fullStripOffSegments`.

**3. A channel-scoped preset needs the healer's cooperation, unchanged from the
audit.** `_presetAllSegmentsOn` treats any segment not `on:true` as damage and
re-saves it ([schedule_sync.dart:1889](../lib/features/schedule/schedule_sync.dart)).
Both U-6 and U-7 confirm the firmware would carry a channel-scoped preset
faithfully; the app is what would erase it. That is F2-3, and it is where D3
belongs.

**4. Do not build on `sel`.** It round-trips into the preset but has no
save-time effect. Anything keyed on it would look like scoping and do nothing.
