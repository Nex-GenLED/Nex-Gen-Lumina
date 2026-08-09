# BASE LADDER — ON presets capture ambient segment state and fire dark

**Status:** root cause CONFIRMED IN SOURCE + bench-proven. Bench rig REPAIRED.
Fleet exposure UNKNOWN (no telemetry reaches it). Root fix SCOPED, **BLOCKED on a
product decision** — see §6.
**Date:** 2026-08-09 · **Rig:** controller `192.168.1.150`

---

## 1. The defect

`ScheduleSyncService` psaves the four system ON presets with **no `seg` key**:

```dart
// schedule_sync.dart:854 (and the 3 sibling psaveIfChanged calls)
state: {'on': true, 'bri': 200, 'ib': true}
// schedule_sync.dart:389
static Map<String, dynamic> onPresetHealState(int bri) =>
    {'on': true, 'bri': bri, 'ib': true};
```

A `psave` **merges its inline state over the controller's CURRENT live state**.
With no `seg` key, the stored preset captures whatever the segments happened to be
doing at that instant. Save the ladder while a channel is off — for any reason —
and that channel is off in the base layer **permanently**.

The OFF preset, four lines up in the same file, already does it correctly:

```dart
buildNglOffPresetState(live) =>
    {'on': false, 'ib': true, 'seg': _fullStripOffSegments(live)}
```

with the comment *"a preset load only touches segments present in the preset
(bench-proven: a seg[0]-only OFF left seg1 lit)."*
**The codebase learned this lesson for OFF and never applied it to ON.**

## 2. Why it is invisible

```dart
static bool isNglOnPresetSatisfied(Map<String, dynamic> def, String expectedName) =>
    _presetNamed(def, expectedName) && def['on'] == true;
```

Name + root `on` only. A preset with every segment off satisfies this predicate,
so `psaveIfChanged` **skips it forever**. The self-heal cannot see the damage it
would need to repair.

Every layer reports success: the timer fires, the preset loads, WLED returns 200,
the app shows a correctly-armed schedule. **The house simply never lights.**

This is the third member of a family already documented in this repo — the
`ib:true` master-power defect (`9158c00`) and the frozen-segment `psave` capture
(`audit/FROZEN_SEGMENT.md`). Same shape each time: `psave` bakes transient state
into a preset that then fires wrong forever.

## 3. Bench evidence (2026-08-09)

Survey of all presets on `.150`:

| slot | name | root on | bri | segments | verdict |
|---|---|---|---|---|---|
| 1 | NGL On | true | 200 | s0:OFF s1:OFF | **fires dark** |
| 3 | NGL Dim | true | 51 | s0:OFF s1:on | lights only the excluded channel |
| 4 | NGL Low | true | 102 | s0:OFF s1:OFF | **fires dark** |
| 5 | NGL Medium | true | 153 | s0:OFF s1:OFF | **fires dark** |
| 2 | NGL Off | false | 200 | s0:OFF s1:OFF | correct |
| 10, 26, 27, 29, 33, 36, 38 | Warm White / leases | true | — | s0:on s1:on | **all healthy** |

Direct confirmation — loading preset 1 on hardware:

```
after ps:1 → root on: true   ps: 1
   seg 0 on: false   0-128
   seg 1 on: false   128-290
```

Master on, zero segments lit. No preset anywhere carried `frz:true`, so this is
**not** the frozen-segment bug.

**The split is the diagnosis.** Every lease and pattern preset is healthy; every
NGL ladder slot is damaged. Lease presets are written by the schedule-sync path
that sets segment state explicitly. The ladder captured ambient state — at four
different moments, given 1/4/5 caught both channels off and 3 caught only seg 0.
Not one bad event; a defect that fires whenever the ladder is saved.

## 4. Repair applied to the bench rig

Per slot: POST explicit state → read back and verify **before** saving → confirm
`frz` clear on both segments → `psave` with explicit `seg` + `ib:true` → re-read
`/presets.json` and verify the stored definition.

Target: master on, seg 0 on, **seg 1 OFF** (the 128-290 run lights into the
bedrooms on this rig and must stay dark). Brightnesses left at their existing
values — a brightness change was deliberately not conflated with this repair.

