# HEALER PUBLISH — participation and base boundaries, one mechanism

**Date:** 2026-08-11 · **Branch:** `main` (working tree, on top of `ec9db58`)
**Status: IMPLEMENTED. DEVICE-SIDE BENCH-VERIFIED 2026-08-11 (steps 2/3/4 PASS, one real defect found and fixed). APP-SIDE OWED — §7.2b. BUILT AS `2.5.10+69`. NOT DEPLOYED, NOT UPLOADED.**

Closes the publish gap scoped in [audit/S3B_CHANNELS.md](S3B_CHANNELS.md) and the
input half of the base-row collision scoped in [audit/S5_GAMEDAY.md](S5_GAMEDAY.md).

---

## 0. WHY THE TWO SHIPPED TOGETHER

They are the same shape, and it is worth stating the shape precisely because it is
what justifies one mechanism rather than two:

> A value that only a client **on the customer's LAN** can read, feeding a server
> that **structurally cannot** read it, written to a document the server
> **already reads**.

| | `participating_channels` | `base_boundaries` |
|---|---|---|
| device source | `/json/cfg` → `hw.led.ins[]` (bus list) | `/json/cfg` → `timers.ins[]` |
| reachable off-LAN? | **No** — the bridge maps only `/json/state` and `/json/info` | **No** — same |
| server-side backfill? | **Impossible** | **Impossible** |
| destination | `users/{uid}/controllers/{controllerId}` | same document |
| consumer | the Game Day planner / dispatcher | the planner, once arbitration exists |

Two families, one LAN read, one document. Publishing them through one helper is
what gives them the **same timestamp discipline** and the **same publish
history**; a second hand-rolled writer would drift on exactly the fields an
auditor needs, and would double the per-connect write cost for two values pulled
out of a single cfg fetch.

---

## 1. WHERE IT FIRES — the defaults healer, on connect

`ControllerDefaultsHealer.run()`, immediately after `fetchClockInfo()` succeeds
and **before** any heal.

The healer was the only candidate that is simultaneously (a) LAN-only, (b)
already holding a `/json/cfg` read, and (c) fired on every on-LAN session for
every customer. The rejected alternatives, restated:

| candidate | why not |
|---|---|
| ordinary app open | needs its own `/json/cfg` read — a LAN round-trip per launch, duplicating one the healer already makes |
| successful schedule sync | only fires when a schedule is saved; most customers set schedules once |
| installer wizard | once per install, ever — fixes future installs and leaves every existing account exactly where it is |

**Ordering is load-bearing, three ways.** It runs *after* the relay bail-out, so
it can only ever fire where the inputs exist. It runs *after* the cfg read, which
is its only source. It runs *before* the heals, so a heal that fails — or the
reboot at step (g) — cannot skip it. Tests cover all three.

### The one contract widening, named

This file's contract was *"make the controller correct."* It now also does one
thing that is not a heal: a **Firestore** write **about** the controller. That is
a real widening and it is argued for rather than smuggled: the alternative is a
second on-connect hook that repeats the cfg read. The report keeps them separate
— `factsPublishDispatched` is deliberately **not** part of `anyHealed`, so a
healthy controller that published still logs as healthy.

---

## 2. THE PARAMETER DECISION (Tyler, 2026-08-11)

The resolved channel ids and the bus list are **passed into the healer as
parameters**. Not a `ref`, not internal derivation.

The healer is deliberately dependency-light and runs for every controller on
every connect. `deviceChannelsProvider` already owns the bus→`DeviceChannel`
parsing; deriving it inside the healer would create a second implementation of
that parsing that can drift. The caller — `controllerDefaultsHealerProvider` —
already holds the provider, and it also holds the roofline segments the resolver
needs, so it resolves and passes both:

```dart
final deviceChannelIds = ref.read(deviceChannelsProvider).map((c) => c.id).toList();
final participating = resolveParticipatingChannels(
  explicit: null, segments: segments, allDeviceChannelIds: deviceChannelIds);
```

