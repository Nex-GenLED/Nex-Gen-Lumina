# DIAGNOSTICS — reduce then declare: implementation report

**Date:** 2026-08-05 · **Predecessor:** `audit/DIAGNOSTICS_DECLARATION.md` §5
**Status:** All three items IMPLEMENTED. **Crash sink and stack traces retained.**
**Not done, deliberately:** functions NOT deployed; `firestore.rules` untouched.

---

## ITEM 1 — the error message no longer carries value content

**[user_service.dart](../lib/services/user_service.dart)**

`_safePreview` returned `value.toString()` truncated to 120 chars — the actual value — and that
string lands inside `FirestoreSerializationError.toString()`, which the global sink persists
verbatim. Because the throw originates in `sanitizeForFirestore`, which wraps **user-document**
writes, it could carry `address`, `phone_number`, `home_ssid_encrypted`, `email` or coordinates.

Replaced with `_safeShape`, returning **type + `toString()` length only**:

```dart
'${value.runtimeType} (toString length ${value.toString().length})'
```

**The field was renamed `valuePreview` → `valueShape`** (and `_safePreview` → `_safeShape`). A field
called *preview* that deliberately holds no preview is exactly the kind of stale label the #84
`TEMPORARY` comment turned out to be — renaming stops someone "restoring" the preview later.
Three test references updated with it.

**Both throw sites audited, as asked:**
- `:215` (non-encodable leaf) — was the PII vector, now `_safeShape`.
- `:188` (nested list) — its `valueShape` is a **fixed description string**, never a value. Safe by
  construction, and now pinned by a test so it stays that way.

**No other `toString()` in the chain quotes a value.** The chain is
`_sanitizeValue` → `FirestoreSerializationError` → write-path `catch` → rethrow → global sink. The
only interpolations in that class are `path`, `valueType` and `valueShape`. Third-party exceptions
(`FirebaseException`, `NetworkImageLoadException`) compose their own messages and are outside our
control — noted, not changed; the empirical scan found no PII from them in 669 records.

**Diagnostic power preserved.** The useful signal was never the value — it is `path`, which pinpoints
the offending field and is carried separately. Type + length still distinguishes a stray `Color`
from a stray `Duration` and still flags an unexpectedly huge blob.

### Verification — `test/unit/firestore_error_no_pii_test.dart` (8 cases, all pass)

Drives real PII shapes through the real sanitizer and asserts the value is **absent** while the path
is **present**:

| Case | Asserts |
|---|---|
| street address, phone, email, coordinates, wifi SSID (5 tests) | raw value absent from `toString()` **and** from `valueShape`; `path` still exact; type still named |
| shape reports type and length | contains type + length, not content |
| `toString()` that itself throws | degrades to `(toString threw)`, still no content, `toString()` never throws |
| nested-list throw site | constant description, no value, path retained |

Both halves are pinned on purpose — a scrub that also destroyed the ability to locate the field
would be a bad trade.

---

## ITEM 2 — retention for `debug_errors`

**[functions/index.js](../functions/index.js)** — `runDataCleanup` now prunes
`users/{uid}/debug_errors` at **30 days**:

- `DEBUG_ERRORS_RETENTION_DAYS = 30` + `debugErrorsCutoffTimestamp`
- `stats.debugErrors` counter, plus the collection in the startup log line and the header docblock
- Query on `timestamp` only (single-field auto-index — **no composite index needed**)
- `limit(450)` per user per run, mirroring the `commands` block, to stay under the 500-op batch cap

30 days because the sink answers "what crashed recently" — Tyler has no Crashlytics and no Mac, so
he reads these within days of a report. `node --check` passes.

### ⚠ THIS IS INERT UNTIL `scheduledDataCleanup` IS DEPLOYED

`scheduledDataCleanup` **has never been deployed** (`audit/COMMAND_SAFETY.md` finding D2), so **no
retention has ever run for ANY collection**. Adding `debug_errors` to the routine changes nothing on
its own.

