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
| full suite | ✅ **2441 / 4 / 0** (2435 + 6) |
| `flutter analyze` on changed files | ✅ clean |
| L→R control routed to `applyGeometryJson` | ❌ **OPEN — §3** |
| celebration revert / schedule-sync replay under test | ❌ **OWED — §2** |
| bench re-verify: `rev` survives a celebration cycle on +81 | ❌ **OWED — hardware** |
