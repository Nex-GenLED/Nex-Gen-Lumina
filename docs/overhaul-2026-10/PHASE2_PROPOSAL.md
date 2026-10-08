# Phase 2 — Proposal (read-only; nothing below is applied until "approved")

Base: `release/store-submission-consolidated` @ `c283d62` (app 2.5.10+116). Everything here draws on `01_TRUTH_TABLE.md`, `02_FINDINGS.md` and `03_GAPS.md`.

## (a) Information architecture — one source of truth, four audiences

```
docs/
  FACTS.md                        ← THE single source of truth. One row per fact: id, plain statement,
                                     status (SHIPPED build N / BUILT NOT SHIPPED / NOT BUILT / NEVER WORKED /
                                     UNVERIFIED), source (file:line, ledger row, measured result), the build
                                     it applies to, date last verified. Seeded from 01_TRUTH_TABLE.md.
  guides/
    customer/
      00-getting-started.md
      01-everyday-use.md
      02-lumina-ai.md
      03-scheduling.md
      04-game-day.md
      05-power-outage-and-recovery.md
      06-troubleshooting.md          (decision trees)
      07-faq.md
    installer/
      10-install-checklist.md
      11-controller-setup.md
      12-bridge-guide.md
      13-installer-sop.md
    dealer/
      20-dealer-guide.md
      21-sales-mode.md
    internal/
      30-admin-operations.md
      31-release-notes.md            (one entry per build, with the tester text)
      32-bridge-firmware.md          (what the firmware does; 1.2 / 1.3 / rules)
      33-claims-policy.md            (what may be said to customers and on the website)
  archive/
    INDEX.md                        (every archived file: why, when, what replaced it)
    <moved files, each with an ARCHIVE NOTE header>
  drive-exports/                    (Phase 3: finished replacement text for Drive and the stores)
```

Rules:
1. A fact lives in `docs/FACTS.md` once. A guide states it in the reader's words and tags it `<!-- fact: T-R2 -->` so the guard can trace it.
2. One audience per page. A customer page never contains an installer step; it says "ask your installer" and links the installer page by name.
3. Nothing unshipped is described as available. BUILT-NOT-SHIPPED renders as "coming" with no date, or is left out. NEVER WORKED is left out entirely.
4. Every page opens with `Describes build: 2.5.10+116 · Last verified: 2026-MM-DD` and closes with the fact ids it used.
5. PDFs are renders, never sources. They leave the repo; `drive-exports/` holds the renders produced at export time from the Markdown, so one text cannot drift from another.
6. Exact on-screen labels in **bold**, spelled as `lib/` spells them. The guard checks them.
7. No credential, address, id or customer detail, ever. Placeholders read `<your Wi-Fi name>`.

## (b) Guides to create, merge, rewrite, archive

