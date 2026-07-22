# Hardcoded Identifier Audit — 2026-05-08

**Branch:** `submission/app-store-v1`
**Status:** READ-ONLY audit. No code changes.
**Trigger:** Item #44 (Dynamic device identifiers required) follow-up; confirms whether Item #47 (bridge `FIREBASE_USER_UID` orphan default) was a unique instance or representative of a broader class.

## Executive summary

**Verdict: clean.** No (C) ORPHAN-RISK or (D) SECRET findings beyond legitimate constants and known-by-design choices. Item #47 was the unique hardcoded-UID instance in the codebase; the previously-flagged blockers from `docs/submissions/BRIDGE_PHASE1_APP_AUDIT.md` (`bridge@lumina.local` client credentials, `?? '192.168.50.91'` IP fallbacks in `bridge_setup_screen.dart`) are also resolved — none of those patterns exist in current code. **Item #44 closes clean** with no follow-up implementation work.

Two minor defense-in-depth concerns surfaced (firmware dead-code line, CLAUDE.md doc drift), neither audit-blocking.

## Methodology

Search patterns executed against `lib/`, `esp32-bridge/`, `functions/src/`, and `scripts/`:

| Pattern | Purpose |
|---|---|
| `FIREBASE_USER_UID\|USER_UID\|HARDCODED.*UID\|DEFAULT.*UID\|PAIRED.*UID` | Item #47 sister-bug detection |
| `Empwc9bf\|"[A-Za-z0-9]{28}"` | Specific orphan UID + Firebase-UID-shaped strings |
| `DEALER_CODE\|INSTALLER_CODE\|MASTER_INSTALLER\|INSTALLER_PIN\|installer_pin` | Hardcoded installer/dealer credentials |
| `[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:.*` | MAC address literals |
| `API_KEY\|SECRET_KEY\|PRIVATE_KEY\|OAUTH_SECRET\|CLIENT_SECRET` | Credentials in source |
| `192\.168\.50\.\|192\.168\.1\.\d\|10\.0\.0\.\d+` | Hardcoded local IPs |
| `bridge@example\.local\|bridge@lumina\.local\|bridge@.*\.local` | Hardcoded bridge service-account credentials |
| `honeycutt\|honeycutt\.tylerg` | Test-account email leakage |
| `hardcoded\|HARDCODED\|TODO.*remove.*before\|FIXME.*launch` | Self-flagged tech debt |

Each match was classified into one of four categories defined by the audit prompt: (A) false positive, (B) legitimate constant, (C) orphan-risk, (D) secret in source.

## Findings

### (A) FALSE POSITIVE — 5 matches

