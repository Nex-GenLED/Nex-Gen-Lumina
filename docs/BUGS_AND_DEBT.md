# BUGS_AND_DEBT — canonical tracking ledger

**As of 2026-07-22 (post schedule-stack saga).** This is the working checklist for all known
bugs, tech debt, and promised features. Not documentation prose — keep it terse.

## Conventions
- **Never delete an item.** When fixed, check it off (`[x]`) and append the fixing commit SHA.
- **Every fix that claims bench verification MUST cite the readback** (curl `/json/state` or
  `/json/cfg` output, or a saved dump path). "Bench-verified" with no readback is not verified.
- **Evidence tags** — `bench-proven` (reproduced on hardware w/ readback) · `reported`
  (observed in-app, not isolated) · `suspected` (inferred, unconfirmed).
- **WLED behavior-claim rule:** every claim about WLED behavior must be tagged
  `verified-by-bench` / `verified-by-source` / `assumption`. Only the first two may appear in
  a fix prompt. Assumptions get bench-checked (see #21) before they gate code.
- Status values: `OPEN` · `IN-PROGRESS` · `BLOCKED` · `DONE <sha>`.

---

## P0 — customer-visible, blocks "sell with certainty"

- [ ] **P0-1 — AI intent applies scheduled commands IMMEDIATELY (Symptom B)**
  - Status: OPEN · Evidence: bench-proven
  - "warm white 2:25–2:30" changed lights instantly and wrote **zero** timers. The AI
    text/voice path bypasses the hardened schedule-sync entirely.
  - Files: `lib/features/ai/scheduling_intent_handler.dart`,
    `lib/features/ai/scheduling_intent.dart`, `lib/features/ai/lumina_smart_scheduler.dart`,
    `lib/features/ai/cloud_ai_processor.dart`, `lib/features/ai/local_command_parser.dart`,
    `lib/features/ai/lumina_command_router.dart` → must route to
    `lib/features/schedule/schedule_sync.dart`.
  - Blocks: P0-2, P1-5, P1-11.

- [ ] **P0-2 — Remove "Generate week" button; port to text/voice intent handling**
  - Status: BLOCKED (by P0-1) · Evidence: reported (product decision made)
  - Don't consolidate the door onto a broken sync path. Land P0-1 first.
  - Files: `lib/features/schedule/my_schedule_page.dart` (generate-week UI),
    `lib/features/schedule/schedule_plan_controller.dart`; target = AI scheduling intent path.

- [ ] **P0-3 — Lease-writer unification (last fire-and-forget cfg writer)**
  - Status: OPEN · Evidence: reported
  - `calendar_entry_lease_manager` `_writeLeaseToWled` / `_writeZeroedSlot` write cfg with no
    verify, no readback, no guard. Route through the hardened cfg path (timeout+retry+readback+
    settle) used by `schedule_sync.dart`.
  - Files: `lib/features/schedule/calendar_entry_lease_manager.dart`.

- [ ] **P0-4 — System presets 1/3/4/5 ib-heal check**
  - Status: OPEN · Evidence: suspected (bench-verify pending)
  - Name-based skip in the psave path may prevent re-saving presets with `ib:true`; if stale,
    "NGL On / Dim / Low / Medium" won't assert master power when fired. Bench-verify AFTER a
    +51 Sync (curl presets.json); fix the skip trigger if the ib flag is absent.
  - Files: `lib/features/schedule/schedule_sync.dart` (`_scheduleDesignMatches` / psave skip).

---

## P1 — correctness & trust

- [ ] **P1-5 — Gamma drift root cause (Symptom C)**
  - Status: OPEN · Evidence: bench-proven (symptom) / suspected (cause)
  - `gc.col` flipped 2.8→1 during the AI-command window; self-healed by the pusher on-connect.
    Source never found. Fold into the P0-1/P0-2 AI-path diagnostic.
  - Files: AI apply path (see P0-1) + `light.gc` writer (gamma push on connect).

- [ ] **P1-6 — Unexplained en:1 evidence row (git archaeology)**
  - Status: OPEN · Evidence: reported (contradicts curl truth table)
  - An f53eec7-era dump showed `en:1` from a reportedly-bool builder, contradicting the curl
    truth table (en must be INT). Pull the actual `f53eec7` blob, settle provenance, and record
    the answer in the en-int comment if it changes anything.
  - Files: `lib/features/schedule/schedule_sync.dart` (en-int comment); git `f53eec7`.

- [ ] **P1-7 — Orange "synced with 1 warning" identity**
  - Status: OPEN · Evidence: suspected (slot exhaustion at 8/8)
  - Never confirmed which warning fired. Answer from logs; ensure warning copy is
    user-interpretable.
  - Files: `lib/features/schedule/schedule_sync.dart` (sync result/warning),
    `lib/features/schedule/schedule_overload_banner.dart`.

- [ ] **P1-8 — Two stale tests mask real failures**
  - Status: OPEN · Evidence: reported (2 pre-existing suite failures)
  - `schedule_sync_time_parse` (asserts flag-disabled solar behavior) and
    `cloud_ai_processor_normalize` ('Sunset'). Fix or delete.
  - Files: `test/…/schedule_sync_time_parse*`, `test/…/cloud_ai_processor_normalize*`.

- [ ] **P1-9 — Roofline widget tests flaky under full-suite load**
  - Status: OPEN · Evidence: reported (pass in isolation, flake in suite)
  - Stabilize or quarantine explicitly (tagged skip w/ reason, not silent).
  - Files: `test/…/roofline*`.

- [ ] **P1-10 — Design-name attribution: schedule fires**
  - Status: OPEN · Evidence: reported
  - After a timer fires, app shows raw WLED effect names ("Solid", "Running") instead of the
    design name. **DIAGNOSTIC FIRST:** curl `/json/state` after a fire — if `ps` shows the
    slot, this is pure app-side mapping (ps → app-owned slot → design name); if `ps:-1`, needs
    P1-11's record.
  - Files: state readback / name resolver — `lib/features/ai/pattern_label_resolver.dart`,
    dashboard state display in `lib/nav.dart`.

- [ ] **P1-11 — Design-name attribution: Game Day / live applies (ps:-1)**
  - Status: OPEN · Evidence: reported
  - Same symptom for non-preset applies where `ps:-1`. Needs a "last applied design" record
    written at apply time. **Rides with** the P0-1..P0-3 consolidation — instrument the
    surviving write paths, not the doomed ones.
  - Files: surviving apply paths (post-consolidation) + a persisted last-applied record.

---

## P2 — hardening & platform

- [ ] **P2-12 — Slot-cap guard (WLED preset max 250)**
  - Status: OPEN · Evidence: bench-proven (251+ silently no-ops)
  - Guard the app's slot allocation against the 250 ceiling.
  - Files: `lib/features/schedule/schedule_sync.dart` (slot allocation),
    `lib/features/schedule/calendar_entry_lease_manager.dart`.

- [ ] **P2-13 — Empty-armed guard verification**
  - Status: OPEN · Evidence: reported (mislabeled in +51 report)
  - +51 report mislabeled it (`splitByTimerCapacity`); grep to confirm the real guard
    (armed-but-zero-armable → loud fail) survived the merges.
  - Files: `lib/features/schedule/schedule_sync.dart`.

- [ ] **P2-14 — Firmware stall on cfg flash-save (vid 2507300)**
  - Status: OPEN · Evidence: bench-proven
  - cfg flash-saves black out controller network for minutes. App tolerates; nothing fixes.
    Evaluate WLED version-pin (0.15.1, see SOP §2.0) before fleet scale.
  - Files: firmware/version-pin policy (no app fix).

- [ ] **P2-15 — Codemagic build-number override**
  - Status: OPEN · Evidence: reported
  - Phone reports CM's counter, not pubspec `+N`; SHA is the only reliable identity. Let
    pubspec drive it, or stamp the git SHA into the About screen.
  - Files: `codemagic.yaml`, About/settings screen (`lib/features/site/`).

- [ ] **P2-16 — Node 20→22 Cloud Functions upgrade**
  - Status: OPEN · Evidence: reported (deadline before Oct 2026 decommission)
  - Files: `functions/package.json` (engines), `functions/` runtime config.

- [ ] **P2-17 — Dead `_controllerIps` plumbing**
  - Status: OPEN · Evidence: suspected (gated on prod confirmation)
  - Remove once `applySyncPattern` confirmed in production. Currently 1 live lib site +
    audit/backlog docs.
  - Files: `lib/features/sports_alerts/services/alert_trigger_service.dart` (+ referenced in
    `docs/audits/AUDIT_assumption_gaps_2026-06.md`, `docs/BUG_BACKLOG.md`).

---

## Features promised (post-cleanup)

- [ ] **F-18 — One-shot date-specific schedules**
  - Status: OPEN · Evidence: bench-proven (controller supports start/end month/day blocks)
  - Include a slot-cleanup story — one-shots must not eat slots forever.
  - Files: `schedule_models.dart`, `schedule_sync.dart`, `my_schedule_page.dart`,
    `solar_schedule_cleanup.dart` (cleanup pattern).

- [ ] **F-19 — "Run Now" on a scheduled event**
  - Status: OPEN · Evidence: reported
  - `/json/state` only. **NO new cfg writers, ever.**
  - Files: `my_schedule_page.dart` + `schedule_day_row.dart`; apply via WledRepository state.

- [ ] **F-20 — Warning copy when syncing a fully-disabled schedule**
  - Status: OPEN · Evidence: reported
  - Green is true but useless; add a nudge when a synced schedule has nothing armable.
  - Files: `schedule_sync.dart` (result), `schedule_off_warning.dart` / overload banner.

---

## Multiplier — do FIRST after main merge

- [ ] **M-21 — `bench/` CLI harness**
  - Status: OPEN · Evidence: n/a (tooling)
  - Seed / sync-sim / verify / probe against the bench controller (`192.168.1.150`). Extract
    from this week's proven curl loops: cfg write + readback assert, en truth-table check,
    preset shape verify, timer-fire test, presets.json diff. Nearly every item above needs
    bench verification; this makes each one cheaper.
  - Files: new `bench/` dir (CLI scripts).

---

## Attack order

```
main merge
  → branch cleanup
  → M-21 (harness)
  → P0-1 + P0-2 + P1-5 + P1-11  (one AI-path cycle)
  → P0-3
  → P0-4
  → P1-10
  → P1 archaeology batch (P1-6, P1-7, P2-13)
  → P2 batch
  → features (F-18, F-19, F-20)
```
