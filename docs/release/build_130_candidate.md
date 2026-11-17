# Build +130 candidate — `fix/entry-sheet-dead-ref`

Assembled 2026-11-17 from `feat/124-colour` at `a9cfc49` (docs only on top of
the build-129 tag's commit `37cf275`, 2.5.10+129): the entry detail sheet's
Delete This Entry works again when the entry is opened from a day sheet, then
the version bump to 2.5.10+130 as the final commit. **Tagged `build-130` at
`321dc7a` (the bump commit; convention 1); the tag matches Codemagic's
`build-*` trigger for the iOS Release workflow; expected TestFlight 2.5.10
(365), not confirmed here (section 7). Not released to testers. Android not built. No Firestore rules, functions or
config write. `feat/124-colour` was fast-forwarded to it; no merge into main.
No controller, bench unit or production system was contacted to assemble it;
the tests use fakes.**

Build 129 (tag `build-129` = `37cf275`, TestFlight 2.5.10 (364)) was built and
installed on the owner's phone for the bench and never released to testers, so
build 130 is the first tester build to carry 129's changes as well.

The queue that was planned for build 130 (healer re-read, lease sweep, tuner
hardening, Info values) is **not** in this build; it moves to build 131.

## 1. What went in

`git log --first-parent 37cf275..321dc7a` (7):

1. `927bf99`, `ebf24fe`, `e1da1ec`, `a9cfc49` — docs only (the ledger rows
   for 126–129, TestFlight numbers, release-notes entries for 126 and 128,
   candidate notes 126–129). Already on `feat/124-colour` before this build.
2. `c16864a` `test(schedule)` — `test/features/schedule/entry_sheet_dead_ref_test.dart`,
   written first and failing on the old code (section 4).
3. `0a364ce` `fix(schedule)` — the entry detail sheet acts through its own
   ref, never a popped caller's (`lib/features/schedule/my_schedule_page.dart`,
   +45 / −38; `entry_detail_sheet_nav_bar_test.dart` one line).
4. `321dc7a` `chore(version)` — 2.5.10+130 in `pubspec.yaml` and
   `lib/app_version.dart` (`kAppVersion`).

Against `build-129`, outside `docs/`: 5 files, +295 / −39
(`my_schedule_page.dart`, the two schedule tests, `pubspec.yaml`,
`lib/app_version.dart`).
`git diff --stat build-129 build-130 -- functions firestore.rules firestore.indexes.json codemagic.yaml ios android`
is EMPTY.

### The bug

The Schedule tab's week strip and its month (and 3-month, 6-month, year)
view open the **day sheet** for the tapped day. Tapping a row there popped
the day sheet and passed that sheet's own `Consumer` ref on into
`showTimelineEntryDetail` → `showScheduleDetailSheetForEntry` →
`_DeleteEntryButton`. After the "Delete this entry?" confirmation,
`ref.read(calendarScheduleProvider.notifier)` threw
`Bad state: Cannot use "ref" after the widget was disposed` (flutter_riverpod
2.6.1 throws in release builds too). The exception was uncaught: no snackbar,
the sheet stayed open, nothing was written to Firestore, and the entry stayed
on the calendar. It has been there since `c9d56b8d` (build 82). Only one path
handed the sheet a live ref: tapping the day card below the week strip for a
day with a single entry.

The owner hit it three times on 2026-11-17 on 2.5.10+129 (recorded in
`users/{uid}/debug_errors`); the same StateError appears 18 times across 10
accounts since 2026-10-20.

Edit This Day never failed this way: both editors are `ConsumerStatefulWidget`s
that ignore the ref they are handed. Its chain is rewritten anyway, so the
sheet borrows no ref at all.

### The fix

- `showScheduleDetailSheetForEntry(..., bool editable = false)` replaces
  `WidgetRef? ref`; delete is offered when `editable` and the sheet has a
  calendar entry or a recurring schedule.
