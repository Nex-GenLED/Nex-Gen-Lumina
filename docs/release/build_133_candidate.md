# Build 133 candidate — `feat/133-candidate`

Assembled 2026-11-26 (CST) on the branch `feat/133-candidate`, cut from
`feat/131-candidate` at `7877cc76` (docs only on top of the build-131 tag's
commit `3191e4b0`). Two finished feature branches merged with `--no-ff`, one
at a time, each at the tip named below; one conflict, in
`docs/BUGS_AND_DEBT.md` only (section 1). **Not bumped and not tagged:**
`pubspec.yaml` and `lib/app_version.dart` are build 131's; the bump is a
separate later step. No Firestore rules, functions, indexes or config write.
No controller, bench unit or production system was contacted to assemble it;
the tests use fakes. No merge into main.

## 1. What went in

`git log --first-parent 7877cc76..` on this branch:

1. `4f130819` — merge `feat/132-saved-designs` @ `0d586341` (`50c6d8a6`,
   `9f02d243`, `20e4cf6d`, `56741955`, `15e159da`, `8631f381`, `59fa715c`,
   `979645a3`, `c35c61d6`, `b716a325`, `5450f6fa`, `0d586341`). **A saved
   design keeps and returns each channel's own look.** Save As Custom
   Pattern and the Now Playing save read the controller once at the tap and
   store each playing channel's own colours, effect, speed, intensity,
   direction, grouping and spacing; a failed read saves nothing and says so.
   My Designs' Apply and a favourite tapped on Home send each stored channel
   its own look (direction is not restored by Apply). Home shows "Saving…"
   while the save reads the lights. A saved effect design opens the card page
   when every channel shows the same look, and the card page takes its colours
   from the first included channel. The Pattern Editor's SAVE updates the
   saved design it was opened from, and the card page closes after it. Home's
   Color Sequence says only the first three colours light. The Favorites
   picker says why it refuses a painted design. Files #191 and #192. No
   conflict.
