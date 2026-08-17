# BUILD LEDGER — shipped artifact identity

One row per build that leaves this machine. **Purpose: given a crash report, a
TestFlight build, or a Play release, recover exactly which commit shipped.**

**Why this file exists:** the iOS and Android build numbers **do not match**.
`codemagic.yaml` overwrites pubspec's build number with Codemagic's own
`PROJECT_BUILD_NUMBER` counter before building the IPA:

```yaml
BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}
sed -i '' "s/^version: .*/version: ${VERSION_NAME}+${BUILD_NUM}/" pubspec.yaml
```

Only the version *name* (`2.5.10`) comes from pubspec on iOS. Android takes both
name and code from pubspec. So **the git SHA is the only identifier common to
both platforms** — it is the join key, and it is why this ledger is not
optional.

## Operational flags

### #76 SEVERITY CAP — CLOSED AND WIRED, 2026-08-14

| # | Layer | Where | Status |
|---|---|---|---|
| 1 | builders no longer emit geometry | seven payload builders | `70726ac` |
| 2 | ladder path never asserts it | `_fullStripOnSegments` | pre-existing, verified |
| 3 | rig configured to catch the class | bench, two segments | restored 2026-08-14 |
| 4 | **gate refuses a drifted save** | `gatedPresetSave` chokepoint | **LIVE** `1aef6d1` |

**Live line.** The gate runs at `gatedPresetSave`, the single chokepoint three
of five save paths call. **Verified by a watched bench connect, 2026-08-14
17:36:20Z:** the healer executed non-vacuously (all three fact families
republished — participation 12->13, boundaries 14->15, ladder fact 2->3),
`presets.json` came through **byte-identical** (`sha256 b66e1185`, 13246 bytes),
segments unchanged at `0[0,128) 1[128,290)`, and the **match branch wrote
nothing**. A refusal would have skipped the heal; a mis-classified drift would
have re-provisioned and re-saved. Neither happened.

**Asterisks of record — what is NOT proven:**

- **#3 `CalendarEntryLeaseManager` is not wired.** Its `_WriteAttempt.
  savePresetFailed` triggers an in-memory registry rollback, and a gate refusal
  is not that. Needs a `gateRefused` state rippling into 4+ call sites with
  rollback semantics — its own reviewed change.
- **Drift and total-loss re-provision are proven by tests plus the pre-wiring
  live classification, NOT by physical drift.** Deliberate: the rig does not get
  broken to watch it recover, having already lost its layout once this week.

**Stand-aside boundary, stated so it is not re-litigated by accident:**
**unreadable stands aside; a readable disagreement always gates.** The gate
guards against a KNOWN mismatch, not against ignorance. This was a spec change
forced by wiring — the original said unreadable refuses, and 14 real test
failures showed that on the sunrise-off path a refusal ABORTS the timer write,
so one transient read failure would leave a customer's lights on at sunrise.
It also brought the gate into line with #67, W4 and the readiness gate, where
unknown is explicitly not bad — the original spec was the odd one out.

**Baseline of record: 2302 / 3 skipped / 0 failed.** Lineage 2282 -> 2301 ->
2302. **2305 discarded — unreconciled, and it appears in no measured run.**

### +78 CONTENT ACCUMULATING — opened 2026-08-17

Not a build row. Opened when `feat/gameday-unified-monitoring` merged; becomes a
row when +78 is built.

**METHOD LINE, verbatim and adopted:** *content gates are written from `git log`,
never from session summaries.* The merge review that produced this section was
run that way and it is the reason the entries below say what they say — the
branch's own commit messages claimed a migration, a screen demotion and a 30s
poll cadence, and the inventory found the first unwired, the second absent, and
the third caller-less.

#### Merged: `f59299c` (branch reviewed at `47a143b`, corrected at `478d18f`)

Unified monitoring model, C10 `start_time_passed` + #90 `daylight_game` planner
rows, C11 dead-code deletion. Merge-base `25a0a29`; **zero code-file overlap**
with main's own advance, which is why it merged clean.

Pre-merge correction of record: `live_scoring_enabled` shipped **with no writer
anywhere in `lib/`**, so the arming gate was permanently on and no UI could turn
it off — the user-facing "Live Scoring" switch writes `score_celebration_enabled`
(49 of 50 live configs carry it). `setLiveScoring` now writes both; both parsers
fall back `live_scoring_enabled ?? score_celebration_enabled ?? true`. See
`BUGS_AND_DEBT.md` #79's merge-review block.

#### Reconciliation — three inputs could NOT be verified against this tree

Recorded rather than adopted, per the `2305 discarded` precedent on the line
above: *unreconciled, and it appears in no measured run.*

| Input | This tree measures | Disposition |
|---|---|---|
| **32 claimed / 82 present** | Branch git log = **2 commits, 12 files** (3 / 18 with the correction commit). | **Unreconciled.** Likely cause named below. |
| **Unclaimed W-track** (device targeting, speed, brightness norm) | **Absent** from the branch-only diff (`25a0a29..478d18f`) under both exact and loose grep. | Needs its own source before it can carry an inventory line. Not attributable to this merge. |
| **Migration neutered to stub-repair-only** | `migrationConfigsFor` still has **zero callers**; no stub-repair code exists. **#92 stands as filed.** | Decision recorded (below); implementation **not in this tree**. |
| **Baseline 2389 / 3 / 0** | **2346 / 3 / 0**, measured twice on `f502f37`, delta reconciled exactly (+27 / +10 / −2 = +35 on 2311). | **2346 is the measured baseline.** 2389 appears in no run here. |

**Likely cause of 82, worth naming because it is the exact failure the method
line guards against:** diffing *merge-base → merge-commit* (`25a0a29..f59299c`)
sweeps in main's own #76/#88/design/schedule work and reports **27 files /
1432 insertions** for `lib/` + `functions/` alone. A content gate built that way
attributes main's work to the branch. The branch-only range is
`25a0a29..478d18f`.

#### Decisions recorded

- **monitored × celebrations = coherent-by-design** (A4 option 1's intent).
  Adopted. One fact preserved so it is not rediscovered as a bug:
  `AlertTriggerService.handleAlertEvent` opens `WledService('http://$ip')` per
  controller and animates for any *monitored* team **without consulting
  `score_celebration_enabled`**. "Monitored" therefore already means "lights the
  house", LAN-direct. Any later monitoring-without-lighting mode must gate that
  path too.
- **#91 filed, not fixed** — the worker's own applies bypass the #67 full
  partition, and this merge makes that emitter live for the first time. A fix
  needs the full device channel list in the background isolate, which the mirror
  does not persist.

#### finding f — CLOSED. Record the reason precisely.

Closed, and nothing on main — that much is agreed. But the relayed reason
("existed in early branch commits, deleted by its own author pre-merge") is
**not supported by this repo**, and the ledger should not credit a cleanup that
cannot be shown to have happened:

- absent at `c7d9a9e` (first branch commit) and at `47a143b`;
- absent from the branch's cumulative diff;
- branch reflog is **linear** — created from main at `25a0a29`, three commits,
  no rewrite, no force-push, so there is no earlier branch commit to have held it;
- both dangling commits in the repo are unrelated (2026-07-22 schedule-picker
  WIP; 2026-06-03 config fix) and neither contains it.

**Reason of record: never present in any reachable commit.** The relay error was
indeed the only error — but it was an error of *invention*, not of *timing*.

#### Accumulating for the +78 build session

1. This merge (`f59299c` + `f864a84`, `f502f37`).
2. Four filed P2s, each its own change: seg-deletion · hero-image **#80** ·
   **#88** defaults · **#3** `gateRefused`.

#### Deploy plan of record

**Nothing is deployed.** Server halves deploy targeted and **before +78
distributes**, per the +74 rule — assert the deployed SHA is an ancestor of main
first (`git merge-base --is-ancestor <sha> main`).

There is **no server half of the migration** to deploy: `migrationConfigsFor` is
client-only and unwired, and `functions/src/` contains no Game-Day migration
(the migration files there are the *schedules* subcollection work). So the
deploy is the two planner rows alone:

```
firebase deploy --only functions:planGameDayFires
```

**Awaiting Tyler's confirm — not run.** Both rows are pure observability (a row
where a counter already bumped), so an un-deployed planner and a +78 client
disagree only about what the log *names*, never about what fires; there is no
ordering hazard in either direction. If a Game-Day migration server half is
written later, it joins this command and the before-+78 ordering starts to
matter for real.

### GEOMETRY GATE IMPLEMENTED 2026-08-14 — #76's severity cap is closed

`lib/features/schedule/geometry_gate.dart`. Geometry clobbering now has four
independent layers, and the gate is the one that makes the damage
**non-durable**:

| # | Layer | Where |
|---|---|---|
| 1 | builders that no longer emit geometry | seven payload builders, `70726ac` |
| 2 | a ladder path that never asserts it | `_fullStripOnSegments` emits `{id,on}` only |
| 3 | a rig configured to catch the class | bench restored to two segments |
| 4 | **a gate that refuses a drifted re-provision, legibly** | this |

1-3 shrink the window in which geometry can be wrong. **Only 4 stops a `psave`
taken during that window from baking it into the base layer**, where it loads
every night. That is the difference between a bad evening and a bad install.

**Compares COUNT and BOUNDS only.** `rev`/`mi`/`of`/`grp`/`spc` are excluded by
design: the pixel map does not own them, and refusing on a correctly-installed
reversed channel the app has no record of would be **#76's mistake with the
sign flipped** — the app's model overriding the installation instead of
flattening it. Pinned as a test.

**Branches:** `match` (proceed, and it must write NOTHING — asserted),
`drift` (same count, bounds moved), `totalLoss` (count differs — the 2026-08-14
reboot collapse, a proven input, and one a preset load cannot undo because
bounds live in cfg). Drift and totalLoss share one repair shape: write the
expected layout, then **prove it by reading back**.

**A write that reports success is not evidence.** Pinned by a test where the
provisioner returns `true` and the shape does not change: the gate re-reads,
sees the mismatch, and refuses. An unreadable device also refuses and writes
nothing — the only safe answer to "I could not tell" is "do not save".

**Refusal message names both shapes** and says why the preset was left alone:
*a stale-but-correct ladder beats a freshly-saved wrong one, because the wrong
one is durable and loads every night.*

**THE INTERACTION WITH THE NON-CONVERGENCE GUARD, pinned in a test.** They ask
different questions — the gate asks *is the device in a state worth saving?*,
the convergence guard asks *has saving stopped helping?* **A gate refusal is NOT
a repair attempt**: no save happened, so counting it would burn the convergence
budget on a condition a save was never going to fix, and would eventually
silence the gate's own legible refusal behind a generic non-convergence one.
Ten consecutive gate refusals leave the repair budget untouched; a gate that
PROCEEDS does feed the guard, and the other guard stops it at three.

**Verified against the live bench, without touching it.** The match branch was
confirmed against the real device (`0[0,128) 1[128,290)` -> `match`, no write).
For drift I fed the gate a deliberately WRONG EXPECTATION rather than
mis-bounding a copy of the pixel map — the device is never mutated at all,
which is strictly safer than snapshot/mutate/restore and proves the same
classification.

19 gate tests. Suite **2301 / 3 skipped / 0 failed** (from 2282). `flutter analyze lib/ test/`: 0 errors.

### ROOT-ON RESOLVED 2026-08-14 — the alarm was mine, not the fleet's

**VERDICT: root `on:false` IS storable. The predicate is satisfiable. There is
no fleet-wide disruption loop from this cause.** My previous pass escalated the
opposite as a live possibility; it was wrong, and the correction matters more
than the finding.

**Source evidence** (WLED `v0.15.1`, `wled00/json.cpp`, `serializeState`):

```cpp
if (includeBri) {
  root["on"] = (bri > 0);
  root["bri"] = briLast;
  root[F("transition")] = transitionDelay/100;
}
```

Root `on` is written **only when `includeBri` is set**, and `ib` is that request
flag. It is not "omitted when false" — it is omitted when brightness is not
included. Unambiguous from source, so **no psave experiment was needed** and the
approved scratch-slot budget went unused.

**So the losing side was my manual repair.** `buildNglOffPresetState` sends
`ib: true` and always has; its own doc says *"`ib: true` persists root `on:false`
into the stored preset."* My hand re-save on 2026-08-14 omitted `ib`, which is
why preset 2 came back with root keys `[mainseg, n]` and no `on`. The app was
never wrong.

**Bench corrected** via the gated sequence (geometry verify -> set live off ->
save with `ib:true` -> read back):

```
preset 2 root keys: [bri, mainseg, n, on, transition]
   on = False      ROOT on:false STORED: True
   segs: [(0, False), (1, False)]
```

**A stale comment was contradicting the code and is fixed.** `schedule_sync.dart`
claimed *"OFF preset 2 is intentionally left without ib"* while the builder sent
`ib: true`. Had anyone acted on the comment and removed the flag, they would have
created the exact unsatisfiable-predicate loop this pass went looking for. The
comment now carries the `serializeState` cite.

### NON-CONVERGENCE GUARD — the general fix the root-on scare earned

Implemented even though the specific case was benign, because the failure mode
is real and cheap to foreclose: an unsatisfiable predicate makes `psaveIfChanged`
re-save every sync, and **`psave` applies live**, so it is a visible flicker on
every connect with each individual save reporting success.

`preset_repair_convergence.dart` + wiring in `psaveIfChanged`. Three consecutive
attempts without the predicate flipping -> refuse with a legible reason naming
the preset, the name and the count. A satisfied predicate resets the counter, so
an intermittent failure cannot accumulate into a permanent refusal. The limit is
above 1 deliberately: one failure is ordinarily a transient write. A throwing
counter **fails open** — the guard must never become a new way to fail. Store is
process-scoped, so a relaunch re-attempts, which is correct when the controller
may since have been repaired.

**The rule: a repair that does not converge is a bug report, not a retry.**

### GEOMETRY GATE — spec written

`docs/SYNC_GEOMETRY_LAYER.md`, appendix. Lives at the healer's ladder-repair
entry, immediately before the first `psaveIfChanged`. Three branches — match,
drift, **total loss** (the reboot collapse, a proven input). Compares segment
**count and bounds only**: `rev`/`mi`/`of`/`grp`/`spc` are deliberately NOT
compared, because the pixel map does not own them and refusing on a correct
install whose reversal the app has no record of would be #76's mistake with the
sign flipped. Readback re-verification is mandatory after any re-provision.

**The two guards compose and are distinct:** the gate asks *is the device in a
state worth saving?*, the convergence guard asks *has saving stopped helping?* A
gate refusal must not count as a repair attempt — the save never happened.

### PRESETS.JSON REPAIRED via /edit — and two firmware facts fell out of it

**The corruption mechanism, recorded as its own finding.** `psave`/`pdel` can
leave garbage in the TRAILING PADDING of flash-resident `presets.json`. Here: 12
non-space bytes (`0x05`, `0x01`, `l`, `"`, and 8 × `0xFF`) sitting between the
last slot's closing brace and the file's final `}`. Strict JSON parse fails; the
slots themselves are untouched and still load.

**No preset operation can repair it.** `pdel` rewrote the file and a full ladder
re-save rewrote two slots — the padding region survived both, byte-identical.
`psave` rewrites slot CONTENT and preserves padding. A reboot does not clear it
either. **Recovery requires a filesystem-level rewrite.**

**RECOVERY PROCEDURE (route (a)) — use this if it ever appears in the field:**

1. `GET /edit?download=/presets.json` — keep as backup.
2. Locate the last valid slot's closing `}`; everything between it and the final
   `}` must be whitespace. **Verify no slot key (`"N":{`) and no quoted field
   name appears in that region** — if either does, STOP: it is not padding.
3. Blank that region to spaces, **preserving file length**, keep the final `}`.
4. Verify locally: strict-parses, and every slot is byte-identical to a tolerant
   parse of the original. Here: **12 bytes changed, 0 slots differing, 0 lost.**
5. `POST` multipart to `/edit` with `filename=/presets.json`.

**Result:** parses clean end-to-end, **18 populated slots** intact (ladder 1-5,
schedule 10/26-31/33/36/38/40/41/160), `ps=1` and `ps=2` both load onto two
segments, and `test/hardware/base_ladder_repair_live_test.dart` — which had
started failing on the corrupt file — **passes again**.

> ### ⚠️ FIRMWARE FACT: WLED 0.15.1 WILL NOT STORE ROOT `on:false` IN A PRESET
>
> Investigating the root-on discrepancy (item 3) produced a harder finding than
> expected. Preset 1 stores `on: true`. Preset 2, saved with `"on":false` inline
> **and the strip genuinely off beforehand**, stores **no `on` key at all**:
>
> ```
> preset 1 root keys: [bri, mainseg, n, on, transition]   on = True
> preset 2 root keys: [mainseg, n]                        on = None
> ```
>
> `isNglOffPresetSatisfied` **requires** the def to assert root `on:false`, and
> its doc calls a segments-only preset 2 "legacy" and re-saves it. If the
> firmware cannot store that key, **the predicate can never be satisfied** — the
> healer would re-save preset 2 on every evaluation, and `psave` applies its
> state live, so that is a visible disruption on every connect.
>
> **NOT RESOLVED, and deliberately not chased further** — diagnosing it needs
> more `psave` cycles than the approved scope allows. Two possibilities worth
> distinguishing next pass: the original preset 2 carried the key (written by an
> older firmware or a different path) and my re-save lost it; or it never did and
> the predicate has been failing quietly all along. **The second would mean the
> ladder repair has been re-saving preset 2 on every heal, fleet-wide.**
> The bench is currently in the unsatisfied shape either way.

### BENCH INCIDENT ARC — closed 2026-08-14, and it is the geometry gate's motivating evidence

**1. Cause (self-inflicted).** Proving WLED captures geometry into presets, I
set `seg1 rev:true`, `psave`d scratch slot 245, `pdel`d it. From that point
`/presets.json` returned 13246 bytes with 8 stray non-ASCII bytes in the trailing
padding, breaking strict JSON at char 12719.

**2. `pdel` rewrite did not clear it. Reboot did not clear it.** Identical length
and identical fault offset after both. `Content-Length` matches bytes received,
so the transfer is complete — **the file on flash is malformed**, not the read.

**3. The reboot then collapsed `seglc` 2 -> 1**, and — the load-bearing finding —
**a preset reload could NOT restore the geometry.** `{"ps":2}` restored
per-segment on-state onto a one-segment layout. Segment BOUNDS live in cfg; a
preset carries state, not shape. **Recovery required a cfg write; no preset
operation could have done it.**

**4. Recovered geometry-first**, the exact sequence the gate will enforce:

```
GATE STEP 1  verify geometry   seg0 [0,128)  seg1 [128,290)   -> PASS
GATE STEP 2  psave ladder onto verified geometry (presets 1 and 2)
GATE STEP 3  verify
```

Executed by hand once because the ladder path cannot run standalone today. **That
manual sequence IS the gate's contract.** Had step 1 failed, step 2 must not run —
which is precisely what would have baked a one-segment layout into the base ladder.

**RESULT — what is fixed and what is not:**

| | |
|---|---|
| Geometry | ✅ `seg0 [0,128)`, `seg1 [128,290)`, readback-confirmed |
| Ladder presets | ✅ `1 'NGL On'` and `2 'NGL Off'`, **both segments**, `rev:false`, captured from the restored layout |
| `ps=1` / `ps=2` | ✅ both load correctly onto two segments |
| All 19 slots | ✅ recoverable — ladder 1-5, schedule 10/26-31/33/36/38/40/41/160 intact |
| `presets.json` strict parse | ❌ **STILL FAILS** — the same 8 stray bytes survive a full ladder re-save |
| `readPresets()` tri-state | ❌ still `unknown` |
| W4 `base_ladder_asserts_segments` | ❌ still publishes **null**, not `true` |

**Item 2's acceptance criteria are therefore PARTIALLY met.** The dogfood run
proved the sequence and restored the ladder; it did **not** repair the file. A
psave rewrites slot contents but preserves the padding region where the stray
bytes live, so no amount of re-provisioning clears them.

**Remaining repair options, neither taken — both need approval:**
(a) `/edit` filesystem download → strip the 8 bytes → re-upload `presets.json`;
precise, preserves all 19 slots, but is a filesystem write.
(b) Delete `presets.json` and let WLED recreate it — **destroys the schedule and
lease slots** and is not acceptable without a rebuild plan.

**One behavioural change to note:** re-saved preset 2 leaves root `on:true` with
both segments off (this firmware stores off-state per segment). The strip is dark
either way, but the previous stored shape had root `on:false`.

**Why this matters beyond the bench.** The incident is the geometry gate's
motivating evidence, and it adds a proven input to its spec: the mismatch branch
must handle **TOTAL geometry loss** — segment count collapsed, not merely bounds
drifted. Reboot collapse is no longer hypothetical.

### BENCH: presets.json malformed by a scratch-slot experiment — REBOOT DID NOT RECOVER IT

**Self-inflicted, not a field failure.** Diagnosing #76 I set `seg1 rev:true`,
`psave`d to scratch slot 245 to prove WLED captures geometry, then `pdel`d it.
Slot 245 is gone, but `/presets.json` has returned malformed output ever since:
valid JSON to ~char 12660, then padding and 8 non-ASCII bytes, `len 13246`.
It parsed clean earlier the same day.

**Reboot did NOT fix it** (approved recovery, performed 2026-08-14): identical
length, identical fault offset afterwards. The damage is on flash, not a flush
artifact. `pdel` had already rewritten the file, so whatever is wrong survives a
rewrite.

**The ladder itself is intact and functional.** Recovered by tolerant parse:
`1 'NGL On'` and `2 'NGL Off'`, both with two segments. `{"ps":2}` loads
correctly. Only the JSON *read* is broken.

**P1-52 note — add to the unparseable-presets guard's rationale:** `psave`/`pdel`
against a scratch slot can malform the stored file, and a reboot does not
necessarily repair it. That is a second, reproducible source for the condition
the guard exists to survive — the guard is not merely defending against a bad
HTTP read.

**Live consequences on the bench, both benign-by-design:**
`readPresets()` returns `PresetsReadState.unknown`, so W4 publishes
`base_ladder_asserts_segments` as **null** (unmeasured, not false) — the
tri-state doing its job. The healer's ladder repair will likewise judge the
presets unreadable rather than empty, which is what P1-52 exists for.

### BENCH: the reboot collapsed the segment layout 2 -> 1, and a preset load did NOT restore it

