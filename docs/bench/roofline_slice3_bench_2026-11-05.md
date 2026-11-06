# Roofline custom designs, slice 3 — bench steps (written 2026-11-05, NOT run)

Branch `feat/123-roofline-slice3` from `2b03208` (the tip of
`feat/123-roofline-slice1-w2`: build-122 plus slice 1). Five commits, one per
concern. Nothing here was run against a controller; these are the steps for the
owner's bench window. Spare only (`.179`, 0.15.4; or the 16.0.1 unit at `.204`),
never the `.150` home controller. No `/cfg.json` or `/json/cfg` read is needed by
any step: the app's own LAN connect performs its cfg read; the bench reads below
are `/json/state` and the `/ws` live view only. No `psave`/`pdel` anywhere in this
slice. A bench account, never a customer's; no production reads.

Record each step's outcome in `docs/BUILD_LEDGER.md` when the slice is gated.

## Common setup (all items)

The spare provisioned as three buses of **162 / 128 / 100** LEDs on three pins
(the audit's bench layout; `hw.led.ins[]` through the app's Hardware Config
LED-count save, which writes the bounds end to end and reads back once). The app
on the LAN, the spare selected, the bench account signed in. The Design Studio
gate wants a segmented roofline: a pixel map for the spare with at least one
marked feature per bus (the feature walkthrough), and the third bus's map ending
in a marked peak (bus 3 LEDs 90–99). Confirm the dashboard shows three channels
and the studio opens in AI mode before starting.

What the slice changed, in one line each:

* the AI composer lays every pattern down per bus (channel-local), one `seg`
  entry per painted bus on the wire, where it used to work in one flat index
  space and address only seg 0 (the D-2 defect);
* "Variations of …" in the studio: a stamped saved design is the starting
  point; the prompt composes in its colours (unless the prompt names a colour)
  over its stamped bus lengths; a saved variation keeps that stamp;
* the AI (claudeProxy) context carries the bus lengths and, in a variation
  session, the saved design's colour summary — numbers only.

## Item 1 — the saved design (slice 1's stamp, the prerequisite)

1. Paint a design in the manual editor on all three buses: bus 1 red on LEDs
   0–80 and blue on 81–161; bus 2 white on 0–9 and the base elsewhere; bus 3
   green on 0–99. Save it as "Bench base 3x".
2. Read the document `/users/{uid}/designs/{id}` (bench account): expect
   `controller_id` = the spare's record id and `bus_lengths` = `[162, 128, 100]`.
3. Keep one UNSTAMPED positional design on the account (one saved before
   slice 1, or a copy of the document above with `bus_lengths` and
   `controller_id` removed by hand).

Pass: step 2 shows the two fields; step 3 leaves one positional design with
neither.

## Item 2 — the "Variations of …" entry

1. Open the Design Studio (AI mode, blank). Under Quick Ideas expect a section
   "Variations of a saved design" with the chip **"Variations of Bench base 3x"**
   and, for the unstamped design of item 1 step 3, the plain line
   `Re-save "<name>" on your roofline first to make variations of it.` with no
   chip. An effect design (a Now Playing save, a tuner save) must appear in
   neither list.
2. Tap the chip. Expect the strip "Variations of Bench base 3x" with its colour
   dots (green, red, blue, white — by share of lights, largest first), the
   sentence about keeping the design's colours, "Variations to try" (Every other
   light · One on, three off · Two on, two off) in place of Quick Ideas, the
   prompt hint `e.g. "every other light" or "1 on 3 off"`, and the Start over
   button in the app bar.
3. Tap the strip's close (×). Expect the blank studio with the entry section
   back. Tap the chip again, then Start over: the same.

Pass: 1 shows exactly one chip and one plain line; 2 and 3 as stated.

## Item 3 — generate a variation from the saved design (three buses)

With "Variations of Bench base 3x" chosen:

1. Tap **"One on, three off"**. The house total is 390 and 390 % 4 = 2, so the
   studio asks the spacing question; answer "1 on, 3 off (with remainder)".
   Expect the preview: on EVERY bus the first LED (bus LED 0) lit and then one
   in four, in the design's accent colour (its third colour by share: blue), the
   rest dark. The phase restarts at each bus: bus 2's first lit LED is bus LED
   0, not bus LED 2 (162 % 4 = 2 — on the old composer the pattern ran straight
   across the bus boundary and bus 2 started mid-cycle).
2. Type `gold every other light` and Create Design. Expect gold every other LED
   on all three buses: a prompt that names a colour keeps it; the design's
   colours are used only when none is named.
3. Type `every other light`. Expect the design's accent (blue) on every other
   LED of every bus, starting at bus LED 0 on each.
