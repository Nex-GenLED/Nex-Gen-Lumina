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
