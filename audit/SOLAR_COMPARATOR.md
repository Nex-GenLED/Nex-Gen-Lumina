# SOLAR — comparator, verification, flag

**Date:** 2026-08-05 · **Rig:** 192.168.1.150 (WLED 0.15.1, vid 2507300)
**Outcome: all parts passed. `config/solar_scheduling.enabled = true` is LIVE and readback-confirmed.**
Solar had been off fleetwide since being declared live 2026-07-28 — the flag had never existed in
either Firebase project.

---

## PART 1 — coordinate fudge

### Q2 first (it made the rest cheap): **YES, the controller exposes computed solar times**

Not in `/json/info` or `/json/state` — neither has any solar field. But
**`GET /settings/s.js?p=5`** returns them:

```
Sunrise: 06:21 Sunset: 20:24
```

…and also the raw solar slots (`N8/T8/W8`, `N9/T9/W9` = min/macro/dow for slots 8 and 9). This is a
far tighter loop than watching the strip: **the computation can be verified without firing at all.**
It is how every step below was checked before committing to a fire test.

### Q1 — recompute is NOT immediate; a reboot is required

| Step | Computed |
|---|---|
| baseline, `ln = -94.2527` | sunrise 06:21 / sunset 20:24 |
| write `ln = -84.2527` (+10° E), read immediately | **06:21 / 20:24 — unchanged** |
| after reboot | **05:41 / 19:44** |

The write lands in `cfg` instantly, but WLED does not recompute until boot. **Each fudge cycle costs
one reboot (~20 s)** — cheap, but it must be in the loop or you measure stale values.

### Q4 — longitude-only confirmed, exactly 4 min/degree

+10° east moved both events exactly **40 minutes** earlier (20:24 → 19:44, 06:21 → 05:41). Latitude
and `tz` untouched, so the timezone frame the timer evaluation uses is undisturbed. Confirmed as the
safest lever, as the brief predicted.

### Q3 — the healer will NOT revert a non-zero fudge

