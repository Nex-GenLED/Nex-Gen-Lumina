# Game Day server authority, steps A + B — deploy plan and Thursday rehearsal

**Date:** 2026-10-02 · **Branch:** `fix/gameday-server-ab` off release `a35e30e`; code commits `05946da` (A1/A3), `43981f5` (A2), `5d5fb6b` (B4), `a779bb0` (B1–B3), `ec0e50b` (B5 rules) · **Status:** BUILT, NOT DEPLOYED. Nothing in this document has been run. Every write step below is the owner's to run, after the owner's approval.

Spec: `docs/gameday_server_authority_plan_2026-10-01.md` (`e397068`, branch `docs/gameday-server-authority-plan-2026-10-01`).

Public-repo rule: no customer or bench identifiers appear here. `<BENCH_UID>` is the bench account's uid; take it from the owner's private notes.

---

## 1. What changes on deploy

| Kind | Name | Change |
|---|---|---|
| function | `sweepExpiredCommands` | Pass 2: `executing` older than 180 s → `failed` / `stuck_executing`. Both passes write with a `lastUpdateTime` precondition, so a concurrent bridge write wins. |
| function | `dispatchFireJobs` | Stuck claims no longer block, and are cleared before a fire (A1/A3). Start/end jobs retry transient failures within `retryUntil` (A2). Scorecard `start.*`/`end.*` and `gameday_server.last_fire` (B2/B3). |
| function | `planGameDayFires` | `retryUntil` on start/end jobs (A2). `on_time_override` honoured (B4). Pre-flight P1–P7 gates new starts, and the P6 probe can skip a minted start (B1). `gameday_server` writer (B2). Scorecard writer (B3). |
| function | `probeControllerHealth` | Age-capped in-flight guard (A1). New optional parameters, unused by the daily run, so the daily probe is byte-for-byte unchanged. |
| function | `collectControllerHealth` | `classifyProbe` blames the BRIDGE for a `stuck_executing` probe. This must ship with the sweeper, or every bridge reboot mid-probe becomes a "controller unreachable" alert. |
| function, **owner approval needed** | `backfillControllerHealth` | Same module and the same `classifyProbe` change. It is an admin-only callable, run by hand. If it is not redeployed, a manual backfill still blames stuck probes on the controller. It is outside the approved list of five. **Recommended: include it.** |
| index | `fire_jobs.fireAt` field override | Adds COLLECTION_GROUP ASC (the collection-scope defaults are kept). Used only by the §4 scorecard fallback query; no function needs it. |
| rules | `firestore.rules` `/users/{uid}` | B5: clients cannot add or change `gameday_server` / `gameday_gate_blocking`. **Separate approval.** |
| config | `config/gameday_planner` | New optional keys: `preflight_mode` (`"observe"` / absent = enforce) and `publish_server_status` (`false` / absent = publish). No write is required for the deploy itself; see step 0.4. |

Not affected: `teardownTeamFires`, `syncControllerIps` and `backfillControllerIps` import only exports this branch did not change. `git diff 8b3bcdf HEAD -- functions/src` touches exactly these modules: commandSafety, commandHygiene (new), controllerHealth, sweepExpiredCommands, dispatchFireJobs, fireJobs, planGameDayFires, gameDayHierarchy, gameDayPreflight (new), and probeControllerHealth. All of them load only into the functions listed above.

## 2. Earliest safe window

The rule: never deploy between a server start's mint (6 h before its fireAt) and its end fire plus 15 minutes, for any allowlisted account. Today that means the bench account.

| Slot (CDT) | Status |
|---|---|
| Thu 10-01 TNF, bench event live | **Avoid** until the end job is `completed` and the session has `endFiredAt`. Expected ~22:30 CDT; the hard cap is 23:45 CDT. |
| Fri 10-02 → Sat 10-03 | **Safe**, after the check in step 0.1. Earliest window. |
| Sun 10-04 NFL (bench start mints at ≥ 08:55 for a 14:55 fire, kickoff 15:25) | **Avoid** 08:55 → end fire + 15 min (~19:30). Re-enabling the bench config before 08:55 is a separate owner action. |
| Mon 10-05 → Wed 10-07 daytime | Safe. This is the plan's own target: Wed 10-07 evening, before the Thu 10-08 rehearsal. |
| Thu 10-08 TNF | **Avoid** from 6 h before the bench fireAt through its end fire + 15 min. This slot is the rehearsal (§6), not a deploy slot. |

