# SOLAR FIX PLAN — locate the flag, then sequence the repair

**Date:** 2026-08-02 · **Status:** SCOPING ONLY — read-only. No writes, no flag changes, no
branches. Nothing here has been implemented.
**Predecessor:** `audit/ELLIE_SUNSET.md`

---

## STEP 1 — WHERE IS THE FLAG?

**It is nowhere. The "wrong project" theory is disproven.**

Both projects were read directly via `gcloud` ADC (`honeycutt.tylerg@gmail.com`) against the
Firestore REST API:

```
nex-gen-lumina-22751            → root collections: (NONE — empty database)
                                  config/ collection: (no documents)

icrt6menwsv2d8all8oijs021b06s5  → root collections: analytics, app_config, brand_library,
                                  bridge_registry, config, dealer_demo_codes, dealers,
                                  installation_records, installations, installers,
                                  invitations, neighborhoods, product_catalog,
                                  referral_codes, staff_auth_log, staff_auth_rate_limit, users
                                  config/: calendar_leases, schedules_subcollection, sync_fanout
```

`nex-gen-lumina-22751` has **no Firestore data whatsoever**. It is not a stale copy of the fleet —
it is empty. So:

- **`config/solar_scheduling` has never existed in either project.**
- **No other flag can have diverged between projects.** There is nothing in the second project to
  diverge to. `calendar_leases`, `schedules_subcollection` and `sync_fanout` exist only in the
  real project and are the complete flag set.

**What this leaves unexplained:** what was actually done on 2026-07-28 when solar was declared
live. Options — a console edit that didn't persist, a different doc path, a local/debug override,
or "solar is live" meaning the *code* shipped rather than the *flag* flipped. This needs Tyler's
recollection; it is not recoverable from the data.

**Nothing for Tyler to check in the other console.** It is empty. If he remembers flipping a
toggle, the question is *which UI* he flipped it in, not which project.

---

## STEP 2 — THREE THINGS STACKED BEHIND THE FLAG

### (a) NARROW THE GATE — and the minimal fix is smaller than it looks

