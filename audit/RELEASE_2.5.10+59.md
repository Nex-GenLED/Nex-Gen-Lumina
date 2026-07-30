# RELEASE 2.5.10+59 — preset master-power healing fix

**Date:** 2026-07-30 · **Base:** `main` @ `393af46` + working-tree changes
**Nothing was uploaded and nothing was committed.** See §7 for what needs your hand.

---

## 1. BLOCKER — P3-57 fixtures fixed

**7/7 tests pass in `schedule_sync_idempotent_test.dart`. No assertion weakened.**

### Diff: 125 insertions / 7 deletions — and all 7 deletions are comment lines

```
$ git diff …idempotent_test.dart | grep "^-" | grep -E "expect\("
(no output — no expect() line was deleted)

expect() count:  before 27  →  after 35   (+8, none removed)
```

The single non-comment deletion is a `reason:` **string** reworded for accuracy
(`'system presets match → skip'` → `'healthy system presets skip'`). Its matcher,
`expect(repo.savedPresetIds, [10])`, is byte-identical.

### (a) The "system presets skip" test — fixtures moved to the HEALED shape

Eight fixtures across two tests (presets 1/3/4/5 × 2) gained root `on: true`:

```diff
         1: {
           'n': 'NGL On',
+          // HEALED shape: root `on: true` is what asserts MASTER power.
+          // Segment-level `on` does NOT — see the broken-shape test below.
+          'on': true,
           'seg': [
             {'on': true}
           ]
         },
```

Both affected tests now assert what they always intended:
- *"Option A … system presets skip"* — `savedPresetIds == [10]` holds, because the system presets are genuinely healthy.
- *"preset 2 named NGL Off but left ON is repaired"* — `savedPresetIds == [2]` holds, because 1/3/4/5 are healthy and the assertion isolates the preset-2 repair (which is its actual subject).

Comments updated so they no longer claim system presets "skip **by name**".

### (b) NEW regression guard — the test that stops the defect returning

```
test('ON presets named correctly but WITHOUT root on are re-saved '
     '(P3-57 regression guard: name-only skip must never come back)')
```

Fixtures 1/3/4/5 in the **broken** shape (right name, segments on, **no root `on`**) — the shape bench-confirmed on vid 2507300 — with preset 2 healthy to isolate them. Asserts:

```dart
expect(repo.savedPresetIds, [1, 3, 4, 5]);          // all four MUST be re-saved
for (final id in [1, 3, 4, 5]) {
  expect(repo.savedStates[id]?['on'], true);        // root master power asserted
  expect(repo.savedStates[id]?['ib'], true);        // ib is what persists root on/bri
}
expect(repo.savedStates[1]?['bri'], 200);           // brightness survives the repair
expect(repo.savedStates[3]?['bri'], 51);
expect(repo.savedStates[4]?['bri'], 102);
expect(repo.savedStates[5]?['bri'], 153);
```

Reinstate the name-only predicate and this fails immediately. The fixture block carries an in-code warning not to "fix" it — it is the defect, deliberately preserved.

---

## 2. PRE-FLIGHT — each verified, none assumed

### (1) Full test suite ✅

```
1834 passed · 3 skipped · 1 failed
```

**The 1 failure is pre-existing and unrelated** — `cloud_ai_processor_normalize_test.dart`
(*"garbage field values … → defaults, no throw"*). **Proven, not assumed:** I stashed my
change and re-ran that file — it still failed. It is the single documented pre-existing
failure in the ledger. **My change introduces zero failures.**

**The 3 skips are exactly the hardware tests**, and they skip without the define:

```
$ flutter test test/hardware/
00:06 +0 ~3: All tests skipped.
```

`kRunHw` is `bool.fromEnvironment('RUN_HW', defaultValue: false)`, so CI is unaffected.
(Note for whoever runs it: it needs `--dart-define=RUN_HW=true`; `=1` does **not** work,
`bool.fromEnvironment` only accepts `true`/`false`.)

### (2) Version: **2.5.10+59** ✅

**Convention, from `git log`:** this project holds the version *name* steady and increments
the *build number* per release — 2.5.10 has spanned +47 through +58, including functional
fixes. The closest precedent is exact: **`248a9bc chore(release): 2.5.10+50 — schedule
ON-presets assert master power (ib:true)`** — the original of this very fix, shipped as a
build-number bump.

**So a functional fix does not earn a version-name bump here; it earns +1 on the build
number.** `2.5.10+58` → **`2.5.10+59`**. versionCode 59 is also the next free Android code
(58 was consumed by the last build).

