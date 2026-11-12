# Release notes and tester messages

*Describes build: 2.5.10+125 · Last verified: 2026-11-11 · Internal; the tester text is what testers receive.*

One entry per build that reached TestFlight, newest first. Each entry is copied from the build's row in `docs/BUILD_LEDGER.md` when the row lands. Build 113 was never built or shipped. Build 124 never shipped: its tag failed the automated test gate and produced no build, and build 125 carries the same changes. Builds 117 to 122 are not listed here yet; see `docs/BUILD_LEDGER.md`. Every tester message ends with the same line: "Send reports to general@nex-genled.com with the date and time."

## 2.5.10 build 125 — 2026-11-11

Uploaded to TestFlight as 2.5.10 (360) on the night of 2026-11-11 (CST), from tag `build-125` = `b9a53da`. Whether Apple's beta review has cleared it for external testers is not verified. Android was not built.

**What changed:** Team colours on the lights are tuned for LEDs. The app still shows each team's own colours, but the lights get the colour that looks right when lit: Chiefs red is deeper and no longer pinkish, and Chiefs gold, like the other golds, no longer looks whitish. Game Day's default look for a team without a saved design is stripes of the team's two colours marching along the lights; the static style shows the same stripes standing still, and the Stripe design now shows stripes. Teams already set up keep the effect they had. Lumina's replies about a team start with the same moving stripes. Twinkle on a warm white design has a darker background, so the twinkles stand out, and Glitter sparkles in the design's own colour instead of flashing white.

**Tester text:** written with the build's ledger row, after the tag.

## 2.5.10 build 123 — 2026-11-08

**What changed:** A custom roofline design can be put on the weekly schedule when your controller's layout matches the layout the design was saved for, on controllers the app supports for this; when it does not match, the app says so and does not schedule it. Design Studio can make colour variations of a saved design, and a variation keeps the saved design's layout. Design Studio understands direction words such as "left to right" and "moving right" as the direction of motion, not as a place on the house. Dancing Shadows starts slower. Animated designs can't be scheduled yet.

**Tester text:** written with the build's ledger row, after the tag.

## 2.5.10 build 116 — 2026-10-07

**What changed:** The Recent Patterns cards on Explore are smaller, grow with Larger Text, and name the effect a tap plays. The selected controller now belongs to the account that chose it: signing out, signing into another account, or an installer entering or leaving a customer drops the previous selection, so the new account's own controller is selected. Deleting the active controller releases its address.

**Tester text (if build 116 is withdrawn):** Build 116 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install 2.5.10 (115). Your schedules, teams, designs and favorites stay. Two things go back to how they were: the Recent Patterns cards on Explore are taller again and don't name their effect, and if you sign out and into a different account on the same phone you may need Settings → System & Device Management → Controllers → Set as Active before the lights respond. If you see anything wrong after switching, tell us the date and time. Send reports to general@nex-genled.com with the date and time.

## 2.5.10 build 115 — 2026-10-04

**What changed:** A Lumina look reaches every channel of the house and the card says how many. Favorites are yours alone: nothing is added automatically, you can keep two, and the app offers a replace when you add a third. Every effect name you read is the controller's own. Each Game Day team has a celebration Length (Short, Medium, Long); an NFL extra point no longer celebrates; every celebration ends on its own even if the app is interrupted.

**Tester text (return to 114):** Build 115 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install 2.5.10 (114). Your schedules, teams, designs and roofline stay. A few things go back to how they were: Lumina may change only one of your channels for a team look, My Favorites can fill with patterns you use often again, and celebrations play their standard length. If you see anything wrong after switching, tell us the date and time. Send reports to general@nex-genled.com with the date and time.

## 2.5.10 build 114 — 2026-10-02

**What changed:** Roofline marking: sections can be merged and deleted, with Undo and Start over; Segment Setup is installer-only. Game Day shows whether it runs from our servers or from this phone. The everyday ON look is Lumina Blue on new systems. The design card's Blocks / Alternating chips and LEDs-per-color row follow the card's own state.

**Tester text (return to 112):** Build 114 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install 2.5.10 (112). Your schedules, teams, designs and roofline stay. A few things go back to how they were: Segment Setup opens for everyone again, the Blocks / Alternating choice on a design card disappears again while you preview another effect, Game Day no longer says whether it runs from our servers or this phone, and score celebrations go back to celebrating every score. If you see anything wrong after switching, tell us the date and time. Send reports to general@nex-genled.com with the date and time.

## 2.5.10 build 112 — 2026-10-01

**What changed:** Scheduling for one day: the "+" editor has Just this day, and every day sheet has an add action. Lumina saves "tonight" and "this weekend" as those nights only and says so. Schedule edits made away from home are saved and applied the next time the phone is on the home Wi-Fi.

**Tester text (return to 111):** Open TestFlight → Nex-Gen Lumina → Previous Builds → install 2.5.10 (111). Your schedules and nights stay; a one-night look saved on 112 shows as a solid colour on 111 until you move back to 112. Send reports to general@nex-genled.com with the date and time.

## 2.5.10 build 111 — 2026-09-30

**What changed:** The same app as build 110, re-tagged so the CI gate passes in UTC; Larger Text fixes in the roofline walkthrough.

## 2.5.10 build 110 — 2026-09-30

**What changed:** Away from home without a bridge, the app now says so at once ("Control from anywhere requires a Lumina Bridge") instead of waiting 45 seconds. Design Studio and Lumina follow-ups. The support card shows your installer's phone and email.

## Before build 110

See the rows in `docs/BUILD_LEDGER.md`.

*Facts: T-B1, T-GD11, T-GD12, T-E5, T-E6, T-L5, T-D4, T-D5, T-G3, T-G4, T-E4, T-E3, T-S1, T-S2, T-L1, T-V1, T-E1, T-C1, T-C3, T-G1, T-GD1, T-GD4, T-E2, T-D1, T-L2, T-R8, T-R1, T-SU1, T-SU2.*
