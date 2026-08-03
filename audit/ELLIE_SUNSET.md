# ELLIE SUNSET FAILURE — root cause

**Date:** 2026-08-02 · **Account:** `5oHhaEaf6icmK2RlOWQMkESAXUG3` / ecochran08@yahoo.com
(Ellie Cochran) · **Reported:** lights did not come on at sunset 2026-08-01
**Status:** DIAGNOSTIC ONLY — read-only Firestore throughout. No writes, no fixes, no branches.

---

## 0. Verdict

**It is NOT the missing-`offTime` defect.** Ellie has **zero** `onTime`-without-`offTime`
calendar entries, and no calendar entry for 2026-08-01 at all.

**The cause is the solar gate.** Both of her schedules are Sunset → Sunrise. The
`solar_scheduling` feature flag resolves **false**, and the flag check in `buildCfgPayload`
drops the **entire schedule** — not just its solar boundary. With both schedules dropped, the
payload is empty, and `syncAll`'s empty-armed guard **aborts before any write**. Her controller
has never been sent a timer while this state has held.

This is not a customer call. **Three accounts are in the same total-failure state and a fourth is
silently partial.**

**AND THE FLAG WAS BELIEVED ON.** Project memory records solar as LIVE since 2026-07-28 — bench
gate passed, Firestore flag flipped, all customer/installer guides rewritten to describe solar
scheduling as a working feature. **The flag document does not exist.** Solar has been OFF
fleetwide the entire time. See §2a — this, not the `continue`, is the reason Ellie's sunset
stopped working *when it did*.

---

## 1. HER DATA

```
schedules: array len 2  (subcollection also 2 — dual-write, consistent)
  [0] "Pattern: 1 On 4 Off - Solid"        timeLabel="Sunset"  offTimeLabel="Sunrise"  enabled=true  dow=all 7
  [1] "Warm White (Daily evening lighting)" timeLabel="Sunset"  offTimeLabel="Sunrise"  enabled=true  dow=all 7

calendar_entries: 10 total — ALL game_day autopilot, ALL carry both onTime and offTime
  entries with onTime and NO offTime: 0
  entry for 2026-08-01: NONE

sunrise_off_enabled : undefined (not set)
latitude / longitude: 38.9934731 / -94.2523898   ← present and valid
time_zone           : "CDT"
controller_ips      : ["10.0.0.32"]
bridge_paired       : true      bridge_ip: "10.0.0.112"     remote_access_enabled: true
controllers/20_e7_c8_f4_d5_38 : dig_octa, ledCount 89, ip 10.0.0.32, fw "16.0.0"
bridge_status/current         : uptime 549763s (6.4d), commands 3, errors 3173
```

Her coordinates and timezone are **fine**. The clock-health path is not implicated — see §4.

---

## 2. ROOT CAUSE — two code facts and one Firestore fact

**Firestore fact.** `config/solar_scheduling` **does not exist.**

```
config collection:
  calendar_leases          = {liveWritesEnabled: true, ...}
  schedules_subcollection  = {enabled: false, allowlistUids: [<Tyler>], rolloutPercent: 0}
  sync_fanout              = {enabled: false}
  solar_scheduling         → ABSENT
```

[solar_scheduling_feature_flag.dart](../lib/features/schedule/solar_scheduling_feature_flag.dart):
`_extractEnabled` returns `false` when `!snap.exists`, and `solarSchedulingEnabledSyncProvider`
defaults to `false` on loading/error. So `solarFlagOn == false`, deliberately and safely.
---

## 2a. THE FLAG WAS BELIEVED ON — THIS IS THE HEADLINE

Project memory (`project_solar_schedules_never_fire`, 2026-07-28) records:

> **SOLAR IS LIVE as of 2026-07-28** — Tyler: *"we can now follow sunrise sunset clocks with the
> most recent updates."* The bench gate above was passed and the Firestore flag
> (`config/solar_scheduling.enabled`) is ON. The flag is runtime state in Firestore — the CODE
> default is still `false`, so reading the repo alone will always suggest solar is off. **Do not
> "correct" docs back to clock-times-only on the strength of the code default; ask.**

That warning is well-taken and I did not rely on the code default. **I read Firestore directly,
and the document is absent.** Verified against the source-of-truth project:

```
service account project_id : icrt6menwsv2d8all8oijs021b06s5   ← correct project
config/solar_scheduling      → exists: false
configs/solar_scheduling     → exists: false
config/solarScheduling       → exists: false
feature_flags/solar_scheduling → exists: false
app_config/*                 → only master_admin / master_corporate_pin /
                                master_installer / master_sales_pin (PIN docs)
config/* (full listing)      → calendar_leases, schedules_subcollection, sync_fanout
```

