# Game Time Display Audit — Item #63

**Date:** 2026-05-08
**Branch:** `submission/app-store-v1`
**Reporter:** Tyler (relayed from Steve / Blue Line Bar, Kansas City CDT)
**Symptom:** A 7:00 PM CDT Royals home game is displayed on the schedule
screen at roughly midnight — a ~5-hour offset that exactly matches the
UTC ↔ CDT gap.

## Categorization: **(B) STORAGE-SIDE**

Tyler's prior was that this would be a display-side bug (C). The audit
**refutes** that prior. The bug is at the boundary where ESPN's UTC
`GameEvent.scheduledDate` is converted into the string-typed fields of a
`CalendarEntry` (`onTime` / `offTime` / `dateKey`). Once those strings
land in Firestore as `"00:00"` / `"03:00"` / `"2026-05-09"`, the display
layer renders them faithfully — the rendered string was wrong before it
was ever drawn.

Tyler's reasoning that autopilot fires at the right time is **still
correct**, and that's exactly why the bug categorizes as (B) and not as
a deeper systemic issue: autopilot's activation logic operates on the
raw UTC `DateTime` instant (via `isAfter` / `subtract`), which is
timezone-flag-agnostic, so timing math is unaffected. Only the
*string formatting* of that DateTime is wrong.

## Pipeline trace

### 1. Parse layer — CORRECT

`lib/features/sports_alerts/services/game_schedule_service.dart:340-411`
parses ESPN's ISO-8601 `Z` timestamps into `DateTime`, defensively
re-flagging as UTC if the trailing `Z` is missing:

```dart
var scheduledDate = DateTime.tryParse(dateStr);
if (scheduledDate == null) return null;
if (!scheduledDate.isUtc) {
  scheduledDate = DateTime.utc(
    scheduledDate.year, scheduledDate.month, scheduledDate.day,
    scheduledDate.hour, scheduledDate.minute, scheduledDate.second,
  );
}
```

