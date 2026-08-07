# BRIDGE FLEET TRIAGE — who has one, who lost one, who never had one

**Date:** 2026-08-05 (queried 20:37–20:46 UTC) · **Branch:** `main` @ `0a76629` (`2.5.10+64`)
**READ-ONLY.** Three Firestore/Auth queries were run against production. **No writes of any
kind** — no document created, updated or deleted, no flag flipped, no registry row touched.

Splits the nine non-reaching accounts from
[UNATTENDED_OPERATION.md §2.4](audit/UNATTENDED_OPERATION.md), which found unattended reach
at 6 of 15 controller-owning accounts.

---

## 0. THE CALL LIST — start here

Ordered by *what the customer is experiencing*, not by how stale the device is.

| # | Who | Email | The conversation |
|---|---|---|---|
| ~~**1**~~ | ~~**The Iron Reserve**~~ | ironreserveclub@gmail.com | ✅ **RESOLVED 2026-08-05 21:15 UTC — paired, verified end-to-end. See §0a.** *(Was: bridge installed, powered, online, never paired; 17 commands, every one failed.)* |
| **2** | **Ellie Cochran** | ecochran08@yahoo.com | **"Your bridge went offline on 21 July and you've been hitting a wall ever since."** 547 commands, most recent **1.8 days ago**, of which **177 timed out and 27 failed.** She is actively using the app against a dead bridge |
| **3** | **Jim Dyer** | jjdyer1@hotmail.com | **"Remote control has never once worked for you, and you appear to have given up."** 166 commands between 45 and 32 days ago — **zero completed, ever.** Nothing since. No bridge has ever reported for this account |
| **4** | **Darrin Nicholas** | dnicholas0131@gmail.com | Remote access is **on**, no bridge has ever reported. Previously held 50 commands aged 31–78 days, all `pending`, since expired by the S2 sweeper (COMMAND_SAFETY D1) and then deleted by retention |
| **5** | **Chris Paschall** | cpaschall10@gmail.com | Bridge dark since **15 July (21.4 d)** — but no evidence he has noticed. Zero commands in the retained window and one sign-in ever. **Lowest urgency of the dark bridges; still a support call** |
| **6** | **Brooke Rozenberg** | brooke.rozenberg1@gmail.com | **No call needed.** She is live. A *superseded* bridge of hers still claims her UID and is inflating the fleet-offline count — that is a data-cleanup task, not a customer issue |
| — | Darian Brosa · Jeff Gruenewald | dbrosa99@icloud.com · thegruenewalds@gmail.com | **No bridge, remote access off, no failed commands.** Either they were never sold one or they never wanted one. **Sales/records question, not a support call** |

---

## 0a. RESOLVED — The Iron Reserve paired and **verified end-to-end**, 2026-08-05 21:15 UTC

Tyler paired `582ABD77687C` ~35 minutes after this triage was written. The question asked
was the right one: **`status: "paired"` in the registry is not proof the pairing took** — the
row could flip while the device never persisted the uid to NVS. Four independent facts
establish that it did.

