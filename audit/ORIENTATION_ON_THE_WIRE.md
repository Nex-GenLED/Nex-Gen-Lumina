# ORIENTATION ON THE WIRE — `rev` was never fenced

**Opened 2026-08-18 from the overnight bench session. `rev` was cleared on the
bench's seg 1 TWICE in one evening, on +80, with the geometry wire pin live.**

---

## 1. The pin passed `rev`. That is the whole gap.

```dart
const List<String> kGeometryKeys = ['start', 'stop'];   // rev, mi never inspected
```

The writer did **not** route around the fence. `findGeometryViolations` and
`stripGeometry` both iterate `kGeometryKeys`, and the list held only the two
bound keys — so a payload carrying `rev:false` walked through **both** fenced
exits untouched, was never reported, and was never stripped. **No third exit
exists and none needed hunting.**

`start`/`stop` say *where* a segment is. `rev`/`mi` say *which way it runs*.
Both describe how a segment maps onto physical hardware, which is provisioning's
to state and an apply's to leave alone — the rule #76 already settled for
bounds:

> #76 — `rev` no longer written at all. Omitting-when-false was a partial fix;
> the rule is that a design payload never asserts geometry, in either direction.
> — `design_models.dart:252`

That rule was enforced in **one builder** and never in **the fence**.

**FIXED:** `kGeometryKeys = ['start', 'stop', 'rev', 'mi']`. `mi` is included
before it costs an evening too; nothing in `lib/` writes it today.

### `rev` is echoed innocently — and that is not an exemption

`len` is deliberately excluded from the key list because WLED reports it in
every `/json/state` readback, so echoes would trip constantly while stating
nothing. **`rev` is also in every readback** — but unlike `len` it *does* move
the hardware, so it stays fenced. A restore must not re-assert direction either.
A debug assert firing on such a path is the pin reporting a real violation.