## 3. Step 0 — read-only pre-checks (no writes)

0.1 **Nothing live.** No allowlisted session may be mid-game:
```
node scripts/_check_gameday.js end
```
Also confirm `gameday_plan_log/<today>.lastSummary` shows `errors: 0` and no session with `startPlannedAt` and no `endFiredAt` for the bench account.

0.2 **Tree identity.**
```
cd "C:/Flutter Projects/lumina-gd-ab"
git status --short          # expect only functions/lib/createCustomerAccount.js{,.map} (stale tracked build output; never commit)
git log --oneline -1        # the branch tip
git diff --stat 8b3bcdf HEAD -- functions/src   # the ten modules in §1, nothing else
```

0.3 **Gates on the exact tree.**
```
cd functions && npm test                       # 789/789
# emulator: JDK 25 on PATH, scratch firebase.json with firestore+auth (see test/emulator/README.md)
firebase --config <scratch>/firebase.json emulators:exec --only firestore,auth --project lumina-fn-test \
  "npx jest --config jest.emulator.config.js --runInBand --forceExit"
# expect 262/264 — the ONLY failures are commercialRules cross-dealer x2 (#119);
# the known setAccountProfile beforeEach(wipe) timeout may add one (261/264) on a cold emulator
```

0.4 **Bench pre-flight dry run (decides observe vs enforce).**
```
npm --prefix functions run build
node scripts/_gameday_preflight_dryrun.js <BENCH_UID>
```
- `"ok": true` → deploy with pre-flight enforcing (the default). The bench behaves exactly as tonight, plus one `getInfo` probe per event at mint.
- Any reason listed → either fix the input first (a stale heartbeat, or `base_ladder_asserts_segments` not `true` after a LAN healer pass), or set `config/gameday_planner.preflight_mode: "observe"` BEFORE deploying. Observe mode logs and publishes, and withholds nothing. Flip it back to enforce once the bench shows `ok`.

0.5 **Live index set.** The deploy must not prompt to delete anything:
```
firebase firestore:indexes --project icrt6menwsv2d8all8oijs021b06s5 > <scratch>/live_indexes.json
```
Diff it against `firestore.indexes.json`. The only expected difference is the new `fieldOverrides` entry. If the live set has indexes the file lacks, do NOT pass `--force`. A non-interactive deploy never deletes without it.

0.6 **Secrets.** Copy `functions/.env` from the MAIN checkout into this worktree (it is gitignored). Delete the copy after the deploy.

## 4. Deploy — ordered commands

All from `C:/Flutter Projects/lumina-gd-ab`, project passed explicitly (this worktree has no `.firebaserc`).

**Step 1 — index (additive).**
```
firebase deploy --only firestore:indexes --project icrt6menwsv2d8all8oijs021b06s5
```
Verify: `gcloud firestore indexes fields describe fireAt --collection-group=fire_jobs --project icrt6menwsv2d8all8oijs021b06s5` shows COLLECTION_GROUP ASC as READY. Nothing waits on it; continue regardless.
Rollback: not needed (additive, unused by functions). To remove it, delete the override from the file and redeploy indexes.

