# Store Submission — Follow-up 2 Report

**Date:** 2026-09-17
**Branch:** `release/store-submission-followup-2`
**Base:** `origin/main` @ `699a498` (`2.5.10+97`) — fetched and verified fresh, not taken from any prior session's claim
**Version produced:** `2.5.10+98`
**Working tree:** clean. `flutter analyze` **0 errors** / 12 warnings / 373 infos (exactly the documented baseline). `flutter test` **2989 passed · 4 skipped · 0 failed**.

---

## 0. Branch state — what Step 0 actually found

The prompt assumed **one** `release/store-submission-<date>` branch. There were **two**, both created today, both already containing `origin/main`'s tip, **divergent from each other**, and — critically — **both checked out in other live worktrees**:

| Branch | Tip at first look | Worktree | Content |
|---|---|---|---|
| `release/store-submission-2026-09-17` | `5ac40ac` | `C:\Flutter Projects\lumina-store-submission` | docs/guides pass — **and `M firestore.rules` uncommitted, mid-edit** |
| `release/store-submission` | `0ae22a0` | a Claude scratchpad worktree | a single one-line `codemagic.yaml` fix |

Neither contained the Firestore-rules, bridge-reset or Apple B-3/S-0 work the prompt described as already landed. At that moment it had not landed — it was **in flight** in another session.

**Decision, and why.** I did not write to either branch. Both were checked out elsewhere, and committing to a branch another worktree holds moves the ref under that session's feet. Instead I branched fresh off `origin/main`'s verified tip into my own isolated worktree. Standing rule applied: *the working tree and index are shared; build from an isolated worktree.*

**Then the situation changed underneath the work.** `release/store-submission-2026-09-17` turned out to be the canonical branch and kept committing throughout this session — it landed the rules fixes, the bridge `reset()` fix, the CLAUDE.md corrections, an auth/link-account fix, a CI guard, its own report, **and its own `2.5.10+98` bump**.

**Resolution: I rebased onto it twice** rather than leave a third divergent line, dropping my own duplicate `+98` commit in favour of theirs (both made the identical change to the identical two files). My branch is now a **strict superset** — verified by `git log <mine>..<theirs>` returning empty.

```
4e3049b  docs(claude): record that the Riverpod dispose hazard is currently clean   ← this session
8582fde  fix(startup): guarantee runApp, and stop losing the FCM token on late sign-in ← this session
b6af99c  fix(functions): delete the unused, key-bearing openaiProxy                 ← this session
65f2b2c  docs: store-submission branch report                                       ┐
122505c  fix(auth): give a signed-up user with no system a way out of /link-account │
195615a  ci(ios): refuse to invent a build number instead of falling back to an epoch│
a3e6b12  chore(release): 2.5.10+98                                                  │ other
0899a86  docs(claude): correct three stale claims that misdescribe the shipping code│ session
f4753ca  fix(bridge): reset() posted to a path the firmware has never served        │
9318625  test(rules): live client-credential verification                           │
ae99259  fix(rules): add the two missing blocks (voice linking + crews)             │
5ac40ac  docs: reconcile the +89 guide pass against verified behavior               │
586a430  docs(guides): 2026.09 how-to family — seven drafts verified against +97    ┘
```

> ⚠️ **This branch needs a human merge decision.** Three branches now exist. `release/store-submission-followup-2` contains everything and is the one to merge; `release/store-submission-2026-09-17` is its parent and is redundant once mine merges; `release/store-submission` (`0ae22a0`) is a **separate, earlier attempt at the same CI fix** that `195615a` supersedes — it is **not** an ancestor of this branch and should be **abandoned, not merged**, or you will double-apply it.
>
> The sibling branch was stable at `65f2b2c` when I finished. **Re-check before tagging** — it moved three times during this session.

Each of my three commits was staged with an **explicit pathspec**. No `git add -A`, no `git stash`. Per-commit file counts: 1 file, 3 files, 1 file — no incidental changes.

---

## 1. Delete the unused `openaiProxy` — **DONE, verified in production**

**Audit first.** Before deleting I confirmed it was genuinely dead:
- No `httpsCallable('openaiProxy')` anywhere. The nine callables the app actually invokes are `claudeProxy`, `createCustomerAccount`, `joinNeighborhood`, `mintStaffToken`, `notifyDay2Team`, `notifyReferrerOfApproval`, `purgeUserAccount`, `sendSyncNotification`, `setAccountProfile`.
- The only surviving `openai` strings in `lib/` are a **prompt-injection blocklist literal** (`lumina_brain.dart:54`, sitting next to `'anthropic'`, `'gpt'`, `'claude'`) and a historical rename comment (`lumina_ai_service.dart:3`). Neither is a call site.

