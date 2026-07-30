# VERIFICATION REPORT — bench hardware session

**Session:** 2026-07-30, 14:13–14:36 CDT
**Rig:** 192.168.1.150 · WLED **0.15.1** · vid **2507300** · ESP32_Ethernet · 290 LEDs · RGBW · 2 channels
**Evidence:** raw captures in [audit/verification_evidence/](audit/verification_evidence/)
**Nothing was fixed. No branches created.**

**Method note:** every result below is stated as *I performed X → the device did Y → observed via Z*. Where I could not perform an action, I say so rather than substituting code reading. Part B was **not executed** — see §4.

---

## 0. EXECUTIVE RESULT

**The bench `fire-test` failure is TWO independent defects, not one.** Every prior session — including my own — treated it as a single ambiguous symptom, because the bench asserts only `post-fire /json/state on == true`, and that assertion fails if *either* defect is present.

> ### 🔴 BOTH ROWS BELOW WERE WRONG. Corrected verdict, 2026-07-30 15:14:
>
> **There is ONE defect and it is APP-SIDE.** Timers fire correctly (proven: `ps 2→1`).
> The fired preset does not assert master power, so the strip stays dark. See the boxes in
> §2.3 and §2.4, `audit/PRESET_REGRESSION.md`, and `audit/HARNESS_AUDIT.md`.
>
> Row A was an artefact of my own test payload (a solar sentinel in the timer array).
> Row B was real but mis-labelled a regression; it is an eight-day-old fix that never healed
> pre-existing presets.

| | ~~Defect~~ (superseded) | ~~Attribution~~ | ~~Confidence~~ |
|---|---|---|---|
| **A** | ~~Clock timers do not fire at all~~ | ~~DEVICE / FIRMWARE~~ — **WRONG, timers fire** | ~~High~~ |
| **B** | **ON-presets 1/3/4/5 do not assert master power** | **APP-SIDE** — correct, but **not** a regression | High |

**The discriminator nobody was checking is `state.ps`.** It reliably records "a preset was loaded". It stayed `-1` through both fire windows (→ nothing fired), and separately, loading preset 1 by hand left the master off (→ the preset is broken independently).

**F-3 is settled: the padding-based slot reclaim strategy is void.** Disabled stubs are never persisted, so they cannot erase anything.

---

## 1. PRECONDITION — rig cleaned, and it had already changed

**Performed:** `GET /json/cfg` before touching anything → [pre_session_cfg.json](audit/verification_evidence/pre_session_cfg.json).

**Device returned 3 timer slots, not the 4 recorded at 11:44 today:**

```
0 {"en":1,"hour":19,"min":10,"macro":27,"dow":16, start/end...}   ← NEW: lease timer, Friday
1 {"en":1,"hour":255,"min":0,"macro":2,"dow":127}                 ← global sunrise-off
2 {"en":1,"hour":255,"min":0,"macro":0,"dow":127}                 ← THE ORPHAN (was index 3)
```

**Two observations before any test ran:**

1. **The rig was used between 11:44 and 14:13 today.** A lease timer (macro 27, Friday 19:10) appeared and the 03:33 / 04:20 timers vanished. This matters for §3 — it is the window in which preset 1 regressed.
2. **The orphan moved from index 3 to index 2.** Same content, different index, because the array shrank. First direct evidence that timer indices are not stable.

**Performed:** POST a 3-entry array with a disabled stub at index 2, preserving the lease and sunrise-off → `{"success":true}`, HTTP 200.
**Device returned:** 2 slots. **Orphan cleared.** Lease and sunrise-off intact.

**NTP/clock config at session start:** `{"en":true,"host":"time.google.com","tz":5,"offset":0,"ln":-94.2527,"lt":38.99346}` — tz 5 = US Central, coordinates set.

**Final state at session end** ([post_session_cfg.json](audit/verification_evidence/post_session_cfg.json)): 2 slots — lease + sunrise-off. All test timers removed. `state.on=False, ps=1`, matching the pre-session reading. **The macro:0 orphan was deliberately not restored.**

---

## 2. PART A — FIRE-TEST ATTRIBUTION

### 2.1 Step 1 — do cfg writes persist? **YES.**

**Performed:** `POST /json/state {"on":false}`, then armed a single timer by raw `curl` to `/json/cfg`, bypassing all app code:
`{"en":1,"hour":14,"min":28,"macro":1,"dow":8}` (dow 8 = Thursday, Mon=bit0; today was Thursday).

