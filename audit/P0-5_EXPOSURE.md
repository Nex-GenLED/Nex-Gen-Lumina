# P0-5 Live-Exposure Check

**Date:** 2026-07-31
**Type:** diagnostic, read-only. Nothing fixed, no branches, no writes to Firestore.
**Method:** Firestore REST reads via `gcloud` ADC (`honeycutt.tylerg@gmail.com`), project
`icrt6menwsv2d8all8oijs021b06s5`; plus **Firebase Rules `:test` evaluation** against the
**deployed** ruleset.

---

## VERDICT (up front)

> **The mechanism is REAL and CONFIRMED. Customer harm to date is ZERO.**
>
> **P0-5 is LIVE-BUT-UNTRIGGERED — not false, not merely theoretical.** The rule denies
> exactly as claimed (proven against the deployed ruleset, below). But the precondition
> that triggers it — a `pixelMap` present at migration time on a **first-time** install —
> has occurred **once** in the entire production history, and that one occurrence was
> masked by an accidental double-run of the install.
>
> **Accounts currently harmed: 0 of 12.** No customer has a captured roofline and zero
> controllers. No customer is missing controllers at all.
>
> **Why it hasn't bitten:** roofline capture during the wizard is essentially never
> completed on a first-time install. Every pixelMap in production was captured **weeks to
> months after handoff** by the account owner — a path governed by `isOwner`, which never
> touches the failing rule branch.

The claim in `TOKEN_REFRESH_REPORT.md` that this may be "already live" is **correct as to
mechanism and wrong as to blast radius**. It is a loaded gun, not a fired one.

---

## 1. Firestore evidence — all 20 user documents

20 user docs. 13 `/installations` docs → **12 distinct** installed customers
(`Aj8lQ1hf…` appears twice — see §4). Every installed customer has ≥1 controller.

| UID | email | dealer | ctrl | pixelMap | user doc created |
|---|---|---|---|---|---|
| `5oHhaEaf…` | ecochran08@yahoo.com | 55 | 1 | 1 | 2026-05-29 |
| `Aj8lQ1hf…` | dbrosa99@icloud.com | 55 | 1 | 1 | 2026-07-16 |
| `Ayf0rqwN…` | textim6@yahoo.com | 55 | 1 | 2 | 2026-06-04 |
| `EHRfYGyf…` | cpaschall10@gmail.com | 55 | 1 | 1 | 2026-05-13 |
| `KOerj0ui…` | nex-genadmin@nex-genled.com | **01** | 1 | 0 | 2026-07-27 |
| `NmDukd5r…` | jjdyer1@hotmail.com | 55 | 1 | 1 | 2026-06-19 |
| `Pqptfawp…` | dnicholas0131@gmail.com | 55 | 1 | 0 | 2026-05-13 |
| `Q8VIQ9lr…` | brooke.rozenberg1@gmail.com | 55 | 1 | 2 | 2026-05-13 |
| `VzgTsg31…` | thegruenewalds@gmail.com | 55 | 1 | 0 | 2026-05-16 |
| `YcSGiwes…` | stegall.s@yahoo.com | 55 | 1 | 1 | 2026-05-07 |
| `j8eXTfcs…` | marc@tapsonmain.com | 55 | 1 | 2 | 2026-06-24 |
| `wrQRUUKy…` | tyler.honeycutt@nex-genled.com | 55 | 1 | 1 | 2026-05-28 |
| `staff_installer_5502` | — (staff) | — | **1** | **1** | 2026-05-27 |
| `staff_owner_5500` · `staff_admin_5503` | — (staff) | — | 0 | 0 | — |
| `44wgtFsB…` | — | — | 0 | 0 | 2026-06-24 (`suggestions` only) |
| `FmWqKQgm…` · `bPMLAyHv…` | — | — | 0 | 0 | 2026-07-16 (see §4) |
| `xD1H2EYn…` | — | — | 0 | 0 | 2026-07-27 |
| `reviewer-demo-account-001` | reviewer@nexgenled.com | — | 0 | 0 | 2026-03-09 |

### THE SIGNAL — searched for, not found

- **A customer with a captured pixelMap and zero controllers: NONE.**
- **A customer missing controllers entirely: NONE.** All 12 installed customers have one.
- The four zero-subcollection docs (`44wgtFsB`, `FmWqKQgm`, `bPMLAyHv`, `xD1H2EYn`) are
  **not** failed installs — none appears as a `primary_user_id` in `/installations`.
  `FmWqKQgm` and `bPMLAyHv` are anonymous-session docs carrying **only** `fcmToken` +
  `referralCode`, both with the *same* FCM token (one physical device), written by
  `sync_notification_service.dart:211` (`set(..., merge:true)`, which creates the doc).
  They are anonymous sessions from the staff-PIN screen, not customers.

