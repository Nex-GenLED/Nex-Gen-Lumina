# Phase 6 — owner decisions of 2026-10-12 applied (documents only, plus one read-only audit)

Branch `docs/overhaul-2026-10`, on top of the Phase 5 head `9737095` (the Friday 2026-10-09 follow-up had landed: mailbox, setup access point, outputs, Drive swap; this phase builds on it). Documents and the docs tooling only: no app code, no `codemagic.yaml` change, no version bump, no tag, no merge, no build, test or analyzer, nothing written to any controller, bridge, Firestore document, configuration or Google Drive, no command of any kind to any controller. Every decision is in `docs/FACTS.md` as "decided by owner" with the date; what is not verified is marked UNVERIFIED.

## A. We are not electricians (FACTS T-W1 to T-W6)

**Searched** (electrician, electrical, licensed, certified, qualified, line voltage, mains, hardwire, building/electrical code, permit, inspection, high voltage, 120 V, breaker, circuit, outlet, GFCI, junction box, conduit) across every maintained document, every file in `docs/drive-exports/`, both checklists, the store-listing and website notes, the privacy corrections, the tester text in the release notes, `docs/submissions/`, `docs/overhaul-2026-10/`, `README.md`, `CLAUDE.md`, `SECURITY.md`, and the app's own strings under `lib/` and `functions/` (plus the `lumina-voice` mirror).

**Every hit in the maintained set and what was done with it:**

