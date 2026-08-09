# S3b — DENORMALIZE RESOLVED PARTICIPATING CHANNELS

**Date:** 2026-08-07 · **Branch:** `main` @ `d48072f` (`2.5.10+66`), working tree
**Status: IMPLEMENTED, TESTED, CONTRACT-VERIFIED AGAINST PRODUCTION FIRESTORE. NOT DEPLOYED.**
One on-device leg is still owed — §6.3.

---

## 0. THE GAP

`resolveParticipatingChannels` needs `allDeviceChannelIds` — the controller's hardware **bus**
list, read over `/json/cfg`. That is LAN-only: the bridge has no cfg dispatch branch and
`CloudRelayRepository.applyConfig` throws `CfgWriteUnsupportedException`. Its **output** is then
cached in SharedPreferences, on the phone.

So a Cloud Function has neither the input nor the output. A cloud-fired Game Day would either
light every channel — including the patio a customer deliberately excluded — or fall back to
segment 0 only. Both are visible regressions against the #29 fix.

**The fix is the `controller_ips` precedent with one structural difference.** `controller_ips`
is maintained by a Cloud Function trigger because its source is server-visible. This set's
source is not: only a phone on the LAN can compute it. So this is **app-written**.

---

## 1. WHERE — `users/{uid}/controllers/{controllerId}`

Four fields, snake_case to match the surrounding convention (`controller_ips`, `dealer_code`,
`display_name`):

| Field | Meaning |
|---|---|
| `participating_channels` | `int[]` — the resolver's output. `[]` is meaningful (see §5) |
| `participating_channels_device_ids` | `int[]` — the bus list it was computed **against** |
| `participating_channels_at` | `serverTimestamp` — when |
| `participating_channels_source` | `"game_day"` / `"neighborhood_sync"` — which resolve site |

**Why that document and not a new one.** `dispatchFireJobs` **already reads it** to resolve
`controllerIp` before every fire. Putting the set there makes it free — no extra read, no new
collection, no rules change (the controllers subcollection is already owner-readable and
Admin-readable). The alternatives both cost something: the user doc forces an arbitrary choice
for multi-controller accounts, and a dedicated collection adds a read per fire.

**`participating_channels_device_ids` is the field that makes this trustworthy.** The resolved
set is only meaningful against the shape it was computed from. Without the shape, the stored
list is an assertion with no basis and no reader can judge whether it still applies.

### What writes it, and when

`publishParticipatingChannels` in
[lib/features/wled/participation_denormalizer.dart](lib/features/wled/participation_denormalizer.dart),
called fire-and-forget from **both** existing resolve sites, immediately beside the existing
`saveLocalParticipatingChannels` call:

