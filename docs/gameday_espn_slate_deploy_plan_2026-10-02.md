# Game Day ESPN slate fix — deploy plan and college rehearsal

**Date:** 2026-10-02 · **Branch:** `fix/gameday-espn-slate`, on `fix/gameday-server-ab` `309a5d9` (A+B, DEPLOYED 2026-10-02 as planner rev 00016 from `d2e0f6e`) · **Code commits:** `84133d6` status-aware cap, `fbbbee3` espnClient, `6fe971d` pre-flight #146/#150, `2298cd9` planner wiring · **Status:** BUILT, NOT DEPLOYED. Nothing here has been run. Every write below is the owner's, after the owner's approval.

Public-repo rule: no customer or bench identifiers appear here. `<BENCH_UID>` is the bench account's uid; take it from the owner's private notes.

## 0. The defect and the fix, in one paragraph

The server's ESPN client read the bare college scoreboard, which is ESPN's FEATURED list (16 Saturday games the week it was found, no Friday games), so an FBS team that is not featured never got a start job. It also found a game only through a scoreboard, so a game ESPN dropped from the board after kickoff was never ended or capped. The fix reads the dated FBS slate for college (ET yesterday, today and tomorrow, `groups=80`, `limit=300`), follows a started session by its ESPN id, makes the hard cap status-aware with per-sport ceilings, and fetches each ESPN URL once per tick. Each behaviour sits behind its own flag, and every flag is off until the owner writes it. Two follow-ups from the +114 app build ride along: pre-flight P4b (#146, also flagged) and `MIN_SERVED_APP_BUILD = 114` (#150).

## 1. What changes on deploy

| Kind | Name | Change |
|---|---|---|
| function | `planGameDayFires` | The only function deployed. With every flag absent it plans exactly as rev 00016 does (golden-tested, §6). The visible differences: one ESPN request per URL per tick instead of one per sport/team pair, and a new `espnFetches` key in the tick summary. P7's informational `lease_hygiene_unknown` now names builds below 114, not 113 (#150); it never skips. |
| config | `config/gameday_planner` | New optional keys, all off when absent: `espn_college_slate`, `track_started_by_id`, `status_aware_cap`, `preflight_ladder_lit`. **No write is part of the deploy.** |
| index | none | Query #8 (`game_day_sessions` where `gameStartMs >=`) is a COLLECTION-scope single-field range, so it uses the automatic index. It runs only with `track_started_by_id` on. |
| rules | none | — |

Not affected: `dispatchFireJobs` imports only unchanged exports from `gameDayPreflight` (the scorecard ids and `publishServerStatusFrom`), so it is not redeployed. The functions diff against `309a5d9` is exactly `espnClient.ts`, `gameDayPlanning.ts`, `gameDayPreflight.ts` and `planGameDayFires.ts`, plus their tests. Outside `functions/`, the diff covers `scripts/_gameday_preflight_dryrun.js` (it follows the P4b flag) and these docs.

## 2. The flags — the exact writes

Each flag is on only when the field is exactly `true` (or `"strict"` for P4b). Absent, `false`, `"true"`, `1` and anything else leave it off. A flip takes effect at the next planner tick (≤ 5 min), with no deploy.

| Flag | On | What it does |
|---|---|---|
| `espn_college_slate` | `true` | `ncaaFB` configs read the dated FBS slate and the deterministic pick, in this order: in progress, then the soonest scheduled game, then a final inside its end window, then a postponed game inside the window. An id that is never on a full slate, and that ESPN says is not FBS (or does not know), is logged `team_not_on_slate`. |
| `track_started_by_id` | `true` | Every sport: a session with a start and no end follows its own game through `scoreboard/{id}`, from the tick after its start is minted until its end fires. An ESPN 404 counts as "silent" and the cap decides; any other error falls back to the scoreboard. |
| `status_aware_cap` | `true` | Every sport: past the shipped bound (kickoff + estimate + 60 min), the cap is HELD while ESPN reports the game live or delayed, up to the per-sport ceiling: football 6 h, MLB 7 h, basketball 4.5 h, NHL 5 h, soccer 5 h. It fires as shipped on silence, postponement, cancellation or suspension. |
| `preflight_ladder_lit` | `true`, or `"strict"` | P4b (#146). `true`: `base_ladder_restore_lit: false` skips new starts (`preflight_ladder_dark`, plus a row naming `base_ladder_dark_channels`), and an absent field is informational only. `"strict"`: an absent field also skips. |

**Turn one on** (from the repo root, ADC credentials, read-only apart from this one field):
```
node -e "const a=require('./functions/node_modules/firebase-admin');a.initializeApp({credential:a.credential.applicationDefault(),projectId:'icrt6menwsv2d8all8oijs021b06s5'});a.firestore().doc('config/gameday_planner').update({espn_college_slate:true}).then(()=>{console.log('ok');process.exit(0)})"
```
Replace `espn_college_slate:true` with `track_started_by_id:true`, `status_aware_cap:true`, `preflight_ladder_lit:true` or `preflight_ladder_lit:"strict"`. Several can go in one `update({...})`. `update()` keeps every other field (`write_jobs`, `uid_allowlist`, `preflight_mode`, …) and fails if the document is missing, which it is not.
Console equivalent: Firestore → `config` → `gameday_planner` → Add field → name, type boolean, `true`.

**Turn it off:** the same command with `false` (or `admin.firestore.FieldValue.delete()`).

**Read back:** `….doc('config/gameday_planner').get().then(d=>{console.log(JSON.stringify(d.data()));process.exit(0)})`.

**These flags are fleet-wide (#157).** Jobs are written only for allowlisted accounts, but a flip changes planning for every allowlisted account at once. Today the allowlist is the bench. Once the friendlies are on it, a "bench-only" flip is not bench-only.

**Suggested order after the rehearsal:** `track_started_by_id` (closes the dropped-game gap, all sports), then `status_aware_cap`, then `espn_college_slate`. `preflight_ladder_lit: true` once +114 is in the fleet; `"strict"` once the controller docs show the field.

## 3. Earliest safe deploy windows

The rule, unchanged from A+B: no deploy between an allowlisted start's mint (fireAt − 6 h) and its end fire + 15 min. The A+B deploy (2026-10-02, rev 00016) soaks through three bench games first.

| Slot (CDT) | Status |
|---|---|
| Sat 10-03 evening, bench college game | **Avoid**, from its mint (~12:00) to its end + 15 min (hard cap ~23:00). A+B soak. |
| Sun 10-04 afternoon, bench NFL | **Avoid** 08:55 → its end + 15 min (~19:30). A+B soak. |
| Thu 10-08 TNF (DAL–TB, 19:15 kickoff) | **Avoid** from its mint (~12:45) to its end + 15 min (hard cap 23:45). A+B soak, and the A+B rehearsal. |
| **Fri 10-09, 08:00–11:00** | **Earliest safe window.** Do it after step 4.1 shows Thursday's session closed and the A+B soak is clean. |
| Sun 10-11 | **Avoid** from 05:30 (friendlies' noon kickoffs mint then, if they are allowlisted) to the last allowlisted end + 15 min. |
| Mon 10-12 → Wed 10-14, daytime | Safe, after checking the allowlist for MNF (10-12 LAR–BUF, 19:15). |

The bench's NFL team has no game on Sun 10-11 and plays Sun 10-18 at 15:25 (read from ESPN 2026-10-02).

## 4. Step 0 — read-only pre-checks

4.1 **Nothing live.** No allowlisted session with `startPlannedAt` and no `endFiredAt` (`node scripts/_check_gameday.js end`). `gameday_plan_log/<today>.lastSummary` shows `errors: 0`.

4.2 **A+B is the live planner, and this branch sits on its head.** Rev 00016 is live from `d2e0f6e`. Run `git fetch` and confirm `fix/gameday-server-ab` is still `309a5d9`; if it moved, rebase this branch and re-run 4.3. Deploying this branch also carries A+B's planner (B1–B4), which is already live, so nothing else rides along.

4.3 **Tree and gates.**
```
cd "C:/Flutter Projects/lumina-gd-espn"
git status --short                       # only functions/lib/createCustomerAccount.js{,.map} (stale tracked output; never commit)
git diff --stat 309a5d9 HEAD -- functions/src   # espnClient, gameDayPlanning, gameDayPreflight, planGameDayFires — nothing else
cd functions && npm run build && npm test       # 895/895
# emulator: JDK 25 on PATH, scratch firebase.json with firestore+auth, --testTimeout=120000 (cold-emulator hooks)
firebase --config <scratch>/firebase.json emulators:exec --only firestore,auth --project lumina-fn-test \
  "npx jest --config jest.emulator.config.js --runInBand --forceExit --testTimeout=120000"
# expect 262/264 — the ONLY failures are commercialRules cross-dealer x2 (#119)
```

4.4 **Config holds none of the new keys,** so the deploy changes nothing: read `config/gameday_planner` (§2 read-back) and confirm that `espn_college_slate`, `track_started_by_id`, `status_aware_cap` and `preflight_ladder_lit` are all absent.

4.5 **Secrets.** Copy `functions/.env` from the MAIN checkout into this worktree, and delete it after the deploy.

## 5. Deploy

```
cd "C:/Flutter Projects/lumina-gd-espn"
FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:planGameDayFires
```
The `predeploy` hook runs the build.

## 6. Verification reads (flags still off)

Within 10 minutes (two ticks):
- **Delivery, not just `updateTime`.** Download the deployed source zip. `lib/planGameDayFires.js` contains `espnFlagsFrom` and `openSessionsByTeam`, `lib/espnClient.js` contains `fetchCollegeSlateGame`, `lib/gameDayPlanning.js` contains `capCeilingMs`, and `lib/gameDayPreflight.js` contains `MIN_SERVED_APP_BUILD = 114`. No `.env` inside the zip.
- **`gameday_plan_log/<UTC date>.lastSummary`** has `espnFetches`. Expect the number of distinct sports with an enabled config fleet-wide (a handful); the pre-fix planner made one request per sport/team pair, about 10 at today's fleet. Expect `espnErrors: 0` and `errors: 0`. The `skipped`/`endSkipped` buckets should match the last pre-deploy tick, moving only as games cross the horizon; there should be no `team_not_on_slate` and no `end:cap_held_live`.
- **Rows:** none with reason `team_not_on_slate` or `cap_held_live`, and none with action `preflight_ladder_dark`.
- **Bench:** `gameday_server.served` and `preflight` are unchanged from before the deploy. Its next start job has the rev-00016 shape (the bench-regression test pins the bytes).
- **Logs:** the planner's stats line carries `espnFetches`. No WARNING+ entries.

Why "unchanged" is a strong claim here: `functions/test/unit/fixtures/plannerFlagsOffGolden.json` is the complete Firestore output of a four-account, three-sport, five-tick scenario. It covers minted starts, a deferral, an ownership-suppressed end, a hard cap, and a game that leaves the scoreboard. It was captured from `d2e0f6e` (rev 00016's source) before any change. The flags-off planner reproduces every document, stat and log row; the summary adds only `espnFetches`.

## 7. Rollback

- **Behaviour:** set the flags back to `false` (§2). That takes effect next tick, with no deploy.
- **Code:** redeploy `planGameDayFires` from `309a5d9` (`fix/gameday-server-ab`, source == rev 00016), with `.env` copied in. **Never from release `a35e30e`**: that rolls back A+B's planner (pre-flight, `gameday_server`, scorecard, `on_time_override`).
- **Nothing to clean up.** The flagged paths write no new document types; `cap_held_live`, `team_not_on_slate` and `preflight_ladder_dark` are plan-log rows only.

## 8. College rehearsal — bench account only

### 8.1 Preconditions
- The deploy is verified (§6) and the flags are absent.
- **The allowlist is the bench alone (#157).** If the friendlies are on it, list their enabled configs with a game in the rehearsal window. For any exposed account, either leave `track_started_by_id` and `status_aware_cap` off for the rehearsal (they act on every sport), or accept that the account takes part. `espn_college_slate` touches only `ncaaFB` configs.
- No other enabled bench config has a game that evening. TNF 10-15 is DEN–SEA.
- The pre-flight dry run returns `ok` for the bench: `node scripts/_gameday_preflight_dryrun.js <BENCH_UID>`. To preview P4b before flipping it: `LADDER_LIT=on node scripts/_gameday_preflight_dryrun.js <BENCH_UID>`.

### 8.2 Candidate games
All are FBS games, and all were off ESPN's default (featured) list for their week when read 2026-10-02. The featured list changes as the week approaches, so re-check on the day (8.4 R0). Times are CDT. Colours come from the app catalog; the config stores ARGB integers.

| Date | Kickoff | Game (ESPN event) | Bench team: slug · ESPN id · name · primary / secondary | Notes |
|---|---|---|---|---|
| **Thu 10-15** | **18:30** | **UAB vs East Carolina (401862800)** | `ncaa_uab` · `5` · "UAB Blazers" · `4280183634` (30,107,82) / `4294955520` (255,210,0) | **Recommended.** First Thursday after the soak. Green/gold reads clearly on LEDs. |
| Thu 10-15 | 19:00 | Texas State vs Colorado State (401860923) | `ncaa_texas_state` · `326` · "Texas State Bobcats" · `4283437588` / `4290945357` | Thursday alternate. |
| Fri 10-09 | 18:00 | Louisville vs Florida State (401858254) | `ncaa_louisville` · `97` · "Louisville Cardinals" · `4289527808` / `4278190080` | Earliest, and guaranteed bench-only (before the friendlies), but on the deploy day. The secondary colour is black, so half the effect is dark. |
| Fri 10-16 | 18:30 | Tulane vs Memphis (401862801) | `ncaa_tulane` · `2655` · "Tulane Green Wave" · `4278216519` / `4285117415` | Friday fallback. |
| Fri 10-16 | 19:00 | Purdue vs Washington (401858493) | `ncaa_purdue` · `2509` · "Purdue Boilermakers" · `4291803537` / `4278190080` | Black secondary. |

Do not use Fri 10-09 Washington–Iowa or BYU–Iowa State: both are on the week-6 featured list, so they would not exercise the fix.

### 8.3 Timeline for the recommended game (UAB vs ECU, Thu 10-15)
- Kickoff 18:30 CDT (23:30Z). Lead 30 min, so fireAt is 18:00 CDT (23:00Z). The start mints at the first tick at or after 12:00 CDT (17:00Z).
- A final is believed no earlier than kickoff + 2 h (20:30). The shipped cap is kickoff + 4.5 h (23:00). The status-aware ceiling is kickoff + 6 h (00:30 Fri).
- Bench sunset is ~18:38, so any end restores base ON (`{"ps":1}`), Lumina Blue on all three buses.

### 8.4 Steps (owner's writes; bench only)
- **R0. Morning check, before 11:30.**
  - `node ~/.lumina/gameday/gd_live.js 401862800 ncaa_uab` should print `PLANNER VIEW: … this event is NOT on it … planner would pick NOTHING (no_game)`. That confirms the game exercises the fix.
  - **That line models the flags-OFF planner** (default scoreboard only). After R2 it still says "NOTHING"; the truth is in the plan log.
  - If the presets were saved since the script's baseline, set `BASE_PMT`.
- **R1. Before 11:30: arm the team.**
  - Create `users/<BENCH_UID>/game_day_autopilot/ncaa_uab` with the same key set as the bench's existing team config (the app's `addTeam` shape), changing these keys: `team_slug "ncaa_uab"`, `team_name "UAB Blazers"`, `sport "ncaaFB"`, `espn_team_id "5"`, `primary_color 4280183634`, `secondary_color 4294955520`, `enabled true`.
  - Keep the look: `effect_id 52`, `speed 160`, `intensity 128`, `brightness 200`, `design_mode "fallback"`, `design_variety "rotating"` and `skip_day_games true`. Set no lead or on-time override.
  - Append "UAB Blazers" to `sports_teams` and `sports_team_priority`, and `ncaa_uab` to `game_day_team_priority`.
- **R2. 11:40–11:55: flip the flags.** `update({espn_college_slate:true, track_started_by_id:true, status_aware_cap:true})` (§2). Read it back.
- **R3. First tick at or after 12:00.**
  - Plan log: a `plan_start` row for `ncaa_uab` with `fireAt 2026-10-15T23:00:00.000Z`. Start job `gd_ncaa_uab_401862800_start`. Scorecard entry. One `gameday_preflight` probe, then `preflight_p6.verdict: "ok"`.
  - `lastSummary.espnFetches` equals the pro sports with an enabled config fleet-wide + 3 (the FBS dates) + any started games + any team documents. Expect `espnErrors: 0` and `errors: 0`.
- **R4. 18:05.**
  - The start job is `completed`, and `.150` reads back on, `bri` 200, all three segments fx 52 in (30,107,82) and (255,210,0). `pmt` is unchanged. The queue is empty.
  - From the tick after the mint, `espnFetches` includes one single-game read for this event.
- **R5. During the game.** No end job and no `cap_held_live` row before 23:00. If there is a weather delay past 23:00, expect `cap_held_live` rows naming `STATUS_DELAYED` (or `STATUS_IN_PROGRESS`) and `ceilingAt 2026-10-16T05:30:00.000Z`, and no end until the final or the ceiling.
- **R6. 10–15 min after the final.**
  - The end job is `confirmed_final` (or `hard_cap_ceiling` at 00:30 at the latest), with payload `{"ps":1}`, completed. `.150` shows `ps` 1, Lumina Blue on three buses.
  - Scorecard `end.reason`. The plan-log `plan_end` row carries `espnVia: "tracked"`.
- **R7. Rollback and cleanup, before Fri 08:00.** Either flip the three flags back to `false`, or leave them on by an explicit decision. Disable `ncaa_uab`, and remove it from the three profile lists if it is not staying.

### 8.5 Checklist
- [ ] §6 verified after the deploy; flags were absent until R2.
- [ ] The allowlist is the bench only, or the exposed accounts were checked (8.1).
- [ ] R0: the game is NOT on the default list today.
- [ ] R3: `plan_start` for `ncaa_uab` at the first tick after the flip; the start job's `fireAt` is right; `espnFetches` as expected; errors 0.
- [ ] No `team_not_on_slate` row for the bench. Rows for other accounts are read, not acted on: each names an id that is not FBS.
- [ ] No start job for any non-allowlisted account.
- [ ] R4: the start landed in its own minute, the look is right, and `pmt` is unchanged.
- [ ] R5: nothing ended before the final, and any hold is named with its ceiling.
- [ ] R6: the end is `confirmed_final` within ~10 min of the final, base ON restored, and the session has `endFiredAt`.
- [ ] R7: the flags are in their decided state, and `lastSummary` has returned to the flags-off shape if they were reverted.

### 8.6 Stop signs
- **No start by 12:10.** Read the plan-log rows for `ncaa_uab`:
  - `no_game`: the flag did not read as on (check the field's type).
  - `team_not_on_slate`: a wrong id.
  - `daylight_game`: the kickoff moved.
  - Flip the flags off and stop.
- **The start has not landed by kickoff − 5 min.** Use the 10-01 plan's manual LAN recovery (the server's own payload, `/json/state` only, never a preset save).
- **An end before 20:30**, or a base restore while ESPN shows the game live: flags off immediately, and keep the plan-log rows.

## 9. Ledger and merge notes
- **On deploy,** add a `docs/BUILD_LEDGER.md` row in the A+B row's format: deploy time, rev, read-backs, rollback = `309a5d9`.
- **#146 and #150 are filed on `fix/114-gameday-app`.** This branch fixes both in `6fe971d`. Mark them FIXED with that SHA when the two branches meet.
- **New debt** #156–#160 is in `docs/BUGS_AND_DEBT.md`, after #142.
