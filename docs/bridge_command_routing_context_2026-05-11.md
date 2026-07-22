# Bridge / Remote-Access / Command Routing — Context Snapshot

**Date:** 2026-05-11
**Branch:** submission/app-store-v1
**Purpose:** Context-load for the action-command remote-routing fix. No code changes proposed here.

---

## 1. Recent commit history (chronological, oldest first)

Key commits touching bridge / remote-access / command routing:

| Hash | Subject |
|---|---|
| `60a5f2b` | feat(bridge): Phase 1 — ship blank, pair at install time |
| `8e26579` | feat(bridge): persist pairing to NVS so bridges deploy without per-customer firmware |
| `4782483` | feat(bridge): tighten /api/bridge/auth to validate userId |
| `36a2b8f` | feat: server-side fanout for sync and game day — **bridge-aware command dispatch via applySyncPattern Cloud Function**, fixes home-LAN-only limitation |
| `e41983c` | build(functions): commit applySyncPattern compiled output |
| `cfd3236` | fix(setup): manual bridge IP dialog and location-permission recovery |
| `4c78580` | fix(bridge): harden setup against saving controller IP as bridge IP |
| `3c3f49e` | fix: bridge_email written correctly during pairing |
| `891d12e` | fix(remote-access): refresh bridge status after pairing wizard returns |
| `1644e36` | fix: remove debugBridgePing diagnostic from production remote access screen |
| `b50b60d` | feat(bridge): Firestore-driven discovery+pairing — no same-WiFi requirement |
| `e29a354` | feat(bridge): Firestore-backed BridgeDiscoveryService + BridgeInfo.deviceId |
| `904f772` | feat(rules): bridge_registry self-registration + pairing-request rules |
| `1d4a18c` | feat(firmware): bridge self-registers in Firestore + handles app pairing |
| `0a954af` | fix: split /json/cfg into two POSTs, set Content-Length to fix 413 on WLED Ethernet builds |
| `678c00a` | merge: audit sprint + bridge self-registration |
| `3753d6a` | chore(firmware): delete obsolete Arduino lumina_bridge firmware |
| `def327e` | chore(cleanup): remove abandoned MQTT relay subsystem (firmware + Flutter) |
| `97549a3` | **fix(bridge): tighten isPaired check to require NVS-stored UID, not compile-time default** (Item #47) |

---

## 2. Bridge firmware state (esp32-bridge/src/main.cpp, 1308 lines)

**Firmware version:** `BRIDGE_FIRMWARE_VERSION "1.2"` ([main.cpp:54](esp32-bridge/src/main.cpp#L54)). Also self-reported in `/api/info` ([main.cpp:381](esp32-bridge/src/main.cpp#L381)) and `/bridge_registry/{deviceId}.firmwareVersion`.

### Local HTTP endpoints (port 80, [main.cpp:365-376](esp32-bridge/src/main.cpp#L365-L376))
- `GET  /api/info` — name, version, ip, mdns, deviceId, pairingSource (`nvs` vs `default`), bridgeEmail
- `GET  /api/bridge/status` — paired, authenticated, wifi, userId, wledIp, commands, errors, uptime
- `POST /api/bridge/pair` — body `{userId, wledIp}` — writes to NVS, sets `isPaired=true`
- `POST /api/bridge/auth` — body `{userId}` — 200 if paired UID matches, 403 if different account
- `POST /api/reboot`, `POST /api/reset`

### Firestore subscription (NOT streaming — polled)
`pollCommands()` ([main.cpp:686](esp32-bridge/src/main.cpp#L686)) runs every `POLL_INTERVAL_MS` (defined in config.h). Uses **runQuery** REST with a structured query:

```
SELECT * FROM users/{pairedUserId}/commands WHERE status == "pending" LIMIT MAX_COMMANDS_PER_POLL
```

Auth: Bearer `firebaseIdToken` (signed in via email/password to `FIREBASE_AUTH_EMAIL`/`FIREBASE_AUTH_PASSWORD` at boot, refreshed before expiry).

### Command dispatch logic ([main.cpp:766-846](esp32-bridge/src/main.cpp#L766-L846))

```cpp
if (commandType == "ping")    → updateCommandStatus("completed"); return;
if (commandType == "getState") endpoint = "/json/state"; method = "GET";
if (commandType == "getInfo")  endpoint = "/json/info";  method = "GET";
else                           endpoint = "/json/state"; method = "POST";
                               body = convertFirestorePayloadToJson(fields);
```

**Critical observation:** the bridge's switch is `getState` / `getInfo` / else-POST-/json/state. **There is no separate `setState` or `applyJson` case** — anything not ping/getState/getInfo falls through to `POST /json/state` with the payload. So `setState`, `applyJson`, `applyToSegments`, `renameSegment`, `loadPreset`, `savePreset`, `configureSyncReceiver`, etc. all become `POST /json/state`. `applyConfig` would also become `POST /json/state` — the bridge does **not** route `applyConfig` to `/json/cfg`. (Functions/index.js webhook path *does* route applyConfig to /json/cfg — [functions/index.js:373-376](functions/index.js#L373-L376) — so there's a divergence in payload semantics between Webhook Mode and Bridge Mode for `applyConfig`.)

### Result writeback ([main.cpp:932-977](esp32-bridge/src/main.cpp#L932-L977))
`updateCommandStatus(commandId, status, error, result)` PATCHes `/users/{uid}/commands/{commandId}` with an updateMask. Stores `result` as a **stringValue** containing the raw WLED response body. Adds `completedAt` timestamp when status is `completed` or `failed`.

### Item #47 fix (closed, committed `97549a3`)
NVS pairing hardening: `isPaired` now requires `nvsUidFound && pairedUserId.length() > 0` ([main.cpp:185](esp32-bridge/src/main.cpp#L185)), not just non-empty `FIREBASE_USER_UID`. `nvsUidFound` is set via `prefs.isKey("uid")` ([main.cpp:176](esp32-bridge/src/main.cpp#L176)) — distinguishes "value present in NVS" from "value defaulted from compile-time macro." Surfaced via `/api/info.pairingSource`. Prevents the orphan-pairing class of bug.

### Registry self-registration ([main.cpp:1069-1178](esp32-bridge/src/main.cpp#L1069-L1178))
- `registerBridgeInRegistry()` — full doc write at boot, PATCH `/bridge_registry/{deviceId}` with deviceId, deviceName, apName, bridgeEmail, ip, status, pairedUid, pendingUid, firmwareVersion, lastSeen, rssi, heap, freeHeap, flashSize.
- `updateRegistryHeartbeat()` — every 30s, refreshes lastSeen, ip, rssi, heap, freeHeap, status, pairedUid only. (deviceId, apName, bridgeEmail, firmwareVersion immutable.)
- `pollPairingRequest()` ([main.cpp:1180](esp32-bridge/src/main.cpp#L1180)) — while unpaired, polls own registry doc every 5s for `pendingUid != "" AND status == "pairing"`. On match: persists UID to NVS, sets `isPaired=true`, PATCHes registry status="paired".
- Watchdog: 5-minute reboot if no successful Firestore activity ([main.cpp:273](esp32-bridge/src/main.cpp#L273)).

### Bridge heartbeat / bridge_status doc ([main.cpp:983-1024](esp32-bridge/src/main.cpp#L983-L1024))
`writeHeartbeat()` PATCHes `/users/{uid}/bridge_status/current` every 30s with: uptime, ip, commands, errors, version, wifi, heap. **It does NOT touch the `result` field anywhere.** This matches Item #52's framing — the heartbeat doc has no rolling "last-command-result" field, only counters and identity.

---

## 3. App command dispatch architecture

### Repository selector ([lib/features/wled/wled_providers.dart:129-217](lib/features/wled/wled_providers.dart#L129-L217))

`wledRepositoryProvider` returns:

| Condition | Repository |
|---|---|
| Demo mode / reviewer | `DemoWledRepository` |
| No selected device IP | `null` |
| Connectivity stream loading (no last-known) | `null` |
| `ConnectivityStatus.offline` | `null` |
| `ConnectivityStatus.local` | **`WledService('http://$ip')`** (direct HTTP) |
| `ConnectivityStatus.remote` + userId + controllerId | **`CloudRelayRepository`** (Firestore relay) |
| Remote but no userId/controllerId | `null` |

The provider is reactive — when connectivity flips local↔remote, the repository instance is swapped under all callers.

### Connectivity detection ([lib/services/connectivity_service.dart](lib/services/connectivity_service.dart))

`_checkConnectivity()`:
1. `connectivity_plus.checkConnectivity()` → if no connection, `offline`.
2. If no WiFi (cellular only), `remote`.
3. If WiFi, read SSID via `network_info_plus.getWifiName()` and compare hashed SSID against user profile's `homeSsidHash` ([connectivity_service.dart:62](lib/services/connectivity_service.dart#L62)).
4. **If SSID unavailable (Android location permission denied), assume `local`** ([connectivity_service.dart:75](lib/services/connectivity_service.dart#L75)). This default favors LAN HTTP and is documented in `feedback_connectivity_defaults.md`.

Polling cadence: emit on subscribe, then every 10s. Cache invalidates on app resume via `refreshConnectivityStatus(ref)`.

### Cloud relay implementation ([lib/features/wled/cloud_relay_repository.dart](lib/features/wled/cloud_relay_repository.dart))

`_executeCommand(type, payload)` ([cloud_relay_repository.dart:59](lib/features/wled/cloud_relay_repository.dart#L59)):
1. Build `RemoteCommand` doc with `type`, `payload`, `controllerId`, `controllerIp`, `webhookUrl`, `status: pending`.
2. `_commandsRef.add(command.toFirestore())` — writes to `/users/{uid}/commands/{auto-id}`.
3. `_waitForCompletion(commandId)` — polls the doc every 500ms for up to **30s**.
4. Returns `command.result` if `status == completed`, else null.

`BridgeDiag` instrumentation ([cloud_relay_repository.dart:79-99](lib/features/wled/cloud_relay_repository.dart#L79-L99)) attaches a `snapshots()` listener that logs every status transition with elapsed-ms — visible in `flutter logs` as `BridgeDiag: doc status changed → executing at 412ms` etc. Useful for the upcoming fix.

### Action-command paths in the app

| Caller | Path |
|---|---|
| `WledNotifier.togglePower / setBrightness / setColor / setWarmWhite / setSpeed` ([wled_providers.dart:670-893](lib/features/wled/wled_providers.dart#L670-L893)) | → `_postUpdate` → `service.setState(...)` or `service.applyJson(...)` via `ref.read(wledRepositoryProvider)` |
| `repo.applyJson(payload)` (~50 call sites across `lib/`: audio, voice, scenes, designs, autopilot, patterns, sports alerts, commercial events, neighborhood sync, AI adjustment, edit pattern, pattern adjustment, colorway selector, schedule autopilot…) | → goes through `wledRepositoryProvider` → same routing |
| `BridgeHealthService.check(...)` ([lib/services/bridge_health_service.dart:42](lib/services/bridge_health_service.dart#L42)) | Direct `commands.add({type:'ping', ...})` — Firestore-only, bypasses the repository selector |
| `RemoteAccessScreen._checkBridge()` ([lib/features/site/remote_access_screen.dart:288](lib/features/site/remote_access_screen.dart#L288)) | Direct `commands.add({type:'getInfo', ...})` — Firestore-only |
| `BridgeSetupScreen` Test Bridge button ([lib/features/site/bridge_setup_screen.dart:617](lib/features/site/bridge_setup_screen.dart#L617)) | Direct `commands.add({type:'ping', ...})` — Firestore-only |
| `applySyncPattern` Cloud Function ([functions/src/applySyncPattern.ts](functions/src/applySyncPattern.ts)) | Server-side fanout — enqueues one `type:'applyJson'` command per target controller |

**Background worker paths that go through `applySyncPattern`:**
- `GameDayAutopilotBackgroundWorker` ([lib/features/autopilot/game_day_autopilot_background_worker.dart:497](lib/features/autopilot/game_day_autopilot_background_worker.dart#L497))
- `SyncEventBackgroundWorker` ([lib/features/neighborhood/services/sync_event_background_worker.dart:724](lib/features/neighborhood/services/sync_event_background_worker.dart#L724))
- `SyncBgQuick` (base-pattern refresh) ([lib/features/neighborhood/services/sync_event_background_worker.dart:994](lib/features/neighborhood/services/sync_event_background_worker.dart#L994))

These were the original motivation for `applySyncPattern` (commit `36a2b8f`) — background isolates have no Firebase SDK, so they `http.post` to the callable's HTTPS endpoint.

### Webhook Mode fallback (functions/index.js executeWledCommand, [functions/index.js:300-429](functions/index.js#L300-L429))

If a command doc has `webhookUrl != ""`, the `executeWledCommand` Firestore trigger executes it server-side by HTTP-POSTing to the user's webhook URL. If `webhookUrl == ""`, the trigger logs "ESP32 Bridge Mode: Skipping" and exits — the bridge picks the doc up via its `runQuery` poll.

Switch table (Webhook Mode only — bridge has its own):
- `getState`/`getInfo` → GET `${baseUrl}/json/state` or `/json/info`
- `setState`, `applyJson`, `configureSyncReceiver`, `configureSyncSender`, `renameSegment`, `applyToSegments`, `savePreset`, `loadPreset` → POST `${baseUrl}/json/state`
- `applyConfig` → POST `${baseUrl}/json/cfg` ← **bridge firmware does NOT honor this distinction**

---

## 4. Command types in use

| Type | Written by | Bridge handling | Webhook handling |
|---|---|---|---|
| `getState` | `CloudRelayRepository.getState`, `WledNotifier._pollOnce`, polling timer | GET /json/state | GET /json/state |
| `getInfo` | `CloudRelayRepository.supportsRgbw / getTotalLedCount`, `RemoteAccessScreen` bridge-test | GET /json/info | GET /json/info |
| `setState` | `CloudRelayRepository.setState` (via `_postUpdate` legacy single-segment path) | POST /json/state | POST /json/state |
| `applyJson` | `CloudRelayRepository.applyJson` (via `_postUpdate` multi-channel path, all `repo.applyJson()` call sites, `applySyncPattern` Cloud Function) | POST /json/state | POST /json/state |
| `applyConfig` | `CloudRelayRepository.applyConfig` | POST /json/state ⚠ | POST /json/cfg |
| `configureSyncReceiver` / `configureSyncSender` | `CloudRelayRepository.configureSync*` | POST /json/state | POST /json/state |
| `renameSegment` / `applyToSegments` / `updateSegmentConfig` | `CloudRelayRepository.*` | POST /json/state | POST /json/state |
| `savePreset` / `loadPreset` | `CloudRelayRepository.*` | POST /json/state | POST /json/state |
| `ping` | `BridgeHealthService`, `BridgeSetupScreen` Test button | Acknowledge only, no WLED call | — (handled by bridge in bridge mode) |
| `power` | `google-home/functions/index.js`, `functions/index.js:1308` (Alexa/legacy integrations) | POST /json/state (fallthrough) | POST /json/state |

Every type the app sends in remote mode is **cloud-only with no LAN fallback**; every type the app sends in local mode is **LAN-only with no cloud fallback**. The repository selector swaps the entire implementation — there is no per-call try-LAN-then-cloud retry. The fallback is purely network-classification-based.

---

## 5. Known fixes in place (with commit references)

- **Item #47 — orphan-UID pairing fix:** `97549a3` — bridge requires NVS-stored UID, not compile-time default. NVS handling lives in [main.cpp:170-194](esp32-bridge/src/main.cpp#L170-L194); `nvsUidFound` flag at [main.cpp:39](esp32-bridge/src/main.cpp#L39).
- **MQTT subsystem removed:** `def327e` — Cleanup of abandoned firmware/Flutter MQTT relay.
- **Arduino lumina_bridge deleted:** `3753d6a` — obsolete firmware removed; `esp32-bridge/` is canonical (PlatformIO, despite README quirks per Item #42).
- **Server-side fanout for sync/game-day:** `36a2b8f` — `applySyncPattern` Cloud Function added so background workers (no Firebase SDK) can dispatch commands via HTTPS POST.
- **Bridge IP keyboard occlusion + schedule time formatting** (`a4a7604`) — UX fixes, unrelated to routing.
- **WLED /json/cfg 413 split** (`0a954af`) — large config payloads split into two POSTs.
- **Bridge auth UID validation** (`4782483`) — `/api/bridge/auth` validates UID match, returns 403 on mismatch.
- **Firestore-driven discovery + pairing** (`b50b60d`, `e29a354`, `904f772`, `1d4a18c`) — replaces same-WiFi requirement; bridge_registry rules; `BridgeDiscoveryService` reads `/bridge_registry/{deviceId}`.
- **Remote polling guard** (`wled_providers.dart:333`) — `_polling` boolean prevents concurrent getState calls in remote mode (where each takes up to 30s, and a 1.5s timer would otherwise pile up ~20 concurrent calls).
- **Remote-mode post-command delay:** [wled_providers.dart:884](lib/features/wled/wled_providers.dart#L884) — 3000ms wait in remote mode (vs 150ms local) before polling after a write, so the bridge has time to clear its queue.
- **3-failure remote downgrade:** [wled_providers.dart:344-348](lib/features/wled/wled_providers.dart#L344-L348) — after 3 consecutive remote getState timeouts, `bridgeReachableProvider` flips to false so the UI shows offline.

---

## 6. Known open items / drift

- **Item #38 — `clearRemoteAccessConfig` non-atomic:** [user_service.dart:619](lib/services/user_service.dart#L619) — single `update()` with multiple `FieldValue.delete()` and writes; not in a transaction or batch. Open.
- **Item #52 — bridge heartbeat doesn't refresh result field periodically:** Heartbeat at [main.cpp:983](esp32-bridge/src/main.cpp#L983) writes uptime/ip/commands/errors/version/wifi/heap — no result snapshot. v1.0.1 firmware candidate. Open.
- **applyConfig payload routing divergence (this audit):** Bridge firmware POSTs all non-getState/getInfo/ping types to `/json/state`, including `applyConfig` which Webhook Mode correctly routes to `/json/cfg`. Bridge Mode users may be silently misrouting timer/config writes. Not yet filed as an Item.
- **No LAN/Cloud fallback per call:** The repository selector is whole-instance switching based on a 10-second-polled `ConnectivityStatus`. If classification is wrong (e.g., a brief stream-loading gap, an SSID-permission flap, a flaky WiFi association where the phone is on the home SSID but cannot reach the controller), commands fail with no automatic retry on the other path. The fallback to "last-known status" at [wled_providers.dart:159-166](lib/features/wled/wled_providers.dart#L159-L166) covers the loading gap but not the misclassification case.

### Closed (verified in code)
- **Bug 1 — bridge UID orphan-pairing:** Closed by `97549a3` (Item #47). `isPaired = nvsUidFound && pairedUserId.length() > 0` at [main.cpp:185](esp32-bridge/src/main.cpp#L185).
- **applySyncPattern Cloud Function wired:** Both [game_day_autopilot_background_worker.dart:497](lib/features/autopilot/game_day_autopilot_background_worker.dart#L497) and [sync_event_background_worker.dart:724](lib/features/neighborhood/services/sync_event_background_worker.dart#L724) POST to `${_functionsBaseUrl}/applySyncPattern`. Compiled output at `functions/lib/applySyncPattern.js`. Wired for **background workers only** — foreground user actions still go through the repository selector (LAN or cloud relay).

---

## 7. Production symptom — relevant data points for the upcoming fix

Symptom: off-home-wifi, action commands (power/apply/brightness) don't reach the bridge; getState round-trips successfully through cloud relay.

Relevant facts assembled from the code:

1. **Both getState and action commands go through the same `_executeCommand` path** in `CloudRelayRepository` ([cloud_relay_repository.dart:59-127](lib/features/wled/cloud_relay_repository.dart#L59-L127)). If getState round-trips successfully (status: completed, result populated), the Firestore write path, the bridge poll, the WLED HTTP call, and the result writeback are all working. That tells us the underlying transport works for at least one command type.

2. **Action commands diverge from getState in payload shape, not transport.** `setState` builds a `{on, bri, seg:[{...}]}` payload; `applyJson` passes through `normalizeWledPayload(...)`. Both POST to /json/state on the WLED side via the bridge. If they were being written to Firestore, the bridge would attempt them.

3. **The two foreground paths that write commands directly (not via the repository) — `BridgeHealthService` and `RemoteAccessScreen` — both write Firestore-only and use `ping`/`getInfo`.** They explicitly bypass the connectivity check. If these work but the repository path doesn't, the discrepancy is in the repository selector, not in the bridge.

4. **The repository selector is reactive.** If `wledConnectivityStatusProvider` is in loading or briefly returns `local` while the user is off-wifi (e.g., during app resume, or due to the SSID-unavailable→local default for unconfigured users), `wledRepositoryProvider` returns `WledService('http://$ip')`. `WledService` does not write to Firestore — it makes a direct HTTP call which will fail silently (timeout) from cellular without writing any doc anywhere. The user sees nothing happen.

5. **Confirm via flutter logs at action-command time:** The `RepositoryInit:` debug print at [wled_providers.dart:133, 143, 150, 169, 175, 192, 202, 214](lib/features/wled/wled_providers.dart#L133) emits the repository selection on each rebuild; `🔍 BridgeRouter:` emits the connectivity classification each tick. Expected pattern when action commands route correctly off-wifi: `selected=CloudRelayRepository, network=remote, hasControllerId=<id>`. Anything else (selected=WledService, selected=null) explains the symptom.

6. **`BridgeDiag:` instrumentation at [cloud_relay_repository.dart:79-99](lib/features/wled/cloud_relay_repository.dart#L79-L99)** will confirm whether action commands are reaching Firestore at all. If `command written → docId=...` appears, the command was queued. If `30s timeout — document never acknowledged by bridge` appears, the bridge isn't polling it (filter mismatch, auth, or different user UID). If no log appears at all, the action handler isn't reaching `_executeCommand` (repository selection issue).

---

## 8. Suggested first diagnostic step (no code changes)

Reproduce off-wifi, capture `flutter logs`, and look for:

- `RepositoryInit: selected=...` lines at the moment of the failed action — confirms which repository the action got.
- `🔍 BridgeRouter: isOnHomeNetwork=...` lines on the surrounding 10-second cadence — confirms classification.
- `BridgeDiag: command written` (or its absence) on each action tap — confirms whether the command reached Firestore.

Those three signals localize the bug to (a) classification, (b) repository selection, or (c) bridge poll/dispatch.
