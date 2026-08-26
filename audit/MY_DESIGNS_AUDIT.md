# My Designs — Read-Only Audit

**Scope:** app-side discovery only. No files modified outside this document, no
commits, no `flutter analyze` / `flutter test` run. Firmware untouched
(v1.0.0-firmware-phase-1 frozen).

---

## 1. Branch and HEAD

| | |
|---|---|
| Branch | `main` |
| HEAD | `c14368d9c4e40d1722afce015ad7b2e46090f967` (`c14368d`) |

---

## 2. Source and model table (Task 1)

### 2.1 Entry point

The home-screen "My Designs" button is a **fallback tile** — it only renders when
the controller does not advertise AudioReactive (or outside debug builds):

- [wled_dashboard_page.dart:497-510](lib/features/dashboard/wled_dashboard_page.dart#L497-L510)
  → `context.push('/explore/library/my_designs', extra: {'name': 'My Designs'})`

There is a second, identical entry point from the Explore "See all" button in
[pattern_library_browser.dart:54-59](lib/features/wled/pattern_library_browser.dart#L54-L59).

A third alias exists in the AI command parser
([local_command_parser.dart:83-84](lib/features/ai/local_command_parser.dart#L83-L84))
pointing at `/dashboard/my-designs`. **That route does not exist** — no
`GoRoute` in [app_router.dart](lib/app_router.dart) declares it, and the screen
it once referred to (`MyDesignsScreen`, still named in a comment at
[apply_saved_design.dart:16](lib/features/design/apply_saved_design.dart#L16))
has been deleted. See UNKNOWNS.

### 2.2 Route → screen

`/explore/library/:nodeId` →
[app_router.dart:892-925](lib/app_router.dart#L892-L925) → `LibraryBrowserScreen`
([pattern_theme_selection.dart:199-204](lib/features/wled/pattern_theme_selection.dart#L199-L204)).

There is **no dedicated My Designs screen**. `my_designs` is a *synthetic
category id* injected into the generic Explore library hierarchy:

- id constant: `kMyDesignsCategoryId = 'my_designs'`
  ([pattern_providers.dart:52](lib/features/wled/pattern_providers.dart#L52))
- synthetic category node: [pattern_providers.dart:57-62](lib/features/wled/pattern_providers.dart#L57-L62)
- child-node branch: [pattern_providers.dart:570-577](lib/features/wled/pattern_providers.dart#L570-L577)
- node-by-id branch: [pattern_providers.dart:587-604](lib/features/wled/pattern_providers.dart#L587-L604)
- ancestors branch: [pattern_providers.dart:610-616](lib/features/wled/pattern_providers.dart#L610-L616)

### 2.3 Stores read

| Store | Path | Read by | Shape |
|---|---|---|---|
| Firestore | `/users/{uid}/designs/{autoId}` | `designsStreamProvider` ([design_providers.dart:20-26](lib/features/design/design_providers.dart#L20-L26)) → `DesignService.streamDesigns` ([design_service.dart:76-84](lib/features/design/design_service.dart#L76-L84)) | `CustomDesign` |

**That is the only store the My Designs list reads.** No local store, no
`patterns` subcollection, no `scenes` subcollection, no `favorites`, no brand
library. The `LibraryNode` rows are adapted from `CustomDesign` in memory by
`_customDesignToLibraryNode` ([pattern_providers.dart:69-90](lib/features/wled/pattern_providers.dart#L69-L90)).

### 2.4 Row model — exactly one type

Every row is a `CustomDesign` ([design_models.dart:10-74](lib/features/design/design_models.dart#L10-L74)).
The surface **does not union** multiple types; it is single-typed, then
*downcast* to `LibraryNode` for rendering. Fields carried by `CustomDesign`:

| Field | Firestore key | Notes |
|---|---|---|
| `id` | doc id | |
| `name` | `name` | stored, editable in principle |
| `description` | `description` | never surfaced in any UI |
| `createdAt` / `updatedAt` | `created_at` / `updated_at` | `updated_at` is the sort key |
| `ownerId` | | |
| `channels: List<ChannelDesign>` | `channels` | per-channel colorGroups + fx/speed/intensity/reverse/ledCount |
| `brightness` | | 0–255 |
| `tags: List<String>` | | never surfaced |
| `rooflineConfigId` | | |
| `isSegmentAware`, `templateType`, `segmentColorGroups`, `segmentPatternConfig` | | segment-aware pattern metadata |
| `composedPattern` | `composed_pattern` | **jsonEncoded String** on the wire (#84 arrays-of-arrays); AI source-of-truth |

**Discriminator carried into the row:** `metadata: {'isSavedDesign': true,
'sourceDesignId': design.id}` ([pattern_providers.dart:85-88](lib/features/wled/pattern_providers.dart#L85-L88)).
The adapter drops everything except `name` and up to 3 preview colors —
`themeColors` is built from the first ≤2 colorGroups of the first included
channels. Description, tags, timestamps, brightness, and `composedPattern`
never reach the row.

### 2.5 Writers — five distinct kinds of design, one collection

All write through `DesignService.saveDesign` into the same collection, so the
list is heterogeneous in *content* while homogeneous in *type*:

| Writer | Call site | What it stores |
|---|---|---|
| Now Playing "Save Custom" | `saveCurrentAsDesignProvider` [design_providers.dart:462-511](lib/features/design/design_providers.dart#L462-L511) | one colorGroup per segment from live `wledStateProvider`; solid color + fx/speed/intensity |
| Current-colors editor | [current_colors_provider.dart:223-277](lib/features/wled/current_colors_provider.dart#L223-L277) | same shape as Now Playing |
| Design Studio — manual (per-pixel) | `ManualDesignEditor._save` [manual_design_editor.dart:237-266](lib/features/design/manual_editor/manual_design_editor.dart#L237-L266) | full per-pixel coverage flattened into `channels[].colorGroups`. **Name hardcoded `'Custom Design'` — no naming dialog.** |
| Design Studio — AI | `saveComposedDesignProvider` [design_providers.dart:611-632](lib/features/design/design_providers.dart#L611-L632) | derived `channels` **plus** `composedPattern` (the AI `sourceIntent`) |
| Colorway/Explore selector | [colorway_effect_selector.dart:485-497](lib/features/wled/colorway_effect_selector.dart#L485-L497) | **does NOT write `/designs`** — Game Day path only (`teamSlug != null`), writes `GameDayAutopilotConfig`. Listed to rule it out. |

**Payload representation:** none of these store a `wledPayload` field. Every
`CustomDesign` stores **structured channels**, and the WLED payload is *derived
at apply time* by `CustomDesign.toWledPayload()`. The per-pixel case is not a
blob either — it is flattened to `LedColorGroup` runs. The one exception is
`composedPattern`, which does embed a `wled_payload` inside the jsonEncoded AI
map, but that field has **no reader anywhere in `lib/`** (see §6.2).

### 2.6 Sort order and read mode

- **Stream** (`StreamProvider` over `.snapshots()`), live.
- Ordered `updated_at DESC` at the query
  ([design_service.dart:78-79](lib/features/design/design_service.dart#L78-L79)).
- The `LibraryNode` adapter sets no `sortOrder`, so grid order is stream order.
- The generic grid decides list-vs-grid by `mostlyPalettes`
  ([pattern_grid_widgets.dart:71-73](lib/features/wled/pattern_grid_widgets.dart#L71-L73)); saved designs are
  all `LibraryNodeType.palette`, so My Designs always renders as the **44px
  single-column compact list**, not the 2-column hero grid.

---

## 2b. Two entry points, one folder? (Task 1b)

### 2b.1 What each entry point resolves to

| Entry point | file:line | Pushes |
|---|---|---|
| Home screen "My Designs" tile | [wled_dashboard_page.dart:497-510](lib/features/dashboard/wled_dashboard_page.dart#L497-L510) | `context.push('/explore/library/my_designs', extra: {'name': 'My Designs'})` |
| Explore Patterns root grid → "My Designs" folder card | `_FolderHeroCard` onTap, [pattern_explore_screen.dart:359-364](lib/features/wled/pattern_explore_screen.dart#L359-L364) | `context.push('/explore/library/${category.id}', extra: {'name': category.name})` — with `category.id == 'my_designs'`, `category.name == 'My Designs'` |
| (Explore "See all", third path) | [pattern_library_browser.dart:54-59](lib/features/wled/pattern_library_browser.dart#L54-L59) | same string literal as the home tile — but the widget that hosts it is never mounted (§4.1) |

Both live paths resolve through the **same** `GoRoute` —
`/explore/library/:nodeId`, [app_router.dart:892-925](lib/app_router.dart#L892-L925) — to the
**same widget**, `LibraryBrowserScreen(nodeId: 'my_designs', nodeName: 'My Designs')`.

### 2b.2 Same screen, and the same provider

Not "two screens reading the same data" — **one screen, one route, one
provider**. The two call sites differ only in the literal that produces the
`extra` map, and both produce `{'name': 'My Designs'}`. Everything downstream —
`libraryChildNodesProvider('my_designs')` → `designsStreamProvider` → the
`_customDesignToLibraryNode` adapter → `LibraryNodeGrid` → `LibraryNodeCard` — is
byte-identical.

**One real behavioural difference, and it is navigational, not visual.** The
router is a `StatefulShellRoute.indexedStack`
([app_router.dart:757](lib/app_router.dart#L757)) and `/explore/library/:nodeId`
declares `parentNavigatorKey: _exploreNavigatorKey`
([app_router.dart:896](lib/app_router.dart#L896)), inside Branch 2 — EXPLORE
([app_router.dart:875-877](lib/app_router.dart#L875-L877)). Pushing it from the
home tile therefore **switches the active shell branch from Home to Explore**.
Backing out of My Designs lands the user on the Explore tab, not the dashboard
they started from. From the Explore entry point the branch is already correct,
so the same push is a no-op on tab state.

### 2b.3 Is My Designs a LibraryNode folder in the Explore tree?

**No — and this is the part that surprises.** The app maintains *two parallel
catalog trees*, and `my_designs` is synthesised into one of them but not the
other:

| Tree | Type | Backing | Root read | Contains `my_designs`? |
|---|---|---|---|---|
| Category list | `PatternCategory` | `PatternRepository._categories`, a `static const` list ([pattern_repository.dart:403](lib/features/wled/pattern_repository.dart#L403)), served by `getCategories()` ([659-662](lib/features/wled/pattern_repository.dart#L659-L662)) | `patternCategoriesProvider` ([pattern_providers.dart:98-116](lib/features/wled/pattern_providers.dart#L98-L116)) | **Yes** — prepended at runtime, unconditionally |
| Node hierarchy | `LibraryNode` | `PatternRepository._allNodes` ([704-707](lib/features/wled/pattern_repository.dart#L704-L707)) ← `_buildFullHierarchy()` ([711+](lib/features/wled/pattern_repository.dart#L711)) from static builders (Sports/Holiday/Seasonal/Party/Movies/Nature/Architectural/Security) | `libraryChildNodesProvider(null)` → `getChildNodes(null)` ([1165-1171](lib/features/wled/pattern_repository.dart#L1165-L1171)) | **No** — `_buildRootCategories()` ([787-845](lib/features/wled/pattern_repository.dart#L787)) returns exactly 8 nodes: `cat_sports`, `cat_holiday`, `cat_season`, `cat_party`, `cat_movies`, `cat_arch`, `cat_security`, `cat_nature` |

So:

- **Populated at runtime from a user collection**, not real docs in the library.
  `patternCategoriesProvider` prepends a hand-built
  `PatternCategory(id: 'my_designs', name: 'My Designs', imageUrl: '')`
  ([pattern_providers.dart:110-116](lib/features/wled/pattern_providers.dart#L110-L116)) — **always**,
  even for guests and empty accounts. The comment there records this as
  deliberate (#85): always-render means writer-drift can only make the surface
  look *empty*, never *vanish*.
- The **children** are equally virtual: `libraryChildNodesProvider` special-cases
  the id before ever touching the repository
  ([pattern_providers.dart:570-577](lib/features/wled/pattern_providers.dart#L570-L577)), mapping
  `CustomDesign` → `LibraryNode` in memory. Same for node-by-id
  ([587-604](lib/features/wled/pattern_providers.dart#L587-L604)) and ancestors
  ([610-616](lib/features/wled/pattern_providers.dart#L610-L616)). Three
  `if`-branches wrap the real repository; nothing is persisted into the library.
- **Leaf handler inherited:** rows are emitted as `LibraryNodeType.palette`
  ([pattern_providers.dart:81](lib/features/wled/pattern_providers.dart#L81)), so they inherit the
  generic palette-leaf rendering and tap handling —
  `LibraryNodeGrid` → `LibraryNodeCard._buildPaletteCard`.

### 2b.4 The generic leaf onTap — and why the fix is *not* automatically global

There are three card builders in `LibraryNodeCard`, and all three have
**structurally identical** onTaps. None has an `onLongPress` or overflow menu:

| Builder | onTap | Used for |
|---|---|---|
| `_buildPaletteCard` | [pattern_grid_widgets.dart:757-784](lib/features/wled/pattern_grid_widgets.dart#L757-L784) | **all palette leaves, including every saved design** |
| `_buildFolderCard` | [pattern_grid_widgets.dart:606-634](lib/features/wled/pattern_grid_widgets.dart#L606-L634) | subfolders |
| `_buildCompactFolderCard` | [pattern_grid_widgets.dart:507-534](lib/features/wled/pattern_grid_widgets.dart#L507-L534) | architectural compact folders |

Each does the same two-way branch: selection/Game Day mode → root-navigator
`MaterialPageRoute` to a new `LibraryBrowserScreen`; plain browse →
`context.push('/explore/library/${node.id}', …)`. **The leaf tap never applies
anything and never opens a detail card — for any node in Explore. It only
recurses into another `LibraryBrowserScreen`.**

That makes `_buildPaletteCard`'s onTap the shared root, but the *divergence*
happens one level down, inside `LibraryBrowserScreen.build`, where three
mutually exclusive branches decide what a palette node becomes
([pattern_theme_selection.dart:374-403](lib/features/wled/pattern_theme_selection.dart#L374-L403)):

1. `node.metadata?['isSavedDesign'] == true` → **spinner + apply + pop**
   ([374-395](lib/features/wled/pattern_theme_selection.dart#L374-L395)) — saved designs only.
2. `node.isPalette` → **`ColorwayEffectSelectorPage`**
   ([396-403](lib/features/wled/pattern_theme_selection.dart#L396-L403)) — every catalog palette,
   i.e. a real tuner screen with preview, effect grid, and apply.
3. otherwise → `LibraryNodeGrid` of children.

So catalog leaves *do* get a detail-ish surface (branch 2); saved designs are
the one node class deliberately routed around it (branch 1, whose comment says
so explicitly). **A fix aimed at branch 1 would be scoped to My Designs; it
would not touch any other Explore folder.** Conversely, adding a long-press or
overflow to `LibraryNodeCard` *would* affect every folder in Explore, since all
three builders are shared — that is the piece to keep deliberate.

### 2b.5 Behavioural differences between the paths

Card, row widget, sort, and apply behaviour are **identical** across the two
entry points (same route, same widget, same providers). The differences that do
exist are about *reachability elsewhere in the app*:

| # | Difference | Evidence |
|---|---|---|
| 1 | **Home tile silently changes tab.** Push crosses from the Home branch into the Explore branch of the indexed stack; back-out lands on Explore. | [app_router.dart:757](lib/app_router.dart#L757), [875-896](lib/app_router.dart#L875-L896) |
| 2 | **The home tile is conditional.** It renders only when the controller lacks AudioReactive support *or* the build is non-debug — in a debug build on an audio-capable controller, the tile is replaced by "Audio Mode" and the home entry point disappears entirely. | [wled_dashboard_page.dart:492-510](lib/features/dashboard/wled_dashboard_page.dart#L492-L510) |
| 3 | **The schedule pattern picker omits My Designs.** It opens `LibraryBrowserScreen(nodeId: null)` ([my_schedule_page.dart:4300-4310](lib/features/schedule/my_schedule_page.dart#L4300-L4310)), whose children come from `getChildNodes(null)` → the 8 static root categories. `my_designs` is prepended only to the *`PatternCategory`* list, which that screen never reads. Its own comment claims it opens "top-level catalog + My Designs" ([my_schedule_page.dart:4291-4293](lib/features/schedule/my_schedule_page.dart#L4291-L4293)) — the code does not match. `_returnSavedDesignSelection` ([pattern_theme_selection.dart:272-298](lib/features/wled/pattern_theme_selection.dart#L272-L298)) exists to serve that picker and is unreachable from it. Marked as a claim about the picker, verified by reading only; not exercised on device. |
| 4 | **Saved designs are unsearchable.** `searchLibrary` iterates `_allNodes` and `_items` only ([pattern_repository.dart:1550-1584](lib/features/wled/pattern_repository.dart#L1550-L1584)); no branch consults `designsStreamProvider`. The Explore search bar cannot find a design by name. | same |
| 5 | **My Designs cannot be pinned.** `pinnedCategoriesProvider` resolves ids against `repo.getCategories()` — the raw static list, not `patternCategoriesProvider` ([pattern_providers.dart:357-379](lib/features/wled/pattern_providers.dart#L357-L379)) — so pinning `my_designs` would resolve to the `'Unknown'` fallback. | same |
| 6 | **Row layout differs from every other folder.** `LibraryNodeGrid` picks the compact 44px single-column list when `mostlyPalettes` ([pattern_grid_widgets.dart:71-90](lib/features/wled/pattern_grid_widgets.dart#L71-L90)); saved designs are all palettes, so My Designs alone never renders as the 2-column hero grid the other folders use. | same |

**Types shown vs omitted:** neither entry point omits anything relative to the
other — both show all `CustomDesign` docs and nothing else. The omission is at
the *tree* level (#3–#5 above): the surface is visible from the Explore root
grid and the home tile, and invisible to the node-tree root, to search, and to
pinning.

---

## 3. Tap handler and dormant methods (Task 2)

### 3.1 The tap does not apply. It *navigates*.

Row tap → `LibraryNodeCard._buildPaletteCard`:

- **[pattern_grid_widgets.dart:757-784](lib/features/wled/pattern_grid_widgets.dart#L757-L784)** — `InkWell.onTap`
  - browse mode (`teamSlug == null && onDesignSelected == null`):
    `context.push('/explore/library/${node.id}', extra: {...})` where
    `node.id == 'design_{firestoreId}'`
    ([pattern_grid_widgets.dart:778-783](lib/features/wled/pattern_grid_widgets.dart#L778-L783))
  - selection / Game Day mode: `Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(... LibraryBrowserScreen ...))`
    ([pattern_grid_widgets.dart:765-777](lib/features/wled/pattern_grid_widgets.dart#L765-L777))

The push lands on a **second `LibraryBrowserScreen`** whose `nodeId` is the
design node. That screen resolves the node, sees the discriminator, and
short-circuits:

- **[pattern_theme_selection.dart:374-395](lib/features/wled/pattern_theme_selection.dart#L374-L395)** — the saved-design intercept.
  `if (node.metadata?['isSavedDesign'] == true)` → renders
  `const Center(child: CircularProgressIndicator())` and schedules a
  post-frame callback that either
  - `_returnSavedDesignSelection(designId)` ([pattern_theme_selection.dart:272-298](lib/features/wled/pattern_theme_selection.dart#L272-L298)) in selection mode, or
  - `_applySavedDesignAndPop(designId)` ([pattern_theme_selection.dart:238-265](lib/features/wled/pattern_theme_selection.dart#L238-L265)) otherwise.
- `_applySavedDesignAndPop` → `applySavedDesign(context, ref, match)`
  ([apply_saved_design.dart:35-102](lib/features/design/apply_saved_design.dart#L35-L102)), the canonical
  6-step routine (sync-pause → U1 channel gate → `applyChannelFilter` →
  `repo.applyJson` → `applyPreviewSync` → `setLabelWithFingerprint`), then
  `context.pop()`.
- A one-shot guard `_savedDesignApplyKicked`
  ([pattern_theme_selection.dart:212](lib/features/wled/pattern_theme_selection.dart#L212)) prevents double-fire.

**This is the mechanism of the apply-only behaviour.** The destination the tap
navigates to is not a detail screen — it is a spinner that exists solely to run
apply and immediately pop. There is no place for a detail card to live, because
the "detail route" is already consumed by the apply side-effect.

### 3.2 No long-press, no overflow menu

`LibraryNodeCard` has **no `onLongPress`, no `PopupMenuButton`, no trailing
action** on any of its three card builders
([pattern_grid_widgets.dart:499-535](lib/features/wled/pattern_grid_widgets.dart#L499-L535),
[599-635](lib/features/wled/pattern_grid_widgets.dart#L599-L635),
[755-790](lib/features/wled/pattern_grid_widgets.dart#L755-L790)). Nothing is
"present but unreachable" at the card level — the affordances were never built
on this card.

### 3.3 Dormant repository methods (exist, no My Designs caller)

| Method | Definition | Called from |
|---|---|---|
| `DesignService.deleteDesign` | [design_service.dart:53-61](lib/features/design/design_service.dart#L53-L61) | via `deleteDesignProvider` ([design_providers.dart:446-459](lib/features/design/design_providers.dart#L446-L459)) — **2 callers, neither on the My Designs surface**: `MySavedDesignsSection._confirmRemoveDesign` ([pattern_library_browser.dart:101-131](lib/features/wled/pattern_library_browser.dart#L101-L131), unmounted — §4.1) and `deleteSceneProvider` ([scene_providers.dart:313-315](lib/features/scenes/scene_providers.dart#L313-L315)) |
| `DesignService.updateDesign` | [design_service.dart:31-39](lib/features/design/design_service.dart#L31-L39) | **no UI caller** — reachable only indirectly via `saveDesign` when `design.id` is non-empty, and every save site passes `id: ''` |
| `DesignService.duplicateDesign` | [design_service.dart:99-107](lib/features/design/design_service.dart#L99-L107) → `duplicateDesignProvider` [design_providers.dart:653-660](lib/features/design/design_providers.dart#L653-L660) | **zero callers** |
| `DesignService.searchDesigns` | [design_service.dart:111-118](lib/features/design/design_service.dart#L111-L118) | **zero callers** |
| `DesignService.getDesign` | [design_service.dart:64-72](lib/features/design/design_service.dart#L64-L72) | **zero callers** |
| `DesignService.getDesigns` | [design_service.dart:86-95](lib/features/design/design_service.dart#L86-L95) | **zero callers** |
| `CurrentDesignNotifier.loadDesign` / `setName` / `setDescription` / `setTags` / `updateChannel` … | [design_providers.dart:71-140](lib/features/design/design_providers.dart#L71-L140) | `loadDesign` has **zero callers** |

So a full CRUD surface — read-one, update, delete, duplicate, rename, search —
already exists at the service layer. Only create and delete have any UI, and
delete's only design-surface caller is an **unmounted widget** (§4.1).

---

## 4. Existing detail surfaces and the closest candidate (Task 3)

### 4.1 `MySavedDesignsSection` / `_SavedDesignCard` — the orphan

[pattern_library_browser.dart:22-92](lib/features/wled/pattern_library_browser.dart#L22-L92) and
[135-230](lib/features/wled/pattern_library_browser.dart#L135)

- **Takes:** `CustomDesign` directly.
- **Renders:** 120×100 gradient card from up to 3 extracted colors, name, a
  "See all" header, horizontal strip capped at 10.
- **Actions:** `onTap` → `applySavedDesign`; `onRemove` → a confirm dialog →
  `deleteDesignProvider` ([pattern_library_browser.dart:101-131](lib/features/wled/pattern_library_browser.dart#L101-L131)).
- **`grep MySavedDesignsSection lib/` returns only its own declaration.** It is
  never mounted. This is the *only* delete UI that has ever existed for saved
  designs, and it is dead code.

### 4.2 `ColorwayEffectSelectorPage`

[colorway_effect_selector.dart:69+](lib/features/wled/colorway_effect_selector.dart#L69)

- **Takes:** `LibraryNode` (a *palette*, not a design).
- **Renders:** large live preview, filter chips, curated effect grid.
- **Actions:** apply (`_applyPattern`, the 6-step reference implementation),
  Game Day persist, selection-mode return.
- **Missing for our purpose:** it edits a *catalog palette*, not a stored
  design; it has no name field, no delete, and it is precisely the surface the
  saved-design intercept was written to **bypass**
  ([pattern_theme_selection.dart:374-380](lib/features/wled/pattern_theme_selection.dart#L374-L380)).

### 4.3 `_CompactPatternItemCard` (Explore catalog card)

[pattern_grid_widgets.dart:1511+](lib/features/wled/pattern_grid_widgets.dart#L1511)

- **Takes:** `PatternItem` (catalog, has inline `wledPayload`).
- **Renders:** animated dot/gradient preview.
- **Actions:** tap → apply; **in-card color toggles**
  ([1586-1600](lib/features/wled/pattern_grid_widgets.dart#L1586-L1600)) and an
  **LEDs-per-color stepper** ([1638-1668](lib/features/wled/pattern_grid_widgets.dart#L1638-L1668))
  that absorb the tap.
- Notable as the **only card in the app that hosts inline actions without
  navigating** — the tap-absorption pattern here is the mechanism a My Designs
  card would need.

### 4.4 `PatternAdjustmentPanel`

[pattern_adjustment_panel.dart:111-149](lib/widgets/pattern_adjustment_panel.dart#L111-L149)

- **Takes:** loose primitives — `initialSpeed`, `initialIntensity`,
  `initialReverse`, `initialEffectId`, `effectName`, `initialColors`
  (`List<List<int>>`), plus `showColors` / `showPixelLayout` /
  `showEffectSelector` toggles and `onChanged` / `onCustomized` callbacks.
- **Renders/actions:** sliders, direction, effect grid, colour sequence
  builder; every change **writes live to the device** (`_applyEffect` →
  `repo.applyJson`, debounced).
- **Mounted at:** [wled_dashboard_page.dart:1135](lib/features/dashboard/wled_dashboard_page.dart#L1135) only.
- It takes no model at all — it is a primitives-in / values-out panel.

### 4.5 `EditPatternScreen`

[edit_pattern_screen.dart:25-32](lib/features/wled/edit_pattern_screen.dart#L25-L32), routed at
[app_router.dart:316](lib/app_router.dart#L316)

- **Takes:** `EditablePattern?` `initialPattern`.
- Has a **`TextEditingController _nameController`**
  ([edit_pattern_screen.dart:35](lib/features/wled/edit_pattern_screen.dart#L35)) — i.e. rename
  already works here — plus colour-slot editing across three picker tabs.
- **Different store:** it persists to `/users/{uid}/patterns/{patternId}` via
  `.set(merge:true)`, *not* `/designs`. It is the structural precedent for
  "open an existing stored artifact in an editor", against a parallel model.

### 4.6 Brand custom-design cards (commercial)

[brand_setup_screen.dart:639-720](lib/features/commercial/brand/brand_setup_screen.dart#L639-L720)

- **Takes:** `BrandCustomDesign`.
- **Actions:** the **only place in the app with full edit + delete + duplicate-id
  guard on a design row** — `_editCustomDesign` ([678-685](lib/features/commercial/brand/brand_setup_screen.dart#L678-L685)),
  `_removeCustomDesign` ([688-719](lib/features/commercial/brand/brand_setup_screen.dart#L688-L719)),
  id-collision check ([669-672](lib/features/commercial/brand/brand_setup_screen.dart#L669-L672)).
- **Missing:** operates on an in-memory list persisted as a `custom_designs[]`
  array field on `/brand_library/{id}`, not per-doc; no preview, no apply.

### 4.7 "For You" strip

`grep -iE "for you|forYou|for_you"` over `lib/` returns **nothing**. Marked
unknown — see §9.

### 4.8 Closest candidate

**`_SavedDesignCard` ([pattern_library_browser.dart:135-230](lib/features/wled/pattern_library_browser.dart#L135)).**
It is the only widget that takes a `CustomDesign`, derives its own preview, and
already carries both an apply action and a confirmed-delete action.

What it would still be missing for a reusable design detail view:

1. No **rename** — no text field, and `updateDesign` is unwired.
2. No **detail layout** — it is a 120px strip tile, not a card/sheet with
   metadata; description, tags, `createdAt`/`updatedAt` are all dropped.
3. No **per-channel breakdown** — `_extractColors`
   ([pattern_library_browser.dart:145-163](lib/features/wled/pattern_library_browser.dart#L145-L163)) flattens
   every included channel into ≤3 swatches; a design scoped to one channel
   looks identical to one spanning all.
4. No **edit affordance** — nothing routes to `ManualDesignEditor` or the AI
   studio.
5. No **type discrimination** — it cannot tell a per-pixel design from a
   Now-Playing snapshot, which is exactly the branch an edit button needs.
6. It is **not reachable**, so adopting it means mounting it as well as
   extending it.

---

## 5. Reference graph (Task 4)

There is only one design type (`CustomDesign`), so the graph is enumerated by
*referrer*:

| Referrer | Field | By id or inline? | Dangles on delete? |
|---|---|---|---|
| `ScheduleItem` | `wledPayload` (Map) + `actionLabel` (`"Pattern: <name>"`) | **Inline copy** — captured at pick time in `PatternSelection.wledPayload` ([my_schedule_page.dart:4577-4586](lib/features/schedule/my_schedule_page.dart#L4577-L4586)), handed over by `_returnSavedDesignSelection` ([pattern_theme_selection.dart:293-297](lib/features/wled/pattern_theme_selection.dart#L293-L297)). `ScheduleItem` has **no design-id field at all** ([schedule_models.dart:13-84](lib/features/schedule/schedule_models.dart#L13-L84)). | **No.** Safe. |
| `GameDayAutopilotConfig` | `saved_design_payload` | **Inline copy**, `jsonEncode(wledPayload)` at write ([game_day_autopilot_providers.dart:1080](lib/features/autopilot/game_day_autopilot_providers.dart#L1080)); read back at [config:368-369](lib/features/autopilot/game_day_autopilot_config.dart#L368-L369), consumed at [service:409-421](lib/features/autopilot/game_day_autopilot_service.dart#L409-L421) and [worker:522-525](lib/features/autopilot/game_day_autopilot_background_worker.dart#L522-L525). No design id stored. | **No.** Safe. |
| `GameDayBackgroundPersistence` | `savedDesignPayload` | **Inline copy** ([game_day_background_persistence.dart:52,131,160-162](lib/features/autopilot/game_day_background_persistence.dart#L52)) | **No.** Safe. |
| `CalendarEntry` | `patternName` (String) | **Neither** — carries only a display name and colour ([calendar_entry.dart:26-40](lib/features/schedule/calendar_entry.dart#L26-L40)). Its lease carries an inline `wledPayload` ([calendar_entry_lease_manager.dart:340](lib/features/schedule/calendar_entry_lease_manager.dart#L340)). | **No.** Safe, but the label goes stale on rename. |
| Neighborhood Sync | `SyncPatternAssignment.wledPayload` ([neighborhood_models.dart:1213-1226](lib/features/neighborhood/neighborhood_models.dart#L1213-L1226)); `PreSyncSceneSnapshot.wledPayload` ([pre_sync_scene_snapshot.dart:40,65](lib/features/neighborhood/services/pre_sync_scene_snapshot.dart#L40)); teardown re-applies `item.wledPayload` ([sync_teardown_resolver.dart:239-245](lib/features/neighborhood/services/sync_teardown_resolver.dart#L239-L245)) | **Inline copy** throughout. No design id anywhere in `lib/features/neighborhood/`. | **No.** Safe. |
| Favorites (`/users/{uid}/favorites`) | `pattern_name` (String) | **By name**, not by id ([user_service.dart:425-435](lib/services/user_service.dart#L425-L435); geofence lookup is `where('name', isEqualTo: actionName)` at [geofence_monitor.dart:293](lib/features/geofence/geofence_monitor.dart#L293)). | **No** (nothing joins on design id) — but a rename orphans the favourite silently. |
| `Scene` (`SceneType.custom`) | `customDesign: CustomDesign?` + `custom_design` map | **Both.** The whole design is embedded ([scene_models.dart:319-320](lib/features/scenes/scene_models.dart#L319-L320), rehydrated at [371-418](lib/features/scenes/scene_models.dart#L371-L418)) **and** its `id` survives inside that embedded copy. | See §5.1 — the one live coupling. |
| Brand cards | `BrandCustomDesign.designId`, `patternId: brand_{brandId}_{designId}` ([brand_design_generator.dart:322,346](lib/features/commercial/brand/brand_design_generator.dart#L322)) | By id — but in a **disjoint id space** (`/brand_library/…`), never `/users/{uid}/designs`. | Not related. |

### 5.1 The one query that joins on designs

`allScenesProvider` ([scene_providers.dart:74-119](lib/features/scenes/scene_providers.dart#L74-L119))
merges `designsStreamProvider` into the scene list via `Scene.fromDesign`. It
is a **stream merge, not a doc join** — a deleted design simply disappears from
the list. It does not throw and does not render blank.

Two consequences worth naming:

1. **Delete cascades the wrong way.** `deleteSceneProvider`
   ([scene_providers.dart:313-315](lib/features/scenes/scene_providers.dart#L313-L315)) — for
   `SceneType.custom` — deletes the underlying **design document**, not a scene
   document. Deleting a "scene" therefore removes the row from My Designs too.
2. **Resolution is by name, in voice/AI.** `allScenesProvider` is consumed by
   [command_intent_classifier.dart:145](lib/features/ai/command_intent_classifier.dart#L145),
   [local_command_parser.dart:538](lib/features/ai/local_command_parser.dart#L538),
   [lumina_command_router.dart:211](lib/features/ai/lumina_command_router.dart#L211),
   [dashboard_voice_control.dart:419](lib/features/voice/dashboard_voice_control.dart#L419),
   [voice_providers.dart:116/221/236](lib/features/voice/voice_providers.dart#L116),
   [voice_assistant_guide_screen.dart:106](lib/features/voice/voice_assistant_guide_screen.dart#L106).
   These match scenes by **name**, so a rename changes what voice commands
   resolve to. This is the sharpest hazard a rename feature would introduce,
   and it is not id-mediated anywhere.

**Net: no reference in the app dangles on design delete.** Every automation
holds an inline payload copy. The exposure of a delete feature is limited to
the scene-cascade above and to name-based voice/favourite matching.

---

## 6. Edit feasibility per type (Task 5)

### 6.1 Per-pixel / manual designs

- **The editor already accepts one.** `ManualDesignEditor({this.initialDesign})`
  ([manual_design_editor.dart:25-29](lib/features/design/manual_editor/manual_design_editor.dart#L25-L29))
  documents itself as "Optional design to open into the editor (a saved manual
  OR AI design)", and `_ensureInit`
  ([manual_design_editor.dart:59-70](lib/features/design/manual_editor/manual_design_editor.dart#L59-L70))
  rebuilds a `PixelDesignDocument` from `initialDesign`'s colorGroups.
- **Nothing ever passes it.** The sole construction site is
  `const ManualDesignEditor()` at
  [ai_design_studio_screen.dart:100](lib/features/design/screens/ai_design_studio_screen.dart#L100).
  The reopen path is **built and unwired**.
- **Save always creates a new doc.** `_save`
  ([manual_design_editor.dart:246-259](lib/features/design/manual_editor/manual_design_editor.dart#L246-L259))
  hardcodes `id: ''` and `name: 'Custom Design'`, so a reopened design would
  fork rather than update, and every per-pixel design in the list carries the
  same name.

### 6.2 AI Design Studio designs

- `AIDesignStudioScreen` ([ai_design_studio_screen.dart:28-33](lib/features/design/screens/ai_design_studio_screen.dart#L28-L33))
  has **no existing-design constructor parameter**. It hydrates only from
  `composedPatternProvider` (a `StateProvider<ComposedPattern?>`,
  [design_studio_providers.dart:162](lib/features/design/design_studio_providers.dart#L162)),
  which is filled by a fresh AI compose ([205](lib/features/design/design_studio_providers.dart#L205),
  [248](lib/features/design/design_studio_providers.dart#L248)) and cleared at
  [269](lib/features/design/design_studio_providers.dart#L269).
- `CustomDesign.composedPattern` is written
  ([design_providers.dart:602](lib/features/design/design_providers.dart#L602),
  persisted jsonEncoded at [design_models.dart:213](lib/features/design/design_models.dart#L213)) and
  decoded on read ([design_models.dart:146-152](lib/features/design/design_models.dart#L146-L152)) —
  but **no code anywhere reads `design.composedPattern` back out**. The field's
  stated purpose ("lets a Studio design be re-opened and re-edited as an AI
  design later", [design_models.dart:41-51](lib/features/design/design_models.dart#L41-L51)) is
  currently unrealised: the data is there, the reader is not.

### 6.3 Now-Playing / current-colors snapshots

No editor. `saveCurrentAsDesignProvider` captures live device state; there is no
inverse that pushes a stored design back into the Now-Playing editing state.
The only editable-in-place surface is `PatternAdjustmentPanel`, below.

### 6.4 `PatternAdjustmentPanel` from a stored payload

**Yes, mechanically.** It takes only primitives
([pattern_adjustment_panel.dart:135-148](lib/widgets/pattern_adjustment_panel.dart#L135-L148)),
`initState` copies them straight into local state
([pattern_adjustment_panel.dart:186-194](lib/widgets/pattern_adjustment_panel.dart#L186-L194)), and
`didUpdateWidget` re-syncs on change
([pattern_adjustment_panel.dart:196-218](lib/widgets/pattern_adjustment_panel.dart#L196-L218)). A caller
could supply `initialSpeed` / `initialIntensity` / `initialEffectId` /
`initialColors` from `design.channels.first` or from `toWledPayload()`.

Two caveats:

1. Every control **writes to the device immediately** (`_applyEffect` →
   `repo.applyJson`, debounced). There is no dry-edit mode — opening the panel
   on a stored design changes what the lights are doing.
2. It emits `PatternAdjustmentValues` ([pattern_adjustment_panel.dart:154-174](lib/widgets/pattern_adjustment_panel.dart#L154-L174)),
   which is flat (one speed / one fx / one colour list). It **cannot represent a
   multi-channel `CustomDesign`** — round-tripping a per-channel design through
   this panel collapses it.

### 6.5 Name storage and rename

**Both, on different surfaces.**

- **Stored field:** `CustomDesign.name` → Firestore `name`. This is what
  `_customDesignToLibraryNode` puts on the row
  ([pattern_providers.dart:82](lib/features/wled/pattern_providers.dart#L82)), and what
  `applySavedDesign` writes to the Now Playing label via
  `setLabelWithFingerprint(design.name, …)`
  ([apply_saved_design.dart:88-90](lib/features/design/apply_saved_design.dart#L88-L90)).
- **Derived resolver:** `displayNameFor` in
  [pattern_display_name.dart](lib/features/patterns/utils/pattern_display_name.dart) is applied by
  `ScheduleItem.displayActionLabel`
  ([schedule_models.dart:86-93](lib/features/schedule/schedule_models.dart#L86-L93)) — it only
  transforms *slug-shaped* input and returns anything containing spaces or
  punctuation unchanged ([pattern_display_name.dart:11-19](lib/features/patterns/utils/pattern_display_name.dart#L11-L19)).
  Since user design names normally contain spaces, the resolver is effectively a
  pass-through for them; it does **not** own the design's display name.

**What happens on rename** (were it wired):

- The `/designs` doc and the My Designs row update live via the stream.
- The Now Playing label updates on the *next* apply only — the current label is
  a snapshot, not a binding.
- **Nothing else follows.** `ScheduleItem.actionLabel` (`"Pattern: <old name>"`)
  keeps the old string; the schedule still fires correctly, because it holds an
  inline payload, but the schedule row reads with the stale name.
- Favourites matched by `pattern_name`
  ([geofence_monitor.dart:293](lib/features/geofence/geofence_monitor.dart#L293)) stop matching.
- Voice/AI scene resolution (§5.1) starts resolving to the new name and stops
  resolving to the old one, with no alias.

---

## 7. Firestore rules findings (Task 6)

`firestore.rules` — the only Task-1 path is `/users/{uid}/designs/{designId}`:

```
match /users/{userId}/designs/{designId} {     // firestore.rules:963-968
  allow read:   if isOwner(userId);
  allow create: if isOwner(userId);
  allow update: if isOwner(userId);
  allow delete: if isOwner(userId);
}
```

**Update and delete by the owning user are already permitted, with no field-shape
assertions.** A rename/edit/delete UI on My Designs would need **no rules
change and no rules deploy.**

Adjacent paths, for context:

| Path | update | delete | Note |
|---|---|---|---|
| `/users/{uid}/designs/{id}` | ✅ owner | ✅ owner | rules:963-968 — the surface's only path |
| `/users/{uid}/patterns/{id}` | ✅ owner | ✅ owner | rules:949-954 — `EditPatternScreen`'s store |
| `/users/{uid}/favorites/{id}` | ✅ owner, immutable `pattern_name`/`added_at` | ✅ owner | rules:870-887 |
| **`/users/{uid}/scenes/{id}`** | **absent** | **absent** | `grep -n "scenes" firestore.rules` returns nothing, and the file has no `{document=**}` wildcard. `SceneService` writes `/users/{uid}/scenes` ([scene_providers.dart:20](lib/features/scenes/scene_providers.dart#L20)) → **default-deny**. Flagged: not a My Designs blocker (the surface never reads `scenes`), but `savedScenesStreamProvider` feeds `allScenesProvider`, which the designs stream also feeds. Worth separate confirmation with a non-admin client credential. |

---

## 8. Root cause

Tapping a saved design does not open it — it *navigates* to
`/explore/library/design_{id}` ([pattern_grid_widgets.dart:778-783](lib/features/wled/pattern_grid_widgets.dart#L778-L783)),
and the destination `LibraryBrowserScreen` detects the `isSavedDesign`
discriminator and, instead of building any screen, renders a bare
`CircularProgressIndicator` while a post-frame callback runs `applySavedDesign`
and pops ([pattern_theme_selection.dart:374-395](lib/features/wled/pattern_theme_selection.dart#L374-L395)) —
so the route that would host a detail card is consumed entirely by the apply
side-effect.

The surface has no edit/rename/delete because it is not a designs screen at all
but the generic Explore catalog hierarchy with `CustomDesign` adapted down to a
read-only `LibraryNode` carrying only a name and three swatches
([pattern_providers.dart:69-90](lib/features/wled/pattern_providers.dart#L69-L90)), rendered by
`LibraryNodeCard`, which has no long-press or overflow affordance on any of its
three builders — while the only widget that ever offered delete,
`MySavedDesignsSection`, is never mounted anywhere in `lib/`.

---

## 9. Unknowns

| Unknown | Where I would expect the answer |
|---|---|
| Is `/dashboard/my-designs` (referenced by the AI navigation map at [local_command_parser.dart:83-84](lib/features/ai/local_command_parser.dart#L83-L84)) intended to be restored, or is the alias stale? No `GoRoute` declares it. | [lib/app_router.dart](lib/app_router.dart) — the `/dashboard` shell's child list |
| What did the deleted `MyDesignsScreen` render? Only a comment survives ([apply_saved_design.dart:16](lib/features/design/apply_saved_design.dart#L16)); the audit it cites (`audit 2026-05-29 / #62 / #81`) is not in `audit/`. | `audit/` (absent), or `git log -- lib/features/design/my_designs_screen.dart` |
| Whether a "For You" strip exists under a different name. `grep -iE "for you\|forYou\|for_you"` over `lib/` finds nothing; the closest home-screen surfaces are `_buildSmartSuggestions` ([wled_dashboard_page.dart:1190](lib/features/dashboard/wled_dashboard_page.dart#L1190)) and `_buildFavoritesSection` ([1264](lib/features/dashboard/wled_dashboard_page.dart#L1264)), which I did not open. | [lib/features/dashboard/wled_dashboard_page.dart](lib/features/dashboard/wled_dashboard_page.dart) |
| Whether `MySavedDesignsSection` was deliberately retired or dropped by accident when #62 unified the surface. Nothing in code says. | git history of [lib/features/wled/pattern_library_browser.dart](lib/features/wled/pattern_library_browser.dart) |
| Whether `/users/{uid}/scenes` writes are currently failing in production (rule absent → default-deny), and whether `SceneType.library` / `snapshot` scenes ever persist. Not verifiable read-only without a client-credential probe. | [firestore.rules](firestore.rules) + a non-admin client readback |
| Whether the per-pixel hardcoded name `'Custom Design'` ([manual_design_editor.dart:252](lib/features/design/manual_editor/manual_design_editor.dart#L252)) is a placeholder awaiting a naming dialog, or intended. | [lib/features/design/manual_editor/manual_design_editor.dart](lib/features/design/manual_editor/manual_design_editor.dart) `_save` |
