# ESP32 Bridge — Phase 1 Hardware Test Protocol

**Branch:** `firmware/phase-1-provisioning-persistence`
**Goal:** Verify the bridge ships blank, pairs via app at install time, and persists pairing across power cycles.

Run this protocol on a test bridge before committing the Phase 1 branch. All 9 steps must pass.

---

## Prerequisites

- ESP32 bridge with CP2102 or CH340 USB-to-serial
- Physical access (USB cable, serial monitor)
- A second Wi-Fi network you can control (for provisioning — **not** the production home network)
- A phone/laptop that can switch Wi-Fi
- Lumina app running on a signed-in test account
- `/c/Users/honey/.platformio/penv/Scripts/pio.exe` available

---

## Step 0 — Flash Phase 1 firmware to a factory-blank bridge

1. Plug bridge into USB. Note the COM port (e.g. `COM17`).
2. From repo root:
   ```bash
   /c/Users/honey/.platformio/penv/Scripts/pio.exe run --project-dir esp32-bridge --target upload --upload-port COM17
   ```
3. Open serial monitor:
   ```bash
   /c/Users/honey/.platformio/penv/Scripts/pio.exe device monitor --port COM17 --baud 115200
   ```
4. **If this is a previously-paired bridge:** hit `POST /api/bridge/reset` from a browser or curl, or hold down the EN button for a full reflash — the goal is an NVS-blank starting state.

---

## Step 1 — Captive portal appears when unconfigured

**Expected serial output on boot:**
```
   Lumina ESP32 Bridge v1.2
Device name: Lumina-XXXX
Pairing state: UNPAIRED — waiting for /api/bridge/pair
Setting up WiFi...
No WiFi credentials configured — starting captive portal
Connect to AP: Lumina-XXXX
Captive portal started
```

**Verification:**
- [ ] Serial log shows `UNPAIRED — waiting for /api/bridge/pair`
- [ ] Serial log shows `starting captive portal` (NOT `Connecting to <SSID>`)
- [ ] Scanning nearby Wi-Fi networks from a phone shows an open AP named `Lumina-XXXX`

**Fail criteria:** bridge auto-connects to any network, or no AP appears.

---

## Step 2 — WiFi provisioning via captive portal

1. Connect your phone to the `Lumina-XXXX` AP.
2. Captive portal should auto-open. If not, browse to `192.168.4.1`.
3. Pick your test Wi-Fi network, enter password, submit.

**Expected serial output:**
```
Connected! IP: 192.168.x.x
mDNS started: lumina-xxxx.local
HTTP server started on port 80
Setting up Firebase connection...
```

**Verification:**
- [ ] Bridge reports a valid IP on the test Wi-Fi
- [ ] mDNS hostname is `lumina-<mac-suffix>.local`
- [ ] Captive portal AP disappears after successful connect

**Fail criteria:** bridge reboot-loops, can't get an IP, or mDNS fails to start.

---

## Step 3 — Firebase sign-in runs WITHOUT Firestore polling

This is the key Phase 1 behavior: auth can happen, but no command polling until paired.

**Expected serial output:**
```
Firebase Auth: signed in successfully
Bridge initialized and ready!
```

…and then silence. The loop's `if (firebaseReady && isPaired && ...)` gate should suppress any poll activity.

**Verification:**
- [ ] `Firebase Auth: signed in successfully` appears
- [ ] **No** `Polling Firestore` / `Fetched N commands` log lines
- [ ] Bridge stays up at least 60s without rebooting (watchdog does not fire because `lastSuccessfulPoll` stays at 0 — this is expected for an unpaired bridge)

**Fail criteria:** bridge attempts Firestore polls with an empty userId (would generate 4xx spam).

---

## Step 4 — HTTP server + mDNS discovery

From a laptop on the same test Wi-Fi:

```bash
curl http://lumina-xxxx.local/api/info
```

**Verification:**
- [ ] Response returns 200 with JSON
- [ ] JSON contains `name`, `version`, `type`, `ip`, `mdns`, `ap` fields
- [ ] **JSON does NOT contain `savedSSID`** (Phase 1 info-disclosure fix)

**Fail criteria:** `savedSSID` present, or endpoint unreachable.

---

## Step 5 — `/api/bridge/status` reports unpaired

```bash
curl http://lumina-xxxx.local/api/bridge/status
```

