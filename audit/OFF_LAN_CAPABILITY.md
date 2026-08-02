# OFF-LAN CAPABILITY — what the bridge carries, what it doesn't, and what that costs

**Date:** 2026-07-30 · **Branch:** `main` @ `c20ed83` (2.5.10+59) · **Method:** static read of
`lib/`, `functions/`, `esp32-bridge/`, `firestore.rules`, `docs/`, plus the bench artifacts under
[audit/verification_evidence/](audit/verification_evidence), plus one live read-only Firestore GET
(`config/calendar_leases`, §2.4). **No device was driven.** Anything not determinable from code is
marked **UNVERIFIED** rather than inferred.

**Bottom line for R-1.** The claim *"schedules fire when you set them"* is true **on the home
network**. Off-LAN it is false and the app says so honestly on the Schedule surface — but the
mechanism it promises ("will arm next time you're on your home WiFi") **does not exist as an
automatic behaviour**; it requires the user to press Sync or edit a schedule while home. R-1 needs a
qualifier. Details in Part 2.

---

## PART 1 — THE SPLIT

### 1.1 What the bridge actually relays

The bridge's entire command vocabulary is three branches in one `if/else`
([main.cpp:815-825](esp32-bridge/src/main.cpp#L815-L825)):

| Command `type` in the Firestore doc | What the bridge does |
|---|---|
| `getState` | `GET http://<ip>/json/state` |
| `getInfo` | `GET http://<ip>/json/info` |
| `ping` | acknowledged locally, no WLED request ([:788-794](esp32-bridge/src/main.cpp#L788-L794)) |
| **everything else** | `POST http://<ip>/json/state` with the doc's payload |

There is no `applyConfig` case, no `/json/cfg`, no `/presets.json`, no `/edit` (LED-map upload), no
`/json/si`. **The bridge relays exactly one payload class: WLED live-state JSON documents.** The
payload arrives as a JSON string and is forwarded verbatim
([main.cpp:852-858](esp32-bridge/src/main.cpp#L852-L858); the app encodes it as a string at
[remote_command.dart:97](lib/models/remote_command.dart#L97)), so nesting is not a transport
constraint — the missing endpoint is.

The webhook (DIY) relay is **not** limited the same way. The Cloud Function has a real cfg case:
`case "applyConfig": endpoint = ${baseUrl}/json/cfg`
([functions/index.js:404-405](functions/index.js#L404-L405)). In Bridge Mode the function
deliberately does nothing and lets the ESP32 pick the command up
([functions/index.js:340-341](functions/index.js#L340-L341)).

### 1.2 The definitive table

Repository selection: home WiFi → `WledService` (direct HTTP);
remote → `CloudRelayRepository`; no network → `null` (no repo at all)
([wled_providers.dart:139-235](lib/features/wled/wled_providers.dart#L139-L235)).

| User-visible operation | Transport | Bridge mode | Webhook mode | LAN |
|---|---|---|---|---|
| Power on/off, brightness, colour | `/json/state` | ✅ | ✅ | ✅ |
| Per-channel power | `/json/state` ([wled_providers.dart:1090](lib/features/wled/wled_providers.dart#L1090)) | ✅ | ✅ | ✅ |
| Apply pattern / effect / palette | `/json/state` | ✅ | ✅ | ✅ |
| Load a preset ("Run Schedule", quick presets) | `/json/state` `{ps:N}` ([:623-626](lib/features/wled/cloud_relay_repository.dart#L623-L626)) | ✅ | ✅ | ✅ |
| Save a preset / save a design | `/json/state` `{…,psave:N}` ([:601-620](lib/features/wled/cloud_relay_repository.dart#L601-L620)) | ✅ | ✅ | ✅ |
| Design Studio per-pixel paint | chunked `/json/state` `i[]` ([:388-403](lib/features/wled/cloud_relay_repository.dart#L388-L403)) | ✅ (serialized, slow) | ✅ | ✅ |
| Rename channel / segment | `/json/state` | ✅ | ✅ | ✅ |
| DDP / UDP sync enable | `/json/state` `udpn`,`ddp` ([:456-474](lib/features/wled/cloud_relay_repository.dart#L456-L474)) | ✅ | ✅ | ✅ |
| Read live state / device info | `/json/state`, `/json/info` | ✅ | ✅ | ✅ |
| **Arm a schedule (timers)** | **`/json/cfg`** | ❌ **throws** | ✅ | ✅ |
| **Arm a calendar/lease entry** | **`/json/cfg`** | ❌ deferred | ✅ | ✅ |
| **Global sunrise-off toggle** | **`/json/cfg`** ([sunrise_off_service.dart:167-169](lib/features/schedule/sunrise_off_service.dart#L167-L169)) | ❌ deferred | ✅ | ✅ |
| **Solar stale-timer cleanup** | **`/json/cfg`** ([schedule_providers.dart:258-264](lib/features/schedule/schedule_providers.dart#L258-L264)) | ❌ deferred | ✅ | ✅ |
| **LED hardware config (bus/segment layout)** | **`/json/cfg`** ([hardware_config_screen.dart:300,358](lib/features/wled/hardware_config_screen.dart#L300)) | ❌ refused | ✅ | ✅ |
| **Controller-defaults self-heal (NTP/tz/coords/gamma/presets)** | **`/json/cfg`** + reads | ❌ no-op | ❌ no-op¹ | ✅ |
| Read hardware config | `getConfig()` returns `null` on relay ([:477](lib/features/wled/cloud_relay_repository.dart#L477)) | ❌ | ❌ | ✅ |
| Read preset names | `fetchPresetNames()` returns `{}` on relay ([:568](lib/features/wled/cloud_relay_repository.dart#L568)) | ❌ | ❌ | ✅ |
| LED-map (2D) upload | returns `false` unconditionally ([:449-453](lib/features/wled/cloud_relay_repository.dart#L449-L453)) | ❌ | ❌ | ✅ |
| Timezone / coordinate clock checks | needs `/json/cfg` read; skipped on relay ([:484-489](lib/features/wled/cloud_relay_repository.dart#L484-L489)) | ❌ | ❌ | ✅ |
| BLE provisioning / Wi-Fi setup | BLE | ❌ | ❌ | ✅ (physical proximity) |

¹ The healer is gated on the repo being a `WledService`, not on `repoCanWriteCfg`
([controller_defaults_healer.dart:456-461](lib/features/wled/controller_defaults_healer.dart#L456-L461),
[:703-721](lib/features/wled/controller_defaults_healer.dart#L703-L721)) — so it is inert in
**both** remote modes, including webhook mode where the cfg write would in fact land. Deliberate:
the class heals only what it can first *read*, and `getConfig()` is null on any relay.

### 1.3 Which constraint is it? — **three, stacked**

1. **Bridge firmware dispatch limit (the root).** [main.cpp:815-825](esp32-bridge/src/main.cpp#L815-L825).
   No cfg endpoint exists in the firmware at all. This is the only one that has to change for
   bridge-mode cfg to work.
2. **App-side routing decision (derived, deliberate).** `supportsCfgWrites` is literally
   `webhookUrl.isNotEmpty` ([cloud_relay_repository.dart:419](lib/features/wled/cloud_relay_repository.dart#L419)) —
   the app mirrors the same test the Cloud Function uses to decide who executes. `applyConfig`
   **throws** `CfgWriteUnsupportedException` rather than returning `false`, because false reads as
   "retry" ([:436-446](lib/features/wled/cloud_relay_repository.dart#L436-L446)), and every cfg
   caller pre-flights `repoCanWriteCfg` ([:651-652](lib/features/wled/cloud_relay_repository.dart#L651-L652)).
   This is a *response* to constraint 1, not an independent one — and the commentary at
   [:421-435](lib/features/wled/cloud_relay_repository.dart#L421-L435) records that before this
   guard existed, **every off-LAN cfg write since the bridge shipped reported success while changing
   nothing.**
3. **Independent app-side gaps, unrelated to the bridge.** `uploadLedMapJson` returns `false` on the
   relay by choice; `getConfig`/`fetchPresetNames` return null/empty. These would still fail on a
   cfg-capable bridge unless separately implemented.

**Not a WLED firmware limit.** WLED serves `/json/cfg` over ordinary LAN HTTP; the webhook relay
reaches it today ([functions/index.js:404-405](functions/index.js#L404-L405)).

### 1.4 Does the documentation match the code? — **YES, with one false promise**

[docs/ESP32_Bridge_Setup_Guide.md:67](docs/ESP32_Bridge_Setup_Guide.md#L67):

> **What the bridge does and doesn't carry.** Remote commands cover the things you'd reach for while
> away — power, brightness, colors, patterns, and scenes. **Schedule (timer) configuration is a
> local-network write only.** Creating or editing a schedule while you're away saves it to your
> account, but it does not arm on the controller until the app is back on your home Wi-Fi. **Open
> the Schedule tab once when you get home and it syncs itself.**

The first three sentences are **accurate and match the code exactly**. The final sentence is
**wrong**: opening the Schedule tab triggers no sync. `_MySchedulePageState.initState`
([my_schedule_page.dart:110](lib/features/schedule/my_schedule_page.dart#L110)) starts no sync; the
only sync entry points are the debounced mutation hook
([schedule_providers.dart:132-135](lib/features/schedule/schedule_providers.dart#L132-L135)) and the
explicit **Sync** button ([my_schedule_page.dart:259](lib/features/schedule/my_schedule_page.dart#L259)).
The doc should say *press Sync*, not *open the tab*. Same wording defect in the in-app copy — see 2.2.

---

## PART 2 — THE FAILURE UX

### 2.1 What actually happens when a customer sets a schedule off-LAN

Trace, in order, through `ScheduleSyncService.syncAll`
([schedule_sync.dart:626](lib/features/schedule/schedule_sync.dart#L626)):

1. **Firestore write succeeds.** The schedule is saved to the account normally; the WLED sync is
   fire-and-forget and never blocks it
   ([schedule_providers.dart:127-135](lib/features/schedule/schedule_providers.dart#L127-L135)).
2. **Presets DO get written.** `savePreset` is `/json/state`, so preset slots 1/3/4/5 (system),
   2 (off) and 10-25 (schedule designs) are psaved *over the bridge*, one Firestore command
   round-trip each, serialized, 45 s timeout apiece
   ([cloud_relay_repository.dart:55](lib/features/wled/cloud_relay_repository.dart#L55)). Note the
   relay is treated as "presets unknown" and therefore **always writes**
   ([schedule_sync.dart:728-730](lib/features/schedule/schedule_sync.dart#L728-L730)) — an off-LAN
   Sync is slow but it *does* heal the ON-preset `ib` shape. That is a real (undocumented) benefit.
3. **The cfg pre-flight refuses before spending a round-trip.** `if (!repoCanWriteCfg(repo))` →
   `ScheduleSyncResult.deferredOffLan(...)`
   ([schedule_sync.dart:1216-1223](lib/features/schedule/schedule_sync.dart#L1216-L1223)), with the
   `CfgWriteUnsupportedException` catch as backstop
   ([:1263-1271](lib/features/schedule/schedule_sync.dart#L1263-L1271)).

**Answer: Firestore-only write.** Not a silent no-op, not a throw at the UI, not a queue. The
timers never reach the controller and no retry is recorded anywhere.

### 2.2 What the UI tells them — **and is this a third false-success?**

**No. The schedule path is the codebase's honest one.** It is the counter-example to F-5 and F-8,
not another instance:

- `deferredOffLan` is a **distinct branch** from both success and failure, handled before the
  `!success` branch in both the snackbar
  ([my_schedule_page.dart:272-281](lib/features/schedule/my_schedule_page.dart#L272-L281)) and the
  persistent status row ([:708-713](lib/features/schedule/my_schedule_page.dart#L708-L713)).
- It renders **cyan with a `home_outlined` icon**, explicitly not red and explicitly not the green
  check.
- Copy: *"Saved — your schedule will arm next time you're on your home WiFi."*
  ([schedule_sync.dart:1544-1545](lib/features/schedule/schedule_sync.dart#L1544-L1545)).

Compare the two known instances: F-5 advances the pixel-walk wizard on a discarded save
([VERIFICATION_REPORT.md:294](audit/VERIFICATION_REPORT.md#L294)); F-8 shows a green *"Profile
Updated & Solar Sync Complete."* at
[edit_profile_screen.dart:236-239](lib/features/site/edit_profile_screen.dart#L236-L239)
**including on the off-LAN branch that skipped the push entirely**
([:215-219](lib/features/site/edit_profile_screen.dart#L215-L219)). Note that F-8 *is itself an
off-LAN false success* — so the pattern does exist in this domain, just not in the schedule path.

**However, the schedule copy contains a promise the code does not keep** — see 2.3. It is not a
false *success*; it is a false *assurance about the future*. That still needs fixing before it goes
into customer material.

Other cfg surfaces, for completeness — all honest:
- Sunrise-off: *"Saved, but your controller can only be updated on your home Wi-Fi. Open the app
  there to finish."* ([settings_page.dart:1227-1229](lib/features/site/settings_page.dart#L1227-L1229)) —
  and this one is **accurate**, because the sunrise-off writer is re-driven by every schedule sync.
- LED hardware config: refuses up front with *"LED hardware settings can only be changed on your
  home WiFi."* ([hardware_config_screen.dart:248-259](lib/features/wled/hardware_config_screen.dart#L248-L259)).

### 2.3 Does it arm later, automatically? — **NO, for ordinary schedules**

This is the material finding of Part 2. There are exactly two automatic sync triggers, and neither
covers the case:

| Trigger | Code | Fires on LAN return? |
|---|---|---|
| Debounced sync after a **schedule mutation** | [schedule_providers.dart:132-135](lib/features/schedule/schedule_providers.dart#L132-L135), called from the 7 mutation paths ([:541,600,714,748,788,823,906](lib/features/schedule/schedule_providers.dart#L541)) | Only if the user edits a schedule again |
| Deferred-hydration re-run | [schedule_providers.dart:214-219](lib/features/schedule/schedule_providers.dart#L214-L219) | No — only when a sync was requested *before* the stream loaded, within the same session |
| **LAN-connect listener** | [schedule_providers.dart:229-233](lib/features/schedule/schedule_providers.dart#L229-L233) | **Calls `maybeRunSolarCleanup()` only** |

The LAN-connect listener exists and is correctly wired to `repoCanWriteCfg`, but it runs the
**solar cleanup**, which short-circuits on `if (!scheduleListHasSolar(state)) return`
([schedule_providers.dart:252](lib/features/schedule/schedule_providers.dart#L252)) — and once it
succeeds it latches a per-account SharedPreferences flag and never runs again
([:254-270](lib/features/schedule/schedule_providers.dart#L254-L270)). So:

- **An account with no solar schedules: nothing happens on LAN return. Ever.**
- **An account with solar schedules: one cleanup runs, once, per account lifetime.**

There is no auto-sync on app launch, no auto-sync on Schedule-tab mount, no persisted "dirty"
marker. `lastScheduleSyncResultProvider` is in-memory, so after an app restart even the cyan status
row is gone and nothing reminds the user.

**Is the schedule permanently orphaned in Firestore, disagreeing with the device?** Yes — until the
user either presses **Sync** or makes any schedule edit while on home Wi-Fi. Both are plausible
(the button is on the Schedule page and edits are common), so this is a *latent* divergence rather
than a guaranteed permanent one. But it is not automatic, and the in-app copy and the setup guide
both tell the customer it is.

**Recommended minimum fix (not implemented, per scope):** widen the existing
[schedule_providers.dart:229-233](lib/features/schedule/schedule_providers.dart#L229-L233) listener
to also run a plain `runSyncNow()` when a session has recorded a `deferredOffLan` result. The
listener, the guard, and the in-flight lock all already exist; this is small.

### 2.4 The calendar / lease path — **materially worse**

Different mechanism, different outcome, and it *is* a false-success:

1. **The lease is recorded as armed when it was not.** Off-LAN, `_writeLeaseToWled` returns
   `_WriteAttempt.cfgUnsupported` before touching the controller
   ([calendar_entry_lease_manager.dart:1073-1079](lib/features/schedule/calendar_entry_lease_manager.dart#L1073-L1079)),
   and the caller **keeps the lease in the registry and returns `LeaseResult.leased`**
   ([:636-643](lib/features/schedule/calendar_entry_lease_manager.dart#L636-L643)). The
   `CalendarEntryLease` model has **no armed/unarmed field** ([:287-341](lib/features/schedule/calendar_entry_lease_manager.dart#L287-L341)),
   so a deferred lease is indistinguishable from a live one thereafter.
2. **The retry the comments promise does not exist.** [:1076](lib/features/schedule/calendar_entry_lease_manager.dart#L1076)
   says *"Lease kept; next on-LAN sweep arms it."* The sweep's promotion loop **skips any dateKey
   already in the registry**: `if (_activeLeases.containsKey(entry.dateKey)) continue;`
   ([:793](lib/features/schedule/calendar_entry_lease_manager.dart#L793)). Because step 1 kept the
   record, the sweep will never re-arm it. The same false comment appears for the `noRepo` branch
   ([:1064-1067](lib/features/schedule/calendar_entry_lease_manager.dart#L1064-L1067)) and the
   `flagOff` branch ([:1052-1059](lib/features/schedule/calendar_entry_lease_manager.dart#L1052-L1059)).
   Only a *re-save of the same entry* (which takes the `existing != null` update path at
   [:553-591](lib/features/schedule/calendar_entry_lease_manager.dart#L553-L591)) recovers it.
   **This is the exact bug class the `cfgWriteFailed` rollback at
   [:620-635](lib/features/schedule/calendar_entry_lease_manager.dart#L620-L635) was written to
   kill — the off-LAN branch was left on the wrong side of it.**
3. **Nothing is surfaced to the user at any level.** `applyEntries` inspects the outcome only for
   `noFreeSlots` (which opens the eviction dialog); every other outcome is a `debugPrint`
   ([calendar_providers.dart:254-272](lib/features/schedule/calendar_providers.dart#L254-L272)).
   The entry appears on the calendar as normal. **That is a third instance of the false-success
   pattern** — quieter than F-5/F-8 (no green toast), which arguably makes it worse: there is not
   even a wrong message to disbelieve.
4. **The expiry sweep can orphan a timer on the device.** `sweepExpiredLeases` removes the registry
   record and then calls `_writeZeroedSlot`, **ignoring its return value**
   ([:719-729](lib/features/schedule/calendar_entry_lease_manager.dart#L719-L729)); off-LAN that
   call returns `false` without writing
   ([:1157-1163](lib/features/schedule/calendar_entry_lease_manager.dart#L1157-L1163)). The record
   is gone, the timer is not. Nothing will ever clear it.
5. **And an orphaned lease timer is not a one-shot.** A lease's dow is a *single weekday bit*
   ([:999-1003](lib/features/schedule/calendar_entry_lease_manager.dart#L999-L1003) →
   [wled_dow.dart:45-59](lib/features/wled/wled_dow.dart#L45-L59)), and the app never writes WLED's
   `start`/`end` month-day fields — the bench readback shows the firmware defaulting them to
   `{mon:1,day:1}`–`{mon:12,day:31}`
   ([post_session_cfg.json](audit/verification_evidence/post_session_cfg.json): `{'en':1,'hour':19,
   'min':10,'macro':27,'dow':16,'start':{'mon':1,'day':1},'end':{'mon':12,'day':31}}`). So a
   "single-date" Christmas lease that is never swept fires **every Friday for a year**.

**There is no mitigating flag. §2.4 is live.** Lease writes are gated behind
`config/calendar_leases.liveWritesEnabled`, whose *code* default is false
([calendar_lease_feature_flag.dart:56-63](lib/features/schedule/calendar_lease_feature_flag.dart#L56-L63)).
Its **production value is `true`**, set 2026-05-19 and unchanged since — read live from Firestore
2026-07-30:

```
$ curl -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    "https://firestore.googleapis.com/v1/projects/icrt6menwsv2d8all8oijs021b06s5/databases/(default)/documents/config/calendar_leases"
{ "fields": {
    "liveWritesEnabled": { "booleanValue": true },
    "lastModified":      { "timestampValue": "2026-05-19T20:51:41.774Z" },
    "modifiedBy":        { "stringValue": "system_bootstrap" } },
  "updateTime": "2026-05-19T21:05:31.935062Z" }
```

So lease writes have been reaching live controllers for roughly ten weeks, and every defect in
§2.4 is in production today.

---

## PART 3 — HEALER REACH

### 3.1 Can a bridge-paired customer go weeks without an on-LAN connect? — **Yes, easily**

The healer fires from one listener, on a *new controller endpoint* transition
([wled_providers.dart:517-521](lib/features/wled/wled_providers.dart#L517-L521),
[controller_defaults_healer.dart:703-721](lib/features/wled/controller_defaults_healer.dart#L703-L721)),
and its cfg work is gated on the repo being a direct `WledService`
([:456-461](lib/features/wled/controller_defaults_healer.dart#L456-L461)). That requires **all
three** of: the app open, the phone on Wi-Fi, and that Wi-Fi matching the stored home-SSID hash
([connectivity_service.dart:238-269](lib/services/connectivity_service.dart#L238-L269)).

The entire value proposition sold to a bridge customer is that they never need to be home
([ESP32_Bridge_Setup_Guide.md:54](docs/ESP32_Bridge_Setup_Guide.md#L54)). A customer who controls
lights from the driveway on cell data, or from a phone that stays on cellular indoors, satisfies
none of the three. **Weeks is entirely plausible; indefinitely is possible.**

One partial mitigation, worth knowing: if the account has **no home SSID configured**, or the SSID
can't be read (Android location permission denied, iOS Core Location dormant),
`isOnHomeNetwork` returns **true** — assume-local
([connectivity_service.dart:169-196](lib/services/connectivity_service.dart#L169-L196)). Those
accounts get classified `local` on *any* Wi-Fi, so they attempt cfg writes (and the healer runs)
more often than a correctly-configured account — succeeding at home, failing loudly elsewhere.

### 3.2 Is there any trigger forcing an on-LAN sync? — **No. It is purely incidental**

Grepped every caller: nothing schedules, nudges, notifies, or geofence-triggers an on-LAN
reconciliation. No local notification, no push, no "you're home, syncing…" path. The gamma watchdog
is the only periodic device-touching loop and it is explicitly LAN-only and no-ops on relay
([controller_defaults_healer.dart:760-770](lib/features/wled/controller_defaults_healer.dart#L760-L770)).

### 3.3 If a controller is never reached, does anything surface? — **No**

The healer's entire output is a `HealReport` of booleans and a log list, consumed only by
`debugPrint`. There is **no Firestore write, no analytics event, no fleet telemetry** anywhere in
[controller_defaults_healer.dart](lib/features/wled/controller_defaults_healer.dart). The customer
sees nothing. Tyler sees nothing.

What *does* reach the cloud is bridge liveness only — `/users/{uid}/bridge_status/current` and
`/bridge_registry/{deviceId}` heartbeats every 30 s
([main.cpp:983-1024](esp32-bridge/src/main.cpp#L983-L1024),
[:1122-1178](esp32-bridge/src/main.cpp#L1122-L1178)). A bridge can be perfectly green while the
controller behind it has unhealed presets, a dead NTP host, and stale timers. **There is no
controller-health signal in the fleet at all.** It stays silently broken indefinitely.

### 3.4 Stale lease presets — **CAN A PRE-`b97f793` LEASE STILL FIRE DARK BEFORE IT EXPIRES?**

**Yes. Explicitly yes, and nothing in the codebase heals it.** Four independent facts:

1. **The healer does not own presets 26-41.** `_healOnPresetMasterPower` iterates
   `ScheduleSyncService.kOnPresetSpecs` ([controller_defaults_healer.dart:538-541](lib/features/wled/controller_defaults_healer.dart#L538-L541)),
   which is exactly `{1: NGL On, 3: NGL Dim, 4: NGL Low, 5: NGL Medium}`
   ([schedule_sync.dart:349-354](lib/features/schedule/schedule_sync.dart#L349-L354)). And it
   explicitly **does not create or repair absent presets**
   ([:514-516](lib/features/wled/controller_defaults_healer.dart#L514-L516)).
2. **The lease writer only touches a preset at create/update time.** `savePreset` runs inside
   `_writeLeaseToWled` ([:1081-1085](lib/features/schedule/calendar_entry_lease_manager.dart#L1081-L1085)),
   reached only from the create path ([:619](lib/features/schedule/calendar_entry_lease_manager.dart#L619))
   or the update path ([:564](lib/features/schedule/calendar_entry_lease_manager.dart#L564)). The
   sweep's promotion loop skips already-registered dateKeys
   ([:793](lib/features/schedule/calendar_entry_lease_manager.dart#L793)). **An already-leased entry
   never has its preset re-saved.**
3. **Schedule sync preserves lease *timers* but never rewrites lease *presets*.** P0-3.2 merges
   `activeLeaseTimers()` into the cfg push
   ([:1223-1225](lib/features/schedule/calendar_entry_lease_manager.dart#L1223-L1225),
   consumed at [schedule_sync.dart:1181-1185](lib/features/schedule/schedule_sync.dart#L1181-L1185)).
   That keeps the stale timer **alive** while leaving the stale preset untouched — it actively
   preserves the broken pairing.
4. **The device evidence already shows the shape.**
   [PRESET_REGRESSION.md:130-137](audit/PRESET_REGRESSION.md#L130-L137): preset 27
   (written after `b97f793`) has root `on:true`; presets 26, 28, 29, 30, 41 (written before) have
   root `on` **ABSENT**. A WLED preset psaved without `ib:true` stores segments only
   ([schedule_sync.dart:356-360](lib/features/schedule/schedule_sync.dart#L356-L360)).

**Therefore:** a lease timer whose date has not yet passed, pointing at a preset written before
`b97f793`, will fire on its date, load segments-only, leave master power wherever it was — and if
the strip is off (the normal overnight state) **the lights stay dark**. The customer sees a
Christmas/game-day override that simply did not happen. Nothing detects it, nothing repairs it, and
per §2.4.5 it may repeat weekly.

**Scope, honestly stated:** this bites accounts that *have* live leases. That precondition is
**satisfied** — `liveWritesEnabled` has been `true` in production since 2026-05-19 (§2.4), which is
two months *before* `b97f793`, so every lease written in that window carries the broken shape.
What remains **UNVERIFIED** is only the count: how many customer controllers currently hold a
stale lease preset paired with a not-yet-fired timer. Establishing that needs a `/presets.json` +
`/json/cfg` readback across the fleet — which is exactly the telemetry §3.3 says does not exist.
The bench rig is the one machine where this is directly checkable today.

---

## PART 4 — OUTAGE RESILIENCE

### 4.1 Once armed, does the fire path have any cloud or app dependency? — **No**

An armed schedule consists of two things, both in the controller's own flash:

- the timer row in `cfg.timers.ins[]` (`en`,`hour`,`min`,`macro`,`dow`), written via `/json/cfg`
  ([schedule_sync.dart:1187-1189](lib/features/schedule/schedule_sync.dart#L1187-L1189));
- the preset the row's `macro` points at, written via `psave`
  ([wled_service.dart:929-1000](lib/features/wled/wled_service.dart#L929-L1000)).

At fire time WLED matches its own clock against `dow`/`hour`/`min` and applies the preset locally.
**Nothing in `lib/` participates.** There is no app-side alarm, no local-notification scheduler, no
Cloud Function cron that fires schedules — grepped; none exists. The app is a *writer* of schedules,
never an executor.

### 4.2 Do armed schedules survive reboot / power cut? — **Yes, with one caveat**

Both `/json/cfg` and `psave` are flash commits — this is the whole reason the codebase models a
post-commit stall and a 900 ms inter-psave settle
([schedule_sync.dart:1225-1231](lib/features/schedule/schedule_sync.dart#L1225-L1231),
[:1283-1299](lib/features/schedule/schedule_sync.dart#L1283-L1299)). Flash survives power loss.

**The caveat is the clock, not the schedule.** WLED needs NTP to know what time it is, and the
healer's header states the firmware behaviour it was designed around: *"WLED only re-attempts NTP on
boot"* ([controller_defaults_healer.dart:13-17](lib/features/wled/controller_defaults_healer.dart#L13-L17)) —
which is why every NTP heal is followed by a forced reboot
([:472](lib/features/wled/controller_defaults_healer.dart#L472)). If that is accurate, then a
**power cut during an internet outage** boots the controller with no reachable NTP server, the clock
never sets, and `CLOCK_UNSET` ([clock_health.dart:254-276](lib/features/wled/clock_health.dart#L254-L276))
means **no timer fires at all** until a later reboot with internet present. *The firmware claim
itself is* **UNVERIFIED** *from this repo* — it is an app-side comment about WLED 0.15.1, not
firmware source. **It is the single highest-value thing to bench-test before the claim ships.**

### 4.3 Does slot-leasing require periodic renewal? — **No for firing; YES for cleanup, and the
failure mode is inverted from what you feared**

Direct answer to the question asked: **leases do not expire on the device.** The controller has no
concept of a lease — it holds an ordinary weekly timer row. No renewal, no keepalive, no
heartbeat. An armed lease keeps firing through any outage of any length; there is no mechanism by
which an internet outage silently stops schedules. **The feared inversion does not exist.**

But the *reverse* problem does, and it is the same defect as §2.4.4-5 seen from the outage angle.
`kLeaseWindow` is 48 h ([calendar_entry_lease_manager.dart:71](lib/features/schedule/calendar_entry_lease_manager.dart#L71))
and the 5-minute sweep ([:72](lib/features/schedule/calendar_entry_lease_manager.dart#L72)) runs
**in the app process only**. During an extended outage (or simply an app the customer doesn't open):

- **Creation stops.** A calendar entry that enters its 48 h window is promoted by the sweep
  ([:779-808](lib/features/schedule/calendar_entry_lease_manager.dart#L779-L808)). No app run inside
  that window → no lease → **that override never fires.** Note this is *not* an outage-specific
  failure: it needs the app *and* home Wi-Fi *and* the feature flag. The flag's stored value is
  `true` (§2.4), but it is read from a **Firestore stream that yields `false` on any degraded
  state** — loading window, missing doc, stream error
  ([calendar_lease_feature_flag.dart:20-53](lib/features/schedule/calendar_lease_feature_flag.dart#L20-L53)).
  **A prolonged internet outage can therefore make lease *arming* fail even though the flag is on** —
  whether Firestore's offline cache carries the value through is **UNVERIFIED**.
- **Release stops.** Expiry sweeps don't run, so the weekly-recurring timer of §2.4.5 keeps firing.

So: **calendar/lease overrides are cloud- and app-dependent to *arm*. Ordinary schedules and
already-armed leases are not cloud-dependent to *fire*.**

### 4.4 On-LAN control during an internet outage

Works. `connectivity_plus` reports Wi-Fi, the SSID hash matches, status is `local`, and the app
builds a direct-HTTP `WledService`
([connectivity_service.dart:250-268](lib/services/connectivity_service.dart#L250-L268),
[wled_providers.dart:209-213](lib/features/wled/wled_providers.dart#L209-L213)) — no cloud in the
path. Whether the *app itself* launches cleanly with no internet (Firebase Auth token restore,
Firestore cached schedule reads) is **UNVERIFIED** and worth an airplane-mode launch test,
particularly given the +55/+56 startup-hang history.

### 4.5 Verdict: **HOLDS WITH CONDITIONS**

You can claim it. Suggested honest form:

> **Your schedules live on the controller, not in the cloud.** Once set, they keep running through
> an internet outage — no servers, no app, no subscription in the path.

Conditions, each of which you should know before saying it in public:

| # | Condition | Status |
|---|---|---|
| 1 | The schedule must have been **armed on the home network** in the first place (Parts 1-2) | Confirmed, code |
| 2 | Holds for recurring schedules and **already-armed** leases | Confirmed, code |
| 3 | Does **not** hold for a calendar override that needed arming *during* the outage (§4.3) | Confirmed, code |
| 4 | A **power cut during** the outage may leave the clock unset → nothing fires (§4.2) | **Needs bench proof** |
| 5 | Competitor contrast is fair: our fire path has no cloud dependency, theirs does | Confirmed for ours |

Do **not** claim "your schedules keep working no matter what" — condition 4 is a real, plausible,
customer-visible counter-example (a storm causes both the outage and the power cut), and it is
precisely the scenario the claim advertises.

---

## PART 5 — COST TO CLOSE

### 5.1 What cfg-over-bridge requires

**A. Bridge firmware (the substantial part).**
1. Two new dispatch cases in `executeCommand`
   ([main.cpp:815-825](esp32-bridge/src/main.cpp#L815-L825)): `applyConfig` → `POST /json/cfg`, and
   `getCfg` → `GET /json/cfg`. **`getCfg` is not optional** — every consumer is readback-verified
   (`pushCfgWithVerify`, [schedule_sync.dart:165](lib/features/schedule/schedule_sync.dart#L165)) or
   heal-only-broken (the healer). A write-only cfg bridge would re-create the false-green class the
   app just spent commits eliminating. Payload transport is already fine: the app sends a JSON
   string and the bridge forwards it verbatim
   ([main.cpp:852-858](esp32-bridge/src/main.cpp#L852-L858)).
2. **The stall model is the hard part.** A cfg commit freezes the controller's web server for
   *minutes* while the LEDs keep running — this is the documented, bench-proven behaviour the app
   models at [schedule_sync.dart:1283-1299](lib/features/schedule/schedule_sync.dart#L1283-L1299),
   and re-POSTing into the blackout is actively harmful. The bridge's `WLED_HTTP_TIMEOUT_MS` is
   **10 s** ([config.h.example:64](esp32-bridge/src/config.h.example#L64)) and any non-200 becomes
   `"ERROR: HTTP <code>"` → command marked `failed`
   ([main.cpp:917-925](esp32-bridge/src/main.cpp#L917-L925),
   [:835-845](esp32-bridge/src/main.cpp#L835-L845)). So a *successful* cfg write would report
   failure. The bridge must learn "POST once, then patiently re-read until it answers" — the same
   contract as `verifyCfgAfterStall`. It must do so without blocking `loop()` past the 5-minute
   watchdog at [main.cpp:273-277](esp32-bridge/src/main.cpp#L273-L277), which means a small state
   machine, not a blocking wait. **This is where the estimate lives.**
3. Bump `BRIDGE_FIRMWARE_VERSION` ([main.cpp:54](esp32-bridge/src/main.cpp#L54)) so the app can gate.

**B. App routing (small).** `supportsCfgWrites` currently returns `webhookUrl.isNotEmpty`
([cloud_relay_repository.dart:419](lib/features/wled/cloud_relay_repository.dart#L419)). It becomes
`webhookUrl.isNotEmpty || bridgeFirmwareSupportsCfg`, read from
`/bridge_registry/{deviceId}.firmwareVersion` which the bridge already publishes
([main.cpp:1052](esp32-bridge/src/main.cpp#L1052)). Every call site already pre-flights through
`repoCanWriteCfg`, so **no caller changes** — the guard was designed for exactly this. The healer
additionally needs its `is WledService` gates relaxed to `repoCanWriteCfg` +
a relay `getConfig()` implementation ([:456-461](lib/features/wled/controller_defaults_healer.dart#L456-L461),
[:477](lib/features/wled/cloud_relay_repository.dart#L477)).

**C. Security implications of accepting remote cfg writes.** Three, in descending severity:

1. **`controllerIp` is attacker-chosen today, and cfg raises the stakes.** The bridge takes the
   target IP straight from the command document
   ([main.cpp:778-779](esp32-bridge/src/main.cpp#L778-L779)) and falls back to the paired IP only
   when empty. Anyone who can write to `/users/{uid}/commands` — owner-only per
   [firestore.rules:441-453](firestore.rules#L441-L453), so: a compromised customer account — can
   currently make the bridge POST arbitrary JSON to any host on the home LAN. Adding cfg turns that
   from "flip someone's lights" into "reconfigure any WLED-shaped device on their network." **Fix
   before shipping cfg, not after:** validate `controllerIp` against the user's registered
   controllers (Cloud Function on command create, or on-bridge against the paired IP).
2. **`/json/cfg` is a much broader key surface than `/json/state`.** Timers are one branch; the same
   endpoint carries network, AP, OTA-lock and LED-bus configuration. A cfg-capable bridge should
   accept a **key allowlist** (`timers.*` plus whatever the healer needs), enforced on the bridge so
   a compromised app build can't widen it.
3. **All bridges share one Firebase Auth identity.** `FIREBASE_AUTH_EMAIL` / `_PASSWORD` are
   compile-time constants ([config.h.example:30-31](esp32-bridge/src/config.h.example#L30-L31)) and
   the bridge self-declares the email over unauthenticated local HTTP
   ([main.cpp:397](esp32-bridge/src/main.cpp#L397)). Also unauthenticated on the LAN:
   `/api/bridge/pair` and `/api/reset` ([main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372)) —
   anyone on the Wi-Fi can re-pair or factory-reset a bridge. Pre-existing, not caused by this work,
   but it is the trust model cfg-over-bridge would be inheriting and it should be recorded as such.

### 5.2 Estimate

| Component | Estimate | Confidence |
|---|---|---|
| Bridge: `applyConfig` + `getCfg` dispatch | 3h | High |
| Bridge: non-blocking stall/verify state machine (§5.1 A2) | 10-16h | **Low-Medium** — the failure modes are only reachable on hardware |
| Bridge: cfg key allowlist | 2h | High |
| App: firmware-gated `supportsCfgWrites` + healer un-gating + relay `getConfig()` | 5h | Medium |
| Backend: `controllerIp` validation on command create | 3h | Medium |
| Bench verification (write → stall → verify → reboot → confirm armed) | 6h | Medium |
| **Total engineering** | **~30-35h** | **Medium** |
| **Fleet deployment** | see 5.3 | — |

Confidence is capped at Medium by one thing: the stall behaviour is bench-observed, not
characterised. If the stall exceeds the bridge's watchdog window in ways the app's patient-verify
never had to care about (the phone can wait; a 5-minute-watchdog ESP32 cannot), item 2 grows.

### 5.3 Can it share an OTA campaign with F-5b? — **Yes, and it should — but the campaign doesn't
exist yet**

**The blocker is that there is no OTA.** [main.cpp](esp32-bridge/src/main.cpp) has no `ArduinoOTA`,
no `httpUpdate`, no update endpoint — the web server registers six routes and none of them is an
update path ([main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372)). Today, "deploy firmware"
means physically visiting each bridge with a USB cable. That is the same wall F-5b hit: its part 2
is *"a paired bridge polls for `status == 'unpaired'` and clears its own NVS"*, with the estimate
deferred as owner-decided
([COMPLIANCE_AND_SECURITY.md:304-320](audit/COMPLIANCE_AND_SECURITY.md#L304-L320)).

So the three pieces are one project, and the ordering is forced:

1. **OTA first** — without it, both features cost a truck roll each and neither is deployable to
   installed hardware. *Estimate not attempted; **UNVERIFIED** whether the current partition table
   leaves room for OTA slots.*
2. **F-5b part 2** (remote unpair) — small once OTA exists: extend `pollPairingRequest`, which today
   returns early unless `status == "pairing"` ([main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220))
   and is only reached while unpaired ([:243-249](esp32-bridge/src/main.cpp#L243-L249)).
3. **cfg-over-bridge** — the largest of the three, per 5.2.

All three touch `executeCommand`/`pollPairingRequest`/the web server in the same file, and all three
need the same bench cycle. Doing them as one image is a clear saving — call it **~8h of the 30-35h
recovered** in shared verification and deployment, and it converts F-5b part 2 from "blocked on
firmware" to "shipped."

---

## Summary of findings

| # | Finding | Severity | Where |
|---|---|---|---|
| 1 | Bridge relays `/json/state` only; no cfg case exists in firmware | By design | [main.cpp:815-825](esp32-bridge/src/main.cpp#L815-L825) |
| 2 | Schedule off-LAN UX is **honest** — not a third F-5/F-8 | ✅ | [my_schedule_page.dart:272-281](lib/features/schedule/my_schedule_page.dart#L272-L281) |
| 3 | **No automatic re-arm on LAN return** for non-solar schedules; in-app copy and the setup guide both promise one | **P1 — R-1 qualifier** | [schedule_providers.dart:229-233](lib/features/schedule/schedule_providers.dart#L229-L233), [ESP32_Bridge_Setup_Guide.md:67](docs/ESP32_Bridge_Setup_Guide.md#L67) |
| 4 | Off-LAN lease returns `leased`, is never retried by the sweep, and is surfaced nowhere — **third false-success instance**. **Live in production**: `liveWritesEnabled=true` since 2026-05-19 | **P1** | [calendar_entry_lease_manager.dart:636-643](lib/features/schedule/calendar_entry_lease_manager.dart#L636-L643), [:793](lib/features/schedule/calendar_entry_lease_manager.dart#L793) |
| 5 | Expiry sweep drops the registry record while ignoring a failed zero-write; single-date leases are weekly-recurring for a year | **P1** | [:719-729](lib/features/schedule/calendar_entry_lease_manager.dart#L719-L729), [post_session_cfg.json](audit/verification_evidence/post_session_cfg.json) |
| 6 | **A stale pre-`b97f793` lease CAN fire dark before it expires, and nothing heals it** | **P1** | [PRESET_REGRESSION.md:130-137](audit/PRESET_REGRESSION.md#L130-L137), [controller_defaults_healer.dart:538-541](lib/features/wled/controller_defaults_healer.dart#L538-L541) |
| 7 | Zero controller-health telemetry; a never-reached controller stays broken silently and invisibly | **P2** | [controller_defaults_healer.dart](lib/features/wled/controller_defaults_healer.dart) (no Firestore writes) |
| 8 | Outage resilience **HOLDS WITH CONDITIONS**; the feared lease-renewal inversion does **not** exist | ✅ | §4 |
| 9 | Clock-unset-after-power-cut-during-outage is the one real counter-example — **needs bench proof** | **UNVERIFIED** | [controller_defaults_healer.dart:13-17](lib/features/wled/controller_defaults_healer.dart#L13-L17) |
| 10 | `controllerIp` is command-supplied and unvalidated — must be fixed *before* cfg-over-bridge | **P1 if cfg ships** | [main.cpp:778-779](esp32-bridge/src/main.cpp#L778-L779) |
| 11 | No OTA in bridge firmware; blocks cfg-over-bridge **and** F-5b part 2 equally | **P0 for any firmware roadmap** | [main.cpp:366-372](esp32-bridge/src/main.cpp#L366-L372) |
