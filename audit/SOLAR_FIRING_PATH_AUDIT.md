# Solar Scheduling — How It Actually Fires

Read-only audit. No edits, no commits. Branch `feat/account-deletion-purge`, working tree as of 2026-08-27.

---

## TL;DR

**Authoritative mechanism: the WLED controller computes and fires solar events itself.**
The app pushes `latitude`/`longitude` into WLED's `if.ntp.lt` / `if.ntp.ln` and writes two dedicated
timer rows (`timers.ins` slot 8 = sunrise, slot 9 = sunset, `hour:255`, `min` = signed offset). Nothing
in the app, in Cloud Functions, or in the ESP32 bridge computes a sunrise/sunset moment and issues a
command at that moment.

There are **three additional solar mechanisms present**, none of which is the firing path for a user's
"Sunrise"/"Sunset" schedule:

1. A **dead legacy encoding** (`hour:24`/`hour:25`) still lives in `cfg_payload_builder.dart` and is
   still reachable from any caller that skips the solar guard, plus a one-time cleanup that exists to
   scrub it off devices.
2. An **app-computed clock substitution** in Autopilot: when the solar flag is OFF, the autopilot
   baseline resolves the real sunrise from `SunUtils` **once, at generation time**, and arms a fixed
   clock timer instead.
3. An **app-side foreground enforcement poll** (`ScheduleEnforcementService`) that evaluates
   sunrise/sunset in-app via `SunUtils` and can push state — a corrective loop, not the trigger.

Cloud Functions: **zero** solar/lat/lon references (`functions/**/*.js` — the only hit is a test
fixture, `functions/test/unit/gameDayPlanning.test.js`). ESP32 bridge: **zero** —
`esp32-bridge/src/main.cpp` contains no sunrise/sunset/lat/lon logic; it is a command-relay poller only.

---

## TASK 1 — The firing path, end to end

### 1a. The authoritative path (controller-side, WLED 0.15.1 positional solar slots)

Chain for a schedule whose `timeLabel` or `offTimeLabel` is `"Sunrise"` / `"Sunset"`:

