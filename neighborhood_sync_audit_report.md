# Neighborhood Sync Feature — Comprehensive Audit

**Auditor:** Claude Opus 4.6 | **Date:** 2026-04-16
**Branch:** `release/2.1.0` | **Scope:** 34 files under `lib/features/neighborhood/` + 10 cross-cutting files

---

**30-Second Summary for Tyler:**

The Neighborhood Sync architecture already has a well-designed priority system: shortForm events (Game Day, ~3 hours) automatically pause longForm events (Holiday, days/weeks) via the `SyncHandoffManager`. This is the right design. **The gap is that the user's *individual* Game Day Autopilot (`GameDayAutopilotService`) has zero awareness of Neighborhood Sync.** When a user's personal Game Day Autopilot activates at 6:40 PM and a neighborhood holiday sync is running, both systems will write WLED payloads independently — causing flicker as they fight for control of the LEDs. The fix: add a `SyncWarningDialog.autoPauseIfInSync()` call inside the Game Day Autopilot's `onApplyPayload` callback (one line, ~15 min). Until that's in, Game Day and Sync will silently conflict on any home that has both features enabled during a game.

---

## Section 1 — Architecture Overview

### What is a Sync Group?

A **Neighborhood Group** (`NeighborhoodGroup` in `neighborhood_models.dart:174-291`) represents a collection of nearby homeowners who coordinate their LED lighting. Groups are stored in the Firestore collection `/neighborhoods/{groupId}`. Each group document contains:

- `name`, `description`, `street`, `city` (human-readable identity)
- `createdBy` (UID of the group creator/host)
- `isPublic` (discoverable by nearby users)
- `syncType` (enum: `independent`, `wave`, `pulse`, `match`, `complement` — `neighborhood_models.dart:57-97`)
- `currentPattern` (the active `SyncPatternAssignment`)
- `isActive` (whether the group is currently running a sync)
- `memberCount`, `maxMembers`
- `activeSessionId`, `lastCommandTime`

**Members** are stored in a subcollection `/neighborhoods/{groupId}/members/{uid}`, using the `NeighborhoodMember` model (`neighborhood_models.dart:294-467`). Each member doc includes:
- `displayName`, `ledCount`, `rooflineLength`, `rooflineDirection`
- `positionIndex` (physical ordering along the street, used for wave/pulse effects)
- `status` (active/paused/offline)
- `isOnline`, `lastSeen`
- `syncParticipation` (active/paused/spectator)
- `groupAutopilotOptIn` (whether the member receives group Game Day pushes)

### What is a Sync Event?

A **SyncEvent** (`models/sync_event.dart:188-392`) is a scheduled multi-home lighting event. Sync events are stored at `/neighborhoods/{groupId}/syncEvents/{eventId}`. Each event defines:

- `triggerType`: `scheduledTime` (fires at a clock time), `gameStart` (fires when ESPN reports game in-progress), or `manual`
- `category`: `gameDay` (shortForm), `holiday` (longForm), or `customEvent` (depends on duration)
- `basePattern` / `celebrationPattern` (PatternRef with effectId, colors, speed, intensity, brightness)
- `postEventBehavior`: `returnToAutopilot`, `stayOn`, or `turnOff`
- `repeatDays` (1=Mon..7=Sun for recurring events)
- Season schedule fields: `isSeasonSchedule`, `seasonYear`, `excludedGameIds`, `lastScheduleReconciliation`

The **shortForm vs longForm** classification (`models/session_duration_type.dart:8-14`) is the foundation of the priority system:
- **shortForm** (< 8 hours): Game Day events — temporary, high-intensity
- **longForm** (> 24 hours): Holiday/seasonal events — ambient, long-running

The rule (`session_duration_type.dart:75-81`): `shouldAutoOverride()` returns true when an incoming shortForm event meets an active longForm event.

### How Sync Events Execute

**Live sessions** are tracked via `SyncEventSession` (`models/sync_event.dart:394-505`) stored at `/neighborhoods/{groupId}/syncSessions/{sessionId}`. A session has:
- `status` (pending/waitingForGameStart/active/ending/completed/cancelled)
- `hostUid` (the member currently driving the lights)
- `activeParticipantUids` / `declinedUids` / `handoffPausedUids`
- `isCelebrating` / `celebrationStartedAt` (for score celebrations)
- `gameId` (ESPN game ID for game-triggered sessions)

