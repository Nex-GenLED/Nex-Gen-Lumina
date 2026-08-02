# SCHEDULING ARCHITECTURE — REVISION 2

**Date:** 2026-07-31 · **Branch:** `main` @ `ebef9fd` (2.5.10+60) · **DESIGN ONLY.** Nothing
implemented, no branch created, no file outside `audit/` touched.

**Supersedes** [SCHEDULING_ARCHITECTURE.md](audit/SCHEDULING_ARCHITECTURE.md) (v1, same date). v1 is
retained — its Part 1 constraint measurements are still the reference, and its device-resident design
is still the correct one for the base layer and for the premium path in §7.

**What changed.** Tyler relaxed the constraint on 2026-07-31: **cloud dependency is acceptable for
event scheduling — firing and updating.** v1 was built around the assumption that everything had to
be device-resident, which forced a scarce-slot materializer as the centrepiece. That centrepiece is
now largely unnecessary.

**Still not launch scope.** iOS submits ~Aug 11-18. Nothing here ships in the RC.

---

## 0. THE SPLIT, AND THE TWO CORRECTIONS TO IT

```
   CLOUD CAN FIRE, BUT CANNOT ARM.

   /json/cfg  ──✗──  no bridge dispatch case          → ARM = LAN only
   /json/state ──✓──  including {ps:N} and full state → FIRE = anywhere
```

