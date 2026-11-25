# Build 131 candidate — `feat/131-candidate`

Assembled 2026-11-24 (CST) on the branch `feat/131-candidate`, cut from
`feat/124-colour` at `a9c63c2` (docs only on top of the build-130 tag's
commit `321dc7a`). Four finished fix branches merged with `--no-ff`, one at a
time, each at the tip named below, with no conflicts. **Tagged `build-131`
at `3191e4b`, the bump commit `chore(version): 2.5.10+131` that follows this
note (convention 1); the tag matches Codemagic's `build-*` trigger for the
iOS Release workflow; TestFlight 2.5.10 (368) (section 7).** No Firestore
rules, functions, indexes or config write. No
controller, bench unit or production system was contacted to assemble it;
the tests use fakes. No merge into main.

The queue that build 130's note moved to build 131 (healer re-read, lease
sweep, tuner hardening, Info values) is **not** in this candidate.

## 1. What went in

`git log --first-parent a9c63c2..bac1d61`:

1. `3fb5816` — merge `fix/relay-timing-test` @ `a0e4c18` (`1444540`,
   `a0e4c18`). **Test-only:** the relay fail-fast test (the flaky failure of
   Codemagic build 366) and the auth hanging flag-write test run on fake time
   instead of a wall-clock bound.
2. `9af72d7` — merge `fix/ref-after-await-sweep` @ `f3b4bbe` (`d2e510e`,
   `d818fa3`, `9331945`, `f3b4bbe`). My Schedule's overload **Clean Up**
   sheet finishes its deletes, and Lumina's entry delete still reports what
   it removed, when their screen closes mid-delete: both read through a ref
   after an await.
3. `f39dbc6` — merge `fix/design-apply-brightness` @ `4d01aa6` (`c0cc012`,
   `913d29a`, `bb83875`, `4d01aa6`). Applying a Design Studio design
   (Apply, Preview on lights) sends each light at its own brightness, as
   the scheduled preset already did (`g.color` → `g.litColor`).
4. `bac1d61` — merge `fix/glitter-white-sparkle` @ `5ef987c` (`1985fb3`,
   `11796a2`, `349529a`, `5ef987c`). Two-colour Glitter sparkles bright
   white again, as in build 123: a revert of build 124's `2c43e55`.
5. This note (docs only).

Against `build-130`, `lib/` changes in 4 files, +17 / −40:

- `lib/features/ai/lumina_conversation_driver.dart` — the entry delete takes
  its conversation thread before the removals (sweep).
- `lib/features/schedule/schedule_overload_banner.dart` — `_CleanupSheet` is
  a `ConsumerStatefulWidget` and reads both notifiers through its own ref
  before the first delete (sweep).
- `lib/features/design/manual_editor/design_apply.dart` — one line,
  `_rgbw(g.color)` → `_rgbw(g.litColor)` (design-apply-brightness).
- `lib/features/wled/wled_payload_utils.dart` — the Glitter revert; the file
  is byte-identical to its state before `2c43e55` (blob `6714776a`).

`test/`: 10 files (section 4). `docs/`: the base's three docs files
(`BUILD_LEDGER.md`, `guides/internal/31-release-notes.md`,
`release/build_130_candidate.md`), then `FACTS.md` row T-E6 (Glitter revert
built, not shipped), `release/build_129_candidate.md` item 6 (per-light
brightness), and this note.
`git diff --stat build-130 bac1d61 -- pubspec.yaml lib/app_version.dart functions firestore.rules firestore.indexes.json codemagic.yaml ios android`
is EMPTY.

## 2. Release notes — build 131 (candidate, not shipped)

**What changed:** Glitter on a two-colour design sparkles bright white again,
as it did before build 125. In Design Studio, lights you set dimmer or
brighter on their own (Pixel brightness: Dim, Full or a Ramp) now light at
that brightness when you tap Apply or Preview on lights, not only when the
design runs on a schedule. Clean Up on an overloaded schedule now finishes
even if you leave the screen while it runs, and when you ask Lumina to delete
entries it still tells you what it removed if you close it straight after
confirming.