### Blast radius of deploying it — measured, not estimated

Counted against live Firestore with the exact cutoffs the function uses:

| Collection | Window | Total docs | **Would delete** | Kept | Max/user | Bounded? |
|---|---|---|---|---|---|---|
| `commands` | 7d | 8,386 | **7,992** | 394 | 3,212 | yes, 450/run |
| `suggestions` | 30d | 362 | **236** | 126 | 49 | **no limit** |
| `debug_errors` *(new)* | 30d | 669 | **413** | 256 | 156 | yes, 450/run |
| `pattern_usage` | 90d | 59 | **0** | 59 | 0 | no limit |
| `ai_usage` | 90d | 0 | 0 | — | — | no limit |
| `detected_habits` | 90d | 0 | 0 | — | — | no limit |
| `oauth_codes` | >1h | 0 | 0 | — | — | no limit |
| **TOTAL** | | | **8,641** | | | |

**Reading of that: the deploy is safe, and 92% of it is the commands TTL doing its intended job.**

- `commands` dominates (7,992). These are exactly the stale relay commands the TTL exists for —
  finding D1 already established 125 stale `pending` commands up to 78 days old. The 450/run cap
  means the worst user (3,212) drains over ~8 daily runs rather than in one burst.
- `debug_errors` 413 is the point of this item; max/user 156 is under the cap, so it clears in one run.
- `suggestions` (236) is unbounded per run but tiny — 49 max for any user.
- `ai_usage`, `detected_habits`, `pattern_usage`, `oauth_codes` delete **nothing** today.

**Recommendation: deploy it in the same pass — but as its own step, after this build ships, and not
bundled with anything else.** Reasons: nothing customer-visible is deleted (no schedules, designs,
controllers, calendar entries, or user docs are touched); the largest deletion is the backlog the
TTL was written for; and it is the only way item 2 becomes real. **Do not deploy it in the same
change as the `controller_ips` rules** — that is still mid-soak, and stacking a first-ever bulk
delete onto a rules cutover would make any incident impossible to attribute.

Not deployed here, as instructed.

---

## ITEM 3 — `PrivacyInfo.xcprivacy` + Play checklist

**[ios/Runner/PrivacyInfo.xcprivacy](../ios/Runner/PrivacyInfo.xcprivacy)** created. `NSPrivacyTracking`
false, `NSPrivacyTrackingDomains` empty, and **every** entry Linked = YES / Tracking = NO.

### The audit found far more than the sink

The brief asked whether any other first-party collection needs declaring. It does — **12 data types**,
not 2. Declaring only the crash sink would have been a different kind of false declaration:

| Declared type | Source |
|---|---|
| `CrashData` + `OtherDiagnosticData` | the sink; **both**, because 556 of 669 records are non-fatal `StateError`, so crash data alone understates it |
| `Name`, `EmailAddress`, `PhoneNumber`, `PhysicalAddress` | `users/{uid}` profile fields |
| `PreciseLocation` | `latitude`/`longitude` at ~7 dp, for sunrise/sunset + geofence |
| `UserID` | the Firebase Auth uid every record is keyed under |
| `PhotosorVideos` | `house_photo_url` — dashboard hero + roofline mapping backdrop |
| `OtherUserContent` | designs, schedules, calendar entries, scenes, Lumina AI prompts |
| `ProductInteraction` | `pattern_usage`, `ai_usage`, `detected_habits`, `suggestions` — purposes AppFunctionality **and** Personalization |
| `OtherDataTypes` | `home_ssid_hash` / `home_ssid_encrypted` — no listed category fits a network identifier |

### Required-reason APIs — deliberately minimal

Declared: **`NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`** (app-owned data only) — the
app persists local state through `shared_preferences`, which is `NSUserDefaults`-backed.

