# Print forms (pen-ready)

*Describes build: 2.5.10+116 · Last verified: 2026-10-12 · For dealers and installers*

Three forms meant to be printed and written on with a pen. They carry the same facts as the installer pages; the pages are the reference, the forms are the paper. White page, dark text, thin light-gray rules, US Letter, 12 mm margins with a 20 mm left margin for a hole punch; checkboxes 5 mm; writing lines at least 8 mm apart; short-answer boxes at least 25 × 10 mm; note boxes at least 60 mm tall; body text 10.5 pt.

| Form | When | Source page |
|---|---|---|
| [P1 Pre-install bench sheet](P1-preinstall-bench-sheet.md) | At the shop, one per controller and bridge | [Pre-install SOP](../installer/13-installer-sop.md) |
| [P2 Install-day sheet](P2-install-day-sheet.md) | On site, install day | [Install checklist](../installer/10-install-checklist.md) |
| [P3 Site and controller record](P3-site-controller-record.md) | From the sale to the file: runs, outputs, firmware version, bridge, hand-off, later changes | [Controller setup](../installer/11-controller-setup.md) |

No form has a field for a password, a PIN or a key. Each has only a "recorded privately" checkbox; the values live in the dealer's own secure record.

## Rendering

Each form carries its own front matter for `md-to-pdf` and uses `_print_write.css` in this folder (the only stylesheet in the maintained set; the dark on-screen look of the archived guides is not shared with it). From this folder:

```
md-to-pdf P1-preinstall-bench-sheet.md
md-to-pdf P2-install-day-sheet.md
md-to-pdf P3-site-controller-record.md
```

Rendered PDFs are not kept in the repository. The Drive copies are listed in `docs/drive-exports/DRIVE_SWAP_CHECKLIST.md`; `bash scripts/docs_exports.sh` copies the forms, the stylesheet and the mark into `docs/drive-exports/print/` for upload.

*Facts: T-W1, T-W2, T-W6, T-X5, T-F2.*