2. `ac0fa3a4` — merge `feat/133-schedule-reliability` @ `b000d316`
   (`46aca0ab`, `3ba66232`, `e3e08ec5`, `b000d316`). **Power-on relights all
   channels after a timed OFF** (`46aca0ab`): when the last poll (at most 30
   seconds old) shows every channel off, the power circle's ON names every
   channel, as "All Channels On" does; otherwise it stays master-only, so a
   channel switched off on purpose stays off. **Expired lease rows are never
   re-sent** (`3ba66232`): the row builder skips a lease whose night is over,
   by the sweep's own rule (`isExpiredAt`). **The lease expiry sweep runs when
   the controller becomes reachable** (`e3e08ec5`): after 2 seconds ready, at
   most once every 30 seconds, through the ordinary sweep; the lease manager
   and the schedule sync now share one timer-table lock. Files #193 to #196.
   One conflict, in `docs/BUGS_AND_DEBT.md`: both branches had added entries
   at the top of P1 (132: #192, #191; 133: #193, #194). Resolved by keeping
   all four, in number order #191, #192, #193, #194, with every entry's text
   as on its own branch; no other line changed. #195 and #196 (P2) merged
   without conflict.
3. This note, with the ledger, FACTS and tracker corrections listed in its
   commit (docs only).

`46aca0ab` is in this history as its own commit, unchanged (parent
`3191e4b0`). No later commit on either branch touches its five files (section
8).

Against `build-131`, `lib/` changes in 19 files, +1,121 / −142: 132's 12
files (+635 / −104) and 133's 7 (+486 / −38). No `lib/` file is touched by
both branches.

- 132: `app_router.dart`; `features/dashboard/wled_dashboard_page.dart`;
  `features/design/` `apply_saved_design.dart`, `design_card_route.dart`
  (new), `design_providers.dart`, `per_pixel_payload_guard.dart`;
  `features/favorites/favorite_apply.dart`;
  `features/patterns/color_sequence_builder.dart`; `features/wled/`
  `colorway_effect_selector.dart`, `edit_pattern_screen.dart`,
  `pattern_theme_selection.dart`, `wled_payload_utils.dart`
  (`applyChannelFilterPerChannel` added; `applyChannelFilter` unchanged).
- 133: `features/dashboard/widgets/channel_selector_bar.dart`;
  `features/schedule/` `calendar_entry_lease_manager.dart`,
  `schedule_sync.dart`, `timer_table_write_lock.dart` (new);
  `features/voice/voice_providers.dart`; `features/wled/`
  `channel_power_payload.dart`, `wled_providers.dart`.

`test/`: 18 files (section 4). `docs/`: `BUGS_AND_DEBT.md` (#191 to #198),
this note, the +131 ledger row's Contents sentence, and FACTS row T-B3.
`git diff --stat build-131 -- pubspec.yaml lib/app_version.dart functions firestore.rules firestore.indexes.json storage.rules codemagic.yaml ios android esp32-bridge`
is EMPTY.

## 2. Release notes — build 133 (candidate, not shipped)

**What changed:** When the channels of your lights each show a different
look and you save it (Save As Custom Pattern, or Save from Now Playing), the
design now keeps each channel's own look, and applying it from My Designs or
tapping it as a favourite on Home brings each channel back as it was (the
direction an effect runs in is not restored). While the save reads your
lights, Home shows "Saving…"; if the lights cannot be read, nothing is saved
and Home says so. Opening the Pattern Editor from a saved design and tapping
SAVE now updates that design instead of making a copy. Home's Color Sequence
says only the first three colors light. After the lights turn off on a timer,
the power button turns every channel back on; a channel you switched off
yourself stays off. A one-night or Game Day look whose night is over is no
longer sent back to the controller, and the app clears it as soon as your
phone can reach the controller.

**Tester text:** none written for this build.

**Withdrawal text (return to the previous build), if needed:** Build 133 has
been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install
the previous build, 2.5.10 (368). Your schedules, teams, designs and
favorites stay. Four things go back to how they were: a design saved with a
different look on each channel plays the first channel's look on every
channel, and saving the current look stores only that first look; the
Pattern Editor's SAVE makes a copy ("Name 2") instead of updating the design;
after the lights turn off on a timer, the power button can bring them up with
every channel still dark (tap All Channels On); and a one-night or Game Day
look can light again the same day the next week if the app did not clear it
in time. Send reports to general@nex-genled.com with the date and time.

*If build 131 is never released to testers, "the previous build" for a tester
is 128 (2.5.10 (363)), and the withdrawal texts of builds 130 and 131 apply as
well.*

## 3. The customer-facing strings

Added by 132 (133 adds none):

- "Couldn't read your lights' current look, so nothing was saved. Try again."
  (Home, when the save cannot read the lights).
- "Saving…" (Home's bar and the Save As Custom Pattern button while the save
  waits; the same word the app already uses elsewhere).
- "Your lights use the first 3 colors. Colors 4 and up are dimmed here."
  (Home's Color Sequence, with more than three colours).
- "Favorites added from this list store colours and effects, not a painted
  picture, so this one can't be added here yet. You can still apply it any
  time from My Designs." (the Favorites picker's card, for a painted design;
  its snackbar form is `"<name>" is a per-pixel design.` followed by the
  first sentence).

`'Failed to save "$name": $error'` moved from the dashboard into
`design_providers.dart` with the same words.

## 4. Tests added, and by which branch

| Branch | Test files | Tests |
|---|---|---|
| `feat/132-saved-designs` | new: `test/features/dashboard/save_current_saving_state_132_test.dart`; `test/features/design/` `design_card_route_test.dart`, `save_current_look_per_channel_132_test.dart`, `saved_design_payload_pins_132_test.dart`, `saved_design_per_channel_apply_132_test.dart`; `test/features/patterns/color_sequence_limit_hint_132_test.dart`; `test/features/wled/` `apply_channel_filter_per_channel_132_test.dart`, `design_card_after_editor_save_132_test.dart`, `design_card_editor_handoff_132_test.dart`, `design_card_palette_wire_132_test.dart`, `edit_pattern_update_in_place_132_test.dart`, `favorites_picker_painted_refusal_132_test.dart`, `saved_design_card_route_132_test.dart`. Changed: `test/features/dashboard/save_custom_pattern_routes_to_designs_test.dart` (its fixture gained a controller; no assertion changed) | +103 |
| `feat/133-schedule-reliability` | new: `test/features/wled/master_power_relight_test.dart`; `test/features/schedule/` `lease_expired_rows_not_resent_test.dart`, `lease_sweep_on_ready_test.dart`. Changed: `test/features/schedule/calendar_entry_lease_manager_test.dart` (one test uses its file's fixed clock instead of the wall clock; its assertion is unchanged) | +61 |

Build 131's suite is 6,673 passing; each branch's own gate measured its
count (132: 6,776; 133: 6,734), so this candidate's expected count is 6,837
(section 7). Per-file counts are not listed because several files generate
tests in loops. Each branch wrote its tests first and showed them failing on
the old code; the evidence is in each branch's commits and report. 132's
saved-design, favourite and card payloads are pinned byte for byte against
build 131 and against `b716a325`.

## 5. Caveats, and known, not fixed

**(a) Designs saved before this build.** On build 131 and earlier, Save As
Custom Pattern and the Now Playing save stored the first channel's look on
every channel. Those designs still apply as one look; save the look again on
this build to keep each channel's own.

**(b) Direction.** The save stores each channel's direction, but no design
Apply sends direction (the #76 rule), so Apply does not restore it.

**(c) Older builds on other phones.** No minimum-build gate exists: nothing
makes an older build stop or update. A phone on build 131 or earlier applies
a mixed design as the first channel's look on every channel, and its lease
writes can still carry an expired lease's row.

**(d) Lease rows still carry no date (#196).** 133 narrows it but does not
close it: a row still fires again if no sweep lands before the same weekday
next week, for example a week with no session on the controller's network.

**(e) Power-on relight.** It acts only when the last poll, at most 30 seconds
old, shows every channel off; with an unknown or older read the ON stays
master-only. Off the home network the channel list comes from the display
fallback (#91). The stored OFF preset is not changed.

**(f) Pattern Editor layers 4 and up (#192).** Since `56741955`, saving in
place from a saved design's card page with the name unchanged removes layers
4 and up from the stored design. The lights never showed them.

**(g) An AI motion design edited by hand (#191).** The paint editor's Apply
shows a still picture, but Save keeps the motion. Open question for the owner
in the entry.

**Not in this build:**

- The card page's Apply drops the white LEDs on RGBW controllers (#197), and
  the main colour is lost on Fireworks (42), Juggle (64), Fireworks Starburst
  (89) and Fireworks 1D (90) (#198). Both filed 2026-11-26, both need a bench
  on WLED 0.15.4.
- A minimum-build gate: it does not exist (caveat c).
- Lumina chat storing "sunset to sunrise" as the creation day's clock times
  (#195).
- Cfg-only drift repair: a night re-sync that writes only the timer table,
  fix shape (a) of #193 (the automatic re-sync runs only 9:00–15:00).
- Sun-aware drift: the keep guard and the drift check cannot see sunrise and
  sunset rows (#194).
- Date-bounded lease rows (#196).
- The Settings sunrise-off toggle reads and rewrites the timer table outside
  the lock the lease sweep and the schedule sync now share
  (`lib/features/schedule/sunrise_off_service.dart`); not filed.
- The old 130 queue (healer re-read, lease sweep, tuner hardening, Info
  values), as listed for builds 130 and 131.
- Marching Stripes: not built.
- Preview work: none.

## 6. Bench pending (owner)

Build 132:

1. A mixed look (a different look on each channel) saves and applies per
   channel.
2. A single look saves and applies unchanged (it opens the card page).
3. A favourite of a mixed design, tapped on Home, applies per channel.
4. A Pattern Editor design applies unchanged.
5. "Saving…" shows while the save reads the lights.
6. With the controller unreachable, the save shows its message and saves
   nothing.

Build 133:

7. Preset 2 (the timed OFF), then the power circle: every channel relights,
   and a channel switched off on purpose stays off.
8. An expired lease is not re-sent.
9. The sweep runs after the phone joins the controller's Wi-Fi.

Carried from build 131:

10. Per-light brightness on Apply and Preview on lights.
11. Two-colour Glitter sparkles bright white.

## 7. Gates

To run on this note's commit, the candidate tip, `TZ=UTC0`, after
`flutter clean`, on Flutter 3.47.9 (the Codemagic pin; its own
`dart analyze`) and then 3.41.2, never at the same time, with
`pubspec.lock` and `analysis_options.yaml` restored after each run. The
results are reported with this branch and go into the ledger row when the
bump is tagged.

Expected, from the two branches' own gates:

| SDK | analyze | per-issue vs build 131 | TZ=UTC0 suite | golden | docs_guard |
|---|---|---|---|---|---|
| 3.47.9 | 0 errors / 12 warnings / 339 infos | build 131's 341 minus two `use_build_context_synchronously` infos in `wled_dashboard_page.dart` that 132 removed | 6,837 pass / 39 skip / 0 fail | 1 / 1 | 44 files / 143 facts / 0 / 0 |
| 3.41.2 | 0 errors / 12 warnings / 334 infos | build 131's 336 minus the same two | 6,837 pass / 39 skip / 0 fail | 1 / 1 | 44 files / 143 facts / 0 / 0 |

6,837 = 6,673 + 103 (132) + 61 (133).

## 8. Dropping the power-on fix before tagging

If the bench does not reproduce the dark power-on, run
`git revert 46aca0ab` on this branch before the bump: it reverts on its own
(no later commit touches its five files), and its test file
`master_power_relight_test.dart` goes with it, so the suite count drops by
that file's tests.
