# ESP32 Firmware Audit — Inventory Only

**Date:** 2026-05-07
**Branch:** `submission/app-store-v1`
**Status:** READ-ONLY audit — no files deleted, no code changed.
**Purpose:** Tyler-facing inventory before any cleanup decisions.

---

## Summary

| Metric | Count |
|---|---|
| Firmware source trees found | **3** |
| Active (canonical) | 1 — `esp32-bridge/` |
| Legacy / orphan | 1 — `firmware/lumina_bridge/` |
| Unknown — needs Tyler input | 1 — `esp32-mqtt-bridge/` |
| Removal candidates (no evidence of use) | 0 — none recommended without Tyler sign-off |
| Phantom directory referenced in docs but not present | 1 — `lumina-firmware/` |

The compiled `firmware.bin` build artifacts under each project's `.pio/build/` are **gitignored** (local-only). The only firmware artifacts under git control are the source files (`*.cpp`, `*.h.example`, `*.ino`, `platformio.ini`, `README.md`) — 16 tracked files total across the three projects.

---

## Inventory Table

| Path | Type | Version (in source) | Source last modified | Last commit touching it | Tracked in git? | Referenced by app/docs? | Classification |
|---|---|---|---|---|---|---|---|
| [esp32-bridge/](../esp32-bridge/) | PlatformIO project (Firestore polling) | **v1.2** ([main.cpp:54](../esp32-bridge/src/main.cpp#L54)) | `main.cpp` 2026-05-04, `config.h` 2026-05-01 | `1d4a18c feat(firmware): bridge self-registers in Firestore + handles app pairing` | Yes (5 files) — `.pio/` ignored | Yes — flash command in `docs/submissions/TEST_PROTOCOL_PHASE1.md`; line refs in `docs/submissions/BRIDGE_PHASE1_APP_AUDIT.md`; companion to `lib/services/bridge_api_client.dart` | **✅ Active** |
| [firmware/lumina_bridge/](../firmware/lumina_bridge/) | Arduino INO (Firestore polling, mobizt lib) | **v1.0.0** ([lumina_bridge.ino:77](../firmware/lumina_bridge/lumina_bridge.ino#L77)) | All files 2026-01-16 | `16705ab Initial commit: Nex-Gen Lumina v1.6` (only) | Yes (3 files) | **No code, script, or doc** references this path. Never modified after initial import. | **🟡 Legacy** |
| [esp32-mqtt-bridge/](../esp32-mqtt-bridge/) | PlatformIO project (HiveMQ MQTT relay) | **v1.0** ([README.md:106](../esp32-mqtt-bridge/README.md#L106)) | `main.cpp` 2026-01-19, `config.h` 2026-04-30 | `36a2b8f security: remove committed credentials from bridge firmware` (only post-import touch) | Yes (7 files including `package*.json`, `test-bridge.js`) | **App side has live MQTT path** (`MqttRelayRepository`, gated by `userProfile.mqttRelayEnabled`). **No backend service in this repo** publishes to HiveMQ. **No docs** reference this dir. | **❓ Unknown** |
| `lumina-firmware/` | (referenced but **does not exist**) | — | — | — | — | Referenced in `esp32-bridge/README.md` lines 3, 9, 29, 31 and `docs/ESP32_Bridge_Setup_Guide.md:78` as the "current recommended" firmware | **⚠️ Stale doc references** |

### Per-project file detail

**`esp32-bridge/`** (active)
```
esp32-bridge/
├── README.md              2,067 B   2026-04-16   ⚠️ refers to non-existent lumina-firmware/
├── platformio.ini           962 B   2026-02-03
├── .gitignore                94 B   2026-02-03   (ignores .pio/)
└── src/
    ├── main.cpp          41,553 B   2026-05-04   ← v1.2, BRIDGE_FIRMWARE_VERSION
    ├── config.h           3,315 B   2026-05-01   (gitignored — credentials)
    └── config.h.example   3,225 B   2026-04-30
.pio/build/esp32dev/firmware.bin   1,126,256 B   2026-05-04   (gitignored build artifact)
```

**`firmware/lumina_bridge/`** (legacy)
```
firmware/lumina_bridge/
├── README.md              6,677 B   2026-01-16
├── lumina_bridge.ino     12,645 B   2026-01-16   ← v1.0.0, Firebase ESP Client (mobizt)
└── config_template.h      1,966 B   2026-01-16
```
No `.pio/`, no compiled binary. This is an Arduino IDE-style sketch, not a PlatformIO project.

**`esp32-mqtt-bridge/`** (unknown)
```
esp32-mqtt-bridge/
├── README.md              6,654 B   2026-01-19
├── platformio.ini         1,176 B   2026-01-19
├── package.json              50 B   2026-01-19
├── package-lock.json     19,489 B   2026-01-19
├── test-bridge.js         2,552 B   2026-01-19
├── nul                       54 B   2026-01-19   (stray Windows null-redirect file)
├── .gitignore                94 B   2026-01-18
└── src/
    ├── main.cpp          15,492 B   2026-01-19   ← v1.0, HiveMQ Cloud MQTT
    ├── config.h           4,145 B   2026-04-30   (gitignored — credentials)
    └── config.h.example   3,898 B   2026-04-30
.pio/build/esp32dev/firmware.bin   1,061,808 B   2026-01-20   (gitignored build artifact)
```

---

## Active firmware (canonical for current installs)

**`esp32-bridge/` — v1.2.** Evidence:

1. **Recent and frequent commits.** 12 commits in git history, latest is `1d4a18c feat(firmware): bridge self-registers in Firestore + handles app pairing`. Phase-1 work is tagged at `v1.0.0-firmware-phase-1` (commit `60a5f2b8`, 2026-04-22, "feat(bridge): Phase 1 — ship blank, pair at install time").
2. **Live flash command in test protocol.** `docs/submissions/TEST_PROTOCOL_PHASE1.md:26` runs `pio.exe run --project-dir esp32-bridge --target upload --upload-port COM17`.
3. **Tightly coupled to live app code.** `docs/submissions/BRIDGE_PHASE1_APP_AUDIT.md` cites `esp32-bridge/src/main.cpp:274` and `:313-346`, paired with `lib/services/bridge_api_client.dart`. The Flutter `BridgeApiClient` calls the firmware's `/api/info`, `/api/bridge/auth`, `/api/bridge/pair`, `/api/reset` endpoints defined in this firmware.
4. **Architectural fit.** Firestore polling + REST Auth + NVS pairing matches the in-app `CloudRelayRepository` path (`lib/features/wled/wled_providers.dart:217-229`).

This is the firmware Tyler is actually building and flashing.

---

## Legacy: `firmware/lumina_bridge/` (Arduino INO)

- Single Arduino sketch, hardcoded credentials, uses the third-party **mobizt Firebase ESP Client** library (heavy dependency).
- The `esp32-bridge/` PlatformIO project supersedes it conceptually (same Firestore-polling architecture, modern REST Auth, NVS persistence, web wizard, mDNS pairing).
- **Zero references** in `lib/`, `functions/`, `scripts/`, or `docs/`. Not imported in any build script, test protocol, or setup guide.
- Untouched since the 2026-01-13 initial commit.

Strong evidence this is the early prototype that was rewritten as `esp32-bridge/`. Likely safe to remove, but Tyler should confirm.

---

## Unknown: `esp32-mqtt-bridge/`

This is the one that warrants a real decision before any action.

**Arguments it's still live:**
- Flutter app actively wires up `MqttRelayRepository` ([wled_providers.dart:200-214](../lib/features/wled/wled_providers.dart#L200-L214)) as remote-access path #6, gated on `userProfile.mqttRelayEnabled` and `luminaBackendUrl`.
- `lib/services/lumina_backend_service.dart` is a complete HTTPS client targeting a remote "Lumina Backend" service that publishes to HiveMQ.
- The user model has `mqtt_relay_enabled` and `lumina_backend_url` fields ([user_model.dart:434-435, 588-589](../lib/models/user_model.dart#L434)).
- `config.h` was updated 2026-04-30 (same day as the credential-cleanup commit) — someone touched it recently, even if `main.cpp` hasn't moved.

**Arguments it's dormant:**
- Only 2 commits in firmware git history: initial import + the security cleanup (`36a2b8f security: remove committed credentials from bridge firmware, add config.h.example templates`) — that commit was a sweep across both bridge dirs, not a feature change.
- `main.cpp` last modified 2026-01-19 — over 3 months stale.
- **No Cloud Function, no script, no doc** in this repo references HiveMQ, MQTT relay, or the `esp32-mqtt-bridge/` path.
- The "Lumina Backend" service the firmware talks to is not in this repo (presumably hosted elsewhere). Without that backend, the firmware can't function.
- Phase 1 work has consolidated on the Firestore bridge — `docs/submissions/TEST_PROTOCOL_PHASE1.md` mentions only `esp32-bridge/`.

**The deciding question for Tyler:** Is the HiveMQ/Lumina-Backend MQTT relay path still being used by any customer, or is it dead code that has not yet been removed from the app?

---

## Stale documentation references

`esp32-bridge/README.md` (lines 3, 9, 29, 31) and `docs/ESP32_Bridge_Setup_Guide.md` (line 78) point customers/installers at a `lumina-firmware/` directory that **does not exist** in the repo.

The Setup Guide is a customer-facing PDF source — it instructs flashing from a folder that's not there, and references a `pio run -t uploadfs` filesystem upload that the actual `esp32-bridge/` project's `platformio.ini` doesn't appear to set up. **This is a docs bug independent of the firmware audit**, but worth flagging here because cleanup of the firmware tree should not happen without also fixing these docs.

---

## Removal candidates (with evidence)

**None recommended without Tyler sign-off.** The `firmware/lumina_bridge/` tree has the strongest evidence for removal (zero references, 4-month-stale, single-file Arduino sketch with a heavy library dep that the active firmware doesn't use), but Tyler should explicitly approve before any deletion.

`esp32-mqtt-bridge/` should not be touched until the dead-code question above is answered.

---

## Open questions for Tyler

1. **Was `firmware/lumina_bridge/lumina_bridge.ino` the prototype that became `esp32-bridge/`?** If yes, can it go? (Strong evidence it can; want explicit confirmation.)
2. **Is the HiveMQ MQTT relay path (`esp32-mqtt-bridge/` + `MqttRelayRepository` + `LuminaBackendService`) still a live install option?**
   - If yes — where does the "Lumina Backend" service live, and which customers have `mqttRelayEnabled = true`?
   - If no — the entire MQTT chain (firmware tree + repository class + service + user-model fields) should be removed together, and that's a multi-file cleanup, not just a firmware deletion.
3. **The `lumina-firmware/` directory referenced in `esp32-bridge/README.md` and `docs/ESP32_Bridge_Setup_Guide.md` is missing.**
   - Was it never created? Renamed to `esp32-bridge/`? Lost to a wipe? Independent of the audit, the docs need fixing.
4. **Stray file:** `esp32-mqtt-bridge/nul` (54 bytes) is a Windows accident — likely from a `command > nul` redirect run from inside that folder. Safe to delete regardless of the larger decision.

---

## Recommended next step

Tyler reviews this document, answers questions 1–3 above, then a *targeted* cleanup prompt is written that deletes ONLY the items Tyler explicitly approves. No bulk action.