```
ps:1  NGL On      bri:200  s0:true  s1:false   OK
ps:3  NGL Dim     bri: 51  s0:true  s1:false   OK
ps:4  NGL Low     bri:102  s0:true  s1:false   OK
ps:5  NGL Medium  bri:153  s0:true  s1:false   OK
ps:2  NGL Off     everything OFF               untouched
```

The repair survives future syncs because it leaves `isNglOnPresetSatisfied` true —
the same predicate weakness that hid the damage now protects the fix.

### 4b. SUPERSEDED — re-repaired to FULL SCOPE, 2026-08-09

The physical constraint was lifted (both channels can run), so the ladder was
rebuilt at **seg 0 ON + seg 1 ON** — the correct default under the migration
decision (all channels on). Same discipline: explicit state → verified live
readback with `frz` clear → `psave` with explicit `seg` + `ib:true` → stored-def
re-read from `/presets.json`.

```
ps:1  NGL On      bri:200  s0:true  s1:true   OK
ps:3  NGL Dim     bri: 51  s0:true  s1:true   OK
ps:4  NGL Low     bri:102  s0:true  s1:true   OK
ps:5  NGL Medium  bri:153  s0:true  s1:true   OK
ps:2  NGL Off     everything OFF              untouched
```

Brightnesses unchanged throughout — a brightness change was never conflated with
either repair.

> **The non-representative warning from §4 is LIFTED.** The ladder now sits at the
> intended default, so it is a valid reference for "healthy". One residual caveat:
> it is still **hand-built**, not a ladder produced by the app's psave path, so it
> proves what a correct ladder looks like — not that the app can produce one.

### 4c. This rig is the acceptance environment for §6 item D

The exclusion model rests on one criterion, and `.150` is the only place it can be
proven: **a ladder saved at full scope, then an explicit exclusion of seg 1, must
survive a sync.** If the sync relights seg 1, the migration default is unsafe to
ship and the predicate widening in §5b would silently relight excluded channels
fleet-wide. Sequence to run: full-scope ladder (done) → apply an explicit seg 1
exclusion → `syncAll` → re-read `/presets.json` and confirm the exclusion held.
**Not yet run.**

## 5. Fleet visibility — a new probe is required

`getInfo` cannot be extended to carry this:

- `/json/info` contains no preset definitions; presets live at `/presets.json`,
  a separate endpoint.
- The bridge implements only `getState` and `getInfo` (`main.cpp:815-818`); the
  default case POSTs verbatim to `/json/state`. There is no arbitrary-GET path.
- `CloudRelayRepository.getPresets()` returns `const []` and `fetchPresetNames()`
  returns `const {}` — off-LAN preset reads are stubbed.

**Two options.**

*App-side census (recommended first).* The on-connect defaults healer already
fetches `/presets.json` on LAN. Add an evaluation plus a small telemetry write.
No firmware; an app release. Reaches anyone who opens the app at home — a wider
population than the ~40% with live bridges (`audit/BRIDGE_TRIAGE.md`).

*Bridge probe.* New `getPresets` case (~20 lines) returning a **digest**, not the
file — `{root_on, bri, seg_on[]}` for slots 1/3/4/5, to keep the command result
doc small. Requires a fleet flash, and structurally cannot exceed bridge reach.
Should bundle with the `/json/cfg` handler the firmware already owes.

Ship the census **read-only**. Do not let it repair — see §6.

## 4d. ITEM D — **CANNOT BE RUN. The exclusion cannot be expressed.**

**Verdict: neither SURVIVES nor RELIT. The test is undefined**, because the app
offers no way to create the state it would test.

### The search

| candidate | what it actually is | base-layer exclusion? |
|---|---|---|
| Per-channel power (P1-43) | `buildChannelPowerPayload` → live `/json/state` only: `{"seg":[{id,on:false}]}`. Never touches presets. | **No — transient** |
| Participating channels | `channel_participation_resolver`, `applyChannelFilter` — which channels join a **shared show** (Game Day, neighborhood sync) | **No — different concept** |
| `DeviceChannel` | `id / name / start / stop / gpioPin` | **No enabled/excluded field** |
| `roofline_config` per-channel docs | pixel maps / geometry | **No** |
| grep `base_layer_channel`, `excluded_channels`, `channel_scope` | only `alert_channel_scope` (commercial sports alerts) | **No** |

