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

## Item 3 — freeze-aware Game Day revert capture

Change: `captureRevertLook` refuses when any live, switched-on segment reports
`frz: true` (a per-pixel frame is showing), with the painted-design sentence, before
the layout verdict and before any repair. Nothing stored, nothing written.

Prerequisite: a Game Day team configured on the bench account with any colour-and-
effect base design; the spare at three buses of 100/100/100; Lumina Blue (or any
effect look) showing on all three buses.

1. Baseline (unchanged behaviour): tap Light Up Now. Expect the team look to fire
   and, in the console, the ephemeral session document's `revert_wled_payload` to
   hold three segments with the effect look and no `frz: true`. End the session
   (or wait for the game-end revert) and confirm the effect look returns.
2. Apply "Bench stamp 3x100" from My Designs (all three buses painted). Read
   `/json/state`: expect `seg[0..2].frz == true`, `fx 0`, `col[0]` black (the base
   under the paint). This is the frozen frame.
3. Tap Light Up Now. Expect the orange snackbar "Your lights are showing a painted
   design, which can't be saved as the look to come back to. Apply a pattern or a
   colour first, then try Light Up Now again." Expect: NO session document created,
   NO POST in the controller log during the tap (the capture must not write, and must
   not run the geometry repair), the painted design still on the strip.
4. Apply any pattern from Explore (any effect; the chokepoint writes `frz:false`).
   Read `/json/state`: `frz == false` on all three. Tap Light Up Now: expect the team
   look to fire and the revert payload to hold the effect look (as step 1).
5. Partial: apply the painted design, then from the Home channel bar switch channel 2
   OFF (the frozen segment is now `on:false`). Tap Light Up Now: expect the refusal
   (channels 1 and 3 are still frozen and on). Switch all three off, then apply a
   pattern to all three and confirm step 4 again.
6. Collapsed AND frozen: power-cycle the spare (one segment after boot), then apply
   the painted design from the LAN (the app re-heals first on connect; if it does not,
   note it: the healer is a +122 item, not this slice). If the strip is frozen with a
   single segment, Light Up Now must refuse with the painted-design sentence and
   ZERO POSTs — the freeze check runs before the repair.
7. One-bus unit (`.204` provisioned as one bus of 100): repeat 2–4; expect the same.

Pass: 1 and 4 capture; 3, 5 (first half) and 6 refuse with the painted-design
sentence and zero writes; no session document exists after a refusal.

## Item 4 — per-pixel designs blocked from Sync fan-out and Game Day base designs

Change: the Game Day plan write (`gameDayDesignUpdate`) throws a plain refusal for a
payload carrying `seg[].i`; the two Game Day save doors show that sentence; the
library picker's refusal names Game Day as the destination. On Sync, a per-pixel
assignment is not well-formed (panel sentence) and `broadcastSync` refuses the command
before the flag read with reason `per_pixel_design` (Start sentence). No server
change: the fan-out whitelist already drops `i`; this stops the app from sending it.

Game Day (bench account, any team configured, "Bench stamp 3x100" saved):

1. Game Day screen → the team's design picker → My Designs → tap "Bench stamp 3x100".
   Expect the snackbar naming the design, "painted design", "can't be the Game Day base
   design", "colour-and-effect"; the picker stays open; the team document's
   `saved_design_payload` / `saved_design_name` are unchanged (console read, own
   account).
2. Explore → any colourway → tuner → Save → Game Day → the team. Expect "Saved … to
   Game Day" and the document updated (effect designs are unaffected).
3. Direct write attempt (defence in depth): from a Dart test shell or the bench CLI, call
   `gameDayDesignUpdate(designName: …, wledPayload: <the painted design's
   toWledPayload()>)`; expect `PerPixelDesignRefused` with the same sentence, and no
   Firestore write (the exception is thrown before `update`).
4. Confirm Light Up Now and a scheduled fire still use the effect design saved in step
   2 (the `saved_design_payload` path is untouched for effect payloads).

Neighborhood Sync (bench group with two synthetic members; fan-out flag ON for the
group, or OFF — both are covered by the guard running before the flag read):

5. Sync control panel → Browse all: confirm My Designs is not offered (unchanged, the
   picker excludes saved designs by node id). Choose any catalog pattern, Start:
   expect the normal start (unchanged).
6. The refusal has no UI door today (step 5), so prove it at the notifier: in a Dart
   test shell against the bench group, build a `SyncCommand` with a member override
   from `SyncPatternAssignment.fromWledPayload(payload: <painted toWledPayload()>)`
   and call `broadcastSync`. Expect `commandWritten == false`,
   `failure.reason == 'per_pixel_design'`, NO document under the group's commands,
   NO fan-out request in the function logs, and `syncStartFeedbackFor` giving the
   "painted design … Nothing was sent" sentence. This mirrors
   test/features/neighborhood/sync_per_pixel_block_test.dart on the live backend.
7. Repeat 6 with the effect override (`SyncPatternAssignment(name, effectId: 28,
   colors: […])`): expect the normal write and fan-out.

Pass: 1 and 3 refuse with the Game Day sentence and no write; 2 and 4 unchanged; 5
and 7 unchanged; 6 refuses with nothing written or fanned out.
