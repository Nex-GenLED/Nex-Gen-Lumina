# UI Polish Audit — 2026-05-25

Read-only audit. No code modified. Six items: file paths, widget/function
names, code snippets, and a brief diagnosis per section.

---

## 1. Home screen app-bar "lightning bolt" icon

The lightning bolt is the **controller selector dropdown** — a Flutter
Material icon, not a custom SVG/asset/painter. Tapping it opens a
`PopupMenuButton` listing all registered WLED controllers; selecting one
writes the chosen IP to `selectedDeviceIpProvider`. It is conditional —
hidden entirely when the user has zero registered controllers.

- **File:** [`lib/features/dashboard/wled_dashboard_page.dart`](../../lib/features/dashboard/wled_dashboard_page.dart)
- **AppBar wiring:** line 343-356 (`Scaffold.appBar = GlassAppBar(...)`)
- **Widget builder:** `_buildControllerSelector` at line 505
- **Icon:** `Icons.bolt_rounded` (line 524, size 22, tinted cyan when
  `state.connected` is true, otherwise `NexGenPalette.textMedium`)
- **Comparator (gear):** `Icons.settings_suggest_outlined` at line 351,
  `onPressed: () => context.go(AppRoutes.settings)`

### AppBar actions array
```dart
appBar: GlassAppBar(
  title: Text(
    isViewingAsCustomer ? 'Viewing: $userName' : 'Hello, $userName',
    overflow: TextOverflow.ellipsis,
  ),
  actions: [
    _buildControllerSelector(context, ref, state),
    IconButton(
      icon: const Icon(Icons.settings_suggest_outlined),
      tooltip: 'Settings',
      onPressed: () => context.go(AppRoutes.settings),
    ),
  ],
),
```

### Controller selector body (the bolt + its action)
```dart
Widget _buildControllerSelector(BuildContext context, WidgetRef ref, WledStateModel state) {
  final controllers = ref.watch(controllersStreamProvider).maybeWhen(
    data: (list) => list,
    orElse: () => <ControllerInfo>[],
  );
  final selectedIp = ref.watch(selectedDeviceIpProvider);
  if (controllers.isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(right: 4),
    child: PopupMenuButton<String>(
      tooltip: state.connected ? 'Controller online' : 'Controller offline',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: NexGenPalette.gunmetal90,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Icon(
          Icons.bolt_rounded,
          size: 22,
          color: state.connected
              ? NexGenPalette.cyan
              : NexGenPalette.textMedium,
        ),
      ),
      itemBuilder: (context) => controllers.map((controller) {...}).toList(),
      onSelected: (newIp) {
        ref.read(selectedDeviceIpProvider.notifier).state = newIp;
      },
    ),
  );
}
```

- (a) Material icon `Icons.bolt_rounded` — no custom asset / painter.
- (b) `onSelected` writes `selectedDeviceIpProvider.state = newIp`.
  No route push — purely a state update. Tooltip toggles between
  "Controller online" / "Controller offline" based on `state.connected`.
- (c) Gear comparator: `Icons.settings_suggest_outlined` →
  `context.go(AppRoutes.settings)`.

---

## 2. "No Favorites Yet" empty state — off-center

The empty state is left-aligned because **its grandparent column on the
dashboard uses `CrossAxisAlignment.start`**, so the FavoritesGrid widget
(in its empty-state branch) sits flush-left in that column. The inner
column inside the empty state has the implicit default
`CrossAxisAlignment.center`, but the inner column shrink-wraps to its
widest child (the subtitle text) — so centering happens WITHIN that
narrow inner column, not within the screen width.

### The empty-state widget
- **File:** [`lib/widgets/favorites_grid.dart`](../../lib/widgets/favorites_grid.dart)
- **Method:** `_buildEmptyState` at line 103

```dart
Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
  return Padding(
    padding: const EdgeInsets.all(24.0),
    child: Column(
      mainAxisSize: MainAxisSize.min,                          // ← vertical shrink
      // crossAxisAlignment: (default) CrossAxisAlignment.center  — but
      // centers children WITHIN this Column's intrinsic width, which
      // is the width of its widest child (the subtitle Text), not the
      // parent's full width.
      children: [
        Icon(
          Icons.star_border_rounded,
          size: 48,
          color: NexGenPalette.textSecondary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Text(
          'No Favorites Yet',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: NexGenPalette.textSecondary,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your most-used patterns will appear here',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(...),
        ),
      ],
    ),
  );
}
```

### The dashboard parent (the actual cause)
- **File:** [`lib/features/dashboard/wled_dashboard_page.dart`](../../lib/features/dashboard/wled_dashboard_page.dart)
- **Method:** `_buildFavoritesSection` at line 1222

