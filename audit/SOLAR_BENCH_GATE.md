# Solar Bench Gate — WLED 0.15.1 @ 192.168.1.150

**Status: INCOMPLETE — Parts 1–5 NOT RUN.** The test host lost the home LAN partway through
setup. Part 0 completed and passed; substantial firmware-contract evidence was captured from the
controller's own settings page before the link dropped. No configuration was written to the
controller at any point.

**CORRECTED 2026-08-27 (see §8).** An earlier revision of this line said "this is not yet the
artifact the flag should have had on Aug 5." That framing was wrong: the Aug 5 gate artifact
EXISTS, and has since 2026-08-05, recorded in the `notes` field of the
`config/solar_scheduling` document itself. It was never absent — it was never looked for. See §8.

- Date: 2026-08-27
- Controller: `192.168.1.150`, WLED `0.15.1`, vid `2507300`, 290 LEDs, RGBW (`seglc [3,3]`, `wv:2`)
- Authorization: Tyler authorized cfg **writes** on the bench for this pass only. **None were used.**
- Arming method (decided with Tyler mid-session): firmware-contract proof via the real builders.
  The fleet flag `config/solar_scheduling` was **NOT** flipped — see §6.

---

## 0. Timeline (host clock, CDT)

| Time | Event |
|---|---|
| 13:07:06 | `/json/cfg` snapshot captured. Controller healthy, 68 ms response. |
| 13:07:06 | Device reports `time = "2026-8-27, 13:07:06"`; host reads `13:07:07 CDT`. 1 s skew. |
| ~13:1x | `/settings/time` fetched (gzip, 8912 B decoded). **Last successful response from the controller.** |
| ~13:20 | `/json/state` begins timing out (`http=000`, 20 s). `/presets.json` also fails. |
| ~13:30 | All five endpoints `http=000`. ICMP: 3 sent, 0 received, 100 % loss. |
| 13:40:58–13:41:30 | Five further retries over 45 s — all `http=000`. Bridge `192.168.1.105` also unreachable. |
| ~13:42 | Host interfaces inspected: machine is on `172.20.10.2/28`, gateway `172.20.10.1`. **Not on `192.168.1.x`.** |

### Cause of the abort

Host-side network change, **not** a controller fault:

- The host's only routable interface is `Wi-Fi` at `172.20.10.2/28` with default route `172.20.10.1`.
  That `/28` on `172.20.10.x` is the standard iPhone Personal Hotspot subnet.
- `arp -a` shows **zero** `192.168.1.x` entries.
- The ESP32 bridge at `192.168.1.105` is unreachable on the same sweep. A controller crash would not
  take the bridge with it.

The bench controller is presumed healthy. **Resume condition: put the host back on the home LAN and
re-verify `192.168.1.150` responds, then re-run from Part 1.**

### Write ledger

**Zero writes.** Every request issued: `GET /json/info`, `GET /json/cfg`, `GET /json/state`,
`GET /settings/time`, `GET /presets.json`, and ICMP. No `POST`, no reboot. The snapshot below was
never needed for a restore.

---

## 1. Snapshot (the restore point, unused)

`bench_cfg_SNAPSHOT.json` — 2790 bytes, sha256 `e1feef2eb74dc2b34bd3ce7eabe0986646c8dd50595d4806dd36db82cef662cb`

```json
"if": { "ntp": {
  "en": true, "host": "time.google.com", "tz": 5, "offset": 0,
  "ampm": false, "ln": -94.2527, "lt": 38.99346 } }
```

```json
"timers": {
  "cntdwn": { "goal": [20,1,1,0,0,0], "macro": 0 },
  "ins": [ {"en":1, "hour":255, "min":0, "macro":2, "dow":127} ] }
```

```json
"def": { "ps": 0, "on": true, "bri": 128 }
```

Cfg top-level keys: `ap, def, eth, hw, id, if, light, nw, ol, ota, rev, timers, um, vid, wifi`.

### 1a. Two findings already visible in the snapshot

