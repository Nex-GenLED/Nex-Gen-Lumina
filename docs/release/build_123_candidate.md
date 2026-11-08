# Build +123 candidate — `feat/123-candidate`

Assembled 2026-11-07 from tag `build-122` (`f7b8317`). Roofline custom designs
slices 1, 2 and 3, one cross-slice test, and the version bump. **Not tagged, not
built, not deployed. No controller, bench unit or production system was contacted
to assemble it.** The tag waits for the owner's go.

## 1. What went in

Base: `build-122` = `f7b83177dbe56f567d5f782f116754f3ab938c3d` (2.5.10+122,
TestFlight 357, Android versionCode 122).

| # | Commit | What |
|---|---|---|
| 1 | `37a74bf` | Merge `feat/123-roofline-slice2` @ `fd48bdf54b13` (no-ff). Carries slice 1 (`2b03208`, 7 commits) and slice 2 (30 commits on `2b03208`). |
| 2 | `872a96e` | Merge `feat/123-roofline-slice3` @ `7a102d43d052` (no-ff). Slice 3: 11 commits on `2b03208`. |
| 3 | `0c3f413` | Test only: a slice 3 colour variation through slice 2's schedule gates (section 4). |
| 4 | this file | Docs only. |
| 5 | the bump | `chore(release): bump to 2.5.10+123`. `pubspec.yaml` and `lib/app_version.dart` only. It is the last commit, so per ledger convention 1 the tag goes on it. |

Source tips (all three are pushed, and none was changed):

- slice 1: `feat/123-roofline-slice1-w2` @ `2b032083e453`. Not merged on its own; it arrives inside slice 2 and slice 3.
- slice 2: `feat/123-roofline-slice2` @ `fd48bdf54b13`
- slice 3: `feat/123-roofline-slice3` @ `7a102d43d052`
- the retired `feat/123-roofline-slice1` @ `03c86cf` is in neither source: checked by ancestry, not merged.

Checks run before merging:

- merge-base(slice 2, build-122) = merge-base(slice 3, build-122) = `f7b8317`.
- merge-base(slice 3, slice 2) = `2b03208`.
- build-122..slice 2 = the 7 slice 1 commits plus 30 slice 2 commits.
- build-122..slice 3 = the same 7 plus 11.
- Neither source has a merge commit, and neither has a commit outside those lists.

**Conflicts: none.** Slice 2 and slice 3 share no file since `2b03208`. A
`git merge-tree` trial was clean, and the merged tree (`4fd2cb9`) is
byte-identical to the trial.

## 2. Gates

Flutter 3.41.2. Run on the tree of commit 5: 0c3f413 plus the bump. This file is
docs only and is not read by any test.

| Gate | Expected | Result |
|---|---|---|
| `flutter analyze` | 0 errors / 12 warnings / 357 infos | **0 / 12 / 357**. With line:col stripped, the issue set is identical to slice 2's and slice 3's own runs; the only differences are line shifts in files the other slice edited. |
| `TZ=UTC0 flutter test` on the pure merge (`872a96e`) | 6,142 + 146 = 6,288 | **6,288 passed / 39 skipped / 0 failed** (12:13) |
| `TZ=UTC0 flutter test` on the final tree | 6,288 + 7 new | **6,295 passed / 39 skipped / 0 failed** (10:54) |
| `test/regression/single_controller_guard_test.dart` | 1 / 1 | **1 / 1** (on the merge and on the final tree) |
| `node scripts/docs_guard.mjs` | 0 failures | 44 files, 119 facts, 0 failures, 0 warnings (on the merge) |

Accounting: slice 1's suite was 5,975, slice 3's 6,121 (+146) and slice 2's
6,142. The merge adds the two deltas, 6,142 + 146 = 6,288 exactly. The cross-slice
file adds 7.

No test file was changed in assembling the candidate. The two merges are
conflict-free, `37a74bf`'s tree equals `fd48bdf`'s, and `0c3f413` adds one new file.
In the slices' own history, slices 2 and 3 only add test files. Slice 1 modifies
three existing tests (`segment_count_save_test`,
`base_ladder_repair_bus_change_test`, `sync_start_look_kinds_matrix_test`), as
already accepted on its branch.

