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

The guide set is `docs/guides/`; the facts behind it are `docs/FACTS.md`; the claims rules are the [Claims policy](33-claims-policy.md). Superseded documents are in `docs/archive/` and are not maintained. Replacement text for Drive and the stores is prepared under `docs/drive-exports/`; uploading it is the owner's step.

*Facts: T-X9, T-X10, T-X8, T-B1, T-B2, T-B3, T-B4, T-X16, T-O4, T-O7, T-S1, T-S2, T-S3, T-S4, T-R1, T-R3, T-R7, T-P1, T-P2, T-GD1, T-GD2, T-GD6, T-GD7, T-GD8, T-VA1, T-F2, T-X21, T-D2, T-R5, T-O3, T-SU1, T-SU2.*