**Trigger evaluation** happens in two places depending on app state:

1. **Foreground** (app open): `AutopilotSyncTrigger` (`services/autopilot_sync_trigger.dart:15-237`) is a Riverpod-based engine. `startMonitoring(groupId)` loads enabled sync events and dispatches each to either `_scheduleTimedEvent()` (sets a precise Dart `Timer`) or `_scheduleGameStartEvent()` (starts 30-second ESPN polling 15 min before scheduled time). When a trigger fires, it calls `SyncSessionManager.startSession()`.

2. **Background** (app closed/suspended): `SyncEventBackgroundWorker` (`services/sync_event_background_worker.dart:34-762`) runs in the sports background service isolate. It reads config from SharedPreferences (no Riverpod), polls ESPN directly, and triggers sessions via HTTP POST to a Cloud Function (`_callInitiateSessionFunction()`). It applies WLED patterns directly via `_applyPatternToControllers()` using raw HTTP to each controller IP.

### Session Lifecycle

`SyncSessionManager.startSession()` (`services/sync_session_manager.dart:33-143`):
1. Creates `SyncEventSession` doc in Firestore
2. Resolves participants (filters by online status, category opt-in, skip-next flags)
3. Resolves host (prefers group creator, falls back to first participant)
4. If the event is `shortForm`, calls `SyncHandoffManager.onShortFormSessionStart()` to pause any active longForm sessions
5. Broadcasts base pattern via `_broadcastBasePattern()`
6. If the event is Game Day, starts score monitoring for celebrations
7. Sends push notifications via `SyncNotificationService`

`SyncSessionManager.endSession()` (`services/sync_session_manager.dart:244-275`): 30-second warning, then dissolution. `_dissolveSession()` applies post-event behavior and calls `SyncHandoffManager.onShortFormSessionEnd()` to resume any paused longForm sessions.

### Pattern Broadcasting

The host pushes patterns to all members. This happens via:
- **Foreground**: `SyncSessionManager._broadcastBasePattern()` builds a `SyncCommand` and calls `neighborhoodService.broadcastCommand()` which writes to `/neighborhoods/{groupId}/commands/{commandId}`. Members listen to this subcollection via Firestore snapshots.
- **Background**: `SyncEventBackgroundWorker._applyPatternToControllers()` makes direct HTTP POST requests to each controller's WLED JSON API (`/json/state`).

### The Handoff System

`SyncHandoffManager` (`services/sync_handoff_manager.dart:103-859`) is a state machine managing priority transitions between shortForm and longForm events:

- `onShortFormSessionStart()`: Finds any active longForm session, captures its state into `PausedSessionState` (pattern, host, timing), pauses the user in Firestore, persists to SharedPreferences + Firestore (`users/{uid}/handoff/current`)
- `onShortFormSessionEnd()`: Routes to victory celebration (15s), loss hold (5s), or direct handoff, then calls `_executeHandoffToLongForm()` which uses WLED `transition: 30` (3-second crossfade) to smoothly resume the longForm pattern

### Persistence

- **Firestore**: Groups, members, sync events, sessions, commands, schedules, consent, handoff state
- **SharedPreferences**: Background worker config (user UID, group ID, active session JSON, sync event list), handoff state backup, onboarding flag
- **Cloud Functions**: Session initiation from background isolate (HTTP POST, no Firebase SDK in isolate)

---

## Section 2 — Integration with Scheduling System

### Does Sync Write to schedulesProvider or calendarScheduleProvider?

**No.** There are zero references to `calendarScheduleProvider`, `schedulesProvider`, `ScheduleFinder`, or `findCurrentSchedule` anywhere in `lib/features/neighborhood/`. The neighborhood sync system operates entirely through its own parallel data path:
- Sync schedules are stored at `/neighborhoods/{groupId}/schedules/{scheduleId}` (via `NeighborhoodService`)
- Sync sessions are stored at `/neighborhoods/{groupId}/syncSessions/{sessionId}`
- Patterns are applied directly to WLED via `broadcastCommand()` or raw HTTP

