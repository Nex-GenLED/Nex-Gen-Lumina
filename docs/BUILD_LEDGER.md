# BUILD LEDGER — shipped artifact identity

One row per build that leaves this machine. **Purpose: given a crash report, a
TestFlight build, or a Play release, recover exactly which commit shipped.**

**Why this file exists:** the iOS and Android build numbers **do not match**.
`codemagic.yaml` overwrites pubspec's build number with Codemagic's own
`PROJECT_BUILD_NUMBER` counter before building the IPA:

```yaml
BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}
sed -i '' "s/^version: .*/version: ${VERSION_NAME}+${BUILD_NUM}/" pubspec.yaml
```

Only the version *name* (`2.5.10`) comes from pubspec on iOS. Android takes both
name and code from pubspec. So **the git SHA is the only identifier common to
both platforms** — it is the join key, and it is why this ledger is not
optional.

## Conventions

- **Never edit a row after the build is uploaded.** Append a correction row instead.
- Record the Android versionCode from the **merged manifest**
  (`build/app/intermediates/bundle_manifest/release/.../AndroidManifest.xml`),
  **not** from pubspec — they drift.
- Fill the iOS build number **when the Codemagic build completes**, not when it
  is queued. `PENDING` is an honest value; a guess is not.
- Archive `build/debug-info/<platform>/*.symbols` per build. Never commit them.

---

## 2.5.10+65 — rebuild at versionCode 65 (no app-code change since +64)

