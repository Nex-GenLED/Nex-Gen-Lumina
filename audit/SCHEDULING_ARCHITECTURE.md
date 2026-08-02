# SCHEDULING ARCHITECTURE — a compositional plan model

**Date:** 2026-07-31 · **Branch:** `main` @ `ebef9fd` (2.5.10+60) · **DESIGN ONLY — nothing here is
implemented, no branch was created, no file outside `audit/` was touched.**

**Scope statement, up front.** iOS submits ~Aug 11-18. **Nothing in this document ships in the
release candidate.** This is the fast-follow track. Where a phase below could ship inside two weeks,
that is a statement about its size, not a proposal to put it in the RC.

**Method.** Static read of `lib/features/schedule/`, `lib/features/autopilot/`, `lib/features/wled/`,
`functions/index.js`, `esp32-bridge/src/main.cpp`, plus the two audits completed yesterday
([LEASE_EXPOSURE.md](audit/LEASE_EXPOSURE.md), [OFF_LAN_CAPABILITY.md](audit/OFF_LAN_CAPABILITY.md))
and the bench captures under [audit/verification_evidence/](audit/verification_evidence). **No device
was driven for this document.** Everything I could not establish from code or an existing capture is
marked **UNVERIFIED** with the specific experiment that would settle it.

---

## PART 1 — THE CONSTRAINTS, MEASURED

### 1.1 Slots: there are ten, and the usable number is four

