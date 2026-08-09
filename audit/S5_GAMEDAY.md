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
