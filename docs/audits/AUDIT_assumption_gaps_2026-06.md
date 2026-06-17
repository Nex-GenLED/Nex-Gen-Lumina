# Overnight Audit 1 — Assumption-Gap Sweep (the catastrophic-after-release class)

**Date:** 2026-06-02 · **Branch:** submission/app-store-v1 · **Method:** READ-ONLY. No code changed, no commits. 5 parallel cluster explorations + direct source verification of every load-bearing claim.
**Purpose:** Systematic, exhaustive enumeration of the bug *class* behind this session's worst issues — single-channel / single-controller / single-home / warm-cache / shared-clock assumptions. Audit 4 (FEATURE_COMPLETENESS_INVENTORY) found ~5 multi-bus-bypass instances at a feature level. This audit enumerates **every** apply / payload-build / device-address site, classifies each against 5 assumption axes, then **groups by class so each can be fixed in one pass** rather than instance-by-instance.

**Verification provenance:** UI/foreground apply paths, the two chokepoints, `_postUpdate`, and every `id:0` hardcode below were read directly and quoted. Background-isolate and Cloud Function claims are tagged **(sub-agent; verify)** where I did not open the file myself — they are high-confidence but not first-hand.

---

## 0. The five assumption axes

| Axis | Assumption | The bug when it's wrong |
|---|---|---|
| **A** | **MULTI-CHANNEL** — one bus / seg 0 / id:0 is the whole device | On a 2+ bus install (Ellie, every Dig-Octa) only channel 1 lights; channel 2+ stays dark |
| **B** | **MULTI-CONTROLLER** — one selected controller is the whole site, and fan-out works everywhere | Linked/zoned controllers don't move together; fan-out that exists is **LAN-only** and dies off-network (relay) |
| **C** | **WARM-CACHE** — the participation cache is populated | Cold/null cache → broadcast-intent payloads fall through the chokepoint → wrong channels (the Game-Day channel-2 class) |
| **D** | **SINGLE-HOME / one-surface** — one home, one active screen, symmetric build versions | Off-screen receiver never applies; dormant teardown; no-op post-event; mixed-build desync |
| **E** | **SHARED-CLOCK** — all devices/homes agree on "now" | Sync animation phase-drift; background game-day pre-roll fires at the wrong wall-clock time |

---

## 1. The canonical-correct contract (so fixes are class-based, not per-call)

Two safe primitives exist in [wled_payload_utils.dart](../../lib/features/wled/wled_payload_utils.dart). **Every multi-channel-correct path uses one of them; every bug below does not.**

1. **`applyChannelFilter(payload, channelIds, channels)`** — the **widget-side** filter. Rewrites `seg[]` to one entry per `channelIds` with **explicit `id`, `start`, `stop`, and `on:true`**. `channelIds` is sourced from `effectiveChannelIdsProvider` (channel selector ∩ participation). **This honors the on-screen channel chips.** SAFE by construction.