### It is by design, not an oversight

`channel_power_payload.dart:7-20` states the policy directly:

> *"OFF the LAST lit channel → master follows: `{"on":false}` (state must not lie;
> **scheduled ON-presets re-assert master via `ib`, so schedule-safe**)"*

Per-channel power is **deliberately transient**, and scheduled presets are
**intended** to override it. The next boundary overwriting a channel toggle is the
contract working, not a defect.

### What this answers in §6

The §6 blocker was *"is there a durable per-channel base-layer scope?"* — the
answer is **no, and none is implied anywhere in the model.** So:

- **The migration hazard is smaller than feared.** There are no persisted
  deliberate exclusions in the field to relight, because the app cannot record
  one. What looked like *"customer excluded this channel"* can only ever have been
  *"this channel happened to be off when the ladder was captured"* — the two cases
  are not merely indistinguishable, **only the second exists.**
- **Predicate widening is therefore safe as remediation**, on this evidence. Every
  all-segments-off ON preset in the field is damage, not intent.
- **Fix and remediation can be ONE change.** The §5b self-repair route is open.

### The claim this supports, and the one it does not

This is a **source-level** finding about what the app can express — stronger than a
bench result, since it does not depend on one rig. It says nothing about whether
the app's psave path can *produce* a correct ladder; that remains unproven and is
still owed (§4b caveat).

**One residual risk, unresolved:** a customer may have excluded a channel by some
route outside the app — the WLED web UI, a dealer's manual setup, a physically
disconnected run. Nothing in the app would know, and predicate widening would
relight it. That risk is real but **out of the app's model**, and it is not
knowable from here — the sweep that would find it cannot run (§5b). Flagging it
rather than pricing it: it argues for shipping the widening with a release note
and a way to turn it off, not for withholding the fix.

---

## 5b. FLEET SWEEP — attempted 2026-08-09, **CANNOT BE RUN**

**Decision going in (Tyler, 2026-08-09):** one-shot sweep rather than extending the
S6 daily probe — the damage comes from an app path about to be fixed, so a
permanent probe for a condition that should not recur is not worth its cost.
Sound reasoning. **It is blocked on reachability, not on cost.**

### The endpoint is a closed set

`executeCommand` (`esp32-bridge/src/main.cpp:815-825`) resolves the target from
three hardcoded pairs:

```cpp
if      (commandType == "getState") { endpoint = "/json/state"; method = "GET";  }
else if (commandType == "getInfo")  { endpoint = "/json/info";  method = "GET";  }
else                                { endpoint = "/json/state"; method = "POST"; ... }
```

`endpoint` is assigned **only string literals**. No field in the command document
reaches it — `type` selects among three fixed pairs. There is no arbitrary-GET
branch. `/presets.json` is unreachable without a firmware change.

Neither reachable endpoint carries the data. `/json/info` has no preset section;
`/json/state` reports `ps` — the *currently loaded* preset id — but never the
stored definitions, which is precisely what the sweep needs.

### Load-and-observe: REFUSED

POSTing `{"ps":1}` and reading back which segments light would answer the
question. It also **changes a customer's lights**, unattended, at an arbitrary
hour, across nine houses. A healthy preset lights the house unexpectedly; a
damaged one darkens it. There is no hour that makes this acceptable, and the
finding is not worth the intrusion. Not built.

### Consequence

**The fleet question stays open. No controller was swept; none is known healthy.**
Reach was never the limit — the ceiling was 9 of 15 controller-owning accounts,
but the achieved count is **0 of 15**, for all accounts, for the same reason.
An unswept controller is not a healthy one.

### What this does to the decision

The one-shot-vs-daily-probe choice was premised on a sweep being possible today.
It is not, so the real options are:

| option | cost | reach |
|---|---|---|
| Bridge firmware `getPresets` case | fleet flash; bundle with the owed `/json/cfg` handler | ≤ bridge fleet (~40%) |
| App-side on-connect census (§5) | app release; healer already reads `/presets.json` on LAN | anyone who opens the app at home |
| Ship the root fix blind | none | remediation only, scope never known |