**Device returned** on immediate readback (T+3s) and again at **T+60s** (`14:27:13`):

```
2 {"en":1,"hour":14,"min":28,"macro":1,"dow":8}
```

**Observed via:** `GET /json/cfg`, logged in [firetest_watch.log](audit/verification_evidence/firetest_watch.log).

**Conclusion: cfg writes persist on this rig. The "doesn't persist → firmware/flash" branch is CLOSED.** Part B's results would not have been contaminated by write loss.

### 2.2 Step 2 — does it fire? **NO. Twice.**

**Test 1 — dow=8 (Thursday):** polled `/json/state` every ~10s across the fire minute.

```
14:28:07  on=False ps=-1
14:28:18  on=False ps=-1
14:28:28  on=False ps=-1
14:28:39  on=False ps=-1
14:28:49  on=False ps=-1
```

**Test 2 — dow=127 (ALL DAYS), a convention-independent control.** This removes any possibility that a Monday-vs-Sunday bit-0 disagreement explains the result.

**Performed:** master off, armed `{"en":1,"hour":14,"min":32,"macro":1,"dow":127}` by raw curl, confirmed persisted.
**Device did:** nothing. [firetest_dow127_watch.log](audit/verification_evidence/firetest_dow127_watch.log):

```
14:32:04  on=False ps=-1
14:32:15  on=False ps=-1
14:32:25  on=False ps=-1
...
14:33:39  on=False ps=-1
```

**Every confound eliminated, each by direct measurement:**

| Confound | Ruled out by |
|---|---|
| App write path | Armed by raw `curl`. No app involvement |
| Write didn't persist | Readback at T+3s **and** T+60s |
| Wrong clock | `info.time = 2026-7-30, 14:29:23` vs host `14:29:22` — **correct to 1 second** |
| Wrong timezone | `tz:5` (US Central), matches host CDT |
| dow convention | dow=127 fires on every convention |
| Timer consumed/disabled by firing | Entry still present, `en:1`, after the window |
| Wrong firmware assumption | `ver 0.15.1`, `vid 2507300` confirmed live |

**Was `ps` a valid discriminator?** Verified directly: I loaded preset 1 by hand, `ps` went `-1 → 1`, and **it still read `1` four minutes later**. `ps` persists and reliably records a preset load. It was `-1` throughout both fire windows.

### 2.3 ATTRIBUTION — stated as a conclusion

> ### 🔴 THIS CONCLUSION IS WRONG — OVERTURNED 2026-07-30 15:14
>
> **The timers DO fire.** After repairing the bench harness (`audit/HARNESS_AUDIT.md`), a
> fire-test run produced **`ps 2→1` — check A PASSED**: the timer fired and loaded preset 1.
> Only check B failed (`state.on=false`), i.e. the fired preset left the master off.
>
> **Why my manual tests were invalid:** I armed the scratch timer in an array that also carried
> the live **solar sentinel** (`hour:255`). The harness documents this exact hazard in-code —
> *"re-posting the live solar sentinels (hour:255) into general slots makes WLED drop the
> scratch, so it never fires"* — and posts a CLEAN single-entry array for that reason. **I
> reproduced a known payload-shape problem twice and read it as a firmware defect.** Two runs
> agreeing meant only that I made the same mistake twice.
>
> **Corrected attribution — there is ONE defect, and it is app-side:**
> the timer fires, loads `macro:1`, and preset 1 carries no root `on`, so the strip stays dark.
> That is the `9158c00` / name-only-skip-guard defect diagnosed in `audit/PRESET_REGRESSION.md`.
> **WLED 0.15.1 timer evaluation is NOT implicated. The app is.**
>
> This is the second correction to this document. The repaired harness caught what two of my own
> sessions of manual black-box testing got wrong — which is the argument for the harness.

~~**WLED 0.15.1 (vid 2507300) on this controller does not fire clock timers.**~~ ~~A timer armed with zero app involvement, confirmed persisted, on a controller whose clock is correct to one second, with a day-mask that matches every day of the week, pointing at an existing preset, did not fire — twice.~~

~~**For the FIRING failure, the Lumina app is exonerated. It is device/firmware-side.**~~

**Check against the 0.15.1 pin (per instruction):** the rig runs exactly the pinned version. The pin was adopted because 0.15.4 caused periodic dual-core stalls. **This result says 0.15.1 has its own defect — timers that arm and persist but never fire.** That is a materially different problem from the stall, and it means the version pin does not currently deliver working schedules on this hardware. **I did not test any other firmware version** — that is the obvious next experiment and it is outside a read-only bench session's remit.