**Fixed the unit, not just the export.** Removed together because they are one thing: the `openaiApiKey` `defineString("OPENAI_API_KEY")` param, `exports.openaiProxy`, and `calculateCost()` — whose only caller was inside `openaiProxy`. **173 lines deleted.** `node --check` passes. `getAiUsageStats` is unaffected: it reads the stored `estimatedCost` **field** off Firestore documents, not the deleted helper.

**Deployment — and a deliberate choice of tool.** I used `firebase functions:delete openaiProxy --region us-central1 --force` rather than `firebase deploy --only functions`. Deleting is what was authorised; a full functions deploy would have pushed **45 other functions** from this branch to production, a far larger blast radius, and would have redeployed code this session never reviewed. `FUNCTIONS_DISCOVERY_TIMEOUT=180` was set.

**Verified after, not assumed:**

```
i  functions: deleting Node.js 22 (2nd Gen) function openaiProxy(us-central1)...
+  functions[openaiProxy(us-central1)] Successful delete operation.
```

Then re-listed twice — once immediately, once at the end of the session:

| Check | Result |
|---|---|
| `openaiProxy` in `functions:list` | **ABSENT** |
| Deployed function count | 47 |
| `claudeProxy` / `purgeUserAccount` / `scheduledDataCleanup` | all still present |

**This closes the sibling branch's open Play blocker B-9.**

> **Still owed, and the repo cannot do it:** revoke the OpenAI API key at the provider, and drop `OPENAI_API_KEY` from the gitignored `functions/.env`. Deleting the function stops the code path; it does not invalidate the key. Flagged in the commit message too.

---

## 2. Guard the `Firebase.initializeApp` fallback — **DONE**

**The defect, confirmed by reading it:** the `catch` branch called the fallback with **no try/catch and no timeout**, and `runApp()` was not in a `finally`. A throw there aborted `main()` before any frame — permanent splash, no crash dialog, nothing in logcat. The file's own header comment at `:39` describes that exact incident (`2.5.10+55`): *"the process sat pre-`runApp()` forever."*

**Fix, matching the discipline already in the file.** The `EncryptionService` block twenty lines below already documents why a bare try/catch is insufficient — it covers a *throw* but does nothing for a *hang*, and only a timeout breaks a hang. Firebase init was the one step that predated that lesson. Now:

- Primary init bounded: `.timeout(const Duration(seconds: 10))` on both the web and native branches.
- Fallback wrapped in its **own** try/catch **and** its own 10s timeout.
- Both-fail is explicitly non-fatal — the app still starts. Deliberate: a launched app whose Firebase calls error is diagnosable by the user and by us; a process sitting pre-`runApp()` is neither.

**Fixed the class, not the instance.** The whole startup body is now wrapped with `runApp()` in a `finally`, under a documented backstop `catch`. A future unguarded `await` added to `main()` degrades into a running app with a reported error rather than another silent hang.

**Verified:**
- `git diff -w` shows **no edit** to the encryption or notification guards — they are re-indented and otherwise untouched, exactly as required.
- `runApp(` appears **exactly once**, in the `finally`. No bare `return` inside the try could skip it.
- `flutter analyze` on the file: **No issues found.**

---

## 3. Notification-permission timing and the FCM-token bug — **DONE, and negative-controlled**

Two genuinely separate problems, both fixed.

**(a) Prompt on the cold-launch frame.** `main()` called `initialize()` unconditionally, so `requestPermission` raised the Android 13+ POST_NOTIFICATIONS dialog before the login screen, with no context. `main()` now calls `startAuthWatch()`, which **only subscribes** — it prompts for nothing and touches no network until a user exists.

**(b) The real functional bug.** `_initialized = true` was set **on entry**, and `_storeToken` early-returns when `uid == null`. On a cold start with no user the token write was skipped — and because the method was idempotent-by-flag it **never ran again for that session**. Only `onTokenRefresh` could ever have recovered it. **Push — weekly brief, sync events — was silently dead for every user who signed in after launch.**

