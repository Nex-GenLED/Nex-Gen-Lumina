# Roofline custom designs, slice 2 — bench steps (written 2026-11-05, NOT run)

Branch `feat/123-roofline-slice2` from `2b03208` (the tip of
`feat/123-roofline-slice1-w2`, build-122 plus slice 1). Nothing here was run against
a controller; these are the steps for the owner's bench window. Builds on the slice
1 stamp and fit gate (docs/bench/roofline_slice1_bench_2026-11-04.md): every step
below assumes a design that slice 1's gate already lets through.

**The spare only** (`.179`, 0.15.4 — the unit the firmware allowlist names; or the
16.0.1 unit at `.204` and a 0.15.1 unit for step 5). **Never the `.150` home
controller**: every step here writes presets (`psave`), and the home controller's
presets.json is owner-only for `psave`/`pdel`. Take `bench snapshot --ip <spare>`
before step 1 and `bench restore --ip <spare>` after the last step.

What slice 2 ships, so the steps make sense:

- A painted design scheduled weekly is saved to the controller as a WLED
  **API-command preset** (`o:true`): the request itself is stored and replayed at
  fire time, `seg[].i` included. The body carries **one entry per bus with explicit
  `start`/`stop`** from the design's stamped `bus_lengths`, so a power cycle before
  the fire (which collapses the split to one segment) is repaired by the fire itself.
  A bus the design leaves out is bounded and `on:false`.
- Gates, in order, at pick time and again at write time: stamped; on the LAN (a
  direct-LAN service, not a relay of either mode); the live buses equal the stamp
  (count, every length, the controller record); firmware on the proven list
  (`kDesignApiPresetProvenFirmware` = `0.15.4` only until this bench adds the
  others); the wire body ≤ `kDesignApiPresetMaxBytes` (**5,000, provisional — step 1
  sets it**); at most 4 painted designs per account.
- Flash safety: the sync writes the preset only when a SHA-256 of the stored copy
  differs from the body (keys sorted; `o`/`v`/`time`/`error`/`psave` set aside; the
  name is inside the hash); one writer at a time; `/presets.json` is read back after
  every write and a hash mismatch is reported and NOT armed.
- The relay refuses an API body; the one-night lease path refuses a painted design;
  any per-pixel payload that reaches a schedule by another path (Lumina chat, a
  calendar intent, an older build) is refused at the sync builder.

Record each step's outcome in `docs/BUILD_LEDGER.md` when the slice is gated, and
put the measured ceiling into `kDesignApiPresetMaxBytes` (one constant,
`lib/features/schedule/design_api_preset.dart`; `kBenchDesignPresetMaxBytes` in
`bench/src/bench_core.dart` mirrors it and a test asserts they agree).

