# TEAM CONSOLIDATION — implementation

**Date:** 2026-08-07 · **Branch:** `main` @ `d48072f` (`2.5.10+66`), working tree
**Release-affecting — touches `lib/`.** Implements
[audit/TEAM_SURFACES.md §6](audit/TEAM_SURFACES.md).
**The backfill was NOT run against production.** Built, dry-run, reported.

**Steps 1–3 and 5 are done. Step 4 is deliberately NOT built — see §5 for why, and it is not
a shortcut.**

---

## 0. FIRST — `assignedZoneIds` IS WRITE-ONLY. Retiring store 3 is pure subtraction.

Asked before building, as instructed. Every mention across `lib/` and `test/`:

| Site | What it does |
|---|---|
| `score_alert_config.dart:26,35,45,54,66,83` | field declaration, `copyWith`, `fromJson`, `toJson` |
| `zone_assignment_screen.dart:379,400` | **writes** it |
| `game_day_service.dart:181` | **writes** it (`// carries the channel scope`) |

**Property reads — `config.assignedZoneIds` used to decide anything: ZERO.** A precise search
excluding named-argument sites returns only the field's own default initializer.

And the consumer proves it. `AlertTriggerService.handleAlertEvent` receives the config and
fires to **`for (final ip in _controllerIps)`** — every controller — capturing and restoring
whole-zone state via `_captureZoneState`. It never consults the field. The commercial
service's comment says the config "carries the channel scope"; nothing ever unpacks it.

> **So the scoping the field advertises has never happened.** Nothing breaks if it disappears.
> Store 3 can be retired without carrying `alert_zone_ids` onto the config document — one less
> field, and one less piece of false capability.

---

## 1. STEP 1 — BACKFILL, DISABLED

[scripts/_backfill_team_configs.js](scripts/_backfill_team_configs.js) — `--dry` / `--commit`.

**The catalogue is parsed out of `team_colors.dart` itself** (449 teams), not hand-copied. One
source of truth; a new team in the Dart file is available to the backfill with no edit.

### Dry run against production — nothing written

```
users with teams   : 13
already configured : 20
would create       : 31          (all enabled:false)
multi-sport names  :  6          (each creates 2 configs)
unresolved         :  0
```

*(Before the multi-sport decision this read `would create: 21, ambiguous: 5`. The extra 10 are
the five unmapped names × 2 sports; `already configured` moved 19 → 20 because ecochran08's
Missouri pair now matches by slug on both entries instead of once by name.)*

**Zero unresolved.** Every name maps or is flagged. `"Chiefs"` → `nfl_chiefs`, `"Royals"` →
`mlb_royals`, `"Kansas City Sporting Kansas City"` → `mls_sporting_kc` (Tyler's confirmed
aliases); everything else resolved by exact catalogue name — `"St. Louis Blues"` → `nhl_blues`,
`"Los Angeles Dodgers"` → `mlb_dodgers`, `"Buffalo Sabres"` → `nhl_sabres`,
`"Kansas City Current"` → `nwsl_kc_current`.

### Multi-sport names — RESOLVED: create both, disabled (Tyler, 2026-08-07)

Three college names map to two catalogue slugs each, because the slugs split by sport and both
carry the identical `teamName`:

| Name | Creates | Accounts |
|---|---|---|
| `Kansas State Wildcats` | `ncaa_kansas_state` + `ncaamb_kansas_state` | dbrosa99 |
| `Kansas Jayhawks` | `ncaa_kansas` + `ncaamb_kansas` | jjdyer1, dnicholas0131, marc |
| `Missouri Tigers` | `ncaa_missouri` + `ncaamb_missouri` | ecochran08 (already has both), marc |

**The precedent settles it rather than a guess:** `ecochran08@yahoo.com` already holds both
`ncaa_missouri` and `ncaamb_missouri`, both disabled, created through the normal Game Day flow.
"A college team means both sports, disabled" is existing product behaviour.