- `showTimelineEntryDetail(context, entry, dateKey, timeFormat:)` takes the
  time format as a value instead of reading it through a ref.
- `_EditEntryButton` and `_DeleteEntryButton` are `ConsumerWidget`s and read
  through their own ref. Delete captures the Navigator and the
  ScaffoldMessenger before the first await and keeps the `mounted` checks
  after every await.
- `_DayHeroCard` and `showTimelineEntryDetail` pass `editable: true` (the
  same two callers that used to pass a ref).

No layout, copy, lease-manager, calendar provider, rules or functions change.
A working delete goes through `removeEntryById` unchanged: it releases the
night's lease exactly as the detail sheet's delete did in build 128.

## 2. Release notes — 2.5.10 build 130 (candidate, not shipped)

**What changed:** Delete This Entry now works when an entry is opened from the week strip or month view.

**What changed (from build 129, carried in this build):** Brightness
patterns now light up the way their cards show them. Each white under
Explore › Architectural Downlighting has a Brightness Patterns folder with
eight cards, led by two new waves (Wave · 6 lights and Wave · 18 lights).
Every brightness card has an Adjust link: the brightest and dimmest level,
how many lights one cycle spans, the shape (Wave, Ramp, Steps or Custom), the
starting light, or tap single lights to set their own level. A brightness
pattern can be saved to My Designs, and scheduling it follows the same rules
as any painted design. In Design Studio, single lights can be made dimmer or
brighter than their neighbours (Pixel brightness, with Dim, Full and a Ramp
across a selection). Looks that use the Palette effect now spread their
colours along the lights instead of showing one still colour, so saved looks
that use Palette look different. When the controller's timer has no room
left for a schedule, My Schedule now says so in its own words and changes
nothing.

**New wording testers may see (from build 129, exact):** "Your controller's
timer is full right now, so nothing was changed. Remove a schedule, or wait
until tonight's calendar lighting ends, then tap Retry."

**Tester text:** none written for this build.

**Withdrawal text (return to 128), if needed:** Build 130 has been withdrawn.
Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous
2.5.10 build. Your schedules, teams, designs and favorites stay. Three things
go back to how they were: Delete This Entry again does nothing when the entry
is opened from the week strip or month view (ask Lumina instead, for example
"remove Friday's entry"); the brightness patterns light as one dim run instead
of the pattern on their card, and the Wave cards and the Adjust link are gone;
and Design Studio no longer sets a brightness per light. Send reports to
general@nex-genled.com with the date and time.

*129 was never on TestFlight for testers, so "the previous 2.5.10 build" for a
tester on 130 is 128 (TestFlight 363).*

## 3. The customer-facing strings (exact)

None added or changed by the fix. "Delete this entry?", "Entry deleted" and
"Could not delete entry" are unchanged; the difference is that the delete now
reaches them from the day sheet path. Build 129's strings are in
`docs/release/build_129_candidate.md`.

## 4. The test, failing first

`test/features/schedule/entry_sheet_dead_ref_test.dart` drives the real
`MySchedulePage` under the glass dock with the large-text harness overrides;
the calendar notifier is a recording subclass (it records `removeEntryById`
and never touches Firestore, a lease or a controller).

1. "the day sheet path deletes: week strip -> day sheet -> row -> Delete This
   Entry -> confirm removes that row and says so"
2. "the day sheet path edits: Edit This Day closes the detail sheet and opens
   the entry editor"
3. "the day-card path keeps working: a single-row day opens its detail from
   the card, and Delete removes it"

On `a9cfc49` plus the test only (3.47.9), test 1 failed with the fleet's
error:

```
Bad state: Cannot use "ref" after the widget was disposed.
#2 _DeleteEntryButton._confirmAndDelete (package:nexgen_command/features/schedule/my_schedule_page.dart:2347:12)
Expected: [(String, String):(2026-11-17, lumina_1794403737068_6)]   Actual: []
```

