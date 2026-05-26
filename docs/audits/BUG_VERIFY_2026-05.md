# Bug Verification Audit — 2026-05-25

Read-only verification of two prior fixes. No code modified.

---

## Summary

**VERDICT A:** **PARTIAL** — the centralized resolver exists and is wired into
the dashboard "Now Playing" label, but several user-facing pattern-name
render sites still render the stored string directly without routing through
`displayNameFor()`. Whether any of those sites actively *leak slugs* depends
on what writers stored. No code-path enforcement exists; the resolver is
opt-in per call site.

**VERDICT B:** **OPEN** — neither Prompt 3 nor Prompt 4 of Item #51's
compound-temporal decomposition has shipped. The schema is **singular** end
to end (`schedulingIntent: object|null`), the handler builds **one**
`ScheduleItem`, the bottom-sheet entry point doesn't even dispatch
`schedulingIntent`, and no decomposition path exists for a prompt like
"red and green until Dec 25, then warm white through New Year's." The
existing audit at [docs/lumina_split_schedule_audit.md](../lumina_split_schedule_audit.md)
already documents this gap.

---

# ITEM A — snake_case pattern IDs leaking into the UI

## 1. Resolver location and override-map size

**Resolver file:** [lib/features/patterns/utils/pattern_display_name.dart](../../lib/features/patterns/utils/pattern_display_name.dart)

**Public entry points** (line 153 and line 199):
```dart
String displayNameFor(String rawId);          // slug → display name
String teamShortName(String officialName);    // "Boston Red Sox" → "Red Sox"
```

**Override-map count (actual, not stale docstring):**

