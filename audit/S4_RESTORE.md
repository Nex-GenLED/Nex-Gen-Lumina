# S4 — RESTORE, REVISED SCOPE

**Date:** 2026-08-08 · **Branch:** `main` @ `d48072f` (`2.5.10+66`), working tree
**No dedicated nightly restore row was built** — Tyler's call, and the reframe holds.
Built instead: the `endsAt` companion restore (B). A and C are findings; D is the guarantee.
**Not deployed.**

---

## A — THE SLOT MODEL, SETTLED

**`f8ce483` IS MERGED into main** (2026-07-29, "feat(schedule): global daily sunrise-off —
controller-resident WLED timer"). Verified with `git merge-base --is-ancestor f8ce483 main`.

**The shipped model is positional, with `hour:255` as the wire marker — both, not either.**
`schedule_sync.dart` is explicit:

```
:312  kWledSunriseSlot = 8              :313  kWledSunsetSlot = 9
:322  kWledSolarHourMarker = 255
:319  "keys solar off the SLOT INDEX (8/9), not this value, but we write 255 to…"
:1157 "correctly-encoded solar (hour:255 at slot 8/9) is armed"
```

So the index carries the sunrise-vs-sunset semantics and `255` is how the firmware serializes
it.

### The consequence you asked for

> **The sentinel IS out-of-pool. Solar does NOT consume a general slot.** Everyday capacity
> remains **8 general slots (0-7) = 4 on/off windows**, not 3. The budget for leases and
> everything downstream is unchanged.

That is the good version of the answer, and it is why a dedicated restore row *could* have been
argued for. It is not why we are not building one — see the reframe below.

### ~~⚠ But the bench does not match, and that is a live defect~~

> # ⛔ CORRECTION — 2026-08-09. THE SECTION BELOW WAS WRONG.
>
> **The claim:** *"the bench's solar row sits at index 4, where the shipped model says it would
> not fire as solar — either the rig is pre-`f8ce483` and stale, or the JSON is truncated."*
> It was filed as a P1 and as "the highest-value open item."
>
> **It is wrong. There is no defect. The rig is current and the solar row is armed.**
>
> **The actual mechanism: WLED serializes only ENABLED timer entries, and compacts them.**
> `assembleSolarAwareIns` sends **10** — four real rows, disabled stubs at 5-7, solar at 8, a
> stub at 9. The readback returns **5** because every stub is omitted and the survivors close
> up:
>
> ```
> sent:      [g0, g1, g2, g3, stub, stub, stub, stub, SOLAR, stub]    (10)
> read back: [g0, g1, g2, g3, SOLAR]                                   (5)
> ```
>
> The solar row appears at JSON index 4 **precisely because four general rows precede it**.
> **JSON INDEX IS NOT SLOT INDEX.**
>
> **The tell was in the data, in both reads, and I missed it both times: not one `en: 0` row
> ever appeared.** A 4-row schedule under `assembleSolarAwareIns` must produce five disabled
> stubs. None were ever visible. That alone falsifies "the read reflects the write", and it was
> sitting in the output I had already printed twice.
>
> **Corroborating structure, also present and also missed:** entries `[0]`–`[3]` carry
> `start`/`end` date bounds and `[4]` does not — exactly the split between the general rows
> written by `buildCfgPayload` and the solar sentinel written by the separate
> `SunriseOffService` path. The array was telling me which writer produced each row.
>
> **What settled it:** a second read, taken later, differed from the first — leases had rotated
> (`macro 38`/`dow 32` → `macro 29`/`dow 1`) and `[0]`'s macro had changed `1 → 10`. A stale rig
> does not change between reads. It is being actively synced.

### What is now confirmed, explicitly

| | |
|---|---|
| **The positional 8/9 model IS what reaches the device** | ✅ confirmed |
| **The sentinel is out-of-pool; solar does NOT consume a general slot** | ✅ confirmed |
| **Everyday capacity remains 4 windows, not 3** | ✅ **nothing downstream needs revisiting** — the lease budget and every estimate built on it stand |
| **The rig is CURRENT, not stale** | ✅ two reads differ; it is actively synced |
| **The standing BENCH-VERIFY on the global sunrise-off is SATISFIED** | ✅ the solar row is armed and maintained on the rig |
| **No `syncAll` is needed; item 1 is closed without the tablet** | ✅ |

### The standing check this earns

> **When a readback disagrees with what was sent, establish what the device OMITS before
> concluding what it STORED.**

**This is the fifth instance this week of a plausible answer against the wrong thing:**

1. `teamName` vs `team_name` — reported 0 name-matched pairs, would have meant total divergence
2. `displayName` vs `display_name` — would have produced a nameless customer call list
3. `calendar_entries` read as a subcollection — a count against the wrong shape
4. the `^READY` index grep — matched the `commands` index, would have deployed against a
   building `fire_jobs` index
5. **JSON index read as slot index** — this one

Every one returned a *plausible* number. None was checkable by looking harder at the answer;
each needed a check against something the wrong reading could not fake — a second source, a
different collection, the specific field, a later sample.

---

## B — THE `endsAt` COMPANION RESTORE — built

The planner's end job previously sent `{"on": false}`. It now sends a **base restore**.

### B.1 — What "return to base" sends, and how the server knows

**The server cannot reconstruct the base state, and does not try.** The base layer is
`timers.ins` + presets on the controller — device-resident cfg behind `/json/cfg`, LAN-only,
with no off-LAN read. That is the hard part you named, and the answer is to stop trying to
reconstruct it.

**It does not need to, because the schedule layer already maintains the base as PRESETS.** The
bench proves the convention: `macro:1` is the base ON row, `macro:2` the base OFF row. So the
restore is a **preset id**, not a reconstruction:

```json
{"ps": 1}   // base ON
{"ps": 2}   // base OFF
```

`{ps:N}` is exactly the right primitive — an absolute state load, tiny, and **explicitly
permitted by `assertPayloadIsFireSafe`** (`ps` is allowed; `psave` is the forbidden one).

**Choosing between them.** Loading base-ON at 07:00 would light a house that should be dark.
The server does not know the base boundaries — but it has the customer's lat/lon and the same
sunset port S5's daylight filter uses, and the overwhelmingly common base is sunset-on /
sunrise-off. So the choice is made solarly: **dark → `ps:1`, daylight → `ps:2`.** With no
coordinates it defaults to base ON, because a house briefly lit when it should be dark is a
smaller failure than a house dark on an evening its owner expects it lit — and the base's own
next boundary corrects either way.

**Residual, stated not hidden:** a customer whose base is a *clock* schedule (the bench's 20:23,
not sunset) can be up to ~30 minutes out at the edges. That is wrong-by-minutes at a boundary,
not a wrong state.

### B.2 — Idempotency

A1 proved an identical-state preset load is **visually silent** — byte-identical readback, no
flash, three trials. **That property transfers directly here, because the restore sends exactly
what A1 tested: a preset load.** This is the reason the restore is `{ps:N}` rather than a
reconstructed inline state — an inline payload would have needed its own silence proof, and any
drift between the reconstruction and the real base would show as a visible step.

### B.3 — If the `endsAt` job also fails

Honestly: **the event design keeps running until the base layer's next boundary.**

The floor is **the base layer's next scheduled transition** — for a sunset-on/sunrise-off house,
the sunrise OFF. Nothing below that. A Game Day design that starts at 19:00 and whose end job
never lands runs until sunrise: roughly 11 hours of team colours instead of 3.

That is materially better than "runs until a human intervenes", and materially worse than a
guarantee. **It depends entirely on the base layer existing** — which brings us to C, and to why
C is now load-bearing rather than a nicety.

---

## C — BASE COMPLETENESS. The census is bad.

Read from production, 2026-08-08:

```
controller-owning accounts   : 15
WITH a base schedule         :  5
WITHOUT any base schedule    : 10   ← no floor at all
accounts with Game Day enabled: 9
*** Game Day enabled AND no base layer: 5 ***
```

| No base layer | Game Day enabled |
|---|---|
| textim6@yahoo.com · cpaschall10@gmail.com · jjdyer1@hotmail.com · dnicholas0131@gmail.com | 1 each |
| **marc@tapsonmain.com** | **2** |
| dbrosa99 · nex-genadmin · thegruenewalds · ironreserveclub · staff_installer_5502 | 0 |

**Five accounts have Game Day enabled and no base layer.** For them a failed event-end has no
floor at all — the design runs indefinitely.

> **Measurement caveat, and it cuts both ways.** This counts **Firestore schedule intent**, not
> device reality. The device timers are the actual floor, and the server cannot read them
> (`/json/cfg`, LAN-only). The bench has base rows on the controller — so an account can have
> device timers without Firestore schedules, armed by an older path or at install. **The true
> number of floorless accounts is therefore ≤ 10 and unknown**, and it cannot be established
> off-LAN. What is certain is that 10 accounts have nothing in the store `syncAll` pushes from.

### C.2 — What should happen: **prompt, do not refuse**

Refusing is defensible and I considered it. **Prompt is better here**, for a specific reason:
refusing to enable Game Day for 5 existing customers who already have it on would be a
regression they did not ask for, delivered as a blocked button. And the failure this guards is
not certain — it needs an event-end to fail first.

**What the customer sees**, at the moment they enable Game Day or join a sync group with an
empty base:

> **"Set up your everyday schedule first?"**
> Game Day changes your lights for the game, then puts them back the way they were. Without an
> everyday schedule there is nothing to put back — if anything goes wrong while you are away,
> your game lighting could stay on until you change it.
> **[Set up my schedule]  [Enable anyway]**

Non-blocking, honest about the actual failure, and it names the consequence rather than
lecturing. "Enable anyway" is a real option because a customer who genuinely wants
event-only lighting exists — Taps On Main is plausibly one.

### C.3 — No auto-creation

**Agreed, and not done.** Auto-creating a base layer is the same mistake as backfilling
`enabled: true`: nine accounts waking to lights on a schedule they never set. The prompt asks;
it does not act.

---

## D — THE GUARANTEE, PRECISELY

> **"When a Game Day or sync event ends, your lights go back to your everyday schedule. If
> anything in that chain fails, your everyday schedule takes over again at its next scheduled
> time — sunrise or sunset — because that runs on your controller and does not depend on us."**

### Every case where it does NOT hold

| # | Case | What actually happens |
|---|---|---|
| 1 | **No base layer** (10 accounts, ≥5 with Game Day on) | **No floor.** The event design runs until a human intervenes. The guarantee is void, not degraded |
| 2 | **Power cut** | The controller boots **lit**, at `def.on` / half brightness, with **segments collapsed** (`seglc [3,3]→[3]`, R-14). The base layer resumes at its next boundary, but until then the house is in a state neither the base nor the event specified |
| 3 | **Clock unset after a power cut with no internet** | WLED re-attempts NTP **only on boot**. No clock → no timer fires at all, including the base. **The floor itself is gone**, and nothing detects it |
| 4 | **The row was never armed** — customer off-LAN since setup | Arming is a `/json/cfg` write, LAN-only. A customer who has never been home with the app open has whatever the installer armed, or nothing |
| 5 | **The solar row is at the wrong index** (§A) | If the bench is representative, the sunrise-off may not fire at sunrise on some controllers. Unresolved |
| 6 | **Base is clock-based and the event ends near a boundary** | The solar ON/OFF choice can be ~30 min out (§B.1) |
| 7 | **Event ends after the base OFF boundary** | Restore correctly sends `ps:2` (off), but a customer watching a late game sees the lights go out at the event end rather than at sunrise |

**Cases 1 and 3 are the ones that void it entirely.** Both are invisible today: nothing reports
a missing base layer, and nothing reports an unset controller clock. **S6's daily probe could
detect case 3** — `/json/info` carries the controller's time, and comparing it against server
time is the check `clock_health.dart` already does on-LAN. That is a small, high-value addition
and it is not built.

---

## VERIFICATION — partial, and I am naming the gap

| Check | Status |
|---|---|
| Build + full functions suite | ✅ **8 suites, 237 tests** |
| `{ps:N}` passes `assertPayloadIsFireSafe` | ✅ asserted in the S5 suite (`ps` allowed, `psave` refused) |
| Base restore wired into the end job | ✅ replaces `{"on":false}` |
| **Bench: restore survives a full schedule sync** | ❌ **not run** |
| **Bench: restore survives lease arm/sweep** | ❌ **not run** |
| **Bench: failed end-signal → house returns to base** | ✅ **RUN 2026-08-09 — OFF half PASSED, ON half FAILED. See below.** |
| **Bench: firing into an already-base house is silent** | ❌ **not run** (A1 proved the property for preset loads generally, not for this payload on this rig) |

The first two are **moot for the built scope** — there is no device row to survive a sync,
because no restore row was built. They would only apply to the design Tyler declined.

The last two are **genuinely owed** and are the acceptance test. Both need real elapsed time on
the rig: fire a design, withhold the end signal, and watch the base boundary reclaim the house.

### ✅/❌ ACCEPTANCE TEST RUN — 2026-08-09

A Game Day design (`mlb_royals`) was fired at `.150` at 23:49 on 2026-08-08 and the end signal
was **deliberately withheld**. Read back the following morning:

```
on: false   bri: 200   ps: 2
  seg 0 on:false  0-128    fx: 0     (was on, fx:3 — the design)
  seg 1 on:false  128-290  fx: 83
```

**The OFF half of the guarantee is DEMONSTRATED.** `ps:2` is what makes it more than a
coincidence — a bare `on:false` could have been a timeout or a power blip, but the controller
reporting preset 2 as loaded could only have come from the 06:22 base OFF row. Seg 0 going
`fx:3 → fx:0` corroborates it: the base **replaced** the event layer rather than dimming it.

**The ON half was DISPROVED on the same rig.** Loading `{"ps":1}` — the preset the 20:23 base ON
boundary fires — gave master on and **zero segments lit**. Presets 1/4/5 stored `s0:OFF s1:OFF`;
preset 3 stored `s0:OFF s1:on`. The base layer could reclaim the house but could not light it.

Root cause is a separate, fleet-shaped defect: the ON ladder psaves with no `seg` key and
captures ambient segment state. **Full analysis, bench evidence, repair log, fleet-probe options
and the blocked root fix: `audit/BASE_LADDER.md`.** The rig's ladder was repaired 2026-08-09 and
re-verified; the rig is now non-representative and must not be the "healthy" reference.

Two limits on the run, stated plainly: only seg 0 was lit (fired with
`participatingChannels:[0]`), so reclaim is shown for a *partial* house; and the reading was
taken at 08:56, inside the 06:22→20:23 window, so `ps:2` proves *what* darkened the house but
not *when*.

### ✅ ON-DIRECTION ACCEPTANCE — 2026-08-09, 13:33

Run without waiting for the evening boundary: the base ON row was moved to fire two minutes
out rather than moving the clock (tz/NTP are asserted by the healer on connect and would have
reverted mid-test). Pre-state was well-posed — `on:false, ps:2`, both segments dark.

```
=== FIRED at 13:33:00 ===
on: true   bri: 200   ps: 1
   seg 0 on: true   fx: 0
   seg 1 on: true   fx: 83
```

**PASS.** `macro:1` loaded the repaired ladder: master on, bri 200, BOTH channels lit, matched
on `ps === 1` strictly. Table restored and verified identical to the pre-state capture;
`light.gc.col` rode along on both cfg writes and stayed 2.8; rig left dark at `ps:2`.

### ⚠️ FINDING — the 20:23 base ON row does NOT fire `macro:1`

The pre-state capture shows it fires **`macro:10` — "Warm White"**, a preset that was never
damaged (`s0:on s1:on` in the original survey). Two consequences:

1. **The armed evening watcher would have reported PASS while proving nothing** about the
   repair. It was killed rather than left to produce a misleading green. Earlier statements in
   this doc and in session that "the 20:23 row fires macro:1" were wrong.
2. **It narrows fleet exposure.** A base ON boundary whose action is a *pattern/design* fires
   that pattern's preset — written by the path that sets segments explicitly, and healthy. Only
   boundaries whose action is a plain brightness step (on/dim/low/medium → macro 1/3/4/5) load
   the NGL ladder and can fire dark. Exposure is therefore a subset of scheduled accounts, not
   all of them — still unmeasurable remotely (`audit/BASE_LADDER.md` §5b), but smaller than
   assumed.

**§D is now demonstrated in BOTH directions** — reclaim to OFF this morning (`ps:2`, design
replaced, no end signal) and reclaim to ON here (`ps:1`, both channels, bri 200).

**What this does not prove:** the untouched 20:23 row's own arrival. B1/B2 already established
that the firmware evaluates rows on the target minute, so that is not the open question.

---

## FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **`f8ce483` IS merged; solar is positional at slots 8/9 and out-of-pool.** Everyday capacity is 4 windows, not 3 — the downstream budget is unchanged | **Settles A** |
| 2 | ~~**The bench's solar row sits at index 4, not 8** — a stale rig or a truncation artefact, unresolved, and the floor everything rests on.~~ **RETRACTED 2026-08-09 — see the correction banner in §A. There is no defect.** WLED serializes only ENABLED entries and compacts them, so JSON index ≠ slot index. The positional model holds, the rig is current, and the sunrise-off BENCH-VERIFY is **satisfied** | ~~P1~~ → **Closed, no action** |
| 2a | **The tell was present in both reads and missed both times: no `en:0` row ever appeared.** Standing check earned: *when a readback disagrees with what was sent, establish what the device OMITS before concluding what it STORED.* Fifth instance this week of a plausible answer against the wrong thing (§A) | **Method** |
| 2b | **`schedule_sync.dart` documents a THIRD solar encoding** — its format comment says `hour: int 0-23 (or 24 for sunrise, 25 for sunset)`, alongside `kWledSolarHourMarker = 255` and the positional 8/9 model, in the same file. At least one is stale documentation, and **the `hour:24/25` path is the one already known to produce timers that never fire.** Logged, not fixed in this pass | **P2 — open** |
| 3 | **10 of 15 accounts have no base schedule; 5 have Game Day enabled.** For those the guarantee is void, not degraded | **P1** |
| 4 | The census measures Firestore intent, not device reality; the true floorless count is **≤10 and not knowable off-LAN** | Honest limit |
| 5 | **The server cannot reconstruct the base and should not try** — the schedule layer already maintains it as presets, so the restore is `{ps:N}`, which is also exactly what A1 proved silent | Design |
| 6 | **An unset controller clock voids the floor entirely and is undetectable today.** S6's probe could catch it by comparing `/json/info` time against server time — not built | **P1 — cheap, high value** |
| 7 | Prompt rather than refuse on an empty base: refusing would regress 5 existing customers over a failure that is not certain | Decision |
| 8 | ~~The acceptance test — failed end-signal → base reclaim — **has not been run**~~ **RUN 2026-08-09. OFF half PASSED** (`ps:2`, design replaced, no end signal) | ~~Owed~~ → **Demonstrated** |
| 9 | **The base layer could not LIGHT the house.** ON presets 1/4/5 stored every segment off and fired dark; preset 3 lit only the excluded channel. The ON ladder psaves with no `seg` key and captures ambient segment state — and `isNglOnPresetSatisfied` (name + root `on`) cannot detect it, so the self-heal skips the damage forever. Bench rig repaired + verified; **fleet exposure unknown, no telemetry reaches presets**. See `audit/BASE_LADDER.md` | **P0 — gates the shadow run** |

## OPEN

1. ~~**Probe the bench solar index.** Re-run `syncAll`, re-read `timers.ins`.~~
   **CLOSED 2026-08-09** — resolved read-only; no `syncAll` and no tablet needed. See §A.
2. ~~**Run the acceptance test** (finding 8). **This is now the only blocker before the shadow
   run** — §D remains reasoned, not demonstrated.~~
   **CLOSED 2026-08-09** — run on `.150`; the OFF half is demonstrated. §D's reclaim is no
   longer the gate.
2b. **THE SHADOW-RUN GATE IS NOW FINDING 9** — whether any customer's base ON presets are
   damaged the same way. A house in that state never lights at sunset, and **nothing in the
   current telemetry would ever surface it**: the timer fires, the preset loads, WLED returns
   200, the app shows an armed schedule.
   **The one-shot sweep was attempted 2026-08-09 and CANNOT BE RUN** — the bridge resolves its
   endpoint from a closed set of three hardcoded pairs, so `/presets.json` is unreachable
   without firmware, and load-and-observe was refused because it mutates customer lights
   (BASE_LADDER §5b). **0 of 15 accounts swept; none is known healthy.**
   Note this matters less than it looks: **widening `isNglOnPresetSatisfied` to include segment
   state would self-repair every damaged ladder on the next sync**, so a census is needed to
   know the scope, not to fix it. Visibility options if still wanted: `audit/BASE_LADDER.md` §5.
   The **root fix is blocked on a product decision** (BASE_LADDER §6): there is no durable
   per-channel base-layer scope, so asserting all-on would relight deliberate exclusions and
   preserving live state re-creates the bug.
2a. **Reconcile the three solar encodings** in `schedule_sync.dart` (finding 2b).
3. **Add the clock-health check to S6's probe** (finding 6).
4. **Build the empty-base prompt** (C.2) — the only Dart change here, and it stacks with S5's
   scope sentence.
5. `tzOffsetHours` is still hardcoded −5 (shared with S5); it should come from the profile.