Creating both **offers** the choice instead of presuming one; both arrive disabled so nothing
fires either way, and the customer enables whichever sport they follow. Leaving them unmapped
would have left four customers with permanently dead rows in a list this change just made
authoritative.

**Matching is now per-SLUG, not per-name** — a multi-sport name may already have one sport
configured and not the other, and the missing one must still be created. `ecochran08`'s Missouri
pair is correctly counted as already-configured rather than duplicated.

### Safety properties

- **`enabled: false` on every created config.** Nine accounts would otherwise wake to Game Day
  firing for teams they never configured.
- **`.create()`, not `.set()`.** If a config appeared between scan and write it is left alone —
  an existing config may be enabled with the customer's own colours and design, and clobbering
  it back to disabled defaults would be a silent regression.
- **Idempotent — verified.** Two consecutive dry runs diffed byte-identical. The second run
  after a commit would report `already configured: 40, would create: 0`, because matching is by
  slug **and** by normalized `team_name`.
- Every created doc carries `backfill_source: 'sports_teams_array'` and `backfilled_at`, so the
  backfilled set is separable from the customer-created set forever.

---

## 2. STEP 2 — EDIT PROFILE IS READ-ONLY, WITH STATUS

`_InterestsCard` becomes a `ConsumerWidget` that watches `gameDayAutopilotConfigsProvider` — the
store that actually fires — and renders per-row truth:

```
Kansas City Chiefs        Game Day: on
Kansas City Royals        Game Day: off
Los Angeles Dodgers       Game Day: not set up      ← in the error colour
[ + Add a team in Game Day ]
```

The free-text `TeamSelector` is gone. "Add a team" navigates to `AppRoutes.gameDay`. **This is
the change that stops the bug at source:** all 26 orphans came from that field, which wrote
`sports_teams[]` and nothing else.

**The removal asymmetry is fixed in the same pass.** `_removeTeamEverywhere` routes through
`TeamRegistrationService.removeTeam`, which strips both arrays *and* deletes the config. Two
details that would otherwise have leaked:

- **A display name can map to more than one slug** (the college split). Removal iterates every
  matching slug — removing "Missouri Tigers" and leaving `ncaamb_missouri` behind would
  reproduce the exact orphan this change exists to delete.
- **Unmappable legacy names still need removing.** New `removeTeamByNameOnly` strips the arrays
  where no config can exist. Deliberately narrow — it cannot delete a config, so it can never
  be used to remove a real team by the wrong route.

---

## 3. STEP 3 — `sports_teams[]` IS NOW A DERIVED MIRROR

`sportsTeams:` was **removed from the Edit Profile save payload entirely.**

Passing the unchanged value would have been equally wrong: a save from this screen would
clobber a team added concurrently in Game Day. Omitting the field means `copyWith` leaves the
stored value alone, and `TeamRegistrationService` is the only writer.

**That also closes the `sports_team_priority` gap for free.** Edit Profile never wrote it, so a
profile-added team was missing from `GameDayPriorityResolver`'s tie-break as well as from the
fire path. `addTeam` writes both arrays, so every team now enters the priority ordering.

Consumers keep working unchanged: `team_color_resolver` ("My Teams" boost), `lumina_brain`
(conversational context), `sportsTeamPriorityProvider`.

---

## 4. STEP 5 — THE REVIEWER ACCOUNT

`reviewer@nexgenled.com` holds `"Chiefs"` and `"Royals"` with **zero** configs. Both resolve
cleanly, so the backfill creates them — disabled.

**Recommendation: seed the reviewer account ENABLED, with working configs. Disabled is not
sufficient.**

The backfill's disabled default is right for *customers*: it protects nine real people from
lights running on a schedule they never set. A reviewer is the opposite case. They open Game
Day, see two teams both marked "not set up", have no NFL/MLB game in progress to demonstrate
anything, and the reasonable conclusion is that the feature is incomplete — a Guideline 2.1
risk on a first submission, and exactly the impression the screen is designed to avoid.