- `_kTeamShortNames` ([pattern_display_name.dart:45-96](../../lib/features/patterns/utils/pattern_display_name.dart#L45-L96)):
  **46 entries** (confirms the audit-prompt's "~46-entry team override
  map" expectation exactly).
  - The docstring at line 113 says "38 teams × 3 suffixes = 114 entries" —
    this is **stale**. Actual count is 46 teams. The lazy-built
    `_slugOverrides` cache materializes 46 × 3 + `_kExtraOverrides`
    (1 entry, `KC_Royals_Game_Day`) = **139 cached slug overrides**.
- `_kAcronyms` ([line 28-32](../../lib/features/patterns/utils/pattern_display_name.dart#L28-L32)):
  13 entries (KC, AI, NY, LA, SF, DC, US, UK, CL, NFL, NBA, MLB, NHL, MLS).
- `_kExtraOverrides` ([line 100-102](../../lib/features/patterns/utils/pattern_display_name.dart#L100-L102)):
  1 entry (`KC_Royals_Game_Day → 'KC Royals Game Day'`).

**Tests:** [test/features/patterns/pattern_display_name_test.dart](../../test/features/patterns/pattern_display_name_test.dart)
exists and covers Tyler's spec cases including KC, NY, LA, SF, DC, and
slug-with-spaces inputs.

---

## 2. Coverage by render path

The resolver has **two call sites** in `lib/`:

1. [lib/features/wled/display_pattern_providers.dart:61](../../lib/features/wled/display_pattern_providers.dart#L61)
   `return displayNameFor(activePreset);` — inside
   `displayPatternNameProvider`. Only the dashboard "Now Playing" bar
   reads this provider.
2. [lib/features/autopilot/game_day_autopilot_config.dart:246](../../lib/features/autopilot/game_day_autopilot_config.dart#L246)
   `return teamShortName(teamName);` — Game Day pattern name composer.

The deprecated local `_humanizePresetName` at
[display_pattern_providers.dart:17](../../lib/features/wled/display_pattern_providers.dart#L17)
is marked `@Deprecated` and `// ignore: unused_element` — kept as a
back-compat shim with no callers.

Direct `displayPatternNameProvider` readers (4 total):
- [lib/features/dashboard/wled_dashboard_page.dart:754](../../lib/features/dashboard/wled_dashboard_page.dart#L754) — main dashboard Now Playing bar ✅
- [lib/screens/commercial/CommercialHomeScreen.dart:213](../../lib/screens/commercial/CommercialHomeScreen.dart#L213) — commercial-mode home ✅
- [lib/features/ai/lumina_bottom_sheet.dart:1297](../../lib/features/ai/lumina_bottom_sheet.dart#L1297) — AI sheet preview readback ✅
- [lib/features/ai/lumina_ai_screen.dart:726](../../lib/features/ai/lumina_ai_screen.dart#L726) — AI full-screen preview readback ✅

---

## 3. High-risk render paths — per-site verdict

### (a) Now Playing card on the dashboard ("Solid" label area) — **COVERED**

[wled_dashboard_page.dart:754](../../lib/features/dashboard/wled_dashboard_page.dart#L754) → `displayPatternNameProvider` → `displayNameFor(activePreset)`.
The big white text at line 810 renders the resolved string. Routes through
the resolver. ✅

### (b) Schedule day-cell — **N/A (no name rendered)**

[my_schedule_page.dart:2269+ `_CalDayCell`](../../lib/features/schedule/my_schedule_page.dart#L2269)
only renders `${d.day}` (the date number) plus a colored dot/nightlight
icon. No pattern name appears on the cell. ✅

### (b′) Schedule entry labels (day-detail row + bottom sheet) — **BYPASSES RESOLVER**

These render `entry.patternName`/`event.patternName` directly:

| Site | What gets shown |
|------|------------------|
| [my_schedule_page.dart:894](../../lib/features/schedule/my_schedule_page.dart#L894) | `Text(entry.patternName, ...)` in the schedule row |
| [my_schedule_page.dart:1224](../../lib/features/schedule/my_schedule_page.dart#L1224) | `Text(patternName ?? 'No Schedule', ...)` |
| [my_schedule_page.dart:1500](../../lib/features/schedule/my_schedule_page.dart#L1500) | `Text(patternName, ...)` build helper |
| [my_schedule_page.dart:2011](../../lib/features/schedule/my_schedule_page.dart#L2011) | `Text(patternName ?? '—', ...)` |
| [autopilot_event_detail_sheet.dart:179](../../lib/features/schedule/autopilot_event_detail_sheet.dart#L179) | `Text(event.patternName, ...)` event-sheet title |
| [autopilot_event_detail_sheet.dart:487](../../lib/features/schedule/autopilot_event_detail_sheet.dart#L487) | SnackBar `'Previewing: ${event.patternName}'` |
| [autopilot_event_detail_sheet.dart:501](../../lib/features/schedule/autopilot_event_detail_sheet.dart#L501) | Dialog body `'Remove "${event.patternName}" from your schedule?'` |
| [calendar_entry_editor.dart:103](../../lib/features/schedule/calendar_entry_editor.dart#L103) | `'Edit ${widget.entry.patternName}'` editor title |
| [eviction_picker_dialog.dart:211](../../lib/features/schedule/eviction_picker_dialog.dart#L211) | `'Adding: ${entry.patternName} on ${entry.dateKey}'` |
| [schedule_conflict_dialog.dart:279](../../lib/features/schedule/schedule_conflict_dialog.dart#L279) | `entry?.patternName ?? dateKey` |
| [schedule_overload_banner.dart:545](../../lib/features/schedule/schedule_overload_banner.dart#L545) | `entry.patternName` in overload card |

Whether these *leak slugs* depends on what was stored when the entry was
created. `CalendarEntry.fromJson` at
[calendar_entry.dart:139](../../lib/features/schedule/calendar_entry.dart#L139)
stores `json['pattern']` verbatim, so if any writer ever passes a slug
(e.g. `'KC_Royals_Game_Day'`) it persists raw and renders raw on every
site above.

### (c) Favorites grid tiles — **BYPASSES RESOLVER**

[lib/widgets/favorites_grid.dart:333](../../lib/widgets/favorites_grid.dart#L333):
```dart
Text(
  favorite.patternName,    // raw — no displayNameFor()
  ...
)
```
The 2×2 favorite tile labels render the stored `patternName` verbatim. If a
favorite was saved while a slug was the active label, the slug renders
on the tile.

Also: SnackBar at [wled_dashboard_page.dart:1280](../../lib/features/dashboard/wled_dashboard_page.dart#L1280)
shows `'Applied: ${favorite.patternName}'` raw after a tile tap.

### (d) Explore pattern cards + "<name> – <mode>" hero — **CATALOG SAFE; PREVIEW BYPASSES**

- [pattern_grid_widgets.dart:1514](../../lib/features/wled/pattern_grid_widgets.dart#L1514)
  `Text(widget.pattern.name, ...)` — these render `PatternItem.name` from the
  static const catalog in
  [pattern_repository.dart](../../lib/features/wled/pattern_repository.dart),
  which are already authored as human strings ("Christmas Twinkle"
  etc.). No slug source → no leak in practice. ✅ (but no enforcement
  if a future catalog entry were added with a slug-style id-in-name)
- [pattern_grid_widgets.dart:2070](../../lib/features/wled/pattern_grid_widgets.dart#L2070)
  `Text(widget.patternName, ...)` inside the "Now Playing" overlay of the
  pattern detail sheet — receives `widget.patternName` from constructor;
  raw passthrough, no resolver.
- [pattern_explore_screen.dart:889](../../lib/features/wled/pattern_explore_screen.dart#L889)
  `Text(node.name, ...)` — `LibraryNode.name` is authored, not slug. ✅
- Hero/`_ExploreRooflinePreview`: **does not exist in the current file**
  (pattern_explore_screen.dart is 973 lines; the audit prompt referenced
  line 983 which is past EOF). `AnimatedRooflineOverlay` is used in 8
  other places. The hero label-on-preview pattern described in the
  earlier UI_POLISH audit does not currently render on this screen.

### (e) AI scheduling confirmation text — **MIXED**

- **Now Playing label after AI apply:** flows through
  `activePresetLabelProvider.setLabelWithFingerprint(label, ...)` at
  [lumina_ai_screen.dart:254](../../lib/features/ai/lumina_ai_screen.dart#L254)
  using `resolveLuminaDisplayName(...)` ([pattern_label_resolver.dart:29](../../lib/features/ai/pattern_label_resolver.dart#L29)).
  Then read via `displayPatternNameProvider` → resolver. ✅
- **AI SnackBar confirmation** after a `schedulingIntent`:
  [lumina_ai_screen.dart:503](../../lib/features/ai/lumina_ai_screen.dart#L503)
  ```dart
  'Add "$patternName" to your schedule at $timeLabel?'
  ```
  Renders `intent['patternName']` raw — bypasses resolver. The system
  prompt instructs the AI to emit a humanized name (see
  [lumina_ai_service.dart:220-229](../../lib/lumina_ai/lumina_ai_service.dart#L220-L229))
  but there's no client-side guarantee. If the AI ever echoes the slug
  form, it leaks here.
- **`actionLabel` written into ScheduleItem:**
  [lumina_ai_screen.dart:519](../../lib/features/ai/lumina_ai_screen.dart#L519)
  ```dart
  actionLabel: 'Pattern: $patternName'
  ```
  Same exposure — stored raw, then surfaced by the Schedule render
  paths in (b′) above.

---

## 4. Underscore-bearing reads reaching Text widgets

The slug-shape regex check `^[A-Za-z0-9_]+$` lives inside `displayNameFor`
(line 141). It is only consulted by call sites that route through the
resolver. Sites listed in (b′), (c), and (e) above accept any string —
including slugs — and emit it to a `Text` widget unchanged.

No global enforcement (e.g. a `Text.safe(...)` wrapper or an analyzer
lint) prevents a future caller from writing a slug into a `Text` widget
directly.

---

## VERDICT A: **PARTIAL**

**Why not CLOSED:**
- The centralized resolver exists and is correctly wired to the highest-
  visibility render site (the dashboard Now Playing label).
- **However**, the resolver is opt-in. Several user-facing render sites
  in Schedule, Favorites grid, AI SnackBar, and pattern-detail "Now
  Playing" overlay render the stored `patternName`/`actionLabel`/
  `event.patternName` string directly. Each of these will leak a slug
  if the writer ever stored a slug — there is no enforced read path.

**Leak surfaces that bypass the resolver (file:line):**
1. [lib/widgets/favorites_grid.dart:333](../../lib/widgets/favorites_grid.dart#L333) — favorites grid tile label
2. [lib/features/dashboard/wled_dashboard_page.dart:1280](../../lib/features/dashboard/wled_dashboard_page.dart#L1280) — SnackBar after favorite tap
3. [lib/features/schedule/my_schedule_page.dart:894, 1224, 1500, 2011](../../lib/features/schedule/my_schedule_page.dart#L894) — schedule rows + helpers
4. [lib/features/schedule/autopilot_event_detail_sheet.dart:179, 487, 501](../../lib/features/schedule/autopilot_event_detail_sheet.dart#L179) — event sheet + dialogs
5. [lib/features/schedule/calendar_entry_editor.dart:103](../../lib/features/schedule/calendar_entry_editor.dart#L103) — editor title
6. [lib/features/schedule/eviction_picker_dialog.dart:211](../../lib/features/schedule/eviction_picker_dialog.dart#L211) — eviction picker
7. [lib/features/schedule/schedule_conflict_dialog.dart:279](../../lib/features/schedule/schedule_conflict_dialog.dart#L279) — conflict dialog
8. [lib/features/schedule/schedule_overload_banner.dart:545](../../lib/features/schedule/schedule_overload_banner.dart#L545) — overload banner
9. [lib/features/ai/lumina_ai_screen.dart:503, 519](../../lib/features/ai/lumina_ai_screen.dart#L503) — AI SnackBar + ScheduleItem.actionLabel
10. [lib/features/wled/pattern_grid_widgets.dart:2070](../../lib/features/wled/pattern_grid_widgets.dart#L2070) — pattern-detail Now Playing overlay label

Audit could not confirm or deny whether any of these *currently* receives
a slug at runtime (would require running the app or tracing writer state).
The guard is structural-only — wrap each Text in `displayNameFor(...)`
or push the resolver into the model getter (e.g.
`FavoritePattern.get displayName => displayNameFor(patternName)`) to
close it.

---

# ITEM B — AI scheduling: compound temporal prompt decomposition (Item #51)

## 1. Intent layer location

**System prompt schema** (the request side):
- File: [lib/lumina_ai/lumina_ai_service.dart](../../lib/lumina_ai/lumina_ai_service.dart)
- Schema declaration: line 207-211
- Detailed schema spec: line 343-372

**Client-side extraction:**
- [lib/features/ai/cloud_ai_processor.dart:121-122](../../lib/features/ai/cloud_ai_processor.dart#L121-L122) — reads `obj['schedulingIntent']` (singular) into the WLED payload bag

**Handler:**
- [lib/features/ai/lumina_ai_screen.dart:225-232](../../lib/features/ai/lumina_ai_screen.dart#L225-L232) — dispatches on `schedulingIntent is Map`
- [lib/features/ai/lumina_ai_screen.dart:463-547](../../lib/features/ai/lumina_ai_screen.dart#L463-L547) — `_handleSchedulingIntent(Map<String, dynamic> intent, ...)`

**Bottom-sheet handler:**
- [lib/features/ai/lumina_bottom_sheet.dart](../../lib/features/ai/lumina_bottom_sheet.dart) — `grep schedulingIntent` returns **zero matches**. The most-prominent Lumina entry point silently drops scheduling intents entirely.

---

## 2. Schema shape — request vs. parsed (Item #58 asymmetry)

**Request side (system prompt at [lumina_ai_service.dart:207-208](../../lib/lumina_ai/lumina_ai_service.dart#L207)):**
```
"schedulingIntent": {
  "action": string,
  "timeLabel": string,
  "offTimeLabel": string|null,
  "repeatDays": [string],
  "patternName": string
} | null
```
A **single Map** or `null`. The schema is explicit at line 358:
> "Omit `schedulingIntent` (or set null) for one-shot/now requests."

It is impossible at the model contract to return more than one
schedule per response.

**Parsed side ([cloud_ai_processor.dart:121-122](../../lib/features/ai/cloud_ai_processor.dart#L121-L122)):**
```dart
if (obj['schedulingIntent'] != null)
  'schedulingIntent': obj['schedulingIntent'],
```
Reads it back verbatim — typed as `Object?` in the WLED payload bag.

**Handler dispatch ([lumina_ai_screen.dart:225-226](../../lib/features/ai/lumina_ai_screen.dart#L225)):**
```dart
final schedulingIntent = result.wledPayload?['schedulingIntent'];
if (schedulingIntent is Map) {
  await _handleSchedulingIntent(
    Map<String, dynamic>.from(schedulingIntent),
    result,
  );
  return;
}
```
Type guard is `is Map` — never iterates, never accepts a `List`.

**Handler body ([lumina_ai_screen.dart:514-522](../../lib/features/ai/lumina_ai_screen.dart#L514-L522)):**
```dart
final item = ScheduleItem(
  id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
  timeLabel: timeLabel,
  offTimeLabel: offTimeLabel,
  repeatDays: repeatDays,
  actionLabel: 'Pattern: $patternName',
  enabled: true,
  wledPayload: result.wledPayload,
);
await ref.read(schedulesProvider.notifier).add(item);
```
Builds **exactly one** `ScheduleItem`. No iteration. No second action.

**Type contract end-to-end is singular.** A single intent can yield
**only one** schedule action.

---

## 3. Decomposition logic — does any path split one compound prompt?

**`CompoundCommandDetector`** ([lib/features/ai/compound_command_detector.dart](../../lib/features/ai/compound_command_detector.dart)):

- `CompoundCommandResult` ([line 122-142](../../lib/features/ai/compound_command_detector.dart#L122)) carries a single `lightingIntent` string and a single optional `TemporalIntent`.
- `TemporalIntent` ([line 27-115](../../lib/features/ai/compound_command_detector.dart#L27)) has single `startDate`/`endDate`/`startTrigger`/`endTrigger`/`startHour`/`endHour` fields — no array of segments.
- `detect()` ([line 282-320](../../lib/features/ai/compound_command_detector.dart#L282)) returns one `CompoundCommandResult` per input. No multi-window path.

**`LuminaSmartScheduler.generatePlan`** ([lib/features/ai/lumina_smart_scheduler.dart:337-479](../../lib/features/ai/lumina_smart_scheduler.dart#L337-L479)):

- Takes ONE `ResolvedTheme` + ONE `CompoundCommandResult` and produces N occurrences (lines 409-457) all sharing the same theme/colors over `dayCount` consecutive days. The variation is **effect rotation only**.
- This is **multi-day same-theme**, not compound multi-theme decomposition.
- A prompt like "red and green until Dec 25, then warm white through New Year's" cannot be represented: there is no way to bind segment 1 to "red and green/end Dec 25" and segment 2 to "warm white/start Dec 26, end Jan 1".

**System prompt instructions to the AI:** lines 343-372 in
`lumina_ai_service.dart` describe a single recurring weekly/daily schedule.
Lines 367-370 explicitly relegate "full-season" multi-day spans to the
**separate** `isSchedule:true / scheduleType:"season_fill"` mechanism, which
also handles only one theme.

**No code path** turns one compound temporal prompt into multiple
sequential schedule entries with different themes.

---

## 4. Tests

`rg compound|decompos|sequential` in `test/`:
- [test/utils/async_lock_test.dart](../../test/utils/async_lock_test.dart) — unrelated (concurrency)
- [test/unit/compound_command_detector_test.dart](../../test/unit/compound_command_detector_test.dart) — 14 tests, all on **single-temporal-window** parsing (date ranges, weekdays, sunset/sunrise, clock times). **Zero tests** exercise a compound multi-theme prompt; the model's API can't represent one.

`rg schedulingIntent` in `test/`: zero matches.

---

## 5. Pre-existing audit corroboration

[docs/lumina_split_schedule_audit.md](../lumina_split_schedule_audit.md)
already documents this exact gap, including:
- "Schema-level (A): `schedulingIntent` as a single `{...}|null` object — multiple actions per response are impossible at the model contract" (line 11)
- "Handler-level (C): `lumina_bottom_sheet.dart` does **not reference `schedulingIntent` at all** (`grep` returns zero matches)" (line 177)
- Cleanup plan at lines 284-291 (extend schema to `schedulingIntents: Array<object>`, rename handler to iterate, add bottom-sheet dispatch)

This audit's findings match that document. None of the cleanup proposals
appear to have been executed.

---

## VERDICT B: **OPEN**

**Why OPEN, not PARTIAL:**

Even Prompts 1–2 only work from the **full-screen** Lumina path
([lumina_ai_screen.dart:225](../../lib/features/ai/lumina_ai_screen.dart#L225));
the bottom-sheet entry point — the dashboard's primary Lumina surface —
silently discards `schedulingIntent`. So one could argue Prompts 1–2 are
themselves only partially shipped.

Prompts 3–4 (the decomposition work) require:

| Layer | Required change | Status |
|-------|------------------|--------|
| Schema | `schedulingIntent: object` → `schedulingIntents: Array<object>` (+ few-shot examples for compound prompts) | **Not done** ([lumina_ai_service.dart:207](../../lib/lumina_ai/lumina_ai_service.dart#L207) still singular) |
| Parser | Extract array, fall back to single-element promotion for back-compat | **Not done** ([cloud_ai_processor.dart:121](../../lib/features/ai/cloud_ai_processor.dart#L121) still singular) |
| Handler | `_handleSchedulingIntent` → `_handleSchedulingIntents`, iterate, emit N `ScheduleItem`s | **Not done** ([lumina_ai_screen.dart:463](../../lib/features/ai/lumina_ai_screen.dart#L463) builds one item) |
| Bottom-sheet dispatch | Wire `schedulingIntent` reading into `lumina_bottom_sheet.dart` | **Not done** (zero references) |
| Detector | `CompoundCommandResult` carrying a list of `(TemporalIntent, lightingIntent)` pairs | **Not done** (single-pair only) |
| Tests | Compound multi-theme parse + emit test | **Not done** (zero matching tests) |

A compound temporal prompt like "red and green until Dec 25, then warm
white through New Year's" provably cannot decompose into multiple
sequential schedule entries through any current code path.

---

*End of audit. No code modified.*
