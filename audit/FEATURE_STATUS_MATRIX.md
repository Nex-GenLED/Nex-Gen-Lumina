# FEATURE STATUS MATRIX — Window A

**Scope:** functional completeness (exists vs. works) of user-facing and installer-facing features.
**Repo state:** `main` @ `393af46`, version `2.5.10+58`, working tree clean.
**Date:** 2026-07-30
**Out of scope (other windows):** Firestore rules/isolation (B), store config & manifests (B), build/branches/migrations (C).

> **COVERAGE HONESTY — READ FIRST.** This is a partial audit. The router exposes ~110
> registered routes; I traced roughly a third of them to device effect. Everything below
> is evidence-backed, but **absence from this document is not evidence of health.** The
> areas I did not reach are listed explicitly in §6. Do not read this as a clean bill for
> anything not named.

---

## 1. EXECUTIVE SUMMARY

### Counts by status (features assessed: 24)

| Status | Count |
|---|---|
| COMPLETE | 3 |
| NEAR-COMPLETE | 7 |
| PARTIAL | 5 |
| STUBBED | 4 |
| BROKEN | 2 |
| MISSING | 0 |
| UNVERIFIED (insufficient evidence) | 3 |

### Counts by severity

| Severity | Count |
|---|---|
| P0-BLOCK | 1 (F-5b) |
| P1-LAUNCH | 7 (+F-5a from the split) |
| P2-FOLLOW | 6 (F-7 → P3) |
| P3-DEBT | 6 |

