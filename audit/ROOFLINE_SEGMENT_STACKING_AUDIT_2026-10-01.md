# Roofline segment "stacking" — audit and fix (+113)

**Date:** 2026-10-01 · **Release head audited:** `a35e30e` (`release/store-submission-consolidated`,
build 112) · **Fix branch:** `fix/113-roofline-segments` (worktree `lumina-113-roofline`) ·
**Tracker:** #130 (fixed), #131 (fixed), #132 (fixed), #133 (fixed), #134–#137 (filed).

No customer identifiers appear in this document. The reporter is "the tester" (a residential
account, one controller, two channels, dealer-linked).

## Reported

- Roofline trace works; anchors work; "light individual lights" works.
- Placing anchors creates a NEW segment every time, each stacking on the previous ones, so the
  channel ends up with many overlapping segments instead of one set of sections.
- No way to delete segments: the delete button is grayed out.

## Phase 1 — findings

### 1. What runs when an anchor (mark) is placed

The only customer surface that places corner / peak / "start of a new run" marks is the +110
feature walkthrough, `lib/features/design/roofline_feature_walkthrough.dart` (created in
`a4f7e3b`, package G row 70–72 / 163–164). A mark is local state (`_addMark`, `:217-230`). **Save
channel N** (`_saveChannel`, `:250-297`) compiles the marks with `applyFeatureMarksToChannel`
(`roofline_feature_marking.dart:99-115`) → `compileMarksToChannelSegments`
(`roofline_capture_logic.dart:154-248`), a gap-filled, non-overlapping partition of the channel,
then `replaceChannelSegments` (`roofline_feature_marking.dart:241-260`) REPLACES that channel's
segment list in the aggregate config, and `RooflineConfigEditorNotifier.save()` →
`RooflineConfigService.savePixelMap` (`roofline_config_providers.dart:120-179`) does a full
`set()` per channel doc.

