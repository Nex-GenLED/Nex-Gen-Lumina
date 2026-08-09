# TEAM SELECTION SURFACES — audit before consolidating

**Date:** 2026-08-07 · **Branch:** `main` @ `d48072f` (`2.5.10+66`) · **READ-ONLY.**
Production Firestore was read; nothing was written. No code changed.

**Verdict up front: three surfaces, three stores, and the divergence is not theoretical —
26 of 45 selected teams (58 %) exist in a store that Game Day never reads.**

---

## 1. THE THREE SURFACES

| # | Surface | Widget | Reads | Writes | Store |
|---|---|---|---|---|---|
| 1 | **Home › Game Day › My Teams** | `game_day_screen.dart` → `TeamRegistrationService` | `game_day_autopilot` subcollection | **BOTH** the subcollection **and** the profile arrays | `users/{uid}/game_day_autopilot/{teamSlug}` **+** `users/{uid}.sports_teams[]` / `.sports_team_priority[]` |
| 2 | **System › Edit Profile › Interests & Fandom** | `edit_profile_screen.dart` `_InterestsCard` → `TeamSelector` | `users/{uid}.sports_teams[]` | **ONLY** `sports_teams[]` | `users/{uid}.sports_teams[]` |
| 3 | **System › Sports Alerts › Your Teams** | `sports_alerts_screen.dart` → `sportsAlertConfigsProvider` | `ScoreAlertConfig[]` | `ScoreAlertConfig[]` | **SharedPreferences — device-local, never in Firestore** |

**Three separate stores, not three views of one.** They share no primary key:

```
users/{uid}.sports_teams[]          →  ["Kansas City Chiefs", "Kansas City Royals"]   display names, free text
users/{uid}/game_day_autopilot/{id} →  nfl_chiefs, mlb_royals, fifa_usa                {league}_{short} slugs
SharedPreferences sports_alert_configs → ScoreAlertConfig{ teamSlug, sport, … }        device-local
```

The **only** join between stores 1 and 2 is the `team_name` field inside the subcollection
document — a denormalized copy of the display string. There is no slug in the profile array
and no array membership recorded on the config doc.

> **Method note, because it changed the answer.** My first census read `teamName` (camelCase)
> off the config docs, got empty on all 20, and reported **0** name-matched pairs — which
> would have meant total divergence. The field is `team_name`; the documents are snake_case
> throughout. Re-running on the correct field gives 9 matched users. **The same
> camelCase/snake_case trap as `display_name` in BRIDGE_TRIAGE.** Both numbers were
> "plausible"; only one was real.

---

## 2. THEY ARE SEPARATE — and the asymmetry is one-directional

### Does adding a team in one surface make it appear in the others?

| Add via… | → profile array | → Game Day config | → sports alerts |
|---|---|---|---|
| **Game Day › My Teams** | ✅ yes (`TeamRegistrationService.registerTeam` writes both) | ✅ yes | ❌ no |
| **Edit Profile › Interests** | ✅ (it *is* the array) | ❌ **NO** | ❌ no |
| **Sports Alerts** | ❌ no | ❌ no | ✅ (device-local) |

**So Game Day → profile propagates; profile → Game Day does not.** The relationship is a strict
subset: `game_day_autopilot ⊆ sports_teams[]`, enforced only by the fact that the one writer
that creates configs also appends to the array.

A customer who adds "Los Angeles Dodgers" in Edit Profile sees it listed under *Interests &
Fandom*, and Game Day will never fire for it. Nothing tells them.

### Can the same team exist in two stores with different settings?

**Not meaningfully — because only one store holds settings at all.** `sports_teams[]` is a bare
list of strings: no colours, no enabled flag, no design. All the settings —
`primary_color`, `secondary_color`, `effect_id`, `design_mode`, `enabled`,
`score_celebration_enabled`, `skip_day_games` — live only on the config document.

So there is no "which one wins" conflict for settings. **The conflict is about EXISTENCE**, and
that one is decided at fire time by `game_day_autopilot`: a team in the array with no config is
simply not a Game Day team.

