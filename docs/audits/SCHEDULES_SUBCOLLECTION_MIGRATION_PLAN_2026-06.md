# #TD-1 — Schedules → Subcollection Migration Plan

> **STATUS: PLAN ONLY — not started.** Gated on: current bridge-fix build
> (`e005a02` #52 + `1b7f25e` getState throttle) being field-verified via
> `_diag_timeout_split.js` re-run. Start at Step 0 (id scan) once unblocked.
> Ordering invariant: **rules → backfill → dual-write code.** Never point a read
> at the subcollection before it is populated and readable.

**Firmware impact:** none. The ESP32 bridge reads `/users/{uid}/commands`, never
`/schedules`. Conflict detection, sync, and the array all live app-side +
Firestore/Functions.

---

## Background — current state

- **Field:** `schedules`, an array on the user doc `/users/{uid}` (JSON key `'schedules'`).
- **Model:** `List<ScheduleItem>` in `lib/models/user_model.dart:230`; serialized in
  `toJson()` at `lib/models/user_model.dart:618` — **every full UserModel write
  re-emits the entire array** (the §3 side-channel clobber surface).
- **Entry shape** (`lib/features/schedule/schedule_models.dart`): `id` (stable unique,
  `final String`), `timeLabel`, `offTimeLabel?`, `repeatDays: List<String>`,
  `actionLabel`, `enabled`, `wledPayload: Map?` (JSON-encoded on write), `presetId?`,
  `useAudioReactive?`, `disabledUntil?` (lease soft-eviction), `sourcePromptId?`
  (compound-prompt provenance).
- **Bound:** soft cap **50**, enforced in `SchedulesNotifier.mergeWithDedup()`
  (`lib/features/schedule/schedule_providers.dart:569`, trims oldest) and server-side
  `enforceScheduleLimits` (Sun 19:00 UTC). The cap exists to keep the user doc bounded
  for read cost — i.e. the array growing the hot user doc is the reason this is HIGH debt.

### Why migrate now
Small fleet (<100 users) = cheap backfill + a short dual-write window. The migration
also **fixes a live concurrency bug** as a side effect (see §3 / Step 3): the
whole-array read-modify-write paths are eliminated when each schedule becomes its own doc.

### Blast-radius summary (from the audit)
- **Read side is contained:** the entire UI/business layer reads through
  `schedulesProvider`; only **two** `user_service.dart` methods actually touch Firestore
  (`streamSchedules`, `fetchSchedulesFromServer`).
- **Write side — clobber race (existing bug):**
  - `addSchedule` / `addSchedules` — atomic (`FieldValue.arrayUnion`). Safe.
  - `removeSchedule` (`user_service.dart:874`), `updateSchedule` (`:898`) — `.get()`
    then `.update({'schedules': ...})`, **wrapped only in `_writeWithRetry`, NOT a
    Firestore transaction.** Concurrent writers lose each other.
  - `saveSchedules` (`:811`) — blind whole-array overwrite. Called by `replaceAll()`
    and autopilot `mergeWithDedup()`. Most dangerous (a manual add landing mid-regen
    is dropped as "oldest").
  - Side channel: `updateUser(copyWith(...))` from `edit_profile_screen.dart:189/199`,
    `roofline_editor_screen.dart:594`, `house_photo_uploader.dart:88/150` re-emit the
    whole array via `toJson()`.
- **Conflict detection / finder / sync:** `ScheduleConflictDetector` and
  `ScheduleFinder` are pure/static and operate on an in-memory `List<ScheduleItem>`
  (+ a separate `calendar_entries` MAP field, NOT part of this migration). They are
  **unaffected as long as `schedulesProvider` keeps hydrating a list** — see the §5
  constraint.
- **Cloud Functions:** `sendWeeklyBrief` reads `autopilot_events`, **NOT** schedules
  (no change). The real server-side schedule readers are `enforceScheduleLimits` and
  `migrateClearScheduleItemsV1` (Step 5).

---

## Step 0 — PRE-FLIGHT: id integrity scan (read-only) — REQUIRED, run first

**Why:** the backfill keys each subcollection doc on `item.id`
(`set(.../schedules/{item.id})`). Correctness + idempotency require every id to be
**non-null, non-empty, and unique within each user's array**. A duplicate id silently
merges two schedules into one doc on backfill — one schedule vanishes (the §7
"schedules vanish" risk). Gate on this.

**Verdict:** keep as Step 0. Null-id is *unlikely* — the model's non-nullable
`json['id'] as String` cast would already crash `fromJson` for live users — so this
will most likely pass. The real targets are **empty-string ids** and **intra-user
duplicate ids**, neither of which the model prevents.

- **Form:** read-only admin callable Cloud Function OR a one-off `firebase firestore`
  script. **No writes.**
- **Logic:** iterate all `/users/*`; read `data.schedules`; collect ids; flag any user
  with (a) null/missing id, (b) empty-string id, (c) duplicate ids within the array.
  Log `{uid, scheduleCount, offendingIds}`. Final summary: `N scanned, M flagged`.
- **Verification:** `M == 0` → proceed to Step 1. `M > 0` → **remediation sub-task
  before backfill:** a one-shot that assigns fresh ids (`<uuid>`) to offending entries
  via the *existing* whole-array write path (`saveSchedules`), then re-run Step 0 until
  clean. Do this while schedules are still array-stored (cheap, single write per user).
- **Files:** new `functions/src/auditScheduleIds.ts` (scan) and, only if needed,
  `functions/src/fixScheduleIdsV1.ts` (remediation). No client changes.
- **Deploy:** `firebase deploy --only functions:auditScheduleIds`.

---

## Step 1 — Rules: add `/schedules/{scheduleId}` block

- **File:** `firestore.rules` — replace the comment at lines 217-219 ("Schedules are
  stored as an array field … No subcollection rules needed") with the block in §2.
- **Deploy:** `firebase deploy --only firestore:rules` — **rules are NOT auto-deployed.**
- **Verification:** after deploy, **confirm Enabled in the Firebase console** (per the
  invitations-index lesson — `firestore:rules` deploys can lag the live ruleset).
  Smoke: as owner, `set/get/delete` on `/users/{ownUid}/schedules/_probe` succeeds;
  cross-user read denied. Additive and harmless — nothing writes there yet.
- **Why first:** the subcollection must be readable/writable before anything populates it.

---

## Step 2 — Backfill (array → subcollection), idempotent

- **File:** new `functions/src/backfillSchedulesToSubcollectionV1.ts` (spec in §3).
  Admin callable, batched, re-runnable.
- **Deploy:** `firebase deploy --only functions:backfillSchedulesToSubcollectionV1`.
- **Run:** invoke once. **Does NOT delete the array.**
- **Verification:** returns `{usersProcessed, docsWritten, usersSkipped}`. Spot-check
  2-3 accounts: subcollection doc count == array length, content matches. Re-run once →
  `docsWritten` identical, **zero duplicates** (idempotency proof).

---

## Step 3 — Dual-write code (read from subcollection, write both)

- **Files:** `lib/services/user_service.dart` only (spec in §5). Repoint the two read
  methods to the subcollection; convert write methods to per-doc writes **while still
  mirroring to the array**. `schedulesProvider`, conflict detection, finder, sync —
  **untouched** (StreamProvider→`List<ScheduleItem>` shape preserved).
- **Deploy:** client release (TestFlight / internal track first).
- **Post-deploy:** **re-run Step 2 backfill** to sweep array writes made by lingering
  old-build clients during rollout.
- **Verification:** on a test account — create/edit/toggle/delete; confirm (a) UI
  updates live, (b) subcollection doc reflects it, (c) array mirror also reflects it,
  (d) conflict dialog + WLED sync still fire. Confirm an *old* build still reads schedules.

---

## Step 4 — Stop array writes (subcollection sole source)

- **Files:** `lib/services/user_service.dart` — drop the array-mirror writes from
  Step 3; reads already come from the subcollection. Remove the array from the
  `UserModel.toJson()` write path so `updateUser(copyWith(...))` no longer re-emits
  `schedules` (kills the §3 profile-write side-channel clobber). Keep `UserModel.schedules`
  field + `fromJson` parse for one release (back-compat read of any un-backfilled
  straggler), or drop if Step 2 verified 100%.
- **Deploy:** client release. **Gate:** only after Step 3 adoption is high enough that
  no meaningful population still reads the array (small fleet → short window).
- **Verification:** new writes appear ONLY in the subcollection; user-doc `schedules`
  stops changing. Conflict/finder/sync still green.

---

## Step 5 — Cloud Functions: migrate/retire array readers

- **Files:**
  - `functions/src/enforceScheduleLimits.ts` — switch from `data.schedules` array-trim
    to: count `.collection('schedules')` docs, batch-delete overflow beyond 50. (Or
    retire — per-doc storage removes the doc-bloat rationale; keep only for
    runaway-count hygiene.)
  - `functions/src/migrateClearScheduleItemsV1.ts` — now obsolete; supersede with a
    subcollection-aware clear if still needed for support wipes.
  - `sendWeeklyBrief.ts` — **no change** (reads `autopilot_events`, not schedules).
- **Deploy:** `firebase deploy --only functions:enforceScheduleLimits` (+ any new).
- **Verification:** trigger `enforceScheduleLimits` against a >50-schedule test account;
  confirm it deletes subcollection docs down to 50 and leaves the doc untouched.

---

## Step 6 — Cleanup: strip dead array field

- **Files:** new one-shot `functions/src/stripScheduleArrayV1.ts` —
  `update({schedules: FieldValue.delete()})` per user. Drop `schedules` from `UserModel`
  (field, `fromJson`, `toJson`, `copyWith`) in `lib/models/user_model.dart` and remove
  the back-compat parse left in Step 4.
- **Deploy:** function deploy + run; client release.
- **Gate:** only after Steps 3-5 verified stable for a full release cycle —
  **irreversible.**
- **Verification:** user docs no longer carry `schedules`; app reads exclusively from
  subcollection; full regression on schedule CRUD + autopilot regen + conflict + sync.

**Invariant across all steps:** rules (1) → backfill (2) → code (3). Never point a read
at the subcollection before it is populated *and* readable.

---

## §2 — Exact rule block (`firestore.rules`, replacing lines 217-219)

Matches the geofences/properties/roofline_config sibling pattern
(`read: canReadUserData(userId)`, `create/update/delete: isOwner(userId)`).

```
      // Schedules subcollection — recurring/one-off lighting automation.
      // Migrated from the array field on /users/{userId} (#TD-1). Mirrors
      // the geofences/properties pattern: owner-private writes, with
      // media/dealer/admin read visibility for content creation & support.
      // Bridge has no access (it executes /commands, never schedules);
      // no installer exception (installers don't author user schedules).
      match /schedules/{scheduleId} {
        // Owner + media/dealer/admin can read (support / content).
        allow read: if canReadUserData(userId);

        // Only the owner creates/edits/deletes their schedules.
        allow create: if isOwner(userId);
        allow update: if isOwner(userId);
        allow delete: if isOwner(userId);
      }
```

> ⚠️ Requires `firebase deploy --only firestore:rules` (not auto-deployed) **and a
> Firebase-console "Enabled" confirmation** before relying on it (deploys can lag the
> live ruleset).

---

## §3 — Backfill function SPEC (`backfillSchedulesToSubcollectionV1`)

**Type:** admin-gated callable (or scheduled one-shot). **Idempotent. Re-runnable.
Never deletes the array.**

**Per-user algorithm:**
```
for each doc in paginated iteration of /users:                   // e.g. 300/page
  data = userDoc.data()
  arr  = data['schedules']
  if arr is null OR empty:
      usersSkipped++; continue                                   // skip-empty
  batch = db.batch()
  for each entry in arr:
      id = entry['id']
      // Step-0 guarantees non-null/non-empty/unique; defensive re-check:
      if id missing/empty: log + collect to needsFix; skip entry
      ref = userDoc.ref.collection('schedules').doc(id)
      batch.set(ref, entry, { merge: true })                     // idempotent: keyed by stable id
      docsWritten++
  await batch.commit()                                           // <=500 ops/batch; chunk if larger
  usersProcessed++
log summary { usersProcessed, docsWritten, usersSkipped, needsFix[] }
return summary
```

**Properties:**
- **Idempotent** — `set(..., {merge:true})` keyed on the existing `id`; a second run
  overwrites identical content, **creates no duplicates**.
- **Logged counts** — per-user debug line + final aggregate summary (Step 2 verification
  artifact).
- **Skip-empty** — users with no array are counted and skipped, not written.
- **Non-destructive** — the `schedules` array is left intact; removal is Step 6 only.
- **Safe under live writes (§7 mitigation)** — run at low traffic; a racy array write
  mid-run converges on a re-run (after Step 3 ships), since the keyed `set` is
  order-independent. `needsFix[]` surfaces any entry Step 0 missed without aborting.

---

## §5 — Dual-write code change SPEC (`lib/services/user_service.dart`, Step 3)

**Hard constraint:** `schedulesProvider` stays a `StreamProvider<List<ScheduleItem>>`.
The stream still emits a fully-hydrated `List<ScheduleItem>` — so
`ScheduleConflictDetector`, `ScheduleFinder.findCurrentSchedule`, the conflict-check
notifier methods, and `ScheduleSyncService.syncAll` **remain synchronous and unchanged.**
We change *where the list comes from*, not its shape.

**Read methods — repoint source:**
- `streamSchedules(uid)` (`:922`) →
  `.collection('users').doc(uid).collection('schedules').snapshots().map((qs) =>
  qs.docs.map((d) => ScheduleItem.fromJson(d.data())).toList())`. Still returns
  `Stream<List<ScheduleItem>>` — provider shape preserved. (Optional: a stable
  `orderBy` for deterministic ordering, since array insertion order is lost.)
- `fetchSchedulesFromServer(uid)` (`:792`) → `.collection('schedules').get(
  GetOptions(source: server))` → map docs to list. Boot persistence-verify
  (`lib/main.dart:304`) keeps working unchanged.

**Write methods — per-doc, mirror to array during Step 3:**

| Method | New per-doc write | Array mirror (Step 3 only) |
|---|---|---|
| `addSchedule` (`:833`) | `.collection('schedules').doc(item.id).set(item.toJson())` | keep `arrayUnion` |
| `addSchedules` (`:856`) | batched per-doc `set` | keep `arrayUnion` |
| `updateSchedule` (`:898`) | `.doc(item.id).set(item.toJson(), merge:true)` — **no read-modify-write** | mirror via existing path |
| `removeSchedule` (`:874`) | `.doc(scheduleId).delete()` — **no get-then-update** | mirror |
| `saveSchedules` (`:811`) (replaceAll / autopilot mergeWithDedup) | batch: delete-absent + `set` present | mirror full array |

**The win:** `updateSchedule`/`removeSchedule` stop doing the non-transactional
`.get()`→`.update()` whole-array rewrite, and `saveSchedules` stops blind-overwriting —
**the live clobber-race class is eliminated** the moment per-doc writes land, because
each schedule is now an independent document with an independent write. The array mirror
in Step 3 still rewrites the whole array (clobber persists *on the mirror only*), which
is why Step 4 removes the mirror promptly. At Step 4, also drop `schedules` from
`UserModel.toJson()` so profile/roofline/photo `updateUser` writes stop re-emitting it
(the side-channel clobber).

---

## Top risk (carried from the audit §7)

**Most dangerous part: the backfill racing live writes during cutover** — specifically
against the existing whole-array clobber paths (`saveSchedules` / autopilot
`mergeWithDedup`). Mitigations: keyed-by-`id` idempotent `set(merge)` (re-run
converges), run backfill at low traffic, and **re-run after the dual-write build ships**
so the final state reflects per-doc writes. Secondary risk — "schedules vanish because a
read path wasn't migrated" — is **low** (read side contained to two `user_service`
methods behind `schedulesProvider`; a miss shows empty lists immediately in testing, not
silent loss). **Thesis confirmed: migrating now (<100 users) is materially cheaper and
safer than at 100+, and it deletes the live whole-array clobber-race class as a bonus.**
