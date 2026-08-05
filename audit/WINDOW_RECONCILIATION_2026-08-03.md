# TWO-WINDOW RECONCILIATION — 2026-08-03

**Read-only.** Nothing committed, built, or resolved. Establishes what actually shipped across
`c5c7baf` (+61) and `43e85c8` (+62).

---

## 0. HEADLINE — there is no conflict, and nothing was lost

**The premise of the question ("is P0-9a in the build?") has a different answer depending on
*which* build, and both reports were correct when written.**

- **`c5c7baf` / +61** — P0-9a is **entirely absent**. Suite was **1867**.
- **`43e85c8` / +62** — P0-9a **fully present**, landed as its own build on top of `c0ebe36`.
  Suite is **1878**.

The +62 work did **not** overwrite the +61 work. Both survive in the same files, in the correct
order. Working tree is clean. `main` is in sync with `origin/main`. **No reconciliation action is
required.**

---

## 1. TEST COUNT — 1878, and the discrepancy is fully explained

Suite run just now on `main` @ `8326c47`:

```
1878 passed · 3 skipped · 1 failed
```

The single failure is the same pre-existing stale P1-8 assertion,
`cloud_ai_processor_normalize_test.dart` — *"typed coercion: garbage field values … → defaults, no
throw"* — re-confirmed by running that file alone (`+10 -1`). It pins behavior deliberately removed
by `b6ca2f1` and should be closed as stale, not fixed.

**1867 → 1878 is +11, and it reconciles:**

| Source | Cases |
|---|---|
| `schedule_sync_lease_tristate_test.dart` (**new** in `306f3d2`) | 8 |
| `calendar_entry_lease_manager_test.dart` (extended) | +3 |

The P0-9a report said "9 cases" for the tri-state file; the file contains **8** `test(` calls.
A one-case discrepancy in a prose summary, not a missing test — the arithmetic
(1867 + 8 + 3 = 1878) closes exactly against the observed total.

**So the earlier 1867 was not wrong, and it does not mean the tri-state work is missing.** It was
the true count at `c5c7baf`, which is the commit +61 was built from.

---

## 2. IS P0-9a IN THE BUILD? — per symbol, at both commits

| Symbol | `c5c7baf` (+61) | `HEAD` (+62) |
|---|---|---|
| `sealed LeaseLedgerState` | **ABSENT** | **PRESENT** |
| `LeaseLedgerLoading` | **ABSENT** | **PRESENT** |
| `LeaseLedgerEmpty` | **ABSENT** | **PRESENT** |
| `LeaseLedgerReady` | **ABSENT** | **PRESENT** |
| `_initialized` consulted in `activeLeaseTimers()` | **ABSENT** (see note) | **PRESENT** — `:1285 if (!_initialized) return const LeaseLedgerLoading();` |
| `deferredLeaseLedger` (schedule_sync) | **ABSENT** | **PRESENT** |
| `kScheduleLeaseLedgerNotice` | **ABSENT** | **PRESENT** |
| retry/backoff (schedule_providers) | **ABSENT** (see note) | **PRESENT** — `_kLeaseLedgerRetryDelays` |
| tri-state branch (my_schedule_page) | **ABSENT** | **PRESENT** |

> **Two false positives worth recording, because a naive grep gets them wrong.**
>
> 1. **`_initialized` greps PRESENT at `c5c7baf`** — the *field* existed and was set correctly; it
>    was read only by a `@visibleForTesting` getter. At `c5c7baf`, `activeLeaseTimers()` returns a
>    bare list and never consults it. Grepping the identifier cannot distinguish "declared" from
>    "consulted in production" — you must look inside the method.
> 2. **`retry` greps PRESENT in `schedule_providers.dart` at `c5c7baf`** — those are pre-existing
>    generic snackbar-retry strings (`_showSaveError`, `onPressed: retry`), unrelated to P0-9a. The
>    real marker is `_kLeaseLedgerRetryDelays`, which appears only at HEAD.

**Conclusion: P0-9a is NOT in `c5c7baf`/+61 and IS in `43e85c8`/+62.** That is expected — +62 was
cut deliberately as its own build on top of +61, not merged into it.