**Readback compaction, confirmed live.** `timers.ins` returns **one** element. That element is a
solar row (`hour:255`) — the global sunrise-off, which lives in firmware **slot 8** — yet it appears
at readback **index 0**. This is a direct, live confirmation of
`project_wled_cfg_readback_is_compacted`: array index ≠ device slot on the way back. Any verification
in Parts 2/3/5 **must** classify by the `hour==255` marker and ordering, exactly as
`sunrise_off_service` does ([sunrise_off_service.dart:304-326](lib/features/schedule/sunrise_off_service.dart#L304-L326)),
and never by position. `assembleSolarAwareIns` writes positionally, which is correct for the *write*
direction; the asymmetry is real and is worth stating plainly in the code.

**A reboot on this bench will light the strip.** `def = {"ps":0,"on":true,"bri":128}`. Per
`project_healer_reboot_lights_on_gate`, WLED's `def.on` boots the strip lit. This matters because the
Part 1–3 method very likely requires a reboot (see §5), so the resumed run must expect the lights to
come on at brightness 128 and must restore state afterwards.

---

## 2. PART 0 — TZ writers — **COMPLETE, PASS**

### 2a. Device check (the gate for Part 1) — PASS

| Field | Value |
|---|---|
| `if.ntp.tz` | `5` |
| `if.ntp.offset` | `0` |
| Device local time | `2026-8-27, 13:07:06` |
| Host local time | `2026-08-27 13:07:07 CDT (-0500)` |
| Skew | 1 s |

`tz: 5` is `TZ_US_CENTRAL` per [kWledTzByIana](lib/services/wled_config_pusher.dart#L57-L66), correct
for the bench's coordinates (`38.99346, -94.2527` — Johnson County, KS). `offset: 0`, so the enum is
the sole authority and nothing is stacked. **Local time confirmed correct before Part 1.**

### 2b. Can the two writers disagree into a wrong local time? **Yes — but not by the documented mechanism.**

The two writers:

- `pushTimeLocation` — writes `tz: wledTzForIana(iana)` **and** `offset: 0` together, deliberately, so
  the enum is the only source of truth: [wled_config_pusher.dart:384-392](lib/services/wled_config_pusher.dart#L384-L392),
  rationale at [:366-368](lib/services/wled_config_pusher.dart#L366-L368) ("`offset` is ADDITIVE to the
  `tz` enum … stacking them double-shifts the clock").
- `tzHealPayload` — two shapes at [controller_defaults_healer.dart:318-328](lib/features/wled/controller_defaults_healer.dart#L318-L328):
  - index branch → `{'tz': tzIndex}` — **writes `tz` without clearing `offset`**
  - offset branch → `{'tz': 0, 'offset': offsetSeconds}`

**The double-shift the comment warns about is currently UNREACHABLE.** The index branch is the one
that could stack onto a pre-existing nonzero `offset`, but it only runs under `tzSuspect`
([:570](lib/features/wled/controller_defaults_healer.dart#L570) → [tzHealFor:206-215](lib/features/wled/controller_defaults_healer.dart#L206-L215)),
and `tzSuspect` requires `deviceIsUtc = tzIndex == 0 && (tzOffsetSeconds ?? 0) == 0`
([clock_health.dart:340-348](lib/features/wled/clock_health.dart#L340-L348)). A device carrying a
nonzero offset therefore never qualifies. The healer cannot stack on itself.

It is safe only because of an invariant enforced in a **different file**. Nothing in
`tzHealPayload` documents or defends that dependency. If `deviceIsUtc` is ever loosened, the
double-shift goes live silently.

**The reachable defect is the DST trap.** Sequence:

1. Profile timezone is null or outside `kWledTzByIana` (the map covers only 7 US zones).
2. `tzHealFor` falls to `TzHeal.offset(phoneOffset.inSeconds)`
   ([:213-214](lib/features/wled/controller_defaults_healer.dart#L213-L214)).
3. Device is left at `tz:0` + a **fixed** offset captured from the phone at heal time. Local time is
   correct *right now*.
4. `tzSuspect` can now never fire again (`offset != 0`), so no future heal touches it.
5. **That frozen offset does not follow DST.** At the next transition the device is exactly one hour
   wrong, permanently, with no self-heal path.

Consequence for solar specifically: WLED computes sunrise/sunset against its own local time, so an
hour-wrong clock fires the solar macros an hour off — while `if.ntp.lt/.ln` are perfectly correct and
every readback looks clean. This is a second, independent path to the same silent-wrong-firing
symptom documented as stale-coordinate drift in `audit/SOLAR_FIRING_PATH_AUDIT.md` §Task 4.

A secondary, self-recovering case: a `pushTimeLocation` re-sync on an unmappable zone writes
`tz:0, offset:0`, reverting a healer's offset fix and jumping the clock to UTC. That one *does*
re-trigger `tzSuspect` on the next connect, so it heals — but there is a window.

**Fix needed (not applied — read-only pass):** make `tzHealPayload`'s index branch write
`'offset': 0` alongside `tz`, so both writers assert the same two-field invariant and neither depends
on a predicate in another file. Separately, the offset branch needs a DST story — either re-evaluate
periodically, or refuse the offset fallback and surface an unmapped-zone warning instead of freezing a
number that silently rots.

**Authority chosen for this test:** the `pushTimeLocation` shape already on the device
(`tz:5, offset:0`). The resumed run must write **only** `if.ntp.lt` / `if.ntp.ln` and must not touch
`tz` or `offset`.

---

## 3. Firmware contract, read from the controller's own UI — **NEW, HIGH CONFIDENCE**

Source: `GET /settings/time` from the bench, gzip, 8912 bytes decoded. This is the firmware's own
form, so it is authoritative about what this build accepts.

### 3a. Slot 8 = Sunrise, slot 9 = Sunset, `hour` = 255 — **CONFIRMED**

```html
<tr><td><input name="W8" id="W8" type="hidden"><input id="W80" type="checkbox"></td>
<td>Sunrise<input name="H8" value="255" type="hidden"></td>
<td><input name="N8" class="xs" type="number" min="-59" max="59"></td>
<td><input name="T8" class="s" type="number" min="0" max="250"></td>
```

```html
<tr><td><input name="W9" id="W9" type="hidden"><input id="W90" type="checkbox"></td>
<td>Sunset<input name="H9" value="255" type="hidden"></td>
<td><input name="N9" class="xs" type="number" min="-59" max="59"></td>
<td><input name="T9" class="s" type="number" min="0" max="250"></td>
```

Resolves **UNKNOWN #4** from `audit/SOLAR_FIRING_PATH_AUDIT.md`. The firmware really does dedicate
indices 8 and 9 to sunrise and sunset, `hour` really is the fixed marker `255`, and the slot's
**position** — not its contents — is what distinguishes sunrise from sunset. `kWledSolarHourMarker`
and `assembleSolarAwareIns` are both correct as written.

It also confirms the timer table is **10 slots**, not 8 — so `kWledTotalTimerSlots = 10`
([schedule_sync.dart:327-328](lib/features/schedule/schedule_sync.dart#L327-L328)) is right, and the
8-slot claim in the older docstring at [:735-740](lib/features/schedule/schedule_sync.dart#L735-L740)
("WLED supports up to 8 timers") is stale.

### 3b. `min` is a SIGNED offset — **CONFIRMED**

`<input name="N8" min="-59" max="59">`. The firmware's own UI accepts negative values, so the signed
interpretation asserted at [sunrise_off_service.dart:21-23](lib/features/schedule/sunrise_off_service.dart#L21-L23)
is right about the *field's intent*. Partially resolves **UNKNOWN #3**.

Still open: whether a negative survives the **JSON cfg** round-trip. The HTML form and the JSON
deserializer are different code paths, and the "226 means unsigned" hypothesis in Part 4 is exactly
the right probe. Part 4 remains necessary.

### 3c. **DEFECT — the app's offset clamp is 2× the firmware's range**

| Source | Permitted offset |
|---|---|
| Firmware UI (`N8`/`N9`) | **±59** minutes |
| App `kWledSolarOffsetLimit` ([schedule_sync.dart:337](lib/features/schedule/schedule_sync.dart#L337)) | **±120** minutes |
| App's own docstring ([cfg_payload_builder.dart:167-170](lib/features/schedule/cfg_payload_builder.dart#L167-L170)) | ±59 minutes |

`buildSolarTimerEntry` clamps to `±kWledSolarOffsetLimit`
([schedule_sync.dart:608](lib/features/schedule/schedule_sync.dart#L608)), so the app would accept and
transmit an offset up to ±120 that the firmware's own form rejects. The codebase contradicts itself —
the constant says 120, the neighbouring comment says 59, and the firmware says 59.

**Latent today**, because every call site passes `offsetMinutes: 0`
([schedule_sync.dart:678](lib/features/schedule/schedule_sync.dart#L678), [:689](lib/features/schedule/schedule_sync.dart#L689))
and no offset UI exists. It becomes live the moment an offset control ships — which is the natural
next feature after this gate passes. What a >59 value actually does (clamped? rejected? stored
wrong?) is unknown and is worth folding into Part 4.

### 3d. Lat/lon are magnitude + hemisphere in the form, signed in JSON

```html
Latitude:  <select name=LTR><option value=N><option value=S></select>
           <input name=LT type=number max=66.6 min=0 step=0.01>
Longitude: <select name=LNR><option value=E><option value=W></select>
           <input name=LN type=number max=180 min=0 step=0.01>
```

The HTML form splits sign into a separate `LTR`/`LNR` selector, but `/json/cfg` carries signed values
(`lt: 38.99346, ln: -94.2527`). The app writes JSON and writes signed — **correct**, no action needed.

Note `LT max=66.6` — the firmware form caps latitude at the polar circle, beyond which solar events
stop existing. Irrelevant to the bench; relevant if Lumina ever installs at high latitude, and it
matches `SunUtils` returning `null` for `cosH` out of range.

### 3e. **The controller does not expose its computed sunrise/sunset — anywhere**

- `/json/info`: all 38 keys enumerated — `arch, brand, clock, cn, core, cpalcount, flash, freeheap,
  fs, fxcount, i2c, ip, leds, lip, live, liveseg, lm, lwip, mac, maps, maxalloc, name, ndc, opt,
  palcount, product, release, resetReason0, resetReason1, simplifiedui, spi, str, time, u, udpport,
  uptime, ver, vid, wifi, ws`. **No solar field.**
- `/settings/time`: contains only a JS placeholder — `Current local time is <span class=times>unknown</span>`.
  No server-rendered sunrise/sunset.

**Consequences.** First, the "cheap field check" Part 1 hoped for **does not exist** — there is no way
to ask a controller what time it believes sunset is. Second, and worse for the product: this means the
stale-coordinate failure in `audit/SOLAR_FIRING_PATH_AUDIT.md` §Task 4A is not merely *undetected* by
the app, it is **undetectable by any readback**. A controller firing on year-old coordinates is
externally indistinguishable from a correct one until someone physically watches the lights. Any
future drift detector must therefore compare `if.ntp.lt/.ln` against the profile — comparing computed
times is not an available strategy.

---

## 4. PARTS 1–5 — **NOT RUN (that session). SUPERSEDED by §8.**

| Part | Status | Reason |
|---|---|---|
| 1 — Coordinate fudge | NOT RUN | LAN lost before any write |
| 2 — Sunset fires | NOT RUN | depends on Part 1 |
| 3 — Sunrise fires | NOT RUN | depends on Part 1 |
| 4 — Offset sign (`min:-30`) | NOT RUN | depends on Part 1 |
| 5 — Sunset-only edge | NOT RUN | depends on Part 1 |

No result may be inferred for any of these. **CORRECTED 2026-08-27 (§8):** an earlier revision
said "the bench gate remains unsatisfied" and that the flag "has no more hardware evidence behind it
now than it did on Aug 5." Both are wrong. The gate PASSED on 2026-08-05 with a slot-9 sunset row
observed firing on this controller; the evidence is quoted in §8. What follows describes only what
THIS session did and did not run — with the
important qualification that §3 has now confirmed the *encoding* is right, narrowing what Parts 2–3
still have to prove to: does the firmware actually fire the macro at the computed moment.

---

## 5. Method for the resumed run

Two design problems surfaced before the abort, and one earlier claim in this
artifact was wrong. All three are resolved here. **Parts 1–5 are otherwise
unchanged.**

### 5a. CORRECTION — the predictor spread is ~1 minute, not ~12

An earlier revision of this document stated that `SunUtils` runs "~12 min early
on sunrise and ~4 min early on sunset." **That was wrong.** Those figures were
measured against sunrise/sunset values asserted from recollection (~06:53 /
~19:59 CDT), not against any computed or cited reference. Corrected by
computing all three predictors — derivation and the WLED port in
`audit/SOLAR_PREP.md` §1:

| Coordinates | Event | NOAA reference | WLED 0.15.1 | SunUtils | WLED−NOAA | SunUtils−NOAA |
|---|---|---|---|---|---|---|
| `38.99346, -94.2527` (bench `if.ntp`) | Sunrise | 06:41 | **06:40** | 06:41 | −1.0 m | +0.0 m |
| `38.99346, -94.2527` | Sunset | 19:56 | **19:55** | 19:55 | −1.4 m | −1.0 m |
| `38.9934731, -94.2523898` | Sunrise | 06:41 | **06:40** | 06:41 | −1.0 m | +0.0 m |
| `38.9934731, -94.2523898` | Sunset | 19:56 | **19:55** | 19:55 | −1.4 m | −1.0 m |

All three agree to within ~1.4 minutes at the bench site on 2026-08-27. The two
coordinate pairs differ by ~26 m and resolve to the same minute.

The fuse still widens — but for a different and better reason than originally
given. WLED fires on **whole-minute equality** inside `checkTimers()`
(`ntp.cpp:374-381`), the predictors still disagree by up to ~1.4 min, and
`getSunriseUTC` truncates rather than rounds. A tight window can therefore miss
on rounding alone, with no defect present.

### 5b. Predict with the WLED port, not SunUtils

Use `lib/features/schedule/wled_solar.dart` (branch `fix/solar-predictor-wled`,
commit `0c1c950`) — a faithful port of `ntp.cpp:429-535` including WLED's own
approximate trig. **Do not predict with `SunUtils`.** They happen to agree
closely at this latitude and date, but that is an observation, not a guarantee:
WLED uses `sin_approx` (±0.0015) and `acos_t` (±6.7e-5) where `SunUtils` uses
exact `dart:math`, and the two have no reason to track each other at other
latitudes or seasons.

**Fuse: 25 minutes.** Place the fudged-coordinate target ~25 min out from the
WLED-port prediction, and poll `/json/state` every 5 s across a **±20 min**
window centred on it. Record the exact instant of the observed state change.
The deliverable is a **measured delta** between predicted and observed, not a
pass/fail on a point estimate.

### 5c. Part 2 splits: no-reboot, then reboot

**Now predicted, not merely suspected** — see `audit/SOLAR_PREP.md` §3.
`calculateSunriseAndSunset()` has exactly four call sites in WLED v0.15.1, and
**none of them is the JSON config path**:

| Call site | Trigger |
|---|---|
| `ntp.cpp:289` | NTP packet received (`handleNetworkTime`) |
| `ntp.cpp:381` | daily, at local **00:01**, inside `checkTimers()` |
| `ntp.cpp:547` | `setTimeFromAPI()`, only when the correction is ≥ 60 s |
| `set.cpp:487` | **HTML settings Time-form save** (`handleSettingsSet`, `SUBPAGE_TIME`) |

`cfg.cpp:534-538` reads `tz`, `offset`, `ln`, `lt` out of `/json/cfg` and
assigns them — and then **does not recompute**. The web form at `set.cpp:487`
explicitly does, with the comment `// force a sunrise/sunset re-calculation`.
The app writes JSON, so the app's coordinate write lands in the variables but
leaves `sunrise`/`sunset` at their previously computed values.

So run Part 2 in two phases and record both:

- **2a — write coords, NO reboot.** Watch the predicted new sunset. Firing here
  would falsify the prediction above and mean cfg writes do take effect live.
- **2b — reboot, then watch the next predicted sunset.** Firing only here
  confirms reboot-required.

Expected: 2a silent, 2b fires. **Record the negative in 2a explicitly** — it is
the evidence for a product question that matters independently of this gate:
whether pushing corrected coordinates to a customer's controller does anything
before the next reboot or midnight.

### 5d. A reboot will light the strip — sequence around it

The bench snapshot has `def = {"ps":0,"on":true,"bri":128}`. Per
`project_healer_reboot_lights_on_gate`, WLED's `def.on` boots the strip **lit**.
So the 2b reboot turns the lights on at brightness 128 *before* the observation
window opens.

Order of operations for 2b, so the reboot artefact cannot be mistaken for the
timer firing:

1. Reboot (`{'rb':true}`).
2. Wait for `/json/info` to answer again, then wait for NTP — confirm
   `info.time` is correct before trusting anything.
3. **Drive the strip to the known pre-test state** (off, or the distinct
   non-firing state) and confirm via `/json/state`.
4. Only then open the ±20 min poll window.

Without step 3 the strip is already on when the window opens and the firing
edge is unobservable.

### 5e. Observability constraint carried forward

There is no way to ask the controller what time it thinks sunset is (§3e). The
firing edge in `/json/state` is the **only** observable — which is why the
pre-test state in 5d step 3 must be unambiguous and why the poll interval is
5 s rather than per-minute.

## 6. Fleet-flag decision (recorded)

Part 2 as briefed said "solar flag on". `config/solar_scheduling` is a **single global Firestore
document** ([solar_scheduling_feature_flag.dart:27-29](lib/features/schedule/solar_scheduling_feature_flag.dart#L27-L29)),
read through a live `snapshots()` stream ([:31-50](lib/features/schedule/solar_scheduling_feature_flag.dart#L31-L50)) —
not per-user and not per-device. Setting `enabled:true` would turn correctly-encoded solar scheduling
on for **every user in the fleet** for the duration of the test, causing any foregrounded customer app
to begin writing solar rows to that customer's controller. That is the same deploy-one-half class as
the +74 join regression (`project_deploy_without_app_half`).

**Tyler's decision: do not flip it.** Arm instead via the real builders, POSTing the byte-identical
payload `syncAll` would produce. This proves the firmware contract — which is what the gate doc
actually asks for ([solar_scheduling_feature_flag.dart:11-16](lib/features/schedule/solar_scheduling_feature_flag.dart#L11-L16)) —
with zero fleet exposure.

**Coverage this consciously gives up**, and which still needs closing before the flag ships:
`syncAll`'s coordinate precondition ([schedule_sync.dart:809-820](lib/features/schedule/schedule_sync.dart#L809-L820)),
the schedule UI's solar segment, and the `solarMismatch` verify path. These are Dart-testable and do
not need hardware; they are not covered by this artifact.

No tablet was available this session, so the app-driven path was not an option regardless.

---

## 7. Open items

1. **Parts 1–5 unrun.** Resume condition: host back on the home LAN, `192.168.1.150` responding.
2. **`kWledSolarOffsetLimit = 120` vs firmware ±59** (§3c) — real contradiction, latent until an
   offset UI ships. Not fixed here (no code changes this pass).
3. **`tzHealPayload` index branch omits `offset: 0`** (§2b) — safe only via a predicate in another
   file. Not fixed here.
4. **Healer offset branch freezes a non-DST-following offset** (§2b) — no self-heal path once set.
   Needs a design decision, not just a patch.
5. **Stale coordinates are undetectable by readback** (§3e) — any drift detector must compare
   `if.ntp.lt/.ln` against the stored profile. No such comparison exists anywhere in the codebase.
6. **Stale docstring** at [schedule_sync.dart:735-740](lib/features/schedule/schedule_sync.dart#L735-L740)
   still says "WLED supports up to 8 timers" and documents the dead `hour 24/25` encoding; §3a
   confirms 10 slots and `hour:255`.
7. **Does a cfg coordinate write take effect without a reboot?** (§5b) — unknown, and materially
   affects whether a remote coordinate fix is worth shipping.

---

## 8. Session close — 2026-08-27 17:10 CDT

### 8a. THE GATE ARTIFACT EXISTS — and has since 2026-08-05

Read from `config/solar_scheduling`. `enabled` is **`true`**, and the doc has never been modified:
`createTime == updateTime == 2026-08-05T16:35:42.365652Z`, `modifiedBy: "bench_gate_2026_08_05"`.

The `notes` field is the gate artifact, verbatim:

> BENCH GATE PASSED 2026-08-05 on 192.168.1.150 (WLED 0.15.1, vid 2507300): a slot-9 sunset row
> FIRED at 11:27:09 against a computed sunset of 11:27, verified with a longitude-only coordinate
> fudge (4 min/degree, lat+tz fixed). Solar readback comparator (`solarTimersLanded`) shipped
> first — before it, `isRealEnabledTimer` excluded `hour==255`, so a solar row verified clean
> whether it landed correctly, landed wrong, or never landed at all. PER-ACCOUNT SAFETY NET:
> `syncAll` gates on `solarFlagOn && solarCoordsUsable`, reading the CONTROLLER coordinates — a
> controller at 0,0 gets a specific "needs your location set on the controller" refusal, not
> silence. ROLLBACK = set `enabled:false` (the five UI surfaces re-gate themselves).

**Consequences.** UNKNOWN #2 of `audit/SOLAR_FIRING_PATH_AUDIT.md` ("has WLED 0.15.1 been observed
firing at real sunrise/sunset on hardware?") is **ANSWERED: yes.** The method recorded there is the
same one re-derived from scratch across two sessions of this file — longitude-only fudge, latitude
and timezone fixed, 4 min/degree.

**What went wrong in this file's process.** The flag value was listed as UNKNOWN #1 in the first
audit, with an explicit note that it needed a credentialed read. Two sessions of analysis then
proceeded *around* that unknown rather than resolving it, and §4 and the header hardened an absence
of evidence into a claim that no evidence existed. The read takes one command. **A stated UNKNOWN
that is cheap to resolve should be resolved before anything is built on top of it.**

### 8b. Flag value confirmed under RULES, not just stored

Admin-SDK reads bypass rules and prove only that a value exists
(`feedback_verify_with_client_credential`). Repeated as a genuine client read: a custom token minted
for a real uid, exchanged for an ID token, then the Firestore REST API:

```
GET config/solar_scheduling            -> HTTP 200   enabled = {"booleanValue": true}
GET staff_auth_log  (control)          -> HTTP 403   (token IS rules-constrained, not admin)
```

The rule is `firestore.rules:1632` — `allow read: if request.auth != null`. The 403 control is what
makes the 200 meaningful: it proves the credential was subject to rules. **The app-side stream
resolves `enabled = true`.**

### 8c. PART 2a — GENUINE NEGATIVE, and the standing installer rule

211 samples, 14:55:08 -> 15:50:05, 15 s poll, predicted sunset 15:24 covered +/-26 min. Strip never
left `on=False / ps=-1`. Coordinates held (`ln=-26.34999`), timer armed (`macro:10`) throughout.

> **STANDING INSTALLER RULE — a coordinate written over `/json/cfg` does not take effect until the
> controller recomputes.** `cfg.cpp:534-538` assigns `lt`/`ln` and never calls
> `calculateSunriseAndSunset()`. The only four call sites are `ntp.cpp:289` (NTP sync), `ntp.cpp:381`
> (local **00:01** daily), `ntp.cpp:547` (`setTimeFromAPI`, >=60 s correction) and `set.cpp:487` (the
> **HTML settings Time form**, which forces it explicitly). The app writes JSON, so an app-side
> coordinate fix lands in the variables and lies dormant until reboot, NTP sync, or 00:01.
>
> Practical form: **after changing a customer's coordinates, reboot the controller or tell them the
> change takes effect overnight.** Do not report it as applied. Nothing in the app currently forces
> a recompute or surfaces the dormancy, and §3e means the stale state is invisible to any readback.

Confirmed in both directions: 2b's reboot at 15:54:21 carried the new coordinates into effect
immediately (uptime 8 s, clock synced, `ln=-42.64999` live), where 2a's identical write without a
reboot did nothing for 55 minutes.

### 8d. PART 2b — CONTAMINATED, not a result

234 samples, 15:55:06 -> 16:55:12, zero read failures. Nothing fired at the predicted 16:29.
**That negative is void**, because the timer was deleted before the firing minute:

| Check | Result |
|---|---|
| slot 9 still `{en:1,hour:255,min:0,macro:10}` | **NO — gone.** The only `hour:255` row is `macro:2` (the global sunrise-off) |
| coordinates still `-42.65` | yes — `ln=-42.64999` |
| second reboot | no — uptime 3975 s vs 66 m 17 s elapsed since the 15:54:21 reboot |

Cause identified by Tyler: the bench is in his production account, and his phone ran `syncAll` on app
open plus a Game Day "Light Up Now" (Royals) at ~16:03:54. That sync rewrote `timers.ins` with the
two live calendar leases and re-asserted the sunrise-off, stubbing slot 9. The strip has held
`on=True bri=200 ps=-1 fx=52 col=[[0,70,135],[192,154,91]]` since.

**Precondition for any re-run: the bench must be isolated from the production account** — his phone
off that account or off the network for the duration, or the bench moved to a test account.
Otherwise the same contamination recurs and no solar result from this rig is trustworthy.

Incidental confirmation: the two lease rows are `dow:16` (Friday) and `dow:32` (Saturday) with macros
37 and 41 — exactly the 2026-08-28 / 2026-08-29 entries identified from Firestore in the slot-budget
audit, and exactly 2 reserved slots, which is the reservation #90 now computes (budget 6) against the
0 the old entry-count arithmetic produced.

### 8e. Parts 3, 4, 5 — DEFERRED

Sunrise (Part 3), offset sign (Part 4), and the sunset-only edge (Part 5) did not run. Deferred to
Tyler's return, behind the isolation precondition in §8d. Part 4 remains the open probe for the §3c
`kWledSolarOffsetLimit` 120-vs-59 defect; Part 5 remains the only way to resolve the §1a compaction
ambiguity, since a lone `hour:255` row cannot be positionally identified on readback.

### 8f. Bench released — restore record

| Item | State |
|---|---|
| `if.ntp` | **RESTORED** to snapshot — `lt=38.99346, ln=-94.2527, tz=5, offset=0`, verified by readback |
| `light.gc` | **RESTORED** to `{bri:1, col:2.8, val:2.8}` — see below |
| every other top-level cfg key | byte-equal to `bench_cfg_SNAPSHOT2.json` (sha256 `e1feef2e...`) |
| `timers.ins` | **DELIBERATELY NOT restored** — see below |

**Why `timers.ins` was not restored.** The snapshot predates Tyler's leases. It holds one row; the
device now holds three — two live calendar leases for 2026-08-28 and 2026-08-29, plus the
sunrise-off. Restoring the snapshot would have stub-clobbered two live leases: the P0-3.2 clobber
class, caused by a "restore". Nothing of this session's remained in the table (the `macro:10` row was
already gone, §8d), so there was nothing to undo. The current table is the app's own current truth.

**A gamma wipe was caused and repaired.** The coordinate-restore POST omitted `light.gc`, and
`gc.col` went **2.8 -> 1** — precisely `project_gamma_revert_open_seg_gc_phantom`. Repaired by a
follow-up POST carrying `light.gc`, verified by readback. Two lessons: the raw `curl` path used by
this harness bypasses `normalizeWledCfgPayload`, which is the only thing that makes the app's own cfg
writes safe; and the earlier POSTs in this session appeared harmless only because Tyler's phone
`syncAll` re-asserted gamma at ~16:03 — **the app was silently repairing the damage as fast as the
harness caused it.** Any future bench harness must route cfg writes through
`normalizeWledCfgPayload` or include `light.gc` in every payload.

**Unrestorable.** Preset slot 10 now holds `"Pattern: BenchSolarMagenta"`. Its prior contents were
never captured — the pre-run `presets.json` fetch timed out, and by the time a snapshot succeeded the
slot had already been overwritten. Preset 41 remains corrupt on the device (#89); the shipped
tolerance fix reads around it but does not repair the stored bytes.