**Not declared:** file-timestamp, disk-space, active-keyboard, system-boot-time. First-party code
does not call them; where a *plugin* does, the plugin declares it in its own manifest. Padding this
list would itself be a review finding. (Separately, `COMPLIANCE_AND_SECURITY.md` F-9 records that
`path_provider_foundation`, `flutter_blue_plus` and `speech_to_text` ship **no** manifest — a plugin
gap this app-level file cannot fix.)

### Verification — it is valid AND it ships

A manifest that does not ship is worse than none, so both were checked:

```
parses as plist                 : YES (plistlib)
collected data types            : 12
every entry Linked/Tracking/purposes : OK
accessed API types              : ['NSPrivacyAccessedAPICategoryUserDefaults']

Runner group membership         : True
Runner target Resources phase   : True
file reference declared         : True
```

`ios/Runner.xcodeproj/project.pbxproj` received **four** coordinated insertions — `PBXFileReference`,
`PBXBuildFile`, Runner group child, and the Runner target's `PBXResourcesBuildPhase`. Being in the
**Resources build phase** is what puts it in the bundle; the first three alone would show it in
Xcode's navigator while shipping nothing.

*(Caveat worth stating: this checkout has never been pod-installed and there is no Mac here, so the
proof is structural — the file is a valid plist and is wired into the target that builds the app.
The first Codemagic run is the end-to-end confirmation.)*

---

## PLAY DATA SAFETY — checklist for Tyler

I have no console access. Work through this in **Play Console → App content → Data safety**.

**Overview**
- [ ] Does your app collect or share any of the required user data types? → **Yes**
- [ ] Is all of the user data collected by your app encrypted in transit? → **Yes** (Firestore TLS)
- [ ] Do you provide a way for users to request that their data is deleted? → **Yes**
      *(genuine: `firestore.rules` grants owner delete on these collections, and account deletion
      exists — see F-5a/F-5b in COMPLIANCE_AND_SECURITY.md for that path's own open items)*

**For every type below: Collected = Yes · Shared = No · Processed ephemerally = No ·
Required (not optional) = Yes · Purpose = App functionality** (add *Personalization* only where noted)

| Category → Type | Notes |
|---|---|
| Personal info → **Name** | profile |
| Personal info → **Email address** | auth + profile |
| Personal info → **Phone number** | profile |
| Personal info → **Address** | install site |
| Location → **Approximate location** | derived from address |
| Location → **Precise location** | lat/lon for solar + geofence |
| Photos and videos → **Photos** | house photo |
| App activity → **App interactions** | *also tick Personalization* |
| App activity → **Other user-generated content** | designs, schedules, scenes, AI prompts |
| App info and performance → **Crash logs** | the sink |
| App info and performance → **Diagnostics** | the sink's non-fatal errors |
| Device or other IDs → **Device or other IDs** | Firebase Auth uid; FCM token |

**Do NOT tick:** any "shared with third parties" box (data stays in your own Firestore), Financial
info, Health, Messages, Contacts, or Browsing history.

**Consistency check before submitting:** the answers above must match the iOS manifest — same 12
types, same Linked = yes, same Tracking = no. If the existing Play form omits **Crash logs** or
**Diagnostics**, that is the specific inconsistency this pass fixes.

---

## VERIFICATION SUMMARY

| Check | Result |
|---|---|
| New PII suite + existing sanitizer suite | **26/26 pass** |
| Full suite | **1901 passed · 3 skipped · 1 failed** |
| Failing test | `cloud_ai_processor_normalize` — the known pre-existing stale P1-8 assertion. **No new failures** |
| Arithmetic | 1893 baseline **+ 8 new = 1901** ✅ |
| `flutter analyze` (3 changed Dart files) | **No issues found** |
| `node --check functions/index.js` | **syntax OK** |
| `PrivacyInfo.xcprivacy` | valid plist; in Runner group **and** Resources build phase |
| `firestore.rules` | **untouched** |
| Functions | **not deployed** |

---

## WHAT REMAINS OPEN

- **Deploy `scheduledDataCleanup`** — item 2 is inert until then. Blast radius measured above
  (8,641 docs, 92% of it the commands TTL). Recommended as its own step, not stacked on the
  `controller_ips` rules cutover.
- **Play Data Safety form** — checklist above; needs Tyler's console access.
- **Plugin-level manifests** — `path_provider_foundation`, `flutter_blue_plus`, `speech_to_text`
  ship none (`COMPLIANCE_AND_SECURITY.md` F-9). Outside this app-level file.
- **End-to-end confirmation the manifest lands in the built IPA** — first Codemagic run.
- The crash sink still collects; that is intended, and is now declared rather than silent.

---

# DEPLOY LOG — `scheduledDataCleanup` ✅ 2026-08-05

**Deployed alone. Nothing else in this release** — the `firestore.rules` deploy had just landed, and
a first-ever bulk delete stacked onto it would have made any incident impossible to attribute.

Closes **D2/D12** (`audit/COMMAND_SAFETY.md`): the function existed in source but had **never been
deployed**, so no retention had ever run for any collection. Only the uncalled `cleanupOldData`
callable was live — confirmed immediately before deploying:

```
cleanupOldData          v2  callable   us-central1   ← deployed
sweepExpiredCommands    v2  scheduled  us-central1   ← deployed
scheduledDataCleanup                                 ← ABSENT
```

This is why 78-day-old `pending` commands survived until the expiry sweeper caught them.

## 1 — Pre-deploy re-count

Measured with `runDataCleanup()`'s own cutoffs (90d usage / 30d suggestions / 7d commands / 30d
debug_errors), its per-user loop, and its 450 caps.

