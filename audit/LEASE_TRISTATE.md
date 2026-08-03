# P0-9 (part a) — TRI-STATE LEASE LOADING GATE

**Status: IMPLEMENTED and BENCH-VERIFIED end-to-end.** · **Date:** 2026-08-03 · **Launch build.**
**Scope:** `lib/features/schedule/` + tests. No Firestore, no schema, no flag, no rules, no branch.
**Bench:** 192.168.1.150, WLED 0.15.1, vid 2507300, 290 LEDs — real `syncAll` against the real
controller. Rig restored to baseline and verified.

---

## 1. What was broken

`activeLeaseTimers()` returned a bare `List`. Two opposite situations shared one representation:

| Situation | Returned | Correct response |
|---|---|---|
| this account has no leases | `[]` | merge nothing and **write** (clear the device) |
| the ledger hasn't loaded yet | `[]` | **don't write at all** |

Because `calendarEntryLeaseManagerProvider` calls `manager.initialize()` fire-and-forget
(`// ignore: unawaited_futures`) and `activeLeaseTimers()` read `_activeLeases` synchronously with
no guard, a schedule sync genuinely races the load. It then emitted a payload containing real
schedule timers and **no lease timers**, `padTimersToMax` stubbed the lease slots, and the
controller lost every live lease — silently, and self-concealing: gone from the device *and* from
the ledger that would have restored it.

`_initialized` already tracked exactly this. It was declared at :407, set at :467, and read **only
by a `@visibleForTesting` getter**. Nothing production-side consulted it. That was the bug.

`shouldSkipClobberingWrite` does not cover this and was not touched: it fires only when the payload
carries no enabled entry, and a partial-arm payload is full of real timers.

---

## 2. The change

### 2.1 A sealed tri-state, not a nullable list — and why

```dart
sealed class LeaseLedgerState { List<Map<String, dynamic>> get timers => const []; }
class LeaseLedgerLoading extends LeaseLedgerState {}   // UNKNOWN — refuse to write
class LeaseLedgerEmpty   extends LeaseLedgerState {}   // loaded, genuinely zero — WRITE
class LeaseLedgerReady   extends LeaseLedgerState {}   // loaded, has timers — MERGE and write
```

The defect was two meanings sharing one in-band encoding. Encoding "unknown" as `null` would be the
same mistake one step removed — a caller can still reach past it for the list. A **sealed hierarchy
makes Dart's exhaustiveness checking refuse to compile a caller that forgets the loading case**, so
the conflation cannot silently return. ~20 lines for a structural guarantee, on a P0 whose entire
cause was an implicit encoding.

Records were the alternative (this file already uses them for multi-value returns) but carry no such
enforcement. `Empty` and `Ready` are kept distinct rather than collapsed into `Ready(const [])` so
the debug log can say which one it was — "ledger empty" vs "ledger loading" is the first question
asked when a lease goes missing.

### 2.2 `_initialized` is now read in production

```dart
LeaseLedgerState activeLeaseTimers() {
  if (!_initialized) return const LeaseLedgerLoading();
  final ins = ...;
  return ins.isEmpty ? const LeaseLedgerEmpty() : LeaseLedgerReady(ins);
}
```

### 2.3 The same race, one level up — also closed

`calendarLeaseActiveTimersProvider` read `calendarLeaseLiveWritesEnabledSyncProvider`, whose doc
says *"an initial AsyncLoading state resolves to `false`"*. That collapse is correct for its other
caller (`_readLiveWritesEnabled` — never WRITE when unsure) but **wrong here**, where `false` means
"no leases to preserve" and licenses the clobbering write. While the flag doc is still loading the
lease set is unknown, so the provider now reads the **stream** and maps `loading`/`error` to
`LeaseLedgerLoading`.

The sync adapter itself was left alone — changing it would alter behaviour for callers that
correctly want defensive-false.

### 2.4 `syncAll` refuses

