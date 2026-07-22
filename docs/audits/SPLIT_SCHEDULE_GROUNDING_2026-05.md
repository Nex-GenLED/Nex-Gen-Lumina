# Split-Schedule Grounding — 2026-05-25

Read-only grounding for compound-schedule decomposition (Item #51,
Prompts 3-4). No code modified. Sourced from the existing audit at
[docs/lumina_split_schedule_audit.md](../lumina_split_schedule_audit.md)
plus current-state reads of the handler, schema, parser, and provider.

---

## 1. Existing cleanup plan — verbatim checklist + commit 99110f8 overlap

From [docs/lumina_split_schedule_audit.md](../lumina_split_schedule_audit.md)
§ "Recommended fix scope" — Tier 1 (schema + handler unification):

- [ ] [`lib/lumina_ai/lumina_ai_service.dart`](../../lib/lumina_ai/lumina_ai_service.dart)
      — extend `_kSmartSystemPrompt` schema from `schedulingIntent: object|null`
      to `schedulingIntents: Array<object>|null`. Add 1-2 few-shot examples of
      compound prompts. Leave `schedulingIntent` as a backward-compat alias
      that gets promoted to a single-element array on read.
- [ ] [`lib/features/ai/cloud_ai_processor.dart`](../../lib/features/ai/cloud_ai_processor.dart)
      — rename or add `schedulingIntents` extraction (line 121-122).
- [ ] [`lib/features/ai/lumina_ai_screen.dart`](../../lib/features/ai/lumina_ai_screen.dart)
      — `_handleSchedulingIntent` becomes `_handleSchedulingIntents`, iterates
      the array, builds one `ScheduleItem` per entry.
- [x] [`lib/features/ai/lumina_bottom_sheet.dart`](../../lib/features/ai/lumina_bottom_sheet.dart)
      — **add** the schedulingIntent dispatch that currently exists only in
      the full-screen path. Mirror the SnackBar-confirm UX or add a sheet-local
      equivalent. **DONE in commit 99110f8.**

**Commit 99110f8 overlap (handler extraction):**

99110f8 lifted `_handleSchedulingIntent` out of `lumina_ai_screen` into a
shared top-level `handleSchedulingIntent` in
[`lib/features/ai/scheduling_intent_handler.dart`](../../lib/features/ai/scheduling_intent_handler.dart),
and wired the same call from `lumina_bottom_sheet`. The audit's bullet 4
(bottom-sheet wiring) is fully satisfied. Its bullet 3 (full-screen
handler iteration) is partially superseded: the *location* of the dispatch
moved, so when the iteration work lands, it changes ONE site — the shared
handler — rather than separately touching screen + sheet. The other two
bullets (schema upgrade + parser) are untouched.

Tier 2 (game-end anchor) and Tier 3 (Cloud Function migration) from the
audit are unrelated to commit 99110f8.

---

## 2. Current shared handler

**File:** [`lib/features/ai/scheduling_intent_handler.dart`](../../lib/features/ai/scheduling_intent_handler.dart) (110 lines total)

**Signature:**
```dart
Future<void> handleSchedulingIntent({
  required WidgetRef ref,
  required BuildContext context,
  required Map<String, dynamic> intent,
  required LuminaCommandResult result,
  required LuminaPatternPreview? preview,
  VoidCallback? onMessagePosted,
}) async
```

**Parameter inventory:**

| Param | Type | Used for |
|---|---|---|
| `ref` | `WidgetRef` | reads `luminaSheetProvider.notifier` (chat thread) and `schedulesProvider.notifier` (persist) |
| `context` | `BuildContext` | `ScaffoldMessenger.of(context)`; `context.mounted` guards each post-await UI step |
| `intent` | `Map<String, dynamic>` | the singular schedulingIntent map straight off the AI payload; reads `timeLabel`, `offTimeLabel`, `repeatDays`, `patternName` |
| `result` | `LuminaCommandResult` | source of `responseText` (assistant chat message) and `wledPayload` (attached to the ScheduleItem) |
| `preview` | `LuminaPatternPreview?` | passed to `controller.addAssistantMessage(preview: ...)` so the chat bubble shows a colored strip |
| `onMessagePosted` | `VoidCallback?` | optional — full-screen path passes `_scrollToEnd`; sheet path also passes `_scrollToEnd`. Surface-specific scroll behavior stays out of the shared helper |

