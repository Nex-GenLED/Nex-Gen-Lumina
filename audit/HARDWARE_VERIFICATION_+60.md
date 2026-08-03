# Hardware verification — 2.5.10+60 · **still owed at +61 and +62**

> ### ⚠ CARRIED FORWARD — NOTHING IN THIS FILE HAS BEEN RUN
>
> **Status at 2026-08-03: every row in the checklist below is still blank.** Two further builds
> have shipped on top of +60 without discharging any of it:
>
> | Build | SHA | Added | Hardware debt discharged |
> |---|---|---|---|
> | `2.5.10+60` | `d92262f` | commissioning silent-failure closeout | none — this file is its debt |
> | `2.5.10+61` | `816aa1b` | solar legibility + all-stub clobber guard | none |
> | `2.5.10+62` | `306f3d2` | P0-9a tri-state lease gate | none *(its own bench work is separate — see below)* |
>
> **+62 must NOT go to EXTERNAL TestFlight until this session passes.** Internal TestFlight and
> the Play closed track are fine — the point of those is to get it onto a handset so this run can
> happen. External distribution is what the gate is for.
>
> **What +62 DID verify on hardware, and what it did not.** `audit/LEASE_TRISTATE.md` §3 is a real
> end-to-end bench run against `192.168.1.150` — but it drove `syncAll` from a `flutter test`
> harness on the laptop, **not from the app on a handset**. It therefore discharges nothing in the
> checklist below, all of which requires the installed APK, the wizard, and a signed-in staff
> session. Do not let "+62 was bench-verified" be mistaken for "+62 was device-verified".
>
> Three separate reports feed this run; none of them can be closed from a desk.

**One session. One rig. Two app installs.** This consolidates every hardware debt owed across
three reports into a single ordered run:

| Source | Owed |
|---|---|
| `audit/TOKEN_REFRESH_REPORT.md` §4.2 | 3 scenarios — token expiry → refresh, refresh failure → retry, fallback unreachable |
| `audit/COMMISSIONING_FIXES.md` §"Hardware ❌" | a–d — capture persists, save-gate blocks, customer gets controllers + pixelMap, staff uid drained |
| `audit/VERIFICATION_REPORT.md` §4 | Part B — Design Studio slices 0–5 with LEDs observed, incl. the save-gate failure case |

**Rig:** controller `192.168.1.150`, WLED 0.15.1, 290 LEDs (ch1=128 / ch2=162).
**Package:** `com.nexgenled.lumina`. **Installer PIN:** `0101` (dealer 01 / installer 01).
**Do NOT use master PIN `55xx`** — the wizard refuses it for customer installs (`68e5f04`),
which is correct behaviour and will just waste a run.

> **Why the order is what it is.** The expensive things are *rig resets* (re-adding a
> controller under the staff uid after a completed install migrates it away) and *phone
> reinstalls*. Block 1 folds **six** separate owed checks into **one** wizard run, because
> each of them happens at a different point of the same run and none consumes the others.
> Part B then reuses the customer account Block 1 just created, so no reset. Only Block 3
> needs a second (instrumented) build.

**Keep a log running for the whole session:**

```bash
adb logcat -c && adb logcat | grep -E "Installer:|MapRoofline:|StaffAuthTelemetry:|LUMINA_STARTUP"
```

Everything below prints to that stream. Capture it — it is the evidence for most steps.

---

## Block 0 — Prep (10 min, strip not needed)

| # | Step | Record |
|---|---|---|
| 0.1 | Confirm rig reachable: `curl -s http://192.168.1.150/json/info \| head -c 200` | `ver` = `0.15.1` |
| 0.2 | Confirm the controller is **not** already migrated to a customer — it must sit under the staff uid or be freshly added in 1.1 | — |
| 0.3 | Install the **+60** release build (§"Artifact" in `docs/BUILD_LEDGER.md`). **Fresh install, not an upgrade** — the telemetry device-id is created on first use | — |
| 0.4 | Baseline the telemetry sink so you can tell new rows from old: Firestore → `demo_analytics` → filter `event_type == installer_anon_fallback`, then again for `installer_commissioning_failure`. **Note both counts.** | counts before |

⚠ **Do not skip 0.4.** Steps 1.9 and 3.2 are "did a row appear" checks and are meaningless
without the before-count.

---

## Block 1 — The wizard run (≈75 min, mostly idle waiting; strip in view for 1.2)

**One continuous run.** Do not force-close the app anywhere in this block — step 1.4
specifically tests surviving *backgrounding*, and a force-close would destroy the wizard state
and invalidate 1.5.

### 1.1 — Start the install
Staff PIN `0101` → new customer (use a **fresh email you control**) → add controller
`192.168.1.150` → proceed to **Map Roofline**.

### 1.2 — 🔦 STRIP IN VIEW — capture, and confirm Slice 0 while you are here
Walk the channel. As you step the cursor:

- **exactly one LED is lit at a time, and it is the one the UI claims** ← this is **Part B
  slice 0**, and it is the one thing no API can verify (`/json/state` exposes no pixel buffer)
- drop marks at the corners/peaks
- **known issue to watch for:** channel-doubling — if stepping channel 1 also lights a pixel on
  channel 2, record it, it is a real defect and this is the run that would catch it

**Records:** ✅/❌ single-pixel addressing · ✅/❌ correct pixel · channel-doubling seen? ·
photo/video if anything is off.

### 1.3 — 🚫 SAVE-GATE FAILURE — *commissioning (b)*, and Part B's highest-value item
With marks captured and **before** tapping Continue: **turn on airplane mode.** Tap **Continue**.

| Expect | Fail = |
|---|---|
| Dialog **"Roofline map didn't save"**, naming the cause | silent advance — the original F-5 defect |
| The wizard **does NOT advance** past Map Roofline | advancing is the defect |
| Log: `MapRoofline: pixel-map save FAILED for uid=… controller=…` | a bare `catch (_)` would print nothing |

Then: **airplane mode off** → tap **Retry** → save succeeds → wizard advances.
Also tap **Close** once first if you want to confirm it leaves you on the step (it must not
advance either).

**Records:** dialog seen ✅/❌ · advanced-on-failure ✅/❌ (must be ❌) · Retry recovered ✅/❌.

### 1.4 — ⏳ THE WAIT — token-refresh scenario 1 setup
**Background the app** (home button — *not* force-close, *not* swipe-away). Let the phone
sleep. **Wait ≥ 55 minutes.**

This is the whole point: the staff custom token has a **1-hour TTL**, and this proves the
refresh survives backgrounding rather than depending on a timer that iOS/Android suspends.
Use the time for a break — the phone must be left alone.

> Impatient alternative: Block 3's instrumented build sets `kStaffTokenSafetyMargin` to
> `Duration.zero`, forcing a re-mint on every install. That proves the *re-mint*, **not** that
> it survives an hour asleep. Do the real wait at least once.

### 1.5 — Return, and test the pre-flight failure — *token-refresh scenario 2*
Wake the phone, return to the app (it should still be on Handoff). **Turn airplane mode ON.**
Tap **Complete Setup**.

| Expect | Notes |
|---|---|
| Error naming the cause, and stating **"Nothing was created — no customer account was made."** | this runs *before* any Firebase write, so aborting is free |
| Wizard does **not** advance | |
| **No customer account exists** — the email is still unused | this is the claim being tested |

**Records:** message seen ✅/❌ · exact wording of the cause.

### 1.6 — Complete for real — *token-refresh scenario 1 result*
**Airplane mode OFF.** Tap **Complete Setup**.

| Expect in the log | Meaning |
|---|---|
| `Installer: cached staff token past safety margin — re-minting before exchange` | the >50 min wait was detected |
| `Installer: staff token RE-MINTED and claims restored` | **the fix working** |
| `Installer: controller migration OK — ControllerMigrationResult(1 controller(s), N pixelMap doc(s))` | P0-6 success path |
| **No** `Installer: staff-claim restore FAILED` | | 

Install completes → handoff screen with credentials.

### 1.7 — *commissioning (c)* — the customer actually got everything
This is the P0-5 path that previously denied. Read-only REST (same method as
`audit/P0-5_EXPOSURE.md`):

```bash
TOKEN=$(gcloud auth application-default print-access-token)
B="https://firestore.googleapis.com/v1/projects/icrt6menwsv2d8all8oijs021b06s5/databases/(default)/documents"
curl -s -H "Authorization: Bearer $TOKEN" "$B/users/<CUSTOMER_UID>/controllers"
curl -s -H "Authorization: Bearer $TOKEN" "$B/users/<CUSTOMER_UID>/controllers/<CID>/pixelMap"
```

**Must show:** ≥1 controller **AND** the pixelMap channel docs. Controllers-without-pixelMap
means the migration partially ran, which the batch should make impossible — record it loudly.

