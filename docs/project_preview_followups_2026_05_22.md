# Preview / Now Playing Follow-Ups — 2026-05-22

Two pre-existing display-layer bugs surfaced during on-device validation
of the cache-refresh cluster fix (`d544f61`) and the writer-migration
follow-on (`aded90b`). **Neither is caused by either fix.** Both were
present on the prior tip; the chokepoint work just made them more
visible by routing more writers through the surfaces that render the
buggy data.

Logged here so they're not lost during cluster-fix cleanup. Hardware
behavior (lights on the device) is correct in both cases — these are
**display-only** bugs in the dashboard / preview / Now Playing chip.

---

## Bug A — Label content omits color ("Solid" instead of "Solid Red")

### Symptom
After the writer-migration fix (`aded90b`), every persistent-pattern
apply correctly updates Now Playing — but the **label text itself** is
incomplete. The chip shows the effect type alone instead of effect +
color. Examples observed on Pulla:

- Scheduled red-solid fires → Now Playing reads `Solid` (expected
  `Solid Red`).
- Autopilot fires a holiday twinkle → reads `Twinkle` (expected
  e.g. `Twinkle Red/Green`).

### Diagnosis
The `applyPayloadWithLabel(payload, labelHint: …)` helper takes
`labelHint` as a string and pipes it straight into
`ActivePresetLabelNotifier.setLabelWithFingerprint`. The migrated call
sites pull their `labelHint` from these fields:

| Site | `labelHint` source field |
|---|---|
| `schedule_enforcement.dart:_enforceSchedule` | `schedule.actionLabel` |
| `autopilot_scheduler.dart:_applyPattern` | `item.patternName` |
| `scenes.dart:applySceneProvider` | `scene.name` |
| `autopilot_event_detail_sheet.dart:_previewNow` | `event.patternName` |
| `geofence_monitor.dart:_triggerAction` | `actionName` |
| `game_day_screen.dart:_lightUpNow` | `'${shortTeamName} Game Day'` |

The pre-existing source fields (`actionLabel`, `patternName`, `name`)
were authored at the time the schedule/autopilot/scene/event was
*created*, when only the effect-type token was captured. The color
component lives in the payload itself (`seg[0].col` arrays) and never
made it into the persisted label string.

So the fanout is correct — it's the **input string** that's incomplete.
The chokepoint can only forward what the caller hands it.

### Preferred fix
**Compose the label from effect + color at write-time**, so the source
fields store complete strings going forward AND the apply path can
derive a label on the fly for legacy/short labels.

Option A (cleanest, but touches every write site): at
schedule/autopilot/scene/event *create* time, build
`'${effectName} ${primaryColorName}'` and persist that into the source
field. Self-heals over time as users save new entries.

Option B (covers legacy data immediately): in `applyPayloadWithLabel`,
if the payload's `seg[0].col[0]` resolves to a named color (via the
existing `_colorToName` helper used by `scene_providers.dart`), append
that name to `labelHint` when `labelHint` doesn't already contain it.
Risks "Royals Game Day Red" cases that should stay "Royals Game Day" —
needs a heuristic or an opt-out flag.

Option C (purist): introduce a `LabelSpec { effect, color, suffix? }`
sum type and require callers to construct it. Most explicit, biggest
refactor; defer unless A and B both prove inadequate.

### Touchpoints if fixing
- Source models: `ScheduleItem.actionLabel` (in `schedule_models.dart`),
  `AutopilotScheduleItem.patternName` (in
  `models/autopilot_schedule_item.dart`),
  `Scene.name` (`scenes/scene_models.dart`),
  `AutopilotEvent.patternName` (`models/autopilot_event.dart`),
  `GeofenceConfig.actionName` (`geofence_monitor.dart`).
- Source-field write paths: schedule creation UI, autopilot generation
  service, scene save flows, event create flows, geofence settings.
- The `_colorToName` helper in `scene_providers.dart` is a candidate
  for promotion to a shared color-naming utility if Option B is taken.

### Scope estimate
- Option A: ~2 days. Touch every save flow + migration for existing
  Firestore data + tests per site.
- Option B: ~half-day. Heuristic + tests + one promoted utility.
- Option C: ~3 days plus API churn.

---

## Bug B — Stale color slots ("preview blend" symptom)

### Symptom
After applying a pattern with fewer colors than the previous pattern
(e.g. previous = 3-color red/white/blue; new = 1-color red), the
roofline preview / settings chips render colors from the **previous**
pattern alongside the new one. Two observed cases on Pulla:

- Sequence: apply red/white/blue 3-color → then apply solid red. The
  dashboard chips and roofline render keep showing white + blue slots
  alongside the red.
- Sequence: apply purple twinkle 1-color → then apply white 1-color.
  Preview renders a purple/white blend instead of pure white.

### Diagnosis — NOT a chokepoint fanout race
This was initially suspected to be a `applyPreviewSync` or
`applyPayloadWithLabel` race (one of the fanned sinks getting stale
data). It is **not**. Confirmed by:

- **Lights on the device are always correct** (single-color renders as
  single color, no blend). The device received and acted on a
  correct-shape payload. Only the dashboard's display data is wrong.
