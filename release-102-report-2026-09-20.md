# Release 2.5.10+102 — pixel-map heal-on-read — report, 2026-09-20

**Tip / build point:** `a988854` — `chore(release): bump to 2.5.10+102`
**Tag:** `build-102` (annotated, tag object `8aa162c`) → `a988854`
**Branch:** `release/store-submission-102` · **Worktree:** `C:\Flutter Projects\lumina-b102` (fresh)
**Content over +101:** exactly one thing — the pixel-map heal-on-read fix (`fix/pixelmap-heal-on-read`,
commits `7383773` + `5a36a2e`). Details of the fix itself are in
`pixel-map-heal-on-read-report-2026-09-19.md`, which ships in this tree; this report covers the release.

| | |
|---|---|
| Merge | clean, no conflicts — `b1acc42` |
| `flutter analyze` | 0 errors / 12 warnings / 370 infos — **0 new, 0 removed** |
| `flutter test` (full suite) | **3,175 passed · 0 failed · 0 skipped** — identical to the baseline, on the merged tree *and* on the bumped tree |
| iOS CI | **started AND finished: `success`** (Codemagic `iOS Release`, 15:33:07Z → 15:50:04Z) |
| Android bundle | built locally, versionCode **102**, same signer as +101, **not uploaded** |
| Production Firestore | **no access of any kind** |
| Shared checkout / `main` | **untouched** |

---

## 1. Ground truth (Step 1)

`git fetch origin --prune`, then `git ls-remote origin` — verified, not assumed:

| Ref | Found | Expected |
|---|---|---|
| `origin/release/store-submission-consolidated` | `9749d91` | `9749d91` ✔ |
| `origin/dev/post-submission` | `9749d91` | ✔ |
| `build-101` | → `9749d91` | ✔ |
| `origin/main` | `699a498` | ✔ (unchanged) |
| `fix/pixelmap-heal-on-read` on origin | **absent** | ✔ still unpushed |

Nothing had moved since last night. Locally the fix branch was intact: `9749d91` → `7383773` → `5a36a2e`,
clean tree, no upstream configured.

## 2. Backup push of the fix branch (Step 2)

Before pushing to a **public** repo I scanned every added line of `9749d91..5a36a2e` (7 files, +1,006 / −4)
for the customer-id prefixes that appear in the +101 report's §4, the controller-id prefix, API-key shapes,
e-mail addresses, key material and the words password / secret / token: **zero hits.**

Plain push (no force). Verified by fetch-and-compare: local `5a36a2ef5d73…` == `origin/fix/pixelmap-heal-on-read`
`5a36a2ef5d73…` == `ls-remote`; `git diff --quiet` between the two: identical.

## 3. Merge (Step 3)

`git worktree add -b release/store-submission-102 …/lumina-b102 origin/release/store-submission-consolidated`
(at the confirmed tip `9749d91`), then `git merge --no-ff fix/pixelmap-heal-on-read`.

- **No conflicts.** Merge commit **`b1acc42`**, 7 files, +1,006 / −4.
- **The merged tree is byte-identical to the fix branch tip** (`git diff --quiet b1acc42 5a36a2e`) — so
  everything verified on that branch last night, including the bench run, was verified on this exact code.
- **One choice to flag:** the fix branch sat directly on top of the consolidated tip, so a plain `git merge`
  would have fast-forwarded and created no commit. I used `--no-ff` so the history records "heal-on-read
  was integrated for +102" as a single, revertable merge. It cannot change the tree, and it did not.
- Git auto-configured the new branch to track `origin/release/store-submission-consolidated`; I unset that
  immediately so that no bare `git push` could ever land there by accident. Every push in this task used an
  explicit `src:dst` refspec.

## 4. Verification on the merged tree (Step 4)

Fresh worktree → `flutter pub get` (exit 0, `pubspec.lock` unchanged, tree still clean), then the gate at `b1acc42`:

- **`flutter analyze`** — 382 issues: **0 errors / 12 warnings / 370 infos.** Issue-set diff (line numbers
  ignored) against the heal-on-read branch's run: **0 new, 0 removed.**
- **`flutter test`**, full suite (`test/bench test/features test/models test/screens test/services test/unit
  test/utils test/widgets`) — **3,175 passed, 0 failed, 0 skipped.** Baseline from the heal-on-read report:
  3,175 / 0 / 0. **No regressions.** (The one `~` in the log is a test *name* containing "~22h", not a skip
  marker — checked.)
