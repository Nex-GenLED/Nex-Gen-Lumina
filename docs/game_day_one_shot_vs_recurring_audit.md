# Game Day Feature Audit — One-Shot vs Recurring

**Date:** 2026-05-08
**Branch:** `submission/app-store-v1`
**Status:** READ-ONLY scoping — no implementation
**Context:** Item #51 follow-up. Steve at Blue Line Bar typed *"give me a royals baseball design for the game today, and then after the game ends resume normal blue lighting."* The previous audit recommended redirecting users to Game Day Autopilot for post-game scenarios. This audit checks whether that recommendation matches Steve's one-shot intent.

## Executive summary

**Categorization: D — AMBIGUOUS / OVERLAP**, with a clear shape:

- **One feature surface (the Game Day Screen)** with **two action paths** sitting side by side on the same Team Card:
  1. **"Light Up Now" button** ([game_day_screen.dart:343](lib/features/game_day/game_day_screen.dart#L343)) — true one-shot manual apply, no scheduling, no post-event handling.
  2. **"Autopilot" toggle** ([game_day_screen.dart:322-330](lib/features/game_day/game_day_screen.dart#L322)) — heavyweight recurring per-team commitment, fires for ALL future games via ESPN polling.
- A user must first **add the team to "My Teams"** (which Game Day Autopilot Config implicitly creates) before either path is reachable. There is no path that operates on a team the user hasn't pre-registered.
- **Lumina chat has zero awareness of either path.** Searching `lib/lumina_ai/` and `lib/features/ai/` for `gameDay`, `game_day`, `GameDay`, `GAME_DAY`, or `autopilot` yields one unrelated `autopilot` reference (`importSmartSchedule` for season-fill, not Game Day).
- **Critical mismatch with Steve's prompt:** Game Day Autopilot's post-game callback (`onResumeNormalSchedule` at [game_day_autopilot_providers.dart:70-79](lib/features/autopilot/game_day_autopilot_providers.dart#L70)) **turns lights OFF**, not "resume normal blue lighting." So even redirecting Steve to autopilot would not satisfy his "resume blue after" ask.

This is **D, not A**. There are not two distinct features; there is one feature with two modes plus a third missing mode (one-shot with post-event revert-to-baseline) that Steve is implicitly asking for.

---

## 1 — All Game Day-related features

### Residential / Personal

#### 1.1 Game Day Screen — feature surface
**File:** [lib/features/game_day/game_day_screen.dart](lib/features/game_day/game_day_screen.dart)
**Route:** `/dashboard/game-day` (registered in `app_router.dart`)
**One-line:** Shows "My Teams" cards; each card has both a "Light Up Now" button and an "Autopilot" toggle.
**User-facing entry point:** A separate Game Day tab/destination on the dashboard nav (not exposed via Lumina chat).
**Per-team data model:** [`GameDayAutopilotConfig`](lib/features/autopilot/game_day_autopilot_config.dart#L71) at `/users/{uid}/game_day_autopilot/{teamSlug}` — stored even for teams the user only ever uses one-shot.

#### 1.2 "Light Up Now" — one-shot manual apply
**File:** [game_day_screen.dart:388-460](lib/features/game_day/game_day_screen.dart#L388)
**One-line:** Builds a WLED payload from team colors + chosen design and POSTs it to the controller immediately.
**Recurring? No** — single fire. Comment at [line 338](lib/features/game_day/game_day_screen.dart#L338) literally says *"Light Up Now (immediate, manual one-off)"*.
**How activated:** Tap the "Light Up Now" FilledButton on a team card.
**Commitment:** None. Lights stay on the team design until manually changed or scheduled override fires.
**Post-event handling:** **None.** No timer, no revert-to-baseline. The lights stay on team colors indefinitely. Sets `activePresetLabelProvider` to `'${shortTeamName} Game Day'` ([line 438](lib/features/game_day/game_day_screen.dart#L438)).
**Prerequisite:** Team must already be in "My Teams" (must have a `GameDayAutopilotConfig` in Firestore). User can't one-shot a team they haven't pre-registered.

#### 1.3 Game Day Autopilot — recurring per-team subscription
**Service:** [lib/features/autopilot/game_day_autopilot_service.dart:1-100](lib/features/autopilot/game_day_autopilot_service.dart#L1)
**Toggle:** [game_day_autopilot_providers.dart:365-433](lib/features/autopilot/game_day_autopilot_providers.dart#L365) (`toggleAutopilot`).
**One-line:** Per-team ESPN-driven phase machine: `idle → preGame → liveGame → postGame → completed`. Fires for every future game of the team automatically.
**Recurring? Yes** — strongly. Toggling on means:
1. Sets `enabled: true` on the team's Firestore config.
2. **Adds the team to user profile** `sports_team_priority` + `sports_teams` lists ([providers:418](lib/features/autopilot/game_day_autopilot_providers.dart#L418)).
3. **Populates the calendar** with `CalendarEntry` records for **all upcoming games** ([providers:432](lib/features/autopilot/game_day_autopilot_providers.dart#L432) — `_populateCalendarInBackground(force: true)`).
4. Background worker polls ESPN to detect game start (30 min before), live status, and game end.
5. Fires for **every future game** until the toggle is turned off.
**How activated:** Toggle on the team card in Game Day screen.
**Commitment:** Heavy. For an MLB team, that's ~162 regular-season games + postseason. For NFL, ~17. The user's calendar fills with autopilot entries.
**Post-event handling:** When ESPN reports `final_` (or estimated-duration fallback fires), runs a 30-min countdown, then invokes `onResumeNormalSchedule` callback. **The callback turns lights OFF** ([providers:70-79](lib/features/autopilot/game_day_autopilot_providers.dart#L70)):
```dart
svc.onResumeNormalSchedule = () {
  debugPrint('[GameDayAutopilot] Resuming normal schedule / turning off');
  // Turn off as default post-game behavior. The autopilot scheduler
  // will pick up the next scheduled event on its next cycle.
  try {
    ref.read(wledStateProvider.notifier).togglePower(false);
  } catch (e) { ... }
};
```
The next scheduled `ScheduleItem` or autopilot event picks up on its own cycle. There is no "revert to a specific user-supplied baseline."

#### 1.4 "Crew" / Game Day Group sync
**Files:** [lib/features/game_day/game_day_crew_models.dart](lib/features/game_day/game_day_crew_models.dart), [lib/features/neighborhood/widgets/game_day_setup_screen.dart](lib/features/neighborhood/widgets/game_day_setup_screen.dart), [lib/features/neighborhood/models/group_game_day_autopilot.dart](lib/features/neighborhood/models/group_game_day_autopilot.dart).
**One-line:** Synchronized neighborhood/group Game Day across multiple homes (host + members).
**Recurring? Yes** — extends the autopilot path; not a one-shot.
**Not relevant to Steve** (commercial bar, single location).

### Commercial

#### 1.5 Commercial Game Day Service
**File:** [lib/services/commercial/game_day_service.dart](lib/services/commercial/game_day_service.dart)
**One-line:** Polls ESPN per commercial team profile; fires `onGameDayStart` / `onGameDayEnd` callbacks that switch the [`CommercialSchedule`](lib/screens/commercial/schedule/CommercialScheduleScreen.dart) to a "Game Day" day-part.
**Recurring? Yes.** Polls continuously, fires for every game of every priority-rank-1 team in the location's `CommercialTeamsConfig`.
**Activation:** Configured in commercial onboarding (team profile registration). Not user-toggled per-event.
**Post-event handling:** `onGameDayEnd` reverts to the location's standard day-part (e.g. evening/late-night). This is closer to "revert to baseline" than the residential autopilot's "turn off" — because commercial schedules have a baseline day-part.
**Relevant to Steve?** Possibly — Blue Line Bar is commercial. But this service is configured at install time, runs continuously, and isn't user-triggered from chat.

### Schedule / Calendar

#### 1.6 `CalendarEntry.sourceTag = 'game_day'`
**File:** [lib/features/schedule/calendar_entry.dart:18](lib/features/schedule/calendar_entry.dart#L18)
**One-line:** Provenance label on calendar entries written by Game Day Autopilot. Date-anchored (`dateKey: 'YYYY-MM-DD'`). **Not** user-creatable as a one-shot path; it's a tag the autopilot service writes.
**Recurring? Indirect.** Each individual entry is one date, but they're written in bulk by the autopilot's `_populateCalendarInBackground`. No user-facing UI to author a single `sourceTag='game_day'` entry directly. The calendar editor doesn't expose this tag.

#### 1.7 Schedule priority resolver — Game Day rank
**File:** [lib/features/schedule/schedule_priority_resolver.dart:214-289](lib/features/schedule/schedule_priority_resolver.dart#L214)
**One-line:** Tiers Game Day individual (priority 3) and Game Day Group (priority 4) above autopilot baselines but below user-set entries. Resolves overlaps when multiple sources write to the same date.
**Not a feature** — a coordination layer.

### AI / chat

#### 1.8 `pattern_label_resolver.dart` — `"KC Royals Game Night"` example
**File:** [lib/features/ai/pattern_label_resolver.dart:9](lib/features/ai/pattern_label_resolver.dart#L9)
**One-line:** Builds a display label like *"KC Royals Game Night"* from AI prompts. **Pure label resolution** — no scheduling, no team registration, no Game Day Autopilot interaction.
**Relevant?** Marginally. Tells you the AI prompt mentions sports terms, but no behavior is wired.

---

## 2 — Activation flows in detail

### 2.1 Game Day Autopilot enable flow

User journey:
1. Navigate to Game Day screen (separate destination).
2. If team isn't in "My Teams" yet, tap "Add a Team", search/pick from ~30 team color presets in `kTeamColors`.
3. Tap the "Autopilot" toggle on the new team card.
4. `_toggleAutopilot` calls `gameDayAutopilotNotifierProvider.notifier.toggleAutopilot(teamSlug, enabled: true)`.
5. Firestore writes:
   - `/users/{uid}/game_day_autopilot/{teamSlug}` with `enabled: true` and full config (colors, ESPN team ID, sport, brightness, design choice).
   - User profile `sports_team_priority` + `sports_teams` lists get the team appended.
6. Background work:
   - `_populateCalendarInBackground(teamSlug, force: true)` fetches the team's upcoming game schedule from ESPN and writes a `CalendarEntry` per game with `sourceTag='game_day'`.
   - Periodic worker (`game_day_autopilot_background_worker.dart`) starts polling for each game.

**Commitment:** All future games of the team will fire pre-game (30 min before start), keep lights on through live game, score celebrations if enabled, then 30-min post-game countdown → **lights off**.

**Disable flow:** Toggle off → service `cancelSession(teamSlug)` + Firestore `enabled: false`. Calendar entries written previously **remain** (per the priority-resolver code path, they're soft-resolved at render time). The team remains in "My Teams."

### 2.2 "Light Up Now" one-shot flow

1. Same prerequisite — team must already be in "My Teams" with a `GameDayAutopilotConfig` (autopilot can be off, just needs the config).
2. Tap "Light Up Now" button on the team card.
3. `_activateNow` builds a WLED payload from the team's `primaryColorValue` + `secondaryColorValue` + selected effect/speed/intensity/brightness, OR uses `savedDesignPayload` if the user picked a custom design via the design picker.
4. `repo.applyJson(payload)` POSTs to the controller.
5. Sets `activePresetLabelProvider.state = '${shortTeamName} Game Day'`.
6. Pops back to wherever pushed the screen.

**Commitment:** Zero. Lights stay on team colors until something else changes them.

**Post-event handling:** **Nothing.** No game tracking, no end-of-game detection, no revert-to-baseline. If the user tapped "Light Up Now" at 6 PM and the game ends at 10:30 PM, the lights stay on team colors until midnight, until tomorrow, until next week — until the user manually changes them or until a `ScheduleItem`'s clock-time override fires.

### 2.3 The missing third mode

Steve's prompt implies a mode that doesn't exist:
- **One-shot, time-bounded.** Apply Royals NOW, automatically revert at game-end-detected to a user-supplied baseline ("normal blue lighting").

The closest thing in the codebase is the *commercial* Game Day Service (1.5), which does have a "revert to baseline day-part" semantic — but that's commercial, configured at install time, and not user-driven per-event from chat.

---

## 3 — Lumina AI / chat awareness

`grep -rn "gameDay\|game_day\|GameDay\|GAME_DAY\|autopilot" lib/lumina_ai/ lib/features/ai/` returns:
- One reference in `lumina_ai_service.dart:498` — a comment on temperature policy mentioning autopilot generation; not actual integration.
- One in `lumina_ai_screen.dart:20, 314` — `autopilotSchedulerProvider.importSmartSchedule(payload)` for **multi-day season-fill** (e.g. "Christmas all of December"), not Game Day Autopilot.
- One in `lumina_smart_scheduler.dart:311` — comment about driving whole-season scheduling.

**Lumina chat does not know that Game Day Autopilot exists.** It does not know about the "Light Up Now" path either. It does not know about the Game Day screen's existence. It does not have a route to navigate the user there.

The smart-tier system prompt (`_kSmartSystemPrompt` in `lumina_ai_service.dart:176`) does tell the AI to recognize sports teams and produce designs, and includes "game day" as a smart-tier classification trigger ([line 43](lib/lumina_ai/lumina_ai_service.dart#L43)) — but the only output behaviors are immediate WLED apply or singular `schedulingIntent` for clock-time recurrences.

---

## 4 — Calendar / schedule sports anchor support

Searched: `sportsAnchor`, `gameAnchor`, `teamId.*schedule`, `schedule.*team`, `teamSlug`, `gameId` in `lib/features/schedule/`.

`CalendarEntry` ([calendar_entry.dart:24](lib/features/schedule/calendar_entry.dart#L24)) fields:
```dart
final String dateKey;       // 'YYYY-MM-DD'
final String? onTime;       // '18:00' (24-hr)
final String? offTime;      // '23:30' (24-hr)
final String? sourceTag;    // 'game_day' | 'game_day_group' | 'autopilot' | null
```

No `teamSlug`, no `gameId`, no `sportsAnchor`. The Game Day-tagged entries **do not retain any link** to which game they were generated for; they're pure date+time entries with a provenance label. End-of-game cannot be re-resolved from a `CalendarEntry` alone — that logic lives in the `GameDayAutopilotService`'s phase machine, which is keyed on `teamSlug` from the persisted config, not on calendar entries.

**There is no one-shot game-anchored calendar entry path.** The closest workflow available today: a user could manually create a calendar entry for the date with custom on/off clock times — but they'd have to guess game start/end and lose the "auto-revert when game actually ends" semantic.

---

## 5 — Categorization

**(D) AMBIGUOUS / OVERLAP** — but with a clearer characterization than "ambiguous" suggests:

- **One feature surface** (the Game Day screen) — not two.
- **Two modes** on that surface (one-shot button, recurring toggle) — not two features.
- **A third needed mode is missing** (one-shot with auto-revert at game end to a user baseline).
- **Lumina chat is unaware of any of this** — including the existence of the Game Day surface itself.

Why not (A) "two distinct features"? Because they share `GameDayAutopilotConfig` (one Firestore doc per team), share the team registration in "My Teams", share the design picker, share the colors, and live on the same card. Calling them distinct features overstates their separation.

Why not (B) "one feature with workaround"? Because "Light Up Now" *is* a real, designed, named one-shot path — not a workaround. It just doesn't include post-event handling.

Why not (C) "no one-shot path at all"? Because "Light Up Now" exists.

The honest characterization is: *"One Game Day surface with two designed modes; a third mode (one-shot + auto-revert) is a real gap."*

---

## 6 — Recommended handling for Steve's prompt

Steve's intent: **one-shot, time-bounded, with auto-revert to a baseline.**

**The previous audit's recommendation to redirect Steve to Game Day Autopilot was wrong on two grounds:**
1. **Over-commitment:** enabling autopilot subscribes Steve to ALL future Royals games (~162 MLB regular-season games + postseason), populates his calendar with all of them, and adds Royals to his "My Teams" / sports priority list. This is dramatically more than "the game today."
2. **Wrong post-event behavior:** autopilot's `onResumeNormalSchedule` callback **turns lights off**, not "resume normal blue lighting." Steve specifically asked for blue after — autopilot would instead leave him in the dark.

### Three options for Steve's prompt

**Option 1 — Honest one-shot now, no auto-revert (cheapest).**
Lumina chat treats this as two separate immediate actions:
1. Apply Royals design now (works today via existing immediate `wled` payload path).
2. *Reply with text* ("I'll set Royals colors now. Once the game ends, just tell me to switch back to blue.") — no scheduled second action.

**Pros:** zero new infrastructure. Honest about limitations. Customer manually triggers blue when the game ends.
**Cons:** Steve has to remember to tell Lumina, mid-evening, after a Royals game. UX failure in the literal "set it and forget it" sense.
**Implementation:** Prompt-only change in `_kSmartSystemPrompt` — add an instruction that compound prompts like "X now then Y after [event]" should apply X immediately and tell the user to ask again later for Y. ~20 LOC of prompt text.
**Time:** half a session.

**Option 2 — Build the missing third mode (medium, durable).**
Add a real one-shot, game-anchored, auto-revert path:
1. New ephemeral session model (in-memory or short-lived Firestore doc) — *not* a `GameDayAutopilotConfig` enable. Lives only until the resolved game ends + 30-min countdown, then deletes itself.
2. Stores: `teamSlug`, `gameId` (from ESPN), `revertToPayload` (Steve's blue lighting WLED payload), `revertToLabel` ("Normal Blue").
3. Reuses `GameDayAutopilotService`'s phase machine but in a one-shot mode (cancel after first `completed` transition, don't re-arm for next game).
4. Lumina chat gains awareness: detect "for the game today" / "tonight's game" → propose this ephemeral session + capture the user's "after" baseline.

**Pros:** Matches Steve's intent literally. Doesn't pollute "My Teams" or the calendar with autopilot entries. Reuses existing phase machine + ESPN polling.
**Cons:** New data model. New chat-side intent vocabulary. Changes to the phase-machine entry point.
**Implementation:** ~250-400 LOC across 4-6 files (new ephemeral session service, new config model, prompt updates, handler updates in `lumina_ai_screen.dart`, possible new home dock dispatch).
**Time:** 2-3 sessions.

**Option 3 — Redirect to Game Day Autopilot (NOT recommended, but listing for completeness).**
Lumina chat detects sports intent → offers "Want me to set up Game Day Autopilot for the Royals so this happens automatically every game?" → user taps yes → enables autopilot.

**Pros:** Reuses existing infrastructure entirely.
**Cons:** Massive over-commitment as described above. Wrong post-game behavior. The previous audit's recommendation was based on this option without the data showing it's mismatched. **Do not pursue this without first changing autopilot's post-game callback to support a user-supplied revert payload, OR explicitly framing the offer as "this will fire for every Royals game from now on."**

### My recommendation

**Ship Option 1 now (half a session).** It's honest, it's small, it's correct given the missing infrastructure. The customer can tell their staff "we type the prompt at first pitch, and again after the game" — that's a reasonable workflow at a sports bar where someone is already attentive.

**Plan Option 2 as a follow-up workstream** if customer feedback (Blue Line Bar or others) shows the manual-second-prompt is too much friction. The infrastructure to do this well already exists in `GameDayAutopilotService`'s phase machine — just needs an ephemeral wrapper.

**Reject Option 3** unless the autopilot post-game callback is first reworked to accept a revert-to-payload parameter and the chat is honest about the recurring commitment.

---

## 7 — Open questions for Tyler

1. **Was the previous audit's "redirect to autopilot" recommendation specifically based on autopilot's post-game behavior, or general "we have a feature for that"?** If the latter, the recommendation is mismatched; if the former, the post-game-turns-off behavior contradicts Steve's "resume blue."

2. **For the Blue Line Bar specifically:** is the bar in commercial mode? If yes, does the **Commercial Game Day Service** (1.5) already handle this — does the bar have a CommercialTeamsConfig with Royals as priority-rank-1, and a "Game Day day-part" configured? That service does have proper revert-to-baseline semantics. If yes, the chat-side fix might just be: detect the team, route to commercial Game Day Service activation rather than build a residential ephemeral session.

3. **Is "normal blue lighting" at the bar a saved scene/design, or just "the brand color the bar usually runs"?** This affects what the chat captures as the revert payload in Option 2 — saved scene reference vs free-form description.

4. **For app-store-v1 launch scope:** Option 1 ships today; Option 2 is post-launch. Does that match your timing? Item #51 currently has no scheduled fix session.

5. **Should the chat at minimum *mention* the Game Day screen exists?** Today, a user typing "Royals game today" gets a Royals design applied with no awareness that there's a dedicated Game Day surface they could use for richer control. Even before any of the above fixes, a "by the way, we have a Game Day section if you want to do this regularly" hint would improve discoverability — ~5 LOC of prompt text.

---

## 8 — One-line per Game Day feature found

| File | Path | One-line |
|---|---|---|
| `game_day_screen.dart` | `lib/features/game_day/` | User-facing Game Day surface; "My Teams" with per-team cards |
| `game_day_screen._activateNow` | line 388 | One-shot manual apply ("Light Up Now"), no post-event handling |
| `game_day_screen._toggleAutopilot` | line 530 | Enables recurring per-team ESPN-driven autopilot |
| `game_day_autopilot_config.dart` | `lib/features/autopilot/` | Per-team Firestore config (`/users/{uid}/game_day_autopilot/{slug}`) |
| `game_day_autopilot_service.dart` | `lib/features/autopilot/` | Phase machine: idle → preGame → liveGame → postGame → completed |
| `game_day_autopilot_providers.dart` | `lib/features/autopilot/` | Riverpod wiring; `onResumeNormalSchedule` turns lights OFF post-game |
| `game_day_autopilot_background_worker.dart` | `lib/features/autopilot/` | Background polling for game-state transitions |
| `game_day_background_persistence.dart` | `lib/features/autopilot/` | SharedPreferences session persistence across app restarts |
| `game_day_crew_models.dart` | `lib/features/game_day/` | Synchronized neighborhood Game Day group |
| `group_game_day_autopilot.dart` | `lib/features/neighborhood/models/` | Group-mode autopilot data model |
| `game_day_setup_screen.dart` | `lib/features/neighborhood/widgets/` | Neighborhood Game Day onboarding |
| `commercial/game_day_service.dart` | `lib/services/` | Commercial-mode equivalent; reverts to baseline day-part post-game |
| `calendar_entry.dart` | `lib/features/schedule/` | `sourceTag='game_day'` provenance label on calendar entries |
| `schedule_priority_resolver.dart` | `lib/features/schedule/` | Game Day priority tier (3 individual, 4 group) |
| `pattern_label_resolver.dart` | `lib/features/ai/` | Builds display labels like "KC Royals Game Night" — label-only, no behavior |
