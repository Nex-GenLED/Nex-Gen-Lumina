# In-app string changes — proposal (no code changed on this branch)

For a separate branch after the bus-repair branch (`fix/ladder-repair-bus-change`) lands, with the accessibility harness at 1.0, 1.75 and 2.0 text scale with Bold Text, and the full gates. Ranked by severity; the bridge "reflash" message and the voice advertising come first. Strings are exact and final; screens and lines are at `c283d62`. Every row cites `docs/FACTS.md`.

## P1 — ship first

| # | Screen · file:line | Today | Proposed | Why |
|---|---|---|---|---|
| 1 | Bridge Setup, pair error · `lib/features/site/bridge_setup_screen.dart:367` | "This bridge firmware is outdated. Please reflash the bridge with the latest firmware and try again." | "This bridge needs servicing. Contact your installer." | Customers never reflash; bridges have no OTA; a reflash wipes pairing. T-R5. |
| 2 | Settings card · `lib/features/site/settings_page.dart:857–871` | "Voice Assistants" / "Set up Siri, Google, or Alexa control" + permanent "New" badge | "Voice Assistants" / "Siri Shortcuts on iPhone. App shortcuts on Android." No badge. | Alexa and Google linking has never worked and is not advertised. T-VA1, T-VA2. |
| 3 | Voice guide screen · `lib/features/voice/voice_assistant_guide_screen.dart` hero :87–93; Google card :299–570; Alexa card :612–835 | Google Home and Alexa cards with Link buttons, "Alexa is connected!", example phrase "Alexa, turn on the house lights" | Remove both cards. Hero: "Say \"Hey Siri, [your phrase]\" to put a saved look on your lights. On Android, long-press the Lumina icon for shortcuts." Keep the Siri section and the Android App Shortcuts box. | T-VA1. (Restore the cards only when linking is deployed and proven.) |
| 4 | Simple Mode dialog · `settings_page.dart:1306`; installer hand-off · `lib/features/installer/handoff_screen.dart:544` | "Voice assistant setup" / "Voice assistant setup guides" | "Siri Shortcuts (iPhone)" | T-VA1. |
| 5 | Google service · `lib/features/voice/google_home_service.dart:32` | setup URL with a placeholder project id | Remove the constant and its button. | No action exists. T-VA1. |
| 6 | Help Center FAQ · `lib/features/site/help_center_screen.dart:20` | "Can I cut the strips?" → "Yes, at the copper pads…" | Remove. | Permanent professional install; dangerous advice. T-R9. |
| 7 | Lumina AI reply · `lib/features/ai/lumina_brain.dart:447` | "…Try updating your firmware." | "…Audio Mode isn't available on this controller." | Customers never update firmware (debug-only path, fix before Audio Mode ever ships). T-F2. |

## P2

