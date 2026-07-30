# PRESET MASTER-ON ASSERTION — DIAGNOSIS

**Date:** 2026-07-30 · **Rig:** 192.168.1.150, WLED 0.15.1, vid 2507300
**Repo:** `main` @ `393af46`, `2.5.10+58`
**Diagnosis only. Nothing fixed. No branches.**

---

## 0. TWO CORRECTIONS BEFORE ANYTHING ELSE

This task was commissioned on a premise from my own `VERIFICATION_REPORT.md`. **That premise was wrong, and the correction changes what needs fixing.** Stating it first because everything downstream depends on it.

### Correction 1 — **There is no regression. Nothing re-broke `9158c00`.**

I reported "11:32 preset-verify 6/6 PASS → 14:35 presets broken" as a same-day regression inside an 8-build window. **It is not.** The two readings measured *different properties*.

The bench's `presetIsOn` ([bench/src/bench_core.dart:146-155](bench/src/bench_core.dart#L146-L155)):

```dart
bool presetIsOn(Map<String, dynamic> def) {
  final seg = def['seg'];
  if (seg is List) {
    for (final s in seg) {
      if (s is Map && s['on'] == true) return true;   // ← SEGMENT-level on
    }
    return false;
  }
  return def['on'] == true;                            // ← root, only when no seg
}
```

Presets 1/3/4/5 each have 2 segments, so **the root-`on` branch is never reached.** I ran the bench's own function against the presets I captured at 14:35:

| Preset | bench `presetIsOn` | root `on` | `seg.on` |
|---|---|---|---|
| 1 NGL On | **True** | **ABSENT** | `[False, True]` |
| 2 NGL Off | False | `false` | `[False, False]` |
| 3 NGL Dim | **True** | **ABSENT** | `[False, True]` |
| 4 NGL Low | **True** | **ABSENT** | `[False, True]` |
| 5 NGL Medium | **True** | **ABSENT** | `[False, True]` |

**The bench returns PASS on these presets right now — the same result it gave at 11:32 — while preset 1 demonstrably fails to power the strip.** There was no change between the two readings. The bench has been passing on broken presets the whole time.

I will correct `VERIFICATION_REPORT.md` §2.4 and §5 accordingly.

### Correction 2 — **`ib` is a request flag, not a stored field**

I reported "`ib` ABSENT" as evidence of breakage on every preset. That is meaningless: `ib` is an input to `psave` telling WLED *whether to include root `on`/`bri` in the stored preset*. WLED never writes `ib` back into `presets.json`, so **`ib: ABSENT` is expected on every preset, healthy or not.**

**The only valid diagnostic signal is the presence of root `on`.** All analysis below uses that.

### What is actually true

The measured device failure stands and is unchanged: **loading preset 1 (`ps` −1→1, HTTP 200) leaves the master OFF.** Presets 1/3/4/5 carry no root `on`, so a timer firing `macro:1` loads segments and never powers the strip.

**The defect is not a regression. It is that `9158c00` never healed pre-existing presets, and still doesn't.**

---

## 1. EVERY PRESET WRITE PATH

