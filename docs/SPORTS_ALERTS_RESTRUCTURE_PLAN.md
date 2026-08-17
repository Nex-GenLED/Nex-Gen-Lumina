# Sports-Alerts Restructure — plan of record

**Filed 2026-08-15.** Decide-and-file only; no implementation in this pass.
Sources: the four-decision elicitation (A4/A3/C11/C10), the in-flight branch
`feat/gameday-unified-monitoring`, and an independent source trace of the
celebration path. Related: **#79** (celebrations have never fired — branch),
**#83** (#67 partition gap), **#66**, **#67**, **#68**, **#76**, **P1-44**.

---

## 1 — Inventory: what actually exists

Branch **`feat/gameday-unified-monitoring`**, head **`47a143b`**
(`c7d9a9e` + `47a143b`), forked at **`25a0a29`** — *before* the #76 arc, 18 main
commits back. Worktree: `C:/Flutter Projects/lumina-gameday`. 12 files,
+1089/−138.

**Mergeable against current main: YES.** `git merge-tree --write-tree` returns a
tree with no conflicts (exit 0). The only file both sides touched since the fork
is `docs/BUGS_AND_DEBT.md`, and the two edits sit in different regions.

| Decision | Verdict | Where |
|---|---|---|
| **A4** — orphaned alert teams auto-create MONITORING-ONLY configs; absent reads as monitored; upgrade is explicit | **IMPLEMENTED-ON-BRANCH**, with a **different and better field** | `lib/features/autopilot/unified_monitoring.dart` (new, 168 ln) + `game_day_autopilot_config.dart` |
| **A3** — alerts screen demoted to tuning-only; the second authority dies; sensitivity moves onto `game_day_autopilot` | **PARTIAL** — the *authority* half is implemented; the *screen* half is ABSENT | arming moved to `shouldPollScores`; `sports_background_service.dart` rewired. `lib/services/sports_alert_service.dart` **untouched** |
| **C11** — delete dead `triggerScoreCelebration` + its SYNC-3 test; repoint QA button; correct the ledger | **IMPLEMENTED-ON-BRANCH (partial)** | removed from `game_day_setup_screen.dart:909`; SYNC-3 group removed from `fanout_trigger_flag_gate_test.dart` (−70). **`sports_alert_service.dart:125` still defines its own `triggerScoreCelebration`** |
| **C10** — `start_time_passed` gains a legible log row; edit, do not deploy | **IMPLEMENTED-ON-BRANCH, NOT DEPLOYED** | `planGameDayFires.ts:604-623` |

### Notes that change the shape of the work

- **A4 landed as `live_scoring_enabled`, not a `monitored` flag.** Deliberately
  client-only and deliberately separate from `enabled`, which the **server**
  planner queries at `planGameDayFires.ts:342`. A migrated alerts-only team is
  therefore monitored while staying invisible to the planner, so it cannot
  produce an unasked-for first-pitch fire. This is a stronger design than
  "monitored-vs-runs-the-show" as elicited — it makes the dangerous state
  unrepresentable rather than merely defaulted-off. **Adopt it; retire the
  `monitored` wording.**
- **C11 is half-done.** The dead *caller* is gone; the dead *service method*
  survives in `sports_alert_service.dart`. Finish it in the same pass or the
  next audit re-finds it.
- **A3's screen work is the largest remaining piece** and is pure client.

---

## 2 — The implementation session

### Scope, in dependency order

| # | Work | Layer | Pri |
|---|---|---|---|
| 1 | **Merge `feat/gameday-unified-monitoring`** into main and re-run the suite | — | **P1** |
| 2 | Finish **C11**: delete `SportsAlertService.triggerScoreCelebration`; repoint the QA "Test Score Trigger" at `gameDayWorker.onScoreAlertEvent` | client | **P1** |
| 3 | **A3 screen half**: strip team add/remove and the Enabled switch from the alerts screen; leave sensitivity, backed by `game_day_autopilot` | client | **P1** |
| 4 | **#83**: assert the #67 full partition on the celebration path — preferably by lifting `partitionBroadcastPayload` above the `groupId` branch so every path partitions | **server** | **P2** |
| 5 | **C10 deploy**: ship the `start_time_passed` row | **server** | **P2** |
| 6 | Backfill/migration for orphaned alert teams → monitoring-only configs (A4 runtime half) | client | **P2** |
| 7 | Re-verify on hardware: a real scoring event reaching a controller, first time ever | bench | **P1** |