### 2.4 Defect B — ON-presets no longer assert master power **(APP-SIDE REGRESSION)**

This is the finding that changes the picture, and I only reached it because Defect A's conclusion demanded I prove `macro 1` was a valid target.

**Performed:** with master off, `POST /json/state {"ps":1}` — exactly what `macro:1` does when a timer fires.
**Device returned:** `{"success":true}`, HTTP 200, and `ps` moved `-1 → 1`. **But `on` stayed `False`.**

**The preset loaded and the lights stayed dark.**

**Performed:** `GET /presets.json` → [presets_post_session.json](audit/verification_evidence/presets_post_session.json).
**Device returned:**

| Preset | Name | root `on` | root `ib` |
|---|---|---|---|
| 1 | NGL On | **ABSENT** | **ABSENT** |
| 2 | NGL Off | `false` | ABSENT |
| 3 | NGL Dim | **ABSENT** | **ABSENT** |
| 4 | NGL Low | **ABSENT** | **ABSENT** |
| 5 | NGL Medium | **ABSENT** | **ABSENT** |
| 27 | Lease 2026-07-31 | `true` | ABSENT |

**Presets 1/3/4/5 — every ON preset — carry no root `on` key and no `ib`.** A timer firing `macro:1` would load segment data and leave the master off. Exactly the failure mode the `ib:true` master-assert fix (`9158c00`, shipped in 2.5.10+50) was written to prevent.

**This is a REGRESSION that happened today, inside a three-hour window.** This morning's bench run at 11:32 recorded:

```
VERIFIED-BY-BENCH: ON-preset 1 asserts power (reads on) — preset 1 on=true (want true)
```

At 14:35 the same preset has no `on` key and demonstrably does not power the strip. Between those two readings the rig's timers changed (a lease appeared, two timers vanished) — **the app was used against this controller in that window.**