### The decisive timestamps

This is what settles the question. pixelMap creation vs. the install:

| customer | install | pixelMap created | lag |
|---|---|---|---|
| `YcSGiwes…` | 2026-05-07 | 2026-07-03 | **+57 days** |
| `Q8VIQ9lr…` | 2026-05-13 | 2026-07-18 | **+66 days** |
| `EHRfYGyf…` | 2026-05-13 | 2026-07-03 | **+51 days** |
| `5oHhaEaf…` | 2026-05-29 | 2026-07-03 | **+35 days** |
| `Ayf0rqwN…` | 2026-06-04 | 2026-07-28 | **+54 days** |
| `NmDukd5r…` | 2026-06-19 | 2026-07-04 | **+15 days** |
| `j8eXTfcs…` | 2026-06-24 | 2026-07-03 | **+9 days** |
| `wrQRUUKy…` (Tyler's own) | 2026-05-28 | 2026-07-20 | +53 days (owner session) |
| **`Aj8lQ1hf…`** | **2026-07-16 17:30:57** | **2026-07-16 17:31:05** | **+8 SECONDS** |

**Eight of nine pixelMaps postdate their install by 9–66 days.** They were written by the
account owner long after handoff, under `isOwner(userId)` — the short-circuit branch that
never evaluates the failing `get()`. Those writes never went near the migration path.

**Exactly one pixelMap in production has ever been written at migration time**: `Aj8lQ1hf`.
See §4.

---

## 2. Where did orphaned maps land?

Swept every plausible `staff_*` uid — including uids with **no parent document**, since
Firestore allows subcollections under a missing parent and a `list` on `/users` would not
reveal them:

| staff uid | controllers | subcollections |
|---|---|---|
| **`staff_installer_5502`** | **1** (+1 pixelMap) | commands, controllers, debug_errors, roofline_config, suggestions |
| `staff_installer_0101` | 0 | none |
| `staff_owner_5500` | 0 | debug_errors |
| `staff_admin_5503`, `staff_installer_55`, `staff_sales_5501`, `staff_installer_0100/0102` | 0 | none |

**Exactly one orphan exists — and it is NOT a P0-5 casualty.**

`staff_installer_5502` = mode `installer`, PIN `5502` = dealer **55** + installer **02** —
the master support PIN, and the uid behind **12 of the 13** historical installs.

Its orphaned controller `80_f3_da_b3_76_64` + pixelMap were created **2026-07-27
16:07:38/39**. The dealer-01 install (`KOerj0ui`) completed **16:43:42**, 36 minutes later,
under `staff_installer_0101` — which is now **empty**, i.e. its migration ran and cleaned up.

The explanation is the master-PIN refusal, `68e5f04` *"refuse the reserved master PIN for
customer installs"*, dated **2026-07-16**. By 2026-07-27 that guard was in the shipped
build. Reconstruction: Tyler entered master PIN 5502, added a controller, walked the
roofline, tapped Complete Setup, and was **refused before any Firebase work** — exactly as
`installUsesReservedDealerCode` intends. He re-entered with his real dealer PIN 0101 and
completed the install. The 5502 artifacts are the abandoned first attempt.

Note this orphan was left by a guard **working correctly**, and it is inert: it belongs to a
staff uid, not a customer.

---

## 3. The rule, re-read precisely — and executed

### Deployment state: NO DRIFT

Given this project's history of rules drift, I compared bytes rather than trusting the repo.

- Deployed ruleset: `6333afad-5add-4fbb-9652-124d1e21de80`, created **2026-07-25T18:19:43**,
  2027 lines, released to `cloud.firestore`.
- Repo `firestore.rules`: 2026 lines.
- **`diff` after normalizing CRLF → 0 changed lines. Deployed == repo, byte-identical.**

(The raw diff first showed all 4052 lines differing — a pure line-ending artifact.)

### Does `get()` on a missing document actually deny?

I did not assert this — I executed it via the Firebase Rules `:test` API against the
deployed source, mocking `get()` to isolate the variable:

| # | `get(/users/{C})` resolves to | expected | **result** |
|---|---|---|---|
| A | doc exists, `dealer_code == '01'` (matches claim) | ALLOW | **ALLOW ✓** |
| B | doc exists, `dealer_code == '99'` (other dealer) | DENY | **DENY ✓** |
| C | **`null` — the missing-document case** | DENY | **DENY ✓** |

Case C's engine message:

```
Error: firestore.rules line [416], column [18]. Null value error.
```

Case A is what makes this conclusive: the identical code path **allows** when the document
exists. So case C's denial is caused specifically by the **absent document**, not by the
rule being broken or the test sandbox lacking a data layer.

Supporting run, without mocks, on real paths:

| case | result |
|---|---|
| pixelMap dest write, customer doc missing | **DENY** (`Function not found error: Name: [get]`) |
| controller dest write, customer doc missing | **ALLOW** — the broad `request.auth != null` grant at `:389` |
| pixelMap **source** delete under own staff uid | **ALLOW** — `isOwner` |
| controller **source** delete under own staff uid | **ALLOW** — `isOwner` |

### Answers to the three sub-questions

1. **Does `get()` on a missing doc deny, or is there a permitting fallback?**
   It **denies**. `dealerCodeOf`/the inline `get()` at `firestore.rules:416` evaluates
   `null.data` → `Null value error` → the `allow` fails. There is **no fallback branch**:
   the only other disjunct is `isOwner(userId)`, which is false for a cross-uid write.
   `hasStaffClaim` itself (`:160-165`) is fine — it never gets a value to test.

2. **Is the pixelMap write in the SAME batch as the controller write?**
   **Yes.** `installer_setup_wizard.dart:184-204` — one `firestore.batch()`; the loop does
   `batch.set(destCol…)` / `batch.delete(sourceCol…)` for the controller **and**
   `batch.set(…/pixelMap/…)` / `batch.delete(…/pixelMap/…)` for each channel, then a single
   `batch.commit()`. Batched writes are atomic, so one denied write fails **all** of them —
   including the plain controller write that would otherwise be allowed.

3. **Any other rule branch that could permit it?**
   **No.** No recursive `{document=**}` matcher exists anywhere in the ruleset (`grep` →
   zero hits), so the permissive parent `match /controllers/{controllerId}` rules do **not**
   cascade to the `pixelMap` subcollection. `match /pixelMap/{channelId}` (`:412-418`) is the
   only rule governing that path.

**The theory holds on the rules as deployed.**

---

## 4. Reconciling with reality — the explanation

The prompt's framing was right to demand this: if every pixelMap-carrying install silently
failed, customers would have called. Here is what actually happened.

### The primary answer: capture-at-install has essentially never happened

Of the three candidate explanations offered — theory wrong / capture rarely completed /
something recreates controllers — the answer is **"pixel-walk capture is rarely completed
during the wizard."** And it is stronger than "rarely": in the entire production history,
**a pixelMap has been present at migration time exactly once.**

The `+9` to `+66` day lags in §1 are the proof. Roofline maps are being captured **after
handoff, by the account owner**, not by the installer during the wizard. That path is
`isOwner(userId)` → the first disjunct → short-circuit → the failing `get()` is never
evaluated. Design Studio Slice 2's *wizard* capture is the feature that would trigger P0-5,
and it has not been used on a real first-time install.

So there is nothing to reconcile for 11 of 12 customers: their migration batches contained
**only** controller set+delete, both permitted, and succeeded.

### The one exception — `Aj8lQ1hf` (Darian Brosa), 2026-07-16

This is the only install-time pixelMap migration, and it is worth reading closely.

| time | event |
|---|---|
| 17:30:57 | `/installations` doc #1 created · `/users/Aj8lQ1hf` **created** |
| **17:31:05** | controller `80_f3_da_b4_d1_50` **and** its pixelMap created under the customer |
| 17:31:06 | `/installations` doc #2 created · user doc updated (`created_at` field rewritten to 17:31:06) |

Two `/installations` docs, same `primary_user_id`, 9 seconds apart — **the install ran
twice.** The user doc's Firestore `createTime` (17:30:57) precedes its own `created_at`
field value (17:31:06), which is the signature of run #1 creating it and run #2 overwriting
it with a fresh payload.

The controllers migrated at **17:31:05 — during run #2**, and run #2's migration was
permitted **because run #1 had already created `/users/Aj8lQ1hf` eight seconds earlier**,
so the rule's `get()` resolved (case A above).

**Run #1's migration is the probable live P0-5 firing.** Run #1 demonstrably reached the
migration (it went on to write the `/installations` doc at `:997` and the user doc at
`:1047`, both downstream of `:933`), and at that moment `/users/Aj8lQ1hf` did not yet exist.
The pixelMap that moved at 17:31:05 must already have existed under the staff uid — nobody
walks a roofline in the 8-second gap. A denied, swallowed batch in run #1 exactly explains
why the controller did not appear under the customer until run #2.

**Confidence: high, but inferential — not proof.** The competing explanation is that run #1
had an empty `selectedControllers` set and simply had nothing to migrate. I cannot separate
these from timestamps alone. Client-side rules denials are **not** recorded in Cloud Audit
Logs (checked: `cloudaudit.googleapis.com/data_access` exists but captures no Firestore
rule rejections from client SDKs), so there is no server-side record to settle it.

Either way the customer was made whole by the re-run, and holds controllers today.

### What did *not* explain it

- **Nothing recreates controllers afterwards.** There is no auth `onCreate` trigger and no
  repair job. `assignReferralCode` is a *Firestore* `onCreate` on `/users/{uid}` — it fires
  after the doc exists and only writes `referralCode`. `createCustomerAccount.ts` is a
  separate, unrelated path.
- **The user doc is not pre-created on customer sign-in.** The only incidental
  `/users/{uid}` creator is the FCM token writer (`sync_notification_service.dart:211`), and
  `Aj8lQ1hf` carries no `fcmToken` — so that is not what created it at 17:30:57.

---

## 5. Verdict

**P0-5 is LIVE as a defect, LATENT as an incident.**

| Question | Answer |
|---|---|
| Is the rule mechanism real? | **Yes — proven** against the deployed ruleset (`Null value error`, line 416) |
| Is the ordering real? | **Yes** — migration `:933`, customer user doc `:1047`; nothing else creates it |
| Is the batch atomic? | **Yes** — one `batch.commit()`; the pixelMap denial takes the controller write with it |
| Is the failure silent? | **Yes** — swallowed at `:207-209`, install reports success |
| Accounts harmed today | **0** — named: none. No customer lacks controllers |
| Probable live firings | **1**, high-confidence inference: `Aj8lQ1hf` run #1, 2026-07-16 — self-healed by an immediate re-run |
| Orphaned staff data | **1**: `staff_installer_5502` (1 controller + 1 pixelMap, 2026-07-27) — caused by the master-PIN refusal `68e5f04`, **not** P0-5 |

### Why this still matters

The exposure is **entirely in front of us, not behind us.** The reason P0-5 has cost nothing
is that installers have not been completing roofline capture during installs. That is
precisely the workflow Design Studio Slice 2 exists to enable — so the first install that
uses the feature as designed is the one that silently hands a customer no controllers.

It also compounds with the pending D4 work: **D4 makes it strictly worse.** Narrowing the
`/controllers` `create` rule to the same `get()`-based `hasStaffClaim` shape would move the
failure from the pixelMap sub-write to the **controller write itself** — so it would no
longer require a captured roofline to trigger. Every install would fail the migration, and
`:207-209` would keep it silent.

### On R-4

I could not locate the marketing register or an `R-4` entry in the repo (`audit/`, `docs/` —
the only `R-4x` items are `R-40`/`R-41` in `BUGS_AND_DEBT.md`, an unrelated series), so I am
not going to characterize the claim's wording. On substance: if R-4 promises installer-side
roofline mapping delivered to the customer at handoff, that capability is **carrying an
unfired defect** — it works only when the customer doc happens to already exist, which today
means only on a repeat install.

### Recommended (not done — diagnostic only)

Ordering is the fix, and it is independent of D4: either migrate **after** the `:1047`
user-doc write, or write the customer doc (at minimum `dealer_code`) before `:933`. Either
makes the `get()` resolve and closes the class. Separately, `:207-209` should stop swallowing
— that is what turned a permission error into a silent handoff (tracked as **P0-6**).

**Do not deploy D4 before the ordering is fixed.**

---

## Reproduction

```bash
# 1. Inventory (read-only)
gcloud auth application-default print-access-token
GET  /v1/projects/icrt6menwsv2d8all8oijs021b06s5/databases/(default)/documents/users
POST .../users/{uid}:listCollectionIds          # subcollections, incl. missing parents
GET  .../users/{uid}/controllers/{cid}/pixelMap # createTime is the evidence

# 2. Deployed rules — verify no drift
GET  https://firebaserules.googleapis.com/v1/projects/{proj}/releases
GET  https://firebaserules.googleapis.com/v1/projects/{proj}/rulesets/{id}
tr -d '\r' before diffing, or every line reports as changed

# 3. Execute the rule (read-only, no data touched)
POST https://firebaserules.googleapis.com/v1/projects/{proj}:test
     functionMocks: get(/users/{C}) -> {value:{data:{dealer_code:'01'}}}  => ALLOW
     functionMocks: get(/users/{C}) -> {value:null}                       => DENY
```

Scripts used: `scratchpad/p05_probe.py`, `scratchpad/rules_test.py`, `scratchpad/rules_test2.py`.