- **Reproduces on both `schedule_enforcement.dart` AND
  `autopilot_scheduler.dart`** despite those being two independent
  callers that share nothing except eventual reliance on the device's
  `col` array. Independent reproduction rules out a single-site race.
- **Reproduces on the cluster-fix-merged build (`d544f61`) before the
  writer-migration commit**, so it isn't introduced by
  `applyPayloadWithLabel`.

### Root cause
WLED's `seg[0].col` is a 3-slot fixed array. When the app builds an
apply payload for a 1-color or 2-color pattern, it writes only the
slot(s) it cares about and **omits the unused slots**. WLED's behavior
when slots are omitted from a `col` partial update is to **leave the
prior slot values in place** (a documented WLED quirk — partial JSON
updates don't clear unspecified fields).

The next time the app polls `/json/state` and reads `seg[0].col`, the
device returns the merged slot state: new slot 0 + stale slot 1 + stale
slot 2. The dashboard / settings / preview-render code reads all three
slots and faithfully renders the stale ones too, producing the
"blend."

This is **display-only** because the WLED effect engine only uses the
slots it needs for the chosen `fx` — it doesn't blend stale slots into
the actual LED output. The lights are correct because the device picks
the right slot for the effect; the UI is wrong because it renders every
non-zero slot.

### Preferred fix
**Apply path explicitly writes all 3 `col` slots on every persistent
apply, with unused slots set to `[0, 0, 0]` (or `null`).** Putting the
fix at the payload-construction layer means every writer (migrated or
not) gets coherent state, and the WLED quirk is contained to the one
place we send payloads.

Candidate code path: the pattern-payload builders in
`features/wled/wled_payload_utils.dart` (or wherever `seg[0].col` is
constructed for schedules / autopilot / scenes). Add a normalizer:

```dart
// Pad col to 3 slots, fill the unused with [0, 0, 0] so WLED's
// partial-update behavior doesn't leak prior slot state into the
// next dashboard render.
List<List<int>> _padColSlots(List<List<int>> cols) {
  final padded = [...cols];
  while (padded.length < 3) {
    padded.add(const [0, 0, 0]);
  }
  return padded;
}
```

Call it on every `seg[0].col` write in payload construction. Should
also apply to per-house assignments in
`neighborhood_sync_engine.dart:_executePattern` even though that path
is "covered" — it produces the same kind of partial payload.

### Why not fix in `applyPayloadWithLabel`?
We considered patching the chokepoint helper to pad on the way through.
Rejected because:
- The chokepoint is reached AFTER the payload is built. Padding there
  fixes the visual cache but not what the device receives — the device
  still gets a partial-shape `col` and on next poll returns the stale
  blend. We'd be fixing the symptom in one mirror while the source
  keeps producing it.
- Fixing at payload construction also fixes the polled-state path
  (which feeds the dashboard during steady-state), not just the apply
  moment.

### Touchpoints if fixing
- `lib/features/wled/wled_payload_utils.dart` (or the `WledRepository`
  layer if normalization belongs there).
- Schedule payload save flows: anywhere `wledPayload` is constructed
  with a partial `col`.
- Autopilot payload generation: `autopilot_generation_service.dart`.
- Scene `toWledPayload()` in `scenes/scene_models.dart`.
- Pattern library applies: `pattern_grid_widgets.dart`,
  `pattern_category_detail.dart`, etc. — these are covered by the
  cluster fix's fanout but still produce un-padded payloads.
- Tests: extend `wled_notifier_preview_sync_test.dart` with a
  partial-col → polled-merge regression case.

### Scope estimate
~half-day. One normalizer + audit of payload construction sites + a
regression test + on-device verification of the 3→1 color sequence.

---

## Priority / sequencing recommendation

Both are display-layer polish, not hardware bugs. Suggested order:

1. **Bug B first** (~half-day, contained at one layer, clear root
   cause). Closes the most visually obvious symptom and any user
   confusion about "is my pattern broken?"
2. **Bug A second** (~half to full day with Option B). Once Bug B's
   slot bleed is gone, the label-completeness gap will be the only
   remaining "Now Playing doesn't look quite right" complaint.

Neither blocks submission. Both can ride a polish PR.

---

## Cross-references

- Cluster fix (`d544f61`) — `merge: cache-refresh cluster fix — drift,
  Now Playing label, channel re-include`. Commit message has the full
  three-fix breakdown and `executeMemberTeardown` / `_executePattern`
  patterns that the helper followed.
- Writer-migration follow-on (`aded90b`) — `merge: route remaining
  what's-playing writers through applyPayloadWithLabel helper`. Commit
  message lists the 7 migrated writers and explicitly defers the
  remaining ~30 sites to incremental future migration via the new
  helper.
- Validated on Pulla single-app 2026-05-22 (192.168.1.108 build of
  `60c22a4` / merged as `aded90b`). Schedule-fire, autopilot exit,
  celebration-flash preservation, and cluster-fix non-regression all
  passed. Bugs A and B surfaced during the validation pass and are the
  subject of this doc.
