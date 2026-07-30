# HANDOFF TO WINDOW B — Firestore rules / isolation

**From:** Window A (feature exists-vs-works tracing)
**Date:** 2026-07-30
**Status:** ABANDONED MID-CHAIN. Window A was out of charter and stopped on instruction.
This is a verbatim dump, not a cleaned-up writeup. Verify everything independently —
none of this was carried to a confirmed conclusion.

---

## HYPOTHESIS I WAS TESTING

That an ordinary authenticated Lumina customer account can (a) harvest other users'
UIDs, and then (b) read, overwrite, and DELETE those users' controller registrations
and profile documents — making it a cross-tenant data-loss + privacy breach rather
than a theoretical rule looseness.

I confirmed the write grants. I did NOT confirm the UID harvest step. The whole
severity call hinges on that unconfirmed step.

---

## EVIDENCE COLLECTED (verbatim, file:line)

### 1. `/users/{userId}` — cross-tenant UPDATE is open

`firestore.rules:355-360`:

```
      allow update: if ((isOwner(userId) &&
                      cannotModifyCriticalFields() &&
                      isValidDealerEmail(request.resource.data.get('dealer_email', null)))
                    || request.auth != null)
                    && (!elevatesRole() || hasAdminOrOwnerClaim())
                    && (!reassignsDealerCode() || hasAdminOrOwnerClaim());
```

Note the paren grouping: `cannotModifyCriticalFields()` sits INSIDE the first
disjunct only. The `|| request.auth != null` branch bypasses it entirely. So the
owner_id / id / email immutability guard defined at `firestore.rules:103-107` does
not constrain a non-owner caller.

Same structure on create, `firestore.rules:344-350`.

READ on the user doc is NOT broadly open — `firestore.rules:263-268` is scoped to
`canReadUserData() || hasAdminOrOwnerClaim() || isDealerStaffAccount(...) ||
installer/salesperson claim with matching dealerCode`. `canReadUserData` is
`isOwner(userId) || isMediaOrAdmin()` at `firestore.rules:88-90`. This is why the
attack needs a UID from somewhere else — the attacker can write but not enumerate.

**Why this matters for data loss specifically:** the `schedules` array is still
stored as a field ON the user doc. Comment at `firestore.rules:426-432`:

```
      // Schedules are ALSO still stored as the `schedules` array field on the
      // user doc (governed by the user-doc update rule above); this rule covers
      // only the per-schedule documents.
```

So a cross-tenant user-doc write can clobber another user's entire schedule array.

The file itself documents the broad grant as known and deliberate —
`firestore.rules:288-292`:

```
      // WHY THE BROAD GRANT STAYS: the installer wizard writes the
      // customer's user doc under an ANONYMOUS session — it calls
      // signInAnonymously() (installer_setup_wizard.dart:731) right
      // after creating the customer's auth account, then
      // set(merge:true) at :937.
```

and calls the fix "the P1 structural fix (re-mint the staff token instead of going
anonymous)". I did NOT verify those installer_setup_wizard.dart line numbers.

### 2. `/users/{userId}/controllers/{controllerId}` — full cross-tenant CRUD

`firestore.rules:383-395`:

```
        allow read: if canReadUserData(userId) || request.auth != null;
        allow create: if request.auth != null;
        allow update: if isOwner(userId) || request.auth != null;
        allow delete: if isOwner(userId) || request.auth != null;
```

All four verbs collapse to "any authenticated user". Delete is the data-loss verb.
Documented as intentional for the installer wizard's anonymous-UID controller
migration (`firestore.rules:377-382`, `:392-394`).

Contrast with the nested `pixelMap` rule immediately below at
`firestore.rules:412-419`, which is explicitly hardened and whose comment
(`firestore.rules:398-411`) says the broad pattern "caused the neighborhoods outage
class and is banned for new rules". The ruleset is internally inconsistent about
whether this pattern is acceptable.

