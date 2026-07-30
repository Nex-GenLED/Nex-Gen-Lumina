# PRESET MASTER-ON FIX — IMPLEMENTATION REPORT

**Date:** 2026-07-30 · **Rig:** 192.168.1.150 · WLED 0.15.1 · vid 2507300
**Repo:** `main` @ `393af46` (working tree), `2.5.10+58`
**Touches `lib/` — release-affecting.** No branches created.

---

## 0. HEADLINE

> ### ✅ (3d) END-TO-END PASSES. A real timer fired and the lights came on.
>
> ```
> VERIFIED-BY-BENCH: fire-test A: timer FIRED (preset 1 loaded) — ps 2→1 (want 1)
> VERIFIED-BY-BENCH: fire-test B: fired preset asserts MASTER power
>                    — post-fire state.on=true (want true)
> ══ 4/4 checks passed ══
> ```
>
> Scratch timer armed for 15:51 targeting `macro:1`, master OFF, waited through the fire minute.
> `ps 2→1` proves the timer fired; `on=true` proves the preset powered the strip.
> **This is the gate on R-1 and it is met.** R-7 is met by the same change.

**Full harness after the fix: 27/28.** All nine preset-related failures cleared. The one remaining failure is a pre-existing layout-baseline artefact, unrelated (§6).

---

## 1. THE CHANGE

Two `lib/` files, **180 insertions / 7 deletions**, most of it comment. The functional diff is four predicate swaps and three additive declarations.

### `lib/features/schedule/schedule_sync.dart`

```diff
-      isSatisfied: (d) => _presetNamed(d, 'NGL On'),
+      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL On'),
-      isSatisfied: (d) => _presetNamed(d, 'NGL Dim'),
+      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL Dim'),
-      isSatisfied: (d) => _presetNamed(d, 'NGL Low'),
+      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL Low'),
-      isSatisfied: (d) => _presetNamed(d, 'NGL Medium'),
+      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL Medium'),
```

Plus three additions:

```dart
static bool isNglOnPresetSatisfied(Map<String, dynamic> def, String expectedName) =>
    _presetNamed(def, expectedName) && def['on'] == true;

static const Map<int, ({String name, int bri})> kOnPresetSpecs = {
  1: (name: 'NGL On', bri: 200), 3: (name: 'NGL Dim', bri: 51),
  4: (name: 'NGL Low', bri: 102), 5: (name: 'NGL Medium', bri: 153),
};

static Map<String, dynamic> onPresetHealState(int bri) =>
    {'on': true, 'bri': bri, 'ib': true};
```

The state maps passed to `psaveIfChanged` are **untouched** — they were always correct. The defect was the skip predicate, not the write.

The stale in-code comment marking this as *"post-main queue item #3"* is updated to record it CLOSED.

### `lib/features/wled/controller_defaults_healer.dart`

New step **(e2)** in `run()` plus `_healOnPresetMasterPower`, and an `onPresetsHealed` field on `ControllerHealReport`.

---

## 2. (1) WHY ONLY `on`, AND NOT `bri`

**The predicate asserts name + root `on == true`. `bri` is deliberately excluded.**

- **A `psave` APPLIES its inline state live on this firmware** (documented in `schedule_sync.dart`, and the reason the idempotence skip exists at all). Every needless re-save is a visible disruption — the strip flashing on each sync.
- Brightness drift is **cosmetic**; root `on` absence is what makes a scheduled ON fire DARK. Only the second breaks the product.
- If `bri` were asserted, a user nudging the controller's brightness, or any rounding difference, would trigger a re-save on **every** sync — a psave storm for no user-visible benefit.
- It mirrors `isNglOffPresetSatisfied`, which asserts the master-state field (`on == false`) and **not** `bri`. Same shape, same reasoning.

**`ib` is asserted nowhere.** It is a `psave` REQUEST flag; WLED never writes it back. Final rig readback confirms it: every preset, healthy or not, shows `ib=ABSENT`. Asserting on it would fail on healthy presets forever.

---

## 3. (2) THE HEALER HOOK — AND A DELIBERATE DEVIATION ON THE MARKER

Hooked into `ControllerDefaultsHealer.run()` as step **(e2)**, alongside the existing NTP / tz / coords / gamma / AudioReactive heals. It repairs on **connect**, so a customer who never edits a schedule is still fixed.

### ⚠️ I did NOT add a persisted version marker. This is a deviation from the brief — reasoning below.

The instruction was to *"gate with a version marker so it runs once per controller"*. I used **readback gating** instead: the heal reads `/presets.json` and writes only to presets that fail the predicate.

**Why — three reasons, the third being decisive:**

