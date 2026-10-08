# Phase 1 — Inventory and truth table: report

Branch `docs/overhaul-2026-10` in worktree `C:\Flutter Projects\lumina-docs-overhaul`, cut from `release/store-submission-consolidated` @ `c283d62` (ls-remote confirmed; build-116 `d103d84` is its parent). Read-only: no existing file was changed; nothing was pushed, tagged, deployed or written to any controller, bridge, Firestore document or config. No build or test ran. All deliverables live under `docs/overhaul-2026-10/` on this branch.

## Deliverables

| File | What it is |
|---|---|
| `00_INVENTORY.md` | Every place that tells a person how to do something: 186 tracked documents (path, kind, audience, last commit, owner, size, summary), 35 untracked local files, ~586 in-app copy surfaces by area and route, the Google Drive folders reached, and the export list for things not reachable from here. |
| `01_TRUTH_TABLE.md` | 95 facts (T-B…, T-F…, T-A…, T-R…, T-S…, T-L…, T-V…, T-E…, T-D…, T-G…, T-C…, T-GD…, T-P…, T-VA…, T-SU…, T-O…, plus T-X1–T-X26 established by the cross-check), each with status and source, and the UNVERIFIED list (24 questions). |
| `02_FINDINGS.md` | The consolidated P1 table (26), the P2 table by theme, the privacy-policy rows, then the full per-document tables from all five passes (717 rows) in the format document / location / claim / verdict / correct statement [source] / severity. |
| `03_GAPS.md` | 21 customer, 17 installer, 13 dealer/staff and 4 engineering tasks no document covers. |
| `04_SECURITY_ITEMS.md` | 33 groups of credentials, identities and internal addresses (file:line and KIND only). |
| `05_INAPP_SURFACES.txt`, `06_TOPIC_SWEEP.txt`, `07–11_findings_*.txt` | The raw audit reports (values redacted). |

## Counts

| | P1 | P2 | P3 | Total |
|---|---|---|---|---|
| Findings | 26 | 233 | 458 | 717 |
| Security items (separate) | 10 credential/secret groups · 18 identity groups · 5 infrastructure groups | | | 33 groups, ~157 files |

Where the P1s sit: 7 in the app's own copy, 7 in the installer set (firmware pin ×5, AP password ×2), 5 in the customer guides, 1 in the admin guide (PIN values), 6 in engineering/marketing documents (two dangerous deploy instructions, a forced rules deploy, and three false privacy/data-safety statements in the website prompts).

## The twelve things the documents get wrong most often

1. **Firmware.** Three documents mandate "pin to 0.15.1, flash via quinled.info". The policy is the opposite: record the version, never flash. No document says so.
2. **Alexa and Google Home** are presented as available, "guided", or "fixed 2026-09-17" in two customer guides, the admin guide, both deployment guides, two security documents, the website prompts, CLAUDE.md, and in the app (Settings card with a "New" badge, the voice guide screen, Simple Mode, the installer hand-off). Linking has never worked for anyone.
3. **The bridge "web page"** (status dashboard, 3-step wizard, Factory Reset button, `/setup` URL, "enter the bridge's cloud credentials") appears in five documents. The firmware serves six JSON routes and nothing else. A reset keeps Wi-Fi and clears only the pairing.
4. **Game Day** is described three incompatible ways ("needs the app open", "runs on its own", "server fires it"). The rule is: the server runs it for the bench only; every customer runs it from the phone; the app must be open at home within 48 h before kickoff; only score celebrations need the app open during the game.
5. **"Download from the App Store / Google Play"** in nine places. The app is invitation-only; the store links in the customer emails are placeholders.
6. **Unreachable screens** (commercial shell, estimate wizard, dealer ordering, Media Mode, Admin Dashboard, Smart Presets, Geofence Controls) are documented as usable in 31 rows.
7. **Setup access point**: the app's own setup screen and the homeowner guide send customers to the bridge's network name for the controller's portal; nothing tells installers to set a non-default AP password, and the SOP prints the default one.
8. **Set as Active**: the September guide tells customers never to touch Controllers; it is the fix for the most common "nothing responds" case on builds ≤115.
9. **Power outage**: no document or in-app string mentions it; every "unplug it for 10 seconds" tip omits "then open the app at home".
10. **The ten-minute bridge gap** is in no document.
11. **Support**: nine mailbox spellings; the app ships one.
12. **Version stamps**: every guide says +89 or +98; nothing from builds 110–116 (favorites cap, Lumina all channels, "Just this day", controller selection, Recent Patterns, celebration length, Game Day banner) is documented anywhere.

## Inventory highlights

- The canonical customer/installer HTML set the July note calls `marketing/how-to-guides/` is absent from every ref in this repository.
- Two guide generations coexist on the branch: the +89 set (16 documents, 15 PDFs rendered 2026-08-27, six marked SUPERSEDED, nine not) and the +98 September drafts (8 files). The main checkout holds LOCAL copies of the September drafts that differ from the committed ones; the committed homeowner draft carries the wrong Alexa/Google claim, the local copy carries the right one.
- Google Drive: the "Lumina How-To's" shared folder holds 13 PDFs (2026-08-27) whose bytes differ from the repo PDFs of the same day; the NEX-GEN Hub "Lumina Dealer Docs and How-To's" folder is empty; two April PDFs sit at the shared-drive root; the Admin Operations Guide PDF (two copies) carries the master PIN values. The privacy policy document promises an analytics opt-out and public store availability that do not exist.
- Not reachable from here, export needed: both store listings and data-safety/App Privacy answers, TestFlight "What to Test" notes, the website pages (voice, "control from anywhere", warranty, download CTAs, privacy page), any printed leave-behinds, the YouTube tutorials playlist.
- Release notes exist only as the "Tester text" paragraphs in ledger rows +112…+116; CHANGELOG.md stopped at 2.1.0 in March.

## Security items (summary; the list is separate)

Live master/admin/dev PIN values in the admin guide and its three PDF copies; the controller setup-AP password in the SOP; a sample temporary password; the historical bridge credential still present at `c283d62`; two literal Google API keys; customer names, personal emails, home LAN addresses, bridge ids and user ids across ~45 internal audit files and one runbook; the owner's personal email in four audits; the reviewer account identity; a stray committed WLED config dump with a Wi-Fi SSID; the owner's bench addresses in ~40 files. Rotation and tree cleanup belong to the security branch; this branch's rewrites will not carry any of these values forward.

## UNVERIFIED (full list in `01_TRUTH_TABLE.md`)

Build number testers see for 116; TestFlight external vs internal; the live Android closed-testing build and tester count; evidence that USB flashing bricks a current unit (the repo records one successful July reflash of an older unit); whether the 0.15.4 stall affects September-cohort units; the out-of-box SSID of a Skikbily controller; what the lights return to when a game ends after the schedule's OFF time; the cause of the ten-minute bridge gaps; the one support mailbox; the Neighborhood Sync fanout scope; solar offsets; whether customers may pair a replacement bridge; the canonical GPIO map; the controller status LED; 2.4 GHz / 12 V claims; solar recompute timing; "Live Scoring alone does nothing"; crew member cap; whether a bridge reflash clears pairing; SMS delivery dependencies; the tutorials playlist; account-deletion purge scope.

## What Phase 2 proposes (next file)

A single `docs/FACTS.md`, one guide set per audience, 15 guides to create/merge/rewrite and ~45 files to archive, a three-layer staleness guard with a ship-checklist convention, 19 in-app string changes (one app build, separate approval), and a seven-day sequence with the P1s on day one.
