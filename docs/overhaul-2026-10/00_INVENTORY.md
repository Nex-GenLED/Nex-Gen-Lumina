# Inventory — every place that tells a person how to do something or what the product does

Audited at `release/store-submission-consolidated` @ `c283d62` (app 2.5.10+116), 2026-10-08. Owner of every repo document is the repository owner (sole committer). "Last modified" is the last commit date on the release branch; untracked files show the file-system date.

## A. Repository documents (tracked on the release branch)

Audience key: **customer** = homeowner or commercial operator · **installer** = install crews · **dealer** = dealer principals and shop staff · **Nex-Gen staff** = internal operations · **internal (engineering …)** = engineering records, never customer- or dealer-facing.

Counts: 186 tracked document files (excluding fonts, launch-image notes, test evidence, the Flutter web shell and a stray cfg dump). By audience: customer 9 · customer+installer 3 · installer 7 · dealer shop staff 2 · dealer 9 · Nex-Gen staff 9 · guide index 1 · marketing/website 1 · release notes 1 · repo front page 1 · internal engineering 39 · internal engineering audit 98 · internal ledger/tracker 3. Fifteen of the facing documents exist twice (Markdown source plus a PDF render from 2026-08-27 that predates the 2026-09-17 text edits).

| # | Path | Kind | Audience | Last commit | Owner | Bytes | What it is |
|---|---|---|---|---|---|---|---|
| 1 | `ANALYTICS_SYSTEM.md` | Markdown | internal (engineering) | 2026-01-25 | Tyler (sole committer) | 19814 | Lumina Analytics System - Implementation Guide |
| 2 | `CHANGELOG.md` | Markdown | testers / customers (release notes, stale) | 2026-03-10 | Tyler (sole committer) | 2603 | Lumina Changelog |
| 3 | `CLAUDE.md` | Markdown | internal (engineering) | 2026-09-20 | Tyler (sole committer) | 23135 | CLAUDE.md |
| 4 | `GUIDED_MODE_IMPLEMENTATION.md` | Markdown | internal (engineering) | 2026-01-25 | Tyler (sole committer) | 32730 | Guided Mode Implementation Guide |
| 5 | `INTEGRATION_COMPLETE.md` | Markdown | internal (engineering) | 2026-01-23 | Tyler (sole committer) | 11325 | ✅ Lumina Learning System - Integration Complete! |
| 6 | `LANDINGSITE_AI_PROMPTS.md` | Markdown | marketing / website | 2026-09-22 | Tyler (sole committer) | 27762 | Landingsite.ai Prompts for www.nex-genled.com |
| 7 | `LEARNING_SYSTEM.md` | Markdown | internal (engineering) | 2026-01-23 | Tyler (sole committer) | 14229 | Lumina Learning System - Implementation Guide |
| 8 | `README.md` | Markdown | public (repo front page) | 2026-05-21 | Tyler (sole committer) | 377 | Nex-Gen Lumina |
| 9 | `SECURITY.md` | Markdown | internal (engineering) | 2026-09-17 | Tyler (sole committer) | 15903 | Lumina Security Implementation Guide |
| 10 | `SECURITY_SUMMARY.md` | Markdown | internal (engineering) | 2026-01-23 | Tyler (sole committer) | 6230 | Security Implementation Summary |
| 11 | `TASK_TEST_PLAN.md` | Markdown | internal (engineering) | 2026-05-15 | Tyler (sole committer) | 6047 | Test Plan — scheduled-event firing + GameDay live scoring + Light Up Now |
| 12 | `alexa-skill/DEPLOYMENT.md` | Markdown | internal (engineering / deployment) | 2026-01-29 | Tyler (sole committer) | 3876 | Amazon Alexa Skill Deployment Guide |
| 13 | `audit/ALL_STUB_CLOBBER.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 8055 | ALL-STUB CLOBBER — trace, bench, verdict |
| 14 | `audit/ALL_STUB_GUARD.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 8661 | ALL-STUB CLOBBER GUARD — implementation report |
| 15 | `audit/BASE_LADDER.md` | Markdown | internal (engineering audit) | 2026-08-09 | Tyler (sole committer) | 30479 | BASE LADDER — ON presets capture ambient segment state and fire dark |
| 16 | `audit/BASE_LAYER_GATE.md` | Markdown | internal (engineering audit) | 2026-08-10 | Tyler (sole committer) | 8189 | BASE-LAYER GATE — the `write_jobs` blocker |
| 17 | `audit/BLOCK_E_MISSING_ROW.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 13820 | BLOCK E — why the 23:17 schedule never reached the controller |
| 18 | `audit/BRIDGE_TRIAGE.md` | Markdown | internal (engineering audit) | 2026-08-07 | Tyler (sole committer) | 32774 | BRIDGE FLEET TRIAGE — who has one, who lost one, who never had one |
| 19 | `audit/CHANNEL_GROUPING_SCOPE.md` | Markdown | internal (engineering audit) | 2026-08-10 | Tyler (sole committer) | 35703 | CHANNEL GROUPING — SCOPE |
| 20 | `audit/COLOR_FIDELITY_AUDIT.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 28887 | Colour Fidelity Audit |
| 21 | `audit/COLOUR_FIDELITY_ADDENDUM.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 16588 | Colour Fidelity — Addendum (Part 2 of 2) |
| 22 | `audit/COMMAND_SAFETY.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 49316 | COMMAND SAFETY — S1 (controllerIp validation) + S2 (command expiry) |
| 23 | `audit/COMMISSIONING_FIXES.md` | Markdown | internal (engineering audit) | 2026-07-31 | Tyler (sole committer) | 17323 | Commissioning Fixes — roofline save gate + P0-5 rules narrowing |
| 24 | `audit/COMPLIANCE_AND_SECURITY.md` | Markdown | internal (engineering audit) | 2026-09-17 | Tyler (sole committer) | 92583 | Lumina — Compliance & Security Pre-Submission Audit |
| 25 | `audit/CONTROLLER_HEALTH.md` | Markdown | internal (engineering audit) | 2026-08-09 | Tyler (sole committer) | 55283 | CONTROLLER HEALTH TELEMETRY — S6, cloud half |
| 26 | `audit/DESIGN_CARD_LAYOUT_CONTROLS_AUDIT_2026-10-02.md` | Markdown | internal (engineering audit) | 2026-10-02 | Tyler (sole committer) | 8812 | Design card — Static setup and grouping controls (audit + fix) |
| 27 | `audit/DESIGN_CARD_P2.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 19757 | Design Card — Phase A |
| 28 | `audit/DESIGN_CARD_P3.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 15103 | Design Card — Phase B: My Designs becomes a real node |
| 29 | `audit/DESIGN_CARD_P4.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 25147 | Design Card — Phase C: effect edit, Sync picker, `composedPattern` |
| 30 | `audit/DEVICE_DIAGNOSTIC_2026-08-24.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 5742 | Device Diagnostic — "My Designs shows pre-Phase-A behaviour" |
| 31 | `audit/DIAGNOSTICS_DECLARATION.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 10898 | DIAGNOSTICS DECLARATION — `users/{uid}/debug_errors` |
| 32 | `audit/DIAGNOSTICS_FIX.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 22919 | DIAGNOSTICS — reduce then declare: implementation report |
| 33 | `audit/ELLIE_SUNSET.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 14736 | ELLIE SUNSET FAILURE — root cause |
| 34 | `audit/FEATURE_STATUS_MATRIX.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 44452 | FEATURE STATUS MATRIX — Window A |
| 35 | `audit/FROZEN_SEGMENT.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 11717 | FROZEN SEGMENT — blast radius audit |
| 36 | `audit/FROZEN_SEGMENT_FIX.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 8685 | FROZEN SEGMENT — implementation report |
| 37 | `audit/GAME_DAY_CELEBRATIONS_P1.md` | Markdown | internal (engineering audit) | 2026-08-25 | Tyler (sole committer) | 16738 | Game Day Celebrations — Implementation Report |
| 38 | `audit/GAME_DAY_SPEC_AUDIT.md` | Markdown | internal (engineering audit) | 2026-08-25 | Tyler (sole committer) | 19509 | Game Day / Score Alerts — Spec Audit |
| 39 | `audit/GAMMA_BUG.md` | Markdown | internal (engineering audit) | 2026-08-07 | Tyler (sole committer) | 17298 | GAMMA_BUG — colour gamma flips OFF durably on any `/json/cfg` write |
| 40 | `audit/GAMMA_FIX.md` | Markdown | internal (engineering audit) | 2026-08-07 | Tyler (sole committer) | 15262 | GAMMA_FIX — stop triggering the WLED cfg-deserialiser defect |
| 41 | `audit/HANDOFF_TO_WINDOW_B.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 7701 | HANDOFF TO WINDOW B — Firestore rules / isolation |
| 42 | `audit/HARDWARE_VERIFICATION_+60.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 14118 | Hardware verification — 2.5.10+60 · **still owed at +61 and +62** |
| 43 | `audit/HARNESS_AUDIT.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 19361 | BENCH HARNESS — ASSERTION AUDIT AND REPAIR |
| 44 | `audit/HEALER_PUBLISH.md` | Markdown | internal (engineering audit) | 2026-08-11 | Tyler (sole committer) | 33166 | HEALER PUBLISH — participation and base boundaries, one mechanism |
| 45 | `audit/INSTALLER_ENTRY.md` | Markdown | internal (engineering audit) | 2026-08-12 | Tyler (sole committer) | 48362 | INSTALLER MODE — ENTRY POINT AUDIT |
| 46 | `audit/INTEGRATION_TEST_BUILD.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 10151 | Integration Test Build — 2026-08-24 |
| 47 | `audit/LAUNCH_PLAN.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 44146 | LAUNCH PLAN — Lumina 2.5.10+58 |
| 48 | `audit/LEASE_EXPOSURE.md` | Markdown | internal (engineering audit) | 2026-08-01 | Tyler (sole committer) | 16525 | LEASE EXPOSURE ASSESSMENT |
| 49 | `audit/LEASE_LEDGER_MIGRATION.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 24841 | P0-9 — LEASE LEDGER TO FIRESTORE |
| 50 | `audit/LEASE_TRISTATE.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 15254 | P0-9 (part a) — TRI-STATE LEASE LOADING GATE |
| 51 | `audit/MULTICHANNEL_GAMEDAY_AUDIT_2026-10-02.md` | Markdown | internal (engineering audit) | 2026-10-02 | Tyler (sole committer) | 26546 | Game Day on a multi-channel system — why the channels do not match (audit) |
| 52 | `audit/MULTI_ENTRY_DISPLAY.md` | Markdown | internal (engineering audit) | 2026-08-11 | Tyler (sole committer) | 29700 | MULTI-ENTRY DAYS — only one entry shows |
| 53 | `audit/MY_DESIGNS_AUDIT.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 43780 | My Designs — Read-Only Audit |
| 54 | `audit/OFF_LAN_CAPABILITY.md` | Markdown | internal (engineering audit) | 2026-08-01 | Tyler (sole committer) | 41669 | OFF-LAN CAPABILITY — what the bridge carries, what it doesn't, and what that costs |
| 55 | `audit/ORIENTATION_ON_THE_WIRE.md` | Markdown | internal (engineering audit) | 2026-08-18 | Tyler (sole committer) | 16238 | ORIENTATION ON THE WIRE — `rev` was never fenced |
| 56 | `audit/P0-5_EXPOSURE.md` | Markdown | internal (engineering audit) | 2026-07-31 | Tyler (sole committer) | 17361 | P0-5 Live-Exposure Check |
| 57 | `audit/P0-6_FIX.md` | Markdown | internal (engineering audit) | 2026-07-31 | Tyler (sole committer) | 10130 | P0-6 — Controller migration failure surfacing |
| 58 | `audit/PARTICIPATION_REENTRY.md` | Markdown | internal (engineering audit) | 2026-08-18 | Tyler (sole committer) | 13660 | PARTICIPATION RE-ENTRY — #95's second half |
| 59 | `audit/PART_B_RESULTS.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 7793 | PART B — Design Studio slices 0-5, bench results |
| 60 | `audit/PRESET_FIX_REPORT.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 13799 | PRESET MASTER-ON FIX — IMPLEMENTATION REPORT |
| 61 | `audit/PRESET_REGRESSION.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 18273 | PRESET MASTER-ON ASSERTION — DIAGNOSIS |
| 62 | `audit/RELEASE_2.5.10+59.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 13485 | RELEASE 2.5.10+59 — preset master-power healing fix |
| 63 | `audit/RELEASE_READINESS.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 32580 | Lumina — Release Readiness Audit |
| 64 | `audit/ROOFLINE_SEGMENT_STACKING_AUDIT_2026-10-01.md` | Markdown | internal (engineering audit) | 2026-10-01 | Tyler (sole committer) | 15613 | Roofline segment "stacking" — audit and fix (+113) |
| 65 | `audit/S3B_CHANNELS.md` | Markdown | internal (engineering audit) | 2026-08-11 | Tyler (sole committer) | 29617 | S3b — DENORMALIZE RESOLVED PARTICIPATING CHANNELS |
| 66 | `audit/S3_DISPATCHER.md` | Markdown | internal (engineering audit) | 2026-08-09 | Tyler (sole committer) | 32779 | S3 — FIRE-JOB DISPATCHER |
| 67 | `audit/S4_RESTORE.md` | Markdown | internal (engineering audit) | 2026-08-11 | Tyler (sole committer) | 24345 | S4 — RESTORE, REVISED SCOPE |
| 68 | `audit/S5_GAMEDAY.md` | Markdown | internal (engineering audit) | 2026-08-11 | Tyler (sole committer) | 35138 | S5 — GAME DAY AS FIRE JOBS |
| 69 | `audit/SCHEDULE_V3_P2.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 27486 | SCHEDULING V3 — PHASE A (MODEL + TIMELINE) · PHASE B (EDITOR WIRING) · PHASE C (U-6 PROBE) |
| 70 | `audit/SCHEDULE_V3_P3.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 17881 | SCHEDULING V3 — PHASE D (F2: PER-CHANNEL FIRING) |
| 71 | `audit/SCHEDULING_ARCHITECTURE.md` | Markdown | internal (engineering audit) | 2026-08-01 | Tyler (sole committer) | 67608 | SCHEDULING ARCHITECTURE — a compositional plan model |
| 72 | `audit/SCHEDULING_ARCHITECTURE_V2.md` | Markdown | internal (engineering audit) | 2026-08-01 | Tyler (sole committer) | 52735 | SCHEDULING ARCHITECTURE — REVISION 2 |
| 73 | `audit/SESSION_CLOSEOUT_2026-08-03.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 8518 | SESSION CLOSEOUT — 2026-08-03 · 2.5.10+61 |
| 74 | `audit/SOLAR_BENCH_GATE.md` | Markdown | internal (engineering audit) | 2026-08-27 | Tyler (sole committer) | 31107 | Solar Bench Gate — WLED 0.15.1 @ <bench LAN address> |
| 75 | `audit/SOLAR_COMPARATOR.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 14569 | SOLAR — comparator, verification, flag |
| 76 | `audit/SOLAR_FAILURE.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 23151 | SOLAR SCHEDULING — Live Customer Failure Diagnosis |
| 77 | `audit/SOLAR_FIRING_PATH_AUDIT.md` | Markdown | internal (engineering audit) | 2026-08-27 | Tyler (sole committer) | 27540 | Solar Scheduling — How It Actually Fires |
| 78 | `audit/SOLAR_FIX.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 13299 | SOLAR FIX — implementation report |
| 79 | `audit/SOLAR_FIX_PLAN.md` | Markdown | internal (engineering audit) | 2026-08-03 | Tyler (sole committer) | 15371 | SOLAR FIX PLAN — locate the flag, then sequence the repair |
| 80 | `audit/SOLAR_PREP.md` | Markdown | internal (engineering audit) | 2026-08-27 | Tyler (sole committer) | 15794 | Solar Prep — predictor, port, recompute trigger, DST exposure |
| 81 | `audit/SOLAR_UI_GATE.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 10793 | SOLAR UI NOT UN-GATING — which gate is actually holding it closed |
| 82 | `audit/SPORTS_ALERTS_SYNC_AUDIT.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 14175 | Sports Alerts ↔ Game Day Sync Audit |
| 83 | `audit/SYNC_PACING_FIX_P1.md` | Markdown | internal (engineering audit) | 2026-08-25 | Tyler (sole committer) | 12338 | Controller Wedge — Pacing Fix (a)/(c)/(d) + Game Day Burst Sources |
| 84 | `audit/TEAM_CONSOLIDATION.md` | Markdown | internal (engineering audit) | 2026-08-09 | Tyler (sole committer) | 20416 | TEAM CONSOLIDATION — implementation |
| 85 | `audit/TEAM_SURFACES.md` | Markdown | internal (engineering audit) | 2026-08-09 | Tyler (sole committer) | 16097 | TEAM SELECTION SURFACES — audit before consolidating |
| 86 | `audit/TOKEN_REFRESH_REPORT.md` | Markdown | internal (engineering audit) | 2026-07-31 | Tyler (sole committer) | 21396 | Token Refresh + Anonymous-Fallback Instrumentation |
| 87 | `audit/U6_PSAVE_PROBE.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 6860 | U-6 — DOES WLED 0.15.1 PRESERVE PER-SEGMENT `on:false` THROUGH `psave`? |
| 88 | `audit/U7_ABSENT_SEGMENT_PROBE.md` | Markdown | internal (engineering audit) | 2026-08-24 | Tyler (sole committer) | 9443 | U-7 — ON `{"ps":N}`, WHAT HAPPENS TO A SEGMENT THAT IS ABSENT FROM THE PRESET? |
| 89 | `audit/UNATTENDED_OPERATION.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 79187 | UNATTENDED OPERATION — Game Day and Neighborhood Sync |
| 90 | `audit/VERIFICATION_REPORT.md` | Markdown | internal (engineering audit) | 2026-07-30 | Tyler (sole committer) | 22183 | VERIFICATION REPORT — bench hardware session |
| 91 | `audit/WINDOW_RECONCILIATION_2026-08-03.md` | Markdown | internal (engineering audit) | 2026-08-05 | Tyler (sole committer) | 7474 | TWO-WINDOW RECONCILIATION — 2026-08-03 |
| 92 | `bench/README.md` | Markdown | internal (engineering) | 2026-09-22 | Tyler (sole committer) | 7152 | bench/ — WLED bench verification harness (ledger M-21) |
| 93 | `demo_review_report.md` | Markdown | internal (engineering) | 2026-04-16 | Tyler (sole committer) | 35393 | Nex-Gen LED Demo Experience — Comprehensive Review |
| 94 | `docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md` | Markdown | internal (engineering) | 2026-09-29 | Tyler (sole committer) | 14160 | Accessibility text-scale testing |
| 95 | `docs/Admin_Operations_Guide.md` | Markdown | Nex-Gen staff | 2026-09-17 | Tyler (sole committer) | 39739 | Nex-Gen Lumina — Admin Operations Guide |
| 96 | `docs/Admin_Operations_Guide.pdf` | PDF render | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 674747 | (render of docs/Admin_Operations_Guide.md) |
| 97 | `docs/BUGS_AND_DEBT.md` | Markdown | internal (ledger / tracker) | 2026-10-06 | Tyler (sole committer) | 387358 | BUGS_AND_DEBT — canonical tracking ledger |
| 98 | `docs/BUG_BACKLOG.md` | Markdown | internal (ledger / tracker) | 2026-07-23 | Tyler (sole committer) | 469 | Lumina — Bug & Work Backlog |
| 99 | `docs/BUILD_LEDGER.md` | Markdown | internal (ledger / tracker) | 2026-10-06 | Tyler (sole committer) | 328954 | BUILD LEDGER — shipped artifact identity |
| 100 | `docs/CLEANUP_PLAN.md` | Markdown | internal (engineering) | 2026-07-09 | Tyler (sole committer) | 5443 | Schedules Dual-Write Cleanup Plan |
| 101 | `docs/DESIGN_STUDIO_REQUIREMENTS.md` | Markdown | internal (engineering) | 2026-04-21 | Tyler (sole committer) | 21587 | Design Studio — Feature Requirements |
| 102 | `docs/Dealer_Dashboard_Guide.md` | Markdown | dealer | 2026-09-17 | Tyler (sole committer) | 18404 | Nex-Gen Lumina — Dealer Dashboard Guide |
| 103 | `docs/Dealer_Dashboard_Guide.pdf` | PDF render | dealer | 2026-08-27 | Tyler (sole committer) | 408746 | (render of docs/Dealer_Dashboard_Guide.md) |
| 104 | `docs/Dealer_Installer_Setup_Guide.md` | Markdown | installer | 2026-09-17 | Tyler (sole committer) | 47522 | Nex-Gen Lumina — Dealer & Installer Setup Guide |
| 105 | `docs/Dealer_Installer_Setup_Guide.pdf` | PDF render | installer | 2026-08-27 | Tyler (sole committer) | 600981 | (render of docs/Dealer_Installer_Setup_Guide.md) |
| 106 | `docs/ESP32_Bridge_Setup_Guide.md` | Markdown | customer+installer | 2026-09-17 | Tyler (sole committer) | 18669 | Nex-Gen Lumina — Lumina Bridge Setup |
| 107 | `docs/ESP32_Bridge_Setup_Guide.pdf` | PDF render | customer+installer | 2026-08-27 | Tyler (sole committer) | 302919 | (render of docs/ESP32_Bridge_Setup_Guide.md) |
| 108 | `docs/Lumina_Homeowner_Guide.md` | Markdown | customer | 2026-09-17 | Tyler (sole committer) | 50115 | Lumina Homeowner Guide |
| 109 | `docs/Lumina_Homeowner_Guide.pdf` | PDF render | customer | 2026-08-27 | Tyler (sole committer) | 540910 | (render of docs/Lumina_Homeowner_Guide.md) |
| 110 | `docs/Media_Mode_Guide.md` | Markdown | customer | 2026-08-27 | Tyler (sole committer) | 7346 | Nex-Gen Lumina — Media Mode |
| 111 | `docs/Media_Mode_Guide.pdf` | PDF render | customer | 2026-08-27 | Tyler (sole committer) | 201839 | (render of docs/Media_Mode_Guide.md) |
| 112 | `docs/ROLLOUT_RUNBOOK.md` | Markdown | internal (engineering) | 2026-07-10 | Tyler (sole committer) | 4927 | Schedules Subcollection — Rollout Runbook |
| 113 | `docs/SPORTS_ALERTS_RESTRUCTURE_PLAN.md` | Markdown | internal (engineering) | 2026-08-16 | Tyler (sole committer) | 14436 | Sports-Alerts Restructure — plan of record |
| 114 | `docs/STREET_TEST_RUNBOOK.md` | Markdown | internal (engineering) | 2026-08-14 | Tyler (sole committer) | 4372 | Two-home street test — Neighborhood Sync crew fanout |
| 115 | `docs/SYNC_GEOMETRY_LAYER.md` | Markdown | internal (engineering) | 2026-08-14 | Tyler (sole committer) | 8085 | The Sync geometry layer — spec stub |
| 116 | `docs/User_Guide_Commercial.md` | Markdown | customer | 2026-09-17 | Tyler (sole committer) | 28972 | Nex-Gen Lumina — Commercial User Guide |
| 117 | `docs/User_Guide_Commercial.pdf` | PDF render | customer | 2026-08-27 | Tyler (sole committer) | 517792 | (render of docs/User_Guide_Commercial.md) |
| 118 | `docs/audits/AUDIT_assumption_gaps_2026-06.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 28795 | Overnight Audit 1 — Assumption-Gap Sweep (the catastrophic-after-release class) |
| 119 | `docs/audits/AUDIT_brand_polish_2026-06.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 29024 | AUDIT 6 — Brand & UI Polish Sweep |
| 120 | `docs/audits/BRIDGE_LATENCY_AUDIT_2026-05.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 19842 | Bridge Latency Audit — May 2026 |
| 121 | `docs/audits/BUG_VERIFY_2026-05.md` | Markdown | internal (engineering audit) | 2026-05-26 | Tyler (sole committer) | 20816 | Bug Verification Audit — 2026-05-25 |
| 122 | `docs/audits/CHANNEL_MAPPING_AUDIT_2026-05.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 54506 | Channel Mapping Audit — 2026-05-26 |
| 123 | `docs/audits/DESIGN_STUDIO_AUDIT_2026-07.md` | Markdown | internal (engineering audit) | 2026-07-02 | Tyler (sole committer) | 13299 | Design Studio — Architecture Audit & Build Blueprint (2026-07) |
| 124 | `docs/audits/FEATURE_COMPLETENESS_INVENTORY_2026-06.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 13859 | Feature-Completeness Inventory — Overnight Audit 4 |
| 125 | `docs/audits/PREVIEW_PARITY_AUDIT_2026-05.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 27246 | Preview Parity Audit — Pattern Detail vs Now Playing |
| 126 | `docs/audits/SCHEDULES_SUBCOLLECTION_MIGRATION_PLAN_2026-06.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 16069 | #TD-1 — Schedules → Subcollection Migration Plan |
| 127 | `docs/audits/SPLIT_SCHEDULE_GROUNDING_2026-05.md` | Markdown | internal (engineering audit) | 2026-05-26 | Tyler (sole committer) | 20145 | Split-Schedule Grounding — 2026-05-25 |
| 128 | `docs/audits/UI_POLISH_AUDIT_2026-05.md` | Markdown | internal (engineering audit) | 2026-06-17 | Tyler (sole committer) | 25579 | UI Polish Audit — 2026-05-25 |
| 129 | `docs/bridge_command_routing_context_2026-05-11.md` | Markdown | internal (engineering) | 2026-05-15 | Tyler (sole committer) | 21814 | Bridge / Remote-Access / Command Routing — Context Snapshot |
| 130 | `docs/commercial_mode_smoke_test.md` | Markdown | internal (engineering) | 2026-04-28 | Tyler (sole committer) | 6922 | Lumina Commercial Mode — Smoke Test Checklist |
| 131 | `docs/commercial_ux_audit.md` | Markdown | internal (engineering) | 2026-05-06 | Tyler (sole committer) | 47363 | Commercial UX Audit — Lumina |
| 132 | `docs/commercial_ux_phase_4a_decisions.md` | Markdown | internal (engineering) | 2026-08-27 | Tyler (sole committer) | 7685 | Phase 4a Decision Lock — 2026-05-06 |
| 133 | `docs/commercial_ux_phase_4b_audit.md` | Markdown | internal (engineering) | 2026-05-07 | Tyler (sole committer) | 33256 | Phase 4b Audit — Zone Management & Sub-User UI as Business Tools Entries |
| 134 | `docs/commercial_ux_phase_5_audit.md` | Markdown | internal (engineering) | 2026-05-07 | Tyler (sole committer) | 42032 | Phase 5 Audit — Sub-User Permissions & Commercial-Field Post-Install UI |
| 135 | `docs/corporate-dashboard-guide.md` | Markdown | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 18008 | Nex-Gen Corporate Dashboard — Guide |
| 136 | `docs/corporate-dashboard-guide.pdf` | PDF render | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 264615 | (render of docs/corporate-dashboard-guide.md) |
| 137 | `docs/day1-electrician-guide.md` | Markdown | installer | 2026-08-27 | Tyler (sole committer) | 10524 | Day 1 Electrician — Field Guide |
| 138 | `docs/day1-electrician-guide.pdf` | PDF render | installer | 2026-08-27 | Tyler (sole committer) | 170621 | (render of docs/day1-electrician-guide.md) |
| 139 | `docs/day2-install-guide.md` | Markdown | installer | 2026-08-27 | Tyler (sole committer) | 15606 | Day 2 Install Team — Field Guide |
| 140 | `docs/day2-install-guide.pdf` | PDF render | installer | 2026-08-27 | Tyler (sole committer) | 204436 | (render of docs/day2-install-guide.md) |
| 141 | `docs/dealer-inventory-guide.md` | Markdown | dealer | 2026-08-27 | Tyler (sole committer) | 11599 | Dealer Inventory Dashboard — Guide |
| 142 | `docs/dealer-inventory-guide.pdf` | PDF render | dealer | 2026-08-27 | Tyler (sole committer) | 161397 | (render of docs/dealer-inventory-guide.md) |
| 143 | `docs/dealer_preinstall_setup.md` | Markdown | dealer shop staff | 2026-07-30 | Tyler (sole committer) | 33492 | Dealer Pre-Install Setup SOP |
| 144 | `docs/dealer_preinstall_setup.pdf` | PDF render | dealer shop staff | 2026-07-30 | Tyler (sole committer) | 438019 | (render of docs/dealer_preinstall_setup.md) |
| 145 | `docs/design/controller_replacement.md` | Markdown | internal (engineering) | 2026-08-18 | Tyler (sole committer) | 33529 | Controller Replacement — Design |
| 146 | `docs/esp32_firmware_audit.md` | Markdown | internal (engineering) | 2026-05-07 | Tyler (sole committer) | 10675 | ESP32 Firmware Audit — Inventory Only |
| 147 | `docs/full-job-lifecycle.md` | Markdown | dealer | 2026-08-27 | Tyler (sole committer) | 33931 | Complete Job Lifecycle — From Prospect to Installed Customer |
| 148 | `docs/full-job-lifecycle.pdf` | PDF render | dealer | 2026-08-27 | Tyler (sole committer) | 505445 | (render of docs/full-job-lifecycle.md) |
| 149 | `docs/game_day_celebration_length_spec_2026-10-02.md` | Markdown | internal (engineering) | 2026-10-02 | Tyler (sole committer) | 13201 | Game Day celebration length: Short / Medium / Long |
| 150 | `docs/game_day_one_shot_vs_recurring_audit.md` | Markdown | internal (engineering) | 2026-05-15 | Tyler (sole committer) | 23698 | Game Day Feature Audit — One-Shot vs Recurring |
| 151 | `docs/game_time_display_audit_2026-05-08.md` | Markdown | internal (engineering) | 2026-05-08 | Tyler (sole committer) | 9989 | Game Time Display Audit — Item #63 |
| 152 | `docs/guides-2026-09/01-feature-overview.md` | Markdown | customer | 2026-09-17 | Tyler (sole committer) | 5731 | Beyond the Light. |
| 153 | `docs/guides-2026-09/02-homeowner-guide.md` | Markdown | customer | 2026-09-17 | Tyler (sole committer) | 27411 | Homeowner Guide |
| 154 | `docs/guides-2026-09/03-commercial-guide.md` | Markdown | customer | 2026-09-17 | Tyler (sole committer) | 10436 | Commercial Guide |
| 155 | `docs/guides-2026-09/04-installer-guide.md` | Markdown | installer | 2026-09-17 | Tyler (sole committer) | 15467 | Installer Guide |
| 156 | `docs/guides-2026-09/05-dealer-guide.md` | Markdown | dealer | 2026-09-17 | Tyler (sole committer) | 10723 | Dealer Guide |
| 157 | `docs/guides-2026-09/06-admin-guide.md` | Markdown | Nex-Gen staff | 2026-09-17 | Tyler (sole committer) | 13991 | Admin Operations Guide |
| 158 | `docs/guides-2026-09/07-bridge-setup-guide.md` | Markdown | customer+installer | 2026-09-17 | Tyler (sole committer) | 10799 | Lumina Bridge Setup |
| 159 | `docs/guides-2026-09/README.md` | Markdown | internal (guide index) | 2026-09-17 | Tyler (sole committer) | 6184 | Lumina How-To's — 2026.09 Refresh |
| 160 | `docs/hardcoded_identifier_audit_2026-05-08.md` | Markdown | internal (engineering) | 2026-05-15 | Tyler (sole committer) | 12266 | Hardcoded Identifier Audit — 2026-05-08 |
| 161 | `docs/lumina_design_pipeline_audit.md` | Markdown | internal (engineering) | 2026-05-07 | Tyler (sole committer) | 20361 | Lumina Design Pipeline Audit (Item #40) |
| 162 | `docs/lumina_split_schedule_audit.md` | Markdown | internal (engineering) | 2026-05-15 | Tyler (sole committer) | 21111 | Lumina Chat Split-Schedule Audit (Item #51) |
| 163 | `docs/memory_directory_verification.md` | Markdown | internal (engineering) | 2026-05-07 | Tyler (sole committer) | 16187 | Memory Directory Verification — 2026-05-06 |
| 164 | `docs/messaging-configuration-guide.md` | Markdown | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 17727 | Customer Messaging Configuration — Guide |
| 165 | `docs/messaging-configuration-guide.pdf` | PDF render | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 349645 | (render of docs/messaging-configuration-guide.md) |
| 166 | `docs/neighborhood_fanout_activation_runbook.md` | Markdown | internal (engineering) | 2026-08-12 | Tyler (sole committer) | 7511 | Neighborhood Sync crew fanout — activation runbook (P1-44) |
| 167 | `docs/nex-gen-operations-overview.md` | Markdown | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 17953 | Nex-Gen LED LLC — Operations Overview |
| 168 | `docs/nex-gen-operations-overview.pdf` | PDF render | Nex-Gen staff | 2026-08-27 | Tyler (sole committer) | 193881 | (render of docs/nex-gen-operations-overview.md) |
| 169 | `docs/project_preview_followups_2026_05_22.md` | Markdown | internal (engineering) | 2026-06-17 | Tyler (sole committer) | 10495 | Preview / Now Playing Follow-Ups — 2026-05-22 |
| 170 | `docs/sales-mode-guide.md` | Markdown | dealer | 2026-08-27 | Tyler (sole committer) | 24611 | Lumina Sales Mode — Complete Guide |
| 171 | `docs/sales-mode-guide.pdf` | PDF render | dealer | 2026-08-27 | Tyler (sole committer) | 294495 | (render of docs/sales-mode-guide.md) |
| 172 | `docs/submissions/BRIDGE_PHASE1_APP_AUDIT.md` | Markdown | internal (engineering audit) | 2026-04-23 | Tyler (sole committer) | 16513 | Bridge Phase 1 — App-Side Audit |
| 173 | `docs/submissions/DEMO_CODE_SCHEMA.md` | Markdown | internal (engineering audit) | 2026-04-21 | Tyler (sole committer) | 7184 | Demo Code Firestore Schema |
| 174 | `docs/submissions/HALFMOON_DIAGNOSIS.md` | Markdown | internal (engineering audit) | 2026-04-21 | Tyler (sole committer) | 16068 | Half-Moon Roofline Regression — APPLE-REVIEW demo path |
| 175 | `docs/submissions/NEIGHBORHOOD_SYNC_PERMISSION_DENIED_DIAGNOSIS.md` | Markdown | internal (engineering audit) | 2026-04-23 | Tyler (sole committer) | 17315 | Neighborhood Sync — "Permission denied" Diagnosis |
| 176 | `docs/submissions/REVIEWER_CONTROLLER_GATE.md` | Markdown | internal (engineering audit) | 2026-09-17 | Tyler (sole committer) | 14422 | Reviewer Controller Gate — Dashboard force-navigates to "Add Controller" |
| 177 | `docs/submissions/REVIEWER_GATE_DIAGNOSIS.md` | Markdown | internal (engineering audit) | 2026-04-21 | Tyler (sole committer) | 14258 | Reviewer Gate Diagnosis — `reviewer@Nex-GenLED.com` lands on `/link-account` |
| 178 | `docs/submissions/SUBMISSION_AUDIT_v1.0.0.md` | Markdown | internal (engineering audit) | 2026-04-21 | Tyler (sole committer) | 24118 | Lumina — App Store & Google Play Pre-Submission Audit |
| 179 | `docs/submissions/TEST_PROTOCOL_PHASE1.md` | Markdown | internal (engineering audit) | 2026-04-23 | Tyler (sole committer) | 12267 | ESP32 Bridge — Phase 1 Hardware Test Protocol |
| 180 | `docs/unified_preview_interpreter_design_2026-05-22.md` | Markdown | internal (engineering) | 2026-06-17 | Tyler (sole committer) | 34217 | Unified Preview Interpreter — Design Proposal |
| 181 | `docs/urgent_findings_overnight.md` | Markdown | internal (engineering) | 2026-05-07 | Tyler (sole committer) | 2414 | Urgent Findings — Overnight Audit Batch |
| 182 | `esp32-bridge/README.md` | Markdown | internal (engineering / deployment) | 2026-04-01 | Tyler (sole committer) | 2031 | Lumina ESP32 Bridge (Legacy — Firebase Polling) |
| 183 | `functions/test/emulator/README.md` | Markdown | internal (engineering) | 2026-10-04 | Tyler (sole committer) | 3575 | Emulator / rules integration tests |
| 184 | `google-home/DEPLOYMENT.md` | Markdown | internal (engineering / deployment) | 2026-01-29 | Tyler (sole committer) | 5624 | Google Smart Home Action Deployment Guide |
| 185 | `neighborhood_sync_audit_report.md` | Markdown | internal (engineering) | 2026-04-16 | Tyler (sole committer) | 30072 | Neighborhood Sync Feature — Comprehensive Audit |
| 186 | `scripts/preview_unification_design_2026-05-22.md` | Markdown | internal (engineering) | 2026-06-17 | Tyler (sole committer) | 30762 | Unified Preview Interpreter — Design (2026-05-22) |

## B. Documents present only on this PC (untracked in the main checkout; not on the release branch)

| Path | Audience | FS date | Bytes | What it is |
|---|---|---|---|---|
| `docs/CONTROLLER_HARDWARE_REQUIREMENTS.md` | internal / vendor-facing | 2026-08-26 | 16,913 | Controller requirements written against WLED 0.15.1; still carries the "fleet is pinned to 0.15.1" finding (lines 248–265). |
| `docs/AUDIT_APP_STRUCTURE_3FRONTS.md` | internal | 2026-08-12 | 59,451 | App-structure audit for the website and dealer-recruiting rewrite; §6 is the website-claims table (voice, "control from anywhere", warranty, store presence). |
| `docs/audits/apple-app-store-submission-audit-2026-09-17.md` | internal | 2026-09-17 | 46,909 | Apple submission audit (blockers B-1..B-4; store-listing and privacy-policy corrections owed). |
| `docs/audits/google-play-submission-audit-2026-09-17.md` | internal | 2026-09-17 | 60,362 | Play submission audit (data-safety inventory, 12-tester gate, listing assets). |
| `docs/guides-2026-09/*.md` (8 files) | as tracked | 2026-09-17 | — | LOCAL COPIES that differ from the tracked versions: `02-homeowner-guide.md` local says "+90" and "Alexa/Google still in development"; the tracked copy says "+98" and "the app's side works". `06-admin-guide.md`, `07-bridge-setup-guide.md`, `README.md` also differ in size. The tracked copies are the ones on origin. |
| `docs/ip/invention-disclosure-neighborhood-sync-and-game-day-2026-09-22.md` | internal (legal) | 2026-09-22 | 150,901 | Patent disclosure draft; not a guide; must never be committed to the public repo. |
| `audit/GAMEDAY_DIRECT_APPLY_WEDGE_AUDIT.md`, `GAMEDAY_E2E_AUDIT_2026-09-14.md`, `GAMEDAY_WEDGE_U1_U6.md`, `GAME_DAY_SCHEDULE_DEPENDENCY_AUDIT.md`, `LIGHT_UP_NOW_CRASH_AUDIT.md`, `NOW_PLAYING_CATEGORY_LEAK_AUDIT.md`, `OVERNIGHT_CRASH_LOGGING_AUDIT.md`, `OVERNIGHT_DATA_LIFECYCLE_AUDIT.md`, `OVERNIGHT_ERROR_SWALLOWING_AUDIT.md`, `OVERNIGHT_PRIVACY_AUDIT.md`, `OVERNIGHT_RELEASE_HYGIENE_AUDIT.md`, `OVERNIGHT_SECURITY_AUDIT.md`, `OVERNIGHT_TEST_DEBT_AUDIT.md`, `SCHEDULING_V3_AUDIT.md`, `SILENT_ERROR_PARSING_AUDIT.md`, `SOLAR_BENCH_GATE.md`, `SOLAR_FIRING_PATH_AUDIT.md`, `SOLAR_PREP.md`, `SPORTS_ALERTS_STILL_PRESENT_ON_84.md`, `SYNC_PACING_FIX_STATUS.md` (20 files) | internal (engineering audit) | 2026-08-24 … 2026-09-16 | ~470 KB | Engineering audits that were never committed; three (`SOLAR_*`) are local copies of tracked files. Not customer-facing. |
| `audit/sales-jobs-access-2026-09-23/results-*.txt` | internal | 2026-09-23 | 8 KB | Rules-test output. |

## C. In-app help and instructional copy (lib/ at c283d62)

Inventoried by a read-only sweep of every string that explains, instructs or blocks. About 586 copy surfaces in 18 areas (the full line-by-line list is in `audit/docs-overhaul-2026-10/inapp_surfaces.txt` — see the companion file). Summary by area, with the routes that carry help:

| Area | Surfaces | Where | Audience |
|---|---|---|---|
| Help Center / FAQ / Support / Version | 44 | `/settings/help` (HelpCenterScreen: 4 FAQs), Settings → Support & Resources (contact sheet, support request form, Video Tutorials link, Privacy Policy link), Take the Tour, Welcome Tutorial, Link Account contact card, version tile | customer |
| Voice assistants | 40 | `/settings/voice-assistants` (Siri, Google Home, Alexa, Home Assistant cards), Settings card with "New" badge, Simple Mode list, installer hand-off list | customer |
| Onboarding / first run / tour / demo | 39 | `/welcome`, `/first-run`, feature tour overlay (10 steps), BLE setup wizard, preferred-white selection, demo flow (8 screens) | customer |
| Blocked apply / connection / reconnect | 43 | `lib/shared/apply_blocked_reason.dart` (10 reasons), connection-status sheet (6 states), Now Playing bar, route badge (Direct / Via Bridge), channel bar | customer |
| Remote Access and bridge | 40 | `/settings/remote-access` (toggle, home-network card, webhook card, bridge status, "How Bridge Mode Works"), `/settings/bridge-setup` (Find / Pair / Verify) | customer, installer |
| Controller choice / adding controllers | 30 | System & Device Management → Controllers (Set as Active, Remove), `/settings/controllers`, manual setup (4-step AP how-to), discovery page | customer |
| Game Day | 55 | Game Day screen (intro, team card controls, alert sensitivity, team priority, crews), run-mode banner (server / phone / blocked), gate and pre-flight reasons, celebration picker, live-scoring prompt, base-layer gate dialog | customer |
| Ladder / preset repair / sync status | 24 | repair banner (fixed / partial / failed), schedule-sync warnings (slots full, solar conflict, off-LAN deferral, firmware mismatch) | customer |
| Schedule editor and hints | 46 | "+" editor (Just this day / Repeats weekly, actions), eviction picker, timer-slot meter, conflict and overload dialogs, clock-health messages and remediation, sunrise-off card | customer |
| Lumina AI chat | 46 | chat screen and bottom sheet (greeting, chips, placeholders by season/holiday/sport), dated-night and recurring replies, error table, mic availability | customer |
| Favorites / Recent Patterns / design card / Explore / My Designs | 35 | favorites-full dialog, grid tile menu, Recent Patterns card, tuner action bar, Static setup chips, save-to sheet, My Designs empty state | customer |
| Design Studio / roofline | 40 | Design Studio gate (5 states), Mark Your Roofline walkthrough, Trace Roofline, Refine Roofline, Segment Setup (installer lock), Roofline Setup Wizard (installer) | customer, installer |
| Settings misc / profile / account / hardware | 35 | Simple Mode, Mode tab, My Lights, Advanced Effects, Hardware Config, Audio Mode (debug only), Welcome Home geofence, properties, security and deletion, family invites, lifestyle profile | customer |
| Auth / account | 8 | login, password reset, forced reset, staff PIN, sign out | customer, staff |
| Neighborhood Sync | 13 | onboarding carousel, join crew, control panel, sync events, battery prompt | customer |
| Notifications | 6 | geofence, weekly brief, score alerts, sync pushes | customer |
| Installer / sales / dealer / corporate / media / inventory | 31 | installer landing and wizard, connection-method screen, hardware step, map-roofline step, sales wizard, dealer dashboard, messaging config, inventory and ordering, corporate admin | installer, dealer, staff |
| Commercial mode | 11 | commercial banner, onboarding wizard, schedule, events, brand library, fleet (all unreachable or orphaned) | commercial customer |

External links from the app: YouTube "Video Tutorials" (Settings), the privacy-policy web page, the Home Assistant WLED integration page, Alexa and Google store/deep links, the corporate website, referral and estimate links, carrier tracking (dealer). Help-like routes: `/settings/help`, `/settings/voice-assistants`, `/welcome`, `/first-run`, `/setup/wizard`, `/settings/remote-access`, `/settings/bridge-setup`, `/roofline-setup-wizard`, `/installer/wizard`, `/demo…`, `/link-account`, `/join-with-code`, `/first-week-reveal`.

## D. Google Drive (read-only listing; the connector reached these)

| Location | Audience | Modified | Owner account | What it is |
|---|---|---|---|---|
| Shared drive folder **"Lumina How-To's"** (13 PDFs) | customer / installer / dealer / staff | 2026-08-27 (one 2026-08-17) | work account | PDF copies of `Lumina_Homeowner_Guide`, `Dealer_Installer_Setup_Guide`, `ESP32_Bridge_Setup_Guide`, `Admin_Operations_Guide`, `Dealer_Dashboard_Guide`, `User_Guide_Commercial`, `Media_Mode_Guide`, `corporate-dashboard-guide`, `day1-electrician-guide`, `day2-install-guide`, `dealer-inventory-guide`, `messaging-configuration-guide`, `sales-mode-guide`. Their byte sizes differ from the repo PDFs of the same date (different renders), and both predate the 2026-09-17 Markdown edits. The Admin Operations Guide PDF carries the PIN values (security item S1). |
| Shared drive root: `Dealer_Dashboard_Guide.pdf`, `Admin_Operations_Guide.pdf` | dealer / staff | 2026-04 | work account | Older stale copies of two guides. |
| Shared drive root: `Lumina_Privacy_Policy.docx` | customer (public web page source) | 2026-04-01 | work account | The privacy policy. Claims checked: "available on the Apple App Store and Google Play Store" (wrong, T-O8); "disable usage analytics through the App's settings" (wrong, T-O4); "firmware update alerts" (no such feature); "delete … within 30 days" (deletion scope UNVERIFIED); a `General@` mailbox (fourth support-address variant). |
| Shared drive root: `Lumina_Capture_Brief.pdf` | internal one-off (addressed to a named helper) | 2026-08-02 | work account | App Store screenshot/video brief for build 60; not a guide; names a person. |
| Shared drive folder "Dealer Development" | dealer / internal | 2026-03 … 2026-04 | personal account | Website prompts (.docx), an NDA, a dealer information sheet, vendor/SKU sheet, dealer-application responses, an "Inventory Documents" folder. Business documents, not product how-tos. |
| Shared drive folder for one dealer's files | dealer / internal | 2026-07 … 2026-08 | work account | Two order/invoice example spreadsheets. Not how-tos. |
| **NEX-GEN Hub** → "Lumina Dealer Docs and How-To's" | — | created 2026-08-27 | personal account | EMPTY (no children returned). |
| NEX-GEN Hub → "Inventory Tools" | dealer / internal | 2025-10 … 2026-09 | personal account | Order sheet, a demo order sheet, cost/profit example, "Expired Inventory Forms", a dealer sub-folder. Not how-tos. |
| NEX-GEN Hub → "Logo, Icons, Media" | marketing | 2025-10 … 2026-09 | personal account | Logos, yard signs, photo/video folders, a "web" folder (not listed further). |
| NEX-GEN Hub → "Warranty/Contract/Estimate Docs" | customer / dealer | created 2025-10 | personal account | EMPTY (no children returned). |

## E. Outside the repo and Drive — not reachable from here; export list for the owner

| Item | Why it matters | What to export |
|---|---|---|
| App Store Connect listing (name, subtitle, description, keywords, What's New, App Privacy answers, screenshots) | Any mention of Alexa/Google, "control from anywhere", "download", warranty | Copy the text fields into `docs/drive-exports/store-listing-ios.md` |
| Play Console listing (short/long description, release notes per track, Data safety form answers, feature graphic text) | Same | `docs/drive-exports/store-listing-android.md` |
| TestFlight "What to Test" notes and tester emails for builds 110–116 | Tester messages are part of the release-notes set | Paste into `docs/guides/internal/31-release-notes.md` |
| Website pages at nex-genled.com: home, product/features, "Voice Activated", "Control from Anywhere", warranty, dealer recruiting, privacy policy page, any "download the app" call to action | The 2026-08-12 audit found claims the product does not meet (voice, permission levels, zero maintenance, store presence) | Export each page's text to `docs/drive-exports/website-<page>.md` |
| Any printed or emailed customer leave-behind (welcome card, QR card, install-day handout) | Not in the repo or Drive listing | Scan or paste |
| Dealer-site pages (if a dealer portal exists outside this repo) | Unknown | List the URLs |
| The YouTube "Video Tutorials" playlist linked from Settings | Content and currency unknown | List the videos and their recording build |

## F. Release notes and tester messages found

- `CHANGELOG.md` — last entry 2.1.0, 2026-03-10; describes features by their old names (Simple Mode removed, "For You strip", Sync Events). Stale.
- `docs/BUILD_LEDGER.md` rows +112, +114, +115, +116 — each carries a "Tester text (return to N)" paragraph and a rollback note; these are the only current release notes.
- `functions/src/onSalesJobStatusChanged.ts:40,42` — customer emails that link to store pages with placeholder app ids.
