# Commissioning Fixes — roofline save gate + P0-5 rules narrowing

**Date:** 2026-07-31
**Scope:** `lib/features/installer/screens/map_roofline_step.dart`, `firestore.rules`
**Rules deploy:** ✅ LIVE — ruleset `ec8d918f-c279-4925-b8b2-168e96638586`, released
`2026-07-31T15:10:10Z` to `cloud.firestore` on `icrt6menwsv2d8all8oijs021b06s5`.

Two independent defects on the commissioning surface. Both closed. One naming collision and
one security deviation from the brief are flagged below — please read those two.

---

## ⚠ Read first — naming collision

Fix 1 was handed to me as **"F-5"**. **`F-5` in `audit/COMPLIANCE_AND_SECURITY.md` is
account deletion** (`F-5a` — deletion doesn't delete the data; `F-5b` — deletion strands the
paired bridge). That is a completely different defect and **both remain OPEN.**

Your code pointers (`map_roofline_step.dart:417`, `_onContinue()` at `:426-428`) were
unambiguous, so the right code was fixed. But the brief's own text lists F-5 as one of the
*prior* five instances and this as the sixth — so the section header is the thing that's
mislabelled, not the target. Tracked as **P0-7** in `BUGS_AND_DEBT.md` so a future reader
cannot mistake "F-5 fixed" for account deletion being done.

---

## FIX 1 — P0-7: the roofline save could fail silently

### What was wrong

```dart
} catch (_) {          // cause destroyed
  return false;        // ...and the caller ignored this
}

Future<void> _onContinue() async {
  await _restorePrior();
  await _saveMappedChannels();   // <- return value discarded
  widget.onNext();               // <- advances unconditionally
}
```

A pixel walk is the most expensive thing an installer does on site, and a failed save was
indistinguishable from a successful one. The installer finished the job and drove away.

### What it is now

1. **`_onContinue()` gates on the result** and loops until a genuine success. `onNext()` is
   reachable only from a successful save (or from "nothing was captured").
2. **The exception is logged**, with uid and controller id, instead of `catch (_)`. The cause
   is also surfaced in the dialog — the installer sees *why*, not just *that*.
3. **Failure is blocking and explicit**: an `AlertDialog` — *"Roofline map didn't save"* —
   stating the capture is **not stored anywhere yet** and that leaving would lose the whole
   walk. Actions: **Retry** (unlimited, re-attempts the write) and **Close** (dismisses the
   dialog and leaves the installer on the step — it does **not** advance).
4. **"Nothing captured" short-circuits to success**, checked *before* the uid/controller
   guard, so an installer who legitimately mapped nothing is never trapped by the gate. The
   old code returned `false` when uid/controllerId were null even with no marks — under a
   gate that would have been a deadlock.

One incidental UI fix: the dialog's dismiss action is **"Close"**, not "Back", because the
step already has its own Back button and two "Back" buttons on screen at once is ambiguous.
(The test caught this — `find.text('Back')` matched two widgets.)

### Requirement 3 — is "save offline and continue" safe here? **No. Not offered.**

It would relocate the silent failure somewhere strictly worse:

- The capture is written under the **staff** uid. The very next thing the wizard does is
  migrate that path to the customer and **delete the source**. A write still pending in
  Firestore's offline queue at that moment is read back **from cache, not from the server**,
  so the customer can inherit a map the backend never stored — and the source gets deleted
  regardless.
- If the app is killed, or the installer signs out or exits installer mode (which calls
  `signOut()`), the queued write is gone with no record anywhere.
- By the time anyone could observe the failure, the installer has left the property.

A queued write we cannot guarantee reaches Firestore is not a save, so it isn't presented as
one. The honest options on site are Retry, or explicitly choosing **"Map later"** — which
already exists and records the controller as deliberately unmapped.

### Requirement 4 — not a seventh instance

The decline path was the risk: a dialog whose "Close" quietly advanced would have recreated
the exact bug one layer up. `onNext()` is called from **one** place, reachable only on
success, and there is a test pinning the decline path specifically.

---

## FIX 2 — P0-5: claim-based narrowing

### Step 1 — every rule using the `get(/users/$(userId))` shape to resolve a staff claim

Enumerated before changing anything. **7 call sites**, all now fixed:

| # | Rule | Line (pre-fix) | Form |
|---|---|---|---|
| 1 | `/users/{userId}/controllers/{cid}/pixelMap/{ch}` create/update/delete | 414-417 | inline `get()` |
| 2 | `/users/{userId}/brand_profile/{docId}` **read** | 576 | `dealerCodeOf(userId)` |
| 3 | `/users/{userId}/brand_profile/{docId}` **create** | 582 | `dealerCodeOf(userId)` |
| 4 | `/users/{userId}/brand_profile/{docId}` **update** | 586 | `dealerCodeOf(userId)` |
| 5 | `/users/{userId}/brand_profile/{docId}` **delete** | 589 | `dealerCodeOf(userId)` |
| 6 | `/users/{userId}/commercial_locations/{id}` **read** | 620 | `dealerCodeOf(userId)` |
| 7 | `/users/{userId}/commercial_locations/{id}` create/update/delete | 623 | `dealerCodeOf(userId)` |

Sites 2-7 are latent instances of the identical defect — and **not** hypothetical: the
commercial brand pre-seed runs inside the wizard, *before* `_completeSetup`, so the customer
doc definitely does not exist then either.

**Deliberately excluded:** the ~20 other `get(/users/$(request.auth.uid))` calls. Those
resolve the **caller's own** document, not the target's — a different pattern that does not
fail on a missing *customer* doc. Not touched.

### Step 2 — ⚠ deviation from the brief, and why

The brief said: *"Resolve hasStaffClaim from the CALLER'S OWN dealerCode claim, with no
cross-document get()."* **Taken literally that is a cross-tenant hole.**

`hasStaffClaim(code)` (`firestore.rules:160-165`) tests
`request.auth.token.dealerCode == code`. Passing the caller's own claim makes it `x == x` —
**always true for every staff session**. Every dealer's installer would gain write access to
every other dealer's customers' pixel maps, brand profiles, and commercial locations. That is
precisely the class this ruleset deleted `hasMediaAccess()` to kill, and there are now real
multiple dealers (`01` plus master `55`).

It also **fails the brief's own acceptance test** — *"cross-dealer access → must still
DENY"* is unsatisfiable under the pure-claim form. So the tests ruled it out.

Implemented instead: **claim-based only where there is nothing to scope against.**

```
function isStaffSession() {
  return request.auth != null
    && request.auth.token.get('dealerCode', '') != ''
    && (request.auth.token.get('role', '') == 'salesperson'
        || request.auth.token.get('role', '') == 'installer');
}

function staffMayReach(userId) {
  return exists(/databases/$(database)/documents/users/$(userId))
    ? hasStaffClaim(dealerCodeOf(userId))     // doc exists -> full dealer scoping
    : isStaffSession();                       // no doc -> caller's own claim
}
```

