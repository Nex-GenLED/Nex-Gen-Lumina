# Build +126 candidate — `feat/126-candidate`

Assembled 2026-11-12 from `feat/124-colour` at `9a440b0` (the build-125 tag's
commit, 2.5.10+125): sync-reliability slices A, C and B, a cross-slice test with
one fix, these docs, then the version bump to 2.5.10+126 as the final commit.
**Not tagged, not built by CI, not deployed. No Firestore rules or functions
deploy. No controller, bench unit or production system was contacted to
assemble it** (one read-only REST call to the Firebase Rules API, section 8).
The tag waits for the owner's go. Slice D is **not** in this candidate
(section 9).

## 1. What went in

Base: `build-125` = `9a440b0` (2.5.10+125, TestFlight 360).

| # | Commit | What |
|---|---|---|
| 1 | `87943add43a5` | Merge slice A `feat/126-sync-queue-24h` @ `0ea0ebc` (no-ff): queue-not-drop; the editor re-opens on a 24-hour label. |
| 2 | `76954ad8b848` | Merge slice C `feat/126-schedule-editor-sentence` @ `1b2987f` (no-ff): the plain-words line under the wheels; the editor header wraps at large text. |
| 3 | `239cbfe9c290` | Merge slice B `feat/126-sync-resync-status` @ `568d70f` (no-ff): persisted status, row and chip with Retry, owed flag, bounded automatic re-sync, Firestore mirror, option (ii). Carries A. |
| 4 | `d409a04507e8` | Cross-slice test (section 4) and the one fix it exposed. |
| 5 | docs | FACTS rows T-D6 to T-D11, this file, the bench plan `docs/bench/sync_reliability_126_bench_plan.md`. |
| 6 | the tip | `chore(release): bump to 2.5.10+126` — `pubspec.yaml` and `lib/app_version.dart` only. |

The bump is the last commit, so the tip is the build point and carries every
app byte (ledger convention 1).

Slice B's new commit, made first (step 1 of the brief), on
`feat/126-sync-resync-status` on top of `f8b85a5`, no amend, pushed:

- `568d70f0d2b9` — `fix(schedule): automatic re-sync runs 9:00–15:00 local,
  lights on or off`. Replaces "lights OFF and 8:00–17:00". The decision has no
  lights input any more; the bounds (one attempt per trigger, ten minutes apart,
  six a day) and the manual Retry (at once) are unchanged. Tests moved to the new
  bounds, and a new one proves a lights-ON account on a LAN return at 13:30 is
  retried while the same account at 16:30 is held.

Source tips (all pushed; none changed by the merge):

- A: `feat/126-sync-queue-24h` @ `0ea0ebc` (2 commits on `9a440b0`).
- C: `feat/126-schedule-editor-sentence` @ `1b2987f` (1 commit on `9a440b0`).
- B: `feat/126-sync-resync-status` @ `568d70f` (5 commits on A).
- D: `feat/126-sync-readback` @ `a227349` (3 commits on B's **old** tip
  `f8b85a5`) — not merged, see section 9.

**Conflicts: none.** A then C auto-merged `my_schedule_page.dart` and
`time_format.dart` (a `git merge-tree` trial was clean first); B then
auto-merged `my_schedule_page.dart`. No file needed a hand merge.

## 2. Release notes — 2.5.10 build 126 (candidate, not shipped)

**What changed:** My Schedule now tells you whether your schedule has reached
your lights, and Home shows the same in one line. If it hasn't — you saved it
away from home, or your controller didn't answer — the app says so, offers
Retry, and tries again by itself the next time you open it at home, during the
day. A change you make while the previous one is still being saved is no longer
lost: it goes next, automatically. The schedule editor spells out what you set
("Lights on at 5:00 PM, off at 7:00 AM the next morning.") and re-opens on the
saved time on phones set to a 24-hour clock. If one pattern could not be
confirmed on your lights, the schedule stays set and the app says so instead of
switching it off.

**Tester text:** written with the build's ledger row, after the tag.

**Withdrawal text (return to 125), if needed:** Build 126 has been withdrawn.
Open TestFlight → Nex-Gen Lumina → Previous Builds → install 2.5.10 (360). Your
schedules, teams, designs and favorites stay. Three things go back to how they
were: My Schedule and Home no longer say whether your schedule reached your
lights, a change made while the previous one is still saving can be lost (save
it again at home), and the editor no longer spells out the on and off times. If
you see anything wrong after switching, tell us the date and time. Send reports
to general@nex-genled.com with the date and time.