### (3) Production Firebase, no bench address ✅

```
lib/firebase_options.dart: projectId 'icrt6menwsv2d8all8oijs021b06s5'  ×3 (android/ios/web)
lib/app_providers.dart:17  kSimulationMode = false
```

**No hardcoded bench address in any release path.** `192.168.1.150` appears twice in `lib/`
and **both are `///` doc comments** citing bench provenance (`schedule_sync.dart:103`,
`sunrise_off_service.dart:250`) — zero occurrences in executable code. The other hits are in
`bench/` and `test/hardware/`, neither of which ships.

### (4) No debug paths or verbose/PII logging in release ✅

```dart
// lib/main.dart:128-130
if (kReleaseMode) { debugPrint = (String? message, {int? wrapWidth}) {}; }
```

All `debugPrint` output is nulled in release. My additions log only preset **IDs** via
`report.log` / `debugPrint` — no user data, no addresses, no credentials. Build ran with
`--obfuscate --split-debug-info`.

### (5) Diff review — one honest correction to the brief's description

**`schedule_sync.dart` is exactly as described: four predicate swaps + three additive
declarations.** Nothing crept in.

**`controller_defaults_healer.dart` is larger than that description, by design** — it is the
healer hook, which was the second half of the previous task's brief, not creep. It contains:

- the `(e2)` call site and `_healOnPresetMasterPower`;
- `onPresetsHealed` on the report;
- **settle + retry + final readback** — added because the live rig proved the first version
  wrong: four back-to-back `psave`s returned `ok=true` while **preset 4 read back with no root
  `on`**. A false-green flash write. A unit test would have passed it.

Nothing else is in the `lib/` diff. Total: **180 insertions / 7 deletions across 2 files.**

---

## 3. BUILD — Android

```
√ Built build\app\outputs\bundle\release\app-release.aab (65.0MB)
```

| | |
|---|---|
| **Artifact** | `build/app/outputs/bundle/release/app-release.aab` (68,206,827 bytes) |
| **versionCode** | **59** — read from the **merged manifest**, not pubspec |
| **versionName** | `2.5.10` |
| **package** | `com.nexgenled.lumina` |
| **Manifest path** | `build/app/intermediates/bundle_manifest/release/processApplicationManifestReleaseForBundle/AndroidManifest.xml` |
| **Symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — **archive these, never commit, never delete** |

Built with `--release --obfuscate --split-debug-info=build/debug-info/android`.

---

## 4. BUILD — iOS: how it is triggered

**Read `codemagic.yaml`: there is NO `triggering:` block.** The build is **not** started by a
branch push, tag, or PR. There is exactly one workflow, `ios-workflow`.

**It must be started by hand**, either:

- **Codemagic UI** → app → *Start new build* → workflow **`iOS Release`** → pick the branch; or
- **Codemagic REST API** — `POST https://api.codemagic.io/builds` with `{appId, workflowId: "ios-workflow", branch}` and an `x-auth-token` header.

### ⚠️ The iOS build number will NOT be 59

The pipeline **overwrites** the pubspec version before building:

```yaml
BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}
sed -i '' "s/^version: .*/version: ${VERSION_NAME}+${BUILD_NUM}/" pubspec.yaml
```