**Tester text:** none written for this build.

**Withdrawal text (return to the previous build), if needed:** Build 131 has
been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install
the previous build. Your schedules, teams, designs and favorites stay. Three
things go back to how they were: Glitter sparkles in the design's second
colour instead of white; Design Studio's per-light brightness reaches the
lights only when the design runs on a schedule, not on Apply; and Clean Up
can stop part-way if you leave the screen while it runs (open My Schedule and
check what is left), and Lumina may not say what it deleted if you close it
straight after confirming. Send reports to general@nex-genled.com with the
date and time.

*If build 130 is never released to testers, "the previous build" for a tester
is 128, and build 130's own withdrawal text applies as well.*

## 3. The customer-facing strings

None added or changed. The `lib/` diff changes no string literal.

## 4. Tests added, and by which branch

| Branch | Test files | Tests |
|---|---|---|
| `fix/relay-timing-test` | `test/models/remote_command_status_test.dart`, `test/features/setup_auth/auth_rows_14_17_test.dart` (rewritten, same count) | +0 |
| `fix/ref-after-await-sweep` | `test/features/schedule/schedule_overload_cleanup_dead_ref_test.dart` (1), `test/features/ai/entry_delete_dismissed_surface_test.dart` (2) | +3 |
| `fix/design-apply-brightness` | `test/features/design/design_apply_pixel_brightness_test.dart` (8), `test/features/design/manual_editor_pixel_brightness_apply_test.dart` (3), helper `test/helpers/per_pixel_wire.dart` | +11 |
| `fix/glitter-white-sparkle` | `test/features/wled/glitter_white_sparkle_test.dart` (6), `test/features/wled/glitter_revert_non_regression_test.dart` (2); `test/features/wled/glitter_sparkle_colour_124_test.dart` (4) deleted | +4 |

Build 130's suite is 6,655 passing; this candidate's is 6,673 on both SDKs
(section 7). Each fix branch wrote its tests first and showed them failing on
the old code; the evidence is in each branch's commits and report.

## 5. Caveats, and known, not fixed

**(a) Glitter presets already on a controller.** Schedule presets and lease
looks saved by builds 124 to 130 keep the coloured Glitter sparkle until the
next schedule sync or until the entry is re-added. In detail:

- Schedule pattern presets (slots 10–25) are re-saved on every full schedule
  sync: any schedule change, Sync or Retry on My Schedule, or an owed
  automatic re-sync. A normal launch runs one only when a sync is owed, and
  the launch check compares timer rows, not colours, so it does not force
  one.
- Lease looks (one-night looks, Game Day calendar entries) are saved once,
  when the entry is created, so they keep the coloured sparkle until the
  entry ends or is deleted and added again.
- A snapshot scene captured from the lights on builds 124 to 130 while
  Glitter was showing holds the second colour as its own third colour, and
  keeps it. Any design with its own non-black third colour keeps it, by
  design.

**(b) Bench pending (Tyler, not done for this candidate):** per-light
brightness on the spare bench controller (.179): a design with dimmed lights,
Apply and Preview on lights.

**Not fixed, carried from the branch reports:**

- `lib/features/installer/installer_setup_wizard.dart` — three
  pop-await-ref places (Start Fresh, Done, Exit Without Saving). Not
  reproducible with real timing; left unchanged. About 80 further ref reads
  after an await remain, as listed for build 130.
- Timing-sensitive tests not converted: `calendar_entry_lease_manager_test.dart:479`
  (a 50 ms bound on a synchronous call), `lease_served_game_day_test.dart:306`,
  `sync_pacing_test.dart:182`, the 950 ms / 900 ms sleeps against an 800 ms
  debounce in `schedule_sync_queue_test.dart` and
  `schedule_sync_hydration_guard_test.dart:98`, and
  `controller_facts_writer_test.dart:185`.
