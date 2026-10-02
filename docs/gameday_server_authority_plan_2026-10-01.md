# Game Day works for everyone — server single authority, sequenced build plan

**Date:** 2026-10-01 (Thursday; a bench-only server fire is in progress tonight) · **Code read:** `release/store-submission-consolidated` @ `a35e30e` (= `build-112` + ledger row), `firmware/bridge-1.3` @ `42722a0`, `feat/gameday-single-authority` @ `089ee12`, fielded bridge image "1.2" (`esp32-bridge/src/main.cpp` at HEAD) · **Status:** PLAN ONLY. No code, no deploys, no Firestore writes, no bridge or controller commands were made for this document. The only write is this file, on a docs-only branch cut from `a35e30e`.

Public-repo rule: no customer names, uids, emails, MACs or home IPs appear here. Accounts are described by shape.

---

## 0. Corrections to the brief's inputs (read first)

| Brief said | What the code and deploy records say | Effect on the plan |
|---|---|---|
| Firmware is frozen at `v1.0.0-firmware-phase-1` | That tag is on an unmerged branch and is **not** the fielded image. Fielded bridges report `1.2` and match `esp32-bridge/src/main.cpp` at HEAD (the May-12 image). The watchdog, heartbeat and poll logic are near-identical in both, so every #109 finding holds for the fleet. | "Freeze" means the 1.2 image. Any firmware item = USB reflash per bridge (no OTA in 1.2; the partition table itself cannot move over the air). |
| Policy B never built (hard cap, base suppression, hold until final) | **Hard cap is live**: `dcd4d1c` deployed as `planGameDayFires` rev `00015` on 2026-09-24 (deploy record in the single-authority report §7; the commit message predates the deploy). Hold-until-final is the existing `REQUIRED_FINAL_POLLS = 2` + cap. The ledger has no rows for revs 00014/00015. | Step 3 shrinks to **base-layer suppression** plus a ledger fix. |
| Lead-time field mismatch (`lead_time_minutes_override` vs `lead_time_minutes`) | Fixed server-side in `2ac3bc8` (rev 00014, in release since +107): `gameDayHierarchy.ts:62-68` reads `lead_time_minutes_override` first. The app never writes the bare key. The stale read only survives in the main checkout, which is detached at build 88. | Step 4 is the armed-state contract only. Work from the release worktree, never the main checkout. |
| Celebration path ignores `alert_sensitivity` **and** `celebration_effect_id` | Build 112 honours the effect (`foreground_celebration_providers.dart:176` → `resolveCelebration`). Sensitivity is still forced to `allEvents` at `:171`. | The app-side fix is one line plus tests. |
| 90 s pickup window is a bridge property | It is server-side: `MAX_FIRE_LATENESS_MS` and `FIRE_GRACE_MS` in `fireJobs.ts:40,68`. The firmware reads neither `createdAt` nor `expiresAt`. | Tunable without firmware. |
| Commands stuck in "executing" block later fires | Confirmed and worse: `hasInFlightCommand` (`controllerHealth.ts:626-636`) has **no age limit**, and no sweeper touches `executing`. One bridge reboot mid-command blocks that controller's Game Day fires until 7-day retention. (P2-56, one customer bridge had 11 stuck.) | Highest-value server fix; no firmware. |
| S5b sketch with numbers (6–10 pickups, 5–65 s) | No S5b design exists in the repo; `UNATTENDED_OPERATION.md` only sizes it (12 h, optional). The numbers come from the conversation, not a document. | §3.5 is the first written design. |

---

## 1. Where it stands today

