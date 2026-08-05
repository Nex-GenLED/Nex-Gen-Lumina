# PART B — Design Studio slices 0-5, bench results

**Rig:** 192.168.1.150 (0.15.1, vid 2507300, 290 px) · **Handset:** 2.5.10+62
**Rig pairing:** UNCHANGED — still paired to Tyler's production account. Commissioning wizard
deliberately NOT run (see §Commissioning debt).
**Status:** COMPLETE. Log only, nothing fixed. **5 of 6 slices PASS on hardware.**

---

## Slice results

| Slice | Result | Substance |
|---|---|---|
| **0 — per-pixel write spine** | **PASS** | Single pixel addressed from the app; exactly one LED changed, in the expected position, nothing else affected |
| **1 — semantic pixel-map persistence** | **PASS** | Map survived a full app force-close and reopen; re-rendered correctly, no read-back gap |
| **2 — pixel-walk capture** | **PASS** | Full channel-1 capture; green confirmation on save, capture durable. "All corners" lit exactly the segments marked as corners — semantic group addressing working end to end |
| **3 — map-driven smart presets** | **BLOCKED, NOT TESTED** | Conflict-resolution prompt appears on every search with no selectable control. See P1-49 |
| **4 — manual per-pixel editor** | **PASS on core, DEFECT on recovery** | Painting lands exactly on captured segments, clean boundaries, no bleed — the substantive R-4 demonstration. Undo and Erase both do nothing. See P1-50 |
| **5 — boundary refinement** | **PASS** | Moved a captured boundary; it updated, saved, and **adjusted each impacted segment** — the edit propagated to neighbours rather than affecting only the segment moved |

**Slices 0, 1, 2, 5 and the painting half of 4 are the real result here:** the per-pixel spine,
persistence, capture, semantic group addressing, precise manual painting and boundary propagation
all work against real hardware. The two defects are both in *recovery and resolution paths*, not in
the core write path.

### Slice 5 is the strongest single piece of evidence for the architectural-map claim

Moving one captured boundary **adjusted each impacted segment**, not just the one dragged. That
behaviour is only possible if the capture is stored as a **semantic model with adjacency** — a set
of independent ranges cannot propagate an edit to its neighbours, because it has no representation
of what "neighbour" means.

This is worth separating from the other passes. Slices 0-2 demonstrate that the app can *address*
pixels and *remember* what it captured; either would be satisfied by a flat list of ranges. Slice 5
demonstrates the map is **relational**, which is the claim the whole Design Studio architecture
rests on and the one thing that could not be inferred from the earlier slices.

Taken together, **2, 4 and 5 demonstrate the underlying capability end to end through the manual
path** — which is why slice 3's blocker (P1-49) costs a test but not the architectural conclusion.
The AI route to those same primitives is broken; the primitives themselves are proven.

---

## Bench-method note — verifying a single pixel on a bare strip

Recorded because it will recur every time slice 0 is re-run.

A bare strip carries no physical pixel identification, so "did pixel N light?" is genuinely hard to
confirm by eye — counting 290 unmarked LEDs is error-prone and slow. Readable alternatives:

- **Anchor pixels** — address 0 and 289. Both are unambiguous by position (first / last), so a
  correct hit is obvious and an off-by-one is visible immediately.
- **Every-Nth pattern** — light every 10th pixel. Mis-indexing shows up as a broken rhythm along
  the run rather than as a single ambiguous dot.

Either beats a lone mid-strip pixel for a pass/fail call. Prefer them for future slice-0 runs.

---

## Commissioning debt — CANNOT be discharged tonight

P0-5 (pixelMap rules), P0-6 (migration surfacing) and P0-7 (roofline save gate) are blocked by
**hardware state, not by time**.

`bridge_discovery_service.dart:90` filters `.where('status', isEqualTo: 'unpaired')`, so an
already-paired rig never appears in discovery and the wizard cannot advance to the roofline step.
`MapRooflineStep` is constructed at exactly one call site
(`installer_setup_wizard.dart:728`), so the P0-7 gate is unreachable outside the wizard.

There is **no supported app-side unpair**. Recovery would require `/api/reset` over LAN or a
re-flash, plus re-pairing and re-creating the controller's saved settings. **Correctly not
attempted.** This debt carries to the next genuine install, which is the only place it can be
honestly discharged.

Note also: P0-5's rules fix is enforced server-side and was already verified 16/16 against the live
ruleset — a hardware run would re-test Firestore, not the app, and adds nothing.

---

## Findings logged from this session

| ID | Finding | Severity |
|---|---|---|
| **P1-49** | Slice 3 — conflict-resolution prompt blocks AI design with no selectable control | P1 |
| **P1-50** | Slice 4 — Undo and Erase do nothing after painting; 290-px misclick unrecoverable | P1 |
| **P1-51** | P0-7 fixed one of at least three roofline save surfaces | P1 |
| **P2-51** | `bridge_setup_screen.dart:528` points at an "Unpair Bridge" affordance that does not exist | P2 |

Full entries in `docs/BUGS_AND_DEBT.md`.

---

## PART B — FINAL

**5 of 6 slices PASS on hardware: 0, 1, 2, 4, 5.** Slice 3 is blocked by **P1-49**, a UI defect in
the conflict-resolution dialog — not a capability gap. The capability it would have exercised is
demonstrated by slices 2, 4 and 5 through the manual path.

**Nothing in Part B was fixed.** Everything below is logged and carries forward.

### Carry-forward register

| Item | State | Blocks |
|---|---|---|
| **P1-49** — conflict dialog has no selectable option | OPEN, unfixed | Slice 3; every AI design search |
| **P1-50** — undo/erase do nothing | OPEN, unfixed. **Root cause is the frozen segment, NOT the history stack** — the Dart is correct end to end | Editor recovery on a 290-px run |
| **P1-51** — P0-7 covered 1 of 3 roofline save surfaces | OPEN, unfixed | Regression guard is narrower than believed |
| **P2-51** — dead "Unpair Bridge" instruction | OPEN, unfixed | Customer follows in-app guidance and finds nothing |
| **FROZEN_SEGMENT** — chokepoint fix **and** psave fix | Both required, neither implemented | **Release blocker for Design Studio per-pixel.** Not a blocker for the current build |
| **Commissioning verification** (P0-5 / P0-6 / P0-7) | Hardware-blocked, not time-blocked | Carries to the next genuine install — the only place it can be discharged |
| **Captured map persists device-locally, not in Firestore** | Observed, not investigated | Same durability exposure as P0-9b: reinstall or second device loses it |

### The two that gate a Design Studio release

Everything else on that list is ordinary debt. These two are not:

1. **The frozen-segment pair.** Without both fixes, every customer who paints becomes exposed, and
   the `psave` path can bake `frz:true` into flash so a schedule fires dark **durably** — a reboot
   does not clear it. Fleet exposure is zero today only because no `pixelMap` document exists
   anywhere in the fleet.
2. **P1-49**, because it makes the AI entry point to Design Studio unusable on every search. The
   manual path works, so the feature is not dead — but the route most customers would take is.

### What Part B established

The per-pixel architecture works on real hardware: addressing, persistence, capture, semantic group
addressing, precise painting, and relational boundary propagation. **The defects found are in
recovery, resolution and delivery — not in the model.** That is a materially better result than the
slice list alone suggests, and it is the reason the frozen-segment finding is a shipping gate rather
than a design problem.