### Does Sync Read from schedulesProvider?

**No.** The sync system has no awareness of the user's personal schedule (recurring `ScheduleItem` entries or `CalendarEntry` overrides). It does not check whether a user's personal schedule is running before applying a sync pattern.

### Does ScheduleFinder Account for Sync Events?

**No.** `ScheduleFinder.findCurrentSchedule` (in `schedule_providers.dart`) only considers:
1. Date-specific `CalendarEntry` overrides (user, holiday, autopilot types)
2. Recurring `ScheduleItem` entries matching the current day/time

It has no awareness of active neighborhood sync sessions.

### Do Sync Events Appear in the User's Schedule UI?

**Indirectly.** The group-level Game Day Autopilot writes to a separate schedule UI within the Neighborhood Sync screen (`widgets/schedule_list.dart`, `widgets/group_autopilot_schedule_card.dart`). But these do NOT appear in the main app's Schedule tab (`/schedule` route). The user's personal schedule and their neighborhood sync schedules exist in completely separate UI and data paths.

### Inconsistency Flag

**This is a design gap, not a bug.** The two schedule systems are intentionally separate (neighborhood sync is a group-level feature, personal schedule is user-level). However, the user has no unified view of "what will my lights do tonight?" The main Schedule tab doesn't mention sync commitments, and the Sync screen doesn't show personal schedule conflicts. If a user has a personal schedule "Warm White at sunset" AND a neighborhood sync "Christmas Lights 5-11 PM," both will attempt to control the lights. The personal schedule's WLED timer fires on-device, while the sync pattern arrives via broadcast command — last write wins, with possible flicker.

---

## Section 3 — Integration with Game Day Autopilot

### Where is GameDayAutopilotService Aware of Sync?

**It is not.** `game_day_autopilot_service.dart` (802 lines) contains zero imports from `features/neighborhood/`. The service operates entirely through callback hooks (`onApplyPayload`, `onResumeNormalSchedule`, etc.) that are wired in `game_day_autopilot_providers.dart`. The provider layer (`game_day_autopilot_providers.dart:46-126`) wires:
- `onApplyPayload` -> `wledRepositoryProvider.applyJson()`
- `onResumeNormalSchedule` -> `wledStateProvider.notifier.togglePower(false)`

Neither callback checks for or interacts with neighborhood sync state.

### Where is SyncEventBackgroundWorker Aware of Game Day Sessions?

**Partially.** The background worker and the Game Day autopilot share the sports background service (`sports_background_service.dart`) as their host process. Score alert events flow from `ScoreMonitorService` to `SyncEventBackgroundWorker.onScoreAlertEvent()` (`sync_event_background_worker.dart:77-99`), which the worker uses to fire celebrations on active sync sessions. However, the worker does not check `hasActiveGameDayAutopilotProvider` before acting — it only checks its own sync event state.

### What Happens When Game Day Activates While Sync is Running?

**Conflict scenario: User's individual Game Day Autopilot activates while a neighborhood holiday sync is active.**

Traced code path:
1. `GameDayAutopilotNotifier.build()` starts a 1-minute evaluation timer (`game_day_autopilot_providers.dart:209`)
2. Timer fires `service.evaluateConfigs()` (`game_day_autopilot_service.dart:192-228`)
3. `evaluateConfigs` finds a game starting within 30 minutes, calls `_activatePreGame()` (line 209)
4. `_activatePreGame()` calls `selectDesign()` then `onApplyPayload(payload)` (line 524)
5. `onApplyPayload` is wired to `ref.read(wledRepositoryProvider)?.applyJson(payload)` (line 54-65 of providers)
6. The WLED device receives the Game Day pattern

Meanwhile:
7. The neighborhood sync session is also active, with the host periodically broadcasting commands
8. When a sync command arrives, `neighborhoodService.broadcastCommand()` writes to Firestore
9. The user's client receives the Firestore snapshot and applies the sync pattern

**Result: Both systems write to the same WLED device with no coordination. The lights flicker between Game Day patterns and sync patterns, with the last writer winning each cycle.**

