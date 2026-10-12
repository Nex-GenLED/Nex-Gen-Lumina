# Drive swap checklist — remove the old, upload the new (owner's step; nothing here is published)

Owner decision 2026-10-09: pull everything old and dated from Drive and replace it with the new documents. The branch cannot write to Drive, so this is the list to work through, in order. Every replacement is a Markdown file in this folder, regenerated from `docs/guides/` and checked by `node scripts/docs_guard.mjs`; render each to PDF with the usual tool before uploading, and keep the file names below so links elsewhere keep working.

What was seen: the file names, sizes and modified dates below come from a read-only Drive listing on 2026-10-08. PDF and image contents were not opened (binary); the privacy policy and the capture brief were read. "Matched git version" names the commit whose text the file most likely renders (by name and date; byte sizes differ from the repository's own renders of the same day, so they are not byte-identical copies).

## A. Shared drive, folder "Lumina How-To's" (13 PDFs) — remove all, replace all

| # | Name (Drive) | Size (B) | Modified (UTC) | Matched git version | Action | Replacement (this folder) | Goes in |
|---|---|---|---|---|---|---|---|
| 1 | Lumina_Homeowner_Guide.pdf | 494,987 | 2026-08-27 22:28 | render of `d67d350` text (2026-08-27); superseded by `9318625` text (2026-09-17), itself now archived | REMOVE | `Lumina_Homeowner_Guide.md` | Lumina How-To's |
| 2 | Dealer_Installer_Setup_Guide.pdf | 514,133 | 2026-08-27 22:28 | render of `d67d350`; superseded by `5ac40ac`, archived | REMOVE | `Dealer_Installer_Setup_Guide.md` | Lumina How-To's + Hub dealer folder |
| 3 | ESP32_Bridge_Setup_Guide.pdf | 287,084 | 2026-08-27 22:28 | render of `d67d350`; superseded by `5ac40ac`, archived | REMOVE | `ESP32_Bridge_Setup_Guide.md` | Lumina How-To's + Hub dealer folder |
| 4 | Dealer_Dashboard_Guide.pdf | 402,700 | 2026-08-27 22:28 | render of `d67d350`; superseded by `5ac40ac`, archived | REMOVE | `Dealer_Dashboard_Guide.md` | Lumina How-To's + Hub dealer folder |
| 5 | sales-mode-guide.pdf | 248,101 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE | `sales-mode-guide.md` | Lumina How-To's + Hub dealer folder |
| 6 | day1-electrician-guide.pdf | 167,273 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE (the name is not reused: we are not electricians, owner 2026-10-12; owner-approved 2026-10-12, T-W10) | `Field_Guide_Day1_Day2.md` (one combined field guide, uploaded as `Field_Guide_Day1_Day2.pdf`; name owner-approved) | Lumina How-To's + Hub dealer folder |
| 7 | day2-install-guide.pdf | 198,817 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE (owner-approved 2026-10-12, T-W10) | `Field_Guide_Day1_Day2.md` (same combined field guide; one upload replaces both) | Lumina How-To's + Hub dealer folder |
| 8 | dealer-inventory-guide.pdf | 158,650 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE | `dealer-inventory-guide.md` (the dealer guide; the inventory screens it described are not available) | Lumina How-To's |
| 9 | messaging-configuration-guide.pdf | 348,150 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE | `messaging-configuration-guide.md` (the dealer guide, Messaging section) | Lumina How-To's |
| 10 | User_Guide_Commercial.pdf | 516,908 | 2026-08-27 22:28 | render of `d67d350`; superseded by `5ac40ac`, archived | REMOVE | `User_Guide_Commercial.md` (commercial customers use the standard app; same pages as the homeowner guide) | Lumina How-To's |
| 11 | corporate-dashboard-guide.pdf | 262,414 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE | `corporate-dashboard-guide.md` — INTERNAL: staff folder only | Staff-only folder (not the dealer folder) |
| 12 | Admin_Operations_Guide.pdf | 616,197 | 2026-08-27 22:28 | render of `d67d350`; superseded by `5ac40ac`, archived; printed staff codes (rotated 2026-08-29) | REMOVE | `Admin_Operations_Guide.md` — INTERNAL: staff folder only | Staff-only folder |
| 13 | Media_Mode_Guide.pdf | 195,485 | 2026-08-17 17:48 | pre-commit render of the 2026-08-27 text, archived | REMOVE | no replacement: retired (`Media_Mode_Guide.md` is a one-paragraph withdrawal note; Media Mode is not reachable) | — |

Also add to "Lumina How-To's": `nex-gen-operations-overview.md` (replaces the removed PDF of the same name, see B2; it is now the guide index plus the claims policy, staff-facing).

## B. Shared drive root (loose files)

| # | Name (Drive) | Size (B) | Modified (UTC) | Matched git version | Action | Replacement | Goes in |
|---|---|---|---|---|---|---|---|
| B1 | Admin_Operations_Guide.pdf (second copy) | 267,762 | 2026-04-01 20:50 | older than the earliest render in this branch's history; no matching git version identified; printed staff codes (rotated 2026-08-29) | REMOVE | `Admin_Operations_Guide.md` (same as A12) | Staff-only folder |
| B2 | Dealer_Dashboard_Guide.pdf (second copy) | 234,730 | 2026-04-03 20:14 | older than the earliest render in this branch's history; no matching git version identified | REMOVE | `Dealer_Dashboard_Guide.md` (same as A4) | Lumina How-To's + Hub dealer folder |
| B3 | Lumina_Capture_Brief.pdf | 99,257 | 2026-08-02 14:45 | not in the repository (one-off screenshot brief for build 60, addressed to a named helper) | REMOVE | no replacement: retired | — |
| B4 | Lumina_Privacy_Policy.docx (in an unnamed parent folder) | 15,258 | 2026-04-01 20:32 | not in the repository | EDIT, do not remove | apply `Lumina_Privacy_Policy_corrections.md`, then republish the web page from it | where it is |
| B5 | nex-gen-operations-overview.pdf | — | — | NOT SEEN in the listing (the repository had a PDF of this name; confirm whether a Drive copy exists) | REMOVE if present | `nex-gen-operations-overview.md` | Staff-only folder |
| B6 | dealer_preinstall_setup.pdf | — | — | NOT SEEN in the listing (the repository had a PDF of this name, rendered 2026-07-30 from `393af46`; it carried the firmware-pin instruction and the setup-AP password; it was the dark page nobody could write on) | REMOVE if present, wherever it is | `Dealer_Installer_Setup_Guide.md` (contains the pre-install SOP) plus the pen-ready `print/P1-preinstall-bench-sheet.md` (section G) | Hub dealer folder |

## C. NEX-GEN Hub (personal account)

| Folder | What is there | Action |
|---|---|---|
| Lumina Dealer Docs and How-To's | EMPTY (created 2026-08-27) | POPULATE with the dealer-facing set: `Dealer_Installer_Setup_Guide.md`, `ESP32_Bridge_Setup_Guide.md`, `Dealer_Dashboard_Guide.md`, `sales-mode-guide.md`, `Field_Guide_Day1_Day2.md`, `Lumina_Homeowner_Guide.md` (to hand to customers), and the three print forms from section G. Do NOT put the two internal staff files there. |
| Warranty/Contract/Estimate Docs | EMPTY | Nothing from this branch belongs there; the warranty wording dealers may use is in the claims policy (inside `nex-gen-operations-overview.md`). |
| Inventory Tools | Spreadsheets: an order sheet, a demo order sheet, a cost/profit example, an "Expired Inventory Forms" folder, a dealer sub-folder | Not product documents; NOT reviewed; leave. The owner confirms nothing inside describes the app. |
| Logo, Icons, Media | Logos, yard-sign artwork, a "web" folder and a "Media Video and Photo" folder | Not documents; NOT opened; leave. The owner confirms the "web" folder holds no copy of the old guides or website text that claims voice assistants. |

## D. Other folders seen

| Folder | What is there | Action |
|---|---|---|
| Nex-Gen Dealer Development | website prompts (.docx, 2026-03), an NDA, a dealer information sheet, a vendor/SKU sheet, an application-responses folder, an "Inventory Documents" folder | Business documents; NOT opened. The website prompts document (2026-03-16) is the same family as the archived repository prompts and will carry the same false claims (voice assistants, store downloads, security wording): REMOVE or rewrite from `store-listings-and-website-notes.md`. Confirm the rest. |
| A dealer's own files folder | two order/invoice example spreadsheets | Not documents; leave. |

## E. Upload order

1. Remove A1–A13 and B1–B3 (and B5/B6 if they exist). Keep nothing dated August or earlier.
2. Upload the customer guide (`Lumina_Homeowner_Guide.md`, rendered) to Lumina How-To's and to the Hub dealer folder.
3. Upload the installer set: `Dealer_Installer_Setup_Guide.md`, then `ESP32_Bridge_Setup_Guide.md`.
4. Upload the dealer set: `Dealer_Dashboard_Guide.md`, `sales-mode-guide.md`, `Field_Guide_Day1_Day2.md`.
4a. Render and upload the three print forms (section G) to the Hub dealer folder and to Lumina How-To's.
5. Upload the staff set to a staff-only folder: `Admin_Operations_Guide.md`, `corporate-dashboard-guide.md`, `nex-gen-operations-overview.md`.
6. Edit the privacy policy document per `Lumina_Privacy_Policy_corrections.md`; republish the web page.
7. Apply `store-listings-and-website-notes.md` to the website and both store listings.
8. Send one test message to general@nex-genled.com and tell the branch owner it arrived (FACTS T-SU2 stays UNVERIFIED until then).

## G. Print forms (new 2026-10-12; pen-ready, white page; upload names owner-approved 2026-10-12, T-W10)

Render each from `docs/drive-exports/print/` with `md-to-pdf <file>` (the front matter sets US Letter, 12 mm margins with a 20 mm left margin, no backgrounds, and `_print_write.css`; keep the `.css` and `nexgen_mark.png` beside the `.md` when rendering). Verified 2026-10-12 by rendering every page to PNG: white pages, dark text, thin light-gray rules, the small mark the only dark area.

| # | File (this folder) | Upload as | Goes in | Replaces |
|---|---|---|---|---|
| G1 | `print/P1-preinstall-bench-sheet.md` | `Lumina_Preinstall_Bench_Sheet.pdf` | Hub dealer folder + Lumina How-To's | the dark pre-install SOP page (B6) as the thing a dealer writes on |
| G2 | `print/P2-install-day-sheet.md` | `Lumina_Install_Day_Sheet.pdf` | Hub dealer folder + Lumina How-To's | nothing (new) |
| G3 | `print/P3-site-controller-record.md` | `Lumina_Site_Controller_Record.pdf` | Hub dealer folder + Lumina How-To's | nothing (new); this is "the install sheet" the guides refer to |

## H. Changed in CONTENT on 2026-10-12, third round (the "no line-voltage work" wording) — upload exactly these

Compared with the branch at `9dcb2bb` (second round; the generated-date line is identical, so a changed file changed in content):

| Export | Content change this round | Upload |
|---|---|---|
| `Dealer_Installer_Setup_Guide.md` | both "Not our work" boxes now read "We do no line-voltage work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage (household power) wiring…"; the checklist's hand-off line says "do not offer line-voltage work" | yes |
| `Field_Guide_Day1_Day2.md` | the same checklist box and line, plus the dealer guide's box and the "add an outlet" call row (full public wording) | yes |
| `Dealer_Dashboard_Guide.md`, `dealer-inventory-guide.md`, `messaging-configuration-guide.md` | dealer guide: box and call row | yes |
| `sales-mode-guide.md` | "Line-voltage work: we do none." line | yes |
| `Lumina_Homeowner_Guide.md`, `User_Guide_Commercial.md` | getting-started paragraph carries the full customer wording | yes |
| `Admin_Operations_Guide.md`, `nex-gen-operations-overview.md` | claims policy: the not-electricians row says "no line-voltage work" and quotes the public wording; a new row: no license, insurance, bonding, liability or terms statement in public text until the owner approves wording; the "Our work" line | yes |
| `print/P1-preinstall-bench-sheet.md`, `print/P2-install-day-sheet.md`, `print/P3-site-controller-record.md` | callouts and the P3 outlet line reworded; re-rendered and checked | yes (rows G1–G3) |
| `store-listings-and-website-notes.md` | unchanged this round; still carries the dealer-coverage sentence from the second round, flagged for the owner's look before it reaches a listing | after the owner's look |
| `ESP32_Bridge_Setup_Guide.md`, `corporate-dashboard-guide.md`, `Media_Mode_Guide.md`, `Lumina_Privacy_Policy_corrections.md`, `README.md` | byte-identical to the second round | no |

### Second round of 2026-10-12 (history)

The exports were regenerated again after the owner's six decisions. Compared with the first round earlier the same day (the generated-date line is identical, so a changed file changed in content):

| Export | Content change this round | Upload |
|---|---|---|
| `Dealer_Installer_Setup_Guide.md` | "Not our work" box rewritten (installer may plug the supply in; no outlets, no household power wiring; no working outlet = stop and tell the customer); checklist pre-install and step 1; SOP troubleshooting row; warranty sentence | yes |
| `Field_Guide_Day1_Day2.md` | the same checklist text plus the dealer guide (box, call row, warranty sentence) | yes |
| `Dealer_Dashboard_Guide.md`, `dealer-inventory-guide.md`, `messaging-configuration-guide.md` | dealer guide: box, "add an outlet" call row, warranty sentence | yes |
| `sales-mode-guide.md` | warranty sentence (two places); the line about the work we do not do | yes |
| `Lumina_Homeowner_Guide.md`, `User_Guide_Commercial.md` | getting-started "What your installer did" paragraph | yes |
| `Admin_Operations_Guide.md`, `nex-gen-operations-overview.md` | claims policy: warranty sentence; the not-electricians row marked owner-confirmed | yes |
| `print/P1-preinstall-bench-sheet.md`, `print/P2-install-day-sheet.md`, `print/P3-site-controller-record.md` | callouts and outlet lines rewritten; re-rendered and checked | yes (rows G1–G3) |
| `store-listings-and-website-notes.md` | warranty sentence added to the store rule (public listing text: the owner looks at it before it reaches a listing) | after the owner's look |
| `ESP32_Bridge_Setup_Guide.md`, `corporate-dashboard-guide.md`, `Media_Mode_Guide.md`, `Lumina_Privacy_Policy_corrections.md`, `README.md` | byte-identical to the first round | no (first-round file stands) |

### First round of 2026-10-12 (history)

Every export was regenerated on 2026-10-12 (the generated-date line changed in all of them). Content changed in these; upload these versions, not the 2026-10-09 renders:

| Export | What changed | Rows above |
|---|---|---|
| `Dealer_Installer_Setup_Guide.md` | Install checklist and pre-install SOP rebuilt as pre-install → install day → handoff with a "Not our work" box; controller-setup firmware wording; print-form references | A2, B6 |
| `Field_Guide_Day1_Day2.md` | New name (was two files named for a trade we are not); dealer guide Day 1/Day 2 and the not-our-work paragraph; rebuilt install checklist | A6, A7 |
| `Dealer_Dashboard_Guide.md`, `dealer-inventory-guide.md`, `messaging-configuration-guide.md` | Dealer guide: Day 1/Day 2 wording, the not-our-work paragraph, the "add an outlet" call row, firmware row | A4, A8, A9, B2 |
| `sales-mode-guide.md` | Day 1/Day 2 wording; "Electrical work: we do none" line | A5 |
| `Lumina_Homeowner_Guide.md`, `User_Guide_Commercial.md` | Getting-started page: "What your installer did" (the not-our-work sentence for customers) | A1, A10 |
| `print/P1…`, `print/P2…`, `print/P3…` + `print/_print_write.css` + `print/nexgen_mark.png` | New | G1–G3 |
| `ESP32_Bridge_Setup_Guide.md`, `Admin_Operations_Guide.md`, `corporate-dashboard-guide.md`, `nex-gen-operations-overview.md`, `Media_Mode_Guide.md`, `Lumina_Privacy_Policy_corrections.md`, `store-listings-and-website-notes.md` | Generated-date line only (no content change); either version is fine | — |

## F. Could not be seen from here — confirm in Drive

- The contents of every PDF (binary; matched by name and date only).
- Whether B5 and B6 exist anywhere on Drive.
- Everything inside "Inventory Tools", "Logo, Icons, Media" (including its "web" and "Media Video and Photo" folders), "Nex-Gen Dealer Development" and the dealer files folder.
- Any folder not reached by the listing (the search was by name and by the folders above).

*Facts: T-O8, T-SU2, T-X8, T-VA1, T-W1, T-W6, T-W10, T-W12. Last verified: 2026-10-12.*
