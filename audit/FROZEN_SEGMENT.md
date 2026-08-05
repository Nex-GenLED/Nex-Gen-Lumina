# FROZEN SEGMENT — blast radius audit

**Date:** 2026-08-04 · **Rig:** 192.168.1.150 (WLED 0.15.1, vid 2507300)
**Status:** AUDIT ONLY. No code changed. Rig restored (one stated deviation, §7).
**Origin:** root cause of P1-50 (undo/erase never reach the strip).

---

## 0. HEADLINE

**Confirmed:** a per-pixel write (`{"seg":[{"id":0,"i":[...]}]}`) sets `seg.frz = true`. A frozen
segment does not run its effect, so **any segment-level colour/effect write is stored and returns
200 but never renders**.

**The exposure is real but currently unrealised, and it is self-healing in the common case:**

| | |
|---|---|
| **Clears the freeze** | a **preset load** (proven: `frz true → false`), and a **reboot** |
| **Does NOT clear it** | `/json/cfg` writes; time; anything segment-level |
| **Sets it** | any per-pixel `i` write; **loading a preset that was saved while frozen** |
| **Fleet exposure today** | **ZERO accounts.** No `pixelMap` documents exist anywhere in the fleet |

**The one genuinely dangerous path** is not the editor — it is `psave`. **A preset saved while the
segment is frozen captures `frz:true` and re-freezes on every future load** (§2). Schedule sync
always-psaves pattern presets from live state, so a customer who paints and then syncs schedules
could bake a permanently-frozen preset into flash.

---

## 1. WRITE PATHS THAT WOULD SILENTLY NO-OP WHILE FROZEN

Every path that renders by setting segment colour or effect goes through `repo.applyJson(...)`.
**There are 66 `applyJson` call sites across ~30 files** outside the repository implementations.
All of them are swallowed while `frz:true`. The ones named in the brief:

| Path | Renders while frozen? | Notes |
|---|---|---|
| **Schedule / timer preset load** (macro → `ps`) | **YES — renders, and CLEARS the freeze** | Proven on hardware. This is the single most important result: schedules self-heal. **Caveat:** only if the loaded preset stored `frz:false` — see §2 |
| **Apply to Lights** (`_apply` → `applyBaseAndSpans`) | **NO — silently swallowed** | Base+spans; base is a segment-level `col` write, never sends `frz` |
| **Live preview** (`_scheduleLivePreview`) | **NO** | Same builder as `_apply` |
| **Undo / Erase** (P1-50) | **NO** | The originating symptom |
| **Quick presets / colour picker / brightness** | **NO** while frozen | Ordinary `applyJson` segment writes. Brightness (`bri`) is *root*-level, not segment — root brightness still applies, so a frozen strip still dims, which will read as "some controls work, some don't" |
| **controller_defaults_healer** | **NO** for any segment write | It writes cfg + surgical state; cfg writes proven not to clear `frz` |
| **Neighborhood Sync fanout** | **NO** | Fans out segment-level design payloads |
| **Game Day / autopilot** | **Depends** — fires via preset macros → **clears**; direct `applyJson` celebration payloads → **swallowed** | Score celebrations use direct applies, so those are the exposed half |

**Practical shape of the failure:** the app reports success everywhere (HTTP 200, state readback
shows the new `col`), the on-screen preview updates, and the LEDs do not change. **Readback cannot
detect it** — `/json/state` reports the *stored* segment colour, not what the LEDs display. Only
`frz` itself gives it away.

---

## 2. THE CRITICAL QUESTION — DOES A PRESET LOAD CLEAR `frz`? **YES**

Bench-proven, in sequence on the rig:

```
baseline                       seg0 frz=True
POST {"ps":1}            ->    seg0 frz=False      ← preset load CLEARS the freeze
per-pixel i-write        ->    seg0 frz=True       ← re-frozen
POST /json/cfg (timers)  ->    seg0 frz=True       ← cfg write does NOT clear
```

