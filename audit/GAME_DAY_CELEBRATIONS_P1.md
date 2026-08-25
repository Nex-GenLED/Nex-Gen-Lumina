# Game Day Celebrations — Implementation Report

Input: [audit/GAME_DAY_SPEC_AUDIT.md](GAME_DAY_SPEC_AUDIT.md). Findings are cited, not re-derived.

## 0. Branch

`feat/game-day-celebrations`, branched from **`900761e`**.

**The reposition-under-Autopilot fix had NOT landed.** `audit/sports-alerts-sync`'s
tip was still `900761e` at start, and no other local or remote branch carried it.
Per instruction I branched from `900761e` and note the gap here:

> The **Alerts** row currently sits under **Live Scoring**, not under Autopilot.
> Phase A's new **Celebration** row was placed directly beneath Alerts, since the
> two are one concern (Alerts = WHEN, Celebration = WHAT). When the reposition
> lands, both rows move together; the pair should stay adjacent.

Gates were run after every phase: `flutter analyze` **0 errors** and **381 issues**
throughout — identical to the pre-work baseline, so no new warnings — and the full
suite green at each step.

---

## 1. Pre-checks P1–P5

### P1 — GameDayAutopilotConfig's field list, and collisions

23 fields at [game_day_autopilot_config.dart:85-201](../lib/features/autopilot/game_day_autopilot_config.dart#L85-L201):
`teamSlug, teamName, espnTeamId, sport, primaryColorValue, secondaryColorValue,
enabled, designMode, savedDesignName, savedDesignPayload, effectId, speed,
intensity, brightness, scoreCelebrationEnabled, liveScoringEnabled,
alertSensitivity, skipDayGames, designVariety, motionStyle,
leadTimeMinutesOverride, onTimeOverride, offTimeOverride, untilDate, createdAt,
updatedAt, participatingChannelIndices`.

**No collision.** The only `celebration`-stemmed name is `scoreCelebrationEnabled`
([:117](../lib/features/autopilot/game_day_autopilot_config.dart#L117), Firestore
key `score_celebration_enabled`), which is a bool gate, not an effect. The new
`celebration_effect_id` / `celebration_speed` / `celebration_intensity` keys are
free.

### P2 — CommercialTeamProfile vs GameDayAutopilotConfig

**Genuinely separate models.** [commercial_team_profile.dart:66](../lib/models/commercial/commercial_team_profile.dart#L66)
is its own class under `lib/models/commercial/`, sharing no code and no supertype:

| | GameDayAutopilotConfig | CommercialTeamProfile |
|---|---|---|
| Team key | `teamSlug` (kTeamColors slug) | `teamId` (ESPN id) |
| Colours | `int` ARGB | `String` hex |
| Alert tuning | `AlertSensitivity` | `AlertIntensity` |
| Sport | `SportType` enum | `String` |

⇒ **Phase F needed its own fields.** Phases A–D did not reach it.

### P3 — final_ dedup, and the double-fire hazard

[score_monitor_service.dart:154-159](../lib/features/sports_alerts/services/score_monitor_service.dart#L154-L159)
does three things on `final_`: evicts `_gameStateCache`, **wipes `_emittedKeys`
for that game**, and drops `_lastCelebrationAt`.

**It can be extended, but not by reusing `_emittedKeys`.** A win routed through
the normal dedup would have its guard erased on the very tick it fired, and
re-fire on every later poll while ESPN still reported the game final. Two
independent guards were required and implemented:

1. a `_winEmitted` set the cleanup never touches;
2. a `previous.status != final_` **transition** check, which also prevents firing
   for a game already over when monitoring starts.

### P4 — Where a lighting apply belongs in the ephemeral phase machine

Transitions into `liveGame` occur at exactly two points:
[:310](../lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L310)
(`idle→liveGame`, the mid-game join) and
[:323](../lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L323)
(`preGame→liveGame`). Both were routed through one new `_goLive` helper.

**`_handleGameEnd`'s revert is unaffected.** It reads only
`session.revertWledPayload` / `revertLabel`, both captured at `createSession`
time and never rewritten, so applying earlier in the lifecycle cannot change
what it reverts to. The only requirement — met — is that the revert snapshot is
captured **before** the team design is applied.

### P5 — The override protocol, and two things the audit had not surfaced

`AutopilotScheduler.requestOverride`
([autopilot_scheduler.dart:106-146](../lib/services/autopilot_scheduler.dart#L106-L146))
**already generalizes**: it takes an `OverrideSource` and a duration, captures
state itself, and is a single-slot mutex. Nothing in it is specific to the
scheduled path.

Two findings that changed the shape of Phases C and E:

- **There are TWO independent celebration renderers.** Besides
  `AlertTriggerService.buildAnimationSteps`,
  [game_day_autopilot_background_worker.dart:243-295](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L243-L295)
  renders its own hardcoded Sparkle (`fx:11`) flash. For a team with a
  registered session but no monitoring config — a manual join — the worker is
  the **only** renderer that fires, because
  [sports_background_service.dart:~233](../lib/features/sports_alerts/services/sports_background_service.dart)
  calls `handleAlertEvent` only when a matching config exists in `active`.
- **Arming for an ephemeral session already had a purpose-built bridge**:
  `registerManualGameDaySession`
  ([game_day_background_persistence.dart:428](../lib/features/autopilot/game_day_background_persistence.dart#L428)),
  the prefs crossing into the background isolate. It was called from exactly one
  unrelated screen, and **not** from "Light Up Now".

---

## 2. What shipped, per phase

| Phase | Commit | Summary |
|---|---|---|
| A | `66ea94a` | Second design slot + celebration picker |
| B | `254cbbf` | Automatic contrast resolver (pure) |
| C | `cf09040` | Firing logic reads the config; timing table preserved |
| D | `3d79576` | Win celebration |
| E | `2c06411` | Manual join self-expires; stops arming the schedule |
| F | `eabd54e` | Commercial parity through one shared firing path |

### A — Data model + picker (`66ea94a`)

`celebrationEffectId` (nullable) / `celebrationSpeed` / `celebrationIntensity` on
`GameDayAutopilotConfig`, mirrored onto `BackgroundGameDayAutopilotConfig`
because of P5's second renderer. **Absent means null** and an unset celebration
writes no keys at all, so every pre-existing config round-trips byte-identically
and keeps its current behavior.

The picker **adapts** `ColorwayEffectSelectorPage` rather than adding a grid: a
new `celebrationMode` flag swaps the effect list for
`WledEffectsCatalog.celebrationPicks` and hides the motion/colour chips (they
would only let the user filter out of the attention-grabbing set). Same live
on-device preview, same tiles.

`celebrationPicks` is the union of the **`Strobe` category** and
**`MotionType.pulse`** — and that really is a union: `getMotionType` maps Strobe
to `MotionType.sweep` (with Wipe and Scanner), while `pulse` comes from
Ambient/Fireworks/Ripple/Noise. Filtering on either alone would have silently
dropped half the set. Sourced from `standardEffects`, so no 2D or audio-reactive
effects — a celebration must fire on any install.

The picker's palette node is **synthesized from the team's own colours** rather
than resolved through the sports library, so it previews in team colours
whichever colorway the base design came from, and does not depend on
`resolveTeamNodeId` finding a leaf.

### B — Contrast (`254cbbf`) and C — Firing (`cf09040`)

Covered in §3 below.

### D — Win (`3d79576`)

`AlertEventType.win`, fired on the transition into `final_` with the monitored
team ahead, guarded as P3 required. **30s, the longest in the table** (staged
5/10/15). Deliberately exempt from **both** the sensitivity filter and the
celebration cooldown: a `clutchOnly` user asked for fewer alerts, not to miss
their team winning, and a win landing seconds after the go-ahead score must not
be swallowed as a cooldown duplicate.

Adding the enum member broke three exhaustive switches — the compiler enforcing
completeness. Local duration table and notification title handled;
`sync_celebration_service` duration scaled to 1.5× base.

### E — Manual join (`2c06411`)

`_activateNow` no longer flips `enabled:true`. It now snapshots pre-apply state,
applies the design, then **arms** via `registerManualGameDaySession` and creates
an **ephemeral session** that reverts and disarms at the real final whistle.
Arming is not conditional on the session — ESPN lookups fail, and a celebration
without auto-revert beats a silent house.

The phase machine now **lights**: both `→liveGame` transitions apply the base
design through the same `applyGameDayConfigToDevice` helper Light Up Now uses.
Best-effort, so a failed apply cannot strand a session in preGame and thereby
prevent its revert. `_handleGameEnd` and `cancelSession` both clear the worker's
session, so arming ends with the session.

**Two gaps closed that would otherwise have made this inert in the field:**
- The worker loaded `_sessions` **once**, at `startMonitoring`. A join made while
  the service was already running armed nothing until a restart. `evaluate()`
  now adopts active persisted sessions for teams it does not already know
  (worker-owned sessions win, so completed sessions cannot be resurrected). This
  also fixes the pre-existing neighborhood caller, which had the same hole.
- Nothing guaranteed the poller was running; the scheduled path starts it only
  when a game is within 60 minutes, which is precisely the path a mid-game join
  is not on. Arming now starts the service (idempotent).

### F — Commercial (`eabd54e`)

See §4.

---

## 3. The exact "too similar" definition, and the fallback

Implemented in `WledEffectsCatalog.effectsTooSimilar`
([wled_effects_catalog.dart](../lib/features/wled/wled_effects_catalog.dart)),
consumed by `resolveCelebration`
([celebration_contrast.dart](../lib/features/sports_alerts/services/celebration_contrast.dart)):

```
tooSimilar(a, b) ⇔
      a == b                                            // same effect id
   OR (category(a) == 'Strobe' AND category(b) == 'Strobe')
   OR (motionType(a) == pulse   AND motionType(b) == pulse)
```

Two *different* strobes therefore clash, as specified. A Strobe and a pulse
effect do **not** clash with each other — they are different groups in this
catalog. An effect id absent from the catalog never clashes: it cannot be
classified, so claiming similarity would be a guess.

**Compared against LIVE house state at trigger time**, not the stored base
design — autopilot may have rotated the design, a schedule may have taken over,
or the user may have applied something by hand. The state comes from
`_captureZoneState`, or from `token.capturedState` when autopilot manages
capture/restore; without that second source the check would be dead in exactly
the case that matters most, a celebration during a scheduled show. `seg` is read
as **either a List or a Map** — the firmware variability documented in
CLAUDE.md; missing it would have silently disabled the check on one firmware.

**Fallback chosen: a full-brightness WHITE strobe** — `fx: 23`, `sx: 255`,
`ix: 255`, `col: [255,255,255,255]`.

White is load-bearing, not decorative. The fallback is substituted precisely
because the *motion* clashed, so another strobe in team colours would clash the
same way; colour is the one axis guaranteed to differ from a team-coloured base.
It is one fixed thing — every clash resolves to the identical celebration, and
it is never offered in the picker.

**Fail-open on missing information.** An unreadable state — controller
unreachable, empty snapshot, unexpected shape — fires the user's choice
unmodified. Substituting a white flood on every transient read failure would be
worse than the invisibility the check guards against.

**The timing table survived whole.** `buildAnimationSteps` keeps the per-event
switch (extracted to `_legacyAnimationSteps`): stage count, hold durations, and
the first stage's `on`/`bri` assertion are untouched, and its literal fx ids
remain the default when nothing is chosen. Only the `fx` (plus `sx`/`ix`) in each
stage is substituted. `turnover` stays silent, per the audit's Phase-2 marker.

**One consequence stated plainly:** because `sx`/`ix` also come from the choice,
the legacy per-stage speed ramp is no longer expressed — a chosen celebration is
one look held for the staged duration rather than three escalating ones. The
alternative was ignoring the speed the user set in the live preview, which would
make the picker lie.

---

## 4. Commercial parity finding

**Separate model, shared firing.** Per P2, `CommercialTeamProfile` needed its own
`celebrationEffectId` / `celebrationSpeed` / `celebrationIntensity`, added with
the same absent-means-null posture. `alertIntensity` does **not** conflict: it
maps to sensitivity (*when* a celebration fires) where these are the effect
(*what* fires).

`game_day_service.dart` copies the three fields onto the `ScoreAlertConfig` it
already builds, so a commercial celebration runs through **exactly** the
residential path — same `handleAlertEvent`, same contrast check, same timing
table, same win handling. No parallel implementation.

**The picker is NOT reachable for commercial accounts, and that is pre-existing.**
The only surface where a commercial account configures a team is `YourTeamsScreen`,
inside the commercial onboarding wizard — and **grep finds zero navigations to
`AppRoutes.commercialOnboarding`** anywhere outside its own route registration
([app_router.dart:699](../lib/app_router.dart#L699), constant at
[:1256](../lib/app_router.dart#L1256)). The whole configuration surface is
stranded, independent of this work.

So: a venue's celebration **can be set by data and fires correctly once set, with
full parity — but has no UI today.** Wiring up that wizard is a separate defect
and was not smuggled into this feature.

---

## 5. Deferred, and why

1. **A commercial celebration-picker UI.** Blocked by the unreachable wizard
   above. Adding a picker to a screen no one can navigate to would be motion
   without effect; reaching the wizard is a product decision.
2. **`turnover` remains silent.** Explicitly out of scope per the instruction and
   the audit's Phase-2 marker.
3. **`sync_celebration_service`'s effect selection for a win.** Its
   `_celebrationEffectId` switch has a `default`, so a synced win falls through to
   the group's configured effect. The neighborhood path has its own effect model;
   only the duration was scaled (1.5×). Out of scope here.
4. **No contrast check on the worker renderer.** That path dispatches through the
   server fanout and has no device read to compare against, so it takes the same
   fail-open posture the resolver takes on an unreadable state. It honours the
   chosen effect; it cannot check it.
5. **The `_activateNow` / picker UI is not widget-tested.** `GameDayScreen` has no
   widget-test harness anywhere in `test/`, and both `setCelebrationEffect` and
   `setAlertSensitivity` write through a hardcoded `FirebaseFirestore.instance`,
   so they cannot be driven against a fake. Tests pin the model contracts, the
   pure resolvers, the animation builder, the monitor's win logic, and the prefs
   crossing — not the screen. That is weaker than an end-to-end test and I did not
   build the harness.
6. **No hardware verification.** Everything here is analyzer- and suite-verified
   only. Nothing was run against a controller.

---

## 6. What I would have had to fabricate, and didn't

- **Whether "Pulse" means a specific effect id.** The spec named Pulse as an
  example; `MotionType.pulse` is a *category* covering Ambient/Fireworks/Ripple/
  Noise, and there is no single effect named "Pulse" driving it. Tests select
  effects **from the catalog at runtime** (`celebrationPicks.firstWhere(...)`)
  rather than hardcoding an id I would have had to invent.
- **The win's duration.** "Longest of the set" was the only constraint given.
  30s is a choice, asserted relative to every other entry rather than as a magic
  number, so it stays correct if the table changes.
- **The white fallback's exact form.** The instruction said "maximum-brightness
  white strobe, **or similar**". I implemented literally that and documented why
  white is doing the work, rather than inventing a more elaborate scheme.
- **Whether celebrations currently work on real hardware.** The prior audit noted
  celebrations were fleet-wide non-firing until recently, so there may be little
  field evidence. I did not claim any.
- **The affected-account Firestore state.** The earlier Phase 1 pre-check probe
  was blocked by the permission classifier and remains unanswered; nothing here
  depends on it, and I did not assume a result.