**Step 2a — step A functions (transport reliability).**
```
FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:sweepExpiredCommands,functions:dispatchFireJobs,functions:probeControllerHealth,functions:collectControllerHealth
#   + ",functions:backfillControllerHealth" ONLY if the owner approved it (§1)
```
The `predeploy` hook runs `npm --prefix functions run build`.
Verify, within 3 minutes:
- `updateTime` advanced on each function; read back the source zip (delivery is not content). `lib/sweepExpiredCommands.js` contains `markStuckExecuting`, `lib/dispatchFireJobs.js` contains `decideRetry` and `GameDayObservers`, and `lib/controllerHealth.js` contains `isStuckExecutingError`.
- Logs: `sweepExpiredCommands` prints `nothing to sweep` or `expired … stuck_executing N … raced N`. Zero `QUERY FAILED` lines. The first ticks may clear old stuck docs fleet-wide, which is expected; each user is named in the log line.
- `dispatchFireJobs` ticks with `errors: 0`. `fire_metrics/<today>` gains `stuckCleared` / `retried` keys.
Rollback: redeploy the same names from the release worktree at `a35e30e` (`C:/Flutter Projects/lumina-110-release`, with `.env` copied in). Jobs already carrying `retryUntil` are then treated by the old 90 s rule, and stuck docs already marked `failed` stay `failed` (terminal, harmless).

**Step 2b — step B (the planner).** Wait one full planner tick after 2a (5 minutes).
```
FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:planGameDayFires
```
Verify, on the next `*/5` tick:
- `gameday_plan_log/<today>.lastSummary` has the new keys `preflightSkips`, `preflightObserved`, `p6Probes`, `serverStatusWrites`, and `errors: 0`.
- The bench user doc has `gameday_server` with `served` matching the dry run, `preflight.reasons` matching the dry run, and `checked_at` within 5 minutes. Every other account with an enabled config gets `gameday_server.served:false` written ONCE (on-change semantics), then nothing.
- No new `fire_jobs` for any non-allowlisted account (unchanged behaviour).
- When the bench's next start mints: `fire_jobs/<event>_start` carries `retryUntil`; `gameday_scorecard/<local date>/entries/<BENCH_UID>_<event>` exists; one `getInfo` command with `source: gameday_preflight`; and after its result the session shows `preflight_p6.verdict: "ok"`.
Rollback: redeploy `planGameDayFires` from `a35e30e` (== live rev 00015 source). The `gameday_server` fields stay on user docs, and nothing reads them until app step C ships. To silence them without a deploy, set `config/gameday_planner.publish_server_status: false`.

**Step 3 — rules (only on separate approval).**
```
# 3.0 prove no undeployed drift rides along:
#     fetch the live ruleset (firebaserules releases/cloud.firestore → rulesetName → GET), diff it against
#     `git show a35e30e:firestore.rules`. Must be identical; if not, STOP.
firebase deploy --only firestore:rules --project icrt6menwsv2d8all8oijs021b06s5
```
Verify with a CLIENT credential, not admin (admin bypasses rules). Use a throwaway test uid (the `_test_rules_integrations_crews_live.js` pattern). `updateDoc(users/<self>, {gameday_server:{served:true}})` must be DENIED. `updateDoc(users/<self>, {display_name:"x"})` must be ALLOWED. Delete the throwaway account afterwards.
Rollback: the console's ruleset history (roll back to the previous release), or redeploy `git show a35e30e:firestore.rules`.

**After all steps:** remove the copied `functions/.env`. Add a "DEPLOYED" row to `docs/BUILD_LEDGER.md` with times, revisions and read-backs, replacing the "built, not deployed" status.

## 5. Rules diff (B5)

```diff
+      function serverOwnedGameDayFields() {
+        return ['gameday_server', 'gameday_gate_blocking'];
+      }
+      function createsServerOwnedField() {
+        return request.resource.data.keys().hasAny(serverOwnedGameDayFields());
+      }
+      function writesServerOwnedField() {
+        return request.resource.data.diff(resource.data).addedKeys()
+                 .hasAny(serverOwnedGameDayFields())
+            || request.resource.data.diff(resource.data).changedKeys()
+                 .hasAny(serverOwnedGameDayFields());
+      }
       allow create: if (…unchanged…)
-                    && (!createsPrivilegedRole() || hasAdminOrOwnerClaim());
+                    && (!createsPrivilegedRole() || hasAdminOrOwnerClaim())
+                    && !createsServerOwnedField();
       allow update: if (…unchanged…)
                     && (!elevatesRole() || hasAdminOrOwnerClaim())
-                    && (!reassignsDealerCode() || hasAdminOrOwnerClaim());
+                    && (!reassignsDealerCode() || hasAdminOrOwnerClaim())
+                    && !writesServerOwnedField();
```
Gate (emulator, release rules vs candidate, same 100-request matrix): **28 deltas, all intended ALLOW → DENY, 0 unexpected.** The deltas are seven write shapes for each of owner, anonymous, another uid and an admin-claim caller: add, change, dotted path, merge-with-forgery, and create carrying the field. The unauthenticated caller is denied under both rule sets. Removals, full-document `set()`, ordinary fields, other identities and subcollections are identical.