| Surface | State (verified) |
|---|---|
| Planner `planGameDayFires` | `*/5` cron, rev 00015 (hierarchy + hard cap). `config/gameday_planner`: `write_jobs:true`, `uid_allowlist` = the bench account only. Reads `controllers.docs[0]` only (#97). Writes `gameday_gate_blocking` for every account whether allowlisted or not. |
| Dispatcher `dispatchFireJobs` | Minute cron. `too_late` after 90 s; command `expiresAt` = dispatch + 90 s; one-in-flight guard per controller with no age cap. Reconcile records `latencyMs`, `writeHopMs`. |
| Sweeper | `pending` only, every minute. `executing` is immortal. |
| Bridge 1.2 (fleet) | Poll every 1–2 s, `status == pending`, `limit 5`, **no orderBy**; serial execution; heartbeat + registry PATCH on the poll thread (5–6 s busy per 30 s); watchdog reset on every heartbeat attempt and on registry 200s; 5-min check inside `loop()`; no task watchdog; no sign-in retry after a failed boot; no OTA. |
| Phone lease | Arms within 48 h, foreground + LAN + flag only. Solid brand colour, `fx:0`, one segment, `ib:true`, preset 26–41, one ON timer with weekday mask, **no OFF row** (re-fires weekly until swept). 112 unregisters a deferred lease so the sweep re-promotes it. Ledger is SharedPreferences only. |
| Phone engine | 1-min foreground timer; fires the design at kickoff − lead; turns OFF at final. Served accounts cannot learn they are served (every server doc is default-denied). |
| Celebrations | Foreground only (`kSportsBackgroundServiceEnabled = false`), ESPN poll 30 s, one controller, effect honoured, sensitivity ignored, revert = captured `ps` or state. Never fired on hardware for anyone (#79 as of August). |
| Fleet | 56 users; ~13 paired bridge rows; 2 customer accounts with no bridge; 4 controllers unreachable in the 10-01 triage; 5 residential customers of dealer 01 hold 10-04 Game Day entries (4 KC, 1 MIN) with no server coverage. |
| Tonight | Bench account, server-only fire (start 1.95 s, 3 buses). Not to be touched. |

---

## 2. Sequence

Re-ordered from the brief. The ordering rule: ship what moves customers to server-fired start/end first, make every step independently reversible, and keep the firmware program on its own track because it is a truck roll.

| Plan step | Brief step | Track | Why here |
|---|---|---|---|
| **A. Server reliability** (stuck sweeper, in-flight age cap, retries, ordering rule) | 1 (server half) | functions | Without A, one bridge hiccup = dark house for a week. Needed before any customer is allowlisted. |
| **B. Pre-flight + `gameday_server` contract + scorecard writer** | 7 (pre-flight) + 4 (server half) | functions + rules | The allowlist is only safe with an automatic skip, and the app cannot stand down until the field exists. |
| **C. App stand-down + lease skip + armed banner + sensitivity fix** | 2 + 4 (app half) + 5 (app fix) | app build 113 | Removes the double-fire for served accounts. Ships after B so the field exists before the reader. |
| **D. Allowlist: 3–5 friendly accounts, two games** | 7 (rollout) | config | First customer server fires. Tolerable before C ships (same-minute overlap, server wins); C makes it clean. |
| **E. Policy B base-layer suppression** | 3 | functions | Visible mid-game stomps; needed before "everyone", not before friendlies. |
| **F. #97 one job pair per controller** | 6 | functions | Needed before "everyone"; multi-controller homes are a minority. |
| **G. S5b server celebrations + kill switch** | 5 | functions + app + config | Highest write frequency; last on the server track. |
| **H. Firmware 1.3.0 (#109 watchdog, heartbeat task, OTA)** | 1 (firmware half) | firmware, parallel | Critical-bar justified, but it never gates the Game Day rollout: pre-flight skips a stale bridge. |
| **I. Everyone** (`uid_allowlist: null`, pre-flight as the gate) | 7 | config | After two clean friendly games and E + F deployed. |

Dependencies: B needs A (the scorecard reads retry outcomes). C needs B (the field). D needs A + B. E needs B (`base_boundaries` facts and the preflight row shape). F needs B. G needs A + B + F (per-controller celebration pairs). I needs D + E + F.

---

## 3. Steps

Each step lists scope at file level, tests, risk, rollback, and the measurable check on a real game. File paths are relative to the release worktree unless marked `esp32-bridge/`.

### 3.1 Step A / brief 1 — bridge reliability

Firmware vs server, item by item:

| Item | Where it must be fixed | Why |
|---|---|---|
| #109 watchdog resets on every heartbeat attempt; 5-min check inside `loop()`; no sign-in retry | **Firmware** (USB reflash per bridge) | The defect is in `main.cpp:251-277` on the fleet image. The server can detect a wedged bridge (stale heartbeat) but cannot reboot it. |
| "executing" stall (no age limit, no sweeper) | **Server** | `sweepExpiredCommands.ts` + `controllerHealth.ts`; the firmware never re-picks `executing` anyway. |
| 90 s pickup window | **Server** | `fireJobs.ts:40,68`. Convert to per-attempt grace + bounded retries. |
| Command ordering (no orderBy) and batch of 5 | **Server design rule**; firmware optional later | The server can guarantee at most one pending Game Day command per controller, which makes order irrelevant. Adding `orderBy createdAt` to the bridge query needs an index and a reflash: first-OTA candidate, not critical. |
| Heartbeat busy window (5–6 s / 30 s) | Firmware; **not required** for Game Day | It adds ≤ 5 s to a fire. Latency, not reliability. |

**A1. Stuck-executing sweeper + in-flight age cap (server).**
- Scope: `functions/src/sweepExpiredCommands.ts` — second pass: `collectionGroup("commands").where("status","==","executing").where("createdAt","<", now − 180 s)` → `status:"failed", error:"stuck_executing", expiredAt`, transactional on still-`executing` (port of the shape already on `feat/neighborhood-sync-v1` `applySyncPattern.ts:965-976`, generalised to every `source`). New composite index `commands (status, createdAt)` COLLECTION_GROUP (the existing one covers `pending`; verify it serves `executing` too — same fields, so it should). `functions/src/controllerHealth.ts:626-636` `hasInFlightCommand`: ignore docs with `createdAt` older than 180 s. `functions/src/dispatchFireJobs.ts:158-197` reconcile: map `failed/stuck_executing` to job `outcome:"stuck_executing"` (feeds A2 retry).
- Why 180 s: an `executing` doc older than ~60 s means the bridge's `completed` PATCH failed or the bridge died (WLED timeout 10 s + PATCH worst case 45 s). 180 s leaves margin for TLS stalls. The app's own 45 s watchdog still handles app commands first.
- Tests: `functions/test/unit/sweepExpiredCommands.test.js` (executing older than threshold → failed; younger → untouched; `completed` arriving concurrently wins), `controllerHealth` age-cap cases, `dispatchFireJobs` reconcile mapping. Emulator: one case in the existing relay emulator suite.
- Risk: a command the bridge is still legitimately finishing gets `failed`; the bridge's later `completed` PATCH overwrites `status` (its mask is `status, completedAt, result`), so the final state is `completed`. Benign.
- Rollback: redeploy the previous `sweepExpiredCommands` + `dispatchFireJobs` revisions; stuck docs return to immortal.
- Real-game check: zero `executing` docs older than 3 min fleet-wide at any sample during the game; scorecard `stuck_executing_count`.

**A2. Retry budget instead of a single 90 s window (server).**
- Scope: `functions/src/fireJobs.ts` — `decideDispatch` lateness becomes per job: `retryUntil` (new job field) instead of the fixed `MAX_FIRE_LATENESS_MS`; new pure `decideRetry(job, outcome, now)` → `{retry: bool, nextFireAt, attempt}` with backoff 30/60/120/300 s. `functions/src/planGameDayFires.ts:699-713, 929-949` — write `retryUntil`: start = `min(fireAt + leadMs, gameStart + 15 min)`; end = `fireAt + 15 min`. `functions/src/dispatchFireJobs.ts` reconcile — on `expired` (not picked up), `failed` with `HTTP -1`, or `stuck_executing`: if `decideRetry` says yes, set `state:"scheduled", fireAt:next, attempts+1, lastOutcome`. Never retry `no_bridge_paired`, HTTP 4xx, `config_missing_or_disabled`. Command ids already include `fireAt` seconds (`commandSafety.ts:172-175`), so each attempt is a new deterministic id.
- Idempotency: start and end payloads are full-state applies (`seg[...]`, `{ps:N}`); re-sending is harmless. Celebrations are excluded (see G).
- Tests: `fireJobs.test.js` retry matrix (each outcome × attempts × `retryUntil`), `plannerHierarchy.test.js` writes `retryUntil`, dispatcher tick-driven: expired → rescheduled → completed on attempt 2; retry refused after `retryUntil`.
- Risk: a late start lands after kickoff (bounded at +15 min); a retried end lands after the user manually changed the lights (bounded at 15 min). Both preferable to dark.
- Rollback: redeploy prior revs; jobs carrying `attempts > 0` are inert.
- Real-game check: scorecard `start.attempts` histogram; start success rate for served + pre-flight-ok accounts = 100%; no `too_late` rows for served accounts.

**A3. Ordering and batch rule (server, no code beyond A1/A2 + G).**
- Rule: the server never has more than one pending or executing Game Day command per controller. Start, re-assert, end and revert jobs are serialised by the in-flight guard (now bounded by A1). The celebration → revert pair is chained (revert minted only when the celebration is terminal, G). Multi-controller fan-out (F) writes one doc per controller; cross-controller order does not matter. App-written commands may interleave; the app's 45 s watchdog owns those.
- Firmware follow-up (optional, first OTA): `orderBy createdAt` in the runQuery + a `commands (status, createdAt)` index. Not a critical-bar change.
- Real-game check: at no sample during the game does a controller have > 1 non-terminal server command.

**A4 / Step H. #109 and the 1.3.0 firmware program (firmware).**
- Scope: `esp32-bridge/src/main.cpp` and `platformio.ini` on `firmware/bridge-1.3` `42722a0` (TWDT 180 s on loopTask + heartbeat task + supervisor; progress = `runQuery` 200 only; sign-in retry every 30 s; RTC breadcrumbs `resetReason/prevCause/prevLoopPhase`; heartbeat task on core 0 with its own TLS client; `min_spiffs` partitions + signed OTA; per-bridge credential). Supersedes `a03cf0f`; never merge both.
- Critical-bar justification: (1) 2026-09-16 live stall, 11 min, ICMP alive, no self-reboot; (2) 11 immortal `executing` docs on one customer bridge; (3) a customer bridge rebooted 10-01 with no watchdog in 1.2 (power blip or someone unplugging); (4) the bug log's "hang until unplugged" reports; (5) no OTA means every later fix is another visit, so the OTA layout must ride the same visit. The server cannot substitute: A1/A2 and pre-flight only make a wedged bridge *visible* and skip it.
- Tests: bench protocol T4j first (NVS survives the partition change), then T1a–T1g (watchdog), T2a–T2d (heartbeat task, `minHeap ≥ 60 KB`), T4a–T4i (OTA), T5 (credential), R regression. Needs a confirmed spare bridge (three blanked units exist; never the home bridge).
- Risk: false reboots (180 s between feeds), heap with two TLS sessions, bootloader rollback behaviour, NVS across the partition change.
- Rollback: USB reflash the 1.2 image at the same visit (keep the 1.2 merged bin on the laptop); the shared credential stays enabled until `fleet_readiness` says otherwise.
- Rollout: bench → home bridge 72 h soak + first OTA → one opted-in beta customer (7 days) → the rest batched by dealer. Each is one USB visit. **Never gates Game Day:** pre-flight P2 (stale heartbeat) skips the account and the app fires as today.
- Real-game check: for served accounts on 1.3.x, heartbeat gap ≤ 60 s all game, `resetReason` absent, `prevCause` never `no_poll_progress`; Proof A re-run: no fire above 4 s write→light.

### 3.2 Step C (part) / brief 2 — retire the phone lease for Game Day entries

Decisions baked in (override if wrong): **D1** heartbeat `checked_at` every tick for served accounts (stale > 30 min = not served; dead planner degrades to today's behaviour, never to dark); **D2** per-team `teams` list; **D3** observe mode until G ships, then full stand-down; **D4** retract already-armed leases on the next LAN sweep, accept the one-night overlap on old builds; **D5** keep the calendar rows, make the lease manager skip them.

- **What stops writing (served teams only):** the lease entry points — `lib/features/schedule/calendar_entry_lease_manager.dart` `_handleEntryCreatedImpl` (new-lease and update paths, the 112 lines around `:745-850`), the sweep promotion loop (`sweepExpiredLeases`), and the eviction picker path in `lib/features/schedule/calendar_providers.dart:450-478` — return a new `LeaseOutcome.servedByServer` for any entry whose `entryId` starts with `gd_<served slug>` and whose `sourceTag == gameDay`. No psave, no cfg POST. The engine — `GameDayAutopilotNotifier._evaluate` → `evaluateConfigs` in `lib/features/autopilot/game_day_autopilot_service.dart:325` — takes the served set; served teams get observe-only sessions that never call `onApplyJson`, `onResumeNormalSchedule`, or the hand-off apply. Unserved teams byte-for-byte unchanged.
- **What migrates:** nothing. The lease ledger is SharedPreferences; the server already holds configs, participation and ladder facts. No Firestore schema change.
- **Existing leased entries and presets 26–41:** on the next LAN sweep after the update, zero the timer row of every Game Day lease whose team is served (`_writeZeroedSlot`, one merged cfg POST) and drop the record. Presets 26–41 stay on the controller: without a timer row they are inert, the lease path has never `pdel`'d, and the bench controller's flash damage argues against new `pdel` traffic. Slot hygiene for 26–41 is a separate later item. Old builds (≤ 112) self-clean the expired lease on the next LAN open after `offTime` (existing behaviour); the only residue is the weekly re-fire for a home that never opens the app at home — pre-flight marks it `lease_hygiene_unknown`, informational.
- **The five dealer-01 accounts with 10-04 entries:** 10-04 is unchanged for them (unserved; lease or foreground app, as today). When they become served (D), a 10-04 lease that armed will have expired by then and is zeroed on their next LAN open on any build; a 113 build zeroes it even earlier. Until the LAN open, that slot re-fires solid team colour every Sunday at the 10-04 on-time; the server's start on the same Sunday overwrites it at its own time and the end restores base. Disclose to the dealer: "open the app at home once after updating."
- **Old-build overlap for served accounts (until 113 is installed):** lease fires solid colour at kickoff − 30; the server's full design lands seconds later and wins. Foreground engine (if the app is open) turns OFF at final; the server restores base 5–10 min later. Visible once, harmless.
- Tests: lease manager — served `gd_` entry → no lease, unserved identical entry → leased; armed lease for a team that becomes served → zeroed on sweep; holiday skip unchanged. Autopilot — served team through a whole game cycle → zero `onApplyJson`/`onResumeNormalSchedule`; mixed served + unserved; the existing ~260 autopilot tests untouched. Existing `lease_deferral_rearm_test.dart`, `game_day_date_refusal_test.dart` stay green.
- Risk: a stale `served:true` (dead planner) silences the app → mitigated by D1 staleness (30 min). A client forging `served:true` on its own user doc → rules deny-list (B).
- Rollback: the field absent/stale ⇒ app behaves as 112. Flip the planner to stop writing it (B's `publish_server_status` flag) and every app reverts within 30 min without a build.
- Real-game check: for served accounts on 113, `controllers/{id}.base_boundaries` shows zero rows with `macro` in 26–41 after the first LAN open (scorecard `lease_residue_rows`), and no `source: game_day` app commands during the game.

### 3.3 Step E / brief 3 — Policy B: base-layer suppression while armed

Hard cap and hold-until-final are live (rev 00015). What is missing is that the controller's own everyday timers (sunset ON ladder, bedtime OFF) fire mid-game and stomp the design. The server cannot disable WLED timers (no `/json/cfg` over the bridge; `applyConfig` lands on `/json/state` and is discarded). So suppression = **re-assert**, plus a ladder-aware end restore.

- Scope: `functions/src/planGameDayFires.ts` — when minting `_start`, read `controllers/{id}.base_boundaries` (healer-published `timers.ins` rows, clock and solar; solar resolved with the existing sun helper used by `isDaylightOnlyGame`) and mint one `${eventId}_reassert_${HHMM}` job per boundary inside `[startFireAt + 2 min, fallbackEnd]`, `fireAt = boundary + 60 s`, payload = the start payload, `seq:"reassert"`, `retryUntil = fireAt + 5 min`. `functions/src/gameDayPlanning.ts:590` `baseRestorePayload` — choose `{ps:2}` if the latest base boundary before the end was an OFF row, else `{ps:1}` (today it is sunset-only). `functions/src/fireJobs.ts` — `seq:"reassert"` in the state machine; `functions/src/dispatchFireJobs.ts` — **user-override guard**: skip a re-assert (`outcome:"user_override"`) if any `source != fire_job` command for that controller completed after the start fire (the user touched the lights). `teardownTeamFires.ts` cancels re-asserts too. Flag `config/gameday_planner.reassert_enabled` (default false) read by the planner.
- Also: a game crossing the base OFF boundary **holds through it** (Tyler's stated goal) and the end restores OFF. State it in copy.
- Tests: `plannerHierarchy.test.js` — boundary inside the window → one re-assert, outside → none, solar row resolves; `gameDayPlanning` restore chooser; dispatcher user-override guard; teardown cancels. Fake Firestore already supports the collections.
- Risk: re-assert relights a house the owner turned off mid-game → the guard covers app commands; a wall switch or WLED web UI change is invisible (accepted). `base_boundaries` stale (healer publishes once per LAN session) → a moved timer is missed; bounded.
- Rollback: `reassert_enabled:false` stops minting; existing re-assert jobs cancelled by the next planner tick when the flag is off.
- Real-game check: pick a served game that spans a base boundary; controller readback (via a `getInfo`/`getState` probe or LAN) 2 min after the boundary shows the Game Day `fx`; scorecard `reasserts.planned == reasserts.completed`; end restore matches the ladder state for the hour.

### 3.4 Step B + C (part) / brief 4 — lead time and armed-state display

- **Lead time:** already live. Remaining: pin it with a test that the planner never falls back to the bare key for a doc carrying the override (exists, `plannerHierarchy.test.js:833`); add ledger rows for revs 00014 and 00015; honour `on_time_override` server-side (`gameDayHierarchy.ts leadMinutesFor` → `windowStartFor(c, game)`), since served accounts would otherwise lose a setting the app honours. ~20 lines + 3 tests.
- **Armed state — server half (B):** `functions/src/planGameDayFires.ts` beside the gate persist (`:418-432`): write `users/{uid}.gameday_server = { served, teams[], celebrations[] (G), checked_at, preflight:{ok, reasons[], at}, next_fire:{event_id, team_slug, seq, fire_at} | null, last_fire:{event_id, seq, state, completed_at, latency_ms} | null }`. `checked_at` every tick for served uids, on change otherwise. `last_fire` is written by the dispatcher reconcile. Inside the existing "a failed state write must never stop planning" catch. Flag `config/gameday_planner.publish_server_status` (default true once deployed; false = stop writing, app falls back).
- **Rules (ceremony: grep lib/ and functions/, deploy after the rules diff gate):** add `gameday_server` and `gameday_gate_blocking` to the client deny-list on `users/{uid}` update, so a client cannot silence its own app.
- **App half (C):** new `lib/features/game_day/game_day_server_status.dart` (pure `fromUserDoc(raw, now)`: absent, malformed, stale > 30 min, signed-out, error ⇒ not served) + `game_day_server_status_provider.dart` cloned from `gate_status_provider.dart`. `lib/features/game_day/gate_status_banner.dart` and `game_day_screen.dart:1351-1429` badge: three states — **Server** ("Runs from our servers. Lights change with the app closed. Next: Chiefs, Sun 2:55 PM" from `next_fire`; celebrations line per G), **Phone** ("Runs from this phone when the app is open at home" + the pre-flight reason when the account is allowlisted but skipped), **Blocked** (gate reason, shown only when served). Day timeline Game Day row gets a small "server" / "phone" tag from the same provider.
- Tests: tick-driven S1 (allowlisted + armed → served; gated, scoped-out, malformed list, flag off → false; heartbeat only for served; pre-flight reasons surface); pure parser unit tests for every fail path and the staleness edge; widget tests for the three banner states and the stale → phone fallback.
- Risk: D1 cost — 288 writes/day per served account (negligible); a planner outage shows "Phone" within 30 min, which is the truthful state.
- Rollback: stop writing (flag) or ship a build; either side alone is safe (absent field = today).
- Real-game check: every allowlisted account shows "Server" in the app on game day (dealer screenshot); `checked_at` age < 10 min sampled hourly; `next_fire` matches the minted job.

### 3.5 Step G / brief 5 — server score celebrations (S5b)

**Design.**
- **Poller** `functions/src/pollLiveScores.ts`: minute cron, `timeoutSeconds: 70`; polls ESPN at t+0 and t+30 (one sleep) so detection latency ≤ 30 s; runs only while a served session is live (`collectionGroup("game_day_sessions").where("startPlannedAt", ">=", now − 6 h)` and no `endFiredAt`; needs a COLLECTION_GROUP index on `startPlannedAt`). One ESPN fetch per (sport, team) per poll, shared across users (extend `espnClient.ts` to return `homeScore, awayScore, period, clock`). Reads the hierarchy owner so only the owning team of a house celebrates.
- **Score state** on the session: `score:{home, away, lastDeltaAt, lastPollAt}`. Deltas classified in a pure `functions/src/celebrationEvents.ts` (port of `ScoreMonitorService` rules: NFL +6/+7/+8 TD, +3 FG, +2 safety, +1 PAT; MLB/NBA/NHL equivalents), **user's team only** plus `win` at the first final poll, filtered by `alert_sensitivity` (`majorOnly` → TD/goal/HR/win; `allEvents` → all). Negative deltas (ESPN corrections) ignored. Multiple scores inside one poll collapse to the biggest event.
- **Celebration job** `fire_jobs/{eventId}_cel_{home}-{away}` (deterministic by score state; `.create()` makes a re-poll idempotent). `type: applyJson`, payload = the team's `celebration_effect_id`/`celebration_speed`/`celebration_intensity` with team LED colours, **one stage** (the bridge costs ~1.5 s per PATCH, so the app's three-stage choreography collapses to one effect held for the app's total: TD 15 s, FG 8 s, win 30 s). `fireAt: now`, `noLaterThan: now + 60 s` (a stale celebration is dropped, never retried), `retryUntil: none`. The poller **dispatches it itself** in the same invocation (same in-flight guard) to skip the minute-cron hop.
- **Revert job** `fire_jobs/{eventId}_rev_{home}-{away}`: `dependsOn` the celebration job; dispatched only once the celebration is terminal (completed, failed, expired) — never while it is pending, which gives ordering on an unordered bridge. `fireAt = cel.completedAt + hold` (fallback `cel.fireAt + hold + 10 s`), payload = the session's start payload (the live design is not a preset, so `{ps:N}` cannot restore it; for a hand-off session use the survivor's payload), `retryUntil = fireAt + 5 min`, idempotent. **Revert grace:** 2 s added to hold for the PATCH cost.
- **Re-mint watchdog:** each poll, any session with a celebration completed and no completed revert within `hold + 3 min` mints `_rev_{score}_r{n}` (n ≤ 3). After three, write `celebration_revert_failed:true` on the session and the scorecard; the end job restores base at the final or the cap regardless.
- **Anti-strobe:** ≥ 20 s between celebrations per house; `kill switch` and `max_celebrations_per_game` (default 12) in `config/gameday_planner`.
- **Flag and kill switch:** `config/gameday_planner.write_celebrations` (default false) plus `celebration_uid_allowlist` (same semantics as `uid_allowlist`). Flipping `write_celebrations:false` stops minting at the next poll and cancels pending celebration jobs (`cancelled_reason: kill_switch`); **reverts still run**.
- **App stand-down:** `gameday_server.celebrations[]` → `computeLiveCelebrationTeams` (`foreground_celebration_providers.dart:129-181`) excludes served teams (observe only). Copy: "Score celebrations run from our servers and land within about a minute of each score."
- **Latency and copy:** detect ≤ 30 s + ESPN feed lag (10–40 s behind broadcast) + bridge 2–7 s. Promise "within about a minute", never "instantly". Show "Last celebration: 3:41 PM, 22 s" from `last_fire`.
- **Pickups per game:** ~6–10 scoring plays → 12–20 commands per controller per game plus start/end/re-asserts. Bridge serial cost ≈ 3 s each; WLED one request at a time. No contention with the one-in-flight rule.
- **Multi-controller:** one celebration + revert pair per controller (F), same ids suffixed with the controller id.
- **Separate small item (app, build 113):** `foreground_celebration_providers.dart:171` pass `cfg.alertSensitivity` instead of `AlertSensitivity.allEvents`; a device check that the chosen effect fires (112 code path). Tests: `foreground_celebration_test.dart` sensitivity matrix; `celebration_firing_test.dart` chosen effect.
- Tests: `celebrationEvents.test.js` (delta × sport × sensitivity; corrections; collapse), `pollLiveScores` tick-driven with the fake Firestore (score → cel + rev; same score → nothing; kill switch cancels but reverts run; watchdog re-mints; owner-only in a two-team house), `fireJobs` `dependsOn` and `noLaterThan`, dispatcher chain ordering, `gameday_server.celebrations` written.
- Risk: a misclassified delta flashes the house for a non-event; a failed revert leaves an effect running (bounded by the watchdog and the end job); ESPN score corrections; a dead poller means no celebrations but never a stuck house (end job is independent).
- Rollback: `write_celebrations:false` (immediate); redeploy prior revisions; the app falls back to phone celebrations when `celebrations[]` is absent.
- Real-game check: scorecard `scores_detected` vs ESPN box score; `celebrations_fired / scores_detected ≥ 95%`; `cel_latency_p95 ≤ 45 s` (poll-detect → completed); `reverts_completed == reverts_total`; `revert_failed == 0`; controller readback after each revert shows the start `fx`.

### 3.6 Step F / brief 6 — #97 multi-controller homes

- Scope: `functions/src/planGameDayFires.ts:374-375` — replace `controllers.docs[0]` with the **live set**: every controller doc with an `ip`, `participating_channels` published ≤ 90 days, and (when present) `controller_health.lastSuccessAt` ≤ 14 days; a dead predecessor doc (no fresh facts) is skipped with `controller_no_facts` and never fired into (the DHCP-reassigned-host hazard in #97). Job ids become `${eventId}_{seq}_{controllerId}`; the session carries `startJobIds[]` and GUARD 0b passes if **any** start reached `dispatched|completed`. Gate inputs (`:387-398`) and `participationForFire` run per controller; the account is armed if ≥ 1 controller passes, the rest skipped with a row. `teardownTeamFires.ts` cancels all. Re-assert (E) and celebration/revert (G) pairs are per controller. The in-flight guard is already per controller. Partial delivery = success for the house, with `controllers_fired/controllers_total` on the scorecard.
- Tests: `plannerHierarchy.test.js` two-controller fake (two starts, two ends, one skipped predecessor); GUARD 0b with id lists; teardown cancels N; hand-off carries per-controller payloads.
- Risk: firing into a stale controller doc with a reassigned IP (mitigated by the freshness rule); doubling bridge traffic per home (bounded, serial).
- Rollback: redeploy prior rev; `startJobIds[]` is additive to `startJobId`.
- Real-game check: a two-controller bench (the spare controller registered beside the bench controller under a test account) reads back the fx on both; a served two-controller customer shows `controllers_fired == controllers_total`.

### 3.7 Steps B, D, I / brief 7 — allowlist rollout and pre-flight

**Pre-flight (server, per allowlisted uid, every planner tick; result in `gameday_server.preflight` and a `preflight_skip` plan-log row with the reason):**

| # | Check | Source | Skip reason |
|---|---|---|---|
| P1 | Bridge paired | `bridge_registry` row with `pairedUid == uid` (`relayEligibility.hasPairedBridge`; never the user doc's `bridge_paired`) | `preflight_no_bridge` |
| P2 | Bridge healthy | `users/{uid}/bridge_status/current` server `updateTime` ≤ 5 min (heartbeat is 30 s) | `preflight_bridge_stale` |
| P3 | Participating channels published | per live controller: `participating_channels` non-empty int array, `participating_channels_at` ≤ 30 days, `_device_ids` non-empty (the brief's "[0,1,2] published" = all buses; a deliberate exclusion is still valid) | `preflight_no_participation` |
| P4 | Ladder asserts true | `base_ladder_asserts_segments === true` (the gate treats absent as advisory; rollout requires true) | `preflight_ladder_unknown` / `_bad` |
| P5 | Gate not blocking | `gameday_gate_blocking == []` | `preflight_gated` |
| P6 | Controller reachable | when the start job is minted (≤ 6 h ahead), write one `getInfo` probe via `probeOneController` with `source: gameday_preflight`; two consecutive failures 5 min apart → cancel the start job (`cancelled_reason: preflight_controller_unreachable`) and set `served:false` for that event so the phone path runs | `preflight_controller_unreachable` |
| P7 | App build ≥ 113 seen (informational) | last `routing_decisions` record `app_version` | `lease_hygiene_unknown` (never a skip) |

Any P1–P6 failure ⇒ `writeJobs = false` for that uid this tick, the row, `gameday_server.served:false` with `preflight.reasons`, stat `preflightSkips` in the tick summary. The app banner shows "Phone" with the reason.

- Scope: new `functions/src/gameDayPreflight.ts` (pure evaluators over snapshots) called from `planGameDayFires.ts` at the `writeJobs` decision (`:402`); `probeControllerHealth.ts` `probeOneController` reused; plan-log row shape; `gameday_server` writer (B). Tests: one unit case per check × pass/fail, tick-driven skip rows, P6 cancel path.
- Risk: P6 cancels a fire for a transient LAN hiccup (two probes mitigate); P2 skips an account whose bridge recovers at kickoff (the app path still runs, as today).
- Rollback: remove uids from the allowlist (config), or `write_jobs:false` (global).

**Rollout (config writes by Tyler, each a console/REST write, never from this session):**
1. **Friendlies, two games:** 3–5 dealer-01 residential accounts that pass P1–P5 on the plan-log dry run (the planner already writes log-only rows for every enabled config, so the first dry run costs nothing), have one controller, and whose dealer can ask them to open the app at home once after the 113 update. Add uids to `uid_allowlist`. Games: 10-11 and 10-18.
2. **Everyone:** set `uid_allowlist: null` (code semantics: "missing or null = armed for everyone"), pre-flight is the gate. After two clean friendly games with E and F deployed.
3. **Celebrations** follow the same two-stage path on `celebration_uid_allowlist` (G).
- Real-game check: per-account success list on the scorecard; zero `preflight_skip` rows for accounts the dealer expected to be served (or a named reason for each).

---

## 4. "Game Day works for everyone" — definition of done

Per game, per served account, measured from the scorecard, with no human action between kickoff and the final:

| Check | Target |
|---|---|
| Start fire | 100% of served + pre-flight-ok accounts `completed`; `fireAt → completedAt` p50 ≤ 10 s, p95 ≤ 70 s (minute cron + bridge); `attempts` p95 ≤ 2; zero `too_late` |
| End fire | `reason: confirmed_final` within 12 min of the ESPN final p95 (two 5-min polls + dispatch); `hard_cap` count = 0 on normally-finished games; restore matches the ladder state for the hour |
| Re-asserts | `planned == completed`; zero `user_override` surprises reported |
| Stale timers / leases | `lease_residue_rows == 0` for every served account after its first LAN open on 113; zero `source: game_day` app commands during the game |
| Celebrations (after G) | `fired / detected ≥ 95%`; detect → completed p95 ≤ 45 s; `reverts_completed == reverts_total`; `revert_failed == 0` |
| Stuck commands | `stuck_executing_count == 0` for the account; fleet-wide zero `executing` older than 3 min |
| App-open requirement | `app_foreground_during_game == false` for at least one served account with start + end completed (proof of unattended); no account *needed* the app |
| Per-account list | every served account appears with start + end completed **or** a named skip reason; no silent absences |

**Scorecard doc** (written by the planner at mint, the dispatcher at reconcile, the poller for celebrations): `gameday_scorecard/{YYYY-MM-DD}/entries/{uid}_{eventId}` with fields `uid, team_slug, sport, game_start, served, preflight_ok, preflight_reasons[], controllers_total, controllers_fired, start{fire_at, dispatched_at, completed_at, latency_ms, attempts, state, outcome}, reasserts{planned, completed, user_override}, end{reason, espn_final_seen_at, fire_at, completed_at, latency_from_final_ms, attempts, state}, celebrations{detected, fired, p50_ms, p95_ms, reverts_total, reverts_completed, revert_failed}, stuck_executing_count, lease_residue_rows, app_foreground_during_game, bridge_fw`.

**The single query** (admin SDK, read-only):
```js
const rows = (await db.collection("gameday_scorecard").doc(dateKey)
  .collection("entries").get()).docs.map(d => d.data());
```
Everything above derives from `rows`. Until the writer ships, the same table is assembled from `fire_jobs` (collection group, `fireAt` range — needs a collection-group single-field index on `fireAt`) joined to `game_day_sessions` and `commands`; the writer exists so that one `get()` replaces four joins. The plan-log `rows` array de-duplicates identical rows and carries no tick timestamp, so it is not a scorecard source.

---

## 5. Marketing and guide claims that are not true for customers today

Truth today for every account except the bench: start/end fire from the phone (foreground) or the solid-colour lease (ON only); celebrations play only while the app is on screen; the lease can turn the house ON with the app closed and never OFF.

| Where | Claim | Not true because | Interim copy (until the named step ships for that account) |
|---|---|---|---|
| `docs/guides-2026-09/01-feature-overview.md:82-85` | "The house turns over on game day on its own … scores land on the house as celebrations" | Phone-side; celebrations app-open | "Game Day puts your team's look up for the game. Today the lights change when the Lumina app is open at home, and score celebrations play while the app is on screen. Server-run Game Day (phone off) is rolling out home by home; your Game Day screen shows which applies to you." — until D (start/end) and G (celebrations) |
| `docs/guides-2026-09/02-homeowner-guide.md:344-345`, `Lumina_Homeowner_Guide.md:410` | "turn Autopilot on … it runs on its own" / "game days handle themselves" | Foreground + lease | "…it runs when the app is open at home. A game you set up at home may still turn the lights on at kickoff with the app closed; they return to normal the next time you open the app at home." — until D + C |
| `docs/guides-2026-09/02-homeowner-guide.md:363-365, 560-562`, `03-commercial-guide.md:171-177` | "Game Day needs the app open … Close it and nothing fires." | Wrong in the other direction: the lease fires ON | Add the lease sentence above; after D: "Homes on server-run Game Day fire with the phone off; your Game Day screen says 'Runs from our servers' when that is you." |
| `docs/Dealer_Installer_Setup_Guide.md:569` | "the Celebration effect that fires when their team scores or wins" | App-open only; sensitivity ignored | "…fires when their team scores, while the customer has the app open on the game. Server-run celebrations are a later rollout." — until G |
| `docs/Dealer_Installer_Setup_Guide.md:580` | "When the game ends, the house reverts on its own." | Only with the app open (or served) | "…reverts on its own while the app stays open; server-run homes revert with the phone off." — until D |
| `docs/sales-mode-guide.md:297` | "automatic game-day lighting … with a celebration effect that fires when their team scores" | Both | "automatic game-day lighting for their teams (server-run rollout in progress), with score celebrations that play while the app is open" — until D + G |
| `docs/guides-2026-09/06-admin-guide.md:134-157` | `write_jobs: false`; "Game Day does not fire unattended" | `write_jobs:true`, bench allowlisted since 09-14 | Replace the table row with the live values and the allowlist semantics; add the pre-flight reasons list — now |
| `lib/features/game_day/game_day_screen.dart:233-236` | "let your lights automatically come alive on game day. Turn on live scoring to celebrate every point" | Both | "Set up your teams and choose a look. For now, keep the app open at home on game day; live scoring celebrates while the app is on screen." — until the C banner replaces it per account |
| `lib/features/game_day/live_scoring_prompt.dart:110-111, 245-246` | "Your lights will celebrate every score" | App-open; sensitivity ignored | "Your lights will celebrate your team's scores while the app is open." — until G (and the sensitivity fix in C) |
| `lib/features/autopilot/base_layer_gate.dart:122-123` | "turns them back off when it ends" | Lease has no OFF row | "turns your lights on for a game; going back to normal needs the app open at home (or server-run Game Day)" — until C + D |
| `lib/features/ai/recurring_sports_autopilot_handler.dart:79-81` | "I'll set your lights for every game automatically." | Foreground | "I'll put your lights on for every game while the app is open at home." — until D |
| `lib/features/game_day/gate_status_banner.dart:91-92` | "Game Day is ready / Your lights will fire for upcoming games." (shown to gate-armed, non-allowlisted accounts) | Speaks for a server path that will not fire | "Game Day is ready. Lights fire from this phone when the app is open at home." — replaced by the three-state banner in C |
| `lib/features/site/edit_profile_screen.dart:1473` | "Lumina will automatically schedule … team game days" | Schedules rows, firing is phone-side | "Lumina will add your team's game days to the calendar" — until D |
| `lib/services/notifications_service.dart:290-291` | "Game Day mode activating at …" | `showGameDayAlert` has no callers | Delete or wire to `next_fire` in C |

---

## 6. Timelines (solo developer)

NFL Sundays: 10-04, 10-11, 10-18, 10-25, 11-01, 11-08. Thursday games 10-08, 10-15, … are bench rehearsal slots.

**The next NFL Sunday (10-04) is not a safe customer target.** It is in three days, a live test is running tonight, no code can be built, tested and deployed with a game-day soak in that window, and the five customers' lease path is already arming. 10-04 is the free dry run: the planner already writes log-only rows for every enabled config, so Monday's read of `gameday_plan_log` shows exactly which customer accounts would have passed and what the server would have fired. **Customers get server-fired start/end on 10-11** on the minimum path below.

### Two weeks (10-02 → 10-15)

| When | What | Track |
|---|---|---|
| Fri 10-02 | Record tonight's bench scorecard by hand (the PIT@CLE plan's table). Re-enable the bench Chiefs config before Sun 08:55 CDT (Tyler). Read-only dry run of pre-flight P1–P5 for the five 10-04 accounts from existing docs. | ops |
| Sun 10-04 | Bench server fire (KC@LV). Customers as today. Afternoon read of the plan log for every enabled config. | observe |
| Mon 10-05 → Wed 10-07 | **Step A** (A1 sweeper + age cap, A2 retries) + **Step B** (pre-flight, `gameday_server`, scorecard writer, `on_time_override`, ledger rows). `npm run build && npm test` (fixes the 17 stale `gameDayGate` tests by rebuilding `lib/`; make `test` build first). Rules deny-list diff through the gate. Deploy Wed evening: indexes → functions (`planGameDayFires, dispatchFireJobs, sweepExpiredCommands, probeControllerHealth`) with `functions/.env` from the main checkout and `--project`. | functions |
| Thu 10-08 | TNF bench rehearsal on the new revisions; verify a forced stuck-executing doc is swept and a retry completes (bench bridge only). | bench |
| Mon 10-05 → Fri 10-09 (interleaved) | **Step C** app build (served reader, lease skip + sweep retraction, engine observe mode, three-state banner, sensitivity fix, copy table rows). Gate under both SDKs with `flutter clean` first. Tag Fri; TestFlight Sat. Build number: next after 112 (113 may be claimed by the roofline branch; take the next free). | app |
| Fri 10-09 | Dry-run pre-flight for candidate friendlies from the plan log; pick 3–5 that pass P1–P5. Dealer asks them to update and open the app at home once. | ops |
| **Sun 10-11** | **Friendlies allowlisted** (config write by Tyler Sat night after the dry run). First customer server fires. Evening: scorecard. | rollout |
| Mon 10-12 → Wed 10-15 | Fix anything the scorecard shows. Build **Step E** (re-assert + ladder-aware restore) behind `reassert_enabled:false`; deploy Wed. | functions |

**Minimum viable path to 10-11:** A + B deployed (Wed 10-07) + allowlist. C is strongly preferred but not required for 10-11: without it, friendlies on 112 see the same-minute overlap and the engine's OFF-then-base at the end, both disclosed to the dealer.

**Can safely wait past 10-15:** E (base suppression — visible but harmless mid-game stomp), F (#97 — exclude multi-controller homes from the friendly set), G (celebrations stay phone-side), H (firmware).

### Six weeks (10-02 → 11-12)

| Week | Server / app | Rollout | Firmware (parallel, never gating) |
|---|---|---|---|
| 1 (10-02–10-08) | A + B deployed; C built | 10-04 bench; dry runs | Confirm a spare bridge; T4j (NVS across partition change) on the bench |
| 2 (10-09–10-15) | C tagged; E built + deployed (flag off) | **10-11 friendlies game 1** | T1 watchdog + T2 heartbeat bench tests |
| 3 (10-16–10-22) | `reassert_enabled:true` for friendlies; **F** (#97) built + deployed; G design review | **10-18 friendlies game 2** (on 113; lease retraction verified via `lease_residue_rows`) | Home bridge visit + 72 h soak + first OTA |
| 4 (10-23–10-29) | G built (poller, events, chained jobs, watchdog, kill switch); app half of G in the next build | **10-25 everyone** for start/end (`uid_allowlist: null`), pre-flight as gate | Beta customer visit (7-day soak) |
| 5 (10-30–11-05) | G bench on TNF 10-29 / Sun 11-01 with `celebration_uid_allowlist` = bench | 11-01 everyone (start/end) continues; scorecard review | Dealer-batched visits begin |
| 6 (11-06–11-12) | G fixes; copy rows for celebrations | **11-08 celebrations for friendlies**; everyone for celebrations the week after if clean | Visits continue; promote OTA `beta → stable` after ≥ 3 fielded 1.3.x bridges |

---

## 7. Decisions this plan makes for you (confirm or override)

1. D1 heartbeat every tick for served accounts; stale > 30 min = phone mode (never dark).
2. D2 per-team served list.
3. D3 observe mode for served teams until G; then celebrations stand down too.
4. D4 retract leases on the next LAN sweep; accept the one-night overlap on old builds.
5. D5 keep calendar rows.
6. Policy B holds through the base OFF boundary and restores OFF afterwards; re-assert is guarded by "the user touched the lights".
7. Retry budgets: start until min(lead, kickoff + 15 min); end 15 min; re-assert 5 min; revert 5 min; celebrations never.
8. Celebrations: user's team scores + win only; one-stage effect for the app's total hold; always revert; ≥ 20 s between celebrations; 12 per game cap.
9. Pre-flight requires `base_ladder_asserts_segments === true` (stricter than the gate).
10. #97 "live set" = fresh participation facts + ip (+ health when present); partial delivery counts as success.
11. The firmware program never gates the Game Day rollout.
12. "Everyone" = `uid_allowlist: null` with pre-flight as the gate, not a second allowlist.
