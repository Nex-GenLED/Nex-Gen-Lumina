# Drive exports — replacement text, not published

Each file here replaces one file in the Google Drive "Lumina How-To's" folder (PDFs dated 2026-08-27) or a store/website text. They are generated from `docs/guides/` and `docs/FACTS.md`; re-generate them with `scripts/docs_guard.mjs`'s companion step below after any guide change. Nothing here is live until the owner uploads it.

| Export | Replaces on Drive | Source pages |
|---|---|---|
| `Lumina_Homeowner_Guide.md` | `Lumina_Homeowner_Guide.pdf` | customer 00–07 |
| `User_Guide_Commercial.md` | `User_Guide_Commercial.pdf` | customer 00–07 (commercial customers use the standard app) |
| `Dealer_Installer_Setup_Guide.md` | `Dealer_Installer_Setup_Guide.pdf` | installer 10–13 |
| `ESP32_Bridge_Setup_Guide.md` | `ESP32_Bridge_Setup_Guide.pdf` | installer 12 |
| `day1-electrician-guide.md`, `day2-install-guide.md` | the two field-guide PDFs | dealer 20 + installer 10 |
| `Dealer_Dashboard_Guide.md`, `dealer-inventory-guide.md`, `messaging-configuration-guide.md` | the three dealer PDFs | dealer 20 |
| `sales-mode-guide.md` | `sales-mode-guide.pdf` | dealer 21 |
| `Admin_Operations_Guide.md`, `corporate-dashboard-guide.md` | the two staff PDFs (the Admin Operations PDF also sits at the shared-drive root; pull both copies: they print old staff codes that were all rotated on 2026-08-29) | internal 30 (+33) |
| `nex-gen-operations-overview.md` | `nex-gen-operations-overview.pdf` | guides README + internal 33 |
| `Media_Mode_Guide.md` | `Media_Mode_Guide.pdf` | withdrawal note |
| `Lumina_Privacy_Policy_corrections.md` | `Lumina_Privacy_Policy.docx` and the live privacy page | corrected paragraphs only |
| `store-listings-and-website-notes.md` | App Store / Play listings, data-safety answers, website pages | what to remove and change |

Re-generate after any guide change: `bash scripts/docs_exports.sh` (concatenates the source pages and strips links), then `node scripts/docs_guard.mjs`.
