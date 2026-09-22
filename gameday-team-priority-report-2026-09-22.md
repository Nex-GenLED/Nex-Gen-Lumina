# Game Day team priority — implementation report

Date: 2026-09-22 · Base: `origin/release/store-submission-consolidated` @ `4cd3413` (confirmed by `ls-remote` at start and again before the merge) · Feature branch `feat/gameday-team-priority-hierarchy` @ `40100cb` · Merge commit **`7886576`** · Audit this implements: `audit/gameday-game-selection-2026-09-21` @ `5af8303`.

Server planner untouched. `config/gameday_planner` and its uid allow-list were not read for writing, not modified, and no Cloud Function changed.

---

## What changed, per consumer

| # | Consumer | Before | After |
|---|---|---|---|
| 1 | **Data** — `/users/{uid}` | one ordered array, `sports_team_priority`, display names, read by nothing live | adds `game_day_team_priority`, ordered **slugs**. Both written together from one derivation on every reorder. Names array shape unchanged. |
| 2 | **Arbiter** — `game_day_priority_resolver.dart` | pure, correct, dead. One caller (the compiled-off worker), no test, and `indexOf(slug)` against a names list so it ranked nobody | fed slugs; gained **rule 5, hand-off on end** (`handoffWinner`); 39 unit tests covering ranking, ties, the empty list, same-game and hand-off |
| 3 | **Foreground activation** — `evaluateConfigs` | walked Firestore document-id order, every team activated independently, last writer won | walks the **hierarchy**; resolves before activating; handles all three verdicts. A deferred team keeps its session and phase tracking but applies nothing |
| 4 | **End of game** — `_updateActiveSession` postGame | called `onResumeNormalSchedule` → `togglePower(false)` unconditionally | hands off to the highest-priority team still playing; resumes **only** when none remains |
| 5 | **Cancel** — `cancelSession` | same unconditional power-off; synchronous | async; hands off when the cancelled team held the lights; a deferred cancel touches nothing |
| 6 | **Calendar populate** — `_doPopulateCalendarsInner` | iterated doc-id order, so the last-iterated team won the one lease a shared night has | iterates **reverse priority**, so the #1 team writes last and owns the lease |
| 7 | **Celebrations** — `computeLiveCelebrationTeams` | every `liveGame` team celebrated, interleaved | gated on `ownsLights`. Only the current team's alerts fire; the incoming team's start at hand-off |
| 8 | **UI** | one reorder control, in Edit Profile only, three taps from the feature it governs | `widgets/team_priority_list.dart`, rendered in **both** Edit Profile and Game Day. Game Day writes immediately; Edit Profile folds into its Save. Both write both fields |
| 9 | **Dead code** | `detectConflicts` + `checkConflicts` | **deleted** — see below |

### Reconciling with `computeEnabledConfigsForTeam`

The splice function still puts a just-toggled team **last**, and `game_day_multi_team_test.dart` still pins that. It answers "which teams are in this populate pass", including beating Firestore stream lag. Ordering for lease primacy is a *different* question, asked later at the write by `orderConfigsForCalendarWrite`. Keeping them in separate functions is what lets both rules stay true; the tests for each are independent and both pass unmodified.

### Two defects found while building this

Both were caught by the new tests, not by inspection, and both are fixed in the same commit.

1. **Same-tick flash.** Resolution is per-config. With two teams whose windows open on the same pass, the lower-priority one resolved first against an empty field, activated, and **put its design on the wire**, and only then was preempted. End state right, house visibly wrong for a moment, two controller writes where one was needed. Fixed by evaluating in hierarchy order (`orderConfigsByPriority`).
2. **Two owners at once.** Rule 3 breaks an equal-priority tie on "who activated first", using `DateTime.now()`. At microsecond resolution two same-pass activations can produce *identical* stamps, neither is "after" the other, both resolve to activate, and two teams own the house — which would have broken celebration gating and hand-off. Fixed with strictly-monotonic activation stamps plus explicit enforcement of the single-owner invariant on activate/preempt.

---

## Migration

**Heal-on-read, per user, no bulk backfill.** No production document was written during this session. The heal runs client-side when a signed-in user opens Game Day, derives the slug order from what their own account already carries, and writes it back to **their own** `/users/{uid}` document only.

