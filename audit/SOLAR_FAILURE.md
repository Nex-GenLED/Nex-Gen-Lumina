# SOLAR SCHEDULING — Live Customer Failure Diagnosis

**Subject:** Ellie Cochran (`5oHhaEaf6icmK2RlOWQMkESAXUG3`) — lights did not come on at sunset, 2026-08-01
**Investigated:** 2026-08-03 · read-only, Firestore REST via gcloud ADC · project `icrt6menwsv2d8all8oijs021b06s5`
**Scope:** diagnosis only. No code changed, no data written, no fix proposed beyond naming what is broken.

---

## Bottom line

Ellie's sunset schedule has **never once been armed on her controller**, and last night was not a regression —
it is the steady state. Three independent, individually-sufficient failures stack:

| # | Failure | Status |
|---|---|---|
| **A** | The only config write her controller ever received used the known-bad `hour:24/25` encoding, with `en` as a JSON **bool** | Proven from her wire payload |
| **B** | That write went out over the **bridge relay**, which by the codebase's own account cannot deliver a `/json/cfg` write at all | Proven — payload is an `applyConfig` relay command |
| **C** | Her bridge has been **dead since 2026-07-21**; every command since has expired | Proven from `bridge_status` + 997 command docs |

Under **current** code she is no better off: `config/solar_scheduling` **does not exist** in Firestore, so the
correctly-encoded solar path is off fleet-wide and both her schedules are refused before they reach a timer slot.

**She is not alone.** 4 of 15 users with controllers have enabled solar schedules; **3 of those 4 have *no other
schedules at all***, so 100% of their scheduling is dead. This is a fleet condition, not one house.

Everything below about her **controller's actual current timer table is inference** — her bridge is down and her
controller is on her LAN, so I could not read the device. All device-side claims are marked as such.

---

## 1. Her actual state (read first, before any code reasoning)

### Does she have a sunset schedule configured at all? — **Yes. Two of them.**

Root `users/{uid}.schedules` (2 entries) and the `schedules` subcollection (same 2, written `2026-08-02T16:42Z`)
agree. `config/schedules_subcollection` is allowlisted to Tyler's uid only, so the app reads her **root array**;
the subcollection is a dual-write shadow. No divergence between them.

| id | action | ON | OFF | days | enabled |
|---|---|---|---|---|---|
| `sch-1785688919895` | Pattern: 1 On 4 Off - Solid | **Sunset** | **Sunrise** | all 7 | true |
| `autopilot-8680a32b-…` | Warm White (Daily evening lighting) | **Sunset** | **Sunrise** | all 7 | true |

**Both of her schedules are solar. She has no clock-time schedule anywhere.** Nothing she owns can fire under
current code.

### Account / site

- Profile coords **present and correct**: `38.9934731, -94.2523898` (924 SE Wood Ridge Ct, Blue Springs MO).
- `time_zone: "CDT"` — an abbreviation, **not an IANA zone**. See §5.
- `remote_access_enabled: true`, `bridge_paired: true`, `bridge_ip 10.0.0.112`, `controller_ips ["10.0.0.32"]`.
- One controller, `20_e7_c8_f4_d5_38` — `dig_octa`, `firmwareVersion "16.0.0"`, 89 LEDs. Controller doc last
  written **2026-05-29** (install day) and never since.
  She is the **only `dig_octa` on the fleet**; every other controller is `skikbily` on `fw 0.15.1`. `"16.0.0"` is
  not a WLED version string.

### When did her controller last sync? — **2026-07-10. Nothing since.**

`bridge_status/current`, last written **2026-07-21T21:11:15Z**: `uptime 549763s`, `errors 3173`, `commands 3`.

Command queue (997 docs, full pagination):

```
getState 869 · getInfo 89 · savePreset 16 · applyJson 16 · applyConfig 4 · ping 3
completed 550 · timeout 400 · failed 27 · executing 14 · expired 6
```

