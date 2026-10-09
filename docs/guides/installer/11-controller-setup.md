# Controller setup: outputs, channels and the roofline

*Describes build: 2.5.10+116 · Last verified: 2026-10-09 · For installers*

## Outputs are channels

Each physical output on the controller drives one run of lights. The app calls each output a channel. Channels come from the controller's hardware, not from how the roofline is drawn: when the app connects at home it reads the outputs and splits the controller's lighting to match them.

**The four canonical outputs (decided by the owner, 2026-10-09):** output 1 = GPIO 2, output 2 = GPIO 14, output 3 = GPIO 16, output 4 = GPIO 18. Every run maps to one of those four positions. Never use more than four; how many outputs a Skikbily unit has beyond these is UNVERIFIED.

**The app disagrees today (app bug #187).** The hardware editor proposes GPIO numbers for new rows from a fixed list (0, 1, 2, 3, 4, 5, 12, 13), so a fourth port it adds gets GPIO 3, which matches no output, and the editor cannot change the number. The app does keep the numbers it reads from a controller that is already configured. So: configure the four outputs with their GPIO numbers on the controller's own LED settings page at the bench (SOP 1.3), let the app read them, and never add a port in the app's editor. After saving, confirm each row drives the right run with **Test Lights** or by walking the lit pixel.

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

1. Set the new output on the controller's own LED settings page with its canonical GPIO number (2, 14, 16 or 18) and its light count; do not add it in the app's editor (bug #187 would give it the wrong number). Then, in the customer's account (Installer Mode → **Existing Customer**), open System & Device Management → My Lights and confirm the app shows the new row with the right number.
2. Open the app on the home Wi-Fi and wait a minute, so the channels are re-read.
3. Re-check the roofline map and any schedule that targets specific channels.
4. Email general@nex-genled.com that an output was added. Game Day checks that the everyday lighting presets describe every output; after a change they may not, and until that is corrected Game Day stays blocked for the house. An in-app repair is coming; today support corrects it.

A change made on the controller's own page bypasses all of this and can leave Game Day blocked and the house stuck in team colours after a game.

## Time, location and the microphone setting

- The customer's address in their profile is what sunrise and sunset use. Confirm it is right.
- The controller's audio-reactive add-on must be off; the app turns it off on connection if it finds it on.

## Firmware

Record the version. Never flash, update or downgrade. See the [install checklist](10-install-checklist.md).

*Facts: T-G1, T-G2, T-X4, T-X5, T-X25, T-GD8, T-GD7, T-D2, T-F2, T-SU2.*