**The timer table.** WLED 0.15.1 reads exactly **10** entries from `timers.ins`
([schedule_sync.dart:286](lib/features/schedule/schedule_sync.dart#L286)):

| Index | Owner | Established at |
|---|---|---|
| 0-7 | General clock timers | [schedule_sync.dart:275](lib/features/schedule/schedule_sync.dart#L275) |
| 8 | **SUNRISE** — positional, firmware special-case | [schedule_sync.dart:282](lib/features/schedule/schedule_sync.dart#L282) |
| 9 | **SUNSET** — positional, firmware special-case | [schedule_sync.dart:283](lib/features/schedule/schedule_sync.dart#L283) |

Slots 8/9 are **positional**, not value-keyed: `checkTimers()` special-cases those two indices, the
`hour` field is ignored there, and `min` is a **signed offset in minutes** (±120), not a wall-clock
minute ([sunrise_off_service.dart:17-30](lib/features/schedule/sunrise_off_service.dart#L17-L30),
[schedule_sync.dart:460-478](lib/features/schedule/schedule_sync.dart#L460-L478)). The app writes
`hour:255` to match the firmware's own serialization
([schedule_sync.dart:292](lib/features/schedule/schedule_sync.dart#L292)).

**The general pool is contended four ways**, and the accounting is spread across three files:

1. **Schedule designs** consume slots 0..N via `buildCfgPayload`, capped at 8
   ([cfg_payload_builder.dart:142](lib/features/schedule/cfg_payload_builder.dart#L142)).
2. **Lease timers** (calendar/Game Day) allocate from the *back* of the range
   ([calendar_entry_lease_manager.dart:868-883](lib/features/schedule/calendar_entry_lease_manager.dart#L868-L883)),
   and `syncAll` reserves them by shrinking the schedule budget to `kMaxWledTimers - leaseCount`
   ([schedule_sync.dart:1124-1125](lib/features/schedule/schedule_sync.dart#L1124-L1125)).
3. **The global sunrise-off** owns slot 8 outright, outside the general pool
   ([sunrise_off_service.dart:31-37](lib/features/schedule/sunrise_off_service.dart#L31-L37)).
4. **Solar schedule boundaries** claim 8/9 first-wins, cross-schedule
   ([schedule_sync.dart:493-554](lib/features/schedule/schedule_sync.dart#L493-L554)).

**The number that matters is not 8.** A schedule with an OFF time emits **two** rows — an ON at
`macro: presetId` and an OFF at `macro: 2`
([cfg_payload_builder.dart:168-193](lib/features/schedule/cfg_payload_builder.dart#L168-L193)). So
the real ceiling is:

> **Four on/off schedule pairs for the entire year — fewer once any lease is active.**

That is the single hardest constraint in this document, and it is the reason a year-out plan cannot
be "arm everything." Note also that the lease manager's own slot-demand estimate counts each
ScheduleItem as **one** slot, not two
([calendar_entry_lease_manager.dart:86-105](lib/features/schedule/calendar_entry_lease_manager.dart#L86-L105)) —
deliberately conservative in the safe direction, but the two sides of the pipe disagree about
capacity, and any new model must unify them.

**Preset ranges** (the `macro` targets):

| Range | Owner | Citation |
|---|---|---|
| 1, 3, 4, 5 | System ON presets (`NGL On/Dim/Low/Medium`) | [schedule_sync.dart:349-354](lib/features/schedule/schedule_sync.dart#L349-L354) |
| 2 | `NGL Off` — every OFF boundary fires this | [schedule_sync.dart:316-334](lib/features/schedule/schedule_sync.dart#L316-L334) |
| 10-25 | Schedule designs (16) | [schedule_sync.dart:267-270](lib/features/schedule/schedule_sync.dart#L267-L270) |
| 26-41 | Calendar leases (16) | [calendar_entry_lease_manager.dart:67-69](lib/features/schedule/calendar_entry_lease_manager.dart#L67-L69) |

### 1.2 The canonical payload shape

```jsonc
POST /json/cfg
{
  "timers": {
    "ins": [
      // slots 0-7 — general. Padded to exactly 8 with disabled stubs so every
      // push is authoritative over the whole general pool.
      {"en": 1, "hour": 19, "min": 10, "macro": 27, "dow": 16},
      {"en": 0, "hour": 0,  "min": 0,  "macro": 0,  "dow": 0},   // stub ×N
      // slot 8 — SUNRISE (hour:255 marker, min = signed offset)
      {"en": 1, "hour": 255, "min": 0, "macro": 2, "dow": 127},
      // slot 9 — SUNSET
      {"en": 0, "hour": 0,  "min": 0,  "macro": 0,  "dow": 0}
    ]
  }
}
```

Five hard-won facts encoded in that shape, each of which cost a bug:

- **`en` is a type-strict INT.** A JSON bool is stored as `0` = disabled. Curl-proven 2026-07-22 on
  vid 2507300 ([schedule_sync.dart:303-312](lib/features/schedule/schedule_sync.dart#L303-L312)).
  Ten weeks of lease timers were silently disabled by exactly this
  ([LEASE_EXPOSURE.md §1.4](audit/LEASE_EXPOSURE.md)).
- **`dow` is Mon=bit0..Sun=bit6**, corrected 2026-05-19 from a wrong Sun=bit0 assumption
  ([schedule_sync.dart:590-594](lib/features/schedule/schedule_sync.dart#L590-L594)).
- **Padding is mandatory.** WLED merges `timers.ins` by index and never clears slots beyond the
  pushed array's length, so a shrinking schedule set leaves stale timers armed in high slots
  ([schedule_sync.dart:297-302](lib/features/schedule/schedule_sync.dart#L297-L302)).
- **The readback compacts.** The controller echoes enabled real entries + the two solar sentinels and
  **drops** disabled stubs, so sent-index ≠ readback-index and per-index comparison is invalid
  ([timer_landing.dart:22-27](lib/features/schedule/timer_landing.dart#L22-L27)).
- **A preset only carries master power if psaved with `ib: true`.** Without it WLED stores segments
  only and the preset loads DARK from a master-off strip
  ([schedule_sync.dart:356-360](lib/features/schedule/schedule_sync.dart#L356-L360)).

### 1.3 `start` / `end` — never written, and this is the cheapest lever available

**VERIFIED: the app never writes them.** A grep for `'start'` / `'end'` across `lib/features/schedule/`
returns **zero** hits in any timer path — every hit in `lib/` is a *segment* boundary
(`lumina_custom_effects.dart`, `channel_power_payload.dart`, `hardware_config_screen.dart`,
`wled_service.dart:1186`), a different field entirely. `buildTimerEntry`
([cfg_payload_builder.dart:93-123](lib/features/schedule/cfg_payload_builder.dart#L93-L123)) and
`buildSolarTimerEntry` ([schedule_sync.dart:464-478](lib/features/schedule/schedule_sync.dart#L464-L478))
emit exactly five keys: `en`, `hour`, `min`, `macro`, `dow`.

**VERIFIED: the firmware supplies them and defaults to the whole year.** Bench readback 2026-07-30
([post_session_cfg.json](audit/verification_evidence/post_session_cfg.json), re-confirmed in
[lease_exposure_bench_cfg_2026-07-30.json](audit/verification_evidence/lease_exposure_bench_cfg_2026-07-30.json)):

```json
{"en":1,"hour":19,"min":10,"macro":27,"dow":16,
 "start":{"mon":1,"day":1},"end":{"mon":12,"day":31}}
```

**This is the mechanism behind the single-date-lease-recurs-weekly bug.** A lease's `dow` is a single
weekday bit ([calendar_entry_lease_manager.dart:999-1003](lib/features/schedule/calendar_entry_lease_manager.dart#L999-L1003)).
With `start`/`end` spanning the full year, a "Christmas Day" row is indistinguishable from "every
Wednesday, forever." The only thing that stops it is the app-side expiry sweep — which requires the
app to be open, on the home network, within the window ([OFF_LAN_CAPABILITY.md §2.4.4-5](audit/OFF_LAN_CAPABILITY.md)).

**A date-bounded row costs no extra slot.** It is the same five-key row plus two nested objects.
That is why this is the highest value-per-hour change in the entire design.

**What is NOT established.** The following are **UNVERIFIED** from this repository — the app has
never written these fields, so there is no code and no capture that exercises them:

| Question | Status | Why it matters |
|---|---|---|
| Are the bounds inclusive on both ends? | **UNVERIFIED** | An exclusive `end` silently drops the event's own day |
| Are they year-agnostic (month/day only, no year)? | **Strongly implied** — the serialization has no year field — but **UNVERIFIED** behaviourally | Determines whether a 2027 event can be armed in 2026 at all |
| Does `start == end` gate to exactly one day? | **UNVERIFIED** | This is the whole single-date-event mechanism |
| Does `end < start` wrap the year boundary? | **UNVERIFIED** | Required for a Dec 20 → Jan 5 holiday season |
| Is an out-of-range value clamped, rejected, or stored? | **UNVERIFIED** | Determines whether a bad write fails loud or quiet |

**The experiment that settles all five** (bench, ~2h, on 192.168.1.150 — the `cfg-truth` and
`fire-test` bench cases already exist for this shape):

1. POST a row with `start:{mon:M,day:D}`, `end:{mon:M,day:D}` where M/D is *today*, `dow:127`,
   `hour` = now+2min, `macro:1`. Observe: does it fire? → inclusivity + single-day gating.
2. Repeat with M/D = *tomorrow*. Observe: does it fire today? → exclusivity of `start`.
3. POST `start:{mon:12,day:20}`, `end:{mon:1,day:5}`. Read back. Does the firmware store it verbatim,
   normalize it, or reject it? → wrap behaviour.
4. POST `start:{mon:13,day:40}`. Read back. → clamp/reject/store.
5. Reboot after each and re-read. → does it survive the flash commit intact.

Until step 1 passes, **no phase below that depends on date bounding should be scheduled.** Several
conclusions this month were overturned by measurement; this one is unmeasured.

### 1.4 cfg writes are LAN-only — what that means for a year-out plan

The bridge's entire command vocabulary is three branches
([main.cpp:815-825](esp32-bridge/src/main.cpp#L815-L825)): `getState` → `GET /json/state`, `getInfo`
→ `GET /json/info`, `ping` → local ack, **everything else** → `POST /json/state`. There is no cfg
case. The app mirrors that: `supportsCfgWrites` is literally `webhookUrl.isNotEmpty`
([cloud_relay_repository.dart:419](lib/features/wled/cloud_relay_repository.dart#L419)), and
`applyConfig` **throws** rather than returning `false`, because `false` reads as "retry"
([cloud_relay_repository.dart:436-446](lib/features/wled/cloud_relay_repository.dart#L436-L446)).
Every account in production is on bridge mode — **zero webhook users**
([LEASE_EXPOSURE.md §1.3](audit/LEASE_EXPOSURE.md)).

**Consequences the design must absorb, not wish away:**

1. **The plan lives in Firestore; arming requires physical presence.** Any year-out feature is a
   *planning* feature by default and a *firing* feature only after an on-LAN reconciliation.
2. **There is no automatic re-arm on LAN return.** The one LAN-connect listener runs solar cleanup
   only, which short-circuits on accounts without solar schedules and latches a once-per-account flag
   afterward ([schedule_providers.dart:229-233, :252, :254-270](lib/features/schedule/schedule_providers.dart#L229-L233)).
   Both the in-app copy and [ESP32_Bridge_Setup_Guide.md:67](docs/ESP32_Bridge_Setup_Guide.md#L67)
   promise an automatic sync that does not exist. **The new model must not inherit that promise
   without building it.**
3. **A bridge customer may never be on-LAN.** The value proposition sold to them is that they never
   need to be home ([OFF_LAN_CAPABILITY.md §3.1](audit/OFF_LAN_CAPABILITY.md)). Weeks is plausible;
   indefinitely is possible.
4. **Therefore: the base layer must be armed permanently and must be a safe standalone.** Whatever
   happens to the event layer, the lights must land somewhere sane using only what is already on the
   controller. This constraint drives the entire Part 2 design.

**Do not design around cfg-over-bridge.** It costs ~30-35h *and* requires an OTA mechanism that does
not exist in the firmware at all ([OFF_LAN_CAPABILITY.md §5](audit/OFF_LAN_CAPABILITY.md);
[main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372) registers six routes, none an update path).

### 1.5 What DOES work remotely — and it is the opening for the unknown-end-time problem

`/json/state` is fully relayed, in both directions, including **preset load**:

| Operation | Payload | Citation |
|---|---|---|
| Load preset N | `{"ps": N}` | [cloud_relay_repository.dart:623-626](lib/features/wled/cloud_relay_repository.dart#L623-L626) |
| Save preset N | `{…, "psave": N}` | [cloud_relay_repository.dart:601-620](lib/features/wled/cloud_relay_repository.dart#L601-L620) |
| Power / brightness / colour / effect | `/json/state` | [OFF_LAN_CAPABILITY.md §1.2](audit/OFF_LAN_CAPABILITY.md) |

**And a Cloud Function can inject one without the app running.** Three facts compose:

1. The bridge polls `SELECT * FROM commands WHERE status == "pending" LIMIT 5` every **1000 ms**
   ([main.cpp:686-697](esp32-bridge/src/main.cpp#L686-L697),
   [config.h.example:61](esp32-bridge/src/config.h.example#L61)). The query is **author-agnostic** —
   it does not care who wrote the document.
2. `executeWledCommand` is an `onDocumentCreated` trigger on `users/{userId}/commands/{commandId}`
   that, in bridge mode, deliberately does nothing and lets the ESP32 pick the command up
   ([functions/index.js:318, :340-341](functions/index.js#L318)).
3. `onSchedule` cron functions already exist and run in this project
   ([functions/index.js:1158](functions/index.js#L1158), `scheduledDataCleanup`).

> **Therefore: a Cloud Function cron can cause a specific preset to load on a customer's controller,
> at an arbitrary moment, with no cfg write, no app running, and no LAN presence.** Round-trip is
> ~5-10s typical per the routing doc. **This is the mechanism that makes an unknown end time
> tractable.** It is stated here as a capability; §2d assesses whether to depend on it (answer: only
> as an accelerator, never as the guarantee).

### 1.6 Machinery to generalize, not replace

The instinct to rewrite this subsystem is wrong. Five pieces already do most of the hard work and
have bench evidence behind them:

| Existing | What it already solves | Where it goes in the new model |
|---|---|---|
| **Slot leasing** — 48h window, promote/sweep every 5 min, slot + preset allocation, soft-eviction of recurring items ([calendar_entry_lease_manager.dart:71-72, :779-808, :868-899](lib/features/schedule/calendar_entry_lease_manager.dart#L71-L72)) | Rolling materialization of dated events into a scarce slot table | **Becomes the Materializer** (§2e). Generalize the window from a fixed 48h to a budget-driven horizon; replace hash-modulo allocation with deterministic ordering |
| **`pushCfgWithVerify`** — single POST, patient poll through the multi-minute post-commit stall, content readback, three terminal outcomes ([schedule_sync.dart:144-250](lib/features/schedule/schedule_sync.dart#L144-L250)) | Never trusting a 2xx; distinguishing confirmed / mismatch / notConfirmed | **Becomes the only device write primitive.** Every arm goes through it |
| **`SchedulePriority`** — 5-tier resolver, user > holiday > gameDay > neighborhood > baseline ([schedule_priority_resolver.dart:26-55](lib/features/schedule/schedule_priority_resolver.dart#L26-L55)) | Autopilot-vs-autopilot conflicts, silently and predictably | **Becomes the layer precedence table** (§2a/2b). Its own Phase-2 handoff note at [:83-90](lib/features/schedule/schedule_priority_resolver.dart#L83-L90) *is* this design's §2a |
| **Game Day phase machine** — ESPN poll, `final` detection, 30-min countdown, **and an estimated-duration + 60-min fallback** ([game_day_autopilot_service.dart:601-653](lib/features/autopilot/game_day_autopilot_service.dart#L601-L653)) | The unknown-end-time problem, **already solved conceptually** — but only in the app process (and a background isolate) | **Becomes the signal source** (§2d). The design's job is to move its guarantee onto the controller |
| **Solar handling + sunrise-off sentinel** — positional slots 8/9, absolute-state OFF macro 2, idempotent by construction ([sunrise_off_service.dart:39-43](lib/features/schedule/sunrise_off_service.dart#L39-L43)) | A controller-resident daily safety net that fires with the app closed | **Becomes the fail-safe floor** (§2d, §3.1). Its "absolute state load, never a toggle" property is the reason double-firing is harmless |

That last row deserves emphasis. **The sunrise-off already is a fail-safe.** Every design below leans
on the same property: *loading an absolute-state preset twice is a no-op, so a redundant safety row
can never do harm.*

---

## PART 2 — THE MODEL

### 2a. Layers

Three layers, evaluated top-down, plus a transient fourth.

```
  ┌─ MANUAL (transient) ── user tapped a pattern right now. Not planned, not
  │                        armed, survives until the next boundary from below.
  ├─ EVENT ────────────── bounded windows on specific dates. Game Day,
  │                        Christmas, a party. Multiple per day allowed.
  ├─ SEASON ───────────── a date-range variation of the base. "Warm white at
  │                        4:45pm, Nov 1 – Feb 28." Zero, one, or many.
  └─ BASE ─────────────── everyday behaviour. Exactly one, always armed,
                          always complete. The floor.
```

**BASE is special and non-optional.** It must:
- be a complete specification of every night (an ON boundary and an OFF boundary);
- be armed on the controller **permanently**, never evicted, never materialized-and-released;
- consume at most **two general slots + the two solar slots**.

That reservation is what makes §1.4's constraint survivable: however badly the event layer fails, a
controller that has ever been reconciled once holds a working everyday schedule.

**SEASON and EVENT are both date-bounded**, and both express that bounding through the *same*
mechanism — `start`/`end` on the timer row (§1.3), pending the bench experiment. A season is
conceptually just a low-priority, long-window event; keeping them as distinct user-facing concepts is
a UX choice, not a model requirement. The materializer treats them identically.

**Precedence when layers overlap.** Higher layer wins **for the duration of its window only**. A
layer does not "replace the day" — it replaces a *time interval*. This is the explicit break from
today's behaviour, which the current resolver documents as a known limitation:

> "**Whole-night replacement is the v1 behavior.** When a Game Day entry is written to a date where a
> Warm White recurring rule (sunset→sunrise) is active, the Game Day entry takes the entire night."
> — [schedule_priority_resolver.dart:75-81](lib/features/schedule/schedule_priority_resolver.dart#L75-L81)

The new model composes instead. For a night with base `sunset → sunrise` warm white and an event
`19:00 → 22:30` Game Day, the compositor emits the sandwich:

```
  sunset ──[base]── 19:00 ──[event]── 22:30 ──[base]── sunrise
```

**What happens the moment an override ends.** This is the question that makes or breaks the feel of
the system, and there is exactly one correct answer:

> **An override never "restores" anything. It ends, and the compositor emits whatever the layer
> *below* specifies for that instant.**

Restoring implies remembering prior device state — which is app-side belief, which is the failure
class that produced every bug in Part 3. The boundary at 22:30 is not "undo Game Day"; it is a
first-class row that says "at 22:30, load the base layer's design." It is armed on the controller
like any other row. If the app is dead, the phone is in another state, and the internet is out, the
lights still go warm white at 22:30, because a timer row said so.

**Cost accounting.** Each interval boundary is one row. The sandwich above costs: base-ON (solar slot
9), event-ON, event-OFF-to-base, base-OFF (solar slot 8) = **2 general slots** for a one-event night.
A two-event night costs 4. This is why §2e's budget arithmetic is load-bearing.

### 2b. Priority

**Recommendation: explicit layer tier first, then specificity, then most-recently-created — in that
order, and surfaced in the UI.**

Resolution order for two candidates on the same date:

1. **Layer tier.** MANUAL > EVENT > SEASON > BASE. Non-negotiable and structural.
2. **Within EVENT: explicit priority tier**, inherited directly from the existing enum —
   user-authored > holiday > gameDay > neighborhoodSync
   ([schedule_priority_resolver.dart:26-51](lib/features/schedule/schedule_priority_resolver.dart#L26-L51)).
   This already exists, already ships, and already encodes real product decisions (holidays beat Game
   Day on a Christmas Day NBA game).
3. **Within the same explicit tier: specificity — the narrower window wins.** A 3-hour event beats an
   all-evening event. This is the rule that makes "Game Day runs tonight, then warm white" work
   without the user thinking about ordering.
4. **Still tied: most-recently-created wins**, and the loser is shown, not silently dropped.

**Why this order, and why not the alternatives:**

- **Explicit-priority-only** fails because most users will never set a priority. The system then has
  no answer for the common case and falls back to something arbitrary — which is exactly the
  "scheduling feels unpredictable" complaint.
- **Specificity-first** (before explicit tier) fails on the case the current resolver was built to
  handle: a 30-minute neighborhood sync would beat an all-day Christmas entry. Wrong. Intent
  outranks duration.
- **Most-recent-only** fails because it is invisible. The user cannot see creation order in the UI,
  so the winner looks random. It is a fine *tiebreaker* precisely because by step 4 the two
  candidates are genuinely equivalent — but it is a terrible primary rule.

**The rule that removes the remaining ambiguity: overlaps are resolved by interval, not by day.** Two
events on the same evening that do not overlap in *time* do not conflict at all — both run, in
sequence. Priority is consulted only for the overlapping interval. Two events 19:00-21:00 and
20:00-23:00 produce: `[19:00 ev1] [20:00 winner] [23:00 base]`, and the loser's non-overlapping
portion (19:00-20:00) still runs. This costs slots, which §2e must budget for, but it is what a user
means by "two things tonight."

**Non-negotiable UI requirement.** Whenever resolution drops or truncates anything, the calendar must
say so on the affected date. Today, autopilot-vs-autopilot losses are dropped *silently by design*
([schedule_priority_resolver.dart:5-6](lib/features/schedule/schedule_priority_resolver.dart#L5-L6)),
and lease outcomes are `debugPrint`-only
([calendar_providers.dart:254-272](lib/features/schedule/calendar_providers.dart#L254-L272)). In a
model where two events per day is a headline feature, silent loss is not acceptable.

### 2c. Duration and "until"

Every event carries a **start trigger** and an **end condition**. Both are tagged unions.

```
StartTrigger  ::= AtClock(hh:mm)
                | AtSolar(sunrise|sunset, offsetMinutes ∈ [-120,+120])

EndCondition  ::= AtClock(hh:mm)                       // "until 11pm"
                | AtSolar(sunrise|sunset, offset)      // "until sunrise"
                | AtNextChange                         // "until whatever's next"
                | AfterDuration(minutes)               // "for 3 hours"
                | OnSignal(source, hardDeadline)       // "until the game ends"
                | Manual(hardDeadline)                 // "until I say stop"
```

Notes per variant:

- **`AtClock`** — the trivial case. One row, `macro` = the successor state.
- **`AtSolar`** — constrained by hardware: there is exactly **one** sunrise slot and **one** sunset
  slot per controller ([schedule_sync.dart:482-484](lib/features/schedule/schedule_sync.dart#L482-L484)).
  If the base layer uses both (dusk-to-dawn, the common case), **an event cannot also end at solar**
  unless it inherits the base's boundary. The compositor must detect this and either (a) reuse the
  base's existing solar row when the successor state is identical, or (b) convert the event's solar
  end to a computed clock time for that specific date, which the app can do because it already
  computes sun times ([sun_time_provider.dart](lib/features/schedule/sun_time_provider.dart)). **(b)
  is the right default**; (a) is an optimization. Note that a computed clock time is date-specific,
  which is fine — an event row is date-bounded anyway.
- **`AtNextChange`** — not a row at all. It resolves at composition time to whatever the next boundary
  is. If nothing follows, it degrades to the base layer's OFF boundary. This is the natural default
  for a quick "run this tonight."
- **`AfterDuration`** — resolves to `AtClock(start + duration)` at composition time. Stored as a
  duration so that a shifted start (a game moved to a later slot) carries the end with it.
- **`OnSignal`** — §2d. **Note the mandatory `hardDeadline` parameter.**
- **`Manual`** — same as `OnSignal` with a null source. **Also carries a mandatory `hardDeadline`.**

**The invariant that makes the whole system safe:**

> **Every end condition resolves, at materialization time, to a concrete wall-clock instant that is
> armed as a real timer row on the controller.** `OnSignal` and `Manual` resolve to their
> `hardDeadline`. There is no such thing as an event armed without an end.

An `OnSignal` event whose signal never arrives ends at its hard deadline. A `Manual` event the user
forgets about ends at its hard deadline. A user cannot create an unbounded event, because the model
has no representation for one. The hard deadline is not an error path — **it is the normal path,
which external signals are permitted to preempt.**

### 2d. The unknown end time — the core problem

**The motivating case, restated in the model:**

```
Event  "Royals Game Day"
  start:  AtClock(19:10)                      // first pitch, known
  end:    OnSignal(source: espn:game/401xxxx,
                   hardDeadline: 23:30)       // ← armed on the controller
  then:   → "Warm White" for the remainder of the night
  then:   → base layer resumes tomorrow (automatic — base was never unarmed)
```

Materialized to the device, that is **three rows**, all date-bounded to today:

| Row | Time | macro | Meaning |
|---|---|---|---|
| A | 19:10 | Game Day preset (26-41) | Event begins |
| B | 23:30 | Warm White preset | **Fallback / hard deadline** |
| C | (slot 8, permanent) | 2 = `NGL Off` | Base sunrise-off — already armed, untouched |

Tomorrow needs nothing: the base layer's rows were never removed, and rows A and B are date-bounded
so they do not recur (§1.3, pending verification).

---

**Option 1 — Fallback row at a configured time.**

*What it is:* row B above. The user picks (or accepts a default for) "if the game hasn't ended by
X, go to warm white."

*Assessment.* Works offline, works with the app closed, works with the internet down, works for a
bridge customer who is never home, requires no cloud, requires no new firmware. Cost: **one general
slot**. It is also the only one of the three that provides a *guarantee* — the other two provide
*improvements*.

*Its weakness is real:* a game that ends at 21:45 leaves Game Day colours running for 105 unnecessary
minutes. For a customer whose neighbours can see their house, that is the visible defect.

**Option 2 — Estimated duration + user "extend" / "end now".**

*What it is:* `AfterDuration` seeded from the existing per-sport `estimatedDuration`
([game_day_autopilot_config.dart](lib/features/autopilot/game_day_autopilot_config.dart), consumed at
[game_day_autopilot_service.dart:625-627](lib/features/autopilot/game_day_autopilot_service.dart#L625-L627)),
with in-app controls to push the deadline out or collapse it to now.

*Assessment.* The "end now" control is **free and should ship regardless of which option wins** — it
is a `{ps:N}` write, which works over the bridge from anywhere (§1.5). The "extend" control is
**not** free: extending the deadline means rewriting row B, which is a **cfg write**, which is
LAN-only. So extend works at home and silently fails away — the exact asymmetry that produces
false-success bugs.

*Mitigation, if extend is wanted off-LAN:* arm row B at the **latest plausible** end (23:30) rather
than the estimate, and let the *early-out* mechanisms shorten it. Shortening is always a `{ps:N}`,
always relayable. **Never design a control that needs to push a deadline later off-LAN.**

**Option 3 — Cloud-driven external signal.**

*What it is:* an `onSchedule` Cloud Function, running every 2-5 minutes during known event windows,
that polls ESPN, detects `status == final`, and writes a command document to
`/users/{uid}/commands/{id}` with `{"ps": <warmWhitePresetId>}`. The bridge picks it up within ~1s
and POSTs it to the controller (§1.5).

*Feasibility: HIGH, and lower-risk than it sounds.* Everything it needs exists:
- `onSchedule` is already used in this project ([functions/index.js:1158](functions/index.js#L1158)).
- The command-document contract is fully specified
  ([remote_command.dart:92-106](lib/models/remote_command.dart#L92-L106)) — `type`, `payload` as a
  **JSON string**, `controllerId`, `controllerIp`, `webhookUrl`, `status: "pending"`.
- The bridge's poll is author-agnostic ([main.cpp:686-697](esp32-bridge/src/main.cpp#L686-L697)).
- The ESPN client and its `GameStatus.final_` detection already exist and already work
  ([game_day_autopilot_service.dart:603-608](lib/features/autopilot/game_day_autopilot_service.dart#L603-L608)).

*Data source:* the same ESPN scoreboard endpoint the app uses today
(`lib/features/sports_alerts/services/espn_api_service.dart`). Moving the poll server-side is a port,
not new integration work. For non-sports events (a party, a stream) there is no data source and the
signal simply never arrives — which is a supported outcome, not a failure.

*Three failure modes, each with a defined behaviour:*

| Failure | Behaviour | Why it's acceptable |
|---|---|---|
| **Signal never arrives** (cloud down, ESPN down, bridge offline, cron missed) | Row B fires at 23:30. Lights go warm white. | This is the *normal* path. The cloud is an optimization on top of it. |
| **Signal arrives late** (game ended 21:45, function fires 23:35) | Row B already fired at 23:30. The `{ps:N}` load is idempotent — same preset, no visible change. | Preset loads are **absolute state, never a toggle** — the same property the sunrise-off relies on ([sunrise_off_service.dart:39-43](lib/features/schedule/sunrise_off_service.dart#L39-L43)). |
| **Signal arrives wrong/early** (ESPN reports final during a delay, or the API returns a stale record) | **Lights change mid-game.** This is the only genuinely bad outcome. | Mitigated, not eliminated — see below. |

*Guards against a wrong-early signal — all three required:*
1. **Two consecutive polls** must report `final` before a command is written. (The app's own logic
   already goes straight to postGame on one reading — that is acceptable in-app where a user can
   correct it, and not acceptable for an unattended cloud writer.)
2. **Never before `gameStart + minimumPlausibleDuration`.** A "final" 20 minutes after first pitch is
   an API artefact, not a game.
3. **Never write a command for an event whose window has not started**, and never more than once per
   event — guarded by a written marker on the event document, not by function-local state (Cloud
   Functions retry).

---

**RECOMMENDATION: combine Option 1 and Option 3, with Option 2's "end now" control. Option 1 is the
guarantee; Option 3 is a discretionary accelerator; Option 2's "extend" is LAN-only and deferred.**

The governing invariant:

> **The cloud signal may only ever make the transition happen EARLIER than the armed fallback. It can
> never delay it, extend it, or be required for it.**

That single rule delivers the mandatory fail-safe by construction. If the cloud, the internet, the
bridge, ESPN, and the phone all fail simultaneously, the controller still transitions to warm white
at 23:30, because a flash-resident timer row says so and the fire path has **no cloud or app
dependency whatsoever** ([OFF_LAN_CAPABILITY.md §4.1](audit/OFF_LAN_CAPABILITY.md)). The worst
possible outcome of total cloud failure is *slightly stale lights for a couple of hours* — not wrong
lights, not dark lights, not lights stuck on until someone opens the app.

**One caveat that must be recorded, because it is the only counter-example to the fail-safe claim:**
if the controller suffers a power cut during an internet outage, WLED may boot with no reachable NTP,
never set its clock, and fire **nothing** — including the fallback row
([OFF_LAN_CAPABILITY.md §4.2](audit/OFF_LAN_CAPABILITY.md)). The firmware claim behind this ("WLED
only re-attempts NTP on boot", [controller_defaults_healer.dart:13-17](lib/features/wled/controller_defaults_healer.dart#L13-L17))
is an app-side comment about 0.15.1, **UNVERIFIED against firmware source**. It is the same
outstanding bench test flagged in yesterday's audit, and it is a precondition of this design's safety
argument, not merely of a marketing claim.

### 2e. Materialization

**Two representations, one direction of flow.**

```
   PLAN (Firestore, unbounded, up to a year+)
        │
        │  materialize(plan, now, deviceCapabilities) — a PURE function
        ▼
   DESIRED DEVICE STATE (≤10 timer rows + the presets they reference)
        │
        │  reconcile(desired, readback) — diff, then write, then verify
        ▼
   DEVICE (flash-resident, executes autonomously)
```

**The plan is the source of truth. The device is a cache. The app is neither** — it is the process
that reconciles them, and it must hold no authoritative state of its own. Every schedule bug in this
codebase's history came from violating that last clause.

**The arming window is budget-driven, not time-driven.**

The obvious design — "arm the next 14 days" — is wrong here, because the constraint is slots, not
time (§1.1). A user with a busy December would blow the budget in three days; a user with one event
in March would waste a 14-day horizon. The correct rule:

> **Arm the base layer permanently, then fill the remaining general slots with the soonest-starting
> events, in resolution order, until the budget is exhausted.**

Budget arithmetic, per controller:

```
  total general slots                       8
  − base layer clock rows                  −2   (0 if base is fully solar)
  = event budget                            6   rows

  each event costs 1 row (its start) + 1 row (its resolved end)
    …unless the end coincides with an existing boundary, in which case 1
  ⇒ typical capacity: 3 concurrent events, or 2 events + headroom
```

Slots 8/9 are reserved for the base layer's solar boundaries and the global sunrise-off, and are
never available to events (§2c's constraint on `AtSolar` end conditions).

**Refresh triggers.** The materializer runs on: app foreground; any plan edit; LAN-connect (the
listener at [schedule_providers.dart:229-233](lib/features/schedule/schedule_providers.dart#L229-L233)
**widened** to actually re-sync, which is the fix already recommended in
[OFF_LAN_CAPABILITY.md §2.3](audit/OFF_LAN_CAPABILITY.md)); and a periodic tick, reusing the existing
5-minute sweep ([calendar_entry_lease_manager.dart:72](lib/features/schedule/calendar_entry_lease_manager.dart#L72)).
Because the function is pure and idempotent, running it too often costs nothing but a readback.

**When the user is away longer than the horizon.** State it plainly, because this is where the
promise gets broken today:

- The **base layer keeps running**, indefinitely, correctly. It was armed once and never released.
- **Season layers keep running** *if* they were date-bounded onto the device before the user left —
  which a `start`/`end` row makes possible for a season of any length, at a cost of 2 slots. This is
  the second big win from §1.3: a Nov 1 – Feb 28 season is *one materialization*, not a rolling one.
- **Events beyond the horizon do not fire.** There is no way around this without cfg-over-bridge.
- **The UI must say so.** A single surface — "Your plan is armed through **December 14**" — with
  events past that date visibly marked as *planned, not armed*. This is the honest version of the
  promise the setup guide currently makes falsely
  ([ESP32_Bridge_Setup_Guide.md:67](docs/ESP32_Bridge_Setup_Guide.md#L67)).

**Reconciling a materialized row against a changed plan.** The materializer emits a **desired set**,
not a diff. Reconciliation is:

1. Read the device: `/json/cfg` timer table **and** `/presets.json`.
2. Compute the desired set from the current plan.
3. Diff. A row matches only if the timer fields **and** the referenced preset's content digest match.
4. Write the whole padded 10-entry array (the existing authoritative-push mechanism), then verify by
   readback through `pushCfgWithVerify`.
5. Record the outcome per row (§3.1).

**Slot allocation must be deterministic and explainable. The current one is neither.** Lease preset
IDs are allocated by `dateKey.hashCode.abs() % 16` with linear probing
([calendar_entry_lease_manager.dart:890-899](lib/features/schedule/calendar_entry_lease_manager.dart#L890-L899)).
That is unexplainable to a user, unreproducible across Dart versions (`String.hashCode` is not a
documented stable hash), and makes "why did my event lose its slot?" unanswerable. Replace with:

> **Sort the desired rows by (resolution order, then start instant, then a stable event id). Assign
> slots in that sorted order, base layer first.** Assign preset IDs from the 26-41 pool by the same
> ordering.

Two consequences worth naming: the mapping becomes reproducible on any machine given the same plan
(directly testable in the pure-Dart bench harness), and eviction becomes a sentence a support person
can say out loud — *"your Dec 24 event is armed; your Dec 26 event is planned but not armed, because
Dec 24 and Dec 25 come first and the controller holds three."*

**Eviction is by the same ordering, and it is loud.** Today an overflow surfaces as a generic "8/8
slots full — delete an old schedule"
([schedule_sync.dart:1128-1130](lib/features/schedule/schedule_sync.dart#L1128-L1130)), and lease
overflow opens an eviction dialog
([eviction_picker_dialog.dart](lib/features/schedule/eviction_picker_dialog.dart)). In the new model,
overflow is *normal and expected* — a year-out plan will always exceed 8 slots — so it must never
read as an error. It reads as the arm-horizon date.

---

## PART 3 — RELIABILITY

### 3.1 Making a failed arm impossible to mistake for a success

The audits identify the following distinct instances of reporting success for work not done. Six is
the right order of magnitude; I list the ones with a citation rather than asserting a count:

| # | Instance | Citation |
|---|---|---|
| 1 | Every off-LAN cfg write since the bridge shipped reported success while changing nothing (now guarded) | [cloud_relay_repository.dart:421-435](lib/features/wled/cloud_relay_repository.dart#L421-L435) |
| 2 | `_writeZeroedSlot` returns `true` for a write it skipped on the feature flag | [calendar_entry_lease_manager.dart:1139-1147](lib/features/schedule/calendar_entry_lease_manager.dart#L1139-L1147) |
| 3 | Off-LAN lease returns `LeaseResult.leased` and is never retried | [calendar_entry_lease_manager.dart:636-643](lib/features/schedule/calendar_entry_lease_manager.dart#L636-L643), [:793](lib/features/schedule/calendar_entry_lease_manager.dart#L793) |
| 4 | Profile solar sync: green "Solar Sync Complete" on the off-LAN branch that skipped the push (F-8) | [edit_profile_screen.dart:236-239](lib/features/site/edit_profile_screen.dart#L236-L239) |
| 5 | Pixel-walk wizard advances on a discarded save (F-5) | [VERIFICATION_REPORT.md:294](audit/VERIFICATION_REPORT.md#L294) |
| 6 | Commercial schedule controls report "All channels paused" etc. while unreachable (F-6) | [FEATURE_STATUS_MATRIX.md:474](audit/FEATURE_STATUS_MATRIX.md#L474) |
| 7 | Install flow reports success on a swallowed failure | [P0-5_EXPOSURE.md:274](audit/P0-5_EXPOSURE.md#L274) |

**Every one of these has the same shape: a `bool` return that means "I did not hit an exception."**

Three structural rules, which together make the class unrepresentable:

**Rule 1 — no boolean device-write returns anywhere in the scheduling subsystem.** The type is
already correct and already shipping — `CfgPushOutcome { confirmed, mismatch, notConfirmed }`
([schedule_sync.dart:129-142](lib/features/schedule/schedule_sync.dart#L129-L142)) — plus the
off-LAN branch's fourth state, `deferredOffLan`
([schedule_sync.dart:1219-1223](lib/features/schedule/schedule_sync.dart#L1219-L1223)). Generalize it
to a four-state `ArmOutcome` and make it the **only** return type of any function that touches the
controller. A function that returns `true` because a flag told it to skip
(instance 2) cannot typecheck.

**Rule 2 — `armed` is a device-derived fact, never an app-side assertion.** Each materialized row
carries:

```
  ArmState ::= plannedOnly      // beyond the horizon; correctly not on the device
             | armPending       // desired, write not yet attempted or deferred off-LAN
             | armedVerified    // present in a readback, timer AND preset digest matched
             | armFailed        // write attempted, verification failed — with the reason
             | drifted          // was verified, a later readback disagrees
```

**`armedVerified` is settable only by the reconciler, only from a readback.** This kills instance 3
by construction: an off-LAN lease lands in `armPending`, which is visibly not armed, and the
retry loop is the ordinary reconciler rather than a special-case sweep path that skips
already-registered keys.

**Rule 3 — the atomic unit is (timer row + its preset), never the row alone.** This is the live P1 in
[LEASE_EXPOSURE.md §4.1](audit/LEASE_EXPOSURE.md): `activeLeaseTimers()` re-arms a timer with
`en:1` from the SharedPreferences registry without re-saving its preset
([calendar_entry_lease_manager.dart:1198-1225](lib/features/schedule/calendar_entry_lease_manager.dart#L1198-L1225)),
so an app upgrade can pair a new timer with an old broken preset and fire **dark**. In the new model a
row is `armedVerified` only when the timer fields match **and** the referenced preset's stored
definition matches the desired digest. A mixed pair is `drifted`, and `drifted` self-heals on the
next reconcile.

**Also required, and cheap:** extend `timersInsLanded` to compare `start`/`end` once they are being
written. Today it deliberately ignores them — *"WLED returns extra keys (start/end/mon/day)... only
the fields we control are compared"*
([timer_landing.dart:40-41](lib/features/schedule/timer_landing.dart#L40-L41)). The moment we control
them, a firmware that clamps or drops a date bound would verify green. **This is a prerequisite of
Phase 0, not a follow-up.**

**One more existing gap to close:** `isRealEnabledTimer` excludes `hour == 255`
([timer_landing.dart:11-17](lib/features/schedule/timer_landing.dart#L11-L17)), so **solar rows are
never readback-verified at all** — including the global sunrise-off, which is the base layer's OFF
boundary for most customers. A separate solar comparator (match slot position 8/9, `en`, `min`
offset, `macro`, `dow`) is needed before the base layer can claim verification.

### 3.2 Self-healing from device state, never from cached belief

The bug catalogue is unusually consistent, and each entry names a specific thing not to do:

| Bug | Root cause | Rule it generates |
|---|---|---|
| dow off-by-one ([:590-594](lib/features/schedule/schedule_sync.dart#L590-L594)) | Assumed encoding, unverified | Encodings are bench facts with a capture, not assumptions |
| `en` bool-vs-int ([:303-312](lib/features/schedule/schedule_sync.dart#L303-L312)) | 2xx trusted as confirmation | Never trust a 2xx; content-verify (already done) |
| Orphaned high slots ([:297-302](lib/features/schedule/schedule_sync.dart#L297-L302)) | Partial writes | Every push is authoritative over the full table (already done) |
| Name-only preset predicate ([:362-386](lib/features/schedule/schedule_sync.dart#L362-L386)) | Identity used as a proxy for content | Predicates assert **content**, never names |
| Mixed timer/preset pair ([LEASE_EXPOSURE §4.1](audit/LEASE_EXPOSURE.md)) | Two halves written at different times | Atomic pair (Rule 3 above) |
| Stale lease presets 26/28/29/30/41 ([LEASE_EXPOSURE §3.2](audit/LEASE_EXPOSURE.md)) | Nothing owns cleanup of a range | The desired set owns **every** slot in its ranges, including deletions |

**The reconciler design that satisfies all six:**

- It reads before it writes, every time. There is no "we believe this is already correct, skip."
- Its skip predicate — the optimization that avoids needless psaves, which matter because *a psave
  applies its state live and is therefore a visible disruption*
  ([schedule_sync.dart:374-377](lib/features/schedule/schedule_sync.dart#L374-L377)) — compares a
  **content digest**, never a name and never a cached flag.
- It owns the full managed ranges: general slots 0-7, solar slots 8/9, presets 1-5, 10-25, 26-41.
  Anything in those ranges not in the desired set is **explicitly cleared**. That is the mechanism
  that would have prevented the five orphaned lease presets, and it must be scoped exactly (the
  existing 10-25 deletion sweep at [schedule_sync.dart:931-933](lib/features/schedule/schedule_sync.dart#L931-L933)
  is the right shape, applied to too narrow a range).
- **The registry is not authoritative.** Today the lease registry lives in SharedPreferences
  ([calendar_entry_lease_manager.dart:74](lib/features/schedule/calendar_entry_lease_manager.dart#L74))
  and survives app upgrades, which is precisely how the mixed-pair bug crosses builds. In the new
  model the plan is in Firestore, the truth is on the device, and local storage holds **only** a
  cache that any disagreement resolves against the device.

### 3.3 Observability — what must be reported

**Today: nothing.** The healer's entire output is a `HealReport` of booleans consumed by
`debugPrint`; there is no Firestore write, no analytics event, no fleet telemetry anywhere in
[controller_defaults_healer.dart](lib/features/wled/controller_defaults_healer.dart). Bridge liveness
heartbeats every 30s ([main.cpp:983-1024](esp32-bridge/src/main.cpp#L983-L1024)), so **a bridge can
be perfectly green while the controller behind it holds unhealed presets, a dead NTP host, and stale
timers** ([OFF_LAN_CAPABILITY.md §3.3](audit/OFF_LAN_CAPABILITY.md)). Yesterday's lease assessment
had to state "which build the three exposed accounts run is **UNVERIFIED** — there is no per-user
build telemetry."

**Proposed: `/users/{uid}/controller_health/{controllerId}`, written by the app after every
reconcile.** Minimum viable field set:

| Field | Why |
|---|---|
| `lastReconciledAt`, `lastReconcileOutcome` | Distinguishes "healthy" from "never checked" — the distinction that does not exist today |
| `appVersion`, `wledVersion`, `wledVid`, `bridgeFirmwareVersion` | The 0.15.4 stall regression and the +59 mixed-pair window were both **version**-scoped; neither was answerable from the fleet |
| `timerTableDigest` + `armedRowCount` | Detects drift and orphaned rows without shipping the whole table |
| `presetDigests` for the managed ranges | The one signal that would have found the five orphaned lease presets fleet-wide |
| `planVersion`, `armedThroughDate` | Closes the loop between Firestore plan and device reality; drives the UI promise in §2e |
| `clockHealth` (NTP reachable, time delta vs. phone) | The §2d caveat — a controller with an unset clock fires nothing, and today nobody would know |
| `slotBudget` (used / total / evicted count) | Turns "why didn't my event fire?" from an investigation into a lookup |

Two derived alerts are then trivial and are the actual payoff: **(a)** a controller not reconciled in
N days, and **(b)** a controller whose digest disagrees with its user's plan. Neither is possible
today at any price.

**Deliberately scoped out:** no per-fire telemetry. The controller executes autonomously and has no
channel to report a fire; adding one would require firmware. Digest-and-drift is the honest ceiling
without cfg-over-bridge.

### 3.4 Migration

**Three sources must survive**, and none of them may be deleted before its successor is verified:

| Today | Becomes | Mapping |
|---|---|---|
| `ScheduleItem[]` on `/users/{uid}` (or the subcollection, behind [schedules_subcollection_feature_flag.dart](lib/features/schedule/schedules_subcollection_feature_flag.dart)) | **BASE layer** rules; anything not daily becomes a low-priority **SEASON** | `timeLabel`/`offTimeLabel` → StartTrigger/EndCondition; `repeatDays` → dow; `wledPayload` → design; `presetId` preserved |
| `calendar_entries` map field on `/users/{uid}` ([user_service.dart:850-871](lib/services/user_service.dart#L850-L871)) | **EVENT** layer | `dateKey` → single-day window; `onTime`/`offTime` → triggers; `type`/`sourceTag` → resolution tier |
| Lease registry in SharedPreferences ([:74](lib/features/schedule/calendar_entry_lease_manager.dart#L74)) | **Discarded, not migrated** | Materialization is recomputed from the plan; the device is re-read |

**Idempotency, and the ordering that makes it safe:**

1. **Derive, don't copy.** Layer records get IDs deterministically derived from their source
   (`base:<scheduleItemId>`, `event:<dateKey>:<sourceTag>`). Re-running the migration produces
   byte-identical output. This is the same discipline as `staff_<mode>_<pin>` — deterministic IDs
   make re-runs free.
2. **Dual-read before dual-write.** The new model reads legacy shapes directly for one release. No
   Firestore migration runs until the materializer has been proven to produce the *same* device state
   as `syncAll` for the same input. That equivalence is testable offline in the pure-Dart bench
   harness (`sync-sim`), against real user documents, with no device — the highest-confidence
   verification available here and it should gate the whole project.
3. **The device is never migrated.** It is reconciled. Whatever rows exist get read, diffed against
   the desired set, and corrected. A controller carrying five orphaned lease presets converges on the
   first reconcile without anyone knowing they were there.
4. **Discard the lease registry last, and only after a verified reconcile.** Dropping it while stale
   timers are armed reproduces the §2.1 stranding scenario from
   [LEASE_EXPOSURE.md](audit/LEASE_EXPOSURE.md) — registry gone, timer armed, nothing left to clear
   it. Order: reconcile → verify → clear registry.
5. **Rollback is a flag flip.** The legacy path stays intact and callable for one release, following
   the existing feature-flag convention. Note the flag-default lesson from the lease work: a flag
   whose *code* default is `false` but whose *production* value is `true`
   ([calendar_lease_feature_flag.dart:56-63](lib/features/schedule/calendar_lease_feature_flag.dart#L56-L63))
   produced ten weeks of exposure nobody was tracking. Any new flag needs its production value
   recorded in the ledger at flip time.

---

## PART 4 — COMPETITIVE POSITIONING

Stated plainly, with the overclaiming stripped out.

### Parity — table stakes we do not currently meet

| Capability | Them | Us today | Us with this design |
|---|---|---|---|
| Plan 12 months out | Oelo, EverLights | ~48h lease window; anything further is Firestore-only and unarmed | ✅ Plan a year; arm a rolling budget-driven window |
| 365-day calendar | Trimlight | Calendar UI exists; date-bounded firing does not (§1.3) | ✅ |
| Date-bounded / seasonal schedules | All four | **Not written at all** — every row is full-year | ✅ Phase 0 |
| Many timers | Gemstone: 64 | **8 general — realistically 4 on/off pairs** | ❌ **Still 8.** Firmware limit, not addressable in software |

**We should not claim a timer count.** Gemstone's 64 is a hardware/firmware property of their
controller. Ours is 8, and no amount of app work changes that. The honest reframing is *"you plan a
year; the controller always holds the part that's coming up"* — which is a better user story and a
worse spec-sheet line. Say the user story; do not put a number next to it.

**UNVERIFIED, and it matters for one specific claim.** I have not established whether competitors'
year-out schedules execute **on the controller** or from **their cloud**. If theirs are cloud-executed,
our "your schedules keep running through an internet outage" claim is a genuine differentiator; if
theirs are also controller-resident, it is parity. The claim itself is confirmed true for *us*
([OFF_LAN_CAPABILITY.md §4.1](audit/OFF_LAN_CAPABILITY.md) — the fire path has zero cloud/app
dependency) with the documented conditions. Do not assert the comparative half until someone checks.

### Genuinely differentiating

1. **Multiple events per day with defined priority and composition.** The layer sandwich (§2a) —
   base runs before and after the event on the same night — is the thing no one else appears to
   offer. Today we do not offer it either: whole-night replacement is documented as v1 behaviour
   ([schedule_priority_resolver.dart:75-81](lib/features/schedule/schedule_priority_resolver.dart#L75-L81)).
2. **Events with an unknown end time, with a guaranteed fallback.** "Game Day tonight, warm white when
   it's over, normal tomorrow" is not a schedule any calendar-based competitor can express. The
   fail-safe framing — *the cloud can only make it happen earlier* — is the part worth explaining to
   a dealer, because it is what makes it trustworthy rather than clever.
3. **Readback-verified arming.** The customer-visible version: *the app tells you when your schedule
   is actually on the controller, not just saved.* Every competitor's app claims saved; none that I
   can check claims verified. This is a differentiator we have **already largely built**
   ([pushCfgWithVerify](lib/features/schedule/schedule_sync.dart#L144-L250)) and do not currently
   surface.
4. **Sports-aware automation as a scheduling primitive**, not a separate mode. Game Day already
   exists; folding it into the schedule model makes it composable with everything else.

### Where we are behind, and should say so internally

- **8 slots.** Structural.
- **Off-LAN arming.** Competitors with a cloud-executed model can arm from anywhere. Ours cannot,
  until cfg-over-bridge + OTA (~30-35h + an OTA mechanism that does not exist). Our compensating
  advantage — no cloud dependency at fire time — is real, but it is a *trade*, not a free win.
- **No fleet telemetry.** Any competitor with a cloud-executed schedule knows whether it fired. We do
  not (§3.3).

---

## PART 5 — PHASING

Each phase is independently valuable, independently verifiable, and independently shippable. Nothing
here is in the RC.

### Phase 0 — Date bounding + arm-state truth · ~2 weeks · confidence **MEDIUM-HIGH**

**This is the two-week candidate, and it is the right one — with one precondition.**

| Item | Est | Confidence |
|---|---|---|
| **Bench experiment §1.3** (5 steps, must run first) | 2h | High |
| Write `start`/`end` on lease + event rows | 4h | High |
| Extend `timersInsLanded` to compare `start`/`end` (**prerequisite**, §3.1) | 3h | High |
| Solar-row readback comparator (slots 8/9) | 4h | Medium |
| `ArmOutcome` four-state return; delete boolean write returns | 8h | High |
| Fix `_writeZeroedSlot` false `true` ([:1139-1147](lib/features/schedule/calendar_entry_lease_manager.dart#L1139-L1147)) | 1h | High |
| Fix off-LAN lease `leased` → `armPending` + surface it ([:636-643](lib/features/schedule/calendar_entry_lease_manager.dart#L636-L643)) | 6h | High |
| Re-save lease preset whenever its timer is re-armed (the live P1, [LEASE_EXPOSURE §4.4](audit/LEASE_EXPOSURE.md)) | 4h | High |
| Widen the LAN-connect listener to actually re-sync ([:229-233](lib/features/schedule/schedule_providers.dart#L229-L233)) | 4h | High |
| Tests + bench verification | 8h | Medium |
| **Total** | **~44h** | |

**Assessment of date bounding as the candidate: yes, with a caveat.** It is the cheapest change with
the largest correctness payoff — it fixes the single-date-recurs-weekly bug at the root instead of
depending on an app-side sweep that requires the app open, on-LAN, in a window. It costs **zero extra
slots**. And it unlocks multi-month seasons as a single materialization, which is most of the
"year-out planning" story on its own.

**The caveat: it is gated on an unrun experiment.** If `start == end` does not gate to a single day,
or the bounds are exclusive, the whole item changes shape. **Run the 2h bench test before committing
the two weeks.** Given the month's history — "seg.gc:0" was a phantom, AudioReactive was exonerated
after being blamed, the `en` fix shipped inverted once — this is not a formality.

The rest of Phase 0 is the false-success cleanup, which is worth doing regardless of whether the
larger model ever ships, and which is a prerequisite for every phase after it.

**Bench-verifiable: entirely.** `cfg-truth`, `fire-test`, and `sync-sim` cases already exist in
[bench/bin/bench.dart](bench/bin/bench.dart). **No field data required.**

### Phase 1 — Layers, compositor, materializer · ~4-5 weeks · confidence **MEDIUM**

The model from §2a/2b/2e. Layer records in Firestore, pure `materialize()`, deterministic slot
allocation replacing hash-modulo, the arm-horizon UI, dual-read migration.

Estimate 120-160h. Confidence MEDIUM — the model is clear but the interval compositor has real edge
cases (midnight crossings, DST, an event ending after the base's sunrise boundary, a solar end
condition when both solar slots are taken). Every one of those is unit-testable without hardware,
which is what keeps confidence at MEDIUM rather than LOW.

**Requires the full model. Cannot be partially shipped** — a compositor that handles one event per
day is the current behaviour with more code.

**Bench-verifiable:** the materializer is a pure function, so equivalence against `syncAll` on real
user documents runs offline in the harness. Only the final write path needs hardware.

### Phase 2 — End conditions + fallback rows · ~2 weeks · confidence **MEDIUM-HIGH**

`EndCondition` union, the mandatory hard deadline, `AfterDuration` resolution, the "end now" control
(a `{ps:N}` — works off-LAN today, no new transport), and the fallback row for `OnSignal`/`Manual`.

Estimate 50-70h. This is where the motivating case starts working **without any cloud component** —
"Game Day tonight, warm white at 23:30, normal tomorrow" is fully deliverable at the end of Phase 2.
That makes it a good stopping point if priorities shift.

**Bench-verifiable: yes** — the fallback is an ordinary timer row; `fire-test` covers it.

### Phase 3 — Cloud early-out signal · ~2 weeks · confidence **MEDIUM**

The `onSchedule` poller, ESPN `final` detection server-side, the two-consecutive-polls and
minimum-duration guards, the once-per-event write marker, and the command-document writer.

Estimate 40-60h. Confidence MEDIUM: the mechanism is well-understood and every piece exists, but ESPN
status semantics under delays, suspensions, and doubleheaders are **UNVERIFIED** and are exactly
where a wrong-early signal comes from.

**Security prerequisite, not optional.** `controllerIp` is attacker-chosen today — the bridge takes
it straight from the command document ([main.cpp:778-779](esp32-bridge/src/main.cpp#L778-L779)).
Adding a *server-side* writer to that collection means the Cloud Function must validate the IP against
the user's registered controllers. That is item C1 from
[OFF_LAN_CAPABILITY.md §5.1](audit/OFF_LAN_CAPABILITY.md) (~3h), and it lands here rather than with
cfg-over-bridge.

**NEEDS FIELD DATA.** Whether the guards are correctly tuned cannot be established on a bench —
it requires observing real games. Ship it flag-gated, log every decision it *would* have made for a
season of Royals games before letting it write a single command.

### Phase 4 — cfg-over-bridge · blocked on OTA · confidence **LOW-MEDIUM**

Off-LAN arming. Everything the audit already costed: ~30-35h engineering, dominated by the
non-blocking stall/verify state machine on an ESP32 with a 5-minute watchdog
([OFF_LAN_CAPABILITY.md §5.2](audit/OFF_LAN_CAPABILITY.md)).

**Blocked, and the blocker is upstream of the estimate: there is no OTA.** Deploying firmware today
means physically visiting each bridge with a USB cable
([main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372) — six routes, none an update path). Whether
the current partition table even leaves room for OTA slots is **UNVERIFIED**.

**What it would unlock:** off-LAN arming (the horizon stops mattering), the healer reaching bridge
customers, and the "opens the app and it syncs itself" promise becoming true rather than a doc defect.
**What it is not:** a prerequisite for anything in Phases 0-3. Every one of those works on-LAN today.

Bundle it with F-5b part 2 (remote unpair) in one OTA campaign — the audit estimates ~8h of the 30-35h
recovered in shared verification.

### Phase 5 — Controller-health telemetry · ~1.5 weeks · confidence **HIGH**

§3.3's document plus the two derived alerts. Estimate 30-40h, high confidence — it is a Firestore
write from a path that already computes everything it needs.

**Sequencing note:** this is listed last but is arguably the highest-leverage item on the whole list,
because it is the only thing that would let anyone *verify* that Phases 0-3 actually worked in the
field. Every conclusion in yesterday's audits that ended in **UNVERIFIED** ended there for want of
this. Consider pulling it forward to run alongside Phase 1.

### Summary table

| Phase | Scope | Est | Confidence | Gate |
|---|---|---|---|---|
| **0** | Date bounding + arm-state truth | ~44h | **MED-HIGH** | **2h bench experiment §1.3 first** |
| **1** | Layers + materializer | 120-160h | MED | Phase 0 |
| **2** | End conditions + fallback | 50-70h | MED-HIGH | Phase 1 |
| **3** | Cloud early-out | 40-60h | MED | Phase 2 + `controllerIp` validation + a season of shadow logging |
| **4** | cfg-over-bridge | 30-35h | LOW-MED | **OTA, which does not exist** |
| **5** | Telemetry | 30-40h | HIGH | none — could run in parallel with Phase 1 |

### Bench vs. field

| Bench-verifiable (rig at 192.168.1.150) | Needs field data |
|---|---|
| `start`/`end` semantics — all five questions (§1.3) | ESPN status semantics under delay/suspension/doubleheader |
| Fallback row fires at its deadline | How often bridge customers actually reach LAN (drives horizon sizing) |
| Timer + preset atomic-pair verification | Whether the arm-horizon UI reads as honest or as a limitation |
| Materializer ≡ `syncAll` equivalence (pure Dart, no device) | Real slot pressure — is 4 pairs actually enough for a December? |
| Multi-row composition, midnight crossing, DST | Whether "verified arming" resonates with dealers |
| **The clock-unset-after-power-cut case (§2d caveat) — still outstanding** | |

---

## UNVERIFIED — the complete list

Every claim in this document that is not backed by code, a bench capture, or a cited audit:

| # | Claim | How to settle it |
|---|---|---|
| 1 | `start`/`end` are inclusive bounds | Bench §1.3 step 1-2 |
| 2 | `start`/`end` are year-agnostic (strongly implied by the serialization) | Bench §1.3 step 1, dated a year out |
| 3 | `start == end` gates to exactly one day | Bench §1.3 step 1 |
| 4 | `end < start` wraps the year boundary | Bench §1.3 step 3 |
| 5 | Out-of-range month/day is clamped vs. rejected vs. stored | Bench §1.3 step 4 |
| 6 | Date bounds survive the flash commit and a reboot | Bench §1.3 step 5 |
| 7 | WLED only re-attempts NTP on boot → power cut during an outage = nothing fires | **Outstanding from the prior audit.** Precondition of this design's fail-safe argument |
| 8 | ESPN `final` is reliable enough for an unattended cloud writer | A season of shadow logging (Phase 3) |
| 9 | Competitors' year-out schedules are cloud-executed vs. controller-resident | Product research — gates one marketing claim |
| 10 | The ESP32 partition table has room for OTA slots | Firmware inspection — gates Phase 4's estimate entirely |
| 11 | 4 on/off pairs is sufficient real-world slot capacity for a busy December | Field data, or a modelling pass over the 91 existing calendar entries |

---

## Findings

| # | Finding | Severity |
|---|---|---|
| 1 | Usable capacity is **4 on/off pairs**, not 8 timers — an OFF time costs a second row | Foundational constraint |
| 2 | `start`/`end` are **never written**; the firmware defaults every row to full-year. Cheapest available lever; costs zero slots | **Highest value-per-hour** |
| 3 | Date-bound semantics are **entirely unmeasured**. Phase 0 is gated on a 2h bench test | Gate |
| 4 | A Cloud Function **can** load a preset on a customer's controller with no cfg write, no app, no LAN — bridge poll is author-agnostic | Unlocks the unknown-end-time design |
| 5 | The Game Day service **already solves** unknown-end-time (ESPN final + 30min countdown + duration fallback) — but only in the app process | Generalize, don't rebuild |
| 6 | The invariant that makes it safe: **the cloud signal may only ever make the transition earlier**, never later, never required | Design keystone |
| 7 | Base layer must be permanently armed and never evicted — the only thing that survives a customer who is never on-LAN | Design keystone |
| 8 | `timersInsLanded` **deliberately ignores** `start`/`end`; writing them without extending it re-creates the false-green class | **Phase 0 prerequisite** |
| 9 | Solar rows (`hour:255`) are **excluded from readback verification entirely** — including the global sunrise-off | P1, pre-existing |
| 10 | Hash-modulo preset allocation is unexplainable and not stably reproducible; replace with ordered deterministic assignment | P2 |
| 11 | Gemstone's 64 timers is a real gap we cannot close in software — **do not put a number on the spec sheet** | Positioning |
| 12 | Telemetry (Phase 5) is the only thing that would let anyone verify Phases 0-3 worked in the field; consider pulling it forward | Sequencing |
