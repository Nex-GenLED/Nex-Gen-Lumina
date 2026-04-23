# Bridge Phase 1 — App-Side Audit

**Scope:** Identify Flutter app assumptions that will break when the ESP32 bridge firmware ships without its three hardcoded defaults (`WIFI_SSID`/`WIFI_PASSWORD`, `FIREBASE_USER_UID = "Empwc9bf..."`, `pairedWledIp = "192.168.50.91"`).

**Method:** Read-only grep + targeted file reads. No edits.

---

## STEP 1 — Hardcoded-literal scan

### `grep "192.168.50.91" lib/`

| File:line | Classification | Notes |
|---|---|---|
| [lib/features/audio/services/audio_capability_detector.dart:168](lib/features/audio/services/audio_capability_detector.dart#L168) | 🟢 CLEAN | Doc-comment example (`/// Usage: ref.watch(audioCapabilityProvider('192.168.50.91'))`). Non-functional. |
| [lib/features/site/bridge_setup_screen.dart:121](lib/features/site/bridge_setup_screen.dart#L121) | 🔴 BLOCKER | **Live default.** `_doPair()` passes `ref.read(selectedDeviceIpProvider) ?? '192.168.50.91'` as the WLED target IP to the bridge's `/api/bridge/pair` endpoint. If no WLED has been discovered yet, the app sends `192.168.50.91` to every bridge it pairs. |
| [lib/features/site/bridge_setup_screen.dart:479](lib/features/site/bridge_setup_screen.dart#L479) | 🔴 BLOCKER | **Live default.** Same fallback in `_buildPairStep()` — the "Controller Target" row displays `192.168.50.91` to the installer as the value that will be sent. This is visible UI text, not a hint. |

**Note on the flagged file:** The SUBMISSION_AUDIT's concern was correct. `bridge_setup_screen.dart` has two `?? '192.168.50.91'` fallbacks (lines 121, 479) — both are live defaults, not placeholder hints. The TextField at line 455 uses `192.168.1.100` as a benign `hintText` for manual IP entry — that one is fine.

### `grep "Empwc9bf" lib/`

No matches. Good — the homeowner UID is not referenced anywhere in app code.

### `grep "bridge@lumina.local" lib/`

| File:line | Classification | Notes |
|---|---|---|
| [lib/services/user_service.dart:598](lib/services/user_service.dart#L598) | 🟡 WARNING | Default value of `bridgeEmail` parameter to `saveBridgeConfig()`. Stored in Firestore as `bridge_email` field so security rules can grant the bridge's auth principal access. Not a Phase 1 blocker (bridge still uses this shared service account), but is the secrets-hygiene concern flagged in the plan. |
| [lib/features/site/bridge_setup_screen.dart:146-147](lib/features/site/bridge_setup_screen.dart#L146-L147) | 🟡 WARNING | `_doPair()` hardcodes `email: 'bridge@lumina.local'`, `password: 'bridge@lumina.local'` in the POST body to `/api/bridge/auth`. On the firmware side (`handleBridgeAuth`, main.cpp:348-352), the endpoint is a **no-op stub** that always returns 200 without reading the body — the real credentials come from `config.h`. So app-side this does nothing functional, but it's still a plaintext credential in client code. |
| [lib/features/site/bridge_setup_screen.dart:215](lib/features/site/bridge_setup_screen.dart#L215) | 🟢 CLEAN | Error message string referencing the email by name. No functional dependency. |

### `grep "Nexgen"` / `"Nexgen365"` in lib/

No matches. Good.

---

## STEP 2 — Bridge API call-site audit

Only **one** call site per bridge endpoint exists in the app. All paths go through [lib/services/bridge_api_client.dart](lib/services/bridge_api_client.dart), invoked from [lib/features/site/bridge_setup_screen.dart](lib/features/site/bridge_setup_screen.dart).

### `/api/bridge/pair` — [bridge_api_client.dart:124-147](lib/services/bridge_api_client.dart#L124-L147)

| Aspect | Finding |
|---|---|
| (a) Call site | [bridge_setup_screen.dart:129-132](lib/features/site/bridge_setup_screen.dart#L129-L132), invoked from `_doPair()` |
| (b) Payload — `userId` | `FirebaseAuth.instance.currentUser!.uid` ([bridge_setup_screen.dart:118-130](lib/features/site/bridge_setup_screen.dart#L118-L130)) — correct, uses the real signed-in user |
| (b) Payload — `wledIp` | `ref.read(selectedDeviceIpProvider) ?? '192.168.50.91'` ([bridge_setup_screen.dart:121](lib/features/site/bridge_setup_screen.dart#L121)) — 🔴 **sends hardcoded IP when no WLED selected** |
| (c) 4xx/5xx handling | `pair()` returns `bool` based on `statusCode == 200`. Any non-200 (or network error, or timeout) collapses to `false`. The UI surfaces a generic `'Pair request failed. Check the bridge is reachable.'` ([bridge_setup_screen.dart:139](lib/features/site/bridge_setup_screen.dart#L139)) — no distinction between 400 (bad payload), 403 (auth), 500 (bridge error), or timeout. This is lossy but not a blocker. |
| (d) Bridge IP source | mDNS lookup via [lib/services/bridge_discovery_service.dart](lib/services/bridge_discovery_service.dart) (queries `_lumina._tcp.local` → falls back to `_http._tcp.local` containing "lumina" → falls back to `lumina.local` hostname lookup). User can also enter IP manually. |

### `/api/bridge/auth` — [bridge_api_client.dart:149-170](lib/services/bridge_api_client.dart#L149-L170)

| Aspect | Finding |
|---|---|
| (a) Call site | [bridge_setup_screen.dart:145-148](lib/features/site/bridge_setup_screen.dart#L145-L148) |
| (b) Payload | `email: 'bridge@lumina.local'`, `password: 'bridge@lumina.local'` — hardcoded in client. Firmware ignores the body (stub handler) so this is a no-op. |
| (c) 4xx/5xx handling | Returns `bool`. Treated identically to pair failure — generic error message. |
| (d) N/A | Same bridge IP as `/api/bridge/pair` |

### `/api/info` — [bridge_api_client.dart:90-105](lib/services/bridge_api_client.dart#L90-L105)

| Aspect | Finding |
|---|---|
| (a) Call site | [bridge_setup_screen.dart:90](lib/features/site/bridge_setup_screen.dart#L90), in `_selectBridge()` after user picks a discovery result |
| (b) Payload | GET — no payload |
| (c) 4xx/5xx handling | Returns `BridgeInfo?`. `null` on any failure. UI shows `'Could not reach $ip — is the bridge powered on?'` ([bridge_setup_screen.dart:96](lib/features/site/bridge_setup_screen.dart#L96)). Acceptable. |

### `/api/bridge/status` — [bridge_api_client.dart:107-122](lib/services/bridge_api_client.dart#L107-L122)

| Aspect | Finding |
|---|---|
| (a) Call site | [bridge_setup_screen.dart:189, 274](lib/features/site/bridge_setup_screen.dart#L189) — only called during the Verify step |
| (b) Payload | GET — no payload |
| (c) 4xx/5xx handling | Returns `BridgeStatus?`. UI handles `null`, `paired==false`, and `authenticated==false` separately with distinct error messages ([bridge_setup_screen.dart:194-220](lib/features/site/bridge_setup_screen.dart#L194-L220)). This is the **best-handled endpoint** in the flow. |

### `/api/bridge/reset`

**No matches.** 🟡 The firmware exposes `POST /api/reset` ([main.cpp:274](esp32-bridge/src/main.cpp#L274)) and the Dart client wraps it as `BridgeApiClient.reset()` ([bridge_api_client.dart:184-194](lib/services/bridge_api_client.dart#L184-L194)), but **nothing in the app UI currently calls it.** Dealers have no in-app way to factory-reset a bridge they've already paired.

### mDNS hostname pattern (`lumina-[hex]` / `*.local`)

- mDNS service type: `_lumina._tcp.local` ([bridge_discovery_service.dart:26](lib/services/bridge_discovery_service.dart#L26))
- Fallback hostname: `lumina.local` ([bridge_discovery_service.dart:91](lib/services/bridge_discovery_service.dart#L91))
- **Potential Phase 1 concern:** the firmware broadcasts hostnames like `lumina-87ec.local` (deviceName lowercased, per main.cpp:247-258). The app's fallback list only contains `lumina.local` — not `lumina-<mac>.local`. This is fine when mDNS service discovery succeeds, but a weakness if only the A-record path works. Not Phase 1 related; pre-existing.

---

## STEP 3 — Blank-bridge handling (post-Phase 1 scenarios)

### (a) Bridge appears on network, never paired (`isPaired == false`)

**Flow:**
1. `bridgeDiscoveryServiceProvider.discover()` returns the endpoint via mDNS
2. User taps it → `_selectBridge()` → `/api/info` succeeds → step advances to Pair
3. `_doPair()` sends userId + wledIp → bridge stores → returns 200
4. `/api/bridge/auth` stub → returns 200
5. Verify step calls `/api/bridge/status` → `paired=true, authenticated=true` → Firestore round-trip → success

✅ **Handled correctly.** This is the happy path the wizard was designed for.

### (b) Bridge appears, was paired, NVS wiped → looks like case (a) to bridge, but user profile still says `bridge_paired=true`

**Flow:**
1. User's Firestore profile has `bridge_paired=true`, `bridge_ip=<old IP>`
2. Remote Access screen displays "**Reconfigure** Bridge" button ([remote_access_screen.dart:835](lib/features/site/remote_access_screen.dart#L835))
3. If user runs wizard → behaves as case (a). Firestore is re-written with the new IP and `bridge_paired=true` stays true. ✅
4. **If user does NOT run wizard** → app routes commands via `CloudRelayRepository` ([wled_providers.dart:217-230](lib/features/wled/wled_providers.dart#L217-L230)) which writes to `/users/{uid}/commands`. The bridge, having no `pairedUserId` in NVS, **will not poll that collection**. Commands silently never execute.

🔴 **Gap:** The app has no startup-time health check that queries `/api/bridge/status` to verify the bridge's NVS pairing matches the profile's `bridge_paired`. Nothing surfaces "your bridge says it is unpaired, please re-run setup." The only UI indicator is the "Paired Bridge" card ([remote_access_screen.dart:844-853](lib/features/site/remote_access_screen.dart#L844-L853)), which reads from the profile, not from the bridge.

**Severity:** Medium. Not a v1.0.0 blocker (factory resets are rare and the dealer re-runs setup). But worth a Phase 2 follow-up: health indicator in Remote Access screen that pings the bridge's `/api/bridge/status` and warns if `paired=false` while profile says otherwise.

### (c) Bridge appears, already paired to a DIFFERENT user

**Flow:**
1. mDNS returns the bridge endpoint
2. `_selectBridge()` calls `/api/info` — returns basic device info, NO userId field in the response ([bridge_api_client.dart:26-34](lib/services/bridge_api_client.dart#L26-L34))
3. **App does not call `/api/bridge/status` before advancing to Pair step.** It never reads the current `userId` to check for ownership.
4. `_doPair()` POSTs the new userId → firmware `handleBridgePair` ([main.cpp:313-346](esp32-bridge/src/main.cpp#L313-L346)) **unconditionally overwrites** the stored userId. No verification, no challenge.
5. Wizard completes, bridge is now bound to the new user, old user's commands silently stop flowing.

🔴 **Gap — hijack risk.** If an installer points the wizard at a neighbor's bridge on the same subnet, or at a previously-deployed customer bridge that was factory-flashed elsewhere, the wizard silently re-pairs it. No confirmation, no warning. The firmware currently has no secret/challenge to prevent this.

**Severity:** Medium. Not exploited in practice today because bridges have unique mDNS hostnames (mac-derived), and the dealer picks by name. But for commercial installs in multi-tenant buildings, this is a real concern.

**Mitigation options (Phase 2):**
- App: call `/api/bridge/status` in `_selectBridge()`, show a confirmation dialog if `paired==true && userId != currentUser.uid` ("This bridge is already paired to another account. Hijack it? [Yes/No]")
- Firmware: require a "reset" or "unpair" before a second pair attempt, OR require a physical button press during pairing
- Both (defense in depth)

### (d) Bridge fails to appear (mDNS timeout)

**Flow:**
1. `_startDiscovery()` completes with empty `_bridges` list ([bridge_setup_screen.dart:74](lib/features/site/bridge_setup_screen.dart#L74))
2. UI shows `'No bridges found on this network.'` + "Scan Again" button ([bridge_setup_screen.dart:395-413](lib/features/site/bridge_setup_screen.dart#L395-L413))
3. Manual IP entry card is always visible as fallback ([bridge_setup_screen.dart:433-471](lib/features/site/bridge_setup_screen.dart#L433-L471))

✅ **Handled correctly.**

---

## STEP 4 — Existing dealer installs / migration risk

**Question:** Does the app have any fast-path logic that skips `/api/bridge/pair` and assumes the bridge is pre-paired with the hardcoded `Empwc9bf...` UID?

**Answer:** No.

Searched for:
- References to the hardcoded UID → zero matches in `lib/`
- Logic that routes around the pair wizard → none found. The only path to set up a bridge is through `bridgeSetup` route ([remote_access_screen.dart:827](lib/features/site/remote_access_screen.dart#L827)), which always executes all three wizard steps.
- Client-side assumption that bridges are "factory paired" → none.

The app's runtime command path ([wled_providers.dart:194-230](lib/features/wled/wled_providers.dart#L194-L230)) selects a repository based on:
- Connectivity (local vs remote)
- `userProfile.remoteAccessEnabled`
- `userProfile.mqttRelayEnabled`
- Presence of `userId` and `controllerId`

**None of these depend on any hardcoded bridge value.** The CloudRelayRepository writes to `/users/{uid}/commands`, which the bridge will poll if and only if its NVS-stored `pairedUserId == uid`.

**Migration path for existing deployed bridges:**
- Old firmware (hardcoded UID) → old firmware keeps working unchanged
- Old firmware → reflashed with new firmware but wizard never re-run → bridge boots with empty NVS, silently stops servicing commands. Dealer must run the wizard again. **This is a rollout operations concern, not an app-side bug.**

✅ **No 🔴 BLOCKER migration logic exists in the app.**

---

## STEP 5 — Summary

### Findings count

| Severity | Count | Items |
|---|---|---|
| 🔴 BLOCKER | 3 | (1) bridge_setup_screen.dart:121 — hardcoded `192.168.50.91` fallback sent to bridge on pair; (2) bridge_setup_screen.dart:479 — same IP shown in UI as target; (3) Step 3(c) hijack risk — wizard unconditionally overwrites an already-paired bridge's userId with no ownership check |
| 🟡 WARNING | 4 | (1) `/api/bridge/reset` has no in-app caller → dealers can't factory reset from the app; (2) `bridge@lumina.local` credentials hardcoded in app (secrets hygiene, not a functional issue because the endpoint is a stub); (3) Step 3(b) — no health check to surface NVS-wiped bridges; (4) mDNS fallback only tries `lumina.local`, not `lumina-<mac>.local` |
| 🟢 CLEAN | 2 | Doc comment in audio_capability_detector.dart; error-message string mentioning the bridge email |

### Must-patch before v1.0.0 submission?

**Yes — at minimum, the two 🔴 BLOCKERs in bridge_setup_screen.dart (lines 121 and 479).** These break the install flow on any new deployment where the dealer hasn't already selected a WLED controller IP in the app — they would silently pair the bridge to `192.168.50.91` (your home's IP), not the customer's WLED. Fix: require a controller to be selected before enabling the Pair button, or collect WLED IP as an explicit wizard field, rather than silently falling back to a hardcoded string.

The third 🔴 (Step 3(c) hijack risk) is medium-severity and probably acceptable for v1.0.0 if documented, but worth a follow-up in Phase 2 given commercial-install scenarios.

### Worth cleaning up in the same submission window?

- **Yes:** Expose the `BridgeApiClient.reset()` already-wrapped method behind a "Factory reset bridge" button on the Remote Access screen. Small change; unblocks support flows.
- **Yes:** Differentiate error messages in `_doPair()` and `_doAuth()` by HTTP status — currently all non-200 responses collapse to the same generic string. Cheap to fix, improves support triage.
- **Probably not (defer):** Post-pair health check, mDNS fallback expansion, credential cleanup — all fine as Phase 2 work after v1.0.0 ships.

### Recommended app-side changes for Phase 1 parity

1. **[BLOCKER]** Remove the `?? '192.168.50.91'` fallbacks at [bridge_setup_screen.dart:121, 479](lib/features/site/bridge_setup_screen.dart#L121). Require the installer to pick a WLED controller before the Pair step enables, OR add a dedicated IP field to the wizard.
2. **[BLOCKER]** In `_selectBridge()`, call `/api/bridge/status` before advancing to the Pair step. If `paired==true && userId != currentUser.uid`, show an "already paired to another account" confirmation dialog before proceeding.
3. **[WARNING]** Wire `BridgeApiClient.reset()` into the Remote Access screen as a "Factory Reset Bridge" action, guarded by a confirmation dialog.

No code was modified. This report is the only artifact.
