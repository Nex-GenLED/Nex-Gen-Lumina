# Controller Wedge — Pacing Fix (a)/(c)/(d) + Game Day Burst Sources

**Branch:** `fix/sync-pacing`, from `main` @ `c14368d`. Standalone reliability
fix — not based on, and not merged with, `feat/design-card`,
`feat/schedule-v3-model`, `audit/sports-alerts-sync`, or
`feat/game-day-celebrations`.

**Firmware impact: none.** No ESP32/WLED change. This alters only the app's
request cadence and connection handling toward the controller.

Input: [audit/SYNC_PACING_FIX_STATUS.md](SYNC_PACING_FIX_STATUS.md).

| | |
|---|---|
| Commits | `187dd9e` (Part C), `f3a2dba` (Parts A/B/D1) |
| Gate | `flutter analyze` **0 errors, 381 issues** — identical to main's baseline, no new warnings |
| Suite | **2483 passed, 4 skipped, 0 failed** |
| Bench verification | **NOT RUN** — requires Tyler present. See §3. |

---

## 1. Pre-check findings

### P1 — close() coverage: **14 of 15 sites leak on their error path**

The pattern at nearly every site:

```dart
try {
  final client = HttpClient()..connectionTimeout = ...;
  final req  = await client.getUrl(...);            // can throw
  final res  = await req.close().timeout(...);      // can throw — TIMEOUT
  final body = await res.transform(...).join();     // can throw
  client.close(force: true);                        // ONLY on success
  ...
} catch (e) { debugPrint(...); }                    // NO close
```

`grep -c '} finally {'` over `wled_service.dart` returns **1**. Fifteen
`client.close(` calls exist, **none inside a catch**. The single exception is
`_fetchCfgRaw` (`:420-435` on main), which had a proper `finally` and was
therefore the only non-leaking site.

**So (d) was not a tidiness consolidation — it also closed a leak**, and one
that is self-amplifying in precisely the wedge scenario: the dominant cause of
a throw here is a request timeout, so as the controller degrades, more requests
time out, more clients and sockets are held, and pressure rises.

### P2 — why `force: true`: **no stated reason found; no keep-alive history**

- **No comment** anywhere near any of the 15 closes explains `force: true`.
- `git log -S "close(force: true)"` returns 8 commits, none of which changes
  close behaviour deliberately — they carry it along while doing other work.
- `git log -S "persistentConnection"` and a repo-wide grep for
  keep-alive/keepalive return **nothing relevant**. There is no history of
  keep-alive being tried and reverted.

