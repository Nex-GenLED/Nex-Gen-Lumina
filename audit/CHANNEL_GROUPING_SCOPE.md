# CHANNEL GROUPING — SCOPE

**Status:** scope only. Nothing implemented, no branches created.
**Repo:** `main` @ `393af46`, `2.5.10+58`.
**Date:** 2026-07-30.
**Field finding being addressed:** verified live across two households — Neighborhood Sync fanout works, but there is no way to express that several physical channels form one visual surface. A 2-channel façade renders an effect twice against a 1-channel neighbor's once. **MISSING capability, not a bug.**
**Decided going in:** grouping, arbitrary N channels per group. Per-channel exclusion is not the primary fix.

---

## 1. Q1 — SYNC OR INSTALLATION?

### Answer: **INSTALLATION.** A multi-channel surface abstraction already exists there — it is just not a *partition*, and sync cannot see the parts of it that matter.

### 1.1 What already exists

The installation layer already carries an ordered, gap-aware, multi-channel geometry model. It is `RooflineConfiguration` + `RooflineSegment`, sliced per channel as `PixelMapChannel`.

| Capability | Where it lives | Evidence |
|---|---|---|
| Ordered sequence across channels | `RooflineConfiguration.segments`, concatenated in channel order then per-channel `sortOrder` | [pixel_map_channel.dart:196-241](lib/models/pixel_map_channel.dart#L196-L241) (`aggregatePixelMapChannelsToConfig`) |
| Which channel a piece of geometry is on | `RooflineSegment.channelIndex` | [roofline_segment.dart](lib/models/roofline_segment.dart) field list, "Maps to hardware bus index" |
| Per-segment direction | `RooflineSegment.direction` (`SegmentDirection`) | [roofline_segment.dart:58-76](lib/models/roofline_segment.dart#L58-L76) |
| **Discontinuity / gap** | `RooflineSegment.isConnectedToPrevious` — *"there's a discontinuity (jump to second story, detached area, etc.)"* | [roofline_segment.dart](lib/models/roofline_segment.dart) field list |
| Per-channel pixel count, device-truth | `PixelMapChannel.sourcePixelCount` (`WledLedBus.len` at map time) + staleness | [pixel_map_channel.dart:28-33](lib/models/pixel_map_channel.dart#L28-L33), [:74-76](lib/models/pixel_map_channel.dart#L74-L76) |
| Per-channel LED range in global index space | `DeviceChannel.start` / `.stop` derived from `hw.led.ins[]` | [device_channel.dart:33-47](lib/features/wled/device_channel.dart#L33-L47) |
| Split / aggregate between per-channel and whole-home | `splitConfigToPixelMapChannels` / `aggregatePixelMapChannelsToConfig` | [pixel_map_channel.dart:160-241](lib/models/pixel_map_channel.dart#L160-L241) |

**`isConnectedToPrevious` is very close to the thing being asked for.** A contiguous run of segments where it is `true`, spanning channels, *is* one visual surface. The concept is already modelled; it is simply not exposed as a first-class group and not honoured at channel seams.

### 1.2 What sync sees instead

Sync collapses all of the above to a **flat, unordered `List<int>` of channel indices**:

```dart
// lib/features/neighborhood/services/channel_participation_resolver.dart:43-71
List<int> resolveParticipatingChannels({
  required List<int>? explicit,
  required List<RooflineSegment> segments,
  required List<int> allDeviceChannelIds,
})
```

No order, no direction, no adjacency, no grouping. It reads `segments` only to ask "does this channel have an `isPrimary` segment" ([:55-59](lib/features/neighborhood/services/channel_participation_resolver.dart#L55-L59)) — it discards every structural field on the way past.

### 1.3 The exact mechanism of the reported field finding

That flat list is handed to `applyChannelFilter`, which **emits one WLED segment per channel, each carrying the same effect template**:

```dart
// lib/features/wled/wled_payload_utils.dart
final expandedSegs = channelIds.map((id) {
  final s = <String, dynamic>{'id': id, ...template, 'on': true};
  for (final ch in channels) {
    if (ch.id == id) { s['start'] = ch.start; s['stop'] = ch.stop; break; }
  }
  return s;
}).toList();
```

WLED runs each segment's effect **independently and from its own origin**. Two channels → two segments → the effect renders twice. **That is the doubled façade, exactly as reported.** It is not a sync defect; it is the absence of any way to say "these two segments are one surface."

The same function is the apply path for **Game Day** ([game_day_apply.dart:89](lib/features/game_day/game_day_apply.dart#L89)), the **dashboard** ([wled_dashboard_page.dart:1192,1270](lib/features/dashboard/wled_dashboard_page.dart#L1192)), the **channel selector bar** ([channel_selector_bar.dart:284](lib/features/dashboard/widgets/channel_selector_bar.dart#L284)), and the **autopilot background worker** ([game_day_autopilot_background_worker.dart:484](lib/features/autopilot/game_day_autopilot_background_worker.dart#L484)). **Every one of them doubles the façade today.** Sync is where it was noticed because sync is where a neighbour provides the contrast.

### 1.4 Therefore: scope this as adding a partition to the installation model

Not "wiring sync to consume an existing abstraction" — the abstraction is a *whole-home aggregate*, not a set of named surfaces, and three things are missing from it:

1. **No partition.** `RooflineConfiguration` is the entire home. Nothing expresses "channels 1+2 are the front façade; channel 3 is the detached garage."
2. **Gap flag is unreliable at channel seams.** `aggregatePixelMapChannelsToConfig` concatenates channels in index order ([pixel_map_channel.dart:213-216](lib/models/pixel_map_channel.dart#L213-L216)) **without setting `isConnectedToPrevious` at the join** — the flag at a seam is whatever the last segment happened to carry. And the installer pixel-walk hardcodes `isConnectedToPrevious: true` on everything it emits ([roofline_capture_logic.dart:113,127,141](lib/features/installer/map_roofline/roofline_capture_logic.dart#L113)), so installer-authored maps carry no gap information at all. Only the customer-facing setup wizard actually captures it ([roofline_setup_wizard.dart:2041,2356](lib/features/design/roofline_setup_wizard.dart#L2041)).
3. **No per-channel wiring direction** — see §2.2, where the answer is more interesting than "missing".

### 1.5 What else would consume it

This is the argument for installation-side, stated concretely. Every one of these already goes through `applyChannelFilter` or the pixel map:

| Consumer | Why it needs grouping |
|---|---|
| **Design Studio** — manual editor, smart presets, per-pixel write spine | A painted design across a 2-channel façade has the same double-origin problem. [design_apply.dart](lib/features/design/manual_editor/design_apply.dart), [smart_preset_apply.dart](lib/features/design/smart_presets/smart_preset_apply.dart) |
| **Game Day** | Same `applyChannelFilter` path, same doubling — [game_day_apply.dart:89](lib/features/game_day/game_day_apply.dart#L89) |
| **Scheduling** | Schedule pattern presets are captured from live state and re-saved; a doubled façade is baked into the stored preset |
| **Dashboard + channel selector** | Per-channel power (P1-43) and channel chips would present a group as one control |
| **Autopilot background worker** | Applies without a UI; inherits whatever the model says |
| **Neighborhood Sync** | The reporting consumer, not the owning one |

### 1.6 Drift cost of a sync-local implementation — asked for explicitly

If the group lives in sync (on the crew member doc, or a sync-local config), you create **a second source of truth about physical topology**. Concretely, not abstractly:

1. **No staleness machinery.** `PixelMapChannel` carries `mapVersion`, `isStale`, and `isStaleAgainst(liveCount)` ([pixel_map_channel.dart:35-45](lib/models/pixel_map_channel.dart#L35-L45), [:74-76](lib/models/pixel_map_channel.dart#L74-L76)) so a remap or a bus-length change is detectable. A sync-local group inherits none of it. Re-run the pixel walk, change a channel's LED count, and the sync group silently describes a topology that no longer exists — with no signal anywhere.
2. **Divergent behaviour on the same house.** Game Day, Design Studio, dashboard and scheduling would keep rendering the façade doubled while sync rendered it correctly. Same physical wall, two behaviours, depending on which feature is driving. That is worse than the current uniform bug because it is unreproducible on demand.
3. **Contradiction with `isConnectedToPrevious`.** The installation model would still assert its own view of surface continuity. Two models, no arbitration rule, and the pixel-map one is the one Design Studio trusts.
4. **Migration debt is duplicated.** Any future change to channel topology (adding a bus, re-commissioning) needs a migration in two places, and only one of them has a version field to migrate on.
5. **It is not cheaper.** The apply-site change (§3, G3) is required either way — that is where the doubling actually happens. Sync-local placement saves only the model work, and spends it back on a bespoke staleness mechanism.

**Recommendation: installation-side, as an extension of the pixel map. Do not put it in sync.**

---

## 2. THE MODEL

A group is not a list of channels. Scoping each required property against what exists.

### 2.1 (a) Ordered channel sequence — **NEW, small**

Needs an ordered `List<int>`, not a set. Note `resolveParticipatingChannels` already sorts ascending in the default policy but preserves caller order for explicit lists ([channel_participation_resolver.dart:40-42](lib/features/neighborhood/services/channel_participation_resolver.dart#L40-L42)) — so the "order is meaningful" idea has a precedent, it is just not carried anywhere.

**Proposed shape** (illustrative, not prescriptive):

```
ChannelGroup {
  id            : String
  name          : String          // "Front Façade"
  members       : List<GroupMember>   // ORDERED
  gapPolicy     : traverse | skip     // §2.3
}
GroupMember {
  channelIndex  : int
  reversed      : bool            // §2.2
}
```

### 2.2 (b) Per-channel direction — **ALREADY CAPTURED AS DEVICE TRUTH, BUT DROPPED IN THE APP**

**This is the most useful finding in the scope and it makes (b) far cheaper than modelling a new concept.**

WLED buses natively carry a reverse flag, and Lumina **already parses it**:

```dart
// lib/features/wled/wled_hardware_config.dart:14, :41
final bool rev; // reversed?
...
rev: m['rev'] == true,
```

It is also treated as precious across every write path — three separate places explicitly preserve it rather than clobber it:

- [wled_config_pusher.dart:299](lib/services/wled_config_pusher.dart#L299) — `'rev': existing?.rev ?? false, // PRESERVE manual bus direction (625226f)`, with a comment at [:246](lib/services/wled_config_pusher.dart#L246) that hardcoding `rev:false` "silently undid an installer's" setting
- [hardware_config_screen.dart:40](lib/features/wled/hardware_config_screen.dart#L40) — same preservation
- [design_models.dart:249-251](lib/features/design/design_models.dart#L249-L251) — preserves the controller's current `seg.rev` on design apply

**But it is dropped at the bus→channel boundary.** `deviceChannelsFromConfig` builds `DeviceChannel` from each bus and **does not carry `rev`** ([device_channel.dart:11-24](lib/features/wled/device_channel.dart#L11-L24) — the class has `id`, `name`, `start`, `stop`, `gpioPin` and nothing else). So `applyChannelFilter`, sync, Game Day, Design Studio and the pixel map are all structurally blind to a field the device already knows.

**Consequence for scope: (b) is plumbing an existing field, not inventing one.**

**Two caveats that must be surfaced, not assumed away:**

1. **`SegmentDirection` is NOT this, and must not be conflated with it.** `SegmentDirection` is per-*segment* semantic/visual direction — `upward`/`downward` along a gable slope, `towardStreet`, `clockwise`. The pixel-walk sets it only for peak geometry ([roofline_capture_logic.dart:111,137](lib/features/installer/map_roofline/roofline_capture_logic.dart#L111)). It cannot express "channel 2's pixel 0 is physically at the far end and counts back toward the controller." Orthogonal concepts, similar names — a live confusion risk for whoever implements this.
2. **Data quality is unknown.** `rev` is only correct if the installer actually set it in WLED at commissioning. The code preserves it carefully but nothing verifies it, and nothing surfaces it. **If installers have not been setting it, the field is present but meaningless** — see Q-D in §7. This is a field question, not a code question, and it determines whether G2 is sufficient or whether direction must also be *captured* (G6).

### 2.3 (c) Gaps — **PARTIALLY MODELLED; POLICY IS MISSING**

`isConnectedToPrevious` records *whether* a discontinuity exists. It does **not** record what an effect should do about it. Those are different questions and only the first is answered.

What the model needs to add:

- **A per-boundary policy: traverse or skip.** A chase crossing a garage door should usually *traverse* (the pixels do not exist but the visual line continues, so the effect should advance through the gap in time without lighting anything). A chase reaching a detached garage should usually *skip* (jump straight to the next real pixel). Today neither is expressible.
- **A gap magnitude for traverse.** To traverse you must know how much apparent distance to cross — a 4-foot door and a 30-foot driveway are not the same delay. Nothing in the model carries physical distance. `RooflineSegment.points` (normalised 0.0-1.0 photo coordinates) is the closest available proxy and only exists for photo-traced segments.

**Two population gaps compound this:**
- The installer pixel-walk hardcodes `isConnectedToPrevious: true` ([roofline_capture_logic.dart:113,127,141](lib/features/installer/map_roofline/roofline_capture_logic.dart#L113)) — installer-authored maps assert full continuity regardless of reality.
- `aggregatePixelMapChannelsToConfig` does not set the flag at channel seams ([pixel_map_channel.dart:213-216](lib/models/pixel_map_channel.dart#L213-L216)) — the very boundary this feature is about.

**Recommendation: ship gap *policy* as a later phase.** Grouping without gap policy is already a large improvement (the façade stops doubling). Gap policy without distance data is guesswork. See §5 phasing.

### 2.4 (d) Differing pixel counts — **ALREADY AVAILABLE, NO MODEL WORK**

Two independent sources, both present:
- `PixelMapChannel.sourcePixelCount` — device truth at map time, with staleness detection ([pixel_map_channel.dart:28-33](lib/models/pixel_map_channel.dart#L28-L33))
- `DeviceChannel.start`/`.stop` — live global LED range ([device_channel.dart:41-45](lib/features/wled/device_channel.dart#L41-L45))

No new model needed. Consumed by G3 and by normalization (§4).

### 2.5 ⚠️ Hard constraint the design must confront: contiguity

`DeviceChannel.start`/`.stop` are **global** LED indices — bus 0 might be 0-119, bus 1 120-199. The clean fix for doubling is to emit **one WLED segment spanning the group** (`start = min`, `stop = max`) so the effect has a single origin across the whole surface.

**That only works if the group's channels are contiguous in global index space.** A group of channels 1+3 would, as a single segment, necessarily include channel 2's pixels.

Three options, and this is a genuine design decision rather than an implementation detail:

| Option | Cost | Trade |
|---|---|---|
| **Restrict groups to contiguous channels** | Cheapest | Physically reasonable — installers wire adjacent runs to adjacent ports — but it is a real constraint on the customer, and it will be violated eventually |
| Re-order buses at commissioning so group members are adjacent | Free in software | Requires a `/json/cfg` bus rewrite and a re-map; touches the LED-count/`rev` config the pusher guards carefully |
| Allow non-contiguous groups, emit multiple segments with computed phase offsets | Most flexible | Requires knowing each effect's spatial period to compute an offset. **Not generally solvable** — WLED effect internals vary per effect. Would work for chases, not for all 187 effects |

**Recommendation: restrict to contiguous for v1**, validate at authoring time, and surface a clear message rather than silently producing a wrong grouping. Revisit only if the field demands it.

---

## 3. SCOPED ITEMS — GROUPING

| ID | Item | Files touched | Data-model change | UI surface | Est | Confidence |
|---|---|---|---|---|---|---|
| **G1** | `ChannelGroup` model + persistence | new `lib/models/channel_group.dart`; [pixel_map_channel.dart](lib/models/pixel_map_channel.dart) split/aggregate; [roofline_config_providers.dart](lib/features/design/roofline_config_providers.dart) | **Yes** — new group list on the pixel-map aggregate; new Firestore field or sibling doc under `/users/{uid}/controllers/{ctrl}/` | None | **8h** | Medium |
| **G2** | Carry `rev` through bus→channel derivation | [device_channel.dart](lib/features/wled/device_channel.dart) (+ `zone_providers.dart` re-export) | `DeviceChannel` gains `reversed` | None | **2h** | **High** — pure plumbing of an already-parsed field |
| **G3** | **Group-aware apply — the actual fix** | [wled_payload_utils.dart](lib/features/wled/wled_payload_utils.dart) `applyChannelFilter`, + all 5 call sites (§1.3) | None | None | **8h** | Medium |
| **G4** | Direction-aware apply (honour `reversed` per member) | [wled_payload_utils.dart](lib/features/wled/wled_payload_utils.dart) | None (consumes G1+G2) | None | **4h** | Medium — depends on Q-D |
| **G5** | Gap policy — traverse vs skip | `channel_group.dart`, apply path, [roofline_segment.dart](lib/models/roofline_segment.dart) | **Yes** — per-boundary policy + magnitude | Authoring toggle | **6h** | **Low** — no distance data exists (§2.3) |
| **G6** | Grouping authoring UI in the pixel-walk wizard | [map_roofline_step.dart](lib/features/installer/screens/map_roofline_step.dart), [roofline_capture_logic.dart](lib/features/installer/map_roofline/roofline_capture_logic.dart) | None | **Installer wizard step** | **8h** | Medium |
| **G7** | Migration + backfill | migration helper; [roofline_config_providers.dart](lib/features/design/roofline_config_providers.dart) | Read-path defaults | None | **4h** | Medium |
| **G0** | *Optional bootstrap:* infer default groups from existing `isConnectedToPrevious` runs | inference helper + G1 | None beyond G1 | None | **4h** | Low-Medium |

**Grouping subtotal (G1+G2+G3+G4+G7): 26h.** With G5 and G6: **40h.**

### G0 — the zero-UI bootstrap, worth considering

Because `isConnectedToPrevious` already encodes surface continuity, a **default grouping can be inferred** with no installer input: walk the aggregated segment list, start a new group wherever the flag is `false`, and treat channel seams per Q-B below. Every existing customer would get plausible grouping without anyone touching a wizard.

**Caveat that makes this Low-Medium and not High:** installer-authored maps hardcode the flag to `true` (§2.3), so inference on those produces *one group spanning every channel* — which is right for a continuous façade and wrong for a detached garage. Useful as a default that the customer or installer can correct; **not** trustworthy as the only mechanism.

---

## 4. PROPORTIONAL NORMALIZATION — SEPARATE AND INDEPENDENTLY SHIPPABLE

### 4.1 Current state: pixel-based, not proportional

Sync carries raw WLED effect parameters:

```dart
// lib/features/neighborhood/neighborhood_models.dart:666-667, 690-696
final int speed;
final int intensity;
...
final int pal;
final int grp;
final int spc;
```

`speed` is a WLED 0-255 effect parameter governing per-frame advance. For the great majority of WLED effects it is **not** normalised to segment length, so traversal time scales with pixel count. **A 120px façade and a 200px façade at identical `speed` are out of phase, and drift further every cycle.** This is true today, ungrouped — and grouping makes it *more* visible, because a correctly-grouped 200px surface now traverses as one long run rather than two short ones.

### 4.2 Two available levers

1. **Scale `speed` at apply time** by the ratio of this home's participating pixel count to a reference length. Cheap; accuracy varies per effect because the speed→velocity curve is effect-specific.
2. **Use `grp` / `spc`** — already carried through the sync payload ([neighborhood_models.dart:694-696](lib/features/neighborhood/neighborhood_models.dart#L694-L696)). WLED's `grp` repeats each logical pixel N times, scaling the effect's spatial period directly. More faithful than speed-scaling but **integer-only**, so it quantises badly at small ratios.

**Note the naming collision:** WLED's `grp` is *pixel* grouping (repeat each pixel N times). It is unrelated to channel grouping. Anyone reading the sync payload will meet the word "grouping" meaning the other thing.

### 4.3 Scope

| ID | Item | Files touched | Data-model change | UI surface | Est | Confidence |
|---|---|---|---|---|---|---|
| **N1** | Proportional effect normalization | [neighborhood_models.dart](lib/features/neighborhood/neighborhood_models.dart) (apply-time transform), sync apply path, [wled_payload_utils.dart](lib/features/wled/wled_payload_utils.dart) | None — apply-time only, no persisted change | Optional debug readout | **6h** | **Low-Medium** |

**Confidence is Low-Medium and the reason matters:** the correct normalization curve is empirical. WLED's speed parameter does not map linearly to pixels-per-second, and the mapping differs by effect. This needs bench measurement across a representative effect set before the constant is trustworthy. **Budget bench time, not just code time.**

**Independently shippable: YES.** N1 requires none of G1-G7. It improves phase alignment between *any* two homes of differing length, grouped or not — including the two households in the field finding. **It is arguably the faster win of the two workstreams**, and it can ship while grouping is still being designed.

---

## 5. ALSO DETERMINED

### 5.1 Who sets grouping — **RECOMMEND: INSTALLER, during commissioning**

**Reasoning is about who holds the physical knowledge**, not about who is more technical.

Grouping is a statement about **wiring and architecture**: which runs are one continuous façade, which channel is reversed because it was wired back toward the controller, where the run genuinely breaks. The installer is the only person who was physically present when those decisions were made. By the time a customer opens the app, the wire is in a soffit.

Three supporting reasons:

1. **The pixel-walk wizard is already the place where this knowledge is captured.** The installer walks the run channel by channel, lighting a cursor pixel and marking features ([map_roofline_step.dart](lib/features/installer/screens/map_roofline_step.dart)). Grouping is one more question asked while they are still standing in the driveway looking at the house.
2. **The direction field is an installer artefact already.** `rev` is set in WLED at commissioning and the codebase treats overwriting it as a bug ([wled_config_pusher.dart:246,299](lib/services/wled_config_pusher.dart#L246)). Grouping belongs with it.
3. **The customer cannot verify the answer.** A customer told "is channel 2 reversed?" has no way to know. An installer can toggle it and watch the strip.

**But provide a customer-side override.** Two reasons: installer-authored maps currently assert `isConnectedToPrevious: true` unconditionally (§2.3), so early groupings will be imperfect; and houses change — a customer adds a detached pergola on channel 3. **Recommendation: installer authors, customer can correct, in Settings, with the pixel map's existing staleness UI as the precedent.** The customer-facing setup wizard already asks the analogous continuity question ([roofline_setup_wizard.dart:2041](lib/features/design/roofline_setup_wizard.dart#L2041)), so the interaction pattern exists.

### 5.2 Does the fanout write path assume channel parity? — **NO**

Checked directly: **`functions/src/applySyncPattern.ts` contains zero channel references.** The server-side fanout is channel-agnostic — it carries an effect payload (`effectId`, `colors`, `speed`, `intensity`, `pal`/`grp`/`spc`) and per-member assignments, and every channel decision happens client-side at the apply site.

**This is good news and it constrains the design favourably:**
- Grouping needs **no Cloud Function change and no wire-protocol change.**
- Two homes with different channel counts already interoperate; nothing assumes parity.
- It also means **each home resolves its own grouping locally** — a 2-channel home and a 1-channel home need no shared vocabulary, only correct local rendering.

**One adjacent thing that is not parity but is worth flagging:** `SyncPatternAssignment` carries per-member `effectId`/`colors`/`speed`/`intensity` ([neighborhood_models.dart:708](lib/features/neighborhood/neighborhood_models.dart#L708)). That per-member channel is where a normalized speed (§4) would naturally be delivered if you later chose to normalize server-side rather than at apply time. Not needed for v1; noted so it is not rediscovered.

### 5.3 Migration impact

| Surface | Impact | Handling |
|---|---|---|
| **Existing sync groups** (`/neighborhoods/*`) | **None.** Grouping is installation-side; crew membership and fanout are untouched. No neighbourhood document changes shape | No migration |
| **Existing pixel maps** (`/users/{uid}/controllers/{c}/pixelMap/{ch}`) | **Additive.** Groups are new state; absent groups must read as "every channel is its own group", which is exactly today's behaviour | Read-path default. `PixelMapChannel.fromJson` already defaults every field ([pixel_map_channel.dart:114-140](lib/models/pixel_map_channel.dart#L114-L140)) — same pattern |
| **`RooflineConfiguration` consumers (~12)** | **None if groups live beside the aggregate rather than inside `segments`.** The split/aggregate pair exists precisely to keep these untouched ([pixel_map_channel.dart:12-15](lib/models/pixel_map_channel.dart#L12-L15)) — preserve that property | Design constraint, not a migration |
| **`mapVersion`** | Should bump when groups are first written, so staleness/regeneration detection stays meaningful | Part of G1 |
| **Untraced installs** | Users with a controller but no pixel map get no groups. `resolveParticipatingChannels` already handles them ([:52-54](lib/features/neighborhood/services/channel_participation_resolver.dart#L52-L54)) by including all channels — behaviour must remain identical | Verify in G3 |
| **Firestore rules** | `pixelMap` is explicitly hardened, owner-read + staff-write ([firestore.rules:412-419](firestore.rules#L412-L419)). **A sibling group doc under the same controller path needs its own rule** — and the surrounding comment bans the broad `request.auth != null` pattern for new rules. Mirror the `pixelMap` shape exactly | ~1h, folded into G1. **Coordinate with the P0-1 rules work in `audit/LAUNCH_PLAN.md`** — do not land a new rule mid-tightening |

**No destructive migration. No backfill required for correctness** — G0 inference (§3) is an optional convenience, not a prerequisite.

---

## 6. SHIPPABLE INDEPENDENTLY vs MUST LAND TOGETHER

### Must land together — the minimum coherent unit

**G1 + G3 (+ G7).** A model with no consumer changes nothing; a group-aware apply with no model has nothing to read. **26h** including G2 and G4. This is the smallest change that stops the façade doubling.

### Independently shippable

| Item | Ships alone? | Note |
|---|---|---|
| **N1 — proportional normalization** | **Yes, fully** | Zero dependency on grouping. Improves phase between any two differing-length homes today. Consider shipping first |
| **G2 — carry `rev` through `DeviceChannel`** | **Yes** | Inert until consumed; pure additive plumbing. Safe to land early and de-risks G4 |
| **G0 — inferred default groups** | Only with G1 | Optional convenience |
| **G5 — gap policy** | Only after G1 | Deliberately deferred — no distance data (§2.3) |
| **G6 — installer authoring UI** | Only after G1 | Deferrable if G0 inference gives an acceptable default |

### Suggested phasing

| Phase | Contents | Est | Outcome |
|---|---|---|---|
| **0** | N1 + G2 | **8h** | Homes of differing length come into phase. `rev` becomes visible to the app. Both independently useful, neither needs the model |
| **1** | G1 + G3 + G7 (+ G0) | **20-24h** | **The façade stops doubling.** Groups exist, apply honours them, existing users migrate silently |
| **2** | G4 + G6 | **12h** | Direction honoured; installers author groups explicitly instead of relying on inference |
| **3** | G5 | **6h** | Gap traverse/skip — only worth doing once there is field evidence about which behaviour customers actually want |

**Total across all phases: ~46h.** Phase 0 and Phase 1 together (**~32h**) resolve the reported field finding.

**Note on timing relative to launch:** none of this is in `audit/LAUNCH_PLAN.md` and none of it should be. It is a new capability, not a defect, and Phase 1 touches `applyChannelFilter` — a function on the apply path of five features including Game Day and the dashboard. **That is not a change to make between now and submission.** The iOS engineering path has slack against the Play window (`LAUNCH_PLAN.md` §5), but slack is not an invitation to add scope to a release candidate.

---

## 7. OPEN QUESTIONS

**Q-D — Do installers actually set `rev` in WLED during commissioning?** *(highest impact on scope)*
The field is parsed and carefully preserved, but nothing verifies or surfaces it. **If it is reliably set, G2+G4 (6h) gives correct direction almost free. If it is not, direction must be *captured* — and G6 grows** to include a per-channel direction step in the pixel walk (probably +4h, and a slower walk for the installer). Answerable by reading `/json/cfg` on a few commissioned controllers and comparing `rev` against physical reality.

**Q-B — What should `isConnectedToPrevious` be at a channel seam?** Today `aggregatePixelMapChannelsToConfig` does not set it ([pixel_map_channel.dart:213-216](lib/models/pixel_map_channel.dart#L213-L216)). For grouping, a seam inside a group is *connected* and a seam between groups is *not* — so the flag arguably becomes derived from group membership rather than stored. **Decide before G1**, because it determines whether groups are authored alongside the flag or replace it.

**Q-C — Contiguity: accept the restriction, or design for non-adjacent groups?** (§2.5) Recommend accepting it for v1. Confirm no real install already has a non-contiguous surface — if one does, the recommendation changes.

**Q-N — What is the reference length for normalization?** (§4) Longest home in the crew, a fixed constant, or the initiator's length? Affects whether normalization is computed per-home locally or distributed with the pattern. Recommend local-per-home against a fixed reference, so no protocol change is needed.

**Q-G — Traverse or skip: which do customers actually want at a garage door?** (§2.3) I would not guess this. It is the reason G5 is Phase 3 — worth one conversation with the two households in the field finding before building either behaviour.

**Q-S — Does the doubling reproduce in Game Day and Design Studio as predicted?** §1.3 says it must, since they share `applyChannelFilter`, but it was reported only from sync. **Confirming it on the bench costs minutes and would validate the whole Q1 analysis** — if Game Day does *not* double on a 2-channel controller, something in my read of the apply path is wrong and this scope needs revisiting before any of it is built.
