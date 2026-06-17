# Channel Mapping Audit — 2026-05-26

Read-only audit. No code modified. Focus: a Dig-Octa install in local mode
(no bridge) where channel 2 greys out / drops after the first command,
while WLED drives output 2 perfectly when commanded directly.

User's stated hypothesis: indexing/off-by-one in the
channel→WLED-segment→participation chain. Dig-Octa is 0-indexed at the
hardware (channel 1 → GPIO0, channel 2 → GPIO1, ...).

**Bottom line up front:** The chain is consistently 0-indexed end-to-end —
no off-by-one. The "first works, channel 2 drops" pattern is a
**stale-participation-cache lazy-load race**, not an indexing bug. The
single most likely fix site is identified at the end.

---

## 1. Channel identity in the roofline / config layer

**Model:** [`RooflineSegment.channelIndex`](../../lib/models/roofline_segment.dart#L540)
```dart
/// Which WLED/controller channel this segment belongs to (0-based).
/// Maps to hardware bus index — channel 0 = bus 0, channel 1 = bus 1, etc.
final int channelIndex;
```
**Convention: 0-indexed.** Doc-locked: "channel 0 = bus 0, channel 1 = bus 1."

**Assignment sites:**

- Constructor default in editor — [`RooflineConfigEditorNotifier.addSegment`](../../lib/features/design/roofline_config_providers.dart#L208):
  ```dart
  int channelIndex = 0,
  ```
- User mutation — [`setSegmentChannel(segmentId, channelIndex)`](../../lib/features/design/roofline_config_providers.dart#L257):
  ```dart
  final updated = existing.copyWith(channelIndex: channelIndex);
  ```
- Editor "+ Add Channel" dropdown — [roofline_editor_screen.dart:452-460](../../lib/features/site/roofline_editor_screen.dart#L452-L460):
  ```dart
  if (v == _totalChannelCount) {
    setState(() => _totalChannelCount++);
    channelIndex = _totalChannelCount - 1;   // ← converts 1-indexed count to 0-indexed
  } else {
    channelIndex = v ?? 0;
  }
  ```
  Correct conversion: `_totalChannelCount` is 1-indexed (a count); `channelIndex` is 0-indexed.
- Editor dropdown population — [roofline_editor_screen.dart:424-440](../../lib/features/site/roofline_editor_screen.dart#L424-L440):
  ```dart
  for (int i = 0; i < _totalChannelCount; i++)
    DropdownMenuItem(
      value: i,
      child: …Text('Channel ${i + 1}'),  // ← 1-indexed DISPLAY ("Channel 1"), 0-indexed STORAGE (value: i)
    ),
  ```
- Chip label — [roofline_editor_screen.dart:665](../../lib/features/site/roofline_editor_screen.dart#L665):
  ```dart
  'CH${channelIndex + 1}',   // display: 1-indexed
  ```

**fromJson default** — [roofline_segment.dart:743](../../lib/models/roofline_segment.dart#L743):
```dart
channelIndex: json['channel_index'] as int? ?? 0,
```

**Verdict:** roofline layer is **consistently 0-indexed in storage and computation**, 1-indexed only in user-facing labels (Channel 1, CH2, etc.). No site assigns `channelIndex = _totalChannelCount` (which would be the off-by-one bug).

---

## 2. Channel → WLED segment / GPIO mapping

**Lumina's authoritative channel model:** [`DeviceChannel`](../../lib/features/wled/zone_providers.dart#L58-L72)
```dart
class DeviceChannel {
  final int id;       // bus index (0, 1, ...)     ← 0-INDEXED
  final String name;  // "Channel 1", "Channel 2"  ← 1-INDEXED display
  final int start;    // LED start index (inclusive)
  final int stop;     // LED stop index (exclusive)
  final int gpioPin;  // GPIO pin number
}
```

**Derivation from WLED config:** [`deviceChannelsProvider`](../../lib/features/wled/zone_providers.dart#L76-L90)
```dart
final deviceChannelsProvider = Provider<List<DeviceChannel>>((ref) {
  final hwConfig = ref.watch(deviceHardwareConfigProvider).valueOrNull;
  if (hwConfig == null || hwConfig.buses.isEmpty) return [];
  return hwConfig.buses.asMap().entries.map((e) {
    final i = e.key;            // ← bus position in hw.led.ins[] (0-indexed)
    final bus = e.value;
    return DeviceChannel(
      id: i,                    // ← Lumina's channel id = WLED bus POSITION
      name: 'Channel ${i + 1}', // ← display label
      start: bus.start,
      stop: bus.start + bus.len,
      gpioPin: bus.pin.isNotEmpty ? bus.pin.first : -1,
    );
  }).toList();
});
```

**Critical observation:** Lumina identifies a channel by its **position in
WLED's `hw.led.ins[]` array**, NOT by GPIO and NOT by WLED segment id. The
GPIO pin is read into `gpioPin` for display only — it does NOT participate
in the channel-id chain.

**Channel → WLED segment id mapping:** [`applyChannelFilter`](../../lib/features/wled/wled_payload_utils.dart#L56-L90)
```dart
final expandedSegs = channelIds.map((id) {
  final s = <String, dynamic>{'id': id, ...template, 'on': true};
  for (final ch in channels) {
    if (ch.id == id) {
      s['start'] = ch.start;
      s['stop'] = ch.stop;
      break;
    }
  }
  return s;
}).toList();
```
Lumina's channel id is passed verbatim as the WLED segment `id`. **Strong
assumption: WLED segment N targets bus N**, which is only true if the WLED
device has been configured with one segment per bus, in order. The
[config pusher](../../lib/services/wled_config_pusher.dart#L113-L132) writes
buses in order (`for (int i = 0; i < channelCount; i++) buses.add(...)`),
preserving the bus-id ↔ position ↔ channel-id correspondence. No
arithmetic transform — pure passthrough.

**No +1/-1 / N→N-1 anywhere in the storage/compute path.** The only `+1`
is in display labels (`'Channel ${i + 1}'`, `'CH${channelIndex + 1}'`),
which are sinks — they never flow back into the mapping logic.

**What Lumina expects vs what's actually on the controller:** Lumina
assumes the WLED config's `hw.led.ins[]` array matches what Lumina pushed
(or what the user configured). The "user had to hand-edit WLED pins to
match Lumina" symptom suggests the customer's Dig-Octa was using
**different pin defaults** than the SKIKBILY-targeted
[`defaultPins = [16, 3, 1, 4]`](../../lib/services/wled_config_pusher.dart#L111).
This is a **pin-level mismatch, NOT a channel-index mismatch** — once the
user hand-edits pins to match the buses Lumina expects, the bus-position-
to-channel-id chain is consistent.

---

## 3. Participation cache — what greys out the chip

**Chip grey-out logic** — [channel_selector_bar.dart:194-207](../../lib/features/dashboard/widgets/channel_selector_bar.dart#L194-L207):
```dart
for (final ch in channels)
  Builder(builder: (_) {
    final isParticipating =
        participatingSet == null || participatingSet.contains(ch.id);  // ← 0-indexed
    return _buildChip(
      …
      disabled: !isParticipating,
      …
    );
  }),
```
The chip greys when `participatingSet != null` AND `!participatingSet.contains(ch.id)`. The participation set's KEY is the **same 0-indexed `DeviceChannel.id`** the rest of the chain uses. **No translation, no off-by-one.**

**Cache shape:** [`participationCacheNotifier`](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L319-L320)
```dart
final ValueNotifier<List<int>?> participationCacheNotifier =
    ValueNotifier<List<int>?>(null);
```

**Cache semantics** (from the [docstring](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L327-L334)):
- `null` — no preference set (cold start). Chokepoint passes through; chips stay enabled.
- `[]` — explicit "no channels." Chokepoint passes through; UI gate is open but the effective list is empty.
- `[..]` — explicit set. Apply expands to these channel ids; chips NOT in the set grey out.

**Persistence:** [`saveLocalParticipatingChannels`](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L382-L400) writes to SharedPreferences key `_kLocalParticipatingChannelsKey` and updates the in-memory `ValueNotifier` synchronously.

**Lazy load:** [`getCachedParticipatingChannels`](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L334-L340)
```dart
Future<List<int>?> getCachedParticipatingChannels() async {
  if (!_participationCacheLoaded) {
    participationCacheNotifier.value = await loadLocalParticipatingChannels();
    _participationCacheLoaded = true;
  }
  return participationCacheNotifier.value;
}
```
**First call only** awaits disk. Subsequent calls return the cached value.

**Synchronous peek:** [`peekCachedParticipatingChannels`](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L346-L348)
```dart
List<int>? peekCachedParticipatingChannels() {
  return _participationCacheLoaded ? participationCacheNotifier.value : null;
}
```
**Returns `null` when the cache is COLD** (not yet loaded), regardless of what's on disk. This is critical to the race described in §4.

**Who writes the cache (the entire surface — three sites only):**

| Site | When | What is written |
|---|---|---|
| [game_day_autopilot_providers.dart:162](../../lib/features/autopilot/game_day_autopilot_providers.dart#L162) | Game Day Autopilot apply | `resolveParticipatingChannels(explicit=config.participatingChannelIndices, segments=roofline.segments, allDeviceChannelIds)` |
| [neighborhood_sync_engine.dart:428](../../lib/features/neighborhood/neighborhood_sync_engine.dart#L428) | Sync `_executePattern` (every apply) | Same resolver call against the user's `NeighborhoodMember` |
| [neighborhood_sync_engine.dart:623](../../lib/features/neighborhood/neighborhood_sync_engine.dart#L623) | Sync teardown | `null` (clear to "no preference") |

**Resolver policy** — [`resolveParticipatingChannels`](../../lib/features/neighborhood/services/channel_participation_resolver.dart#L42-L71):
```dart
if (explicit != null) return explicit;          // 1. user picker wins verbatim
if (segments.isEmpty) {                          // 2. untraced install
  return List<int>.from(allDeviceChannelIds);    //    → all device channels
}
final tracedChannels = <int>{};
final primaryChannels = <int>{};
for (final seg in segments) {
  tracedChannels.add(seg.channelIndex);                       // 0-indexed
  if (seg.isPrimary) primaryChannels.add(seg.channelIndex);   // 0-indexed
}
final untracedDeviceChannels =
    allDeviceChannelIds.toSet().difference(tracedChannels);
final result = primaryChannels.union(untracedDeviceChannels).toList()..sort();
return result;
```
**The exclusion rule:** a channel with **at least one segment but NO `isPrimary` segment** is EXCLUDED. Untraced device channels (no segments at all) participate by default. This is "Lever 2, 2026-05-23" policy.

**No off-by-one in the resolver.** All compares use `seg.channelIndex` (0-indexed) against `allDeviceChannelIds` (0-indexed). The translation between roofline-channel-index and participation-key is **the identity function**.

---

## 4. First-works-then-degrades — the actual mechanism

**The flow that matches Tyler's symptom:**

1. **App boots.** Cache is COLD: `_participationCacheLoaded = false`, `participationCacheNotifier.value = null`.
2. **Dashboard renders.** `participatingChannelIdsProvider` calls
   [`peekCachedParticipatingChannels()`](../../lib/features/wled/zone_providers.dart#L121) — returns `null` (cache cold).
   → `effectiveChannelIdsProvider` sees `participating == null` →
   returns ALL device channels.
   → All chips render enabled.
3. **User taps a pattern.** Widget reads `effectiveChannelIdsProvider` = `[0, 1]` (both channels).
4. **Widget calls** `applyChannelFilter(payload, [0, 1], …)` →
   builds a multi-seg payload with seg ids 0 and 1.
5. **`applyJson` runs:**
   ```dart
   final participating = await getCachedParticipatingChannels();  // FIRST CALL — lazy-loads from prefs
   ```
   If a **stale** value was previously written (e.g. by a prior Game Day
   or Sync session whose teardown didn't fire / was skipped, or by a
   resolver result that excluded channel 2 due to roofline data), the
   load returns `[0]` (channel 2 excluded). The `ValueNotifier.value = …`
   assignment fires listeners → providers invalidate → **dashboard
   rebuild scheduled**.
6. **`expandForParticipation(normalized, [0])`** sees multi-seg payload
   → **Rule 4 passes through unchanged**
   ([wled_payload_utils.dart:219-220](../../lib/features/wled/wled_payload_utils.dart#L219-L220)):
   ```dart
   // Rule 4: already multi-seg → caller built it that way intentionally.
   if (seg.length > 1) return payload;
   ```
   → POST to WLED includes seg[0] AND seg[1] → **channel 2 LIGHTS UP**
   on the first command.
7. **Listener fires** from step 5 → `participatingChannelIdsProvider`
   invalidates → `effectiveChannelIdsProvider` recomputes:
   - `baseIds = [0, 1]` (all device channels, since no selector)
   - `participating = [0]` (now loaded from prefs)
   - `effective = [0, 1] ∩ [0] = [0]`
   → channel 2 chip greys out (its id=1 is no longer in
   `effectiveChannelIds`).
8. **User taps second pattern.** Widget reads
   `effectiveChannelIdsProvider` = `[0]` → builds payload with seg[0]
   ONLY. **Channel 2 not in payload, stays at whatever state.**

**Why "first works":** the dashboard's chip computation runs from
`peekCachedParticipatingChannels()` (synchronous, returns `null` cold) at
build time. The chokepoint's `await getCachedParticipatingChannels()`
DOES load the cache, but `expandForParticipation` then passes the
multi-seg payload through unchanged — so the cache value doesn't filter
this apply. **The race window is exactly one apply wide.**

**Why "channel 2 specifically":** there is no per-channel mechanism that
singles out channel 2. The stale prefs value happens to be whatever the
last resolver call computed. The most likely causes of channel 2 being
absent from that value:
- The roofline trace marked channel 2's segments with `isPrimary=false`
  (whether intentionally or by some upgrade-path default), OR
- The roofline-config Firestore document was authored when only channel 1
  had traced segments (channel 2 was added to hardware later, but no
  segments were traced for it on the roofline photo), OR
- A prior `GameDayAutopilotConfig.participatingChannelIndices` explicit
  list was set to `[0]` only.

**The "Sync teardown didn't clear the cache" precedent** is documented in
[neighborhood_sync_engine.dart:613-622](../../lib/features/neighborhood/neighborhood_sync_engine.dart#L613-L622):
> *"Sync's `_executePattern` writes the participation cache on every
> apply but nothing clears it on teardown, so the dashboard channel-
> selector chips stayed strike-through across sync sessions until app
> relaunch reloaded the cache from disk (which mirrored the same value).
> Clearing to null here restores the 'no preference = all channels'
> default…"*

Same shape as the current symptom. The Sync teardown fix added the
explicit clear; **no equivalent clear runs on app boot for Game Day
Autopilot or for a Sync session that ended abnormally** (force-quit, OS
kill, etc.).

---

## 5. Indexing convention summary

| Layer | Identifier | 0/1-indexed | Source of truth |
|---|---|---|---|
| Roofline config (storage) | `RooflineSegment.channelIndex: int` | **0-indexed** | `RooflineSegment` model, Firestore `channel_index` field |
| Roofline editor (display) | "Channel ${i + 1}", "CH${channelIndex + 1}" | **1-indexed** | UI sink only — does not feed back |
| Lumina `DeviceChannel` (the canonical map) | `id: int` (= bus position) | **0-indexed** | `deviceChannelsProvider` (derived from WLED `hw.led.ins[]`) |
| Lumina channel→GPIO expectation | `gpioPin: int` (read from bus.pin[0]) | **GPIO numbers verbatim** | Display only — not in mapping logic |
| Lumina channel→WLED segment id | `applyChannelFilter` sets `seg.id = ch.id` | **0-indexed identity** | `wled_payload_utils.dart:74` |
| WLED bus position (`hw.led.ins[]`) | Array index | **0-indexed** | WLED config writer + reader |
| WLED actual GPIO | `bus.pin[0]` | **GPIO numbers** | WLED hardware config |
| WLED segment id | Array index in `/json/state.seg[]` | **0-indexed** | WLED protocol |
| Participation cache key | `int` in `List<int>?` | **0-indexed** | `participationCacheNotifier`, SharedPreferences `_kLocalParticipatingChannelsKey` |
| Dashboard chip grey-out check | `participatingSet.contains(ch.id)` | **0-indexed identity** | `channel_selector_bar.dart:197` |

**No layer disagrees with its neighbor.** Every indexing transition is
the identity function on a 0-indexed integer. Display labels (1-indexed)
are sinks only.

---

## Most likely root cause + the ONE site to fix

**Root cause:** *Stale participation cache from a prior Game Day or Sync
session is lazy-loaded on the first `applyJson`, causing a one-cycle
race where (a) the first apply slips through `expandForParticipation`'s
Rule 4 multi-seg passthrough and lights channel 2, then (b) the
just-loaded cache value invalidates Riverpod providers, the dashboard
rebuilds with channel 2 greyed out, and subsequent applies use a
`effectiveChannelIds` that omits channel 2.*

The cache value itself excludes channel 2 because **a previous resolver
run** (Game Day Autopilot start or Neighborhood Sync apply at some point
in this user's history) computed and persisted a participation list that
didn't include channel 2 — most likely because:
- The roofline config for this install has channel-2 segments marked
  `isPrimary=false`, OR
- The roofline config has no traced segments for channel 2 (so it was
  "untraced" at the time, would be included now — but a prior resolver
  ran when channel 2 had at least one non-primary segment), OR
- An explicit `participatingChannelIndices` list was saved (Game Day
  config picker) that omits channel 2.

The bug is NOT an off-by-one in the channel-identity chain. The chain is
clean 0-indexed end-to-end.

**The ONE site to fix:**
[`getCachedParticipatingChannels`](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L334-L340)
— add a **device-channel reconciliation step** at lazy-load time. When
the cache is loaded from disk and the loaded list is non-null, verify
that every id in the list is still present in the current
`deviceChannels`. If not (the user added/changed/removed buses since
the cache was written), treat the cached value as stale and clear it
(set to null + remove the prefs key). This matches the spirit of the
Sync teardown's `restoreParticipation` clear, but generalizes it to
"any cached value that no longer matches the current device shape is
invalid."

**Why this site, not the writers:** Adding clears to every writer
(boot, app-resume, device-config-arrival) requires coordination across
five+ surfaces (game day, sync, dashboard init, app router, lifecycle
observer). Reconciling at the read side fixes every entry point in one
place — and is read-only with respect to legitimate user-explicit lists
(which always pass the device-channel check because the user picked
them against the current device).

**Reasoning:** the user's stale value was correct at the time it was
written but is wrong for the current install (Dig-Octa channel 2 is
now wired up and being used). The user's intent in the current
session is "all channels participate" (cache should be null) — and the
load-time reconciliation can detect this whenever the loaded list is
not a subset of the current device channels OR whenever the loaded
list excludes a device channel that has no roofline-traced segments
(i.e. the resolver would now include it as "untraced default in").

**Secondary recommendation (independent):** add a
`peekCachedParticipatingChannels()` warm-up at dashboard init so the
first-apply race window closes. The dashboard should not render chips
based on a "cache cold" `null` answer when the apply pipeline is about
to load a non-null value. Calling
`unawaited(getCachedParticipatingChannels())` once when the dashboard
mounts will make the chip state and the apply state agree from the
first frame.

---

*End of original audit. No code changes.*

---

# Addendum (2026-05-26) — Precise reconciliation rule

The first audit proposed read-side reconciliation at `getCachedParticipatingChannels`. Before implementing, we need to confirm the rule won't wipe a deliberately-deselected channel. This addendum traces the storage model end-to-end and produces the exact boolean.

## 1. How "participating" is stored vs defaulted

### Storage layer

There are **TWO** explicit-choice fields in Firestore, both nullable:

- [`GameDayAutopilotConfig.participatingChannelIndices`](../../lib/features/autopilot/game_day_autopilot_config.dart#L155-L161)
  ```dart
  /// Channel indices that participate in this team's Game Day show for
  /// the user's controller. `null` means "no explicit choice" — the
  /// default-participation policy in [resolveParticipatingChannels]
  /// applies. An empty list `[]` means the user explicitly opted out
  /// of all channels for this team. Read by the apply path, not stored
  /// verbatim.
  final List<int>? participatingChannelIndices;
  ```
- [`NeighborhoodMember.participatingChannelIndices`](../../lib/features/neighborhood/neighborhood_models.dart#L307-L312)
  ```dart
  /// Channel indices that participate in sync/Game Day shows for this
  /// member's controller. `null` means "no explicit choice" — the
  /// default-participation policy in [resolveParticipatingChannels]
  /// applies. An empty list `[]` means the user explicitly opted out
  /// of all channels. Read by the apply path, not stored verbatim.
  final List<int>? participatingChannelIndices;
  ```

Both have identical semantics: `null` = no explicit choice, `[]` = explicit opt-out of all, `[..]` = explicit allowlist. Both are read by the resolver as the `explicit` parameter ([game_day_autopilot_providers.dart:155](../../lib/features/autopilot/game_day_autopilot_providers.dart#L155), [neighborhood_sync_engine.dart:421](../../lib/features/neighborhood/neighborhood_sync_engine.dart#L421)).

### Default path (when `explicit == null`)

[`resolveParticipatingChannels`](../../lib/features/neighborhood/services/channel_participation_resolver.dart#L42-L71):
```dart
if (explicit != null) return explicit;          // (1) explicit wins verbatim
if (segments.isEmpty) {                         // (2) untraced install
  return List<int>.from(allDeviceChannelIds);   //     → all device channels
}
final tracedChannels = <int>{};
final primaryChannels = <int>{};
for (final seg in segments) {
  tracedChannels.add(seg.channelIndex);
  if (seg.isPrimary) primaryChannels.add(seg.channelIndex);
}
final untracedDeviceChannels =
    allDeviceChannelIds.toSet().difference(tracedChannels);
final result = primaryChannels.union(untracedDeviceChannels).toList()..sort();
return result;
```

Channel inclusion rules under the default policy:
- **Channel has ≥1 primary segment** → INCLUDED (via `primaryChannels`)
- **Channel has segment(s), NONE primary** → EXCLUDED (in `tracedChannels` but not `primaryChannels`, also not in `untracedDeviceChannels`)
- **Channel has NO segment at all** → INCLUDED (via `untracedDeviceChannels`)

### Write path to the cache

The resolved result (NOT the explicit field) is written to the SharedPreferences cache by [`saveLocalParticipatingChannels`](../../lib/features/neighborhood/services/sync_event_background_persistence.dart#L382-L400). The cache stores the resolver's OUTPUT, not the user's INPUT.

## 2. Can the code tell deliberate-deselection from stale-drop?

### Today: **YES**, by construction — but for an unexpected reason.

**No UI in `lib/` writes to either `participatingChannelIndices` field.** I grep'd every variant — `copyWith(participatingChannelIndices: …)`, `setParticipating…`, `saveParticipating…`, `updateParticipating…`, any picker class name. The fields exist, are serialized, are copyWith-able, and are read by the resolver. But **no widget calls a method that ever sets them to a non-null value.**

The only writers to the cache are:
- The resolver's output (game day + sync paths), with `explicit = null` every time (because no UI populates the explicit fields)
- `null` (sync teardown's `restoreParticipation`)

**Consequence:** every non-null cached value in `_kLocalParticipatingChannelsKey` is, by construction today, the resolver's default-policy output. It is NEVER the user's explicit list — because no user can produce one. **Any disagreement between the cached value and the current resolver output is therefore stale**, not a deselection preference.

### Tomorrow: **NO**, when pickers ship.

The fields exist for a reason. When a picker is added (game day config picker, neighborhood member picker), it'll write an explicit non-null list to Firestore, the resolver will return it verbatim, the cache will store it. **The cache has no provenance tag distinguishing "explicit user choice" from "default resolver output."** The fix needs an extension path for that day.

## 3. The exact reconciliation boolean

**Inputs available at the foreground load site:**
- `cachedSet: List<int>?` — value from `loadLocalParticipatingChannels()` (the disk read).
- `deviceChannels: List<DeviceChannel>` — current bus list from `deviceChannelsProvider`.
- `currentRoofline: RooflineConfig?` — current roofline from `currentRooflineConfigProvider`.

**Boolean (clear-when-true):**

```text
let cachedSet         = <loaded value from SharedPreferences>     // List<int>? — null means no preference
let deviceIds         = deviceChannels.map((c) => c.id).toList()  // 0-indexed bus positions
let segments          = currentRoofline?.segments ?? const []     // empty if no roofline traced

// Today there is no UI that sets an explicit list. When one ships, this
// must be passed into the resolver instead of null and the reconciliation
// rule will need a per-source comparison (per-team for game-day config,
// per-member for sync) rather than a single foreground check.
let currentExpected   = resolveParticipatingChannels(
                          explicit: null,
                          segments: segments,
                          allDeviceChannelIds: deviceIds,
                        )

let isStale = cachedSet != null
           && !setEquals(cachedSet.toSet(), currentExpected.toSet())
```

When `isStale == true` → call `saveLocalParticipatingChannels(null)` to clear the prefs key and reset the in-memory cache.

**Why this is safe today:**

- The resolver is deterministic over `(segments, deviceIds, isPrimary flags)`. Two foreground calls with the same inputs always return the same set.
- The cache can ONLY have been written by a resolver call (no UI alternative exists).
- Therefore: if the cache and the freshly-recomputed expected set disagree, **either**:
  - device shape changed (new/removed bus since the cache was written), **or**
  - roofline shape changed (segment added/removed/re-primaried since the cache was written), **or**
  - the cache was written by a prior session against state that no longer exists.
  All three reduce to "the cache value is no longer reachable through the current resolver and is therefore stale."

**What this DOESN'T touch:**

- A `null` cache (`cachedSet == null`) is left alone — nothing to reconcile.
- An empty cache (`cachedSet == []`) IS technically reconcilable, but the resolver under the default policy only returns `[]` when `deviceIds == []` (no buses) — a degenerate device state. Including the empty-set check in the rule covers it for free; excluding it just leaves the chokepoint's Rule 2 "explicit empty → pass through" intact, which is also harmless because the dashboard chips render `null → all enabled` style when participation is empty anyway. **Recommend including** for completeness.
- A cache value that EQUALS the current expected set is correct — leave alone. This is the steady-state common case (resolver wrote it, nothing has changed since).

**Extension path for when pickers ship:**

The `explicit: null` argument to the recompute is the lever. When a picker writes an explicit list, the reconciliation site needs to know WHICH source (which game day config or which sync member) owns the cache value. Options:

- **Add provenance to the cache.** Wrap the cached value as `{source: 'game_day:nfl_chiefs', value: [0,2]}` and compare against the matching source's `participatingChannelIndices` field. Most explicit, requires schema migration of the SharedPreferences key.
- **Reconcile against the most-recent writer's explicit field.** When the foreground loads the cache, also read the relevant Firestore doc (active game day config or active sync member) and pass its `participatingChannelIndices` as `explicit` to the recompute. Adds a Firestore round-trip to the load path.
- **Skip reconciliation if any picker has ever written a non-null value to either field.** A `bool _explicitListEverSet` flag in prefs. Reconciliation runs only when no explicit list is in play. Cheap, but a one-way door — once any user touches a picker, reconciliation is permanently disabled until reset.

Pick the schema option when the picker lands. **The immediate fix doesn't need to choose.**

## 4. Will this change behavior for any current install beyond fixing the bug?

**No.** Because no UI writes to either explicit field today, no install has a "deliberately deselected channel" state to protect. Every install's cached value is the resolver's default-policy output computed against the install's (segments, deviceIds, isPrimary) snapshot at the time of last write.

The reconciliation only flips behavior for installs whose **current** (segments, deviceIds, isPrimary) snapshot computes a DIFFERENT set than the cached snapshot. Those installs are by definition exhibiting the bug — the cache is wrong for the current device. Clearing to null restores the "no preference → resolver runs fresh on next apply" behavior, which is the correct state.

Installs whose snapshot hasn't changed (cache and recompute agree) see zero behavior change.

## Final precise rule

```text
ON FOREGROUND CACHE LOAD (one-shot, app boot or first applyJson):

  cachedSet ← loadLocalParticipatingChannels()
  IF cachedSet == null:                                    leave alone, done
  
  deviceIds ← deviceChannelsProvider.read().map(.id).toList()
  segments  ← currentRooflineConfigProvider.read()?.segments ?? []
  expected  ← resolveParticipatingChannels(
                explicit:           null,
                segments:           segments,
                allDeviceChannelIds: deviceIds,
              )

  IF cachedSet.toSet() ≠ expected.toSet():
    saveLocalParticipatingChannels(null)                   ← clear stale
  ELSE:
    leave alone (cache matches what the resolver would write today)
```

**Race-free condition:** the recompute requires `deviceChannels` and `currentRooflineConfig` to be loaded. If either is still loading, defer the reconciliation until both are ready (a one-time `Future.wait` or a `ref.listen` chain on first non-null values from both providers). Do NOT run reconciliation against a null/empty deviceChannels — that would wrongly clear caches on cold boot before `/json/cfg` returns.

When picker UIs ship, the recompute's `explicit:` argument must be sourced from the writer-of-record for the cache (game day config or sync member). The current rule is correct until that point because explicit is provably null for all current writes.

---

*End of addendum. No code changes.*

---

# Addendum 2 (2026-05-26) — Roofline editor surface relationship

Read-only audit. Read by request to determine the relationship between the
"Roofline Trace" editor (reached via Profile Setup, owner-accessible) and
the "Edit Layout" / "Setup Wizard" surface (reached via My Lights → Roofline
Setup, framed as installer-gated), and whether their relationship contributes
to the channel-2 mapping bug analyzed above.

> **Bottom line up front**
>
> 1. "Edit Layout" (My Lights) and "Trace Roofline" / "Edit" (Profile Setup)
>    push to the **same** screen — `RooflineEditorScreen` — and **neither is
>    installer-gated**. The mental model that "Edit Layout requires installer"
>    is **incorrect**.
> 2. "Setup Wizard" is a **different** screen (`RooflineSetupWizard`) and
>    **is** the only installer-gated surface.
> 3. **The Wizard hard-codes every segment to `channelIndex = 0`** by omitting
>    the field on construction. It collects channel/LED-count input at Step 2
>    but never threads it onto segments at Step 3 save. This is a
>    distinct candidate for the channel-2 bug class, separate from the
>    stale-cache mechanism in §4 of the original audit.
> 4. Both surfaces write the same Firestore document
>    (`users/{uid}/roofline_config/config`), so a later edit in either path
>    fully overwrites the other. The Editor *also* writes a legacy
>    `rooflineMask` field on the user profile; the Wizard does not.
>    Divergent dual-write.

## A2.1 Entry points & routing

Two screens, three buttons.

### Surface A — `RooflineEditorScreen` (un-gated)
File: [lib/features/site/roofline_editor_screen.dart](../../lib/features/site/roofline_editor_screen.dart)
Route: `AppRoutes.rooflineEditor` → `/settings/roofline-editor`
Registered: [lib/app_router.dart:340-344](../../lib/app_router.dart#L340-L344), constant at [lib/app_router.dart:1164](../../lib/app_router.dart#L1164).

**Three buttons push this route, all unconditionally:**

1. Profile Setup → "Trace Roofline" in the photo-source bottom sheet
   [lib/widgets/house_photo_uploader.dart:235](../../lib/widgets/house_photo_uploader.dart#L235):
   ```dart
   _OptionTile(
     icon: Icons.edit_location_alt_outlined,
     label: 'Trace Roofline',
     subtitle: 'Draw where your lights are installed',
     onTap: () {
       Navigator.pop(ctx);
       context.push(AppRoutes.rooflineEditor);
     },
   ),
   ```

2. Profile Setup → roofline status row "Trace/Edit" button
   [lib/widgets/house_photo_uploader.dart:496](../../lib/widgets/house_photo_uploader.dart#L496):
   ```dart
   TextButton(
     onPressed: () => context.push(AppRoutes.rooflineEditor),
     child: Text(hasRoofline ? 'Edit' : 'Trace'),
   ),
   ```

3. My Lights → Roofline Setup card → "Edit Layout"
   [lib/features/site/system_management_screen.dart:387](../../lib/features/site/system_management_screen.dart#L387):
   ```dart
   OutlinedButton.icon(
     onPressed: () => context.push(AppRoutes.rooflineEditor),
     icon: const Icon(Icons.edit),
     label: const Text('Edit Layout'),
   ),
   ```

### Surface B — `RooflineSetupWizard` (installer-gated)
File: [lib/features/design/roofline_setup_wizard.dart](../../lib/features/design/roofline_setup_wizard.dart)
Route: `AppRoutes.rooflineSetupWizard` → `/roofline-setup-wizard`
Registered: [lib/app_router.dart:351-356](../../lib/app_router.dart#L351-L356), constant at [lib/app_router.dart:1166](../../lib/app_router.dart#L1166).

**One button pushes this route:**

- My Lights → Roofline Setup card → "Setup Wizard"
  [lib/features/site/system_management_screen.dart:379](../../lib/features/site/system_management_screen.dart#L379):
  ```dart
  FilledButton.icon(
    onPressed: () => context.push(AppRoutes.rooflineSetupWizard),
    icon: const Icon(Icons.auto_fix_high, color: Colors.black),
    label: const Text('Setup Wizard'),
  ),
  ```

### Are "Setup Wizard" and "Edit Layout" the same screen?

**No.** Sister buttons in the same card on the My Lights screen route to
**two different screens**: "Setup Wizard" → `RooflineSetupWizard`, "Edit
Layout" → `RooflineEditorScreen`. The framing-time assumption that both
"require installer profile" is wrong — only the Wizard is gated.

## A2.2 Widget sharing — how much overlap

| Surface | Top-level screen | Editor primitive used |
|---|---|---|
| Profile-Setup "Trace Roofline" | `RooflineEditorScreen` | `RooflineEditor` widget (canvas) |
| My-Lights "Edit Layout" | `RooflineEditorScreen` (**same**) | `RooflineEditor` widget (canvas) |
| My-Lights "Setup Wizard" | `RooflineSetupWizard` | `PageView` of 5 step forms, **no canvas** |

**`RooflineEditor` (the canvas widget at
[lib/widgets/roofline_editor.dart:31](../../lib/widgets/roofline_editor.dart#L31)) instantiation sites:**
- [lib/features/site/roofline_editor_screen.dart:120](../../lib/features/site/roofline_editor_screen.dart#L120) — the only screen.

**`RooflineSetupWizard` body**:
- [lib/features/design/roofline_setup_wizard.dart:255-265](../../lib/features/design/roofline_setup_wizard.dart#L255-L265) — five-step `PageView` with bespoke form widgets per step. Does not import or instantiate `RooflineEditor`.

**Classification:** **(c) independent implementations that merely look related.**
The Editor screen and the Wizard share no UI primitives. They share only the
Firestore destination and the `RooflineConfiguration` / `RooflineSegment`
model types.

## A2.3 CRITICAL — channel/segment assignment per path

The two paths disagree on how `channelIndex` is set on segments. This section
quotes the assignment sites verbatim and identifies a load-bearing bug in the
Wizard.

### Path A — `RooflineEditorScreen`: explicit per-segment channel selection

A "+ segment" dialog prompts label, channel, story level. Channel comes from
a dropdown sized by `_totalChannelCount`:

[lib/features/site/roofline_editor_screen.dart:361-513](../../lib/features/site/roofline_editor_screen.dart#L361-L513) (channel dropdown excerpt):
```dart
DropdownButtonFormField<int>(
  initialValue: channelIndex,
  ...
  items: [
    for (int i = 0; i < _totalChannelCount; i++)
      DropdownMenuItem(
        value: i,
        child: Row(children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: kChannelColors[i % kChannelColors.length],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('Channel ${i + 1}'),
        ]),
      ),
    // ... "Add Channel" option
  ],
  ...
),
```

The chosen index flows into `RooflineEditor.startNewSegment(...)`:

[lib/features/site/roofline_editor_screen.dart:494-498](../../lib/features/site/roofline_editor_screen.dart#L494-L498):
```dart
_editorKey.currentState?.startNewSegment(
  label: label.isEmpty ? 'Segment ${_currentSegments.length + 1}' : label,
  channelIndex: channelIndex,
  storyLevel: storyLevel,
);
```

…and ultimately into the persisted segment:

[lib/features/site/roofline_editor_screen.dart:611-620](../../lib/features/site/roofline_editor_screen.dart#L611-L620):
```dart
for (final seg in segments) {
  configEditor.addSegment(
    name: seg.name,
    pixelCount: seg.pixelCount > 0 ? seg.pixelCount : 30,
    channelIndex: seg.channelIndex,   // ← per-segment, from dropdown
    level: seg.level,
    points: seg.points,
    isConnectedToPrevious: seg.isConnectedToPrevious,
  );
}
```

**Outcome:** Editor segments carry whatever channel index the user picks in
the dropdown. The mechanism is sound.

### Path B — `RooflineSetupWizard`: every segment defaults to channel 0

The wizard collects channel info at **Step 2** (LED Info) into class-level
state:

[lib/features/design/roofline_setup_wizard.dart:37-39](../../lib/features/design/roofline_setup_wizard.dart#L37-L39):
```dart
Set<int> _selectedChannels = {1};      // Channels 1-8, at least one selected
int _totalLedCount = 200;              // Total LEDs combined (1-2600)
Map<int, int> _channelLedCounts = {};  // LED count per channel
```

At **Step 3** (Segments) the user adds segments with name, LED count, type,
location, prominence, level. **There is no channel field on a segment in
this flow.**

The save flow:

[lib/features/design/roofline_setup_wizard.dart:86-114](../../lib/features/design/roofline_setup_wizard.dart#L86-L114):
```dart
for (int i = 0; i < _segments.length; i++) {
  final draft = _segments[i];

  ArchitecturalRole? aiRole;
  if (draft.segmentType == InstallerSegmentType.peak) {
    aiRole = ArchitecturalRole.peak;
  } else if (draft.segmentType == InstallerSegmentType.corner) {
    aiRole = ArchitecturalRole.corner;
  }

  segments.add(RooflineSegment(
    id: _uuid.v4(),
    name: draft.name,
    pixelCount: draft.ledCount,
    startPixel: currentStart,
    type: draft.type,
    direction: draft.direction,
    anchorPixels: draft.anchorIndices,
    anchorLedCount: 2,
    sortOrder: i,
    architecturalRole: aiRole,
    location: draft.location.storageName,
    isProminent: draft.isProminent,
    isConnectedToPrevious: draft.isConnectedToPrevious,
    level: draft.level,
    // ← NO channelIndex argument
  ));
  currentStart += draft.ledCount;
}
```

`channelIndex` is **not specified**, so the constructor default applies:

[lib/models/roofline_segment.dart:568](../../lib/models/roofline_segment.dart#L568):
```dart
const RooflineSegment({
  ...
  this.channelIndex = 0,   // ← default; the wizard always hits this
  this.overrideColor,
});
```

The wizard also never sets `totalChannelCount` on its `RooflineConfiguration`
(see [lib/features/design/roofline_setup_wizard.dart:119-125](../../lib/features/design/roofline_setup_wizard.dart#L119-L125)), so the config's default applies for that field too.

### Divergence summary

| Aspect | Editor (Path A) | Wizard (Path B) |
|---|---|---|
| Channel selection UI | Per-segment dropdown | Per-installation checkboxes (Step 2), never applied to segments |
| `channelIndex` written | User-chosen | Hard-coded `0` for every segment |
| `totalChannelCount` written | `configEditor.setTotalChannelCount(_totalChannelCount)` ([roofline_editor_screen.dart:623](../../lib/features/site/roofline_editor_screen.dart#L623)) | Not set; `RooflineConfiguration` default applies |
| Legacy `rooflineMask` on user profile | Updated ([roofline_editor_screen.dart:587-594](../../lib/features/site/roofline_editor_screen.dart#L587-L594)) | Not touched |

**Quote — the smoking gun:** the wizard's segment construction at
[roofline_setup_wizard.dart:97-112](../../lib/features/design/roofline_setup_wizard.dart#L97-L112) omits `channelIndex:` entirely; combined with the model default at
[roofline_segment.dart:568](../../lib/models/roofline_segment.dart#L568), all wizard-authored segments collapse onto channel 0.

## A2.4 Permission gate

### Editor (`RooflineEditorScreen`) — no gate
Grep for `installerMode|isInstaller|installer_profile|installerProfile` in
[lib/features/site/roofline_editor_screen.dart](../../lib/features/site/roofline_editor_screen.dart) returns no matches. The screen is reachable by any signed-in user via Profile Setup or My Lights.

### Wizard (`RooflineSetupWizard`) — installer-only
[lib/features/design/roofline_setup_wizard.dart:172-238](../../lib/features/design/roofline_setup_wizard.dart#L172-L238):
```dart
@override
Widget build(BuildContext context) {
  // Check if installer mode is active - this wizard is installer-only
  final isInstallerMode = ref.watch(installerModeActiveProvider);

  if (!isInstallerMode) {
    return Scaffold(
      appBar: GlassAppBar(title: const Text('Roofline Setup'), ...),
      body: Center(
        ...
        Text('Installer Access Required', ...),
        Text(
          'The Roofline Setup Wizard is only available to certified installers. '
          'This ensures your LED system is configured correctly for optimal '
          'performance.',
          ...
        ),
        ...
      ),
    );
  }
  // ...wizard body...
}
```

Gate is via `installerModeActiveProvider` from
[lib/features/installer/installer_providers.dart](../../lib/features/installer/installer_providers.dart).

### What an owner (non-installer) can change

The Editor is un-gated, so an owner can independently do all of the
following, with no installer in the loop:

| Operation | Profile-Setup Trace | My-Lights Edit Layout | Setup Wizard (installer) |
|---|---|---|---|
| Add segment | ✓ | ✓ | ✓ |
| Assign per-segment channel via dropdown | ✓ | ✓ | ✗ (no per-segment channel UI) |
| Remove segment | ✓ | ✓ | ✓ |
| Reorder segments | ✓ | ✓ | ✓ (form drag) |
| Retrace points on photo | ✓ | ✓ | ✗ (no canvas) |
| Change segment's `channelIndex` | ✓ | ✓ | ✗ (locked to 0) |
| Change `totalChannelCount` | ✓ | ✓ | ✗ (never written; defaults) |
| Select active installation channels (1–8) | ✗ | ✗ | ✓ (Step 2 — collected, not persisted onto segments) |
| Set architectural role (peak/corner/etc.) | ✗ | ✗ | ✓ |

**Intentional capability split or inconsistency?** This reads as an
**inconsistency**, not a deliberate role split:
1. The Wizard's "Installer Access Required" copy implies the Wizard owns
   channel hardware mapping — but the Wizard is the path that hard-codes
   channel 0.
2. The owner-accessible Editor is the **more powerful** surface: it can
   change every field the Wizard can change, plus `channelIndex` and
   `totalChannelCount`. A gating model designed for "installer holds the
   keys" would be inverted from this layout.
3. Two un-gated entry points reach the Editor under two different framings
   ("Trace Roofline" in onboarding vs. "Edit Layout" in system management),
   suggesting the gating was simply never considered for the Editor — the
   gate was added to the Wizard recently and not propagated.

## A2.5 Data model — one layout or divergent writes

### Single Firestore record
Both paths write to the same document:
`users/{uid}/roofline_config/config` — single, replaceable
`RooflineConfiguration` per user. Resolved at
[lib/features/design/roofline_config_providers.dart:21-26](../../lib/features/design/roofline_config_providers.dart#L21-L26).

### Wizard writes only the new doc
[lib/features/design/roofline_setup_wizard.dart:127-138](../../lib/features/design/roofline_setup_wizard.dart#L127-L138):
```dart
final userId = ref.read(authStateProvider).maybeWhen(
  data: (user) => user?.uid,
  orElse: () => null,
);
if (userId == null) { throw Exception('User not logged in'); }
final service = ref.read(rooflineConfigServiceProvider);
await service.saveConfiguration(userId, config);
```

### Editor dual-writes: new doc AND legacy mask
[lib/features/site/roofline_editor_screen.dart:587-624](../../lib/features/site/roofline_editor_screen.dart#L587-L624):
```dart
// 1. Save the legacy RooflineMask for backward compatibility
final mask = editorState.getMask();
final userService = ref.read(userServiceProvider);
final updatedProfile = profile.copyWith(
  rooflineMask: mask.toJson(),
  updatedAt: DateTime.now(),
);
await userService.updateUser(updatedProfile);

// 2. Save the multi-segment RooflineConfiguration
final configEditor = ref.read(rooflineConfigEditorProvider.notifier);
await configEditor.initialize();

// ... add each traced segment ...

configEditor.setPhotoPath(imageUrl);
configEditor.setTotalChannelCount(_totalChannelCount);
await configEditor.save();
```

The Editor maintains a legacy `rooflineMask` field on `users/{uid}` for
backward-compatible callers; the Wizard does not. After a Wizard save, the
legacy mask is whatever it was before — possibly stale, possibly empty,
possibly the previous Editor's mask. Any code path still reading the legacy
field will silently see divergent state from the new config doc.

### Cross-path consistency

**Scenario 1 — Wizard, then Editor:**
1. Installer runs Wizard. Step 2: selects channels {1, 2, 3}. Step 3:
   defines 5 segments. Save:
   - Firestore: 5 segments, all `channelIndex=0`. `totalChannelCount`
     defaults (per `RooflineConfiguration` default). Legacy mask untouched.
2. Owner opens Profile-Setup → "Edit" or My-Lights → "Edit Layout".
   - Editor loads `_totalChannelCount` from the existing config (default —
     likely 1, given the wizard never wrote it).
   - The channel dropdown is now sized to whatever was persisted, not the
     {1,2,3} the installer selected in Step 2. Owner sees one channel
     option (or however many `_totalChannelCount` is hydrated to).
3. Owner re-saves: every segment is rewritten with the owner's choices,
   and the legacy mask is populated for the first time.

**Scenario 2 — Editor, then Wizard:**
1. Owner traces in Editor, assigns channels carefully (say, `[0, 1]`).
2. Installer reruns Wizard "to fix it up."
3. Wizard replaces the document. All channelIndex values collapse to 0.
   Legacy mask still holds the owner's prior trace, now divergent from
   `roofline_config/config`.

**Channel assignments do not survive consistently across path order.**
Either sequence yields data loss along some axis.

## A2.6 Verdict

### Are these surfaces safe to keep as-is?
**No.** Three concrete reasons:

1. **The Wizard's hard-coded `channelIndex = 0`** is almost certainly a
   bug — it writes data that the rest of the app expects to be
   channel-aware, and is the *primary installer-facing setup path* for
   the data field involved in the channel-2 bug.
2. **Asymmetric gating, inverted from the framing.** The wizard
   ("Installer Access Required") is the *less* powerful surface; the
   un-gated Editor is the *more* powerful one. Either the gate is in
   the wrong place or the feature split is wrong.
3. **Editor's legacy dual-write is not matched by the Wizard.** The two
   paths produce two distinct "saved" states — new + legacy versus new
   only. Any code that still reads `rooflineMask` silently sees stale
   data after a Wizard save.

### Should they be unified?

**Yes (propose).** Two viable shapes:

- **Recommended — single editor screen, with a wizard-style guided mode for
  first-time setup.** The Wizard's strengths (architectural role tagging,
  channel/LED Step-2 collection, location metadata) become a header /
  setup panel above the existing `RooflineEditor` canvas. One persistence
  path, one channel-assignment mechanism, one place to gate.

- **Minimal-change alternative — keep two screens but fix the Wizard.**
  At Step 3, require channel assignment per segment, derived from Step
  2's `_selectedChannels`. Set `totalChannelCount` on the saved config.
  Write the legacy mask the same way the Editor does. This is a smaller
  diff but leaves the gating inconsistency unresolved.

### Does this relationship contribute to the channel-2 bug?

**Yes — directly, in one concrete way; suggestively in others.** This is
a **distinct mechanism** from the stale-cache race documented in §4 of
the original audit — both can produce "channel 2 misbehaves" symptoms,
and either or both may be active on any given install.

**Direct contribution (this addendum's mechanism):** Any user who set
up via the Setup Wizard has a `roofline_config/config` document where
every segment claims `channelIndex = 0`. Downstream consumers of
`RooflineSegment.channelIndex` — the resolver's
`tracedChannels.add(seg.channelIndex)` and
`primaryChannels.add(seg.channelIndex)` at
[channel_participation_resolver.dart:42-71](../../lib/features/neighborhood/services/channel_participation_resolver.dart#L42-L71)
— will treat channel 2 as **untraced** (no segment claims it) and
therefore include it via the "untraced default in" rule **only if the
device's `deviceChannels` list contains id=1**. Whether channel 2
participates then depends entirely on whether the WLED device exposes
two buses; the Wizard didn't and couldn't influence this.

For an install where the Wizard authored the roofline and channel 1
also has segments marked `isPrimary=true`, the resolver returns
`{0} ∪ {untraced device channels}`. If the device has two buses, that
resolves to `{0, 1}` — channel 2 included. **So far the bug is masked.**

But if the user later opens the Editor (which IS un-gated and accessible
without installer credentials) and assigns one or more segments to
channel 1 (i.e. channelIndex=1) **without marking them isPrimary**, the
resolver flips: channel 1 now has segment(s), none primary, so it gets
EXCLUDED. **Channel 2 drops off the participating list** at the next
write to the participation cache. That stale value then drives the
chip greyout via the §4 mechanism.

**Cross-mechanism interaction:** the Wizard's bug (channelIndex=0 for all)
creates the *initial wrong state*; the un-gated Editor lets the owner
*shift to a more dangerous* wrong state; the participation cache (§4)
*persists* that wrong state across sessions even after the underlying
config is fixed. The three together explain the "channel 2 drops, then
sticks dropped" pattern more completely than the stale-cache mechanism
alone.

**Suggestive contribution:** the two-paths-one-document setup means the
observed channel mapping depends on which path last wrote. A bug report
that channel 2 misbehaves on one device but not another is consistent
with one user having gone through Wizard-only, another through Editor,
and a third through Wizard → Editor in sequence.

**What I would verify next** (out of scope for this read-only audit):
1. Open Firestore for a known-affected account and inspect
   `users/{uid}/roofline_config/config.segments[*].channel_index` —
   if all zeros, that account went through the Wizard and was never
   re-edited.
2. Inspect the same document for `segments[*].is_primary` distribution
   across channels — channel 1 segments with `is_primary=false` are the
   trigger condition described above.
3. Check whether `kChannelColors` and channel-selector UIs in the Editor
   size their channel list from `totalChannelCount` (defaulting to 1) —
   if so, Wizard-authored configs render as "single-channel installs"
   in the Editor even when the installer selected 8 channels.

**Bug-fix sequencing recommendation (propose only, no code changes):**

1. **Fix the Wizard's channel assignment first** (smallest, highest-yield
   diff). Either (a) add a per-segment channel dropdown to Step 3 sized
   to `_selectedChannels`, or (b) round-robin / first-fit assign segments
   to `_selectedChannels` based on cumulative LED counts hitting
   `_channelLedCounts[ch]`. Also write `totalChannelCount` on save.
2. **Then implement the read-side cache reconciliation** from Addendum 1.
   With (1) in place, the reconciliation's `currentExpected` recompute
   becomes truthful (segments actually carry the right channel
   indices), and stale caches will be cleared correctly on foreground
   load.
3. **Then resolve the gating inconsistency** — propose locking the
   un-gated Editor's channel-assignment dropdown behind installer mode
   (the canvas and per-segment add/remove can stay open for owners), or
   unifying the two screens entirely.

---

*End of Addendum 2. No code changes.*
