# MULTI-ENTRY DAYS — only one entry shows

**Status:** diagnosis only. Read-only. Nothing fixed, nothing designed.
**Date:** 2026-08-10 · **Repo:** `main` @ `679f32c`, `2.5.10+67`

---

## VERDICT — it is not one bug, it is TWO, on two different stores

They present identically to a customer, which is why it reads as a single
problem. They are not, and they do not have a common fix.

| store | shape | severity |
|---|---|---|
| `calendar_entries` (dated) | **STORAGE** — multiple entries for one date are **not representable**. A second entry **overwrites** the first. | **Data loss** |
| `schedules` (recurring) | **DISPLAY** — every matching schedule IS read into a list; only `.first` is rendered. | Display gap |

So the answer to "display, read, or storage" is **storage for dated entries and
display for recurring ones**. Neither surface has a read bug: both read
correctly for what the store can hold.

---

## 1. One component or two? — **TWO independent implementations, shared data**

| surface | widget | file |
|---|---|---|
| Schedule screen, week strip | `_WeekDayCell` | `my_schedule_page.dart:2095` |
| Schedule screen, month grid | `_CalDayCell` | `my_schedule_page.dart:2488` |
| Home screen, "tonight" card | `_buildTonightCard` | `wled_dashboard_page.dart:1327` |

No shared day-summary widget. Each open-codes its own resolution and each
independently makes the same two mistakes.

They DO share the data sources — `calendarScheduleProvider` and
`schedulesProvider` — so the storage half is one fix, but **the display half is
three fixes, not one.**

> `ScheduleDayRow` (`schedule_day_row.dart`) and `SchedulePlanDay`
> (`schedule_plan_controller.dart`) look like the shared component but are
> referenced only by each other. **Neither live surface uses them.** Anyone
> fixing "the day row" will likely find this file first and fix nothing.

---

## 2. Can a day hold multiple entries at all? — **NO, by construction**

```dart
// user_service.dart:838
Future<bool> saveCalendarEntries(String userId, Map<String, CalendarEntry> entries)

// calendar_providers.dart:44
class CalendarScheduleNotifier extends StateNotifier<Map<String, CalendarEntry>>
```

`Map<String, CalendarEntry>` keyed by `'YYYY-MM-DD'`. **One entry per date is the
type.** A second entry for the same date replaces the first at every layer —
in-memory state, the Firestore write, and the reload.

The codebase already knows this. `calendar_providers.dart:138`:

```dart
/// Returns date keys from [entries] that would OVERWRITE an existing
/// [CalendarEntryType.user] record. Used by autopilot to decide
/// whether to show a conflict card.
List<String> findUserConflictKeys(List<CalendarEntry> entries)
```

A conflict dialog exists — **but only on the autopilot write path.** It protects
a user entry from being clobbered by autopilot. It does not fire for a user
writing a second entry over their own, and it is not a general guard.

### Production confirms it (read 2026-08-10)

```
accounts with calendar_entries : 7
total date keys                : 71
LIST-valued keys               : 0
```

Every date maps to a single object across the entire fleet. Not one date holds a
list. The structure has never held more than one entry per day, so there is no
existing data to migrate — **and no way to tell how many entries customers have
already lost**, because an overwrite leaves no trace.

---

## 3. What each surface actually renders

### Schedule screen — week strip (`_WeekDayCell`)

```dart
final calEntry = pendingEntries[key] ?? calEntries[key];   // map lookup → ONE
final recurringItems = _itemsForWeekday(scheduleItems, wd); // a LIST

final patternName = calEntry?.displayName ??
    (recurringItems.isNotEmpty
        ? _labelFromAction(recurringItems.first.actionLabel)   // ← .first
        : null);
final rawOnTime = calEntry?.onTime ?? recurringItems.firstOrNull?.timeLabel;
```

The recurring list is fully populated and then **collapsed to `.first`**. Nothing
counts it, and nothing indicates more exist.

