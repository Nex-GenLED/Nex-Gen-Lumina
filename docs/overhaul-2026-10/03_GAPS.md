# Gaps — tasks a customer, installer or dealer must do that no document covers today

Each gap names the truth-table rows the new page will draw from. "Partly" means a document touches it but with wrong or missing steps.

## Customer

| # | Task | Covered today? | Facts |
|---|---|---|---|
| C1 | First-time setup: accept the installer's invitation, install the test build, sign in, see the controller, run a look | Partly (old homeowner guide says "download from the store"; the September draft says invitation) | T-O8, T-B3, T-B4 |
| C2 | Install on a new phone and pick the right controller (Set as Active); what the stale-selection messages mean | No | T-S2, T-S4, T-R3 |
| C3 | Switch accounts on the same phone (household, or after an installer visit) | No (the September guide tells customers never to touch Controllers) | T-S1, T-S2 |
| C4 | Join a new home Wi-Fi after a router change: what the controller's setup network is, that the bridge's network is different, and whether to call the installer | Partly, with the wrong network name | T-A1, T-A4, T-R9 |
| C5 | Lights are dark: a decision tree (power, home Wi-Fi, Direct vs Via Bridge, Reconnect, installer) | Partly (one FAQ with a reboot step and no reconnect) | T-R2, T-R10, T-P2 |
| C6 | Lights are the wrong look or only part of the house changed (mixed channels, left-out channel) | No | #165 (Now Playing reads segment 0), channel bar "left out" copy |
| C7 | After a power outage: why one plain look, why a channel is wrong, the one step that fixes it | No | T-P1, T-P2 |
| C8 | What "base lighting" / "everyday look" is (Lumina Blue), what the repair banner means, that opening the app does not repair it today | No | T-GD4, T-GD6, T-GD7 |
| C9 | Game Day end to end: set a team, what to do before kickoff (app open at home within 48 h), the banner (servers / this phone / blocked), what happens at kickoff, during (celebrations need the app open), after (back to preset 1), the 8-hour cap, and what NOT to touch (the controller's own pages, buses) | Partly, contradictory ("needs the app open" vs "runs on its own") | T-GD1..T-GD10 |
| C10 | Change or remove a team; Team Priority; Skip day games; Alerts | Partly | T-GD9, in-app labels |
| C11 | Celebrations: Short / Medium / Long, 5–60 s, always ends, no extra-point celebration, phone-only | No | T-C1..T-C3 |
| C12 | Lumina AI: which phrases change the lights now vs save a repeating schedule vs save those nights only; "Sent to: All N channels" | No | T-L1..T-L4 |
| C13 | Scheduling: repeating vs "Just this day"; the two limits (20 saved, 8 timer slots); sunrise/sunset; what a schedule edit does when away from home | Partly | T-D1..T-D3, T-L4, T-R8 |
| C14 | Favorites: cap of 2, Replace, nothing automatic, hidden old automatic favorites | No | T-V1 |
| C15 | Explore: Recent Patterns row; the design card's Static setup (Blocks / Alternating) and LEDs per color; effect names are the controller's | No | T-E1..T-E3 |
| C16 | Away from home: what needs a bridge, every message and what it means, the ten-minute gap, what Test Bridge does | Partly | T-R1, T-R2, T-R7, T-R10 |
| C17 | Remove a controller from the account (deletes its saved settings) | No | manage_controllers_page.dart |
| C18 | Voice: only Siri Shortcuts (iPhone) and Android app shortcuts; how to add a look to Siri | Partly (in-app only) | T-VA2, T-VA3 |
| C19 | Support: who to contact (dealer card vs corporate card), what to include (date, time, which game), hours | Partly (four mailboxes) | T-SU1, T-SU2 |
| C20 | Which build to install / how to update (TestFlight "Previous Builds", Play closed testing) | Only in ledger tester text | T-B1, T-B2, T-B4 |
| C21 | Manual day-add writes a repeating item: the workaround ("Just this day") | No | T-D3, T-D1 |

## Installer

| # | Task | Covered today? | Facts |
|---|---|---|---|
| I1 | Record the firmware version; never flash, update or downgrade | No (the opposite is written) | T-F1..T-F4 |
| I2 | First-time controller setup without a flash step: power, setup network, Wi-Fi, buses, time/location, AudioReactive off | Partly (SOP, after the flash mandate) | T-A1, T-A2, SOP §2.1–2.5 |
| I3 | Secure the setup access point: turn "Always serve AP" off, set a per-unit password, where to record it | Partly (keeps the published default) | T-A2, T-A3 |
| I4 | Join home Wi-Fi on site when a controller lost its credentials (captive-portal path) | Partly | T-A1 |
| I5 | Pair a bridge: Remote Access → Set Up Bridge → Find / Pair / Verify; no web page; Test Bridge; who may pair | Partly, with a phantom web wizard | T-R4, T-R9 |
| I6 | Replace a bridge, or move one between houses: reset keeps Wi-Fi, clears pairing; same account vs different account | No | T-R4; firmware facts |
| I7 | Re-pair after a router or ISP change: portal reappears, controller may get a new address, refresh the controller record, Detect Home Network | No | T-R10 |
| I8 | Add a bus or segment after install, and what it does to Game Day; Segment Setup is installer-only | No | T-GD8, T-G1 |
| I9 | Mark a roofline after install (Design Studio → Roofline setup; merge/delete, Undo, Start over) vs the installer pixel-walk | Partly | T-G1 |
| I10 | Power-outage recovery and what to tell the customer | No | T-P1, T-P2 |
| I11 | Remove a controller from a live account (not whole-account decommissioning) | No | manage_controllers_page.dart |
| I12 | Game Day hand-off script: lease rule, foreground celebrations, base look, Length picker, what NOT to touch | Partly | T-GD3, T-GD4, T-C1, T-GD8 |
| I13 | Account switching / Set as Active after an installer visit | No | T-S1, T-S2 |
| I14 | The ten-minute bridge gap in field triage | No | T-R7 |
| I15 | Do not promise Alexa / Google Home at hand-off | No | T-VA1 |
| I16 | Colour order and the canonical GPIO map (two documents disagree with each other and with the app) | Contradictory | owner decision |
| I17 | Who marks the 50 % deposit (only the Day 1 Queue card in Installer Mode) | No | day1_queue_screen.dart |

## Dealer and Nex-Gen staff

| # | Task | Covered today? | Facts |
|---|---|---|---|
| D1 | Firmware policy for the whole network, in one place | No | T-F2, T-F3 |
| D2 | Bridge as a dealer task: pairing policy, Test Bridge, reset path, 1.2 fielded / 1.3 not flashed, gap triage | Partly | T-R4, T-R5, T-R7, T-R9 |
| D3 | Controller-selection triage after an account or installer switch | No | T-S1, T-S2, T-S4 |
| D4 | Game Day support playbook (served = bench only; lease; celebrations; restore; cap; bus-change strand; dry-run repair; the 10-09 server deploy) | No | T-GD1..T-GD10 |
| D5 | The one support mailbox, and what the in-app contact card shows per account | No (nine variants) | T-SU1, T-SU2 |
| D6 | Customer-facing claims policy: no Alexa/Google, no "lifetime warranty", no store-download instructions, no "AR", no "military-grade" | Scattered | T-VA1, T-O6, T-O8 |
| D7 | How dealers order stock (the in-app ordering screens are unreachable; the corporate Orders tab exists) | No | T-O2 |
| D8 | Power-outage recovery for support staff | No | T-P1, T-P2 |
| D9 | Tester onboarding (TestFlight group; Play closed-testing opt-in; 12 testers × 14 days) in a current document | Only in the superseded admin guide | T-B3, T-B4 |
| D10 | Analytics-required declaration and the debug_errors crash record, for support answers | No | T-O4, T-O7 |
| D11 | Neighborhood Sync fanout scope and what dealers may promise | Contradictory | T-O3 |
| D12 | Release notes per build in customer words (what changed, tester text, rollback) | Only in the ledger | ledger rows |
| D13 | Verify docs against the truth table before a build (ship checklist) | No | Phase 2 (c) |

## Engineering (not customer-facing, but instructs people)

| # | Task | Covered today? |
|---|---|---|
| E1 | What the bridge firmware actually does (six routes, 30 s heartbeat, 1 s poll, 5 s pairing poll, 5-min watchdog, relays /json/state and /json/info only, LED codes, TLS posture) | No (README describes a different firmware) |
| E2 | Bridge firmware lifecycle: 1.2 fielded, 1.3 built not flashed, no OTA, rules locked to 1.2 — widen before any 1.3 flash | No |
| E3 | Rules and functions deploy discipline (per-function deploys; rules from the matching checkout; never --force) | Contradicted by SECURITY.md and google-home/DEPLOYMENT.md |
| E4 | Voice integration status for engineers (never worked; fix branch; Android `<queries>`) | No |
