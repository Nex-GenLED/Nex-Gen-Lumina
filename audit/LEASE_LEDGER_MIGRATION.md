# P0-9 — LEASE LEDGER TO FIRESTORE

**Design document. Nothing implemented, no branch created, `firestore.rules` untouched.**
**Date:** 2026-08-03 · **Track:** fast-follow (iOS submits ~Aug 11-18 — **not launch scope**)
**Grounded against:** `calendar_entry_lease_manager.dart` (1441 lines), `schedules_subcollection_feature_flag.dart`,
`schedule_sync.dart` working tree, and live Firestore reads via gcloud ADC.

---

## 0. THE AUTHORITY MODEL — answered first, because it changes the design

### Your prior is right, and it is not sufficient

> *the DEVICE is truth for what is armed, Firestore is truth for what SHOULD be armed, and the local cache is
> non-authoritative*

**Confirmed on all three counts.** I'd keep that as the governing rule. But applied naively it produces the wrong
schema, because it contains a hidden assumption: that the lease is *derived* from the CalendarEntry. **Most of it
is. Two fields are not.**

Split the ten fields of `CalendarEntryLease` by origin:

| Field | Origin | Recomputable from Firestore? |
|---|---|---|
| `wledHour`, `wledMin` | entry `onTime` | **Yes** |
| `dowMask` | `dateKey` (a single date) | **Yes** |
| `expiresAt` | entry `offTime` + overnight wrap | **Yes** |
| `wledPayload`, `patternName` | entry pattern + brightness | **Yes** |
| `leasedAt` | wall clock at creation | No, but disposable |
| **`slotIndex`** | **`_allocateFreeSlotIndex()`** | **NO** |
| **`presetId`** | **`_allocatePresetId(dateKey)`** | **NO** |

`slotIndex` and `presetId` are **allocation decisions**, not derivations. They depend on what else was contending
for slots at the instant of allocation. Nothing in Firestore or on the controller records *why* slot 3 belongs to
`2026-08-04` rather than `2026-08-05`. That single fact — the allocation claim — is the thing that exists only on
one phone, and it is the whole of P0-9.

This reframes the work. It is **not** "move the ledger to Firestore." It is **"give the allocation claim a durable
home, and keep everything else derived."** Storing the derived fields would be the mistake: it duplicates the
CalendarEntry, and the copy goes stale the moment the user edits the entry.

### The model, stated explicitly

```
Firestore  /users/{uid}.calendar_entries[dateKey]   = INTENT      — what SHOULD happen
Firestore  /users/{uid}/leases/{dateKey}            = CLAIM       — which slot/preset is reserved
Controller GET /json/cfg → timers.ins               = TRUTH       — what IS armed
SharedPreferences                                    = CACHE       — non-authoritative, discardable
```

**Four rules, and rule 2 is the one that prevents this from becoming a fourth place to disagree:**

1. **The controller is the only authority on arm state.** Any disagreement between a Firestore lease and a
   controller readback is resolved *in favour of the controller*, always.
2. **A lease document is a reservation, never a confirmation.** It says "slot 3 and preset 27 are spoken for by
   `2026-08-04`." It does **not** say "a timer is armed." The instant a lease doc is allowed to mean "armed," it
   becomes a competing truth and this fix makes things worse rather than better.
3. **`armState` may only advance to `confirmed` from a device readback.** Never from a successful write, never
   from a local assumption. A 2xx on the cfg POST is not confirmation — that lesson is already paid for.
4. **The cache may be deleted at any time without loss.** If deleting SharedPreferences loses information, the
   design is wrong.

### Reconciliation — one direction, four cases

Only the controller and Firestore participate. The cache never votes.

| Firestore claim | On controller | Resolution |
|---|---|---|
| present | present, matching | → `confirmed`, stamp `confirmedAt` |
| present | present, **mismatched** hour/min/dow | controller wins as *fact*; re-arm to match intent; log drift |
| present, unexpired | **absent** | lease was dropped → **re-arm** (this is the P0-9 detection) |
| present, expired | absent | → `released`, delete doc (normal sweep) |
| absent | present, `macro ∈ 26-41` | orphan → reclaim the slot. **Only** in that preset range |