2. **The applyJson chokepoint** — both transports ([wled_service.dart:397-404](../../lib/features/wled/wled_service.dart#L397-L404) and [cloud_relay_repository.dart:364-373](../../lib/features/wled/cloud_relay_repository.dart#L364-L373)) run `normalizeWledPayload` → `expandForParticipation(payload, await getCachedParticipatingChannels())`. **`expandForParticipation` only expands a payload that is single-seg, has NO `id` on `seg[0]`, HAS `fx`, AND participation is non-null/non-empty.** It is keyed on the **SharedPreferences participation cache** — which is **written only by Game Day Autopilot and Neighborhood Sync** ([game_day_autopilot_providers.dart:162], [neighborhood_sync_engine.dart:428]). It does NOT read the channel selector and does NOT set `start`/`stop`.

**The load-bearing distinction that defines the whole bug class:**

| Payload shape a path emits | Chokepoint behavior | Multi-channel result |
|---|---|---|
| `applyChannelFilter(...)` was called → multi-seg with ids | Rule 4 pass-through (already correct) | **SAFE — honors the channel selector** |
| `seg:[{id:0, ...}]` (hardcoded id) | Rule 5 pass-through | **ALWAYS bus-0 only**, even with a warm cache |
| `seg:[{fx:.., ...}]` (no id, has fx) | Rule 7 expand **iff cache warm**, else Rule 1 pass-through | **bus-0 when cache cold/null; all *participating* channels when warm** — never the channel selector |
| top-level only (`{on}`, `{bri}`) | Rule 3 pass-through | Global — correct (device-level) |

So there are **two multi-channel bug sub-shapes**: **(1a) `id:0` hardcode** = unconditionally bus-0; **(1b) no-id broadcast** = bus-0 unless a *participation* cache (not the selector) happens to be warm. A user who never ran Game Day/Sync has a null cache, so 1b is *also* bus-0 for them.

---

## 2. Master enumeration — every apply / payload / device-address site

Status: ✅ SAFE · ⚠️ AT-RISK · ❌ CONFIRMED-BUG · — N/A. "Reaches" = does the payload reach `expandForParticipation`.

| # | Site (`file:line`) | Payload shape | A (ch) | B (ctrl) | C (cache) | D | E | Customer symptom |
|---|---|---|---|---|---|---|---|---|
| **Core pipeline** |
| 1 | [wled_service.dart:397](../../lib/features/wled/wled_service.dart#L397) `applyJson` (chokepoint) | normalize→expand | ✅ | ✅ LAN single | ⚠️ cold→pass-through | — | — | (mechanism, not a site) |
| 2 | [cloud_relay_repository.dart:364](../../lib/features/wled/cloud_relay_repository.dart#L364) `applyJson` | normalize→expand | ✅ | single `controllerId` (relay) | ⚠️ | — | — | `getConfig` null off-LAN |
| 3 | [wled_providers.dart:1275-1404](../../lib/features/wled/wled_providers.dart#L1389-L1404) `_postUpdate` | per-seg `{id,col/sx,start,stop}` when `effectiveChannels` non-empty | ✅ when warm / ⚠️ cold→`setState` id:0 | ✅ single selected | ⚠️ empty selector→bus-0 | — | — | Color/brightness reaches all selected channels once hardware config loads; bus-0 only before it does |
| 4 | [wled_providers.dart:248](../../lib/features/wled/wled_providers.dart#L248) controller loop | — | — | residential link set | — | — | — | link-set resolution only |
| **Dashboard** |
| 5 | [wled_dashboard_page.dart:949](../../lib/features/dashboard/wled_dashboard_page.dart#L949) power fan-out | `WledService('http://$ip').setState(on:)` ×N | ⚠️ setState=id:0 per ctrl | ❌ **LAN-only** direct-IP | — | — | — | Linked/zone power: works on Wi-Fi, dead off-LAN; each controller only seg 0 toggles |
| 6 | [wled_dashboard_page.dart](../../lib/features/dashboard/wled_dashboard_page.dart) pattern/preset apply | `applyChannelFilter`→applyJson | ✅ | ✅ single | ✅ | — | — | — |
| **Current Colors editor** |
| 7 | [current_colors_provider.dart:303](../../lib/features/wled/current_colors_provider.dart#L303) | `seg:[{id:0, fx, col, pal:5}]` | ❌ **1a bus-0** | single | — | — | — | Ellie: color editor updates ch1 only; ch2 keeps old color. Code comment self-admits "should be enhanced to apply to all segments" |
| **Pattern library / Edit / Design** |
| 8 | [colorway_effect_selector.dart:207,278](../../lib/features/wled/colorway_effect_selector.dart#L278) | `applyChannelFilter`→applyJson | ✅ | single | ✅ | — | — | — |
| 9 | [edit_pattern_screen.dart:93](../../lib/features/wled/edit_pattern_screen.dart#L93) | `applyChannelFilter` | ✅ | single | — | — | — | — |
| 10 | [pattern_category_detail.dart:104,247,280,504](../../lib/features/wled/pattern_category_detail.dart#L104) | `applyChannelFilter` (incl. grp/spc, pal tweaks) | ✅ | single | — | — | — | — |
| 11 | [pattern_theme_selection.dart:693,783](../../lib/features/wled/pattern_theme_selection.dart#L693) | `applyChannelFilter` | ✅ | single | — | — | — | — |
| 12 | [pattern_adjustment_panel.dart:249,276,303,536](../../lib/widgets/pattern_adjustment_panel.dart#L249) | `applyChannelFilter` | ✅ | single | — | — | — | — |
| 13 | [pattern_grid_widgets.dart ~1422](../../lib/features/wled/pattern_grid_widgets.dart) `_handlePatternApply` | single-seg, fx 0→83/84 substitution | ⚠️ **VERIFY** filter presence | single | — | — | — | If unfiltered, Ellie bus-0 only on grid apply (sub-agent partial read) |
| 14 | [apply_saved_design.dart:56](../../lib/features/design/apply_saved_design.dart#L56) | builds multi-seg ids + `applyChannelFilter` | ✅ | per-design channels | ✅ pre-filters vs cold | — | — | — |
| **Scenes** |
| 15 | [scene_providers.dart:140-150](../../lib/features/scenes/scene_providers.dart#L140) `applyScene` | `scene.toWledPayload()`→`applyPayloadWithLabel` (no `applyChannelFilter`) | ⚠️/❌ **1b** | single | ⚠️ | — | — | Library scene = no-id+fx ([scene_models.dart:243](../../lib/features/scenes/scene_models.dart#L243)) → bus-0 unless cache warm; custom scene = design payload (id-bearing, ok); snapshot = stored blob |
| **Lumina AI chat** |
| 16 | [lumina_ai_screen.dart:258,328,425,635](../../lib/features/ai/lumina_ai_screen.dart#L258) | `repo.applyJson(wledPayload)` no filter | ⚠️/❌ **1b** | ❌ single LAN | ⚠️ | — | — | AI "make the roof purple" lights ch1 only on a fresh multi-bus install (cold cache); reaches participating channels only after a Game-Day/Sync session warmed the cache |
| 17 | [lumina_bottom_sheet.dart:598,669](../../lib/features/ai) | same | ⚠️/❌ **1b** | single | ⚠️ | — | — | same |
| 18 | [adjustment_state_controller.dart:168,232](../../lib/features/ai/adjustment_state_controller.dart#L168) | `seg:[{fx,...}]` no id | ⚠️/❌ **1b** | single | ⚠️ | — | — | AI "brighter/slower" adjustment bus-0 on cold cache |
| 19 | [local_command_parser.dart:459-484](../../lib/features/ai/local_command_parser.dart#L459) | builds `seg:[{fx:0/effectId,...}]` no id | (source of 16-18 shapes) | — | — | — | — | the payload factory feeding the AI bus-0 class |
| **Audio mode (release-gated, kDebugMode)** |
| 20 | [audio_mode_page.dart:53,76,101](../../lib/features/audio/audio_mode_page.dart#L53) | `seg:[{id:0, si/fx/sx/ix}]` | ❌ **1a bus-0** | single | — | — | — | Audio reactivity ch1 only. Gated off in release, low blast radius |
| 21 | [audio/screens/audio_reactive_screen.dart:37,51](../../lib/features/audio/screens/audio_reactive_screen.dart#L37) | `seg:[{id:0,...}]` | ❌ **1a** (orphan dup file) | single | — | — | — | dead duplicate; same bug |
| **Geofence** |
| 22 | [geofence_monitor.dart:252](../../lib/features/geofence/geofence_monitor.dart#L252) welcome-home favorite | `applyPayloadWithLabel(favorite)` | ⚠️ depends on stored favorite shape (often id:0) | ❌ single, app-alive only | ⚠️ | — | — | Welcome-home lights bus-0; only fires while app is running (not true bg) |
| 23 | [geofence_monitor.dart:282-284](../../lib/features/geofence/geofence_monitor.dart#L284) "party" fallback | `seg:[{id:0, fx:27,...}]` | ❌ **1a bus-0** | single | — | — | — | Party arrival lights ch1 only |
| **Voice (Siri shortcuts; Alexa/Google have no backend)** |
| 24 | dashboard_voice_control.dart:198,232,270 *(sub-agent; verify)* | `seg:[{id:0, fx, col}]` | ❌ **1a bus-0** | ❌ single LAN | — | — | — | "Hey Siri warm white" → ch1 only |
| **Schedule** |
| 25 | [schedule_sync.dart:266](../../lib/features/schedule/schedule_sync.dart) `applyConfig` *(sub-agent; verify)* | `{tim/ins:[...]}` device timers | — device-level | ❌ single device, **LAN-only** (no relay) | — | — | ⚠️ device clock | Timers push to selected controller only; linked controllers never get timers. Cap **8** timers, not 20. Off-LAN sync impossible |
| **Game Day (foreground)** |
| 26 | [game_day_apply.dart:88](../../lib/features/game_day/game_day_apply.dart#L88) | `applyChannelFilter(basePayload, participatingChannels, deviceChannels)` | ✅ pre-filters vs cold cache | ✅ single LAN | ✅ explicit channels | — | — | — (the reference fix for the cold-cache class) |
| 27 | [light_it_up_now.dart](../../lib/features/game_day/light_it_up_now.dart), [game_day_screen.dart:439](../../lib/features/game_day/game_day_screen.dart) | delegate to #26 | ✅ | single | ✅ | — | — | — |
| **Game Day Autopilot** |
| 28 | [game_day_autopilot_service.dart:807-846](../../lib/features/autopilot/game_day_autopilot_service.dart#L807) foreground | single-seg no-id; relies on chokepoint + resolver callback | ⚠️ **1b** if callback returns null (try/catch at providers:166) | single LAN | ⚠️ resolver→cache | — | — | If Riverpod resolve throws, autopilot apply falls to bus-0 |
| 29 | [game_day_autopilot_background_worker.dart:402-523](../../lib/features/autopilot/game_day_autopilot_background_worker.dart) *(sub-agent; verify)* | catalog single-seg → `applySyncPattern` CF, payload verbatim | ❌ **bus-0**: isolate can't resolve participation, server can't `expandForParticipation` | ☁️ CF server fan-out per-UID (relay) | ❌ cache irrelevant in isolate | — | ⚠️ ESPN vs device clock | **App-closed Game Day lights only ch1 on every multi-bus install**; pre-roll can fire at wrong wall-clock under clock skew |
| **Sports Alerts** |
| 30 | [alert_trigger_service.dart:119-258](../../lib/features/sports_alerts/services/alert_trigger_service.dart#L119) | per-controller `_resolveChannels`→`applyChannelFilter` | ✅ per-controller | ✅ multi-ctrl but ❌ **LAN-only**, no relay | ✅ reads hw config, not cache | — | — | Test-fire works on Wi-Fi; nothing off-LAN |
| 31 | [sports_background_service.dart:101,177,273](../../lib/features/sports_alerts/services/sports_background_service.dart) *(sub-agent; verify)* | `AlertTriggerService(controllerIps: const [])` on iOS; `updateControllerIps()` has **zero callers** | — | ❌ **INERT**: empty IP list → addresses no device | ❌ | — | — | **Real app-closed score celebration fires the notification but no LEDs** — multi-controller and single alike |
| **Neighborhood Sync** |
| 32 | [neighborhood_sync_engine.dart:643-656](../../lib/features/neighborhood/neighborhood_sync_engine.dart) `_executePattern` | single-seg no-id→applyJson; resolver writes cache at :428 | ✅ expands (cache freshly written) | local apply only | ✅ writes then reads | ⚠️ per-home local | ❌ **start = device `DateTime.now()`** ([:247]) | Two homes apply at skewed local times → **animation phase drift**; >2s clock skew visibly desyncs |
| 33 | [sync_event_background_worker.dart:749-815](../../lib/features/neighborhood/services/sync_event_background_worker.dart) *(sub-agent; verify)* | explicit-id **8-channel** seg → `applySyncPattern` CF | ⚠️ over-broad: lights all 8 incl. non-participating | ☁️ CF per-initiator-UID | ❌ no cache in isolate | ⚠️ host-only fan-out | ⚠️ | Receiver's non-participating channels can light during sync |
| 34 | [sync_teardown_resolver.dart:232](../../lib/features/neighborhood/services/sync_teardown_resolver.dart#L232) | `filterMultiSegByParticipation` | ✅ *if called* | — | ✅ | ❌ **dormant** per sub-agent — confirm wired | — | Stop-Sync scene restore may force-light a staged-off channel if resolver path unused |
| 35 | [sync_session_manager.dart:408-425](../../lib/features/neighborhood/services/sync_session_manager.dart) `_applyPostEventBehavior` *(sub-agent; verify)* | debugPrint only | — | — | — | ❌ **no-op** (turnOff/stayOn/returnToAutopilot all dead) | — | After a sync show ends, lights stay frozen in sync state instead of turning off/restoring |
| 36 | [sync_handoff_manager.dart:340-377](../../lib/features/neighborhood/services/sync_handoff_manager.dart) *(sub-agent; verify)* | local broadcast only; hardcoded `transition:30` | — | local-only | — | ⚠️ asymmetric per-user resume | ⚠️ crossfade un-coordinated across homes | Handoff resume can leave one home stuck |
| 37 | [main.dart:298-320](../../lib/main.dart#L298) app-level sync listener | keepalive | — | — | ⚠️ resume replay local-only | ✅ fixes off-screen receiver | ⚠️ replay out-of-phase | (the live-propagation fix; replay timing not phase-aligned with peer) |
| **Multi-controller fan-out (status / config)** |
| 38 | [site_providers.dart:127,212](../../lib/features/site/site_providers.dart#L212) `areaAnyOnProvider`, DDP secondaries | `WledService('http://$ip')` ×N | — | ❌ **LAN-only** direct-IP | — | — | — | Off-LAN status reads as offline; DDP zone setup LAN-only |
| 39 | [site_providers.dart:168](../../lib/features/site/site_providers.dart#L168) `activeAreaControllerIpsProvider` | falls back to all controllers "until a Zone selector exists" | — | commercial zone targeting **unwired** | — | — | — | Commercial: no per-zone targeting; broadcasts to all |
| **Commercial fleet** |
| 40 | corporate_push_service.dart:36-73 *(sub-agent; verify)* | Firestore batch write to `commercial_schedule` docs | — | ❌ **never reaches a device** | — | — | — | "Push to all locations" updates Firestore; **controllers never pull it** — no device effect |
| 41 | FleetDashboardScreen *(sub-agent; verify)* | read-only display, faked `lastSync` | — | — | — | — | — | Fleet status is cosmetic (naive online heuristic, never pings) |
| **Design Studio** |
| 42 | ai_design_studio_screen *(sub-agent; verify)* | "Apply to Lights" **hard-disabled** "coming soon"; live-preview toggle is a no-op | — (inert) | — | — | — | — | Toggle implies device preview; has zero side-effects |

---

## 3. Findings grouped by CLASS (the deliverable — fix each in one pass)

### CLASS 1 — Multi-channel bypass (Axis A). **Touches the most shipping-v1 features. Highest priority.**

Two sub-shapes, one root: the path does not call `applyChannelFilter`, so it ignores the channel selector.

**1a — Hardcoded `seg:[{id:0,...}]` → unconditionally bus-0** (worst; a warm cache cannot save these):
- ❌ [current_colors_provider.dart:303](../../lib/features/wled/current_colors_provider.dart#L303) — Current Colors editor
- ❌ [audio_mode_page.dart:53,76,101](../../lib/features/audio/audio_mode_page.dart#L53) + ❌ [audio_reactive_screen.dart:37,51](../../lib/features/audio/screens/audio_reactive_screen.dart#L37) (orphan dup) — Audio mode (release-gated)
- ❌ [geofence_monitor.dart:284](../../lib/features/geofence/geofence_monitor.dart#L284) — Geofence party fallback
- ❌ dashboard_voice_control.dart:198,232,270 — Voice presets *(verify)*

**1b — No-id `seg:[{fx,...}]` → bus-0 unless the *participation* cache is warm** (and even then it tracks participation, never the on-screen selector):
- ⚠️ [lumina_ai_screen.dart:258,328,425,635](../../lib/features/ai/lumina_ai_screen.dart#L258), [lumina_bottom_sheet.dart:598,669], [adjustment_state_controller.dart:168,232](../../lib/features/ai/adjustment_state_controller.dart#L168) — fed by [local_command_parser.dart:459-484](../../lib/features/ai/local_command_parser.dart#L459)
- ⚠️ [scene_providers.dart:150](../../lib/features/scenes/scene_providers.dart#L150) (library-type scenes, [scene_models.dart:243](../../lib/features/scenes/scene_models.dart#L243))
- ⚠️ [game_day_autopilot_service.dart:807](../../lib/features/autopilot/game_day_autopilot_service.dart#L807) (only if the resolver callback throws → null)
- ⚠️ [pattern_grid_widgets.dart ~1422](../../lib/features/wled/pattern_grid_widgets.dart) — **VERIFY** whether `applyChannelFilter` is called

**Reference fix already in tree:** [game_day_apply.dart:88](../../lib/features/game_day/game_day_apply.dart#L88) and [apply_saved_design.dart:56](../../lib/features/design/apply_saved_design.dart#L56) both call `applyChannelFilter(payload, effectiveChannels, deviceChannels)` *before* `applyJson`. **Class fix = make every Class-1 site do the same** (or, for 1a, drop the hardcoded `id:0`). One-pass: route all of the above through a single `applyToDevice(payload)` helper that always pre-filters.

**Background variant (can't use the widget helper):** [game_day_autopilot_background_worker.dart](../../lib/features/autopilot/game_day_autopilot_background_worker.dart) #29 — isolate can't resolve participation and the `applySyncPattern` Cloud Function sends the payload verbatim, so **app-closed Game Day is bus-0 on every multi-bus install.** Fix requires either persisting resolved channel ids for the isolate to read, or `buildParticipatingSegArray` at payload-build time, or teaching the Cloud Function to expand. (Sync's background worker #33 *does* build explicit ids 0-7 — over-broad but not dark — confirming the asymmetry.)

### CLASS 2 — Multi-controller is single-controller, and the fan-out that exists is LAN-only (Axis B). **Second-broadest.**

- `_postUpdate` (#3) — the main control path — targets exactly ONE controller (`selectedDeviceIpProvider`). Brightness/color/speed/power/pattern never fan out by themselves.
- The fan-outs that *do* exist are all scattered **direct-IP `WledService('http://$ip')`** loops, **LAN-only**, so they die off-network: dashboard power (#5), `areaAnyOnProvider`/DDP (#38), sports alerts `_controllerIps` (#30), schedule sync is single-device (#25).
- The **only relay-capable multi-controller fan-out** is the `applySyncPattern` Cloud Function (sync + game-day background, per-initiator-UID) — and that path carries the Class-1 background bus-0 defect.
- Commercial "fleet push" (#40) writes Firestore only and **never reaches a device**; zone targeting is unwired (#39).

**Class fix:** a transport-agnostic "apply to active controller set" that resolves `activeAreaControllerIpsProvider` and dispatches through `WledRepository` (so relay works), instead of ad-hoc LAN loops. Until then, **document** every LAN-only fan-out as Wi-Fi-only.

### CLASS 3 — Cold / null participation cache (Axis C). **The Game-Day channel-2 class.**

- The chokepoint keys on `getCachedParticipatingChannels()`, written ONLY by Game Day/Sync. For everyone else it's null → Class-1b paths broadcast bus-0.
- `peekCachedParticipatingChannels()` returns null when cold → dashboard chips render "all enabled" while the first apply may load a non-null stale value (the one-cycle race fully analyzed in [CHANNEL_MAPPING_AUDIT_2026-05.md §4](./CHANNEL_MAPPING_AUDIT_2026-05.md)).
- `_postUpdate` cold-start (#3): empty `effectiveChannels` → legacy `setState` (id:0).
- Background isolates (#29, #33) cannot read the cache at all.

**Class fix (already specified in CHANNEL_MAPPING_AUDIT Addendum 1):** read-side reconciliation at lazy-load + a dashboard warm-up `unawaited(getCachedParticipatingChannels())`. Pairs with Class 1: if Class-1 paths pre-filter from `effectiveChannelIds` they stop depending on the cache entirely.

### CLASS 4 — Single-home / one-surface / dormant teardown (Axis D). **Neighborhood Sync.**

- `_applyPostEventBehavior` (#35) is a debugPrint no-op → lights freeze in the sync state after a show.
- `filterMultiSegByParticipation` teardown (#34) reportedly dormant → Stop-Sync can force-light a staged-off channel.
- Handoff resume (#36) is per-user, not group-coordinated → one home can stick.
- App-resume replay (#37) is local-only and not phase-aligned with the peer.
- Mixed-build hazard: memory already notes both homes must run the new build.

**Class fix:** wire the teardown/post-event executor that already exists (`executeMemberTeardown` + `sync_teardown_resolver`) into the engine's stop path; verify no dormant branches. *(Several of these are sub-agent-sourced — confirm dormancy first-hand before acting.)*

### CLASS 5 — Shared-clock / phase-drift (Axis E). **Sync + background game-day.**

- Sync start timestamp = each device's `DateTime.now()` ([neighborhood_sync_engine.dart:247]); homes apply at skewed local times → **guaranteed animation drift with >2s clock skew.** No server reference frame.
- Background game-day pre-roll gate compares device clock to ESPN timestamps (#29) → pre-roll at wrong wall-clock under skew/wrong timezone.
- Handoff crossfade (#36) hardcodes a transition duration with no cross-home coordination.

**Class fix:** derive the sync start instant from a server timestamp (the session doc already stamps `startedAt: serverTimestamp()` in `initiateSyncSession.ts`) + a shared "begin at the next whole-second boundary" rule, instead of each client's local clock.

### CLASS 6 — Looks-done-but-dark (inert/stubbed apply). Not an assumption bug per se, but the same customer-facing failure (a control that addresses no device).

- ❌ Sports background celebration inert — `updateControllerIps()` zero callers, iOS `const []` (#31)
- ❌ Commercial corporate push never reaches devices (#40)
- ❌ Design Studio "Apply to Lights" disabled + fake live-preview toggle (#42)
- ⚠️ Fleet `lastSync` faked, never pings (#41)

---

## 4. Class ranking by shipping-v1 feature footprint

| Rank | Class | v1 features touched | Blast radius |
|---|---|---|---|
| **1** | **Class 1 — multi-channel bypass** | Current Colors, Lumina AI, Scenes, Audio, Geofence, Voice, Game-Day-background, (pattern-grid?) — **8+ surfaces** | **Every 2+ bus install** (Ellie, all Dig-Octa, Blue Line). Silent — channel 2 just stays dark. This is the exact class that caused this session's worst issues. |
| **2** | **Class 2 — multi-controller / LAN-only fan-out** | Dashboard power, Schedule, Sports, Commercial fleet, zone targeting — **5+ surfaces** | Every linked-controller or commercial site; *and* every off-LAN user of the fan-out paths |
| **3** | **Class 3 — cold participation cache** | The enabling condition for half of Class 1b + the channel-2 race | Every fresh install before first Game-Day/Sync |
| **4** | **Class 5 — shared-clock** | Neighborhood Sync, background game-day | Every multi-home sync (Tyler+Ellie) |
| **5** | **Class 4 — single-home/dormant teardown** | Neighborhood Sync stop/handoff | Every sync show's end-of-life |
| **6** | **Class 6 — inert apply** | Sports bg, Commercial push, Design Studio | Features that look shipped but do nothing |

---

## 5. Corrections to the parallel sub-agent findings (kept honest)

These over-claims surfaced during fan-out and were corrected against source:

1. **`_postUpdate` is NOT a confirmed multi-channel bug.** When `effectiveChannels` is populated it builds correct per-channel multi-seg with `id`/`start`/`stop` ([wled_providers.dart:1391-1401]). The real, smaller gaps: (a) it omits per-seg `'on':true` in the template, so a *currently-off* targeted channel won't relight on a color/speed tweak (minor — these tweaks act on already-lit shows); (b) cold-start with empty selector falls to `setState` id:0 (Class 3). Downgraded CONFIRMED→AT-RISK.
2. **"Participation expansion is never activated in user flows" is wrong.** It IS activated whenever Game Day or Sync has written the cache. The correct statement is narrower: it's keyed on the *participation* cache, not the channel *selector*, so it doesn't honor the chips and is null for users who never ran Game-Day/Sync.
3. **"All apply paths are bus-0 / the app is non-functional for multi-channel" is overstated.** The entire pattern-library/Edit/Colorway/Design surface (#8-#14) *is* multi-channel-correct via `applyChannelFilter`. The bug is concentrated in the Class-1 list, not universal.
4. **Lumina AI is "1b" not flat "bus-0."** Its payloads are no-id+fx, which the chokepoint *will* expand on a warm cache — so the symptom is install-state-dependent, which matters for repro.

---

## 6. One-pass fix recommendations (no code changed here)

1. **Class 1:** introduce a single `applyToDevice(payload, {labelHint})` chokepoint on `WledNotifier` that ALWAYS does `applyChannelFilter(payload, ref.read(effectiveChannelIdsProvider), ref.read(deviceChannelsProvider))` before `applyJson`, and migrate sites #7, #15-#24 onto it. Delete the hardcoded `id:0`. For the background isolate (#29), persist resolved channel ids next to the autopilot config so the isolate builds `buildParticipatingSegArray`.
2. **Class 2:** replace ad-hoc `WledService('http://$ip')` loops with a repository-level fan-out over `activeAreaControllerIpsProvider` so it works over relay; until then, label LAN-only paths in the UI.
3. **Class 3:** land CHANNEL_MAPPING_AUDIT Addendum 1's read-side reconciliation + dashboard cache warm-up.
4. **Class 5:** source the sync start instant from the server `startedAt` + a whole-second-boundary begin rule.
5. **Class 4 / 6:** wire the dormant teardown/post-event executor; wire `updateControllerIps()` or mark the real-game celebration "coming soon"; hide the Design Studio preview toggle.

**Sequencing:** Class 1 first (broadest, silent, multi-bus install base) → Class 3 (removes the cache dependency Class 1b leans on) → Class 2 → Class 5 → Class 4/6.

---

*End of Audit 1. READ-ONLY. No code modified, no commits. Sites tagged "(sub-agent; verify)" were enumerated by parallel exploration and should be opened first-hand before any fix lands.*