`explicit: null` matches the other two publish sites; no channel picker writes
`participatingChannelIndices` today. When one ships, **all three sites** need the
explicit set threaded together — noted at each.

---

## 3. THE CORRECTED COST CLAIM

The S3B scope originally said a compare-then-write in the healer means *"a
controller whose `participating_channels` already matches receives ZERO writes."*

**That was wrong, and this implementation does not claim it.**

The dedup memo is **process-scoped and never reads Firestore**. So:

- **once per app session, per controller — healthy or not.**
- Within a session, a second connect to the same controller writes **nothing**.
- On relaunch, the memo is cold and the first connect **republishes**.

The relaunch republish is **correct by design, not a defect**. It is the free
self-heal for a lost write: no read-back, no reconciliation job. A test pins both
halves so nobody later "fixes" it.

Making it genuinely zero-write would require reading the Firestore value first —
the read-back the design deliberately avoids, and which would cost a read per
connect to save a write per session.

---

## 4. WHAT LANDS ON THE DOCUMENT

### Participation (unchanged fields, one new refusal)

`participating_channels`, `_device_ids`, `_at`, `_source` — as shipped in S3b.

**New:** a resolution computed against an **empty bus list is no longer
published.** `deviceHardwareConfigProvider` is a `FutureProvider` fed by the same
`/json/cfg` and is routinely still in flight early in a session; resolving
against it yields `[]`, and `[]` is a **usable** verdict server-side meaning
"light nothing". Publishing it would silently darken a house that expected a
show, while recording `_device_ids: []` as if we had checked.

This was latent before and is now load-bearing, because the healer publishes far
earlier in a session than either previous call site did. `participationShapeIsKnown`
carries the guard and the picker-era TODO.

### Base boundaries (new)

| field | meaning |
|---|---|
| `base_boundaries` | array of armed rows — see below |
| `base_boundaries_slots_read` | how many `timers.ins` slots were read (10 normally). Provenance; the analogue of `_device_ids` |
| `base_boundaries_dow_bit0` | the literal string `"monday"` |
| `base_boundaries_indices_are_slots` | whether a row `index` IS its device slot. False unless the readback was full-length — WLED compacts it |
| `base_boundaries_at` / `_source` | timestamp discipline, shared |

Per row: `index`, `kind` (`clock`/`sunrise`/`sunset`/`solar`), `macro`, `role`,
`dow`, and then **either** `hour` + `minute` **or** `offset_minutes` — never both.

Four deliberate choices:

1. **`kind` comes from the row's CONTENT (`hour == 255`), not its position** —
   and `index` is explicitly not a slot number. This is the **corrected** rule;
   the first cut keyed off array index 8/9 and the bench disproved it (§7.2).
   WLED's `checkTimers()` does special-case slots 8/9 positionally, but the
   `/json/cfg` **readback is compacted**, so the array we read is not the array
   we sent.
2. **Direction is refused rather than guessed.** Two solar rows pair ordinally;
   a lone one publishes as `kind: "solar"`. A planner told "sunrise" about a
   sunset row plans in the wrong half of the day.
3. **A solar row emits no `hour` and no `minute`.** On a solar row, `hour` is the
   marker 255 and `min` is a signed offset. Two different quantities sharing one
   device field is exactly how this project already produced a wrong answer once
   — the UTC-vs-local mixup that put the base row on the wrong side of the design
   fire. A planner reading `minute` off a solar row now gets **nothing** instead
   of a plausible wrong number. Negative offsets are folded back from the
   unsigned byte (`226 → −30`) via the existing `normalizeSolarOffset`.
4. **`base_boundaries_dow_bit0` is written on every publish.** WLED is
   Monday = bit 0, and Lumina previously shipped Sunday = bit 0 for months —
   invisible because Daily (127) is convention-agnostic. The planner does not
   exist yet and will be written by someone who cannot see the device. Thirty
   bytes is cheap insurance.

### Publish history — Part 3

