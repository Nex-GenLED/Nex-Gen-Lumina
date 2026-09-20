# Signing-input guard — report, 2026-09-20

**Branch:** `chore/signing-inputs-guard` — **local only, not pushed** · commit `73ae375`
**Base:** `origin/release/store-submission-consolidated` @ `a988854` (= `build-102`)
**Worktree:** `C:\Flutter Projects\lumina-signing-guard`
No release branch, tag or version number was touched. **No release artifact was built.**

> **The one thing to act on:** the guard does nothing until this branch is merged into the line releases
> are cut from. A +103 cut from `consolidated` today would still be unguarded. See §6.

---

## 1. Audit — what I found before changing anything

**The real input set** (convention 3, confirmed against `.gitignore` and `android/app/build.gradle`):

| file | size | why it is an input |
|---|---|---|
| `android/key.properties` | 112 B | store/key passwords, alias, and `storeFile` |
| `android/app/nex-gen-lumina.keystore` | 2,776 B | the release key — the file `storeFile` names, resolved from `android/app` |
| `android/app/google-services.json` | 712 B | Firebase project binding; `processReleaseGoogleServices` needs it |

`GoogleService-Info.plist` is **not** in the set: it is iOS-only, is not tracked, and no local Android build
reads it. The guard follows `storeFile` rather than hardcoding the keystore's name.

**Canonical source:** the main working tree of this git repository — `C:\Flutter Projects\Lumina V 1.6` —
which is what `git worktree list` reports first from *any* worktree. The guard asks git; no path is hardcoded.

**Three findings that shaped the fix:**

1. **`build.sh` is not how releases are built.** +100, +101 and +102 were all cut with
   `flutter build appbundle` directly (`build.sh` also builds an APK nobody wants). A check that lived only
   in `build.sh` — what the brief suggested — **would not have fired for either deviation you named.** The
   only place every Android release build passes through is Gradle, so that is where the enforcement is.
   `build.sh` gets the same check too, as an early pre-flight.
2. **It has happened three times, not two.** The ledger's own +97 row records the identical deviation
   (copied from the `lumina-114-fix` worktree). Three of the last five Android builds: +97, +101, +102;
   +99 and +100 complied.
3. **No stale copy exists anywhere today.** I checksummed the three files in every worktree: 13 copies of
   each, all byte-identical to main. So nothing is currently wrong — and the mismatch test had to use a
   deliberately altered copy.

## 2. What was added, and where

| file | role |
|---|---|
| **`android/signing-inputs-guard.gradle`** (new) | **The enforcement.** |
| `android/app/build.gradle` | one `apply from:` line (+ comment) |
| **`scripts/signing_inputs.sh`** (new) | `verify` and `install` |
| `build.sh` | pre-flight 0 for `build-android-release`: runs `verify` before anything else |
| `docs/BUILD_LEDGER.md` | convention 3 rewritten; one note on convention 2 |
| `CLAUDE.md` | release-build section now names `install` and the guard |

**The guard.** When the Gradle task graph is known — **before any task executes** — if the graph contains
any release task of `:app`, it compares the three inputs **byte for byte** with the main repo's copies. Any
file missing or different throws, and the build stops with a banner:
`SIGNING-INPUT GUARD: RELEASE BUILD REFUSED - NOTHING WAS BUILT`, a per-file verdict, and the fix.

- **No skip flag, deliberately.** A hurried session would use it. `LUMINA_SIGNING_CANONICAL_DIR` exists for
  a *separate clone* (which cannot discover the main repo) and names where to compare against — it does not
  turn the comparison off.
- In the main repo itself the inputs *are* the canonical set; only their presence is checked.
- `CM_KEYSTORE_PATH` set (CI signing from the secret store, already supported by `build.gradle`) scopes out
  `key.properties` and the keystore; `google-services.json` is still checked.
- Debug and profile builds are untouched.
- Nothing prints file contents or hashes — `key.properties` holds passwords; a hash of a 112-byte,
  low-entropy file is a small offline-guessing aid. Sizes only.

**`install` addresses the root cause.** The deviation kept happening because hand-copying from the nearest
worktree is the path of least resistance. `bash scripts/signing_inputs.sh install` is now shorter than the
three `cp` commands: it copies from main, refuses any path that is not git-ignored in the target (so a copy
cannot leak into a commit), and verifies.

