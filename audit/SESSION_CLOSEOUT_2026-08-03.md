# SESSION CLOSEOUT — 2026-08-03 · 2.5.10+61

**Build:** `816aa1b` (merge `c5c7baf`, pushed to origin) · Android **versionCode 61**
**Nothing deployed. No flag created. No build uploaded.**

---

## 1. TREE STATE (as found, before any change)

`main`, **in sync with `origin/main`, nothing unpushed.** Seven modified `lib/` files, one
modified doc, seven untracked audit docs, one new test.

**Diff surface — the schedule-sync path, made explicit before shipping:**

```
 lib/features/schedule/schedule_sync.dart                    125 ++++++-   guard, refusedCount, abort msg
 lib/features/schedule/my_schedule_page.dart                 176 +++++++-  warning render, dialog, editor gate
 lib/features/autopilot/autopilot_providers.dart              85 ++++-     solar gate + clock sunrise fallback
 lib/lumina_ai/lumina_ai_service.dart                         25 ++-       chat() solar constraint
 lib/features/neighborhood/widgets/schedule_list.dart         21 ++-       sunset checkbox gate
 lib/features/commercial/events/create_event_screen.dart      18 ++-       clock fallback (activate + revert)
 lib/features/ai/lumina_brain.dart                            10 ++        pass the live flag
 lib/features/installer/staff_auth_telemetry.dart              2 +-        app_version bump
 docs/BUGS_AND_DEBT.md                                        57 +++       P0-9 logged
 pubspec.yaml                                                  2 +-        2.5.10+60 -> +61
 test/.../schedule_all_stub_clobber_guard_test.dart          214 +++       NEW, 11 cases
```

**`firestore.rules`, `firestore.indexes.json` and `functions/` are CLEAN** — no rules changes
stacked onto this build, as instructed.

**Two parallel-session artifacts, flagged rather than silently swept:**
- `audit/SOLAR_FAILURE.md` — the other window's analysis. **Committed**, because this build's docs
  and the memory index both reference it and leaving it untracked would orphan the citation.
- `audit/LEASE_LEDGER_MIGRATION.md` — appeared *during* the commit. **Deliberately NOT committed**;
  it is in-progress work from the other window and is still untracked on `main`.

---

## 2. PRE-FLIGHT (each verified, nothing assumed)

| # | Check | Result |
|---|---|---|
| 1 | Full suite | **1867 passed · 3 skipped · 1 failed** — exactly the expected baseline. Failure identified twice this session as the stale P1-8 `cloud_ai_processor_normalize`. Count matched, so no stash proof required |
| 2 | `flutter analyze`, all changed files | **0 errors, 0 warnings.** 15 info-level: 8 SDK deprecations, 6 `prefer_interpolation` in `lumina_ai_service` const concatenations, 1 pre-existing `foundation`/`material` overlap at `lumina_brain.dart:1` |
| 3 | Version bump | `pubspec.yaml` → `2.5.10+61`; `kStaffAuthTelemetryAppVersion` → `'2.5.10+61'` (**both** bumped — a stale constant makes the S-5 dealer-adoption query unreadable) |
| 4 | `kStaffTokenSafetyMargin` | `Duration(minutes: 50)` — real value, not `Duration.zero`. Swept for `TEMP`/`REVERT`/`DO NOT SHIP`/`XXX`/`Duration.zero`: all remaining hits are legitimate (accumulator inits, animation defaults, enum arms, UI placeholder strings) |
| 5 | Release config | Firebase `icrt6menwsv2d8all8oijs021b06s5` (production) · `kSimulationMode = false` · `debugPrint` nulled under `kReleaseMode` (`main.dart:129`) · **no bench address in any executable path** — all `192.168.1.150`/`.250` hits are `///` doc comments |
| 6 | Rules untouched | **Confirmed clean.** controller_ips change stays mid-soak and undeployed |

---

## 3. BUILD

**Android** — `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info/android`

