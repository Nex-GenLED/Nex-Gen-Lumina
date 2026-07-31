# P0-6 — Controller migration failure surfacing

**Date:** 2026-07-31
**Scope:** `lib/` only. `firestore.rules` untouched. No branches.
**Files:** `lib/features/installer/installer_setup_wizard.dart`,
`lib/features/installer/staff_auth_telemetry.dart`,
`test/features/installer/controller_migration_failure_test.dart` (new).

The last silent link in the commissioning chain. `migrateInstallerControllersToCustomer`
wrapped its entire body in `try { … } catch (e) { debugPrint('…(non-blocking)'); }`, so a
denied or dropped migration returned normally, the wizard showed the handoff screen, and the
installer drove away from a customer whose app would be empty on first login.

---

## Design questions, answered before the code

### 1. Is the migration idempotent and safely retryable? **Yes — confirmed, not assumed.**

**"Delete succeeded but set did not" cannot happen.** All the writes live in a single
`WriteBatch`, and `WriteBatch.commit()` is atomic: every write in the batch applies, or none
does. There is no interleaving in which the source delete lands without the destination set.
That is a property of the batch, not of the ordering of the `batch.set` / `batch.delete`
calls in the loop.

Confirmed by test rather than by reading the docs — after a forced commit failure:

```
source      /users/staff_installer_0101/controllers  ->  ['ctrlA']   (intact)
destination /users/CUST_A/controllers                ->  []          (nothing half-written)
```

So the two failure states are:

| Outcome | State afterwards | Retry behaviour |
|---|---|---|
| Commit rejected (rules denial, offline) | source intact, destination empty | re-reads and re-commits — **succeeds** |
| Commit applied but the **client** timed out | source drained, destination populated | source read comes back empty → returns `skipReason: 'source-empty'` — **harmless no-op**, not an error |

The second row is the genuinely ambiguous case and it is the one that would have made a naive
"just rethrow and retry" loop wrong: a retry after a landed commit must not error or
duplicate. It returns a skip result instead, and the wizard proceeds. Both directions are
pinned by tests.

**Bound worth knowing (not a defect today):** a batch is capped at 500 operations, and this
migration costs 2 ops per controller plus 2 per pixelMap channel doc. A 1-controller,
8-channel install is 18 ops. It would take roughly 124 pixelMap docs to reach the cap — far
beyond any current install, but it is a hard ceiling rather than a soft one, so it is written
down here.

**One pre-existing non-atomicity, unchanged:** the source reads (`sourceCol.get()` and each
`pixelMap.get()`) happen *before* the batch and are not part of it. If something mutated the
source between read and commit, stale data could be copied. Not a partial-write risk, not
introduced here, and not addressed here.

### 2. Correct behaviour on failure: **retry in place.**

The failure happens after `createUserWithEmailAndPassword`, so a real customer account
already exists with no controllers on it. Options considered:

| Option | Verdict |
|---|---|
| **Retry in place** | ✅ **Chosen.** The realistic cause is a driveway with no signal, and the installer is still standing there with the hardware — Retry fixes it on the spot. Nothing has been lost at that moment: the controllers are still under the installer's uid. |
| Complete setup, flag the account as needing migration | ❌ The flag would have to be **written through the same Firestore that just failed**, and there is no repair job to consume it. That is the original defect with extra steps and a longer delay before anyone notices. |
| Roll back the customer account | ❌ Deleting a just-created auth user from the client is several non-atomic steps that can themselves half-fail — and the password-reset email has *already* been sent, so the customer may have a live reset link for an account being deleted underneath them. Strictly worse than an honest failure. |

On decline the install is reported as **failed**, because it did fail — the customer has no
lights. That is the whole point of the fix.

### 3. Reuse of the existing machinery

`_migrateControllersWithRetry` is deliberately the same shape as
`_restoreInstallerAuthWithRetry` from the token-refresh work: same position in the flow, same
`while (true)` + Retry/Stop `AlertDialog`, same contract that **Stop rethrows into the outer
catch**. It relies on the existing `installCommitted` / `classifyInstallError` machinery
rather than adding a parallel one — the migration runs before `installCommitted = true`, so
the rethrow lands as `InstallErrorOutcome.reportFailure` and the existing
`_showError('Setup failed: $e')` surfaces the specific cause.

No second failure UX was invented.

---

## What changed

**1. The swallow is gone.** `migrateInstallerControllersToCustomer` no longer catches. A
commit failure propagates to the only place that can do something about it.

