# LEASE EXPOSURE ASSESSMENT

**Date:** 2026-07-30 · **Branch:** `main` @ `c20ed83` (2.5.10+59) · **Diagnostic only — nothing was
changed. The flag was not touched.**

**Method:** read-only Firestore REST reads via `gcloud` ADC (`honeycutt.tylerg@gmail.com`);
read-only HTTP GETs against the bench controller at `192.168.1.150`; static trace of
`lib/features/schedule/`. Raw bench captures saved to
[lease_exposure_bench_cfg_2026-07-30.json](audit/verification_evidence/lease_exposure_bench_cfg_2026-07-30.json)
and [lease_exposure_bench_presets26plus_2026-07-30.json](audit/verification_evidence/lease_exposure_bench_presets26plus_2026-07-30.json)
(delete if you'd rather not keep them).

**Reference dates.** Flag on: **2026-05-19**. `b97f793` (P0-3.1 lease `en` int + preset `ib`):
**2026-07-24 13:23 -0500**. Today: 2026-07-30.

---

## HEADLINE — the assessment inverted twice while I ran it

1. **The historical exposure is far smaller than feared, and it is not dark-firing.** Before
   `b97f793` the lease writer sent `'en': true` — a **JSON bool**, which WLED stores type-strictly as
   `0` = disabled. So a pre-fix lease timer **never fired at all.** Ten weeks of bad leases were
   *silent no-shows*, not dark fires.
2. **But a dark-fire mechanism does exist, it is newly created by the +59 rollout, and it is live
   this week.** A lease record surviving an app upgrade gets its timer **re-armed with `en:1` by the
   new build's schedule sync — without its preset being re-saved.** Old preset + new timer = the
   mixed pair that fires dark. The +59 closed-track upload happened **today**, during an active run
   of dated Game Day entries.

**Recommendation: leave the flag ON.** Turning it off converts a *conditional* dark-fire into a
*certain* no-show for all 14 pending entries across three real accounts, one commercial — and cleans
nothing that leaving it on doesn't also clean. Full justification in §4.

---

## 1. COUNT THE EXPOSURE

Calendar entries are **not a subcollection** — they are a map field `calendar_entries` on
`/users/{uid}` ([user_service.dart:850-871](lib/services/user_service.dart#L850-L871)). Read with a
field mask across the whole `users` collection; **20 documents, no pagination.**

| Metric | Count |
|---|---|
| User documents total | **20** |
| Users with any calendar entries | **7** |
| Calendar entries total | **91** |
| Entries still future-dated (≥ 2026-07-30) | **14**, across **3** users |

### 1.1 A note on "created between" — the field does not exist

`CalendarEntry` has **no `createdAt`** ([calendar_entry.dart:27-52](lib/features/schedule/calendar_entry.dart#L27-L52)),
and the only timestamp is the whole-document `users/{uid}.updated_at`, which moves on any profile
write. **Per-entry creation time is unrecoverable.**

That turns out not to matter, because creation date is the wrong question. A lease is written when
the entry **enters its 48-hour window** ([calendar_entry_lease_manager.dart:815-825](lib/features/schedule/calendar_entry_lease_manager.dart#L815-L825)),
i.e. within ~2 days of the entry's own date. **`dateKey` is therefore a direct proxy for the
lease-write date**, accurate to ±48 h — better than a creation timestamp would have been.

### 1.2 Entries bucketed by when their lease would have been written

| Bucket | Range | Entries | What was written |
|---|---|---|---|
| Pre-flag | < 2026-05-19 | **10** | Nothing — `liveWritesEnabled` was false |
| **Flag-on, pre-fix** | 2026-05-19 → 2026-07-23 | **59** | Broken shape (`en` bool → **timer disabled**; preset no root `on`) |
| Post-fix, past | 2026-07-24 → 2026-07-29 | **8** | Correct shape |
| **Future** | ≥ 2026-07-30 | **14** | **Not yet written — depends on the user's build** |

May 8 · June 24 · July 27 for the 59 in-window entries. **All 59 are past-dated**; whatever they
armed has already had its chance to fire (or, per §1.4, not fire).

### 1.3 Who is exposed

| UID | Account | Entries | Future | SSID set | Relay mode |
|---|---|---|---|---|---|
| `wrQRUUKy…` | Tyler Honeycutt | 29 | **5** | yes | bridge |
| `5oHhaEaf…` | Ellie Cochran | 26 | **5** | yes | bridge |
| `j8eXTfcs…` | Taps On Main (`marc@tapsonmain.com`) | 16 | **4** | yes | bridge |
| `Q8VIQ9lr…` | Brooke Rozenberg | 8 | 0 | no | bridge |
| `NmDukd5r…` | Jim Dyer | 6 | 0 | no | bridge |
| `Pqptfawp…` | Darrin Nicholas | 4 | 0 | no | bridge |
| `YcSGiwes…` | Steve Stegall | 2 | 0 | yes | bridge |

No account uses webhook mode, so **every one of them is on the cfg-incapable bridge transport**.

**All 14 future entries are Game Day autopilot entries, all `Kansas City Royals *` patterns:**

```
2026-07-30  Ellie · Taps On Main                  (TODAY)
2026-07-31  Ellie · Taps On Main · Tyler          (Friday)
2026-08-01  Ellie · Taps On Main · Tyler
2026-08-02  Ellie · Taps On Main · Tyler
2026-08-04  Ellie · Tyler
2026-08-05  Tyler
```

**The exposure is bounded to three accounts and one homestand.** It is not the unbounded fleet
problem it read as before this count.

### 1.4 What the 59 in-window entries actually did — **nothing, silently**

The diff of `b97f793` on the lease writer is two changes:

```
-        'en': true,          →  +        'en': 1,
                                +        'ib': true,     (both on- and off-lease payloads)
```

WLED reads timer `en` **type-strictly as an int**; a JSON bool is stored as `0`
([calendar_entry_lease_manager.dart:1199-1204](lib/features/schedule/calendar_entry_lease_manager.dart#L1199-L1204),
curl-proven in the `en` saga at `727ef0b`). So **every lease timer written between 2026-05-19 and
2026-07-24 landed disabled.** The missing `ib` was real but academic — the timer that would have
loaded the segments-only preset never ran.

Ten weeks of lease writes produced **silent non-firing**, not dark firing. Customer-visible as "the
Christmas/game-day override didn't happen," with no wrong-looking lights. That harm is already spent
and cannot be retroactively repaired.

---

## 2. IS THE SWEEP FLAG-GATED? — **The flag can be turned off safely. Two mechanisms, and the
second is the one that matters**

### 2.1 The sweep itself is NOT gated; only its device write is — and it lies about it

`sweepExpiredLeases` is driven by an ungated `Timer.periodic`
([:1374-1377](lib/features/schedule/calendar_entry_lease_manager.dart#L1374-L1377)) and always runs.
Inside it, the registry record is removed **first**, then the device cleanup is attempted and its
return value **ignored** ([:719-729](lib/features/schedule/calendar_entry_lease_manager.dart#L719-L729)):

```dart
final lease = _activeLeases.remove(key);
if (lease != null) {
  await _writeZeroedSlot(lease.slotIndex);   // ← return value discarded
```

and `_writeZeroedSlot` short-circuits on the flag, **returning `true`**
([:1139-1147](lib/features/schedule/calendar_entry_lease_manager.dart#L1139-L1147)) — reporting
success for a write it did not perform. Taken alone, that is exactly the feared failure: flag off →
registry purged, device timer left armed, no record remains to ever clear it, and per
OFF_LAN_CAPABILITY §2.4.5 the timer recurs **weekly for a year** (no `start`/`end` written; the
firmware defaults to `{mon:1,day:1}`–`{mon:12,day:31}` — confirmed again in today's bench capture).

### 2.2 But the flag also empties the schedule-sync merge — which clobbers the strays clean

`calendarLeaseActiveTimersProvider` is **itself flag-gated** and returns an empty list when off
([:1396-1401](lib/features/schedule/calendar_entry_lease_manager.dart#L1396-L1401)). Schedule sync
reads exactly that provider ([schedule_sync.dart:1107-1115](lib/features/schedule/schedule_sync.dart#L1107-L1115))
and merges it into the payload, then pads to 8 slots with **disabled stubs**
(`{'en':0,'hour':0,'macro':0,'dow':0}` — [schedule_sync.dart:405-414](lib/features/schedule/schedule_sync.dart#L405-L414),
[:303-312](lib/features/schedule/schedule_sync.dart#L303-L312)).

So with the flag off, **the next on-LAN schedule sync writes disabled stubs over every lease slot.**
The P0-3.2 clobber-protection is precisely what the flag suppresses — and here that regression is
the *remedy*. Stranded lease timers get wiped.

### 2.3 Plain answer

**Yes, the flag can be turned off safely — but the cleanup is not automatic.** It requires one
on-LAN schedule sync (a Sync press or any schedule edit while home) after the flip. Between the flip
and that sync, an already-armed lease timer stays armed and can still fire. That is the same
on-LAN-sync precondition every other remedy in this area has; the flag does not make it worse.

What the flag being off does **not** do is repair anything. It stops new lease writes and enables a
clobber; it cannot re-save a preset or reach a controller the app never talks to.

---

## 3. WHAT IS ACTUALLY ON THE BENCH RIGHT NOW

`GET http://192.168.1.150/json/cfg` and `/presets.json`, 2026-07-30. Controller confirmed:
`ver 0.15.1, vid 2507300, "Kōsen", 290 LEDs, rgbw:true`.

### 3.1 Timer table — **one lease timer, and it is healthy**

```
[0] {en:1, hour:19, min:10, macro:27,  dow:16  (Fri), start:{1,1}, end:{12,31}}   ← LEASE
[1] {en:1, hour:4,  min:20, macro:2,   dow:17  (Mon+Fri), start:{1,1}, end:{12,31}}
[2] {en:1, hour:255,min:0,  macro:2,   dow:127 (daily)}                            ← solar marker
```

Entry [2]'s `hour:255` is the firmware's serialized sunrise/sunset marker
([schedule_sync.dart:289-292](lib/features/schedule/schedule_sync.dart#L289-L292)) with `macro:2`
(NGL Off) daily — consistent with the **global sunrise-off**. Its positional slot cannot be
confirmed because WLED returned only 3 of 8 entries; **UNVERIFIED**, and not relevant to leases.

### 3.2 Lease presets 26-41 — five broken, all orphaned

| Preset | Name | Date | Past/Future | root `on` | Timer pointing at it? | Would fire |
|---|---|---|---|---|---|---|
| 26 | `Lease 2026-07-22` | 07-22 | past | **ABSENT** | **no** | — (orphan) |
| 27 | `Lease 2026-07-31` | 07-31 | **FUTURE** | **`true`**, bri 199 | **YES** (slot 0) | **LIT** ✅ |
| 28 | `Lease 2026-07-21` | 07-21 | past | **ABSENT** | **no** | — (orphan) |
| 29 | `Lease 2026-07-24` | 07-24 | past | **ABSENT** | **no** | — (orphan) |
| 30 | `Lease 2026-07-26` | 07-26 | past | **ABSENT** | **no** | — (orphan) |
| 41 | `Lease 2026-07-25` | 07-25 | past | **ABSENT** | **no** | — (orphan) |

System presets are clean — 1/3/4/5 all `root_on=true` (the 2.5.10+59 healer worked), 2 `root_on=false`.

The two shapes side by side, verbatim:

```jsonc
// preset 27 — written AFTER b97f793
{"on": true, "bri": 199, "transition": 0, "mainseg": 0, "seg": [ … col [0,70,135,0] … ]}
//  ^^^^^^^^^^^^^^^^^^^ root master power asserted → loads LIT from a dark strip

// preset 26 — written BEFORE b97f793
{"mainseg": 0, "seg": [{"id":0,"on":false,…},{"id":1,"on":true,…}]}
//  no root "on", no root "bri" → segments only → master stays OFF → would load DARK
```

### 3.3 What the bench proves

- **Zero live dark-fire exposure on the one controller we can observe.** The only armed lease points
  at a healthy preset and will fire **lit tomorrow (Friday) at 19:10** — Tyler's
  `2026-07-31 Kansas City Royals Colors` entry.
- **The sweep works when the app runs on-LAN.** Five expired leases had their *timers* cleared; only
  the *presets* were left behind. That is the designed behaviour (the sweep zeroes the slot; nothing
  deletes presets) and it means the §2.1 stranding scenario did **not** occur here.
- **Residual cost is cosmetic:** five orphaned presets occupying slots 26/28/29/30/41. They cannot
  fire — nothing points at them — and the allocator will reuse those IDs.
- **The predicted broken shape is confirmed empirically**, not just inferred from code.

---

## 4. RECOMMENDATION — **leave the flag ON; fix forward in the next build**

### 4.1 The new risk the count and the bench surfaced

The dark-fire case needs a **mixed pair**: a timer written by fixed code pointing at a preset written
by old code. `_writeLeaseToWled` always writes both together, so a single build can't produce one.
**But the schedule-sync merge can.** `activeLeaseTimers()` rebuilds timer entries from the
SharedPreferences registry with `'en': 1` hardcoded
([:1198-1209](lib/features/schedule/calendar_entry_lease_manager.dart#L1198-L1209),
[:1223-1225](lib/features/schedule/calendar_entry_lease_manager.dart#L1223-L1225)) and **never
re-saves the preset**. The registry survives an app upgrade.

So: *lease created on a pre-fix build (preset broken, timer disabled) → user upgrades to ≥ +53 →
on-LAN schedule sync re-arms that timer with `en:1` → it now fires, into the old segments-only
preset → **dark**.*

**+59 went to the Play Closed track today** (`c20ed83`), against a fleet whose last widely-available
build predates `b97f793`. The upgrade that creates this window is happening now, during the Royals
run in §1.3. Which build Ellie and Taps On Main are actually running is **UNVERIFIED** — there is no
per-user build telemetry.

### 4.2 Why not turn the flag off

- It would guarantee **all 14 pending entries never arm**, for three real accounts including a
  commercial customer (Taps On Main). That is a **certain** regression to avoid a **conditional**
  one.
- It does not repair anything already on a controller (§2.3), and its cleanup path needs the same
  on-LAN sync the on-flag path needs.
- The historical damage it would have prevented (§1.4) was silent non-firing, and it is already
  spent — 59 past entries, nothing pending.

### 4.3 Why not "leave it and do nothing"

The §4.1 window is real and is opening this week. It should not be left unrecorded just because the
bench happens to be clean.

### 4.4 Fix forward — the targeted change (do **not** implement now)

The minimal correct fix is to make the timer and its preset inseparable: **re-save the lease preset
whenever its timer is re-armed**, or have `activeLeaseTimers()` omit any lease the current process
has not itself written a preset for. Either kills the mixed pair at the source. It rides the next
build; it is not launch scope.

Two zero-code things worth doing meanwhile, both diagnostic:

1. **Re-read the bench after any +59 schedule sync** — it is the one controller where the §4.1
   mechanism can be observed directly, and Tyler's registry may still hold pre-fix records.
2. **Ask the three affected users' app versions.** If all three are on a pre-fix build, §4.1 cannot
   trigger until they update, and the window is schedulable rather than live.

### 4.5 One-line verdict

> **Leave `liveWritesEnabled = true`.** The ten-week historical exposure was silent non-firing, not
> dark firing, and is spent. Live exposure is 14 entries across 3 accounts, all Royals game days
> through 2026-08-05. The bench — the only observable controller — is clean and will fire lit. The
> genuine risk is a **mixed old-preset/new-timer pair created by upgrading to +59**, which turning
> the flag off would not fix and would trade for 14 guaranteed no-shows.

---

## Findings

| # | Finding | Severity |
|---|---|---|
| 1 | Pre-`b97f793` leases wrote `en` as a **bool** → stored `0` → **never fired at all**. Ten weeks of exposure was silent non-firing, not dark firing | Downgrades the prior assessment |
| 2 | Exposure is **bounded**: 20 users, 7 with entries, 91 entries, **14 future across 3 accounts**, all one Royals homestand | Bounds a previously unbounded risk |
| 3 | `CalendarEntry` has **no `createdAt`**; `dateKey` is the correct (better) proxy | Method note |
| 4 | The sweep is **not** flag-gated, but `_writeZeroedSlot` returns `true` for a write it skips | P2 — false success, caller ignores it |
| 5 | The flag **also** empties the schedule-sync merge, so flipping it off makes the next on-LAN sync stub-clobber stray lease slots → **turning it off is safe**, though cleanup is not automatic | Answers the mitigation question |
| 6 | Bench: **one** lease timer (macro 27), preset healthy, **fires LIT** 2026-07-31 19:10. Five pre-fix presets are orphaned with no timers | Zero observable live exposure |
| 7 | **`activeLeaseTimers()` re-arms a timer with `en:1` without re-saving its preset** — the upgrade to +59 can create an old-preset/new-timer pair that fires **dark** | **P1 — new, live this week** |
| 8 | No per-user build telemetry; which build the 3 exposed accounts run is unknowable | **UNVERIFIED** |