[cfg_payload_builder.dart:156-164](../lib/features/schedule/cfg_payload_builder.dart#L156):

```dart
if (!solarEnabled) {
  if (onSolar || offSolar) { debug?.call('... skipped solar timer ...'); continue; }
}
```

**The `continue` is redundant.** The loop already guards each boundary individually, twenty lines
below — `if (!onSolar) { build ON }` at :166 and `if (... && !offSolar ...) { build OFF }` at :180.
Deleting the `continue` block leaves per-boundary skipping already correct. This is a
deletion, not a rewrite.

**But deleting it alone would make things worse, and this is the important part.**

Tim Kelly today: ON=Sunset (dropped), OFF=1:00 AM. All his schedules are solar-tainted, so the
payload is empty, the empty-armed guard fires, and he gets a **red error and nothing armed**.
After a naive narrowing: his 1:00 AM OFF arms, `scheduleIns` is non-empty, the guard does **not**
fire, and the sync reports **green success** — while his lights never come on. He would go from a
loud failure to a silent half-failure. **That is a new silent-success instance, manufactured by
the fix.**

So narrowing the gate is only safe if it ships **together with** a user-visible warning per
dropped boundary. Scope:

- Delete the `continue` block; per-boundary guards already handle the rest.
- For each dropped solar boundary, append to `presetErrors` naming the schedule and the boundary:
  *"'Captain America' will turn OFF at 1:00 AM but will not turn ON — sunset scheduling is not
  available on this controller."*
- **A half-armed schedule must never report plain success.** A schedule that arms its OFF and not
  its ON is arguably worse than one that arms nothing: the lights go off on a timer that the user
  cannot see the other half of.

**Open product question, not mine to decide:** is half-arming desirable at all? The alternative is
to keep refusing the whole schedule but say clearly *why*. For Tim specifically, a lone 1:00 AM
OFF has no user value. I'd lean toward refusing the schedule whole with a clear message, and
treating (a) as a *messaging* fix rather than a *behavioral* one — but that is Tyler's call and it
changes the work materially.

### (b) SOLAR ROWS ARE UNVERIFIABLE — HARD BLOCKER

[timer_landing.dart:11-17](../lib/features/schedule/timer_landing.dart#L11) —
`isRealEnabledTimer` returns `enOn && macro != 0 && hour != 255`. Every solar row is excluded
from both sides of `timersInsLanded`:

- `sentReal` filters them out, so no solar row is ever *required* to be present.
- The cleared-schedule branch, `!readback.any(en==1 && hour != 255)`, explicitly ignores them.

**Flip the flag today and every solar row verifies clean whether it landed, landed wrong, or never
landed at all.** This is the same structural blindness as P0-8 (out-of-range bounds), one layer
over.

**Scope for a solar comparator** — and it cannot simply match by array index:

1. **Positional pairing, not index equality.** WLED compacts the readback: it echoes real entries
   plus the solar sentinels and drops disabled stubs, so the 255-entries **trail** the general
   ones. Per [sunrise_off_service.dart:257-261](../lib/features/schedule/sunrise_off_service.dart#L257),
   the rule is ordinal: **first 255-entry = sunrise (sent slot 8), second = sunset (sent slot 9).**
   The comparator must pair sent-slot-8 → first readback 255, sent-slot-9 → second.
2. **Compare `en`, `macro`, `dow`** as for general timers.
3. **Compare `min` as a SIGNED offset** (−120..+120), *not* as a minute.
4. **Verify sign round-trip at the bench before trusting it.** If the firmware stores the offset in
   an unsigned byte, `min: -30` may read back as `226`. Latent today because the offset is
   hardcoded 0 (no editor UI), which is precisely why it would slip through unnoticed and then
   break the first time an offset ships.
5. Assert `hour == 255` on the readback entries — that is the marker, not a value to ignore.

### (c) FIRST-WINS CONTENTION — surfaced as a count, with the text thrown away

Ellie has **two** Sunset schedules. The moment solar works, `solarTimerSlots` rejects one and
composes: *"Only one sunrise and one sunset schedule are supported per controller — 'X' was not
armed."*

It is **not** a `debugPrint` — it goes into `presetErrors`. But trace where `presetErrors` is
displayed:

- [my_schedule_page.dart:288-292](../lib/features/schedule/my_schedule_page.dart#L288) — SnackBar
  reading, in full: **"Schedule saved with warnings"**.
- [my_schedule_page.dart:719-723](../lib/features/schedule/my_schedule_page.dart#L719) — status row:
  **"Synced with 1 warning · 2m ago"**.

**Neither renders the message text.** The composed explanation — which schedule, and why — is
discarded at the UI boundary. So the customer who reported this bug would be told "1 warning" and
never which of her two schedules stopped working.

This is a **shared defect, not a solar one**: every `presetErrors` message in the codebase is
composed carefully and then reduced to a count. Fixing the display is the highest-leverage item
in this whole plan, because (a) depends on it too.

---

## STEP 3 — THE ABORT MESSAGE, AND WHETHER ANYTHING IS VISIBLE

**Correction to the working assumption: the abort IS visible.** The three customers have not been
syncing into a void.

- [my_schedule_page.dart:282-287](../lib/features/schedule/my_schedule_page.dart#L282) — on
  `!result.success`, a **red SnackBar** showing `result.error` verbatim.
- [my_schedule_page.dart:714-717](../lib/features/schedule/my_schedule_page.dart#L714) — a
  persistent status row, red `cloud_off` icon, label = `last.error`.

So Ellie, Tim and Chris have each been shown, repeatedly:

> **internal: enabled schedules produced no armable timers**

That is worse than silence in one specific way: it is visibly broken *and* uninterpretable, so it
trains the user to ignore the status row. It contains no reference to sunrise, sunset, or solar,
and no remedy. The `continue` that actually dropped the schedules logs only via `debugPrint`,
invisible in release.

**Scope:** the abort should name cause and remedy, and the sync layer already has the information
to do it — `buildCfgPayload` knows exactly which schedules it dropped and why. Pass that reason up
instead of discarding it. Target text along the lines of:

> *"Sunset/sunrise scheduling isn't available on this controller yet, so none of your schedules
> could be armed. Set a specific time (e.g. 8:00 PM) to have them run."*

The `internal:` prefix should never reach a customer at all; that string reads like a developer
assertion, which is what it is.

---

## STEP 4 — IS THE UI OFFERING A DEAD FEATURE?

**Yes, from five separate surfaces, none of which is gated on the flag.**

`solarSchedulingEnabledSyncProvider` has **exactly one consumer in the entire codebase**:
[schedule_sync.dart:666](../lib/features/schedule/schedule_sync.dart#L666). Nothing in the UI
reads it.

| Surface | Evidence | Behavior |
|---|---|---|
| **Schedule editor** | [my_schedule_page.dart:4361-4363](../lib/features/schedule/my_schedule_page.dart#L4361) | Offers `Sunrise` / `Sunset` buttons outright |
| **Autopilot baseline** | [autopilot_providers.dart:557](../lib/features/autopilot/autopilot_providers.dart#L557) | **Generates** `timeLabel='Sunset'` automatically |
| **AI window** | [scheduling_intent.dart:98-99,160,189](../lib/features/ai/scheduling_intent.dart#L98) | Prompt schema instructs the model to emit `"Sunset"`/`"Sunrise"` |
| **Commercial events** | [create_event_screen.dart:235](../lib/features/commercial/events/create_event_screen.dart#L235) | Defaults `timeLabel: 'Sunset'` |
| **Neighborhood sync** | [schedule_list.dart:1085](../lib/features/neighborhood/widgets/schedule_list.dart#L1085) | `_useSunset` toggle |

The editor *does* gate on clock health — [my_schedule_page.dart:4215-4222](../lib/features/schedule/my_schedule_page.dart#L4215)
raises `LOCATION_UNSET` for solar schedules — so someone was thinking about solar preconditions.
**The feature flag was simply never wired into that check.**

**The autopilot row is how this happened.** The default baseline is *"Warm white from sunset, off
at sunrise"* ([my_schedule_page.dart:2848](../lib/features/schedule/my_schedule_page.dart#L2848)),
and it is exactly Ellie's second schedule (`id: autopilot-8680a32b-…`). **Users do not have to
choose sunset — enabling autopilot creates an unarmable solar schedule for them.** That is the
likely path for all three affected accounts, and it means the population will keep growing on its
own until either the flag or the UI gate lands.

---

## STEP 5 — SAFE ORDER OF OPERATIONS

Ordered so that no step can manufacture a silent failure that a later step cleans up.

| # | Step | Why this position | Verifiable where |
|---|---|---|---|
| **1** | **Render `presetErrors` text** in SnackBar + status row instead of a count | Everything downstream emits warnings into a channel that currently discards them. Doing this last would mean shipping steps 2-4 blind | Bench / widget test |
| **2** | **Replace the abort message** with cause + remedy; drop the `internal:` prefix | Pure messaging, no behavior change; immediately improves the live experience of 3 customers | Bench / unit test |
| **3** | **Decide half-arm vs refuse-whole** (product call), then narrow or keep the gate accordingly, emitting a per-boundary warning either way | Depends on #1 existing. If half-arm is chosen without #1, it creates the Brooke shape at scale | Bench |
| **4** | **Build the solar comparator** (§2b) + unit tests | **Hard blocker on the flag flip.** Must exist before any solar row is trusted | Bench, unit |
| **5** | **Gate the five UI surfaces on the flag** — especially the autopilot baseline | Stops the affected population growing. Independent of the flip, valuable even if solar stays off | Bench |
| **6** | **Bench-verify solar end-to-end** on .150 with the comparator: row lands at slots 8/9, correct `en`/`macro`/`dow`, offset sign round-trips | The original bench gate, now actually checkable | **.150, requires waiting for real dusk** |
| **7** | **Create `config/solar_scheduling` with `enabled:true`** — only after 1-6 | The flip everyone thought had happened | Firestore console |
| **8** | **Re-check first-wins on Ellie** — she has two Sunset schedules and one will be rejected | Only observable once solar actually works | Her controller |

### What is bench-verifiable vs what needs a customer's controller

**Bench (.150) covers:** the gate, all messaging, the comparator, UI gating, row landing at slots
8/9 with correct fields. One real constraint — **verifying a solar row actually *fires* requires
waiting for real dusk**, roughly one attempt per day. Landing can be checked in seconds; firing
cannot be rushed.

**Needs a customer's controller (cannot be bench-tested):**
- **Ellie is bridge-paired and remote-access enabled.** `repoCanWriteCfg` short-circuits cfg
  writes to `deferredOffLan` — the bridge routes everything but `getState`/`getInfo` to
  `/json/state`, where WLED discards cfg keys. **She has never reached that check** (the abort
  fires first), but after the fix it becomes the next gate. **Anyone testing on her account must
  confirm she is on her home LAN, or the fix will look like it failed.**
- First-wins contention on a real two-solar-schedule account (§2c).
- Her 1-controller / 89-LED record vs the reported two-channel façade (see `ELLIE_SUNSET.md` §5).

### What to tell the three customers now

There is an **effective workaround available today that needs no code**: replace the sunrise/sunset
boundaries with specific clock times. Clock schedules arm correctly — B1/B2/B3-wrap proved the
firmware path is sound, and Brooke's seven non-solar schedules arm today.

Suggested substance, for Tyler to word: *"Sunset/sunrise timing isn't working on your system yet —
that's a bug on our side, not anything you did. Set a specific time for now (around 8:15 PM is
close to sunset this month) and your lights will run on schedule. We'll let you know when
sunset tracking is ready and switch you back."*

**Two cautions for that conversation:**
1. **The autopilot baseline will recreate a Sunset schedule.** If the customer has the *"Warm white
   from sunset, off at sunrise"* baseline enabled, it regenerates solar labels and will undo a
   manual clock-time edit. It has to be switched off as part of the workaround, or the fix won't
   hold.
2. **Ellie must be on her home Wi-Fi when she edits**, or the timers defer off-LAN and nothing
   arms even with valid clock times.

---

## OPEN QUESTIONS FOR TYLER

1. **Half-arm or refuse-whole** when one boundary is solar? Changes the work in step 3 materially.
2. **What was actually flipped on 2026-07-28?** Not recoverable from the data; both projects
   checked.
3. **Should the customer-facing guides be corrected now?** They currently describe solar
   scheduling as a working feature ([[project_guide_docs_canonical_set]]). If the flip is more than
   a few days out, they are actively misleading — including the installer SOP.
