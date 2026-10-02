# Game Day celebration length: Short / Medium / Long

**Spec for owner approval, 2026-10-02.** Not built. Debt **#169**; related finding **#170**.

A team setting for how long a score celebration plays. Every celebration has a fixed, finite length: there is no "until I turn it off", and nothing may let a celebration run on indefinitely. Length is separate from **Speed**, which sets how fast the effect animates.

---

## 1. How length works today

### Where it lives
- **Timing table.** `AlertTriggerService._legacyAnimationSteps` and `animationDuration` in `lib/features/sports_alerts/services/alert_trigger_service.dart` (`:200-215`, `:403-560`). Each event is a list of stages; each stage is a WLED payload plus a hold.
- **Live path.** The foreground coordinator (`foreground_celebration_coordinator.dart`) does capture → `buildAnimationSteps` → `WledCelebrationDelivery.play` → `revert`.
  - `play` (`foreground_celebration_providers.dart`) sends each stage through `wledRepositoryProvider` (LAN or relay), then holds it with `Future.delayed(step.hold)`.
  - `revert` then reloads the captured preset (`{ps:N}`), or restores the captured `on` / `bri` / `seg`.
  - Consecutive celebrations are separated by at least `kCelebrationMinGap` (2 s). If several scores arrive while one plays, they coalesce into a single follow-up celebration.
- **The team doc's three celebration fields** (`users/{uid}/game_day_autopilot/{team}`):
  - `celebration_effect_id` replaces the `fx` of **every stage**;
  - `celebration_speed` sets `sx` (default 240);
  - `celebration_intensity` sets `ix` (default 240).

  They change what plays. They never change how many stages there are or how long each is held (`_applyCelebrationToStage`).

### The exact table (medium = today)

| Event | Sport | Stages (effect · hold) | Total |
|---|---|---|---|
| Touchdown | NFL, NCAA FB | Breathe fx 2 · 2 s → Wipe fx 3 · 5 s → Running fx 15 · 8 s | **15 s** |
| Goal | NHL | same as touchdown | **15 s** |
| Goal | MLS, NWSL, FIFA, Champions League | Chase fx 28 · 6 s → Strobe fx 23 · 4 s → Running fx 15 · 6 s → Breathe fx 2 · 4 s | **20 s** |
| Field goal | NFL, NCAA FB | Breathe fx 2 · 8 s | **8 s** |
| Safety | NFL, NCAA FB | Strobe fx 23 · 6 s | **6 s** |
| Run | MLB | Theater fx 13 · 6 s | **6 s** |
| Quarter end, winning | all | Breathe fx 2 · 10 s | **10 s** |
| Clutch basket | NBA, WNBA, NCAA MB (clutch time only) | Strobe fx 23 · 5 s | **5 s** |
| Win | all | Breathe fx 2 · 5 s → Wipe fx 3 · 10 s → Running fx 15 · 15 s | **30 s** |
| Turnover | — | none | 0 |

- **The touchdown's 15 s is by design.** `animationDuration` says 15 s, and its stages sum to 2 + 5 + 8. The earlier fx 2 / 9 / 63 stages became 2 / 3 / 15 in `60282a3` (2026-09-21, rainbow → team colours).
- **There is no extra-point event.** An NFL +1 falls to the `default:` branch of `_diffNfl` and is classified as a **touchdown**. So a PAT plays a second 15-second touchdown celebration, even under "Major only". That's filed in #169; the fix is a `fieldGoal`-class or ignored event for +1.

