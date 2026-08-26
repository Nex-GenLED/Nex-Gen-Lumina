# SCHEDULING V3 — PHASE D (F2: PER-CHANNEL FIRING)

**Worktree:** `C:/Flutter Projects/lumina-schedule-v3` · **Branch:** `feat/schedule-v3-model`
**Commits:** `3e31e4b` (U-7 probe) · `967c621` (Phase D)
**Rebase:** none needed — `main` is still `c14368d`; `feat/design-card` has moved
(`dffd8cd`) but is **unmerged**, so there was no `my_schedule_page.dart` overlap.
**Gate:** `flutter analyze` **0 errors**, 11 warnings (all pre-existing, none in a
touched file) · `flutter test` **2557 pass, 0 fail, 4 skipped**
**Firmware:** unchanged. `base_layer_gate.dart` and every fire-job path untouched (§9).

---

## 1. U-7, AND THE v1 SEMANTICS IT FORCED

Full evidence: **[U7_ABSENT_SEGMENT_PROBE.md](U7_ABSENT_SEGMENT_PROBE.md)**.

**Literal answer: UNTOUCHED.** A segment absent from a preset keeps its colour,
its on-state and its effect through `{"ps":N}` — three confirmations, from the
seven segment-absent presets already on the rig (2, 3, 4, 5, 10, 11, 30).

**The answer that decided D2 was a different one:**

> **`psave` cannot produce a segment-absent preset.** It snapshots the
> controller's full live state. A psave naming only seg[0] stored *both*
> segments; `sel:false` stored the segment *with* `sel:false` rather than
> excluding it.

So "leave the other channels untouched" is unreachable through the app's preset
path regardless of what the firmware does with absence. **v1 semantics, as
decided: a channel-scoped event lights its channels and writes every other
segment `on:false`. No `otherChannels` field. The editor states it plainly:**
*"Other channels will turn off during this schedule."*

The scoped **OFF** is the exception, and it falls out of the same fact: it names
only its own segments and lets the psave snapshot carry the rest, so turning off
one channel decides nothing about the others. Bench-confirmed — §6.

---

## 2. P1–P5, RESTATED

| | Finding | Where |
|---|---|---|
| **P1** | Both stores rewrite EVERY entry through `toJson()` on an ordinary edit: `saveAll` [legacy_array_schedule_repository.dart:117](../lib/features/schedule/data/legacy_array_schedule_repository.dart), `applyArrayTxn` (behind `remove`/`update`) [schedule_store_sync.dart:106](../lib/features/schedule/data/schedule_store_sync.dart), `overwriteArray` [:120](../lib/features/schedule/data/schedule_store_sync.dart), the subcollection mirror [:135](../lib/features/schedule/data/schedule_store_sync.dart), and the whole `calendar_entries` field. Only `add`/`addAll` (arrayUnion) are safe. **⇒ both stores need a sidecar.** |
| **P2** | `psaveIfChanged` took `state:` and `isSatisfied:` as independent arguments; the four ladder sites passed a builder for one and a hand-written predicate for the other. No second "expected" builder existed, but the predicate and the body could disagree — and did, historically. [schedule_sync.dart:964](../lib/features/schedule/schedule_sync.dart) |
| **P3** | Full-strip by construction: `buildNglOnPresetState` → `_fullStripOnSegments`, `buildNglOffPresetState` → `_fullStripOffSegments`. NOT full-strip: the pattern path, which passes the stored `wledPayload` through — the one place scope could land without changing a builder. |
| **P4** | `splitByTimerCapacity(armable, maxSlots: kMaxWledTimers - leaseCount)` [schedule_sync.dart:1473→1671](../lib/features/schedule/schedule_sync.dart). Overflow surfaced only after the save, as *"…full (8/8). Delete an old schedule."*, naming nothing. |
| **P5** | `deviceChannelsFromConfig` derives channels from `hw.led.ins[]`, id = bus index [device_channel.dart:35](../lib/features/wled/device_channel.dart). `deviceHardwareConfigProvider` reads the **selected** device only — no union, no per-controller map. |

---

## 3. WHAT SHIPPED — `967c621`

Pathspec (21 paths, no `git add -A`, no stash):

