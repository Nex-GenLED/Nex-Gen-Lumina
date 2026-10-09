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
| 6 | day1-electrician-guide.pdf | 167,273 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE | `day1-electrician-guide.md` (one combined field guide) | Lumina How-To's + Hub dealer folder |
| 7 | day2-install-guide.pdf | 198,817 | 2026-08-27 22:28 | render of `d67d350`, archived | REMOVE | `day2-install-guide.md` (same combined field guide) | Lumina How-To's + Hub dealer folder |
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
| B6 | dealer_preinstall_setup.pdf | — | — | NOT SEEN in the listing (the repository had a PDF of this name, rendered 2026-07-30 from `393af46`; it carried the firmware-pin instruction and the setup-AP password) | REMOVE if present, wherever it is | `Dealer_Installer_Setup_Guide.md` (contains the bench SOP) | Hub dealer folder |

## C. NEX-GEN Hub (personal account)

| Folder | What is there | Action |
|---|---|---|
| Lumina Dealer Docs and How-To's | EMPTY (created 2026-08-27) | POPULATE with the dealer-facing set: `Dealer_Installer_Setup_Guide.md`, `ESP32_Bridge_Setup_Guide.md`, `Dealer_Dashboard_Guide.md`, `sales-mode-guide.md`, `day1-electrician-guide.md`, `Lumina_Homeowner_Guide.md` (to hand to customers). Do NOT put the two internal staff files there. |
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
4. Upload the dealer set: `Dealer_Dashboard_Guide.md`, `sales-mode-guide.md`, `day1-electrician-guide.md`.
5. Upload the staff set to a staff-only folder: `Admin_Operations_Guide.md`, `corporate-dashboard-guide.md`, `nex-gen-operations-overview.md`.
6. Edit the privacy policy document per `Lumina_Privacy_Policy_corrections.md`; republish the web page.
7. Apply `store-listings-and-website-notes.md` to the website and both store listings.
8. Send one test message to general@nex-genled.com and tell the branch owner it arrived (FACTS T-SU2 stays UNVERIFIED until then).

## F. Could not be seen from here — confirm in Drive

- The contents of every PDF (binary; matched by name and date only).
- Whether B5 and B6 exist anywhere on Drive.
- Everything inside "Inventory Tools", "Logo, Icons, Media" (including its "web" and "Media Video and Photo" folders), "Nex-Gen Dealer Development" and the dealer files folder.
- Any folder not reached by the listing (the search was by name and by the folders above).

*Facts: T-O8, T-SU2, T-X8, T-VA1. Last verified: 2026-10-09.*
