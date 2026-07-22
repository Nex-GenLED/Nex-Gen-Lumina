# Design Studio — Architecture Audit & Build Blueprint (2026-07)

**Status:** blueprint for a multi-slice build. Slice 0 (per-pixel write-path hardening)
implemented alongside this doc; Slices 1–5 pending.
**Firmware impact:** none — WLED JSON API only (segment `i` individual-LED control).
Bench-verified on `192.168.1.250` (WLED 0.15.4, ESP32, `maxseg: 32`).

Two halves in one build: (1) a **per-pixel editor** (any pixel on any channel individually
set/painted), and (2) a **semantic pixel map** per channel — ordered feature ranges with
types (corner / run / peak-up / peak / peak-down …). The map is long-term moat infrastructure:
consumers are smart presets, Lumina AI design generation, Neighborhood Sync per-home scaling,
and effect placement.

Evidence is `file:line`. Findings are marked **[CONFIRMED]** (read from code / measured on
hardware) vs **[DECISION]** (requires design choice).

---

## 1. Reusable surfaces — the feature is ~70% modeled already

### 1a. Roofline trace / multi-segment rebuild — REUSE DIRECTLY [CONFIRMED]
| Piece | What it is | Evidence |
|---|---|---|
| `RooflineEditor` | Interactive canvas: tap to place points, drag handles, hit-test segments; normalized 0–1 offsets on a house photo; imperative API (`startNewSegment`, `selectSegment`, `reorderSegment`…) | `lib/widgets/roofline_editor.dart:15` |
| `RooflineEditorScreen` | Full "Trace Roofline" page: toolbar, reorderable segment panel, Auto-Detect, Save. Route `/settings/roofline-editor` | `lib/features/site/roofline_editor_screen.dart:16` |
| `RooflineSegment` | **The semantic-map backbone already:** `pixelCount`, `startPixel`/`endPixel`, `channelIndex`, `SegmentType {run,corner,peak,column,connector}`, **`architecturalRole {peak,eave,valley,ridge,corner,fascia,soffit,gutter,column,archway}`**, and **`anchorPixels`/`AnchorPoint` (local LED index + type)** with `globalAnchorPixels` helpers | `lib/models/roofline_segment.dart:27,470-603` |
| `RooflineConfiguration` | Aggregates segments + `totalPixelCount`, `segmentsForChannel()`, `allPixelsInChannelOrder()`, `validateAgainstDevice()` | `lib/models/roofline_configuration.dart:12-381` |

The example map (`1=Corner, 2–24=Run, 25=Corner, 26–40=Peak-Up…`) is exactly
`RooflineSegment.{startPixel,endPixel,type,architecturalRole}`. **Gap:** `RooflineEditor` edits
endpoint handles, not per-LED state — per-pixel editing is an LED-index selection/paint layer on
top of the existing normalized-path geometry.

### 1b. Home-preview rendering — two reusable renderers [CONFIRMED]
- **`RooflineLightPainter`** (`lib/widgets/roofline_light_painter.dart:43`) — photo-overlay renderer,
  already multi-segment/per-channel/index-colored via `SegmentPathData` + `overrideColor` +
  `_getColorForLed`. Renders *virtual* LEDs by path length; needs a real-LED-index mode for true
  per-pixel display. **Recommended base for the editor** (users reason about their house).
- **`PixelRenderer`** (`lib/features/ai/pixel_renderer.dart:20`) — true per-pixel engine with
  abstract `computePixelPositions`; currently strip layout.

### 1c. Controller / channel model [CONFIRMED]
- **Authoritative per-channel pixel count = `WledLedBus.len`** (`lib/features/wled/wled_repository.dart:85`),
  surfaced as `DeviceChannel(start,stop)` via `deviceChannelsProvider`
  (`lib/features/wled/zone_providers.dart:83-103`). Read live from `/json/cfg`.
- **`ControllerModel` stores no counts** (`lib/models/controller_model.dart:8-128`).
- Counts in `RooflineConfiguration` are installer-entered, not device-derived (hence
  `validateAgainstDevice()`, `roofline_configuration.dart:236`) — **BUG-SYNC-1 root**. Source
  pixel-map counts from `WledLedBus.len`, validate segment sums against it.

### 1d. Installer mode [CONFIRMED]
- Auth: `mintStaffToken` mints a custom token with `role`+`dealerCode` claims;
  `installerModeActiveProvider` (`lib/features/installer/installer_providers.dart:125-243`).
- Reusable gating: `effectiveUserUidProvider` (`lib/features/installer/installer_access_providers.dart:39-49`).
- **Insert a "Map Roofline" step after `hardwareConfig`** in `InstallerWizardStep`
  (`installer_providers.dart:439`) — that's where per-channel `bus.len` counts are set.
- Handoff **migration** (`installer_setup_wizard.dart:567-610`) must carry any install-time map docs.