Rules: keep stored slugs that still have a config → append profile names translated through `kTeamColors` (case-insensitive, the same normalisation the add/remove paths already use) → append configs missing from the list in document-id order. Entries matching no catalogue team, and slugs with no config, are dropped. Idempotent, so the write happens once and converges.

Simulated against the read-only production snapshot taken for the audit (20 Game Day accounts, 51 configs):

| Outcome | Accounts |
|---|---|
| Will get the field written on first Game Day open | **20 of 20** |
| Of those, single-team — write happens, no behaviour change | 10 |
| Multi-team where the healed order **differs from the old doc-id order**, i.e. the winner actually changes | **9** |
| Had a list entry dropped (legacy free text, no config) | 1 |
| Had configs appended because the profile array had drifted | 6 |

The nine where the winner changes, healed order versus what the loop used to obey:

| Account | Enabled teams | Healed #1 | Old #1 (doc-id) |
|---|---|---|---|
| `RGPinapl…` | 7 | `nfl_chiefs` | `mlb_royals` |
| `j8eXTfcs…` | 2 | `mlb_royals` | `mlb_royals` (order below it changes) |
| `NmDukd5r…` | 2 | `mlb_royals` | `mlb_royals` (order below it changes) |
| `reviewer…` | 2 | `nfl_chiefs` | `mlb_royals` |
| `Pqptfawp…` | 1 | `mlb_royals` | `fifa_mexico` |
| `r0iBwg8b…` | 0 | `nfl_chiefs` | `mlb_royals` |
| `IARQUnn9…` | 0 | `nfl_seahawks` | `mlb_mariners` |
| `YcSGiwes…` | 0 | `nhl_blues` | `mls_sporting_kc` |
| `CeDVdKfK…` | 0 | `ncaa_central_michigan` | (same #1, #2/#3 swap) |

The reviewer account is the sharpest case: it has Chiefs and Royals both enabled, ranks Chiefs first, and the loop ran Royals first. That is the production shape the bench reproduces.

---

## Gate

| Check | Baseline | After | Verdict |
|---|---|---|---|
| `flutter analyze` | 382 (0 errors / 12 warnings / 370 infos) | **382** | **No deviation.** Line-by-line diff of the normalised issue set is empty — not merely the same count |
| `flutter test` | 3357 passed / 34 skipped / 0 failed | **3423 passed / 34 skipped / 0 failed** | +66, exactly the new tests. **Skips unchanged at 34**, so the hardware-skip invariant holds |

One transient deviation during development, resolved: moving the reorder list out of Edit Profile left `sports_teams.dart` unused there, producing a 13th warning. The dead import was removed; the count returned to 382.

The bench file lives under `evidence/`, not `test/`, deliberately — it writes to real hardware, and the suite counts must stay comparable. It carries a scoped `invalid_use_of_visible_for_testing_member` ignore because the analyzer scopes that annotation to `test/`.

---

## Bench — 192.168.1.150

Run twice, results identical. Controller WLED 0.15.1, 290 px RGBW, `ws:0` and `live:false` at snapshot (no other client or bench session attached).

**Real:** `GameDayAutopilotService` exactly as shipped, its arbitration, design selection and payload builder; the HTTP write to the controller; the readback; and `computeLiveCelebrationTeams`, the real derivation, for the alert-gating assertions.
**Simulated:** the two ESPN readers. A real Royals-and-Chiefs overlap cannot be waited for, so kick-off times and final whistles are injected, and the 30-minute post-game countdown is fast-forwarded through the service's own test seam.
**Not covered:** multi-channel fan-out. The payload lands on segment 0 and the readback reads segment 0. Channel participation is untouched by this change. No celebration animation was fired at the LEDs; alert gating is asserted through the real derivation, not observed as a flash.

| Case | Observed on hardware | Result |
|---|---|---|
| **B1** two teams overlapping, Chiefs #1 | wire `[227, 24, 55]` = Chiefs red; owner `nfl_chiefs`; `mlb_royals` deferred; unchanged across two further ticks | PASS |
| **B2** hierarchy reversed, identical game times | wire `[0, 70, 135]` = Royals blue; owner `mlb_royals`; `nfl_chiefs` deferred | PASS — priority decides, not slug order |
| **B3** lower-priority game ends first | `resumeCalls=0`, `on=true`, wire still Chiefs red; celebrating `{nfl_chiefs}` throughout | PASS — the dark-mid-game bug is gone |
| **B4** winner ends, other still live | `resumeCalls=0`, `on=true`, wire `[0, 70, 135]`, owner `mlb_royals`, celebrating `{mlb_royals}` | PASS — hand-off applies the survivor's design and moves the alerts |
| **B5** last game ends | `resumeCalls=1` | PASS — resuming is still correct when nothing remains |

Restore, both runs:

```
state diffs: NONE
presets.json unchanged: true    (sha256 8c53e9fe88f65c3c…)
cfg.json     unchanged: true    (sha256 e1feef2eb74dc2b3…)
uptime 13093s → 13097s  (run 1)   no reboot
uptime 13115s → 13119s  (run 2)   no reboot
```

No `psave`, no `pdel`, no `/json/cfg` POST — the bench controller's known presets.json flash corruption and the gamma-wipe hazard were both avoided by construction and verified unchanged by hash.

Logs: `evidence/gameday-team-priority-2026-09-22/bench_run{1,2}.txt` (local paths sanitised — this repository is public).

---

## `detectConflicts` — deleted

Deleted, along with its only wrapper `GameDayAutopilotNotifier.checkConflicts()`.

It paired teams whose next games fell within four hours and returned the pairs. It had **no caller anywhere in `lib/` or `test/`**, its four-hour window bore no relationship to any arbitration the system performs, and it answered — badly, and only pairwise — the question `GameDayPriorityResolver` now answers properly and per event. Leaving a second, overlapping, untested answer sitting beside a live arbiter is how the wrong one gets wired up six months from now. A comment stands where it was, saying what it did and why it went.

---

## Things the audit did not have

1. **Deferral has to be a session, not an absence.** The brief specified defer as "no session, no apply". That cannot work: the only way a team is ever picked up is `hasGameSoon`, which is false once its game has already started — so a team deferred at 12:40 for a 1 pm start could never take over at 3 pm when the winner finished. It would simply never light. A deferred team therefore keeps a real session and runs the full phase machine; what deferral suppresses is the two things that reach the user, the applied design and the celebrations. Step 7's "deferred teams keep their session, they still hand off" is the reading the code implements.
2. **`postGame` counts as a hand-off candidate.** A team whose game has ended is still inside its own 30-minute wind-down, which is a deliberate part of the show. Excluding it would cut a wind-down short.
3. **The audit's "one new field" recommendation has a second beneficiary.** `setAccountProfile.ts` `mapTeams` already expects `sports_team_priority` to hold slugs and would skip every production entry on a commercial conversion. `game_day_team_priority` is the field it actually wanted. Not wired this pass — commercial conversion is out of scope — but the data now exists for it.
4. **Two same-tick defects** that only a real arbitration test surfaces: the wrong-team flash and the two-owners tie. Both described above.

---

## Landing

The merge commit is **`7886576`**, parents `4cd3413` + `40100cb`, created with `--no-ff` on top of origin's real consolidated tip.

**The `release/store-submission-consolidated` branch pointer was NOT moved.** The local ref is stale at `7c55c8e` and is checked out in another session's worktree (`…/69541678-…/scratchpad/wt-merge`); moving it would have desynced that session's working tree. The merge therefore sits on the local ref `merge/gameday-team-priority-consolidated`, which is a strict fast-forward from `origin/release/store-submission-consolidated`. Nothing was pushed. Version not bumped, as instructed.

To land it, from a checkout that owns the branch:

```
git fetch origin
git checkout release/store-submission-consolidated
git reset --hard origin/release/store-submission-consolidated   # clears the stale 7c55c8e
git merge --ff-only merge/gameday-team-priority-consolidated
```

## Still owed

- A real two-team overlap observed end to end against live ESPN, rather than injected game times.
- Multi-channel fan-out for the hand-off apply was not exercised; it is unchanged by this work but has never been bench-verified on the Game Day path specifically (the audit noted the cold-participation-cache seg-0 behaviour as pre-existing).
- The server planner still has no arbitration. It is allow-listed to one account with one team, so multi-team is not reachable there today, but the client half shipping first is the deploy ordering this repo's own notes prescribe.