| Action | Page | Purpose (one line) | Built from | Day |
|---|---|---|---|---|
| CREATE | customer/00-getting-started | From the installer's invitation to the first look: install the test build, sign in, see the controller, run a look, where things live (5 tabs). | 02-homeowner §1–3, first-run and tour copy, T-O8, T-B1 | 3 |
| CREATE | customer/01-everyday-use | Power, brightness, channels (and "left out"), favorites (2, Replace), Explore collections, Recent Patterns, the design card (Blocks / Alternating, LEDs per color), Direct vs Via Bridge. | T-V1, T-E1–E3, T-R10, T-X20, T-X22 | 3 |
| CREATE | customer/02-lumina-ai | What to say: plain phrases change the lights now; "every night / every Friday" saves a repeating schedule; "tonight / this weekend" saves those nights only. "Sent to: All N channels". Limits. | T-L1–L4, T-X14, T-X21 | 4 |
| CREATE | customer/03-scheduling | Repeating vs **Just this day**; 20 saved / 8 timer slots; sunrise/sunset; edits away from home apply when you are home; the manual day-add workaround. | T-D1–D3, T-L4, T-R8 | 4 |
| CREATE | customer/04-game-day | What it does; set a team; before kickoff (app open at home within 48 h); the banner (servers / this phone / blocked); during (celebrations need the app open; Short/Medium/Long); after (back to your everyday look, Lumina Blue on new systems); the 8-hour cap; what NOT to touch. | T-GD1–GD10, T-C1–C3 | 4 |
| CREATE | customer/05-power-outage-and-recovery | What the lights do after a power cut, why one channel may look wrong, the one step that fixes it. | T-P1, T-P2 | 4 |
| CREATE | customer/06-troubleshooting | Decision trees: lights are dark · wrong look · "I'm away from home" · slow or failed remote command (ten-minute gap) · Game Day didn't switch back · nothing responds on a new phone or after switching accounts (Set as Active) · voice isn't available · schedule didn't run. | T-R2, T-R3, T-R7, T-S2, T-VA1, T-GD5/6, T-X19 | 4 |
| CREATE | customer/07-faq | Twenty short answers linking into the pages above; replaces the four in-app FAQs' content. | all | 4 |
| REWRITE | installer/10-install-checklist | The day-of checklist. Firmware: record the version, never flash. Setup network: join it, enter Wi-Fi, turn "Always serve AP" off, set a per-unit password (recorded off-repo). Buses, time/location, AudioReactive off, roofline, hand-off script. | SOP §2.1–2.8 (minus §2.0), 04-installer §3, T-F2, T-A1–A2, T-X25 | 5 |
| REWRITE | installer/11-controller-setup | Buses = channels; Segment Setup (installer-only); the roofline walkthrough; adding a bus after install and what it does to Game Day; colour order RGB; the canonical pin map (after the owner's decision). | T-G1, T-G2, T-GD8, T-X4, T-X5 | 5 |
| MERGE | installer/12-bridge-guide | ESP32_Bridge_Setup_Guide + 07-bridge-setup-guide → one installer-facing guide: what the bridge is, pair (Find / Pair / Verify), Test Bridge (10 s), Reconfigure / Unpair, reset (POST /api/reset keeps Wi-Fi), replace, move house, router change, LED codes, the ten-minute gap, what the bridge cannot do (schedules, config). | T-R1–R10, T-X1–X3 | 5 |
| REWRITE | installer/13-installer-sop | The shop SOP without §2.0 and without any credential or real id; labelling, pairing strategy (installer pairs), troubleshooting. Appendix A (repo flashing) moves to internal/32. | dealer_preinstall_setup.md | 5 |
| MERGE | dealer/20-dealer-guide | Dealer_Dashboard_Guide + 05-dealer-guide + the dealer parts of full-job-lifecycle and nex-gen-operations-overview → one: entry, six tabs, the deposit gate, pipeline statuses, team, payouts, messaging config, claims policy, what is not available (ordering, waste intelligence). | T-X9–X13, T-O2, T-O6 | 6 |
| REWRITE | dealer/21-sales-mode | Sales mode as it is: Prospect → Zones → Review → Estimate → Sign; no estimate wizard; warranty wording; deposit hand-off. | sales-mode-guide.md, T-X11, T-X13 | 6 |
| MERGE | internal/30-admin-operations | Admin_Operations_Guide (minus every PIN value) + 06-admin-guide + corporate-dashboard-guide + messaging-configuration-guide → one staff guide: tiers, corporate dashboard (5 tabs), PIN rotation in-app, tester onboarding, account deletion, support escalation table, Game Day support playbook, feature-flag table with live values marked "read the console". | T-X8–X10, T-GD1–GD8, T-B3–B4, T-O3–O4 | 6 |
| CREATE | internal/31-release-notes | One entry per build 110→116 (what changed in customer words, tester text, rollback note), then one per future build, copied from the ledger row at ship time. | ledger rows | 6 |
| CREATE | internal/32-bridge-firmware | What fw 1.2 does (six routes, timings, LED codes, TLS), 1.3 status, no OTA, rules locked to 1.2 — widen before any flash; bench flashing procedure (from SOP Appendix A). | T-R5, T-X1, T-X3 | 6 |
| CREATE | internal/33-claims-policy | One page: never say Alexa/Google, "lifetime warranty", "download from the store", "AR", "military-grade", "SOC 2", "90-day retention", "export your data", "opt out of analytics"; what may be said instead. Drives the website rewrite and both store listings. | T-VA1, T-O4, T-O6, T-O8, T-X14–X16 | 2 |
| KEEP+FIX | README.md, CLAUDE.md | README points at `docs/guides/` and says invitation-only; CLAUDE.md gets the firmware policy, voice status, "425 tests", timer counts, palette file, round-trip figures, bridge limits, deploy discipline, and drops the superseded guide pointer. | findings | 2 |
| REWRITE | SECURITY.md | Rebuilt from code: what is encrypted, limits, retention (incl. the `claude_usage` gap as a tracker item), deploy discipline (per-function; rules from the matching checkout; never `--force`), Alexa/Google status, bridge posture, analytics declaration. | T-X14–X17 | 6 |
| ARCHIVE | docs/guides-2026-09/* (8) | Superseded by the new set; the README's grounding notes are folded into FACTS. | — | 6 |
| ARCHIVE | docs/Lumina_Homeowner_Guide, User_Guide_Commercial, Media_Mode_Guide, Dealer_Installer_Setup_Guide, Dealer_Dashboard_Guide, Admin_Operations_Guide (PIN values replaced by `<REDACTED>` in the archived copy — owner decision, see below), ESP32_Bridge_Setup_Guide, corporate-dashboard-guide, dealer-inventory-guide, full-job-lifecycle, messaging-configuration-guide, nex-gen-operations-overview, day1-electrician-guide, day2-install-guide, sales-mode-guide, dealer_preinstall_setup (16 .md) and their 15 PDFs | Each folds into a new page or describes unreachable screens. Archived with a note naming the replacement; PDFs are dropped from the tree (recoverable from history). | findings | 6 |
| ARCHIVE | CHANGELOG.md, LANDINGSITE_AI_PROMPTS.md, SECURITY_SUMMARY.md, INTEGRATION_COMPLETE.md, LEARNING_SYSTEM.md, ANALYTICS_SYSTEM.md, GUIDED_MODE_IMPLEMENTATION.md, demo_review_report.md, neighborhood_sync_audit_report.md, TASK_TEST_PLAN.md, esp32-bridge/README.md (replaced by a two-line pointer to internal/32), alexa-skill/DEPLOYMENT.md and google-home/DEPLOYMENT.md (replaced by a one-paragraph status page pointing at internal/33 and the fix branch; the dangerous commands go) | Dated engineering or marketing drafts; none describes the product today. | findings | 6 |
| ARCHIVE (bulk, indexed) | audit/* (79), docs/audits/* (11), docs/submissions/* (8), the dated docs/*_audit*.md, design notes and runbooks | Engineering records: keep, do not maintain, index in `archive/INDEX.md` by topic and date. Addresses and identities inside them are the security branch's job; the index never repeats them. | inventory | 6 |
| DELETE from the tree (history keeps it) | the stray root file with the mangled temp-path name (WLED cfg dump) | Not a document; contains a Wi-Fi SSID. | S30 | 1 |

Owner decision needed before Day 1: the archived copy of `Admin_Operations_Guide.md` either (a) keeps its text with the 14 PIN values replaced by `<REDACTED>` on this branch (the history rewrite stays with the security branch), or (b) is left untouched here and handled entirely by the security branch. I recommend (a): the values must not survive into any rendered export, and the archive note is a content change, not a history change.

## (c) Staleness guard — three layers

1. **`scripts/docs_guard.mjs`** (Node, no dependencies; runs in under a second). Fails when any file under `docs/guides/` or `docs/FACTS.md`:
   - names a **bold** label of up to six words, starting with a capital letter, that does not occur as a string literal in `lib/` (the guard extracts `Text('…')`, `label:`, `title:`, `tooltip:` and `const String k… = '…'` literals once per run; an allow-list file `scripts/docs_guard_allow.txt` holds bold prose that is not a label);
   - names a route, file path or doc path that does not exist (`/settings/…`, `lib/…`, `docs/…`);
   - states a build number above `pubspec.yaml` or below the page's own `Describes build`;
   - cites a fact id absent from `docs/FACTS.md`, or cites a fact whose status is BUILT-NOT-SHIPPED, NOT BUILT or NEVER WORKED without the word "coming" in the same paragraph;
   - contains a banned phrase from `internal/33-claims-policy` (`quinled`, `flash the`, `0.15.1` outside FACTS.md, `Alexa`, `Google Home`, `Google Assistant`, `lifetime warranty`, `http://<bridge-ip>/`, `Factory Reset button`, `/setup`, `Upload system logs`, `Lumina-XXXX` in a sentence about the controller, `App Store` / `Google Play` in a sentence about downloading, `AR `, `military-grade`, `SOC 2`);
   - contains an email, phone, password-shaped string, 4-digit PIN after the word PIN, private IP, MAC, bridge id or 28-character uid pattern anywhere under `docs/` (same regexes as the PII scan; placeholders allow-listed);
   - has no `Last verified:` line, or one older than 90 days (warning until Phase 3 lands, then failure);
   - has a `[text](path)` link whose target does not exist (link and path checker).
2. **`test/docs/facts_consistency_test.dart`** — reads `docs/FACTS.md` and asserts the constants it quotes against code: `kMaxFavorites == 2`, the base-look RGB, `kLeaseWindow == 48 h`, the exact blocked-apply sentences, the Set as Active label, the route `/settings/voice-assistants`, `kAppVersion`, the hard-cap duration, the timer-slot count. Same pattern as `test/services/bridge_api_client_endpoints_test.dart`, which already parses `esp32-bridge/src/main.cpp`.
3. **Ship checklist** — a new convention 9 in `docs/BUILD_LEDGER.md` "STANDING BUILD CONVENTIONS" (after convention 8, line ~150): *"Before the bump: `node scripts/docs_guard.mjs` passes; every `docs/FACTS.md` row this build touches is re-stamped (status, build, date); the row's tester text is copied into `docs/guides/internal/31-release-notes.md`. The ledger row records the guard's output line."* The guard also runs in Codemagic's "Test and analyze" step as one line before `flutter test`. (Adding it to `codemagic.yaml` is a tracked change; it rides with the first Phase 3 commit that creates the script, or stays local until the owner says.)

## (d) In-app self-help changes — PROPOSALS ONLY (one app build; separate branch and approval; gates at 1.0 / 1.75 / 2.0 with Bold Text)

Strings are exact. "Docs-only" items need no build.

| # | Screen / file:line | Today | Proposed string | Why | Needs |
|---|---|---|---|---|---|
| 1 | Settings → Voice Assistants card, `settings_page.dart:857–871` | "Voice Assistants — Set up Siri, Google, or Alexa control" + "New" badge | **Voice Assistants** — "Siri Shortcuts on iPhone. App shortcuts on Android." No badge. | T-VA1 | app build |
| 2 | Voice guide screen, `voice_assistant_guide_screen.dart` (hero :87–93; Google card :299–570; Alexa card :612–835) | Google and Alexa cards with Link buttons | Remove both cards. Hero: "Say \"Hey Siri, [your phrase]\" to put a saved look on your lights. On Android, long-press the Lumina icon for shortcuts." | T-VA1, T-VA2 | app build |
| 3 | Simple Mode dialog `settings_page.dart:1306`; installer hand-off `handoff_screen.dart:544` | "Voice assistant setup" / "Voice assistant setup guides" | "Siri Shortcuts (iPhone)" | T-VA1 | app build |
| 4 | Help Center FAQs, `help_center_screen.dart:12–27` | Four FAQs (two wrong, one dangerous) | Replace with seven: **My lights are dark.** "Check that the controller is plugged in and its outlet is on. Then open Lumina at home: the Home screen should say Direct. If it says Can't reach your lights, tap Reconnect. Still dark? Contact your installer from Support & Resources." · **My lights look wrong after a power outage.** "After a power cut the controller shows one plain look across the whole roofline until the app reconnects. Open Lumina on your home Wi-Fi and wait a minute. Your channels and your next schedule come back on their own. Nothing is lost." · **The app says I'm away from home.** "On your home Wi-Fi, Lumina talks to your lights directly. Away from home it needs a Lumina Bridge, which your installer sets up. If you have a bridge and see this at home, open System & Device Management → Remote Access and tap Detect Home Network." · **Game Day didn't switch back.** "Your lights return to your everyday look when the game ends. If they are still in team colours an hour after the final, open the app at home and tap your everyday schedule, or turn the lights off and on from Home. Then tell your installer which game it was." · **Nothing responds on a new phone.** "Open System & Device Management → Controllers and tap Set as Active on your controller." · **Can I use Alexa or Google Home?** "Not yet. Siri Shortcuts work on iPhone today. On Android, long-press the Lumina icon for shortcuts." · **Who do I contact?** "Tap Contact Nex-Gen Support above. It shows your installer's phone and email, or Nex-Gen LED's if your installer hasn't been added." The cut-the-strips FAQ is removed. | gaps C2, C5, C7, C9, C18, C19 | app build |
| 5 | Game Day pre-flight reason, `game_day_server_status.dart:252` | "Your everyday lighting settings need repairing. Opening the app at home repairs them." | "Your everyday lighting settings need repairing. Contact your installer or Nex-Gen support." (When the Repair card ships: "…Tap Repair base lighting below.") | T-GD6, T-GD7 | app build |
| 6 | Bridge setup, `bridge_setup_screen.dart:367` | "This bridge firmware is outdated. Please reflash the bridge…" | "This bridge needs servicing. Contact your installer." | T-R5 | app build |
| 7 | Bridge setup, `bridge_setup_screen.dart:529` | "…(Settings → Remote Access → Unpair Bridge)" | "This bridge is paired to a different account. Its owner's installer must release it first." | T-R4 | app build |
| 8 | Bridge setup, `bridge_setup_screen.dart:266` | "Choose a controller in Site Setup before pairing a bridge." | "Choose your controller first: System & Device Management → Controllers → Set as Active." | T-S2 | app build |
| 9 | Link Controllers sheet, `settings_page.dart:294` | "Add devices in Settings > Controllers & Devices." | "Add controllers in System & Device Management → Controllers." | T-X19 | app build |
| 10 | Version tile, `settings_page.dart:631` | "Version 1.6.0 / Build 2026.01" | Read `kAppVersion`: "Version 2.5.10 (116)" | T-B1 | app build |
| 11 | Welcome wizard camera step, `welcome_wizard.dart:192` | "To map your home for effects, we use the camera in AR." | "To preview designs on a photo of your house, we use the camera." | no AR | app build |
| 12 | Clock-health remediation, `clock_health.dart:407–418` | "Open the controller in a browser … Config → Time & Macros …" | "Open Lumina on your home Wi-Fi and it will set the controller's clock. If this message is still here tomorrow, contact your installer." | healer; "what NOT to touch" | app build |
| 13 | Hardware step skip note, `hardware_config_step.dart:120` | "…from System → Hardware." | "…from System & Device Management → My Lights." | T-X19 | app build |
| 14 | `wled_providers.dart:144` (shown to homes at `system_management_screen.dart:480`) | "Connect to venue Wi-Fi to change hardware settings" | "Connect to your home Wi-Fi to change hardware settings" (keep "venue" only in commercial mode) | wording | app build |
| 15 | Game Day run-mode banner, `game_day_run_mode.dart:118` | "Your lights change for the game when the Lumina app is open at home." | "Open Lumina at home in the two days before a game so your lights are set to change at kickoff. Keep the app open during the game for score celebrations." | T-GD3 | app build |
| 16 | Manual setup step 1, `wled_manual_setup.dart:305` | "…connect to the \"Lumina-XXXX\" WiFi network…" | "…join the controller's setup Wi-Fi network (its name starts with WLED)…" — pending the owner's SSID answer | T-A4 | app build |
| 17 | Relay stale message, `bridge_pairing.dart:227` | "Your Lumina Bridge hasn't checked in for N. Check that it's powered on and online at home." | "Your Lumina Bridge hasn't checked in for N. This usually clears on its own within ten minutes. Try again then, or check that it's plugged in at home." | T-R7 | app build |
| 18 | Blocked-apply snackbars (every `ApplyBlockedReason` surface) | message only | Add a **Help** action that opens `/settings/help` (the FAQ above). | gap C16 | app build |
| 19 | Favorites add tile, `favorites_grid.dart:346` | "Add a favorite" | "Add a favorite (you can keep 2)" | T-V1 | app build |
| 20 | Profile privacy line `edit_profile_screen.dart:1070`; builder match `:1154` | "Your data is stored locally and securely." / "We have 12 saved lighting designs…" | Remove both sentences (or wire the count to data). | false claims | app build |
| 21 | Properties hint `my_properties_screen.dart:793`; Simple Mode tab list `settings_page.dart:1339`; dead favorites push `notifications_service.dart:196` | "WLED" / "Settings" / auto-favorites push | "your controller" / "System" / delete the dead string with its sender | wording | app build |
| 22 | Everything else in `02_FINDINGS.md` | — | Documents only. | — | docs-only |

Misleading status messages that point to the wrong cause (fixes above): #5 (promises a repair that does not happen), #17 (names the bridge when the gap clears itself), and T-R3's "remote access isn't set up" on a stale selection (its fix is already built on `fix/118-controller-selection` commit 3 — ship that commit rather than re-word).

## (e) Writing standard (every page, in-app string and export)

- Plain words. No internal names (healer, lease, ladder, psave, relay, fanout, census) on customer pages; use the on-screen name or none.
- Short numbered steps, one action each. The exact on-screen label in **bold**, spelled as the app spells it. Paths as **System & Device Management → Controllers**.
- One task per page; the title is the question ("Fix lights that are dark").
- After every step: "You'll see …". After every task: "If you don't: …" with one next action that ends at Support.
- State what the product does today. Unshipped = "coming" with no date, or omitted. No "should", "usually", "may" where a fact exists.
- Every page ends with `Describes build: 2.5.10+N · Last verified: YYYY-MM-DD · Facts: T-xx, T-yy`.
- Accessibility of the documents: one H1, ordered H2/H3; descriptive link text (never "here"); alt text on every screenshot saying what it shows; tables with header rows; no meaning carried by colour alone ("the red badge that reads Blocked"); sentences under 20 words; reading level about grade 7.
- Never a credential, address, id or customer detail. Placeholders read `<your Wi-Fi name>`.
- In-app strings follow the same rules and pass the text-scale harness at 1.0, 1.75 and 2.0 with Bold Text.

## (f) Effort and sequencing — P1 first, each day lands alone

| Day | Commits (by audience) | Content | P1s closed |
|---|---|---|---|
| 1 | `docs(installer): firmware policy and AP` · `docs(staff): admin guide PINs` · `chore: drop stray cfg dump` | Replace SOP §2.0 and the Dealer guide's pin warning with the "record the version, never flash" rule; redact the AP password and the real bridge id; archive the admin guide with PINs redacted (decision above); delete the stray cfg file; create `docs/FACTS.md` seeded from the truth table. | 1–8 |
| 2 | `docs(policy): claims policy` · `docs(customer): remove voice and dangerous advice` · `docs(eng): deploy discipline` | `internal/33-claims-policy`; strip Alexa/Google, cut-the-strips and the bridge dashboard from both homeowner guides (as interim edits before archive); replace the two DEPLOYMENT guides with status pages; fix SECURITY.md's forced-deploy line; fix CLAUDE.md's voice/firmware lines. | 9–26 |
| 3 | `docs(customer): getting started, everyday use` | New customer pages 00, 01. | — |
| 4 | `docs(customer): Lumina AI, scheduling, Game Day, power outage, troubleshooting, FAQ` | New customer pages 02–07. | — |
| 5 | `docs(installer): checklist, controller setup, bridge guide, SOP` | Installer pages 10–13 (bridge guide merge). | — |
| 6 | `docs(dealer): dealer guide, sales mode` · `docs(internal): admin ops, release notes, bridge firmware` · `docs(archive): move superseded guides and audits` · `chore(docs): staleness guard` | Dealer and internal pages; archive moves with INDEX; `scripts/docs_guard.mjs` + allow-list; `test/docs/facts_consistency_test.dart`; ledger convention 9; `drive-exports/` renders. | — |
| 7 (separate branch, separate approval, PC free) | `fix(copy): in-app self-help strings` | Items (d) 1–21 with the accessibility harness and full gates. | — |

Each day is small enough to review in one sitting and reverts cleanly. Phase 4 (verify, push branch only) follows day 6; the app-string branch follows its own gates.

## Decisions needed from the owner before Phase 3

1. Archive copy of the admin guide: redact PINs on this branch (recommended) or leave to the security branch.
2. The one support mailbox (T-SU2) — every page prints it.
3. Out-of-box controller SSID (T-A4) — one sentence in the installer checklist and the manual-setup screen depends on it.
4. Canonical GPIO map (T-X5).
5. Bridge pairing: installer-only, or may a customer pair a replacement (T-R9)?
6. Whether to say anything about USB flashing "bricking" units (T-F4) or simply "never flash" (recommended: the policy line only).
7. Whether `codemagic.yaml` may gain the one-line guard call on this branch or waits.
