# BLOCK E — why the 23:17 schedule never reached the controller

**Date:** 2026-08-02 · **Rig:** 192.168.1.150 (0.15.1, vid 2507300) · **Account:**
`wrQRUUKyXyc0deyuu0ORS6wsovO2` / tyler.honeycutt@nex-genled.com
**Status:** DIAGNOSTIC ONLY — no fixes, no branches, read-only throughout.

---

## 0. Answer in one paragraph

The schedule was created through the Lumina AI window as a **CalendarEntry**, not a
`ScheduleItem`. It is in Firestore right now, at `users/{uid}.calendar_entries['2026-08-01']`,
carrying `onTime: "23:17"` and **no `offTime` key**. It never reached `buildCfgPayload` because
that path builds from `.schedules`, which is an **empty array** for this account. It never reached
the controller by the *lease* path either, because the lease manager's window check computes an
expiry from `offTime` and returns `null` when `offTime` is absent — which
`_isWithinLeaseWindow` collapses into a plain `false`. The entry was saved, shown in the UI, and
silently declared out-of-window. **Nothing anywhere reported a failure.**

---

## 1. FIRESTORE FIRST — which half are we in?

**Neither half as framed.** The row is not absent (so it is not purely a UI/write-side break) and
it is not present as a `ScheduleItem` (so it is not a sync/payload break). It is present *as a
different type entirely*.

```
users/{uid}.schedules                     → array, length 0
users/{uid}/schedules (subcollection)     → 0 documents
users/{uid}.schedulesMigratedAt           → 2026-07-14T23:21:20.140Z
users/{uid}.calendar_entries['2026-08-01'] → {
    "dateKey":"2026-08-01", "onTime":"23:17", "patternName":"Royals",
    "brightness":85, "color":"#003687", "autopilot":false, "type":"user"
}                                            ← NOTE: no "offTime" key
```

Two consequences that reframe the whole Block E result:

1. **This account has zero recurring schedules.** Both the array and the subcollection are empty.
   `buildCfgPayload(armedSchedules)` was therefore correctly given nothing and correctly produced
   nothing. **syncAll did not malfunction.** The observed post-sync table — one lease timer plus
   the sunrise-off — is exactly what a zero-schedule account should produce.
2. **The bench has never once exercised a real recurring schedule on this account.** Every
   schedule-firing test to date (B1, B2, B3-wrap included) armed `timers.ins` by hand via curl.
   That is a valid firmware test and its conclusions stand, but it says nothing about the app's
   schedule pipeline.

---

## 2. WHY F-2a's CONCLUSION WAS WRONG

`FEATURE_STATUS_MATRIX` F-2a ruled the AI path out as a fifth schedule write boundary on the
grounds that it produces `ScheduleItem`s flowing through `buildCfgPayload`, citing
`scheduling_intent.dart:15`.

That citation describes the **recurring weekly/daily** scheduling-intent contract — the
`schedulingIntent` / `schedulingIntents` shape. It is accurate for *that* contract. The error is
one of coverage, not of reading: the Lumina AI window in the Scheduling tab also emits
**dated single-day entries**, and those take a completely different road:

```
AI window (dated entry) → CalendarEntry → user_service.dart:860
                        → users/{uid}.calendar_entries[dateKey]   ← MAP FIELD, not ScheduleItem
                        → calendar_entry_lease_manager (SharedPreferences ledger)
                        → its OWN cfg write, macro 26-41
```