There is no lock, no priority check, no pause mechanism invoked. `SyncWarningDialog.autoPauseIfInSync()` exists for user-initiated actions (power toggle, pattern change) but is never called by the Game Day Autopilot.

### What About Neighborhood Sync's Own Game Day Events?

The neighborhood sync system has its *own* Game Day capability via `SyncEvent` with `triggerType: gameStart`. When a sync-level Game Day event fires:
1. `SyncSessionManager.startSession()` calls `SyncHandoffManager.onShortFormSessionStart()` (`sync_session_manager.dart:101-104`)
2. The handoff manager finds any active longForm sync, captures its state, pauses the user
3. The shortForm Game Day sync takes control

**This works correctly** within the sync system. The problem is that this mechanism is entirely separate from the user's *individual* `GameDayAutopilotService`. A user could have:
- A neighborhood holiday sync (longForm) running
- A neighborhood Game Day sync event (shortForm) that correctly pauses the holiday sync
- AND their personal Game Day Autopilot, which knows about neither

### Score Alert / Celebration Path

When a score is detected (`sports_background_service.dart:165-168`):
1. `syncWorker.onScoreAlertEvent(event)` is called in the background worker
2. The worker checks for active sync sessions matching the team
3. If found, `_fireCelebration()` applies the celebration pattern to all controllers, with an auto-revert timer

Separately, the personal Game Day Autopilot has its own celebration logic (score celebrations via the autopilot config). These two celebration paths are independent and could conflict if both are active for the same game.

### Post-Game Transition

When a Game Day Autopilot session ends (`_updateActiveSession` detects game final):
1. After a 30-minute countdown, `onResumeNormalSchedule` fires
2. This calls `wledStateProvider.notifier.togglePower(false)` — turns lights OFF

If a neighborhood sync was running before Game Day, turning lights off is wrong. The sync pattern should resume. **The Game Day service has no concept of "what was running before me."**

In contrast, the sync system's `SyncHandoffManager.onShortFormSessionEnd()` correctly resumes the paused longForm pattern via crossfade transition.

---

## Section 4 — Priority & Precedence Findings

### Scenario 4a: Christmas Sync + Chiefs Game on Dec 14

| Time | Sync System | Game Day Autopilot | Actual Behavior | Ideal Behavior |
|------|-------------|-------------------|-----------------|----------------|
| 4:30 PM | Sync not yet started | Idle | Lights per user schedule | Same |
| 5:00 PM | Holiday sync starts (longForm) — Christmas lights applied to all members | Idle | Christmas pattern running | Same |
| 6:40 PM | Still running Christmas | `_activatePreGame()` fires — writes Chiefs pattern via `applyJson()` | **CONFLICT**: Christmas pattern from sync + Chiefs pattern from autopilot both writing to WLED. Last write wins, flicker likely. | Game Day should pause sync via handoff, then apply Chiefs pattern cleanly |
| 7:10 PM | Still writing Christmas commands | Live game phase | Same conflict, ongoing | Game Day has control, sync is paused |
| 10:30 PM | Still writing Christmas | Post-game 30-min countdown | Same conflict | Game Day still has control |
| 11:00 PM | Still active | `onResumeNormalSchedule` -> turns lights **OFF** | Lights go dark despite Christmas sync still active | Handoff back to Christmas sync pattern via crossfade |
| 11:01 PM | Next sync command arrives → Christmas resumes | Idle | Christmas pattern restored (eventually, after next poll) | Should be instant via handoff |

**Summary:** The 6:40-11:00 PM window has uncontrolled conflict. At 11:00 PM lights go dark briefly. Christmas resumes only when the next sync poll fires (could be seconds to minutes).

### Scenario 4b: Touchdown at 8:45 PM

Two independent celebration paths could fire:
1. **Personal Game Day Autopilot**: Score celebration (if `scoreCelebrationEnabled`) — applies celebration pattern directly to WLED
2. **Neighborhood Sync background worker**: `_fireCelebration()` on the active sync session — applies celebration pattern to all controllers

If both are active, both celebration patterns write to WLED simultaneously. The visual result depends on which HTTP call arrives last. **No coordination exists between these two celebration paths.**