| Hit | Decision |
|---|---|
| `docs/drive-exports/day1-electrician-guide.md` (the export's file name and its line 3 naming the Drive file) | Removed. One combined field guide now exports as `Field_Guide_Day1_Day2.md`; the Drive checklist keeps the old Drive file name only as the file to remove (row A6) and says the name is not reused. |
| `docs/drive-exports/day2-install-guide.md` (its twin) | Removed; same replacement. |
| `docs/drive-exports/README.md:11`, `DRIVE_SWAP_CHECKLIST.md:16, 42, 59` | Reworded to the new export name; rows A6/A7, section C and the upload order updated. |
| `docs/guides/customer/05-power-outage-and-recovery.md:31` ("Check the controller's power supply and the outlet it is on"); `06-troubleshooting.md:9` ("Is the controller plugged in and its outlet on?") and their exports | **Kept** as safety and troubleshooting information: the customer checks their own outlet; no statement about our work. |
| `docs/guides/dealer/20-dealer-guide.md:28` (pipeline statuses "pre-wire scheduled → pre-wire complete") | **Kept**: these are the app's status labels, and "pre-wire" is the low-voltage pre-install. A sentence now defines Day 1 and Day 2 and carries the not-our-work statement. |
| Store-listing notes, privacy corrections, release notes / tester text, `SECURITY.md`, `README.md`, `CLAUDE.md` | 0 hits. |
| `docs/submissions/DEMO_CODE_SCHEMA.md:47`, `NEIGHBORHOOD_SYNC_PERMISSION_DENIED_DIAGNOSIS.md:220, 240` | Matched "inspection" only (console inspection, code inspection). Archived-in-place engineering notes; **kept**. |
| `docs/overhaul-2026-10/00_INVENTORY.md`, `02_FINDINGS.md`, `06_TOPIC_SWEEP.txt`, `08–10_findings_*.txt`, `PHASE2_PROPOSAL.md:76` | Phase 1 audit records that quote the old documents by name; **kept** as the record of what was found (they make no claim). |
| `docs/archive/**` (about 60 hits across the August and September guides) | Archived, not maintained, left as instructed; every file carries the archive note. |

**Guard.** `scripts/docs_guard.mjs` now bans the trade word outright and "electrical work / pre-wire / team / crew / visit" (a sentence that negates it, "we do no electrical work", passes). `docs/guides/internal/33-claims-policy.md` has the matching row and an "Always say" line.

**A1, the sentence.** Every guide that touches the subject says, in these words: "Nex-Gen LED and its dealers do the low-voltage wiring and the pre-install. We do no electrical work. Where a job involves line-voltage power (power to the power-supply location, a new outlet, a circuit, a breaker, hardwiring), Nex-Gen LED does not perform that work; the customer arranges it through a licensed professional of their own choosing." That is the only place a licensed professional is mentioned; no trade is named anywhere in the maintained set.

**A2, the boundary.** Recorded as the owner's statement, UNVERIFIED (T-W3), with the seven edge cases listed as questions (OWNER DECISION block 2 below). No guide answers them; the install checklist and the SOP tell installers not to improvise on site.

**A3, warranty / terms / liability / insurance / licensing.** Not rewritten. Hits and proposals are in OWNER DECISION block 1. Whether a license or insurance requirement applies to low-voltage lighting installation in Missouri or California is UNVERIFIED (T-W4) and a question for the owner.

**A4, in-app strings (file:line, no code changed).** Added to `APP_STRINGS_PROPOSAL.md` as item 29, ranked P1:

User-visible:
- `functions/src/onSalesJobStatusChanged.ts:212` (text) and `:239` (HTML): "Step 1 — Day 1: Our electrician visits to run all wiring. No lights go up on this day." · `:219`, `:251`: "your electrical panel" (the booking email every customer receives).
- `functions/src/sendInstallReminders.ts:274–275`: Day 1 reminder text "…to run all wiring. Please make sure we have access to: your electrical panel, garage or utility area, and exterior eaves." · `:344`: Day 2 reminder "No electrical access needed tomorrow".
- `lib/features/sales/screens/dealer_messaging_config_screen.dart:350–353`: the Messaging tab's live preview of the same reminder.
- `lib/features/sales/screens/estimate_preview_screen.dart:498` "Day 1 — Electrical pre-wire" · `lib/features/sales/screens/visit_review_screen.dart:484` same · `lib/features/sales/screens/job_detail_screen.dart:211` "Day 1 — Electrical" · `lib/features/sales/services/pdf_service.dart:130` "Day 1 — Pre-wire & Electrical", `:285` "New outlet" / "Electrician install" · `lib/features/sales/services/install_plan_service.dart:87` task category "Electrician".
- Unreachable estimate wizard (T-X8): `lib/features/sales/screens/estimate_wizard/wizard_step2_controller.dart:119` "The Day 1 electrician will run wire to this location.", `:126` hint "near breaker panel" · `wizard_step4_injections.dart:561` "Adds an electrician task to Day 1".
- `lib/features/installer/installer_lock_screen.dart:75` "…is only available to certified installers." (Nex-Gen's own term; OWNER DECISION block 3.)
- The `Icons.electrical_services` icon on the Day 1 rows (listed in item 29).

Comments only, not user-visible: `lib/app_router.dart:526, 1182`; `lib/features/sales/models/sales_models.dart:1189, 1195`; `lib/features/sales/sales_providers.dart:211`; `lib/features/sales/screens/blueprint_widgets.dart:23`; `customer_signature_screen.dart:91`; `day1_blueprint_screen.dart:15`; `day1_queue_screen.dart:14`; `lib/features/sales/services/sales_job_service.dart:169`; `material_calculation_service.dart:12`; `install_plan_service.dart:65`; `lib/features/installer/installer_lock_screen.dart:10`; `lib/models/user_role.dart:14` ("Certified"); `functions/src/probeControllerHealth.ts:65` ("mains-powered"). The compiled copies under `functions/lib/` and the `lumina-voice` checkout mirror the sources and regenerate on build.

## B. The install family, rebuilt

Maintained install-family documents (listed first, as asked):

1. `docs/guides/installer/13-installer-sop.md` — the dealer pre-install setup guide (bench SOP). **Rebuilt**: "Not our work" box; "The pre-install, in order" (record → line-voltage confirmed as the customer's → bench prep controller and bridge → Day 1 low-voltage wiring → install day); Sections 1–4 kept with every verified statement, every earlier decision and every UNVERIFIED flag; a new troubleshooting row for "no power at the power-supply location"; the firmware section now also says the controller's own page offers an update and that the app never checks the version.
2. `docs/guides/installer/10-install-checklist.md` — the install checklist. **Rebuilt** as Not our work → Pre-install (the dealer, before install day: record, line-voltage status, deposit gate, Day 1 wiring, bench prep, PIN and phone, Wi-Fi) → Install day (at the controller; in the app; bridge) → Handoff (what the customer gets: account and invitation, their phone signed in, the five things shown, the homeowner guide and the final payment, nothing on paper with a secret) → Before you leave.
3. `docs/guides/customer/00-getting-started.md` — the customer-facing install page. **Added** "What your installer did" with the not-our-work sentence in customer words and the firmware line.
4. `docs/guides/installer/11-controller-setup.md` — outputs, channels, roofline. Firmware section extended with verified statements only; record and print-form references.
5. `docs/guides/dealer/20-dealer-guide.md` (Day 1/Day 2 definition, the not-our-work paragraph, a new "add an outlet" call row, the firmware row) and `docs/guides/dealer/21-sales-mode.md` (Day 1/Day 2 wording, an "Electrical work: we do none" line with the open questions marked as the owner's).
6. `docs/guides/installer/12-bridge-guide.md` — unchanged (no electrical content).

Tone, brand, verified facts, earlier decisions (mailbox, setup access point, GPIO 2/14/16/18 with outputs beyond four UNVERIFIED, bridge pairing installer-only, never flash) and every UNVERIFIED flag are carried unchanged. No site survey or measurement sheet exists in the maintained set (the sales visit captures runs in the app, T-X8); the runs table on the site and controller record covers the paper side.

## C. Pen-ready print forms

**Where the dark look came from.** The Drive PDFs were rendered from the archived August guides, whose inline `<style>` blocks set a near-black page (`docs/archive/guides-2026-08/dealer_preinstall_setup.md:18–33`), and from the archived September family's `docs/archive/guides-2026-09/_shared.css`. The maintained guides and the exports carry no stylesheet at all (md-to-pdf renders them with its default light theme), so nothing on-screen shares a file with the new variant. The new `docs/guides/print/_print_write.css` is used only by the three forms.

**Forms** (`docs/guides/print/`, copied to `docs/drive-exports/print/` by `scripts/docs_exports.sh`): `P1-preinstall-bench-sheet.md` (one per unit, from the SOP), `P2-install-day-sheet.md` (from the checklist), `P3-site-controller-record.md` (the "install sheet" the guides refer to: runs, outputs, firmware version, bridge, hand-off, later changes). US Letter; margins 12 mm with 20 mm left; body 10.5 pt; headings dark navy; thin light-gray rules; no fills, bands, images or gradients; the brand is the small mark (`nexgen_mark.png`, the logo inverted to black on transparent) and the heading colour. Checkboxes 5 mm; short-answer cells 10 mm × ≥ 25 mm; writing lines 8.5 mm apart; note boxes 60 mm; no field for a password, PIN or key, only "recorded privately" checkboxes; the controller sections map outputs 1–4 to GPIO 2, 14, 16, 18.

**Render verification** (md-to-pdf 5.2.5, every page to PNG at 100 dpi, colour and grayscale, each page looked at): dark % = pixels darker than mid-gray (text, rules, boxes, the mark); fill % = dark pixels surviving a 3-pass 3×3 erosion (anything thicker than about 1.8 mm, i.e. fills, not strokes); "−mark" masks the mark's rectangle; mid % = pixels between mid-gray and near-white (rules and anti-aliasing; light text would show here).

| Form | Pages | dark % per page | fill % | fill % −mark | mid % | darkest pixel |
|---|---|---|---|---|---|---|
| P1 Pre-install bench sheet | 3 | 3.25 / 2.55 / 1.18 | 0.001 / 0.000 / 0.000 | 0.000 | 3.9 / 2.9 / 1.6 | 17 (black text) |
| P2 Install-day sheet | 3 | 3.75 / 2.79 / 2.86 | 0.001 / 0.000 / 0.000 | 0.000 | 4.2 / 3.7 / 3.3 | 17 |
| P3 Site and controller record | 3 | 1.50 / 1.51 / 0.58 | 0.000 / 0.000 / 0.000 | 0.000 | 3.6 / 2.3 / 1.7 | 17 |

Target was 0 apart from text and rules: met (the only non-zero figure, 0.001 % on each first page, is the mark). Every field has room for a pen: checked page by page, including the grayscale renders.

## D. WLED 0.15.1 vs 0.15.4 — read-only audit

Written to `docs/FIRMWARE_VERSION_ANALYSIS.md` (maintained, no customer data); FACTS rows T-F6 to T-F13 added. Nothing was done to any controller.

- **Docs** (§1): no standard version is named; record and never change (T-F2); the July pin is withdrawn (T-F3); same effect ids (T-F5).
- **Code** (§2): nothing branches on the version. The app stores it once at controller-add (`firmwareVersion`, never refreshed); the server's probe stores `wledVersion`, `wledVid`, `wledRelease`. Every 0.15-specific behaviour is a measurement applied to all units: timers and solar slots, preset save/delete, effect ids, gamma re-write, per-pixel freeze (measured on 0.15.1); the 224-LED request budget (measured on 0.15.4). The one concrete upstream reason for a difference: 0.15.4 blacks unused segments on every segment write, so a per-pixel design sent in several requests may keep only its last request (UNVERIFIED).
- **Census** (§3, counts only): 58 accounts; 27 with a controller record; 29 rows; best-known version 16 on 0.15.1, 6 on 0.15.4, 7 unknown; 23 Skikbily, 1 Dig-Octa (on 0.15.4), 5 untyped; every probed unit `ESP32_Ethernet`; add-time and probe versions never disagree. The per-account list (uid prefixes and last-seen) went to the owner in the hand-back and is not in the repository.
- **Upstream** (§4): 0.15.1 2025-07-31; 0.15.2 2025-11-29 (ESP32 only; OTA validation, old-version check, bootloop recovery, segments not reset when unchanged); 0.15.3 2025-12-04; 0.15.4 2026-03-14 (presets.json file-handle protection, unused segments set to black, Ethernet default pin 4, audio default no mic). No note mentions downgrading or what an update keeps.
- **How a unit moves** (§5): WLED's Security settings → unlock OTA → Manual OTA update → the board's image → re-lock. Official image `WLED_<ver>_ESP32_Ethernet.bin`; the vendor's repository offers `WLED_LAN_4CH_0.15.1` to `_0.15.4` and a "16.0.1" image, USB web-flasher only. Our rule: owner 2026-10-08/09 (T-F2–T-F4); "never USB" from the SOP's serial-write ban of 2026-08-28 (`a84aec2`, "bricking risk"); the July pin (`9fdad58`) rested on one bench pause. What an update keeps, and what a refused or interrupted update does, is UNVERIFIED. The home unit's presets file has seven bad bytes (slot 41 unparseable) and is never a test unit (T-F11).
- **Verdict** (§6): options given; the safest is "no fleet standard, record and never change" with 0.15.1 named as the reference the app was measured against; a move in either direction is not proven safe or reversible (down may be refused by the old-version check; the USB route is banned); a bench plan on the spare unit with backups and SHA checks is written and not run; a mixed fleet causes no app, healer or Game Day problem known today; the installer guides carry verified statements only.

## OWNER DECISION blocks

### Block 1 — warranty, terms, liability, insurance, licensing wording (not changed)

Hits (maintained set; the exports mirror them):

| file:line | Today | Proposed (apply only on the owner's word) |
|---|---|---|
| `docs/FACTS.md` T-O6 | "5-year product warranty, 1-year labor minimum, 50,000-hour rated life. 'Lifetime warranty' is never said." | Keep the figures (they are the app's, `lib/features/sales/screens/estimate_preview_screen.dart:449–451`). If the warranty should exclude line-voltage work, add: "The 1-year labor minimum covers the low-voltage pre-install and the install performed by the dealer; work arranged by the customer through a licensed professional is outside it." |
| `docs/guides/dealer/21-sales-mode.md:16` | "'What's included' lists the 5-year product warranty, the 1-year labor minimum, the 50,000-hour rated life and ongoing dealer support." | Same optional sentence after it. |
| `docs/guides/dealer/21-sales-mode.md:28`, `20-dealer-guide.md` ("Claims you may make"), `installer/10-install-checklist.md` (Handoff), `internal/33-claims-policy.md:14`, `drive-exports/store-listings-and-website-notes.md:10` | The "never lifetime warranty" rule with the three figures. | No change, or the same optional sentence. |
| `docs/drive-exports/DRIVE_SWAP_CHECKLIST.md` section C ("Warranty/Contract/Estimate Docs" folder) | Empty folder; nothing from the branch belongs there. | No change. |
| Liability, insurance, licensing, "terms", bonded, indemnity | **0 hits** in the maintained set. The only new mention is the T-W2 sentence's "licensed professional of their own choosing". | If the owner confirms the Missouri / California question (T-W4), one sentence for the dealer guide: "Low-voltage lighting installation in [state] [does / does not] require [a license / registration]; [the dealer] carries [insurance]." Left blank until then. |

### Block 2 — the boundary between the low-voltage pre-install and the line-voltage side (T-W3, UNVERIFIED)

Questions for the owner; no guide answers them, and installers are told not to improvise on site:

1. Does our installer plug the power supply into the customer's outlet, or does the customer?
2. GFCI and weatherproof outlets: who specifies, who provides, who installs?
3. Junction boxes: ever ours?
4. Where the power supply mounts: our call, the customer's, or the licensed professional's?
5. Fusing on the low-voltage side: ours? on the line side: never ours?
6. Extension cords: allowed at all, and by whom?
7. Permits and inspections: who applies, who meets the inspector, who pays?

### Block 3 — "certified installers"

`lib/features/installer/installer_lock_screen.dart:75` says a feature "is only available to certified installers"; `lib/models/user_role.dart:14` calls the role "Certified Nex-Gen installer". "Certified" is Nex-Gen's own term, not an electrical qualification. Keep, or change to "Nex-Gen installers" (proposal item 29 carries the change as optional).

### Block 4 — Drive file names

The old `day1-electrician-guide.pdf` and `day2-install-guide.pdf` are removed and not renamed; one replacement uploads as `Field_Guide_Day1_Day2.pdf`. The three forms upload as `Lumina_Preinstall_Bench_Sheet.pdf`, `Lumina_Install_Day_Sheet.pdf`, `Lumina_Site_Controller_Record.pdf` (checklist section G). Change the names if you prefer; the checklist is the place.

### Block 5 — firmware

Choose: (1) no fleet standard, record and never change (today; recommended), with 0.15.1 named in FACTS as the reference the app was measured against; (2) the same plus an authorised bench test on the spare unit per `docs/FIRMWARE_VERSION_ANALYSIS.md` §6b (a written exception to the never-flash rule, spare only); (3) something else. No fielded unit moves until §6b step 7 passes.

### Block 6 — the new guard rule

The guard now refuses the trade word and "electrical work / pre-wire / team / crew / visit" in guides and exports unless the sentence negates it. Confirm, or name exceptions.

## Verification

- `node scripts/docs_guard.mjs`: 44 files checked, 111 facts, 0 failures, 0 warnings (after this report existed; the only failure before it was this file's path).
- `node scripts/docs_guard.mjs --links-all`: 0 failures in the maintained set; 516 warnings, all in archived engineering records with repo-root-relative links (unchanged since Phase 5).
- `bash scripts/docs_exports.sh`: 17 exports plus 3 print forms regenerated; every one passes the guard.
- PII scan over every added line of the working tree (848 lines; email, phone, private IP, MAC, 12-hex id, 28-character id, PIN value, password value, uid-prefix and known-name patterns): 0 hits. Commit messages scanned the same way before the push.
- Read-only: the Firestore census used the admin SDK for reads only (two collections, counts kept); no document written.

## Prepared, not run

`MERGE_PLAN.md` (updated for this head): the no-ff merge into release with the tree checks, no tag, no build trigger (`codemagic.yaml` triggers on `build-*` tags only).

## Still UNVERIFIED

The low-voltage / line-voltage boundary and its seven edge cases (T-W3); Missouri / California license or insurance requirements (T-W4); the vendor's images versus stock WLED and its "16.0.1" image (T-F6); whether an update keeps cfg.json, presets.json and Wi-Fi, and what a refused, failed or mismatched image does (T-F8); whether the July pause occurs on any unit shipped since September (T-F10); the exact "Access Point opens" option labels and the right choice for Skikbily builds (T-A5); how many outputs a Skikbily controller has beyond four (T-X5); mail delivery to general@nex-genled.com (T-SU2); the out-of-box controller network name (T-A1); the Drive items in checklist section F; and everything already listed in `docs/FACTS.md`.

*Last verified: 2026-10-12.*
