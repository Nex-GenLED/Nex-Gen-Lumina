# Token Refresh + Anonymous-Fallback Instrumentation

**Date:** 2026-07-30
**Scope:** `lib/` only. `firestore.rules` deliberately untouched — that is D4.
**Purpose:** make the installer wizard a genuine `hasStaffClaim` caller, and turn
"did every dealer update?" into an observation that gates the D4 rules deploy (S-5).

Baseline: `main` @ `c20ed83`, `2.5.10+59` (which shipped **without** this change).

---

## Part 1 — The residual, resolved: the uids **do not diverge**

> **Question (from Window B):** does the staff-token uid equal `fromUid` for the
> source-side `batch.delete`?
>
> **Answer: YES — and not by coincidence. They are the same uid by construction.**
> The narrowing plan's assumption holds. No design change, no re-estimate.

### The chain, from code

| # | Event | `FirebaseAuth.currentUser.uid` |
|---|---|---|
| 1 | `StaffPinScreen.initState` → `_ensureAuthSession()` → `signInAnonymously()` <br/> [staff_pin_screen.dart:141](../lib/features/auth/staff_pin_screen.dart#L141) | random anon `A` |
| 2 | PIN accepted → `mintStaffToken` → `signInWithCustomToken(token)` <br/> [installer_providers.dart:291](../lib/features/installer/installer_providers.dart#L291) | **`S`** |
| 3 | Wizard adds controllers under `users/{currentUser.uid}/controllers` <br/> [controller_setup_screen.dart:549](../lib/features/installer/screens/controller_setup_screen.dart#L549) | `S` |
| 4 | `_completeSetup` captures `installerAnonymousUid = currentUser?.uid` (`:812`) | **`S`** ← this becomes `fromUid` |
| 5 | `createUserWithEmailAndPassword` (`:822`) | customer `C` |
| 6 | `_restoreInstallerAuth` re-exchanges **the same token** (`:741`) | **`S`** |
| 7 | `_migrateControllersToCustomer(fromUid: S, toUid: C)` (`:933`) | `S` |

The decisive fact is at [staffAuth.ts:541](../functions/src/staffAuth.ts#L541):

```ts
const uid = `staff_${mode}_${pin}`;
```

The staff uid is **deterministic** — derived from mode + PIN, not minted fresh.
So step 6 lands on the same uid as step 2, and step 4 captured that same uid.
This also means **a re-minted token yields the identical uid**, which is what
makes the fix in Part 2 safe: refreshing cannot orphan the migration source path.

Independent corroboration: `test/features/installer/map_roofline_migration_test.dart:12`
already hardcodes the migration source as `const _staff = 'staff_installer_55'`.

### Why it looked open

The local at `:812` is named **`installerAnonymousUid`**, and the rule comments at
[firestore.rules:380-388](../firestore.rules#L380-L388) say the installer is
"signed in as an anonymous/different user." Both are stale — they describe the
pre-`mintStaffToken` world. The name is the reason this question was still open.
Logged as **P3-62**; not renamed here (scope).

### What this means for D4

With the refresh in place:

- **Source side** — `batch.delete(/users/S/controllers/{id})`: `request.auth.uid == S == userId`,
  so **`isOwner(userId)` is TRUE**. This side needs **no grant at all**. The broad
  `|| request.auth != null` on `delete` (`:396`) can go.
- **Destination side** — `batch.set(/users/C/controllers/{id})`: `S != C`, so `isOwner` is
  false. This side **still needs a grant** — it is the one that must become a
  `hasStaffClaim` branch, not the delete.

The uids diverged in exactly one case: when `_restoreInstallerAuth` fell through to
anonymous, leaving `request.auth.uid = A′ ≠ fromUid = S`. That case is what forced the
broad grant to exist, and it is the case this change removes.

### ⚠ Blocker found while proving the above — D4 will break as currently shaped

The migration runs at **`:933`**. The customer's `/users/{userId}` doc is not written
until **`:1047`**. So a narrowed rule of the shape used by the `pixelMap` rule
([firestore.rules:414-417](../firestore.rules#L414-L417)):

```
hasStaffClaim(get(/databases/$(database)/documents/users/$(userId)).data.get('dealer_code',''))
```

evaluates `get()` against a **document that does not exist yet** and **denies**.

That is the exact driveway failure the D4 sequencing exists to prevent — and the
token refresh does **not** fix it. Worse, it is arguably **already live**: the same
batch writes `/users/{C}/controllers/{id}/pixelMap/{ch}`, which is *already* governed
by that `get()`-based rule. On any install carrying a captured roofline map, that write
should already be denied, the whole batch fails atomically, and
`migrateInstallerControllersToCustomer` swallows the error — so the customer silently
gets **no controllers**. Needs bench confirmation on a pixelMap-carrying install.

Fix before D4 (pick one): move the migration after the `:1047` user-doc write; or write
`dealer_code` to the customer doc first; or narrow on the caller's own `dealerCode` claim
with no cross-doc `get()`. Filed as **P0-5**; **D4 should not deploy until it is closed.**

---

## Part 2 — Refresh design

### The core correction: the expiring credential is the *custom* token

The fallback is not an ID-token problem. The Firebase SDK already auto-refreshes ID
tokens. What expires is the **custom token** minted by `mintStaffToken`, valid **one
hour from mint** — and the SDK cannot refresh one, because only the server can mint it.

So "refresh the token" must mean **re-mint**. That is possible because
`InstallerSession.pin` ([installer_providers.dart:239](../lib/features/installer/installer_providers.dart#L239))
still holds the PIN that authorized the session, and `mintStaffToken` authorizes by
**PIN alone** — it has no `request.auth` requirement ([staffAuth.ts:429-462](../functions/src/staffAuth.ts#L429-L462)).
Re-minting therefore works from *any* session state, including anonymous, so the retry
path cannot deadlock.

### Chosen: **refresh-on-demand at the point of need**, in two places

**1. Pre-flight, at the top of `_completeSetup` — before any Firebase write.**
If the cached token is past a 50-minute safety margin (or absent), re-mint *before*
`createUserWithEmailAndPassword`. This is the primary defense: it means the token
exchanged moments later at `_restoreInstallerAuth` is **seconds old**, not an hour old.
A failure here costs nothing — no customer account, no docs, nothing to unwind.

**2. At the restore itself**, with the same re-mint as a second chance, plus retry UI.

### Why not the alternatives

**Not a proactive timer.** A periodic refresh is defeated by precisely the scenario it
is meant to cover. A pixel-walk on a large roofline runs with the app backgrounded and
the phone asleep; iOS suspends Dart timers outright, and Android dozes them. The timer
would not fire during the hour it needed to. Evaluating at the point of need has no such
dependency — however long the device slept, the pre-flight runs when the installer taps
Complete Setup. **This is how the design survives backgrounding: it never depends on
anything having run while backgrounded.**

**Not permission-denied-reactive alone.** Today the broad `|| request.auth != null` grant
means the claim-less writes **succeed**. A reactive refresh would therefore never fire,
could not be exercised, and could not be verified before D4 — while S-5 requires the
telemetry to read zero *before* the rules move. Reactive-only is unverifiable in exactly
the window that matters. (After D4 it becomes a reasonable belt-and-braces addition.)

The 50-minute margin leaves 10 minutes of headroom under the hard 60-minute TTL — enough
for a slow driveway LTE handshake — and avoids burning a callable on every install: a
normal-length install never re-mints at all.

### Part 2.2 — The failure path is explicit and loud

Requirement: if the refresh itself fails, tell the installer, offer retry, and **do not
advance as though the write landed**. This codebase already has four instances of
reporting success for work not done (F-5, F-8, the off-LAN lease, `_writeZeroedSlot`).

| Where | Behavior |
|---|---|
| **Pre-flight fails** | Record telemetry → reset spinner → `_showError` naming the cause and stating plainly **"Nothing was created — no customer account was made."** Wizard does not advance. Safe: nothing committed. Deliberately does **not** sign in anonymously — nothing needs salvaging, and the existing staff session may still work on retry; dropping it would destroy a working session for no gain. |
| **Post-creation restore fails** | Blocking `AlertDialog` — *"Installer session could not be renewed"* — with **Retry** (unlimited; re-mints each time) and **Stop**. Copy states the controllers have **NOT** been transferred and setup is not finished. |
| **Installer taps Stop** | `StateError` thrown. `installCommitted` is still `false`, so `classifyInstallError` → `reportFailure` → the wizard reports **failure**, which is the truth. |

Two consequences worth knowing:

- **Retry is rate-limited upstream.** `mintStaffToken` allows 10 attempts per 60s per IP
  ([staffAuth.ts:126-127](../functions/src/staffAuth.ts#L126-L127)). An installer mashing
  Retry can trip it; the dialog then shows `remint_resource-exhausted` and clears itself
  after a minute. Honest and self-resolving, but it is what that message means.
- **Each failed attempt emits one telemetry row**, so a single flaky install can produce
  several. This is why the query below reports **distinct `device_id`s** and not just a raw
  row count.

The gate is placed deliberately: the migration below it writes under the customer's uid
and deletes under the installer's, and `migrateInstallerControllersToCustomer` **swallows
its own failures** (`:207-209`). Once D4 narrows the grant, a claim-less migration would be
denied and would surface as a *successful* install with none of the customer's controllers.
Refusing to proceed is what keeps that from becoming the fifth silent success. (The swallow
itself is filed as **P0-6** — not fixed here, scope.)

### Part 2.3 — Anonymous path preserved

`signInAnonymously()` is retained, moved into `_fallBackToAnonymous()`, and now emits a
telemetry record **before** it signs in (the sign-in itself can throw, and that is the most
interesting case to have a record of). It is unreachable on the happy path but present, so
Part 3 can prove it never fires. **Delete only after D4 lands.**

### Files changed

| File | Change |
|---|---|
| `lib/features/installer/staff_auth_telemetry.dart` | **new** — telemetry sink, device id, stage enum |
| `lib/features/installer/installer_setup_wizard.dart` | `staffTokenNeedsRefresh` (pure, testable); `_refreshStaffToken`; `_restoreInstallerAuth` rewritten; `_restoreInstallerAuthWithRetry`; `_fallBackToAnonymous`; pre-flight + gate in `_completeSetup` |
| `test/features/installer/staff_token_refresh_test.dart` | **new** — 11 tests |
| `docs/BUGS_AND_DEBT.md` | P0-5, P0-6, P3-60, P3-61, P3-62 |

No refactoring, no unrelated edits, `firestore.rules` untouched.

---

## Part 3 — Instrumentation

### Destination: `/demo_analytics` — and why

Per `OFF_LAN_CAPABILITY.md` §3.3 there is **no fleet telemetry** in this codebase: the
healer writes nothing to Firestore and there is no analytics event anywhere. So the sink
had to be chosen against a hard constraint — **this change may not touch `firestore.rules`**
— which means the write must be permitted by rules that *already exist*, **for an anonymous
caller**, since an anonymous caller is exactly who we need to hear from.

| Candidate | Verdict |
|---|---|
| A new collection e.g. `/staff_auth_telemetry` | ❌ **Actively dangerous.** No rule exists → default-deny → every write fails → the counter reads **zero for the wrong reason**. A false all-clear that unblocks a global rules deploy. This is the worst available option. |
| `/users/{uid}/debug_errors` ([rules:859](../firestore.rules#L859)) | ❌ `isOwner` only. Rows land under a random anonymous uid, and `read: if isOwner` blocks cross-user reads — Tyler cannot answer "has **any** device hit this" without walking every user. Not queryable. |
| Crashlytics / Analytics | ❌ Not a dependency; adding an SDK to a release candidate. |
| A new Cloud Function | ❌ Bigger diff, separate deploy, and needs the network anyway. |
| **`/demo_analytics`** ([rules:1354-1358](../firestore.rules#L1354-L1358)) | ✅ **`allow create: if true`** — accepts an anonymous (even unauthenticated) writer. Top-level, so one place to query. `read: if false` blocks *clients*, but the Console and Admin SDK bypass rules entirely, so Tyler can read it. **Zero rules changes.** |

The semantic overload (a demo-funnel collection carrying installer rows) is deliberate and
is the lesser evil: rows are namespaced by `event_type == 'installer_anon_fallback'` and
never collide with demo rows. Post-D4 this should move to a purpose-built collection with
its own rule.

### Row shape

```json
{
  "event_type":     "installer_anon_fallback",
  "device_id":      "a3f9…",                        // stable per install (SharedPreferences)
  "app_version":    "2.5.10+60",
  "stage":          "restore_after_account_creation" | "preflight_refresh",
                    // restore_… = actually went anonymous (the S-5 event proper)
                    // preflight_… = could not renew, aborted safely, still claim-bearing
  "reason":         "remint_permission-denied",     // truncated to 300 chars
  "dealer_code":    "01",
  "installer_code": "01",
  "auth_uid":       "staff_installer_0101",
  "created_at":     <serverTimestamp>,              // server clock — a wrong phone clock
  "client_time":    "2026-07-30T…Z"                 //   must not hide a row from the window
}
```

`device_id` is a random persisted value, **not** a hardware identifier — the project has no
`device_info_plus`, and this answers the only question being asked ("how many distinct
devices?") without collecting anything new from the handset, which also keeps it clear of
the F-6 privacy-label mismatch.

### Part 3.3 — The exact query Tyler runs

**The gate question:** *has any installer device hit the anonymous fallback in the last N days?*

**Console click-path** (no index required — single-field equality is auto-indexed):

> Firebase Console → **Firestore Database** → **Data** → `demo_analytics`
> → **Filter** → Field `event_type` · Condition `==` · Value `installer_anon_fallback`

**S-5 passes when that returns zero rows whose `app_version` is the token-refresh build or
later.** Rows from older builds are expected and are the adoption signal, not a failure —
what must go quiet is *current* builds still falling back.

**Copy-paste script** (avoids a composite index by filtering dates in memory):

```js
// scripts/check_anon_fallback.js —  node scripts/check_anon_fallback.js [days]
const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.applicationDefault() });

const DAYS = Number(process.argv[2] || 7);
const cutoff = new Date(Date.now() - DAYS * 864e5);

(async () => {
  const snap = await admin.firestore()
    .collection('demo_analytics')
    .where('event_type', '==', 'installer_anon_fallback')
    .get();

  const rows = snap.docs
    .map(d => d.data())
    .filter(r => r.created_at && r.created_at.toDate() >= cutoff);

  console.log(`anon fallbacks in last ${DAYS}d: ${rows.length}`);
  console.log(`distinct devices: ${new Set(rows.map(r => r.device_id)).size}`);
  const byVersion = {};
  for (const r of rows) byVersion[r.app_version] = (byVersion[r.app_version] || 0) + 1;
  console.table(byVersion);          // ← stale builds vs adopted builds
  for (const r of rows) {
    console.log(`  ${r.created_at.toDate().toISOString()}  v${r.app_version}  ` +
                `dealer=${r.dealer_code} installer=${r.installer_code}  ` +
                `stage=${r.stage}  reason=${r.reason}`);
  }
})();
```

`console.table(byVersion)` is the actual D4 decision surface: **when no row carries the
token-refresh build or later, adoption is complete and the rules may tighten.**

### Part 3.4 — Telemetry cannot fail silently *or* block

- Every entry point catches **all** errors and returns normally — proven by a test that
  injects a Firestore whose every access throws.
- The write is bounded by a **5-second timeout**, so a dead network cannot stall an install.
- Device-id lookup failure degrades to `'unknown'` rather than throwing or skipping the row.
- It is never awaited in a position that gates install work: it runs inside
  `_fallBackToAnonymous`, after the decision to fall back has already been made.
- "Cannot fail silently" is satisfied at the level that matters — a failed *write* still
  `debugPrint`s locally, and, critically, **the install itself now fails loudly** when the
  refresh fails. The telemetry is evidence, never the control path.

---

## Part 4 — Verification

**Legend:** ✅ automated · 🔬 on-device required

### 4.1 Automated — `flutter test test/features/installer/staff_token_refresh_test.dart`

**✅ 11/11 passed.**

```
00:00 +11: All tests passed!
```

| Test | Proves |
|---|---|
| minted seconds ago → no refresh | normal install burns no callable |
| 49m59s → no refresh · 50m00s → refresh | margin boundary is exact |
| 75-minute pixel-walk → refresh | the scenario that motivated this |
| margin < 60 min | regression guard: refresh can never fire *after* the hard TTL |
| row carries every queried field | the S-5 query has something to filter on |
| `device_id` stable across records | a churning id can't inflate the fleet count |
| `preflight_refresh` wire value | the two stages are distinguishable |
| 5000-char reason → 300 | unbounded error strings can't bloat the row |
| no session → still a countable row | the most interesting case is still observable |
| **exploding Firestore → `completes`** | **telemetry is not load-bearing** |

`flutter analyze` on all three changed files: **No issues found.**

### 4.2 On-device (🔬 owed before the D4 gate is read)

The three scenarios below exercise `signInWithCustomToken` / `signInAnonymously` /
`mintStaffToken`, which are plugin- and network-bound and cannot be driven from
`flutter test`. Rig: controller `192.168.1.150`, installer PIN `0101`.

| # | Scenario | How to force | Expected |
|---|---|---|---|
| 1 | **Token expiry → refresh → write lands** | Enter PIN, leave the wizard idle >50 min (background the app, let the phone sleep), then complete setup | Log `staff token RE-MINTED and claims restored`; **no** telemetry row; controllers appear under the customer |
| 2 | **Refresh failure → installer sees it → retry works** | Airplane mode just before Complete Setup | Pre-flight path: error naming the cause + *"Nothing was created"*, wizard does not advance. Post-creation path: Retry/Stop dialog. Restore signal, tap **Retry** → install completes |
| 3 | **Fallback unreachable on happy path; correct when forced** | (a) normal install → no row. (b) temporarily make `_refreshStaffToken` return `null` → row appears | (a) zero rows. (b) one row, correct `stage`, `device_id`, `app_version`, `dealer_code` |

Shortcut for #1 without waiting an hour: temporarily set `kStaffTokenSafetyMargin` to
`Duration.zero` to force the re-mint on every install.

### 4.3 Full suite

`flutter test` → **1845 passed · 3 skipped · 1 failed.**

```
04:32 +1845 ~3 -1: Some tests failed.
```

**The single failure is PRE-EXISTING and unrelated — proven by stash, not asserted:**

```
test/features/ai/cloud_ai_processor_normalize_test.dart:
  CloudAIProcessor.normalizeSchedulingIntents
  typed coercion: garbage field values in a well-formed Map entry → defaults, no throw [E]
```

Proof:

```bash
git stash push -u -- <the five changed files>   # tree back to clean main
flutter test test/features/ai/cloud_ai_processor_normalize_test.dart
  → 00:00 +10 -1: … typed coercion: garbage field values … [E]
  → Some tests failed.
git stash pop
```

Same test, same failure, with this change **absent**. It is `lib/features/ai/` — untouched by
this work — and is already tracked as **P1-8** ("Two stale tests mask real failures ...
`cloud_ai_processor_normalize` ('Sunset')").

Note: P1-8 describes *two* stale failures. Only one fails on `main` today —
`schedule_sync_time_parse` currently passes, so P1-8's count is stale. Not touched here.

**Net: this change introduces zero test failures and zero analyzer issues.**

---

## Deliberately not done

- **`firestore.rules` untouched.** That is D4, and it ships *after* adoption.
- **Anonymous fallback not removed** — it must stay until the counter reads zero.
- **P0-6 (swallowed migration failures) not fixed** — real, adjacent, and out of scope for a
  release candidate. The new gate stops the *auth* precondition from reaching it.
- **`installerAnonymousUid` not renamed**, stale comments not corrected (P3-62).

## Sequencing

1. ✅ This change ships (next Android build **≥ +60**; bump `kStaffAuthTelemetryAppVersion` to match).
2. 🔬 On-device verification 4.2.
3. **Close P0-5** — otherwise D4 breaks controller migration regardless of adoption.
4. Dealers adopt; watch the query until no current-build rows appear (checkpoint **Thu 2026-08-06**, decision **Mon 2026-08-10**).
5. D4: narrow `/controllers` — `delete` needs **no** grant (`isOwner` covers it); `create`/`update` need the `hasStaffClaim` branch.
6. Then remove the anonymous fallback and this telemetry.