If the sync group also has a group-level Game Day event (via `SyncEvent.gameDay`), the celebration fires through the sync system's path only, which is clean. The conflict is specifically between the *individual* autopilot and the *neighborhood* sync.

### Scenario 4c: User Leaves Crew at 8 PM During Game

Code path:
1. User taps "Leave Crew" -> `NeighborhoodService.leaveGroup()` (`neighborhood_service.dart:170-196`)
2. Member doc deleted from Firestore
3. The user's individual Game Day Autopilot continues — it has no dependency on neighborhood membership
4. When Game Day ends, `onResumeNormalSchedule` turns lights off

**What about sync resumption?** If the user was in a longForm sync that was paused by a shortForm sync, and they leave the group mid-shortForm, the `SyncHandoffManager` still has `PausedSessionState` in SharedPreferences and Firestore (`users/{uid}/handoff/current`). But the longForm group no longer includes this user. When `_executeHandoffToLongForm()` tries to resume, `_resumeUserInGroup()` will attempt to update a member doc that no longer exists. **This is a bug** — the leave-group flow does not clear handoff state.

### Scenario 4d: Sync Event Scheduled to Start at 7 PM, Game Day Activates at 6:40 PM

Code path:
1. At 6:40 PM: Game Day Autopilot's `_activatePreGame()` fires, applies Chiefs pattern
2. At 7:00 PM: Sync event trigger fires (via `AutopilotSyncTrigger._scheduleTimedEvent()` or background worker)
3. `SyncSessionManager.startSession()` creates the session and broadcasts the sync pattern
4. The sync pattern overwrites the Game Day pattern

**The sync system does not check for active Game Day Autopilot sessions before starting.** There is no `hasActiveGameDayAutopilotProvider` check in `startSession()` or the trigger evaluation logic.

**Ideal behavior:** The sync event should detect that a Game Day session is active and defer startup until the game ends, or start in a "paused" state that resumes post-game.

---

## Section 5 — Technical Risks & Bugs

### 5.1 Leave-Group Does Not Clear Handoff State

**File:** `neighborhood_service.dart:170-196` (leaveGroup), `sync_handoff_manager.dart:724-752` (persistence)
**Description:** When a user leaves a neighborhood group, `NeighborhoodService.leaveGroup()` deletes the member doc but does not clear `users/{uid}/handoff/current` from Firestore or the handoff state from SharedPreferences. If the user was mid-handoff (longForm paused for shortForm), the handoff manager will attempt to resume a session in a group the user no longer belongs to.
**Severity:** Medium — causes a silent failure (Firestore permission error on member doc update) and leaves orphaned handoff state.
**Fix:** Add `syncHandoffManagerProvider.read().onUserManualOverride()` call in `leaveGroup()`.

### 5.2 Background Worker and Foreground Trigger Can Both Fire for the Same Event

**File:** `sync_event_background_worker.dart:102-147` (_poll), `autopilot_sync_trigger.dart:54-66` (_scheduleEvent)
**Description:** Both the background worker (isolate) and foreground trigger (Riverpod) evaluate the same sync events independently. If the app transitions from background to foreground during a trigger window, both could call `startSession()` for the same event, creating duplicate sessions in Firestore.
**Severity:** Medium — could cause duplicate session docs and double pattern application. The background worker uses a Cloud Function while the foreground uses Riverpod, so there's no shared lock.
**Fix:** Add an idempotency check in `SyncSessionManager.startSession()` — before creating a session, query for an existing active session with the same `syncEventId`. If found, skip creation.

### 5.3 Background Worker Uses Hardcoded Cloud Function URL

