# Roofline custom designs, slice 1 — bench steps (written 2026-11-04, NOT run)

Branch `feat/123-roofline-slice1` from tag `build-122` (`f7b8317`). Four items, one
commit each. Nothing here was run against a controller; these are the steps for the
owner's bench window. Spare only (`.179`, 0.15.4; or the 16.0.1 unit at `.204`), never
the `.150` home controller. No `/cfg.json` or `/json/cfg` read is needed by any step:
the app's own LAN connect performs its cfg read; the bench reads below are `/json/state`
and `/ws` live view only. No `psave`/`pdel` anywhere in this slice.

Record each step's outcome in `docs/BUILD_LEDGER.md` when the slice is gated.

Common setup (all items): the spare provisioned as three buses of 100 LEDs each
(`hw.led.ins[]` lengths 100 / 100 / 100 on three pins; through the app's Hardware
Config screen LED-count save, which writes the bounds end to end and reads back once).
The app on the LAN, the spare selected, My Designs open. Confirm the dashboard shows
three channels before starting.

## Item 1 — layout stamp at save time

Change: `CustomDesign.layoutStamp` (`controller_id`, `bus_lengths`), written by the
paint editor and the AI studio from `deviceChannelsProvider` + the selected controller
record id. Legacy designs are unstamped and unchanged.

1. Paint a design in the manual editor on all three channels (a base colour plus a
   few accents per channel). Save it as "Bench stamp 3x100".
2. Read the document `/users/{uid}/designs/{id}` in the console (own account; a
   bench account, never a customer's): expect `controller_id` = the spare's controller
   record id and `bus_lengths` = `[100, 100, 100]`; `channels[].led_count` = 100 each.
3. Rename the design from the detail screen. Re-read: both fields unchanged (the
   rename path copies the loaded model and `.update()` merges by key).
4. Duplicate it. Re-read the copy: same two fields.
5. Open an older design saved before this build (unstamped) from the detail screen's
   Edit, paint nothing, Save. Re-read: it is now stamped for the spare's three buses.
   (An unstamped design that is never re-saved must show NO new text anywhere in My
   Designs or the detail screen — walk both screens and confirm nothing changed for it.)
6. AI studio: generate any design over the roofline, Save. Re-read: stamped the same way.
7. Off the LAN (phone on mobile data, bridge paired): the editor cannot open (no bus
   data; unchanged behaviour). The AI studio's Save, if reachable, writes the design
   UNSTAMPED (no `bus_lengths` field) — confirm, and confirm it still applies through the
   relay exactly as it did on +122 (the gate in item 2 only fires for stamped designs).

Pass: steps 2, 3, 4, 5, 6 show the fields as stated; step 7 shows no field and no
behaviour change.
