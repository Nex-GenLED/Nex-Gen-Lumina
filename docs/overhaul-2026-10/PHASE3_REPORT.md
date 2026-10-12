# Phase 3 (rewrite) and Phase 4 (verify) — report

Branch `docs/overhaul-2026-10`, base `c283d62`. Documents only: no in-app string changed, no build, test or analyzer run, nothing written to any controller, bridge, Firestore document or config, `codemagic.yaml` untouched, no tag.

## What landed, in commit order

| Commit | Audience | Content |
|---|---|---|
| `aad0077` | installer | SOP §2.0 replaced by "record the version, never flash"; setup-AP password, a real bridge id and a sample credential removed; two PDF renders dropped. P1 1–7. |
| `c2cd4ee` | customer | Both homeowner guides: Alexa/Google not available; no cut-the-strips advice; bridge reset is an installer step, not a web page. P1 9, 10, 12, 17–19. |
| `99b24ac`, `8051457` | staff | The owner's two existing redaction commits, cherry-picked onto this branch (the Phase 1 bridge audit). |
| `521c0aa` | staff | PIN values and a controller id redacted at HEAD in the admin guide and five audit notes; the admin guide PDF dropped. P1 8. (Cleanup only: the values were rotated 2026-08-29.) |
| `2dcce8a` | engineering | Both voice deployment guides become status pages without deploy commands; SECURITY.md no longer instructs a forced rules deploy; CLAUDE.md gains the firmware policy and the real voice/audio/test status; the website prompts archived with a do-not-use note. P1 21–26. |
| `0f62e8a` | all | `docs/FACTS.md` (97 facts, status, build, verified date, 21 UNVERIFIED questions); `docs/guides/README.md`; the claims policy. |
| `c9622a8` | customer | Eight pages: getting started, everyday use, Lumina AI, scheduling, Game Day, power outage, troubleshooting trees, FAQ. |
| `8c5a39b` | installer | Install checklist, controller setup, bridge guide (merged from two), bench SOP. |
| `bf061b5` | dealer | Dealer guide (merged from four), sales mode. |
| `c20b1ad` | internal | Admin operations (no PIN values), release notes 110–116 with tester text, bridge firmware. |
| `0ea9518` | archive | 16 August guides, 8 September drafts and 9 root drafts moved to `docs/archive/` with notes; 16 PDF renders removed from the tree; `docs/archive/INDEX.md`; README, CLAUDE.md, `esp32-bridge/README.md` and `audit/README.md` repointed. |
| `5ba5911` | tooling | `scripts/docs_guard.mjs`, `scripts/docs_guard_allow.txt`, `scripts/docs_exports.sh`; ledger convention 6. |
| `f89c5ca` | Drive | `docs/drive-exports/`: 17 replacement files, not published. |
| (this commit) | — | `APP_STRINGS_PROPOSAL.md`, this report, security-items update, SECURITY.md line corrections. |

The in-app P1s (findings 9, 11, 13–16, 20) are written up, not changed: `APP_STRINGS_PROPOSAL.md`, ranked, for a separate branch after the bus-repair branch lands.

## P1 status (26)

| # | Finding | Closed by |
|---|---|---|
| 1–5 | Firmware pin / flash mandates in the SOP, the installer guide and the untracked hardware-requirements doc | `aad0077` (SOP, installer guide, now archived with the fix); the untracked main-tree file is outside this branch: delete or correct it locally (listed below). |
| 6–7 | Setup-AP password printed in the SOP | `aad0077`; policy in FACTS T-A2/T-A3; per-unit password and AP-off steps in the checklist and SOP (`8c5a39b`). |
| 8 | PIN values in the admin guide and copies | `521c0aa` at HEAD (cleanup; rotated 2026-08-29). Drive PDFs: replace from `docs/drive-exports/` or pull. |
| 9, 10 | Cut-the-strips FAQ (app, guide) | guide: `c2cd4ee`; app: proposal #6. |
| 11 | "Reflash the bridge" app message | proposal #1 (first in the ranked list). |
| 12 | Bridge "dashboard" reset in the homeowner guide | `c2cd4ee`. |
| 13–16 | Voice advertising in the app | proposal #2–#5. |
| 17–19 | Alexa/Google "fixed" or "guided" in the guides | `c2cd4ee`; the new set never mentions them except to say not available. |
| 20 | "Try updating your firmware" app reply | proposal #7. |
| 21–23 | Dangerous deploy instructions | `2dcce8a`. |
| 24–26 | False privacy / data-safety claims in the website prompts | `2dcce8a` (archived, do-not-use); corrected text in `docs/drive-exports/`. |

## Phase 4 verification

