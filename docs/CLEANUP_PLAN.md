# Schedules Dual-Write Cleanup Plan

Status: **DEFERRED — do not start until the removal conditions below all hold.**

During the array→subcollection migration the app **dual-writes**: every schedule
mutation lands in both the legacy `schedules` array field on `/users/{uid}` and
the `/users/{uid}/schedules/{id}` subcollection (mirrored in both directions by
`schedule_store_sync.dart` `runMirror`). This plan retires the array once the
subcollection is the sole source of truth.

Do NOT delete the array field or the legacy code path opportunistically — the
array is the rollback surface (see ROLLOUT_RUNBOOK.md: rollback = flip the flag
OFF, which reads the still-current array with zero data loss).

---

## 1. Removal conditions (ALL must hold)

1. **Flag ON fleet-wide.** `config/schedules_subcollection.enabled == true` for
   the whole fleet, observed stable (no per-cohort gating remaining).
2. **Min app version ≥ the release carrying A-5** (the read-flip + lazy
   migrator, commit `043ffb3`). Enforce a hard min-version gate so no
   pre-A-5 client — which reads/writes ONLY the array and is unaware of the
   subcollection — is still active. A single legacy-only writer would silently
   diverge the two shapes the moment the array is deleted.
3. **30 days of zero legacy-only writes observed.** Telemetry must show every
   schedule write in the trailing 30 days came from a subcollection-aware client
   (i.e. also produced a subcollection doc / carried `sortKey`). Concretely:
   no `/users/{uid}` write that mutates `schedules` without a matching
   subcollection mutation, and no user doc still lacking `schedulesMigratedAt`.

Only when 1–3 hold is the array field dead weight.

---

## 2. Array-field deletion script (dry-run FIRST)

The array is removed per-user with `FieldValue.delete()`, gated on proven
convergence. **Never delete on the first pass** — dry-run, review, then execute.

Enumerate migrated users via the subcollection using a collection-group query
(every migrated user has ≥1 doc under a `schedules` subcollection):

```js
// DRY-RUN — writes nothing. Reports, per user, whether the array and the
// subcollection have converged so deletion is safe.
const migratedUserRefs = new Set();
const cg = await db.collectionGroup('schedules').get(); // /users/*/schedules/*
for (const doc of cg.docs) {
  // parent = the `schedules` collection; parent.parent = the user doc.
  const userRef = doc.ref.parent.parent;
  if (userRef && userRef.parent.id === 'users') migratedUserRefs.add(userRef.path);
}

for (const path of migratedUserRefs) {
  const userSnap = await db.doc(path).get();
  const arr = Array.isArray(userSnap.get('schedules')) ? userSnap.get('schedules') : [];
  const subCount = (await db.doc(path).collection('schedules').get()).size;
  const migratedAt = userSnap.get('schedulesMigratedAt');
  const converged = migratedAt != null && arr.length === subCount;
  console.log(`${path}: array=${arr.length} sub=${subCount} migrated=${!!migratedAt} SAFE=${converged}`);
}
```

Real deletion (second pass, only after the dry-run shows `SAFE=true` for all,
and conditions 1–3 hold) — batched, guarded:

```js
// For each SAFE user: userRef.update({ schedules: admin.firestore.FieldValue.delete() });
// Skip any user where migratedAt == null OR array.length !== subCount.
```

Ship the script as a callable admin function (mirror `backfillSchedulesSubcollection`:
`admin` custom claim, `dryRun` param default true, paged, progress logs).

---

## 3. Deferred helper consolidation (post-cutover only)

Once the array + legacy path are gone, remove the now-redundant machinery:

- **`LegacyArrayScheduleRepository`** — delete. With it, the array primitives in
  `schedule_store_sync.dart` (`applyArrayTxn`, `overwriteArray`,
  `decodeScheduleArray`, and the array-side of `runMirror`) become dead; keep
  only the subcollection primitives.
- **Duplicated `_writeWithRetry`** — one copy in `LegacyArrayScheduleRepository`,
  one in `UserService` (still used by `saveCalendarEntries`). After the legacy
  repo is deleted, keep the `UserService` copy (or hoist to a shared util) and
  drop the duplicate.
- **`verifyServerWrite` dedupe** — `UserService.verifyServerWrite` is already an
  unused read-only leftover (the delegated `saveSchedules` no longer calls it;
  `LegacyArrayScheduleRepository._verifyServerWrite` is the live copy). Delete
  the `UserService` one at cutover.
- **Feature flag** — `schedules_subcollection` flag, `scheduleRepositoryProvider`
  branch, and `ScheduleLazyMigrator` (+ its in-flight lock + marker seam) all
  become unconditional; collapse `userSchedulesStreamProvider` to read the
  subcollection directly and delete the flag doc + rule.
- **`enforceScheduleLimits`** — retire the array-trim half; the cap becomes a
  subcollection doc-count check (or is dropped if the 50-cap moves entirely to
  the client). Its transaction over the array field is meaningless once the
  array is gone.
- **`migrateClearScheduleItemsV1`** — already RETIRED (do-not-run header);
  delete outright at cutover.
- **`user_model.toJson` `schedules` field** — stop serializing it (the A-5
  coherence-pin comment marks exactly this line); drop the array from the model.
- **`sortKey` stays** — it is the subcollection's ordering key, not dual-write
  scaffolding. Keep it.

Track each as its own small PR after the deletion script completes fleet-wide.