Placed **below** the off-LAN check (so `deferredOffLan` keeps its neutral copy — the ordering lesson
already paid for by `schedule_sync_off_lan_test`) and **above** the clobber guard (stricter refusal
first; when both apply neither writes, so safety is unaffected).

A lease-read **throw** now also maps to Loading. The old catch proceeded "schedule-only", which is
the clobber under another name — "never let a lease-read error break a schedule sync" was trading a
deferred sync for silent data loss.

The gate keys on `leaseState is LeaseLedgerLoading`, **never** on `leaseTimers.isEmpty` — a loaded
empty ledger must still write, exactly as a hydrated user with zero schedules does.

### 2.5 Legibility — and why a retry, not just a message

The brief asked whether the user needs to see this at all if the next sync succeeds, and not to
default to silence. Both were considered, and the answer is **both a surface and a retry**:

- **Surfaced**, mirroring the shipped `deferredNotLoaded` precedent: a neutral cyan status row
  (never red — nothing failed and the controller was left untouched on purpose), and a neutral
  snackbar on the manual Sync path so it can't fall through to the red failure branch. Copy:
  *"Saved — finishing up on your controller. This clears in a moment."* Deliberately no mention of
  "leases" — the word means nothing to a customer.
- **Retried**, because a refusal with no retry *is* silent. The schedule saves to Firestore, nothing
  reaches the controller, and the status row clears on the next rebuild — the exact
  "success reported for work not done" shape this codebase already has too many instances of. The
  refusal must be followed by something, and a retry is the better answer because the user never has
  to act.

Bounded at three attempts on a widening backoff (1200 / 2500 / 5000 ms), then it stops and the
deferral stays visible. Widening because the ledger can be waiting on a fast prefs read *or* the
flag doc's first Firestore emission, which is slow on a first-ever launch and instant from cache
after. A single short retry would burn its one attempt against a cold Firestore and leave the
schedule unarmed with nothing further scheduled.

### 2.6 Files touched

| File | Change |
|---|---|
| `calendar_entry_lease_manager.dart` | sealed `LeaseLedgerState`; `activeLeaseTimers()` returns it and consults `_initialized`; provider reads the flag STREAM |
| `schedule_sync.dart` | consume the tri-state; refuse on Loading; `deferredLeaseLedger` + factory + `kScheduleLeaseLedgerNotice` |
| `schedule_providers.dart` | bounded retry + backoff constant + timer disposal |
| `my_schedule_page.dart` | neutral status-row branch + neutral snackbar branch |

No refactoring. `shouldSkipClobberingWrite` untouched.

---

## 3. BENCH VERIFICATION — 192.168.1.150

Method: a temporary `flutter test` harness driving the **real** `ScheduleSyncService.syncAll` and a
**real** `WledService` over the network, varying only the tri-state. Full source kept out of the
release tree; reproduce from §3.5.

**Baseline captured before any change** (WLED compacts readback, dropping disabled stubs):

```
--- timers.ins BASELINE ---
  [0] en=1 hour=19 min=0  macro=26 dow=64      <== a lease-range timer
  [1] en=1 hour=255 min=0 macro=2  dow=127     <== solar sentinel
  REAL macros: [26, 2]
```

### 3.1 CASE 0 — the P0-9 reproduction (pre-fix behaviour)

The ledger reports **EMPTY** while a lease is armed. This *is* the old code path: pre-fix,
`activeLeaseTimers()` returned `[]` whenever the ledger was cold, which is indistinguishable from
Empty.

```
--- timers.ins CASE 0 BEFORE (2) ---
  [0] en=1 hour=19 min=10 macro=27 dow=16      <== THE LEASE
  [1] en=1 hour=255 min=0  macro=2  dow=127
  REAL macros: [27, 2]

result: success=true  deferredLeaseLedger=false  error=null

--- timers.ins CASE 0 AFTER (2) ---
  [0] en=1 hour=19 min=30 macro=10 dow=1
  [1] en=1 hour=255 min=0  macro=2  dow=127
  REAL macros: [10, 2]
```