## 3. How it was verified (Step 4)

All in the fresh worktree, which began with **no inputs at all** — the state every release session starts
in. Mismatches came from a simulated **stale build worktree** in my scratchpad; no real worktree's files were
altered. **Nothing was built:** Gradle runs used `--dry-run`; the two real `flutter build` invocations were
ones the guard refuses, run only after the dry-run had proved it fires on that exact graph.

**Fails loudly:**

| # | state | entry point | result |
|---|---|---|---|
| T1 | all three absent | `signing_inputs.sh verify` | exit 1 — 3 × `MISSING HERE` |
| T2 | keystore with **one flipped bit, same 2,776 B**; other two from main | `verify` | exit 1 — keystore `DIFFERS (here 2776 B, main repo 2776 B)`; the other two `IDENTICAL` |
| T3 | all three from the stale worktree (`key.properties` + 1 trailing newline; `google-services.json` 1 char changed, same size) | `verify` | exit 1 — 3 × `DIFFERS` |
| G1 | same as T3 | `gradlew :app:bundleRelease --dry-run` | **BUILD FAILED**, banner; **0** `:app` tasks; no `build/app/outputs` |
| G3 | same | `gradlew :app:verifySigningInputs` | BUILD FAILED |
| **G4** | same | **`flutter build appbundle --release --obfuscate …`** — the literal release command | **exit 1 in 7 s**, banner; no `.aab`, no `debug-info` |
| B1 | same | `./build.sh build-android-release` (`flutter` stubbed on PATH) | exit 1 at pre-flight 0; the stub was **never reached** |
| **E1** | all three absent | **`flutter build appbundle --release …`** | exit 1 — 3 × `MISSING HERE`; no `.aab` |
| E3 | override → nonexistent dir | `verifySigningInputs` | BUILD FAILED, clear message |

T2 is the one that matters most: the old convention asked for a **size** diff, which a same-size corruption
passes. E1 matters second: per convention 2, a release build with no inputs used to *succeed* (silently
debug-signed). It is now refused.

**Then restored and passes cleanly:** `signing_inputs.sh install` (copied 3, verified) →

| # | entry point | result |
|---|---|---|
| P1 | `verify` | exit 0 — 3 × `IDENTICAL to the main repo` |
| P2 | `./build.sh build-android-release` (flutter stubbed) | pre-flight passes, reaches the stub (`exit 99`) — i.e. the build *would* have started; no marker written |
| P3 | `gradlew :app:bundleRelease --dry-run` | `SIGNING-INPUT GUARD: OK`, **BUILD SUCCESSFUL**, 67 release tasks listed, all `SKIPPED` by dry-run; 0 `.aab` |
| G2 | `gradlew :app:assembleDebug --dry-run` **while inputs were mismatched** | BUILD SUCCESSFUL, guard silent — debug is not blocked |
| E2 | `CM_KEYSTORE_PATH` set, only `google-services.json` present | OK — notes the key files are out of scope |
| E4 | main-repo/self case (override → this checkout) | OK — `this checkout is the main repo`, script and Gradle agree |

Re-run once more after the final edits: `verify` OK, release dry-run OK, debug dry-run OK. `bash -n` clean
on both scripts. `git status` in the worktree stayed free of the inputs throughout (all three are ignored).
No Dart changed, so I did not re-run `flutter analyze` / `flutter test`.

## 4. The updated convention wording (`docs/BUILD_LEDGER.md`)

Heading: **"3. A fresh build worktree needs three ignored inputs, and they come from the MAIN repo — never
from a prior build worktree. ENFORCED BY THE BUILD, not by memory (from 2026-09-20)."** The core of it:

> *Why this matters.* The main repo's copies are the single source of truth for who signs a Lumina release
> and which Firebase project it talks to. A copy taken from another worktree is a copy of a copy: if one is
> ever stale, truncated, swapped during a key rotation, or tampered with, hand-to-hand copying carries it
> forward build after build and nothing notices — the build still succeeds, and the signer CN (convention 2)
> still reads correctly for any key issued under the same name. **So a release built from inputs that were
> not verified against the canonical set *before* the build is untrusted — even if they turn out to match
> afterwards.** "Checked after the fact and they happened to match" is luck recorded as a result, not a
> control: the artifact already exists by then, its versionCode is already consumed, and the check only ever
> happens if the session remembers it.
>
> *Why it is enforced rather than remembered.* As a rule to remember, this convention failed in **three of
> the last five Android builds — +97, +101, +102** …
>
> *The enforcement* is **`android/signing-inputs-guard.gradle`** … It is in Gradle because that is the only
> place every release build passes through: releases are cut with `flutter build appbundle` directly, not
> through `build.sh` …

