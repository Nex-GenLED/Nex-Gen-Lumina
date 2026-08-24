# Sports Alerts ↔ Game Day Sync Audit

**Read-only audit.** No source files were modified; nothing was committed; no
tests or analyzer were run.

## 1. Branch and HEAD

| | |
|---|---|
| Branch | `audit/sports-alerts-sync` |
| Created from | `main` @ `c14368d9c4e40d1722afce015ad7b2e46090f967` |
| HEAD at audit time | `c14368d` — *docs(#108): file the Roofline Parent Segment redesign* |
| Worktree | isolated worktree (the primary tree was on `feat/design-card` with uncommitted work; it was not touched) |

Independent of `feat/design-card` and `feat/schedule-v3-model`.

---

## 2. Sports Alerts data source (Task 1)

**Screen:** `lib/features/sports_alerts/ui/sports_alerts_screen.dart`
(route `/settings/sports-alerts`, `lib/app_router.dart:1089`, constant at
`lib/app_router.dart:1161`).

### 2.1 Firestore paths read: **NONE**

The screen reads **zero** Firestore paths and **zero** fields. Its import block
(`sports_alerts_screen.dart:1-18`) contains no `cloud_firestore` import, no
Firestore provider, and no Game Day import. Every data read in the file:

| Line | Read | Backing store |
|---|---|---|
| `sports_alerts_screen.dart:59` | `sportsAlertConfigsProvider` | **SharedPreferences** |
| `sports_alerts_screen.dart:60` | `sportsAlertActiveProvider` | derived from the same list |
| `sports_alerts_screen.dart:196` | `sportsAlertConfigsProvider` (read) | same |
| `sports_alerts_screen.dart:208` | `activeAreaControllerIpsProvider` | controller IPs — unrelated to teams |
| `sports_alerts_screen.dart:786` | `activeGameProvider(config.teamSlug)` | live ESPN HTTP fetch, keyed off the local config |

**The actual store is a device-local SharedPreferences string-list under the key
`sports_alert_configs`** — declared twice, once per consumer:

- `lib/features/sports_alerts/providers/sports_alert_notifier.dart:12`
- `lib/features/sports_alerts/services/sports_background_service.dart:36`

Write helper: `saveAlertConfigs()` at `sports_background_service.dart:361`.

### 2.2 Stream or one-time fetch: **one-time, once per app process**

`sportsAlertConfigsProvider` is a plain `StateNotifierProvider` (not
`autoDispose`, not a `StreamProvider`) — `sports_alert_providers.dart:16-19`.

`SportsAlertNotifier` loads exactly once, from its constructor
(`sports_alert_notifier.dart:22-32` → `_load()` → `_loadFromPrefs()` at
`:88-96`). There is no listener, no re-read, no invalidation hook, and no
`ref.listen` on auth state. After first construction the list only ever changes
through this notifier's own `addConfig` / `removeConfig` / `updateConfig` /
`toggleConfig` (`:38-66`).

Because SharedPreferences is **device-scoped, not user-scoped**, and nothing
clears the key on sign-out (grep for a `sports_alert_configs` removal or a
`prefs.clear()` across `lib/auth`, settings, and `app_providers.dart` returns
nothing), these configs also survive account switches.

### 2.3 `lib/services/sports_alert_service.dart` (legacy) — not in this path

Only one reference exists in the whole tree:

```
lib/features/autopilot/background_learning_service.dart:10
```

It is **not** reachable from `SportsAlertsScreen` directly or transitively —
the screen's transitive closure is `sports_alert_providers.dart` →
`sports_alert_notifier.dart` → `sports_background_service.dart` /
`espn_api_service.dart` / `alert_trigger_service.dart`, none of which import it.
The legacy file is not the cause of this bug.

### 2.4 Row model

Each team row is backed by **`ScoreAlertConfig`**
(`lib/features/sports_alerts/models/score_alert_config.dart:30`), held as
`final ScoreAlertConfig config` on the row widgets at
`sports_alerts_screen.dart:458`, `:563`, and `:779`.

`ScoreAlertConfig` is a **JSON/SharedPreferences model** — `fromJson`/`toJson`
(`score_alert_config.dart:49`, `:61`). It has no `fromFirestore`, no document
id, and no Firestore counterpart. Its `id` is minted by whoever constructs it.

Sports Alerts' own add flow is likewise fully local:
`sports_alerts_screen.dart:757` → `TeamPickerScreen`
(`team_picker_screen.dart:28`, which filters the static `kTeamColors` catalogue)
→ `ZoneAssignmentScreen` → `addConfig` at `zone_assignment_screen.dart:404`.

---

## 3. Game Day write paths (Task 2)

### 3.1 Deleting a team

Confirmed call chain (not assumed):

1. `lib/features/game_day/game_day_screen.dart:586` →
   `GameDayAutopilotNotifier.removeTeam(teamSlug:, teamName:)`
2. `lib/features/autopilot/game_day_autopilot_providers.dart:773-801` →
   `TeamRegistrationService.removeTeam(...)` at `:789`
3. `lib/features/sports_alerts/services/team_registration_service.dart:105-126`:
   - `_stripTeamFromProfile` (`:214-235`) — `users/{uid}`, rewrites
     `sports_team_priority` and `sports_teams` with the team filtered out
     (case-insensitive), plus `updated_at`
   - **`.delete()` on `users/{uid}/game_day_autopilot/{teamSlug}`** —
     `team_registration_service.dart:118-122`. Best-effort: wrapped in
     try/catch, failure logged only.
4. Back in the notifier: `cancelSession(teamSlug)` and
   `state = Map.from(state)..remove(teamSlug)`
   (`game_day_autopilot_providers.dart:791-800`).

**Form of deletion: hard document delete + array element removal.** No soft
flag, no tombstone.

Server-side, `functions/src/teardownTeamFires.ts:87-90` fires an
`onDocumentDeleted` trigger on `users/{uid}/game_day_autopilot/{teamSlug}` and
retracts armed fires. It writes only to fire-job docs; it touches nothing
Sports Alerts reads.

### 3.2 Adding a team (Astros)

1. `game_day_screen.dart:1869-1880` → `toggleAutopilot(teamSlug:, enabled:false)`
2. `game_day_autopilot_providers.dart:626-660` (create branch) →
   `TeamRegistrationService.addTeam(uid:, teamSlug:)` at `:636`
3. `team_registration_service.dart:51-89`:
   - `set()` on **`users/{uid}/game_day_autopilot/{teamSlug}`** with
     `enabled:false` (`:64-86`)
   - `_appendTeamToProfile` (`:191-208`) — appends the team name to
     `users/{uid}.sports_teams` and `users/{uid}.sports_team_priority`
4. Optional follow-up `docRef.update({'enabled': true})` when the caller asked
   to create-and-enable (`game_day_autopilot_providers.dart:648-655`).

### 3.3 Does either write touch what Sports Alerts reads?

| Store | Game Day delete | Game Day add | Sports Alerts screen reads it? |
|---|---|---|---|
| `users/{uid}/game_day_autopilot/{slug}` | hard delete | `set()` | **No** |
| `users/{uid}.sports_teams[]` | element removed | element appended | **No** |
| `users/{uid}.sports_team_priority[]` | element removed | element appended | **No** |
| SharedPreferences `sports_alert_configs` | **untouched** | **untouched** | **Yes — exclusively** |

Verified by exhaustive grep: the only production callers of
`addConfig`/`removeConfig` (the sole writers of the prefs key) are
`zone_assignment_screen.dart:404` (Sports Alerts' own picker) and
`live_scoring_prompt.dart:104`. Neither Game Day add nor Game Day delete is
among them.

### 3.4 Would deletion form matter to the Sports Alerts query?

No — and this is the point. Sports Alerts issues **no query at all** against
either store. Hard delete, soft flag, and array removal are all equally
invisible to it. Changing the delete's shape cannot fix this symptom.

---

## 4. Root cause per symptom

### 4.1 Same store or two stores?

**Two entirely different stores, with no overlap:**

- Game Day → Firestore (`game_day_autopilot` subcollection + profile arrays)
- Sports Alerts screen → device-local SharedPreferences `sports_alert_configs`

### 4.2 Is there sync code intended to bridge them?

Three bridges exist in the tree. **None of them syncs the Sports Alerts screen.**

1. **`resolveMonitoring`** — `lib/features/autopilot/unified_monitoring.dart:83-104`.
   This *is* the real unification, and it works, but it lives in the
   **background monitoring engine only**: called from
   `sports_background_service.dart:178`, and nowhere else in `lib/`. Game Day is
   authoritative there; legacy prefs configs are honoured only as orphans
   (`unified_monitoring.dart:98-101`). The Sports Alerts **UI never calls it.**

2. **`migrationConfigsFor`** — `unified_monitoring.dart:141`. Written to adopt
   orphaned prefs configs into Game Day docs. Grep for callers across `lib/`
   and `test/`: **the only references are its own definition and
   `test/features/autopilot/unified_monitoring_test.dart`.** The migration is
   **implemented, unit-tested, and never wired to a production caller.** The
   comment at `sports_background_service.dart:174-175` ("honoured only until
   migration adopts them") describes a migration that does not run.

3. **`maybePromptLiveScoring`** — `lib/features/game_day/live_scoring_prompt.dart:39-116`.
   The one place Game Day writes into the prefs store — but it is a
   **one-directional, opt-in, apply-time prompt**: it fires only after a
   team-associated design is applied, only when ESPN reports a game within 24h,
   and only when the user taps accept (`:86`, `:94-105`). It has **no delete
   counterpart at all.**

No Cloud Function trigger bridges the two; `teardownTeamFires` (§3.1) is
Firestore-to-Firestore, and prefs are on-device and unreachable from a function.

### 4.3 The asymmetry — one cause or two?

**One root cause, two faces.** Both symptoms follow from the same defect: the
Sports Alerts screen never migrated off its private SharedPreferences store when
Game Day became the source of truth, so it reads a store no Game Day write ever
touches.

- **Stale Chiefs / Royals / Dodgers persist** — those three entries were written
  to prefs at some earlier point (via `zone_assignment_screen.dart:404`, or
  `live_scoring_prompt.dart:104`). Deleting them in Game Day ran
  `team_registration_service.dart:118-122` and `:214-235`, which delete a
  Firestore doc and edit two Firestore arrays. **Nothing in that path can
  remove a prefs entry.** The prefs list is unchanged, so the screen renders the
  same three rows.
- **Astros absent** — adding it ran `team_registration_service.dart:64-86` and
  `:191-208`, which write Firestore only. **No `ScoreAlertConfig` was ever
  minted**, so there is no prefs entry to render.

This is **not** a missing invalidation. A missing `ref.invalidate` would produce
only the stale half; here the store is simply disjoint, so *every* Game Day
mutation is invisible in *both* directions — deletes fail to propagate and
creates fail to propagate. One store mismatch, symmetric by construction, which
is exactly why both symptoms appear together.

The one-time-load design (`sports_alert_notifier.dart:22-32`) is a **second,
independent latent bug** — it would keep the screen stale within a session even
if the store were correct — but it is not what produced either reported symptom.

### 4.4 Functional consequence beyond the UI

Because `resolveMonitoring` includes orphaned legacy configs in `monitored`
(`unified_monitoring.dart:98-101`) and no Game Day doc exists for the three
deleted teams, those stale prefs entries **still arm background monitoring**.
The user deleted Chiefs, Royals, and Dodgers from Game Day and the device can
still poll ESPN and fire celebrations for them. Only teams that *retain* a Game
Day doc are correctly governed by Live Scoring (`unified_monitoring.dart:94` —
"Game Day wins"). Deleting the doc removes the very thing that would have
suppressed the orphan.

---

## 5. UI-only fix, data fix, or both?

**Both — and the data half is the load-bearing one.**

- **UI half:** the Sports Alerts screen reads `sportsAlertConfigsProvider`, not
  the Game Day source (`gameDayAutopilotConfigsProvider`,
  `game_day_autopilot_providers.dart:213-230`, which is already a live
  `StreamProvider`). That mismatch accounts for both rendered symptoms.
- **Data half:** the orphaned prefs entries would still exist and would still
  arm monitoring (§4.4) even if the UI read the right source.
  `migrationConfigsFor` (`unified_monitoring.dart:141`) is the already-written,
  already-tested tool for adopting or clearing them, and it has no production
  caller.

Addressing only the UI layer hides the symptom while leaving deleted teams
monitored; addressing only the data layer leaves the screen unable to show
newly added teams.

*(Per scope: no fix is proposed or written here — this is a characterisation of
which layers the defect spans, not a plan.)*

---

## 6. Unknowns

1. **Which surface originally created the Chiefs / Royals / Dodgers entries.**
   Two writers are possible — `zone_assignment_screen.dart:404` (the Sports
   Alerts picker) and `live_scoring_prompt.dart:104` (the Game Day apply-time
   prompt). The prompt stamps a `gameday_adhoc_` id prefix
   (`live_scoring_prompt.dart:99`) while the picker mints its own; reading
   on-device prefs would settle it, but the code alone cannot.
2. **Whether the three teams also still have `game_day_autopilot` docs.** The
   delete is best-effort (`team_registration_service.dart:123-125`, failure
   swallowed and logged). If a delete silently failed, that team would *also*
   have a surviving Firestore doc. Requires reading the user's Firestore data
   with a client credential — not verified here.
3. **Whether the profile arrays are actually clean.** `_stripTeamFromProfile`
   matches on `teamName` case-insensitively, not on slug. A drifted or free-text
   `sports_teams` value (the case `removeTeamByNameOnly` at
   `team_registration_service.dart:140` exists to handle) would survive the
   strip. Not verifiable from code.
4. **Whether the weekly-brief Cloud Function's view agrees.** It reads
   `sports_teams` / `sports_team_priority`, which Game Day *does* maintain, so
   it should track Game Day rather than the Sports Alerts screen — but the
   function's own read path was not traced in this audit.
5. **Whether `SportsAlertsScreen` is intended to survive.** `unified_monitoring.dart:21`
   and `game_day_autopilot_config.dart:131` both refer to a "retired
   sports-alerts" surface, yet the route is live at `app_router.dart:1089`.
   Whether the intended end state is "repoint the screen" or "delete the screen"
   is a product decision the code does not record.