### 1e. Current Design Studio state [CONFIRMED]
`AIDesignStudioScreen` (`lib/features/design/screens/ai_design_studio_screen.dart:18`) is **live
and wired into all three shell branches**; it is an **AI-first natural-language** surface. Save
works; **only "Apply to Lights" is disabled** (`onPressed: null`, #86) pending payload
verification. `docs/DESIGN_STUDIO_REQUIREMENTS.md` specifies the **manual per-pixel editor
(range/every-Nth/anchor selection, undo/redo, Strip/Roofline/Grid views) that does not exist
yet** — that unbuilt manual half is this project, sitting beside `AIDesignStudioScreen` under the
same routes, consuming `RooflineConfiguration` + `LedColorGroup`/`CustomDesign`
(`lib/features/design/design_models.dart:391`).

---

## 2. WLED per-pixel write path — the spine

### 2a. Segment `i` support [CONFIRMED]
- No typed per-pixel method on `WledRepository` — interface is whole-segment
  (`lib/features/wled/wled_repository.dart:5-78`).
- `i` already rides `applyJson` untyped. The one legacy builder,
  `_generateStaticPayload` (`lib/features/design/services/pattern_composer.dart:682-712`), emitted
  a **flat** `i` array (`[idx,r,g,b,…]`), **RGB-only (dropped W)**.
- **Latent bug (fixed in Slice 0):** both normalizers validated only *nested-list* `i` elements,
  so the flat form passed **unvalidated** (`wled_payload_utils.dart:439-447`,
  `rgbw_validation.dart:74-82`). Worse, WLED interprets a flat `[idx,r,g,b]` run as *four
  indices*, so the flat form never rendered correctly on device. **Canonical form is nested**:
  `[idx,[r,g,b,w]]` (single) and `[start,stop,[r,g,b,w]]` (range, stop **exclusive**).

### 2b. Payload ceiling + chunking [CONFIRMED — bench-measured 2026-07 on 192.168.1.250]
- The per-pixel POST must use **`HttpClient` + explicit `Content-Length`** (mirror `_postConfig`
  `wled_service.dart:404-446` / `savePreset:774-790`), **not** `http.post` — WLED 0.15.x
  drops/rejects chunked transfer-encoding.
- **Measured unchunked body ceiling: ~337 distinct single-pixel entries ≈ 6.0 KB.** First failure
  at ~346 entries (~6.2 KB). **Failure mode is HTTP 400 `{"error":9}`** (WLED JSON-buffer limit),
  **not 413** — the chunk retry classifier must treat **400 and 413** as "payload too large."
- **Chosen chunk constant `kDefaultPixelChunkSize = 224` LEDs** (~34 % headroom under 337; worst
  case all-distinct ≈ 4 KB). Range-compressed chunks are far smaller. Chunk by LED-coverage;
  oversized single ranges are sliced into ≤chunk sub-ranges (kept as ranges, not exploded to
  singles).
- **Range-compression** collapses mostly-solid designs to a few `[start,stop,[rgbw]]` entries.
- Chunking = **sequential** `i` POSTs (WLED merges successive `i` writes into segment state):
  ordered await, stop-on-failure, **retry-once-on-400/413 with a halved chunk size**.

### 2c. Persistence (Slice 3+, out of Slice-0 scope) [CONFIRMED]
- Presets save via `savePreset` (unchunked path, `wled_service.dart:722-807`); reserved ranges in
  `lib/features/wled/wled_preset_ranges.dart` — **`42-99` and `201-250` are free**; `42-99` is the
  natural home for per-pixel design presets + an allocator.
- Prefer **Firestore `CustomDesign` as source of truth**, writing a WLED preset only for
  "boot/active look" — controller LittleFS (~1 MB) is shared and finite.

### 2d. The honest boundary — segment-granular animation [CONFIRMED]
WLED motion effects run **per-segment, not per-pixel**. A painted `i` array is a **static** frame
(and needs `fx:0` to persist — a running effect repaints over it; see
`memory/project_blocks_boundary_blend_fix`). Animated use of the map = **define segments at
feature boundaries** (each peak its own segment running an effect while runs hold color). The
ceiling is **`maxseg = 32` on this ESP32** (bench `/json/info`) — that bounds how many features can
animate simultaneously and must shape the Slice-4 UX promise. Do not promise per-pixel animation.

### 2e. Relay path [CONFIRMED]
- `CloudRelayRepository.applyJson` (`cloud_relay_repository.dart:363`) writes to
  `/users/{uid}/commands/{id}` with **`payload: jsonEncode(payload)` — a JSON string**
  (`lib/models/remote_command.dart:94-107`), dodging Firestore's nested-array rejection.
  Firestore doc cap 1 MiB; per-chunk payloads are KB. Relay timeout 45 s.
- **Chunk ordering holds**: per-pixel chunks post as **sequential command docs**, each awaited to
  completion before the next is written (`_executeBool` → `_executeCommand` → `_waitForCompletion`),
  and the bridge executes docs in order. No reordering window.
- **`uploadLedMapJson` is unsupported remotely** (`cloud_relay_repository.dart:381-385`) — the
  per-pixel path uses `i`-array writes, **never ledmap**.

---

## 3. Semantic map data model (Slice 1) [DECISION]

- **Evolve `RooflineConfiguration` to per-controller + installer-writable** rather than a parallel
  `pixelMap` model (memory convention: no parallel models). It already carries
  `SegmentType`/`architecturalRole`/`anchorPixels`/`channelIndex`.
- Today it lives at `/users/{uid}/roofline_config/config`, **owner-write only**
  (`firestore.rules:282-287`) — installers cannot write it. A per-controller map at
  `/users/{uid}/controllers/{controllerId}/pixelMap` needs a **new explicit rules block**
  (subcollections are not rule-inherited) modeled on the **controllers** block
  (`firestore.rules:196-215`, `create/update: if isOwner || request.auth != null`) so installers
  write and customers edit.
- **Compact AI serialization already exists**: `LuminaBrain._buildRooflineContext`
  (`lib/lumina_ai/lumina_brain.dart:1269-1341`) serializes the map as a compact feature list
  (name/role/range/anchors), respecting the **1024-token output cap + truncation net**
  (`lumina_ai_service.dart:730`). Never inject per-pixel arrays.

---

## 4. Capture workflow (Slice 2) [DECISION]
- **Pixel-walk via single-pixel `i` spotlight** (`{"seg":{"i":[idx,[255,255,255,0]]}}`) or slow
  chase; installer taps boundaries. Interaction cost for a 600-px home: **mark-boundaries-only**
  (~10–20 taps for feature edges) — a per-pixel walk (600 taps) is untenable.
- Shortcuts: symmetric-peak inference (mark apex, infer up/down), copy-across-channels.
- Customer refine: adjust a boundary ±N with live `i`-spotlight feedback.

---

## 5. Consumer sequencing [DECISION]
1. **Smart presets (corner/peak accents) — SHIP FIRST.** Low effort, immediate visible payoff,
   **no AI round-trip**: turns "light the peaks" into a range-targeted `seg` payload riding the
   existing `applyChannelFilter`→`applyJson` chokepoint (`wled_dashboard_page.dart:1179-1287`);
   mirror `WhitePreset` (`lib/features/whites/white_preset_models.dart:35-49`).
2. Lumina AI map-aware generation (injection point + serializer already exist).
3. Neighborhood Sync scaling (BUG-SYNC-1: `member.ledCount` defaults to 300, hand-typed —
   `neighborhood_models.dart:304`, `member_position_list.dart:735`).
4. Segment-at-boundary animated presets (bounded by `maxseg=32`).

---

## 6. Staged build plan
- **Slice 0 — per-pixel `i` write-path hardening (this commit).** Canonical nested `i`; typed
  `applyPerPixel` (capability interface `PerPixelWriter`) with range-compression + sequential
  chunking (224-LED, 400/413 retry) over the unchunked `HttpClient` transport; validator tightening
  (flat→nested conversion so nothing unvalidated passes); channel-filter bypass; relay chunk
  ordering. No UI, no data-model/rules changes.
- **Slice 1 — data model.** Per-controller map + rules block; counts seeded from `WledLedBus.len`;
  versioning/staleness vs live channel counts.
- **Slice 2 — capture flow (installer).** "Map Roofline" step after `hardwareConfig`; boundary-mark
  pixel-walk; migration-carry.
- **Slice 3 — first consumer: smart presets.**
- **Slice 4 — editor / painting.** Real-LED-index `RooflineLightPainter`; manual selection/paint +
  undo/redo per `DESIGN_STUDIO_REQUIREMENTS.md`.
- **Slice 5 — customer refine.**

---

## Appendix A — Slice-0 bench log (192.168.1.250, 2026-07-02)
```
INFO: ver=0.15.4  ledCount=153  maxseg=32   (ESP32_Ethernet)
RANGE-FORM  [0,10,[0,0,255,0]]  -> 200 {"success":true}   (nested range accepted, stop exclusive per WLED deserializeState)
N=  64  bytes=1153  200
N= 128  bytes=2309  200
N= 256  bytes=4611  200
N= 400  bytes=7193  400 {"error":9}     <- JSON buffer limit (NOT 413)
bisect 337 bytes=6075 200 / 346 bytes=6230 400
CEILING: ~337 single-pixel entries (~6.0 KB).  Chunk constant set to 224 LEDs (~34% headroom).
MAX_NUM_SEGMENTS (maxseg) = 32  -> animation ceiling for Slice-4+.
```
Note: WLED stock `/json/state` has **no per-pixel readback**, so visual confirmation of range
stop-exclusivity and exact colors is **deferred to Slice-4** (has UI). Slice-0 verifies wire
acceptance + body ceiling + firmware constants; range semantics follow WLED source
(`deserializeState`: `for (i=start; i<stop; i++)`).