Common setup (all steps): the spare provisioned as **three buses** through the
app's Hardware Config LED-count save (e.g. 100 / 100 / 100 on three pins; a
distinct middle length such as 100 / 120 / 100 is better, because it proves the
cumulative offsets). The app on the LAN, the spare selected, a bench account (never
a customer's). A painted design saved on this build over all three channels — a
base colour with a few accents per channel — as "Bench nightly 3-bus"; confirm on
its document that `bus_lengths` matches the spare. Reads are `/json/state`,
`/json/info`, `/presets.json` and the `/ws` live view; no `/json/cfg` read is
needed by any step beyond the app's own LAN connect.

Byte sizes below are the **wire body**: the JSON the app POSTs (`o`, `on`, `bri`,
`seg[]` with `i`, plus `psave` and `n`), UTF-8 length. The app prints it in its
`savePreset` log line (`Payload:`); `curl` bodies are the same string.

## Step 1 — calibrate the real ceiling (2 / 4 / 6 / 8 / 12 KB bodies)

Sets `kDesignApiPresetMaxBytes`. The audit puts the POST ceiling near 6 KB
(`{"error":9}` at ~6.0 KB on 0.15.4); the FILE-LOAD path an API preset takes at
fire time has never been measured, and may be lower.

Build five API bodies by hand (`curl`, or the editor with progressively denser
paint), each `{"o":true,"on":true,"bri":180,"seg":[…3 bus entries with bounds…],
"psave":N,"n":"cal-N"}`, with `i` arrays padded with distinct single-pixel entries
until the wire body is about 2,000 / 4,000 / 6,000 / 8,000 / 12,000 bytes. Use
slots 20, 21, 22, 23, 24 (the top of the schedule band, so nothing the app wrote
is touched; the app's orphan purge would delete them on the next sync, so run this
step with the app's schedule screen closed, or re-create them after).

For each body, in order:

1. `POST /json/state` with the body. Record the HTTP status and response body
   (`{"success":true}` or `{"error":9}`), and the time to respond.
2. `GET /presets.json`: record the file's total byte length and whether it parses
   (`python -m json.tool`). Confirm slot N is present with `seg[].i`, bounds and
   `n`, and that slots 1–5 are unchanged byte for byte against the snapshot.
3. Fire it by `POST {"ps":N}` from master-off (`{"on":false}` first). Read
   `/json/state`: `on` true, three segments with the bounds from the body,
   `frz` true on every painted bus. Read one `/ws` live frame: every bus shows the
   body's colours at the right LEDs (0/N differ against the body).
4. Arm it from a timer row: write ONE general timer row (`timers.ins[0]`,
   `en:1`, `macro:N`, hour/min = two minutes ahead on the spare's own clock,
   `dow:127`) through `bench sync-sim`-style `/json/cfg` POST that carries
   `hw.led.fps` (never a bare cfg POST — fps 0 stalls the web UI). Power the strip
   master-off, wait for the minute: same assertions as 3.
5. `GET /json/info`: heap (`freeheap`) and `uptime` before and after each save and
   fire — a reboot (uptime reset) or a heap step down of more than ~10 KB that
   does not recover is a failure for that size.

Pass for a size: 200/success on the POST, presets.json parses, the fire and the
timer fire both paint all three buses, no reboot. The **largest passing size**
with at least 15 % headroom below the first failing size becomes the cap;
record the first failing size and its symptom (HTTP 400 `{"error":9}`,
presets.json truncated, fire paints nothing, reboot). If 12 KB passes, the cap
may be raised to the largest tested size minus headroom and the next step uses
the real design. Delete the five calibration slots afterwards (`{"pdel":N}` once
each, then `GET /presets.json` and confirm the file still parses and slots 1–5
are byte-identical to the snapshot — this is the file-integrity half of step 6).

## Step 2 — a three-bus design fires by timer from master-off

1. Schedule editor → Run a pattern → Pick → My Designs → "Bench nightly 3-bus".
   Expect the design to be accepted (no snackbar), and the helper line under the
   picker row ("saved to your controller as a picture … fired by its own timer").
   Set ON two minutes ahead, OFF ten minutes ahead, every day. Save.
2. On the sync: the app log shows ONE `savePreset` for slot 10 with `"o":true`,
   three `seg` entries with the stamp's bounds, `fx:0`, `i` on every painted bus,
   `n:"Pattern: Bench nightly 3-bus"`, and no `ib`. Then a `/presets.json` read
   (the read-back) and NO second write. `GET /presets.json`: slot 10 holds the body
   minus `o`, with `n`.
3. Sync again (pull to refresh / edit the time of a different schedule): NO
   `savePreset` for slot 10 (the stored hash matches). This is the flash-safety
   proof.
4. Master off (`{"on":false}`). Wait for the ON minute. Expect: `on` true, `bri`
   180, three segments at the bounds, every painted bus showing the design
   (`/ws` 0/N differ), `frz` true on painted buses, `ps` 10.
5. `bench preset-verify --ip <spare>` (reads only): the line
   "design preset 10 well-formed (per-bus bounds, lit, under cap)" passes and names
   `buses=3` and the byte count.

Pass: one write then none, the timer paints all three buses from master-off.

## Step 3 — the OFF boundary still kills it

With step 2's schedule showing (frozen segments): wait for the OFF minute (preset
2). Expect master off, all LEDs dark. Then `{"on":true}` by hand: expect the strip
to come up and NOT re-show the design on its own (the freeze clears on the preset
load of the OFF boundary or stays harmlessly on a dark strip — record which); apply
any Explore pattern and confirm it renders on all three buses (`frz` false after).

Pass: OFF kills the design; the next pattern is not swallowed by a leftover freeze.

## Step 4 — power cycle before the fire, app off the LAN

The evidence for owner decision 1 (per-bus bounds).

1. Step 2's schedule armed, the design NOT currently showing. Move the ON time to
   five minutes ahead and sync (one write expected: the time is in the cfg, not the
   preset — confirm NO `savePreset` for slot 10).
2. Put the phone on mobile data (bridge paired or not; the point is no app on the
   LAN). Power-cycle the spare. After boot, `GET /json/state` from the laptop: ONE
   segment over the whole strip (the collapsed layout), master in its boot state.
3. Wait for the ON minute with the app still off the LAN. Read `/json/state`:
   expect **three segments at the body's bounds** (the API body re-created them),
   master on, every painted bus showing the design (`/ws` frame). This is the step
   that an API body WITHOUT bounds would fail (bus 0 only, ids 1–2 ignored).
4. Record also: `GET /json/info` uptime (no second reboot), and the `/ws` frame for
   bus 2 specifically (the last bus is the one a collapsed layout loses first).
5. Bring the app back to the LAN. Expect the healer / restart watch to find the
   buses already at their bounds (no re-provision POST, or an idempotent one) and
   the next sync to write NOTHING for slot 10.

Pass: all three buses painted after a power cycle with no app on the LAN.

## Step 4b — the per-bus bounds repaint all three buses after the power cycle

Same as step 4, measured per bus with the live view:

1. Before the power cycle, capture one `/ws` frame while the design shows
   (`ws://<spare>/ws` + `{"lv":true}`) and save it as the reference.
2. Power-cycle with the app off the LAN; after the fire, capture another frame.
3. Compare bus by bus (LED ranges 0–99 / 100–219 / 220–319 for a 100/120/100
   spare): expect 0 LEDs differing on EACH bus, not just overall. A pass with bus
   0 only (the no-bounds failure) shows buses 1 and 2 at the firmware amber or dark.
4. Repeat once with the design's middle channel EXCLUDED (re-save the design with
   channel 2 unchecked, re-pick it in the schedule, sync, power-cycle, fire):
   expect bus 1 dark (`on:false` with bounds) and buses 0 and 2 painted — the
   left-out bus is still bounded.