## 3. The customer-facing strings (exact)

From `ScheduleSyncCopy.forState` in `lib/features/schedule/schedule_sync_status.dart`.
The row on My Schedule reads `<first line> <second line> · <when>`; the Home chip
reads the first line only. `<when>` is `just now`, `5m ago`, `2h ago` or `3d ago`
(`scheduleSyncRelativeTime`). The action is labelled `Retry` on both.

| State | First line (row and chip) | Second line (row only) | Retry | Colour |
|---|---|---|---|---|
| synced | Your schedule is on your lights. | *(none)* | no | green |
| queued | Saving your latest change. | It goes to your lights next, automatically. | no | cyan |
| deferredOffLan | Your schedule hasn't reached your lights yet. | It will the next time you open the app on your home Wi-Fi. You can retry now if you're home. | yes | cyan |
| failed | Your schedule hasn't reached your lights yet. | Your controller didn't answer. Check that it's powered and on Wi-Fi, then retry. | yes | red |
| writtenNotVerified | Your schedule is set, but one pattern could not be confirmed on your lights. | We'll keep trying on our own. You can retry now. | yes | amber |

Neither surface renders until the account has ever synced. "Chip cleared" in
this build means the chip shows the synced line in green with no Retry; the
chip is not removed (a customer who looks for it finds "Your schedule is on your
lights.").

The line under the editor's wheels (`scheduleWindowSentence` in
`lib/utils/time_format.dart`):

- `Lights on at 5:00 PM, off at 7:00 AM the next morning.`
- `Lights on at 6:30 AM, off at 8:00 AM this morning.` / `… this afternoon.` /
  `… this evening.` (same-day off; before noon, noon to 5 PM, later)
- `Lights on at sunset, off at sunrise the next morning.` (solar words in lower
  case; sunrise is a morning, sunset an evening)
- `Lights on at 5:00 PM and they stay on until you turn them off.` (no off time)
- Times follow the phone's 12/24-hour setting.

The queued result's own message, where a sync button shows it
(`kScheduleSyncQueued`): `Still saving your last change — this one goes next,
automatically.`

## 4. The cross-slice test

`test/features/schedule/schedule_sync_cross_slice_126_test.dart` (commit
`d409a04`), one widget test on the real `SchedulesNotifier` with a held fake
sync service and both surfaces mounted over the same container:

1. Prefs seeded as the last session left them: owed flag set, status
   deferred-off-LAN. Clock pinned to 20:15 local (the automatic re-sync is
   outside its window, so the owed flag survives launch and the customer's own
   toggles resolve it). Lights ON, on the LAN.
2. Launch: schedules load; verdict `outsideDaytime`; nothing written; the row
   and chip show the deferred line with Retry.
3. Toggle OFF → the debounced sync #1 runs and holds the lock (the clearing
   sync, verifying through the controller's stall).
4. Toggle ON four seconds later: not dropped, not run — queued behind #1
   (slice A); the row and chip now say "Saving your latest change." with no
   Retry (slice B).
5. #1 resolves; exactly one follow-up runs with the current state. Its
   schedule list is the ON schedule — armed.
6. End state: status `synced`; owed flag false in memory and in prefs; the
   mirror's last write is `synced`; row and chip show "Your schedule is on your
   lights." with no Retry; no further write.

**The fix it exposed** (same commit, `lib/features/schedule/schedule_providers.dart`):
slice A's in-flight branch returned the queued result without recording it, so
slice B's row kept the previous state (with Retry) while the edit was queued.
The branch now records the queued outcome; and when the in-flight sync finishes
with a follow-up owed, its own result is recorded as `queued` rather than
`synced`, so the owed flag is not cleared for the 800 ms until the follow-up
runs and records the real outcome. Both slices' intent is kept: A's "queued is
its own neutral state", B's "the row shows it".

## 5. Phone checklist — homeowner steps

**Before you start.** Use the spare controller (0.15.4) for steps 9–14 and 19;
never the home controller for anything that saves to the controller. Use a
bench account. Steps 15–18 need the phone's clock moved or the right time of
day; the automatic re-sync only runs between 9:00 and 15:00. "Laptop:" marks a
check that needs the controller's own pages or the app log.

**The status row and the chip, every state**