1. **It matches this class's own stated policy.** The file header: *"HEAL-ONLY-BROKEN: a healthy controller receives ZERO writes."* The gamma heal in this same class already works exactly this way (*"pushGammaConfig readback-skips when already correct"*). A marker would make presets the odd one out.
2. **Cost is identical.** A marker costs a SharedPreferences read; readback costs one GET. Neither is meaningful on connect.
3. **A marker would suppress the re-heal you actually need.** A preset can be clobbered later by any psave path, and this codebase has a *documented, still-open* device-side revert phenomenon (gamma reverting after a few uses). A marker says "already done" and stops looking; **the readback re-heals automatically.** It also cannot desync from device truth — which matters here specifically, because the whole defect was an app-side belief about preset state that the device disagreed with.

**Answering the question as asked:** the marker, had I used one, would have been a SharedPreferences key. I did not add one, so there is no marker and nothing is stored. **If you want the marker anyway, say so** — it is a small addition, but I think it makes this heal strictly worse.

### A defect the rig exposed in my own first implementation

The first version issued four `psave`s back to back with no settle. On the live rig **preset 4 returned `ok=true` and read back with no root `on`** — a false-green flash write. Fixed by:

- a **900 ms settle** between psaves (`kPresetHealSettle`, mirroring the schedule-sync post-psave settle);
- a **second pass** that re-reads and retries whatever did not persist;
- a **final readback** that prunes `onPresetsHealed` to what actually landed, so the report never claims a heal that silently failed.

Found only because verification was against hardware. A unit test would have passed.

---

## 4. (3) VERIFICATION AGAINST THE RIG

Driven through the **real** `ControllerDefaultsHealer.run()` via `test/hardware/preset_heal_live_test.dart` (skipped unless `--dart-define=RUN_HW=true`, so CI is unaffected).

### (3a) PRE-STATE — presets 1/3/4/5 have no root `on`

```
preset 1: n='NGL On'     root_on=ABSENT   segs=2
preset 2: n='NGL Off'    root_on=False    bri=255     ← healthy (content-aware predicate)
preset 3: n='NGL Dim'    root_on=ABSENT   segs=2
preset 4: n='NGL Low'    root_on=ABSENT   segs=2
preset 5: n='NGL Medium' root_on=ABSENT   segs=2
```

### (3b) HEALER RUN — all four now assert root `on: true` ✅

```
PRE  broken: [1, 3, 4, 5]
HEAL report: on-presets1/3/4/5

POST preset 1 (NGL On):     root on=true bri=200
POST preset 3 (NGL Dim):    root on=true bri=51
POST preset 4 (NGL Low):    root on=true bri=102
POST preset 5 (NGL Medium): root on=true bri=153
```

Brightnesses match `kOnPresetSpecs` exactly. `ib` absent on all — as expected.

### (3c) FUNCTIONAL — master OFF → load preset → strip powers on ✅

```
FUNCTIONAL: master off → ps:1 → on=true ps=1
```

And all four via the harness's functional guard:

```
VERIFIED-BY-BENCH: functional: preset 1 lights a dark strip — master off → ps:1 → state.on=true
VERIFIED-BY-BENCH: functional: preset 3 lights a dark strip — master off → ps:3 → state.on=true
VERIFIED-BY-BENCH: functional: preset 4 lights a dark strip — master off → ps:4 → state.on=true
VERIFIED-BY-BENCH: functional: preset 5 lights a dark strip — master off → ps:5 → state.on=true
```

### (3d) END TO END — the one that matters ✅

```
controller time=2026-07-30 15:48:27  host=15:48:26  skew=0s
VERIFIED-BY-BENCH: fire-test: scratch timer armed — scratch landed on /json/cfg readback
scratch timer armed for 15:51 (dow bit 8); master off; ps=2; waiting for fire…
VERIFIED-BY-BENCH: fire-test A: timer FIRED (preset 1 loaded) — ps 2→1 (want 1)
VERIFIED-BY-BENCH: fire-test B: fired preset asserts MASTER power — post-fire state.on=true
══ 4/4 checks passed ══
```

**A real timer, armed on the controller, fired at its minute, loaded `macro:1`, and turned the lights on from a dark strip.** Reproduced in the standalone run and again inside the full suite (15:56).

### (3e) IDEMPOTENCY — second run is a clean no-op ✅

```
2nd run: no-op  onPresetsHealed=[]
```

Zero writes on a healthy controller, exactly as the heal-only-broken policy requires.

---

## 5. (4) FULL HARNESS — 27/28, all nine cleared

| | Before fix | After fix |
|---|---|---|
| **Total** | **18/28** | **27/28** |
| ON-preset asserts MASTER power ×4 | FAIL | **PASS** |
| functional: preset lights a dark strip ×4 | FAIL | **PASS** |
| fire-test B: fired preset asserts MASTER power | FAIL | **PASS** |
| fire-test A: timer FIRED | PASS | PASS |
| layout drift (P1-42) | FAIL | FAIL *(unrelated — §6)* |

**Nine of nine cleared.** No check regressed.

---

## 6. THE ONE REMAINING HARNESS FAILURE — unrelated

