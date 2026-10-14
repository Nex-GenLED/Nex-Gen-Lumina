# Phase 8 — "we do no line-voltage work" everywhere; insurance and licensing recorded as owner statements only

Branch `docs/overhaul-2026-10`, on top of the Phase 7 head `9dcb2bb`. Documents and the docs tooling only: no app or functions code, no `codemagic.yaml` change, no version bump, no tag, no merge, no build, test or analyzer, nothing written to any controller, bridge, Firestore document, configuration or Google Drive, no OTA or firmware action, no command to any controller. No process was stopped, killed or restarted; the three renderer runs were started by this session with a per-file timeout and all exited normally. The guard logic is untouched. Decisions are in `docs/FACTS.md` as T-W12 (decided by owner 2026-10-12) and T-W13 (owner states 2026-10-12); nothing was renumbered; everything not verified stays UNVERIFIED.

## Decision 1 — the wording (T-W12)

Every blanket "we do no electrical work" sentence in the maintained set, the exports, the forms, the checklists and the claims policy is replaced. Customer-facing pages carry the full public wording: "We do no line-voltage (household power) work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage wiring. That is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing." Installer and dealer guides, forms and checklists carry the same meaning shortened to "no line-voltage work", with the plug-in sentence and the "no working outlet at the supply location: stop and tell the customer" instruction in every "Not our work" box. Safety information is untouched; the licensed-professional reference lives only in that sentence; the trade word still describes nobody of ours. Store, privacy and tester text had no such sentence (0 hits).

Changed (file:line):

| Where | Line | What |
|---|---|---|
| `docs/guides/customer/00-getting-started.md` | 64 | full customer wording (replaces the previous sentence and its second licensed-professional clause) |
| `docs/guides/installer/10-install-checklist.md` | 9, 70 | Not-our-work box; "do not offer line-voltage work" |
| `docs/guides/installer/13-installer-sop.md` | 9 | Not-our-work box |
| `docs/guides/dealer/20-dealer-guide.md` | 30, 66 | the inline box; the "add an outlet" call row now gives the full public wording |
| `docs/guides/dealer/21-sales-mode.md` | 34 | "Line-voltage work: we do none." |
| `docs/guides/internal/33-claims-policy.md` | 27, 39 | the not-electricians row (why and say-instead cells quote T-W12); the "Our work" line |
| `docs/guides/print/P1-preinstall-bench-sheet.md` | 32 | callout |
| `docs/guides/print/P2-install-day-sheet.md` | 31 | callout |
| `docs/guides/print/P3-site-controller-record.md` | 36 | outlet line |
| `docs/overhaul-2026-10/APP_STRINGS_PROPOSAL.md` | 16 | item 29: the booking email adds the public wording (T-W12) and its access list replaces "your electrical panel"; the Day 1 and Day 2 reminders, the Day 1 labels, the materials row ("Homeowner's responsibility"), the task category and the wizard strings use the same meaning; a deploy note lists `functions/src/onSalesJobStatusChanged.ts` and `functions/src/sendInstallReminders.ts` as a text-only functions deploy using this wording, held until after the Game Day S3; the in-app strings wait for the next app build. No code change. |
| `docs/FACTS.md` | 108 (T-W1 notes the public wording), 115 (T-W8 keeps the owner's statement verbatim; the "bare electrical wires" question is recorded as answered by the owner's choice of wording), 119 (T-W12) | |
| Exports regenerated from the above | `Dealer_Installer_Setup_Guide`, `Field_Guide_Day1_Day2`, `Dealer_Dashboard_Guide`, `dealer-inventory-guide`, `messaging-configuration-guide`, `sales-mode-guide`, `Lumina_Homeowner_Guide`, `User_Guide_Commercial`, `Admin_Operations_Guide`, `nex-gen-operations-overview`, `print/P1`, `print/P2`, `print/P3` | content changed; see the Drive checklist section H |

## Decision 2 — insurance and licensing, FACTS only (T-W13)