**ScheduleItem construction (single, hard-coded shape):**
```dart
final item = ScheduleItem(
  id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
  timeLabel: timeLabel,                          // intent['timeLabel'] ?? 'Sunset'
  offTimeLabel: offTimeLabel,                    // intent['offTimeLabel']  (nullable)
  repeatDays: repeatDays,                        // intent['repeatDays'] OR default to all 7 days
  actionLabel: 'Pattern: $patternName',          // intent['patternName'] ?? 'Custom', prefixed
  enabled: true,
  wledPayload: result.wledPayload,
);
```

`patternName` is also fed through `displayNameFor(...)` for the SnackBar
prompt display (`displayPatternName`), but the **stored `actionLabel`
uses the raw `patternName`** — the schedule render sites pick up
resolution downstream via the read-side `_labelFromAction` /
`ScheduleItem.displayActionLabel` getter.

**Persistence call:**
```dart
await ref.read(schedulesProvider.notifier).add(item);
```
One per Add-button tap. No conflict pre-check at the handler layer; no
batch path; no rollback if a follow-on item fails.

---

## 3. Schema declaration — quoted

**File:** [`lib/lumina_ai/lumina_ai_service.dart`](../../lib/lumina_ai/lumina_ai_service.dart)

### 3a. Schema block (lines 203-211 — `_kSmartSystemPrompt`'s JSON contract)

```
- JSON schema: {"message":string,"patternName":string,"thought":string,
"colors":[{"name":string,"rgb":[R,G,B,W]}],
"effect":{"name":string,"id":number,"direction":string,"isStatic":boolean},
"speed":number,"intensity":number,"wled":object,
"schedulingIntent":{"action":string,"timeLabel":string,"offTimeLabel":string|null,
"repeatDays":[string],"patternName":string}|null,
"ephemeralSession":{"type":"post_game_revert","teamSlug":string,
"gameAnchor":{"type":"today"|"tonight"|"tomorrow"|"next"|"specific_date",
"specificDate":string|null},"revertWledPayload":object,"revertLabel":string}|null}
```

`schedulingIntent` is a single `object|null`. Not an array, not a tuple.

### 3b. SCHEDULING INTENT section (lines 343-372 — instructions the model reads)

```
═══ SCHEDULING INTENT ═══
When the user's request implies a recurring or future schedule (e.g.
"turn on Chiefs colors every Thursday night this season", "warm white
every night at sunset", "every Friday at 7pm", "Christmas pattern from
Dec 1 to Dec 31"), generate BOTH the lighting design AND a
`schedulingIntent` field in the JSON.
`schedulingIntent` schema:
  {
    "action": "add" | "replace",
    "timeLabel": "HH:MM" | "Sunset" | "Sunrise",
    "offTimeLabel": "HH:MM" | "Sunset" | "Sunrise" | null,
    "repeatDays": ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],
    "patternName": string
  }
Rules:
• Omit `schedulingIntent` (or set null) for one-shot/now requests.
• `repeatDays` uses three-letter day codes. Use all 7 for "every night",
"nightly", "daily". Use the matching subset for "every Thursday",
"weekends" → ["Sat","Sun"], "weekdays" → ["Mon","Tue","Wed","Thu","Fri"].
• If the user says "sunset"/"sunrise", set the corresponding label
literally as "Sunset"/"Sunrise" — the app resolves these from device
location.
• `patternName` mirrors the design's patternName so the schedule entry
reads naturally (e.g. "Chiefs Game Day", "Warm White Wash").
• Multi-day full-season requests (Christmas season, Halloween month,
Independence week, etc.) still use the existing `isSchedule:true` /
`scheduleType:"season_fill"` mechanism described in HOLIDAY SEASONS —
`schedulingIntent` is for recurring weekly/daily patterns, not season-fill.
• The `message` field must mention the schedule plainly: "Saved as Chiefs
Game Day every Thursday from sunset to sunrise."
```