---

## 3. `my_schedule_page.dart` — BOTH change sets survive, ordering is correct

Both windows edited this file. Both sets are present at HEAD:

**+61 work (presetErrors text rendering) — intact:**
- `showScheduleWarningsDialog` defined at `:746`
- invoked from the `!success` branch at `:310` (the fix that keeps warnings alive through a failure
  result)
- invoked from the `hasPresetErrors` branch at `:337`
- status-row `InkWell` at `:903`

**+62 work (tri-state neutral branches) — intact, and ORDERED CORRECTLY:**

| Site | Branch chain (line numbers) |
|---|---|
| SnackBar | `verifying` 263 → `deferredOffLan` 273 → **`deferredLeaseLedger` 282** → `!success` 292 → `hasPresetErrors` 314 |
| Status row | `verifying` 816 → `deferredOffLan` 823 → **`deferredLeaseLedger` 829** → `!success` 839 → `hasPresetErrors` 854 |

**`deferredLeaseLedger` precedes `!success` at BOTH sites**, which is the ordering the question
flagged as load-bearing. A lease-ledger deferral therefore renders through its own neutral branch
and **cannot** fall through to the red failure branch.

This is the same ordering discipline the +61 guard needed against `deferredOffLan` — the deferral
states must all sit above `!success`, because each is a "nothing was attempted" outcome rather than
a failure, and the generic `!success` branch would otherwise mis-colour them.

---

## 4. WORKING TREE

```
CLEAN — nothing uncommitted, nothing untracked
main...origin/main   (in sync, nothing ahead or behind)
```

`my_schedule_page.dart` and `calendar_entry_lease_manager.dart` are **both clean**. There is
nothing uncommitted that could revert pushed work if committed.

The two files I flagged as "modified by the parallel session" at the end of the +61 closeout were
that session's in-flight edits; they have since been committed as `306f3d2` and pushed. The
`audit/LEASE_LEDGER_MIGRATION.md` I deliberately left untracked is also gone from the untracked
list — folded into the +62 work.

---

## 5. WHAT IS NEEDED — nothing, and +61 should NOT be rebuilt

**P0-9a does not need landing on top of `c5c7baf`. It is already on `main` as its own build.**

**Do not rebuild +61.** Two reasons:

1. **versionCode 61 is consumed.** It was built, merged, pushed, and ledgered, and its AAB is
   preserved on disk as `versionCode61-816aa1b-solar-and-clobber-guard.aab.bak`. Rebuilding "+61"
   with different contents would make the pushed +61 ledger row describe code it does not contain —
   exactly the drift the ledger exists to prevent. This is why the later request for "+61" correctly
   became **+62**.
2. **+62 supersedes it.** `43e85c8` contains everything in +61 plus the tri-state gate. The +62 AAB
   (`versionCode 62`, 68,239,152 bytes, built 13:33) is the artifact to upload.

**Upload +62, not +61.** The +61 AAB should be retained only as the archived `.bak` for SHA
traceability.

---

## 6. RESIDUAL — what this reconciliation does NOT settle

- **P0-9b** (ledger durability across reinstall / second device) and **P0-9c**
  (`_kLeaseStorageKey` not uid-namespaced) remain **OPEN**. +62 closed part (a) only — the
  cold-ledger *within a session*. Chris Cipollone's reinstall/second-device exposure is **not**
  closed by +62.
- **Solar is still OFF fleetwide.** Neither build creates `config/solar_scheduling`; it has never
  existed in either Firebase project.
- **The solar comparator still does not exist** — `isRealEnabledTimer` excludes `hour == 255`, so
  solar rows verify clean regardless of whether they landed. The flag flip stays blocked on it.
- **Hardware verification still owed on +60, +61 and +62**: token refresh 4.2, commissioning a-d,
  Part B.
- **controller_ips rules**: steps 1-5 complete, 24h soak pending, rule **NOT deployed**. Order
  remains backfill → soak → rule.
- **P1-8** still red as a stale assertion.
