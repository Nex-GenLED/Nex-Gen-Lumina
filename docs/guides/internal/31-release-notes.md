# Release notes and tester messages

*Describes build: 2.5.10+131 · Last verified: 2026-11-25 · Internal; the tester text is what testers receive.*

One entry per build that reached TestFlight, newest first. Each entry is copied from the build's row in `docs/BUILD_LEDGER.md` when the row lands. Build 113 was never built or shipped. Build 124 never shipped: its tag failed the automated test gate and produced no build, and build 125 carries the same changes. Builds 117 to 122 are not listed here yet; see `docs/BUILD_LEDGER.md`. Build 127 (TestFlight 362) was built but never distributed to testers; its changes are listed under build 128. Build 129 (TestFlight 364) was built and installed on the owner's phone for the bench but never distributed to testers; its changes are listed under build 130. Every tester message ends with the same line: "Send reports to general@nex-genled.com with the date and time."

## 2.5.10 build 131 — 2026-11-25

Tagged `build-131` = `3191e4b` on 2026-11-25; the tag matches Codemagic's `build-*` trigger for the iOS Release workflow; it is TestFlight 2.5.10 (368). No Android bundle is recorded for it. The wording below is taken from `docs/release/build_131_candidate.md`, section 2.

**What changed:** Glitter on a two-colour design sparkles bright white again, as it did before build 125. In Design Studio, lights you set dimmer or brighter on their own (Pixel brightness: Dim, Full or a Ramp) now light at that brightness when you tap Apply or Preview on lights, not only when the design runs on a schedule. Clean Up on an overloaded schedule now finishes even if you leave the screen while it runs, and when you ask Lumina to delete entries it still tells you what it removed if you close it straight after confirming.

**Tester text:** none written for this build; the withdrawal text below is the candidate notes' own.

**Withdrawal text (return to the previous build), if needed:** Build 131 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous build. Your schedules, teams, designs and favorites stay. Three things go back to how they were: Glitter sparkles in the design's second colour instead of white; Design Studio's per-light brightness reaches the lights only when the design runs on a schedule, not on Apply; and Clean Up can stop part-way if you leave the screen while it runs (open My Schedule and check what is left), and Lumina may not say what it deleted if you close it straight after confirming. Send reports to general@nex-genled.com with the date and time.

*If build 130 is never released to testers, "the previous build" for a tester is 128, and build 130's own withdrawal text applies as well.*

## 2.5.10 build 130 — 2026-11-17

Tagged `build-130` = `321dc7a` on 2026-11-17; the tag matches Codemagic's `build-*` trigger for the iOS Release workflow; it is TestFlight 2.5.10 (367), and 365 and 366 were failed Codemagic attempts of the same tag. Not released to testers yet. Android not built. Build 129 (TestFlight 364, tag `build-129` = `37cf275`) was built and installed on the owner's phone for the bench but never distributed to testers; this build carries its changes, so they are listed here too. The wording below is taken from `docs/release/build_130_candidate.md`, section 2.

**What changed:** Delete This Entry now works when an entry is opened from the week strip or month view.

**What changed (from build 129, carried in this build):** Brightness patterns now light up the way their cards show them. Each white under Explore › Architectural Downlighting has a Brightness Patterns folder with eight cards, led by two new waves (Wave · 6 lights and Wave · 18 lights). Every brightness card has an Adjust link: the brightest and dimmest level, how many lights one cycle spans, the shape (Wave, Ramp, Steps or Custom), the starting light, or tap single lights to set their own level. A brightness pattern can be saved to My Designs, and scheduling it follows the same rules as any painted design. In Design Studio, single lights can be made dimmer or brighter than their neighbours (Pixel brightness, with Dim, Full and a Ramp across a selection). Looks that use the Palette effect now spread their colours along the lights instead of showing one still colour, so saved looks that use Palette look different. When the controller's timer has no room left for a schedule, My Schedule now says so in its own words and changes nothing.

**New wording testers may see (from build 129, exact):** "Your controller's timer is full right now, so nothing was changed. Remove a schedule, or wait until tonight's calendar lighting ends, then tap Retry."

**Tester text:** none written for this build; the withdrawal text below is the candidate notes' own.

**Withdrawal text (return to 128), if needed:** Build 130 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous 2.5.10 build. Your schedules, teams, designs and favorites stay. Three things go back to how they were: Delete This Entry again does nothing when the entry is opened from the week strip or month view (ask Lumina instead, for example "remove Friday's entry"); the brightness patterns light as one dim run instead of the pattern on their card, and the Wave cards and the Adjust link are gone; and Design Studio no longer sets a brightness per light. Send reports to general@nex-genled.com with the date and time.

*Note: 129 was never on TestFlight for testers, so "the previous 2.5.10 build" for a tester on 130 is 128 (TestFlight 363).*

## 2.5.10 build 128 — 2026-11-16