Every preset currently on the rig stores `frz:false` (presets 1-5, 26-30, 41 — all `[False, ...]`).
So **as the fleet stands, any schedule firing a macro un-freezes the strip and renders correctly.**
The Design Studio exposure is bounded to the editor session, and the next schedule boundary heals it.

### But `psave` captures the freeze — and that is the real hazard

```
freeze seg0 (i-write)          seg0 frz=True
POST {"psave":60}        ->    stored preset 60: seg.frz = [True, False]     ← CAPTURED
POST {"ps":1}            ->    seg0 frz=False                                 (cleared)
POST {"ps":61}           ->    seg0 frz=True                                  ← RE-FROZEN by load
```

A preset saved while frozen **re-freezes the segment every time it loads**, and — since a frozen
segment does not render — **cannot display its own stored colours**. It becomes a preset that
loads successfully (`ps` updates, HTTP 200) and lights nothing.

**Why this is reachable in production:** schedule sync **always** psaves pattern presets from
captured live state (the Option-A always-psave behaviour). Sequence:

1. Customer paints in Design Studio → `seg0.frz = true`.
2. Schedule sync runs → psaves pattern preset(s) from live state → **`frz:true` baked into flash**.
3. Every subsequent fire of that schedule loads a frozen segment → **schedule fires dark**, silently.
4. A reboot clears the runtime freeze but **not the poisoned preset** — the next load re-freezes.

That is the same "schedule fires dark" class this codebase has already hit twice (the `ib`/master
-power bug and the solar encoding). It is currently **unreachable in the fleet only because no
customer has per-pixel data** (§4).

*(Scratch presets 60 and 61 were deleted; preset set verified back to 1,2,3,4,5,10,26,27,28,29,30,41.)*

---

## 3. PERSISTENCE

| Event | Clears `frz`? |
|---|---|
| Time / idle | **No** — persists indefinitely |
| `/json/cfg` write (timers, config) | **No** — proven |
| Segment-level `col`/`fx` write | **No** — that is the bug |
| **Preset load** (preset stored `frz:false`) | **Yes** |
| Preset load (preset stored `frz:true`) | **No — re-freezes** |
| **Reboot / power cycle** | **Yes** — post-reboot `seg0 frz=False` |

The freeze is **runtime segment state, not config** — it does not survive a power cycle. So a
customer stuck with a *runtime* freeze is one power blip away from healing. A customer with a
*poisoned preset* is not.

### Incidental correction found while restoring

**A preset load does NOT restore the two-segment split after a reboot.** Post-reboot the rig
collapsed to one segment (0-290, `seglc [3]`), and `{"ps":1}` left it at **one** segment. Preset 1
*does* define two segment entries — but with **`start`/`stop` absent** — so it sets properties on
segments that already exist and cannot recreate bounds. My earlier note in
`project_reboot_segment_collapse` asserted presets restore the split; **that was inference and it is
wrong.** Restoring the split required an explicit
`{"seg":[{"id":0,"start":0,"stop":128},{"id":1,"start":128,"stop":290}]}`.

---

## 4. FLEET SCOPE — **zero accounts exposed today**

Scanned all 24 user documents, walking `users/{uid}/roofline_config/*/pixelMap`:

```
accounts WITH pixelMap data (per-pixel capable):   0
accounts with roofline_config but no pixelMap:    12
```

Twelve accounts have a `roofline_config/config` document (name, photo, segments, counts), but
**no account anywhere has a single `pixelMap` document.** Per-pixel painting is Design-Studio-only
and nobody has used it in production. **No customer can currently be in this state.**

Two observations from the same scan, flagged not chased:

