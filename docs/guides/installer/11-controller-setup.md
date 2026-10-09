# Controller setup: outputs, channels and the roofline

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For installers*

## Outputs are channels

Each physical output on the controller drives one run of lights. The app calls each output a channel. Channels come from the controller's hardware, not from how the roofline is drawn: when the app connects at home it reads the outputs and splits the controller's lighting to match them.

**Read the output numbers from the controller's own labels.** The app's hardware editor proposes output numbers from a fixed list when you add a row; installed units do not always use those numbers. After you save, confirm each row drives the right run with **Test Lights** or by walking the lit pixel. If a row lights the wrong run, change its output number to the one printed on the controller. This mismatch is logged as a likely app defect; until it is fixed, the label on the controller wins.

## Hardware configuration (Installer Mode → the hardware step, or System & Device Management → My Lights)

For each output:

1. Enter the number of lights on that run ("Count the bulbs on this strand").
2. Keep the Nex-Gen standard LED settings. The standard is an RGBW strip with colour order RGB. Do not set GRB.
3. Save. The controller restarts.

The app also keeps the controller's clock, time zone and location correct on every connection at home, using the customer's address from their profile. You do not set those on the controller.

## Roofline marking

Design Studio needs to know where the corners, peaks and runs are. Two tools do this:

- **Mark Your Roofline** (from Design Studio → **Roofline setup**, also the wizard's map step). One light is lit on the house; move it along the run and tap what it is sitting on: a corner, a peak, or the start of a new run. You can merge or delete sections, **Undo**, or **Start over** on a channel. Customers can use this one.
- **Roofline Segments** (installer-only, behind the installer lock) for detailed edits and clean-up of duplicate sections.

Get the light counts right first: the count drives the map and everything downstream.

## Adding or changing an output after install

Do it in the app, never on the controller's own web page.

1. In the customer's account (Installer Mode → **Existing Customer**), open System & Device Management → My Lights and add the row with the output number printed on the controller and its light count. Save.
2. Open the app on the home Wi-Fi and wait a minute, so the channels are re-read.
3. Re-check the roofline map and any schedule that targets specific channels.
4. Tell Nex-Gen support that an output was added. Game Day checks that the everyday lighting presets describe every output; after a change they may not, and until that is corrected Game Day stays blocked for the house. An in-app repair is coming; today support corrects it.

A change made on the controller's own page bypasses all of this and can leave Game Day blocked and the house stuck in team colours after a game.

## Time, location and the microphone setting

- The customer's address in their profile is what sunrise and sunset use. Confirm it is right.
- The controller's audio-reactive add-on must be off; the app turns it off on connection if it finds it on.

## Firmware

Record the version. Never flash, update or downgrade. See the [install checklist](10-install-checklist.md).

*Facts: T-G1, T-G2, T-X4, T-X5, T-X25, T-GD8, T-GD7, T-D2, T-F2.*