### Home screen — tonight card (`_buildTonightCard`)

```dart
final calEntry = calEntries[todayKey];                       // map lookup → ONE
final recurring = schedules.where(/* weekday match */).toList();
final first = recurring.isNotEmpty ? recurring.first : null; // ← .first
final patternName = calEntry?.displayName ?? (first != null ? ... );
```

Structurally identical, independently written.

### Schedule screen — month grid (`_CalDayCell`) — **a third, distinct gap**

```dart
class _CalDayCell extends StatelessWidget {
  final CalendarEntry? calEntry;   // ← that is ALL it receives
```

It takes **no recurring schedules at all.** A day covered only by a recurring
schedule renders as empty in the month view — not "one of several", but *none*.
That is a separate defect from the one reported and worth confirming with Tyler
before it gets folded in.

---

## 4. Which entry wins?

**Between stores — the dated entry always wins.** Every surface uses
`calEntry?.x ?? recurring...`. A single dated entry **masks every recurring
schedule on that day**, however many there are.

**Among recurring — `.first`, and it is deterministic, not arbitrary.** The list
is ordered by `ScheduleItem.sortKey`, which is insertion order
(`schedule_providers.dart:47,534-552` — subcollection reads are ordered by
sortKey specifically to reproduce the legacy array's insertion order). So
**`.first` is the oldest-created schedule matching that weekday.**

That is better than the feared "arbitrary" — the behaviour is predictable and
reproducible. It is still wrong, and it is the *least* useful choice: a customer
adding a new schedule to a day that already has one sees **no change at all**,
because the newest entry sorts last and is the one dropped. That is the most
likely way this gets noticed and the most likely to read as "the app didn't save
it".

**Between pending and saved** — `pendingEntries[key] ?? calEntries[key]`, so an
unsaved edit correctly shadows the stored one. Not a defect.

---

## 5. What this means before anyone designs a fix

- **The dated-entry half is not a display change.** It needs the stored shape to
  hold more than one entry per date, which is a model + write-path + read-path
  change with a migration. Making the UI render a list first would render a list
  that can never have more than one element.
- **The recurring half is genuinely display-only** and could be fixed in the
  three widgets without touching storage — but doing only that would make the
  inconsistency worse, not better: recurring days would show everything while
  dated days silently keep overwriting.
- **The masking rule (`calEntry ?? recurring`) is a product decision, not a
  bug**, and it is load-bearing. Whatever replaces it has to say what a day with
  one dated entry AND two recurring schedules should show.

---

# §2 — SCOPE OF THE FIX (design only, 2026-08-10)

Three defects, two stores. **Nothing here is implemented.**

## A — STORAGE: a date must hold N entries

### A1 — Smallest change: **the VALUE becomes a list, not a keyed discriminator**

| option | shape | verdict |
|---|---|---|
| **List value** | `Map<String, List<CalendarEntry>>` | **RECOMMENDED** |
| Key discriminator | `Map<String, CalendarEntry>`, key `'YYYY-MM-DD#<id>'` | **Reject** |

**Why the key must not change.** The date key is load-bearing far beyond
display. Every reader does `state[dateKey]` / `entryFor(dateKey)` /
`pendingEntries[key]` with a plain `'YYYY-MM-DD'`. Adding a discriminator makes
all of those return `null` — a **silent** miss, not a failure. A no-op lookup
that compiles is the worst possible outcome for a change touching 25+ call
sites.

**Why the list value is the safe one.** Changing `CalendarEntry` to
`List<CalendarEntry>` is a **compile-time break at every reader**. Dart's type
system enumerates the work for us — the migration cannot be partially applied
and silently ship. That property is worth more than the syntactic tidiness of
the key option.

**But the key change is still forced, in one place.**
`calendar_entry_lease_manager.dart:296` documents
`CalendarEntry.dateKey` as **the lease registry key**. Once a date holds N
entries, two entries on one date collide over a single lease slot. So:

- `CalendarEntry` gains a **stable `id`**, and
- the **lease registry re-keys on that id**, not on `dateKey`.

That is the real cost of A1 and it lands in P0-9 territory (the lease ledger is
device-local, persisted in prefs, and its Firestore migration is still design
only — `audit/LEASE_LEDGER_MIGRATION.md`). **A1 cannot be scoped without the
lease ledger owner.**

### A2 — Migration: nothing structural, one dangerous asymmetry

0 of 71 date keys are list-valued, so there is **no backfill**. The risk is the
other direction:

> `user_service.dart:875` — `if (entry.value is Map<String, dynamic>)`
> **A list value fails this test and is SILENTLY SKIPPED.**

So an **older app version reading new-format data drops every dated entry with
no error**. Not a display gap — the entries vanish from that client, and if that
client then saves, it writes back a map without them. **This is a data-loss
rollout hazard and it gates the whole of A.** Mitigation is a dual-format read
shipped at least one release BEFORE any list write, or a version gate — not
optional, and the reason A1/A2 cannot go first.

**Readers to update** (compile-time enumerated once the type changes):

| reader | file | needs |
|---|---|---|
| load / save | `user_service.dart:838,864` | dual-format read; list write |
| notifier state + `entryFor` | `calendar_providers.dart:44,476` | `List<CalendarEntry>` |
| conflict detection | `calendar_providers.dart:138` | per-entry, see A3 |
| **lease registry** | `calendar_entry_lease_manager.dart:110,296` | **re-key on entry id** |
| lease entry list | `calendar_entry_lease_manager.dart:109` | flatten N per date |
| week strip / month grid / AI card | `my_schedule_page.dart:197,701,711,1874` | list |
| home tonight card | `wled_dashboard_page.dart:1330` | list |
| Game Day autopilot | `game_day_autopilot_providers.dart:93,189,909` | list + conflict semantics |
| background learning | `background_learning_service.dart:135` | list |
| autopilot calendar screen | `autopilot_calendar_screen.dart:284` | list |
| overload banner | `schedule_overload_banner.dart:62,241` | **count semantics change** |
| schedule providers | `schedule_providers.dart:441` | list |
| entry editor | `calendar_entry_editor.dart:399` | which entry is being edited |
| sync→calendar bridge | `sync_event_calendar_bridge.dart` | may now append |

### A3 — INTERIM GUARD — ✅ **IMPLEMENTED 2026-08-10**

**Enforced at the WRITE, not only in the UI.** `applyEntries` gained
`overwriteAcknowledged` (default `false`); if a write would replace a
user-authored dated entry without it, the write is **REFUSED and returns
`false`** with a named debugPrint. That is the answer to "confirm the guard
cannot itself fail silently": a guard living in a widget is bypassed by the next
call site that forgets it, and this codebase has a long list of guards that
reported success for work never done. A new UI path that skips the prompt gets a
refused write surfaced through the caller's existing failure handling — not
silent data loss.

**Dialog, not `presetErrors`.** `presetErrors` is a POST-hoc report rendered
after a sync has already run. This is a PRE-write decision about a destructive
action: the answer is needed before anything is lost. Telling someone what you
just destroyed is not a choice.

**No "keep both".** `ConflictResolution` already has a `keepBoth` member and is
deliberately NOT reused — storage cannot represent two entries for one date
(A1 unbuilt), so offering it would promise what the write cannot deliver. The
new `DatedOverwriteChoice` has exactly `{ replace, cancel }`, and a test pins
that it never grows a third option. The dialog also states plainly *"A day can
only hold one saved entry. The old one is not kept."*

**Scope of detection** — `findDatedOverwrites` flags only a **user** entry
landing on an existing **user** entry:

| incoming → existing | flagged | why |
|---|---|---|
| user → user | **yes** | authored work, unrecoverable |
| user → empty | no | the common path takes no new friction |
| user → holiday / auto | no | generated, not authored |
| autopilot → user | no | has its own flow (`resolveAutopilotConflicts`); double-guarding would prompt twice |

**Wired at both user write paths:** `calendar_entry_editor.dart:399` (save this
game only) and `my_schedule_page.dart:712` (pending-batch apply). Dismissing the
dialog returns `cancel` — a destructive action never defaults to proceeding.

**Verified:** 7/7 new unit tests; full suite **2025 passed / 3 skipped / 1
pre-existing failure**; `flutter analyze lib/` **0 errors, 0 warnings**.

**LIMIT:** this does not preserve the replaced entry and is not a fix. It makes
the loss deliberate. A1 remains the fix.

#### Original scoping

`findUserConflictKeys` already detects exactly this case and is already
documented as detecting overwrites. It is only wired to the autopilot-over-user
direction. Extending it to warn a **user writing over their own entry** converts
silent data loss into a visible choice.

- No storage change, no migration, no lease impact.
- Reuses the existing conflict dialog (`schedule_conflict_dialog.dart`).
- Bounded to the user-initiated write paths (`calendar_entry_editor.dart:399`,
  the AI card, `my_schedule_page.dart:701,711,1874`).
- **Caveat to state honestly:** this does not preserve the second entry. It
  makes the loss deliberate rather than invisible. That is a real improvement
  and is not a fix.

## B — DISPLAY: one shared resolution, three consumers

### B1 — Shared component + delete the decoy

Scope a **pure resolution function**, not a widget — the three surfaces have
irreconcilable layouts but identical logic:

```
resolveDay(dateKey, datedEntries, recurringItems, {preferNewest})
  → { primary, others, totalCount, source }
```

Pure and unit-testable, no rendering opinion. Each surface renders it its own
way.

> **TRAP — fix this in the same pass.** `ScheduleDayRow`
> (`schedule_day_row.dart`) and `SchedulePlanDay`
> (`schedule_plan_controller.dart`) look exactly like this component and are
> referenced **only by each other**. Anyone assigned "fix the day row" will find
> them first and fix nothing. **Delete them, or rename to `*_Unused_*`, in the
> same PR.** Leaving them is how this bug gets "fixed" twice without changing
> behaviour.

### B2 — What a multi-entry day should look like — **proposal, needs a decision**

Space differs by an order of magnitude, so one treatment will not serve all three:

| surface | space | proposed |
|---|---|---|
| Week strip (`_WeekDayCell`) | ~1/7 width × 118px | Primary entry as today **+ a `+N` chip**. No second row — the cell is already dense. |
| Month grid (`_CalDayCell`) | a few mm | **Dot count only** (up to 3 dots, then a denser dot). No text survives at this size. |
| Home tonight card | full width | **Stacked list**, up to 2 rows, then `+N more`. The only surface with room to show real content. |

Open for Tyler: is a multi-entry day a normal state to display, or an
**exception to flag**? A `+N` chip says "normal, more available"; an amber count
says "you may not have intended this". That choice drives all three treatments
and I am not assuming it.

### B3 — Ordering — ✅ **IMPLEMENTED 2026-08-10** (ahead of A3, no dependencies)

Single-pick changed from `.first` (oldest-created) to `.last` (newest).
**Precedence `calEntry ?? recurring` deliberately UNTOUCHED** — that is B2's
question and changing it here would mask the storage bug.

**Ordering contract verified, not assumed.** `_assignSortKeys`
(`schedule_providers.dart:548`) stamps `nextSortKeySeed(state)` = max + 1 per
insert, so newer items carry HIGHER keys; the subcollection repo reads
`.orderBy('sortKey')` ascending (`subcollection_schedule_repository.dart:55,64`)
and the legacy array preserves append order. **Both backends put the newest
last.** Positional `.last` was chosen over max-by-`sortKey` because fleet data
shows stored schedules carrying `sortKey: 1` — ties are real, and `.last`
degrades correctly where a max-pick would be ambiguous.

**Five sites across FOUR surfaces** — one more than §1 recorded:

| surface | file:line | change |
|---|---|---|
| `_DayHeroCard` (selected-day card) | `my_schedule_page.dart:1190` | `.first` → `.last` |
| `_WeekDayCell` (week strip) | `my_schedule_page.dart:2126,2134,2136` | `.first`/`.firstOrNull` → `.last`/`.lastOrNull` ×3 |
| `_buildTonightCard` (home) | `wled_dashboard_page.dart:1350` | `.first` → `.last` |
| `_CalDayCell` (month grid) | `my_schedule_page.dart:2488` | **no change possible** |

> **`_DayHeroCard` is a FOURTH open-coded resolution** that §1 missed — it
> resolves `recurringItems` independently with its own `.first`. Three surfaces
> was an undercount. **This is the B1 argument, sharpened:** a one-line
> behavioural change required edits in four places and five expressions, and the
> only reason none were missed is that `.first` is greppable. A future change
> that is not greppable will be missed.
>
> **`_CalDayCell` could not be changed at all** — it receives only `calEntry`
> and never sees recurring schedules (defect C). It is unaffected by newest-wins
> because it renders nothing for those days either way.

**Verified:** 8/8 new unit tests (`multi_entry_newest_wins_test.dart`) covering
two-schedule days, third-displaces-second, the old-behaviour regression, tied
`sortKey`s, and weekday-filter order preservation. Full suite **2018 passed / 3
skipped / 1 pre-existing failure**. `flutter analyze` on both changed files: **0
errors, 0 warnings** (16 pre-existing deprecation infos).

**What this does and does not do.** It makes the customer's most recent action
visible — the symptom actually experienced. It does **not** fix multi-entry
display: a day with three schedules still shows one. A3 and B/C remain as
sequenced.

#### Original analysis

`.first` is **oldest-created** (sortKey == insertion order). If only one can
show, **newest is the better pick** — a customer who just added something must
see it, and today they see nothing change, which reads as a failed save.

**But showing all of them is the actual answer**, and `preferNewest` should be a
transitional parameter on `resolveDay`, not a permanent behaviour. Worth noting:
flipping to newest-wins is a **one-line change with no storage dependency** and
could ship with A3 if the `+N` work is delayed.

## C — Month grid renders recurring days empty

`_CalDayCell` receives only `calEntry`. A day covered solely by a recurring
schedule renders **empty** — not "one of several", none.

Scope with B: it consumes the same `resolveDay`. **One consequence to surface
before building it:** most days have *some* recurring coverage, so the month
grid will go from sparsely marked to almost fully marked. That is more correct
and visually much noisier, and it will need dated-vs-recurring visual weight
(e.g. filled dot for dated, hollow for recurring) or the month view stops
communicating anything.

## SEQUENCE — recommended, with justification

**1. A3 alone (+ optionally B3's newest-wins one-liner).**
Stops ongoing data loss for the cost of a warning. No migration, no lease
impact, no storage change. Ships independently and is revertible alone.
*Tyler's prior is right and I would not reorder it.*

**2. B + C together.**
They share `resolveDay`; splitting them means writing the resolution twice.
Display-only, no storage dependency. **Must not precede A3** — otherwise
recurring days show everything while dated days still silently overwrite, which
is a worse inconsistency than the uniform bug.

**3. A1 + A2 last**, and only with the lease-ledger owner, because:
- The dual-format read must ship **at least one release before** any list write,
  or older clients silently drop dated entries (A2).
- Re-keying the lease registry off `dateKey` collides with the unfinished P0-9
  Firestore migration.
- By then B/C already render `resolveDay`'s list — which will simply start
  returning more than one element. **No display rework at step 3.** That is the
  payoff for doing display against a list-shaped API before storage can produce
  one.

**What this sequence deliberately accepts:** between steps 1 and 3, a dated day
still holds only one entry. The user is warned rather than protected. If that is
unacceptable, A1/A2 has to move first and the rollout gets a mandatory
two-release window before anyone sees a fix.

---

## OPEN QUESTIONS

1. Is the month view's total omission of recurring schedules (§3) known and
   intended, or a second report waiting to happen?
2. Has any customer lost a dated entry to an overwrite? **Unknowable from the
   data** — an overwrite leaves no record. Only the autopilot conflict card ever
   surfaced it, and only for the autopilot-over-user direction.
3. Should a dated entry continue to mask recurring schedules once a day can show
   several things?

---

# B1 + C — PARTIAL. Shared resolver built and decoy removed; WIRING NOT DONE.

**Date:** 2026-08-11 · **Shipped:** the shared function, its tests, and the
decoy deletion. **NOT shipped:** the four call-site migrations, and therefore
defect C is NOT yet fixed on screen.

## What shipped

**`lib/features/schedule/day_resolution.dart`** — one pure `resolveDay()`,
no widgets and no Riverpod, because the surfaces have irreconcilable layouts
(full-width card, 1/7-width cell, a few-mm dot) but identical logic. Returns
`DayResolution` with `source`, `datedEntry`, `recurringPrimary`,
`others` and `totalCount`.

It preserves both existing behaviours exactly:

- **Precedence unchanged** — a dated entry masks recurring, as all four
  surfaces already did. Changing it is B2 and would mask the storage bug.
- **Newest-wins (B3)** — the newest recurring item is primary; `others` is
  newest-first.

Masked recurring items are **counted, not discarded** (`totalCount`,
`hasMore`), so B2 can add a `+N` badge without touching resolution again.

**Decoy DELETED** — `schedule_day_row.dart` and `schedule_plan_controller.dart`
are gone. They looked exactly like this component and were referenced only by
each other; anyone told to "fix the day row" found them first and fixed
nothing. Re-confirmed unreferenced across `lib/` and `test/` before removal;
`flutter analyze lib/` is 0 errors / 0 warnings after.

**Tests: 11/11** — precedence, masked-but-counted, newest-wins, third-displaces,
tied `sortKey`, disabled excluded, empty, and a defect-C case asserting a
recurring-only day resolves to `DaySource.recurring` rather than empty.

## What did NOT ship — and the honest consequence

**The four surfaces still open-code their own resolution.** `resolveDay` is
currently unused by any widget:

| surface | file:line | still to do |
|---|---|---|
| `_DayHeroCard` | `my_schedule_page.dart:1190` | replace inline resolve |
| `_WeekDayCell` | `my_schedule_page.dart:2126,2134,2136` | replace 3 expressions |
| `_CalDayCell` | `my_schedule_page.dart:2488` | **needs a new `recurringItems` param AND a caller change** — this is defect C |
| `_buildTonightCard` | `wled_dashboard_page.dart:1350` | replace inline resolve |

> ⚠️ **Defect C is NOT fixed.** A day covered solely by a recurring schedule
> still renders EMPTY in the month view. The resolver can express it
> (`DaySource.recurring`, pinned by a test) but `_CalDayCell` does not yet
> receive recurring items. Fixing it needs the new param and its call site —
> and note that the month grid will get visibly much busier, since most days
> have some recurring coverage. It will want dated-vs-recurring visual weight
> or it stops communicating anything.

**Why it stopped here:** the session ran short of room to migrate four surfaces
across two files and verify no visual regression. A half-migrated set of display
surfaces — some resolving centrally, some inline — is worse than none, because
the next person cannot tell which is authoritative. The resolver landing first
with tests makes the remaining work mechanical.

## Still true, and unchanged by this

**This does NOT make multi-entry days display all their entries.** A day with
three schedules still shows one. That is B2 — a per-surface design question
(chip, stacked rows, dot counts) — and A1 still cannot store two dated entries
per date, blocked behind the `user_service.dart:875` rollout hazard and the
lease-registry re-key.
