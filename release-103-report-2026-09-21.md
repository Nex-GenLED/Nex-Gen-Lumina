# Release 2.5.10+103 — three-way convergence — 2026-09-21

**Build point:** `64fa5af` (`chore(release): bump to 2.5.10+103`), tag **`build-103`** (annotated, obj `a369953`).
**Branch:** `release/store-submission-103`, worktree `C:/Flutter Projects/lumina-b103`.
**Base:** `origin/release/store-submission-consolidated` @ `73ae375` — fetched and confirmed from the
server immediately before branching, not assumed.

| | |
|---|---|
| Merge | 3 branches, `--no-ff`, **0 conflicts** |
| Tests | **3253 pass / 19 skip / 0 fail** — exactly 3175 + 6 + 28 + 44 |
| Analyze | **0 errors / 12 warnings / 370 infos (382)** — issue set identical to baseline |
| iOS CI | Codemagic **iOS Release: `success`**, 18 min 17 s — pod resolution therefore succeeded; the log line itself could not be read (§6) |
| Android | AAB built, versionCode **103**, same signer as +102, **not uploaded** |
| `main` | untouched, still `699a498` |

---

## 1. Ground truth (Step 1)

`git fetch origin --prune --tags`, then tips read from the server with `git ls-remote`:

| Ref | Tip |
|---|---|
| `origin/release/store-submission-consolidated` | `73ae375` (unchanged since this morning) |
| `origin/dev/post-submission` | `73ae375` |
| `origin/main` | `699a498` |

All three fix branches existed, local tip == origin tip, each cut from `73ae375`:

| Branch | Tip | Commits beyond base |
|---|---|---|
| `fix/firestore-transaction-crash` | `46a1458` | `c1c2cca`, `46a1458` |
| `fix/gameday-celebration-team-colors` | `7963e0c` | `60282a3`, `878a712`, `7963e0c` (evidence — landed) |
| `fix/save-to-my-designs-and-favorites` | `aaa4ac1` | `dc20d79`, `adacf15`, `ff5f1b4`, `54a7baf`, `aaa4ac1` |

**One correction to the brief.** `aaa4ac1` is not a fix commit with a report on top — it *is* the
report commit, and the branch tip. The fix is the four commits beneath it. Nothing was missing: that
session's worktree was clean and idle, and local == origin. Noted only so the ledger row is right.

Pre-merge checks: the three branches touch **no file in common** (8 + 17 + 22 = 47 paths, no
overlap), and `build-103` / `release/store-submission-103` did not exist locally or on origin.

## 2. Integration (Step 2)

Fresh worktree, branch created off the confirmed tip, upstream tracking unset. Three `--no-ff`
merges, one at a time, each checked for unmerged paths before the next:

| Merge commit | Parents | Brings in |
|---|---|---|
| `bb23737` | `73ae375` + `46a1458` | Firestore crash fix: FlutterFire bump + two transaction serializations |
| `6620c98` | `bb23737` + `7963e0c` | Game Day celebration team colours + evidence |
| `c2b013a` | `6620c98` + `aaa4ac1` | Save → My Designs, single favorites doc shape |

**No conflicts. Nothing was resolved by hand, because nothing needed resolving.** Merged tree =
47 changed paths vs base, as predicted.

The risk I was actually watching was not textual but *semantic*: two branches written against
`cloud_firestore 6.1.1` meeting a tree now on 6.7.1 — which exports a `Type` enum that shadows
`dart:core`'s, made `WriteBatch.update` generic, and added a `getToken` parameter. New code or new
test fakes from the other two branches could have tripped on any of those. **They did not** — the
analyzer came back with zero new issues (§3).

Before the full suite I also confirmed the save branch's new
`test/hardware/save_to_my_designs_live_test.dart` cannot touch the bench controller in a normal
run: it is gated on `--dart-define=RUN_HW`, and its `setUpAll` returns before any I/O without it.
(It matters because `@Tags('hardware')` is inert in this repo.) Those are the +5 skips.

## 3. Verification on the merged tree (Step 3)

Run on `c2b013a`, full and unfiltered. Logs: `C:/Flutter Projects/lumina-b103-artifacts/gate/`.

| | Baseline `73ae375` | Merged `c2b013a` | Expected | |
|---|---|---|---|---|
| passed | 3175 | **3253** | 3175 + 6 + 28 + 44 = 3253 | exact |
| skipped | 14 | **19** | 14 + 5 `RUN_HW` hardware tests | exact |
| failed | 0 | **0** | 0 | |
| analyze | 0 / 12 / 370 | **0 / 12 / 370** | identical | exact |