**Owed before the tag** (ledger conventions, not run here):

- **Convention 5:** analyze plus `TZ=UTC0` test under Codemagic's SDK (3.47.5, at
  `%USERPROFILE%\.lumina\sdk\flutter`), on the exact commit to be tagged.
- **Convention 6:** re-stamp every `docs/FACTS.md` row this build changes, and add
  the build's entry to `docs/guides/internal/31-release-notes.md`. Not done: no
  slice has been benched with the app in the loop, and a guide must not describe
  unshipped behaviour.

## 3. Version

**`2.5.10+123`.** I deviated from the "358 / 2.5.11" in the prompt; the reasons:

- **Build number.** In this repo `+N` is the build tag's number and the Android
  versionCode: build-119 through build-122 are `+119` through `+122`, and convention
  1 tags the bump commit itself. The iOS build number is not taken from the
  pubspec: Codemagic writes its own `PROJECT_BUILD_NUMBER` over it at build time
  (`codemagic.yaml`, "Set build number"). That counter gave build-122 TestFlight
  357, so it will most likely give this build 358 by itself. Putting 358 in the
  pubspec would make the Android versionCode 358 and break the tag-equals-`+N` join
  the ledger relies on.
- **Version name.** Every ledger row from +78 to +122 is `2.5.10`, and every bump
  commit changed only `+N`. A new marketing version starts a new TestFlight version
  train, which needs Beta App Review again before external testers get the build.
- **To use 2.5.11 anyway:** before tagging, edit the same two lines (`pubspec.yaml`
  `version:`, `lib/app_version.dart` `kAppVersion`). The version tests read both
  files and check that they agree.

## 4. Cross-slice proof

`test/features/schedule/variation_schedule_cross_slice_test.dart`: 7 tests, all
passing.

The variation is made by the real slice 3 code:

1. The studio orchestrator composes it over the saved design's stamped lengths,
   using the `configForAiPipeline` of a variation session.
2. The real studio save stores it.
3. It is read back from Firestore the way My Designs reads it.

It then goes through slice 2's pick-time verdict, `designSchedulePickVerdict`.
That verdict runs slice 1's fit gate, the bus-starts check, the firmware and model
check, the bounds-first builder, and both caps. Finally the test runs the checks
the sync makes before it writes: body shape, bounds against the controller's buses,
and both caps with the real slot and name.

| Variation (3 buses × 100, stamp `[100,100,100]` on ctl-a) | Verdict | Elements / bytes |
|---|---|---|
| "1 on 3 off" | admitted. Bounds-first; one light in four lit from LED 0 of every bus. | 1,065 / 3,080 |
| same, channel 2 switched off in the editor | admitted. Bus 1 is in the bounds group and at the end as `{id,start,stop,on:false}`. | 721 |
| "1 on 3 off" on the controller with channel 2 at 120 | refused at the fit gate, with no body | — |
| "every other light" | **refused as too detailed** by the element cap (1,890 > 1,700). Its bytes are under the 6,000 byte cap, and the body is still bounds-first. | 1,890 / 5,246 |

The element counts were worked out by hand in the test file's header before the
first run, and the code gave the same three numbers.

## 5. Dancing Shadows: decision owed, NOT changed

- **Where the speed lives: app code only.** No cloud library holds a copy, and no
  bundled asset does either. The value is `kEffectDefaultSpeed[112] = 20` in
  `lib/features/wled/pattern_effect_speeds.dart` (line 200). Every place a customer
  starts the effect reads it: Explore cards, the palette tuner, the Home Tune panel,
  the edit screen and Lumina.
- **The app's speed levels:** the five bands of the speed slider. They are
  `EffectSpeedProfile.speedLabel` in `lib/features/wled/effect_speed_profiles.dart`
  (lines 130–137), mapped through each effect's own profile. Dancing Shadows'
  profile (line 411) is min 5, max 100, logarithmic, and gives these bands:

  | Band | Speed values |
  |---|---|
  | Very Slow | 5–47 |
  | Slow | 48–67 |
  | Medium | 68–81 |
  | Fast | 82–91 |
  | Very Fast | 92–100 |

