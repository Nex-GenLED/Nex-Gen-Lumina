# Claims policy — what may be said about Lumina

*For Nex-Gen staff, dealers and anyone writing for the website, a store listing or a customer. Describes build: 2.5.10+116 · Last verified: 2026-10-09.*

This page lists the claims that must not be made, the reason, and what to say instead. The guard (`node scripts/docs_guard.mjs`) refuses guide text that uses the banned phrases below; this page is exempt because it quotes them.

## Never say

| Banned | Why | Say instead |
|---|---|---|
| "Works with Alexa", "Works with Google Home", "Google Assistant", "voice activated" (meaning those) | Account linking has never worked for anyone. The fix is built, not deployed. Facts T-VA1. | "Siri Shortcuts on iPhone; app shortcuts on Android." |
| "Flash the controller", "update the firmware", "pin to version…", any web-flasher name | Controllers are never flashed, updated or downgraded by anyone. Facts T-F2, T-F3. | "Your controller's firmware is installed at the factory and recorded at install. Nobody updates it." |
| "Download Lumina from the App Store / Google Play" | The app is not publicly listed; customers arrive by installer invitation. Facts T-O8. | "Your installer sends you an invitation to install the app." |
| "Lifetime warranty" | The warranty is 5 years on the product and a 1-year minimum on labor, with a 50,000-hour rated life. Facts T-O6. | "5-year product warranty, 1-year labor minimum, 50,000-hour rated life." |
| "AR", "augmented reality" | There is no AR. The camera takes a photo of the house for the preview. | "Live preview on a photo of your house." |
| "Control your lights from anywhere" without the bridge | Away-from-home control needs a dealer-installed Lumina Bridge. Facts T-R1, T-R9. | "Control from anywhere with the Lumina Bridge your installer sets up." |
| "Set it and forget it", "zero maintenance" | Bridges and controllers do need attention (power cuts, the bridge's quiet window). | "Runs on its own night after night; your installer stays in the loop." |
| "Game Day runs by itself from our servers" (to a customer) | Server-run Game Day is proven on the bench only; customers run it from the phone. Facts T-GD1, T-GD2. | "Game Day runs from your phone: open the app at home in the two days before kickoff." |
| "Military-grade", "bank-level", "encrypts everything" | Three fields are encrypted; the rest is stored normally. Facts T-X15. | "Your address and Wi-Fi name are stored encrypted." |
| "GDPR / CCPA compliant", "SOC 2", "audited", "we delete everything after 90 days", "export your data", "opt out of analytics" | None is anchored in the product; AI usage records are never purged; there is no export or opt-out. Facts T-X16, T-O4. | Say only what the privacy policy, once corrected, says. |
| "OpenAI" (as the AI vendor) | Lumina AI runs on Anthropic through our proxy. Facts T-X14. | "Lumina AI runs on Anthropic's models through our own service." |
| "10 requests per hour" | The limit is 50 an hour. Facts T-X14. | "Lumina AI has a fair-use limit of 50 requests an hour." |
| A bridge "dashboard", "web page", "Factory Reset button", any `http://<bridge-ip>/` address | The bridge serves no web page. Facts T-R4. | "Your installer tests and resets the bridge from the app." |
| "Repair base lighting" card, "Use this controller", server celebrations | Built, not shipped. Facts T-GD7, T-S3, T-C2. | "Coming." or nothing. |
| "Opening the app repairs your everyday lighting" | The repair is a dry run today. Facts T-GD6. | "Contact your installer." |
| Any phone number, password, PIN, address, device id, customer name, or any email address other than the support mailbox, in a document | The repository is public. | "Email general@nex-genled.com" (lowercase; the only address a document carries). |

## Always say

- Firmware: "Your controller's firmware is recorded at install. Nobody updates it." (T-F2)
- Away from home: "Needs the Lumina Bridge your installer set up. Remote commands take a few seconds. About every seven hours the bridge is quiet for ten minutes; try again then." (T-R1, T-R6, T-R7)
- Game Day: "Runs from your phone. Open the app at home in the two days before a game. Score celebrations play while the app is open. After the game the lights go back to your everyday look." (T-GD3, T-C2, T-GD5)
- Voice: "Siri Shortcuts on iPhone. Android app shortcuts." (T-VA2)
- Schedules: "Up to 20 saved schedules; the controller holds 8 timed changes at once. Edits made away from home apply when you are home." (T-L4, T-R8)
- Favorites: "Keep up to 2." (T-V1)
- Support: "Email general@nex-genled.com, or in the app open Settings → Support & Resources → Contact Nex-Gen Support." Always lowercase; no other support address. (T-SU1, T-SU2)

## Store listings and the website

Until the listings and the site are rewritten from this page and FACTS, treat them as unverified. The archived website prompts in `docs/archive/root-drafts/LANDINGSITE_AI_PROMPTS.md` are marked DO NOT USE for the reasons above. Replacement text for Drive and the stores is prepared under `docs/drive-exports/`; nothing there is published until the owner uploads it.

*Facts: T-VA1, T-VA2, T-F2, T-F3, T-O8, T-O6, T-R1, T-R4, T-R6, T-R7, T-R9, T-GD1, T-GD2, T-GD3, T-GD5, T-GD6, T-GD7, T-S3, T-C2, T-X14, T-X15, T-X16, T-O4, T-L4, T-R8, T-V1, T-SU1, T-SU2.*