Fix shape:
- `_initialized` is set only **after** the wiring actually completes.
- A separate `_initializing` flag provides the re-entrancy guard that set-on-entry was really doing.
- `initialize()` returns **without burning the flag** when there is no user.
- `startAuthWatch()` re-stores the token on **every** sign-in, so a second account on the same device is covered too.
- The two halves are invoked independently and each swallows its own failure — the wiring half touches static `FirebaseMessaging.onMessage`/`onMessageOpenedApp`, which can throw when Play Services is wedged, and the token half must still run when it does.

`authStateChanges()` emits current state on subscribe, so an already-signed-in user at cold start is still handled on the same tick.

### Verified with a real test path, then proved the test is meaningful

New: `test/features/neighborhood/sync_notification_token_on_late_signin_test.dart` — drives the real `startAuthWatch()` path against injected fakes. **5 cases, all pass:**

1. **THE REGRESSION** — signing in *after* `startAuthWatch()` stores the token, and `requestPermissionCalls == 0` before a user exists.
2. The token half survives the wiring half throwing.
3. A second account on the same device also gets its token stored.
4. A null FCM token writes nothing.
5. A null auth emission writes nothing.

**Negative control — the part that makes the above mean something.** I re-introduced the old semantics (`_initialized = true` on entry; no per-sign-in re-store) and re-ran:

```
+0 -1  THE REGRESSION: signing in AFTER startAuthWatch() stores the token   [E]  Expected: true  Actual: <false>
+0 -2  the token half survives the wiring half throwing                     [E]  Expected: true  Actual: <false>
+0 -3  a second account on the same device also gets its token stored       [E]  Expected: true  Actual: <false>
+1 -3  Some tests failed.
```

**3 of 5 fail against the old code**; the 2 that pass are the controls that should pass either way. The fix was then restored from the commit and the suite re-run green. This is a real regression test, not a shape assertion.

---

## 4. Version bump — **2.5.10+98, both files together**

`versionCode 97` is consumed: a signed AAB was built from `5b7804b` on 2026-09-16 and never uploaded; a built bundle burns its code regardless.

**Verified 98 was actually free before taking it** — highest `build-*` tag is `build-97`, and `docs/BUILD_LEDGER.md` has no row at +98 or above.

| File | Value |
|---|---|
| `pubspec.yaml:5` | `version: 2.5.10+98` |
| `lib/features/installer/staff_auth_telemetry.dart:57` | `const String kStaffAuthTelemetryAppVersion = '2.5.10+98';` |

They agree. Confirmed no lingering `2.5.10+97` in either file.

**Reconciliation note:** the sibling session bumped to +98 independently and first. Rather than carry two commits making the same change, I dropped mine and kept theirs (`a3e6b12`). One build number, one content — the +98 on this branch now contains both sets of fixes.

**Strengthening fact, verified this session:** `codemagic.yaml` defines **only `ios-workflow`**. There is no Android CI, so nothing rewrites `pubspec.yaml` on the Android path — the AAB comes from `build.sh` consuming pubspec as written. **+98 is what will ship.**

---

## 5. CLAUDE.md — mostly already done; I completed the remainder

The sibling session's `0899a86` had already corrected three claims. I verified each on this branch rather than assume:

| Claim | State |
|---|---|
| HTTP timeouts "5 s, fix must be re-applied" | **Corrected** — now documents 15 s as present and verified, with `areaAnyOnProvider` too |
| `nav.dart` is the dashboard | **Corrected** — now notes it is a four-line barrel and points at `wled_dashboard_page.dart` |
| `kSimulationMode` hardcoded `true` | **Corrected** — now `false`, with an explanation of why believing the old text would mislead a reader |
| **Riverpod "Bad state" as an active hazard** | **Was still outstanding at "Common Gotchas 1" — I completed it (`4e3049b`)** |
| targetSdk 35 / API-36 deadline | **Not in CLAUDE.md at all** — see below |

**What I added, and why it isn't a duplicate.** "Common Gotchas 1" stated the rule with no indication of the code's actual state, so a reader could not tell whether they were being warned about an outstanding defect or handed a convention. **I swept before writing it down:** zero cached `*Notifier` fields anywhere in `lib/`, and exactly **two** `ref.` uses inside a `dispose()` body — `installer_setup_wizard.dart:320` (synchronous) and `pattern_theme_selection.dart:218` (captures the notifier before its microtask, naming the `debug_errors` doc it fixes). Both deliberate and already commented. The rule stays; the current state is now recorded alongside it.