So the walkthrough splits; it never appends. Every corner mark **does** produce two new stored
segments (the corner and the run after it), a peak produces four, because in this data model a
"section" and a "segment" are the same stored entity (`RooflineSegment` inside
`PixelMapChannel.segments`). The Parent Segment spec (`docs/design/roofline_parent_segments.md`
on `design/roofline-parent-segments`, status FINAL, **"No code written"**) intended sections to be
children shown under their channel; that UI was never built (#108). What shipped in +110 is the
partition compiler plus flat-list screens:

| Screen | How a section appears | Where |
|---|---|---|
| Trace Roofline | one outline per section (`_carryForward` slices the traced polyline per section, `roofline_feature_marking.dart:182-203`); a 1-light corner and a 2-light run become 2-point slivers at the same spot | `roofline_editor_screen.dart:57-74` |
| Segment Setup | a flat reorderable list, no channel grouping | `segment_setup_screen.dart:200-221` |
| House-photo card | "N sections mapped" counts them | `house_photo_uploader.dart:469-487` |
| Design Studio | sections are the selection unit (intended) | `manual_design_editor.dart:178-187` |

That is the "new segment every time, stacked on the previous ones" the tester saw.

**A real defect rode along:** `_carryForward` (`roofline_feature_marking.dart:117-152`) keeps an
old section's id when a compiled feature matches its range exactly, while the compiler names new
sections by POSITION (`ch1_seg$i`, `roofline_capture_logic.dart:234`). Adding a corner before an
existing section therefore produced two sections with the same id (worked example: 100 lights,
corner at 50 saved, then corner at 20 → `[20,21)` gets `ch0_seg1` and the old `[50,51)` keeps
`ch0_seg1`). Consequences: `removeSegment` removes both (`roofline_configuration.dart:422-425`),
`mergeTraceIntoRoofline` keys by id and brings a deleted copy back
(`roofline_trace_merge.dart:37-49`), and both lists key rows by the duplicated id.

### 2. The grayed-out delete

The only segment delete in `lib/` with a disabled state is Trace Roofline's toolbar **Delete**
(`roofline_editor_screen.dart:289-296`):
`onTap: _editorKey.currentState?.activeSegmentIndex != null ? _deleteActiveSegment : null`.

- It reads the child editor's state during the parent's build. After `_load()` re-keys the editor
  (`:64-73`), `currentState` is null on the first frame, and selecting a segment
  (`roofline_editor.dart:211-215`, `:280-282`) rebuilds only the editor — so Delete stays grey until
  something unrelated rebuilds the screen (adding a point, opening the panel). Same condition at
  build 109 (`710b8f8` `:231`), so long-standing, worsened by +110's async re-key.
- Sections without a photo outline (installer walk, or walkthrough sections over lights never
  traced) are never shown in Trace (`:62-63`), cannot be selected, and the merge keeps them
  unconditionally — undeletable there.
- No `featureConfirmed`, lock, installer or minimum-count gate exists on any roofline delete.
- Segment Setup's per-card delete is never disabled (`segment_setup_screen.dart:500-506`); the
  walkthrough's per-mark X is disabled only while saving (`:513-517`). Neither offered a
  section-level delete, a merge, an undo, or a start-over.

### 3. Which screen she was in, and customer reachability

A plain customer account (`installation_role` primary/subUser) reaches, with no role, flag or
installer check: the walkthrough (from Design Studio, the Trace banner, the manual editor), Trace
Roofline (System → System & Device Management → My Lights → Roofline Setup → Edit Layout), Segment
Setup (Design Studio → "Roofline setup"), and Refine. The installer Map Roofline step and the
Roofline Setup Wizard are gated on `installerModeActiveProvider` (server-validated staff PIN);
customers see a lock screen. The sequence that matches every word of the report is: Trace Roofline
→ banner "Mark them" → walkthrough (marks, one lit light) → Save → back in Trace, the sections appear
as separate stacked outlines and Delete is grey.

Side findings (filed, not changed): the router lets any signed-in user into `/installer*` and
`InstallerLandingScreen` has no gate (#135); the customer-visible "Setup Wizard" tile leads to a lock
screen (#135); the walkthrough writes `architectural_role`, which flips the Design Studio gate hard
for still-unmarked channels (#136).

### 4. The data (counts only; read-only, admin credential, `.get()` only)

The tester's account: 1 controller, 2 pixelMap channel docs, both last written by the walkthrough
~10 minutes before the read (`created_by` = owner, compile-style ids, every segment
`feature_confirmed`). Channel 0: 1 run, 44 lights = strip. Channel 1: run 42 · corner 1 · run 2 =
45 lights = strip. No overlaps, no duplicate ids, no offset starts. The stack she saw was collapsed
by her later walkthrough save (its save always rebuilds the channel from marks).

Fleet: 41 pixelMap channel docs across all accounts (all `residential`). **0** overlapping ranges,
**0** duplicate ranges, max **4** segments on a channel. Overlap is impossible in stored data because
every write rebases a channel to a gapless run (`splitConfigToPixelMapChannels`,
`pixel_map_channel.dart:288,308-317`). Pre-existing drift unrelated to this report: 5 docs map more
lights than their strip, 11 fewer, 5 carry offset starts. The tester's docs are the only
walkthrough-compiled ones in the fleet.

### 5. Blast radius of stacked segments (had they persisted)

| Reader | Effect | Where |
|---|---|---|
| Design Studio gate | flips only via a copy carrying type/role/confirmation; a role makes the gate HARD | `roofline_segmentation.dart:54-63,108-133`; `design_studio_gate.dart:160-166` |
| Lights: per-pixel paints | spans rasterize per LED, later overwrite earlier; chunked at 224; not under the 4,096 B `applyJson` cap | `per_pixel.dart:92-129,205-232` |
| Smart presets / manual editor / AI composer | a copy BEFORE a real segment shifts every later segment → wrong lights; copies past the strip are clamped on LAN, sent over the relay off-LAN; the composer uses the inflated total | `smart_preset_logic.dart:37-90`; `manual_design_editor.dart:178-187`; `pattern_composer.dart:151-208` |
| Game Day participation | unaffected: the resolver reduces segments to channel sets and `is_primary` is always true | `channel_participation_resolver.dart:42-71` |
| Neighborhood sync | unaffected (same resolver) | `neighborhood_sync_engine.dart:689-720` |
| Schedule / lease | no segment readers | — |
| Defaults healer | never reads or writes pixelMap; heal-on-read only recomputes `start_pixel` in memory | `controller_defaults_healer.dart:951-1039`; `pixel_map_channel.dart:139-169` |
| Cloud Functions | none read segments (purge deletes the subtree) | `functions/src/purgeUserAccount.ts` |
| Lumina AI context | lists every segment; prompt bloat, possibly wrong LED targets | `lumina_brain.dart:1443-1500` |

Could the tester's extra segments cause wrong lights or wrong Game Day participation? **Not today**
(her data is a clean partition). Participation is unaffected by this class in general.

### 6. Regression verdict

`710b8f8` (109) → `9e5376a` (110 E2): walkthrough, marking compiler, segmentation assessor and the
trace merge were CREATED; Trace, Segment Setup and Refine were rewritten (2,150 insertions across
11 files). `9e5376a` → `aec40f5` (111): one 27-line Material fix in the walkthrough. `aec40f5` →
`a35e30e` (112): no roofline changes. So: the sections-as-segments experience and the duplicate-id
bug are **new in +110**; the grey Trace Delete is **long-standing** (present at 109); Segment Setup's
channel-0 default is **long-standing** (spec finding 2, 2026-08-19).

## Phase 2 — the fix (`fix/113-roofline-segments`)

- **Idempotent, unique sections** — `placeMark` (one light, one mark; the same mark twice returns
  the same list); new sections named `ch{n}_at{start}`; `withUniqueSectionIds` guarantees
  uniqueness; compiling the same marks twice yields identical ids (tested).
- **Strip-first channel length** — `channelLengthForMarking`: live strip → recorded
  `source_pixel_count` → stored sum; a notice when map and strip disagree. Behaviour change: the
  first save on a drifted channel writes a partition of the strip length (#133; bench on `.173`).
- **Real delete and merge in the walkthrough** — a sections list with per-section merge-delete
  (`planSectionRemoval` removes the mark that made the section; its lights merge into the
  neighbour), **Undo**, **Start over** with a confirmation that names what goes; a section no single
  removal can merge says why on its row.
- **Trace Roofline Delete** — `RooflineEditor.onActiveSegmentChanged`; the screen holds the index;
  disabled toolbar buttons explain themselves on tap; the panel reports sections without outlines.
- **Segment Setup** — channel picker in the form (default: the last segment's channel), channel chip
  on cards, delete offers "Merge into <neighbour>" (`removeSegmentMerging`, light count preserved)
  or "Remove with its lights".
- **Repair** — `roofline_repair.dart`: plan → dry run → `backupChannelSegments` (merge-writes
  `segments_backup`, `segments_backup_at`, `segments_backup_reason` on the channel doc; carried
  forward by every later `savePixelMap`) → cleaned save. Rules: same id + same lights, or same stored
  start + same lights → remove the later copy; same id + different lights → rename; identical
  neighbours reported only. Kept segments keep their own start and count. In-app: a "Review
  clean-up" banner in Segment Setup, shown only when there is work. Script:
  `scripts/pixelmap_cleanup_dry_run.js --uid=… [--controller=…]` is read-only; `--confirm`
  writes backup + cleaned segments in one batch. **Not run against production.** The tester's
  account has nothing to clean; the in-app banner will not appear for her.
- **Functions, rules, firmware:** untouched.

### Customer-reachability recommendation (no gating changed)

Keep the walkthrough, Trace Roofline and Refine customer-reachable: they are the +110 customer
design and now explain themselves. **Recommend gating Segment Setup** (the installer's flat editor
that lets a customer type pixel counts) on `installerModeActiveProvider`, the same lock the
Roofline Setup Wizard already uses, and pointing the Design Studio "Roofline setup" button at the
walkthrough for customers. Until #108's parent-segment UI exists, Segment Setup is where a
customer can still make a channel longer than its strip. Owner decision; not changed here.

### Device walk (for the owner)

Use `.173` (spare) or a test account's controller. Never select `.150`; the walkthrough and Refine
light LEDs on the SELECTED controller only.

1. Trace Roofline (System → System & Device Management → My Lights → Roofline Setup → Edit Layout):
   Delete is enabled right after load when a traced segment exists; tapping another segment in the
   list moves it; with nothing selectable, tapping Delete shows the reason.
2. Banner "Mark them" → walkthrough: mark a corner → the sections list shows run · corner · run with
   merge buttons; merge the corner → back to one run; Undo restores it; Start over → confirmation
   text names "1 corner"; Save channel; reopen → same sections, same ids (Firestore: `ch0_at…`).
3. Design Studio → Roofline setup (Segment Setup): Add Segment asks for the channel; cards show
   "Channel N"; delete a middle segment → "Merge into …" keeps the channel's total.
4. Clean-up banner: seed a TEST account's channel doc with two copies of a segment (same id, same
   lights) → banner appears → Review → dry run text → Back up and clean up → the doc has
   `segments_backup` and one copy. Or `node scripts/pixelmap_cleanup_dry_run.js --uid=<test uid>`.

### Gates (2026-10-01)

| Gate | Result |
|---|---|
| `flutter analyze`, local 3.41.2 | 367 infos/warnings, all pre-existing; 0 new in the touched files (the ones reported there — the `uuid` import, the `sum` parameter names, the older type dropdown's deprecated `value` — predate this branch) |
| `flutter test`, local 3.41.2 | 4,763 passed, 38 skipped, 0 failed |
| `flutter analyze`, 3.47.5, `TZ=UTC0`, after `flutter clean` | 372 infos/warnings, 0 new in the touched files (the five extra versus 3.41.2 are pre-existing `onReorder` deprecations) |
| `flutter test`, 3.47.5, `TZ=UTC0` | 4,763 passed, 38 skipped; the one failure was the new Trace Delete widget test tripping Flutter 3.47's debug assertion on the pre-existing segment panel (`ListTile` in a coloured box without its own `Material`, the 7b7dc79 class) — fixed in the panel, then the Trace, Segment Setup and walkthrough test files re-run green under both SDKs |
| `git diff 8b3bcdf HEAD -- functions/` | empty |
| PII scan of the change set (names, emails, uids, controller ids, non-documentation IPs) | clean |

### Build 113?

Quick build justified: the tester is stuck on a grey Delete and a confusing sections view, the change
is confined to roofline screens and pure logic, and no functions, rules or firmware move. One
behaviour change (#133, strip-first length) deserves the `.173` walk above before the tag.