Recorded at `docs/FACTS.md:120` as the owner's statements with every unstated detail UNVERIFIED: product insurance on the wholesale products sold; the owner's local installation coverage for his own installations; every LLC operator carrying their own installation insurance for low-voltage electrical work (the owner's wording); California operating with a licensed low-voltage employee within the operating LLC; a certificate of insurance collected from each operator and from the local Kansas City installer. UNVERIFIED, for the owner's insurance agent and the licensing authorities: policy scope and limits; whether coverage includes plugging the supply into a customer outlet and installs in other states; the California license classification and who holds or qualifies it; whether Missouri requires a license or insurance for low-voltage lighting installation (T-W4, now Missouri only; line 111); licensing and insurance of dealers in other states; whether dealer-added coverage is the dealer's obligation alone (T-W7); whether certificates are current and tracked for renewal.

No guide, export, store listing, privacy text, tester text or print form carries any license, insurance, bonding, liability or terms statement: a search for licence, license, insur, bonded, liabilit, indemn, terms of service and terms and conditions over the maintained set and the exports finds only FACTS rows and the one allowed licensed-professional sentence. A new claims-policy row (`33-claims-policy.md:28`) says public text carries no such claim until the owner approves wording. The sentence "Local dealers may add additional coverage at their discretion." stays where Phase 7 placed it and stays flagged for the owner's look before it reaches a public listing.

The guard does not flag licence, insurance, bonding or liability words; its only warranty rule is the "lifetime warranty" ban. Its logic was not changed; the new claims-policy row is the control, and the owner can ask for a guard rule later.

## Print forms re-rendered

Every changed page rendered to PNG at 100 dpi in colour and grayscale and looked at (md-to-pdf 5.2.5; same measures as before).

| Form | Pages | dark % per page | fill % | fill % −mark | mid % | darkest pixel |
|---|---|---|---|---|---|---|
| P1 Pre-install bench sheet | 3 | 3.25 / 2.81 / 1.20 | 0.001 / 0.000 / 0.000 | 0.000 | 3.6 / 3.1 / 1.6 | 17 |
| P2 Install-day sheet | 3 | 3.89 / 2.93 / 2.88 | 0.001 / 0.000 / 0.000 | 0.000 | 4.1 / 3.7 / 3.3 | 17 |
| P3 Site and controller record | 3 | 1.60 / 1.51 / 0.60 | 0.000 / 0.000 / 0.000 | 0.000 | 3.7 / 2.3 / 1.7 | 17 |

Dark fill apart from text and rules: 0 (the 0.001 % on each first page is the mark). Pen room on every field; the grayscale renders match.

## Guard, exports, Drive, verification

- `node scripts/docs_guard.mjs`: 44 files checked, 119 facts, 0 failures, 0 warnings.
- Throwaway page under `docs/guides/`, deleted afterwards: "Our electrician runs the wiring. The electrical work is ours." produced exactly two failures (the trade word; unnegated "electrical work"); the full public wording and "We do no line-voltage work." produced none; after deletion the guard returned to 0 failures.
- `node scripts/docs_guard.mjs --links-all`: 0 failures in the maintained set; the 516 archive warnings are unchanged.
- `bash scripts/docs_exports.sh`: 17 exports plus 3 print forms regenerated; every one passes the guard. Compared with `9dcb2bb`, 13 changed in content and the rest are byte-identical; `DRIVE_SWAP_CHECKLIST.md` section H lists exactly which uploads changed this round (`store-listings-and-website-notes.md` is unchanged this round and stays flagged).
- PII scan over every added line of this round and every commit message (email, phone, private IP, MAC, 12-hex id, 28-character id, PIN value, password value, uid prefix, known names): 0 hits.
- `MERGE_PLAN.md`: prepared, NOT run (no-ff, tree check, no tag); the trigger re-read from `codemagic.yaml` lines 24–29 (`events: [tag]`, `tag_patterns: build-*`): a docs commit or merge pushed to release starts no build.

## Still UNVERIFIED

That an insurer or licensing authority classifies the work the same way as the public "line-voltage" wording (T-W12); every insurance and licensing detail in T-W13; whether Missouri requires a license or insurance (T-W4); whether dealer-added coverage is the dealer's obligation alone (T-W7); the remaining boundary edge cases (T-W3: outlets that are not weatherproof or GFCI, junction boxes, where the supply mounts, fusing, extension cords, permits and inspections); everything firmware-side in T-F6, T-F8, T-F10; the "Access Point opens" labels (T-A5); Skikbily outputs beyond four (T-X5); mail delivery to general@nex-genled.com (T-SU2); the out-of-box controller network name (T-A1); the Drive items in checklist section F.

*Last verified: 2026-10-12.*
