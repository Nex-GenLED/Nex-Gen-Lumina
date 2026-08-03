# ALL-STUB CLOBBER GUARD — implementation report

**Date:** 2026-08-03 · **Rig:** 192.168.1.150 (0.15.1, vid 2507300)
**Predecessor:** `audit/ALL_STUB_CLOBBER.md` (the bench proof this guard answers)
**Status:** IMPLEMENTED. Suite green against the known pre-existing failure. No branch created.

---

## 1. THE CHANGE

**[schedule_sync.dart](../lib/features/schedule/schedule_sync.dart)**

```dart
@visibleForTesting
static bool shouldSkipClobberingWrite({
  required List<Map<String, dynamic>> ins,
  required int refusedCount,
}) => refusedCount > 0 && !ins.any(_carriesAnyEnabledEntry);
```

- **`refusedCount`** — incremented via `countRefusal(s)` at all **five** refusal points in the
  arm-check loop: no-saved-preset, unparseable time, sunrise-off conflict, solar gate, `dow:0`.
- **Not `presetErrors.isNotEmpty`**, as instructed — several warnings fire without dropping a
  schedule (slots-full overflow; a redundant sunrise OFF superseded by the global one). Keying on
  the warning list would refuse a legitimate clearing write and strand stale timers forever.
- **`countRefusal` filters on `enabled && !isCurrentlyEvicted`.** The arm-check loop iterates
  `updatedSchedules` and, unlike `buildCfgPayload`, does **not** filter on `enabled`. Without this
  filter a single *disabled* solar schedule would block the clearing write for a user who had
  switched everything off. Not in the original scope; found while implementing.

The refusal returns `success: false` with actionable copy plus the per-schedule `presetErrors`:

> None of your schedules could be armed, so your controller was left unchanged. Check the warnings
> for what to fix.

**[my_schedule_page.dart](../lib/features/schedule/my_schedule_page.dart)** — the `!success`
branch preceded the warning branch at *both* display sites, so a failure carrying warnings showed
only the generic error and swallowed the per-schedule reasons. Both now append the warnings and
offer **Details**. Without this the guard would have been a tenth silent-ish failure: visibly
red, but with the only actionable text hidden.

---

## 2. TWO BUGS IN MY FIRST VERSION — both caught by the existing suite

Worth recording, because both were wrong in ways the four-case table did not cover.

**(a) Ordering — the guard ran before the off-LAN check.** For an off-LAN all-solar user
(Ellie and Tim are exactly this) it converted the neutral *"saved, will arm on next LAN sync"* into
a red failure. Off-LAN **no cfg write is attempted at all**, so there is nothing to clobber and
`deferredOffLan` is the truthful answer. Caught by `schedule_sync_off_lan_test`. The guard now
sits **below** the off-LAN check, with a comment pinning the ordering.

**(b) The global sunrise-off is meaningful payload.** My first predicate used
`isRealEnabledTimer`, which excludes `hour == 255`. A payload whose only content is the slot-8
sunrise-off therefore looked "empty" and was skipped — silently breaking the invariant that every
sync **re-asserts slot 8 rather than leaving it to luck**. Caught by `sunrise_off_preserve_test`
(2 failures). Hence `_carriesAnyEnabledEntry` (`en` truthy && `macro != 0`), which is broader than
`isRealEnabledTimer` on purpose: the question is *"is there anything worth writing?"*, not *"is
this an armable clock timer?"*.

**My own edge-case test asserted (b) backwards** — I had written "solar sentinel alone does NOT
count as armable" and expected a skip. It is now inverted, with a comment explaining why. The
pre-existing suite was right and my new test was wrong.

---

## 3. TESTS — `schedule_all_stub_clobber_guard_test.dart` (11 cases, all pass)

The four required cases:

| Case | `ins` | `refusedCount` | Expected | Result |
|---|---|---|---|---|
| all-solar + no leases | 8 stubs | 2 | **REFUSE** | ✅ |
| all-solar + active leases | leases + stubs | 2 | POST | ✅ |
| deleted last schedule | 8 stubs | **0** | POST | ✅ |
| normal sync | real timers | 0 and 3 | POST | ✅ |

Cases 1 and 3 use **byte-identical payloads** — `refusedCount` is the only thing distinguishing
them, which is the entire point of the flag.

