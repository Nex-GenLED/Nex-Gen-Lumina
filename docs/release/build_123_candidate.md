# Build +123 candidate — `feat/123-candidate`

Assembled 2026-11-07 from tag `build-122` (`f7b8317`): roofline custom designs
slices 1, 2 and 3, a cross-slice test, the version bump, then items A–D of the
same day. Those are animated designs refused for scheduling, Dancing Shadows
slower, the FACTS and release-notes re-stamp, and these notes. **Not tagged, not
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
| 4 | `f626268` | First version of this file. |
| 5 | `92cd072` | `chore(release): bump to 2.5.10+123`. `pubspec.yaml` and `lib/app_version.dart` only. |
| 6 | `fadbf34` | **Item A:** animated designs refused for scheduling at pick, compose and write time (section 5). |
| 7 | `f7aaee3` | **Item B:** Dancing Shadows starts at speed 10, not 20 (section 6). |
| 8 | `080e38d` | **Item C:** FACTS.md re-stamp and the build 123 release-notes entry (ledger convention 6). |
| 9 | the tip | **Item D:** this file. |

Items A and B are app code that lands *after* the bump. So the bump commit is no
longer the build point, and per ledger convention 1 the tag goes on the tip, which
is the commit carrying every app byte. `git log 92cd072..<tip>` lists exactly
what came after the bump. No re-bump was made: there was no instruction to, and
`+123` is unchanged.

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

Run on `080e38d`, which is the final app and test tree. This file is docs only,
outside docs_guard's scope, and read by no test.

