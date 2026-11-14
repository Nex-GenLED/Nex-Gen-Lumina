# Build +128 candidate — `feat/128-entry-delete`

Assembled 2026-11-14 from `feat/127-table-ownership` at `de4766b` (the
build-127 candidate's tip, 2.5.10+127): dated calendar entries can be deleted
by hand again on a phone at the default text size, and through the Lumina AI
with a confirmation card, then these docs, then the version bump to
2.5.10+128 as the final commit. **Not tagged, not built by CI, not deployed.
No Firestore rules, functions or config write. No merge into main,
`feat/124-colour`, `feat/126-candidate` or `feat/127-table-ownership`. No
controller, bench unit or production system was contacted to assemble it; the
tests use fakes.** The tag waits for the owner's go.

## 1. What went in

1. `test(schedule)` — the Step 1 tests, written first and failing on
   `de4766b` (section 4): the dated-entry detail sheet pumped under the real
   glass dock at 393 x 852 for text scale 1.0, 1.3 and 2.0 and across the
   +120 large-text matrix.
2. `fix(schedule)` — the detail sheet draws above the glass dock, scrolls its
   details, and pins Edit This Day and Delete This Entry in a footer.
3. `feat(ai)` — Lumina deletes dated calendar entries: the model proposes,
   the app confirms. Schema, parser, resolver, driver branch, confirmation
   card, the brain's pre-tier, and the Step 4 tests.
4. `docs` (this file, FACTS T-D16 and T-L6) and the bump.

### Problem 1 — the manual route

`showScheduleDetailSheetForEntry` (lib/features/schedule/my_schedule_page.dart)
opened a `showModalBottomSheet` on the BRANCH navigator without
`isScrollControlled`. Two defects compounded: the branch navigator is a
sibling of the dock in `NavBarInsetShell`'s Stack and sits beneath it, so the
dock covered the sheet's bottom; and without `isScrollControlled` the sheet's
height is capped at 9/16 of the screen (about 479 pt on a 393 x 852 phone)
while the body was a plain Column with Edit and Delete LAST, so anything past
the cap was clipped silently. At the default text size on an iPhone 15 Pro
both buttons were clipped and under the dock; only at the second-smallest
text size did the content fit above it.

The fix: the sheet goes on the ROOT navigator (`useRootNavigator: true`, the
`showIpEntrySheet` precedent) with `isScrollControlled: true`. The caller's
context reports the dock plus the safe area as its bottom inset and the root
context the safe area alone; when the caller's inset exceeds the safe area a
dock is there and the sheet stops at its top edge, so no part of the sheet
shares a pixel with it (the dock stays visible under the barrier). The
details sit in a loose-fit `Flexible` `SingleChildScrollView` that scrolls
only when they outgrow the screen; Edit and Delete are a footer below it.
The confirmation dialog ("Delete this entry?" … Cancel / Delete) and the
"Entry deleted" / "Could not delete entry" snackbar are untouched.
`_DetailRow`'s value now wraps instead of overflowing the row by 2 px at
320 pt / 2.0x, which the matrix measures now that the sheet no longer clips.

### Problem 2 — the AI route

**Where the action list lives.** Entirely on the phone. The Smart-tier
system prompt in `lib/lumina_ai/lumina_ai_service.dart` declares the JSON
contract (`wled`, `schedulingIntent(s)`, `ephemeralSession`,
`recurringSportsAutopilot`, and now `deleteCalendarEntries`), assembled from
per-intent fragments (`SchedulingIntent.schemaPromptFragment`,
`EntryDeleteIntent.schemaPromptFragment`). `CloudAIProcessor`
(lib/features/ai/cloud_ai_processor.dart) extracts the fields into
`LuminaCommandResult`, and `LuminaConversationDriver.handleResult`
(lib/features/ai/lumina_conversation_driver.dart) dispatches each one to its
branch. The Cloud Function `claudeProxy` (functions/src/claudeProxy.js) is a
pass-through: it forwards `model`, `system` and `messages`, prepends a clock
preamble, enforces an allow-list of models and a token cap, and never reads
the schema. **Nothing in functions/ changes and nothing needs deploying.**

**Where the refusal came from.** No literal in the code matches "I can't do
that, request something different". The Smart prompt had no delete action,
so the model fell to its scope rule — the only refusal literal is the
preamble's "I specialize in lighting — I'm not able to help with that. What
can I light up for you?" — and paraphrased it. Two phone-side gates also
stood in the way of any future delete action: `_classifyPromptTier` routed a
short request ("delete the entries you made", five words) to the Fast tier,
whose prompt has no scheduling contract at all; and `LuminaBrain.chat` runs
team, holiday, theme and compound-command resolution BEFORE the cloud, so
"delete the Chiefs entries" would have composed a Chiefs design locally.
Build 128 adds `isEntryDeleteRequest` (a delete verb plus a schedule noun,
pure) and uses it in both places: such a request routes to the Smart tier and
skips the local tiers.

**Design rules, as built.**

- Dated calendar entries only. The intent has `target: "recurring"` for a
  repeating schedule; the app refuses it and names the manual route. Nothing
  here touches `ScheduleItem`.
- Scope: entries Lumina wrote (`sourceTag lumina_ai`) and hand-made entries
  (`type user`, no source tag). Any entry that holds a Game Day (whatever its
  type — an edited Game Day row is type user and keeps the tag), and any
  other automatic entry (autopilot, neighbourhood sync, type auto), is
  refused and pointed at Game Day settings. Holiday defaults are not offered.
- The model proposes, the app confirms. The model emits a DESCRIPTION
  (`scope: date | range | lumina_all | unclear`, strict dates, an optional
  name filter) and never sees the calendar. `resolveEntryDeletion` (pure,
  lib/features/ai/entry_delete_resolver.dart) turns it into a proposal; the
  app posts a confirmation card (`EntryDeleteConfirmCard`) with the count, the
  dates and the names, and Delete / Cancel. Nothing is removed until Delete
  is tapped. The card is a real card in both chat surfaces (the full screen
  and the dashboard sheet) — the two-turn text fallback was not needed.
- Removal goes through `CalendarScheduleNotifier.removeEntryById` one entry
  at a time, each followed by `saveCalendarEntries` — the same path as the
  detail sheet's button — so the night's lease is released or re-derived
  exactly as for a manual delete (`RiverpodLuminaEntryDeleteServices`).
- At most 31 entries per confirmed request (`kEntryDeleteMaxPerRequest`);
  the earliest 31 by date are offered and the card says how many more match.
- Ambiguous or empty: the parser degrades a missing or malformed date to
  `unclear` and the app asks; a window with nothing deletable says so and
  names the window. Nothing is ever guessed.
- functions/: no action list there, nothing to deploy. If `claudeProxy` were
  ever to reject an unknown field it would do so for the whole request and
  the processor's existing error handling would answer "I'm having trouble
  connecting right now…"; it does not inspect the body today.

## 2. Release notes — 2.5.10 build 128 (candidate, not shipped)

**What changed:** Tap a one-night entry on your Schedule and the sheet now
opens above the bottom bar with Edit This Day and Delete This Entry always in
reach, at any text size. And you can ask Lumina to delete one-night entries:
"delete the entries you created for me", "remove Friday's entry", "cancel what
you set up for Nov 20 to Nov 27". Lumina shows you exactly which entries it
found — the count, the dates and the names — and nothing is removed until you
tap Delete. Game Day entries and repeating schedules are not deleted this
way; Lumina tells you where to manage those.

**Tester text:** written with the build's ledger row, after the tag.

**Withdrawal text (return to 127), if needed:** Build 128 has been withdrawn.
Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous
2.5.10 build. Your schedules, teams, designs and favorites stay. Two things go
back to how they were: on some phones the entry sheet's Edit and Delete
buttons sit behind the bottom bar at the default text size (lower the text
size in Settings → Display to reach them), and Lumina no longer deletes
entries for you (open Schedule, tap the entry, then Delete This Entry). Send
reports to general@nex-genled.com with the date and time.

## 3. The customer-facing strings (exact)

All from `lib/features/ai/entry_delete_resolver.dart` unless noted.

**The confirmation card** (`EntryDeleteProposal.leadText`, then one line per
entry, then the buttons `Cancel` and `Delete`):

> Delete this entry? Nothing is removed until you tap Delete.

> Delete these N entries? Nothing is removed until you tap Delete.

appended when the window also holds Game Day entries:

> 1 Game Day entry stays; manage it in Game Day settings.

> M Game Day entries stay; manage those in Game Day settings.

appended when more than 31 match:

> I can remove up to 31 at a time; K more match. Ask again afterwards for the rest.

each entry line (`EntryDeleteProposal.lines`): `Fri, Nov 20 · Chiefs Game Night`

after Delete (`entryDeleteOutcomeText`):

> Deleted 1 entry.

> Deleted N entries.

> Deleted D of N entries; F couldn't be removed. Check your connection and try again.

after Cancel (`kEntryDeleteCancelled`):

> Okay, nothing was deleted.

the decided card shows `Deleted` or `Cancelled` in place of the buttons.

**The refusal for Game Day entries** (`kEntryDeleteGameDayRefused`, when the
window holds only Game Day entries):

> Those are Game Day entries, so I can't delete them from here. You can manage them in Game Day settings.

**The refusal for a repeating schedule** (`kEntryDeleteRecurringRefused`):

> I can't delete a repeating schedule from here. Open My Schedule, tap the schedule, then Delete Recurring Schedule.

**The no-match reply** (`_nothingReply`):

> I couldn't find any entries to delete on Fri, Nov 20.

> I couldn't find any entries to delete from Nov 20 to Nov 27.

> I couldn't find any entries to delete that I created.

> I couldn't find an entry called "Halloween" on Fri, Nov 20.

appended when the window holds Game Day entries:

> The Game Day entry there stays; manage it in Game Day settings.

> The M Game Day entries there stay; manage those in Game Day settings.

**The question** (`kEntryDeleteUnclear`):

> Which entries should I delete? Give me a day, a range of dates, or say "everything you created".

**The fallback on a surface without the delete service**
(`kEntryDeleteNotAvailable`; neither shipped surface hits it):

> I can't delete calendar entries from here yet. Open Schedule, tap the entry, then Delete This Entry.

The model's own one-line `message` ("Here's what I found — confirm below.")
is NOT shown; the card's lead line replaces it.

## 4. The Step 1 tests, failing first

`test/features/schedule/entry_detail_sheet_nav_bar_test.dart`, five tests,
run on `de4766b` before any fix (3.41.2, log in the session scratchpad under
`gates/128-step1/step1_at_de4766b.txt`). Each test stops at its first failed
assertion, so one reason is shown per test:

| Test | First failure on de4766b |
|---|---|
| 393x852 @ 1.0 | a tap at (196.5, 685.8) does not reach "Edit This Day" — the dock takes it |
| 393x852 @ 1.3 | "Edit This Day" at (21, 694.8)–(372, 744.8) is covered by the dock at (0, 718)–(393, 852) |
| 393x852 @ 2.0 | "Edit This Day" at (21, 835.8)–(372, 899.8) is not fully on the 393x852 screen |
| large-text matrix, reachability | 320x568 @ 1.0: "Edit This Day" at (21, 537.5)–(299, 585.5) is not fully on the 320x568 screen |
| large-text matrix, overflow | 320x568 @ 1.0: a RenderFlex overflowed by 203 pixels on the bottom |

All five pass on the candidate tip (3.41.2 and 3.47.9; section 6).

## 5. Other bottom sheets with the same pattern (not changed)

`showModalBottomSheet` calls in lib/ without `isScrollControlled: true`,
read for whether a primary action is the last element and whether the dock
can cover it (the day sheet, which has `isScrollControlled` but opens on the
branch navigator, is noted at the end). Not changed in this candidate;
reported as asked.

Read from the code at 1.0 text scale (not pumped); heights are estimates.
The dock band is 100 pt plus the bottom safe area (about 134 pt on a 390 x
844 phone); the 9/16 cap is about 475 pt there and 375 pt on 375 x 667.

| file:line | sheet | primary action last? | bottom padding | opens under the dock? | can the dock cover it? |
|---|---|---|---|---|---|
| lib/features/dashboard/main_scaffold.dart:424 | demo "Ready for your own lights?" | no (consultation button, then "Keep exploring") | fixed 32 | yes from a pattern card's "Talk to us" (explore tab); no from the demo banner (root) | **yes** on the explore path: the dock covers "Keep exploring" and part of the consultation button |
| lib/features/dashboard/widgets/channel_selector_bar.dart:514 | "… isn't in your shows" | no ("Include in Shows", then "Leave it out") | SafeArea | yes (dashboard, explore) | marginal: fits at 390 x 844; overflows about 28 pt at 375 x 667, 8 pt of it under the dock |
| lib/features/game_day/live_scoring_prompt.dart:71 | "… has a game today, live scores?" | **yes** ("No thanks" / "Let's go!") | SafeArea | yes (after a pattern-card apply) | **yes**: about 375 pt of content plus the inset is over the cap; the button row is under the dock on a 667 pt phone and 10 to 35 pt under on 844 pt |
| lib/features/installer/screens/controller_setup_screen.dart:275 | "Add Controller" | none | SafeArea | no (installer wizard, root) | no |
| lib/features/installer/screens/controller_setup_screen.dart:1651 | "Replace Photo" | none | SafeArea | no (root) | no |
| lib/features/installer/screens/zone_configuration_screen.dart:737 | "Add Secondary Controller" | none | 24 | no (root) | no; four or more controllers overflow the cap off screen regardless |
| lib/features/inventory/corporate/warehouse_screen.dart:135 | "Select PO" | none | SafeArea | no (root) | no; five or more POs overflow the cap regardless |
| lib/features/inventory/dealer/inventory_screen.dart:173 | dealer filters | none | 16 | unreachable (no importer) | no, unreachable |
| lib/features/neighborhood/neighborhood_sync_screen.dart:1248 | "+" menu | none | SafeArea | yes (home tab) | no, fits |
| lib/features/neighborhood/widgets/schedule_list.dart:131 | "Create Schedule" chooser | none | SafeArea | yes, but hidden (`kGroupScheduleVisible` false) | no today; overflows above 1.0 text if shown |
| lib/features/neighborhood/widgets/schedule_list.dart:203 | schedule details, opt out | **yes** ("Opt Out of This Event") | 24, no inset | yes, hidden by the same flag | **yes** if the flag is ever on: the button sits inside the dock band |
| lib/features/properties/my_properties_screen.dart:197 | "Link Controllers to …" | none (switch list) | `navBarTotalHeight + 16` | yes (system tab) | **yes** with three or more controllers: the list's 0.4-screen box plus the inset exceeds the cap and the last tile ends under the dock |
| lib/features/sales/screens/day2_wrap_up_screen.dart:277 | photo source | none | SafeArea | no (root) | no |
| lib/features/sales/screens/estimate_wizard/widgets/wizard_photo_capture.dart:16 | photo source | none | SafeArea | no (root) | no |
| lib/features/schedule/calendar_entry_editor.dart:410 | "Save changes for…" | no (scope cards, then Cancel) | SafeArea | no: opened from the entry editor, which the root-navigator detail sheet opens | no |
| lib/features/site/settings_page.dart:369 | "Contact Nex-Gen Support" | none | SafeArea | yes (system tab) | no, fits |
| lib/features/wled/colorway_effect_selector.dart:1306 | save-to target | none | SafeArea, root navigator | no | no |
| lib/features/wled/colorway_effect_selector.dart:1413 | Game Day team picker | none | SafeArea, root navigator | no | no |
| lib/features/wled/pattern_theme_selection.dart:1127 | "Choose Solid Color" | no (swatches, then Cancel) | `navBarTotalHeight + 20` | yes (explore tab) | marginal: two swatch rows at 375 x 667 put Cancel's lower edge about 13 pt under |
| lib/screens/commercial/fleet/FleetDashboardScreen.dart:355 | filter locations | none | SafeArea | no (root) | no |
| lib/screens/commercial/fleet/FleetDashboardScreen.dart:1086 | "Push to Fleet" | none | SafeArea | no (root) | no |
| lib/screens/commercial/onboarding/screens/channel_setup_screen.dart:55 | "Select Channel Role" | none | SafeArea | no (root) | no; six roles overflow the cap at 375 x 667 |
| lib/screens/commercial/schedule/CommercialScheduleScreen.dart:402 | "Copy day to…" | none | SafeArea | no (root) | no; overflows the cap at 375 x 667 |
| lib/screens/commercial/schedule/CommercialScheduleScreen.dart:992 | "Assign Design" | **yes** (Cancel / Assign) | SafeArea, no `viewInsets` | no (root) | no, but the keyboard covers the fields and the Assign row |
| lib/widgets/connection_status_indicator.dart:232 | connection status | yes when offline ("Retry Connection") | SafeArea | unreachable (no importer) | no, unreachable; would be covered if mounted in a tab |
| lib/widgets/favorites_grid.dart:140 | favourite tile actions | yes ("Remove from My Favorites" tile) | SafeArea | yes (dashboard) | no, fits |
| lib/widgets/house_photo_uploader.dart:186 | "Add House Photo" | none (four option tiles, "Trace Roofline" last) | SafeArea | yes (Edit Profile, system tab) | **yes**: about 480 pt of content; "Trace Roofline" is under the dock on 844 pt and off screen on 667 pt |

The DAY sheet (`showDayDetailSheet`, lib/features/schedule/my_schedule_page.dart:1841)
has `isScrollControlled` but opens on the branch navigator; it pads by
`24 + navBarTotalHeight(ctx)`, which there is the dock's full height, so its
scrolling list ends above the dock and the dock cannot cover its last row.
Its background runs under the dock (cosmetic), and a very full day can grow it
to full height with only 12 pt of top padding.

Worth fixing next, in this order: live_scoring_prompt.dart:71, house_photo_uploader.dart:186, the demo sheet's explore path (main_scaffold.dart:424), my_properties_screen.dart:197.

## 6. Phone checklist (build 128 on the phone)

1. Schedule tab → tap a day with one one-night entry (or open a multi-entry
   day and tap a row). The sheet opens above the bottom bar; Edit This Day
   and Delete This Entry are visible without scrolling. Repeat with iOS text
   size at the largest non-accessibility step: the details scroll, the two
   buttons stay put at the bottom of the sheet.
2. Delete one by hand: Delete This Entry → "Delete this entry?" → Delete →
   "Entry deleted"; the day no longer shows it. Anything else on that day
   stays.
3. Lumina (full screen): "delete the entries you created for me". A card
   lists the count, the dates and the names, with Cancel and Delete. Tap
   Cancel → "Okay, nothing was deleted."; the entries are still there.
4. Ask again → tap Delete → "Deleted N entries."; the Schedule tab no longer
   shows them. Any hand-made or Game Day entry sharing those nights stays.
5. Lumina (dashboard sheet): "remove Friday's entry" → the same card.
6. "delete my nightly schedule" → the repeating-schedule refusal; nothing
   changes. A day holding only a Game Day entry → the Game Day refusal.

## 7. Known, not fixed in this candidate

- **The model decides the dates.** "Friday" or "this week" is resolved by the
  model against the clock preamble `claudeProxy` prepends; a wrong resolution
  shows up as the wrong dates on the card, which is why the card lists them
  and nothing is removed until Delete. The app does not second-guess the
  dates.
- **A Fast-tier reply cannot delete.** The gate is `isEntryDeleteRequest` (a
  delete verb plus a schedule noun). A phrasing with neither — "scrap
  Friday", "undo that" — still goes where it went before.
- **One Firestore write per entry.** Removal reuses `removeEntryById`, which
  saves after each removal; 31 entries are 31 saves. Deliberate: the brief
  asked for the manual path, not a batch.
- **"Everything you created" is today and later.** Past Lumina nights are
  not offered; a date or range names them explicitly if wanted.
- **The confirmation card is not persisted.** Like every chat message it
  lives in the session; close the chat before tapping Delete and the proposal
  is gone (nothing was removed).
- **The other bottom sheets in section 5** are reported, not changed.
- **No deploy, no functions change.** `claudeProxy` is a pass-through; if it
  ever validated the reply body it would need the new key allowed, and the
  processor's existing connection-error message would be what the customer
  saw until then.
- **Nothing has run on a phone or against a controller.** The suite proves
  the app's side with fakes; section 6 is the checklist for the phone.

## 8. Gates

Run on the candidate tip, one at a time, free space on C: checked before each
SDK (stop under 10 GB). Logs under the session scratchpad `gates/128-tip/`.

Filled in by the integration report.

| SDK | pub get | analyze | TZ=UTC0 suite | golden | docs_guard |
|---|---|---|---|---|---|
| 3.47.9 | | | | | |
| 3.41.2 | | | | | |
| 3.50.0 (information) | | — | | — | — |

Not built by CI, not tagged, not deployed as of 2026-11-14.