**The lease is GONE.** Overwritten by the schedule timer, and the sync reported `success=true`.
This is P0-9 on real hardware.

### 3.2 CASE 1 — THE FIX

The ledger reports **LOADING** with the same lease armed.

```
--- timers.ins CASE 1 BEFORE (2) ---
  [0] en=1 hour=19 min=10 macro=27 dow=16      <== THE LEASE
  [1] en=1 hour=255 min=0  macro=2  dow=127
  REAL macros: [27, 2]

ScheduleSync: DEFERRED cfg write — the lease ledger has not loaded, so the active lease set is
UNKNOWN. Writing now would drop any live lease timers (macro 26-41) from the merged payload and
stub-clobber their slots. Controller left unchanged; the sync re-runs once the ledger is warm.

result: success=false  deferredLeaseLedger=true
        error=Saved — finishing up on your controller. This clears in a moment.

--- timers.ins CASE 1 AFTER (2) ---
  [0] en=1 hour=19 min=10 macro=27 dow=16      <== SURVIVED
  [1] en=1 hour=255 min=0  macro=2  dow=127
  REAL macros: [27, 2]
```

**Byte-identical before and after.** Not merely lease-preserving — the table is untouched, which is
the assertion (`after.length == before.length` plus macro presence). No cfg POST was made.

### 3.3 CASE 2 — a normal sync still works end to end

Ledger **READY** with the lease. This is the P0-3.2 path and it must be unaffected.

```
--- timers.ins CASE 2 BEFORE (2) ---
  REAL macros: [27, 2]

CfgVerify: cfg 2xx but readback unavailable (controller likely stalling) — verifying patiently,
           NOT trusting the 2xx
CfgVerify: controller stalled ~20s after the cfg commit; write VERIFIED on recovery
result: success=true  deferredLeaseLedger=false  presetErrors=[]

--- timers.ins CASE 2 AFTER (3) ---
  [0] en=1 hour=19 min=30 macro=10 dow=1       <== schedule armed
  [1] en=1 hour=19 min=10 macro=27 dow=16      <== lease preserved
  [2] en=1 hour=255 min=0  macro=2  dow=127    <== sentinel intact
  REAL macros: [10, 27, 2]
```

Both armed. Incidentally re-confirmed the post-commit stall (~20 s) and that the hardened verify
rides it out instead of false-reporting.

### 3.4 Rig restored

```
--- timers.ins RESTORED ---        --- timers.ins BASELINE ---
  [0] en=1 h=19 m=0 macro=26 dow=64    [0] en=1 h=19 m=0 macro=26 dow=64
  [1] en=1 h=255 m=0 macro=2 dow=127   [1] en=1 h=255 m=0 macro=2 dow=127
  REAL macros: [26, 2]                 REAL macros: [26, 2]
```

Identical. **One residual change disclosed:** the bench runs psaved preset **10**
(`"Pattern: P09 Bench"`), overwriting whatever it held. Preset 10 is a schedule-pattern slot that
the always-psave design rewrites on every sync anyway, so this is normal bench churn rather than
damage — but it was not restored to its prior contents, because those were not captured first. Flag
if that slot mattered.

### 3.5 Reproducing

The harness lived at `test/bench_p09_live_test.dart` and was **deleted** — it makes real network
calls and does not belong in a release tree. To rebuild it: a `flutter test` file with
`TestWidgetsFlutterBinding.ensureInitialized()`, then **`HttpOverrides.global = null`** (the test
binding otherwise stubs every request to 400), `SharedPreferences.setMockInitialValues({})` (because
`WledService.applyJson` reaches prefs via the neighborhood participation cache), and a
`ProviderContainer` overriding `wledRepositoryProvider` with `WledService('http://192.168.1.150')`
and `calendarLeaseActiveTimersProvider` with each of the three states in turn.

---

