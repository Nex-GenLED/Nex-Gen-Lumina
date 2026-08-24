# SCHEDULING V3 — PHASE A (MODEL + TIMELINE) · PHASE B (EDITOR WIRING) · PHASE C (U-6 PROBE)

**Worktree:** `C:/Flutter Projects/lumina-schedule-v3`
**Branch:** `feat/schedule-v3-model`, from `main` @ `c14368d`
**Commits:** `23cf4f0` (Phase A) · `c9d56b8` (Phase B)
**Gate:** `flutter analyze` **0 errors, 0 new warnings** · `flutter test` **2495 pass, 0 fail, 4 skipped**
**Firmware impact:** none. `schedule_sync.dart`, the self-healer, WLED timer
writes, presets, `fire_jobs` and `base_layer_gate.dart` are **untouched** —
confirmed by `git diff --name-only` on both commits.

Input: [SCHEDULING_V3_AUDIT.md](SCHEDULING_V3_AUDIT.md), cited throughout rather
than re-derived.

---

## 0. WORKTREE SETUP, AND A SHARED-TREE INCIDENT WORTH RECORDING

`git checkout -b feat/schedule-v3-model` in the main tree moved the shared
working tree's HEAD **off `feat/design-card`**, which the parallel design window
was actively committing to. Both branches pointed at `c14368d`, so no file
moved and no work was lost — but the shared tree AND index are shared across
windows (`memory/feedback_parallel_session_build_hazards`), and this is exactly
how that goes wrong.

Recovery, in order:

1. `git status` — confirmed nothing of mine was modified.
2. `git reflog` — identified `feat/design-card` as the branch the tree was on
   (`HEAD@{1}: checkout: moving from main to feat/design-card`).
3. `git checkout feat/design-card` — restored. Verified the design window's 8
   modified + 5 untracked paths were all still present and untouched.
4. `git worktree add ../lumina-schedule-v3 feat/schedule-v3-model`.
5. `flutter pub get` in the worktree.

**Gitignored files copied into the worktree** (item f):

| File | Why |
|---|---|
| `.firebaserc` | project id for any `firebase` CLI call |
| `android/local.properties` | SDK paths |
| `android/app/google-services.json` | Android Firebase config |
| `android/key.properties` | signing config |
| `scripts/.env` | diagnostic scripts |
| `functions/.env` | functions config |

`lib/firebase_options.dart` is **tracked** and was already present.
`ios/Runner/GoogleService-Info.plist` **does not exist in the origin tree
either** — consistent with `CLAUDE.md`'s note about fallback handling for
missing native config. Nothing was needed for `analyze`/`test`, which is all
that ran here.

Both audit inputs were read by absolute path from the ORIGINAL tree; the reports
below are written into the worktree's `audit/` and committed by explicit
pathspec. **Every `flutter analyze` / `flutter test` in this report ran in the
worktree.**

---

## 1. PRE-CHECKS

### P1 — Real Firestore shape

Read with the Admin SDK across the whole `users` collection.

```
users scanned            29
users with the field     11
users with >=1 entry     11
entries total            159      max on one user: 41 (bench uid wrQRUUKy)
values WITH dateKey      159      values WITHOUT: 0
non-plain-date map keys  0
union of value fields    autopilot, brightness, color, dateKey, note,
                         offTime, onTime, patternName, sourceTag, type
per-user counts          22 12 1 18 4 8 3 15 34 1 41
```

Storage is `users/{uid}.calendar_entries` — a Firestore **map keyed
`'YYYY-MM-DD'`**, written whole-field at
[user_service.dart:846](../lib/services/user_service.dart) and read at
[:863](../lib/services/user_service.dart). A real Game Day row:

```json
{ "dateKey": "2026-05-31", "type": "autopilot", "sourceTag": "game_day",
  "onTime": "13:05", "offTime": "17:35", "brightness": 78,
  "color": "#004687", "patternName": "Kansas City Royals Colors" }
```

**Every value carries `dateKey`, 159/159.** That is the fact P4 rests on: the
value is self-describing, so the map key can be demoted to a uniqueness token
without losing the date. No key was already non-plain, so nothing had to be
reconciled.

