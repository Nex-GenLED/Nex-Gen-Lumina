# U-6 — DOES WLED 0.15.1 PRESERVE PER-SEGMENT `on:false` THROUGH `psave`?

# **PRESERVED.**

Stored **and** applied, in both psave variants. A preset saved with a segment
off restores that segment to off when loaded onto a strip where it is currently
lit — colour, bounds and all.

---

**Date:** 2026-08-24 · **Controller:** `192.168.1.150` · **Firmware:** WLED
`0.15.1`, `vid 2507300`, `ESP32_Ethernet`, core `v3.3.6-16-gcc5440f6a2`
**Hardware:** 290 LEDs, RGBW (`wv:2`), 2 segments (`seglc:[3,3]`), `maxseg:32`
**Scope:** read/POST `/json/state` + `/presets.json` only. No app code, no
`/json/cfg`, no reboot. Scratch preset slot **250** (verified empty first,
deleted after).

This closes **U-6** in [SCHEDULING_V3_AUDIT.md §9](SCHEDULING_V3_AUDIT.md) —
filed there as "not determinable from the repo… F2 needs a bench answer before
a design commits."

---

## C1 — Baseline captured

```
/json/info   ver 0.15.1 · vid 2507300 · count 290 · rgbw true · maxseg 32
/json/state  on=true bri=128 ps=-1 transition=7
             seg 0  [0,128)   on=true  bri=255 fx=0 col0=[0,70,135,0]  frz=false
             seg 1  [128,290) on=true  bri=255 fx=0 col0=[0,70,135,0]  frz=false
/presets.json  slots in use: 1 2 3 4 5 10 11 26 27 28 29 30 31 33 36 37 38 40 41 160
               slot 250: null  ← free, safe to use as scratch
```

Both segments lit, no freeze anywhere — a clean starting point, and the strip
was not mid-design.

## C2 — psave with seg[1] off

```json
POST /json/state
{"on":true,"bri":128,
 "seg":[{"id":0,"on":true,"fx":0,"col":[[255,0,0,0]]},
        {"id":1,"on":false}],
 "psave":250,"n":"U6_PROBE"}
→ {"success":true}
```

Live state immediately after — the psave applied inline, as this firmware does:

```
seg 0  on=true   col0=[255,0,0,0]
seg 1  on=false  col0=[0,70,135,0]
```

## C3 — What preset 250 actually stored

**`"on": false` is PRESENT on seg[1].** Not absent, not dropped, not coerced.

```json
{ "mainseg": 0,
  "seg": [
    { "id":0, "on":true,  "frz":false, "bri":255, "col":[[255,0,0,0],…], "fx":0, … },
    { "id":1, "on":false, "frz":false, "bri":255, "col":[[0,70,135,0],…], "fx":0, … }
  ],
  "n": "U6_PROBE" }
```

Two details worth recording alongside the answer:

- **No root `on` / `bri`.** Expected: `ib` was not set, and this firmware only
  persists root master state when asked. This is the same mechanism behind the
  ON-ladder defect (`memory/project_schedule_preset_ib_master`), and it is
  orthogonal to the per-segment question.
- **`frz:false` was captured** on both segments. Worth noting because a `psave`
  that captures `frz:true` produces a preset that fires dark forever
  ([FROZEN_SEGMENT.md](FROZEN_SEGMENT.md)); nothing in this probe went near a
  per-pixel `i` write, so the hazard did not arise.

## C4 — Does loading it re-apply the off?

Forced the opposite state first, so a no-op could not masquerade as a pass:

```
POST all segments on, green
  seg 0 on=true   col0=[0,255,0,0]
  seg 1 on=true   col0=[0,255,0,0]

POST {"ps":250}
  master on=true bri=128
  seg 0 on=true   col0=[255,0,0,0]
  seg 1 on=false  col0=[0,70,135,0]   ← WENT BACK OFF
```

**seg[1] transitioned lit → off purely from the preset load.** That is the
answer: the off state is not merely stored, it is *asserted* on load.

