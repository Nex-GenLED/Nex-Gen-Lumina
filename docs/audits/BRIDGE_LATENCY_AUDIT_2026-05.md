# Bridge Latency Audit — May 2026

**Date:** 2026-05-26
**Mode:** Read-only audit. No code changed.
**Baseline:** Item #87 / commit `47f8ba7` — static 10 s remote poll cadence,
`_polling` in-flight gate, sticky `state.connected` (3 consecutive failures).

**Symptoms under investigation**

1. ~8 s cold-start before real status surfaces on the dashboard.
2. 5–10 s for a single design / effect change to take effect (remote).
3. Command backup when the user taps rapidly.

For each section: file:line, the relevant snippet, and an explicit
**APP-SIDE vs FIRMWARE** classification.

---

## 1. Cold-start status hydration

### How the dashboard first obtains controller state

`WledNotifier.build()` is called the first time `wledStateProvider` is read.
It returns the seed `WledStateModel.initial()` (no `connected`, no `bri`, no
colors) and kicks off `_startPolling()`.

[lib/features/wled/wled_providers.dart:371-382](../../lib/features/wled/wled_providers.dart#L371-L382):

```dart
@override
WledStateModel build() {
  final s = WledStateModel.initial();
  _startPolling();
  ref.onDispose(() {
    _poller?.cancel();
    _poller = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  });
  return s;
}
```

`_startPolling()` builds a `Timer.periodic` whose first callback fires
**after** the period, not immediately.

[lib/features/wled/wled_providers.dart:384-394](../../lib/features/wled/wled_providers.dart#L384-L394):

```dart
void _startPolling() {
  _poller?.cancel();
  // ...
  final pollMs = ref.read(isRemoteModeProvider) ? 10000 : 1500;
  _poller = Timer.periodic(Duration(milliseconds: pollMs), (_) async {
    // ...
  });
}
```

There is **no one-shot fetch at construction time.** The notifier seeds with
`initial()` and waits the full `pollMs` for the first periodic tick.

### Cold-start delay in LOCAL mode

- `pollMs = 1500` ms.
- First tick → `service.getState()` is a direct HTTP `GET /json/state` on the
  LAN. Typical LAN latency ≪ 1 s.
- Connectivity stream (`watchConnectivity`) yields its first value
  *immediately* on subscription — not a contributor.
  [lib/services/connectivity_service.dart:112-123](../../lib/services/connectivity_service.dart#L112-L123).
- **Expected cold-start: ~1.5–2 s.** Matches lived experience.

### Cold-start delay in REMOTE mode

- `pollMs = 10000` ms (Item #87 baseline,
  [wled_providers.dart:393](../../lib/features/wled/wled_providers.dart#L393)).
- First tick → `CloudRelayRepository.getState()` writes a Firestore command
  doc and `_waitForCompletion` polls Firestore every 500 ms until the bridge
  flips `status` to `completed`.
  [lib/features/wled/cloud_relay_repository.dart:53,146-167](../../lib/features/wled/cloud_relay_repository.dart#L53-L167).
- Bridge picks up new commands every `POLL_INTERVAL_MS = 1000` ms.
  [esp32-bridge/config.h.example:61](../../esp32-bridge/src/config.h.example#L61),
  [esp32-bridge/src/main.cpp:229-238](../../esp32-bridge/src/main.cpp#L229-L238).

**Cold-start budget in remote:**

| Stage | Time |
|---|---|
| Wait for first Timer.periodic tick | **10 000 ms** |
| Firestore command write | ~300–800 ms |
| Bridge poll pickup (worst case 1 s) | ~500 ms avg |
| Bridge GET /json/state on LAN | ~200 ms |
| Bridge PATCH status=completed | ~300–800 ms |
| App `_waitForCompletion` notices completed (500 ms poll) | ~250 ms avg |
| **Total** | **≈12–13 s** to first visible state |

The reported **~8 s** is consistent with local mode plus some HTTP cold-cache
warmup, OR remote mode where the first tick coincidentally lands faster than
expected — but the dominant cost in remote is the **10 s blocking wait for
the first periodic tick before any request is issued at all.**

> **Classification: APP-SIDE.** The 10 s first-tick wait is purely a property
> of the `Timer.periodic` construction in `WledNotifier._startPolling`. Adding
> an unawaited one-shot `_pollOnce()` immediately after `Timer.periodic(...)`
> would hydrate state in parallel with the periodic tick window, cutting
> remote cold-start to ~2–5 s (Firestore round-trip only) and local
> cold-start to ~200 ms. No firmware change required.

---

## 2. Single user command apply path

### LOCAL mode

User tap → `WledNotifier.togglePower / setBrightness / setColor / etc.` →
`_postUpdate(...)` →
`service.applyJson(payload)` where `service` is `WledService`.

[lib/features/wled/wled_service.dart:379-384](../../lib/features/wled/wled_service.dart#L379-L384):

```dart
Future<bool> applyJson(Map<String, dynamic> payload) async {
  final participating = await getCachedParticipatingChannels();
  final normalized = normalizeWledPayload(payload);
  final expanded = expandForParticipation(normalized, participating);
  return _postJson(expanded);
}
```

`_postJson` is a direct `http.post` to `http://<controller-ip>/json/state`
with a 15 s timeout:
[lib/features/wled/wled_service.dart:343-347](../../lib/features/wled/wled_service.dart#L343-L347):

```dart
final response = await http.post(
  _uri('/json/state'),
  headers: {'Content-Type': 'application/json'},
  body: body,
).timeout(const Duration(seconds: 15));
```

**Local apply is a single HTTP round-trip on the LAN. Typical: 100–300 ms.**
No queue, no Firestore involvement, no relay. After completion `_postUpdate`
sleeps 150 ms then fires `_pollOnce()` to refresh state
([wled_providers.dart:1219-1228](../../lib/features/wled/wled_providers.dart#L1219-L1228)).

### REMOTE mode

User tap → `WledNotifier._postUpdate(...)` (or pattern path:
`repo.applyJson(...)`) → `CloudRelayRepository.applyJson` →
`_executeBool('applyJson', ...)` → `_executeCommand(...)`.

[lib/features/wled/cloud_relay_repository.dart:217-226](../../lib/features/wled/cloud_relay_repository.dart#L217-L226):

```dart
Future<bool> applyJson(Map<String, dynamic> payload) async {
  final participating = await getCachedParticipatingChannels();
  final normalized = normalizeWledPayload(payload);
  final expanded = expandForParticipation(normalized, participating);
  return _executeBool('applyJson', expanded);
}
```

`_executeCommand` does **three things sequentially**:

1. `_commandsRef.add(command.toFirestore())` — writes a new doc under
   `/users/{uid}/commands/{commandId}` with `status: "pending"`.
   [cloud_relay_repository.dart:67-85](../../lib/features/wled/cloud_relay_repository.dart#L67-L85).
2. Attaches a `snapshots()` listener for diag logging.
3. `await _waitForCompletion(commandId)` — polls
   `_commandsRef.doc(commandId).get()` every **500 ms** until
   `command.isComplete` (status `completed` / `failed` / `timeout`), bounded
   by `_commandTimeout = 45 s`.
   [cloud_relay_repository.dart:50,146-167](../../lib/features/wled/cloud_relay_repository.dart#L50-L167).

**Bridge-side consumer** ([esp32-bridge/src/main.cpp:225-239,686-846](../../esp32-bridge/src/main.cpp#L225-L846)):

- `loop()` checks `millis() - lastPollTime >= POLL_INTERVAL_MS` (1 s).
- `pollCommands()` does `:runQuery` for
  `WHERE status == "pending" LIMIT MAX_COMMANDS_PER_POLL` (= 5).
- For each result: `executeCommand`
  - `updateCommandStatus(commandId, "executing")` (Firestore PATCH)
  - `makeWledRequest(...)` — HTTP GET/POST to WLED on LAN
  - `updateCommandStatus(commandId, "completed", ..., response)` (Firestore PATCH)

**Where the 5–10 s in remote mode goes (single command):**

| Stage | Typical | Notes |
|---|---|---|
| App writes doc to Firestore | 300–800 ms | network + Firestore commit |
| Bridge poll wait (avg ½ × 1 s) | 500 ms | bounded by `POLL_INTERVAL_MS` |
| Bridge `:runQuery` round-trip | 300–600 ms | Firestore REST + JSON parse |
| Bridge PATCH status=executing | 200–500 ms | Firestore REST |
| Bridge HTTP to WLED (LAN) | 100–300 ms | direct |
| Bridge PATCH status=completed | 200–500 ms | Firestore REST |
| App `_waitForCompletion` next 500 ms poll picks up | 250 ms avg | app-side |
| **Total** | **~2–3.5 s steady-state; 5–10 s under load** | |

> **Classification:** The single-command latency is **split**. The intrinsic
> floor (~2 s) is dominated by **firmware-side serial Firestore I/O**: three
> sequential Firestore HTTP round-trips per command (`:runQuery`, PATCH
> executing, PATCH completed). That's a firmware redesign question, not an
> app-side knob.
>
> However, the **app-side `_waitForCompletion` 500 ms poll cadence** adds
> ~250 ms avg of needless lag — converting this to a Firestore `snapshots()`
> listener (which the diag block already opens at
> [cloud_relay_repository.dart:91-98](../../lib/features/wled/cloud_relay_repository.dart#L91-L98))
> would shave 0–500 ms off every command **purely app-side**. The diag
> listener already proves the snapshot path works for status changes.

---

## 3. Rapid-press command handling (the backup)

### What happens to each tap?

**Every tap enqueues a separate durable Firestore command document.** There
is no app-side debounce, throttle, or coalescing on user-initiated commands.

Dashboard brightness slider — fires `setBrightness` on **every drag tick**:

[lib/features/dashboard/wled_dashboard_page.dart:981-983](../../lib/features/dashboard/wled_dashboard_page.dart#L981-L983):

```dart
onChanged: st.connected
    ? (v) => ref.read(wledStateProvider.notifier).setBrightness(v.round())
    : null,
```

There is no `onChangeEnd`, no `Timer? _debounce`, no `_lastSendAt`
throttle. A single 1-second slider drag emits dozens of brightness values;
in remote mode, that is dozens of separate Firestore command writes.

Pattern card taps go through `_applyPattern` →
`repo.applyJson(payload)` directly
([pattern_grid_widgets.dart:1681](../../lib/features/wled/pattern_grid_widgets.dart#L1681))
— no debounce, no in-flight check.

Compare to the **pattern adjustment panel**, which **does** debounce at
200 ms ([widgets/pattern_adjustment_panel.dart:182,257-258](../../lib/widgets/pattern_adjustment_panel.dart#L182-L258)).
The dashboard does not.

### Does the Item #87 `_polling` gate apply to user commands?

**No.** The `_polling` gate guards `Timer.periodic` *getState polls only* —
not user-initiated writes.

[lib/features/wled/wled_providers.dart:394-410](../../lib/features/wled/wled_providers.dart#L394-L410):

```dart
_poller = Timer.periodic(Duration(milliseconds: pollMs), (_) async {
  final service = ref.read(wledRepositoryProvider);
  if (service == null) return;
  if (_posting) return; // avoid fighting with user updates
  if (_polling) {
    debugPrint('🔍 BridgeRouter: poll skipped (previous in-flight)');
    return;
  }
  _polling = true;
  // ...
});
```

User commands flow through `_postUpdate`, which sets `_posting = true` for
its own duration but **does not check `_posting` on entry**:

[lib/features/wled/wled_providers.dart:1098-1223](../../lib/features/wled/wled_providers.dart#L1098-L1223).
The flag is purely a hint to the poller to back off, not a serialization
gate on user commands. Two parallel taps → two parallel `_postUpdate` calls
→ two parallel `applyJson` calls → two parallel Firestore doc writes.

### Queue data structure and drop semantics

- **App-side:** Firestore subcollection `/users/{uid}/commands`. Every
  enqueue is an `_commandsRef.add(...)`
  ([cloud_relay_repository.dart:82](../../lib/features/wled/cloud_relay_repository.dart#L82)).
  Append-only. **No supersession, no replace, no coalescing.**
- **Bridge-side:** drains up to `MAX_COMMANDS_PER_POLL = 5` per 1 s tick,
  executes them sequentially in a `for (JsonObject result : results)` loop
  ([main.cpp:725-741](../../esp32-bridge/src/main.cpp#L725-L741)).

### The backup mechanism

When N rapid taps fire:

1. N Firestore writes complete in ~300–800 ms each (parallel — no app
   serialization).
2. Bridge drains 5 every 1 s. Each command costs ~1–2 s of bridge work
   (one WLED HTTP + two Firestore PATCHes).
3. Effective drain rate ≈ 2–4 commands/s. Above that, queue depth grows.
4. Each app-side `_waitForCompletion` call sits in a 500 ms poll loop for
   **its specific docId** up to 45 s
   ([cloud_relay_repository.dart:50,149](../../lib/features/wled/cloud_relay_repository.dart#L50-L149)).
   The 5th tap waits behind the 4 earlier commands.
5. The visible light state lags by `(N-1) × avg_drain_time` because
   commands execute in arrival order, not "latest wins."

> **Classification: APP-SIDE wins biggest.** The fundamental fix —
> **latest-wins coalescing for transient knobs (brightness, speed,
> intensity, color)** — is entirely client-side and ships to existing
> bridges with no firmware change. Concretely:
>
> - Add a per-command-type in-flight gate: while a `setState` write for
>   "brightness" is in flight, replace any earlier-queued duplicate locally
>   before issuing.
> - Move slider events from `onChanged` to `onChangeEnd`, or wrap
>   `setBrightness` / `setSpeed` in a 150–250 ms debounce identical to the
>   pattern adjustment panel pattern.
> - For pattern apply: gate `repo.applyJson` so a second tap during an
>   in-flight pattern apply replaces the pending request rather than
>   queueing another one.
>
> A **firmware-side dedupe** (bridge collapses N pending commands of the
> same type to the latest) is *also* possible but would be additive — the
> app-side fixes deliver the user-visible win immediately and on every
> deployed bridge.

---

## 4. Connection-state sticky logic

[lib/features/wled/wled_providers.dart:322-325](../../lib/features/wled/wled_providers.dart#L322-L325):

```dart
/// Consecutive remote poll failures. After 3, bridge is marked unreachable
/// even if it was previously confirmed — prevents stale "Connected" status.
int _consecutiveRemoteFailures = 0;
static const _maxRemoteFailuresBeforeDowngrade = 3;
```

[lib/features/wled/wled_providers.dart:413-449](../../lib/features/wled/wled_providers.dart#L413-L449):

```dart
final isRemote = ref.read(isRemoteModeProvider);
if (data == null) {
  if (isRemote) {
    _consecutiveRemoteFailures++;
    if (_consecutiveRemoteFailures >= _maxRemoteFailuresBeforeDowngrade) {
      if (state.connected) {
        state = state.copyWith(connected: false);
      }
      ref.read(bridgeReachableProvider.notifier).state = false;
    }
  } else {
    // Local mode: flip immediately
    if (state.connected) {
      state = state.copyWith(connected: false);
    }
    _consecutiveRemoteFailures = 0;
  }
  // ...
}
// On success:
_consecutiveRemoteFailures = 0;
if (isRemote) {
  ref.read(bridgeReachableProvider.notifier).state = true;
}
```

### Time-to-offline

- Remote: **3 consecutive null/timeout polls** × **10 s cadence** = up to
  **~30 s** plus per-poll latency before the dot flips. Worst case (each
  poll times out at the full 45 s `_commandTimeout`): ~135 s, though that's
  not the steady-state path — Firestore-side reads resolve faster than the
  command-completion timeout.
- Local: immediate flip on a single null.

### Reset conditions

The counter resets on:

- Any successful poll
  ([wled_providers.dart:446](../../lib/features/wled/wled_providers.dart#L446)).
- Repository transitioning to local mode
  ([wled_providers.dart:437](../../lib/features/wled/wled_providers.dart#L437)).
- `refreshConnection()` (e.g. app resume)
  ([wled_providers.dart:809](../../lib/features/wled/wled_providers.dart#L809)).

> **Classification: APP-SIDE.** Both the threshold (`3`) and the cadence
> (`10 000` ms) are constants in
> [wled_providers.dart:325,393](../../lib/features/wled/wled_providers.dart#L325-L393).
> Tunable without firmware. Trade-off: lowering threshold or cadence
> reintroduces the dot-flicker Item #87 was designed to solve.

---

## 5. Firmware boundary

### Pure app-side wins (no bridge update; helps every fielded bridge)

1. **Cold-start one-shot fetch.** Fire an immediate `_pollOnce()` after
   `Timer.periodic` construction in
   [wled_providers.dart:394](../../lib/features/wled/wled_providers.dart#L394).
   Cuts remote cold-start ~10 s → ~2–5 s; local ~1.5 s → ~200 ms.
2. **Latest-wins coalescing for transient knobs.** Debounce brightness /
   speed / intensity slider events at the call site
   ([wled_dashboard_page.dart:981](../../lib/features/dashboard/wled_dashboard_page.dart#L981)),
   and add a per-command-type in-flight gate inside `_postUpdate` so a
   second slider event during an in-flight write replaces rather than
   queues. Existing 200 ms debounce in
   [pattern_adjustment_panel.dart:257-258](../../lib/widgets/pattern_adjustment_panel.dart#L257-L258)
   is the template.
3. **Pattern-apply in-flight gate.** Same shape: a second
   `repo.applyJson` while a pattern is in flight replaces the pending
   request.
4. **Snapshot-listener completion path.** Replace
   `_waitForCompletion`'s 500 ms `.get()` poll with a one-shot
   `snapshots()` subscription (the diag block already opens one at
   [cloud_relay_repository.dart:91-98](../../lib/features/wled/cloud_relay_repository.dart#L91-L98)).
   Saves 0–500 ms per command and reduces Firestore read volume.
5. **Sticky-threshold tuning.** Both constants in
   [wled_providers.dart:325,393](../../lib/features/wled/wled_providers.dart#L325-L393)
   are app-side knobs.

### Pure firmware-side (requires bridge re-flash; swap-only for the field)

1. **Reduce serial Firestore round-trips per command.** Bridge currently
   does: `:runQuery` → PATCH `executing` → WLED HTTP → PATCH
   `completed`. Three Firestore REST calls per command. Folding the
   `executing` status into a single trailing PATCH at completion (or
   skipping it for non-getState commands) would cut ~200–500 ms off each
   command for every customer.
2. **Increase `POLL_INTERVAL_MS` granularity or move to Realtime
   Database / WebSocket.** Today `POLL_INTERVAL_MS = 1000` is the floor
   for command pickup. A push-style transport (Firestore Realtime
   listener on the bridge, RTDB onValue, or a TCP/WebSocket persistent
   connection) would drop pickup latency to ~tens of ms.
3. **Bridge-side dedupe of same-type pending commands.** Additive to
   the app-side fix above.

> **Firmware critical-bar policy implications:** Items (1) and (3) under
> "firmware-side" are local changes to the existing `pollCommands` /
> `executeCommand` flow — low brick risk, no network/auth surface change.
> Item (2) is a transport rewrite (HTTPClient → WebSocket / RTDB
> listener) — higher risk: changes auth flow, persistent socket state,
> watchdog assumptions, and would need careful staging given Tyler's
> swap-only field deployment model.

---

## Symptom → root-cause table

| # | Symptom | Root cause | App-side / Firmware | Helps field fleet (Y/N) |
|---|---|---|---|---|
| 1 | ~8 s cold-start before real status shows | `Timer.periodic` first tick waits the full `pollMs` (10 s remote / 1.5 s local) before any fetch is issued — `WledNotifier.build()` has no one-shot hydration | **APP-SIDE** | **Y** |
| 2 | 5–10 s for a single design / effect change (remote) | Three sequential Firestore REST round-trips per command on the bridge (`:runQuery` + PATCH executing + PATCH completed) + app-side 500 ms `_waitForCompletion` poll cadence | **Mostly FIRMWARE** (intrinsic bridge cost) + **partially APP-SIDE** (poll→snapshot listener saves 0–500 ms) | App-side portion: **Y**. Firmware portion: **N** until reflash. |
| 3 | Command backup on rapid taps | No app-side debounce / throttle / coalescing on user commands; every tap is a durable Firestore enqueue; bridge drains serially at ~2–4 cmd/s; `_polling` gate guards only the poll loop, not user writes | **APP-SIDE** | **Y** |
| 4 (related) | Up-to-30 s delay before the dot flips red in remote | Sticky 3-consecutive-failures × 10 s cadence (Item #87 design choice — eliminates dot flicker) | **APP-SIDE** (constants in `wled_providers.dart`) | **Y** if tuned; current values are intentional |