Plus, driving the **real builder chain** rather than hand-built maps: two enabled `Sunset→Sunrise`
schedules (Ellie's live shape) through the real `buildCfgPayload` → real `padTimersToMax` → real
predicate. The test log captures the genuine gate firing:

```
ScheduleSync: skipped solar timer for "Pattern: a" (on=Sunset off=Sunrise) — solar disabled
ScheduleSync: skipped solar timer for "Pattern: b" (on=Sunset off=Sunrise) — solar disabled
```

Plus edge cases: sunrise-off makes the write worth sending; empty `ins` with/without refusals; a
disabled entry carrying a macro does not rescue the payload.

---

## 4. BENCH VERIFICATION (192.168.1.150)

**T0 — known state armed** (real clock schedule + lease at macro 27 + sunrise-off at slot 8):
```
ins length: 3
  [0] {"en":1,"hour":20,"min":0, "macro":1, "dow":127, start 1/1 end 12/31}
  [1] {"en":1,"hour":19,"min":10,"macro":27,"dow":16,  start 1/1 end 12/31}
  [2] {"en":1,"hour":255,"min":0,"macro":2, "dow":127}
```

**T1 — guard fires (all-solar shape → predicate SKIP → no POST issued):**
```
ins length: 3
  [0] {"en":1,"hour":20,"min":0, "macro":1, "dow":127, start 1/1 end 12/31}
  [1] {"en":1,"hour":19,"min":10,"macro":27,"dow":16,  start 1/1 end 12/31}
  [2] {"en":1,"hour":255,"min":0,"macro":2, "dow":127}

  ALL THREE ROWS SURVIVE — byte-identical to T0
```
Contrast with `ALL_STUB_CLOBBER.md` §2, where the same starting state lost both general rows.

**T2 — legitimate clear (`refusedCount == 0` → predicate POST → clearing payload sent):**
```
ins length: 1
  [0] {"en":1,"hour":255,"min":0,"macro":2,"dow":127}

  clock 20:00 macro1 : CLEARED (correct)
  lease macro27      : CLEARED (correct)
  sunrise-off hour255: SURVIVED (correct)
```
The slot-reclaim path still works — this was the case most likely to regress.

**Rig restored, verified byte-identical to pre-test.**

**Honest limitation.** I could not drive the real app's `syncAll` against .150 — that needs the
Flutter app running on a handset signed into an affected account. T1's "no POST" is established by
the pinned predicate (including through the real builder chain) plus the wire state being
untouched; it is not an end-to-end app-driven observation. T2 **is** a genuine wire test. The T1
payload shape simulated is Ellie's (no sunrise-off enabled), which is the at-risk configuration.

---

## 5. VERIFICATION SUMMARY

| Check | Result |
|---|---|
| `flutter analyze` — `schedule_sync.dart` + new test | **No issues found** |
| New guard suite | **11/11 pass** |
| Affected schedule suites (off-LAN, sunrise-off preserve, slot reclaim, lease preserve, solar refuse) | **38/38 pass** |
| Full suite | **1867 passed · 3 skipped · 1 failed** |
| Failing test | `cloud_ai_processor_normalize_test.dart` — the known stale P1-8 assertion. **No new failures.** |

---

## 6. WHAT THIS CHANGES FOR THE THREE CUSTOMERS

- **Ellie / Tim** — off-LAN they still get the neutral deferred message (guard sits below that
  check, deliberately). On their home LAN the sync now **leaves the controller untouched** and
  says so, instead of erasing slots 0-7. Their lights still won't come on until a schedule is
  converted to a clock time — that part is unchanged and by design.
- **Chris Cipollone** — his leases for 8/04-8/07 make `ins` non-empty, so his sync **still POSTs
  and still arms them**, which is the behavior the second test case pins. He is materially safer,
  **but see the residual below before telling him he is clear.**

**Residual, logged as P0-9, NOT fixed:** lease timers live in general slots 0-7 and the
`macro 26-41` range is a preset-id convention, not a slot reservation. The only protection is the
same-write merge from a **device-local SharedPreferences ledger**. A sync run while that ledger is
cold — after a reinstall, a cleared cache, on a second device, or before it loads — still drops
live leases, and this guard does not catch that (the payload has real timers, so it POSTs). It is
also structurally unverifiable from Firestore *or* the bench, because the authoritative lease
record exists only on the handset.

---

## FILES CHANGED

```
lib/features/schedule/schedule_sync.dart                        guard + refusedCount + predicate
lib/features/schedule/my_schedule_page.dart                     surface warnings on failure results
test/features/schedule/schedule_all_stub_clobber_guard_test.dart   NEW — 11 cases
docs/BUGS_AND_DEBT.md                                           P0-9 logged (lease slot exposure)
```
