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
| **Android track** | Play **Closed testing** (not Internal — Internal does not advance the 12-tester production-access streak) |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), started **manually** (no `triggering:` block) |
| **iOS branch built** | `PENDING` — per the release sequence, build iOS from `main` after the branch merges |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**What shipped:** ON presets 1/3/4/5 now assert root master power, so a fired
ON-timer turns the lights on instead of loading a design into a dark master.
Fixes the name-only skip predicate that made `9158c00` (2.5.10+50) inert on
every controller commissioned before it, and adds an on-connect healer so
existing controllers repair without the customer editing a schedule.

**Hardware verification (bench rig 192.168.1.150, WLED 0.15.1, vid 2507300):**
end-to-end timer fire confirmed — `ps 2→1` **and** `state.on == true`. Bench
harness 18/28 → 27/28.

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