**File:** `sync_event_background_worker.dart:438-488` (_callInitiateSessionFunction)
**Description:** The Cloud Function HTTP endpoint for session initiation is constructed from a hardcoded project ID or region. If the Firebase project changes or the function is redeployed to a different region, the background worker silently fails (the isolate can't read Firebase config). The worker catches and logs the error but doesn't retry or notify the user.
**Severity:** Low — only affects initial deployment and region changes.
**Fix:** Pass the Cloud Function URL through SharedPreferences during foreground initialization.

### 5.4 `SyncParticipationConsent.oderId` Typo

**File:** `models/sync_event.dart:509`
**Description:** The field is named `oderId` instead of `userId` or `memberId`. This appears to be a typo that has propagated into Firestore field names.
**Severity:** Low — functional but confusing. Changing it now would require a Firestore migration.
**Fix:** Add a comment noting the typo and leave as-is, or migrate if the collection is small enough.

### 5.5 Celebration Timer in Background Worker Has No Cancellation on Session End

**File:** `sync_event_background_worker.dart:554-585` (_fireCelebration)
**Description:** `_fireCelebration()` applies a celebration pattern and sets a `Future.delayed` to revert to the base pattern after `celebrationDurationSeconds`. If the session ends during the celebration (e.g., game goes final right after a score), the revert timer still fires and re-applies the base pattern after the session has already dissolved.
**Severity:** Low — the base pattern application will succeed (WLED accepts any valid payload) but it's semantically wrong. The user might see a brief flash of the base pattern after dissolution applies post-event behavior.
**Fix:** Track the celebration `Timer` and cancel it in `_callEndSessionFunction()`.

### 5.6 Score Diff Logic in Background Worker Doesn't Account for Correction Scores

**File:** `sync_event_background_worker.dart:493-551` (_monitorActiveSession)
**Description:** The score celebration triggers when the new score is higher than the previous score for the user's team. If ESPN corrects a score downward (e.g., overturned touchdown), the diff goes negative and no celebration fires — which is correct. But if a correction then restores the score, it fires a duplicate celebration for a score that was already celebrated.
**Severity:** Low — rare edge case (score corrections are uncommon).
**Fix:** Track celebrated score thresholds rather than diffs.

### 5.7 Handoff Manager Crossfade Uses WLED `transition` Field Without Checking Support

**File:** `sync_handoff_manager.dart:385-421` (_executeCrossfadeTransition)
**Description:** The crossfade uses `'transition': 30` (3 seconds in 100ms units) in the WLED payload. Not all WLED firmware versions support the `transition` field in JSON API state payloads. Older firmware (<0.14) silently ignores it, which means no crossfade — the pattern snaps instantly.
**Severity:** Low — degrades gracefully (instant transition instead of crossfade).
**Fix:** Accept as-is; document minimum firmware requirement.

### 5.8 No Timeout on Cloud Function HTTP Calls in Background Worker

**File:** `sync_event_background_worker.dart:438-488` (_callInitiateSessionFunction)
**Description:** The HTTP POST to the Cloud Function does not set an explicit timeout. On poor networks, this could hang the background worker's poll loop indefinitely, preventing other sync events from being evaluated.
**Severity:** Medium — blocks all sync event processing for the duration of the hang.
**Fix:** Add `client.post(...).timeout(const Duration(seconds: 15))`.

### 5.9 Static `_cached` in DemoStockHome Breaks Hot Reload (Pre-existing, Not Sync-Specific)

Not re-flagged — this is a demo issue already noted.

---

## Section 6 — Recommendations for Implementing Game-Day-Over-Sync Priority

### Recommended Approach: Option (b) — Autopilot Layer Integration

The fix should live at the **autopilot callback layer** in `game_day_autopilot_providers.dart`, using the existing `SyncWarningDialog.autoPauseIfInSync()` mechanism for the initial implementation, with a future path to the full `SyncHandoffManager`.

**Reasoning:**

Option (a) (Schedule layer) won't work because Neighborhood Sync doesn't use the schedule system at all — there's nothing to integrate with.

Option (c) (WLED apply layer lock) is too low-level — it would require a shared mutex across the WLED repository, the background worker's direct HTTP calls, and the sync command broadcast system. Three different write paths would need to respect the lock.

Option (d) (SyncHandoffManager) is architecturally the best long-term answer, but it requires the Game Day Autopilot to model its sessions as `shortForm` events that the handoff manager can reason about. This is a larger refactor.

**Option (b)** is the right balance: modify the Game Day Autopilot's callbacks to check for and interact with active sync state. Two touch points:

### Implementation Plan

**Step 1: Pause sync when Game Day activates** (Small — ~30 min)

In `game_day_autopilot_providers.dart`, modify the `onApplyPayload` callback (lines 54-65) to call `SyncWarningDialog.autoPauseIfInSync(ref)` before applying the payload:

```dart
onApplyPayload: (payload) async {
  // Pause neighborhood sync if active — Game Day takes priority
  await SyncWarningDialog.autoPauseIfInSync(ref);
  final repo = ref.read(wledRepositoryProvider);
  if (repo == null) return;
  await repo.applyJson(payload);
},
```

This uses the existing auto-pause mechanism (already proven for user actions) to silently pause the user's sync participation when Game Day activates. Other members in the sync group continue unaffected.

**Step 2: Resume sync when Game Day ends** (Small — ~30 min)

Modify the `onResumeNormalSchedule` callback (lines 67-76) to resume sync instead of turning lights off:

```dart
onResumeNormalSchedule: () async {
  // Check if user was in a sync before Game Day
  final syncStatus = ref.read(userSyncStatusProvider);
  if (syncStatus.isInActiveSync && syncStatus.isPaused) {
    // Resume sync participation — sync will push its current pattern
    await ref.read(neighborhoodNotifierProvider.notifier).resumeMySync();
    return;
  }
  // No active sync to resume — turn off as before
  final notifier = ref.read(wledStateProvider.notifier);
  await notifier.togglePower(false);
},
```

**Step 3: Block sync event startup during active Game Day** (Medium — ~1-2 hours)

In `SyncSessionManager.startSession()`, add a check before broadcasting:

```dart
// Check if user has an active personal Game Day session
final hasGameDay = ref.read(hasActiveGameDayAutopilotProvider);
if (hasGameDay && event.isLongForm) {
  // Don't start a new longForm sync while Game Day is active
  // The sync will start naturally when Game Day ends and resumes normal
  return;
}
```

For shortForm sync events (a group Game Day sync starting during a personal Game Day), the existing behavior is acceptable — both are trying to apply game colors, and the sync version coordinates multiple homes.

### What Breaks If This Approach Is Wrong

- If we pause at the autopilot layer but a NEW sync event starts during Game Day (Scenario 4d), `startSession()` will still fire and apply the sync pattern. Step 3 addresses this.
- If the user manually resumes sync during a game (taps "Rejoin" on the banner), the sync pattern will overwrite Game Day. This is acceptable — explicit user action should always win.
- If the Game Day Autopilot crashes or the app is killed, the sync remains paused. On next app launch, `SyncHandoffManager.restoreState()` checks for stale paused sessions and can clean up — but only if the pause was done through the handoff system. The Step 1 approach uses `pauseMySync()` which sets the member's `syncParticipation` to `paused` in Firestore. This persists correctly but doesn't have the handoff manager's automatic resume logic.

**Risk mitigation:** Add a 4-hour timeout to the auto-pause. If the member has been paused for >4 hours and no Game Day session is active, auto-resume. This catches crash/kill scenarios.

### Future Path (Large — half-day+)

The full solution is to make `GameDayAutopilotService` emit its sessions as `shortForm` events that `SyncHandoffManager` natively manages. This means:
1. `AutopilotSession` gets a `toSyncEventSession()` converter
2. `SyncHandoffManager.onShortFormSessionStart()` is called with the Game Day session
3. All the crossfade, celebration, and resume logic works automatically
4. Background worker awareness comes for free

This is architecturally superior but requires unifying two session models. Recommend doing this as a v2.2 feature.

### Rough Effort Estimates

| Step | Effort | Risk |
|------|--------|------|
| Step 1: Pause sync on Game Day activate | Small (30 min) | Very low — uses proven mechanism |
| Step 2: Resume sync on Game Day end | Small (30 min) | Low — straightforward conditional |
| Step 3: Block longForm sync during Game Day | Medium (1-2 hours) | Medium — needs testing for timing edge cases |
| Auto-resume timeout safety net | Small (30 min) | Low |
| **Total for v2.1 fix** | **Medium (2-3 hours)** | |
| Future: Unified session model | Large (half-day+) | Medium — session model unification |

---

*End of audit. All findings are based on static code analysis against the current working tree on the `release/2.1.0` branch. No code was executed or modified.*