| Match | File:line | Why false positive |
|---|---|---|
| `installerPin = '/installer/pin'` | [lib/app_router.dart:1140](lib/app_router.dart#L1140) | Route path constant, not a credential |
| `final ip = '192.168.1.123';` (BLE stub) | [lib/features/ble/provisioning_service.dart:52, 256](lib/features/ble/provisioning_service.dart#L52), [lib/features/ble/device_setup_page.dart:352](lib/features/ble/device_setup_page.dart#L352) | Gated behind `kIsWeb \|\| kSimulationMode`. `kSimulationMode = false` in production ([lib/app_providers.dart:14](lib/app_providers.dart#L14)) — dead-code path on real devices |
| `currentLightingState`, `clarificationOptions` (20-char strings) | functions/src/ | Field names matched the 20-28 char regex; not UID-shaped |
| `// hardcoded …` comments | 8 files in lib/ | Documentation comments; usually warning *against* hardcoding or describing legitimate compile-time fallbacks |
| `convertFirestorePayloadToJson` (function name match) | esp32-bridge/src/main.cpp | Identifier longer than 28 chars matched by accident; not a UID literal |

### (B) LEGITIMATE CONSTANT — 8 matches

| Match | File:line | Justification |
|---|---|---|
| `'192.168.50.1'` socket-connect probe | [lib/features/discovery/device_discovery.dart:38](lib/features/discovery/device_discovery.dart#L38) | iOS local-network permission prompt trigger. Comment at line 30-34 explains: socket attempt is *expected to fail*; only the side effect (permission prompt) is needed. Any local-shaped IP would do |
| `'192.168.1.100'` `hintText` | 5 files (`ip_entry_sheet.dart`, `wled_manual_setup.dart`, `controller_setup_screen.dart`, `settings_page.dart`, etc.) | UI placeholder text in TextField widgets; not a runtime value |
| `'192.168.50.91'` doc comment example | [lib/features/audio/services/audio_capability_detector.dart:168](lib/features/audio/services/audio_capability_detector.dart#L168) | `/// Usage: …` doc-comment example. Non-executable |
| `reviewerEmail = 'reviewer@Nex-GenLED.com'` | [lib/services/reviewer_seed_service.dart:18](lib/services/reviewer_seed_service.dart#L18) | App Store reviewer login email — by design. Class-level comment lines 13-16 explicitly states the design: seed under the *signed-in* user's Auth UID, not a hardcoded UID |
| `reviewerInstallationId = 'reviewer-installation-001'` | [lib/services/reviewer_seed_service.dart:19](lib/services/reviewer_seed_service.dart#L19) | Stable installation doc ID for predictable demo state across reviewer sessions. Auth UID is still per-user and dynamic |
| `#define FIREBASE_USER_UID "USER_UID_HERE"` | [esp32-bridge/src/config.h.example:25](esp32-bridge/src/config.h.example#L25) | Template file; gitignored real `config.h` overrides. With Item #47 fix at `main.cpp:185`, even a non-empty placeholder default cannot cause a fresh device to claim paired |
| `#define DEFAULT_WLED_IP "192.168.1.100"` | [esp32-bridge/src/config.h.example:49](esp32-bridge/src/config.h.example#L49) | Compile-time fallback overridden by NVS after first pair. Comment at line 45-47 documents this clearly |
| `bridge@example.local` Firebase Auth email | [esp32-bridge/src/config.h.example:30](esp32-bridge/src/config.h.example#L30) | Template placeholder; gitignored real `config.h` has the actual service-account credentials. Authorization is enforced at Firestore rule layer (rule grants access only when `bridgeEmail` field in user profile matches), not by per-bridge auth account |

### (C) ORPHAN-RISK — 0 matches

**No findings.** Specific verifications:

1. **Item #47 fix is robust.** [esp32-bridge/src/main.cpp:185](esp32-bridge/src/main.cpp#L185): `isPaired = nvsUidFound && pairedUserId.length() > 0;` — overrides the legacy line-163 set. `nvsUidFound = prefs.isKey("uid");` (line 176) precisely distinguishes "NVS-stored UID" from "compile-time default fallback". Even if `config.h` ships with a non-empty `FIREBASE_USER_UID` placeholder, fresh devices with no NVS entry correctly report `isPaired = false`.

2. **No `Empwc9bf` orphan UID anywhere in source.** Only audit-doc references in `docs/submissions/BRIDGE_PHASE1_APP_AUDIT.md`. The orphan UID has been purged from the codebase.

3. **No `?? '192.168.50.91'` fallbacks in `bridge_setup_screen.dart`.** The blockers documented in `BRIDGE_PHASE1_APP_AUDIT.md` lines 14-19 are resolved. Current line 121 is a `Navigator.pop(false)` button handler; current line 479 is a `loadFromBridgeRegistry` doc comment. The IP-fallback patterns those line numbers used to point at no longer exist.

4. **No `bridge@lumina.local` client-side credentials in `lib/`.** The hardcoded client credential pattern documented in `BRIDGE_PHASE1_APP_AUDIT.md:30` and flagged as a 🟡 WARNING is no longer present. Only matches are audit doc, firestore rules comment, and the gitignored config template.

5. **No hardcoded MAC addresses anywhere.** Only match: `WiFi.macAddress(mac);` at [esp32-bridge/src/main.cpp:146](esp32-bridge/src/main.cpp#L146) — runtime read of the device's own MAC, not a hardcoded value.

6. **No hardcoded dealer codes or installer PINs as values.** The `5502` PIN known from memory does not appear as a string literal anywhere in `lib/` (zero matches). All `dealerCode` references are field names on data models or Firestore rule helpers — that's the correct architecture (dealer code is per-record data, not a baked-in constant).

7. **No 28-char UID-shaped string literals in `lib/` or `esp32-bridge/src/`.** Quoted-form regex (`"[A-Za-z0-9]{28}"`) returned zero matches in production code.

### (D) SECRET — 0 matches

**No findings.** All credential management uses environment-variable injection or Firebase Functions secret parameters:

| Credential | Location | Mechanism |
|---|---|---|
| `ANTHROPIC_API_KEY` | functions/src/ (multiple) | `defineString("ANTHROPIC_API_KEY")` Firebase Functions secret + `process.env.ANTHROPIC_API_KEY` runtime read |
| `OPENAI_API_KEY` | [functions/index.js:85](functions/index.js#L85) | `defineString("OPENAI_API_KEY")` |
| `ALEXA_CLIENT_SECRET`, `GOOGLE_CLIENT_SECRET` | [functions/index.js:89, 93](functions/index.js#L89) | `defineString(...)` |
| `RESEND_API_KEY` | [functions/index.js:101](functions/index.js#L101) | `defineString(...)` |
| `BRANDFETCH_API_KEY` | [scripts/seed_brand_library.js:129](scripts/seed_brand_library.js#L129) | `process.env.BRANDFETCH_API_KEY` with explicit error if unset |
| `FIREBASE_API_KEY` (bridge) | [esp32-bridge/src/config.h.example:18](esp32-bridge/src/config.h.example#L18) | Macro defined in gitignored `config.h`. Note: Firebase API keys for client-side use are publishable identifiers, not secrets — restricted by Firebase Security Rules + App Check |
| Firebase config keys (Flutter) | [lib/firebase_options.dart](lib/firebase_options.dart) | Generated by `flutterfire configure`; publishable client identifiers (same caveat as bridge `FIREBASE_API_KEY`) |
| Bridge Firebase Auth password | gitignored `config.h` | Template placeholder `"PASSWORD_HERE"` in `config.h.example`. Real value never enters source control |

## Defense-in-depth concerns (not blocking)

These are not audit findings under (A)/(B)/(C)/(D) but worth noting for separate cleanup:

### 1. Firmware dead-code at `main.cpp:163` (LOW)

```cpp
// Mark as paired if a user UID is configured
isPaired = (strlen(FIREBASE_USER_UID) > 0);
```

This is the legacy buggy line that Item #47 fixed by adding the line-185 override. The line-163 set is mooted by the line-185 reassignment before any consumer reads `isPaired`, so functionally it's dead. But it conveys the wrong intent to a future maintainer. A refactor that moves the pair-check logic earlier in `setup()` could reintroduce the Item #47 bug class.

**Recommendation:** delete line 163 in a follow-up firmware cleanup. Not urgent. ~5 min change + reflash to verify.

### 2. `CLAUDE.md` is stale on `kSimulationMode` (LOW)

CLAUDE.md says (current text):

> `kSimulationMode` constant in [lib/app_providers.dart](lib/app_providers.dart):
> - Currently hardcoded to `true`
> - Bypasses permission prompts and uses virtual devices for web preview

Actual value at [lib/app_providers.dart:14](lib/app_providers.dart#L14): `const bool kSimulationMode = false;`

**Recommendation:** correct CLAUDE.md to reflect `kSimulationMode = false` (production default) in a follow-up doc commit. Not a code bug.

## Item #44 closure

> [Item #44 — Dynamic device identifiers required (memory)](memory/project_dynamic_device_identifiers.md): Tyler's 2026-05-07 directive — no hardcoded bridge IDs, device IDs, or account tokens in app or firmware; pairing must be reversible without reflash. Audit of identifier-handling code deferred.

This audit deferred-work is now complete:
- **No hardcoded bridge IDs** in firmware (`main.cpp:155 deviceId = String(idBuf)` — runtime-generated from MAC)
- **No hardcoded device IDs** in client code
- **No hardcoded account tokens** in client code (BLE creds removed; bridge auth creds in gitignored config)
- **Pairing is reversible without reflash** (NVS-based UID storage with `prefs.remove("uid")` factory-reset path; firmware behavior verified at `main.cpp:185` line-by-line)

**Status:** Item #44 closes clean. No additional fix work scheduled.

## Item #47 closure (already-closed — confirmation)

> [Item #47 — Bridge FIREBASE_USER_UID default bug (FIXED) (memory)](memory/project_bridge_firebase_uid_default_fix.md): Fixed 2026-05-07 in commit `97549a3`.

This audit confirms Item #47 was a unique instance, not representative of a broader class. The pattern (compile-time identifier default leaking into runtime pairing claims) does not exist elsewhere in the codebase. **Item #47 closure verified.**

## Estimated session count

**Zero sessions for fix work.** Audit closes Item #44 with no follow-up.

Optional cleanup (separate workstreams, post-launch):
- Firmware dead-code line removal (`main.cpp:163`): ~5 min + reflash
- CLAUDE.md `kSimulationMode` doc correction: ~5 min, no code change

Both can be bundled into the next firmware/docs commit with no dedicated session needed.