**1 — The registry row is bridge-written, not client-written.** Under
[firestore.rules:805-809](firestore.rules#L805), a *user* may only write `pendingUid`, and
only while `status == "unpaired"`. Only `isBridge()` (auth email `bridge@nex-genled.com`)
may write `pairedUid` or `status`. So `status: paired` + `pairedUid: r0iBwg8bye…` +
`pendingUid` **cleared back to `""`** could only have been written by the device itself.

**2 — `users/r0iBwg8bye…/bridge_status/current` now EXISTS. It did not at 20:46.**

```
createTime : 2026-08-05T21:15:17Z   ← the document's FIRST-EVER write
updateTime : 2026-08-05T21:18:53Z   ← and it is heartbeating
wifi: true · errors: 0 · commands: 8 · ip: 10.1.10.70 · version: 1.2
```

This is the strongest single signal, because it is a **different document in a different
collection** that the bridge only writes once it has adopted a uid. §4 recorded this
account as having no `bridge_status/current` document *ever*. That is now false, and the
`createTime` timestamps the moment it changed.

**3 — NVS persistence confirmed by survival across heartbeats.** The bridge re-asserts
`pairedUid` from NVS on *every* heartbeat
([main.cpp:1046](esp32-bridge/src/main.cpp#L1046)) — which is precisely why F-5b says a
server-side reset gets overwritten within one beat. Turned around, that property makes it a
free NVS test: a `pairedUid` that survives repeated heartbeats **is** the NVS proof.

```
pairingRequestedAt  21:14:55Z
lastSeen            21:18:22Z   → 21:19:54Z    (pairedUid unchanged, pendingUid still "")
```

~5 minutes ≈ 10 heartbeats at the 30 s cadence, every one re-asserting the same uid. It
stuck in flash, not just in RAM.

**4 — A real command completed with a real controller response. This is the one that
matters.**

```
21:13:59Z  getInfo   timeout     ← pre-pairing
21:14:19Z  getInfo   timeout     ← pre-pairing
21:14:29Z  getInfo   timeout     ← pre-pairing
   ── 21:14:55Z  pairing requested ──
21:15:58Z  getInfo   completed   result={"ver":"0.15.1","vid":2507300,"cn":"Kōsen",
                                         "release":"ESP32_Ethernet", …}
21:15:58Z  ping      completed
```

Command totals moved from **17 (9 timeout / 8 expired / 0 completed)** to **21 (12 timeout /
7 expired / 2 completed)**. The `result` field carries WLED's own response body — so the
full path **cloud → bridge → controller at 10.1.10.240 → response** is proven, not inferred.
Three timeouts immediately before the pairing and a completion 63 seconds after it is about
as clean a before/after as this system can produce.

### Three things that fell out of the verification

- **Their controller is on the correct pinned firmware.** `ver: 0.15.1`, `vid: 2507300` —
  the version pinned in SOP §2.0 after the 0.15.4 stall regression. **No action.**
- **This is S6, working, for free.** SCHEDULING_ARCHITECTURE_V2 §6 argued that a scheduled
  `getState`/`getInfo` probe would yield a per-account build/version signal with zero
  firmware work. That is exactly what the `result` field just produced — an unprompted
  live demonstration on a real customer account. It strengthens the case for pulling S6
  forward (Finding 9 of UNATTENDED_OPERATION.md).
- **`cn` is not a unique identifier.** This controller reports `"cn":"Kōsen"` — the same
  name carried by the bench controller. It is a flash-image default, not a per-install
  name. Harmless, but do not use `cn` to identify a site.

**Net effect on the triage:** unattended reach moves from **6/15 to 7/15**, and from 5 to 6
among the 12 real customers. Bucket C-1 is now empty.

---

## 1. METHOD, AND TWO CAVEATS THAT CHANGE HOW TO READ THIS

**Sources.** `bridge_registry/*` (all 11 docs), `users/{uid}/bridge_status/current` (server
`updateTime` — the firmware writes counters, not a `lastSeen` field, so the doc's write time
is the authoritative heartbeat), `users/{uid}` flags, `users/{uid}/controllers/*`,
`users/{uid}/commands/*`, `installations/*`, and Firebase **Auth** records. Identity is
keyed on **email**, taken from Auth — a source independent of the Firestore doc being
measured — per the §2.4a discipline.

> **Caveat 1 — `display_name`, not `displayName`.** The user doc uses snake_case
> (`display_name`), per the repo's serialization convention. A camelCase read returns `null`
> for every account. My first triage pass did exactly that and would have produced a
> nameless call list. Called out because it is the same trap as the `bridge_health` path
> probe: a query that returns a plausible answer against the wrong field.

> **Caveat 2 — absence of commands is NOT evidence of non-use.** `runDataCleanup` deletes
> commands older than **7 days** ([functions/index.js:1152-1165](functions/index.js#L1152)),
> capped at 450 per user per run, and it **ran for the first time ever on 2026-08-05** —
> hours before this query. The results are visibly uneven: Ellie retains commands 67.7 days
> old and Steve Stegall 74.9 days, while Darrin Nicholas and Chris Paschall show zero. That
> is consistent with a **partial first run** (the deployed build still lacks the C5 per-user
> query caps, which are committed but undeployed — `0a76629`).
>
> **So: recent failing commands prove active use. Zero commands prove nothing.** Every
> "never tried" claim below rests on flags and registry data, never on a zero count.

**Scope.** 15 accounts own at least one controller. Three are not customers:
`nex-genadmin@nex-genled.com` (Demo), `staff_installer_5502` (installer staff, no
installation record), and `tyler.honeycutt@nex-genled.com` / "Trend Setter" (the bench).
**Twelve are real customers.**

---

## 2. BUCKET A — LIVE. No action. (6 accounts / 5 customers + bench)

Heartbeat inside 10 minutes at query time, from both `bridge_status/current` and
`bridge_registry.lastSeen`.

| display_name | Email | Bridge device | Bridge IP | Controller | Last heartbeat | Commands (retained) |
|---|---|---|---|---|---|---|
| Trend Setter *(bench)* | tyler.honeycutt@nex-genled.com | `0070077F92C8` | 192.168.1.96 | 192.168.1.150 | 20:44:26Z | 1309 — 1006 ok / 63 fail / 240 timeout |
| Taps On Main *(commercial)* | marc@tapsonmain.com | `20E7C8AFD174` | 192.168.10.241 | 192.168.10.201 | 20:44:24Z | 113 — 110 ok / 2 fail / 1 timeout |
| Steve Stegall | stegall.s@yahoo.com | `E08CFE405538` | 192.168.1.237 | 192.168.1.250 | 20:44:05Z | 2854 — 2139 ok / 79 fail / 635 timeout |
| Chris Cipollone | chris_cipollone@simonton.com | `20E7C86BAAB4` | 192.168.1.83 | 192.168.1.250 | 20:44:27Z | 20 — 16 ok / 1 fail / 3 timeout |
| Tim Kelly | textim6@yahoo.com | `D4E9F4FA8E78` | 10.0.0.243 | 10.0.0.100 | 20:44:17Z | 7 — 7 ok |
| Brooke Rozenberg | brooke.rozenberg1@gmail.com | `D4E9F4FA54B8` | 192.168.86.34 | 192.168.86.250 | 20:44:03Z | 17 — 8 ok / 9 timeout |

All six carry `bridge_paired: true` and `remote_access_enabled: true`; none uses webhook
mode. **Brooke additionally owns a second, superseded registry row — see §7.**

⚠️ **Worth a separate look, not part of this triage:** timeout rates on *live* bridges are
not small — Steve **635/2854 = 22 %**, Tyler **240/1309 = 18 %**. A `timeout` is written by
the app's own 45 s watchdog
([cloud_relay_repository.dart:286-290](lib/features/wled/cloud_relay_repository.dart#L286)),
so each one is a customer who waited three quarters of a minute and got nothing. "Live
bridge" and "good experience" are not the same claim, and this triage does not establish
the second.

---

## 3. BUCKET B — WENT DARK. A device exists, once reported, now stale. (2 accounts)

Both are genuine regressions: `bridge_status/current` has a `createTime` weeks before its
last `updateTime`, so each bridge worked for a sustained period and then stopped. Nothing in
the data distinguishes a power cycle from a router/SSID change — that is a phone call.

### B-1 · Ellie Cochran — `ecochran08@yahoo.com` — **dark 15.0 days, and she is still trying**

| | |
|---|---|
| Bridge | `D4E9F4FA9D40` @ **10.0.0.112**, firmware 1.2 |
| Controller | `20_e7_c8_f4_d5_38` @ 10.0.0.32 (same /24 — same house) |
| **Last heartbeat** | **2026-07-21T21:11:15Z** (`bridge_status`) / **T21:11:16Z** (`registry`) — agreeing to one second |
| Worked from | `bridge_status` created **2026-05-30** → ran ~7.5 weeks before stopping |
| Flags | `bridge_paired: true`, `remote_access_enabled: true`, `bridge_ip: 10.0.0.112` |
| Install | `ztB9L6Cl4YalDqi58s5h` — 924 SE Wood Ridge Court, Blue Springs · dealer 55 |
| **Commands** | **547** — 326 completed, **177 timeout**, 27 failed, 6 expired, 11 stuck `executing`. **Newest: 2026-08-04 (1.8 days ago)** |

> **This is the sharpest live outage in the fleet.** Her bridge died on 21 July; she has been
> issuing commands since — including two days ago. Every off-LAN action she takes now costs
> her a 45-second wait and a failure. She has no way to know why.
>
> Note her Auth `lastSignInTime` reads 2026-07-02, *before* the bridge died —
> `lastSignInTime` only updates on a fresh sign-in, not on app use, so **it is useless as a
> usage signal.** Command timestamps are the real one.

### B-2 · Chris Paschall — `cpaschall10@gmail.com` — **dark 21.4 days, apparently unnoticed**

| | |
|---|---|
| Bridge | `D4E9F4FAA5F4` @ **192.168.1.197**, firmware 1.2 |
| Controller | `80_f3_da_af_69_60` @ 192.168.1.201 (same /24) |
| **Last heartbeat** | **2026-07-15T12:17:00Z** (`bridge_status`) / **T12:16:38Z** (`registry`) |
| Worked from | `bridge_status` created **2026-05-14** → ran ~2 months |
| Flags | `bridge_paired: true`, `remote_access_enabled: true`, `bridge_ip: 192.168.1.197` |
| Install | `kKP6b8ZR7wdQZLQVHW8p` — 1017 SE Beatty Ct, Blue Springs · dealer 55 |
| Commands | **0 in the retained window.** Auth shows one sign-in ever (2026-05-14, the day after signup) |

**Stalest active bridge in the fleet**, but the *least* felt: no retained evidence of remote
use, and a single recorded sign-in. Per Caveat 2 the zero is not proof he never tried —
but combined with the sign-in record, "dormant customer" is the most likely reading.
**Still worth the call:** he is paying for a system whose remote half has been dead for
three weeks, and he may simply have stopped expecting it to work.

---

## 4. BUCKET C — NEVER REPORTED. (7 accounts / 4 customers + 3 internal)

No `bridge_status/current` document has **ever** existed for these accounts, and none has a
`bridge_registry` device paired to its uid. But they are **not one problem** — they split
three ways, and the differences are the whole point of this section.

### C-1 · HARDWARE IS THERE AND ONLINE — PAIRING NEVER COMPLETED (1) — ✅ **NOW EMPTY, RESOLVED 21:15 UTC (§0a)**

> **Superseded 35 minutes after writing.** Retained as the diagnosis of record; the
> end-to-end verification is in §0a. The state below is as observed at 20:46 UTC.

**The Iron Reserve — `ironreserveclub@gmail.com` — and this is the headline of the triage.**

```
bridge_registry/582ABD77687C
  status     : unpaired          ← never claimed by any account
  pairedUid  : ""
  pendingUid : ""
  ip         : 10.1.10.70
  lastSeen   : 2026-08-05T20:45:42Z   ← 0 days. HEARTBEATING RIGHT NOW.
  firmware   : 1.2
```

**Subnet correlation is unambiguous.** `10.1.10.x` has exactly **one** controller owner in
the entire fleet: `ironreserveclub@gmail.com` @ **10.1.10.240**. No other account is on that
network. A bridge is powered, on their LAN, talking to Firestore — and unpaired.

| | |
|---|---|
| Flags | `bridge_paired: false`, **`remote_access_enabled: true`** |
| Install | `6glJfSUyzxjUVHEW3Mjr` — 20050 East Jackson Drive, Independence · **dealer 01** |
| Account created | 2026-07-31 |
| **Commands** | **17 — 9 timeout, 8 expired, ZERO completed. Newest 0.8 days ago** |

> **A new commercial customer, installed five days ago by dealer 01, has been trying to use
> remote control since day one. Their bridge is sitting there powered and online. The
> pairing step never happened, or did not stick.** Everything they have sent has failed.
>
> This is the cheapest fix on the list and the most recent install — which makes it also a
> **dealer-onboarding signal**: dealer 01's first commercial job shipped with an unpaired
> bridge and nothing flagged it. Worth checking against Chris Cipollone (also dealer 01,
> also 1 Aug, and *correctly* paired) to see whether this was a one-off or a process gap.

### C-2 · REMOTE ACCESS ENABLED, NO BRIDGE ANYWHERE (2 — 1 customer, 1 internal)

The prompt's exact question: an account with `remote_access_enabled` and no bridge that ever
reported is a **different problem** from one that never had a bridge. Confirmed — this is
the class where the app is in remote mode, writes commands, and nothing on earth executes
them.

| display_name | Email | `bridge_paired` | `remote_access_enabled` | Registry | Commands |
|---|---|---|---|---|---|
| **Darrin Nicholas** | dnicholas0131@gmail.com | `false` | **`true`** | none, ever | 0 retained — **but held 50 commands aged 31–78 days**, all `pending`, expired by the S2 sweeper on 2026-08-01 (COMMAND_SAFETY D1) and since deleted by retention |
| `staff_installer_5502` *(internal)* | — | `false` | **`true`** | none | 0 |

Darrin's history is the proof that this class is real and costly: **50 commands, up to 78
days old, sat unexecuted** — the largest single backlog the sweeper found. Install
`OhwV4qHrAXGioSSjbrXJ`, 901 SE Wood Ridge Ct, Blue Springs, dealer 55.

### C-3 · NO BRIDGE, REMOTE ACCESS OFF, NO EVIDENCE ONE WAS EVER FITTED (4 — 2 customers, 2 internal)

| display_name | Email | Flags | Registry | Commands | Reading |
|---|---|---|---|---|---|
| Darian Brosa | dbrosa99@icloud.com | both `false` | none | 0 | Installed 2026-07-16 (dealer 55). Clean LAN-only install |
| **Jim Dyer** | jjdyer1@hotmail.com | both `false` | none | **166 — 128 timeout, 38 expired, ZERO completed.** Oldest 44.8 d, newest 31.7 d | **⚠️ Not clean. See below** |
| Jeff Gruenewald | thegruenewalds@gmail.com | both `false` | none | 0 | Installed 2026-05-16; controller doc id is an auto-ID, not a MAC (`g6YTg5yhRXOaUvfdM6qL`) — added by hand rather than by the wizard |
| Demo *(internal)* | nex-genadmin@nex-genled.com | both `false` | none | 0 | Demo account. Expected |

> **Jim Dyer breaks the bucket, and reveals a design fact.** His `remote_access_enabled` is
> **`false`** — yet he accumulated 166 relay commands, none of which ever completed. That
> is only possible because **`remote_access_enabled` does not gate the relay write path.**
> Repository selection reads *connectivity*, not the flag:
>
> ```dart
> // lib/features/wled/wled_providers.dart:209-228
> if (connectivityStatus == ConnectivityStatus.local) return WledService('http://$ip');
> if (userId != null && controllerId != null) return CloudRelayRepository(...);
> ```
>
> So **any** customer who opens the app off their home Wi-Fi is routed into the bridge relay
> whether or not they have a bridge, whether or not the toggle is on. With no bridge, each
> action is a 45-second wait ending in `timeout`. Jim did that 166 times over ~13 days and
> then stopped, 31.7 days ago. **He is a churn signal, not a records gap.**
>
> This also means `remote_access_enabled` is unreliable as a triage field: it tells you what
> the customer *intended*, not what the app *does*. Combined with the memory note that
> SSID-null defaults to *local*, the flag is doing much less work than its name implies.

---

## 5. WAS A BRIDGE EVER SOLD OR INSTALLED? — **the schema cannot answer this**

The prompt asks for installation-record evidence. There is none to be had, and that is
itself the finding.

Union of **every** field key across all 15 `installations` documents:

```
address · city · controller_serials · dealer_code · dealer_company_name · id ·
installed_at · installer_code · installer_name · is_active · max_sub_users ·
primary_user_email · primary_user_id · primary_user_name · primary_user_phone ·
site_mode · state · system_config · warranty_expires · zip_code
```

**No `bridge`, `relay` or `remote` field exists on any installation record.**
`controller_serials` lists WLED controllers only. So the commissioning record captures what
controllers were fitted and by whom — and is **silent on whether a bridge was part of the
job.** There is no way to distinguish "sold without a bridge" from "sold with a bridge that
was never installed" from "installed but never powered."

The only available evidence, in descending strength:

| Evidence | Strength | Who it resolves here |
|---|---|---|
| A registry device on the account's **LAN subnet** | **Strong** where the subnet is unique | Proved The Iron Reserve (C-1). Useless on `192.168.1.x`, shared by 7 accounts |
| `bridge_status/current` `createTime` | **Definitive** that one worked once | Both bucket-B accounts |
| `bridge_paired` + `bridge_ip` on the user doc | Strong, but **stale-by-design** — never cleared when a bridge dies | Both bucket-B accounts still read `true` |
| `remote_access_enabled` | **Weak** — does not gate the relay (§4 C-3) | Misleading on its own |
| Failed command history | Moderate, and **now truncated to 7 days** | Jim Dyer, Iron Reserve |

> **Recommendation (records, not code):** add a `bridge_serial` / `bridge_installed`
> field to the installation record at commissioning. It costs nothing at write time and it
> is the single field that would have made this entire triage a one-line query instead of a
> subnet-correlation exercise. Until then, "was a bridge sold?" is answerable only from
> dealer paperwork.

---

## 6. WHAT A DARK BRIDGE COSTS THE CUSTOMER — and what still works

### Lost — everything on the `/json/state` relay path

When off-LAN, `CloudRelayRepository` is the *only* repository
([wled_providers.dart:214-228](lib/features/wled/wled_providers.dart#L214)). With the bridge
dark, every one of its methods writes a command that is never picked up, waits **45 s**, and
resolves to `timeout`:

| Surface | Method | Customer-visible effect |
|---|---|---|
| Power on/off | `setState` / `setPower` | Dead |
| Brightness | `setState` | Dead |
| Apply any pattern or scene | `applyJson` | Dead |
| Per-channel / segment control | `applyToSegments`, `updateSegmentConfig` | Dead |
| Per-pixel Design Studio push | `applyPerPixel` (chunked) | Dead |
| **Remote preset save** | `savePreset` (`psave` via `/json/state`) | Dead |
| Load a preset | `loadPreset` (`{ps:N}`) | Dead |
| Read current state | `getState` | Dead — dashboard cannot show what the lights are doing |
| Device info / RGBW / LED count | `getInfo`, `supportsRgbw`, `getTotalLedCount` | Dead |
| Segment list / rename | `fetchSegments`, `renameSegment` | Dead |
| Clock health | `fetchClockInfo` | Dead |
| Neighborhood Sync / Game Day fan-out | via `applySyncPattern` → same queue | Dead |

Plus: **each failure costs 45 seconds of waiting**, and the error the customer sees is a
generic timeout — nothing says "your bridge is offline." Ellie's 177 timeouts are ~2.2 hours
of cumulative staring at a spinner.

### Never worked remotely anyway — not a loss

- **Anything on `/json/cfg`.** `CloudRelayRepository.applyConfig` throws
  `CfgWriteUnsupportedException`; the bridge has no cfg dispatch branch. So **arming
  schedules/timers was never possible off-LAN**, bridge alive or dead. A dark bridge takes
  nothing extra here.

### Still works — and this is why a customer may not have noticed

| Surface | Depends on the bridge? | Why |
|---|---|---|
| **All on-LAN control** — power, brightness, patterns, presets, Design Studio, schedule arming | ❌ No | At home the app builds a direct-HTTP `WledService` and never touches the relay ([:209-213](lib/features/wled/wled_providers.dart#L209)) |
| **Device timers** — sunset-on, sunrise-off, the whole base schedule | ❌ No | Flash-resident on the controller, fired by its own RTC. Zero cloud, zero app, zero LAN |
| **Saved presets already on the controller** | ❌ No | Resident in flash |
| **Everyday lighting behaviour, end to end** | ❌ No | The lights come on and go off correctly every night |

> **This is the reason two customers have been dark for 15 and 21 days without a support
> ticket.** Their lights have been working perfectly the entire time. Nothing is broken that
> they can see from the driveway. The failure is confined to *remote* control — which they
> only discover when they are away, at which point they get a 45-second spinner and a
> generic error, and quite reasonably assume it is their phone signal.
>
> **Nothing in the app or in any dashboard reports a stale bridge to anyone** — not to the
> customer, not to the dealer, not to Tyler. That is
> [OFF_LAN_CAPABILITY.md §3.3](audit/OFF_LAN_CAPABILITY.md)'s fleet-blindness, and this
> triage is its cost, itemised. **S6 (~8 h) is what turns this document from a one-off
> script into a standing alert.**

---

## 7. ORPHANED REGISTRY ROWS, AND HOW THEY MEET F-5b

All 11 `bridge_registry` documents, with everything not currently healthy called out:

| deviceId | status | claims | IP | lastSeen | age | Assessment |
|---|---|---|---|---|---|---|
| `0070077F92C8` | paired | Trend Setter | 192.168.1.96 | 20:37:28Z | 0 d | ✅ healthy |
| `20E7C86BAAB4` | paired | Chris Cipollone | 192.168.1.83 | 20:37:09Z | 0 d | ✅ healthy |
| `20E7C8AFD174` | paired | Taps On Main | 192.168.10.241 | 20:37:26Z | 0 d | ✅ healthy |
| `D4E9F4FA54B8` | paired | Brooke Rozenberg | 192.168.86.34 | 20:37:34Z | 0 d | ✅ healthy |
| `D4E9F4FA8E78` | paired | Tim Kelly | 10.0.0.243 | 20:37:38Z | 0 d | ✅ healthy |
| `E08CFE405538` | paired | Steve Stegall | 192.168.1.237 | 20:37:09Z | 0 d | ✅ healthy |
| **`582ABD77687C`** | ~~unpaired~~ → **paired** | ~~—~~ → **The Iron Reserve** | 10.1.10.70 | 20:45:42Z → **21:19:54Z** | 0 d | ✅ **PAIRED 21:14:55Z, verified end-to-end (§0a)** |
| **`0070077E8F60`** | **paired** | **Brooke Rozenberg** | 192.168.86.187 | 2026-07-14T21:56:30Z | **21.95 d** | 🔴 **ORPHAN claiming a live UID** |
| `D4E9F4FA9D40` | paired | Ellie Cochran | 10.0.0.112 | 2026-07-21T21:11:16Z | 14.98 d | 🔴 Dark, correctly claimed (bucket B-1) |
| `D4E9F4FAA5F4` | paired | Chris Paschall | 192.168.1.197 | 2026-07-15T12:16:38Z | 21.35 d | 🔴 Dark, correctly claimed (bucket B-2) |
| `007007745388` | unpaired | — | 192.168.1.41 | 2026-06-09T13:24:31Z | **57.31 d** | ⚪ Dead and unclaimed. **Unattributable** — `192.168.1.x` is shared by 7 accounts, so subnet correlation cannot identify it. Most likely a bench/spare unit |

### Is the old device still paired? — **Yes, and it is the only true orphan**

`0070077E8F60` still carries `status: "paired"`, `pairedUid: Q8VIQ9lrIASO6mHRAI7k5ebF5U72`
(Brooke) after 21.95 days of silence, while her live replacement `D4E9F4FA54B8` runs
alongside it. **Both are on her `192.168.86.x` LAN**, so this is a genuine
replaced-in-place unit, not a mis-pairing.

Its practical harm today is **reporting, not function**: nothing routes commands by registry
row (the bridge polls the *user's* command queue, and the live unit drains it), so Brooke is
unaffected. What it does is **inflate every fleet-health count by one** — it is exactly the
row that made "is the 15-day-stale bridge Brooke's?" a reasonable question in the first
place.

### Where this meets F-5b

[COMPLIANCE_AND_SECURITY.md §F-5b](audit/COMPLIANCE_AND_SECURITY.md) (P0-BLOCK) establishes
that a pairing cannot be released from the server side:

- `/bridge_registry/{deviceId}` is `allow delete: if false` ([firestore.rules:700](firestore.rules#L700))
- a **paired** bridge never polls for an unpair — `pollPairingRequest` returns early unless
  `currentStatus == "pairing"` ([main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220))
- and it re-asserts `pairedUid` from NVS on every heartbeat ([:1046](esp32-bridge/src/main.cpp#L1046))
  — so an Admin-SDK reset is overwritten within one beat

**Three observations this triage adds:**

1. **`0070077E8F60` is a *benign* instance of the F-5b shape** — the UID it claims still
   exists, so nothing is stranded and no truck roll is implied. But it is unreleasable by
   exactly the same mechanism. **Crucially, it is silent** — 22 days without a heartbeat —
   which means the "re-asserts from NVS every beat" defence does **not** apply to it. A
   one-off Admin-SDK reset of this row **would stick**, as long as the device stays off. If
   it is ever powered back on, it re-claims. That is a materially cheaper remedy than the
   F-5b general case, and worth taking while the window is open.
2. **The hardcoded blocklist is working.** Both blocked MACs — `441D64C935AC` and
   `E08CFE4049AC` ([firestore.rules:767-771](firestore.rules#L767)) — are **absent from
   `bridge_registry` entirely**, confirmed by direct doc reads. `isNotBlockedDeletedUid()`
   is denying their create/update as intended. No new blocklist entry is needed for anything
   in this triage.
3. **No registry row claims a non-existent UID.** Every `pairedUid` and `pendingUid` in the
   registry resolves to a live user document. **The fleet currently has zero F-5b-class
   stranded devices** — the two known ones are blocked out, and no new one has appeared.
   Worth recording as a clean state, because it will not stay clean once account deletion is
   exercised again.

---

## FINDINGS

| # | Finding | Severity |
|---|---|---|
| 1 | ~~**The Iron Reserve has a bridge powered, online and heartbeating on their LAN — status `unpaired`.**~~ Subnet correlation was unique (`10.1.10.x`, one controller owner); 17 commands in 5 days, zero completed. **✅ RESOLVED 21:15 UTC — paired and verified end-to-end (§0a): registry row bridge-written, `bridge_status/current` created at 21:15:17, uid survived ~10 heartbeats (NVS), and a `getInfo` completed 63 s post-pairing carrying WLED's real response.** Reach 6/15 → **7/15** | ✅ **CLOSED same day** |
| 1a | **`status: "paired"` alone would NOT have proven the pairing took** — the decisive evidence is a *different* document (`bridge_status/current` first-ever `createTime`) plus a completed command carrying a controller response. Recording the discriminator, because the next pairing will need the same check | Method |
| 2 | **Ellie Cochran is actively using the app against a bridge dark since 21 July** — 547 commands, newest 1.8 days ago, 177 timeouts. The one customer with a felt, ongoing outage | **P1 — call first among bucket B** |
| 3 | **Jim Dyer issued 166 relay commands over 13 days with zero ever completing, then stopped 31.7 days ago.** A churn signal that no dashboard surfaced | **P1** |
| 4 | **`remote_access_enabled` does not gate the relay write path.** Repository selection reads *connectivity* only, so any off-LAN customer with a controller is routed into the bridge queue regardless of the toggle — and with no bridge, every action is a 45 s wait ending in `timeout`. Jim Dyer is the proof | **P1 — design, and it makes the flag unreliable for triage** |
| 5 | **`installations` has no bridge field of any kind** (20 keys, none bridge-related). "Was a bridge sold or installed?" is **unanswerable from the records** — only subnet correlation, `bridge_status.createTime`, and dealer paperwork can answer it | **P2 — records gap** |
| 6 | **A dark bridge is invisible to the customer** because on-LAN control and all device timers are unaffected. Their lights work perfectly every night. That is why 15- and 21-day outages produced no support ticket | **The reason this list needed building** |
| 7 | `/json/cfg` was never available off-LAN (`applyConfig` throws), so a dark bridge costs **nothing extra** for schedule arming — it costs the entire `/json/state` surface: power, brightness, patterns, per-pixel, preset save/load, state reads, and both sync features | Scoping |
| 8 | **`0070077E8F60` is the fleet's only true orphan** — still `paired` to Brooke after 22 days of silence, alongside her live replacement. Harm is to reporting, not function. **Because it is silent, a one-off Admin-SDK reset would actually stick** — unlike the F-5b general case | **P2 — cheap while the window is open** |
| 9 | **Both hardcoded blocked MACs are absent from `bridge_registry`** — the rule is working. **No registry row claims a non-existent UID: zero F-5b-class stranded devices in the fleet today** | ✅ Clean state, worth recording |
| 10 | **Timeout rates on LIVE bridges are 18–22 %** (Steve 635/2854, Tyler 240/1309). Each is a 45 s wait. "Bridge is up" and "remote control is good" are different claims and this triage only establishes the first | **P2 — separate investigation** |
| 11 | **Command history is now truncated to 7 days**, and the first-ever retention run (2026-08-05) was visibly partial — some accounts retain 75 days, others zero. **Absence of commands is not evidence of non-use**; every "never tried" claim here rests on flags and registry data instead | Method — protects the conclusions |
| 12 | **`display_name` is snake_case.** A `displayName` read returns null for all 15 accounts and would have produced a nameless call list — the same "plausible answer against the wrong field" class as the `bridge_health` path probe | Method |
| 13 | Auth `lastSignInTime` updates only on fresh sign-in, not on app use — Ellie shows 2026-07-02 while issuing commands on 2026-08-04. **Useless as a usage signal; command timestamps are the real one** | Method |
| 14 | **Dealer-onboarding signal:** dealer 01's two installs are Chris Cipollone (paired correctly, 1 Aug) and The Iron Reserve (unpaired, 31 Jul). Worth checking whether bridge pairing is a reliably-completed step in that dealer's process | **P2 — process** |
