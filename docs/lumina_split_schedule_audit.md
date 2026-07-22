# Lumina Chat Split-Schedule Audit (Item #51)

**Date:** 2026-05-08
**Branch:** `submission/app-store-v1`
**Status:** READ-ONLY scoping — no implementation

## Executive summary

Steve at Blue Line Bar typed into the home Lumina chat: *"give me a royals baseball design for the game today, and then after the game ends resume normal blue lighting."* The app applied the Royals design but silently dropped the second intent (blue-after-game). The audit traces this to a **dual-layer failure with a third underlying gap**:

1. **Schema-level (A):** the home/dashboard chat path uses a JSON schema that defines `schedulingIntent` as a single `{...}|null` object — multiple actions per response are impossible at the model contract.
2. **Handler-level (C):** even where the schema does support arrays (the schedule-page calendar chat at `LuminaCalendarService.parseRequest` and the unwired Cloud Function `processScheduleCommand`), the home chat's bottom sheet doesn't invoke either path — it only consumes `wled` payload + (in the full-screen variant) one `schedulingIntent`.
3. **Relative-temporal gap (E):** no path supports "after game ends" as a temporal anchor. All schemas accept `HH:MM | sunset | sunrise | null`. Game-end awareness exists in `GameDayAutopilotService` but is sealed inside that service — not exposed as an AI-resolvable anchor.

The root failure is layer A in the path Steve actually used. A multi-action fix at any single layer is insufficient; this is a **D — hybrid (A + C + E)** problem.

A "smallest-shippable" fix that handles `compound prompts at all` is feasible at the schema+handler layer in ~1 focused session. Handling Steve's exact relative-temporal anchor ("after the game ends") is a separate, larger workstream that depends on resolving game end times via ESPN at AI-prompt time and probably defining a new trigger type plumbed end-to-end.

---

## Schema findings

There are **three distinct AI scheduling schemas** in the codebase, two of them in active use, one defined-but-unused.

### Schema 1 — `_kSmartSystemPrompt` (Opus, home/Lumina chat) — **Steve's path**