`GameEvent.scheduledDate` is consistently a UTC-flagged `DateTime`
(documented at [game_event.dart:25](../lib/features/sports_alerts/models/game_event.dart#L25):
"Scheduled start time in UTC."). Round-trip through `toJson` /
`fromJson` preserves the UTC flag because `toIso8601String()` emits the
trailing `Z`.

**Verdict:** Parse layer is solid. No change needed.

### 2. Storage boundary — BROKEN

[lib/features/autopilot/game_day_autopilot_service.dart:677-709](../lib/features/autopilot/game_day_autopilot_service.dart#L677-L709)
is the GameEvent → CalendarEntry conversion. Three places extract clock
fields directly from the UTC `DateTime` without `.toLocal()`:

**onTime computation (line 678-684):**
```dart
String _computeOnTime(GameDayAutopilotConfig config, GameEvent game) {
  if (config.onTimeOverride != null) return config.onTimeOverride!;
  final leadMinutes = config.effectiveLeadTimeMinutes;
  final onTime =
      game.scheduledDate.subtract(Duration(minutes: leadMinutes));
  return _formatHHmm(onTime);  // _formatHHmm reads .hour/.minute
}
```

**offTime computation (line 687-693):**
```dart
String _computeOffTime(GameDayAutopilotConfig config, GameEvent game) {
  if (config.offTimeOverride != null) return config.offTimeOverride!;
  final offTime = game.scheduledDate
      .add(config.estimatedDuration)
      .add(const Duration(minutes: 60));
  return _formatHHmm(offTime);
}
```

**`_formatHHmm` (line 695-697):**
```dart
static String _formatHHmm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';
```
`dt.hour` and `dt.minute` return UTC values when `dt.isUtc == true`.

**dateKey construction (line 707-709):**
```dart
final dateKey = '${game.scheduledDate.year}-'
    '${game.scheduledDate.month.toString().padLeft(2, '0')}-'
    '${game.scheduledDate.day.toString().padLeft(2, '0')}';
```
Same problem — UTC year/month/day, not local.

#### Concrete trace of Steve's case

Royals 7:00 PM CDT home game on May 8 →
`game.scheduledDate = 2026-05-09 00:00:00 UTC` (CDT is UTC-5).

With `leadMinutes = 60` and `estimatedDuration = 3h`:

| Field | UTC math (current, broken) | Local math (correct) |
|---|---|---|
| `dateKey` | `"2026-05-09"` | `"2026-05-08"` |
| `onTime` | `"23:00"` (May 8 UTC) | `"18:00"` (6:00 PM CDT) |
| `offTime` | `"04:00"` (May 9 UTC) | `"23:00"` (11:00 PM CDT) |

So the entry is filed under the **wrong date** (May 9, the day after the
game) AND the displayed times are **5 hours late**. Steve's report of
"around midnight" matches `"23:00"` displayed in his Central locale.
The 5-hour offset matches the UTC↔CDT gap exactly.

Note: this also means Steve sees **nothing** on the May 8 schedule row
where he expects the game, which compounds the trust erosion — both
"that time is wrong" and "where did Tuesday's game go?" stem from the
same root cause.

#### Secondary affected site

[lib/features/autopilot/game_day_autopilot_service.dart:628-642](../lib/features/autopilot/game_day_autopilot_service.dart#L628-L642)
`_isDaylightOnlyGame` calls
`SunUtils.sunsetLocal(lat, lon, game.scheduledDate)`. Sunset is a local
phenomenon, but here it is computed for the UTC date. A 7 PM CDT game
on May 8 looks up sunset for May 9, off by ~24h. Effect on the daylight
filter is small in practice (sunset moves only ~1 minute/day in May),
but it's the same root error and worth fixing in the same pass.

### 3. Display layer — CORRECT

`lib/features/schedule/my_schedule_page.dart` reads `entry.onTime` /
`entry.offTime` and runs them through
[utils/time_format.dart](../lib/utils/time_format.dart)'s
`formatTimeLabel`, which converts the `"HH:mm"` 24-hour string into
`"7:00 PM"` per user preference. The display does no arithmetic and no
timezone conversion. Given a correct stored string it produces correct
output. Given a broken stored string it faithfully renders the broken
output.

**Verdict:** Display layer is innocent. Do not change.

## Categorization rationale (why B and not C)

The naming "storage-side" might suggest the bug is in Firestore writes
or in `CalendarEntry.toJson` — it is not. Categorization (B) here means
the bug lives at the **format-conversion boundary** between the typed
`DateTime` domain (UTC) and the string-typed `CalendarEntry` domain
(meant to be local clock time). The entries persist correctly given
their string values; the values are wrong before they are persisted.

The clean fix is at that boundary — not at parse, not at display, and
not at the Firestore call.

## Proposed fix shape

Single-file change in
[lib/features/autopilot/game_day_autopilot_service.dart](../lib/features/autopilot/game_day_autopilot_service.dart):

1. `_computeOnTime` (line 682) — change
   `game.scheduledDate.subtract(...)` → `game.scheduledDate.toLocal().subtract(...)`
2. `_computeOffTime` (line 689-691) — change
   `game.scheduledDate.add(...)` → `game.scheduledDate.toLocal().add(...)`
3. `_buildCalendarEntry` (line 707-709) — change `game.scheduledDate.year/month/day`
   → `game.scheduledDate.toLocal().year/month/day` (or hoist a `local`
   variable to avoid three `.toLocal()` calls)
4. `_isDaylightOnlyGame` (line 628-642) — pass `game.scheduledDate.toLocal()`
   to `SunUtils.sunsetLocal`. `gameEnd` is fine (instant arithmetic
   compares to instant `sunset`), but the date argument needs the local
   day. Worth confirming with `SunUtils` author intent before changing.

No changes to parse layer, storage layer (`toJson`/`fromJson`), or
display layer.

No new dependencies. `.toLocal()` is standard `DateTime` API.

## Risk assessment

- **Existing data:** Entries already in Firestore for upcoming games
  carry the wrong `dateKey` / `onTime` / `offTime`. After the code fix,
  new writes will be correct, but **stale entries persist** until the
  weekly autopilot refresh re-populates. For Steve, this means he will
  still see broken times on the schedule until `populateCalendarForTeam`
  next runs for his team. Tyler may want to either:
    - Force-trigger a re-population on app startup post-fix, or
    - Document that affected customers need ~1 week for self-heal, or
    - Run a one-off cleanup script for any customers we know are affected.
  This is a **migration concern, not a code concern**, but it must be
  considered before declaring the fix ships.

- **DST transitions:** `.toLocal()` honors the device's current
  IANA-driven DST rules. A game scheduled at the moment of fall-back
  (1:30 AM ambiguous) is theoretically problematic, but ESPN doesn't
  schedule games at 1-2 AM local, so this is not a practical concern.

- **Users in non-US timezones:** Fix works for all timezones — `.toLocal()`
  uses the device's timezone, which is what the user expects to see.

- **Subusers / commercial chain locations:** If a chain operator views
  schedules for locations in a different timezone than their device,
  the schedule will display in the *operator's* device timezone, not the
  *location's*. This is a pre-existing limitation of the
  `CalendarEntry` string model (no timezone field) and is **out of scope**
  for this fix. Worth flagging to Tyler as a separate item if it matters
  for the commercial roadmap.

- **Game Day chat confirmations (Item #51 Prompt 3):** Tyler's note in
  the prompt is correct — the upcoming chat-confirmation surface would
  inherit this bug if it reads from the same CalendarEntry strings or
  from `GameEvent.scheduledDate` directly without `.toLocal()`. The
  storage-side fix here protects the CalendarEntry path; the chat surface
  needs to use `.toLocal()` when formatting from `GameEvent` directly.

## Halt point

Per Tyler's instructions: categorization is **(B) STORAGE-SIDE**, not
(C) DISPLAY-SIDE. Phase 2 fix is **NOT** applied. Awaiting Tyler's
decision on:

1. Whether to expand scope to fix `game_day_autopilot_service.dart` in
   this commit, or carve it into a dedicated commit;
2. Whether to handle the stale-data migration concern (force re-populate,
   document, or cleanup script);
3. Whether the secondary `_isDaylightOnlyGame` site is in scope.

If Tyler greenlights all three: it's still a one-file, ~4-site change
plus migration handling. Low risk, narrow blast radius.
