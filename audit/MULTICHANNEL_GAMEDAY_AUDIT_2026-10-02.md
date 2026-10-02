# Game Day on a multi-channel system — why the channels do not match (audit)

**Filed:** 2026-10-02 · **Branch:** `fix/115-multichannel-and-design-card` off release head
`a35e30e` (build 112) · **Read-only:** no controller, bridge, Firestore, config or functions writes.
**Evidence tags:** `verified-by-source` (WLED **v0.15.1** `FX.cpp` / `FX_fcn.cpp`, fetched from the
tag; line numbers are that file's), `verified-by-test` (the contract test in this branch executes
the app builders), `verified-by-bench` (prior bench notes, cited), `assumption` (stated as such).
**Tracker:** #77 (renderer, OPEN), **#151** (server payload gap, new), **#154** (lease fallback,
new), **#155** (pal disagreement, new).

## 0. Summary

1. **Every app path sends the same look to every participating segment** — one template copied per
   channel id, with `pal`, `grp`, `spc`, `bri`, `frz:false` and three colour slots stated
   (`verified-by-test`, `test/features/game_day/multichannel_seg_array_contract_test.dart`). The
   server start payload sends the same `fx/sx/ix/col` per segment but **states none of `pal`, `grp`,
   `spc`, `frz`, segment `bri`, `col[2]`** — those stay whatever each segment last had
   (`verified-by-source`, §1.1, §4 server note).
2. **With identical settings, WLED still renders one effect instance per segment, each over its
   own length and from its own origin.** The Game Day defaults — Running Dual (52) and Chase (28) —
   are *length-sensitive*: dot position, dot size, wave phase and the palette gradient all scale with
   each segment's pixel count, so 162 / 128 / 100 px channels show three different-looking runs of
   the same effect. Static Blocks shows thirds *per channel*. Only Solid, Breathe, Fade and Strobe
   are length-free. (§2, `verified-by-source`.) This is tracker **#77**.
3. **There is no in-device way to make three segments run as one** short of a single segment
   spanning the buses. WLED "sync groups" are inter-device UDP; segment `set` is UI-only (§2.8).
4. **Recommendation (§4):** short term (d) — make the Game Day looks length-independent and close
   the server's inherited-field gap (**#151**, server note below, one-line builder change); medium
   term (a) — a single spanning segment when the participating buses are contiguous, which is the
   geometry-layer work #77 already points at. (b) normalisation cannot make a chase on 162 px match
   one on 100 px; (c) does not exist in WLED.