### 3. UNCONFIRMED — the UID harvest step

`/bridge_registry/{deviceId}` at `firestore.rules:677`:

```
      // Any signed-in user can read so the discovery flow can list
      // unpaired bridges and look up a specific bridge by deviceId.
      allow read: if request.auth != null;
```

`allow read` covers both `get` and `list`, and there is no query-shape constraint —
so on the face of it any authenticated client can list the entire collection.

Registry docs appear to carry a `pairedUid` field — referenced at
`firestore.rules:657-660` inside `isNotBlockedDeletedUid()`:

```
      function isNotBlockedDeletedUid() {
        return !(request.resource.data.get('pairedUid', '') in [
          'xBnFxkN6ScRueZRgWxRnzGKsVMt2',
          'ASeUR5nnqtYAui1XRkaQu2iqxkI2',
        ]);
      }
```

**IF** bridge_registry docs are listable AND carry `pairedUid`, that is a UID
harvest for every paired customer, which chains into findings 1 and 2 and makes
this a P0 with a concrete mechanism. **I never verified this.** The exact command
I was about to run when stopped:

```
grep -rn "bridge_registry" --include=*.dart lib/
grep -rn "bridge_registry" --include=*.js functions/
```

to determine the actual written field set and whether any client does an unfiltered
`.collection('bridge_registry').get()`.

### 4. Two real customer UIDs are hardcoded in the ruleset

`firestore.rules:658-659` — `xBnFxkN6ScRueZRgWxRnzGKsVMt2` and
`ASeUR5nnqtYAui1XRkaQu2iqxkI2`, described in the comment above them
(`firestore.rules:650-656`) as belonging to Ellie's bridges. firestore.rules is
committed to the repo. Whether that matters is your call; flagging it because the
comment marks the block TEMPORARY and it has survived since 2026-05-27.

### 5. Lower-priority things I noticed but did not chase

- `firestore.rules:884`, `:903`, `:929` — `allow write: if request.auth != null`
  on `analytics/**/users/{hashedUserId}`, `/raters/{hashedUserId}`,
  `/voters/{hashedUserId}`. Read is `if false`, so it's blind-write vandalism of
  aggregate stats, not a read breach.
- `firestore.rules:1346-1349` — `/demo_leads/{leadId}` has `allow create: if true`,
  `allow get: if true`, `allow update: if true`, unauthenticated. The comment at
  `firestore.rules:1327-1344` explains this as a deliberate capability-URL pattern
  (unguessable ~120-bit auto-ID) and `list` IS correctly restricted to
  `hasAdminOrOwnerClaim()`. The residual is that `allow update: if true` lets
  anyone who ever learns a lead ID overwrite that prospect's record. Looked
  reasoned, low impact, did not pursue.
- `firestore.rules:1323` — `/dealer_demo_codes` `allow read: if true`,
  unauthenticated. Presumably intended (pre-auth code validation).

---

## WHAT I DID NOT DO

- Did not run the emulator suite. There is emulator test coverage in the repo —
  commit `69f2678` mentions `config/sync_fanout` emulator tests — so there may be
  an existing harness you can extend to settle finding 3 empirically.
- Did not check `storage.rules` (14 lines, unread).
- Did not audit the remaining ~1400 lines of firestore.rules. My grep for
  permissive patterns returned 34 hits (`allow ... if true` / `if request.auth !=
  null` bare); I only examined about 8 of them. The unexamined hits were at lines
  389, 546, 550, 709, 872, 937, 940, 948, 960, 1225, 1424, 1451, 1470, 1488, 1502,
  1546, 1553, 1558, 1559, 1751, 1775, 1839, 1919.

## SEVERITY — DELIBERATELY NOT ASSIGNED

Findings 1 and 2 are confirmed-as-written but their real-world severity depends
entirely on finding 3, which is unverified. Per the audit's own rule that P0
requires a concrete named mechanism, I am not assigning a tier. That call is yours.
