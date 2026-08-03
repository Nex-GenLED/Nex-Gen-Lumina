# ALL-STUB CLOBBER — trace, bench, verdict

**Date:** 2026-08-03 · **Rig:** 192.168.1.150 (0.15.1, vid 2507300)
**Status:** DIAGNOSTIC. No code changed. Fix scoped in §3, not implemented.

---

## 0. VERDICT FIRST (§4 answered up front — Tyler needs this)

**It clobbers. Confirmed on hardware.** An 8-entry all-stub push **wipes every general timer in
slots 0-7**, including lease timers. Slot 8 (the global sunrise-off) survives.

| Customer | Safe to press Sync today? |
|---|---|
| **Ellie Cochran** | **Yes — but pointless.** No active leases to lose; her controller holds only disabled junk from 2026-07-10. Nothing will arm either. |
| **Tim Kelly** | **Yes — but pointless.** Same shape: no active leases, nothing to lose, nothing gained. |
| **Chris Cipollone** | **⚠️ NO — do not have him sync on his home LAN.** He has **four future calendar entries** (8/04, 8/05 inside the 48h lease window). A sync can wipe live lease timers. |
| Brooke Rozenberg | Yes. Her 7 clock schedules build a real payload, so this path never triggers. |

All four are `bridge_paired` + `remote_access_enabled`. **Off-LAN the write short-circuits to
`deferredOffLan` and nothing is POSTed** — the risk only exists on their home Wi-Fi. That is the
only reason no damage has occurred yet.

---

## 1. TRACE — what an all-solar sync actually POSTs

For an account whose every schedule carries a solar boundary, with the flag off:

```
solar gate (schedule_sync.dart:1066-1077)  → `continue` before armable.add(s)
armable                                    → []
splitByTimerCapacity([])                   → armed: [], overflowed: false
armedSchedules                             → []            ← guard's first conjunct is FALSE
buildCfgPayload([])                        → {'ins': []}
builtIns                                   → []

empty-armed guard (:1198)
  armedSchedules.isNotEmpty && !scheduleIns.any(isRealEnabledTimer)
  = false && …                             → NEVER FIRES
```

Then the branch at `:1154`:

```dart
if (solarEnabled || globalSunriseOff != null) { … 10-entry solar assembly … }
else {
  scheduleIns = builtIns;                                   // []
  ins = padTimersToMax([...builtIns, ...leaseTimers]);      // ← 8 entries
}
```

**All three affected accounts take the `else` branch** — `sunrise_off_enabled` is `undefined`
(Ellie, Tim) or `false` (Chris), so `globalSunriseOff` is null and `solarEnabled` is false. The
push is therefore **8 entries covering slots 0-7 only**.

`leaseTimers` comes from `calendarLeaseActiveTimersProvider` — the app's own device-local ledger,
gated on `config/calendar_leases.liveWritesEnabled` (**true** in Firestore). So:

- **Ellie / Tim / Brooke** — no calendar entries dated ≥ today → no active leases →
  `ins` = **8 disabled stubs**, a pure erase.
- **Chris** — entries on 8/04 and 8/05 fall inside `kLeaseWindow` (48h) → `ins` =
  `[lease…, stubs…]`, which *preserves* his leases **only if his phone's SharedPreferences ledger
  is populated**. A reinstall, cleared cache, or a ledger that hasn't loaded yet reduces his case
  to the pure-erase one.

Nothing downstream stops the POST: `repoCanWriteCfg` only diverts off-LAN, and
`_pushCfgWithVerify` then writes.

---

## 2. BENCH — before and after, in full

Known state armed on .150 (10-entry push: a real clock schedule, a lease in a general slot, and the
global sunrise-off at slot 8):

**BEFORE** — `/json/cfg` readback (WLED compacts, dropping disabled stubs):
```
ins length: 3
  [0] {"en":1,"hour":20,"min":0, "macro":1, "dow":127, start 1/1 end 12/31}   ← real clock schedule
  [1] {"en":1,"hour":19,"min":10,"macro":27,"dow":16,  start 1/1 end 12/31}   ← LEASE (macro 26-41)
  [2] {"en":1,"hour":255,"min":0,"macro":2, "dow":127}                        ← sunrise-off, slot 8
```