- Last **successfully executed** command of any kind: **2026-07-10T20:10:16Z**.
- Every command from **2026-07-21T21:38Z** onward is `expired` — including a `ping` on **2026-08-03T01:57Z**.
- `errors: 3173` is the highest on the fleet by ~3×.

For contrast, 5 other bridges reported in at `2026-08-03T15:44Z` while I was pulling this. **Hers alone is dead.**

---

## 2. Was the row ever written?

**A solar row should exist. Slots 8/9 have never been touched — by her path or any other.**

Her last config write, `applyConfig` @ `2026-07-10T20:10:16Z`, `status: completed`, verbatim:

```json
{"timers":{"ins":[
  {"en":true,"hour":25,"min":0,"macro":1,"dow":127},
  {"en":true,"hour":24,"min":0,"macro":2,"dow":127},
  {"en":true,"hour":20,"min":44,"macro":1,"dow":16},
  {"en":true,"hour":20,"min":44,"macro":1,"dow":32},
  {"en":true,"hour":20,"min":43,"macro":1,"dow":64},
  {"en":true,"hour":20,"min":43,"macro":1,"dow":1},
  {"en":true,"hour":20,"min":42,"macro":1,"dow":2},
  {"en":true,"hour":20,"min":41,"macro":1,"dow":4}]}}
```

Eight entries. **No slot 8. No slot 9. No `hour:255` anywhere.** There is no positional solar sentinel in her
history at all — an earlier `applyConfig` on 2026-05-30 has the same shape with `dow:0` on the trailing rows.

### The first-wins collision — present, but not her cause