| field | answers |
|---|---|
| `{family}_publish_count` | **how many writes have ever happened.** Last-wins cannot distinguish "deduped" from "republished identically"; the counter can. Divide the delta by app sessions in the window: dedup is holding at ≈1 per session per controller. Anything scaling with *resolves per session* means a memo is not being consulted |
| `{family}_previous` | the value the most recent write superseded. **Present** ⇒ an in-session change. **Absent** ⇒ first write of a session, no in-process predecessor |

`_previous` is **deleted**, not left stale, when unknown. A `_previous` from two
sessions ago sitting beside a fresh `_at` would read as a change that never
happened. The absence is the honest reading of a process-scoped memo, and it is
precisely why the counter exists alongside it.

Cheap: two fields per family, no extra read, an increment and a scalar.

---

## 5. NULL vs EMPTY — the discipline both families share

| state | participation | base boundaries |
|---|---|---|
| **unknown** → publish nothing | resolver returned null, or bus list empty | `timers.ins` unreadable (relay, failed cfg read) |
| **known and empty** → publish `[]` | customer excluded every channel | controller has no armed rows |

Collapsing these would let an unreadable cfg tell the planner a house has no
boundaries — the state in which it would plan a fire straight through one. WLED
always serializes a `timers.ins` array, so a null there means we could not see
the table, never that it is empty.

---

## 6. WHAT THIS DOES **NOT** DO

- **No arbitration.** Deciding what a planner does when a base row lands inside a
  fire window is the compositor's job. This publishes inputs. Option (a) from the
  S5 scope — planner disables the conflicting row — remains dead on the same LAN
  constraint, and worse than the problem: a disable that lands without its
  restore silently destroys the customer's everyday schedule.
- **No server reader.** Nothing in `functions/src` reads `base_boundaries` yet.
- **No `firestore.rules` change.** The controllers subcollection is already
  owner-writable under the user's own uid via `set(merge: true)`, and Admin
  bypasses rules. Verified against the existing `/users/{userId}/controllers/{id}`
  update rule.
- **No index change.** Read by document id; nothing queries these fields.

### The limit that does not close

A bridge-paired customer whose phone is rarely on the home network may still
never publish, because every path needs the LAN and the bridge supplies no
`/json/cfg`. For them unattended Game Day is **unavailable, not degraded** — the
planner refuses rather than guessing. That is a statement to make to a customer,
not a defect to fix here; closing it needs the bridge `applyConfig`/`getCfg`
branch already owed.

---

## 7. VERIFICATION

### 7.1 Automated — all green

| suite | result |
|---|---|
| `flutter test` (full) | **2137 passed, 3 skipped, 1 failed** |
| `functions` `npx jest test/unit` | **8 suites, 237 tests, all passed** |
| `flutter analyze lib/ test/` | **no errors; nothing new on any touched file** |

The single Dart failure is `test/hardware/base_ladder_repair_live_test.dart`
("the app repairs a deliberately damaged ladder slot", expected ≥2, actual 1).
**Confirmed pre-existing** — stashed this branch's changes and reproduced the
identical failure at baseline.

New tests, 68 across three files:

- `base_boundary_denormalizer_test.dart` (42) — null-vs-empty; the bench rig's
  exact table; solar by slot position; the negative-offset fold and that clock
  minutes are *not* folded; asymmetric `toJson` keys; armed-row filtering matching
  the clobber guard; dedup in every direction; `wledPresetRole` per range and its
  refusal to guess on a gap; the **drift guard** binding the pure range table to
  `ScheduleSyncService.kOnPresetSpecs` / `kNglOffPresetId` / the solar slots;
  `timerInstancesFromCfg`; `ControllerClockInfo.timersKnown`.
- `controller_facts_writer_test.dart` (25, against `fake_cloud_firestore`) — one
  write carrying both families; a family abstaining without blocking the other;
  zero writes when both abstain; the counter incrementing per family and **not**
  incrementing on a dedup; `_previous` carried, absent on a session's first
  write, and cleared rather than left stale; the memo committing only on a
  successful write; the empty-bus-list refusal; a throwing commit neither failing
  the write nor skipping a sibling.
