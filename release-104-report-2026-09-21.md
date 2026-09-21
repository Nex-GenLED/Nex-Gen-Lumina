# Release 2.5.10+104 — geofence favorites lookup — 2026-09-21

**Build point:** `3859df7` (`chore(release): bump to 2.5.10+104`), tag **`build-104`** (annotated, obj `6728843`).
**Branch:** `release/store-submission-104`, worktree `C:/Flutter Projects/lumina-b104`.
**Base:** `origin/release/store-submission-consolidated` @ `64fa5af` (= `build-103`) — fetched and
confirmed from the server immediately before branching, not assumed.

| | |
|---|---|
| Merge | 1 branch (`fix/geofence-favorites-lookup`), `--no-ff`, **0 conflicts** |
| Held branches | **None of the three is in this build** — verified by ancestry and by patch content (§2) |
| Tests | **3270 pass / 19 skip / 0 fail** — exactly 3253 + 17 |
| Analyze | **0 errors / 12 warnings / 370 infos (382)** — issue set identical to build-103 |
| iOS CI | Codemagic **iOS Release: `success`**, 16 min 7 s (§7) |
| Android | AAB built, versionCode **104**, same signer as +103, **not uploaded** |
| `main` | untouched, still `699a498` |

---

## 1. Ground truth (Step 1)

`git fetch origin --prune --tags`, then tips read from the server with `git ls-remote`:

| Ref | Tip |
|---|---|
| `origin/release/store-submission-consolidated` | `64fa5af` — equals the `build-103` tag, as expected |
| `origin/dev/post-submission` | `64fa5af` |
| `origin/main` | `699a498` |

`fix/geofence-favorites-lookup` exists at **`89065d7`**, as expected. It is **one commit** beyond
consolidated; its parent is `aaa4ac1`, the tip of the favorites fix that shipped in +103, so it brings
nothing else with it. Its session's worktree was clean and idle. The branch had never been pushed —
this release is what publishes it — so its 307 added lines and its commit message were scanned first
for credentials, keys, PINs, e-mail addresses, user ids (full and truncated), MACs, coordinates and
concrete Firestore paths: **nothing.** It cites production counts in aggregate only.

`build-104` and `release/store-submission-104` did not exist locally or on origin.

## 2. The three held branches are NOT in this build

Held pending bench verification on the home network, and not cleared to ship:

| Branch | Tip | Commits not in consolidated |
|---|---|---|
| `fix/gameday-celebration-picker-wiring` | `3e0e904` | 3 |
| `fix/brightness-restore-consistency` | `7984d5e` | 3 |
| `feat/static-per-pixel-favorites` | `5d2b1b4` | 4 |

"Not an ancestor" is a weaker claim than it sounds — a cherry-pick slips straight past it — so this
was checked four ways:

1. **Ancestry, before the merge:** none of the three is merged into `origin/…-consolidated`.
2. **Patch content, before the merge:** `git cherry` marks all ten of their commits `+`, i.e. no
   equivalent patch exists in consolidated under a different hash either.
3. **The carrier:** none of those ten commits is reachable from `fix/geofence-favorites-lookup`, and
   the geofence branch shares no file with any of the three.
4. **After the merge, on the release tree:** commits from each held branch reachable from `HEAD`:
   **0 / 0 / 0**.

The bump commit and the tag message both name the three as deliberately excluded, so the exclusion is
recorded in the history itself, not only in this report.

## 3. Integration (Step 2)

Fresh worktree, branch created off the confirmed tip, upstream tracking unset. One `--no-ff` merge:

| Merge commit | Parents | Brings in |
|---|---|---|
| `30a03fe` | `64fa5af` + `89065d7` | Welcome Home finds favorites by `pattern_name` |

**No conflicts; nothing was resolved by hand.** The merged tree differs from `64fa5af` in exactly the
five files the branch touches:

```
M  lib/features/favorites/favorites_providers.dart
A  lib/features/geofence/geofence_favorite_lookup.dart
M  lib/features/geofence/geofence_monitor.dart
M  lib/features/geofence/geofence_setup_screen.dart
A  test/features/geofence/geofence_favorite_lookup_test.dart
```