One real divergence does exist: **`enabled`**. `ecochran08@yahoo.com` has
`ncaa_missouri (en=false)` and `ncaamb_missouri (en=false)` while "Missouri Tigers" sits in her
profile array looking selected. Two configs, both disabled, one array entry, no UI reconciling
them.

### Is there any sync?

**None.** No trigger, no reconciler, no migration. And removal does not cascade:

- `TeamRegistrationService.removeTeam` (Game Day) strips the array **and** deletes the config — correct.
- Edit Profile's save writes `sportsTeams: _sportsTeams` and **never touches `game_day_autopilot`**. Removing a team there leaves an orphan config that keeps firing.

That orphan path is live but **currently unrealised — 0 orphan configs fleet-wide** (§4). It
has simply not been exercised yet.

**One further asymmetry:** Edit Profile writes `sports_teams` but **not**
`sports_team_priority`, while `TeamRegistrationService` writes both. Priority drives
`GameDayPriorityResolver`'s tie-break when two teams play at once, so a profile-added team is
absent from the priority ordering as well.

---

## 3. WHAT EACH ACTUALLY DRIVES

| Consumer | Reads | Notes |
|---|---|---|
| **`GameDayAutopilotService` at fire time** | **`users/{uid}/game_day_autopilot/{teamSlug}`** | via `gameDayAutopilotConfigsProvider` (`:217`). The array is **not** consulted |
| **Background Game Day worker** | SharedPreferences mirror of the same configs | seeded from the subcollection |
| **Ephemeral session machine** | `users/{uid}/ephemeral_game_sessions` for state; **team config from `game_day_autopilot`** | same store as the autopilot |
| **Group / neighborhood Game Day** | `game_day_autopilot` (`group_autopilot_service.dart:32`) | same store |
| **`GameDayPriorityResolver`** | `sports_team_priority[]` → `sportsTeamPriorityProvider` | the array's one load-bearing use |
| **Sports alerts / notifications** | **SharedPreferences `ScoreAlertConfig[]`** | independent of both Firestore stores |
| **`team_color_resolver`** ("My Teams boost") | `profile.sportsTeams` | decorative — biases colour naming |
| **Lumina AI brain** | `profile.sportsTeams` | decorative — conversational context |

**Nothing is purely decorative enough to retire outright.** The closest is `sports_teams[]`,
whose only non-cosmetic consumers are the priority tie-break and AI/colour context — but it is
also the array every surface displays, so deleting it would empty two screens.

**The store that drives lights is `game_day_autopilot`. The store customers most visibly edit
is `sports_teams[]`. They are not the same store.** That is the whole problem in one sentence.

---

## 4. FLEET EVIDENCE — divergence has already happened

Read live, 2026-08-07, joined on `team_name`:

```
users with any team data              : 13
sports_teams[] entries (total)        : 45
game_day_autopilot docs (total)       : 20
users with a name-matched pair        :  9
users with profile teams and ZERO Game Day config: 4

TEAMS IN THE PROFILE WITH NO GAME DAY CONFIG : 26   ← selected, never fire
GAME DAY CONFIGS NOT IN THE PROFILE          :  0   ← no orphans yet
```

**58 % of every team any customer has selected will never trigger Game Day.**

| Account | Configured (fires) | Profile-only (never fires) |
|---|---|---|
| ecochran08@ | 10 — the only fully-configured account | 0 |
| marc@tapsonmain.com | mlb_royals, nfl_chiefs | 5 — Sporting KC, KC Current, Jayhawks, Missouri Tigers, Buffalo Sabres |
| dnicholas0131@ | fifa_mexico, fifa_usa (`en=false`) | 3 — Royals, Chiefs, Jayhawks |
| stegall.s@ | nfl_chiefs | 2 — St. Louis Blues, Sporting KC |
| chris_cipollone@ | mlb_royals | 2 — Chiefs, Dodgers |
| jjdyer1@ | mlb_royals | 2 — Chiefs, Jayhawks |
| tyler.honeycutt@ | nfl_chiefs | 2 — Sporting KC, KC Current |
| textim6@ | nfl_chiefs | 1 — Royals |
| cpaschall10@ | nfl_chiefs | 0 |
| **dbrosa99@** | **none** | **3** |
| **brooke.rozenberg@** | **none** | **2** |
| **ironreserveclub@** | **none** | **2** |
| **reviewer@** | **none** | **2** ("Chiefs", "Royals") |