- **The problem:** 20 is already in **Very Slow**, the lowest band, so there is no
  level below it. The profile's own `rawDefault` (35) is also Very Slow, and it is
  not read for this effect.
- **Choices for the owner** (none applied):
  - a lower number inside Very Slow, for example 10 (firmware pace × 0.11 against
    × 0.21 today);
  - the slider floor, 5;
  - a different meaning of "one level".
- Whichever is chosen goes in before the bump commit (or in a new bump), with a test
  that pins the value.

## 6. Known, not fixed — from the bench docs

**Slice 2** (`docs/bench/roofline_slice2_bench_2026-11-05.md`):

1. Only WLED **0.15.4** on a classic **ESP32** is proven (step 5 was not run).
   0.15.1 and 16.0.1 are refused with "proven on WLED 0.15.4 only". The fleet count
   of 2026-11-02 was 0.15.1 × 11, 0.15.4 × 9, 16.0.1 × 3, with 10 unrecorded.
2. Never run with the app in the loop: the picker hand-off on a phone, the
   editor-to-sync write of slot 10, one write then none, the read-back and its
   unreadable retry, transient against persistent purge on a live controller, and
   the healer and restart watch when the app comes back (step 4.5, steps 7.2–7.3,
   8.2–8.3).
3. Not run: step 11, the +122 sun rows beside a design schedule (the spare's sun
   rows were removed on 2026-11-06 and need re-arming first), and step 9.3,
   restoring the allowlist for one write.
4. The presets.json ceiling is above 100 KB and was not measured.
5. `fs.u` on the spare read 221 KB after the growth test while the file was
   2,862 B. Re-read it after the spare's next cold boot.

