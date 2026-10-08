# Security items found in documents (report only — the history cleanup is a separate branch)

Rule: file and line and KIND only. No values are reproduced here or anywhere in this overhaul. The repository is public, so every item below is already exposed on origin unless the file is untracked (marked). Items are grouped by what a reader could do with them.

## S-A. Credentials and secrets (P1)

| # | Location | Kind | Note |
|---|---|---|---|
| S1 | `docs/Admin_Operations_Guide.md:45,58,59,61,68,74,114,131,246,252,634,653,691,692` | live staff / master / dev PIN values | 14 lines; line 74 holds two values. The same text is rendered into `docs/Admin_Operations_Guide.pdf` (tracked) and the PDF of the same name in the Drive "Lumina How-To's" folder (2026-08-27) and at the shared-drive root (2026-04). The September admin draft (`docs/guides-2026-09/06-admin-guide.md:24-26`) already states that any copy carrying PIN values is a security incident. |
| S2 | `audit/P0-5_EXPOSURE.md:111,120,122`; `audit/INSTALLER_ENTRY.md:164`; `audit/HARDWARE_VERIFICATION_+60.md:36,78`; `audit/TOKEN_REFRESH_REPORT.md:330`; `docs/hardcoded_identifier_audit_2026-05-08.md:70` | PIN values | Internal audits that quote a PIN. |
| S3 | `docs/dealer_preinstall_setup.md:170,181` | controller setup-AP password value | Also rendered into `docs/dealer_preinstall_setup.pdf`. |
| S4 | `docs/Dealer_Installer_Setup_Guide.md:537` | sample temporary password in a UI mock | Rendered into its PDF and the Drive copy. |
| S5 | `docs/submissions/BRIDGE_PHASE1_APP_AUDIT.md:58` | historical bridge credential | Two redaction commits (`c13b281`, `df6063b`) exist on the main checkout but are NOT on the release branch; line 58 still carries the value at `c283d62`. The memory note "redactions never reached origin" applies: rotate, do not rely on history rewrites. |
| S6 | `functions/index.js:652,1601` | literal Google/Firebase web API key | Inside the Alexa/Google link-page HTML. A web key is a client key, but it is unrestricted here and the same key is the billable Places key noted in the Play audit. |
| S7 | `android/app/src/main/AndroidManifest.xml:110` | literal Google API key (Maps meta-data) | Expected location for a Maps key; confirm it is restricted to the Android package and SHA. |
| S8 | `audit/COMPLIANCE_AND_SECURITY.md:473` | records that the project's password-hash signer key was read; recommends rotation | Value not present; the recommendation is still open. |
| S9 | `audit/CONTROLLER_HEALTH.md:710` | truncated mail-provider API-key prefix | Four characters; low. |
| S10 | `esp32-bridge/src/config.h.example:18,31,40`; `google-home/DEPLOYMENT.md:26,28`; `alexa-skill/DEPLOYMENT.md:55,57`; `scripts/.env.example:8` | placeholders | Fine as placeholders; listed so the guard can allow-list them. |

## S-B. Customer identities and home-network details (P1 — privacy)

