<!-- docs_guard: allow-banned -->
# Admin Operations Guide (internal)

*Replacement text for the Drive file `Admin_Operations_Guide.pdf`. Generated 2026-10-09 from docs/guides/; not published until the owner uploads it. Describes build: 2.5.10+116.*


---

# Admin operations

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · Internal, Nex-Gen staff only. This page contains no PIN values; every master PIN is held offline.*

## Staff access

One PIN pad (**Staff Access**, reached by five taps on the sign-in logo or **Nex-Gen Professional Access → Installer**) resolves four tiers in order: Owner, Admin, Installer, Sales. The PIN is checked by the server; no PIN value exists in the app. Five wrong attempts lock the pad for 30 seconds. Sessions last 30 minutes (corporate 60) with a five-minute warning. An admin or owner PIN opens the Corporate Dashboard; there is no separate admin dashboard.

PINs are rotated in-app: Corporate Dashboard → **Admin** → System PINs → change the slot. The app verifies the current PIN and stores a hash. Never write a PIN value in a document, a ticket or a chat.

## The Corporate Dashboard

| Tab | What is there |
|---|---|
| **Network** | One card per dealer with this month, active, month-to-date and last-job pills. Health: active when the last job is within 14 days, quiet within 30, otherwise stalled. Tapping a dealer opens that dealer's own dashboard in Admin view. |
| **Pipeline** | Every job across dealers, with status chips. |
| **Warehouse** | Nex-Gen stock: SKU table (on hand, reserved, available, reorder point), purchase orders, receiving. |
| **Orders** | Dealer orders awaiting review, with approve, reject, confirm-payment and mark-shipped actions. Dealers have no reachable ordering screen in the app today, so this queue fills only from other paths. |
| **Admin** | Dealer management (add, activate, deactivate; deactivation also deactivates the dealer's installers), pricing defaults, network announcements, dealer accounts (promote, revoke), the product catalog, the brand library (its admin actions do not work for any PIN session), and System PINs. |

Installers are managed from each dealer's dashboard: **Team → Manage team**.

Demo codes and demo leads are Firestore collections read in the console; there is no admin screen for them. Media Mode has no entry point in the shipped app.

## Testers and builds

- iOS: TestFlight only. Add testers in App Store Connect. The current build is 2.5.10 build 116; the build number testers see comes from the CI counter and is recorded in the ledger row when known.
- Android: Play closed testing. Production access needs 12 opted-in testers for 14 continuous days; the last recorded count was 4. A built bundle consumes its version code whether or not it is uploaded; bump before building. The +116 bundle is built and not uploaded.
- Every build gets a ledger row and a release-notes entry with the tester text and a rollback note. Run `node scripts/docs_guard.mjs` and re-stamp the facts the build touched before the bump (build convention 9).

## Customer account operations

- Self-serve deletion: **System → My Profile → Security & Password → Delete Account**. The controller keeps running its stored schedule; a live bridge stays claimed until an installer resets it; crew membership is not purged automatically.
- Analytics cannot be turned off in the app; they are declared required. The public privacy policy still says otherwise and needs the correction.
- Uncaught app errors are written to the account's crash record with the app version (since 115). The release stacks are not symbolicated.

## Support playbooks

| Report | What is true | What to do |
|---|---|---|
| Nothing responds after switching accounts on one phone | On 116 the previous selection is dropped automatically; on 115 and earlier the old controller stays selected. Other stale cases (address changed elsewhere, cold start with an old address) are still open on 116. | **System & Device Management → Controllers → Set as Active**. |
| "Requires a Lumina Bridge" away from home | No bridge is paired. | Sell and install one; installer pairs. |
| "Remote access isn't set up for this controller" with a bridge paired | A stale controller selection. The clearer message and a "choose your controller" prompt are built, not shipped. | Set as Active; if two controllers exist, pick the right one. |
| Remote commands fail for about ten minutes, or Game Day "served" flips off | Every fielded bridge goes quiet about every seven and a half hours for roughly ten minutes. Cause open; a server-side hold is built, not deployed. | Wait ten minutes. Do not reset or reflash the bridge. |
| Lights wrong after a power cut | Controller boots lit with one segment; the split is restored only when the app connects at home. | Open the app at home for a minute. |
| Game Day stuck in team colours | The end did not run. On the deployed server, a house gated for bad everyday presets (for example after an output was added on the controller's own page) also has its end blocked; the end guarantee is built and not deployed. | Restore the everyday look by hand (everyday schedule or a favorite). Correct the presets so they describe every output. |
| "Your everyday lighting settings need repairing" | The on-connect repair is a dry run while the server setting is absent; the banner's "opening the app repairs them" is wrong. A user-driven repair card is built, not shipped. | Correct the everyday presets by hand; tell the customer the in-app repair is coming. |
| "Can I use Alexa / Google?" | Linking has never worked for anyone; the fix is built, not deployed. | Say not available. Never advertise. |
| "Will you update the firmware?" | Never. Record the version only. | Say no. |
| Schedules did not fire | Common causes: edited away from home (applies when home), 8 timer slots full, no address for solar, controller clock unset (the app sets it at home). | Walk the Troubleshooting page with them. |

Server-run Game Day exists for the bench account only. Do not tell a customer their house is served, and do not promise a date.

## Feature flags

The deployed values of the server flags (solar scheduling, calendar leases, sync fanout scope, the Game Day planner allowlist) are read in the Firebase console, not from any document. Rules and functions are deployed per function from the matching checkout, never from an arbitrary branch and never with a forced rules deploy. The bridge rules were tightened on 2026-10-05 to firmware 1.2's exact behaviour; widen them before any 1.3 unit is flashed.

## Support mailbox

The support mailbox is general@nex-genled.com, lowercase, and it is the only address printed in any guide, export, checklist or tester message. The app's own corporate contact uses the same address. Mail delivery to it is UNVERIFIED until the owner sends a test.

## Documents

The guide set is `docs/guides/`; the facts behind it are `docs/FACTS.md`; the claims rules are the Claims policy. Superseded documents are in `docs/archive/` and are not maintained. Replacement text for Drive and the stores is prepared under `docs/drive-exports/`; uploading it is the owner's step.

*Facts: T-X9, T-X10, T-X8, T-B1, T-B2, T-B3, T-B4, T-X16, T-O4, T-O7, T-S1, T-S2, T-S3, T-S4, T-R1, T-R3, T-R7, T-P1, T-P2, T-GD1, T-GD2, T-GD6, T-GD7, T-GD8, T-VA1, T-F2, T-X21, T-D2, T-R5, T-O3, T-SU1, T-SU2.*

---

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
