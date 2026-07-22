# Test Plan — scheduled-event firing + GameDay live scoring + Light Up Now

Manual test plan for the release-blocker fix landing in `submission/app-store-v1`.

**Deploy order before testing:**

1. `cd functions && firebase deploy --only functions:applySyncPattern,functions:initiateSyncSession,functions:endSyncSession`
2. Wait for deploy to succeed.
3. Install the new app build over the previous one (don't uninstall — we want
   to verify the upgrade path).

> **Note:** Once the new functions are deployed, any older client still calling
> them via the Firebase Functions callable SDK will start failing with auth
> errors. That's acceptable because the existing background calls were
> already failing 100% — nothing currently working will stop working.

---

## Test A — Scheduled Sync event fires at start and end

**Setup:**

1. Sign in on the test device (Pulla tablet, `192.168.1.90`).
2. Open Neighborhood Sync → create a new scheduled sync event:
   - Name: `End-Time Smoke Test`
   - Trigger: Scheduled Time
   - Start: 5 minutes from now
   - End: 10 minutes from the start (so 15 minutes from now total)
   - Pattern: any obvious / non-default pattern so the change is visible
   - Enabled: on
3. Background the app — the background isolate should pick up the event from
   SharedPreferences.

**Expected — Start:**

- At the scheduled start time (±60 s), the controller's lights change to the
  event's pattern.
- App notification: `Sync Active — End-Time Smoke Test`.
- `syncSessionStarted` event surfaces to the foreground UI if the app is
  reopened.

**Expected — End:**

- At the scheduled end time (±60 s on next poll), the session ends:
  - If `postEventBehavior == turnOff`: lights turn off.
  - Otherwise (default `returnToAutopilot`): lights drop out of the sync and
    return to the autopilot/baseline schedule.
- App notification: `Sync session ended`.
- `[SyncBgWorker] Scheduled end time reached for "End-Time Smoke Test" — ending session`
  appears in adb logcat.

**Failure modes to watch for:**

- Start fires but end never fires → check that `scheduledEndTime` made it
  into Firestore on the event document.
- No HTTP call observed in logcat → check that the persisted ID token isn't
  null (`adb logcat | grep "No ID token"`).

---

## Test B — GameDay Live Scoring toggle persists

**Setup:**

1. Open GameDay screen, ensure at least one team is added (or add one).
2. Make sure the Live Scoring toggle on the team card is currently **on**.

**Steps + expected:**

1. Flip Live Scoring **off** on the team card.
   - Toggle should remain off (no snap-back).
2. Background the app (home button or app switcher).
3. Reopen the app, navigate back to GameDay.
   - Toggle should still be **off**.
4. Flip Live Scoring **on**.
   - Toggle should remain on.
5. Repeat the background/reopen cycle.
   - Toggle should still be **on**.

**Spot-check Firestore:**

- `users/{uid}/game_day_autopilot/{teamSlug}` document should have
  `score_celebration_enabled: false` after step 1, `true` after step 4.

**Failure modes:**

- Toggle visually flips for a frame then snaps back → `setLiveScoring` not
  wired or the new method is throwing (check debug console for `setLiveScoring failed`).

---

## Test C — Light Up Now enables autopilot

**Setup:**

1. Open GameDay, add a team if needed.
2. Make sure the **Autopilot** toggle on the team card is **off**.

**Steps + expected:**

1. Tap **Light Up Now**.
   - Snackbar: `<Team> lights activated!`
   - Lights apply the team design.
2. Navigate back into GameDay (the screen pops on success — re-enter from
   the dashboard).
   - The team card's **Autopilot** toggle should now be **on**.
3. If the team has a live game in progress, wait for a score event.
   - Background worker should detect the score via `ScoreMonitorService`.
   - Lights should briefly flash the celebration pattern, then return to
     base pattern after ~15s.

**Failure modes:**

- Autopilot toggle stays off → `_activateNow` did not call
  `toggleAutopilot(enabled: true)`, or the call threw and logged
  `[GameDay] Light Up Now: enable autopilot failed`.
- No celebration when team scores → background worker has no session for
  the team. Check that `evaluate()` ran since enabling autopilot, and that
  `loadGameDayConfigsForBackground()` returns the team with `enabled: true`.

---

## Test D — Cloud Function auth

**Setup:**

1. Debug-build install on the test device.
2. Open a Dart-side dev shell or temporary debug button that calls
   `saveSyncIdToken(null)` to clear the persisted token.

**Steps + expected:**

1. After clearing the token, trigger a scheduled sync event (or wait for
   one that's about to fire).
2. Open adb logcat / debug console.
   - Expected lines (one or more, depending on which path is exercised):
     - `[SyncBgWorker] No ID token persisted — skipping initiateSync`
     - `[SyncBgWorker] No ID token persisted — skipping applySyncPattern`
     - `[SyncBgWorker] No ID token persisted — skipping endSession`
     - `[GameDayBg] No ID token persisted — skipping applySyncPattern`
   - The worker must **not** crash and must **not** spin in a retry loop.
3. Foreground the app (just bring it back to the front).
   - `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` fires.
   - `refreshSyncIdToken(ref)` runs → token is force-refreshed via
     `user.getIdToken(true)` and saved back to SharedPreferences.
4. Trigger another scheduled event (or wait for one).
   - The worker now finds a token, attaches `Authorization: Bearer …` and
     the Cloud Function returns 200.

**Spot-check — function-side:**

- `firebase functions:log --only initiateSyncSession` should show the
  request with a verified UID matching `initiatorUid`.

**Failure modes:**

- Worker crashes when token is null → null-guard missing in one of the
  HTTP call sites.
- Token never repopulates after foreground → `WidgetsBindingObserver` not
  registered (check `addObserver` in `_MainScaffoldState.initState`).