**A note that changes the shape of this problem:** the root fix and the
remediation may be the same change. Existing damage survives today only because
`isNglOnPresetSatisfied` reports damaged presets as satisfied. **Widen that
predicate to include segment state and every damaged ladder repairs itself on the
next sync — no census required to fix, only to know the scope.**

That is not a free win, and it is the same wall as §6: a predicate that demands
"some segment on" will relight a channel a customer deliberately excluded. But it
means the census is worth far less than it looked. **The blocker is the §6 product
decision, not the missing telemetry.** Buying visibility with a firmware flash
would tell us how many houses are affected without moving us closer to fixing
one.

### Exposure is a SUBSET of scheduled accounts (2026-08-09)

The bench rig's own base ON row fires **`macro:10` ("Warm White")**, not `macro:1`. A boundary
whose action is a pattern/design loads that pattern's preset — written by the path that sets
segments explicitly, and healthy in every case observed. **Only boundaries whose action is a
plain brightness step** (on/dim/low/medium → macro 1/3/4/5) load the NGL ladder and can fire
dark.

So the exposed population is smaller than "every account with a schedule". It is still not
measurable remotely (the sweep cannot run), and it is not zero — but it is bounded by which
action type a customer picked for their ON boundary, which is knowable from Firestore schedule
documents without touching a controller. **That census has not been run.**

### Shadow-run gate

Unchanged and unanswerable by sweeping: a customer whose base ON preset fires
dark has a house that never lights at sunset, with no signal to them or to us.
**Gate the shadow run on the §6 decision and the root fix, not on a census that
cannot be run.**

---

## 5c. SCHEDULE ACTION CENSUS — **EXPOSURE IS ZERO**. Read-only, 2026-08-09.

§5b concluded fleet exposure was unknowable because preset state is unreachable.
That answered the wrong question: preset state determines whether a ladder is
*damaged*, but what determines whether damage can ever *fire* is in Firestore.

**Result: 0 of 24 accounts exposed.**

### The discriminator is `wledPayload`, NOT the action label

The premise going in — "brightness-step boundaries load the ladder, pattern
boundaries don't" — is not how the code branches. `syncAll` splits on whether the
schedule carries a design payload:

| schedule | path | preset |
|---|---|---|
| has `wledPayload` | psaved to a 10–25 slot with the design + `on:true` + `ib:true` | pattern slot — **never touches the ladder** |
| no `wledPayload` | `clearPresetId`, macro resolved by `_presetForAction` | **1/2/3/4/5 — the only path to the ladder** |

The label only matters for payload-less schedules. Verified empirically: Tyler's
`"Warm White"` 8:23 PM schedule has a payload, and the rig's 20:23 row fires
`macro:10` — a pattern slot, exactly as the code says.

### Census (both stores, all 24 user documents)

```
user documents            : 24
accounts with schedules   :  4
accounts with controllers : 15
payload-less schedules    :  0   ← the only path to the ladder
EXPOSED ACCOUNTS          :  0
```

Every schedule in the fleet, named:

| account | store | action label | payload | macro |
|---|---|---|---|---|
| Steve Stegall | array + subcol | `Deep Blue` | yes | pattern slot |
| Trend Setter (Tyler) | array + subcol | `Warm White` | yes | pattern slot (10 on `.150`) |
| Ellie Cochran | array + subcol | `Pattern: 1 On 4 Off - Solid` | yes | pattern slot |
| Chris Cipollone | array + subcol | `Pattern: 3 On 2 Off - Solid` | yes | pattern slot |

The other 20 accounts have no schedules at all; 11 of them own a controller.
**Array and subcollection agree for every account — 0 divergences**, despite the
two stores having diverged historically.

### Autopilot does NOT increase exposure