- `controller_defaults_healer_publish_test.dart` (19) — a **healthy** controller
  publishing on connect with zero heals; no extra device read; the rig table
  arriving intact through the healer; publish surviving a failed heal and
  surviving a reboot; relay/unreachable/no-controller-id gating; a publisher that throws not aborting the heals;
  and the session semantics pinned in both directions.

### 7.2 Device-side — RUN 2026-08-11 against `.150`. Steps 2/3/4 PASS.

Everything reachable over HTTP was verified directly. **Read-only throughout —
zero writes to the controller.** The three remaining steps need the app itself
and are in §7.2b.

**Segment state, recorded first** (`/json/state`): master `on:false`, `bri:200`,
`ps:-1`, **ONE segment** id 0 spanning 0-128, `frz:false`, `fx:28`, `pal:5`.

> **SEGMENTS ARE NOT BUSES, and participation follows BUSES.** The rig showing
> one segment does **not** mean participation resolves to `[0]`.
> `/json/cfg hw.led.ins` still holds **two buses** — bus 0 (0-128, pin 2) and
> bus 1 (128-290, pin 14), `hw.led.total: 290` — and `deviceChannelsProvider`
> derives channels from buses, never from segments. So a resolve on this rig
> publishes **`[0, 1]`**, and `[0]` would be the regression.
>
> The collapse is live-state only, and it is the documented reboot behaviour
> (`project_reboot_segment_collapse`). All five ladder presets still carry
> **two** segments, so the next preset load restores the split.

| # | step | result |
|---|---|---|
| 2 | base boundaries match `timers.ins` | **PASS** — see below |
| 3 | `gc.col` still 2.8 | **PASS** — `{"bri":1,"col":2.8,"val":2.8}` before and after; no cfg write issued |
| 4 | ladder intact | **PASS** — 1 `NGL On` on:true bri:200 · 2 `NGL Off` on:false · 3 `NGL Dim` bri:51 · 4 `NGL Low` bri:102 · 5 `NGL Medium` bri:153, each carrying 2 segments. No `psave` this run |

**Step 2 in full.** The device timer table:

```
slot 0: en=1 hour=20  min=23 macro=10 dow=127
slot 1: en=1 hour=6   min=22 macro=2  dow=127
slot 2: en=1 hour=20  min=40 macro=40 dow=4
slot 3: en=1 hour=255 min=0  macro=2  dow=127
```

The **real** `timerInstancesFromCfg` -> `extractBaseBoundaries` ->
`buildBaseBoundariesDoc` chain was run over the **captured device bytes** and
produced:

```json
{"base_boundaries": [
  {"index":0,"kind":"clock","macro":10,"role":"schedule",  "dow":127,"hour":20,"minute":23},
  {"index":1,"kind":"clock","macro":2, "role":"system_off","dow":127,"hour":6, "minute":22},
  {"index":2,"kind":"clock","macro":40,"role":"lease",     "dow":4,  "hour":20,"minute":40},
  {"index":3,"kind":"solar","macro":2, "role":"system_off","dow":127,"offset_minutes":0}],
 "base_boundaries_slots_read": 4,
 "base_boundaries_dow_bit0": "monday",
 "base_boundaries_indices_are_slots": false}
```

Every row matches the device: base ON 20:23 macro 10, base OFF 06:22 macro 2,
the Wednesday (`dow:4`) lease macro 40, and the solar sentinel.

#### THE BENCH FOUND A REAL DEFECT — fixed before the build

**`timers.ins` came back with FOUR entries, and the slot-8 sentinel was at index
3.** WLED **compacts** the `/json/cfg` readback: it echoes armed rows and drops
the disabled padding stubs, so array index != device slot.

`timer_landing.dart:139-149` already documented exactly this, hardware-confirmed
— and the first cut of `extractBaseBoundaries` classified solar **by array
index** anyway. On this rig it would have published the sentinel as
`kind:"clock", hour:255` — a boundary at an impossible time, i.e. precisely the
plausible-wrong-number failure the split `hour`/`offset_minutes` keys were
introduced to prevent. The unit tests did not catch it because their fixture was
the **sent** 10-entry shape; the publisher only ever sees the **readback** shape.