**Verification:**
- [ ] `paired: false`
- [ ] `userId: ""`
- [ ] `wledIp: ""`
- [ ] `wifi: true`
- [ ] `authenticated: true` (Firebase auth succeeded in Step 3)

**Fail criteria:** `paired: true` on a factory-flashed bridge (indicates leftover NVS state).

---

## Step 6 — Pair via Lumina app → NVS write

1. On the phone running Lumina, open **Remote Access** → **Set Up Bridge**.
2. Let mDNS discovery find `Lumina-XXXX`, tap it.
3. Confirm the "Controller Target" row shows a **real** WLED IP (not `192.168.50.91` — the app-side fallback is gone in Phase 1). If it shows "None selected — set up a controller first", back out, pick a controller in Site Setup, then return.
4. Tap **Pair Bridge**. Watch the serial log.

**Expected serial output:**
```
Paired with user: <firebase-uid>
WLED target: 192.168.x.x
Pairing written to NVS
```

**Verification:**
- [ ] Serial log shows `Pairing written to NVS`
- [ ] `curl http://lumina-xxxx.local/api/bridge/status` now returns `paired: true` with the correct userId and wledIp
- [ ] Wizard advances to Verify step and the Firestore round-trip succeeds

**Fail criteria:** Pair succeeds but `paired` stays false, or NVS write never logs.

---

## Step 7 — Power cycle → pairing persists

1. Unplug USB for 10 seconds.
2. Reconnect USB. Let the bridge boot fully.

**Expected serial output on boot:**
```
Device name: Lumina-XXXX
Pairing state: PAIRED (user=<first-8-chars>..., wledIp=<ip>)
Setting up WiFi...
Connecting to <your-test-ssid>       # auto-reconnect via saved WiFiManager creds
...
Firebase Auth: signed in successfully
```

**Verification:**
- [ ] Pairing state is `PAIRED` on boot (NVS persistence works)
- [ ] Bridge reconnects to same Wi-Fi without captive portal
- [ ] Firestore polling resumes (send a test command from the app — it should execute)

**Fail criteria:** bridge reverts to `UNPAIRED` or captive portal after reboot.

---

## Step 8 — `/api/bridge/reset` returns bridge to blank

> **Important:** Step 8 requires a **stable Wi-Fi environment** to test cleanly. The endpoint needs a working LAN connection to the bridge long enough to complete an HTTP POST — the noisy 2.4 GHz environment flagged under "Known Pre-Existing Issues" will block the round-trip.
>
> **Do not use an iPhone Personal Hotspot as the test network.** iPhone hotspots auto-shut-off after ~90s when no device is actively connected, and the ESP32 will drop the AP during WiFiManager's scan-to-connect gap (`NO_AP_FOUND`). Confirmed failure mode during Phase 1 development — spent significant session time troubleshooting.
>
> **Recommended test networks:** a stable home Wi-Fi on a different AP from the known-flaky one, a dedicated 2.4 GHz test router, or an Android hotspot (does not have the auto-sleep behavior).
>
> If `/api/bridge/reset` cannot be verified end-to-end in the available RF environment, the code path is still trustworthy — `wm.resetSettings()` is a single-line call to a documented library method. Mark as "code-complete, runtime-deferred" and move on.

```bash
curl -X POST http://lumina-xxxx.local/api/bridge/reset
```

**Expected serial output:**
```
Factory reset requested — clearing NVS + WiFi creds
```

Bridge should reboot within a few seconds.

**After reboot:**

**Verification:**
- [ ] Serial shows `Pairing state: UNPAIRED` again
- [ ] Captive portal AP `Lumina-XXXX` re-appears (WiFi creds were erased)
- [ ] `/api/bridge/status` (once reconnected to test Wi-Fi) shows `paired: false`, empty userId

**Fail criteria:** bridge reboots but keeps old Wi-Fi creds, or NVS retains pairing.

---

## Step 9 — Re-pair with a DIFFERENT user triggers the app dialog

1. On a second test phone, sign in to Lumina with a **different** test account.
2. First, re-complete Steps 1–6 from the first account so the bridge is paired to User A.
3. Without resetting the bridge, on the second phone (User B) open **Remote Access** → **Set Up Bridge**.
4. Let discovery find the bridge. Tap it.

