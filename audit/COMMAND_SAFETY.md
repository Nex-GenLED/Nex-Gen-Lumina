# COMMAND SAFETY — S1 (controllerIp validation) + S2 (command expiry)

**Date:** 2026-08-01 · **Branch:** `main` @ `ebef9fd` (2.5.10+60), working tree · **No branch created.
Nothing deployed.**

**Why now, independent of the scheduler.** [SCHEDULING_ARCHITECTURE_V2.md §4](audit/SCHEDULING_ARCHITECTURE_V2.md)
found three defects live in production today, on every account. They are worth closing whether or not
the event dispatcher (S3) ever ships; they also hard-gate it. This document implements the fixes and
records what they do and do not cover.

**Deployment status: NOTHING IS DEPLOYED.** Rules go live globally and instantly, and the rule in
this change **will break the fleet if deployed in the wrong order**. §5 has the required sequence.
Everything below is verified locally against the real Rules `:test` API.

---

## 1. THE BREAKS-LIST — ten writers, not four

**This was the gate, and it caught a real error in my own prior document.**
[SCHEDULING_ARCHITECTURE_V2.md §8](audit/SCHEDULING_ARCHITECTURE_V2.md) said "This document found
four writers." That count was built from `lib/` and `functions/index.js`. The full enumeration across
`lib/`, `functions/` (including `functions/src/*.ts`), `alexa-skill/` and `google-home/` finds **ten**
— and two of the ones it missed are exactly the kind that "would break silently."

### 1.1 Writers to `/users/{uid}/commands` — complete