Then POSTed **exactly** what `padTimersToMax([])` produces for an all-solar account with no leases —
eight copies of `{"en":0,"hour":0,"min":0,"macro":0,"dow":0}`. HTTP 200.

**AFTER:**
```
ins length: 1
  [0] {"en":1,"hour":255,"min":0,"macro":2,"dow":127}
```

| Row | Result |
|---|---|
| clock schedule 20:00 macro 1 | **WIPED** |
| **lease macro 27 @ 19:10 dow 16** | **WIPED** |
| sunrise-off `hour:255` (slot 8) | **SURVIVED** |

**Two findings:**

1. **Lease timers occupy GENERAL slots 0-7 — they are not in a protected range.** The macro 26-41
   convention is a *numbering* convention for the preset id, not a slot reservation. An all-stub
   push destroys them exactly as it destroys any clock timer. The only thing that saves a lease is
   being re-merged from the app's ledger in the same write.
2. **Slot 8 is out of the blast radius for these accounts**, because the array pushed is 8 long and
   WLED does not clear slots beyond the pushed length (the behavior `_disabledTimerStub`'s comment
   documents). The global sunrise-off is safe here — for a user who *has* it enabled the push is
   10 entries and slot 8 is re-asserted anyway.

Rig restored and verified byte-identical to its pre-test state.

*Incidental:* the rig's lease row had moved from `13:40` to `19:00 dow 64` since the Block E
session, so leases **are** being re-derived rather than left stale — partially answering the open
question in `BLOCK_E_MISSING_ROW.md` §6.

---

## 3. FIX SCOPE (not implemented)

**Shape:** refuse to POST when the payload contains nothing real *and* we refused something to get
there. That matches the empty-armed guard's stated intent — *"Refusing to POST a no-op that would
false-green"* — which currently can't reach this case because it keys on `armedSchedules`, and
everything was dropped before `armable`.

```dart
// Sketch — not implemented.
if (!ins.any(isRealEnabledTimer) && refusedCount > 0) {
  // Enabled schedules existed and were ALL refused. Writing stubs here would
  // erase whatever the controller has and arm nothing. Report, don't write.
}
```

`refusedCount` = schedules dropped by the arm-check loop (solar gate, `dow:0`, dead macro,
sunrise-off conflict). `presetErrors.isNotEmpty` is a usable proxy but weaker — some warnings are
emitted without dropping a schedule.

**Does this break the legitimate "user deleted their last schedule" case? No — and that is exactly
what the second conjunct protects.**

| Case | `ins` has real? | `refusedCount` | Outcome |
|---|---|---|---|
| All-solar, no leases | no | > 0 | **Refuse to POST** — the fix |
| All-solar, active leases | **yes** (leases) | > 0 | POST proceeds — leases must still arm |
| User deleted last schedule | no | **0** | POST proceeds — **clearing is correct** |
| Normal sync | yes | any | POST proceeds |

The distinction is "we had schedules and rejected them all" versus "there are no schedules" — those
are different states that currently produce byte-identical payloads. That collapse is the bug.

**Secondary hardening worth considering separately:** leases sitting in general slots means *any*
shrinking sync can drop one whenever the ledger is cold. The merge is the only protection and it
depends on device-local SharedPreferences — see `project_ai_dated_entry_5th_write_boundary`. Out of
scope here, but it is the same root exposure P0-3.2 was meant to close.

---

## 4. WHAT TO TELL THE THREE CUSTOMERS

- **Ellie and Tim** can safely press Sync — it just won't help. Their lights still won't come on,
  because refuse-whole is working as designed and the solar flag is still off. Better to walk them
  through converting a schedule to a clock time (the editor now allows this in place), which is the
  action that actually fixes their lights.
- **Chris should not sync on his home LAN** until the §3 guard lands. He has live lease automation
  for 8/04-8/07 that a sync can erase. Off-LAN he is safe — the write defers.
- The warning text shipped in `SOLAR_FIX.md` will now tell all of them *why* their schedules aren't
  arming, which is the change that makes a Sync press likely. **That makes this guard urgent, not
  optional.**