What it fixes, in one paragraph: the geofence picker and the geofence trigger both looked favorites
up by a camelCase `name` field. The live security rule has rejected that document shape on every
write, so no stored favorite has ever had it — the picker listed no favorites, the trigger matched
none, and every arrival fell through to the keyword fallback. Both halves now live in one file and key
on `pattern_name`, so the name the picker offers is by construction the name the trigger queries.
Built-in scenes remain selectable alongside favorites (the old code would have *replaced* them, handing
the dropdown a saved value that was not among its items — an assertion failure — for any account whose
saved action was a built-in, the moment that account had a favorite).

## 4. Verification on the merged tree (Step 3)

Run on `30a03fe`, full and unfiltered. Logs: `C:/Flutter Projects/lumina-b104-artifacts/gate/`.

| | build-103 `64fa5af` | Merged `30a03fe` | Expected | |
|---|---|---|---|---|
| passed | 3253 | **3270** | 3253 + 17 = 3270 | exact |
| skipped | 19 | **19** | unchanged | exact |
| failed | 0 | **0** | 0 | |
| analyze | 0 / 12 / 370 | **0 / 12 / 370** | identical | exact |

The 17 was counted rather than taken on trust: the new test file contains exactly 17 `test(` cases,
and the merge changes **no existing test file**, so +17 is the whole delta. The 19 skips are the
`RUN_HW`-gated hardware tests, unchanged — nothing in this run touched the bench controller.

Analyzer: counts can match while one issue is fixed and another introduced, so the issue **sets** were
diffed against the +103 build tree with line:column stripped. Only-in-104: **0**. Only-in-103: **0**.
(`flutter analyze` exits 1 on both: the 382 pre-existing issues, not a regression.)

## 5. Version bump (Step 4)

```
pubspec.yaml          version: 2.5.10+103            -> 2.5.10+104
lib/app_version.dart  kAppVersion = '2.5.10+103'     -> '2.5.10+104'
```

`kStaffAuthTelemetryAppVersion` is still `= kAppVersion` (`staff_auth_telemetry.dart:58`), so the
telemetry stamp follows with no third edit. No other `2.5.10+10x` literal exists in `lib/`,
`android/` or `ios/`.

**Gate re-run on the bumped tree before committing:** 3270 / 19 / 0; analyze 0 / 12 / 370; issue-set
delta vs the merged tree +0 / −0. Then committed by explicit pathspec
(`git commit -F … -- pubspec.yaml lib/app_version.dart`) as **`3859df7`**. The bump commit is the
build point (ledger convention 1).

## 6. Tag and push (Step 5)

| Action | Result |
|---|---|
| `build-104` annotated tag on `3859df7` | obj `6728843` |
| push `release/store-submission-104` | `[new branch]` → `3859df7` |
| push `build-104` | `[new tag]`, **2026-09-21T20:47:45Z** — the CI trigger (`codemagic.yaml` is tag-only, `build-*`) |
| `origin/release/store-submission-consolidated` | **fast-forward** `64fa5af..3859df7` (3 commits) |
| `origin/dev/post-submission` | **fast-forward** `64fa5af..3859df7` (3 commits) |
| `origin/main` | **not touched** — still `699a498` |

Both protected-branch updates were plain pushes of the SHA — no force, no `+` refspec — after
re-reading each server tip and checking it was an ancestor of `3859df7`. Git would have refused a
non-fast-forward; neither was. All five refs were re-verified from the server afterwards.

## 7. iOS CI (Step 6)

**Started: confirmed. Result: `completed` / `success`.**

| | |
|---|---|
| Check-run | `iOS Release`, app `codemagic-ci-cd`, on `3859df7` |
| Started | 2026-09-21T20:47:46Z — **one second** after the tag push |
| Completed | 2026-09-21T21:03:53Z — **16 min 7 s** (build-103: 18 min 17 s; build-102: 17 min) |
| Conclusion | **success** |
| Build page | https://codemagic.io/app/696ff9da8b1bbc3a976106be/build/6ab197f2688764aa17dbf46c |

Read via the public GitHub check-runs API (no token needed), polled to a terminal state and then
re-queried independently. The workflow runs its own `Test and analyze` gate on macOS before building,
so a `success` also corroborates §4 on a second platform. This is the second consecutive iOS build on
the FlutterFire 2026-07-14 set (`cloud_firestore 6.7.1`), so pod resolution is no longer an open
question.