Tests 2 and 3 passed on the old code too. After the fix: 8 / 8 (the three new
tests and the five detail-sheet nav-bar tests).

## 5. Known, not fixed in this candidate

The fix branch's sweep of `lib/` found the same shape elsewhere; none is
changed here (full list in the fix report, session d7922f9c scratchpad
`ENTRY_SHEET_DEAD_REF_FIX_REPORT_2026-11-17.md`):

- `lib/features/schedule/schedule_overload_banner.dart` — `_CleanupSheet`
  stored the banner's ref and read it after the awaited deletes. Reproduced
  and fixed on `fix/ref-after-await-sweep`, which is **not** in this build.
- The Lumina entry delete (`lib/features/ai/lumina_conversation_driver.dart`,
  reached through `entry_delete_services.dart`) reads through a ref after the
  awaited deletes and throws if the Lumina surface is closed mid-delete.
  Reproduced and fixed on the same branch; **not** in this build.
- `lib/features/installer/installer_setup_wizard.dart` — `Navigator.pop`,
  then an await, then `resetInstallerWizardState(ref)` with no mounted check
  (three places). Not reproducible with real timing; left unchanged.
- About 80 further reads of a `WidgetRef` after an await with no mounted
  check, listed in the fix report.

The build-130 queue that was planned before this build (healer re-read,
lease sweep, tuner hardening, Info values) moves to build 131.

## 6. Phone checklist (build 130 on the phone)

1. Schedule tab → tap a day in the week strip that has two or more one-night
   entries → the day sheet opens → tap a row → the entry's sheet opens →
   Delete This Entry → "Delete this entry?" → Delete → "Entry deleted"; the
   day no longer shows it, the other entry stays.
2. Switch the calendar to Month, tap a day with an entry → the day sheet →
   row → Delete This Entry → confirm → "Entry deleted".
3. The same row → Edit This Day → the entry editor opens.
4. A day with a single entry: tap its card below the week strip → the entry's
   sheet → Delete works as in build 128.
5. Build 129's checks: `docs/release/build_129_candidate.md` and its bench
   note.

## 7. Gates

Run on the tagged commit `321dc7a`, Flutter 3.47.9 (the Codemagic pin),
`TZ=UTC0`, after `flutter clean`; free space on C: checked before each step
(stop under 10 GB). `pubspec.lock` and `analysis_options.yaml` (rewritten by
3.47.9's `pub get`) restored afterwards; worktree clean. Logs under this
session's scratchpad `gates/bump_3479/`.

| SDK | pub get | analyze | TZ=UTC0 suite | golden | docs_guard |
|---|---|---|---|---|---|
| 3.47.9 | exit 0 | 0 errors / 12 warnings / 341 infos | 6,655 pass / 39 skip / 0 fail (17:32–17:54Z) | 1 / 1 | 44 files / 143 facts / 0 failures / 0 warnings |

The analyze count is from the 3.47.9 SDK's own `dart analyze`: that SDK
copy's `flutter analyze` wrapper stops before analysing ("Flutter failed to
list directory … Graphic Bezel.imageset", a path of about 260 characters
inside the SDK copy), as on the fix branch earlier the same day. It is the
same analyzer and the same `analysis_options.yaml`; the per-issue list is identical to the fix branch's 3.47.9 record on `0a364ce` (empty diff), and the totals match build 129 (`37cf275`).
3.41.2 and 3.50.0 were not run for the tag (the fix branch's 3.41.2 run on
`0a364ce` was analyze 0 / 12 / 336 and suite 6,655 / 39 / 0).

Tagged `build-130` at `321dc7a` on 2026-11-17 17:58:30Z (11:58:30 CST; annotated, tag object `fd60654`), pushed 17:58:45Z. As of 18:16Z (18 minutes after the push) no Codemagic check-run had appeared on `321dc7a` on GitHub (build-129's appeared 14 s after its tag); whether Codemagic started the iOS Release build is not confirmed here. Not released to testers; Android not built.