**Deliberately not changed:** the "targetSdk 35 / API 36 deadline approaching" claim. **CLAUDE.md never mentioned targetSdk.** That claim lives in `audit/COMPLIANCE_AND_SECURITY.md` items 2.3 and F-13, which still describe API 36 as a future risk — it shipped in +97 and the deadline passed 2026-08-31. I left it alone on purpose: that file is a **dated point-in-time audit record**, not living guidance, and rewriting its findings would destroy the trail. Recorded here instead.

---

## 6. Re-audit verdicts

Both platforms were re-audited against this branch's final state.

### Google Play — **NOT-YET** (unchanged overall; two more blockers cleared)

| # | Category | Verdict |
|---|---|---|
| 1 | Manifest & build config | **GO** — re-verified line by line; targetSdk/compileSdk 36, minSdk 24, signing config intact, FGS/boot/AD_ID stripped from the merged manifest |
| 2 | Data safety & secrets | **GO (code side)** — `openaiProxy` gone from source *and* production; no secrets in `lib/` |
| 3 | App identity & versioning | **GO — cleared.** +98 in both files; no Android CI can overwrite it |
| 4 | 12 testers × 14 days | **NOT-YET** — calendar, not engineering |
| 5 | Crash / stability | **GO with caveats** — improved |
| 6 | **App completeness** | **NOT-YET — new.** The fake "Remote Diagnostics (Pro)" tile (N-1) is consumer-reachable |
| 7 | **Third-party IP** | **NOT-YET — new.** Franchise/character marks as consumer navigation, no licence, no disclaimer (N-2) |

| Prior finding | Now |
|---|---|
| versionCode blocker | **FIXED** |
| R-1 dead splash | **FIXED** — both attempts bounded; `runApp` in a `finally` |
| R-2 prompt timing + FCM token | **FIXED** — verified in code and by test |
| R-3 staff-PIN screen / no router `errorBuilder` | **STILL OPEN** — quality, not policy |
| R-4 Back is a no-op on Home | **STILL OPEN** — quality, not policy |

**Name the right AI recipient.** With `openaiProxy` gone, OpenAI need not be declared — but **Anthropic must be**. `functions/package.json` carries `@anthropic-ai/sdk`, and both `lumina_ai_service.dart:772` and `event_lumina_service.dart:74` call `claudeProxy`. Chat text leaves the device → your Cloud Function → Anthropic. The Data Safety form and privacy policy should say **Anthropic**, not OpenAI, and not neither.

### Apple App Store — **NOT-YET**

| # | Area | Verdict |
|---|---|---|
| 1 | `Info.plist` usage strings | **NOT-YET** — 2 inaccurate strings, unused background modes, export-compliance flag |
| 2 | `PrivacyInfo.xcprivacy` | **NOT-YET** — exists and is correctly wired into the **Runner** target's Resources phase, but omits Financial Info and the e-signature |
| 3 | Account deletion 5.1.1(v) | **GO** — 4 taps from dashboard, re-auth first, fails safe |
| 4 | Reviewer / demo path | **NOT-YET** — the *code* is GO and better than the docs suggest; the blocker is entirely App Store Connect-side |
| 5 | Clean-install stability | **GO** — the notification prompt cannot now appear before sign-in, which is exactly what iOS review expects |
| 6 | `codemagic.yaml` iOS gate | **GO** — tag-only trigger, gate runs before the build-number rewrite, `PROJECT_BUILD_NUMBER` fail-fast present |
| 7 | Other rejection surfaces | **NOT-YET** — undisclosed staff gesture (2.3.1), privacy-policy content gap, **plus N-1 (2.1 fake feature) and N-2 (5.2.5 franchise IP)** |

**Two corrections to that audit, which I verified live and it could only doc-assert:**
- `purgeUserAccount` **is deployed** — confirmed by `firebase functions:list` this session, not inferred from `BUILD_LEDGER.md:2692`. Its item 7 is closed.
- Its item 10 (suite green) is closed: **2989 passed · 4 skipped · 0 failed**, run outside the #64 midnight window, plus `flutter analyze` at exactly the 0/12/373 baseline.

---

## 7. Left open

### Closed by this session
`openaiProxy` deployed-and-unused (Play B-9) · dead-splash vector R-1 · prompt timing + FCM token R-2 · versionCode at +98 · the last stale CLAUDE.md claim.