**What P2 *did* find is load-bearing, and adjacent:** the `HttpClient` +
explicit `contentLength` pattern exists to avoid **chunked transfer encoding**,
which ESP32 WLED builds reject — returning **200 while silently not persisting
the body** (`7ad46ac`, Item #67; same class fixed for `_postConfig` in Item
#61). That rationale governs Content-Length, **not** the forced close and
**not** per-call-site instantiation.

### P3 — `_syncInFlight` under the calendar loop: **1 sync normally, N only under latency**

Traced chain: `applyEntries` loops entries → per entry
`await leaseManager.handleEntryCreated(entry)` → the lease manager's schedule
updater → `schedulesProvider.update(item)` → **`await` Firestore write** →
`_triggerWledSync()`, which **cancels and restarts** an 800ms timer
(`schedule_providers.dart:158-165`).

Because each mutation *restarts* the timer, the loop collapses to **exactly one
`syncAll`** whenever consecutive entries are processed less than 800ms apart —
the common case. **This is timing-dependent, and I am marking it as such:** each
iteration awaits a Firestore round-trip, so if any single entry exceeds 800ms
the timer fires mid-loop and a sync starts while later writes are still coming.

Two consequences follow, and the second is the one that matters:

1. Up to N syncs are possible under slow network, not just 1.
2. A second sync arriving while the first is verifying is **dropped** by
   `_syncInFlight` (returns `verifying()`), **not queued** — so under exactly
   those conditions the *tail* of the loop can go unpushed.

**This materially reframes D1.** Its value is not "N → 1" in the common case
(the debounce already did that); it is making the outcome **deterministic**
instead of a latency race, and removing the drop.

### P4 — firmware pin confirmed

Read-only `GET /json/info` against `192.168.1.150`. No state changed, no sync,
fire, or Game Day action triggered.

```
ver       : 0.15.1        ← pin holds
vid       : 2507300
arch      : esp32
uptime    : 10338 s  (≈ 2h52m)
freeheap  : 129172
resetReason: not exposed by this build
```

Uptime is consistent with the post-wedge power cycle. `resetReason` is **not
exposed** in this firmware's `/json/info`, which is worth knowing now rather
than at step 3 of the bench protocol, since that protocol asks for it on the
way back up.

---

## 2. What shipped

### Part C — shared clients + leak fix (`187dd9e`)

A process-wide cache keyed by `connectionTimeout` replaces 15 per-call-site
instantiations. **Keyed, not collapsed to one**, because the sites legitimately
differ (5s ×1, 10s ×3, 15s ×11) and flattening them would change how long a
dead host is waited on. Three long-lived clients replace fifteen short-lived
ones; no per-request close is needed, which is what removes the 14 leaks.

**Wire behaviour deliberately unchanged:** every request sets
`persistentConnection = false`, so the connection still closes after its
response exactly as the force-close did. Per Part C's instruction, this is the
"reuse the object, keep the close-behaviour" branch — chosen because P2 found
**no** evidence keep-alive was ever validated against this firmware, and
introducing it silently against a frozen 0.15.1 controller is exactly the kind
of change that could wedge a customer in the field. Enabling keep-alive remains
a real further win and is left as a separate, bench-verifiable step.

Explicit Content-Length is untouched (P2's load-bearing finding).

### Part A — pacing (`f3a2dba`)

`kControllerWritePace = 300ms`, injectable via
`ScheduleSyncService({paceDelay})` so tests need not sleep. Applied immediately
before `savePreset`, **after** every skip/refuse branch has returned — so it is
a gap *between writes that actually go out*, never a per-iteration tax. A
converged controller writes nothing and pays nothing.

### Part B — poller suspension (`f3a2dba`)

`WledNotifier.pausePolling()` / `resumePolling()`, backed by a **depth counter**
(`_pollPauseDepth`) rather than a bool — the populate pauses around its whole
loop while a `syncAll` inside it pauses again, and a bool would let the inner
resume restart polling mid-burst. `_scheduleNextPoll` returns early while
paused, and `_runPollTick` re-checks (a tick already queued when the pause
landed must not fire).

Wired at two places, both with `finally`:
- `syncAll` — wrapped as a thin public method delegating to `_syncAllInner`,
  because the inner method has a dozen `return finish(...)` exits and a wrapper
  covers all of them including a throw, without touching existing control flow.
- `_doPopulateCalendars` — same wrapper shape, around the **whole** loop.

`resumePolling` clamps at zero and never throws: it runs in `finally` blocks,
and raising there would mask the original failure.

### Part D1 — deterministic batching (`f3a2dba`)

`beginSyncBatch()` / `endSyncBatch()` on `SchedulesNotifier`. While batched,
`_triggerWledSync()` records that a sync is *owed* instead of arming the timer;
the outermost close arms exactly one. Called from `_doPopulateCalendars`
alongside the poller pause, with the **batch closed before the poller resumes**
so the owed sync is armed while the quiet period still holds.

### Part D2 — reported, not changed (as scoped)

The design-apply live preview keeps its **150ms** debounce
(`colorway_effect_selector.dart:566`). **Part B's pause does NOT cover the
preview burst** — that burst is user-driven and happens *before* any sync
begins, so there is no sync or populate in scope to have paused around it. The
pause covers from the populate onward. Stated explicitly because the prompt
asked whether it covers the adjacency, and the honest answer is: it covers the
second half of it, not the first.

### Tests (18 new, all passing)

- `test/features/schedule/sync_pacing_test.dart` (7) — real writes are paced
  (asserted on absolute wall-clock, since the sleeps are real); **a
  steady-state sync with zero real writes is not slowed even with a 5s pace**;
  the default sits in the 250-500ms band; pause/resume nests; an inner resume
  does not restart polling; unbalanced resume tolerated; resume after sync.
- `test/features/wled/wled_http_client_reuse_test.dart` (6) — same timeout
  returns the *identical* instance; distinct timeouts get their own; 50 rounds
  of 3 timeouts still yields 3 clients.
- `test/features/schedule/sync_batch_test.dart` (5) — nesting, unbalanced end
  tolerated, closing a batch that owed nothing invents no sync.

---

## 3. Bench verification — **NOT RUN**

The protocol explicitly requires Tyler present and forbids unsupervised
execution, and it deliberately re-triggers a known wedge. **I did not run any
part of it**, and nothing here is claimed as bench-confirmed.

Only P4's read-only `GET /json/info` touched `.150`. No sync, fire, design
apply, or Game Day action was issued.

Two things to settle before step 3, both surfaced by this pass:

- **`resetReason` is not exposed** by this firmware build's `/json/info` (P4).
  Step 3 asks to read it on the way back up; it will not be there. An
  alternative (serial log, or `/json/info` `uptime` reset to near-zero as the
  cycle marker) should be agreed first.
- **Step 3's "no prior Game Day config" condition is load-bearing** and now has
  a precise reason. Per P3 and Part A, a *converged* controller skips every
  psave via the idempotence gate — so a repeat attempt on an already-populated
  controller issues few or no flash writes and is **unlikely to reproduce**.
  The "before" case genuinely needs a first-write state.

---

## 4. Deferred, and why

1. **Keep-alive / connection reuse on the wire.** The clients are shared, but
   `persistentConnection = false` preserves today's close-after-response
   behaviour. P2 found no evidence keep-alive was ever tried against 0.15.1.
   Enabling it is a further win and a genuine risk; it belongs behind a bench
   test, not inside a fix meant to *reduce* wedge risk.
2. **The 150ms preview debounce (D2).** Out of scope by instruction; it is a UX
   tradeoff and carries no flash-write risk.
3. **The `_syncInFlight` drop-instead-of-queue behaviour.** P3 found that an
   overlapping sync is dropped, which can strand the tail of a batch. D1 makes
   this unreachable *from the populate path*, but the underlying
   drop-not-queue semantics remain for other callers. Not touched — it is a
   correctness change beyond this fix's remit.
4. **`WledService` instance churn.** Callers still construct
   `WledService('http://$ip')` ad-hoc all over the app. The client cache is
   process-wide precisely so that churn no longer costs connections, but the
   object churn itself was left alone.

---

## 5. What I would have had to fabricate, and didn't

- **Whether `force: true` was protecting against something.** P2 searched
  history and comments and found nothing. I did not invent a rationale, and I
  did not assume its absence meant keep-alive is safe either — I preserved the
  close-after-response behaviour and said why.
- **That the calendar loop fires N syncs.** The prompt's D1 framing implied it.
  P3 shows the 800ms debounce already collapses it in the common case, and that
  N-syncs is a slow-Firestore edge. I reported the correction rather than
  shipping D1 under a premise I had disproven.
- **Any bench result.** No before/after was captured. Nothing in this report
  claims the fix is confirmed against hardware — only that the code-level gaps
  in (a)/(c)/(d) were real and are now closed.
- **`resetReason`.** The probe showed the field absent; I reported that rather
  than substituting `uptime` and presenting it as the reset reason.
- **A wedge mechanism.** Socket exhaustion and flash-commit stall are both
  plausible and both addressed; I did not assert which one actually caused the
  observed hang, because this pass cannot discriminate them.