| # | Location | Kind |
|---|---|---|
| S11 | `audit/BRIDGE_TRIAGE.md` (names ~55 lines; emails 19 lines; LAN IPs 24 lines; bridge ids 27 lines; uids 3 lines) | customer names, personal emails, home LAN addresses, bridge ids, uids |
| S12 | `audit/UNATTENDED_OPERATION.md` (names ~28 lines; emails 14; LAN IPs 11; bridge ids 10; uids 8) | same |
| S13 | `audit/CONTROLLER_HEALTH.md` (names 21; emails 14; LAN IPs 12; bridge ids 9; uids 3) | same |
| S14 | `audit/COMMAND_SAFETY.md` (names 13; LAN IPs 15; uids 15; email 1) | same |
| S15 | `audit/P0-5_EXPOSURE.md` (emails 10; uids 23; controller doc ids 2) | same |
| S16 | `audit/SOLAR_FAILURE.md:3` and ~22 more lines; `audit/ELLIE_SUNSET.md:3` and ~18 more lines (the FILENAME carries a customer first name) | customer name, uid, personal email, home LAN |
| S17 | `audit/LEASE_EXPOSURE.md` (uids 6; names 13; email 1); `audit/BASE_LAYER_GATE.md` (names 12); `audit/SOLAR_COMPARATOR.md` (10); `audit/SOLAR_FIX_PLAN.md` (10); `audit/ALL_STUB_CLOBBER.md` (9); `audit/SOLAR_FIX.md` (8); `audit/S5_GAMEDAY.md` (6); `audit/ALL_STUB_GUARD.md` (5); `audit/BASE_LADDER.md` (5); `audit/SESSION_CLOSEOUT_2026-08-03.md` (5); `audit/DIAGNOSTICS_FIX.md` (4 + uids 3); `audit/LEASE_LEDGER_MIGRATION.md` (3 + uid 1); `audit/TEAM_CONSOLIDATION.md` (emails 4); `audit/TEAM_SURFACES.md` (emails 2); `audit/S4_RESTORE.md` (emails 2); `audit/HANDOFF_TO_WINDOW_B.md` (uids 4); `audit/HEALER_PUBLISH.md:389`, `audit/PARTICIPATION_REENTRY.md:49`, `audit/S3B_CHANNELS.md:198,230` (uid + LAN in doc-id form); `audit/SCHEDULE_V3_P2.md:69,133`; `audit/BLOCK_E_MISSING_ROW.md:4`; `audit/GAMMA_BUG.md:3,293` (controller MAC) | customer names / emails / uids / ids |
| S18 | `docs/STREET_TEST_RUNBOOK.md:16,19,20,21,34,44,54,56,62,71,78,84,91` | two customers' names, uids and a home LAN address |
| S19 | `docs/lumina_split_schedule_audit.md` (19 lines), `docs/game_day_one_shot_vs_recurring_audit.md` (18), `docs/game_time_display_audit_2026-05-08.md` (5), `docs/audits/AUDIT_assumption_gaps_2026-06.md` (5), `docs/commercial_ux_phase_5_audit.md` (4), `docs/commercial_ux_audit.md` (2), `docs/commercial_ux_phase_4b_audit.md` (2), `docs/lumina_design_pipeline_audit.md` (2), one line each in `docs/commercial_ux_phase_4a_decisions.md`, `docs/audits/FEATURE_COMPLETENESS_INVENTORY_2026-06.md`, `docs/memory_directory_verification.md`, `docs/urgent_findings_overnight.md` | possible customer or commercial-contact names |
| S20 | `functions/src/collectControllerHealth.ts:13,171,208,636` | customer names and a personal-email fragment in code comments (the precedent the PII memory note says to stop) |
| S21 | `scripts/brands_to_seed.json:1700,1720` | commercial-customer brand seed entries naming businesses |
| S22 | `docs/dealer_preinstall_setup.md:344,506` | real-looking bridge id used as an example |
| S23 | `docs/Admin_Operations_Guide.md:777`; `audit/BRIDGE_TRIAGE.md:197`; `audit/P0-5_EXPOSURE.md:114,226` | controller document ids with a real MAC prefix |
| S24 | `audit/COMMAND_SAFETY.md:461`; `audit/LEASE_EXPOSURE.md:6`; `audit/P0-5_EXPOSURE.md:5`; `audit/SOLAR_FIX_PLAN.md:13` | the owner's personal email |
| S25 | `audit/BLOCK_E_MISSING_ROW.md:4`; `audit/BRIDGE_TRIAGE.md:134,146`; `audit/CONTROLLER_HEALTH.md:707,893`; `audit/P0-5_EXPOSURE.md:52`; `audit/UNATTENDED_OPERATION.md:378` | individual staff emails |
| S26 | `services/reviewer_seed_service.dart:18` (lib/); `docs/submissions/REVIEWER_GATE_DIAGNOSIS.md:1,25,102,195` | the App Store reviewer account identity |
| S27 | `lib/features/installer/screens/customer_info_screen.dart:423` | a 4-digit gate-code literal in hint text — PII if it is a real customer's |
| S28 | Untracked, main tree only: `audit/*OVERNIGHT*`, `audit/GAMEDAY_*`, `audit/SOLAR_*` (local copies), `docs/AUDIT_APP_STRUCTURE_3FRONTS.md`, `docs/ip/…` (150 KB invention disclosure) — not scanned line by line here; the two store-submission audits name the legacy bridge account identities at `docs/audits/google-play-submission-audit-2026-09-17.md:319,650` | must be scanned before any of them is ever committed |

## S-C. Internal addresses and infrastructure detail (P2)

| # | Location | Kind |
|---|---|---|
| S29 | Owner bench/home LAN addresses in ~40 `audit/*.md` files (list in the sweep: ALL_STUB_CLOBBER:3 … VERIFICATION_REPORT:4), `bench/README.md:18`, `bench/config.json:2`, `codemagic.yaml:71`, `docs/ROLLOUT_RUNBOOK.md:92`, `docs/audits/DESIGN_STUDIO_AUDIT_2026-07.md:6,85,184`, `docs/neighborhood_fanout_activation_runbook.md:94`, `docs/SPORTS_ALERTS_RESTRUCTURE_PLAN.md:229`, `docs/project_preview_followups_2026_05_22.md:230`, `docs/unified_preview_interpreter_design_2026-05-22.md:494`, `docs/submissions/REVIEWER_CONTROLLER_GATE.md:209`, `docs/submissions/SUBMISSION_AUDIT_v1.0.0.md:237`, `TASK_TEST_PLAN.md:23` | private LAN addresses of the owner's home rig |
| S30 | A stray tracked file at the repo root whose name is a mangled Windows temp path (`C<U+F03A>Users…wled_config.json`) | a full WLED configuration dump: station Wi-Fi SSID value, AP settings, an mDNS name with a MAC suffix |
| S31 | `audit/verification_evidence/*.json` | WLED cfg dumps with mDNS MAC-suffix names (SSID is a placeholder) |
| S32 | `audit/RELEASE_READINESS.md:28,339` | keystore filename, expiry and algorithm |
| S33 | `firebase.json:6,13,7,15-17`; `functions/index.js:653`; several `docs/submissions/*` lines | Firebase project id and app ids (not secrets; listed for completeness) |

## S-D. Company mailboxes (not secrets; inventory for the support-contact decision)

Nine distinct support-style addresses appear across documents (`docs/guides-2026-09/README.md:94-95` lists three; the sweep found `support@` on two domains and a third top-level domain, plus `security@`, `privacy@`, `payouts@`, `media@`, `info@`, and `General@` in the privacy policy). The app ships exactly one corporate email constant. Decision needed: T-SU2.

## What to do with this list (not done in this overhaul)

1. Rotate: S1 (every PIN that appears), S3 (the AP password on every fielded controller — a bench/installer job), S5 (bridge credential, already recommended), S6/S7 (restrict or rotate the keys), S8 (signer key).
2. Remove from the tree on the security branch: S1–S5 values, S11–S27 identities, S30, and move the owner-LAN audits (S29) to the archive with addresses masked.
3. Pull from Drive: the Admin Operations Guide PDF (two copies) until a PIN-free render replaces it.
4. The docs guard proposed in Phase 2 (c) blocks every one of these patterns under docs/ going forward.
