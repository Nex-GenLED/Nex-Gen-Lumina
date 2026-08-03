# SOLAR FIX — implementation report

**Date:** 2026-08-03 · **Scope:** steps 1-3 implemented, step 4 investigated only.
**Not done, deliberately:** `config/solar_scheduling` NOT created; solar comparator NOT built.
**Product decisions applied (Tyler, 2026-08-02):** refuse-whole (the `continue` stays); guides
handled separately.

---

## 0. A PREMISE CORRECTION THAT CHANGED THE WORK

`SOLAR_FIX_PLAN.md` step 3 said three customers repeatedly see
`internal: enabled schedules produced no armable timers`. **They do not.** A parallel session
caught this and it is correct.

There is a solar gate **inside the `armable` loop**
([schedule_sync.dart:1066-1077](../lib/features/schedule/schedule_sync.dart#L1066)) that I missed
when writing `ELLIE_SUNSET.md`:

```dart
if (solarLabels.isNotEmpty && !solarEnabled) {
  presetErrors.add('"${s.actionLabel}" uses sunrise/sunset timing, which $why.');
  continue;                       // ← never reaches armable.add(s)
}
```

For an all-solar account `armable` is **empty**, so `armedSchedules` is empty, so the empty-armed
guard's first conjunct is false and **it never fires**. Two consequences:

1. **The abort message was never the customer-facing symptom.** What Ellie, Tim and Chris actually
   see is the orange *"Schedule saved with warnings"*.
2. **A correct, specific, actionable message already existed** — composed at that `presetErrors.add`
   and even distinguishing flag-off from coords-missing — and was thrown away by the count-only
   display.

**So step 1 was not merely first; it was the whole customer-facing fix.** Step 2 became a
correctness cleanup of a message that fires only on a genuine internal inconsistency.

---

## 1. RENDER `presetErrors` TEXT — the linchpin

**[my_schedule_page.dart](../lib/features/schedule/my_schedule_page.dart)**

- **SnackBar** (was `'Schedule saved with warnings'`): now shows the first warning verbatim; with
  more than one, `first + "+N more"` plus a **Details** action opening the dialog. Duration 3s → 6s
  because there is now something to read.
- **Status row** (was `'Synced with 1 warning · 2m ago'`): now leads with the real message and, for
  N>1, `+N more — tap for details`. The whole row becomes an `InkWell` opening the dialog.
  This row *already* wrapped without ellipsis (deliberate, bench 2026-07-23) — it was built to hold
  long remedy text and simply never given any.
- **New `showScheduleWarningsDialog(context, warnings)`** — bulleted, scrollable, count in the
  title. A dialog is the only treatment that stays readable for N messages.

**Why this fixes more than solar.** The display is source-agnostic: it renders whatever is in
`presetErrors`. Every refuse point in `schedule_sync.dart` — solar-not-enabled, `dow:0`, dead
macro, slots-full (8/8), sunrise-off conflict, solar slot contention — already composes a named,
actionable message and now all of them reach the user. First-wins contention (`SOLAR_FIX_PLAN` §2c),
which would have hit Ellie the moment solar works, is covered by construction rather than by a
separate change.

**Scope correction:** the plan called this defect "every presetErrors message in the codebase."
Checked — `presetErrors` has exactly these two display sites, both fixed. Two other
"with warnings" strings exist ([controller_setup_screen.dart:1373](../lib/features/installer/screens/controller_setup_screen.dart#L1373),
[manage_controllers_page.dart:170](../lib/features/site/manage_controllers_page.dart#L170)) but
they are a different type (`result.warnings`), and the latter already joins and displays its text.

---

## 2. THE ABORT MESSAGE

**[schedule_sync.dart](../lib/features/schedule/schedule_sync.dart)** — behavior unchanged, as
instructed; the guard is working and is why this failed loudly rather than false-greening.

> Your schedules are saved but could not be armed on the controller. Try syncing again — if this
> keeps happening, contact support.

**I did not use the suggested sunset/sunrise wording, and deliberately so.** Given §0, solar
schedules are refused upstream and never reach this guard. Reaching it means a schedule passed
every arm check and still produced no timer — an internal inconsistency, not a user
misconfiguration. Telling that user to "set a specific time" would send them to fix something that
isn't wrong. The `internal:` prefix is gone; the diagnostic detail stays in `debugPrint`. A comment
at the site records why the message must *not* mention solar, so it isn't "corrected" later.

---

## 3. GATE THE FIVE UI SURFACES

Before this change `solarSchedulingEnabledSyncProvider` had exactly one consumer in the codebase.

| Surface | File | Behavior with flag OFF |
|---|---|---|
| **Autopilot baseline** | [autopilot_providers.dart](../lib/features/autopilot/autopilot_providers.dart) | Emits **clock times**, not `Sunset`/`Sunrise` |
| Schedule editor | [my_schedule_page.dart](../lib/features/schedule/my_schedule_page.dart) | `Solar` segment **disabled** (both ON and OFF pickers); new-schedule OFF default flipped to clock |
| AI window | [lumina_ai_service.dart](../lib/lumina_ai/lumina_ai_service.dart) + [lumina_brain.dart](../lib/features/ai/lumina_brain.dart) | Hard constraint appended: never emit `"Sunset"`/`"Sunrise"` |
| Commercial events | [create_event_screen.dart](../lib/features/commercial/events/create_event_screen.dart) | Activate `7:00 PM`→`11:00 PM`, revert `6:00 AM` |
| Neighborhood sync | [schedule_list.dart](../lib/features/neighborhood/widgets/schedule_list.dart) | "Start at sunset" checkbox disabled, labelled *(unavailable — pick a time)* |

### Autopilot — the important one, and the fallback is exact, not invented

This is how all four affected accounts got here: the default baseline is *"warm white from sunset,
off at sunrise"*, so a user who never touched a solar control still got solar labels. Ellie's second
schedule (`autopilot-8680a32b-…`) is exactly this.

The code already computed the real clock time and then overwrote it:

```dart
String timeLabel = _formatTime(localTime, timeFormat);   // ← already "sunset o'clock"
if (item.trigger == AutopilotTrigger.sunset) timeLabel = 'Sunset';   // ← discarded it
```

`item.scheduledTime` comes from `SunUtils.sunsetLocal()` via `AutopilotScheduler`, so with the flag
off we simply **stop overwriting** — the ON time is the genuine sunset for the generation date, not
a guess.

The OFF boundary had no equivalent, so `_clockSunriseLabel()` resolves the **actual next sunrise**
from the user's coordinates (`SunUtils.sunriseLocal`, next morning — sunset schedules run
overnight). `latitude`/`longitude` are threaded from `UserModel`; all four affected accounts have
them.

**Fixed fallback `06:00`, used only when coordinates are absent** (a coordinate-less account cannot
compute sunrise at all). Justification: at mid-latitudes 6 AM is after sunrise for roughly half the
year and before it for the other half, so it errs toward switching off slightly early rather than
leaving a house lit into full daylight, and it is a round number a user recognises as a default and
can change.

### Editor — disabled, not removed

`ButtonSegment(enabled: solarEnabled)` rather than dropping the segment. Removing it would make
`SegmentedButton` **assert** when an existing solar schedule hydrates `_onTrigger`/`_offTrigger` to
`solarEvent` (selected value absent from segments) — i.e. it would crash the editor for exactly the
four affected customers. Disabled-but-present also leaves `Time` selectable, which is what allows a
stranded schedule to be converted in place (see §4).

Also flipped: `_offTrigger`'s field default is `solarEvent`. Left alone, opening the editor and
saving would mint a fresh unarmable schedule for a user who never touched the Solar control — the
autopilot bug in miniature. `initState` now falls back to the clock default when the flag is off,
while an existing schedule still hydrates to whatever it was saved with.

### AI window — appended, not edited

`_kSmartSystemPrompt` is a compile-time `const` assembled from
`SchedulingIntent.schemaPromptFragment` (the #58 single-source-of-truth, pinned by an equivalence
test), so it cannot vary at runtime. A trailing **"SCHEDULING CONSTRAINT (OVERRIDES SCHEMA)"**
block instructs the model to never emit solar labels, to substitute a sensible clock time, and to
*say so* in its reply. `chat()` gained `bool solarSchedulingEnabled = true` (defaulted so tests and
non-Riverpod callers are unaffected); `LuminaBrain.chat` passes the live flag, read defensively.

---

## 4. EXISTING AFFECTED SCHEDULES (investigated, not fixed)

| Question | Answer |
|---|---|
| Do they still display? | **Yes.** Nothing filters the list; Firestore is untouched. |
| Do they still fail to arm? | **Yes** — refuse-whole was the product decision. Behavior is unchanged by design. |
| Is the failure still invisible? | **No.** This is the change that matters for them: they now get *"'Warm White (Daily evening lighting)' uses sunrise/sunset timing, which isn't supported yet — please set a specific time."* naming the schedule and the remedy. |
| Can they be edited to clock times without deleting? | **Yes** — this drove the disable-don't-remove choice. Open the schedule, tap **Time**, pick a time, save. |
| Does the editor break on them? | **No.** Verified by reasoning about the hydrate path; this is precisely what removing the segment would have broken. |

**Per account:**

- **Ellie** — 2 solar schedules. `autopilot-8680a32b-…` **self-heals on the next autopilot
  generation** (clock times now). `sch-1785688919895` is hers manually and needs a manual edit.
- **Tim Kelly** — 1 schedule, ON=Sunset / OFF=1:00 AM. Still refused whole (decision). Now told why.
- **Chris Cipollone** — 1 autopilot-style solar schedule; expected to self-heal on next generation.
- **Brooke Rozenberg** — 7 clock + 1 solar. Her sync still reports success, but the dropped
  schedule is **no longer silent** — the warning names it. This was the plan's "silent partial".

---

## ⚠️ NOT ADDRESSED BY THIS CHANGE — the all-stub clobber

`audit/SOLAR_FAILURE.md` (parallel session) documents that for an all-solar account `armable` is
empty → `buildCfgPayload([])` → `padTimersToMax([])` → **8 disabled stubs POSTed**, erasing the
controller's timer table. Only `repoCanWriteCfg`/`deferredOffLan` has prevented it so far.

**Nothing here changes that.** My edits touch messaging and UI gating; the payload path is
untouched. **Do not trigger a LAN sync on Ellie / Tim Kelly / Chris Cipollone until that is
bench-checked.** It is arguably now more likely to be hit, because a user who finally sees a
readable warning is more likely to press Sync.

---

## VERIFICATION

| Check | Result |
|---|---|
| `flutter analyze` on all 7 touched files | **0 errors, 0 warnings.** 15 `info` remain — pre-existing deprecations + `prefer_interpolation` |
| Full suite | **1857 passed · 3 skipped · 1 failed** |
| Failing test | `cloud_ai_processor_normalize_test.dart` — *"typed coercion: garbage field values…"*. **Pre-existing and stale** (asserts the `'Sunset'` default deliberately removed by `b6ca2f1`); matches the known single pre-existing failure. **No new failures.** |
| Solar schedule → readable specific error | Yes — the existing named message now renders at both sites |
| Non-solar warnings render too | **By construction** — the display is source-agnostic, so dow:0 / dead-macro / slots-full / first-wins all surface. Not separately exercised on hardware |
| Autopilot with flag off → clock baseline | Implemented; the ON time is the pre-existing `_formatTime(localTime)` and the OFF is `SunUtils.sunriseLocal`. **Reasoned from the code path, not executed** — `_convertToScheduleItem` is private and needs a `ref`, so there is no unit seam for it today |

**Honest gap:** the autopilot clock-baseline behavior has no automated test. Adding one needs a
seam that doesn't exist yet (extract the label resolution into a pure function, as
`cfg_payload_builder`/`timer_landing` were extracted). Worth doing, out of scope here.

---

## FILES CHANGED

```
lib/features/schedule/my_schedule_page.dart        warning display + dialog + editor gate + default
lib/features/schedule/schedule_sync.dart           abort message
lib/features/autopilot/autopilot_providers.dart    solar gate + clock sunrise fallback
lib/lumina_ai/lumina_ai_service.dart               chat() solar constraint
lib/features/ai/lumina_brain.dart                  pass the live flag
lib/features/commercial/events/create_event_screen.dart   clock fallback (activate + revert)
lib/features/neighborhood/widgets/schedule_list.dart      sunset checkbox gate
```

No branch created, no flag document created, no comparator work — as instructed.