- The gated hardware tests (`test/hardware`, `RUN_HW=true`) are outside the suite by design and were **not**
  re-run today: nothing hardware-facing differs from the tree that was bench-verified last night (§3), and
  I did not want to change the house lights unattended for no new information.

## 5. Version bump (Step 5)

- `pubspec.yaml`: `2.5.10+101` → **`2.5.10+102`**
- `lib/app_version.dart`: `kAppVersion = '2.5.10+102'`
- **Alias verified after the merge, not assumed:** `lib/features/installer/staff_auth_telemetry.dart:58` is
  still `const String kStaffAuthTelemetryAppVersion = kAppVersion;`, consumed at `:143` and `:191`
  (`'app_version': …`). The login screen reads `kAppVersionName`, derived from the same constant.
- `grep` for any `2.5.10+10x` literal across `lib test android ios codemagic.yaml pubspec.yaml`: only the two
  bumped lines, plus one historical mention in a test file's header comment (`design_studio_101_live_test.dart`).
  No third literal to drift.
- **Gate re-run on the bumped working tree *before* committing**, same as +100 / +101: `pub get` exit 0;
  analyze **0 / 12 / 370, 0 new / 0 removed**; tests **3,175 / 0 / 0**. Only then committed — explicit
  pathspec, two files, +2 / −2 — as **`a988854`**. The bump commit is therefore both the tested tree and the
  build point; nothing was committed after it.

## 6. Tag and push (Step 6)

Immediately before pushing I fetched again and checked ancestry explicitly
(`git merge-base --is-ancestor`): both target branches were still at `9749d91`, and `9749d91` is an ancestor
of `a988854` — **both fast-forwards clean.** `build-102` and `release/store-submission-102` did not exist
locally or on origin. No force-push anywhere; each was a plain push that can only succeed as a fast-forward.

Confirmed afterwards with `git ls-remote origin`:

| Ref on origin | Now | Was |
|---|---|---|
| `release/store-submission-102` | `a988854` | (new) |
| `build-102` (annotated, tag object `8aa162c`) | → `a988854` | (new) — matches `codemagic.yaml` `tag_patterns: 'build-*'`, the only CI trigger |
| `release/store-submission-consolidated` | `a988854` | `9749d91` — **fast-forward** (`9749d91..a988854`) |
| `dev/post-submission` | `a988854` | `9749d91` — **fast-forward** (`9749d91..a988854`) |
| `fix/pixelmap-heal-on-read` | `5a36a2e` | (new — §2) |
| `main` | `699a498` | `699a498` — **not touched** |

## 7. CI (Step 7)

**Did the build start? Yes — confirmed**, via the public GitHub check-runs API for the tagged commit:

`iOS Release` · started **2026-09-20T15:33:07Z** · head `a988854` · app `codemagic-ci-cd`

**And it finished: `completed` / `success` at 2026-09-20T15:50:04Z** (about 17 minutes). I polled once a
minute until it resolved rather than leave it open. What that does and does not tell you: the Codemagic
workflow passed end to end; I have no view into App Store Connect, so whether the build has finished
Apple-side processing and appears in TestFlight is **not** something I can confirm — check TestFlight. The
iOS build number comes from Codemagic's own counter, not from `+102`; read it off TestFlight. Re-query:
`https://api.github.com/repos/Nex-GenLED/Nex-Gen-Lumina/commits/a9888549be4eeca24d5cf6429cf89c87508deb56/check-runs`

For the record, since last night's report left it open: **+101's iOS build completed `success`** at
2026-09-20T00:18:32Z.

## 8. Android bundle (Step 8) — local only, NOT uploaded

Same recipe as +100 / +101:
`flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info/android` — exit 0, 293 s.

- **`C:\Flutter Projects\lumina-b102-artifacts\lumina-2.5.10+102-a988854.aab`** — **68,722,424 bytes**,
  sha256 `c40ca722ac87ac53c018a9381dd28c75698a0606d00c786e9abefa0b92e75c3a` (equal to the build output's hash,
  re-verified after the copy). `SHA256.txt` alongside.
- `debug-info-android/` — the three symbol files (`arm`, `arm64`, `x64`). **Keep them**: they are required to
  symbolicate any crash from this build. Not in source control.
- **From the built bundle itself** (its proto manifest, not `pubspec`): `package com.nexgenled.lumina`,
  **`versionCode="102"`**, `versionName="2.5.10"`, `minSdk 24`, `targetSdk 36`. The reader I used was first
  checked against the +101 bundle, where it returned the known `101`.