Path constants confirmed at
[solar_scheduling_feature_flag.dart:26-27](../lib/features/schedule/solar_scheduling_feature_flag.dart#L26):
`kSolarSchedulingFlagCollection = 'config'`, `kSolarSchedulingFlagDocId = 'solar_scheduling'`.

**So solar scheduling has been off fleetwide since it was declared live.** Whatever was flipped on
2026-07-28 is not in this project at this path. The most likely explanation, given the standing
warning in `BUGS_AND_DEBT.md` about exactly this confusion, is that it was set in the **wrong
Firebase project** (`nex-gen-lumina-22751` rather than `icrt6menwsv2d8all8oijs021b06s5`). I cannot
confirm that from here — it needs credentials for the other project — but it is the first thing
to check.

**This reframes the whole incident.** Ellie's schedules were presumably written *after* solar was
announced as working. The customer-facing guides describe solar as a supported feature. Customers
were invited into a configuration that cannot arm, on the strength of a flag that isn't there.

The bootstrap that should have created the doc (`bootstrapSolarSchedulingFlagDoc`, best-effort,
never rethrows) has also never succeeded — so there has never even been a doc in the console for
anyone to notice was `false`.

**Code fact 1 — the gate drops the WHOLE schedule.**
[cfg_payload_builder.dart:156-164](../lib/features/schedule/cfg_payload_builder.dart#L156)

```dart
final onSolar  = isSolarLabel(s.timeLabel);
final offSolar = s.hasOffTime && s.offTimeLabel != null && isSolarLabel(s.offTimeLabel!);

if (!solarEnabled) {
  if (onSolar || offSolar) {
    debug?.call('... skipped solar timer ... — solar disabled');
    continue;                    // ← drops the ENTIRE ScheduleItem
  }
}
```

`continue` skips the whole loop iteration. A schedule with **either** boundary solar contributes
nothing at all — including a perfectly armable clock boundary on its other end. Both of Ellie's
schedules are solar on both ends, so `timers` comes back empty.

**Code fact 2 — the sync then aborts and writes nothing.**
[schedule_sync.dart:1198-1208](../lib/features/schedule/schedule_sync.dart#L1198)

```dart
if (armedSchedules.isNotEmpty && !scheduleIns.any(isRealEnabledTimer)) {
  debugPrint('ScheduleSync: ABORT — ... zero real timers (all stubs). '
             'Refusing to POST a no-op that would false-green.');
  return finish(ScheduleSyncResult(
    success: false,
    error: 'internal: enabled schedules produced no armable timers', ...));
}
```

Her two schedules pass every arm check (`enabled`, `dow != 0`), so `armedSchedules` is non-empty;
`scheduleIns` is empty; the guard fires. **No `/json/cfg` POST is ever attempted.** Every sync she
performs takes this path. This is permanent for as long as all her schedules are solar.

**Credit where due:** the guard is working exactly as designed. It is the reason this failed
loudly at the sync layer instead of false-greening. The defect is upstream of it.

---

## 3. IS IT SILENT? — partly, and the message is the problem

Unlike the Block E defect, this is **not** a silent success at the sync layer: it returns
`success: false` with an error string. That is a meaningful difference and it is to the code's
credit.

But `"internal: enabled schedules produced no armable timers"` names neither the cause nor a
remedy. It tells Ellie nothing, tells support nothing, and does not contain the words "sunrise",
"sunset", or "solar". The `continue` that actually dropped her schedules logs only to
`debugPrint` — invisible in a release build. So the *diagnosis* is silent even though the
*failure* is not.

Her `debug_errors` subcollection would not capture this either: the abort is a returned result,
not a thrown error.

---

## 4. THE OTHER SOLAR HYPOTHESES — checked and excluded

**`isRealEnabledTimer` excludes `hour == 255`** — correct, and confirmed at
[timer_landing.dart:11-17](../lib/features/schedule/timer_landing.dart#L11):
`return enOn && macro != 0 && hour != 255;`. Solar rows are structurally invisible to
`timersInsLanded`. **But that is not what bit Ellie** — no solar row was ever built. This exclusion
becomes live the moment the flag is turned on, and it means a wrong or missing solar row will
verify clean. It should be treated as a blocker on the flag flip, not as tonight's cause.

**First-wins solar slot contention** ([schedule_sync.dart:493-554](../lib/features/schedule/schedule_sync.dart#L493)) —
not reached. `solarTimerSlots` only runs inside the `solarEnabled || globalSunriseOff != null`
branch; Ellie has `solarFlagOn == false` and no `sunrise_off_enabled`, so the branch is skipped
entirely. Worth noting for later: with two Sunset schedules she **would** hit the first-wins
rejection if the flag were flipped — one of her two would be refused with the "Only one sunrise and
one sunset schedule are supported per controller" warning.

**Clock / coordinates / tz** — not implicated. Her lat/lon are populated and valid and tz is CDT.
`solarCoordsUsable` is only computed when `solarFlagOn` is true, so it was never even evaluated.
The clock-health evaluator remains unaudited, but it is not on this failure path.

---

## 5. PARTIAL VS TOTAL — total, and a data discrepancy

**Total, not partial.** No timer of any kind was armed, so there is no preset for a segment-level
`on:false` to spoil. The bench's preset-1 shape (`seg0.on:false`) does not apply here.

For the record, her schedules' payloads assert master power correctly and carry a single segment
with no per-segment `on` override:

```
[0] {"on":true,"bri":255,"seg":[{"fx":0,"pal":5,"grp":1,"spc":4,"col":[[255,193,141,0],[255,218,187,0]]}]}
[1] {"on":true,"bri":180,"seg":[{"fx":0,"pal":0,"grp":1,"spc":1,"col":[[255,169,87,0]]}]}
```

**Discrepancy worth resolving:** the report describes a *two-channel façade*, but Firestore shows
**one** controller (`10.0.0.32`, `dig_octa`, `ledCount 89`). Either the second channel is a second
bus on the same controller (not visible in this document) or the account record is incomplete.
Not causal, but it will matter when someone tries to verify the fix on her house.

---

## 6. FLEET SCOPE — this is a fleet event

Scanned all 24 user documents. **5 solar schedules across 4 accounts, out of 13 schedules
fleetwide (38%).**

| Account | ctrl | schedules | solar | Effect |
|---|---|---|---|---|
| **Ellie Cochran** | 1 | 2 | 2 | **ALL-SOLAR → sync aborts, nothing ever arms** |
| **Tim Kelly** | 1 | 1 | 1 | **ALL-SOLAR → sync aborts, nothing ever arms** |
| **Chris Cipollone** | 1 | 1 | 1 | **ALL-SOLAR → sync aborts, nothing ever arms** |
| Brooke Rozenberg | 1 | 8 | 1 | Partial — 7 arm, the solar one **silently vanishes** |

**Three accounts are in total failure.** Their controllers cannot receive a timer at all.

**Brooke's case is the more dangerous shape.** Her seven clock schedules build fine, so
`scheduleIns` is non-empty, the empty-armed guard does **not** fire, and the sync reports
**success** — while her "Warm White (Daily evening lighting)" schedule is dropped by the same
`continue` and never arms. Success reported, work not done, no warning of any kind. That is the
silent-partial variant and it would not have surfaced through any existing check.

**Tim Kelly's case shows the over-broad `continue` doing extra damage:** his schedule is
`on="Sunset"`, `off="1:00 AM"`. The 1:00 AM OFF boundary is an ordinary clock time and would arm
perfectly well — but because the ON boundary is solar, `continue` discards the whole schedule and
his OFF timer is lost too. A narrower gate that dropped only the solar boundary would have left
him with a working OFF.

---

## 7. A SECOND GATE STACKED BEHIND THE FIRST

Even with the solar flag flipped on, Ellie's timers may still not arm.
[schedule_sync.dart:1211-1221](../lib/features/schedule/schedule_sync.dart#L1211): arming is a
`/json/cfg` write, and `repoCanWriteCfg(repo)` short-circuits to `deferredOffLan` because the
bridge routes everything but `getState`/`getInfo` to `/json/state`, where WLED discards cfg keys.

She is `bridge_paired: true`, `remote_access_enabled: true`. If her phone is off-LAN when she
syncs, the write defers regardless of the solar fix. That check sits *after* the empty-armed
guard, so she has never reached it — but anyone testing a solar fix on her account must confirm
she is on-LAN, or they will conclude the fix failed.

Also flagged, not causal: her bridge reports **3173 errors** against 3 commands over 6.4 days
uptime. Nothing in this failure path touches the bridge, but that ratio deserves its own look.

---

## 8. OPEN ITEMS

| # | Item | State |
|---|---|---|
| 1 | Solar gate `continue` drops the ENTIRE schedule, not just the solar boundary | Root cause, confirmed, unfixed |
| 2 | 3 accounts (Ellie, Tim Kelly, Chris Cipollone) arm **zero** timers — total failure | Confirmed, customer-visible now |
| 3 | Brooke Rozenberg: silent partial — success reported, 1 of 8 schedules vanishes | Confirmed; new silent-success shape |
| 4 | Abort message `"internal: enabled schedules produced no armable timers"` names neither cause nor remedy | Confirmed |
| 5 | **`config/solar_scheduling` ABSENT though solar was declared LIVE 2026-07-28 → solar OFF fleetwide the whole time; guides describe a feature that cannot arm** | **P0 — check the other Firebase project first** |
| 6 | `isRealEnabledTimer` excludes `hour==255` → solar rows unverifiable by `timersInsLanded` | Blocker on any flag flip |
| 7 | Ellie has TWO Sunset schedules → would hit first-wins rejection if flag flipped | Latent, surfaces on fix |
| 8 | Firestore shows 1 controller / 89 LEDs vs reported two-channel façade | Unresolved data discrepancy |
| 9 | Bridge `errors: 3173` vs `commands: 3` | Unrelated to this failure; own investigation |

**Not investigated (would require writes):** her controller's live `timers.ins`. Reading it means
enqueueing a command document, which is not read-only. Everything above is from Firestore user
state and source.

**Not investigated (UI):** whether the `success:false` abort surfaces any visible message in the
Scheduling tab, and whether the AI/editor offers solar boundaries to users at all given the flag
is off fleetwide — if it does, the product is inviting users into a state that cannot work.
