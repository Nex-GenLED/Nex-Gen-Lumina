# Phase 5 — owner decisions of 2026-10-09 applied (documents only)

Branch `docs/overhaul-2026-10`, on top of `62f917a`. Documents only: no app code, no `codemagic.yaml` change, no build, test or analyzer, nothing written to any controller, bridge, Firestore document, config or Google Drive. Every decision is recorded in `docs/FACTS.md` with the date and "decided by owner"; what is not verified stays marked UNVERIFIED.

## Decision 1 — Drive: pull everything old, replace with the new documents

- `docs/drive-exports/DRIVE_SWAP_CHECKLIST.md`: every Drive file identified on 2026-10-08 (folder, name, size, modified date, matched git version), the action, the replacement export, the destination folder, and the upload order. Covers the 13 PDFs in "Lumina How-To's", both copies of the Admin Operations PDF, the second Dealer Dashboard copy, the capture brief, the privacy-policy document, two PDFs the repository had but the listing did not show (marked for the owner to confirm), and what populates the empty NEX-GEN Hub "Lumina Dealer Docs and How-To's" folder (the dealer-facing set; never the two staff files).
- All 18 exports were regenerated after the edits below (`bash scripts/docs_exports.sh`) and every one passes the guard. Nothing is published; uploading is the owner's step.
- Files that could not be seen are listed in section F of the checklist (PDF contents, two folders' contents, two PDFs' existence).

## Decision 2 — support mailbox: general@nex-genled.com, lowercase, everywhere

- FACTS T-SU2: decided by owner 2026-10-09; mail delivery UNVERIFIED, owner to send a test. The guard now allows exactly this address and no other.
- Replaced in every maintained guide, the claims policy, the install checklist, the SOP, the bridge guide, the dealer guide, admin operations, the release notes (every tester message now ends "Send reports to general@nex-genled.com with the date and time."), the privacy-policy corrections, the store-listing and website notes, and SECURITY.md. No "open Help in the app" fallback remains (0 matches).
- Other spellings still present:
  - Maintained documents: none (SECURITY.md:517 was the last and is replaced).
  - The app's own strings (listed in `APP_STRINGS_PROPOSAL.md` as new ranked item 22, P2):
    - `lib/features/auth/support_contact.dart:15` — already exactly general@nex-genled.com (no change).
    - `lib/features/installer/media_access_code_screen.dart:229` — "media@Nex-GenLED.com" in the Media Mode footer (unreachable screen).
    - `lib/services/reviewer_seed_service.dart:18` — "reviewer@Nex-GenLED.com", the App Store reviewer account identity, not a support address (no change unless the account is renamed).
  - Archived documents keep their old addresses, as instructed.

## Decision 3 — controller setup access point

- FACTS T-A5 reworded: the owner states the controller's interface can turn the broadcast off or show it only when not connected; exact setting names and the right option for Skikbily builds are UNVERIFIED until observed on a spare unit. T-A2 now holds the three steps.
- Installer SOP 1.2, install checklist steps 4–6, controller setup, the bridge guide's router-change section and the customer troubleshooting note now say: set a unique AP password per controller, recorded privately (never in a document, a message or the repo); set the "Access Point opens" option on the controller's Settings → Wi-Fi Setup page to one of the "when there is no connection" choices, never "never", so an installer can always reach a controller whose network is gone (labels UNVERIFIED); confirm the controller still answers on the home network before leaving the site. No controller was touched; no key or password is printed.

## Decision 4 — GPIO map: Skikbily outputs are GPIO 2, 14, 16, 18

- FACTS T-X5: decided by owner 2026-10-09. The SOP, checklist and controller-setup page map runs to those four positions; the number of outputs on a Skikbily unit is stated as UNVERIFIED beyond the four (the app's own type name says "4-Channel"); nothing claims more than four. Installers set the outputs on the controller's own LED settings page at the bench and never add a port in the app's editor until the bug is fixed.
- **App bug #187** filed in `docs/BUGS_AND_DEBT.md` (P2, "fix goes in the next app build with the strings changes and after the bus-repair branch"). Number checked against the tracker on `origin/release/store-submission-consolidated` (highest #176), `origin/fix/118-controller-selection` (#176), `origin/fix/ladder-repair-bus-change` (#184) and `origin/fix/gameday-espn-slate` (#186): #187 collides with none. The entry lists every site: `lib/features/wled/hardware_config_screen.dart:38, 57, 60, 65, 84, 145, 223, 498`; `lib/services/wled_config_pusher.dart:254, 263, 297`; `lib/features/wled/wled_hardware_config.dart:9, 28–36`; `lib/features/wled/device_channel.dart:15, 45`; `lib/features/wled/wled_service.dart:219–246`; `lib/features/installer/screens/hardware_config_step.dart:74`; `lib/features/site/manage_controllers_page.dart:145`; `lib/models/controller_type.dart:52`; tests `test/features/wled/hardware_config_buses_test.dart:43`, `test/services/wled_config_pusher_test.dart:31, 39`; the healer and ladder code compare bus bounds and ids, never pins. It gives the replacement list (per controller type; Skikbily `[2, 14, 16, 18]`; the Dig-Octa list deliberately not decided), the UI behaviour beyond four buses, the tests and goldens that change, and the risk. No code changed.

## Verification

- `node scripts/docs_guard.mjs`: 38 files checked, 97 facts, 0 failures, 0 warnings.
- `node scripts/docs_guard.mjs --links-all`: 0 failures in the maintained set; 516 warnings, all in archived engineering records with repo-root-relative links (unchanged, historical).
- PII scan of every line added in this phase: the decided mailbox (50 mentions), the two in-app spellings quoted in the proposal by request, and the synthetic example id. No private address, PIN, password, customer name or device id.
- Commit messages scanned the same way; clean.

## Prepared, not run

`MERGE_PLAN.md`: the no-ff merge into release with the tree checks, the confirmation from `codemagic.yaml` (only `build-*` tags trigger a build; a docs merge pushed to release starts nothing), no tag, and the ship-checklist line.

## Still UNVERIFIED

Mail delivery to general@nex-genled.com (owner to send a test); the exact "Access Point opens" option labels and the right choice for Skikbily builds; how many outputs a Skikbily controller has beyond the four; the out-of-box controller network name; the Dig-Octa pin list; the Drive items in checklist section F; and everything already listed in `docs/FACTS.md`.

*Last verified: 2026-10-09.*