5. **Two app-side gaps found on the way, not fixed here:** the dated-night **lease** fallback lights
   channel 1 only (**#154**, file overlaps build 114), and the two foreground Game Day builders
   disagree on `pal` for palette-reading effects (**#155**, no visible effect for the default fx 52).

## 1. Every path that applies a Game Day look, and the segment array it sends

Device in every row: three buses 162 / 128 / 100 px = segments 0–162, 162–290, 290–390, channel
ids 0/1/2. Colours `P = [255,0,0,0]`, `S = [0,0,255,0]`, `K = [0,0,0,0]`. "Wire" = after the shared
chokepoint (`normalizeWledPayload` → `expandForParticipation`), which both repositories
(`WledService.applyJson` [wled_service.dart:1002](../lib/features/wled/wled_service.dart#L1002),
`CloudRelayRepository.applyJson` [:399](../lib/features/wled/cloud_relay_repository.dart#L399)) run.

### 1.1 Server start job and its re-asserts — `functions/src/planGameDayFires.ts` + `gameDayPlanning.ts`

Builder: `buildFullPartitionSegArray`
([gameDayPlanning.ts:171-194](../functions/src/gameDayPlanning.ts#L171)) when the device channel
list is known, else `buildParticipatingSegArray` ([:124-139](../functions/src/gameDayPlanning.ts#L124)).
Assembled at [planGameDayFires.ts:259-299](../functions/src/planGameDayFires.ts#L259). Run read-only
against the compiled module in the main checkout (`functions/lib/gameDayPlanning.js`, 2026-10-02):

```json
{"on":true,"bri":200,"seg":[
  {"id":0,"on":true,"fx":52,"sx":160,"ix":128,"col":[[255,0,0,0],[0,0,255,0]]},
  {"id":1,"on":true,"fx":52,"sx":160,"ix":128,"col":[[255,0,0,0],[0,0,255,0]]},
  {"id":2,"on":true,"fx":52,"sx":160,"ix":128,"col":[[255,0,0,0],[0,0,255,0]]}]}
```

With channel 1 excluded: `{"id":1,"on":false}` and nothing else (#67). The payload goes through the
relay to the bridge, which POSTs the body **verbatim** to `/json/state`
([esp32-bridge/src/main.cpp:820-823](../esp32-bridge/src/main.cpp#L820)) — nothing normalises it.

| Field | Server | Every app path | Effect of inheriting it |
|---|---|---|---|
| `fx sx ix` | stated | stated | — |
| `col` | **2 slots** | 3 slots (slot 3 padded black) | slot 3 keeps the previous look's colour on *that* segment. **The default fx 52 reads it:** `running_base(dual)` colours its reverse wave with `color_from_palette(i, …, mcol 2)`, which at `pal 0` returns `SEGCOLOR(2)` = `col[2]` ([FX_fcn.cpp:1173](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L1173)). A channel whose slot 3 was last white (a Blocks design) runs a white reverse wave; its neighbour, last black, runs none — **visibly different channels from an identical server payload** |
| `pal` | **inherited** | stated (0 / 5 / 4 by policy) | a segment left at `pal 5` by a Blocks design and one at `pal 0` render Running Dual's gradient from different sources — **visibly different channels** |
| `grp` / `spc` | **inherited** | stated (`1` / `0` or the design's) | a channel left at `grp 3` by a Stripe or Alternating design renders every effect at 3-px virtual pixels — **visibly different** |
| `frz` | **inherited** | `false` | a frozen segment **ignores the whole fire** and keeps its old look (`verified-by-bench`, memory `project_frozen_segment_swallows_writes`; `.173` was found with `seg 0 frz:true` on 09-24) |
| segment `bri` | **inherited** | `255` (`kSegDefaultBri`, +110) | a dimmer channel |
| `c1 c2 c3 o1 o2 o3` | inherited | stated for effects that read them (`kWledEffectOptionKeys`) | fx 52 / 28 / 0 / 2 / 12 read none — no effect for the Game Day set |
| `rev mi of start stop` | not sent | not sent (#76) | provisioning's; a segment-level `rev` or `mi` set in the WLED UI reverses or mirrors that channel's effect forever — neither side corrects it (§2.6) |

End fire: `{ps:1}` or `{ps:2}` (`baseRestorePayload`,
[gameDayPlanning.ts:544-575](../functions/src/gameDayPlanning.ts#L544)); re-asserts are a job
`type` the schema allows ([fireJobs.ts:135](../functions/src/fireJobs.ts#L135)) that nothing in the
planner writes today — the start is asserted once.

### 1.2 App engine — foreground `GameDayAutopilotService` and Light-it-Up-Now

- **Light it Up Now / Path 1 activate** — `applyGameDayConfigToDevice`
  ([game_day_apply.dart:61-110](../lib/features/game_day/game_day_apply.dart#L61)): one template
  `{grp:1, spc:0, fx, sx, ix, pal:0, col:[P,S]}` → `applyChannelFilter` over the device census →
  wire (`verified-by-test`):

  ```
  seg: [ {id:0, grp:1, spc:0, fx:52, sx:160, ix:128, pal:0, col:[P,S,K], on:true, bri:255, frz:false},
         {id:1, …identical…}, {id:2, …identical…} ]
  ```
- **Engine (`_buildWledPayload`,
  [game_day_autopilot_service.dart:1176-1215](../lib/features/autopilot/game_day_autopilot_service.dart#L1176))**:
  single id-less seg `{fx, sx, ix, pal: setColorsPaletteFor(fx), col}` → chokepoint **Rule 7**
  fans it per participating channel ([wled_payload_utils.dart:333-360](../lib/features/wled/wled_payload_utils.dart#L333)).
  Identical per channel. Note the `pal` disagreement with Light-it-Up-Now (**#155**): `0` vs
  `setColorsPaletteFor` — equal (0) for every colour-reading effect including the default 52.
- **Background worker** ([game_day_autopilot_background_worker.dart:591-616](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L591))
  + `TeamDesignCatalog` ([team_design_catalog.dart:72-180](../lib/features/autopilot/team_design_catalog.dart#L72)):
  all six designs fan identically (`verified-by-test`): Colors fx 52 · Alt fx 0 · Chase fx 28 ·
  Breathe fx 2 · Fade fx 12 · Stripe fx 0 `grp 3`.
- **Saved design** (`saved_design_payload`): forwarded verbatim, already per-channel from the picker
  (Rule 4 pass-through) — per-channel by design.

### 1.3 Lease (a dated Game Day night) — `CalendarEntryLeaseManager`

`_synthesizeWledPayload` ([calendar_entry_lease_manager.dart:1134-1193](../lib/features/schedule/calendar_entry_lease_manager.dart#L1134)):
a carried +112 payload is used as-is (per-channel from the picker); the **fallback is ONE id-less
Solid segment** `{fx:0, sx:128, ix:128, col:[C]}` with root `on/bri/ib`. It is never
channel-filtered (no `applyChannelFilter`/`scopePatternPayload` in the file), and `savePreset`'s
`ensurePsaveClearsFreeze` only adds `{id, frz:false}` markers when the caller supplied **no**
segments ([wled_payload_utils.dart:508-525](../lib/features/wled/wled_payload_utils.dart#L508)) —
it does not fan a single segment out. WLED applies an id-less seg to `mainseg`, and the `psave`
captures channels 2 and 3 **as they were at arming** ("ambient capture", memory
`project_lease_path_gameday_1004_prep_2026_10_01`). `verified-by-test`. **On a three-bus house a
lease-fired Game Day night is channel 1 in the team colour and the other two on whatever came
before.** Filed **#154**. The 10-04 lease already armed on the home controller (preset 39) has this
shape.

### 1.4 Celebrations

- **Foreground** (`WledCelebrationDelivery.play`,
  [foreground_celebration_providers.dart:46-56](../lib/features/sports_alerts/services/foreground_celebration_providers.dart#L46)):
  each stage of `AlertTriggerService.buildAnimationSteps`
  ([alert_trigger_service.dart:384-520](../lib/features/sports_alerts/services/alert_trigger_service.dart#L384))
  → `applyChannelFilter` over all device channels → identical per channel (`verified-by-test`, every
  event type; turnover has no stages). Stages use fx 2 / 3 / 13 / 15 / 23 / 28 with
  `pal:_kTeamColorPalette` — see §2 for which of those drift per segment. **Revert** replays the
  captured `seg` array verbatim (`{ps}` when a preset was active), so it restores whatever
  per-segment state was captured, geometry included.
- **Background** (`buildCelebrationPayloadForTest`, [:620-660](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L620)):
  one id-less seg → `expandForChannels` → identical per channel.

### 1.5 Base-layer restore

- Server: `{ps:1|2}` — the preset's own per-segment state loads; per channel it is whatever the
  ladder psave captured.
- App ladder (`_fullStripOnSegments`,
  [schedule_sync.dart:2168-2200](../lib/features/schedule/schedule_sync.dart#L2168)): `{id, on}` per
  live segment, look fields deliberately not written; the psave captures the live look — the +114
  branch replaces this with a named base look (`base_look.dart`).

### 1.6 Neighborhood Sync

Engine ([neighborhood_sync_engine.dart:754-780](../lib/features/neighborhood/neighborhood_sync_engine.dart#L754)):
one id-less seg `{fx, sx, ix, pal, grp, spc, col×3}` → Rule 7 → identical per channel
(`verified-by-test`). Server fan-out: `partitionBroadcastPayload`
([applySyncPattern.ts:586-640](../functions/src/applySyncPattern.ts#L586)) copies the single seg per
device channel — it carries `pal/grp/spc` only because the app put them in the broadcast; the same
inherited-field class as §1.1 applies to anything it does not carry.

### 1.7 Explore Patterns (for §3)

`buildSelectorPayload` ([selector_payload.dart:140-170](../lib/features/wled/selector_payload.dart#L140))
→ `applyChannelFilter` over the effective channels
([colorway_effect_selector.dart:917](../lib/features/wled/colorway_effect_selector.dart#L917)) → wire.
Static Blocks (`verified-by-test`):

```
seg: [ {id:0, fx:83, sx:128, ix:128, pal:5, grp:1, spc:0, col:[R,W,B], on:true, bri:255, frz:false}, ×3 ]
```

## 2. Why identical settings look different on different buses (WLED 0.15.1)

**The model.** `service()` walks the segments in order every frame with one shared clock
(`strip.now`) and runs the effect function **once per segment** with `SEGLEN = seg.virtualLength()`
and that segment's own runtime (`step/aux0/aux1/call`), which `resetIfRequired()` zeroes when the
segment's mode changes ([FX_fcn.cpp:1363-1420](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L1363),
[:186-192](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L186)). A frozen segment
is skipped entirely ([:1381](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L1381)).
`virtualLength = ceil(length / (grp+spc))`, halved under `mi`
([:674-702](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L674)). Positional
palette mapping: `paletteIndex = i·255 / (virtualLength−1)`
([:1169-1182](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L1169)). So: effects
that read `strip.now` only are **in phase** across segments; effects that read `i` restart their
pattern at **every segment origin**; effects that read `SEGLEN` **scale** with each segment's length.

### 2.1 Length-sensitivity of the effects Game Day and celebrations use (`verified-by-source`)

| fx | Name | Source | Reads | Across 162 / 128 / 100 px |
|---|---|---|---|---|
| 0 | Solid | — | `SEGCOLOR(0)` | identical |
| 83 | Solid Pattern (Blocks, `pal 5`) | [FX.cpp:2849](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L2849) | `i`, positional palette, `1+sx` lit / `1+ix` unlit | thirds **per segment** (54/43/33 px): R-W-B, R-W-B, R-W-B — three runs, not one; the lit band is `1+sx` *virtual* px (129 at sx 128), so a 162-px channel at `grp 1` shows `col[1]` from px 129 (`verified-by-bench` 09-22, **#153**) |
| 84 | Solid Pattern Tri (Alternating) | [:2870](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L2870) | `i` | bands restart at each segment origin — a seam unless each length is a multiple of 3·grp |
| 2 | Breathe | [:331](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L331) | `strip.now` only | **in phase, identical** (palette positional, but `pal 0` ⇒ `SEGCOLOR(0)`) |
| 12 | Fade | [:353](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L353) | `strip.now` only | **identical** |
| 23 | Strobe | `blink()` [:88](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L88) | `strip.now` | **identical** |
| 3 | Wipe | `color_wipe()` [:157](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L157) | `strip.now`, `SEGLEN` | wipes its whole segment per cycle: same *fraction* at the same instant, different px/s |
| 13 | Theater | `running(theatre)` [:454](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L454) | `i % width`, `strip.now` | in phase, pattern restarts at each origin (seam) |
| 15 | Running | `running()` [:454](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L454) | `i`, `strip.now`, positional palette when `pal≠0` | in phase, seam at origin; gradient stretched per segment |
| **28** | **Chase** (Game Day catalog, celebrations) | `chase()` [:814-835](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L814) | `a = (counter·SEGLEN)>>16`, `size = 1 + (ix·SEGLEN)>>10`, positional palette background | **dot position, dot size and speed (px/s) all scale with the segment**: at ix 180 the dot is 29 / 23 / 18 px on the three channels and crosses each in the same period — three chases that never line up |
| **52** | **Running Dual** (the Game Day default, `effect_id 52`) | `running_base(dual)` [:503-531](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX.cpp#L503) | forward wave `i·x_scale − counter`; **reverse wave `(SEGLEN−1−i)·x_scale − counter`**; positional palette `mcol 0` and `mcol 2` | forward wave: in phase, seam at each origin; **reverse wave anchored to each segment's END**, so its phase differs per length; at `pal 0` the forward wave is `col[0]` and the reverse wave `col[2]` (black on every app path, inherited on the server path — §1.1); at `pal 5` both are a positional gradient stretched per segment. Three different interference patterns |
| 17/20/87 | Twinkle / Sparkle / Glitter | random | `random8/16` | uncorrelated by nature |

**What this means for the reported case.** The reporter's server fire carried fx 52 (the default).
Even with every field identical, Running Dual's reverse wave and gradient are computed *per segment
length*, so a 162-px channel and a 100-px channel cannot show the same picture. That matches "the
channels appear to do different things" without any parameter differing — and it is the renderer-level
#77 class, not a payload bug. The payload gaps in §1.1 are a second, independent way to get there.

### 2.2 Per-segment fields that change the picture with identical fx/sx/ix/col

- **`rev` / `mi`** ([FX_fcn.cpp setPixelColor](https://github.com/Aircoookie/WLED/blob/v0.15.1/wled00/FX_fcn.cpp#L705)):
  a segment-level `rev:true` runs the chase the other way on that channel; `mi` halves its virtual
  length and mirrors. Install geometry (#76): no app or server path writes or clears them. The bench
  home controller has channel 1 reversed (`verified-by-bench`, design_solid_layout_live_test note) —
  on it, Chase/Running Dual run *towards* each other at the seam by design.
- **`grp` / `spc`** — see §1.1 table. Inherited on the server path only.
- **`pal`** — inherited on the server path only. Running Dual's gradient source (`pal 0` → `col`,
  `pal 5` → palette built from `col`, `pal 4` → gradient of `col`) differs per channel if the segments
  were last left in different palettes.
- **`frz`** — a frozen channel ignores the fire (server path only; the app clears it).
- **`bri` (segment)** — dimmer channel (server path only).
- **`of`** — shifts the pattern origin within the segment; inherited everywhere (#76 keeps it).

### 2.3 Sync groups, master segment, a spanning segment

- **WLED "sync groups" (`udpn.sgrp/rgrp`) synchronise *devices* over UDP**, not segments within a
  device. Segment `set` (0–3) is a UI selection group only. **There is no in-device segment
  synchronisation.** `verified-by-source` (no cross-segment state in `service()`).
- **One segment spanning the participating buses** (`0–390`) is the only in-device construction
  that renders one effect across the house: one `SEGLEN`, one origin, one gradient. Buses are
  contiguous in pixel index, so a spanning segment is legal. Cost: per-channel exclusion (`{id, on:false}`)
  is lost for channels *inside* the span (WLED segments cannot overlap), the channel model (`seg N ==
  bus N`, `applyChannelFilter`, ladder presets, `seglc`) stops holding, and segment bounds are
  provisioning's (#76/#82) and do not survive a reboot (memory `project_reboot_segment_collapse`).
- **Matched intervals** (same `sx/ix`) do not help the length-scaled effects (28, 52, 3): the
  period matches, the geometry does not.

## 3. Explore Patterns apply vs the server apply — same design, same controller

| | Explore (§1.7) | Server start (§1.1) |
|---|---|---|
| Builder | `buildSelectorPayload` → `applyChannelFilter` → chokepoint | `buildFullPartitionSegArray` |
| Segments | full partition, one template per id | full partition, one template per id |
| Stated | `fx sx ix pal grp spc col×3 on bri frz:false` (+ `c1..o3` where the effect reads them) | `fx sx ix col×2 on` |
| Palette for fx 52 | `paletteForEffect(52)` = **5** (Colors Only) | inherited |
| Palette for fx 52 via Light-it-Up-Now / engine | **0** | — |

So for the *same* fx-52 design: Explore sends `pal 5`, the app's Game Day paths send `pal 0`, the
server sends nothing. On a controller whose segments were last left in different palettes, the server
fire is the only one that can render **differently per channel**; the two app paths agree with
themselves but not with each other (`pal 5` builds a 16-entry palette from `col` and maps it
positionally — a smooth P→S gradient along each channel; `pal 0` reads `SEGCOLOR` directly). Both
are "team colours", but they are not the same picture. **#155**.

## 4. Options

| | Option | Scope | Risk | Server / app |
|---|---|---|---|---|
| (a) | **One segment spanning the participating buses when contiguous** | provisioning + channel model + ladder presets + `applyChannelFilter` + server partition builder; a geometry-layer design (`docs/SYNC_GEOMETRY_LAYER.md`, #77) | high: reboot collapse, exclusion semantics, every `seg N == bus N` assumption, bench re-provisioning on every install | both, as one design; not a window fix |
| (b) | **Per-segment parameter normalisation** (scale `sx/ix` by pixel count) | a shared pure helper | low risk, **low value**: Chase's dot *position* is a fraction of `SEGLEN` whatever `sx` is; Running Dual's reverse wave is anchored to the segment end; only `ix`-sized dots could be equalised | shared builder (TS + Dart) |
| (c) | **WLED sync groups / master segment** | — | **does not exist in-device** (§2.3) | — |
| (d) | **Length-independent looks for Game Day** — Solid / Breathe / Fade / Strobe (and Alternating for a seam-tolerant stripe); keep Chase and Running Dual as explicit "per-channel motion" picks | `TeamDesignCatalog` default order and `GameDayAutopilotConfig.effectId` default (52 → 12 Fade or 2 Breathe), picker copy | low; a product decision on the default look | **app**, and the server inherits it through `effect_id` with no server change |
| (d′) | **Close the server's inherited-field gap** so a server fire states what every app fire states | one builder in `gameDayPlanning.ts` | low; same shape the app already sends; needs the Game Day window | **server** (note below) |

**Recommendation.** Ship **(d′)** in the next Game Day functions window (it is the only change that
makes a server fire *deterministic* per channel) and take **(d)** as the product decision for the
default look — Fade (12) or Breathe (2) read identically on every channel and are already in the
catalog. Keep **(a)** as the #77 design-session answer; do not build (b) or (c). A **shared payload
builder** is feasible for the *field set* (the Dart side is `applyChannelFilter` + `normalizeWledPayload`
+ `completeEffectSegment`; the TS side is `buildFullPartitionSegArray`), and the contract test in
this branch pins the Dart side so a TS golden can be written against the same arrays — but the
renderer-level difference (§2) is not a payload property and no builder removes it.

### 4.1 Server note — the exact change for the Game Day window (NOT applied here)

`functions/src/gameDayPlanning.ts`, both builders. Replace the participating-segment literal with:

```ts
{
  id: ch,
  on: true,
  fx: args.effectId,
  sx: args.speed,
  ix: args.intensity,
  // What every app fire states; the fleet's wire defaults (lib/shared/wled_segment_defaults.dart).
  pal: args.palette,          // 0 for colour-reading effects (setColorsPaletteFor); 5 only for palette-reading ones
  grp: 1,
  spc: 0,
  bri: 255,                   // segment opacity — never inherit a dimmed channel
  frz: false,                 // a frozen segment ignores the fire otherwise
  col: [...args.colorSlots, [0, 0, 0, 0]].slice(0, 3),   // three slots, always
}
```

with `palette` resolved in `planGameDayFires.ts` next to `look` (`effect_id` → 0 unless the effect is
in the palette-reading set; port `WledEffectsCatalog.overridesUserColors` for the catalog's six ids,
all 0). Exclusion stays `{id, on:false}`; add `frz:false` there too so a frozen excluded channel still
goes dark. `assertPayloadIsFireSafe` already permits every key above. Add the three-bus golden from
this branch's contract test to `functions/test/unit/gameDayBenchRegression.test.js` so the TS and
Dart arrays are compared field for field. Payload size stays well under `MAX_FIRE_PAYLOAD_BYTES`
(three segments ≈ 420 bytes).

## 5. Visual bench test plan (not run)

**Rig:** `.173` (spare, unregistered, 4 × 30 px RGBW, 4 segments) for anything that writes;
`.150` **view-only** (it is the home controller with flash damage: no `psave`, no cfg). The 3-bus
geometry (162/128/100) exists only on `.150`; on `.173` use the 4 × 30 segments and *re-bound two of
them* to unequal lengths for the length tests — `.173` is cleared for destructive tests. Record with
the websocket liveview (`ws://IP/ws` + `{"lv":true}`, memory `project_bench_rig`) plus a phone video
of the strip; log `/json/state` before and after each step.

| # | What | Buses | Send | "Matching" looks like | Record |
|---|---|---|---|---|---|
| 1 | Length-free control | all four 30-px | Fade fx 12, `sx 90`, `col [P,S,K]`, `pal 0` | all four segments the same colour at every instant; one crossfade | 10 s liveview; frames identical across segments |
| 2 | Same, unequal lengths | seg 0 = 0–45, seg 1 = 45–60, seg 2 = 60–120 (bounds via `applyGeometryJson`, then restore 4×30) | same as 1 | still identical | as 1 |
| 3 | Chase, equal lengths | 4 × 30 | fx 28 `sx 180 ix 180 pal 0` | four dots at the same offset from each segment start, same size (≈6 px) | video; note seam |
| 4 | Chase, unequal lengths | as 2 | same as 3 | dots of **different sizes** (≈9 / 3 / 11 px) crossing each segment in the same period — the §2.1 prediction; "not matching" is the expected result | video + liveview |
| 5 | Running Dual, unequal | as 2 | fx 52 `sx 160 ix 128 pal 0 col [P,S,K]` | reverse wave phase differs per segment; forward wave seams at each origin | video |
| 6 | Blocks | as 2 | fx 83 `pal 5 col [R,W,B] sx 128 ix 128 grp 1` | thirds **per segment** (15/15/15, 5/5/5, 20/20/20) | liveview frame |
| 7 | Inherited-field reproduction (server shape) | as 2; first put seg 1 at `grp 3` and seg 2 at `pal 5`, seg 0 `frz:true` via a per-pixel write | the §1.1 server JSON verbatim (`fx 52`, no pal/grp/frz) | seg 0 does not change; seg 1 at 3-px pixels; seg 2 a gradient — three different channels from an identical payload | `/json/state` readback showing the inherited fields + video |
| 8 | Same with the §4.1 note's fields | as 7 | the app wire shape (`pal 0 grp 1 spc 0 frz false bri 255 col×3`) | all three change; identical up to the length effects of row 5 | readback + video |
| 9 | Spanning segment (option a) | one segment 0–120 | row 5's payload on `id 0` only | one wave across the strip, no seams | video |

Restore `.173` to 4 × 30 (`{"seg":[{"id":0,"start":0,"stop":30},…]}`) and `frz:false` on every
segment when done. Nothing in this plan touches `.150`.