Both documented reboot behaviours fired. The strip **booted lit**
(`on=true bri=128`, the `def.on` fact) and the **segment layout collapsed**:

```
post-reboot   segs=1
after ps=2    seg0 [0,290) on=false rev=false     <- ONE segment, not two
```

The recorded expectation was that a preset reload restores the two-segment
layout. **It did not.** Segment BOUNDS live in `cfg` (`seglc`), not in the
preset, so the preset restored per-segment on-state onto a layout that no longer
has a seg1. **The bench is now single-segment**, which changes the rig's shape
for every geometry test — including the #76 blind-spot work it was meant to
support.

Restoring two segments is a **controller cfg write**, which the standing
constraint says to flag rather than perform. Not done; awaiting direction.

### FIELD FINDINGS — Ellie sync night, 2026-08-12 (recorded 08-14)

Three findings, **one root: the system has no model of the physical house.**
Filed as #76 / #77 / #78; the layer that dissolves all three is specced in
[`docs/SYNC_GEOMETRY_LAYER.md`](SYNC_GEOMETRY_LAYER.md).

- **#76 (P1, ship-soon) — design payloads clobber installation geometry.** Her
  reversed channel 2 was stamped `rev:false` by the design template and ran
  backwards until she fixed it by hand in WLED. Root cause:
  `editable_pattern_model.dart:187-193` emits `'rev': direction == left` and
  `'mi': direction == centerOut`, so any pattern not authored "left" un-reverses
  a correctly-provisioned channel. Seven builders write geometry; all are listed
  in the bug entry.
  **THE RULE, complement to #67:** design payloads assert DESIGN fields only
  (`fx/col/pal/sx/ix/on/bri`); geometry (`rev/mi/start/stop/of/grp/spc`) belongs
  to provisioning. #67: unstated segment state is inherited state. #76: **state
  that isn't yours to state must not be stated.**
- **#77 (P2) — multi-channel continuity.** Her two front channels rendered the
  design independently: one design, two visual runs, a seam at the boundary.
  Structural fix is the geometry layer; interim phasing hacks deliberately NOT
  scoped yet, because the coordinate system would only have to unpick them.
- **#78 (P2) — join fabricates geometry.** `joinNeighborhood.ts:359-360` writes
  `ledCount: 300, rooflineMeters: 15.0` (= **49.2 ft**) for every member; the
  client mirrors the same defaults as `fromFirestore` fallbacks. Neither number
  is measured, and nothing ever reports "unknown" — so no consumer can tell a
  real 300-pixel home from a placeholder.

**BENCH FINDING that changes #76's fix, proven on `.150` 2026-08-14:**

```
seg1 rev=true   (live write)
{"ps":2}  ->  seg1 rev=false
```

**Geometry is stored inside presets.** So (a) the clobber self-heals at the next
base-preset boundary for any account with a floor — Ellie's ran backwards for the
evening, not permanently; and (b) **a customer who fixes it in WLED without
re-saving the preset loses the fix at the next boundary**, which is the worse
case and belongs in the support answer.

**Bench blind spot ESCALATED, not silently done.** Both bench segments run
forward, so the rig cannot catch this class. Making one `rev:true` *permanently*
is not a state write — it requires re-saving the base ladder presets, a `psave`
against presets 1/2, the operation carrying the frozen-segment capture and
ambient-seg history. Live-only reversal is reverted by the first preset load.
**Needs a decision before the rig is changed.**

**E — milestone evidence stands, and its limits are stated.** Her house converged
via **self-apply on her own LAN** (0.16.1 Dig-Octa), and the **cross-network join**
is real. Neither is the crew fanout. **R-5 remains AMBER** pending the deliberate
street test.

**IP:** the feet-based multi-home composition in item 3 of the geometry spec is
assessed novel and server-side — **counsel before any public disclosure**, per the
IP timeline doc. The spec doc carries the notice at the top.

### CENSUS CORRECTED + R-5 STAYS AMBER — 2026-08-14

**The worksheet census was stale, and I published a stale row.** Ellie
(`5oHhaEaf`) was recorded as failing R1. She does not: `schedules` array len 1,
subcollection 1, and the planner's own persisted verdict is
`gameday_gate_blocking: []` — **armed**. Her R2 is `true` (W4's fact, published
from her hardware) and R3 is present. **All three green.**

That stale row nearly produced a worse error. Asked to check whether her house
was stranded on a sync design, the census answer would have been "no floor to
recover it." The live read said otherwise. **Read the account, not the
worksheet** — the worksheet is a snapshot with a date on it.

**Fresh census, 2026-08-14, read live:**

| uid | account | R1 | R2 | R3 | verdict |
|---|---|---|---|---|---|
| `wrQRUUKy` | bench | OK | **true** | OK | **ARMED** |
| `cndlN3nm` | chris_cipollone | OK | unknown | OK | **ARMED** |
| `5oHhaEaf` | **Ellie** | OK | **true** | OK | **ARMED** |
| `Ayf0rqwN` | textim6 | — | unknown | OK | log-only `[no_floor]` |
| `YcSGiwes` | Blue Line | OK | unknown | — | log-only `[no_facts]` |
| `Pqptfawp` | dnicholas0131 | — | unknown | OK | log-only `[no_floor]` |
| `j8eXTfcs` | marc ⚑ #53 | — | unknown | OK | log-only `[no_floor]` |
| `EHRfYGyf` | cpaschall10 | — | unknown | — | log-only `[no_floor, no_facts]` |
| `NmDukd5r` | jjdyer1 | — | unknown | — | log-only `[no_floor, no_facts]` |
| `reviewer` | reviewer | — | unknown | — | log-only `[no_floor, no_facts]` |

**ARMED 3, no-floor 6, of 10.** Two corrections to the figures in the request:
it is **3 armed, not 4** — `Ayf0rqwN` graduated **`no_facts`** on 2026-08-13, not
`no_floor`, and its persisted verdict is still `["gated_no_floor"]`. And
**6 floors remain, not 5.** Easy to conflate two graduations; recorded so the
worksheet is not corrected into a second wrong number.

**R2 has started moving.** Two accounts now read `true` (bench and Ellie) where
the whole fleet was `unknown` yesterday — W4 collecting per account exactly as
designed, with no server change.

**THE TRUE STATE, not the flattering one:**

- `config/sync_fanout` = `enabled:true`, `group_allowlist:["OqWsIyvNUwYjel6Dbzwl"]`
  — **Ellie's group**. Her house is **one `fanout:true` away from being
  commanded**. This is a **STAGED LIVE WIRE**, deliberate, for the street test.
  The previous scoping's "no customer" safety property is gone by choice, and
  the allowlist is therefore NOT what protected her last night.
- **The two-homes crew-fanout milestone has NOT occurred.** Last night was
  **host-only self-apply** (four commands, all in Tyler's own queue, all
  targeting `.150`) plus a genuine **cross-network join** earlier. Both real,
  neither is the milestone.
- **R-5 stays AMBER** pending the deliberate test in
  [`docs/STREET_TEST_RUNBOOK.md`](STREET_TEST_RUNBOOK.md).

**#75 filed (P3):** host-only and crew fanout stamp the same `sync_fanout`
source string; the only discriminator is the target queue. It already caused a
misreading of last night's data.

### Sync cleanup + fanout RESCOPED — 2026-08-13

Production `/neighborhoods` held three groups. Two were internal test artifacts
and were deleted with their subcollections enumerated explicitly (Firestore does
not cascade):

```
06m7bMxKNjolhsRXV5MJ  "demo test"  commands/1  members/2
8b25LBEhS51H65VHKGQ1  "demo"       commands/1  members/2  rate_limits/state
```

Verified after: both group docs gone, **0 residual subcollection docs**,
`/neighborhoods` = 1. `/neighborhood_public` was already empty. **No user doc
referenced any deleted group id** — scanned every user for all three ids, zero
hits, so no denormalized cleanup was needed.

**`/invitations` is NOT Sync** and was left alone: those two pending docs are
household-sharing invites (`installation_id`, `permissions`,
`primary_user_id: j8eXTfcs` = marc@tapsonmain.com).

> **THE THIRD GROUP WAS KEPT, AND THE PREMISE THAT WOULD HAVE DELETED IT WAS
> WRONG.** The cleanup brief described the real Tyler+Ellie group as something
> that "gets created fresh when Tyler and Ellie run the live street test." It
> already existed: `OqWsIyvNUwYjel6Dbzwl` — *"Let's Hope This Works"*, created
> 2026-07-28, whose second member `ecochran08@yahoo.com` reads
> `display_name: "Ellie Cochran"`, `bridge_paired: true`, bridge `10.0.0.112`,
> controller `20_e7_c8_f4_d5_38` at `10.0.0.32`. Deleting it would have dropped a
> remote household's membership and forced a re-join by invite code. Audit-first
> is what caught it.

**Fanout rescoped in the same pass**, readback-confirmed:

```
BEFORE group_allowlist=["8b25LBEhS51H65VHKGQ1"]   enabled=true
AFTER  group_allowlist=["OqWsIyvNUwYjel6Dbzwl"]   enabled=true
```

> ⚠️ **THIS IS A DELIBERATE WIDENING, NOT A LIKE-FOR-LIKE MOVE.** The previous
> entry justified itself as *"bench-created … no customer."* The new target
> contains a **real second home**: a fanout in this group commands **Ellie's**
> lights, not a bench rig. That is presumably the point — it is the live
> street-test group — but the safety property the old scoping relied on is gone,
> and the next fanout run is against someone's house. `enabled:false` remains the
> instant rollback, no deploy.

### `config/sync_fanout` — SCOPED ENABLE, 2026-08-12T21:15:10.089Z

```
{ enabled: true, group_allowlist: ["8b25LBEhS51H65VHKGQ1"] }
```

**Fanout live for exactly one group: "demo" (`8b25LBEhS51H65VHKGQ1`).**

Chosen because it is bench-created and its only members are
`tyler.honeycutt@nex-genled.com` (controller `192_168_1_150`) and
`nex-genadmin@nex-genled.com` (controller `80_f3_da_b3_76_64`) — **no customer**.

> **`OqWsIyvNUwYjel6Dbzwl` ("Let's Hope This Works") is deliberately EXCLUDED.**
> It contains `ecochran08@yahoo.com` with a real controller
> (`20_e7_c8_f4_d5_38`). Fanout writes commands to *other people's* controllers,
> so enabling that group would put a customer's lights under another member's
> control. `06m7bMxKNjolhsRXV5MJ` is also excluded — it was the F-3 join-test
> target and is left untouched so that verification's evidence stays clean.

Verified against the **deployed** parser reading the **live** flag doc:

```
demo      8b25LBEhS51H65VHKGQ1  ->  true
demo test 06m7bMxKNjolhsRXV5MJ  ->  false
CUSTOMER  OqWsIyvNUwYjel6Dbzwl  ->  false
```

**ROLLBACK: `enabled: false`. Instant, no deploy** — both the CF and the client
re-read the flag live.

`applySyncPattern` imports only `firebase-functions` and `firebase-admin`, shares
no module with `planGameDayFires`, and was deployed with `--only
functions:applySyncPattern`, so the planner keeps its existing revision.



### §4 two-node fanout verification — 2026-08-12. Three runs, 3/4, and the feature does not work.

Runbook step 4/5, group `8b25LBEhS51H65VHKGQ1`. A = bench controller `.150`
(Tyler), B = stub endpoint + bridge simulator draining `nex-genadmin`'s queue.
Recorded in full because each run failed differently and only the third failure
was the product's.

**Run 1 — 21:40Z, 0/4.** Every fanout returned 400 and the harness printed
`reason=null` four times. The body carried no `initiatorUid`, which
`applySyncPattern` rejects at the top of the handler — before the membership
gate, the flag read, and the rate-limiter reservation. That last one is why
fanout#2 reported `retryAfterMs=0`: no slot was ever reserved, so *both* the
convergence and rate-limit failures were one defect wearing two costumes. The
`reason=null` was its own bug — the CF names rejected fields in `error`, which
the harness never read. Fixed in `44c7f17`; `initiatorUid` is derived from the
`--a-token` rather than passed as a flag, because the CF asserts
`decoded.uid === initiatorUid` and two sources for one fact is how the next
mismatch gets written.

**Run 2 — 21:40Z, 3/4. First cross-account propagation in the feature's
history.** The command landed in a non-initiator's queue, the bridge-sim
delivered it, B reflected `fx=88 pal=5` exactly, and fanout#2 was refused with
`retryAfterMs=14669`. A did not converge. The server had already said why —
`members=1 commands=1 skipped=1` — in three fields the harness discarded. A's
member doc was `participationStatus:"paused"`, and since the fanout arm
*returns*, the host-only self-write never runs when fanout is on, so a paused
initiator's own house is never commanded (**#69**). A's evidence line read
`A fx=0 pal=5` against a broadcast of `fx=88 pal=5` and looked like a partial
apply; nothing had been applied at all — the rig rests on `pal=5` on both
segments and one field coincided. A convergence assertion resting on a
pre-existing value is not evidence, so the harness now snapshots A first and
reports a pre-matching baseline as INCONCLUSIVE rather than passing it.

**Run 3 — 22:03/22:04Z, 3/4 — and the real one.** A's member doc flipped to
`participationStatus:"active"` (**permanent**; active is the correct resting
state for the test crew). The flip worked exactly as intended:
`served=2 wrote=2 skipped=0`. The rig still never moved:

```
controllerId: "192_168_1_150"   controllerIp: ""
error: "ERROR: HTTP -1"          status: "failed"
```