`savePreset` is the sole funnel to the wire ([wled_service.dart:929-1000](lib/features/wled/wled_service.dart#L929-L1000)); it spreads the caller's state and appends `psave`. `normalizeWledPayload` ([wled_payload_utils.dart](lib/features/wled/wled_payload_utils.dart)) copies the payload and replaces only `seg` — **root keys survive it.** So `on`/`ib` correctness is entirely determined by each caller.

Four callers. **All four are correct in code.**

| # | Path | Slots | Asserts root `on`? | Sends `ib:true`? | Guarded by |
|---|---|---|---|---|---|
| 1 | [schedule_sync.dart:702](lib/features/schedule/schedule_sync.dart#L702) `psaveIfChanged` — system presets | 1, 3, 4, 5 | **Yes** — `{'on': true, 'bri': N, 'ib': true}` ([:728-782](lib/features/schedule/schedule_sync.dart#L728)) | **Yes** | ⚠️ **name-only** `_presetNamed` |
| 2 | same, OFF preset | 2 | **Yes** — `buildNglOffPresetState` | **Yes** | ✅ content-aware `isNglOffPresetSatisfied` |
| 3 | same, schedule design presets | 10-25 | Yes — always-psave (Option A, `2fbf45e`) | Yes | ✅ always re-saves |
| 4 | [calendar_entry_lease_manager.dart:1081](lib/features/schedule/calendar_entry_lease_manager.dart#L1081) — lease presets | 26-41 | **Yes** — `_synthesizeWledPayload` emits `'on'` + `'ib': true` for both on and off leases ([:915-950](lib/features/schedule/calendar_entry_lease_manager.dart#L915)) | **Yes** | date-keyed; old leases never re-saved |
| 5 | [sunrise_off_service.dart:237](lib/features/schedule/sunrise_off_service.dart#L237) — NGL Off | 2 | Yes — reuses the schedule OFF state | Yes | ✅ content-aware |
| 6 | [edit_pattern_screen.dart:136](lib/features/wled/edit_pattern_screen.dart#L136) — user pattern save | **100+** ([wled_preset_ranges.dart:34,59-61](lib/features/wled/wled_preset_ranges.dart#L34)) | ❌ No — `pattern.toWledPayload()` | ❌ No | n/a — **cannot collide with 1-5** |
| 7 | [cloud_relay_repository.dart:611](lib/features/wled/cloud_relay_repository.dart#L611) — relay transport | passthrough | inherits caller | inherits caller | n/a |

**Indirect / read-modify-write paths checked:** no path reads a preset, mutates, and writes back. There is no bulk save-all. `normalizeWledPayload` is the only shared mutator and it preserves root keys. **The "model round-trip drops the keys" hypothesis is NOT what happened here** — I checked it specifically because it was the most likely shape, and the two model-sourced payloads (`lease.wledPayload`, `pattern.toWledPayload`) are the ones at slots 26-41 and 100+, not 1-5.

**Path 6 is worth noting but is not this bug:** user-pattern saves genuinely omit `on`/`ib`, so a user pattern fired as a scheduled macro would load dark. It lands at slot 100+, which no timer macro currently targets. **Latent, not active.**

---

## 2. THE OFFENDER — a name-only skip guard

Not a bad write. **A write that never happens.**

```dart
// schedule_sync.dart:728-733  — presets 1/3/4/5
await psaveIfChanged(
  id: 1,
  state: {'on': true, 'bri': 200, 'ib': true},   // ← CORRECT
  name: 'NGL On',
  isSatisfied: (d) => _presetNamed(d, 'NGL On'), // ← checks ONLY the name
);
```

```dart
// schedule_sync.dart — the predicate
static bool _presetNamed(Map<String, dynamic> def, String name) =>
    def['n'] is String && (def['n'] as String).trim() == name;
```

`psaveIfChanged` short-circuits when `isSatisfied` returns true ([:697-700](lib/features/schedule/schedule_sync.dart#L697)). So **if a preset named `NGL On` exists — with any content whatsoever — the write is skipped forever.** The `ib:true` in `state` is never sent.

Contrast preset 2, which self-heals because its predicate inspects content:

```dart
static bool isNglOffPresetSatisfied(Map<String, dynamic> def) =>
    _presetNamed(def, kNglOffPresetName) &&
    def['on'] == false &&          // ← root on checked
    _presetIsOff(def);
```

**That asymmetry exactly predicts the device state:** preset 2 has root `on:false` (healed), presets 1/3/4/5 do not (never healed).

### This is a known, documented, un-actioned gap

The code says so, at [schedule_sync.dart:776-781](lib/features/schedule/schedule_sync.dart#L776):

> *"isSatisfied requires the stored def to actually assert root on:false… this self-heals legacy segments-only preset 2… **(The ON presets 1/3/4/5 skip on name only and share this landmine; re-saving them is tracked separately as post-main queue item #3.)**"*

**The author of `9158c00` knew the ON presets would not self-heal and deferred it.** The fix works on a virgin controller and is inert on every controller that already had these presets — which is every controller commissioned before 2026-07-22.

### Corroboration from the lease presets

The same pattern appears independently, and it confirms the model:

| Preset | Name | root `on` | Written |
|---|---|---|---|
| 27 | Lease 2026-07-31 | **`true`** | After `b97f793` (lease ib fix) → healthy |
| 26, 28, 29, 30, 41 | Leases 2026-07-21…26 | **ABSENT** | Before it → never re-saved |

**Presets written after their respective `ib` fix carry root `on`; presets written before it do not, and nothing re-saves them.** Two independent code paths, one behaviour. That is a structural gap, not a regression.

---

## 3. GIT — what changed between `9158c00` and HEAD

`9158c00` — 2026-07-22 — *"fix(schedule): scheduled ON-presets assert master power at load via ib:true"*.

Twelve commits touched preset write paths since:

```
9190cb8  sunrise-off — guarantee NGL Off preset + compaction-safe slot 8
f8ce483  global daily sunrise-off — controller-resident WLED timer
852eaf1  merge: Neighborhood Sync hardening (flag-gated inert)
0b99137  P0-3.2 — schedule sync preserves lease timer slots
7874f5c  P0-3.3 — lease cfg write verified via hardened path
b97f793  P0-3.1 — lease timer en int + preset ib
c3a1d9f  feat(bench): WLED verification harness — M-21
200e9e3  refactor: extract pure builders to Flutter-free files
d04776c  per-channel power (P1-43)
ccc4573  stall path re-LOOKs before re-POST
8ff5cd3  tolerate post-stall cfg readback race
769d6e9  OFF preset asserts master-off via ib + purge orphaned presets
```

**No commit reverses `9158c00`.** I read the current `psaveIfChanged` block: `ib: true` is still present on all four ON presets. **There is no offending commit to name, because there is no regression.**

Two commits are relevant in the opposite direction:
- **`769d6e9`** gave preset 2 its content-aware predicate — the fix pattern that presets 1/3/4/5 still lack.
- **`b97f793`** added `ib` to lease presets — which is why lease 27 is healthy and 26/28/29/30/41 are not.

---

## 4. BLAST RADIUS

### Per-device. No cloud propagation.

**There is no Firestore `presets` collection.** WLED presets live only in controller flash. Nothing syncs a preset definition between controllers or restores one from cloud. So a degraded preset **cannot propagate** to another customer or another controller.

### Does a customer's library degrade as they use the app? **No.**

This was the wrong framing in my earlier report. Presets are not corrupted by use. They are **written once and never re-healed.** The state is static, not progressive. Using the app more does not make it worse; it also never makes it better.

### How many stored presets are already degraded?

| Scope | Degraded? |
|---|---|
| Presets 1/3/4/5 on any controller commissioned **before 2026-07-22** | **Yes — and permanently, under current code** |
| Presets 1/3/4/5 on a controller first synced **after** `9158c00` with no prior `NGL On` | No — written correctly on first sync |
| Preset 2 | No — content-aware predicate heals it |
| Schedule design presets 10-25 | No — always re-saved |
| Lease presets created before `b97f793` | Yes — but self-expiring (date-keyed, superseded) |
| User patterns 100+ | Omit `on`/`ib`, but no timer targets them — **latent only** |

**Realistically the whole installed fleet.** `9158c00` is eight days old; the app has been in customers' hands far longer. Any controller that ever ran a schedule sync before 2026-07-22 has a `NGL On` preset that the name-only guard will protect from correction forever.

**Field symptom:** every scheduled ON event fires the design but leaves the master off — **the lights stay dark**. Which is exactly the original complaint `9158c00` was written to fix, still live on every pre-existing install.

### Does this need a repair script alongside the fix? **No — if the fix is done right.**

Making the predicate content-aware **is** the repair: the next schedule sync on each controller detects the missing root `on` and re-saves. Same self-healing mechanism `769d6e9` already gave preset 2, proven on this rig.

**A separate script would be needed only** if you wanted to heal controllers that will not run a sync soon. Given sync runs on schedule edits and app use, self-heal is likely sufficient — but it heals **on next sync, not on next launch**, so a customer who never edits a schedule stays broken. Worth an explicit decision rather than an assumption.

⚠️ **One cost to weigh, and it is not free:** a `psave` on this firmware **applies its state live**. Healing four presets means four live applies on the next sync. `schedule_sync` already has capture/restore scaffolding for exactly this ([:901-905](lib/features/schedule/schedule_sync.dart#L901)), so the machinery exists — but the healing sync will be visibly disruptive once per controller.

---

## 5. REGRESSION GUARD — make it un-re-breakable

`9158c00` shipped with no test that would catch its own reversal, **and the harness it did ship alongside actively masks the failure** (§0). Both need fixing.

### Guard 1 — fix `presetIsOn`, or rather stop using it for this

**The existing check is not merely incomplete, it is measuring the wrong property.** Segment-level `on` says a segment renders; **root `on` is what powers the master.** Those are different, and only the second is what `ib:true` exists to produce.

```dart
/// Does loading this preset ASSERT MASTER POWER? Only root `on` does that.
/// Segment-level `on` is NOT a substitute — a preset can have on:true segments
/// and still load into a master-off strip, leaving the lights dark. That is
/// exactly the 9158c00 failure mode.
bool presetAssertsMasterPower(Map<String, dynamic> def) => def['on'] == true;
```

Assert `presetAssertsMasterPower` for 1/3/4/5, and `def['on'] == false` for 2. **Keep `presetIsOn` for any caller that genuinely means "does anything render", but it must not gate the ON-preset invariant.**

This is a static check on the persisted preset — it satisfies "assert on the persisted preset, not on the write call."

### Guard 2 — the functional check, which is the one that cannot be faked

Static key inspection still encodes an assumption about what WLED does with `ib`. **Test the actual property instead:**

```
For each ON preset P in {1,3,4,5}:
  1. POST /json/state {"on": false}            → confirm state.on == false
  2. POST /json/state {"ps": P}                → load the preset
  3. GET  /json/state                          → ASSERT on == true
  4. restore prior state
```

**This is un-re-breakable by construction.** It does not care whether the mechanism is `ib`, root `on`, or something a future firmware invents — it asserts the only thing that matters: *loading this preset turns the lights on from a dark strip*. It is the exact test I ran by hand today that exposed the defect, and it takes seconds per preset.

**Add it to `preset-verify`.** Note it is mutating (it toggles master), so it belongs behind the same capture/restore the harness already uses.

### Guard 3 — a unit test on the predicate, not the payload

The existing `psaveIfChanged` state maps are already correct; testing them proves nothing. **Test the skip predicate:**

```
GIVEN a stored def {"n":"NGL On", "seg":[{"on":true}]}   // name matches, no root on
THEN  isSatisfied(def) MUST be false                      // → forces a re-save
```

That is the assertion that fails today and would have failed on the day `9158c00` shipped.

---

## 6. BENCH `fire-test` — split the two failure modes (~0.5h)

Separate item, and the single cheapest high-value change in this document.

**Today** `fire-test` asserts one thing — `post-fire /json/state on == true` — which fails **identically** under two unrelated defects:

- the timer never fired, or
- the timer fired and loaded a preset that does not power the strip.

I confirmed both are present on this rig simultaneously, which is why this has been ambiguous for weeks.

**`state.ps` is the discriminator, and I verified it is reliable:** loading preset 1 by hand moved `ps` −1→1, and it still read `1` four minutes later. It persists and records a preset load. During both fire windows it stayed `-1`.

### Specified change

In the `fire-test` command ([bench/src/bench_core.dart](bench/src/bench_core.dart), harness in [bench/bin/bench.dart](bench/bin/bench.dart)):

1. **Before arming:** read `state.ps`, record as `psBefore`. Arm the scratch timer with macro `M`.
2. **After the fire minute:** read `state` once, capturing **both** `on` and `ps`.
3. **Emit two independent checks instead of one:**

| Check | Condition | Meaning on failure |
|---|---|---|
| `fire-test: timer fired (preset loaded)` | `ps == M` (and `ps != psBefore`) | **Timer evaluation did not fire.** Device/firmware side. App exonerated |
| `fire-test: fired preset asserts master power` | `on == true` | **Timer fired but the preset is dark.** App side — the `9158c00` class |

4. **Report them separately.** A run where check 1 fails and check 2 is skipped is a firmware finding. A run where check 1 passes and check 2 fails is an app finding. Today's rig fails check 1 *and* would fail check 2 — which the current single assertion collapses into one uninformative line.

**Caveat worth encoding in the check's message:** `ps` is cleared when state is modified after a preset load, so nothing else may write state during the fire window. The harness already holds the strip idle; make it explicit so a future edit does not break the discriminator silently.

---

## 7. SUMMARY

| Question | Answer |
|---|---|
| Is this a regression? | **No.** No commit reversed `9158c00`. My earlier claim was wrong — §0 |
| What is the defect? | The name-only skip guard on presets 1/3/4/5 means `ib:true` **never reaches any controller that already had those presets** |
| Which path is the offender? | [schedule_sync.dart:728-782](lib/features/schedule/schedule_sync.dart#L728) — `isSatisfied: (d) => _presetNamed(d, …)` |
| Was it known? | **Yes** — documented at [:776-781](lib/features/schedule/schedule_sync.dart#L776) as "post-main queue item #3" and deferred |
| Blast radius | Effectively the whole pre-2026-07-22 fleet. Per-device, no cloud propagation, does not worsen with use |
| Repair script needed? | **No**, if the predicate becomes content-aware — that self-heals on next sync. But it heals on next *sync*, not next *launch* |
| Why did the harness not catch it? | `presetIsOn` checks **segment** `on`, never root `on`. It passes on these broken presets right now |
| Cheapest decisive fix to the harness | The functional check (Guard 2): master off → load preset → assert `on == true` |

**Not fixed. No branches created.**
