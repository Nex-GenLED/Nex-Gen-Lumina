# Colour Fidelity — Addendum (Part 2 of 2)

**Read-only.** No files outside this document were modified; no commits to `lib/`
or `test/`. Branch `feat/design-card` @ `02b471c`.

> ## Note on placement
>
> **Part 1 of this brief never reached me, and no colour-fidelity audit exists in
> this tree** — `audit/` holds only `MY_DESIGNS_AUDIT.md`, `DESIGN_CARD_P2/P3/P4.md`
> and `SCHEDULING_V3_AUDIT.md`, and no commit on any branch mentions it. I
> therefore do not know the parent document's path, its Task 1–4 headings, or
> what 2a–2d and 4a–4c already cover.
>
> The four addendum items are self-contained questions, so I answered them in
> full rather than blocking. **They are written to be pasted into the parent as
> §2e, §2f, §4d and a BLOCKERS entry** — the headings below match those labels.
> Tell me the parent's path and I will merge them in place. If 2a–2d already
> cover any of this, treat the overlap as corroboration rather than duplication.

Source for the three items handed over:
[DESIGN_CARD_P4.md §5 "Handed to the colour-fidelity stream"](DESIGN_CARD_P4.md).

---

## 2e — Every builder that turns a stored design, card, or library node into a WLED seg

Scope: builders on the **design / card / library-node** path. (`grep "'seg':"`
matches 60 files; most are device-command, timer, healer, or provisioning paths
that never start from one of those three sources.)

### The table