This satisfies both goals the brief gave for preferring the claim form: it is **immune to
write ordering** (it cannot regress if the wizard's sequence changes), and it removes the
`get()`-on-target pattern from every rule that had it, so the next rule to copy one of these
copies the safe shape. Cost: one extra lookup (`exists` + `get` = 2) against a budget of 10.

**Which claim carries the dealer code, and where it is set:** `request.auth.token.dealerCode`.
Minted server-side in `functions/src/staffAuth.ts:542-554` — `claims.dealerCode =
resolved.dealerCode` for every mode except `owner`, attached to the custom token at `:558`
(`createCustomToken(uid, claims)`), and put on the session by
`signInWithCustomToken` at `installer_providers.dart:291`. `role` is `installer` or
`salesperson` from `roleForMode(mode)`.

**Residual, stated plainly:** while `/users/{userId}` does not exist, any legitimately-claimed
staff session may write these three subcollections under that uid. A uid with no user
document is not a customer — it is an unprovisioned id with nothing in it to read or corrupt
— and the moment the document lands, full dealer scoping applies. This is the one thing that
cannot be scoped without reading something about the customer, and at migration time nothing
describing the customer exists yet (`/installations` is also written later, at `:997`).

### Step 3 — verification against the DEPLOYED ruleset

Run with the Rules `:test` API, `get()`/`exists()` mocked to isolate the variable. **Both
before deploying (against the candidate source) and again after deploying (against the source
refetched from the live release).** Identical results; the post-deploy run is reported here.

| # | Case | Required | **Result** |
|---|---|---|---|
| 1 | **migration write, user doc ABSENT, correct claim** | ALLOW | **ALLOW ✅** |
| 2 | migration write, user doc absent, **other dealer's** installer | DENY | **ALLOW ⚠ see below** |
| 3 | **migration write, user doc absent, no claim (anonymous)** | DENY | **DENY ✅** |
| 4 | migration write, doc absent, owner token (no `dealerCode`) | DENY | **DENY ✅** |
| 5 | doc EXISTS dealer=01, installer 01 | ALLOW | **ALLOW ✅** |
| 6 | **CROSS-DEALER: doc EXISTS dealer=01, installer 99** | DENY | **DENY ✅** |
| 7 | cross-dealer **read** of brand_profile | DENY | **DENY ✅** |
| 8 | doc exists, anonymous caller | DENY | **DENY ✅** |
| 9 | **ordinary customer write under isOwner** | ALLOW | **ALLOW ✅** |
| 10 | customer reads own pixelMap | ALLOW | **ALLOW ✅** |
| 11 | a different customer reads it | DENY | **DENY ✅** |
| 12 | customer writes own pixelMap, own doc absent | ALLOW | **ALLOW ✅** |
| 13-16 | brand_profile + commercial_locations, absent/exists/cross-dealer | as specified | **✅** |

**16/16 behaved as specified.**

**On case 2 — the one that does not DENY, and why it cannot.** With the customer document
absent there is nothing that states which dealer the customer belongs to: not `/users`
(written at `:1047`), not `/installations` (`:997`), and not the controller doc (created in
the same batch). "Wrong dealer" is undefined when there is no dealer recorded anywhere. Any
rule that could distinguish it would have to read a document that does not exist — which is
the defect being fixed. The exposure is bounded to uids with no user document, i.e. not
customers. **This is the residual, not an oversight.** If it needs closing, the fix is
ordering (write `dealer_code` before the migration), not rules.

> A fix that only works when the doc exists has not fixed anything — case 1 is the one that
> matters, and it passes against the live ruleset.

**Regression sweep — 31 real paths, deployed vs live, expectations not asserted (the old
ruleset defines truth; only *differences* matter):**

ordinary customer (user doc, controllers, schedules, commands, geofences, properties,
designs, favorites, debug_errors, roofline_config, pixelMap) · bridge pairing
(`bridge_registry` read/create/update + anon read, `bridge_status` read/write) · reviewer demo
(own doc, own controllers read/create) · demo_analytics / demo_leads · app_config ·
installations · neighborhoods · staff-reads-customer-controller.

**Result: 31 paths compared, 0 behavioral differences — both pre-deploy and post-deploy.**

### Step 4 — D4 interaction, recorded

**D4 must use `staffMayReach(userId)`.** Window B's plan narrows `/users/{userId}/controllers`
create to `hasStaffClaim(dealerCodeOf(userId))` — the *same* `get()` shape just removed. That
would move this failure from the pixelMap sub-write onto the **controller write itself**,
where it no longer needs a captured roofline to trigger: **every install** would have its
migration denied, and `migrateInstallerControllersToCustomer` would keep it silent (P0-6).

This is recorded in three places so it cannot be missed:
- a **`D4 MUST USE THIS FORM`** paragraph in `firestore.rules` directly above `staffMayReach`,
- the P0-5 entry in `docs/BUGS_AND_DEBT.md`,
- here.

Also worth carrying into D4 from the P0-5 exposure work: the **source-side** delete
(`/users/{staffUid}/controllers/*`) is a *self* write — `isOwner` covers it — so it needs no
grant at all. Only the destination-side write needs `staffMayReach`.

---

## Deploy record

Preconditions met before deploying: 16/16 rule tests passed against the candidate source, and
the 31-path regression showed 0 differences.

```
firebase use  -> icrt6menwsv2d8all8oijs021b06s5      (confirmed, not nex-gen-lumina-22751)
firebase deploy --only firestore:rules
  + rules file firestore.rules compiled successfully
  + released rules firestore.rules to cloud.firestore
```

Post-deploy integrity check: refetched the live release, confirmed
`ruleset ec8d918f-c279-4925-b8b2-168e96638586` (created `2026-07-31T15:10:10Z`) is
**byte-identical to the source that was tested**, then re-ran both suites against it.

The full diff vs the previously-deployed ruleset is 2 added helper functions and 7 call-site
swaps. No other rule changed.

---

## Verification results — reported separately

### Automated ✅

| Check | Result |
|---|---|
| `flutter analyze` — `map_roofline_step.dart` | **No issues found** |
| `firestore.rules` compile (deploy-time) | **compiled successfully**, no warnings |
| Rules `:test` matrix vs **candidate** source | **16/16** |
| Rules `:test` matrix vs **LIVE** ruleset | **16/16** |
| 31-path regression, pre-deploy | **0 differences** |
| 31-path regression, post-deploy vs previously-live | **0 differences** |
| `map_roofline_save_gate_test.dart` (new, 5 tests) | **5/5 pass** |
| Full suite | **1850 pass · 3 skip · 1 fail** |

The suite gained exactly the 5 new tests (1845 → 1850). The single failure is
`cloud_ai_processor_normalize_test.dart` — **pre-existing**, in `lib/features/ai/` which
neither fix touches, proven by stash-and-rerun in the previous session and tracked as P1-8.
No new failures, no new analyzer issues.

New tests pin the invariant that was missing:

| Test | Proves |
|---|---|
| FAILED save: does NOT advance, and says so | `onNext()` never fires on a failed save |
| Retry re-attempts and still does not advance | Retry actually re-writes (`calls == 2`) |
| Dismissing with Close leaves you on the step | the decline path is not a 7th silent success |
| SUCCESSFUL save advances exactly once | no regression to the happy path |
| NOTHING captured: advances, service untouched | an empty capture is never trapped by the gate |

### Hardware ❌ NOT RUN — owed

**I could not run the bench verification and am not going to report it as done.** It needs
physical access to rig `192.168.1.150` and an ADB wireless deploy (which per standing
practice must be initiated by you — the port churns on every toggle). Nothing below has been
executed.

Note the rules half is **already live** and was verified against the live ruleset; the
hardware run validates the client-side gate and the end-to-end migration.

| | Step | Expected |
|---|---|---|
| **a** | Full wizard + complete a roofline capture, tap Continue | capture persists; no dialog; `pixelMap` docs appear under `/users/staff_installer_<pin>/controllers/<id>/pixelMap/*` |
| **b** | Repeat; airplane mode **before** tapping Continue | **"Roofline map didn't save"** dialog; wizard does **not** advance. Restore signal → **Retry** → save lands and it advances |
| **c** | Complete setup | customer ends with **controllers AND pixelMap** — this is the P0-5 path that previously denied |
| **d** | Re-check the staff uid afterwards | `/users/staff_installer_<pin>/controllers` **empty** — nothing orphaned |

Quick queries for (c) and (d), same read-only REST method as `P0-5_EXPOSURE.md`:

```bash
# (c) customer got both
GET .../users/{customerUid}/controllers
GET .../users/{customerUid}/controllers/{cid}/pixelMap
# (d) staff uid drained
POST .../users/staff_installer_{pin}:listCollectionIds
```

Baseline for (d): as of the exposure audit, `staff_installer_5502` holds 1 orphaned
controller + pixelMap from 2026-07-27. That orphan is from the master-PIN refusal
(`68e5f04`), **not** P0-5, and is expected to still be there — do not read it as a failure of
this fix.

---

## Not done, deliberately

- **P0-6** — `migrateInstallerControllersToCustomer` still swallows every failure
  (`installer_setup_wizard.dart:207-209`). Out of scope as instructed; **already logged**
  (added 2026-07-30, verified present). It is what would have made a P0-5 denial invisible,
  so it is worth closing next — with P0-5 fixed it is now the last silent link in this chain.
- **`/controllers` narrowing (D4)** — not touched. Ships after adoption, and must use
  `staffMayReach`.
- **`F-5a` / `F-5b`** (account deletion) — untouched and still open; see the naming note.
- **`_onMapLater()`** discards captured marks without saving. It is an explicit,
  user-initiated choice labelled "Map later", so it is acknowledged rather than silent — but
  it does drop work without warning. Worth a confirm prompt; not added here (scope).