`PROJECT_BUILD_NUMBER` is **Codemagic's own counter**, so iOS ships as `2.5.10+<codemagic
counter>`. Only the *name* (`2.5.10`) is taken from pubspec. **Expect the iOS and Android build
numbers to differ — that is the existing design, not a fault.** Worth knowing when you match a
TestFlight build to this change.

The pipeline then handles signing (`app-store-connect fetch-signing-files`), pod install with a
full clean, `flutter build ipa`, and publishing.

---

## 5. UPLOAD — what the pipeline does vs. what you must do

**I uploaded nothing. I hold no App Store Connect, Codemagic, or Play credentials, and I did
not attempt to use any.**

### iOS → TestFlight

| Handled by the pipeline | You must do by hand |
|---|---|
| Code signing, pod install, IPA build | **Start the build** (§4 — no auto-trigger) |
| `submit_to_testflight: true` → uploads to TestFlight | **Confirm the `NexGen` App Store Connect integration is still authorised** in Codemagic — I cannot verify it |
| `expire_build_submitted_for_review: true` | **Distribution is INTERNAL only.** `codemagic.yaml` has no `beta_groups:` key, so nothing reaches external testers |

⚠️ **If you want the external-TestFlight Beta App Review rehearsal** recommended in
`LAUNCH_PLAN.md` §2A, that needs an external group configured in App Store Connect and either
a `beta_groups:` entry added to `codemagic.yaml` or a manual distribution from ASC. **The
current config cannot do it.**

### Android → Play **CLOSED** testing

**There is no Android CI** — `codemagic.yaml` defines only `ios-workflow`. Everything is manual:

1. Play Console → **Testing → Closed testing** → your existing track (**not** Internal — only
   closed counts toward the 12-tester × 14-day production-access requirement).
2. **Create new release** → upload `build/app/outputs/bundle/release/app-release.aab`.
3. Confirm the console shows **versionCode 59** and that it exceeds every previously uploaded
   code — **the console is authoritative**; my local read is only evidence the bundle is right.
4. Add release notes, review, **roll out to the closed track**.
5. Upload/retain `build/debug-info/android/*.symbols` for crash symbolication.

⚠️ **Uploading to Internal testing instead of Closed would not advance the 12-tester streak** —
that is the gate on Play production per `LAUNCH_PLAN.md` §2C.

---

## 6. SMOKE TEST — after install, in this order

**This is the first `lib/` change reaching testers and it touches the schedule sync path.** Run
**on LAN**, with a real controller — the healer is LAN-only by design.

**Before you start:** capture the baseline so you can prove the heal happened —
`curl http://<controller>/presets.json` and note whether presets 1/3/4/5 have a root `"on"`.

| # | Step | Expected | Why |
|---|---|---|---|
| 1 | Cold-launch the app on LAN, let it connect to the controller | App reaches the dashboard; no hang past the securestorage step | +55 shipped a dead splash — always check this first |
| 2 | **`curl /presets.json` — confirm presets 1/3/4/5 now have `"on": true`** with bri 200/51/102/153 | All four healed on first on-LAN connect | **THE headline assertion.** If this fails, stop and report |
| 3 | Re-launch and re-check | Same values, **no flashing on connect** | Heal is readback-gated; a second connect must write nothing. Flashing = it is re-saving every time |
| 4 | Set master OFF, then load preset 1 from the controller UI | Strip **lights up** | Functional proof the preset asserts master power |
| 5 | Create a schedule (ON 5 min ahead, OFF 10 min ahead), Sync | Save succeeds, no error banner | Core write path |
| 6 | Wait for the ON boundary | **Lights come on at the minute** | The end-to-end claim (R-1). This is the one that matters to a customer |
| 7 | Wait for the OFF boundary | Lights go off | OFF preset symmetry (preset 2) |
| 8 | Edit that schedule's time, Sync again | Change persists; strip not left in a wrong state | Edit path + non-disruptive restore |
| 9 | Delete the schedule, Sync | Timer removed; **no orphaned timer** in `/json/cfg` | Slot reclaim — known-weak area |
| 10 | **Calendar lease:** create a calendar entry, confirm it arms | Lease timer appears (macro 26-41); **schedule timers still present** | P0-3 merge behaviour — a lease must not clobber schedules, or vice versa |
| 11 | Re-run a schedule Sync with the lease active | Both lease and schedule timers survive | The clobber regression this codebase has hit before |
| 12 | Toggle the global sunrise-off on/off | Slot arms/disarms; other timers untouched | Reserved-slot handling |
| 13 | Check brightness presets 3/4/5 load at 51/102/153 | Correct brightness, lights on | Confirms `bri` survived the repair |

**Stop-and-report triggers:** step 2 fails · step 3 shows flashing on every connect · step 6
fires dark · step 10 or 11 loses timers.

---

## 7. NOT DONE — needs your decision

1. **Nothing is committed.** The change sits in the working tree (`lib/` ×2, `test/` ×2,
   `bench/` ×3, `docs/BUGS_AND_DEBT.md`, `pubspec.yaml`, plus untracked `audit/` and
   `test/hardware/`). I do not commit or push unless asked — say the word and I will, on a
   branch rather than straight to `main`.
2. **Nothing is uploaded.** §5 lists exactly what needs your hands.
3. **P3-56 remains open** — ON-preset definitions still live in two places
   (`kOnPresetSpecs` vs the inline literals in `syncAll`). Deliberate, logged, ~0.5h.
4. **The `layout drift` bench failure remains** — `known_layout.json` predates the `rev`/`pin`
   comparison. `probe --update` clears it once you have reviewed the values (notably
   `bus1.rev == true`).

### Rig state

Presets 1-5 all healthy (`on` true/false as intended, bri 200/255/51/102/153). Timers: lease
(macro 27) + sunrise-off + one sync-sim `4:20` fixture residue from the harness's
containment-only restore. `state: on=false, ps=-1`.
