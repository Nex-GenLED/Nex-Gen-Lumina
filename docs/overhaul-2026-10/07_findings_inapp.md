# In-app surfaces — findings (checked against the truth table; paths relative to lib/)

Columns: Location | Claim (quoted) | Verdict | Correct statement [source] | Severity

## P1

| Location | Claim | Verdict | Correct statement | Sev |
|---|---|---|---|---|
| features/site/help_center_screen.dart:20 | "Can I cut the strips?" → "Yes, at the copper pads marked with cut lines. Ensure power is off first." | wrong / dangerous | A Lumina system is a professionally installed permanent product; the customer FAQ must not invite cutting the installed strip. Remove; replace with "Call your installer for any change to the strip." [T-R9 policy; OWNER 10-08] | P1 |
| features/site/bridge_setup_screen.dart:367 | "This bridge firmware is outdated. Please reflash the bridge with the latest firmware and try again." | wrong / risky | Bridges have no OTA; a reflash is an installer bench procedure that wipes the pairing. The customer sentence must say "Contact your installer: this bridge needs servicing." [T-R5; MEM esp32_bridge_flashing (merged image wipes NVS)] | P1 |
| features/site/settings_page.dart:857–871 | Settings card "Voice Assistants — Set up Siri, Google, or Alexa control" with a permanent "New" badge | wrong (never worked) | Alexa and Google Home linking has never worked and must not be advertised. Card text becomes "Siri Shortcuts (iPhone) and Android app shortcuts"; badge removed. [T-VA1, T-VA2; OWNER 10-08] | P1 (owner directive) |
| features/voice/voice_assistant_guide_screen.dart:93, 299–361, 396–497, 612–835 | Google Home and Amazon Alexa cards: "Link Google Home", "Link Alexa Account", "Open the Alexa app and search for 'Nex-Gen Lumina' in Skills", "Alexa is connected!", example phrase "Alexa, turn on the house lights" | wrong (never worked) | Remove both cards and the Alexa phrase from the hero until linking is deployed and proven; keep Siri Shortcuts and Android App Shortcuts. [T-VA1, T-VA2] | P1 (owner directive) |
| features/voice/google_home_service.dart:32 | setupWebUrl is a placeholder containing YOUR_PROJECT_ID | wrong | No Google action exists to link to. [T-VA1] | P1 (owner directive) |
| features/site/settings_page.dart:1306; features/installer/handoff_screen.dart:544 | Simple Mode feature list "Voice assistant setup"; installer hand-off lists "Voice assistant setup guides" | wrong | Same as above: name Siri Shortcuts only. [T-VA1] | P1 (owner directive) |
| features/ai/lumina_brain.dart:447 | "Your controller has AudioReactive firmware but no audio effects were detected. Try updating your firmware." | wrong / risky | Customers never update controller firmware. (Audio Mode is debug-only, so this is unreachable in release; the sentence still has to go before Audio Mode ever ships.) [T-F2, T-O1] | P1 (latent) |

## P2