### What the length is in practice
- **On home Wi-Fi:** the table, plus write latency (well under a second).
- **Away from home (relay):** each stage write waits for the bridge, typically 2–7 s and up to 30–45 s. Each stage therefore shows for its hold plus the next write's latency. A touchdown is 15 s plus three bridge round trips plus the revert: usually 25–35 s, occasionally over a minute.
- **When it can run on indefinitely (#170).**
  - The hold is a Dart timer on the phone. If iOS suspends the app mid-celebration (screen locked, app switched), the timer stops: the celebration keeps playing and the revert waits until the app resumes.
  - If the app is killed while suspended, nothing ever reverts it. The house stays on the celebration effect until the Game Day end, a schedule or the customer changes it.
  - This is the one way today's design can break the "always finite" rule.

---

## 2. The proposal

### Data model
- **Field:** `celebration_length` on the team doc. Values `"short"`, `"medium"` or `"long"`.
- **Absent or unknown means medium**, which is exactly today's table. Existing accounts change nothing; no migration.
- `GameDayAutopilotConfig` gains `celebrationLength` (an enum). It is written only when the customer picks one.
- **Rules:** none needed. The `game_day_autopilot` match is owner-only, with no key list.

### Two options

| | (a) Multiplier of each event's length (**recommended**) | (b) Fixed lengths, whatever the event |
|---|---|---|
| Short / Medium / Long | × 0.5 / × 1 / × 2 | e.g. 8 s / 15 s / 30 s |
| A touchdown stays longer than a field goal | yes | no — every event the same length |
| Medium = today | yes, exactly | no — a field goal would go from 8 s to 15 s |
| Staging (build-up of a win) | kept, scaled | must be re-cut per length |
| Copy | "about half / twice as long" | three numbers |

**Recommendation: (a).** It is the only option where the default stays today's behaviour. It also keeps the table's intent ("a win is the moment the whole feature exists for", the longest entry).

### Hard limits (enforced in code, whatever the setting)
- **Maximum 60 s** for any single celebration, including all of its stages. The win at Long is exactly 60 s. A value from anywhere else (a bad doc, a future preset, the server) is clamped.
- **Minimum 5 s.** Anything shorter reads as a glitch, and away from home a shorter one can be over before the bridge has delivered it.
- **Rounding.** Each stage is scaled and rounded to whole seconds (at least 1 s per stage). The last stage absorbs the remainder, so the total is `round(medium × multiplier)`, then clamped to 5–60 s.
- **Always reverts.** The player computes `revertBy = start + total + 10 s` before it plays. See §2.5 for how that holds when the app is suspended.

### Seconds per event

| Event | Short | **Medium (today)** | Long |
|---|---|---|---|
| Touchdown / NHL goal | 8 (1 + 3 + 4) | **15** (2 + 5 + 8) | 30 (4 + 10 + 16) |
| Soccer goal | 10 (3 + 2 + 3 + 2) | **20** (6 + 4 + 6 + 4) | 40 (12 + 8 + 12 + 8) |
| Field goal | 5 (min) | **8** | 16 |
| Safety | 5 (min) | **6** | 12 |
| MLB run | 5 (min) | **6** | 12 |
| Quarter end, winning | 5 | **10** | 20 |
| Clutch basket | 5 (min) | **5** | 10 |
| Win | 15 (3 + 5 + 7) | **30** (5 + 10 + 15) | 60 (10 + 20 + 30) — the max |

### 2.5 Keeping it finite on the phone (#170)
1. **Before** the first stage, persist `{captured state, revertBy}` in local storage.
2. On every app resume and launch, if a persisted celebration is past `revertBy` and was not reverted, revert it now, then clear the record.
3. **Away from home:** play ONE stage held for the total instead of several, as the server does. Three serial bridge round trips make stage holds meaningless and stretch a short celebration well past its length.

This gives a bound of `revertBy` after the next app open. The only true "phone off" guarantee is the server path (§4).

---

## 3. In the app

### Where
In the celebration picker (`ColorwayEffectSelectorPage`, celebration mode), directly under the **Speed** slider (`colorway_effect_selector.dart`, `_buildCelebrationBody`). That is where a team's celebration is already shaped. The team card's **Celebration** row value gains the length, e.g. "Chase · Long".

### Labels and copy
- **Label:** "Length"
- **Control:** a three-way segmented control: **Short · Medium · Long** (Medium selected when unset).
- **Helper line** (changes with the selection):
  - Short: "About half as long — a touchdown plays 8 seconds, a win 15."
  - Medium: "The usual length — a touchdown plays 15 seconds, a win 30."
  - Long: "Twice as long — a touchdown plays 30 seconds, a win a full minute."
- **Always shown, below:** "Celebrations always end on their own, and your lights go back to the game look."

### Preview
- The picker's animated preview shows a length chip ("15 s").
- "Preview on lights" plays the touchdown sequence at the chosen length, then reverts. It goes through the same player, so the preview proves the length and the revert.

### Accessibility
At ×1.0 / ×1.75 / ×2.0 with Bold Text:
- the segmented control wraps to one option per line instead of truncating;
- the helper line wraps;
- the 48 dp targets hold.

The harness test lives beside the existing celebration-picker text-scale tests.

---

## 4. Server-run celebrations (plan step G / S5b)

### Design today
Plan `docs/gameday_server_authority_plan_2026-10-01.md` §3.5, on the `docs/gameday-server-authority-plan-2026-10-01` branch:
- **Poller.** `pollLiveScores` runs on a minute cron (`timeoutSeconds: 70`) and polls ESPN at t+0 and t+30.
- **Celebration job.** `fire_jobs/{eventId}_cel_{score}` holds **one stage** (the team's effect, speed and intensity in team colours) for the app's medium total. It has `noLaterThan: now + 60 s` and is never retried. The poller dispatches it itself, in the same invocation.
- **Revert job.** `fire_jobs/{eventId}_rev_{score}` `dependsOn` the celebration and is minted only once that is terminal.
  - `fireAt = cel.completedAt + hold + 2 s` (fallback `cel.fireAt + hold + 10 s`); `retryUntil = fireAt + 5 min`.
  - Its payload is the session's start payload.
  - It is dispatched by the **minute-cron dispatcher**, which runs each minute at about :03–:18 s.
- **Watchdog.** It re-mints a revert that has not completed within `hold + 3 min`, up to 3 times. The game's end job restores the base look regardless.

### How precisely each length could be honoured
- **Through the minute dispatcher (as designed):** the revert lands up to about 60 s after it is due, plus the bridge's 2–7 s.
  - A Short touchdown (8 s) could show for about 70 s.
  - Medium (15 s) for about 75 s.
  - Long (30 s) for about 90 s.

  That is too coarse for Short and Medium.

### Proposed: the poller dispatches the revert itself
1. The poller sleeps until the revert is due, then dispatches it in-process. This applies when the revert's `fireAt` falls inside the current invocation, with a 10 s margin; that is any hold up to about 45 s for a celebration found at t+0, and about 15 s for one found at t+30.
   - **Result:** about exact (± bridge latency) for Short and Medium, and for Long when detected at t+0.
2. Otherwise, the poller's t+0 and t+30 ticks also check "reverts due" (a cheap query on the session's revert job). Lateness is then at most 30 s, not 60 s.
3. The minute dispatcher remains the backstop.

**Copy, honestly:** "Score celebrations from our servers run for about the length you chose; the end can land up to half a minute late."

### Note for the functions window (paste-able)
> **Celebration length (owner spec 2026-10-02, debt #169) — for S5b.**
> - Read `celebration_length` from `users/{uid}/game_day_autopilot/{team}`: `"short"` × 0.5, `"medium"` × 1 (absent or unknown = medium), `"long"` × 2. Apply it to the app's per-event medium totals: TD/NHL goal 15, soccer goal 20, FG 8, safety 6, MLB run 6, quarter-end 10, clutch 5, win 30.
> - Clamp every hold to **5–60 s**. This is the same hard maximum as the app, whatever the doc says.
> - **Always mint the revert**: on every celebration, including failed, expired and kill-switched ones, as §3.5 already says.
> - Dispatch the revert from the poller when it is due inside the current invocation; otherwise check due reverts on every poll tick. The minute dispatcher stays the backstop.
> - The per-event table is mirrored from the app. Add it to the drift check proposed in #162.

---

## 5. What changes, and when

### Files (when approved)
- **App:**
  - `lib/features/autopilot/game_day_autopilot_config.dart`: field, `fromJson`/`toJson`, enum.
  - `lib/features/autopilot/game_day_autopilot_providers.dart`: `setCelebrationLength`.
  - `lib/features/sports_alerts/services/alert_trigger_service.dart`: scale `buildAnimationSteps` by length, clamp 5–60 s, rounding.
  - `lib/features/sports_alerts/services/foreground_celebration_coordinator.dart` and `foreground_celebration_providers.dart`: pass the length; persisted `revertBy` with revert on resume; single stage away from home.
  - `lib/features/wled/colorway_effect_selector.dart`: the Length control and the preview chip.
  - `lib/features/game_day/game_day_screen.dart`: Celebration row value.
  - The ScoreMonitorService +1 fix (`score_monitor_service.dart`).
- **Tests:**
  - `celebration_length_test.dart`: table × preset, clamps, rounding, absent = medium.
  - The coordinator: revert-on-resume and single stage on relay.
  - The picker at ×1.0 / 1.75 / 2.0 with Bold Text.
  - The PAT classification.
- **Functions (separate window):** the S5b items above. **Rules:** none.

### Migration
None. Absent means medium, which is today.

### When to ship
**The app half can ship in the next planned build**, independent of the server:
- it changes nothing until a customer picks Short or Long;
- the 60 s cap and the resume revert (#170) make the phone path safer as they stand.

**The server half waits for S5b** (plan step G). Until then server-run teams stand down to the phone for celebrations, so the phone honours the setting everywhere.