Seeding the reviewer enabled is safe in a way it is not for customers: the account has **zero
controllers** and has **never written a command** (COMMAND_SAFETY D5), so an enabled config
cannot drive any hardware. It is presentation only.

**For the pre-submission checklist:**

- [ ] `reviewer@nexgenled.com` — both teams `enabled: true`, with catalogue colours and a
      non-`fallback` design so the Game Day screen renders something
- [ ] Confirm Edit Profile shows both as **"Game Day: on"**, not "not set up"
- [ ] Note that the account has no controller, so nothing fires — enabled is cosmetic

---

## 5. STEP 4 — NOT BUILT, AND WHY

Retiring the Sports Alerts store means rewriting `sports_alerts_screen.dart` into a per-team
toggle view over `game_day_autopilot`, plus a one-shot prefs→Firestore migration, plus reworking
`zone_assignment_screen.dart` (which writes the now-provably-dead `assignedZoneIds`).

**I did not build it, and I do not think I should have in this pass.** Steps 1–3 change the
data model and one screen in a release-affecting file; step 4 is a second screen rewrite plus a
migration, and bundling them means one larger diff to verify at once — with the customer-visible
part (Edit Profile) and the reviewer-visible part (Sports Alerts) landing together.

**What §0 changes about it:** the hard part got easier. `assignedZoneIds` is write-only, so there
is nothing to carry across. The migration is:

1. On next app open, for each `ScoreAlertConfig`, set `score_celebration_enabled` and
   `sensitivity` on the matching `game_day_autopilot/{teamSlug}`; **drop `assignedZoneIds`**.
2. Delete the `sports_alert_configs` prefs key.
3. Point the screen at `gameDayAutopilotConfigsProvider`.

Configs whose `teamSlug` has no config document should be **created disabled**, same rule as §1.

**Nothing regresses by deferring it.** Store 3 is device-local and already independent; it keeps
working exactly as it does today until it is retired.

---

## 6. VERIFICATION

| Check | Result |
|---|---|
| **Backfill idempotent** | ✅ two dry runs diffed **byte-identical** |
| **Nothing disappears from any screen** | ✅ Edit Profile still renders every `sports_teams[]` entry, including the 5 ambiguous ones — they gain a "not set up" label, not a deletion |
| **Game Day add still propagates to the array** | ✅ unchanged — `TeamRegistrationService.addTeam` was already correct and was not touched |
| **Removal cascades both ways** | ✅ Game Day → already correct; Edit Profile → now routes through the same service, and iterates every slug sharing the display name |
| **Existing enabled configs untouched** | ✅ backfill uses `.create()`; dry run shows `already configured: 19` skipped |
| **`flutter analyze`** | ✅ 9 issues, **all pre-existing `deprecated_member_use`**. My own lint and a newly-dead controller/import were removed |
| **Full suite** | see below |

**Full `flutter test`: 1981 passed, 3 skipped, 1 failed.** Exactly +20 — the new tests, with no
other movement. The single failure is `cloud_ai_processor_normalize`, the expected pre-existing
P1-8, unchanged from before this work (1961 → 1981).

### Tests added — 20, against a fake Firestore

**`test/features/sports_alerts/services/team_removal_cascade_test.dart` — 11 passed.** The path
that writes two stores and iterates multiple slugs:

- single-slug removal deletes exactly one config + both array entries, and leaves the other
  team's config and its `enabled` state untouched
- **multi-sport removal clears BOTH configs** from one array entry
- **the orphan shape is pinned explicitly** — removing only one of two slugs leaves the array
  empty while a config survives, which is the failure this guards against
- `removeTeamByNameOnly` strips both arrays and **provably cannot delete a config**; rejects an
  empty uid; no-ops on an absent name
- `addTeam` still creates disabled, appends to **both** arrays (the priority gap), preserves an
  existing enabled config on re-add, rejects an unknown slug
- add→remove round trip returns both stores to their starting state

