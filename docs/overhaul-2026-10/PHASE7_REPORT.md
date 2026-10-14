# Phase 7 — the owner's answers to the six OWNER DECISION blocks applied (documents only)

Branch `docs/overhaul-2026-10`, on top of the Phase 6 head `36c9ba1`. Documents and the docs tooling only: no app or functions code, no `codemagic.yaml` change, no version bump, no tag, no merge, no build, test or analyzer, nothing written to any controller, bridge, Firestore document, configuration or Google Drive, no OTA or firmware action, no command to any controller. No process was stopped, killed or restarted; the only renderer runs were started by this session with a per-file timeout and all exited normally. Every decision is in `docs/FACTS.md` as "decided by owner 2026-10-12" under the next free numbers (T-W7 to T-W11, T-F14); nothing was renumbered; everything not decided stays UNVERIFIED.

## Decision 1 — warranty (T-W7; T-O6 extended)

The standard warranty is 1-year labor, 5 years product, rated 50,000 hours (T-O6, unchanged figures). Exactly one sentence was added to every maintained place that states it: "Local dealers may add additional coverage at their discretion." Nothing else about the warranty wording changed; no liability, insurance, licensing, bonding or terms wording was added; the earlier "outside the warranty" proposal was not applied.

Placements (file:line):

| Where | Line |
|---|---|
| `docs/FACTS.md` T-O6 | 124 (and T-W7 at 114) |
| `docs/guides/installer/10-install-checklist.md` | 70 |
| `docs/guides/dealer/20-dealer-guide.md` | 70 |
| `docs/guides/dealer/21-sales-mode.md` | 16, 28 |
| `docs/guides/internal/33-claims-policy.md` | 14 |
| `docs/drive-exports/store-listings-and-website-notes.md` | 10 — **public store-listing rule text now carries the sentence; the owner looks at it before it reaches a listing** |
| Exports (generated): `Dealer_Installer_Setup_Guide.md` 77; `Field_Guide_Day1_Day2.md` 77, 156; `Dealer_Dashboard_Guide.md`, `dealer-inventory-guide.md`, `messaging-configuration-guide.md` 77; `sales-mode-guide.md` 23, 35; `Admin_Operations_Guide.md` 91; `nex-gen-operations-overview.md` 81 | as listed |

Questions for the owner, not decided here: whether Missouri or California requires a license or insurance for low-voltage lighting installation (T-W4, UNVERIFIED); whether dealer-added coverage is the dealer's obligation alone (T-W7, UNVERIFIED).

## Decision 2 — the line-voltage boundary (T-W8; T-W3 updated)

Recorded verbatim in FACTS T-W8: "Our installer can plug the supply in, but we do not install actual outlets, or run bare electrical wires. That is purely the homeowner's responsibility." Applied as (a) the installer may plug the power supply into an existing customer outlet; (b) Nex-Gen LED and its dealers do not install outlets and do not run line-voltage (household power) wiring; that is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing (the only neutral reference to a licensed professional; the trade word still describes nobody of ours); (c) with no working outlet at the supply location the installer installs nothing, stops and tells the customer. (d) Whether "bare electrical wires" means exactly line-voltage wiring is UNVERIFIED and is the owner's question; guides use the plain-language wording in (b).

Changed (file:line), and nothing else in these documents:

- `docs/guides/installer/10-install-checklist.md:9` (Not our work box), `:11` (open questions, the plug-in item removed), `:16` (pre-install: a working outlet in place or arranged by the homeowner), `:27` (install day step 1: plug into the existing outlet; no working outlet = stop and tell the customer).
- `docs/guides/installer/13-installer-sop.md:9` (box), `:11` (open questions), the pre-install order step 2 and the information-to-capture line (working outlet), `:100` (troubleshooting row: no working outlet = not ours; stop, tell, reschedule).
- `docs/guides/customer/00-getting-started.md:64` (customer wording of a, b).
- `docs/guides/dealer/20-dealer-guide.md:30` (the same box inline) and `:66` (the "add an outlet" call row); `docs/guides/dealer/21-sales-mode.md:34` (the electrical-work line; the plug-in item removed from its open list). These two pages carried the first-round statement, so they were brought into line; no other change on them beyond decision 1.
- Print forms: `P1-preinstall-bench-sheet.md:32` (callout) and `:41` (working outlet: in place / arranged by the homeowner / not needed); `P2-install-day-sheet.md:31` (callout) and `:44` (step 1); `P3-site-controller-record.md:36` (outlet line and the plain statement).
- `docs/guides/internal/33-claims-policy.md:27` (the row now notes that the installer may plug the supply in).

Edge cases still NOT decided, kept as open questions in the checklist, the SOP, the sales page and FACTS (T-W3 at lines 110 and 141), with installers told not to improvise on site: whether the installer may plug into an outlet that is not weatherproof or GFCI; junction boxes; where the power supply mounts; fusing; extension cords; permits and inspections.