⚠️ **Admin read = storage shape only, not client readability**
(`memory/feedback_verify_with_client_credential`). Readability was checked
separately, in the rules — see P3.

### P2 — dow:0 guards, all nine, **all intact post-change**

Re-verified by literal match in the worktree after both commits:

| # | Guard | file:line | Post-change |
|---|---|---|---|
| 1 | `_hasArmableDays` definition | [schedule_providers.dart:423](../lib/features/schedule/schedule_providers.dart) | ✅ |
| 2 | enforced on `add` | [schedule_providers.dart:639](../lib/features/schedule/schedule_providers.dart) | ✅ |
| 3 | enforced on `addAll` | [schedule_providers.dart:716](../lib/features/schedule/schedule_providers.dart) | ✅ |
| 4 | `if (dow == 0)` cfg build | [cfg_payload_builder.dart:193](../lib/features/schedule/cfg_payload_builder.dart) | ✅ |
| 5 | `if (dow == 0) continue` | [schedule_sync.dart:663](../lib/features/schedule/schedule_sync.dart) | ✅ |
| 6 | "Never arm a dead dow:0 timer" refusal | [schedule_sync.dart:1427](../lib/features/schedule/schedule_sync.dart) | ✅ |
| 7 | `if (lease.dowMask == 0)` | [calendar_entry_lease_manager.dart:1430](../lib/features/schedule/calendar_entry_lease_manager.dart) | ✅ |
| 8 | AI handler defence-in-depth | [scheduling_intent_handler.dart:470](../lib/features/ai/scheduling_intent_handler.dart) | ✅ |
| 9 | Autopilot derived-weekday repair | [autopilot_providers.dart:607](../lib/features/autopilot/autopilot_providers.dart) | ✅ |

Files 4, 5, 6 were never opened by this work. #7's line moved 1421→1430 because
a doc comment above it grew; the guard is byte-identical.

### P3 — Feature flags. **Remote Config is empty.**

```
firebase remoteconfig:get --project icrt6menwsv2d8all8oijs021b06s5
→ parameters: (empty)   parameterGroups: (empty)   version: undefined
```

The command **succeeded** and returned nothing. None of these flags is in
Remote Config; all three are Firestore `config/*` documents. Values read
2026-08-24:

| Flag | Value | Read at | Client-readable? |
|---|---|---|---|
| `config/calendar_leases.liveWritesEnabled` | **`true`** | [calendar_lease_feature_flag.dart:30](../lib/features/schedule/calendar_lease_feature_flag.dart) → consumed [calendar_entry_lease_manager.dart:156](../lib/features/schedule/calendar_entry_lease_manager.dart) | ✅ `firestore.rules:1564` |
| `config/solar_scheduling.enabled` | **`true`** | [solar_scheduling_feature_flag.dart:65](../lib/features/schedule/solar_scheduling_feature_flag.dart) → consumed [schedule_sync.dart:807](../lib/features/schedule/schedule_sync.dart) | ✅ `firestore.rules:1632` |
| `config/gameday_planner.write_jobs` | **`false`** | [planGameDayFires.ts:156, :185](../functions/src/planGameDayFires.ts) | server-only |

`gameday_planner` also carries `uid_allowlist: ["wrQRUUKy…"]` (bench only) and a
`disarmed_note` dated 2026-08-20: armed against a stale target, no jobs minted,
disarmed pending re-arm.

**This closes U-1 and U-2 from the audit, and corrects project memory.**
`memory/project_solar_schedules_never_fire` recorded solar as "created but
CLIENT CANNOT READ IT → 403 → still OFF fleetwide". A read rule now exists
(`firestore.rules:1632`, mirroring its three siblings), so both flags are
genuinely live. **Rule + value together is what makes "live" a safe claim** —
the admin value alone proves only that the document exists, which is precisely
the trap that cost a day previously. The memory file has been corrected.

Capacity consequence: solar boundaries occupy the dedicated slots 8/9 and
consume **0** general slots, so the audit's §7.4 arithmetic is the pessimistic
case.