1. Fresh bench account, never synced. Open My Schedule and Home. *Expect:* no
   status row, no chip.
2. On home Wi-Fi, add a schedule (any Explore pattern, ON in 20 minutes, OFF in
   25, every day) and Save. *Expect:* within about 15 seconds the row reads
   "Your schedule is on your lights. · just now" in green with no Retry; Home
   shows a green chip "Your schedule is on your lights." with no Retry.
3. Wait six minutes, re-open My Schedule. *Expect:* the row ends "· 6m ago".
4. Put the phone on mobile data. Change the schedule's OFF time and Save.
   *Expect:* the row reads "Your schedule hasn't reached your lights yet. It
   will the next time you open the app on your home Wi-Fi. You can retry now if
   you're home. · just now" with Retry; the chip reads "Your schedule hasn't
   reached your lights yet." with Retry.
5. Still on mobile data, kill the app and re-open it. *Expect:* step 4's row
   and chip are still there (the state is kept on the phone).
6. Still on mobile data, tap Retry on the row. *Expect:* the row stays on
   "hasn't reached your lights yet" (the retry could not write either); nothing
   alarming, no red.
7. Unplug the controller's Ethernet (or power it down), join home Wi-Fi, edit
   the schedule and Save. *Expect:* the row reads "Your schedule hasn't reached
   your lights yet. Your controller didn't answer. Check that it's powered and
   on Wi-Fi, then retry. · just now" in red with Retry; the chip is red with
   Retry.
8. Reconnect the controller, wait 30 seconds, tap Retry on the chip (Home).
   *Expect:* both surfaces go green, "Your schedule is on your lights.", no
   Retry.
9. (Spare only.) Laptop: make the schedule's pattern slot unconfirmable (for
   example, fill the controller's preset file so the psave is refused, or pull
   Ethernet during the save and restore it before the verify). Save the
   schedule. *Expect:* the row reads "Your schedule is set, but one pattern
   could not be confirmed on your lights. We'll keep trying on our own. You can
   retry now. · just now" in amber with Retry; the schedule's toggle on My
   Schedule is still ON (not switched off).
10. Tap Retry. *Expect:* green "Your schedule is on your lights."

**Queue-not-drop**

11. On home Wi-Fi, toggle the schedule OFF, then ON within four seconds.
    *Expect:* after the OFF, the row reads "Saving your latest change. It goes
    to your lights next, automatically." with no Retry; within about 15
    seconds it reads "Your schedule is on your lights." Laptop: the
    controller's timers page shows the schedule's ON and OFF rows enabled.
12. Toggle OFF, ON, OFF quickly. *Expect:* the row ends green; Laptop: the
    schedule's timer rows are disabled (the last toggle won).

**The automatic re-sync**

13. On mobile data, edit and Save (row: "hasn't reached your lights yet").
    With the phone's time between 9:00 and 15:00, join home Wi-Fi with the app
    open. *Expect:* within about 15 seconds the row turns green by itself, no
    tap.
14. Same as 13 but with the lights ON (any pattern playing). *Expect:* the
    same: it runs; the lights blink for well under a second and come back.
15. Same as 13 with the phone's time at 16:30. *Expect:* the row stays on
    "hasn't reached your lights yet"; nothing runs by itself. Tap Retry.
    *Expect:* green at once.
16. Same as 13 at 8:45. *Expect:* as 15.
17. With a re-sync owed inside the window, turn Wi-Fi off and on twice within
    ten minutes. *Expect:* one automatic run (the first), then nothing until
    ten minutes have passed.
18. Kill the app with a re-sync owed, re-open it at home inside the window.
    *Expect:* it runs by itself on launch (row goes green with no tap).

**The line under the wheels and the 24-hour label**

19. Open the editor for a 5:00 PM → 7:00 AM schedule. *Expect:* under the
    wheels, "Lights on at 5:00 PM, off at 7:00 AM the next morning." Move the
    OFF wheel to 9:00 PM. *Expect:* "… off at 9:00 PM this evening." Clear the
    OFF time. *Expect:* "Lights on at 5:00 PM and they stay on until you turn
    them off." Pick sunset / sunrise. *Expect:* "Lights on at sunset, off at
    sunrise the next morning."
20. Set the phone to a 24-hour clock. Save a schedule at 17:30. Close and
    re-open its editor. *Expect:* the ON wheel shows 17:30 (not the current
    time). Back on a 12-hour clock, re-open. *Expect:* 5:30 PM.
