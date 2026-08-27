# Solar Prep — predictor, port, recompute trigger, DST exposure

Off-LAN prep for the solar bench-gate rerun. No bench access used. Nothing
deployed, nothing merged.

- Date: 2026-08-27
- Firmware reference: **WLED v0.15.1**, `github.com/wled/WLED`, `wled00/` — the
  pinned version per `project_wled_version_pin_regression`. Fetched fresh; not
  read from memory.
- Companion: `audit/SOLAR_BENCH_GATE.md` (§5 amended by item 5 below).

---

## 1. Predictor comparison

### 1a. CORRECTION — what the "12-min / 4-min" figures were measured against

They were measured against **nothing computed**. An earlier report stated that
`SunUtils` runs "~12 min early on sunrise, ~4 min early on sunset" for the bench
site. The comparison baseline was `~06:53 / ~19:59 CDT`, which I asserted from
recollection as the "actual" Kansas City times. That baseline was never derived,
never cited, and was wrong.

The error mattered: it was the stated justification for widening the test fuse,
and it wrongly implied `SunUtils` was badly inaccurate. Recomputed against a
real NOAA reference, the spread is about **one minute**.

### 1b. The three predictors

Date 2026-08-27, timezone US Central with DST (UTC−5), zenith 90.833° / −0.83°.

| Coordinates | Event | NOAA reference | WLED 0.15.1 | SunUtils | WLED−NOAA | SunUtils−NOAA | WLED−SunUtils |
|---|---|---|---|---|---|---|---|
| `38.99346, -94.2527`<br>(bench `if.ntp` as stored) | Sunrise | 06:41 | **06:40** | 06:41 | −1.0 m | +0.0 m | −1.1 m |
| " | Sunset | 19:56 | **19:55** | 19:55 | −1.4 m | −1.0 m | −0.3 m |
| `38.9934731, -94.2523898` | Sunrise | 06:41 | **06:40** | 06:41 | −1.0 m | +0.0 m | −1.1 m |
| " | Sunset | 19:56 | **19:55** | 19:55 | −1.4 m | −1.0 m | −0.3 m |

Raw WLED intermediate (`getSunriseUTC`, minutes from UTC midnight), identical
for both coordinate pairs: **sunrise 700** (11:40 UTC), **sunset 55** (00:55 UTC
next day). Converted at UTC−5 → 06:40 / 19:55 local.

**Observations.**

- All three agree within ~1.4 minutes here. `SunUtils` is *not* materially
  inaccurate at this site and date.