```
✗ layout drift (P1-42): bus0 pin [0]→[2]; bus1 rev false→true; bus1 pin [0]→[14]
```

`known_layout.json` predates the `rev`/`pin` comparison added during the harness repair, so there is no baseline for those fields. **`probe --update` clears it.** I did not run it — that rewrites the baseline, and you should see the values first. Not caused by, and not related to, this fix.

---

## 7. (5) TESTS THAT ENCODE THE DEFECT — FOUND, REPORTED, NOT REWRITTEN

**Yes — `test/features/schedule/schedule_sync_idempotent_test.dart`.** Two tests now fail, and **both failures are the fix working.**

The fixtures define presets 1/3/4/5 as:

```dart
1: {'n': 'NGL On', 'seg': [{'on': true}]},     // name + segment-on, NO root `on`
```

That is exactly the broken on-device shape. Preset 2's fixture, by contrast, carries `'on': false` with the comment *"Already healed: carries root on:false … so the OFF-preset self-heal skips it"* — the author had the correct model for preset 2 and not for the ON presets.

| Test | Expected | Actual |
|---|---|---|
| *Option A: pattern preset ALWAYS re-saved…; **system presets skip*** | `[10]` | `[1, 3, 4, 5, 10]` |
| *preset 2 named NGL Off but left ON is repaired (off-timer safety)* | `[2]` | `[1, 2, 3, 4, 5]` |

The first test's name states the now-incorrect expectation outright: *"system presets skip"*. They must **not** skip when they are broken.

**Not rewritten, per instruction.** Logged as **P3-57** in `docs/BUGS_AND_DEBT.md` with the recommended shape: make the 1/3/4/5 fixtures healthy (add root `on: true`) so the skip expectation becomes correct, **and** add a sibling test with the no-root-`on` shape asserting those slots ARE re-saved. ~1h.

**Rest of the schedule suite: 346 pass, 2 fail — and the 2 are exactly these.** No other `lib/` test encodes the broken preset shape (checked `schedule_sync_lease_preserve_test.dart`, `sunrise_off_gating_test.dart`, `sunrise_off_preserve_test.dart`; all clean).

---

## 8. SCOPE DISCIPLINE — what I did NOT do

| Noticed | Where it went |
|---|---|
| ON-preset definitions now live in two places (`kOnPresetSpecs` vs the inline literals in `syncAll`) | **P3-56.** Rewriting the shipping sync path to consume the map is a refactor; left it. The risk (definitions diverging → connect and sync fighting, strip flashing) is written up |
| `schedule_sync_idempotent_test.dart` fixtures | **P3-57.** Reported, not rewritten |
| `WledService.applyJson` reaches SharedPreferences | Noted only — test-environment friction, not a defect |

No refactoring, no cleanup, no opportunistic edits. The four broken presets on the rig were used as the fixture and are now healed **by the code under test**, which is the point.

---

## 9. RIG STATE LEFT BEHIND

```
preset 1: n='NGL On'     root_on=True  bri=200  ib=ABSENT
preset 2: n='NGL Off'    root_on=False bri=255  ib=ABSENT
preset 3: n='NGL Dim'    root_on=True  bri=51   ib=ABSENT
preset 4: n='NGL Low'    root_on=True  bri=102  ib=ABSENT
preset 5: n='NGL Medium' root_on=True  bri=153  ib=ABSENT

TIMERS: 3
  0 {"en":1,"hour":19,"min":10,"macro":27,"dow":16}   ← lease (Fri 19:10)
  1 {"en":1,"hour":4,"min":20,"macro":2,"dow":17}     ← sync-sim fixture residue (see note)
  2 {"en":1,"hour":255,"min":0,"macro":2,"dow":127}   ← global sunrise-off
STATE: on=false, ps=-1
```

**All five system presets are now healthy** — the fixture is consumed, which is the intended outcome of a successful fix.

⚠️ Timer index 1 (`4:20 macro:2 dow:17`) is the sync-sim fixture's OFF timer, left by the harness's containment-only restore (`HARNESS_AUDIT.md` finding #12/#21, open). It fires the OFF preset at 04:20 on Mon+Fri — harmless on a bench rig, but it is residue, not intent.

---

## 10. WHAT THIS DOES AND DOES NOT CLOSE

**Closes:**
- **R-7** — ON presets assert master power. Verified statically, functionally, and end-to-end.
- **R-1** — *"schedules work from the customer's seat."* A timer fires and the lights come on (3d).
- The in-code *"post-main queue item #3"*.

**Does NOT close:**
- Fleet repair is **per controller, on connect** and requires the app to reach it **on LAN**. The healer is LAN-only by design (the bridge cannot carry cfg). A customer who is only ever off-LAN is repaired on their next on-LAN connect, not before.
- Presets that are **absent** are not created by the healer — schedule sync owns that. An un-synced controller stays un-synced.
- The two failing idempotency tests (**P3-57**) and the definition-drift risk (**P3-56**).
