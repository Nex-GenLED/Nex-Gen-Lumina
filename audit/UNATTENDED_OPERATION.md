# UNATTENDED OPERATION — Game Day and Neighborhood Sync

**Date:** 2026-08-05 · **Branch:** `main` @ `0a76629` (`2.5.10+64`) · **DESIGN ONLY.**
Nothing implemented, no branch created, no file outside `audit/` touched. One read-only
Firestore census was run against production (§2.4); no writes.

**Goal as stated:** both features working when the relevant user's app is closed and they
are not on their home network.

---

## 0. THE HEADLINE — the background service is compiled off, so today the answer is ZERO

Everything below is downstream of one constant:

```dart
// lib/features/sports_alerts/services/sports_background_service.dart:29
const bool kSportsBackgroundServiceEnabled = false;
```

Both entry points early-return on it —
[`initialiseSportsBackgroundService`](../lib/features/sports_alerts/services/sports_background_service.dart#L47-L48)
and [`startSportsService`](../lib/features/sports_alerts/services/sports_background_service.dart#L71-L72) —
and every caller in `lib/` routes through one of those two
(`main.dart:211`, `autopilot_scheduler.dart:480`, `sports_alert_notifier.dart:79`,
`sync_event_providers.dart:361` → `startSyncEventService` → `startSportsService`).
`performQuickSyncCheck` (the iOS background-fetch pass) is called from exactly one place —
`_onIosBackground` at `:304` — which is only registered by the `configure()` call that
early-returns.

It is stripped at the manifest level too. `AndroidManifest.xml` removes
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` and `RECEIVE_BOOT_COMPLETED` with
`tools:node="remove"`, and removes the plugin's own
`id.flutter.flutter_background_service.BackgroundService` `<service>` node
([:139-140](../android/app/src/main/AndroidManifest.xml#L139-L140)).

> **Consequence, stated plainly.** `GameDayAutopilotBackgroundWorker` and
> `SyncEventBackgroundWorker` — the two classes that contain **all** of the app-closed
> logic for these features, roughly 1,600 lines between them — **have never executed in a
> shipped build and cannot execute in the current one.** Both features are, today, 100 %
> foreground-only. This is not a degradation to be tuned; the capability is absent.

This is not a surprise defect — it was a deliberate release decision (avoid the Play FGS
declaration + demo video). But it reframes the question. The choice is not "improve
unattended operation," it is **pick which of two mechanisms to build it on**:

| | Path A — re-enable the device background service | Path B — server-side dispatcher (S3) |
|---|---|---|
| Restores | The existing 1,600 lines, as written | Nothing; new code |
| Android cost | Manifest restore + **Play FGS declaration + demo video**, per release | none |
| iOS cost | Background fetch is opportunistic, ~15-20 s, **not scheduled** — a 19:07 first pitch is not a thing iOS will wake you for | none |
| Phone off / dead / rebooted | ❌ (`autoStartOnBoot:false`) | ✅ |
| Phone in another timezone / airplane mode | ❌ | ✅ |
| Auth | Needs a <1 h ID token the app must have refreshed (§1.1 F-2) | Admin SDK — no token |
| Fires when | Best-effort, OS-scheduled | Deterministic, minute cron |

**Recommendation: Path B for both features.** Path A cannot deliver "app closed" on iOS at
all — iOS background fetch is opportunistic and will not wake an app for a specific wall
clock instant — so it can never satisfy the stated goal on half the fleet. Path B is
already designed (SCHEDULING_ARCHITECTURE_V2 §2), already precedented in production
(Google Smart Home and Alexa both write commands server-side), and its two hard gates are
now shipped and deployed.

---

# PART 1 — GAME DAY

## 1.1 What in the current path requires the app

The Game Day path exists in **three** parallel implementations. This matters because the
S5 estimate was written against one of them.

| # | Implementation | File | Status today |
|---|---|---|---|
| 1 | `GameDayAutopilotService` | [game_day_autopilot_service.dart](../lib/features/autopilot/game_day_autopilot_service.dart) | Foreground only; 1-minute `evaluateConfigs` loop driven from providers |
| 2 | `GameDayAutopilotBackgroundWorker` | [game_day_autopilot_background_worker.dart](../lib/features/autopilot/game_day_autopilot_background_worker.dart) | **Inert** (§0). This is the one S5 proposed porting |
| 3 | `EphemeralGameSessionService` (the phase machine that lights a mid-game join) | [ephemeral_game_session_service.dart](../lib/features/game_day/ephemeral_session/ephemeral_game_session_service.dart) | Foreground only; 1-minute `Timer` |

Component-by-component:

| Piece | Where its state lives | Requires the app? | Server equivalent |
|---|---|---|---|
| **ESPN poll** — `hasGameSoon`, `fetchTeamGame`, `fetchSeasonSchedule` | none (stateless HTTP) | Yes, only because the caller is in-process | ✅ **Trivial.** ESPN is an unauthenticated public API; a Cloud Function can call it. No blocker at all |
| **Config** (`enabled`, team, colours, design, `skipDayGames`, `untilDate`) | **Firestore** `users/{uid}/game_day_autopilot/{teamSlug}` ([:205](../lib/features/autopilot/game_day_autopilot_providers.dart#L205)) — *and* mirrored to SharedPreferences for the isolate | Only the mirror does | ✅ **Already server-readable.** Read the Firestore doc; the prefs mirror is redundant server-side |
| **Phase machine** (`idle → preGame → liveGame → postGame → completed`) | In-memory `Map<String, AutopilotSession>` (#1), SharedPreferences (#2), Firestore `users/{uid}/ephemeral_game_sessions` (#3) | Yes for #1/#2 | ✅ Straightforward — the machine is a pure function of (config, ESPN state, now). Give it a Firestore home |
| **30-minute pre-game window** | `_kPreGameLeadTimeMinutes`, `config.effectiveLeadTimeMinutes` | Yes | ✅ Pure arithmetic |
| **30-minute post-game countdown** | `session.countdownEnd` in the session record | Yes | ✅ Pure arithmetic — but see §3.3: a countdown that spans a function restart must be a *stored deadline*, not a timer, which it already is |
| **Duration fallback** (`gameStart + estimatedDuration + 60 min`) | `_estimatedDuration(sport)` — a hardcoded switch | Yes | ✅ Pure |
| **Daylight filter** (`skipDayGames`) | `SunUtils.sunsetLocal(lat, lon, …)` + `loadUserLocation()` | Location is mirrored from `currentUserProfileProvider` | ✅ lat/lon are on the user profile doc. `SunUtils` is a pure Dart port of a standard algorithm — would need re-implementing in TS, ~2 h, or the function can use a published solar library |
| **Priority resolution** (Game Day vs Neighborhood Sync) | `GameDayPriorityResolver` — pure; inputs are the two workers' persisted sessions | Yes | ⚠️ Needs both session machines on the same (server) side to be meaningful. Falls out of S5 only if sync also moves server-side |
| **Participating-channel resolution** | `resolveParticipatingChannels(explicit, rooflineSegments, allDeviceChannelIds)` — pure, but `allDeviceChannelIds` comes from the **device's bus list**, read over `/json/cfg` | **Yes — and this one has no clean server equivalent** | ❌ **See below.** This is the only genuine gap |
| **Firebase ID token** for `applySyncPattern` | SharedPreferences, written by the foreground on auth change and on app *resume* | **Yes — hard** | ✅ Disappears entirely on Path B (Admin SDK) |
| **User override check** (`onGetCalendarEntry` — a `user`-type entry wins over autopilot) | Firestore calendar entries | No | ✅ Server-readable |
| **Calendar population** (`populateCalendarForTeam`, rolling 7-day) | Firestore `calendar_entries` | No | ✅ Server-readable/writable |

### The two that do not port cleanly

**F-1 — channel participation is device-derived and device-cached, and the server has
none of it.** `resolveParticipatingChannels` needs `allDeviceChannelIds`, which is the
controller's *bus* list — read from `/json/cfg`, which is **LAN-only** (the bridge has no
cfg dispatch branch; `CloudRelayRepository.applyConfig` throws
`CfgWriteUnsupportedException`). The resolver's *output* is cached in SharedPreferences
via `saveLocalParticipatingChannels`, i.e. on the phone. Worse, per
[CHANNEL_MAPPING_AUDIT_2026-05.md:459](../docs/audits/CHANNEL_MAPPING_AUDIT_2026-05.md) —
which I re-confirmed by grep — **no UI in `lib/` ever writes
`participatingChannelIndices` to a non-null value**, on either
`GameDayAutopilotConfig` or `NeighborhoodMember`. The field is serialized, `copyWith`-able
and read by the resolver, and is always `null` in production.

*Design consequence:* a server-side fire cannot compute the participating set. Three
options, in order of preference:

1. **Denormalize the resolved set to Firestore.** The app already resolves it whenever it
   is open; have it write the result to `users/{uid}/controllers/{id}.participating_channels`
   alongside the existing `controller_ips` denormalization (same trigger pattern as
   `syncControllerIps`). Cheap, and it is the same shape S1 already established. ~4 h.
2. **Fire unfiltered** — a single seg-no-id payload, which WLED applies to seg 0 only.
   This is the pre-#29 behaviour and is a visible regression for multi-channel installs.
3. **Fire the 8-channel broadcast shape** the sync worker uses
   (`buildPatternPayloadForTest`, `id: 0..7`) — lights *everything*, including the patio
   the customer deliberately excluded.

Option 1 is the only one that preserves the #29 fix. **It is a prerequisite for S5, and it
was not in the S5 estimate.**

**F-2 — the persisted ID token has an expiry field that nobody reads.** `saveSyncIdToken`
writes both the token and `expiresAt`
([:500-514](../lib/features/neighborhood/services/sync_event_background_persistence.dart#L500-L514)).
`loadSyncIdTokenExpiresAt` is defined at `:521` and, by repo-wide grep, **has zero
callers.** All six background call sites use bare `loadSyncIdToken()` and attach whatever
string is there. Firebase ID tokens live one hour; the only refreshes are on auth-state
change and on app *resume* (`main_scaffold.dart:118`).

> So even with the background service re-enabled (Path A), any fire more than ~1 hour after
> the last app foreground would attach an expired token, `applySyncPattern` would return
> **401**, and the failure would surface only as a `debugPrint`. **A "designed TTL with no
> reader" — the exact shape of the `expiresAt` finding in COMMAND_SAFETY §3.1, in a second
> place.** Path B deletes this problem rather than fixing it.

## 1.2 Does the celebration/score path use direct `applyJson`? — **Yes. Every Game Day
write is inline state. There is not a single preset load anywhere in the feature.**

Confirmed at every apply site:

| Path | Payload | Preset? |
|---|---|---|
| Foreground base show | `game_day_apply.dart` → `applyPayloadWithLabel` → `applyJson` | ❌ inline |
| Foreground revert | `ephemeral_game_session_service.dart:401` → `repo.applyJson(session.revertWledPayload)` | ❌ inline |
| Background base show | `buildBasePayloadForTest` → `{on, bri, seg:[{fx,sx,ix,pal,col}]}` | ❌ inline |
| Background celebration | `buildCelebrationPayloadForTest` → `{on:true, bri:255, seg:[{fx:11 Sparkle, sx:240, ix:240, col:[primary,secondary]}]}` | ❌ inline |
| Background celebration revert (+15 s) | `buildBasePayloadForTest` again | ❌ inline |
| Post-game default | `{'on': false}` | ❌ inline |
| `_buildWledPayload` (service #1) | `{on:true, bri, seg:[{fx,sx,ix,pal:0,col}]}` | ❌ inline |

`grep -rn 'psave\|loadPreset\|savePreset' lib/features/game_day lib/features/autopilot` →
**no matches.**

**This is the favourable answer.** Per SCHEDULING_ARCHITECTURE_V2 Correction 1, a cloud
fire carrying inline state consumes **zero preset slots** and needs nothing pre-staged on
the controller. Game Day is already in exactly the shape the cloud dispatcher wants.

Two carve-outs to record:

- **Saved designs bypass the builder.** `config.savedDesignPayload` ships verbatim from
  Firestore ([game_day_autopilot_service.dart:410-423](../lib/features/autopilot/game_day_autopilot_service.dart#L410-L423),
  and `buildBasePayloadForTest`'s `designMode == 'saved'` branch). Those blobs can be any
  shape, including a Design Studio per-pixel design. Per the V2 size caveat, a per-pixel
  payload exceeds one command and is chunked (337 px / 6 KB ceiling, chunk = 224) —
  **that is the one case that would need a pre-staged preset**, and it is bounded and rare.
- **Score celebrations are explicitly foreground-only by design today.** `main_scaffold.dart:109-112`:
  *"Score celebrations are app-open-only BY DESIGN — pause the ESPN poll + celebration
  playback whenever the app leaves the foreground."* Making them unattended is a **new
  product decision**, not a port. It is also the highest-frequency fire in the system
  (one per score, plus a revert 15 s later), which interacts with §3 queue pressure and
  with the anti-strobe reasoning in `applySyncPattern`. **I have flagged it as S5b and
  deliberately not folded it into S5.**

## 1.3 S3–S7 restated, with S1/S2 shipped

S1 and S2 are **done and deployed** — the rule went live 2026-08-05 (ruleset `93c99c50`,
rollback target `ec8d918f`), the sweeper and `syncControllerIps` are running, the backfill
is a verified no-op, and post-deploy verification was 12/12 with a **non-admin** token
(COMMAND_SAFETY, "STEP 7 — RULE DEPLOYED"). Actual cost was ~18 h against the ~13 h
estimate.

| # | Step | V2 est | **Revised** | Confidence | Change and why |
|---|---|---|---|---|---|
| ~~S1~~ | `controllerIp` validation | 3 h | **DONE** (~8 h actual) | — | Shipped + deployed |
| ~~S2~~ | Expiry + deterministic IDs + sweeper | 10 h | **DONE** (~10 h) | — | Shipped + deployed. **One obligation deferred into S3** — the one-in-flight-per-controller guard is specified in §3.4 but not implemented, by design ("an uncalled guard is untestable") |
| **S3** | Fire-job collection + minute-cron dispatcher; `ping` shadow-latency run | 16 h | **19 h** | Medium | +3 h: the one-in-flight guard S2 deferred is now S3's, and it is load-bearing against the measured 30-32 s tail |
| **S3b** | **NEW — denormalize resolved participating channels to Firestore** (F-1) | — | **4 h** | High | Not in V2. Without it a cloud fire cannot honour per-channel participation and silently regresses #29 |
| **S4** | Nightly restore row | 6 h | **6 h** | High | Unchanged. Still gated on UNVERIFIED #11 (is an identical-state preset load visually silent — 10 min at the bench) |
| **S5** | Game Day → fire jobs: start at first pitch, end via server-side ESPN `final` | 20 h | **24 h** | Medium | +4 h: the port is of the *background* worker, but the live foreground behaviour is the *ephemeral* phase machine (impl #3) and the two disagree — see below. Also needs `SunUtils` in TS for the daylight filter |
| **S5b** | **NEW, OPTIONAL — server-side score celebrations** | — | **12 h** | Low-Med | Explicitly out of S5. Today foreground-only *by design*; making it unattended is a product decision, and it is the fire pattern most exposed to §3 queue pressure and anti-strobe concerns |
| **S6** | Fire receipts + cloud half of controller health | 8 h | **8 h** | High | Unchanged, and §2.4's census is a strong argument for pulling it earlier — see Finding 9 |
| **S7** | Tests + bench | 12 h | **14 h** | Medium | +2 h for S3b and the impl-#3 reconciliation |
| | **→ MOTIVATING CASE COMPLETE** | 75 h | **~75 h remaining** (~93 h total incl. S1/S2) | MED | |

**The S5 estimate correction, specifically.** V2 §2 sized S5 as *"port of
[game_day_autopilot_service.dart:601-653](../lib/features/autopilot/game_day_autopilot_service.dart#L601-L653)."*
Those lines are real and still do what the doc says. But the memory record shows that path
was **blind to the ephemeral phase machine** — score celebrations never fired in the field
until `d753ea7` united them. A server-side port that reads only the autopilot session
record will reproduce that blindness. **S5 must port the union of impl #1 and impl #3, or
explicitly declare impl #3 out of scope for unattended operation and say so in the UI.**
That is the +4 h.

**What the customer gets at S7, unchanged from V2 and still accurate:** Game Day design
fires at first pitch from the cloud, app closed, customer anywhere; ESPN `final` detected
server-side ends it; total cloud failure still lands on base at 23:30 via the restore row.
**What they do not get:** score celebrations (unless S5b), and the mid-game-join ephemeral
show (unless S5 takes the union).

---

# PART 2 — NEIGHBORHOOD SYNC

## 2.1 What works unattended today — **nothing, and the fanout has never run**

`applySyncPattern` is a real server-side fan-out and it does write into other users'
command queues. But two facts bound it hard.

**Fact 1 — it is not a scheduled function. It is `onRequest` with manual ID-token
verification.**

```ts
// functions/src/applySyncPattern.ts:65, :74-89, :120-125
export const applySyncPattern = onRequest({ maxInstances: 10, cors: false }, …
  const idToken = authHeader.substring("Bearer ".length).trim();
  decoded = await admin.auth().verifyIdToken(idToken);
  …
  if (decoded.uid !== initiatorUid) → 403
```

It fans out **server-side**, but it must be **called by the initiator** holding a valid,
unexpired ID token. There is no cron, no trigger, no other invocation path. So it removes
the *receivers'* app dependency — and keeps the *initiator's*. Combined with §0 (the only
non-foreground caller is the inert background worker) and F-2 (the token expires in an
hour and nothing checks), the initiator dependency is currently absolute.

**Fact 2 — the crew fan-out branch is flag-gated OFF and has never executed in
production.** Verified three ways:

- The runbook states it outright: *"**Status: PREP ONLY — fanout is NOT active.** The
  server-side crew fanout has never executed in production"*
  ([neighborhood_fanout_activation_runbook.md:3-5](../docs/neighborhood_fanout_activation_runbook.md)).
- The gate is `if (fanout === true && groupId && groupId.length > 0)` then
  `readSyncFanoutEnabled(db)`, which defaults `false` on absence or error
  ([:159-190, :311-325](../functions/src/applySyncPattern.ts#L159)).
- The live flag was read **with a non-admin token** during the 2026-08-05 rules deploy:
  `config/sync_fanout READABLE enabled=false` (COMMAND_SAFETY §5).

Also note: **only the foreground ad-hoc "start" caller ever sets `fanout:true`.** Both
background workers pass a `groupId` but *not* `fanout`
([sync_event_background_worker.dart:794-801](../lib/features/neighborhood/services/sync_event_background_worker.dart#L794),
[game_day_autopilot_background_worker.dart:560-568](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L560))
— a deliberate choice recorded in the interface comment, to preserve the distributed
self-apply model. So even with the flag flipped and the background service re-enabled,
**scheduled sync events would still self-apply only**, never fan out.

### The two channels, precisely

| | `/neighborhoods/{groupId}/commands` (live today) | `/users/{uid}/commands` (fanout, dark) |
|---|---|---|
| Written by | Any group member, client SDK (`broadcastSyncCommand`, `writeTeardownCommand`) | `fanoutToCrew`, Admin SDK |
| Rule | `allow read, create, update, delete: if isGroupMemberLookup()` — **any member, any payload, no `controllerIp` validation, no expiry** (firestore.rules, group block) | Admin SDK — bypasses rules entirely |
| Consumed by | A **Firestore listener in the receiving app** (`_commandSubscription` → `watchLatestCommand`, [neighborhood_sync_engine.dart:338](../lib/features/neighborhood/neighborhood_sync_engine.dart#L338)) | **The ESP32 bridge poll** — no app involved |
| Works with the receiver's app closed | **❌ No.** This is the whole limitation | ✅ Yes — this is the point |
| Expiry | **None.** Docs carry `startTimestamp`, not `status`/`createdAt`, so `sweepExpiredCommands`' collection-group query never matches them (§3.1). Cleared only by owner End Group (`_clearGroupCommands`) | Covered by the S2 sweeper |

> **So: `applySyncPattern`'s fan-out is the right mechanism, it is correctly built, it is
> unit-tested, it has anti-strobe rate limiting, it has SYNC-1 mutual-membership
> verification — and it has never carried a single production command.** What it can do
> today without the receiving app open is: **nothing, because it is off.** What it *would*
> do if flipped on: deliver an ad-hoc, initiator-app-open sync to every crew member whose
> bridge is alive. That is a real and substantial capability, and it is one console edit
> plus a two-node verification away (runbook steps 4-5).

## 2.2 What requires the absent user — fan-out time vs setup time

| Thing | Where it lives | Needed at **fan-out** time? | Verdict |
|---|---|---|---|
| **Join** (`members/{uid}` doc + `memberUids[]`) | Firestore, both places | Read only — `fanoutToCrew` reads the group's `memberUids` and the members subcollection **live**, never a cached list ([:419-437](../functions/src/applySyncPattern.ts#L419)) | ✅ **Setup-time. Fine** |
| **Leave** | Deletes `members/{uid}`, removes from `memberUids[]` | Read only | ✅ **Setup-time, and correct by construction** — the live read means a member who just left is already gone |
| **`participationStatus`** (`paused` / `optedOut`) | `members/{uid}` field | Read only, `isMemberSkipped` | ✅ **Setup-time** |
| **`isParticipating`** (runtime apply-state) | `members/{uid}` field | **Deliberately NOT checked** on the fan-out path — the code comment explains why: it is false on every resting member, so gating START on it would skip the whole crew ([:274-281](../functions/src/applySyncPattern.ts#L274)) | ✅ Correct as designed, but see §2.5 — it means the STOP-path gate is not yet built |
| **`settings/syncConsent`** (`categoryOptIns`, `skipNextEventIds`) | Firestore subcollection | ⚠️ **Read by `initiateSyncSession` — and NOT read by `fanoutToCrew`** | ❌ **Gap. See §2.5** |
| **Channel selection** | `member.participatingChannelIndices` (**always null**, §1.1 F-1) + a SharedPreferences cache on the member's own phone | The fan-out writes the **initiator's payload verbatim** into every member's queue — `buildFanoutCommandDoc` takes `payloadString` with no per-member filtering | ❌ **Fan-out time, and unsatisfiable server-side today.** Mitigated in practice because the sync payload is the 8-channel broadcast shape (`id: 0..7`) that lights everything anyway — i.e. the feature currently *has no* per-member channel selection, so nothing regresses. But "the patio stays dark during sync" is not achievable unattended without S3b's denormalization |
| **Controller targets** | `member.controllerId[]` denormalized, else live `users/{uid}/controllers`, else legacy `controllerIp`, else `{id:"", ip:""}` (bridge self-resolves) — `resolveMemberTargets` ([:339-374](../functions/src/applySyncPattern.ts#L339)) | Read only, with a four-tier fallback that always yields something | ✅ **Setup-time. Well built** |
| **Webhook URL** | `users/{uid}.webhookUrl` | Read only | ✅ Setup-time (and moot — zero production accounts are webhook-mode) |
| **The local ledger — pre-sync scene snapshot** | **In-memory only, never persisted** ([pre_sync_scene_snapshot.dart:24-25](../lib/features/neighborhood/services/pre_sync_scene_snapshot.dart#L24)), and **DORMANT** — "NOT yet wired into `broadcastSync`/`startListening`… consumed only by tests" | **Yes — at teardown time, on the member's own device** | ❌ **The hard one.** See §3.3 |
| **Teardown restore** (schedule → autopilot → pre-sync scene → off) | `SyncTeardownResolver`, also dormant; driven by the app's command listener | Yes, on the member's device | ❌ **See §3.3** |
| **Host failover** (2-min grace, backup host takes over) | SharedPreferences on each candidate host's phone | Yes | ❌ Inert with §0; and conceptually unnecessary once a server dispatcher is the host |

**Summary: setup-time dependencies are all fine and mostly well-built.** The three
fan-out-time dependencies are (a) per-member channel selection — currently vacuous,
(b) consent beyond `participationStatus` — a real gap, and (c) **teardown/restore, which
is entirely device-resident and dormant.** (c) is the one that turns "the neighbour changed
my lights while I was away" into "…and they stayed that way."

## 2.3 The preset problem — **confirmed on the wire: there is no preset in this path, and
`psave` does relay**

**Claim 1 — Neighborhood Sync never uses a preset.** `grep -rn 'psave\|loadPreset\|savePreset\|"ps"'
lib/features/neighborhood` → **no matches.** Every sync fire is inline state:

```dart
// sync_event_background_worker.dart:748-762 — buildPatternPayloadForTest
seg: [ for (ch in 0..7) {'id': ch, 'fx': effectId, 'sx': speed, 'ix': intensity, 'col': colorSlots} ]
→ normalizeWledPayload({'on': true, 'bri': brightness, 'seg': segArray})
```

So the premise of the question — *"if the synced pattern is not resident on the receiving
controller"* — **does not arise.** A sync fire carries the full effect/palette/colour state
and the receiving controller needs nothing pre-staged. It also consumes zero preset slots,
which is exactly the property V2 Correction 1 wanted.

**Claim 2 — a `psave` *would* relay, and this is confirmed in the firmware, not assumed.**
The bridge's `executeCommand` has exactly three special cases and one default:

```cpp
// esp32-bridge/src/main.cpp — executeCommand
if (commandType == "ping")      { updateCommandStatus(id,"completed"); return; }   // no WLED call
if (commandType == "getState")  { endpoint="/json/state"; method="GET"; }
else if (commandType == "getInfo"){ endpoint="/json/info";  method="GET"; }
else { endpoint = "/json/state"; method = "POST"; body = convertFirestorePayloadToJson(fields); }
```

and `convertFirestorePayloadToJson` returns `fields["payload"]["stringValue"]` **verbatim**
when the payload is a string — which it always is on every writer. **The `type` field is
not a dispatch table for WLED semantics; it is only a ping/GET/POST selector.** Any JSON
object, including `{"psave": N, "n": "…", …}`, is POSTed unmodified to `/json/state`.

Corroborated independently in `lib/`: `CloudRelayRepository.savePreset` exists, is a real
implementation (not a throw), and its own comment records the mechanism —
*"a relay psave can poison a preset exactly the same way (the bridge routes psave via
`/json/state`)"* ([cloud_relay_repository.dart](../lib/features/wled/cloud_relay_repository.dart)).
Contrast `applyConfig`, which throws `CfgWriteUnsupportedException` because `/json/cfg`
genuinely has no bridge branch. **The asymmetry in V2 §0 is confirmed at the firmware
level: `/json/state` relays, `/json/cfg` does not.**

> **Verdict.** Presets are not needed for sync, and pre-staging *is* available as an escape
> hatch if a future sync design is per-pixel (the one case where inline state exceeds a
> command and would need chunking). **Two things must be recorded before anyone uses it:**
> (1) COMMAND_SAFETY §4.2's standing constraint — *"Route only fire jobs through the
> scheduled path. Never a state-mutating operation — no `psave`, no `applyConfig`, no
> pairing"* — because a `psave` executed 60 s late is **not** equivalent to on time; and
> (2) the frozen-segment fact from memory: a `psave` that captures `frz:true` produces a
> preset that fires dark forever. `ensurePsaveClearsFreeze` is already in the relay path,
> which is the right guard, but a *server-written* psave would bypass that Dart helper
> entirely and would have to re-implement it in TS.
>
> **UNVERIFIED (carried from V2 #15):** whether a 0.5-6 KB inline-state payload transits a
> command document and the bridge's `convertFirestorePayloadToJson` without truncation. The
> sync payload's 8-segment shape with 3 colour slots each is on the order of ~1 KB, so this
> is live for sync as well as for Game Day. Settle it by writing one server-side and
> watching the bridge — ~30 min.

## 2.4 Bridge dependency — measured against the live fleet, 2026-08-05 20:19 UTC

Read-only census of `users/*/bridge_status/current` (doc `updateTime` is the authoritative
heartbeat signal — the firmware writes counters, not a `lastSeen` field, per the existing
`_diag_bridge_liveness.js` note) plus `bridge_registry/*.lastSeen`. No writes.

```
users total                    : 24
users with >= 1 controller     : 15
with a bridge_status/current   :  8
heartbeat <= 10 min (ONLINE)   :  6
heartbeat ages (min), sorted   : [0, 0, 0, 0, 0, 0, 21548, 30722]
```

**Identity re-derived from scratch 2026-08-05 20:37 UTC and independently corroborated —
see §2.4a.** The triage key below is the **email**, not the display name.

| uid (trunc) | display_name | email | controller | bridge device | `bridge_status/current` updateTime | age | verdict |
|---|---|---|---|---|---|---|---|
| `wrQRUUKyXy` | Trend Setter | tyler.honeycutt@nex-genled.com | 192.168.1.150 | `0070077F92C8` | 2026-08-05T20:37:14Z | 0 d | ✅ live (bench) |
| `j8eXTfcsAB` | Taps On Main | marc@tapsonmain.com | 192.168.10.201 | `20E7C8AFD174` | 2026-08-05T20:37:12Z | 0 d | ✅ live |
| `YcSGiwesJu` | Steve Stegall | stegall.s@yahoo.com | 192.168.1.250 | `E08CFE405538` | 2026-08-05T20:37:23Z | 0 d | ✅ live |
| `cndlN3nmU9` | Chris Cipollone | chris_cipollone@simonton.com | 192.168.1.250 | `20E7C86BAAB4` | 2026-08-05T20:37:09Z | 0 d | ✅ live |
| `Ayf0rqwNOQ` | Tim Kelly | textim6@yahoo.com | 10.0.0.100 | `D4E9F4FA8E78` | 2026-08-05T20:37:07Z | 0 d | ✅ live |
| `Q8VIQ9lrIA` | Brooke Rozenberg | brooke.rozenberg1@gmail.com | 192.168.86.250 | `D4E9F4FA54B8` (192.168.86.34) | 2026-08-05T20:37:25Z | **0 d** | ✅ **live** — but **also owns a second, superseded bridge `0070077E8F60` (192.168.86.187) stale 21.95 d.** Both are on her /24. Orphaned registry row, not a customer-facing outage |
| `5oHhaEaf6i` | **Ellie Cochran** | **ecochran08@yahoo.com** | 10.0.0.32 | `D4E9F4FA9D40` (10.0.0.112) | **2026-07-21T21:11:15Z** | **14.98 d** | ❌ **offline — this is the 15-day-stale account** |
| `EHRfYGyfQX` | **Chris Paschall** | **cpaschall10@gmail.com** | 192.168.1.201 | `D4E9F4FAA5F4` (192.168.1.197) | **2026-07-15T12:17:00Z** | **21.35 d** | ❌ **offline — stalest active bridge in the fleet** |
| `Aj8lQ1hfwf` · `KOerj0uiKy` · `NmDukd5rKw` · `PqptfawprO` · `VzgTsg31JE` · `r0iBwg8bye` · `staff_installer_5502` | Darian Brosa · Demo · Jim Dyer · Darrin Nicholas · Jeff Gruenewald · The Iron Reserve · installer staff | dbrosa99@icloud.com · nex-genadmin@nex-genled.com · jjdyer1@hotmail.com · dnicholas0131@gmail.com · thegruenewalds@gmail.com · ironreserveclub@gmail.com · — | 1 each | **none in `bridge_registry`** | **no document at all** | — | ❌ **never heartbeated** |

`bridge_registry` agrees: 11 device docs, 9 `paired` across **8 distinct uids** (Brooke
holds two), **6 fresh**; one `unpaired` device idle 57.3 days.

### 2.4a Identity verification — re-derived, four independent sources

Tyler queried the attribution: was the 15-day-stale bridge Brooke's rather than Ellie's?
The mapping was re-derived from raw data with no reliance on the first census's labels.
**The original attribution is correct.** Four sources agree:

| Source | Independent of | Says |
|---|---|---|
| **Firebase Auth record** (`admin.auth().getUser(uid)`) | The Firestore user doc entirely | `5oHhaEaf6i` → `ecochran08@yahoo.com` |
| Firestore `users/{uid}.displayName` | Auth | `5oHhaEaf6i` → "Ellie Cochran" |
| `users/{uid}/bridge_status/current` **server** `updateTime` | The registry collection | `2026-07-21T21:11:15Z` = 14.98 d |
| `bridge_registry/D4E9F4FA9D40.lastSeen` — different collection, different writer | `bridge_status` | `2026-07-21T21:11:16Z` = 14.98 d, **agrees to one second** |
| **LAN subnet correlation** | All of the above | The 15-day device sits at **10.0.0.112**; that account's controller is **10.0.0.32** — same /24. Brooke's controller and *both* her bridges are **192.168.86.x**. The 15-day device is not on Brooke's network |

**The confusion is real and explainable — Brooke does own a stale bridge, just not that
one.** Three stale figures sit within a day of each other and are easy to transpose:

```
  14.98 d   ecochran08@yahoo.com     ACTIVE bridge, offline          ← the "15-day" one
  21.35 d   cpaschall10@gmail.com    ACTIVE bridge, offline
  21.95 d   brooke.rozenberg1@…      SUPERSEDED bridge, orphaned row  ← Brooke's stale device
```

> **Triage list, by email — two customers to call, and they are not Brooke:**
> **`ecochran08@yahoo.com`** (dark 15 days) and **`cpaschall10@gmail.com`** (dark 21 days).
> Brooke needs **no call**; she needs the orphaned `0070077E8F60` registry row cleaned up so
> it stops reading as a fleet outage.

**The one thing this cannot settle.** Every source above keys on the *account*. If the
person Brooke uses an account registered to `ecochran08@yahoo.com`, no query can detect it —
that is a fact about people, not data. The subnet correlation argues against it (Ellie's
account is on `10.0.0.x`, Brooke's on `192.168.86.x`), but **if Tyler knows Brooke's house
is on a `10.0.0.x` LAN, that would overturn the reading and the accounts are mislabeled at
signup.** Please confirm.

**Method note, since this is the third instance of the class.** The first census printed
`displayName || email` and I then wrote *names* into the table — so the label and the
measurement travelled together and a wrong label would have been invisible. The fix used
here is what should be standard: **key the triage list on the email, take identity from a
source independent of the one being measured (Auth, not the user doc), and cross-check with
a physical fact the data cannot fake (the subnet).** Same discipline as verifying with a
client credential rather than admin, and as probing the path the code actually writes rather
than the one its name suggests.

> ### The number that matters
>
> **Unattended reach today is 6 of 15 controller-owning accounts — 40 %.**
> Restated the other way: **9 of 15 customers (60 %) cannot receive a cloud-fired command
> at all right now**, and 7 of those 9 have never had a bridge report in.
>
> Among accounts that *have* a bridge, reach is 6/8 = 75 %, and the worst live-bridge
> account is **21.3 days stale**.

Two consequences for design:

1. **A design that assumes the bridge is there is a design that works for 40 % of
   customers.** The nightly restore row (§3.3) is not a nicety, it is what the other 60 %
   experience *as the whole feature*. This materially strengthens V2's Correction 2.
2. **This is not observable in-app today, by anyone.** Nothing surfaces "your bridge has
   been offline for three weeks" — to the customer or to Tyler. That is exactly
   [OFF_LAN_CAPABILITY.md §3.3](../audit/OFF_LAN_CAPABILITY.md)'s "no controller-health
   signal in the fleet at all," now quantified. **S6 (~8 h) turns this census from a
   one-off script into a standing signal.** Given that a 21-day-dark bridge means a
   customer's remote control has been silently broken for three weeks, I would pull S6
   forward ahead of S5.

Aside worth a separate look, not part of this design: the bridges' cumulative error
counters are high relative to commands processed — Ellie `commands:3 / errors:3173`,
Tim Kelly `33 / 1113`, Tyler `505 / 680`, Steve `3070 / 506`. Counters are cumulative since
boot and may be counting poll failures rather than command failures. **UNVERIFIED** what
increments `commandErrors` vs. poll errors; worth one read of the firmware before drawing
any conclusion.

## 2.5 CONSENT — flagged, not resolved. **Tyler's call.**

### What exists today

| Control | Where | Enforced by `initiateSyncSession` (scheduled path) | Enforced by `fanoutToCrew` (the unattended path) |
|---|---|---|---|
| Group membership | `members/{uid}` doc exists | ✅ implicit | ✅ explicit, live-read |
| **Mutual membership (SYNC-1)** | uid ∈ group `memberUids[]` | ❌ not checked | ✅ `verifyFanoutTarget` — closes the one-sided/orphan-member hole |
| `participationStatus` = `paused` / `optedOut` | member doc | ✅ | ✅ `isMemberSkipped` |
| **`settings/syncConsent` must EXIST** | member subcollection | ✅ `if (!consentDoc.exists) continue` — **no consent doc means never a participant** | ❌ **not read** |
| **`categoryOptIns[category]`** (per-category opt-in: gameDay / holiday / custom) | consent doc | ✅ `if (!optIns[category]) continue` | ❌ **not read** |
| **`skipNextEventIds`** ("skip just this one") | consent doc | ✅ | ❌ **not read** |
| Anti-strobe rate limit | `neighborhoods/{id}/rate_limits/state`, transactional | n/a | ✅ 18 s per initiator, 5 per 60 s per group |
| `isParticipating` | member doc | n/a | ❌ deliberately not a START gate (documented); **the STOP-path gate it is meant to be does not exist yet** |

### The gap, stated precisely

> **The unattended path enforces a strictly weaker consent model than the app-open path.**
> `initiateSyncSession` requires an existing consent document *and* a positive
> per-category opt-in. `fanoutToCrew` requires only that the member has not explicitly
> paused or opted out. A crew member who has **never** completed consent — no
> `settings/syncConsent` doc at all — is skipped by the scheduled path and **fanned out to**
> by the ad-hoc path.
>
> Under today's model (app-open receivers) that is a bounded annoyance: the receiver is
> present and can hit Stop. **The moment the fan-out flag flips, it becomes "a neighbour
> changed the lights on an empty house belonging to someone who never opted in."**

That is a product decision, and I am not resolving it. What the design would need,
whichever way it goes:

1. **Bring `fanoutToCrew` to parity with `initiateSyncSession`** — read the consent doc,
   require existence + `categoryOptIns[category]`, honour `skipNextEventIds`. ~3 h. This
   is the minimum and I would treat it as a **gate on flipping the flag**, in the same way
   S1 gated S3. (Note the fan-out envelope does not currently carry a `category` — it would
   need one, or would need to resolve the event.)
2. **A distinct "while I'm away" consent tier.** Consenting to "my lights join the crew
   while I'm home and can see it" is not the same act as "my lights can be changed while my
   house is empty." Today there is one flag for both.
3. **A revocation path that works while away.** `selfLeaveSync` writes to the group command
   channel, which only an *open app* consumes. An absent member cannot currently stop a
   sync that is running on their house. This is the same dormancy as §3.3 and is arguably
   the sharper half of the consent problem: consent without a working withdrawal is not
   consent.
4. **An after-the-fact record.** The fan-out writes commands with `initiatorUid` and
   `sessionId` already ([:483-492](../functions/src/applySyncPattern.ts#L483)) — so "who
   changed my lights and when" is *already answerable from the data*; it is just not
   surfaced anywhere. Cheap to expose, and it is what makes the trust story defensible.
5. **A default.** New members' `participationStatus` and consent doc state on join — I
   could not determine the intended default from the code with confidence, because the
   consent doc is created in a path I did not fully trace. **Question for Tyler below.**

> **DO NOT BUILD PAST THIS.** Items 1 and 3 are, in my reading, prerequisites for
> unattended sync in any form, not follow-ups. But whether unattended sync should exist at
> all for a non-present neighbour is Tyler's decision and nothing here presumes it.

---

# PART 3 — WHAT BOTH SHARE

## 3.1 Does S1 + S2 cover a server process writing to a user's `commands`? — **S2 yes,
S1 not at all, and that is correct by construction**

**S1 (`controllerIp` validation) does not constrain a server writer, and was never meant
to.** The Admin SDK bypasses security rules entirely — COMMAND_SAFETY §2.2 says so in the
rule's own comment: *"this constrains APP writers only."* A server-side dispatcher gets its
safety from **provenance**, not from the rule:

- Writers #5/#8/#9 (Google Home, Alexa) **omit `controllerIp`** → the bridge falls back to
  its own paired IP → structurally unredirectable.
- Writers #6/#7 (`applySyncPattern`) **must** name the IP, because a fan-out targets
  multiple controllers per user and the bridge holds only one paired IP. Their safety is
  that the IP is resolved server-side from the user's own `controllers` subcollection
  ([:339-369](../functions/src/applySyncPattern.ts#L339)) — never from client input.

**This is already the correct pattern and a new Game Day dispatcher should follow #6/#7,
not V2 §8's "omit the field" advice** — COMMAND_SAFETY §1.3 already corrected that as "too
broad." ✅ **Covered. Nothing missing.**

**S2 (expiry) does cover it, with one caveat and one gap.**

- `applySyncPattern` writes **no `expiresAt`** ([:243-255](../functions/src/applySyncPattern.ts#L243),
  [:481-493](../functions/src/applySyncPattern.ts#L481)) → falls to
  `DEFAULT_COMMAND_TTL_MS = 120 s` from `createdAt`. For a *fire* that is right: 120 s late
  is still the right absolute state, and 120 s is far below any plausible bridge outage. ✅
- **Caveat — 120 s is sized for the app's 45 s watchdog, not for a fire job.** V2 §4 Layer 2
  specifies `expiresAt = fireAt + graceWindow`, default **90 s**. A dispatcher should set
  `expiresAt` explicitly rather than inherit the default; an explicit value always wins
  (`isExpiredCommand`). Small, but it is the difference between a designed TTL and a
  borrowed one.
- **Gap — the group broadcast channel is entirely outside S2.** `sweepExpiredCommands`
  runs a `collectionGroup("commands")` query filtered `status == "pending"` AND
  `createdAt < cutoff`. `SyncCommand.toFirestore` writes **neither field** — it carries
  `startTimestamp` and no status
  ([neighborhood_models.dart:661+](../lib/features/neighborhood/neighborhood_models.dart#L661)).
  So `/neighborhoods/{groupId}/commands` docs **never match the sweeper**, which is
  fortunate (the sweeper would otherwise corrupt them) but means **that channel has no
  expiry of any kind.** It is purged only by owner End Group (`_clearGroupCommands`). The
  code already names the resulting bug — *"so they can never be replayed to re-light a
  member after the group ends (defect #2)"* — and the `writeTeardownCommand` docstring
  describes engineering around a *"fireImmediately/resume replay"* of a stale command. **A
  lingering design command on that channel re-lights any member whose app resumes,
  arbitrarily far in the future.** Bounded today because it needs an open app; worth
  closing regardless.

- **Deterministic IDs are available and unused.** `fireJobDocId(eventId, fireAtEpochSeconds)`
  → `fire_<eventId>_<epoch>` with `.doc(id).create()` is shipped in `commandSafety.ts`, with
  no caller by design. Both `applySyncPattern` writers still use `.add()`, so a retried
  invocation writes a second document and the bridge fires twice. Harmless for an
  idempotent absolute-state fire; **not** harmless for a *sequence* against an unordered
  poll. **S3 obligation, as recorded.**

## 3.2 Firing into an unattended house that is in an unexpected state

Both features fire an **absolute state load**. Neither reads prior state, neither toggles,
neither can partially apply. That is the governing property from V2 §3 and it makes most of
this tractable — but not all of it.

| The house is… | What happens | Assessment |
|---|---|---|
| **Master off** (lights down for the night) | Fires anyway and turns them **on**. Every payload carries an explicit `'on': true` — `_buildWledPayload`, `buildBasePayloadForTest`, `buildCelebrationPayloadForTest`, `buildPatternPayloadForTest`. | ⚠️ **Correct mechanically, questionable as behaviour.** Memory records the `ib:true` master-assert fix precisely because ON-presets fired dark; the inline path never had that bug. But "the neighbour's block party lit my house at 23:40 while I was on holiday" is a real complaint. **A cloud fire should respect the base layer's OFF boundary** — V2 §3 Case A: the compositor truncates an event at the base OFF boundary and emits no fire jobs past it. **That rule must apply to sync fan-out too, and today there is no compositor on the sync path at all.** |
| **Mid-schedule** (a device timer fired an hour ago) | The fire clobbers it; nothing re-asserts the schedule. At the *next* device boundary the schedule clobbers back. | ✅ Understood — V2 §3 Case B. Needs the re-assert rule (fire job at boundary + 60 s) and the ±2 min exclusion zone. **Sizing the exclusion zone is still gated on UNVERIFIED #12** (real WLED RTC drift on a long-uptime controller). §2.4 gives fresh ammunition: Steve Stegall's bridge reports 2,884,472 s uptime ≈ **33 days**, and Taps On Main ≈ 26 days — if WLED really only re-attempts NTP on boot, ±2 minutes is very likely far too tight. **Measure it on one of those two.** |
| **Mid-lease** (a calendar-entry lease holds a preset slot and a timer points at it) | The fire is inline state and touches **no preset and no timer**, so the lease survives intact. The lease's *timer* will re-fire at its boundary and clobber the event — which is just Case B again. | ✅ **The zero-preset property pays off here.** This is a strong argument for keeping every cloud fire inline-only |
| **A frozen segment** | Memory: a per-pixel `i` write sets `seg.frz=true`; that segment then swallows every subsequent segment-level write, returning 200 OK with a correct readback and unchanged LEDs. **FIXED and shipped +63**, fleet exposure zero. | ✅ Closed — but note the failure mode: **a cloud fire would report `completed` with a plausible `result` while the lights did nothing.** That is V2 §5's "completed — but wrong" row, and it is the one failure only S6's `result`-vs-intent comparison can catch |
| **Two segments collapsed into one** (post-reboot, `seglc [3,3]→[3]`) | A payload addressing `seg id: 1..7` finds no such segment. Bench-proven that WLED discards out-of-range seg ids without creating phantoms (the `_kMaxSyncChannels` comment asserts this). | ✅ Degrades to "seg 0 only," i.e. partial show. Not a crash, but the customer sees half a house |
| **Controller offline / bridge offline** | `expired` (bridge never picked it up) or `failed` + HTTP code (bridge picked it up, WLED unreachable). Distinct terminal states, deliberately. | ✅ Exactly what S2 built, and §2.4 shows both states are common in this fleet |
| **A sync fires while Game Day is running** (or vice versa) | `GameDayPriorityResolver` + `_checkPriorityBeforeStart` arbitrate — **both of which live in the inert background workers**. Server-side there is no arbitration at all. | ❌ **Unbuilt.** Two independent server dispatchers writing to the same house is exactly the Case-C ordering problem with no plan-time resolution. If both features go server-side, **they must share one compositor**, not run as two crons |

## 3.3 Does one nightly-restore design (S4) cover both? — **Yes for Game Day. For
Neighborhood Sync it is not merely a fail-safe, it is the ONLY teardown that works.**

**For Game Day:** yes, cleanly, exactly as V2 Correction 2 describes. One permanent device
timer at ~23:30 whose `macro` is the base-layer design preset. Invisible on an ordinary
night; a no-op when the cloud already restored; the guarantee when the cloud died. One
slot, once, forever. Nothing about Game Day complicates it.

**For Neighborhood Sync it is doing much heavier lifting, and this is the most important
finding in Part 3.** The sync teardown path is:

```
SyncTeardownResolver:  active schedule item → autopilot item → pre-sync scene → off
```

and **every tier of it is device-resident and currently dormant.** `PreSyncScene` is
*"held in memory only — never persisted"*; the module is *"additive, DORMANT… NOT yet wired
into `broadcastSync`/`startListening`… consumed only by tests today (and by
`SyncTeardownResolver` which is itself dormant)"*. The teardown *signal*
(`writeTeardownCommand`) is written to the group command channel, which is read by an
**app-side Firestore listener**.

> **So: if a sync fires into an absent member's house today (or after the flag flip), there
> is no mechanism by which it ever ends.** Not the owner's End Group, not the member's
> self-leave, not the scheduled end time — all three write to a channel only an open app
> reads. The lights stay on the crew pattern until the member opens the app, or until a
> device timer happens to fire.
>
> **The nightly restore row is therefore not a fail-safe for sync. It is the entire
> teardown story.** And the "cloud restored it earlier" branch that makes the row a no-op
> on a good night **does not exist for sync at all** — there is no server-side sync end.

Design consequences:

1. **One S4 design does cover both**, and it should be built once, shared. The row is
   feature-agnostic by construction: it loads the base layer, regardless of what put the
   strip in a non-base state.
2. **S4 is a hard gate on flipping the fan-out flag**, not a follow-on. Without it, an
   unattended sync has no bounded duration. I would state that as flatly as V2 stated
   "S1 lands before S3 is written."
3. **The restore row's default hour needs re-thinking for sync.** ~23:30 is right for a
   Game Day that ends around 22:30. A 17:00 block-party sync with no server-side end would
   run **six and a half hours** before the row rescues it. Either the fan-out must carry a
   server-side end (an `endsAt` fire job written at the same time as the start — cheap,
   since it is just a second fire job carrying the base state), or the customer needs
   a per-event bounded duration. **The `endsAt` companion fire job is the right answer and
   costs almost nothing once S3 exists.**
4. **`expiresAt` and the restore row are complementary, not redundant.** Expiry stops a
   *stale* command from firing. The restore row stops a *successful* command from lasting
   forever. Both are needed, and §2.4 shows why: on a 40 %-reachable fleet, plenty of
   houses will get the start and miss the end.
5. **Still gated on UNVERIFIED #11** — is loading a preset identical to the running state
   visually silent? 10 minutes at the bench, and it is now the premise of two features
   rather than one.

---

## UNVERIFIED

| # | Claim | How to settle | Gates |
|---|---|---|---|
| U1 | A 0.5-6 KB inline-state payload transits the command doc and `convertFirestorePayloadToJson` without truncation (V2 #15) | Write one server-side, watch the bridge serial | S3, and the sync fan-out |
| U2 | Loading a preset identical to the running state is visually silent (V2 #11) | Bench, 10 min | **S4 — now gating both features** |
| U3 | WLED RTC drift between NTP syncs (V2 #12). §2.4 supplies two 26-33-day-uptime controllers to measure on | Compare `/json/info` time vs. phone on Steve Stegall's or Taps On Main's controller | The ±2 min exclusion zone, which is probably far too tight |
| U4 | Real cloud-fired P50/P95 latency; the Admin-SDK write hop is unmeasured (V2 #13) | One-week `ping` shadow run during S3 | S3 |
| U5 | Firestore `runQuery` ordering without `orderBy` (V2 #14) | Read a bridge poll response with 3+ queued commands | The one-in-flight guard's necessity |
| U6 | ESPN `final` reliability under delays / suspensions / doubleheaders (V2 #8) | A season of shadow logging, log-only | S5 quality |
| U7 | **NEW** — what increments the bridge's `commandErrors` counter vs. poll errors. §2.4 shows Ellie at `commands:3 / errors:3173` | One read of `main.cpp` | Whether §2.4's error counters mean anything |
| U8 | **NEW** — whether a member joining a crew gets a `settings/syncConsent` doc by default, and with which `categoryOptIns` | Trace `joinGroup` / the consent-creation path, or ask | §2.5 item 5 |

---

## QUESTIONS FOR TYLER — I could not determine intent from the code

1. **§2.5, consent — the blocking one.** Should a crew member's lights be changeable while
   they are away and not present to decline? And is "I consented to sync" the same act as
   "I consented to sync while my house is empty"? **Nothing past §2.5 should be built until
   this is answered.**
2. **§0 — Path A or Path B?** Is re-enabling the Android foreground service (manifest
   restore + Play FGS declaration + demo video, per release) on the table, or is the
   server-side dispatcher intended to *replace* the two background workers permanently? If
   Path B, `GameDayAutopilotBackgroundWorker` and `SyncEventBackgroundWorker` become ~1,600
   lines of dead code that should be deleted rather than maintained — and that is a
   meaningful simplification I would want your sign-off on before proposing it.
3. **§1.1 F-1 — per-member channel selection.** `participatingChannelIndices` is
   serialized, resolved and read, and **never written by any UI**, on both the Game Day
   config and the neighborhood member. Was per-member channel selection abandoned, or is
   the picker still owed? The answer decides whether S3b (4 h) is required or whether the
   field should be deleted.
4. **§2.1 — is the fan-out's self-only default for background callers deliberate long-term,
   or a Slice-1 safety measure?** The comment says it preserves "the distributed self-apply
   model," but under Path B there is no distributed self-apply — there is one server. If
   scheduled sync events should fan out, that comment's invariant needs revisiting
   explicitly rather than silently.
5. **§3.2 last row — one compositor or two crons?** If both Game Day and Neighborhood Sync
   go server-side, do you want them arbitrated by a single shared compositor (my
   recommendation — it is the only way `GameDayPriorityResolver`'s intent survives), or run
   as independent dispatchers with last-write-wins?

---

## Findings

| # | Finding | Severity |
|---|---|---|
| 1 | **`kSportsBackgroundServiceEnabled = false`.** Both background workers — all of the app-closed logic for both features, ~1,600 lines — **have never run in a shipped build.** Unattended operation is not degraded today; it is absent | **Headline. Reframes the whole question** |
| 2 | **iOS can never satisfy the goal via the device path.** Background fetch is opportunistic and will not wake an app for a specific wall-clock instant. Path A is structurally incapable on half the fleet → **Path B (server dispatcher) is the only design that works** | **Decisive** |
| 3 | **`loadSyncIdTokenExpiresAt` has zero callers.** A second "TTL designed, enforcement never built," identical in shape to the `expiresAt` finding S2 fixed. Any Path-A fire >1 h after the last app foreground would 401 and fail with only a `debugPrint` | **P1, latent** |
| 4 | **Game Day uses `applyJson` inline state everywhere; zero presets in the feature.** Cloud fires consume zero preset slots and need nothing pre-staged — exactly what V2 Correction 1 wanted | **Favourable** |
| 5 | **Confirmed on the wire:** the bridge's `type` field is only a ping/GET/POST selector; the default branch POSTs the payload **verbatim** to `/json/state`. So `psave` **does** relay — corroborated by `CloudRelayRepository.savePreset`'s own comment — while `/json/cfg` genuinely does not. V2 §0's asymmetry holds at firmware level | **Confirmed, not assumed** |
| 6 | **Neighborhood Sync's crew fan-out has never carried a production command.** Flag `config/sync_fanout.enabled = false` (verified with a non-admin token), and **only the foreground ad-hoc caller ever sets `fanout:true`** — both background callers deliberately opt out. Answer to "what works unattended today": **nothing** | **P1 — the premise correction** |
| 7 | **`applySyncPattern` is `onRequest`, not scheduled.** It removes the *receivers'* app dependency and keeps the *initiator's* — it needs a live ID token from the initiating user | **Scoping** |
| 8 | **Unattended reach is 6 of 15 controller-owning accounts — 40 %.** 7 accounts have **never** had a `bridge_status/current` document; the worst live account is **21.3 days** stale. Measured, not estimated | **P1, and it sizes everything** |
| 8a | **Identity re-verified against a challenge (§2.4a): the original attribution holds.** The 15-day-stale bridge is `ecochran08@yahoo.com`, confirmed by Firebase Auth, the Firestore doc, two separate Firestore collections agreeing to one second, and subnet correlation. Brooke Rozenberg is **live** — she owns a *second, superseded* bridge stale at **21.95 d**, which is the transposable number. **Triage: call `ecochran08@yahoo.com` and `cpaschall10@gmail.com`; Brooke needs a stale registry row deleted, not a call** | **Confirmed — no correction needed** |
| 9 | Nothing surfaces a 21-day-dark bridge to the customer or to Tyler. **S6 (~8 h) should move ahead of S5** — a customer whose remote control has been broken for three weeks is a support problem today, not a future one | **High leverage** |
| 10 | **The unattended sync path enforces WEAKER consent than the app-open path.** `fanoutToCrew` checks only `participationStatus`; `initiateSyncSession` additionally requires the consent doc to exist and the category to be opted in. A member who never consented is skipped by one and commanded by the other | **P1 — product gate** |
| 11 | **An absent member has no way to stop a sync running on their house.** `selfLeaveSync` writes to a channel only an open app reads. Consent without a working withdrawal is not consent | **P1 — product gate** |
| 12 | **The sync teardown path is entirely device-resident and DORMANT** — `PreSyncScene` is in-memory-only and unwired; `SyncTeardownResolver` is unwired; the teardown signal needs an app listener. So **the nightly restore row is not a fail-safe for sync, it is the only teardown that works** — and S4 becomes a hard gate on the fan-out flag | **P1 — the biggest Part 3 finding** |
| 13 | The restore row's ~23:30 default is right for Game Day and wrong for a 17:00 sync (6.5 h of unbounded show). The fix is an **`endsAt` companion fire job** written alongside the start — near-free once S3 exists | Design |
| 14 | **`/neighborhoods/{groupId}/commands` has no expiry of any kind.** Its docs carry `startTimestamp`, not `status`/`createdAt`, so the S2 sweeper never matches them (fortunate — it would corrupt them). Purged only by owner End Group; the code already names the resulting "defect #2" replay | **P2** |
| 15 | **S1 correctly does not constrain server writers** (Admin SDK bypasses rules); their safety is server-side IP provenance, which `applySyncPattern` already does right. **S2 does cover them** via the 120 s default, but a dispatcher should set `expiresAt = fireAt + 90 s` explicitly rather than inherit an app-watchdog-sized default | ✅ Covered, one refinement |
| 16 | **The channel-participation input is device-derived** (`/json/cfg` bus list) and device-cached (SharedPreferences), and `participatingChannelIndices` is **never written by any UI**. A server fire cannot honour per-channel participation → **new S3b, 4 h**, denormalizing the resolved set to Firestore the way `controller_ips` already is | **P1, missing from the V2 estimate** |
| 17 | **V2's S5 estimate targets the wrong implementation.** There are three Game Day phase machines; S5 cites the background one, but the *live* mid-game behaviour is the ephemeral machine — the same blindness that made score celebrations never fire IRL until `d753ea7`. S5 must port the union or explicitly exclude the ephemeral path | **Estimate correction** |
| 18 | **Score celebrations are foreground-only BY DESIGN today** (`main_scaffold.dart:109`). Making them unattended is a product decision, not a port, and it is the fire pattern most exposed to queue pressure and anti-strobe concerns → split out as **S5b, 12 h, optional** | Scoping |
| 19 | **Two server dispatchers writing to one house have no arbitration.** `GameDayPriorityResolver` and `_checkPriorityBeforeStart` both live in the inert workers. If both features go server-side they need **one shared compositor**, not two crons | **Design gate** |
| 20 | Revised total: **~75 h remaining** to the Game Day motivating case (S3 19 + S3b 4 + S4 6 + S5 24 + S6 8 + S7 14), ~93 h including the shipped S1/S2. Sync's unattended path needs, on top: consent parity (~3 h), the `endsAt` companion job (small), and the §2.5 items Tyler decides on | Summary |

---

# PART 4 — WINDOWED CONSENT (design only, nothing implemented)

**DECISION (Tyler, 2026-08-05):** syncs land unattended **only within an agreed window**. Not
always-on, not confirm-each-time. A member joins a group and agrees to a window; inside it a sync
fires on their controller with their app closed and their phone anywhere. Outside it, nothing lands.

This **resolves §2.5**, which flagged the consent model as Tyler's call and deliberately stopped.
Everything below is design. No code, schema or flag was changed.

> **The single most useful property of this decision:** a window **expires by itself**. §2.5 item 3
> said "consent without a working withdrawal is not consent," and the absent member still has no
> revocation channel (`selfLeaveSync` writes to a group command channel only an open app consumes).
> A window does not fix revocation — but it **bounds the exposure without requiring one**, which is
> what makes shipping possible before that channel exists. Default-deny on expiry is the whole
> safety story.

---

## 4.1 What is a window? — date range **and** optional hours, one object

**Recommendation: a single object with four fields, of which only the two bounds are required.**

```
{
  startsAt:   Timestamp,        // REQUIRED — absolute UTC instant
  endsAt:     Timestamp,        // REQUIRED — absolute UTC instant. THIS is what makes it a window
  daysOfWeek: [int] | null,     // optional. 1=Mon..7=Sun. null = every day in range
  localStart: int  | null,      // optional. minutes past local midnight, 0..1439
  localEnd:   int  | null,      // optional. null pair = the whole day
  ianaTz:     string,           // REQUIRED when localStart/localEnd are set — see 4.3
}
```

**Do not build a recurrence engine.** No RRULE, no "every other Friday," no exception dates. The
three cases Tyler named are all expressible above, and the shape is small enough to validate in one
function:

| Real case | Encoding |
|---|---|
| "Halloween night" | `startsAt` Oct 31 00:00, `endsAt` Nov 1 06:00, `localStart` 18:00, `localEnd` 01:00 |
| "Every Friday in December" | `startsAt` Dec 1, `endsAt` Dec 31 23:59, `daysOfWeek [5]`, `localStart` 17:00, `localEnd` 23:00 |
| "This weekend" | `startsAt` Sat 00:00, `endsAt` Sun 23:59, everything else null |

**Three properties worth fixing in the design now, because each is a known bug shape in this repo:**

1. **`endsAt` is mandatory and capped.** Enforce a maximum duration (**90 days** recommended) at
   write time. Without a cap, "startsAt now, endsAt 2099" is always-on wearing a window's clothes —
   the exact model Tyler rejected — and it would arrive by accident through a UI default, not malice.
2. **`localEnd < localStart` means the window crosses midnight**, and must be handled explicitly.
   "Halloween 18:00-01:00" is the *normal* case for this feature, not an edge case. A naive
   `start <= now && now <= end` silently matches nothing for every evening window that runs past
   midnight — and it fails **closed**, so it would present as "sync never lands" with no error.
3. **A window is a list, not a singleton.** `unattendedWindows: [...]` — a member may plausibly
   agree to Halloween *and* December. A single-object field forces them to overwrite one to add the
   other. Cap the list (**8**) so evaluation stays trivially bounded.

---

## 4.2 Where does it live? — on the existing per-member consent doc

**It is per-participant per-group, and there is already a document with exactly that scope:**

```
neighborhoods/{groupId}/members/{uid}/settings/syncConsent
  categoryOptIns:    { gameDay: bool, holiday: bool, custom: bool }   // exists today
  skipNextEventIds:  [string]                                        // exists today
  unattendedWindows: [Window]                                        // NEW
```

Put it here rather than on `users/{uid}` or the member doc, for three reasons: consent to *this
crew* is not consent to every crew a member may later join; the two gates that must be read
together (`categoryOptIns` and the window) then cost **one document read, not two**; and it inherits
whatever rules already protect the consent doc rather than needing a new block — which, after the
`config/solar_scheduling` outage earlier today, is not a small consideration.

**Relation to existing participation state — the window is a fourth AND-gate, not a replacement:**

| # | Gate | Where | Read by fanout today? |
|---|---|---|---|
| 1 | Mutual membership (SYNC-1) | group `memberUids[]` x `members/{uid}` | yes |
| 2 | `participationStatus` not in {paused, optedOut} | member doc | yes |
| 3 | Consent doc exists AND `categoryOptIns[category]` | consent doc | **no — §2.5 item 1** |
| 4 | **An unattended window contains now** | consent doc | **new** |

Gates 3 and 4 arrive together on the same read, so the §2.5 parity fix and this feature are **one
change, not two.** Sequencing them separately would mean touching the same function twice.

> **Measured, and it changes the risk picture: `withConsentDoc = 0`.** Across all **3** neighborhood
> groups and **6** member documents, **not one `settings/syncConsent` document exists.** So today
> `initiateSyncSession` would skip every member (`if (!consentDoc.exists) continue`) while
> `fanoutToCrew` would fan out to every member. Adding gates 3+4 flips the unattended path from
> **"everyone"** to **"nobody"** until windows are deliberately created. That is the safe direction,
> and it means the change cannot cause an unexpected fire — only an unexpected *silence*, which
> 4.5 makes visible.

---

## 4.3 Who enforces it? — server-side, and the function is missing three inputs

**Correct: the check belongs in `fanoutToCrew`, immediately before `commandsRef.add()`.** A
client-side check is unenforceable for precisely the case this exists to serve — the receiving
client is closed, so there is nothing running to consult. The sender's client cannot be trusted to
enforce a *receiver's* consent, and the bridge polls Firestore for `status == "pending"` with no
notion of consent at all. The command document's existence **is** the authorization; nothing
downstream re-checks it.

**`fanoutToCrew` does not currently have what it needs. Three specific gaps:**

1. **It never reads the consent doc.** Its per-member loop reads the member doc and the controllers
   subcollection only. One `settings/syncConsent` get per member must be added — N extra reads,
   negligible at 2 members/group.
2. **The envelope carries no `category`.** Confirmed at the signature: `fanoutToCrew(db, {groupId,
   initiatorUid, payloadString, sessionId, source})`. Without a category, `categoryOptIns` cannot be
   evaluated at all. Either thread `category` through, or thread `eventId` and resolve it — the
   former is simpler and the caller knows it.
3. **There is no trustworthy timezone.** This is the real blocker, and it is a data problem rather
   than a code one — **measured on the live fleet:**

   ```
   users/{uid}.time_zone —  9x  "CDT"              <- NOT a valid IANA zone
                            7x  "America/Chicago"  <- valid
                            8   users have no value at all
   ```

   `"CDT"` is a **DST-specific abbreviation**, not a zone. It cannot be handed to `Intl` or any tz
   library, it is ambiguous across regions, and it is *wrong for half the year by construction* — a
   window written against it silently shifts an hour at the DST boundary. The client derives its
   timezone from the device (`DateTime.timeZoneOffset`) and does not persist an IANA name.

   **Design answer: store `ianaTz` ON the window itself, captured at agreement time** from the
   device that created it, and never consult `users/{uid}.time_zone`. This makes each window
   self-contained and auditable ("you agreed to 6-11pm America/Chicago"), removes the dependency on
   a field that is 9/16 invalid, and avoids a fleet-wide backfill on the critical path. Validate it
   against the IANA database at write time and **refuse the window** if it does not resolve — a
   window that cannot be evaluated must never be treated as open.

**Evaluation order matters.** Check the cheap local gates (1, 2, 4) before the expensive ones. A
member outside their window should cost one consent read and no controller reads.

**Failure posture: closed.** If the consent doc is unreadable, the timezone will not resolve, or the
window list is malformed, **skip the member and report it** (4.5). Every other gate in this codebase
that guessed on ambiguous input is in this document as a defect.

---

## 4.4 What the absent neighbour sees afterward — a receipt, and it must not be the command doc

**The data already exists.** Fanout writes `initiatorUid`, `sessionId`, `source`, and the bridge
updates `status` (`pending -> executing -> completed | failed`) plus `completedAt`, and `error` /
`result` on terminal states. So "who changed my lights, when, and did it work" is **already
answerable** — this is genuinely better than the device-timer path, which as noted has no
fire-level telemetry at all.

> **But do not build the receipt on the command document, because I deployed the thing that will
> delete it.** `scheduledDataCleanup` went live earlier today with a **7-day TTL on
> `users/{uid}/commands`** (first run removed 3,336 of them). A history surface reading command docs
> would work perfectly in testing and then quietly lose everything older than a week — and "my
> lights changed and I don't know why" is *exactly* the question asked more than seven days later.

**Recommendation: a small durable per-receiver record**, written by the fanout at the moment it
decides to fire:

```
users/{uid}/sync_receipts/{receiptId}
  firedAt, groupId, groupName, initiatorUid, initiatorName,
  category, sessionId, commandId,
  authorizedBy: { windowId, label, localStart, localEnd, ianaTz },   <- "you agreed to this"
  outcome: pending | completed | failed, outcomeAt, error
```

Two notes on shape. `outcome` needs mirroring from the command doc — a Firestore trigger on command
status change is the cheap way; **the bridge should not be asked to write two documents**, since
that is a firmware change and the current bridge already writes status with an explicit
`updateMask`. And `groupName`/`initiatorName` should be **denormalised at write time**: the receipt
must still read correctly after the sender leaves the group.

**`authorizedBy` is the part that changes the support call.** "Chris synced the crew at 7:42pm,
inside the Halloween window you agreed to" is a categorically different conversation from "your
lights changed." It also gives the member the exact object to revoke.

Retention: these are low-volume and user-facing, unlike commands (8,386 live). A **season, or 90
days**, is defensible. If they ever get a TTL, add it to `runDataCleanup` **with a `limit()`** — see
C5 in `audit/DIAGNOSTICS_FIX.md` for why an unbounded query there aborts the entire run.

---

## 4.5 Outside the window — skip, and **tell the sender**

**Recommendation: skip, never queue, and return per-member reasons to the sender.**

*Not queued.* A neighbourhood sync is a shared live moment. Delivering it when the window opens —
possibly the next evening — is worse than not delivering it: the member's house lights up for an
event nobody is having. Windows also make queue semantics genuinely ambiguous (does a Friday sync
fire next Friday?). Drop it.

*Not silent.* Tyler's framing is right and it is the failure shape this codebase has spent a week
eliminating — the missing-`offTime` lease drop, the all-stub clobber, the schedule `continue` that
skipped a whole schedule, trust-2xx. **A sync that half-lands with nobody told is the same bug
wearing different clothes.**

**`fanoutToCrew` currently returns `{memberCount, commandCount, skipped}` — `skipped` is a bare
integer with no reason.** That is not enough to tell a sender anything useful. It should return a
per-member breakdown:

```
{ delivered: [...], skipped: [{ uid, displayName, reason }] }
   reason in outsideWindow | noConsentDoc | categoryOptedOut | paused
           | notMutualMember | bridgeOffline | noController
```

Surfaced as: **"4 of 6 neighbours received this. 2 aren't accepting syncs right now."**

> **One caution that should shape the copy: "outside their window" leaks absence.** A sender who
> learns Ellie is outside her window has learned something about Ellie's evening, and by extension
> that her house may be empty — from a feature she enabled for a different purpose. Within a
> self-selected neighbourhood crew this is probably acceptable, but the wording should stay
> **neutral and about the setting, not the person**: "not accepting syncs right now," never "away,"
> "not home," or "offline." Distinguishing `outsideWindow` from `bridgeOffline` in the *sender's*
> UI is not worth the inference it hands them — collapse both to one neutral state for the sender
> while keeping the precise reason in logs and in the receiver's own receipt.

---

## 4.6 The preset problem — **already resolved in §2.3; the windowed design inherits nothing**

Confirmed on the wire, not assumed. A grep of `lib/features/neighborhood` for `psave`, `loadPreset`,
`savePreset` and the `"ps"` key returns **no matches**. Every sync fire is inline full state —
effect, palette, speed, intensity, colours, brightness — via `normalizeWledPayload`. The premise
("if the synced pattern is not resident on the receiving controller") **does not arise**: nothing
needs pre-staging and zero preset slots are consumed. A `psave` *would* relay if one were ever
introduced (the bridge's `executeCommand` has three special cases and a `/json/state` default), so
the option stays open — but this feature does not need it. **No work here.**

---

## 4.7 Bridge dependency — re-measured, and it is the binding constraint

Fresh census, **2026-08-05T23:18Z** (independent of §2.4's 20:19Z run):

```
users 24 · with >= 1 controller 15 · with bridge_status/current 9 · heartbeat <= 10 min 7

  7 ONLINE   (all < 0.5 min — the bridges that are up are very much up)
  2 STALE    15.09 days · 21.46 days
  6 controller-owning accounts have NO bridge_status document — never heartbeated
```

**Ceiling: 7 of 15 controller-owning accounts (47%) could receive an unattended sync right now** —
consent, windows and code all being perfect. One bridge (`r0iBwg8bye`) came online between the two
censuses, so the number moves.

Two consequences for this design:

1. **A windowed sync to an offline bridge is a no-op regardless of consent**, and it fails *silently
   today* — the command doc sits `pending` until the 7-day TTL removes it. `bridgeOffline` therefore
   has to be a first-class skip reason in 4.5, resolved by reading `bridge_status/current`'s
   heartbeat age **before** writing the command. Otherwise the sender is told "delivered" for a
   house that will never light.
2. **Do not gate the rollout on fleet health, and do not let the 47% masquerade as consent
   working.** These are independent failures with the same symptom — nothing happened — and during
   testing a stale bridge will look exactly like a closed window. The skip reasons are what keep
   them distinguishable, which is an argument for building 4.5 *first*.

---

## 4.8 What this does NOT solve

- **Revocation while away (§2.5 item 3) remains open.** `selfLeaveSync` writes to a group command
  channel only an open app consumes. A window *bounds* exposure and expires on its own, which is why
  it can ship first — but "stop the sync running on my house right now, from my phone, elsewhere"
  still has no path. A window makes this less urgent; it does not close it.
- **`isParticipating` still has no STOP-path gate** (§2.5).
- **The window says nothing about *what* may be fired.** A crew member inside their window accepts
  any pattern the initiator sends, including one they would find garish. Out of scope, worth naming.
- **No default window is proposed.** New members should get **none** — an empty `unattendedWindows`
  means nothing lands unattended, which is the correct default for a feature whose entire premise is
  explicit agreement.

---

## 4.9 Build order — gates, not a wish list

1. **Skip-reason plumbing (4.5)** — return per-member reasons. Do this **first**: without it, every
   subsequent step is untestable, because a closed window, a missing consent doc and a dead bridge
   are indistinguishable at the fleet level today.
2. **Consent parity (§2.5 item 1)** — read the consent doc in `fanoutToCrew`; require existence +
   `categoryOptIns[category]`. Requires threading `category` through the envelope. Ships with 3.
3. **Window evaluation (4.1-4.3)** — `ianaTz` on the window, midnight-crossing handled, `endsAt`
   capped, malformed implies closed.
4. **Receipts (4.4)** — including the command-status mirror trigger.
5. **Bridge-liveness skip reason (4.7)**.
6. **Only then** consider flipping `config/sync_fanout.enabled`.

**Steps 1-3 are gates on the flag flip, not follow-ups** — the same relationship S1 had to S3. And
per the `config/solar_scheduling` lesson from earlier today: when that flag is eventually flipped,
**verify it with an authenticated non-admin token**, not an admin readback, or the flip will report
healthy while the client cannot read it.

---

## 4.10 Open questions for Tyler

1. **Who may create or edit a member's window — only that member?** Recommendation: **only the
   member**, never the group creator, or "agreed window" is not agreed. This needs a rules block
   (`request.auth.uid == memberUid`) that does not exist yet.
2. **Should a window be per-category** ("Halloween pattern yes, Game Day no") or a single window
   covering all categories the member has opted into? Recommendation: **single window, ANDed with
   the existing `categoryOptIns`** — two axes are enough; three is a settings screen nobody finishes.
3. **Does an in-progress sync survive its window closing mid-fire?** Recommendation: yes — evaluate
   the window at *fanout* time only. Re-evaluating mid-session means a member's lights strand in a
   half-applied state with no one present.
4. **Is 90 days the right maximum?** A holiday installer might reasonably want "all of December,"
   which fits; "all season" (Nov-Jan) does not.
