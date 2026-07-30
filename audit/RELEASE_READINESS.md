# Lumina — Release Readiness Audit

**Scope:** Does the release build correctly, and does it break existing users?
**Explicitly out of scope:** feature logic, store metadata (Windows A and B).
**Audited commit:** `393af46` (main), working tree clean, `2.5.10+58`
**Date:** 2026-07-30
**Method:** read-only. One build was executed (`flutter build appbundle --release`). No source file was modified, no branch created.

---

## 1. Go / No-Go Summary — Release Mechanics

### **GO for submission.** Zero P0-BLOCK findings.

I could not construct a P0 against the release mechanics. Specifically, the thing this audit was most worried about — the schedules array→subcollection migration eating a paying customer's data on upgrade — **cannot fire in the shipped build**, because the feature flag that gates it defaults false and no client ever writes that flag. Details in §2.

What is verified good:

| Check | Result | Evidence |
|---|---|---|
| Release build compiles | **PASS** — exit 0, 65.0 MB AAB | `flutter build appbundle --release --obfuscate` |
| versionCode baked correctly | **PASS** — 58, from merged manifest not pubspec | `build/app/intermediates/.../AndroidManifest.xml` |
| Points at production Firebase | **PASS** — `icrt6menwsv2d8all8oijs021b06s5` on all 3 platforms | [firebase_options.dart](lib/firebase_options.dart), [firebase.json](firebase.json) |
| No bench IP in a release path | **PASS** — every `192.168.*` is a hint string, comment, or dead sim branch | see §5 F-9 |
| Simulation mode off | **PASS** — `kSimulationMode = false` | [app_providers.dart:17](lib/app_providers.dart#L17) |
| Verbose logging off in release | **PASS** — `debugPrint` globally nulled | [main.dart:128-130](lib/main.dart#L128-L130) |
| Secrets not committed | **PASS** — `functions/.env` untracked + gitignored | `.gitignore:189-190` |
| Keystore valid | **PASS** — expires **2053-09-13**, SHA256withRSA 2048 | `keytool -list` on `android/app/nex-gen-lumina.keystore` |
| Remote kill switches exist | **PASS** — 4 independent flags | §5 F-6 |
| Working tree clean | **PASS** — 0 modified, 0 untracked | `git status --porcelain -uall` |

**Two caveats attached to that GO**, neither approval-preventing:

1. **The release build was compiled but not launched on a device.** Installing the AAB needs the wireless-ADB port, which churns on every toggle and needs your input. Given `2.5.10+55` shipped a dead splash screen, "it compiles" is materially weaker evidence than "it launches." See F-4 — this is the one item I'd want closed before you press submit, and it costs about 15 minutes.
2. **Cloud Functions must be rebuilt before their next deploy.** A committed compiled artifact is stale and is missing a security fix present in source. It does not affect the app binary or store review. See F-1.

---

## 2. Upgrade-Path Test Results

### 2.1 Schedules array → subcollection

**The migration is real, complete, and well-engineered.** (My own memory index had this recorded as "PLAN ONLY" — that was stale; it is fully implemented.)

Architecture as actually built:

- Flag `config/schedules_subcollection`, **defaults false** — [schedules_subcollection_feature_flag.dart:66-85](lib/features/schedule/schedules_subcollection_feature_flag.dart#L66-L85)
- Backend selected off that flag — [schedule_repository.dart:54-59](lib/features/schedule/data/schedule_repository.dart#L54-L59)
- Client lazy migrator — [schedule_lazy_migrator.dart](lib/features/schedule/data/schedule_lazy_migrator.dart)
- Server backfill — [functions/src/backfillSchedulesSubcollection.ts](functions/src/backfillSchedulesSubcollection.ts), shared planner [scheduleMigrationShared.ts:127-166](functions/src/scheduleMigrationShared.ts#L127-L166)
- Bidirectional dual-write — [legacy_array_schedule_repository.dart](lib/features/schedule/data/legacy_array_schedule_repository.dart), [subcollection_schedule_repository.dart](lib/features/schedule/data/subcollection_schedule_repository.dart)

**Scenarios evaluated** (by code trace against seeded-shape reasoning — see the honesty note below):

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | Oldest supported version → RC, flag OFF (**the shipping case**) | **No migration runs at all.** Reads/writes the legacy array, byte-identical to prior releases. | `ensureMigrated` is called only under `if (subEnabled)` — [schedule_providers.dart:54-61](lib/features/schedule/schedule_providers.dart#L54-L61) |
| 2 | Migration correctness / completeness | **PASS.** Iterates the RAW array so malformed elements consume their index slot; client and server assign identical sortKeys. | [schedule_lazy_migrator.dart:93-98](lib/features/schedule/data/schedule_lazy_migrator.dart#L93-L98) vs [scheduleMigrationShared.ts:138-155](functions/src/scheduleMigrationShared.ts#L138-L155) |
| 3 | Idempotency — run twice | **PASS, two independent guards.** Durable: `schedulesMigratedAt` marker checked before any write. In-session: per-uid in-flight future. Server rerun preserves existing sortKey, never renumbers. | [:86](lib/features/schedule/data/schedule_lazy_migrator.dart#L86), [:65-76](lib/features/schedule/data/schedule_lazy_migrator.dart#L65-L76), [scheduleMigrationShared.ts:148-150](functions/src/scheduleMigrationShared.ts#L148-L150) |
| 4 | Partial failure / crash mid-write | **PASS — cannot half-migrate.** Upsert is a single atomic `batch.commit()`, and the marker is stamped *after* it. Crash between the two → marker unset → retries next launch. Re-upsert is a `set` on the same doc ids, so it converges. | [:99-108](lib/features/schedule/data/schedule_lazy_migrator.dart#L99-L108) |
| 5 | Batch-size overflow | **PASS.** `MAX_SCHEDULES = 50`, an order of magnitude under Firestore's 500-op batch cap. | [scheduleMigrationShared.ts:16](functions/src/scheduleMigrationShared.ts#L16) |
| 6 | User skips several versions | **PASS.** Migration is keyed on data shape (marker present / array contents), never on an app-version number. A user jumping any number of releases takes the identical path. | no version predicate anywhere in [schedule_lazy_migrator.dart](lib/features/schedule/data/schedule_lazy_migrator.dart) |
| 7 | Migration throws | **PASS.** Caught and logged; the stream falls through and reads the subcollection as-is. Unset marker means it retries. | [schedule_providers.dart:57-60](lib/features/schedule/schedule_providers.dart#L57-L60) |
| 8 | Rollback after the flag is flipped on | **PASS — zero data loss.** All five mutations mirror in **both** directions, so the legacy array stays current the whole time. Rollback = flip flag false. | all 5 methods in both repos carry a `runMirror` (`legacy.*->sub` / `sub.*->array`) |
| 9 | Offline / mid-write failure | **PARTIAL — see F-5.** Writes queue durably in the Firestore SDK and replay, so no loss. But a *first* launch under flag ON with a cold cache can read an empty subcollection and briefly render "no schedules." | [:81-82](lib/features/schedule/data/schedule_lazy_migrator.dart#L81-L82) |

**Two traps I specifically checked for and did *not* find:**

- **`orderBy` silently dropping documents.** The subcollection reader uses `.orderBy('sortKey')` ([subcollection_schedule_repository.dart:54](lib/features/schedule/data/subcollection_schedule_repository.dart#L54)), and Firestore excludes docs missing the ordered field entirely — a mirrored doc without `sortKey` would have become invisible. `toJson()` emits `sortKey` unconditionally, explicitly commented as non-optional ([schedule_models.dart:163-164](lib/features/schedule/schedule_models.dart#L163-L164)). Safe.
- **sortKey tie-collapse.** Legacy items deserialize to `sortKey: 0`, which would tie and scramble order. There is a deliberate `current.length` floor in the seed to clear a contiguous backfilled block, with the reasoning written out ([schedule_providers.dart:484-505](lib/features/schedule/schedule_providers.dart#L484-L505)). Safe, and the author flagged it as "a safety net, not a proof."

> **Honesty note on "test it explicitly with seeded old-format data."** I did **not** execute the migration against seeded legacy data. Doing so writes to Firestore (emulator or project) and stands up the emulator suite, which exceeds a read-only audit. What I did instead: traced both implementations line-by-line and confirmed the client and server planners agree on index accounting and sortKey policy. The repo already contains the executable proof — `functions/test/emulator/scheduleFunctions.emulator.test.ts` covers backfill idempotency and dry-run-writes-nothing, recorded green 8/8 on 2026-07-10 ([ROLLOUT_RUNBOOK.md:51](docs/ROLLOUT_RUNBOOK.md#L51)). **Re-running that suite is the correct gate before flipping the flag, and it is not a submission gate.** Cost: 1h including JDK 21 setup.

### 2.2 Other schema migrations

| Migration | Trigger | Assessment |
|---|---|---|
| `ConnectionMethodMigration` | Auth listener, non-anonymous sign-in | **SAFE.** Fires via `ref.listen`, never awaited on the startup path; all errors swallowed at two levels. Guarded by SharedPreferences *and* data-level idempotency (`migrationPatchFor` returns null when already migrated), so a reinstall re-running it is harmless. [connection_method_migration.dart:59-112](lib/services/connection_method_migration.dart#L59-L112), wired [main.dart:395-403](lib/main.dart#L395-L403) |
| Roofline legacy mask → `RooflineConfiguration` | Dashboard mount | **SAFE.** One-shot lazy, legacy doc marked not deleted. [roofline_config_providers.dart:337](lib/features/design/roofline_config_providers.dart#L337) |
| Legacy config → per-controller pixelMap | First per-controller read | **SAFE.** Cheap existence guard first; legacy doc retained for rollback/audit rather than deleted. [roofline_config_providers.dart:178-207](lib/features/design/roofline_config_providers.dart#L178-L207) |
| `migrateClearScheduleItemsV1` | Manual callable | Server-side, operator-invoked. Not on the upgrade path. |

No migration in the codebase deletes its source data. That is the single most important property for upgrade safety and it holds universally.

### 2.3 Firestore composite indexes

19 composite indexes defined in [firestore.indexes.json](firestore.indexes.json), 0 field overrides. The schedules subcollection needs none — `.orderBy('sortKey')` is single-field and auto-indexed.

**UNVERIFIED: whether these are deployed.** That is Firebase console state and I have no credentials. `firebase.json` wires the file, but nothing auto-deploys — the runbook is explicit that rules/functions/indexes are each a separate manual step ([ROLLOUT_RUNBOOK.md:7-9](docs/ROLLOUT_RUNBOOK.md#L7-L9)). See Q1.

### 2.4 Cloud Functions deploy parity

**Repo-internal parity is BROKEN — see F-1.** I compiled `functions/src` to a scratch directory and hashed every emitted `.js` against the committed `functions/lib`. 30 of 31 match. One does not.

### 2.5 Controller firmware compatibility

The app reads `ver` from `/json/info` ([wled_service.dart:276](lib/features/wled/wled_service.dart#L276)) but **only ever displays it** — installer setup screen ([controller_setup_screen.dart:740](lib/features/installer/screens/controller_setup_screen.dart#L740), [:1299](lib/features/installer/screens/controller_setup_screen.dart#L1299)). There is **no compatibility floor, no version comparison, and no gating anywhere in `lib/`.**

Meanwhile the entire effect catalog is hard-pinned to WLED 0.15.1 effect IDs ([effect_database.dart:1858](lib/features/wled/effect_database.dart#L1858), [wled_effects_catalog.dart:256](lib/features/wled/wled_effects_catalog.dart#L256)).

**This is not a new regression.** The 0.15.1 pinning is long-standing and shipped in prior 2.5.x releases, so the RC does not newly break older field firmware — it inherits the existing assumption. That keeps it off the blocking path. See F-7 and Q4.

---

## 3. Branch Disposition

`origin/main` @ `393af46`. Working tree clean.

| Branch | Ahead | Behind | Disposition |
|---|---|---|---|
| `feat/schedule-cfg-harden` | 0 | 42 | **MERGED** — safe to delete |
| `feat/schedule-picker-cfg` | 0 | 36 | **MERGED** — safe to delete |
| `feat/sunrise-off-toggle` | 0 | 2 | **MERGED** (`c290a6c`, +58) — safe to delete |
| `fix/android-securestorage-hang` | 0 | 9 | **MERGED** — the +55 dead-splash fix is in main |
| `fix/p0-3-lease-writer` | 0 | 30 | **MERGED** — P0-3 lease pre-arm is in main |
| `feat/voice-canonical-commands` | 4 | 125 | **UNMERGED — and should stay that way for this release.** See §3.1 |
| `fix/neighborhood-join-membership` | 2 | 10 | **UNMERGED — carries user-visible fixes.** See F-8 |
| `feat/dealer-team-empty-state` | 1 | 11 | **UNMERGED** — dealer Team-tab empty-state deadlock fix. Dealer-facing, not customer-facing |
| `hotfix/rollback-55` | 1 | 33 | **ABANDONED** — emergency rebuild of +53, superseded by +58 |
| `firmware/phase-1-provisioning-persistence` | 1 | 605 | **ABANDONED as a branch** — ESP32 firmware, not app. 605 behind |
| `feature/commercial-ux-rework` | 1 | 435 | **ABANDONED as a branch** — single docs commit, 435 behind |

### 3.1 `feat/voice-canonical-commands` — resolved

**Is it merged to the release line?** **No.** 4 commits ahead of main.

**If it ships enabled without certification, is that a compliance problem?** **The question does not arise, and this is the important finding:**

```
functions/index.js                           | 235 +-
functions/src/voice/{intentCore,alexaSmartHome,alexaJwt,googleSmartHome}.ts | new
functions/test/voice/*.ts                    | new
docs/VOICE_LAUNCH_CHECKLIST.md               | new
```

**All 16 changed files are `functions/`, tests, or docs. Zero files under `lib/`.** The branch is entirely server-side Cloud Functions. None of it can be compiled into the app binary under any circumstance.

**Your recommendation is correct, and the cost is lower than you assumed:**

- External certification should **not** block submission.
- Shipping it dark costs **0 hours and requires no flag** — leaving the branch unmerged and not deploying those functions is already "dark." There is nothing to gate, because there is no client code.
- Certification can complete on its own timeline and be activated later by deploying functions, with **no app release required**.

One caveat worth your attention: a **legacy** voice surface already exists on main — `alexaAuth`, `alexaToken`, `alexaUnlink`, `generateAlexaAuthCode`, `googleSmartHome`, `googleAuth`, `googleToken`, `generateGoogleAuthCode` are all exported from [functions/index.js](functions/index.js), and `lib/features/voice/` (9 files, 2,852 lines) is on main. Whether the app *advertises* Alexa/Google linking in reachable UI is a **feature-surface question that belongs to Window A or B**, not to release mechanics. I flag it as Q3 rather than assessing it.

### 3.2 Unmerged commits fixing P0/P1 from Windows A/B

I read `audit/HANDOFF_TO_WINDOW_B.md` (the only file in `audit/` at audit time). **I have no visibility into Windows A/B findings**, so I cannot map their P0/P1 list onto branches. What I can state factually: the only unmerged branches carrying non-doc code are `fix/neighborhood-join-membership` (2), `feat/dealer-team-empty-state` (1), and `feat/voice-canonical-commands` (4, server-only). See Q2.

---

## 4. Findings

No finding below is P0-BLOCK. I attempted to construct a P0 for F-1 (it is a security fix absent from a build artifact) and could not sustain it — see the severity note in that row.

| ID | Sev | Finding | Est | Conf |
|---|---|---|---|---|
| F-1 | **P1** | Cloud Functions compiled-output drift | 0.5h | **High** |
| F-2 | **P1** | No crash reporting for pre-auth crashes; obfuscated stacks unsymbolicated | 4h | **High** |
| F-3 | **P1** | No fleet monitoring — a fleet-wide schedule failure is invisible | 8h | **Medium** |
| F-4 | **P1** | Release build compiled but never launched | 0.5h | **High** |
| F-5 | **P2** | Cold-cache offline read under flag ON can render "no schedules" | 2h | **Medium** |
| F-6 | — | Kill-switch coverage (informational, no action) | — | **High** |
| F-7 | **P2** | No firmware compatibility floor | 4h | **Medium** |
| F-8 | **P2** | Neighborhood join fixes unmerged | 1h | **Medium** |
| F-9 | **P3** | Stale CLAUDE.md claims | 0.5h | **High** |
| F-10 | **P3** | `functions/lib` build output committed to VCS | 1h | **High** |
| F-11 | **P3** | `minifyEnabled = false` → 65 MB AAB | 2h | **Medium** |

---

### F-1 — P1-LAUNCH — Cloud Functions compiled-output drift · 0.5h · High confidence

`functions/index.js` requires from `./lib/` (tsc output), and `functions/lib` is **git-tracked** (78 files, no `functions/.gitignore`). I compiled `src` to a scratch dir and hash-compared:

```
DIFFERS: applySyncPattern.js     (committed 487 lines, fresh compile 546)
```

All 30 other files match. The committed artifact is missing **SYNC-1 server-side crew-membership verification** — commit `76324ce`, *"closes self-fanout DoS."* Absent from `functions/lib/applySyncPattern.js`: `verifyFanoutTarget()`, the `memberUids[]` cross-check, and the skip-unverified-target guard.

**Concrete mechanism if deployed stale:** a fanout could write `RemoteCommand` documents into the command queue of a uid that holds only a one-sided/orphaned member-subcollection doc — i.e. control of another household's lights without mutual consent.

**Why P1 and not P0.** Two independent conditions must both hold for exposure, and neither does today:
1. The server-side fanout path is gated on `config/sync_fanout.enabled`, **default false** ([applySyncPattern.ts:160,311-316](functions/src/applySyncPattern.ts#L160)).
2. That path is documented **dormant in production** — the flag doc is unreadable ([BUGS_AND_DEBT.md:216](docs/BUGS_AND_DEBT.md#L216), P1-44).

With fanout off, no fanout write occurs at all, so the missing verification is unreachable. It is also entirely server-side: it does not touch the app binary and cannot affect store review. **It is not on the submission path.**

**It does become a genuine P0 the moment `sync_fanout` is flipped on with stale functions deployed.**

**Fix:** `cd functions && npm run build && firebase deploy --only functions`. Note `npm run deploy` already chains the build; a bare `firebase deploy --only functions` from repo root does not, which is how this drifted.

**Do this before flipping `sync_fanout`, not before submitting.**

### F-2 — P1-LAUNCH — Crash reporting has two structural blind spots · 4h · High confidence

There is **no Crashlytics and no Sentry** — absent from [pubspec.yaml](pubspec.yaml). In their place is a homegrown sink writing to `/users/{uid}/debug_errors/{autoId}` ([main.dart:64-99](lib/main.dart#L64-L99)), wired to both `FlutterError.onError` and `PlatformDispatcher.onError` ([main.dart:108-123](lib/main.dart#L108-L123)). The rationale is documented and reasonable: you have no Mac, so Crashlytics/TestFlight logs are unreadable to you ([main.dart:56-61](lib/main.dart#L56-L61)).

Two gaps:

1. **Pre-auth crashes are silently dropped.** `if (uid == null) return;` ([main.dart:73-74](lib/main.dart#L73-L74)). Every crash before sign-in completes writes nothing, anywhere. **This is exactly the `2.5.10+55` dead-splash class of bug** — the one failure mode with a live precedent in this app, and the sink is blind to it by construction.
2. **Stacks are unreadable.** The build runs `--obfuscate --split-debug-info=build/debug-info/android`. Captured traces are obfuscated text with no symbolication pipeline. Symbol files exist locally but nothing maps a stored trace back through them.

Native (JVM/ObjC) crashes are also uncaptured, though that is inherent to a Dart-level handler.

**Mitigation actually present:** `_startupBreadcrumb` uses raw `print()` deliberately so the startup trace survives release logcat ([main.dart:46-48](lib/main.dart#L46-L48), rationale at [:125-127](lib/main.dart#L125-L127)) — `adb logcat | grep LUMINA_STARTUP` remains your startup diagnostic. That is a real and well-chosen mitigation for gap 1, but it needs a USB/ADB-connected device, so it does not cover field users.

**Suggested fix:** buffer pre-auth errors in SharedPreferences and flush on the next successful sign-in (~2h), plus a documented `flutter symbolize` runbook (~2h).

### F-3 — P1-LAUNCH — No fleet monitoring · 8h · Medium confidence

Direct answer to 4.4 — *"will you know within an hour if schedules stop firing fleet-wide?"*: **No. You would find out from customer calls.**

The only scheduled function is `scheduledDataCleanup` (daily, 04:00). No health check, no aggregation, no alerting anywhere in `functions/`. The `debug_errors` sink is **per-user** — diagnosing a fleet event means opening user documents one at a time in the console.

Confidence Medium because I verified absence of alerting *in the repo*; external monitoring (a GCP alerting policy, an uptime check) would not appear in source and may exist. See Q5.

**Cheapest meaningful version:** a scheduled function counting `debug_errors` created in the last hour across users, emailing via the already-integrated Resend when it crosses a threshold. ~8h. Genuinely worth doing in the first two weeks, not before submission.

### F-4 — P1-LAUNCH — Release build compiled but not launched · 0.5h · High confidence

`flutter build appbundle --release --obfuscate` returned **exit 0** and produced a 65.0 MB AAB with versionCode 58 correctly baked. That proves it *compiles*; it does not prove it *launches*.

Given `2.5.10+55` shipped a dead splash — and per [project_android_securestorage_launch_hang](memory) the `e9c6575` fix in +56 is recorded **UNVERIFIED** — compile-only evidence is materially weaker than this release needs.

I did not install it: per your standing instruction the wireless-ADB port churns on every toggle and I must ask you first.

**Recommended:** install this exact AAB (or its APK equivalent) on a real device, cold-launch it, and confirm `adb logcat -d | grep LUMINA_STARTUP` reaches past the securestorage step. ~15 minutes. **This is the single highest-value pre-submit action in this report.**

### F-5 — P2-FOLLOW — Cold-cache offline read under flag ON · 2h · Medium confidence

Under flag ON, first launch while offline: `userRef.get()` ([schedule_lazy_migrator.dart:81](lib/features/schedule/data/schedule_lazy_migrator.dart#L81)) serves from cache. On a cold cache `!snap.exists` returns early without stamping the marker (correct — it retries), but the subsequent subcollection read also has nothing cached, so the user sees an empty schedule list until connectivity returns.

**No data loss** — writes queue durably in the Firestore SDK and replay, and the legacy array remains authoritative. This is a transient empty-state, not corruption. Irrelevant at launch since the flag ships OFF; it becomes relevant during staged rollout.

### F-6 — Informational — Kill-switch coverage is good · no action

Answering 4.1 directly: **a remote kill-switch mechanism already exists**, and you should not spend pre-launch time building one. Four independent Firestore-backed flags, all default-false, all fail-safe:

| Flag | Gates | Reader |
|---|---|---|
| `config/schedules_subcollection` | schedules storage backend | [schedules_subcollection_feature_flag.dart:41](lib/features/schedule/schedules_subcollection_feature_flag.dart#L41) |
| `config/sync_fanout` | neighborhood server fanout | [sync_fanout_feature_flag.dart:24](lib/features/neighborhood/sync_fanout_feature_flag.dart#L24) |
| `config/solar_scheduling` | solar schedule encoding | [solar_scheduling_feature_flag.dart:27](lib/features/schedule/solar_scheduling_feature_flag.dart#L27) |
| `config/calendar_leases` | calendar lease timers | [calendar_lease_feature_flag.dart:20](lib/features/schedule/calendar_lease_feature_flag.dart#L20) |

The schedules flag additionally supports **per-uid allowlist and stable-bucket percentage rollout** ([:104-114](lib/features/schedule/schedules_subcollection_feature_flag.dart#L104-L114)) with an md5-based bucket that is release-invariant, so a uid never flip-flops backends. All four collapse to false on missing doc, malformed field, stream error, or the provider loading window. Rules restrict them to authenticated read-only ([firestore.rules:1450-1501](firestore.rules#L1450-L1501)).

This is the strongest single piece of launch engineering in the audited surface. **The riskiest features are already off the "must be perfect" path.**

### F-7 — P2-FOLLOW — No firmware compatibility floor · 4h · Medium confidence

Covered in §2.5. `info.ver` is read and displayed but never gates behavior, while the effect catalog is pinned to 0.15.1 IDs. A field controller on 0.14.x or 0.15.4 may resolve effect IDs differently.

**Not a launch blocker** because the pinning is pre-existing, not introduced by this RC. Medium confidence because I could not determine the actual field firmware distribution — see Q4.

### F-8 — P2-FOLLOW — Neighborhood join fixes unmerged · 1h · Medium confidence

`fix/neighborhood-join-membership` (2 commits, 10 behind main) carries `ab00f35` *"reflect successful join in UI + surface join errors (was silent-success)"* and `315b400` *"leave-sync no longer forces master off on restart."* A silent-success join is a plausible week-one support call. Both are customer-facing.

Medium confidence on severity: I did not audit the neighborhood feature logic (out of scope), only the branch state. Merge decision should account for Windows A/B findings.

### F-9 — P3-DEBT — Stale CLAUDE.md claims · 0.5h

Three claims in `CLAUDE.md` contradict the code. Left as-is per read-only rules; noting because they misled this audit and will mislead the next:
- "`kSimulationMode` currently hardcoded to `true`" — it is `false` ([app_providers.dart:17](lib/app_providers.dart#L17)).
- "HTTP timeouts currently 5 seconds / fix requires 15s" — presented as an outstanding KNOWN ISSUE; the timeout work has since shipped.
- "No automated tests currently exist" — there are 170 test files under `test/` plus emulator suites in `functions/test/`.

### F-10 — P3-DEBT — `functions/lib` committed to VCS · 1h

The structural cause of F-1: compiled output tracked in git with no `functions/.gitignore`, so `src` and `lib` can diverge silently and a bare `firebase deploy` ships whichever `lib` happens to be on disk. Gitignoring `functions/lib` and relying on the predeploy build removes the failure mode entirely.

### F-11 — P3-DEBT — `minifyEnabled = false` · 2h

[android/app/build.gradle:60-61](android/app/build.gradle#L60-L61) disables both minify and resource shrinking in the **release** buildType, contributing to the 65.0 MB AAB. Well under Play's limit and harmless; enabling R8 would cut download size but needs a keep-rules pass against the reflection-using plugins. Not launch-relevant.

---

## 5. Recommended Rollout Plan

**Before submitting — 1 hour total:**
1. **F-4: install and cold-launch the +58 AAB on a real device.** Confirm `LUMINA_STARTUP` breadcrumbs pass the securestorage step. *This is the only item I'd genuinely hold the button for.* (~15 min)
2. Confirm in the Play console that versionCode 58 exceeds every previously uploaded code. Local evidence says the highest consumed is 55, but console state is authoritative and I cannot see it. (~5 min)
3. Confirm Firestore **rules and indexes are deployed** (Q1). Nothing auto-deploys. (~15 min)
4. Leave `feat/voice-canonical-commands` unmerged. No action, no flag, no cost.
5. Decide on `fix/neighborhood-join-membership` (F-8) — merge only if it fits without delaying.

**Submit.**

Ship with **all four feature flags OFF**. The RC is then behaviorally identical to the current field build on every gated path, which is the whole point of the flag architecture.

**Staged rollout:**
- **Play:** staged rollout at 10% → 25% → 50% → 100%, holding ≥48h at each stage. Play staged rollout is available and should be used; the halt control is your fastest lever for an app-binary problem.
- **TestFlight:** external testing first if iOS ships in the same wave.

**Rollback procedure and realistic timings** (answering 4.3 — these differ by an order of magnitude, which is the important part):

| Problem class | Recovery | Time to effect |
|---|---|---|
| A flagged feature misbehaves | Flip the `config/*` doc to `enabled:false` | **Seconds to minutes** — clients hold a live `snapshots()` listener |
| Bad Cloud Function | Rebuild + redeploy, or roll back the function revision | ~10 min |
| Bad Firestore rules | Redeploy previous `firestore.rules` | ~5 min |
| **Bad app binary** | Halt Play staged rollout, then rebuild + resubmit | **Halt is minutes; a fixed binary is hours-to-days (review latency)** |

The asymmetry is the argument for the staged rollout: flag problems are instantly reversible, binary problems are not.

**Post-launch, in priority order:** F-2 (pre-auth crash capture, 4h) → F-3 (fleet alerting, 8h) → F-10 (gitignore `functions/lib`, 1h) → F-7 (firmware floor, 4h).

**Only after all of that**, begin the schedules subcollection rollout by following [docs/ROLLOUT_RUNBOOK.md](docs/ROLLOUT_RUNBOOK.md) from step (a). Re-run the emulator suite first — the recorded green is from 2026-07-10 and the code has moved since. **Do not begin this in the same window as the app release**; the runbook's own gates assume a stable baseline underneath.

---

## 6. Open Questions for Tyler

**Q1 — Are Firestore rules and composite indexes currently deployed?**
19 composite indexes are defined and `firebase.json` wires them, but nothing auto-deploys and I have no console access. A missing index is a runtime query failure that only appears at real data volume — exactly the failure mode that hides in testing. Please confirm, or run `firebase deploy --only firestore:rules,firestore:indexes`.

**Q2 — What did Windows A and B actually find?**
Task 2.3 asks me to identify unmerged commits fixing their P0/P1 issues, but I have no visibility into their findings — `audit/` contained only `HANDOFF_TO_WINDOW_B.md` when I ran. The candidate branches are `fix/neighborhood-join-membership` (2 commits) and `feat/dealer-team-empty-state` (1). If you share their lists I can map them in minutes.

**Q3 — Does the shipping app expose Alexa/Google account-linking UI?**
Legacy voice endpoints are live on main and `lib/features/voice/` is 2,852 lines. If the app *advertises* a voice integration that isn't certified and doesn't work end-to-end, that is a review and partner-branding risk — but it is a feature-surface question owned by Window A/B, not release mechanics, so I deliberately did not assess it. Worth confirming someone has.

**Q4 — What firmware versions are actually in the field?**
I could not determine this from the repo. The app enforces no compatibility floor while pinning effect IDs to 0.15.1. If any installed controller runs 0.14.x, effect resolution may already be wrong for that customer today. If the fleet is uniformly 0.15.1 per the dealer SOP, F-7 drops to P3.

**Q5 — Is there any monitoring outside the repo?**
F-3 assumes none because none exists in source, but a GCP alerting policy or uptime check would not appear in the codebase. If you already have one, F-3's estimate drops substantially.

**Q6 — Intentional: `dependenciesInfo.includeInApk/includeInBundle = true`?**
[build.gradle:66-69](android/app/build.gradle#L66-L69) embeds the dependency metadata blob. This is the Play-default and is *required* for Play's vulnerability scanning, so it looks deliberate — flagging only because it is an explicit non-default-looking block and some teams disable it. No action recommended.

---

### Verification boundary

Stated plainly, so nothing here reads as stronger than it is. **Verified by execution:** release AAB compiles (exit 0); versionCode 58 baked in the merged manifest; keystore valid to 2053; `functions/src` compiles clean and 30/31 emitted files match committed `lib`; git branch topology; working tree clean. **Verified by code reading:** every migration path, flag resolution, dual-write mirroring, logging suppression, crash-sink wiring. **Not verified:** deployed Firestore rules/indexes state; deployed Cloud Functions state; the app launching on a device; any iOS build (no macOS available); field firmware distribution; the migration executed against seeded legacy data.
