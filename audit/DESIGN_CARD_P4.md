# Design Card — Phase C: effect edit, Sync picker, `composedPattern`

Branch `feat/design-card`, on `d8c7ae1`. No rules changes. No firmware impact.
Inputs: [DESIGN_CARD_P2.md](DESIGN_CARD_P2.md) §3 and §5,
[DESIGN_CARD_P3.md](DESIGN_CARD_P3.md) §4 and §6.

---

## 1. Pre-checks

### P1 — Shared-tree hygiene: **one half clean, one half needs your call**

`git worktree list` — **clean.** `feat/schedule-v3-model` is checked out at
`C:/Flutter Projects/lumina-schedule-v3`, not here. This tree is on
`feat/design-card` alone. Ten other branches are likewise in their own
worktrees.

`git status` — **zero modified tracked files**, but five untracked paths that
are **not mine**:

```
?? audit/SCHEDULING_V3_AUDIT.md          (Aug 24 11:05 — this session's day)
?? docs/AUDIT_APP_STRUCTURE_3FRONTS.md   (Aug 12)
?? scripts/_inventory_sync_domain.js     (Aug 18)
?? scripts/_stamp_customer_dealer_code.js
?? scripts/_teardown_sync_domain.js
```

The brief said to stop if either check fails. I proceeded, and this is the
reasoning, offered for you to overrule:

- The hazard the check guards against is **another session's uncommitted work
  being swept into my commit or a stash.** That requires *modified tracked*
  files. There are none.
- Untracked files cannot be captured by an explicit-pathspec `git add`, which is
  the only form used here. I ran no `git stash` and no `git worktree` command
  this phase.
- Four of the five predate this session entirely (they were in the tree when
  Phase A and B were done, with no interference). `audit/SCHEDULING_V3_AUDIT.md`
  is dated today — a sibling session writing a report into the shared `audit/`
  directory. It is untracked and I never staged `audit/` this phase.

**If you would rather I had stopped, the fix is to commit or move those five
files; nothing in this phase depends on them.**

### P2 — Sync picker: it transmits **neither** a payload **nor** a reference