The last row is why `presetId` range discipline matters: `macro 26-41` is the only signal that a timer on the
controller is ours to reclaim. It is a convention, not a reservation — bench-proven in `audit/ALL_STUB_CLOBBER.md`
— so the reconciler must never reclaim outside it.

### Does this add a fourth place to disagree?

**It adds a fourth place to *store*, and removes a place to disagree** — but only because of rule 2. Today the
allocation claim has *no* authoritative home, so "was this lease supposed to be armed?" is unanswerable and
therefore un-disagreeable-with in the worst way: silently. Giving it a home makes the question answerable, and
rules 1-3 keep the answer subordinate to the device.

If rule 2 is relaxed — if anyone starts reading `armState == 'confirmed'` as *"the timer is on the controller"*
without a readback — this becomes a net negative and should not ship. That is the acceptance criterion for the
whole design.

---

## 1. PRECEDENT — reuse `schedules_subcollection_feature_flag.dart`, with two deliberate deviations

The machinery is genuinely reusable and should be copied nearly verbatim:

- `SchedulesSubcollectionConfig` shape → `LeaseLedgerConfig` (`enabled` / `allowlistUids` / `rolloutPercent`)
- `parseSchedulesSubcollectionConfig` defensive parse — every field independently falls back to safe-empty
- `resolveSchedulesSubcollectionEnabled` pure resolution (global OR allowlist OR stable bucket)
- Defensive-false on missing doc, malformed field, loading window, and stream error
- `bootstrap…FlagDoc()` written but **deliberately not called** — same discipline

### Deviation 1 — salt the bucket hash. This is not cosmetic.

`schedulesSubcollectionBucket` is `md5(uid) % 100`. If the lease flag reuses it unchanged, **every user lands in
the identical bucket for both rollouts.** The first 10% of the schedules rollout and the first 10% of the lease
rollout would be *the same ten percent of customers* — so a failure in either is indistinguishable from a failure
in the other, on exactly the users you're watching most closely.

Use `md5('lease:' + uid) % 100`. Same function, salted namespace, independent populations. Document that the salt
must never change for the same reason the original hash must never change.

### Deviation 2 — a separate flag document

`config/lease_ledger`, not a field added to `config/schedules_subcollection`. Coupling them means advancing one
advances the other, and they have unrelated risk profiles.

### What the current flag state implies for staging

Live read, 2026-08-03:

```json
config/schedules_subcollection = {
  enabled: false,  allowlistUids: ["wrQRUUKyXyc0deyuu0ORS6wsovO2"],  rolloutPercent: 0,
  modifiedBy: "stage1_founder_allowlist",  lastModified: "2026-07-14T19:31:56Z"
}
```

Three things follow, and the second is uncomfortable:

1. **The pattern works.** `enabled:false` with a non-empty allowlist resolves TRUE for the allowlisted uid — the
   doc's own `notes` field confirms this is intentional and is the documented rollback (`allowlistUids: []`).
   Copy it exactly.
2. **It has been parked at stage 1 for three weeks** and has never advanced past the founder account.
   **`rolloutPercent` has never been exercised in production — not once, on any flag.** The lease migration would
   be the first real percentage rollout this codebase has done. Do not treat that path as proven because the code
   exists; it is untested in the field, and the lease rollout should not be the thing that discovers a bug in it.
   Advancing the *schedules* flag to a small percentage first would de-risk both, and costs nothing extra.
3. **Stage 1 for leases is Tyler only, on the bench** — and unlike schedules, the lease path can be exercised
   end-to-end there (arm a dated entry, sync, read back). See §5.

---

## 2. DOCUMENT SHAPE

### Path: `/users/{uid}/leases/{dateKey}` — yes

