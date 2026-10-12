# WLED firmware versions in the fleet — read-only analysis

*Maintained. Describes build: 2.5.10+116 · Written 2026-10-12 · No controller, bridge, Firestore document, configuration or Drive file was changed to produce this page. Facts it establishes are rows T-F1 to T-F14 in `docs/FACTS.md`; the owner's decision of 2026-10-12 is T-F14.*

The owner's question: can controllers be moved to 0.15.1 without risking their integrity? This page answers what the documents say, what the code expects, what the fleet runs, what changed upstream, how a unit actually moves between versions, and then gives options. It decides nothing and runs nothing. Anything not provable from the repository, the official WLED sources read today, or a recorded bench measurement is marked UNVERIFIED.

## 1. What our own documents say

| Statement | Where | Status |
|---|---|---|
| Controllers run stock WLED. More than one version is in service (older units on one version, units shipped since September on a newer one); every version in service is supported as shipped. | `docs/FACTS.md` T-F1 | FACT (owner 2026-10-08; bench and fleet readings) |
| Installers record the version (controller card in the installer wizard, or `/json/info`) and never flash, update or downgrade a controller. Generic WLED images are never loaded. | `docs/FACTS.md` T-F2; `docs/guides/installer/10-install-checklist.md` (install day, step 2); `docs/guides/installer/13-installer-sop.md` §1.0; `docs/guides/installer/11-controller-setup.md` (Firmware); `docs/guides/dealer/20-dealer-guide.md` ("Can you update my firmware?"); `docs/guides/dealer/21-sales-mode.md` (What to say) | POLICY (owner 2026-10-08) |
| The instruction "pin the controller to one version and flash it via a web flasher" is withdrawn everywhere; no claim is made about what flashing does to a unit. | `docs/FACTS.md` T-F3, T-F4 | POLICY (owner 2026-10-08/09) |
| The versions in service share the same effect list and ids. | `docs/FACTS.md` T-F5 | FACT (upstream comparison 2026-10-02; tracker #167) |
| "Flash the controller", "update the firmware", "pin to version…" and any web-flasher name are banned in guides; versions are written only in FACTS. | `docs/guides/internal/33-claims-policy.md:12`; `scripts/docs_guard.mjs` (banned phrases) | POLICY |

**So: no document names a standard version today.** The only "standard" ever written was the July pin to 0.15.1 (git `9fdad58`, 2026-07-23, "pin WLED 0.15.1 (0.15.4 stall regression)"), withdrawn on 2026-10-09 (git `aad0077`, "firmware is recorded, never flashed"). "Tested" means: the app's effect catalog was verified against a 0.15.1 device (`lib/features/wled/wled_effects_catalog.dart:256–258`), nearly every bench proof in the ledger was taken on the owner's home unit on 0.15.1 (for example `docs/BUILD_LEDGER.md:428, 4830`), and the per-request payload budget was measured on a 0.15.4 unit (`lib/features/wled/per_pixel.dart:20–24`). "Shipped by the vendor": the vendor's current image set is the 0.15.1 to 0.15.4 series plus a "16.0.1" image (§5); which one a new unit arrives with is not recorded anywhere except as T-F1's "units shipped since September on a newer one", and the census below bears that out.

## 2. What the app and the server expect

**No code anywhere branches on the WLED version.** There is no minimum-version constant and no comparison of `ver`, `vid` or `release` (sweep of `lib/`, `functions/`, `test/`, `esp32-bridge/`, 2026-10-12). What exists:

### 2.1 Reading and storing the version

| Where | What |
|---|---|
| `lib/features/wled/wled_service.dart:708–745` | `getInfo()` parses `leds.maxseg`, `arch`, `ver` from `/json/info` and keeps the raw body. |
| `lib/features/installer/screens/controller_setup_screen.dart:493–516, 602–616` | At controller-add the wizard reads `mac`, `ver`, `arch`, `leds.count` and writes the account's controller record with `firmwareVersion` (= `ver`), `ledCount`, `arch`, `mac`, `controller_type`. On a duplicate MAC it updates only `ip`, so `firmwareVersion` is never refreshed (`:558–568`). |
| `lib/features/installer/screens/controller_setup_screen.dart:1092–1100, 755` | Shows "WLED v…" on the controller card and in the mismatch dialog. Display only. |
| `lib/models/controller_model.dart:8–97`; `lib/features/site/controllers_providers.dart:41–51` | Nothing in `lib/` reads `firmwareVersion` back. |
| `functions/src/controllerHealth.ts:175–183, 355–389` | The server's health probe parses `ver`, `vid`, `release`, `leds.count`, `leds.rgbw` from a relayed `getInfo`. |
| `functions/src/collectControllerHealth.ts:286–290` | Writes `wledVersion`, `wledVid`, `wledRelease`, `ledCount`, `rgbw`, `bridgeFirmwareVersion`, `lastProbeAt`, `lastSuccessAt` to the account's `controller_health` record (merge). Version fields are sticky across failed probes. |
| `functions/src/collectControllerHealth.ts:573–588` | The daily `fleet_health` snapshot carries counts and alerts only, no versions. |
| `esp32-bridge/src/main.cpp:818–820, 842, 954–956` | The bridge relays `/json/info` unparsed. |
| `lib/features/wled/wled_service.dart:219–251` | `validateControllerMatch` warns on `maxseg` (fewer than 4 for Skikbily, 8 for Dig-Octa), not on version. |

### 2.2 Behaviours coded to one version's measurement

Every row below is applied to every unit regardless of version. "Measured on" is what the code comment says.

| Dependency | Where | Measured on | What the official notes say changes by 0.15.4 |
|---|---|---|---|
| Timer slots: 8 general, solar in slots 8 and 9, hour 255 as the solar marker, offset limit 120 | `lib/features/schedule/schedule_sync.dart:336–356`; `cfg_payload_builder.dart:11–13`; `lib/features/wled/base_boundary_denormalizer.dart:86–92` | 0.15.1 | Nothing about timers in 0.15.2–0.15.4. `schedule_sync.dart:341–342` warns that a later upstream refactor of the sunrise/sunset encoding would change this; it names no version. UNVERIFIED on 0.15.4 by bench. |
| Timer `en` stored as an int; readback of `timers.ins` is compacted | `schedule_sync.dart:358–373`; `lib/features/schedule/sunrise_off_service.dart:300–316` | 0.15.1 (vid 2507300) | No note. UNVERIFIED on 0.15.4. |
| Preset save applies its state live; `ib:true` gates root `on`; presets 1/3/4/5 read `on` absent; `pdel` can leave erased-flash bytes; a `psave` captures a live `frz` | `schedule_sync.dart:492–506, 596–597, 1106–1134, 1319–1339`; `wled_service.dart:1593–1594, 1609–1640, 1663–1691, 21–33, 1461–1520`; `wled_payload_utils.dart:478–525` | 0.15.1 | 0.15.4 adds "prevent file data loss from replacing an open file handle (protects against presets.json corruption)"; 0.15.2 fixes "brightness factor wrong on save". Whether these change the `ib` / `on` observations is UNVERIFIED. |
| Effect ids 0–186 and the reserved ids; palette 5 = set colours only; the celebration effect list | `lib/features/wled/wled_effects_catalog.dart:256–258, 749, 764–784, 1031–1045`; `lib/shared/wled_segment_defaults.dart:60–73`; `lib/features/design/design_models.dart:769, 793`; `lib/features/patterns/canonical_palettes.dart` (every `suggestedEffects` list) | 0.15.1 | No effect added or renumbered; Twinkle (fx 17) and Tri Fade (fx 56) fixed, so those two look slightly different. T-F5. |
| Every segment write sends `frz:false` because a per-pixel write freezes the segment | `lib/features/wled/wled_payload_utils.dart:721–746` | 0.15.1 | 0.15.4: "unused segments are set to black" on segment writes (#5192); 0.15.2: "don't reset segments if their settings are unchanged" (#4969). Effect on a per-pixel paint sent in several requests is UNVERIFIED (see §6b). |
| Per-pixel chunk of 224 LEDs per request; 4096-byte body cap; shrink-and-retry on HTTP 413 / error 9 | `lib/features/wled/per_pixel.dart:20–26, 45, 49`; `wled_service.dart:918–943, 1059–1125` | 0.15.4 | Measured on the newer version; 0.15.1 proofs use the same chunker throughout the ledger. |
| Gamma block re-written on every configuration write (`light.gc`, `if.live.no-gc` injected) | `lib/features/wled/wled_cfg_gamma.dart:28–46`; `wled_service.dart:1128–1134`; `lib/services/wled_config_pusher.dart:554–558` | 0.15.1 | No note. The injection makes the write safe on either version. |
| One connection per host; explicit Content-Length; split `hw`/`id` configuration writes (listen backlog of 5; chunked POST dropped or 413) | `wled_service.dart:389–399, 424–434, 955–957`; `wled_config_pusher.dart:134–140, 539–544` | "0.15.x" | AsyncWebServer and AsyncTCP updated in 0.15.2; behaviour on 0.15.4 not re-measured. UNVERIFIED. |
| Bus configuration: type 30 (RGBW), colour order RGB, four entries, fallback pins `[16, 3, 1, 4]`; Dig-Octa editor list `[0,1,2,3,4,5,12,13]` | `wled_config_pusher.dart:243–306`; `lib/features/wled/hardware_config_screen.dart:59–60` | both | 0.15.4 Ethernet builds change the default LED pin to 4; only an unconfigured unit is affected, and the app writes pins explicitly. The fallback list is app bug #187 (T-X5). |
| Audio add-on healed to `enabled:false` when it reads `true` | `lib/features/wled/audioreactive_health.dart:1–56, 86–98` | 0.15.1 | 0.15.4 Ethernet builds default audio-reactive to "no mic"; the heal becomes a no-op there. |
| Clock, time zone and coordinates healed from the profile; boot preset `def.ps` read | `lib/features/wled/controller_defaults_healer.dart:262–332`; `lib/features/wled/clock_health.dart:16–26, 199–221` | 0.15.1 | No note. |
| Game Day and the healer compare bus bounds and ids, never pins or versions | `docs/overhaul-2026-10/PHASE5_REPORT.md` (Decision 4); `functions/src/gameDayPlanning.ts:119, 568` | — | A mixed fleet changes nothing here. |
| OTA, flashing, `/update`: nothing. No code path updates a controller. Bridge firmware has no OTA either. | sweep; `lib/features/wled/controller_defaults_healer.dart:45` | — | — |

**Net: moving a unit between 0.15.1 and 0.15.4 changes nothing in how the app addresses it.** What it may change is the outcome of the behaviours above that were measured on one version only; the per-pixel multi-request paint on 0.15.4 is the one with a concrete upstream reason to differ.

## 3. Fleet census (read-only Firestore, 2026-10-12)

Source: every account's controller records (`controller_type`, `firmwareVersion` written at controller-add) and the server's `controller_health` records (`wledVersion`, `wledRelease`, probe times). Counts only; the per-account list was handed to the owner separately and is not in the repository.

| Measure | Count |
|---|---|
| Accounts | 58 |
| Accounts with at least one controller record | 27 |
| Controller rows (controller records, plus 2 health records with no matching controller record) | 29 |
| By type: Skikbily 4-Channel / no type recorded / health-only / QuinLED Dig-Octa | 23 / 3 / 2 / 1 |
| Version recorded at controller-add: 0.15.1 / 0.15.4 / not recorded | 12 / 5 / 12 |
| Version from the server probe: 0.15.1 / 0.15.4 / no health record | 13 / 6 / 10 |
| Release from the server probe: `ESP32_Ethernet` / none | 19 / 10 |
| Best-known version (probe, else add-time): **0.15.1 / 0.15.4 / unknown** | **16 / 6 / 7** |
| Skikbily on 0.15.1 / on 0.15.4 / unknown | 14 / 5 / 4 |
| Dig-Octa on 0.15.4 | 1 (the only Dig-Octa) |
| Add-time version disagreeing with the probe | 0 |
| Of the six 0.15.4 units: probed successfully today / last success 2026-09-25 | 5 / 1 |
| Of the seven unknown-version rows: last probe attempt between 2026-09-23 and 2026-09-29, none ever successful / never probed | 5 / 2 |
| Oldest last-successful probe in the fleet | 2026-08-23 |

The majority is 0.15.1. Every 0.15.4 unit is a September-or-later registration or the Dig-Octa, which matches T-F1. The seven unknowns are units the probe has never reached and that were added before the wizard stored the version.

## 4. What changed upstream, from the official release notes

Read 2026-10-12 from the GitHub releases API and release pages for `wled/WLED`. Years come from the API's `published_at`.

| Release | Published | Items that touch configuration, presets, Ethernet, buses, segments, OTA or security |
|---|---|---|
| 0.15.1 | 2025-07-31 | Prefers the I2S parallel output over RMT (flicker under network load); I2S limits: one chipset type per output, at most 600 LEDs per output. An extra "V4" image for fresh installs only: "do not install this bin via OTA". Advice: "take backups of your configs and presets before you upgrade" and "try on only a few of your devices before pushing to all". |
| 0.15.2 (ESP32 only) | 2025-11-29 | OTA validation (#4999); old-version check in OTA updates (#5058); bootloop detection and recovery (#4840); brightness factor wrong on save fixed (#4827); don't reset segments if unchanged (#4969); dynamic LED type selection (#5084); RMT high-priority interrupt driver (#4980); AsyncWebServer/AsyncTCP updated (#4834); Tri Fade (#4918) and Twinkle (#5007) fixes; version reporting (#5126); DMX conflict (#5097). ESP8266 images withdrawn pending a bug. |
| 0.15.3 | 2025-12-04 | "Basically 0.15.2 plus a hotfix for the esp8266 and GPIO pin 3 issue"; ESP8266 DMA and buffer fixes; audio-reactive crash guard. |
| 0.15.4 | 2026-03-14 | "Fixing a long standing bug that caused corruption when editing your presets": prevent file data loss from replacing an open file handle (partial fix for #5275, protects presets.json); unused segments set to black (#5192); FX checkmark sync (#5241); Wi-Fi scan fix for multi-AP setups (#5359); bootloader SHA fixes (#5410); OTA metadata structure version block removed (#5214); Gledopto Ethernet boards added (#5156); **Ethernet builds: default LED pin 4 and audio-reactive default "no mic" (#5323)**; I2S/aPLL conflict with Ethernet avoided (#5391); release name shown on the Info panel; upgrade reporting UX. |

Not in any of the four notes: anything about downgrading, anything about what an update keeps, anything about the timer or preset JSON format. The `CHANGELOG.md` at the 0.15.4 tag stops at 0.15.0, so the release pages are the only official text for these four.

What the 0.15.2 "old-version check" and "OTA validation" do to an older image is not spelled out in the notes. A source comparison made on 2026-10-02 (session notes, not in the repository) read it as: stock 0.15.4 refuses an image without WLED metadata or with a different release name unless validation is skipped. That reading is UNVERIFIED here.

## 5. How a controller actually moves between versions

**The documented path (kno.wled.ge, read 2026-10-12).** On the controller's own Security settings page: enter the OTA passphrase and untick the OTA lock, save and reboot; open Manual OTA update and upload a release image; re-lock OTA and reboot. If OTA is locked the update page says "OTA lock active". "Only allow update from same network" rejects uploads from another subnet. Factory reset "deletes all custom settings data (passwords, configuration, macros, presets)". Presets and configuration can be downloaded and uploaded as JSON ("restoring overwrites what is on the device; passwords are not backed up"). The documentation does not say what an over-the-air update keeps. The usual WLED behaviour, that an update replaces the program and leaves the file system with cfg.json and presets.json in place, is widely stated in the community but is **UNVERIFIED here**: no repo measurement exists and no unit of ours has been updated by us.

**Which image.** Our units report `release: ESP32_Ethernet` (every probed unit, §3); the matching official image is `WLED_<version>_ESP32_Ethernet.bin` from the GitHub release (present in 0.15.1, 0.15.2, 0.15.3 and 0.15.4). The vendor's public repository (`github.com/Jimi68/DOM-Z-102`, "WLED_ETH_Skikibily") offers `WLED_LAN_4CH_0.15.1.bin`, `_0.15.2`, `_0.15.3`, `_0.15.4` and `WLED_LAN_4CH_16.0.1_Skikibily.bin`, and documents one method only: the Espressif web tool over a USB-C cable. It gives no warnings, no backup advice and no OTA instructions. Whether its images are stock WLED or carry vendor changes is UNVERIFIED; the units themselves identify as stock `ESP32_Ethernet` builds, and "16.0.1" is not an upstream 0.15 release.

**Our rule and where it comes from.**
- "Never flash, update or downgrade; never load a generic WLED image": owner decisions 2026-10-08 and 2026-10-09 (FACTS T-F2, T-F3, T-F4), applied by git `aad0077`.
- "Never via USB": git `a84aec2` (2026-08-28, "SKIKBILY serial-write ban (2.0a)") added to the old SOP: serial/USB flash writes prohibited on Skikbily-class controllers, "bricking risk; wire is read-only for dumps and diagnostics", and named the vendor repository as the firmware source. The bricking claim is the SOP author's; no unit was bricked in the repo's record, so it stays UNVERIFIED as a measurement and binding as a rule.
- The July pin (git `9fdad58`, 2026-07-23) rested on one bench observation: a unit reflashed to 0.15.4 through a web flasher paused periodically (about every 17 s, frame rate to zero for 4–6 s) while a 0.15.1 unit of the same variant beside it did not. Recorded again in the tracker (`docs/BUGS_AND_DEBT.md:1942–1946`: the September hang on the home unit was on 0.15.1, "the 0.15.4 stall is not in play"; `:3034–3038`: P2-14, "evaluate WLED version-pin before fleet scale"). It has never been reproduced on a fielded unit and is UNVERIFIED as a fleet problem.

**What is kept or lost.** By the documentation: a factory reset loses everything; backup and restore of presets and configuration exist. By an OTA update: UNVERIFIED (above). The Wi-Fi credentials, the setup-network password and the OTA passphrase are in cfg.json; if an update kept the file system they survive, if not the unit returns to its setup network with the factory default password (T-A3), which an installer could reach only on site.

**What a failed or mismatched update does.** 0.15.2 and later carry OTA validation, an old-version check and bootloop detection with recovery (§4); what each does on our units when the image is refused, the upload is interrupted, or the image is for another board is UNVERIFIED. Nothing in the repository has observed any of these. A unit that does not boot after an update has no recovery path under our rules, because the only other path is the USB flash that `a84aec2` forbids.

**The home unit is never a test unit.** The owner's home controller, also the bench unit, carries seven bad bytes in its presets file (one stored preset, slot 41, cannot be parsed; `docs/BUGS_AND_DEBT.md:618`; FACTS T-F11). Its presets file cannot be trusted as a before-image, and a write that resaves the file could lose or spread the damage. The unregistered spare unit (0.15.4, four outputs) is the only unit on which anything destructive may be tried.

## 6. Verdict (options; option 1 decided by the owner on 2026-10-12)

### (a) Which version should be the fleet standard

| Option | For | Against |
|---|---|---|
| **1. No fleet standard; "record, never change" stays** (today's policy, T-F2) | Nothing in the app depends on the version (§2); 16 of 22 known units are on 0.15.1 and the six on 0.15.4 have run their probes and schedules without a version-tied report; every move carries the UNVERIFIED risks in §5. | The behaviours measured on 0.15.1 only (§2.2) are assumed, not proven, on the six 0.15.4 units; the per-pixel multi-request paint is the concrete gap. |
| 2. 0.15.1 as the **reference** version: what new bench proofs are taken against, what a new unit is checked against at the bench, no fielded unit moved | Majority version; every ledger proof; the effect catalog verification; the July observation. Costs nothing on the fleet. | Units arrive from the vendor on 0.15.4 now (T-F1, §3), so "reference" cannot mean "what ships" without a flash the rules forbid. |
| 3. 0.15.4 as the standard | Vendor's current image; adds OTA validation, bootloop recovery and the presets file protection, which is the only upstream change aimed at the kind of damage the home unit shows. | The July pause is unexplained; the 0.15.1-measured behaviours are unverified on it; reaching it on 16 units means 16 OTA updates with UNVERIFIED retention and no recovery path. |

**Decided by the owner on 2026-10-12: option 1 (FACTS T-F14).** Record, never change, for every fielded unit. 0.15.1 is named as the reference the app was measured against; that is a FACTS statement, not an instruction to flash and not a claim that 0.15.1 is what ships or is newer. A 0.15.4 unit is supported as today. Nothing moves. Option 2 was not chosen, so the bench plan in (b) is unauthorized.

### (b) Is a move supported, safe and reversible for our units

- **Up, 0.15.1 → 0.15.4:** supported by WLED's own OTA path with the official `ESP32_Ethernet` image. Safe: UNVERIFIED (retention of cfg.json, presets.json and Wi-Fi; behaviour on a refused or interrupted upload). Reversible: UNVERIFIED and doubtful, because 0.15.4's old-version check may refuse the 0.15.1 image, and the USB route is forbidden.
- **Down, 0.15.4 → 0.15.1:** the route the vendor documents is USB, which `a84aec2` forbids; the OTA route may be refused by the old-version check (UNVERIFIED). Not supported under our rules today.
- **Vendor "16.0.1" image:** not an upstream release; nothing known. Not an option.

**Bench test plan: written, NOT authorized (option 2 was not chosen on 2026-10-12), never run; no controller to be touched. If it is ever authorized it applies to the spare unit only, never the home unit with the seven bad bytes.**

1. Baseline, read-only: `GET /json/info`, `/json/state`, `/json/cfg`, `/presets.json`, `/json/effects`, `/json/palettes`; save each with its SHA-256; record `ver`, `vid`, `release`, `mac`, `leds.count`, the four buses, every timer row, the setup-network settings (behaviour value only, never the key) and the effect-list hash. Confirm the spare is unregistered in Firestore (read-only) before anything else.
2. Backup through the controller's own backup page as well (presets and configuration JSON), so there is a restore path that does not depend on the file system surviving.
3. Nothing past this step without the owner's written one-off exception for the spare. On 2026-10-12 the owner chose option 1, so there is no exception and steps 4–9 are not to be run.
4. OTA per §5 with the official image for `ESP32_Ethernet` of the target version. Time the upload; capture the page's response verbatim.
5. After the restart, read the same six endpoints. Pass criteria: `ver` is the target; `release` unchanged; SHA-256 of `/presets.json` identical to the baseline (a byte change here fails the test, because it means the update rewrote or lost presets); `/json/cfg` readback equal to baseline on every key the app writes (buses, timers, `if.ntp`, `light.gc`, `ap.behav`, `def.ps`; readback is compacted, so compare parsed values, not bytes); Wi-Fi still joined; effect-list hash identical.
6. App checks on the spare (harness, LAN): apply a look; a per-pixel design larger than 224 LEDs so that it is sent in two or more requests, then read `/json/live` and confirm every pixel of every request is lit (this is the §2.2 gap); schedule sync with one general timer and one solar timer, then read the timer rows back; preset save and delete round trip with a SHA check of `/presets.json` between steps; the on-connect healer reports zero writes on a healthy unit; a 30-minute one-second `/json/info` log on an animated effect to look for the July pause (frame rate to zero).
7. Reverse direction: repeat 4–6 back to the starting version. If the page refuses the image, record the exact text; that answers T-F8's first question. Do not try to bypass the check.
8. Interrupted update: not tested. There is no recovery path without USB, and USB is forbidden.
9. Write the results into FACTS T-F8 and this page. Until step 7 passes, no fielded unit moves in either direction.

### (c) Does a mixed fleet cause an app, healer or Game Day problem today

- App: no version gate, so no. The two measured differences that could show: a per-pixel design sent in several requests may render only its last request on a 0.15.4 unit (UNVERIFIED, §2.2); Twinkle and Tri Fade look slightly different. No customer report in the tracker is tied to a version.
- Healer: compares clock, zone, coordinates, gamma, audio flag and bus bounds; never version. On a 0.15.4 Ethernet build the audio heal is a no-op. No problem.
- Game Day: the server plans from bus bounds and preset ids (`functions/src/gameDayPlanning.ts:119, 568`); the phone-run path writes a preset and a timer the same way for every unit. No problem known; the 0.15.4 units have not been in a server-run game (T-GD2 is bench-only).
- Support: the only version signal off-LAN is the probe's `wledVersion`; the add-time field is stale by design. Triage should read the health record, not the controller record.

### (d) What the installer guides should say about firmware (verified statements only)

Already in the install checklist, the pre-install SOP, the controller-setup page and the forms:

- Record the version (`ver` and `release`) at the bench and on install day; write it on the record and the label.
- Never flash, update or downgrade a controller; never load a generic WLED image; the controller's own settings page offers an update, do not use it.
- Every version in service is supported as shipped; the app never checks the version and treats every unit the same.
- A version you have not seen: note it and email general@nex-genled.com; change nothing.

Nothing about a standard version, a pin, a stall, a web flasher or what flashing does; none of that is verified for the fleet.

## 7. Sources read for this page

- `docs/FACTS.md` T-F1 to T-F13; `docs/guides/installer/10-install-checklist.md`, `11-controller-setup.md`, `13-installer-sop.md`; `docs/guides/dealer/20-dealer-guide.md`, `21-sales-mode.md`; `docs/guides/internal/33-claims-policy.md`; `scripts/docs_guard.mjs`.
- Code: the files and lines in §2 (sweep of 2026-10-12 at the branch head).
- Tracker and ledger: `docs/BUGS_AND_DEBT.md:618, 1942–1946, 3034–3038, 4432–4440`; `docs/BUILD_LEDGER.md:428, 4830`; `docs/audits/DESIGN_STUDIO_AUDIT_2026-07.md:6, 186`.
- Git history: `9fdad58` (2026-07-23), `a84aec2` (2026-08-28), `aad0077` (2026-10-09).
- WLED: `https://api.github.com/repos/wled/WLED/releases/tags/v0.15.1` … `v0.15.4` and the matching release pages; `https://kno.wled.ge/basics/getting-started/`; `https://kno.wled.ge/features/settings/` (Security settings); `https://raw.githubusercontent.com/wled/WLED/v0.15.4/CHANGELOG.md` (stops at 0.15.0).
- Vendor: `https://github.com/Jimi68/DOM-Z-102` (README and file list).
- Firestore, read-only, 2026-10-12: `users/*/controllers/*` and `users/*/controller_health/*`.