- **Tyler's own `roofline_config/config` carries `migrated_to_pixel_map: true`, `migrated_at` and
  `migrated_controller_id` — yet the `pixelMap` subcollection is empty and the doc has no
  subcollections at all.** A migration that recorded success and wrote nothing. Worth its own look;
  it is the same silent-success shape, and it means the migration flag cannot be trusted as evidence
  the data exists.
- Slice 1 confirmed the captured map survives an app force-close, but it is **not in Firestore** —
  so the capture persists **device-locally**, like the lease ledger. Same durability exposure as
  P0-9b (reinstall / second device loses it).

---

## 5. WHERE `frz:false` SHOULD BE SENT — one chokepoint, not 66 call sites

**Recommendation: inject at the repository write boundary, not in `applyBaseAndSpans`.**

Rule: **every segment-level write clears `frz` unless the payload is itself a per-pixel write**
(i.e. unless the `seg` entry carries an `i` array).

```
in the payload builder / applyJson boundary:
  for each seg entry in the payload:
      if entry has no 'i' key  ->  entry['frz'] = false
```

Reasoning:

1. **Coverage.** There are **66** `applyJson` call sites. Patching `applyBaseAndSpans` fixes
   Design Studio and leaves 65 others — quick presets, colour picker, celebrations, neighborhood
   fanout, the healer — all still swallowed. Anyone frozen by *any* route stays broken everywhere
   else.
2. **Self-maintaining.** A new call site added next month inherits the fix. A call-site patch has
   to be remembered forever; this codebase's own history (P1-51, three roofline save surfaces) shows
   that does not happen.
3. **The invariant is honest.** "A segment-level write means *render this*" is true of every one of
   those 66 sites. Freezing is only ever intended as a side effect of per-pixel painting, and the
   `i`-presence test distinguishes them precisely.
4. **It does not break per-pixel painting.** Bench step B showed the per-pixel write re-freezes on
   its own, so the paint sequence unfreeze → base → per-pixel still ends frozen and still paints.
   This does need a bench re-verify of ordering before shipping.

**A second, separate fix is required — the chokepoint does not cover it.** `psave` must not
capture `frz:true`. Either unfreeze immediately before every psave, or strip `frz` from the captured
state. Without this, a poisoned preset already in flash keeps re-freezing forever and no amount of
write-path hygiene reaches it. **These are two fixes, and the psave one is the higher severity**
because its damage is durable.

Optionally also worth considering: a startup/connect assertion that clears `frz` on segments the app
believes should be rendering — the same "heal only what is broken" pattern as
`controller_defaults_healer`. That would recover a customer who somehow got frozen without needing
them to trigger a preset load.

---

## 6. SEVERITY

| Aspect | Assessment |
|---|---|
| **Today** | **Low** — zero fleet exposure; no customer has per-pixel data |
| **On Design Studio release** | **High** — every customer who paints becomes exposed, and the poisoned-preset path makes schedules fire dark durably |
| **Detectability** | **Very poor** — 200 responses, correct readback, correct on-screen preview, LEDs unchanged. Only `frz` reveals it |
| **Recovery (runtime freeze)** | Easy and often automatic — any preset load or power cycle |
| **Recovery (poisoned preset)** | **Requires a re-psave.** Reboots do not fix it |

**This is a release blocker for Design Studio per-pixel, not for the current build.**

---

## 7. RIG STATE

Restored and verified: 2 segments (`seg0` 0-128, `seg1` 128-290), `seglc [3,3]`, `count 290`, both
`frz:false`. Timer table healthy — lease macro 26 @ 19:00 Sun, lease macro 36 @ 18:10 Tue (the app
re-synced this back mid-restore), sunrise-off sentinel `hour:255`. Scratch presets 60/61 deleted.

**One deliberate deviation from byte-faithful restore:** the rig was found `frz:true` (left over
from Tyler's Design Studio session — independent corroboration of the whole finding). The reboot
cleared it and **I did not re-freeze it.** Restoring a hazard would be wrong, and a frozen segment
would silently break anything else tested tonight.