| Site | Trigger |
|---|---|
| [game_day_autopilot_providers.dart:172](lib/features/autopilot/game_day_autopilot_providers.dart#L172) | every Game Day payload build |
| [neighborhood_sync_engine.dart:684](lib/features/neighborhood/neighborhood_sync_engine.dart#L684) | every sync command applied |

It is **never fatal and never blocking**. This is data for a feature that does not exist yet
(S5); it must not fail an apply. The SharedPreferences cache remains the sole authority for
on-device behaviour and is written independently, exactly as before. Nothing about what
participates changed — this only publishes the answer.

A `null` resolution is **not** published. Null means "the resolver had no opinion", which is
not the same as `[]`, and writing it would destroy the distinction the server depends on.

---

## 2. WHEN — on change only

A resolve runs on every Game Day payload build and every applied sync command — for an active
session that is several per minute. Publishing each one would be a write per apply, per user,
forever, for a value that changes when **hardware** changes.

So: publish only when the set differs from the last value **this process** published for that
controller (`publishedParticipationMemo`, in-memory, keyed by controller id).

The memo is deliberately **not persisted**, which means each app launch republishes once. That
is the point — it is a free self-heal. If a write is ever lost, the next cold start repairs it,
with no read-back and no reconciliation job. One write per launch per controller is noise-free.

---

## 3. STALENESS — the honest answer

### What the app already does

`ParticipationReconciler` ([participation_reconciler.dart](lib/features/wled/participation_reconciler.dart))
already clears the local cache when the live bus list stops matching what the resolver would
produce — that is the Addendum-1 fix for "a 2nd bus wired up after the cache was written". The
next resolve then republishes. **So in normal operation the denormalized value self-heals on
the next app open after any hardware change.**

### What the server can and cannot detect

**Cannot: the current bus list.** That is the whole reason this document exists. There is no
off-LAN source. I considered deriving it from S6's daily `getInfo` probe, which returns
`leds.seglc` — Ellie's shows `[3,3]`, two entries. **Rejected:** `seglc` is per-*segment*, not
per-*bus*, and the repo already records that a reboot can collapse two segments into one
(`seglc [3,3] → [3]`). Cross-checking bus count against it would generate false staleness on
every controller reboot. A wrong staleness signal is worse than none.

**Can: age, and provenance.** So the design is:

```
absent            → REFUSE (never_resolved)
malformed         → REFUSE
no timestamp      → REFUSE (age unknowable — never assumed fresh)
older than 90d    → REFUSE (stale:<n>d)
otherwise         → USE
```

**Why 90 days.** This is a bound on **abandoned** data, not a freshness requirement. A customer
using the system republishes constantly and never approaches it. A shorter horizon would strand
people who simply do not open the app — which is most of them, and is precisely the population
whose lights a cloud fire exists to serve. The single dangerous case is *hardware changed AND
the app has not been opened since*, which nothing server-side can detect; 90 days is the
backstop for that case alone.

**The residual risk, stated plainly:** a customer who re-busses their controller and never
opens the app again will have a fire honour the old set for up to 90 days. The set will be a
subset or superset of the truth, so some channels light wrongly. This is not fully closable
without either OTA cfg-over-bridge (does not exist) or the controller reporting its bus list in
`/json/info` (it does not).

---

## 4. THE FIELD THAT IS ALWAYS NULL — **still owed, not abandoned. Keep it.**

`participatingChannelIndices` on `GameDayAutopilotConfig` and `NeighborhoodMember` is read by
the resolver as its `explicit` argument and, per
[CHANNEL_MAPPING_AUDIT_2026-05.md:459](docs/audits/CHANNEL_MAPPING_AUDIT_2026-05.md), written by
no UI. **Re-confirmed today:** the only assignments anywhere in `lib/` are in `fromJson`
deserialization and `copyWith` — four sites, no widget among them. There is no picker.

**Abandoned or owed?** Owed — and the codebase says so explicitly. The sync engine records, at
the point where the old empty-participation gate was removed:

> *"the `participatingChannelIndices` field is dead schema (no UI writes it, no picker exists,
> every shipped member null) — so the gate was defending semantics no UI could produce.
> Dropped; every joined home applies. **When/if partial-channel participation ships with a real
> picker, re-add the gate with defaults co-designed against the picker.**"*

That is a deliberate deferral with a named re-entry condition, not an abandonment.

**Recommendation: keep the field. Do not delete it** (and this pass does not, as instructed).
Three reasons: it is the resolver's documented override input and deleting it would collapse a
three-branch policy into two; it costs nothing (absent from every document, so zero storage);
and S3b makes it *more* valuable, because the moment a picker ships, its output flows to the
server through the pipe built here with no further work.

**What would change the recommendation:** if the product decides partial-channel participation
will never ship, then the field, the `explicit` branch of the resolver, and this deferral
comment should all go together — as one deliberate removal, not a drive-by.

---

## 5. BACKFILL — there is none, and the server skips

**No server-side backfill is possible.** The input is the hardware bus list; it is only readable
over `/json/cfg`, on-LAN. Unlike `controller_ips` — which a Cloud Function could compute from
data it already had — nothing on the server can manufacture this value.

So every controller starts at `never_resolved` and stays there until its owner next opens the
app while on their home network. **The server skips.** Skipping is right: a fire that does not
happen is a disappointment; a fire on the wrong channels is a support call from someone who
cannot see their own house.

### What the operator sees

`participationForFire` returns a **distinct reason per refusal** — `never_resolved`,
`malformed`, `no_timestamp`, `stale:<n>d` — rather than an undifferentiated skip. A test asserts
all four are distinguishable, because "the dispatcher skipped 9 controllers" is not an
actionable sentence and "9 controllers have never published a channel set" is.

`never_resolved` is the **expected** state fleet-wide on day one, not an error, and the digest
copy should say so. Distinguishing it from `stale` matters: the first is "waiting for the
customer to open the app", the second is "this data is too old to trust".

**One case that is usable but still fires nothing:** an empty set, `[]`, meaning the customer
excluded every channel. `isEmptyParticipation` exists so the caller can tell "we do not know"
from "we know, and the answer is none". At the fire both produce no command; to an operator they
are completely different.

---

## 6. VERIFICATION

### 6.1 Unit

- **Dart** — `test/features/wled/participation_denormalizer_test.dart`: **16 passed.** Publish-on-change in every direction; order sensitivity; `[]` publishable and distinct from never-published; the memo is per-controller and stores copies; `buildParticipationDoc` records the device shape and copies its inputs; field names asserted snake_case; the horizon bounded at both ends.
- **Functions** — `functions/test/unit/participationForFire.test.js`: part of **7 suites / 201 tests, all passing.** Every refusal reason including malformed shapes (`[0,"1"]`, `[0,1.5]`, `[-1]`, `[[0]]`); the 90-day boundary at ±1 ms; clock skew not producing a negative age; empty-usable vs unusable; all four reasons provably distinct.

### 6.2 Contract, against production Firestore — **10 passed, 0 failed**

Ran the **real compiled** `participationForFire` against the **real** bench controller document
(`users/wrQRUUKyXyc0deyuu0ORS6wsovO2/controllers/192_168_1_150`):

```
PASS  controller doc has NO participating_channels yet (never resolved)
PASS  server verdict = never_resolved → SKIP
      stored: {"c":[0,1],"d":[0,1,2,3],"s":"bench_verify","at":"2026-08-07T18:30:36.994Z"}
PASS  server verdict = usable
PASS  channels round-tripped exactly
PASS  age is ~0
PASS  device shape recorded for provenance
PASS  backdated set is REFUSED as stale
PASS  empty set is USABLE and means nothing-to-light
PASS  CLEANED UP — synthetic fields removed
PASS  controller doc otherwise intact (ip preserved)
```

The written document used the exact shape `buildParticipationDoc` produces. **All four synthetic
fields were deleted afterwards** so no future fire can act on bench test data; the controller's
`ip` was re-verified intact.

### 6.3 On-device — **OWED, and I have not done it**

What is **not** yet proven: that a real resolve on the tablet actually calls
`publishParticipatingChannels` and lands the set. Everything either side of that call is
verified — the decision logic by unit test, the document shape and the server's reading of it
against production — but the wiring inside a running app is not.

That needs the app on the bench tablet over wireless ADB, whose port churns on every toggle, so
per the standing rule I have **not** attempted it unasked. The check, when run:

1. Open the app on the bench tablet, connected to `.150`
2. Trigger a resolve — start a Neighborhood Sync or apply a Game Day design
3. Read `users/wrQRUUKyXyc0deyuu0ORS6wsovO2/controllers/192_168_1_150` and confirm
   `participating_channels` matches what the local cache holds
4. Change the bus shape (add/remove a bus in the controller config), re-resolve, confirm the
   stored set **and** `participating_channels_device_ids` both update

Step 4 is the one that matters most — it exercises the reconciler → republish path that §3's
self-healing argument rests on.

### 6.4 Full suites

- `flutter test` → **1961 passed, 3 skipped, 1 failed.** The single failure is
  `cloud_ai_processor_normalize` — the expected pre-existing P1-8. Tree was clean of the other
  window's edits (HEAD `d48072f`).
- `cd functions && npx jest test/unit` → **7 suites, 201 tests, all passed.**
- `flutter analyze` on the three touched files → clean apart from one pre-existing
  `unnecessary_import` info in `neighborhood_sync_engine.dart` that predates this change.

---

## 7. CHANGED FILES

| File | Change |
|---|---|
| [lib/features/wled/participation_denormalizer.dart](lib/features/wled/participation_denormalizer.dart) | **NEW** — publish decision, document shape, staleness constant, fire-and-forget writer |
| [lib/features/autopilot/game_day_autopilot_providers.dart](lib/features/autopilot/game_day_autopilot_providers.dart) | Publish beside the existing local cache write |
| [lib/features/neighborhood/neighborhood_sync_engine.dart](lib/features/neighborhood/neighborhood_sync_engine.dart) | Same |
| [functions/src/participationForFire.ts](functions/src/participationForFire.ts) | **NEW** — pure server-side verdict; S5 wires it |
| [test/features/wled/participation_denormalizer_test.dart](test/features/wled/participation_denormalizer_test.dart) | **NEW** — 16 tests |
| [functions/test/unit/participationForFire.test.js](functions/test/unit/participationForFire.test.js) | **NEW** — 14 tests |

**No `firestore.rules` change.** The controllers subcollection is already owner-readable and
the Admin SDK bypasses rules. The app writes with `set(merge: true)` under its own uid, which
existing rules permit.

**No index change.** Nothing queries on these fields; they are read by document id.

---

## 8. FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **No server-side backfill is possible** — unlike `controller_ips`, the input only exists on-LAN. Every controller starts at `never_resolved` and the server must skip until the owner opens the app | Structural, by design |
| 2 | **`participatingChannelIndices` is owed, not abandoned** — the sync engine carries an explicit re-entry condition ("when/if a real picker ships"). Keep it; deleting would collapse the resolver's three-branch policy into two | Decision |
| 3 | **`seglc` from `/json/info` cannot substitute for the bus list.** It is per-segment, and a reboot collapses segments (`[3,3] → [3]`), so cross-checking would fire false staleness on every reboot. Rejected deliberately | Design — a tempting wrong answer |
| 4 | **Age is the only server-detectable staleness signal**, and it does not cover the one dangerous case (hardware changed, app never reopened). Bounded at 90 days as a backstop; not closable without OTA cfg-over-bridge or a firmware change | **Accepted residual risk** |
| 5 | Refusal reasons are **distinct by design** — `never_resolved` is the expected fleet-wide state on day one and must not read as an error, while `stale` is a genuine data-trust problem | Operator clarity |
| 6 | An **empty set is usable** and means "nothing to light"; `isEmptyParticipation` keeps it distinguishable from "unknown", which looks identical at the fire and is completely different to explain | Design |
| 7 | The in-memory memo republishes **once per app launch**, which is a free self-heal for a lost write with no read-back or reconciliation job | Design |
| 8 | **The on-device leg is unverified** (§6.3) — the wiring inside a running app has not been exercised. Everything either side of it has | **Owed** |

---

## 9. OPEN — for S5

1. **Wire `participationForFire` into the dispatcher.** It has no caller today, deliberately.
   The planner must skip a fire whose participation is unusable, and record the reason on the
   job so `fire_metrics` can count `never_resolved` separately from real failures.
2. **Decide the digest copy** for controllers that have never published. It is not an outage
   and must not read like one.
3. **The payload still has to be built from the set** — `applyChannelFilter` /
   `buildParticipatingSegArray` are Dart. The server needs an equivalent, and that is the other
   half of S3b's motivation that this pass does not address.