```dart
Widget _buildFavoritesSection(BuildContext context, WidgetRef ref) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,             // ← here
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('My Favorites'.toUpperCase(), ...),
          const SizedBox(height: 10),
        ]),
      ),
      FavoritesGrid(
        onPatternTap: (favorite) async { ... },
      ),
    ],
  );
}
```

### Diagnosis
- The dashboard's `_buildFavoritesSection` Column declares
  `crossAxisAlignment: CrossAxisAlignment.start`. Every child of that
  Column — including the FavoritesGrid widget itself — gets left-
  aligned to the column's start edge.
- FavoritesGrid in its empty-state branch returns
  `Padding(24) → Column(mainAxisSize: min)`. With no explicit width
  constraint, the inner Column shrink-wraps to its widest child (the
  subtitle text). The widget tree honors `mainAxisSize: min` which
  shrinks vertically; the horizontal extent collapses to intrinsic
  width because the parent column above doesn't stretch its children.
- Result: the entire empty-state column sits flush-left, with its
  inner content centered relative to itself — which from the user's
  perspective looks "off-center left."

### Fix options (not applied)
- Wrap the empty-state return in `Center(...)`, OR
- Wrap the Column inside `SizedBox(width: double.infinity, ...)`, OR
- Wrap the `FavoritesGrid` call in `_buildFavoritesSection` with
  `Center(child: FavoritesGrid(...))` (most targeted — doesn't change
  the non-empty grid layout because that branch already constrains its
  own width via the inner Column + Row + Expanded).

---

## 3. Mini-month calendar — dot under the date number, overlap risk

