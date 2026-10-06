# Game Day ESPN slate fix — deploy plan and college rehearsal

**Date:** 2026-10-02 · **Branch:** `fix/gameday-espn-slate`, on `fix/gameday-server-ab` `309a5d9` (A+B, DEPLOYED 2026-10-02 as planner rev 00016 from `d2e0f6e`) · **Status:** BUILT, NOT DEPLOYED. Nothing here has been run. **Updated 2026-10-05:** the same deploy now also carries the two bridge write-gap fixes (B2 `served_sticky`, A `preflight_bridge_grace`); see §6b and §10. **Updated 2026-10-06:** and `end_ignores_gate`, the fix for the house left in team colours on 10-05 (§0, §6c, §11). Every write below is the owner's, after the owner's approval.

**Code commits:**

| Commit | What |
|---|---|
| `84133d6` | status-aware cap |
| `fbbbee3` | espnClient |
| `6fe971d` | pre-flight #146/#150 |
| `2298cd9` | planner wiring |
| `f821b8e` | flags take `true` or a uid list (#157) |
| `18a8209` | the clock guarantee (#159) |
| `2c15e27` | no start for a postponed game (#158) |
| `08b2596` | `payload_full_state` |
| `3dfce14` | the bridge write gap: `served_sticky` (B2) and `preflight_bridge_grace` (A) |
| `dde45b3` | `end_ignores_gate`: the end of a fired start is written past a blocking readiness gate |

Public-repo rule: no customer or bench identifiers appear here. `<BENCH_UID>` is the bench account's uid; take it from the owner's private notes.

**The plan in one line:** deploy `planGameDayFires` only, **Fri 10-09 08:00–11:00 CDT**, after the A+B code has run the Sat 10-03, Sun 10-04 and Thu 10-08 bench games. Rehearse the same evening on **Louisville vs Florida State, 18:00 CDT**, bench account only, with uid-list flags. The friendlies are allowlisted **Sat 10-10 only after the rehearsal is clean**. The two bridge write-gap flags go on for the bench the same morning (§6b), and fleet-wide **before** any friendly is allowlisted. So does `end_ignores_gate` (§6c): **all three** on and verified before the allowlist widens.

## 0. The defect and the fix

The server read ESPN's featured college list, so an FBS team that was not featured never got a start. It also found a game only through a scoreboard, so a game dropped from the board after kickoff never ended. The fix:
- **College slate:** college football reads the dated FBS slate (ET yesterday, today and tomorrow, `groups=80`, `limit=300`).
- **Tracking:** a started session is followed by its ESPN id.
- **Status-aware cap:** the hard cap holds while ESPN says the game is live, up to a per-sport ceiling. With the same flag, the clock fires the ceiling whatever ESPN does (#159), and no start is minted for a game ESPN already reports postponed or cancelled (#158).
- **URL cache:** each ESPN URL is fetched once per tick.
- **Ride-alongs:** P4b (#146); the first served app build is 114 (#150); `payload_full_state` (the multichannel audit §4.1).
- **Bridge write gap (added 2026-10-05):** firmware-1.2 bridges stop landing Firestore writes for about ten minutes at a time, a few times a day, with no reboot. The bench bridge does it about every 7.5 h, and the same gap was seen on three other fleet bridges at other houses. Each gap fails pre-flight P2 (heartbeat under 5 minutes old) on one or two planner ticks. Each of those ticks published `served:false`, which app builds 114 and 115 read as "not served": an app open on the home network during those minutes can arm the phone lease (a preset save plus a timer row). **B2, `served_sticky`:** `served` stays true until P2 has failed for 30 minutes without a break. **A, `preflight_bridge_grace`:** P2's window is 15 minutes instead of 5. See §6b for the turn-on and §10 for what the app sees.
- **The house left in team colours (added 2026-10-06):** on 10-05 a start minted in the morning fired on the server path at 18:46 CDT. The owner had added a fourth controller bus at 15:50 CDT, so the readiness gate flipped to `gated_ladder_bad`. ESPN's final was seen at 22:30 CDT, and every tick after it logged `plan_end confirmed_final scopedOut:true` and wrote nothing: `writeJobs = allowlisted && gate.armed` guarded the end as well as the start. Pre-flight never gated ends; the gate did. **`end_ignores_gate`:** the end of a start this system FIRED is written while the account is allowlisted, whatever the gate says, by every end path (confirmed final, hard cap, status-aware cap and ceiling). Starts keep the gate. See §6c and §11.

Every behaviour sits behind a flag, and every flag is off until the owner writes it.

## 1. What changes on deploy

| Kind | Name | Change |
|---|---|---|
| function | `planGameDayFires` | The only function deployed. With every flag absent, it plans exactly as rev 00016 does (golden-tested, §6). The visible differences: one ESPN request per URL per tick instead of one per sport/team pair, a new `espnFetches` key in the tick summary, and P7's informational `lease_hygiene_unknown` naming builds below 114. |
| config | `config/gameday_planner` | New optional keys, all off when absent: `espn_college_slate`, `track_started_by_id`, `status_aware_cap`, `preflight_ladder_lit`, `payload_full_state`, and (2026-10-05) `served_sticky`, `preflight_bridge_grace`, and (2026-10-06) `end_ignores_gate`. **No write is part of the deploy.** |
| data | `users/{uid}.gameday_server.stale_since` | New optional field. Written only for an account with `served_sticky` on, while P2 is failing; removed on the first tick P2 passes. The app's parser reads named keys only and ignores it. On a tick that holds someone, the plan log gains a `served_held` row and the tick summary a `servedHeld` count; when a hold runs out, a `served_hold_expired` row. None of these exist with the flag absent. |
| data | `end_ignores_gate` traces | No new document or field. On a tick where it acted: `gateBypassed: true` on the `plan_end` row, a `handoff_refused:gate_blocking` row when a hand-off was refused, `endsGateBypassed` in the tick summary, and `gate_bypassed: true` under the scorecard entry's `end`. None of these exist with the flag absent. |
| index | none | Query #8 (`game_day_sessions` where `gameStartMs >=`) is a COLLECTION-scope single-field range, which uses the automatic index. It runs only for accounts with `track_started_by_id` or `status_aware_cap` on. |
| rules | none | — |

Not affected: `dispatchFireJobs` imports only unchanged exports from `gameDayPreflight` (the scorecard ids and `publishServerStatusFrom`), so it is not redeployed. The functions diff against `309a5d9` touches exactly `espnClient.ts`, `gameDayPlanning.ts`, `gameDayPreflight.ts` and `planGameDayFires.ts`, plus their tests. Outside `functions/`: `scripts/_gameday_preflight_dryrun.js` (follows P4b per uid) and these docs. The 2026-10-05 write-gap change stays inside `gameDayPreflight.ts` and `planGameDayFires.ts`, with two new test files (`gameDayBridgeStale.test.js`, `plannerBridgeStale.test.js`); the dry-run script now also follows `preflight_bridge_grace` per uid and reports what a tick would publish as `served`. The 2026-10-06 end-gate change is inside `planGameDayFires.ts` alone, with one new test file (`plannerEndGate.test.js`).

## 2. The flags — shapes and exact writes

**Shapes (#157).** Each flag is exactly `true` (fleet-wide) or an array of uid strings (only those accounts). `preflight_ladder_lit` also takes `"strict"`, fleet-wide. Anything else is OFF: absent, `false`, `"true"`, a number, `[]` (nobody), or a list holding a non-string. A present-but-malformed field logs a warning and stays off. A flip takes effect at the next tick (≤ 5 min), with no deploy. Jobs are still written only for allowlisted accounts.

| Flag | What it does when on for an account |
|---|---|
| `espn_college_slate` | `ncaaFB` configs read the dated FBS slate. The pick order: in progress, then the soonest scheduled game, then a final inside its end window, then a postponed game inside the window. An id that is never on a full slate, and that ESPN says is not FBS (or does not know), is logged `team_not_on_slate`. |
| `track_started_by_id` | A session with a start and no end follows its own game through `scoreboard/{id}` until its end fires. A 404 counts as "silent"; any other error falls back to the scoreboard. |
| `status_aware_cap` | Past the shipped bound (kickoff + estimate + 60 min), the cap is HELD while ESPN reports the game live or delayed, up to the ceiling: football 6 h, MLB 7 h, basketball 4.5 h, NHL 5 h, soccer 5 h. **#159:** a started game ESPN cannot be read for (HTTP error, 429, timeout, network, unparseable, partial slate) is held, and the clock fires the ceiling; a game ESPN answers about but no longer lists (empty, missing, single-game 404) is capped at the bound. **#158:** no start for a game ESPN reports postponed, cancelled or suspended. |
| `preflight_ladder_lit` | P4b (#146). `base_ladder_restore_lit: false` skips new starts (`preflight_ladder_dark`, plus a row naming `base_ladder_dark_channels`). With `true` or a list, an absent field is informational; with `"strict"`, it also skips. |
| `payload_full_state` | Start and hand-off payloads state every participating segment field the app sends: `fx sx ix pal grp:1 spc:0 bri:255 frz:false`, three colour slots. An excluded segment becomes `{id, on:false, frz:false}`. Never geometry. 3 buses: 263 B → 431 B. **Not to be turned on before this weekend's bench games finish**, and not during the rehearsal (one variable at a time). |
| `served_sticky` | **B2.** `gameday_server.served` stays true through a P2 failure (`preflight_bridge_stale`) shorter than 30 minutes, so a bridge write gap no longer publishes `served:false`. The hold needs all of: the stale bridge is the ONLY failing reason; the stored `served` is already true; under 30 minutes since `gameday_server.stale_since` (the tick P2 first failed in this unbroken run). `teams` and `next_fire` are published as on a good tick, `checked_at` is written every tick, and `preflight` carries the real `ok:false` and reason. **No start is minted on a held tick**, and ends are never gated. |
| `preflight_bridge_grace` | **A.** P2's heartbeat window is 15 minutes instead of 5 for the account: 14:59 old passes, 15:01 is `preflight_bridge_stale`. A ten-minute gap therefore fails nothing, and a start due inside it is minted. No heartbeat document at all is still stale. |
| `end_ignores_gate` | The END of a FIRED start is written while the account is allowlisted, even when the readiness gate blocks the account (`gated_ladder_bad`, `gated_no_facts`, `gated_no_floor`). Every end path: confirmed final, hard cap, status-aware cap and its ceiling. **Fired** is GUARD 0b's test, unchanged: the start job (the team's own `_start`, or the relinquisher's `_end` for a team lit by hand-off) is `dispatched` or `completed`. A start that is `scheduled`, `cancelled`, `expired`, `skipped`, `failed` or missing never commanded the controller, so no end is written, as before. **Starts keep the gate.** A hand-off (the survivor's start) is refused under a blocking gate and the end restores base. An account removed from `uid_allowlist`, or `write_jobs:false`, still gets no end: the planner logs `plan_end … scopedOut:true` and commands nothing. |

**The write** — from the repo root with ADC credentials. It changes only the named fields:
```
node -e "const a=require('./functions/node_modules/firebase-admin');a.initializeApp({credential:a.credential.applicationDefault(),projectId:'icrt6menwsv2d8all8oijs021b06s5'});a.firestore().doc('config/gameday_planner').update({FIELDS}).then(()=>{console.log('ok');process.exit(0)})"
```
Replace `{FIELDS}` with one of:

| Purpose | `{FIELDS}` |
|---|---|
| **Bridge write gap, bench only** — B2 | `{served_sticky:['<BENCH_UID>']}` |
| **Bridge write gap, bench only** — A | `{preflight_bridge_grace:['<BENCH_UID>']}` |
| Bridge write gap, bench only — both in one write | `{served_sticky:['<BENCH_UID>'], preflight_bridge_grace:['<BENCH_UID>']}` |
| **Bridge write gap, everyone** | `{served_sticky:true, preflight_bridge_grace:true}` — before any account is added to `uid_allowlist` (§6b) |
| Bridge write gap, **remove** (= rev 00016 behaviour) | `{served_sticky:a.firestore.FieldValue.delete(), preflight_bridge_grace:a.firestore.FieldValue.delete()}` |
| **End gate, bench only** | `{end_ignores_gate:['<BENCH_UID>']}` |
| **End gate, everyone** | `{end_ignores_gate:true}` — before any account is added to `uid_allowlist` (§6c) |
| **All three, everyone** (the S3 write) | `{served_sticky:true, preflight_bridge_grace:true, end_ignores_gate:true}` |
| End gate, **remove** | `{end_ignores_gate:a.firestore.FieldValue.delete()}` — never while an allowlisted account has a lit session and a blocking gate (§7) |
| **Bench-only rehearsal (Fri 10-09)** | `{espn_college_slate:['<BENCH_UID>'], track_started_by_id:['<BENCH_UID>']}` |
| Fleet-wide, after the rehearsal | `{track_started_by_id:true}`, then `{status_aware_cap:true}`, then `{espn_college_slate:true}` |
| Full-state payload, bench first | `{payload_full_state:['<BENCH_UID>']}` (not before this weekend's bench games finish) |
| P4b | `{preflight_ladder_lit:true}` once +114 is in the fleet; `"strict"` once the controller docs show the field |
| **Remove** (= off) | `{espn_college_slate:a.firestore.FieldValue.delete(), track_started_by_id:a.firestore.FieldValue.delete()}`, or any other field the same way |

`update()` keeps every other field (`write_jobs`, `uid_allowlist`, `preflight_mode`, …) and fails on a missing document, which this is not. Console equivalent: Firestore → `config` → `gameday_planner` → Add field. For a uid list, the type is **array** with one string element.

**Read back after every write:** `….doc('config/gameday_planner').get().then(d=>{console.log(JSON.stringify(d.data()));process.exit(0)})`. Confirm each list holds exactly the intended uid string.

## 3. The deploy window

The rule, unchanged from A+B: no deploy between an allowlisted start's mint (fireAt − 6 h) and its end fire + 15 min.

| Slot (CDT) | Status |
|---|---|
| Sat 10-03 evening, bench college | A+B code runs it. **No deploy.** |
| Sun 10-04 afternoon, bench NFL | A+B code runs it. **No deploy.** |
| Thu 10-08 TNF (DAL–TB, 19:15 kickoff) | A+B code runs it, and it is the A+B rehearsal. **No deploy** from its mint (~12:45) to its end + 15 min (hard cap 23:45). |
| **Fri 10-09, 08:00–11:00** | **THE DEPLOY.** Only after step 4.1 shows Thursday's session closed and the three A+B games behaved. It must finish, and §6 pass, before 11:00. The rehearsal's start mints from 11:30 and its flags go in at 11:00–11:25. The bridge write-gap flags follow §6b the same morning. |
| Sat 10-10 | Friendlies allowlisted, **only if the rehearsal was clean** (§8.7). |

## 4. Step 0 — read-only pre-checks (Fri 10-09, from 08:00)

4.0 **Create the worktree — the first commands of the window.** The worktrees this branch was built in were removed after each push, so the window makes its own. It is named `lumina-gd-espn`, as in every command below. From Git Bash, in the main checkout:
```
cd "C:/Flutter Projects/Lumina V 1.6"

# 1. fetch
git fetch origin --prune

# 2. the two heads
git ls-remote --heads origin fix/gameday-espn-slate fix/gameday-server-ab
#    fix/gameday-server-ab    must be 309a5d9. It is rev 00016's source line and the rollback target.
#                             If it moved: stop, rebase this branch onto it, and re-run 4.3.
#    fix/gameday-espn-slate   must be ff917d8 (the code as gated on 2026-10-05) or a DOCS-ONLY
#                             descendant of it, the close-out head the owner was given. Prove that:
git diff --name-only ff917d8 origin/fix/gameday-espn-slate     # only docs/ paths (nothing if the head IS ff917d8)

# 3. the worktree, with node_modules as a junction to the main checkout's
git worktree add "C:/Flutter Projects/lumina-gd-espn" fix/gameday-espn-slate
cmd //c mklink //J "C:\\Flutter Projects\\lumina-gd-espn\\functions\\node_modules" "C:\\Flutter Projects\\Lumina V 1.6\\functions\\node_modules"
git -C "C:/Flutter Projects/lumina-gd-espn" rev-parse --short HEAD   # the ls-remote head; if behind: merge --ff-only origin/fix/gameday-espn-slate
```
- These are the commands the branch was built and gated with on 2026-10-05, with only the folder name changed.
- The junction is sound because the branch adds no dependency: `git diff --stat 309a5d9 HEAD -- functions/package.json functions/package-lock.json` prints nothing. From PowerShell the junction command is `cmd /c mklink /J "<link>" "<target>"`.
- **Teardown, after the ledger commit (§9).** Restore the two stale build outputs, remove the JUNCTION (never its target, never `rm -rf` on the worktree), then remove the worktree, and check the main checkout still has its modules:
```
git -C "C:/Flutter Projects/lumina-gd-espn" checkout -- functions/lib/createCustomerAccount.js functions/lib/createCustomerAccount.js.map
cmd //c rmdir "C:\\Flutter Projects\\lumina-gd-espn\\functions\\node_modules"
git worktree remove "C:/Flutter Projects/lumina-gd-espn"
ls "C:/Flutter Projects/Lumina V 1.6/functions/node_modules" | wc -l     # unchanged from before the window
```

4.1 **Nothing live.** No allowlisted session with `startPlannedAt` and no `endFiredAt` (`node scripts/_check_gameday.js end`). Thursday's end job is `completed`. `gameday_plan_log/<today>.lastSummary` shows `errors: 0`.

4.2 **A+B is the live planner, and this branch sits on its head.** Rev 00016 is live from `d2e0f6e`. Step 4.0's `ls-remote` confirmed `fix/gameday-server-ab` is still `309a5d9`; if it moved, rebase and re-run 4.3.

4.3 **Tree and gates.**
```
cd "C:/Flutter Projects/lumina-gd-espn"
git status --short                       # only functions/lib/createCustomerAccount.js{,.map} (stale tracked output; never commit)
git diff --stat 309a5d9 HEAD -- functions/src   # the four modules, nothing else
cd functions && npm run build && npm test          # 43 suites, 1018 tests
firebase --config <scratch>/firebase.json emulators:exec --only firestore,auth --project lumina-fn-test \
  "npx jest --config jest.emulator.config.js --runInBand --forceExit --testTimeout=120000"
# 262 of 264: only the two #119 commercialRules cross-dealer cases may fail
```

4.4 **No new key is in the config.** Read `config/gameday_planner` (§2) and confirm all eight keys are absent: the five ESPN-slate keys, `served_sticky`, `preflight_bridge_grace` and `end_ignores_gate`.

4.5 **Secrets.** Copy `functions/.env` from the MAIN checkout into this worktree; delete it after the deploy.

## 5. Deploy

```
cd "C:/Flutter Projects/lumina-gd-espn"
FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:planGameDayFires
```

## 6. Verification reads (flags still absent) — within 10 minutes, two ticks

- **Delivery.** Download the deployed source zip, not just the `updateTime`. `lib/planGameDayFires.js` contains `espnFlagsFrom` and `openSessionsByTeam`. `lib/espnClient.js` contains `fetchCollegeSlateGame` and `defaultScoreboardAnswered`. `lib/gameDayPlanning.js` contains `flagScopeFrom`, `decideEndWithoutEspn` and `gameDayPaletteFor`. `lib/gameDayPreflight.js` has `MIN_SERVED_APP_BUILD = 114`, and (2026-10-05) contains `decideServedSticky` and `BRIDGE_STALE_GRACE_MS`; `lib/planGameDayFires.js` contains `servedStickyScopeFrom`, `served_hold_expired` and (2026-10-06) `endsGateBypassed` and `handoff_refused:gate_blocking`. No `.env` in the zip.
- **`gameday_plan_log/<UTC date>.lastSummary`.** `espnFetches` is present and equals the number of distinct sports with an enabled config fleet-wide (a handful, against ~10 requests before). `espnErrors: 0`, `errors: 0`. `skipped`/`endSkipped` match the last pre-deploy tick, moving only as games cross the horizon.
- **None of the new rows:** `team_not_on_slate`, `cap_held_live`, `cap_held_unavailable`, `espn_unavailable`, `game_not_played`, `preflight_ladder_dark`, `served_held`, `served_hold_expired` or `handoff_refused:gate_blocking`, and no row carrying `gateBypassed`.
- **Bench.** `gameday_server.served`/`preflight` are unchanged, and no new job. No `stale_since` under `gameday_server`, and no `servedHeld` or `endsGateBypassed` key in any tick summary.
- **A bench `preflight_skip` naming `preflight_bridge_stale` during these reads is the known write gap, not a deploy fault.** It recurs about every 7 h 28 min (§6b says how to place the next one). With the flags absent it flips `served` false for one or two ticks, exactly as rev 00016 does.
- **Logs.** The planner's stats line carries `espnFetches`. No WARNING+, in particular no "malformed" flag warning.

Why "unchanged" is a strong claim: `functions/test/unit/fixtures/plannerFlagsOffGolden.json` is the complete Firestore output of a four-account, three-sport, five-tick scenario, captured from `d2e0f6e` before any change. The flags-off planner reproduces every document, stat and log row, and the bench-regression snapshot is byte-identical with every flag off, with every ESPN flag on, and with `payload_full_state` explicitly off. The 2026-10-05 write-gap code passes the same golden and the same snapshot with both of its flags absent, and a healthy three-tick run is document-for-document identical with both flags ON (`plannerBridgeStale.test.js`).

**If §6 is not clean by 11:00:** do not write the flags. Roll back (§7) and move the rehearsal to the Friday fallback week (§8.1).

## 6b. The bridge write-gap flags — turn-on order and verification reads

Only after §6 is clean with every flag absent. Each step is one `update()` (§2) and a read-back. No deploy is involved.

**Order.** B2 first and alone, so that one real gap is seen HELD. Then A. Then both fleet-wide. **Friendlies are allowlisted only after all three flags (`served_sticky`, `preflight_bridge_grace`, `end_ignores_gate`) are on (`true`) and verified** (§6c for the third). An account added to `uid_allowlist` while the flags are bench-only gets rev 00016's behaviour on its first gap.

| Step | `{FIELDS}` (§2) | When |
|---|---|---|
| S1 | `{served_sticky:['<BENCH_UID>']}` | Fri 10-09, after §6, before 11:00 |
| S2 | `{preflight_bridge_grace:['<BENCH_UID>']}` | after S1's gap read below; not between the rehearsal's 17:30 fire and prompt C |
| S3 | `{served_sticky:true, preflight_bridge_grace:true, end_ignores_gate:true}` | after S2's gap read and §6c's E1 read; before `uid_allowlist` changes (Sat 10-10) |

**The predicted gap (bench).** The bench bridge's write gap recurs about every 7.46 h. The planner saw P2 fail on these ticks: 10-03 at 01:10, 08:40, 16:05 and 23:30Z; 10-04 at 07:00, 14:30 and 21:55Z; 10-05 at 05:25 and 12:50Z. That is nine ticks, each 7 h 25 min or 7 h 30 min after the one before. Carried forward from the 10-04 21:55Z tick (the 10-05 ticks give the same times to within two minutes):

| Predicted stale tick, ±1 h of drift | CDT | What is going on then |
|---|---|---|
| Fri 10-09, about 13:46Z | about 8:46 AM | **inside the deploy window** (§4 to §6) |
| Fri 10-09, about 21:13Z | about 4:13 PM | S1 in place; about 75 min before the rehearsal's 17:30 fire |
| Sat 10-10, about 04:41Z | Fri, about 11:41 PM | after prompt C: the S2 read |
| Sat 10-10, about 12:08Z | about 7:08 AM | before `uid_allowlist` changes: the margin for S3 |

The bridge is silent from about ten minutes before a stale tick until just after it. The cadence drifts, so re-anchor on the day: take the newest entry in `gameday_plan_log/<UTC date>.ticks` with `preflightSkips: 1` and add multiples of 7 h 28 min.

**A real gap, or a deploy problem?** Read these for the bench:

| Read | The known gap, flags absent (§6, before S1) | The known gap, HELD (S1 in place) | A deploy problem |
|---|---|---|---|
| `gameday_server.served` | false for one or two ticks | **true** | false and staying false |
| `gameday_server.preflight` | `ok:false`, reasons exactly `["preflight_bridge_stale"]` | `ok:false`, reasons exactly `["preflight_bridge_stale"]` | any other reason, or `ok:false` while the heartbeat is fresh |
| `gameday_server.stale_since` | absent | **set**, equal to the first stale tick | not applicable |
| `gameday_server.checked_at` | the first stale tick, then not rewritten | **fresh on every tick** | not advancing while `served` is true: the planner is not ticking |
| plan log | a `preflight_skip` row | `preflight_skip` **and `served_held`** rows; `servedHeld: 1` on that tick | `errors` above 0, a WARNING+ log line, or a summary key missing |
| heartbeat (`heartbeatAgeS` in the dry run) | over 300, and back under 60 within about 11 min | the same | fresh while P2 fails, or still stale after 15 min |
| other accounts | unaffected | unaffected | several change on the same tick |

So a real held gap reads: `served:true` with `preflight.ok:false`, `stale_since` set, `checked_at` fresh, and a `served_held` row in the plan log. All of that, clearing without help inside about eleven minutes, is the fix working. It is not a reason to roll back.

**If the gap lands mid-deploy** (the 8:46 AM one):
- **During the upload (§5):** carry on. The deploy does not involve the bridge.
- **During the §6 reads (flags absent):** the bench may show a `preflight_skip` naming only `preflight_bridge_stale`, and `served:false` for one or two ticks. That is rev 00016's behaviour, and the new code's with no flag written. Confirm it with the dry run (`heartbeatAgeS` over 300, no other reason), wait for the heartbeat to return, and take §6's two ticks after that. The other §6 reads (the zip, `espnFetches`, `errors: 0`, no warning) hold good during the gap.
- **Do not write S1 during a gap.** The hold only keeps a `served:true` that is already stored. If a flags-absent tick has just published `served:false`, S1 cannot hold that gap: the bench stays `served:false` until the heartbeat returns. That is correct, and it looks exactly like S1's stop sign. Write S1 when the dry run reads `ok: true` with a fresh heartbeat. If S1 went in mid-gap anyway, judge it on the next gap, not this one.
- **Not the known gap:** the heartbeat is still stale after 15 minutes, or a second reason appears. Stop. Write no flag, and treat the rehearsal's precondition (§8.3, dry run `ok`) as failed until the bridge is back.
- **The afternoon gap and the rehearsal:** the start job exists from 11:30, and the dispatcher fires it at 17:30 whatever pre-flight says. If the bridge is silent at that minute the command waits, and the dispatcher retries until kickoff (18:00). Prompt A then shows a late start with retries: record it as the gap. If it has not landed by kickoff − 5 min, §8.6's manual recovery applies.

**S1 reads (`served_sticky`, bench).**
- Config read-back: `served_sticky` is an array holding exactly the bench uid string. No "malformed" warning in the planner log.
- Dry run: `node scripts/_gameday_preflight_dryrun.js <BENCH_UID>` shows `served.sticky: "on (config)"` and `wouldPublish: true`.
- Healthy ticks, at once: the bench `gameday_server` is as before. `served:true`, `checked_at` advancing every tick, no `stale_since`. `lastSummary` has no `servedHeld`.
- **At the next gap** (one or two ticks):
  - Plan log: the usual `preflight_skip` row (`reasons:["preflight_bridge_stale"]`) and a `served_held` row whose `staleSince` is that first tick. That tick's entry in `ticks` carries `servedHeld: 1` and `preflightSkips: 1`.
  - Bench `gameday_server` during the gap: `served:true`, `teams` unchanged, `checked_at` under 5 min old, `preflight.ok:false`, `preflight.reasons:["preflight_bridge_stale"]`, `stale_since` equal to the first stale tick.
  - After the gap: `preflight.ok:true` and **no `stale_since`**. `served` never read false.
  - No start job was created on a stale tick. If one fell due inside the gap, it appears on the first good tick with its normal `fireAt`.
- **Stop sign:** `served:false` on the bench during a gap shorter than 30 min with S1 in place. The flag was not read as on. Remove it, check the value's type, and do not go on to S2 or S3.

**S2 reads (`preflight_bridge_grace`, bench).**
- Config read-back. The dry run shows `bridgeStaleWindowS: "900 (grace on, config)"`.
- **At the next gap:** no `preflight_skip` row for the bench and `preflightSkips: 0` on those ticks. `gameday_server.preflight.ok` stays true. No `served_held` row (nothing failed, so nothing was held) and no `stale_since`.
- A gap that outlasts 15 min shows `preflight_skip` and `served_held` again. That is B2 working behind A. Note it in the ledger: it is a longer gap than any seen so far.

**S3 reads (both, fleet-wide).** The read-back shows both fields exactly `true`. The next tick's summary is unchanged, with `errors: 0` and no warning. Only then edit `uid_allowlist`.

**If a gap cannot be waited for** because the window is closing: the reads that need no gap (read-back, dry run, healthy ticks unchanged) are the minimum, and the gap behaviour then rests on `plannerBridgeStale.test.js`. That is the owner's call, and it goes in the ledger row.

## 6c. `end_ignores_gate` — turn-on and verification reads

**What it changes.** Nothing, until an allowlisted account's readiness gate blocks it while a start this system fired is still on the house. Then the end (final, hard cap, status-aware cap or ceiling) is written instead of logged `scopedOut`. The flag never mints a start, never overrides the allowlist or `write_jobs`, and never ends a show whose start was not dispatched (§2's definition of fired).

| Step | `{FIELDS}` (§2) | When |
|---|---|---|
| E1 | `{end_ignores_gate:['<BENCH_UID>']}` | Fri 10-09, with S1, after §6 and before 11:00. It does not depend on a gap. |
| E2 | part of S3: `{served_sticky:true, preflight_bridge_grace:true, end_ignores_gate:true}` | before `uid_allowlist` changes (Sat 10-10) |

**E1 reads (bench).** No incident is needed to verify that the flag is read; the behaviour itself is pinned by `plannerEndGate.test.js`.
- Config read-back: `end_ignores_gate` is an array holding exactly the bench uid string. No "malformed" warning in the planner log.
- The next tick's summary is unchanged: no `endsGateBypassed` key, `errors: 0`.
- The rehearsal's own end (prompt C, gate armed): the `plan_end` row has neither `scopedOut` nor `gateBypassed`. The flag is inert while the gate is armed.

**Optional live proof during the rehearsal (owner's call; one bench-only Firestore write).** After prompt A (the start completed) and at least 15 minutes before the expected final, set `base_ladder_asserts_segments: false` on the bench controller document. Expect on the next tick: a `gate` row `gated_ladder_bad`, `users/<BENCH_UID>.gameday_gate_blocking` = `["gated_ladder_bad"]`, `gameday_server.served: false` with `preflight.reasons` containing `preflight_ladder_bad` and `preflight_gated`. At prompt C: the end job exists with `{"ps":1}`, the `plan_end` row carries `gateBypassed: true` and no `scopedOut`, `lastSummary.endsGateBypassed: 1`, the scorecard entry's `end.gate_bypassed: true`, and `.150` reads back preset 1. After C, set the field back to `true` (or let the app's on-connect healer republish it the next time the app is opened on the home network). While the gate blocks, no NEW start is minted for the bench, which the rehearsal does not need. **Stop sign:** at C the row says `scopedOut: true` although the flag reads back as the list: the flag is not read; check the value's type and do not go on to S3.

**If the 10-05 shape recurs without the flag:** `plan_end … scopedOut:true` every five minutes for a lit house. Restore by hand on the LAN with the 10-01 plan's recovery (`/json/state`, `{"ps":1}` after sunset, never a preset save), then write E1/E2.

**The allowlist, defined.** Removing an account from `uid_allowlist` (or setting `write_jobs:false`) while it has a session with `startPlannedAt` and no `endFiredAt` leaves that house to its owner: the planner logs the end decision `scopedOut` and commands nothing, flag or no flag. Change the allowlist only when no allowlisted session is open, or after its end has completed.

## 7. Rollback
- **Behaviour:** remove the flags (§2 "Remove"). That takes effect next tick, with no deploy.
- **Code:** redeploy `planGameDayFires` from **`309a5d9`** (`fix/gameday-server-ab`, source == rev 00016), with `.env` copied in. **Never from release `a35e30e`**: that rolls back A+B's planner (pre-flight, `gameday_server`, scorecard, `on_time_override`).
- **Bridge write-gap flags:** remove `served_sticky` and `preflight_bridge_grace` (§2 "remove"). From the next tick P2 is 5 minutes again and `served` follows every verdict. Leave the new code live for at least one tick after removing `served_sticky`: a served account is written every tick, and that write deletes any `gameday_server.stale_since`.
- **`end_ignores_gate`:** remove it (§2). From the next tick the gate blocks ends again, exactly as rev 00016. **Do not remove it while an allowlisted account has a lit session and a blocking gate**: that house is then stranded exactly as on 10-05. Nothing to clean: the flag writes no new document type or field; its traces are plan-log rows and the scorecard's `end.gate_bypassed`.
- **Nothing to clean up.** The flagged paths write no new document types; the new reasons are plan-log rows only. The one new field is `gameday_server.stale_since`. If the code is rolled back to `309a5d9` while one is still stored, it is inert: rev 00016 and the app both ignore it.

## 8. Rehearsal — Fri 10-09, Louisville vs Florida State, bench account only

### 8.1 The game
- **Louisville vs Florida State**, Fri 10-09, kickoff **18:00 CDT** (23:00Z). ESPN event **401858254**; Louisville is ESPN team **97**, FBS (group 80). It was NOT on the week-6 featured list when read 2026-10-02.
- **Re-check both on the day** (R0).
- Fallbacks the same evening, both off the featured list on 10-02: Utah State vs Washington State (401860922) and San José State vs Wyoming (401864519), both 20:00 CDT. Next week: Thu 10-15 UAB vs East Carolina, 18:30 CDT (401862800).
- The server event id is **`gd_ncaa_louisville_401858254`**.

### 8.2 Timeline (CDT)

| | |
|---|---|
| fireAt | 17:30 (22:30Z), lead 30 min |
| Mint | the first `*/5` tick at or after 11:30 (16:30Z) |
| Flags in | 11:00–11:25 |
| Final believed | no earlier than kickoff + 2 h (20:00) |
| Shipped cap | kickoff + 4.5 h (22:30). `status_aware_cap` stays absent for the rehearsal. |
| Sunset | ~18:46, so the end restores base ON (`{"ps":1}`), Lumina Blue |

### 8.3 Preconditions
- §6 passed, and the five ESPN-slate keys are still absent. `served_sticky` (and `preflight_bridge_grace`, if already verified) may be on for the bench per §6b; neither changes what the rehearsal mints or when.
- **`uid_allowlist` is the bench**, and `write_jobs: true`. With uid-list flags the rehearsal is bench-only even if another account were allowlisted; there should be none until Saturday.
- The bench pre-flight dry run returns `ok`: `node scripts/_gameday_preflight_dryrun.js <BENCH_UID>`.
- No other enabled bench config has a game Friday evening; the bench NFL team's next game is Sun 10-18.
- **Do not open the app on the home Wi-Fi** from 11:00 until after prompt C; the lease and engine would be a second actor.

### 8.4 The team document (owner's write)
Create `users/<BENCH_UID>/game_day_autopilot/ncaa_louisville` with exactly these fields; it is the app's `GameDayAutopilotConfig.toFirestore` shape.

| Field | Value | Note |
|---|---|---|
| `team_slug` | `"ncaa_louisville"` | |
| `team_name` | `"Louisville Cardinals"` | |
| `espn_team_id` | `"97"` | |
| `sport` | `"ncaaFB"` | |
| `primary_color` | `4289527808` | `0xFFAD0000`, Cardinal red (173,0,0) |
| `secondary_color` | `4294967295` | `0xFFFFFFFF`, white (255,255,255) — not the catalog's black, which renders as "off" in half the effect |
| `enabled` | `true` | |
| `design_mode` | `"fallback"` | |
| `saved_design_name` | `null` | |
| `saved_design_payload` | `null` | |
| `effect_id` | `52` | |
| `speed` | `160` | |
| `intensity` | `128` | |
| `brightness` | `200` | |
| `score_celebration_enabled` | `false` | celebrations are app-only (#145); off keeps the rehearsal server-only |
| `live_scoring_enabled` | `false` | same reason |
| `alert_sensitivity` | `"allEvents"` | |
| `skip_day_games` | `true` | |
| `design_variety` | `"rotating"` | |
| `motion_style` | `0.5` | |
| `created_at` | server timestamp (now) | |
| `updated_at` | server timestamp (now) | |

There is no lead or on-time override, so the lead is 30 min. The participating channels come from the controller doc (`[0,1,2]` as of 10-02). Also append "Louisville Cardinals" to `sports_teams` and `sports_team_priority`, and `ncaa_louisville` to `game_day_team_priority`, on `users/<BENCH_UID>`.

### 8.5 Steps
- **R0. 10:30–11:00: re-check the game.**
  - Run `node ~/.lumina/gameday/gd_live.js 401858254 ncaa_louisville`.
  - The ESPN line must match event 401858254 on `20261009 groups=80`, Louisville (97) vs Florida State, `STATUS_SCHEDULED`, kickoff 23:00Z.
  - The PLANNER VIEW line should read "this event is NOT on it … NOTHING (no_game)", which proves the game exercises the fix. **That line models the flags-off planner.** After R2 it keeps saying "NOTHING"; the truth is in the plan log.
  - If the event id, kickoff or featured status changed, switch to a §8.1 fallback and re-derive the timeline.
- **R1. 11:00–11:15: arm the team.** Write §8.4 and the three profile lists.
- **R2. 11:15–11:25: the flags (bench only).** Write `{espn_college_slate:['<BENCH_UID>'], track_started_by_id:['<BENCH_UID>']}` (§2), then read it back.
- **R3. The first tick at or after 11:30.** Expect:
  - a `plan_start` row for `ncaa_louisville` with `fireAt 2026-10-09T22:30:00.000Z`;
  - the start job `gd_ncaa_louisville_401858254_start`;
  - a scorecard entry;
  - one `gameday_preflight` probe, then `preflight_p6.verdict: "ok"`;
  - `lastSummary.espnFetches` = the pre-flip count (the default boards) + 3 (the FBS dates, read only for the bench), with `espnErrors 0` and `errors 0`;
  - **no new job for any other account.**
- **Prompt A — 17:35.**
  - The start job is `completed`; record the dispatch and bridge latencies.
  - `.150` reads back on, `bri` 200, all three segments fx 52 in (173,0,0) and (255,255,255). `pmt` is unchanged and the queue is empty.
  - `gameday_server.served: true`, the scorecard `start` is completed, and `retryUntil` = kickoff (23:00Z).
  - From the tick after the mint, the summary's `espnFetches` includes one single-game read for 401858254.
- **Prompt B — about 19:30.**
  - The look is unchanged, and there are no new commands.
  - The session shows `consecutiveFinalPolls 0`, and there is no end job.
  - `gd_live` shows the ESPN line in progress. No `cap_held_*`, `espn_unavailable` or `team_not_on_slate` row for the bench.
- **Prompt C — 10–15 min after the final** (not before 20:00).
  - ESPN shows final. The session has `consecutiveFinalPolls 2` and `endFiredAt` set.
  - The end job reason is `confirmed_final` (or `hard_cap` after 22:30), with payload `{"ps":1}`, completed. The plan-log `plan_end` row carries `espnVia: "tracked"`.
  - `.150` shows `ps` 1, Lumina Blue on three buses at `bri` 200. `pmt` is unchanged, and the scorecard has `end.reason` and latencies.
- **R7. After C, before Sat 08:00.**
  - Remove the two flags (§2), or keep them by an explicit decision.
  - Set `ncaa_louisville` to `enabled: false` and remove it from the three profile lists.

### 8.6 Stop signs
- **No `plan_start` by 11:40.** Read the plan-log rows for `ncaa_louisville`, then remove both flags and stop:
  - `no_game`: the flag did not read as on. Check it is an array holding exactly the bench uid string, and look for a "malformed" warning in the logs.
  - `team_not_on_slate`: a wrong id.
  - `daylight_game`: the kickoff moved.
  - `game_not_played`: postponed. `status_aware_cap` should be absent, so this means it is not.
- **A start job for any account other than the bench:** remove the flags at once.
- **The start has not landed by kickoff − 5 min:** the 10-01 plan's manual LAN recovery (the server's own payload, `/json/state` only, never a preset save).
- **An end before 20:00, or a base restore while ESPN shows the game live:** remove the flags immediately, and keep the plan-log rows and the session doc.
- **The app was opened on the home Wi-Fi during the window:** note the time; the lease and engine may have acted. Read `.150`'s `pmt` and timers before trusting prompt C.

### 8.7 Clean means
Every R3/A/B/C expectation is met, the stop-sign list is empty, the end came from the server within ~10 min of the final, and nothing changed outside the bench account. **Only then are the friendlies allowlisted on Sat 10-10** (A+B plan step D). A rehearsal that hit any stop sign moves the friendlies until it is rerun clean.

### 8.8 Checklist
- [ ] §6 verified; the five ESPN-slate keys were absent until R2.
- [ ] §6b S1: `served_sticky` on for the bench, read back; the next gap HELD (`served_held` row, `served` never false, `stale_since` set then removed).
- [ ] §6b S2: `preflight_bridge_grace` on for the bench, read back; the following gap shows no `preflight_skip`.
- [ ] §6c E1: `end_ignores_gate` on for the bench, read back; the rehearsal's `plan_end` row has neither `scopedOut` nor `gateBypassed`; (optional) the gate-flip proof showed `gateBypassed: true` and the end job.
- [ ] §6b S3: all three `true`, read back, BEFORE `uid_allowlist` changes.
- [ ] R0: event 401858254, Louisville = 97, kickoff 18:00 CDT, NOT on the featured list today.
- [ ] R1: the team doc is exactly §8.4; the profile lists are appended.
- [ ] R2: both flags read back as `['<BENCH_UID>']`.
- [ ] R3: `plan_start` at the first tick; fireAt 22:30Z; no job for any other account.
- [ ] A: completed in its minute; red/white on all three buses; `pmt` unchanged.
- [ ] B: nothing ended; tracking visible in `espnFetches`.
- [ ] C: `confirmed_final` within ~10 min; `{"ps":1}`; `espnVia: "tracked"`; Lumina Blue.
- [ ] R7: the flags removed (or kept by decision); the team disabled.

## 9. Ledger and merge notes
- **On deploy,** add a `docs/BUILD_LEDGER.md` row in the A+B row's format: deploy time, rev, read-backs, rollback = `309a5d9`.
- **After the ledger commit,** tear the worktree down as §4.0 says: the junction first, then `git worktree remove`.
- **#146 and #150 keep the 114 branch's numbers.** They are fixed here in `6fe971d`; mark them FIXED when the branches meet.
- **This branch's debt is #156–#162.** `fix/115-multichannel-and-design-card` holds #151–#155. #157 and #159 are fixed here; #158 is partly fixed (the mint-time skip); #161 and #162 are new.
- **The 2026-10-05 write-gap entries are #171–#174** (the release line and `fix/116` hold #163–#170). #172 is fixed here behind `served_sticky` and stays open until the flag is on fleet-wide; #171 (the cause of the gap), #173 and #174 are open.
- **The 2026-10-06 end-gate entries are #177–#180** (`fix/118-controller-selection` holds #175–#176). #177 is fixed here behind `end_ignores_gate` and stays open until the flag is `true` fleet-wide; #178, #179 and #180 are open (§11).
- **Rollback target unchanged:** flags removed first; code from `309a5d9`, never `a35e30e`.

## 10. What the app sees across a ten-minute gap — before and after

The app (builds 114 and 115, `game_day_server_status.dart`) treats a team as server-run when `gameday_server.served` is true, `checked_at` is no older than 30 minutes, and the team is in `teams`. Anything else is "Phone": the phone runs Game Day itself and, on the home network, arms its lease (a preset save plus a timer row).

One gap, planner ticks five minutes apart, the last heartbeat landing just before tick 1:

| Tick | Heartbeat age | Before (rev 00016, or the flags absent) | `served_sticky` on | `preflight_bridge_grace` on (with or without sticky) |
|---|---|---|---|---|
| 1 | 20 s | `served:true`, teams listed. **Server** | the same | the same |
| 2 | 5 min 20 s | `served:false`, `teams:[]`, `preflight.reasons:[preflight_bridge_stale]`. **Phone.** An open app on the home network may arm its lease | `served:true`, teams listed, `checked_at` fresh, `preflight.ok:false` with the reason, `stale_since` set. **Server** | P2 passes inside 15 min: `served:true`, `preflight.ok:true`. **Server** |
| 3 | 10 min 20 s | nothing changed, so nothing is written: still `served:false`. **Phone** | held again, `checked_at` fresh. **Server** | passes. **Server** |
| 4 | 20 s (writes resumed) | `served:true`. **Server** | `served:true`, `preflight.ok:true`, `stale_since` removed. **Server** | **Server** |
| A start due on tick 2 or 3 | | not minted; minted on tick 4 | not minted; minted on tick 4 | minted on its own tick |

Before: about ten minutes of "Phone" per gap, roughly three times a day per house. With B2: none. With A as well: the gap is not a pre-flight event at all.

**Longer than a gap.** With `served_sticky` alone, a bridge that stays silent flips to `served:false` on the first tick at least 30 minutes after P2 first failed, which is about 35 minutes after its last heartbeat. With both flags, P2 first fails 15 minutes after the last heartbeat, so the flip comes at about 45 minutes. Recovery is immediate either way: the first tick that sees a fresh heartbeat publishes `served:true` and the teams.

**What does not change.** A tick on which P2 fails mints no start, held or not, and a start whose fire time has passed is never minted afterwards (`start_time_passed`). Ends are never gated by pre-flight. `checked_at` is written on every tick while `served` is true, so the app's own 30-minute reader keeps working and still catches a planner that has stopped.

**The definition of `gameday_server.stale_since`.** The clock of the planner tick on which P2 first failed in the current unbroken run of failing ticks. It is set on the first failing tick, carried unchanged while P2 keeps failing, and removed on the first tick P2 passes. The hold applies when all of these are true: the flag is on for the account; pre-flight is what withheld the start (enforce mode); `preflight_bridge_stale` is the only failing reason; the stored `served` is true; and less than 30 minutes have passed since `stale_since`. Any other failing reason flips `served` at once, as before, and an account that was not served is never made served by a hold.

**The cost, stated (#173, #174).** While `served` is held the phone stands down. A start that first falls due inside a held gap, and whose fire time passes before the bridge writes again, is fired by nobody. That needs the game to become plannable less than about ten minutes before its fire time, which a normal game (planned six hours ahead) never does. A bridge that is really dead keeps the phone standing down for the length of the hold.

## 11. Where else an end or a restore can be withheld (audit, 2026-10-06)

Read against the branch at `dde45b3`. "Strand" means a house left in team colours with no server end coming.

| Where | What withholds | Can it strand a lit house? |
|---|---|---|
| `planGameDayFires.ts:1071` `writeJobs = allowlisted && gate.armed`, used at the end write `:2056` and the not-owner record `:1973` | the readiness gate | **Yes — the 10-05 incident.** Fixed behind `end_ignores_gate` (`writeEnds`, `:1083`). |
| `planGameDayFires.ts:331` `writesJobsFor` → `allowlisted` | the account leaves `uid_allowlist`, or `write_jobs` is false | **Yes, by design** (§6c). The end is logged `scopedOut`; the owner restores. Change the allowlist only with no open session. |
| `planGameDayFires.ts:1015` `configs.empty` → `continue`; `teardownTeamFires.ts:52–83` cancels only `scheduled` jobs on a config delete | the team is disabled or deleted mid-game | **Yes.** The session is never evaluated again; the teardown writes no restore. **#178.** |
| `planGameDayFires.ts:1461` `no_controller` → `continue` | the controller document is gone | **Yes**, rare. **#180.** |
| `planGameDayFires.ts:1517–1523` participation unusable → `continue` | participation facts aged out or cleared mid-game | **Yes** until they are usable again. **#161 / #180.** |
| `planGameDayFires.ts:1492` `no_game` → `continue` | ESPN drops the game from the scoreboard with `track_started_by_id` and `status_aware_cap` off | **Yes** until the game reappears: neither the final nor the hard cap is evaluated. The ESPN slate fix (this branch) ends it by id and on the clock once those flags are on. |
| `planGameDayFires.ts:1937` GUARD 0b (`gameDayPlanning.ts:453`) | the start job is `scheduled`, `cancelled`, `expired`, `skipped`, `failed` or missing | **No** for all but `failed`: nothing was lit. A `failed` start after a partial apply is the one case. **#180.** |
| `planGameDayFires.ts:1964` `end:not_owner` | a higher-ranked lit team is still playing | **No** by itself: that team's end restores. Chains with any row above. |
| `planGameDayFires.ts:2007` `handoff_refused:gate_blocking` (new) | the gate blocks at a hand-off | **No**: the end restores base instead of lighting the survivor. |
| `planGameDayFires.ts:2092` `endFiredAt` set when the end JOB is created; `gameDayPlanning.ts:588` `already_fired`; `fireJobs.ts:502` 15-minute end budget, `:638` `retry_budget_exhausted`; `dispatchFireJobs.ts:392` terminal `expired`/`failed` | the bridge is silent for more than 15 minutes at the end | **Yes.** The end job goes terminal and nothing re-mints it. **#179.** |
| `dispatchFireJobs.ts:628` one in flight per controller; A1/A3 (`:622` stuck claims cleared, `sweepExpiredCommands.ts:251` stuck pass at 180 s) | a stuck or pending command in front of the end | **No**: a delay inside the retry budget, not a withholding. Combined with the row above, yes. |
| `gameDayPlanning.ts:488` `cap_held_live` (status-aware cap) | ESPN says the game is still live | **No**: the ceiling fires on the clock (#159). |
| pre-flight (any reason), `served:false`, a stale bridge heartbeat | — | **No.** None of them gates an end (`plannerPreflight.test.js`, `plannerBridgeStale.test.js`, `plannerEndGate.test.js`). |
| hierarchy deferral (`startDecision`) | a lower team never started | **No**: nothing was lit; its end is `no_start`. |
