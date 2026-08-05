# SOLAR UI NOT UN-GATING — which gate is actually holding it closed

**Date:** 2026-08-05 · **Build:** 277 / +64 · **Status:** ✅ **RESOLVED — rule deployed 2026-08-05T19:27Z.**

> ## RESOLUTION
>
> The missing `match /config/solar_scheduling` block was added and deployed in ruleset
> **`93c99c50-0b3d-4a72-b76f-eb6f3040550d`** (replacing `ec8d918f-…`), shipped together with the
> `controller_ips` command-safety rule because a rules deploy publishes the whole file.
>
> **Verified with a plain authenticated non-admin `idToken`** — the correction to the error this
> document diagnoses: `config/solar_scheduling` now reads `enabled=true` for an ordinary client,
> where it previously returned `403 PERMISSION_DENIED`.
>
> **Tyler confirmed the real acceptance test on build 277: the schedule editor's Sunrise/Sunset
> segments are selectable.** All six gated surfaces and the sync path un-gate from the same
> provider, so they follow automatically.
>
> Deploy log: `audit/COMMAND_SAFETY.md` § "STEP 7 — RULE DEPLOYED".
> The verification rule this cost us is recorded in §8 below and was adopted permanently.

The diagnostic below is preserved as written, in its pre-fix present tense.

---

## 0. ANSWER

**Firestore rules. The client cannot read `config/solar_scheduling` at all.**

There is **no `match /config/solar_scheduling`** block in `firestore.rules`. Its three sibling
flags each have one; solar has none, and the catch-all is default-DENY. The app's listen is
rejected, the provider's `catch` yields `false`, and every solar surface stays shut.

**My "readback-confirmed" verification was wrong — I verified with the wrong credential.** The flag
was created and read back with the **admin SDK, which bypasses rules**. That proved the document
exists; it did not prove the app can read it. Measured just now:

```
Authenticated as a PLAIN user (no admin claim) — this is what the app is.

  config/solar_scheduling         DENIED (403 PERMISSION_DENIED)
  config/calendar_leases          READABLE  enabled=true
  config/schedules_subcollection  READABLE  enabled=false
  config/sync_fanout              READABLE  enabled=false

  ADMIN SDK read of config/solar_scheduling: exists=true enabled=true
  ^ bypasses rules — which is why the original readback looked fine.
```

**Consequence: the 2026-08-05 flag flip has had no effect whatsoever.** Solar is still refused
fleetwide. Ellie Cochran, Tim Kelly and Chris Cipollone are exactly as broken as they were on
2026-07-28 — not because the flag is missing this time, but because the app cannot see it.

---

## 1. THE EDITOR'S GATE — traced

`my_schedule_page.dart:4013`

```dart
final solarEnabled = ref.watch(solarSchedulingEnabledSyncProvider);
```

feeds `ButtonSegment(value: _TriggerType.solarEvent, enabled: solarEnabled, …)` for both the ON and
OFF pickers. It is the **same provider** that reads `config/solar_scheduling` — there is no second
or stale source. The wiring is correct; its input is `false`.

---

## 2. WHICH PROVIDER — the sync adapter, but that is NOT the cause

The UI reads `solarSchedulingEnabledSyncProvider` (the adapter), which watches the
`solarSchedulingEnabledProvider` stream and collapses anything non-`data` to `false`:

```dart
ref.watch(solarSchedulingEnabledProvider).maybeWhen(data: (v) => v, orElse: () => false)
```

The loading-race theory in the brief is sound in general — the adapter *does* report `false` while
`AsyncLoading` — but it is **not** what is happening, for two reasons:

1. `ref.watch` (not `ref.read`) means the widget **does** rebuild when the stream later emits. A
   transient loading `false` would self-correct within a frame or two.
2. The stream never emits `true` at all. Its `catch` block converts the permission error into a
   terminal `yield false`:

```dart
} catch (e) {
  debugPrint('SolarScheduling: feature-flag stream error — $e (defaulting to false)');
  yield false;
}
```

So the value is a **settled `false` derived from an error**, not an unresolved loading state. The
safe-default design is correct — it just makes a permission denial indistinguishable from a flag
that is genuinely off.

---

## 3. CACHING / LIFECYCLE — not the cause, and the force-close PROVES it

**Tyler's force-close and reopen changed nothing, and that is diagnostic rather than incidental.**

A stale-cache explanation predicts that a cold start would fix it: a fresh process re-listens, gets
the now-existing document, and the segments enable. That did not happen. A permission denial, by
contrast, predicts exactly what was observed — every re-listen is denied again, on every launch,
indefinitely.

Firestore's offline cache is also not serving a stale "does not exist": a denied listen produces an
error, not a cached negative.

---

## 4. THE SECOND GATE — not involved

The clock-health `LOCATION_UNSET` gate is at **`my_schedule_page.dart:4386`**, inside the save
handler:

```dart
final clockOk = await maybeWarnClockBeforeSave(…, creatingSolar: creatingSolar);
```

It runs **when the user presses Save**. It has no connection to `ButtonSegment(enabled:)`, so it
cannot be what disables the segments — the segments are disabled before any save is attempted.