Pass: per-bus 0/N on every painted bus after the power cycle; a left-out bus is
dark and bounded.

## Step 5 — repeat on 0.15.1, 0.15.4 and 16.0.1

The firmware allowlist names 0.15.4 only. For each other family, run steps 1
(the 4 KB and 8 KB bodies at least), 2, 3 and 4 on that unit:

- **0.15.4** — the spare `.179`: steps above as written.
- **16.0.1** — the `.204` unit, provisioned as three buses. 16.x has `rSeg`
  (`makeAutoSegments`) and different `fxdata`; prove the API body is stored and
  replayed un-mangled: `GET /presets.json` after the save must hold `seg[].i`
  byte-for-byte (the app's read-back compares a hash; also diff the raw text), and
  the fire must paint all three buses. Note `fx 77` is a different effect on 16.x;
  irrelevant here (the body is `fx:0`) but record it.
- **0.15.1** — a vendor 0.15.1 unit (NOT `.150`). The fleet version; the
  `deserializeSegment` `i` block freezes and fills black before painting, which
  the body relies on.

To run step 2 on an unproven family through the APP (rather than `curl`), add that
family's `ver` string to `kDesignApiPresetProvenFirmware` on a scratch build; do
not commit that change until the family passes. Record each family's `ver` string
exactly as `/json/info` reports it (the allowlist compares exactly).

Pass per family: steps 1 (sizes), 2, 3, 4 as stated. Then add the family's `ver`
to the allowlist in a follow-up commit with this ledger row as the evidence.

## Step 6 — presets.json byte compare (file integrity)

The API-preset save is the branch the firmware's own comment calls corruption-
prone. Before step 1 and after every step that wrote a preset:

1. `GET /presets.json` to a file; record its byte length; `python -m json.tool`
   must parse it; count stray `0x00` / `0xFF` bytes (`grep -c` on the raw bytes).
2. Diff against the previous capture: ONLY the slots the step wrote may differ;
   slots 1–5 and every lease slot (26–41) byte-identical throughout.
3. After the final `bench restore`, compare against the pre-step-1 snapshot: back
   to byte-identical once the calibration slots are deleted and slot 10 is removed
   by deleting the schedule (the orphan purge `pdel`s it on the next sync — confirm
   the file still parses after that `pdel`).

Pass: the file parses after every write and delete, no stray bytes appear, and
only the written slots change.

## What to bring back

- The measured ceiling (step 1) and the final value for `kDesignApiPresetMaxBytes`.
- For each firmware family: pass/fail per step and the exact `ver` string.
- The step 4 / 4b `/json/state` and `/ws` evidence (three segments at the bounds,
  per-bus 0/N) — the proof for owner decision 1.
- presets.json byte lengths before / after each write and after restore.
- Any sync that wrote slot 10 twice (a hash that did not match the stored copy):
  that is a defect in `presetPayloadHash`'s canonicalisation against what this
  firmware stores, and the raw stored copy is the evidence.
