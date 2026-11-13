# Build +127 candidate — `feat/127-table-ownership`

Assembled 2026-11-13 from `feat/126-candidate` at `bd29c38` (the build-126
tag's commit, 2.5.10+126): table ownership for every controller timer write,
the kept rows and keep guard in schedule sync, the verified lease zeroing,
drift detection at launch, these docs, then the version bump to 2.5.10+127 as
the final commit. **Not tagged, not built by CI, not deployed. No Firestore
rules, functions or config write (`config/calendar_leases.liveWritesEnabled`
stays true). No merge into main, `feat/124-colour` or `feat/126-candidate`.
No controller, bench unit or production system was contacted to assemble
it.** The tag waits for the owner's go.

## 1. What went in

Five commits on `bd29c38`, in order:

1. `test(schedule)` — the five Step 1 cases, written first and failing on
   `bd29c38` (section 4 says how): Ellie's table under a lease promotion, a
   lease expiry zeroing and the sunrise-off toggle; a painted design whose
   read-back mismatches and one whose read-back is unreadable, with its rows
   on the device; Stegall's "Deep Blue" table under a Game Day entry edit.
2. `fix(schedule)` — (ii) and (iii): lease writers and the sunrise-off
   toggle keep every row they do not own; a lease record goes only after its
   zero-write is confirmed.
3. `fix(schedule)` — (i): schedule sync keeps a refused schedule's device
   rows and never sends a table that drops an enabled schedule's row.
4. `feat(schedule)` — drift detection: the launch read against the enabled
   schedules, the sixth status state.
5. `docs` and the bump (this file, the bench plan, FACTS T-D12 to T-D15).

### The design rule — ownership

A writer changes only the rows it owns and preserves every other row already
on the device, byte for byte (the controller's `start`/`end` date-range fields
included). Lease writers own lease rows. The sunrise-off toggle owns the
system_off row in the sunrise slot. Schedule sync owns schedule rows. A row's
owner is read from its `macro` with exactly the classification the
controller-facts publisher already uses for `base_boundaries`
(`wledPresetRole`: schedule 10–25, lease 26–41, system_off 2, system_on
1/3/4/5) — never from its slot position. A schedule row cannot carry a lease
macro because the bands do not overlap, and `timer_table_ownership_rules_test`
pins both the bands and "position never decides".

### How (i), (ii) and (iii) changed

**(i) schedule sync.** When it cannot produce a row for an enabled schedule
this time, it keeps that schedule's existing device rows (matched by on time,
weekday mask and macro role) instead of omitting them, and if the outgoing
table would still remove an enabled schedule's row the controller holds, it
skips the POST and fails with the Failed status and Retry. Until 126 the rows
were omitted and the POST still went out, because the always-enabled
sunrise-off row kept `shouldSkipClobberingWrite` from seeing an empty table.

**(ii) the lease writers and the toggle.** They read the controller's table in
the same write path, replace or zero only the rows they own, and send every
other row back unchanged; they no longer resolve stored schedules at all. If
the kept rows leave no free slot for a night, nothing is evicted: the night is
skipped, left unarmed, and the reason rides on the lease result (nightly
schedules win over Game Day nights). Until 126 both composed the table from
stored schedules through `presetId ?? presetForAction(label)`, which resolved
every "Pattern: …", Lumina-chat and Autopilot schedule to nothing.

**(iii) the expired-lease sweep.** The registry record is removed only once
the zero-write is confirmed by the verify read; a silent skip (off the home
Wi-Fi, no controller, live writes off, the controller's table unreadable, an
unconfirmed write) leaves the record for the next sweep. Delete (release) and
Game Day retraction follow the same order. The "next sweep retries" comments
now describe what happens.

## 2. Release notes — 2.5.10 build 127 (candidate, not shipped)

**What changed:** Adding a one-night look or a Game Day, letting one expire,
or switching "Turn lights off at sunrise daily" on or off no longer removes
your other schedules from your controller: each of those now changes only its
own entry on the controller and leaves everything else exactly as it was. A
schedule the app could not re-save on one attempt keeps its place on the
controller instead of being dropped, and if the app cannot be sure it would
keep every schedule it says so and changes nothing (Retry). And each time you
open the app at home it checks that every schedule is actually on your
lights; if one is not, My Schedule and Home say "Your schedule isn't on your
lights." and the app sends it again during the day, or you can tap Retry.

**Tester text:** written with the build's ledger row, after the tag.

**Withdrawal text (return to 126), if needed:** Build 127 has been withdrawn.
Open TestFlight → Nex-Gen Lumina → Previous Builds → install the previous
2.5.10 build. Your schedules, teams, designs and favorites stay. Two things go
back to how they were: adding or ending a one-night look or Game Day, or
switching the sunrise-off setting, can again drop a schedule from your
controller (open My Schedule and tap Retry afterwards to put it back), and the
app no longer checks at launch whether your schedules are on your lights. If
you see anything wrong after switching, tell us the date and time. Send
reports to general@nex-genled.com with the date and time.

## 3. The customer-facing strings (exact)

The sixth status state, from `ScheduleSyncCopy.forState` in
`lib/features/schedule/schedule_sync_status.dart`. The row on My Schedule
reads `<first line> <second line> · <when>`; the Home chip reads the first
line only; the action is `Retry` on both; the colour is amber.

| State | First line (row and chip) | Second line (row only) | Retry |
|---|---|---|---|
| drifted | Your schedule isn't on your lights. | Something changed on your controller. It sends again when you open the app at home between 9 am and 3 pm, or tap Retry now. | yes |