> **REVISED 2026-07-30 (2) — beta-fleet facts.** Lumina has active beta users on both platforms:
> iOS via an established Codemagic → TestFlight pipeline ([codemagic.yaml:128-131](codemagic.yaml#L128-L131),
> **internal testers only**), Android via Play internal/closed testing. Two consequences for this
> document. **(a) The "UNVERIFIED" rows below are now testable rather than merely untested** — the
> Android beta fleet is a real verification environment for Design Studio, Neighborhood Sync, and
> Inventory, none of which any audit traced to device effect. **(b) The iOS fleet is staff-only**
> (internal TestFlight is capped at 100 App Store Connect team members), so it cannot serve that
> purpose and Lumina has never been through any Apple review. Verification planning lives in
> `audit/LAUNCH_PLAN.md` §2B and §3A; the status calls below are unchanged.
>
> **REVISED 2026-07-30 (1) — after Window B.** Three corrections applied: the account-deletion finding
> was **split** by arbitration into F-5b (P0, bridge orphan — my position upheld) and F-5a (P1,
> erasure gap — Window B's position upheld); **F-7's deep-link reachability claim is retracted**
> as false, re-tiering it P2 → P3; and **F-6 is re-costed 16h → 1h** because the screen has no
> entry vector, making "delete the route" the only sensible remediation. My F-5b remediation was
> also **wrong** and is corrected — resetting the registry doc does not reclaim the hardware.
> These counts cover Window A's charter only; Window B carries four further P0s
> (`audit/COMPLIANCE_AND_SECURITY.md` §3), consolidated in `audit/LAUNCH_PLAN.md` §2.

### The three things most likely to delay submission

1. **Account deletion is incomplete and strands hardware (P0).** Deleting an account
   removes only the `/users/{uid}` document. Every subcollection survives — including
   `properties` (home addresses) and `geofences` (home coordinates) — and the paired
   ESP32 bridge is left pointing at a dead UID with no recovery path short of a physical
   re-flash. This has already happened twice in production; the evidence is two customer
   UIDs hardcoded into the shipped ruleset as permanently blocked. See F-1.
2. **Schedules did not fire on the bench rig, reproducibly (P1).** Two independent
   `fire-test` runs armed a correct timer and the strip never powered on. This is the
   product's core promise. See F-2 and §5.
3. **A live orphaned timer is armed on the bench controller right now (P1).** Slot 3 holds
   `{"en":1,"hour":255,"min":0,"macro":0,"dow":127}` — enabled, every day, at a solar
   boundary, pointing at preset 0 (nothing). See F-3.

### Single biggest concern

**The bench harness regressed from a recorded 21/21 to 18/21, and the failure is schedule
firing.** Everything else in this document is a normal pre-launch defect list. This one
undercuts the thing the product is for. I could not attribute it to the app versus the
controller firmware from the host, and that attribution is the first thing that should
happen — it decides whether this is a code fix or a fleet/firmware problem. It is filed
P1 rather than P0 strictly because it is not approval-preventing, per the explicit
instruction that only approval-preventing items block submission. Treat it as the top
launch-readiness item regardless of tier.

---

## 2. FEATURE MATRIX

Audience: **C** = customer, **I** = installer/dealer/staff, **B** = both.

| Feature | Aud | Status | Sev | Est | Conf | Evidence | Remediation summary |
|---|---|---|---|---|---|---|---|
| Acct deletion — **F-5b** strands the bridge | C | **BROKEN** | **P0** | 4 + firmware | High | [main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220), [:1046](esp32-bridge/src/main.cpp#L1046), [firestore.rules:700](firestore.rules#L700) | **Cannot be closed pre-launch.** Mitigate only; real fix is firmware unpair |
| Acct deletion — **F-5a** erasure gap | C | **BROKEN** | P1 | 8 (−2 if bundled) | High | [user_service.dart:277-285](lib/services/user_service.dart#L277-L285), [security_settings_screen.dart:104-106](lib/features/site/security_settings_screen.dart#L104-L106) | Recursive cascade + fix delete-before-reauth ordering. **Must not ship before F-5b mitigation** |
| Schedule firing (device) | C | **BROKEN** | P1 | 8 | Low | bench `fire-test` ×2, §5 | Attribute app vs firmware first; do not code-fix blind |
| Orphaned timer slot (macro:0, en:1) | C | PARTIAL | P1 | 4 | Med | live `/json/cfg` readback, §5 | Make padding authoritative or actively clear trailing slots |
| Pixel-walk capture — interruption | I | PARTIAL | P1 | 8 | High | [map_roofline_step.dart:424-429](lib/features/installer/screens/map_roofline_step.dart#L424-L429) | Persist capture draft; add lifecycle observer |
| Pixel-walk capture — silent save failure | I | **BROKEN** | P1 | 2 | High | [map_roofline_step.dart:417](lib/features/installer/screens/map_roofline_step.dart#L417), [:426-428](lib/features/installer/screens/map_roofline_step.dart#L426-L428) | Check the return value; block advance on failure |
| Commercial Schedule screen | C | **STUBBED** | **P3** (v1) | **1** | High | [CommercialScheduleScreen.dart:1819](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1819), [:1850](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1850), [:2064](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L2064) | **Ships fast-follow, not v1.** Keep sealed + guard-list. 16h build-out moves to `LAUNCH_PLAN.md` §4A |
| Commercial Fleet dashboard | C | STUBBED | **P3** (v1) | 4 | High | [FleetDashboardScreen.dart:1041](lib/screens/commercial/fleet/FleetDashboardScreen.dart#L1041), [:1050](lib/screens/commercial/fleet/FleetDashboardScreen.dart#L1050) | Two dead nav targets — folded into the fast-follow build-out |
| Commercial mode (whole surface) | C | **UNVERIFIED** | **P3** (v1) | 12 (audit) | Low | [route_guards.dart:245-252](lib/route_guards.dart#L245-L252) | **Retirement REVERSED — it ships.** Surface was never traced; needs its own audit before release |
| Profile address → solar coords | C | PARTIAL | P2 | 2 | High | [edit_profile_screen.dart:205-222](lib/features/site/edit_profile_screen.dart#L205-L222) | Dead `loc` write + false success toast; fix the toast |
| Orphaned routes (7) | B | PARTIAL | P3 | 4 (class fix) | High | §4 F-7 **(RETRACTED IN PART)** | No entry vector — my deep-link claim was false. Architectural only |
| Schedule cfg write boundaries | C | **COMPLETE** | — | — | High | §3 F-2a | All 4 construction sites carry the guards |
| Reviewer / App Store demo path | C | COMPLETE | — | — | High | [reviewer_seed_service.dart:17-25](lib/services/reviewer_seed_service.dart#L17-L25) | Correctly wired across 5 call sites |
| First-run empty state (dashboard) | C | COMPLETE | — | — | High | [wled_dashboard_page.dart:197-224](lib/features/dashboard/wled_dashboard_page.dart#L197-L224) | Non-blocking banner; no dead-end |
| Error surfacing (raw exceptions) | B | NEAR-COMPLETE | P3 | 1 | High | §3 F-9 | Zero raw `$e` in UI; 108 silent catches is the residual |
| Push notifications (FCM) | C | NEAR-COMPLETE | P2 | 1 | Med | [main.dart:204](lib/main.dart#L204), [sync_notification_service.dart:169-184](lib/features/neighborhood/services/sync_notification_service.dart#L169-L184) | Wired; two services double-listen to the same tap event |
| Per-channel power (P1-43) | C | COMPLETE | — | — | High | bench 4/4 PASS, §5 | No action |
| WLED preset invariants | C | COMPLETE | — | — | High | bench 6/6 PASS, §5 | No action |
| `en` int/bool polarity guard | C | COMPLETE | — | — | High | bench `cfg-truth` PASS, §5 | Regression guard holding |
| Voice (Alexa / Google / Siri) | C | NEAR-COMPLETE | P2 | 4 | Low | [alexa_service.dart:51](lib/features/voice/alexa_service.dart#L51), [google_home_service.dart:50](lib/features/voice/google_home_service.dart#L50) | App reads `isLinked`; end-to-end unverifiable from repo |
| Global sunrise-off | C | NEAR-COMPLETE | P2 | 2 | Med | [sunrise_off_service.dart:154-200](lib/features/schedule/sunrise_off_service.dart#L154-L200) | Present on device (slot 2); bench-verify pending |
| Calendar lease pre-arm (P0-3) | C | NEAR-COMPLETE | — | — | Med | bench lease slots 26/28/41 intact | Guards present; slots verified untouched |
| Design Studio slices 0-5 | B | UNVERIFIED | — | — | Low | §6 | All files exist; not traced to device |
| Neighborhood Sync + fanout | C | UNVERIFIED | — | — | Low | §6 | Flag-gated; not traced |
| Inventory (~61 SKU) | I | UNVERIFIED | — | — | Low | §6 | Screens exist; Shippo integration is TODO |
| Autopilot | C | NEAR-COMPLETE | P2 | 2 | Low | [autopilot_weekly_preview.dart:252](lib/features/autopilot/autopilot_weekly_preview.dart#L252), [autopilot_scheduler.dart:751](lib/services/autopilot_scheduler.dart#L751) | Approval workflow + solar calc are TODO |

---

## 3. DETAILED FINDINGS

### F-1 — SUPERSEDED BY THE ARBITRATION SPLIT → see F-5b and F-5a below

*This finding merged two defects with different mechanisms, different tiers, and different
fixes. Window B's arbitration (`audit/COMPLIANCE_AND_SECURITY.md` §2.6(c)) split them and both
positions were upheld — mine on the bridge half, Window B's on the erasure half. The original
text is retained below for provenance; **the remediation in it is wrong** and is corrected in
F-5b.*

---

### F-5b — Account deletion strands the paired bridge irrecoverably — **P0-BLOCK** — 4h mitigation + firmware — High

**Status:** BROKEN · **Audience:** customer · **My P0 position, upheld in arbitration**

Deleting an account releases nothing on the hardware side. The pairing lives in two places,
neither touched: the bridge's NVS ([main.cpp:1234](esp32-bridge/src/main.cpp#L1234)) and
`/bridge_registry/{deviceId}`, which is `allow delete: if false`
([firestore.rules:700](firestore.rules#L700)).

**P0 justification:** a truck roll to recover installed customer hardware, triggered by a
supported in-app action. Realized twice — the two hardcoded blocked UIDs at
[firestore.rules:669-672](firestore.rules#L669-L672), one recorded as "physically unlocatable
at wipe time" ([:649-663](firestore.rules#L649-L663)).

#### CORRECTION — my original remediation does not work

I wrote that resetting the registry doc makes the hardware "reclaimable without a re-flash."
**That is false**, and Window B verified why against the firmware:

- `pollPairingRequest` returns early unless `currentStatus == "pairing"` —
  [main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220). **A paired bridge never polls
  for an unpair.**
- The bridge re-asserts `pairedUid` from NVS on **every heartbeat** —
  [main.cpp:1046](esp32-bridge/src/main.cpp#L1046). An Admin-SDK reset is overwritten within
  one beat.
- `prefs.clear()` exists at [main.cpp:507](esp32-bridge/src/main.cpp#L507) but is a local
  reset path, not remotely triggerable.

**The truck roll is a FIRMWARE limitation, not a backend one.** No backend change removes it.

#### Remediation — two items, only the second closes it

**(1) Pre-launch mitigation — 4h — Medium confidence.** Does *not* reclaim hardware; bounds the
damage and stops each deletion from minting a permanent rules liability.
- Admin-SDK cleanup on deletion: reset the registry doc **and** write the `deviceId` into a new
  Admin-SDK-only `blocked_bridges` collection.
- Swap the literal blocklist at [firestore.rules:669-672](firestore.rules#L669-L672) for
  `!exists(/databases/$(database)/documents/blocked_bridges/$(deviceId))` — one extra document
  read, well inside the 10-lookup budget. Without this, **every future orphan costs a rules
  edit plus a global production deploy** while the orphan writes freely.
- Add a warning on the deletion path: tell the user their bridge will require service before it
  can be reused, and queue the device for recovery.
- `/bridge_registry` keeps `allow delete: if false`; no client write path is added.

**(2) Post-launch firmware fix — OUTSIDE THE LAUNCH PATH — estimate deferred.** A paired bridge
polls for `status == 'unpaired'` and clears its own NVS, plus a fleet OTA to deliver it. Only
this makes the device self-reclaiming, retires the blocklist, and makes the two stranded units
recoverable. Requires firmware work and an OTA campaign — I have no basis to estimate either,
and neither belongs on the submission path.

**Do not remove the two blocked-UID entries until (2) ships.** The cleanup function alone does
not make those devices safe to unblock.

---

### F-5a — Account deletion does not delete the account's data — **P1-LAUNCH** — 8h (−2h bundled) — High

**Status:** BROKEN · **Audience:** customer · **Window B's P1 position, upheld in arbitration**

`deleteUser()` is a single `.doc(userId).delete()`
([user_service.dart:277-285](lib/services/user_service.dart#L277-L285)). Firestore does not
cascade. Everything under `/users/{uid}/` survives: `controllers`, `schedules`, `properties`,
`geofences` (home coordinates), `commands`, `designs`, `patterns`, `pixelMap`, `debug_errors`.
Storage `users/{uid}/house_photo.jpg` survives. `/installations` (with `address`, `city`,
`zipCode`) survives. So does `/referral_codes`, which is itself a UID-directory path.

**Two aggravators Window B found that I missed:**
1. **The published privacy policy commits to deletion within 30 days.** Nothing implements it.
   A published commitment the system does not fulfil is worse than silence.
2. **Ordering bug.** [security_settings_screen.dart:104-106](lib/features/site/security_settings_screen.dart#L104-L106)
   deletes the profile document *before* `user.delete()`, which throws `requires-recent-login`
   on any session older than ~5 minutes. The profile is already gone and the auth account still
   exists — the user is stranded signed-in with no profile and no way to finish. **A reviewer
   testing this on a warm session will very likely hit exactly this.**

**Why P1 not P0:** the in-app control exists and is reachable in three taps, which is what
5.1.1(v) tests and what a reviewer observes. The residue is server-side and invisible to review.

#### ⚠️ ORDERING CONSTRAINT — F-5a must not ship first

**Shipping the erasure cascade before F-5b's mitigation exists would deliberately increase the
orphan rate.** F-5a makes deletion *work properly*, which makes it more likely to be used —
and every use under today's firmware strands a bridge with no warning and no recovery queue.

Required sequence:
1. F-5b mitigation (cleanup function + `blocked_bridges` + **the user-facing deletion warning**)
2. *Then* F-5a cascade — sharing the same cleanup function, which is where the −2h comes from
3. F-5b part 2 (firmware) whenever it lands, independently

Do not reorder 1 and 2, and do not ship 2 alone.

---

### F-1 (original text, superseded — retained for provenance)

**Status:** BROKEN · **Audience:** customer

The UI path is correct: confirmation dialog, `requires-recent-login` handling, Firestore
delete, then Auth delete ([security_settings_screen.dart:100-107](lib/features/site/security_settings_screen.dart#L100-L107)).
The implementation underneath is not.

```dart
// lib/services/user_service.dart:277-285
Future<void> deleteUser(String userId) async {
  try {
    await _firestore.collection('users').doc(userId).delete();
  } ...
```

Deleting a Firestore document **does not delete its subcollections.** Everything under
`/users/{uid}/` survives the account deletion permanently:

| Subcollection | Contents | Rule reference |
|---|---|---|
| `properties` | Home addresses | `firestore.rules:483` |
| `geofences` | Home coordinates | `firestore.rules:468` |
| `controllers` | Device registry | `firestore.rules:378` |
| `schedules`, `commands`, `bridge_status`, `designs`, `patterns`, `favorites`, `ai_usage`, `pixelMap`, … | | various |

I confirmed no server-side cleanup exists — there is no `onDelete`, `beforeUserDeleted`,
`recursiveDelete`, or `auth.user()` trigger anywhere in `functions/`.

**Two distinct exposures:**

*(a) Incomplete deletion — App Store Guideline 5.1.1(v).* The guideline requires an app
that supports account creation to let the user "initiate deletion of their account **and
associated data**." Retaining home addresses and geofence coordinates after the user
deletes their account is incomplete deletion. The affordance exists, which is what a
reviewer clicks; the data retention is what fails the guideline's substance and any
GDPR/CCPA erasure request.

*(b) Hardware orphaning — proven twice, requires a truck roll.* The bridge pairing lives
in the bridge's own NVS and in `/bridge_registry`, neither of which the deletion touches.
`bridge_registry` is explicitly `allow delete: if false` (`firestore.rules:700`). A bridge
whose paired UID is deleted keeps heartbeating into a dead account with no in-app recovery.

This is not hypothetical. The shipped ruleset carries a hardcoded blocklist of two real
customer UIDs for exactly this reason (`firestore.rules:650-660`), with the comment:

> "Block their writes until each device is physically recovered and re-flashed … bridge
> physically unlocatable at wipe time"

**Why P0:** it meets the charter's own explicit criterion — orphaning that strands a
controller in an unrecoverable state requiring a truck roll — and it has a named
guideline (5.1.1(v)) plus a proven, twice-realized mechanism. This is the only P0 I am
assigning.

**Remediation.** Do this server-side; a client cannot be trusted to complete a multi-collection delete.
1. Add a callable/`beforeUserDeleted` Cloud Function in `functions/` that recursively
   deletes `/users/{uid}` and all subcollections (Admin SDK `firestore.recursiveDelete`).
2. In the same function, look up any `bridge_registry` doc with `pairedUid == uid` and
   reset it to `status: 'unpaired'`, clearing `pairedUid`, so the hardware is reclaimable
   without a re-flash.
3. Change [security_settings_screen.dart:104](lib/features/site/security_settings_screen.dart#L104)
   to await that function and only then call `user.delete()`.
4. Backfill: the two blocked UIDs in `firestore.rules:658-659` should be resolvable once
   step 2 exists.

**Dependency:** step 2 touches `bridge_registry` write rules — coordinate with Window B.

---

### F-2 — Schedule firing failed reproducibly on the bench rig — **P1-LAUNCH** — 8h — Low confidence

**Status:** BROKEN · **Audience:** customer

The bench harness's `fire-test` arms a scratch timer ~2 minutes ahead, sets master off,
and asserts the strip powers on at the minute. **It failed on two independent runs**
(11:32 and 11:39 CDT, 2026-07-30), each waiting ~4 minutes past the target:

```
FAIL: fire-test: strip powered on at the minute — post-fire /json/state on=false (want true)
```

I ruled out the two cheap explanations before filing this:

- **Not a `dow` bug.** The harness armed "dow bit 8". Today is Thursday; the mapping is
  Mon=0 ([bench_core.dart:213](bench/src/bench_core.dart#L213)), so Thursday = `1<<3` = 8.
  Correct.
- **Not a clock/timezone problem.** Live `/json/cfg` on the controller shows
  `ntp: {"en":true,"host":"time.google.com","tz":5,"offset":0,"ln":-94.2527,"lt":38.99346}`.
  `tz:5` is US-Central, matching host time (CDT), and coordinates are set.

**What I could not determine:** whether the fault is in the app's write path or in the
controller firmware. Two of the run's three failures were cfg **readback verification**
failures (`post=true, verified=false`) on the restore path, which suggests cfg writes are
returning 2xx without landing. If the scratch timer never actually persisted, it could not
fire — and the failure would be device-side, not a scheduling-logic bug.

Given the rig's documented history of LittleFS churn and settings reverting, device-side is
a live possibility. **Confidence is Low precisely on the attribution, not on the symptom** —
the symptom is confirmed twice.

**Prevalence — the question the bench structurally cannot answer.** This rig has a documented
history of flash-persistence problems, so N=1 cannot distinguish "one sick controller" from
"fleet-wide defect" — and that distinction is the difference between noise and a launch
stopper. **The Android beta fleet answers it for the cost of a message:** ask those users
whether their lights came on last night, over two overnight cycles. I assessed building real
telemetry and recommend against it pre-launch — the bridge heartbeat carries no controller
power state ([main.cpp:982-1000](esp32-bridge/src/main.cpp#L982-L1000)), so it would be 8h+ of
firmware plus an OTA to answer something asking resolves tonight. Reasoning in
`audit/LAUNCH_PLAN.md` §3A item 5.

**Remediation — attribution first, do not code-fix blind.**
1. Arm a single timer by raw `curl` (bypassing all app code), read `/json/cfg` back
   immediately, then again after 60s. If it does not persist → firmware/flash, and the app
   is exonerated.
2. If it persists but still does not fire → firmware timer evaluation; check against the
   0.15.1 pin.
3. Only if raw curl fires correctly does this become an app-path bug, at which point the
   `pushCfgWithVerify` path is the place to look.

Estimate covers attribution plus one round of fixing, and is soft until step 1 runs.

---

### F-2a — Schedule write boundaries: guards ARE complete — no finding

Charter 5a asked whether the schedule guards are present at *all* write boundaries or only
the patched ones. **I enumerated every timer-entry construction site and all four carry the
guards.** This is a clean result and I want it on record as such.

| # | Boundary | dow:0 refused | `en` is INT | Unparseable refused |
|---|---|---|---|---|
| 1 | [cfg_payload_builder.dart:130-197](lib/features/schedule/cfg_payload_builder.dart#L130-L197) (`buildCfgPayload`) | ✅ `:146` | ✅ `:106,120` | ✅ `:111-115` |
| 2 | [schedule_sync.dart:414-428](lib/features/schedule/schedule_sync.dart#L414-L428) (`buildSolarTimerEntry`) | ✅ at caller `:481` | ✅ `:423` | n/a (solar) |
| 3 | [calendar_entry_lease_manager.dart:1189-1211](lib/features/schedule/calendar_entry_lease_manager.dart#L1189-L1211) (lease) | ✅ `:1193` | ✅ `:1205` | n/a |
| 4 | [schedule_sync.dart:304-313](lib/features/schedule/schedule_sync.dart#L304-L313) (`_disabledTimerStub`) | intentional `dow:0` | ✅ `en:0` int | n/a |

The AI scheduling path does **not** constitute a fifth boundary — it produces
`ScheduleItem`s that flow through boundary 1, not raw cfg
([scheduling_intent.dart:15](lib/features/ai/scheduling_intent.dart#L15)).

**One latent landmine (P3).** `buildTimerEntry` still contains the known-wrong solar
encoding (`hour: 24`/`25`) at [cfg_payload_builder.dart:100-108](lib/features/schedule/cfg_payload_builder.dart#L100-L108).
It is currently unreachable — `buildCfgPayload` skips all solar labels before calling it —
so it is dead, not broken. But it is a correct-looking function that a future caller would
reasonably use, reintroducing the bug. Delete the branch or make it `assert(false)`.

---

### F-3 — Live orphaned timer on the controller — **P1-LAUNCH** — 4h — Medium

**Status:** PARTIAL · **Audience:** customer

Read-only `/json/cfg` on the bench controller, after the harness's own restore completed:

```
TIMER SLOTS PERSISTED: 4
 0 {"en":0,"hour":3,"min":33,"macro":1,"dow":2,...}
 1 {"en":1,"hour":4,"min":20,"macro":2,"dow":17,...}
 2 {"en":1,"hour":255,"min":0,"macro":2,"dow":127}    ← global sunrise-off, correct
 3 {"en":1,"hour":255,"min":0,"macro":0,"dow":127}    ← ORPHAN
```

**Slot 3 is enabled, fires every day (`dow:127`) at a solar boundary, and loads `macro: 0`
— no preset.** It is exactly the dead-slot class the schedule work has been chasing.

Secondary and possibly the cause: **the device persists 4 slots, but the app pads every
push to 8 (or 10 with solar).** [schedule_sync.dart:304-309](lib/features/schedule/schedule_sync.dart#L304-L309)
documents the padding as the mechanism that makes each sync "authoritative over all 8
slots" and prevents "the dow:0 orphan-accumulation bug". The device state says that
mechanism is not doing what the comment claims — either WLED compacts trailing entries, or
the padded writes are not landing (see F-2's readback failures).

If padding is being compacted away, the reclaim guarantee is void and orphans will keep
accumulating in the field.

**Remediation.**
1. Determine empirically whether WLED 0.15.1 trims trailing timer entries: POST a padded
   10-entry array by curl, read back, count.
2. If it trims: the reclaim strategy must change from "pad and overwrite" to explicitly
   writing `en:0` stubs into each previously-occupied index, tracked app-side.
3. Clear slot 3 on the bench rig.

**Dependency:** shares a root with F-2; do F-2 step 1 first, it answers both.

---

### F-4 — Pixel-walk capture: no interruption persistence — **P1-LAUNCH** — 8h — High

**Status:** PARTIAL · **Audience:** installer

Capture progress lives in `rooflineCaptureProvider`, an in-memory Riverpod provider. It is
written to Firestore **only** when the installer taps Continue:

```dart
// lib/features/installer/screens/map_roofline_step.dart:424-429
Future<void> _onContinue() async {
  await _restorePrior();
  // Auto-persist any mapped-but-unsaved channels so nothing is lost at handoff;
  await _saveMappedChannels();
  widget.onNext();
}
```

There is **no** `WidgetsBindingObserver`, no `didChangeAppLifecycleState`, no
`SharedPreferences` draft, and no periodic autosave anywhere in
[roofline_capture_logic.dart](lib/features/installer/map_roofline/roofline_capture_logic.dart)
or [map_roofline_step.dart](lib/features/installer/screens/map_roofline_step.dart). The
`_restorePrior()` calls restore the *WLED light state*, not capture progress.

Consequence: a phone call, a low-memory kill, or an OS eviction during a long walk discards
the entire capture. On a large roofline that is a return visit.

**Remediation.** Persist `rooflineCaptureProvider` to `SharedPreferences` on every mark
(it is a small structure); add a `WidgetsBindingObserver` that flushes on
`AppLifecycleState.paused`; offer "resume previous capture?" on wizard entry when a draft
exists. Files: `map_roofline_step.dart`, `roofline_capture_logic.dart`.

---

### F-5 — Pixel-walk save failure is silent and still advances — **P1-LAUNCH** — 2h — High

**Status:** BROKEN · **Audience:** installer

Distinct from F-4 and cheaper to fix. `_saveMappedChannels()` swallows every exception and
reports failure only through its return value:

```dart
// lib/features/installer/screens/map_roofline_step.dart:417
} catch (_) {
  return false;
}
```

`_onContinue()` **discards that return value** and calls `widget.onNext()` unconditionally
([:426-428](lib/features/installer/screens/map_roofline_step.dart#L426-L428)).

So if the Firestore write fails — offline van, permission-denied, transient — the installer
sees the wizard advance normally and has no signal that the pixel map was never saved. They
finish the job and leave. The loss is discovered later, by the customer.

This is worse than F-4: F-4 loses work visibly, this loses it invisibly.

**Remediation.** Have `_onContinue()` check the result; on false, show a blocking dialog
with Retry / Save-offline-and-continue, and do not call `onNext()` on an unacknowledged
failure. Log the exception rather than discarding it with `catch (_)`.

---

### F-6 — Commercial Schedule screen reports success it did not perform — **P2-FOLLOW** — 16h — High

**Status:** STUBBED · **Audience:** customer (currently unreachable in-app)

Three controls show a success message and then do nothing:

| Control | Message shown | Backing logic |
|---|---|---|
| Pause All | "All channels paused" | `// TODO: send pause command to all controllers` [:1819](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1819) |
| Run Default | "Running default: {id}" | `// TODO: push defaultAmbientDesignId to all active channels` [:1850](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1850) |
| Apply Override | "Override applied: {id}" | `// TODO: push override to controllers via WledService` [:2064](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L2064) |

Two further affordances are inert: day-part Edit pops the sheet and does nothing
([:984](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L984)), and drag-to-resize
shows an instructional snackbar for a gesture that is not implemented
([:1006](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1006)).

**Why P2 — and the reasoning is now stronger than when I filed it.** I originally rated this
P2 on "no in-app navigation, but direct-URL access survives." The direct-URL half was wrong
(see F-7 retraction): there is **no external entry vector at all**. Window B independently
confirmed the screens are unreachable and upgraded its own completeness row to a clean PASS on
that basis (`audit/COMPLIANCE_AND_SECURITY.md` §2.6(b) Q2b). A reviewer cannot reach these
controls by any means.

#### ⚠️ REMEDIATION CORRECTED — commercial mode SHIPS (Tyler, 2026-07-30)

**My "delete the route, ~1h" recommendation is withdrawn.** It assumed retirement, and the
decision is the opposite: **commercial mode ships as a fast-follow point release, not in v1.**
Deleting now would mean rebuilding later. My Q3 is answered — this is no longer an open
product question.

**v1 action — leave the code in place and confirm the seal.** ~1h:

1. **Leave commercial code untouched.** No deletion, no refactor.
2. **Confirm the route stays sealed** — no in-app navigation to `/commercial`
   ([route_guards.dart:245-252](lib/route_guards.dart#L245-L252)), and no deep-link path
   (Window B verified `flutter_deeplinking_enabled` and `FlutterDeepLinkingEnabled` absent on
   both platforms). This is a re-confirmation, not a re-derivation.
3. **Add `/commercial` and `/media` to the restricted list** at
   [route_guards.dart:54](lib/route_guards.dart#L54) as defense-in-depth. The list is a
   prefix match — `const restricted = ['/installer', '/sales', '/admin', '/dealer']` — so both
   are one-line additions. `/media` is included per my own F-7 / Window B's F-25 class finding.
   Verify the demo-browsing flow still behaves, since this list is what gates it.

**Re-tiered for v1: P2 → P3.** With the code shipping later and the route sealed *and*
guard-listed, there is no v1 exposure. The real work moves to the fast-follow item below.

#### ⚠️ ORDERING CONSTRAINT — handlers before entry vector

Same pattern as F-5a/F-5b. **The three TODO-backed controls at
[CommercialScheduleScreen.dart:1819](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1819),
[:1850](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1850) and
[:2064](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L2064) are safe only
while unreachable.** Each reports success — "All channels paused", "Running default",
"Override applied" — and performs no write.

**They must be implemented BEFORE any entry vector to `/commercial` lands.** An entry vector
means any of: in-app navigation added, `/commercial` removed from the restricted list,
`flutter_deeplinking_enabled` turned on, or the commercial-mode redirect restored.

**This is a gate on the fast-follow release, not on v1.** If an entry vector ships first, three
false-success controls become reachable and it is a Guideline 2.1 finding on that release.

**Fast-follow work item: see `audit/LAUNCH_PLAN.md` §4A.**

---

### F-7 — Seven orphaned routes — **P2-FOLLOW** — 2h — High

**Status:** PARTIAL · **Audience:** both

Registered in the router, zero navigation from anywhere in `lib/` — verified both by
`AppRoutes.*` symbol reference and by literal path string:

| Route | Path |
|---|---|
| `commercialOnboarding` | `/commercial/onboarding` |
| `currentColors` | `/settings/current-colors` |
| `dealerPayouts` | `/dealer/payouts` |
| `firstWeekReveal` | `/autopilot/first-week` |
| `mediaLanding` | `/media` |
| `systemDeactivated` | `/system-deactivated` |
| `zoneSetup` | `/installer/zone-setup` |

`systemDeactivated` is the notable one: a "your system is deactivated" screen exists but
nothing routes to it, so whatever condition it was built to explain currently surfaces some
other way — or not at all.

#### ⚠️ RETRACTION — my deep-link reachability claim was false

I wrote that these "remain reachable via the `lumina://` URL scheme, which is registered with
`autoVerify` on Android. Not a reviewer path, but not sealed either." **That is wrong.** Window B
repeated it from me before checking, then verified it and retracted
(`audit/COMPLIANCE_AND_SECURITY.md` §2.6(b) Q2d). Three facts:

1. **Deep links never reach GoRouter.** [deep_link_service.dart:59-90](lib/features/voice/deep_link_service.dart#L59-L90)
   switches the first path segment against a closed allow-list (`power`, `brightness`, `scene`, …)
   and returns `null` for anything unmatched. It never hands a path to the router.
2. **Flutter's automatic deep-linking is off on both platforms.** `flutter_deeplinking_enabled`
   is absent from the Android manifest and `FlutterDeepLinkingEnabled` is absent from Info.plist.
3. **The `autoVerify="true"` I cited is inert.** [AndroidManifest.xml:107](android/app/src/main/AndroidManifest.xml#L107)
   — `autoVerify` applies only to `http`/`https` App Links, not to a custom `lumina` scheme. It
   grants nothing here.

Combined with "nothing in `lib/` navigates to them," **the orphaned routes are unreachable at
runtime by any means.** I should have verified the mechanism before asserting reachability;
asserting it also propagated the error into Window B's report.

**Re-tiered P2 → P3.** No live exposure. The residue is architectural: the router grants by
default ([route_guards.dart:294-296](lib/route_guards.dart#L294-L296)), so new routes inherit
"allow" and the only backstop is the rules layer.

**Remediation — class fix, not per-route.** Add `/commercial` + `/media` to the restricted list
at [route_guards.dart:54](lib/route_guards.dart#L54), add a `/dealer` prefix check beside
`isInstallerRoute`/`isSalesRoute`, and make unknown prefixes deny-by-default. **4h for the class,
versus ~1h × 7 for the instances** — cheaper *and* it changes the default from allow to deny,
which is the actual defect. Point release, not a launch gate.

---

### F-8 — Profile address change: dead cfg write + false success toast — **P2-FOLLOW** — 2h — High

**Status:** PARTIAL · **Audience:** customer

The code is honest with itself and dishonest with the user. The FIXME is explicit:

```dart
// lib/features/site/edit_profile_screen.dart:205-211
// FIXME(coords): `loc` is NOT a WLED cfg key — WLED stores latitude/
// longitude at if.ntp.lt / if.ntp.ln ... So this push has always been a no-op,
// on LAN too; it is the on-connect healer's coordHealPayload() that actually
// sets coordinates.
```

and the write still happens at [:221](lib/features/site/edit_profile_screen.dart#L221).
Regardless of outcome, the user is then shown:

> **"Profile Updated & Solar Sync Complete."** ([:237](lib/features/site/edit_profile_screen.dart#L237))

Solar sync did not complete; nothing was synced. Coordinates do get set eventually by the
on-connect healer — I confirmed the bench controller has correct `lt`/`ln` — so the feature
is not broken end-to-end, but the confirmation is premature and wrong when the user is
off-LAN or the healer has not yet run.

**Remediation.** Cheapest correct fix: drop the dead `applyConfig({'loc': …})` call and
change the toast to "Profile updated — lighting location will sync on next connection."
Rewiring to `if.ntp.lt`/`ln` is the larger change the FIXME correctly defers.

---

### F-9 — Error-handling posture — **P3-DEBT** — 1h — High

Two observations, one good, one not.

**Good:** I found **zero** instances of a raw exception string rendered into the UI (no
`Text('… $e')` patterns anywhere in `lib/`). Charter 5c's raw-Firestore-path-leak concern
does not apply — error copy is written by hand throughout. The account-deletion screen even
distinguishes `requires-recent-login` from generic failure
([security_settings_screen.dart:110-115](lib/features/site/security_settings_screen.dart#L110-L115)).

**Not good:** **108 silent empty catch blocks** across `lib/`. Most are defensible
best-effort paths, but F-5 shows the pattern hiding a real data-loss bug. Not worth a
blanket sweep before launch; worth a rule that catches on *write* paths must surface.

---

## 4. BENCH HARNESS RESULTS (Step 6)

**Command:** `dart run bench/bin/bench.dart all`
**Controller:** 192.168.1.150 — WLED `0.15.1`, vid `2507300`, ESP32_Ethernet, 290 LEDs, RGBW. Reachable and healthy.
**Result: 18/21 passed — a regression from the recorded 21/21 (2026-07-24).**

| Group | Result |
|---|---|
| `probe` / `snapshot` | PASS — 2 timers, 11 presets captured |
| `cfg-truth` (en int/bool) | PASS — `en:1`→1, `en:true`→0. Regression guard holding |
| `preset-verify` | PASS 6/6 — ON-presets 1/3/4/5 assert power, OFF preset 2 reads off, all slots ≤250, lease slots 26/28/41 intact |
| `sync-sim` | PASS on landing (`timersInsLanded`, 1 post, no stall) |
| `sync-sim restore` | **FAIL** — `post=true, verified=false (20s)` |
| `fire-test` | **FAIL** — `post-fire /json/state on=false (want true)` |
| `channel-power` (P1-43) | PASS 4/4 — all four payload shapes correct |
| `restore` | **FAIL** — `post=true, verified=false (20s)` |

**Confirmatory re-run:** `fire-test` alone → **FAIL again** (1/2 checks, `DART_EXIT=1`).
The failure is reproducible, not a flake.

Notes:
- Two of three failures are cfg **readback verification** on restore — writes return 2xx
  without confirming. Likely a shared root with the `fire-test` failure (F-2, F-3).
- `preset-verify` reported `app-managed schedule slots present (10-25): []` — no app
  schedule presets on the rig at audit time, which is consistent with an idle bench.
- The harness left the rig in a mutated state: its own restore steps failed twice. **The
  bench controller currently holds the orphaned slot-3 timer described in F-3** and should
  be cleaned up before the next verification session.

---

## 5. WHAT I DID NOT COVER

Stated plainly so this is not mistaken for a full pass. Roughly two-thirds of the ~110
registered routes were not traced to device effect. Specifically **not** audited:

> **There is now a cheaper way to close most of this than a tracing session.** The Android beta
> fleet has been running real builds against real hardware. **Ask those users which of the
> features below they have actually used and whether they worked.** Real usage is evidence no
> amount of code-reading produces, and it costs a message rather than days. Bundle it with the
> schedule-firing ask in `audit/LAUNCH_PLAN.md` §3A item 5. Caveat: the **iOS** fleet is
> internal/staff-only and cannot serve this purpose. If the Android fleet turns out to be a
> handful of staff accounts too (question B-1), this shortcut evaporates and the gaps below
> stand as written.

- **Design Studio slices 0-5** — all files present (`manual_editor/`, `smart_presets/`,
  `refine/`, `pixel_design_document.dart`, `pixelMap` models) and the structure matches the
  seed list, but I traced none of them UI→device. The seed list's six slices are
  **unverified**, not confirmed.
- **Neighborhood Sync + crew fanout** — flag-gated; not exercised.
- **Inventory (~61 SKU)** — screens exist; I did not confirm the SKU count or the ordering
  path. Shippo integration is an explicit TODO at
  [order_screen.dart:782](lib/features/inventory/dealer/order_screen.dart#L782) and
  [corporate_orders_screen.dart:1005](lib/features/inventory/corporate/corporate_orders_screen.dart#L1005).
- **Clock-health evaluator** (CLOCK_UNSET / TZ_SUSPECT / LOCATION_UNSET) and the defaults
  self-healer — `clock_health.dart` read only for its cfg-key documentation. The healer is
  what makes F-8 non-broken, so it deserves its own verification.
- **Remote mode / queue backpressure** — `cloud_relay_repository.dart` referenced only.
- **Multi-property / multi-controller management**, **dealer & admin surfaces**,
  **Commercial Brand & Events / Brandfetch**, **Autopilot** beyond its TODOs,
  **offline/local-network fallback**.
- **Empty/first-run state on screens other than the dashboard.** I verified the dashboard
  handles zero controllers correctly; I did **not** walk every screen in that state, which
  is what charter 5b actually asked for. This is the largest single gap and the one I would
  close first.

---

## 6. OPEN QUESTIONS FOR TYLER

1. **F-2 attribution.** Has `fire-test` passed on this rig since 2026-07-24? If it has, what
   changed in between — app, firmware, or a manual config edit? If it has *not* been run
   since, the 21/21 record may predate the regression and the search window is much wider.
   This single answer changes the estimate more than anything else in the document.

2. ~~**F-1 severity.**~~ **RESOLVED — no longer needs your arbitration.** Window B and I
   converged: the finding was two defects, not one, and the split
   (`audit/COMPLIANCE_AND_SECURITY.md` §2.6(c)) upholds **both** positions —
   **F-5b P0** (bridge orphan, my position) and **F-5a P1** (erasure gap, Window B's). Nothing
   left to decide here.
   **What replaces it as a decision for you:** F-5b **cannot be closed before launch** — the
   truck roll is a firmware limitation ([main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220),
   [:1046](esp32-bridge/src/main.cpp#L1046)), not a backend one, so pre-launch work can only
   mitigate it. Accepting a P0 that ships open, mitigated rather than fixed, is a call only you
   can make. See `audit/LAUNCH_PLAN.md` §2 for how it is carried forward.

3. **Commercial mode disposition (F-6).** Is Phase 6 retirement still the plan? If yes,
   deleting the route is ~1h and removes a 16h remediation and a false-success surface. If
   commercial is shipping in some form, F-6 needs real work and should be re-tiered.

4. **Slot padding (F-3).** Was the "pad to 8/10 makes each sync authoritative" behavior ever
   verified on-device, or was it reasoned from the WLED docs? The live rig shows 4 persisted
   slots, which contradicts the comment. If it was never device-verified, the orphan
   accumulation guard has never worked.

5. **`buildTimerEntry`'s 24/25 solar branch.** It is currently dead code. Do you want it
   deleted, or is it staged for a future solar-offset feature? Leaving a
   correct-looking-but-known-wrong encoding in a shared builder is how it gets called again.

6. **Silent-catch policy (F-9).** 108 of them. Want a lint rule for write paths, or leave
   it as debt and fix opportunistically?

7. **Bench rig cleanup.** The harness's restore failed twice and left slot 3 orphaned. Want
   me to leave it as-is as evidence for F-3, or is someone clearing it before the next run?
   I left it untouched (read-only audit).
