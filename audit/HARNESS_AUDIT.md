# BENCH HARNESS — ASSERTION AUDIT AND REPAIR

**Date:** 2026-07-30 · **Scope:** `bench/` (+ its own unit test, `test/bench/bench_core_test.dart`)
**Rig:** 192.168.1.150 · WLED 0.15.1 · vid 2507300 · 290 LEDs · 2 channels
**Nothing in `bench/` ships.** No `lib/` file was modified. No branches created.

---

## 0. THE CLASS OF DEFECT

`presetIsOn` was not a one-off. Reading every predicate the way it should have been read turns up **eleven divergences between what an assertion is named and what it verifies**, including:

- **two checks hardcoded to `true`** — they could never fail and verified nothing at all;
- **one check that passes on total write failure** — a dead controller, a dropped POST or a network error all read as the expected result;
- **one silent skip** that shrinks the denominator, so a controller missing presets scores green;
- **one documented invariant that was never implemented** — printed as a log line, asserted nowhere;
- **an infrastructure helper that claims five minutes of patience and delivers two attempts**;
- and, worst in kind, **a unit-test suite that encoded the defect as the expected behaviour**, which is why `presetIsOn` survived scrutiny for weeks.

The common shape: **the harness asserts a structural proxy that is cheap to read, and names it after the functional property it stands in for.** When firmware behaviour changed (or was never what the proxy assumed), the proxy kept passing.

---

## 1. AUDIT — EVERY ASSERTION

Legend: **✅** name matches behaviour · **⚠️** diverges under stated conditions · **🔴** materially wrong today.