`dateKey` is already the registry key (`_activeLeases` is keyed by it), is unique per entry by construction, and
is a legal, human-readable doc id (`2026-08-04`). It joins to `calendar_entries[dateKey]` for free, and — see §3
— it gives you mutual exclusion at the document level at no cost.

### What it carries

```jsonc
/users/{uid}/leases/2026-08-04
{
  "schema_version": 1,

  // ── ALLOCATION — the only non-derivable state. This is the point of the doc.
  "slot_index":   3,          // WLED timers.ins position, 0-7
  "preset_id":    27,         // WLED preset holding the payload, 26-41

  // ── LIFECYCLE
  "date_key":     "2026-08-04",   // redundant with the id; carried for collectionGroup queries
  "leased_at":    Timestamp,
  "expires_at":   Timestamp,      // release must not require the CalendarEntry to still exist
  "arm_state":    "claimed",      // claimed | confirmed | released  — see rule 3
  "confirmed_at": Timestamp|null, // set ONLY from a controller readback

  // ── BINDING
  "controller_id": "20_e7_c8_f4_d5_38",  // see open question below

  // ── DRIFT DETECTION (not a copy)
  "payload_hash": "sha256:…"      // hash of the synthesized payload, NOT the payload
}
```

Snake_case + `toJson`/`fromJson` + `Timestamp`, per the project convention — **not** `toMap`/`fromMap`.

### What stays derived — and why `wledPayload` in particular must not be stored

Recomputed from the CalendarEntry at read time: `wledHour`, `wledMin`, `dowMask`, `patternName`, `wledPayload`.

The tempting mistake is to persist `wledPayload`, since `CalendarEntryLease` carries it today. Three reasons not
to:

1. **The merge path does not need it.** `_buildLeaseTimersPayload()` emits `{en, hour, min, macro, dow}`. The
   payload lives in the *WLED preset*, already on the controller. Dropping it from the durable record costs the
   merge nothing.
2. **It goes stale.** Edit the entry's pattern and the stored payload silently disagrees with the intent. That is
   rule 2 violated by the back door.
3. **Size.** Payloads can carry per-pixel `i` arrays — the Sparkler-class presets in the command log run to
   several KB. Multiply by up to 16 leases and the offline cache (§6) starts to matter.

Store `payload_hash` instead: enough to *detect* that the armed preset no longer matches intent, without becoming
a second copy of it.

**Release never needs the payload.** `slot_index` + `preset_id` + `expires_at` are self-sufficient to zero a slot,
which matters because a lease may outlive its CalendarEntry (`handleEntryDeleted`).

### Open question — `controller_id`

Leases today are implicitly single-controller. A residential account with linked controllers, or a commercial
zone, arms on *one* of them, and nothing in the record says which. Recommend carrying `controller_id` from the
start rather than adding it later; it is free now and a migration if deferred. **This needs a decision, not a
default** — I don't know from the code whether multi-controller lease arming is intended to fan out or bind to
the primary.

### Rules — and the sequencing constraint you flagged

`/users/{uid}/leases/{dateKey}` needs owner read/write, structurally identical to the existing
`/users/{uid}/schedules` rule.

**This ships after the `controller_ips` rules deploy completes its soak. Do not stack two rules changes.**
Confirmed from the repo: `firestore.rules` references `controller_ips` at lines 513 and 545, and HEAD is
`624d347 merge: command-safety S1+S2 -- staged, NOT DEPLOYED`. The deploy-order constraint on that change is
already load-bearing (backfill `controller_ips` **before** the rules, or remote control dies fleet-wide). Adding a
second rules change into that window means a rollback cannot be attributed.

**Sequence:** `controller_ips` backfill → `controller_ips` rules → 24h soak, confirmed clean → *then* a
single-purpose leases-rules deploy → then flag stage 1. Four discrete steps, each independently revertible.

---

## 3. MULTI-DEVICE

### Today this is already broken, silently