**Expected behavior in app:**
- [ ] After `/api/info` succeeds, app shows a dialog: **"Bridge already paired"** — "This bridge is currently paired to a different Nex-Gen account. Continuing will transfer the bridge to your account and stop service for the previous owner."
- [ ] Tapping **Cancel** returns to the bridge list; no state change.
- [ ] Tapping **Transfer to my account** proceeds. Serial log shows a second `Paired with user:` line with the new UID. `/api/bridge/status` now reports User B's UID.

**Fail criteria:** dialog does not appear (hijack protection broken), or pair silently overwrites without user intent.

---

## Sign-off

- [ ] All 9 steps pass
- [ ] Tester name: ____________________
- [ ] Date: ____________________
- [ ] Test bridge MAC: ____________________
- [ ] Any deviations or notes:

Once all 9 steps are verified on real hardware, the Phase 1 branch is clear to commit. The atomic commit should cover:
- `esp32-bridge/src/config.h` (blanked hardcoded creds)
- `esp32-bridge/src/main.cpp` (NVS persistence, pair-gated polling, /api/bridge/reset factory-reset fix, savedSSID removal)
- `lib/services/bridge_api_client.dart` (reset() URL aligned to /api/bridge/reset)
- `lib/features/site/bridge_setup_screen.dart` (app-side BLOCKER fixes: WLED IP guard, hijack-check dialog)
- `TEST_PROTOCOL_PHASE1.md` (this document)
- `BRIDGE_PHASE1_APP_AUDIT.md` (optional — audit artifact; exclude if not wanted in repo history)

---

## Known Pre-Existing Issues

These are tracked separately from Phase 1 and do **not** invalidate a passing run of this protocol. If you see these symptoms, log them and continue — they are environmental or predate Phase 1.

### WiFi beacon timeout + Firebase TLS handshake failures

**Symptom in serial log:**
```
[W][WiFiGeneric.cpp:1062] _eventCallback(): Reason: 200 - BEACON_TIMEOUT
[W][WiFiGeneric.cpp:1062] _eventCallback(): Reason: 2 - AUTH_EXPIRE
[W][WiFiGeneric.cpp:1062] _eventCallback(): Reason: 203 - ASSOC_FAIL
[E][ssl_client.cpp:37] _handle_error(): ... UNKNOWN ERROR CODE (004C)
[E][WiFiClientSecure.cpp:144] connect(): start_ssl_client: -76
Firebase Auth: FAILED to sign in
```

The bridge associates to the saved AP, then the association drops repeatedly. TLS to `identitytoolkit.googleapis.com` errors out mid-handshake. Firebase Auth sign-in fails. Loop retries on the next poll cycle.

**Status:** Predates Phase 1 — reproduced against the v1.2 firmware before any of these changes landed. Root cause is environmental:
- 2.4 GHz spectrum congestion in the test location, OR
- Router/AP firmware quirk with this MAC address, OR
- Weak signal strength at the bench position

**Not a Phase 1 regression.** No firmware code path introduced or modified in this branch affects WiFi association or TLS handshake behavior.

**Tracked for:** v1.0.1 connectivity-robustness workstream — candidate mitigations include configurable retry/backoff, a fallback to ping-before-TLS, per-channel scan preference, and surfacing a diagnostic endpoint.

### Impact on this protocol

Test steps that depend on Firebase / Firestore **may be flaky in noisy RF environments**:
- **Step 3** — Firebase sign-in confirmation
- **Step 6** — Firestore round-trip during the app's Verify step
- **Step 7** — test command execution after power cycle

If those steps fail *only* in the Firebase/Firestore round-trip portion (not in the NVS/HTTP/pairing portions), re-run on a cleaner RF environment (e.g., 5 GHz test network, or a different physical location) before marking them failed.

Test steps that are **independent of Firebase** and remain fully valid regardless of RF environment:
- **Step 1** — captive portal appears (local only)
- **Step 2** — WiFi provisioning via captive portal (local only)
- **Step 4** — HTTP server + mDNS (LAN only)
- **Step 5** — `/api/bridge/status` response shape (LAN only)
- **Step 6 (partial)** — NVS write by `/api/bridge/pair` — verifiable via `/api/bridge/status` without needing the Firestore round-trip to complete
- **Step 8** — `/api/bridge/reset` clears state (LAN only)
- **Step 9** — hijack-protection dialog (LAN only)

If the RF environment is the problem, the NVS/pairing/reset parts of Phase 1 are still fully verifiable. Record RF-blocked Firebase failures as "environmental, not Phase 1" in the sign-off notes.