## C5 — Repeat with `ib:true` + `sb:true`

```json
POST … {"on":true,"bri":200,
        "seg":[{"id":0,"on":true,"col":[[255,0,255,0]]},{"id":1,"on":false}],
        "psave":250,"n":"U6_PROBE_IB","ib":true,"sb":true}
```

Stored:

```
root on=true  root bri=200            ← ib:true persists master state
seg 0 on=true  start=0   stop=128     ← sb:true persists bounds
seg 1 on=false start=128 stop=290
+ 30 empty segment stubs (padded to maxseg=32)
```

Loaded from all-on/green:

```
master on=true bri=200                ← root brightness APPLIED (was 128)
seg 0 on=true   start=0   stop=128 col0=[255,0,255,0]
seg 1 on=false  start=128 stop=290 col0=[0,70,135,0]
```

**Differences from C2–C4:**

| | plain `psave` | `+ ib:true, sb:true` |
|---|---|---|
| seg `on:false` stored | ✅ | ✅ |
| seg `on:false` applied on load | ✅ | ✅ |
| root `on`/`bri` stored | ❌ absent | ✅ `on:true bri:200` |
| `start`/`stop` stored | ❌ | ✅ |
| segment array padded to `maxseg` | ❌ (2 entries) | ✅ (32 entries) |

`ib`/`sb` change what *else* rides along; **they do not change the per-segment
`on` behaviour at all.**

## C6 — Cleanup verified

```
POST {"pdel":250}                      → {"success":true}
POST <C1 state restored explicitly>    → {"success":true}

/json/state   on=true bri=128 ps=-1
              seg 0 [0,128)   on=true bri=255 fx=0 col0=[0,70,135,0]
              seg 1 [128,290) on=true bri=255 fx=0 col0=[0,70,135,0]
/presets.json 250 = null
              slots: 1 2 3 4 5 10 11 26 27 28 29 30 31 33 36 37 38 40 41 160
```

Byte-identical to C1, and all 20 pre-existing presets untouched. The rig is
back where it started.

---

## WHAT THIS MEANS FOR F2 (per-channel scheduling)

**The firmware was never the blocker.** The audit's F2-2 read:

> A WLED timer fires ONE preset, and every system preset is FULL-STRIP by
> construction.

The second half is a statement about **Lumina's preset builders**, not about
WLED — and the probe shows the firmware would faithfully carry a channel-scoped
preset if one were written. So a channel-scoped timer is mechanically possible
today.

**The blocker is entirely app-side, and it is F2-3, which this probe does not
touch:**

- `_fullStripOnSegments` builds every ON-ladder preset with every live segment
  forced `on:true` (`schedule_sync.dart:1871`), and
- `_presetAllSegmentsOn` treats any segment not `on:true` as **damage**, so
  `psaveIfChanged` **overwrites** a channel-excluded preset on the next connect
  (`schedule_sync.dart:1889`).

That is deliberate and documented — `schedule_sync.dart:464-470` states the app
"cannot record a deliberate channel exclusion", so an all-segments-off ON preset
"is DAMAGE, never intent." **That premise is what F2 has to change.** With
`channels` now on the model (written null, consumed by nothing — Scheduling V3
A1), the healer gains a way to tell exclusion from damage, which is the
precondition the comment is really describing.

**Two things this probe did NOT establish** — do not read them into it:

1. **Whether the healer leaves a channel-scoped preset alone.** Not tested; the
   code says it would not. Testing it means exercising
   `baseLadderRepairEnabledSyncProvider` on hardware, which is a separate run.
2. **Slot arithmetic.** Preservation says nothing about capacity. Per-channel ×
   multiple-per-day still exhausts the 8 general timer slots as computed in
   [SCHEDULING_V3_AUDIT.md §7.4](SCHEDULING_V3_AUDIT.md) — at 4 channels, a
   single nightly on/off event fills the pool.
