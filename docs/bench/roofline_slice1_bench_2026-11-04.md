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

## Item 2 — fit gate at apply time

Change: `applyPositionalDesignDetailed` (the one spine behind My Designs, scenes,
favourites, the AI studio) refuses a STAMPED design when the live buses differ from
its stamp (bus count, any bus length, or the controller record), and refuses it off
the LAN (no bus data). Nothing is written on a refusal. Unstamped designs are not
gated. The editor's own Apply/preview are not gated: the editor re-fits over the live
lengths, which is the repair the message names.

Prerequisite: "Bench stamp 3x100" from item 1 (stamped `[100, 100, 100]`).

1. Fits: apply it from My Designs. Expect "Applied", `/ws` live view shows all three
   buses painted (0/300 differ from the editor's picture). Also from the Home
   favourites grid after saving it as a Static favourite, and from the detail screen.
2. One bus length differs: in Hardware Config set bus 2's LED count to 120 and save
   (bounds 0/100, 100/220, 220/320; read-back lands). Back in My Designs, apply the
   design. Expect the refusal snackbar naming the design, "100 lights on channel 2 …
   has 120 now", and the repair sentence; `/json/state` unchanged (same `seg[].col`,
   no `i` write in the controller log; `/ws` frame unchanged).
3. Repair path A: open the design (Edit), Save. Re-read the doc: `bus_lengths` =
   `[100, 120, 100]`. Apply: expect "Applied", three buses painted, bus 2 painted to
   120 (the editor re-fitted it; LEDs 100–119 on bus 2 carry the base colour).
4. Bus count differs: set bus 3's LED count to 0 / remove the third output in
   Hardware Config (two buses). Apply the design re-saved in step 3. Expect "saved for
   3 channels, but your controller has 2 now" and no write.
5. Repair path B: restore the three outputs (100/120/100). Apply: expect "Applied".
6. Re-provisioned controller: select the OTHER bench unit (`.204`, 16.0.1) provisioned
   as three buses of 100/120/100 — same lengths, different controller record. Apply
   the design. Expect "saved for a different controller" and no write. (If only one
   unit is available, edit the stored `controller_id` on the bench account's doc to
   any other string and repeat.)
7. Off the LAN: phone on mobile data, bridge paired. Apply the design. Expect "can
   only be applied on your home network", and NO command document written under
   `/users/{uid}/commands` for it (check the collection before/after).
8. Legacy: a design saved before this build (unstamped) applies from every door on
   every layout above exactly as on +122. Confirm with one such design in step 2's
   layout.
9. Restore the spare to 100/100/100 and re-save the design once so the stamp matches.

Pass: 1, 3, 5, 8 apply; 2, 4, 6, 7 refuse with the stated sentence and zero writes.