**Four accounts have teams selected and no Game Day configuration at all.** For them the
feature is entirely inert while the profile screen shows their teams.

Two further observations from the data:

- **`sports_teams[]` accepts free text.** The reviewer account holds `"Chiefs"` and `"Royals"`;
  others hold `"Kansas City Sporting Kansas City"` — a double-prefixed name that would never
  match a canonical slug. The array has no validation against the team catalogue.
- **Store 3 cannot be audited at all.** `ScoreAlertConfig` lives only in SharedPreferences, so
  there is no fleet number for it, no backup, and no server read. It also does not survive a
  reinstall or a device change.

---

## 5. THIS BLOCKS S5 — and the answer is uncomfortable

**S5 must read `users/{uid}/game_day_autopilot/{teamSlug}`.** It is the only store that carries
what a fire needs — `espn_team_id`, colours, `effect_id`, `design_mode`, `enabled`,
`skip_day_games` — and it is what every existing fire path already reads. There is no
alternative.

**But it is not the store customers most visibly edit.** So the unattended failure mode is
precise and bad:

> A customer adds three teams under *Interests & Fandom*, sees them listed, goes away for the
> weekend, and unattended Game Day fires for none of them — while a fourth team they added
> months ago through the Game Day screen fires as normal. Nothing anywhere says why.

That is worse than today only because today the app is open and the Game Day screen shows the
real list. **Unattended operation removes the surface that currently reveals the truth.**

**S5 must not ship without at least one of:** (a) the consolidation below, or (b) an explicit
in-app signal on the Edit Profile list — "not set up for Game Day" against every array entry
with no config, with a one-tap fix. **(b) is the minimum**, and it is small.

---

## 6. RECOMMENDED CONSOLIDATION — not implemented

### Which store survives

**`users/{uid}/game_day_autopilot/{teamSlug}` survives as the single source of truth for
*which teams the customer follows*.** It is the only store with a stable key, the only one with
settings, the only one every fire path reads, and the only one already server-readable.

**`sports_teams[]` becomes a derived mirror**, not an input. Keep the field — `team_color_resolver`,
`lumina_brain`, and the priority provider read it — but have it written **only** by
`TeamRegistrationService`, never by a screen.

**`sports_team_priority[]` survives unchanged.** It carries ordering, which the config
subcollection has no home for.

**Store 3 (Sports Alerts / SharedPreferences) is the one to retire.** It is device-local,
unauditable, lost on reinstall, and duplicates a team list that already exists twice. Its one
unique field is `assignedZoneIds`; that belongs on the Game Day config as
`alert_zone_ids`.

### Which surface becomes a view

| Surface | Becomes |
|---|---|
| **Home › Game Day › My Teams** | **The editor.** Unchanged; it already writes both stores correctly |
| **System › Edit Profile › Interests & Fandom** | **A read-only view + deep link.** Shows the same list; "Add a team" navigates to Game Day rather than writing the array |
| **System › Sports Alerts › Your Teams** | **A per-team toggle view** over `game_day_autopilot`, editing `score_celebration_enabled` / alert fields in place |

Making Edit Profile read-only is the single highest-value change: it is the surface that
silently creates unfireable teams, and it is the source of all 26.

### Migration path

1. **Backfill configs for orphaned array entries.** For each of the 26, resolve the display
   name against the team catalogue and create a `game_day_autopilot` doc with
   **`enabled: false`** and catalogue-default colours. Disabled is essential — see below.