| # | Builder | file:line | Source | fx substitution | `pal` | `grp`/`spc` | Colours carried |
|---|---|---|---|---|---|---|---|
| 1 | `CustomDesign.toWledPayload` | [design_models.dart:244-278](../lib/features/design/design_models.dart#L244-L278) | Stored design | **0 → 83** when >1 colour group. Never 84. | **NONE EMITTED** | Always the #88 constants (`...kDesignSpacingDefaults`, [:272](../lib/features/design/design_models.dart#L272)) | `colorGroups.take(3)` per channel |
| 2 | `buildSelectorPayload` | [selector_payload.dart:107-131](../lib/features/wled/selector_payload.dart#L107-L131) | Tuner state (catalog palette **or**, since Phase C, a stored design) | **None.** Emits `s.effectId` verbatim; the 0→83 decision is the caller's | `WledEffectsCatalog.paletteForEffect(fx)` — **derived** | From selector providers; design-edit hides the control so they are the defaults | `_paletteColsRgbw()` → `.take(3)` |
| 3 | `_CompactPatternItemCard._preparePayload` | [pattern_grid_widgets.dart:1484-1543](../lib/features/wled/pattern_grid_widgets.dart#L1484-L1543) | Explore card tap | **0 → 83 (2 colours) / 84 (3+)**, and **N → 0** when only one colour is active | `pal: 5` hardcoded, but only inside the fx-0 branch | **`grp: ledsPerColor`** (user-chosen), `spc: 0` | All *active* colours (user-togglable), no cap in this function |
| 4 | `GradientPattern.toWledPayload` | [pattern_models.dart:326-356](../lib/features/wled/pattern_models.dart#L326-L356) | Library node → generated card | **0 → 83** when >1 colour. Never 84. | `pal: 5` **hardcoded unconditionally** | `kDesignDefaultGrp` / `kDesignDefaultSpc` | `colors.take(3)` |
| 5 | `SyncPatternAssignment.fromLibraryNode` | [neighborhood_models.dart:1286-1308](../lib/features/neighborhood/neighborhood_models.dart#L1286-L1308) | Library node (Sync picker) | **None** — the effect is picked separately by the user | `pal: 5` default | `grp: 1`, `spc: 0` defaults | `themeColors` — **preview swatches**, not design colours |
| 6 | Sync member-side apply | [neighborhood_sync_engine.dart:760-777](../lib/features/neighborhood/neighborhood_sync_engine.dart#L760-L777) | A received assignment | **None** — `memberPattern.effectId` verbatim | `memberPattern.pal` | `memberPattern.grp` / `.spc` | `colorArrays.take(3)` |
| 7 | `customDesignToSpans` → `applyBaseAndSpans` | [design_apply.dart:95-113](../lib/features/design/manual_editor/design_apply.dart#L95-L113) | Stored design (per-pixel spine) | **N/A** — emits per-pixel `i` arrays, no `fx` at all | N/A | N/A | Every group; no cap |
| 8 | `Scene.toWledPayload` | [scene_models.dart:234-240](../lib/features/scenes/scene_models.dart#L234-L240) | Scene (wraps a `CustomDesign`) | Delegates to #1 | Delegates | Delegates | Delegates |
| 9 | `EditablePattern.toWledPayload` | [editable_pattern_model.dart:123](../lib/features/wled/editable_pattern_model.dart#L123) | `/users/{uid}/patterns` doc | *(not audited — different store, out of the design/card/node scope)* | — | — | — |
| — | `normalizeWledPayload` (transformer, not a builder) | [wled_payload_utils.dart:553-640](../lib/features/wled/wled_payload_utils.dart#L553-L640) | Any payload, at the apply chokepoint | None | **`pal` absent → untouched**; only rewrites an explicit `pal:5` → `4` for palette-driven effects ([:635](../lib/features/wled/wled_payload_utils.dart#L635)) | Injects the #88 defaults when the seg "states a design" (`fx`, `col`, or `i`) — `putIfAbsent`, so an explicit value wins | Untouched |

### Findings — builders that disagree on the same stored design

**F1. Three different palette behaviours; the stored-design one emits nothing.**
Builder #1 emits **no `pal` key at all**, and `normalizeWledPayload` explicitly
leaves an absent `pal` alone ("`pal` absent → untouched",
[wled_payload_utils.dart:632](../lib/features/wled/wled_payload_utils.dart#L632)).
So **a saved design applied to a segment inherits whatever palette the previous
look left there.** Under #67's own rule — *unstated design state is inherited
design state, and inherited state is a bug* — that is the bug class #88 was
written to close, still open on the design path.

Meanwhile #4 hardcodes `pal:5`, #3 sets `pal:5` only in its fx-0 branch, and #2
derives it from the catalog. **The same visual design applied from My Designs, from
an Explore card, and from the tuner can land on three different palettes.**

**F2. The fx-0 substitution has two incompatible implementations.**
Both #1 and #3 substitute for multi-colour Solid, but:

- #1: `0 → 83` for *any* count > 1.
- #3: `0 → 83` for exactly 2, `0 → 84` (Solid Pattern Tri) for 3+.

A three-colour design applied from its card runs **84**; the same design applied
from My Designs runs **83**. 83 cycles two colours, 84 cycles three — so the
third colour is visible from one surface and not the other.

**F3. #3 repurposes `sx`/`ix` as band widths; #1 does not know that.**
In the card path's fx-83 branch, `s['sx'] = n; s['ix'] = n` where
`n = ledsPerColor - 1` ([pattern_grid_widgets.dart:1512-1516](../lib/features/wled/pattern_grid_widgets.dart#L1512-L1516)).
Builder #1 writes `channel.speed` / `channel.intensity` into the same two keys.
When #1's substitution fires, **the design's stored speed and intensity are
reinterpreted by the device as pattern geometry** — see the BLOCKERS entry.

**F4. Only #3 can express user-chosen banding; nothing can store it.**
`grp: ledsPerColor` exists solely in the card path and is discarded the moment the
look is saved as a design — #1 always writes the constants (see BLOCKERS).

**F5. `.take(3)` appears in five independent places** (#1, #2, #4, #6, and the
Sync `colorArrays`), each re-deciding the cap. #3 does not cap. A 4-colour design
therefore renders 4 colours from its card and 3 everywhere else.

---

## 2f — What a neighbour's controller receives vs. what the assigning house shows

**Wire format.** `SyncPatternAssignment.toJson`
([neighborhood_models.dart:1314-1324](../lib/features/neighborhood/neighborhood_models.dart#L1314-L1324))
carries exactly nine primitives: `name, effectId, colors, speed, intensity,
brightness, pal, grp, spc`. The model has a `wledPayload` field
([:1213](../lib/features/neighborhood/neighborhood_models.dart#L1213)) — **`toJson` does not
serialise it**, so an attached payload is dropped at the boundary.

**What the member applies** ([neighborhood_sync_engine.dart:760-777](../lib/features/neighborhood/neighborhood_sync_engine.dart#L760-L777)):
a single seg with **no `id`**, expanded per participating channel by the apply
chokepoint —

```
{'on': true, 'bri': bri,
 'seg': [{'fx': effectId, 'sx': speed, 'ix': intensity,
          'pal': pal, 'grp': grp, 'spc': spc,
          'col': colorArrays.take(3)}]}
```

### Assigner vs. neighbour

| Axis | Assigning house shows | Neighbour receives |
|---|---|---|
| **fx** | Whatever its own builder produced — possibly a **substituted** 83 or 84 (F2) | The assignment's `effectId` **verbatim, no substitution**. If the assignment was built from a look already running substituted 83, the neighbour gets 83 with `sx`/`ix` meaning *speed/intensity*, not band widths (F3) — the same number, a different picture. |
| **Colour count** | Up to 4 from a card (#3), 3 from most builders | **Hard cap 3**, twice: `.take(3)` at build and again at apply |
| **Channel scope** | Per-channel `id`s, per-channel effects | **None.** One id-less seg broadcast to every participating channel. A design that lights one channel lights all of the neighbour's. |
| **Per-pixel** | `i` arrays via the per-pixel spine (#7) | **Not representable.** No `i` key exists in the nine primitives, and no field could carry one. |
| **Brightness** | The design's own | The assignment's — set by the picker, not the design |

### Can either design kind be represented?

- **Per-pixel design — no.** Structurally impossible: the wire format has no
  per-LED channel. Even a payload field would not help, because roofline geometry
  differs per house (a span meaningful on one roof is meaningless on another).
- **Effect design — partially, and not today.** fx / sx / ix / bri / up-to-3
  colours *could* survive if an assignment were built **from the design**. But
  `fromLibraryNode` builds from `themeColors` + a separately-picked effect, so
  even the representable subset is not transmitted: the neighbour receives the
  design's **preview swatches** and the *picker's* effect, not the design's.

This is the evidence behind the C2 exclusion
([DESIGN_CARD_P4.md §3](DESIGN_CARD_P4.md)). **Every neighbourhood look is a
reconstruction at the receiving house**, bounded by nine fields, regardless of
what the initiating house is actually displaying.

---

## 4d — Census additions

### Neighborhood Sync assignments

| | |
|---|---|
| **Store** | Sync command docs / per-house assignment maps (`SyncPatternAssignment.toJson`) |
| **Colour representation** | `colors: List<int>` — packed `0xRRGGBB`, `c.value & 0xFFFFFF` ([neighborhood_models.dart:1300](../lib/features/neighborhood/neighborhood_models.dart#L1300)) |
| **W channel** | **Dropped at write.** The mask discards alpha *and* any W the source carried; W is re-derived at apply by `rgbToRgbw`. An RGBW design's explicit W does not survive. |
| **Cap** | 3 at apply (`colorArrays.take(3)`) |
| **fx fidelity** | Verbatim, no substitution (2f) |
| **Fidelity verdict** | **Lossy by construction.** Not a design; a nine-field recipe. |

### Game Day `savedDesignPayload`

| | |
|---|---|
| **Store** | `/users/{uid}/game_day_autopilot/{teamSlug}`, key `saved_design_payload` |
| **Encoding** | `jsonEncode(wledPayload)` at write ([game_day_autopilot_providers.dart:1080](../lib/features/autopilot/game_day_autopilot_providers.dart#L1080)); decoded at [game_day_autopilot_config.dart:368-369](../lib/features/autopilot/game_day_autopilot_config.dart#L368-L369). jsonEncoded because `col:[[r,g,b,w]]` is the #84 nested-array crash shape. |
| **Colour representation** | **Full RGBW `col` arrays** — the only one of the two that keeps W |
| **Source builder** | `buildSelectorPayload` (#2) via the tuner's Game Day exit — so `pal` is **catalog-derived**, unlike the stored-design path (F1) |
| **Cap** | 3 (`_paletteColsRgbw().take(3)`) |
| **Fidelity verdict** | **Highest of any stored form.** A complete seg, W intact, palette stated. Note the asymmetry: **Game Day stores a better-specified payload than `/users/{uid}/designs` does** (F1) — the design store keeps structured channels and re-derives, and drops `pal` doing it. |

---

## BLOCKERS — does the #88 `grp`/`spc` model gap block accurate static-pattern previews (83/84 "Size")?

**No, not for 83/84 Size — but a worse adjacent problem does.**

**Why the grp gap is not the blocker.** For effects 83 and 84 the app's own
metadata says size travels on **`ix`**, not `grp`:

```dart
// wled_effect_metadata.dart:325-336
83: WledEffectMetadata(usesSpeed: false, usesIntensity: true,
                       intensityLabel: 'Pattern Size'),
84: WledEffectMetadata(usesSpeed: false, usesIntensity: true,
                       intensityLabel: 'Pattern Size'),
```

`ChannelDesign.intensity` **is** stored and **is** emitted as `ix` by builder #1,
so the size of a static pattern is representable today. The #88 gap
(`ChannelDesign` has no `grouping`/`spacing`, [design_models.dart:296-346](../lib/features/design/design_models.dart#L296-L346);
`toWledPayload` spreads the constants, [:272](../lib/features/design/design_models.dart#L272))
blocks something different: **user-chosen LED-per-colour banding on
non-substituted multi-colour effects** — the card path's `grp: ledsPerColor`
(F4), which is discarded on save. Two designs differing only in banding are
indistinguishable once stored. Real, but not the 83/84 Size path.

**What does block accurate 83/84 preview — the substitution changes what `ix`
means, silently.**

The fx-0 → 83/84 substitution happens **at payload-build time**, after the model
is fixed. The consequence:

- A design stored as `fx: 0, speed: 128, intensity: 200` renders on the device as
  `fx: 83, sx: 128, ix: 200`.
- Under fx 0, `ix` is effect intensity and `sx` is speed — for Solid, both inert.
- Under fx 83, **`ix` is Pattern Size** and `sx` is inert
  (`usesSpeed: false`; `effect_speed_profiles.dart:217` labels 83 `'Static'`).

So the stored `intensity: 200` — a value the user very likely never set as a size,
since Solid ignores intensity — **becomes the pattern's band size** the moment the
substitution fires. Nothing in the model, the detail screen, or the tuner records
that reinterpretation. The detail screen's "Effect" row even reports `fx 0`
([DESIGN_CARD_P4.md §5.1](DESIGN_CARD_P4.md)), so the UI names an effect whose
slider semantics are not the ones in force.

**Therefore:** any preview that renders a stored design by reading `intensity` as
*intensity* will be wrong for exactly the designs that get substituted — the
multi-colour Solids, which are the commonest saved look. The card path already
concedes this and hand-computes `sx`/`ix` from `ledsPerColor` instead
([pattern_grid_widgets.dart:1512-1522](../lib/features/wled/pattern_grid_widgets.dart#L1512-L1522)),
which is why the card's preview and a My Designs preview of the same design can
legitimately differ.

**Blocker statement.** A truthful static-pattern preview needs the **substituted**
fx and the **slider semantics that follow from it**, not the stored fx. The
minimum is a shared resolver — "given a stored `ChannelDesign`, return the
as-applied `(fx, sx, ix)` and what each means" — derived from the one substitution
rule rather than re-decided per builder (F2 shows it is currently decided twice,
incompatibly). The #88 model gap should be fixed too, but it is a **separate,
lower-priority** blocker affecting banding, not Size.

---

## What I would have had to fabricate, and didn't

1. **The parent audit's structure.** Part 1 never arrived and no colour-fidelity
   document exists in the tree; I did not invent Task 1–4 headings, a numbering
   scheme, or an output path. This is a standalone fragment labelled to merge.
2. **Whether 2a–2d already cover builders 1–4.** Unknown; flagged as possible
   corroboration rather than silently deduplicated.
3. **Device-observed behaviour.** Every claim is from source. The 83/84 `ix`
   semantics are taken from the app's own `wled_effect_metadata.dart` and
   `effect_speed_profiles.dart`, **not** from WLED firmware or a bench capture. If
   the app's metadata is itself wrong about 83/84, this analysis inherits that
   error — worth one bench check before acting on the blocker.
4. **`EditablePattern.toWledPayload` (builder #9).** Left unaudited rather than
   guessed: it serves `/users/{uid}/patterns`, a different store from the
   design/card/node path this item scopes. Say the word and I will add it.
5. **A count of affected designs.** How many stored designs are multi-colour
   Solids — i.e. how many actually hit the substitution — needs a client-credential
   read of `/users/{uid}/designs`, which I do not have.