| Location | Claim | Verdict | Correct statement | Sev |
|---|---|---|---|---|
| features/site/help_center_screen.dart:16 | "Go to Device Setup > Select Controller > Wi-Fi Settings. You may need to connect to the controller's AP (Lumina-XXXX) first." | wrong | No such path exists. The controller's setup network is WLED's own; "Lumina-XXXX" is the bridge's. Correct answer: "Changing your home Wi-Fi? Ask your installer; the controller must be joined to the new network at the house." [T-A1, T-A4] | P2 |
| features/site/help_center_screen.dart:24 | "Check 'Time & Macro' settings in Hardware Config to ensure your time zone is correct." | wrong | Hardware Config has no time section. The app sets the controller's clock and time zone itself when it connects at home; the right answer is "Open the app at home on your Wi-Fi; if a schedule still misses, contact support." [MEM controller_defaults_healer; T-P2] | P2 |
| features/site/help_center_screen.dart:12 | "Lights are not responding." → "Ensure controller is powered (green LED). Try unplugging for 10 seconds to reboot." | misleading | A power cycle collapses the controller to one segment and boots it lit; the answer must add "then open the app at home so it can restore your channels." The "green LED" claim is unverifiable for Skikbily units. [T-P1, T-P2] | P2 |
| features/site/settings_page.dart:631 | Version tile reads "Version 1.6.0 / Build 2026.01" (hard-coded) | wrong | Must read `kAppVersion` (2.5.10+116). Support triage and the capture brief both tell people to read the version here. [T-B1; lib/app_version.dart] | P2 |
| features/game_day/game_day_server_status.dart:252 | "Your everyday lighting settings need repairing. Opening the app at home repairs them." | misleading | The on-connect repair is a dry run while the server config is absent (it is absent), so opening the app repairs nothing. Until the Repair card ships: "Your everyday lighting settings need repairing. Contact support." After it ships: "…Tap Repair base lighting on the Game Day screen." [T-GD6, T-GD7] | P2 |
| features/site/bridge_setup_screen.dart:529 | "…the previous owner must release it first (Settings → Remote Access → Unpair Bridge)" | wrong | No Unpair button exists. A bridge is released by its owner's installer (POST /api/reset at the house) or by Nex-Gen support. [T-R4; agent S4.3] | P2 |
| features/site/bridge_setup_screen.dart:266 | "Choose a controller in Site Setup before pairing a bridge." | wrong | No "Site Setup" screen. Path is Settings → System & Device Management → Controllers → Set as Active. [T-S2] | P2 |
| features/site/settings_page.dart:294 | "Add devices in Settings > Controllers & Devices." | wrong | No such label. Settings → System & Device Management → Controllers → Add Controller. [agent F; T-S2] | P2 |
| features/permissions/welcome_wizard.dart:192 | "To map your home for effects, we use the camera in AR." | wrong | There is no AR. The camera takes a house photo for the roofline preview. (Store-review exposure: a permission rationale that names a feature that does not exist.) [docs/guides-2026-09/README.md "AR never used"] | P2 |
| features/site/edit_profile_screen.dart:1154 | "Matches Found: We have 12 saved lighting designs for the '$builder - $plan' model. Lumina can auto-configure your zones." | wrong (hard-coded) | The count is a literal; no builder-match feature is verified. Remove or wire to data. [agent S4.10] | P2 |
| features/site/edit_profile_screen.dart:1070 | "Nex-Gen respects your privacy. Your data is stored locally and securely." | wrong | Profile data is stored in the cloud account (Firestore). Privacy wording must match the policy. [agent S4.10; CLAUDE.md Firestore collections] | P2 |
| features/wled/clock_health.dart:407–418 | Remediation sends the customer into the controller's web UI: "Open the controller in a browser (type its IP address), then Config → WiFi Setup … Config → Time & Macros" | misleading / risky | The app heals NTP host, time zone and location itself on the home Wi-Fi; customers should not edit the controller's own pages. Replace with "Open the app at home; it will fix the controller's clock. If this message stays, contact support." [MEM controller_defaults_healer; OWNER 10-08 "what NOT to touch"] | P2 |
| features/installer/screens/hardware_config_step.dart:120 | "You can configure this later from System → Hardware." | wrong | No "Hardware" item under System. The path is System → System & Device Management → My Lights (hardware config). [agent M; MEM guide_docs_canonical_set ("System → Hardware" never existed)] | P2 |
| features/site/system_management_screen.dart:480 (uses wled_providers.dart:144) | Homes see "Connect to venue Wi-Fi to change hardware settings" | wrong wording | Commercial wording shown to homeowners. "Connect to your home Wi-Fi to change hardware settings." [agent S4.5] | P2 |
| features/game_day/game_day_run_mode.dart:118 | "Game Day runs from this phone — Your lights change for the game when the Lumina app is open at home." | misleading | The controller fires the game from its own timer once the app has been open at home within 48 h before kickoff; the app need not be open at kickoff. Score celebrations do need the app open. Say both. [T-GD3] | P2 |
| features/neighborhood/widgets/game_day_setup_screen.dart:186 | "Lights activate 30 min before game start, off 30 min after." | contradictory | Lead time is a setting, and the end is "The game decides" (calendar_entry_editor.dart:360). [agent G] | P2 |
| features/audio/audio_mode_page.dart:213 | "The Nex-Gen NGL-CTRL-P1 comes with AudioReactive firmware and onboard mic pre-installed." | unverifiable (debug-only screen) | No product named NGL-CTRL-P1 is anchored anywhere; the fleet runs stock WLED with AudioReactive disabled by the SOP. Unreachable in release. [T-F1; dealer SOP §2.5] | P2 (latent) |

## P3