The +6 / +28 / +44 are each branch's own reported deltas (crash: 3181; Game Day: 3203; save: 3219),
so the merged total is the clean sum with no test lost or double-counted.

Analyzer: counts can match while one issue is fixed and another introduced, so I diffed the issue
**sets** against the recorded baseline with line:column stripped. Only-in-merged: **0**.
Only-in-baseline: **0**. `flutter analyze` exits 1 on both — that is the 382 pre-existing issues,
not a regression.

## 4. Version bump (Step 4)

Two one-line edits, the same shape as `a988854` (+102):

```
pubspec.yaml          version: 2.5.10+102            -> 2.5.10+103
lib/app_version.dart  kAppVersion = '2.5.10+102'     -> '2.5.10+103'
```

`kStaffAuthTelemetryAppVersion` is still `= kAppVersion` (`staff_auth_telemetry.dart:58`), so the
telemetry stamp follows with no third edit. No other `2.5.10+10x` literal exists in `lib/`,
`android/` or `ios/`.

**Gate re-run on the bumped tree before committing:** 3253 / 19 / 0; analyze 0 / 12 / 370; issue-set
delta vs the merged tree +0 / −0. Then committed by explicit pathspec
(`git commit -F … -- pubspec.yaml lib/app_version.dart`) as **`64fa5af`**. The bump commit is the
build point (ledger convention 1).

## 5. Tag and push (Step 5)

| Action | Result |
|---|---|
| `build-103` annotated tag on `64fa5af` | obj `a369953` |
| push `release/store-submission-103` | `[new branch]` → `64fa5af` |
| push `build-103` | `[new tag]`, **2026-09-21T16:48:10Z** — this is the CI trigger (`codemagic.yaml` is tag-only, `build-*`) |
| `origin/release/store-submission-consolidated` | **fast-forward** `73ae375..64fa5af` (14 commits) |
| `origin/dev/post-submission` | **fast-forward** `73ae375..64fa5af` (14 commits) |
| `origin/main` | **not touched** — still `699a498` |

Both protected-branch updates were plain pushes of the SHA — no force, no `+` refspec — after
re-reading each server tip and checking it was an ancestor of `64fa5af`. Git would have refused a
non-fast-forward; neither was. All five refs re-verified from the server afterwards.

## 6. iOS CI and the pod step (Step 6)

**Result: `completed` / `success`.**

| | |
|---|---|
| Check-run | `iOS Release`, app `codemagic-ci-cd`, on `64fa5af` |
| Started | 2026-09-21T16:48:11Z — **one second** after the tag push |
| Completed | 2026-09-21T17:06:28Z — **18 min 17 s** (build-102 took 17 min) |
| Conclusion | **success** |
| Build page | https://codemagic.io/app/696ff9da8b1bbc3a976106be/build/6ab15fcb688764aa17db2f6e |

Read via the public GitHub check-runs API (no token needed), polled to a terminal state and then
re-queried independently.

**What this proves about the pod step, and what it does not.** The workflow order is
*Test and analyze (build gate) → Set build number → Install CocoaPods → Build IPA → Dump signed
entitlements*. `Build IPA` cannot run without a resolved `Pods/` project, and CI deletes
`Pods`, `Podfile.lock` and `.symlinks` and runs `pod install --repo-update` from scratch every build.
So a `success` conclusion means **the FlutterFire 2026-07-14 set resolved, compiled and archived on
iOS** — including the new `cloud_firestore 6.7.1` native code that carries the crash fix. The one
genuinely unverified part of this release is now verified in the sense that matters.

**What I could not do:** read the log and see the literal `Firebase 12.15.0` /
`FirebaseFirestore 12.15.0` lines. There is no Codemagic API token on this machine (checked), the
build page is a login-walled app shell, and the check-run payload carries no step output. The
version is what `firebase_core 4.12.1`'s `firebase_sdk_version.rb` pins, and the Podfile overrides
nothing, so 12.15.0 is the expected resolution — but **that specific line is inferred, not
observed.** If you want it nailed down, it is a 10-second look at the *Install CocoaPods* step on
the build page above. The TestFlight build number is Codemagic's own counter and is likewise only
visible to you.

CI also ran its own `Test and analyze` gate on macOS and passed it, which independently corroborates
§3 on a second platform.

## 7. Android bundle (Step 7)