What this cannot tell you: the step logs are behind a Codemagic login and there is no API token on
this machine, so the TestFlight build number — Codemagic's own counter, not the pubspec `+104` — is
only visible to you.

## 8. Android bundle (Step 7)

Built at `3859df7` — HEAD was the tagged bump commit, worktree `git status` empty.

| | |
|---|---|
| Command | `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info/android` |
| Result | exit 0, Gradle `bundleRelease` 395.7 s |
| Artifact | `C:/Flutter Projects/lumina-b104-artifacts/lumina-2.5.10+104-3859df7.aab` |
| Size | 69,186,629 B |
| sha256 | `7f903873b3a38d1aded30383f01f1905fc33b48af0e10cdc6d0e5d62924bd5ce` |
| versionCode | **104** — read from both merged manifests **and** from the bundle's own `base/manifest/AndroidManifest.xml` |
| versionName / package / targetSdk | `2.5.10` / `com.nexgenled.lumina` / 36 |
| Signature | `jar verified` |
| Signer | `CN=Tyler Honeycutt, OU=Nex-Gen LED LLC, O=Nex-Gen LED LLC, L=Blue Springs, ST=MO, C=US` |
| Signer SHA1 | `8E:4A:35:82:8B:32:BA:52:B9:93:25:25:B8:5E:B4:D4:FD:0A:57:DA` |
| Same signer as +103? | **Yes** — SHA-256 cert fingerprint read from *both* AABs and identical |
| Symbols | `debug-info-android/` — arm, arm64, x64 `.symbols` (keep for crash symbolication) |
| Uploaded | **No** |

Signing inputs (convention 3): `bash scripts/signing_inputs.sh install` — all three reported
`IDENTICAL to the main repo` before the build, and again on a `verify` after it. **Signing inputs:
GUARD OK.** All three copies were then **removed from this worktree**, leaving `git status` empty; the
main repo's originals are untouched (112 / 2776 / 712 B). No stale AAB existed to quarantine (fresh
worktree). `.android-versioncode-state` written by hand to `104` (build.sh was bypassed; the file is
git-ignored).

**versionCode 104 is now consumed**, uploaded or not. Next Android build ≥ `+105`.

## 9. No other production changes (Step 8)

- **No Firestore write occurred.** Nothing in this task ran against the production project: no
  `firebase deploy`, no `scripts/*.js`, no admin SDK, no rules change. Every test ran on in-memory
  `fake_cloud_firestore`; the hardware tests were skipped, so the bench controller was not touched
  either. The only outward actions were the git pushes in §6.
- **The shared checkout was not touched.** `C:/Flutter Projects/Lumina V 1.6` is still detached at
  `df6063b` with the same 34-line status (1 modified: `docs/BUGS_AND_DEBT.md`; 33 untracked). A sweep
  for files modified during this task's whole window found **none** — not in any source or config
  path, and not even in its git-ignored `android/.gradle/` bookkeeping. It was read from
  (`signing_inputs.sh` copies *from* it), never written to. Its `.git` directory is shared by every
  worktree, so the new refs and objects necessarily landed there — that is git's storage, not the
  working tree.
- No other worktree was modified. The geofence session's worktree was only inspected, and was clean.

## 10. Still open

1. **`docs/BUILD_LEDGER.md` has no row for +104** — nor for +100 through +103. The rows need TestFlight
   numbers only you can read. Convention 1 puts the ledger commit *after* the tag, so adding them now
   is clean.
2. **The three held branches** are untouched and still waiting on bench verification. When they are
   cleared, note that `fix/gameday-celebration-picker-wiring` is based on `73ae375` (two releases back)
   while the other two are based on `64fa5af`; none shares a file with this release's change, but they
   have not been checked against *each other*.
3. **Nothing in this build was seen on a phone.** The geofence fix is covered by 17 unit tests against
   the in-memory fake; whether Welcome Home now actually fires the chosen favorite on arrival needs a
   device crossing a real geofence.
4. This report is committed on `docs/release-104-report-2026-09-21` (one commit on top of the build
   point `3859df7`, outside the `build-104` tag), matching the +101 through +103 report branches.
