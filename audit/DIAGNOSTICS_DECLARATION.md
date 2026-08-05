# DIAGNOSTICS DECLARATION — `users/{uid}/debug_errors`

**Date:** 2026-08-05 · **Status:** DIAGNOSTIC ONLY. Nothing changed. **The crash sink stays.**
**Context:** iOS submission ~1 week out. This is a declaration problem, not a strip-it problem.

---

## 0. VERDICT

**Today's declarations do NOT match today's behaviour.** The app collects crash diagnostics linked
to an authenticated user and declares nothing: **`PrivacyInfo.xcprivacy` does not exist anywhere in
the repo.**

**No PII has actually landed** — 669 live documents scanned, zero emails, coordinates, addresses,
tokens or phone numbers. **But one unguarded code path can put user-document values into the error
text**, and it has simply never fired.

**Recommendation: reduce scope first, then declare** (§5). The reduction is ~30 minutes and removes
the only traced PII vector, which changes the declaration from *"diagnostics that might contain
personal data"* to *"diagnostics that structurally cannot"*.

---

## 1. EVERY WRITER

**Exactly one, in Dart.** `captureBug84` was removed in `7e04b00`; no server-side writer exists
(`functions/` has zero references to `debug_errors`).

| Writer | Trigger | Fields persisted |
|---|---|---|
| `_reportUncaughtError` — [main.dart:64-99](../lib/main.dart#L64) | `FlutterError.onError` (framework errors) and `WidgetsBinding.instance.platformDispatcher.onError` (uncaught async) | `timestamp` (serverTimestamp), `context` (which handler), `error_type` (runtimeType), **`error`** (`error.toString()`, truncated 3000), **`stack`** (truncated 3000), `platform` (ios/android/other) |

Guards already present: a `_errorSinkActive` re-entrancy flag, `uid == null` early return (no
anonymous writes), a 3000-char cap on both text fields, and a `catch (_) {}` so the sink can never
crash the app.

**Firestore rules** ([firestore.rules:973-978](../firestore.rules#L973)): owner-only read / create /
update / delete. The user can read *and delete* their own records — which is a genuine asset for a
data-subject request. Tyler reads other users' records through the console as project admin, which
bypasses rules.

**Live fleet state:** **669 documents across 14 accounts**, oldest **2026-05-29 (68 days)**.
Context split: `FlutterError.onError` 622, `PlatformDispatcher.onError` 47 — i.e. **all 669 come
from this sink**, confirming the removed `captureBug84` never produced a document in production.
Dominant `error_type`: `StateError` ×556, then `NetworkImageLoadException` ×33, `FlutterError` ×26.

---

## 2. CAN PII REACH THE PAYLOAD?

### In code: YES — one specific, unguarded path

**Nothing is sanitized or scrubbed. The only treatment is truncation at 3000 characters.**
`error.toString()` is written verbatim.

The concrete vector is `FirestoreSerializationError`:

- [user_service.dart:895-898](../lib/services/user_service.dart#L895) — its `toString()` embeds
  `(type: $valueType, preview: $valuePreview)`.
- [user_service.dart:225-232](../lib/services/user_service.dart#L225) — `_safePreview` returns
  **`value.toString()` truncated to 120 characters** — the *actual value*, not a type name.
- It is thrown from `sanitizeForFirestore`, which wraps writes of the **user document** — the
  document holding `address`, `address_encrypted`, `phone_number`, `latitude`, `longitude`,
  `home_ssid_encrypted`, `display_name`, `email`.

So a single non-encodable field in a profile save produces an exception whose message quotes up to
120 characters of that field, and the global sink writes it to Firestore verbatim. **This is the
same shape that made the #84 capture blocking.**

Secondary, lower-risk: `FirebaseException.toString()` on a permission error includes the document
path (which contains the uid), and `NetworkImageLoadException` includes the failing URL.

### In practice: NO — it has never happened

All 669 live documents scanned for PII patterns (**counts only; no values were printed or copied**):

| Pattern | Docs |
|---|---|
| email address | **0** |
| decimal coordinates | **0** |
| street address | **0** |
| `users/{uid}` path | **0** |
| `ssid` | **0** |
| long token/secret | **0** |
| **`preview:`** (the `_safePreview` vector) | **0** |

**A first pass appeared to show phone numbers in 89.4% of documents. That was my regex being wrong,
and it is worth recording so nobody repeats it.** A loose digit-run pattern matched
`pid: 20245, tid: 8623923648`, `isolate_dso_base`, and `build_id` values inside iOS stack traces.
Discriminating: **598 matches, all in the `stack` field, and exactly 598 stacks contain
`pid`/`tid`/`dso_base` markers. Zero matches in the `error` field, and zero strict phone-number
shapes anywhere.** No phone number has ever been written.

**Conclusion: the risk is latent, not realised.** The `preview:` path has fired zero times in
68 days. But it is unguarded, and the first profile-save serialization failure would land address
or phone text into a collection declared (if at all) as crash logs.

### One thing that is true regardless of payload

Every record is stored **under the user's own uid**, so it is **linked to an identifiable user by
construction**. That cannot be argued away by scrubbing the text, and it determines the "Linked to
You" answer in both stores. It is also *correct* for the feature — Tyler needs to find a specific
customer's crashes — so it should be declared, not engineered around.

---

## 3. WHAT MUST BE DECLARED

### Apple — **currently FAILING**

**`PrivacyInfo.xcprivacy` does not exist.** Confirmed by glob (`**/PrivacyInfo.xcprivacy` → 0
results), and independently by `audit/COMPLIANCE_AND_SECURITY.md` item **1.4 (FAIL)** and finding
**F-9**, which already scoped it at ~2h. Several plugins ship their own manifests; the **app-level**
one is missing, and that is the one that must declare first-party collection.

Required entries under `NSPrivacyCollectedDataTypes`:

| Field | Value |
|---|---|
| Data type | `NSPrivacyCollectedDataTypeCrashData` — and `NSPrivacyCollectedDataTypeOtherDiagnosticData` if the sink is characterised as broader than crashes (it catches non-fatal `FlutterError`s too, so this is the safer pairing) |
| Linked to user | **YES** — stored under the uid |
| Used for tracking | NO |
| Purpose | `NSPrivacyCollectedDataTypePurposeAppFunctionality` (diagnostics/debugging) |

Note the sink captures **non-fatal** framework errors as well as crashes (556 of 669 are
`StateError`), so declaring *only* Crash Data understates it.

### Google Play — Data Safety

- Category: **App activity / Crash logs** and **Diagnostics**.
- Collected: **Yes**. Shared with third parties: **No** (stays in your own Firestore).
- Linked to the user: **Yes**. Optional vs required: it is automatic, so **required**.
- Encrypted in transit: yes (Firestore TLS). User can request deletion: **yes** — the rules already
  permit owner delete, which is a genuine "yes" rather than an aspirational one.

**I cannot see the current Play form** (no console access; same limitation recorded in
`COMPLIANCE_AND_SECURITY.md` §4). If the existing form omits Diagnostics/Crash logs, it is
inconsistent with shipped behaviour and must be updated before the next release.

**Plain answer to the question asked: no, today's declarations do not match today's behaviour.**
iOS declares nothing at all. Play is unverifiable from here and should be assumed inconsistent
until checked.

---

## 4. RETENTION — none, and worse than expected

**`debug_errors` is not covered by any retention policy at all.**

`runDataCleanup` ([functions/index.js:1014+](../functions/index.js#L1014)) handles `ai_usage` (90d),
`pattern_usage` (90d), `detected_habits` (90d), `suggestions` (30d), `commands` (7d), oauth codes and
analytics. **`debug_errors` is absent from that list** — so even a correctly deployed cleanup would
never touch it.

On top of that, **`scheduledDataCleanup` has never been deployed** (recorded as finding D2 in
`audit/COMMAND_SAFETY.md`), so *none* of the retention above has ever run for *any* collection.

**Net effect: per-user error text and stack traces accumulate indefinitely.** Live evidence: 669
documents, oldest 68 days, growing. Tim Kelly alone holds 241; Trend Setter 140.

That is a **data-minimisation problem stacked on top of the declaration problem**, and it is the
part a reviewer or a data-subject request is most likely to expose — "how long do you keep it?"
currently has no good answer.

---

## 5. RECOMMENDATION — reduce, then declare

**Do not declare as-is.** Declaring is *defensible today* on the evidence (0/669 PII), but it
locks in a description that the `preview:` path can invalidate at any moment, and it answers
"retention?" with "forever".

### Recommended: three small changes, then declare the reduced version

| # | Change | Cost | Why |
|---|---|---|---|
| 1 | **Stop `FirestoreSerializationError` quoting the value.** Make `_safePreview` return the type/length only, or drop `preview:` from `toString()` | **~30 min** | Removes the *only* traced PII vector. Turns "might contain personal data" into "structurally cannot". The path's diagnostic value is the **field path**, which is already carried separately and is far more useful than 120 chars of a value |
| 2 | **Add `debug_errors` to `runDataCleanup`** with a short window (30 days is ample — the sink exists for "what crashed recently") | **~30 min** | Gives a real retention answer. Note it is **inert until `scheduledDataCleanup` is deployed**, which is already an open P0 — so pair them |
| 3 | **Write `PrivacyInfo.xcprivacy`** declaring Crash Data + Other Diagnostic Data, Linked = YES, Tracking = NO, Purpose = App Functionality; and update the Play Data Safety form to match | **~2h** (F-9's existing estimate) | Required regardless of 1 and 2 |

**Keep the stack traces.** They are the entire value of the sink — Tyler has no Crashlytics and no
Mac — and 669 real samples contain no PII. Dropping them would cost the feature's whole purpose to
mitigate a risk the evidence does not support.

### The alternative, honestly stated

**Declare as-is** costs only item 3 (~2h) and ships. It is not reckless — the evidence genuinely
shows a clean payload. The risks you accept: (a) the first profile-save serialization failure writes
customer address/phone text into a collection declared as crash logs, and (b) "we keep it forever"
is your retention answer if anyone asks.

Items 1 and 2 together are **about an hour** and remove both. Given submission is a week out and the
manifest work (item 3) has to happen anyway, doing all three in one pass is the better trade.

### Not recommended

- **Removing the sink** — asked and answered; it stays.
- **Dropping uid-keying to avoid "Linked to You"** — it would break the feature (Tyler could no
  longer find a given customer's crashes) and "linked" is the honest answer anyway.