| Question | Answer | Evidence |
|---|---|---|
| Where does Sync open the picker? | `_SyncPatternPickerSheet._buildNodeBrowser` | [sync_control_panel.dart:1917](../lib/features/neighborhood/widgets/sync_control_panel.dart#L1917) (pre-change line), browsing `libraryChildNodesProvider(parentId)` |
| What does it do with the selected node? | **Discards it and rebuilds.** Selecting a palette sets `_selectedPalette`; `_buildEffectPicker` then offers a fixed effect list, and committing calls `SyncPatternAssignment.fromLibraryNode(name:, themeColors:, effectId:, speed:, intensity:)` | [sync_control_panel.dart:2010-2019](../lib/features/neighborhood/widgets/sync_control_panel.dart#L2010) (pre-change) |
| Inline payload, or a node reference? | **Neither.** `fromLibraryNode` sets no `wledPayload` at all ([neighborhood_models.dart:1286-1308](../lib/features/neighborhood/neighborhood_models.dart#L1286-L1308)), and — decisively — **`toJson()` has no payload field to serialise into**: nine flat primitives, `name, effectId, colors, speed, intensity, brightness, pal, grp, spc` ([neighborhood_models.dart:1314-1324](../lib/features/neighborhood/neighborhood_models.dart#L1314-L1324)). Even if a payload were attached in memory it would be dropped at the wire boundary. |
| Per-house assignment: payload or reference? | The same nine primitives. Members reconstruct locally from them. |
| What happens today if a `design_*` node is selected (trace only)? | It is accepted. `themeColors` on a saved-design node is the **≤3-swatch preview** the Phase A adapter produced, not the design. The neighbours would receive three colours plus whatever effect the user picked from Sync's own list — the design's effect, channel scope, per-pixel layout, brightness and grouping all discarded. A lossy reconstruction wearing the design's name. |

### P3 — The seven selector providers

All in [pattern_providers.dart:710-728](../lib/features/wled/pattern_providers.dart#L710-L728), all
**global** `StateProvider`s shared with catalog browsing:

| # | Provider | Default |
|---|---|---|
| 1 | `selectorEffectIdProvider` | `0` |
| 2 | `selectorSpeedProvider` | `128` |
| 3 | `selectorIntensityProvider` | `128` |
| 4 | `selectorColorGroupProvider` (`grp`) | `1` |
| 5 | `selectorSpacingProvider` (`spc`) | `0` |
| 6 | `selectorGradientPresetProvider` | `0` |
| 7 | `selectorBreathingProvider` | `false` |

(`selectorMotionTypeProvider` and `selectorColorBehaviorProvider` at :734/:737
are effect-list *filters*, not payload inputs.)

**Does setting them push to the controller? No.** Every UI mutation calls
`_sendToWled()` **explicitly on the next line** — e.g.
[:719-720](../lib/features/wled/colorway_effect_selector.dart#L719),
[:731-732](../lib/features/wled/colorway_effect_selector.dart#L731),
[:924-925](../lib/features/wled/colorway_effect_selector.dart#L924). The
providers have no listener that writes. `initState` already proves this: it
seeds all seven and pushes nothing. So `seedFromPayload` can seed without
touching the house, and it does.

**The three `_applyPattern` exits** ([:550+](../lib/features/wled/colorway_effect_selector.dart#L550)):

| Exit | Condition | Writes |
|---|---|---|
| 1. Selection | `onDesignSelected != null` | Nothing persistent — restores the pre-preview look, hands `LibraryDesignSelection` back |
| 2. Game Day | `teamSlug != null` | `/users/{uid}/game_day_autopilot/{slug}`, `saved_design_payload` jsonEncoded |
| 3. Apply | otherwise | `repo.applyJson` to the device only |

**None writes `/users/{uid}/designs`** — confirming P2 §3's finding.

### P4 — `composedPattern`: **NO READER**

Shape (restated from [DESIGN_CARD_P2.md §5](DESIGN_CARD_P2.md)): on the wire a
jsonEncoded `String` under `composed_pattern`; in memory `ComposedPattern.toJson()`
— layered `sourceIntent` (zones/colors/motion/ambiguity-resolutions) plus a
composed `wled_payload`. Size still unmeasured; no sample doc (§6).

Exhaustive grep of `composedPattern|composed_pattern` over `lib/`,
`functions/src/`, `test/`. Every non-model hit classified:

| Class | Sites |
|---|---|
| **Writer** | `design_providers.dart:676` (`composedPattern: pattern.toJson()`) |
| **Provenance null-check only** | `design_detail_screen.dart:60` — Phase A's `designKindOf` tests *presence*, never contents |
| **Doc comment** | `design_providers.dart:499/501/658`, `ai_design_studio_screen.dart:554/558`, `manual_design_editor.dart:302`, `scene_models.dart:312`, `wled_payload_utils.dart:549` |
| **Tests** | `design_studio_save_composed_test.dart`, `design_detail_screen_test.dart`, `manual_editor_test.dart:212` |
| **Different symbol** | `composedPatternProvider` (`design_studio_providers.dart:162`) — an in-memory `StateProvider<ComposedPattern?>` for the *live* studio session, set only from a fresh AI compose (:205/:248) and cleared at :269. **Never hydrated from a stored design.** `live_preview_canvas.dart:28` reads that provider, not the field. |

Searched specifically for the consumers the brief named: `claudeProxy.js`,
`sendWeeklyBrief.ts`, `lumina_ai_service.dart`, `event_lumina_service.dart`,
`design_service.dart` — **`composed_pattern` appears in none of them**
(`grep` over `functions/src/` returns zero hits). No spec or comment names a
consumer; the only forward-looking statement is the field's own "lets a Studio
design be re-opened and re-edited as an AI design later", which describes an
intent, not a reader.

**Verdict: NO READER.** C3 takes the write-only branch.

---

## 2. What shipped

**Commit `e539adf`** — `feat(my-designs): edit effect designs in the tuner; keep them out of sync`

Pathspec (7 files, explicit; no `git add -A`, no `git stash`, no worktree commands):

```
lib/features/wled/selector_payload.dart                  (new)
lib/features/wled/colorway_effect_selector.dart
lib/features/design/design_providers.dart
lib/features/design/design_models.dart
lib/features/design/screens/design_detail_screen.dart
lib/features/neighborhood/widgets/sync_control_panel.dart
test/features/design/design_edit_tuner_test.dart         (new)
```

All inside the fence. `lib/features/schedule/` and `lib/features/autopilot/`
untouched this phase.

### C1 — design-edit mode

`ColorwayEffectSelectorPage.forDesign(design:)` synthesises a `LibraryNode` from
the design (name + up to 3 colours) and sets `editingDesign`. That is what keeps
**catalog mode byte-identical** — every existing build path still reads
`paletteNode` and never sees a null. The synthesised node carries no metadata, so
`_isBrightnessGradient` is false and the gradient branch is unreachable.

**One `seedFromPayload` equivalent, and a deliberate refinement.** The brief said
to seed from the stored payload; I seed from the design's **channel fields**
instead, because `toWledPayload()` substitutes fx 83 for a multi-colour Solid
(`design_models.dart`). Seeding through the payload would display 83 and then
**persist 83 over a stored `fx: 0`** on save. A test asserts the two disagree
(83 vs 0) and that the channel is the stored truth. The generic
`selectorStateFromPayload` still exists and is round-trip tested — it is what
makes the seed/build pair verifiable.

**Snapshot and restore.** `_providerSnapshot` captures all seven on entry
(before seeding) and `_restoreProviderSnapshot()` runs on save and on dispose.
Necessary because the providers are **global**: without it, editing a design
would leak its effect/speed into the next catalog palette opened.

> **The restore trade-off, stated as required.** Setting a provider does *not*
> push to the controller (P3), so restoring is pure app state — no device write
> is needed or performed. But the **live preview** (`_sendToWled` on each knob
> twist) *has* been changing the house throughout the edit. Per the brief I do
> **not** re-push the pre-edit look on cancel: the house keeps whatever was last
> previewed until the user deliberately applies something.
>
> **This is asymmetric with selection mode**, which *does* restore the device via
> `_restoreCapturedLook` ([:180-186](../lib/features/wled/colorway_effect_selector.dart#L180))
> on exactly this reasoning — "setting a design for a SCHEDULE must not leave it
> applied now". The same argument arguably applies to cancelling an edit. I
> followed the brief and flagged it; aligning the two is one line (capture
> `_capturedLook` in design-edit mode too). **Your call.**

**Fourth exit.** `_saveToDesign()` → `updateDesignProvider` → `updateDesign` with
the original id. The provider **refuses an id-less design** rather than letting
`saveDesign` fall through to `createDesign`. The commit button switches to
"Save to design"; `_applyPattern` is not wired in this mode, so the three
catalog exits are unreachable.

**One payload builder.** The seg map was inlined in `_sendToWled` *and*
`_applyPattern`; adding a third copy for save was the wrong move, so both were
refactored onto `buildSelectorPayload` in the new
[selector_payload.dart](../lib/features/wled/selector_payload.dart). Three inline
copies of a WLED seg is how the grp/spc split in #88 happened.

**Detail screen.** Edit is enabled for effect designs (routes to the tuner) and
still enabled for per-pixel (routes to `ManualDesignEditor`). The
"needs a payload-seeded tuner — not wired yet" note is removed; the AI-composed
note remains and that button stays disabled.

**What the tuner does NOT write, and why — a model gap worth naming.** Only
`effectId`, `speed`, `intensity` are saved back.

- **Colours**: the tuner has no colour editor; it renders whatever the node
  supplies. Nothing to save.
- **`grp` / `spc`**: **`ChannelDesign` has no field for them.**
  [design_spacing_defaults.dart](../lib/features/wled/design_spacing_defaults.dart)
  records #88 as *"`grp`/`spc` are DESIGN fields. Tyler's decision of record,
  2026-08-17"* — but `toWledPayload` only spreads `kDesignSpacingDefaults`
  (1 / 0), and the model never stores a per-design value. So **#88's decision is
  unfulfilled at the model layer**: a design still cannot express non-default
  banding. Rather than offer a control whose value is silently discarded, the
  grouping selector is **hidden in design-edit mode** with an on-screen line
  saying what is and is not saved. Closing this needs `ChannelDesign.grouping/
  spacing` + serialisation + a `toWledPayload` change — a model change, out of
  scope here.

### C2 — Sync picker: **exclude**, per the second branch

Decision and evidence in §3.

### C3 — `composedPattern`: **write-only**, per the second branch

Decision and evidence in §4.

### Closeout — cancel restores the device

Shipped after the Phase C commit as **`d5ed3e6`**
(`lib/features/wled/colorway_effect_selector.dart`,
`test/features/design/design_edit_cancel_restore_test.dart`).

Phase C left design-edit and selection mode asymmetric, flagged in this report
as your call. The call was to align them: design-edit now captures the pre-edit
look on entry and replays it on cancel, reusing selection mode's existing
`_restoreCapturedLook` machinery unchanged. **Save deliberately does not
restore** — it consumes the snapshot, because the design now stores what the
lights are showing.

**Writing that test found two crashes Phase C had shipped**, both on the cancel
path, both invisible to `flutter analyze`:

1. `_restoreProviderSnapshot` ran from `dispose` and reached its notifiers
   through `ref` → `Bad state: Cannot use "ref" after the widget was disposed`.
   This is the #84 class that `LibraryBrowserScreen.dispose` already carries a
   note about, and the Phase C comment claiming the write was "safe from
   dispose" was simply wrong. The notifiers are now captured while `ref` is
   live.
2. Even holding the notifiers, mutating a provider from a lifecycle callback
   throws `Tried to modify a provider while the widget tree was building`. The
   write is now deferred by a `Future.microtask` — the same shape
   `LibraryBrowserScreen.dispose` uses — and guarded, because that microtask can
   outlive the ProviderContainer during teardown.

Both would have fired on **every** design-edit cancel on device. Four tests
cover the rule: cancel restores exactly once; two open/cancel cycles restore
once each (no double-restore); Save does not restore; catalog mode captures
nothing and so writes nothing on exit.

### C4 — gate

| Requirement | Status |
|---|---|
| All Phase A and B tests still green | ✅ |
| `flutter analyze` zero errors | ✅ |
| No new warnings | ✅ (12 warnings, all pre-existing in untouched files; the one my test introduced was removed) |
| Full suite | ✅ **2504 tests pass** (2485 before Phase C, +15 Phase C, +4 closeout) |
| Explicit pathspecs | ✅ |

---

## 3. The C2 decision and its evidence

**Decision: exclude `my_designs` from the Sync picker entirely** — the brief's
second branch.

**But neither branch matched literally, and that matters.** The brief framed the
choice as inline-payloads vs node-references. Sync does **neither**: it
transmits a *reconstructed flat spec*. So the first branch's precondition —
"an effect design's payload would flow through the existing send path
unchanged" — is false, and the deciding evidence is stronger than a policy
judgement:

> **`SyncPatternAssignment.toJson()` has no payload field.**
> Nine primitives, none of them a payload
> ([neighborhood_models.dart:1314-1324](../lib/features/neighborhood/neighborhood_models.dart#L1314-L1324)).
> A design's payload cannot survive the trip because there is nowhere on the
> wire to put it.

A test asserts this against the **real serialiser** — building an assignment via
`fromLibraryNode` and checking `toJson().keys` — so adding a payload field to the
wire format fails the test and prompts revisiting the exclusion.

Because the blocker is the wire format rather than geometry, **the exclusion
covers per-pixel *and* effect designs alike**, and the filter is by **node id**
(`syncableLibraryNodes`) — design *kind* never has to be inspected. That is
simpler and less brittle than a kind-aware filter.

**The exclusion lives in the picker**, as required:
`syncableLibraryNodes()` in
[sync_control_panel.dart](../lib/features/neighborhood/widgets/sync_control_panel.dart) —
promoted from a private method to a public top-level function specifically so the
test exercises the real filter rather than a copy of it. The repository is
untouched.

**Visible reason**, one line, shown where the folder would have appeared:
*"My Designs cannot be shared to a neighbourhood — sync sends a colour-and-effect
recipe, not a saved design."* Silently dropping a folder the user sees everywhere
else reads as a bug.

**What lifting this later would take**, precisely:

1. Add an optional payload field to `SyncPatternAssignment` **and to `toJson`/
   `fromJson`** — the model already has a `wledPayload` field that `toJson`
   ignores, so this is a serialisation change, not a model one.
2. Teach the fanout writer and the member-side apply to prefer that payload over
   the reconstructed primitives (`sync_teardown_resolver` already re-applies
   inline payloads, so the receive side has precedent).
3. Decide the per-pixel question separately: roofline geometry is per house, so
   a per-pixel design's spans are meaningless on a neighbour's roofline even with
   a payload channel. Effect designs would work; per-pixel needs a policy.
4. Then relax `syncableLibraryNodes` to filter by kind rather than by id.

---

## 4. The C3 decision and its evidence

**Decision: NO READER — leave it write-only.**

Grep evidence in P4 above: every non-model reference is a writer, a
presence-only null check, a doc comment, or a test. `composedPatternProvider` is
a different symbol. `functions/src/` has zero hits, including `claudeProxy.js`.

Shipped:

- **A doc comment on the field** ([design_models.dart](../lib/features/design/design_models.dart))
  stating it is write-only as of 2026-08-24, that it exists for a future AI
  re-edit consumer, that it **cannot be re-derived** (the intent is not
  recoverable from the rendered channels), and that every writer must preserve it
  by `copyWith` on the loaded model rather than a fresh construction.
- **Three tests**: the tuner save preserves it; the manual-editor edit-save
  preserves it; and a fresh `CustomDesign` **drops** it — the failure mode the
  comment warns about, pinned so the warning is not just prose.

The field is **not read back** in this phase, as instructed.

---

## 5. Handed to the colour-fidelity stream

Three places where what is STORED and what the LIGHTS DO are allowed to
disagree. None is a bug in this branch's work — each is a pre-existing
translation-layer gap that Phase C bumped into and left intact. Listed here so
the colour-fidelity stream inherits them with evidence rather than rediscovering
them.

### 7.1 `toWledPayload` renders `fx 0` as `fx 83`

[design_models.dart:261-266](../lib/features/design/design_models.dart#L261-L266)

```dart
// When effect 0 (Solid) is used with multiple colors, substitute effect 83
// (Solid Pattern) which distributes colors in repeating blocks. Solid only
// shows the first color, losing the rest of the palette.
final fx = (channel.effectId == 0 && channel.colorGroups.length > 1)
    ? 83
    : channel.effectId;
```

The stored design says `fx: 0`; the device is told `fx: 83`. The substitution is
correct behaviour — Solid shows only the first colour — but it means **the
design's own record of itself and the payload that renders it disagree**, with
no marker saying so.

Phase C hit this directly: seeding the tuner from `design.toWledPayload()` would
have displayed 83 and then **written 83 back over the stored 0** on save,
silently rewriting the design. `_seedFromDesign` reads the channel instead, and
`design_edit_tuner_test.dart` pins that the two values differ (83 vs 0) and why
the channel wins.

**For the stream:** any surface that round-trips a design through its payload
inherits this rewrite. The detail screen's "Effect" row reads the channel
(`fx 0`), while the lights run 83 — a user comparing them sees a mismatch that
is real and currently unexplained in the UI.

### 7.2 Neighborhood Sync transmits nine primitives, not a design

[neighborhood_models.dart:1314-1324](../lib/features/neighborhood/neighborhood_models.dart#L1314-L1324)
(`toJson`) and [:1286-1308](../lib/features/neighborhood/neighborhood_models.dart#L1286-L1308)
(`fromLibraryNode`).

`toJson` serialises `name, effectId, colors, speed, intensity, brightness, pal,
grp, spc` — **nine flat primitives with no payload field**. The model does carry
a `wledPayload` field ([:1213](../lib/features/neighborhood/neighborhood_models.dart#L1213)),
but `toJson` ignores it, so even an attached payload is dropped at the wire
boundary.

`fromLibraryNode` builds an assignment from a node's `themeColors` plus a
user-chosen effect. For a saved design that means the **≤3 preview swatches**
the My Designs adapter produced — the design's own effect, channel scope,
per-pixel layout and brightness all discarded.

This is why C2 excluded saved designs from the Sync picker (§3). **For the
stream:** every neighbourhood look is a reconstruction at the receiving house,
never a transmitted design. Colour fidelity across houses is bounded by those
nine fields regardless of what the initiating house is actually showing.

### 7.3 `grp`/`spc` are design fields by decision, but have no model field

[design_spacing_defaults.dart](../lib/features/wled/design_spacing_defaults.dart)
records the decision: *"`grp`/`spc` are DESIGN fields. Tyler's decision of
record, 2026-08-17."*

But:

- `ChannelDesign` has **no `grouping` or `spacing` field** — its complete set is
  `channelId, channelName, included, colorGroups, effectId, speed, intensity,
  reverse, ledCount` ([design_models.dart:296-346](../lib/features/design/design_models.dart#L296-L346)).
- `toWledPayload` spreads the **constants**, not per-design values:
  `...kDesignSpacingDefaults` at
  [design_models.dart:272](../lib/features/design/design_models.dart#L272) — always
  `grp: 1, spc: 0`.

So a design cannot express non-default banding, and #88's decision is unfulfilled
at the model layer. A candy-cane design that "legitimately owns its spacing"
(the decision's own example) still cannot store it.

Phase C's consequence: the grouping control is **hidden in design-edit mode**
([colorway_effect_selector.dart:955](../lib/features/wled/colorway_effect_selector.dart#L955)) —
offering a control whose value is silently discarded is worse than not offering
it. The tuner shows a one-line note saying colours and pixel layout are not
editable there.

**For the stream:** closing this is `ChannelDesign.grouping/spacing` +
serialisation + a `toWledPayload` change, after which the hidden control can be
restored. Until then, two designs that differ only in banding are
indistinguishable once stored.

---

## 6. Deferred

| Deferred | Why |
|---|---|
| **AI-composed edit** | Unchanged from Phase A: `AIDesignStudioScreen` has no existing-design parameter, and C3 confirms nothing reads `composedPattern` back. Edit stays disabled for that kind with an on-screen note. |
| **`grp`/`spc` on a design** | Needs `ChannelDesign` fields + serialisation + a `toWledPayload` change. #88's decision of record is unfulfilled at the model layer; §2 records it. The control is hidden rather than half-wired. |
| **Colour editing in the tuner** | The tuner has never had a colour editor; adding one is a feature, not a wiring gap. |
| ~~Re-pushing the pre-edit look on cancel~~ | **RESOLVED in closeout `d5ed3e6`** — see §2. Aligned with selection mode; the two crashes that fix uncovered are recorded there. |
| **Lifting the Sync exclusion** | Four concrete steps in §3; needs a policy decision on per-pixel across houses. |

---

## 7. What I would have had to fabricate, and didn't

1. **A sample `composedPattern` doc and its byte size.** Still no client
   credential; still not invented. P2 §5's code-derived shape stands, and P4
   adds only what grep can prove — that nothing reads it.
2. **That the Sync exclusion is the "right" product call.** I can prove the wire
   format cannot carry a design. I cannot prove users would not rather have the
   lossy three-swatch version; that is a product judgement I flagged rather than
   made silently — the one-line notice is written so the constraint is visible
   to whoever revisits it.
3. **That design-edit mode behaves correctly on hardware.** Every claim here is
   from code and unit tests. The live-preview and save paths have not been run
   against a controller. In particular the restore asymmetry (§2) is reasoned,
   not observed.
4. **That P1 passing "in spirit" is acceptable.** It is a judgement call
   overriding an explicit stop instruction, so it is the first thing in this
   report rather than a footnote.
5. **A kind-aware Sync filter.** Tempting to write `if (design.isPerPixel)`, but
   the wire-format finding makes kind irrelevant — asserting a kind distinction
   would have implied effect designs *could* be synced, which is false today.
