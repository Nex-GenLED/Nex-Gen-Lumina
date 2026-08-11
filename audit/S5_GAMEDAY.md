# S5 — GAME DAY AS FIRE JOBS

**Date:** 2026-08-08 · **Branch:** `main` @ `d48072f` (`2.5.10+66`), working tree
**Status: IMPLEMENTED, TESTED, BENCH-VERIFIED END TO END. NOT DEPLOYED.**
`functions/` + tests only. No Dart. No rules change. **No new index** — §5.

**Ships LOG-ONLY.** `config/gameday_planner.write_jobs` defaults **false**; the planner records
what it *would* fire and writes no jobs until deliberately flipped in the console.

---

## 1. THE SCOPE DECISION — #3 is out of scope, explicitly

Three implementations exist. V2's estimate cited **#2**, which has never executed in a shipped
build. **This ports #1 (`GameDayAutopilotService`).**

**`EphemeralGameSessionService` (#3) is DECLARED OUT OF SCOPE for unattended operation.** Not
skipped — excluded, with a reason:

> #3 exists to light a house when its owner **opens the app during a game already in progress**.
> Unattended operation has no analogue. There is no join, because the planner schedules from the
> game schedule before first pitch. A server-side "mid-game join" would mean firing at an
> arbitrary instant for a customer who did nothing.

**The d753ea7 lesson is respected rather than repeated.** That bug was score *celebrations*
reading only the autopilot session and being blind to the ephemeral machine. **Celebrations are
S5b and are not built here**, so that blindness has no surface in this work. If S5b ships it
MUST read both machines — recorded in §6.

> ### UI OBLIGATION — this is not optional
> The Game Day screen must state that away-from-home firing covers **scheduled starts and ends
> only** — not mid-game joins, not score celebrations. A customer whose lights came on when they
> opened the app mid-game will reasonably expect that to happen while they are away. Saying so
> in this document is not saying so to them. **Tracked as the one Dart change S5 requires.**

---

## 2. PART 1 — THE PLANNER

`planGameDayFires`, `*/5 * * * *`, us-central1.

**Cadence justification — two requirements pulling opposite ways.** A start job must exist
before the dispatcher can act: the dispatcher ticks every minute and terminally refuses a job
more than 90 s late, so with a 6-hour plan horizon every start is written hours early. The *end*
signal needs two consecutive polls, so 5 minutes confirms a real final within ~10 minutes of the
whistle — invisible to someone away. A 15-minute cadence would make that 30, which is noticeable
on a re-watch. ESPN state changes on the order of minutes, so polling faster buys nothing and
costs a request per team per tick.

### 2.2 Fire-safety — confirmed, then asserted

Game Day is inline state everywhere; `grep -rn 'psave\|loadPreset\|savePreset' lib/features/game_day lib/features/autopilot` returns nothing. **Confirmed.** But the planner does not
trust that: every payload passes `assertPayloadIsFireSafe` before a job is written, and a
failure logs `UNSAFE payload` at ERROR rather than proceeding. A test asserts every generated
payload passes and contains no `psave` / `"ps"`.

### 2.3 The saved-design carve-out — **accept effect-shaped, REFUSE per-pixel**

Not blanket refusal, not chunking, not pre-staging.

| Option | Rejected because |
|---|---|
| **Chunk it** | A per-pixel design exceeds one command (337 px / 6 KB ceiling, chunk 224). Chunking from a scheduled path has **no atomicity**: 3 of 5 chunks landing leaves the strip in neither the old design nor the new one, unattended, with nobody to correct it. S3's one-in-flight guard also makes a multi-command sequence awkward by design |
| **Pre-stage a preset** | Needs `psave`. COMMAND_SAFETY §4.2 forbids state-mutating operations on the scheduled path outright |
| **Refuse everything saved** | Most saved designs are effect-shaped and fit in one command comfortably. Refusing them would break a working case to defend against a rare one |

`savedDesignUsable` refuses when the payload is **> 4 KB**, carries a per-pixel `i` array in any
segment, is unparseable, or is not an object — each with a distinct reason. **It never
truncates.** A refusal is visible and fixable; a truncated per-pixel payload is a house lit
wrongly.

A usable saved blob ships **verbatim and is NOT re-expanded** across channels — it carries its
own multi-seg shape, and re-expanding would flatten it onto bus 0. That matches the client,
whose `selectDesign` saved branch also bypasses participation filtering.

**A saved-design refusal does NOT fall back to a generated design.** Firing something the
customer never chose is worse than not firing: they would see lighting they did not pick and
have no way to connect it to anything. Test-locked.

### 2.4 `participationForFire` — wired, first caller

S3b shipped it with no caller. The planner is it. Unusable participation **skips the fire** and
records the reason on the tick (`participation:never_resolved`, `:stale`, `:malformed`,
`:no_timestamp`), so `never_resolved` — the expected fleet-wide state until each customer next
opens the app on their LAN — counts separately from a real failure.

### 2.5 The other half of S3b — and the doubling decision

`buildParticipatingSegArray` ported to TS: one segment per participating channel, per-segment
`on: true` (the channel-2-dark fix), **no `start`/`stop`** (WLED retains install-time ranges;
the server could not know them anyway — bus ranges are `/json/cfg`, LAN-only).

> **THE EFFECT DOUBLING IS REPLICATED, DELIBERATELY.** One segment per channel each running the
> same `fx` from its own origin is what a multi-channel house sees today from every foreground
> and background apply. **Fixing it server-side only would make an unattended fire render
> differently from the identical design fired from the app** — the customer sees one thing at
> home and another away, with nothing to explain it. Whether the doubling is desirable is a
> product question; whichever way it is answered, **both paths must change together**. Flagged
> in §8, not fixed by accident.

---

## 3. PART 2 — THE END SIGNAL

`espnClient.ts` is a **port, not a new integration**: the same public, unauthenticated
scoreboard endpoint the app already calls in production. No key, no quota. It returns null
rather than throwing on an unrecognised shape — an unparseable ESPN response must skip one team
for one tick, not fail the run for every customer.

### The three guards — all mandatory, all from PERSISTED state

| Guard | Rule | What it stops |
|---|---|---|
| **1. Two consecutive finals** | `REQUIRED_FINAL_POLLS = 2`; a non-final **resets the run to 0** | A single-sample glitch ending the show mid-game |
| **2. Minimum plausible duration** | Never before `gameStart + 1.5–2 h` by sport | ESPN reporting a stale `final` from the **previous meeting of the same two teams** — the failure that fires at first pitch |
| **3. Once per event** | A written `endFiredAt` marker on `users/{uid}/game_day_sessions/{eventId}` | A retried invocation firing twice |

**All three read persisted state, never function-local variables.** Cloud Functions retry; an
in-memory counter would either lose the count (never firing) or double it (firing on one real
poll). S3's deterministic command id protects the *transport*; only a written marker protects
the *plan*. Guard 3 outranks everything, including a confirmed final — test-locked.

The reset-on-non-final is the subtle one: two finals separated by a non-final are **not** two
consecutive finals, and treating them as such would defeat the guard on exactly the flapping
case it exists for.

### Sunset — ported, not imported. And it found a client bug.

`SunUtils.sunsetLocal` ported to TS: same algorithm, same zenith, same approximations. **Ported
rather than taking a library** so `skip_day_games` decides *identically* on server and client —
a library disagreeing by minutes would skip a boundary game attended and fire it unattended,
with nothing to explain it. Agreeing with the app matters more than being astronomically better,
and it adds no dependency.

**Two bugs in my first port, both caught by the bench comparison:** I used the *sunrise*
hour-angle (`360 − acos`) with the sunset time estimate, putting "sunset" at 05:52 local; and I
double-applied the timezone offset. Corrected, the port now agrees with the shipped Dart to
within a minute:

```
                 TS port                 Dart (shipped)
2026-06-21   2026-06-22T01:47Z = 20:47   2026-06-20T20:48   ← same TIME, DIFFERENT DATE
2026-12-21   2026-12-21T22:59Z = 16:59   2026-12-21T16:59   ← identical
```

> **⚠ FINDING — `SunUtils.sunsetLocal` returns the wrong DATE in summer.** For a 21 June query at
> KC it returns **20 June** 20:48. That is the western-longitude wraparound: an evening sunset
> falls on the following UTC date, and the Dart never re-anchors. The TS port handles it
> explicitly.
>
> **The consequence in the app is that `skipDayGames` never skips in summer.** The client asks
> `gameEnd < sunset − 30 min`; with sunset a day early, a 1 pm game ending at 4 pm is compared
> against the *previous* evening and the test always fails, so a fully-daylight game is never
> skipped. Latent since the feature shipped.
>
> **This creates a deliberate, one-directional divergence:** the server *will* skip day games
> correctly; the client does not. Unattended therefore does strictly **less**, which is the safe
> direction. Replicating the bug for symmetry was considered and rejected — it would defeat the
> feature on the only path where it works. **Recommend fixing the Dart** and removing the
> divergence.

### Log-only — a flag, not a promise

`config/gameday_planner.write_jobs`, default **false**, read every tick (so the flip is instant
and reversible with no deploy). In log-only the planner does everything except write fire jobs
and session markers, appending what it would have done to `/gameday_plan_log/{YYYY-MM-DD}.rows`.

**Run it for a full Royals homestand before flipping.** ESPN semantics under delays, suspensions
and doubleheaders are UNVERIFIED, and a wrong-early `final` is the one genuinely bad outcome.

---

## 4. PART 3 — NOT BUILT

| Not built | Note |
|---|---|
| **Score celebrations** | S5b, ~12 h. Foreground-only by design today. **If built, it must read BOTH the autopilot session and the ephemeral machine** — that union is the d753ea7 fix |
| **The nightly restore row (S4)** | **Where it is needed:** the end fire returns the strip to off. If that fire never lands — bridge down at final, ESPN never reports final, planner outage — the Game Day design runs until someone intervenes. S4 is the fail-safe and this ships without one |
| **Any sync fanout** | Unchanged |
| **The shared compositor** | **GATE.** Two server dispatchers writing one house have no arbitration. S5 and any server-side sync **must not both go live** until a compositor exists — `GameDayPriorityResolver` lives in the inert background worker and has no server equivalent |

---

## 5. QUERY SCOPES AND INDEXES — heeding the S3 lesson

S3 shipped broken because a bare single-field equality at COLLECTION_GROUP scope needs its own
`COLLECTION_GROUP_ASC` exemption, and the bench's `--uid` scoping takes the plain-COLLECTION
path and **cannot reveal it**. 28/28 passed against a query shape that does not exist in
production.

**Every query in this work, stated rather than discovered:**

| # | Query | Scope | Index |
|---|---|---|---|
| 1 | `collection("users").get()` | COLLECTION, no filter | none |
| 2 | `users/{uid}/game_day_autopilot .where("enabled","==",true)` | COLLECTION, single-field equality | automatic |
| 3 | `users/{uid}/controllers.get()` | COLLECTION, no filter | none |
| 4 | `users/{uid}/game_day_sessions/{id}.get()` | document read | none |
| 5 | `users/{uid}/fire_jobs/{id}.create()` | document write | none |

**No collection-group query is used anywhere in this file, deliberately.** Iterating users and
reading each subcollection costs one extra read per user per tick and buys immunity from exactly
the class of failure that broke S3 on deploy. At 24 users that trade is obviously right; past a
few thousand it should be revisited **with the index deployed and verified READY first.**

**No index change is required by S5.**

---

## 6. VERIFICATION

### 6.1 Unit — **8 suites, 237 tests, all passing** (36 new)

Every seg-array property including the replicated doubling and the absence of `start`/`stop`;
all four saved-design refusals plus the usable case; **all three end guards** including the
exact minimum-duration boundary, non-final resetting the run, and guard 3 outranking a confirmed
final; sunset against KC in both solstices, summer-later-than-winter, and polar-day null; every
`buildGameDayPayload` branch including saved-verbatim, per-pixel refusal, and refusal *not*
falling back.

### 6.2 Bench — real compiled functions against production + `.150`

**Log-only, 5/5:**

```
planGameDayFires[LOG-ONLY]: {"usersScanned":1,"configsEnabled":1,"startsPlanned":0,
  "endsPlanned":0,"skipped":{"participation:never_resolved":1},"espnErrors":0,"errors":0}
PASS  planner ran without error
PASS  LOG-ONLY wrote NO fire jobs
PASS  enabled configs found
PASS  unusable participation SKIPPED with the reason
PASS  reason is never_resolved (bench has never published)
```

ESPN succeeded live (`espnErrors: 0`).

**End-to-end, 6/6** — planner-built payload → fire job → dispatcher → command → controller:

```
config: mlb_royals
payload: {"on":true,"bri":255,"seg":[{"id":0,"fx":3,"sx":50,"ix":128,"pal":5,...}]}
PASS  planner built a payload          PASS  payload is fire-safe
PASS  job DISPATCHED at its fireAt     PASS  command carries the Game Day payload
PASS  controllerIp named               PASS  reached the controller (completed)
bench restored, job deleted
```

That payload carries `pal`/`grp`/`spc`, so it came through the **saved-design branch** — the
carve-out was exercised on real customer data, not only in tests. Bench state was captured
before and restored after.

**Not covered:** a live `final` transition end-to-end. It needs a real game reaching final, which
is what the log-only homestand is for.

---

## 7. DEPLOY COST

| | Per day |
|---|---|
| Invocations (`*/5`) | 288 |
| Reads — users + per-user configs/controllers | ~288 × (1 + 2×N_active). At 9 enabled-config users ≈ **~5,500** |
| ESPN requests | ~288 × distinct (sport, team), cached per tick ≈ **~2,900** |
| Writes — log rows only in log-only mode | ~1 per tick with activity |

**~5,500 reads/day is ~11 % of the 50 k free tier**, on top of S3's ~2,880 and S6's ~180. Total
across the three ≈ **17 %** of free reads. Writes stay trivial until `write_jobs` is on.

**The honest costs:** a 9th Cloud Scheduler job (+$0.10/month); ESPN is unauthenticated and
unmetered but ~2,900 requests/day is real traffic against someone else's endpoint — the per-tick
cache keeps it to one request per distinct team, and if the fleet grows this needs a shared
scoreboard cache rather than per-user polling. Node 20 decommissions 2026-10-30.

**Deploy sequence:** no index step. Build with an explicit `$?` check (never piped), then
`firebase deploy --only functions:planGameDayFires`, then watch `gameday_plan_log` accumulate
for a homestand before touching the flag.

---

## 8. FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **`SunUtils.sunsetLocal` returns the wrong DATE in summer** (20 June for a 21 June query), so **`skipDayGames` never skips in summer** in the app. Latent since the feature shipped; the TS port fixes it, creating a deliberate one-directional divergence | **P1 — client bug found by porting** |
| 2 | **My first sunset port used the sunrise hour-angle** and double-applied the tz offset — "sunset" at 05:52 local. Caught only by diffing against the shipped Dart, not by any test I would have written | Method |
| 3 | **#3 (ephemeral) is out of scope, and that must be said in the UI**, not just here. A customer who has seen mid-game join will expect it away from home | **Dart change owed** |
| 4 | **The effect doubling is replicated deliberately.** Fixing it server-side only would make unattended fires render differently from app-driven ones | Design decision |
| 5 | **Saved designs: accept effect-shaped, refuse per-pixel.** Chunking has no atomicity from a scheduled path; pre-staging needs `psave`, which §4.2 forbids | Design decision |
| 6 | **A saved-design refusal must not fall back to a generated design** — firing lighting the customer never chose is worse than not firing | Design decision |
| 7 | **No collection-group query anywhere**, deliberately, at the cost of one read per user per tick. Directly answers the S3 failure | Deploy risk ↓ |
| 8 | **The shared compositor is a hard gate** on S5 and server-side sync coexisting. Neither should go live alongside the other without it | **Gate** |
| 9 | **S4 (nightly restore row) is the missing fail-safe.** If the end fire never lands, the Game Day design runs until someone intervenes | **Gate for `write_jobs`** |
| 10 | ESPN polling is ~2,900 requests/day against a third-party unauthenticated endpoint. Cached per tick; needs a shared cache before the fleet grows | P2 |

---

## 9. OPEN

1. **Run the log-only homestand.** Nothing is verified about ESPN under delays, suspensions or
   doubleheaders until a real season passes through it.
2. **Fix `SunUtils` (finding 1)** and remove the divergence.
3. **The UI sentence (finding 3)** — the only Dart change S5 requires.
4. **S4 before `write_jobs` flips** (finding 9).
5. **The compositor before S5 and sync coexist** (finding 8).
6. `tzOffsetHours` is hardcoded to −5 for the daylight filter; the user doc carries no timezone.
   A ±1 h error only matters within 30 minutes of sunset, but it should come from the profile.

---

# SHADOW-RUN CHECKPOINTS — copy-paste, 2026-08-11

Two windows, hours apart. Run from the repo root. Read-only; neither command
writes anything.

> ⚠️ Both use a PLAIN `.get()` with NO `orderBy`. An `orderBy` on a field
> some documents lack silently drops them — that is what made
> `gameday_plan_log` look empty for two days (audit/S4_RESTORE.md, 8th instance).

## WINDOW 1 — ~20:10 UTC / 3:10 PM CDT (game enters the 6h horizon)

```bash
cd "c:/Flutter Projects/Lumina V 1.6" && GOOGLE_APPLICATION_CREDENTIALS="C:/Users/honey/AppData/Roaming/gcloud/application_default_credentials.json" node scripts/_check_gameday.js start
```

**Expect:** `outside_horizon` drops to 0, and either `startsPlanned: 1` with a
`plan_start` row, or a named skip. The command prints the computed fire time
and how many minutes before first pitch (02:10 UTC) it lands.

| result | what it means |
|---|---|
| `startsPlanned: 1` + a `plan_start` row | **Good.** Fire-time computation works — the first downstream path ever to execute. Check the lead time looks sane (default 15 min before first pitch). |
| `outside_horizon: 1` still | Too early, or the game moved. Re-run in 20 min. Not a fault. |
| `start_time_passed: 1` | **Bad, and worth waking up for.** The fire time already elapsed — the planner found the game too late to act. On a live run this is a MISSED START: the house never lights. Means the horizon opened while the function was failing, or ESPN moved the start earlier. |
| `payload:*` or `unsafe_payload` | The design was refused. `payload:no_participating_channels` means participation regressed; `unsafe_payload` should be unreachable and is a real defect if seen. |
| `RECONCILES ✗` | A config vanished from the counters again. The thing the horizon counter was added to prevent. |

## WINDOW 2 — ~05:00–06:00 UTC (after ESPN reports final)

```bash
cd "c:/Flutter Projects/Lumina V 1.6" && GOOGLE_APPLICATION_CREDENTIALS="C:/Users/honey/AppData/Roaming/gcloud/application_default_credentials.json" node scripts/_check_gameday.js end
```

**Expect:** a `plan_end` row with its fire time, plus the guard state —
`consecutiveFinalPolls` per session, which is how many finals ESPN reported
before the end would have fired.

| result | what it means |
|---|---|
| `plan_end` row + `consecutiveFinalPolls >= 2` | **Good.** The two-consecutive-finals guard held and the end signal fired on a real final — the first time end detection has ever run. |
| `consecutiveFinalPolls: 1`, no `plan_end` | **Correct, mid-flight.** One final seen, waiting for the second. Re-run in 10 min. This is the guard doing its job. |
| **No `plan_end` at all, hours after the final** | **The failure mode that matters.** On a live run the house stays lit until the base layer reclaims it. Check: did ESPN ever report final (`espnErrors`), did a session exist (`startPlannedAt` set), and did window 1 actually plan a start? **No start ⇒ no session ⇒ no end** — an absent `plan_end` is EXPECTED if window 1 planned nothing, and means nothing about end detection. |
| `end:minimum_duration` | `minimumPlausibleDuration` REFUSED a final. Correct if the game was genuinely short/suspended; a defect if it ran normal length. This guard is the premature-final protection. |
| `endFiredAt` set but no `plan_end` row | Already fired on an earlier tick — look at the previous day document. |

## Both commands also confirm

- `fire_jobs docs: 0` — `write_jobs` is OFF, so **nothing should ever be
  written**. Any non-zero here means the flag got flipped and a real house
  could be driven. That is the one line worth reading first.
- `write_jobs: doc absent → LOG-ONLY`.
- Skip breakdown reconciling to 19/19.

## What tonight can and cannot prove

Only ONE account (Trend Setter / `.150`) has resolved participation, so this
exercises the planner half for a single account. It does **not** exercise the
dispatcher (`write_jobs` is off, so no jobs are written for
`dispatchFireJobs` to pick up), multi-account fan-out, or
`minimumPlausibleDuration` as a rejection unless the game ends abnormally
early. A normal-length game reaching a normal final proves the happy path only.

---

# BASE-ROW vs GAME DAY COLLISION — scope, 2026-08-11. DESIGN ONLY.

Found during the base-layer restore. A device base ON row and a cloud Game Day
fire act on the same house with **no arbitration**, and the device timer wins by
default because nothing server-side knows it exists. From the customer's seat,
a base row firing mid-game is **the design dying mid-game**.

This is NOT the end-signal failure case. That one is "the design never stops".
This one is "the design stops early, on schedule, correctly, for the wrong
reason".

## ⚠️ CORRECTION — tonight does NOT collide

I first reported the base row landing 23 minutes AFTER the design fire. **That
was wrong** — I mixed UTC and local. With `DEFAULT_LEAD_MINUTES = 30`:

| event | local (CDT) | UTC |
|---|---|---|
| base ON row | 20:23 | 01:23 |
| Game Day START fire | 20:40 | 01:40 |
| first pitch | 21:10 | 02:10 |

The base row fires **17 minutes BEFORE** the design, so the design lands on top
and stays. **Tonight is clean.** The late west-coast start is what saves it —
and that is luck, not design.

## 1. Does anything suppress it today? — NO, confirmed

No server code reads `timers.ins`. Every reference in `functions/src` is a
COMMENT, and the comments say why: *"lives in timers.ins + presets on the
controller — device-resident cfg behind /json/cfg, which is LAN-only. There is
no off-LAN read."* (`gameDayPlanning.ts:405`).

The planner reads Firestore configs and ESPN. It has **no knowledge that base
rows exist**, cannot enumerate them, and cannot reason about them. Your prior
was right.

## 2. How often does it actually bite? — COMMONLY, on ordinary evening games

Collision window = **[START fire, end fire]** = first pitch −30 min through the
final. A base ON row inside that window overwrites the design.

A typical MLB evening home game: 19:10 first pitch → design fires 18:40 → final
~22:10. **Any base ON boundary between 18:40 and 22:10 collides.**

| account | base ON | typical evening game (18:40–22:10) |
|---|---|---|
| Trend Setter | 20:23 | **COLLIDES** |
| Ellie Cochran | 20:30 | **COLLIDES** |
| Chris Cipollone | Sunset (~20:10 in Aug) | **COLLIDES** |
| Steve Stegall | 11:00 | no — outside the window |

**Three of the four accounts with a base layer collide on a normal evening
game.** That is the common case, not the edge. Evening base-ON boundaries and
evening first pitches occupy the same hours by nature — people turn their house
lights on around sunset, and baseball starts around sunset.

Tonight avoids it only because a west-coast away game pushes first pitch to
21:10 local, later than every base row.

## 3. Options — scoped, not chosen

### (a) Planner disables conflicting base rows for the window — **DEAD**

Confirmed dead on the LAN constraint, as suspected. Disabling a base row is a
`/json/cfg` write; the bridge resolves only `/json/state` and `/json/info`
and has no cfg branch (audit/BASE_LADDER.md §5b). The server cannot read the
rows, let alone rewrite them. **Would require the owed bridge firmware branch
AND a restore-after guarantee that survives the bridge being offline** — if the
disable lands and the restore does not, the customer loses their everyday
schedule silently. Strictly worse than the problem.

### (b) End fire restores base; collisions are overridden then corrected

Accept that a base row may interrupt, and rely on the END fire to put the design
— or the base — back. **Cheapest, and partly built**: S4's `endsAt` companion
already restores to base rather than off.
Cost: the customer sees a visible flip to Warm White mid-game, then back. On a
3-hour game with one base row that is one interruption; the design does not
return until the next planner tick (≤5 min).

### (c) Design re-fires after the base row, on a schedule

The planner knows the design and could re-assert it periodically or immediately
after a known base boundary. **But it does not know the boundaries** (§1), so
this degrades to blind periodic re-fire — every N minutes for the game duration.
Cost: N× the commands per game per house, each a Firestore write and a bridge
round-trip, against a fleet where bridge reach is ~40%. Correctness is decent,
cost and noise are high.

### (d) Accept and disclose

Tell the customer their everyday schedule will interrupt a game design. **Zero
engineering, honest, and bad** — it makes the flagship feature visibly
unreliable for three of four current base-layer accounts, on ordinary games.
Viable only as a stopgap alongside (b).

## 4. What this means for the floor — the tension, stated plainly

**The base ON row is half the §D floor AND the thing that interrupts.** The same
row that guarantees the house is reclaimed if an end signal never lands is the
row that overwrites a healthy running design.

They cannot be separated by removing the row: deleting it fixes the collision
and destroys the floor — precisely the state Trend Setter was in for two days,
where a failed end signal would have left the house lit indefinitely.

So the base layer is **both the safety net and the interference**, and any fix
has to preserve the first while suppressing the second — which is the arbitration
problem, i.e. **the compositor**.

## 5. Is this a `write_jobs` gate? — PARTIALLY. I do not fully agree.

Your read was that flipping would make Tyler's house demonstrate the bug on the
first game. **On tonight's game specifically, it would not** — the base row
fires 17 minutes before the design and the design lands on top (see the
correction above). Tonight would be a clean live-fire test.

But it gates the **next** ordinary evening game, and it gates any rollout past
Tyler: three of four base-layer accounts collide on a normal 19:10 start.

**Recommendation:** flip for tonight if the shadow satisfies you — one house,
demonstrated floor, no collision on this fixture — and treat the collision as a
blocker on the NEXT game and on widening beyond one account. Watching one clean
game first is worth more than deferring until arbitration is designed, and the
collision is visible-and-recoverable rather than dangerous: the house shows the
wrong scene, it does not stay dark or stay lit forever.

## Against the V2 compositor section

This is **the compositor question arriving early**. V2 scoped a shared compositor
to arbitrate Game Day against Neighborhood Sync — two CLOUD sources contending
for the same house. This is the same arbitration problem with a third contender
the design did not account for: **a device-resident timer that no cloud path can
see or modify.**

That changes the compositor's shape. Arbitrating cloud-vs-cloud is a server-side
priority question. Arbitrating cloud-vs-device requires either the cfg bridge
branch (making device rows readable and writable off-LAN) or an explicit model
where **the device layer is authoritative and the cloud composes around it** —
accepting base rows as fixed points and planning fires between them.

The second is cheaper, needs no firmware, and matches how the floor already
works. It also means the planner must LEARN the base boundaries — which, given
§1, would have to be published from the app the same way participation is
(audit/S3B_CHANNELS.md publish gap). **The same on-LAN publish mechanism solves
both**, and that is the strongest argument yet for putting it in the defaults
healer.

---

# PLANNER ACCOUNTING — the 20/19 was the LOG lying, not the planner

**Date:** 2026-08-11 · **Deployed:** `planGameDayFires` only. Flag untouched.

## The reported defect, and why it was not the defect

The checkpoint reader showed `RECONCILES: 20 / 19 ✗ UNACCOUNTED CONFIGS` and an
`outside_horizon: 1` that would not clear. The obvious mechanism — the START
if/else chain has no `continue` before the END block, so a config that plans a
start falls through into `decideEndSignal` and increments twice — **is real but
was NOT what produced those numbers.**

`ticks` is `arrayUnion`ed as whole per-tick objects and is therefore the ground
truth. **All 42 ticks that day reconcile 19/19.** The planner's per-config
accounting was correct the entire time:

```
17:10Z … 19:35Z  (31 ticks)  starts=0  skipped={no_game:11, participation:5, no_controller:2, outside_horizon:1}  19/19 ok
19:40Z … 20:35Z  (11 ticks)  starts=1  skipped={no_game:11, participation:5, no_controller:2}                      19/19 ok
```

At 19:40Z the Royals game came inside `PLAN_HORIZON_MS`. `outside_horizon`
correctly stopped occurring and `startsPlanned` became 1.

**The lie is in `lastSummary`.** It was written inside
`set({...}, {merge: true})`, and **Firestore merges nested maps key by key**.
`bump()` only ever creates keys, so a bucket that stops occurring is never
cleared — the stale `outside_horizon: 1` was frozen into `lastSummary` at 19:35Z
and kept being added to the total forever after. Hence 20 of 19, and hence a
config reported as "waiting on the horizon" when no such config existed.

This is the same class as the `orderBy("at")` miss recorded above: the surface
was not broken, the **read of it** was. Both cost a wrong conclusion about a
live shadow run.

**Fix:** `lastSummary` is now written by a separate `update()`, which replaces a
top-level field wholesale. It runs after the `set()` that creates the document,
so there is no missing-doc failure mode.

## The END fall-through — real, latent, and fixed a different way than asked

A config CAN increment a START bucket and an END bucket in the same tick. It
contributed nothing on 2026-08-11 (`endsPlanned: 0`, no `end:*` key), but it
would break the invariant on any night a game goes final.

**`continue` after the START chain would be a serious bug.** During a live game
every config sits on `start_already_planned` — and it still has to reach
`decideEndSignal` to fire its end. Cutting the fall-through would disable the
end path for exactly the configs that need it.

The fall-through is correct; the *invariant* was wrong. START and END are two
accounting dimensions, not one. `end:*` outcomes now bump a separate
`stats.endSkipped`, so:

```
sum(skipped) + startsPlanned === configsEnabled     ← START, one bucket per config
endsPlanned + sum(endSkipped)                        ← END, independent
```

A config that throws is counted in `errors` and may never reach a bucket, so the
sum can legitimately fall short by up to `errors`; the checker allows for that
explicitly rather than reporting a false ✗.

## Counter-only buckets are now attributable

`no_game` (11), `outside_horizon` (1) and `no_controller` (2) bumped and
`continue`d without pushing a row — countable but not attributable, which is the
exact state `outside_horizon` was added to escape. All three now push
`{uid, teamSlug, action:"skip", reason}`; `outside_horizon` also carries
`eventId` and `fireAt`.

**Volume needs no cap, and this is why:** rows persist via `arrayUnion`, which
**dedupes identical objects**. A row carrying no per-tick-varying field collapses
to ONE entry for the whole day however many ticks run. Volume is bounded by
distinct `(uid, teamSlug, reason)` — at most `configsEnabled` rows/day from these
three buckets, not `ticks × configs`. Adding a timestamp would defeat the dedupe
and turn 11 rows into ~3,100; that is the thing not to do here.

Still counter-only, deliberately, as they did not appear on 2026-08-11:
`daylight_game`, `start_already_planned`, `start_time_passed`. **`start_time_passed`
is the one worth doing next** — its own comment calls it "materially worse" than
beyond-horizon, and it is currently as anonymous as the three just fixed.

## ⚠️ FOR THE NEXT READER — rows accumulate; that is not a double-count

`rows` is written with `arrayUnion(...logRows)`, so it **accumulates across every
tick of the day** and dedupes identical objects. `lastSummary` is ONE tick.
Comparing them will mislead you:

- On 2026-08-11, `rows` held 11 `participation_never_resolved` entries while
  `lastSummary.skipped` said 5. Both correct — 5 in the latest tick, 11 distinct
  `(uid, team, eventId)` across the day, spanning two different games
  (`…401816475` and `…401816490`).
- One config, `wrQRUUKy/mlb_royals/gd_mlb_royals_401816490`, appears with BOTH a
  `participation_never_resolved` row AND a `plan_start` row **for the same
  game**. That looks like the planner skipping and planning the same config at
  once. It is not, and it cannot be: `teamSlug = cfgDoc.id`, so a user has at
  most one config per team, and the participation branch `continue`s.

  **Those two rows are different ticks.** Participation was unresolved earlier in
  the day and RESOLVED before the planning tick — S3b's publish landing for that
  user. It is the good news in that log, not a bug.

If you want per-tick truth, read `ticks`. Never reconstruct it from `rows`.