- **`jar verified.`** Signer `CN=Tyler Honeycutt, OU=Nex-Gen LED LLC, O=Nex-Gen LED LLC, L=Blue Springs, ST=MO,
  C=US`, SHA-1 `8E:4A:35:82:…:FD:0A:57:DA`, SHA-256 `96:6A:36:4E:…:A1:C8:6D:DF` — **the same certificate as
  +101**, compared against the +101 bundle directly, both fingerprints.
- Built from `a988854` with an empty `git status` before and after.
- **A convention I broke in the letter, and checked in substance.** `docs/BUILD_LEDGER.md` standing
  convention 3 says the three git-ignored signing inputs must be copied **from the main repo, never from a
  prior build worktree**, so that a stale key cannot propagate build to build. Following the +101 pattern I
  copied them from the +101 worktree; I only re-read the convention afterwards. I then compared the copies
  used for this build **byte for byte (`cmp`) against the main repo's** — `key.properties` (112 B), the
  keystore (2,776 B), `google-services.json` (712 B): **all three IDENTICAL**, and the sizes match the
  convention's table. So the bundle is signed with exactly the bytes the convention would have produced and
  I did not rebuild (a rebuild would consume nothing new but proves nothing new either). Convention 2's exact
  check — `jarsigner -verify -verbose:summary -certs` — reads `X.509, CN=Tyler Honeycutt, OU=Nex-Gen LED LLC`.
  Next build: copy from main. (+101 did the same thing; its report says so in its §7.)
- **versionCode 102 is now consumed. The next Android build must be ≥ +103.**

## 9. No other production changes (Step 9)

- **Production Firestore: no access of any kind — no write, no read.** No script was run against the
  project, no admin SDK, no REST call, no rules call. **Nothing was deployed**: no rules, no functions, no
  indexes. This release changes app code only, and that code is itself incapable of writing on load (see the
  heal-on-read report §6 — proven by test, not only argued).
- The 7 stale production pixelMap documents are **still stale and untouched**. With +102 they behave
  correctly in the app; the 3 overflow homes still need a real remap, and the app still says so.
- **Everything that touched a network in this task:** `git fetch` / `git push` to GitHub (§2, §6), the public
  unauthenticated GitHub check-runs API (§7), `flutter pub get` and the Gradle build's dependency resolution.
  Nothing else.
- **The bench controller was not touched.**
- **Shared checkout `C:\Flutter Projects\Lumina V 1.6`: not touched.** I recorded a baseline before doing
  anything and compared at the end — `HEAD` `df6063b` (detached), index file SHA-1 `05513ea492db…`, 42 pending
  paths, and a hash of the full `status --porcelain -uall` listing: **all four identical.** The only reads
  were `git status` (with `GIT_OPTIONAL_LOCKS=0`, so not even the index was refreshed) and an md5 of the
  three signing inputs.
- `main` not touched. No existing branch modified other than the two fast-forwards asked for. No tag moved.

## 10. Flagged for you

1. **CI passed** (§7) — but TestFlight availability and the iOS build number are yours to read; I cannot see App Store Connect.
2. **`docs/BUILD_LEDGER.md` is three builds behind: its newest row is +99.** +100, +101 and now +102 are not
   in it, and its own header says "one row per build that leaves this machine … this ledger is not optional"
   (all three left the machine: each went to Codemagic). I did **not** add rows: it is outside the brief, a
   ledger commit would have to land *after* the tag (convention 1) and so would move
   `consolidated` / `post-submission` past the tip you asked me to fast-forward to, and the rows need the
   TestFlight build numbers, which only you can read. Everything else they need is in §6–§8 here and in the
   +100 / +101 reports. This is a decision for you, not an oversight I am papering over.
3. **Signing inputs were copied from the +101 worktree, not from main** (§8) — against ledger convention 3
   in the letter; byte-identical to main's in fact.
4. **The `--no-ff` merge** (§3) — a deliberate choice where the brief was silent. Tree-neutral.
5. **The heal-on-read report is now public** along with the code. It was written for that: homes by letter,
   no ids (scanned again before the push, §2).
6. **Not re-run today:** the gated bench tests (§4). Last night's bench result stands for this exact tree.
7. **Neither store upload was done**, as instructed: the `.aab` is on disk only; iOS goes wherever the
   Codemagic workflow sends it.
