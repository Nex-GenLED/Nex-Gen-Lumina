# CONTROLLER HEALTH TELEMETRY — S6, cloud half

**Date:** 2026-08-06/07 · **Branch:** `main` — see the working-tree note below
**Status: IMPLEMENTED, TESTED, BENCH-VERIFIED. NOTHING DEPLOYED.** No branch created.
No rules change. No index change. §7 has the deploy sequence and its cost.

> ### ⚠ WORKING-TREE NOTE — a second session is in flight in this repo
>
> This work began at `0a76629` (`2.5.10+64`). By the time the Dart suite ran, `main` had
> moved to **`5cebd8b` (`2.5.10+65`)** — three commits landed from elsewhere (`361c958`
> version bump, `87f904a` build ledger, `5cebd8b` neighborhood windowed-consent design), and
> the working tree carries **six modified Dart files plus an untracked `audit/GAMMA_BUG.md`
> dated 2026-08-07 that this session did not create**:
>
> ```
>  M lib/features/wled/wled_payload_utils.dart        M lib/features/wled/wled_service.dart
>  M lib/features/wled/cloud_relay_repository.dart    M lib/features/wled/controller_defaults_healer.dart
>  M lib/services/wled_config_pusher.dart             M lib/features/site/edit_profile_screen.dart
> ```
>
> That is another window's in-progress gamma investigation. **Nothing in this document
> touched any of those files**, and none of them is reachable from the functions/ code here.
> The Dart-suite result in §5.3 must be read against that tree, not a clean one.

---

## 0. WHY THIS AHEAD OF S5

[audit/BRIDGE_TRIAGE.md](audit/BRIDGE_TRIAGE.md) was a hand-written script run once. It found
two customer bridges dark for **15.0** and **21.4 days**, and a third customer — The Iron
Reserve — with a **powered, online, never-paired** bridge for five days and 17 failed
commands. None of it was visible to the customer, the dealer, or Tyler, because everyday
lighting is device-resident: the lights came on at sunset and off at sunrise the entire time.
Nothing was broken that anyone could see from the driveway.

That triage does not repeat itself. Nothing in the product would surface the next one.

The same evening supplied the mechanism, unprompted. Pairing the Iron Reserve's bridge
produced this 63 seconds later:

```
21:15:58Z  getInfo  completed
  result={"ver":"0.15.1","vid":2507300,"cn":"Kōsen","release":"ESP32_Ethernet", …}
```

A command's `result` field carries WLED's own response body, relayed back from a controller
nobody could otherwise reach — that customer's firmware version and build id, **with zero
firmware work**. Exactly what [SCHEDULING_ARCHITECTURE_V2.md §6](audit/SCHEDULING_ARCHITECTURE_V2.md)
predicted. This turns that accident into a daily measurement.

---

## 1. PART 1 — THE DAILY PROBE

Two scheduled functions, both `us-central1`, both UTC:

| Function | Schedule | Does |
|---|---|---|
| `probeControllerHealth` | `15 9 * * *` (09:15 UTC ≈ 04:15 US Central) | Writes one `getInfo` command per controller |
| `collectControllerHealth` | `30 9 * * *` (+15 min) | Reads them back, writes health, evaluates alerts, pushes the digest |

**Why 04:15 Central:** the command queue is empty, so a probe never competes with customer
traffic; it collides with neither `scheduledDataCleanup` (04:00 UTC) nor the 1-minute
sweeper's steady state; and controllers are mains-powered, so "the lights are off" is
irrelevant to a GET.

**Why `getInfo` and not `getState`:** both are GETs and neither mutates the strip, but
`/json/info` carries version, vid, LED count and rgbw — the fleet signal that has never
existed — while `/json/state` carries only what the lights are doing right now.

**Why a probe is safe to schedule at all.** [COMMAND_SAFETY.md §4.2](audit/COMMAND_SAFETY.md)
imposes a standing constraint on anything routed through a scheduled path: *"never a
state-mutating operation, where 'executed 60 s late' is not equivalent to 'executed'."* A
GET satisfies that trivially. It is precisely why the **cloud** half of controller health is
schedulable and the **app** half (cfg digests) is not.

### 1.1 `controllerIp` — the design changed, and the bench is why

**Specified:** omit where the target is the paired controller, *or* resolve server-side as
`applySyncPattern` does — and state which and why per controller.