- Artifact: `build/app/outputs/bundle/release/app-release.aab` · **68,237,215 bytes** · 2026-08-03 12:18
- **Baked versionCode: 61**, verified from the merged manifest
  (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`)
  — **not** from pubspec. versionName `2.5.10`, package `com.nexgenled.lumina`. No drift.
- Symbols: `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (12:17). Archive; never commit.
- **NOT uploaded.**

**iOS — exact trigger:** Codemagic → workflow **`ios-workflow`** ("iOS Release"),
**started manually from the Codemagic UI against branch `main` @ `c5c7baf`**.
`codemagic.yaml` has **no `triggering:` block** (re-verified this build), so there is no push- or
tag-based automation — someone must press Start. **Not attempted here.**

> **The iOS build number will NOT be 61.** `codemagic.yaml` overwrites pubspec's build number with
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}` before building; only the version *name*
> survives from the repo. **`816aa1b` / `c5c7baf` is the join key** between the Android
> `versionCode 61` and whatever number TestFlight shows.

`docs/BUILD_LEDGER.md` has a +61 row with the SHA, versionCode, `iOS PENDING`, and the join-key
caveat repeated.

---

## 4. WHAT SHIPS vs WHAT REMAINS OPEN

| Area | Ships in +61 | Still open |
|---|---|---|
| **Solar scheduling** | Failure is now **legible** — the composed per-schedule remedy renders instead of "1 warning". Spread is **stopped**: all five surfaces gated, autopilot emits clock times | **Solar still does not work.** `config/solar_scheduling` deliberately NOT created. Ellie, Tim Kelly and Chris Cipollone still need clock-time schedules to get lights back |
| **The flag flip** | — | **Gated on a solar comparator that does not exist.** `isRealEnabledTimer` excludes `hour == 255`, so a solar row verifies clean through `timersInsLanded` whether it landed correctly, landed wrong, or never landed. Do not flip before this exists |
| **All-stub clobber** | Guard shipped + bench-verified: known state survived byte-identical; the legitimate clearing write still lands | — |
| **Lease exposure (P0-9)** | Blast radius narrowed (all-refused case blocked) | **OPEN.** Leases occupy general slots 0-7; `macro 26-41` is a preset-id convention, not a slot reservation. Only a same-write merge from a **device-local SharedPreferences** ledger protects them. **Chris is exposed on reinstall, cleared cache, or a second device** — the guard does not catch it (payload has real timers, so it POSTs) |
| **Hardware verification** | — | **Still owed on +60 AND +61:** token refresh 4.2, commissioning a-d, Part B. Unchanged by this build |
| **controller_ips rules** | — | Steps 1-5 complete, **24h soak pending, rule NOT deployed.** Deploy order remains load-bearing: backfill → soak → rule |
| **P1-8 stale test** | — | Still red. It pins behavior `b6ca2f1` deliberately removed; should be **closed as stale**, not "fixed" |

---

## 5. IMMEDIATE ACTIONS FOR TYLER

1. **Upload the AAB** (versionCode 61) — not done here.
2. **Start `ios-workflow` manually** in Codemagic against `main` @ `c5c7baf`; record the returned
   build number in the ledger's `iOS PENDING` field.
3. **Contact the three customers.** Ellie and Tim: pressing Sync is safe but achieves nothing —
   the useful action is converting a schedule to a clock time (the editor now allows this in place,
   and their autopilot baseline must be switched off or it will regenerate solar labels).
   **Chris: still keep him off a home-LAN sync** until P0-9 is closed.
4. **Do not flip the solar flag** until the comparator exists.

---

## 6. SESSION AUDIT TRAIL (all committed in `816aa1b`)

```
audit/BLOCK_E_MISSING_ROW.md   why an AI-window schedule never reached the controller
audit/ELLIE_SUNSET.md          Ellie's sunset failure -> solar gate + the missing flag
audit/SOLAR_FIX_PLAN.md        flag located (nowhere), fix sequenced
audit/SOLAR_FIX.md             steps 1-3 implemented
audit/ALL_STUB_CLOBBER.md      clobber traced + bench-proven, verdict per customer
audit/ALL_STUB_GUARD.md        guard implemented, two self-inflicted bugs recorded
audit/SOLAR_FAILURE.md         parallel session's analysis (the ABORT-vs-CLOBBER correction)
```

**One correction worth carrying forward:** `ELLIE_SUNSET.md` §0/§2 originally claimed syncAll
*aborts* before writing. It does not — it **clobbers**. The parallel session caught it; the solar
gate `continue`s before `armable.add(s)`, so `armedSchedules` is empty and the empty-armed guard's
first conjunct is false. That correction is what produced this whole guard, and the affected
sections of `ELLIE_SUNSET.md` should be read alongside `SOLAR_FAILURE.md` and `ALL_STUB_CLOBBER.md`
rather than on their own.