It goes on to list: bytes not sizes; how "main repo" is resolved; no skip flag; absent inputs refused; the CI
scope; and that a ledger row now records `Signing inputs: GUARD OK` — "a row that has to say 'deviation'
should no longer be possible." Convention 2 gained one sentence: the absent-inputs path is closed, but
reading the signer out of the artifact **stays mandatory** — the guard checks inputs, convention 2 checks
the output.

## 5. One honest limit

The guard proves **the bytes used are the canonical bytes, before the build**. It cannot know *where* a
matching copy came from — a byte-identical copy taken from another worktree passes. I think that is the right
control (provenance stops mattering once identity is established up front, and that is the actual hazard
convention 3 names), and the convention now says so explicitly rather than implying more. Your brief's
phrasing — "untrusted even if it happens to match" — I have read as "not verified *before* the build", and
worded the ledger and the error message that way. If you meant provenance literally, that needs a different
mechanism (e.g. the inputs never being copied at all: `storeFile` and `key.properties` resolved from the main
repo by absolute path) — a bigger change to the signing config than I would make without a real signed build
to verify it against, which this task forbade.

## 6. Flagged

1. **Inert until merged.** Nothing on `consolidated`, `post-submission` or `main` has the guard. Merge
   `chore/signing-inputs-guard` (one commit on top of `a988854`, so currently a fast-forward) before +103 is
   cut. I did not, per "do not touch any release branch". Not pushed either — nothing in the brief asked for it.
2. **Pre-existing leak, found, not fixed.** `android/app/build.gradle:15` —
   `keystoreProperties.load(new FileInputStream(keystorePropertiesFile))` never closes the stream, so the
   Gradle daemon holds `key.properties` open on Windows: mid-test, `rm` failed with "Device or resource busy"
   (overwriting still works, so `install` is unaffected). Identical at `build-101` and `main`. One-line fix
   (`withInputStream`), but it is the signing config and I could not verify it with a real signed build here,
   so I left it. To finish the all-absent test I stopped the daemon — after confirming with
   `gradlew --status` that it was the only one and IDLE, so no other session's build could be affected.
3. **The release key is in 13 directories.** Every build worktree back to +79 (plus `lumina-114-fix` and a
   scratchpad worktree under `%TEMP%`) still holds the keystore *and* its passwords. All identical to main, so
   not a correctness problem — a hygiene one. The guard makes the copies disposable: retired worktrees can
   have them deleted, and `install` recreates them in a second. I deleted nothing.
4. **Beyond the brief, small:** the CLAUDE.md note and the one-sentence addendum to convention 2. Both keep
   the docs true now that the behaviour changed; say if you would rather they came out.
5. `gradlew` and its jar are git-ignored generated files, absent from a fresh worktree until Flutter's first
   build — so `bash scripts/signing_inputs.sh verify` is the by-hand check, not the Gradle task. For my
   dry-runs I copied the generated wrapper (tooling, not signing material) from the +102 worktree.

## 7. Confirmation

- No release branch, tag or version number touched. Remote refs unchanged: `consolidated` / `post-submission`
  `a988854`, `main` `699a498`, `build-102` → `a988854`. Nothing pushed.
- No release artifact built: no `.aab` / `.apk` exists under the worktree's `build/`.
- Shared checkout `C:\Flutter Projects\Lumina V 1.6` **read only** (the canonical copies were read for
  comparison and for `install`): HEAD, index SHA-1, pending-path count and status hash identical to the
  baseline recorded at the start.
- The main repo's three canonical files are unchanged (md5 before == after).
- I removed the key copies from my own test worktree afterwards (the count in §6.3 stays 13, not 14);
  `bash scripts/signing_inputs.sh install` puts them back in a second.
- No Firestore access. No deploy.