- Design Studio: the editor strip still shows each light's pure colour
  (`manual_design_editor.dart:756`); zoom and scroll carry across channel
  switches; an AI motion design dimmed in the paint editor still applies as
  its effect with pure colours.

## 6. Phone checklist (build 131 on the phone)

1. Explore → a two-colour Glitter look → the sparkles are bright white.
2. Design Studio → set a few lights to Dim (or a Ramp) → Apply → those
   lights are dimmer on the house; Preview on lights shows the same.
3. My Schedule with an overload banner → Clean Up → select items → confirm →
   leave the tab while it runs → come back: everything selected is gone.
4. Ask Lumina to delete an entry → Delete → close the sheet straight away →
   the entry is gone, and reopening Lumina shows its reply saying what it
   removed.
5. A Glitter schedule saved on build 130 → tap Sync on My Schedule → it
   sparkles white at its next run.

## 7. Gates

Run on the merged tip `bac1d61` (this note, which adds only
`docs/release/build_131_candidate.md`, lands after it), `TZ=UTC0`, after
`flutter clean`, on Flutter 3.47.9 (the Codemagic pin) and 3.41.2. Free
space on C: was 36.7 GB or more at every step (stop under 10 GB).
`pubspec.lock` and `analysis_options.yaml` (rewritten by 3.47.9's
`pub get`) were restored after each run; the worktree was clean after both.

The baselines are analyze runs on `a9c63c2`, whose code is build-130's (the
diff from `321dc7a` is three docs files). Their per-issue lists are identical
to the 2026-11-21 records on the same commit. Per-issue means each issue's
severity, file, message and lint, compared as sorted lists with line numbers
removed, because merges move lines.

| SDK | analyze | per-issue vs build 130 | TZ=UTC0 suite | golden | docs_guard |
|---|---|---|---|---|---|
| 3.47.9, build 130 (baseline) | 0 errors / 12 warnings / 341 infos | — | 6,655 pass / 39 skip / 0 fail | 1 / 1 | 44 files / 143 facts / 0 / 0 |
| 3.47.9, `bac1d61` | 0 errors / 12 warnings / 341 infos | identical (empty diff) | 6,673 pass / 39 skip / 0 fail (05:32–05:40Z) | 1 / 1 | 44 files / 143 facts / 0 / 0 |
| 3.41.2, build 130 (baseline) | 0 errors / 12 warnings / 336 infos | — | 6,655 pass / 39 skip / 0 fail | 1 / 1 | 44 files / 143 facts / 0 / 0 |
| 3.41.2, `bac1d61` | 0 errors / 12 warnings / 336 infos | identical (empty diff) | 6,673 pass / 39 skip / 0 fail (05:41–05:49Z) | 1 / 1 | 44 files / 143 facts / 0 / 0 |

6,673 = 6,655 + 0 (relay timing) + 3 (sweep) + 11 (design brightness) + 4
(Glitter: 8 added, 4 deleted). No test failed, so nothing was re-run as a
possible flake. The overload Clean Up test was also run on its own on 3.47.9
(1 / 1), because the compact reporter's 3.47.9 log never prints its line;
the 3.41.2 log shows it passing inside the suite. The 3.47.9 analyze count comes from that SDK's own
`dart analyze`, because its `flutter analyze` wrapper stops on a long path
inside the SDK. 3.50.0 was not run. The suite baselines are the build-130
records (3.47.9 on `321dc7a`; 3.41.2 on `0a364ce`) and the 2026-11-21 runs on
`a9c63c2`.

Tagged `build-131` at `3191e4b` (the bump, gated on both SDKs with the same
results as `bac1d61`; ledger row +131) on 2026-11-25 13:55:56Z (07:55:56 CST;
annotated, tag object `cb36dc4`), pushed 13:56:04Z. Codemagic built it as
TestFlight 2.5.10 (368) (owner, 2026-11-25), the next number after build
130's 367; the owner confirmed it is on their phone.