| # | Check | (a) Name claims | (b) Code actually verifies | (c) Divergence condition |
|---|---|---|---|---|
| 1 | `probe reachable` | Controller is reachable | `/json/info` **and** `/json/cfg` both non-null | ✅ |
| 2 | `layout matches known_layout.json` | Live layout == known layout | `totalLeds` + per-bus `start`/`len` **only** | 🔴 **Always.** `rev`, `pin`, `type`, `order`, `skip` are never compared. `rev` is the per-channel wiring direction the app preserves across every cfg write; a silent flip reverses a chase and the check stays green. Compounded by `layoutFromJson` hardcoding `pin: [0]`, making pin drift *structurally* undetectable |
| 3 | `layout drift (P1-42)` | Drift is detected | Same predicate as #2 | 🔴 Same |
| 4 | `snapshot captured` | A snapshot was captured | `state`+`cfg` non-null and a file was written | ⚠️ `presets` may be null and the check still passes, silently recording a snapshot with zero presets — which `restore` later replays |
| 5 | `en truth table (int→1, bool→0)` | WLED is **type-strict** on `en` | `norm(v) = (v==1 \|\| v==true) ? 1 : 0`, then int→1, bool→0 | 🔴 **Two holes.** (i) `norm` maps bool `true`→1, erasing the exact type distinction under test — an int write echoed back as a bool passes. (ii) `stored == null` (scratch never appeared) normalizes to 0, so **the bool half PASSES on total write failure**: dead controller, dropped POST, network error all read as "correctly disabled" |
| 6 | `ON-preset N asserts power (reads on)` | Preset asserts **MASTER** power | `presetIsOn` → true if **ANY SEGMENT** is `on`; root `on` reached only when there is no `seg` list | 🔴 **Whenever the preset has segments — i.e. always in practice.** This is the known defect. Bench-rig presets 1/3/4/5 return `presetIsOn=True` while root `on` is absent and loading them leaves the strip dark |
| 7 | (absent ON preset) | — | `if (def == null) continue;` — **emits no check at all** | 🔴 **Always.** A missing preset produces silence, shrinking the denominator: 6/6 can become 2/2 and still read as green. A partially-synced controller is invisible |
| 8 | `OFF-preset 2 reads off` | Preset 2 kills master power | `!presetIsOn(off)` → "no segment is lit" | ⚠️ A preset with root `on:true` and all segments off **passes**. All-segments-off does not imply master-off — that is the pre-`769d6e9` bug shape |
| 9 | `all preset slots ≤ 250` | No over-ceiling slots | Exactly that | ✅ (minor: empty `{}` slots were counted as present) |
| 10 | `lease slots (26/28/41) not clobbered` | Lease slots were not clobbered | **`CheckResult(..., true, ...)` — hardcoded** | 🔴 **Always. The check can never fail and verifies nothing.** It reports whichever lease slots happen to exist and calls that a pass |
| 11 | (schedule slots 10-25) | Doc comment promises "no app-managed slots outside 10-25" | `_log` only — **never `_record`ed** | 🔴 **Documented invariant never implemented.** Printed, not asserted |
| 12 | `sync-sim landed (timersInsLanded)` | The sync write landed | Sent **real** timers are *contained* in the readback, position-independent | ⚠️ Containment by design (correct, given compaction). But **extra/stale timers are ignored**, so orphan accumulation — the actual field failure behind F-3 — is undetectable. `post2xx` is shown in evidence but not asserted |
| 13 | `fire-test: scratch timer armed` | Scratch armed | `timersInsLanded` | ⚠️ Records the failure and **does not return** — proceeds to wait 90s and emit a second check about a timer that was never armed |
| 14 | `fire-test: strip powered on at the minute` | The timer fired | `state.on == true` | 🔴 **Conflates two unrelated defects.** Fails identically when the timer never fired (firmware) and when it fired into a preset that does not assert master power (app). Both were true on the rig simultaneously |
| 15 | (fire-test dow/target) | — | Computed from the **HOST** clock, with a comment claiming *"WLED 0.15.1 does not expose wall time over JSON"* | 🔴 **The comment is false** — `/json` → `info.time` exposes it. Any host/controller clock or timezone skew arms the timer for the wrong minute and fails the test for a reason unrelated to the app |
| 16 | `P1-43 case 3` | One post, only A lit | Emitted shape + `state.on == true` + seg flags | ✅ (the only channel-power case that checks master) |
| 17 | `P1-43 case 4` | B on, A undisturbed | Seg flags **only** | ⚠️ Does not assert master is on. `litFromState` means "segment flagged on", not "physically lit" — with master off, both segs read `on:true` and the check passes on a dark strip |
| 18 | `P1-43 case 1` | Only A dies | Seg flags **only** | ⚠️ Same |
| 19 | `P1-43 case 2` | Master follows off | Emitted shape + `state.on == false` | ✅ |
| 20 | (channel-power restore) | *"Restore master to its pre-test power"* | Restores **master only** | ⚠️ Per-segment on-states are left mutated, leaking state into every command that follows |
| 21 | `restore timers from <snap>` | Timers restored | `timersInsLanded` containment | ⚠️ Same containment gap as #12 — a stale timer surviving the restore is invisible unless it collides |
| 22 | `restore master power` | Master power restored | **`CheckResult(..., true, ...)` — hardcoded** | 🔴 **Always.** Posts the state and asserts nothing about whether it took |
| 23 | `patientVerify` *(infra, gates #12/#13/#21)* | *"poll … up to `maxWait`"* (5 min) | Fast-path confirm; if false, wait 20s, ping, confirm **once**, then **return** | 🔴 **Always.** Two confirm attempts ~20s apart despite `maxWait: 5min`. **Every historical `verified=false (20s)` is this bug**, not a controller given five minutes |
| 24 | `test/bench/bench_core_test.dart` | Regression guard for the above | Fixtures are segment-only presets with **no root `on`**, asserted to PASS; plus an explicit test that bool `true` must normalize like int 1 | 🔴 **The guard asserted the bug.** This is why #5 and #6 survived review — a correct fix would have turned the suite red and looked like the regression |

---

## 2. REPAIR — what changed

All in `bench/` plus that harness's own unit test. **No `lib/` file touched.**

### `bench/src/bench_core.dart`

| Fix | Detail |
|---|---|
| **`presetIsOn` removed** | Split into two honestly-named functions. `presetAssertsMasterPower(def) => def['on'] == true` is now **the** authoritative signal; `presetAnySegmentOn(def)` keeps the segment scan for supporting evidence and is never consulted for power. The old fallback-to-root behaviour is gone — it was what made the misnomer plausible |
| **`ib` documented as a non-signal** | `ib` is a `psave` **request flag**; WLED never writes it back, so `ib: ABSENT` is expected on every preset, healthy or broken. Called out in-code so nobody re-adds it as a check |
| **Absent presets emit a check** | Partial sync → explicit FAIL per missing ON/OFF preset. A wholly un-synced controller emits **one** explicit, passing check instead of silence |
| **OFF preset 2** | Now requires root `on:false` **and** no segment lit |
| **Slot-band invariant implemented** | `checkPresetSlotBands` — the invariant the doc comment promised. Flags slots in the unaccounted 6-9 and 42-99 gaps |
| **`checkLeaseSlotsIntact`** | Replaces the hardcoded `true` with a real before/after comparison |
| **`detectLayoutDrift`** | Now compares `rev`, `type`, `order`, `skip`, `pin`. `layoutToJson`/`layoutFromJson` round-trip them, with defaults mirroring `WledLedBus` (type 30, order 1) so legacy layout files do not report false drift |
| **`checkEnTruthTable`** | Type-strict (a bool readback for an int write now FAILS); requires `intWriteLanded` so a never-landed control write reports **INCONCLUSIVE** instead of passing the bool half |
| **`parseControllerTime`** | Parses WLED's non-padded `info.time` so fire-test can use the controller clock |
| **`checkFireTestSplit`** | The two-check split, keyed on `ps` |
| **`parsePresets`** | Drops empty `{}` slots WLED emits for never-written presets |

### `bench/bin/bench.dart`

| Fix | Detail |
|---|---|
| **fire-test split** | Emits **A: timer FIRED (preset loaded)** keyed on `ps`, and **B: fired preset asserts MASTER power** keyed on `on`. When A fails, B is recorded as explicitly **NOT EVALUATED** rather than silently masked — the denominator stays honest and nobody misreads silence as a pass |
| **fire-test uses the controller clock** | Reads `info.time`; logs host/controller skew and records a **precondition FAIL** if skew > 60s. Falls back to host with a loud warning |
| **fire-test bails on arming failure** | Was: record FAIL, then wait 90s and emit a meaningless second check. Now returns |
| **`ps` captured before arming** | With an in-code warning that nothing may write `/json/state` during the window, or the discriminator is destroyed |
| **Functional preset guard added** | `master OFF → load preset N → assert state.on == true`, per preset 1/3/4/5. Captures and restores master + `ps`. **This cannot be faked by a firmware change in mechanism** — it asserts the only property that matters |
| **Lease-slot check made real** | Uses `checkLeaseSlotsIntact` against a re-read |
| **`restore master power` made real** | Posts, re-reads, compares |
| **channel-power cases 1 & 4** | Now also assert master is on, so "lit" means lit |

### `bench/src/wled_client.dart`

| Fix | Detail |
|---|---|
| **`patientVerify` actually retries** | Keeps re-confirming while the controller is live, instead of returning on the first attempt. Bounded by a new `maxConfirmAttempts` (default 4) so a genuinely-unpersisted write fails in ~1 min rather than pinning the suite for 5. **Stall polls do not burn an attempt**, so real multi-minute flash stalls are still waited out |

### `test/bench/bench_core_test.dart`

Rewrote the fixtures that encoded the defect. Notable additions:

- **`ON preset with segs on but NO root on → FAIL (the 9158c00 shape)`** — the live bench-rig shape, asserted to fail. This is the guard that was missing.
- `int write echoed back as bool true = FAIL` — replaces `bool true normalizes like int 1`, which asserted the bug.
- `int control never landed = FAIL as INCONCLUSIVE`.
- `OFF preset 2 with no seg lit but root on:true → FAIL`.
- Partial-sync and un-synced controller cases.
- Full coverage of the fire-test split, slot bands, lease integrity, and controller-clock parsing.

**Result: 36/36 unit tests pass** (was 24 tests before; several of the originals asserted the wrong thing).

> **Note on scope:** the instruction was "`bench/` only". `test/bench/bench_core_test.dart` is the harness's own test and had to move with the signatures — leaving it red would have broken `flutter test` for everyone. It carries no release risk for the same reason `bench/` doesn't.

---

## 3. RE-BASELINE

### **TRUE baseline: 18/28 checks passed. Exit code 1.**

`dart run bench/bin/bench.dart all` — 2026-07-30 15:16 · full log:
[rebaseline_final.log](audit/verification_evidence/rebaseline_final.log)

**The historical "21/21" is void as a comparison.** It counted 21 checks; this counts 28. Two of the old 21 could never fail (hardcoded `true`), several measured the wrong property, and absent presets emitted nothing. **Do not read 21→18 as a regression — the old denominator was not measuring the same things.** Nothing about the rig got worse today; the instrument stopped lying.

### Which previously-passing checks now fail — and why

| Check | Was | Now | Why the old result was wrong |
|---|---|---|---|
| `ON-preset 1/3/4/5 asserts power` ×4 | **PASS** | **FAIL** | Tested segment-level `on`. Root `on` is ABSENT on all four; loading any of them leaves the strip dark |
| `functional: preset N lights a dark strip` ×4 | *(did not exist)* | **FAIL** | New end-to-end guard. Independently confirms the four static failures by a different method — `master off → ps:N → state.on` stays `false` |
| `fire-test: strip powered on at the minute` | FAIL (single line) | **split → A PASS / B FAIL** | The old line conflated two defects. See below — this is the headline |
| `layout drift (P1-42)` | PASS | **FAIL** | New `rev`/`pin` comparison. `known_layout.json` predates those fields — see "artefact" below |
| `lease slots not clobbered` | PASS *(hardcoded)* | **PASS (real)** | Now a genuine before/after comparison |
| `restore master power` | PASS *(hardcoded)* | **PASS (real)** | Now posts, re-reads, compares |
| `sync-sim restore` / `restore timers` | **FAIL (20s)** | **PASS (0s)** | Were failing on the `patientVerify` bug (2 attempts, not 5 minutes), not on the controller |
| `en truth table` | PASS | **PASS (stricter)** | Now type-strict and gated on a landed control write. Firmware genuinely is type-strict: `en:1(int)→1`, `en:true(bool)→0` |
| `P1-43` cases 1-4 | PASS | **PASS** | Cases 1 and 4 now also assert master power. **P1-43 survives the stricter check — that claim is sound** |

### 🔴 The headline: the fire-test split overturned a conclusion I had reached twice

```
VERIFIED-BY-BENCH: fire-test A: timer FIRED (preset 1 loaded) — ps 2→1 (want 1)
FAIL: fire-test B: fired preset asserts MASTER power — post-fire state.on=false
      — the timer FIRED but preset 1 left the master OFF. APP side.
```

**The timers fire.** `audit/VERIFICATION_REPORT.md` concluded — twice, from two manual runs — that WLED 0.15.1 does not evaluate clock timers, and exonerated the app. **That was wrong.** My manual tests armed the scratch timer in an array that also carried the live **solar sentinel** (`hour:255`); the harness documents that exact hazard in-code and posts a clean single-entry array to avoid it. I reproduced a known payload-shape problem twice and read it as firmware behaviour.

**There is ONE defect and it is app-side:** the timer fires, loads `macro:1`, and preset 1 carries no root `on`. Diagnosed in `audit/PRESET_REGRESSION.md`. `VERIFICATION_REPORT.md` has been corrected.

**9 of the 10 failures are that single root cause**, measured statically (4), functionally (4), and end-to-end through a real timer fire (1). Convergence from three independent methods is the useful property here — the old harness scattered one defect into an uninterpretable line.

### The one failure that is an artefact, not a defect

`layout drift` fails with `bus0 pin [0]→[2]; bus1 rev false→true; bus1 pin [0]→[14]`. `known_layout.json` predates the new fields, so there is no baseline for them. **`probe --update` clears it.** I deliberately did not run it — that would rewrite the baseline before you have seen what changed.

**But it surfaced a fact that had been invisible: `bus1.rev == true`.** Channel 2 on this rig **is** wired reversed, and nothing in the app or the old harness could see it. That directly answers **Q-D** in `audit/CHANNEL_GROUPING_SCOPE.md` — "do installers actually set `rev`?" — with **yes, at least on this rig**, which makes the per-channel direction work there plumbing rather than modelling.

### ⚠️ One audit finding I flagged and did NOT fix — with a live demonstration

Finding **#12/#21**: `timersInsLanded` is a *containment* check, so a restore passes while stale timers survive. **That happened during this very run.** After `restore` reported PASS, the rig still held the sync-sim fixture's `4:20/macro 2/dow 17` timer.

I left the gap open (a "nothing extra survived" assertion is a design change, not a repair) but it is real, it is demonstrated, and it should be the next thing fixed in this harness.

### 📌 A correction to `VERIFICATION_REPORT.md` §3 that came out of cleanup

While removing that stale timer I could not displace it with 2-entry, 3-entry, or ad-hoc 10-entry arrays — and one attempt **appended a duplicate solar sentinel**, making it worse. What finally worked in a single write was the **canonical 10-slot shape the app actually uses**: indices 0-7 general (`en:0` stubs), **index 8 = sunrise, index 9 = sunset**. It cleared both stale entries at once.

**So §3's conclusion — "the padding-based slot reclaim strategy is void" — is NOT established.** My F-3 experiments used non-canonical arrays (stubs at 2-9, sentinels absent or in general slots). WLED evidently treats `hour:255` entries as a separate slot space, which is precisely the model the app encodes. **Re-test slot reclaim with canonical payloads before acting on that finding.** I have not corrected §3 beyond flagging it here, because settling it deserves its own controlled run rather than an inference from a cleanup.

### Rig state left behind

**Clean, and matching the session's intended baseline:**

```
TIMERS: 2
  0 {"en":1,"hour":19,"min":10,"macro":27,"dow":16, ...}   ← lease (Fri 19:10)
  1 {"en":1,"hour":255,"min":0,"macro":2,"dow":127}        ← global sunrise-off
STATE: on=false, ps=-1
```

Removed during cleanup: the sync-sim `4:20` fixture artefact and a duplicate sunrise sentinel I created while experimenting. Presets untouched — **the four broken ON presets are deliberately left as-is** so the fix can be verified against them. Snapshots from both runs are in `bench/snapshots/`.

### Recommended next steps

1. **Fix the preset defect** (`audit/PRESET_REGRESSION.md`) — make the skip predicate content-aware. Then re-run: 9 of the 10 failures should clear in one change.
2. **Run `probe --update` once** after reviewing the `rev`/`pin` values, to establish the fuller layout baseline.
3. **Close finding #12/#21** — add a "nothing unexpected survived" assertion beside the containment check.
4. **Re-test slot reclaim with canonical 10-slot payloads** before acting on `VERIFICATION_REPORT.md` §3.