21. Settings → Larger Text at the largest size. Open the editor. *Expect:*
    the header wraps to two lines; nothing is cut off; the line under the
    wheels wraps.

## 6. Gates

Run on the candidate tip, one at a time, free space on C: checked before each
SDK (stop under 10 GB). Filled in by the integration report; the logs are
under the session scratchpad `gates/126-candidate/`.

| SDK | pub get | analyze | TZ=UTC0 suite | golden | docs_guard |
|---|---|---|---|---|---|
| 3.47.9 | | | | | |
| 3.41.2 | | | | | |
| 3.50.0 (information) | | — | | — | — |

## 7. Bench plan

`docs/bench/sync_reliability_126_bench_plan.md` — slice B on the spare `.179`
(0.15.4) with slices A and C: the owed flag set off-LAN then the LAN-return
re-sync (inside and outside the window, lights on, the ten-minute bound),
queue-not-drop on the controller's timers, and the status mirror on the
account. **Written, not run.** The home controller `.150` is excluded by name.

## 8. The status mirror against the deployed ruleset

The mirror (`FirestoreScheduleSyncMirror`) does one merge write of the field
`schedule_sync` on the account's own user document, with nothing else in the
payload, and swallows any rejection.

Read on 2026-11-12 (read-only, Firebase Rules REST API with the owner's gcloud
token): the live Firestore release `cloud.firestore` points at ruleset
`b5a1764a-32e4-4c0a-978a-63304ef991dd`, updated 2026-10-05T15:11:31Z, and its
source is **byte-identical** to the repository's `firestore.rules` at `9a440b0`
(2,566 lines, same sha256). So the undeployed rule branches A to D are not in
the live set, and the rule that governs the mirror is the live one.

The live `match /users/{userId}` update rule allows the write when
`(isOwner(userId) && cannotModifyCriticalFields() && isValidDealerEmail(...))
|| request.auth != null`, and additionally forbids elevating `user_role` or
reassigning `dealer_code` without an admin or owner claim. A merge-set of one
field leaves `owner_id`, `id`, `email`, `user_role` and `dealer_code` as they
were, so the owner's own write passes `cannotModifyCriticalFields()`, and the
`|| request.auth != null` arm admits it regardless. **No rules change is
needed and none is made.**

What this does and does not prove: the rule exists live. A client write by a
signed-in customer against production has not been exercised (the mirror test
in the suite uses a fake). That is the bench plan's section 3.

## 9. Known, not fixed in this candidate

- **Read-back blind spot.** The post-write check that decides whether a pattern
  slot "landed" (`presetSatisfies`) compares each segment's bounds and power,
  not its effect (`fx`) or colours (`col`). An effect-only or colour-only drift
  in a slot is reported as confirmed. Slice D (`feat/126-sync-readback`)
  addresses the read-back and is not here.
- **Slice D not included.** `feat/126-sync-readback` @ `a227349` sits on slice
  B's **old** tip `f8b85a5`. It must be rebased onto B's new tip `568d70f`
  (the window change touches `schedule_providers.dart` and
  `schedule_sync_status.dart`, both of which D's base carries) before its bench
  on the spare, and it stays a branch until that bench passes.
- **Flutter 3.50.0, first widget test of a new file.** The 3.50.0 harness
  defect (a system-fonts message delivered after the widget tree is disposed
  hits the first widget test of a file) fails the known 22 text-scale tests on
  every branch, plus the first widget test of each file this candidate adds:
  `schedule_editor_24h_reopen_test.dart`, `schedule_editor_sentence_test.dart`,
  `schedule_sync_status_widgets_test.dart` and
  `schedule_sync_cross_slice_126_test.dart`. The gate SDK is 3.47.9 (pinned in
  `codemagic.yaml`); 3.50.0 runs for information only. The fix is the
  `loadAppFontsForTest` change noted in the build-125 ledger entry, not in
  scope here.
- **The mirror has not been exercised against production** (section 8).
- **Nothing has run on hardware.** The suite proves the app's side with a fake
  controller; the bench plan (section 7) is written and not run.
- **The lights-off trigger is kept as a trigger moment** (a live LAN state
  change while a re-sync is owed) even though the lights are no longer a
  condition; it is bounded like the other two. Whether it is worth keeping is
  the owner's call after the bench.

Not built, not tagged, not deployed as of 2026-11-12.