```
lib/features/schedule/scope_sidecar.dart                        (new)
lib/features/schedule/widgets/channel_scope_picker.dart         (new)
lib/features/schedule/widgets/timer_slot_meter.dart             (new)
lib/features/schedule/{calendar_entry,calendar_entry_storage,
  calendar_entry_editor,schedule_models,schedule_sync,
  my_schedule_page,day_timeline_providers}.dart
lib/features/schedule/data/{schedule_store_sync,
  legacy_array_schedule_repository,
  subcollection_schedule_repository}.dart
lib/features/schedule/widgets/timeline_row.dart
lib/features/dashboard/wled_dashboard_page.dart
lib/services/user_service.dart
test/features/schedule/{scope_sidecar,scoped_preset,preset_satisfies,
  channel_scope_display,entry_editor_wiring}_test.dart
```

**61 new tests** across the four D-phases (13 sidecar, 15 scoped preset, 15
predicate, 19 display/slots), plus the pre-existing 18 ladder-repair tests
re-run against the new predicate as the regression net.

---

## 4. THE TWO SIDECARS

```
users/{uid}.schedule_scope        { "<scheduleId>": {"c":"<controllerId>","ch":[0,2]} }
users/{uid}.calendar_entry_scope  { "<entryStorageKey>": {"c":…,"ch":[…]} }
```