| Gate | Flutter 3.41.2 (this PC) | Flutter 3.47.5 (separate install, scratchpad) |
|---|---|---|
| `flutter analyze` (3.47.5 with the ledger's `--no-fatal-warnings --no-fatal-infos`) | **0 / 12 / 357**. With line:col stripped, the issue set is identical to build-122 + slices; the one moved line is the existing `unnecessary_cast` in `schedule_sync.dart`, 1127 → 1156. | **0 / 12 / 362**, exit 0 |
| `TZ=UTC0 flutter test` | **6,306 passed / 39 skipped / 0 failed** (12:08) | **6,306 passed / 39 skipped / 0 failed** (11:20) |
| golden `test/regression/single_controller_guard_test.dart` | **1 / 1** | **1 / 1** |
| `node scripts/docs_guard.mjs` | 44 files, 124 facts, 0 failures, 0 warnings | (no Flutter) |

Earlier runs, kept for the arithmetic:

- the pure merge `872a96e`: 6,288 / 39 / 0 (6,142 + 146);
- `92cd072`: 6,295 / 39 / 0 (+7 cross-slice).

Items A and B add 8 and 3 tests, so 6,295 + 11 = **6,306**.

**3.47.5 against 3.41.2, every difference.** No code change is needed, and none
was made.

- **Tests:** none. The same 6,306 / 39 / 0, and the golden passes under both.
- **Analyze:** errors 0 = 0 and warnings 12 = 12 (the same set); infos 357 → 362
  (+5). Compared by severity, location and rule:
  - **+6 `deprecated_member_use`:** `ReorderableListView.onReorder` is deprecated
    in 3.47 ("use onReorderItem"). The six sites:
    - `lib/features/design/roofline_setup_wizard.dart:937`
    - `lib/features/design/segment_setup_screen.dart:236`
    - `lib/features/neighborhood/widgets/member_position_list.dart:184`
    - `lib/features/site/roofline_editor_screen.dart:426`
    - `lib/screens/commercial/onboarding/screens/your_teams_screen.dart:187`
    - `lib/widgets/team_priority_list.dart:51`
  - **−1 `prefer_initializing_formals`:**
    `lib/features/design/models/design_intent.dart:630` is no longer reported.
  - **Moved:** `use_build_context_synchronously` at
    `lib/features/geofence/geofence_monitor.dart:152` is reported at column 18
    instead of 9 (the same finding).
  - **None of these eight files** was changed by this candidate since build-122.
    All are infos, and the ledger's flags pass infos.
  - **The message wording** of many deprecation infos changed between the SDKs;
    the findings themselves did not.
- **Toolchain rewrites from 3.47.5's `pub get`.** These are exactly what convention
  5 predicts, and both were restored with `git checkout`:
  - `pubspec.lock`: matcher 0.12.18 → 0.12.20, meta 1.17.0 → 1.19.0, test_api
    0.7.9 → 0.7.12, vector_math 2.2.0 → 2.4.4, and the Dart floor ≥3.9.0 →
    ≥3.11.0-0;
  - `analysis_options.yaml`: +6 lines excluding `build/**`, `android/**`, `ios/**`
    and `web/**`.
- **How the 3.47.5 gate was run.** The archive came from Google's release index,
  SHA-256 checked. It was extracted under the scratchpad through the `\\?\` prefix,
  because long paths are off on this PC and the scratchpad path is 105 characters.
  The steps were `flutter clean`, then `pub get`, analyze, the suite and the
  golden, then a restore to 3.41.2 (clean and `pub get`). PATH and
  `C:\develop\flutter` were untouched; the default pub cache was used.
- **One tooling workaround.** `flutter analyze` walks the whole SDK repo
  (`getRepoPackages()`, used only under `--flutter-repo`) and crashed on an SDK
  directory deeper than 260 characters. Three empty `.dartignore` markers in the
  scratchpad SDK's `dev/`, `examples/` and `packages/` stop that walk. No SDK code
  and no project file was changed.

No existing test file was changed by this candidate's own commits. The two merges
are conflict-free, and `37a74bf`'s tree equals `fd48bdf`'s.
`0c3f413` and `f7aaee3` add new files. `fadbf34` adds 8 tests and helpers to this
candidate's own cross-slice file; that file's original 7 tests are unchanged
(diff: 0 lines removed). In the slices' own history, slices 2 and 3 only add test
files. Slice 1 modifies three existing tests (`segment_count_save_test`,
`base_ladder_repair_bus_change_test`, `sync_start_look_kinds_matrix_test`), as
already accepted on its branch.

**Codemagic's SDK:** `codemagic.yaml` builds with `flutter: stable`, and
`releases_windows.json` says stable is now **3.47.9** (3.47.5 was released
2026-09-18). The ledger's local copy at `~/.lumina/sdk/flutter` is still 3.47.5.
The 3.47.5 column is what was asked for; whether Codemagic now builds on 3.47.9
is not verified here.

## 3. Version

**`2.5.10+123`.** I deviated from the "358 / 2.5.11" in the prompt; the reasons:

- **Build number.** In this repo `+N` is the build tag's number and the Android
  versionCode: build-119 through build-122 are `+119` through `+122`. The iOS build
  number is not taken from the pubspec: Codemagic writes its own
  `PROJECT_BUILD_NUMBER` over it at build time (`codemagic.yaml`, "Set build
  number"). That counter gave build-122 TestFlight 357, so it will most likely give
  this build 358 by itself. Putting 358 in the pubspec would make the Android
  versionCode 358 and break the tag-equals-`+N` join the ledger relies on.
- **Version name.** Every ledger row from +78 to +122 is `2.5.10`, and every bump
  commit changed only `+N`. A new marketing version starts a new TestFlight version
  train, which needs Beta App Review again before external testers get the build.
- **To use 2.5.11 anyway:** before tagging, edit the same two lines (`pubspec.yaml`
  `version:`, `lib/app_version.dart` `kAppVersion`). The version tests read both
  files and check that they agree.

## 4. Cross-slice proof

`test/features/schedule/variation_schedule_cross_slice_test.dart`: 15 tests, all
passing (7 from `0c3f413`, 8 from item A).

The variation is made by the real slice 3 code:

1. The studio orchestrator composes it over the saved design's stamped lengths,
   using the `configForAiPipeline` of a variation session.
2. The real studio save stores it.
3. It is read back from Firestore the way My Designs reads it.

It then goes through slice 2's pick-time verdict, `designSchedulePickVerdict`.
That verdict runs slice 1's fit gate, the bus-starts check, the firmware and model
check, the bounds-first builder, and both caps. Then come the checks the sync
makes before it writes: body shape, bounds against the controller's buses, and both
caps with the real slot and name. Item A's tests also drive the real
`ScheduleSyncService.syncAll`.

| Variation (3 buses × 100, stamp `[100,100,100]` on ctl-a) | Verdict | Elements / bytes |
|---|---|---|
| "1 on 3 off" | admitted. Bounds-first; one light in four lit from LED 0 of every bus. | 1,065 / 3,080 |
| same, channel 2 switched off in the editor | admitted. Bus 1 is in the bounds group and at the end as `{id,start,stop,on:false}`. | 721 |
| "1 on 3 off" on the controller with channel 2 at 120 | refused at the fit gate, with no body | — |
| "every other light" | **refused as too detailed** by the element cap (1,890 > 1,700). Its bytes are under the 6,000 byte cap, and the body is still bounds-first. | 1,890 / 5,246 |
| "chase left to right" (effect 28) | **refused: animated** at pick (no device read), at compose, and at write | — |
| "wave effect moving right to left" (effect 67) | **refused: animated** | — |

The element counts were worked out by hand in the test file's header before the
first run, and the code gave the same three numbers.

## 5. Item A — animated designs are refused for scheduling

A design whose motion is on with a non-zero effect id (`motionEffectOf`) used to
pass slice 2's gates. It was saved as the still preset (`fx:0` plus an `i` frame)
and fired as one still frame at the ON time. It is now refused, never converted,
with: **"<name>" is an animated design. Animated designs can't be scheduled yet.
Pick a still design, or save a still version.**

- **Pick time.** `designSchedulePickVerdict` refuses before the `/json/info` read.
  The schedule selection gate shows the sentence and hands nothing back.
- **Compose time** (slice 2's own name for the verdict). `designScheduleEligibility`
  returns the new `animated` verdict ahead of every other gate, and
  `buildDesignApiPresetBody` builds no body for an animated design.
- **Write time.** The sync reads the owner's saved designs once per sync, and only
  when the sync holds a design schedule (`designsStreamProvider`, waiting up to
  3 s). Then, under the C1 rule:
  - **design is animated:** a *persistent* refusal. Not written, not armed, and a
    copy already on the controller is purged.
  - **designs can't be read:** *transient*, "couldn't check … left exactly as it
    is". A copy already on the controller stays armed.
  - **design isn't in the list** (deleted): judged exactly as before.
- **Unaffected:** still painted designs, colour-only variations, and the Game Day
  and Sync per-pixel blocks. Slice 2's design suites plus the Sync per-pixel block
  tests ran 145 / 145.

**Fail-before.** The new tests were run against `92cd072`'s lib: **9 passed /
6 failed**.
- The chase pick, the wave pick and the compose verdict read `allowed`.
- The write saved slot 10 and armed it.
- A landed copy was not purged.
- No transient sentence appeared.

The two "still admitted" tests passed before and after. With the fix: 15 / 15.

## 6. Item B — Dancing Shadows starts one band slower

**Trace.** What the tile named "Dancing Shadows" sends, from the tap to the
controller:

| Where | Tap → speed | Effect / intensity | Speed sent (old → new) | Band |
|---|---|---|---|---|
| Pattern library tuner (Explore → a colourway → tune → **Pulse** filter → the tile) | `_selectEffect(112)` → `effectDefaultSpeedOr(112, current)` = `kEffectDefaultSpeed[112]` | fx 112; intensity: the slider's current value (no default for 112); palette by effect | **20 → 10** | Very Slow → Very Slow |
| Home Tune panel (effect menu → "Dancing Shadows") | `_applyEffect(112)` → same function | fx 112; intensity: the current value | **20 → 10** | Very Slow |
| Edit pattern screen | `effectDefaultSpeedOr` | fx 112 | 20 → 10 | Very Slow |
| Library cards "<colourway> Shadows" (not named "Dancing Shadows") | `scaledEffectDefaultSpeed(112, folder pace)` | fx 112; intensity: the folder's | pace 128: 20 → 10; pace 30: 5 → 2; pace 255: 40 → 20 | Very Slow |
| Lumina chat (when the cloud states no speed) | `EffectDecisionTree.recommendSpeed` from `effect_database` (default 60, min 0, max 255) | fx 112 | **60, unchanged** (energy low 21, high 187) | Slow |
| AI studio / autopilot / Game Day celebrations | not offered by name. The studio's effect words are chase, wave, twinkle and pulse. Autopilot and Game Day code never names 112 and reads none of these speed sources (their fixed looks use effects 0, 2, 11, 28, 52 and 65); a look the cloud chooses carries the cloud's own speed. 112 is not a celebration pick. | — | — | — |
| Game Day design picker | opens the same tuner, so the same path as row 1 | — | 20 → 10 | — |

Further facts from the trace:

- **No slider memory.** `effectDefaultSpeedOr(112, x)` is the table value for every
  `x`.
- **The wire chokepoint leaves it alone.** `normalizeWledPayload` passes sx 10 (and
  20) unchanged; the flash caps cover only 23, 24 and 57. So the controller
  receives the table value.
- **The bands** on effect 112's profile (`effect_speed_profiles.dart` 130–137 and
  411; min 5, recommended max 100, logarithmic) are Very Slow 5–47, Slow 48–67,
  Medium 68–81, Fast 82–91 and Very Fast 92–100.
- **The rule applied.** 20 was already Very Slow, the slowest band, so by the
  owner's rule it was halved with a floor of 5: **20 → 10**. That is a firmware
  pace of × 0.11 against × 0.21 before.
- **Left alone:** no effect was renamed and no other effect changed. The profile's
  unused `rawDefault` of 35 (Very Slow) stays as it is.
- **effect_database:** the legacy table's key **97** is named "Dancing Shadows" and
  there is no key 112. The app re-keys every entry by name, so at run time 97 is
  Plasma (default 100) and 112 is Dancing Shadows (default 60). The picker reads
  names from the catalog: **both appear**, as "Plasma" (97) and "Dancing Shadows"
  (112), and nothing shows "Dancing Shadows" twice.
- **Tests.** `test/features/wled/dancing_shadows_speed_test.dart` pins the table
  value, and end to end, the speed both tiles send: the tuner tile's recorded
  payload, and the Home Tune body the controller would receive. Before the change it
  ran 0/3 (each "expected 10, actual 20"); after, 3/3. No existing test pinned 20,
  and the existing speed suites ran 84/84.

## 7. Known, not fixed

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

**Added 2026-11-07:**

1. **"Every other light"** can be scheduled only up to about **268 lights on three
   channels**. Its element count is 6 + 28 × channels + 6 × lights against the
   1,700 cap. The slice 3 bench layout (162/128/100) works out to 2,430 (computed).
   The real fix is segment grouping and spacing: the runs-as-segments follow-up.
2. **Effect id 97 is labelled "Dancing Shadows"** in `effect_database.dart`'s
   legacy table, but 97 is Plasma in WLED. At run time the entry is re-keyed by name
   to 112, so no customer sees the wrong name (section 6). The source label is still
   wrong.
3. **Dancing Shadows' defaults disagree.** The table now says 10 (it was 20), and it
   is used by the tiles. The speed profile's `rawDefault` 35 is unused for 112.
   `effect_database`'s 60 is used by the Lumina chat path when the cloud states no
   speed (section 6).

None of the slice 1, 2 or 3 bench items has been run with this candidate on a phone.

## 8. Found while assembling, not changed

1. **Correction to the first version of this file.** It said the AI path reads id
   97 as Dancing Shadows. It does not: `EffectDatabase.effects` re-keys by name
   (`effect_database.dart` 1873–1887), so the 97 label is source-only.
2. **Lumina chat can still start Dancing Shadows at 60** (Slow) when the cloud
   reply carries no speed. Item B changed only the tile's path, as instructed.
3. **Calm library collections now start their "… Shadows" card at speed 2–4**
   (pace 30 → 2, 40 → 3, 50 → 4). That is below the floor of 5 the owner set for
   the tile, and below the slider's own minimum of 5, because cards scale the table
   value by the collection's pace. A per-effect floor in `scaledEffectDefaultSpeed`
   would change every effect, so it was not done.
4. **Going back to build 122 with a design schedule saved on 123** is analysed in
   section 12, which also holds the withdrawal tester text.
5. **Item A's write-time check makes one Firestore read per sync**, and only when
   a design schedule is present. If the designs can't be read within 3 s, a design
   schedule that has not landed yet waits for the next sync, while a landed copy
   stays armed. Pattern schedules never wait.
6. **FACTS rows T-D4, T-D5, T-G3, T-G4 and T-E4 say `BUILT NOT SHIPPED (123
   candidate)`, and T-B1 names build 122.** That is true until the tag. After the
   tag they move to `SHIPPED (123)` (section 11).
7. **The release-notes guide lists no entries for builds 117–122,** and FACTS.md
   was last re-stamped for 116. Convention 6 was not followed for 117–122; this
   candidate fixed only its own rows and the intro sentence.

## 9. NOT in this candidate

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
  - Runs-as-segments (the real fix for "every other light" on long rooflines).

## 10. Phone checklist

**Before you start**

- Use the **spare controller** (0.15.4, three channels of 100). Never use the home
  controller for steps that save a design to the controller (steps 12–23, 35–37
  and 46).
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

**Item A — animated designs can't be scheduled** (spare only)

35. Design Studio → "Variations of Bench stamp 3x100" → type "chase left to right"
    → Save. Schedule → new → Run a pattern → Pick → My Designs → that variation.
    *Expect:* "… is an animated design. Animated designs can't be scheduled yet.
    Pick a still design, or save a still version." Nothing is picked.
36. Do the same with "wave effect moving right to left", and with the chase design
    from step 29. *Expect:* the same sentence each time.
37. Save a "1 on 3 off" variation the same way and pick it. *Expect:* it is
    accepted, with the "saved to your controller as a picture" line. Delete the
    schedule afterwards.

**Item B — Dancing Shadows is slower**

38. Explore → any colourway → tune → Pulse → Dancing Shadows. *Expect:* the speed
    slider reads "Very Slow", and the shadows move about half as fast as on build
    122. Laptop: the controller's state shows speed 10.
39. Home → Tune → effect menu → Dancing Shadows. *Expect:* the same pace. Laptop:
    speed 10.
40. Explore → a calm collection (Nature & Outdoors) → a colourway → its
    "… Shadows" card. *Expect:* it still visibly moves; calm collections now start
    it at speed 2–5. Write down whether it looks still.

**+122 sunrise and sunset — must not have regressed**

41. Schedule Warm White on at sunset and off at sunrise, every day, then sync.
    *Expect:* no warning.
42. At sunset. *Expect:* Warm White comes on within a minute of the app's sunset
    time.
43. At the next sunrise. *Expect:* the lights go off.
44. Before a sunset, unplug the controller for 10 s with the phone away, plug it
    back in, and set its clock if it is the spare. *Expect:* it still comes on at
    sunset, not at sunrise.
45. Turn on a sunrise OFF for one weekday only. *Expect:* the lights go off at
    sunrise on that day.
46. Add "Bench nightly 3-bus" at a clock time beside the sunset schedule, then
    sync. *Expect:* the sunset and sunrise behave exactly as in steps 42–43.
47. Delete the design schedule and sync. *Expect:* sunset and sunrise still work,
    and Warm White is unchanged.

## 11. After the tag

- In the ledger commit, which goes outside the tag:
  - move T-D4, T-D5, T-G3, T-G4 and T-E4 in `docs/FACTS.md` to `SHIPPED (123)`;
  - move T-B1 to build 123 with its TestFlight number;
  - add the build's ledger rows and the withdrawal tester text to
    `docs/guides/internal/31-release-notes.md` (the text is in section 12).
- Android: versionCode 123 is not consumed until a bundle is built; bump nothing
  before that.

## 12. Rolling back to build 122 — what build-122 does with a 123 design schedule

Read-only, 2026-11-07.

**How it was run.**
- **Where:** a throwaway worktree of `build-122` (`f7b8317`). The tag was not
  touched, and the worktree was removed afterwards.
- **What ran:** build-122's real `ScheduleItem.fromJson` and
  `ScheduleSyncService.syncAll`, against a fake controller (three buses of 100,
  WLED 0.15.4, classic ESP32). Its `savePreset` ran build-122's own code in
  simulation mode, including its normalizer and freeze guard, so the recorded
  body is build-122's wire body.
- **Input:** the exact entry 123 stores for "Bench nightly 3-bus" (3 × 100,
  channel 2 left out). That is `toJson` with `design_id`, `preset_kind: api`, the
  bounds-first `o:true` body and `presetId` 10, plus the copy 123's sync leaves in
  slot 10.
- **The way back** to 123 ran on the tip the same way.
- **Not run:** what WLED then shows on the lights is reasoned from the 2026-11-06
  bench facts, not run on hardware.

**What 122 receives.** It reads the entry as a catalog pattern:
- the label, slot 10 and the bounds-first `o:true` body come through intact;
- `design_id` and `preset_kind` are ignored;
- 122's own `toJson` writes the entry back without them, and any schedule save on
  122 rewrites the whole schedules array.

**What 122 writes, on every sync.** This is the catalog-pattern path,
`alwaysWrite`.
- **The request:** `POST /json/state` with `psave: 10`,
  `n: "Pattern: Bench nightly 3-bus"` and the body.
- **What 122 adds:** `ib:true`, `on:true` and `bri:255`, plus `frz:false` on the
  three bounds entries and on the left-out entry (122's freeze guard).
- **What stays:** `o:true`, so it is still an API-command preset; the bounds,
  because the preset save does not pass 122's geometry wire pin; and the paint
  entries, unchanged.
- **No checks:** no layout, firmware, model, size or read-back check, and no
  warning. The sync reports success.
- **Both starting points behave the same:** a controller holding 123's copy (a
  rewrite) and an empty controller (a first write).

**Timer row and stored copy.**
- The 19:00 ON row (macro 10) and the 23:00 OFF row (preset 2) stay armed.
- Slot 10 is still owned, so nothing is purged.
- The stored copy becomes 123's body plus `ib:true` and the `frz:false` keys.

**On the lights (reasoned).** WLED replays an API-command preset as the request:
- the bounds group first (the added `frz:false` on a bounds entry changes nothing
  visible);
- then the paint, which freezes the painted channels;
- then the left-out channel, off.

So at the ON time the house should show the same picture as on 123, also after a
power cut (bounds first, as benched), and OFF at 23:00 ends it as before.
- **Not dark, no loop, no error.** The cost is one slot-10 write per sync, against
  123's write-only-on-change. The extra keys are not bench-proven.

**Where it can go wrong.**
1. **The layout changed after the design was picked.** 122 checks nothing. At
   every fire the body re-bounds the segments to the saved lengths, so the picture
   lands on the wrong lights until the app re-splits the controller on its next
   home connect, and 122 re-arms it every sync.
2. **Firmware.** 122 writes it whatever the controller runs; 123 only proves WLED
   0.15.4 on a classic ESP32.
3. **The app is open during the schedule's window.** 122's enforcement re-applies
   the stored body live. Its geometry wire pin strips the bounds (an assertion in a
   debug build; a release build strips and carries on), so the paint lands on the
   segments the controller already has. That is the same look on a split layout,
   but it can land wrong after a power cut, before the app re-splits.

**Coming back to 123** (ran on the tip):
- **(a) Nothing was saved on 122**, so the fields are intact. 123 rewrites slot 10
  once (122's copy hashes differently), reads it back and arms it. Normal.
- **(b) Any schedule was saved on 122**, so the fields are gone. 123 refuses the
  schedule: a painted design that "reached your schedule without being checked …
  open it and pick the design again from My Designs to arm it".
  - Slot 10 is purged, and nothing of that schedule is armed, its OFF row included.
  - It stays in the list until the design is picked again.

**Withdrawal tester text** (for the build's release-notes entry once the ledger
row lands):

> Before you install build 122, open Schedule on build 123, delete every schedule
> that runs a painted design, and let the app sync once on your home Wi-Fi. Build
> 122 can't check a painted design against your lights, so a schedule left in place
> keeps firing the saved picture even if your channels change, and it must be
> picked again when you come back to 123. Your other schedules are not affected.
> Send reports to general@nex-genled.com with the date and time.

The last sentence is the line every tester message ends with (release notes
convention). "Other schedules are not affected" is grounded: 123 writes a
non-design schedule's entry exactly as 122 does (`design_id` and `preset_kind` are
omitted when null).
