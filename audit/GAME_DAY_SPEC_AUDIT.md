# Game Day / Score Alerts — Spec Audit

**Read-only.** Nothing was modified, nothing committed, no tests or analyzer run.

## 1. Branch and HEAD

| | |
|---|---|
| Branch | `audit/sports-alerts-sync` |
| HEAD | `900761e55db16e659d1241cd863f187aac608bb6` — *feat(sports-alerts): fold alerts onto the Game Day team card, retire the screen* |
| Base | `main` @ `c14368d`, plus the three shipped sync-fix phases (`71429c6`, `00ade26`, `900761e`) |
| Working tree | clean |

Measured against Tyler's five-point spec as stated.

---

## 2. Task 1 — What "sensitivity" actually does

### 2.1 What triggers `handleAlertEvent`

Three call sites, all score-event driven:

| Caller | Path |
|---|---|
| `sports_background_service.dart:234` | background isolate poll → `ScoreMonitorService` alert stream |
| `sports_background_service.dart:333` | background isolate, second arm of the same loop |
| `lib/services/commercial/game_day_service.dart:185` | commercial teams path |

Upstream, events are minted by `ScoreMonitorService` from ESPN score deltas.
The event vocabulary is `AlertEventType`
([score_alert_event.dart:4-27](lib/features/sports_alerts/models/score_alert_event.dart#L4-L27)):
`touchdown, fieldGoal, safety, goal, soccerGoal, run, quarterEndWinning,
clutchBasket, turnover`.

**Scores only. There is no win event.** No `win`, `victory`, or `gameWon`
member exists. `GameStatus.final_` is handled in exactly one place in the
monitor — [score_monitor_service.dart:154-159](lib/features/sports_alerts/services/score_monitor_service.dart#L154-L159)
— and all it does is evict cache entries and dedup keys. A final whistle fires
no celebration. `quarterEndWinning` is the closest existing thing and it is a
period boundary, not an outcome.

### 2.2 What `alert_sensitivity` gates

**It is a THRESHOLD FILTER on which events survive, not a selector among
effects.** The only consumer is
[`_filterBySensitivity`, score_monitor_service.dart:397-425](lib/features/sports_alerts/services/score_monitor_service.dart#L397-L425),
called at [:273](lib/features/sports_alerts/services/score_monitor_service.dart#L273):

- `allEvents` → pass everything through
- `majorOnly` → keep `touchdown, goal, soccerGoal, run, clutchBasket, quarterEndWinning`; drop `fieldGoal`, `safety`
- `clutchOnly` → keep only when `current.isClutchTime || current.isCollegeBasketballClutchTime`, or the event is `quarterEndWinning`

So it answers "how noisy should alerts be", and `clutchOnly` is the one option
that is genuinely game-context aware (close/late games).

**It never reaches the effect.** `handleAlertEvent` takes the config as its
second parameter — [alert_trigger_service.dart:89-92](lib/features/sports_alerts/services/alert_trigger_service.dart#L89-L92)
— and the body **never reads it**. Every other occurrence of the token `config`
in that 468-line file is an import, a doc comment, or the word "configured" /
"channel config". The parameter is dead inside the trigger service. Sensitivity
has already done its whole job upstream by the time the animation is chosen.

### 2.3 What actually goes to the house

`_applyAlertAnimation` → [`buildAnimationSteps(eventType, team)`,
alert_trigger_service.dart:273-390](lib/features/sports_alerts/services/alert_trigger_service.dart#L273-L390).
Two inputs: the **event type** and the **team's colors**. Nothing else.

The effects are **hardcoded per event type** — a fixed `switch` over
`AlertEventType` emitting literal WLED `fx` ids, speeds and hold durations:

| Event | Sequence (fx ids literal in source) |
|---|---|
| touchdown / goal | 15s: Strobe `fx:2` (2s) → Wipe `fx:9` (5s) → Running `fx:63` (8s) |
| fieldGoal | 8s: Breathe `fx:2` |
| safety | 6s: Strobe Mega `fx:23` |
| run | 6s: Theater Chase `fx:5` |
| quarterEndWinning | 10s: slow Breathe `fx:2` |
| clutchBasket | 5s: rapid Strobe `fx:23` |
| soccerGoal | 20s: Chase `fx:28` → Strobe `fx:23` → Running `fx:63` → Breathe `fx:2` |
| turnover | no animation |

**Per-team only in colour**, via `_teamColorArray(team)` / `colorToRgbw(team.primary)`
drawn from `kTeamColors`. The *motion* is identical for every team and every
user. **There is no user choice anywhere in this path** — no field is read that
a user could have set, because no such field exists.

So, against Tyler's point 3: a distinct effect DOES fire, and it is deliberately
attention-grabbing (strobe-led). What is missing is that it is **not chosen by
the user** — it is chosen by which sport-event happened.

### 2.4 Awareness of current house state

**It captures, but only to restore — never to contrast.**

- [`_captureZoneState`, :189+](lib/features/sports_alerts/services/alert_trigger_service.dart#L189) is a bare `svc.getState()`; the result is stored and passed to `_restoreZoneState` at [:141](lib/features/sports_alerts/services/alert_trigger_service.dart#L141).
- The captured state is **never read by `buildAnimationSteps`** — that function's signature takes only `eventType` and `team`, so it is structurally incapable of consulting what is on screen.
- When autopilot is running, capture/restore is delegated instead via the override protocol ([:110-118](lib/features/sports_alerts/services/alert_trigger_service.dart#L110-L118), released at [:147-152](lib/features/sports_alerts/services/alert_trigger_service.dart#L147-L152)) to avoid a double-restore race.

The steps do force `'on': true, 'bri': 255` on their first payload, which is a
blunt way of ensuring visibility, but there is **no comparison against the base
design's effect, palette, or brightness**. If a team's base design happened to
be a strobe in the same colours, the celebration would be near-invisible and
nothing in the code would notice.

---

## 3. Task 2 — `EphemeralGameSessionService`: does "join live" exist?

### 3.1 Status: complete and live, but it is **not** what the name suggests

The class is fully implemented and actively used —
[ephemeral_game_session_service.dart](lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart),
450 lines, with a model, providers, and a UI sheet beside it.

**It never lights anything at session start.** `createSession`
([:84-123](lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L84-L123))
takes exactly four arguments: `teamSlug`, `gameId`, `revertWledPayload`,
`revertLabel`. There is no game-time design parameter, and the only
`applyJson` in the entire file is inside `_handleGameEnd`
([:397-404](lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L397-L404)),
which applies the **revert** payload.

So it is an **auto-revert timer with a phase machine**: the caller lights the
house, then hands this service what to put back and when. The earlier
characterisation of it as "the phase machine that lights a mid-game join" is
half right — it is the phase machine; it does not light.

### 3.2 What `_advanceSession` does

[:279-362](lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L279-L362).
Polls ESPN on a 1-minute timer and walks `idle → preGame → liveGame → postGame
→ completed`.

It **does** detect an in-progress game: from `idle`, if game start has already
passed it polls ESPN and jumps straight to `liveGame` (or to `postGame` if
already final) — [:293-312](lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L293-L312).
That is genuine mid-game-join detection. But the transition only records a
phase; no payload is applied on entering `liveGame`. `postGame` starts a 30-min
countdown, then `_handleGameEnd` reverts.

### 3.3 Which UI calls it

| Affordance | Calls | Creates a session? |
|---|---|---|
| Lumina AI chat → [ephemeral_session_dispatcher.dart:245-251](lib/features/ai/ephemeral_session_dispatcher.dart#L245-L251) | `createSession` + `startTracking` | **Yes — the only creator** |
| Dashboard tile → [wled_dashboard_page.dart:550-562](lib/features/dashboard/wled_dashboard_page.dart#L550-L562) | opens `ActiveSessionSheet` | No — view only |
| `ActiveSessionSheet` → [active_session_sheet.dart:137, :227](lib/features/game_day/ephemeral_session/active_session_sheet.dart#L137) | `cancelSession` | No (the `createSession` at [:237](lib/features/game_day/ephemeral_session/active_session_sheet.dart#L237) is the **undo** of a cancel) |

**No button anywhere creates an ephemeral session.** The only entry point is a
natural-language request through the AI. The dashboard and sheet are
management-only surfaces for a session the chat already made.

### 3.4 Relationship to the other two systems

Three genuinely separate systems. None calls another:

- **`GameDayAutopilotService`** — the scheduled path, Firestore-backed, keyed on `teamSlug`, drives lighting from `game_day_autopilot` docs.
- **`EphemeralGameSessionService`** — transient one-shot revert timer, keyed on `sessionId` so multiple sessions per team can coexist. Its own file header ([:1-18](lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart#L1-L18)) admits the phase machine **structurally duplicates** `GameDayAutopilotService._updateActiveSession`, tracked as Item #54 for consolidation.
- **`AlertTriggerService`** — the celebration path, driven by `ScoreMonitorService`, coupled to autopilot only through the `AutopilotScheduler` override protocol, and **not** aware of ephemeral sessions at all.

### 3.5 The actual "join live" button

It is **"Light Up Now"** on the Game Day team card
([game_day_screen.dart:349-356](lib/features/game_day/game_day_screen.dart#L349-L356),
handler `_activateNow` at [:501+](lib/features/game_day/game_day_screen.dart#L501)) — not
the ephemeral service. It applies the team's base design immediately via
`applyGameDayConfigToDevice`, and then **force-enables Autopilot** if it was off,
with the comment stating this is required so the background worker creates a
session and score celebrations can fire.

That satisfies Tyler's point 5 functionally, with one wrinkle worth naming: a
manual mid-game join **cannot stay manual** — it flips `enabled:true`, which is
the field the server planner queries (`planGameDayFires.ts:342`), so joining one
live game also opts the team into scheduled shows for future games.

---

## 4. Task 3 — Base design selection

**Confirmed built and working.** Spec point 2 is the most complete of the five.

The user picks a team design from the team card's "Design" row
([game_day_screen.dart:368-375](lib/features/game_day/game_day_screen.dart#L368-L375)),
which routes through `_openDesignPicker` ([:442+](lib/features/game_day/game_day_screen.dart#L442))
to `/dashboard/game-day/picker/:nodeId` — the sports library leaf resolved by
`SportsLibraryBuilder.resolveTeamNodeId` — landing on
`ColorwayEffectSelectorPage`. Selection is written back to the
`game_day_autopilot` doc and rendered by `config.designLabel`
([game_day_autopilot_config.dart:247-256](lib/features/autopilot/game_day_autopilot_config.dart#L247-L256)).

### Storage, and whether a celebration effect would collide

The base design occupies these fields on `GameDayAutopilotConfig`:
`designMode` ([:95](lib/features/autopilot/game_day_autopilot_config.dart#L95)),
`savedDesignName` ([:98](lib/features/autopilot/game_day_autopilot_config.dart#L98)),
`savedDesignPayload` ([:102](lib/features/autopilot/game_day_autopilot_config.dart#L102)),
`effectId` ([:105](lib/features/autopilot/game_day_autopilot_config.dart#L105)),
plus `speed`/`intensity`/`brightness` and `designVariety`.

**They would not collide — but only because the celebration has nowhere to
live.** The two are already in separate code paths: `buildAnimationSteps` is a
pure function of `(eventType, team)` and never reads any design field, so a
celebration cannot overwrite the base design in the data model today.

The problem is the inverse: **there is exactly one design slot**, and it is
taken by the base look. There is no second slot — no `celebrationEffectId`, no
`celebration_payload`, nothing — so a user-chosen celebration effect has no
field to be stored in. Adding one is additive, not a conflict.

---

## 5. Task 4 — Effect-picker precedent

**Yes. A directly reusable one exists, and it is already on Game Day's own
design path.**

### The catalog
[`WledEffectsCatalog`](lib/features/wled/wled_effects_catalog.dart) — all WLED
effects 0-186, verified against `/json/effects` on firmware 0.15.1, each tagged
with a `category` and a `ColorBehavior`. It ships **17 named categories**
([:234-252](lib/features/wled/wled_effects_catalog.dart#L234-L252)) including an
explicit `EffectCategory(name: 'Strobe', icon: '⚡', description: 'Strobe and
lightning')` at [:245](lib/features/wled/wled_effects_catalog.dart#L245), and a
`MotionType` enum ([:35-43](lib/features/wled/wled_effects_catalog.dart#L35-L43))
whose members are `solid, twinkle, chase, sweep, **pulse**, fire, rainbow`.

So the "attention-grabbing" grouping Tyler describes — strobe / pulse — already
exists as first-class metadata. It is not curated *for celebrations*, but the
axis to curate on is there.

### The widget
[`ColorwayEffectSelectorPage`](lib/features/wled/colorway_effect_selector.dart)
— self-described at [:67-68](lib/features/wled/colorway_effect_selector.dart#L67-L68)
as "a large live preview with filter chips and curated effect grid". It renders:

- a **motion-type filter-chip row** over `MotionType.values` ([:1074-1090](lib/features/wled/colorway_effect_selector.dart#L1074-L1090))
- a **colour-behaviour filter row** — Any / My Colors / Blended / Auto ([:1095-1133](lib/features/wled/colorway_effect_selector.dart#L1095-L1133))
- a live on-device preview, and speed/intensity controls

This is the page Game Day's Design row already navigates to, so the interaction
model is familiar in exactly the right context.

### One dead alternative worth knowing about
[`EffectSelector`](lib/features/design/widgets/effect_selector.dart#L10) — a
Design Studio dropdown+sliders widget — **has no callers anywhere in `lib/`**.
It is dead code, not a second precedent.

Also note there are **two overlapping effect databases**:
`wled_effects_catalog.dart` and
[`effect_database.dart`](lib/features/wled/effect_database.dart) (both define
"Strobe"). The catalog is the one wired to the picker.

---

## 6. Task 5 — Gap table

| # | Spec point | Status | Shape of the gap |
|---|---|---|---|
| 1 | User selects a team | **(a) fully built** | None. Team card + `TeamRegistrationService.addTeam`, canonical and reversible. |
| 2 | Base design from team colours | **(a) fully built** | None. Design row → sports library → `ColorwayEffectSelectorPage` → `savedDesignPayload`. |
| 3 | User-chosen distinct celebration effect | **(b) partially built** | A distinct effect fires, but it is hardcoded per event type. Needs **data model** (a celebration-effect slot: fx id + speed/intensity, or a payload, distinct from the base design fields) + **new UI** (a picker; can reuse `ColorwayEffectSelectorPage`'s chip-grid-preview pattern filtered to strobe/pulse) + **firing logic** (`buildAnimationSteps` must take the user's choice; `handleAlertEvent` must actually read the `config` parameter it already receives and currently ignores). |
| 3b | "…stands out against whatever the base design is doing" | **(d) not built at all** | Nothing compares the celebration to the current house state; `buildAnimationSteps(eventType, team)` cannot see it. Needs **new firing logic** (contrast evaluation against the captured state, which is already fetched at `_captureZoneState` and currently used only for restore). No new UI implied. |
| 3c | A **win** triggers a celebration | **(d) not built at all** | `AlertEventType` has no win member; `GameStatus.final_` only evicts caches. Needs **new firing logic** (win detection + outcome comparison in `ScoreMonitorService`) + a **data model** addition (new enum member, and its animation/effect binding). |
| 4 | Runs under Autopilot, armed/disarmed around the real game | **(a) fully built** | None found. `GameDayAutopilotService` + the server planner (`planGameDayFires.ts`) schedule around ESPN game times; `AutopilotScheduler`'s override protocol already coordinates celebrations with the scheduled show. |
| 5 | Manual mid-game join, in real time | **(b) partially built** | "Light Up Now" works and arms celebrations. Two gaps, both **firing logic**: it force-enables `enabled:true`, so a one-off join permanently opts the team into scheduled shows; and the purpose-built transient path (`EphemeralGameSessionService`) that would let a join self-expire is **(c) built but disconnected** — see below. |
| 5b | `EphemeralGameSessionService` | **(c) built but disconnected from any button** | Complete and running, but its only creator is the Lumina AI chat dispatcher. Needs **new UI** (a button that creates a session) and, to match "join live" fully, **new firing logic** (apply the design on entering `liveGame`; today it only applies a payload on revert). |

Summary: **2 of 5 fully built** (team selection, base design), **1 fully built
and not in question** (autopilot scheduling), **2 partial** (celebration effect,
manual join), and **2 sub-points not built at all** (contrast-awareness, win
celebrations), plus **1 complete subsystem stranded without a button**.

The single highest-leverage observation: `handleAlertEvent` **already accepts
the config object** that would carry a user's celebration choice
([alert_trigger_service.dart:91](lib/features/sports_alerts/services/alert_trigger_service.dart#L91))
and simply never reads it. The plumbing for point 3 is half-laid.

---

## 7. Unknowns

1. **Whether "distinct effect" means one per team or one per event type.** The spec says the user chooses an effect; the current model has seven event-type-specific sequences. Whether a user choice replaces all of them, or overrides only the "big" events while `fieldGoal`/`safety` keep their smaller sequences, is a product decision the code does not record.
2. **What "stands out against the base design" should mean concretely.** Contrast could be evaluated on effect id, palette, brightness, or motion class. `ColorBehavior` and `MotionType` metadata would support any of these; nothing in the code indicates which was intended.
3. **Whether the commercial path is in scope.** `lib/services/commercial/game_day_service.dart:176-185` builds its own `ScoreAlertConfig` from `CommercialTeamProfile.alertIntensity` and calls the same trigger service. A user-chosen celebration effect would need a decision about whether commercial teams get the same control.
4. **Whether `turnover` is intentionally silent.** It is in the enum, is filtered out by `majorOnly`, and `buildAnimationSteps` returns no steps for it — marked "Phase 2". Whether it is meant to become a real event is not recorded.
5. **Real-world behaviour of the strobe-led sequences.** Whether the current celebrations actually read as distinct on a live roofline against a running base design is a hardware observation. Per the earlier sync audit, celebrations were fleet-wide non-firing until recently, so there may be little field evidence either way. Not verifiable from code.
6. **Whether a mid-game join should survive an app restart.** `EphemeralGameSessionService._bootstrap` resumes tracking on launch, but "Light Up Now" leans on the autopilot worker instead. Which of the two is intended to own a manual join is not stated anywhere in the code.
