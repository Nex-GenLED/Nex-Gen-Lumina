# Design Card — Phase B: My Designs becomes a real node

Branch `feat/design-card`. Phase A (`0553a94`) committed before Phase B started.
Input: [audit/MY_DESIGNS_AUDIT.md](MY_DESIGNS_AUDIT.md) §2b, cited not re-derived.
No rules changes. No firmware impact.

---

## 1. Pre-checks

### P5 — How each root is read, and where the single source must live

| Surface | Reads | Backing |
|---|---|---|
| Explore root grid | `patternCategoriesProvider` → `repo.getCategories()` | `_categories`, a `static const List<PatternCategory>` ([pattern_repository.dart:403](../lib/features/wled/pattern_repository.dart#L403)) |
| Node-tree root | `libraryChildNodesProvider(null)` → `getChildNodes(null)` | `_allNodes` filtered to `category && parentId == null`, sorted by `sortOrder` ([pattern_repository.dart:1165-1171](../lib/features/wled/pattern_repository.dart#L1165-L1171)) ← `_buildRootCategories()` ([:787](../lib/features/wled/pattern_repository.dart#L787)) |

Two **disjoint static lists** covering the same eight ids. Consequences found:

- **Would a tree root double the grid?** No — the grid read only `_categories`,
  so adding to `_buildRootCategories()` alone would have left the grid
  unchanged (i.e. still wrong, just differently). The doubling risk was the
  *other* direction: adding to the tree while **keeping** the runtime prepend.
- **Ordering rules differed.** The tree has one — `sortOrder`, applied at
  `getChildNodes`. The grid had none: raw list order (arch, sports, holiday,
  movies, nature, party, seasonal, security), which did **not** match the tree's
  `sortOrder` 0–7 (sports first). The two surfaces already disagreed about order
  before this change.

**Where the single source must live:** `_buildRootCategories()`. It is the
richer type (`LibraryNode` carries `sortOrder`, `parentId`, `metadata`;
`PatternCategory` is id + name + imageUrl), and it is what search, ancestors,
and every picker traverse. `getCategories()` derives from it.

### P6 — Consumers of the three if-branches

`grep` over `lib/` and `test/`:

| Consumer | file:line | Uses |
|---|---|---|
| `LibraryBrowserScreen` | [pattern_theme_selection.dart:306-310](../lib/features/wled/pattern_theme_selection.dart#L306-L310) | all three |
| Neighborhood Sync picker `_buildNodeBrowser` | [sync_control_panel.dart:1917](../lib/features/neighborhood/widgets/sync_control_panel.dart#L1917) | children only |
| `my_designs_category_injection_test.dart` | — | all three |

**No side effects beyond producing the virtual folder.** All three are pure
reads: they return adapted nodes and mutate nothing. Nothing depends on the
prepend's *position* except that one test asserted `cats.first.id` — updated.

One consumer worth naming: the **Neighborhood Sync picker** browses
`libraryChildNodesProvider(parentId)` and will now see My Designs among its
roots for signed-in users. Drilling in yields `design_*` palette nodes it hands
to `_selectedPalette`. That path expects to generate patterns for a catalog
palette, which a saved design is not. See §4 — deferred, not silently shipped.

### P7 — The schedule picker after the change: **wireable as-is, zero edits needed**

The picker pushes `LibraryBrowserScreen(nodeId: null, onDesignSelected: …)`
([my_schedule_page.dart:4300-4310](../lib/features/schedule/my_schedule_page.dart#L4300-L4310)).
Once the tree root includes `my_designs`, the existing chain completes:

1. Root grid renders the My Designs category card.
2. Selection mode → `_buildFolderCard` root-navigator-pushes
   `LibraryBrowserScreen(nodeId: 'my_designs', onDesignSelected:)`.
3. Children are `design_*` palettes → `_buildPaletteCard` pushes
   `nodeId: 'design_x'`.
4. The saved-design branch sees `onDesignSelected != null` and calls
   `_returnSavedDesignSelection` ([pattern_theme_selection.dart:272-298](../lib/features/wled/pattern_theme_selection.dart#L272-L298)).

**What it expects:** it constructs `LibraryDesignSelection(id: match.id, name:
match.name, wledPayload: match.toWledPayload())` — the design's **own** id, not
a catalog node id. The schedule editor stores that into `PatternSelection`
([my_schedule_page.dart:4310-4318](../lib/features/schedule/my_schedule_page.dart#L4310-L4318)), where
`id` is used only for display and the **inline payload** is what arms the
schedule. So the id-space difference is harmless and no code changed.

### P8 — Guest behaviour: **the reason for the auth gate**

`designsStreamProvider` returns `Stream.value([])` when
`authStateProvider` has no user ([design_providers.dart:21-23](../lib/features/design/design_providers.dart#L21-L23)).
The old synthesis prepended the category **unconditionally**
(pre-change pattern_providers.dart:110-116), so a signed-out user saw a My
Designs folder that opened to a permanently-empty grid whose empty-state text
told them to "save a design from the dashboard" — advice they cannot act on.

That prepend was unconditional deliberately (#85: a writer-drift lost save must
look *empty*, not *vanished*). **That guarantee is about signed-in users** — it
distinguishes "your save failed" from "the folder disappeared". For a signed-out
user there is no save to have drifted, so the two cases do not exist and the
folder carries no information. Phase B gates on auth and **keeps** the #85
guarantee for signed-in users with zero designs, re-asserted by test.

---

## 2. Where the single source of truth now lives

**`PatternRepository._buildRootCategories()`**
([pattern_repository.dart:787+](../lib/features/wled/pattern_repository.dart#L787)) — nine `LibraryNode`s.

- `getCategories()` **derives** from it, mapping node → `PatternCategory` and
  sorting by `sortOrder`. The static `_categories` list no longer feeds any
  surface.
- The grid and the tree therefore cannot disagree about membership **or** order.
  A test asserts `patternCategoriesProvider` and `libraryChildNodesProvider(null)`
  produce identical id sequences.

**`sortOrder` renumbered.** Since the grid now inherits the tree's ordering rule
and the two previously disagreed, one had to move. I moved the **tree** to match
the **grid's** historical display order (arch 0, sports 1, holiday 2, movies 3,
nature 4, party 5, seasonal 6, security 7), because the Explore grid is the
prominent surface and reordering it would be a user-visible change nobody asked
for. My Designs takes `sortOrder: 8` — last, after the eight catalog roots, per
the brief.

The node-tree root order **did** change as a result (previously sports-first).
That order surfaces only in `LibraryBrowserScreen(nodeId: null)` — the schedule
picker and the Sync picker — which disagreed with the grid before anyway. They
now agree.

**What the provider layer still owns**, because a static, auth-less repository
cannot know it:

| Kept | Why it cannot move to the repository |
|---|---|
| Auth gate on the `my_designs` root (both `patternCategoriesProvider` and `libraryChildNodesProvider(null)`) | `PatternRepository` has no `authStateProvider` |
| Children of `my_designs` (`design_*` adaptation) | per-user Firestore docs; the repository has no Firestore |
| `libraryNodeByIdProvider`'s `design_*` branch | same |
| `libraryAncestorsProvider`'s `design_*` branch | same — though it now **looks the root up** from the repository instead of returning a fabricated node |

The node carries `metadata: {'isDynamic': true}` so this split is declared in
the data rather than implied by an id comparison.

**Honest correction to the brief's B2.** It asked to "remove the three
if-branches". Two of the four my_designs special cases are genuinely gone — the
category prepend and the node-by-id root case — and the ancestors branch no
longer fabricates a node. The **children** branch and the `design_*` node-by-id
branch remain and must: they are the dynamic node's data source, not a
workaround for the folder's absence. I did not delete them and pretend
otherwise.

---

## 3. What shipped

**Commit `d8c7ae1`** — `refactor(explore): make My Designs a real tree root, not a synthesis`

Pathspec (6 files, explicit; no `git add -A`):

```
lib/features/wled/pattern_repository.dart
lib/features/wled/pattern_providers.dart
lib/features/wled/pattern_explore_screen.dart
lib/features/wled/library_hierarchy_models.dart
lib/features/schedule/my_schedule_page.dart          (B3 comment site only)
test/features/design/my_designs_category_injection_test.dart
```

### B1 — repository-level node

Ninth root in `_buildRootCategories()`, `sortOrder: 8`,
`metadata: {'isDynamic': true}`, plus `PatternRepository.isDynamicNode()`.
The id constant moved to `LibraryCategoryIds.myDesigns`
([library_hierarchy_models.dart](../lib/features/wled/library_hierarchy_models.dart)) —
`kMyDesignsCategoryId` now aliases it, so every existing call site compiles
unchanged and there is no `providers → repository` import cycle.

**Rows stay `LibraryNodeType.palette`.** P7 showed the schedule picker needs no
distinct type, so no `LibraryNodeType.savedDesign` was added and no switch
statement had to learn a new case. The `isSavedDesign` metadata flag continues
to be the discriminator, exactly as Phase A's detail route depends on. Child
node ids remain `design_{id}` — **Phase A's route and `DesignDetailScreen` are
untouched by Phase B.**

Visibility: signed in → the folder appears with an empty state for zero designs
(#85 preserved). Signed out → absent.

### B2 — synthesis deleted

Removed: `myDesignsCategoryNode`, the unconditional prepend in
`patternCategoriesProvider`, the `my_designs` case in `libraryNodeByIdProvider`,
and the fabricated ancestor. `grep myDesignsCategoryNode` → one stale doc-comment
mention, zero code references. The grid renders My Designs exactly once
(asserted by test).

### B3 — what the tree gives, verified not special-cased

**Search.** `_allNodes` is a static snapshot, so the dynamic root's *children*
cannot live in it. Rather than a second search path, `searchLibrary` gained an
`extraNodes` parameter appended to the **same scored sweep**
(`for (final node in [..._allNodes, ...extraNodes])`) — one ranking, one
relevance rule. `librarySearchProvider` supplies the adapted design nodes.
`pattern_explore_screen.dart` was switched from calling
`repo.searchLibrary(query)` directly to `ref.read(librarySearchProvider(query).future)`,
which is what actually folds designs in — a direct repository call still
searches the catalog alone, and that is documented on the method.

**Pinning.** No change needed. `pinnedCategoriesProvider` already resolved
pinned ids against `repo.getCategories()`
([pattern_providers.dart:357-379](../lib/features/wled/pattern_providers.dart#L357-L379)); with
`getCategories()` now derived from the tree, `my_designs` resolves to
"My Designs" instead of falling through to the `'Unknown'` placeholder.
Asserted by test.

**Schedule picker.** **The code caught up to the comment**, not the reverse. The
comment at [my_schedule_page.dart:4291-4293](../lib/features/schedule/my_schedule_page.dart#L4291-L4293)
claimed the picker opens "top-level catalog + My Designs"; per audit §2b.5 item
3 that was false. It is now true, and `_returnSavedDesignSelection` — previously
unreachable from this screen — is reachable with **no code change**
(P7). The comment was annotated to record that it had been aspirational and what
made it true. That annotation is the **only** edit in `lib/features/schedule/`.

### B4 — gate

| Requirement | Status |
|---|---|
| 9 roots authenticated, 8 unauthenticated | ✅ test |
| Explore grid renders My Designs once | ✅ test |
| `searchLibrary` returns a saved design by name | ✅ test (+ a companion asserting catalog search is unchanged when there are no designs) |
| Pinning `my_designs` yields its real name | ✅ test |
| Schedule picker returns a saved design selection | ⚠️ **verified by reading the chain (P7), not by an end-to-end test** — see §4 |
| Grid and tree agree on root set and order | ✅ test (added beyond the gate) |
| All Phase A tests still green | ✅ |
| `flutter analyze` clean | ✅ zero errors |
| Full suite | ✅ **2485 tests pass** |

---

## 4. Deferred, and why

**Neighborhood Sync picker interaction — flagged, not handled.** P6 found
`sync_control_panel.dart:1917` browses the same root provider, so signed-in
users now see My Designs there too. Its `_PalettePickerCard` → `_selectedPalette`
path expects a catalog palette it can generate patterns from; a saved design is
a finished payload. Handling it means either excluding dynamic nodes from that
picker or teaching it the `isSavedDesign` branch — a change inside
`lib/features/neighborhood/`, which is outside this branch's scope and was not
in the brief. **Flagged rather than half-wired.** Behaviour today: the folder is
reachable there and selecting a design likely yields no generated patterns.

**Schedule-picker end-to-end test — not written.** The chain is verified by
reading (P7) and every link is unit-covered, but an integration test driving
root → My Designs → design → callback would live in
`test/features/schedule/`, which `feat/schedule-v3-model` owns. I did not write
into that directory.

**Effect / AI edit** remain deferred from Phase A (P4) — unchanged by Phase B.

---

## 5. What I would have had to fabricate, and didn't

1. **That the schedule picker works end-to-end.** I traced all four links and
   report it as read-verified, not exercised. It is the one B4 row not backed by
   a test, and it is marked as such rather than ticked.
2. **That the Sync picker is unaffected.** It is affected. I could not verify
   what selecting a saved design does there without running it, so I described
   the mechanism and the likely outcome in hedged terms instead of asserting a
   behaviour.
3. **That removing "the three if-branches" was achievable.** Two of four special
   cases are gone; two must remain because the repository has no Firestore. §2
   says so plainly rather than reporting the brief as fully satisfied.
4. **A rationale for reordering the Explore grid.** I chose to preserve the
   grid's visible order and move the tree instead — a judgement call with a
   user-visible consequence either way. §2 states which surface moved and why,
   so it can be reversed by renumbering `sortOrder` alone.
5. **`flutter analyze` "clean".** It reports 380 issues, all pre-existing
   deprecations and style infos across untouched files. Zero **errors**, and no
   new warnings from these two commits — the three unused imports Phase A's
   deletion created were removed. Stated precisely rather than as a bare "clean".

---

## 6. Process note

While measuring an analyzer delta I ran `git stash push --keep-index`, which
stashed all six uncommitted Phase B files. I popped it immediately; the stash
list is empty, all six files were restored, tests re-run green, and nothing was
lost. Recording it because the working tree and index are shared with parallel
sessions, where a stash can capture another branch's work — it should not have
been run at all.