### P4 — Backward compatibility. Composite keys, value unchanged.

**The prompt's guess was right, but the degradation is not what it assumed.**
`loadCalendarEntries` keys its result map by the **raw Firestore map key**, not
by `value.dateKey`:

```dart
// pre-V3, user_service.dart:872-878
for (final entry in raw.entries) {
  result[entry.key] = CalendarEntry.fromJson(...);   // ← raw key
}
```

So an old build given `"2026-05-31#gd_royals"` files it under that literal
string. Every lookup it performs is `entries[todayKey]` with a plain date, so
the composite row is never found: **it degrades by IGNORING, not by showing the
newest, and not by breaking.** The visible result is one entry per date — its
own pre-V3 behaviour.

**Chosen shape** ([calendar_entry_storage.dart](../lib/features/schedule/calendar_entry_storage.dart)):

```
"2026-05-31"            → the date's PRIMARY entry   (unchanged, byte-for-byte)
"2026-05-31#gd_royals"  → an additional entry
"2026-05-31#gd_chiefs"  → another
```

New builds ignore the key entirely and group by `value.dateKey` — safe because
P1 proves it is present on 159/159.

Three properties that decided it over a nested list:

1. **An old build that WRITES preserves the extras.** It round-trips its own
   state map verbatim, so composite keys survive an old-build save. A nested
   list would hand `fromJson` a `List`, throw, log "Skipping corrupt calendar
   entry", and the next save would **erase every multi-entry date**.
2. **No migration.** Existing plain-keyed documents are already valid new-shape
   documents; the 159 live rows are untouched.
3. **No arrays-of-maps** on a Firestore write path — clear of the #84 class.

Pinned by `test/features/schedule/calendar_entry_storage_test.dart`, including a
test that simulates the old loader and the old save round-trip.