Short keys (this rides the user document, already the account's largest). `ch`
is a **flat** list of ints — never nested (#84). **Unscoped items are omitted
entirely**, so an all-channel account has no such field at all, and clearing a
scope deletes its row rather than leaving a tombstone.

Written in the SAME `update()` / transaction as the items themselves, so an item
and its scope cannot be half-persisted.

### The subcollection could not have one on its own documents

The obvious placement is wrong, and it is worth stating because a reviewer will
reach for it: a per-schedule document is written by an old build with `.set()`,
which **replaces the whole document** and would take any sidecar field with it.
The array store is safe only because `update({'schedules': …})` names one field
and leaves siblings alone. So both backends read the **user-doc** sidecar;
`SubcollectionScheduleRepository` pays one extra user-doc read, and only when
something actually lost its scope.

### Old-build simulation results

`test/features/schedule/scope_sidecar_test.dart` strips exactly the pre-D1
`toJson()` key set from every entry and reloads:

| Store | Result |
|---|---|
| Calendar | `channels` **recovered** `[0]`, `controllerId` **recovered** `ctrl-A`; the unscoped sibling stays unscoped |
| Schedules | `channels` **recovered** `[1]`, `controllerId` **recovered** `ctrl-B` |
| Both — **control** | With the sidecar withheld, the scope IS lost. This is what proves the tests exercise the sidecar rather than `toJson` |
| Both | Clearing a scope removes its sidecar row |
| Calendar | Model field wins over a stale sidecar when they disagree |

---

## 5. THE ONE PREDICATE

```dart
presetSatisfies(stored, builderOutput, {expectedName, compareSegments,
                                        requireAllExpectedSegments})
```

**Replaced, as logic:** `isNglOnPresetSatisfied`, `isNglOffPresetSatisfied`,
`_presetAllSegmentsOn`, `_presetIsOff`. The last two are **deleted**.

**Call sites updated** — `psaveIfChanged` no longer takes an `isSatisfied`
parameter at all, so a caller cannot supply a bar that disagrees with what it is
about to write:

| Site | Before | After |
|---|---|---|
| preset 1 `NGL On` | `isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL On', repairSegments: repairLadder)` | `compareSegments: repairLadder` |
| preset 2 `NGL Off` | `isSatisfied: isNglOffPresetSatisfied` | *(derived)* |
| preset 3 `NGL Dim` | as preset 1 | `compareSegments: repairLadder` |
| preset 4 `NGL Low` | as preset 1 | `compareSegments: repairLadder` |
| preset 5 `NGL Medium` | as preset 1 | `compareSegments: repairLadder` |
| pattern 10–25 | `isSatisfied: (_) => false` | `alwaysWrite: true` |

**Two names survive as one-line adapters**, carrying no logic:
`isNglOnPresetSatisfied` and `isNglOffPresetSatisfied`. Their callers are outside
this file — the on-connect healer
([controller_defaults_healer.dart:1085, :1154](../lib/features/wled/controller_defaults_healer.dart)),
the sunrise-off writer
([sunrise_off_service.dart:229](../lib/features/schedule/sunrise_off_service.dart)),
and three hardware tests. **Collapsing those in the same commit would have
changed when the healer repairs presets on every customer's controller, inside a
change whose subject is something else.** Leaving them as adapters means those
call sites now exercise the new predicate, which is the strongest regression net
available: all 18 existing `base_ladder_repair_test.dart` assertions pass
unchanged.

**Two fields are deliberately not asserted**, both preserving existing rules:

- **`ib`** — a psave request flag, never stored. Asserting it would mark every
  preset on every controller broken.
- **`bri`** — `psave` applies its inline state live, so a needless re-save is a
  visible flash on a customer's house. Brightness drift is cosmetic. Root `on`
  remains the only master-state field asserted, because its absence is what
  actually breaks firing.

The removed rationale — *"the app cannot record a deliberate channel
exclusion"* — is gone, as instructed. It was true when written and is not now.

### ⚠️ A revert worth recording

The first implementation returned **false** when the controller's preset lacked
a segment the builder named. Strictly more correct — such a preset provably does
not control that segment (U-7) — and it broke an existing test, which is how I
caught it.

But the old `_presetAllSegmentsOn` never counted segments. Tightening it would
have started a **fleet-wide ladder repair on the next sync**, with a visible
flash per controller, on every account whose presets predate
`_fullStripOnSegments` — which U-7 shows includes the bench rig's own presets
2/3/4/5/10/11. That is a real change to what customers' houses do and it is not
this change's to make.

Resolved as: **silence is not contradiction for an all-channel intent, but it is
for a scoped one** (`requireAllExpectedSegments`), because for a scope a missing
segment means the exclusion was never written and psave captured whatever was
live. Both branches are tested.

---

## 6. BENCH RESULTS

### Scoped OFF leaves the other channel lit — CONFIRMED

Controller `.150`, both channels lit distinctly, then the exact body
`buildNglOffPresetState(live, channels:[0])` produces:

```
psave 250  ←  {"seg":[{"id":0,"on":false}]}        (no root on:false)

both lit again:  seg0 red        seg1 green
{"ps":250}    →  master on=TRUE
                 seg 0 on=FALSE  col=[255,0,0,0]
                 seg 1 on=TRUE   col=[0,255,0,0]   ← STILL LIT
```

Stored preset readback: **root `on` ABSENT**, `ib` ABSENT, seg 1 stored
`on:true`. Exactly the D2 contract — and a direct demonstration of why a scoped
OFF must not inherit `NGL Off`'s root-power kill.

### Healer / scoped preset survival — verified in unit, NOT as an app run

**Stated plainly rather than glossed:** I could not drive the app's on-connect
healer from a shell, so the bench half of D3 was not performed as an app run.
What was verified:

1. **Unit** — a scoped preset matching its intent satisfies the new predicate
   (`preset_satisfies_test.dart`, "the healer leaves them alone"), and an all-on
   preset does *not* satisfy a scoped intent, so it repairs *to* the scoped
   shape.
2. **Code** — the healer's repair set is `kOnPresetSpecs` = presets **1, 3, 4,
   5** plus preset 2. It does **not** touch the 10–25 schedule range where a
   scoped schedule's preset lives.

**Which means the F2-3 threat was narrower than the audit implied, and I should
say so rather than claim a rescue.** A scoped *schedule* preset is written with
`alwaysWrite: true` every sync, so it is re-asserted from its scoped intent and
can never be clobbered to all-on. The predicate change matters for any *future*
scoped ladder preset and removes the structural drift; it is not repairing an
active fleet defect.

---

## 7. KNOWN, UNCHANGED — the root-`on:false` partial façade

Not fixed here; unchanged for all-channel items, per the brief. Evidence from
U-7 Test 3 on `.150`:

```
before   seg 0 on=true col=[255,0,0,0]     seg 1 on=true col=[0,255,0,0]
{"ps":2}                                    ("NGL Off", root on:false, 1 seg)
after    master on=FALSE
         seg 0 on=false col=[255,160,0,0]  ← named by the preset
         seg 1 on=TRUE  col=[0,255,0,0]    ← NEVER TOUCHED
```

`NGL Off` darkens the house by killing **master power**; seg[1] remains
`on:true`. Anything that turns the master back on — another preset, a manual
tap, `def.on` after a reboot — relights it at its last colour. The same shape
holds for the Dim/Low/Medium ladder (3/4/5) and pattern presets 10/11: each names
only seg[0], so on this 2-segment rig **they have never controlled seg[1] at
all.**

This is the class already recorded against Ellie's two-segment controller in
`memory/project_solar_schedules_never_fire`. Fixing it means letting the ladder
repair run stricter — see the revert in §5, and the reason it was not done here.

---

## 8. OPTIONAL PROBE — API-command preset

**NOT REACHABLE via the JSON API; unverified.** A `psave` carrying `win` is
accepted (`{"success":true}`) but the key is **ignored** — slot 250 stored an
ordinary two-segment state preset, not an API command. Creating one requires
uploading a hand-crafted `presets.json` through `POST /edit`, which the sandbox
classifier blocked (also in U-7). So whether a timer firing an `SS=`-scoped API
command leaves the other segment untouched **remains open**, and the "untouched"
option stays unavailable. Scratch preset deleted; rig restored.

---

## 9. D5 GATE

**dow:0 guards — all nine intact** (line numbers post-change):

`schedule_providers.dart:423` (def), `:639` (add), `:716` (addAll) ·
`cfg_payload_builder.dart:193` · `schedule_sync.dart:837`, `:1625` ·
`calendar_entry_lease_manager.dart:1430` · `scheduling_intent_handler.dart:470` ·
`autopilot_providers.dart:611`

**Untouched paths — asserted, not assumed.** `git diff --name-only main..HEAD`
plus the working tree, filtered for `base_layer_gate|fireJobs|dispatchFireJobs|
planGameDayFires|gameDayPlanning|teardownTeamFires|commandSafety` → **no match.**

**`schedule_sync.dart`: 33 hunks, +365 / −62.** By region:

| Hunks | Region | What |
|---|---|---|
| 1–4 | `buildNglOffPresetState` / `buildNglOnPresetState` | scope params; scoped OFF drops root `on`/`ib` |
| 5 | new, before the ON predicate | `presetSatisfies` — the one predicate |
| 6–8 | the two old predicates | reduced to adapters + `_liveStateFromStoredPreset` |
| 9–11 | `psaveIfChanged` | `isSatisfied` param removed; derived; `compareSegments`/`alwaysWrite`/`scoped` added |
| 12–16 | the five ladder/OFF call sites | predicate arguments replaced |
| 17–20 | the pattern-preset path | `scopePatternPayload` inserted |
| 21–30 | `_fullStripOffSegments` / `_fullStripOnSegments` | scope params + `scopePatternPayload` |
| 31–33 | end of class | `_presetAllSegmentsOn` / `_presetIsOff` deleted |

---

## 10. DEFERRED, AND WHY

| # | Deferred | Why |
|---|---|---|
| E1 | **The ladder never carries a scope.** `buildNglOnPresetState` is called with `channels: null` at all four sites. | The NGL ladder IS the all-channel base layer; scoping it would be a different feature. The `channels` parameter exists for a future scoped ladder and is fully tested. |
| E2 | **`scoped:` on `psaveIfChanged` has no production caller.** | Follows from E1: the only scoped preset today is the pattern path, which uses `alwaysWrite`. Kept because it is the correct plumbing for E1 and is under test. |
| E3 | **Multi-controller picker.** Per P5, the picker offers the *selected* controller's channels and stamps its id; scoped rows show the controller name in a multi-controller home. No cross-controller UI. | Explicit decision. |
| E4 | **Sync does not yet filter a scoped item to its `controllerId`.** The id is stored, displayed, and available; `syncAll` still arms against the connected controller. | Arming per-controller is a change to which device a schedule reaches — a firing-layer routing change beyond "scope the preset body". The field is in place for it. |
| E5 | **The `NGL Off` / ladder partial façade.** §7. | Instructed to record, not fix. |
| E6 | **`_fullStripOffSegments`'s degraded path with a scope** names the requested ids directly rather than guessing a single seg. | The alternative — one unscoped `{on:false}` — would darken everything on a cloud-relay/mock path. Stated in code. |

---

## 11. WHAT I WOULD HAVE HAD TO FABRICATE, AND DIDN'T

- **Whether an absent segment is left alone.** Measured (U-7), three times, from
  presets the fleet actually runs.
- **Whether `psave` can omit a segment.** Tried it two ways — omission and
  `sel:false` — and reported that it cannot, which changed D2's design.
- **The `/edit` synthetic-preset case and the `win` API-command case.** Both
  blocked by the sandbox; reported as blocked and unverified rather than
  reasoned about. The `win` result is a genuine measurement (the key is ignored);
  the timer-firing-an-API-command question is *not* answered.
- **The healer bench run.** Not performed as an app run; §6 says so and states
  exactly what was verified instead.
- **The scope of F2-3.** The audit implied the healer was actively clobbering
  scoped presets. It is not — it never touches the 10–25 range. Reported as a
  narrowing rather than left as an implied rescue.
- **The old predicate's exact bar.** Rather than assume `_presetAllSegmentsOn`
  counted segments, the first implementation was run against the existing suite,
  which disagreed — and the revert in §5 follows from that, not from a guess.
- **A slot-accounting formula.** `slotsForSchedule` mirrors
  `splitByTimerCapacity`'s rule (clock on, clock off, solar free) rather than
  inventing a second one.