| # | Screen · file:line | Today | Proposed | Why |
|---|---|---|---|---|
| 8 | Help Center FAQs · `help_center_screen.dart:12–27` | Four FAQs; two name paths that do not exist ("Device Setup > Select Controller > Wi-Fi Settings", "Time & Macro in Hardware Config"); one tells people to unplug the controller with no reconnect step | Replace with seven: **My lights are dark.** "Check that the controller is plugged in and its outlet is on. Then open Lumina at home: the Home screen should say Direct. If it says Can't reach your lights, tap Reconnect. Still dark? Contact your installer from Support & Resources." · **My lights look wrong after a power outage.** "After a power cut the controller shows one plain look across the whole roofline until the app reconnects. Open Lumina on your home Wi-Fi and wait a minute. Your channels and your next schedule come back on their own. Nothing is lost." · **The app says I'm away from home.** "On your home Wi-Fi, Lumina talks to your lights directly. Away from home it needs a Lumina Bridge, which your installer sets up. If you have a bridge and see this at home, open System & Device Management → Remote Access and tap Detect Home Network." · **Game Day didn't switch back.** "Your lights return to your everyday look when the game ends. If they are still in team colours an hour after the final, open the app at home and tap your everyday schedule, or turn the lights off and on from Home. Then tell your installer which game it was." · **Nothing responds on a new phone.** "Open System & Device Management → Controllers and tap Set as Active on your controller." · **Which voice assistants work?** "Siri Shortcuts on iPhone. On Android, long-press the Lumina icon for shortcuts. Others aren't available." · **Who do I contact?** "Tap Contact Nex-Gen Support above. It shows your installer's phone and email, or Nex-Gen LED's if your installer hasn't been added." | T-X20, T-P1, T-P2, T-R1, T-R10, T-GD5, T-S2, T-VA2, T-SU1. |
| 9 | Game Day pre-flight reason · `lib/features/game_day/game_day_server_status.dart:252` | "Your everyday lighting settings need repairing. Opening the app at home repairs them." | "Your everyday lighting settings need repairing. Contact your installer or Nex-Gen support." (When the repair card ships: "…Tap Repair base lighting below.") | The on-connect repair is a dry run. T-GD6, T-GD7. |
| 10 | Bridge Setup, paired elsewhere · `bridge_setup_screen.dart:529` | "…(Settings → Remote Access → Unpair Bridge)" | "This bridge is paired to a different account. Its owner's installer must release it first." | No such button. T-R4. |
| 11 | Bridge Setup, no controller · `bridge_setup_screen.dart:266` | "Choose a controller in Site Setup before pairing a bridge." | "Choose your controller first: System & Device Management → Controllers → Set as Active." | No "Site Setup" screen. T-S2. |
| 12 | Link Controllers sheet · `settings_page.dart:294` | "Add devices in Settings > Controllers & Devices." | "Add controllers in System & Device Management → Controllers." | T-X19. |
| 13 | Version tile · `settings_page.dart:631` | "Version 1.6.0" / "Build 2026.01" (hard-coded) | Read `kAppVersion` and show "Version 2.5.10 (116)". | T-B1. |
| 14 | Welcome wizard camera step · `lib/features/permissions/welcome_wizard.dart:192` | "To map your home for effects, we use the camera in AR." | "To preview designs on a photo of your house, we use the camera." | No AR. |
| 15 | Clock-health remediation · `lib/features/wled/clock_health.dart:407–418` | "Open the controller in a browser … Config → Time & Macros …" | "Open Lumina on your home Wi-Fi and it will set the controller's clock. If this message is still here tomorrow, contact your installer." | The app heals the clock; customers do not edit the controller's pages. |
| 16 | Hardware step skip note · `lib/features/installer/screens/hardware_config_step.dart:120` | "…from System → Hardware." | "…from System & Device Management → My Lights." | T-X19. |
| 17 | LAN-only message · `lib/features/wled/wled_providers.dart:144` (shown to homes at `system_management_screen.dart:480`) | "Connect to venue Wi-Fi to change hardware settings" | "Connect to your home Wi-Fi to change hardware settings" (keep the venue wording in commercial mode only). | Wording. |
| 18 | Game Day run-mode banner · `lib/features/game_day/game_day_run_mode.dart:118` | "Your lights change for the game when the Lumina app is open at home." | "Open Lumina at home in the two days before a game so your lights are set to change at kickoff. Keep the app open during the game for score celebrations." | T-GD3, T-C2. |
| 19 | Manual setup, step 1 · `lib/features/ble/wled_manual_setup.dart:305` | "…connect to the \"Lumina-XXXX\" WiFi network…" | "…join your controller's setup Wi-Fi network (the name is on the controller's label)…" | The named network is the bridge's. T-A1, T-A4. |
| 20 | Relay stale message · `lib/services/bridge_pairing.dart:227` | "Your Lumina Bridge hasn't checked in for N. Check that it's powered on and online at home." | "Your Lumina Bridge hasn't checked in for N. This usually clears on its own within ten minutes. Try again then, or check that it's plugged in at home." | T-R7. |
| 21 | Profile privacy line and builder match · `lib/features/site/edit_profile_screen.dart:1070, 1154` | "Your data is stored locally and securely." / "We have 12 saved lighting designs for the '…' model." | Remove both sentences (or wire the count to data). | False claims. T-X15. |

## P3 — small polish, same branch

| # | Screen · file:line | Today | Proposed |
|---|---|---|---|
| 22 | Blocked-apply snackbars (every `ApplyBlockedReason` surface) | message only | Add a **Help** action that opens `/settings/help`. |
| 23 | Favorites add tile · `lib/widgets/favorites_grid.dart:346` | "Add a favorite" | "Add a favorite (you can keep 2)" |
| 24 | Properties hint · `lib/features/properties/my_properties_screen.dart:793` | "Discover a WLED controller first from the System tab." | "Add your controller from the System tab first." |
| 25 | Simple Mode disable dialog · `settings_page.dart:1339` | tab list ends "…Settings)" | "…System)" |
| 26 | Dead push string · `lib/services/notifications_service.dart:196` | "Your top N patterns have been added to favorites." | Delete with its (dead) sender. |
| 27 | Remote Access / System Management · `remote_access_screen.dart`, `system_management_screen.dart:957–987` | "ESP32 Bridge" | "Lumina Bridge" everywhere. |

Reference: `docs/overhaul-2026-10/07_findings_inapp.md` for the full in-app findings and `docs/FACTS.md` for every fact cited.