| Collection | Live | Matching cutoff | **First run** | Max/user | 500-op batch cap |
|---|---|---|---|---|---|
| `commands` | 8,386 | 8,008 | **3,336** | 3,228 | bounded 450 |
| `debug_errors` | 669 | 413 | **413** | 156 | bounded 450 |
| `suggestions` | 362 | 236 | **236** | 49 | ok (<500) |
| `ai_usage` | 0 | 0 | 0 | 0 | ok |
| `pattern_usage` | 59 | 0 | 0 | 0 | ok |
| `detected_habits` | 0 | 0 | 0 | 0 | ok |
| `oauth_codes` | 0 | 0 | 0 | 0 | ok |
| **TOTAL** | | **8,657** | **3,985** | | |

**The brief's 8,641 was the eventual total, not the first-run blast radius.** The 450/user cap holds
back 4,672 of the 8,008 matching commands, so run one deletes **3,985** and the rest drains over
about eight daily runs. Reported before deploying; the divergence is smaller-not-larger and fully
explained by the documented cap.

**No unbounded collection approaches the 500-op batch limit.** `suggestions`, `ai_usage`,
`pattern_usage`, `detected_habits` and `oauth_codes` are queried without a `.limit()`, so a single
user holding >500 matching docs would fail `batch.commit()` and abort the entire run. The worst case
today is 49. Worth re-checking before any future growth in `suggestions`.

## 2 — Deploy

```
firebase deploy --only functions:scheduledDataCleanup
  + creating Node.js 20 (2nd Gen) function scheduledDataCleanup(us-central1)...
  + Successful create operation.
```

Cloud Scheduler job `firebase-schedule-scheduledDataCleanup-us-central1` created, `0 4 * * *` UTC,
ENABLED.

## 3 — First run — EXACT MATCH TO PREDICTION

Triggered manually at **2026-08-05T20:03:49Z** rather than waiting eight hours for 04:00 UTC.

| Collection | Predicted | **Actual** | Δ |
|---|---|---|---|
| `commands` | 3,336 | **3,336** | 0 |
| `debug_errors` | 413 | **413** | 0 |
| `suggestions` | 236 | **236** | 0 |
| `aiUsage` / `patternUsage` / `habits` / `oauthCodes` | 0 | **0** | 0 |
| **TOTAL** | 3,985 | **3,985** | **0** |