**Pinned by 6 tests** (`geometry_wire_pin_test.dart` → *"orientation is geometry
too"*), including the evening's exact payload `{'id':1,'rev':false}`, the
mirrored `rev:true` case, the combined violation string, and two guards against
over-fencing (a pure look payload stays untouched; `len` stays exempt).

---

## 2. The unattended writer: the celebration revert

**`WledCelebrationDelivery` — `foreground_celebration_providers.dart:60`.**

```dart
Future<Map<String, dynamic>?> capture() async => repo.getState();  // FULL /json/state
...
final restore = {
  if (captured['on']  != null) 'on':  captured['on'],
  if (captured['bri'] != null) 'bri': captured['bri'],
  if (captured['seg'] != null) 'seg': captured['seg'],   // ← replayed VERBATIM
};
await repo.applyJson(restore);
```

`getState()` returns every segment with `start`, `stop`, `rev`, `len`, `mi`.
The revert replays that array **unmodified**, so it re-stamps whatever `rev` held
at capture time. `rev` was already `false` when the coordinator first captured,
so every celebration cycle re-asserted `rev:false` — including over a manual
restore, ~2 minutes later, twice.

Every observation is accounted for:

| observed | cause |
|---|---|
| no user action, app foregrounded | `_pollTimer`, `foreground_celebration_coordinator.dart:174` |
| Chiefs red/gold exactly | `team_color_database.dart:322` — `0xFFE31837` = (227,24,55), `0xFFFFB81C` = (255,184,28) |
| BOTH segments written, differing fx | `play()` expands each step via `applyChannelFilter` across all device channels |
| `rev` cleared, twice | the **revert**, not the flash |
| `ps: -1` | the seg-restore branch, not the preset branch |
| gate `write_jobs:false` did not stop it | correct — this path is **entirely client-side** |
| manual applies tested clean | they are; no manual path replays a snapshot |

**The item-1 fix closes this.** `rev`/`mi` now strip at the wire, so the revert
restores the LOOK without re-asserting ORIENTATION.

**`smart_pattern.dart:87` is NOT the culprit.** It unconditionally emits
`rev` + `grp` + `spc`, which is a real instance of the #76/#88 class — but
`.toJson()` has **zero call sites** in `autopilot/`, `sports_alerts/` or
`game_day/`. Automation never reaches it. It is a latent MANUAL-path emitter;
worth fixing, not tonight's cause.

**Second instance of the identical capture-replay shape:**
`schedule_sync.dart:1279` — `if (capturedLiveState['seg'] != null) 'seg':
capturedLiveState['seg']`. Same exposure, now equally fenced.

### The reason a live pin missed a live leak

The full suite went **2441 / 4 / 0 with ZERO `GEOMETRY ON THE WIRE` assertions**
after widening the fence. That is not reassurance — **no test exercises the
celebration revert or the schedule-sync capture-replay at all.** The leak
survived a pin that was working, because nothing drove the paths that leak.
Coverage of the two replay sites is owed.

---

## 3. OPEN DECISION — the L→R control is now a silent no-op

Three callers write `rev` through the pinned door:

| caller | what it is | effect of the fix |
|---|---|---|
| `pattern_adjustment_panel.dart:267` | debounced apply sends `{sx, ix, rev}` on **every speed/intensity drag** | ✅ correct — an incidental clobber, a slider re-asserting direction from local state |
| `pattern_grid_widgets.dart:2264` | the explicit **L→R / R→L** SegmentedButton | ❌ **silently stripped** — deliberate user intent |
| `smart_pattern.dart:87` | unconditional `rev`+`grp`+`spc` | ✅ correct — the #76/#88 class |

`_applyChange` routes through `repo.applyJson` — the pinned door. `applyGeometryJson`
is the provisioning door and already exists (healer, schedule sync, lease
manager, sunrise-off use it).

**By the pin's own doctrine the L→R control belongs on `applyGeometryJson`** —
it is a legitimate geometry writer. Not done here: it is a behaviour change to
an interactive control and wants a deliberate call, not a drive-by. **Until it
is routed, reversing a channel from the pattern grid does nothing.**

---

## 4. FILED — heal trigger gap (for +81, same region as #102)

**Confirmed on the bench:** the connect-time heal does **not** fire when the
app's connection survives a controller reboot. A foregrounded app saw collapsed
geometry **indefinitely**; a cold launch healed it within seconds.

The missed case is the **most common real outage** — a blip shorter than the app
session. The trigger is connect, and no connect occurs.

**Fix shape:** a second trigger on reboot detection — uptime regression, or a
shape change observed on any state read. Same code region as #102.

---

## 5. Verification

| check | status |
|---|---|
| 6 new pin tests, incl. the exact payload | ✅ green |
| full suite | ✅ **2449 / 4 / 0** (2441 + 8 — §7) |
| `flutter analyze` on changed files | ✅ clean |
| L→R control routed to `applyGeometryJson` | ❌ **OPEN — §3** |
| celebration revert / schedule-sync replay under test | ✅ **CLOSED — §6 / §7** |
| bench re-verify: `rev` survives a celebration cycle on +81 | ❌ **OWED — hardware** |

---

## 6. CAPTURE-REPLAY IS A NAMED CLASS — the full census

§2 found the celebration revert and, next to it, `schedule_sync.dart:1279`. Two
instances of one shape is not a coincidence, so the shape gets a name and a
census, the same way #76/#88/#89/#95 forced the emitter census that produced the
wire pin.

**CAPTURE-REPLAY: a stored `/json/state` snapshot, trusted at use-time.** The
third sibling of **stored-intent** (a design/preset built once and fired later)
and **stored-addresses** (a controller list held past the point it was true).
All three fail the same way: something was correct when it was written down, and
is asserted as still-correct when it is played back. Capture-replay is the
worst-behaved of the three because the thing written down is *the controller's
own readback* — which necessarily carries every field the controller reports,
including the ones the app has no business restating.

**Method:** `grep getState() lib/`, then read each call site for whether the
snapshot is replayed through `applyJson`. Not a walk of the sites already known
— that is the census method #88 recorded as insufficient.

### Identical shape — full `seg[]` replayed verbatim

| # | capture → replay | durability of the snapshot | notes |
|---|---|---|---|
| 1 | `foreground_celebration_providers.dart:43` → `:74` | in-memory, one celebration cycle | **THE incident writer.** Covered by `celebration_revert_capture_replay_test.dart` |
| 2 | `schedule_sync.dart:892` → `:1279` | in-memory, one sync | Covered by `schedule_sync_capture_replay_test.dart` |
| 3 | `alert_trigger_service.dart:183` → `:206` (`_restoreZoneState`) | in-memory, one animation | **NEW.** Near-verbatim the same code as #1, `ps` short-circuit included. The header of `foreground_celebration_providers.dart` calls this "the dead direct-IP AlertTriggerService path" — dead-ness is the only thing keeping it quiet, and dead-ness is not a fence |
| 4 | `sports_alert_service.dart:222` (`_basePayload`) → `:233` | in-memory, one alert | **NEW.** The widest of them all: replays the **entire** `getState()` map, not even field-picked to on/bri/seg |
| 5 | `autopilot_scheduler.dart:123` → `releaseOverride` | in-memory, one override window | **NEW.** Routes via `applyPayloadWithLabel` → `applyJson`, so it is fenced, but the extra hop means a `grep applyJson` census misses it |
| 6 | `pre_sync_scene_snapshot.dart:155` → `sync_teardown_resolver.dart:245` | **SharedPreferences — survives app restart, days** | **NEW.** Neighborhood Sync's pre-sync scene. The staleness window is bounded by `kPreSyncSceneMaxStaleness`, which bounds *how wrong the look is*, not *how wrong the geometry is* |
| 7 | `scene_providers.dart:248` (`captureSnapshotProvider`) → `Scene.toWledPayload()` → `applySceneProvider` | **Firestore — permanent, cross-device** | **NEW.** A snapshot Scene stores the readback `seg[]` under `wled_payload`. Geometry captured on one controller can be replayed onto another, months later |

**Nothing here is fenced site-by-side, and nothing needs to be.** All seven exit
through `applyJson`, and `applyJson` is the pin. That is the whole argument for
putting the fence at the wire instead of in the builders: this census found five
new sites and **changed no production code**, because they were already covered
the day they were written. A builder-side census would have owed five patches.

**Fenced ≠ clean, though.** Sites 6 and 7 write geometry into *durable storage*
(SharedPreferences, Firestore), so the bad data outlives the session that made
it. The wire pin means it can never reach hardware — but on a debug build the
pin *asserts*, so a snapshot scene captured today is a latent debug-build crash
whenever it is applied. **FILED, not fixed here:** #7 in particular should strip
geometry at *capture* time, so Firestore never holds a bound. That is a data
change with a migration question attached and wants its own call.

### Same class, already safe by construction — field-selective replay

| site | why it is safe |
|---|---|
| `refine_roofline_screen.dart:84` → `:118` | Rebuilds the seg from an **allowlist** — `id`/`on`/`fx`/`col`/`i` only. Geometry is never copied out of the snapshot |
| `map_roofline_step.dart:81` → `:113` | Same allowlist shape, plus `sx`/`ix` |

**This is the shape the seven should converge on.** An allowlist replay states
the look and nothing else, and it is correct with the fence *removed* — it does
not depend on a downstream strip to be right. Worth noting that the two sites
that got this right are the two written by someone staring at segment boundaries
at the time.

### Not in the class

| site | why |
|---|---|
| `schedule_enforcement.dart:136` | Reads the snapshot to **compare** (power/bri/fx drift). No replay |
| `controller_defaults_healer.dart`, `sunrise_off_service.dart`, `calendar_entry_lease_manager.dart` | Read via `segmentShapeFromState` and re-provision through `applyGeometryJson` — the provisioning door. Geometry is the **point** there, and it is derived from the controller's own buses, not from a snapshot |
| `site_providers.dart:214`, `current_colors_provider.dart:84`, `zone_providers.dart:79`, `wled_providers.dart` polls | Read-only state for UI |

---

## 7. Coverage — the zero-assertions gap, closed

§2 recorded the reason a live pin missed a live leak: the suite was
`2441 / 4 / 0` with **zero** geometry assertions on either replay site, because
no test drove either path. Two files close it.

| file | site | tests |
|---|---|---|
| `test/features/wled/celebration_revert_capture_replay_test.dart` | `WledCelebrationDelivery` capture→revert | 4 |
| `test/features/schedule/schedule_sync_capture_replay_test.dart` | `ScheduleSyncService` live-state restore | 4 |

**Suite: 2449 / 4 / 0** (2441 + 8). `flutter analyze` clean on both files.

Each file asserts the same three things, and all three are needed:

- **A — the tap point (pre-strip).** The raw payload the site hands `applyJson`
  *does* carry geometry. Without this, "the wire is geometry-free" would pass
  just as happily against a payload that never had geometry in it. Asserted with
  raw `containsKey`, deliberately **not** `findGeometryViolations` — the tap
  point must not depend on the fence it is testing, or a narrowed `kGeometryKeys`
  fails at A and masks the regression at B.
- **B — the wire (post-strip).** `stripGeometry` is the production release-path
  function, so what it emits is what the controller receives. `start`/`stop`/
  `rev`/`mi` gone; `id`/`on`/`col`/`fx`/`pal`/`sx`/`ix` intact; `len` still
  exempt, so over-fencing is caught too.
- **C — the real exit.** Driven against an un-stubbed `WledService.applyJson`,
  so the payload takes `normalizeWledPayload` → `expandForParticipation` →
  `_postJson` → `pinNoGeometryOnWire`, the real chain, and trips the debug
  assert. B is therefore not a bench-side simulation of the wire; it *is* the
  wire.

Both files use the evening's exact payload (`rev: false` on seg 1) and the
mirrored `rev: true` case — a genuinely reversed channel, where re-stamping the
snapshot is the more damaging direction.

### Proven able to fail

Same standard as every pin this week. With `kGeometryKeys` temporarily reverted
to its pre-`a356b5f` value `['start', 'stop']`:

**6 of the 8 fail.** Every geometry-bearing assertion, on both sites — B reports
`rev: false` still on the wire, C reports the pin enumerating only
`seg[n]:start+stop`. The 2 that stay green are the negative controls (the
celebration `ps >= 0` preset branch, and the no-preset-written no-restore case),
which carry no geometry and correctly do not care. Re-greened to 8/8 by
restoring `['start', 'stop', 'rev', 'mi']`.

**One real assertion bug was caught by doing this**, and it is worth recording
because it is the exact failure mode the exercise exists to find. C originally
matched `contains('rev')` on the violation report — which **passed under the
reverted fence**, because the report's static prose reads *"Bounds AND
orientation (start/stop/rev/mi) are provisioning's"* regardless of what the
fence actually caught. The assertion was matching the pin's boilerplate, not its
finding. It now matches the enumerated keys
(`seg[1](id=1):start+stop+rev+mi`). A test that asserts on an error message must
assert on the part of it that varies.

### Two things the tests had to work around, both worth knowing

- **The schedule-sync fixture's bounds are the simulator's bus layout
  (0–100 / 100–200), not the bench's 0–291 / 291–441.** `syncAll` runs the #76
  layer-4 geometry gate before every psave; a readback that disagrees with the
  controller's *own* buses is drift, the gate refuses the batch,
  `didWriteAnyPreset` stays false, and the restore at `:1274` never arms. A
  bench-literal bounds pair makes the file assert nothing at all. The value
  under test is `rev`, which the gate does not look at.
- **On a debug build, the schedule-sync restore is FATAL, not degraded.**
  Nothing between `syncAll`'s restore call and the pin catches, so the
  `AssertionError` propagates straight out of `syncAll`. Release strips and
  proceeds as designed; debug dies mid-sync. That is the pin working as
  specified, recorded here so it is not diagnosed as a sync bug.
