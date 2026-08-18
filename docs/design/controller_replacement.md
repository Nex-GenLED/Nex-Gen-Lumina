# Controller Replacement — Design

**Status:** **APPROVED 2026-08-18.** Stage 0 and Stage 1's client half are DONE. Everything touching
`functions/` is **HELD pending explicit confirmation that #94 (Node 22) has landed.**
**Filed:** 2026-08-18
**Depends on:** the identity census (this doc's §1 tables), #94 (Node 20→22), and **#96** (§5.0 — now filed).
**Explicitly out of scope:** #92 (A4 monitoring-only migration), #93 (predeploy hook — lands *with* #94, not here).

### Progress

| Stage | State |
|---|---|
| 0 — file the `effectiveUserUid` defect | **DONE** — filed as **#96** |
| 1 — client half (four call sites → `effectiveUserUidProvider`) | **DONE** — `flutter analyze lib/`: 0 errors, 0 new warnings |
| 1 — `functions/` half (resolver spec + conformance fixture, zones id-conversion backfill, `voicePrimaryControllerId` seeding) | **HELD** — awaiting #94 confirmation |
| 2 — cascade delete + orphan reaping | not started |
| 3 — replace callable + UI | not started; needs R-4 sweep first |
| 4 — bridge IP reconciliation | not started; needs R-5 sweep first |

### Hard requirement — `voicePrimaryControllerId` seeding

**The highest-blast-radius change in the arc.** Before it ships, prove **byte-identical SYNC output for a
multi-controller household**: capture before → seed → diff → **identical or it does not ship**. Not "looks
equivalent", not "same device count" — a byte diff. A household whose `lumina-main` silently moves loses its
Google/Alexa rooms and routines, and the in-source contract at `voice/deviceResolver.ts:84-96` exists
because that is unrecoverable for the customer.

---

## 0. Why this exists

Every hardware failure in the field is this operation. A controller dies, the dealer swaps the box, and
today there is no path that binds the successor to the existing home. The read-only audit that preceded
this doc found **first-time pairing only** — no replace, re-pair, swap, adopt, or reprovision flow exists
for controllers. The only migration in the codebase (`migrateInstallerControllersToCustomer`,
`installer_setup_wizard.dart:211`) re-scopes controller docs between UIDs at handoff and **preserves doc
ids verbatim** — it is a UID transfer, not a hardware swap.

So a field replacement today is founder-level Firestore surgery: hand-edit `linkedControllerIds`, hand-copy
`pixelMap/*`, hand-delete the orphan, and hope nothing else referenced the dead id. That is not a dealer
operation, and it does not scale past one person.

The census also established *why* this is harder than "add new, delete old": controller identity is
persisted or cached in **18 distinct places**, and staleness fails silently in all of them.

> **Count correction.** The census summary said "17 fail silently"; the enumerated groups total **18**.
> The table in §1.2 is the authoritative list. The doc uses 18.

---

## 1. Core principle: identity is a REFERENCE, resolved at use-time

### 1.1 The pattern, stolen from `dispatchFireJobs`

`dispatchFireJobs` is the one place in the codebase that gets this right. A fire job stores
`controllerId` — and nothing else about the target. At dispatch time it does this
(`functions/src/dispatchFireJobs.ts:275-293`):

```ts
const controllerId = job.controllerId as string;

// ── Resolve the target IP SERVER-SIDE, always. Never omit. ───────
const ctrl = await db.collection("users").doc(uid)
  .collection("controllers").doc(controllerId).get();
const ipRaw = ctrl.exists ? ctrl.get("ip") : null;
const controllerIp = typeof ipRaw === "string" && ipRaw.length > 0 ? ipRaw : null;
if (!controllerIp) {
  await jobSnap.ref.update({
    state: "skipped", skipReason: "unresolvable_target", /* … */
  });
  continue;
}
```

Three properties make it correct, and all three are the design contract for this arc:

1. **The stored value is a key, not an address.** The job never carries an IP.
2. **The address is resolved from the single source of truth at the moment of use.** Not at plan time,
   not from a denormalized copy.
3. **Unresolvable refuses, and says why.** `unresolvable_target` is terminal and legible. It does not
   guess, does not fall back, does not retry into a wrong host.

Stated as the principle for this arc:

> **Stored controller identity is a REFERENCE to be resolved at use-time, never an address to be trusted.
> A reference that cannot be resolved must refuse loudly, never fall back to a cached address.**

This is the same family as the three facts already in the project's ledger — *a readback proves existence,
never app-readability*; *a simulator must fail everywhere the real component fails*; *a deploy's success
proves delivery, never content*. In each, a green signal was never measured against the thing it claimed.
A cached IP is the same shape: it proves an address was once correct, never that it is correct now.

### 1.2 Which surfaces resolve-at-use fixes, and which need explicit migration

The distinction is mechanical:

- **Resolve-at-use fixes it** when the stale thing is a *copy of an address*. Delete the copy, read the
  source at use-time, and staleness becomes structurally impossible.
- **Explicit migration is required** when the stale thing is *set membership* — a reference to a document
  id that no longer exists. No amount of resolve-at-use repairs `linkedControllerIds: ["OLD_MAC"]`, because
  the reference itself is what is wrong. Something must rewrite old→new.
- **A third bucket is already correct** and needs only hardening, not redesign.

| # | Surface | Bucket | Rationale |
|---|---|---|---|
| 1 | `controllers/{id}.ip` (root field) | **C — source of truth** | This *is* the source. It stays, and stays mutable (DHCP). Everything else stops copying it. |
| 2 | `controllers/{cid}/pixelMap/{ch}` | **B — migration** | Channel map is per-controller data, not an address. Must be copied to the successor and cascade-deleted from the retired doc. |
| 3 | `roofline_config/config` (legacy, unkeyed) | **B — migration (decision)** | Has no controller key at all, so it cannot be resolved *or* rewritten. See §2.6 for the decision required. |
| 4 | `users/{uid}.controller_ips[]` | **C — already correct, needs hardening** | Trigger-maintained from source on every controller write incl. delete. Self-heals. Two holes to close (§2.7). |
| 5 | `systemConfig.linkedControllerIds[]` | **B — migration** | Set membership by doc id. Must be rewritten. |
| 6 | `systemConfig.zones[].primaryIp` / `.members[]` | **A — resolve-at-use** | Stores **raw IPs**. Convert to controller ids; resolve IPs at use. Then a DHCP move needs no write at all. |
| 7 | `properties/{pid}.controllerIds[]` | **B — migration** | Set membership by doc id. |
| 8a | member `controllerId[]` (denormalized set) | **B — migration** | Set membership. Refresh denormalization so the successor is named. |
| 8b | member `controllerIp` (legacy single) | **A — resolve-at-use (delete the field)** | A cached address on a doc the server already joins against `controllers`. Branch 3 of `resolveMemberTargets` should be retired. |
| 9 | `commands/{id}.controllerIp` | **A — resolve-at-use** | Every writer must attach a server-resolved IP, as `buildFireCommand` already does. |
| 10 | `fire_jobs/{id}.controllerId` | **A — already resolve-at-use at dispatch** | Dispatch is correct. Only the *selection* at plan time is wrong (row 15). |
| 11 | `controller_health/{controllerId}` | **B — migration** | Keyed by controller id; never pruned. Transfer or initialize, and reap the orphan. |
| 12 | Native WLED timers on the device | **B — migration (device-side)** | Not a Firestore reference at all. New hardware boots with **no timers**, and nothing detects the gap. Only an explicit re-sync fixes it. |
| 13 | Bridge NVS `wledIp` | **A — resolve-at-use** | Make the fallback unreachable by always carrying an explicit IP (§4). |
| 14 | Google Home `controllerId:"primary"`, no IP | **A — resolve-at-use** | A sentinel string, not a reference. Replace with a real resolved id + IP. |
| 15 | `planGameDayFires` `controllers.docs[0]` | **A — resolve-at-use (shared resolver)** | Unordered selection. Delegate to the shared resolver (§3). |
| 16a | voice oldest-first ordering | **A — resolve-at-use (shared resolver)** | The *ordering rule* is correct and stays; it moves behind the shared resolver. |
| 16b | `lumina-main` binding to the dead controller | **B — migration** | The external binding must be *transplanted* to the successor. Ordering alone cannot do this — see §3.2. |
| 17 | `selectedControllerIdProvider` (IP→id match) | **A — resolve-at-use (inverted)** | Currently resolves id *from* an IP. Invert: select by id, resolve IP. |
| 18 | Installer preference draft `linkedControllerIds` | **B — migration** | A resumed draft can re-assert retired ids. Invalidate on replace. |

**Tally: 9 fixed by resolve-at-use (A), 8 need explicit migration (B), 2 already correct (C).**
(Rows 8 and 16 split across buckets, hence 19 classifications for 18 surfaces.)

The important consequence: **resolve-at-use is the larger and cheaper half, and it is independently
shippable before any replace flow exists.** It also reduces the replace callable's job from "rewrite 18
places" to "rewrite 8" — which is why §5 sequences it first.

---

## 2. The replace flow

### 2.1 Entry point

From an existing controller's management surface — **"Replace this controller"** — in both:

- `lib/features/site/manage_controllers_page.dart` (customer)
- `lib/features/site/system_management_screen.dart` (customer)
- `lib/features/installer/screens/controller_setup_screen.dart` (installer, in-wizard)

Entry from the *old* controller's row is deliberate: it makes the predecessor an explicit parameter of the
operation. A flow entered from "Add controller" cannot know what it is replacing, which is exactly how
today's additive path produces orphans.

### 2.2 Pair the successor — BLE/MAC only

Manual-IP entry is **ineligible** for replacement. The census established why: `DeviceRepository.saveDevice`
derives the doc id as `serial.replaceAll(':','_')` falling back to `ip.replaceAll('.','_')`
(`device_discovery.dart:210-222`), and writes with `SetOptions(merge: true)`. A successor that takes the
predecessor's DHCP lease and is added by manual IP therefore **merges onto the predecessor's document**,
silently inheriting its stale `serial` — a collision, not an orphan, and a worse failure because the two
controllers become indistinguishable in the data.

Replacement therefore requires a real MAC, which means BLE provisioning
(`lib/features/ble/provisioning_service.dart`). The UI must state this rather than silently hiding the
manual option, because an installer whose BLE fails needs to know *why* the path is closed and that the
fallback is "pair manually, then run replace" — not "pair manually as a replacement."

**Open question (R-1):** should the flow allow "the successor is already paired" as an entry state? An
installer may have added it before realising a replace was needed. Recommendation: yes, offer picking an
existing unpaired-to-anything controller as the successor, because the alternative is the installer
deleting and re-pairing hardware to satisfy the tool.

### 2.3 Atomic server-side migration — a callable

Modeled on `joinNeighborhood` / F-3: an `onCall` that validates, then commits one batch.

```
replaceController({ predecessorId, successorId, unarmAcknowledged? })
  → { migrated: {...}, warnings: [...], retired: bool }
```

Why server-side and not a client batch:

- **Atomicity across collections the client cannot see.** `controller_health` is server-written.
- **The client cannot be trusted to be present for the whole operation.** An installer's phone leaving
  the network mid-batch must not leave a half-migrated home.
- **`migrateInstallerControllersToCustomer` already proves the shape** — reads before the batch, one
  `WriteBatch.commit()` for atomicity, throws rather than swallowing (the P0-6 correction). Reuse that
  discipline exactly, including its retry semantics: a commit that landed but was never acknowledged must
  be detectable as already-done rather than failing.

Migration steps, all keyed old→new:

| Step | Target | Operation |
|---|---|---|
| M1 | `controllers/{new}/pixelMap/*` | Copy every channel doc from `{old}/pixelMap/*`. Reads happen **before** the batch (a `WriteBatch` cannot read) — same constraint `migrateInstallerControllersToCustomer:254-257` already handles. |
| M2 | `users/{uid}.systemConfig.linkedControllerIds[]` | Replace `old` with `new`, preserving position and any other members. |
| M3 | `properties/{pid}.controllerIds[]` | For every property naming `old`, swap to `new`. Requires a query across the properties subcollection. |
| M4 | `users/{uid}.systemConfig.zones[]` | Rewrite `primaryIp`/`members[]`. **If Stage 1 has converted zones to ids, this step becomes an id swap; if not, it is an IP swap and will re-stale on the next DHCP move.** This is the clearest argument for sequencing resolve-at-use first. |
| M5 | `neighborhoods/{gid}/members/{uid}.controllerId[]` | Refresh the denormalized set. Note this is a **cross-user document** — the caller writes their own member doc only, which the existing rules already permit (`neighborhood_service.dart:505` does this today). |
| M6 | `controller_health/{new}` | Initialize. **Do not copy** the predecessor's history: consecutive-failure counts and `lastFoldedCommandId` describe dead hardware, and carrying them forward would let a fresh controller inherit an ALERT it never earned. Write a `replacedFrom: {oldId}` provenance field instead, then delete `controller_health/{old}`. |
| M7 | Native WLED timers on the successor | Re-sync via `ScheduleSyncService`. **This is a device-side write, not Firestore**, so it cannot live in the batch — see §2.5. |
| M8 | Installer preference draft | Invalidate any draft naming `old` (`installer_draft_service.dart`). |
| M9 | `lumina-main` external binding | Transplant — see §3.2. |

`users/{uid}.controller_ips[]` is deliberately **absent** from this list: the `syncControllerIps` trigger
recomputes it from source on every controller write including the delete, so it self-heals. Adding a manual
write would be a second writer for a field that already has one.

### 2.4 All writes through `effectiveUserUid`

The callable takes the target uid explicitly and the client passes `effectiveUserUidProvider`, so
installer-serviced replacement works. This is **blocked on a client defect that is not currently filed** —
see §5.0. Without it, an installer inside the Existing Customer flow who runs a replacement writes it under
their own uid, because every add/delete/rename path uses `FirebaseAuth.instance.currentUser.uid`
(`controllers_providers.dart:65`, `:81`; `provisioning_service.dart:206`; `wled_manual_setup.dart:144`)
while only the *read* stream honours impersonation (`controllers_providers.dart:14`).

Server-side, the callable must **not** infer the uid from `request.auth.uid` alone. It needs the staff-session
authorization path that the installer surfaces already use, so a dealer replacing a customer's controller is
authorized without impersonating their auth token.

### 2.5 Retiring the predecessor

Ordered, and the order matters:

1. **Un-arm native WLED timers on the old device, while it is still reachable.** Best-effort. This is the
   step nothing in the codebase does today: the census found that deleting a controller leaves its
   schedule armed on the hardware, so a "removed" controller keeps running its lighting forever.
2. **If unreachable — which is the *normal* RMA case, since the box is usually dead — surface an explicit
   `UNREACHABLE` acknowledgment.** Not a silent skip, not a toast. The installer must affirm "this
   controller could not be reached; its on-device schedule may still be armed" before the flow proceeds.
   For a dead box that is harmless; for a *replaced-because-flaky* box that is still powered, it is a
   support call waiting to happen. The acknowledgment is recorded in the callable's audit trail.
3. **Delete `controllers/{old}` and cascade `pixelMap/*`.** Firestore client deletes never cascade, which
   is precisely how today's delete path orphans the channel map while its dialog promises *"This will
   delete all saved settings for this controller."* The cascade is Stage 2 work and the replace flow
   consumes it rather than reimplementing it.

**Open question (R-2):** should retirement be *deferrable*? An installer may want the old doc retained
briefly for comparison. Recommendation: no — a retained predecessor is exactly the orphan that makes
`planGameDayFires`' `docs[0]` and voice's oldest-first select dead hardware. If retention is wanted, it
belongs as a `retired: true` tombstone that every resolver filters, not as a live doc.

### 2.6 Decision required — legacy `roofline_config/config`

`users/{uid}/roofline_config/config` predates per-controller channel maps and carries **no controller key**
(`roofline_config_providers.dart:37-41`). It is retained as the read source for a one-time lazy migration
into `pixelMap`. After a replacement it will happily re-migrate onto whichever controller next triggers the
lazy path — possibly the successor, possibly a sibling.

Options: (a) delete it once every user has migrated (needs telemetry to confirm); (b) stamp it with the
controller it was migrated into and refuse to re-migrate; (c) have the replace callable re-point it.
**Recommendation: (b)** — it is the smallest change and it closes the hazard for all users, not just those
who run a replacement.

### 2.7 Two holes in `controller_ips[]`

Not replacement-specific, but they sit directly under this flow. `syncControllerIps`:

- **Swallows every error** (`syncControllerIps.ts:122-126`) so as not to block controller writes. The
  backfill callable is the documented recovery path — but nothing *detects* that recovery is needed.
- **No-ops when the user doc is missing** (`:78`), logging a warning. The rules guard then treats a missing
  allowlist as "deny", so every non-empty `controllerIp` command write fails fleet-wide for that user.

Either way remote control is dead and the only signal is a Cloud Logging line. Recommendation: fold an
allowlist-freshness check into `collectControllerHealth`, which already runs daily per user and already
reads the controllers subcollection — it can compare and alert for free.

---

## 3. Primary-selection unification

### 3.1 One resolver, two named selectors — not one rule

The census found three divergent rules:

| Caller | Rule | Location |
|---|---|---|
| Client controller list | **newest-first** by `createdAt` | `controllers_providers.dart:50-55` |
| `planGameDayFires` | **unordered** `docs[0]` | `planGameDayFires.ts:348-349` |
| Voice (Google/Alexa) | **oldest-first**, ties on doc id | `voice/deviceResolver.ts:98-129` |

It would be a mistake to collapse these into one ordering, because two of them encode *different intents*:

- Voice needs a **stable external identity binding**. `lumina-main` is the device id Google and Alexa hang
  rooms, routines, and voice targeting off. Its ordering key must be immutable and controller-intrinsic.
  The contract is documented in-source and says so explicitly: *"A future refactor that re-sorts by name,
  IP, last-seen, or any mutable/reorderable key would silently reassign lumina-main to a different
  controller and churn device identity for every linked household."*
- The client needs **"the controller the user most likely means right now"**, which for a just-paired
  device is the newest.

So the unification is one module exposing named selectors with stated contracts, not one function:

```
resolveControllers(uid) → ControllerRef[]     // single read, tombstones filtered
  ├─ primaryForExternalBinding()  → oldest by createdAt, ties on doc id. IMMUTABLE CONTRACT.
  │                                 Voice/Google/Alexa only. Never call for UI.
  ├─ defaultForUi()               → newest by createdAt. Selection default, not identity.
  └─ allActive()                  → every non-tombstoned controller.
```

**The unification is a specification, implemented twice.** There is no shared code between `lib/` (Dart)
and `functions/` (TypeScript), and this doc should not pretend otherwise. What makes it "one resolver" is a
**conformance fixture** — a JSON table of controller sets and expected selections — exercised by both a
Dart test and a Jest test. That fixture is the artifact that keeps the two implementations honest; without
it, "shared resolver" degrades into two functions that agreed once.

**`planGameDayFires` — DECIDED (R-3, 2026-08-18).** Its `docs[0]` is not just unordered — it means
multi-controller homes only ever fire **one** controller, which is a separate latent bug the census
surfaced. **This arc takes `primaryForExternalBinding()`**, purely because it is deterministic and
tombstone-aware; it fixes *which* controller is chosen and explicitly does **not** widen coverage. The
widening is filed as **#97** and is not to be started yet. Do not quietly fold it in — the fan-out needs the
one-in-flight-per-controller guard (`dispatchFireJobs:317`) re-examined across siblings and a ruling on
whether partial delivery to a subset of a home is success or failure.

### 3.2 Transplanting the `lumina-main` binding

This is the part ordering cannot solve, and it is the sharpest consequence of replacement in the whole arc.

Under oldest-first, a retained predecessor is *permanently* the voice primary: it is the oldest, so it keeps
`lumina-main`, so every "turn on the lights" goes to dead hardware. Deleting the predecessor is necessary
but not sufficient — it hands `lumina-main` to whichever controller is now oldest, which in a
multi-controller home may be a *third* controller that was never the primary. The user's rooms and routines
silently retarget.

The design must therefore make the binding explicit rather than purely derived:

- Store the external-binding owner as a field — `users/{uid}.voicePrimaryControllerId` — seeded on first
  SYNC from `primaryForExternalBinding()` for backward compatibility with every currently-linked household.
- `resolveDevices()` honours the stored field when present, and falls back to the derived ordering when
  absent. Households that never replace hardware see byte-identical SYNC output, which is the compatibility
  requirement the in-source contract demands.
- The replace callable rewrites the field old→new (**M9**), so `lumina-main` follows the successor and rooms
  and routines survive.
- Then a **Google/Alexa re-SYNC must be requested** after replacement. Recommendation: fire a Home Graph
  request-sync from the callable. Without it the binding is right in Firestore and stale in Google's graph
  until the next natural SYNC — the classic "server fixed, client never told" shape.

**Open question (R-4):** does the Alexa path have an equivalent proactive-state mechanism, and is it wired?
The census did not examine `alexa-skill/`. This needs answering before Stage 3 ships, because a
half-transplanted binding across two assistants is worse than a consistent stale one.

---

## 4. Bridge reconciliation — which side owns the address?

Today the bridge holds `pairedWledIp` in NVS (`main.cpp:66`, key `wledIp` at `:172`/`:452`, seeded from
compile-time `DEFAULT_WLED_IP`) and uses it **only as a fallback when a command carries no `controllerIp`**
(`:796-797`). Two writers take that fallback:

- The **Google Home path** always: `functions/index.js:1578` writes `controllerId:"primary"` — a sentinel
  string, not a reference — with **no `controllerIp` at all**.
- Any other addressless command. The in-source note records this measured on the bench as literally
  `0.0.0.0`.

So after a controller replacement, the bridge's cached address points at dead hardware and every voice
command silently goes there.

**Decision: the SERVER owns the address. The bridge's NVS fallback becomes unreachable, not smarter.**

Rationale:

- **Firmware is the slowest and riskiest thing to change**, and the installed fleet cannot be assumed
  updated. A fix that requires new firmware protects only re-flashed units; a fix in the command writer
  protects every unit immediately, including ones that will never be re-flashed.
- **The correct behaviour already exists server-side.** `buildFireCommand` never omits the IP, for exactly
  the reason recorded in its own comment: an untargeted probe got `ERROR: HTTP -1` while 282 named commands
  to the same controller succeeded. Generalizing that to every writer is a known-good change, not a new
  design.
- **It matches the core principle.** A bridge that self-heals its cached address is still a bridge that
  trusts a cached address. Removing the cache from the decision path is strictly stronger than refreshing it.

Work:

1. Every `commands/*` writer attaches a server-resolved `controllerIp`. Specifically: kill
   `controllerId:"primary"` in the Google Home path and resolve through the shared resolver (§3).
2. The two known intentional exceptions stay, and stay documented, because the rules guard depends on
   them: `bridge_setup_screen.dart:617` writes `controllerId:''` with a real IP (pairing verification), and
   `bridge_health_service.dart:35-46` writes no `controllerId` with a real IP at a fixed doc id. Both carry
   an IP, so neither takes the NVS fallback. **Neither is a regression risk here** — the change is about
   commands with no IP, not commands with no id.
3. Firmware change is **optional and deferred**: once no writer omits the IP, the fallback is dead code.
   Retiring it is a cleanup, not a fix, and should not gate this arc.

**Open question (R-5):** is there any *other* command writer — voice, Alexa, a script under `scripts/` —
that omits `controllerIp`? The census enumerated the writers it found, but did not audit `alexa-skill/` or
`google-home/`. A grep sweep for command writes with no IP is a Stage 4 prerequisite, and this doc should
not claim the list is complete.

---

## 5. Sequencing

Four stages, each independently shippable and each leaving the system better than it found it. The ordering
is not arbitrary: **every stage reduces the work of the one after it.** Stage 3's callable rewrites 8
surfaces if Stage 1 ships first, and considerably more if it does not.

### 5.0 Stage 0 — the unfiled prerequisite (CLIENT ONLY)

**File the `currentUser`-vs-`effectiveUserUid` defect.** It is referenced as already filed, but it appears
in neither `docs/BUGS_AND_DEBT.md` nor `docs/BUG_BACKLOG.md` — only an incidental mention in
`docs/audits/DESIGN_STUDIO_AUDIT_2026-07.md`. Untracked work that Stage 1 depends on will be lost.

Scope: `controllers_providers.dart:65` (delete), `:81` (rename), `provisioning_service.dart:206` (add),
`wled_manual_setup.dart:144` (add) — all four take `FirebaseAuth.instance.currentUser.uid` where they
should take `effectiveUserUidProvider`. 2 of 20 `effectiveUserUidProvider` references live in this feature
area, which is the measure of the gap.

### Stage 1 — shared resolver + `effectiveUserUid` (MIXED: client + `functions/`)

- ~~Fix the four `currentUser` call sites~~ — **DONE** (client only, shipped first; see #96).
- Build the resolver spec, the conformance fixture, and both implementations.
- Repoint `controllers_providers` → `defaultForUi()`, `voice/deviceResolver` → `primaryForExternalBinding()`,
  `planGameDayFires` → `primaryForExternalBinding()` (**R-3 decided: no coverage widening; that is #97**).
- Invert `selectedControllerIdProvider` to select by id and resolve the IP (row 17).
- Convert `zones[]` from raw IPs to controller ids with resolve-at-use (row 6). **This needs a backfill** —
  flag as its own sub-stage with the usual rules→backfill→dual-write ordering.
- Seed `voicePrimaryControllerId` (§3.2) without changing SYNC output.

**Touches `functions/`** → deploy discipline applies. Also: **#94 must land first** (Node 20 decommissioned
2026-10-30, all 45 functions become undeployable), and **#93's predeploy hook lands with #94** — without it
`firebase deploy` uploads whatever sits in `functions/lib/` and prints `Deploy complete!` regardless. Any
functions work in this arc assumes Node 22 and a predeploy hook. Verify the deployed SHA is an ancestor of
`main` before deploying, per the +74 join-regression lesson.

### Stage 2 — cascade delete + orphan reaping (MIXED)

- Cascade `pixelMap/*` on controller delete, so the `system_management_screen` dialog's promise becomes
  true.
- Reap orphaned `controller_health/{cid}` docs whose controller no longer exists.
- Reap `pixelMap` subcollections already orphaned by past deletes.
- Introduce the `retired: true` tombstone convention and teach `resolveControllers` to filter it (per
  **R-2**).

**Note:** reaping is a natural fit for `scheduledDataCleanup`, but that function already carries a known
risk — unbounded `suggestions`/`ai_usage` queries can abort a run at >500 docs/user (C5). Adding two more
unbounded queries would compound it. Either page the queries or give reaping its own function.

**Ships before Stage 3 deliberately:** the replace callable *consumes* the cascade rather than
reimplementing it, and the reaper cleans up the mess that already exists in production from past deletes.

### Stage 3 — the replace callable + UI (MIXED)

Everything in §2. Depends on Stage 1 (so M4 is an id swap, not an IP swap; so M9 has a field to rewrite)
and Stage 2 (so retirement can cascade).

Sub-sequence within the stage: callable + unit tests against a fake Firestore first (the shape
`migrateInstallerControllersToCustomer` established as `@visibleForTesting` with an injectable `firestore`),
then the UI, then bench verification on real hardware with a real second controller. **The bench rig has two
controllers (`.150` and the home unit), so this is physically verifiable** — and it must be, because the
un-arm step (§2.5) cannot be proven against a fake.

Answer **R-1** and **R-4** before this stage ships.

### Stage 4 — bridge IP reconciliation (`functions/` + optional firmware)

§4. Kill the `"primary"` sentinel, ensure universal `controllerIp`, sweep for other addressless writers
(**R-5**). Firmware cleanup optional and deferred.

Could technically ship earlier — it is independent of the replace flow — but it depends on the shared
resolver to know *which* controller `"primary"` meant, so it sits after Stage 1. If Stage 3 slips, Stage 4
should ship anyway: it fixes silent voice misfires for every multi-controller home today, replacement or
not.

### Stage summary

| Stage | Client | `functions/` | Firmware | Blocked on |
|---|---|---|---|---|
| 0 — file the defect | — | — | — | nothing |
| 1 — resolver + uid fix | ✅ | ✅ | — | #94 (+#93) for the functions half |
| 2 — cascade + reap | ✅ | ✅ | — | Stage 1 (tombstone filter) |
| 3 — replace callable + UI | ✅ | ✅ | — | Stages 1, 2; R-1, R-4 |
| 4 — bridge reconciliation | — | ✅ | optional | Stage 1; R-5 |

The client half of Stage 0/1 can ship without touching `functions/` at all, which means **useful progress
is available even while #94 is outstanding.**

---

## 6. Decisions and open sweeps

**Decided 2026-08-18.** These are settled; implement to them.

| id | Decision |
|---|---|
| R-1 | **YES** — an already-paired, unowned controller is eligible as the successor. |
| R-2 | **Tombstone** (`retired: true`). Never a live orphan. Every resolver filters it. |
| R-3 | **Stage 1 uses `primaryForExternalBinding()` for `planGameDayFires`** — deterministic and tombstone-aware. **Do NOT widen to all-controllers in this arc.** The coverage defect is filed separately as **#97** with the census evidence, and is not to be started yet. |
| R-6 | **Stamp** `roofline_config/config` with the controller id it was migrated into, and refuse to re-migrate. |

**Open — must be answered by a read-only sweep, NOT from memory.** Both were explicitly ruled
un-closeable without looking:

| id | Sweep | Needed by |
|---|---|---|
| R-4 | Does the Alexa path have a proactive re-SYNC / proactive-state equivalent, and is it wired? Sweep `alexa-skill/`, `google-home/`. | **before Stage 3** |
| R-5 | Any command writer that omits `controllerIp`? Sweep `alexa-skill/`, `google-home/`, `scripts/`. The §4 writer list is **not** known to be complete. | **before Stage 4** |

---

## 7. Explicitly out of scope

- **#92** — the A4 monitoring-only migration stays unwired.
- **#93** — the predeploy hook is a *dependency* of any functions work here, but it lands with #94 in its
  own session, not in this arc.
- **#94** — Node 20→22. Lands first. All functions work in this arc assumes Node 22.
- **#TD-1** — schedules→subcollection migration. Replacement re-syncs timers to hardware (M7); it does not
  touch where schedules are *stored*.
- **Bridge replacement.** This arc is WLED *controller* replacement. Swapping the ESP32 bridge is a
  different operation against `bridge_registry`, and the census found it partly handled already (the
  newest-`lastSeen` tie-break at `collectControllerHealth.ts:206-214`). Worth its own doc.
- **Multi-controller replacement in one operation.** One predecessor, one successor. Batch RMA is a
  later concern.