| Field | Value |
|---|---|
| **Git SHA** | `361c958` — the build commit (the version bump itself) |
| **Merged to main** | built directly on `main`; no feature branch — the bump is the only change |
| **Version name** | `2.5.10` |
| **Android versionCode** | **65** — verified from the merged manifest (`android:versionCode="65"`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,237,538 bytes · built 2026-08-05 16:23 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android signing** | `jar verified` — CN=Tyler Honeycutt, OU=Nex-Gen LED LLC (correct upload key) |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | **n/a** — Android-only rebuild; no IPA cut at this version |

> ### WHAT CHANGED SINCE +64: NO APP CODE.
>
> `git diff 68786e9..361c958 -- lib/ android/ ios/` is empty apart from the two version constants.
> Everything on `main` since +64 is server-side or documentation:
>
> - **`firestore.rules` DEPLOYED** (ruleset `93c99c50`) — `config/solar_scheduling` + the
>   `controller_ips` command-safety rule. **This is why +65 behaves differently from +64 in the
>   field despite identical app code:** +64's solar surfaces were shut only because the rules
>   blocked the flag read. Any build from `68786e9` onward un-gates solar now that the rule is live.
> - **`scheduledDataCleanup` DEPLOYED** — first retention run, 3,985 documents.
> - **C5 cleanup-query caps** in `functions/` — committed, **NOT deployed**.
>
> `kStaffAuthTelemetryAppVersion` bumped to `2.5.10+65` in the same commit so S-5 dealer-adoption
> telemetry records the right build.

> ### ⚠ +64 IS SUPERSEDED — DO NOT UPLOAD
>
> A built AAB consumes its versionCode whether or not it is uploaded. The +64 artifact is
> quarantined on disk as `versionCode64-68786e9-DO-NOT-UPLOAD-superseded.aab.bak`.
> **Next Android build ≥ +66.** Superseded and unuploaded: +64, +63, +62, +61, +60.

---

## 2.5.10+64 — solar LIVE + comparator wired + privacy manifest + #84 strip

| Field | Value |
|---|---|
| **Git SHA** | `68786e9e745b28ce45bb637cc76e267d6d07b736` (`68786e9`) — the build commit |
| **Merged to main** | `dad7329382e1d379cef5ebeeb1213f45b85d031f` (`dad7329`, `--no-ff`), **pushed to origin 2026-08-05** |
| **Branch at build time** | `feat/solar-live-comparator-privacy` (off `main` @ `7e04b00`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **64** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,237,290 bytes · built 2026-08-05 13:04 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | **277** — uploaded to App Store Connect 2026-08-05 |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch built** | `main` @ `dad7329` |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

> ### 🔑 JOIN KEY — all three identities of this build
>
> | Identity | Value |
> |---|---|
> | **Git build commit** | **`68786e9`** (`68786e9e745b28ce45bb637cc76e267d6d07b736`) |
> | **Git merge commit** | **`dad7329`** (`dad7329382e1d379cef5ebeeb1213f45b85d031f`) |
> | **Android versionCode** | **64** |
> | **iOS build number** | **277** |
>
> A tester who reports "build 277" is reporting on `68786e9` / `dad7329`, which is the same code as
> Android `versionCode 64`. The numbers differ only because `codemagic.yaml` overwrites pubspec's
> build number with its own `PROJECT_BUILD_NUMBER` counter.

**Contents.** *Solar:* `config/solar_scheduling.enabled = true` went LIVE 2026-08-05
(readback-confirmed) — it had **never existed** since solar was declared live 2026-07-28, so four
accounts had solar silently refused for eight days. Bench gate passed properly this time: a slot-9
row **FIRED at 11:27:09 against a computed sunset of 11:27**. `solarTimersLanded` +
`CfgPushOutcome.solarMismatch` wired into `pushCfgWithVerify` the same day — before it, solar rows
verified clean whether or not they landed. *Privacy:* #84 instrumentation stripped (it wrote
PII-bearing diagnostics to Firestore in release builds), `_safePreview` → `_safeShape`,
`debug_errors` retention at 30d, and `ios/Runner/PrivacyInfo.xcprivacy` declaring **12** data types
and wired into the Runner target's **Resources build phase**.

**Three findings from this build worth keeping:**
- `GET /settings/s.js?p=5` exposes the controller's **computed** sunrise/sunset — `/json/info` and
  `/json/state` have no solar field. Verifies the computation without firing.
- Coordinate writes do **not** recompute; a **reboot** does. Longitude-only is exactly 4 min/degree.
- WLED 0.15.1 stores the solar offset **SIGNED** (`-30` reads back `-30`, not `226`) — measured.

**Test suite at build time:** 1934 passed · 3 skipped · 1 failed (`cloud_ai_processor_normalize` —
pre-existing stale P1-8). **`flutter analyze lib/` WHOLE: 0 errors, 0 warnings** (368 pre-existing
info). Whole-lib was used deliberately: the `CfgPushOutcome` addition broke an exhaustive switch in
`sunrise_off_service.dart` that a file-scoped analyze had missed.

> ### ⚠ HARDWARE DEBT — now owed on +60, +61, +62, +63 AND +64
>
> - **Token refresh 4.2** — undischarged since +60.
> - **Commissioning a-d (P0-5/P0-6/P0-7)** — blocked by rig pairing state; carries to the next
>   genuine install.
> - **P1-50 step 6** — undo/erase confirmed in the RUNNING editor on a handset. Only the wire
>   equivalent is proven.
> - **`PrivacyInfo.xcprivacy` in the built IPA — still unconfirmed.** See the note below; the
>   successful upload does NOT establish it. Low effort to close, low risk if it slipped.

> ### ⚠ WHAT THE SUCCESSFUL UPLOAD DOES AND DOES NOT PROVE
>
> Build 277 uploaded to App Store Connect cleanly. It is tempting to read that as confirmation that
> `PrivacyInfo.xcprivacy` shipped in the IPA. **It does not**, and this project's own history is the
> counter-example: the file was created **today**, in `68786e9` — yet **2.5.6 went live and 2.5.7+43
> uploaded successfully with no app-level privacy manifest at all.** If a missing manifest failed
> upload validation, those uploads could not have happened.
>
> More precisely, upload validation checks **required-reason API declarations**
> (`NSPrivacyAccessedAPITypes`, e.g. ITMS-91053) — and those can be satisfied entirely by the
> bundled plugins' own manifests (`shared_preferences_foundation` ships one). The part this build
> actually adds — **`NSPrivacyCollectedDataTypes`, the 12 first-party data types** — is **not
> validated at upload at all**. It feeds the privacy report, while the App Privacy "nutrition label"
> comes from the ASC questionnaire, filled in by hand.
>
> **To actually close this**, do one of:
> 1. In App Store Connect, generate the **privacy report** for build 277 and confirm the 12
>    first-party data types appear; or
> 2. Download the Codemagic IPA artifact, unzip, and confirm
>    `Payload/Runner.app/PrivacyInfo.xcprivacy` exists.
>
> Either takes a couple of minutes and turns a structural argument into an observation.
>
> ### ⚠ Same join-key caveat — the iOS build number will NOT be 64
>
> `codemagic.yaml` overwrites pubspec's build number with
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`. **Match on `68786e9` / `dad7329`.**

---

## 2.5.10+63 — frozen-segment fix (seg.frz cleared on every segment write)

| Field | Value |
|---|---|
| **Git SHA** | `a3468058d3eab379095786d48084cd09607b2f20` (`a346805`) — the build commit |
| **Merged to main** | `d0c4753aa0c49dbaf7708dea8ab513b55b577f31` (`d0c4753`, `--no-ff`), **pushed to origin 2026-08-05** |
| **Branch at build time** | `fix/frozen-segment-clear` (off `main` @ `8326c47`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **63** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,239,711 bytes · built 2026-08-05 09:55 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (2026-08-05 09:55) — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch to build** | **`main` tip.** Commits after the merge `d0c4753` are docs-only, so `lib/ android/ ios/ pubspec.yaml codemagic.yaml test/` are byte-identical to the build commit. Stable identifiers are **`a346805`** (build) and **`d0c4753`** (merge) |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**Contents:** `normalizeWledPayload` clears `seg.frz` on any seg entry without an `i` key — one
chokepoint covering both transports and ~66 `applyJson` call sites. New pure
`ensurePsaveClearsFreeze` synthesizes `{id, frz:false}` for seg-LESS psaves, so the
schedule-fired ON-presets (1/3/4/5) cannot be poisoned. Participation lookup wrapped `try/catch`
with a segment-0 fallback (`savePreset` had no I/O of its own before this).

**Why:** a per-pixel write sets `seg.frz = true` on WLED 0.15.1; a frozen segment does not run its
effect, so every segment-level colour/effect write was stored, answered 200, read back correctly —
and never reached the LEDs. Found by **wire replay** after three source-reading passes each produced
a wrong hypothesis; every Dart layer was correct and the defect was one WLED field never sent.
The `psave` half is the durable one: a preset saved while frozen re-freezes on every load and cannot
render its own colours, and schedule sync always-psaves from live state.

**Fleet exposure at time of fix: ZERO** — no account holds a single `pixelMap` document (all 24 user
docs scanned).

**Test suite at build time:** 1893 passed · 3 skipped · 1 failed (`cloud_ai_processor_normalize` —
pre-existing stale P1-8 assertion). 1878 baseline + 15 new = 1893, so no test was lost. Analyze on
all changed files: **0 errors, 0 warnings** (28 pre-existing info).

**Hardware verification: 5 of 6 on 192.168.1.150.** Freeze → fixed segment write clears and renders
→ per-pixel still paints (ordering `base(frz:false) → per-pixel` verified, not assumed) → psave
while frozen stores `[False, False]` (pre-fix `[True, False]`) → loading it does not re-freeze.
Rig restored byte-equal.

> ### ⚠ HARDWARE DEBT CARRIED FORWARD — now owed on +60, +61, +62 AND +63
>
> - **Token refresh 4.2** — undischarged since +60.
> - **Commissioning a-d (P0-5 / P0-6 / P0-7)** — **blocked by rig pairing state**, not by time.
>   `bridge_discovery_service.dart:90` filters `status == 'unpaired'`, so the already-paired bench
>   rig never appears and the wizard cannot reach the roofline step. No supported app-side unpair
>   exists (`/api/reset` over LAN or a re-flash). Carries to the next genuine install.
> - **NEW: P1-50 step 6** — undo/erase confirmed in the RUNNING editor on a handset. Only the wire
>   equivalent is proven. **P1-50 stays OPEN until this is done.**
>
> ### ⚠ Same join-key caveat — the iOS build number will NOT be 63
>
> `codemagic.yaml` overwrites pubspec's build number with
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`. Only the version *name* survives from the repo.
> **Match on `a346805` / `d0c4753`.**

> ### ⛔ THIS AAB IS SUPERSEDED — DO NOT UPLOAD
>
> The +63 artifact above was built **before** the #84 instrumentation was stripped, so it still
> contains `captureBug84`, which performs a **Firestore write to `users/{uid}/debug_errors`
> carrying `errorMessage` and `stackTrace` in release builds**. That is a data-collection path that
> must not go to review undeclared.
>
> The strip landed after this build (see the commit following `d0c4753`). **`main` no longer matches
> this AAB.** A fresh build is required before any upload, and it must take **versionCode ≥ 64** —
> 63 is consumed by the artifact on disk.
>
> The Git SHA / versionCode rows above remain accurate for *this artifact*; they are kept so a
> crash report against it can still be resolved.

---

## 2.5.10+62 — P0-9a tri-state lease-ledger gate

| Field | Value |
|---|---|
| **Git SHA** | `306f3d233097a181c5866e69979ef4410dc6a15b` (`306f3d2`) — the build commit |
| **Merged to main** | `43e85c8457e3ebb8173f769ae986bc617cb8170c` (`43e85c8`, `--no-ff`), **pushed to origin 2026-08-03** |
| **Branch at build time** | `fix/p0-9a-lease-tristate-gate` (off `main` @ `c0ebe36`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **62** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,239,152 bytes · built 2026-08-03 13:33 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (2026-08-03 13:33) — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch to build** | **`main` tip** — just pick the branch; Codemagic defaults to its tip. Every commit after the merge `43e85c8` is **docs-only** (`docs/`, `audit/`), so `lib/ android/ ios/ pubspec.yaml codemagic.yaml test/` are byte-identical to the build commit and the IPA is the same from any of them. Deliberately NOT pinned to a SHA here — naming a tip in a file that lives on the tip just chases itself. The stable identifiers are **Git SHA `306f3d2`** (build commit) and **`43e85c8`** (merge); record the actual built SHA below when Codemagic reports it |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**Contents:** P0-9 part (a) only — the tri-state lease-ledger gate.
`activeLeaseTimers()` returns a sealed `LeaseLedgerLoading | LeaseLedgerEmpty | LeaseLedgerReady`
instead of a bare list, so "no leases" and "ledger not loaded yet" stop sharing one representation.
`_initialized` is consulted in production for the first time (it existed, was set correctly, and was
read only by a `@visibleForTesting` getter). `calendarLeaseActiveTimersProvider` reads the flag
*stream* rather than the sync adapter, which collapsed `AsyncLoading → false` and licensed the same
clobber one level up. `syncAll` refuses the cfg write on `Loading`
(`ScheduleSyncResult.deferredLeaseLedger`, neutral UI, bounded 3-attempt backoff retry).

**Verification:** suite 1878 pass / 3 skipped / 1 fail (pre-existing stale
`cloud_ai_processor_normalize`, P1-8). `flutter analyze` on all changed files: 0 errors, 0 new
warnings. **Bench end-to-end on 192.168.1.150** (real `syncAll`, real `WledService`): cold-ledger
sync wiped a live lease and returned `success=true` (case 0), gate leaves the table byte-identical
with no POST (case 1), warm sync arms schedule + lease together (case 2). Rig restored to baseline
and verified. Full report: `audit/LEASE_TRISTATE.md`.

**Ships into, but does NOT change:** solar is still OFF fleetwide —
`config/solar_scheduling` has never existed in either Firebase project, and this build does not
create it. **Still open:** P0-9b (ledger durability — reinstall / second device) and P0-9c
(`_kLeaseStorageKey` not uid-namespaced).

> **Note on numbering.** This was requested as "+61". versionCode **61 was already consumed** by the
> build below — merged (`c5c7baf`), pushed, ledgered, and its AAB preserved on disk as
> `versionCode61-816aa1b-solar-and-clobber-guard.aab.bak`. Re-cutting +61 would have made the pushed
> +61 row describe contents it does not have, so this is **+62**. The solar fix and all-stub clobber
> guard listed in the +62 request shipped in +61; +62 adds only the lease gate on top.

---

## 2.5.10+61 — solar failure made legible + all-stub clobber guard

| Field | Value |
|---|---|
| **Git SHA** | `816aa1b538e947ad8d801bfe1d26f2349ff019db` (`816aa1b`) — the build commit |
| **Merged to main** | `c5c7baf1f280ce07d22eee4114d3dfce1ec5e911` (`c5c7baf`, `--no-ff`), **pushed to origin 2026-08-03** |
| **Branch at build time** | `fix/solar-legible-and-clobber-guard` (off `main` @ `624d347`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **61** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,237,215 bytes · built 2026-08-03 12:18 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (2026-08-03 12:17) — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch built** | `main` @ `c5c7baf` |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**Contents:** `presetErrors` text now renders at both display sites (was a bare count, discarding
the composed remedy); abort message rewritten without the `internal:` prefix; five UI surfaces
gated on the solar flag (editor, autopilot baseline, AI prompt schema, commercial events,
neighborhood sync); `_offTrigger` default flipped off solar; `shouldSkipClobberingWrite` +
`countRefusal` at five refusal points; both display sites reordered so warnings survive the
`!success` branch. Audit trail: `audit/SOLAR_FIX.md`, `audit/ALL_STUB_GUARD.md`,
`audit/ALL_STUB_CLOBBER.md`, `audit/ELLIE_SUNSET.md`.

**Test suite at build time:** 1867 passed · 3 skipped (hardware-gated) · 1 failed
(`cloud_ai_processor_normalize` — pre-existing stale P1-8 assertion, pins behavior deliberately
removed by `b6ca2f1`; count matched the expected baseline exactly, so no stash proof was needed).
Analyze on all changed files: **0 errors, 0 warnings** (15 pre-existing info-level lints).

**Known-open at ship:** solar still does not work — this build makes the failure legible and stops
it spreading; `config/solar_scheduling` is deliberately NOT created. The flag flip is gated on a
solar comparator that does not exist (`isRealEnabledTimer` excludes `hour == 255`). **P0-9** open —
lease timers occupy general slots 0-7, protected only by a same-write merge from a device-local
SharedPreferences ledger. `firestore.rules` deliberately untouched (controller_ips mid-soak).

> ### ⚠ Same join-key caveat as +60 — the iOS build number will NOT be 61
>
> `codemagic.yaml` still overwrites pubspec's build number:
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`, then `sed`s it into pubspec. Only the version
> *name* (`2.5.10`) survives from the repo. **Android `versionCode 61` and the iOS build number
> identify the same code only through `816aa1b` / `c5c7baf`.** Match on the SHA.

---

## 2.5.10+60 — commissioning silent-failure closeout

| Field | Value |
|---|---|
| **Git SHA** | `d92262fbf86cc5aafbd95fd76e5e339d8783b8cf` (`d92262f`) — the build commit |
| **Merged to main** | `4bd2227f339807fb08626a7f5ba6319669498a4a` (`4bd2227`, `--no-ff`), **pushed to origin 2026-07-31** |
| **Branch at build time** | `fix/commissioning-silent-failures` (off `main` @ `c20ed83`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **60** — verified from the merged manifest (`build/app/intermediates/bundle_manifest/release/processApplicationManifestReleaseForBundle/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,227,800 bytes · built 2026-07-31 11:29 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), started **manually** — `codemagic.yaml` still has no `triggering:` block |
| **iOS branch built** | `main` @ `4bd2227` |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

> ### ⚠ The iOS build number will NOT be 60 — the SHA is the join key
>
> `codemagic.yaml` overwrites pubspec's build number before building:
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`, then `sed`s it into pubspec. Only the
> version *name* (`2.5.10`) survives from the repo. `PROJECT_BUILD_NUMBER` is **Codemagic's
> own counter**, so iOS will ship as `2.5.10+<codemagic counter>` — some number that is not
> 60, and not predictable from here.
>
> **Android `versionCode 60` and the iOS build number identify the same code only through
> `d92262f` / `4bd2227`.** When matching a TestFlight build or a crash report to this change,
> match on the SHA.

**What shipped:** three fixes on the commissioning surface, all the same class — reporting
success for work that did not happen.

- **P0-7** — the roofline pixel-map save could fail silently and the wizard advanced anyway.
  Now a blocking retry gate; the cause is logged and shown; an empty capture still passes
  through. No offline-queue option (it would relocate the failure, not fix it).
- **P0-6** — `migrateInstallerControllersToCustomer` swallowed every failure, so a denied
  migration handed over a customer account with no controllers. Now throws, with a Retry/Stop
  dialog matching `_restoreInstallerAuthWithRetry`; Stop reports the install as FAILED.
- **Token refresh + anon-fallback telemetry** — `_restoreInstallerAuth` re-mints the staff
  custom token from the cached PIN instead of dropping to `signInAnonymously()`. **This build
  is the D4 dependency**: it must be adopted, and the `installer_anon_fallback` count must
  reach zero, before the resource rules tighten.

**firestore.rules:** no new changes in this build. It carries the **already-deployed** P0-5
fix (ruleset `ec8d918f-c279-4925-b8b2-168e96638586`, live `2026-07-31T15:10:10Z`), committed
here so the repo matches production. D4 is not in this build.

**Test suite at build time:** 1857 passed · 3 skipped · 1 failed
(`cloud_ai_processor_normalize` — pre-existing, P1-8, proven by stash). `flutter analyze`
clean on all six changed files.

**Rules verification at build time:** 16/16 against the **live** ruleset via the Rules `:test`
API (including cross-dealer DENY), plus a 31-path deployed-vs-live regression with 0
behavioral differences.

**Hardware verification at upload: NONE.** All three owed debts — token refresh §4.2,
commissioning a–d, and Part B (Design Studio slices 0–5) — are consolidated into one runnable
session in `audit/HARDWARE_VERIFICATION_+60.md`. Nothing in this build has been exercised on
the rig. The P0-6 Retry/Stop dialog is additionally not widget-testable (no auth-mocking
dependency); its mechanism is unit-pinned, the dialog is not.

**Known-open at ship:** P3-60 (`kStaffAuthTelemetryAppVersion` is hand-bumped — verified
`2.5.10+60` for this build, but it will drift), P3-61 (aborting after account creation is
unrecoverable in-app), P3-62 (stale line-number cross-references), F-5a/F-5b (account
deletion — unrelated to P0-7 despite the label collision, still open).

---

## 2.5.10+59 — ON-presets self-heal master power

| Field | Value |
|---|---|
| **Git SHA** | `d2e4d5b043b58a3e5c32e82697a36d015effecab` (`d2e4d5b`) |
| **Branch at build time** | `fix/preset-master-power-heal` (off `main` @ `393af46`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **59** — verified from the merged manifest |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,206,827 bytes |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` |
| **Android track** | Play **Closed testing** — **UPLOADED 2026-07-30**, confirmed Closed (not Internal; Internal would not advance the 12-tester production-access streak) |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), started **manually** (no `triggering:` block) |
| **iOS branch built** | `PENDING` — build from `main` (merged as `9d4fa99`) |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |
| **Merged to main** | `9d4fa99` (`--no-ff`), pushed 2026-07-30 — **merged ahead of the device smoke test at owner's direction**; see that commit's body |

**What shipped:** ON presets 1/3/4/5 now assert root master power, so a fired
ON-timer turns the lights on instead of loading a design into a dark master.
Fixes the name-only skip predicate that made `9158c00` (2.5.10+50) inert on
every controller commissioned before it, and adds an on-connect healer so
existing controllers repair without the customer editing a schedule.

**Hardware verification (bench rig 192.168.1.150, WLED 0.15.1, vid 2507300):**

- Pre-merge: end-to-end timer fire — `ps 2→1` **and** `state.on == true`. Bench
  harness 18/28 → 27/28.
- **Post-merge, with the SHIPPED build on a real device** (evidence commits
  `73a3745`, `adb256a`, `c09d086`): all four ON presets deliberately broken and
  confirmed `root_on=ABSENT` → **first connect healed all four** to
  200/51/102/153 → **second connect: no flash, zero writes**, presets
  byte-identical to the healthy baseline and `state.on` still false. The
  psave-storm hard stop is **cleared**.
- Four presets were broken rather than one on purpose: a single broken preset
  exercises the predicate but skips the settle / retry / final-readback path,
  which exists because four back-to-back psaves produced a false green during
  development.

**Smoke coverage at upload: partial.** Connect + heal + idempotency (checklist
steps 1-4) are verified. **Steps 5-13 are NOT** — schedule create/edit/delete,
boundary firing, calendar-lease interaction, sunrise-off, brightness presets.
The lease interaction is the highest-risk gap: schedule-vs-lease clobbering has
shipped before and this change touches the same preset-write path.

**Test suite at build time:** 1834 passed · 3 skipped (hardware-gated) · 1
failed (`cloud_ai_processor_normalize` — pre-existing, proven by re-running with
the change stashed).

**Known-open at ship:** `P3-56` (ON-preset definitions in two places), bench
`layout drift` baseline artefact (needs `probe --update`).

---

## Rows before this one

This ledger starts at **2.5.10+59**. Earlier builds predate it; their identity
must be reconstructed from `git log` (`chore(release):` and `chore: bump to`
commits) and the Play Console / App Store Connect upload history. Reconstructing
them retroactively is not recommended — record forward, do not guess backward.