She is the **only user on the fleet who over-subscribes the solar slots**: both schedules claim sunset and both
claim sunrise (2 claims each against 1 slot each). Under `solarTimerSlots`
([schedule_sync.dart:493-554](../lib/features/schedule/schedule_sync.dart#L493-L554)) the second schedule loses
both boundaries and lands in `rejected` → a user-visible "Only one sunrise and one sunset schedule are supported
per controller" warning.

**This is real and she will hit it the moment solar is switched on** — but it is not why last night failed. It
cannot be: that code path is gated off, and one of the two would still have won the slot. Her sunset boundary did
not lose a slot fight; **there was no slot fight, because no solar row is ever built.**

The 6 clock rows at `20:41`–`20:44` with single-day `dow` masks (16,32,64,1,2,4 = Fri…Wed from Fri 2026-07-10)
are a **per-day materialized sunset** from a pre-fix path — 6 days, the 7th truncated at the 8-slot cap. Even had
they been delivered, they were frozen at July 10's sunset and would run roughly 20 minutes late by August 1, then
drift further. They are moot for the reason in §3, but they document that an older build did try to approximate
solar with clock rows.

---

## 3. Which encoding? — **The known-bad `hour:24/25` branch. On the wire. On a live customer.**

`hour:25` / `hour:24` at slots 0/1 is exactly
[cfg_payload_builder.dart:100-108](../lib/features/schedule/cfg_payload_builder.dart#L100-L108). It is not the
positional sentinel. On WLED 0.15.1, `hour:24` means *fire hourly* and `hour:25` never matches the RTC.

Three compounding defects in that single payload:

1. **`hour:25` sunset** — invalid, never matches.
2. **`hour:24` sunrise-off** — means "hourly", not "sunrise".
3. **`"en": true` as a JSON bool** — WLED reads `en` type-strict as INT; a bool stores as **0 = disabled**
   (curl-proven 2026-07-22, `727ef0b`). **All eight rows are disabled**, including the six clock rows. Even the
   non-solar part of her schedule table was dead on arrival.

### Is `buildTimerEntry` reachable from a live path today?

**Not for solar — and that is the second half of the problem, not a reassurance.**

Current `buildCfgPayload` omits solar from slots 0-7 and `syncAll` refuses solar entirely unless `solarEnabled`.
So the `hour:24/25` branch is now unreachable for solar labels. Her July-10 payload predates all of it:

| commit | date | effect |
|---|---|---|
| `5b285af` | 2026-07-15 | stop silently succeeding on cfg writes the bridge cannot deliver |
| `a75f504` | 2026-07-20 | refuse sunrise/sunset timers — they never fire |
| `75daeb9` | 2026-07-20 | positional 0.15.1 encoding, **flag-off** |
| `727ef0b` | 2026-07-22 | `en` must be INT not bool |

**Her last write is 2026-07-10 — five days before the earliest of these.** She has received none of them.

**On the unexplained Block-E `hour:255` row:** I found no app-generated `hour:255` in her history, and no live
path that could produce one. Her sentinel-shaped rows are `24`/`25`, not `255`. That anomaly is **not explained
by this account** and remains open.

### The flag is not merely off — the document does not exist

```
GET config/solar_scheduling → 404 NOT_FOUND
```

`bootstrapSolarSchedulingFlagDoc()` has never successfully run against production.
`_extractEnabled` returns `false` for a missing doc, so the resolver is correct and safe — but the practical
consequence is that **the corrected solar encoding is off for every user on the fleet**, and the only two
schedules Ellie owns are refused at
[schedule_sync.dart:1066](../lib/features/schedule/schedule_sync.dart#L1066) with
*"uses sunrise/sunset timing, which isn't supported yet — please set a specific time."*

### Why nothing reported this as broken

Three separate silencers, which is why "solar has never been verified" survived this long:

- **`isRealEnabledTimer` excludes `hour == 255`**
  ([timer_landing.dart:11-17](../lib/features/schedule/timer_landing.dart#L11-L17)) — as the prompt states,
  slots 8/9 are structurally invisible to `timersInsLanded`. A wrong *or absent* solar row reads clean.
- **The empty-armed guard cannot fire for her.** It only trips when
  `armedSchedules.isNotEmpty && !scheduleIns.any(isRealEnabledTimer)`
  ([schedule_sync.dart:1198](../lib/features/schedule/schedule_sync.dart#L1198)). Both her schedules are refused,
  so `armedSchedules` is **empty** and the guard is skipped entirely.
- **A LAN sync today would therefore POST an all-stub array** — `builtIns` empty → `padTimersToMax` → eight
  disabled stubs → slot reclaim **wipes whatever is on her device**, and returns `success: true` with a warning
  attached. That is worth confirming on the bench before anyone touches her account.

Off-LAN (her actual condition) the sync now returns `deferredOffLan` — *"schedule saved, will arm on next LAN
sync"* — and writes nothing. Honest, but she has had no LAN sync recorded and no working bridge.

---

## 4. Partial vs total — **total, and the partial risk is real but secondary**

**Her façade is genuinely two channels.** Confirmed from her last completed `getState` (2026-07-10T18:37Z):

```
seg[0] start:0  stop:45 len:45  on:true  col:[0,70,135]   (front)
seg[1] start:45 stop:89 len:44  on:true  col:[255,177,110] (back)
```

Two segments, both `on:true` at last read.

**Last night was total, not partial** — no timer existed to fire, on either channel.

But the structural hazard the prompt asks about **is present in her data**:

- Her solar row targets a **pattern preset** (slots 10-25). `armable` is built from `updatedSchedules`, which
  carry the preset id assigned at [schedule_sync.dart:881-915](../lib/features/schedule/schedule_sync.dart#L881-L915)
  — so her macro resolves to 10/11, **not** to `_presetForAction`. *(I checked the substring trap in
  `presetForAction` — `"Pattern: 1 On 4 Off - Solid"` contains `"off"` and would map to preset 2, the OFF preset.
  It does **not** bite her, because her schedule is payload-bearing and takes the pattern-preset branch first. It
  remains a live landmine for any payload-less schedule whose label contains "off".)*
- The preset **does** assert master power: `ib: true` is forced on, so root `on:true`/`bri` persist and an
  ON-timer from a master-off state powers the strip.
- **The preset does NOT assert both segments.** Her stored design is single-segment:
  `{"on":true,"bri":255,"seg":[{...}]}` — one unindexed `seg` entry against a **two-segment** controller. Per the
  bench finding already recorded for preset 2 (a `seg[0]`-only preset turned seg0 off and **left seg1 running**),
  a one-element `seg` array leaves seg1 untouched on load.

So when solar is eventually armed, her sunset preset will assert master power and seg0, and **inherit** whatever
state seg1 happens to be in. Both segments were `on:true` at last read, so it would probably look correct — by
luck, not by assertion. If a per-channel power operation ever leaves seg1 off, the back lights and the front (or
vice versa) stays dark, and from the street that reads as "the lights didn't come on."

**This is a latent second failure that would survive the solar fix.** It should be closed in the same pass.

---

## 5. Clock

Nothing here caused last night, but two problems are sitting in her data.

**Coordinates:** her *profile* coords are correct. Whether her **controller** has them is **unknown and
unverifiable** — `cfg.if.ntp.lt/.ln` lives on the device and her bridge is down. Note the healer's coord/tz push
is LAN-gated and she has had no recorded LAN session; her controller doc has not been written since install day.

**Timezone — `"CDT"` is not an IANA zone.** `kWledTzByIana`
([wled_config_pusher.dart:50-58](../lib/services/wled_config_pusher.dart#L50-L58)) keys on
`America/Chicago`, `America/New_York`, etc. `"CDT"` is not a key, so:

- `wledTzForIana("CDT")` → `kWledTzUtc` (0) — **UTC**.
- `tzHealFor(...)` ([controller_defaults_healer.dart:127-131](../lib/features/wled/controller_defaults_healer.dart#L127-L131))
  → `idx` is null → falls through to `TzHeal.offset(phoneOffset)` — a **fixed numeric offset**, which discards
  DST. A controller healed that way is correct until the DST boundary and then an hour off.

**This is a split population, not a one-off.** Of 15 users with controllers, **8 store an abbreviation**
(`"CDT"` — Ellie, Tim Kelly, Brooke, Chris Cipollone, Taps On Main, Iron Reserve, Tyler, staff\_installer) and
**7 store a proper IANA name** (`"America/Chicago"`). Whatever writes `time_zone` is inconsistent, and half the
fleet cannot resolve a WLED tz index.

**The clock-health evaluator itself reads sound** — `evaluateClockHealth` removes whole-hour offsets before
judging drift, so a wrong-tz device is classified `TZ_SUSPECT` rather than mislabeled `CLOCK_UNSET`. One gap
worth noting: `LOCATION_UNSET` requires `device.locationKnown` (both lat and lon non-null) **and** both exactly
zero. A controller whose `cfg` is unreadable — Ellie's exact situation — yields `locationKnown == false` and is
therefore **silently exempt** from the location warning. It cannot warn about the case that matters most.

---

## 6. How many others?

Full census of all 15 users with controllers (`scripts/`-equivalent run inline, read-only).

**The premise that solar is on by default for most customers is not what the data shows** — only 4 of 15 have any
solar schedule. But the concentration is worse than the count suggests:

| User | Total scheds | Solar | All-solar? | Slot over-sub | Bridge last seen |
|---|---|---|---|---|---|
| **Ellie Cochran** | 2 | **2** | **YES** | **YES** (2 sunset / 2 sunrise) | **2026-07-21 (DEAD)** |
| **Tim Kelly** | 1 | **1** | **YES** | no | 2026-08-03 ✓ |
| **Chris Cipollone** | 1 | **1** | **YES** | no | 2026-08-03 ✓ |
| **Brooke Rozenberg** | 8 | 1 | no | no | 2026-08-03 ✓ |
| Steve Stegall | 1 | 0 | — | — | 2026-08-03 ✓ |
| Chris Paschall | 0 | 0 | — | — | 2026-07-15 |
| Taps On Main | 0 | 0 | — | — | 2026-08-03 ✓ |
| Darian Brosa, Demo, Jim Dyer, Darrin Nicholas, Jeff Gruenewald, Iron Reserve, Tyler, staff | 0 | 0 | — | — | — |

### Findings

- **3 customers have zero working schedules** — Ellie, Tim Kelly, Chris Cipollone. Every schedule they own is
  solar, and no solar schedule can arm. From their side the product simply does not schedule.
- **Brooke loses 1 of 8.** Her other 7 are clock-time and should be arming normally.
- **Ellie is the only slot-over-subscription on the fleet**, and the only one whose bridge is dead.
- **Autopilot is the systemic generator.** 3 of the 4 solar schedules are `autopilot-*` ids, all named
  *"Warm White (Daily evening lighting)"*, all `Sunset` → `Sunrise`, all 7 days. **Autopilot is manufacturing
  schedules that the sync layer is guaranteed to refuse.** Every new autopilot user inherits a dead schedule.
  This is the mechanism by which the blast radius grows on its own.
- Tim Kelly's schedule (`Sunset` ON → `1:00 AM` OFF) is the mixed case: the OFF is a valid clock time but the
  whole entry is refused as a unit, so he loses the working half too.

---

## Timeline — Ellie

```
2026-05-29  install. controller doc written once, never again.
2026-05-30  applyConfig #1 → timeout. hour:25/24, en:bool, dow:0 tail rows.
2026-05-31  applyConfig #2 → timeout.
2026-07-02  presets 1/2/3/4 saved OK (relay → /json/state, which works).
2026-07-10  applyConfig #3 + #4 → "completed". hour:25/24, en:bool. LAST device contact.
2026-07-15  5b285af  — relay cfg no longer silently succeeds        [she never receives it]
2026-07-20  a75f504  — solar refused-and-warned                     [she never receives it]
2026-07-20  75daeb9  — correct positional encoding, FLAG OFF        [flag doc does not exist]
2026-07-21  bridge_status last write. errors:3173. bridge goes dark.
2026-07-22  727ef0b  — en must be INT                               [she never receives it]
2026-07-25 → 08-03   every queued command expires. ping 08-03 expires.
2026-08-01  SUNSET — nothing fires. No timer has ever existed on the device.
```

---

## What is proven vs. inferred

**Proven from her data:** both schedules are solar and enabled; the last cfg write used `hour:24/25` with `en` as
a bool; no `hour:255` / slot 8/9 row exists in her history; the write was an `applyConfig` relay command; her
bridge has been dead since 2026-07-21; her controller has two segments; `config/solar_scheduling` is absent;
`time_zone` is `"CDT"`; the fleet census counts above.

**Inferred, stated as such:** that the July-10 `applyConfig` armed nothing on the device. `status: completed`
means the bridge returned 200 — and per the codebase's own note at
[schedule_sync.dart:1211](../lib/features/schedule/schedule_sync.dart#L1211), the bridge *"routes everything but
getState/getInfo to `/json/state`, where WLED discards cfg keys and returns 200."* That is the defect `5b285af`
was written to fix. I could not confirm it against her device.

**Not established:** the actual contents of her controller's timer table right now; whether her controller has
coordinates or a correct tz; whether any LAN sync has ever occurred (LAN writes leave no Firestore trace); the
origin of the unexplained Block-E `hour:255` row; and why her controller reports `dig_octa / fw 16.0.0` when the
rest of the fleet is `skikbily / 0.15.1`.

**Collateral risk noticed, not chased:** `pushDefaultsForControllerType` states it now applies the SKIKBILY
4-bus × 100px profile to **all** controller types. Ellie is the fleet's only `dig_octa`, at 89 LEDs in two
segments. If that pusher is ever invoked against her controller it would rewrite her bus layout. Unverified
whether that path is reachable for her — flagging it because she is the one account where it would do damage.

---

## Reconciliation with `audit/ELLIE_SUNSET.md`

A parallel session produced [audit/ELLIE_SUNSET.md](ELLIE_SUNSET.md) (dated 2026-08-02) on the same incident.
We independently agree on the headline: **`config/solar_scheduling` does not exist, solar is off fleetwide, and
Ellie / Tim Kelly / Chris Cipollone have zero armable schedules while Brooke is a silent partial.** That
corroboration is worth something — two separate Firestore reads, same answer.

Two substantive differences:

**1. Its central mechanism claim is incorrect, and the error is not cosmetic.**
ELLIE_SUNSET.md §0 and §2 state the sync *"aborts before any write"*, citing the empty-armed guard's
`ScheduleSync: ABORT` debugPrint. That guard is:

```dart
if (armedSchedules.isNotEmpty && !scheduleIns.any(isRealEnabledTimer)) { ... abort ... }
```

In the all-solar case `armedSchedules` is **empty** — every schedule was refused upstream — so the guard's first
conjunct is false and **it cannot fire**. I grepped for any other empty-armable early return
(`armable.isEmpty` / `armedSchedules.isEmpty` / `enabled.isEmpty`): **there is none.** Control flow continues to
`buildCfgPayload([])` → `builtIns = []` → `padTimersToMax([])` → **eight disabled stubs** → `_pushCfgWithVerify`.

So on-LAN the sync does not abort — it **POSTs a fully-stubbed timer table**, which is a slot-reclaim write that
**erases whatever timers are on the device.** Off-LAN (Ellie today) it returns `deferredOffLan` before the POST,
which is the only reason nothing has been clobbered yet.

This matters for remediation: the prior report characterises the current state as a safe no-op. It is not. The
first time one of these three accounts gets a LAN sync, it actively wipes the controller's timer table. That
should be bench-checked before anyone "just runs a sync" on Ellie, Tim Kelly, or Chris Cipollone.

> **UPDATE 2026-08-03, later same day — the clobber is now guarded.** After I read `schedule_sync.dart`
> for this report, a parallel session added `shouldSkipClobberingWrite`
> ([schedule_sync.dart:436](../lib/features/schedule/schedule_sync.dart#L436), called at
> [:1334](../lib/features/schedule/schedule_sync.dart#L1334); working tree, **uncommitted**). It skips the cfg
> POST when `refusedCount > 0` and the payload carries no enabled entry — exactly the all-solar case. So the
> all-refused clobber described above **no longer occurs on the working tree**, and ELLIE_SUNSET.md's
> *conclusion* ("nothing is written") is now correct, via a guard that did not exist when either report was
> written. Its stated *mechanism* (the empty-armed guard) remains wrong — that guard still cannot fire when
> `armedSchedules` is empty. The distinction matters because the new guard only covers the **all**-refused case:
> a partially-armable sync still POSTs real timers and still drops anything not re-merged into that write. See
> `audit/LEASE_LEDGER_MIGRATION.md` and P0-9.

**2. It did not examine the command queue.** ELLIE_SUNSET.md reads her profile, schedules, and `bridge_status`
uptime, but not `users/{uid}/commands`. That is where the answers to "was the row ever written" and "which
encoding" actually live — the 2026-07-10 `applyConfig` carrying `hour:25`/`hour:24` with `en` as a bool (§2, §3),
and the fact that **her bridge has been dead since 2026-07-21** with every command since expiring (§1). Neither
appears in the prior report, and the second is an open service issue independent of solar.

The two documents are otherwise complementary: ELLIE_SUNSET.md goes deeper on the missing-`offTime` hypothesis it
ruled out and on the flag-believed-ON history; this one goes deeper on the wire evidence, the bridge, the
two-segment preset hazard, and the timezone population split.

---

## Immediate follow-ups (not actions taken)

1. Her bridge is down — that is a service call regardless of the solar verdict, and it blocks any remote
   remediation or device readback.
2. Do **not** trigger a LAN sync on her account until the all-stub clobber in §3 is bench-checked.
3. Tim Kelly and Chris Cipollone are in the same total-failure state and are **not** aware of it.
4. Autopilot is still generating `Sunset`/`Sunrise` schedules that cannot arm.