4. Turn "Preview on lights" ON with the step 3 design composed. Expect "preview"
   to land (the fit gate passes: the stamp equals the live buses) and all three
   buses painted. Turn it OFF.

Pass: 1 and 3 restart the phase on every bus and use the design's colour; 2
uses gold; 4 paints all three buses.

## Item 4 — apply, and the `/ws` frame per bus

1. With the step 3 design ("every other light", blue) composed, tap **Apply to
   Lights**. Expect "Applied to your lights". Read `/json/state`: `seg[0..2]`
   each `fx 0`, `frz true`, `col[0]` black.
2. Read the `/ws` live view frame and check it PER BUS:
   * bus 1 = frame LEDs 0–161: even bus LEDs (0, 2, …, 160) blue, odd dark;
   * bus 2 = frame LEDs 162–289: bus LED 0 = frame 162 blue, then 164, 166, …,
     288; odd bus LEDs dark;
   * bus 3 = frame LEDs 290–389: 290, 292, …, 388 blue.
   0/390 differ from the preview. On the old composer the frame would have
   stopped at bus 1 (one seg 0 `i` array, truncated at seg 0's range).
3. Repeat with "One on, three off" (with remainder): bus 1 lit at 0, 4, …, 160;
   bus 2 lit at frame 162 (bus LED 0), 166, …; bus 3 at 290, 294, …, 386. The
   old composer would have lit bus 2 first at frame 164 (bus LED 2).
4. Tap **Save**. Expect "Saved to My Designs". Read the new document: `name`
   = `Variation of Bench base 3x: <composer name>`, `controller_id` = the
   spare's record id, `bus_lengths` = `[162, 128, 100]`, `channels[].led_count`
   = 162 / 128 / 100, and `composed_pattern` (decode the string) carrying
   `channel_groups` with keys `"0"`, `"1"`, `"2"` and `channel_lengths`
   `{"0":162,"1":128,"2":100}`.
5. Apply the saved variation from My Designs (the slice 1 gate passes). The
   `/ws` frame is identical to step 2.
6. The 16.0.1 unit (`.204`), provisioned 162 / 128 / 100: repeat 1–2 once. The
   per-channel `i` arrays must land unchanged (16.x has `rSeg`; nothing in this
   slice writes bounds).

Pass: 2, 3 and 5 as stated per bus; 4 shows the stamp and the channel-local
layer; 6 matches 2.

## Item 5 — the kept stamp protects the variation

1. Hardware Config → bus 2 → 120 → Save Changes. From My Designs apply the
   saved variation of item 4 step 4. Expect the slice 1 refusal naming "128
   lights on channel 2 … has 120 now"; `/json/state` unchanged, no `i` write in
   the controller log.
2. In the studio tap "Variations of Bench base 3x" again (the base design is
   still stamped `[162, 128, 100]`), tap "Every other light", then Apply to
   Lights. Expect the SAME refusal and no write: the in-memory variation carries
   the base design's stamp. The preview still shows bus 2 at 128 LEDs — it is
   composed over the stamp, not the live 120.
3. Restore bus 2 → 128 → Save Changes. Apply again: "Applied to your lights".
4. Off the LAN (phone on mobile data, bridge paired): the studio still composes
   a variation (the stamped lengths need no cfg read). Apply to Lights →
   "can only be applied on your home network" and NO command document under
   `/users/{uid}/commands`. Save → the document is STAMPED `[162, 128, 100]`
   (an ordinary off-LAN studio save stays unstamped, as before).

Pass: 1 and 2 refuse with zero writes; 3 applies; 4 refuses the apply, writes
no command, and saves stamped.

## Item 6 — the AI context (claudeProxy)

The context block is proven by the unit snapshot
(`test/features/ai/roofline_context_snapshot_test.dart`): the roofline block
carries `- Hardware channels: 3 (162, 128, 100 LEDs)`, the SAVED DESIGN block
carries the stamped bus lengths and the colour summary and nothing that names
the design, the controller or the account. No bench step reads the function
logs (production). On the bench, confirm only the behaviour:

1. With "Variations of Bench base 3x" chosen in the studio, open the Lumina tab
   and ask "suggest a variation of this look". Expect a reply proposing colours
   and an effect (the `colors` / `effect` / `wled` shape), containing no
   per-LED list and no `i` array, and not naming the design.
2. Start over in the studio (the base is cleared), ask the same. Expect an
   ordinary reply with no mention of a saved look.

Pass: 1 proposes colours and an effect only; 2 has no saved-design content.

## Items 7–8 — the prompt-parser follow-ups (written 2026-11-06, NOT run)

Two defects of the Design Studio's prompt parser, found while building slice 3
and fixed in the two commits after the five above (`nlu_service.dart` only;
no effect id, label or table changed). Unit-proven by
`nlu_direction_not_location_fail_before_test` + `nlu_direction_phrases_test`
(defect 1) and `nlu_motion_effect_id_fail_before_test` +
`nlu_motion_effect_id_test` (defect 2). On the bench confirm only the
behaviour. Blank studio (no "Variations of" base chosen), the spare at
162 / 128 / 100 with the map of the common setup — no segment named "left",
"west", "right" or "east".

### Item 7 — a direction of motion is never a location zone (defect 1)

Before: the parser read the bare words "left" / "right" anywhere in a clause
as the left or right SIDE of the house, a location the composer matches by
segment name; on this map nothing matched, so the clause composed nothing.

1. Tap the **"Chase Effect"** quick idea ("Blue chase effect moving left to
   right"). Expect the understanding panel to show the whole roofline, a
   chase, left to right, and a preview on all three buses — NOT the red
   "No layers produced LED assignments" error of before.
2. Type `wave effect moving right to left` (the placeholder example's motion
   clause) and Create Design. Expect the whole roofline, moving right to
   left, no direction question. (It composes as a CHASE — see item 8 step 6.)
3. Type `red moving right`. Expect the whole roofline, moving left to right
   (before: the right side of the house, and the direction silently "inward").
4. Type `red chase left`. Expect the whole roofline, right to left, and no
   direction question — the side was stated.
5. A place is still a place. In the installer's map step rename bus 2's
   segment to **"Left run"** (a name the composer matches for the left side)
   and save. Back in the studio type `red on the left side`: expect bus 2
   alone painted red. Type `chase on the left side`: expect the direction
   question (none was stated) and, after answering, bus 2 alone. Type `red to
   the left of the garage`: expect bus 2 alone (no motion word, so "to the
   left" is a place). Rename the segment back.

Pass: 1–4 compose on the whole roofline with the stated direction and no
question; 5 paints bus 2 alone for all three prompts.

### Item 8 — a prompted motion runs as an effect (defect 2)

Before: the parser's motion carried no WLED effect id, the composer read
"no id" as "no effect" and emitted the still picture, and the saved design
said `has_motion: true, effect_id: 0`, read back as static. Now a prompted
word carries the id the clarification sheet's chip already applies: chase 28,
wave 67, twinkle 80, pulse 2.

1. Item 7 step 1 composed ("Chase Effect"): tap **Apply to Lights**. Expect
   "Applied to your lights". Read `/json/state`: `seg[0..2]` each `fx 28`,
   `sx 128`, `ix 128`, `col[0]` = `[0,0,255,0]`, no `i` frame. Before: `fx 0`
   and a still `i` frame on every bus.
2. Read the `/ws` live view twice, a second apart: the frame differs on every
   bus (a running chase), blue the only lit colour.
3. Type `wave effect right to left`, Create Design, Apply: `fx 67` on
   `seg[0..2]`. Then `red twinkle inward` → `fx 80`; `red breathe inward` →
   `fx 2`. Cross-check the sheet once: type `red`, and when the studio asks
   for an effect tap **Chase** — the same `fx 28` per bus as step 1.
4. Type `red scan inward`, Create Design, Apply. Expect a STILL picture:
   `fx 0` and an `i` frame on every bus. Scan is in no existing effect table
   and was left static on purpose rather than guessed.
5. Save the step 1 design. Read the document: `composed_pattern` (decode the
   string) carries `has_motion: true`, `effect_id: 28`, `speed: 128`. Open it
   in My Designs: the detail screen shows it as a motion. Apply from My
   Designs: `fx 28` on `seg[0..2]`. Before: `effect_id: 0`, shown and applied
   as a still picture.
6. Known and NOT fixed here — record only. (a) `wave effect moving right to
   left` runs as a chase (`fx 28`): "moving" is a chase word in the motion
   table and chase is scanned first. (b) `blue chase` with no direction asks
   "Which direction should the chase effect go?"; choosing "Right to left" is
   not applied and the design composes left to right — the parser never
   binds a clarification to its layer; the effect id survives the question
   either way (`fx 28`).

Pass: 1–3 and 5 run the stated effect on all three buses; 4 is a still
picture; 6 recorded as observed.

## Teardown

Restore the spare to 162 / 128 / 100 if any step changed it. Delete the bench
variations from My Designs through the app (bench account designs only; bridge
records are never deleted). Re-run `docs/bench/roofline_slice1_bench_2026-11-04.md`
items 1 and 2 if the stamp fields are in doubt.
