# Schedules Subcollection — Rollout Runbook

Ordered, gated sequence to take the `/users/{uid}/schedules` subcollection from
"code-complete, flag OFF" to "fleet-wide source of truth." Execute top-to-bottom;
do not skip a gate.

**Nothing auto-deploys.** Firestore rules, Cloud Functions, and the app release
are each a separate manual step. The flag defaults FALSE and only a manual
console edit turns it on.

**Rollback at any point = flip `config/schedules_subcollection.enabled` back to
`false`.** Because the app dual-writes (every subcollection mutation mirrors to
the legacy array and vice-versa), the array is always current, so a rollback
reads the array with **zero data loss**. This is the safety net for every step
below.

---

## Founder-side prerequisites (already tracked)

- The `config/schedules_subcollection` flag doc must be **created in the console
  with `enabled:false`** BEFORE the release ships, so the eventual activation is
  an *edit*, not a *create* (no client bootstraps it — the bootstrap writer in
  `schedules_subcollection_feature_flag.dart` is intentionally never called).
- `sync_fanout` is a **different, unrelated** flag (neighborhood sync) — ignore
  it here.

---

## Ordered sequence

### (a) Emulator rules + function suites — LOCAL, green — **[HARD GATE]**
The Firestore rules tests and Cloud Function integration tests
(`functions/test/emulator/schedulesRules.emulator.test.ts`,
`scheduleFunctions.emulator.test.ts`) are **written but NOT executed** in the
dev sandbox (no emulator, no `@firebase/rules-unit-testing`). They MUST be run
green locally before any deploy:
```
cd functions
npm i -D @firebase/rules-unit-testing ts-jest @types/jest
firebase emulators:exec --only firestore "npx jest --config jest.emulator.config.js"
```
Do not proceed past (a) until these pass. This gate covers: owner-only
`/schedules` access, a different uid DENIED (parent broad grant not inherited),
unauthenticated denied, flag-doc readable, backfill idempotency + dryRun-writes-
nothing, and `enforceScheduleLimits` trimming both shapes.

### (b) Create the flag doc
Console → Firestore → `config/schedules_subcollection` → `{ enabled: false }`.
(Create, not edit — so the later flip is a one-field edit.)

### (c) Deploy Firestore rules
```
firebase deploy --only firestore:rules
```
Adds the owner-only `/users/{uid}/schedules/{id}` rule and the flag-doc read
rule. Verify in console that both are live.

### (d) Deploy the Cloud Functions
```
cd functions && npm run build
firebase deploy --only functions:enforceScheduleLimits,functions:backfillSchedulesSubcollection
```

### (e) Backfill — DRY RUN
Invoke `backfillSchedulesSubcollection({ dryRun: true })` (console or shell).
Review per-user counts, `newDocIds`, and the `sortKeyAssignments` (index→sortKey)
diffs. Confirm the numbers match expectations; writes nothing.

### (f) Backfill — REAL
Invoke `backfillSchedulesSubcollection({ dryRun: false })`. Idempotent — a rerun
never renumbers (existing `sortKey` preserved). Confirms `schedulesMigratedAt`
stamped per user.

### (g) Ship the app release, flag OFF
Release the build carrying A-5 (read-flip + lazy migrator, commit `043ffb3`).
Flag is OFF ⇒ every client still reads/writes the legacy array — **no behavior
change ships to users.** This just puts the ON-capable code in the field.

### (h) Flip the flag on the founder account ONLY
Rather than a global flip, first restrict activation to the founder's uid (e.g.
a temporary per-uid gate, or flip globally on a founder-only device/account) and
set `enabled:true` for that scope. The founder client now reads the subcollection
(migrating first if needed via the lazy migrator).

### (i) Bench-verify on REAL hardware
On the founder account against a real controller (e.g. bench `192.168.1.250`):
1. A schedule fires **end-to-end** (WLED timer arms and triggers).
2. A user with **>8 schedules** arms the **correct timer subset** (ordering
   equivalence — the capacity-8 selection must match legacy insertion order).
3. The **eviction sweep** clears a `disabledUntil` and re-arms.
Do not proceed until all three pass on hardware.

### (j) Staged fleet flip
Flip `enabled:true` in widening cohorts (e.g. 1% → 10% → 50% → 100%), watching
for divergence/errors between stages. **Rollback = set `enabled:false`** — the
dual-written array is current, so rollback loses zero data. Only after 100% is
stable and the CLEANUP_PLAN.md removal conditions hold do you begin dual-write
teardown.

---

## Post-rollout
Proceed to `CLEANUP_PLAN.md` ONLY after: flag ON fleet-wide + min app version ≥
A-5 release + 30 days of zero legacy-only writes.