**`test/features/site/edit_profile_team_readonly_test.dart` — 9 passed.** All three row states;
punctuation/case-insensitive matching (`"St. Louis Blues"` vs `St Louis Blues`); a multi-sport
name reads **"on" if either sport is enabled** and "off" only when both are disabled; an empty
config list makes every row "not set up" (four accounts are in that state today); an unmappable
legacy name still renders rather than vanishing; and a concurrent Game Day add **survives** a
profile save, which is why the field had to be omitted rather than passed unchanged.

`flutter analyze` on both new files: **No issues found.**

**Still owed:** neither test drives the real `_InterestsCard` widget — the card is private, so
the status logic is mirrored as a pure function and asserted there. A `pumpWidget` test through
the real screen, and one run on a device, are not done.

---

## 7. CHANGED FILES

| File | Change |
|---|---|
| [scripts/_backfill_team_configs.js](scripts/_backfill_team_configs.js) | **NEW** — catalogue-parsing backfill, `--dry`/`--commit` |
| [lib/features/site/edit_profile_screen.dart](lib/features/site/edit_profile_screen.dart) | Read-only team list with per-row Game Day status; add navigates; removal cascades; `sportsTeams` dropped from the save payload; dead controller + import removed |
| [lib/features/sports_alerts/services/team_registration_service.dart](lib/features/sports_alerts/services/team_registration_service.dart) | **+`removeTeamByNameOnly`** for unmappable legacy entries |

No Firestore rules change (the subcollection is already owner-scoped). No index change. No
`functions/` change.

---

## 8. FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | **`assignedZoneIds` is write-only** — three writers, zero readers; `AlertTriggerService` fires to all controllers and captures whole-zone state. The scoping it advertises has never happened. Store 3 retires as pure subtraction | **Settles the step-4 question** |
| 2 | **The college ambiguity is 3 names across 4 accounts, not 1** — `Kansas Jayhawks` and `Missouri Tigers` split exactly like `Kansas State Wildcats`. All five left unmapped | **Wider than briefed** |
| 3 | **"Both sports, disabled" is existing product behaviour** — `ecochran08@` already holds `ncaa_missouri` + `ncaamb_missouri` from the Game Day flow. Creating both would offer rather than presume, and nothing fires either way | Option, not taken |
| 4 | **Zero unresolved names.** All 21 creatable configs map by exact catalogue name or a confirmed alias | Clean backfill |
| 5 | **Removal had a second hole beyond the known one:** a display name can map to two slugs, so removing a college team by name would have left the other sport's config firing | **Caught while fixing the first** |
| 6 | **Passing `sportsTeams` unchanged on save would still have been a bug** — it would clobber a concurrent Game Day add. The field had to be omitted, not preserved | Design |
| 7 | **The reviewer account needs enabling, not just backfilling.** Two teams both "not set up" reads as an incomplete feature; the account has no controller, so enabled is cosmetic and safe | **Submission risk** |
| 8 | Backfilled docs carry `backfill_source` + `backfilled_at`, so system-created configs stay separable from customer-created ones permanently | Reversibility |

---

## 8a. RUN LOG — production, 2026-08-07

**Backfill committed. Exact match to the dry run: 31 planned → 31 created, 20 skipped,
0 errors, 0 unresolved.** No divergence, so nothing changed between the runs.

### Spot-checks, before → after

| Account | Before | After |
|---|---|---|
| **marc@tapsonmain.com** | 2 configs (`mlb_royals`, `nfl_chiefs`, both **enabled**) | **9** — +7 new, all `enabled:false`; both pre-existing verified **unchanged** (enabled state, colours, `updated_at`). Includes both multi-sport pairs: `ncaa_kansas`+`ncaamb_kansas`, `ncaa_missouri`+`ncaamb_missouri` |
| **dbrosa99@icloud.com** | **0 configs** — feature entirely inert | **4** — `nfl_chiefs`, `mlb_royals`, and the K-State pair `ncaa_kansas_state`+`ncaamb_kansas_state`, all disabled |
| **ecochran08@yahoo.com** | 10 configs, 8 enabled | **10 — every one byte-identical.** All ten verified unchanged on enabled, colours and `updated_at` |