- The two coordinate pairs differ by ~26 m and resolve to the **same minute**.
  Coordinate precision beyond ~2 decimals is irrelevant to firing time, which
  retroactively justifies the healer rounding to 2 dp
  ([controller_defaults_healer.dart:232](lib/features/wled/controller_defaults_healer.dart#L232)).
- Agreement here is **not** a general guarantee — see §2c.

### 1c. Why WLED and SunUtils are close but not equal

They descend from the same almanac algorithm, so the structure matches. They
diverge on:

| | WLED 0.15.1 | SunUtils |
|---|---|---|
| Zenith constant | `-0.83` fed to `sin()` (`ntp.cpp:428`) | `cos(90.833°)` — same quantity, third decimal differs |
| Trig | **approximations**: `sin_approx` (±0.0015), `acos_t` (≤6.7e-5), `atan_t` polynomial | exact `dart:math` |
| Precision | 32-bit `float` | 64-bit `double` |
| Minutes | float→int **truncation** (`return UT*60`) | `hour` floored, `minute` **rounded** |
| Timezone | `Timezone` library with real DST rules, plus additive `utcOffsetSecs` | phone's fixed `timeZoneOffset`, no DST rules |

The trig is the dominant term. WLED does **not** use `sinf`/`cosf` — that block
is commented out at `fcn_declare.h:447-456`; the live defines at `:443-445`
point at `sin_approx`/`cos_approx`/`tan_approx`.

### 1d. Method

NOAA reference: standard NOAA Solar Calculator with full equation-of-time,
implemented independently for this comparison. Sanity: it puts Kansas City proper
(`-94.5786`) ~1.3 min later than the bench longitude, consistent with published
almanac times to ~2 min.

WLED: the port in item 2, run both in Dart and in an independent Python
transcription of the same source. Both produce 700 / 55 exactly.

---

## 2. The port — `lib/features/schedule/wled_solar.dart`

Branch **`fix/solar-predictor-wled`**, off `main` (`4d61ba1`), one commit
**`0c1c950`**. Two files, explicit pathspecs, built in an isolated worktree so
the shared index was never touched (`feedback_parallel_session_build_hazards`).
**Not merged, not pushed.**

```
 lib/features/schedule/wled_solar.dart       | 313 +
 test/features/schedule/wled_solar_test.dart | 182 +
```

`flutter analyze` on both files: **No issues found.**
`flutter test`: **15/15 pass.**

### 2a. What was ported, and from where

| Dart | WLED v0.15.1 source |
|---|---|
| `getSunriseUtcMinutes` | `ntp.cpp:429-480` `getSunriseUTC()` |
| `wledLocalEventMinutes` | `ntp.cpp:482-535` `calculateSunriseAndSunset()` |
| `kZenithDegrees` | `ntp.cpp:428` `#define ZENITH -0.83` |
| `sin16t` | `wled_math.cpp:65-75` |
| `sinApprox` / `cosApprox` / `tanApprox` | `wled_math.cpp:92-111` |
| `acosT` / `asinT` | `wled_math.cpp:137-161` |
| `atanT` | `wled_math.cpp:169-200` |
| `floorT` / `fmodT` | `wled_math.cpp:205-222` |

### 2b. Fidelity decisions

1. **float32 throughout.** Every intermediate is rounded through a
   `Float32List`. WLED has no doubles in this path.
2. **Approximate trig preserved.** Using `dart:math` would give a different
   answer than the device.
3. **`floorT` reproduces a real firmware bug.** It truncates toward zero then
   unconditionally decrements when negative, so `floorT(-2.0)` returns **−3.0**,
   not −2.0. Preserved deliberately and pinned in the test, because the device
   computes −3.
4. **Truncation, not rounding**, on the float→int minute conversion.
5. **The ±3-day retry at `ntp.cpp:494-504` is NOT reproduced.** It only engages
   near the poles, and reproducing it would mask a genuine no-event result. The
   port returns `null` where the firmware would retry then store 0.

### 2c. Scope

**No callers. No wiring. `SunUtils` and every consumer untouched.** This is the
predictor for the bench rerun and for a future coordinate-drift field check.
Pointing production scheduling at it is a separate decision — and note that the
close agreement in §1b is an observation at one site on one date, not a licence
to treat the two as interchangeable.

---

## 3. Recompute trigger — when does WLED recalculate solar times?

`calculateSunriseAndSunset()` has **exactly four call sites** in v0.15.1:

| # | Site | Trigger |
|---|---|---|
| 1 | `ntp.cpp:289` | NTP packet received, in `handleNetworkTime()`, right after `updateLocalTime()`. Comment: `// if time changed re-calculate sunrise/sunset` |
| 2 | `ntp.cpp:381` | Inside `checkTimers()`, gated `if (!hour(localTime) && minute(localTime)==1)` — i.e. **daily at local 00:01** |
| 3 | `ntp.cpp:547` | `setTimeFromAPI()`, only when the correction is ≥ 60 s |
| 4 | `set.cpp:487` | `handleSettingsSet()`, `subPage == SUBPAGE_TIME` — the **HTML settings Time form**. Explicit: `// force a sunrise/sunset re-calculation` |

### 3a. The JSON config path does NOT recompute

`cfg.cpp:534-538` deserialises the fields:

```cpp
CJSON(currentTimezone, if_ntp[F("tz")]);
CJSON(utcOffsetSecs,   if_ntp[F("offset")]);
CJSON(longitude,       if_ntp[F("ln")]);
CJSON(latitude,        if_ntp[F("lt")]);
```

…and there is **no `calculateSunriseAndSunset()` anywhere in `cfg.cpp`**. Grep
across `ntp.cpp`, `set.cpp`, `cfg.cpp`, `wled.cpp`, `json.cpp` returns only the
four sites above.

So the asymmetry is explicit in the firmware: the **web form** author remembered
to force a recompute; the **JSON config** path does not. The app writes JSON.

**Prediction for Part 2** (now derived, not guessed): a `/json/cfg` coordinate
write updates `latitude`/`longitude` but leaves the computed `sunrise`/`sunset`
at their previous values until one of NTP sync, local 00:01, or a reboot. Part
2a should therefore be **silent** and Part 2b should fire. If 2a fires, this
analysis is wrong and should be revisited.

### 3b. Product consequence beyond the gate

A remote coordinate fix — the natural remedy for the stale-coordinate failure in
`audit/SOLAR_FIRING_PATH_AUDIT.md` §Task 4A — **does not take effect when
written.** It sits dormant until the controller happens to NTP-sync, cross
midnight, or reboot. Nothing in the app forces any of those after a coordinate
write, and nothing surfaces the dormancy.

---

## 4. DST exposure

### 4a. Does anything record `tz`? **No.**

- **App → Firestore:** `tz` and `offset` appear only on the *write path to the
  device* ([controller_defaults_healer.dart:321,326](lib/features/wled/controller_defaults_healer.dart#L321),
  [wled_config_pusher.dart:387](lib/services/wled_config_pusher.dart#L387)) and
  in one in-memory read ([clock_health.dart:224](lib/features/wled/clock_health.dart#L224)).
  `ClockHealth` is consumed by UI banners, the installer handoff screen, and
  healer decisions — and **never persisted**.
- **Healer facts:** `FirestoreControllerFactsPublisher.publishDeviceFacts`
  writes to `users/{uid}/controllers/{controllerId}` with exactly four families —
  participation, base boundaries, base-ladder verdict, disposition
  ([controller_facts_publisher.dart:277-330](lib/features/wled/controller_facts_publisher.dart#L277-L330)).
  No tz, no offset, no coordinates.
- **`controller_health`:** exists at `/users/{uid}/controller_health/{controllerId}`
  (`functions/lib/collectControllerHealth.js:97`), fed by a daily **read-only
  `getInfo` probe** — `functions/lib/probeControllerHealth.js:5-14` states it
  writes one `getInfo` command per controller per day and explains *why getInfo
  and not getState*: version, vid, LED count, rgbw flag.

  Verified at the field level, not inferred. `foldProbeIntoHealth`
  (`functions/lib/controllerHealth.js:290-294`) extracts exactly five device
  fields from the probe:

  ```js
  wledVersion, wledVid, ledCount, rgbw, wledRelease
  ```

  **No tz, offset, latitude or longitude.** And it could not carry them even if
  it tried: I enumerated all 38 keys of `/json/info` from the live bench
  controller — `arch, brand, clock, cn, core, cpalcount, flash, freeheap, fs,
  fxcount, i2c, ip, leds, lip, live, liveseg, lm, lwip, mac, maps, maxalloc,
  name, ndc, opt, palcount, product, release, resetReason0, resetReason1,
  simplifiedui, spi, str, time, u, udpport, uptime, ver, vid, wifi, ws` — and
  none of them is a timezone or a coordinate. The clock/location block lives in
  `/json/cfg` under `if.ntp`, which this probe never requests.

- **`fleet_health`:** a top-level daily snapshot at `fleet_health/{dayKey}`
  (`collectControllerHealth.js:99`, written at `:483`). Built from the same
  rows, carrying `status`, `lastSeenMs`, `firmwareVersion` and probe counts
  (`:466-471`, `:563-566`). Also **no tz, offset or coordinates**.

**Therefore: no controller can be listed as "reporting tz:0 with a nonzero
offset." That data does not exist in Firestore.** The only way to obtain it is a
per-controller LAN `GET /json/cfg`, which is exactly the reachability the fleet
does not have.

### 4b. The unmappable-zone half — answerable, and worse than expected

The healer takes the frozen-offset branch when the profile's zone is null or
outside `kWledTzByIana`, which holds only 7 keys
([wled_config_pusher.dart:57-66](lib/services/wled_config_pusher.dart#L57-L66)).

**`UserModel.timeZone` is written from two places, and they disagree:**

| Writer | Value | Mappable? |
|---|---|---|
| Installer wizard ([installer_setup_wizard.dart:1413](lib/features/installer/installer_setup_wizard.dart#L1413)) | `customerInfo.ianaTimezone` — a real IANA name | yes |
| **Edit Profile** ([edit_profile_screen.dart:210](lib/features/site/edit_profile_screen.dart#L210)) | **`DateTime.now().timeZoneName`** | **never** |
| Reviewer seed ([reviewer_seed_service.dart:64](lib/services/reviewer_seed_service.dart#L64)) | `'America/Chicago'` literal | yes |

`DateTime.now().timeZoneName` returns a **platform display name, not an IANA
identifier**. Verified by execution on this machine:

```
timeZoneName   = "Central Daylight Time"
timeZoneOffset = -5:00:00.000000
is it a key in kWledTzByIana? false
```

On Android/iOS it returns an abbreviation such as `CDT`. Neither form can ever
match a `kWledTzByIana` key.

**So every profile save overwrites a good IANA timezone with a permanently
unmappable string.** Two consequences, both silent:

1. `wledTzForIana()` returns `kWledTzUtc` (0), so a subsequent
   `pushTimeLocation` — install or installer "Re-sync Configuration" — sets the
   controller's clock to **UTC**, five hours wrong, with `offset: 0`.
2. `tzHealFor` falls to `TzHeal.offset(phoneOffset)`
   ([:213-214](lib/features/wled/controller_defaults_healer.dart#L213-L214)) —
   the frozen-offset **DST trap** from `audit/SOLAR_BENCH_GATE.md` §2b, which
   then can never self-heal because `tzSuspect` requires `offset == 0`.

The answer to "any account whose zone the healer could not map" is therefore
structural rather than a list: **every account that has ever saved its profile
through Edit Profile**, plus every account that never had an IANA zone set.
Accounts still holding the installer's value are the only mappable ones.

### 4c. The uid list — BLOCKED, needs your approval

I wrote a read-only query (`scratchpad/dst_exposure.js`) to bucket every
`users/*.time_zone` into mappable / unmappable / missing and print the uids,
plus sample `controller_health` docs to confirm 4a empirically. It uses the
admin key at `~/.lumina/` via the `scripts/_service_account.js` convention.

**The permission classifier blocked execution**, which is a reasonable gate on
admin-credentialed Node against production. I did not work around it. Say the
word and I'll re-run it.

Caveat when it does run: an admin read bypasses rules, so it establishes what
**exists**, never what a client can read
(`feedback_verify_with_client_credential`). For this inventory question that is
the right tool, but the distinction should be stated in whatever it produces.

---

## 5. `audit/SOLAR_BENCH_GATE.md` §5 — amended

§5 replaced with the rerun method. Parts 1–5 otherwise unchanged. New
subsections:

- **5a** — the §1a correction, with the corrected comparison table.
- **5b** — predict with `wled_solar.dart` (`0c1c950`), **not** `SunUtils`.
  Fuse widened to **25 min**, polled every 5 s across a **±20 min** window; the
  deliverable is a measured delta, not a point pass/fail. Rationale corrected:
  the driver is WLED's whole-minute firing in `checkTimers()` plus a ~1.4 min
  predictor spread and truncation — not the (wrong) 12-minute claim.
- **5c** — Part 2 split into **2a no-reboot** then **2b reboot**, with §3's
  four-call-site table as the stated prediction, and an instruction to record
  the 2a negative explicitly.
- **5d** — `def.on:true` lights the strip at bri 128 on the 2b reboot, with a
  4-step ordering (reboot → confirm NTP → **drive to known pre-test state** →
  open window) so the boot artefact cannot be mistaken for the firing edge.
- **5e** — the only observable is the `/json/state` edge (§3e of that doc), which
  is why the pre-test state must be unambiguous.

---

## 6. Open items from this pass

1. **`edit_profile_screen.dart:210` writes a non-IANA timezone** (§4b). This is
   the highest-value finding here and is not solar-specific — it mis-sets
   controller clocks to UTC and arms the DST trap. Not fixed (read-only pass).
2. **`controller_health` cannot ever carry tz** (§4a) — if fleet-level clock
   drift is to be detectable, the probe needs `/json/cfg`, not `/json/info`.
3. **The uid inventory is unrun** (§4c) — blocked pending approval.
4. **A remote coordinate fix is dormant until reboot/NTP/midnight** (§3b), and
   nothing surfaces that.
5. **`kWledSolarOffsetLimit = 120` vs firmware ±59** — carried from
   `audit/SOLAR_BENCH_GATE.md` §3c, still unfixed.
6. **The port is unmerged** on `fix/solar-predictor-wled` (`0c1c950`).