### Out of scope by instruction — flagged, not attempted
- **Analytics opt-out toggle** — decision is to remove the unmet promise from the policy, so no code change. Confirmed the mechanism is still unwired: `analyticsPreferenceNotifierProvider` (`analytics_providers.dart:205`) has **zero consumers**. Found no *other* code implying analytics is user-toggleable.
- **H-10** (rules audit of `sales_jobs` / `installation_records` / `email_notifications`) and **H-11** (public estimate URL PII) — untouched, status unchanged.
- Anything needing Play Console, App Store Connect or Google Cloud Console.

### 🔴 Two NEW findings that outrank everything else on this list

Neither appeared in any prior audit. I verified both myself by reading the source, because both change the submission picture and both affect **Play and Apple equally**. Neither is in this session's step list, and neither is a mechanical fix — one is a product decision, the other is a legal one — so both are flagged, not touched.

**N-1 · A fake feature ships in consumer Settings — the cleanest rejection trigger in the app.**
`lib/features/site/settings_page.dart:519-530` renders a tile **"Remote Diagnostics (Pro)"** — *"Upload system logs to help our team diagnose hardware issues."* Tapping it calls `_uploadDiagnostics()` (a modal spinner, `:419-432`) then `_simulateUpload()` (`:434-444`):

```dart
await Future.delayed(const Duration(milliseconds: 1600));
Navigator.of(context).pop();
... AlertDialog(title: Text('Success'),
                content: Text('Success. Ref ID: #8821.'))
```

**Nothing is uploaded.** No network call, no Firestore write, no Storage put. The delay is cosmetic and `#8821` is a **hardcoded constant** — the same "reference ID" for every user, every tap, forever. It is reachable in about three taps from the bottom-nav System tab.

This is Apple **Guideline 2.1 (App Completeness)** and the Play equivalent (non-functional / misleading feature). A reviewer who taps it twice and sees an identical Ref ID, or who watches the network, has an open-and-shut rejection. The `(Pro)` suffix compounds it by implying a paid tier that does not exist and cannot be bought. By contrast the two neighbouring screens with similar delay loops — `bridge_setup_screen.dart:617-649` and `remote_access_screen.dart:309-340` — are **real**: they write a command doc and poll for `status == 'completed'`. Only this tile is theatre.

**Recommendation: delete the tile, or implement it.** Deleting is a two-line change but it removes a user-facing feature, which is Tyler's call, not mine.

**N-2 · Third-party franchise IP is used as consumer navigation, with no licence and no disclaimer.**
The prior audits flagged sports team names. The larger exposure is `lib/data/movies_superheroes_palettes.dart`, surfaced into the consumer **Explore** tab as category `cat_movies` ("Movies & Superheroes", `pattern_repository.dart:835`) — roughly two taps from home. Verified folder names at `:15,25,35,45,55,65,75,85`:

> `Disney Classics` · `Marvel` · `Star Wars` · `DC Comics` · `Pixar` · `DreamWorks` · `Harry Potter` · `Nintendo & Gaming`

and character palettes including `Mickey Mouse` (`:102`), `Spider-Man` (`:219`), `Darth Vader` (`:336`), `Grogu (Baby Yoda)` (`:436`), `Batman` (`:453`), `Hogwarts` (`:794`), `Super Mario` (`:861`), `Pikachu` (`:891`).

These are **character and franchise marks used as UI labels**, not descriptive colour words — a different and weaker position than "Chiefs Red". Disney, Lucasfilm, Marvel, WB/DC, Nintendo and The Pokémon Company are among the most active enforcers on both stores. Related, same class: golf tournament folders (`The Masters`, `Amen Corner`, `Magnolia Lane`, `Ryder Cup`) in `golf_library_builder.dart:9-38`, and a `'Barbie Pink'` palette.

**Mitigating, and it matters:** **no logos or brand artwork are bundled.** `find assets -type f` returns 8 files, none of them team or franchise art. That is the difference between "likely rejection" and "certain rejection".

**Aggravating:** there is **no trademark disclaimer anywhere in the app** — no "not affiliated with", no "marks are property of their respective owners". That is the cheapest available mitigation and it is absent.

**Recommendation:** a legal call for Tyler. Cheapest partial mitigations are renaming franchise folders to descriptive labels and adding a disclaimer footer on the `cat_movies` and `cat_sports` category screens.

