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
- **This is the ONE home for items.** `docs/BUG_BACKLOG.md` was folded in here on 2026-07-22
  (items #61–#85, #TD-1..3). That file is now a pointer — do not add items there.
- **Firestore project (source of truth):** `icrt6menwsv2d8all8oijs021b06s5`. NOT
  `nex-gen-lumina-22751`. Always `firebase use icrt6menwsv2d8all8oijs021b06s5` and confirm
  before any `firebase deploy`.
- **SINGLE-OWNER PER STATE DOMAIN** (2026-08-12). When parallel sessions are open, each live
  state domain has exactly ONE owning window; other windows read but never write. Established
  when a Sync window read `config/gameday_planner` five minutes before the watch window armed
  it and reported cleared blockers as live. Game Day domain = flags, configs, sessions, fire
  jobs (`config/gameday_planner`, `game_day_sessions`, `fire_jobs`, `functions/`) → the watch
  window. A stale cross-domain read is not evidence; ask the owner. Read-only diagnostic
  scripts (all-`.get()`, e.g. `scripts/_check_gameday.js`) are exempt — they observe, not own.
  Pairs with the shared-tree rule: commit with an explicit pathspec, never bare `git add`.
- **Numbering hazard:** the live series (`#62`–`#68`) REUSES integers that the folded-in
  `BUG_BACKLOG.md` also used. Old ones are re-labeled `P2-NN … (ex-#NN)` — so `#67`/`#68` below
  are the NEW Game Day items, distinct from `P2-29 (ex-#67)` / `P2-30 (ex-#68)`. Always read
  the `ex-` annotation before assuming a cross-reference.

---

## P0 — customer-visible, blocks "sell with certainty"

- [x] **#66 — END FIRE WITHOUT A START. Lights on at 1am. FIXED + DEPLOYED 2026-08-12.**
  - Status: **FIXED** (GUARD 0 + 0b, deployed) · Severity: **P0** · Blast radius as
    it happened: bench only, because the flip was scoped
  - **Timeline** — `05:45:21.359Z` flag armed (bench-scoped) → `05:50:04Z` the
    `writeJobs || startPlannedAt` gate at `planGameDayFires:499` opens,
    `consecutiveFinalPolls` 0→1 → `05:55:04.001Z` counter→2,
    `REQUIRED_FINAL_POLLS` met, `plan_end reason="confirmed_final"`, job
    `gd_mlb_royals_401816490_end` written, dispatched, **COMPLETED**, payload
    `{"ps":1}` = preset "NGL On" → `05:58:50Z` `endsPlanned: 1` → **bench strip ON
    at 01:00 local**, for a game finished hours earlier whose START this system
    never fired. Ten minutes, two ticks, after arming.
  - **Root cause** — `decideEndSignal` verified `endFiredAt`, `espnIsFinal`,
    `gameStartMs`, minimum duration and two consecutive finals. **Every one passed
    honestly.** None asked whether we started the show. The counter had been
    pinned at 0 for the whole log-only era; arming released it.
  - **Counterfactual** — under a **global** flip this was a simultaneous 1am
    `{"ps":1}` across **all ten** Game-Day-enabled accounts, **seven of them with
    no base layer** (#65) to correct it. The scoped flip is the only reason this
    was one rig instead of a fleet incident.
  - **Fix** — GUARD 0 (`startPlannedAt` required, checked *before* `already_fired`)
    + GUARD 0b (`startJobConfirmsFired`: the start job must read
    `dispatched|completed`). Refusals log as `end_skipped_no_start` /
    `end_skipped_start_never_dispatched`. 11 regression tests.
  - **Start path audited, no mirror-image hole**: it gates on `startFireAt` vs
    `nowMs` recomputed each tick, not on a persisted accumulator, so arming
    unlocks nothing there.
  - **PROCESS LESSON, the one worth keeping**: a first live arm should be scoped
    to a rig you can inspect, even when the dry-run evidence looks clean — the
    dry run *structurally could not* exercise this path (F1), so its cleanliness
    was not evidence of anything.
  - Files: `functions/src/gameDayPlanning.ts` (GUARD 0/0b),
    `functions/src/planGameDayFires.ts`. Related **#65** (no floor), **F1**.


- [ ] **#69 — App Store reviewer account: password ROTATED 2026-08-13, and the address in
  the submission docs DOES NOT EXIST**
  - Status: **ACTION REQUIRED before next submission** · Severity: **P0** (an unusable
    reviewer login is an automatic 2.1 rejection) · Evidence: verified-by-live-auth
  - **(a) Password rotated 2026-08-13.** The reviewer account's password was not recoverable
    — it is not in repo config or docs by design, and Firebase stores only hashes, so no
    lookup could ever return it. Rotated via the Admin SDK on uid
    `atzEKyOfrjRWmN6apQQzvJwBgmv1`. **The new credential was handed over in session and is
    deliberately NOT recorded here or anywhere in version control.** Get it from Tyler.
    → **App Store Connect → App Review Information must be updated to match before the next
    submission.** Until it is, the notes carry a dead password.
  - **(b) THE ADDRESS IN THE DOCS IS WRONG — this is the bigger problem.** Firebase Auth has
    exactly one reviewer account (full user-list scan, 2026-08-13):
    - ✅ **`reviewer@nex-genled.com`** (hyphenated) — uid `atzEKyOfrjRWmN6apQQzvJwBgmv1`,
      provider `password`, not disabled, created 2026-04-21, last sign-in 2026-04-23.
    - ❌ `reviewer@nexgenled.com` (no hyphen) — **`auth/user-not-found`**.
    The hyphen-less form is what appears in
    [SUBMISSION_AUDIT_v1.0.0.md:262](submissions/SUBMISSION_AUDIT_v1.0.0.md#L262),
    [BUILD_LEDGER.md:322](BUILD_LEDGER.md#L322) and
    [COMMAND_SAFETY.md:634](../audit/COMMAND_SAFETY.md#L634). **The code is correct** —
    `ReviewerSeedService.reviewerEmail` is `'reviewer@Nex-GenLED.com'`, which matches the
    real account (and `isReviewer()` compares case-insensitively, so case is not the issue;
    the HYPHEN is).
    → **If the App Store Connect review notes carry the hyphen-less address, Apple's reviewer
    types an address that does not exist, login fails, and it is a 2.1 rejection regardless
    of the password.** Verify the notes against the live account, not against these docs.
    Fix the three docs above so the wrong address stops propagating.
  - **This closes the open half of V-1** ([LAUNCH_PLAN.md:629](../audit/LAUNCH_PLAN.md#L629),
    [COMPLIANCE_AND_SECURITY.md:459](../audit/COMPLIANCE_AND_SECURITY.md#L459)) — *"does
    `reviewer@Nex-GenLED.com` exist in Firebase Auth with a known password?"* Answer: the
    account exists and the password is now known. The remaining limb is the ASC-side update
    in (a) + (b), which is Tyler's, not code.
  - **Blast radius of the rotation: none.** The account holds 0 controllers
    ([COMMAND_SAFETY.md:634](../audit/COMMAND_SAFETY.md#L634) — *"No exposure"*) and runs on
    `DemoWledRepository`, so it cannot reach hardware or customer data. Last sign-in was
    2026-04-23, ~4 months before the rotation, so no review was in flight.
  - ⚠️ **Related gap, unresolved:** `ReviewerSeedService` seeds only the Firestore profile +
    installation docs — it does **not** create the Auth user
    ([SUBMISSION_AUDIT_v1.0.0.md:262](submissions/SUBMISSION_AUDIT_v1.0.0.md#L262)). If that
    Auth user is ever deleted, reviewer login fails silently and no code path recreates it.
  - Files (docs to correct): `docs/submissions/SUBMISSION_AUDIT_v1.0.0.md`,
    `docs/BUILD_LEDGER.md`, `audit/COMMAND_SAFETY.md`. Code is correct, no change needed:
    `lib/services/reviewer_seed_service.dart:18`. Related **V-1**,
    `docs/submissions/REVIEWER_GATE_DIAGNOSIS.md`.


- [ ] **F-3 — Neighborhood Sync: fleet-wide read of home coordinates + uninvited crew join.
  CODE COMPLETE on `fix/f3-neighborhood-security`, NOT DEPLOYED.**
  - Status: **FIX WRITTEN + TESTED, awaiting Tyler's deploy gate** · Severity: **P0** ·
    Evidence: verified-by-deployed-state (deployed ruleset read 2026-08-12) + census
  - **The defect, re-confirmed live 2026-08-12** against ruleset
    `93c99c50-0b3d-4a72-b76f-eb6f3040550d` (not just the repo copy):
    `/neighborhoods/{groupId}` was `allow read: if request.auth != null`, exposing
    `streetName`, `city`, `latitude`, `longitude` and `inviteCode` to any authenticated —
    including anonymous — token. The members subcollection was equally open and carries
    `displayName` + `controllerIp`. Group `update` additionally accepted
    `request.auth.uid in request.resource.data.memberUids` ("enforced app-side"), so a
    stranger could join any crew with NO credential, satisfy `isGroupMemberLookup()`, and
    unlock its commands/schedules/syncEvents. That last limb also went around **SYNC-1**: a
    self-joined attacker is in `memberUids[]` legitimately, so `verifyFanoutTarget` waves
    them through — light control was held shut ONLY by `config/sync_fanout.enabled == false`.
  - **EXPOSURE, MEASURED (not guessed) — census 2026-08-12, `/neighborhoods`:**
    | metric | count |
    |---|---|
    | groups | **3** |
    | `isPublic=true` | **0** (all 3 private) |
    | carrying a street name | **0** |
    | carrying lat/lon | **0** |
    | carrying `inviteCode` | **3** |
    | member docs | **6** (0 with `controllerIp`) |
    | `isParticipating=true` | **1** (in 1 group) |
    | distinct household uids | **3** |
    - All three are bench/demo crews ("demo test", "demo", "Let's Hope This Works").
    - **So the REALIZED leak today is 3 demo group names + 3 invite codes + 6 member
      display names — no addresses, no coordinates, no controller IPs.** The rule is wide
      open, but nothing has yet been put behind it. This is a latent P0 that becomes a real
      one the moment a customer creates a crew with an address, and it means the fix can
      ship without a data-migration scramble.
    - Second-order: 0 public groups ⇒ `findNearbyGroups` returns nothing today, so the
      discovery path could be re-pointed at a projection with no user-visible regression.
  - **THE FIX (three parts):**
    1. **Rules** — group read is now `isGroupMember() || isGroupCreator()`; the members
       roster is `isGroupMemberLookup()` (matching its sibling subcollections); the
       self-insertion clause is DELETED from `allow update`.
    2. **`joinNeighborhood` callable** (`functions/src/joinNeighborhood.ts`) — validates the
       invite code SERVER-side with the admin SDK, enforces a crew ceiling
       (`MAX_CREW_SIZE = 24`; there is no per-group capacity field), and writes `memberUids`
       + `members/{uid}` in ONE batch (the old client path wrote them independently, and the
       resulting orphan shape is exactly what SYNC-1 had to defend against). Rate-limited
       per CALLER on the SYNC-2 envelope (18s cooldown / 5 per 60s), because a brute-forcer
       rotates codes and supplies no groupId, so a per-group limit would not see the
       attempts as related. `invalid_code` and `group_not_found` both surface as `not-found`
       so the callable is not an existence oracle.
    3. **`/neighborhood_public` projection** — discovery genuinely needs one cross-tenant
       read, so it gets a narrow one: name, description, memberCount, and COARSE coords
       (2dp ≈ 1.1 km). The rule enforces the SHAPE (`hasAny(['inviteCode','streetName',
       'latitude','longitude','memberUids',...])` is rejected), so a future writer bug fails
       loudly instead of leaking. Precision is decided in
       `NeighborhoodService.coarsenCoordinate` — the rule cannot catch a loosening there,
       noted at both sites.
  - **TESTS (all green, this branch):**
    - Emulator rules suite **193/193, 12/12 suites** — including 20 new F-3 cases and the
      pre-existing SYNC-1 `neighborhoodMembersRules` suite, which still passes.
    - `joinNeighborhood` unit tests **22/22**.
    - Full Dart suite **2191/3/0** — 2165 pre-existing + the 26 new `fanout_verify` harness
      tests. Main baseline is 2164/3/1; the absent failure is #64's clock caveat, which only
      fires in the 90 min before local midnight (this ran at ~13:00 CDT), NOT a fix.
    - `flutter analyze` on all changed areas: **0 errors**.
  - ⚠️ **The JDK-21 emulator blocker was a JAVA_HOME problem, not a missing JDK.**
    `jdk-25.0.1.8-hotspot` is installed alongside 17; `JAVA_HOME` simply points at 17. Set
    `JAVA_HOME=/c/Program Files/Eclipse Adoptium/jdk-25.0.1.8-hotspot` (Git Bash needs the
    `/c/...` form in PATH, not `C:/...`) and the whole emulator suite runs. The
    "differential rules test" substitute in `scripts/_test_rules_diff.js` is no longer the
    only option.
  - **DEPLOY IS GATED (Tyler), in this order:** end-fire completes → F-3 rules **and**
    functions deploy (they must land TOGETHER — deploying rules without the callable makes
    joining impossible; deploying the callable without rules leaves the hole open) → scoped
    fanout allowlist → two-node run → **P1-44** #7 flip decision.
  - **Coordination with `fix/neighborhood-join-membership` (002b0b7):** the typed-code join
    sequence survives UNCHANGED — the callable slots under `NeighborhoodService.joinGroup`
    and preserves the null-vs-throw contract that `_performJoin` branches on. The
    NEARBY-groups join needs ONE line changed (`joinGroup(group.inviteCode)` →
    `joinPublicGroup(group.id)`), in a method 002b0b7 also edited, so expect a one-line
    merge conflict there and nowhere else.
  - Files: `firestore.rules` (neighborhoods read/update, members read, new
    `/neighborhood_public`), `functions/src/joinNeighborhood.ts`, `functions/index.js`,
    `lib/features/neighborhood/neighborhood_service.dart`, `neighborhood_providers.dart`,
    `neighborhood_sync_screen.dart`. Tests: `functions/test/emulator/neighborhoodF3Rules.
    emulator.test.ts`, `functions/test/unit/joinNeighborhood.test.js`. Related **P1-44**
    (the flip this unblocks), **SYNC-1**.
  - **SIBLING FINDING, not fixed here:** `game_day_crews` has NO rules block and no
    catch-all, so it is default-DENIED — `GameDayCrewService.joinCrew`
    (`lib/features/game_day/game_day_crew_service.dart:88`) queries it by `invite_code` and
    cannot ever succeed in production. Same invite-code-as-client-query shape as F-3, but
    currently inert rather than leaking. File separately before that collection is opened.


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

- [x] **P0-5 — D4 BLOCKER: controller migration runs BEFORE the customer user doc exists** — **DONE 2026-07-31** (rules deployed, ruleset `ec8d918f-c279-4925-b8b2-168e96638586`)
  - FIX: claim-based resolution via new `staffMayReach(userId)` in `firestore.rules` — when
    `/users/{userId}` does not exist yet, scope from the CALLER'S OWN `dealerCode` claim
    instead of a `get()` on the absent doc. Ordering-immune, so it cannot regress if the
    wizard's sequence changes. Applied to all 7 vulnerable call sites (pixelMap inline +
    6 × `hasStaffClaim(dealerCodeOf(userId))` on brand_profile / commercial_locations).
  - NOT pure claim-based: `hasStaffClaim(token.dealerCode)` is `x == x`, i.e. always true,
    which would have granted every dealer's installer access to every other dealer's
    customers. Scoping is retained whenever the customer doc exists. See `audit/COMMISSIONING_FIXES.md`.
  - VERIFIED against the LIVE ruleset via the Rules `:test` API — 16/16 incl. cross-dealer
    DENY; plus a 31-path deployed-vs-live regression with 0 behavioral differences.
  - **D4 MUST use `staffMayReach(userId)`**, not `hasStaffClaim(dealerCodeOf(userId))`.
  - Original finding below.
  - Status: was OPEN · Evidence: source-proven (2026-07-30, token-refresh work)
  - `_completeSetup` migrates controllers at `installer_setup_wizard.dart:933` but the
    customer's `/users/{userId}` doc is not written until `:1047`. Any narrowed rule of the
    form `hasStaffClaim(get(/databases/../users/$(userId)).data.dealer_code)` therefore
    evaluates `get()` on a **non-existent document** and DENIES.
  - This is exactly the shape D4 intends to give `/users/{userId}/controllers` create
    (mirroring the `pixelMap` rule at `firestore.rules:414-417`). Deploying it as-is breaks
    controller migration for every install — the driveway failure the D4 sequencing is
    designed to avoid.
  - **Already latent today:** the migration batch also writes
    `/users/{customer}/controllers/{id}/pixelMap/{ch}`, which is *already* governed by that
    `get()`-based rule. When a roofline map was captured (Design Studio Slice 2), that write
    should already be denied — and because the whole batch fails atomically and the error is
    swallowed (see P0-6), the customer silently receives **no controllers at all**. Needs
    bench confirmation on a pixelMap-carrying install.
  - Fix options: (a) move the migration to after the `:1047` user-doc write, (b) write the
    customer user doc (at minimum `dealer_code`) before migrating, or (c) narrow using only
    the caller's own `dealerCode` claim with no cross-doc `get()`.
  - Files: `lib/features/installer/installer_setup_wizard.dart`, `firestore.rules`.

- [x] **P0-6 — `migrateInstallerControllersToCustomer` swallowed every failure** — **DONE 2026-07-31**
  - **DONE 2026-07-31** — see `audit/P0-6_FIX.md`. The swallow is removed:
    `migrateInstallerControllersToCustomer` now THROWS on failure and returns a
    `ControllerMigrationResult` on success. `_migrateControllersWithRetry` logs the cause,
    records it to the `/demo_analytics` telemetry sink
    (`event_type: installer_commissioning_failure`), and shows a blocking Retry/Stop dialog
    naming the cause — the same shape as `_restoreInstallerAuthWithRetry`, not a second UX.
    **Stop rethrows**; the migration is pre-`installCommitted`, so `classifyInstallError`
    yields `reportFailure` and the wizard reports the install as FAILED rather than handing
    over an account with no controllers.
  - RETRY IS SAFE — confirmed by test, not assumed: `WriteBatch.commit()` is atomic, so a
    failed commit leaves the source intact and the destination empty ("delete succeeded but
    set did not" cannot occur). A retry after a commit that *did* land finds the source
    drained and returns `skipReason: 'source-empty'` — a no-op, not an error.
  - Tests: `test/features/installer/controller_migration_failure_test.dart` (7).
    Full suite 1857/3/1 (only the pre-existing P1-8 AI-normalize failure).
  - GAP: the dialog itself is not widget-tested — `_completeSetup` calls
    `FirebaseAuth.instance.createUserWithEmailAndPassword` directly and the project has no
    auth-mocking dependency. The mechanism is pinned in two composing halves (it throws; a
    pre-commit throw classifies as `reportFailure`). Same gap as
    `_restoreInstallerAuthWithRetry`. Closing it means putting the auth call behind an
    injectable seam — worth doing, out of scope for an RC.
  - Was: `installer_setup_wizard.dart:207-209` caught and `debugPrint`ed any migration failure
    so "handoff still completes". A permission denial, a partial batch, or an offline device
    all rendered as a successful install whose customer has zero controllers on first login.
    This is what would have made the P0-5 denial invisible.
  - Files: `lib/features/installer/installer_setup_wizard.dart`,
    `lib/features/installer/staff_auth_telemetry.dart`.

- [x] **P0-7 — Roofline pixel-map save failure was silent; wizard advanced anyway** — **DONE 2026-07-31**
  - ⚠ **NAMING:** this was handed to me labelled "F-5", but **F-5 in
    `audit/COMPLIANCE_AND_SECURITY.md` is ACCOUNT DELETION** (F-5a/F-5b). They are unrelated.
    **F-5a/F-5b remain OPEN.** Tracked here as P0-7 so the ledger cannot conflate them.
  - `map_roofline_step.dart:417` was `catch (_) { return false; }` — cause destroyed — and
    `_onContinue()` discarded the bool and called `widget.onNext()` unconditionally. A pixel
    walk that failed to persist looked identical to one that succeeded; the installer
    finished the job and left. This was the **6th** silent-success instance (after F-5, F-8,
    the off-LAN lease, `_writeZeroedSlot`, `migrateInstallerControllersToCustomer`).
  - FIX: `_onContinue()` gates on the result and loops on a blocking Retry dialog; the
    exception is logged with uid/controller; "nothing captured" short-circuits to success so
    an installer who mapped nothing is never trapped. **No "save offline and continue"** — a
    queued write would be migrated-from-cache and deleted at handoff, relocating the silent
    failure somewhere unobservable.
  - Regression test: `test/features/installer/map_roofline_save_gate_test.dart` (5 tests)
    pins "onNext only on genuine success", incl. the decline-to-retry path so the fix cannot
    become a 7th instance.

- [ ] **P0-8 — Out-of-range timer bounds stored verbatim; `timersInsLanded` reports "landed"**
  - Status: OPEN · Evidence: bench-proven (`verified-by-bench` — 192.168.1.150, vid 2507300,
    0.15.1, 2026-08-01) · **7th silent-success instance — and the FIRST where the VERIFIER
    itself is fooled** (after F-5, F-8, the off-LAN lease, `_writeZeroedSlot`,
    `migrateInstallerControllersToCustomer`, P0-7).
  - POSTed `/json/cfg` slot 0:
    `{"en":1,"hour":23,"min":59,"macro":1,"dow":127,"start":{"mon":13,"day":40},"end":{"mon":1,"day":5}}`
    → **HTTP 200**, and `/json/cfg` read back **byte-identical**, `"start":{"mon":13,"day":40}`
    intact. No clamp, no normalization, no rejection. Month 13 / day 40 accepted and stored.
  - Why this class is new: `timersInsLanded` compares SENT vs READBACK. Here they MATCH, so it
    reports "landed" on a row whose start month can never equal a real month — a permanently
    dead timer that reads healthy at every layer. **Readback verification structurally cannot
    catch this.** The only downstream signal is a schedule that never fires, discovered months
    later by a customer.
  - **HARD REQUIREMENT for Phase 0:** range validation MUST live in the bound builder, BEFORE
    the POST (mon 1–12, day 1–31, day valid for that mon). Do NOT bolt it onto the readback
    comparator — wrong layer, and it would still pass any garbage that round-trips cleanly.
  - Same-session bench facts that bound the scope: date bounds ARE evaluated, not decorative —
    `start=end=`today fired at 22:12:00 (`ps -1→1`, `on false→true`), `start=end=`tomorrow did
    NOT fire across 44 polls spanning target +6.5min. Year-wrap `start:{mon:12,day:20}`/
    `end:{mon:1,day:5}` also stored verbatim. Wrap **evaluation** then confirmed separately: a
    wrap range CONTAINING today (`start:{mon:9,day:1}`/`end:{mon:8,day:2}`, today 8/1) FIRED at
    23:12:02 (`ps -1→1`, `bri→200`, seg0/seg1 flipped to preset 1's fingerprint). **The
    evaluator is wrap-aware — a Dec–Jan season is ONE row, no year-end splitting.**
  - Files: `lib/features/schedule/cfg_payload_builder.dart` (`buildTimerEntry` — add the range
    guard; it already refuses dow:0 and unparseable times, this is the same refusal class),
    `lib/features/schedule/timer_landing.dart` (`timersInsLanded` — document that it cannot
    catch out-of-range bounds, so nobody re-derives false confidence from it).

- [x] **P0-9 (part a) — cold-ledger race CLOSED: the lease ledger is now a tri-state**
  - Status: **FIXED 2026-08-03** · Evidence: **bench-proven end-to-end** (192.168.1.150,
    vid 2507300 — real `syncAll` against the real controller). Report: `audit/LEASE_TRISTATE.md`.
  - `activeLeaseTimers()` returned a bare list, so "no leases" and "ledger not loaded yet" were
    both `[]`. `initialize()` is fire-and-forget, so a sync racing the load merged ZERO leases and
    `padTimersToMax` stubbed their slots. `_initialized` already tracked this and was read ONLY by
    a `@visibleForTesting` getter — nothing production-side consulted it.
  - Now returns sealed `LeaseLedgerLoading | LeaseLedgerEmpty | LeaseLedgerReady`; `syncAll`
    REFUSES the cfg write on Loading (`ScheduleSyncResult.deferredLeaseLedger`, neutral UI,
    bounded auto-retry). Bench: lease `macro 27` WIPED pre-fix → SURVIVES post-fix, table
    byte-identical; warm sync still arms schedule + lease together.
  - Also closed one level up: the flag's sync adapter collapsed `AsyncLoading`→`false`, which
    would have licensed the same clobber while the flag doc was still loading.
  - **Part (b), the Firestore migration, is still open** — design only, `audit/LEASE_LEDGER_MIGRATION.md`.
    Part (a) stops the data loss; part (b) makes lease survival verifiable and multi-device correct.

- [ ] **P0-9 (part b) — lease ledger is device-local SharedPreferences, not Firestore**
  - Status: OPEN · Evidence: bench-proven (`verified-by-bench` — 192.168.1.150, vid 2507300,
    2026-08-03) · **Design only (`audit/LEASE_LEDGER_MIGRATION.md`); not implemented.**
  - **`macro 26-41` is a PRESET-ID convention, NOT a slot reservation.** Armed
    `{en:1,hour:19,min:10,macro:27,dow:16}` alongside a clock timer and the slot-8 sunrise-off,
    then pushed 8 disabled stubs: **the lease was WIPED along with the clock timer.** Only the
    slot-8 sentinel survived, and only because an 8-entry push never reaches slot 8. Full
    before/after tables: `audit/ALL_STUB_CLOBBER.md` §2.
  - **The only thing protecting a lease is being re-merged into the same write** from
    `calendarLeaseActiveTimersProvider` (P0-3.2). That ledger is **device-local
    SharedPreferences** (`_kLeaseStorageKey`, `_loadFromPrefs`), not Firestore — so any sync run
    while the ledger is COLD drops every live lease: after a reinstall, a cleared app cache, on a
    second device, or simply before the ledger finishes loading.
    **UPDATE 2026-08-03 — "before the ledger finishes loading" is CLOSED by part (a) above.**
    The remaining exposure is durability, not timing: reinstall / cleared cache / second device
    still start from an empty ledger, which now correctly reports EMPTY (not Loading) because it
    genuinely finished loading nothing. Part (a) cannot distinguish "loaded, empty" from "loaded,
    empty because the data lives on another phone" — only part (b) can.
  - **Severity note — this is why it is P0 rather than P1:** the failure is silent, destroys
    automation the user configured, and self-conceals (the lease is gone from the controller AND
    absent from the ledger that would have restored it).
  - **Unverifiable from either side, structurally.** Firestore holds only the `CalendarEntry`;
    the derived lease (slot, presetId, wledHour, dowMask) exists solely on the phone. Neither a
    Firestore read nor a controller readback can tell you whether a given lease *should* be
    armed — the authoritative record is on a device you cannot query. Confirming a fix therefore
    needs a SharedPreferences dump from the handset, not a bench test.
  - The `shouldSkipClobberingWrite` guard (P0-9's sibling, shipped 2026-08-03) narrows the blast
    radius but does NOT close this: it only blocks the all-refused case. A partially-armable sync
    with a cold ledger still writes real timers and drops the leases.
  - Files: `lib/features/schedule/calendar_entry_lease_manager.dart` (ledger + `activeLeaseTimers`),
    `lib/features/schedule/schedule_sync.dart` (merge point).

- [ ] **P0-9c — `_kLeaseStorageKey` is not uid-namespaced: account switch inherits stale leases**
  - Status: OPEN · Evidence: code-confirmed 2026-08-03 · **Logged during P0-9 part (a), not fixed
    (out of scope for a release candidate; no user report).**
  - `const String _kLeaseStorageKey = 'calendar_leases_v1'` is a single GLOBAL SharedPreferences
    key with no uid in it. Sign out of account A and into account B on the same handset and B's
    lease manager rehydrates **A's leases** — A's `slotIndex`/`presetId` values then get merged
    into B's cfg writes, arming timers against presets B never saved (a dead-macro fire) and
    occupying slots B's own leases need.
  - Most likely to bite installers and demo devices, which switch accounts routinely; a normal
    customer handset has one account for life.
  - Fixed incidentally by P0-9 part (b) — the Firestore path `/users/{uid}/leases/{dateKey}` is
    uid-scoped by construction. A standalone fix is a one-line key change plus a migration of the
    existing unscoped blob, which is why it is worth doing WITH part (b) rather than before it.
  - Files: `lib/features/schedule/calendar_entry_lease_manager.dart:74`.
  - Related: [[project_ai_dated_entry_5th_write_boundary]], P0-3.2.

- [ ] **P0-4 — System presets 1/3/4/5 ib-heal check**
  - Status: OPEN · Evidence: suspected (bench-verify pending)
  - Name-based skip in the psave path may prevent re-saving presets with `ib:true`; if stale,
    "NGL On / Dim / Low / Medium" won't assert master power when fired. Bench-verify AFTER a
    +51 Sync (curl presets.json); fix the skip trigger if the ib flag is absent.
  - Files: `lib/features/schedule/schedule_sync.dart` (`_scheduleDesignMatches` / psave skip).

---

## P1 — correctness & trust

- [ ] **#79 — SCORE CELEBRATIONS HAVE NEVER FIRED ON HARDWARE FOR ANYONE, and the
  `start_time_passed` skip that hid the Dodgers cycle is invisible**
  - Status: **IN-PROGRESS** on `feat/gameday-unified-monitoring` · Severity: **P1** ·
    Evidence: verified-by-live-data (read-only pull 2026-08-14) + verified-by-source
  - **THE EVIDENCE.** 678 command docs fleet-wide, by source: `(none)` 577, `health_probe`
    70, `bench_fanout_verify` 9, `bench_67_partition` 2, `sync_fanout` 4, `fire_job` 16 —
    **zero `game_day`-sourced commands, ever.** `_applyToControllers` stamps
    `'source': 'game_day'`, so any celebration, or any Game Day worker apply at all, would
    appear there. Retention covers the window (fire_job + bench entries from 08-12→08-14
    survive). Combined with the three structural blockers below, celebrations have never
    reached a controller for any account.
  - **THREE INDEPENDENT BLOCKERS, each sufficient on its own:**
    1. **Arming keyed off the wrong subsystem.** `checkScores` AND the `alertStream`
       subscription both sat inside `if (active.isNotEmpty)` where `active` = enabled
       **sports-alert** configs — a list configured in a separate screen, unrelated to the
       Game Day teams the user selected. A user with Game Day teams and no sports-alert
       opt-in polled nothing.
    2. **`_sessions` is never populated by a manual start.** `onScoreAlertEvent` finds its
       session in the worker's in-memory map, which only `evaluate()` (the scheduled path)
       wrote. "Light It Up Now" applied a pattern and armed nothing.
    3. **The background mirror defaulted celebrations OFF.**
       `game_day_background_persistence.dart:147` read `scoreCelebrationEnabled ?? false`
       while `fromFirestore` defaulted the same field to `true`. The two layers disagreed
       and the worker reads the pessimistic one. The live Twins config has no such field.
  - **`start_time_passed` is a #68 sibling.** `planGameDayFires.ts:606-611` bumped the
    counter and pushed **no** `logRows` row, while `outside_horizon` immediately above it
    pushes one. So the 2026-08-13 Dodgers cycle reconciled perfectly (21/21) while naming no
    team, and "which config lost its start?" was unanswerable. Root cause of that cycle: the
    `mlb_dodgers` config was created AFTER its own fire time (first pitch
    `2026-08-14T02:10:00Z`, 30-min lead → fire `01:40Z`); `configsEnabled` went 20 → 21
    between the 13th and 14th and `start_time_passed:1` appeared for the first time. The
    only Dodgers row in the whole log is `end_skipped_no_start` — **#66's GUARD 0 working
    correctly.**
  - **Corroborating, and good news:** the Twins cycle that DID run the same night was the
    **first #67 full-partition fire** and is correct on the wire —
    `{"on":true,"bri":200,"seg":[{"id":0,"on":true,"fx":0,…},{"id":1,"on":false}]}` — both
    bench segments named, exclusion-only for the non-participating one. The previous Twins
    start (08-12) named seg0 only.
  - ⚠️ **SYNC-3 CORRECTION — the verification was of dead code.**
    `triggerScoreCelebration` (`game_day_setup_screen.dart:895`) is **hardened but
    caller-less**: its only references are the debug button and
    `fanout_trigger_flag_gate_test.dart`. SYNC-3 TASK A rerouted it through the
    `broadcastSync` flag gate and TASK B pinned that contract, but the live pipeline never
    invokes it — the real path is `sports_background_service` →
    `gameDayWorker.onScoreAlertEvent` / `syncWorker.onScoreAlertEvent`. Neither sets
    `fanout`, so **`group_allowlist` (dab5b27) cannot scope celebrations out** — the
    allowlist is only consulted inside `if (fanout === true && groupId …)`. SYNC-3's ledger
    standing should read *"hardened but caller-less; verification was of dead code."*
  - 📌 **RIDER (Tyler, 2026-08-14):** audit `gameDayWorker.onScoreAlertEvent` as the REAL
    celebration path — gating, participation, monitored-field respect, and the **#67/#76**
    payload contracts. The Dodgers celebration trace runs against this path, not against
    `triggerScoreCelebration`.
  - **FIX IN FLIGHT** (`feat/gameday-unified-monitoring`): Game Day + Live Scoring becomes
    the single source of truth for monitoring (`live_scoring_enabled`, client-only,
    deliberately separate from `enabled` which the **server planner** queries at
    `planGameDayFires.ts:342` — so a migrated alerts-only team is monitored while staying
    invisible to the planner and cannot produce an unasked-for first-pitch fire); arming
    moves to `shouldPollScores`; "Light It Up Now" registers its session; the mirror default
    flips to true; the four bare returns in `onScoreAlertEvent` become counted, named skips;
    and `start_time_passed` gets its row.
  - Files: `lib/features/autopilot/unified_monitoring.dart` (new),
    `game_day_autopilot_config.dart`, `game_day_background_persistence.dart`,
    `game_day_autopilot_background_worker.dart`,
    `lib/features/sports_alerts/services/sports_background_service.dart`,
    `lib/features/game_day/light_it_up_now.dart`, `functions/src/planGameDayFires.ts`
    (edited, **NOT deployed**). Related **#66**, **#67**, **#68**, **#76**, **P1-44**.
  - **MERGE-REVIEW CORRECTIONS, 2026-08-16 (pre-merge, applied on the branch).** The branch
    was authored on the premise that `score_celebration_enabled` was absent fleet-wide and the
    feature unreachable. **Measurement inverts that: 49 of 50 live configs carry
    `score_celebration_enabled: true`**, and the switch writing it is the one labelled
    **"Live Scoring"** (`game_day_screen.dart:385` → `setLiveScoring`). Three consequences,
    all fixed before merge:
    1. **`live_scoring_enabled` had NO WRITER anywhere in `lib/`.** Grep-verified at
       `47a143b`: declared, defaulted, mirrored, read by `isMonitored` — never written. With
       `?? true` the arming gate was permanently on and **could not be turned off by any UI**.
       Fixed: `setLiveScoring` now writes both fields, and both parsers fall back
       `live_scoring_enabled ?? score_celebration_enabled ?? true`, so the existing switch
       stays authoritative and an explicit OFF is honoured instead of overridden.
    2. **Blast radius restated.** The `?? false → ?? true` mirror flip was described as
       unblocking one stub config; with 49 configs already `true`, merging arms monitoring +
       celebrations for **49 accounts at once** on the +78 client. Not a defect — but it is a
       launch-risk number, and it is Tyler's call, not the branch's.
    3. **`migrationConfigsFor` and `monitoringPollInterval` have NO production callers** —
       library + tests only. The A4 migration does **not** run; see **#92**.

- [ ] **#91 — the Game Day worker's own applies bypass the #67 full partition, and the
  celebration path just became reachable**
  - Status: OPEN (filed 2026-08-16, merge review of `feat/gameday-unified-monitoring`) ·
    Severity: **P2** · Evidence: **verified-by-source** · Sibling of **#67**
  - #67 closed with *"fires assert the full partition; non-participating segments get
    `{id:N, on:false}` ONLY"* and *"unstated segment state is inherited state, and inherited
    state is a bug"*. It was fixed and hardware-verified in **two server builders** —
    `buildFullPartitionSegArray` (`gameDayPlanning.ts:163`, used by the planner) and
    `partitionBroadcastPayload` (`applySyncPattern.ts:586`, used by the **fanout** arm).
  - **The worker is on neither path.** `buildCelebrationPayloadForTest` and
    `buildBasePayloadForTest` build through `expandForChannels` → `applyChannelFilter`
    (`wled_payload_utils.dart:59`), which emits **only the participating segs, each with an
    explicit `id`** — no `{id:N, on:false}` for the excluded ones. It then dispatches via
    `applySyncPattern` as a **background self-apply**, which by design
    (`applySyncPattern.ts:56-61`) takes the **self-only path** — and that path stringifies the
    payload verbatim and enqueues it with **no partitioning at all**.
  - Even had it reached the fanout arm, `partitionBroadcastPayload` requires
    `seg.length === 1` **and** `design.id === undefined`; a client-filtered array fails both
    and returns `pass("segment_already_addressed" | "not_single_segment")` — whose own log line
    reads *"excluded channels stay UNCHANGED, not dark"*.
  - **Why it is filed and not fixed here.** Pre-existing on `main`; the branch does not touch
    either builder. But it was **harmless while dead** — zero `game_day`-sourced commands have
    ever existed — and this merge makes the celebration emitter live, so a latent
    non-compliance becomes an emitting one. The fix needs the **full device channel list** in
    the background isolate, and `BackgroundGameDayAutopilotConfig` persists only
    `participatingChannelIds`; a full partition is therefore impossible without a new
    persisted field. That is a change of its own, not a merge rider.
  - **Symptom to expect meanwhile:** on a multi-channel install with partial participation, a
    celebration flashes the participating channels and the others hold their prior look —
    the Twins failure shape, not a swallow.

- [ ] **#92 — the A4 monitoring-only migration is written, tested, and NOT WIRED**
  - Status: OPEN (filed 2026-08-16, merge review) · Severity: **P3 — inert** ·
    Evidence: **verified-by-source (grep)**
  - `migrationConfigsFor` (`unified_monitoring.dart:141`) has **no caller in `lib/`** — only
    `unified_monitoring_test.dart`. `MonitoringPlan.orphanedLegacy` is computed and returned
    on every poll and **nothing consumes it**. `monitoringPollInterval:119` is likewise
    caller-less; the live cadence still comes from `intervalInfo.intervalSeconds` and, on the
    else-branch, from `loadActiveSession()` — the **neighborhood sync** session, not the Game
    Day one, so the "mid-game join gets 30s polling" claim is not in force.
  - **Do not wire it without deciding the lighting question first.** It mints
    `enabled:false, liveScoringEnabled:true, scoreCelebrationEnabled:true` under the comment
    *"monitored, not shown … no lighting they did not ask for"*. That is **not what the code
    does**: `enabled:false` only hides the team from the planner's first-pitch fire. A
    migrated team still lights the house on every qualifying score, by **two** independent
    paths — `gameDayWorker.onScoreAlertEvent` (sparkle flash + a base-pattern apply 15s
    later) and `AlertTriggerService.handleAlertEvent`, which opens
    `WledService('http://$ip')` per controller and runs an LED animation **without checking
    `scoreCelebrationEnabled` at all**.
  - Being inert is the only reason this is P3. Left as-is, the honest state is: the model
    landed, the migration did not.
  - 🚫 **HOLD ADDED 2026-08-18 — do not wire until #101 is fixed.** `migrationConfigsFor`
    falls back to `primaryColorValue: meta?.primary ?? 0xFF000000` and
    `secondary ?? 0xFFFFFFFF` (`unified_monitoring.dart:152-153`) — **the exact black/white
    pair that rendered the `mlb_twins` ghost's mono two-dot icon.** Any orphan whose slug is
    absent from `teamMetadata` mints a config in the ghost's shape. Today that is one
    hand-made doc on the bench; wired, it is a **fleetwide batch** of them, each with a live
    "Light Up Now" button, on the very accounts that never opted into Game Day. #101 is the
    prerequisite: once a malformed config cannot render or match, this migration is safe to
    wire. Filing this as a second reason to hold, independent of the lighting question above.

- [x] **#95 — a channel that is OFF reads as a channel that is GONE. Release-blocking; WITHDREW
  +78. FIXED, awaiting +79 hardware smoke (c).**
  - Status: **FIXED on main** (filed + fixed 2026-08-17) · Severity: **P1 — release-blocking,
    customer-visible, no recovery path** · Evidence: **verified-on-hardware (bench `.150`) +
    verified-by-source**
  - **Symptom.** After a single-channel design apply, the untargeted channel rendered greyed
    with a strikethrough and was completely non-interactive. WLED-side state was **correct and
    healthy** (JSON read: seg 1 present, bounds `128/290/162` intact, `rev:true` intact, exactly
    `on:false`), and direct WLED control still worked. **App-side lockout only**, with no
    re-enable path except applying another design that happened to target that channel.
  - **THE REPORTED DIAGNOSIS WAS WRONG, and the difference decides the fix.** The hypothesis was
    "channel availability is derived from the segment's `on` state rather than segment
    existence/bounds." **It is not.** Traced and disproven:
    - the chip's predicate is
      [channel_selector_bar.dart:210](../lib/features/dashboard/widgets/channel_selector_bar.dart#L210)
      `disabled: !isParticipating`, sourced from `participatingChannelIdsProvider` →
      `peekCachedParticipatingChannels()` → the SharedPreferences participation cache;
    - that cache is written by exactly three places (Game Day config save, sync engine
      start/stop, and the reconciler clearing it to `null`) — **none reachable from a design
      apply**;
    - `resolveParticipatingChannels` derives from roofline segments + the bus census, **never**
      from seg `on`;
    - the only reader of seg `on` is `channelPowerStatesProvider`, and it drives **only the
      power icon's colour**.
    Implementing the requested fix as stated ("availability = segment exists with `len > 0`")
    would have changed nothing, because availability was never computed from segments at all.
  - **What actually happened — a latent lockout that #89 made visible.** A non-participating
    channel got `disabled:true` → dimmed, struck through, `onTap:null`, **and its power icon
    suppressed** by `&& !disabled` at the chip's power block. Every affordance gone.
    That was survivable only because such a channel stayed **lit**: nobody noticed. **#89**
    brought the #67 full partition to the interactive path, so an unused channel now correctly
    writes `{id, on:false}` and goes **dark**. Dark **plus** no control reads as *gone*. Neither
    half was new; the combination was.
  - **Fixes (3):**
    1. **Power is never gated on participation.** Participation scopes *shows*; it is not a
       claim the channel is absent and must not remove manual control of hardware the device
       reports. Selection stays gated (the apply chokepoint would filter it anyway, so offering
       it would be a silent no-op).
    2. **No strikethrough, ever.** Strikethrough is the typography of *deleted*. Dimming says
       "out of scope for shows" without claiming the channel is gone.
    3. **`buildChannelPowerPayload` no longer emits geometry** — see below.
  - **SECOND DEFECT, found while fixing the first: the wake payload wrote BOUNDS.**
    `buildChannelPowerPayload` stamped `start`/`stop` from the channel map whenever a config
    refresh had succeeded (`withBounds`). That is geometry on an apply — forbidden by **#76**
    (seven design builders) and by **#89**'s own rule 2 (*"an apply NEVER writes `start`/`stop`;
    bounds are provisioning's"*). This builder was in **neither** census. That is the **third**
    time a geometry sweep has under-counted its own family (**#76** → **#88** → this), and it
    re-proves #88's lesson verbatim: *an emitter census must be a grep of the FIELD NAMES across
    `lib/`, not a walk of the builders you already know about.* The `withBounds` parameter is
    gone; id+`on` only. The config re-fetch that existed solely to make those bounds fresh went
    with it — a power tap can no longer re-bound anything, stale map or not.
  - **Blast radius swept — clear.** Every seg-`on` reader in `lib/` was enumerated: the
    remaining ones (`schedule_sync` all-off preset detection, `controller_defaults_healer`
    master read, `setChannelPower`'s `litChannelIds`, `schedule_enforcement`) are all genuinely
    *about* on-ness. **No other site derives availability, existence or readiness from `on`** —
    grep-verified for the availability/exists/missing/readiness family against `['on']`.
  - **Pins (proved able to fail, not just observed to pass):**
    - `test/features/dashboard/channel_availability_not_from_on_state_test.dart` — an OFF
      channel and a NON-PARTICIPATING channel each keep a power control, and no label is ever
      struck through. **Verified by reintroducing `&& !disabled`: the pin fails.** Both a
      chips-rendered and a power-states-resolved guard are asserted first, so a broken setup
      cannot produce a vacuous pass.
    - `channel_power_test.dart` `#95 — NO geometry field, in ANY case, ever` — a **field sweep**
      (`start stop len rev mi of grp spc`) across **all four** policy cases, deliberately not
      spot checks on the two cases someone remembered, since that is precisely how the previous
      two sweeps under-counted.
  - **PARTIAL HARDWARE VERIFICATION, bench `.150` 2026-08-17 (WLED 0.15.1, vid 2507300).**
    The wake-write half of smoke (c) is **PASS on hardware**, driven through the REAL fixed
    `buildChannelPowerPayload` by `bench/bin/bench.dart channel-power` — **4/4** policy cases,
    each asserting the emitted shape *and* the resulting `/json/state`.
    - **No geometry moved.** Full field diff pre→post over both segments
      (`start stop len rev mi grp spc of`) is **EMPTY**: `seg0 [0,128) len=128 rev=false`,
      `seg1 [128,290) len=162 rev=true`, `grp/spc 1/0`, `of 0` — byte-identical either side of
      four power writes. The bounds-stamp defect is disproven on the wire, not argued.
    - Rig restored to exact pre-state (master off, both segs off, `rev:true` intact).
  - **FULL HARDWARE VERIFICATION — all three smokes PASS, iOS build 310, bench `.150`,
    2026-08-17.** Tyler drove the app; every assertion read from `/json/state`, never from UI.
    - **Build confirmed BEHAVIOURALLY, which is worth more than the number here.** The app
      surfaces no build number (no `package_info_plus`) and every build is version `2.5.10`
      (**#62**), so 310-is-from-`build-79` could not be read off the device. It was settled by
      the fix itself: the greyed, non-participating **bench ch1** chip **carried a power icon**.
      On +78 that icon was suppressed by the `!disabled` term. Its presence *is* +79.
    - **(a) rev-survival — PASS.** Design apply + `ps=1` + `ps=2`: both segments present,
      bounds `[0,128) len=128` / `[128,290) len=162` unmoved, `rev:true` standing. Geometry
      diff empty.
    - **(b) single-channel apply — PASS.** Targeted `seg0`, excluded `seg1`. The #67 contract
      verbatim: `seg1` went `on:false` and **not one other field moved** (`fx pal sx ix col
      grp spc` all unchanged), bounds intact, `rev:true` intact, no true geometry written
      anywhere. *Recorded as method, not trivia:* the first scoring pass reported FAIL because
      the script **assumed** which segment was targeted. The device resolved it —
      `on:true` marks the targeted seg — and the labels were then confirmed by Tyler (front of
      the home = `seg0`; "bench ch1" is the roofline zone name on `seg1`). **An assumed mapping
      produced a false FAIL on a passing device**, which is the same failure mode as reading
      `seg[0]` as the design seg (#89's `firstDesignSeg`).
    - **(c) tap-to-wake — PASS. This is the one that gates the ship.** With `seg1` dark AND
      non-participating — the combination unrecoverable on +78 — a tap on its power icon
      **woke it**: `on false → true`. The wake wrote **power only**: no `start`/`stop`/`len`/
      `rev`/`mi`/`of`, no design field touched, `seg0` undisturbed.
    - **Whole-run geometry diff against the ORIGINAL baseline is EMPTY** — across a design
      apply, two preset loads, a single-channel apply and a tap-to-wake, nothing in
      `start stop len rev mi of` moved on either segment.
  - **Observation carried forward, not a failure: `spc` moved `0 → 2` on the targeted seg
    during (b).** Under #88 `grp`/`spc` are DESIGN fields and a design that owns its spacing
    may set them; Tyler confirmed the strip was "showing correctly", so this is design intent.
    Recorded because a silent `spc` change is the exact #88 signature (`grp=1 spc=2` renders
    every third pixel) and the next person to see it should know it was checked and accepted,
    not missed. Worth one look at that design's saved payload to confirm the spacing is stored
    rather than inherited.
  - **Ships in +79.** Nothing further gates it.

- [ ] **#93 — `firebase deploy` ships `functions/lib/` WITHOUT compiling, and reports success
  either way**
  - Status: OPEN (filed 2026-08-17, during the `planGameDayFires` deploy) · Severity: **P2** ·
    Evidence: **verified-by-source + verified-in-practice**
  - `firebase.json` declares `functions` with `source` and `runtime` and **no `predeploy`
    hook**. So `firebase deploy --only functions:<name>` uploads whatever already sits in
    `functions/lib/`. A TypeScript edit that was never compiled deploys as **stale JS** — and
    **the deploy still prints `Deploy complete!` and exits 0.**
  - **A deploy's success proves DELIVERY, never CONTENT.** Same family as
    *"a readback proves existence, never app-readability"* and *"a simulator must fail
    everywhere the real component fails."* A green result that was never measured against the
    thing it claims.
  - **Caught, not suffered.** The 2026-08-17 C10/#90 deploy was preceded by an explicit
    exit-checked `npm run build` and a `grep` proving both rows were in
    `lib/planGameDayFires.js` before upload. Without that step it would have shipped the
    previous compile and reported success.
  - **Fix:** add a predeploy hook so the toolchain enforces it rather than a human
    remembering:

    ```json
    "functions": {
      "source": "functions",
      "runtime": "nodejs20",
      "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"]
    }
    ```

    A failing `tsc` then aborts the deploy. Note the hook makes the build mandatory but still
    does not prove the *change* is in the artifact — step 2 of the ledger convention
    (verify the edit exists in `lib/`) stays a human step until something better exists.
  - Interacts with **#94**: whoever does the Node 22 upgrade edits this same block, so land
    them together rather than touching `firebase.json` twice.

- [ ] **#94 — HARD DATE 2026-10-30: Node 20 is decommissioned and all 45 functions become
  undeployable**
  - Status: OPEN (filed 2026-08-17) · Severity: **P1 — dated, external, non-negotiable** ·
    Evidence: **deploy-time warning from the Firebase CLI**
  - Emitted on every deploy: *"Runtime Node.js 20 was deprecated on 2026-04-30 and will be
    decommissioned on 2026-10-30, after which you will not be able to deploy without
    upgrading."* Second warning alongside it: *"package.json indicates an outdated version of
    firebase-functions."*
  - **Scope is the whole backend, not one function.** `functions/index.js` exports **45**
    functions, all on `nodejs20` (`firebase.json`). After the date, **no function can be
    deployed at all** — including an emergency fix. Already-deployed functions keep running;
    it is the *deploy path* that closes. That is the part that matters: it removes the ability
    to respond.
  - **Scheduled: an upgrade session within ~4 weeks** (i.e. by mid-September), deliberately
    clear of the holiday install season. Deferring into October leaves no room for a failed
    upgrade before the deadline.
  - **Session scope:** `nodejs22` in `firebase.json` + `engines` in `functions/package.json`;
    `npm install --save firebase-functions@latest`; the **full functions test suite**
    (`npm run test:unit` — `tsc && jest`); then a deploy of every function, not a targeted one,
    because a runtime change is not per-function.
  - Land **#93**'s predeploy hook in the same session — same `firebase.json` block.

- [ ] **P1-52 — `pdel` can leave `presets.json` UNPARSEABLE; the app then goes blind to every preset and says nothing**
  - Status: OPEN · Evidence: **bench-reproduced 2026-08-09 on `.150`** (observed, not theorised)
  - Found while cleaning up two scratch presets during the base-ladder work
    (`audit/BASE_LADDER.md` §6b). Two `pdel`s left a stray `s` byte inside the padding run
    before the closing brace, so the ENTIRE file failed to parse — not one entry, the whole
    document.
  - **TRIGGER IS ROUTINE APP BEHAVIOUR, not a manual action.** `schedule_sync.dart:1131-1140`
    issues `pdel` for every orphaned schedule preset in the managed 10–25 range on any sync that
    finds one. A deleted schedule leaves an orphan, so this fires in ordinary use on customer
    controllers. Nothing about this required a bench or a scratch slot.
  - **`psave` does NOT repair it.** WLED patches `presets.json` in place; byte length was
    identical (13,246) before and after a re-save. Recovery required rebuilding the file with the
    stray byte blanked and uploading it via `/edit` — not something a customer or a support call
    can do.
  - **NO DETECTION.** `WledService.fetchPresets()` catches the `FormatException` and
    `return const {}` — the SAME value it returns for sim mode, an empty controller, a non-2xx
    response, and an unreachable device. A corrupted preset file is indistinguishable from a
    device with no presets.
  - What the customer would see: presets silently stop being visible, and **the lights flash on
    every Sync** — with `existingPresets` empty, `psaveIfChanged` believes every slot is missing
    and re-`psave`s the whole block, and each psave APPLIES its inline state to the live strip.
    That is precisely the "every-sync storm" the idempotence work exists to prevent, reappearing
    with no error text anywhere. The on-connect defaults healer also goes inert
    (`presets.isEmpty → return`), so nothing self-heals.
  - Not-worse note: the orphan purge is guarded by `existingPresets.containsKey(id)`, so an empty
    map means it stops issuing further `pdel`s. The corruption does not cascade.
  - **Detection cost — cheap, and worth it even without a fix.** Separate the parse failure from
    the empty case in `fetchPresets`: catch `FormatException` distinctly and surface a named
    error ("controller preset file is unreadable") instead of folding it into `const {}`. That
    alone converts a silent, uninterpretable failure into one a support call can act on. A
    stronger version returns a tri-state (`presets | empty | unreadable`) so `psaveIfChanged` can
    refuse to rewrite the world on an unreadable file. **Repairing the file from the app is a
    separate, larger question — this entry asks only that it be NAMED.**
  - **DETECTION SHIPPED 2026-08-11 (tri-state).** `fetchPresets` folded FIVE
    conditions into one `const {}` — sim mode, an empty controller, a non-2xx, an
    unreachable device, and a `FormatException` on an unparseable body.
    `WledService.readPresets()` now returns `PresetsRead` with
    `available | deviceEmpty | unreadable` plus a cause
    (`http`/`parse`/`shape`/`io`).
    **Same bug class as `activeLeaseTimers()` returning `[]` for both "no leases"
    and "do not know yet", which became P0-9a.**
  - Behaviour on `unreadable`: the sync REFUSES to rewrite the preset block (this is
    what stops the flash storm, since each psave applies its inline state live), refuses
    the `pdel` orphan purge (never delete what you cannot see, and `pdel` is what
    corrupts the file), and adds a user-visible `presetErrors` line naming the cause.
    The healer distinguishes too: an unreadable read logs a SKIP instead of the old
    silent `presets.isEmpty` return. `deviceEmpty` still permits a legitimate
    first write.
  - **The corrupt file is still NOT repaired from the app** — deliberately out of scope.
    This names the problem so a support call can act on it; recovery still needs the
    `/edit` upload used on the bench 2026-08-10.
  - Logged read-only per instruction; nothing fixed. Full incident write-up in
    `audit/BASE_LADDER.md` §6b.

- [ ] **P1-53 — WLED rejects chunked-encoding POSTs; Dart's `HttpClient` sends chunked by default**
  - Status: OPEN (gotcha to document, not necessarily code to change) · Evidence: bench 2026-08-09
  - `HttpClient` uses `Transfer-Encoding: chunked` whenever `contentLength` is not set. WLED's
    HTTP server rejects those bodies, so **the POST fails while GETs on the same client succeed** —
    which reads as "the controller ignored my write" rather than a transport error.
  - Fix at the call site is one line: `req.contentLength = bytes.length;` and `req.add(bytes)`
    instead of `req.write(...)`.
  - Cost an hour during the base-ladder hardware test, where a damage step silently no-opped and
    the assertion was too weak to say why. The bench harness hit the same thing earlier.
  - Worth a check that every `HttpClient` POST in `lib/` sets `contentLength` — the shipping
    `WledService` paths appear to work, so this may be test-only today, but the failure mode is
    silent and the next person will pay the same hour.

- [ ] **P1-5 — Gamma drift root cause (Symptom C)**
  - Status: OPEN · Evidence: bench-proven (symptom) / suspected (cause)
  - `gc.col` flipped 2.8→1 during the AI-command window; self-healed by the pusher on-connect.
    Source never found. Fold into the P0-1/P0-2 AI-path diagnostic.
  - NEW EVIDENCE 2026-07-24: `gc.col` observed 2.8 at ~10:40 and 1 at ~10:47. Only actions in the
    window: P1-43 channel-power taps (`/json/state` only — CANNOT write cfg, so exonerated), app
    connects (pusher ASSERTS 2.8 — the medic, not the culprit), and throwaway schedule CREATION
    with a pattern + Sync. Sync itself was previously exonerated (gamma unchanged across multiple
    syncs 2026-07-21) → prime suspect NARROWS to the **design/pattern-apply path** — consistent
    with Symptom C's original AI-command window, which also applied a design. The caught-in-the-act
    diagnostic should instrument pattern/design applies FIRST.
  - NEIGHBORHOOD-AUDIT NOTE 2026-07-24: gamma `no-gc:false` (realtime/DDP gamma NOT bypassed) is
    re-asserted on EVERY connect by the LAN-only watchdog/healer
    ([controller_defaults_healer.dart:615-709](lib/features/wled/controller_defaults_healer.dart#L615),
    readback-gated `pushGammaConfig`) — but LAN-ONLY: a fleet member controlled only via the remote
    relay never gets the heal, so it could carry stale `no-gc:true` from a pre-fix provision.
    Bench 192.168.1.150 verified `if.live.no-gc:false`, `light.gc {bri:1,col:2.8,val:2.8}` (correct).
    Fleet-wide parity is unverifiable remotely — needs a per-controller LAN read.
  - Files: AI apply path (see P0-1) + design/pattern-apply path + `light.gc` writer (gamma push on connect).

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
  - Status: OPEN · Evidence: bench-proven (2026-07-23 12:56 OFF fire: `ps:-1` after timer-fired preset load)
  - After a timer fires, app shows raw WLED effect names ("Solid", "Running") instead of the
    design name. **Diagnostic ANSWERED (was "curl /json/state, is ps the slot?"):** firmware
    does NOT leave `ps` pointing at the fired preset — `ps:-1` confirmed on the 12:56 fire. So
    this CANNOT be solved by a `ps → app-owned slot → design name` lookup; it requires the same
    "last applied design" record as P1-11.
  - Files: `lib/features/ai/pattern_label_resolver.dart`, dashboard state display in
    `lib/nav.dart`, + the persisted last-applied record shared with P1-11.

- [ ] **P1-11 — Design-name attribution: Game Day / live applies (ps:-1)**
  - Status: OPEN · Evidence: reported; `ps:-1` now bench-proven (2026-07-23) for timer fires too
  - Non-preset applies report `ps:-1` — and, per the 12:56 bench finding, so do timer-fired
    *preset* loads. So a "last applied design" record written at apply time is now REQUIRED for
    BOTH the live-apply case AND the schedule-fire case (P1-10); neither can lean on `ps`.
    **Rides with** the P0-1..P0-3 consolidation — instrument the surviving write paths, not the
    doomed ones.
  - Files: surviving apply paths (post-consolidation) + a persisted last-applied record.

- [ ] **P1-22 — My Designs apply + Now-Playing label (ex-#62/#81)**
  - Status: OPEN (code shipped `b7f335a`, on-device verify never recorded) · Evidence: reported
  - My Designs unified to an Explore category applying through the 6-step canonical apply
    (`applySavedDesign`); #81's stale-preview + wrong-label fall-through fixed as a consequence.
    Verify owed: apply saved all-blue design → preview only blue + Now Playing = design name
    (not "Solid"/"Halloween Eyes"); survives cold-start. Related to P1-10/P1-11 (attribution
    still broken elsewhere — this surface may share the fix).
  - Files: `lib/features/design/apply_saved_design.dart`, My Designs Explore category.

- [ ] **P1-23 — Game Day team cluster E1/E3/E5 (ex-#63)**
  - Status: OPEN (E1 shared service exists; E3/E5 unverified) · Evidence: reported (Ellie 2026-05-27)
  - Writer≠reader. E1: installer must route through `TeamRegistrationService.addTeam` (writes
    BOTH `/game_day_autopilot/` + profile `sports_teams`/`sports_team_priority`) —
    service now exists, confirm installer uses it. E3: `updateMyTeams()`/`clearMyTeams()` had
    zero call sites → Explore "My Teams" never populates; wire `patternRepositoryProvider` to
    `currentUserProfileProvider`. E5 (product-locked): autopilot toggle ON populates season
    calendar force-bypassing 7-day gate + tags entries by source; OFF tears down tagged entries.
  - Files: `lib/features/sports_alerts/services/team_registration_service.dart`,
    `patternRepositoryProvider`, Game Day picker, `calendar_entry_lease_manager.dart`.

- [ ] **P1-24 — Cold-start preview/label leak: verify across all writer paths (ex-#77)**
  - Status: OPEN (code shipped `e222dde` + `7ddb8cc`, formal on-device verify owed) · Evidence: bench-proven (symptom)
  - Bug B `normalizeWledPayload` col[]-pad chokepoint was bypassed by 4 sibling writers
    (`WledService.setState`/`.savePreset`, `CloudRelayRepository.setState`/`.savePreset`); all
    routed through `applyJson` + solid-mode read guard added. Run the 6-step on-device sequence
    (3-color→solid→cold-start→lease/savePreset→slider→remote-mode repeat) and document.
    Subsumes ex-#74 (Bug B `e556251` formal verify).
  - Files: `lib/features/wled/wled_service.dart`, `lib/features/wled/cloud_relay_repository.dart`.

- [ ] **P1-25 — Cloud Function WLED payload normalize parity (ex-#78)**
  - Status: OPEN · Evidence: suspected (surfaced by #77 writer sweep)
  - Background workers POST to `applySyncPattern` etc.; if Cloud Functions build WLED payloads
    without an equivalent `normalizeWledPayload` step, the col[] stale-slot leak re-poisons
    devices server-side on autopilot/sync fires regardless of client fixes. Audit
    `functions/src/` for WLED payload construction; ensure chokepoint parity.
  - Files: `functions/src/` (WLED payload builders), callers
    `game_day_autopilot_background_worker.dart`, `sync_event_background_worker.dart`.

- [ ] **P1-42 — LED layout change staleness: presets render wrong until next Sync**
  - Status: OPEN · Evidence: bench-proven (2026-07-23: channel-2 `hw.led` 30→73)
  - Resizing a channel's pixel count (`hw.led`) leaves ALL stored presets rendering wrong on the
    changed segments until the next Sync re-psaves them — presets bake segment geometry, so a
    layout change silently orphans them. Fix: detect layout drift in the sync (compare
    `hw.led.ins` against last-known) OR hook the layout-save flow to force a full preset re-save
    + user notice. **Workaround until fixed: Sync after any layout change** — surface this to users.
  - Files: `lib/features/schedule/schedule_sync.dart` (drift detect + re-psave), the
    channel/segment layout-save flow, `lib/features/schedule/calendar_entry_lease_manager.dart`
    (shares the psave path).

- [x] **P1-43 — Per-channel power is master-global (both channels toggle together)** — DONE `cdc436b`
  - Status: DONE `cdc436b` (merged to main `ad6ae98`, tag `v2.5.10+53`) · Evidence: bench-proven
  - BENCH-VERIFIED 2026-07-24 (192.168.1.150, build cdc436b/+53, 290 LEDs ch1=128/ch2=162): case 3
    (critical) from master-off, front on → ONLY front lit, one POST — PASS; case 4 back on while
    master on → seg-only, front undisturbed — PASS; case 1 front off → only front dies — PASS;
    case 2 last lit channel off → master reads off — PASS. Two-boundary throwaway also passed
    (curl /json/cfg 10:50 macro:10 / 10:55 macro:2, both en:1, dow:16; ON 10:50, OFF 10:55 fully
    dark). Fix: additive `setChannelPower` (live getState + fresh-bounds cfg refresh, id-only
    fallback) → `buildChannelPowerPayload` 4 shapes; per-chip power icon; `togglePower` + 5 master
    callers untouched; `/json/state` only.
  - Original diagnosis (bench-proven 2026-07-23: curl seg-scoped on:false darkened ch1 only; app
    power toggled both):
  - Firmware segment independence is confirmed
    (`{"seg":[{"id":0,"on":false},{"id":1,"on":true}]}` darkens ch1, leaves ch2 lit). The app's
    power path writes **top-level master `{"on":bool}`** regardless of the channel selector, so a
    per-channel off hits the whole device. There is NO seg-scoped OFF primitive anywhere:
    `applyChannelFilter` and `buildParticipatingSegArray` both force `on:true`; off is master-only
    by construction.
  - Wrong payload: `_postUpdate` sets `payload['on'] = on` top-level —
    [wled_providers.dart:1530](lib/features/wled/wled_providers.dart#L1530) (`on` deliberately
    excluded from `needsChannels` at :1494; never enters seg[] at :1547). Entry:
    dashboard power circle [wled_dashboard_page.dart:956](lib/features/dashboard/wled_dashboard_page.dart#L956)
    → `togglePower` [wled_providers.dart:1073](lib/features/wled/wled_providers.dart#L1073) → `_postUpdate(on:)`.
  - Mapping (sound): channel id = bus index, `start/stop` from `hw.led.ins[]` via
    `deviceChannelsFromConfig` [zone_providers.dart:83](lib/features/wled/zone_providers.dart#L83).
    Staleness risk (see P1-42): `deviceHardwareConfigProvider` caches `/json/cfg`, invalidated only
    at [system_management_screen.dart:238](lib/features/site/system_management_screen.dart#L238) or
    app restart — so a seg-scoped off with stale bounds (ch2 73 vs 160) could leave the new pixels lit.
  - Fix (additive, minimal): a seg-scoped per-channel power write
    `{"seg":[{"id,start,stop,on:false"}]}` with NO top-level `on`, routed through `applyJson`, used
    when a channel filter is active; force-refresh device config first (P1-43 depends on P1-42).
    Add a seg-off primitive (both filter builders currently hardcode `on:true`).
  - Master policy DECISION NEEDED: single-channel off must NOT write master; when the LAST lit
    channel goes off, should master follow (`{"on":false}`) or stay on with all segs dark? (Confirm
    with Tyler.) "All Channels On" recovery already exists
    [channel_selector_bar.dart:272](lib/features/dashboard/widgets/channel_selector_bar.dart#L272).
  - Blast radius — `togglePower` callers that legitimately want MASTER and must NOT change: dashboard
    circle, voice ([voice_providers.dart:255](lib/features/voice/voice_providers.dart#L255)/:276,
    [dashboard_voice_control.dart:126](lib/features/voice/dashboard_voice_control.dart#L126)/:137),
    Game Day resume [game_day_autopilot_providers.dart:84](lib/features/autopilot/game_day_autopilot_providers.dart#L84),
    Neighborhood resume. Fix must add a new seg-scoped action, not repoint `togglePower`.

- [ ] **P1-44 — Neighborhood Sync server-fanout path is DORMANT in production (config/sync_fanout unreadable)**
  - Status: OPEN · DECISION: **keep the fanout code, mark DORMANT** pending a Neighborhood Sync
    launch decision — DO NOT delete. Evidence: verified-by-deployed-state (2026-07-24, project
    `icrt6menwsv2d8all8oijs021b06s5`)
  - The foreground crew-fanout path (`NeighborhoodService.fanoutAdHocSync`
    [neighborhood_service.dart:472] → CF `applySyncPattern`) is gated on
    `config/sync_fanout.enabled` ([sync_fanout_feature_flag.dart]). DEPLOYED-STATE CHECK: (1) there
    is **no `match /config/sync_fanout`** rule in the deployed ruleset OR the repo — default-deny;
    (2) the **doc does not exist** (Firestore REST → 404). So the flag reader (client AND the CF's
    own `readSyncFanoutEnabled`) always falls back to `false` → the fanout branch is unreachable.
  - **DOUBLE-DEAD finding (2026-07-24):** `bootstrapSyncFanoutFlagDoc()`
    [sync_fanout_feature_flag.dart:71] is DEFINED but **NEVER CALLED** anywhere. So the doc is
    double-dead: nothing creates it, and even if bootstrap ran, the missing rule would default-deny
    the client create anyway. That is why it is 404.
  - **ACTIVATION STEPS (future session, when a launch decision is made — deliberate, not accidental):**
    (a) create `config/sync_fanout` with `enabled:false` — via a `bootstrapSyncFanoutFlagDoc()` call
    at launch OR the console (needs a create-allowing rule first: mirror
    `config/schedules_subcollection` [firestore.rules:1471], which allows create when
    `enabled==false`); (b) verify the anti-strobe rate limiter `reserveFanoutSlot` is live
    [applySyncPattern.ts:166]; (c) flip `enabled:true` in the console ONLY after (b) and a real-crew
    test. NOTE: a READ-ONLY rule was added separately (see below) to stop the per-launch
    permission-denied; that does NOT activate fanout (no doc, no create rule → flag stays false).
  - **Five never-executed-in-production code paths (dormant, keep):**
    1. Foreground fanout branch `broadcastSync` — [neighborhood_providers.dart:336-346]
    2. `NeighborhoodService.fanoutAdHocSync` (HTTP POST, `fanout:true`) — [neighborhood_service.dart:472]
    3. CF flag-gated fanout block — [applySyncPattern.ts:159-190]
    4. `reserveFanoutSlot` (rate limit) + `fanoutToCrew` — [applySyncPattern.ts:166,180]
    5. `bootstrapSyncFanoutFlagDoc()` (never called) — [sync_fanout_feature_flag.dart:71]
  - **DONE (partial):** read-only `match /config/sync_fanout` rule added to `firestore.rules`
    (hygiene — stops the fleet-wide per-launch permission-denied on the flag listen; flag stays
    absent/false). NOT deployed (rules deploy authorized separately).
  - ⚠️ **STATE CORRECTION 2026-08-12 — the title and the 404 premise above are now STALE.**
    Re-verified against live infra; four of the blockers recorded above have since cleared:
    1. **Rule is DEPLOYED.** Live ruleset `93c99c50-0b3d-4a72-b76f-eb6f3040550d`
       (release `cloud.firestore`, updateTime `2026-08-05T19:27:10Z`) contains the full
       `match /config/sync_fanout` block — `allow read` **and** `allow create` (enabled==false),
       `update/delete: if false`. It rode along with the 2026-08-05 command-safety/solar deploy.
       So it is no longer "read-only, not deployed" — the create-rule is live too.
    2. **The doc EXISTS.** `config/sync_fanout` = `{enabled: false}` (admin read, 2026-08-12).
       Not 404. Runbook step 2 is satisfied. `bootstrapSyncFanoutFlagDoc()` is **still never
       called**, so the doc was provisioned out-of-band (console) — the "double-dead" finding
       holds for the *bootstrap function* but no longer for the *doc*.
    3. **The CF is DEPLOYED and current.** `applySyncPattern` updateTime
       `2026-07-25T19:55:32Z`, state ACTIVE. Every SYNC-1/2 source commit predates it
       (`7d71374` rate limiter 2026-07-01; `76324ce` SYNC-1 2026-07-25T02:11Z; `25baadb`
       2026-07-25T15:46Z) and **no commit has touched `functions/src/applySyncPattern.ts`
       since** — so deployed == current source. Runbook step 3 is satisfied.
    4. **`evaluateRateLimit` HAS tests.** `functions/test/unit/fanoutRateLimit.test.js` +
       `fanoutMutualMembership.test.js` — **17/17 pass under jest** against the tsc-compiled
       `lib/` (2026-08-12). The runbook's "NO test file" gap note is stale. NOTE: they need
       `npx jest`; `node --test` fails with `describe is not defined` (no `node:test` import).
    - Also resolves `audit/RELEASE_READINESS.md:180` ("SYNC-1 absent from the committed
      `functions/lib/applySyncPattern.js`"): `lib/` is tracked, was rebuilt `be0b007`
      2026-08-01, and now carries `verifyFanoutTarget` (×4) plus the correct constants
      (5 / 18000 / 60000).
    - **Net: fanout is dormant by FLAG, not by absence.** The only thing between here and live
      is the two-node test (runbook step 4) and the console flip (step 5). Correct the title
      when this item is next touched: it is no longer "unreadable".
  - Files: `firestore.rules` (read-only sync_fanout block added; create/flip still absent by design),
    `lib/features/neighborhood/sync_fanout_feature_flag.dart`, `neighborhood_service.dart:472`,
    `functions/src/applySyncPattern.ts:159-190,312-325`.

- [ ] **P1-46 — MAIN suite is RED (2 pre-existing failures) — masks regressions (green-main gate)**
  - Status: OPEN · Evidence: reported (verified on main + every build branch, 2026-07-24)
  - `main` (and every branch off it) fails exactly 2 tests: `cloud_ai_processor_normalize`
    ('Sunset') and `schedule_sync_time_parse` (solar). Because the suite is ALWAYS red, a NEW
    regression is invisible — you can't tell "2 failing" (known) from "3 failing" (a fresh break)
    at a glance, and any green-gate on PRs is unusable. Fix = repair or explicitly quarantine
    (skip-with-reason) the 2 so `main` goes GREEN; thereafter red==real regression and the suite
    can gate merges. This is the release-gate/trust framing of the SAME two tests tracked by
    **P1-8** (fix-or-delete the stale tests) — resolve together; P1-8 is the mechanism, P1-46 is
    the "keep main green" outcome + gate.
  - Files: `test/…/cloud_ai_processor_normalize*`, `test/…/schedule_sync_time_parse*` (see P1-8).

- [ ] **P1-47 — Single-channel "on" briefly lit ALL channels (RESOLVED/INTERMITTENT — WATCH)**
  - Status: WATCH (self-corrected in-session; root cause NOT confirmed) · Evidence: reported
    (observed in-app, not isolated — no readback captured)
  - With only ch1 selected, an "on" lit **all** channels. Corrected by deselecting/reselecting
    channels; subsequent single-channel commands targeted correctly. No code change made.
  - Hypothesis (unconfirmed): stale selection-vs-command-target state — the channel selection the
    UI showed was not the selection the command path read. NOT a confirmed regression of P1-43
    (which is bench-proven for the fresh-selection cases); the failing shape here is the
    additive/stale-selection case P1-43's bench matrix did not cover.
  - **REPRO CAPTURE (do this BEFORE correcting, if it recurs):** exact screen, controller IP,
    whether the selection was **fresh** (app-launch/first pick) or **additive** (toggled after a
    prior selection), and a `curl /json/state` readback taken while the wrong channels are lit.
    Without that, the selection→command path cannot be audited from a live repro.
  - Suspect files (unaudited): `lib/features/dashboard/widgets/channel_selector_bar.dart`
    (selection state), `lib/features/wled/wled_providers.dart` (`setChannelPower` /
    `applyChannelFilter`), `lib/features/wled/channel_power_payload.dart`
    (`buildChannelPowerPayload`).

- [ ] **P1-49 — Design Studio conflict prompt blocks EVERY AI search with no selectable control**
  - Status: OPEN · Evidence: bench-observed 2026-08-03 (2.5.10+62, 192.168.1.150) ·
    **LOG ONLY, not fixed.** Blocks Part B slice 3 entirely — map-driven smart presets could not
    be tested.
  - **Observed:** every AI design search returns *"Resolve Conflict — These settings overlap,
    which should take priority?"* with **no selectable option**. The user cannot choose a priority
    and cannot proceed. Dismissible (back to home), so it blocks the feature rather than trapping
    the app.
  - **The DETECTION is correct, the RESOLUTION UI is the defect.** Captured corners sit at the
    boundary of adjacent runs, so the overlap is genuine — this is not a false positive to be
    tuned away. Suppressing the detection would be the wrong fix.
  - The question is built at
    [clarification_service.dart:379-388](../lib/features/design/services/clarification_service.dart#L379)
    and **does** populate `options` — including a `'merge'`/"Blend both" option injected at
    `:371-378`, then `options.take(4)`. So options exist at construction. The break is therefore
    downstream: either the list arrives empty/1-length at the widget, or
    [clarification_dialog.dart](../lib/features/design/widgets/clarification_dialog.dart) has no
    render arm for `ClarificationType.conflictResolution`. **Not isolated — needs a repro to
    discriminate.** Start by logging `options.length` at the dialog boundary.
  - **Severity note:** filed P1, not P0, because no customer lighting is broken and there is no
    data loss. Re-file as P0 if Design Studio is launch-critical — as observed it is a total
    feature block with no workaround, on every search.
  - Files: `lib/features/design/services/clarification_service.dart`,
    `lib/features/design/widgets/clarification_dialog.dart`,
    `lib/features/design/models/clarification_models.dart`.

- [ ] **P1-50 — Manual pixel editor: Undo and Erase do nothing; a 290-px misclick is unrecoverable**
  - Status: OPEN · Evidence: bench-observed 2026-08-03 (2.5.10+62) · **LOG ONLY, not fixed.**
  - **Observed:** painting is correct — corners and runs land exactly on the captured segments,
    clean boundaries, no bleed (the substantive R-4 result). But after applying colour, **UNDO and
    ERASE both do nothing**, with no way to revert. Installer-facing on a 290-pixel run, where a
    misclick is inevitable.
  - **The machinery exists and is wired**, which is why this needs a repro rather than a rebuild:
    `EditHistory` implements undo/redo/`canUndo`
    ([edit_history.dart](../lib/features/design/manual_editor/edit_history.dart)); `_commit` pushes
    to history ([manual_design_editor.dart:81](../lib/features/design/manual_editor/manual_design_editor.dart#L81));
    Erase → `_clearSelectionToBase` (`:348`), Undo → `_undo` (`:349`).
  - ## ROOT CAUSE — BENCH-PROVEN 2026-08-04 on 192.168.1.150. **The Dart is correct end to end.**
    **A per-pixel write FREEZES the WLED segment (`frz:true`), and the undo/erase payload is a
    segment-level `col` write, which a frozen segment never renders.**
    - Proven by replaying the app's exact wire payloads:

      | Step | POST | `seg0.frz` after |
      |---|---|---|
      | A | unfreeze + base solid (`col:[[10,10,12,0]]`) | `false` |
      | B | **per-pixel** `{"seg":[{"id":0,"fx":0,"i":[100,[0,229,255,0]]}]}` | **`true`** ← the paint froze it |
      | C | base solid **with `"frz":false`** | `false` |

    - `applyBaseAndSpans` writes base-then-spans
      ([design_apply.dart:39-52](../lib/features/design/manual_editor/design_apply.dart#L39)) and
      **never sends `frz`**. After any paint the segment is frozen, so the base write is stored but
      not rendered — the painted pixels persist and undo/erase look inert.
    - Only a direct `i` write changes a frozen segment's pixels. Undo/erase emit **fewer** spans,
      so they write nothing per-pixel and rely entirely on the base repaint that cannot land.
    - **The rig was found already frozen** (`frz:true`) from Tyler's own design session before the
      experiment began — independent corroboration.
    - **This is why three code-reading passes failed.** Nothing in the Dart is wrong; the defect is
      a single WLED field the app never sends. It is invisible from the source alone.
    - **Fix direction (NOT implemented):** include `"frz": false` in the base payload of
      `applyBaseAndSpans`, or unfreeze before the base write. Needs a bench re-verify that
      unfreezing does not break the per-pixel paint that immediately follows it (order matters:
      unfreeze → base → per-pixel, since step B shows the per-pixel write re-freezes anyway).
  - **FALSIFIED HYPOTHESES — do not re-derive.** Each was reasoned from source and each was wrong
    against hardware: (1) controls unwired — they are wired; (2) empty undo stack — history is
    pushed on every paint; (3) the `_livePreview` gate — Tyler re-tested with **Live Preview
    explicitly ON** and the strip still did not revert.
  - **Collateral finding — a frozen segment is a latent hazard beyond this editor.** Anything that
    renders by setting segment colour/effect (schedules, presets, Apply-to-Lights, the healer) will
    appear to do nothing while `frz:true` persists. The freeze survives until something explicitly
    clears it. Worth its own audit; the bench rig is sitting frozen right now.
  - Superseded source-only reading (kept for the trail): the controls are NOT dead and the history
    is NOT empty — undo and erase mutate the document correctly and simply never reach the LEDs.
    - The strip is written from exactly two places: `_apply()` ("Apply to Lights", `:366→:220`) and
      `_scheduleLivePreview()` (`:212`). **`_scheduleLivePreview` is gated on `_livePreview`, which
      defaults to `false`** (`:42`) — and `_commit` (`:83`), `_undo` (`:106`) and `_redo` (`:112`)
      *all* push to the strip only through that gate.
    - So the observed sequence is: **Paint** → document + on-screen preview update, strip unchanged
      → **Apply to Lights** → strip shows the design (this is the "painting works" observation) →
      **Undo/Erase** → document + on-screen preview revert, **but `_apply()` is not re-run and live
      preview is off, so the strip keeps showing the applied design.**
    - Nothing tells the user that Undo requires pressing "Apply to Lights" again to take effect on
      the hardware.
    - **Falsification test (one minute at the bench):** toggle **Live Preview ON**, paint, then
      undo. If the strip reverts, this is confirmed and the fix is about re-apply/affordance, not
      about the history stack.
  - **Secondary real defect found in the same trace:** `_clearSelectionToBase` (`:95-101`) has **no
    empty-selection guard**, unlike `_paintSelection` (`:87`, which early-returns). With no active
    selection, Erase commits a document identical to the current one *and pushes it onto the undo
    stack* — a silent no-op that also inflates history with junk entries the user must undo through.
  - **Ruled out during the trace, record so it is not re-derived:**
    - *Additive-only apply* — `applyBaseAndSpans` repaints the base across the effective channels
      (`col: [baseRgbw]`, [design_apply.dart:39-52](../lib/features/design/manual_editor/design_apply.dart#L39))
      **before** overlaying spans, so a removal IS visible once a push happens. `onlyPainted: true`
      in `_spans()` is therefore not the problem.
    - *Empty history / disabled Undo* — the only paint path is the explicit **Paint** button
      (`:347 → _paintSelection → _commit → _history.push`); tapping the strip toggles *selection*
      (`:419-420 onToggle`), it does not paint. So `canUndo` is true after any real paint.
    - *Selection cleared by paint* — `_commit` does not touch `_selection`, so Erase still has
      pixels to act on immediately after a Paint.
  - Files: `lib/features/design/manual_editor/manual_design_editor.dart`,
    `lib/features/design/manual_editor/edit_history.dart`.

- [ ] **P1-51 — P0-7 fixed ONE of at least THREE roofline save surfaces**
  - Status: OPEN · Evidence: verified-by-source 2026-08-03 · **Scoping gap in a shipped fix.
    Checkable without hardware.**
  - P0-7 gated `MapRooflineStep._onContinue()` on a confirmed save. That step is constructed at
    exactly one call site ([installer_setup_wizard.dart:728](../lib/features/installer/installer_setup_wizard.dart#L728))
    — so the fix covers the **wizard path only**. Two other roofline save paths are routed and
    reachable:
    1. [roofline_editor_screen.dart:636-647](../lib/features/site/roofline_editor_screen.dart#L636) —
       `_saveRoofline` awaits `configEditor.save()`, then shows a **green "Saved N roofline
       segments"** and `context.pop()`s. Success is inferred from "no exception thrown", not from a
       confirmed write. Its `catch` does surface a red snackbar, so it is **not silent** — but it is
       the same assume-success shape P0-7 was written to remove.
    2. [roofline_setup_wizard.dart:140](../lib/features/design/roofline_setup_wizard.dart#L140) —
       `savePixelMap` / `saveConfiguration`, a third independent path.
  - **Why it matters:** the P0-7 regression test pins the wizard step only, so a future change to
    either other surface reintroduces the class with the suite still green.
  - Files: `lib/features/site/roofline_editor_screen.dart`,
    `lib/features/design/roofline_setup_wizard.dart`,
    `test/features/installer/map_roofline_save_gate_test.dart` (coverage stops at the wizard).

- [ ] **P1-48 — Off-WiFi save is NOT detected as off-LAN; it attempts a LAN write and parks on
  "this can take a few minutes"**
  - Status: OPEN · Evidence: reported (bench-observed 2026-08-03, root cause traced in source;
    not yet isolated with a repro) · **LOG ONLY — the schedule armed correctly on the next
    on-WiFi sync; no data was lost.**
  - **Observed:** schedule created with the phone OFF the home WiFi. App showed the neutral cyan
    *"Saving to controller — this can take a few minutes. Your lights keep working."* Nothing
    further happened — no retry, no resolution, nothing armed. Reconnecting and syncing again
    landed the write and both boundaries fired.
  - **The branch that fired was `verifying`, NOT either deferral.** That copy is
    `kScheduleCfgVerifying` ([schedule_sync.dart:1748](../lib/features/schedule/schedule_sync.dart#L1748)).
    `verifying` is only reachable from `_pushCfgWithVerify`'s `onVerifying` callback
    ([:1485](../lib/features/schedule/schedule_sync.dart#L1485)) or the transient in-flight drop
    ([schedule_providers.dart:198](../lib/features/schedule/schedule_providers.dart#L198), cleared
    in a `finally`). The first implies **a cfg write was actually attempted** — so
    `repoCanWriteCfg(repo)` returned TRUE and the off-LAN branch never ran.
  - **Why:** `repoCanWriteCfg` is `repo is! CloudRelayRepository || repo.supportsCfgWrites`
    ([cloud_relay_repository.dart:651](../lib/features/wled/cloud_relay_repository.dart#L651)) — it
    is a REPO-TYPE test, not a reachability test. Off WiFi the SSID is null and connectivity
    **defaults to LOCAL, not remote** (known behavior — see project memory
    `feedback_connectivity_defaults`), so the app selects `WledService` and believes it can write.
    It then issues a LAN HTTP call to a controller it cannot reach and parks in the verify poll.
  - **Why this matters more than the wording:** the copy says the write *committed* and the
    controller will answer once it recovers. Nothing left the phone. The user is reassured about a
    write that never happened, and the only reason it self-corrected is that a later on-WiFi sync
    redid it. **This is the silent-success shape wearing a progress message.**
  - **NOT the lease gate pre-empting the off-LAN check.** In `syncAll` the off-LAN check
    (`:1316`) precedes `deferredLeaseLedger` (`:1357`), so the lease gate cannot pre-empt it. That
    ordering is correct and needs no change; the display-chain ordering is correct too.
  - Files: `lib/features/wled/cloud_relay_repository.dart` (`repoCanWriteCfg`), repo selection /
    connectivity detection, `lib/features/schedule/schedule_sync.dart` (`_pushCfgWithVerify`).
  - Related: P0-9, [[feedback_connectivity_defaults]].

- [ ] **P2-51 — In-app instruction points at an "Unpair Bridge" affordance that does not exist**
  - Status: OPEN · Evidence: verified-by-source 2026-08-03 · **LOG ONLY.**
  - [bridge_setup_screen.dart:528](../lib/features/site/bridge_setup_screen.dart#L528) tells the
    user to go to **"Settings → Remote Access → Unpair Bridge"**.
    `lib/features/site/remote_access_screen.dart` contains **no** unpair, reset, or forget action —
    grepped for all three. A customer following the in-app instruction finds nothing and calls
    support.
  - **This is also a real operational gap, not only a copy bug.** There is no supported app-side
    way to release a bridge: the firmware re-asserts `pairedUid` from NVS every heartbeat and
    `pollPairingRequest` returns early unless `status == "pairing"` (`main.cpp:1219-1220`), so a
    registry reset alone does not release it. Recovery today needs `/api/reset` over LAN or a
    re-flash. `manage_controllers_page`'s **Remove Controller** deletes the Firestore doc and its
    saved settings but does **not** touch NVS — leaving a bridge still claiming a uid the account
    has forgotten.
  - Two separable fixes: (a) correct or remove the dead instruction; (b) build the unpair path the
    instruction already promises. (a) is trivial and should not wait for (b).
  - Found while scoping whether the bench rig could be unpaired for commissioning verification —
    it cannot. See `audit/PART_B_RESULTS.md`.
  - Files: `lib/features/site/bridge_setup_screen.dart`,
    `lib/features/site/remote_access_screen.dart`, `esp32-bridge/src/main.cpp`.

- [ ] **P2-50 — Lease-deferral copy promises it "clears in a moment"; after ~8.7 s of backoff it
  never will**
  - Status: OPEN · Evidence: verified-by-source · **LOG ONLY — cosmetic; the protection works.**
  - `kScheduleLeaseLedgerNotice` = *"Saved — finishing up on your controller. This clears in a
    moment."* ([schedule_sync.dart:1755](../lib/features/schedule/schedule_sync.dart#L1755)).
    The retry ladder `_kLeaseLedgerRetryDelays` is `1200 + 2500 + 5000 ms` = **8.7 s total**
    ([schedule_providers.dart:31](../lib/features/schedule/schedule_providers.dart#L31)).
  - Once the ladder exhausts, the deferral **stands and stays on the status row** by design
    (documented at `schedule_providers.dart:124-127`) — so it is NOT silent, and that is the right
    call. But the copy asserts it will clear, and past that point it will not. Either soften the
    copy or give the exhausted state its own line.
  - **Scope correction on the report that raised this:** the "could take a few minutes" string is
    NOT the lease copy — it belongs to `verifying` (see P1-48). The 8.7 s ladder pairs with
    "in a moment", which is defensible. The two were conflated; only this narrower overpromise is
    real.
  - Files: `lib/features/schedule/schedule_sync.dart`, `lib/features/schedule/schedule_providers.dart`.

- [ ] **#67 — `_GameStatusBadge` renders 'Today' from the raw ESPN schedule regardless of
  server-side skip decisions — the client promises a fire the server refused**
  - Status: OPEN (recorded 2026-08-12) · Severity: **P1** · Evidence: verified-by-source
  - `_GameStatusBadge` ([game_day_screen.dart:1033](../lib/features/game_day/game_day_screen.dart#L1033))
    branches on `game.status` and nothing else: live → `score`, final → `Final x-y`, **else →
    `'Today'`**. Its data is `upcomingGameProvider`
    ([game_day_providers.dart:170](../lib/features/game_day/game_day_providers.dart#L170)) — a raw
    ESPN scoreboard read via `liveScoreFetcherProvider`. ESPN says a game exists; the badge says
    "Today"; nothing in between consults our own planner.
  - **The server decides separately, and none of its refusals reach the badge:** the
    `skip_day_games` daylight filter
    ([planGameDayFires.ts:366-386](../functions/src/planGameDayFires.ts#L366)), the
    `startInPast` / `startBeyondHorizon` horizon tests (`:401-403`), the participation gate
    (`:355-363`), and the #66 GUARD 0/0b end refusals. A daylight game the server dropped as
    `daylight_game` still reads **'Today'** on the card.
  - Customer-visible shape: user sees "Today", expects lights at first pitch, gets nothing, and
    has no way to learn the system decided against it on purpose. This is the trust failure #66
    was the mirror image of — there we fired without deciding to; here we decide not to fire and
    still promise it.
  - **Fix direction:** the pre-game promise must read plan/session state — `gameday_plan_log`
    rows and `game_day_sessions.startPlannedAt` — not the schedule. `'Today'` should mean *a
    start is planned*, with a distinct treatment (and reason) for *game today, no fire*.
  - ⚠️ **CONSTRAINT — do not regress the frozen-badge fix.**
    [game_day_providers.dart:164-169](../lib/features/game_day/game_day_providers.dart#L164)
    deliberately chose a live-gated self-poll **over** the celebration coordinator's
    `ScoreMonitorService`, because the coordinator polls only when celebrations are ARMED — so a
    celebrations-off user, or a team with no autopilot config, saw a permanently frozen badge.
    Repointing the whole badge at coordinator state reintroduces exactly that. **Split it:** the
    live/final SCORE half keeps its own ESPN cadence; only the pre-game PROMISE half reads plan
    state.
  - **Ordering: #68 is a prerequisite for the daylight case.** A daylight skip currently writes
    no plan-log row at all, so there is nothing for the badge to read — it cannot distinguish
    "server skipped this" from "not planned yet". Land #68 first or this fix is blind for the
    single most common skip reason.
  - Files: `lib/features/game_day/game_day_screen.dart:1033-1090`,
    `lib/features/game_day/game_day_providers.dart:112-200`,
    `functions/src/planGameDayFires.ts` (read-only — decision source). Related **#68**, **#66**.

- [ ] **#96 — installer-serviced controller writes land under the INSTALLER's uid, not the
  customer's: the read stream honours impersonation and every write ignores it**
  - Status: OPEN (filed 2026-08-18, controller-identity census) · Severity: **P1** ·
    Evidence: **verified-by-source**
  - `effectiveUserUidProvider` (`installer_access_providers.dart:39`) exists precisely so the
    "Existing Customer" flow redirects customer-data scopes at the customer's
    `/users/{uid}` documents while leaving the Firebase Auth identity alone.
    `controllersStreamProvider` honours it (`controllers_providers.dart:14`). **Nothing that
    writes does.**
  - **The four scoped call sites** (Stage 1 of the controller-replacement arc):
    - `lib/features/site/controllers_providers.dart:65` — `deleteControllerProvider`
    - `lib/features/site/controllers_providers.dart:81` — `renameControllerProvider`
    - `lib/features/ble/provisioning_service.dart:206` — `_saveToRepository` (BLE add)
    - `lib/features/ble/wled_manual_setup.dart:144` — manual-IP add
    All four take `FirebaseAuth.instance.currentUser.uid`.
  - **Consequence.** An installer inside Existing Customer sees the *customer's* controller
    list, then: an add writes a controller doc under the **installer's** account (the customer
    still has nothing, and the installer accumulates strangers' hardware); a delete or rename
    targets a doc id **in the installer's own subcollection** — usually absent, so it is a
    silent no-op that reports success. `deleteControllerProvider` returns `true` on a delete of
    a non-existent doc, because Firestore deletes are idempotent.
  - **Two further sites found during filing, NOT in the Stage 1 scope** — file-and-hold, they
    need their own decision:
    - `lib/features/wled/controller_facts_writer.dart:139` — `uidOverride ?? currentUser`.
      `uidOverride` is a **test seam only**: no production caller passes it (the sole forwarder
      is `participation_denormalizer.dart:231`, itself never called with one). So device-fact
      publishing (participation + base boundaries, one write per app session) writes to
      `users/{installerUid}/controllers/{controllerId}` during impersonation — **creating a
      stray controller doc under the installer's account** via `SetOptions(merge: true)`.
      That doc then feeds `syncControllerIps`, so the installer's own `controller_ips[]`
      allowlist grows a customer's IP.
    - `lib/features/dashboard/wled_dashboard_page.dart:213` — a **read**, not a write: the
      `limit(1)` probe that decides whether to show the "no controller" banner. Under
      impersonation it counts the installer's controllers, so the banner shows or hides on the
      wrong account's data. Cosmetic, but it is the same defect class.
  - **Why it matters beyond installer mode.** This blocks **Stage 1 of the controller-
    replacement arc** (`docs/design/controller_replacement.md` §2.4, §5.0): dealer-RMA
    replacement is by definition installer-performed, so a replace flow built on these paths
    would migrate a customer's home into the installer's account. Fixing this is the
    prerequisite, not a nicety.
  - **Fix shape.** `controllers_providers` reads `ref.watch(effectiveUserUidProvider)` at
    provider-build time (matching `controllersStreamProvider:14`, so consumers rebuild when the
    impersonation target changes). `ProvisioningService` is a plain class with no `ref` — inject
    the uid through its constructor from its single construction site
    (`device_setup_page.dart:386`, a `ConsumerState`). `WledManualSetup` is already a
    `ConsumerState` and can read the provider directly.
  - **Note for the auth boundary:** `effectiveUserUidProvider`'s own doc comment is explicit
    that auth-side providers (login, signup, password reset, claim checks) MUST keep using
    `FirebaseAuth.instance.currentUser`. This fix is only for data scopes. Do not sweep
    `currentUser` globally.

- [ ] **#97 — Game Day fires only ONE controller in multi-controller homes, chosen
  arbitrarily**
  - Status: OPEN (filed 2026-08-18, controller-identity census) · Severity: **P1** ·
    Evidence: **verified-by-source** · Related **#91**, **#67**
  - `planGameDayFires.ts:348-349`:

    ```ts
    const controllers = await db.collection("users").doc(uid).collection("controllers").get();
    const controller = controllers.docs[0] ?? null;
    ```

    One controller read per user, and **`docs[0]` with no `orderBy`**. Every fire job the
    planner writes names that single controller (`:588`, `:727`).
  - **Two distinct defects in one line.**
    1. **Coverage:** a home with two or more controllers has fires planned for exactly one of
       them. The rest of the house stays dark for the whole event. This is the same failure
       *shape* as #91 (partial-house fire) but a different cause — #91 is a payload-partition
       gap, this is a target-enumeration gap.
    2. **Determinism:** with no ordering clause the selection is Firestore's default document-id
       order, which for controller docs is the MAC-derived id
       (`device_discovery.dart:210-222`). So *which* controller fires is effectively arbitrary
       and can change. After a hardware replacement that left the predecessor's doc in place —
       today's normal outcome, since no replace flow exists — `docs[0]` can select the **dead**
       controller. `dispatchFireJobs` then resolves its stale `ip` and dispatches there.
  - **Why the dispatch half does NOT save it.** `dispatchFireJobs:275-293` correctly re-resolves
    the IP server-side and terminally skips `unresolvable_target` when the doc is gone. But an
    orphaned predecessor doc is **not** gone — it exists, with a stale `ip` — so dispatch
    succeeds into a dead or DHCP-reassigned host. The one robust pattern in the codebase cannot
    compensate for a wrong reference handed to it.
  - **Deliberately NOT bundled into the replacement arc.** Stage 1 of
    `docs/design/controller_replacement.md` repoints this call at the shared resolver's
    `primaryForExternalBinding()` — decision R-3, 2026-08-18 — which fixes **determinism and
    tombstone-awareness only**. It leaves the coverage defect exactly as it is: still one
    controller, just a predictable and live one. Widening to all controllers is this item, and
    it is its own change: it needs a per-controller job fan-out, the one-in-flight-per-controller
    guard re-examined across siblings (`dispatchFireJobs:317`), and a decision about whether
    partial delivery to a subset of a home's controllers is a success or a failure.
  - Files: `functions/src/planGameDayFires.ts:348-349, 588, 727` (`functions/` — deploy
    discipline applies; assumes **#94** Node 22 has landed). Do not start before the
    replacement arc's Stage 1.

- [ ] **#98 — removing a Game Day team does NOT tear down its scheduled fire jobs; the job
  fires for a team that no longer exists. 🚫 BLOCKS RE-ARM**
  - Status: OPEN (filed 2026-08-18, ghost-config teardown session) · Severity: **P1** ·
    Evidence: **PRODUCTION-PROVEN — caught armed and 4 h from firing**
  - `removeTeam` ([team_registration_service.dart:105](../lib/features/sports_alerts/services/team_registration_service.dart))
    strips the profile arrays, deletes `game_day_autopilot/{slug}`, cancels the in-memory
    session — and **cannot** touch fire jobs, because **`fire_jobs` has ZERO references
    anywhere in `lib/`**. There is no client teardown path to call. Nothing server-side reaps
    them either: there is no `.delete()` on a fire job in `functions/src/`, and
    `dispatchFireJobs`' "reconcile" reconciles *dispatched* jobs against their command
    outcomes (`:164-198`), not orphaned `scheduled` ones.
  - **The live instance.** On the bench uid `wrQRUUKyXyc0deyuu0ORS6wsovO2`:
    `fire_jobs/gd_mlb_royals_401816580_start`, planned **2026-08-18T17:10:06Z**,
    `state:"scheduled"`, `type:"applyJson"`, 130-byte `on+bri+seg` payload,
    `controllerId:"192_168_1_150"`, `fireAt` **2026-08-18T23:10:00Z**. The user deleted the
    Royals *after* 17:10; the config is gone (the account's only remaining config is
    `nfl_chiefs`) and the job survived untouched. Found at 18:57Z with **4 h 13 m to
    go** and retracted by hand.
  - **Why it would have fired.** See **#99** — the dispatcher never re-reads the config.
  - **Retraction convention set by this session** (follow it, or supersede it deliberately):
    retracted jobs are `state:"cancelled"` + `cancelled_reason` + `cancelled_at`, **never
    deleted** — `fireAt` and `payload` stay for the audit trail.
  - ⚠️ **`"cancelled"` is NOT in the `FireJobState` union** (`fireJobs.ts:110-116`:
    `scheduled|dispatched|completed|failed|expired|skipped`). It is *inert and safe* —
    `decideDispatch` only tests `!== "scheduled"` and both dispatch queries filter on
    `"scheduled"`/`"dispatched"` — but it is an undeclared value that any future exhaustive
    switch will not handle, and it will bucket as unknown in stats. **Add it to the union as
    part of this fix.**
  - **Gated, not fixed:** exposure is currently zero only because `config/gameday_planner`
    `write_jobs` was rolled back to `false` on 2026-08-18. Re-arming without this fix
    reopens it.

- [ ] **#99 — `decideDispatch` never re-reads the config or the team before firing; the #66
  guard's blind spot. 🚫 BLOCKS RE-ARM**
  - Status: OPEN (filed 2026-08-18) · Severity: **P1** · Evidence: **verified-by-source +
    production instance (#98)** · Sibling of **#66**
  - `decideDispatch` ([fireJobs.ts:214-253](../functions/src/fireJobs.ts)) checks exactly
    five things: `state === "scheduled"`, `fireAt` present, lateness ≤
    `MAX_FIRE_LATENESS_MS` (90 s), payload fire-safety, non-empty `controllerId`.
    **There is no check that the team's config still exists, or that it is still `enabled`.**
    `dispatchFireJobs` re-reads only the job and the controller doc — never
    `game_day_autopilot`.
  - **This is precisely the gap #66's guard does not cover.** The gate's own `armedReason`
    records GUARD 0/0b as *"confirmed live with two production sightings … both refused
    `end_skipped_no_start`"* — i.e. it protects the **end** fire from firing with no recorded
    start. A **start** fire whose team was deleted is a different shape and passes cleanly.
  - **Fix shape:** a config-existence + `enabled` recheck at dispatch, refusing terminally
    with a legible reason (`team_removed` / `config_disabled`) in the same style as
    `unresolvable_target`. Note this is the one place the codebase already models correctly
    for *addresses* (`dispatchFireJobs:275-293` re-resolves the controller IP server-side and
    never trusts the job's copy) — the same discipline simply was not extended to the team.
  - Files: `functions/src/fireJobs.ts:214-253`, `functions/src/dispatchFireJobs.ts:239-300`
    (`functions/` — assumes **#94**).

- [ ] **#101 — `gameDayTeamsProvider` renders any malformed config as a ghost card with a
  LIVE fire button, and couples its visibility to unrelated teams**
  - Status: OPEN (filed 2026-08-18) · Severity: **P1** · Evidence: **PRODUCTION-PROVEN**
  - Two clauses in [game_day_providers.dart:70-110](../lib/features/game_day/game_day_providers.dart):

    ```dart
    if (selectedTokens.isEmpty) return const [];        // (A)
    ...
    configName.contains(token) || token.contains(configName) || …   // (B)
    ```

    **(B)** — `configName` is `''` when a config lacks `team_name`, and in Dart
    `anyString.contains('')` is **always true**, so a nameless config matches *every* token.
    **(A)** — with no teams in the profile the provider returns before examining any config.
    Together: the ghost appears whenever **any** team is selected and vanishes when the last
    one is removed. The customer reads that as "the ghost is coupled to the Chiefs"; it is
    not — Chiefs merely satisfies (A).
  - The provider's own doc comment claims the invariant (B) breaks: *"orphaned subcollection
    docs from prior sessions are ignored."*
  - **The card is not cosmetic.** Its "Light Up Now"
    ([game_day_screen.dart:351 → :488-555](../lib/features/game_day/game_day_screen.dart))
    calls `applyGameDayConfigToDevice` against the live controller with the config's
    *defaults* — `0xFF000000`/`0xFFFFFFFF`, `effect_id:52`, `brightness:200` — then calls
    `toggleAutopilot(enabled: true)`, whose `existing.exists` branch is a bare
    `update({'enabled': true})` with **no slug validation** (`game_day_autopilot_providers.dart:585`).
    On a malformed doc that is a one-tap arm of the server planner.
  - **Production instance:** `users/wrQRUUKyXyc0deyuu0ORS6wsovO2/game_day_autopilot/mlb_twins`
    — a **four-key** doc (`enabled, espn_team_id, sport, updated_at`), no `team_name`, no
    `team_slug`, no colors, `enabled:true`. Rendered as "⚾ " with a bare "MLB" label and
    black/white `_TeamColorDots`. **Origin CONFIRMED**, not hypothesised: the 2026-08-13
    bench re-arm recorded in `docs/BUILD_LEDGER.md` as *"#72 instance 3 … Bench re-armed via
    `mlb_twins`"*. Its field set is exactly what `planGameDayFires` needs (`enabled` for the
    where-clause, `sport`+`espn_team_id` for the ESPN lookup) and nothing the card needs —
    the signature of a write authored against the server, not the UI. Full content preserved
    before deletion.
  - **It was also unremovable.** `_confirmRemove` passes `config.teamSlug` (`''`) →
    `_stripTeamFromProfile(uid, '')` matches nothing → **no write**, then `.doc('')` throws →
    **swallowed** at `team_registration_service.dart:123` → snackbar reports success. See
    **#100**.
  - **Fix shape:** filter malformed configs out of `gameDayTeamsProvider` (a config with no
    `team_name` or no `team_slug` is not renderable), and make (B) require a non-empty
    `configName`. Both halves — a nameless config must neither render nor match.

- [ ] **#108 — Roofline Mapping redesign to the PARENT SEGMENT model. Segments float free of
  channels, coverage is unverifiable, and direction has no home (+ September headline)**
  - Status: **OPEN — FILE ONLY, no implementation on main** (filed 2026-08-19) ·
    Severity: **P1 — promised feature, September headline** · Evidence: **reported**
    (first real-user walkthrough — Tyler + Ellie's install, 2026-08-19)
  - Surface: Design Studio → roofline setup (`lib/features/design/roofline_setup_wizard.dart`,
    `lib/features/design/segment_setup_screen.dart`, `lib/widgets/roofline_editor.dart`).

  **THREE OBSERVED DEFECTS**
  1. **Segments float free of channels.** Add-segment cannot target a channel, and nothing in
     the UI tells the user which pixels belong to which channel. Channel membership is an
     afterthought rather than a constraint.
  2. **Coverage is unverifiable.** No allocated/total accounting anywhere. A user cannot know
     whether every pixel is accounted for, so a partial map looks identical to a complete one.
  3. **Direction (`rev`) has no control in the roofline surface at all.** A misconfigured
     direction today requires hand-correction in the WLED UI. Direction is
     **provisioning-domain truth** per the wire-pin work; the pattern-grid L→R control
     (`2f5db8b`, routed through `applyGeometryJson`) is currently its only UI, which is the
     wrong home for it.

  **THE SPEC — Parent Segment model + two capture-time mechanics**
  1. **Parent Segment = channel.** Auto-derived from bus config (`hw.led.ins`), immutable, one
     per channel, showing hardware truth (name, total px, current direction). Children
     subdivide a parent, so **every segment belongs to exactly one channel by construction** —
     defect 1 becomes structurally impossible rather than validated against.
  2. **Identity is classification.** Each child is exactly one of Run / Corner / Peak / Column /
     Connector — the semantic types the map-driven presets already consume
     (`SegmentType` / `ArchitecturalRole` in `lib/models/roofline_segment.dart`). Coverage
     enforced: per-parent allocated/total px, unassigned ranges flagged.
  3. **Direction test per parent.** Fire a chase from pixel 0, user confirms visually, and the
     answer writes to the **bus config** via the provisioning door — not to a segment.
  4. **Live pixel identification.** Adjusting a child's range lights exactly those pixels on the
     physical strip, recomposed from the per-pixel write spine. ⚠️ Mind the `frz:true` / +63
     `psave` hazard (`audit/FROZEN_SEGMENT.md`) — a per-pixel `i` write sets `frz=true`, and a
     `psave` that captures it produces a preset that fires dark forever.

  **CAUTION for the design pass — this editor writes the pixelMap docs participation derives
  from.** The design must state explicitly what it writes to `is_primary`, `pixel_count`, and
  segment structure, plus the migration story for existing docs (`map_version` exists — use it,
  `lib/models/pixel_map_channel.dart:128,143`).
  - ⚠️ **Citation correction (verified 2026-08-19).** The spec as dictated cited
    "`roofline_editor.dart:690` hardcodes `is_primary` true". That line is a **false lead** —
    [roofline_editor.dart:690](../lib/widgets/roofline_editor.dart) is
    `_ControlButton(isPrimary: true)`, a Save-**button styling** prop with no relation to the
    `is_primary` data field. `pixel_map_channel.dart` does not carry `is_primary` at all.
    The real defaults-to-true writes are the **deserializers**:
    [roofline_segment.dart:721](../lib/models/roofline_segment.dart) and
    [led_channel_config.dart:111](../lib/models/led_channel_config.dart), both
    `json['is_primary'] as bool? ?? true`, serialized back at `roofline_segment.dart:764`.
    A doc that never carried the field reads back as primary. Send the design pass there, not
    to line 690. See **#95 / #101**.
  - ⚠️ **Leg B drift** — `pixel_count` 128 vs bus 162. The design must say which one the
    Parent Segment displays as "hardware truth" and which loses.

  **RESOLVES #102's open UI-ownership question.** Direction-correction belongs in the roofline
  surface, writing bus config — which is exactly the "UI write must also update the
  installation record" resolution #102 asks for and defers.

  **SIBLING, not part of this:** the per-channel photo-preview arc — same model, two views.
  Note the integration point only; do not scope it in.

  **Permitted work:** Phase 0 (design doc) may begin **in an isolated worktree**. The full
  design prompt exists. No implementation on `main`.

---

## P2 — hardening & platform

- [ ] **#107 — installer wizard has NO back/previous navigation; any input error forces a
  full restart**
  - Status: OPEN (filed 2026-08-19) · Severity: **P2 — UX, installer-facing**
    · Slot: **September UX arc, alongside per-channel previews**
  - **The symptom:** every step is forward-only. A typo in the customer email, a wrong
    controller selection, a mis-set site mode — none can be corrected in place. The
    installer restarts the wizard, in front of the customer.
  - **⚠️ THIS IS A STATE-MANAGEMENT TASK, NOT A BUTTON.** Do not scope it as "add a Back
    control". The steps have SIDE EFFECTS, and each one needs a defined answer to *what
    un-happens on back*:
    - **Account creation** (`_completeSetup` → `createUserWithEmailAndPassword` /
      `createCustomerAccount`) — an auth user and a `/users` doc may already exist.
      Backing past this step cannot simply forget the uid: re-running forward hits
      `email-already-in-use` and drops into the existing-customer lookup branch.
    - **Controller selection set** (`selectedControllerIds` / `linkedControllerIds`) —
      backing out of zone setup must decide whether the selection survives, and whether
      any controller-side write already made is reverted.
    - **Draft autosave** (`installer_draft_service.dart`, `_saveDraft()` fires on EVERY
      `_goToStep`) — back-nav writes a draft too, so a naive implementation persists the
      *backward* step index and makes resume land on the step the installer just left.
  - **BACK-NAV MUST RECONCILE WITH DRAFT-RESUME**, which already carries the
    **stale-controller-ID hazard** filed separately: a resumed draft can name controller
    ids that no longer exist on the network. Back-nav multiplies the paths into that
    state, so the two features have to be designed together, not sequenced.
  - **INTERIM MITIGATION EXISTS, AND ITS LIMITS ARE NOW VERIFIED** (not assumed —
    read out of `InstallerDraft.toJson`, `installer_providers.dart:754`). Autosave/resume
    genuinely reduces restart cost. It restores:
    `currentStepIndex`, `customerInfo`, `selectedControllerIds`, `linkedControllerIds`,
    `zones`, `siteMode`, `photoUrl`, `sessionPin`, `savedAt`.
    It does **NOT** restore:
    - the **handoff preference draft** (`installerPreferenceDraftProvider` —
      sportsTeams, favoriteHolidays, vibeLevel, changeTolerance, autonomy, managerEmail).
      It is a separate object collected at the LAST step, so the loss is small, but the
      mitigation does not cover it and should not be described as if it does.
    - any **account-creation state** (`userId`, `isExistingAccount`) — those are local to
      `_completeSetup` and are re-derived, not resumed.
    - commercial **brand setup** progress.
    So: resume restores the data-entry steps, not the side-effecting tail. That is the
    honest scope of the mitigation.


- [ ] **#106 — firebase-admin v13 → v14: the namespaced API is gone; 183 call sites across
  31 backend files (filed out of #94)**
  - Status: OPEN (filed 2026-08-18) · Severity: **P2 — no external deadline**
    · Evidence: **full compile census, measured — not estimated**
  - **Not urgent, and the reason matters:** `firebase-admin@13` declares `engines: node >=18`,
    so it runs on the **nodejs22** runtime unchanged. #94’s runtime migration did **not**
    require this bump and deliberately did not take it. There is no decommission date driving
    this the way 2026-10-30 drove Node 20 — v14 is available, not mandatory.
  - **What breaks:** v14 removes the namespaced surface. `admin.firestore()`, `admin.auth()`,
    `admin.firestore.FieldValue`, `admin.firestore.Timestamp` and the `admin.firestore.*`
    **types** all resolve to nothing. The replacement is the modular entry points —
    `getFirestore()` / `getAuth()` from `firebase-admin/firestore` and `firebase-admin/auth`,
    with `FieldValue` and `Timestamp` imported as values.
  - **THE CENSUS, taken 2026-08-18 against `firebase-admin@14.2.0` — 183 errors, 31 files:**

    | code | count | what it is |
    |---|---|---|
    | TS2339 | 122 | `.firestore` / `.auth` not on the admin module |
    | TS2694 | 37 | `admin.firestore` used as a **namespace** (type positions) |
    | TS7006 | 23 | implicit `any` — callback params inferred from the old types |
    | TS2322 | 1 | assignment mismatch |

    Heaviest files: `dispatchFireJobs.ts` (23), `planGameDayFires.ts` (17),
    `applySyncPattern.ts` (14), `staffAuth.ts` (13), `collectControllerHealth.ts` (10),
    `sendSyncNotification.ts` (9), `sendWeeklyBrief.ts` (8), `endSyncSession.ts` (7);
    23 more files with 1–6 each.
  - **The 23 TS7006s are the real work.** The other 160 are a mechanical import rewrite. The
    implicit-`any`s were previously inferred **from the namespaced types**; with the namespace
    gone they need **real signatures written** (`QueryDocumentSnapshot`, `DocumentData`), and a
    wrong one type-checks while changing what the code accepts. Do not treat the whole number
    as find-and-replace.
  - **⚠️ IT MUST LAND SOLO — do not let it ride along with other functions work.** It touches
    every backend function, so bundling it means a deploy where a behavioural regression
    cannot be attributed. Own branch, own commit, own full test pass, and its own **content
    gate** (`functions/lib/` readback proving the compiled output is the migrated code) before
    it goes near the fleet — the same gate #94 used.


- [ ] **#104 — Game Day entry stalls when hardware geometry disagrees with the installation
  record; the app must DEGRADE LEGIBLY, never freeze (+81)**
  - Status: OPEN (filed 2026-08-18, carried out of +80) · Severity: **P1 — customer-visible**
    · Evidence: **field-reported; NOT reproduced from source**
  - **The requirement, which stands regardless of the diagnosis:** when the controller's shape
    disagrees with the installation record, the screen **renders from the installation record
    immediately**, fills in device truth **asynchronously**, marks untrusted channels
    **inline** as *"controller layout out of sync"*, and offers a **re-provision button**. No
    modal traps. No infinite spinners.
  - **Why it is still open after +80:** the connect-time heal (`e5c39c8`) **shrinks the
    mismatch window; it cannot remove it.** A device can be mid-drift when the app attaches,
    and the heal deliberately stands aside on an unreadable read. Do not close this item on
    the grounds that the heal exists — that is the trap this note is written to prevent.
  - **TRACE RESULT — the hang is NOT where it was expected, and the timeout audit is CLEAN:**
    - Game Day's build path is shape-independent. `effectiveChannelIdsProvider`,
      `deviceChannelsProvider` and `applyGameDayConfigToDevice` are read in `_activateNow`
      (`game_day_screen.dart:514-515`) — a **tap** handler, not a build.
    - Cleared: `resolveParticipatingChannels` (pure); `_gameDayBackgroundPersistenceProvider`
      (every write `unawaited`); `runParticipationReconciliationIfReady` (self-gating, and
      **dashboard-only** — not reachable from Game Day); `CloudRelayRepository.getConfig()`
      (returns null immediately).
    - **Every controller-facing call on the path is bounded.** `WledService`: **24 I/O sites,
      all with `connectionTimeout` + `.timeout()`** (5s/10s/15s/30s). Relay `_executeCommand`:
      bounded by `_commandTimeout` with listener auto-cancel. ESPN
      (`espn_api_service.dart:96`): 15s. **No user-facing controller call lacks a timeout.**
  - **Two surviving hypotheses, and they need DIFFERENT fixes — which is why no fix shipped
    in +80:**
    1. **Serial-timeout stall.** Several 15s timeouts in sequence = 45–60s of
       unresponsiveness, which a user reports as a freeze. Bounded but neither fast nor
       legible. **A degraded-state widget alone does NOT fix this** — it would still sit
       behind 45s of timeouts. Needs render-then-fill (or parallelised reads).
    2. **A never-resolving loading state** → permanent spinner. Cured by the degraded state.
  - **THE EXPERIMENT THAT SETTLES IT** (post-cut, Tyler drives the app): collapse the bench to
    1 seg, enter Game Day, **time it**, with `adb logcat | grep -E "LUMINA_WIRE|TimeoutException"`
    running. Under ~60s and self-recovering ⇒ (1). Indefinite ⇒ (2).
  - **Design already settled** (implement after the diagnosis): trust boundary from the shape
    comparison that already exists — `expectedShapeFromChannels` (buses) vs
    `segmentShapeFromState` (live) — yielding trusted/untrusted channel ids in the same
    `SegmentShape` vocabulary as `decideGeometryHeal` and the repro suite. The re-provision
    button is **a button to `applyGeometryJson` via the healer's existing
    `_reprovisionSegments`** — not new machinery. Extract as a pure
    `evaluateShapeAgreement(expected, live)` so it is testable without a widget, matching
    `decideGeometryHeal` and `buildChannelPowerPayload`.
  - Files: `lib/features/game_day/game_day_screen.dart`,
    `lib/features/wled/controller_defaults_healer.dart` (existing re-provision), plus a new
    pure shape-agreement helper (client-only).

- [ ] **#102 — a geometry re-provision restores bounds but NOT `rev`, so a repaired channel
  runs backwards (+81)**
  - Status: OPEN (filed 2026-08-18, +80 geometry work) · Severity: **P2** ·
    Evidence: **bench-measured 2026-08-18 on `.150`**
  - `_reprovisionSegments` emits `{id, start, stop}` only. After the +79 destruction the
    bench's seg1 lost `rev:true`; the repair restored its bounds and left it running in the
    wrong direction. A customer sees half the house animating backwards and has no control
    that fixes it.
  - **`rev` is NOT smuggling — measured.** Bus config vs live segments on `.150`:

    | | bus `rev` (`hw.led.ins`) | segment `rev` (`/json/state`) |
    |---|---|---|
    | 0 | `false` | `false` |
    | 1 | **`true`** | **`true`** |

    They agree, and `WledHardwareConfig` already parses `rev`
    (`wled_hardware_config.dart:41`). So `rev` comes from **the controller's own buses** —
    the same source the bounds come from.
  - **The healer's comment conflates two things.** *"must not smuggle geometry FIELDS
    (rev/mi/of/grp/spc)"* is right about `mi`/`of`/`grp`/`spc` — **look/rendering** properties
    with no bus-config counterpart, which the app would be *inventing*. `rev` is different:
    it is **physical wiring direction**, readable from `hw.led.ins`. Restoring it is the same
    act as restoring `start`/`stop`.
  - **Approved principle, verbatim (Tyler, 2026-08-18):** *"restore what the controller's own
    buses state; never assert what only the app believes."* Amend the comment to that
    principle rather than a field blacklist — a blacklist has to be maintained by hand, which
    is the failure mode of the four emitter censuses.
  - **Shape:** `SegmentShape` gains `rev`; `expectedShapeFromChannels` sources it from
    `WledHardwareConfig.rev`; `segmentShapeFromState` reads seg `rev`; `_reprovisionSegments`
    emits `{id, start, stop, rev}`.
  - ⚠️ **Why this is +81 and not +80.** Adding `rev` to `SegmentShape.==` changes the geometry
    gate's equality: devices whose segment `rev` disagrees with their bus `rev` would start
    classifying as **drifted** and get re-provisioned. That is correct behaviour but it is a
    LIVE change on devices previously considered healthy, and it needs its own bench
    verification rather than riding on the +80 pin.
  - ⚠️ **NEW TENSION, added 2026-08-19 — the UI can now set `rev`, and this bug will
    overwrite it.** The L→R / R→L direction controls
    (`pattern_grid_widgets.dart`, `pattern_adjustment_panel.dart`) were routed through
    `applyGeometryJson` so they actually reach the device — they had been silent no-ops since
    the wire pin was widened to fence `rev`/`mi`. That makes them the **first
    `applyGeometryJson` caller that derives its payload from a TAP** rather than from the
    controller's own buses, which is precisely what the approved principle above forbids
    asserting.
    - **The collision:** once this bug's shape-check ships, a user's direction flip that
      disagrees with the bus config's `rev` is classified as **drift** and "repaired" back.
      The user's choice silently reverts on the next heal, and the control looks broken
      again — differently.
    - **The resolution is NOT to exempt the UI write.** The bus config is the source of
      truth the healer restores from, so the UI write must **also update the installation
      record** (`hw.led.ins[].rev`), so the two agree and the heal is a no-op. Until then,
      a direction flip is durable only until the next re-provision.
    - **REMOTE GAP, deferred deliberately (2026-08-19):** `applyGeometryJson` is
      **LAN-only**. `CloudRelayRepository` throws `UnsupportedError` — the bridge
      dispatches live state and has no provisioning branch, the same boundary
      `applyConfig` hits with `CfgWriteUnsupportedException`. **A customer off
      their home network therefore cannot change a channel's direction.** The
      control is the only affected caller; `applyChannelDirection` catches the
      throw and reports "not applied" rather than crashing a button tap. Every
      other geometry writer (healer, geometry gate, sunrise-off, lease manager)
      is already LAN-only by construction, so nothing else regresses. Closing
      this means giving the relay a provisioning door — out of scope for +81.
    - Not resolved on either side; **made visible on both**. See
      `lib/features/wled/channel_direction.dart` for the same note at the write site.
    - **UI-OWNERSHIP QUESTION RESOLVED 2026-08-19 — see #108.** Direction-correction's home
      is the **roofline surface** (a per-parent direction test writing bus config), not the
      pattern grid. That is the "UI write must also update the installation record" half
      above. #108 is FILE-ONLY; this stays open until it lands.
  - Files: `lib/features/schedule/geometry_gate.dart:27`,
    `lib/features/wled/controller_defaults_healer.dart` (`_reprovisionSegments`),
    `lib/features/wled/wled_hardware_config.dart:41` (client-only),
    `lib/features/wled/channel_direction.dart` (the new UI writer).

- [ ] **#103 — the Lumina custom-effects catalog animates by MOVING SEGMENT BOUNDARIES.
  UNREACHABLE on +79 (two gates) — pre-launch redesign, NOT a hotfix**
  - Status: OPEN (filed 2026-08-18, updated same day with the sweep) · Severity: **P2 — no
    field exposure** · Evidence: **bench-proven on `.150` + verified-by-source**
  - 🚩 **NO FIELD EXPOSURE ON +79. Two independent gates make this dead code:**
    1. `LuminaCustomEffectsCatalog.isCustomEffect(int id) => false`
       (`lumina_custom_effects.dart:325`) — hardcoded. Every dispatch site asks it first
       (`pattern_repository.dart:255`, `pattern_explore_screen.dart:33`), so no id ever
       routes to a custom effect.
    2. `LuminaEffectController._isRunning` is initialised `false` and only ever assigned
       `false`. There is **no `_isRunning = true` anywhere in the file.**
    So **this was NOT the +79 field destruction** (see the ledger's incident closeout — root
    cause was a power-cycle + `bootps:0`, software attribution ruled out). This is a **latent
    class**, and the redesign is **pre-launch work, not a hotfix.**
  - 🔒 **STANDING CONSTRAINT: do not re-enable the custom-effects catalog without the geometry
    wire pin in place.** Flipping `isCustomEffect` to a real lookup without
    `geometry_wire_pin.dart` at the wire exit re-arms the exact class that can destroy a
    layout. The pin is the PRECONDITION for re-enabling, not a companion to it. Recorded in
    the source file's own library header so it is unmissable at the point of edit, and pinned
    by `test/features/wled/lumina_custom_effects_geometry_test.dart`, which **fails if the
    catalog is re-enabled**.
  - **THE SWEEP — every bounds-stating builder, and what each states:**

    | id | Effect | What it states | Note |
    |---|---|---|---|
    | 1001 | Rising Tide | final frame `{id:0,start:0,stop:290}`, seg 1 **omitted** | the +79 collapsed shape verbatim |
    | 1002 | Falling Tide | same builder, `reverse:true` | sweeps `start` instead of `stop` |
    | 1003/1004 | Pulse Burst / Gather | boundary sweep from/to centre | |
    | 1005 | Grand Reveal | final frame emits **ZERO-LENGTH** segs `[0,0)` and `[290,290)` | a zero-length bound is exactly what `applyChannelFilter` **Rule 1 forbids** — *"never a zero-length `[0,0)` bound"* — because it reads as "this channel does not exist" |
    | 1006 | Curtain Call | terminal split **hardcoded to `totalPixels ~/ 2`** = 145 on a 290 strip | a boundary derived from PIXEL COUNT that **matches no bus**; the bench's real split is **128** |
    | 1007 | Ocean Swell | nothing — animates colour/phase | **already contract-clean; excluded from the redesign** |
  - Severity: **P2** · Evidence: **bench-proven 2026-08-18
    on `.150`, 20 frames posted, readback cited below**
  - `generateRisingTideFrames`, `generatePulseBurstFrames` and `generateGrandRevealFrames`
    (`lumina_custom_effects.dart`) carry their animation **entirely in `start`/`stop`** — the
    "motion" is a boundary sweeping across the strip. `generateOceanSwellFrames` does not and
    is unaffected.
  - **Bench result with the pin's strip path forced** (this is release behaviour):
    - **Geometry SURVIVED** — `seg0[0,128) seg1[128,290) rev=true` identical before and after
      all 20 frames. The pin does its job; nothing crashed; every POST returned OK.
    - **The effect is dead.** Stripped, frames 1–19 are byte-identical:
      `[{id:0,on,col:[0,128,255,0],fx:0},{id:1,on,col:[0,0,0,0],fx:0}]`. Twenty frames render
      one static image.
    - **It ends in a WRONG state.** The final frame omits seg 1 entirely (its
      `clampedPixels < totalPixels` guard goes false), so seg 1 keeps frame 19's **black** and
      stays dark until something else lights it. Half a dark house, persistent.
  - **Verdict: DEGRADES (badly), does not BREAK.** Correctly not a reason to allowlist them —
    an allowlist would restore the animation by restoring the destruction.
  - **Redesign scope (do not allowlist):**
    1. **Prefer a NATIVE WLED effect.** Rising Tide ≈ Percent/Wipe; Pulse Burst ≈
       Ripple/Fireworks. Zero geometry, zero custom frames, and the controller runs it
       locally — which also deletes 20 sequential HTTP POSTs per effect (20 command DOCS over
       the relay, where this is currently unusable regardless of the pin).
    2. **Fall back to per-pixel (`i`)** where no native equivalent exists: `applyPerPixel` /
       `postPixelSpansChunked` (Design Studio Slice 0) paints spans **within fixed segments**
       and states no geometry — the correct primitive for a growing span. Must handle the
       `frz:true` side-effect (a per-pixel write freezes the segment; `psave` captures it →
       poisoned preset fires dark forever — fixed +63, reuse that handling).
    3. Per-segment colour ramps are NOT viable — 2 steps on a 2-channel device is not a tide.
  - **Dead-code removal candidate, found in the same sweep:**
    `lib/services/segment_pattern_generator.dart` has **ZERO importers** across `lib/` and
    `test/`. It emits `start`/`stop` at `:479` and elsewhere, so it is a bounds-stating
    builder that nothing can reach. Not a risk today; delete it rather than carry a fifth
    geometry emitter that no census will remember to check. Verify the zero-importer claim
    again at removal time — that is the whole basis for calling it dead.
  - Files: `lib/features/wled/lumina_custom_effects.dart`,
    `lib/services/segment_pattern_generator.dart` (removal candidate) — client-only.

- [ ] **#100 — client and server derive a config's team slug from DIFFERENT sources, so the
  client can go blind to a config the server still acts on**
  - Status: OPEN (filed 2026-08-18) · Severity: **P2** · Evidence: **verified-by-source +
    production instance (#101)**
  - **Client:** `GameDayAutopilotConfig.fromFirestore(doc.data())` reads
    `data['team_slug'] ?? ''` (`game_day_autopilot_config.dart:358`) — and is handed
    **`doc.data()` only**, never the snapshot, so the doc id is not even available to fall
    back on (`game_day_autopilot_providers.dart:219`).
  - **Server:** `const teamSlug = cfgDoc.id` (`planGameDayFires.ts:425`).
  - When the `team_slug` *field* is missing but the doc id is valid — the `mlb_twins` shape in
    **#101** — the client resolves `''` and the server resolves `mlb_twins`. Every client
    action keyed on the slug (remove, toggle, session cancel) silently fails on `.doc('')`
    while the planner happily keeps planning fires. The customer's UI is blind to a document
    the backend is acting on.
  - **Fix shape:** pass the snapshot (or its id) into `fromFirestore` and prefer the doc id,
    matching the server. The field then becomes a redundant convenience rather than the sole
    source. Cheap, and it removes a whole class of divergence rather than this one instance.
  - Files: `lib/features/autopilot/game_day_autopilot_config.dart:355-358`,
    `lib/features/autopilot/game_day_autopilot_providers.dart:219` (client-only).

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

- [x] **#70 — Every crew fanout command names an EMPTY controllerIp, so no real bridge can
  execute it. Neighborhood Sync has never reached hardware. FIXED + DEPLOYED + HARDWARE-VERIFIED
  2026-08-12.**
  - Status: **CLOSED** — fix `06e36dc`, deployed `--only functions:applySyncPattern` 22:20:40Z,
    verified on hardware 22:27Z (`A converged after ~2s (real bridge)`, TRUE 4/4). The denorm
    branch joins ids to addresses via one `getAll`; an unresolvable target is written
    `status:"failed" error:"no_address"` rather than dispatched at an empty host. A failed join
    does NOT fall through to the subcollection scan — that would command controllers the member
    never named. **Deliverability is ip-OR-webhook**: `executeWledCommand` routes Webhook Mode on
    `webhookUrl` and never reads `controllerIp`, so judging on ip alone would have marked every
    Webhook-Mode member `no_address`. 291 tests / 12 suites (baseline 271 / 11).
  - Severity: **P1 — the feature did not work in production** · Evidence: **hardware-proven**
  - [applySyncPattern.ts:418-425](../functions/src/applySyncPattern.ts#L418): `resolveMemberTargets`
    takes a denormalized branch whenever the member doc carries a `controllerId` **array**:
    ```ts
    if (denormIds.length > 0) {
      return (denormIds as string[]).map((id) => ({ id, ip: "" }));   // ip DROPPED
    }
    ```
    It returns early, so `/users/{uid}/controllers` — which holds the real address — is never
    read. The `ip` is not unknown; it is discarded.
  - Hardware evidence, A's command docs from the 22:03:45Z and 22:04:39Z fanouts:
    ```
    controllerId: "192_168_1_150"   controllerIp: ""
    error: "ERROR: HTTP -1"          status: "failed"
    ```
    The rig never moved. Both bench member docs carry `controllerId` arrays
    (`["192_168_1_150"]`, `["80_f3_da_b3_76_64"]`), so **both** members were affected.
  - **This is not bench-specific.** Any member doc written with the denormalized array — the
    normal shape — produces undeliverable commands. The self/host path is unaffected because it
    resolves IPs from the controllers subcollection directly (`:206-240`).
  - **Why it stayed hidden through three runs:** the harness bridge-sim POSTs to its own stub and
    never reads `controllerIp`, so it reported *delivered* for a command byte-identical to the
    one the real bridge refused. Closed harness-side in `0c5fd92`; assertion 2 now fails on an
    empty IP.
  - **Fix:** the denormalized branch must resolve each id against
    `/users/{memberUid}/controllers/{id}` and use the stored `ip`, falling back to the full
    subcollection read. An id that resolves to no ip must be **skipped and logged**, never
    written as `ip:""` — a command that cannot be delivered should not be queued at all.
  - Prerequisite for the global `sync_fanout` flip. Files:
    `functions/src/applySyncPattern.ts:413-445`. Related **#69**, F-3.

- [x] **#69 — A PAUSED member who initiates a sync gets no command for their OWN house. FIXED + DEPLOYED + HARDWARE-VERIFIED 2026-08-13.**
  - Status: **CLOSED.** Tyler's decision, quoted: *"pause does NOT mute your own broadcast. A
    paused member who initiates receives their own command; pause continues to mute INCOMING
    broadcasts."* Fix `8cb9d3c` at `applySyncPattern.ts:587-608`: `memberUid` is read before the
    skip, which becomes `!isInitiator && isMemberSkipped(...)`. Keyed on **identity**, not on a
    relaxed predicate — `isMemberSkipped` is untouched, so every other member's pause semantics
    are unchanged. That branch was also **silent**; it now logs the member and status, matching
    its sibling. Deployed `--only functions:applySyncPattern`. 322 tests / 14 suites (was 313/13).
  - **Two runs, same rig, same roster:** 2026-08-12 with A paused → `members=1 commands=1
    skipped=1`, A never converged (the exposing configuration). 2026-08-13 with A **still paused**
    → `served=2 skipped=0`, A converged **~2s via the real bridge**, B's stub reflected,
    `retryAfterMs=14883`. **4/4 with a paused initiator.**
  - Bench resting state is deliberately left **`paused`** so every future run exercises the
    exemption — see the ledger note.

- [x] **#71 — `initiateSyncSession` had the same defect as #69. FIXED + DEPLOYED 2026-08-13;
  RIG VERIFICATION BLOCKED (see below).**
  - Status: **CLOSED in code.** Fix `initiatorConsentVerdict` / `memberSkippedForSession` /
    `chooseHost`, deployed `--only functions:initiateSyncSession`. 392 tests / 17 suites.
  - **Precedence: CONSENT > PAUSE.** The exemption is identity-keyed on pause only;
    `participationStatus` is deliberately not an input to the consent verdict, so the
    exemption structurally cannot reach a contract. Pinned by a test.
  - Three distinct refusals, no session created: `consent_missing` (never answered),
    `consent_blocked` (said no to the category), `skip_next_active` (said skip this one).
  - **:234 is NOT a defect and was left alone.** It skips the initiator when building the FCM
    recipient list — suppressing a push to the person who just pressed the button. Exempting
    them there, as the brief asked, would notify the initiator about their own action.
  - **RIG VERIFICATION NOT PERFORMED — preconditions absent, and seeding them is not free.**
    The demo group has **zero `syncEvents`**, and A has **no `syncConsent` doc**. The handler
    validates the event before reaching any #71 code, so neither the paused-initiator case nor
    the consent refusal can be reached today. Seeding a live `syncEvent` is not inert: the
    background worker polls for triggers and is the ONLY caller, so a seeded event could fire a
    real session and fan out to B, driving A's rig unattended. Deferred for a decision rather
    than done quietly.
  - Files: `functions/src/initiateSyncSession.ts`. Related **#69**, **+76** (client half).

- [ ] **#73 — a refused sync initiation is invisible to the user (+76 client half)**
  - Status: OPEN (found 2026-08-13 closing #71) · Severity: **P2** · Evidence:
    verified-by-source
  - `initiateSyncSession`'s only caller is
    [sync_event_background_worker.dart:502-510](../lib/features/neighborhood/services/sync_event_background_worker.dart#L502):
    on 200 it returns `result['sessionId']` — **null** for a `{success:false, reason}` body —
    and on non-200 it `debugPrint`s and returns null. **Either way the refusal is discarded.**
  - So #71's legible refusals are legible to the SERVER LOG and to nobody else. There is no
    foreground caller at all, which also means there is no user present at the moment of
    refusal — the message needs a surface (a notification, or state the Sync screen reads),
    not just a return value.
  - **This is why the server half shipped without the client half rather than instead of it:**
    the server now refuses correctly and says why in the log, which is strictly better than
    silently dropping the initiator. Filing the surface as +76 app work.

  - Status: OPEN (found 2026-08-13 while closing #69) · Severity: **P2** · Evidence:
    verified-by-source
  - [initiateSyncSession.ts:167-171](../functions/src/initiateSyncSession.ts#L167) skips any member
    whose `participationStatus` is `paused`/`optedOut` — with **no exemption for the caller**,
    even though `initiatorUid` is known at `:70` and verified against the token at `:79`.
  - Consequence is worse than #69's: the paused initiator is dropped from `participants`, so at
    `:185-188` they cannot be chosen host either (`creatorUid` if present, else `initiatorUid` if
    present — a paused initiator is in neither), and `:234` skips them again. They start a sync
    session they do not join and may not host.
  - **Not fixed with #69 deliberately.** This path also gates on a per-category `syncConsent`
    doc, so "the initiator always participates" is a stronger claim here than in the fanout —
    it would override an explicit consent opt-out, not just a pause. Tyler's #69 decision reads
    naturally as covering it, but the consent interaction is a product call and should be made
    explicitly rather than inherited.
  - **DECISION RECORDED 2026-08-13 (Tyler):** the initiator exemption extends to PAUSE in
    `initiateSyncSession` — a paused initiator joins the session they started — but it **NEVER
    overrides `syncConsent`**. An opted-out initiator gets a **legible refusal**, not a silent
    re-opt-in: consent is a stated preference and pause is a temporary mute, and quietly
    honouring the second by overriding the first would be the worst of both. Implementation
    scoped separately; this entry stays OPEN until it lands.
  - Files: `functions/src/initiateSyncSession.ts:167-171`, `:185-188`, `:234`. Related **#69**.

- [x] **#69 (original entry) — A PAUSED member who initiates a sync gets no command for their OWN house, and only
  when fanout is enabled**
  - Status: OPEN (found 2026-08-12 on the first successful two-node fanout run) · Severity:
    **P2** · Evidence: verified-by-source + live run
  - [applySyncPattern.ts:174-201](../functions/src/applySyncPattern.ts#L174): the `if
    (fanoutEnabled)` arm **returns**. The host-only path below it — the one that writes the
    initiator's own command — is therefore a *fallback*, not an additional step. With fanout on,
    the initiator's command can come from exactly one place: the fanout loop, iterating the
    roster.
  - That loop skips any member whose `participationStatus` is `paused`/`optedOut`
    ([`isMemberSkipped`, :292](../functions/src/applySyncPattern.ts#L292)) — and it does **not**
    exempt the initiator, because it has no concept of one. So a paused member who presses
    broadcast lights up the whole crew and not their own house.
  - **The behavior is flag-dependent, which is the part that will confuse someone.** With fanout
    OFF the host path never consults `participationStatus`, so the same user action works. Turning
    fanout on silently changes what a paused member's own button does.
  - Observed live: bench group `8b25LBEhS51H65VHKGQ1`, A = `wrQRUUKy…` (initiator) with
    `participationStatus:"paused"`, B = `KOerj0ui…` with `"active"`. Server logged
    `members=1 commands=1 skipped=1`; B converged, A was never written to.
  - **Product decision, not a mechanical fix.** "Paused" plausibly means *the crew does not drive
    my lights* — it does not obviously mean *my own deliberate action does not drive my lights
    either*. Recommend the initiator bypass `isMemberSkipped` for their own uid; whoever decides
    otherwise should record why, because the flag-dependence above will otherwise read as a bug
    forever.
  - Also noted while reading the roster: A is `participationStatus:"paused"` with
    `isParticipating:true`, B is `"active"` with `isParticipating:false`. Both docs carry
    contradictory pairs. `isParticipating` is documented as a not-yet-wired STOP-path gate
    (`:289`), so nothing reads it today — but it will be read eventually, and it currently
    disagrees with the field that governs.
  - Files: `functions/src/applySyncPattern.ts:174-201` (the returning arm), `:292`
    (`isMemberSkipped`), `:517-534` (the loop). Related **F-3**, the scoped `sync_fanout` flag.

- [ ] **#68 — Daylight skip increments a counter but writes NO plan-log row — skipped teams are
  invisible in `gameday_plan_log`**
  - Status: OPEN (recorded 2026-08-12) · Severity: **P2** (observability) · Evidence:
    verified-by-source
  - [planGameDayFires.ts:366-386](../functions/src/planGameDayFires.ts#L366): when
    `isDaylightOnlyGame` is true the loop does `bump(stats.skipped, "daylight_game")` then bare
    `continue`. Every **other** skip in the same loop also pushes a `logRows` row — participation
    does, twelve lines up at `:358-361`. Daylight is the one path that increments and stays
    silent.
  - Consequence: the aggregate `lastSummary.skipped.daylight_game` tells you *three teams were
    skipped* and nothing else — not which teams, which uids, which events, or what sunset was
    computed. `scripts/_check_gameday.js` filters rows by `action`, so a daylight-skipped team
    simply does not appear in any window's output. The count reconciles, which makes the
    invisibility look like health.
  - Same observability class as the disposition mirror and the 2026-08-11 horizon-counter fix
    (`:395-400`, *"every path out of this block must increment something"*) — that fix added the
    missing **counters** and left this path's missing **row**.
  - **Fix:** push `{uid, teamSlug, eventId, action:"skip", reason:"daylight_game"}` alongside the
    bump, carrying the decision inputs — `gameStartMs`, estimated end, computed sunset, lat/lon,
    and the `tzOffsetHours` actually used.
  - **Why the inputs matter, not just the row:** the filter hardcodes `tzOffsetHours: -5`
    ("US Central is the fleet's reality today", `:376-379`), self-documented as accurate only
    outside ±30 min of sunset. So every near-sunset call is a coin flip that **currently leaves
    no trace to audit**. The row is what turns that limitation from invisible into reviewable.
  - Files: `functions/src/planGameDayFires.ts:366-386`,
    `functions/src/gameDayPlanning.ts:433` (`isDaylightOnlyGame`),
    `scripts/_check_gameday.js` (reader — will surface the rows once written). Related **#67**
    (badge needs these rows), **F1**.

- [x] **#67 — A fire NAMES participating segments but never excludes the others. FIXED + DEPLOYED
  + HARDWARE-VERIFIED 2026-08-13.**
  - Status: **CLOSED.** Decisions: *"fires assert the full partition; non-participating segments
    get `{id: N, on: false}` ONLY — look/effect preserved (exclusion = dark for this event; the
    base restore asserts full state after)"* and *"unstated segment state is inherited state,
    and inherited state is a bug"* (third appearance). Fix `adfb49d`,
    deployed `--only functions:applySyncPattern,functions:planGameDayFires`.
  - **Both builders**: `buildFullPartitionSegArray` (Game Day, driven by
    `participating_channels_device_ids` now carried on the `participationForFire` verdict) and
    `partitionBroadcastPayload` (Sync), applied **per target** — each member has their own
    channel count and excluded set. `baseRestorePayload` excluded, verified by reading: it emits
    `{ps:N}` and bench presets 1/2 both assert per-segment state for both segments.
  - **Discriminating run, 2026-08-13.** Both channels pre-lit, seg1 visibly different
    (`fx=57` green/purple). One scoped broadcast, bench participation `[0]`. On the wire:
    `{"seg":[{"fx":88,"pal":5,"col":[[255,0,0],[0,0,255]],"id":0,"on":true},{"id":1,"on":false}]}`.
    Converged ~3s via the real bridge:
    ```
    seg0 on=True   fx=88  pal=5  col0=[255,0,0]
    seg1 on=False  fx=57  sx=180 ix=200 pal=0 col0=[0,255,120,0]
    ```
    Channel 1 **went dark with its look byte-identical to pre-light** — the Twins failure
    inverted, and the preserve-look assertion verified on the wire rather than argued.
  - **#65 unblocked.** #67 was the reason fixing #65 was dangerous: it would have made advisory
    exclusion customer-visible the same day. Exclusion now means dark, so #65 can be fixed on
    its own merits. 338 tests / 15 suites (was 322 / 14).
  - Regression safety: participation == all channels is byte-equivalent to the old builder,
    pinned as a test — which is every live account today, because of #65.

- [x] **#76 — design payloads CLOBBER INSTALLATION GEOMETRY. BUILDERS FIXED 2026-08-14 (`70726ac`);
  the gate that caps severity is still OPEN.**
  - **Builders: DONE.** All seven strip geometry; `custom_design_rev_test` inverted from the
    half-measure ("reversed emits rev:true") to the real contract, plus a sweep over all seven
    geometry fields. Dart 2273/3/0, analyze clean.
  - **STILL OPEN:** the geometry gate (verify geometry -> save -> verify) that makes the
    remaining window non-durable. Until it lands, a `psave` taken while geometry is wrong can
    still bake the error into the base ladder.
  - **Support answer, pre-fix fleet:** a WLED-side direction correction is silently reverted at
    the next base boundary unless the presets are re-saved, because geometry lives INSIDE
    presets (bench-proven). Known-phantom class; cite #76.
  - Status: OPEN (field-reported 2026-08-12, root-caused 2026-08-14) · Severity: **P1 —
    customer-visible, wrong output on correct hardware** · Evidence: field + verified-by-source
    + bench-reproduced
  - **THE RULE (Tyler, complement to #67):** a design payload asserts **DESIGN** fields only —
    `fx`, `col`, `pal`, `sx`, `ix`, `on`, `bri`. **Geometry** — `rev`, `mi`, `start`/`stop`,
    `of`, `grp`/`spc` — is NEVER written by a design path. It belongs to provisioning and
    roofline tooling. #67 said unstated segment state is inherited state; this says the
    complement: **state that isn't yours to state must not be stated.**
  - **Primary offender:** [editable_pattern_model.dart:187-193](../lib/features/wled/editable_pattern_model.dart#L187)
    emits `'rev': direction == PatternDirection.left` and `'mi': direction == centerOut`. Any
    pattern not authored as "left" therefore stamps **`rev:false`**, silently un-reversing a
    correctly-provisioned channel. It also writes `grp`, `spc`, `of`.
  - **Full audit of geometry-writing payload builders:**
    | File | Geometry written |
    |---|---|
    | `wled/editable_pattern_model.dart:187-193` | `grp`, `spc`, `of`, **`rev`**, **`mi`** |
    | `wled/pattern_models.dart:346-348` | `grp`, `spc`, `of` |
    | `design/services/pattern_composer.dart:670-676` | `start`, `stop`, **`rev`** |
    | `design/services/clarification_service.dart:130,995,1006,1024` | `start`, `stop` |
    | `design/models/composed_pattern.dart:110-111` | `start`, `stop` |
    | `autopilot/team_design_catalog.dart:202` | `grp` |
    | `design/design_models.dart:252` | `rev` (echoes the channel's own config — still to go) |
  - **BENCH-PROVEN 2026-08-14, and it changes the fix:** setting `rev:true` on a segment then
    loading a preset **reverts it**. `.150` seg1: `rev=true` after a live write, `rev=false`
    after `{"ps":2}`. **Geometry is stored INSIDE presets.** Two consequences: (a) the clobber
    self-heals at the next base-preset boundary for any account with a floor — Ellie's ran
    backwards for the evening, not forever; (b) **a customer who "fixes it in WLED" without
    re-saving the preset loses the fix at the next boundary**, which is the more damaging
    version and should be in the support answer.
  - **Bench blind spot, and what closing it costs.** Both bench segments run forward, so the rig
    cannot catch this class. Making one segment `rev:true` **permanently** requires re-saving
    the base ladder presets — a `psave` against presets 1/2, which is the operation with the
    frozen-segment capture and ambient-seg history. Live-only reversal is reverted by the first
    preset load. **Escalated rather than done:** the instruction assumed a state write; it is
    actually a base-ladder preset edit.
  - **Fix:** strip geometry from every builder above; pin a test that a `rev:true` segment
    survives a design apply. Related **#67**, **#77**.

- [ ] **#77 — multi-channel continuity: one design renders as two independent runs**
  - Status: OPEN (field-reported 2026-08-12) · Severity: **P2 — quality** · Evidence: field
  - Ellie's two front channels each rendered the design independently: one design, two visual
    runs, a visible seam at the channel boundary. It should read as one face.
  - Long-term answer is the geometry layer (`docs/SYNC_GEOMETRY_LAYER.md`); interim mitigations
    (offset/grouping phasing across channels) are scoped when that is designed, not before —
    a phasing hack chosen now would have to be unpicked by the coordinate system that replaces it.

- [ ] **#80 — home hero flashes the STOCK house over the customer's own photo on any profile-stream
  re-subscription**
  - Status: OPEN (filed 2026-08-15) · Severity: **P3 — cosmetic, but see the principle** · Evidence:
    field-observed by Tyler on build **301 (+77)**, first launch after install, triggered by a Game Day
    enable; **verified-by-source** below · Rides **+78**
  - **Observed:** the home-screen house preview flickered between the stock image and Tyler's own home
    photo momentarily after a Game Day enable rebuilt the home screen. Did NOT replicate after a
    controller + app restart.
  - **The 'first-launch cold cache' reading is incomplete.** A cold cache explains why it was VISIBLE
    that once — a warm asset paints instantly while a cold `NetworkImage` does not — but the stock
    image is not merely winning a race. It is being deliberately assigned to state:

    ```dart
    // wled_dashboard_page.dart:368-376
    final profileLoaded = profileAsync.hasValue;                       // TRUE during a refresh
    final houseImageUrl = profileAsync.maybeWhen(
      data: (u) => u?.housePhotoUrl, orElse: () => null);               // NULL during a refresh
    if (profileLoaded) _updateHeroImage(houseImageUrl, ...);            // -> called with null

    // _updateHeroImage:234-242  — null url is treated as 'no photo exists'
    final provider = (url != null && url.isNotEmpty)
        ? NetworkImage(url)
        : const AssetImage('assets/images/Demohomephoto.jpg');          // STOCK, into state
    ```

    `hasValue` and `maybeWhen(data:)` **disagree** on a Riverpod loading-with-previous-value state:
    `hasValue` is true (there IS a cached profile) but the value is `AsyncLoading`, so `data:` does not
    match and `orElse` returns null. The guard admits the rebuild; the read then reports no photo.
    `_updateHeroImage` cannot tell *"this user has no photo"* from *"the profile is momentarily
    unavailable"* — both arrive as `null` — so it commits the stock asset to `_heroImageProvider`.
  - **The existing guard is bypassed, not absent.** Line 649 (`else if (!profileAsync.isLoading)`) was
    written precisely to stop stock rendering during load — but it lives in the `else` of
    `if (_heroImageProvider != null)` (:647). Once the stock asset has been *assigned*, line 647 wins
    and 649 is never consulted. Somebody already anticipated this failure and defended the wrong layer.
  - **Trigger scope (what a Game Day enable rebuilds):** the whole home screen, not the affected tile.
    `build()` watches `activeUserProfileProvider` at :369 alongside `wledStateProvider`,
    `selectedDeviceIpProvider`, `isRemoteModeProvider` and `isViewingAsCustomerProvider` — every one of
    them rebuilds the entire `Scaffold`, hero card included. And `activeUserProfileProvider`
    ([media_access_providers.dart:56-69](../lib/features/installer/media_access_providers.dart#L56)) is a
    `StreamProvider` that itself watches `viewAsCustomerIdProvider` and `authStateProvider` — so an auth
    or view-as change **re-creates the stream**, dropping it back to loading-with-value and re-entering
    the null branch above. That is the general trigger; Game Day was one instance of it.
  - **Why P3 and not lower:** it is cosmetic and self-corrects within a frame or two. But showing a
    customer a stranger's house on their own home screen reads as *"the app lost my setup"*, and the
    same disagreement between "unknown" and "absent" is the exact defect class as **#78** (fabricated
    geometry) and the **geometry gate** (unreadable ≠ empty). Absent must not render as a value.
  - **Fix direction — hold last-known-good, and distinguish the two nulls:**
    1. `_updateHeroImage` takes an explicit *unknown* case and **returns without touching
       `_heroImageProvider`**, leaving whatever was last resolved on screen.
    2. Call it only from a genuine `AsyncData` (switch on the value, or gate with
       `profileAsync is AsyncData`), never from `hasValue` + `orElse`.
    3. Stock renders only once a loaded profile has **affirmatively** reported no photo — never
       during resolution. Blank/`matteBlack` (:646) is the correct interim, and is already there.
  - **Principle (Tyler, 2026-08-15):** *a fallback must never flash stock over an existing user photo,
    even once.* Rarity is not a fix; it only decides who sees it.
  - **Reproduction note:** expect it on first launch after install/update, if at all — a warm image
    cache hides the swap. Do not treat non-replication as evidence the ordering is sound; the
    source-level branch above is the evidence.
- [ ] **#90 — `daylight_game` is a SECOND silent skip in the planner, and it is the one that
  swallowed the 2026-08-16 Royals game**
  - Status: OPEN (filed 2026-08-17) · Severity: **P2** · Evidence: **verified-by-live-data +
    verified-by-source** · Sibling of **C10**/**#68**
  - [planGameDayFires.ts:498-499](../functions/src/planGameDayFires.ts#L498) bumps
    `stats.skipped.daylight_game` and `continue`s — **no `logRows.push`**, exactly like
    `start_time_passed` before C10. The 2026-08-16 summary reads **`daylight_game: 9`** and names
    not one team.
  - **This is not a malfunction — it is correct behaviour made invisible.** The filter is
    per-config opt-in (`c.skip_day_games === true`) and requires user lat/lon. Live data:

    | account | `skip_day_games` | outcome for `mlb_royals` 08-16 |
    |---|---|---|
    | Tyler `wrQRUUKy…` | **`true`** | **skipped, silently** — no row, no fire, no session |
    | Ellie `5oHhaEaf…` | `false` | `plan_start` `fireAt 2026-08-16T19:37:00Z` |

    First pitch ≈ 20:07Z = **15:07 CDT**. A day game. Tyler asked for day games to be skipped and
    they were. The defect is that **"your team played and we deliberately sat it out" is
    indistinguishable from "nothing happened"** — which is precisely why a scoring game with an
    enabled config read as a celebrations failure.
  - **C10 fixes only `start_time_passed`.** When that branch merges, the same row must be added
    here or the next silent night is this one. Two of the planner's skip reasons write rows and two
    do not; the asymmetry is the bug, not either branch individually.
  - **Fix:** `logRows.push({uid, teamSlug, action:"skip", reason:"daylight_game", fireAt})`,
    batched with C10. Server-side, deploy-after-merge per the +74 rule.
- [ ] **#89 — a design-side animation engine overwrites hardcoded segment BOUNDS and ends by
  swallowing the whole strip into seg0. It is currently caller-less.**
  - Status: OPEN (filed 2026-08-17) · Severity: **P2 — latent** · Evidence: **verified-by-source**
    · Rides **+78**
  - **NOT the cause of the 2026-08-16 grey-out** (that is participation) and **not observed on any
    device**. No `[0,0)` segment has ever been captured. Filed because the shape is a device-
    geometry destroyer sitting one wire away from live.
  - **The shape**, [lumina_custom_effects.dart:45-93](../lib/features/wled/lumina_custom_effects.dart#L45)
    and three siblings (`generatePulseBurstFrames`, `generateGrandRevealFrames`,
    `generateOceanSwellFrames`):

    ```dart
    'seg': [
      {'id': 0, 'start': reverse ? clampedPixels : 0,
                'stop':  reverse ? totalPixels : clampedPixels, …},
      if (clampedPixels < totalPixels && !reverse)
        {'id': 1, 'start': clampedPixels, 'stop': totalPixels, …},
    ]
    ```

    Segment ids are **hardcoded 0/1/2** and their bounds are **animation frames over
    `totalPixels`**, with no reference to the installed buses. On the bench's
    `seg0 [0,128) / seg1 [128,290)` this rewrites both.
  - **The endgame frame is the collapse signature.** At `i == steps`,
    `clampedPixels == totalPixels`, so seg0 becomes **`[0, totalPixels)` = `[0,290)`** and the
    `if` guard drops seg1 from the array entirely. Compare the previously-recorded symptom:
    *"Reboot collapses 2 segments into 1 — **seg0 spans 0–290**; per-channel power has no seg1
    until a preset reloads."* **Identical.** The reverse branch reaches the same state from the
    other side (`clampedPixels` clamps to 0 → `[0, totalPixels)`).
  - **It cannot have caused anything yet: `executeEffect` has NO caller outside its own file.**
    The catalog is referenced (`isCustomEffect`, `getName` in `pattern_explore_screen.dart` and
    `pattern_repository.dart`) but the frame engine is never driven. **Same class as
    `triggerScoreCelebration` (C11)** — hardened-looking, caller-less. Recording it explicitly so
    the next audit does not "verify" it and bank the result, which is the error C11 corrected.
  - **Fix shape — #67's answer on the interactive path** (correct as specified, and it should land
    before anything wires this up):
    1. An apply expresses "channel unused" as **`{id: N, on: false}`** and nothing else.
    2. **Applies NEVER write `start`/`stop`.** Bounds are provisioning's, sourced from the buses.
    3. Segment ids come from the device channel list, never from a literal.
  - **Pinned test (write with the fix):** a single-channel design applied to a two-channel device
    leaves **both segments existing**, the unused one `on:false`, and **bounds unchanged** —
    asserted against `/json/state` bounds, not just segment count, so a full-strip swallow fails
    it as loudly as a deletion.
- [ ] **#88 — the #76 geometry strip missed FOUR more emitters, one of them an interactive design
  path — and `spc` is on bench hardware right now**
  - Status: OPEN (filed 2026-08-17) · Severity: **P2** · Evidence: **verified-by-source +
    verified-on-hardware**
  - **Hardware proof, bench `.150`, capture `20260817T014938Z`:**

    ```
    seg0 [0,128)   len=128  grp=1 spc=2  fx=0   rev=False
    seg1 [128,290) len=162  grp=1 spc=0  fx=83  rev=True
    ```

    `spc=2` with `grp=1` renders **every third pixel** on channel 1 — ~43 of 128 lit. The two
    segments disagree in a geometry-family field, which is the #76 signature.
  - **The strip (`70726ac`) covered seven builders across `design/` and `wled/`. These were not in
    it and still emit `grp`/`spc`:**
    - [colorway_effect_selector.dart:232-233,358](../lib/features/wled/colorway_effect_selector.dart#L232)
      — **interactive**: a look the user applies from the dashboard. This is the one that matters.
    - ~~[neighborhood_providers.dart:414-415](../lib/features/neighborhood/neighborhood_providers.dart#L414)~~
    - ~~[neighborhood_sync_engine.dart:766-767](../lib/features/neighborhood/neighborhood_sync_engine.dart#L766)~~
    - ~~[neighborhood_models.dart:833-834,858-859,1255-1256,1322-1323,1337-1338](../lib/features/neighborhood/neighborhood_models.dart#L833)
      — the sync pattern model round-trips `grp`/`spc` through Firestore, so a neighbour's
      spacing can arrive as your spacing.~~

      **STRUCK 2026-08-17 — NOT A DEFECT.** All three Sync entries are withdrawn, and the
      reason is that this bullet was written while `grp`/`spc` were still classified as
      geometry. Under the decision of record below they are DESIGN, and *"share this look"*
      sharing its banding is the feature — a candy-cane broadcast that arrived solid would be
      the bug. Tyler, 2026-08-17: **keep the round-trip.**

      The bullet's own worry ("a neighbour's spacing can arrive as *your* spacing") is
      correct and is now the intent. Its unstated second half — that a sender with no
      opinion would leave the receiver's stale spacing in place — **was already impossible,
      verified by reading rather than assumed:** `SyncCommand`
      ([:725,759](../lib/features/neighborhood/neighborhood_models.dart#L725)) and
      `SyncPatternAssignment` ([:1207,1223](../lib/features/neighborhood/neighborhood_models.dart#L1207))
      declare `grp`/`spc` as non-nullable `int` defaulting to **1 / 0**; the payload
      extractor ([:1240-1256](../lib/features/neighborhood/neighborhood_models.dart#L1240))
      seeds those defaults and only overwrites them when the source seg carries a value;
      both serializers write them unconditionally and both parsers default `?? 1` / `?? 0`;
      and both emitters write them on every payload. **A Sync payload therefore always
      carries `grp`/`spc` — the sender's if they had one, `1`/`0` if not.** No code change
      was required to satisfy the decision.

      `colorway_effect_selector` above stays in scope and is fixed: it is an interactive
      *local* apply, not a broadcast.
  - **This is the BUG-GD-PICKER-1 pattern again** — the sibling a "seven builders, all listed" sweep
    missed. Two sweeps in a row have now under-counted their own family. The lesson is not "look
    harder": it is that **an emitter census must be a grep of the FIELD NAMES across `lib/`, not a
    walk of the builders you already know about.** #76's own list was assembled the second way.
  - **~~Open question for Tyler, not assumed~~ — ANSWERED 2026-08-17. `grp`/`spc` are DESIGN.**
    `rev`/`mi`/`of` are unambiguously installation geometry. `grp`/`spc` were arguable — a
    candy-cane look may legitimately own its spacing. But **#76 stripped them from the seven**,
    so the codebase applied two different rules to the same two fields depending on which screen
    you came from. **The split was the defect, not either half.** Resolved toward design:
    grouping is how a colourway distributes its colours, and spacing is part of the look.

    **And the consequence, which is the half that actually changed code:** once they are design,
    omission stops being neutral. Under #67 — *unstated design state is inherited design state,
    and inherited state is a bug* — a design with no opinion now **asserts `grp:1`/`spc:0`**
    rather than staying silent, or it renders through whatever the previous look left behind.
    Landed `721e26e`: at the apply boundary (`normalizeWledPayload`, trigger widened from
    "has `fx`" to "states a design at all") and at the builders for correctness at rest, since
    `psave` and Firestore blobs do not all cross that boundary. `of` explicitly did **not** move
    — it stayed geometry, and the chokepoint stopped asserting it in `25b8531`.
  - **Not the cause of the 2026-08-16 grey-out** — that is participation (see the #77-era
    diagnosis). Found while capturing for it.
- [ ] **#83 — score celebrations do NOT assert the #67 full partition: they take the self-apply path,
  which never partitions**
  - Status: OPEN (filed 2026-08-15) · Severity: **P2** · Evidence: **verified-by-source** · Answers the
    2026-08-14 rider on **#79** (audit `onScoreAlertEvent` against the #67/#76 contracts)
  - **Scorecard for the real celebration path** (`gameDayWorker.onScoreAlertEvent`,
    [game_day_autopilot_background_worker.dart:151](../lib/features/autopilot/game_day_autopilot_background_worker.dart#L151)):

    | contract | verdict |
    |---|---|
    | `participating_channels` (#29) | **RESPECTED** — `expandForChannels(..., config.participatingChannelIds)`; null passes through, `[]` opts out via empty `seg` and `_applyToControllers` skip-applies |
    | **#76 geometry** (design fields only) | **COMPLIANT** — the flash emits `fx/sx/ix/pal/col` and nothing else; `applyChannelFilter` is called with the default `channels: []`, so it strips `start`/`stop` from the template and adds none. WLED keeps the install-time ranges |
    | **#67 full partition** | **NOT ASSERTED — predates the contract** |

  - **Why the partition is missed.** `_applyToControllers` POSTs `applySyncPattern` with
    `groupId: ''` (:562). `partitionBroadcastPayload` is called **only inside the fanout loop**
    ([applySyncPattern.ts:770](../functions/src/applySyncPattern.ts#L770)); the self-apply path
    (:247-268) JSON-stringifies the payload as received and enqueues one command per controller.
    So a celebration names the participating segments only and says nothing about the excluded ones.
  - **Why it has not yet been visible, and why that is the fragile part.** `applyChannelFilter`
    already emits segs for participating ids only, and the **fire** that started the show DID
    partition — the 08-13 Twins fire is on the wire as `seg:[{id:0,on:true,…},{id:1,on:false}]`. So
    an excluded channel is normally already dark when the flash lands, and the flash correctly does
    not wake it. **The celebration is inheriting correctness from the fire rather than asserting its
    own.** Any path that reaches a celebration without a partitioning fire first — a manual
    "Light It Up Now", a base-pattern re-apply, a controller reboot mid-show — leaves the excluded
    channel showing whatever it was showing, and the flash confirms nothing. This is exactly the
    assumption #67 was written to delete.
  - **Fix direction:** partition at the same chokepoint the fanout uses. Either lift
    `partitionBroadcastPayload` above the `groupId` branch in `applySyncPattern` so **every** target
    is partitioned regardless of path, or have the worker emit a full-partition payload client-side.
    Server-side is preferred — one place, and it covers future callers that forget. Batches with the
    **#79** implementation session; see `docs/SPORTS_ALERTS_RESTRUCTURE_PLAN.md`.
  - **Also confirmed this pass (already covered by #79's in-flight fix, recorded so it is not
    re-derived):** `onScoreAlertEvent` has **four bare `return`s** (:152 disposed, :156 no slug,
    :159 no active session, :166 no config / celebrations off) and **not one of them logs**. The only
    `debugPrint` is in the `catch`. The outer poller gate is the same shape: when `active.isEmpty`
    but Game Day work exists, `sports_background_service.dart:188` skips the whole polling block in
    silence. **Fires or nothing, with no legible middle** — the mirror lesson again.
- [ ] **#87 — INFRA: no read-only Codemagic API token, so every build's identity chain stalls on a
  console trip**
  - **RENUMBERED #79 → #87 (2026-08-15).** `feat/gameday-unified-monitoring` filed its own #79
    (celebrations have never fired) on 2026-08-14 — earlier, and referenced from that branch's own
    text. The branch merges CLEAN into main (`git merge-tree`, exit 0): the only shared file is this
    one and the two entries sit in different regions, so **git would have silently produced a
    document with two #79s.** A clean textual merge is not a clean semantic merge. Mine moved
    because I own it and nothing else references it; the branch was left untouched — editing
    another window's in-flight branch is the hazard, not the fix.
  - Status: OPEN (filed 2026-08-15) · Severity: **P2 — process, not product** · Evidence: three
    consecutive occurrences
  - **The same read has blocked +75, +76 and +77.** In each case everything git-side and
    artifact-side verified cleanly and the chain still could not close, because one fact lives
    only in Codemagic: **which build number the `build-NN` tag produced, what triggered it, and
    which commit SHA it checked out.**
  - It is not a nuisance — it is the check that catches the failure it exists for. On 2026-08-11
    TestFlight served a stale **288** while **291** was the real build and a hardware run was
    attributed to the wrong artifact. On +76 the trigger read is what proved **297 was the tag
    build and 298 a manual duplicate**, correcting my own inference that the numbering gap
    weakened confidence — it did the opposite.
  - **Ask: a READ-ONLY token.**
    - Scope: list builds; read build metadata — number, trigger (tag vs branch push vs manual),
      commit SHA, status, workflow.
    - **Explicitly NOT: trigger, cancel, or configure builds.** A verification credential that
      can start a build is a credential that can start a build by accident, and the whole point
      of #62's tag-deliberate pipeline is that builds are a deliberate human act.
  - **Storage: the `functions/.env` convention** — gitignored, and therefore subject to the
    **worktree-copy rule**. Worktrees do NOT inherit gitignored files; that is what silently
    broke an earlier release build until `google-services.json`, `key.properties` and the
    keystore were copied across by hand. Any tooling that reads this token from a worktree must
    copy it in the same way, or fail loudly rather than fall back to "unverified".
  - **Payoff:** the identity-chain step becomes a window-side read instead of a Tyler-side console
    trip, and the verdict stops being "I cannot tell, please go look". The distribution gate keeps
    its evidence and loses its stall.
  - **Until it exists**, the honest form of the chain report is unchanged: verify everything
    git-side and artifact-side, then name the two Codemagic fields as an explicit GAP rather than
    inferring them from build numbers. Numbering inference has already been wrong once in both
    directions.

- [ ] **#78 — join FABRICATES geometry: every member gets 300 px and 15.0 m**
  - Status: OPEN (2026-08-14) · Severity: **P2** · Evidence: verified-by-source
  - **Live write path is the server:** [joinNeighborhood.ts:359-360](../functions/src/joinNeighborhood.ts#L359)
    writes `ledCount: 300, rooflineMeters: 15.0` for **every** joining member. 15.0 m = **49.2 ft**,
    the figure seen in the UI; 300 is the per-channel pixel cap reused as a default.
  - Client mirrors the same defaults at
    [neighborhood_models.dart:341-342](../lib/features/neighborhood/neighborhood_models.dart#L341)
    and `:361-362` (the `fromFirestore` fallback), so a member doc missing the fields still reads
    as 300/15.0 rather than as unknown.
  - **Neither number is measured.** They are placeholders that look like data — the failure mode
    is that nothing ever reports "unknown", so no consumer can tell a real 300-pixel home from a
    default. Fixed properly by D2 (join reads real geometry from healer facts); until then the
    honest interim is to write **null** and let consumers handle unknown.

- [ ] **#75 — host-only and crew fanout share the source string `sync_fanout`, so the log cannot
  tell them apart**
  - Status: OPEN (recorded 2026-08-14) · Severity: **P3** (diagnosability) · Evidence:
    verified-by-source + a live misreading
  - [applySyncPattern.ts:274](../functions/src/applySyncPattern.ts#L274) and the fanout writer
    both default to `source || "sync_fanout"`. The host-only self-apply path and the crew fanout
    therefore stamp **the same string**, and the ONLY discriminator is which user's queue the
    command landed in.
  - **It has already cost a misreading.** On 2026-08-14, four commands stamped `sync_fanout`
    appeared in Tyler's queue after an evening sync with Ellie. They read as a crew fanout; they
    were host-only self-apply, every one targeting his own controller. Ellie's queue had zero
    commands with that source, all time. Nothing was wrong — but proving it took a second query
    that the source field should have made unnecessary.
  - **Fix (one line each):** the host-only path defaults to `"self_apply"`, the fanout writer to
    `"crew_fanout"`. Callers passing an explicit `source` are unaffected.
  - **Do not rewrite history when fixing.** Existing docs carry `sync_fanout` on both paths;
    any reader of the corpus must keep using the target queue for anything before the fix.
  - Files: `functions/src/applySyncPattern.ts:274` (host-only), `:562` (fanout doc builder).

- [ ] **#72 — WATCH: a crew member's `participationStatus` changed with no authoring commit**
  - Status: OPEN (watch item, recorded 2026-08-13) · Severity: **P3 until it recurs** · Evidence:
    two timestamps and an absence
  - `neighborhoods/8b25LBEhS51H65VHKGQ1/members/wrQRUUKyXyc0deyuu0ORS6wsovO2`
    was set **`active` on 2026-08-12 ~21:5x Z** (deliberately, for the §4 4/4 run) and read back
    **`paused` on 2026-08-13 ~14:4x Z**, before any write in that session.
  - No commit in `main` between those points touches roster data, and no session recorded the
    change. Candidates, none confirmed: the app itself (a pause toggle in the Sync UI), a
    leave/rejoin cycle re-seeding the member doc (`joinNeighborhood.ts:366` writes
    `participationStatus: "active"`, so a rejoin would set active, not paused), another Claude
    window, or a manual console edit.
  - **Why it is worth a number rather than a shrug:** `participationStatus` gates who receives a
    crew broadcast. A value that changes without an author is a value no test can rely on, and
    it silently changed the meaning of a bench run twice in two days.
  - **What would close it:** an audit trail on member-doc writes, or one reproduction with a
    known actor. Until then, read the field at the START of any run that depends on it — do not
    assume the value the last session left.

- [x] **#67 (original entry) — A fire NAMES participating segments but never excludes the others, so participation is advisory**
  - Status: OPEN (found 2026-08-12 on the first real start fire) · Product decision,
    not a code bug
  - Observed on the bench Twins fire, 17:10:00Z. Participation resolved `[0]`, the
    plan row said `channels:[0]`, and the dispatched payload carried exactly one
    segment:
    `{"on":true,"bri":200,"seg":[{"id":0,"on":true,"fx":52,...}]}`.
    **Both channels lit.** Planner and dispatcher were correct end to end.
  - Mechanism: root `"on":true` powers the master, which lights every segment whose
    own `on` is true. A `seg` array naming only `id:0` leaves segment 1 **untouched**
    — not off. So excluding a channel currently prevents it from *changing*, not
    from *lighting*.
  - **The decision**: should a Game Day fire assert `on:false` on non-participating
    segments? Doing so makes participation mean what a customer will assume it
    means. Not doing so means the exclusion is advisory and the customer's patio
    lights anyway — in whatever look it already had.
  - This is the START-side twin of the S4 "what does a fire actually send" question.
    Whatever is decided should apply to both fires and to the base restore.
  - **Currently unobservable in production** because of **#65**: no account can
    produce a non-participating channel. The bench can only show it because of the
    `is_primary:false` segment written for §7.2d Leg B. Fixing #65 without deciding
    #67 would make this customer-visible on the same day.
  - Unresolved side note, recorded rather than guessed: seg 1 came up
    **byte-identical** to seg 0 (same fx/sx/ix/pal/colours). Pre-existing state
    alone does not explain that — it points at WLED propagating segment properties
    beyond the named id, or seg 1 having been created as a copy. Not settled from
    outside the firmware; seg 1 did not exist at 13:2x and no reboot occurred.
  - Files: `functions/src/planGameDayFires.ts` (`buildParticipatingSegArray` call
    site), `functions/src/gameDayPlanning.ts` (`baseRestorePayload`). Related
    **#65**, S4.

- [ ] **#65 — No code path can create a non-primary roofline segment, so participation always resolves to ALL channels**
  - Status: OPEN (recorded 2026-08-12) · Evidence: exhaustive grep of every
    `RooflineSegment(` construction site
  - Every real creation site — `roofline_setup_wizard.dart:97`,
    `roofline_capture_logic.dart:105/118/131/233`,
    `roofline_config_providers.dart:441`, `roofline_configuration.dart:453` —
    omits `isPrimary`, taking the constructor default **`true`**. No UI, wizard or
    importer emits `isPrimary: false`.
  - Consequence: in `resolveParticipatingChannels`, `primaryChannels == tracedChannels`
    always, so `primaries ∪ untraced` == **every device channel**, for every account.
    The documented "traced but NOT primary → EXCLUDED" branch is **unreachable in
    production**, and so is the `explicit` branch (no picker — see
    `audit/S3B_CHANNELS.md` §4). Participation is currently a value that is always
    "all channels".
  - **Two consequences, opposite signs.** It LOWERS the risk of the `write_jobs`
    flip — no channel can be wrongly excluded when the answer is always "all". It
    also means the roofline-await guard (the superset hazard, +73) protects a path
    no production account can currently exercise, and **no hardware test can
    discriminate it** until a non-primary segment exists somewhere.
  - Blocks §7.2d Leg B by app: the bench segment has to be written directly to
    Firestore because the app cannot produce one.
  - Decide: ship a way to mark a segment secondary (the exclusion feature this
    machinery exists for), or retire the branch. Do not leave it half-built —
    dead policy that looks live is what `audit/S3B_CHANNELS.md` §4 already flagged
    for the sibling field.
  - Files: `lib/models/roofline_segment.dart:559` (the default),
    `lib/features/neighborhood/services/channel_participation_resolver.dart`,
    every creation site above.

- [ ] **#63 — `deviceHardwareConfigProvider` caches null permanently and collapses four causes into one**
  - Status: OPEN (recorded 2026-08-12, not fixed) · Evidence: **§7.2d on +72, build 291**
  - `wled_providers.dart:274-284` returns `null` when `repo == null` and `null` from
    its `catch`, then **caches** it. So no-repo / unreachable / parse-failed /
    no-buses are one indistinguishable value, and `await`ing `.future` later returns
    the completed stale null — **an await on an already-completed future waits for
    nothing.**
  - Proof: `participation_publish_disposition = "SKIPPED(bus list resolved empty —
    shape unknown)"` at `2026-08-12T04:19:08.171Z`, the *same instant* the healer's
    own `/json/cfg` read succeeded and returned three timer rows. Same endpoint, same
    moment, two answers.
  - **Third instance of the null-vs-unknown class this week** (after `fetchPresets`
    tri-state `6a37186` and the base-boundary null-vs-empty discipline). *The class
    is the bug*, not the individual sites.
  - Healer no longer depends on it (+73 sources buses from its own cfg via
    `hardwareConfigFromCfg`), so this is now latent rather than active — **audit the
    provider's OTHER consumers when picked up**; they still take a cached null as
    "no buses".
  - Files: `lib/features/wled/wled_providers.dart:274-284` and every `ref.watch`er.
    Cross-ref **#62** / **P2-15** — build-identity-adjacent observability debt.

- [ ] **#64 — Lease integration test fails in the 90 minutes before local midnight**
  - Status: OPEN (recorded 2026-08-12) · Evidence: reproduced, and reproduced at
    pre-change HEAD, so it is NOT caused by the +73 work
  - `calendar_entry_lease_manager_integration_test.dart:55-70` builds an entry with
    `dateKey: todayDateKey()` but `onTime = now + 30 min` / `offTime = now + 90 min`
    formatted as bare `HH:MM`. After ~22:30 local those wrap past midnight while the
    dateKey stays *today*, so the entry reads as "today at 00:15-01:15" — ~22 h in the
    past — and every assertion returns `LeaseOutcome.alreadyExpired`.
  - **Empirically confirmed**: 5 red at 23:45 local; the SAME five green at 23:59 with
    no code change, once now+90 stopped wrapping past midnight. Deterministic, not flaky.
  - Fix: roll `dateKey` forward with the wrap, or inject a fixed clock. The suite
    should not have a time-of-day-dependent result.
  - Files: `test/features/schedule/calendar_entry_lease_manager_integration_test.dart`.

- [ ] **#62 — Codemagic auto-submits every green `main` build to TestFlight**
  - Status: OPEN (recorded 2026-08-11, not acted on) · Evidence: `codemagic.yaml:131`
  - `submit_to_testflight: true` with a push trigger on `main`. Harmless when `main`
    moved once a day; `main` now moves several times a night, so every docs commit
    ships a TestFlight build. Two builds tonight (`680abc6`, `a0cde1e`) carried +72
    code under a +71 telemetry stamp and auto-submitted with no ledger row able to
    identify them — see the +72 VOID note in `docs/BUILD_LEDGER.md`.
  - Options: manual submit; or trigger on **tag** rather than push, which also makes
    the ledger's SHA join key the thing that creates the build instead of a race
    against the next commit.
  - Evaluate AFTER §7.2d — gating it now would block the verification build.
  - Files: `codemagic.yaml`. Related: **P2-15** (build-number override — same
    build-identity problem from the other end).

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
  - (Was `#TD-2` in BUG_BACKLOG.)

- [ ] **P2-26 — iOS "Detect Home Network" SSID signing lockdown (ex-#61)**
  - Status: OPEN (lockdown shipped `021dcc2`, loop-broken build + on-device GREEN owed) · Evidence: reported
  - Junk team-id-suffixed App ID `6MWGH4KKC4` was recreated every build by two engines
    (fetch-signing-files prefix match + `signingStyle: automatic`). Fixed via
    `--strict-match-identifier` + manual export pinning `com.nexgenled.command` → `Lumina
    AppStore 2`. Verify: next build shows exactly ONE bundle id / ONE profile, no
    "Creating new Profile"; on device Detect Home Network = GREEN; THEN delete junk App ID.
  - Files: `codemagic.yaml`, `ios/ExportOptions.plist`, `lib/services/connectivity_service.dart`
    (instrumentation only).

- [ ] **P2-27 — Game Day team add is single-select only (ex-#64)**
  - Status: OPEN · Evidence: reported (Ellie E2)
  - One team at a time; needs multi-select in one pass.
  - Files: `_TeamPickerSheet` in `game_day_screen.dart` (+ sibling pickers).

- [ ] **P2-28 — Calendar can't show Game Day + regular schedule for a date (ex-#65)**
  - Status: OPEN · Evidence: reported (Ellie E4) — feature gap
  - No way to tap a date and see both autopilot entries and regular schedules. Connects to the
    parked Game Day phase-machine work.
  - Files: calendar/schedule day view (`my_schedule_page.dart`, Game Day calendar surfaces).

- [ ] **P2-29 — Orphan UID `BTAmiOGW…` + bridge `D4E9F4FA8E78` (ex-#67)**
  - Status: OPEN (parked, not actively harmful) · Evidence: reported
  - Third orphan UID; bridge paired to a deleted UID, status `paired`, not caught by the
    current hardcoded rule. Closed automatically by P2-30 if that lands.
  - Files: `bridge_registry` data; `firestore.rules`.

- [ ] **P2-30 — Generalize orphan-bridge rule to existence check (ex-#68)**
  - Status: OPEN · Evidence: verified-by-source (rule still hardcoded — confirmed 2026-07-22)
  - `isNotBlockedDeletedUid()` still lists only `xBnFxkN6`/`ASeUR5n`. Replace with a
    `pairedUid` existence check (Firestore `exists()` per `bridge_registry` write), closing ALL
    orphans incl. P2-29 without list maintenance; then remove the hardcoded entries.
  - Files: `firestore.rules` (`isNotBlockedDeletedUid`, lines ~668-673).

- [ ] **P2-31 — Pre-wipe orphan scan in `clear_account_state.js` (ex-#69)**
  - Status: OPEN · Evidence: reported — procedural
  - Before a user wipe, query `bridge_registry` `pairedUid` values, check each against Auth,
    surface/handle orphans BEFORE deleting.
  - Files: `scripts/clear_account_state.js`.

- [ ] **P2-32 — Roofline trace zoom / magnifier loupe (ex-#70)**
  - Status: OPEN · Evidence: reported — polish
  - Point-placement accuracy during roofline tracing; magnifier-loupe first, normalized 0–1
    coords cooperate.
  - Files: roofline tracing widget.

- [ ] **P2-33 — connectivity_service Crashlytics non-fatal for null SSID (ex-#71)**
  - Status: OPEN · Evidence: reported
  - Log a non-fatal when SSID read returns null so future occurrences are visible without Xcode.
  - Files: `lib/services/connectivity_service.dart`.

- [ ] **P2-34 — Automate Firestore rules tests (ex-#72)**
  - Status: OPEN · Evidence: reported
  - Grant the service account `firebaserules.rulesets.test` (for `scripts/_test_rules_block.js`)
    OR stand up the Firestore emulator + `@firebase/rules-unit-testing`. Currently manual via
    Console Playground.
  - Files: `scripts/_test_rules_block.js`, CI rules-test config.

- [ ] **P2-35 — On-device verify channel-2 participation reconciler (ex-#73)**
  - Status: OPEN (committed `cc62c39` + unit-tested, hardware verify owed) · Evidence: reported
  - Open dashboard with a deliberately-stale participation cache → channels self-correct
    (Ellie's channel-2 greyed-out bug).
  - Files: channel participation reconciler (`isParticipationCacheStale()` + foreground reconciler).

- [ ] **P2-36 — CloudRelayRepository wire-level test coverage (ex-#79)**
  - Status: OPEN (deferred from #77) · Evidence: reported
  - 4 bypass sites fixed; wire tests cover only the 2 WledService sites. Add direct
    `setState`/`savePreset` wire assertions (needs `fake_cloud_firestore` + Firebase init scaffold).
  - Files: `test/…/cloud_relay_repository*`, `lib/features/wled/cloud_relay_repository.dart`.

- [ ] **P2-37 — Lost-save finish A3: EditablePattern→LibraryNode adapter (ex-#85)**
  - Status: OPEN (W2 resolved; A3 unwired — `patternsStreamProvider`/`isSavedPattern` have zero
    lib call sites, confirmed 2026-07-22) · Evidence: reported
  - Adjustment-panel "Save As Custom Pattern" writes `/favorites/` but doesn't surface in My
    Designs. W2 removed the dead `/patterns/` write + relabeled the editor button "SAVE TO
    DEVICE". Finish A3: `EditablePattern → LibraryNode` adapter (`pattern_` prefix,
    `isSavedPattern` flag), wire `patternsStreamProvider` into the 3 injection sites, or
    consolidate the `/favorites/` writer onto `saveCurrentAsDesignProvider` (`/designs/`).
  - Files: `edit_pattern_screen.dart`, `patternCategoriesProvider`, `childNodes`,
    `libraryNodeByIdProvider`, `pattern_theme_selection.dart`, `saveCurrentAsDesignProvider`.

- [ ] **P2-38 — Migrate schedules off the user-doc array field (ex-#TD-1)**
  - Status: OPEN (plan only) · Evidence: reported — tech debt, HIGH before ~100 active users
  - Move array field → `/users/{uid}/schedules/{scheduleId}` subcollection. Also fixes the live
    whole-array clobber race (non-transactional remove/update, blind `saveSchedules` overwrite).
    Plan: `docs/audits/SCHEDULES_SUBCOLLECTION_MIGRATION_PLAN_2026-06.md`. Ordering:
    rules → backfill → dual-write.
  - Files: `schedule_providers.dart`, `user_model.dart`, `firestore.rules`, all schedule R/W;
    flag `schedules_subcollection_feature_flag.dart`.

- [ ] **P2-45 — Controller-native sync/realtime config is UNMANAGED (fleet-drift risk) + DDP/Zone scaffolding untested**
  - Status: OPEN · Evidence: verified-by-source + verified-by-bench (2026-07-24)
  - Neighborhood Sync does NOT use controller-native sync — it broadcasts via Firestore and each
    member self-applies over HTTP `applyJson` (`neighborhood_sync_engine.dart:625-734`). So
    `if.sync.*` / `if.live` / `udpn` are never touched by neighborhood code. Install disables native
    UDP (`wled_config_pusher.dart:231` writes `udpn:{send:false,recv:false}`); the ONLY code that
    ENABLES `udpn`/`ddp` is the SEPARATE Site/Zone DDP feature
    (`DDPSyncController.applyZoneSync` [site_providers.dart:109], `WledService.configureSyncSender/Receiver`
    [wled_service.dart:788-821], `DdpService` RawDatagramSocket:4048 [ddp_service.dart:20-63, has a
    `DDP(sim)` simulate branch]), reachable ONLY from Site settings [settings_page.dart:215] and
    UNTESTED (no DDP-transport test exists). Bench 192.168.1.150 live: `if.sync.send.en:false`,
    `if.sync.recv` flags on (bri/col/fx/pal), `if.live.en:true` (realtime IN on, port 5568),
    ports 21324/65506 (WLED defaults) — none of this is app-asserted, so it's whatever each
    controller happens to carry (drift risk if any future path relies on it). WLED UDP-notifier
    sync + E1.31 are not used by either feature.
  - Decision: either (a) formally OWN a leader/member controller-sync policy (assert `if.sync`/
    `udpn`/`if.live` per role on connect) if native sync is ever put on the Neighborhood path, or
    (b) document that Neighborhood Sync is Firestore-only and treat the DDP/Zone feature as a
    separate, test-owed surface. Today there is NO leader election (creator=admin, `isParticipating`
    =per-member runtime gate) — every member self-applies.
  - Files: `lib/features/site/site_providers.dart`, `lib/features/wled/ddp_service.dart`,
    `lib/features/wled/wled_service.dart` (configureSync*), `lib/services/wled_config_pusher.dart`.

- [ ] **P2-46 — Remove vestigial Sports Alerts settings surface (orphaned pre-Game-Day UI)**
  - Status: OPEN · Evidence: verified-by-source (audit 2026-07-24) · **Execute AFTER P0-3 lands — not now**
  - Sports Alerts (System → Settings) is the superseded predecessor of Game Day score celebrations.
    Its toggle reads/writes a SharedPreferences flag (`sports_alert_configs`, `ScoreAlertConfig.isEnabled`)
    whose ONLY runtime reader is the **kill-switched** background service
    (`kSportsBackgroundServiceEnabled=false` [sports_background_service.dart:29], "was already inert —
    updateControllerIps never wired up"). The LIVE celebration path derives teams from
    `game_day_autopilot` ∩ per-team `scoreCelebrationEnabled` and explicitly ignores this flag
    ([foreground_celebration_providers.dart:98-105]; header :5-7 "NOT the dead direct-IP path"). It
    does not share state with My Teams (Firestore `game_day_autopilot` + profile `sports_teams`) — the
    only bridge is one-way and unrelated to the toggle ([live_scoring_prompt.dart:94-104]). This is the
    remove-vs-wire "(a) dead UI" verdict.
  - **DELETE set:** `lib/features/sports_alerts/ui/sports_alerts_screen.dart`, `.../ui/team_picker_screen.dart`,
    `.../ui/zone_assignment_screen.dart`, `.../providers/sports_alert_providers.dart`,
    `.../providers/sports_alert_notifier.dart`, `_SportsAlertsCard` + route in
    `lib/features/site/settings_page.dart` (:1002-1007), `.../services/sports_background_service.dart`
    + its `lib/services/autopilot_scheduler.dart:480` `startSportsService()` call, and the
    `lib/features/game_day/live_scoring_prompt.dart:94-104` prefs write.
  - **MUST-KEEP (reused by the LIVE foreground path — deleting breaks working celebrations):**
    `lib/features/sports_alerts/models/score_alert_config.dart` (`ScoreAlertConfig`),
    `.../services/score_monitor_service.dart`, `.../services/foreground_celebration_coordinator.dart`
    (incl. `CelebrationTeam.toAlertConfig()` :67), `.../services/foreground_celebration_providers.dart`.
  - **Coordinate with P2-17** (`_controllerIps` / `alert_trigger_service` — same dead pipeline).
  - **(b) alternative — NOT this item:** if app-closed score celebrations are ever wanted, that is a
    SEPARATE feature (re-enable the service + repoint it at `game_day_autopilot` instead of the prefs
    store + wire `controllerIps` + Play FGS declaration), NOT a revival of this toggle.

- [ ] **P2-48 — `functions/lib/` is TRACKED despite `.gitignore` listing it (inert rule → chronic dirty tree)**
  - Status: OPEN (tech debt — dedicated task, NOT bundled into a feature fix) · Evidence:
    verified-by-repo-state (2026-07-27)
  - `.gitignore:225` lists `functions/lib/`, but all **81 files** under it are committed and tracked
    in HEAD (`applySyncPattern`, `staffAuth`, `createCustomerAccount`, …). **A `.gitignore` rule has
    no effect on already-tracked files** — the entry was added after the files were committed, so git
    keeps tracking them and the rule is inert. Confirmed: `git check-ignore -v` on
    `functions/lib/applySyncPattern.{js,d.ts,js.map}` matches **no rule**, while
    `git ls-tree --name-only HEAD functions/lib/` lists all 81.
  - **Symptom:** chronic dirty-tree churn. Any `tsc`/`npm run build` rewrites the compiled output,
    which git then reports as modified. Because the files are tracked, the modifications **follow
    every branch switch** — observed 2026-07-27 carrying `applySyncPattern.*` from
    `feat/dealer-team-empty-state` → `main` → `fix/neighborhood-join-membership` untouched. It also
    means a routine `git add -A` can silently commit stale build output.
  - **Doc drift:** the SYNC-1 commit (`76324ce`) states *"functions/lib/ is gitignored build output —
    deploy/test:unit rebuild it; compiled output intentionally not committed."* That is **false** for
    this repo as it stands — it IS committed. Fix the claim or fix the repo; right now they disagree.
  - **FIX (separate dedicated task — do NOT fold into an unrelated branch):** decide which model is
    intended, then make the repo match.
    - (a) **Generated** — `git rm --cached -r functions/lib` + commit; the existing `.gitignore:225`
      rule then takes effect and the churn stops permanently.
    - (b) **Build-committed** — remove `functions/lib/` from `.gitignore` so the tracked state is
      honest, and accept that compiled output is reviewed in diffs.
  - **BLOCKER on (a) — must confirm BEFORE untracking:** that every deploy path rebuilds `lib/`
    from source. Check `functions/package.json` (`predeploy`/`build` scripts), `firebase.json`
    (`functions.predeploy` hooks), and any CI/Codemagic step that runs `firebase deploy --only
    functions`. If any path ships `lib/` as-is from the checkout, untracking it **breaks deploys**.
    Removing 81 files from the repo is not reversible-by-accident — verify first.

- [ ] **P2-49 — Sunrise-off toggle arms only the ACTIVE controller (no fan-out to a user's others)**
  - Status: OPEN (known limitation — ledger only, NOT a regression) · Evidence: verified-by-code
    (2026-07-29, `f8ce483` on `feat/sunrise-off-toggle`)
  - The global "Turn lights off at sunrise daily" toggle arms/disarms via
    `SunriseOffService._write`, which resolves a single repo from `wledRepositoryProvider` and writes
    the reserved sunrise slot to **that controller only**. This is the **same scope as
    `ScheduleSyncService.syncAll`** (which also reads one `wledRepositoryProvider`), so it is
    consistent with existing per-controller behavior — **not a regression**, and not a defect
    introduced by the sunrise-off feature.
  - **Fine for residential**, the shipping case: a single controller, or a linked set fronted by one
    active repo.
  - **KNOWN LIMITATION for multi-controller / commercial multi-zone properties:** toggling on arms
    only the active controller. **The user's other controllers stay ON at sunrise**, with no UI
    signal that the toggle only covered one of them — the settings switch reads as account-wide.
  - **FIX (only if commercial multi-zone adoption happens — do NOT pre-build):** extend arm/disarm to
    fan out across all of the user's controllers, then aggregate the per-controller results so a
    partial success is reported as partial (the existing `SunriseOffWriteResult` is single-valued and
    would otherwise report the first/last controller's outcome as if it were the whole account).
    Natural source for the controller set is `activeAreaControllerIpsProvider`
    (`lib/features/site/site_providers.dart`).
  - **Coordinate with schedule sync.** `syncAll` has the identical single-repo scope, so a fan-out
    that covers only the sunrise-off would leave the two paths inconsistent (sunrise-off on every
    controller, schedules on one). Either fan out both or neither — this is one decision, not two.

---

## P3 — debt (no launch relevance)

> Added 2026-07-30 from the pre-submission audit (`audit/LAUNCH_PLAN.md`, consolidating
> `audit/FEATURE_STATUS_MATRIX.md` + `audit/RELEASE_READINESS.md`). None of these block
> submission; none are customer-visible.

- [ ] **P3-60 — `kStaffAuthTelemetryAppVersion` is a hand-bumped constant (drift risk)**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30)
  - `lib/features/installer/staff_auth_telemetry.dart` stamps a hardcoded app version onto
    every fallback row because the project has no `package_info_plus` (adding a plugin to a
    release candidate was judged riskier than a constant). A stale value defeats the S-5
    metric, whose entire job is telling adopted builds from stale ones.
  - Fix: add `package_info_plus` post-submission and read the real version, or add the bump
    to the release checklist next to the `versionCode` bump.

- [ ] **P3-61 — Aborting the wizard after customer-account creation is unrecoverable in-app**
  - Status: OPEN · Evidence: source-proven (2026-07-30)
  - If the installer taps **Stop** on the new staff-auth retry dialog (or any post-`:822`
    failure aborts), the customer's Firebase Auth account exists but `/users/{userId}` was
    never written. Re-running with the same email hits `email-already-in-use`, whose recovery
    path queries `/users` by `dealer_code` + `email`, finds nothing, and dead-ends on
    "No existing customer matches this email under your dealer code."
  - Pre-existing (any post-creation abort does this); the retry dialog just makes the branch
    reachable on purpose. Mitigated by the pre-flight refresh making Stop very unlikely, and
    the dialog copy tells the installer not to restart with the same email.
  - Fix: recover by uid instead of by query when the account exists but the user doc does not.

- [ ] **P3-62 — Stale line-number cross-references around the installer auth path**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30)
  - `firestore.rules:405` cites `installer_providers.dart:192` for the `signInWithCustomToken`
    call; it is at `:291`. `staff_pin_screen.dart:75-78` cites wizard lines `506`/`512` for
    `createUserWithEmailAndPassword` / `signInAnonymously`; they are at `:822` and inside
    `_fallBackToAnonymous`. The `staff_pin_screen` note also now misdescribes the wizard,
    which re-mints rather than falling back.
  - Also: `installer_setup_wizard.dart`'s `installerAnonymousUid` local is a misnomer — post-PIN
    it holds the **staff** uid (`staff_installer_<pin>`), not an anonymous one. That name is
    what made the "does the staff uid equal `fromUid`?" question look open. Rename it.

- [ ] **P3-50 — `buildTimerEntry` still carries the known-wrong solar 24/25 encoding (dead, but loaded)**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30, `393af46`)
  - `lib/features/schedule/cfg_payload_builder.dart:100-108` emits `hour: 24` (sunrise) /
    `hour: 25` (sunset) — the encoding proven wrong for WLED (24 = hourly, 25 = invalid).
  - **Currently unreachable**: `buildCfgPayload` skips every solar label before it can be
    called with one (`:155-165`), and the real solar path is
    `ScheduleSyncService.buildSolarTimerEntry` (`hour: 255` marker, `schedule_sync.dart:414-428`).
    So this is dead code, not a live defect.
  - **Why it is still worth closing:** it is a correct-*looking* helper in a shared builder. The
    next author who needs a solar timer will reasonably call it and silently reintroduce the bug.
  - Fix: delete the solar branch, or `assert(false)` it. ~0.5h.

- [ ] **P3-51 — 108 silent empty catch blocks in `lib/`**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30) — `grep -rn "catch (_) {}" lib/`
  - Most are defensible best-effort paths. But the class hid a real data-loss bug: the pixel-walk
    save swallows its exception at `map_roofline_step.dart:417` and the caller discards the
    `false` return (`:426-428`), so a failed Firestore write advances the wizard silently.
    That specific instance is tracked separately as a P1 in the launch plan (T-5).
  - Not worth a blanket sweep. Worth a rule: **catches on WRITE paths must surface or log.**
  - Fix: lint rule + targeted audit of write paths. ~4h.

- [ ] **P3-52 — `CLAUDE.md` carries three claims that contradict the code**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30)
  - `kSimulationMode` documented as hardcoded `true`; it is `false` (`app_providers.dart:17`).
  - HTTP timeouts documented as an outstanding 5s KNOWN ISSUE requiring a 15s fix; that work shipped.
  - "No automated tests currently exist" — there are ~170 files under `test/` plus emulator
    suites in `functions/test/`.
  - Also stale in project memory: the schedules array→subcollection migration is recorded as
    "PLAN ONLY"; it is fully implemented (client lazy migrator + server backfill + bidirectional
    dual-write). All four misled the pre-submission audit and will mislead the next session.
  - Fix: correct the four claims. ~0.5h.

- [ ] **P3-53 — `functions/lib` (compiled output) is committed to VCS**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30) — 78 tracked files, no `functions/.gitignore`
  - Structural cause of the deploy-parity drift tracked in the launch plan (T-4): `src` and `lib`
    diverge silently, and a bare `firebase deploy --only functions` from repo root ships whichever
    `lib` is on disk without building. `npm run deploy` chains the build; the bare form does not.
  - Fix: gitignore `functions/lib`, rely on the predeploy build hook. ~1h. Removes the failure
    mode entirely rather than re-fixing the artifact each time.

- [ ] **P3-54 — `minifyEnabled = false` in the release buildType → 65 MB AAB**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30) — `android/app/build.gradle:60-61`
  - Both minification and resource shrinking are disabled for **release**. Well under Play's
    limit and harmless; enabling R8 would cut download size materially.
  - Needs a keep-rules pass against the reflection-using plugins (Firebase, flutter_blue_plus,
    speech_to_text) — which is why it is debt and not a quick win. ~2h + regression testing.

- [ ] **P3-55 — Orphaned-route safety rests on the ABSENCE of deep-link config — needs a regression guard**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30, Window B `audit/COMPLIANCE_AND_SECURITY.md`
    §2.6(b) Q2d; corrects an earlier Window A claim)
  - Seven routes are registered in `app_router.dart` with **zero** navigation from anywhere in
    `lib/` (`/commercial/onboarding`, `/settings/current-colors`, `/dealer/payouts`,
    `/autopilot/first-week`, `/media`, `/system-deactivated`, `/installer/zone-setup`). Several
    host stub controls that report false success (`CommercialScheduleScreen.dart:1819,1850,2064`).
  - **They are currently unreachable — but only by accident of configuration, not by design:**
    - `deep_link_service.dart:59-90` is a closed allow-list (`power`, `brightness`, `scene`, …);
      an unmatched first path segment returns `null` and never reaches GoRouter.
    - `flutter_deeplinking_enabled` is **absent** from `AndroidManifest.xml` and
      `FlutterDeepLinkingEnabled` is **absent** from `Info.plist`, so Flutter's automatic
      URI→route mechanism is off.
    - `autoVerify="true"` at `AndroidManifest.xml:107` is inert — it applies to `http`/`https`
      App Links only, not to the custom `lumina` scheme.
  - **The hazard:** compliance row 1.1 PASSes *because of these absences*. Adding
    `flutter_deeplinking_enabled` in any future release — a one-line, innocuous-looking change
    someone will eventually make for App Links or marketing attribution — **re-opens the entire
    orphaned-route class at once**, making every stub screen externally addressable.
  - Guard (pick one, cheapest first): a widget/unit test asserting neither flag is present in the
    built manifest/plist; **or** land the route-guard class fix (deny-by-default for unknown
    prefixes, `route_guards.dart:54,294-296`, ~4h) so reachability stops depending on the absence
    of a config key. The class fix is the durable answer — the test only detects the regression.
  - Related: the `/commercial` deletion (~1h) removes the worst instance regardless.

- [ ] **P3-56 — ON-preset definitions exist in TWO places (drift risk from the master-power fix)**
  - Status: OPEN · Evidence: verified-by-code (2026-07-30, master-power fix)
  - `ScheduleSyncService.kOnPresetSpecs` (slot → name+bri) was added so the on-connect defaults
    healer can repair presets 1/3/4/5 without re-deriving them. The four `psaveIfChanged` calls
    in `syncAll` still carry their literals inline (`{'on': true, 'bri': 200, 'ib': true}` etc.).
  - **Left deliberately.** Rewriting the shipping sync path to consume the map is a refactor, and
    that fix was scoped to the master-power defect on a release candidate. Zero behavioural risk
    was the priority.
  - **The risk:** change a brightness in one place and the healer and the sync will write
    different definitions, so every connect and every sync will fight each other — each seeing
    the other's value as "unsatisfied" and re-saving. A psave APPLIES live, so that presents as
    the strip flashing on every connect.
  - Fix: have the four calls consume `kOnPresetSpecs` + `onPresetHealState`. ~0.5h. Add a unit
    test asserting the sync's emitted state equals `onPresetHealState(spec.bri)` for each slot.

- [ ] **P3-57 — `schedule_sync_idempotent_test.dart` fixtures encode the pre-fix preset shape**
  - Status: OPEN · Evidence: verified-by-test (2026-07-30) — 2 failures after the master-power fix
  - Presets 1/3/4/5 are fixtured as `{'n': 'NGL On', 'seg': [{'on': true}]}` — name + segment-on,
    **no root `on`** — which is exactly the broken on-device shape. Preset 2's fixture carries
    `'on': false` with the comment *"Already healed…so the OFF-preset self-heal skips it"*, so the
    author had the right model for 2 and not for 1/3/4/5.
  - Two tests now fail **because the fix works**:
    - *"Option A: pattern preset ALWAYS re-saved…; system presets skip"* — `Expected: [10]`,
      `Actual: [1, 3, 4, 5, 10]`
    - *"preset 2 named NGL Off but left ON is repaired"* — `Expected: [2]`, `Actual: [1,2,3,4,5]`
  - **NOT rewritten** — reported rather than silently changed, since a fixture that encodes broken
    behaviour is exactly what made the original defect survive review. Deciding what these tests
    *should* assert is a judgement call, not a mechanical edit.
  - Fix: add root `'on': true` to the 1/3/4/5 fixtures (making them healthy, so the skip
    expectation becomes correct) **and** add a sibling test with the no-root-`on` shape asserting
    that those slots ARE re-saved. ~1h.

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

- [x] **M-21 — `bench/` CLI harness** — DONE (inaugural all-green 2026-07-24, 21/21)
  - Status: DONE · Evidence: bench-proven (`dart run bench/bin/bench.dart all` → 21/21, exit 0,
    192.168.1.150, 2026-07-24)
  - Pure-Dart CLI (`bench/bin/bench.dart`) with 9 subcommands: probe (+layout-drift vs
    `known_layout.json`, P1-42), snapshot, cfg-truth (en int→1/bool→0, permanent regression
    guard), preset-verify, sync-sim, fire-test, channel-power (P1-43 four shapes), restore, all.
    REUSES the app's REAL builders via extraction to Flutter-free files (re-exported, app
    unchanged): `buildCfgPayload`, `timersInsLanded`/`isRealEnabledTimer` (→ `timer_landing.dart`,
    `cfg_payload_builder.dart`), `buildChannelPowerPayload` (→ `channel_power_payload.dart`),
    `deviceChannelsFromConfig`/`DeviceChannel` (→ `device_channel.dart`),
    `WledLedBus`/`WledHardwareConfig` (→ `wled_hardware_config.dart`). Discipline as code:
    Content-Type + Content-Length on every POST (chunked is rejected by WLED — caught on the
    inaugural run), capture/restore brackets, VERIFIED-BY-BENCH evidence, exit 0/1. Assertion/
    diff logic unit-tested (`test/bench/bench_core_test.dart`, 19 tests). Extraction proven
    behavior-preserving: full suite unchanged at 1746 pass / 2 pre-existing fail, 0 new lint.
  - Files: `bench/` (bin/bench.dart, src/bench_core.dart, src/wled_client.dart, config.json,
    known_layout.json, README.md) + the 5 extracted pure lib files above.

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
  → P2 batch (incl. migrated #61/#63/#64/#65/#67-#73/#77-#79/#85/#TD-1)
  → features (F-18, F-19, F-20)
```

The migrated ex-backlog items are non-schedule surfaces (iOS signing, Game Day, orphan
bridges, design apply/label, tech debt). Slot them by priority into the batches above; the
schedule stack still leads because it gates "sell with certainty."

---

## Resolved / closed (migrated from BUG_BACKLOG.md — kept, not dropped)

- [x] **R-39 — kEffectNames off-by-one (ex-#82)** — DONE `c8ed60a`
  - Hand-maintained `kEffectNames` had drifted from firmware order ~id 37 ("Halloween Eyes" vs
    "Solid Pattern" at 83). Map deleted; 5 call sites switched to `WledEffectsCatalog.getName`;
    parity test locks 12 indices. Verified-by-source: `kEffectNames` now absent from lib
    (only in `test/features/wled/effects_catalog_device_parity_test.dart`). Display-only; no
    data migration. Cold-start eyeball verify was owed but the fix is complete.

- [x] **R-40 — Design Studio Tier 2 save/apply stubs (ex-#66)** — DONE (implemented in current source; SHA not pinned)
  - `_handleSaveDesign` → `saveComposedDesignProvider` (real `/designs/` write) and
    `_handleApplyToLights` → `applyCustomDesignToLights` (real per-pixel apply) are both fully
    wired in `lib/features/design/screens/ai_design_studio_screen.dart` — no longer toast-only.

- [x] **R-41 — CRASH on Save Design: global error sink (ex-#84)** — DONE (crash-death mechanism closed)
  - `main.dart` now installs `FlutterError.onError` + `PlatformDispatcher.onError` (candidate #1,
    the missing global sink → uncaught-async SIGABRT). Caveat: the exact save-path root cause
    was never isolated from a stack trace; if a save silently *fails* (vs crashes) reopen. The
    separate nested-array (`col:[[…]]`) crash class tracked in project memory is distinct.

> Also folded: ex-#74 (Bug B `e556251` formal verify) → subsumed by **P1-24**. ex-#TD-2 →
> **P2-17**. ex-#TD-3 → **P2-16**.

---

## Historical context (from BUG_BACKLOG.md — reference only, not tracked)

**Closed 2026-05-27 → 05-28:** orphan-bridge cleanup (3 UIDs wiped, rule deployed);
`/patterns/` + `/designs/` Firestore rules added (were default-deny); Design Studio nav-bar
occlusion / clarification no-op / async error handling; Game Day team-picker occlusion;
Neighborhood Sync side-by-side buttons (`b77b5ca`); channel-2 reconciler landed (`cc62c39`,
verify → P2-35); Bug B preview parity confirmed live (`e556251`, verify → P1-24); iOS SSID
stale profile root-caused (→ P2-26).

**Recurring theme — Writer ≠ Reader:** features write user content to their own
collection/location while the display surface reads elsewhere (Patterns, Designs, Teams;
also participation-cache and orphan-bridge). A "unified user-content read layer" audit may
eventually beat fixing each surface individually. Strategic, not immediate.

**Recurring gotchas:** bottom-of-screen unreachable = glass-dock occlusion, fix with
`navBarTotalHeight(context)`; rules dry-run printing "enabling API / creating database" =
wrong-project alarm, confirm `firebase use` first; "looks fixed / tests pass" ≠ verified,
check runtime/on-device; map all writers before fixing a reader.
