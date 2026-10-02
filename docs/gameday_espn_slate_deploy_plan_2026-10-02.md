# Game Day ESPN slate fix — deploy plan and college rehearsal

**Date:** 2026-10-02 · **Branch:** `fix/gameday-espn-slate`, on `fix/gameday-server-ab` `309a5d9` (A+B, DEPLOYED 2026-10-02 as planner rev 00016 from `d2e0f6e`) · **Status:** BUILT, NOT DEPLOYED. Nothing here has been run. Every write below is the owner's, after the owner's approval.

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

Public-repo rule: no customer or bench identifiers appear here. `<BENCH_UID>` is the bench account's uid; take it from the owner's private notes.

**The plan in one line:** deploy `planGameDayFires` only, **Fri 10-09 08:00–11:00 CDT**, after the A+B code has run the Sat 10-03, Sun 10-04 and Thu 10-08 bench games. Rehearse the same evening on **Louisville vs Florida State, 18:00 CDT**, bench account only, with uid-list flags. The friendlies are allowlisted **Sat 10-10 only after the rehearsal is clean**.

## 0. The defect and the fix

The server read ESPN's featured college list, so an FBS team that was not featured never got a start. It also found a game only through a scoreboard, so a game dropped from the board after kickoff never ended. The fix:
- **College slate:** college football reads the dated FBS slate (ET yesterday, today and tomorrow, `groups=80`, `limit=300`).
- **Tracking:** a started session is followed by its ESPN id.
- **Status-aware cap:** the hard cap holds while ESPN says the game is live, up to a per-sport ceiling. With the same flag, the clock fires the ceiling whatever ESPN does (#159), and no start is minted for a game ESPN already reports postponed or cancelled (#158).
- **URL cache:** each ESPN URL is fetched once per tick.
- **Ride-alongs:** P4b (#146); the first served app build is 114 (#150); `payload_full_state` (the multichannel audit §4.1).

Every behaviour sits behind a flag, and every flag is off until the owner writes it.

## 1. What changes on deploy

| Kind | Name | Change |
|---|---|---|
| function | `planGameDayFires` | The only function deployed. With every flag absent, it plans exactly as rev 00016 does (golden-tested, §6). The visible differences: one ESPN request per URL per tick instead of one per sport/team pair, a new `espnFetches` key in the tick summary, and P7's informational `lease_hygiene_unknown` naming builds below 114. |
| config | `config/gameday_planner` | New optional keys, all off when absent: `espn_college_slate`, `track_started_by_id`, `status_aware_cap`, `preflight_ladder_lit`, `payload_full_state`. **No write is part of the deploy.** |
| index | none | Query #8 (`game_day_sessions` where `gameStartMs >=`) is a COLLECTION-scope single-field range, which uses the automatic index. It runs only for accounts with `track_started_by_id` or `status_aware_cap` on. |
| rules | none | — |

Not affected: `dispatchFireJobs` imports only unchanged exports from `gameDayPreflight` (the scorecard ids and `publishServerStatusFrom`), so it is not redeployed. The functions diff against `309a5d9` touches exactly `espnClient.ts`, `gameDayPlanning.ts`, `gameDayPreflight.ts` and `planGameDayFires.ts`, plus their tests. Outside `functions/`: `scripts/_gameday_preflight_dryrun.js` (follows P4b per uid) and these docs.

## 2. The flags — shapes and exact writes

**Shapes (#157).** Each flag is exactly `true` (fleet-wide) or an array of uid strings (only those accounts). `preflight_ladder_lit` also takes `"strict"`, fleet-wide. Anything else is OFF: absent, `false`, `"true"`, a number, `[]` (nobody), or a list holding a non-string. A present-but-malformed field logs a warning and stays off. A flip takes effect at the next tick (≤ 5 min), with no deploy. Jobs are still written only for allowlisted accounts.

| Flag | What it does when on for an account |
|---|---|
| `espn_college_slate` | `ncaaFB` configs read the dated FBS slate. The pick order: in progress, then the soonest scheduled game, then a final inside its end window, then a postponed game inside the window. An id that is never on a full slate, and that ESPN says is not FBS (or does not know), is logged `team_not_on_slate`. |
| `track_started_by_id` | A session with a start and no end follows its own game through `scoreboard/{id}` until its end fires. A 404 counts as "silent"; any other error falls back to the scoreboard. |
| `status_aware_cap` | Past the shipped bound (kickoff + estimate + 60 min), the cap is HELD while ESPN reports the game live or delayed, up to the ceiling: football 6 h, MLB 7 h, basketball 4.5 h, NHL 5 h, soccer 5 h. **#159:** a started game ESPN cannot be read for (HTTP error, 429, timeout, network, unparseable, partial slate) is held, and the clock fires the ceiling; a game ESPN answers about but no longer lists (empty, missing, single-game 404) is capped at the bound. **#158:** no start for a game ESPN reports postponed, cancelled or suspended. |
| `preflight_ladder_lit` | P4b (#146). `base_ladder_restore_lit: false` skips new starts (`preflight_ladder_dark`, plus a row naming `base_ladder_dark_channels`). With `true` or a list, an absent field is informational; with `"strict"`, it also skips. |
| `payload_full_state` | Start and hand-off payloads state every participating segment field the app sends: `fx sx ix pal grp:1 spc:0 bri:255 frz:false`, three colour slots. An excluded segment becomes `{id, on:false, frz:false}`. Never geometry. 3 buses: 263 B → 431 B. **Not to be turned on before this weekend's bench games finish**, and not during the rehearsal (one variable at a time). |

**The write** — from the repo root with ADC credentials. It changes only the named fields:
```
node -e "const a=require('./functions/node_modules/firebase-admin');a.initializeApp({credential:a.credential.applicationDefault(),projectId:'icrt6menwsv2d8all8oijs021b06s5'});a.firestore().doc('config/gameday_planner').update({FIELDS}).then(()=>{console.log('ok');process.exit(0)})"
```
Replace `{FIELDS}` with one of:

| Purpose | `{FIELDS}` |
|---|---|
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
| **Fri 10-09, 08:00–11:00** | **THE DEPLOY.** Only after step 4.1 shows Thursday's session closed and the three A+B games behaved. It must finish, and §6 pass, before 11:00. The rehearsal's start mints from 11:30 and its flags go in at 11:00–11:25. |
| Sat 10-10 | Friendlies allowlisted, **only if the rehearsal was clean** (§8.7). |

## 4. Step 0 — read-only pre-checks (Fri 10-09, from 08:00)

4.1 **Nothing live.** No allowlisted session with `startPlannedAt` and no `endFiredAt` (`node scripts/_check_gameday.js end`). Thursday's end job is `completed`. `gameday_plan_log/<today>.lastSummary` shows `errors: 0`.

4.2 **A+B is the live planner, and this branch sits on its head.** Rev 00016 is live from `d2e0f6e`. Run `git fetch` and confirm `fix/gameday-server-ab` is still `309a5d9`; if it moved, rebase and re-run 4.3.

4.3 **Tree and gates.**
```
cd "C:/Flutter Projects/lumina-gd-espn"
git status --short                       # only functions/lib/createCustomerAccount.js{,.map} (stale tracked output; never commit)
git diff --stat 309a5d9 HEAD -- functions/src   # the four modules, nothing else
cd functions && npm run build && npm test
firebase --config <scratch>/firebase.json emulators:exec --only firestore,auth --project lumina-fn-test \
  "npx jest --config jest.emulator.config.js --runInBand --forceExit --testTimeout=120000"
# only the two #119 commercialRules cross-dealer cases may fail
```

4.4 **No new key is in the config.** Read `config/gameday_planner` (§2) and confirm all five keys are absent.

4.5 **Secrets.** Copy `functions/.env` from the MAIN checkout into this worktree; delete it after the deploy.

## 5. Deploy

```
cd "C:/Flutter Projects/lumina-gd-espn"
FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:planGameDayFires
```

## 6. Verification reads (flags still absent) — within 10 minutes, two ticks

- **Delivery.** Download the deployed source zip, not just the `updateTime`. `lib/planGameDayFires.js` contains `espnFlagsFrom` and `openSessionsByTeam`. `lib/espnClient.js` contains `fetchCollegeSlateGame` and `defaultScoreboardAnswered`. `lib/gameDayPlanning.js` contains `flagScopeFrom`, `decideEndWithoutEspn` and `gameDayPaletteFor`. `lib/gameDayPreflight.js` has `MIN_SERVED_APP_BUILD = 114`. No `.env` in the zip.
- **`gameday_plan_log/<UTC date>.lastSummary`.** `espnFetches` is present and equals the number of distinct sports with an enabled config fleet-wide (a handful, against ~10 requests before). `espnErrors: 0`, `errors: 0`. `skipped`/`endSkipped` match the last pre-deploy tick, moving only as games cross the horizon.
- **None of the new rows:** `team_not_on_slate`, `cap_held_live`, `cap_held_unavailable`, `espn_unavailable`, `game_not_played` or `preflight_ladder_dark`.
- **Bench.** `gameday_server.served`/`preflight` are unchanged, and no new job.
- **Logs.** The planner's stats line carries `espnFetches`. No WARNING+, in particular no "malformed" flag warning.

Why "unchanged" is a strong claim: `functions/test/unit/fixtures/plannerFlagsOffGolden.json` is the complete Firestore output of a four-account, three-sport, five-tick scenario, captured from `d2e0f6e` before any change. The flags-off planner reproduces every document, stat and log row, and the bench-regression snapshot is byte-identical with every flag off, with every ESPN flag on, and with `payload_full_state` explicitly off.

**If §6 is not clean by 11:00:** do not write the flags. Roll back (§7) and move the rehearsal to the Friday fallback week (§8.1).

## 7. Rollback
- **Behaviour:** remove the flags (§2 "Remove"). That takes effect next tick, with no deploy.
- **Code:** redeploy `planGameDayFires` from **`309a5d9`** (`fix/gameday-server-ab`, source == rev 00016), with `.env` copied in. **Never from release `a35e30e`**: that rolls back A+B's planner (pre-flight, `gameday_server`, scorecard, `on_time_override`).
- **Nothing to clean up.** The flagged paths write no new document types; the new reasons are plan-log rows only.

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
- §6 passed, and the five keys are still absent.
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
- [ ] §6 verified; the five keys were absent until R2.
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
- **#146 and #150 keep the 114 branch's numbers.** They are fixed here in `6fe971d`; mark them FIXED when the branches meet.
- **This branch's debt is #156–#162.** `fix/115-multichannel-and-design-card` holds #151–#155. #157 and #159 are fixed here; #158 is partly fixed (the mint-time skip); #161 and #162 are new.
