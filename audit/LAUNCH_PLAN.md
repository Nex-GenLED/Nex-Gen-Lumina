# LAUNCH PLAN — Lumina 2.5.10+58

**Consolidated from:** `audit/FEATURE_STATUS_MATRIX.md` (A), `audit/COMPLIANCE_AND_SECURITY.md` (B), `audit/RELEASE_READINESS.md` (C).
**Repo:** `main` @ `393af46`, `2.5.10+58`, working tree clean.
**Date:** Thursday 2026-07-30. **Revision 4** — Play prerequisite answered. **iOS is the launch platform; Android is a follow-on.**

---

## 0. THE SHAPE OF THIS PLAN CHANGED

**Play production is blocked by a calendar requirement no engineering can shorten.** The
developer account is personal, created after 13 Nov 2023, and the app is on the closed track
with **4 opted-in testers**. Google requires **12 opted-in testers continuously for 14 days**
before you may apply for production access. Internal testing does not count, and the streak
starts only when the count *first reaches 12* — **the existing 4 accrue nothing.**

Three consequences, applied throughout:

1. **iOS is the launch platform.** It has no equivalent gate.
2. **Android is a follow-on with its own gate set**, and its date is driven by recruitment, not
   by code. **No Play date in this plan is engineering-pullable.**
3. **Recruitment to 12+ is now a plan dependency with an owner (Tyler) and a date**, and it is
   the longest pole in the entire program. Every day of recruitment delay is a day of Android
   delay, one for one.

### Revision history of the things I got wrong

| Rev | Claim | Corrected |
|---|---|---|
| 1 | "2 P0s, both Firestore-side, can ship during review" | 5 P0s; rules deploys are atomic/global and cannot ride along with a review |
| 1 | "Gate `/bridge_registry` list — best ratio in the audit" | Retracted. Enumeration-hiding; `/referral_codes` is a full UID directory |
| 1 | "F-7: orphaned routes reachable via `lumina://`" | Retracted — my error, no entry vector exists |
| 2 | "Q1 — no macOS, iOS unknown, top date gate" | Closed. Codemagic pipeline exists; most of the iOS surface was repo-inspectable |
| 2 | "D4 gated on dealer adoption → weeks post-launch" | Pre-submission; blast radius is the installer population |
| 3 | "D4 blast radius ≈ 2 devices" | **1-5 active dealers plus Tyler.** See §3A-3 |
| 3 | Ask beta testers about schedule firing | **Wrong population.** Play closed testers mostly have no hardware. See §3A-5 |
| 3 | Play as a same-wave platform | **Late August at the earliest, and not engineering-gated** |

---

## 1. DEDUPLICATION

Unchanged and still accurate.

| Merged finding | Appeared as | Resolution |
|---|---|---|
| Cross-tenant read/overwrite/delete | A handoff · B F-1 | **P0-1.** Fix the resource, not the harvest |
| UID harvest | A handoff (unverified) · B §2.6(a) | Confirmed, **seven paths**. Context for P0-1 |
| Account deletion | A F-1 · B F-5a/F-5b | **Split** → P0-5 (bridge) + P1 (erasure). Both positions upheld |
| Bridge orphaning | A F-1 · B F-17 · ledger "closed" | One defect, three sightings. Ledger is wrong |
| Orphaned routes / commercial stubs | A F-6+F-7 · B F-25 | Merged, re-tiered down. **A F-6 remediation corrected 2026-07-30 — commercial SHIPS fast-follow, so keep the code and seal the route (§4A). Do not delete** |
| Neighborhood Sync | A §5 · B F-3 · C F-1 | Three non-overlapping halves |
| Schedule firing | A F-2+F-3 · C §2.5 | **T-1.** One diagnostic answers all three |

---

## 2. iOS SURFACE

### Repo-inspectable, checked

