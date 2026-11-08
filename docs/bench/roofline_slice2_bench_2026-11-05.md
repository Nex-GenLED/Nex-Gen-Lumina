# Roofline custom designs, slice 2 — bench steps (written 2026-11-05; steps 1–4b run 2026-11-06; steps 7–10 run 2026-11-06, second window, at 4ee8e2d; step 11 NOT run)

Branch `feat/123-roofline-slice2` from `2b03208` (the tip of
`feat/123-roofline-slice1-w2`, build-122 plus slice 1). Builds on the slice 1
stamp and fit gate (docs/bench/roofline_slice1_bench_2026-11-04.md): every step
below assumes a design that slice 1's gate already lets through.

**Run record.** Steps 1, 2, 3, 4 and 4b were run on 2026-11-06 against the spare
(`.179`, WLED 0.15.4 vid 2508020, classic ESP32 — `/json/info` `arch` =
`esp32`), curl-driven with the app's own builder output (TestFlight 357 lacks
slice 2); the raw record is the bench window's `bench-s2-results/results.md`.
Step 1 set the caps (elements, not bytes — see below). Step 4 FAILED on the
original body shape and PASSED on the bounds-first shape; the branch now emits
bounds-first (commit "bounds-first design preset body"). A second window the
same evening, on the branch at `4ee8e2d` (the fix series), ran steps 7, 8, 9
and 10 — the hardware halves curl-driven on the spare with the real builder's
body, the gate halves under `flutter test` against a request-counting fake —
all PASS, and the spare was restored byte-identical afterwards (presets.json
2,862 B, state and cfg as snapshotted, timers empty). Step 10 grew
presets.json to 100,211 B with no anomaly: the audit's 32 KB figure did NOT
reproduce, the real ceiling is above 100 KB and unmeasured, and the byte cap
was raised from 4,000 to 6,000 on 2026-11-07 (commit "raise the design
preset byte cap"). NOT run: step 5 (0.15.1, 16.0.1), step 11, and every item
that needs the app in the loop — the picker hand-off on a phone, the
editor-to-sync path writing slot 10 itself, "one write then none" on a second
sync, the read-back and its unreadable retry, the transient-versus-persistent
purge on a live controller, and the healer / restart watch when the app
returns (step 4.5).

**The spare only** (`.179`, 0.15.4 — the unit the firmware allowlist names; or
the 16.0.1 unit at `.204` and a 0.15.1 unit for step 5). **Never the `.150`
home controller**: every step here writes presets (`psave`), and the home
controller's presets.json is owner-only for `psave`/`pdel`. Snapshot
`/json/state`, `/json/info`, `/cfg.json` and `/presets.json` to files (with
sha256) before step 1 and restore after the last step (`POST /upload` of the
snapshot presets.json restores it byte for byte; a 10-row all-empty
`timers.ins` POST clears the general AND sun slots; preset 2 on the spare
captures segment 0 only, so segments 1–2 are restored by a state POST).

What slice 2 ships, so the steps make sense:

- A painted design scheduled weekly is saved to the controller as a WLED
  **API-command preset** (`o:true`): the request itself is stored and replayed at
  fire time, `seg[].i` included. The body is **BOUNDS-FIRST**: one
  `{id,start,stop}` entry per bus (left-out buses included, bus order) from the
  design's stamped `bus_lengths`, THEN one paint entry per painted bus with NO
  `start`/`stop`, THEN each left-out bus as `{id,start,stop,on:false}`. After
  a power cycle (one segment) the bounds group re-creates every bus BEFORE any
  paint is laid — see step 4's root cause for why the order is the point.
- Gates, in order, at pick time and again at write time: stamped; on the LAN (a
  direct-LAN service, not a relay of either mode); the live buses equal the stamp
  (count, every length, the controller record) AND are laid end to end (the
  body's bounds are cumulative from zero); firmware on the proven list
  (`kDesignApiPresetProvenFirmware` = `0.15.4`); the controller model proven
  (`kDesignApiPresetProvenArch` = `esp32`, `/json/info` `arch`); the wire body
  under BOTH caps — `kDesignApiPresetMaxElements` = **1,700** JSON elements (the
  limit the firmware enforces, and the cap that decides first for a typical
  body, at about 5.2 KB) and `kDesignApiPresetMaxBytes` = **6,000** (a
  backstop); at most 4 painted designs per account.
- Flash safety: the sync writes the preset only when a SHA-256 of the stored copy
  differs from the body (keys sorted; `o`/`v`/`time`/`error`/`psave` set aside;
  the name is inside the hash); one writer at a time; `/presets.json` is read
  back after every write — a readable mismatch is reported and NOT armed (and
  counts a repair attempt); an unreadable read-back gets one retry after a
  1.5 s settle within a 5 s budget, and if still unreadable is "written, not
  verified": not armed, never purged, no attempt counted, verified by the next
  sync.
- A device read that fails at write time (bus layout unread, firmware/model
  read failed) is TRANSIENT: the slot, its stored copy and its timer row are
  left exactly as they were and the owner reads "checked again on the next
  sync". Only a deleted schedule or a persistent refusal purges a slot.
- The relay refuses an API body; the one-night lease path refuses a painted
  design; any per-pixel payload that reaches a schedule by another path is
  refused at the sync builder.

Record each step's outcome in `docs/BUILD_LEDGER.md` when the slice is gated.
The caps live in `lib/features/schedule/design_api_preset.dart`
(`kBenchDesignPresetMaxBytes` in `bench/src/bench_core.dart` mirrors the byte
cap and a test asserts they agree).

Common setup (all steps): the spare provisioned as **three buses** (the spare is
100 / 100 / 100 on pins 2 / 14 / 16; a distinct middle length such as 100 / 120 /
100 is better where available, because it proves the cumulative offsets). The
app on the LAN, the spare selected, a bench account (never a customer's). A
painted design saved on this build over all three channels — a base colour with
a few accents per channel — as "Bench nightly 3-bus"; confirm on its document
that `bus_lengths` matches the spare. Reads are `/json/state`, `/json/info`,
`/presets.json` and the `/ws` live view. The spare has NTP off: after a power
cycle its clock resets, so set it with `POST /json/state {"time":<unix>}` before
waiting for a timer minute.

Byte sizes below are the **wire body**: the JSON the app POSTs (`o`, `on`, `bri`,
`seg[]` with `i`, plus `psave` and `n`), UTF-8 length. The app prints it in its
`savePreset` log line (`Payload:`); `curl` bodies are the same string. **Element
counts** are the bench's rule, which `wledJsonElementCount` implements: every
array element and every object member is one (16-byte) ArduinoJson slot, the
root takes none.

`/ws` live frames on 0.15.4 carry the gamma-2.8-corrected colour (WLED's
`calcGammaTable`), NOT scaled by state `bri`: compare frames with that model
(body 60 → 4, 255 → 255; measured 0/300 differ).

## Step 1 — calibrate the real ceiling — RUN 2026-11-06

Result: the ceiling is a JSON **element count**, not a byte count. The firmware
parses the POST into an ArduinoJson pool of 32,767 bytes at 16 bytes per
element, about 2,047 elements, and answers HTTP 400 `{"error":9}` above it.
Measured on the spare (typical body = two-digit indices, three-digit colours;
dense body = one-digit indices, small colour values):

| wire body | elements | result |
|---|---|---|
| 2,015 / 4,012 / 6,007 B | 627 / 1,299 / 1,971 | pass (save, `ps` fire, timer fire from master-off, 0/100 per bus) |
| 6,152 B | 2,019 | pass |
| 6,259 B | 2,055 | HTTP 400 `{"error":9}`, presets.json untouched |
| 7,010 / 8,011 / 12,005 B | 2,307 / 2,643 / 3,987 | HTTP 400 `{"error":9}` |
| 4,505 B dense | 1,971 | pass |
| 4,700 B dense | 2,061 | HTTP 400 `{"error":9}` |

The file-load path at fire time handled the same 2,019 elements. The audit's
"about 6.0 KB" did not reproduce (6,007 B passed). Caps set from this:
`kDesignApiPresetMaxElements` = 1,700 (15 % under the proven 2,019) and, on
the day, `kDesignApiPresetMaxBytes` = 4,000 (15 % under the dense failure,
chosen to bound presets.json growth; the former 5,000 admitted the 4,700 B
body). After step 10 (the file grew to 100,211 B with no anomaly) the byte
cap was raised to 6,000 on 2026-11-07: a typical body runs about 3.0–3.3 B
per element, so the element cap bites first at about 5.2 KB and bytes are a
backstop; 5,075 B (step 8), 6,007 B and 6,152 B all stored and fired, so
6,000 stays inside what was proven. `{"pdel":N}` pads the deleted object with
spaces instead of shrinking presets.json; later writes reuse the padding.

The procedure, for another unit or family (slots 20–24, the app's schedule
screen closed):

1. `POST /json/state` with each body. Record the HTTP status and response body
   (`{"success":true}` or `{"error":9}`), and the time to respond.
2. `GET /presets.json`: record the file's total byte length and whether it parses
   (`python -m json.tool`). Confirm slot N is present with `seg[].i`, bounds and
   `n`, and that every other slot is unchanged byte for byte against the snapshot.
3. Fire it by `POST {"ps":N}` from master-off (`{"ps":2}` or `{"on":false}`
   first). Read `/json/state`: `on` true, three segments with the bounds from
   the body, `frz` true on every painted bus. Read one `/ws` live frame: every
   bus shows the body's colours at the right LEDs (0/N differ, gamma model).
4. Arm it from a timer row: write ONE general timer row (`timers.ins[0]`,
   `en:1`, `macro:N`, hour/min = two minutes ahead on the spare's own clock,
   `dow:127`) through a `/json/cfg` POST that carries `light.gc` and
   `hw.led.fps` (never a bare cfg POST — fps 0 stalls the web UI). Power the
   strip master-off, wait for the minute: same assertions as 3. Disarm the row
   afterwards.
5. `GET /json/info`: heap (`freeheap`) and `uptime` before and after each save and
   fire — a reboot (uptime reset) or a heap step down of more than ~10 KB that
   does not recover is a failure for that size.

Pass for a size: 200/success on the POST, presets.json parses, the fire and the
timer fire both paint all three buses, no reboot. Bisect to the first failing
element count; the element cap is 15 % under the largest passing count. Delete
the calibration slots afterwards (`{"pdel":N}` once each, then `GET
/presets.json` and confirm the file still parses and every other slot is
byte-identical to the snapshot — this is the file-integrity half of step 6).

## Step 2 — a three-bus design fires by timer from master-off — RUN 2026-11-06 (curl, app body)

1. Schedule editor → Run a pattern → Pick → My Designs → "Bench nightly 3-bus".
   Expect the design to be accepted (no snackbar), and the helper line under the
   picker row ("saved to your controller as a picture … fired by its own timer").
   Set ON two minutes ahead, OFF ten minutes ahead, every day. Save.
2. On the sync: the app log shows ONE `savePreset` for slot 10 with `"o":true`,
   the bounds group, then the paint entries (`fx:0`, `i` on every painted bus, no
   `start`/`stop`), `n:"Pattern: Bench nightly 3-bus"`, and no `ib`. Then a
   `/presets.json` read (the read-back) and NO second write. `GET /presets.json`:
   slot 10 holds the body minus `o`, with `n`.
3. Sync again (pull to refresh / edit the time of a different schedule): NO
   `savePreset` for slot 10 (the stored hash matches). This is the flash-safety
   proof.
4. Master off (`{"on":false}`). Wait for the ON minute. Expect: `on` true, `bri`
   180, three segments at the bounds, every painted bus showing the design
   (`/ws` 0/N differ), `frz` true on painted buses, `ps` 10.
5. `bench preset-verify --ip <spare>` (reads only): the line
   "design preset 10 well-formed (bounds-first per-bus bounds, lit, under cap)"
   passes and names `buses=3` and the byte count.

Run 2026-11-06: 2 and 4 passed with the builder's body posted by curl (one
write, stored 891 B, hash of the stored copy equal to the sync's expected hash
offline, 10:21 timer fire from master-off painted all three buses 0/100). 1, 3
and 5 — the app in the loop — were NOT run; they are what step 7's app parts
(7.2, 7.3) would prove, and those remain NOT run.

Pass: one write then none, the timer paints all three buses from master-off.

## Step 3 — the OFF boundary still kills it — RUN 2026-11-06, PASS

With step 2's schedule showing (frozen segments): wait for the OFF minute (preset
2). Expect master off, all LEDs dark. Then `{"on":true}` by hand: expect the strip
to come up and NOT re-show the design on its own; apply any Explore pattern and
confirm it renders on all three buses (`frz` false after).

Run 2026-11-06: the OFF preset load cleared `frz` on all three segments and left
0/300 LEDs lit; a manual `on:true` showed preset 2's own look (not the design);
fx 9 with `frz:false` rendered and animated on all three buses.

Pass: OFF kills the design; the next pattern is not swallowed by a leftover freeze.

## Step 4 — power cycle before the fire, app off the LAN — RUN 2026-11-06

The evidence for owner decision 1 (per-bus bounds).

**Root cause recorded (power cycle #1, FAIL on the original shape).** After a cold
boot WLED holds ONE segment over the strip. The original body carried bounds on
each paint entry; replayed, ids 1 and 2 were APPENDED — and an appended segment
starts as a full-strip `Segment(0, total)` whose `setUp` fills its OLD range
black when the new bounds are applied. Each append therefore wiped every frozen
pixel already painted on the earlier buses, and only the LAST bus survived:
state reported three bounded frozen segments and `ps 10`, the live frame showed
buses 0 and 1 dark and bus 2 painted. Proven directly: appending one extra tiny
segment onto a fully painted strip turned all 300 LEDs dark. A hand collapse
does NOT reproduce it (deleted segments stay in the list as inactive entries, so
nothing is appended) — only a cold boot does. The fix is the ORDER: all
`{id,start,stop}` entries first, then the paint entries without bounds, then
the left-out buses as `on:false` (power cycle #2, PASS).

1. Step 2's schedule armed, the design NOT currently showing. Move the ON time to
   five minutes ahead and sync (one write expected: the time is in the cfg, not the
   preset — confirm NO `savePreset` for slot 10).
2. Put the phone on mobile data (bridge paired or not; the point is no app on the
   LAN). Power-cycle the spare (pull power, 10 s, plug in). After boot, `GET
   /json/state` from the laptop: ONE segment over the whole strip (the collapsed
   layout), master in its boot state. Set the spare's clock by API (NTP is off).
3. Wait for the ON minute with the app still off the LAN. Read `/json/state`:
   expect **three segments at the body's bounds** (the bounds group re-created
   them), master on, every painted bus showing the design (`/ws` frame at +10 s
   and again at +3 min, 0/N per bus). This is the step the original shape
   failed (last bus only).
4. Record also: `GET /json/info` uptime (no second reboot), and the `/ws` frame for
   bus 0 specifically (the first bus is the one an append wipes first).
5. Bring the app back to the LAN. Expect the healer / restart watch to find the
   buses already at their bounds (no re-provision POST, or an idempotent one) and
   the next sync to write NOTHING for slot 10. (NOT run 2026-11-06: no app.)

Pass: all three buses painted after a power cycle with no app on the LAN. Run
2026-11-06 with the bounds-first body and the middle channel excluded (power
cycle #2): buses 0 and 2 painted 0/100, bus 1 dark and bounded `on:false`,
identical at +10 s and +3 min, uptime monotonic, presets.json unchanged.

## Step 4b — the per-bus bounds repaint all three buses after the power cycle

Same as step 4, measured per bus with the live view:

1. Before the power cycle, capture one `/ws` frame while the design shows
   (`ws://<spare>/ws` + `{"lv":true}`) and save it as the reference.
2. Power-cycle with the app off the LAN; after the fire, capture another frame.
3. Compare bus by bus (LED ranges 0–99 / 100–199 / 200–299 on the spare): expect 0
   LEDs differing on EACH bus, not just overall. The original shape's failure
   shows bus 2 only, buses 0 and 1 dark.
4. Repeat once with the design's middle channel EXCLUDED (re-save the design with
   channel 2 unchecked, re-pick it in the schedule, sync, power-cycle, fire):
   expect bus 1 dark (`on:false` with bounds) and buses 0 and 2 painted — the
   left-out bus is still bounded. With the bounds-first body this is expected to
   PASS from a cold boot (it did on 2026-11-06, curl-driven, and again in step 7
   with the real builder's body; the app's own write remains unproven).

Pass: per-bus 0/N on every painted bus after the power cycle; a left-out bus is
dark and bounded.

## Step 5 — repeat on 0.15.1, 0.15.4 and 16.0.1 — NOT run

The firmware allowlist names 0.15.4 only, and the model allowlist names `esp32`
only. For each other family, run steps 1 (the 4 KB and 8 KB bodies at least,
AND the element bisect — the pool size differs by model), 2, 3 and 4 on that
unit:

- **0.15.4** — the spare `.179`: steps above as written (run 2026-11-06).
- **16.0.1** — the `.204` unit, provisioned as three buses. 16.x has `rSeg`
  (`makeAutoSegments`) and different `fxdata`; prove the API body is stored and
  replayed un-mangled: `GET /presets.json` after the save must hold `seg[].i`
  byte-for-byte (the app's read-back compares a hash; also diff the raw text), and
  the fire must paint all three buses from a cold boot. Note `fx 77` is a
  different effect on 16.x; irrelevant here (the body is `fx:0`) but record it.
- **0.15.1** — a vendor 0.15.1 unit (NOT `.150`). The fleet version; the
  `deserializeSegment` `i` block freezes and fills black before painting, which
  the body relies on, and `Segment::setUp`'s old-range blanking must be checked
  for the same append behaviour (step 4's root cause).

To run step 2 on an unproven family through the APP (rather than `curl`), add that
family's `ver` string to `kDesignApiPresetProvenFirmware` (and its `arch` to
`kDesignApiPresetProvenArch` if it differs) on a scratch build; do not commit that
change until the family passes. Record each family's `ver` and `arch` strings
exactly as `/json/info` reports them (both allowlists compare exactly).

Pass per family: steps 1 (sizes and elements), 2, 3, 4 as stated. Then add the
family's `ver` to the allowlist in a follow-up commit with this ledger row as the
evidence.

## Step 6 — presets.json byte compare (file integrity) — RUN 2026-11-06, PASS

The API-preset save is the branch the firmware's own comment calls corruption-
prone. Before step 1 and after every step that wrote a preset:

1. `GET /presets.json` to a file; record its byte length; `python -m json.tool`
   must parse it; count stray `0x00` / `0xFF` bytes (`grep -c` on the raw bytes).
2. Diff against the previous capture: ONLY the slots the step wrote may differ;
   every other slot (and every lease slot, 26–41) byte-identical throughout.
3. After the final restore, compare against the pre-step-1 snapshot: back to
   byte-identical once the calibration slots are deleted and slot 10 is removed
   (`pdel` pads the deleted object with spaces — the file keeps its length; the
   slots are what must match; `POST /upload` of the snapshot puts the bytes
   back exactly).

Run 2026-11-06: parsed after every write and delete, zero stray bytes throughout,
only written slots changed, restored byte-identical by upload.

Pass: the file parses after every write and delete, no stray bytes appear, and
only the written slots change.

## Step 7 — cold-boot re-proof with the real builder's body, through the app — RUN 2026-11-06 (second window, curl-driven; the app parts NOT run)

The 2026-11-06 proof used the builder's body posted by curl. This step proves
the same thing with the APP writing: pick, editor, compose, save, sync, timer,
power cycle.

1. On a build that contains the bounds-first builder, generate the exact body
   the app will write under `flutter test` (a scratch test calling
   `buildDesignApiPresetBody` on the "Bench nightly 3-bus" fixture — the test in
   `test/features/schedule/design_api_preset_shape_test.dart` holds the fixture
   and the golden) and keep it beside the app log for the byte compare.
2. In the app: Schedule editor → Run a pattern → Pick → My Designs → "Bench
   nightly 3-bus" (save it with ONE channel excluded, so the left-out case is
   covered). Expect the in-place gate to hand the design back (no "can't be
   chosen here" card), the helper line, then Save. ON five minutes ahead, every
   day.
3. On the sync: ONE `savePreset` for slot 10 whose `Payload:` equals the
   generated body byte for byte (plus `n`/`psave`); the read-back; NO second
   write on a second sync.
4. Master off; app off the LAN; ONE power cycle (pull power, 10 s, plug in);
   set the clock by API from the laptop; wait for the ON minute.
5. `/json/state`: three bounded segments, the left-out one `on:false`; `/ws`
   frames at +10 s and +3 min: every painted bus 0/N against the body, the
   left-out bus dark; uptime monotonic; presets.json unchanged.

Pass: the app's own write paints every included bus and darkens the excluded
one from a cold boot, with one write and no rewrite.

Run 2026-11-06 (branch at `4ee8e2d`): PASS for the body. 7.1 — the real
`buildDesignApiPresetBody` under `flutter test`, for the 100/100/100 fixture
with the middle channel excluded, gives 770 B / 202 elements, wire keys
`o,on,bri,seg,n,psave`, and the segment array AND the whole wire text are
byte-identical to the hand-built body that fired on power cycle #2 (both sha
`b8baa3bf…`). Saved to slot 10 by curl (stored 750 B, six entries in the
posted order); the stored copy's `presetPayloadHash` equals the hash the
sync computes before a write (`cb8860a7…`), so the no-rewrite precondition
holds for the bounds-first shape. 7.4–7.5 — ON armed, parked off, ONE power
cycle, clock set by API, fire at 16:39 with nothing on the LAN: three bounded
segments, the left-out one `on:false`; `/ws` at +10 s and +3 min identical:
buses 0 and 2 painted with 0/100 LEDs differing, bus 1 dark and bounded;
uptime monotonic; presets.json unchanged. Deviation: the owner's reply came
after the armed minute, so the row was re-armed three minutes ahead with no
preset write. NOT run: 7.2 and 7.3 (the picker hand-off, the app's own
`savePreset`, the read-back and "no second write" on a second sync).

## Step 8 — the element cap: just under fires, just over is refused before any write — RUN 2026-11-06 (hardware half by curl, gate half under flutter test)

1. Build two designs on the spare's layout whose wire bodies count 1,700 and
   1,701 elements (`designApiPresetWireElements`; the dense fixture in
   `test/features/schedule/design_api_preset_caps_test.dart` shows the shape —
   single-LED accents, repeated indices are fine). Record both bodies' element
   and byte counts.
2. Pick the 1,700-element design in the schedule editor: expect the gate to
   accept it; save; sync: ONE `savePreset`, read-back equal; master off; timer
   fire paints every bus (`/ws` 0/N). Also `POST` the body by curl to slot 24
   and fire it by `ps` — the controller must accept it (the cap is under the
   measured ceiling with headroom; a refusal here means the ceiling moved).
3. Pick the 1,701-element design: expect the "too detailed for your controller"
   sentence IN THE PICKER naming 1,701 details and the 1,700 limit, the editor
   offered, NOTHING handed back. Then, to cover the write-time gate, place the
   same body in a schedule document by hand (an older-build simulation) and
   sync: the same sentence in the sync status, NO `savePreset`, NO `pdel`
   (nothing landed), the schedule not armed.
4. Record that the 1,701-element body would still PARSE on this unit (the cap
   is headroom, not the ceiling): `POST` it by curl to slot 24, expect 200,
   delete it.

Pass: 1,700 fires; 1,701 is refused by the app at pick time and at write time
with no controller traffic for it.

Run 2026-11-06: PASS. Hardware half — a typical-shape bounds-first body of
1,647 elements (two-digit indices, three-digit colours, 256 accents; 5,075 B
on the wire, "Pattern: Bench cap 1650") saved to slot 10 by curl: 200 in
0.29 s, stored 5,055 B, presets.json 2,862 → 7,923 B parsing with no stray
bytes and the other slots byte-identical; applied by `ps` and fired by timer
from master-off at 16:46: three bounded frozen segments, `/ws` at +10 s and
+3 min 0/100 differing on every bus; uptime monotonic. Note: at this shape
1,647 elements is 5,075 B, OVER the 4,000-byte cap in force that day — the
app would have refused by bytes first — which is one reason the cap moved to
6,000 (see step 1). Gate half (`flutter test`, request-counting fake): the
pure cap question both gates share refuses exactly 1,701 elements (naming
1,701 details and the 1,700 limit) and exactly one byte over the byte cap —
6,001 bytes with the cap now at 6,000 (4,001 against the 4,000 in force on
the day; the boundary tests moved with the cap) — with zero requests by
construction; the pick verdict over the providers refuses an over-cap design
after one GET `/json/info` (the firmware and model read precedes the caps in
the gate order) and no write; the sync's write gate refuses the
1,701-element body and the one-byte-over body with the same sentence and
sends no `psave`, `pdel` or cfg write for the design (its other traffic on
an empty fake — the ladder presets 1–5 and one live-state restore — is
build-122 behaviour). NOT run: 8.2 and 8.3 in the app (the picker on a
phone), and 8.4's curl parse of a 1,701-element body (step 1 already parsed
1,971 and 2,019).

## Step 9 — the model (arch) refusal — RUN 2026-11-06 (flutter test only, no hardware)

Only `arch` = `esp32` is proven. Without a non-classic unit, prove the refusal
with the version-string trick used for step 5: on a scratch build, replace
`kDesignApiPresetProvenArch` with a value the spare does NOT report (e.g.
`esp32s3`), then:

1. Pick "Bench nightly 3-bus" in the schedule editor: expect "This controller
   model is not proven for roofline schedules (it reports "esp32")", nothing
   handed back, ONE `/json/info` read in the log (ver and arch come from the
   same read).
2. With a design schedule already landed (step 7), sync on that scratch build:
   the same sentence, the schedule NOT armed, and — because this refusal is
   persistent — slot 10 `pdel`'d; `GET /presets.json` parses afterwards.
3. Restore the constant; sync; expect the preset written again (one write) and
   armed.

If an S2/C3 or ESP8266 unit is available, run step 1's element bisect on it
instead: the expected ceilings are ~1,535 (24,576 B pool) and ~640 (10,240 B),
which is why the model is gated.

Pass: an unproven model is refused at pick and write time with the sentence;
restoring the allowlist recovers with one write.

Run 2026-11-06 (`flutter test` with the fake reporting `arch` "esp32s3"; the
spare was not contacted for this step): PASS. Pick: the `archUnproven`
verdict with the model sentence after exactly ONE GET `/json/info` (ver and
arch from the same read), zero writes. Sync with nothing landed: refused, no
`psave`, `pdel` or cfg write for the design. Sync with a copy already in
slot 10: refused, no `psave`, no cfg write, and ONE `pdel` of slot 10 — an
unproven model is a PERSISTENT refusal (C1), so the stale slot is purged
after the refusal, never before it. 9.3 (restore the constant, one write)
NOT run.

## Step 10 — presets.json growth toward the 32 KB figure — RUN 2026-11-06, PASS to 100,211 B, no anomaly

The audit put presets.json's safe size near 32 KB — a figure this run did
NOT reproduce: the file reached 100,211 B with no anomaly, so the real
ceiling is above 100 KB and unmeasured. The byte cap (6,000 per design, four
designs per account) bounds the app's own contribution to about 24 KB plus
the ladder and lease slots. Measure the controller rather than the estimate:

1. Snapshot presets.json. Record `fs.u` from `/json/info`.
2. By curl, save bounds-first API bodies of ~3,900 B into slots 20, 21, 22, 23
   (four, the per-account cap), then catalog-shaped presets into 24 and 25,
   then ~3,900 B bodies into 26, 28 and 41 (the lease slots) — about 32 KB of
   presets.json in all. After EACH save: `GET /presets.json` parses, zero stray
   bytes, the file length, `fs.u`, and the save's response time.
3. Fire slots 20–23 by `ps` from master-off, one at a time: every bus painted.
   Then fire them by timer, one per minute, from master-off: same.
4. Power-cycle (pull power, 10 s); set the clock; fire slot 23 by timer from the
   collapsed layout: every bus painted.
5. Keep going in 4 KB steps (slots 100+) until a save fails, presets.json stops
   parsing, a fire stops painting, or the controller reboots. Record the last
   good file length and the first bad one.
6. Delete everything written (`pdel` each, parse after each), then restore the
   snapshot by `/upload`.

Pass: 32 KB of presets.json saves, parses, fires and survives a power cycle;
the first failure point is recorded as the real ceiling for the ledger.

Run 2026-11-06: PASS, no anomaly. Base 7,923 B (slots 0/2/10/11, slot 10 =
step 8's body), baseline freeheap 121,368. Every save answered 200 in
0.05–0.49 s; after each the file parsed with zero stray bytes, every other
slot was byte-identical, and the slot applied from master-off with 0/100
LEDs differing per bus (catalog slots: on/ps correct).

| phase | slots | presets.json | freeheap after |
|---|---|---|---|
| 10.2 | 20, 21, 22, 23 (API, 3,914 B wire, 1,263 elements) | 11,823 / 15,723 / 19,623 / 23,523 B | 123,080 / 121,608 / 123,084 / 123,088 |
| 10.2 | 24, 25 (catalog, 459 B) | 24,801 / 26,079 B | 123,088 / 121,608 |
| 10.2 | 26, 28, 41 (API, lease slots) | 29,979 / 33,879 / 37,779 B | 123,088 / 122,676 / 122,668 |
| 10.5 | 100–115 (API, ~3,916 B each, 16 steps) | 41,681 B rising 3,902 B per step to 100,211 B | 120,884–123,016 |

10.3 — `ps` fires 20–23 from master-off and timer fires 20/21/22/23 one per
minute (16:57–17:00), each on/ps correct, three bounded frozen segments,
0/100 per bus. 10.4 — ONE power cycle at 37,779 B (past the audit's 32 KB):
boot to one segment, clock set by API, slot 23 by timer from the collapsed
layout at 17:11: 0/100 on every bus at +10 s and +3 min; presets.json
byte-identical through the cycle (sha `8a11f3f6…`). Deviation: the reply
came 46 s before the armed minute, so the row was re-armed three minutes
ahead with no preset write. 10.5 — stopped at a 16-step bound set for the
window (about 100 KB, three times the audit's figure), NOT at a failure:
the heap stayed within 0.5 KB of the baseline (lowest 120,884, recovered)
and save times stayed under 0.5 s. 10.6 — all 25 slots deleted by `pdel`,
the file parsing after each with the remaining slots byte-identical; the
length stays 100,211 B (pdel pads with spaces) until the `/upload` restore
put the 2,862 B snapshot back byte for byte. Observation to re-read after
the spare's next cold boot: `/json/info` `fs.u` read 221 KB after this test
against 45 KB before, while presets.json was back to 2,862 B — LittleFS
usage accounting rather than file content; a reboot or later writes should
reclaim it. (After 10.4's reboot `fs.u` read 57 against 94 before it.)

## Step 11 — the +122 sunrise and sunset rows are untouched — NOT run (needs the app on the phone)

Slice 2 must change nothing for a non-design schedule. The +122 bench proved
the sun rows on the spare (sunset flip 17:15:18, Wednesday sunrise OFF); the
restore of 2026-11-06 REMOVED the spare's sun rows at the owner's request, so
re-arm them first.

1. In the app on the LAN: one schedule "Warm White at sunset, off at sunrise"
   (a catalog pattern), plus "Bench nightly 3-bus" at a clock time. Sync.
2. `GET /json/cfg` `timers.ins`: the sunset row (hour 254, macro = the Warm
   White slot) and the sunrise row (hour 255, macro 2) are present exactly as
   build-122 writes them, and the design's clock row is a general slot; the
   general slots carry the same `en`/`dow` encoding as build-122 (compare
   against a build-122 capture of the same two schedules).
3. Sync again: no cfg write for an unchanged table, no `savePreset` for slot 10.
4. Edit the design schedule's time; sync: the sun rows unchanged byte for byte
   in the readback, only the design's general row moved.
5. Delete the design schedule; sync: slot 10 `pdel`'d, the sun rows unchanged,
   the Warm White preset untouched.
6. Wait for the sunset minute on the spare's clock (or set the clock to one
   minute before it by API): the Warm White fires; at the sunrise minute the
   strip goes off. Same as the +122 record.

Pass: the sun rows and the catalog preset behave exactly as in build-122 with
a design schedule beside them, and after it is removed.

## What to bring back

- The measured ceiling (step 1: elements first, bytes second) and the final
  values of `kDesignApiPresetMaxElements` and `kDesignApiPresetMaxBytes`
  (1,700 and 6,000 as of 2026-11-07).
- For each firmware family and model: pass/fail per step and the exact `ver`
  and `arch` strings.
- The step 4 / 4b / 7 `/json/state` and `/ws` evidence (three segments at the
  bounds, per-bus 0/N after a cold boot, the left-out bus dark) — the proof for
  owner decision 1 as re-decided on 2026-11-06 (bounds-first).
- presets.json byte lengths before / after each write, after restore, and the
  growth ceiling from step 10 (above 100 KB on the spare, unmeasured; the
  32 KB figure did not reproduce).
- Any sync that wrote slot 10 twice (a hash that did not match the stored copy):
  that is a defect in `presetPayloadHash`'s canonicalisation against what this
  firmware stores, and the raw stored copy is the evidence.
- The step 11 readbacks beside a build-122 capture of the same schedules.