`calendar_entries` has exactly one writer in the codebase
([user_service.dart:860](../lib/services/user_service.dart#L860)) and it never touches
`.schedules`. **This is a fifth write boundary and it bypasses `buildCfgPayload` entirely.**
F-2a should be reopened.

---

## 3. THE ACTUAL DROP POINT

[calendar_entry_lease_manager.dart:836-848](../lib/features/schedule/calendar_entry_lease_manager.dart#L836)

```dart
DateTime? _computeExpiresAt(CalendarEntry entry) {
  final dt = DateTime.tryParse(entry.dateKey);
  if (dt == null) return null;
  final onHm  = _timeStringToWledHourMin(entry.onTime);
  final offHm = _timeStringToWledHourMin(entry.offTime);
  if (onHm == null || offHm == null) return null;   // ← offTime absent ⇒ null
  ...
}

bool _isWithinLeaseWindow(CalendarEntry entry) {
  final expiresAt = _computeExpiresAt(entry);
  final onAt = _computeOnAt(entry);
  if (expiresAt == null || onAt == null) return false;   // ← null ⇒ "not in window"
  ...
}
```

An entry with no `offTime` can never be armed. The refusal is expressed as a **boolean
window miss**, which is indistinguishable from the legitimate "this entry is 3 weeks out" case,
so it is neither surfaced nor logged.

**The asymmetry is the tell.** An unparseable `onTime` gets a *typed* rejection —
`LeaseResult.invalidEntry('onTime unparseable')` at line 546. A missing `offTime` gets silence.
One field is validated; its twin is not.

`calendar_entries` contains a second instance already: `2026-07-06`
(`onTime:"11:25"`, `patternName:"Bright White"`, no `offTime`). Both unarmable entries are
`type:"user"`. Every `game_day` autopilot entry carries both times and is unaffected.

---

## 4. QUESTION 3 — DOES THE AI PATH VALIDATE ANYTHING? (the 8th silent-success)

**Confirmed. This is the eighth instance, and it is customer-facing.**

A user asks the AI window to turn the lights on at 11:17pm and does not specify an off time. The
entry is written to Firestore, appears in the Scheduling tab, and is **structurally incapable of
ever firing**. The user is told it was created. Nothing in the app, the logs, or the controller
ever contradicts that.

Prior seven, for the ledger: F-5, F-8, the off-LAN lease, `_writeZeroedSlot`,
`migrateInstallerControllersToCustomer`, P0-7 (roofline), P0-8 (out-of-range bounds accepted
verbatim). This one differs from P0-8 in an instructive way: P0-8 fools the *verifier*; this one
never reaches a verifier at all, because the entry is discarded before any write is attempted.

Note the near-miss in the record: `scheduling_intent.dart`'s header documents that a previous
`timeLabel` default *"fabricated a solar schedule the user never asked for → an hour:25 timer that
never fires"* — the same class of defect, on the sibling field, already found and fixed
(`b6ca2f1`). The `offTime` path was not audited at the same time.

---

## 5. LEAD HYPOTHESIS (P1-8) — NOT THE CAUSE, AND THE TEST IS STALE

`cloud_ai_processor_normalize_test.dart` fails on:

```
typed coercion: garbage field values in a well-formed Map entry → defaults, no throw
  Expected: 'Sunset'
    Actual: ''
```

The test asserts `timeLabel` defaults to `'Sunset'`. The code returns `''`. **The code is
correct and the test is stale.** [scheduling_intent.dart:17-21](../lib/features/ai/scheduling_intent.dart#L17)
documents `''` (UNRESOLVED) as the deliberate replacement for exactly that `'Sunset'` default,
because the default fabricated solar schedules that never fire. The test was never updated when
`b6ca2f1` landed.

So the ~six dismissals of P1-8 as "unrelated" were right about this incident. They were wrong to
leave it failing: a red test that pins *previously-fixed buggy behavior* trains everyone to ignore
the suite, and it is why this hypothesis was plausible enough to chase tonight. **P1-8 should be
closed as a stale assertion, not fixed.**

---

## 6. QUESTION 4 — macro 26 @ 13:40 dow 64

**Partially resolved; one part is not resolvable from Firestore, by design.**

- `dow 64` = bit 6 = **Sunday** under the app's Mon=bit0 mapping. Sunday is 2026-08-02, inside the
  48h `kLeaseWindow` from the sync. The mapping is corroborated independently: the pre-flight lease
  was macro 27 @ dow 16 = bit 4 = Friday, and preset 27 is named "Lease 2026-07-31" — 2026-07-31
  was a Friday.
- The `2026-08-02` entry does carry both times (`onTime:"19:00"`, `offTime:"22:00"`), so unlike
  8/1 it **is** armable. Consistent with a legitimate rebuild.
- **But `13:40` does not match that entry's `onTime` of `19:00`,** and the gap is not a timezone
  offset (CDT is −5; 19:00 → 14:00, not 13:40). So the armed timer does not correspond to the
  current Firestore state of the entry it appears to represent.

**Why this cannot be settled from Firestore or the bench:** the lease ledger — slot index, preset
id, `wledHour`, `dowMask` — persists to **SharedPreferences on the phone**
(`_kLeaseStorageKey`, `_loadFromPrefs`/`_persist`), not to Firestore. Firestore holds only the
`CalendarEntry`; the *lease* derived from it is device-local. That is also the structural reason
the bench could not settle lease survival earlier: **neither side of the comparison holds the
authoritative record.**

Leading reading (unconfirmed): a **stale lease** — armed from an earlier version of the 8/2 entry
and not re-derived when the entry was edited. Confirming it requires dumping the app's
SharedPreferences lease ledger from the device. Recorded as open.

---

## 7. QUESTION 5 — WAS IT DROPPED FOR WANT OF A SLOT?

**No. The slot-budget path is exonerated.**

[schedule_sync.dart:1124-1125](../lib/features/schedule/schedule_sync.dart#L1124) computes
`splitByTimerCapacity(armable, maxSlots: kMaxWledTimers - leaseCount)`. With `.schedules` empty,
`armable` is empty, so `capacity.overflowed` is false and the 8/8 warning was correctly not
raised. The lease-count arithmetic was never reached in a way that could drop anything.

The concern that the device-side lease I restored by curl would corrupt the accounting was
well-founded in principle but does not apply: `leaseCount` comes from
`calendarLeaseActiveTimersProvider` — the app's own in-memory ledger — not from reading the
controller. My curl restore was invisible to it.

---

## 8. QUESTION 6 — THE hour:255 ROW

**Correct encoding. Not the known-bad path. No finding.**

[sunrise_off_service.dart:22](../lib/features/schedule/sunrise_off_service.dart#L22) documents
`hour:255` as *"the firmware's own serialized marker"*, and lines 257-261 record the parsing rule:
WLED serializes general timers with hour 0-23 and **only** the sunrise/sunset slots serialize
`hour:255`; the first 255-entry is sunrise (slot 8), the second is sunset (slot 9).

`users/{uid}.sunrise_off_enabled = true`, so the row is the **global sunrise-off**, correctly
armed and correctly re-asserted on every sync. The known-bad encoding at
[cfg_payload_builder.dart:100-108](../lib/features/schedule/cfg_payload_builder.dart#L100)
(`hour: 24`/`25`) is a different code path and remains dead — **no live caller reintroduced it.**

This also explains the readback shape that looked odd at the bench: with one general timer and the
sunrise-off, WLED compacts to a 2-entry array with the 255-marker trailing at index 1, rather than
reporting it positionally at index 8.

---

## 9. QUESTION 6 — WHY NOTHING CAUGHT IT, AND WHAT WOULD HAVE

**What the bench harness asserts:** it drives the *real builders* — `buildCfgPayload`,
`buildTimerEntry`, `padTimersToMax`, `assembleSolarAwareIns` — with constructed `ScheduleItem`
inputs, and asserts the resulting `timers.ins` is correct. Every one of those assertions is
sound and none of them fired, because **the builders were never called.** The harness proves
"given a ScheduleItem, the payload is right." The break is upstream of the word *given*.

**The gap in one sentence:** nothing in the suite asserts that creating a schedule through a UI
surface *produces a ScheduleItem at all*.

**The check that would have caught this** — an end-to-end assertion anchored on persisted state,
not on builder output:

> For each schedule-creating surface (ordinary editor, AI window recurring, **AI window dated**,
> autopilot, installer seed): drive the surface's write path with a representative user input,
> then assert that (a) a durable record exists in the store the sync path actually reads, and
> (b) `syncAll` over that store yields a `timers.ins` containing a real enabled timer at the
> requested time.

Applied to the AI dated path, (a) fails immediately: the record lands in `calendar_entries`, which
`syncAll` does not read, and the lease manager silently declines it.

**A cheaper guard with most of the value:** make the lease manager's refusal *typed*. It already
has `LeaseResult.invalidEntry` and already uses it for `onTime`. Routing the missing-`offTime`
case there instead of through a boolean window miss would have surfaced this the moment the entry
was saved — and would convert an entire class of silent drops into reportable ones.

**R-1 cannot return to green** on the current mechanism. Its evidence covers the builder half of
a chain whose first half has now demonstrably failed, and there is no regression guard on the
UI→ScheduleItem boundary for any surface.

---

## 10. OPEN ITEMS

| # | Item | State |
|---|---|---|
| 1 | Missing-`offTime` CalendarEntry silently unarmable — **8th silent-success** | Root cause, confirmed, unfixed |
| 2 | F-2a undercounted schedule write boundaries; AI dated path is a 5th | Confirmed, needs reopening |
| 3 | P1-8 is a stale test asserting pre-`b6ca2f1` behavior | Confirmed — close as stale, do not "fix" |
| 4 | macro 26 @ 13:40 vs entry `onTime` 19:00 — suspected stale lease | Open; needs device SharedPreferences dump |
| 5 | Lease ledger is device-local, so lease survival is unverifiable from Firestore *or* bench | Structural; blocks P0-3.2 verification |
| 6 | No regression guard on UI→ScheduleItem for any surface | Gap named, unbuilt |
| 7 | Account has zero recurring schedules — no app-path schedule has ever been bench-verified | Context |

**Not investigated:** whether the AI window offers an off-time prompt for dated entries, and
whether the ordinary calendar editor can produce the same offTime-less shape. Both are UI
questions this read-only pass could not answer.