Three corrections:

1. **Solar is identified by `hour == 255`**, wherever compaction puts it.
2. **Direction is refused when undecidable.** Two 255-rows pair ordinally
   (first sunrise, second sunset — order is preserved on the wire). A **lone**
   255-row is genuinely ambiguous: "on at sunset / off at a clock time" produces
   an identical shape, and the sync comparator only resolves it by comparing
   against what it had just sent, which a cold connect-time read has no access
   to. Such a row publishes as `kind:"solar"`. The rig's sentinel is a lone row,
   which is why it reads `solar` above and not `sunrise`.
3. **`slot` renamed to `index`**, plus `base_boundaries_indices_are_slots`
   (false here, since `slots_read` is 4, not 10). The old field name asserted
   something compaction makes untrue.

Every fixture table in the tests is now the readback shape.

#### Incidental finding — not caused by this change

**The Wednesday lease timer macro 40 points at a preset that does not exist.**
`/presets.json` holds 10, 26-30, 33, 36, 38, 41, 160 — but **not 40**. That timer
fires into nothing every Wednesday at 20:40. Pre-existing rig state, outside this
change scope, and worth noting that publishing base boundaries is what made it
visible at all.

### 7.2b App-side — OWED. Phone on home Wi-Fi, `2.5.10+69`.

The bench tablet is unavailable, so the trigger is **opening the app on a phone
joined to the home network** rather than an ADB command. The steps are otherwise
unchanged: the healer fires on controller connect, so a plain app open on-LAN is
the whole trigger. **Do not run a Neighborhood Sync or a Game Day apply at any
point** — that would publish through the OLD path and invalidate step 1.

Target document throughout:
`users/wrQRUUKyXyc0deyuu0ORS6wsovO2/controllers/192_168_1_150`.

Read it with a **client credential, not the Admin SDK** — an admin readback
proves existence, never app-readability, and that distinction has already cost a
day on the solar flag.

1. **Participation publishes with no neighborhood sync** — *the whole point of
   the change.* Install `+69`, join home Wi-Fi, open the app, let it connect to
   `.150`. Do nothing else. Expect:
   - `participating_channels: [0, 1]` — **two buses; see the warning above**
   - `participating_channels_device_ids: [0, 1]`
   - `participating_channels_source: "healer"`
   - `participating_channels_publish_count` incremented by exactly 1
   - `participating_channels_previous` **absent** (first write of the session)
2. **Base boundaries land** alongside, in the **same** write — compare against
   the JSON block in §7.2, which is what the code produces from these exact
   device bytes. `base_boundaries_at` and `participating_channels_at` should
   carry the same server timestamp.
3. **`gc.col` still 2.8** after the connect —
   `curl http://192.168.1.150/json/cfg`. Four cfg writes today each preserved
   gamma; this run performs none, so a change here means the healer wrote
   something it should not have.
4. **Ladder intact** — `curl http://192.168.1.150/presets.json`, presets 1/3/4/5
   unchanged from the values in §7.2.
5. **Second connect, same session, does NOT republish.** Without leaving the
   app, force a reconnect (Wi-Fi off/on, or switch controller away and back).
   **Neither** `_publish_count` may move.
6. **Relaunch DOES republish.** Force-stop the app, reopen, reconnect. Both
   `_publish_count` values increment by exactly 1 **with the stored values
   unchanged**, and `_previous` stays absent. This is the designed self-heal —
   §3 states it in advance so it is not misread as a dedup failure.

Steps 5 and 6 are the pair that pins the session semantics on hardware.

**Which phone.** Any device running `+69` on the home network works; the healer
does not care that it is not the tablet. If that phone has never opened this
account on-LAN before, step 1 `_publish_count` starts at 1 rather than
incrementing — read the absolute value, not the delta, on the first run.

### 7.3 Still unresolved from the reconciler work