**Built first:** omit for single-controller accounts (all 15 of them),
server-resolve for multi. That followed
[SCHEDULING_ARCHITECTURE_V2 §8](audit/SCHEDULING_ARCHITECTURE_V2.md) ("free, and strictly
best" — an unnamed target cannot be redirected) as narrowed by
[COMMAND_SAFETY §1.3](audit/COMMAND_SAFETY.md).

**The bench refuted it.** 2026-08-06 01:34 UTC, Tyler's account:

```
01:34:58Z  getInfo  status=failed  controllerIp=undefined  ERROR: HTTP -1
```

while, against the same bridge and the same controller, every named command succeeded:

```
controllerIp x status, all retained commands on the bench account
  192.168.1.150|completed = 282      192.168.1.250|completed = 733
  192.168.1.150|failed    =  20      192.168.1.250|failed    =  43
  192.168.1.150|timeout   = 113      192.168.1.250|timeout   = 127
  undefined|failed        =   1      ← the only untargeted command ever written
```

A `ping` to `.150` completed 30 minutes later, so bridge and controller were both healthy.

**The error string is diagnostic.** The firmware answers an *empty* fallback with
`"No controller IP specified"` ([main.cpp:806-811](esp32-bridge/src/main.cpp#L806)). We got
`ERROR: HTTP -1` — a connection failure — so `pairedWledIp` was **populated and wrong**.

**Q4 settled what it actually holds, and it is not what I guessed.** I hypothesised stale
NVS from the bench controller's `.250 → .150` move. `GET http://192.168.1.96/api/bridge/status`:

```json
{ "paired": true, "authenticated": true, "wifi": true,
  "userId": "wrQRUUKyXyc0deyuu0ORS6wsovO2",
  "wledIp": "0.0.0.0",                      ← never populated, not stale
  "commands": 565, "errors": 857, "uptime": 1448996, "version": "1.2" }
```

**`wledIp` is `0.0.0.0`.** The pairing completed and never recorded a controller address at
all. That defeats the firmware's guard precisely: `controllerIp.isEmpty()` is FALSE for
`"0.0.0.0"`, so the fallback "succeeds" and the bridge dials `http://0.0.0.0/json/info` →
connection refused → `HTTP -1`. Meanwhile the bridge self-reports `paired: true,
authenticated: true` — it believes it is healthy. See §9 Q4 for the separate defect log.

**The deeper point:** no shipping app writer omits the field. `CloudRelayRepository`,
`bridge_health_service` and `bridge_setup_screen` all set it. Only the three voice
integrations omit, and they are barely exercised. **The omit path was reasoned about across
two audit documents and never once tested against a bridge.**

> **Correction, now empirical rather than argued: always NAME the IP, resolved server-side
> from the user's own `controllers` subcollection.** The "unredirectable" property is real,
> but it buys safety by making the target **unverifiable** — and an unverifiable target that
> is silently stale turns every probe into a false *controller unreachable*. For a health
> monitor that is the worst possible failure mode: it would have reported the entire fleet
> dark on day one.
>
> Safety comes from **provenance**, not absence — the same argument COMMAND_SAFETY §1.3
> already established for `applySyncPattern`'s fan-out (writers #6/#7). It is also
> self-correcting: `controller_ips` derives from the same subcollection, so a DHCP move
> updates target and allowlist together.

A controller document with **no** IP is skipped and counted as `unresolvable_target` — never
falling back, never guessing. Locked by five regression tests, including one asserting the
`bridge_paired_fallback` value is no longer producible, because the omit advice is written
down persuasively in two places and someone will propose it again.

### 1.2 `expiresAt` — explicit, and deliberately tighter than the default

```ts
expiresAt = fireAt + PROBE_GRACE_MS   // 90_000
```

Not the inherited `DEFAULT_COMMAND_TTL_MS` (120 s), which is sized for an **app** command —
it must exceed the app's own 45 s watchdog so expiry is invisible to a waiting user. A probe
has no user waiting and the opposite requirement: it is a **liveness measurement**, so one
that executes ten minutes late tells you almost nothing.

90 s, against three constraints, all test-locked:

- **~3× the measured 30-32 s worst case** under queue pressure, so a healthy-but-loaded
  bridge is never marked expired.
- **≥ `MIN_SWEEPABLE_AGE_MS` (60 s).** The sweeper will not even *query* commands younger
  than that floor, so a grace below 60 s would claim a deadline nothing can enforce.
- **Far inside the 15-minute collect gap**, so every probe is terminal when read back.

Verified live: `expiresAt − createdAt = 90 s` exactly.

### 1.3 Deterministic IDs

`fireJobDocId("health_" + controllerId, fireAtEpochSeconds)` → `fire_health_<controllerId>_<epoch>`,
written with **`.doc(id).create()`** — which fails `already-exists` rather than overwriting.
A retried invocation cannot double-probe; `already-exists` is caught and reported as
`already_exists_idempotent`, i.e. treated as success, because the probe exists and that was
the goal. Live ID: `fire_health_192_168_1_150_1786115923`.

This is `commandSafety.fireJobDocId`'s **first caller**. It was shipped in S2 with no caller
by design.

### 1.4 One-in-flight-per-controller

The contract [COMMAND_SAFETY §3.4](audit/COMMAND_SAFETY.md) specified and deliberately left
unimplemented ("an uncalled guard is untestable"). **S6 is its first caller.**

Deliberately conservative — it blocks on *any* pending/executing command that could be for
this controller, not just a prior probe:

- same `controllerId` → obviously ours
- **no `controllerId` at all** → `bridge_health_service.dart` writes none
- **`controllerId: ''`** → `bridge_setup_screen.dart` writes empty

Because the measured tail is 30-32 s (`MAX_COMMANDS_PER_POLL = 5`, processed **serially**), a
probe must never be the command that pushes a customer's brightness drag into it. Skipping a
probe costs one day of one controller's telemetry; competing with customer traffic costs the
customer.

The guard also **fails closed**: if the in-flight query itself errors, the whole user is
skipped rather than probed blind.

---

## 2. PART 2 — WHAT IT RECORDS

`/users/{uid}/controller_health/{controllerId}`:

| Field | Source | Note |
|---|---|---|
| `lastProbeAt` | collector clock | |
| `lastProbeOutcome` | command `status` | `completed` / `failed` / `expired` / `timeout` / `pending` / `missing` |
| **`lastProbeBlame`** | derived | **`none` / `bridge` / `controller` / `app` / `unknown`** — the field that makes the record actionable |
| `lastSuccessAt` | last `completed` | how stale the version data is |
| **`firstFailureAt`** | folded, on the 0→1 transition | **Q3** — makes duration independent of probe cadence |
| **`lastCollectedAt`** | every collect | proves the collector ran without disturbing the backoff clock |
| `consecutiveFailures` | folded | resets on success; counts **probes**, not days |
| **`probeCadence`** | derived | `daily` / `weekly` — a skip is auditable |
| **`bridgePresence`** | registry + `bridge_status` | **Q1** — `live` / `silent` / `never`; `never` suppresses alerts |
| `probeLatencyMs` | `completedAt − createdAt` | |
| `lastError` | bridge `error` | truncated to 300 |
| `wledVersion`, `wledVid`, `ledCount`, `rgbw`, `wledRelease` | parsed `result` | **sticky** — see below |
| `bridgeDeviceId`, `bridgeLastSeen`, `bridgeFirmwareVersion`, `bridgeStatus` | `bridge_registry` | |
| `probeTargeting` | derived | only `server_resolved_ip` is produced (§1.1) |

**`blame` is the whole point of S2's `expired` ≠ `failed` distinction**, and it is preserved
end to end: `expired` → the **bridge** was unreachable (nobody picked it up); `failed` → the
**controller** was (the bridge picked it up and WLED refused). Collapsing them would destroy
the only fleet-visible way to tell "customer's bridge is down" from "customer's controller is
down". A test asserts the two blames differ.

**Version fields are sticky.** A failed probe carries no `/json/info` body; blanking the
last-known version on every failure would destroy exactly the fleet-build signal this exists
to collect. `lastSuccessAt` tells you how old it is.

**`missing` never counts as a failure.** A skipped probe (in-flight guard) or a
retention-deleted document is an absence, not evidence of ill health. Manufacturing a failure
from an absence is how a monitor starts lying.

**`cn` is NOT recorded, deliberately.** The Iron Reserve's controller reports `"cn":"Kōsen"` —
byte-identical to the bench controller's. It is a flash-image default, not a per-install
identifier, and treating it as one would silently merge two sites. Asserted by a test that
greps the serialized health document for the string.

---

## 3. PART 3 — THE ALERTS, AND HOW TYLER SEES THEM

### 3.1 The alerts

| Kind | Severity | Fires when | The case it would have caught |
|---|---|---|---|
| `controller_unreachable` | **warn @1**, **alert @2** consecutive failed probes | — | Ellie Cochran as a warning on **day 1** and an alert on day 2, instead of invisible for 15 days |
| `bridge_paired_but_silent` | alert | registry `paired`, silent > 24 h | Both bucket-B customers |
| `bridge_superseded_orphan` | **warn** | as above, but the account has **another paired row that is live** | **Brooke Rozenberg** — see below |
| `bridge_unpaired_but_heartbeating` | alert | registry `unpaired`, seen < 60 min ago | **The Iron Reserve**, on day 1 instead of day 5 |
| `bridge_claims_unknown_uid` | alert | `pairedUid` has no user document | The **F-5b** stranded shape. Zero today; the value is catching the *first* |

**Two tiers, deliberately.** The brief asked for day-1 detection. But a single missed probe is
also what a router reboot looks like, and paging on one miss trains the reader to ignore the
digest — recreating the exact failure this exists to fix. So: **warn at 1** (visible next
digest — day-1 detection as asked), **alert at 2** (act on it).

**The superseded-orphan discriminator was added because the seed dry run produced the wrong
call list.** Brooke's replaced-in-place bridge (`0070077E8F60`, silent 23.7 d) sits beside her
live one, and its staleness is close enough to two genuine outages (23.1 d, 16.8 d) to be
mistaken for one — which is precisely the question that came up on 2026-08-05. Without the
discriminator the digest put a **healthy customer at the top of the call list**. Now a silent
row whose account has a fresh sibling is a `warn` that says *"NOT a customer outage; clear the
stale row so it stops inflating the offline count."* Three tests pin it, including the pair
where only the sibling differs.

### 3.2 How Tyler sees it — **recommendation: a pushed email digest, plus a Firestore snapshot**

A Firestore collection alone **repeats the current failure**. The data that would have shown
Ellie's outage already existed — `bridge_status/current` was sitting there, stale, for 15
days. It was not a data gap; it was a *nobody-looked* gap. Adding another collection to not
look at solves nothing.

So the primary surface is **push**:

- **A digest email** via the repo's existing `sendEmail` (Resend, `messaging-helpers.ts`).
  No new infrastructure, no new dependency, no app release, no rules change, and it lands in
  an inbox Tyler already reads.
- **Sent only when there is something to say** — otherwise it becomes noise and gets
  filtered, which is the same failure by a slower route.
- **Plus a weekly Monday all-clear even when there is nothing.** This is not decoration.
  Without it a silent inbox is ambiguous between *"the fleet is healthy"* and *"the monitor
  has been throwing for three weeks"* — and this repo has already shipped one scheduled
  routine that never ran and went unnoticed for months (`scheduledDataCleanup`,
  COMMAND_SAFETY D2). **A heartbeat that must arrive weekly makes failure of the monitor
  itself detectable.**

The secondary surface is **pull**: `/fleet_health/{YYYY-MM-DD}` — full alert list, counts and
stats per day. Scriptable, historical, and the natural read source for a future in-app dealer
dashboard.

**If `FLEET_HEALTH_DIGEST_TO` is unset, the collector logs an ERROR naming the number of
alerts that were computed and sent nowhere.** An alerting system that quietly sends nowhere is
worse than none, because it manufactures confidence.

**Not recommended: FCM push to Tyler's phone** (no per-device targeting exists for a
non-customer recipient, and it would need an app change) or **a new in-app screen** (that is
the app half, P5a, and it should read `controller_health` once this has run long enough to be
trustworthy).

---

## 4. PART 4 — BACKFILL

`backfillControllerHealth` — admin callable, `{dryRun?: boolean}`, seeds every controller's
health document from currently-knowable state so the first alert run has a baseline instead
of treating a three-week-dark bridge as a brand-new controller with zero failures.

**Derived live, not hardcoded from the triage.** Hardcoded findings rot: one of them was
repaired the same evening it was written (the Iron Reserve). Re-deriving means the seed is
correct whenever it runs.

In seed mode the probe fields are left **null** — there was no probe, and a `missing` outcome
must not masquerade as a measurement — while a bridge silent over 24 h seeds
`consecutiveFailures: 1`, so a known-bad account is a **warning on the first digest** rather
than starting at zero and hiding a 21-day outage for two more days.

**Dry run against production, 2026-08-06 — no writes:**

```
stats: {"controllers":15,"probed":0,"missing":15,"seeded":15,"written":0}

ALERTS: 5  (alert=2  warn=3)
 [ALERT] bridge_paired_but_silent   cpaschall10@gmail.com        D4E9F4FAA5F4  23.1d
 [ALERT] bridge_paired_but_silent   ecochran08@yahoo.com         D4E9F4FA9D40  16.8d
 [WARN ] bridge_superseded_orphan   brooke.rozenberg1@gmail.com  0070077E8F60  23.7d
 [WARN ] controller_unreachable     ecochran08@yahoo.com         D4E9F4FA9D40  never probed
 [WARN ] controller_unreachable     cpaschall10@gmail.com        D4E9F4FAA5F4  never probed
```

**That is the hand-written triage, reproduced independently by code** — the same two customers
to call, Brooke correctly demoted to a cleanup task, and the Iron Reserve correctly absent
because it was repaired.

> **It also caught an identity defect the triage did not.** The seed logged:
> `identity mismatch for Q8VIQ9lrIA… — auth=brooke.rozenberg1@gmail.com
> doc=brooke.rozenberg@gmail.com; using auth`. The `users/{uid}.email` field **disagrees with
> the Firebase Auth record** for at least one customer. A digest is a **call list**, so it now
> takes identity from Auth — the address the person actually signs in with and receives mail
> at — with the doc field as fallback, and logs every mismatch. Batched via `getUsers`
> (100/call), degrading to the doc email on lookup failure rather than throwing.

---

## 5. VERIFICATION

### 5.1 Unit — `cd functions && npm run build && npx jest test/unit`

**5 suites, 143 tests, all passed** (77 new in `controllerHealth.test.js`; the suite was 66
before S6, and 122 before the §9 decisions).

Covered: every outcome→blame mapping; `expired ≠ failed` asserted directly; `missing` and
`pending` never counting as failures; negative latency reporting null rather than nonsense;
the **real Iron Reserve `/json/info` payload** parsed correctly and `cn` provably absent;
malformed/typed-wrong JSON never throwing; sticky version fields across a failure;
consecutive-failure fold in every direction; all five targeting cases including the
`bridge_paired_fallback` regression lock; all six in-flight-guard shapes including the two
real app writers that send no usable `controllerId`; every alert shape anchored to the
2026-08-05 fleet (Ellie, Iron Reserve, Brooke's orphan, F-5b); alert ordering; and the
digest-suppression rule including the Monday all-clear. Plus four constant-property tests so
a future edit cannot silently break `PROBE_GRACE_MS ≥ MIN_SWEEPABLE_AGE_MS`.

**Added for the §9 decisions (21 more):** every backoff boundary including the exact 7-day
edge; the recovery path from 40 failures back to `daily`; the **missing-collect-must-not-reset-
the-backoff-clock** case; Tyler's 60-days-as-11-failures case reported as 60 days;
`firstFailureAt` stamped once and not moving; `never` suppression versus `silent` alerting;
the roster split and its ordering; and the empty-`display_name` blank-line fix.

### 5.2 Bench, end to end — `scripts/_verify_controller_health.js`

Exercises the **real compiled functions** (`probeOneController`, `collectAll`, `classifyProbe`),
not a reimplementation, scoped to the bench account via `--uid`. **23 passed, 0 failed.**

```
TEST 1  probe write + targeting               PASS  fire_health_192_168_1_150_1786115923
                                              PASS  controllerIp NAMED = 192.168.1.150
                                              PASS  expiresAt = createdAt + 90s (not 120s)
TEST 2  one-in-flight guard                   PASS  second probe refused, reason=in_flight
TEST 3  end-to-end delivery                   PASS  completed, latency 1705 ms
        {"wledVersion":"0.15.1","wledVid":2507300,"ledCount":290,"rgbw":true,
         "release":"ESP32_Ethernet"}
TEST 4  collectAll writes controller_health   PASS  outcome=completed, failures=0,
                                              PASS  cn NOT present anywhere in the doc
TEST 5  forced failure → 192.168.1.199        PASS  failed (NOT expired), blame=controller
TEST 6  real production `expired` document    PASS  blame=bridge, not a success
```

Three things worth pulling out:

- **1705 ms** sits inside the **1.1–1.9 s** band [SCHEDULING_ARCHITECTURE_V2 §5](audit/SCHEDULING_ARCHITECTURE_V2.md)
  predicted for a cloud-initiated fire from per-hop measurements. That prediction had never
  been tested; it is now.
- **`failed` vs `expired` was verified both ways** — a *forced* controller failure on the
  bench, and a *real* production `expired` document from the Iron Reserve's backlog. The
  expired case was not manufactured.
- **`ledCount: 290`** matches the bench's known segment span (seg 0 covering 0–290).

**One thing the harness does NOT prove:** the `onSchedule` wrappers' fleet iteration. It calls
the per-controller and per-user logic directly, scoped to one account, so the loop that walks
every user has run only in the seed dry run (which did traverse all 24 users and 15
controllers, read-only). Stated rather than implied.

### 5.3 Dart suite — read against a tree another session is editing

**This work changed zero Dart files**, and nothing in `functions/`, `functions/test/`,
`scripts/` or `audit/` is in the Flutter package's source set, so it cannot affect
`flutter test`. The suite is therefore a confirmation, not a signal — but the run needs
explaining, because the first one looked alarming.

| Run | Result |
|---|---|
| First, ~09:05 | `+1812 ~3 -16` — **16 failures** |
| Second, settled tree | `+1933 ~3 -2` — **2 failures** |

**The totals differ (1831 vs 1938), which is the tell: the tree changed between runs.** The
other window was actively editing `lib/features/wled/*` while the first run was in progress,
so it executed against a transiently inconsistent mix of old and new files. The second run is
the one to read.

The two remaining failures:

1. `test/features/ai/cloud_ai_processor_normalize_test.dart` — *"typed coercion: garbage field
   values in a well-formed Map entry → defaults, no throw"*. **The expected pre-existing
   failure**, tracked as P1-8 and named in the brief.
2. `test/features/wled/controller_defaults_healer_test.dart` — *"audioreactive heal (LAN)
   ENABLED → exactly one surgical POST + readback verify, NO reboot"*. **The other session's
   in-flight work**, not mine: `controller_defaults_healer.dart` is one of the six modified
   files, and `audit/GAMMA_BUG.md` §TL;DR states the defect being fixed there is *"a
   self-defeating ordering defect inside the healer: it asserts gamma at step (d), then
   performs an AudioReactive cfg POST at step (e) that wipes the gamma it just set."* That is
   the same assertion the failing test makes.

> **I deliberately did not stash, revert or "fix" any of it.** Getting a clean baseline would
> have meant ripping in-flight work out from under another window. The scope argument above is
> sufficient: a change confined to `functions/` cannot fail a Dart test. If a clean baseline is
> wanted later, `git worktree` on a fresh checkout is the non-destructive way to get one.

---

## 6. CHANGED FILES

| File | Change |
|---|---|
| [functions/src/controllerHealth.ts](functions/src/controllerHealth.ts) | **NEW** — pure contract: outcome/blame classification, `/json/info` parsing, health fold, probe targeting, in-flight guard, alert evaluation, digest-suppression rule |
| [functions/src/probeControllerHealth.ts](functions/src/probeControllerHealth.ts) | **NEW** — daily `onSchedule` probe writer |
| [functions/src/collectControllerHealth.ts](functions/src/collectControllerHealth.ts) | **NEW** — `onSchedule` collector + alerts + digest, and `backfillControllerHealth` callable |
| [functions/index.js](functions/index.js) | Exports the three new functions |
| [functions/test/unit/controllerHealth.test.js](functions/test/unit/controllerHealth.test.js) | **NEW** — 56 unit tests |
| [scripts/_verify_controller_health.js](scripts/_verify_controller_health.js) | **NEW** — bench end-to-end harness against the compiled functions |

**No Dart files changed. No `firestore.rules` change. No `firestore.indexes.json` change.**

**Why no rules change, deliberately:** `controller_health` and `fleet_health` are written by
the Admin SDK (which bypasses rules) and read by no client today. Adding an undeployed rules
block would leave a landmine for whoever next deploys rules for an unrelated reason —
`firestore.rules` should be deployable at any moment. The rule the **app half (P5a)** will
need, when a client first reads this:

```
match /users/{userId}/controller_health/{controllerId} {
  allow read: if isOwner(userId) || staffMayReach(userId) || hasAdminOrOwnerClaim();
  allow write: if false;   // Admin SDK only
}
match /fleet_health/{dayKey} {
  allow read: if hasAdminOrOwnerClaim();
  allow write: if false;
}
```

**Why no index change:** both queries are single-field and auto-indexed —
`where("status","in",[...])` decomposes to equality on one field, and
`where("source","==",...)` is a plain equality. Confirmed empirically on the bench (both ran
against production without a `FAILED_PRECONDITION`). This is a real advantage over the S2
sweeper, which needed a COLLECTION_GROUP composite deployed first.

---

## 7. WHAT DEPLOYING WOULD COST

### 7.1 Firestore operations, per day, at today's fleet (15 controllers, 24 users)

| Operation | Count/day | Note |
|---|---|---|
| **Writes** — probe command `create` | 15 | |
| **Writes** — bridge status updates (`executing`, `completed`) | 30 | The bridge already does this for every command |
| **Writes** — `controller_health` docs | 15 | |
| **Writes** — `fleet_health/{date}` snapshot | 1 | |
| **Deletes** — retention sweeps the probes after 7 days | 15 | Existing `runDataCleanup` |
| **Reads** — users ×2 passes | 48 | |
| **Reads** — controllers, in-flight query, probe read-back, health read, registry | ~130 | |
| | | |
| **≈ 61 writes, ~180 reads, 15 deletes per day** | | |

Firestore's free tier is **20,000 writes / 50,000 reads / 20,000 deletes per day**. This is
**~0.3 % of the write allowance** and ~0.4 % of reads. At **10× the fleet** (150 controllers)
it is ~600 writes/day — still ~3 %.

Two Cloud Function invocations per day, each well under a second of billable time at this
scale. One to five Resend emails per week.

**Monetarily this is free.** The honest costs are elsewhere:

### 7.2 The real costs

1. **A daily write per controller lands in `/users/{uid}/commands`.** Steady state is +15
   documents/day, ~105 at any time under the 7-day retention. It slightly enlarges the
   collection the sweeper scans each minute — negligible, but it is a permanent additive load
   on the one collection that is already load-bearing for remote control.
2. **The probe competes for the bridge's serial poll.** Bounded by the in-flight guard and by
   firing at 04:15 Central, but non-zero. If a customer is awake and using the app at exactly
   that minute, their command queues behind a probe for ~1.7 s.
3. **`FLEET_HEALTH_DIGEST_TO` must be set before deploy**, or the alert half computes and
   sends nowhere (loudly logged, but still nowhere).
4. **Node.js 20 is decommissioned 2026-10-30** (COMMAND_SAFETY D6). These are new 2nd-gen
   functions on Node 20; they inherit that deadline and will need a runtime bump with
   everything else.
5. **A `getInfo` probe reaches only as far as the bridge does.** For the 7 accounts with **no
   bridge at all**, every probe will expire, every day, forever — correctly reporting
   `blame: bridge`, but generating a permanent standing alert for accounts that were never
   sold a bridge. **See §9, open question 1** — this needs a suppression decision before the
   digest is useful.

### 7.3 Deploy sequence

| # | Step | Command | Verify before proceeding |
|---|---|---|---|
| 1 | Set the digest recipient | add `FLEET_HEALTH_DIGEST_TO=…` to `functions/.env` | Present alongside the existing `RESEND_*` params |
| 2 | Deploy the three functions | `cd functions && npm run build && firebase deploy --only functions:probeControllerHealth,functions:collectControllerHealth,functions:backfillControllerHealth` | All three "Successful create operation" |
| 3 | **Dry-run** the seed | callable `backfillControllerHealth` `{"dryRun": true}` | Matches §4's expected output |
| 4 | Seed for real | `{"dryRun": false}` | `written` = controller count |
| 5 | Wait for the first 09:15 UTC probe pass | — | Logs reconcile: `controllers == written + skipped + errors` |
| 6 | Check the 09:30 collect pass | — | `controller_health` populated; digest arrives |
| 7 | Spot-check one健 health doc against a manual `getInfo` | — | `wledVersion` agrees |

Rollback is clean: delete the three functions. Nothing else references them; `controller_health`
and `fleet_health` are additive and harmless if left.

**Invoking the callable needs an admin claim, which zero of the fleet's 124 auth users hold**
(COMMAND_SAFETY D3) — mint a short-lived custom token, per the established pattern in
`scripts/_run_backfill_controller_ips.js`.

---

## 8. FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **"Omit `controllerIp`" is wrong on the current fleet.** An untargeted bench probe returned `ERROR: HTTP -1` while 282 named commands to the same controller completed. The firmware's distinct empty-fallback error proves `pairedWledIp` was populated and **stale**. The advice was reasoned about across two audit documents and **never tested against a bridge** | **P1 — corrected here, regression-locked** |
| 2 | **No shipping app writer omits `controllerIp`** — only the three lightly-used voice integrations do. The omit path is effectively unexercised in production, which is why its staleness went unnoticed | Context for #1 |
| 3 | **Safety from provenance, not absence.** Naming a server-resolved IP is as safe as omitting and is *verifiable*; omission buys unredirectability at the price of an unverifiable target — fatal for a monitor, which would have reported the whole fleet dark | Design principle |
| 4 | **The seed reproduces the hand-written triage exactly** — same two customers to call, Brooke correctly demoted, Iron Reserve correctly absent after its repair | Validates the whole approach |
| 5 | **`users/{uid}.email` disagrees with the Firebase Auth record** for at least one customer. A digest is a call list, so identity now comes from Auth with the doc as fallback, and every mismatch is logged | **P2 — new, and it would have mis-addressed a customer** |
| 6 | **A superseded-orphan registry row would have put a healthy customer top of the call list.** The discriminator (silent row + live sibling on the same account → `warn`, not `alert`) is what keeps the digest actionable | **P1 for usefulness** |
| 7 | **Measured cloud-fire latency 1705 ms**, inside V2 §5's predicted 1.1–1.9 s band. That prediction was derived from per-hop measurements and had never been end-to-end tested | Confirms a load-bearing estimate |
| 8 | **`commandSafety.fireJobDocId` and the one-in-flight guard both get their first caller here.** Both were shipped in S2 as uncalled contracts; both now work against a live bridge | Closes an S2 loose end |
| 9 | **`failed` vs `expired` verified in both directions** — a forced controller failure on the bench and a real production `expired` document. The distinction S2 fought to preserve is what makes the health record actionable | Validates S2 |
| 10 | **No new index and no rules change required.** Both queries are single-field auto-indexed — a real simplification versus the sweeper, which needed a composite deployed first | Deploy risk ↓ |
| 11 | **7 accounts have no bridge at all**, so their probes will expire daily and forever. Without a suppression rule the digest carries a permanent standing alert for customers who were never sold a bridge | **P1 — open, see §9** |
| 12 | The bench harness loads `firebase-admin` from `functions/node_modules` explicitly; the repo-root copy is a **different `@google-cloud/firestore` instance** whose `serverTimestamp()` sentinel the functions' copy rejects outright | Gotcha, documented in the script |
| 13 | **The bench bridge's `wledIp` is `0.0.0.0`** — the pairing completed and never recorded a controller address. `"0.0.0.0"` is not empty, so the firmware's `controllerIp.isEmpty()` guard never fires and it dials an unroutable host. The bridge self-reports `paired: true, authenticated: true` throughout | **P1 — separate pairing-flow/firmware defect, logged not fixed (§9 Q4)** |
| 14 | **The three voice integrations omit `controllerIp` by design and rely on exactly that fallback.** If other bridges share the `0.0.0.0` state, voice control is silently broken for those accounts. No untargeted command exists in the 7-day retained window fleet-wide, so voice is either unused or aged out — **unmeasured, not cleared.** `wledIp` is NVS-only and not in Firestore, so this cannot be answered remotely | **P1 — open, needs a LAN check per site** |
| 15 | **The backoff clock was nearly self-defeating.** `lastProbeAt` initially advanced on every collect including `missing`, which would have reset the 7-day retry daily and left dark controllers never re-probed. Caught by the decision work, fixed, test-locked | **P1 — caught pre-deploy** |
| 16 | `display_name: ""` (empty string, not null) defeated an `??` fallback chain and rendered a **blank roster line** naming nobody. Same class as the earlier `displayName`-vs-`display_name` trap: a call list that cannot be acted on | P3, fixed |
| 17 | **A concurrent session is editing `lib/features/wled/*` in this same tree.** A `flutter test` run taken mid-edit reported **16** failures; a re-run on a settled tree reported **2**, with different totals (1831 → 1938). **A test count taken while another window is writing is not a measurement** — check `git status` before trusting one | Method, and it nearly produced a false alarm |

---

## 9. DECISIONS — Tyler, 2026-08-07. All four applied.

### Q1 — no-bridge accounts: **option (b)** — probe, suppress the alert, roster them

> *"Option (a) — skip probing accounts with no registry row — would have hidden the Iron
> Reserve, which is the case this whole system exists to catch."*

**Implemented.** A new `bridgePresence: "live" | "silent" | "never"` on every health record:

| Value | Condition | Effect |
|---|---|---|
| `live` | registry row seen within 60 min | normal alerting |
| `silent` | a registry row exists **or** `bridge_status/current` has ever existed, but it is not reporting now | **alerts normally** — this is Ellie |
| `never` | no registry row **and** no `bridge_status/current`, ever | **`controller_unreachable` suppressed**; still probed; appears only on the roster |

`never` requires **both** halves. `bridge_status/current` is written only once a bridge has
adopted a uid, so its existence is the definitive "a bridge once reported here" signal — the
same one the 2026-08-05 triage relied on. An account whose registry row was deleted but which
once reported is `silent`, **not** `never`, and keeps its alerts.

**The roster distinguishes the two conversations, as asked** — `buildRoster()` returns two
lists, rendered as separate digest sections:

```
ROSTER — 8 controller(s) without a live bridge:
  NEVER HAD A BRIDGE (6) — alerts suppressed; sales/records question, not a support call:
    dbrosa99@icloud.com · dnicholas0131@gmail.com · jjdyer1@hotmail.com
    nex-genadmin@nex-genled.com · staff_installer_5502 · thegruenewalds@gmail.com
  HAD ONE, NOW SILENT (2) — these are the support calls, and they alert above:
    cpaschall10@gmail.com  D4E9F4FAA5F4  23.2d
    ecochran08@yahoo.com   D4E9F4FA9D40  16.8d
```

Suppression is verified two ways: a unit test asserting a `never` row with 30 failures
produces **zero** alerts, and its twin asserting a `silent` row with 5 failures still alerts.

> **One defect the roster itself exposed.** `staff_installer_5502` carries
> `display_name: ""` — an empty string, not null — so the obvious
> `email ?? displayName ?? uid` chain passed it straight through and rendered a **blank
> roster line**: a row naming nobody, which is unactionable. Fixed with an explicit
> non-empty fallback. Small, but a call list with an anonymous row in it is the same class
> of defect as a mislabeled one.

### Q2 — superseded orphan: **keep as `warn`**

**No change.** It stays a `warn` with copy that leads on *"NOT a customer outage; clear the
stale row so it stops inflating the offline count."* Three tests pin the behaviour, including
the pair where only the live sibling differs — same device, same 22-day staleness, opposite
classification.

### Q3 — dark controllers: **daily → weekly after 3 consecutive failures**

**Implemented.** `shouldProbeToday()` is consulted before every write:

- `consecutiveFailures < 3` → probe daily
- `>= 3` → probe only when `now − lastProbeAt >= 7 days`, skip reason `backoff_weekly`
- no recorded `lastProbeAt` despite failures → probe anyway rather than stall forever

**Recovery returns to daily automatically**, with no separate cadence state to reconcile: a
success sets `consecutiveFailures = 0`, and the cadence is *derived* from that counter. A test
takes a record at 40 failures / 60 days dark, feeds it one success, and asserts the very next
run is back to `daily`.

#### The distortion, and how it is handled

> *"a controller dark 60 days should not read as 11 failures."*

Correct — and **`consecutiveFailures` is not adjusted to hide it**, because the count is
honest about what it measures: probes, not days. Inflating it to match elapsed time would make
it lie about both. Instead **duration is read from a timestamp and is independent of the
sampling rate**:

- **`firstFailureAt`** — new field, stamped on the `0 → 1` transition, cleared on success.
- **`darkForMs()`** — prefers `lastSuccessAt` (it once worked), falls back to `firstFailureAt`
  (it never has), null when neither is known.
- The alert now **leads with duration**: `dark 23.2d (never successfully probed) — bridge
  unreachable (last outcome: expired); 1 failed probe(s) at weekly cadence`.

A test encodes Tyler's exact case: `{lastSuccessAt: T0 − 60d, consecutiveFailures: 11}` →
reports **60 days**.

#### A load-bearing bug this surfaced

The backoff keys on `lastProbeAt`. As originally written, `foldProbeIntoHealth` set
`lastProbeAt = now` on **every** collect, including a `missing` outcome — so a backed-off
controller's "7 days since the last probe" clock would have **reset daily and the weekly retry
would never have fired.** The controller would have gone permanently dark to us, silently.

Fixed: `lastProbeAt`, `lastProbeOutcome` and `lastProbeBlame` now advance **only when a probe
document was actually observed**; a new `lastCollectedAt` always advances and carries the
"the collector ran" signal. A test asserts a skipped day leaves `lastProbeAt` unmoved and that
the retry fires at day 7.

**Seed mode stamps duration too.** The first dry run reported the two known outages as
"duration unknown" — precisely the baseline the seed exists to avoid. The seed now sets
`firstFailureAt` from the bridge's last heartbeat, so the first digest reads `dark 23.2d`
rather than shrugging.

### Q4 — bench bridge `pairedWledIp`: **checked. It is `0.0.0.0`.** Logged, not fixed.

```
GET http://192.168.1.96/api/bridge/status
{ "paired": true, "authenticated": true, "wifi": true, "wledIp": "0.0.0.0",
  "commands": 565, "errors": 857, "uptime": 1448996, "version": "1.2" }
```

**Not the config-drift I predicted.** It is not a stale `.250`; the pairing completed and
**never recorded a controller address at all**. Three things follow, and none is an S6 issue:

1. **The firmware's empty-check is defeated by a non-empty sentinel.**
   `if (controllerIp.isEmpty())` is false for `"0.0.0.0"`, so the "no controller IP" guard at
   [main.cpp:806-811](esp32-bridge/src/main.cpp#L806) never fires and the bridge dials an
   unroutable address instead of failing loudly.
2. **The bridge reports itself healthy while being unable to reach anything untargeted** —
   `paired: true, authenticated: true`. Its own status endpoint would not have told anyone.
3. **⚠ The three voice integrations omit `controllerIp` by design** (Google Smart Home, Alexa,
   standalone google-home — writers #5/#8/#9 in COMMAND_SAFETY §1.1). They rely on exactly the
   fallback that is `0.0.0.0` here. **If other bridges share this state, voice control is
   silently broken for those accounts.** I checked: the 7-day retained window contains **no
   untargeted command from any account** except my own probe — so voice is either unused or
   its evidence has aged out. **Unmeasured, not cleared.** `wledIp` is not in Firestore
   (it lives in NVS and is only exposed on the LAN endpoint), so this cannot be answered
   fleet-wide from here — it needs a LAN check per site, or a firmware change to publish it.

**Filed as a pairing-flow/firmware defect, independent of S6. Not fixed here.** S6 is immune
because it always names the IP (§1.1) — and it was S6's bench run that found this.