The five 126 states are unchanged (`docs/release/build_126_candidate.md`,
section 3). The hours in all three window lines are derived from
`kAutoResyncDayStartHour` (9) and `kAutoResyncDayEndHour` (15) by a test.

The sync result's own sentence when the keep guard refuses a write
(`kScheduleKeepRowsRefused`, shown where a sync button shows the result; the
status row shows the Failed state's lines):

> Your controller still has a schedule the app couldn't rebuild this time, so
> nothing was changed. Tap Retry; if this keeps happening, contact support.

Internal only, never shown: the lease result's reason when a night is skipped
for want of a slot (`LeaseResult.noFreeSlots(reason:)`), of the form "no free
timer slot: the controller holds N rows that are not lease rows and M lease
rows are registered; nothing is evicted".

## 4. The Step 1 tests, failing first

`test/features/schedule/timer_table_ownership_test.dart`, seven tests, run on
`bd29c38` before any fix (log kept in the session scratchpad under
`gates/127-step1/step1_at_bd29c38.txt`). Every one failed for the ownership
reason:

| Case | Failure on bd29c38 |
|---|---|
| (a) Ellie, lease promotion | "the 17:00 ON row (macro 10) must be kept byte-for-byte" — the written table held only the lease row, eight stubs and the sunrise-off |
| (b) Ellie, lease expiry zeroing | the same: the zero-write held stubs and the sunrise-off |
| (c) Ellie, sunrise-off toggle OFF and ON | the same, twice: the toggle wrote stubs and slot 8 |
| (d) painted design, read-back mismatch | "the 19:00 ON row (macro 10) is still on the controller — device table now: [the sunrise-off only]" |
| (d) painted design, read-back unreadable | the same |
| (e) Stegall, Game Day entry edit | "the 17:12 "Deep Blue" ON row must be kept byte-for-byte" — the table held only the updated lease row |

All seven pass on the candidate tip.

## 5. Known, not fixed in this candidate

- **Stale lease rows with no registry record** (Hogan, Goff and Stegall have
  some). Nothing cleans a lease row (macro 26–41) the controller holds that no
  registry record describes; the lease writer replaces the lease rows with the
  registry's, so such a row is dropped by the *next lease write* on that
  controller, and schedule sync merges only the registry's lease rows, so a
  schedule sync drops it too — but neither is a deliberate cleanup, and a
  controller that gets neither write keeps the row. *Design note:* a cleanup
  would have to decide that a lease row with no record is stale rather than a
  row written by another phone of the same account (the per-phone registry,
  next item), which needs the registry in the account, not on the phone.
  Deliberately not built here.
- **The per-phone registry.** The lease registry lives in the phone's local
  storage; two phones on one account each hold their own, and each one's lease
  write replaces the other's lease rows. Unchanged.
- **The read-back blind spot.** `presetSatisfies` compares a slot's segment
  bounds and power, not its effect or colours (126 candidate, section 9).
  Unchanged; the ownership keep works at the timer-row level, not the preset.
- **Preset saves not persisting on 0.15.1 is unexplained.** The home unit's
  presets file has seven bad bytes (FACTS T-F11) and some psaves do not persist
  on it; whether that is the file, the firmware or the write is not known.
  Nothing here touches it.
- **A lone sun row with an ON macro.** A table that reads back with exactly one
  hour-255 row carrying an ON macro, no sunset marker and no placeholder — a
  "Sunrise → …" schedule under the current encoding, or a "Sunset → …" under
  the encoding before +122 — cannot be placed from the wire. The lease writer
  defers (the night is re-promoted by a later sweep) and the toggle reports it
  could not finish, until a schedule sync rewrites the table in the current
  encoding. A lone master-OFF row (the daily sunrise-off, a schedule's "off at
  sunrise") is placed as the sunrise.
- **A schedule the sync itself refuses reads as drifted at every launch**
  (its row is not on the controller and cannot be), so the status says so and
  the bounded re-sync tries again, up to six times a day inside the window.
  True, and noisy; the fix is to make the sync's own refusals visible to drift
  detection, not done here.
- **After the sunrise-off toggle is switched off, a schedule's own "off at
  sunrise" returns at the next schedule sync**, not with the toggle write: the
  toggle writes the placeholder into the slot it owned and does not rebuild
  schedule rows.
- **Live writes off keeps lease records.** With `liveWritesEnabled` false the
  zero-write is a silent skip, so expired records stay (the brief's rule); the
  flag is true in production.
- **Nothing has run on hardware.** The suite proves the app's side with a fake
  controller; the bench plan (section 7) is written and not run.

## 6. Gates

Run on the candidate tip, one at a time, free space on C: checked before each
SDK (stop under 10 GB). Filled in by the integration report; the logs are
under the session scratchpad `gates/127-tip/`.

| SDK | pub get | analyze | TZ=UTC0 suite | golden | docs_guard |
|---|---|---|---|---|---|
| 3.47.9 | | | | | |
| 3.41.2 | | | | | |
| 3.50.0 (information) | | — | | — | — |

## 7. Bench plan

`docs/bench/table_ownership_127_bench_plan.md` — a test account whose only
controller is the spare `.179` (0.15.4): lease promotion over a "Pattern: …"
schedule, expiry zeroing, the sunrise-off toggle and drift detection.
**Written, not run.** The home controller `.150` is excluded by name.

Not built by CI, not tagged, not deployed as of 2026-11-13.