**Print forms re-rendered** (md-to-pdf 5.2.5, every page to PNG at 100 dpi in colour and grayscale, each looked at; same measures as Phase 6):

| Form | Pages | dark % per page | fill % | fill % −mark | mid % | darkest pixel |
|---|---|---|---|---|---|---|
| P1 Pre-install bench sheet | 3 | 3.31 / 2.81 / 1.19 | 0.001 / 0.000 / 0.000 | 0.000 | 3.6 / 3.1 / 1.6 | 17 |
| P2 Install-day sheet | 3 | 3.64 / 3.18 / 2.87 | 0.001 / 0.000 / 0.000 | 0.000 | 4.0 / 3.9 / 3.3 | 17 |
| P3 Site and controller record | 3 | 1.58 / 1.51 / 0.59 | 0.000 / 0.000 / 0.000 | 0.000 | 3.7 / 2.3 / 1.7 | 17 |

Dark fill apart from text and rules: 0 (the 0.001 % on each first page is the mark). Every field has pen room; the grayscale renders match.

## Decision 3 — "Nex-Gen installers" (T-W9)

No maintained document or export used "certified installers"; nothing needed changing in the documents. The only other use of "certif" in the maintained set is `docs/guides/internal/32-bridge-firmware.md:11` ("TLS without certificate validation"), unrelated and unchanged. There is no dealer-certification wording anywhere in the maintained set, so there is nothing to ask about. The app string `lib/features/installer/installer_lock_screen.dart:75` stays list-only: `docs/overhaul-2026-10/APP_STRINGS_PROPOSAL.md` item 29 now proposes "…is only available to Nex-Gen installers." as decided. No code change.

## Decision 4 — Drive names (T-W10)

Approved as proposed and marked owner-approved in `docs/drive-exports/DRIVE_SWAP_CHECKLIST.md`: rows A6 and A7 (the old field-guide PDFs removed, not renamed; replacement `Field_Guide_Day1_Day2.pdf`) and section G (`Lumina_Preinstall_Bench_Sheet.pdf`, `Lumina_Install_Day_Sheet.pdf`, `Lumina_Site_Controller_Record.pdf`).

## Decision 5 — firmware, option 1 (T-F14)

Record, never change, for every fielded unit; 0.15.1 is named as the reference version the app was measured against, not a claim that it is shipped or newer. `docs/FIRMWARE_VERSION_ANALYSIS.md` §6 now reads as owner-decided (heading at line 114, the decision paragraph at 124); the bench plan (line 132) is marked "written, NOT authorized (option 2 was not chosen), never run; no controller to be touched", its step 3 says steps 4–9 are not to be run, and the home unit with the seven bad bytes stays excluded by name. The installer guides carry only the verified firmware lines of §6d (unchanged this round).

## Decision 6 — the guard rule (T-W11)

Confirmed; logic unchanged (`scripts/docs_guard.mjs:108–109`). The claims-policy row (`33-claims-policy.md:27`) is marked owner-confirmed. Proof it still works: a throwaway page under `docs/guides/` containing "Our electrician runs the wiring. The electrical pre-wire is ours." produced two failures and "We do no electrical work." produced none; the page was removed and the guard returned to 0 failures.

## Exports, Drive, verification

- `bash scripts/docs_exports.sh`: 17 exports plus 3 print forms regenerated; every one passes the guard. Compared with the first round of 2026-10-12, 14 changed in content and 5 are byte-identical (the generated-date line is the same day). `DRIVE_SWAP_CHECKLIST.md` section H now lists exactly which uploads changed in content this round and which first-round files stand.
- `node scripts/docs_guard.mjs`: 44 files checked, 117 facts, 0 failures, 0 warnings.
- `node scripts/docs_guard.mjs --links-all`: 0 failures in the maintained set; the 516 archive warnings are unchanged.
- PII scan over every added line of this round and over every commit message (email, phone, private IP, MAC, 12-hex id, 28-character id, PIN value, password value, uid prefix, known names): 0 hits.
- `MERGE_PLAN.md`: prepared, NOT run; the trigger was re-read from `codemagic.yaml` lines 24–29 (`events: [tag]`, `tag_patterns: build-*`): a docs commit or merge pushed to release starts no Codemagic build.

## Still UNVERIFIED

Whether dealer-added warranty coverage is the dealer's obligation alone (T-W7); Missouri / California license or insurance (T-W4); whether "bare electrical wires" means exactly line-voltage wiring (T-W8); the remaining boundary edge cases (T-W3); everything firmware-side in T-F6, T-F8, T-F10; the "Access Point opens" labels (T-A5); Skikbily outputs beyond four (T-X5); mail delivery to general@nex-genled.com (T-SU2); the out-of-box controller network name (T-A1); the Drive items in checklist section F.

*Last verified: 2026-10-12.*