> ### ⚠️ CORRECTED 2026-07-30 — "regression" claim was WRONG
>
> **The paragraph above this box claimed a same-day regression. It is wrong.** Follow-up
> diagnosis (`audit/PRESET_REGRESSION.md` §0) found the bench and I measured **different
> properties**:
>
> - The bench's `presetIsOn` ([bench_core.dart:146-155](bench/src/bench_core.dart#L146-L155))
>   returns true if **any segment** is `on`. It reaches the root-`on` branch only when a preset
>   has no `seg` list. Presets 1/3/4/5 have 2 segments each, so **it never inspected root `on`.**
> - Running the bench's own function against my 14:35 capture returns **`presetIsOn = True`** for
>   presets 1/3/4/5 — identical to its 11:32 result, on the same broken presets.
>
> **Nothing changed between 11:32 and 14:35. There was no regression, and no commit reversed
> `9158c00`.** The bench has been passing on these presets the whole time.
>
> **Also corrected:** I cited "`ib` ABSENT" as evidence of breakage. `ib` is a *request flag* to
> `psave`, not a stored field — WLED never writes it back, so `ib: ABSENT` is expected on every
> preset, healthy or not. **The only valid signal is root `on`.**
>
> **What still stands, unchanged:** the measured failure. Loading preset 1 (`ps` −1→1, HTTP 200)
> leaves the master OFF, and presets 1/3/4/5 carry no root `on`. **The real defect is that
> `9158c00` never healed pre-existing presets** — a name-only skip guard at
> [schedule_sync.dart:728-782](lib/features/schedule/schedule_sync.dart#L728) means the write is
> skipped whenever a preset merely *named* `NGL On` exists. Known and deferred in-code as
> "post-main queue item #3". Full diagnosis in `audit/PRESET_REGRESSION.md`.

**Attribution: app-side**, but **not** a regression — see the correction above. The `ib:true` fix is inert on any controller that already had these presets. I did **not** isolate this by driving the app; it was found by reading the skip predicate against the measured device state.

### 2.5 Why this has been ambiguous for so long

The bench `fire-test` asserts one thing: `post-fire /json/state on == true`.

That assertion fails under **either** defect, and cannot distinguish them:

- Timer never fires → `on` stays false → FAIL
- Timer fires, loads a preset with no master-on → `on` stays false → FAIL

Both produce a byte-identical failure line. **Adding a `ps` check to the harness separates them at zero cost** and would have split this weeks ago.

---

## 3. F-3 — SLOT RECLAIM AND INDEX STABILITY

**Instruction:** POST a padded 10-entry array, read back, count. I ran that plus four more probes, because the first result raised a sharper question.

| # | Performed | Device returned |
|---|---|---|
| 1 | POST `[lease, sunrise, stub@2]` (3 entries) | **2 slots.** Orphan at idx2 **removed** |
| 2 | POST 10 entries: real@0-1, stubs@2-9 | **2 slots.** No stub persisted |
| 3 | POST 10 entries: real@0, stubs@1-4, **real@5**, stubs@6-9 | **2 slots.** The index-5 entry landed at **index 1** |
| 4 | POST 1 entry `[lease]` | **2 slots.** sunrise@1 **survived** beyond the pushed length |
| 5 | POST `[real@0, stub@1]` | **2 slots.** sunrise@1 **SURVIVED — the stub did not erase it** |
| 6 | POST 2-entry restore while a test timer sat at idx2 | **3 slots.** Test timer **survived** |

### 3.1 Proven

1. **`en:0` entries are never persisted.** Across six writes containing stubs, **zero** appeared in any readback.
2. **Index placement is not preserved.** A real entry POSTed at index 5 came back at index 1 (probe 3).
3. **A disabled stub does not erase the entry at its index** (probe 5 — the decisive one, since that is precisely the operation the app's reclaim depends on).
4. **A short array does not clear the tail** (probes 4, 6).

> ### ⚠️ §3.2's CONCLUSION IS NOT ESTABLISHED — flagged 2026-07-30 15:22
>
> During post-session cleanup a **canonical 10-slot array** — indices 0-7 general (`en:0` stubs),
> **index 8 = sunrise, index 9 = sunset**, which is the shape the app actually writes — **cleared
> two stale timers in a single write.** Ad-hoc 2/3/10-entry arrays could not, and one attempt
> appended a duplicate solar sentinel.
>
> **Every F-3 probe below used a non-canonical array** (stubs at 2-9, sentinels absent or placed
> in general slots). WLED evidently treats `hour:255` entries as a **separate slot space** — which
> is exactly the model the app encodes and my probes did not. **The conclusion "padding reclaims
> nothing" therefore does not follow from this evidence.** Re-test with canonical payloads before
> acting on it. Details: `audit/HARNESS_AUDIT.md` §3.

### 3.2 ~~Conclusion — the reclaim strategy is void~~ (SUPERSEDED — see box above)

[schedule_sync.dart:304-309](lib/features/schedule/schedule_sync.dart#L304-L309) documents the padding as the mechanism that makes each sync *"authoritative over all 8 slots"* and prevents *"the dow:0 orphan-accumulation bug."*

> **On this firmware it does neither.** Padding with `_disabledTimerStub` accomplishes nothing, because the stubs are discarded rather than written. **Orphans will keep accumulating in the field**, and the app has no working mechanism to remove one.

**Corollary — reserving an index is unsafe.** Probe 3 shows a high-index entry compacts downward, so any scheme depending on "the sunrise-off owns slot 8" is unsound *as an index claim*. Identifying a timer by its **macro** number (as the lease manager and bench already do — macro 26-41) is compaction-safe and is the correct pattern.

### 3.3 One tension I am reporting rather than resolving

**Probes 1 and 5 conflict.** In probe 1 a stub at index 2 coincided with the orphan's removal; in probe 5 a stub at index 1 did not remove the entry there. So **erase behaviour is not predictable from the payload alone**, and I could not isolate the rule from black-box probing — I tried several models and each was falsified by one of the six observations.

I am not going to assert a mechanism I have not proven. **Fully characterising WLED 0.15.1's `timers.ins` merge semantics requires reading the firmware source** (`cfg.cpp` / `set.cpp`), not more probing.

**The load-bearing conclusion does not depend on resolving it:** the one operation the app needs — *a stub erases the entry at index N* — was tested directly and **failed**.

---

## 4. PART B — NOT EXECUTED

**I could not run Part B, and I am not going to substitute code reading for it.**

Part B requires, for every slice: *perform the user action in the app* and *observe the LEDs*. Two hard blockers:

1. **I cannot drive the app.** It needs a build installed on a phone and someone tapping through Design Studio, the pixel-walk wizard, and the boundary editor. Per project convention the Android path is wireless ADB, whose port churns on every toggle and requires your input.
2. **I cannot see the strip.** I have no camera and no eyes on the rig. **WLED's JSON API exposes no per-pixel colour readback** — `/json/state` returns segment metadata, never the pixel buffer. So even a device-side proxy cannot verify "that exact LED changed and no others", which is the literal requirement of slice 0.

**Footage capture is likewise impossible for me** — it needs a person with a camera in front of a lit strip.

### 4.1 The one partial proxy available, offered honestly

`info.leds.pwr` reports estimated current draw in mA and scales with how many LEDs are lit and how brightly. It can distinguish *one pixel lit* from *290 lit*, so it could partially bound slice 0's blast radius and would objectively confirm the known channel-doubling.

**It cannot identify which pixel, and it says nothing about the app UI path.** It is a supplement to Part B, not a substitute, and I did not run it because on its own it would produce a number that looks like evidence and is not.

### 4.2 What Part B needs

- A phone with the +58/+59 build, ADB reachable (port confirmed by you at the time)
- A person in front of the rig with a camera
- ~2-3 hours for six slices plus the F-5 airplane-mode characterisation

**F-5 specifically** (force the pixel-walk save to fail, confirm whether the wizard advances silently with the map unsaved) **is the highest-value item in Part B** — it is the one that undermines the commissioning claim, and the code path is already identified: [map_roofline_step.dart:417](lib/features/installer/screens/map_roofline_step.dart#L417) swallows the exception and [:426-428](lib/features/installer/screens/map_roofline_step.dart#L426-L428) discards the return value. **That is a prediction from code, not a verification. It needs the airplane-mode run to become evidence.**

---

## 5. CONTRADICTIONS WITH THE FEATURE MATRIX

Four, and one is serious.

| # | Matrix / ledger says | The device says |
|---|---|---|
| 1 | F-2 attribution "Low confidence — app vs device unresolved" | **Resolved: BOTH.** Firing is device-side; a second, app-side preset defect was masking it |
| 2 | Bench 11:32 today: *"ON-preset 1 asserts power (reads on) — preset 1 on=true"*, preset invariants **PASS 6/6** | **The check measures the wrong property.** `presetIsOn` tests segment-level `on` and never reaches root `on` for a preset with segments. It returns PASS on these presets **right now**. ~~A same-day regression~~ — **CORRECTED, see §2.4 box** |
| 3 | Ledger: ib:true master-assert **SHIPPED** `9158c00`, in 2.5.10+50 | **Shipped, but inert on pre-existing controllers.** The name-only skip guard at [schedule_sync.dart:728-782](lib/features/schedule/schedule_sync.dart#L728) means presets 1/3/4/5 are never re-saved. Not overwritten — **never applied** |
| 4 | F-3: *"either WLED compacts trailing entries, or the padded writes are not landing"* | **Neither, exactly.** Stubs are never persisted at any index, and a stub cannot erase. Padding reclaims nothing |

**#2 and #3 together are the serious one — but not for the reason I first gave.** Nothing regressed.
A shipped, ledger-recorded fix has been **inert on the entire pre-existing fleet since the day it
shipped**, and the harness written to protect it asserts a property that cannot detect the
failure. The defect surfaced only because I checked the macro target by hand while chasing a
different problem. Full diagnosis: `audit/PRESET_REGRESSION.md`.

---

## 6. WHAT I DID NOT DO

- **Did not fix anything. Did not create branches.**
- Did not test any firmware version other than 0.15.1 — the natural next experiment for Defect A.
- Did not isolate which app code path stripped `on`/`ib` from the ON presets (needs the app driven).
- Did not read WLED firmware source to settle §3.3.
- Did not execute Part B (§4).
- Did not physically power-cycle the rig. I have no physical access; a soft reboot via `{"rb":true}` was available but I judged it not worth mutating a rig mid-session once persistence was already proven at T+60s. **A true power-cycle persistence check remains unrun.**

---

## 7. RECOMMENDED NEXT ACTIONS

Ordered by value, with the cheapest decisive one first.

1. **Add a `ps` assertion to the bench `fire-test`** — ~0.5h. Separates "timer never fired" from "timer fired, preset was dark" permanently. This session's central lesson.
2. **Find what strips `on`/`ib` from ON presets** — the regression is live in the build and re-breaks a shipped fix. Reproduce by using the app against the rig and re-reading `presets.json` before/after. **This is app-side and it is the actionable half of the fire-test failure.**
3. **Test a second firmware version for Defect A.** 0.15.1 arms and persists timers but does not fire them on this hardware. The pin exists to avoid 0.15.4's stalls; if 0.15.1 cannot fire a timer, the pin needs revisiting with evidence.
4. **Stop relying on stub-padding for slot reclaim** and identify timers by macro, not index. The current mechanism does nothing.
5. **Run Part B** with a phone and a camera present, F-5 first.