### Client/server split and deploy ordering (the +74 rule)

Server items are **4** and **5** only; both are in `functions/`, neither touches
rules. Everything else is client.

**The +74 rule applies in its literal form:** before any deploy, assert the
deployed SHA is an ancestor of `main`. The +74 join regression came from
deploying a server half from an unmerged branch and stranding the client.
`planGameDayFires.ts` on this branch is **not on main yet**, so:

1. **Merge first** (item 1). Do not deploy C10 from the branch.
2. Then deploy items 4 + 5 **together**, from a merged main, in one targeted
   deploy.
3. Ship the client in the next build.

Ordering is safe in both directions here — the C10 row is observability-only and
the #83 partition is additive — so a client/server version skew degrades to
"less legible" rather than "broken". That is worth preserving deliberately, not
by luck: **neither server item may grow a client dependency.**

### Verification gate

The suite is the floor, not the proof. **#79's evidence standard was
fleet-wide command-source counts** — zero `game_day`-sourced commands, ever.
That query is the acceptance test: after the merge and a real scoring event,
`source: 'game_day'` must appear. Until it does, celebrations remain unproven
regardless of green tests. A unit test cannot distinguish "fires correctly" from
"never armed", which is precisely how this survived to now.

---

## 3 — Contract debt carried into the session

- **#83** — celebrations do not assert the #67 partition (above).
- **Legible skips** — the four bare returns in `onScoreAlertEvent` and the silent
  `active.isEmpty` poller gate. Covered by #79's in-flight fix; verify it landed
  rather than re-deriving it.
- **#76 geometry** — the celebration path is **already compliant**. Record it so
  the next audit does not re-open it: the flash emits design fields only, and
  `applyChannelFilter`'s default empty `channels` list means no `start`/`stop` is
  ever written.

---

## 4 — The two silent games, gates named (added 2026-08-17, live data)

Re-verified against a main that had moved to `b510f22`: the branch head is still
**`47a143b`** and it still **merges clean**. C10's row is still branch-only and was
deliberately not duplicated onto main — main has not touched
`planGameDayFires.ts` since the fork, so a copy there would manufacture a conflict
in that exact hunk. **C10 exists; it is one merge away, not one edit away.**

### The games had DIFFERENT gates, and neither was the celebration code

| game | first unsatisfied condition | legible? |
|---|---|---|
| **Dodgers 08-13** (~298) | `start_time_passed` — config created after its own fire time, so no show, so no session | **NO** — counter only (C10) |
| **Royals 08-16** (301) | `daylight_game` — Tyler's `skip_day_games=true`, 15:07 CDT first pitch | **NO** — counter only (**#90**) |
| **Twins 08-16** (301, the cycle that DID run) | `score_celebration_enabled` **absent from the config** → mirror reads `?? false` | **NO** — bare `return` at `:166` |

**The unifying finding: in neither silent game did execution ever reach
`onScoreAlertEvent`.** Both were stopped upstream, in the planner, by a skip that
wrote no row. The celebration path was never the thing that failed — it was never
invoked, and nothing said so.

**And the one game that DID run proves blocker 3 in production.** Tyler's
`mlb_twins` config carries only `{enabled, espn_team_id, sport, updated_at}` —
**no `score_celebration_enabled`**. The Firestore model defaults that field `true`
while `game_day_background_persistence.dart:147` reads `?? false`, and the worker
reads the pessimistic one. So even with a live session and a running poller, the
Twins celebration would have bare-returned. The branch's #79 predicted this from
source; the live config now confirms it.

### A4/A3 confirmed ABSENT in production data

Live config keys on both accounts contain **no** `monitored`, `monitoring_only`,
`live_scoring_enabled`, or any `sensitivity` field. The inventory's
IMPLEMENTED-ON-BRANCH / ABSENT-ON-MAIN split is confirmed from the data side, not
just the source side.

### What this changes in the plan

- **Item 5 (C10 deploy) grows to include #90.** Shipping one silent-skip row and
  leaving its twin is how this recurs.
- **Add: an acceptance query, not just a test.** "Celebrations work" must be
  demonstrated by a `source:'game_day'` command appearing after a scoring event in a
  **night** game on an account whose config **has** `score_celebration_enabled`.
  Tyler's Royals config qualifies; his Twins config does not.
- **Add (P2): backfill `score_celebration_enabled` on stub configs**, or make the
  two layers agree on `true`. Today a config created by the shorter write path is
  silently celebration-disabled forever.
