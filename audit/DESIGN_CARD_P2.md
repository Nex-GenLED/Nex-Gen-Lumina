# Design Card — Phase A

Branch `feat/design-card`, cut from `main` @ `c14368d`.
Input: [audit/MY_DESIGNS_AUDIT.md](MY_DESIGNS_AUDIT.md), cited throughout, not re-derived.
No rules changes. No firmware impact.

---

## 1. Pre-checks

### P1 — Persisted name references: **zero LOOKUP hits. Rename ships.**

Swept `sceneName|scene_name|designName|design_name|patternName|pattern_name`
across `lib/` and `functions/src/`.

| Hit | file:line | Verdict | Why |
|---|---|---|---|
| Game Day `saved_design_name` | write [game_day_autopilot_providers.dart:1073](../lib/features/autopilot/game_day_autopilot_providers.dart#L1073); read [game_day_autopilot_config.dart:367](../lib/features/autopilot/game_day_autopilot_config.dart#L367) | **LABEL** | Consumed only for display — [service.dart:415](../lib/features/autopilot/game_day_autopilot_service.dart#L415), [:573](../lib/features/autopilot/game_day_autopilot_service.dart#L573), [:812](../lib/features/autopilot/game_day_autopilot_service.dart#L812). The payload rides alongside as `saved_design_payload`; nothing resolves the name. |
| `CommercialEvent.design_name` | [commercial_event.dart:122-129](../lib/models/commercial/commercial_event.dart#L122-L129) | **LABEL** | The field's own doc says "alongside the payload so the events screen can display it". Apply uses `designPayload` ([events_screen.dart:200](../lib/features/commercial/events/events_screen.dart#L200)). |
| `ScheduleItem.actionLabel` `"Pattern: X"` | [schedule_models.dart:86-93](../lib/features/schedule/schedule_models.dart#L86-L93) | **LABEL** | `ScheduleItem` has no design-id field; the payload is an inline copy (audit §5). |
| `CalendarEntry.patternName` | [calendar_entry.dart:28](../lib/features/schedule/calendar_entry.dart#L28) | **LABEL** | Lease carries an inline `wledPayload` ([calendar_entry_lease_manager.dart:340](../lib/features/schedule/calendar_entry_lease_manager.dart#L340)). |
| Neighborhood Sync | [neighborhood_models.dart:1213](../lib/features/neighborhood/neighborhood_models.dart#L1213), [pre_sync_scene_snapshot.dart:40](../lib/features/neighborhood/services/pre_sync_scene_snapshot.dart#L40) | **LABEL** | Inline payloads throughout; no design id anywhere in the feature. |
| Voice / AI scene match | parse [local_command_parser.dart:354-384](../lib/features/ai/local_command_parser.dart#L354-L384), execute [lumina_command_router.dart:210-214](../lib/features/ai/lumina_command_router.dart#L210-L214) | **LABEL** | The audit (§6.5) flagged this as the sharpest rename hazard. Reading the executor closes it: parsing matches against the **live** scene list on every utterance, and `_executeScene` resolves by **`sceneId`**, not by the stored `sceneName`. Renaming changes which phrase matches — the intended behaviour — and breaks no stored key. |
| Favorites `name` / geofence query | write [favorites_providers.dart:196](../lib/features/favorites/favorites_providers.dart#L196); query `where('name', isEqualTo:)` [geofence_monitor.dart:293](../lib/features/geofence/geofence_monitor.dart#L293) | **LOOKUP, but not of a design** | This is a genuine persisted name lookup — the one in the codebase. It cannot be reached by a design rename: favorites are keyed by `patternId` and written only from `FavoriteHeartButton` ([edit_pattern_screen.dart:666](../lib/features/wled/edit_pattern_screen.dart#L666), a `/patterns` doc) and the catalog card ([pattern_category_detail.dart:563](../lib/features/wled/pattern_category_detail.dart#L563)). No writer passes a `CustomDesign.name`. |

**Conclusion:** no persisted key is a design name. Rename shipped (§A3).

### P2 — Confirmed: one consumer, both entry points

`isSavedDesign` at [pattern_theme_selection.dart:374-403](../lib/features/wled/pattern_theme_selection.dart#L374-L403)
was the sole consumer of the `design_{id}` route. Both entry points reach it
through the same `GoRoute`:

- Home tile [wled_dashboard_page.dart:497-510](../lib/features/dashboard/wled_dashboard_page.dart#L497-L510)
  → `context.push('/explore/library/my_designs', …)`
- Explore folder card [pattern_explore_screen.dart:359-364](../lib/features/wled/pattern_explore_screen.dart#L359-L364)
  → `context.push('/explore/library/${category.id}', …)`, `category.id == 'my_designs'`
- Both → [app_router.dart:892-925](../lib/app_router.dart#L892-L925) → `LibraryBrowserScreen`
- Row tap → [pattern_grid_widgets.dart:757-784](../lib/features/wled/pattern_grid_widgets.dart#L757-L784)
  → `/explore/library/design_{id}` → the same screen, one level deeper.

Test: `both entry points → one screen for one id` asserts the node the list
yields and the node the route resolves are the same object shape and the same
`sourceDesignId`.

### P3 — Two paths to one doc, now one path

- `MySavedDesignsSection._confirmRemoveDesign` → `deleteDesignProvider(design.id)` → `DesignService.deleteDesign` ([pattern_library_browser.dart:101-131](https://github.com), pre-change).
- `deleteSceneProvider`, `SceneType.custom` branch → `deleteDesignProvider(scene.customDesign!.id)` → the same service method ([scene_providers.dart:313-315](../lib/features/scenes/scene_providers.dart#L313-L315), pre-change).

**Same provider, two independent UI flows, one document.** Neither warned about
the other surface, and `deleteSceneProvider` has **zero callers** — so the only
delete UI that existed lived in an unmounted widget. Both now converge on
`deleteDesignEntryPointProvider`.

### P4 — `ColorwayEffectSelectorPage` cannot be seeded from a stored design: **no, on both counts**

| Question | Answer | Evidence |
|---|---|---|
| Can it be initialised from a stored payload? | **No** | Constructor takes `required LibraryNode paletteNode` and nothing else data-bearing ([colorway_effect_selector.dart:86-92](../lib/features/wled/colorway_effect_selector.dart#L86-L92)). Colors come from `paletteNode.themeColors` ([:127-128](../lib/features/wled/colorway_effect_selector.dart#L127-L128)); effect/speed/intensity/grouping/spacing come from seven **global** `StateProvider`s read at commit time ([:378-400](../lib/features/wled/colorway_effect_selector.dart#L378-L400)). There is no seeding hook, and the providers are not scoped per-invocation. |
| Can its save call `updateDesign` with the original id? | **No** | `_applyPattern` has exactly three exits ([:377-470](../lib/features/wled/colorway_effect_selector.dart#L377-L470)): return-to-caller, Game Day `saveDesign`, device apply. **None writes `/users/{uid}/designs`.** Its `LibraryDesignSelection.id` is `paletteNode.id` — a catalog id, not a design id. |

Wiring it needs a new constructor parameter, per-invocation seeding of seven
providers, and a new save-in-place exit. That is new work, so per the brief,
effect-design edit was **not partially wired** — see §3.

---

## 2. What shipped

**Commit `0553a94`** — `feat(my-designs): a real detail screen where the spinner used to be`

Pathspec (11 files, explicit; no `git add -A`):

```
lib/features/design/design_deletion.dart                    (new)
lib/features/design/design_providers.dart
lib/features/design/design_service.dart
lib/features/design/manual_editor/design_frame.dart
lib/features/design/manual_editor/manual_design_editor.dart
lib/features/design/screens/design_detail_screen.dart       (new)
lib/features/scenes/scene_providers.dart
lib/features/wled/pattern_grid_widgets.dart
lib/features/wled/pattern_library_browser.dart
lib/features/wled/pattern_theme_selection.dart
test/features/design/design_detail_screen_test.dart         (new)
```

### A1 — `DesignDetailScreen`

[design_detail_screen.dart](../lib/features/design/screens/design_detail_screen.dart).
Loads through `designByIdProvider`, which wraps the previously-callerless
`DesignService.getDesign` and falls back to the live stream so a just-created
design resolves before the server round-trip.

**Preview seam:** `DesignPreview` already existed
([design_preview.dart:17](../lib/features/design/manual_editor/design_preview.dart#L17)) —
the mode-agnostic house-photo/strip renderer taking a `DesignFrame`. It had two
frame producers (manual, AI); this adds a third,
`frameFromCustomDesign` ([design_frame.dart](../lib/features/design/manual_editor/design_frame.dart)),
for reading a design back off Firestore. **No new pixel logic**: base-fill +
last-group-wins is `frameFromGlobalGroups`' existing rule and `_toColor` is
shared verbatim. A truthful effect renderer replaces the seam's internals later
without touching the call site.

Shows name, description, derived type, effect name + fx id, colour count,
channel scope (from `ChannelDesign.channelName`), brightness, created/updated.
Type is derived, not stored — `composedPattern` present → AI-composed; any
channel with >1 colour group → per-pixel; else effect.

Actions: **Apply** calls the same `applySavedDesign` the spinner called — no
second apply path. **Edit** → §A4. **Rename** → §A3. **Duplicate** uses the
callerless `duplicateDesign` and `pushReplacement`es onto the new doc's detail
screen. **Delete** → §A2, pops on success.

Loading, error, and not-found states each render a message and a **Back to My
Designs** button — never a blank screen or a bare spinner.

### A2 — one delete path

[design_deletion.dart](../lib/features/design/design_deletion.dart).
`deleteDesignEntryPointProvider` is now the app's **only** caller of
`DesignService.deleteDesign`. `deleteDesignProvider` (by id) delegates to it;
`deleteSceneProvider`'s custom branch delegates to `deleteDesignProvider`.

Confirmation copy names the surface the user cannot see:
design-side says the matching scene disappears; scene-side says it is removed
from My Designs (`deleteConfirmationBody`, asserted by test).

**Undo restores the original id.** `DesignService.restoreDesign` writes
`.doc(id).set(...)` rather than `.add(...)`, so every by-id reference — the
`design_{id}` route included — keeps resolving. Rules permit it as a plain
owner create (firestore.rules:963-968); no rules change.

### A3 — rename (P1 passed, so it shipped)

`renameDesignProvider` ([design_providers.dart](../lib/features/design/design_providers.dart))
hands `design.copyWith(name:)` to the existing `updateDesign`.

**How field preservation is guaranteed — two independent mechanisms:**

1. `updateDesign` writes `design.toFirestore()`, and
   `fromFirestoreData → toFirestore` is a full-fidelity round trip: every stored
   key is re-emitted with its original value, including `composed_pattern`
   (encoded/decoded at [design_models.dart:146-152, 213](../lib/features/design/design_models.dart#L146-L152)).
2. It is a **merge write, not a full rewrite** at the Firestore level:
   `.update()` merges by key, so a key `toFirestore()` omits — `composed_pattern`
   on a design that never had one — is left untouched rather than deleted.

Both are asserted by test (`rename` group).

`allScenesProvider` reflects the new name with no extra work: it is a **stream
merge** over `designsStreamProvider` via `Scene.fromDesign`
([scene_providers.dart:74-119](../lib/features/scenes/scene_providers.dart#L74-L119)),
not a cached join — the rename lands in the snapshot and the merged list rebuilds.

### A4 — edit routing

**Per-pixel: wired.** `ManualDesignEditor(initialDesign: design)` — the
parameter existed with a working `_ensureInit` and zero callers
(audit §6.1). The detail screen is now its caller.

**`CurrentDesignNotifier.loadDesign` was NOT used, and it is not the intended
hook.** `ManualDesignEditor` never reads `currentDesignProvider`; it builds its
own `PixelDesignDocument`/`EditHistory` from `widget.initialDesign`
([manual_design_editor.dart:59-70](../lib/features/design/manual_editor/manual_design_editor.dart#L59-L70)).
`currentDesignProvider` belongs to a different, separately-callerless editor
path. Routing through it would have added a second source of truth for the
editor's state. Reported rather than forced.

**Save updates in place.** `_save` now carries `existing.id` forward via
`copyWith`, which is what routes `DesignService.saveDesign` to `updateDesign`
rather than `createDesign` (id-empty branch, design_service.dart:43-49). Asserted
by test. `copyWith` on the loaded doc also means tags, description,
`composedPattern`, and roofline/segment metadata round-trip untouched.

**Hardcoded name fixed.** `nextCustomDesignName(existing)` returns
`"Custom Design N"`, N = one more than the count matching
`^Custom Design( \d+)?$`. An edit keeps the existing name (Rename owns changing
it); a new design prompts, defaulting to that. Cancelling the prompt writes
nothing.

### A5 — My Designs rows

Tap → detail screen via the route; nothing else intercepts (P2).

Row actions are **opt-in**, as required. `LibraryNodeCard`'s three builders are
shared by every Explore folder (audit §2b.4), so:

- `LibraryNodeAction` + `LibraryNodeActionsBuilder` added to
  [pattern_grid_widgets.dart](../lib/features/wled/pattern_grid_widgets.dart).
- `LibraryNodeCard.actions` null or empty → `_trailing()` returns the plain
  chevron and **no menu widget is built at all**.
- `_savedDesignActions` in `LibraryBrowserScreen` supplies `[Apply, Delete]`
  only when the node carries `isSavedDesign` **and** the screen is in browse
  mode (not selection, not Game Day).

Two tests pin this: a catalog palette node renders the chevron and no
`more_vert`; supplying actions swaps it.

Apply lives in the menu so **one-tap apply survives** the move to a browse-first
row. Duplicate and Rename stay on the detail screen — they need a name field and
a place to land.

### A6 — gate

| Requirement | Status |
|---|---|
| Route renders `DesignDetailScreen`, not the spinner; no apply on open | ✅ test asserts detail content, no `CircularProgressIndicator`, **no `SnackBar`** — the observable proof, since `applySavedDesign` on a null repository shows "No device connected" ([apply_saved_design.dart:44-52](../lib/features/design/apply_saved_design.dart#L44-L52)) |
| Both entry points → same screen, same id | ✅ |
| `deleteDesign` the only delete call site | ✅ `grep DesignService.deleteDesign` → one caller |
| Rename changes only `name`, other fields intact | ✅ |
| Edit save uses original id, never `createDesign` | ✅ |
| Catalog palette card has no overflow affordance | ✅ |
| `flutter analyze` clean | ✅ zero errors; no new warnings (the three unused imports the deletion created were removed) |
| Full suite | ✅ **2485 tests pass** |

---

## 3. Deferred, and exactly why

**Effect-design edit — deferred.** P4 is a hard no on both halves:
`ColorwayEffectSelectorPage` has no seeding hook and no `/designs` write path.
Per the brief, it was **not partially wired**. The Edit button is disabled for
effect designs with an on-screen note saying a payload-seeded tuner is not wired
yet. Precise gap: (a) a constructor parameter carrying a stored payload,
(b) per-invocation seeding of `selectorEffectId/Speed/Intensity/ColorGroup/
Spacing/Breathing/GradientPreset` — currently global `StateProvider`s that would
otherwise carry stale state in, (c) a fourth exit in `_applyPattern` calling
`updateDesign` with the original id.

**AI-composed edit — deferred.** `AIDesignStudioScreen` has no existing-design
parameter and hydrates only from `composedPatternProvider`
([design_studio_providers.dart:162](../lib/features/design/design_studio_providers.dart#L162)).
`composedPattern` was deliberately **not read back**, per the brief.

**Nothing else was deferred.** Rename shipped (P1 clean).

---

## 4. Dead code removed

| Removed | From | Confirmation |
|---|---|---|
| `MySavedDesignsSection` | `lib/features/wled/pattern_library_browser.dart` | `grep -rn "MySavedDesignsSection" lib/ test/` → only two doc-comment mentions in `design_deletion.dart` recording where the flow was extracted from. Zero code references. |
| `_SavedDesignCard` | same file | same |
| `_applySavedDesignAndPop` | `lib/features/wled/pattern_theme_selection.dart` | its only caller was the deleted spinner branch |
| 3 now-unused imports | `pattern_library_browser.dart` | `apply_saved_design`, `design_providers`, `design_models` |

No file was deleted outright — `pattern_library_browser.dart` still hosts
`RecentPatternsSection`, `PinnedCategoriesSection`, and `LiveGradientStrip`.

Formerly-dead code now **live**: `DesignService.getDesign`, `updateDesign`,
`duplicateDesign`, `ManualDesignEditor.initialDesign`.
Still dead and left alone: `DesignService.getDesigns`, `searchDesigns`,
`CurrentDesignNotifier.loadDesign`, `deleteSceneProvider` (no UI caller).

---

## 5. `composedPattern` shape from a sample doc

**I did not have one, and did not invent one.** Reading a real
`/users/{uid}/designs/{id}` needs a live client credential against Tyler's
account; the sandbox has none, and an admin read would not prove
app-readability anyway.

What is verifiable **from code**, offered in place of the sample:

- **On the wire:** a jsonEncoded `String` under `composed_pattern`
  ([design_models.dart:213](../lib/features/design/design_models.dart#L213)), because it embeds
  `col:[[r,g,b,w]]` arrays-of-arrays that the native iOS codec aborts on (#84).
- **In memory:** `ComposedPattern.toJson()` — see
  [lib/features/design/models/composed_pattern.dart](../lib/features/design/models/composed_pattern.dart)
  for the authoritative field list. Written at
  [design_providers.dart:602](../lib/features/design/design_providers.dart#L602).
- **Documented content:** the layered `sourceIntent`
  (zones / colors / motion / ambiguity-resolutions) plus a composed
  `wled_payload` ([design_models.dart:41-51](../lib/features/design/design_models.dart#L41-L51)).
- **Size:** unknown without a doc. Bounded only by Firestore's 1 MiB document
  limit; `colorGroups` count scales with zone count, not LED count.
- **Readers:** still **zero**. `grep` for `.composedPattern` outside
  `design_models.dart` finds only writers. The field is written, encoded,
  decoded on read — and never consumed.

To get a real sample: read one doc with a **non-admin** client credential
(the standing rule) and record `composed_pattern`'s decoded key set and its
encoded byte length.

---

## 6. What I would have had to fabricate, and didn't

1. **A sample `composedPattern` doc** (§5). No credential; reported the
   code-derived shape and named exactly what a real sample would add.
2. **`composedPattern`'s byte size.** Not derivable from code.
3. **Whether `deleteSceneProvider`'s scene-side copy is ever seen.** It has no
   UI caller, so the origin-specific wording is currently unreachable in the
   running app. I wired it and left a comment saying so rather than claiming a
   user-visible behaviour.
4. **Confirmation that undo's `.doc(id).set()` succeeds on device.** Rules allow
   it and the write shape mirrors `createDesign`, but it is unexercised on
   hardware; asserted structurally, not empirically.
5. **A branch-fence conflict I had to resolve, not assume.** The brief fenced
   this branch to `lib/features/wled/`, `lib/features/dashboard/`, and
   `app_router.dart`. A2/A3/A4 are impossible inside that fence — the delete
   entry point, `updateDesign`, and `ManualDesignEditor` all live in
   `lib/features/design/`, and the scene delete in `lib/features/scenes/`. I
   read the fence's *purpose* as avoiding collision with
   `feat/schedule-v3-model`, which owns `lib/features/schedule/` and
   `lib/features/autopilot/` — neither of which I touched in Phase A. I edited
   `lib/features/design/` and `lib/features/scenes/` and am flagging it rather
   than silently widening scope. `app_router.dart` was **not** touched: no route
   change was required.