| # | What happens | Where |
|---|---|---|
| 1 | Sync entry. `syncAll` reads the Firestore feature flag. | [schedule_sync.dart:807](lib/features/schedule/schedule_sync.dart#L807) |
| 2 | Flag source: `config/solar_scheduling`, field `enabled`, defaults **false** on any degraded state. | [solar_scheduling_feature_flag.dart:31-73](lib/features/schedule/solar_scheduling_feature_flag.dart#L31-L73) |
| 3 | Coordinate precondition — fetches the **controller's own** `if.ntp.lt`/`.ln` and requires non-null, not `(0,0)`. | [schedule_sync.dart:809-820](lib/features/schedule/schedule_sync.dart#L809-L820) |
| 4 | `solarEnabled = solarFlagOn && solarCoordsUsable`. Anything else → the a75f504 refuse. | [schedule_sync.dart:820](lib/features/schedule/schedule_sync.dart#L820) |
| 5 | Solar boundaries are **excluded** from the general clock slots 0–7. | [cfg_payload_builder.dart:198-210](lib/features/schedule/cfg_payload_builder.dart#L198-L210) |
| 6 | Cross-schedule slot resolution: exactly one sunrise + one sunset, first-wins; extras → `rejected` warnings. | [schedule_sync.dart:631-695](lib/features/schedule/schedule_sync.dart#L631-L695) |
| 7 | Solar row encoding: `{'en':1,'hour':255,'min':<offset clamped ±120>,'macro':<preset>,'dow':<mask>}`. Offset is hardcoded `0` — no offset UI exists. | [schedule_sync.dart:598-612](lib/features/schedule/schedule_sync.dart#L598-L612); offsets forced 0 at [:678](lib/features/schedule/schedule_sync.dart#L678) and [:689](lib/features/schedule/schedule_sync.dart#L689) |
| 8 | 10-slot assembly: slots 0–7 general (padded with disabled stubs), slot 8 = sunrise, slot 9 = sunset. **Slot POSITION, not the map, is what makes a row sunrise vs sunset.** | [schedule_sync.dart:701-720](lib/features/schedule/schedule_sync.dart#L701-L720); branch at [:1503-1531](lib/features/schedule/schedule_sync.dart#L1503-L1531) |
| 9 | POST `{"timers":{"ins":[...10...]}}` via `WledRepository.applyConfig` → `/json/cfg`. | [schedule_sync.dart:219](lib/features/schedule/schedule_sync.dart#L219), [:1671](lib/features/schedule/schedule_sync.dart#L1671) |
| 10 | Verify: solar rows are invisible to the clock comparator (`isRealEnabledTimer` excludes `hour==255`), so a separate `solarTimersLanded` runs; a solar-only failure reports `CfgPushOutcome.solarMismatch`. Readback is **LAN-only** (`repo is! WledService` → `null`; a relay 2xx is trusted blind). | [schedule_sync.dart:207-240](lib/features/schedule/schedule_sync.dart#L207-L240) |
| 11 | **The controller does the rest.** WLED computes sunrise/sunset from `if.ntp.lt`/`.ln` plus its NTP-synced clock and fires `macro` at that local moment. No app involvement. | firmware |

Coordinates reach the controller by two writers, both `if.ntp`:

- Install / "Re-sync Configuration": [wled_config_pusher.dart:370-420](lib/services/wled_config_pusher.dart#L370-L420) — writes `if.ntp {en,host,tz,offset:0,ampm,ln,lt}` with readback verification. Called from [wled_config_pusher.dart:196](lib/services/wled_config_pusher.dart#L196) inside `pushDefaultsForControllerType`.
- On-connect self-heal, **only when the device reads (0,0)**: [controller_defaults_healer.dart:330-334](lib/features/wled/controller_defaults_healer.dart#L330-L334) (`coordHealPayload` → `if.ntp {lt,ln}`), gated by [:243-257](lib/features/wled/controller_defaults_healer.dart#L243-L257) (`coordHealFor`: profile coords → phone position if permission already granted → skip), invoked at [:587-599](lib/features/wled/controller_defaults_healer.dart#L587-L599).

### 1b. Legacy WLED-solar path — STILL PRESENT

`buildTimerEntry` still emits the **old, dead** encoding for solar labels: `hour: 24` for sunrise,
`hour: 25` for sunset — [cfg_payload_builder.dart:141-152](lib/features/schedule/cfg_payload_builder.dart#L141-L152).
The file's own docs call this wrong ([:22](lib/features/schedule/cfg_payload_builder.dart#L22),
[:29-32](lib/features/schedule/cfg_payload_builder.dart#L29-L32)). Per
[sunrise_off_service.dart:25-27](lib/features/schedule/sunrise_off_service.dart#L25-L27): in WLED,
`hour:24` means **fire HOURLY** (match on minute only) and `hour:25` never matches the RTC at all.

Reachability today: `buildCfgPayload` skips solar schedules entirely when `solarEnabled == false`
([cfg_payload_builder.dart:198-210](lib/features/schedule/cfg_payload_builder.dart#L198-L210)) and
excludes them via `onSolar`/`offSolar` when it is true
([:212-241](lib/features/schedule/cfg_payload_builder.dart#L212-L241)) — so on the `syncAll` path the
24/25 branch is unreachable. It remains live code for any **other** caller of `buildTimerEntry`.
`parseTimeLabel` also maps both solar keywords to `00:00`
([:37-40](lib/features/schedule/cfg_payload_builder.dart#L37-L40)), a midnight trapdoor for any future
caller that skips the `isSolarLabel` guard.

Remediation for devices already carrying 24/25 rows:
[solar_schedule_cleanup.dart](lib/features/schedule/solar_schedule_cleanup.dart) — one-time, LAN-only
re-sync that overwrites stale slots with disabled stubs; the persistent flag is set only on a confirmed
sync ([:63-84](lib/features/schedule/solar_schedule_cleanup.dart#L63-L84)).

### 1c. Global sunrise-off — same controller-side mechanism, separate owner

A user-profile toggle owns **slot 8 outright**, outranking any schedule's sunrise boundary:
[sunrise_off_service.dart:77-97](lib/features/schedule/sunrise_off_service.dart#L77-L97) builds the
slot-8 entry (`macro: kSunriseOffMacro`); `syncAll` merges it at
[schedule_sync.dart:826-835](lib/features/schedule/schedule_sync.dart#L826-L835) and
[:1521](lib/features/schedule/schedule_sync.dart#L1521). `solarTimerSlots(sunriseTaken: true)` then
silently supersedes a schedule's sunrise
([schedule_sync.dart:642-646](lib/features/schedule/schedule_sync.dart#L642-L646)).
Note this branch runs the 10-slot assembly **even when `solarEnabled` is false**
([:1503](lib/features/schedule/schedule_sync.dart#L1503)) — so the sunrise-off is a controller-side
solar timer that ships independent of the solar feature flag.

### 1d. App-computed substitution (Autopilot) — a real second mechanism, flag-inverse

When the solar flag is **OFF**, the autopilot baseline does not emit a `'Sunrise'` token; it resolves
the actual next sunrise from the user's profile coords and writes a **fixed clock label**:
[autopilot_providers.dart:593-594](lib/features/autopilot/autopilot_providers.dart#L593-L594) →
`_clockSunriseLabel` at [:662-676](lib/features/autopilot/autopilot_providers.dart#L662-L676),
falling back to `06:00` when coords are unavailable. Computed **once at generation time**, then armed
as an ordinary clock timer in slots 0–7 — the controller has no idea it is solar. The ON boundary keeps
the `'Sunset'` token ([:583](lib/features/autopilot/autopilot_providers.dart#L583)).

### 1e. App-side enforcement poll — corrective, not a trigger

`ScheduleEnforcementService` polls every 2–10 min in the **foreground app**, asks
`currentScheduledActionProvider` which schedule should be active, and pushes state if the device
disagrees: [schedule_enforcement.dart:60-122](lib/features/schedule/schedule_enforcement.dart#L60-L122);
provider and auto-start at [:239-260](lib/features/schedule/schedule_enforcement.dart#L239-L260)
(default mode `soft`). Its solar resolution is app-side `SunUtils`:
[schedule_providers.dart:1196-1217](lib/features/schedule/schedule_providers.dart#L1196-L1217)
(`ScheduleFinder._parseTimeLabel`), fed profile lat/lon at
[:1235-1250](lib/features/schedule/schedule_providers.dart#L1235-L1250).
It runs only while the provider is alive; it is instantiated lazily, e.g. by the manual-override hooks
at [wled_providers.dart:1163](lib/features/wled/wled_providers.dart#L1163) and
[:1572](lib/features/wled/wled_providers.dart#L1572). The same provider also feeds the neighborhood
sync engine ([neighborhood_sync_engine.dart:900](lib/features/neighborhood/neighborhood_sync_engine.dart#L900))
and voice ([voice_providers.dart:295](lib/features/voice/voice_providers.dart#L295)).

### 1f. Ruled out

- **Cloud Functions:** grep over `functions/**/*.js` for `sunrise|sunset|solar|latitude|longitude` returns one hit, a test fixture (`functions/test/unit/gameDayPlanning.test.js`). No server-side solar scheduler exists.
- **ESP32 bridge:** grep over `esp32-bridge/src/main.cpp`, `*.h`, `platformio.ini` — no solar, no lat/lon, no time computation beyond `millis()` bookkeeping. It polls Firestore and forwards commands.
- **`{'loc':{'lat','lon'}}` POST to `/json/cfg`:** removed (F-8). `loc` is not a WLED cfg key; the write never set anything, and it did trigger the cfg deserializer that wipes colour gamma. See the comment block at [edit_profile_screen.dart:259-271](lib/features/site/edit_profile_screen.dart#L259-L271).

### Verdict

**Authoritative: WLED computes and fires (1a).** Both app-computed alternatives are conditional and
non-primary: (1d) is what runs *instead* when the controller-side path is switched off, and (1e) is a
drift-correction poll that runs only while the app is foregrounded.

**Both a legacy path and a newer app-computed path coexist with the authoritative one.** The legacy
hour:24/25 encoding (1b) is unreachable from `syncAll` but is still live code, with a live midnight
trapdoor in `parseTimeLabel`.

---

## TASK 2 — Where coordinates come from and where they go

### Source

`GeocodingService` — Google Places Autocomplete (New) primary, Photon (OSM) fallback:
[geocoding_service.dart:59-88](lib/features/schedule/geocoding_service.dart#L59-L88);
`geocode()` at [:307-340](lib/features/schedule/geocoding_service.dart#L307-L340);
`fetchPlaceLocation(placeId)` at [:248-275](lib/features/schedule/geocoding_service.dart#L248-L275).
Both entry points return `null` on failure — there is no exception to catch.

Two capture surfaces:

- **Customer, self-serve:** the address field in Edit Profile — geocoded on debounce ([edit_profile_screen.dart:305-318](lib/features/site/edit_profile_screen.dart#L305-L318)) and again on save when the address changed ([:250-253](lib/features/site/edit_profile_screen.dart#L250-L253)).
- **Installer, at install:** [customer_info_screen.dart:165-192](lib/features/installer/screens/customer_info_screen.dart#L165-L192) — coords taken straight off the selected `AddressSuggestion`, with a `fetchPlaceLocation` fallback; held in `InstallerCustomerInfo` ([installer_providers.dart:430-437](lib/features/installer/installer_providers.dart#L430-L437)).

A third, non-address source exists for the healer only: the phone's own GPS, used **only if location
permission is already granted** — [controller_defaults_healer.dart:1444-1461](lib/features/wled/controller_defaults_healer.dart#L1444-L1461).

### Destinations

| Destination | Field / path | Written by |
|---|---|---|
| **Firestore `/users/{uid}`** | `latitude`, `longitude` (validated doubles) | [edit_profile_screen.dart:255-257](lib/features/site/edit_profile_screen.dart#L255-L257); installer at [installer_setup_wizard.dart:1411-1412](lib/features/installer/installer_setup_wizard.dart#L1411-L1412). Model: [user_model.dart:107](lib/models/user_model.dart#L107), [:389](lib/models/user_model.dart#L389) (`InputValidation.validateLatitude`), [:431](lib/models/user_model.dart#L431), [:591](lib/models/user_model.dart#L591) |
| **WLED controller `/json/cfg`** | `if.ntp.lt`, `if.ntp.ln` (**rounded to 2 dp on the heal path**) | install/re-sync: [wled_config_pusher.dart:384-392](lib/services/wled_config_pusher.dart#L384-L392); heal: [controller_defaults_healer.dart:330-334](lib/features/wled/controller_defaults_healer.dart#L330-L334), rounding at [:232](lib/features/wled/controller_defaults_healer.dart#L232) and [:250-256](lib/features/wled/controller_defaults_healer.dart#L250-L256) |
| **Firestore `/installations/{id}`** | `latitude`, `longitude` | [installation_model.dart:133](lib/models/installation_model.dart#L133), [:164](lib/models/installation_model.dart#L164); written at [installer_setup_wizard.dart:1402](lib/features/installer/installer_setup_wizard.dart#L1402) |
| **Commercial account callable** | `location.lat` / `location.lng` (note `lng`, not `lon`) | [installer_setup_wizard.dart:1546-1550](lib/features/installer/installer_setup_wizard.dart#L1546-L1550) → `setAccountProfile`; model [commercial_location.dart:83-84](lib/models/commercial/commercial_location.dart#L83-L84), [:110-111](lib/models/commercial/commercial_location.dart#L110-L111) |
| **Firestore neighborhood household docs** | `latitude`, `longitude` | [neighborhood_models.dart:178](lib/features/neighborhood/neighborhood_models.dart#L178), [:198](lib/features/neighborhood/neighborhood_models.dart#L198); [neighborhood_service.dart:302](lib/features/neighborhood/neighborhood_service.dart#L302), [:1071](lib/features/neighborhood/neighborhood_service.dart#L1071) |
| **Firestore `/users/{uid}/properties`** | `latitude`, `longitude` (geofence centre) | [property_models.dart:177](lib/features/properties/property_models.dart#L177), [:186](lib/features/properties/property_models.dart#L186) |
| **Local cache (SharedPreferences), Game Day background isolate** | `latitude`, `longitude` in the persisted background config | [game_day_background_persistence.dart:326-342](lib/features/autopilot/game_day_background_persistence.dart#L326-L342) |
| **In-memory only** | sun-time display strings, autopilot generation, geofence dusk logic | [sun_time_provider.dart:30-40](lib/features/schedule/sun_time_provider.dart#L30-L40), [autopilot_providers.dart:449-457](lib/features/autopilot/autopilot_providers.dart#L449-L457), [geofence_monitor.dart:272](lib/features/geofence/geofence_monitor.dart#L272), [calendar_providers.dart:728-729](lib/features/schedule/calendar_providers.dart#L728-L729) |

**No Cloud Function consumes coordinates for scheduling.** The only server-side coordinate consumer is
`setAccountProfile` storing a commercial location record.

### The gap that matters for Task 4

The Edit Profile save path writes lat/lon to Firestore and **deliberately does not push them to the
controller** ([edit_profile_screen.dart:259-271](lib/features/site/edit_profile_screen.dart#L259-L271)).
The comment says the healer covers it. But `coordHealFor` only fires when the device reads **exactly
(0,0)** ([controller_defaults_healer.dart:243-248](lib/features/wled/controller_defaults_healer.dart#L243-L248);
predicate at [clock_health.dart:351-355](lib/features/wled/clock_health.dart#L351-L355)). A controller
already holding the **old address's** coordinates is not `(0,0)`, so the healer skips it. Nothing on the
customer-facing move-house path re-pushes `if.ntp.lt`/`.ln`. The only writer that overwrites non-zero
coords is `pushTimeLocation`, reachable from install and the installer-facing "Re-sync Configuration"
action ([controller_setup_screen.dart:1350-1356](lib/features/installer/screens/controller_setup_screen.dart#L1350-L1356)).

---

## TASK 3 — "Solar Sync Complete" on geocode failure

**CONFIRMED — still present in current code. Not fixed since the overnight privacy audit.**

[edit_profile_screen.dart:182-296](lib/features/site/edit_profile_screen.dart#L182-L296), specifically:

- [:250](lib/features/site/edit_profile_screen.dart#L250) — `final result = await geocoder.geocode(address);`
- [:251](lib/features/site/edit_profile_screen.dart#L251) — `if (result != null) { ... }`
- [:280-282](lib/features/site/edit_profile_screen.dart#L280-L282) — the else branch is a bare
  `debugPrint('EditProfile: Geocoding failed for address');` and nothing else. No state, no rethrow, no flag.
- [:284-287](lib/features/site/edit_profile_screen.dart#L284-L287) — the **unconditional** green snackbar
  `'Profile Updated & Solar Sync Complete.'`, sitting outside the `if (addressChanged)` block entirely.

So there are actually **two** ways to reach a false "Solar Sync Complete":

1. **Geocode returned null** — the address is saved, `latitude`/`longitude` keep their previous values,
   and the user is told solar sync completed. This is the audited defect.
2. **Address unchanged** (`addressChanged == false`, [:193](lib/features/site/edit_profile_screen.dart#L193)) —
   no geocode is even attempted, yet the same "Solar Sync Complete" fires. The copy claims a solar sync
   on every profile save, including a pure vibe-level change.

`debugPrint` is the only signal, and it is release-silenced. Per `project_crash_reporting_posture`, that
means this failure leaves no durable trace anywhere.

Independently, the message is **misleading even on the success path**: nothing in that block syncs
anything solar to a controller. Coordinates go to Firestore
([:255-257](lib/features/site/edit_profile_screen.dart#L255-L257)) and the only "solar" work is a
`debugPrint` of the computed times ([:273-278](lib/features/site/edit_profile_screen.dart#L273-L278)).
The controller push was removed at F-8. "Solar Sync Complete" describes an operation this screen no
longer performs in any branch.

The debounced sibling has the same swallow — `if (res == null) return;` with no user-visible signal:
[edit_profile_screen.dart:313-314](lib/features/site/edit_profile_screen.dart#L313-L314).

---

## TASK 4 — Consequence of wrong or stale coordinates

The answer depends on which mechanism is live, and the mechanisms degrade **differently**.

### A. Solar flag ON + controller holds stale coords (the move-house case)

The controller has valid, non-`(0,0)` coordinates — just the wrong ones. So:

- `solarCoordsUsable` passes ([schedule_sync.dart:815-816](lib/features/schedule/schedule_sync.dart#L815-L816)) — the gate only rejects `(0,0)`, never "implausible" or "disagrees with the profile."
- Slots 8/9 are written and verified green. `CfgPushOutcome.confirmed`.
- `ClockHealthIssue.locationUnset` is **not** raised — that predicate is also `lat==0 && lon==0` ([clock_health.dart:351-355](lib/features/wled/clock_health.dart#L351-L355)).

**Observable symptom:** the lights fire at the *old address's* sunrise/sunset, every day, silently.
Every layer reports success — the app UI, the cfg readback verify, and the clock-health banner.
Magnitude is longitude- and latitude-dependent: roughly 4 minutes of error per degree of longitude, plus
a seasonal term from latitude. A cross-country move (~35° longitude) is roughly a **2h20m** offset —
lights coming on mid-afternoon, or hours after dark. A cross-town move is invisible. **There is no
detector for this class anywhere in the codebase.** Nothing compares `if.ntp.lt/.ln` against
`UserModel.latitude/longitude`; the healer's readback check only asks whether the device is still at
`(0,0)` ([controller_defaults_healer.dart:1261-1264](lib/features/wled/controller_defaults_healer.dart#L1261-L1264)).

### B. Solar flag ON + controller at (0,0)

`solarCoordsUsable` is false → `solarEnabled` false → every solar boundary is **refused and warned**,
not armed ([cfg_payload_builder.dart:200-208](lib/features/schedule/cfg_payload_builder.dart#L200-L208),
[schedule_sync.dart:1406](lib/features/schedule/schedule_sync.dart#L1406)).

**Observable symptom:** the lights simply never fire on that boundary. The user gets a warning, and the
clock-health banner surfaces `locationUnset` — but only when a solar schedule exists (`solarRelevant`,
[clock_health.dart:370-382](lib/features/wled/clock_health.dart#L370-L382)); copy at
[:396-398](lib/features/wled/clock_health.dart#L396-L398). This is the loud, correct degradation.

### C. Solar flag OFF (the shipped production default per the flag's own doc)

Solar boundaries are refused in `syncAll`, and the UI defends against minting new ones
([my_schedule_page.dart:3947](lib/features/schedule/my_schedule_page.dart#L3947),
[:4048](lib/features/schedule/my_schedule_page.dart#L4048)), as do the AI
([lumina_brain.dart:325-331](lib/features/ai/lumina_brain.dart#L325-L331)) and Autopilot
([autopilot_providers.dart:641-647](lib/features/autopilot/autopilot_providers.dart#L641-L647)).
The controller's coordinates are then **irrelevant to firing** — but the **profile's** coordinates are
not: `_clockSunriseLabel` bakes a clock time from them
([autopilot_providers.dart:662-676](lib/features/autopilot/autopilot_providers.dart#L662-L676)).

**Observable symptom of stale profile coords here:** the autopilot OFF boundary is a *frozen wrong clock
time*. It is frozen twice over — even with correct coordinates it does not track the seasonal drift of
sunrise, because it is resolved once at generation and armed as a fixed clock timer. With no coords at
all it silently becomes `06:00`. Nothing in the schedule UI marks that time as derived; it reads as a
time the user chose.

### D. App-side enforcement (`ScheduleEnforcementService`)

Uses **profile** coords via `ScheduleFinder`. Stale coords shift the computed on/off window, so the poll
can conclude the wrong schedule is "currently active" and push that state — but only while the app is
foregrounded and the provider is alive, and only outside the grace/rate windows
([schedule_enforcement.dart:94-115](lib/features/schedule/schedule_enforcement.dart#L94-L115)).

**Observable symptom:** an intermittent, app-presence-correlated state correction near the boundary —
lights snapping on or off within ~10 minutes of opening the app, near dawn or dusk, with no
corresponding controller timer.

### E. Cross-mechanism divergence

A, C, and D read **different coordinate stores**: the controller reads `if.ntp`, while autopilot and
enforcement read the Firestore profile. Edit Profile updates the profile but not the controller. So after
an address change, C and D immediately track the new location while A keeps firing on the old one — the
same house can be operating on two different sets of coordinates simultaneously, with no surface that
shows the disagreement.

### F. Remote (off-LAN) writes

The solar coord precondition needs `fetchClockInfo`; `CloudRelayRepository` does implement
`ClockInfoSource` ([cloud_relay_repository.dart:35](lib/features/wled/cloud_relay_repository.dart#L35)),
so the gate can evaluate off-LAN. But the cfg **readback** is LAN-only — `repo is! WledService` returns
`null` and a relay 2xx is trusted blind
([schedule_sync.dart:207-208](lib/features/schedule/schedule_sync.dart#L207-L208),
[:246-249](lib/features/schedule/schedule_sync.dart#L246-L249)). Combined with the known relay
`applyConfig` misroute (memory `project_relay_applyconfig_misroute`: app-side fixed at `5b285af`,
firmware still owed), a solar arm attempted over the relay reports confirmed on a 2xx that may never have
reached the controller.

**Observable symptom:** the UI says armed, nothing ever fires, and no readback contradicts it.

---

## UNKNOWNS

1. **Is `config/solar_scheduling.enabled` currently true in production?** Not determinable from the repo.
   Memory (`project_solar_schedules_never_fire`, corrected 2026-08-24) records the rule at
   `firestore.rules:1632` existing with `enabled:true`, but that is a recollection of a live Firestore
   value, not code. Per `feedback_verify_with_client_credential`, confirming it needs a **client**
   credential read. Everything in Task 4 branches on this.
2. **Has WLED 0.15.1 been observed firing at real sunrise/sunset on hardware?** The flag doc states a
   bench gate requiring exactly that, with a nonzero offset
   ([solar_scheduling_feature_flag.dart:11-16](lib/features/schedule/solar_scheduling_feature_flag.dart#L11-L16)).
   No artifact in `audit/` records the gate being satisfied. Whether the slot 8/9 positional encoding
   actually fires on the pinned firmware is unresolved.
3. **Is the `min` field on a `hour:255` row a signed offset in the pinned firmware?** Asserted in comments
   ([sunrise_off_service.dart:21-23](lib/features/schedule/sunrise_off_service.dart#L21-L23)) and clamped
   to ±120 ([schedule_sync.dart:337](lib/features/schedule/schedule_sync.dart#L337)), but it is always
   written as `0`, so the assertion has never been exercised.
4. **Does WLED tolerate a >8-entry `timers.ins` array?** The 10-slot assembly assumes yes;
   `kWledTotalTimerSlots = 10` ([schedule_sync.dart:327-328](lib/features/schedule/schedule_sync.dart#L327-L328))
   is asserted, not cited to firmware source in-repo. Note the readback is compacted
   (`project_wled_cfg_readback_is_compacted`), so array index ≠ device slot on the way back —
   `sunrise_off_service` classifies by the `hour==255` marker rather than position
   ([:304-326](lib/features/schedule/sunrise_off_service.dart#L304-L326)), but `assembleSolarAwareIns`
   writes positionally. Whether the write side needs the same treatment is unverified.
5. **Does anything still call `buildTimerEntry` with a solar label?** Only `buildCfgPayload` was traced in
   `lib/`. The bench harness (`bench/`) imports the same pure module and was not swept.
6. **Was the one-time `solar_schedule_cleanup` ever run against the fleet?** The pure function is present
   and testable; its Firestore/SharedPreferences wiring, and whether any account has the persistent flag
   set, were not traced.
7. **Timezone correctness is out of scope here but is coupled.** WLED's solar computation needs both coords
   and a correct `if.ntp.tz`. `pushTimeLocation` sends `offset: 0` deliberately
   ([wled_config_pusher.dart:366-368](lib/services/wled_config_pusher.dart#L366-L368)) while `tzHealPayload`
   can send `tz: UTC + offset`
   ([controller_defaults_healer.dart:319-328](lib/features/wled/controller_defaults_healer.dart#L319-L328)).
   Whether these two writers can leave a device in a contradictory tz state was not analysed.