## 4. Unit tests

**New — `test/features/schedule/schedule_sync_lease_tristate_test.dart` (9 cases):**

- LOADING → `applyConfigCalls == 0`, `lastCfg` null, `deferredLeaseLedger`, `success == false`
- LOADING → the refusal carries the neutral notice (legibility is asserted, not assumed)
- LOADING **with two cleanly-armable schedules** → still refuses. This is the case
  `shouldSkipClobberingWrite` cannot catch, asserted explicitly so nobody later concludes the
  sibling guard covers it.
- **EMPTY → DOES write** (`applyConfigCalls == 1`, schedule macro present) — *the regression the
  brief called out as most likely, asserted directly*
- **EMPTY with zero schedules → still writes** (slot reclaim). If the gate had keyed on "no lease
  timers" instead of "ledger loading", this would be refused and stale timers would strand forever.
- READY → writes and preserves the lease (P0-3.2 unchanged)
- the tri-state itself: Loading and Empty are distinct types that both expose no timers

**New — 3 cases in `calendar_entry_lease_manager_test.dart`**, against the **real** manager:

- before `initialize()` → `LeaseLedgerLoading`, `isInitializedForTest == false` (the race at source)
- after `initialize()` with zero leases → `LeaseLedgerEmpty`
- after `initialize()` with a rehydrated lease → `LeaseLedgerReady`, macro ≥ 26

---

## 5. Test suite

**1878 pass / 3 skipped / 1 fail.** The single failure is the expected pre-existing stale
`cloud_ai_processor_normalize` case. The count matches expectation, so no stash comparison was
needed.

`flutter analyze` on all nine changed files: **0 errors, 0 new warnings.** The 8 remaining infos are
pre-existing `deprecated_member_use` in untouched regions of `my_schedule_page.dart`.

### Five other tests broke first, and that was informative

An intermediate run showed 6 real failures. Five were mine, and they were not noise:

- `schedule_sync_idempotent_test` ×4 — these containers never overrode the lease provider, so they
  had been relying on the flag adapter's loading window collapsing to `false`. That is **an
  accidental resolution of the exact race being closed here.** Fixed by declaring
  `LeaseLedgerEmpty` explicitly, which also documents which lease state each suite exercises.
- `sunrise_off_preserve_test` — compile error: it overrode the provider with a raw `List`. The
  sealed type caught it at build time, which is the enforcement argued for in §2.1 doing its job on
  the very first commit.

`schedule_sync_off_lan_test` and `schedule_sync_hydration_guard_test` pass untouched — both return
before the new gate, confirming the ordering in §2.4.

---

## 6. Logged, not implemented

**`_kLeaseStorageKey` is not uid-namespaced** (`calendar_entry_lease_manager.dart:74`). A single
global key `'calendar_leases_v1'`: sign out of account A and into B on the same handset and B
rehydrates **A's** leases, merging A's slot/preset numbers into B's cfg writes — arming timers
against presets B never saved and occupying slots B's own leases need. Real, separate, most likely
to bite installers and demo devices. Fixed incidentally by part (b) (the Firestore path is
uid-scoped by construction). Filed as **P0-9c** in `docs/BUGS_AND_DEBT.md`.

---

## 7. What this does and does not close

**Closes:** the cold-ledger *timing* race — the sync that runs before the ledger loads, which was
the live weekly exposure (Taps On Main 6 in-window entries, Chris Cipollone 4, Tyler 2, with
`config/calendar_leases.liveWritesEnabled = true`). Also closes the same race at the feature-flag
level.

**Does not close:** ledger *durability*. Reinstall, cleared cache, or a second device still start
from an empty ledger — which now correctly reports `Empty`, because it genuinely finished loading
nothing. Part (a) cannot distinguish "loaded, empty" from "loaded, empty because the data lives on
another phone." **Only part (b) can** — see `audit/LEASE_LEDGER_MIGRATION.md`, still design-only and
still fast-follow.