**Slice 3** (`docs/bench/roofline_slice3_bench_2026-11-05.md`, "Known, not
fixed", left on the owner's instruction):

1. The bare words `in` / `up` / `out` / `down` are matched as directions inside
   other words. `red chase spinning` is silently "inward", with no question.
2. `run` / `running` doubles as the architectural run. `red running lights
   everywhere` targets the "runs" zone.
3. The colour-shade question cannot be reached, because every vague colour key is
   also a colour-map key.
4. Also noted in items 8.6 and 8.7: an answered direction shows in the app and in
   the document, not on the lights (the design payload carries no `rev`, #76). A
   design carries one motion, so a second layer's effect does not reach the device.

None of the slice 1, 2 or 3 bench items has been run with this candidate on a phone.

## 7. Found while assembling, not changed

1. **A motion variation is scheduled as a still picture.** This needs both slices
   to show up. In a variation session, "chase left to right" or "wave effect moving
   right to left" saves a design with `has_motion: true` and `effect_id` 28 or 67.
   Slice 2's pick admits it, but the scheduled body is `fx:0` plus a still `i`
   frame. At the ON time the house shows a still picture, not the chase. Found with
   a throwaway probe, not pinned by a test. A fix would refuse motion designs at the
   schedule pick, or schedule them as an effect preset.
2. **"Every other light"**, one of the three suggested variations, can be scheduled
   only on small rooflines. On three buses the element count is 6 + 28 × buses +
   6 × lights, which reaches the 1,700 cap above 268 lights. The slice 3 bench
   layout (162/128/100) works out to 2,430 elements (computed, not run). "One on,
   three off" and "Two on, two off" stay under the cap there.
3. `lib/features/wled/effect_database.dart` names id **97** "Dancing Shadows"
   (default speed 60). In WLED, 97 is Plasma and Dancing Shadows is 112. This is one
   of the wrong-effect entries noted on 2026-10-20, and the AI path reads speeds
   from that table.
4. Dancing Shadows has two app defaults that disagree: the table's 20, which is
   used, and the profile's 35, which is not (section 5).

## 8. NOT in this candidate

- **Account deletion hardening.** `feat/123-account-deletion` sits at `f7b8317`
  with nothing committed; the Stage 1 audit stopped on 2026-11-05. Build-122's
  existing delete flow ships unchanged.
- **The clamp follow-up.** The server-side Strobe/Lightning limit for
  `applySyncPattern` is on `fix/sync-server-clamp`, a Cloud Function. It is not
  deployed, and an app build does not carry it.
- **The other +123 candidates the notes name.** None is merged; the owner may know
  of others.
  - `feat/121-celebration` @ `542c5e9`: 5 commits, absent by ancestry and by
    patch-id. They cover live-score celebrations without Autopilot, "Also
    broadcast", a host-set sync expiry, and joining a live sync by hand.
  - "Replace <day>'s schedule": the one-night entry owns the exception (size M,
    from the 10-27 read). Not built.
  - The solar flag read in error is treated as OFF by the lease write (the fix
    shape is noted 11-03). Not built.
  - Slice 2's allowlist additions (0.15.1, 16.0.1). They wait on bench step 5.
  - The Dancing Shadows speed (section 5).

## 9. Phone checklist

**Before you start**

- Use the **spare controller** (0.15.4, three channels of 100). Never use the home
  controller for steps that save a design to the controller (steps 12–23, 35 and
  42).
- Use a bench account with a Game Day team set up (steps 9–11).
- The spare's clock resets when it loses power. After every unplug, set its clock
  from the laptop before you wait for a timer.
- "Laptop:" marks a check that needs the app log or the controller's own pages.
  Everything else is seen on the phone or on the lights.

**Slice 1 — saved designs know their roofline**

1. Paint a design on all three channels and save it as "Bench stamp 3x100".
   *Expect:* "Saved".
2. Apply it from My Designs. *Expect:* "Applied"; all three channels show it.
3. Settings → Hardware Config → channel 2 → 120 → Save. *Expect:* "LED counts
   updated."; Home shows channel 2 as 101–220 straight away, with no reconnect.
4. Apply "Bench stamp 3x100" again. *Expect:* it is refused, saying 100 lights on
   channel 2 and 120 now; the lights don't change.
5. Open the design, Save, Apply. *Expect:* "Applied"; channel 2 is painted all
   the way to 120.
6. Set channel 2 back to 100 and Save. Apply. *Expect:* refused (120, 100 now).
   Open, Save, Apply. *Expect:* "Applied".
7. Put the phone on mobile data and apply the design. *Expect:* "can only be
   applied on your home network"; the lights don't change. Back on home Wi-Fi.
8. Apply an old design saved before this build. *Expect:* it applies as it did on
   +122.
9. With the painted design showing, tap Light Up Now (Game Day). *Expect:* an
   orange message that your lights are showing a painted design; nothing changes.
10. Apply any Explore pattern, then Light Up Now. *Expect:* the team look plays.
11. Game Day → design picker → My Designs → "Bench stamp 3x100". *Expect:*
    refused, "can't be the Game Day base design".

**Slice 2 — a painted design on a nightly schedule** (spare only)

12. Save a design "Bench nightly 3-bus" with channel 2 unchecked.
13. Schedule → new → Run a pattern → Pick → My Designs → "Bench nightly 3-bus".
    *Expect:* it is accepted, with the line "This painted design will be saved to
    your controller as a picture…"; no "can't be chosen here".
14. Set ON 5 minutes ahead, every day, and Save. *Expect:* the sync finishes with
    no warning. Laptop: one save for slot 10, then a read-back.
15. Turn the lights off and wait for the ON minute. *Expect:* channels 1 and 3
    show the design and channel 2 stays dark.
16. Pull to refresh the schedule. *Expect:* no warning and no change on the
    lights. Laptop: no second save for slot 10.
17. Read-back: this can't be forced safely, so don't pull power during a save.
    *Expect:* no sync says "couldn't be read back yet". If one ever does, sync again
    from home Wi-Fi. *Expect:* it arms without saving again.
18. Transient: unplug the spare after a sync has finished, then pull to refresh.
    *Expect:* if a sync runs, the design's line says "couldn't check … left exactly
    as it is". Other lines of that sync may warn too, but nothing says the schedule
    was removed. Plug it back in and set its clock. *Expect:* the design still fires
    at the ON minute.
19. Persistent: Hardware Config → channel 2 → 120 → Save, then sync. *Expect:*
    "Your roofline layout no longer matches … won't run"; nothing fires at the ON
    minute.
20. Set channel 2 back to 100. Open the design, save it, pick it again in the
    schedule, and sync. *Expect:* it is armed again and fires at the ON minute.
21. Restart: lights off, phone on mobile data, unplug the spare for 10 s, plug it
    in, set its clock. *Expect:* at the ON minute channels 1 and 3 are painted and
    channel 2 is dark.
22. Phone back on home Wi-Fi; open the app. *Expect:* no warning. Laptop: no
    second save for slot 10.
23. Design Studio → "Variations of Bench stamp 3x100" → Every other light → Save.
    Pick that variation for a schedule. *Expect:* "too detailed for your
    controller" (about 1,890 details against the 1,700 limit), an offer to open the
    editor, and nothing picked.

**Slice 3 — the prompt parser** (Design Studio)

24. Quick idea "Chase Effect". *Expect:* the whole roofline, a chase, left to
    right, with a preview on all three channels; no "No layers produced LED
    assignments".
25. Type "wave effect moving right to left". *Expect:* the whole roofline, a wave,
    right to left, and no question.
26. Type "red moving right", then "red chase left". *Expect:* the whole roofline
    each time, left to right and then right to left, with no question.
27. Rename channel 2's map segment "Left run". Type "red on the left side" and then
    "red to the left of the garage". *Expect:* only channel 2 lights each time.
    Type "chase on the left side". *Expect:* a direction question, then only
    channel 2. Rename the segment back.
28. Chase Effect → Apply to Lights. *Expect:* a moving blue chase on all three
    channels.
29. Save that chase design and apply it from My Designs. *Expect:* it still runs as
    a chase.
30. Type "wave effect moving right to left" and apply. *Expect:* a wave, not a
    chase. Then "red twinkle inward" gives a twinkle, and both "red pulse inward"
    and "red breathe inward" give a pulse.
31. Type "red", and at the effect question tap Chase. *Expect:* the same chase as
    step 28.
32. Type "red scan inward" and apply. *Expect:* a still picture (on purpose).
33. Type "blue chase" and answer Right to left. *Expect:* the panel says right to
    left. The lights run their installed way either way.
34. Type "red chase on the peaks and blue wave on the corners". *Expect:* two
    direction questions. Apply. *Expect:* a chase on both areas (one motion per
    design). Write down what you see.
35. Known gap (spare only): pick the chase design from step 29 for a schedule, with
    ON a few minutes ahead. *Expect:* it is accepted, but at the ON minute it shows
    a still picture, not a chase (section 7, item 1). Delete the schedule
    afterwards.

**Dancing Shadows** (no change in this build; this records today's pace)

36. Explore → any colourway → Dancing Shadows. *Expect:* the speed slider reads
    "Very Slow". Note how fast it looks, so the change can be judged later
    (section 5).

**+122 sunrise and sunset — must not have regressed**

37. Schedule Warm White on at sunset and off at sunrise, every day, then sync.
    *Expect:* no warning.
38. At sunset. *Expect:* Warm White comes on within a minute of the app's sunset
    time.
39. At the next sunrise. *Expect:* the lights go off.
40. Before a sunset, unplug the controller for 10 s with the phone away, plug it
    back in, and set its clock if it is the spare. *Expect:* it still comes on at
    sunset, not at sunrise.
41. Turn on a sunrise OFF for one weekday only. *Expect:* the lights go off at
    sunrise on that day.
42. Add "Bench nightly 3-bus" at a clock time beside the sunset schedule, then
    sync. *Expect:* the sunset and sunrise behave exactly as in steps 38–39.
43. Delete the design schedule and sync. *Expect:* sunset and sunrise still work,
    and Warm White is unchanged.