Built at `64fa5af` — HEAD was the tagged bump commit, worktree `git status` empty.

| | |
|---|---|
| Command | `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info/android` |
| Result | exit 0, Gradle `bundleRelease` 445.7 s |
| Artifact | `C:/Flutter Projects/lumina-b103-artifacts/lumina-2.5.10+103-64fa5af.aab` |
| Size | 69,182,018 B |
| sha256 | `027e7dc9cc38f74a40b5515ef454384deaeda27f5228b2017f4dd9a24d5d84da` |
| versionCode | **103** — read from both merged manifests **and** from the bundle's own `base/manifest/AndroidManifest.xml` |
| versionName / package / targetSdk | `2.5.10` / `com.nexgenled.lumina` / 36 |
| Signature | `jar verified` |
| Signer | `CN=Tyler Honeycutt, OU=Nex-Gen LED LLC, O=Nex-Gen LED LLC, L=Blue Springs, ST=MO, C=US` |
| Signer SHA1 | `8E:4A:35:82:8B:32:BA:52:B9:93:25:25:B8:5E:B4:D4:FD:0A:57:DA` |
| Same signer as +102? | **Yes** — SHA-256 cert fingerprint `96:6A:36:4E:…:C8:6D:DF` read from *both* AABs and identical |
| Symbols | `debug-info-android/` — arm, arm64, x64 `.symbols` (keep for crash symbolication) |
| Uploaded | **No** |

Signing inputs (convention 3): `bash scripts/signing_inputs.sh install` — all three reported
`IDENTICAL to the main repo` before the build, and again on a `verify` after it. **Signing inputs:
GUARD OK** (the Gradle guard has no skip flag, so a release build that completed passed it;
Flutter swallows Gradle's stdout, so its three lines are not in `android_build.log` — the pre/post
`verify` output stands in). All three copies were then **removed from this worktree**; the main
repo's originals are untouched (112 / 2776 / 712 B). No stale AAB existed to quarantine (fresh
worktree). `.android-versioncode-state` written by hand to `103` (build.sh was bypassed; file is
git-ignored).

**versionCode 103 is now consumed**, uploaded or not. Next Android build ≥ `+104`.

## 8. No other production changes (Step 8)

- **No Firestore write occurred.** Nothing in this task ran against the production project: no
  `firebase deploy`, no `scripts/*.js`, no admin SDK, no rules change. Every test ran on in-memory
  `fake_cloud_firestore`; the 5 live-hardware tests were skipped (no `RUN_HW`), so nothing touched
  the bench controller at `.150` either. The only outward actions were the git pushes in §5.
- **The shared checkout was not touched.** `C:/Flutter Projects/Lumina V 1.6` is still detached at
  `df6063b` with the same 34-line status as at session start (1 modified: `docs/BUGS_AND_DEBT.md`;
  33 untracked). A sweep for files modified in the last 4 hours found **nothing in any source directory** (`lib`, `test`, `docs`, `scripts`, `functions`, `android/app`, `ios/Runner`, `pubspec.*`) and no build output. It did find git-ignored Gradle bookkeeping under `android/.gradle/` stamped **09:41 local** — before either Gradle run I made today (10:22 in the crash worktree, 11:56 here) and before this task began, so not from this task; most plausibly the IDE's Gradle sync on the open workspace, or another session. It was read from twice (`signing_inputs.sh` copies
  *from* it), never written to. Its `.git` directory is shared by every worktree, so new refs and
  objects necessarily landed there — that is git's storage, not the working tree.
- No other worktree was modified. The two other sessions' fix worktrees were only inspected
  (`git status`), and were clean.

## 9. Still open

1. **`BUILD_LEDGER.md` has no row for +103** — nor for +100, +101, +102. The rows need TestFlight
   numbers only you can read. Convention 1 puts the ledger commit *after* the tag, so adding it now
   is clean.
2. **One repository-hygiene item carried over from this morning is unchanged by this release.** It
   is deliberately not described here because this repository is public; the details are in the
   maintainer's private notes (2026-09-21). It does not affect the contents of this build.
3. The Firestore crash fix cannot be confirmed *in the field* from here: a native `SIGSEGV` never
   reaches `debug_errors`. Watch App Store Connect / Xcode Organizer crash counts for +103 vs prior.
4. This report is committed on `docs/release-103-report-2026-09-21` (one commit on top of the
   build point `64fa5af`, outside the `build-103` tag), matching the +101 and +102 report branches.