| # | Writer | file:line | Sets `controllerIp`? | Sets `expiresAt`? | Subject to rules? |
|---|---|---|---|---|---|
| 1 | `CloudRelayRepository._executeCommand` — the main relay path | [cloud_relay_repository.dart:95](lib/features/wled/cloud_relay_repository.dart#L95) | **Yes**, from the repo's constructor | No | **Yes** (client SDK) |
| 2 | `BridgeHealthService.check` | [bridge_health_service.dart:35-46](lib/services/bridge_health_service.dart#L35-L46) | **Yes** — and **no `controllerId` at all** | No | **Yes** |
| 3 | Remote-access webhook check | [remote_access_screen.dart:288](lib/features/site/remote_access_screen.dart#L288) | Yes | No | **Yes** |
| 4 | Bridge-setup verification ping | [bridge_setup_screen.dart:617](lib/features/site/bridge_setup_screen.dart#L617) | **Yes** — with `controllerId: ''` | No | **Yes** |
| 5 | Google Smart Home (main functions) | [functions/index.js:1416-1424](functions/index.js#L1416-L1424) | **No** ✅ | Yes, 60 s | No — Admin SDK |
| 6 | `applySyncPattern` direct enqueue | [functions/src/applySyncPattern.ts:243](functions/src/applySyncPattern.ts#L243) | **Yes** | **No** | No — Admin SDK |
| 7 | `applySyncPattern` member fan-out | [functions/src/applySyncPattern.ts:478](functions/src/applySyncPattern.ts#L478) | **Yes**, into **other users'** collections | **No** | No — Admin SDK |
| 8 | Alexa skill lambda | [alexa-skill/lambda/utils/firebase.js:118-129](alexa-skill/lambda/utils/firebase.js#L118-L129) | **No** ✅ | Yes, 60 s | No — Admin SDK |
| 9 | Standalone google-home function | [google-home/functions/index.js:350-362](google-home/functions/index.js#L350-L362) | **No** ✅ | Yes, 60 s | No — Admin SDK |
| 10 | `heal_fleet_ntp.js` (operator script) | [scripts/heal_fleet_ntp.js:149-157](scripts/heal_fleet_ntp.js#L149-L157) | **Yes** | No | No — Admin SDK |

**Not in scope, and confirmed distinct:** `NeighborhoodService` writes to
`/neighborhoods/{groupId}/commands` ([neighborhood_service.dart:582,657](lib/features/neighborhood/neighborhood_service.dart#L582)),
a **different collection** governed by [firestore.rules:1861](firestore.rules#L1861). Untouched here.

### 1.2 The two that a naive rule breaks — and why the estimate was wrong

The natural rule keys on `controllerId`:

```
get(/users/$(userId)/controllers/$(request.resource.data.controllerId)).data.ip
  == request.resource.data.controllerIp
```

It works for writer #1, where `controllerId` and `controllerIp` agree **by construction** —
`selectedControllerIdProvider` resolves the controllers doc id *by matching its `ip`*
([wled_providers.dart:239-255](lib/features/wled/wled_providers.dart#L239-L255)).

It **denies writers #2 and #4 outright**:

- **#4 `bridge_setup_screen.dart:617`** sends `'controllerId': ''` explicitly, with a real
  `controllerIp`. A `get()` on an empty doc id errors the ruleset → DENY. **This is the bridge
  pairing verification step.**
- **#2 `bridge_health_service.dart`** sends **no `controllerId` field at all** — and writes to a
  **fixed document id** (`bridge_health_check`) via `.set()`, so its second and every subsequent call
  is an **UPDATE, not a create**.

Rules go live globally and instantly against an installed fleet on 2.5.10+59/+60 that cannot be
changed to suit a new rule. A `controllerId`-keyed rule would have taken out bridge setup and bridge
health for every existing install the moment it deployed.

> **Correction to [SCHEDULING_ARCHITECTURE_V2.md §8](audit/SCHEDULING_ARCHITECTURE_V2.md):** the ~3 h
> estimate assumed a `controllerId` `get()` would just work. It does not. The real shape is an
> **IP allowlist**, which needs a denormalized field, a maintenance trigger, a backfill and a staged
> deploy. **Revised: ~8 h**, of which ~5 h is the safe-deployment machinery rather than the rule.

### 1.3 Server-side writers and the "should omit `controllerIp`" advice

[SCHEDULING_ARCHITECTURE_V2.md §8](audit/SCHEDULING_ARCHITECTURE_V2.md) said any server-side writer
*should* omit `controllerIp`, calling it "free, and strictly best." **That is too broad and is
corrected here.**

The bridge holds exactly **one** paired WLED IP (`pairedWledIp`,
[main.cpp:795-800](esp32-bridge/src/main.cpp#L795-L800)). Omitting the target only works when the
intended target *is* that paired controller. Writers #6/#7 (`applySyncPattern`) fan out to
**multiple controllers per user** — omitting the field would silently retarget every command at the
primary. They must name the IP.

**What makes #6/#7/#10 safe is not omission but provenance:** their IPs are resolved *server-side*
from the user's own `controllers` subcollection
([applySyncPattern.ts:339-369](functions/src/applySyncPattern.ts#L339-L369),
[heal_fleet_ntp.js:140-142](scripts/heal_fleet_ntp.js#L140-L142)) — never taken from client input.
They are validated by construction.

**Verdict: no server-side writer needs changing.** #5/#8/#9 already omit the field; #6/#7/#10
legitimately name it and derive it safely. Recorded rather than "fixed."

---

## 2. S1 — controllerIp validation

### 2.1 The hole

The bridge takes the target IP straight from the command document
([main.cpp:778-779](esp32-bridge/src/main.cpp#L778-L779)) and falls back to its paired IP only when
the field is empty ([:795-800](esp32-bridge/src/main.cpp#L795-L800)). Anyone who can write to
`/users/{uid}/commands` — owner-only, so: **a compromised customer account** — can make that
customer's bridge `POST` arbitrary JSON to **any host on their home LAN**. The bridge is an
unauthenticated HTTP client sitting inside the perimeter.

### 2.2 The change

**`users/{uid}.controller_ips`** — a denormalized, deduped, sorted array of the customer's registered
controller IPs, maintained by [functions/src/syncControllerIps.ts](functions/src/syncControllerIps.ts):

- `syncControllerIps` — `onDocumentWritten` on `users/{userId}/controllers/{controllerId}`. Fires on
  create, update **and delete**; delete matters most, or a decommissioned controller's IP stays a
  legal target forever. Writes only on change, and never throws (a failure here must not block
  controller writes).
- `backfillControllerIps` — admin-claim callable, `{ dryRun?: boolean }`, idempotent, recomputes from
  source and writes only on change.

**The rule** ([firestore.rules:528-597](firestore.rules#L528)):

```
function declaredControllerIp() {
  return request.resource.data.get('controllerIp', '');
}
function targetsOwnController() {
  return declaredControllerIp() == ''
    || (exists(/databases/$(database)/documents/users/$(userId))
        && declaredControllerIp() in
           get(/databases/$(database)/documents/users/$(userId))
             .data.get('controller_ips', []));
}
allow create: if isOwner(userId) && targetsOwnController();
allow update: if (isOwner(userId) && targetsOwnController()) || isBridgeForUser(userId);
```

Three deliberate properties:

1. **An empty/absent `controllerIp` is always allowed.** An untargeted command is unredirectable —
   the bridge uses its own paired IP. This is what keeps writers #2 and #4 working unchanged.
2. **`update` is validated too, not just `create`.** Writer #2 uses a fixed doc id with `.set()`, so
   validating create alone would leave a permanent bypass: write once with a good IP, then re-point
   it anywhere forever.
3. **The bridge's update branch is deliberately not IP-validated.** It writes status/result/error on
   a document whose target was already checked at create, and it authenticates as itself.

**Scope, stated plainly: this constrains APP writers only.** The Admin SDK bypasses security rules
entirely, so writers #5-#10 are unaffected by it. Their safety is the construction argument in §1.3,
which is recorded in the rule's own comment so a future reader does not mistake the rule for
whole-system coverage.

### 2.3 Verification — Rules `:test` API, 15 cases, ALL PASSED

`node scripts/_test_command_ip_rule.js` — read-only, no deploy. Every `get()`/`exists()` is satisfied
by an explicit `functionMock`, so results depend only on the rules text and are reproducible on any
machine.

```
PASS  expected=ALLOW actual=ALLOW  1. valid registered controllerIp → ALLOW
PASS  expected=DENY  actual=DENY   2. unregistered LAN host as controllerIp → DENY
PASS  expected=ALLOW actual=ALLOW  3. controllerIp field OMITTED → ALLOW (unredirectable)
PASS  expected=DENY  actual=DENY   4. another customer's controller IP → DENY
PASS  expected=ALLOW actual=ALLOW  5. empty-string controllerIp → ALLOW (bridge_setup_screen shape)
PASS  expected=ALLOW actual=ALLOW  6. registered IP with NO controllerId → ALLOW (bridge_health_service shape)
PASS  expected=DENY  actual=DENY   7. UPDATE re-pointing to an unregistered IP → DENY (the .set() bypass)
PASS  expected=ALLOW actual=ALLOW  8. UPDATE keeping a registered IP → ALLOW
PASS  expected=DENY  actual=DENY   9. another user writing into this user's commands → DENY
PASS  expected=DENY  actual=DENY   10. unauthenticated create → DENY
PASS  expected=ALLOW actual=ALLOW  11. owner read own command → ALLOW (read path untouched)
PASS  expected=ALLOW actual=ALLOW  12. owner delete own command → ALLOW (cleanup path untouched)
PASS  expected=DENY  actual=DENY   13. targeted write with NO user doc → DENY (conservative)
PASS  expected=ALLOW actual=ALLOW  14. untargeted write with NO user doc → ALLOW (still unredirectable)
PASS  expected=DENY  actual=DENY   15. PRE-BACKFILL: user doc with no controller_ips, targeted → DENY
ALL PASSED
```

Cases 1-4 are the four the brief specified. Cases 5-6 are the regressions writers #2/#4 demand.
Case 7 is the `.set()` bypass. **Case 15 is the empirical proof of the deploy-order hazard in §5** —
before the backfill runs, a legitimate targeted write is DENIED.

**An auth note worth recording:** the `android/app/…adminsdk…json` service account used by the
existing `_test_rules_block.js` / `_test_sync_fanout_rule.js` scripts **lacks
`firebaserules.rulesets.test`** (HTTP 403 IAM_PERMISSION_DENIED, verified 2026-08-01). The new
harness prefers `gcloud` ADC and falls back to the key. **The two existing rules-test scripts are
therefore currently non-functional** and will 403 for anyone who runs them — pre-existing, unrelated
to this change, and worth a one-line auth fix when someone next touches them.

### 2.4 Regression — differential, 53 paths, blast radius contained

The emulator rules suite (`functions/test/emulator/**`, ~170 cases across 11 files) **could not run
on this machine**: firebase-tools 15.13.0 requires **JDK 21** and this box has **JDK 17**. I am not
going to claim a regression that did not execute.

Instead — and this is stronger evidence for a rules edit — `node scripts/_test_rules_diff.js`
evaluates **the same 53 requests** against `git show HEAD:firestore.rules` and against the working
tree, then asserts the only behavioural differences are on `/commands` paths. It requires no
knowledge of each rule's intent; it measures the blast radius directly.

```
Cases: 53
HEAD rules: 102165 bytes    Working-tree rules: 105786 bytes

IN-SCOPE   ALLOW → DENY   commands: owner create, UNREGISTERED ip
IN-SCOPE   ALLOW → DENY   commands: owner update, UNREGISTERED ip

Probed:        53      Unchanged:  51
Changed:        2      Out-of-scope: 0
BLAST RADIUS CONTAINED
```

Coverage spans `/users/{uid}` and 20 subcollections (controllers, pixelMap, schedules, bridge_status,
geofences, properties, game_day_autopilot, ephemeral_game_sessions, brand_profile, commercial_*,
referrals, favorites, designs, patterns, suggestions, debug_errors, roofline_config, ai_usage) plus
`bridge_registry`, `installers`, `installations`, `invitations`, `dealers`, `app_config/*`,
`referral_codes`, `referral_payouts`, `demo_leads`, `email_notifications`, `sites`, `devices` — as
owner, stranger, bridge, installer-claim, and unauthenticated.

**Exactly two behavioural changes, both intended. Zero stray changes.**

---

## 3. S2 — command expiry

### 3.1 What was actually there

| Finding | Evidence |
|---|---|
| **The bridge has no age check of any kind.** `executeCommand` reads `type` and `controllerIp` and fires. It never reads `createdAt` or `expiresAt`. | [main.cpp:763-845](esp32-bridge/src/main.cpp#L763-L845) |
| **The Cloud Function's 5-minute check is dead code fleet-wide.** The bridge-mode early return is at `:338-343`; the age check is at `:348-360` — *after* it. Every production account is bridge-mode. | [functions/index.js:338-360](functions/index.js#L338-L360), [LEASE_EXPOSURE.md §1.3](audit/LEASE_EXPOSURE.md) |
| **`expiresAt` is written by three writers and read by nobody.** A repo-wide grep finds no reader in the bridge, in `executeWledCommand`, or in `CloudRelayRepository`. **The TTL convention was designed; the enforcement half was never built.** | [functions/index.js:1423](functions/index.js#L1423), [google-home/functions/index.js:362](google-home/functions/index.js#L362), [alexa-skill/lambda/utils/firebase.js:129](alexa-skill/lambda/utils/firebase.js#L129) |
| **Commands are retained 7 days**, so a `pending` command stays eligible for pickup that entire time. | [functions/index.js:1000](functions/index.js#L1000) |
| **The poll has no `orderBy`**, and ids are non-sortable Firestore auto-ids, so a backlog drains in unspecified order — an ON and an OFF can invert. | [main.cpp:692-698](esp32-bridge/src/main.cpp#L692-L698) |

### 3.2 The change

[functions/src/commandSafety.ts](functions/src/commandSafety.ts) — the shared contract (pure, no
`firebase-admin` at module scope, so it unit-tests against compiled `lib/` with no emulator).
[functions/src/sweepExpiredCommands.ts](functions/src/sweepExpiredCommands.ts) — an `onSchedule`
running **every 1 minute** that transitions `status == "pending"` past its effective expiry to
`status: "expired"`.

**Why flipping status is a complete remedy with no firmware change:** the bridge's poll filters
`status == "pending"`, so an expired command becomes invisible to it. That matters because there is
no OTA in the bridge firmware — "deploy firmware" currently means visiting each unit with a USB cable.

**`expired` is deliberately distinct from `failed`:**

- `expired` → the **bridge** was unreachable (nobody picked it up)
- `failed` → the **controller** was unreachable (bridge picked it up; WLED refused or timed out)

Collapsing them would destroy the only fleet-visible way to tell "customer's bridge is down" from
"customer's controller is down" — the distinction
[SCHEDULING_ARCHITECTURE_V2.md §6](audit/SCHEDULING_ARCHITECTURE_V2.md) telemetry depends on.

Also added: a `COLLECTION_GROUP` composite index on `commands(status, createdAt)`
([firestore.indexes.json](firestore.indexes.json)). The sweeper fails loudly if it is missing —
a silently-not-running sweeper is exactly the defect class this change exists to remove.

### 3.3 The default TTL — 120 s, and why

**Decision: `DEFAULT_COMMAND_TTL_MS = 120_000` for commands whose writer sets no `expiresAt`. An
explicit `expiresAt` always wins**, so the voice integrations keep their 60 s unchanged.

Justification against three measured constraints:

1. **It must exceed the app's own watchdog.** `CloudRelayRepository` waits **45 s**, sized from a
   **measured** worst case of **30-32 s** under queue pressure
   ([cloud_relay_repository.dart:44-52](lib/features/wled/cloud_relay_repository.dart#L44-L52)). A
   TTL below that would expire commands the app is still legitimately waiting on, converting a
   slow-but-successful command into a spurious failure.
2. **120 s is ~2.7× that watchdog and ~4× the measured worst case.** This yields the key property:
   **expiring an app-written command is invisible to the user**, because the app stopped waiting 75 s
   earlier and already ran its own reconcile-and-report path (the #52 late-result-wins logic in
   `_reconcileAfterWatchdog`). The user sees the app's existing timeout messaging, unchanged.
3. **It is far below any plausible bridge outage**, so a bridge reconnecting after a real outage
   finds nothing pending.

**On the "user on bad LTE" concern in the brief — it does not apply, and this is worth knowing.**
`createdAt` is a `serverTimestamp`: it is stamped by Firestore when the write **commits**, not when
the phone starts the request. Poor uplink delays the write itself; the TTL clock starts after. **The
only actor whose slowness this TTL measures is the bridge.** A user on 2G whose write takes 8 s still
gets a full 120 s of bridge budget.

**What a user sees when their own command expires:** nothing new. At 45 s the app has already given
up and reported. At 120 s the document flips to `expired`, after everyone stopped watching. The one
observable change is in the Firestore console and in future telemetry, which is the point.

### 3.4 Deterministic ids and the one-in-flight guard

Both are **helpers for S3, deliberately not wired to a dispatcher** (the brief says do not build S3).

`fireJobDocId(eventId, fireAtEpochSeconds)` → `fire_<eventId>_<epoch>`, to be used with
`.doc(id).create()`, which **fails with `already-exists`** rather than overwriting. Today every
writer uses `.add()`, so a retried Cloud Function invocation writes a **second document** and the
bridge fires **twice**; with an unordered poll, a two-document backlog has unspecified order. A
deterministic id makes the write itself the idempotency barrier and makes a retry unambiguously
distinguishable from a genuine second fire.

**Existing app writers are left on `.add()`** — out of scope per the brief, and it needs its own
analysis.

**One-in-flight-per-controller** is specified but **not implemented**, because it has no caller until
S3 exists and an uncalled guard is untestable. The contract it must satisfy: refuse to write a fire
job while a prior one for the same controller is still `pending` or `executing`. It bounds queue
pressure against the measured 30-32 s tail and works around the missing `orderBy` without firmware.
**Recorded here as an S3 obligation rather than shipped as dead code.**

### 3.5 Verification

`cd functions && npm run build && npx jest test/unit` → **4 suites, 66 tests, all passed** (22 of
them new, in [functions/test/unit/commandSafety.test.js](functions/test/unit/commandSafety.test.js)).

Covered: explicit `expiresAt` beats the default; fallback to `createdAt + TTL`; **undeterminable age
is never expired** (never guess); malformed fields do not throw; boundary behaviour at ±1 ms and
exactly-at-expiry; the 60 s voice TTL expires earlier than the 120 s default; the default outlives
the 45 s app watchdog (asserted as a property, so a future TTL edit that breaks it fails the suite);
the sweeper's age floor cannot exceed the smallest TTL in use; a six-hour-offline bridge has
everything expired; `expired ≠ failed`; `fireJobDocId` determinism, sanitization and second-flooring;
`controllerIpsFrom` dedup/sort/stability.

**Dart suite:** `flutter test` → **1857 tests, 1 failure**, and the failure is
`test/features/ai/cloud_ai_processor_normalize_test.dart` — the expected pre-existing one. The count
matches the brief's expectation exactly, so no stash comparison was needed. **No Dart files were
changed by this work**, so this is a confirmation rather than a meaningful signal.

---

## 4. WHAT IS *NOT* CLOSED

### 4.1 Needs firmware + OTA — which does not exist

The bridge has no OTA path; [main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372) registers six
routes and none is an update endpoint. All three of these are blocked behind an OTA campaign that has
not been built ([OFF_LAN_CAPABILITY.md §5.3](audit/OFF_LAN_CAPABILITY.md)):

1. **Bridge-side expiry check** — read `expiresAt` in `executeCommand`, mark `expired`, skip. ~1 h of
   firmware. Closes the residual window below completely.
2. **Ordered draining** — `orderBy: createdAt` on the poll query. Until then, backlog order is
   unspecified.
3. **Drain-and-discard on reconnect** — on a WiFi reconnect after >N minutes offline, expire all
   pending without executing.

### 4.2 The residual window, stated plainly

**The sweeper runs at best every 60 s. The bridge polls every 1 s.** A bridge that reconnects inside
that gap **still fires a late command**, bounded at roughly 60 s + the command's grace.

For a lighting command that is the right command slightly late — acceptable. It is **not** acceptable
for anything with side effects, which yields a standing constraint:

> **Route only fire jobs through the scheduled path. Never a state-mutating operation — no `psave`,
> no `applyConfig`, no pairing — where "executed 60 s late" is not equivalent to "executed."**

Note the S3 mitigation already designed in
[SCHEDULING_ARCHITECTURE_V2.md §4](audit/SCHEDULING_ARCHITECTURE_V2.md): the dispatcher writes the
command **at fire time, not at plan time**, so the document exists for ~90 s rather than for weeks.
Layer 1 does most of the work; this sweeper is Layer 2.

### 4.3 Other things this does not fix

- **Unauthenticated LAN endpoints on the bridge** — `/api/bridge/pair` and `/api/reset`
  ([main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372)): anyone on the Wi-Fi can re-pair or
  factory-reset a bridge.
- **All bridges share one Firebase Auth identity** — compile-time constants
  ([config.h.example:30-31](esp32-bridge/src/config.h.example#L30-L31)).
- Both are pre-existing, inherited, and firmware-blocked. Recorded as accepted risk, not silently
  carried.
- **Commands with no `createdAt`** cannot be dated and are never expired (the sweeper's query filters
  on `createdAt`, so they never match). They fall to the 7-day retention sweep. Anomalous shape;
  documented in `effectiveExpiryMs`.

---

## 5. DEPLOYMENT — ORDER IS LOAD-BEARING. NOTHING HAS BEEN DEPLOYED.

**Deploying the rule first denies every non-empty `controllerIp` write fleet-wide and takes out
remote control entirely.** Test case 15 in §2.3 is the empirical proof: with a user doc that has no
`controller_ips`, a legitimate targeted write is DENIED.

Required sequence, each step verified before the next:

| # | Step | Command | Verify before proceeding |
|---|---|---|---|
| 1 | Deploy the index **first** — the sweeper throws without it | `firebase deploy --only firestore:indexes` | Console shows the `commands` COLLECTION_GROUP index **Enabled**, not Building |
| 2 | Deploy the functions (additive; breaks nothing) | `cd functions && npm run build && firebase deploy --only functions:sweepExpiredCommands,functions:syncControllerIps,functions:backfillControllerIps` | Sweeper logs "nothing pending past the age floor" on its first ticks |
| 3 | **Dry-run** the backfill | callable `backfillControllerIps` with `{"dryRun": true}` | Review `updated` / `withoutControllers` / `errors` |
| 4 | Run the backfill for real | `{"dryRun": false}` | `errors` empty |
| 5 | **VERIFY POPULATION** across every user doc | read `users/*.controller_ips` | Every user with controllers has a non-empty array containing their real IPs |
| 6 | **ONLY THEN** deploy the rule | `firebase deploy --only firestore:rules` | — |
| 7 | Post-deploy smoke, immediately | — | See below |

**Step 7 — re-verify these three by hand, because rules are global and instant:**

1. **An ordinary customer session** — remote power/brightness through the relay (writer #1).
2. **Bridge pairing verification** — the `bridge_setup_screen` ping (writer #4, `controllerId: ''`).
3. **Bridge health check** — writer #2, which is the `.set()`-on-a-fixed-id update path.

Also worth re-checking, per the reviewer-demo concern: the demo path does not write commands, but if
a reviewer account has controllers with no `controller_ips` populated, its remote actions will deny —
step 5 covers it only if demo accounts are included in the backfill scan (they are; it scans all of
`/users`).

**Rollback:** `git checkout firestore.rules && firebase deploy --only firestore:rules`. The functions
and the denormalized field are additive and can stay — they break nothing on their own.

---

## 6. CHANGED FILES

| File | Change |
|---|---|
| [functions/src/commandSafety.ts](functions/src/commandSafety.ts) | **NEW** — expiry contract, status constants, deterministic fire-job id, allowlist extraction. Pure. |
| [functions/src/sweepExpiredCommands.ts](functions/src/sweepExpiredCommands.ts) | **NEW** — 1-minute `onSchedule` sweeper, `pending` → `expired`. |
| [functions/src/syncControllerIps.ts](functions/src/syncControllerIps.ts) | **NEW** — `controller_ips` maintenance trigger + admin backfill callable. |
| [functions/index.js](functions/index.js) | Exports the three new functions. |
| [firestore.rules](firestore.rules) | `commands` create/update gated on `targetsOwnController()`. |
| [firestore.indexes.json](firestore.indexes.json) | `commands(status, createdAt)` at COLLECTION_GROUP scope. |
| [functions/test/unit/commandSafety.test.js](functions/test/unit/commandSafety.test.js) | **NEW** — 22 unit tests. |
| [scripts/_test_command_ip_rule.js](scripts/_test_command_ip_rule.js) | **NEW** — 15-case Rules `:test` verification, mocked, ADC-authed. |
| [scripts/_test_rules_diff.js](scripts/_test_rules_diff.js) | **NEW** — 53-path differential HEAD-vs-working-tree regression. |

**No Dart files were changed.** No branch was created. Nothing was deployed.

**One incidental change, deliberately kept — `functions/lib/applySyncPattern.{js,d.ts,js.map}`.**
`npm run build` regenerated them. They are **tracked despite `functions/lib/` being gitignored**
([.gitignore:225](.gitignore#L225)), and the rebuild differs from the committed artifact by **+110
lines** — the committed build output is **stale** relative to `functions/src/applySyncPattern.ts`.

I first reverted them to keep this diff scoped. **That was wrong and I undid it:** reverting broke
**10 tests** in `fanoutMutualMembership.test.js` and `fanoutRateLimit.test.js`, which load the
compiled `lib/`. So the tracked artifact at HEAD is not merely stale — **`npx jest test/unit` fails
against it until you build.** (The suite's README does instruct `npm run build` first, so this is a
documented workflow rather than a broken repo, but the committed file genuinely disagrees with its
source.) The rebuilt files are the correct state and are left in place. Worth someone's attention
independently of this work: either untrack `functions/lib/` properly or commit a current build.

---

## Findings

| # | Finding | Severity |
|---|---|---|
| 1 | **Ten writers to `/users/{uid}/commands`, not four.** The prior count was built from `lib/` + `functions/index.js` and missed both `applySyncPattern.ts` writers, the standalone google-home function, and the operator script | Method — the enumeration gate worked |
| 2 | **Two shipping app writers send a `controllerIp` with no usable `controllerId`** (`bridge_health_service` sends none; `bridge_setup_screen` sends `''`), so the natural `controllerId`-keyed rule would have broken bridge health and bridge pairing fleet-wide on deploy | **The reason the design changed** |
| 3 | `bridge_health_service` writes a **fixed doc id via `.set()`** — its 2nd+ call is an UPDATE, so validating `create` alone leaves a permanent bypass | P1 for the rule design |
| 4 | **S1 is ~8 h, not ~3 h.** The extra is the safe-deployment machinery (denormalized field + trigger + backfill + staged deploy), not the rule | Estimate correction |
| 5 | "Any server-side writer should omit `controllerIp`" is **too broad** — the bridge has one paired IP, so multi-controller fan-out must name it. Safety comes from server-side provenance instead | Correction to V2 §8 |
| 6 | **The `expiresAt` field was designed and its enforcement never built** — written by 3 writers, read by 0 | Confirms V2 §4 |
| 7 | Default TTL **120 s**: above the app's 45 s watchdog so expiry is user-invisible; `serverTimestamp` means bad LTE does not consume the budget | Decision |
| 8 | **The emulator rules suite cannot run here** — firebase-tools 15.x needs JDK 21, box has 17. Replaced with a 53-path differential; **not** claimed as an emulator run | Honest gap |
| 9 | **The two existing rules-test scripts are currently broken** — their service account lacks `firebaserules.rulesets.test` (403). Pre-existing, unrelated | P3 |
| 10 | `functions/lib/applySyncPattern.*` is **tracked but gitignored, and the committed artifact is stale** by +110 lines vs its source — **10 unit tests fail against it until you `npm run build`** | P2, pre-existing |
| 11 | Residual exposure after this change is **~60 s** between sweeper ticks. Closing it needs firmware + an OTA that does not exist | Accepted, stated |

---

# DEPLOY LOG — 2026-08-01

Executed steps 1-5 of §5. **Step 6 (soak) is in progress. The rule is NOT deployed.**
Operator: `honeycutt.tylerg@gmail.com`, project `icrt6menwsv2d8all8oijs021b06s5`.

## STEP 1 — INDEX ✅

```
$ firebase deploy --only firestore:indexes
i  firestore: reading indexes from firestore.indexes.json...
i  cloud.firestore: checking firestore.rules for compilation errors...
+  cloud.firestore: rules file firestore.rules compiled successfully
i  firestore: deploying indexes...
+  firestore: deployed indexes in firestore.indexes.json successfully for (default) database
+  Deploy complete!
```

Note the rules line reads **"checking ... for compilation errors"**, not "deployed" — an index
deploy compiles `firestore.rules` as a side effect but does **not** publish it. The tightened rule
remained un-deployed throughout, and this incidentally confirms it compiles against the live service.

Index state, polled until READY (Firestore Admin REST):

```
NAME  : CICAgOi3kJAK
SCOPE : COLLECTION_GROUP
FIELDS: status:ASCENDING, createdAt:ASCENDING, __name__:ASCENDING
STATE : CREATING   →   READY
```

Held at this gate until `READY`; the sweeper throws `FAILED_PRECONDITION` without it.

## STEP 2 — FUNCTIONS ✅

```
$ firebase deploy --only functions:sweepExpiredCommands,functions:syncControllerIps,functions:backfillControllerIps
i  functions: creating Node.js 20 (2nd Gen) function sweepExpiredCommands(us-central1)...
i  functions: creating Node.js 20 (2nd Gen) function syncControllerIps(us-central1)...
i  functions: creating Node.js 20 (2nd Gen) function backfillControllerIps(us-central1)...
+  functions[backfillControllerIps(us-central1)] Successful create operation.
+  functions[sweepExpiredCommands(us-central1)] Successful create operation.
+  functions[syncControllerIps(us-central1)] Successful create operation.
+  Deploy complete!
```

Two pre-existing warnings, unrelated and not caused by this change: **Node.js 20 was deprecated
2026-04-30 and is decommissioned 2026-10-30** (deploys will start failing then), and `package.json`
pins an outdated `firebase-functions`.

### 2.1 The sweeper's first tick found a real production backlog

```
20:20:02  sweepExpiredCommands: expired 125 command(s) across 8 user(s) —
          PqptfawprOd2lTIsGr9tp7zeuVT2:50  NmDukd5rKwP9fGYOXm95l9JS8Cr1:47
          staff_installer_5502:12  5oHhaEaf6icmK2RlOWQMkESAXUG3:6
          r0iBwg8byeTqmROJgob8RK72DZm2:4  KOerj0uiKyTDQ83cWpRXkEYDnLk2:3
          EHRfYGyfQXQs5PQ5gBNWejjnnK13:2  VzgTsg31JEV78gwzVSVeFuvjMOv2:1
20:21:01  sweepExpiredCommands: nothing pending past the age floor
20:22:01  sweepExpiredCommands: nothing pending past the age floor
20:23:01  sweepExpiredCommands: nothing pending past the age floor
20:24:01  sweepExpiredCommands: nothing pending past the age floor
```

Zero `severity>=ERROR` entries. One-time drain, then clean steady state — exactly the expected shape.

**The stale-backlog hazard was not theoretical.** Age at expiry for the 50 commands belonging to
`Pqptfawpr…` (Darrin Nicholas):

```
min = 31.7 days     median = 62.8 days     max = 78.0 days
```

**125 commands, up to 78 days old, were sitting `pending` and were eligible for pickup and execution
by any bridge that reconnected.** They are now `expired` and invisible to the bridge poll. No user
was affected by the expiry itself — every one was far past the app's 45 s watchdog, so nothing was
waiting on them.

### 2.2 NEW FINDING — the 7-day retention sweep has never run

78-day-old commands should not exist: `COMMANDS_RETENTION_DAYS = 7`
([functions/index.js:1000](functions/index.js#L1000)). The deployed-function list explains why —
**`scheduledDataCleanup` is exported at [functions/index.js:1158](functions/index.js#L1158) but is
NOT deployed:**

```
$ gcloud functions list --format="value(name)" | grep -i scheduleddatacleanup
(no output)
```

Only the `onCall` variant `cleanupOldData` exists, and nothing calls it. `gcloud logging read` over
14 days returns **no invocations**. The code comment at
[functions/index.js:993-994](functions/index.js#L993-L994) says the routine was extracted from the
onCall handler *"so a scheduled trigger can run it too (Slice 0 — previously onCall-only, so it
NEVER fired)"* — the extraction happened, the deploy never did.

**This invalidates one statement in §4.3 of this document.** It said commands with no `createdAt`
"fall to the 7-day retention sweep." There is no working retention sweep. Un-dateable commands
persist indefinitely.

**Not fixed here** — deploying `scheduledDataCleanup` is outside the authorized scope of this staged
deploy and touches five other collections (habits, suggestions, oauth codes, analytics). It should be
its own change with its own blast-radius review. Recorded as a finding.

## STEP 3 — BACKFILL DRY RUN ✅

Invoked via [scripts/_run_backfill_controller_ips.js](scripts/_run_backfill_controller_ips.js).

**Auth note.** The callable requires an ID token with `admin: true`. **Zero of the 124 auth users
hold that claim** — so this callable and its siblings (`backfillUserLocations`,
`backfillUserDealerCodes`, same guard) are otherwise uninvokable. Rather than grant a persistent
admin claim to a production account, the script mints a **short-lived custom token** for a throwaway
uid: `createCustomToken(uid, {admin:true})` puts the claim in the *token only* and writes **no**
persistent `customClaims` on any user record. The token was used once and the throwaway auth user was
deleted at the end of each run. **Residue: none.**

```json
{ "dryRun": true, "scanned": 24, "updated": 15, "unchanged": 0,
  "withoutControllers": 9, "errors": [] }
```

`errors` empty → proceeded.

## STEP 4 — BACKFILL FOR REAL ✅

```json
{ "dryRun": false, "scanned": 24, "updated": 15, "unchanged": 0,
  "withoutControllers": 9, "errors": [] }
```

**Corrects a count in §5 of this document**, which said "the 20 user docs ... the 7 with
controllers". Those figures came from [LEASE_EXPOSURE.md](audit/LEASE_EXPOSURE.md) and describe users
with *calendar entries*, not controllers, and predate four new signups. Actual: **24 user docs, 15
with controllers.**

## STEP 5 — PER-USER VERIFICATION ✅ — the gate, not a formality

Read every user doc's `controller_ips` and compared it against that user's actual `controllers`
subcollection documents. Not the function's self-report — an independent read.

| | uid (trunc) | account | ctrls | `controller_ips` |
|---|---|---|---|---|
| OK | `5oHhaEaf6i` | Ellie Cochran | 1 | `["10.0.0.32"]` |
| OK | `Aj8lQ1hfwf` | Darian Brosa | 1 | `["192.168.1.73"]` |
| OK | `Ayf0rqwNOQ` | Tim Kelly | 1 | `["10.0.0.100"]` |
| OK | `EHRfYGyfQX` | Chris Paschall | 1 | `["192.168.1.201"]` |
| OK | `KOerj0uiKy` | **Demo** (`nex-genadmin@`) | 1 | `["192.168.1.156"]` |
| OK | `NmDukd5rKw` | Jim Dyer | 1 | `["10.0.0.100"]` |
| OK | `PqptfawprO` | Darrin Nicholas | 1 | `["10.0.0.250"]` |
| OK | `Q8VIQ9lrIA` | Brooke Rozenberg | 1 | `["192.168.86.250"]` |
| OK | `VzgTsg31JE` | Jeff Gruenewald | 1 | `["192.168.1.250"]` |
| OK | `YcSGiwesJu` | Steve Stegall | 1 | `["192.168.1.250"]` |
| OK | `cndlN3nmU9` | Chris Cipollone | 1 | `["192.168.1.250"]` |
| OK | `j8eXTfcsAB` | **Taps On Main** (commercial) | 1 | `["192.168.10.201"]` |
| OK | `r0iBwg8bye` | The Iron Reserve | 1 | `["10.1.10.240"]` |
| OK | `staff_inst…` | installer staff | 1 | `["192.168.1.156"]` |
| OK | `wrQRUUKyXy` | **Tyler Honeycutt** (bench) | 1 | `["192.168.1.150"]` |

```
users scanned         : 24
with controllers OK   : 15      ← stored array === actual controller IPs, exactly
with controllers BAD  : 0
without controllers   : 9       ← controller_ips ABSENT, which is correct
```

**Zero mismatches.** No user with controllers has an empty or wrong array, so no customer can be
locked out of remote control when the rule ships.

The 9 users without controllers carry no `controller_ips` field, which is correct and harmless: with
no controller there is no targeted command to write, and the rule allows untargeted writes
unconditionally.

### 5.1 Demo / reviewer accounts — explicitly cleared

| Account | uid | Controllers | `controller_ips` | Commands ever | Verdict |
|---|---|---|---|---|---|
| **Demo** `nex-genadmin@nex-genled.com` | `KOerj0uiKyTDQ83cWpRXkEYDnLk2` | 1 (`192.168.1.156`) | `["192.168.1.156"]` | 5+ | **Covered.** Allowlist correct |
| **Demo Home** `reviewer@nexgenled.com` | `reviewer-demo-account-001` | **0** | ABSENT | **NONE, ever** | **No exposure** |

The reviewer account cannot hit a denial. With zero controllers, `selectedControllerIdProvider`
returns null ([wled_providers.dart:239-255](lib/features/wled/wled_providers.dart#L239-L255)), so
`CloudRelayRepository` is never constructed ([:216](lib/features/wled/wled_providers.dart#L216)
requires a non-null `controllerId`) and no command document can be written. Consistent with its
having written **zero commands in its lifetime** — it is a demo-mode account.

**And it self-heals if that changes:** `syncControllerIps` fires on controller *create*, so if a
controller is added to the reviewer account before App Review, the allowlist is populated
automatically within seconds. **No submission risk.**

## STEP 6 — SOAK ⏳ IN PROGRESS — STOPPING HERE

Per the brief, the rule was **not** deployed in this session. `syncControllerIps` is now live and
maintaining the field. Leave it through ≥24 h of normal controller churn, then **re-run the Step 5
verification and diff the two readings**.

What the soak is actually testing: the backfill proved the field is *correct once*. Only live churn
proves the trigger *keeps* it correct — specifically that a controller **delete** removes its IP
(otherwise a decommissioned controller stays a legal target forever) and that a DHCP address change
is picked up (otherwise the customer is locked out of their own controller).

Re-run:

```bash
node scripts/_run_backfill_controller_ips.js --dry
```

**Expected after a clean soak: `updated: 0`, `unchanged: 15`.** Any non-zero `updated` means the
trigger missed a change — investigate before deploying the rule.

## STEP 7 — RULE ⛔ NOT RUN *(superseded — see "STEP 7 — RULE DEPLOYED ✅ 2026-08-05" below)*

Deliberately not executed. Requires a separate session after a clean soak. Sequence and the three
hand-verification paths are in §5.

## Deploy-log findings

| # | Finding | Severity |
|---|---|---|
| D1 | **125 stale `pending` commands, up to 78 days old, were live and pickup-eligible across 8 accounts.** The stale-fire hazard was real, not theoretical. Now expired | **Confirms the premise** |
| D2 | **`scheduledDataCleanup` has NEVER been deployed** — only the uncalled `onCall` variant exists, so the 7-day command retention has never run. This is why 78-day-old commands survived. **Invalidates a claim in §4.3.** Not fixed here | **P2, new** |
| D3 | **Zero of 124 auth users hold the `admin` claim** — `backfillControllerIps`, `backfillUserLocations` and `backfillUserDealerCodes` are all uninvokable without minting a token first | P3, pre-existing |
| D4 | Population verified **15/15 with zero mismatches**; 9 controller-less users correctly have no field | **Step 5 gate PASSED** |
| D5 | Reviewer account has 0 controllers and has never written a command → **cannot hit a denial; no submission risk**, and self-heals via the trigger if a controller is added | Cleared |
| D6 | Node.js 20 runtime is **decommissioned 2026-10-30**; deploys will fail after that date | P3, unrelated |
| D7 | Real counts are **24 users / 15 with controllers**, not the 20/7 in §5 (those were calendar-entry figures from a different audit) | Correction |

---

# STEP 7 — RULE DEPLOYED ✅ 2026-08-05

**Shipped: the `controller_ips` command-safety rule AND the `config/solar_scheduling` rule, together,
in one `firestore.rules` release.** Tyler's decision — a rules deploy publishes the whole file, so
solar could not ship without also cutting over command safety. Steps 1–5 of the soak plan were
already complete; the backfill dry run below re-confirmed the population immediately before deploy.

**Prior live ruleset:** `ec8d918f-c279-4925-b8b2-168e96638586`, released **2026-07-31T15:10:10Z**,
102,165 bytes. Keep this ID — it is the rollback target.

## 1 — The solar rule, and the config/ audit

`match /config/solar_scheduling` added mirroring `config/sync_fanout` exactly: `read` for any
authed user, bootstrap-only `create` with `enabled == false`, `update`/`delete` denied.

**Audit of the whole `config/` collection — solar was the only gap.** Four flag documents are read
by the client; three had blocks and solar did not:

| Client-read document | Rules block | Status |
|---|---|---|
| `config/calendar_leases` | :1564 | covered |
| `config/schedules_subcollection` | :1583 | covered |
| `config/sync_fanout` | :1601 | covered |
| `config/solar_scheduling` | **was absent** | **added this deploy** |
| `config/migrations/items/{id}` | :1615 | covered (admin-write) |

The three other client reads that *look* like `config` are different paths and each already has a
covering block: `dealers/{code}/config/{docId}` (:1809), `users/{uid}/roofline_config/{configId}`
(:615), `neighborhoods/{id}/game_day_autopilot/{configId}` (:627). **No sibling carries the same
gap.**

## 2 — Backfill dry run (pre-deploy)

```
node scripts/_run_backfill_controller_ips.js --dry
  scanned: 24   updated: 0   unchanged: 15   withoutControllers: 9   errors: []
```

`updated: 0 / unchanged: 15` — the exact expectation. The backfill is a **no-op**: every account
holding controllers already carries `controller_ips`, so the rule had nothing to strand.

## 3 — Verification gate (pre-deploy)

New script `scripts/_test_rules_deploy_gate.js` asserts absolute expectations against the candidate
rules via the Security Rules `:test` endpoint. **29/29 pass.**

- **Part A — 15-case `controllerIp` matrix (15/15).** Registered IPs allowed on create and update;
  unregistered denied on both; **commands with no `controllerIp`, and with `controllerIp: ''`,
  still allowed** (the pairing/health regression risk); bridge status update allowed; reads and
  deletes unaffected; stranger and unauth denied.
- **Part B — solar + sibling control (14/14).** Authed read allowed, unauth denied, create only
  with `enabled == false`, the flip denied, delete denied. The three sibling flags behave
  identically, and `config/not_a_real_flag` is still denied — proving the new block is not an
  accidental wildcard.

**53-path differential, run against the LIVE deployed ruleset** (not `HEAD` — the fetched
`ec8d918f` source), so it measures what this deploy actually changes:

```
Probed 53 · Unchanged 51 · Changed 2 · Out-of-scope 0
  ALLOW → DENY   commands: owner create, UNREGISTERED ip
  ALLOW → DENY   commands: owner update, UNREGISTERED ip
BLAST RADIUS CONTAINED
```

Both changes are the intended ones. **No other path moved**, so the stop condition never triggered.
A textual diff of live-vs-candidate agrees: the only non-comment changes are the
`declaredControllerIp()`/`targetsOwnController()` helpers with their two `/commands` guards, and the
`config/solar_scheduling` block.

## 4 — Deploy

```
firebase deploy --only firestore:rules
  + rules file firestore.rules compiled successfully
  + released rules firestore.rules to cloud.firestore
```

## 5 — Post-deploy verification — NON-ADMIN TOKEN

**Every assertion below was made with a plain authenticated `idToken` over the Firestore REST API,
so rules were enforced.** The admin SDK was used only to mint the custom token and to seed/clean the
throwaway user — never to assert. This is the correction to the 2026-08-05 failure recorded in
`audit/SOLAR_UI_GATE.md`, where an admin-SDK readback of `config/solar_scheduling` reported a
healthy flag that the app could not actually read.

**(0) The flag the deploy was for:**

```
config/solar_scheduling         READABLE  enabled=true     ← was 403 PERMISSION_DENIED
config/calendar_leases          READABLE  enabled=true
config/schedules_subcollection  READABLE  enabled=false
config/sync_fanout              READABLE  enabled=false
```

**(a) Customer remote control via the relay** — power and brightness with a registered
`controllerIp` both accepted; an unregistered IP refused with 403. Remote control is intact.

**(b) Bridge pairing verification ping** — `controllerId: ''` accepted, and a ping with no
`controllerIp` field at all accepted. The empty-string escape in `declaredControllerIp()` works
against live rules.

**(c) Bridge health check `.set()`** — create, update-over-existing, both accepted with a registered
IP; unregistered refused.

**12/12 pass.**

> **One correction worth recording.** The first (c) probe wrote to a `users/{uid}/bridge_health/`
> collection and got a 403 that briefly looked like a regression. **That collection does not
> exist.** `bridge_health_service.dart:34-46` writes to
> `users/{uid}/commands/bridge_health_check` — a *commands* document carrying a `controllerIp`, and
> therefore genuinely subject to the new rule. The 403 was the catch-all correctly denying an
> undeclared path; the differential had already shown zero out-of-scope movement. Re-probing the
> real path passed. **Verify against the path the code actually writes, not the one its name
> suggests.**

## 6 — Acceptance test ✅ CONFIRMED BY TYLER

Build 277 force-closed and reopened; **the schedule editor's Sunrise/Sunset segments are
selectable.** That is the acceptance test — a Firestore read is not, which is the whole lesson of
this deploy. All six gated surfaces and the sync path read the same provider, so they follow.

`firestore.rules` is now **committed** (it was held uncommitted only until this confirmation).

**Rollback:** redeploy the prior ruleset **`ec8d918f-c279-4925-b8b2-168e96638586`** from the
Firebase console — that reverts *both* rules in one action. To revert solar alone, drop the
`match /config/solar_scheduling` block and redeploy; note that this re-breaks solar fleetwide and
should only follow a decision to do so.

## Deploy-log findings (continued)

| # | Finding | Severity |
|---|---|---|
| D8 | `config/solar_scheduling` had no rules block; the 2026-08-05 flag flip therefore had **no effect for a full day**. The client's listen was default-denied and the provider's `catch` turned it into a settled `false`, making a permission denial indistinguishable from a flag that is off | **Fixed this deploy** |
| D9 | The `controller_ips` backfill is a **no-op** (`updated: 0`) — the cutover stranded nobody | Gate passed |
| D10 | Blast radius against the live ruleset is **exactly 2 paths**, both intended `/commands` denials | Gate passed |
| D11 | A `catch`-to-safe-default on a feature-flag stream hides permission errors. Worth distinguishing "denied" from "off" in the flag providers so the next missing block is loud | P3, new |
| D12 | `scheduledDataCleanup` **still not deployed** (D2 unchanged); 7-day command retention still never runs | P2, carried |