Released to testers on 2026-11-16 as TestFlight 2.5.10 (363), from tag `build-128` = `9759da3`. Also on Google Play closed testing as versionCode 128 (2.5.10), uploaded 2026-11-16. Build 127 (TestFlight 362, tag `build-127` = `de4766b`) was built but never distributed; this build carries its changes, so they are listed here too. The wording below is taken from `docs/release/build_128_candidate.md` and `docs/release/build_127_candidate.md`, section 2 of each.

**What changed:** Tap a one-night entry on your Schedule and the sheet now opens above the bottom bar with Edit This Day and Delete This Entry always in reach, at any text size. And you can ask Lumina to delete one-night entries: "delete the entries you created for me", "remove Friday's entry", "cancel what you set up for Nov 20 to Nov 27". Lumina shows you exactly which entries it found — the count, the dates and the names — and nothing is removed until you tap Delete. Game Day entries and repeating schedules are not deleted this way; Lumina tells you where to manage those.

**What changed (from build 127, carried in this build):** Adding a one-night look or a Game Day, letting one expire, or switching "Turn lights off at sunrise daily" on or off no longer removes your other schedules from your controller: each of those now changes only its own entry on the controller and leaves everything else exactly as it was. A schedule the app could not re-save on one attempt keeps its place on the controller instead of being dropped, and if the app cannot be sure it would keep every schedule it says so and changes nothing (Retry). And each time you open the app at home it checks that every schedule is actually on your lights; if one is not, My Schedule and Home say "Your schedule isn't on your lights." and the app sends it again during the day, or you can tap Retry.

**New wording testers may see (from build 127, exact):** the sixth sync state on My Schedule and the Home chip reads "Your schedule isn't on your lights." with the second line "Something changed on your controller. It sends again when you open the app at home between 9 am and 3 pm, or tap Retry now." When the keep guard refuses a write, the sync result reads "Your controller still has a schedule the app couldn't rebuild this time, so nothing was changed. Tap Retry; if this keeps happening, contact support."

**Tester text:** none written for this build; the withdrawal texts below are the candidate notes' own.

**Withdrawal text (return to 127), if needed:** Build 128 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous 2.5.10 build. Your schedules, teams, designs and favorites stay. Two things go back to how they were: on some phones the entry sheet's Edit and Delete buttons sit behind the bottom bar at the default text size (lower the text size in Settings → Display to reach them), and Lumina no longer deletes entries for you (open Schedule, tap the entry, then Delete This Entry). Send reports to general@nex-genled.com with the date and time.

**Withdrawal text (return to 126), if needed:** Build 127 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous 2.5.10 build. Your schedules, teams, designs and favorites stay. Two things go back to how they were: adding or ending a one-night look or Game Day, or switching the sunrise-off setting, can again drop a schedule from your controller (open My Schedule and tap Retry afterwards to put it back), and the app no longer checks at launch whether your schedules are on your lights. If you see anything wrong after switching, tell us the date and time. Send reports to general@nex-genled.com with the date and time.

*Note: 127 was never on TestFlight, so "the previous 2.5.10 build" for a tester on 128 is 126 (TestFlight 361), and both withdrawal texts apply together.*

## 2.5.10 build 126 — 2026-11-13

Uploaded to TestFlight as 2.5.10 (361) from tag `build-126` = `bd29c38` and released to testers. Android: a bundle was built and never uploaded. The wording below is taken from `docs/release/build_126_candidate.md`, section 2.

**What changed:** My Schedule now tells you whether your schedule has reached your lights, and Home shows the same in one line. If it hasn't — you saved it away from home, or your controller didn't answer — the app says so, offers Retry, and tries again by itself the next time you open it at home, during the day. A change you make while the previous one is still being saved is no longer lost: it goes next, automatically. The schedule editor spells out what you set ("Lights on at 5:00 PM, off at 7:00 AM the next morning.") and re-opens on the saved time on phones set to a 24-hour clock. If one pattern could not be confirmed on your lights, the schedule stays set and the app says so instead of switching it off.

**Tester text:** none written for this build; the withdrawal text below is the candidate notes' own.

**Withdrawal text (return to 125), if needed:** Build 126 has been withdrawn. Open TestFlight → Nex-Gen Lumina → Previous Builds → install 2.5.10 (360). Your schedules, teams, designs and favorites stay. Three things go back to how they were: My Schedule and Home no longer say whether your schedule reached your lights, a change made while the previous one is still saving can be lost (save it again at home), and the editor no longer spells out the on and off times. If you see anything wrong after switching, tell us the date and time. Send reports to general@nex-genled.com with the date and time.

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

*Facts: T-B1, T-D6, T-D7, T-D8, T-D9, T-D10, T-D11, T-D12, T-D13, T-D14, T-D15, T-D16, T-L6, T-GD11, T-GD12, T-E5, T-E6, T-L5, T-D4, T-D5, T-G3, T-G4, T-E4, T-E3, T-S1, T-S2, T-L1, T-V1, T-E1, T-C1, T-C3, T-G1, T-GD1, T-GD4, T-E2, T-D1, T-L2, T-R8, T-R1, T-SU1, T-SU2.*