`_kLeaseStorageKey = 'calendar_leases_v1'` — a **single global key, not namespaced by uid**. Two consequences,
both live today:

- Two phones on one account hold fully independent ledgers, neither aware of the other.
- **An account switch on one device inherits the previous account's leases.** Slot and preset numbers from
  account A get merged into account B's cfg writes. The Firestore path is uid-scoped, so the migration fixes this
  incidentally — worth noting as a second bug closed.

The concrete two-phone failure: phone A allocates slot 3 for `2026-08-04`. Phone B, cold, sees an empty ledger,
allocates slot 3 for `2026-08-05`. Both write cfg. One silently overwrites the other on the controller, and each
phone believes it owns the slot.

### Last-write-wins: fine for the body, **not** for allocation

You asked for this to be stated rather than defaulted to. Stating it:

**LWW is correct for lease *body* updates.** `arm_state` advances `claimed → confirmed → released` monotonically
within a lease's life, and `confirmed_at` is idempotent. Two devices confirming the same lease converge. No
transaction needed, no conflict to resolve.

**LWW is wrong for *allocation*,** which is mutual exclusion, not a value update. Two mitigations, matched to the
two collision shapes:

1. **Same `dateKey`, two devices** → free. Allocation writes as a `create` (fail-if-exists) against
   `/users/{uid}/leases/{dateKey}`. Because `dateKey` **is** the doc id, the second device's create fails
   deterministically and it re-reads instead of double-allocating. This is the common case and it costs nothing.
2. **Different `dateKey`, competing for the same free slot** → needs a transaction. Read the whole `/leases`
   collection, pick the lowest free `slot_index`, write. The collection is bounded at ~16 docs (8 slots, preset
   range 26-41), so this is a cheap transaction, not a scaling concern.

`_allocateFreeSlotIndex()` today also counts ScheduleItem demand before allocating. That input stays local and
unsynchronised — a known, accepted imprecision that the transaction does not fix and does not need to.

---

## 4. MIGRATION

Same discipline as the schedules migration: dual-write, then dual-read, then flip, then remove.

| # | Step | Flag | Reads from | Writes to |
|---|---|---|---|---|
| 0 | Leases rules deploy (standalone, post-soak) | — | — | — |
| 1 | Ship dual-**write**. Every mutation writes prefs **and** Firestore | off | prefs | both |
| 2 | Backfill on launch: prefs → Firestore, create-if-absent | off | prefs | both |
| 3 | Flip stage 1 (Tyler allowlist) — read path → Firestore | allowlist | Firestore | both |
| 4 | Stage 2: `rolloutPercent` 10 → 50 → 100 | percent | Firestore | both |
| 5 | Remove prefs writes — only after 100% + one full release soak | on | Firestore | Firestore |

Step 1 must bake for a full release before step 3. Step 2 is the only thing that saves existing ledgers, and it
must run *before* any device flips its read path — otherwise a flipped device sees an empty collection and
concludes the user has no leases.

### Idempotency — a re-run must produce identical output

It does, **if three things hold**, and the third is the one that is easy to get wrong:

1. **Doc id = `dateKey`.** A re-upload targets the same document. No duplicates possible.
2. **Every written field is a pure function of the source prefs record.** `leased_at` and `expires_at` are carried
   **from the record**, never re-derived from `now()`.
3. **No `FieldValue.serverTimestamp()` anywhere in the document body.** A `migrated_at: serverTimestamp()` field
   would make every re-run produce a *different* document — content-idempotent is what matters, not
   "it doesn't crash on re-run." If a migration timestamp is wanted, put it in a **separate marker document**, not
   in the lease body.

Verification: run the backfill twice against a scratch account, export both times, `diff`. Byte-identical or the
migration is not idempotent.

### The dual-read trap

The obvious precedence rule — *"read Firestore; if empty, fall back to prefs"* — is **wrong**, and would cause a
visible bug.