Notable absences:
- No mention of compound or chained requests ("X then Y").
- No date-range fields (no `startDate`/`endDate`/`untilDate`) — only weekly recurrence + clock/sun time-of-day.
- No few-shot examples for compound prompts.
- Multi-day spans are explicitly punted to a *different* mechanism (`season_fill`), which is single-theme.

---

## 4. Parser — quoted

**File:** [`lib/features/ai/cloud_ai_processor.dart`](../../lib/features/ai/cloud_ai_processor.dart)
**Lines 121-122** (inside the `wled` merge block):

```dart
if (obj['schedulingIntent'] != null)
  'schedulingIntent': obj['schedulingIntent'],
```

The field is copied verbatim into the WLED payload bag as `Object?`. No
type validation, no shape normalization, no array/single coercion. The
handler downstream re-reads it with an `is Map` guard
([lumina_ai_screen.dart:226](../../lib/features/ai/lumina_ai_screen.dart#L226),
[lumina_bottom_sheet.dart:564](../../lib/features/ai/lumina_bottom_sheet.dart#L564)).

If the AI ever emits an array, today's parser would forward it unchanged
into the bag, and the downstream `is Map` guard would drop it silently.

---

## 5. schedulesProvider.add — behavior, conflict-checking, batch

**File:** [`lib/features/schedule/schedule_providers.dart`](../../lib/features/schedule/schedule_providers.dart)

### 5a. Signature

```dart
// Line 250-291
Future<void> add(ScheduleItem item,
    {ConflictResolution? resolution}) async
```

The `resolution` arg is **caller-supplied** — passed AFTER the caller has
already shown the conflict dialog. `add()` itself does **not** invoke any
dialog; if `resolution` is null it skips conflict handling entirely.

### 5b. Default behavior (resolution == null — the shared handler's case)

1. Append to `state` optimistically: `state = [...state, item];` (line 277)
2. `await _ref.read(userServiceProvider).addSchedule(userId, item)` (line 281)
3. Trigger debounced WLED sync (`_triggerWledSync()`)
4. On Firestore failure: revert `state = oldState`; show error SnackBar via `_showSaveError`

There is **no conflict pre-check in this default path.** The handler at
[`scheduling_intent_handler.dart:85`](../../lib/features/ai/scheduling_intent_handler.dart#L85)
calls `add(item)` with no resolution — conflicts are not detected, not
shown, and not blocked.

### 5c. Conflict-check API (separate, opt-in)

```dart
// Line 195-210
ScheduleConflictInfo checkConflictsForAdd(ScheduleItem item,
    {String? excludeId})
```

Returns conflicting items + calendar entry keys. Caller must:
1. Invoke `checkConflictsForAdd(item)`
2. If conflicts exist, `await showScheduleConflictDialog(context, conflicts)` ([schedule_conflict_dialog.dart:39](../../lib/features/schedule/schedule_conflict_dialog.dart#L39))
3. Pass the user's `ConflictResolution` choice to `add(item, resolution: ...)`

The pending-changes preview flow in `my_schedule_page.dart:608-616` is
the only place doing this end-to-end (and it uses `calendarScheduleProvider`,
not `schedulesProvider`, for entry-level conflict checks).

### 5d. Eviction picker — entry-level only

`showEvictionPicker` ([eviction_picker_dialog.dart:28](../../lib/features/schedule/eviction_picker_dialog.dart#L28))
is fired by a listener on `pendingEvictionRequestProvider`
([my_schedule_page.dart:191-214](../../lib/features/schedule/my_schedule_page.dart#L191-L214)).
It is triggered by `CalendarScheduleNotifier.applyEntries` when an
incoming **CalendarEntry** can't claim a WLED timer slot — it is **not
invoked** for `ScheduleItem` add.

### 5e. Overload banner

[`schedule_overload_banner.dart`](../../lib/features/schedule/schedule_overload_banner.dart)
is a passive UI element ("Includes a 'Clean Up' bottom sheet to review and
batch-delete conflicts") that reads state, not a step in `add()`.

### 5f. Batch / transaction paths

- **No `addAll` or `addBatch` method exists.** Adding N items requires N
  separate `add()` calls, each doing its own Firestore `arrayUnion`
  update (`userServiceProvider.addSchedule` at
  [user_service.dart:739-749](../../lib/services/user_service.dart#L739-L749)).
- `replaceAll(List<ScheduleItem>)` ([line 354](../../lib/features/schedule/schedule_providers.dart#L354))
  exists for the Autopilot 7-day-fan-out case but **clobbers all existing
  schedules** — not suitable for additive compound dispatch.
- Firestore write itself uses `FieldValue.arrayUnion` on a single doc
  field; no `WriteBatch` or transaction in the schedules path.
- N sequential `add()` calls means N optimistic state updates, N
  Firestore round-trips, N WLED-sync debounces, and **N independent
  failure points**. Each failure reverts only its own item; siblings
  that already succeeded stay persisted.

### 5g. Summary of relative ordering

```
caller flow today:
  1. (optional) checkConflictsForAdd  ← caller-driven, not in add()
  2. (optional) showScheduleConflictDialog
  3. add(item, resolution: ...)
       ├─ optimistic state push
       ├─ userService.addSchedule (Firestore arrayUnion)
       └─ debounced WLED sync
  4. (separate) overload banner observes resulting state

handler flow today (scheduling_intent_handler.dart):
  1. add(item)        ← skips steps 1-2 above entirely
```

---

## 6. Grouping field on ScheduleItem — none

**File:** [`lib/features/schedule/schedule_models.dart:13-166`](../../lib/features/schedule/schedule_models.dart#L13)

Full field inventory:

| Field | Type | Role |
|---|---|---|
| `id` | `String` | unique per item |
| `timeLabel` | `String` | ON time |
| `offTimeLabel` | `String?` | OFF time |
| `repeatDays` | `List<String>` | weekday codes |
| `actionLabel` | `String` | "Pattern: <name>" or "Turn Off" |
| `enabled` | `bool` | on/off toggle |
| `wledPayload` | `Map<String, dynamic>?` | full WLED state to apply |
| `presetId` | `int?` | assigned WLED preset slot (10-250) |
| `useAudioReactive` | `bool?` | audio-reactive override |
| `disabledUntil` | `DateTime?` | soft-eviction marker (Item #61) |

**Zero fields link related entries.** No `groupId`, no `batchId`, no
`sourcePromptId`, no `parentIntentId`. `toJson` / `fromJson` mirror this —
nothing to deserialize a grouping from existing Firestore records either.

Implication: if Prompts 3-4 ship without adding such a field, a compound
set ("red until Dec 25, then warm white through New Year's") persists as
two independent rows with no way for the UI to:
- Show them together in a "this came from one prompt" group
- Offer an "undo all from this prompt" bulk action
- Delete the second when the first is deleted
- Edit one and propagate the change to its sibling

This is additive scope on top of the audit's Tier 1 plan and is not
discussed in the existing doc.

---

## Three design decisions — audit coverage vs. open

### Decision 1 — Model-vs-detector decomposition

> *Where does the compound prompt get split into N intents — the AI emits
> a list, or the app pre-splits before sending?*

**Audit position:** **Model-side.** The Tier 1 plan extends
`_kSmartSystemPrompt` to declare `schedulingIntents: Array<object>` and
adds few-shot compound-prompt examples so Claude returns the array
itself ([audit lines 284, 291](../lumina_split_schedule_audit.md)).

**App-side detector unused:** `CompoundCommandDetector`
([lib/features/ai/compound_command_detector.dart](../../lib/features/ai/compound_command_detector.dart))
is consulted *before* the AI call for tier routing and date-range
extraction, but its `CompoundCommandResult` is single-theme — it cannot
represent "X until D1, then Y from D2" today. The audit does not
discuss extending the detector instead of the model.

**Audit answers this:** YES. Model-side, with the prompt-edit risk
called out explicitly ("the riskiest piece — Opus needs to reliably emit
… for compound prompts and a single-element array (or the back-compat
singular form) otherwise. Few-shot examples are essential.").

---

### Decision 2 — Boundary computation

> *For "red and green until Dec 25, then warm white through New Year's",
> who computes the date boundaries and how do they flow to ScheduleItem
> (which has no startDate/endDate fields)?*

**Audit position:** **OPEN.** The Tier 1 schema rewrite (each entry's
`{action, timeLabel, offTimeLabel, repeatDays, patternName}`) carries
**no date-range fields** — only weekly recurrence + clock/sun time-of-day.
The audit's example phrasing ("red until Dec 25, then warm white through
New Year's") needs an `untilDate` / `startDate` / `endDate` somewhere,
and the audit doesn't propose adding it.

Tangentially, `CompoundCommandDetector.TemporalIntent` *does* have
`startDate` and `endDate` ([compound_command_detector.dart:48-52](../../lib/features/ai/compound_command_detector.dart#L48-L52)),
parsed from "starting X through Y" phrases. But that data path doesn't
feed into the schedulingIntent dispatcher today, and `ScheduleItem` has
no fields to receive it ([schedule_models.dart:13-61](../../lib/features/schedule/schedule_models.dart#L13)).

Three follow-on sub-questions the audit doesn't answer:
1. Add `startDate`/`endDate` to the AI's per-intent schema, or compute
   boundaries app-side from the prompt's date language?
2. Add `startDate`/`endDate`/`untilDate` to `ScheduleItem`, or use
   `disabledUntil` (currently the Item #61 soft-eviction marker) as the
   "end" boundary?
3. How does a recurring weekly schedule (`repeatDays: ['Mon'-'Sun']`)
   coexist with a date-range bound (run nightly *until* Dec 25)?

**Audit answers this:** NO. This is the largest open design question.

---

### Decision 3 — Conflict / partial-failure batching

> *N intents become N `add()` calls. What happens when item 2 of 3 fails
> Firestore persistence — do siblings roll back? Does the SnackBar offer
> a single "Add 3 schedules" tap or one per item? Is there an
> all-or-nothing transaction?*

**Audit position:** **OPEN — not discussed.** The audit's Tier 1
estimates "80-120 LOC, 1 session, ~2-3 hours" for the schema + parser +
handler iteration, but does not call out:
- The lack of a batch `addAll` on `schedulesProvider` (today it's N
  optimistic-update-+-Firestore-arrayUnion calls in sequence).
- The lack of WriteBatch / transaction at the user-service layer
  ([user_service.dart:739-749](../../lib/services/user_service.dart#L739-L749)
  is a single-field arrayUnion).
- The eviction picker (entry-level) and conflict dialog
  (caller-driven, not invoked by `add()`) — neither is wired to a multi-
  intent flow, and a compound dispatch could collide with the user's
  existing schedule N different ways without any of those surfaces
  firing.
- UX for the SnackBar: today the singular handler offers `Add "$name"
  to your schedule at $time?` — should compound be N separate SnackBars
  (annoying), one combined SnackBar (need wording for ambiguity), or a
  modal/inline list (richer but heavier)?
- Partial-failure rollback policy: today a single `add()` failure
  reverts only its own optimistic state. With N items, if item 2 fails
  after item 1 persists, the user sees one of three: item 1 ghosted in
  but item 2 missing, item 1 ghosted out by a global rollback, or
  inconsistent state pending a retry. None of these are picked.

**Audit answers this:** NO. Significant UX + persistence design work
still required.

---

## Bottom line — what's actually decided vs. open

| Decision | Audit | Current code | Status |
|---|---|---|---|
| 1. Model vs. detector | Model-side (Claude emits array) | Schema is singular; detector unused for multi-intent | **Decided in audit** |
| 2. Boundary computation | — | No date-range fields on either AI schema or ScheduleItem | **Open** |
| 3. Conflict + partial-failure batching | — | No batch add path; conflict dialog caller-driven; per-item failure semantics | **Open** |

Additional unmentioned scope from this grounding pass:
- **ScheduleItem grouping field** (groupId / sourcePromptId) — needed if
  a compound set must be visually grouped, bulk-edited, or atomically
  rolled back. Not in the audit's Tier 1 LOC estimate.
- **Read-side display** — `_labelFromAction` and the resolver getters
  (post-commit `5fbc482` work) cover single-item rendering; a compound
  group's "from one prompt" affordance is currently impossible.
- **Bottom-sheet vs full-screen UX** — audit Open Question #2 surfaces
  this; commit `99110f8` *unified* the SnackBar UX between the two
  surfaces, which means the multi-intent UX change will land in one
  place but also commits both surfaces to the same idiom (no per-surface
  opt-out).

---

*End of grounding. No code modified.*