And it would not have fired anyway. The rig reports usable coordinates, restored after the fudge
testing and re-verified for this report:

```
rig coords: lt=38.99346 ln=-94.2527 tz=5   → non-zero and usable: True
```

---

## 5. THE OTHER FOUR SURFACES — all shut, and that locates the bug

Every surface reads the **same** provider, so none of them un-gated:

| Surface | Call site | State |
|---|---|---|
| Schedule editor | `my_schedule_page.dart:4013` (`watch`) | shut |
| Editor `_offTrigger` default | `my_schedule_page.dart:3912` (`read`) | still forced to clock |
| Autopilot baseline | `autopilot_providers.dart:643` | still emits clock times |
| AI prompt schema | `lumina_brain.dart:327` | still appends the "never emit Sunset/Sunrise" constraint |
| Commercial events | `create_event_screen.dart:239` | still uses the clock fallback |
| Neighborhood sync | `schedule_list.dart:1072` (`watch`) | checkbox still disabled |

**The distinction the brief was looking for: it is NOT editor-specific.** A uniform failure across
six independent call sites points at their shared input, not at any one of them — which is what
pointed at the provider, and from there at the rules.

**And it reaches past the UI.** `schedule_sync.dart:744` reads the same provider for
`solarFlagOn`, so the *sync* path also still refuses solar. This is not merely a greyed-out button;
no solar row can be written by any path.

---

## 6. WHY THE +61 CLAIM WAS RIGHT AND STILL FAILED

`audit/SOLAR_COMPARATOR.md` said the five surfaces "un-gate themselves" because they were built
flag-driven rather than hardcoded. **That is true and remains true** — none of them needs a code
change. They are driven by a value that is stuck `false` upstream of all of them.

The error was not in the gating design. It was in **treating an admin-SDK readback as proof the app
could see the flag.** Every prior verification in this saga used the same tool for the same reason
and got away with it, because those reads were of user documents the admin SDK and the client can
both reach. `config/` is the first place where the credential mattered — and it is exactly where
the flag lives.

---

## 7. WHAT FIXING IT WILL INVOLVE (not done here)

The shape is a one-block rules addition mirroring its siblings:

```
match /config/solar_scheduling {
  allow read: if request.auth != null;
  allow create: if request.auth != null && request.resource.data.enabled == false;
  allow update, delete: if false;
}
```

**But it needs a `firestore.rules` DEPLOY, and that collides with an open sequencing constraint.**
The repo's `firestore.rules` also carries the **undeployed `controller_ips` command-safety change**,
which is mid-soak and whose deploy order is load-bearing (backfill → soak → rule; deploying the rule
early kills remote control fleet-wide). A `firebase deploy --only firestore:rules` ships the whole
file, so the solar rule **cannot** be deployed without also shipping the controller_ips rule.

That is a decision for Tyler, not a detail to resolve inside a fix:
- deploy both together, accepting the controller_ips cutover now (its steps 1-5 are complete); or
- temporarily revert the controller_ips hunk, deploy solar alone, and restore it; or
- wait for the controller_ips soak to finish and ship both.

**Until the rules deploy, solar stays off in the app no matter what the flag document says.**

> **DECIDED AND DONE (2026-08-05):** option one — both shipped together. The controller_ips
> cutover was safe to take: its pre-deploy backfill dry run returned `updated: 0 / unchanged: 15`,
> so every account holding controllers already carried the allowlist and nobody was stranded. The
> combined blast radius was measured against the **fetched live ruleset** at exactly two paths,
> both intended `/commands` denials.

---

## 8. VERIFICATION METHOD TO ADOPT

For anything gated by a `config/` document, an admin-SDK readback is not sufficient evidence.
**Verify with an authenticated non-admin client token** — the differential in §0 took under a minute
and would have caught this at flip time. The sibling flags in the same run act as the control: if
they read and the new one 403s, the gap is rules, not data.

**✅ ADOPTED 2026-08-05.** The post-deploy verification in `audit/COMMAND_SAFETY.md` §5 was run
entirely through a plain authed `idToken` over the Firestore REST API; the admin SDK minted the
token and cleaned up the throwaway uid, and made **no assertion**. The sibling flags were read in
the same run as the control.

**A second instance of the same class turned up during that verification, and is worth as much as
the first.** The bridge-health probe wrote to `users/{uid}/bridge_health/` and got a 403 that
briefly read as a deploy regression. **That collection does not exist** — the real path is
`users/{uid}/commands/bridge_health_check` (`bridge_health_service.dart:34-46`), a *commands*
document carrying a `controllerIp` and therefore genuinely subject to the new rule. The 403 was the
catch-all correctly denying an undeclared path.

Both errors are the same mistake: **verifying against something other than what the app actually
does** — the wrong credential in one case, a path that does not exist in the other. Generalised:

> A verification is only evidence if it exercises the same credential, the same path, and the same
> code the app uses. Confirm the path from the writing code, not from its name; confirm readability
> with the client's own token; and treat the behaviour in the app as the acceptance test.