| Item | Verdict |
|---|---|
| **`NSLocalNetworkUsageDescription`** — silently kills ESP32/mDNS discovery on iOS 14+ if missing | **PRESENT** — [Info.plist:60-61](ios/Runner/Info.plist#L60-L61). `NSBonjourServices` declares `_wled._tcp` + `_http._tcp` ([:48-52](ios/Runner/Info.plist#L48-L52)); `NSAllowsLocalNetworking` set ([:54-57](ios/Runner/Info.plist#L54-L57)). No action |
| All other purpose strings | **PRESENT** — [Info.plist:60-99](ios/Runner/Info.plist#L60-L99) |
| Orientation / iPad / min iOS 15.0 | **PASS** — [Info.plist:31-43](ios/Runner/Info.plist#L31-L43) |
| **`UIBackgroundModes` over-declaration** | **APPROVED FOR FIX — 0.5h, scheduled Day 2.** `fetch` and `processing` ([Info.plist:78-84](ios/Runner/Info.plist#L78-L84)) plus both `BGTaskSchedulerPermittedIdentifiers` ([:85-90](ios/Runner/Info.plist#L85-L90)) are unreachable: no `BGTaskScheduler` reference anywhere, no `workmanager`/`background_fetch`, no `flutter_background_service_ios` ([pubspec.yaml:43-44](pubspec.yaml#L43-L44) is Android-only), sports service hard-off ([sports_background_service.dart:29,48](lib/features/sports_alerts/services/sports_background_service.dart#L29)). `remote-notification` is justified. Guideline 2.5.4 |
| `PrivacyInfo.xcprivacy` | **ABSENT** — see the precise check below |

### 2.1 — The ITMS-91053 check, stated precisely

**Correction to rev 3's reasoning.** I wrote that successful build-187 uploads were evidence the
privacy manifest is satisfied. **That inference is too strong. ITMS-91053 does not block upload
— it is delivered by email to the account holder.** A successful upload is therefore *not*
proof of absence; it is only proof that nothing hard-failed.

**The exact check — owner: Tyler (the emails go to the account holder's address, not to any
console surface):**

1. Search the Apple ID account holder's email for **`ITMS-91053`**, and for the subject phrase
   **"Missing API declaration"**, from sender `no_reply@email.apple.com`.
2. Cover the window spanning your recent Codemagic uploads, not just the last one.
3. App Store Connect does **not** reliably surface these warnings in its UI. Email is the
   channel. If nothing is found, the app-level manifest is genuinely not being demanded today.

**Decision either way:** adding an app-level `PrivacyInfo.xcprivacy` is **2h** and closes the
question permanently. I would do it regardless — warnings have historically hardened into
rejections — but it is **not** a gate.

### 2.2 — Third-party SDK manifests are macOS-gated

**Flag raised, and it is a real limitation of Window B's check.** Window B spot-checked plugin
privacy manifests **from the pub cache** — that is the *Flutter plugin wrapper* packages. It is
not the resolved CocoaPods set. **Firebase is the important case:** `FirebaseCore`,
`FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`, `FirebaseMessaging` ship as CocoaPods
whose privacy manifests live in the pods, not in the Flutter plugin.

There is **no `Podfile.lock` in this checkout**, so the resolved pod set — and therefore which
SDK manifests are actually present in the built app — **cannot be enumerated without macOS or a
Codemagic build log.** Recoverable cheaply from any recent build log; just not from here.

### 2.3 — What genuinely requires macOS

1. Building/signing the IPA — Codemagic does it.
2. **Pod resolution** — §2.2 above.
3. Running the verification gate on an actual iOS device.

---

## 2A. EXTERNAL TESTFLIGHT — CONFIRMED, DAY 2

Beta App Review is a real human pass. Lumina has never had one: internal TestFlight skips it
entirely, so 187-plus builds have produced **zero human review signal**.

| | Detail |
|---|---|
| Requires | External test group; Beta App Review Information (**demo account credentials**, notes); beta description; feedback email; privacy policy URL; export-compliance answer. All already on the plan |
| Takes | 24-48h typical for a first external build; **budget 3 days** |
| Costs against production review history | **Nothing.** A beta rejection is free information |

**Catches:** a real reviewer opening the app with no controller on the network (2.1); whether
the demo account works from Apple's side; 2.3.1 hidden-functionality disclosure; export
compliance; purpose strings and the 2.5.4 fix.

### ⚠️ Caveat — recorded as a standing condition, not a footnote

**A clean Beta App Review pass does NOT clear:**
- **5.2 IP — the 155+ sports team and league names** ([team_color_database.dart:302-308](lib/data/team_color_database.dart#L302-L308)). Beta review will almost certainly not surface this. It remains a full-review and legal exposure.
- **5.1.1(v) account deletion** — unlikely to be exercised in beta.
- Store metadata and screenshots — not evaluated in beta review at all.
- Business-model guidelines (3.x).

**Do not treat a beta pass as broad validation.** It de-risks completeness and the demo path.
Nothing else.

---

## 2B. FLEET STATE

### iOS

| Fact | Evidence |
|---|---|
| Codemagic → App Store Connect, auto-submit to TestFlight | [codemagic.yaml:128-131](codemagic.yaml#L128-L131) |
| **Internal testers only** — no `beta_groups:` key | [codemagic.yaml:128-131](codemagic.yaml#L128-L131) |
| ≥187 builds shipped | signing-diagnostic comment in `codemagic.yaml` |
| Bundle `com.nexgenled.command`; **not obfuscated** (Android is) | [codemagic.yaml:12](codemagic.yaml#L12); explicit "No --obfuscate" rationale |
| **Never through any Apple review** | Internal TestFlight skips Beta App Review |

### Android — the binding constraint

| Fact | Value |
|---|---|
| Developer account | **Personal**, created after 13 Nov 2023 |
| Track | **Closed testing** |
| Opted-in testers | **4** |
| Requirement | **12 opted-in, continuously, for 14 days** before applying for production access |
| Internal testing counts? | **No** |
| Do the existing 4 accrue? | **No** — the streak starts when the count first reaches 12 |
| CI | **None** — Android builds are local, manually uploaded (`codemagic.yaml` defines `ios-workflow` only) |

---

## 2C. THE PLAY PRODUCTION MODEL

**Play production is not engineering-gated. Model it from recruitment.**

```
D12  = the date opted-in tester count FIRST reaches 12        ← owner: Tyler, currently unknown
     + 14 days continuous ................................... earliest date you may APPLY
     + production access review ............................. Google-side, plan ~7 days
     + production release review ............................ plan 1-3 days
     ────────────────────────────────────────────────────────
     = Play production live
```

**The ask is 8 more testers.** Not a number engineering affects.

| Scenario | D12 | Streak ends | Apply → access | Play live |
|---|---|---|---|---|
| Immediate | Fri Aug 1 | Aug 15 | ~Aug 22 | **~Aug 25** |
| One week | Fri Aug 8 | Aug 22 | ~Aug 29 | **~Sep 1** |
| Two weeks | Fri Aug 15 | Aug 29 | ~Sep 5 | **~Sep 8** |

**"Late August at the earliest" holds only if recruitment is essentially immediate.**

### ⚠️ Interaction risk — rules tightening during the streak

**D1-D5 deploy to shared backend infrastructure. Android closed testers are subject to them
the moment they land** — rules are atomic and global. If a tightening breaks those testers
badly enough that any of them opt out, **the count drops below 12 and the 14-day streak
restarts.** That is a two-week penalty for a five-minute rollback.

**Recommendation: start recruitment immediately anyway, on Day 1.** The streak is the longest
pole, delaying it costs 1:1, and the risk is manageable — D1-D3 are low-risk deploys, D4 is
verified against the instrumented fallback before it lands, and a rules rollback takes ~5
minutes. But **monitor tester count daily through the streak**, and treat any opt-out as an
incident rather than attrition.

#### Keep the two populations disjoint — the structural mitigation

The rules-affected population and the streak population should not overlap. **Recruit closed-track
testers from people WITHOUT paired systems** — friends, family, staff on spare devices, anyone
willing to install the app and opt in. A tester with no controller is nearly immune to D1-D5:
the tightened rules govern `/users/{uid}/controllers`, `/bridge_registry`, neighborhood groups
and Storage, none of which an unpaired account meaningfully touches. They still count toward the
12, because Google counts opt-ins, not usage.

Conversely, **dealers and commissioned customers belong on the installer build for S-5, not on
the closed track.** They are the population D4 can break and the population the §3A-5 prevalence
ask needs. Putting them on the closed track pulls the one group that *can* be broken into the
one group whose departure restarts a 14-day clock.

**⚠️ Overlap risk — check this explicitly.** If any current or prospective closed tester is
*also* a paired customer, they sit in both populations at once and a rules break could cost the
streak. There are 4 testers today; enumerate them before recruiting further and confirm none
holds a paired system. If one does, the cleanest fix is to move them off the closed track and
recruit a replacement — not to soften the deploys.

**Alternative if you would rather not carry that risk:** finish all rules work and V-1…V-4
first (~Aug 7), then recruit. Costs about a week of Android date. I do not recommend it —
it trades a certain week for an unlikely two.

---

## 3. GATE SET — SPLIT BY PLATFORM

Submission is gated on conditions, not dates.

### Shared — backend and binary. Block **both** platforms.

| # | Condition | Verified by | Owner |
|---|---|---|---|
| **S-1** | **T-1 answered** — `fire-test` attributed app-side vs device-side | Raw-curl arm + readback (§3A-5) | Tyler |
| **S-2** | **Rules tightened with no breakage** — D1-D5 deployed, V-1…V-4 pass | §6 | Tyler |
| **S-3** | **Installer wizard survives >60 min against tightened rules** — also resolves `fromUid` | V-4, real hardware | Tyler |
| **S-4** | **Bridge self-registration + pairing work against tightened rules** | V-2, V-3 — one fresh, one paired bridge | Tyler |
| **S-5** | **All installer devices confirmed on the token-refresh build, zero anonymous fallbacks** | Instrumented `:756` telemetry (§3A-3) | Tyler |
| **S-6** | **Prevalence check clean** — ≥2 overnight cycles across **customers with installed systems** | Direct ask (§3A-5) | Tyler |

### iOS — the launch platform

| # | Condition | Verified by |
|---|---|---|
| **I-1** | Demo path works with **NO controller online**, on an iOS device | V-1 on iOS |
| **I-2** | +59 cold-launches on iOS past securestorage | Manual, real device |
| **I-3** | ITMS-91053 email check complete (§2.1) | Tyler, account-holder inbox |
| **I-4** | 2.5.4 background-mode fix shipped | Info.plist diff |
| **I-5** | Export-compliance answer resolved deliberately | Window B F-14 |
| **I-6** | **Beta App Review passed** | External TestFlight |
| | | **NON-BLOCKING** — recommended; a rejection is free information |

### Android — follow-on. All of Shared, plus:

| # | Condition | Verified by | Owner |
|---|---|---|---|
| **P-1** | **12 opted-in closed testers, continuously, for 14 days** | Play Console, checked **daily** | **Tyler — recruitment, not engineering** |
| **P-2** | Production access granted after applying | Play Console | Google |
| **P-3** | Demo path works with no controller online, on Android | V-1 on Android | Tyler |
| **P-4** | +59 cold-launches on Android past securestorage | `adb logcat \| grep LUMINA_STARTUP` | Tyler |
| **P-5** | **Migration verified against real old-format data** | §3A-4, allowlist rehearsal | Tyler |
| **P-6** | versionCode exceeds every code ever uploaded | Play Console (authoritative) | Tyler |

**P-1 is the binding gate for Android and it is the only gate in this document that engineering
cannot influence at all.**

---

## 3A. WORK ITEMS

### 3A-3 — D4 (P0-1 resource narrowing), re-verified against 1-5 dealers

**The 6.5h engineering estimate holds. The risk profile does not — and that changes the gate,
not the cost.**

Why the estimate is insensitive to dealer count: every step is build-and-deploy work, not
per-device work.

| Step | Action | Est | Scales with dealer count? |
|---|---|---|---|
| a | Token-refresh fix in `_restoreInstallerAuth` ([installer_setup_wizard.dart:756](lib/features/installer/installer_setup_wizard.dart#L756)) | 2h | No — one build |
| b | **Instrument `signInAnonymously()` at :756** — log every fallback to `debug_errors` | 1h | No |
| c | One deliberate >60-minute install run | 1.5h | No — one run proves the mechanism |
| d | Tighten [firestore.rules:383,389,392,395](firestore.rules#L383) and [:355-360](firestore.rules#L355-L360) | 2h | No |
| | **Total** | **6.5h** | |

**What does change, materially:**

1. **The failure mode now has real customers attached.** With Tyler alone, a missed update is an
   inconvenience. With up to 5 external dealers, a dealer who has not updated gets their
   controller migration denied **mid-install in a paying customer's driveway**, with no
   client-side error path built for it.
2. **You do not control dealer update timing.** Auto-update may be off; they may not open the
   app for days.
3. **Confirmation becomes a gate rather than an assumption.** This is exactly what step (b)
   buys: the instrumented build turns "did everyone update?" from a question into an
   observation.

**Added as gate S-5:** do not deploy D4 until telemetry confirms **every** installer device is
on the token-refresh build **and** reports zero anonymous fallbacks. Not one device — all of
them.

#### S-5 dealer timeout — decided now, with trigger dates

Deciding this in the moment, under deploy pressure, is how the wrong answer gets picked. The
rule below is set in advance and uses the slack against the Play window (§5).

| Date | Checkpoint | Action |
|---|---|---|
| **Thu 2026-08-06** (Day 6, D4 deploy day) | Read S-5 telemetry | **All devices confirmed → deploy D4 as planned.** Any device missing → **do not deploy, do not decide yet.** Escalate: call the dealer directly |
| Thu Aug 6 → Mon Aug 10 | Grace window | Chase the outstanding dealer(s). This window is free — it consumes iOS slack, not the Play critical path |
| **Mon 2026-08-10** (Day 8) | **Hard decision date** | Apply the rule below. Do not extend a second time |

**The rule at Mon Aug 10** turns on whether the dealer has been *reached*, not whether they have
*updated*:

- **(a) PROCEED past them** — permitted only if **all three** hold: the dealer has been contacted
  and acknowledged; they have **no install scheduled** before they update; and they have been
  given an explicit warning that controller migration will fail mid-install until they take the
  build. Log the warning somewhere durable, not in a text message.
- **(b) HOLD D4 behind submission** — required if the dealer is **unreachable**, or has **any
  install scheduled**. Ship iOS with D4 open and deploy it once they confirm.

**Default is (b).** A denied migration in a customer's driveway costs a relationship and a truck
roll; D4 open for another week is a P0 that has already been open for months. Choose (a) only
when all three conditions are affirmatively met — not merely when none is known to be violated.

**Confidence: Medium**, unchanged, still contingent on the `fromUid` result from step (c).

### 3A-4 — Migration rehearsal (Android only, gate P-5)

Machinery already exists — `allowlistUids` and stable `rolloutPercent`
([schedules_subcollection_feature_flag.dart:16-56](lib/features/schedule/schedules_subcollection_feature_flag.dart#L16-L56)).
Console configuration, not code.

1. **Identify old-format accounts** — Android closed-tester uids with a non-empty `schedules`
   array and no `schedulesMigratedAt` marker. Capture each pre-image (count + full array).
2. **Canary of one** — allowlist a single uid. Confirm marker stamped, doc count equals
   pre-image, `sortKey`s contiguous with no ties.
3. **Idempotency** — force a second run. Confirm no renumbering, no duplicates.
4. **No half-migrated state** — kill mid-migration. Marker unset, next launch converges.
5. **Rollback** — remove from allowlist, confirm legacy array still current and schedules
   identical.
6. **Widen** to `rolloutPercent: 100` across the closed fleet, ≥48h soak.

**Est 4h across two sessions + 48h soak.** This now has room: it runs during the 14-day streak,
which is dead calendar time otherwise. **If no closed tester holds old-format data**, this
degrades to non-blocking and the flag simply stays off at Android launch.

### 3A-5 — Fire-test: bench for mechanism, direct ask for prevalence

**Recommendation accepted. Not building telemetry.** The bridge heartbeat carries no controller
power state ([main.cpp:982-1000](esp32-bridge/src/main.cpp#L982-L1000)); adding it is 8h+ of
firmware plus an OTA to answer what a message answers tonight.

#### ⚠️ Correction — the right population

Rev 3 said "ask the beta users." **Wrong.** Play closed testers are recruited for the tester
count and **mostly have no LED hardware at all** — they cannot observe whether lights came on.
Asking them produces noise, and after recruitment to 12 it will produce mostly noise.

**The correct population: customers with commissioned, installed systems running real
overnight schedules.** From project context that is a small, specific set:

- Tyler's own installation
- Ellie's installation (the Neighborhood Sync counterpart home)
- **Dealer `01`'s installed customers** — the real-world population, reachable via the dealer
- The bench rig (N=1, already known bad)

**This population does not overlap the Play closed track and must not be conflated with it.**
It is small — likely single digits — which limits statistical strength but is still the only
real-world evidence available, and it is free.

**Ask:** "Over the last two nights, did your lights come on and go off at the scheduled times?"
Two overnight cycles. Feeds gate **S-6**.

**Bench (mechanism, 1.5h, gate S-1):** arm one timer by raw `curl`, read `/json/cfg` back at 0s
and +60s. Does not persist → device-side, app exonerated. Persists but does not fire → firmware
timer evaluation. Fires correctly → app-path bug.

**If the two disagree, believe the customers.**

### 3A-3b — P0-5 (bridge orphan): unchanged, cannot be closed

Firmware limitation: a paired bridge never polls for unpair
([main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220)) and re-asserts `pairedUid` from
NVS every heartbeat ([:1046](esp32-bridge/src/main.cpp#L1046)). Pre-launch is **mitigation only,
4h**: cleanup function, `blocked_bridges` collection, deletion warning. Part 2 (firmware unpair
+ OTA) remains unestimated — see Q-O.

---

## 4. PLAN

**Decision recorded (accepted):** Option 1 declined; **D4 stays pre-submission**. Rationale, in
your words and worth preserving because it is the right frame: *no public users are waiting,
Play is late August regardless, and shipping a first public release with a known-open P0 costs
more than four days.*

### Track A — iOS to submission

**DAY 1 — Thu Jul 30 (today) — 4h**
1. **Start Play recruitment to 12+.** Longest pole; every day costs a day *(0.5h to launch, ongoing)*
2. **T-1 bench diagnostic** — raw-curl arm, readback 0s/+60s, await fire *(1.5h, gates S-1)*
3. **Send the prevalence ask** to customers with installed systems — **not** Play testers *(0.5h, feeds S-6)*
4. **T-2** cold-launch +58 on Android *(0.5h)*
5. Clear the orphaned slot-3 timer on the bench rig *(0.5h)*
6. **ITMS-91053 email check** (§2.1) *(0.5h, gates I-3)*

**DAY 2 — Fri Jul 31 — 6h — BINARY BATCH → +59, START BETA REVIEW**
7. **P0-4** liability / not-life-safety / not-UL-924 text + in-app Legal screen *(2h)*
8. **2.5.4 fix** — remove `fetch` + `processing` and both BGTask identifiers *(0.5h, gates I-4)*
9. Login version string `v2.2.0` → real; **resolve export compliance** *(1h, gates I-5)*
10. **Seal `/commercial` — do NOT delete it.** Confirm no in-app navigation and no deep-link path; add `/commercial` **and** `/media` to the restricted list at [route_guards.dart:54](lib/route_guards.dart#L54); verify demo browsing still behaves *(1h — §4A)*
11. Build +59 both platforms; cold-launch verify *(1h, gates I-2 / P-4)*
12. **Submit +59 to an EXTERNAL TestFlight group** *(0.5h, starts I-6)*

**DAY 3 — Mon Aug 3 — 5h — SAFE DEPLOYS**
13. Pre-flight: capture deployed ruleset as rollback artifact; confirm HEAD diffs clean; confirm `sync_fanout == false` *(1h)*
14. **D1 — P0-2** auth check on `createCustomerAccount` *(2h)*
15. **D2 — P0-1 Storage half** — `users/{userId}` read → owner-only *(1h)*
16. Migration rehearsal step 1 — identify old-format accounts, capture pre-images *(1h)*

**DAY 4 — Tue Aug 4 — 5h — D3**
17. **D3 — P0-3** neighborhood read scoping + invite-code into a callable. **Callable first, then rules** *(5h)*
    · *Beta App Review verdict expected in this window — react before proceeding*

**DAY 5 — Wed Aug 5 — 5h — D4 PREREQUISITE**
18. Token-refresh fix + **instrument `signInAnonymously()` at :756** *(3h)*
19. Ship to **all** installer devices; begin the >60-minute run *(2h, resolves `fromUid`)*

**DAY 6 — Thu Aug 6 — 5h — D4 + D5**
20. **Confirm every installer device reports in with zero anonymous fallbacks** (gate S-5), then deploy **D4** *(3h)*
21. **D5 — P0-5 mitigation** — cleanup function, `blocked_bridges`, deletion warning *(2h)*

**DAY 7 — Fri Aug 7 — 6h — VERIFICATION GATE**
22. **V-1** reviewer path, no controller online, **both platforms** *(2h, gates I-1 / P-3)*
23. **V-2** bridge self-registration · **V-3** pairing handshake *(2h, gates S-4)*
24. **V-4** installer wizard >60 min *(2h, gates S-3)*

**DAY 8 — Mon Aug 10 — 4h**
25. Migration rehearsal steps 2-6; begin 48h soak *(2h)*
26. Privacy policy correction (photos + physical addresses), then both store forms *(2h)*

**DAY 9 — Tue Aug 11 — 5h — SUBMIT iOS**
27. Screenshots + metadata; review notes **disclosing the 5-tap staff gesture** *(3h)*
28. Confirm S-1…S-6 and I-1…I-5; run §6; **submit to App Store** *(2h)*

### Track B — Android, parallel and recruitment-driven

| When | Action | Owner |
|---|---|---|
| **Day 1, ongoing** | **Recruit 8+ testers to reach 12.** Monitor count daily | Tyler |
| Day 1 → D12 | Nothing engineering-side blocks this | — |
| D12 → D12+14 | **Streak runs.** Watch for opt-outs — an opt-out below 12 restarts the clock. Run the migration rehearsal (P-5) in this window | Tyler |
| D12+14 | Apply for production access | Tyler |
| +~7d | Production access granted | Google |
| + review | Android production release | — |

---

## 4A. FAST-FOLLOW WORK ITEM — COMMERCIAL MODE

**Decision (Tyler, 2026-07-30): commercial mode SHIPS, as a fast-follow point release, not in
v1.** This supersedes the retirement assumption every prior revision was built on.

### What this reverses

My rev 2/3 recommendation — *"delete the `/commercial` route and `CommercialHomeScreen`, ~1h,
cheapest fix in either document"* — is **withdrawn**. It was correct only under retirement.
Deleting shipping code means rebuilding it.

**Also reversed: the existing commercial retirement plan.** `docs/commercial_ux_audit.md` and
the project ledger carry a Phase 4-6 plan whose Phase 6 deletes `CommercialHomeScreen` and the
`/commercial` route. **That plan's terminal phase is now void.** The earlier phases may still be
useful, but the whole document was written toward retirement and should be re-read against a
ship decision before anyone works from it. Flagged rather than rewritten — it is not an audit
deliverable.

### v1 action — 1h, on Day 2

**Leave the code in place. Seal the route.**

1. No deletion, no refactor of commercial code.
2. **Confirm the seal holds** — no in-app navigation ([route_guards.dart:245-252](lib/route_guards.dart#L245-L252)),
   no deep-link path. Window B verified `flutter_deeplinking_enabled` and
   `FlutterDeepLinkingEnabled` absent on both platforms; this is a re-confirmation, not a
   re-derivation.
3. **Add `/commercial` and `/media` to the restricted list** at
   [route_guards.dart:54](lib/route_guards.dart#L54) as defense-in-depth. Prefix match, so both
   are one-line additions:
   `const restricted = ['/installer', '/sales', '/admin', '/dealer'];`
   `/media` is included per Window A F-7 / Window B F-25 — the same class, and free to fix here.
4. **Verify demo browsing still behaves.** This list gates the demo flow, so it is the one thing
   that can regress.

**Estimate 1h. Confidence High** — the change is two strings plus a demo-flow check.

**Note this is not the full class fix.** Window B's F-25 (tracked as T-25) additionally adds a
`/dealer` prefix check and makes unknown prefixes deny-by-default — 4h, still separately tracked
in §4. Adding two entries to the list is defense-in-depth for a known surface; it does not change
the router's allow-by-default posture.

### ⚠️ ORDERING CONSTRAINT — gate on the fast-follow release, NOT on v1

Same pattern as F-5a/F-5b. **The three TODO-backed controls are safe only while unreachable:**

| Control | Reports | Actually does |
|---|---|---|
| Pause All — [:1819](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1819) | "All channels paused" | Nothing |
| Run Default — [:1850](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1850) | "Running default: {id}" | Nothing |
| Apply Override — [:2064](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L2064) | "Override applied: {id}" | Nothing |

**These must be implemented BEFORE any entry vector to `/commercial` lands.**

An **entry vector** means any of: in-app navigation to `/commercial` added; `/commercial` removed
from the restricted list; `flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled` turned on;
or the commercial-mode redirect restored in `route_guards.dart`.

**If an entry vector ships first, three false-success controls become reachable — a Guideline 2.1
finding on that release.** The ordering is not negotiable and it is cheap to honour: implement,
then open the door.

### Fast-follow scope

| # | Item | Est | Confidence |
|---|---|---|---|
| C-1 | Implement the three control handlers against real `WledService` calls | **16h** | Medium |
| C-2 | Wire the two dead nav targets on Fleet Dashboard — [:1041](lib/screens/commercial/fleet/FleetDashboardScreen.dart#L1041), [:1050](lib/screens/commercial/fleet/FleetDashboardScreen.dart#L1050) | 4h | Medium |
| C-3 | Day-part edit ([:984](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L984)) and drag/resize with 15-min snap ([:1006](lib/screens/commercial/schedule/CommercialScheduleScreen.dart#L1006)) — both currently inert | 8h | Low |
| C-4 | **Commercial surface audit — exists-vs-works** | **12h** | Low |
| C-5 | Remove the seal: in-app entry vector + restricted-list removal, **after C-1** | 2h | High |
| | **Total** | **42h** | |

### C-4 — why the audit is not optional

**The commercial surface has never been traced.** Window A covered roughly a third of ~110
routes and **commercial was not among them** — the whole `/commercial/*` tree is `UNVERIFIED`,
not `verified working`. What is known is only what a stub-grep surfaced, which is why C-1…C-3
exist. That is a floor on the defect count, not a ceiling.

Untraced surfaces in scope:

- `/commercial` · `/commercial/onboarding` · `/commercial/brand/search` · `/commercial/brand/setup` · `/commercial/brand/corrections` · `/commercial/events` · `/commercial/events/create`
- `CommercialHomeScreen`, `FleetDashboardScreen`, `CommercialScheduleScreen`
- Firestore collections `commercial_locations`, `commercial_hours`, `commercial_events`, `brand_profile` — all rule-scoped ([firestore.rules:561-641](firestore.rules#L561-L641)) but never traced UI→write→device

Known-adjacent items already in the ledger that this audit must reconcile: commercial onboarding
unreachable; dual commercial-activation write paths; commercial fields lacking post-install UI;
the smoke test referencing UI that was never built; the "Profile" tab misnamed. **Several were
filed as "will be resolved by retirement." They no longer will be.**

**Sequence C-4 before C-1**, not after. Implementing three handlers on a surface whose data flow
has never been verified risks building on a broken foundation — and Window A's F-8 (a dead
`applyConfig` write paired with a false success toast) is precedent for exactly that failure mode
elsewhere in this codebase.

### Relationship to v1

**Nothing in §4A is on the v1 critical path** beyond the 1h seal on Day 2. The fast-follow
release is a separate cycle with its own gate (the ordering constraint above). It should not
borrow v1's slack (§5) — that slack exists to absorb v1 risk, not to start the next release
early.

---

## 5. DATES

### iOS — **ACCEPTED**

| | Date |
|---|---|
| **Submission, earliest** | **Tue 2026-08-11** |
| **Submission, confidence-adjusted** | **Tue 2026-08-18** |
| App Review | 1-3 days typical; first submission can run longer |
| **iOS live** | ~Aug 13-15 earliest · ~Aug 20-22 adjusted |

### Android — recruitment-driven, **not engineering-pullable**

**`Play live = D12 + 14 days + ~7 days access review + 1-3 days release review`**

| D12 | Play live |
|---|---|
| Fri Aug 1 | **~Aug 25** |
| Fri Aug 8 | **~Sep 1** |
| Fri Aug 15 | **~Sep 8** |

**Android trails iOS by roughly two weeks in the best case.** Nothing in the engineering plan
changes that. **The only lever is how fast 8 more testers opt in.**

### Slack — no engineering item is on the binding constraint

The iOS engineering path finishes **Aug 11-18**. The Play window opens **~Aug 25-Sep 1**. That
leaves roughly **one to three weeks of slack** between the last engineering task and the earliest
possible Android release.

**Consequences worth holding onto:**

- **P-1 recruitment is the critical path. Everything else is float.** If a schedule conversation
  starts with an engineering task, it is about the wrong thing.
- **Nothing in §4 Track A is worth rushing.** A day saved on D3 or the verification gate buys
  nothing — it lands in slack. Spend the time on quality instead: this is why the S-5 grace
  window to Aug 10 is free, and why holding D4 for an unreachable dealer costs schedule nothing.
- **The slack is not infinite and it is one-directional.** It absorbs iOS-side slip up to about a
  week before it starts pushing the Android date. The T-1 fork (2-3 days if app-side) fits inside
  it; a compounding failure would not.
- **If recruitment stalls, slack grows and no engineering decision should change in response.**
  Resist the temptation to backfill idle time with scope — the parallel track in the point-release
  list is where spare capacity belongs.

### Gated on, in order of impact

1. **P-1 recruitment (Android only).** The single longest pole in the program. Owner: Tyler.
2. **S-1 / T-1 fork.** App-side attribution adds 2-3 days for fix + rebuild + re-verify — affects **both** platforms.
3. **S-5 — reaching all 1-5 dealers.** If one is unreachable, hold D4.
4. **The `fromUid` contingency** (Day 5). If it fails, D4 grows; hold rather than force.
5. **Beta App Review verdict** (Day 4). Non-blocking; a rejection redirects remaining days.

**No longer gates:** iOS build capability; the privacy manifest as a hard unknown.

---

## 6. CHECKLIST

### Day 1
- [ ] **Start Play recruitment to 12+** — longest pole in the program. **Recruit people WITHOUT paired systems** (§2C): they count toward the 12 and are nearly immune to D1-D5. Keep dealers and commissioned customers OFF the closed track — they belong on the installer build for S-5 and in the §3A-5 prevalence ask
- [ ] T-1 bench diagnostic (**S-1**) · T-2 cold-launch +58 · clear slot-3 orphan
- [ ] **Prevalence ask to customers with installed systems** — Tyler's, Ellie's, dealer `01`'s customers. **NOT Play testers** (**S-6**)
- [ ] **ITMS-91053 email check** — account holder's inbox, `no_reply@email.apple.com`, subject "Missing API declaration" (**I-3**)
- [ ] Window B V-1 — does `reviewer@Nex-GenLED.com` exist in Firebase Auth with a known password?

### Binary (+59, both platforms)
- [ ] P0-4 liability text + Legal screen
- [ ] **Remove `fetch` + `processing` and both BGTask identifiers** (**I-4**)
- [ ] Login version string; **export-compliance answer resolved** (**I-5**)
- [ ] **Seal `/commercial` (do NOT delete)** — confirm no in-app nav, no deep-link path; add `/commercial` **and** `/media` to the restricted list at [route_guards.dart:54](lib/route_guards.dart#L54); re-verify demo browsing (§4A)
- [ ] `flutter analyze` clean; `--obfuscate` on Android; symbols archived both platforms
- [ ] Cold-launch +59 past securestorage, **both** (**I-2**, **P-4**)
- [ ] **Submit to external TestFlight** (**I-6**)
- [ ] *Optional, recommended:* app-level `PrivacyInfo.xcprivacy` (2h)

### Backend deploys — IN ORDER, verify between each
- [ ] `firebase use icrt6menwsv2d8all8oijs021b06s5`
- [ ] **Capture deployed ruleset as rollback artifact** — there is no undo
- [ ] Confirm HEAD diffs clean; confirm `sync_fanout == false`
- [ ] **D1** functions:createCustomerAccount · **D2** storage · **D3** callable then rules
- [ ] **D4 — only after S-5: every installer device confirmed, zero anonymous fallbacks**
- [ ] **D5** — function + collection first, rule swap second
- [ ] `cd functions && npm run build` before any function deploy
- [ ] `firebase deploy --only firestore:indexes`
- [ ] All four feature flags **false**
- [ ] ⚠️ **Snapshot the closed-track tester count immediately BEFORE and AFTER every one of D1-D5.** Record both numbers against the deploy. **Only the count is observable — Play does not expose the identity of an opt-out**, so a before/after pair on each deploy is the only way to attribute a drop to a specific rules change rather than to background attrition. A drop with no other explanation should be treated as deploy-caused until shown otherwise
- [ ] Confirm no closed tester is also a paired customer (§2C overlap risk) — enumerate the current 4 before recruiting further

### Verification gate
- [ ] **V-1** reviewer path, no controller online — **iOS** (**I-1**) and **Android** (**P-3**)
- [ ] **V-2** bridge self-registration · **V-3** pairing handshake (**S-4**)
- [ ] **V-4** installer wizard >60 min, resolves `fromUid` (**S-3**)
- [ ] Prevalence: ≥2 clean overnight cycles from installed customers (**S-6**)
- [ ] Re-confirm `sync_fanout` still false

### Store — iOS
- [ ] Privacy policy corrected — currently omits photos and physical addresses
- [ ] Apple nutrition labels match
- [ ] Screenshots, description, support/marketing URLs, age rating
- [ ] Review notes **disclose the 5-tap staff gesture** (2.3.1)

### Store — Android (follow-on)
- [ ] **P-1: 12 opted-in testers × 14 continuous days** — check daily
- [ ] Apply for production access; **P-2** granted
- [ ] Play Data Safety form matches
- [ ] Play account-deletion **web URL** — currently absent
- [ ] **P-6** versionCode exceeds every code ever uploaded
- [ ] **P-5** migration rehearsal complete, 48h soak clean

### Rollout
- [ ] iOS phased release · Play staged 10→25→50→100%, ≥48h per stage
- [ ] Confirm the halt control is reachable on both consoles before you need it

---

## 7. OPEN QUESTIONS

**ANSWERED — recorded, no longer open:**
- **Q-P Play account** → personal, post-Nov-2023, closed track, 4 testers. **Now the binding constraint.** §2C
- **Q-T TestFlight** → internal only. iOS fleet is staff; never through Apple review
- **Q-I Installer devices** → Tyler + 1-5 active dealers. §3A-3
- **Fire-test telemetry** → do not build. Bench + direct ask. §3A-5
- **Date decision** → Aug 11 / Aug 18, D4 pre-submission

**STILL OPEN:**

**Q-A — Do any Android closed testers hold old-format schedule data?** Decides whether P-5 is a
real gate or degrades to "flag stays off." Answerable now; the rehearsal window is free calendar
during the streak.

**Q-O — Is there an OTA path to fielded ESP32 bridges?** If yes, P0-5 part 2 (firmware unpair)
becomes schedulable and the truck roll gets an end date. If no, P0-5 ships open indefinitely and
`blocked_bridges` is the permanent answer.

**Q-2 — Do you accept P0-5 shipping open, mitigated but not fixed?** Firmware is the only fix.
Unchanged by every fact learned since rev 2.

**Q-3 — Design Studio slices 0-5: verified on hardware, ever?** No audit traced any of six to
device effect. **Note the population correction applies here too** — ask customers with
installed systems, not Play testers.

**Q-4 — Does Alexa/Google linking work end-to-end?** If no, hide the settings entry (0.5h)
rather than advertise a broken integration.

**Q-5 — Has counsel seen Game Day?** 155+ team and league names ship live. **Beta App Review
will not catch this** (§2A caveat) — it is a full-review and legal exposure regardless.

**Q-6 — Has `fire-test` passed on this rig since 2026-07-24?** Narrows T-1.

**Q-7 — Is the 30-day deletion promise backed by any process today?** Decides whether F-5a is an
engineering gap or a live compliance gap.

**Q-8 — Does a ToS/EULA exist outside the repo?** Changes P0-4 from 2h to a legal engagement.

**Q-10 — `sales_jobs/**` Storage has no rule, so signed contracts are not being stored.** Who
should be allowed to read signed contracts?

---

## 8. THE HONEST PARAGRAPH

**The plan is no longer shaped by engineering, and that is the most useful thing to say about
it.** Android production is behind a 14-day tester streak that has not started, on a count of 4
against a requirement of 12, with the existing four accruing nothing — so Play is late August at
the absolute earliest and every day of recruitment delay costs a day one-for-one. Nothing in
this document, and nothing anyone writes in this codebase, moves that date. iOS therefore
becomes the launch platform by default rather than by choice, and it is in reasonable shape: the
purpose string that actually matters is correct, the pipeline has shipped 187-plus builds through
Apple's automated validation, and the one real iOS finding I turned up — two background modes
declared for functionality that does not exist — is half an hour of work.

**Realistic risk of iOS first-submission rejection: moderate, around one in four, and I want to
be honest that this number is soft in a way the others are not.** It is soft because Lumina has
never been through any Apple review at all — internal TestFlight skips Beta App Review entirely,
so every prediction in three audits about reviewer behaviour is inference from guidelines rather
than observation. The residual paths are mostly clerical and each is hours: an undisclosed 5-tap
staff gesture, an export-compliance answer that may not survive contact, a login screen reading
`v2.2.0`. **The external TestFlight run on Day 2 is what converts that guess into an
observation**, and it costs nothing against production review history — but do not let a clean
pass read as broad validation, because it will not touch the sports-marks IP question and
probably will not touch account deletion either. Those stay live into full review.

**Two things are most likely to go wrong, and neither is a rejection.** The first is that
schedules quietly do not fire: the bench regressed 21/21 → 18/21 and I reproduced the firing
failure twice, on a rig with a documented history of flash-persistence problems, which means I
still cannot tell you whether that is one sick controller or the fleet. The 1.5-hour bench
diagnostic answers the mechanism and the ask to installed customers answers the prevalence — and
the population correction matters more than it sounds, because asking Play closed testers would
have produced confident-looking noise from people with no lights. The second is D4 breaking an
install: with up to five external dealers rather than the two I assumed last revision, a dealer
who has not taken the token-refresh build gets their controller migration denied mid-job in a
customer's driveway. That is why S-5 is written as *every* device confirmed reporting zero
anonymous fallbacks, not one. **If a dealer cannot be reached, hold D4.** It is a P0 that has
waited months; it can wait for a phone call.