- **Fact tracing.** Every guide page lists the fact ids it used; the guard rejects an id that is not in FACTS and rejects an unshipped fact described as available. Result: `docs_guard: 37 files checked, 97 facts, 0 failure(s)`.
- **Labels.** Every bold label in the guides was matched against string literals in `lib/` (case-insensitive). Three were wrong and fixed before commit: "Segment Setup" (the screen is **Roofline Segments**), "Ethernet" (not a label), and "Set Up Controller" spellings. The allow-list is empty.
- **Links and paths.** `node scripts/docs_guard.mjs --links-all`: 0 failures in the maintained set; 516 warnings, all inside archived engineering records (`audit/`, `docs/audits/`, `docs/submissions/`) whose links are repo-root-relative. They are historical and were not edited.
- **Archived or removed.** 16 PDFs removed from the tree (renders of older text; one carried rotated PIN values); 35 files moved under `docs/archive/` with an ARCHIVE NOTE each and an index. Nothing deleted from history.
- **PII scan of every added line and every commit message since `c283d62`.** Emails: none except the legacy bridge account name that appears in the owner's own two redaction commits (an internal identity on a `.local` domain, no password). Private addresses: only the bridge portal address `192.168.4.1`. Ids: only the synthetic example id. PIN or password patterns: none. Customer names: none.
- **Guard passes.** Yes, at `HEAD`.
- **Not run (by instruction):** `flutter analyze`, `flutter test`, any build. The Dart test proposed in Phase 2 (`test/docs/facts_consistency_test.dart`) was NOT added, because an un-analyzed Dart file could break the next gate; it stays a follow-up for a branch that runs the gates.

## Deviations from the Phase 2 proposal

- `audit/`, `docs/audits/`, `docs/submissions/` and the dated design notes are archived in place (README + index) rather than moved: moving ~100 files would break hundreds of links in the tracker and ledger for no reader benefit.
- `SECURITY.md` got the P1 fix plus five line corrections (non-existent files, the key name, a non-existent helper, the retention claim); the full rewrite from code is still owed.
- `docs/BUGS_AND_DEBT.md` keeps its references to the old guide paths (they are historical narrative in debt entries); `docs/archive/INDEX.md` maps old to new. Two code comments in `lib/` reference old doc paths; no in-app effect.
- Convention 6 was added to the ledger (five conventions existed, not eight).

## Still UNVERIFIED (full list in `docs/FACTS.md`)

The TestFlight build number testers see; TestFlight group type; the live Android closed-testing build and tester count; the out-of-box controller network name; the canonical GPIO map (likely app bug: the editor assigns from 0,1,2,3,4,5,12,13 while installed units use the outputs printed on the controller); whether the Skikbily build supports turning the AP off while connected; the one support mailbox; what the lights return to when a game ends after the schedule's off time; the bridge-gap cause; solar offsets; Neighborhood Sync fanout scope; a controller status LED; 2.4 GHz / 12 V claims; solar recompute timing; "Live Scoring alone does nothing"; crew member cap; whether a bridge USB reflash clears pairing; SMS delivery dependencies; the tutorials playlist; account-deletion purge scope.

## What the owner must do

1. **Mailbox.** Decide the one support address. Until then every page says "open Help in the app". When decided: add it to FACTS T-SU2 and run `scripts/docs_exports.sh`.
2. **SSID.** Confirm what a Skikbily controller broadcasts out of the box; the guides say "the network named on your controller's label" (FACTS T-A1).
3. **GPIO.** Decide the canonical map, or file the app bug: the hardware editor's fixed output list vs installed units' labelled outputs (FACTS T-X5). The guides tell installers to read the controller's labels.
4. **Skikbily answers.** (a) Does the build support turning the setup network off while connected (FACTS T-A5)? (b) Out-of-box network name (T-A1). Until answered the AP-off step stays flagged UNVERIFIED and nobody experiments on a controller.
5. **PIN check.** The redactions at HEAD are cleanup (rotation of 2026-08-29 holds). Replace or pull the two Drive copies of the Admin Operations PDF (`docs/drive-exports/Admin_Operations_Guide.md` is the replacement text) and the rest of the "Lumina How-To's" folder from `docs/drive-exports/`.
6. **Untracked local files** in the main checkout: `docs/CONTROLLER_HARDWARE_REQUIREMENTS.md` still states the firmware pin (P1 5) and carries a real id and a bench address; the local copies of `docs/guides-2026-09/` are stale; `docs/ip/` must never be committed.
7. **App strings.** Open `APP_STRINGS_PROPOSAL.md` on its own branch after the bus-repair branch, with the accessibility harness and the full gates.
8. **Website and store listings.** Export their text into `docs/drive-exports/` for the next pass; apply `store-listings-and-website-notes.md` meanwhile.

*Last verified: 2026-10-09.*