`coordHealFor` returns null unless `locationUnset`
([controller_defaults_healer.dart:165](../lib/features/wled/controller_defaults_healer.dart#L165)),
and the call site is guarded by `if (health.locationUnset)` (`:411`). `locationUnset` means the
device is at **0,0** (`_usable(v) => v != null && v != 0`).

**So any fudge with both axes non-zero is safe from the healer** — which longitude-only shifting
guarantees by construction. No need to disable anything or avoid app reconnects.

### Restore

`lt=38.99346 ln=-94.2527 tz=5 offset=0` — **byte-matches the pre-test capture**, and computed solar
is back to 06:21 / 20:24. All three original timer rows restored.

> **⚠ The coordinates in the brief were Ellie's, not Tyler's.** The brief said restore to
> `38.9934731 / -94.2523898`; that is Ellie Cochran's profile. Tyler's are `38.9934607 /
> -94.2527395`, and the rig originally held `38.99346 / -94.2527` (firmware-rounded Tyler). I
> restored the **actual captured original**, not the value in the brief. Writing Ellie's would have
> left a ~1.6-second solar error on Tyler's bench — harmless, but wrong and invisible.

---

## PART 2 — the comparator

**[timer_landing.dart](../lib/features/schedule/timer_landing.dart)** gains `solarTimersLanded`,
plus `extractSolarRows`, `normalizeSolarOffset`, `SolarTimerRow` and `kSolarHourMarker`.

| Requirement | Implementation |
|---|---|
| 1. Ordinal pairing, not index equality | `extractSolarRows` walks the array and takes the **first** `hour==255` as sunrise, the **second** as sunset — never an index |
| 2. `en`, `macro`, `dow` | compared as for general timers |
| 3. `min` as a SIGNED offset | `normalizeSolarOffset` folds `>127` back into negative (−120..+120) |
| 4. Sign round-trip | **bench-verified — see below** |
| 5. `hour == 255` asserted | it is the marker that identifies the row, not noise |

Extra rule, added because the wire makes it ambiguous: a sent solar row with `en == 0` is a
disabled slot WLED drops, exactly like a general stub. If sunrise is disabled and sunset enabled,
the readback's single 255-row reads ordinally as *sunrise* — genuinely undecidable. The comparator
**fails loudly rather than guessing**, and a test pins that.

### Sign round-trip — measured, not assumed

Sent `min:-30` (slot 8) and `min:+45` (slot 9). Readback:

```
[1] {"en":1,"hour":255,"min":-30,"macro":2,"dow":127}
[2] {"en":1,"hour":255,"min":45,"macro":10,"dow":31}
```

**WLED 0.15.1 stores and returns the offset SIGNED — not as an unsigned byte.** `-30` came back as
`-30`, not `226`. So `normalizeSolarOffset` is *defensive* on this firmware rather than load-bearing.
It stays, and is tested both ways, because the app hardcodes offset 0 today — which is exactly the
condition under which a future sign bug would ship unnoticed.

### The ordinal assumption, confirmed on hardware

Sent 10 entries; readback returned **3** — one general timer, then both 255-markers **trailing, in
order** (sunrise macro 2, then sunset macro 10). That is precisely the compaction the ordinal rule
depends on, now observed rather than inferred from a comment.

### Tests — `solar_comparator_test.dart`, 21 cases

The **negative** cases are the point; a comparator that only passes proves nothing. Each of these
must be CAUGHT: wrong macro · wrong dow · wrong offset · **sign error on the offset** ·
sunrise/sunset **swapped** · slot never landed · empty readback · `en` downgraded to 0.

One test documents the blindness being closed: for a corrupted solar row,
`timersInsLanded` returns **true** while `solarTimersLanded` returns **false**.

---

## PART 3 — first-wins contention

The message names the schedule **and the boundary** — `'${s.actionLabel} (${s.timeLabel} ON)'` —
producing:

> Only one sunrise and one sunset schedule are supported per controller —
> **"Warm White (Daily evening lighting) (Sunset ON)"** was not armed.

It goes to `presetErrors`, which **renders as text since +61** (SnackBar + status row + Details
dialog), not as a count. So Ellie sees which of her two schedules lost and why.

`solar_first_wins_test.dart` (5 cases) pins it against her exact live shape: the first arms, the
second is rejected **by name**, the winner is not reported as rejected, sunrise and sunset are
independent slots, and the global sunrise-off supersedes a redundant sunrise OFF **silently**
(identical macro 2 — warning there would be noise).

---

## PART 4 — verification before the flag

| Check | Result |
|---|---|
| Solar row lands at slots 8/9 with correct `en`/`macro`/`dow` | ✅ hardware readback |
| Comparator CATCHES a corrupted row | ✅ 8 negative cases, incl. swap and sign |
| The row **FIRES** at the computed solar time | ✅ **fired 11:27:09 against computed sunset 11:27** — `on` False→True, `ps` −1→1 |
| Offset sign round-trips | ✅ signed, not uint8 |
| Two sunset schedules: one arms, one rejected legibly | ✅ 5 tests |

**The fire is the headline: a slot-9 solar row fired on its own solar computation, four minutes
after being armed, with no wait for real dusk.**

> **A polling bug I made, recorded so it is not repeated.** My first fire-poll broke on
> `*"|1"*` against the string `False|128|-1` — the `1` in `bri=128` matched. It reported a fire that
> had not happened. Same false-positive class as the earlier `on==true` break. **Match `ps` exactly.**

### FLEET READINESS

**Coordinate coverage — 15 accounts hold a controller; 14 have valid coordinates.**

| Account | ctrl | coords | account tz | solar scheds |
|---|---|---|---|---|
| Ellie Cochran | 1 | ✅ | CDT | 1 |
| Tim Kelly | 1 | ✅ | CDT | 1 |
| Chris Cipollone | 1 | ✅ | CDT | 1 |
| Brooke Rozenberg | 1 | ✅ | CDT | 1 |
| Jim Dyer, Taps On Main, The Iron Reserve, Trend Setter | 1 each | ✅ | CDT | — |
| Darian Brosa, Chris Paschall, Demo, Darrin Nicholas, Jeff Gruenewald, Steve Stegall | 1 each | ✅ | America/Chicago | — |
| **`staff_instal`** | 1 | **❌ NONE** | CDT | — |

The nine coordinate-less accounts hold **no controller** (test/staff/orphan records) and are
unaffected.

**1. What a coordinate-less account experiences when the flag flips — a legible refusal, not
silence.** `syncAll` computes `solarEnabled = solarFlagOn && solarCoordsUsable`, and
`solarCoordsUsable` is read from the **controller** via `fetchClockInfo` (non-null, not 0,0). With
the flag on and coordinates missing the message becomes:

> "X" uses sunrise/sunset timing, which **needs your location set on the controller — sunrise/sunset
> can't be computed without it**.

…and that renders since +61. **This is the safety net that makes a global flip defensible**: the
failure mode is an instruction, not the silent no-op we spent the week removing.

**2. The editor gate fires BEFORE save — and is deliberately non-blocking.**
`maybeWarnClockBeforeSave` runs ahead of the write (`if (!clockOk) return;`), is gated on
`creatingSolar`, and offers **Cancel / Save anyway** with a message plus remediation. So a user can
still save a solar schedule against a coordinate-less controller — by choice, having been told — and
then hits the sync-side refusal above. Two legible layers.

**3. Controllers vs accounts — handled, but unverifiable from here.** Account coordinates and
controller coordinates are separate. The healer writes the profile's coordinates to the controller
on connect **when the device reports 0,0**, so the 14 accounts with coordinates self-heal on their
next LAN connect. I cannot reach customer controllers to confirm their current state — only the
bench rig. The `solarCoordsUsable` guard is what makes that acceptable: an unhealed controller
refuses legibly rather than failing silently.

**4. Timezone.** The bench controller is `tz=5` (US Central), correct for the fleet's geography. I
cannot read customer controllers' `tz`. Noted risk: **a wrong tz makes sunset fire at the wrong
time rather than not at all, which is harder to notice than a non-fire** — there is no guard for it,
because a wrong-but-valid tz is indistinguishable from a right one without knowing where the house
is. Worth a follow-up sweep once controllers are reachable.

> **Data-hygiene finding:** account `time_zone` is stored in **two formats** — 9 accounts use
> `"CDT"`, 6 use `"America/Chicago"`. `"CDT"` is not an IANA zone, and `tzHealFor` maps
> `ianaTimezone`. Not blocking (both resolve to US Central today), but it will bite the first time
> a non-Central account appears. Logged, not fixed.

---

## PART 5 — the flag

Created **only after** everything above passed, and **verified by readback** — the lesson from
07-28 being that an unconfirmed flip is indistinguishable from one that never happened:

```
BEFORE: config/solar_scheduling exists = false

AFTER — READBACK VERIFICATION
  exists       : true
  enabled      : true (type boolean)
  modifiedBy   : bench_gate_2026_08_05
  lastModified : 2026-08-05T16:35:42.352Z
  FLAG LIVE AND CONFIRMED: true
  app _extractEnabled would return: true

config/ collection now: calendar_leases, schedules_subcollection, solar_scheduling, sync_fanout
```

`enabled` is asserted to be a real **boolean**, because `_extractEnabled` requires `raw is bool` — a
string `"true"` would have read as **false** and reproduced the original failure exactly.

### The five UI surfaces needed NO code change

They were built flag-driven in +61, not hardcoded, so **they un-gate themselves**:

| Surface | Behaviour now the flag is true |
|---|---|
| Schedule editor | `ButtonSegment(enabled: solarEnabled)` → Solar selectable |
| `_offTrigger` default | the `if (!flag)` override no longer applies → back to `solarEvent` |
| Autopilot baseline | emits `Sunset`/`Sunrise` again |
| AI prompt schema | the "never emit Sunset/Sunrise" constraint is no longer appended |
| Commercial events | `Sunset`/`Sunrise` instead of the clock fallback |
| Neighborhood sync | "Start at sunset" checkbox enabled |

**Rollback is one field**: set `enabled:false` and all six re-gate themselves.

---

## VERIFICATION SUMMARY

| Check | Result |
|---|---|
| `solar_comparator_test.dart` | **21/21** |
| `solar_first_wins_test.dart` | **5/5** |
| Full suite | **1927 passed · 3 skipped · 1 failed** |
| Failing test | `cloud_ai_processor_normalize` — known pre-existing stale P1-8. **No new failures** |
| Arithmetic | 1901 **+ 21 + 5 = 1927** ✅ |
| `flutter analyze` (timer_landing.dart) | **No issues found** |
| Rig restored | coords byte-match original; 3 timer rows restored; computed solar back to 06:21 / 20:24 |

---

## WHAT REMAINS

- **The comparator is not yet WIRED INTO the sync verify path.** `solarTimersLanded` exists and is
  tested, but `_pushCfgWithVerify` still calls `timersInsLanded` alone. Until it is called, a solar
  row still verifies clean in production. **This is the highest-priority follow-up** — the flag is
  on, so solar rows are being written now.
- Customer controllers' coordinate and `tz` state is unverified (unreachable from here); the
  `solarCoordsUsable` guard makes a missing coordinate legible, but a *wrong tz* has no guard.
- `time_zone` format inconsistency (`CDT` vs `America/Chicago`).
- Offsets remain hardcoded to 0 — the encoding and comparator support ±120, but there is no editor
  field (the long-standing OFFSET UX GAP).
- `staff_instal` has a controller and no coordinates; staff account, no action needed.