Each day cell is a small `Container` whose body is a vertical `Column`
stacking the date number above a 4×4 colored dot with a blur shadow.
The two are NOT in a `Stack` — they're laid out top-to-bottom. The
"overlap" perception comes from how tight the spacing is on the 3-Mo /
6-Mo cells (28px tall, 9px font, 2px margin, 4px dot, plus a 3px blur
shadow that bleeds upward into the number's row).

### The day cell builder
- **File:** [`lib/features/schedule/my_schedule_page.dart`](../../lib/features/schedule/my_schedule_page.dart)
- **Widget:** `_CalDayCell` at line 2269
- **Multi-month grid parent:** the outer view-mode bar declares the modes
  at line 448 (`'1 Mo' / '3 Mo' / '6 Mo' / 'Year'`); the grid that
  invokes `_CalDayCell` lives a little above line 2240.

### Hardcoded sizes — set by the calling grid
- **File:** [`lib/features/schedule/my_schedule_page.dart`](../../lib/features/schedule/my_schedule_page.dart) line 2212-2213
```dart
final cellSize = size == _CalDaySize.tiny ? 20.0 : 28.0;
final fontSize = size == _CalDaySize.tiny ? 7.0  : 9.0;
```
The `tiny` enum is used for the **Year** view; `compact` is used for
**3 Mo / 6 Mo**. The dot is suppressed entirely on `tiny` cells
(see snippet — `if (color != null && size >= 24)`).

### Day-cell body
```dart
return GestureDetector(
  onTap: onTap,
  child: Container(
    decoration: BoxDecoration(
      color: isPending
          ? NexGenPalette.amber.withValues(alpha: 0.12)
          : color != null
              ? color.withValues(alpha: 0.2)
              : Colors.transparent,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${d.day}',
          style: TextStyle(
            fontSize: fontSize,                  // 7px tiny / 9px compact
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w400,
            color: isToday ? NexGenPalette.cyan
                   : isPast ? NexGenPalette.textMedium.withValues(alpha: 0.5)
                            : NexGenPalette.textHigh,
          ),
        ),
        if (calEntry?.brightness == 0 && size >= 24)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.nightlight_round, size: 8, color: NexGenPalette.textMedium),
          )
        else if (color != null && size >= 24)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 3)],
            ),
          ),
      ],
    ),
  ),
);
```

### Diagnosis
- Layout = `Column(mainAxisAlignment: center)`. Number on top, dot below.
  Not a `Stack` / `Positioned`.
- Cell sizing math, 3-Mo / 6-Mo case (`compact`, 28px cell):
  - 9px font text + 2px margin + 4px dot = 15px of fixed content
  - Centered vertically → ~6-7px slack on each side of the column
  - The dot's `boxShadow` blurs 3px in every direction → effective
    visual footprint ~10×10px, which **reaches up into the number's
    row** since only 2px of margin separates them.
- The crowding worsens on a `compact` cell with `borderRadius: 3` and
  a colored fill (when `color != null`) — the cell is also tinted, so
  the dot's color is the same as the cell background tint, reducing
  visual separation and increasing the "overlap" perception.

### Fix surface area (not applied)
- Increase the margin between number and dot (`EdgeInsets.only(top: 2)`
  → say `top: 3` or `top: 4` on compact cells), OR
- Reduce / drop the boxShadow blur on the dot (3px → 0 or 1.5), OR
- Convert layout to `Stack` with `Positioned`, placing the number near
  the top and the dot near the bottom of the cell, taking the
  pressure off `mainAxisAlignment: center`.

---

## 4. Explore Patterns — stray house preview persists on back-nav

The preview hero is `_ExploreRooflinePreview` watching
`explorePreviewProvider`. It's a plain `StateProvider` with **no
auto-dispose** and **no clear-on-pop / clear-on-route-change**. Once any
chokepoint apply (`applyPreviewSync` at `wled_providers.dart:953`) writes
to it, the preview persists until either:
(a) the user explicitly taps the X (which sets the provider to null), or
(b) the app process is restarted.

### The preview widget
- **File:** [`lib/features/wled/pattern_explore_screen.dart`](../../lib/features/wled/pattern_explore_screen.dart)
- **Widget:** `_ExploreRooflinePreview` at line 983
- **Mount point on the Explore root:** line 186

```dart
// Roofline preview hero — only shown when a design card is selected
_ExploreRooflinePreview(
  onDismiss: () => ref.read(explorePreviewProvider.notifier).state = null,
),
```

### Preview body
```dart
class _ExploreRooflinePreview extends ConsumerWidget {
  final VoidCallback onDismiss;
  const _ExploreRooflinePreview({required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(explorePreviewProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: preview == null
          ? const SizedBox.shrink()                       // ← collapses when null
          : Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 994 / 492,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset('assets/images/Demohomephoto.jpg', ...),
                      AnimatedRooflineOverlay(...),
                      // gradient + name label + dismiss X (line 1061-1077)
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
```

### The state provider
- **File:** [`lib/features/wled/pattern_providers.dart`](../../lib/features/wled/pattern_providers.dart) line 634
```dart
final explorePreviewProvider = StateProvider<ExplorePreviewState?>((ref) => null);
```
Plain `StateProvider`. NOT `.autoDispose`. No listeners that clear it
on route changes.

### Who writes to it (sets the preview visible)
- **`WledNotifier.applyPreviewSync`** at
  [`lib/features/wled/wled_providers.dart`](../../lib/features/wled/wled_providers.dart):975:
  ```dart
  if (updateExplorePreview) {
    ref.read(explorePreviewProvider.notifier).state = ExplorePreviewState(
      colors: colors,
      effectId: effectId,
      speed: speed,
      brightness: brightness,
      name: effectName ?? '',
      colorGroupSize: colorGroupSize,
      spacing: spacing,
    );
  }
  ```
- This chokepoint is called by every user-initiated apply that should
  reflect on the Explore hero (design cards, pattern adjustments, etc.).

### Who clears it
- The dismiss X in `_ExploreRooflinePreview` (line 187).
- Module-level `null` initializer on first read (only runs once).
- **No other clearing site.** Grep across `lib/` finds NO call to
  `explorePreviewProvider.notifier).state = null` outside the dismiss
  handler.

### Lifecycle on the Explore screen itself
- **File:** [`lib/features/wled/pattern_explore_screen.dart`](../../lib/features/wled/pattern_explore_screen.dart)
- `State.dispose()` at line 126-128 only disposes `_searchController`.
  Does NOT touch `explorePreviewProvider`.
- No `RouteAware` mixin, no `didPopNext`, no GoRouter pop listener.

### Where else is the preview rendered?
- Grep for `_ExploreRooflinePreview` in `lib/`: ONE call site
  (pattern_explore_screen.dart line 186).
- Grep for `AnimatedRooflineOverlay` in widget code: usage is wider
  (dashboard hero, demo screen, edit pattern, autopilot detail —
  `widget/animated_roofline_overlay.dart` consumers) — but those
  paths supply their own colors / effect inputs and do NOT watch
  `explorePreviewProvider`. So the persistence bug is isolated to
  the Explore root.

### Diagnosis
The state survives Pop because `StateProvider` has process-level
lifetime by default. The Explore screen's `State.dispose` is unrelated
to the provider. Tyler's symptom — preview reappears after navigating
back to Explore root — is the expected behavior of this code path,
not a glitch.

### Fix surface area (not applied)
- Convert `explorePreviewProvider` to `.autoDispose` AND add a
  long-lived "keepAlive" trigger only while the Explore screen is in
  focus, OR
- Add a `dispose()` override on `_PatternExploreScreenState` (the
  outer screen state) that resets the provider to null, OR
- Add a one-shot `WidgetsBinding.instance.addPostFrameCallback` /
  `didChangeDependencies` clear when the screen route is the active
  route after a Pop (RouteAware mixin pattern).

---

## 5. Pattern category and pattern ordering

All categories and subcategories are **hardcoded `static const` lists**
in `lib/features/wled/pattern_repository.dart`. Order is implicit by
declaration order. **No `sortOrder` / `order` / `sequence` field exists**
on any of: `PatternCategory`, `SubCategory`, `PatternItem`. No `.sort()`
call is applied at read time. Models accept a JSON shape but there is
no field for ordering in `toJson` / `fromJson`.

### Models — fields present
- **File:** [`lib/features/wled/pattern_models.dart`](../../lib/features/wled/pattern_models.dart)

```dart
class PatternCategory {
  final String id;
  final String name;
  final String imageUrl;
  // NO sortOrder / order / sequence field
}

class PatternItem {
  final String id;
  final String name;
  final String imageUrl;
  final String categoryId;
  final Map<String, dynamic> wledPayload;
  // NO sortOrder / order / sequence field
}

class SubCategory {
  final String id;
  final String name;
  final List<Color> themeColors;
  final String parentCategoryId;
  // NO sortOrder / order / sequence field
}
```

### Data source — categories
- **File:** [`lib/features/wled/pattern_repository.dart`](../../lib/features/wled/pattern_repository.dart)
- **Top-level category list:** `_categories` static const at line 395

```dart
static const PatternCategory catArchitectural = PatternCategory(
  id: 'cat_arch',
  name: 'Architectural Downlighting (White)',
  imageUrl: 'https://images.unsplash.com/photo-1600585154154-8c857b74f2ab',
);
static const PatternCategory catHoliday = PatternCategory(
  id: 'cat_holiday',
  name: 'Holidays',
  imageUrl: 'https://images.unsplash.com/photo-1482517967863-00e15c9b44be',
);
// ... + catSports, catSeasonal, catParty, catSecurity, catMovies, catNature

static const List<PatternCategory> _categories = [
  catArchitectural,
  catHoliday,
  catSports,
  catSeasonal,
  catParty,
  catMovies,
  catSecurity,
  catNature,
];
```

### Data source — sub-categories (Holidays as the requested example)
- **File:** [`lib/features/wled/pattern_repository.dart`](../../lib/features/wled/pattern_repository.dart) line 407-444

```dart
static final List<SubCategory> _subCategories = [
  // Holidays
  SubCategory(
    id: 'sub_xmas',
    name: 'Christmas',
    themeColors: const [Color(0xFFFF0000), Color(0xFF00FF00), Colors.white],
    parentCategoryId: catHoliday.id,
  ),
  SubCategory(
    id: 'sub_halloween',
    name: 'Halloween',
    themeColors: const [Color(0xFFFF8C00), Color(0xFF800080), Colors.black],
    parentCategoryId: catHoliday.id,
  ),
  SubCategory(
    id: 'sub_july4',
    name: '4th of July',
    themeColors: const [Color(0xFFFF0000), Colors.white, Color(0xFF0000FF)],
    parentCategoryId: catHoliday.id,
  ),
  SubCategory(
    id: 'sub_easter',
    name: 'Easter',
    themeColors: const [Color(0xFFFFB6C1), Color(0xFFADD8E6), Color(0xFFBFFF00)],
    parentCategoryId: catHoliday.id,
  ),
  SubCategory(
    id: 'sub_valentines',
    name: "Valentine's",
    themeColors: const [Color(0xFFFF0000), Color(0xFFFF69B4), Colors.white],
    parentCategoryId: catHoliday.id,
  ),
  SubCategory(
    id: 'sub_st_patricks',
    name: "St. Patrick's",
    themeColors: const [Color(0xFF00FF00), Color(0xFF90EE90), Colors.white],
    parentCategoryId: catHoliday.id,
  ),
  // ... Game Day, Seasonal, Party, etc. follow in the same list
];
```

### Diagnosis & fix surface area
- **No** Firestore collection or asset JSON involved; pure Dart const data.
- **No** sort applied — the repository serves whatever order is in the
  Dart list literal.
- Two paths if Tyler wants explicit ordering:
  1. **Reorder the Dart lists** (zero-schema change; cheapest fix; suits
     a one-shot reordering).
  2. **Add `sortOrder: int` field** to the three models + a
     `.sort((a, b) => a.sortOrder.compareTo(b.sortOrder))` at read
     time. Future-proof if categories are ever sourced from Firestore.

---

## 6. Neighborhood Sync — stacked CTA buttons (convert to side-by-side)

The two buttons stack in a Column inside a fixed bottom bar; the
messaging content above is a scrollable ListView with bottom padding
that reserves space for the button bar. Converting Column → Row is safe
— the bar has its own bordered Container, and the ListView's
`navBarTotalHeight + 88` reserve is independent of how the buttons are
laid out inside.

### The stacked buttons
- **File:** [`lib/features/neighborhood/neighborhood_sync_screen.dart`](../../lib/features/neighborhood/neighborhood_sync_screen.dart)
- **Method:** `_buildActionButtons` at line 1070

```dart
Widget _buildActionButtons() {
  return Container(
    padding: EdgeInsets.fromLTRB(
        24, 12, 24, navBarTotalHeight(context) + 12),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.7),
      border: Border(
          top: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.1))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary — matches "Start a Block Party" in onboarding
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onCreateGroup,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: const Text(
              'Start a Block Party',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 8,
              shadowColor: NexGenPalette.cyan.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Secondary — matches "Join the Party" in onboarding
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onJoinGroup,
            icon: const Icon(Icons.login, size: 20),
            label: const Text('Join the Party'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              side: const BorderSide(color: NexGenPalette.cyan),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    ),
  );
}
```

### Surrounding layout — what's above the buttons
- **File:** [`lib/features/neighborhood/neighborhood_sync_screen.dart`](../../lib/features/neighborhood/neighborhood_sync_screen.dart) line 475-490

```dart
padding: EdgeInsets.fromLTRB(
    16, 8, 16, navBarTotalHeight(context) + 88),     // ← reserve for buttons
children: [
  for (int i = 0; i < sorted.length; i++)
    _buildGroupCard(sorted[i], i + 1),
  if (previousGroups.isNotEmpty) ...[
    const SizedBox(height: 24),
    _buildPreviousGroupsSection(previousGroups),
  ],
],
// ...
// ── Bottom action buttons ─────────────────────────────────────
_buildActionButtons(),     // line 489 — sibling to the ListView
```

The ListView and the button bar are siblings inside an outer Column.
The ListView's bottom padding (`navBarTotalHeight + 88`) reserves space
for the buttons so the scroll content never hides under them.

### Diagnosis & fix surface area
- The Column → Row conversion is contained entirely within
  `_buildActionButtons`. No effect on the ListView or its padding.
- For a side-by-side layout:
  - Replace `Column(...)` with `Row(...)`.
  - Wrap each button in `Expanded(child: ...)` instead of
    `SizedBox(width: double.infinity, child: ...)`.
  - Replace the inter-button `SizedBox(height: 12)` with
    `SizedBox(width: 12)`.
- Optional: shrink the primary button's vertical padding from 16 to 12
  to match the secondary, OR keep the asymmetry as a deliberate cue.
- The bordered Container + `Colors.black.withValues(alpha: 0.7)` glass
  background stays unchanged.

---

## Summary

| # | Symptom | Source | Fix scope |
|---|---------|--------|-----------|
| 1 | Lightning bolt is the controller selector dropdown | `dashboard/wled_dashboard_page.dart::_buildControllerSelector` (line 505) | Identified — `Icons.bolt_rounded`, opens PopupMenu, writes selectedDeviceIpProvider |
| 2 | Empty-state off-center | dashboard's `_buildFavoritesSection` uses `CrossAxisAlignment.start` (line 1224); FavoritesGrid's empty Column has no width constraint | Wrap empty state in `Center` or constrain width |
| 3 | Mini-month dot crowds number | `_CalDayCell` Column + 4px dot with 3px blur shadow + 2px margin in 28px cell | Increase margin, reduce blur, or convert to Stack |
| 4 | Explore preview persists across pop | `explorePreviewProvider` is plain StateProvider; no auto-dispose; no clear-on-pop site | Convert to `.autoDispose` OR clear in screen `dispose()` OR RouteAware clear |
| 5 | Pattern ordering | Hardcoded `static const` lists in `pattern_repository.dart`; no sortOrder field on models | Reorder lists in place OR add `sortOrder` field + sort at read |
| 6 | Stacked CTAs | `_buildActionButtons` uses `Column` with infinity-width children | Column→Row, SizedBox(width: double.infinity)→Expanded, height-spacer→width-spacer |

No code modified. Audit only.
