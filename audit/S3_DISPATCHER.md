# S3 — FIRE-JOB DISPATCHER

**Date:** 2026-08-07 · **Branch:** `main` @ `5cebd8b` (`2.5.10+65`), working tree
**Status: IMPLEMENTED, TESTED, BENCH-VERIFIED. NOTHING DEPLOYED.** `functions/` only, plus one
index declaration. No `firestore.rules` change. No Dart change.

**Ships in PING SHADOW MODE.** The dispatcher is built, but nothing plans a real payload yet —
§3 is a measurement campaign, not a feature launch.

> **Coordination.** Another window is editing `lib/features/wled/*` and `audit/GAMMA_BUG.md`.
> This change is confined to `functions/src/`, `functions/test/`, `functions/index.js`,
> `firestore.indexes.json` and `scripts/`. **Stage by explicit path** — `functions/lib/` is
> tracked-but-gitignored (COMMAND_SAFETY finding #10), so `git add -A` from either window
> sweeps in the other's build artifacts.

---

## 0. WHY

Game Day and Neighborhood Sync are **100% app-open-only today.**
`kSportsBackgroundServiceEnabled = false` compiles out both background workers
([UNATTENDED_OPERATION.md §0](audit/UNATTENDED_OPERATION.md)), and iOS background fetch is
opportunistic — it will not wake an app for a specific wall-clock instant, so the device path
cannot satisfy "fires at first pitch while you're away" on half the fleet at any price.

Everything gating a server-side dispatcher is now shipped: **S1** (controllerIp validation),
**S2** (expiry + deterministic IDs + sweeper), the rules cutover of 2026-08-05, and **S6**,
which supplied the first working precedent — a scheduled function writing a command that
reached a customer's controller and returned its firmware version in the `result` field.

---

## 1. PART 1 — THE FIRE-JOB COLLECTION

### 1.1 Plan time or fire time? — **the question conflates two documents**

The brief asks whether jobs are written at plan time and dispatched at fire time, or written
at fire time by a cron reading a plan, and cites V2 §4 Layer 1 for the latter. **Confirming
Layer 1, and correcting the framing:** there are two documents with different lifetimes, and
Layer 1 is a claim about only one of them.

| | **Fire job** — `/users/{uid}/fire_jobs/{jobId}` | **Command** — `/users/{uid}/commands/{id}` |
|---|---|---|
| What it is | Intent. "At 19:07 put this state on that controller." | Transport. What the bridge polls for. |
| Written | **At plan time** — days or months ahead | **At fire time**, by the cron |
| Lives for | As long as the plan does | **~90 seconds** |
| Read by | The dispatcher only | The bridge, author-agnostically |

**V2 §4 Layer 1 is about the command, and it is right**: writing the command at fire time is
the single strongest defence against stale execution, because a bridge that is offline at the
fire instant never sees the command at all. That is exactly what this implements.

But the *job* must exist beforehand — otherwise there is no plan for the cron to read. So it
is not either/or: **plan-time job, fire-time command.** The 78-day-old `pending` backlog S2
found (COMMAND_SAFETY D1) is precisely what pre-writing commands would have recreated.

### 1.2 Why a separate collection at all

The command collection is transport: swept by retention after 7 days, written by ten different
writers. Intent needs to outlive its transport, be cancellable before it fires, and carry the
identity that makes dispatch idempotent. Conflating them would mean the plan disappears when
the transport is cleaned up.

### 1.3 The shape, and why each field is there

```
users/{uid}/fire_jobs/{jobId}
  eventId          string    logical event identity ("gameday_chiefs_2026-09-07")
  seq              string    which fire within it ("start" | "end" | "reassert")
  controllerId     string    target; the IP is resolved at dispatch, never stored
  fireAt           Timestamp the instant of intent
  type             string    "applyJson" | "ping"      ← closed set
  payload          string    JSON STRING, not a map
  state            string    scheduled → dispatched → completed|failed|expired
                             scheduled → skipped (terminal refusals)
  -- written by the dispatcher --
  commandId, dispatchedAt, dispatchLatenessMs, writeHopMs, attempts
  outcome, commandError, latencyMs, reconciledAt
  skipReason, skippedAt
```

Four choices worth defending rather than inheriting:

**`payload` is a JSON string, not a map.** Not stylistic: the iOS Firestore SDK crashes on
deeply-nested arrays — the #84 class — which is why `applySyncPattern` and
`CloudRelayRepository` both stringify. A job storing a map would reintroduce it the first time
a payload carried `col: [[r,g,b,w]]`.

**No `controllerIp` on the job.** Storing it at plan time would bake in an address that DHCP
can move months before the fire. It is resolved server-side at dispatch, from the same
`controllers` subcollection that feeds `controller_ips` — so target and allowlist move together.

**`type` is a closed set,** and the payload is inspected too (§1.4).

**Per-user subcollection, not a top-level collection.** It scopes naturally for a future
client read, it is swept by any eventual account-deletion cascade rather than orphaning
(F-5a), and it matches the repo's convention. Cost: one COLLECTION_GROUP composite index on
`(state, fireAt)`, declared in `firestore.indexes.json` and **not deployed**.

### 1.4 The §4.2 constraint, enforced in code rather than in prose

COMMAND_SAFETY §4.2 says: *"Route only fire jobs through the scheduled path. Never a
state-mutating operation — no psave, no applyConfig, no pairing — where 'executed 60 s late'
is not equivalent to 'executed'."*

That was prose, and prose does not stop a job. A `type: "applyJson"` whose **payload** is
`{"psave": 5}` sails past a type allowlist and reaches `POST /json/state` — which is exactly
how a preset gets written by a cron. So `assertPayloadIsFireSafe` inspects the payload:

| Refused | Why |
|---|---|
| `psave` | writes a preset — and can capture `frz:true`, poisoning it into a preset that fires dark forever ([FROZEN_SEGMENT.md](audit/FROZEN_SEGMENT.md)) |
| `pdel` | deletes a preset |
| `rb` | reboots the controller, which boots the strip **lit** (`def.on`) |
| any type outside `applyJson` / `ping` | — |
| unparseable / non-object payload | fails **closed**: no user is present to notice a malformed fire |

`ps` — preset **load** — is deliberately allowed: it is an absolute state load, the same
idempotent shape as any other fire.

Two layers, because a payload that never parses can still carry the key: a raw
case-insensitive substring scan, then a parsed top-level key check.

---

## 2. PART 2 — THE MINUTE CRON

`dispatchFireJobs`, `* * * * *`, us-central1. Each tick reconciles, then dispatches.
Reconcile runs **first** so an outcome is recorded before the same tick considers anything
else for that controller, and so a fire's metrics land on the next tick rather than a day later.

### 2.1 Reused from S6, not reinvented

- **Always name `controllerIp`, resolved server-side.** The omit path is bench-refuted: an
  untargeted probe got `ERROR: HTTP -1` while 282 named commands to the same controller
  succeeded, because the bridge's paired IP was `0.0.0.0`
  ([CONTROLLER_HEALTH.md §1.1, §9 Q4](audit/CONTROLLER_HEALTH.md)). Safety here is
  **provenance**, not absence.
- **Deterministic IDs** via `fireJobDocId` + `.doc(id).create()`.
- **The one-in-flight-per-controller guard** — S6 was its only caller; it now has two.
  Imported from `controllerHealth` rather than duplicated, so there is exactly one definition
  of "is this controller busy".

### 2.2 Grace — and a correction to V2 §4 Layer 2

V2 specifies `expiresAt = fireAt + graceWindow`. **With a minute cron that silently shrinks
the bridge's budget by however late the tick ran.** A job due at 19:00:00 dispatched at
19:00:45 would have 45 s left of a 90 s window — below the measured 30-32 s worst case plus
any margin. A perfectly healthy bridge under load would be marked `expired`, the fire silently
dropped, and **the dispatcher's lateness charged to the bridge** — wrong, and undetectable.

Split into two independent knobs:

```
MAX_FIRE_LATENESS_MS = 90_000   how stale a fire may be when it STARTS  (terminal if exceeded)
FIRE_GRACE_MS        = 90_000   the bridge's budget, measured from DISPATCH — constant
```

- Worst-case execution is `fireAt + 90 s + 90 s = 3 min`, **bounded by construction**.
- The bridge always gets its full 90 s: ~3× the measured 30-32 s tail.
- 90 s ≥ `MIN_SWEEPABLE_AGE_MS` (60 s), or the sweeper could not enforce the expiry at all.
- 90 s < `DEFAULT_COMMAND_TTL_MS` (120 s): **a scheduled fire must not outlive a command a
  human is actually waiting on.**

All four are locked by property tests.

### 2.3 Terminal vs transient — the distinction that is easy to get wrong

A job blocked by the in-flight guard must stay `scheduled` and retry next tick; the guard is
momentary. A job that is too late, unsafe, or has no resolvable target can never succeed and
must be terminalized so it is not re-read every minute forever.

| Outcome | State | Retried? |
|---|---|---|
| in-flight guard | stays `scheduled` | ✅ next tick, until too-late |
| not yet due | stays `scheduled` | ✅ |
| `too_late` | `skipped` | ❌ terminal |
| `unsafe:*` | `skipped` | ❌ terminal |
| `unresolvable_target` / no `controllerId` / no `fireAt` | `skipped` | ❌ terminal |

The guard also **fails closed**: if the in-flight query itself errors, the user is treated as
busy rather than probed blind.

### 2.4 The retry trap, avoided deliberately

The command ID is keyed on **the job's `fireAt`**, not on `now`:

```ts
fireJobDocId(jobSnap.id, Math.floor(fireAtMs / 1000))
```

Keying on `now` would mint a **different** ID on a retried invocation, `.create()` would not
collide, and the bridge would fire **twice**. The job's own `fireAt` is stable across retries,
so the collision happens exactly when it should. A unit test documents the trap explicitly.

---

## 3. PART 3 — THE PING SHADOW RUN

Nothing plans a real payload. The only type any planner may emit today is `ping`, which the
bridge acknowledges **locally with no WLED request** — so the whole transport is measured at
zero customer risk.

### 3.1 Instrumentation added

`/fire_metrics/{YYYY-MM-DD}`, updated transactionally each tick:

| Field | Answers |
|---|---|
| `writeHop` `{count,p50,p95,min,max}` | **V2 UNVERIFIED #13** — the Admin-SDK write hop, never measured |
| `e2e` `{count,p50,p95,min,max}` | command `createdAt` → `completedAt` |
| `inFlightBlocks` | how often the guard fires in real conditions |
| `expired` | how often the bridge was unreachable at fire time |
| `dispatched` / `completed` / `failed` / `tooLate` / `unsafe` / `errors` / `ticks` | tick health |

Per-job forensics live on the job itself: `writeHopMs`, `dispatchLatenessMs`, `latencyMs`,
`outcome`, `commandError`.

Samples are capped at 500/day keeping the **most recent** — a path that degrades through the
day must show in that day's percentiles rather than being masked by a healthy morning.

### 3.2 First measurements — from the bench run, 2026-08-07

```
writeHop : count=10  p50=117 ms  p95=146 ms  min=89  max=146
e2e      : count=7   p50=1010 ms p95=2385 ms min=270 max=2385
inFlightBlocks=8   tooLate=3   unsafe=3   errors=0
```

**V2 UNVERIFIED #13 is answered: the Admin-SDK write hop is ~117 ms p50.** V2 guessed "likely
faster" than the app's measured 300-800 ms from a phone and left it unverified. It is roughly
**3-7× faster**, which is a real (if unsurprising) confirmation that a cloud-fired event beats
an app-driven one on the slowest hop.

**Caveat, stated rather than buried:** `e2e` here is for `ping`, which short-circuits before
any WLED request. It measures cloud → bridge → Firestore ack — **not** the full path to the
controller. It is therefore a *floor* on real fire latency, not an estimate of it. S6's
`getInfo` probe measured the full path at **1705 ms**, inside V2 §5's predicted 1.1-1.9 s band;
that remains the number to quote for a real fire.

**This is a bench sample of 7-10, not a week.** It is enough to prove the instrumentation
works and to answer #13; it is **not** enough to characterise P95 under real fleet conditions.
The week-long run is §5 step 5.

---

## 4. PART 4 — WHAT WAS DELIBERATELY NOT BUILT

| Not built | Why |
|---|---|
| **Any Game Day logic** | S5, and it needs S3b's channel denormalization first — the participating-channel set is device-derived and cached on the phone ([CONTROLLER_HEALTH.md §1.1 F-1](audit/CONTROLLER_HEALTH.md)) |
| **Any sync fanout** | Gated on consent parity (`fanoutToCrew` enforces strictly weaker consent than `initiateSyncSession`) and on the windowed-consent model |
| **Any planner** | Nothing writes a fire job. The dispatcher is a consumer with no producer yet — deliberate, so the shadow run measures transport before anything drives lights |
| **State-mutating jobs** | §1.4, enforced in code |
| **Any Dart** | The app cannot see fire jobs and does not need to |

---

## 5. VERIFICATION

### 5.1 Unit — `cd functions && npm run build && npx jest test/unit`

**6 suites, 188 tests, all passed** (45 new in `fireJobs.test.js`).

Covered: all four timing-constant properties; every forbidden key rejected, including in an
unparseable payload and case-insensitively; `ps` allowed while `psave` is refused; every
terminal-vs-transient dispatch branch; the lateness boundary at ±1 ms; **the retry trap** (same
job + same `fireAt` → same ID; `now`-keyed → different ID, which would have double-fired);
expiry measured from dispatch so an 80 s-late job still gets a full bridge budget; `expired` ≠
`failed` preserved through reconciliation; percentiles returning **null rather than a
fabricated zero** on an empty sample; and the sample cap keeping the most recent.

### 5.2 Bench, end to end — `scripts/_verify_fire_dispatcher.js`

Drives the **real compiled `runDispatchTick`**, scoped to the bench account, `ping` only.
**28 passed, 0 failed.**

```
TEST 1  a job fires at its fireAt        PASS  fire_bench_fire_1_1786120956, writeHop 129 ms
                                         PASS  controllerIp NAMED = 192.168.1.150
                                         PASS  expiresAt explicit = dispatch + 89 s (not 120 s)
TEST 2  retry cannot double-fire         PASS  3 → 3 commands; guard was NOT what stopped it
                                         PASS  commandId unchanged by the retry
TEST 3  one-in-flight guard, one tick    PASS  exactly one of two dispatched; other has no commandId
TEST 4  too-late job                     PASS  skipped, and no document at its deterministic id
TEST 5  psave payload                    PASS  refused, skipReason names the key
TEST 6  reconcile                        PASS  dispatched after 2 ticks, completed, latency 332 ms
TEST 7  shadow metrics                   PASS  writeHop p50 117 ms
```

**The first run failed 4 of 23, and all four were the harness, not the dispatcher** — worth
recording, because three of them looked like real defects:

1. *"retry still marks the job dispatched"* — the **guard** blocked the retry before
   `.create()` could collide. The two defences are independent and the guard fires first; the
   test was measuring the wrong one. Fixed by waiting for the command to go terminal so the
   queue is clear, then asserting the ID barrier **and** asserting the guard was not involved.
2. *"competing job NOT dispatched"* — asserted on the tick's aggregate `dispatched` count,
   which included an unrelated job. Rewritten as two jobs / one tick, which is deterministic
   and does not race the bridge.
3. *"NO command written for the stale job"* — a fleet-wide count, masked by a legitimate
   dispatch on the same tick. Now asserts the stale job has no `commandId` **and** that no
   document exists at its deterministic ID.
4. *"reconcile counted"* — the job had already been reconciled on an earlier tick.

> **The lesson is the same one this repo keeps relearning: an aggregate count is not a
> measurement of a specific thing.** Every rewritten assertion names the document it is about.

A fifth surfaced on the second run: the fresh reconcile job was **blocked by the guard** from
leftover contention and never dispatched. That was the dispatcher working correctly — the
block is transient by design — so the test now ticks until it dispatches, which also proves
the retry path.

### 5.3 Dart suite — not run, and not applicable

No Dart file was changed. Nothing in `functions/` is in the Flutter package's source set. The
other window is still mid-flight in `lib/features/wled/*`, so a run would measure their tree,
not this change — see [CONTROLLER_HEALTH.md §5.3](audit/CONTROLLER_HEALTH.md) for what that
looked like last time (16 failures mid-edit, 2 on a settled tree).

---

## 6. CHANGED FILES

| File | Change |
|---|---|
| [functions/src/fireJobs.ts](functions/src/fireJobs.ts) | **NEW** — pure contract: payload safety, dispatch decision, command construction, reconciliation mapping, percentiles |
| [functions/src/dispatchFireJobs.ts](functions/src/dispatchFireJobs.ts) | **NEW** — the minute cron; `runDispatchTick` exported for the bench |
| [functions/index.js](functions/index.js) | Exports `dispatchFireJobs` |
| [functions/test/unit/fireJobs.test.js](functions/test/unit/fireJobs.test.js) | **NEW** — 45 unit tests |
| [scripts/_verify_fire_dispatcher.js](scripts/_verify_fire_dispatcher.js) | **NEW** — bench harness against the compiled dispatcher |
| [firestore.indexes.json](firestore.indexes.json) | `fire_jobs(state, fireAt)` at COLLECTION_GROUP scope |

**No Dart. No `firestore.rules`.** Rules are not needed: `fire_jobs` and `fire_metrics` are
Admin-SDK-only and read by no client, and adding an undeployed block would leave a landmine
for whoever next deploys rules for an unrelated reason. The rule a future client read needs:

```
match /users/{userId}/fire_jobs/{jobId} {
  allow read: if isOwner(userId) || hasAdminOrOwnerClaim();
  allow write: if false;   // Admin SDK only
}
```

**A note on the scoped query path.** When `onlyUid` is set the dispatcher queries the user's
own subcollection with a single equality and filters `fireAt` in memory, which uses the
automatic single-field index and needs **no index deploy** — that is how the bench ran
end-to-end before the composite ships. The fleet path uses the composite, because reading
every scheduled job in existence each minute would not scale past a few weeks of plan.

---

## 7. WHAT DEPLOYING WOULD COST

### 7.1 The shape of the cost is different from S6

S6 is 2 invocations/day. **This is 1,440.** That is the headline, and it is worth being precise
because "a minute cron" sounds cheap and its read cost is not zero when idle.

**Idle (shadow mode, no jobs planned) — per day:**

| Operation | Count/day | Note |
|---|---|---|
| Invocations | 1,440 | 2 collection-group queries each |
| **Reads** | **~2,880** | two queries × 1,440; **an empty query result still bills 1 read minimum** |
| Writes | 1,440 | the `fire_metrics` transaction, one per tick |

**~2,880 reads + ~1,440 writes/day idle** — against free tiers of 50,000 reads / 20,000
writes, that is **~6 % of reads and ~7 % of writes doing nothing.** Not free, but not close to
a limit either.

**Per fire, on top:** 1 controller read, 1 in-flight query, 1 command create, 1 job update,
1 command read + 1 job update at reconcile ≈ **3 reads + 3 writes**. At 15 controllers × 4
fires/day that is ~180 reads + ~180 writes — negligible beside the idle floor.

**The idle metrics write is the one avoidable cost.** Writing `fire_metrics` on a tick with
nothing to report burns a write per minute for no signal. **Recommendation: skip the metrics
transaction when the tick is entirely quiet** — it would cut idle writes by ~95 % once the
shadow run ends. Left in for now *because* the shadow run wants the `ticks` counter as proof
the cron is alive, which is the same all-clear-heartbeat argument as S6's Monday digest.

**Cloud Scheduler:** ~~3 jobs free per month; this is the third.~~ **Wrong — corrected
2026-08-07 during the S6 deploy.** `gcloud scheduler jobs list --location=us-central1` shows
**7** jobs already (`sweepExpiredCommands`, `scheduledDataCleanup`, `sendWeeklyBrief`,
`sendInstallReminders`, `enforceScheduleLimits`, `probeControllerHealth`,
`collectControllerHealth`). The 3-free allowance was exceeded long before S3, so
`dispatchFireJobs` would be the 8th at $0.10/month. Immaterial in money — the original claim
was simply not checked.

### 7.2 The real costs

1. **A minute cron is a standing commitment.** It runs 43,200 times a month whether or not
   anything is planned.
2. **Node.js 20 is decommissioned 2026-10-30** (COMMAND_SAFETY D6). Inherited deadline.
3. **The composite index must be deployed BEFORE the function**, or every tick throws
   `FAILED_PRECONDITION` — the same ordering hazard as S2's sweeper. Both queries log loudly
   and rethrow rather than silently returning nothing.
4. **Nothing produces jobs yet.** Deploying this alone changes no customer-visible behaviour.
   That is the point, but it means the deploy's only observable is `fire_metrics.ticks`
   incrementing.

### 7.3 Deploy sequence

| # | Step | Command | Verify before proceeding |
|---|---|---|---|
| 1 | **Index first** | `firebase deploy --only firestore:indexes` | Console shows `fire_jobs` COLLECTION_GROUP **Enabled**, not Building |
| 2 | Check the scheduler quota | `gcloud scheduler jobs list` | Confirm the 3-free-job position |
| 3 | Deploy the function | `cd functions && npm run build && firebase deploy --only functions:dispatchFireJobs` | "Successful create operation" |
| 4 | Watch 10 idle ticks | `firebase functions:log --only dispatchFireJobs` | Quiet ticks log nothing; `fire_metrics/{today}.ticks` increments |
| 5 | **Shadow run — one week**, `ping` jobs only | plan a handful per day against the bench + one consenting account | `writeHop` and `e2e` percentiles stabilise; `inFlightBlocks` and `expired` are understood |
| 6 | **Only then** consider a real payload | — | gated on S5 + S3b, not on this document |

Rollback: delete the function. `fire_jobs`, `fire_metrics` and the index are additive and
harmless if left.

---

## 8. FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **"Plan time or fire time" conflates two documents.** V2 §4 Layer 1 is right *about the command* — plan-time job, fire-time command. Pre-writing commands is exactly what produced the 78-day-old pending backlog S2 found | Framing correction |
| 2 | **V2 §4 Layer 2's `expiresAt = fireAt + grace` is wrong under a minute cron.** It charges the dispatcher's lateness to the bridge and would expire a healthy bridge's command. Split into a lateness bound and a constant, dispatch-relative grace | **Design correction** |
| 3 | **§4.2 was prose and would have stayed prose.** A `type: "applyJson"` with `{"psave":5}` reaches `POST /json/state`. The payload is now inspected, not just the type — with a raw scan as well as a parsed one, because an unparseable body can still carry the key | **P1 — constraint made real** |
| 4 | **Keying the command ID on `now` instead of the job's `fireAt` would double-fire on every retry.** The ID must be stable across invocations, which means it must come from the plan, not the clock | **P1 — trap avoided, test-documented** |
| 5 | **V2 UNVERIFIED #13 answered: the Admin-SDK write hop is ~117 ms p50** (min 89, p95 146), versus the app's measured 300-800 ms from a phone — 3-7× faster, confirming V2's unverified guess with a number | **Closes an UNVERIFIED** |
| 6 | The shadow `e2e` p50 of ~1 s is for **`ping`, which never reaches the controller**. It is a floor, not an estimate. S6's full-path `getInfo` at 1705 ms remains the number to quote | Honesty about what was measured |
| 7 | **The guard and the deterministic ID are independent defences, and the guard fires first.** The first bench run could not test the ID barrier at all until the queue was drained deliberately | Test design |
| 8 | **4 of 23 first-run bench assertions failed, all harness, three of them measuring aggregate counts rather than the specific document under test.** Same class as every prior "plausible answer against the wrong thing" in this repo | **Method** |
| 9 | **A minute cron costs ~2,880 reads + ~1,440 writes/day even when idle** — ~6-7 % of the free tier doing nothing. The per-tick metrics write is the avoidable part and should be skipped on quiet ticks once the shadow run ends | **P2 — named, with a fix** |
| 10 | The one-in-flight guard now has **two** callers (S6, S3). It was shipped in S2 with none, deliberately | Closes an S2 loose end |
| 11 | Scoping the dispatcher to one uid lets it use single-field auto-indexes, so **the bench ran end-to-end before the composite index shipped**. Worth keeping — it makes every future dispatcher change bench-testable without a deploy | Deploy risk ↓ |

---

## 8a. DEPLOY LOG — 2026-08-08

**Deployed. Its own step; nothing else.** One real defect shipped and was fixed in ~9 minutes —
recorded in full because the lesson is not the fix.

### STEP 1 — INDEX FIRST ✅

`firebase deploy --only firestore:indexes` → deployed. Polled the Firestore Admin API until
`fire_jobs(state, fireAt)` read **READY** — **CREATING for ~3.5 minutes** before flipping.

> **A near-miss worth recording.** My first poll grepped `^READY` against a response that listed
> **two** indexes, and matched the `commands(status, createdAt)` line — reporting the index ready
> while `fire_jobs` was still `CREATING`. Had I proceeded, the function would have deployed
> against a building index. The fix was to match the specific index by its fields rather than
> by position. **Same class as `teamName`/`team_name` and `displayName`/`display_name` this
> week: a check that returns a plausible answer against the wrong thing.**

### STEP 2 — SCHEDULER COUNT ✅ — the doc was wrong, as suspected

**7 jobs existed**, not 2. `dispatchFireJobs` is the **8th**:

```
sweepExpiredCommands      every 1 minutes     scheduledDataCleanup     0 4 * * *
probeControllerHealth     15 9 * * *          collectControllerHealth  30 9 * * *
sendInstallReminders      every day 18:00     sendWeeklyBrief          every sunday 18:30
enforceScheduleLimits     every sunday 19:00  → dispatchFireJobs       * * * * *
```

Free tier is 3, so 5 were already billing; the 8th adds **$0.10/month**, total ~$0.50/month.

### STEP 3 — BUILD, VERIFIED ✅

`npm run build` with an **explicit `$?` check**, not piped. `tsc exit: 0`. Additionally deleted
`lib/dispatchFireJobs.js` and `lib/fireJobs.js` beforehand and confirmed both were regenerated
and newer than their `.ts` sources — because `firebase deploy` ships `lib/` and never checks it
agrees with `src/`. Unit suite: **7 suites, 201 tests, all passing.**

### STEP 4 — DEPLOY ✅

`Successful create operation.` `FUNCTIONS_DISCOVERY_TIMEOUT=120` set pre-emptively; no
discovery timeout this time. Scope verified: only `dispatchFireJobs` created.

### ⚠ THE DEFECT — every tick threw for ~20 minutes

```
FAILED_PRECONDITION: The query requires a COLLECTION_GROUP_ASC index
for collection fire_jobs and field state.
dispatchFireJobs: RECONCILE QUERY FAILED — fire outcomes are not being recorded.
```

**The composite I deployed was the wrong index for one of the two queries.**

- The **due** query — `where(state==).where(fireAt<=)` — is served by `(state, fireAt)`. Fine.
- The **reconcile** query was a **bare single-field equality** — `where(state=='dispatched')` —
  at COLLECTION_GROUP scope. Firestore auto-creates single-field indexes at **COLLECTION** scope
  only; a collection-group single-field query needs its own `COLLECTION_GROUP_ASC` exemption.

Reconcile runs **first**, so the throw killed the whole tick before dispatch. Nothing worked.

**Fix — no second index.** Added `.orderBy("fireAt")` to the reconcile query, which makes it use
the `(state, fireAt)` composite already deployed. Oldest-first is also the correct reconcile
order. Rebuilt with an explicit exit check, redeployed; **errors stopped immediately.**

> **I had already hit this exact error twice this week** — in the S6 verification harness
> (`commands.status` at collection-group scope) and again in the probe-status poller — and
> documented it both times as a *harness* limitation. **I did not apply it to the dispatcher's
> own query.** The §6 note even says the scoped path "needs no index deploy" while the fleet path
> uses the composite; that sentence is true of the *due* query and silently wrong about
> reconcile. A lesson recorded in a document about test scripts did not transfer to production
> code doing the same thing.

**Why the bench did not catch it:** the harness runs with `onlyUid` set, which takes the
subcollection path — `db.collection('users').doc(uid).collection('fire_jobs')` — a plain
COLLECTION query that needs no exemption. **The scoped path that made the bench deployable
without an index is exactly what hid the fleet path's index requirement.** The 28/28 bench pass
was real and covered the wrong query shape.

### STEP 5 — IDLE TICKS ✅

**14 consecutive clean ticks**, one per minute:

```
02:24 ticks=7   02:26 ticks=9    02:28 ticks=11   02:30 ticks=13
02:25 ticks=8   02:27 ticks=10   02:29 ticks=12   02:31 ticks=14
                             errors=0 throughout
```

- `errors: 0`, `dispatched: 0`, `inFlightBlocks: 0`
- `e2e` and `writeHop` both `count: 0` with **null** percentiles — not a fabricated zero
- **Quiet ticks log nothing** — an INFO search over 5 minutes returns empty, as designed
- **`fire_jobs` fleet-wide: 0** — correct; there is no producer. Nothing unexpected is writing them

### STEP 6 — COST, first sample

Not yet 24 h. From 14 observed ticks the idle profile is **1 metrics write + 2 collection-group
reads per tick**, matching the §7.1 estimate of ~1,440 writes and ~2,880 reads/day. A full
24 h reading is still owed before the estimate is confirmed.

The recommendation stands and is **not** actioned: skip the metrics transaction on entirely
quiet ticks once the shadow run ends (~95 % of idle writes). Kept for now because `ticks` is the
only proof the cron is alive — and this deploy is precisely why that matters: **the metrics doc
being absent is what revealed the function was throwing.** Had quiet ticks written nothing, the
failure would have looked identical to "working normally, nothing to do".

### Deploy findings

| # | Finding | Severity |
|---|---|---|
| S3-D1 | **A bare single-field equality at COLLECTION_GROUP scope needs its own `COLLECTION_GROUP_ASC` exemption.** The composite does not cover it. Every tick threw until `.orderBy("fireAt")` routed reconcile through the existing composite | **P1 — shipped and fixed** |
| S3-D2 | **The bench could not have caught it.** `onlyUid` takes the plain-COLLECTION path; the scoping that made the harness index-free is what hid the fleet path's requirement. 28/28 passed against the wrong query shape | **Method — the important one** |
| S3-D3 | **I had hit this error twice this week and filed it as a harness quirk both times.** The lesson did not transfer to production code making the same query | Method |
| S3-D4 | **Index-readiness poll matched the wrong index** and would have reported READY while `fire_jobs` was still CREATING. Matched by field set on the retry | Near-miss |
| S3-D5 | 7 scheduler jobs existed, not 2 — §7.1's free-tier note was wrong. The 8th costs $0.10/month | Correction, confirmed |
| S3-D6 | **The unconditional metrics write is what surfaced the outage.** An absent `fire_metrics` doc was the signal; a quiet-tick optimisation would have made a throwing function indistinguishable from a healthy idle one | **Argues for keeping it until a producer exists** |

---

## 9. OPEN — for whoever picks up S5

1. **Nothing writes fire jobs.** A planner is S5's job. The contract it must satisfy is
   §1.3 plus `assertPayloadIsFireSafe`.
2. **`MAX_JOBS_PER_TICK = 200`** is a runaway guard, not a capacity plan. A fleet that ever
   needs more than 200 fires in one minute needs sharding, and the tick should log loudly when
   it truncates — it currently does not.
3. **No cancellation path.** Setting `state` to anything but `scheduled` prevents dispatch, so
   cancel-before-fire works today by construction, but nothing exposes it.
4. **Re-assert jobs (V2 §3 Case B) are unmodelled.** `seq` is a free string; the compositor
   that decides when a re-assert is needed is Phase 1, not S3.