**Zero divergence on every collection.** The query is matching exactly what was predicted and
nothing unexpected — the step-3 stop condition never came close.

## 4 — Cap and timeout behaviour ✅

**Runtime 17.4s** (20:03:56.708 → 20:04:14.077). The function declares no `timeoutSeconds` and so
inherits the **60s v2 default**; the heaviest run it will ever do — a first-ever drain with twelve
450-op batch deletes — finished in under a third of that. Later runs are strictly smaller. No
timeout risk, but the margin is worth remembering if collections are ever added to the loop.

**The cap drained exactly 450 per user, not in one burst:**

| User | Before | After | Removed | Runs left |
|---|---|---|---|---|
| `YcSGiwesJuS7` | 3,228 | 2,778 | 450 | 7 |
| `wrQRUUKyXyc0` | 1,632 | 1,182 | 450 | 3 |
| `5oHhaEaf6icm` | 996 | 546 | 450 | 2 |
| `NmDukd5rKwP9` | 616 | 166 | 450 | 1 |
| 8 others | ≤443 | 0 | all | 0 |

Fleet total 8,008 → **4,672** still matching. The ~3,212-command user in the brief is
`YcSGiwesJuS7` (3,228 at deploy time) and is draining as designed — **8 daily runs, not one burst.**

## 5 — Nothing customer-visible was touched ✅

| Account | schedules | controllers | designs | `calendar_entries` | user doc |
|---|---|---|---|---|---|
| Ellie Cochran | 1 | 1 | 1 | 10 | OK, 72 fields |
| Tim Kelly | 1 | 1 | 0 | 0 | OK, 72 fields |
| Chris Cipollone | 1 | 1 | 2 | 6 | OK, 73 fields |
| Taps On Main | 0 | 1 | 2 | 21 | OK, 70 fields |

Fleet-wide: **24/24 user documents, 15 controllers, 12 schedules, 11 designs, 84 dated calendar
entries across 8 users** — all intact. This is structural, not just observed: `runDataCleanup()`
touches only the seven subcollections in the table above plus top-level `oauth_codes`, and never
writes to a user document at all.

> **A path error caught during this verification — third instance of the same class.** The first
> pass reported `calendar_entries: 0` for every account, which would have looked like a wipe.
> **`calendar_entries` is a MAP FIELD on `users/{uid}`, not a subcollection**
> (`user_service.dart:836-871`) — counting a subcollection by that name returns 0 for everyone
> whether or not the data exists. Re-measured on the field: 84 entries across 8 users, intact.
>
> Same mistake as the `bridge_health` probe in `audit/COMMAND_SAFETY.md` §5 and the admin-SDK
> readback in `audit/SOLAR_UI_GATE.md`: **verifying against something other than what the code
> actually does.** Confirm the shape and path from the writing code before reading a count as
> evidence — a zero from the wrong path is indistinguishable from a zero that means data loss.

## Findings

| # | Finding | Severity |
|---|---|---|
| C1 | `scheduledDataCleanup` is deployed; **retention now actually runs**, daily 04:00 UTC. D2/D12 closed | **Resolved** |
| C2 | First run deleted **3,985 of 8,657**, matching prediction exactly on every collection | Verified |
| C3 | First-run blast radius is **3,985, not 8,641** — the latter is the eventual total across ~8 runs | Correction |
| C4 | Runtime 17.4s against a **60s default timeout** on the heaviest run the function will ever do | Verified, thin-ish margin |
| C5 | `suggestions`, `ai_usage`, `pattern_usage`, `detected_habits`, `oauth_codes` are queried **without `.limit()`** — >500 matching docs for one user aborts the whole run. Worst case today is 49 | **P3, latent** |
| C6 | `commands` still has 4,672 matching docs; full drain ~7 more daily runs | Expected |
| C7 | `calendar_entries` is a user-document field, not a subcollection — a subcollection count returns a misleading 0 | Gotcha, recorded |