Reconciler **test 3 passed** (bus change `[0,1] → [0]` produced a consistent
updated pair; recovery to `[0,1]` confirmed). Whether it dedups on a
**design-only** change is still open — a roofline/segment edit that does not
alter the bus list. The mechanism says it should: the resolver's output would be
unchanged, so the memo suppresses it. Now cheaply observable, because
`participating_channels_publish_count` will not move if it holds.

---

## 8. CHANGED FILES

| file | change |
|---|---|
| `lib/features/wled/controller_facts_writer.dart` | **NEW** — field naming, `stampFactFamily`, `PreparedFacts`, the one merge-set writer |
| `lib/features/wled/base_boundary_denormalizer.dart` | **NEW** — row model, cfg extraction, dedup, doc shape |
| `lib/features/wled/controller_facts_publisher.dart` | **NEW** — the injected seam; assembles both families into one write |
| `lib/features/wled/participation_denormalizer.dart` | refactored onto the shared writer; adds `participationShapeIsKnown`; public API unchanged |
| `lib/features/wled/controller_defaults_healer.dart` | publish params + dispatch step + report fields + provider wiring |
| `lib/features/wled/clock_health.dart` | `ControllerClockInfo.timerRows` / `timersKnown` off the existing cfg read |
| `lib/features/schedule/timer_landing.dart` | `carriesAnyEnabledEntry` and `timerInstancesFromCfg` promoted from two private copies |
| `lib/features/schedule/schedule_sync.dart` | uses the shared predicate + shared preset-range constants |
| `lib/features/wled/wled_service.dart` | `fetchTimerInstances` uses the shared extractor |
| `lib/features/wled/wled_preset_ranges.dart` | schedule/lease/system range constants + `wledPresetRole` |
| `lib/features/schedule/calendar_entry_lease_manager.dart` | lease range constants moved here-from; re-exported so importers are unaffected |

### Three deduplications taken along the way

Each removed a *second* implementation rather than adding one — the same concern
that drove the parameter decision in §2:

- `_carriesAnyEnabledEntry` was private to `schedule_sync`. The clobber guard and
  the boundary publisher ask the identical question of the identical rows ("is
  there anything here that does something?"), so they now share one predicate.
- `timers.ins` extraction existed twice inside `wled_service`. Now once, shared
  with `ControllerClockInfo`, so a timer row means the same thing to the
  publisher and to the sync verifier.
- The preset-id ranges were documented in `wled_preset_ranges.dart` in prose but
  defined as constants in two other files. `wledPresetRole` needed them, and a
  third copy was the wrong answer; a drift-guard test binds the pure table to the
  real allocators.

---

## 9. FINDINGS

| # | finding | severity |
|---|---|---|
| 1 | **The publish is once per app session per controller, not zero-when-healthy.** The S3B scope's zero-write claim was wrong; the memo never reads Firestore. Corrected in code comments and §3 | Corrected claim |
| 2 | **A resolution against an empty bus list was publishable and now is not.** `[]` is a *usable* server-side verdict meaning "light nothing", so publishing it during the pre-load window would darken a house. Latent before; load-bearing now that the healer publishes early in a session | **Behaviour change — flagged** |
| 3 | **Solar rows carry a different key set on purpose.** `hour` 255 is a marker and `min` is a signed offset; emitting them under clock names invites the exact UTC-vs-local class of error already paid for once | Design |
| 4 | **`base_boundaries_dow_bit0` is written per document.** Redundant to anyone who reads the code, insurance against a future server author who cannot. Lumina already shipped the wrong convention once | Design |
| 5 | **Publish history is two fields, not an audit log.** The counter answers "did dedup hold"; `_previous` answers "what did the last write change", with an honest gap on a session's first write | Design |
| 6 | **Nothing reads `base_boundaries` yet.** Publishing inputs is the whole scope; the arbitration is deliberately absent and still owed | By design |
| 7 | **Bench verification is owed** (§7.2), specifically steps 5/6, which are the only on-hardware evidence of the session semantics | **Owed** |
| 8 | Whether the reconciler dedups on a **design-only** change is still open — but now cheaply observable via `participating_channels_publish_count` | Open |