`AutopilotSuggestion.wledPayload` is a **required** constructor field, and
autopilot schedules are created as `id: 'autopilot-${item.id}'` carrying it
(Chris Cipollone's row above is one). So every autopilot boundary is
payload-bearing and takes the pattern-slot path. **Exposure does not track
autopilot adoption** — autopilot is structurally on the safe side of the branch.

### Ceiling — state this plainly, the number is easy to over-read

This bounds who **could** be affected, not who **is**. Zero here means something
stronger than usual, though: it is not "no damaged ladders found" (we still
cannot read a customer's presets), it is **"no scheduled boundary in the fleet
currently routes to the ladder at all."** A ladder could be damaged on any of the
15 controller-owning accounts and it would still never fire, because nothing
points at macro 1/3/4/5.

Two ways that becomes non-zero, neither observable in advance:
1. **A customer creates a payload-less schedule** — a plain Turn On / Brightness
   action with no design attached. One tap.
2. **A schedule loses its payload** — the guard at `schedule_sync.dart:1168`
   exists precisely because `wledPayload:null` legacy entries have been seen.

### Latent hazards in `_presetForAction`, unreachable today

Currently dead code for the fleet (every schedule has a payload) but wrong, and
the first payload-less schedule reaches them:

- **`a.contains('off')` is a substring test and runs FIRST.** `"Pattern: 1 On 4
  Off - Solid"` → contains `off` → **macro 2, the OFF preset**. That label exists
  in the fleet today on two accounts; only the payload saves them. A payload-less
  schedule named that way would turn the lights OFF at its ON boundary.
- **`a.contains('on')` runs before the pattern test.** Any label with `on`
  anywhere — `Neon`, `Bronze`, `Monday` — resolves to macro 1 before the pattern
  branch is reached.
- **The fallthrough default is `return 1`.** Unrecognised labels — `"Deep Blue"`,
  `"Warm White"` — land on the ladder. Both exist in the fleet today.

Logged, not fixed; out of scope for this pass.

### What this changes

The root fix (§6b) is **still worth shipping** — it repairs damage and stops new
damage — but it is **not urgent on current fleet evidence**, and the kill switch
matters less than it looked. The realistic risk is prospective: the first
payload-less schedule anyone creates.

---

## 5d. ROUTING FIX — `presetForAction`. **IMPLEMENTED 2026-08-09.** Not deployed.

Separate change from §6b, deliberately: **§6b repairs preset CONTENT, this fixes
ROUTING.** They touch different files and are revertible independently.

### What a payload-less schedule now does when no action maps

**It refuses to arm, and says so.** Previously an unrecognised label fell through
to `return 1` and armed macro 1 — "turn the house on at bri 200". Both `"Deep
Blue"` and `"Warm White"` exist in the fleet and both landed there.

Refusal is the same posture the sync already takes for a pattern whose preset
never saved (`schedule_sync.dart:1168`, "never silently arm an empty macro"). The
principle is now consistent: **an ON-timer we cannot resolve must not fire
something we did not choose.** A schedule that does nothing and warns is
recoverable; a schedule that lights the house at 3am because a label did not
parse is not.

### The change

`presetForAction` returns `int?` — `null` means "not a recognised action".

| label | before | after |
|---|---|---|
| `Turn On` / `Turn Off` | 1 / 2 | 1 / 2 (unchanged) |
| `Brightness: 40%` | 4 | 4 (unchanged) |
| `Pattern: 1 On 4 Off - Solid` | **2 — the OFF preset** | `null` — refused |
| `Neon Dream`, `Bronze Autumn` | **1** | `null` — refused |
| `Deep Blue`, `Warm White` | **1** | `null` — refused |
| `Turn On The Lights` | **1** | `null` — refused |
| `Brightness` (no %) | **3 — guessed Dim** | `null` — refused |
| `Brightness: 150%` | 1 | `null` — refused |

Substring tests replaced with `==` for fixed actions and an anchored
`^brightness\s*:?\s*(\d{1,3})\s*%?$` for the brightness form. Both call sites —
`cfg_payload_builder.dart:166` (clock) and `schedule_sync.dart:659` (solar) —
`continue` on `null` and emit a REFUSED line.

### The model problem, named rather than patched around

`ScheduleItem` persists `actionLabel`, **a display string**, and has no
action-type field. This function is parsing UI copy to recover intent that was
never stored. Anchored matching makes the parsing honest and its failures loud;
it cannot make it correct. **Renaming a button, translating the app, or an
AI-authored label all silently break the mapping**, and nothing outside this
function would know.

The real fix is an `actionType` enum persisted on the schedule at authoring time,
with this function reduced to a migration shim for pre-existing rows. Not done
here — it changes the model, every write path, and needs a backfill. Recorded as
the correct next step rather than attempted as a side effect of a bug fix.

### Verification

- **Unit: 10/10** (`test/features/schedule/preset_for_action_test.dart`) — one
  group per bug, using the ACTUAL fleet labels (`Pattern: 1 On 4 Off - Solid`,
  `Deep Blue`, `Warm White`), plus a decoy sweep asserting no label can reach the
  ON ladder except an explicit on/brightness action.
- **Full suite: 2010 passed, 3 skipped, 1 failure** — the same pre-existing
  `cloud_ai_processor_normalize_test.dart` failure (`Expected 'Sunset'`), already
  proven unrelated by stashing to HEAD. No new failures.

### Behaviour change worth flagging before deploy

This is a **refusal added to a live path**. Fleet exposure is zero today (§5c:
every schedule carries a payload, so nothing reaches this function), so the
expected blast radius is nil. But if any account later holds a payload-less
schedule with a non-canonical label, it will now arm **nothing** where it
previously armed macro 1. That is the intended behaviour and strictly safer than
lighting the house on a guess — but it is a change from "does something wrong" to
"does nothing, loudly", and support should know which to expect.

---

## 6. Root fix — scoped, BLOCKED

**Where:** the four inline `psaveIfChanged` calls in `syncAll` and
`onPresetHealState`. Copy the shape of `buildNglOffPresetState`.

**Trap that would make the fix inert:** adding `seg` to the psave payload without
also adding it to `isNglOnPresetSatisfied` means every already-damaged preset
still reports satisfied and is skipped. The fix would land and change nothing on
the installed fleet — **exactly what happened to the `ib:true` work before
`9158c00`**, documented in the comment above that very predicate.

**The blocker — what segment state is correct?**

The existing participation concept (`channel_participation_resolver`,
`applyChannelFilter`) answers *which channels join a shared show* (Game Day,
neighborhood sync). It does **not** answer *which channels the base layer should
light*. Conflating them is a category error: a customer who opts out of
neighborhood sync still wants their own schedule to light their house.

There is **no durable store of per-channel base-layer scope**. The bench
exclusion was a live-state toggle. That rules out both easy answers:

| candidate | outcome |
|---|---|
| assert all segments on | relights a deliberately excluded channel |
| preserve current live seg state | *is* the bug — ambient capture renamed |
| new persisted base-layer channel scope | correct; new concept + UI + storage + migration |

**The migration is the sharp edge.** For presets already damaged in the field,
nothing distinguishes *"customer deliberately excluded this channel"* from
*"this channel was off when the preset was captured."* A blind repair would
relight channels people turned off on purpose — someone else's bedroom. That is
the same fact that makes the §4 repair correct here and portable nowhere.

**Open question for product, not engineering:** does the base layer get its own
persisted channel scope, and how is an existing house migrated into it without
either relighting an intentional exclusion or leaving a dark house dark?

---

## 6b. ROOT FIX — **IMPLEMENTED 2026-08-09.** Not deployed.

§4d unblocked this: the app cannot record a deliberate exclusion, so every
all-segments-off ON preset is damage. **Fix and fleet repair are ONE change.**

### What changed

| file | change |
|---|---|
| `schedule_sync.dart` | `buildNglOnPresetState(bri, liveState)` — the ON ladder's single definition, mirroring `buildNglOffPresetState`. All four `psaveIfChanged` call sites now pass it instead of a bare `{on, bri, ib}` map. |
| `schedule_sync.dart` | `isNglOnPresetSatisfied(def, name, {repairSegments = true})` — now also requires every stored segment `on:true`. |
| `schedule_sync.dart` | `_fullStripOnSegments` + `_presetAllSegmentsOn`, exact mirrors of the OFF helpers. No bounds written (P1-42). |
| `schedule_sync.dart` | Release note appended to `presetErrors` when a repair actually happens. |
| `controller_defaults_healer.dart` | Fetches live state and passes it to `onPresetHealState` — **the healer had the identical defect** and would have re-damaged what the sync repaired. |
| `base_ladder_repair_feature_flag.dart` | NEW kill switch at `config/base_ladder_repair`. |
| `firestore.rules` | `match /config/base_ladder_repair` — public read. **Needs deploying.** |

### Two halves that must ship together

Adding `seg` to the payload without widening the predicate would have been
**inert on the entire installed fleet** — every damaged preset still reports
satisfied and is skipped. That is exactly what happened to the `ib:true` work
before `9158c00`. Same file, same function, same mistake available twice; a
regression test now pins it.

### The kill switch fails OPEN

Defaults **true**, opposite of `solar_scheduling`. This is a repair for houses
that never light, not a capability being eased in, so a degraded flag read must
not silently withhold it — the failure mode that left solar off fleet-wide. Only
an explicit `enabled:false` disables it. Consequence: a missing firestore rule
costs the ability to PULL the switch, not the fix.

### Preset 2 is explicitly excluded, and the code says why

Its all-segments-off shape is correct — but on a damaged rig preset 2 reads
*identically* while being right only **by accident** (it captured a dark house).
The two are indistinguishable by inspection, so preset 2 keeps its own predicate.
Applying the ON bar to it would relight the house at every OFF boundary. Comment
and a test both pin this so nobody "fixes" it later.

### Verification

- **Unit: 18/18** (`test/features/schedule/base_ladder_repair_test.dart`) —
  damaged repairs, correct is left alone, partial damage caught, legacy
  segments-absent caught, `ib` master bar not regressed, kill switch restores
  pre-fix behaviour exactly, idempotency, preset 2 excluded, healer shares one
  definition.
- **Full suite: 1998 passed, 3 skipped, 1 failure** — `cloud_ai_processor_normalize_test.dart`
  (`Expected 'Sunset', Actual ''`). **Pre-existing**, proven by stashing both
  modified source files back to HEAD and re-running: still fails.
- **HARDWARE, `.150`** (`test/hardware/base_ladder_repair_live_test.dart`,
  `--tags hardware`) — **PASSES.** Deliberately re-damages slot 3 exactly as the
  defect did (bare `{on,bri,ib}` psave from a dark strip), confirms the REAL
  predicate reports it unsatisfied *and* that the old bar called it healthy, then
  repairs it with the REAL shipping builder and re-verifies the stored def.

### §4b caveat — CLOSED

The hardware test repairs using `ScheduleSyncService`'s own builder and predicate,
so the app's psave path is now proven to **PRODUCE** a correct ladder, not merely
preserve a hand-built one. Remaining gap: this exercises the builder + predicate
against real hardware, **not a full `syncAll`** (that needs the app on the tablet
and an ADB port). The decision logic in `psaveIfChanged` is covered by unit tests
only.

### Two incidents during verification, both recorded

1. **Dart `HttpClient` POSTs failed silently against WLED.** Without an explicit
   `contentLength` it uses chunked transfer-encoding, which WLED's server
   rejects — GETs succeed on the same client, so it reads as "the controller
   ignored my write". First attempt of the hardware test failed this way and the
   assertion was too weak to say so; preconditions are now asserted.
2. **`pdel` corrupted `presets.json`.** Deleting the two scratch slots (250/251)
   left a stray `s` byte inside the padding run before the closing brace, so the
   whole file failed to parse — which would blind BOTH `fetchPresets()` callers
   (sync falls back to rewriting every preset; the healer bails entirely). A
   `psave` did **not** fix it (WLED patches in place; byte length unchanged at
   13,246). Repaired by rebuilding the file with the stray byte blanked —
   byte-identical length, all 15 presets intact — and uploading via `/edit`.
   Verified parsing, ladder healthy, probe slots gone.
   **Worth knowing independently of this work: `pdel` on this firmware can leave
   presets.json unparseable, and the app has no detection for it.**

## 7. Relationship to S4

`audit/S4_RESTORE.md` §D asserts the base layer reclaims the house. The bench run
on 2026-08-09 **demonstrated the OFF half** (`ps:2`, design replaced, no end
signal) and **disproved the ON half** on this rig — the floor could not light the
house at all until §4's repair.

For unattended operation the ON direction is the worse failure: the design ends
correctly and the house is then dark indefinitely, with no signal to the customer
and none to us.

**The shadow run is gated on this, not on §D reclaim.**