2. **Report what could not be resolved.** `"Chiefs"`, `"Kansas City Sporting Kansas City"` and
   `"Kansas State Wildcats"` may not map cleanly. Those need a human decision, not a guess;
   leave them in the array and list them.
3. **Make Edit Profile read-only** in the same release as the backfill, never before — until
   the backfill runs it is the only way some customers can express a team at all.
4. **Migrate `ScoreAlertConfig`** into the config docs on next app open, then drop the prefs key.
5. **Leave `sports_teams[]` in place permanently** as the derived mirror.

### What the customer sees during it — and the trap to avoid

**Nothing should disappear.** Every one of the 26 stays visible in both places; it simply gains
a real config behind it.

**But do not backfill with `enabled: true`.** Nine accounts would wake up to Game Day firing for
teams they never configured — Brooke's lights running for the Royals and Chiefs on a schedule
she never set. That is a worse first impression than the current silence, and it is exactly the
kind of change that erodes trust in an automation product. **Backfill disabled, and surface the
newly-created teams as "Ready to set up".**

The one genuinely visible change is Edit Profile losing its text field. Mitigate by keeping the
list, adding per-row status ("Game Day: on / off / not set up"), and making "Add a team" a
button that navigates rather than a field that silently half-works.

---

## 7. FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **Three surfaces, three stores, no shared key.** Profile holds display names, Game Day holds `{league}_{short}` slugs, Sports Alerts holds device-local configs. The only join is a denormalized `team_name` copy | **Structural** |
| 2 | **26 of 45 selected teams (58 %) have no Game Day config and will never fire.** Divergence is realised, not theoretical | **P1** |
| 3 | **Four accounts have teams selected and zero Game Day configs** — the feature is entirely inert for them while their teams display normally | **P1** |
| 4 | **Propagation is one-directional.** Game Day → profile writes both; profile → Game Day writes nothing. Every one of the 26 came from the profile screen | **Root cause** |
| 5 | **Removal does not cascade from Edit Profile** — it strips the array and leaves the config firing. Live path, 0 instances so far, simply not yet exercised | **P2, latent** |
| 6 | **Edit Profile also skips `sports_team_priority`**, so a profile-added team is missing from the tie-break ordering as well as from the fire path | P2 |
| 7 | **`sports_teams[]` is unvalidated free text** — `"Chiefs"`, `"Kansas City Sporting Kansas City"`. Some entries cannot be mapped to a slug without a human decision | **Blocks a clean backfill** |
| 8 | **Store 3 is device-local SharedPreferences** — unauditable, unbacked-up, lost on reinstall, invisible to the server. It is the right one to retire | Design |
| 9 | **S5 must read `game_day_autopilot`, which is not the store customers most visibly edit.** Unattended operation removes the Game Day screen — the only surface that currently reveals the truth | **Blocks S5** |
| 10 | **Backfilling `enabled: true` would be actively harmful** — nine accounts would find Game Day running for teams they never configured. Backfill disabled | Migration safety |
| 11 | **My first census read `teamName`; the field is `team_name`.** It returned 0 matches and would have reported total divergence. Same snake_case trap as `display_name` in BRIDGE_TRIAGE — both readings were plausible, one was real | **Method** |

---

## 8. OPEN QUESTIONS

1. **Was Edit Profile's team field ever meant to create Game Day teams?** The `TeamSelector` is
   a generic widget shared with onboarding; it may predate Game Day entirely and simply never
   have been reconciled. That changes whether §6 is a consolidation or a completion.
2. **What are the 3 unmappable names?** `"Chiefs"`, `"Kansas State Wildcats"`,
   `"Kansas City Sporting Kansas City"` — do these map to `nfl_chiefs`, an NCAA slug, and
   `mls_sporting_kc`? A slug table lookup would answer it; guessing would silently give a
   customer the wrong team.
3. **Does `ScoreAlertConfig.assignedZoneIds` matter to anyone today?** It is the only field
   store 3 owns. If unused, retiring store 3 is pure subtraction.