### Other new findings from the re-audits — none fixed here
1. **Reviewer access on Play is Apple-branded.** The new demo door (`route_guards.dart:290`) lands on a **server-validated code prompt**; the only lead-capture bypass triggers on `dealerCode == 'APPLE-REVIEW'` (`demo_code_screen.dart:89`). A **Play** reviewer given that flow needs a working, active, unexpired code with `maxUses` headroom — or full credentials. *Most likely source of an avoidable rejection.*
2. **`dealer_demo_codes` is world-readable** — `firestore.rules:1484` `allow read: if true`, and `read` covers `list`, so every dealer demo code is enumerable unauthenticated. **Pre-existing, not introduced by this branch.** Security finding, not a store blocker.
3. **Customer e-signatures escape the account purge.** Written to `sales_jobs/{jobId}/signature_*.png`, not under `users/{uid}/`, so `purgeUserAccount` never sweeps them. **Not currently recorded in `PENDING_PHASE_2`** — an unrecorded gap. Same applies to job-site photos.
4. **iOS `Info.plist` declares unused background modes** — `fetch` and `processing` plus two `BGTaskSchedulerPermittedIdentifiers` that nothing registers (`kSportsBackgroundServiceEnabled = false`). Guideline 2.5.4. `remote-notification` is justified and should stay.
5. **`ITSAppUsesNonExemptEncryption = false` is very likely a misstatement** — the app ships and actively uses third-party AES-256 on user PII. Legal/compliance call.
6. **Latent iOS Maps crash, currently unreachable** — `GMSServices.provideAPIKey` is never called, and `GoogleMap` is instantiated in two screens. Neither is reachable today (`/settings/geofence` has no navigator). **Fix before anyone wires a button to that route.**

### Requires manual confirmation — no Console access from here
1. **`versionCode 98` has never been uploaded** — check Play before building. This is exactly the class of problem that consumed 97.
2. **Firestore rules on this branch are NOT deployed.** The sibling session confirmed against the live ruleset that `integrations` and `game_day_crews` are absent from it. Their new blocks are **inert until `firebase deploy --only firestore:rules` runs.** I deliberately did not deploy: it was outside my step list, it is another session's change, and per standing rule the deployed SHA must first be asserted an ancestor of `main` — deploying a server half without its app half is how the +74 join regression happened.
3. **ASC App Review Information** — email exactly `reviewer@nex-genled.com` (**hyphenated**) and the password from the 2026-08-13 rotation. Three in-repo docs still carry the non-existent hyphen-less form (`SUBMISSION_AUDIT_v1.0.0.md:253,262,289`, `BUILD_LEDGER.md:1714`, `COMMAND_SAFETY.md:634`) — that is *how the blocker keeps recurring*. Applies to **Play's App Access declaration too**, not just Apple.
4. **Review notes must disclose the 5-tap staff gesture** (Guideline 2.3.1). Two sentences; highest value-per-minute item on this list.
5. **Data Safety form / nutrition label** — name **Anthropic**; add **Financial Info** and the e-signature; cover Nominatim, Photon, Open-Meteo and Google Fonts as recipients of address text, precise location and IP.
6. **Revoke the OpenAI API key** and remove `OPENAI_API_KEY` from `functions/.env`.
7. **Firebase API-key restrictions** in GCP — the Android key doubles as a billable Places key.
8. **Codemagic UI trigger is tag-only** — `codemagic.yaml` cannot disable a trigger it does not own.
9. **Legal sign-off on 155+ team and league names** (Guideline 5.2) — reviewer-visible, since the reviewer seed sets `sportsTeams: ['Chiefs','Royals']`.

### Operational reminder
Do not push a `build-*` tag while the Codemagic runner's local clock is inside **22:30–00:00** — bug #64 turns the whole gate red on a flake, not a regression.

---

## 8. Confirmations

| Item | Status |
|---|---|
| `origin/main` tip verified fresh | ✅ `699a498`, `2.5.10+97` |
| Built on a tree at or ahead of `origin/main` | ✅ branched off its exact tip, then rebased onto the canonical branch twice |
| No ref belonging to another worktree was moved | ✅ |
| Explicit pathspec on every commit | ✅ 1, 3 and 1 files — no `git add -A`, no `git stash` |
| `FUNCTIONS_DISCOVERY_TIMEOUT=180` on the deploy | ✅ |
| Deletion verified by `functions:list`, not by the success message | ✅ twice |
| Steps 1–3 verified, not just applied | ✅ production check, `git diff -w`, and a negative-controlled test |
| Version in both files, same commit | ✅ `2.5.10+98` |
| `flutter analyze` | ✅ 0 errors / 12 warnings / 373 infos — baseline exactly |
| `flutter test` | ✅ 2989 passed · 4 skipped · 0 failed |
| Nothing built, uploaded or submitted | ✅ |