The asymmetry is confirmed: the bridge's dispatch is three branches
([main.cpp:815-825](esp32-bridge/src/main.cpp#L815-L825)), and its command poll is
`WHERE status == "pending" LIMIT 5` — **author-agnostic**
([main.cpp:686-697](esp32-bridge/src/main.cpp#L686-L697)), so a Cloud Function writing a command
document is indistinguishable from the app writing one. **This is not speculative: a Cloud Function
already does exactly this today** — the Google Smart Home handler writes commands server-side with
the Admin SDK ([functions/index.js:1416-1424](functions/index.js#L1416-L1424)), as does the Alexa
lambda ([alexa-skill/lambda/utils/firebase.js:129](alexa-skill/lambda/utils/firebase.js#L129)).
Server-side command injection is a **shipping, exercised path**, not a new capability.

Two corrections to the framing before designing on it.

### Correction 1 — "EVENT layer → zero slots" is true for timers, **not** for presets

A `{ps:N}` fire requires preset N to be resident on the controller. Preset IDs are as scarce as timer
slots — 16 for leases (26-41), 16 for schedule designs (10-25)
([calendar_entry_lease_manager.dart:67-69](lib/features/schedule/calendar_entry_lease_manager.dart#L67-L69),
[schedule_sync.dart:267-270](lib/features/schedule/schedule_sync.dart#L267-L270)). If events fire by
preset ID, the allocation problem survives — just softer, because `psave` is `/json/state` and
therefore **relayable off-LAN**
([cloud_relay_repository.dart:601-620](lib/features/wled/cloud_relay_repository.dart#L601-L620)).

**But the fire command does not have to be `{ps:N}`.** The bridge forwards the payload verbatim to
`POST /json/state` ([main.cpp:852-858](esp32-bridge/src/main.cpp#L852-L858)) — the payload is an
opaque string ([remote_command.dart:97](lib/models/remote_command.dart#L97)). A fire job can carry
the **full inline state** (effect, palette, colours, brightness, per-segment) and need no preset at
all.

| Fire mechanism | Preset slot | Payload size | Survives if the command is lost | Where it's required |
|---|---|---|---|---|
| `{ps: N}` | **1 consumed** | tiny | Yes — preset stays resident | **Mandatory for device timer rows** (a timer's `macro` *is* a preset ID) |
| Full inline state | **0** | ~0.5-6 KB | No | **Preferred for cloud fires** |

> **Design rule: cloud-fired events carry inline state and consume zero preset slots. Preset IDs are
> reserved exclusively for things a device timer must point at** — the system presets 1-5 and the
> base layer. That fully drains the preset-allocation problem out of the event path, and retires the
> hash-modulo allocator ([:890-899](lib/features/schedule/calendar_entry_lease_manager.dart#L890-L899))
> along with the lease preset range.

Size caveat: Design Studio per-pixel payloads already exceed a single command and are chunked over
the relay ([cloud_relay_repository.dart:388-403](lib/features/wled/cloud_relay_repository.dart#L388-L403),
with a 337px / 6 KB ceiling and chunk=224). A cloud fire of a per-pixel design would need the same
chunking, multiplying the failure surface. **Recommendation: cloud fires carry effect/palette/colour
state inline; per-pixel custom designs fall back to `{ps:N}` against a pre-staged preset.** That is a
small, bounded exception, not the general case.

### Correction 2 — the fail-safe gets *cheaper*, not more expensive

v1's fallback-row design put one device timer per event. Under the new split there is a strictly
better construction:

> **THE NIGHTLY RESTORE ROW.** One permanent device timer, at a user-chosen hour (default ~23:30),
> every day, `macro` = the base layer's design preset. It is **not** per-event. It is armed once and
> never touched again.

Why this is the best idea in this revision:

- **On an ordinary night it is invisible.** Loading the base design at 23:30 while the base design is
  already running is a no-op — preset loads are absolute state, the same property the sunrise-off
  relies on ([sunrise_off_service.dart:39-43](lib/features/schedule/sunrise_off_service.dart#L39-L43)).
- **On an event night where the cloud worked**, the cloud already restored base at game end; the row
  fires later and changes nothing.
- **On an event night where the cloud died**, it is the guarantee: lights return to normal at 23:30
  with zero cloud, zero app, zero LAN.
- **It needs no date bounding.** It recurs deliberately. So it does **not** depend on the
  `start`/`end` bench experiment.
- **It costs one permanent slot, once, forever** — not one slot per event.

Every cloud-fired event is automatically fail-safe the moment this row exists. **UNVERIFIED:** whether
loading a preset identical to the running state produces any visible artefact (WLED applies a
transition; identical state should be invisible, and the codebase already forces `transition: 0` in
capture/restore paths — [schedule_sync.dart](lib/features/schedule/schedule_sync.dart) `2fbf45e`
lineage). One bench observation settles it.

### The revised layer map

| Layer | Home | Slots | Arms from | Fires from | Fails to |
|---|---|---|---|---|---|
| **BASE** | Device timers | ~2 general + slots 8/9 | **LAN only** | Controller RTC | — (it *is* the floor) |
| **NIGHTLY RESTORE** | Device timer | **1 general, permanent** | LAN only, once | Controller RTC | — |
| **SEASON** | Device timers, date-bounded | 2 general | LAN only | Controller RTC | BASE |
| **EVENT** | Cloud fire jobs | **0** | **Anywhere** | Cloud cron → bridge → `/json/state` | NIGHTLY RESTORE → BASE |

Slot budget after this: 8 general − 2 base − 1 restore = **5 free**, versus v1's 6-minus-events. And
the free slots are now genuinely free, because events no longer compete for them. Seasons are the
only remaining consumer.

**Consequence for the R-14 outage claim:** it survives intact *for the base layer*, which is what it
was always about. §7 states the honest boundary.

---

## 1. DOES THIS COLLAPSE PHASE 1? — Yes. **120-160h → 60-80h.**

v1's Phase 1 was dominated by scarce-resource management. Line by line:

| v1 Phase 1 component | Fate | Why |
|---|---|---|
| Budget-driven arming window (§2e) | **DELETED** | Events consume no slots; there is no budget to divide |
| Deterministic slot allocation replacing hash-modulo | **DELETED** | Nothing to allocate. The lease preset range 26-41 is retired entirely (Correction 1) |
| Eviction ordering + eviction UI | **DELETED** | Nothing is evicted. [eviction_picker_dialog.dart](lib/features/schedule/eviction_picker_dialog.dart) becomes dead code |
| Arm-horizon UI ("armed through Dec 14") | **DELETED** | Every event in the plan is live, to any horizon. This was the concession the new model removes |
| Rolling materialization + 5-min sweep promotion | **DELETED** | Replaced by a cloud cron that needs no client |
| Lease registry migration | **DELETED** | Registry is discarded, not migrated ([:74](lib/features/schedule/calendar_entry_lease_manager.dart#L74)) |
| Layer records in Firestore | **KEPT, simplified** | Still needed; no `armState` machinery per row |
| **Interval compositor (base-vs-event within a night)** | **KEPT — and still genuinely required** | See below |
| Dual-read migration from `ScheduleItem` / `calendar_entries` | **KEPT** | Unchanged |
| Pure-function equivalence testing vs `syncAll` | **KEPT, narrowed** | Only the base/season path must match `syncAll`; events have no `syncAll` equivalent |
| — | **ADDED: fire-job expansion + dispatcher** | Was v1 Phase 3; now the centrepiece |

### The compositor survives, and changes character

It is still required, for a reason that is not obvious: **the device and the cloud both act on the
same strip, on the same night, from two independent clocks.** The compositor is what guarantees they
compose rather than fight (§3). What it no longer does is allocate anything.

It becomes: *given the base/season rules and the events for a date, produce (a) the device rows —
which are stable and rarely change — and (b) an ordered list of cloud fire jobs, including re-assert
jobs where a device boundary falls inside an event window.*

Its hard cases are unchanged from v1 and remain the bulk of the risk: midnight crossings, DST,
an event ending after the base's sunrise boundary, an `AtSolar` end when both solar slots are taken.
All unit-testable without hardware.

### Revised Phase 1

| Component | Est | Confidence |
|---|---|---|
| Layer records + plan model in Firestore | 12h | High |
| Interval compositor (timeline, re-assert jobs, DST/midnight/solar edges) | 24h | Medium |
| Fire-job expansion (plan → dated jobs) | 10h | High |
| Dual-read migration + equivalence tests vs `syncAll` (base path only) | 14h | Medium |
| Tests | 16h | High |
| **Total** | **~76h** | **MEDIUM-HIGH** |

Confidence rises from v1's MEDIUM because the component that carried the most unknowns — allocating
a year of intent into four scarce slots, with explainable eviction — no longer exists.

### The knock-on: the `start`/`end` experiment is **downgraded, not retired**

v1 made the bench experiment a gate on everything. Under the new split:

- **BASE** — full-year by nature. Needs no date bounds.
- **NIGHTLY RESTORE** — recurs deliberately. Needs no date bounds.
- **EVENTS** — cloud-fired, never a device row. Needs no date bounds.
- **SEASONS** — still need them. Still gated on the experiment.
- **Per-event device fallback rows** (the §7 premium path) — still need them. Still gated.

> **The motivating case no longer touches `start`/`end` at all.** The experiment moves off the
> critical path and onto the seasons/premium track. It is still the right 2h to spend before either
> of those, and all six of its UNVERIFIED questions from v1 §1.3 stand unchanged.

---

## 2. FASTEST PATH TO THE MOTIVATING CASE

**"Game Day runs tonight. When the game ends, go to Warm White for the rest of the night, then normal
schedule resumes tomorrow."**

Under the new split this needs: no cfg write, no LAN presence at event time, no slot allocation, no
date bounding, no compositor, and no layer model. It needs a scheduler, a safety row, and the ESPN
detection that already exists.

### The shortest credible sequence

| # | Step | Est | Confidence | Notes |
|---|---|---|---|---|
| **S1** | **`controllerIp` validation** (§8) | **3h** | High | **Gate. Non-negotiable.** Do not write step S3 before this lands |
| **S2** | Command expiry + idempotency: deterministic doc IDs, honour `expiresAt`, server sweeper (§4) | 10h | High | **Gate.** Step S3 creates the stale-fire hazard; this is its remedy |
| **S3** | Fire-job collection + minute-granularity `onSchedule` dispatcher | 16h | Medium | `onSchedule` already used at [functions/index.js:1158](functions/index.js#L1158); command write already precedented at [:1416](functions/index.js#L1416) |
| **S4** | **Nightly restore row** (Correction 2) — one permanent device timer | 6h | High | The fail-safe. Rides the existing `pushCfgWithVerify` path. **LAN-armed once** |
| **S5** | Game Day → fire jobs: start at first pitch; end via server-side ESPN `final` | 20h | Medium | Port of [game_day_autopilot_service.dart:601-653](lib/features/autopilot/game_day_autopilot_service.dart#L601-L653), which already does `final` detection + 30-min countdown + duration fallback |
| **S6** | Fire receipts surfaced in-app + written to controller health (§6) | 8h | High | Falls out of the command doc's existing status/result fields |
| **S7** | Tests + bench (fire timing, restore-row invisibility, ESPN shadow run) | 12h | Medium | |
| | **TOTAL** | **~75h** | **MEDIUM-HIGH** | |

**Comparison to v1's path to the same capability:** Phase 0 (44h) + Phase 1 (120-160h) + Phase 2
(50-70h) + Phase 3 (40-60h) = **254-334h**. This is a **~4× reduction**, and it removes the
dependency on an unrun bench experiment and on OTA firmware entirely.

**What the customer gets at the end of S7, precisely:**

- Game Day design fires at first pitch, from the cloud, with the app closed and the customer anywhere.
- Game ends → ESPN `final` detected server-side → Warm White fires within ~2s (§5).
- Cloud/ESPN/bridge all fail → lights return to base at 23:30 via the nightly restore row, no cloud
  in the path.
- Next morning → base sunrise-off, unchanged, as today.
- Tomorrow → base layer, untouched throughout.

**What it does not get:** seasons, multi-event composition within a night, priority resolution beyond
"one event at a time", or the arm-anywhere story for base-layer changes. Those are Phase 1.

**One dependency worth naming:** S5's quality is gated on ESPN status semantics under delays,
suspensions, and doubleheaders — **UNVERIFIED**, and only settleable by shadow-logging a real season
(v1 §Phase 3 said the same). Ship S5 flag-gated in log-only mode first. Note that a wrong-early
signal is now *less* dangerous than in v1: it fires Warm White early rather than leaving Game Day
colours up, which is the benign direction.

---

## 3. HYBRID PRECEDENCE — device timer vs. cloud event

### The governing insight

Both mechanisms do exactly one thing: **load an absolute state.** Neither toggles, neither reads
prior state, neither can partially apply. Therefore:

> **At run time there is no arbitration — only ordering. The last absolute-state load before an
> instant defines the strip. Precedence is resolved at PLAN time and expressed as a timeline; the
> devices merely replay it.**

This is why the collision is tractable, and it is the same property the codebase already relies on
for the sunrise-off ("it is an ABSOLUTE state load, never a toggle — so if another timer also lands
on sunrise, both resolve to off. Idempotent; no power-back-on race",
[sunrise_off_service.dart:39-43](lib/features/schedule/sunrise_off_service.dart#L39-L43)).

### The four collision cases, specified

**Case A — base OFF fires at sunrise while a cloud event is "running."**

Lights go off. **Correct, desired, and must not be prevented.** The base layer's OFF boundary is the
safety floor; an event does not get to hold the strip past it. A "running" event has no state on the
device to resist with — it was a momentary preset load hours ago.

Specification: the compositor **truncates** any event window at the base OFF boundary and does not
emit fire jobs past it. If a user asks for an event that runs past sunrise, the UI says the event
ends at sunrise. No fire job is scheduled into a period the base layer has already turned off.

**Case B — base ON fires at sunset while an event is already running.** *This is the only genuinely
bad case.*

Event starts 17:00 (cloud fire, Game Day colours). Base ON boundary at sunset 18:30 loads the base
design. **The base clobbers the running event**, silently, and nothing re-asserts it. The customer
sees Game Day colours for 90 minutes, then normal lighting for the rest of the game.

Specification — **the re-assert rule:**

> Whenever a device boundary falls strictly inside an event's window, the compositor emits an
> additional cloud fire job at `boundary + Δ` re-asserting the event state.

`Δ` must exceed the worst-case device-fire-to-cloud-fire ordering uncertainty. Given a measured
cloud fire path of ~1.1-1.9s (§5) and independent clocks, **Δ = 60s** is generous and imperceptible
in this context (the base design flashes for a minute at sunset, then Game Day returns). Cost: one
extra fire job. **Zero slots.**

**Case C — clock skew between WLED's RTC and the cloud's clock.**

The device fires on the controller's NTP-set RTC; the cloud fires on Google's clock. They will not
agree exactly, and the codebase already treats controller clock health as a real risk
([clock_health.dart:254-276](lib/features/wled/clock_health.dart#L254-L276); the whole NTP-heal
design exists because of it). Two events scheduled within seconds of each other have **undefined
order**.

Specification — **the exclusion zone:**

> The compositor never schedules a cloud fire within **±2 minutes** of a device boundary. A fire job
> landing in that zone is snapped outside it, away from the boundary. Case B's re-assert at +60s is
> the deliberate exception — it is *ordered after* by construction and its whole purpose is to land
> on the far side.

**UNVERIFIED:** the actual RTC drift of a WLED controller between NTP syncs. The healer's comment
says WLED only re-attempts NTP on boot
([controller_defaults_healer.dart:13-17](lib/features/wled/controller_defaults_healer.dart#L13-L17)),
which if true means drift accumulates for the entire uptime. A controller up for three months could
be minutes off. **±2 minutes may be far too tight.** Measure it: compare `/json/info`'s reported time
against the phone's on a long-uptime controller. This is cheap and it directly sizes the exclusion
zone.

**Case D — nightly restore row fires after the cloud already restored base.**

No-op. Idempotent by construction (Correction 2). No specification needed beyond confirming the
identical-state load is visually silent.

### Summary table

| Collision | Resolution | Cost |
|---|---|---|
| Base OFF during event | **Base wins.** Compositor truncates the event; no fire jobs past it | 0 |
| Base ON during event | **Event wins.** Re-assert fire job at boundary + 60s | 1 fire job |
| Fire within ±2 min of a device boundary | Snapped outside the zone | 0 |
| Restore row after a cloud restore | No-op | 0 |
| Two cloud fires at the same instant | Plan-time resolution; compositor emits one | 0 |

---

## 4. STALE COMMAND EXECUTION — new failure mode, and it is **live today**

### What I found — worse than the question assumed

**Finding 4.1 — the bridge has no expiry check of any kind.** `executeCommand` reads `type` and
`controllerIp` and fires ([main.cpp:763-845](esp32-bridge/src/main.cpp#L763-L845)). It never reads
`createdAt`, never reads `expiresAt`, never computes an age. There is no code path in the firmware
that can decline a command for being old.

**Finding 4.2 — the Cloud Function's 5-minute expiry check is webhook-only, and every production
account is on bridge mode.** The bridge-mode early return is at
[functions/index.js:338-343](functions/index.js#L338-L343); the age check is at
[:348-360](functions/index.js#L348-L360) — **after** it. Zero production accounts use webhook mode
([LEASE_EXPOSURE.md §1.3](audit/LEASE_EXPOSURE.md)). **The expiry check is dead code for the entire
fleet.**

**Finding 4.3 — an `expiresAt` field already exists, is already written, and is read by nobody.**
The Google Smart Home handler writes `expiresAt: new Date(Date.now() + 60000)`
([functions/index.js:1423](functions/index.js#L1423)); so does the standalone Google Home function
([google-home/functions/index.js:362](google-home/functions/index.js#L362)) and the Alexa lambda
([alexa-skill/lambda/utils/firebase.js:129](alexa-skill/lambda/utils/firebase.js#L129)). A repo-wide
grep for `expiresAt` finds **no reader anywhere in the command path** — not in the bridge, not in
`executeWledCommand`, not in `CloudRelayRepository`. **The TTL convention was designed and never
enforced.** Someone already saw this problem and the enforcement half was never built.

**Finding 4.4 — commands are retained for 7 days.** `COMMANDS_RETENTION_DAYS = 7`
([functions/index.js:1000](functions/index.js#L1000)), swept daily at 04:00 UTC
([:1158](functions/index.js#L1158)). So a `pending` command survives up to a week and remains
eligible for pickup that entire time.

**Finding 4.5 — a backlog drains in unspecified order.** The bridge's query has **no `orderBy`**
([main.cpp:692-698](esp32-bridge/src/main.cpp#L692-L698)) and command IDs come from Firestore's
`.add()` auto-ID ([cloud_relay_repository.dart](lib/features/wled/cloud_relay_repository.dart)),
which is not chronologically sortable. **UNVERIFIED** whether `runQuery` without `orderBy` returns
`__name__` order or something else — but in no case may it be assumed chronological. Consequence: a
backlog containing an ON and an OFF can drain **in reverse**, leaving the lights in the opposite of
the intended final state.

> **Composite live behaviour today:** a bridge offline for six hours reconnects, polls, and fires
> every accumulated pending command — up to 5 per second-long poll, in arbitrary order, with no age
> check at any layer. This is not hypothetical and not new to this design. It does not bite hard
> today only because commands are user-initiated and the user is present to correct the result. **A
> server-side scheduler turns it into an unattended hazard.**

### The specification

**Four layers, in order of strength. The first two need no firmware.**

**Layer 1 — write at fire time, not at plan time.** The dispatcher writes the command document
*when the event is due*, not when it is planned. The document exists for ~90 seconds, not for weeks.
This is the strongest lever and it is free — it is simply what a minute-granularity cron does
naturally. A bridge offline at fire time never sees the command at all.

**Layer 2 — `expiresAt` at write, enforced server-side.**

```
  expiresAt = fireAt + graceWindow      // default 90s
```

A sweeper — either its own 1-minute `onSchedule`, or folded into the dispatcher's own tick —
transitions `status: "pending" && expiresAt < now` → `status: "expired"`. The bridge's query filters
on `status == "pending"`, so an expired command becomes invisible to it **without any firmware
change**. This is the enforcement half that Finding 4.3 shows was always intended.

Residual exposure, stated honestly: the sweeper runs at best every 60s while the bridge polls every
1s. **A bridge that reconnects inside that window still fires a late command.** Bounded at ~60s +
grace. For a lighting command that is the right command slightly late — acceptable. It is *not*
acceptable for anything with side effects, so: **fire jobs only. Never route a state-mutating
operation (psave, config, pairing) through the scheduled path.**

**Layer 3 — bridge-side check (requires firmware + OTA, Phase 4 bundle).** Read `expiresAt` in
`executeCommand`; if `< now`, `updateCommandStatus(id, "expired")` and skip. ~1h of firmware work
riding an OTA campaign that does not yet exist
([OFF_LAN_CAPABILITY.md §5.3](audit/OFF_LAN_CAPABILITY.md)). Closes the 60s window completely.

**Layer 4 — drain-and-discard on reconnect (firmware).** On a WiFi reconnect after >N minutes
offline, mark all pending commands expired without executing. Belt and braces; same OTA bundle.

**Also required, and independent of expiry — deterministic ordering.** Add `orderBy: createdAt` to
the bridge query (firmware) **or**, without firmware, guarantee at most one in-flight fire job per
controller by having the dispatcher refuse to write a new fire job while a prior one for the same
controller is still `pending`. The second option is server-side and should be done regardless,
because it also bounds queue pressure (§5).

**What the bridge does with an expired command:** with Layer 2 alone, it never sees it — the status
is no longer `pending`. With Layer 3, it marks it `expired` and skips. Either way the terminal state
is a distinct `expired`, **not** `failed` — the distinction matters for §6's telemetry, because an
expired command means *the bridge was unreachable*, while a failed one means *the controller was*.

---

## 5. RELIABILITY OF THE CLOUD FIRE PATH — measured

### The real distribution

The "~5-10s round trip" in the routing doc is an **app-initiated** figure and includes app-side hops
that a cloud-initiated fire does not have. Measured per-hop budget from
[BRIDGE_LATENCY_AUDIT_2026-05.md](docs/audits/BRIDGE_LATENCY_AUDIT_2026-05.md):

| Hop | Measured | In a cloud-fired event? |
|---|---|---|
| App writes doc to Firestore | 300-800 ms | ❌ replaced by the function's own write (Admin SDK, same region as Firestore — **UNVERIFIED**, likely faster) |
| Bridge poll wait (avg ½ × 1000 ms) | 500 ms | ✅ |
| Bridge `:runQuery` round-trip | 300-600 ms | ✅ |
| Bridge PATCH `status=executing` | 200-500 ms | ✅ |
| Bridge HTTP to WLED on LAN | 100-300 ms | ✅ ← **the lights change here** |
| Bridge PATCH `status=completed` | 200-500 ms | ✅ (receipt only) |
| App `_waitForCompletion` notices | 250 ms avg | ❌ no app in the loop |

```
  Cloud-fired, time to VISIBLE LIGHT CHANGE:   ~1.1 – 1.9 s
  Cloud-fired, time to CONFIRMED RECEIPT:      ~1.3 – 2.4 s
```

**A cloud-fired event is faster than an app-driven remote command**, because the two slowest hops are
the app's. That is a genuinely favourable and slightly counter-intuitive result — worth stating to
Tyler because it changes the felt quality of the feature.

**The tail is real and much worse.** The app's command timeout is 45s, and the comment records why:
*"under queue pressure (poller backpressure + serial bridge processing) individual setState commands
have been measured at 30-32s"*
([cloud_relay_repository.dart:44-52](lib/features/wled/cloud_relay_repository.dart#L44-L52)). The
mechanism is `MAX_COMMANDS_PER_POLL = 5` ([config.h.example:67](esp32-bridge/src/config.h.example#L67))
processed **serially**, each costing 2-3 Firestore REST round-trips. A backlog drains at roughly 5
commands per 5-10 s.

> **Implication for the design: a scheduled fire must never compete with user traffic.** If a customer
> is dragging a brightness slider at 19:10, the Game Day fire queues behind it. Mitigation — the
> dispatcher's one-in-flight-per-controller rule from §4 bounds *its own* contribution, but cannot
> bound the user's. **Accept a P95 in the tens of seconds when the user is actively using the app at
> the fire instant, and do not design any behaviour that depends on sub-5s fire timing.** For an
> event boundary, tens of seconds is invisible.

**UNVERIFIED and worth measuring before S5 ships:** the *cloud-write* hop's latency (Admin SDK
write from us-central1 to Firestore, vs. the app's 300-800 ms from a phone) and the end-to-end P50/P95
of a genuine cloud-fired command. A one-week shadow run of the dispatcher writing `ping` commands
(which the bridge acknowledges locally with no WLED request,
[main.cpp:788-794](esp32-bridge/src/main.cpp#L788-L794)) measures the whole path at zero customer
risk. **Do this during S3.**

### Failure modes

| Failure | Detection | Behaviour | Terminal status |
|---|---|---|---|
| **Bridge offline at fire time** | `expiresAt` passes with `status == "pending"` | Nothing fires. Nightly restore row covers the night | `expired` |
| **Bridge reconnects late** | — | Layer 1+2 (§4) prevent the fire; ~60s residual window | `expired` |
| **Command write fails** (Firestore error, function crash) | Dispatcher's own error handling | Retry with the **same deterministic ID** → duplicate-safe | — |
| **Function times out mid-fan-out** | Partial writes | Next tick re-attempts; deterministic IDs make it idempotent | — |
| **Bridge picks up, controller unreachable** | Bridge gets non-200 from WLED | `"ERROR: HTTP <code>"` recorded ([main.cpp:917-925](esp32-bridge/src/main.cpp#L917-L925)) | `failed` + error string |
| **Controller accepts but ignores** (bad payload) | `result` field carries WLED's response | Detectable by comparing `result` against intent | `completed` — **but wrong**. Only §6 catches it |
| **ESPN wrong-early `final`** | Two-consecutive-polls + minimum-duration guards | Fires Warm White early — the benign direction | `completed` |

### Can a retry be distinguished from a duplicate fire? — **Today, NO. That must change.**

The app writes commands with `.add()`
([cloud_relay_repository.dart](lib/features/wled/cloud_relay_repository.dart) `_commandsRef.add(...)`),
which mints a random ID. Two invocations of a retried Cloud Function would create **two documents**,
and the bridge would fire **twice**. For a lighting command a double fire of the same absolute state
is harmless — but for a *sequence* (fire Game Day, then fire Warm White) an out-of-order duplicate is
not, and §4.5 shows ordering is unspecified.

**Specification:**

> Fire jobs are written with a **deterministic document ID**: `fire_<eventId>_<fireAtEpochSeconds>`,
> using `.doc(id).create()` — which **fails if the document already exists** — rather than `.add()`.

That makes the write itself the idempotency barrier. A retried function invocation gets a
`already-exists` error, which it treats as success. A duplicate fire becomes structurally impossible,
and the status field then unambiguously answers "did this specific fire happen?" — which is precisely
what §6 needs.

Note this is a **new** convention for the fire path only. Existing app-written commands keep `.add()`;
changing them is out of scope and would need its own analysis.

---

## 6. FIRE-LEVEL TELEMETRY — v1 was wrong here, and this is the biggest unlock

v1 stated: *"no per-fire telemetry. The controller executes autonomously and has no channel to report
a fire; adding one would require firmware."* **That is correct for device timers and false for cloud
fires.** Correcting it:

### What a cloud fire already reports, for free

The bridge writes the command document's status at three points
([main.cpp:938-960](esp32-bridge/src/main.cpp#L938-L960) and callers):

| Signal | Written by | What it proves |
|---|---|---|
| `status: "pending"` + `createdAt` | Dispatcher | The fire was **dispatched** |
| `status: "executing"` | Bridge, before the WLED call | The **bridge is alive and picked it up** — and, with the timestamp delta, exactly how long it took |
| `status: "completed"` + **`result`** | Bridge, after a 200 | The **controller accepted it** — and `result` carries WLED's own response body |
| `status: "failed"` + `error` | Bridge, on non-200 | The **controller refused or was unreachable**, with the HTTP code |
| `status: "expired"` (§4) | Sweeper | The **bridge was unreachable** at fire time |

**The `result` field is the important one.** For a `/json/state` POST, WLED echoes state. That means a
cloud fire produces a **readback-verified receipt of the actual device state after the fire** — which
is *stronger* than anything the device-timer path can ever produce, and stronger than what
`pushCfgWithVerify` gets for cfg writes (it has to poll separately through a stall).

### What this gives, concretely

1. **Per-event fire confirmation with latency**, per customer, per controller, historically.
2. **A failure taxonomy that separates the three layers** — no pickup (bridge down) / pickup but HTTP
   error (controller down or wrong IP) / completed but `result` disagrees with intent (controller
   ignored the payload). Today all three are indistinguishable and invisible.
3. **A controller-reachability probe that does not require the app to be running.** This is the part
   that matters most. [OFF_LAN_CAPABILITY.md §3.3](audit/OFF_LAN_CAPABILITY.md) states flatly:
   *"There is no controller-health signal in the fleet at all... A bridge can be perfectly green while
   the controller behind it has unhealed presets, a dead NTP host, and stale timers."* A scheduled
   `getState` command — one per controller per day, at a quiet hour — is a full end-to-end probe:
   cloud → bridge → controller → response body, all recorded. **That closes the fleet-blindness gap
   with zero firmware and roughly 4h of work.**
4. **A per-account build/version signal**, because the `getState`/`getInfo` result carries the WLED
   version and vid. Yesterday's lease assessment had to conclude *"which build the three exposed
   accounts run is UNVERIFIED — there is no per-user build telemetry."* This answers it.

### How it feeds Phase 5

v1's Phase 5 proposed `/users/{uid}/controller_health/{controllerId}`, written by the app after every
reconcile — which inherits the app's reach problem (a bridge customer who is never home never writes
it). The cloud fire path fixes that:

| v1 Phase 5 field | v1 source | **v2 source** |
|---|---|---|
| `lastReconciledAt` / outcome | App, on-LAN only | unchanged (cfg is still LAN-only) |
| `wledVersion`, `wledVid` | App, on-LAN only | **Daily probe `result`** — no app, no LAN |
| `clockHealth` | App, on-LAN only | **Probe `result`** vs. server time — no app, no LAN |
| `timerTableDigest`, `presetDigests` | App, on-LAN only | unchanged (needs `/json/cfg`, LAN-only) |
| — | — | **NEW: `lastFireAt`, `lastFireOutcome`, `fireSuccessRate7d`, `medianFireLatencyMs`, `expiredFireCount7d`** |

So Phase 5 splits cleanly into a **cloud-written half** (reachability, version, clock, fire outcomes —
covers the whole fleet, always) and an **app-written half** (cfg digests — covers customers who come
home). The cloud half is the one that makes silent failure detectable, and it is now cheaper and more
complete than v1 assumed. **Revised Phase 5: ~24h for the cloud half, ~20h for the app half.**

**Pull the cloud half forward into the §2 sequence** — S6 already includes most of it, and every
subsequent phase is unverifiable in the field without it.

---

## 7. AVAILABILITY EXPOSURE — stated honestly

### What Nex-Gen now owns

Before this design, a customer's lighting had **no** runtime dependency on Nex-Gen. After it, **every
special event does.** That is a real transfer of risk and it should be recorded as a deliberate
decision, not discovered during an outage.

### Blast radius of a Functions outage during holiday season

**Total, for events.** A regional Cloud Functions or Firestore outage in us-central1 stops **every
customer's every event, simultaneously, for the duration.** Christmas Eve at 5pm, with a multi-hour
outage: nobody's holiday show starts. There is no per-customer degradation curve and no partial
failure — it is all of them, at once, on the highest-visibility night of the year.

Contributing single points of failure, all shared:
- Cloud Functions (dispatcher) — regional
- Firestore (command transport) — regional
- The bridges' **shared Firebase Auth identity** — `FIREBASE_AUTH_EMAIL`/`_PASSWORD` are compile-time
  constants ([config.h.example:30-31](esp32-bridge/src/config.h.example#L30-L31)). A credential
  problem on that one account takes the **entire fleet** off the command path at once, and with no
  OTA there is no remote remedy
- ESPN (for sports events only)

**I am deliberately not quoting an SLA figure** — I would be reciting it from memory and this document
does not do that. The design assumption should simply be that a multi-hour regional outage is a
realistic annual occurrence, and that a fleet-wide auth failure is a plausible one.

### The degraded mode

**What keeps working with the cloud entirely gone:**

- **Base layer** — device timers, controller RTC, flash-resident. Lights come on at sunset and off at
  sunrise, in the base design. Zero cloud, zero app, zero LAN
  ([OFF_LAN_CAPABILITY.md §4.1](audit/OFF_LAN_CAPABILITY.md) — the fire path has no cloud or app
  dependency).
- **Seasons** — same, if armed.
- **Nightly restore row** — same. Any half-applied event night still lands on base at 23:30.
- **On-LAN control** — works during an internet outage; the app builds a direct-HTTP `WledService`
  ([wled_providers.dart:209-213](lib/features/wled/wled_providers.dart#L209-L213)).

**What stops:** every event. Full stop.

### Does the base layer alone leave a customer in a defensible state? — **Yes, but only if it is non-empty, and that is not currently guaranteed**

*"Your Christmas lights ran your normal warm-white scene instead of the holiday show"* is a bad night.
*"Your Christmas lights didn't come on"* is a support call and a refund conversation. The difference
is entirely whether the base layer is populated.

**The failure case is real and specific:** a customer — most plausibly a commercial account like Taps
On Main — who uses the system *entirely* through events, with no everyday schedule. Their base layer
is empty. Their degraded mode is **dark**.

**Therefore, promote v1's model invariant to an availability control:**

> **BASE MUST BE NON-EMPTY AND COMPLETE.** The system refuses to save a plan whose base layer does not
> specify both an ON and an OFF boundary. It is not a default the user can clear; it is a
> precondition. If a customer genuinely wants "nothing unless there's an event," their base is an
> explicit low-brightness warm white, not nothing.

v1 stated base completeness as a correctness requirement (§2a). Under the new split it is the **only**
thing standing between a Functions outage and a dark house, and it should be enforced in the model,
in the UI, and in a migration backfill.

### The escape hatch — and where v1's device-resident work earns its keep

For a small number of **known-critical dates** (Christmas, a commercial customer's grand opening, a
wedding), cloud dependency is the wrong trade at any latency benefit. For those, the right answer is
v1's design: **materialize the event to device timers**, date-bounded, armed while the customer is
on-LAN in the days before.

That is a genuinely useful two-tier product distinction:

| Tier | Mechanism | Slots | Arms from | Survives a cloud outage |
|---|---|---|---|---|
| **Ordinary events** (unlimited, year-out) | Cloud fire jobs | 0 | Anywhere | ❌ falls back to base |
| **Pinned events** (a handful per year) | Device timers, date-bounded | 2 | LAN only | ✅ |

**Pinning is what the `start`/`end` bench experiment gates** (§1). It is not on the motivating case's
critical path, but it is the correct home for that work, and it turns v1's device-resident design from
"superseded" into "the premium tier." Estimate ~24h on top of Phase 1, gated on the experiment.

### Honest summary for the availability question

> Everyday lighting has no dependency on Nex-Gen and never will. Events do, and during a cloud outage
> every customer's events stop at once — they fall back to their everyday lighting rather than going
> dark, provided the base layer is populated, which the system must enforce rather than assume. A
> small number of critical dates can be pinned to the controller and are immune.

---

## 8. SECURITY PREREQUISITE — `controllerIp` validation is a **gate**

### The hole

The bridge takes the target IP straight from the command document
([main.cpp:778-779](esp32-bridge/src/main.cpp#L778-L779)) and falls back to the paired IP only when
it is empty ([:795-800](esp32-bridge/src/main.cpp#L795-L800)). Anyone who can write to
`/users/{uid}/commands` — owner-only per
[firestore.rules:496-508](firestore.rules#L496-L508), so: a compromised customer account — can make
the bridge POST arbitrary JSON to **any host on the customer's LAN**.

[OFF_LAN_CAPABILITY.md §5.1](audit/OFF_LAN_CAPABILITY.md) scoped this at ~3h as a prerequisite for
cfg-over-bridge. **This design makes it a prerequisite for something much nearer.** Adding a
server-side, unattended writer to that collection means the collection is now written by a system
process on a schedule; validation stops being a hardening item and becomes structural.

### The scope (~3h, and part of it is free)

**(a) The server-side writer omits `controllerIp` entirely. — 0h, and it is strictly the best option.**

The bridge already falls back to its own paired IP when the field is empty. A fire job that does not
name a target cannot be redirected. **The scheduler should place zero trust in the document it
writes.** Note the existing Google Smart Home writer already omits `controllerIp`
([functions/index.js:1416-1424](functions/index.js#L1416-L1424)) — there is precedent, and it is
correct.

**(b) Tighten the create rule for app-written commands. — ~2h**

`allow create: if isOwner(userId)` becomes additionally conditional on the declared `controllerIp`
matching a controller registered under that user
(`/users/{uid}/controllers/{controllerId}`). Firestore rules support the cross-document `get()` this
needs. Cost is one rules read per command write.

**(c) Record what this does and does not cover. — ~1h**

- **The Admin SDK bypasses security rules entirely.** Rule (b) does not constrain the dispatcher, the
  Google Smart Home handler, or the Alexa lambda. Their validation must be in code, which is what (a)
  achieves by construction.
- Rule (b) does not fix the **unauthenticated LAN endpoints** `/api/bridge/pair` and `/api/reset`
  ([main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372)), nor the **shared bridge Auth identity**
  ([config.h.example:30-31](esp32-bridge/src/config.h.example#L30-L31)). Both are pre-existing, both
  are inherited by this design, and neither is fixable without firmware + OTA. **Record them as
  accepted risk with a named owner, do not silently inherit them.**

**Ceremony note.** Per the standing rule for rule-tightening in this repo: before (b) lands, enumerate
**every** writer to `/users/{uid}/commands` across `lib/` **and** `functions/` **and** `alexa-skill/`
**and** `google-home/`. This document found four writers; a fifth would break silently, and a
BREAKS-list assembled from `lib/` alone has been wrong here before.

> **Gate condition: step S1 lands before step S3 is written.** Not "in the same release" — before.

---

## 9. POSITIONING — the two-tier story is stronger, with one correction

### Confirming Tyler's read

> *"Everyday lighting runs on your controller and never depends on us; special events get cloud
> intelligence."*

**Confirmed. It is stronger than either pure model**, for three reasons:

1. **It converts an apparent weakness into the differentiator.** A pure cloud model has no answer to
   "what if your servers go down." A pure device model has no answer to "why can't I schedule more
   than four things." The split answers both, and each half covers the other's exposed flank.
2. **It inverts the timer-count comparison.** v1 said *"do not put a number on the spec sheet"*
   because our 8 slots lose badly to Gemstone's 64. Under the split, events are unbounded — the
   comparison becomes **"unlimited events" vs "64 timers"**, and we win the line. The 8-slot limit
   stops being customer-facing at all; it becomes an internal budget for base + seasons + pinning,
   which will never approach it. **This is a genuine correction to v1's positioning conclusion.**
3. **It makes the unknown-end-time feature natural rather than clever.** v1 had to build an elaborate
   fallback-row construction to make "until the game ends" safe. Under the split it is just: the cloud
   knows when the game ends and sends the next state. The nightly restore row is a one-sentence
   safety net rather than the load-bearing mechanism.

### The one correction

**"Everyday lighting never depends on us" is only true for the base layer, and "everyday" is doing a
lot of work in that sentence.** Many customers' *everyday* experience will be a rotating set of
designs — which, in this architecture, are events. If those are cloud-fired, the claim misleads.

**Corrected form:**

> **Your everyday schedule lives on your controller — it runs through internet outages, server
> outages, and anything on our end. Special events and automations run from the cloud, so you get
> unlimited of them, planned as far out as you like, updated from anywhere.**

That is defensible sentence-by-sentence. It also creates a real product obligation: the **base layer
must be genuinely useful on its own**, not a degenerate "on at sunset, off at sunrise" placeholder,
because it is both the outage floor (§7) and half the marketing claim.

### Revised competitive table

| Capability | Competitors | v1 (device-only) | **v2 (split)** |
|---|---|---|---|
| Year-out planning | Oelo, Trimlight, EverLights | Plan yes, arm a rolling window | ✅ **Full parity — plan and arm a year, no horizon** |
| Timer count | Gemstone: 64 | ❌ 8, structural | ✅ **Unlimited events** — comparison retired |
| Multiple events/day + priority | None found | ✅ (slot-limited) | ✅ **Unlimited** |
| Unknown end time + defined fallback | None found | ✅ (elaborate) | ✅ **Natural** |
| Works during an internet outage | **UNVERIFIED** for them | ✅ everything | ⚠️ **base only** — honest, and still more than a pure-cloud competitor |
| Off-LAN schedule changes | Presumably yes | ❌ | ✅ **for events**; ❌ for base (needs cfg-over-bridge + OTA) |
| Verified arming / firing | None found | ✅ arm-verified (cfg readback) | ✅ **arm-verified AND fire-verified** (§6) — the strongest of the three |

**Do not overclaim, specifically:**

- Do **not** say "your lights never depend on our servers." False for events under this design.
- Do **not** say "unlimited timers." They are not timers; they are cloud events, with a different
  failure mode. Say "unlimited events."
- The comparative half of the outage claim — whether competitors' year-out schedules are
  cloud-executed or controller-resident — remains **UNVERIFIED** from v1 and gates that one
  comparison.
- "Fire-verified" is new and true (§6) but only for cloud-fired events. Device-timer fires remain
  unobservable without firmware.

---

## 10. REVISED PHASING

| Phase | Scope | Est | Confidence | Gate |
|---|---|---|---|---|
| **S1** | `controllerIp` validation (§8) | **3h** | High | **Gates S3. Hard.** |
| **S2** | Command expiry + deterministic IDs + sweeper (§4) | 10h | High | **Gates S3. Hard.** |
| **S3** | Fire-job collection + minute-cron dispatcher; `ping` shadow-latency run (§5) | 16h | Medium | S1, S2 |
| **S4** | Nightly restore row (Correction 2) | 6h | High | LAN visit; bench-check invisibility |
| **S5** | Game Day → fire jobs, server-side ESPN end-signal | 20h | Medium | Ship log-only first; a season of shadow data |
| **S6** | Fire receipts + cloud half of controller health (§6) | 8h | High | S3 |
| **S7** | Tests + bench | 12h | Medium | |
| | **→ MOTIVATING CASE COMPLETE** | **~75h** | **MED-HIGH** | |
| **P1** | Layers, compositor, hybrid precedence, migration (§1, §3) | 60-80h | Med-High | S3 |
| **P5a** | App half of controller health (cfg digests) | 20h | High | — |
| **PIN** | Pinned events → device timers, date-bounded (§7) | 24h | Medium | **`start`/`end` bench experiment** |
| **P4** | cfg-over-bridge + bridge-side expiry + ordered poll | 30-35h | Low-Med | **OTA, which does not exist** |

**What is now off the critical path** that v1 had on it: date bounding, the budget materializer,
deterministic slot allocation, eviction UI, the arm-horizon concession, and the entire lease preset
range 26-41.

**What remains gated on the bench:** seasons and pinned events only.

**What remains gated on OTA:** off-LAN *arming* (base-layer changes from away), bridge-side expiry
enforcement, and ordered command draining. All three are hardening or convenience, none blocks the
motivating case.

---

## UNVERIFIED — v2 list

Carried from v1 where still live, plus new items.

| # | Claim | How to settle |
|---|---|---|
| 1-6 | All six `start`/`end` semantics questions (v1 §1.3) | Bench, ~2h. **Now gates seasons + pinning only** |
| 7 | WLED re-attempts NTP only on boot → power cut during an outage = nothing fires | Bench. Still a precondition of the base-layer safety argument |
| 8 | ESPN `final` reliability under delays / suspensions / doubleheaders | A season of shadow logging (S5, log-only) |
| 9 | Competitors' year-out schedules: cloud-executed or controller-resident | Product research; gates one comparative claim |
| 10 | ESP32 partition table has room for OTA slots | Firmware inspection; gates P4 entirely |
| **11** | **Loading a preset identical to the running state is visually silent** | Bench, 10 min. **Gates S4** — the nightly restore row's whole premise |
| **12** | **WLED RTC drift between NTP syncs** — could be minutes on a long-uptime controller | Compare `/json/info` time vs. phone on a 30+ day uptime controller. **Sizes §3's ±2 min exclusion zone**, which may be far too tight |
| **13** | **Real cloud-fired P50/P95 latency**; the Admin-SDK write hop is unmeasured | One-week `ping` shadow run during S3 |
| **14** | **Firestore `runQuery` ordering without `orderBy`** — must not be assumed chronological | Read the bridge's poll response with 3+ queued commands |
| **15** | Whether a 0.5-6 KB inline-state fire payload transits the command document without chunking | Bench: write one server-side, observe the bridge |

---

## Findings

| # | Finding | Severity |
|---|---|---|
| 1 | **Server-side command injection is already a shipping path** — Google Smart Home and Alexa both write commands with the Admin SDK. This design is an extension, not a new mechanism | De-risks the whole approach |
| 2 | **"Events cost zero slots" is true for timers, false for presets** — unless fires carry inline state, which they can and should | Design correction |
| 3 | **The nightly restore row**: one permanent device timer makes *every* cloud event fail-safe, needs no date bounding, and costs 1 slot forever instead of 1 per event | **Best idea in this revision** |
| 4 | Phase 1 collapses **120-160h → ~76h**; the motivating case drops from **254-334h → ~75h** (~4×) | Headline |
| 5 | **The `start`/`end` bench experiment leaves the critical path** — it now gates seasons and pinned events only | Re-scoping |
| 6 | **The bridge has NO command expiry check of any kind**; the Cloud Function's 5-min check is webhook-only and every account is bridge-mode → **it is dead code fleet-wide** | **P1, live today** |
| 7 | **`expiresAt` is written by three server-side writers and read by nobody.** The TTL convention was designed; enforcement was never built | **P1, live today** |
| 8 | Commands are retained **7 days**; the bridge poll has **no `orderBy`** → a reconnecting bridge fires a stale backlog in unspecified order | **P1, live today** |
| 9 | A cloud-fired event is **faster** than an app-driven remote command (~1.1-1.9s to visible change) — the two slowest hops are the app's | Favourable, counter-intuitive |
| 10 | Measured tail is **30-32s** under queue pressure; a scheduled fire competes with user traffic. Design nothing that needs sub-5s fire timing | Constraint |
| 11 | Today two retried function invocations produce **two commands and two fires**. Deterministic doc IDs + `.create()` make duplicates structurally impossible | **Gate on S3** |
| 12 | **v1 was wrong that fire-level telemetry needs firmware** — the command `result` field carries WLED's own response, giving a fire receipt *stronger* than the cfg path's | **Biggest unlock** |
| 13 | A daily scheduled `getState` probe closes the "no controller-health signal in the fleet at all" gap with **zero firmware, ~4h** | **High leverage** |
| 14 | A Functions outage stops **every customer's events simultaneously**; the degraded mode is defensible **only if the base layer is non-empty**, which is not currently enforced | **P1 for the design** |
| 15 | Base-layer completeness must be promoted from a correctness invariant to an **availability control** | Design requirement |
| 16 | `controllerIp` validation moves from "prerequisite for cfg-over-bridge" to **gate on this design**; the server-side writer should omit the field entirely (0h, strictly best) | **Hard gate** |
| 17 | Positioning inverts: **"unlimited events" beats "64 timers."** v1's "put no number on the spec sheet" conclusion is superseded | Positioning |
| 18 | "Everyday lighting never depends on us" needs correction — true for base, false if a customer's everyday experience is cloud-fired events | Claim accuracy |