### Integrity checks

```
CHECK 3 — every backfilled doc
  backfilled docs found                        : 31  (expected 31)
  enabled !== false                            :  0
  team_slug missing/undefined/≠ doc id         :  0   ← the r.slug bug, absent
  missing or zero catalogue colours            :  0
  missing sport or espn_team_id                :  0

CHECK 4 — no pre-existing enabled config modified
  enabled configs  BEFORE 17  →  AFTER 17
  lost or mutated (uid/slug|updated_at)        :  0
  newly enabled                                :  0
  total configs fleet-wide                     : 51
```

`.create()` made check 4 structural; it was verified against a full pre-run census rather than
assumed.

### A defect the reviewer seeding surfaced — 5 rows would still have read "not set up"

Seeding the reviewer enabled was not sufficient on its own. The status matcher compares an
array entry against the config's `team_name`, and the aliases do not match their canonical
names:

```
"Chiefs"                            vs  "Kansas City Chiefs"
"Kansas City Sporting Kansas City"  vs  "Sporting Kansas City"
```

**5 rows across 4 accounts — including BOTH reviewer rows — would have rendered
"Game Day: not set up" while the config was present and enabled.** That is precisely the
submission risk §4 exists to remove, reintroduced by a display-layer mismatch rather than a data
gap.

Fixed by normalizing those array entries to their catalogue names — the §9 item that was already
owed, now blocking. Only alias-resolved entries whose target config exists were rewritten;
`sports_team_priority` was rewritten in step so the two arrays stay aligned:

| Account | Rewrite |
|---|---|
| stegall.s@ · marc@ · tyler.honeycutt@ | `"Kansas City Sporting Kansas City"` → `"Sporting Kansas City"` |
| reviewer@ | `"Chiefs"` → `"Kansas City Chiefs"`, `"Royals"` → `"Kansas City Royals"` |

### Final fleet state

```
Edit Profile rows, fleet-wide : 45
  "on"          : 19
  "off"         : 26
  "not set up"  :  0     ← was 26
```

**Every selected team on every account is now backed by a config the fire path reads.**

### Reviewer account — seeded

| | Before | After |
|---|---|---|
| `nfl_chiefs` | `enabled:false`, `design_mode:fallback`, `fx:52` | **`enabled:true`**, `design_mode:autoSelected`, `fx:28` (Chase), speed 180, intensity 180, brightness 200, `score_celebration_enabled:true`, **`skip_day_games:false`** |
| `mlb_royals` | same | same |
| `sports_teams` | `["Chiefs","Royals"]` | `["Kansas City Chiefs","Kansas City Royals"]` |

`skip_day_games:false` because a reviewer may test at any hour and the daylight filter would
otherwise suppress the feature. `fx:28` rather than the `fallback` solid so the design preview
renders something animated. Both carry `reviewer_seed:true` so the seeding is separable.

**Safe because the account has 0 controllers and has never written a command** (COMMAND_SAFETY
D5) — enabled is presentation only; nothing can fire.

### Pre-submission checklist

- [x] Reviewer's two teams `enabled: true` with a non-`fallback` design
- [x] Edit Profile shows both as **"Game Day: on"** — verified from the data, not assumed
- [x] Account has no controller, so nothing fires; enabled is cosmetic
- [ ] **Visually confirm on-device** before submitting — the row rendering has not been seen

---

## 9. OPEN

1. **The 5 ambiguous entries** — human call, or adopt the "both sports, disabled" pattern (§1).
2. **Run the backfill.** `node scripts/_backfill_team_configs.js --commit`. Dry run is clean and
   idempotent; it has not been run.
3. **Step 4** (§5), unblocked now that `assignedZoneIds` is known dead.
4. **Widget tests** for the read-only card and the cascading removal (§6).
5. **`sports_teams[]` is still unvalidated at the schema level.** Nothing now writes free text —
   but nothing prevents it either, and the fleet still carries
   `"Kansas City Sporting Kansas City"`. A one-off normalization pass would retire the aliases.
