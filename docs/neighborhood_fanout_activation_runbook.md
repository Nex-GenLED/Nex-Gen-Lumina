# Neighborhood Sync crew fanout — activation runbook (P1-44)

**Status: STEPS 1–3 DONE — fanout is dormant by FLAG. Remaining: step 4 (two-node
test) + step 5 (console flip).** The server-side crew fanout has still never
executed in production, but the reason changed: as of **2026-08-12** the doc
EXISTS at `{enabled:false}`, the rule (read **+** create) is live in ruleset
`93c99c50-0b3d-4a72-b76f-eb6f3040550d`, and `applySyncPattern` is deployed
current (`2026-07-25T19:55:32Z`, ACTIVE — no src commit since). So the flag reads
`false` because it is *set* false, not because it is missing. **Nothing here
auto-deploys; the `enabled:true` flip is console-only.**

## What fanout does
When ON, the initiator's "Start" tap ALSO calls the Cloud Function
`applySyncPattern` with `fanout:true`, which (admin SDK) writes the command into
every consenting crew member's own `/users/{uid}/commands` queue — so closed-app
members get synced without the app open. When OFF (today), only the existing
`neighborhoods/{groupId}/commands` broadcast fires, which only app-open members
apply.

## Anti-strobe protection (already live in code)
`reserveFanoutSlot` ([applySyncPattern.ts:549]) is a real Firestore transaction
(serializes concurrent function instances on `neighborhoods/{groupId}/rate_limits/state`,
admin-only) delegating to the pure `evaluateRateLimit` ([:490]):
- **per-initiator cooldown:** `INITIATOR_COOLDOWN_MS = 18000` (18s between one
  initiator's fanouts)
- **per-group ceiling:** `GROUP_CEILING_PER_MIN = 5` in a rolling
  `RATE_WINDOW_MS = 60000` (60s) window
- Wired at [applySyncPattern.ts:166], BEFORE `fanoutToCrew`; on reject writes
  nothing and returns `200 {ok:false, reason:"rate_limited", retryAfterMs}` and
  the app suppresses its broadcast too.
- ✅ **Tested** (was flagged as a gap; closed by `25baadb`, re-verified 2026-08-12):
  `functions/test/unit/fanoutRateLimit.test.js` + `fanoutMutualMembership.test.js`,
  **17/17 pass** against the tsc-compiled `lib/`. Run them with **`npx jest`** from
  `functions/` — `node --test` fails with `describe is not defined` (the files use
  jest globals and never import `node:test`).

## Ordered activation checklist

- [x] **1. Deploy the create-rule** — **DONE.** Live in ruleset
      `93c99c50-0b3d-4a72-b76f-eb6f3040550d` (release `cloud.firestore`,
      updateTime `2026-08-05T19:27:10Z`), verified by reading the deployed source:
      `allow read: request.auth != null`; `allow create` gated on
      `request.resource.data.enabled == false`; `allow update, delete: if false`.
      Rode along with the command-safety/solar deploy.
- [x] **2. Provision the doc with `enabled:false`** — **DONE.** `config/sync_fanout`
      = `{enabled: false}` (admin read 2026-08-12). Provisioned out-of-band, i.e.
      option (A) console create — `bootstrapSyncFanoutFlagDoc()` is still never
      called, so option (B) remains unwired if fresh installs ever need to
      self-provision.
      ⚠️ **Existence ≠ client-readable.** This was an ADMIN read, which bypasses
      rules. The deployed `allow read` above is the evidence for client
      readability; if that is ever in doubt, re-verify with a NON-ADMIN client
      token (the solar flag burned a day on exactly this distinction).
- [x] **3. Deploy the CF** `applySyncPattern` — **DONE / current.** updateTime
      `2026-07-25T19:55:32Z`, state ACTIVE. All SYNC-1/2 source predates it
      (`7d71374` 2026-07-01, `76324ce` 2026-07-25T02:11Z, `25baadb`
      2026-07-25T15:46Z) and nothing has touched
      `functions/src/applySyncPattern.ts` since — deployed == current source.
      Re-check this line before step 5 if that file has been edited.
- [ ] **4. TWO-NODE VERIFICATION** (see below) — prove a fanout lands on a
      member that is NOT the initiator, on a test group, with `enabled:true`
      set ONLY in a test context (emulator or a throwaway group). Do not flip
      prod yet. GATE: do not proceed unless the non-initiator node converges.
- [ ] **5. Flip `enabled:true`** — Firestore console only, on
      `config/sync_fanout`. (Rules deny client update; this is an admin edit.)
- [ ] **6. Monitor** — watch CF logs for `rate_limited` rejects and fanout
      command counts; watch a real crew for correct closed-app delivery; be
      ready to flip back to `false` (instant kill — the app + CF both re-read
      the flag live).

## BOOTSTRAP options (step 2) — pick one
Doc shape (`bootstrapSyncFanoutFlagDoc`, [sync_fanout_feature_flag.dart:71-90]):
```json
{ "enabled": false, "lastModified": <serverTimestamp>,
  "modifiedBy": "system_bootstrap", "notes": "…" }
```
- **(A) Console create** — simplest, no code/deploy: create `config/sync_fanout`
  in the Firestore console with `{enabled:false}`. Best for a controlled launch.
- **(B) Wire the bootstrap call** — `bootstrapSyncFanoutFlagDoc()` is defined but
  never called. Mirror the lease-flag precedent (`bootstrapCalendarLeaseFlagDoc()`
  called best-effort in `CalendarEntryLeaseManager.initialize()`
  [calendar_entry_lease_manager.dart:450], mounted via main_scaffold): add one
  best-effort `bootstrapSyncFanoutFlagDoc()` call at a startup point (main_scaffold
  or main.dart after Firebase init), try/caught so it never blocks boot. Requires
  the create-rule (step 1) first, else the client create is default-denied.
  Recommendation: **(A) for the initial launch** (deterministic, one doc, no app
  release needed); wire **(B)** later only if fresh installs must self-provision.

## TWO-NODE VERIFICATION (step 4) — prove closed-app fanout
Goal: a command initiated by member A reaches member B (NOT the initiator, app
closed) and B's controller converges with A's.

Setup:
- **Node A (initiator):** the real bench controller `192.168.1.150`.
- **Node B (closed-app member):** a stub HTTP server serving WLED
  `/json/state` — GET returns current state, POST records the applied payload
  (represents B's controller; the bench harness's client already speaks this).
- A test neighborhood group with two member docs (A_uid, B_uid), both
  `isParticipating`; `config/sync_fanout.enabled=true` set ONLY here (emulator or
  throwaway group).
- A **bridge simulator** for B: a poller that drains `/users/{B_uid}/commands`
  (exactly what the ESP32 bridge does) and executes each `applyJson` against
  Node B's stub endpoint.

Run:
1. Snapshot both endpoints' `/json/state`.
2. As A, trigger a fanout sync (the pattern to broadcast).
3. Assert, in order:
   - **server:** the CF wrote a command to `/users/{B_uid}/commands` (fanout
     landed server-side, B ≠ initiator);
   - **delivery:** the bridge-sim drained it and POSTed `applyJson` to B's stub →
     B's `/json/state` now reflects the broadcast pattern;
   - **convergence:** Node A (`.150`) also reflects it → A and B match.
   - **rate limit:** fire a 2nd fanout <18s later → CF returns
     `rate_limited` (initiator cooldown), nothing delivered.
4. Restore both endpoints; delete the test group + rate_limits state.

This is stub-testable end-to-end without a second phone (Node B never runs the
app — it's a command queue + a bridge-sim + a stub controller). It can be added
as a `bench fanout-verify` command (M-21 harness) — not built by this prep.

## Rollback
Flip `config/sync_fanout.enabled` back to `false` in the console — the client
(`syncFanoutEnabledProvider`) and the CF (`readSyncFanoutEnabled`) both re-read
it live, so fanout stops immediately with no deploy.
