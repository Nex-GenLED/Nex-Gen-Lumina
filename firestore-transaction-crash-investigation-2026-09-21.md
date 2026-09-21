# Firestore transaction crash investigation — 2026-09-21

**Crash:** `EXC_BAD_ACCESS` / `SIGSEGV` in the `cloud_firestore` iOS plugin, matching
[flutterfire#18417](https://github.com/firebase/flutterfire/issues/18417).
**Branch:** `fix/firestore-transaction-crash`, worktree `C:/Flutter Projects/lumina-fs-txn-crash`,
cut from `origin/release/store-submission-consolidated` @ `73ae375` (fetched and confirmed).
**State:** all changes are **uncommitted** in that worktree. Nothing was committed, pushed, tagged,
or version-bumped. `main`, the shared checkout, and every other worktree were not modified.

> **Status update, later on 2026-09-21 — supersedes the "uncommitted" statements above and in §7
> item 1.** The work was reviewed and committed on `fix/firestore-transaction-crash`, still
> **local-only: not pushed, not tagged, version still `2.5.10+102`**:
>
> - `c1c2cca` — the FlutterFire bump, the `hide Type` fix and the two test-fake signatures (§3).
> - `46a1458` — the two `AsyncLock` serializations and the new regression test (§5, §6.2).
>
> `c1c2cca` was additionally verified **on its own** in a throwaway worktree: 3175 pass / 14 skip /
> 0 fail, identical to baseline — so each commit is independently green for bisecting. With both:
> 3181 / 14 / 0. The fully-merged local branch name `fix/slot-meter-reservation` (§4.3, §7 item 7)
> was deleted with `git branch -d`; its commit `22c2fdb` remains on `main`.
>
> This branch is **not meant to ship alone**: it converges with the Game Day celebration-colors and
> Save-to-Device/favorites fix branches into one combined build. Everything else below is the
> report as originally written and reviewed. §3.4 (iOS `pod install`) and §6.3 (native repro)
> remain open.

---

## 1. Summary

| Question | Answer |
|---|---|
| Does the pinned plugin include the fix? | **No.** Locked `cloud_firestore 6.1.1`; the fix first ships in **6.7.0**. |
| Was a bump needed and applied? | **Yes.** Moved to the FlutterFire set of 2026-07-14 (`cloud_firestore 6.7.1`). It is a 6-package move, not a 1-package move. |
| Did the bump break anything? | **Yes, one production compile error** (`Type` name collision in `user_service.dart`) plus two test fakes. All three fixed; none is an API redesign. **Not blocking.** |
| Is there a concurrent-transaction pattern in mainline? | **Yes, two.** The relay's post-watchdog reconcile (customer-reachable) and the dealer order screen (same-document, dealer-only). Both now serialized. |
| `fix/slot-meter-reservation`? | **Coincidental, and already merged.** Not a Firestore transaction; not unmerged. |
| Tests | Baseline **3175 pass / 14 skip / 0 fail** → after **3181 / 14 / 0** (+6 new). |
| Could the native crash be reproduced? | **No** — no iOS/Android device, simulator, or emulator on this machine. See §6.3. |

**Two things I could not verify from Windows and that you should treat as open:** `pod install`
(§3.4) and the native crash itself (§6.3). The first real proof of the iOS half is the next
Codemagic build.

---

## 2. Step 1 — plugin version and whether the fix is included

### 2.1 What is pinned

| Source | Value |
|---|---|
| `pubspec.yaml` constraint (before) | `cloud_firestore: '>=5.5.0'`, `firebase_core: ^4.3.0` — effectively unpinned; the lockfile is the real pin |
| `pubspec.lock` (before) | `cloud_firestore 6.1.1`, `firebase_core 4.3.0`, `firebase_auth 6.1.3`, `cloud_functions 6.0.5`, `firebase_storage 13.0.5`, `firebase_messaging 16.1.0` |
| `ios/Podfile.lock` | **Does not exist in the tree and is not tracked** (it appears in history only in the initial commit and `0882796`). |

Because there is no `Podfile.lock`, the native versions are not pinned by the repo at all.
`codemagic.yaml` runs `rm -rf Pods Podfile.lock .symlinks`, `pod cache clean --all`, then
`pod install --repo-update` on every build, so the Firebase iOS SDK version is derived at build
time from `firebase_core`'s `ios/firebase_sdk_version.rb`. I read that file from the pub cache
instead:

| | `firebase_core 4.3.0` (before) | `firebase_core 4.12.1` (after) |
|---|---|---|
| Firebase iOS SDK | 12.6.0 | 12.15.0 |
| Firebase Android BoM | 34.4.0 | 34.15.0 |
| Podspec iOS deployment target | 15.0 | 15.0 (unchanged; app `Podfile` is 15.0) |

`ios/Podfile` contains no hard-pinned Firebase pods and no precompiled-framework override, so
nothing there fights the new version.

### 2.2 Which release first contains the fix

- PR [#18421](https://github.com/firebase/flutterfire/pull/18421), "fix(cloud_firestore): guard
  shared transactions map against concurrent access", merged **2026-07-08** as
  `e81cb6db46a87e932cbff3c1fb3a93fedbcb9a3b`.
- pub.dev changelog lists it under **`cloud_firestore 6.7.0`** (published 2026-07-13).
- I did not rely on the changelog alone. I inspected the native source in the pub cache:

| File | 6.1.1 (pinned) | 6.2.0 | 6.7.1 (new) |
|---|---|---|---|
| iOS `FLTFirebaseFirestorePlugin.m` — `@synchronized` sites | 2, none on the hot path | — | 5, all four `_transactions` accesses guarded |
| Android `transactions` map | `new HashMap<>()` | `new HashMap<>()` | `new ConcurrentHashMap<>()` |

In 6.1.1, lines 639 / 758 / 761 read and write `self->_transactions[...]` bare, from blocks that
Firestore invokes on its transaction worker threads. That is the race.

**Verdict: the pinned version definitively predates the fix.** It has been locked at 6.1.1
since the initial commit (2026-01-20).

### 2.3 One correction to the framing

The corrupted dictionary is not inside `FLTTransactionStreamHandler`; it is `_transactions` on
`FLTFirebaseFirestorePlugin`. `FLTTransactionStreamHandler` *invokes* the `started` / `ended`
blocks that mutate it, which is why its frames show in the crash stack. `e81cb6d` did not touch
`FLTTransactionStreamHandler.m` at all.

This matters for §4: the dictionary is shared **plugin-wide**, so the race needs only two
transactions in flight at once, on *any* documents. Same-document contention is an amplifier, not
a requirement — every retry re-enters the run block, which calls `started` again, which is
another unguarded dictionary write.

---

## 3. Step 2 — the bump

### 3.1 It is a six-package move

`cloud_firestore 6.7.0` requires `firebase_core ^4.12.0` and
`firebase_core_platform_interface ^7.1.0`. Every other FlutterFire plugin in the app was locked
against platform interface `^6.x`. They share that package, so they must move together.

### 3.2 Target choice: 6.7.1, deliberately not "latest"

The transaction code kept changing upstream after the fix, and one of those releases is a trap:

| Release | Commit | What it did |
|---|---|---|
| **6.7.0** | `e81cb6db` #18421 | **The crash fix.** The only commit in the whole range that touches iOS transaction code. |
| 6.7.1 | — | Dependency re-release one day later (platform interface 7.1 → 8.0). |
| **6.8.0** | `ae002c7c` #18475 | Android leak fix that **introduced a regression: `MissingPluginException` after every Android `runTransaction`** (#18546). **Do not land here.** |
| 6.9.0 | `f949c23d` #18553 | Fixes the 6.8.0 regression. Also: Kotlin Gradle plugin 2.3.0, "align Android toolchain with Flutter 3.47", and `firebase_core 4.14.0` **rewrites its native layer in Kotlin/Swift**. |
| 6.10.0 | `168172a8` #18668 | Pre-existing Android bug: a timed-out transaction could kill the process. 7 days old today. |

I chose the **2026-07-14 set (`cloud_firestore 6.7.1`)**:

- It is the smallest jump that contains the fix, on a store-submission line.
- For iOS transaction code it is *identical to latest* — nothing after `e81cb6d` touched it.
- It sits before the 6.8.0 regression and before the `firebase_core` native rewrite, which I
  cannot build-verify for iOS from this machine.

What 6.7.1 knowingly leaves on the table (both **pre-existing in 6.1.1 today**, so not
regressions): the Android per-transaction native leak (#18474) and the Android timed-out-transaction
crash (#18666). Moving to ≥ 6.9.0 later picks both up; that should be its own change with its own
iOS build verification.

### 3.3 What changed

`pubspec.yaml` — the six Firebase constraints became caret floors at the new set, with a comment
recording the 6.7.0 floor and the 6.8.0 trap. To land *exactly* on the 07-14 set rather than on
latest, I resolved once with exact pins, then relaxed to carets and re-resolved; the second
resolve produced **0 lockfile drift**.

`pubspec.lock` — 24 packages, all FlutterFire or its test fakes:

| Package | Before | After |
|---|---|---|
| `cloud_firestore` | 6.1.1 | **6.7.1** |
| `firebase_core` | 4.3.0 | 4.12.1 |
| `firebase_auth` | 6.1.3 | 6.5.6 |
| `cloud_functions` | 6.0.5 | 6.3.5 |
| `firebase_storage` | 13.0.5 | 13.4.5 |
| `firebase_messaging` | 16.1.0 | 16.4.3 |
| `cloud_firestore_platform_interface` | 7.0.5 | 8.0.5 |
| `firebase_core_platform_interface` | 6.0.2 | 8.1.1 |
| `fake_cloud_firestore` *(dev)* | 4.1.0+1 | 4.3.0 |
| `fake_firebase_security_rules` *(dev)* | 0.5.4 | 0.6.0 |
| + 14 `_web` / `_platform_interface` / transitive (`cel`, `rx`, `equatable`, `_flutterfire_internals`) | | |

No `ios/` or `android/` file changed. Flutter floor rises to ≥ 3.27 (local is 3.41.2; Codemagic
uses `stable`).

### 3.4 `pod install` — NOT RUN (cannot, on Windows)

You asked me to run `pod install` and confirm `Podfile.lock`. I could not: this is a Windows
machine with no CocoaPods, and the repo tracks no `Podfile.lock` to diff. What I can say with
confidence is *what CI will resolve*: Codemagic deletes `Pods`/`Podfile.lock` and runs
`pod install --repo-update` every build, the Podfile pins nothing, and `firebase_core 4.12.1`
declares Firebase iOS SDK **12.15.0** at the same iOS 15.0 target. **The first Codemagic iOS
build on this branch is the real verification; check its `pod install` step for
`Firebase 12.15.0` / `FirebaseFirestore 12.15.0`.**

### 3.5 Breakage caused by the bump — found and fixed, not blocking

`flutter analyze` on the bumped tree reported 4 errors (0 before):

1. **Production — `lib/services/user_service.dart`.** `cloud_firestore` ≥ 6.3 (the Pipelines
   feature) exports `enum Type` from `pipeline_expression.dart`, which is a `part` of the main
   library. It shadows `dart:core`'s `Type` in every file that imports `cloud_firestore`
   unprefixed. `FirestoreSerializationError.valueType` is declared `final Type`, so it silently
   became the Pipelines enum and both `valueType: x.runtimeType` call sites stopped compiling.
   **Fix:** `import 'package:cloud_firestore/cloud_firestore.dart' hide Type;` with a comment.
   This was the only file in `lib/` affected. It will recur in any future file that uses `Type`
   next to a bare `cloud_firestore` import.
2. **Test fake** — `controller_migration_failure_test.dart`: `WriteBatch.update` became generic
   (`update<T>(DocumentReference<T>, T)`) for the new `withConverter` batch support. Signature
   updated. No `lib/` caller is affected.
3. **Test fake** — `sync_notification_token_on_late_signin_test.dart`: `getToken` gained a
   web-only `serviceWorkerScriptPath` parameter. Signature updated.

After the fixes: **0 errors, 12 warnings, 371 infos** — the 12 warnings are the pre-existing
baseline.

I also checked one runtime-behaviour change: 6.7.0 "preserve detailed native Firestore error
messages" alters `FirebaseException.message` text. Lumina does not string-match on Firestore
error messages anywhere in `lib/`, so this is inert.

---

## 4. Step 3 — every `runTransaction` call site

Ten call sites in five files. There are no others (searched all `*.dart`, including `test/` and
`bench/`). Each is syntactically `await`ed; the real question is whether the *enclosing function*
can be entered concurrently.

| # | Site | Target doc | Concurrency gate before | Verdict |
|---|---|---|---|---|
| 1 | `cloud_relay_repository.dart` `_reconcileAfterWatchdog` | the command's own doc | **none** | **CONCURRENT — fixed** |
| 2 | `dealer_order_providers.dart` `addOrUpdateLineItem` | one shared order doc | **none** | **CONCURRENT, same doc — fixed** |
| 3 | `dealer_order_providers.dart` `removeLineItem` | one shared order doc | **none** | **CONCURRENT, same doc — fixed** |
| 4 | `dealer_order_providers.dart` `approveWithShipping` | order doc | screen `_busy` flag | Safe (now also behind the per-order lock) |
| 5 | `dealer_order_providers.dart` `rejectOrder` | order doc | screen `_busy` flag | Safe (now also behind the per-order lock) |
| 6 | `schedule_store_sync.dart` `applyArrayTxn` | `users/{uid}` | **per-uid `AsyncLock`**; mirrors chained per uid | **Already correct** — this is the house pattern I copied |
| 7–9 | `invitation_service.dart` accept / revoke / updatePermissions | invite + user docs | single user tap | Safe |
| 10 | `referral_program_screen.dart` `_ensureReferralCode` | a *different* code doc per attempt | sequential `await` in a `for` loop | Safe (a `FutureProvider` re-run could overlap two at most, once per account lifetime) |

### 4.1 Site 1 — the relay reconcile (the one ordinary customers can hit)

Introduced by `e005a02` on **2026-06-01** (the #52 false-timeout fix). Every relay command that
times out ends in a `runTransaction` exactly `_commandTimeout` (45 s) after it was dispatched, and
`_executeCommand` has no in-flight limit. So **a burst of commands at a slow or offline bridge
becomes a burst of concurrent transactions 45 s later.** Two things make real bursts likely:

- Callers abandon the future early (`.timeout(const Duration(seconds: 3))` at two sites in
  `wled_providers.dart`) while the underlying command — and its eventual transaction — keeps
  running. Users also re-tap when lights do not respond, which is exactly when the bridge is slow.
- **iOS resume from background.** Dart timers that expire during suspension all fire together on
  resume, so every in-flight watchdog resolves in the same instant.

What limits it: the poller has a `_polling` re-entry guard (at most one poll-driven transaction
per 45 s), and the dashboard write path has a latest-wins transient gate, so slider drags
collapse. Writers that call the repository directly (pattern apply, scenes, etc.) bypass both.

The new regression test demonstrates it directly: against the **unfixed** tree, an 8-command
burst produced a measured **peak of 8 simultaneous transactions**.

Honest scope: each of these transactions hits a *different* document, so there is no contention
and no retry amplification. Per §2.3 the race does not need same-document contention, but the
per-event probability is low. This is a **plausible** trigger and the only customer-reachable one;
I cannot prove it is *the* trigger without the crash reports. Two checks you can make that I
cannot: (a) no affected build should predate `e005a02` / 2026-06-01 if this is the cause;
(b) affected sessions should skew toward remote mode with a slow or offline bridge, often just
after foregrounding.

### 4.2 Sites 2–3 — the dealer order screen (the textbook shape, small scale)

`order_screen.dart`: the +/− stepper only edits local state (good), but **"Add to Order" /
"Update" / "Remove" have no in-flight gate.** A row stays `isDirty` until the transaction commits
*and* the snapshot stream re-delivers, so a double-tap, or "Add" on several product cards in a
row, launches concurrent read-modify-write transactions on **one order document** — contention,
retries, the documented pattern exactly. Dealer-only and low volume (dealer `01` is the only live
dealer), so it is unlikely to explain a customer crash, but it was genuinely wrong. Under the
passthrough test fake the unfixed code also **loses line items** (measured peak 6).

### 4.3 `fix/slot-meter-reservation` — coincidental, and not unmerged

- Its tip `22c2fdb` **is** the merge-base with the consolidated line: zero unique commits. It is
  an ancestor of `origin/main`, `origin/dev/post-submission` and
  `origin/release/store-submission-consolidated` (verified with `git merge-base --is-ancestor`).
  Only the branch *name* is local-only. The earlier audit's "unmerged, never investigated" flag
  was stale.
- Content (#90): the schedule save guard was shrinking the WLED timer budget by the count of
  calendar *dates* (55 on your account) instead of the lease timers actually *reserved on the
  device*, so every save was refused. "Reservation" means **WLED on-device timer slots**. It is
  in-memory arithmetic in `timer_slot_meter.dart` plus tests.
- It contains **no** `runTransaction`, no Firestore write, and no resource-reservation
  transaction. The only "Firestore" matches in the diff are prose in comments.

**Verdict: coincidental.** Not related context, not an attempted fix for anything adjacent. The
branch name can be deleted whenever convenient (I did not).

---

## 5. App-level fixes and why

Both use the existing `lib/utils/async_lock.dart` (FIFO, exception-safe, already tested) and
follow the `applyArrayTxn` precedent, including its honest scope: `runTransaction` still owns
cross-device correctness; the lock only stops this isolate contending with itself.

### 5.1 `cloud_relay_repository.dart`

`_reconcileAfterWatchdog` now runs its transaction inside a **`static`** `AsyncLock`. Static on
purpose: `wledRepositoryProvider` rebuilds the repository on every connectivity or controller
change, so reconciles that overlap routinely belong to different instances, and a per-instance
lock would miss them. Behaviour is otherwise byte-for-byte the same (the diff is mostly
re-indentation).

**Trade-off:** a queued reconcile waits for those ahead of it. That only delays a result the
caller has already waited 45 s for, on a path that is already failing. Worst case is fully
offline, where each transaction can take several seconds to fail, so the *n*-th command of a burst
reports its failure correspondingly later. I judged that acceptable; say so if you would rather
cap it with an explicit shorter `timeout:` on the transaction.

### 5.2 `dealer_order_providers.dart`

All four order transactions go through a new `_orderTxn(orderId, body)` helper with a **per-order**
`AsyncLock`. Keyed per order so unrelated orders never queue behind each other. Placed in the
notifier rather than the screen so every current and future caller is covered.

Not done: a UI in-flight flag on the buttons. With the lock a double-tap is now two *sequential*
transactions (the second a no-op write) and two snackbars — harmless, so I left the screen alone.

### 5.3 Why both, given the plugin is now fixed

The upstream fix stops the crash. It does not stop the app launching avoidable parallel
transactions — and, for the order document, avoidable contention and retries against Firestore.
The plugin's internal lock should be the backstop, not the only safeguard.

---

## 6. Step 4 — verification

### 6.1 Full suite

| Run | Tree | Passed | Skipped | Failed |
|---|---|---|---|---|
| Baseline | `73ae375`, `cloud_firestore 6.1.1`, throwaway detached worktree | **3175** | 14 | **0** |
| After | bump + fixes + new tests | **3181** | 14 | **0** |

3181 = 3175 + 6 new. Identical skip count. (#64's midnight-wrap lease test did not fire in either
run.) After a final one-line lint cleanup in the new test file I re-ran it together with the
three touched/related test files: 34 / 34 pass.

### 6.2 The new tests discriminate

`test/regression/firestore_transaction_serialization_test.dart` — 6 tests using a
`FakeFirebaseFirestore` subclass that records peak in-flight `runTransaction` calls. Run against
the **unfixed** baseline tree, 5 of 6 fail with measured peaks of **8, 4, 2, 6 and 3**; the sixth
(unrelated orders must *not* block each other) passes on both, as designed. On the fixed tree all
six pass with peak = 1, and the order test additionally proves no line item is lost.

### 6.3 Native crash reproduction — NOT DONE, and why

- `flutter devices` shows only Windows desktop, Chrome and Edge. No iOS device or simulator (no
  Mac), no Android device or emulator. `flutter test` on a host never loads the native plugin, so
  it cannot exercise the corrupted dictionary either way.
- I did not attempt a reproduction against the production Firebase project from desktop or web:
  those use different plugin implementations (C++ / JS), so it would prove nothing about the iOS
  code while still writing to production.
- **Consequently no throwaway Firestore data was created anywhere, and there is nothing to clean
  up.** Every test ran against in-memory `fake_cloud_firestore`.
- Upstream PR #18421 added its own end-to-end regression test (`transaction_e2e.dart`) that runs
  on their device CI; that is the evidence that the native fix holds.

If you want a real repro once a Mac or device is available: two builds (6.1.1 and 6.7.1), a debug
hook that fires ~50 un-awaited `runTransaction` calls at one document under
`users/{uid}/_txn_repro/{doc}` in the **Firestore emulator**, then delete the collection.

### 6.4 Android debug build

Not something you asked for, but since I cannot build iOS here it was the best available proof
that the new *native* dependency set compiles. `flutter build apk --debug` on the bumped tree:
**succeeded, exit 0, 308.9 s** (`app-debug.apk`), against Firebase Android BoM 34.15.0 with the
app's existing AGP 8.7.3 / Kotlin 2.1.0 / Gradle 8.12 / `compileSdk 36` / `minSdk 24` — no Gradle
or manifest change needed. `cloud_firestore 6.7.1`'s Java compiled with deprecation notes only.

Build inputs: the worktree had no `google-services.json` (git-ignored), so I used the sanctioned
`bash scripts/signing_inputs.sh install` (copies from the main repo read-only; all three verified
IDENTICAL). A debug build does not need the release keystore or `key.properties`, so after the
build **I deleted all three copies from this worktree** — no signing material was left behind, and
the main repo's originals are untouched. If you cut a release from this branch, do it from a
release worktree and re-run `install` there as usual.

This is a **debug** build only: it proves compilation and dependency resolution, not R8 / release
behaviour, and not runtime behaviour on a device.

---

## 7. Open items and decisions for you

1. **Nothing is committed.** Review the worktree diff; tell me to commit (and how to split it —
   I would suggest: bump + `Type` fix + test-fake fixes as one commit, the two serialization fixes
   + new test as a second).
2. **Version:** not bumped. Per the ledger the next Android build must be ≥ `+103`.
3. **iOS pod resolution is unverified** until Codemagic builds this branch (§3.4).
4. **Later, separately:** move to ≥ 6.9.0 for the two pre-existing Android transaction bugs.
   **Never 6.8.0.** Budget an iOS build check for the `firebase_core` native rewrite.
5. **Confirming the trigger** needs the crash reports' build numbers and session context (§4.1).
   Note the posture gap already in memory: Lumina has no Crashlytics/Sentry, and the `debug_errors`
   sink is Dart-level, so a native `SIGSEGV` never reaches it — these crashes are visible only in
   App Store Connect / Xcode Organizer.
6. **Incidental bug, not fixed (out of scope):** the order screen's **"Remove" button does not
   remove** in the common case. It calls `onLocalChange(0)` then `onCommit()` synchronously, but
   `onCommit` closed over the *previous* `pendingQty`, so it re-commits the old quantity and the
   row snaps back. It only works if the user first steps the quantity down to 0. One-line fix
   (pass the quantity explicitly); wants its own widget test.
7. **Housekeeping:** the local branch name `fix/slot-meter-reservation` is fully merged and can be
   deleted.

## 8. Files changed

```
lib/features/wled/cloud_relay_repository.dart        static reconcile lock
lib/services/inventory/dealer_order_providers.dart   per-order transaction lock
lib/services/user_service.dart                       `hide Type` (bump fallout)
pubspec.yaml / pubspec.lock                          FlutterFire set of 2026-07-14
test/features/installer/controller_migration_failure_test.dart              fake signature
test/features/neighborhood/sync_notification_token_on_late_signin_test.dart fake signature
test/regression/firestore_transaction_serialization_test.dart               NEW, 6 tests
firestore-transaction-crash-investigation-2026-09-21.md                     this report
```
