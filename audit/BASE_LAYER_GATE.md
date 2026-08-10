# BASE-LAYER GATE — the `write_jobs` blocker

**Status:** IMPLEMENTED 2026-08-10. Not deployed, not built.
**Repo:** `main` @ `08ae0b6` + this change · **Gates:** flipping
`config/gameday_planner.write_jobs`

---

## 1. Why this gates `write_jobs`

Game Day fires a design and relies on an END SIGNAL to put the house back. When
that signal fails — bridge offline, command expired, ESPN never reports final, a
Functions outage — the house is returned by the **base layer** at its next
boundary. An account with no everyday schedule **has no next boundary**, so the
design runs until a human intervenes.

**Six of ten Game-Day-enabled accounts are in that state:**

| account | teams | base layer |
|---|---|---|
| Tim Kelly | nfl_chiefs | **none visible** |
| Chris Paschall | nfl_chiefs | **none visible** |
| Jim Dyer | mlb_royals | **none visible** |
| Darrin Nicholas | fifa_mexico | **none visible** |
| **Taps On Main** | mlb_royals, nfl_chiefs | **none visible — COMMERCIAL** |
| Demo Home | mlb_royals, nfl_chiefs | **none visible** |
| Ellie Cochran | 8 teams | present |
| Steve Stegall | nfl_chiefs | present |
| Chris Cipollone | mlb_royals | present |
| Trend Setter | mlb_royals | present |

`Taps On Main` is the worst instance — a bar left in team colours overnight, and
Marc has already had game-day lighting fail once when leases were silently
unarmable.

**This is independent of ESPN semantics.** It gates `write_jobs` regardless of
how the shadow read goes.

## 2. What was built

`lib/features/autopilot/base_layer_gate.dart` — a pure evaluation, a
session-once marker, and a fail-open prompt. Wired into
`game_day_screen.dart::_toggleAutopilot`, **on enable only**.

### It prompts, it does not refuse

`maybeWarnNoBaseLayer` returns **`true` (proceed) in every case except one**: an
explicit "Not now". Base layer present → proceed. Already prompted this session
→ proceed. No context → proceed. **Any exception → proceed**, logged via
`debugPrint`. Dismissing the dialog by tapping outside → proceed.

Refusing would have regressed the four accounts already running Game Day with a
base layer, and blocked the six from a feature they already use.

### It does not auto-create anything

No base layer is written, ever. Accounts waking to lights they never scheduled
is the same mistake backfilling `enabled:true` would have been. The dialog
offers a **path** to set one ("Set a schedule" → `AppRoutes.schedule`) and
nothing more.

### The copy says what actually happens

> "You don't have an everyday schedule saved. If something goes wrong at the end
> of a game — your bridge is offline, or the score never arrives — there's
> nothing scheduled to turn the lights off afterwards, so they may stay on until
> you turn them off yourself."

Deliberately **"may stay on"**, not "will". And **"you don't have one saved"**,
not "your house has no schedule" — see §3.

## 3. THE CAVEAT, CARRIED IN THE CODE

The census counts **Firestore intent, not device reality**. A controller can
hold base timer rows with no Firestore schedules — the bench rig `.150` is
exactly that. So six is an **upper bound**, and it is **not knowable off-LAN**.

This is enforced structurally rather than by comment:

```dart
enum BaseLayerStatus { present, absentInFirestore }
```

`absentInFirestore` — **not `absent`**. The name makes every call site read as
"we can't see one", not "there isn't one". **A test pins the enum members**, so
renaming it to `absent` fails the suite. That is deliberate: the caveat is the
kind that gets optimised away in a tidy-up six months from now.

## 4. Failure mode — explicitly not a guard

If the prompt cannot be shown for **any** reason, the enable **proceeds**.

```dart
} catch (e) {
  debugPrint('BaseLayerGate: prompt failed ($e) — proceeding with enable');
  return true;
}
```

A broken prompt must not silently block a customer from enabling Game Day. The
`debugPrint` means a silent regression is still visible in a debug run rather
than being invisible everywhere.

## 5. Where it fires — and the accounts already enabled

**Implemented:** enable time, once per account per app session.

**NOT implemented — recommendation for the six already-on accounts.** They will
never cross the enable path again, so the prompt as built never reaches them.
Options considered:

| surface | verdict |
|---|---|
| Modal on Game Day screen open | **Rejected** — nagging. A modal they did not trigger, for a state they did not just change. |
| **Passive inline card on the Game Day screen**, shown while the condition holds | **RECOMMENDED** — visible, dismissible by fixing the cause, no interruption |
| Push notification | Rejected — disproportionate |
| Nothing, rely on outreach | Viable for six accounts; Tyler can call them |

Recommending the inline card rather than building it, because it is a
visual-design decision on a screen I have not been asked to change. **For six
known accounts, a phone call is faster than a release.**

Session-scoped, not persisted: a dismissal must not hide this forever, and the
condition is worth re-stating in a later session if it still holds.

## 6. Verification

| check | result |
|---|---|
| Account WITH a base layer sees no new friction | ✅ returns early on `present`, and does **not** consume the session slot — losing the schedule later still prompts |
| Account WITHOUT one sees the prompt and can proceed | ✅ "Enable anyway" and dismissal both proceed |
| Does not fire twice per account per session | ✅ `markPromptedOnce` |
| Different accounts tracked independently | ✅ |
| No persisted suppression | ✅ new session prompts again |
| Disabled / no-repeat-day schedules do not count as a floor | ✅ they never fire |
| **Full suite** | ✅ **2036 passed, 3 skipped, 0 failed** |

## 7. P1-8 CLOSED in the same pass

`cloud_ai_processor_normalize_test.dart` asserted `timeLabel == 'Sunset'`. The
**test** was stale, not the code: `b6ca2f1` deliberately removed that default
because it fabricated `hour:25` timers that never fire. A garbage time value
must normalise to empty and be refused downstream, not silently become a real
boundary. **The assertion was corrected; the code was not touched.**

It had been red in every suite run for weeks and cost real investigation time as
a false suspect during the Block E diagnosis. **The suite is now fully green for
the first time in weeks** — which is the actual value: a permanently red test is
a credible suspect for every future mystery.

## 8. THE GATE, RESTATED

> **Do not flip `config/gameday_planner.write_jobs` until this ships to devices.**

It is committed but **not built and not deployed**. Until a build carrying it
reaches customers, the six accounts remain unwarned, and a `write_jobs` flip
would put a real design on a real house with no floor under it.
