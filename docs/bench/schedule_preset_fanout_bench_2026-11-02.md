# Spare-bench proof — scheduled catalog pattern on every bus (fix/122-schedule-presets)

Scope: prove that a repeating schedule's preset (slots 10–25) and a one-night
lease preset (slots 26–41) now name every bus of the controller, that the fire
lights every channel, and that unknown-facts and single-bus behaviour is
unchanged. **Spare unit only** (the 0.15.4 spare), never the home unit `.150`
(presets.json flash corruption, no psave/pdel there) and never a customer unit.
Every step below runs on the owner's go. Nothing here contacts a controller
until the owner says so.

Prerequisite: the spare must have **two or more buses** (`hw.led.ins` length ≥ 2).
It had one bus / 100 LEDs on 2026-10-27; the owner re-wires or re-provisions it
first. Record `ver`, `vid`, bus lengths and the bus GPIOs before starting.

## 0. Baseline (reads only)

1. `GET /json/cfg` → save; note `hw.led.ins[]` (count N, each `start`/`len`).
2. `GET /json/state` → save; note `seg[]` count and bounds (should be N
   segments at the bus boundaries; if not, let the app's healer re-provision
   on connect and re-read).
3. `GET /presets.json` → save, sha256. Note which of slots 10–41 are occupied.
4. `GET /json/cfg` → `timers.ins` → save (expect no schedule rows for the bench
   account).

## 1. Repeating schedule — two or more buses

1. On the home LAN, bench account, 122 build with this branch: Schedule → `+`
   → Run a pattern → Explore → pick a three-colour Solid (e.g. "Harvest Moon -
   Solid", fx 84 pal 5) → ON = now + 3 min, OFF = now + 6 min, every day → Save.
   Let Sync finish (status row green).
2. `GET /presets.json` → the schedule slot (10 if the account has one schedule)
   must hold `seg` with **exactly N entries, ids 0..N-1**, each with the same
   `fx`/`col`/`sx`/`ix`/`pal`/`grp`/`spc` and `on:true`, root `on:true`, and
   **no `start`/`stop`** on any entry (ids only). Save the slot body.
3. Watch the ON fire (`LUMINA_WIRE` not involved — the controller fires it):
   `GET /json/state` at ON + 15 s → `ps` = the slot, every `seg[i]` has the
   pattern's `fx` and `col[0]`, `on:true`, `frz:false`. Walk outside: every
   channel shows the pattern. **Before the fix** (build-121 on the same unit):
   channel 1 shows the pattern, channel 2+ shows the capture from the last Sync.
4. OFF fire → `GET /json/state` → root `on:false`.

## 2. One-night entry — two or more buses

1. Schedule → `+` → Just this day (today) → the same Explore pattern → ON =
   now + 3 min, OFF = now + 10 min → Save on the LAN ("Saved for …", not the
   off-LAN text).
2. `GET /presets.json` → the lease slot (26–41, name `Lease YYYY-MM-DD`) has the
   same N-entry id-only shape; `GET /json/cfg timers.ins` has one row with
   `macro` = that slot, `hour`/`min` = ON, single-day `dow`.
3. Fire → `GET /json/state` → every segment carries the pattern.

## 3. One-night entry — channel scope

1. Same as §2 but tick only channel 2 in the channel picker (the editor says
   the other channels will turn off).
2. `GET /presets.json` → lease slot `seg` = `{id:0,on:false}` … and
   `{id:1, <pattern>, on:true}` (addressed bus lit, every other bus `on:false`).
3. Fire → channel 1 dark, channel 2 shows the pattern.

## 4. One segment after a restart

1. Owner power-cycles the spare. Wait 90 s. `GET /json/state` → one segment
   over the whole strip (the factory collapse), orange, `ps -1`.
2. Open the app on the LAN with the bench account and edit the §1 schedule's
   time (forces a Sync). In the app log expect `applyGeometryJson` (the gate's
   re-provision) **before** the psave of the schedule slot.
3. `GET /json/state` → N segments at the bus boundaries again. `GET
   /presets.json` → the schedule slot still has N id-only entries (the bus set,
   not the one live segment, decided the shape).
4. Fire → every channel shows the pattern.

## 5. Unchanged behaviour (negative controls)

1. Single-bus: not provable on this spare once re-wired; covered by the unit
   test (`fanOutPatternPayloadToBuses` returns the input for < 2 bus ids). If a
   single-bus unit is at hand: §1 steps produce a one-entry id-less slot body
   identical to build-121's.
2. Unknown facts: a relay-only account never psaves a schedule (presets are
   unreadable over the relay, the sync refuses to rewrite the block) and a
   lease is deferred off-LAN; no bench step, covered by the unit tests.
3. A My Design with per-channel ids scheduled from My Designs: the slot body is
   the design's own `seg` array, unchanged.

## 6. Restore

1. Delete the bench schedule and the one-night entries in the app; let Sync
   run (its orphan purge `pdel`s 10–25; lease slots stay, inert without a timer
   row — delete them with the bench harness restore from the §0 snapshot if a
   clean presets.json is wanted).
2. `GET /presets.json` → compare with §0 (slots touched: the schedule slot,
   the lease slot(s)); `GET /json/cfg timers.ins` → back to §0.
3. `bench restore --ip <spare>` from the §0 snapshot (timers + master power).

## What to record

Per step: the `/presets.json` slot body, the `/json/state` at fire (+15 s),
the app's `LUMINA_WIRE` lines around the Sync, and the walk-outside
observation per channel. Tag each firmware fact `verified-by-bench` with
`ver`/`vid`.