**File:** [lib/lumina_ai/lumina_ai_service.dart:176-421](lib/lumina_ai/lumina_ai_service.dart#L176)
**Active:** yes — used by `LuminaAI.chat()` for compound prompts that route to smart tier (line 432).

```dart
// JSON schema (line 203-208):
'- JSON schema: {"message":string,"patternName":string,"thought":string,'
'"colors":[{"name":string,"rgb":[R,G,B,W]}],'
'"effect":{"name":string,"id":number,"direction":string,"isStatic":boolean},'
'"speed":number,"intensity":number,"wled":object,'
'"schedulingIntent":{"action":string,"timeLabel":string,"offTimeLabel":string|null,'
'"repeatDays":[string],"patternName":string}|null}\n'
```

**`schedulingIntent` is `object|null` — singular.** Lines 343-350 reinforce this:

```dart
'`schedulingIntent` schema:\n'
'  {\n'
'    "action": "add" | "replace",\n'
'    "timeLabel": "HH:MM" | "Sunset" | "Sunrise",\n'
'    "offTimeLabel": "HH:MM" | "Sunset" | "Sunrise" | null,\n'
'    "repeatDays": ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],\n'
'    "patternName": string\n'
'  }\n'
```

There is **no array form, no alternatives field, no follow-up event field.** A model obeying the schema cannot encode "Royals during game, blue after."

`timeLabel`/`offTimeLabel` allow only `HH:MM`, `"Sunset"`, or `"Sunrise"`. No relative-to-event values.

### Schema 2 — `_kFastSystemPrompt` (Haiku, fast tier)

**File:** [lib/lumina_ai/lumina_ai_service.dart:117-174](lib/lumina_ai/lumina_ai_service.dart#L117)
**Active:** yes for short/simple prompts.

Schema **does not include `schedulingIntent` at all** (line 123-125):

```dart
'- JSON schema: {"patternName":string,"thought":string,"colors":[{"name":string,"rgb":[R,G,B,W]}],'
'"effect":{"name":string,"id":number,"direction":string,"isStatic":boolean},'
'"speed":number,"intensity":number,"wled":object}\n'
```

Steve's prompt would not route here (12+ words triggers smart tier per `_classifyPromptTier` at line 59), so this schema is informational rather than load-bearing for this bug. But it's a separate place to remember if multi-action support is ever introduced.

### Schema 3 — `LuminaCalendarService` calendar mode

**File:** [lib/features/schedule/calendar_providers.dart:302-338](lib/features/schedule/calendar_providers.dart#L302)
**Active:** yes — used **only** when the user chats from inside the My Schedule page ([my_schedule_page.dart:2312](lib/features/schedule/my_schedule_page.dart#L2312)).

```dart
{
  "message": "Brief friendly confirmation (1-2 sentences max)",
  "changes": [
    {
      "date": "YYYY-MM-DD",
      "pattern": "Pattern Name",
      "color": "#RRGGBB",
      "onTime": "HH:MM",
      "offTime": "HH:MM",
      "brightness": 85
    }
  ]
}
```

**`changes` is an array.** Multiple entries are explicitly supported (line 323-326):

> "For ranges (e.g. 'every Friday in April 2026', 'nightly next week'), include one entry PER matching day."

But `onTime`/`offTime` is still `HH:MM | sunset | sunrise | null` — no relative anchor. Also, this path is gated behind the My Schedule UI, not the home chat; Steve's prompt would not reach it.

### Schema 4 — Cloud Function `processScheduleCommand` (defined, unused)

**Files:**
- [functions/src/scheduling-system-prompt.ts:205-256](functions/src/scheduling-system-prompt.ts#L205)
- [functions/src/processScheduleCommand.ts:85-94](functions/src/processScheduleCommand.ts#L85)
- Exported from [functions/index.js:15-16](functions/index.js#L15)

**Active in deploy:** yes (exported from `index.js`).
**Called from app:** **NO** — `grep -r "processScheduleCommand" lib/` returns zero matches.

Schema is the most complete of the four:

```ts
"scheduleEntries": [
  {
    "name": "string",
    "zone": "string",
    "startTime": "HH:mm" | null,
    "endTime": "HH:mm" | "manual" | null,
    "days": ["monday", ...] | ["2025-12-25", ...],
    "effectId": number,
    "colors": [[R,G,B], ...],
    "brightness": number, "speed": number, "intensity": number,
    "recurring": boolean,
    "triggerType": "clock" | "sunrise" | "sunset",
    "triggerOffset": number,
    "priority": number
  }
] | null,
"conflicts": [...],
"clarificationOptions": [...],
"complexity": "SIMPLE" | "MODERATE" | "COMPLEX",
```

Supports multiple entries, server-side conflict detection, variety enhancement for multi-day plans. **Still no relative-to-event triggerType** — `clock | sunrise | sunset` only (line 80, 226).

This is the "right" schema for Steve's request shape (multi-entry), but it's never invoked from the Flutter app. The wiring gap is itself a separate finding (#51-A).

---

## Prompt findings

The smart-tier system prompt — Steve's path — explicitly limits itself to single intents and never instructs decomposition.

**Singular framing (line 211-213):**

```dart
'  • "schedulingIntent" — optional. Include when the request implies a '
'recurring or future schedule (see SCHEDULING INTENT section). Omit or '
'set null for one-shot/now requests.\n'
```

**The full SCHEDULING INTENT section (line 337-366)** never mentions:
- compound requests ("X then Y")
- decomposition into multiple actions
- relative temporal anchors (post-game, after sunset, after timer)
- examples of multi-step scheduling

The closest example of multi-day intent is the **HOLIDAY SEASONS / season_fill** branch (line 249-273), which is a fundamentally different mechanism: a single `seasonId` token expanded server-side to a date range — not a list of distinct actions.

The model, faced with Steve's prompt, has only two reasonable choices under this prompt:
1. Apply Royals as the immediate `wled` payload, omit `schedulingIntent` → second intent silently dropped.
2. Apply Royals as immediate, populate `schedulingIntent` with the post-game blue → but `timeLabel: "AfterGameEnds"` is not an allowed value, so the model would either invent a clock time (often incorrect) or omit it.

Behaviorally, choice 1 is what happened.

**No few-shot examples for compound prompts exist anywhere in the codebase.**

The calendar-mode prompt (Schema 3) does instruct decomposition — "include one entry PER matching day" — but it's about expanding a *recurrence* (every Friday), not about chaining distinct actions.

---

## Handler findings

### Path A — home dashboard bottom sheet (`lumina_bottom_sheet.dart`)

**File:** [lib/features/ai/lumina_bottom_sheet.dart:546-595](lib/features/ai/lumina_bottom_sheet.dart#L546)

**Critical finding:** `lumina_bottom_sheet.dart` does **not reference `schedulingIntent` at all** (`grep` returns zero matches). The handler reads `result.wledPayload`, applies it, sets the active label. No schedule path. No intent dispatch.

```dart
if (result.wledPayload != null) {
  preview = _extractPreview(result.wledPayload!);
  final repo = ref.read(wledRepositoryProvider);
  if (repo != null) {
    try {
      final ok = await repo.applyJson(result.wledPayload!);
      // ... set label, update metadata
    }
  }
}
```

**If Steve typed his prompt into the home dashboard bottom sheet (which is the most prominent Lumina entry point), even a perfectly-formed `schedulingIntent` from the AI would be discarded.** This is layer C.

### Path B — full-screen Lumina (`lumina_ai_screen.dart`)

**File:** [lib/features/ai/lumina_ai_screen.dart:198-216](lib/features/ai/lumina_ai_screen.dart#L198)

This handler does dispatch on `schedulingIntent`, but treats it as singular:

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

`_handleSchedulingIntent` ([line 355-439](lib/features/ai/lumina_ai_screen.dart#L355)) reads `intent['timeLabel']`, `intent['offTimeLabel']`, `intent['repeatDays']`, `intent['patternName']`, builds a single `ScheduleItem`, offers a SnackBar action to add. **No iteration; no second event.** Even if the schema were upgraded to `schedulingIntents: [...]`, this handler would only consume the first map.

The same handler also has a separate `isSchedule == true` branch ([line 198-202](lib/features/ai/lumina_ai_screen.dart#L198)) that delegates to `_handleScheduleResult` (line 283) → routes to `AutopilotScheduler.importSmartSchedule(payload)`. That path supports multi-day arrays inside `payload['schedule']`, but it's specifically for *holiday season-fill* shape, not chained actions, and isn't accessible via `schedulingIntent`.

### Path C — schedule-page calendar chat

**File:** [lib/features/schedule/calendar_providers.dart:425-467](lib/features/schedule/calendar_providers.dart#L425)

`_parseAiResponse` correctly iterates `parsed['changes'] as List<dynamic>` and builds multiple `CalendarEntry` records:

```dart
final rawChanges = parsed['changes'] as List<dynamic>? ?? [];
final changes = rawChanges
    .whereType<Map<String, dynamic>>()
    .map(CalendarEntry.fromAiJson)
    .whereType<CalendarEntry>()
    .toList();
```

This is the only handler in the codebase that genuinely consumes a list of AI-emitted events. **But this path requires the user to be inside My Schedule's chat input** ([my_schedule_page.dart:2312](lib/features/schedule/my_schedule_page.dart#L2312)) — not the home Lumina dock or full-screen Lumina.

### Path D — `processLuminaCommand` / `processScheduleCommand` Cloud Functions

Both define `commands[]` / `scheduleEntries[]` array contracts and would handle multiple actions structurally. **Neither is invoked by the Flutter app today.** Dead-code-ish on the function side.

---

## Relative temporal anchor findings

Game-end awareness exists in the codebase but is not exposed to AI scheduling.

**Where game end is computed:**

- [lib/features/autopilot/game_day_autopilot_service.dart:560-615](lib/features/autopilot/game_day_autopilot_service.dart#L560) — phase machine with `liveGame → postGame` transition gated on ESPN `gameState.status == GameStatus.final_` or estimated-duration fallback. Triggers an `onResumeNormalSchedule` callback after a 30-min countdown.
- [lib/features/autopilot/autopilot_schedule_generator.dart:263](lib/features/autopilot/autopilot_schedule_generator.dart#L263) — `postGameEnd = game.gameEnd.add(20 minutes)` for autopilot-generated week plans.
- [lib/services/sports_alert_service.dart:40](lib/services/sports_alert_service.dart#L40) — comment: "*Stored base payload to revert to after game ends.*"
- [lib/features/sports_alerts/services/game_schedule_service.dart](lib/features/sports_alerts/services/game_schedule_service.dart) — ESPN team schedule fetcher that returns upcoming games.

**Where game end is not exposed:**

- No AI prompt mentions `"AfterGameEnds"` / `"PostGame"` as a `timeLabel` value.
- Neither `ScheduleItem` (lib/features/schedule/schedule_models.dart) nor `CalendarEntry` has a "wait for event" / "trigger by external signal" field.
- No client → ESPN call at chat-parse time to resolve "today's Royals game end ≈ ~10:30 PM" before the AI sees the prompt.

**This means even if the multi-intent schema gap were fixed tomorrow, Steve's "after the game ends" anchor still couldn't be honored without additional plumbing:** either (1) prepending the AI prompt with "today's Royals game ends approximately at X:XX PM" (a context injection, similar to what `_buildPrefix` does for sunset times), or (2) introducing a new trigger type (`"trigger": "post_game_end"`) and wiring it through the schedule storage/enforcement layer + ESPN polling.

Option 1 is much smaller; the AI converts a relative anchor to a clock estimate and the user sees an approximate time. Option 2 is the correct long-term answer and is closer in shape to what `GameDayAutopilotService` already does for autopilot.

---

## Failure mode categorization

**D — Hybrid (A + C + E):**

| Layer | Status for Steve's path |
|---|---|
| A — Schema | **Blocking.** Smart-tier prompt's `schedulingIntent` is a single object. |
| B — Prompt | **Blocking.** No instruction to decompose compound requests; no examples; no relative-anchor mention. |
| C — Handler | **Blocking.** `lumina_bottom_sheet.dart` ignores `schedulingIntent` entirely; full-screen `_handleSchedulingIntent` is single-object. |
| D — Combination | All three above contribute. |
| E — Relative-temporal anchor | **Independent gap.** Even if A+B+C were fixed, "after the game ends" has no schema value, no resolver, no enforcer. |

The minimum fix for "compound prompts work at all" is A + B + C. The minimum fix for **Steve's exact prompt** is A + B + C + E.

---

## Recommended fix scope

### Tier 1 — Schema + handler unification (smallest viable)

Goal: make compound prompts produce two ScheduleItems even if the second has only a clock-time anchor.

**Files affected:**
- `lib/lumina_ai/lumina_ai_service.dart` — extend `_kSmartSystemPrompt` schema from `schedulingIntent: object|null` to `schedulingIntents: Array<object>|null`. Add 1-2 few-shot examples of compound prompts. Leave `schedulingIntent` as a backward-compat alias that gets promoted to a single-element array on read.
- `lib/features/ai/cloud_ai_processor.dart` — rename or add `schedulingIntents` extraction (line 121-122).
- `lib/features/ai/lumina_ai_screen.dart` — `_handleSchedulingIntent` becomes `_handleSchedulingIntents`, iterates the array, builds one `ScheduleItem` per entry.
- `lib/features/ai/lumina_bottom_sheet.dart` — **add** the schedulingIntent dispatch that currently exists only in the full-screen path. Mirror the SnackBar-confirm UX or add a sheet-local equivalent.

**Approximate LOC:** 80-120.

**Risk:** medium. The prompt edit is the riskiest piece — Opus needs to reliably emit `schedulingIntents: [{...}, {...}]` for compound prompts and a single-element array (or the back-compat singular form) otherwise. Few-shot examples are essential.

**Estimated session count:** 1 session, ~2-3 hours of focused prompt-and-handler work plus tablet verification.

### Tier 2 — Game-end anchor support (close Steve's loop fully)

Goal: handle "after the game ends" as a literal anchor, not a clock-time approximation.

**Two options:**

**Option E.1 — Context injection (smaller).** Before sending the prompt to Claude, the app:
1. Detects a sports/team token in the user prompt.
2. Calls `GameScheduleService` to fetch today's game for the matched team.
3. Prepends a context line: *"Royals game today scheduled to end approximately at 22:30 local."*
4. AI emits `schedulingIntent` with `timeLabel: "22:30"` (clock).

Files affected: a thin pre-processor in `lumina_ai_service.dart` or a new `lib/features/ai/sports_context_injector.dart`. Plus the prompt section telling the AI how to use this context.
Approximate LOC: 60-90.
Risk: low/medium. Game-end estimation is approximate (estimatedGameDuration buffers + extra-innings), so the user sees an inaccurate clock time; this is a UX trade-off, not a correctness bug.
Estimated session count: 1 session.

**Option E.2 — First-class `triggerType: "post_game_end"` (durable).** Extend the schedule data model with a `relativeTrigger: { type: "post_game_end", teamSlug, offsetMinutes }` field; on the enforcement side, plug into `GameDayAutopilotService`'s phase machine; on the storage side, recompute the actual fire time daily.

Files affected: `schedule_models.dart`, `schedule_enforcement.dart`, `schedule_priority_resolver.dart`, `schedule_sync.dart`, all UI that displays trigger times, plus the prompt and handler. Touches 6-10 files.
Approximate LOC: 250-400.
Risk: high. Schedule infrastructure rework. WLED preset timer slots don't natively support this — would require keeping the schedule app-side and only pushing to WLED when the resolved fire time lands inside the device timer window.
Estimated session count: 2-3 sessions.

### Tier 3 — Migrate to `processScheduleCommand` Cloud Function

Goal: stop maintaining two separate schemas (in-app prompt vs Cloud Function), use the more capable server-side schema for both home and schedule-page chat.

**Files affected:**
- `lib/lumina_ai/lumina_ai_service.dart` — point smart tier at `processScheduleCommand` callable instead of `claudeProxy` for scheduling-shaped prompts.
- `lib/features/ai/lumina_ai_screen.dart` + `lumina_bottom_sheet.dart` — handle the richer response shape (`responseType`, `conflicts`, `confirm_multi_day_plan`).

Approximate LOC: 100-150.
Risk: medium. Touches the boundary between two prompt families; needs careful tier-classifier hooks to avoid sending non-scheduling prompts to the wrong endpoint.
Estimated session count: 1-2 sessions.

This is **independent of the Steve fix** but worth surfacing as a related cleanup; running parallel chat schemas in two places guarantees future drift.

---

## Open questions for Tyler

1. **Tier scope:** smallest-shippable (Tier 1) or full Steve-loop close (Tier 1 + E.1)? The latter is the *thing the customer asked for*; the former is the architectural fix that unblocks any compound prompt and is testable today.

2. **Bottom sheet vs full-screen:** should the home dock chat (bottom sheet) be the same surface as full-screen Lumina for scheduling, or stay command-only? Today the bottom sheet is design-only — adding scheduling there changes the mental model.

3. **Cloud Function migration (Tier 3):** is this on the post-launch roadmap? If yes, Tier 1's prompt rework should aim at the existing `claudeProxy` schema (cheaper) but be designed to migrate to `processScheduleCommand` cleanly. If no, the schema rework lives in `lumina_ai_service.dart` permanently.

4. **Game-end anchor (Tier 2 E.1 vs E.2):** is "approximate clock time" acceptable interim UX, given that the autopilot session machine already does the "real" thing inside `GameDayAutopilotService`? An alternative middle path: when the AI sees "after game ends" in a sports context, *redirect the user to enable Game Day Autopilot for the team* and let that service own the post-game restore — no chat-side scheduling at all. This is closest to the existing infra and might be the right design.

5. **Steve's expected behavior:** what is "normal blue lighting" for the Blue Line Bar? Is that a saved scene? A pre-existing autopilot baseline? The "after game ends, resume normal" semantic implies a default state to revert to — which the app does support via schedule baselines, but the AI prompt has no notion of "resume the daily default."

---

## Estimated session count (totals)

| Goal | Tier | Sessions |
|---|---|---|
| Compound prompts produce multiple events at all | T1 | 1 |
| Steve's exact loop closed (clock-approx for game end) | T1 + E.1 | 2 |
| Steve's loop closed durably (post-game trigger first-class) | T1 + E.2 | 3-4 |
| Above + migrate to Cloud Function | T1 + T3 + (E.1 or E.2) | 4-5 |

The cheapest *visible* fix to the customer is T1 + E.1 (~2 sessions). The cheapest *correct* fix is T1 alone, which leaves "after game ends" producing an approximate clock time and a follow-up customer message about why the timing isn't perfect.
