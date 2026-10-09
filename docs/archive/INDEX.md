# Archive index

Files here were superseded on 2026-10-09 by the guide set in `docs/guides/` and the facts file `docs/FACTS.md`. Each archived file carries an ARCHIVE NOTE at the top naming its replacement. Nothing in this folder is maintained; statements in these files may be wrong. Git history holds every earlier version.

Rule: a document is never silently deleted. It is moved here with a note, or (for PDF renders) removed from the tree because its Markdown source is the record.

## Guides from August 2026 (`guides-2026-08/`, previously at `docs/`)

| Archived file | Replaced by |
|---|---|
| `Lumina_Homeowner_Guide.md` | `docs/guides/customer/` (pages 00–07) |
| `User_Guide_Commercial.md` | `docs/guides/customer/` (commercial customers use the standard app) |
| `Media_Mode_Guide.md` | nothing; Media Mode is not reachable in the shipped app |
| `Dealer_Installer_Setup_Guide.md` | `docs/guides/installer/10-install-checklist.md`, `11-controller-setup.md`, `12-bridge-guide.md`; dealer sections in `docs/guides/dealer/20-dealer-guide.md` |
| `dealer_preinstall_setup.md` | `docs/guides/installer/13-installer-sop.md` |
| `ESP32_Bridge_Setup_Guide.md` | `docs/guides/installer/12-bridge-guide.md` |
| `Dealer_Dashboard_Guide.md` | `docs/guides/dealer/20-dealer-guide.md` |
| `dealer-inventory-guide.md` | `docs/guides/dealer/20-dealer-guide.md` (Inventory) |
| `messaging-configuration-guide.md` | `docs/guides/dealer/20-dealer-guide.md` (Messaging) |
| `full-job-lifecycle.md` | `docs/guides/dealer/20-dealer-guide.md` and `21-sales-mode.md` |
| `sales-mode-guide.md` | `docs/guides/dealer/21-sales-mode.md` |
| `day1-electrician-guide.md`, `day2-install-guide.md` | `docs/guides/dealer/20-dealer-guide.md` (queues, deposit gate) and `docs/guides/installer/10-install-checklist.md` |
| `Admin_Operations_Guide.md` | `docs/guides/internal/30-admin-operations.md` (PIN values in the archived copy are redacted; they had already been rotated on 2026-08-29) |
| `corporate-dashboard-guide.md` | `docs/guides/internal/30-admin-operations.md` |
| `nex-gen-operations-overview.md` | `docs/guides/README.md` and `docs/guides/internal/33-claims-policy.md` |

The 16 PDF renders that sat beside these files (`docs/*.pdf`, rendered 2026-08-27 from older text) are removed from the tree. Replacement renders are produced from `docs/drive-exports/` when the owner uploads them.

## Guides drafted September 2026 (`guides-2026-09/`, previously at `docs/guides-2026-09/`)

| Archived file | Replaced by |
|---|---|
| `01-feature-overview.md` | `docs/guides/internal/33-claims-policy.md` (what may be claimed) and the customer pages |
| `02-homeowner-guide.md` | `docs/guides/customer/` |
| `03-commercial-guide.md` | `docs/guides/customer/` |
| `04-installer-guide.md` | `docs/guides/installer/` |
| `05-dealer-guide.md` | `docs/guides/dealer/20-dealer-guide.md` |
| `06-admin-guide.md` | `docs/guides/internal/30-admin-operations.md` |
| `07-bridge-setup-guide.md` | `docs/guides/installer/12-bridge-guide.md` |
| `README.md` | `docs/guides/README.md`; its grounding notes are now rows in `docs/FACTS.md` |

## Drafts and reports from the repository root (`root-drafts/`)

| Archived file | Why | Replaced by |
|---|---|---|
| `CHANGELOG.md` | stopped at 2.1.0 (March 2026) | `docs/guides/internal/31-release-notes.md` |
| `SECURITY_SUMMARY.md` | January snapshot naming the wrong AI vendor, limits and files | `SECURITY.md` (corrected in place) |
| `LANDINGSITE_AI_PROMPTS.md` | dictates false privacy and data-safety claims (DO NOT USE) | `docs/guides/internal/33-claims-policy.md` |
| `ANALYTICS_SYSTEM.md`, `LEARNING_SYSTEM.md`, `INTEGRATION_COMPLETE.md`, `GUIDED_MODE_IMPLEMENTATION.md` | January implementation notes; the features changed or were removed | `docs/FACTS.md` |
| `demo_review_report.md`, `neighborhood_sync_audit_report.md`, `TASK_TEST_PLAN.md` | dated reviews and test plans | — |

## Engineering records archived in place

These stay where they are, with a README in each folder saying they are historical. They are not fact-checked line by line and must not be used as instructions.

- `audit/` — 79 engineering audits and reports, July–October 2026. Several carry bench-rig details from the time; the security branch handles identities and addresses inside them.
- `docs/audits/` — 11 audits, May–July 2026.
- `docs/submissions/` — 8 store-submission diagnoses, April and September 2026.
- Dated design notes and plans still under `docs/`: `bridge_command_routing_context_2026-05-11.md`, `commercial_mode_smoke_test.md`, `commercial_ux_*`, `design/controller_replacement.md`, `esp32_firmware_audit.md`, `game_day_celebration_length_spec_2026-10-02.md`, `game_day_one_shot_vs_recurring_audit.md`, `game_time_display_audit_2026-05-08.md`, `hardcoded_identifier_audit_2026-05-08.md`, `lumina_design_pipeline_audit.md`, `lumina_split_schedule_audit.md`, `memory_directory_verification.md`, `neighborhood_fanout_activation_runbook.md`, `project_preview_followups_2026_05_22.md`, `unified_preview_interpreter_design_2026-05-22.md`, `urgent_findings_overnight.md`, `CLEANUP_PLAN.md`, `DESIGN_STUDIO_REQUIREMENTS.md`, `ROLLOUT_RUNBOOK.md`, `SPORTS_ALERTS_RESTRUCTURE_PLAN.md`, `STREET_TEST_RUNBOOK.md`, `SYNC_GEOMETRY_LAYER.md`, `BUG_BACKLOG.md`.
- Living engineering files that are NOT archived: `docs/BUILD_LEDGER.md`, `docs/BUGS_AND_DEBT.md`, `docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md`, `CLAUDE.md`, `SECURITY.md`, `bench/README.md`, `functions/test/emulator/README.md`, `esp32-bridge/README.md` (now a pointer), `alexa-skill/DEPLOYMENT.md` and `google-home/DEPLOYMENT.md` (now status pages).