## 6. Bench rehearsal — Thu 10-08 (TNF), bench account only

Everything below writes ONLY under `users/<BENCH_UID>/…`, touches only the bench controller through the bench bridge, and is undone by the system itself. Do not open the app on the home Wi-Fi during the window (stop sign 1 of the 10-01 plan still applies).

**R0. Before the mint (~13:15 CDT for an 18:45 fire).** Run `node scripts/_gameday_preflight_dryrun.js <BENCH_UID>` and expect `ok`. Read `gameday_server`: `served:true`, `checked_at` fresh.

**R1. Mint + P6 (~6 h before the fire).** On the first tick after the horizon opens, expect:
- the start job with `retryUntil` = kickoff;
- the scorecard entry;
- one `gameday_preflight` `getInfo` command, completed within seconds;
- by the next tick, `preflight_p6.verdict: "ok"`.

**R2. Force a stuck `executing` doc (A1 sweeper).** At any quiet moment ≥ 30 min before the fire, add one synthetic command under the bench account:
```
users/<BENCH_UID>/commands/rehearsal_stuck_1 =
  { type: "getInfo", payload: "{}", controllerId: "<bench controller id>", controllerIp: "<bench controller ip>",
    status: "executing", source: "bench_rehearsal", createdAt: <now − 10 min> }
```
The bridge never polls `executing`, so the device never sees it. Expect within 60 s `status: "failed"`, `error: "stuck_executing"`, `stuckSweptAt` set, and no `completedAt`. The sweeper log names the bench uid with `stuck_executing 1`.

**R3. Stuck claim in front of the fire (A1 + A3).** About 30 seconds before the fire, add `rehearsal_stuck_2`, the same shape with `createdAt: <now − 185 s>`. The sweeper and the dispatcher both run every minute, and whichever reaches the doc first terminates it. The dispatcher's tick log shows `stuckCleared: 1` if it won; the sweeper's log names the bench uid if it did. **The property checked is that the start dispatches in its own minute.** Before A1/A3 this doc would have blocked the start until `too_late`.

**R4. Force a retry (A2) — bridge offline across the fire.** At fireAt − 1 min, unplug the bench bridge (it is on its own power) and leave it out for 3 minutes. Expect:
- the start command is not picked up; the sweeper marks it `expired` (bridge-offline wording) about 150 s after dispatch;
- on the next dispatcher tick the job is back to `scheduled`, `fireAt` +30 s, `lastOutcome: expired`, `retries: 1`;
- plug the bridge back in; attempt 2 dispatches with a NEW deterministic command id and completes;
- scorecard `start.attempts: 2`, `start.retries: 1`, `start.latency_ms` measured from the ORIGINAL fireAt;
- `gameday_server.last_fire` shows the start completed.

Abort and recover if the start has not landed by kickoff − 5 min: use the 10-01 plan's manual LAN curl (the server's own payload, `/json/state` only, never a preset save).

**R5. End (unchanged path, now scored).** After the final, expect the end job with `retryUntil` = its fireAt + 15 min, and the scorecard `end.reason`, `end.espn_final_seen_at` and `end.latency_from_final_ms`.

**R6. Cleanup.** Both synthetic commands are already terminal. Leave them for the 7-day retention sweep; no deletes.

**Do not rehearse P6 `unreachable` on Thursday.** It skips the start by design. The unit and emulator suites cover it; if a live check is wanted, use a second synthetic event on a day with no game.