Consider: user deletes all their leases on phone A. Firestore is now legitimately empty. Phone B falls back to its
stale prefs and **resurrects every deleted lease**, then merges them into its next cfg write.

Fix: a one-way **migration marker** (`lease_ledger_migrated_at` on the user doc, or a sentinel doc in the
collection). Once set, prefs are never read again for that account, and an empty collection means empty. The
fallback exists only for the pre-migration window.

---

## 5. WHAT IT UNBLOCKS — and the honest limit

### Yes, it makes P0-3.2 verifiable. Here is exactly how.

Today, per BUGS_AND_DEBT's own P0-9 entry: *"Confirming a fix therefore needs a SharedPreferences dump from the
handset, not a bench test."* That is correct and it is the structural blocker — the authoritative record lives on
a device you cannot query. Not from Firestore, not from the bench, not remotely.

After the migration, verification becomes a **three-way diff runnable from a laptop**:

```
Firestore /users/{uid}/leases   → {slot_index, preset_id, expires_at}  = SHOULD be armed
GET http://<controller>/json/cfg → timers.ins[]                        = IS armed
match on macro == preset_id                                            → survived / dropped
```

Two things this enables that are impossible today:

1. **A bench case for P0-3.2.** The harness (`bench/bin/bench.dart`) currently cannot populate the phone ledger,
   so "arm a lease → run a schedule sync → assert the lease timer survives" is unwritable. With Firestore the
   harness **seeds the collection directly** and the case becomes ordinary. The comparator already exists in
   embryo: `_logLeaseReadback` ([:1012](../lib/features/schedule/calendar_entry_lease_manager.dart#L1012))
   already fetches `timers.ins` and matches on `macro == lease.presetId`. Re-source it from Firestore instead of
   the in-memory registry and it is the reconciler.
2. **A fleet-wide lease audit.** "How many claimed leases are actually armed right now?" is currently
   unanswerable for any account. It becomes a read-only script of the same shape as the census in
   `audit/SOLAR_FAILURE.md`.

### The limit — and this is the most important paragraph in the document

**Moving the ledger to Firestore does not, by itself, fix P0-9.**

The cold-ledger race is not fundamentally about *where* the data is stored. It is that
`activeLeaseTimers()` returns `[]` for **two different situations that must not be conflated**:

- "this account has no leases" → merging nothing is correct
- "I don't know yet" → merging nothing **destroys live automation**

The mechanism, confirmed in the code: `calendarEntryLeaseManagerProvider` calls `manager.initialize()`
**fire-and-forget** (`// ignore: unawaited_futures`,
[:1372](../lib/features/schedule/calendar_entry_lease_manager.dart#L1372)); `activeLeaseTimers()`
([:1223](../lib/features/schedule/calendar_entry_lease_manager.dart#L1223)) reads `_activeLeases` synchronously
with **no initialization guard**. There *is* an `_initialized` field — declared at :407, set at :467, and read
**only by a `@visibleForTesting` getter at :1359. Nothing in production consults it.** A sync racing the load
silently merges zero leases.

Swap prefs for Firestore and the race survives verbatim, renamed: a snapshot listener's first emission on cold
start arrives from cache and can be empty before the server responds.

**So the fix is two parts, and Firestore is only the second:**

- **(a) Make the tri-state explicit.** `activeLeaseTimers()` returns `Loading | Empty | Leases(...)` instead of a
  bare list, and `syncAll` **refuses to write cfg** while the ledger is `Loading`. Deferring a sync by a few
  hundred milliseconds is free; wiping a customer's Game Day automation is not.
- **(b) Move the ledger to Firestore** — which is what makes (a) *verifiable*, multi-device correct, and
  survivable across reinstall.

**(a) is small, has no schema or rules dependency, and does not need the migration.** It could ship on its own
timeline. Whether it belongs in the launch build is your call, not mine — flagging it because it is the part that
actually stops the data loss, and the exposure below is live this week.

### Also note: `shouldSkipClobberingWrite` does not cover this

The sibling guard shipped today ([schedule_sync.dart:436](../lib/features/schedule/schedule_sync.dart#L436),
working tree, uncommitted) skips the cfg write when `refusedCount > 0` **and** the payload carries no enabled
entry. A cold-ledger sync where some schedules *do* arm produces a payload full of real timers — the guard
correctly does not fire, and the leases are dropped anyway. BUGS_AND_DEBT already says this; it is confirmed.

---

## 6. OFFLINE — not assumed better, and it isn't

Firestore offline persistence is on by default in the Flutter SDK. Comparing honestly against prefs:

| | SharedPreferences (today) | Firestore offline cache |
|---|---|---|
| Survives app restart offline | Yes | Yes |
| Survives **reinstall** | **No** | **No** — the local cache is cleared on uninstall too |
| Second device sees the record | **No** | **Yes**, once online — the real win |
| Empty-vs-unknown distinguishable | **No** | **Yes** — `metadata.isFromCache`, *if you check it* |
| Cross-device write conflict | Impossible (never shared) | **Newly possible** |
| Stale read after a week offline | Yes | Yes — but can now be silently contradicted later |

**Verdict: better for multi-device, worse for conflict.** It is not a straight upgrade, and reinstall — one of the
four cold-ledger causes in the P0-9 writeup — is **not** fixed by the cache. It is fixed by the *server* copy, on
the next online read. Worth being precise about, because "Firestore survives reinstall" is true only with
connectivity.

The genuinely new hazard: a device offline for days can allocate a slot another device already took, with the
conflict surfacing only at reconnect. Prefs never had that class of bug because it never shared anything.

**Two mitigations, and the second is a clean rule that falls out of the domain:**

1. **Treat cache-only as `Loading`, not `Empty`.** Check `snapshot.metadata.isFromCache` and feed the tri-state
   from §5(a). This is the same distinction, and it is why the tri-state has to exist regardless of substrate.
2. **You may READ a lease offline. You may not ALLOCATE one offline.** Allocation offline is *meaningless* —
   arming a lease requires a LAN write to the controller, so a device with no connectivity cannot complete the
   operation anyway. Gate allocation on a server-confirmed read (`Source.server`) and the entire offline-conflict
   class disappears by construction. Nothing is lost: the user was never going to get an armed timer out of it.

---

## Live exposure while this is undesigned

Read from Firestore, 2026-08-03. Lease window is 48h, so entries dated 08-04 and 08-05 are **in-window today**.

| Account | Future entries | Dates |
|---|---|---|
| **Taps On Main** (commercial) | **6** | 08-04 → 08-09 |
| **Chris Cipollone** | **4** | 08-04 → 08-07 |
| Tyler Honeycutt | 2 | 08-04, 08-05 |

`config/calendar_leases.liveWritesEnabled = true` — lease writes are live.

You named Chris. **Taps On Main is more exposed** — six pending entries against his four, and it is the commercial
account. Both have leases in-window right now. Any sync either runs against a cold ledger this week drops them
silently, and neither the customer nor we would see it: the lease is gone from the controller *and* from the
ledger that would have restored it.

---

## Summary of decisions requiring your call

1. **Rule 2 is the acceptance criterion.** If a lease doc is ever read as proof a timer is armed, don't ship this.
2. **Salt the rollout bucket** (`md5('lease:'+uid)`) — otherwise both rollouts hit the identical 10% of customers.
3. **`rolloutPercent` has never run in production.** Consider advancing the schedules flag off stage 1 first, so
   the lease rollout isn't what discovers a bug in the rollout mechanism.
4. **`controller_id` in the lease doc** — needs a decision on multi-controller lease semantics; I could not
   determine intent from the code.
5. **Part (a), the tri-state loading gate, is separable from the migration** and is the part that actually stops
   the data loss. Launch build or fast-follow is your call.
6. **Rules sequencing:** `controller_ips` soak must complete and be confirmed clean before the leases rule ships.
   Separate deploys.