### 1.8 — *commissioning (d)* — nothing orphaned
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}' "$B/users/staff_installer_0101:listCollectionIds"
curl -s -H "Authorization: Bearer $TOKEN" "$B/users/staff_installer_0101/controllers"
```

**Must be empty.** ⚠ **Expected pre-existing noise:** `staff_installer_5502` still holds 1
orphaned controller + pixelMap from 2026-07-27. That is the master-PIN refusal, **not** a
failure of this build — do not chase it. Only `staff_installer_0101` matters here.

### 1.9 — *token-refresh scenario 3a* — the fallback did not fire
Re-run the 0.4 queries. **Both counts must be unchanged.** A new `installer_anon_fallback` row
on a happy-path install means the refresh did not do its job. A new
`installer_commissioning_failure` row means the migration retried.

**Records:** anon_fallback Δ = ___ (must be 0) · commissioning_failure Δ = ___ (0 unless 1.3
counted).

---

## Block 2 — Part B, remaining slices (≈60–90 min, 🔦 STRIP IN VIEW throughout)

Uses the customer account from Block 1 — **no rig reset, no reinstall.** Sign in as the
customer (temp password / reset link from the handoff screen).

| Slice | What it is | Verify by eye | ✅/❌ |
|---|---|---|---|
| **0** | per-pixel `i` write path | *already done in 1.2* — carry the result forward | |
| **1** | data model: per-controller pixelMap, counts seeded from `WledLedBus.len` | channel lengths in the app match the rig (ch1 **128**, ch2 **162**, total **290**). A mismatch here is the versioning/staleness path | |
| **2** | capture flow | *already done in 1.2–1.3* — carry forward | |
| **3** | first consumer: smart presets | apply a smart preset → the segments light **in the mapped positions**, not raw indices | |
| **4** | editor / painting | paint a selection in the manual editor → **the LEDs you painted light, and only those**. Test undo/redo. `maxseg` is **32** — a design needing more segments is the known animation ceiling | |
| **5** | customer refine | nudge a boundary → the lit region shifts by the expected number of pixels; proportional rescale keeps the shape | |

**Force-close the app between slice 3 and slice 4** — this is the one place a cold start is
worth testing, since apply-then-reopen is where a "looks right until you restart" persistence
bug would surface (`Slice 3+ persistence` is explicitly out of Slice-0 scope per the audit).

**Records per slice:** what you did → what the strip did → photo/video for anything wrong.

---

## Block 3 — Instrumented build (≈20 min, strip not needed)

**Requires a second install.** Left to last so Blocks 1–2 run on the exact artifact that ships.

### 3.1 — Build it
Two temporary edits, both in `lib/features/installer/`:

```dart
// installer_setup_wizard.dart — force the re-mint path every time
const Duration kStaffTokenSafetyMargin = Duration.zero;

// installer_setup_wizard.dart — force the refresh to fail, in _refreshStaffToken
_lastRefreshFailure = 'forced_test_failure';
return null;   // as the first statement of the method body
```

Build + install. **This build must never be uploaded anywhere.**

### 3.2 — *token-refresh scenario 3b* — the fallback records correctly
Run an install to the point of Complete Setup.

| Expect | |
|---|---|
| Pre-flight error naming `forced_test_failure`, nothing created | the failure path |
| **A new `installer_anon_fallback` row** in `demo_analytics` | this is what S-5 counts |
| Row fields correct: `stage`, `device_id` (matches Block 1's device), `app_version` **`2.5.10+60`**, `dealer_code` `01`, `installer_code` `01` | |

⚠ **`app_version` is the field the D4 adoption gate reads.** If it does not say `2.5.10+60`,
`kStaffAuthTelemetryAppVersion` drifted from pubspec (**P3-60**) and the whole adoption metric
is unreadable — that is a stop-and-fix, not a note.

### 3.3 — Restore
`git checkout lib/features/installer/installer_setup_wizard.dart`, confirm
`kStaffTokenSafetyMargin` is back to `Duration(minutes: 50)`, and **reinstall the real +60
build** before doing anything else with the phone.

---

## Summary sheet

| Debt | Step | Result |
|---|---|---|
| Token refresh 4.2 #1 — expiry → refresh → write lands | 1.4 + 1.6 | |
| Token refresh 4.2 #2 — refresh failure visible + retry | 1.5 (+1.3 for the retry UX) | |
| Token refresh 4.2 #3a — fallback unreachable on happy path | 1.9 | |
| Token refresh 4.2 #3b — fallback records correctly when forced | 3.2 | |
| Commissioning (a) — capture completes and persists | 1.2 + 1.3 | |
| Commissioning (b) — save failure blocks, does not advance | 1.3 | |
| Commissioning (c) — customer ends with controllers **and** pixelMap | 1.7 | |
| Commissioning (d) — nothing orphaned under staff uid | 1.8 | |
| Part B slice 0 — single-pixel addressing | 1.2 | |
| Part B slice 1 — data model / channel counts | 2 | |
| Part B slice 2 — capture flow | 1.2–1.3 | |
| Part B slice 3 — smart presets | 2 | |
| Part B slice 4 — editor / painting | 2 | |
| Part B slice 5 — customer refine | 2 | |

**Not covered by this session, and not claimed:** P0-6's Retry/Stop **dialog** is only reached
if the migration genuinely fails, which Block 1 will not reproduce on a healthy network. To
exercise it you would have to force a migration denial (e.g. an instrumented build that throws
in the batch commit). The P0-6 unit tests cover the mechanism; the dialog itself stays
unverified on device — see `audit/P0-6_FIX.md` §"Honest gap".