**2. It returns a result instead of `void`** — `ControllerMigrationResult` with
`controllers`, `pixelMapDocs`, and a `skipReason` (`no-source-uid`, `same-uid`,
`source-empty`, `no-match`). Failure is *not* a result value; it throws. This is what lets a
retry distinguish "already migrated" from "there was never anything to migrate", and it makes
the success log say what actually moved.

**3. The call site gates on it.** `_migrateControllersWithRetry` logs the exception with the
full context (`from`, `to`, selected count, stack), records telemetry, and shows a blocking
dialog — *"Controllers didn't transfer"* — naming the cause and stating plainly that stopping
means the customer signs in to an app with no lights, and that nothing has been lost yet.
**Retry** re-attempts; **Stop** rethrows.

**4. A durable record.** `recordCommissioningFailure` writes to the same `/demo_analytics`
sink built for the anon-fallback telemetry, under a distinct
`event_type: 'installer_commissioning_failure'` so the S-5 adoption count is not polluted.
Rationale: the installer is told, but if they tap Stop and drive away the only trace was a
`debugPrint` on a phone nobody will read. This makes "a customer was left without
controllers" answerable from the console. Same never-load-bearing contract — every error
swallowed, 5s timeout, cannot block or fail an install.

Console query:

> Firestore → Data → `demo_analytics` → Filter `event_type` `==`
> `installer_commissioning_failure`

Fields: `stage`, `reason`, `customer_uid`, `source_uid`, `device_id`, `app_version`,
`created_at`.

---

## Verification

### 1. Forced migration failure ✅

Stubbed the batch to throw `permission-denied` (`_ThrowingBatch` / `_CommitFailsFirestore` —
reads work normally, only `commit()` explodes; this reproduces exactly what a P0-5-style
rules denial did).

| Assertion | Result |
|---|---|
| The call **throws** instead of returning normally | ✅ |
| The thrown error carries the **specific cause** (`permission-denied`, "insufficient permissions") — this string is what reaches the dialog | ✅ |
| Source left **intact**, destination left **empty** | ✅ |
| A retry then completes the migration (1 controller, 2 pixelMap docs) | ✅ |
| Declining reports **failure**: `classifyInstallError(installCommitted: false) == reportFailure` | ✅ |

### 2. Happy path unaffected ✅

The pre-existing `map_roofline_migration_test.dart` (4 tests covering the successful
migration, the pixelMap carry-along, the no-match case, and the same-uid no-op) passes
unchanged — the signature widened from `Future<void>` to
`Future<ControllerMigrationResult>`, which those call sites ignore, so nothing there needed
editing. No new prompt appears on success: the dialog is reachable only from the `catch`.

Also pinned explicitly: a retry after a commit that already landed returns
`skipReason: 'source-empty'` and leaves the customer's data untouched — no duplicate, no
error, no dialog.

### 3. Full suite

`flutter test` → **1857 pass · 3 skip · 1 fail.**

1850 → 1857 is exactly the 7 new tests. The single failure is
`test/features/ai/cloud_ai_processor_normalize_test.dart` — pre-existing, in
`lib/features/ai/`, which this change does not touch. It was proven pre-existing by
stash-and-rerun two sessions ago and is tracked as **P1-8**; the count matches the expected
1850/3/1 baseline plus the new tests, so no re-stash was needed to explain a discrepancy.

`flutter analyze` on both changed files: **No issues found.**

---

## Honest gap

**The dialog itself is not widget-tested.** It lives inside `_migrateControllersWithRetry`,
reachable only through `_completeSetup`, which calls
`FirebaseAuth.instance.createUserWithEmailAndPassword` directly. The project has no
`firebase_auth_mocks` / `mocktail` / `mockito` dependency, so that method cannot be driven
from a test without either adding a mocking package or refactoring the auth call behind an
injectable seam — both out of scope for a release candidate.

What *is* pinned is the mechanism the decline path depends on, in two halves that compose:
the migration **throws** (test 1), and a pre-commit throw **classifies as `reportFailure`**
(test 7). The remaining unpinned link is the single line `if (retry != true) rethrow;`.

This matches the existing `_restoreInstallerAuthWithRetry`, which is also not widget-tested
for the same reason. P0-7's dialog *was* widget-testable only because `map_roofline_step`
has no auth dependency.

Worth closing later by putting the auth call behind an injectable interface — that one seam
would make every post-account-creation failure path testable. Not done here.

---

## Not done

- **`firestore.rules`** — untouched, as instructed.
- **The auth seam / widget test for this dialog** — see above.
- **P3-61** (aborting after account creation is unrecoverable in-app: the auth user exists
  but `/users/{uid}` does not, so re-running hits `email-already-in-use` and the recovery
  query finds nothing) now applies to this decline path too. Still open, still the right fix
  — recover by uid when the account exists but the user doc does not.