`resolveMemberTargets` discards the IP for any member whose doc carries a
denormalized `controllerId` array — the normal shape — so **every crew fanout
command ever written names no destination** (**#70**, P1). Neighborhood Sync has
never reached hardware. It survived three runs because the bridge-sim POSTs to
its own stub and never reads `controllerIp`: it reported *delivered* for a
command byte-identical to the one the real bridge refused. Closed harness-side
in `0c5fd92` — a simulator more capable than the thing it simulates does not
verify it.

**Assertions, verified against raw evidence rather than the harness's
self-report** (Firestore queues and `.150 /json/state` read directly):

| # | Assertion | Verdict |
|---|---|---|
| 1 | CF wrote into a NON-initiator's queue | **PASS** — `served=2 wrote=2 skipped=0`, docs present in both queues |
| 2 | B reflects the broadcast | **PASS for the stub, VOID for hardware** — same empty `controllerIp` a real bridge rejects |
| 3 | A converges | **FAIL** — `#70`; A's commands `status=failed`, rig unchanged at `fx=0` |
| 4 | 2nd fanout <18s refused | **PASS** — `retryAfterMs` 14826 / 14875 |

**The gate held.** "Stop unless the non-initiator converges" was set to catch a
non-working fanout, and the fanout *does* work — the CF's routing, membership
verification, allowlist scoping, and rate limiting are all proven. What is
broken is one line of address resolution beneath it.

**Bench restored** to `on=false bri=200 ps=2`, identical to the post-end-fire
baseline. Ellie's bridge `D4E9F4FA9D40` was never reachable: her crew
`OqWsIyvNUwYjel6Dbzwl` is excluded by the `group_allowlist` above, and no
command doc was written to any account outside the two test uids.

**Run 4 — 22:27Z, TRUE 4/4. Neighborhood Sync reached hardware for the first
time.**

```
A baseline fx=0 pal=5 on=true
fanout#1 -> status=200 ok=true served=2 wrote=2 skipped=0
bridge-sim drained 1 command(s)
A converged after ~2s (real bridge)
fanout#2 -> status=200 ok=false reason=rate_limited
4/4
```

`#70` fixed in `06e36dc`, deployed `--only functions:applySyncPattern` at
**22:20:40Z**. The denorm branch now joins each id against
`/users/{uid}/controllers` with one `getAll`; an addressless target is written
`status:"failed" error:"no_address"` instead of dispatched at an empty host.
A failed join deliberately does **not** fall through to the subcollection scan —
that would command controllers the member never named, widening the blast radius
on an error path.

**Webhook Mode is not addressless.** The first cut judged deliverability on
`controllerIp` alone; `executeWledCommand` (`functions/index.js:398`) routes on
`webhookUrl` and never reads `controllerIp`, so that would have marked every
Webhook-Mode member `no_address` — breaking a working path to repair a broken
one. Deliverability is ip-OR-webhook. 291 tests / 12 suites (baseline 271 / 11).

Verified independently of the harness, at 22:27Z — the before/after sits in one
collection:

```
A  22:27:17.380Z  status=completed  ip="192.168.1.150"  err=null   <- the fix
A  22:04:39.941Z  status=failed     ip=""   err="ERROR: HTTP -1"   <- #70
A  22:03:45.287Z  status=failed     ip=""   err="ERROR: HTTP -1"
B  22:27:17.373Z  status=completed  ip="192.168.1.156" err=null
```

and on the strip itself: `seg0 fx=88 pal=5 col=[[255,0,0],[0,0,255]]`.

**Bench restored** to `on=false bri=200 ps=2`. Note that power-toggling alone
leaves `ps=-1`; base is re-established by re-applying preset 2, not by switching
off.

**Flag state held overnight**, both bench-scoped and correct:
`config/gameday_planner` `write_jobs:true` / `uid_allowlist:[bench]`
(`updateTime 15:51:14Z`); `config/sync_fanout` `enabled:true` /
`group_allowlist:["8b25LBEhS51H65VHKGQ1"]` (`updateTime 21:15:10Z`). Neither was
touched by the deploy, and `planGameDayFires` keeps its `15:33:21Z` revision.

**§4 CLOSED.** Commits: `a60a808` (format only), `44c7f17` (initiatorUid + error
surfacing), `1e5f07f` (#69), `3910a85` (poll for the real bridge), `0c5fd92`
(empty-IP fidelity + #70 filed), `06e36dc` (#70 server fix). The global flip is
now a decision, not a blocker.

### GATE REBUILT 2026-08-13 — per-account readiness, enforced by the planner

**What it replaces.** `base_layer_gate.dart` describes itself: *"⚠️ NOT A GUARD.
If anything here fails — no context, dialog throws, provider unavailable — the
enable PROCEEDS."* Toggle-only, session-dismissible, and **all nine live Game Day
accounts predate it**, so it has gated nobody.

**Enforcement moved server-side** (`392f5db`, deployed
`--only functions:planGameDayFires`). A client guard covers only the paths it is
attached to, and enablement has at least three — the toggle
(`game_day_autopilot_providers.dart:587`), the create-and-enable path (`:638`),
and the AI recurring-sports handler. The planner iterates every `enabled==true`
config every five minutes, so it covers all of them, grandfathered accounts, and
any path added later, **without knowing they exist**. That is the recon answer to
"map every enablement path": server-side evaluation dissolves the question.

Failing means **LOG-ONLY for that account** — the same shape `uid_allowlist`
already produces. `writeJobs = allowlisted && gate.armed`. One mechanism, two
reasons: the allowlist protects the FLEET from unproven code, the gate protects a
CUSTOMER from unattended wrong lighting.

| Check | Source | Semantics |
|---|---|---|
| **R1 floor** | `users/{uid}.schedules` array **or** `/schedules` subcollection (#TD-1 dual state, either counts) | enforced |
| **R2 ladder** | `controllers/{id}.base_ladder_asserts_segments` | **tri-state** |
| **R3 facts** | `controllers/{id}.participating_channels_device_ids` | enforced |

R1 is deliberately **not** `base_boundaries` — those are device timers the healer
published, and an account can have boundaries with no schedule (Ellie does).

**R2's asymmetry is the load-bearing decision.** `true` passes, `false` fails
CLOSED, absent is unknown-and-**allowed** with an advisory. The fact does not
exist yet, so failing closed on absence would put the entire fleet in log-only
awaiting a healer pass that only happens when each customer next opens the app on
their LAN. Writing the check as `!ladderAssertsSegments` would collapse unknown
into bad and do exactly that — pinned as a test.

Reasons are distinct per the #68 lesson: `gated_no_floor`, `gated_no_facts`,
`gated_ladder_bad`, `gated_no_ladder_unknown` (advisory). **Graduation is
automatic** — re-evaluated every tick, so setting a schedule arms the account on
the next one with no re-toggle, logged `graduated_<reason>`. The prior verdict
persists on the user doc and is written ONLY on change. Reads are reused: the
user doc and controllers are already in hand, and the schedules subcollection is
read only when the array is empty. **374 tests / 16 suites** (was 338 / 15).

**Summary counter** (2026-08-13, `formatGateSummary`): one aggregate line beside
the per-account rows, folded from the SAME verdict array the rows are built from
— `gate: 8 accounts gated {no_facts:5, no_floor:7} · 10 advisory
{no_ladder_unknown:10} · 2 armed`. Advisory is stated apart from gating: every
account carries the R2 advisory today, and a merged figure would read "10
blocked" when 2 of those are armed. **Eight gated, not the seven in the approved
example** — the two reason sets overlap by four and `YcSGiwes` fails only R3, so
the distinct count is the union. The test caught that before the log could state
it wrongly.

### WORKSHEET MOVEMENT — first customer-driven graduation, 2026-08-13T15:55:14Z

`Ayf0rqwN` (textim6@yahoo.com) published participation facts — `dev=[0,1]` —
minutes after the gate went live. Nobody did anything server-side: this is the
self-healing R3 path, a customer opening the app on their LAN and the healer
publishing. **The first movement on the global-arm worksheet, and it came from a
customer rather than from us.**

The account graduated `no_facts` and stays gated on `no_floor`, so the live line
moved `{no_facts:5}` to `{no_facts:4}` with `gated` holding at 8 — the counts
behaving exactly as the model predicts, which is a better check on the summariser
than any fixture. **R3 gaps are now three:** `EHRfYGyf`, `NmDukd5r`, `YcSGiwes`
(`reviewer` has no controller at all). `Ayf0rqwN` now needs only a floor.

Also this pass: the summary separator became **ASCII** (`|`) — the middot rendered
as `?` in the gcloud console, so the line's first act in production was to become
unreadable in the place it is read. And the census test split in two: permanent
**invariants** (gated + armed = evaluated; advisory never folded in; counts folded
from the same verdicts as the rows; a gated count is the UNION of reasons, not
their sum) and a dated **snapshot** that reports drift and never hard-fails —
a red build because a customer set a schedule would teach everyone to stop reading
it. Updating the snapshot is a deliberate ledger act; this entry is the first one.
376 tests / 16 suites.

### GLOBAL-ARM WORKSHEET — census 2026-08-13

Nine accounts, eighteen configs — reconciles exactly with the planner's
`configsEnabled:18`.

| uid | account | teams | R1 floor | R2 ladder | R3 facts | verdict |
|---|---|---|---|---|---|---|
| `5oHhaEaf` | ecochran08@yahoo.com | 8 | ❌ | unknown | 1/1 | log-only |
| `Ayf0rqwN` | textim6@yahoo.com | 1 | ❌ | unknown | 0/1 | log-only |
| `EHRfYGyf` | cpaschall10@gmail.com | 1 | ❌ | unknown | 0/1 | log-only |
| `NmDukd5r` | jjdyer1@hotmail.com | 1 | ❌ | unknown | 0/1 | log-only |
| `Pqptfawp` | dnicholas0131@gmail.com | 1 | ❌ | unknown | 1/1 | log-only |
| `YcSGiwes` | stegall.s@yahoo.com | 1 | ✅ | unknown | 0/1 | log-only |
| `cndlN3nm` | chris_cipollone@simonton.com | 1 | ✅ | unknown | 1/1 | **ARMED** |
| `j8eXTfcs` | **marc@tapsonmain.com** ⚑ **#53** | 2 | ❌ | unknown | 1/1 | log-only |
| `reviewer` | reviewer@nexgenled.com | 2 | ❌ | unknown | no controller | log-only |
| `wrQRUUKy` | bench (re-enabled `mlb_twins`) | 1 | ✅ | unknown | 1/1 | **ARMED** |

**Seven of nine fail R1** — the figure confirmed independently of the original
estimate. **R2 is `unknown` for every account**, because nothing publishes it yet.
Marc is flagged for the **#53** commercial pairing — his floor is plausibly a
business-hours schedule; flagged in the census, **not special-cased in code**.

**The remaining path to global arm, plainly:**

1. **Floors — Tyler-side, not code.** Seven accounts need an everyday schedule.
   This is customer contact (texts), and it is the long pole.
2. **R3 facts — three accounts** (`Ayf0rqwN`, `EHRfYGyf`, `NmDukd5r`, plus
   `YcSGiwes`) have a controller that has never published. Self-healing: it
   happens the next time the owner opens the app on their LAN. Not actionable
   server-side — the input is only readable over `/json/cfg`.
3. **R2 fact — a healer publish, filed as +76 app work.** Cheapest shape: a
   boolean + timestamp `base_ladder_asserts_segments`, computed on the LAN
   connect the healer already performs, by fetching `/presets.json` and checking
   that presets **1 and 2** each carry a `seg` array asserting `on` for every
   device channel. Reuses `controller_facts_writer`'s one-write discipline; costs
   one extra GET per session.
4. **Then, and only then, the allowlist-removal decision.** The gate does not
   replace the allowlist — it makes removing it a decision about *code* maturity
   rather than a bet on nine customers' base layers.

**#72 instance 3.** The bench's `mlb_royals` config read `enabled=false` with
`updated_at 2026-08-13T02:28:03.573Z`; it was enabled when it fired the Twins
cycle on 08-12. No session and no commit accounts for the change. Same class as
the `participationStatus` flip. Bench re-armed via `mlb_twins`, and the pattern —
**rig state moves between sessions** — is now three-for-three on being worth
re-reading rather than assuming.

### #71 — CLOSED 2026-08-13. Consent > pause, verified on the rig.

**Decision, quoted:** *"the initiator exemption extends to participationStatus
(pause) in initiateSyncSession, but NEVER overrides syncConsent. Pause is a mood;
consent is a contract. A paused initiator joins and can host their own session; an
explicitly opted-out initiator gets a LEGIBLE refusal telling them their consent
setting blocks it — never a silent re-opt-in, never a silent drop."*

**Structural pin:** `participationStatus` is not an input to
`initiatorConsentVerdict` at all, so the exemption cannot reach a contract even by
a future edit. Tested as a property, not just as behaviour.

**Two corrections to the brief, both quoted here because each would have shipped a
defect:**

1. **`:234` is the FCM recipient list, not a participation drop.** It skips the
   initiator when choosing who to push-notify — suppressing a notification to the
   person who just pressed the button. Exempting them there, as asked, would have
   notified the initiator about their own action. Left alone.
2. **`participationStatus.optedOut` is NOT syncConsent.** They are different
   fields; the decision's line runs between the two, so the exemption covers
   `participationStatus` whole — matching #69, where it covers `isMemberSkipped`
   whole. "An opted-out initiator gets a refusal" reads as if it covers this
   field, and it must not.

**Worker-hazard analysis (required before touching data).** The background worker
polls every 5 min (adaptive to 30 s near a trigger) and reads its configs
**exclusively from SharedPreferences** — *"No Riverpod, no Firestore listeners"*,
*"Avoids pulling in Firestore dependencies in the background isolate."* A Firestore
seed is therefore invisible to it unless a running app mirrors it via
`_syncEventsToBackground`. Belt and braces: the seeded event carried
`scheduledTime` in **2030** (the worker schedules no timer beyond 60 min out) and
**no** `espnTeamId`/`sportLeague` (the gameStart path bails immediately). Inert on
both paths.

**The proposed disabled-event control could not work, and was replaced.** The CF
validates `isEnabled` *before* consent, so a disabled event returns "Event is
disabled" and never reaches the #71 code. Both cases therefore used an enabled
event, made safe by the worker-inert state above rather than by ordering.

**Blocked case** — consent off, A paused:
```
HTTP 200 {"success":false,"reason":"consent_blocked","category":"gameDay",
          "message":"Your sync consent for \"gameDay\" is off, so this session
                     was not started. Turn it on to sync this category."}
sessions before=0 after=0   (NO session created)
```

**Success case** — consent on, A **still paused** (confirmed at start, per #72):
```
HTTP 200 {"success":true,"sessionId":"KfaznnvMPZwu0NHz9fF2","participantCount":1,
          "hostUid":"wrQRUUKyXyc0deyuu0ORS6wsovO2"}
session doc: activeParticipantUids=["wrQRUUKy"]  hostUid=wrQRUUKy
```
A is in participants **and** is host, while paused. Exactly the decision.

**#74 found by this run** — the first attempt created the session and answered
**500**: `arrayRemove([eventId])` passes a nested array, which Firestore refuses.
Latent until now (the loop runs per participant; with none it never validated),
and **#71 is what reached it** by putting the paused initiator into participants.
It throws AFTER `sessionRef.set()`, so the session went live while the caller saw
a failure — and the worker treats non-200 as failure. Fixed and redeployed; the
re-run is the clean 200 above.

**Cleanup verified, not assumed:** 0 syncEvents (no orphaned enabled event for the
worker to find later), 0 syncSessions, A's `syncConsent` deleted back to absent,
A still `paused`, no new commands in A's queue, bench `on=false bri=200 ps=2`.

**Client surface remains open as #73 (+76):** the only caller
(`sync_event_background_worker`) discards the reason — on 200 it reads
`result['sessionId']`, null for a refusal; on non-200 it `debugPrint`s. There is no
foreground caller, so no user is present at the moment of refusal. #71's refusals
are legible to the server log and to nobody else yet.

392 tests / 17 suites.

### #67 — CLOSED 2026-08-13. Exclusion means dark, not unchanged.

**Decisions, quoted:** *"fires assert the full partition; non-participating
segments get `{id: N, on: false}` ONLY — look/effect preserved (exclusion = dark
for this event; the base restore asserts full state after, so nothing else needs
clearing)."* And the principle, on its **third appearance**: *"unstated segment
state is inherited state, and inherited state is a bug."*

**Both builders** (`adfb49d`, deployed
`--only functions:applySyncPattern,functions:planGameDayFires`):

- **Game Day** — `buildFullPartitionSegArray`, wired through `buildGameDayPayload`,
  driven by `participating_channels_device_ids` which `participationForFire` now
  carries on its verdict. `deviceChannelIds` is the sole authority for what exists:
  a participating id absent from the device set is dropped, never emitted.
- **Sync** — `partitionBroadcastPayload`, applied **per target** inside the fanout
  loop, because every member has their own channel count and their own excluded
  set. The facts ride along on the `getAll` the #70 address join already performs,
  so the partition costs no extra reads.

**`baseRestorePayload` excluded — the claim was verified by reading, not assumed.**
It emits `{ps:N}`, and on the bench both base presets assert per-segment state:
`preset 1 'NGL On' seg (id,on)=[(0,true),(1,true)]`, `preset 2 'NGL Off'
[(0,false),(1,false)]`. Two refinements to the brief, recorded because they narrow
the claim: it loads preset **1 or 2** (solar-chosen), not always 2; and the
assertion is **device state, not code** — the bench ladder was repaired 2026-08-09,
and an unrepaired account whose presets psave with no `seg` key would NOT assert
full state. On such an account the exclusion would leak past the end fire. That is
the base-ladder issue, already tracked, not a new one — but it means "the restore
asserts full state" is true of the bench and not yet provable of the fleet.

**THE DISCRIMINATING RUN.** Both channels pre-lit, seg1 given a visibly different
look (`fx=57`, green/purple). One scoped Sync broadcast to the demo group, bench
participation `[0]`. What the CF put on the wire:

```
{"seg":[{"fx":88,"pal":5,"col":[[255,0,0],[0,0,255]],"id":0,"on":true},{"id":1,"on":false}]}
```

Converged in ~3s via the real bridge:

```
          BEFORE                                    AFTER
seg0  on=True  fx=0   pal=0 col0=[255,170,60]   on=True   fx=88 pal=5 col0=[255,0,0]
seg1  on=True  fx=57  sx=180 ix=200 pal=0       on=FALSE  fx=57 sx=180 ix=200 pal=0
                     col0=[0,255,120]                     col0=[0,255,120]
```

**Channel 1 went dark with its look byte-identical to pre-light.** That is the
2026-08-12 Twins failure inverted, and it verifies the preserve-look half on the
wire rather than by argument. Bench restored to `on=false bri=200 ps=2`.

**Regression safety for the live fleet:** participation == all channels is
byte-equivalent to the old builder, pinned as a test. Because of **#65** that is
every real account today, so this ships as a no-op everywhere except the bench.
**#65 is now unblocked** — it was gated on #67 precisely because fixing it first
would have made advisory exclusion customer-visible the same day.

**Fallback, never a guess:** facts missing or malformed → the pre-#67 payload,
reported `partitioned:false` and logged `partition_unavailable`, with the plan-log
row carrying both. Absent facts are `null`, never `[]` — an empty array would
claim the controller has no channels and darken everything. 338 tests / 15 suites
(was 322 / 14). Both flag docs unchanged after the deploy.

**Left behind, stated:** the broadcast also queued a command for member B
(`commandCount:2`), who has no live bridge, so that doc sits pending until it
expires. Harmless, and the cost of exercising the real fanout rather than a
self-only call.

### #69 — CLOSED 2026-08-13. Pause mutes the crew, not yourself.

**Tyler's decision, quoted** (a product choice, not derivable from the code):
*"pause does NOT mute your own broadcast. A paused member who initiates receives
their own command; pause continues to mute INCOMING broadcasts."*

**Fix** `8cb9d3c`, `applySyncPattern.ts:587-608`. `memberUid` moves above the skip;
the skip becomes `!isInitiator && isMemberSkipped(...)`. Keyed on **identity, not a
relaxed predicate** — `isMemberSkipped` is untouched, so every other member's pause
semantics are unchanged, and a later "simplification" into the predicate fails a
pinned test. The branch was also SILENT: it incremented `skipped` and returned, which
is why the 3/4 run reported `skipped:1` with no reason anywhere and the cause had to
be recovered by reading the roster by hand. It now logs member + status, matching its
sibling branch. Deployed `--only functions:applySyncPattern`; **322 tests / 14 suites**
(was 313 / 13).

**Two runs, same rig, same roster — the exposing configuration became the proof:**

| Date | A's status | Result |
|---|---|---|
| 2026-08-12 | `paused` | `members=1 commands=1 skipped=1` — A never converged |
| 2026-08-13 | `paused` | `served=2 skipped=0`, A converged **~2s via the real bridge**, B's stub reflected, `retryAfterMs=14883` — **4/4** |

**Post-deploy flag check:** `config/gameday_planner` `write_jobs:true` /
`uid_allowlist:[bench]` (`updateTime 15:51:14Z`, 2026-08-12) and `config/sync_fanout`
`enabled:true` / `group_allowlist:[demo]` (`21:15:10Z`) both **unchanged**;
`planGameDayFires` still on its `15:33:21Z` revision.

**The first deploy attempt failed** — `Cannot determine backend specification. Timeout
after 10000`. Not a code fault: `require('./index.js')` loads in 897ms locally, and the
identical retry succeeded. Recorded so the next occurrence is read as transient rather
than diagnosed from scratch.

**BENCH RESTING STATE: A stays `paused`.** Recommended and set, for two reasons.
(1) **Discriminating power.** Paused is the only state that exercises the initiator
exemption. With A `active` the exemption is dead code on the bench, and a revert would
pass every run silently — exactly how #69 hid. With A `paused`, a regression fails the
very next fanout run, visibly, on hardware.
(2) **It costs #67 nothing.** `participationStatus` is read by exactly two consumers —
`applySyncPattern` and `initiateSyncSession`. The **fire path does not read it at all**;
Game Day participation resolves from `participating_channels` (published by the healer),
a separate mechanism. Segment state is likewise unaffected. So #67's step 6 keeps full
bench participation and segment readability with A paused.

**One trade-off, named rather than buried:** with A paused, `initiateSyncSession` will
exclude A from sync SESSIONS — that path has the same skip and **no** initiator
exemption (**#71**, filed today). Any future bench test that drives a sync session will
see A missing, and should read #71 before treating it as a new bug.

**Unexplained, recorded:** A's member doc read `paused` at the start of today's work,
having been set `active` on 2026-08-12 for the 4/4 run. Nothing in this session's
commits touches roster data. It was the state the test wanted, so it was left alone —
but the reset itself is unaccounted for.

### F-3 — CLOSED 2026-08-12. Neighborhood reads scoped, crew join moved server-side.

Deployed from `fix/f3-neighborhood-security` @ `a83193f` (worktree
`C:/Flutter Projects/lumina-f3`). **`firestore.rules` + the `joinNeighborhood`
callable in ONE operation window** — rules alone makes joining impossible, the
callable alone leaves the hole open.

**Exposure at close: 3 demo crews / 0 street names / 0 coordinates / 0
`controllerIp`s.** A latent P0 closed before a single real customer crew existed
behind it.

**Ruleset id: unavailable.** The Rules API returned 403 to the ADC token. The
release is therefore **VERIFIED BY BEHAVIOUR**, which is the stronger evidence
anyway — every assertion below ran against PRODUCTION with a **client**
credential, never admin (admin bypasses rules and proves nothing):

```
c1  NON-MEMBER read group        HTTP 403   DENIED
c2  MEMBER read group            HTTP 200   ALLOWED
c2b NON-MEMBER read roster       HTTP 403   DENIED
c3  SELF-INSERT into memberUids  HTTP 403   DENIED
c4  callable, bad code           HTTP 404   NOT_FOUND, "No crew found for that
                                            invite code" — no existence oracle
c5  callable, good code          HTTP 200   ok:true, alreadyMember:false
                                            memberUids 2 -> 3, joined
                                            members/{uid} written in the SAME batch
```

The same `c1` read returned **200 before the deploy**, so these are not vacuous
passes. The `c5` test join was fully reverted (`memberUids` back to 2, member doc
deleted).

**Bonus evidence, unplanned:** the per-caller **18s cooldown fired on production
traffic** during verification — `429 RESOURCE_EXHAUSTED`, `retryAfterMs: 16562`,
because `c4` and `c5` came from the same caller back to back. Re-run from a fresh
caller for the real assertion.

> **NOTE FOR FUTURE DEBUGGERS.** A newly-created 2nd-gen callable returns **401 on
> the legacy `cloudfunctions.net` URL**. The Cloud Run URL
> (`https://joinneighborhood-<hash>-uc.a.run.app`) and the SDK's `httpsCallable`
> both work, and IAM was verified correct throughout (`allUsers` /
> `roles/run.invoker`, identical to `initiateSyncSession`). **Do not conclude the
> callable is broken** — check which URL the harness used.

**Planner unaffected** (targeted deploy did not touch it): flag still
`{write_jobs: true, uid_allowlist: [bench]}`, and the 21:05:09Z tick read
`planGameDayFires[LIVE:scoped(1)]`.



### F1 — CLOSED 2026-08-12. Full Game Day cycle on real hardware, first time anywhere.

`mlb_twins` / `gd_mlb_twins_401816500`, bench `.150`, `2.5.10+73` build 292,
`write_jobs` armed scoped(1).

| time (UTC) | event |
|---|---|
| 15:55:16.682Z | `startPlannedAt` **SET** — the pairing key, written for the first time ever |
| 17:10:00.000Z | start `fireAt` (first pitch 17:40 − `DEFAULT_LEAD_MINUTES` 30) |
| 17:11:02Z | start **dispatched** |
| 17:15:07Z | start **completed** — design running, `fx:52` blue→red |
| ~20:27Z | ESPN final → `consecutiveFinalPolls` 0 → **1**, and it PERSISTED |
| 20:30:34.247Z | counter → **2**, `REQUIRED_FINAL_POLLS` met, **GUARD 0 passed legitimately**, `plan_end reason="confirmed_final"` |
| 20:30:36.893Z | `endFiredAt` SET; end job `{"ps":2}` dispatched → completed |
| 20:31Z | bench `on=False`, both segments off — **restored to base** |

**GUARD 0 discriminated in the same tick**: Twins (`startPlannedAt` SET) fired;
stale Royals `...816490` (`startPlannedAt` ABSENT) refused, `end:no_start` still
bucketed. A guard that only ever refuses proves nothing — this one said yes and
no simultaneously, correctly.

**Too-early guard clear by 50 min**: MLB minimum 2h, elapsed 2h50m.

**Idempotency confirmed silently.** No second end fire: `endsPlanned` 0 on every
later tick, exactly two `plan_end` rows all day, three fire jobs, and `errors: 0`
throughout — a duplicate `create()` on the `_end` doc would have thrown and
incremented `errors`.

> **CORRECTION to the #66 record.** I described `{"ps":1}` as the harm. It was
> not. `baseRestorePayload` is time-aware and was **right both times**: `{"ps":1}`
> (NGL On) at 01:00 local, because the bench base state between the 20:23 ON and
> 06:22 OFF rows genuinely is on; `{"ps":2}` (NGL Off) at 15:30 local, because
> mid-afternoon it is off. **The harm in #66 was firing at all**, not what it
> sent. "Return to base" means *what the everyday schedule would be doing now*,
> not "turn off".

**Open, and what each gates:**

- **#67** — participation is advisory. The start fire lit BOTH channels despite
  `channels:[0]`; the end restore darkened both only because preset 2 asserts
  per-segment `on:false`. Product decision, not a bug.
- **#65** — 7 of 10 Game-Day-enabled accounts have no base layer. **This is what
  blocks the global arm, not F1.**
- Base-layer gate rebuild — the gate is informational-only and has never fired
  for anyone (all 10 enablements predate it).

`write_jobs` stays **armed, scoped(1)** overnight per Tyler. Rollback unchanged:
`write_jobs:false` or delete the doc; absent is false.



### `config/gameday_planner` — ARMED then DISARMED, 2026-08-12

| | |
|---|---|
| **armed (scoped)** | `05:45:21.359Z` — `{write_jobs: true, uid_allowlist: [bench]}` |
| **confirmed live** | `05:50:04Z` — `planGameDayFires[LIVE:scoped(1)]` |
| **INCIDENT** | `05:55:04Z` — end fire without a start, bench lights ON at 01:00 local. See **#66** |
| **DISARMED** | `13:16:34.680Z` — `write_jobs: false`. Confirmed `LOG-ONLY` at `13:22:35Z` |
| **current state** | **DISARMED.** `uid_allowlist` retained — the shape is proven; only the arm state changed |
| **rollback** | delete the document, or `write_jobs: false`. Absent is false; fails safe both ways |
| **re-arm** | **Tyler's decision.** Guard shipped and deployed; see readiness below |

The scoped flip did exactly its job. It was armed for ten minutes, produced a
real incident on the one rig chosen to absorb it, and that incident was
diagnosable from the corpus within minutes. Under the global arm originally
requested it would have been ten houses at 1am, seven without a floor.

### `config/gameday_planner` — original scoped-flip rationale, 05:45:21.359Z

```
{ write_jobs: true, uid_allowlist: ["wrQRUUKyXyc0deyuu0ORS6wsovO2"] }
```

**Blast radius: the bench account only.** Confirmed live at 05:50:04Z —
`planGameDayFires[LIVE:scoped(1)]`.

**ROLLBACK:** delete the document, or set `write_jobs: false`. Absent is false
(`planGameDayFires.ts:113` → `writeJobsPolicyFrom`), so it fails safe in both
directions.

**Why scoped and not global** — the S5 log-only audit (`gameday_plan_log`, 4
days, 3 plan rows) produced three findings:

- **F1** — the end-fire path has **never planned and cannot in log-only mode**.
  `startPlannedAt` is written only inside `if (writeJobs)`, and the
  consecutive-final counter persists only when
  `writeJobs || session.startPlannedAt`, so `consecutiveFinalPolls` never
  advances past 1 and `REQUIRED_FINAL_POLLS = 2` is unreachable. `endsPlanned:
  0` across the whole corpus is structural. `baseRestorePayload` executes for
  the first time in production.
- **F2** — a global flip would have driven a real customer immediately, not
  just the bench: `ecochran08@yahoo.com` had a `plan_start` for the same event.
- **F3** — that customer has **no base layer**, and a census found **7 of 10**
  Game-Day-enabled accounts in the same state. No floor if the never-executed
  end fire fails.

**Global arm is deliberately unreachable** until `uid_allowlist` is removed,
which should not happen until the end path has executed on the bench and F3 is
resolved for the affected accounts.

---

## Conventions

- **A simulator must fail everywhere the real component fails, or its passes are
  void.** The bench bridge-sim POSTs to its own stub and never read
  `controllerIp`, so it reported *delivered* for commands the real bridge
  refused with `ERROR: HTTP -1`. Three §4 runs "passed" that assertion while the
  feature had never once reached hardware (#70). A stub that is more permissive
  than the thing it stands in for does not merely miss bugs — it manufactures
  evidence against their existence. When stubbing a transport, enforce every
  precondition the real transport enforces, and encode each one as a test the
  day you learn of it.
- **Never edit a row after the build is uploaded.** Append a correction row instead.
- Record the Android versionCode from the **merged manifest**
  (`build/app/intermediates/bundle_manifest/release/.../AndroidManifest.xml`),
  **not** from pubspec — they drift.
- Fill the iOS build number **when the Codemagic build completes**, not when it
  is queued. `PENDING` is an honest value; a guess is not.
- **Builds are TAG-DELIBERATE (from 2026-08-12, #62).** iOS no longer builds on
  every push to `main`; it builds on a `build-*` tag
  (`codemagic.yaml` `triggering:` + the Codemagic UI webhook, changed together —
  the yaml cannot disable a trigger it does not own). **Record the tag alongside
  the SHA in every future row.** A tag is a human-chosen identity for a build,
  which the Codemagic build number is not (see P2-15) and the SHA alone is not
  memorable enough to be.

  ```sh
  git tag build-74 && git push origin build-74   # one tag, one TestFlight build
  ```

  **The first tagged build will be `build-74` or later.** `2.5.10+73` /
  Codemagic **292** predates the convention and has **no tag** — that is
  expected, not a missing field. Do not backfill tags onto earlier rows; a tag
  that never triggered a build would be a fiction.
- **Never instruct "build iOS from `<sha>`".** Codemagic auto-builds the **tip of
  `main`** on push, and the ledger row naming the SHA is itself a commit on
  `main` — so the instruction invalidates itself the moment it is written, and
  correcting it moves the tip again. Instead: record the SHA that fixes the **app
  bytes** and prove the tip has not disturbed them. A range is stable; a pinned
  SHA is not.
- **Prove that with a TREE COMPARISON, not a path-pattern grep.** Compare the
  trees that actually become the app; a grep for "docs-only" silently mislabels
  any new top-level directory as app code (a `scripts/` diagnostic tripped
  exactly this on +69). Empty output = the tip is the same build:

  ```sh
  for d in lib assets pubspec.yaml pubspec.lock android ios; do
    [ "$(git rev-parse <app-bytes-sha>:$d)" = "$(git rev-parse origin/main:$d)" ] \
      || echo "DIFFERS: $d"
  done
  ```
- **Never cut a release build from the shared working tree.** This repo is
  worked by parallel Claude sessions, so another window can save uncommitted
  work into your tree mid-build and it will be compiled in. That is not
  hypothetical — it burned **+70**, whose `.aab` contained a second session's
  unreviewed installer-entry work. Build from an isolated worktree at the exact
  merge SHA, and confirm its `git status` is empty before and after:

  ```sh
  git worktree add --detach /tmp/wt <merge-sha>
  cp android/app/google-services.json /tmp/wt/android/app/   # gitignored
  cp android/key.properties android/app/*.keystore /tmp/wt/android/…
  cd /tmp/wt && flutter build appbundle --release --obfuscate \
      --split-debug-info=build/debug-info/android
  ```
- **A burned versionCode gets its own row**, marked DO NOT UPLOAD, with why.
  Silently skipping a number leaves the next person unable to tell a burn from a
  bookkeeping error.
- **`git commit` commits the INDEX, and the index is shared between parallel
  sessions.** Staging your own files does not exclude what another window has
  already staged. A "docs-only" ledger commit on +71 swept in two file deletions
  another session had staged mid-refactor and pushed them to `main`. Always
  commit release/ledger changes with an explicit pathspec, which bypasses the
  rest of the index entirely:

  ```sh
  git commit -m "…" -- docs/BUILD_LEDGER.md      # not `git add` + `git commit`
  ```

  And read `git show --stat --name-status HEAD` before pushing — the file list
  is the only thing that catches this.
- **Test-channel distribution is a verification path, not an exposure.**
  Pushing to **TestFlight** or a **Play internal track** does NOT violate a
  hardware-gate hold, and a hold is not a reason to refuse one — a build that
  cannot reach a device cannot clear the gate that is blocking it, which is
  circular. What a hardware gate protects is **production exposure**:

  | held by the gate | not held by the gate |
  |---|---|
  | flipping `config/gameday_planner.write_jobs` | TestFlight |
  | public / open Play tracks, staged rollout | Play **internal** track |
  | merging gated feature work into a shipping build | installing on the bench rig or a tester device |

  Record the distribution in the row (`Uploaded: internal track only` is a
  distinct and useful value from `NO` and from `YES`).
- **A watcher asserts on STRUCTURED STATE, not on log text.** A grep over a log
  line is a prototype, not a monitor. Read the fields — Firestore documents, job
  `state`, a parsed JSON counter — and compare values.

  Three-strikes retrospective from the 2026-08-12 Game Day cycle, all one root
  cause (asserting on rendered text instead of state):

  | # | symptom | why |
  |---|---|---|
  | 1 | alerted every tick after the disarm | expectation was hard-coded to the previous operating mode |
  | 2 | re-reported known state on restart | truncated its own snapshot file, so cold start looked like a change |
  | 3 | reported a second end fire that never happened | unanchored grep matched the wrong field in the same line |

  Strike 3 is the one that matters: it produced a **false positive on a P0-shaped
  event** — a duplicate end fire, days after #66. The ground truth (`endsPlanned:
  0`, two `plan_end` rows, three fire jobs, `errors: 0`) took three independent
  checks to establish, all of which were available to the watcher and none of
  which it used.

  Rules: parse, don't grep; anchor and validate any pattern against a real
  payload BEFORE arming; seed state from the first observation rather than
  treating it as a change; and re-derive expectations when the operating mode
  changes rather than editing thresholds. If a watch fires three times without a
  real event, retire it — its alerts have stopped carrying information.
- **A worktree does NOT inherit gitignored runtime files.** Building or deploying
  from a fresh worktree silently lacks whatever `.gitignore` covers, and the
  failure never names the real cause. **Third instance:** the signing keystore +
  `google-services.json` (+71 Android build) and `functions/.env` (F-3 deploy —
  which failed as "no value for ANTHROPIC_API_KEY…", twelve unrelated secrets,
  with nothing pointing at the worktree). Before building or deploying from one,
  copy across: `functions/.env`, `android/app/google-services.json`,
  `android/key.properties`, `android/app/*.keystore`. They stay gitignored, so
  the worktree remains clean.
- Archive `build/debug-info/<platform>/*.symbols` per build. Never commit them.

---

### +77 SMOKE GREEN — Ellie's bug is dead, proven on the rig shaped to catch it

**2026-08-15 22:10Z, build 301 on device, bench `.150`.**

The test only means anything because the rig was first put into Ellie's
configuration: `seg1 rev=true`, captured into ladder presets 1 and 2 through the
gated sequence. Before that the bench ran both segments forward and **could not
fail this test**.

```
BEFORE  presets sha 9a5af8c6   preset1 seg1 rev=True   preset2 seg1 rev=True
        LIVE  ps=2  seg0 [0,128) rev=False   seg1 [128,290) rev=True

APPLY   one design from the +77 app, normal path

AFTER   LIVE  fx=49 pal=5 on BOTH segments   <- the design landed
        seg0 [0,128) rev=False
        seg1 [128,290) rev=TRUE              <- PASS
        bounds intact, presets sha 9a5af8c6 UNCHANGED

CYCLE   ps=1 -> seg1 rev=True
        ps=2 -> seg1 rev=True
```

**Three things pass, not one:**
1. **The apply did not clobber `rev`** — the #76 defect itself. Pre-fix, this
   exact action stamped `rev:false` and Ellie's channel ran backwards all evening.
2. **The ladder was untouched** — `presets.json` byte-identical across the apply,
   so nothing captured a geometry state into a durable slot.
3. **The reversal survives a load cycle** — the durability half. `rev` lives in
   the presets now, so a regression could not hide behind a base restore; it
   would persist rather than self-heal.

**Free extra verification from the power cycle** that preceded the smoke
(Tyler's glitch-replication attempt): the two-segment layout **survived this
reboot** — unlike 2026-08-14, where a reboot collapsed it to one. Collapse is
therefore INTERMITTENT, not deterministic, which makes it harder to catch by hand
and is precisely why the gate's total-loss branch exists.

One observation worth keeping: the reboot left live `seg1 rev=FALSE` while the
presets held `true`, with `ps=-1` (boot state, no preset loaded). Loading `ps=2`
restored it. **Starting the smoke from that state would have produced a false
FAIL** — "rev is false" for a reason unrelated to #76. The starting state has to
be established, not assumed.

**GREEN FOR DISTRIBUTION.**

### GREYED-CHANNEL INCIDENT CLOSED 2026-08-17 — no repair was performed, because none was needed

**The rig is whole and was never broken.** Capture `20260817T014938Z`, bench `.150`:

```
uptime=100700s  ver=0.15.1   presets sha256=9a5af8c6df5a23ae  (IDENTICAL to the +77 smoke)
seg0 [0,128)   len=128  on=True rev=False grp=1 spc=2  fx=0
seg1 [128,290) len=162  on=True rev=True  grp=1 spc=0  fx=83
bus0 start=0 len=128 pin=[2] | bus1 start=128 len=162 pin=[14] | total=290
```

**Recorded precisely, because three things in the closeout as drafted did not happen:**

| claimed | actual |
|---|---|
| seg1 degenerate / zero-length | seg1 is **162 px, `on`, `rev:true`** — bounds match bus1 exactly |
| +77 greyed it via a zero-length drop | **no such code exists** — `deviceChannelsFromConfig` maps every bus unconditionally; greying is participation-only |
| repair routed through provisioning; `rev:true` survived it | **no repair was run.** The gate never executed. `rev:true` survived because nothing touched it |

**The gate did not stand aside on a legal single-segment shape — it never ran at all.** There was
no second segment missing to classify. Recording a `match` verdict here would put a gate execution
in the ledger that did not occur, and the gate's whole value is that its verdicts are trustworthy.

**`rev:true` and the Ellie shape are intact** — verified by direct read, not inferred from a repair.
`uptime` puts boot at ~2026-08-15 21:51Z against the smoke's 21:54Z: the **same boot**, ~3 min of
counter drift across 28 hours. Layout and ladder have been continuous since the smoke.

**Actual cause of the grey-out: participation.** `participating_channels=[0]` narrows the apply to
seg0, so `seg id:1` is **omitted** from the payload — never sent `on:false`, which is why channel 2
held its previous design instead of going dark. The capture corroborates: seg0 `fx=0`, seg1 `fx=83`.
The gate dates to `d8691be` (2026-05-21) and ships in every build including the live +76.

**Reclassification — the 2026-08-14 collapse was self-inflicted, and a single-channel design was NOT
applied before it.** Per this ledger's own incident arc: the antecedent was **my `psave`/`pdel`
against scratch slot 245**, which malformed `presets.json`; the reboot that followed collapsed
`seglc` 2 → 1. The proposed design-apply mechanism does not fit it.

**#72's intermittent-collapse phantom therefore shrinks — by a different route than expected.** Not
because a design apply explains the sightings, but because the one well-documented sighting was
caused by a bench experiment. What remains is the **08-15 non-event** (a power cycle the layout
survived) and roster flips + config disables.

**One real hazard found while capturing (#89):** `lumina_custom_effects.dart` overwrites hardcoded
segment bounds and its final frame swallows the strip into `seg0 [0,290)` — **the exact recorded
collapse signature**. It is **caller-less**, so it caused nothing, and is filed as latent rather
than as this incident's cause. Also **#88**: four `grp`/`spc` emitters the #76 strip missed, one
interactive — `spc=2` on seg0 in the capture above is that leak on hardware.

**Distribution posture unchanged: +77 STANDS.** The greying is old participation behavior, not new
honest behavior; the defect predates +77 and ships in every prior build, so holding protects nobody.

### FIRST FULL UNATTENDED CYCLE UNDER THE POST-#76 STACK — verified 2026-08-17

**Tyler = `wrQRUUKyXyc0deyuu0ORS6wsovO2`. Two clean cycles, both on 2026-08-16.**
Correction to the framing: the verified end-to-end cycle is **`mlb_twins`
(`gd_mlb_twins_401816555`)**, not Royals, and it ran **yesterday**. Today's log
(`2026-08-17`) has **zero plan_start rows for anybody** and no Tyler rows at all.
The Royals cycle is real but earlier — `gd_mlb_royals_401816544`, planned 08-15,
ended 08-16T03:55Z.

**Plan rows → command execution, paired:**

| event | plan row | command | delta |
|---|---|---|---|
| `mlb_royals_…544` | `plan_end` `03:55:04.807Z` `confirmed_final` | `fire_job` `03:56:08.915Z` `{"ps":1}` | +64s |
| `mlb_twins_…555` | `plan_start` `17:40:00.000Z` ch `[0]` 133 B `partitioned:true` | `fire_job` `17:40:03.362Z` | **+3s** |
| `mlb_twins_…555` | `plan_end` `21:20:12.654Z` `confirmed_final` | `fire_job` `21:21:03.939Z` `{"ps":2}` | +51s |

**START FIRE, VERBATIM** (`2026-08-16T17:40:03.362Z`, `status=completed`):

```json
{"on":true,"bri":200,"seg":[
  {"id":0,"on":true,"fx":0,"sx":128,"ix":128,
   "col":[[255,255,255,0],[255,255,255,0]]},
  {"id":1,"on":false}]}
```

- **#67 FULL PARTITION — PASS.** Participation is `[0]`; seg1 is **named and
  explicitly `on:false`** rather than omitted. Every channel asserted. The row's
  `bytes:133` matches the stored payload exactly, so the planner's accounting and
  the wire agree.
- **#76 CLEAN — PASS.** `fx`/`sx`/`ix`/`col` only. **No `rev`, `mi`, `grp`, `spc`,
  `of`, no `start`/`stop`.** Contrast Ellie's pre-strip 08-13 payload, still in her
  queue, which carries `"grp":1,"spc":0,"of":0,"frz":false` — the shape the strip
  removed.
- **#88 note:** `grp`/`spc` are **absent**, not asserted. This cycle **predates** the
  assert-to-`1`/`0`-when-unused rule, exactly as expected. Absence now, assertion is
  the future state.
- **GUARD 0 (#66) — PASS, and visible.** `end_skipped_no_start` rows appear for
  `…twins_401816555` on both 08-15 and 08-16 **before** its start was planned, then
  stop once the start exists. The guard refused an unrequested end and said so.
- **Base restore picked the right rung, twice.** Royals → `{"ps":1}` (NGL **On**) at
  03:56Z = **22:56 CDT**; Twins → `{"ps":2}` (NGL **Off**) at 21:21Z = **16:21 CDT**.
  Lights on at night, off in daylight. The ladder chose by time of day, not by habit.

**Device state across the window** (post-cycle capture `2026-08-17T01:58:27Z`):
`presets sha256 9a5af8c6df5a23ae` — **unchanged** from the closeout baseline, so the
cycle psaved nothing. `seg0 [0,128)`, `seg1 [128,290)` both present; **`seg1 rev=true`**.
The layout's continuity here is **native, not repaired** — no repair has ever been
performed on this rig.

#### Allowlist removal: this cycle is necessary evidence, and it is NOT sufficient

**Tyler is the only un-scoped uid.** Every other account's `plan_start` carries
`scopedOut:true` — planned, then suppressed by the `write_jobs` uid allowlist. So
"the fleet planned 7 starts on 08-16" means **one** of them reached hardware.

**The blocker, straight out of the same log:**

```
uid=Ayf0rqwN  ch=[0,1,2]  partitioned=FALSE  note=partition_unavailable   08-15
uid=Ayf0rqwN  ch=[0,1,2]  partitioned=true                                08-15
uid=Ayf0rqwN  ch=[0,1,2]  partitioned=FALSE  note=partition_unavailable   08-16
```

A three-channel account whose partition facts **come and go between ticks**. Remove
the allowlist today and that account fires an **unpartitioned** payload at a
3-channel house — #67's exact failure mode, live, on a schedule nobody is watching.
Intermittent is worse than absent: a pre-flight check would have passed it on 08-15.

**Second limit, stated plainly so it is not glossed:** every Tyler fire is
`channels:[0]` on a 2-channel rig. It proves the pipeline and the 2-channel
partition. It does **not** exercise 3+ channels, which is precisely where
`partition_unavailable` lives.

**Verdict: bank it as the pipeline's first clean production-shaped cycle. The gate
for widening is `partitioned:true` on EVERY plan_start for a candidate uid across
consecutive ticks — not this cycle's success.**

#### Celebrations, 4th check: still silent

Tyler's newest 12 commands: `fire_job` ×3, `health_probe`, and un-sourced writes.
**Zero `game_day`-sourced commands.** His `mlb_royals` config has
`score_celebration_enabled=true`, so the config gate would have passed — consistent
with the trace earlier this session, which found the blockers upstream (poller armed
off the sports-alert list, `_sessions` unpopulated by a manual start). That trace DID
run and its verdict stands; this is a fourth confirming data point, now on build 301.
**The fix is still unmerged on `feat/gameday-unified-monitoring`.**

### RECORDS — method, evidence roles, and provenance (2026-08-17)

Companion to the closure entry below; that entry carries the numbers, this one
carries what they are *for*.

#### 1. Method line

> **Measure the population, don't generalise the sample.**

The unreachable-feature verdict came from one config. The population says the
opposite:

```
50 game_day_autopilot configs, all users
PRESENT = 49  (true 49 / false 0)
ABSENT  =  1  -> wrQRUUKy / mlb_twins, 4-key stub
live setter: setLiveScoring -> Live Scoring switch, game_day_screen.dart :385 / :1411
```

The stub sat in the one seat that made it look systemic — it is the config whose
cycle actually ran on 08-16. **A sample drawn from the thing you are investigating
is the least representative sample available**, because investigation goes where
the anomaly is. Counting cost one query.

#### 2. The Ellie control row carries TWO findings, not one

| | |
|---|---|
| same game, same tick, `skip_day_games=false` | `plan_start` `2026-08-16T19:37:00Z` |
| Tyler, `skip_day_games=true` | skipped, **no row written** |

- **Evidence for #90.** One per-config field decided a game, and the planner
  recorded nothing. `daylight_game` bumps a counter and `continue`s. The 08-16
  summary reads `daylight_game: 9` and names no team. Correct behaviour is not
  the same as accounted-for behaviour.
- **Evidence for the allowlist file.** Her config **plans on real games** —
  ESPN resolution, participation, partition all succeeded and produced a
  `plan_start`. **Only `scopedOut:true` stops it reaching hardware.** She is a
  ready candidate whose readiness is already demonstrated, not assumed. Weigh
  against `Ayf0rqwN`, whose partition facts flip between ticks — the two
  together are why widening must be per-uid on observed `partitioned:true`
  across consecutive ticks, not a fleet flip.

#### 3. Provenance — finding f is RELAYED-WITHOUT-PROVENANCE

A fixed-IP fanout (unawaited HTTP to `192.168.1.11` / `.222`) was relayed for
deletion. **It does not exist in any tree reachable from here.** Searched:

```
main lib/ + functions/src/          0 hits
feat/gameday-unified-monitoring     0 hits in lib/  (2 hits are TEST FIXTURES:
                                    connection_method_screen_test, handoff_verification_test)
lumina-gameday .-f3 .-r75 .-voice .-sunrise-off .-p0-3   0 hits each in lib/
no `192.168.*.222` literal anywhere at all
```

The Game Day worker has one `http.post` (to `$_functionsBaseUrl/applySyncPattern`,
resolved) and one `unawaited` (the 15 s revert timer). **Recorded as relayed
without provenance; Tyler is putting the existence question to the originating
window.** Nothing was deleted. If it is real it is real somewhere else, and the
deletion should happen there — the concern itself is sound and not disputed.

### THE TWO SILENT GAMES — CLOSED 2026-08-17. Both questions answered; the
### fleet-wide premise did not survive measurement.

**Dodgers 08-13 and Royals 08-16 are CLOSED.** Neither was a celebrations failure,
and in neither case did execution reach `onScoreAlertEvent` at all.

| game | first unsatisfied condition | verdict |
|---|---|---|
| **Dodgers 08-13** | `start_time_passed` — config created after its own fire time | no show → no session |
| **Royals 08-16** | `daylight_game` — Tyler's `skip_day_games=true`, first pitch 15:07 CDT | **worked as configured** |
| **Twins 08-16** (the cycle that ran) | stub config lacks `score_celebration_enabled`; the worker mirror reads `?? false` | armed off |

Ellie is the control for the Royals case: **same game, same tick,
`skip_day_games=false`, and she received a `plan_start` at `19:37Z`.** One
per-config field decided it. Both planner skips are **silent** — counter bumped,
no row (C10, and its twin **#90**).

#### The "absent fleet-wide" premise is inverted — measured, not assumed

```
50 game_day_autopilot configs across all users
PRESENT = 49   (value true = 49, false = 0)
ABSENT  =  1   -> wrQRUUKy / mlb_twins, a 4-key stub
```

**`score_celebration_enabled` is present and `true` on 49 of 50 live configs, and a
live setter exists** — `setLiveScoring`
([game_day_autopilot_providers.dart:692](../lib/features/autopilot/game_day_autopilot_providers.dart#L692)),
wired to the **Live Scoring switch on the Game Day team card**
(`game_day_screen.dart:385`, `:1411`). The feature is **not** unreachable by design
accident; it is armed at the config layer fleet-wide.

**The single absence is Tyler's own `mlb_twins` — which is exactly the config whose
cycle ran on 08-16.** A 1-in-50 stub sat in the one seat where it would be mistaken
for a fleet-wide condition. The branch's #79 saw the same stub and generalised from
it; the count is the correction.

**What that leaves standing.** The real fleet-wide blockers are unchanged and are
NOT the config field: the score poller is armed off **sports-alert** configs, and
`_sessions` is never populated by a manual start. Blocker 3 narrows from "celebrations
default off" to **"a stale or stub-derived mirror reads `?? false` against a model
that defaults `true`"** — the two layers disagreeing, which is the same defect the
count now bounds to one config.

#### Not filed: the fixed-IP fanout

Asked to delete an unawaited HTTP fanout to hardcoded `192.168.1.11` / `.222` from
the worker this week. **No such code exists in this repository.** No literal
matching `192.168.*.11` or `192.168.*.222` appears anywhere in `lib/` or
`functions/src/`, and none in the autopilot / sports-alerts / neighborhood service
trees at all. The Game Day worker has exactly **one** `http.post`
([:554](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L554)) —
to `$_functionsBaseUrl/applySyncPattern`, the Cloud Function, resolved not hardcoded —
and exactly **one** `unawaited` ([:173](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L173)),
the 15-second revert timer. **Nothing was deleted, because there is nothing to
delete.** If it exists, it is in another window's tree — the ask stands there, not here.

## 2.5.10+77 — #76's cap closed and wired; geometry stops being fabricated

| Field | Value |
|---|---|
| **Tag** | **`build-77`** — points at the docs-only commit following `100174a`. |
| **Git SHA (app bytes)** | **`100174a`** — `chore(release): bump to 2.5.10+77`. **iOS↔Android join key.** |
| **App-bytes ancestry** | `2aa5c15` (+76) **+** the #76 builders, the non-convergence guard, the geometry gate, its wiring, and #78's client half. |
| **Ledger SHA (tagged)** | The `build-77` tag. `git diff --stat 100174a build-77 -- . ':(exclude)docs'` is EMPTY. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **77** — `kStaffAuthTelemetryAppVersion` moved in the same commit. |
| **Android artifact** | `app-release.aab` · **68,331,830 bytes** · `jarsigner -verify` → **jar verified** · merged manifest `versionCode="77"` / `versionName="2.5.10"` · built 2026-08-14 from isolated worktree `lumina-b77` at tag `build-77`, `git status` empty **before and after**. Obfuscated; symbols at `build/debug-info/android/`. **versionCode 77 CONSUMED.** |
| **iOS** | **Build 301** — tag-triggered from `build-77`, commit **`4f3ab11`**, confirmed against the Codemagic build record 2026-08-15. **No manual twin this time** (+76 produced 297 tag + 298 manual; +77 produced one build from one tag). Chain COMPLETE. |
| **Uploaded** | `<PENDING>` |
| **Supersedes** | **+76** |

**Content gate — six commits, all attributed, nothing unexpected:**
`70726ac` #76 builders · `e1332b6` non-convergence guard + root-on ·
`65ff312` geometry gate · `1aef6d1` gate wiring · `27471bf` #78 server ·
`f4477a7` #78 client.

**The sports-alerts restructure is NOT in this build** — another window's work,
not on `main`. The expectation was corrected before the bump rather than after,
which is the only reason this row is trustworthy.

**#78 shipped ORDERED, server first.** `joinNeighborhood` writes `null`
(deployed `--only functions:joinNeighborhood`) before the client stopped
fabricating. An old client reading `null` falls back to its own 300/15.0 —
today's behaviour exactly. Shipping the client first would have left a +77
client reading old member docs and still seeing a real-looking 300. The client
half had the SAME defaults as `fromFirestore` fallbacks, so without it the
server fix would have been inert.

**The line #78 draws:** stored values stop lying; render-time code may assume a
number, but locally, named (`kAssumedLedCount`), and never written back. The
member editor now prefills EMPTY when unknown — a pre-filled 300 invites the
user to press save and promote a placeholder into a "confirmed" measurement.

> **MY MISS, recorded as an UNFLAGGED OMISSION — not a deferral.** #78's interim
> was item 5 of the +76 build prompt. I did W1–W4, the bump and the tag, and
> simply did not do it, and it did not appear in my +76 report as outstanding.
> A deferral is a decision; this was neither decided nor visible. It surfaced
> only because +77's content gate compared against an expectation. **The audit
> lesson: a build report must enumerate the prompt's items and their status,
> not just describe what was built** — describing the work cannot reveal work
> that is absent.

**BENCH IS NOW ELLIE-SHAPED, permanently.** Via the gated sequence — bounds
verified `0[0,128) 1[128,290)`, then `seg1 rev:true` live, then both ladder
presets re-saved with `ib:true`:

```
preset 1  root on=True   seg0 rev=False  seg1 rev=TRUE
preset 2  root on=False  seg0 rev=False  seg1 rev=TRUE
ps=1 -> seg1 rev=True     ps=2 -> seg1 rev=True     presets parse clean, 18 slots
```

`rev` now **survives a preset load**, which is the exact behaviour that reverted
it on 2026-08-14 and the reason the rig could not previously catch #76's class.
The rig lives in the configuration that catches the bug.

**Suite 2311 / 3 skipped / 0 failed** (from 2302). `analyze lib/ test/`: 0
errors. Functions 392 / 17 unchanged.

---
## 2.5.10+76 — every legible server refusal gets a customer surface

| Field | Value |
|---|---|
| **Tag** | **`build-76`** — points at the docs-only commit following `2aa5c15`. |
| **Git SHA (app bytes)** | **`2aa5c15`** — `chore(release): bump to 2.5.10+76`. **iOS↔Android join key.** |
| **App-bytes ancestry** | `7796a40` (+75) **+** W4, the gate reader, W2+W3, W1. |
| **Ledger SHA (tagged)** | The `build-76` tag. `git diff --stat 2aa5c15 build-76 -- . ':(exclude)docs'` is EMPTY. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **76** — `kStaffAuthTelemetryAppVersion` moved in the same commit. |
| **Android artifact** | `app-release.aab` · **68,316,478 bytes** · `jarsigner -verify` → **jar verified** · merged manifest `versionCode="76"` / `versionName="2.5.10"` · built 2026-08-13 from isolated worktree `lumina-b76` at tag `build-76`, `git status` empty **before and after**. Obfuscated; symbols at `build/debug-info/android/`. **versionCode 76 CONSUMED.** |
| **iOS** | **Build 298** (manual, Branch `main`, commit `f7323c2`) — the artifact TestFlight served and the one on-device. **Build 297** is its tag-triggered twin (GitHub webhook, tag `build-76`, same commit `f7323c2`). **Both are valid +76 artifacts, byte-identical in source.** Confirmed from the Codemagic build records 2026-08-13. |
| **Uploaded** | `<PENDING>` |
| **Supersedes** | **+75** |

**Theme: a refusal nobody sees is still a silent drop.** Three server-side
guards shipped legible refusals in the preceding days — #69/#71 consent, the
readiness gate, #67's partition — and every one of them was legible to the
server log and to nobody else.

**W4 — the R2 fact** (`b0bfa05`). The healer measures
`base_ladder_asserts_segments` on the LAN connect it already performs: do
presets **1 and 2**, the only two `baseRestorePayload` can load, each carry a
`seg` array with an explicit `on` for every device channel? `null` is not
`false` three times over (no bus list, `PresetsReadState.unknown`, relay rather
than LAN) because `false` moves an account into log-only and a failed GET must
never do that. `deviceEmpty` IS `false` — we looked, there are no presets. A
segment present but SILENT about `on` counts as not asserted: precisely the
inherited-state case #67 exists to eliminate. Zero-mutation on reconnect is
pinned, since the disposition mirror nearly broke the equivalent guarantee.
**This begins hardening R2 per account with no server change — the gate already
consumes the field.**

**W2 — the gate's client state** (`8bd6237`, `5d50353`). Eight of ten live
accounts are held in log-only and saw a UI that looked armed. The banner
reflects the planner's persisted verdict, names the missing item, and offers the
one fix performable in-app. Armed renders NOTHING; graduation is said ONCE,
device-locally. Advisory renders nothing at all — `gated_no_ladder_unknown` is
ours to collect (W4), not the customer's to fix. The reader never invents a
refusal: absent, empty and malformed all read as armed.

**W3 — the badge** (`5d50353`). Only the UPCOMING branch consults the gate; live
and final are reports of fact and cannot be wrong about the future. The verdict
is READ at the call site rather than polled by the badge, so its own cadence
stays uncoupled — the coupling that once froze it for celebrations-off users.

> **W3 SCOPE, and the residual stated plainly.** Gated-state only. `will-fire`
> needs `users/{uid}/fire_jobs` and `skipped(reason)` needs a per-user mirror of
> skip reasons; **neither is client-readable** — no rule matches either path and
> there is no recursive wildcard under `users/{userId}`. Wiring them needs a
> rules deploy, which moves on its own clock per the +74 lesson rather than
> riding a client build. **Residual: a non-gated account whose specific game was
> skipped still shows plain "Today".** That is incomplete honesty, not a false
> promise — that account does fire, just not for that game. Filed as follow-up;
> the fleet-wide `gameday_plan_log` must never be client-exposed.

**W1 — the refusal surface** (`5cb3852`, #73). `initiateSyncSession` has **no
foreground caller**: at the moment of refusal there is no user, no BuildContext
and no Riverpod, so a snackbar is structurally impossible. Persist always,
notify for `consent_blocked`/`consent_missing`, **silent for**
`skip_next_active` — they asked to skip it. Dedup keyed **(eventId, reason)**:
the notification announces the TRANSITION, the banner shows the STANDING state,
pinned by a test running ten worker attempts across one blocked night and
asserting exactly one announcement. The key excludes message and timestamp, so a
reworded server message cannot re-notify. **Permission gates immediacy, never
legibility** — persistence runs first and unconditionally, every notification
failure path is swallowed, and with notifications denied the banner is fully
functional. No new dependency.

**The 297 "gap" is resolved, and my reading of it was wrong.** I recorded 295 → 296 → 298 as an
unexplained gap that *weakened* the no-stray-build inference. The opposite was true: **297 IS the
tag build**, fired by the GitHub webhook on tag `build-76` exactly as the #62 pipeline is designed
to. 298 was a manual duplicate started at 12:32 from Branch `main`, on the same commit. The
tag-only trigger has not drifted; there was never a stray push-build. Recorded because the
inference, not just the number, is what needed correcting — a numbering gap can mean a build
succeeded twice as easily as it can mean something ran that should not have.

> **CONVENTION — prefer re-running the TAG build over a manual `main` start.** A manual build
> from Branch `main` is safe only while `main`'s tip still equals the tag. Here it did, so 297 and
> 298 carry identical source. But `main` moved within the hour (five docs-only commits followed
> `f7323c2`), and a manual `main` build started after that would carry a different SHA — same app
> bytes, different identity, and the ledger's join key stops matching the artifact. The tag is the
> deliberate act; re-run it rather than reaching for the branch.

> ⚠️ **OPEN — BOTH BUILDS "finished with post-processing failed".** The same step failed on 297
> and 298, which makes it systematic rather than a flake. Submission itself succeeded — 298 reached
> TestFlight and the device — so the failure is downstream of the build and upload. Suspected
> dSYM/artifact publishing. **Step name pending from the log**; filed when Tyler reports it. Until
> then the symbol files for +76 should not be assumed archived on Codemagic's side — the local
> Android `build/debug-info/` symbols are unaffected.
**Suites:** Dart **2272 / 3 skipped / 0 failed**, from +75's 2218 — +23 (W4),
+15 (gate reader), +16 (W1). `flutter analyze lib/ test/`: **0 errors**.
Functions unchanged at **392 / 17** — no server code in this build, and **no
deploys were performed**.

**Carried forward:** the +75 on-device join smoke is still PENDING. One
fresh-account invite-code join on +76 closes it for both builds.

---
> ### THE JOIN-SMOKE ACCOUNT WAS A CUSTOMER — SMOKE VALID, JOIN REVERTED
>
> The account used was **`YcSGiwesJuS7Qsh1aql0Qh1jqYh2` = stegall.s@yahoo.com** — not a fresh
> test account. It is a **real customer**, row 6 of the Game Day census, with a real controller
> (`80_f3_da_b3_b8_20`, `192.168.1.250`).
>
> The smoke result stands: the join path works on device, which is what it was there to prove.
> What does NOT stand is the reason `sync_fanout` was scoped to this group. The flag record says:
> *"Chosen because it is bench-created and its only members are tyler.honeycutt and
> nex-genadmin — **no customer**."* **That premise is now false.**
>
> Their member doc is `participationStatus:"active"`, so the fanout loop would serve them, and
> `resolveMemberTargets` would resolve `192.168.1.250` from their controllers subcollection.
> **The next crew broadcast in the demo group would write commands to a customer's lights.**
> Not spontaneous — a fanout only runs when someone initiates one — but the next `fanout-verify`
> run would do it.
>
> They have no `syncConsent` doc, so `initiateSyncSession` would skip them; `applySyncPattern`
> does not consult consent at all, so the fanout path is the exposed one.
>
> **REVERTED 2026-08-13, verified in both places.** Tyler confirmed Blue Line was a genuine
> non-member, so the smoke is VALID and the flag is closed for +75 and +76. The membership was
> then removed, because a commercial customer's bar is not a rig asset:
>
> ```
> memberUids (2): wrQRUUKy, KOerj0ui      Blue Line present: false
> members/{blueline} exists: false        member docs remaining: 2
> ```
>
> **Blue Line's own state untouched**, checked before and after: 1 controller
> (`80_f3_da_b3_b8_20`), 75 user-doc keys, 3 Game Day configs, `gameday_gate_blocking` unchanged
> at `["gated_no_facts"]`. Crews they belong to: 0 — the demo crew was their only one, which is
> why removal restores them exactly to where they started. The member doc had no subcollections,
> so nothing was orphaned.
>
> `arrayRemove(U)` — the ELEMENT, not `[U]`. **#74 is one week old** and this is the same call
> shape that took `initiateSyncSession` down.
>
> **The fanout scoping premise is restored:** the demo group's only members are again
> `tyler.honeycutt` and `nex-genadmin`, which is what `config/sync_fanout`'s allowlist entry
> claims.
>
> **STILL WANTED: a dedicated outsider-uid rig asset.** A known clean non-member has been needed
> three times this week. Five-minute setup whenever Tyler makes one — a purpose-built test
> account, recorded here as a rig asset, so the next smoke never reaches for a customer.

## 2.5.10+75 — F-3's app half ships; the +74 join regression is closed

| Field | Value |
|---|---|
| **Tag** | **`build-75`** — points at the docs-only commit that follows `7796a40`; app bytes are `7796a40`. |
| **Git SHA (app bytes)** | **`7796a40`** — `chore(release): bump to 2.5.10+75`. **iOS↔Android join key.** |
| **App-bytes ancestry** | `850c0db` (+74) **+** the rebased F-3 app half **+** join-navigation **+** leave-sync restore. |
| **Ledger SHA (tagged)** | The `build-75` tag. `git diff --stat 7796a40 build-75 -- . ':(exclude)docs'` is EMPTY. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **75** — merged manifest. `kStaffAuthTelemetryAppVersion` moved in the same commit. |
| **Android artifact** | `app-release.aab` · **68,283,657 bytes** · `jarsigner -verify` → **jar verified** · built 2026-08-13 from isolated worktree `lumina-b75` at tag `build-75`, `git status` empty before **and** after. Obfuscated; symbols at `build/debug-info/android/` (arm, arm64, x64). **versionCode 75 CONSUMED.** |
| **iOS** | **Build 296** — reported by Tyler 2026-08-13 for the `build-75` tag. **Trigger and checked-out SHA NOT independently confirmed:** this session has no Codemagic credential, so "triggered by the tag, built from `0769e70`" rests on the tag-only webhook plus Tyler's attribution, not on a read of the build record. Corroboration, not proof: +74 was 295 and +75 is 296 with no gap, which is consistent with no stray push-build having run between the two tags. |
| **Uploaded** | **DISTRIBUTED 2026-08-13** — Play **closed testing track** + **TestFlight** (iOS 296, tag `build-75`). Supersedes +74 on BOTH tracks. |
| **Supersedes** | **+74** (join regression) — superseded on both tracks. |
| **OPEN AT DISTRIBUTION** | ✅ **CLOSED 2026-08-13 — on-device join smoke PASSED on +76 (iOS 298).** A non-member account joined the demo crew by invite code; the app confirmed "Welcome to demo" and the server shows `memberUids` at 3 with an `active` member doc. The +74 regression path is verified fixed ON DEVICE, for +75 and +76 both. Was: ⚠️ pending. Posted on the strength of the F-3 c5 callable proof in production (membership written same-batch, server-side). The app's UI wiring TO that callable is unit-tested (`neighborhood_join_reflects_in_ui_test.dart`, 6 cases) but **has not been exercised on a device**. Closed by exactly one thing: **a fresh-account join by invite code on +75**. Until then the claim is "the server accepts the join" — not "the app performs it". |

**Why this build exists**

+74 shipped F-3's rules live with its app half stranded on an unmerged branch.
Reproduced against production with CLIENT credentials — 403 PERMISSION_DENIED for
a non-member **and** for a member. Joining a crew was broken for every caller.

**Rebase resolution, file by file** (`rebase/f3-onto-main`, 5 commits replayed +
2 cherry-picked, zero conflicts):

- `functions/src/applySyncPattern.ts` — **main's copy survives, verified by
  reading.** `mergeDenormTargets` / `db.getAll(...)` / `no_address` (#70) and
  `readSyncFanoutPolicy` / `fanoutsForGroup` / `group_allowlist` (scoped fanout)
  all present. The "keep main wholesale" policy was never actually exercised:
  **the F-3 branch never touched this file.** The 172-line diff reported on
  2026-08-13 was main being AHEAD, not the branch diverging — a distinction worth
  recording, because "no conflict" here is structural, not luck.
- `lib/features/neighborhood/` — branch's version taken. Callable
  `joinNeighborhood`, `/neighborhood_public` discovery; the client-side
  `where('inviteCode')` + `arrayUnion([uid])` self-insert is gone. The nearby-groups
  overlap auto-merged correctly: the public card calls `joinPublicGroup(group.id)`,
  not the invite-code path, which is right because the projection carries no code.
- `firestore.rules` — **byte-identical to `a83193f`, the source that was actually
  deployed.** `git diff a83193f HEAD -- firestore.rules` is empty, so main and
  production have converged and the next rules deploy cannot silently drift prod.
- `lib/features/neighborhood/neighborhood_sync_engine.dart` — rebased copy has 10
  lines the branch lacked: main's S3b `publishParticipatingChannels`. Main's work
  preserved, not clobbered.

**Suite reconciliation** — Dart **2218 passed / 3 skipped / 0 failed**, from
+74's 2165. Every one of the +53 accounted for:

| Source | Δ |
|---|---|
| `test/bench/fanout_verify_test.dart` (new) | +33 |
| `neighborhood_join_reflects_in_ui_test.dart` (new) | +6 |
| `neighborhood_sync_engine_teardown_test.dart` (12 → 15, **modified, not new**) | +3 |
| `pre_sync_scene_persistence_test.dart` (new) | +11 |
| **total** | **+53** |

The join-membership branch contributes **20**, not the +21 carried in the plan.
Not a loss: all three of its test files are byte-identical to the branch tip
(`git diff fix/neighborhood-join-membership HEAD -- <files>` empty), so nothing
was dropped in the cherry-pick — the +21 figure was simply imprecise. Functions
suite **313 / 13 suites** (was 291 / 12; `joinNeighborhood.test.js` adds 22).
`flutter analyze lib/ test/` — **0 errors**.

**PRE-DISTRIBUTION CONTENT GATE** — `git log 850c0db..build-75 -- lib functions
firestore.rules`, every commit named:

| Commit | Workstream |
|---|---|
| `7796a40` | release — version bump |
| `6caefa5` | join-membership — leave-sync restore |
| `bcf6ea3` | join-membership — join-navigation / UI reflect |
| `71e7fb8` | F-3 (rebased from `a83193f`) |

Four commits, nothing unattributed, nothing unexpected.

**Must-be-present, read AT THE TAG** (`git show build-75:<file>`), not inferred
from the merge:

- `functions/src/applySyncPattern.ts` → `mergeDenormTargets`, `db.getAll(...)`,
  `no_address` (#70 `06e36dc`) and `readSyncFanoutPolicy`, `fanoutsForGroup`,
  `group_allowlist` (scoped fanout `dab5b27`). Both commits confirmed ancestors
  of `build-75`. **Neither reverted.**
- `lib/features/neighborhood/neighborhood_service.dart` → `httpsCallable(
  'joinNeighborhood')`, `joinPublicGroup`, `/neighborhood_public`. F-3's app half
  is in the build.

**A trap worth recording: `a83193f` is NOT an ancestor of `build-75`.** The
rebase reshaped it into `71e7fb8`; the content survives, the hash does not. An
ancestry test on a deployed SHA therefore raises a FALSE ALARM after any rebase.
The correct test is per-path content equality —
`git diff a83193f build-75 -- firestore.rules functions/src/joinNeighborhood.ts
functions/index.js` → **0 lines on all three**. Do not diff whole directories for
this: the target legitimately carries other work, so a non-empty directory diff
proves nothing in either direction.

**RULES FREEZE LIFTED as of `0769e70`.** Rules deploys from `main` are safe —
main and production are equivalent by source and by behaviour (below).
**FUNCTIONS DEPLOYS REMAIN FROZEN until the #69 prompt.**

### Pre-distribution smoke plan (Tyler, on device, against production)

Nothing is posted to either track until these pass. This is the +74 lesson: that
build was internally consistent and still shipped a dead join path, because no
one exercised the path end-to-end before distribution.

**a. Build-number check FIRST, before any testing.** Read what Codemagic reports
for the `build-75` tag, then confirm the installed app shows the SAME number
(Settings → version). On 2026-08-11 TestFlight served a stale 288 while 291 was
the real build and a hardware run was attributed to the wrong artifact. If the
numbers differ, STOP — every later result is unattributable.

**b. Join a crew by invite code** — the exact path dead in +74. Use a test
account that is NOT already a member. Expected: the join succeeds, the crew
appears in the list, and membership is written SERVER-side by the callable (the
client no longer writes `memberUids`). A silent no-op or a permission error is a
FAIL, and `bcf6ea3` specifically made a silent failure surface as a message.

**c. Nearby-group discovery** renders from `/neighborhood_public` — public crews
appear with NO invite code exposed, and joining one goes through
`joinPublicGroup(groupId)`, not the invite-code path.

**d. If either fails, capture before retrying:** the exact on-screen error text;
the build number from (a); whether the account was already a member; and the
Cloud Function log for `joinNeighborhood` around the attempt
(`gcloud logging read 'resource.labels.service_name="joinneighborhood"'`). A
client-side permission error and a callable-side refusal look identical on the
handset and are diagnosed from opposite ends.
**Rules/functions convergence, verified both ways.** Source: `git diff a83193f HEAD`
is **0 lines** for `firestore.rules`, `functions/src/joinNeighborhood.ts` and
`functions/index.js` — main now equals the source that was actually deployed on
2026-08-12. Behaviourally, against the LIVE ruleset with client credentials:

```
GET /neighborhoods/8b25LBEh...  MEMBER     (wrQRUUKy)       -> HTTP 200  readable
GET /neighborhoods/8b25LBEh...  NON-MEMBER (f3_repro_probe) -> HTTP 403  denied
```

which is exactly `allow read: if isGroupMember() || isGroupCreator()`. The source
identity alone would not have proved this — the Rules API still 403s to the ADC
token, so behaviour is the evidence and source identity is the corroboration.

**No deploy in this step.** The rules freeze can lift now that main and production
have converged; **functions deploys remain frozen until Prompt 2.**

---
## 2.5.10+74 — legacy installer entries retired; first build carrying a verified crew fanout

| Field | Value |
|---|---|
| **Tag** | **`build-74`** — the deliberate act that produced the iOS build (#62). The tag points at the docs-only commit that follows `850c0db`; the app bytes are `850c0db` (see below). |
| **Git SHA (app bytes)** | **`850c0db`** — `feat(staff): retire the legacy installer entry points; bump to 2.5.10+74`. **iOS↔Android join key.** |
| **App-bytes ancestry** | `1d95104` (+73) **+** the staff-entry retirement — **and nothing else.** Corrected 2026-08-13: the original row credited "F-3 security" and "the #70 fanout fix" here. Both are real and both are LIVE IN PRODUCTION, but neither is app bytes — #70 is `functions/` (deployed 22:20:40Z, independent of any build) and F-3 is `firestore.rules` + a callable, whose **app-side half is not on `main` at all** (see the WARNING below). The full app-bytes delta is: `git diff --stat 1d95104 build-74 -- lib pubspec.yaml` → 10 files, +223/-856. |
| **Ledger SHA (tagged)** | The `build-74` tag, docs-only on top of `850c0db`. Verified with a tree comparison, not a grep — `git diff --stat 850c0db build-74 -- . ':(exclude)docs'` is EMPTY, so the tag builds byte-identical app code. Deliberately named by TAG, not by hash: a commit cannot state its own SHA (amending to insert it changes it), and that self-invalidating reference has bitten this ledger before. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **74** — merged manifest (`android:versionCode="74"`, `android:versionName="2.5.10"`), read from the manifest and not from pubspec. `kStaffAuthTelemetryAppVersion` moved to `2.5.10+74` in the same commit; they are one fact in two files. |
| **Android artifact** | `app-release.aab` · **68,271,666 bytes** · `jarsigner -verify` → **jar verified** · built 2026-08-12 from isolated worktree `lumina-b74` at tag `build-74`, `git status` empty before **and** after. Obfuscated; symbols at `build/debug-info/android/` (arm, arm64, x64) — archive, never commit. **versionCode 74 is now CONSUMED: a built AAB consumes its code even if never uploaded.** |
| **iOS** | **Build 295**, from tag `build-74` (Codemagic). |
| **Uploaded** | iOS to TestFlight; Android AAB to the **Play closed testing track** (both reported by Tyler 2026-08-13). |
| **STATUS** | ⚠️ **SUPERSEDED by +75 — JOIN REGRESSION.** Shipped with F-3's rules live but its app half absent, so joining a crew by invite code fails. See the warning below. Not a distribution candidate. |
| **Supersedes** | **+73** |

**Contents since +73**

- **Legacy installer entry points retired** (`audit/INSTALLER_ENTRY.md`). Two
  parallel entries existed, both live, both minting real server-side staff
  tokens, landing on two different destinations. `/staff/pin` superseded the
  legacy path on 2026-04-09 but only the login-screen caller was migrated — the
  documentation was not stale, the code was. `installer_pin_screen.dart` (361
  lines) and `admin/admin_dashboard_screen.dart` (248) deleted with routes
  `/installer/pin` and `/admin/pin`; Day 1 / Day 2 session-expiry gates
  repointed to `staffPin`.
- **The Settings 5-tap is gone.** This was the entry Tyler had been using in the
  field. On this build installer mode is reachable only via the login-screen
  logo 5-tap or the visible "Installer" button on `/link-account`.
- **The `/link-account` "Media" button removed** — it pushed a 4-digit staff PIN
  screen while `MediaAccessCodeScreen` expects a 6-character media code, on the
  default path of every fresh sign-up including a reviewer's. Repointing it
  would not have fixed it: `media_codes`/`media_access_logs` have no
  `firestore.rules` coverage, `/media` is in no `appRedirect` allow-list, and the
  screen fabricates an `installerSessionProvider` with no minted token.
- **`/sales/pin` and the visible "Installer" button KEPT deliberately** — the
  former because `sales_landing_screen` still bounces to it on session expiry,
  the latter because it is an open submission-review question and not something
  to change silently under a release.
- **Server work verified before this build, not after** — #70 (crew fanout wrote
  `controllerIp:""`, so no real bridge could ever execute it) fixed in `06e36dc`,
  deployed 22:20:40Z, and proven on hardware at **4/4** the same evening:
  `A converged after ~2s (real bridge)`, strip carrying `seg0 fx=88 pal=5`
  red/blue, A's command `completed` against `ip="192.168.1.150"`. Also carries
  F-3 and the #66 end-fire guard. **The fanout fix is server-side and is already
  live for the demo group regardless of this build** — +74 does not gate it.

> ### ⚠️ WARNING — F-3 IS DEPLOYED BUT ITS APP HALF IS NOT IN THIS BUILD
>
> Discovered during the +74 identity verification, 2026-08-13. F-3 lives on
> branch `fix/f3-neighborhood-security` (`a83193f`), which was **never merged to
> `main`**. Its rules and `joinNeighborhood` callable were deployed to production
> from the worktree on 2026-08-12; its **285 lines of `lib/features/neighborhood/`
> changes ship only in a build, and +74 does not contain them.**
>
> The deployed rule is `allow read: if isGroupMember() || isGroupCreator()`, and
> self-insertion into `memberUids` is refused. +74's `NeighborhoodService.joinGroup`
> still does the pre-F-3 thing — queries `/neighborhoods` by `inviteCode`, then
> `update({memberUids: arrayUnion([uid])})` and writes `members/{uid}` client-side.
> A non-member cannot perform that read.
>
> **Expected consequence in +74: joining a crew by invite code fails with
> permission-denied, and so does nearby-group discovery** (the
> `/neighborhood_public` projection reader is branch-only). Creating a group and
> existing members' in-crew function are unaffected.
>
> **REPRODUCED against production 2026-08-13** with CLIENT credentials (not the
> admin SDK, which bypasses rules). Ran +74's exact first step - a `runQuery` on
> `/neighborhoods` filtered by `inviteCode` - for the "demo" group:
>
> ```
> NON-MEMBER (synthetic uid f3_repro_probe)
>   HTTP 403 {"error":{"code":403,"message":"Missing or insufficient permissions.",
>             "status":"PERMISSION_DENIED"}}
> MEMBER     (wrQRUUKy, in the group)
>   HTTP 403 {"error":{"code":403,"message":"Missing or insufficient permissions.",
>             "status":"PERMISSION_DENIED"}}
> ```
>
> **Worse than derived: the MEMBER is denied too.** A collection query is allowed
> only when its constraints prove every matched document satisfies the rule; a
> filter on `inviteCode` proves nothing about `memberUids`, so Firestore refuses
> the query outright rather than filtering it. `joinGroup` therefore fails for
> EVERY caller in +74, not only for new joiners. The caveat is closed.
>
> Merging the branch is **not** a clean fix: its `functions/src/applySyncPattern.ts`
> predates the scoped fanout (`dab5b27`) and the #70 address fix (`06e36dc`), so a
> naive merge reverts both. Rebase onto `main` and keep `main`'s copy of that file.
>
> **Do not deploy `firestore.rules` or `functions` from `main` until this is
> resolved** — `main`'s rules predate F-3 and would reopen the P0.

**Hardware state at cut:** bench `.150` restored to `on=false bri=200 ps=2`.
Controller config untouched — type 30 / RGB order 1 remains source of truth.

---

## 2.5.10+73 — participation reads buses from the healer's own cfg

| Field | Value |
|---|---|
| **Git SHA (app bytes)** | **`1d95104`** — `chore(release): bump to 2.5.10+73`. **iOS↔Android join key.** |
| **App-bytes ancestry** | `4f76b56` (+72) **+** the bus-source rewire. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **73** — merged manifest (`android:versionCode="73"`, `android:versionName="2.5.10"`) |
| **Android artifact** | `app-release.aab` · **68,296,715 bytes** · `jarsigner -verify` → **jar verified** · built 2026-08-12 from an isolated worktree at `1d95104`, `git status` empty before **and** after |
| **iOS** | **Build 292**, from `1d95104`. Installed build verified against Codemagic **before** connecting (`2.5.10 (292)`), and distinct from 291 — which is what makes the 05:04:23.001Z run attributable to +73 rather than to a lucky +72. |
| **Uploaded** | **NO.** TestFlight distribution for §7.2d is a verification path, not production exposure (Conventions). |
| **Supersedes** | **+72** |

**Contents since +72**

- **Bus-source rewire** — participation resolves the bus list from
  `ControllerClockInfo.hardware`, parsed from the `/json/cfg` the healer has
  already fetched, instead of `deviceHardwareConfigProvider`. §7.2d proved that
  provider hands back a **stale cached null at the same instant the healer's own
  read succeeds** (#63). `wled_service.dart`'s inline `hw.led` parsing was
  extracted to `hardwareConfigFromCfg()` and `getConfig()` rewired to it, so both
  paths share **one** parser.
- **Approved decision reversal** — "the caller owns the bus-list derivation" is
  reversed for the bus leg only. The original constraint (no second parser, no
  `ref` in the healer) is better served by this shape than by the provider. The
  **roofline** leg is unchanged: still the caller's awaited Firestore future.
- **`noBusesConfigured`** disposition added — "we read `hw.led` and the
  controller reports no LED outputs", now distinguishable from "we could not
  read it". `shapeUnknown` is retained although it should be unreachable from
  the healer path: an unreachable disposition that fires anyway is the signal
  worth having.

**What the 20s bound covers now:** the **roofline await only**. The bus leg no
longer crosses a provider boundary and cannot time out.

**Verification:** suite run **from `1d95104` inside the build worktree** —
**2159 passed · 3 skipped · 6 failed**, of which 1 is pre-existing
(`base_ladder_repair_live_test`) and **5 are #64**, a midnight-wrap defect in the
lease integration test, reproduced at pre-change HEAD in a clean worktree.

Re-run after local midnight on the same tree, no code change:
**2164 passed · 3 skipped · 1 failed** — the pre-existing hardware test alone.
**2164 is the new baseline**, up 4 from +72's 2160 (3 parser / one-fetch tests,
1 disposition test). #64 is deterministic, not flaky: the same five went red at
23:45 and green at 23:59.

### §7.2d ON +73 (build 292) — **GREEN. First participation publish from the healer on real hardware.**

Ran 2026-08-12 **05:04:23.001Z**. Read with a client credential.

```
participating_channels                 [0, 1]
participating_channels_device_ids      [0, 1]
participating_channels_source          healer      <- was neighborhood_sync
participating_channels_at              05:04:23.001Z   <- was 2026-08-11T18:20:14.409Z
participating_channels_publish_count   1           <- appeared
participation_publish_disposition      offered
participation_publish_disposition_at   05:04:23.001Z
base_boundaries                        3 rows, MATCH to timers.ins, count 3 -> 4
light.gc.col                           2.8
```

Disposition transition: `SKIPPED(bus list resolved empty — shape unknown)` →
**`offered`**.

**Step 6 confirmed again:** all three families carry the identical `_at`
(`05:04:23.001Z`) — participation, base boundaries and the mirror in one
`set(merge: true)`.

**The `[0, 1]` assertion is evidence-based, not assumed.** The bench roofline
holds one segment (channel 0, `isPrimary: true`), so the resolver's answer is
primaries `{0}` ∪ untraced device channels `{1}` = `[0, 1]`. Correct, and not a
superset.

**Build identity mattered and was checked.** `offered` is byte-identical in +72
and +73, so Firestore alone cannot tell them apart — a +72 build could have
produced this result if `deviceHardwareConfigProvider` happened to be warm, which
is exactly the timing luck +73 removes. Build **292** (≠ 291) is what makes this
attributable.

#### Leg A — DEDUP ON HARDWARE: **GREEN**

Second heal via a Wi-Fi cycle (endpoint key change — a genuine healer re-run, not
a backgrounding, which would not re-fire the listener and would pass vacuously).
App process kept alive throughout.

```
participating_channels             publish_count 1 -> 1  (+0)   value changed: no
base_boundaries                    publish_count 4 -> 4  (+0)   value changed: no
participation_publish_disposition  offered -> offered
all _at unchanged at 05:04:23.001Z
```

**Zero mutations.** All three memos held — including the disposition memo, which
is the one that would have silently turned this from a 0-write pass into a
1-write regression when the mirror shipped.

#### Leg B — ROOFLINE DISCRIMINATION: **GREEN**. `[0]`, first ever.

The rig was made discriminating first. **Live source determined from code, not
assumed:** `currentRooflineConfigProvider` maps
`streamPixelMapChannels(uid, controllerId)` through
`aggregatePixelMapChannelsToConfig`, so the live collection is **`pixelMap`** —
`roofline_config` is legacy migration-only and writing there would have changed
nothing.

Written (permanent, per Tyler) to
`users/wrQRUUKyXyc0deyuu0ORS6wsovO2/controllers/192_168_1_150/pixelMap/1`,
which did not previously exist:

```json
{"channel_index": 1, "source_pixel_count": 162, "map_version": 1,
 "is_stale": false, "name": "Bench ch1 (secondary)",
 "segments": [{"id": "ch1-secondary", "channel_index": 1,
               "is_primary": false, "pixel_count": 10, "points": [], ...}]}
```

Every field was checked against `RooflineSegment.fromJson` before writing — all
default safely, so no other consumer breaks. `source_pixel_count: 162` matches
bus 1's real length, so `pixelMapStalenessProvider` does not flag it.

Result after a Wi-Fi cycle:

```
participating_channels                 [0]          <- was [0, 1]
participating_channels_device_ids      [0, 1]       <- device shape still both buses
participating_channels_previous        [0, 1]       <- FIRST time this field has been written
participating_channels_publish_count   1 -> 2
participating_channels_at              05:21:54.099Z
base_boundaries                        DEDUPED (count 4, _at still 05:04:23.001Z)
participation_publish_disposition      offered, DEDUPED (_at still 05:04:23.001Z)
```

`tracedChannels {0,1}`, `primaryChannels {0}`, `untraced {}` ⇒ `[0]`. **The
"traced but NOT primary ⇒ EXCLUDED" branch executed against real hardware for
the first time anywhere**, and the roofline await demonstrably held — a sampled
(unresolved) roofline would have produced `[0, 1]`.

`_previous: [0, 1]` is also its first hardware exercise: an in-session change,
so the memo was warm and the superseded value was recorded rather than deleted.

**The bench rig is now discriminating for the roofline leg** and the segment
stays in place. Cross-ref **#65**: this branch remains **unreachable in
production** until some code path can set `is_primary: false` — so this proves
the resolver and the await, not that any customer is in this state.

#### Single-write property — the accurate count

Two hardware confirmations of families sharing one `_at`, not four:

| run | families in the write | shared `_at` |
|---|---|---|
| 04:19:08.171Z (+72) | base boundaries + disposition | **yes** |
| 05:04:23.001Z (+73) | participation + base boundaries + disposition | **yes** |
| Leg A | none — all deduped | n/a (0 writes) |
| Leg B | participation only | n/a (1 family) |

Legs A and B confirm the complementary property — that non-writing families are
**not** dragged into a write — which is what makes the shared-`_at` result
meaningful rather than incidental.

---

## 2.5.10+72 — facts-publish disposition mirror

| Field | Value |
|---|---|
| **Git SHA (app bytes)** | **`4f76b56`** — `chore(release): bump to 2.5.10+72`. **iOS↔Android join key for both artifacts.** |
| **App-bytes ancestry** | `01ab2b4` (+71 bytes) **+** `680abc6` (disposition mirror, its dedup memo, enum-label distinctness). `a0cde1e` and the other commits in between are docs/tools-only. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **72** — merged manifest (`android:versionCode="72"`, `android:versionName="2.5.10"`) |
| **Android artifact** | `app-release.aab` · **68,296,487 bytes** · `jarsigner -verify` → **jar verified** · built 2026-08-11 from an isolated worktree at `4f76b56`, `git status` empty before **and** after |
| **iOS** | **Build 291**, from `998307b` — verified byte-identical to `4f76b56` across `lib/assets/pubspec/android/ios`, contains the mirror commit `680abc6`, stamps `2.5.10+72`. **TestFlight served build 288 first** (an older `2.5.10` artifact); the device had to be updated to 291 before §7.2d could run. **#62 materialised exactly as filed** — the version name is identical across builds, so only the build number distinguishes them. |
| **Uploaded** | **NO** (Android). iOS: `codemagic.yaml` sets `submit_to_testflight: true`, so a green build **auto-submits** — see the VOID note below. TestFlight is a verification path, not production exposure (Conventions). |
| **Supersedes** | **+71**, wholesale. |
| **SUPERSEDED BY +73** | `1d95104`. +72 was correct and it did its job — see the §7.2d result below. |

**Contents since +71**

- **Disposition mirror** (`680abc6`) — `participation_publish_disposition` (+ `_at`)
  written on **every** facts-publish attempt including `offered`, so an absent
  field means "the healer never attempted here" and can never mean "attempted
  and skipped". `ControllerHealReport.factsPublish` is in-process only and
  `debugPrint` is nulled under `kReleaseMode`, so before this a skip left **zero
  external evidence** — the blindness that made §7.2d undiagnosable.
  One formatter (`participationDispositionLabel`) feeds both the log line and
  the field. The mirror carries its own dedup memo so it rides an existing write
  and a fully-deduped connect still costs **zero** mutations.

**Why +71 is superseded rather than burned:** it was a correct build —
worktree-clean, jar verified, 68,296,168 bytes — simply sealed before the mirror
existed, and never uploaded, so nothing depends on it.

**Verification:** suite run **from `4f76b56` inside the build worktree** —
**2160 passed · 3 skipped · 1 failed** (`base_ladder_repair_live_test` —
pre-existing, reproduced at baseline). `flutter analyze lib/ test/` no errors.

### §7.2d ON +72 (build 291) — RED, and legibly so

First run with the mirror. Verbatim from the controller document:

```
participation_publish_disposition
    SKIPPED(bus list resolved empty — shape unknown)
    at: 2026-08-12T04:19:08.171Z
```

| step | result |
|---|---|
| participation published | **RED** — `_source` still `neighborhood_sync`, no `publish_count` |
| base boundaries | **GREEN** — 4 rows → 3 after the lease expired, exact match to `timers.ins`, `publish_count` 2 → 3 |
| `gc.col` | **GREEN** — 2.8 |
| disposition mirrored | **GREEN** — first mirrored outcome |
| **step 6 on hardware** | **GREEN** — `base_boundaries_at` and the disposition `_at` are the SAME instant, `04:19:08.171Z`. Both families rode one `set(merge:true)`. First hardware confirmation of the one-write guarantee. |

**The mirror paid for itself immediately.** The same run would previously have
produced a base-boundary update and total silence on participation; instead it
named the cause in one line, and the root cause (#63) was diagnosable without a
second bench cycle. Fixed in **+73**.

Also confirmed live: the solar sentinel moved from readback index 3 → 2 when the
lease row expired and compaction closed the gap — the content-based (`hour ==
255`) classification held through a real index shift that would have
misclassified it under the original index-based rule.

### ⚠️ VOID — two Codemagic builds that must not be trusted

`680abc6` and `a0cde1e` carry the **+72 mirror code** but predate this bump, so
they still stamp `kStaffAuthTelemetryAppVersion = '2.5.10+71'`.

**Why they are void — stated accurately.** The "versionCode 71 on +72 bytes"
framing is Android-only and does **not** apply to these: `codemagic.yaml`
overwrites the iOS build number with `PROJECT_BUILD_NUMBER`, so no iOS build was
ever going to be stamped 71 or 72. The two real defects are:

1. **No ledger row can identify them.** They match neither the +71 row
   (different `lib`) nor this +72 row (different SHA). Given a crash report from
   one, the shipped commit is unrecoverable — the exact failure this file exists
   to prevent.
2. **Telemetry misattributes.** They report as `2.5.10+71`, so S-5
   dealer-adoption would credit their events to +71.

**They auto-submit.** With `submit_to_testflight: true`, a green build from
either is pushed to TestFlight without further action. Cancel them if running;
if either already went green, expire/remove the TestFlight build and do not
promote it. Superseded by the `4f76b56` build in every respect.

### Codemagic triage — tonight's SHAs

| SHA | classification |
|---|---|
| `a712180` `2a15b83` `aa8298b` `42746bd` `6d86668` `d8da74a` | **+71 app bytes.** A green build from any of these is the +71 iOS artifact: verified, NOT uploaded, superseded by +72 |
| `680abc6` `a0cde1e` | **VOID** — +72 code, +71 telemetry stamp, no ledger identity |
| **`4f76b56`** and later | **+72** — the TestFlight candidate for §7.2d |

---

## 2.5.10+71 — healer participation ordering fix

| Field | Value |
|---|---|
| **Git SHA (app bytes)** | **`01ab2b4`** — the `--no-ff` merge of `release/2.5.10+71`. **iOS↔Android join key.** |
| **SHA range for this release** | `9e8607c..01ab2b4` defines the app bytes; later commits for this release are docs-only. Verify with the tree comparison in Conventions — **not** a path grep. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **71** — merged manifest (`android:versionCode="71"`, `android:versionName="2.5.10"`) |
| **Android artifact** | `app-release.aab` · 68,296,168 bytes · built 2026-08-11 19:11 · `jarsigner -verify` → **jar verified** |
| **Built from** | **An isolated `git worktree` checked out at `01ab2b4`**, not the main working tree — see the +70 row. Worktree `git status` was empty before and after the build, so no in-flight edit could reach the artifact. |
| **iOS** | **TRIGGERED 2026-08-11** by the push that landed this row; Codemagic builds the **tip**, which was `42746bd` at that moment. Build number and exact SHA **`PENDING`** — fill both from Codemagic when it completes, not while queued. Whatever tip it took, it is the same build: every commit after `01ab2b4` in this release is docs- or test-only, and `lib`, `assets`, `pubspec.yaml`, `pubspec.lock`, `android`, `ios` are identical trees. **So the IPA and the +71 AAB are the same app bytes.** |
| **iOS build number ≠ 71, by design** | `codemagic.yaml` takes only the version *name* (`2.5.10`) from pubspec and overwrites the build number with its own `PROJECT_BUILD_NUMBER`. The git SHA is the join key; a build-number mismatch here is expected and is not a defect. |
| **Sibling artifact** | Android **`2.5.10+71`** — `app-release.aab`, **68,296,168 bytes**, `jarsigner -verify` → *jar verified*, built 2026-08-11 19:11 from an isolated worktree at `01ab2b4`. **Built, NOT uploaded.** |
| **Uploaded** | NO — neither platform |
| **SUPERSEDED BY +72** | `4f76b56`. +71 was correct and complete; it was sealed before the disposition mirror existed and nothing was ever distributed from it. Retained as a row for identity, not as a candidate. |

**Contents since +69**

- **Participation ordering fix** (`89ca43e`) — +69 published base boundaries but
  **never** participation. Both participation inputs are asynchronous and
  neither has resolved when the healer fires at t=0:
  `deviceHardwareConfigProvider` is a FutureProvider doing its own `/json/cfg`
  GET (empty bus list ⇒ correct-but-permanent refusal), and
  `currentRooflineConfigProvider` is a **StreamProvider** (no segments ⇒ the
  resolver reads "untraced install" and would publish a **superset**). The
  caller now hands the healer a `Future<ParticipationInput?>`, awaited on the
  fire-and-forget path with a 20s bound. Heals unaffected.
- **The silence, fixed structurally** — a skipped publish left no log line, no
  field and no report entry, which is why a bench run caught this and nothing
  else did. `ParticipationDisposition` enumerates every skip reason,
  `FactsPublishOutcome.describe()` logs one line always, and
  `ControllerHealReport.factsPublish` exposes the outcome as an awaitable.

**Verification:** Dart suite **2148 passed · 3 skipped · 1 failed**
(`test/hardware/base_ladder_repair_live_test.dart` — pre-existing, reproduced at
baseline), run **inside the clean worktree**. `flutter analyze lib/ test/` no
errors. Step 6 (both families in one `set(merge:true)`) is now pinned by counting
document mutations via a snapshot listener.

**Pre-flight for the iOS counterpart (2026-08-11):** production Firebase
(`icrt6menwsv2d8all8oijs021b06s5`); `kSimulationMode = false`;
`kStaffTokenSafetyMargin = 50 min`; `debugPrint` nulled under `kReleaseMode` in
`main.dart:129`; no `192.168.1.150` on an executable path (four hits in `lib/`,
all doc comments); no strip-before-release markers; **`PrivacyInfo.xcprivacy`
traced into the Runner target's `PBXResourcesBuildPhase` (`97C146EC…`)** — not
merely a group member, so it actually ships.

**Added after the AAB, test-only** (`aa8298b`): a regression guard pinning the
`currentRooflineConfigProvider` **await**. Mutation-verified — swapping the await
for `.valueOrNull` reproduces `ParticipationInput([0, 1] of [0, 1])` where `[0]`
is correct, i.e. the untraced-install superset. Suite with it: **2153 passed · 3
skipped · 1 pre-existing**.

**Participation re-verification on hardware is OWED** — `audit/HEALER_PUBLISH.md`
§7.2d. +69 proved base boundaries; participation has never once published from
the healer on a real device.

**NOT deployed:** Cloud Functions, `firestore.rules`, and
`config/gameday_planner.write_jobs` NOT flipped.

---

## 2.5.10+70 — BURNED, NEVER SHIPPED. DO NOT UPLOAD.

| Field | Value |
|---|---|
| **Status** | **Artifact built, then DELETED. versionCode 70 is consumed and must never be reused.** |
| **Why** | The `.aab` was built from the main working tree at 17:37 while a **parallel session** saved uncommitted work-in-progress into that same tree at 17:20–17:21 (`lib/app_router.dart`, `lib/features/auth/staff_pin_screen.dart`, `lib/features/auth/link_account_screen.dart`, `lib/features/site/settings_page.dart`). The Dart compile picked them up. The artifact therefore contained another session's unreviewed, untested, uncommitted code. |
| **Disposition** | Deleted from `build/app/outputs/bundle/release/`. No commit was ever made at +70; the version bump went straight to +71. The other session's files were left untouched and uncommitted. |

**The lesson, promoted to Conventions:** this repo is worked by parallel sessions,
so **a release build must never be cut from the shared working tree.** +71 was
built in an isolated `git worktree` at the exact merge SHA, whose `git status`
was empty before and after.

---

## 2.5.10+69 — healer publishes device-only facts on connect

| Field | Value |
|---|---|
| **Git SHA (app bytes)** | **`e4bd463`** — the `--no-ff` merge of `release/2.5.10+69`. **iOS↔Android join key.** The last commit in this release that changes what the app does. |
| **SHA range for this release** | **`ec9db58..e4bd463` defines the app bytes; every commit after it on `main` for this release is docs-only.** Verified, not assumed: `lib/`, `assets/`, `pubspec.yaml`, `pubspec.lock`, `android/`, `ios/` are byte-identical trees across the range. Recorded as a range so the SHA is not chased with corrections. |
| **Which SHA to build iOS from** | **The tip of `main`, whatever it is** — Codemagic auto-builds the tip on push, and *this row is itself inside the range it describes*, so naming one SHA is self-defeating: every ledger correction moves the tip. Any tip that leaves the app-byte trees untouched is the same build. Check before triggering (see below) — **empty output means safe**. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **69** — verified from the merged manifest (`android:versionCode="69"`, `android:versionName="2.5.10"`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,295,738 bytes · built 2026-08-11 16:25 |
| **Built from** | The **working tree**, before the commits below existed. Verified content-identical to `e4bd463`: no `lib/` file changed after the build — the only post-build edits were to `audit/HEALER_PUBLISH.md`, which is not compiled. |
| **iOS** | **NOT YET TRIGGERED.** Build number is `PENDING` — fill it when Codemagic finishes, not when it is queued. Codemagic takes only the version *name* (`2.5.10`) from pubspec and overwrites the build number with its own `PROJECT_BUILD_NUMBER`, so the iOS build number will NOT be 69 and is not expected to be. Expect the iOS SHA to be a docs-only descendant of `e4bd463` (see the row above) — record the actual SHA here when it completes. |
| **Uploaded** | NO |

**Contents since +68**

- **Healer publish** (`f041463`) — `participating_channels` and `base_boundaries`
  now publish from the on-connect defaults healer, one `set(merge:true)`, zero
  writes when both families dedup. Closes the gap where publishing required an
  autopilot evaluation or a hand-run neighborhood sync, which left five accounts
  at `never_resolved` through a 24-hour shadow. `deviceChannelIds` and the
  resolved set are **parameters**, not a `ref` — the healer stays
  dependency-light on a path that runs for every controller on every connect.
- **Predicate/range consolidation** (`b9c9ec9`) — `carriesAnyEnabledEntry`, the
  `timers.ins` extractor, and the preset-id ranges each had a second
  implementation. No behaviour change; verified standalone (clean analyze, 465
  schedule tests) before the feature was stacked on it.

> ⚠️ **BEHAVIOUR CHANGE.** A participation resolution computed against an
> **empty bus list is no longer published**. `[]` is a *usable* server-side
> verdict meaning "light nothing", and the healer publishes far earlier in a
> session than the old call sites did, so the pre-load window would have
> darkened houses that expected a show.

> ⚠️ **WRITE RATE IS ONCE PER APP SESSION PER CONTROLLER**, not
> zero-when-healthy — the dedup memo is process-scoped and never reads
> Firestore. A relaunch republishing an unchanged value is the designed
> self-heal, pinned by tests in both directions. Do not "fix" it.

**Verification:** device-side bench-verified against `.150` on 2026-08-11,
**read-only** — base boundaries match `timers.ins` exactly, `gc.col` still 2.8
before and after, ladder (presets 1/3/4/5) intact, zero cfg writes. The bench
found and fixed a real defect first: **WLED compacts the `/json/cfg` readback**,
so the slot-8 solar sentinel arrives at index 3 and classifying solar by array
index published it as a clock row at `hour: 255`. Dart suite **2137 passed · 3
skipped · 1 failed** (`test/hardware/base_ladder_repair_live_test.dart` —
pre-existing, proven by re-running with the change stashed). `functions`
`npx jest test/unit` 8 suites / 237 tests. `flutter analyze lib/ test/` no
errors.

**App-side verification OWED** — `audit/HEALER_PUBLISH.md` §7.2b. The bench
tablet was unavailable, so the protocol is written against a phone on home
Wi-Fi: install +69, open the app on-LAN, do **not** run a neighborhood sync, and
read `users/wrQRUUKyXyc0deyuu0ORS6wsovO2/controllers/192_168_1_150` **with a
client credential, not the Admin SDK**.

**NOT deployed with this build:** Cloud Functions, `firestore.rules` (no rules
change is needed — the controllers subcollection is already owner-writable), and
**`config/gameday_planner.write_jobs` NOT flipped**. Nothing server-side reads
`base_boundaries` yet; this build publishes inputs only, with no arbitration.

---

## 2.5.10+68 — base-layer gate for Game Day + P1-8 closed

| Field | Value |
|---|---|
| **Git SHA (build from this)** | **`585b574`** — the `--no-ff` merge of `release/2.5.10+68`, and the state `main` built from. **iOS↔Android join key.** |
| **SHA range for this release** | `08ae0b6..585b574`. Any docs-only commit AFTER this (e.g. this ledger row) does not change app bytes and remains valid for +68 — recorded as a range so the SHA is not chased with corrections. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **68** — verified from the merged manifest (`android:versionCode="68"`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,264,238 bytes · built 2026-08-10 14:12 |
| **iOS** | **BUILDING from `e3eeb3a`** (triggered 2026-08-10). Differs from the Android tree `585b574` by `docs/BUILD_LEDGER.md` ONLY — verified docs-only, so **app bytes are identical** and the two platforms are the same build despite different SHAs. |
| **Uploaded** | NO |

**Contents since +67**

- **Base-layer gate** (`e2edd64`) — six Game-Day-enabled accounts have no everyday schedule (Tim Kelly, Chris Paschall, Jim Dyer, Darrin Nicholas, **Taps On Main — commercial**, Demo Home). A failed end signal leaves the design running with no next boundary to return the house. Prompts on enable, never refuses, never auto-creates, **fails OPEN**. Enum is `absentInFirestore` not `absent` (census counts Firestore intent, not device reality) and **a test pins that name**. Happy path does not consume the session slot.
- **P1-8 closed** (`cf6d0a2`) — stale `Sunset` assertion corrected; the test was wrong, the code was right (`b6ca2f1` removed that default because it fabricated `hour:25` timers that never fire).
- Carried from the +67→+68 window: **B3 newest-wins** (`f7bd784`) and **A3 dated-entry overwrite guard** (`94fca3a`), merged as `b3214a1`; **CHANNEL_GROUPING_SCOPE §0** (`08ae0b6`).

**Verification:** `flutter analyze lib/` whole-tree — **0 errors, 0 warnings** (373 pre-existing info). Dart suite **2036 passed / 3 skipped / 0 FAILED — fully green for the first time in weeks**. `functions` `npm run build` exit 0 (explicit check). Functions suite 8/8, 237 tests.

**NOT deployed with this build:** Cloud Functions, `firestore.rules` (`config/base_ladder_repair` committed but undeployed — the switch fails open), and **`config/gameday_planner.write_jobs` NOT flipped**.

> ⚠️ **`write_jobs` stays gated until this build REACHES DEVICES.** The gate existing in code is not the same as customers having it. Until then the six accounts are unwarned.

---
## 2.5.10+67 — base ladder root fix + _presetForAction routing

| Field | Value |
|---|---|
| **Git SHA (build from this)** | **`037a83c`** — current `main`. This is what a build off `main` produces today, and the **iOS↔Android join key**. |
| **Android .aab cut at** | `bea0d68` (the `--no-ff` merge of `release/2.5.10+67`; build commit `c400d62`). `037a83c` adds only this ledger entry — **docs-only, app bytes identical**, so the artifact is valid for `037a83c`. Pushed to origin 2026-08-09. |
| **Version name** | `2.5.10` |
| **Android versionCode** | **67** — verified from the merged manifest (`android:versionCode="67"`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,241,882 bytes · built 2026-08-09 16:54 |
| **iOS** | **PENDING** — Codemagic not triggered. It will build `037a83c` off `main`; record that SHA, not the merge commit |
| **Uploaded** | NO |

**Contents since +66**

- **Base ladder root fix** (`4e1a3a0`) — ON presets captured ambient segment state and fired dark. Nothing asserted `seg.on` on save, so any `psave` taken while a channel was off baked it in permanently; 4 of 5 ON presets on the bench were damaged at 4 different moments. `buildNglOnPresetState` writes `seg` explicitly at all four `psaveIfChanged` sites AND `isNglOnPresetSatisfied` asserts segment state — either alone is inert. **The healer had the identical defect** and would have re-damaged every repair on the next connect. Kill switch `config/base_ladder_repair` **fails OPEN**, deliberately opposite to `solar_scheduling`.
- **`_presetForAction` routing** (`6aa6785`) — `contains('off')` was a substring test running first, so `"Pattern: 1 On 4 Off - Solid"` resolved to the OFF preset; that label is on two accounts today. Now returns `int?` with anchored matching; unrecognised labels refuse rather than defaulting to macro 1.
- Team consolidation (`7dd018b`), S3b participation denormalization (`e6b0b67`).
- **functions/** (`0cd5bec`) — S3 dispatcher (deployed earlier), S5 Game Day planner + ESPN end signal and S4 `endsAt` companion **log-only and UNDEPLOYED**, S6 health source.
- Debt log (`34c681e`) — P1-52 `pdel` corrupts `presets.json`; P1-53 chunked-POST gotcha.

**Fleet exposure for the ladder defect is ZERO, structurally** — no scheduled boundary routes to the ladder because every schedule in the fleet carries a `wledPayload` and gets its own 10–25 pattern slot. That is a coincidence, not a guard: one payload-less schedule makes it non-zero.

**NOT deployed with this build:** Cloud Functions, and `firestore.rules` (the `config/base_ladder_repair` rule is committed but undeployed — the switch fails open, so a missing rule costs the ability to PULL it, not the fix).

**Verification:** `flutter analyze lib/` whole-tree — 0 errors, 0 warnings, 368 pre-existing info. Dart suite 2010 passed / 3 skipped / 1 pre-existing failure (`cloud_ai_processor_normalize`, proven unrelated by stashing to HEAD). `functions/` `npm run build` exit 0 (explicit check, not piped). Functions suite 8/8, 237 tests. Hardware test on `.150` passed.

---
## 2.5.10+66 — gamma cfg-write chokepoint + S6 controller-health functions

| Field | Value |
|---|---|
| **Git SHA** | `d4f124f818b5a5a215e81f741522a65edfd78481` (`d4f124f`) — the build commit (version bump) |
| **Merged to main** | two `--no-ff` merges ahead of it: `6ca15e4` (gamma, from `fix/gamma-cfg-chokepoint` @ `ef91660`) and `ec2925e` (S6, from `feat/s6-controller-health` @ `985c23a`). **Pushed to origin 2026-08-07** |
| **Version name** | `2.5.10` |
| **Android versionCode** | **66** — verified from the merged manifest (`android:versionCode="66"`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,231,469 bytes · built 2026-08-07 11:22 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android signing** | `jar verified` — CN=Tyler Honeycutt, OU=Nex-Gen LED LLC (correct upload key), SHA256withRSA 2048-bit |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | **PENDING** — not triggered by this session |

> ### WHAT SHIPPED: THE GAMMA FIX. This is the first app-code change since +62.
>
> **Colour gamma was being wiped fleetwide, durably, by the app itself.** Root cause is a WLED
> 0.15.1 firmware deserializer defect: any `POST /json/cfg` omitting `light.gc` resets
> `gammaCorrectCol`/`gammaCorrectBri` to false and `serializeConfig()` persists it to `cfg.json`
> on LittleFS — it survives reboot. `gc.val` is preserved by a separate code path; that
> `col`-resets-while-`val`-survives asymmetry is the fingerprint.
>
> All eight of Lumina's cfg writers omitted `light.gc`, so every schedule sync, calendar-lease
> sweep, healer heal and installer hardware push disabled gamma on its way past — a no-op
> re-sync with byte-identical timers did it too. Every controller in the fleet is affected;
> the visible harm is washed/amber rendering on every colour until repair.
>
> - **Fix 1** — `normalizeWledCfgPayload` asserts `light.gc` at the **write boundary**, on all
>   three cfg transports (`WledService._postConfig`, `wled_config_pusher._postConfig`,
>   `CloudRelayRepository.applyConfig`). Same shape as `normalizeWledPayload`/`frz` for state.
> - **Fix 2** — the defaults healer's step (e) AudioReactive write wiped the gamma step (d) had
>   just set, while reporting `gammaHealed: true`. Gamma is now step (f), last cfg write, before
>   the reboot; `gammaHealed` now means VERIFIED (it was set on readback mismatches, and hard
>   failures were swallowed silently).
> - **Fix 3** — deleted the dead `{'loc':…}` write in edit_profile (F-8). `loc` is not a WLED
>   cfg key; its only effect was triggering the deserializer.
>
> **Bench-verified 9/9 on rig `.150`** via `scripts/_verify_gamma_chokepoint.dart`, which drives
> the real `WledService` and reads `/cfg.json` — the LittleFS **file**, not the live serialise.
> Its test 1 is a control asserting the raw defect still reproduces, so the suite cannot pass
> vacuously on patched firmware. Timers, NTP and coords all still land.
> Diagnosis `audit/GAMMA_BUG.md`, fix `audit/GAMMA_FIX.md`.
>
> **Also on main, NOT in the app binary:** S6 controller-health telemetry (`functions/` only —
> daily read-only getInfo probe, collect, fleet alerts, push digest). **NOT DEPLOYED**;
> `FLEET_HEALTH_DIGEST_TO` must be set first. See `audit/CONTROLLER_HEALTH.md` §7.
>
> **Not deployed this build:** `functions/` (S6 + the C5 caps still pending from +65).
> **`firestore.rules` UNTOUCHED** — no rules change is pending; last touched by `bb12cb6`.
>
> `kStaffAuthTelemetryAppVersion` bumped to `2.5.10+66` in the same commit so S-5
> dealer-adoption telemetry records the right build.

> ### Pre-release sweep (the one that caught #84)
>
> `TEMPORARY` / strip-before-release / test-only sweep over `lib/`: **clean** — every hit is
> "contemporary", "temporary password", or an `@visibleForTesting` seam. `kSimulationMode`
> `false`. `kStaffTokenSafetyMargin` at its real value (`Duration(minutes: 50)`, documented
> against the 60-minute custom-token TTL). `debugPrint` nulled in release
> (`main.dart:129`). Firebase `icrt6menwsv2d8all8oijs021b06s5` consistent across
> `firebase_options.dart`, `.firebaserc` and `google-services.json`; package
> `com.nexgenled.lumina`. **No `192.168.1.150` in any executable path** — all rig references in
> `lib/` are doc comments, and the rig harness lives in `scripts/` (not compiled into the app).
> `PrivacyInfo.xcprivacy` confirmed still in the Runner target's Resources build phase
> (`97C146EC…`, `project.pbxproj:273`) after pbxproj churn.

> ### ⚠ +65 AND EARLIER ARE SUPERSEDED — DO NOT UPLOAD
>
> A built AAB consumes its versionCode whether or not it is uploaded.
> **Next Android build ≥ +67.** Superseded and unuploaded: +65, +64, +63, +62, +61, +60.

**Test suite at build time:** 1945 passed · 3 skipped · 1 failed
(`cloud_ai_processor_normalize` — pre-existing and stale, unrelated).
`flutter analyze lib/` — 0 errors, 0 warnings. `functions`: 143/143 jest,
`node --check index.js` clean.

---

## 2.5.10+65 — rebuild at versionCode 65 (no app-code change since +64)

| Field | Value |
|---|---|
| **Git SHA** | `361c958` — the build commit (the version bump itself) |
| **Merged to main** | built directly on `main`; no feature branch — the bump is the only change |
| **Version name** | `2.5.10` |
| **Android versionCode** | **65** — verified from the merged manifest (`android:versionCode="65"`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,237,538 bytes · built 2026-08-05 16:23 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android signing** | `jar verified` — CN=Tyler Honeycutt, OU=Nex-Gen LED LLC (correct upload key) |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | **n/a** — Android-only rebuild; no IPA cut at this version |

> ### WHAT CHANGED SINCE +64: NO APP CODE.
>
> `git diff 68786e9..361c958 -- lib/ android/ ios/` is empty apart from the two version constants.
> Everything on `main` since +64 is server-side or documentation:
>
> - **`firestore.rules` DEPLOYED** (ruleset `93c99c50`) — `config/solar_scheduling` + the
>   `controller_ips` command-safety rule. **This is why +65 behaves differently from +64 in the
>   field despite identical app code:** +64's solar surfaces were shut only because the rules
>   blocked the flag read. Any build from `68786e9` onward un-gates solar now that the rule is live.
> - **`scheduledDataCleanup` DEPLOYED** — first retention run, 3,985 documents.
> - **C5 cleanup-query caps** in `functions/` — committed, **NOT deployed**.
>
> `kStaffAuthTelemetryAppVersion` bumped to `2.5.10+65` in the same commit so S-5 dealer-adoption
> telemetry records the right build.

> ### ⚠ +64 IS SUPERSEDED — DO NOT UPLOAD
>
> A built AAB consumes its versionCode whether or not it is uploaded. The +64 artifact is
> quarantined on disk as `versionCode64-68786e9-DO-NOT-UPLOAD-superseded.aab.bak`.
> **Next Android build ≥ +69.** +68 BUILT 2026-08-10, not uploaded. Superseded and unuploaded: +67, +66, +64, +63, +62, +61, +60.

---

## 2.5.10+64 — solar LIVE + comparator wired + privacy manifest + #84 strip

| Field | Value |
|---|---|
| **Git SHA** | `68786e9e745b28ce45bb637cc76e267d6d07b736` (`68786e9`) — the build commit |
| **Merged to main** | `dad7329382e1d379cef5ebeeb1213f45b85d031f` (`dad7329`, `--no-ff`), **pushed to origin 2026-08-05** |
| **Branch at build time** | `feat/solar-live-comparator-privacy` (off `main` @ `7e04b00`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **64** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,237,290 bytes · built 2026-08-05 13:04 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | **277** — uploaded to App Store Connect 2026-08-05 |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch built** | `main` @ `dad7329` |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

> ### 🔑 JOIN KEY — all three identities of this build
>
> | Identity | Value |
> |---|---|
> | **Git build commit** | **`68786e9`** (`68786e9e745b28ce45bb637cc76e267d6d07b736`) |
> | **Git merge commit** | **`dad7329`** (`dad7329382e1d379cef5ebeeb1213f45b85d031f`) |
> | **Android versionCode** | **64** |
> | **iOS build number** | **277** |
>
> A tester who reports "build 277" is reporting on `68786e9` / `dad7329`, which is the same code as
> Android `versionCode 64`. The numbers differ only because `codemagic.yaml` overwrites pubspec's
> build number with its own `PROJECT_BUILD_NUMBER` counter.

**Contents.** *Solar:* `config/solar_scheduling.enabled = true` went LIVE 2026-08-05
(readback-confirmed) — it had **never existed** since solar was declared live 2026-07-28, so four
accounts had solar silently refused for eight days. Bench gate passed properly this time: a slot-9
row **FIRED at 11:27:09 against a computed sunset of 11:27**. `solarTimersLanded` +
`CfgPushOutcome.solarMismatch` wired into `pushCfgWithVerify` the same day — before it, solar rows
verified clean whether or not they landed. *Privacy:* #84 instrumentation stripped (it wrote
PII-bearing diagnostics to Firestore in release builds), `_safePreview` → `_safeShape`,
`debug_errors` retention at 30d, and `ios/Runner/PrivacyInfo.xcprivacy` declaring **12** data types
and wired into the Runner target's **Resources build phase**.

**Three findings from this build worth keeping:**
- `GET /settings/s.js?p=5` exposes the controller's **computed** sunrise/sunset — `/json/info` and
  `/json/state` have no solar field. Verifies the computation without firing.
- Coordinate writes do **not** recompute; a **reboot** does. Longitude-only is exactly 4 min/degree.
- WLED 0.15.1 stores the solar offset **SIGNED** (`-30` reads back `-30`, not `226`) — measured.

**Test suite at build time:** 1934 passed · 3 skipped · 1 failed (`cloud_ai_processor_normalize` —
pre-existing stale P1-8). **`flutter analyze lib/` WHOLE: 0 errors, 0 warnings** (368 pre-existing
info). Whole-lib was used deliberately: the `CfgPushOutcome` addition broke an exhaustive switch in
`sunrise_off_service.dart` that a file-scoped analyze had missed.

> ### ⚠ HARDWARE DEBT — now owed on +60, +61, +62, +63 AND +64
>
> - **Token refresh 4.2** — undischarged since +60.
> - **Commissioning a-d (P0-5/P0-6/P0-7)** — blocked by rig pairing state; carries to the next
>   genuine install.
> - **P1-50 step 6** — undo/erase confirmed in the RUNNING editor on a handset. Only the wire
>   equivalent is proven.
> - **`PrivacyInfo.xcprivacy` in the built IPA — still unconfirmed.** See the note below; the
>   successful upload does NOT establish it. Low effort to close, low risk if it slipped.

> ### ⚠ WHAT THE SUCCESSFUL UPLOAD DOES AND DOES NOT PROVE
>
> Build 277 uploaded to App Store Connect cleanly. It is tempting to read that as confirmation that
> `PrivacyInfo.xcprivacy` shipped in the IPA. **It does not**, and this project's own history is the
> counter-example: the file was created **today**, in `68786e9` — yet **2.5.6 went live and 2.5.7+43
> uploaded successfully with no app-level privacy manifest at all.** If a missing manifest failed
> upload validation, those uploads could not have happened.
>
> More precisely, upload validation checks **required-reason API declarations**
> (`NSPrivacyAccessedAPITypes`, e.g. ITMS-91053) — and those can be satisfied entirely by the
> bundled plugins' own manifests (`shared_preferences_foundation` ships one). The part this build
> actually adds — **`NSPrivacyCollectedDataTypes`, the 12 first-party data types** — is **not
> validated at upload at all**. It feeds the privacy report, while the App Privacy "nutrition label"
> comes from the ASC questionnaire, filled in by hand.
>
> **To actually close this**, do one of:
> 1. In App Store Connect, generate the **privacy report** for build 277 and confirm the 12
>    first-party data types appear; or
> 2. Download the Codemagic IPA artifact, unzip, and confirm
>    `Payload/Runner.app/PrivacyInfo.xcprivacy` exists.
>
> Either takes a couple of minutes and turns a structural argument into an observation.
>
> ### ⚠ Same join-key caveat — the iOS build number will NOT be 64
>
> `codemagic.yaml` overwrites pubspec's build number with
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`. **Match on `68786e9` / `dad7329`.**

---

## 2.5.10+63 — frozen-segment fix (seg.frz cleared on every segment write)

| Field | Value |
|---|---|
| **Git SHA** | `a3468058d3eab379095786d48084cd09607b2f20` (`a346805`) — the build commit |
| **Merged to main** | `d0c4753aa0c49dbaf7708dea8ab513b55b577f31` (`d0c4753`, `--no-ff`), **pushed to origin 2026-08-05** |
| **Branch at build time** | `fix/frozen-segment-clear` (off `main` @ `8326c47`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **63** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,239,711 bytes · built 2026-08-05 09:55 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (2026-08-05 09:55) — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch to build** | **`main` tip.** Commits after the merge `d0c4753` are docs-only, so `lib/ android/ ios/ pubspec.yaml codemagic.yaml test/` are byte-identical to the build commit. Stable identifiers are **`a346805`** (build) and **`d0c4753`** (merge) |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**Contents:** `normalizeWledPayload` clears `seg.frz` on any seg entry without an `i` key — one
chokepoint covering both transports and ~66 `applyJson` call sites. New pure
`ensurePsaveClearsFreeze` synthesizes `{id, frz:false}` for seg-LESS psaves, so the
schedule-fired ON-presets (1/3/4/5) cannot be poisoned. Participation lookup wrapped `try/catch`
with a segment-0 fallback (`savePreset` had no I/O of its own before this).

**Why:** a per-pixel write sets `seg.frz = true` on WLED 0.15.1; a frozen segment does not run its
effect, so every segment-level colour/effect write was stored, answered 200, read back correctly —
and never reached the LEDs. Found by **wire replay** after three source-reading passes each produced
a wrong hypothesis; every Dart layer was correct and the defect was one WLED field never sent.
The `psave` half is the durable one: a preset saved while frozen re-freezes on every load and cannot
render its own colours, and schedule sync always-psaves from live state.

**Fleet exposure at time of fix: ZERO** — no account holds a single `pixelMap` document (all 24 user
docs scanned).

**Test suite at build time:** 1893 passed · 3 skipped · 1 failed (`cloud_ai_processor_normalize` —
pre-existing stale P1-8 assertion). 1878 baseline + 15 new = 1893, so no test was lost. Analyze on
all changed files: **0 errors, 0 warnings** (28 pre-existing info).

**Hardware verification: 5 of 6 on 192.168.1.150.** Freeze → fixed segment write clears and renders
→ per-pixel still paints (ordering `base(frz:false) → per-pixel` verified, not assumed) → psave
while frozen stores `[False, False]` (pre-fix `[True, False]`) → loading it does not re-freeze.
Rig restored byte-equal.

> ### ⚠ HARDWARE DEBT CARRIED FORWARD — now owed on +60, +61, +62 AND +63
>
> - **Token refresh 4.2** — undischarged since +60.
> - **Commissioning a-d (P0-5 / P0-6 / P0-7)** — **blocked by rig pairing state**, not by time.
>   `bridge_discovery_service.dart:90` filters `status == 'unpaired'`, so the already-paired bench
>   rig never appears and the wizard cannot reach the roofline step. No supported app-side unpair
>   exists (`/api/reset` over LAN or a re-flash). Carries to the next genuine install.
> - **NEW: P1-50 step 6** — undo/erase confirmed in the RUNNING editor on a handset. Only the wire
>   equivalent is proven. **P1-50 stays OPEN until this is done.**
>
> ### ⚠ Same join-key caveat — the iOS build number will NOT be 63
>
> `codemagic.yaml` overwrites pubspec's build number with
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`. Only the version *name* survives from the repo.
> **Match on `a346805` / `d0c4753`.**

> ### ⛔ THIS AAB IS SUPERSEDED — DO NOT UPLOAD
>
> The +63 artifact above was built **before** the #84 instrumentation was stripped, so it still
> contains `captureBug84`, which performs a **Firestore write to `users/{uid}/debug_errors`
> carrying `errorMessage` and `stackTrace` in release builds**. That is a data-collection path that
> must not go to review undeclared.
>
> The strip landed after this build (see the commit following `d0c4753`). **`main` no longer matches
> this AAB.** A fresh build is required before any upload, and it must take **versionCode ≥ 64** —
> 63 is consumed by the artifact on disk.
>
> The Git SHA / versionCode rows above remain accurate for *this artifact*; they are kept so a
> crash report against it can still be resolved.

---

## 2.5.10+62 — P0-9a tri-state lease-ledger gate

| Field | Value |
|---|---|
| **Git SHA** | `306f3d233097a181c5866e69979ef4410dc6a15b` (`306f3d2`) — the build commit |
| **Merged to main** | `43e85c8457e3ebb8173f769ae986bc617cb8170c` (`43e85c8`, `--no-ff`), **pushed to origin 2026-08-03** |
| **Branch at build time** | `fix/p0-9a-lease-tristate-gate` (off `main` @ `c0ebe36`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **62** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,239,152 bytes · built 2026-08-03 13:33 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (2026-08-03 13:33) — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch to build** | **`main` tip** — just pick the branch; Codemagic defaults to its tip. Every commit after the merge `43e85c8` is **docs-only** (`docs/`, `audit/`), so `lib/ android/ ios/ pubspec.yaml codemagic.yaml test/` are byte-identical to the build commit and the IPA is the same from any of them. Deliberately NOT pinned to a SHA here — naming a tip in a file that lives on the tip just chases itself. The stable identifiers are **Git SHA `306f3d2`** (build commit) and **`43e85c8`** (merge); record the actual built SHA below when Codemagic reports it |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**Contents:** P0-9 part (a) only — the tri-state lease-ledger gate.
`activeLeaseTimers()` returns a sealed `LeaseLedgerLoading | LeaseLedgerEmpty | LeaseLedgerReady`
instead of a bare list, so "no leases" and "ledger not loaded yet" stop sharing one representation.
`_initialized` is consulted in production for the first time (it existed, was set correctly, and was
read only by a `@visibleForTesting` getter). `calendarLeaseActiveTimersProvider` reads the flag
*stream* rather than the sync adapter, which collapsed `AsyncLoading → false` and licensed the same
clobber one level up. `syncAll` refuses the cfg write on `Loading`
(`ScheduleSyncResult.deferredLeaseLedger`, neutral UI, bounded 3-attempt backoff retry).

**Verification:** suite 1878 pass / 3 skipped / 1 fail (pre-existing stale
`cloud_ai_processor_normalize`, P1-8). `flutter analyze` on all changed files: 0 errors, 0 new
warnings. **Bench end-to-end on 192.168.1.150** (real `syncAll`, real `WledService`): cold-ledger
sync wiped a live lease and returned `success=true` (case 0), gate leaves the table byte-identical
with no POST (case 1), warm sync arms schedule + lease together (case 2). Rig restored to baseline
and verified. Full report: `audit/LEASE_TRISTATE.md`.

**Ships into, but does NOT change:** solar is still OFF fleetwide —
`config/solar_scheduling` has never existed in either Firebase project, and this build does not
create it. **Still open:** P0-9b (ledger durability — reinstall / second device) and P0-9c
(`_kLeaseStorageKey` not uid-namespaced).

> **Note on numbering.** This was requested as "+61". versionCode **61 was already consumed** by the
> build below — merged (`c5c7baf`), pushed, ledgered, and its AAB preserved on disk as
> `versionCode61-816aa1b-solar-and-clobber-guard.aab.bak`. Re-cutting +61 would have made the pushed
> +61 row describe contents it does not have, so this is **+62**. The solar fix and all-stub clobber
> guard listed in the +62 request shipped in +61; +62 adds only the lease gate on top.

---

## 2.5.10+61 — solar failure made legible + all-stub clobber guard

| Field | Value |
|---|---|
| **Git SHA** | `816aa1b538e947ad8d801bfe1d26f2349ff019db` (`816aa1b`) — the build commit |
| **Merged to main** | `c5c7baf1f280ce07d22eee4114d3dfce1ec5e911` (`c5c7baf`, `--no-ff`), **pushed to origin 2026-08-03** |
| **Branch at build time** | `fix/solar-legible-and-clobber-guard` (off `main` @ `624d347`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **61** — verified from the merged manifest (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,237,215 bytes · built 2026-08-03 12:18 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` (2026-08-03 12:17) — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), **started manually** — `codemagic.yaml` still has no `triggering:` block (re-verified this build) |
| **iOS branch built** | `main` @ `c5c7baf` |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

**Contents:** `presetErrors` text now renders at both display sites (was a bare count, discarding
the composed remedy); abort message rewritten without the `internal:` prefix; five UI surfaces
gated on the solar flag (editor, autopilot baseline, AI prompt schema, commercial events,
neighborhood sync); `_offTrigger` default flipped off solar; `shouldSkipClobberingWrite` +
`countRefusal` at five refusal points; both display sites reordered so warnings survive the
`!success` branch. Audit trail: `audit/SOLAR_FIX.md`, `audit/ALL_STUB_GUARD.md`,
`audit/ALL_STUB_CLOBBER.md`, `audit/ELLIE_SUNSET.md`.

**Test suite at build time:** 1867 passed · 3 skipped (hardware-gated) · 1 failed
(`cloud_ai_processor_normalize` — pre-existing stale P1-8 assertion, pins behavior deliberately
removed by `b6ca2f1`; count matched the expected baseline exactly, so no stash proof was needed).
Analyze on all changed files: **0 errors, 0 warnings** (15 pre-existing info-level lints).

**Known-open at ship:** solar still does not work — this build makes the failure legible and stops
it spreading; `config/solar_scheduling` is deliberately NOT created. The flag flip is gated on a
solar comparator that does not exist (`isRealEnabledTimer` excludes `hour == 255`). **P0-9** open —
lease timers occupy general slots 0-7, protected only by a same-write merge from a device-local
SharedPreferences ledger. `firestore.rules` deliberately untouched (controller_ips mid-soak).

> ### ⚠ Same join-key caveat as +60 — the iOS build number will NOT be 61
>
> `codemagic.yaml` still overwrites pubspec's build number:
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`, then `sed`s it into pubspec. Only the version
> *name* (`2.5.10`) survives from the repo. **Android `versionCode 61` and the iOS build number
> identify the same code only through `816aa1b` / `c5c7baf`.** Match on the SHA.

---

## 2.5.10+60 — commissioning silent-failure closeout

| Field | Value |
|---|---|
| **Git SHA** | `d92262fbf86cc5aafbd95fd76e5e339d8783b8cf` (`d92262f`) — the build commit |
| **Merged to main** | `4bd2227f339807fb08626a7f5ba6319669498a4a` (`4bd2227`, `--no-ff`), **pushed to origin 2026-07-31** |
| **Branch at build time** | `fix/commissioning-silent-failures` (off `main` @ `c20ed83`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **60** — verified from the merged manifest (`build/app/intermediates/bundle_manifest/release/processApplicationManifestReleaseForBundle/AndroidManifest.xml`), not pubspec |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,227,800 bytes · built 2026-07-31 11:29 |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` — archive these, never commit |
| **Android track** | **NOT UPLOADED** — Tyler uploads |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), started **manually** — `codemagic.yaml` still has no `triggering:` block |
| **iOS branch built** | `main` @ `4bd2227` |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |

> ### ⚠ The iOS build number will NOT be 60 — the SHA is the join key
>
> `codemagic.yaml` overwrites pubspec's build number before building:
> `BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}`, then `sed`s it into pubspec. Only the
> version *name* (`2.5.10`) survives from the repo. `PROJECT_BUILD_NUMBER` is **Codemagic's
> own counter**, so iOS will ship as `2.5.10+<codemagic counter>` — some number that is not
> 60, and not predictable from here.
>
> **Android `versionCode 60` and the iOS build number identify the same code only through
> `d92262f` / `4bd2227`.** When matching a TestFlight build or a crash report to this change,
> match on the SHA.

**What shipped:** three fixes on the commissioning surface, all the same class — reporting
success for work that did not happen.

- **P0-7** — the roofline pixel-map save could fail silently and the wizard advanced anyway.
  Now a blocking retry gate; the cause is logged and shown; an empty capture still passes
  through. No offline-queue option (it would relocate the failure, not fix it).
- **P0-6** — `migrateInstallerControllersToCustomer` swallowed every failure, so a denied
  migration handed over a customer account with no controllers. Now throws, with a Retry/Stop
  dialog matching `_restoreInstallerAuthWithRetry`; Stop reports the install as FAILED.
- **Token refresh + anon-fallback telemetry** — `_restoreInstallerAuth` re-mints the staff
  custom token from the cached PIN instead of dropping to `signInAnonymously()`. **This build
  is the D4 dependency**: it must be adopted, and the `installer_anon_fallback` count must
  reach zero, before the resource rules tighten.

**firestore.rules:** no new changes in this build. It carries the **already-deployed** P0-5
fix (ruleset `ec8d918f-c279-4925-b8b2-168e96638586`, live `2026-07-31T15:10:10Z`), committed
here so the repo matches production. D4 is not in this build.

**Test suite at build time:** 1857 passed · 3 skipped · 1 failed
(`cloud_ai_processor_normalize` — pre-existing, P1-8, proven by stash). `flutter analyze`
clean on all six changed files.

**Rules verification at build time:** 16/16 against the **live** ruleset via the Rules `:test`
API (including cross-dealer DENY), plus a 31-path deployed-vs-live regression with 0
behavioral differences.

**Hardware verification at upload: NONE.** All three owed debts — token refresh §4.2,
commissioning a–d, and Part B (Design Studio slices 0–5) — are consolidated into one runnable
session in `audit/HARDWARE_VERIFICATION_+60.md`. Nothing in this build has been exercised on
the rig. The P0-6 Retry/Stop dialog is additionally not widget-testable (no auth-mocking
dependency); its mechanism is unit-pinned, the dialog is not.

**Known-open at ship:** P3-60 (`kStaffAuthTelemetryAppVersion` is hand-bumped — verified
`2.5.10+60` for this build, but it will drift), P3-61 (aborting after account creation is
unrecoverable in-app), P3-62 (stale line-number cross-references), F-5a/F-5b (account
deletion — unrelated to P0-7 despite the label collision, still open).

---

## 2.5.10+59 — ON-presets self-heal master power

| Field | Value |
|---|---|
| **Git SHA** | `d2e4d5b043b58a3e5c32e82697a36d015effecab` (`d2e4d5b`) |
| **Branch at build time** | `fix/preset-master-power-heal` (off `main` @ `393af46`) |
| **Version name** | `2.5.10` |
| **Android versionCode** | **59** — verified from the merged manifest |
| **Android artifact** | `build/app/outputs/bundle/release/app-release.aab` · 68,206,827 bytes |
| **Android build flags** | `--release --obfuscate --split-debug-info=build/debug-info/android` |
| **Android symbols** | `build/debug-info/android/app.android-{arm,arm64,x64}.symbols` |
| **Android track** | Play **Closed testing** — **UPLOADED 2026-07-30**, confirmed Closed (not Internal; Internal would not advance the 12-tester production-access streak) |
| **iOS Codemagic build number** | `PENDING` — fill when the build completes |
| **iOS workflow** | `ios-workflow` ("iOS Release"), started **manually** (no `triggering:` block) |
| **iOS branch built** | `PENDING` — build from `main` (merged as `9d4fa99`) |
| **iOS distribution** | TestFlight **internal only** (no `beta_groups:` in `codemagic.yaml`) |
| **Merged to main** | `9d4fa99` (`--no-ff`), pushed 2026-07-30 — **merged ahead of the device smoke test at owner's direction**; see that commit's body |

**What shipped:** ON presets 1/3/4/5 now assert root master power, so a fired
ON-timer turns the lights on instead of loading a design into a dark master.
Fixes the name-only skip predicate that made `9158c00` (2.5.10+50) inert on
every controller commissioned before it, and adds an on-connect healer so
existing controllers repair without the customer editing a schedule.

**Hardware verification (bench rig 192.168.1.150, WLED 0.15.1, vid 2507300):**

- Pre-merge: end-to-end timer fire — `ps 2→1` **and** `state.on == true`. Bench
  harness 18/28 → 27/28.
- **Post-merge, with the SHIPPED build on a real device** (evidence commits
  `73a3745`, `adb256a`, `c09d086`): all four ON presets deliberately broken and
  confirmed `root_on=ABSENT` → **first connect healed all four** to
  200/51/102/153 → **second connect: no flash, zero writes**, presets
  byte-identical to the healthy baseline and `state.on` still false. The
  psave-storm hard stop is **cleared**.
- Four presets were broken rather than one on purpose: a single broken preset
  exercises the predicate but skips the settle / retry / final-readback path,
  which exists because four back-to-back psaves produced a false green during
  development.

**Smoke coverage at upload: partial.** Connect + heal + idempotency (checklist
steps 1-4) are verified. **Steps 5-13 are NOT** — schedule create/edit/delete,
boundary firing, calendar-lease interaction, sunrise-off, brightness presets.
The lease interaction is the highest-risk gap: schedule-vs-lease clobbering has
shipped before and this change touches the same preset-write path.

**Test suite at build time:** 1834 passed · 3 skipped (hardware-gated) · 1
failed (`cloud_ai_processor_normalize` — pre-existing, proven by re-running with
the change stashed).

**Known-open at ship:** `P3-56` (ON-preset definitions in two places), bench
`layout drift` baseline artefact (needs `probe --update`).

---

## Rows before this one

This ledger starts at **2.5.10+59**. Earlier builds predate it; their identity
must be reconstructed from `git log` (`chore(release):` and `chore: bump to`
commits) and the Play Console / App Store Connect upload history. Reconstructing
them retroactively is not recommended — record forward, do not guess backward.