| Location | Claim | Verdict | Correct statement | Sev |
|---|---|---|---|---|
| features/site/remote_access_screen.dart, system_management_screen.dart:957–987 | "ESP32 Bridge" | naming drift | Every other surface says "Lumina Bridge". One name. [T-R2] | P3 |
| features/site/remote_access_screen.dart:810–1317 | Webhook (Dynamic DNS) mode with a four-step port-forwarding guide, shown to every customer | misleading audience | The DIY webhook path exists but is not the installed product; move behind an "Advanced" disclosure or installer lock. [CLAUDE.md Remote Access; T-R9] | P3 |
| features/site/remote_access_screen.dart:1094–1114 | "Your User ID" card with copy button | stale purpose | The id was for manual bridge pairing in early firmware; pairing is in-app now. Remove or label "for support". [T-R4] | P3 |
| features/properties/my_properties_screen.dart:793–825 | "Discover a WLED controller first from the System tab." | wording | Customers never see the word WLED elsewhere. "Add your controller from the System tab." | P3 |
| features/site/settings_page.dart:1339 | Simple Mode dialog lists tabs "(Home, Schedule, Lumina, Explore, Settings)" | wrong label | The fifth tab is labelled System. [CLAUDE.md Bottom Navigation; agent S4.8] | P3 |
| features/site/security_settings_screen.dart:54 vs features/auth/forced_password_reset_screen.dart:57 | "at least 6 characters" vs "At least 8 characters." | contradictory | One minimum. | P3 |
| features/game_day/game_day_screen.dart:2118 vs features/site/edit_profile_screen.dart:1424 | Two different Team Priority explanations | duplicate | One sentence, used in both places. | P3 |
| features/schedule/my_schedule_page.dart:5045; eviction_picker_dialog.dart:188; schedule_sync.dart:1765 | "up to 20 schedules" / "All 8 schedule slots" / "timer slots are full (8/8)" | confusing | Both limits are real: 20 saved schedules in the account, 8 timer slots on the controller. Copy should name which one each time. [T-L4] | P3 |
| features/schedule/my_schedule_page.dart:4851 | Schedule action "React to Music — Use a random audio-reactive effect" | accurate but conditional | Shown only when the controller reports AudioReactive support (`audioCapabilityProvider`); the dealer SOP disables AudioReactive, so customers should never see it. Leave; do not document. [my_schedule_page.dart:4858–4867; dealer SOP §2.5] | P3 |
| features/game_day/game_day_screen.dart:1105 | "Autopilot generates 6 team-themed designs" | wrong count (minor) | The team design catalog holds 7 entries. [lib/features/autopilot/team_design_catalog.dart] | P3 |
| services/notifications_service.dart:196 | Push "Your top $count patterns have been added to favorites." | dead copy | Nothing adds favorites automatically since build 115. Remove the string with its (dead) sender. [T-V1] | P3 |
| features/demo/demo_completion_screen.dart:145 | "A Nex-Gen lighting specialist will contact you within 24 hours." | unverifiable | Business promise; owner to confirm. | P3 |
| features/site/edit_profile_screen.dart:1447 | "Receive a notification every Sunday evening with your upcoming schedule…" | unverifiable | Not checked against the scheduler. | P3 |
| widgets/commercial/commercial_pro_banner.dart:91–102; screens/commercial/onboarding/… | "A Lumina Commercial subscription is coming — set up now to be grandfathered." | unreachable | The commercial shell and onboarding are unreachable. No change needed until it ships; do not document. [T-O2] | P3 |
| features/site/settings_page.dart:481 | "Video Tutorials" → external YouTube link | unverifiable | Whether the channel holds current tutorials is external. Owner to confirm or remove. | P3 |
| features/site/edit_profile_screen.dart:1057 | "Allow Nex-Gen to recommend your custom designs to other users with the same Builder/Floor Plan." | unverifiable | No such sharing pipeline verified. | P3 |
| features/auth/link_account_screen.dart:118; features/auth/join_with_code_screen.dart | Invitation-code entry advertised while Manage Family Members is compile-time off | contradictory | Either expose the invite screen or drop the code entry. [agent S4.12] | P3 |

## Gaps (no in-app copy exists)

- Power outage: no string anywhere mentions lost power, a reboot, or "open the app at home to restore your channels". [agent D note]
- Account switching: no customer-facing sentence explains what happens when a second account signs in on the same phone (116 behaviour) or what Set as Active is for. [T-S1, T-S2]
- The ten-minute bridge gap: the only hint is the relay-stale sentence ("Your Lumina Bridge hasn't checked in for N minutes"); nothing says "this clears on its own in about ten minutes". [T-R7]
- Lumina AI: no hint anywhere tells the customer which phrases save a schedule versus just show a look; the placeholders are all "show" phrases. [T-L2]
- Favorites cap: the cap is explained only at the moment it is hit; the Home empty tile does not say "up to 2". [T-V1]
- Game Day: nothing tells the customer what the lights return to after the game or what the base look is called; the repair banner names "Lumina Blue" only after a repair. [T-GD4, T-GD5]
- Celebration length: the helper explains seconds, not that the server ignores the setting when a game is server-run. [T-C2] (Only the bench is server-run today, so no customer sees the difference yet.)
- Help Center: four FAQs total, two wrong, one dangerous; no entry for "away from home", "Set as Active", "Game Day didn't switch back", "voice", or "support hours".
- "contact support" appears in 13 strings with no link; the only contact UI is Settings → Support & Resources and the Link Account card. [agent A aggregate]

## Security items in lib/ (kind only)

| Location | Kind | Note |
|---|---|---|
| services/reviewer_seed_service.dart:18 | internal account email | The App Store reviewer account identity, in a public repo. |
| features/installer/screens/customer_info_screen.dart:423 | 4-digit gate-code literal in a hint | If this is a real customer's gate code it is PII; replace with "0000"-style placeholder. |
| features/installer/media_access_code_screen.dart:229 | business email | Fine if it is a shared mailbox; confirm. |
| firebase_options.dart:50, 59, 67 | Firebase client API keys | Expected in a Flutter client, but the Play audit notes the Places key is billable and no App Check exists. |
| features/voice/alexa_service.dart:25 | Alexa skill id | Identifier only. |
| features/installer/installer_setup_wizard.dart:2068 | clipboard template interpolating a temporary password | Runtime value; design question (credentials on the clipboard). |