**The accepted cost, recorded as instructed.** An old build's `toJson` has no
`channels` / `endMode` / `estimatedEnd` / `hardCapAt`, so any entry it rewrites
loses them (and its `entryId`, collapsing that row back to a date's primary).
Accepted because **all four are display-only in this prompt**. Under Policy B
the authoritative hard cap will be a **server-side fire job written by the
planner from `estimatedDurationMs`** ([gameDayPlanning.ts:572](../functions/src/gameDayPlanning.ts)),
not the client field. The design constraint, stated once so it cannot drift:

> **`hardCapAt` on `CalendarEntry` is never load-bearing.**

It is written into the field's own doc comment in
[calendar_entry.dart](../lib/features/schedule/calendar_entry.dart), and the
last storage test asserts the stripped-field degradation explicitly.

### P5 — Nightly restore row: **ABSENT**

[S4_RESTORE.md:4](S4_RESTORE.md): *"No dedicated nightly restore row was built —
Tyler's call, and the reframe holds."* Grep for `restoreRow|nightlyRestore|
nightly_restore|restore_row` across `lib/` and `functions/src/` returns nothing.

What shipped instead is the **`endsAt` companion restore**: the Game Day end
fire job sends a preset load, `{ps:1}` after sunset / `{ps:2}` in daylight,
chosen solarly from lat/lon —
[gameDayPlanning.ts:543-569](../functions/src/gameDayPlanning.ts), constants
`BASE_ON_PRESET`/`BASE_OFF_PRESET` at [:512](../functions/src/gameDayPlanning.ts).

**Why this gates Policy B** — S4 §B.3 states the fallback plainly: if the end
job never lands, *"the event design keeps running until the base layer's next
boundary."* That boundary is the base stomp B proposes to remove. See §6.

### P6 — Duration table, and there is no hard cap today

Table: `estimatedGameDuration(SportType)` —
[game_day_autopilot_config.dart:22-33](../lib/features/autopilot/game_day_autopilot_config.dart).
MLB 3h · NFL/NCAAFB 3h30 · NBA/WNBA/NCAAMB/NHL 2h30 · MLS/NWSL/FIFA/UCL 2h.
Server mirror: `estimatedDurationMs` [gameDayPlanning.ts:572](../functions/src/gameDayPlanning.ts).

The `+60 min` buffer appears twice, and only one is a timing decision:

- **[game_day_autopilot_service.dart:626](../lib/features/autopilot/game_day_autopilot_service.dart)** — foreground session fallback. `gameStart + duration + 60min` flips the session to `postGame` and starts a 30-minute countdown. Cap-*like*, but session-scoped, foreground-only, and it ends a phase rather than the show.
- **[game_day_autopilot_service.dart:745](../lib/features/autopilot/game_day_autopilot_service.dart)** — `_computeOffTime`, the **fabricated display off-time**. This is the one A1 removes.

Server-side there is **no cap at all**: `MIN_PLAUSIBLE_DURATION_MS`
([gameDayPlanning.ts:65](../functions/src/gameDayPlanning.ts)) is a *floor*
guarding against ending too early — the opposite.

`hardCapAt` is therefore derived as **`gameStart + estimatedGameDuration(sport)
+ 60min`**, matching the existing foreground fallback so **no second constant is
introduced** (approved, item 4).

---

## 2. WHAT SHIPPED

### Phase A — `23cf4f0`

Explicit pathspec (23 paths):

```
lib/features/schedule/{calendar_entry,calendar_entry_set,calendar_entry_storage,
  calendar_providers,calendar_entry_lease_manager,day_timeline,
  day_timeline_providers,schedule_models,schedule_overload_banner,
  schedule_providers,my_schedule_page}.dart
lib/features/schedule/widgets/timeline_row.dart
lib/features/schedule/day_resolution.dart                    (deleted)
lib/features/dashboard/wled_dashboard_page.dart
lib/features/autopilot/{background_learning_service,game_day_autopilot_providers}.dart
lib/features/autopilot/screens/autopilot_calendar_screen.dart
lib/services/user_service.dart
test/features/schedule/{day_timeline,day_timeline_widget,
  calendar_entry_storage,schedule_addall}_test.dart
test/features/schedule/day_resolution_test.dart              (deleted)
```

**A1 — a date holds many entries.** `CalendarEntry` gains `entryId`; identity is
`(dateKey, entryId)`. State moves `Map<String,CalendarEntry>` →
`CalendarEntrySet`, which keeps a Map-shaped read surface (`operator []`,
`primaries`) so the ~20 call sites that legitimately reason one-per-date did not
have to change semantics. New fields: `channels` (bus indices, written null,
consumed by nothing), `endMode`, `estimatedEnd`, `hardCapAt`. `channels` is also
added to `ScheduleItem`.

**The fabricated Game Day off-time is gone from new writes and reinterpreted on
read.** Per instruction 3: no fleet repair. A `sourceTag == game_day` row with an
`offTime` and no stored `endMode` reads back as `untilGameEnd` with that time
demoted to `estimatedEnd`, labelled as an estimate. Scoped to `game_day` on
purpose — a user or holiday `offTime` is a real boundary and keeps meaning one.
Five legacy-read tests, including the overnight roll and the
explicit-`endMode`-wins case.

**A2 — the timeline.** `resolveDayTimeline(inputs, policy)` returns every row.
Dated entries no longer mask recurring. 17 unit tests across cases (a)–(g), both
policies.

**A3 — surfaces.** Tonight card: two rows + "+N more". Day hero: the full
timeline, with an OFF stat chip that states a condition rather than a clock time
for open-ended rows. Week cell: count badge + stacked dots. `day_resolution.dart`
is **deleted**, not left beside the timeline — its `others`/`totalCount` were
dead plumbing nothing read (audit §3.1).

Two drifted copies of `_labelFromAction` were found and collapsed into one
`timelineLabelForAction`; one of them split on the first `:` unconditionally and
turned `"Brightness: 70%"` into `"70%"`.

### Phase B — `c9d56b8`

```
lib/features/schedule/my_schedule_page.dart
lib/features/schedule/calendar_entry_editor.dart
lib/features/schedule/autopilot_event_detail_sheet.dart      (deleted)
test/features/schedule/entry_editor_wiring_test.dart
```

**B1.** The detail sheet gains `_EditEntryButton`: a recurring row →
`showScheduleEditor(editing:)`, a dated row → `showCalendarEntryEditor`, which
gains its first reachable call site. `showAutopilotEventDetailSheet` was
re-checked after wiring, found still unreferenced, and **deleted** (grep across
`lib/` and `test/` returns only a comment).

The calendar editor exposes `onTime`, `offTime`, `brightness`, and a
this-game/all-games scope. It now **hides the off-time picker for an open-ended
entry** and shows a read-only end block instead: the condition, the estimate,
and — when stored — the cap, worded as *"If it never reports final, the show
stops by HH:MM."* `hardCapAt` is displayed, never editable. Saving an
open-ended entry writes no `offTime`, so the editor cannot reintroduce the
fabricated end.

**B2.** Day tap = select **and** open, one gesture. The day sheet lists the
timeline (not the lead row), and each row opens its own detail. The day hero's
own tap routes to the day sheet when `count > 1`.

**B3 — save paths, unchanged, no new firing code:**

| Save | Path |
|---|---|
| Recurring | `composeEditedSchedule` [my_schedule_page.dart:4772](../lib/features/schedule/my_schedule_page.dart) → `add`/`update` [:4787-4789](../lib/features/schedule/my_schedule_page.dart) → `userService.addSchedule/updateSchedule` + `_triggerWledSync()` [schedule_providers.dart:672, :820](../lib/features/schedule/schedule_providers.dart) → 800 ms debounce → `syncAll` |
| Dated, this game | `_onSave` [calendar_entry_editor.dart:363](../lib/features/schedule/calendar_entry_editor.dart) → `_saveThisGameOnly` [:469](../lib/features/schedule/calendar_entry_editor.dart) → `applyEntries` [:494](../lib/features/schedule/calendar_entry_editor.dart) → `saveCalendarEntries` + lease hook |
| Dated, all future games | `_saveAllFutureGames` [:516](../lib/features/schedule/calendar_entry_editor.dart) → `updateTeamSettings(onTimeOverride, offTimeOverride)` [:525](../lib/features/schedule/calendar_entry_editor.dart) |

---

## 3. THE TAKEOVER DERIVATION, AND THE ONE CONSTANT

**The selector** — [day_timeline.dart:69](../lib/features/schedule/day_timeline.dart),
passed by exactly one caller ([day_timeline_providers.dart](../lib/features/schedule/day_timeline_providers.dart)):

```dart
const PrecedencePolicy kActiveSchedulePrecedence = PrecedencePolicy.lastWriteWins;
```

**`lastWriteWins` — today's truth. This is the function Prompt 4 replaces.**

```dart
List<TimelineEntry> _deriveLastWriteWins(List<TimelineEntry> rows) {
  final out = <TimelineEntry>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.startsAt == null || row.conflict) { out.add(row); continue; }

    TimelineEntry? successor;
    for (var j = i + 1; j < rows.length; j++) {
      final cand = rows[j];
      if (cand.startsAt == null) continue;
      if (cand.startsAt!.isAfter(row.startsAt!)) { successor = cand; break; }
    }
    if (successor == null) { out.add(row); continue; }

    final stillRunning =
        row.endsAt == null || row.endsAt!.isAfter(successor.startsAt!);
    out.add(stillRunning
        ? row._copy(takenOverAt: successor.startsAt,
                    takenOverByLabel: successor.label)
        : row);
  }
  return out;
}
```

A row is taken over by the next row starting strictly later, when it would
otherwise still be running. A conflicted row claims no takeover, because we do
not know which of the two is running.

**`holdUntilEnd` — Policy B, implemented and tested, NOT selected.** A Game Day
holds; base rows starting inside its window are marked `suppressed` with a
`suppressedUntil`, and the Game Day carries `holdsUntil`.

**One design correction made during implementation, worth recording.** The first
version ended the hold at `min(hardCapAt, estimatedEnd)`, reading `estimatedEnd`
as a proxy for the ESPN final. That is wrong, and test (a) caught it. A hard cap
is a **ceiling**; an estimate is a **caption**. Taking the minimum would end the
window at a guessed time and present that as the schedule — reintroducing the
exact fabricated-end defect A1 removes. Corrected to:

```dart
/// The cap, always, when there is one. `estimatedEnd` is the fallback for a
/// legacy row that carries an inferred estimate and no cap.
DateTime? _holdEndFor(TimelineEntry row) => row.hardCapAt ?? row.estimatedEnd;
```

**Where Prompt 4 changes things:** `_deriveHoldUntilEnd` becomes the selected
branch by flipping `kActiveSchedulePrecedence`. Nothing downstream re-derives
takeover — the surfaces render what these two functions return — so the flip is
one constant. **It must not happen alone**; see §6.

---

## 4. NIGHTTRACKBAR EVALUATION (A3, required report)

Evaluated as the day-hero renderer and **rejected**. It stays unreferenced and
untouched; the day hero uses a multi-row list (`DayTimelineList`).

What it lacks, from reading all 399 lines of
[night_track_bar.dart](../lib/features/schedule/widgets/night_track_bar.dart):

1. **`List<ScheduleItem>` only** (`:17`). It cannot render a `CalendarEntry` at
   all, so **every Game Day and every dated entry is invisible to it** — the
   core requirement.
2. **A 6pm→6am axis with daytime clamped to the edges** (`_timeToPosition`,
   `:56` — `hour < 12 ? 1.0 : 0.0`). The 13:05 MLB matinee that exists in the
   real fleet data (P1 sample) collapses onto the right edge, i.e. renders as if
   it were sunrise.
3. **No open-ended representation.** `endPos = 1.0` when there is no off time
   (`:229`), so an open-ended Game Day is drawn running to sunrise — asserting
   exactly the false end A1 removes.
4. **No vocabulary for takeover, suppression, or conflict.**
5. **44 px with in-bar labels** and no `+N` affordance; 3+ overlapping entries
   collide.

Wiring it would mean changing its input type, rewriting its axis, and adding
three visual states — i.e. replacing it. Its colour-derivation helpers
(`_styleFromPayload`, `_styleForPattern`) are the genuinely reusable part and are
a candidate for a later extraction.

---

## 5. DEFERRED, AND WHY

| # | Deferred | Why |
|---|---|---|
| D1 | **Multi-entry LEASING.** `calendarLeaseEntriesProvider` still feeds `.primaries` — one entry per date. | The lease registry is keyed by `dateKey` (`_activeLeases[entry.dateKey]`). Handing it two entries for one night makes them fight over one slot: each sweep arms one, overwrites with the other, reports success both times. Leasing per `(dateKey, entryId)` is a **firing-layer change** and needs more WLED slots than the 8-slot pool has (audit §7.4). Marked in-code at [calendar_entry_lease_manager.dart:120](../lib/features/schedule/calendar_entry_lease_manager.dart). |
| D2 | **Conflict detection, overload banner, priority resolver, habit learning, `findCurrentSchedule`** all read `.primaries`. | Each is defined over one entry per date. Widening them changes conflict semantics and — for `findCurrentSchedule` — what `ScheduleEnforcementService` re-applies to the device. Behaviour preserved exactly. |
| D3 | **`_CalDayCell` still receives no recurring schedules** ("defect C"). | It now shows a dated-entry count, but the zoomed grid cells are ~20 px and `_ZoomedCalendarSection` would need the schedule list threaded through two more widgets to compute a full timeline it has no room to render. |
| D4 | **`channels` is inert.** | By instruction. Also correct: the firing layer cannot honour it (audit F2-2/F2-3), and the self-healer would overwrite a channel-scoped preset. See §7. |
| D5 | **`estimatedEnd` for a legacy row uses the stored `offTime`.** | The genuinely correct value would be `gameStart + estimatedGameDuration(sport)`, but a legacy row carries no sport and no game start. Using the stored value is the honest floor: it is what the row already claimed, now labelled as an estimate rather than a fact. |
| D6 | **Widget tests exercise `DayTimelineList` / `TimelineCountBadge`, not `_buildTonightCard` / `_DayHeroCard` / `_WeekDayCell` directly.** | Those are private. Rather than test a copy of their logic, the three surfaces were **refactored onto the shared components** so the tests drive the real thing. The composition (`maxRows: 2` vs `null`) is the only untested line. |

---

## 6. GATES ON THE POLICY B PROMPT

Recorded from P3/P5 as notes. **Not acted on here.**

1. **`config/gameday_planner.write_jobs` is `false`** — disarmed 2026-08-20,
   `uid_allowlist` bench uid only. The end fire job that would release a Policy-B
   hold **has never executed in production**. B cannot flip until that path is
   live and proven, because suppressing the base before then removes the only
   working recovery.
2. **No nightly restore row exists** (Tyler's call, [S4_RESTORE.md](S4_RESTORE.md)).
   The `endsAt` companion restore — `{ps:1}`/`{ps:2}`, solar-chosen — is the end
   mechanism, and it rides that same disarmed path. **The cap under B must be a
   planner-written fire job that lands when ESPN final has not.**
3. **Mixed-version writes strip the new fields** (P4). B needs either the
   server-side cap (preferred — item 2 above, and the reason `hardCapAt` is
   documented as never load-bearing) or a minimum-build gate before `hardCapAt`
   matters.

A fourth, from S4 §B.3, worth carrying: with the end job absent the design runs
until the base layer's next boundary — for a sunset-on/sunrise-off house, until
sunrise. That is ~11 hours of team colours. It is the floor B is removing, so B
must supply a better one before removing it.

---

## 7. WHAT I WOULD HAVE HAD TO FABRICATE, AND DIDN'T

- **Production flag values.** Read them (P3) rather than guessing, and checked
  the read RULE separately rather than inferring client-readability from an
  admin read.
- **Whether solar/leases are live.** Project memory said solar was off fleetwide
  behind a 403. Rather than trust it or overwrite it on the strength of one
  admin read, I checked `firestore.rules` for the read block. Both are live; the
  memory file is corrected with the method noted.
- **A hard-cap constant.** None exists server-side; `MIN_PLAUSIBLE_DURATION_MS`
  is a floor, not a cap. Rather than invent a number, `hardCapAt` reuses the
  existing foreground fallback's arithmetic.
- **`estimatedEnd` for legacy rows** — see D5. A per-sport recomputation would
  have required a sport and a game start the row does not carry.
- **Sunrise/sunset when coordinates are missing.** A solar label with no sun
  time resolves to `null` and the row is flagged `timeUnresolved`, shown with its
  raw label. It is never placed at an invented hour — the same rule
  `parseTimeLabel` enforces on the firing side.
- **A takeover for a same-minute overlap.** Today's order genuinely is
  indeterminate (audit §4.4: "last write wins, with no arbiter"), so it is marked
  CONFLICT and left unresolved.
- **Whether `psave` preserves per-segment `on:false`.** Measured on hardware
  rather than reasoned about — Phase C.
- **Whether the self-healer would leave a channel-scoped preset alone.** NOT
  tested. The code says it would not. Recorded as an open item in the probe
  report rather than asserted.

---

## 8. PHASE C — U-6 BENCH PROBE

**Answer: PRESERVED.** WLED 0.15.1 stores per-segment `on:false` through
`psave` **and asserts it on load** — a segment lit at load time goes back off.
Identical with and without `ib:true`/`sb:true`.

Full evidence, all six steps, plus the restore verification:
**[U6_PSAVE_PROBE.md](U6_PSAVE_PROBE.md)**

The consequence for F2: **the firmware was never the blocker.** The audit's
F2-2 ("every system preset is FULL-STRIP by construction") is a statement about
Lumina's preset builders, not about WLED. The real blocker is F2-3 — the
self-healer treats a channel-excluded ON preset as damage and overwrites it
([schedule_sync.dart:1889](../lib/features/schedule/schedule_sync.dart), rationale
at [:464-470](../lib/features/schedule/schedule_sync.dart)) — and that premise is
what F2 has to change. The `channels` field added in A1 is the thing that would
let the healer tell exclusion from damage.

Bench left byte-identical to its captured baseline; scratch preset 250 deleted;
all 20 pre-existing presets intact.
