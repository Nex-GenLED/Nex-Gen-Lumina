# INSTALLER MODE — ENTRY POINT AUDIT

**Date:** 2026-08-11
**Scope:** read-only. Nothing changed.
**Trigger:** Tyler reaches installer mode via System → Support & Resources → tap
the version tile 5× → enter a dealer code, and doesn't recognise that as the
documented flow.

---

## VERDICT UP FRONT

The path Tyler found is **real, it is not a debug affordance, and it mints a
genuine server-side staff token.** It is the *original* installer entry from the
Dreamflow port (2026-01-23). It was **superseded** on 2026-04-09 by the unified
`/staff/pin` screen, but only the *login-screen* caller was migrated. The
Settings tap-5 was never retired, and it still points at the **legacy**
`InstallerPinScreen`, not the unified one.

So: **the documentation is not stale — the code is.** Two parallel installer
entries exist, both live, both functional, reaching two different screens that
land on two different destinations.

The most serious finding in this audit is **not** the tap-5. It is entry point
**#5 below**: a *fully visible, unhidden* "Installer" button on the
link-account screen, which is exactly where a fresh sign-up lands.

---

## 1. ENUMERATION — EVERY ENTRY POINT

| # | Widget / location | Gesture or route | Lands on | Requires |
|---|---|---|---|---|
| 1 | `_InstallerModeEntry`, [settings_page.dart:588-676](lib/features/site/settings_page.dart#L588-L676) — the "Version 1.6.0 / Build 2026.01" tile inside the **Support & Resources** card | **5 taps within a rolling 2 s window** reveals an "Installer Mode" tile; tapping it pushes `/installer/pin` | **legacy** `InstallerPinScreen` → on success `context.go('/installer/wizard')` — **skips the landing screen** | 4-digit PIN validated server-side |
| 2 | Lumina logo, [login_page.dart:74-87](lib/features/auth/login_page.dart#L74-L87) | **5 taps within a rolling 3 s window** → `context.push('/staff/pin')` | **unified** `StaffPinScreen` → routes by role; installer → `/installer` landing | 4-digit PIN validated server-side |
| 3 | `_SalesModeEntry`, [settings_page.dart:686-776](lib/features/site/settings_page.dart#L686-L776) — the "Powered by Nex-Gen" text | **6 taps / 2 s** → `/sales/pin` | `SalesPinScreen` | 4-digit PIN |
| 4 | `_AdminModeEntry`, [settings_page.dart:786-873](lib/features/site/settings_page.dart#L786-L873) — the "© 2026 Nex-Gen Lighting Systems" line | **7 taps / 2 s** → `/admin/pin` | admin PIN screen | 4-digit PIN |
| 5 | **"Nex-Gen Professional Access" panel**, [link_account_screen.dart:127-176](lib/features/auth/link_account_screen.dart#L127-L176) | **NO GESTURE — a permanently visible labelled button** reading "Installer" | `/staff/pin` | 4-digit PIN |
| 6 | Same panel, "Media" button, [link_account_screen.dart:165-170](lib/features/auth/link_account_screen.dart#L165-L170) | visible button | `/staff/pin` (**mislabelled** — pushes the staff PIN screen, not `MediaAccessCodeScreen`) | 4-digit PIN |
| 7 | Sales queue bounces, [day1_queue_screen.dart:159](lib/features/sales/screens/day1_queue_screen.dart#L159), [day2_queue_screen.dart:92](lib/features/sales/screens/day2_queue_screen.dart#L92) | automatic `context.go(AppRoutes.installerPin)` when installer mode is inactive | legacy `InstallerPinScreen` | 4-digit PIN |
| 8 | Direct route registration, [app_router.dart:387-392](lib/app_router.dart#L387-L392) | deep link / `context.go('/installer/pin')` | legacy `InstallerPinScreen` | 4-digit PIN |

**Entry points 1, 7 and 8 all reach the legacy screen. Entry points 2, 5 and 6
reach the unified screen.** Both screens call the same notifier.

Note the gesture counts are deliberately staggered — 5 installer / 6 sales /
7 admin — with the comments explicitly cross-referencing each other
("different from installer's 5 and admin's 7"). That is *designed* behaviour,
not an accident. Whoever wrote it intended all three to ship.

---

## 2. WHICH IS THE INTENDED ONE?

**The login-screen logo 5-tap (#2) is the intended one.** Git says so plainly:

```
7b166b7  2026-01-23  Fix compilation errors and type mismatches
         → introduces InstallerPinScreen AND the Settings tap-5 (_InstallerModeEntry)
         → 85 files, +23,401 lines — the Dreamflow bulk port

5841f43  2026-04-09  feat: hidden 5-tap staff PIN entry replaces visible Dealer Access button
2e83023  2026-04-09  fix: make staff PIN screen actually reachable from login page
e75e14a  2026-04-09  fix: delegate all PIN validation to existing notifiers
81f87b4  2026-05-05  feat(auth): migrate corporate to owner role ...
```

The tap-5 path predates the unified screen by **11 weeks**. It is an **older
version of the same mechanism** — not a different mechanism, and not a debug
affordance.

The migration was explicitly incomplete, and the router comment admits it —
[app_router.dart:365-372](lib/app_router.dart#L365-L372):

> "Unified PIN entry — reachable only via the hidden 5-tap gesture on the Lumina
> logo on the login screen. […] The legacy single-purpose PIN routes
> (`/installer/pin`, `/sales/pin`, `/corporate/pin`) **remain registered below
> for now, but nothing on the login screen navigates to them directly anymore.**"

That last clause is scoped to *the login screen* — and within that scope it is
true. Applied to the app as a whole it is false:
[settings_page.dart:673](lib/features/site/settings_page.dart#L673) navigates to
`/installer/pin` right now.

The header of the unified screen repeats the same overreach —
[staff_pin_screen.dart:27-30](lib/features/auth/staff_pin_screen.dart#L27-L30):

> "Reachable only via the hidden 5-tap gesture on the Lumina logo on the login
> screen. **No visible entry point exists.**"

Both halves are wrong. It is also reachable from two visible buttons on
link-account (#5, #6). **These two comments are the reason the second path went
unnoticed** — anyone auditing entry points by reading the comments would
conclude there was only one.

---

## 3. WHAT DOES THE TAP-5 PATH ACTUALLY GRANT?

**A real staff token. Not a local flag.** This is the reassuring part of the
audit.

The reveal itself (`_revealed = true`) is purely cosmetic — it only un-hides a
`ListTile`. It grants nothing. The grant happens one screen later:

[installer_pin_screen.dart:56](lib/features/installer/installer_pin_screen.dart#L56)
calls `installerModeActiveProvider.notifier.enterInstallerMode(pin)` — **the
exact same notifier the unified screen calls**
([staff_pin_screen.dart:227-229](lib/features/auth/staff_pin_screen.dart#L227-L229)).

That notifier
([installer_providers.dart:271-340](lib/features/installer/installer_providers.dart#L271-L340)):

1. calls the `mintStaffToken` Cloud Function with `{pin, mode: 'installer'}`;
2. `FirebaseAuth.instance.signInWithCustomToken(token)`;
3. only then sets `state = true`.

Server-side rate limiting is real — `RATE_LIMIT_MAX_ATTEMPTS = 10` per
`RATE_LIMIT_WINDOW_MS = 60_000`, keyed on IP
(`functions/src/staffAuth.ts:126-127, 461-462`).

**No client-side-flag bypass exists.** I checked every consumer of the bool:

- [installer_setup_wizard.dart:536-544](lib/features/installer/installer_setup_wizard.dart#L536-L544) — self-guards, bounces to `/` if false
- [day1_queue_screen.dart:156](lib/features/sales/screens/day1_queue_screen.dart#L156), [day2_queue_screen.dart:89](lib/features/sales/screens/day2_queue_screen.dart#L89) — bounce to PIN if false
- [device_setup_page.dart:97](lib/features/ble/device_setup_page.dart#L97), [roofline_setup_wizard.dart:181](lib/features/design/roofline_setup_wizard.dart#L181), [settings_page.dart:610](lib/features/site/settings_page.dart#L610) — cosmetic reads

The bool is only ever set to `true` after a successful mint. The
"screens visible but every write fails" failure mode you were worried about
**does not occur here.**

### The one real defect in the tap-5 path: it destroys the customer's session

This is unique to the Settings entry and does not exist on the login path,
because on the login path there is no customer session yet.

A signed-in customer taps 5×, enters a PIN → `signInWithCustomToken()` replaces
their Firebase Auth session with the staff one. On exit,
[installer_providers.dart:343-361](lib/features/installer/installer_providers.dart#L343-L361)
does `signOut()` then `signInAnonymously()` — with an explicit comment:

> "We do not attempt to restore a customer's prior session — see commit body for
> the trade-off."

**The customer is silently logged out of their own account** and must sign in
again. That trade-off was presumably weighed for the login-screen path where
it costs nothing. On the Settings path it is a live UX bug.

### Other legacy-vs-unified divergences

| | legacy `InstallerPinScreen` (tap-5) | unified `StaffPinScreen` (login) |
|---|---|---|
| Anonymous-auth bootstrap | **absent** | `_ensureAuthSession()` in `initState` |
| Lockout after 5 fails | dialog → tap OK → screen pops; **reopening resets the counter** — no real lockout | **30 s timed lockout with countdown** |
| Roles handled | installer only | owner → admin → installer → sales |
| Destination on success | `/installer/wizard` — **skips the landing screen** | `/installer` landing |
| PIN format disclosed on screen | **yes** — "Format: Dealer Code (2) + Installer Code (2)", with the dots labelled "Dealer" and "Installer" | no — generic "Staff Access / Enter 4-digit PIN" |

That last row explains Tyler's wording exactly. He said "enter a dealer code"
because **the legacy screen literally labels the first two PIN dots "Dealer"**
([installer_pin_screen.dart:223-230](lib/features/installer/installer_pin_screen.dart#L223-L230))
and prints the format hint at
[:184](lib/features/installer/installer_pin_screen.dart#L184). It is one
4-digit PIN — `0101` = dealer `01` + installer `01` — the same PIN the
documented flow uses. He is describing the documented credential entered on an
undocumented screen.

---

## 4. IS IT REACHABLE BY A REVIEWER? — **YES, AND THAT IS THE HEADLINE**

The demo-browsing guard does **not** protect against this. Three of the four
Settings entries are wrapped in `if (ref.watch(demoBrowsingProvider)) return
SizedBox.shrink()` ([settings_page.dart:547-568](lib/features/site/settings_page.dart#L547-L568)),
and `appRedirect` blocks `/installer` when `isDemoBrowsingFlag`
([route_guards.dart:51-58](lib/route_guards.dart#L51-L58)).

**But the App Store reviewer is not a demo browser.** `ReviewerSeedService`
signs them in as a *real account* (`reviewer@Nex-GenLED.com`) with
`installationRole: primary`
([reviewer_seed_service.dart:18-48](lib/services/reviewer_seed_service.dart#L18-L48)).
So for the reviewer:

- `demoBrowsingProvider` is **false** → all four hidden Settings entries **render**
- `isDemoBrowsingFlag` is **false** → `appRedirect` **permits** `/installer/*`
  (it hits the `isInstallerRoute` allow at [route_guards.dart:217-221](lib/route_guards.dart#L217-L221))

### What a reviewer would actually see

**Via tap-5 (#1)** — plausible; tap-N-on-build-number is a well-known idiom and
the tile is styled exactly like a version readout. They land on a screen
titled **"Installer Access" / "Enter Installer PIN"** stating *"This area is
restricted to authorized installers"* and disclosing the credential format
*"Dealer Code (2) + Installer Code (2)"*. Without a valid PIN they cannot
proceed. Nothing renders broken or half-built.

**Via link-account (#5, #6)** — **this is the exposure that matters.** It needs
no gesture at all. A reviewer who creates a fresh account gets
`installation_role: 'unlinked'`
([route_guards.dart:37](lib/route_guards.dart#L37)) and is redirected straight
to `/link-account` ([route_guards.dart:288](lib/route_guards.dart#L288)) — a
screen carrying a permanently visible panel headed **"Nex-Gen Professional
Access"** with a labelled **"Installer"** button. Creating an account is the
first thing a reviewer does. This is not a corner they have to go looking for;
it is on the path.

And **the "Media" button next to it is broken** — it pushes `/staff/pin`
(the 4-digit staff PIN screen) rather than `MediaAccessCodeScreen`, which
expects a **6-character** media code
([media_access_code_screen.dart:11-14](lib/features/installer/media_access_code_screen.dart#L11-L14)).
A reviewer tapping "Media" gets a screen that cannot accept the credential its
own button implies. That is a visible dead end reached from a visible button —
squarely the **Guideline 2.1** risk you flagged, and a stronger case for it
than the tap-5.

---

## 5. DOES IT RESPECT THE MASTER-PIN REFUSAL?

**Yes — identically to the intended path, because the refusal isn't in either
PIN screen.**

`68e5f04` (2026-07-16) put the check in the *wizard*, not at PIN entry —
[installer_setup_wizard.dart:1111-1121](lib/features/installer/installer_setup_wizard.dart#L1111-L1121):

```dart
if (installUsesReservedDealerCode(session.dealer.dealerCode)) {
  _showError("That's a master support PIN — it can't be used to set up a customer. ...");
  return;
}
```

`installUsesReservedDealerCode` tests `dealerCode == DealerCode.masterReserved`
(`'55'`), which `mintStaffToken` stamps on any master PIN
(`functions/src/staffAuth.ts:119, 208-210`). Since **both** PIN screens hand off
to the same wizard, both are covered equally. **No bypass.**

One nuance worth recording, though it applies to both paths: the guard sits at
the top of `_completeSetup()` — the *final commit* step. The doc comment claims
it "refuses this code up front so the install stops before any Firebase work",
and that is true of *Firebase writes*. It is not true of *the installer's time*:
a master-PIN holder can walk all eight wizard steps — customer info, controller
setup, connection method, zones, hardware, roofline, brand — and only be refused
at the end. The tap-5 path makes this marginally worse by landing directly on
`/installer/wizard` and skipping the landing screen, so there is one fewer
surface where the session's dealer code could have been shown before the work
began.

---

## 6. GIT — WAS IT MEANT TO BE TEMPORARY?

**No. There is no evidence it was ever intended as temporary.**

I swept `settings_page.dart`, `installer_pin_screen.dart`, `staff_pin_screen.dart`,
`link_account_screen.dart` and `installer_providers.dart` for
`TEMPORARY`, `TEMP HACK`, `REMOVE BEFORE`, `STRIP BEFORE`, `DEBUG ONLY`,
`debug affordance`, `remove this`, `FIXME`, `XXX HACK`, `dev only`, `kDebugMode`.

**Zero hits.** (This is the same sweep shape that previously caught the live
release-build Firestore write in the #84 instrumentation — so the negative here
is meaningful, not a sweep that wasn't run.)

Positive evidence it was meant to ship:

- The three Settings gestures use **deliberately staggered counts** (5/6/7) with
  comments cross-referencing each other. Someone designed a set.
- The revealed tiles are **fully styled** — gradient icon containers, "Active"
  status chips, exit affordances. Debug affordances don't get gradients.
- There is an **exit path** (`exitInstallerMode` wired to the Active tile at
  [settings_page.dart:637-642](lib/features/site/settings_page.dart#L637-L642)).
- It is `const`-constructed in the production widget tree with no build-mode
  guard whatsoever.

It is production code that was **orphaned by an incomplete migration**, not
debug scaffolding that was forgotten.

---

## SUMMARY OF FINDINGS

| # | Finding | Severity |
|---|---|---|
| F1 | **Visible unhidden "Installer" button** on `/link-account` — the screen every fresh sign-up lands on. No gesture required. Reviewer-reachable on the default path. | **Guideline 2.1 risk — highest** |
| F2 | **"Media" button pushes the wrong screen** (`/staff/pin`, 4-digit) instead of `MediaAccessCodeScreen` (6-char). Visible button → dead end. | **Guideline 2.1 risk** |
| F3 | Settings tap-5 routes to the **legacy** `InstallerPinScreen`, which **discloses the PIN format** on screen and has **no real lockout** (dialog + pop; counter resets on reopen) vs the unified screen's 30 s timed lockout. | Medium |
| F4 | Settings-path installer entry **silently destroys the customer's Firebase Auth session**; exit drops to anonymous, never restores the customer. | Medium (UX/data) |
| F5 | Two comments assert the unified screen is the *only* entry and that "no visible entry point exists" — [app_router.dart:365-372](lib/app_router.dart#L365-L372), [staff_pin_screen.dart:27-30](lib/features/auth/staff_pin_screen.dart#L27-L30). Both false. These comments are why this went unnoticed. | Medium (audit hazard) |
| F6 | Legacy path lands on `/installer/wizard` directly, skipping the landing screen — inconsistent session context before an install begins. | Low |
| — | Master-PIN `'55'` refusal is **respected identically** by both paths. | ✅ no gap |
| — | Tap-5 mints a **real server-side token**; no client-flag bypass anywhere. | ✅ no gap |

---

## WHAT I DID NOT DO (original audit pass)

Nothing was removed, and no fix was applied — per instruction. Recommendations
are deliberately withheld pending your read of §2: **if the tap-5 path is to be
retired, the decision belongs with the incomplete `5841f43` migration, not with
this audit.** The documentation describes the intended flow correctly; it is the
un-migrated callers that diverge from it.

Two things I'd flag as needing a decision before submission regardless of what
happens to the tap-5: **F1 and F2** — those are visible, unhidden, on a
reviewer's default path, and F2 is an outright broken destination.

---
---

# IMPLEMENTATION PASS — 2026-08-11

**Decision (Tyler, 2026-08-11):** remove the Settings tap-5. Not deployed.

> Note on labels: the follow-up prompt referred to the link-account panel as
> "F2" and the Media button as "F1"; the table above numbers them the other way
> (F1 = panel, F2 = Media button). Same two findings, inverted labels. This
> section uses descriptions, not letters.

## Changes made (4 files)

| File | Change |
|---|---|
| [settings_page.dart](lib/features/site/settings_page.dart) | `_InstallerModeEntry` → `_VersionTile`. Tap counter, 2 s window, `_revealed` state and the `/installer/pin` push all deleted. Now a `ConsumerWidget`. |
| [link_account_screen.dart](lib/features/auth/link_account_screen.dart) | **"Media" button removed.** "Installer" button untouched. |
| [app_router.dart](lib/app_router.dart) | False comment at the `/staff/pin` registration corrected. |
| [staff_pin_screen.dart](lib/features/auth/staff_pin_screen.dart) | False header comment corrected. |

### What was deliberately KEPT

The `installerModeActiveProvider == true` branch of the old widget survives in
`_VersionTile`. It is an **exit**, not an entry — it renders only when a real
server-minted staff token already exists, and removing it would strand an
active installer session in Settings with no way out. The version readout
("Version 1.6.0 / Build 2026.01") also stays; it is now plain, non-interactive
text with no `GestureDetector`.

---

## 1. Tap-5 removed ✅

Gesture and route both gone. There is no longer any path from Settings to
`/installer/pin`.

## 2. Does `InstallerPinScreen` become unreferenced? — **NO. Not deleted.**

You asked me to confirm no other caller first. **There are two**, plus the route
registration:

- [day1_queue_screen.dart:159](lib/features/sales/screens/day1_queue_screen.dart#L159) — `context.go(AppRoutes.installerPin)`
- [day2_queue_screen.dart:92](lib/features/sales/screens/day2_queue_screen.dart#L92) — same
- [app_router.dart:387-392](lib/app_router.dart#L387-L392) — route registration

Both are **role gates**, not user-facing entries: the Day 1 / Day 2 sales
dispatch screens bounce to the installer PIN when `installerModeActiveProvider`
is false. So the screen is still live code and deleting it now would break the
sales dispatch flow.

**This is not the ScheduleDayRow situation.** That was genuinely unreferenced.
This one has real callers.

**To finish the job** (recommend, not implemented — it changes sales-flow
behaviour and needs your call): repoint those two bounces at
`AppRoutes.staffPin`, then delete `InstallerPinScreen` and its route. The
behavioural difference is real and worth weighing — the unified screen lands
installers on `/installer` (landing) rather than `/installer/wizard`, so a
salesperson bounced out of the Day 1 queue would arrive at the landing screen
and need one extra tap to get back. It also *gains* them the 30 s lockout and
loses the on-screen PIN-format disclosure.

## 3. The staggered 5/6/7 gestures — 6 and 7 still exist and still work

Removing the 5 did **not** orphan or renumber them; the counts are independent
per-widget constants, not derived from each other. Only the *comments* referred
to each other, and those comments live on the surviving widgets:

| Gesture | Widget | Target text | Destination | Still wanted? |
|---|---|---|---|---|
| **6 taps** | `_SalesModeEntry` | "Powered by Nex-Gen" | `/sales/pin` → `SalesPinScreen` | **Your call.** Same hidden-entry pattern, same reviewer reachability. No session-destruction bug proven for it, but it enters via `salesModeProvider` which mints its own token — worth a look if the tap-5 concern generalises. |
| **7 taps** | `_AdminModeEntry` | "© 2026 Nex-Gen Lighting Systems" | `/admin/pin` | **Your call**, and the highest-privilege of the three. Note it also has an "Active" branch that pushes `AppRoutes.corporateDashboard` directly. |

Both remain wrapped in the `demoBrowsingProvider` guard — which, as §4
establishes, **does not protect against an App Store reviewer**, because the
reviewer is signed into a real account. If the tap-5 was worth removing on
reviewer-reachability grounds, the same argument applies to these two. I have
not touched them.

The `_SalesModeEntry` comment still reads "different from installer's 5 and
admin's 7". That is now a dangling reference to a removed gesture. Left as-is
rather than silently rewritten, since it is evidence for the 6/7 decision.

## 4. Both false comments corrected ✅

Worded against reality, not intention — as instructed. The unified screen is
**still** not the only entry, because `/link-account` was left in place, so
neither comment now claims it is. Both now name the visible link-account panel
explicitly and carry a "do not re-assert 'only one'" warning so the claim
doesn't regrow.

---

## The Media button — removed, and why repointing was NOT the fix

The premise in the prompt was that this is a wrong route constant. It is more
than that. `AppRoutes.mediaAccessCode` (`/media/code`) **is** registered
([app_router.dart:593-596](lib/app_router.dart#L593-L596)), so repointing
compiles — but it produces a button that is still broken, in three
independent ways:

1. **The route guard bounces the only user who can press it.** `/media` is in
   no `appRedirect` allow-list (only `/installer`, `/admin`, `/sales`, `/demo`).
   The sole population reaching `/link-account` is `installation_role:
   'unlinked'`, which falls through to
   [route_guards.dart:288](lib/route_guards.dart#L288) → back to
   `/link-account`. **The button would return you to the screen you pressed it
   on.**
2. **`media_codes` has no firestore.rules coverage at all.** The lookup at
   [media_access_code_screen.dart:259](lib/features/installer/media_access_code_screen.dart#L259)
   default-denies for every caller, as does the `media_access_logs` write at
   :316. The `hasMediaAccess()` helper was deliberately dismantled in D3-S2 —
   the only remaining mentions of "media" in `firestore.rules` are the comments
   recording its removal.
3. **The success path fabricates a session client-side.** On a valid code the
   screen writes `installerSessionProvider` directly
   ([:301-313](lib/features/installer/media_access_code_screen.dart#L301-L313))
   with **no `mintStaffToken`, no custom token, no claims** — the exact
   "client-side flag that unlocks UI without server-side authorisation" shape
   the original audit went looking for on the installer path and did not find.
   It is here instead. (It does *not* set `installerModeActiveProvider`, so it
   unlocks less than it appears to — but every read it enables is claim-less
   and would be denied.)

`MediaLandingScreen` (`/media`) is also **orphaned** — registered, but nothing
in the app navigates to it.

So: removing the button is the minimal change that takes a broken visible
control off the reviewer's default path. Reviving media access is a feature
decision (rules + guard + real token mint), not a one-line fix. The full
reasoning is recorded inline at the removal site so this isn't rediscovered.

---

## SEPARATE — the `/link-account` Professional Access panel (NOT touched)

Left in place as instructed. Reporting only.

### What would a dealer do without it?

**They would still get in.** Capability is preserved; only discoverability is
lost. The login-screen logo 5-tap works **before** authentication —
[route_guards.dart:87-98](lib/route_guards.dart#L87-L98) explicitly allows
`isStaffPinRoute` for logged-out users, and `StaffPinScreen.initState`
establishes its own anonymous session for the Firestore reads. So:

- **Installer not signed in at all** → login screen → 5-tap logo → `/staff/pin`. Works today, panel or no panel.
- **Installer signed in as an unlinked personal account** (the case that lands on `/link-account`) → the screen already has a **"Sign out"** button at [link_account_screen.dart:179](lib/features/auth/link_account_screen.dart#L179) → login screen → 5-tap. Two extra steps.

### Is there another route in for someone not already staff?

Yes — the login-screen 5-tap, and it is the *only* other one. After this pass
the complete set of installer-mode entries is:

1. Login-screen logo 5-tap → `/staff/pin` (pre-auth, works signed-out)
2. `/link-account` "Installer" button → `/staff/pin` (visible, no gesture)
3. Day 1 / Day 2 sales-queue bounces → `/installer/pin` (role gates, not user entries)

### So what is the panel actually for?

It is the only entry that does not require knowing an **undocumented gesture**,
and the only one reachable **without signing out first**. That is a real
onboarding function: a new dealer who installs the app, makes an account, and
lands on `/link-account` has no way to discover the logo tap. Removing the panel
converts installer access into tribal knowledge.

**The trade-off is discoverability for dealers vs. a labelled "Installer" button
on the first screen an App Store reviewer sees.** Both are real. My read: the
panel is defensible if you're comfortable that a reviewer pressing "Installer"
gets a clean, functional PIN prompt that simply refuses them — which it does,
and which is materially better than the Media button was. It is not an
incomplete or broken surface; it is a locked one. That is usually a 2.1 pass.

If you want it gone anyway, the cheap mitigation that keeps dealer onboarding
working is to document the logo 5-tap in the dealer/installer setup guide
**before** removing the panel — not after.

---

## VERIFICATION

```
flutter analyze  → 385 issues; 0 errors/warnings in the 4 touched files
                   (only pre-existing infos: deprecated_member_use,
                   use_build_context_synchronously, unnecessary_import)

flutter test     → 2148 passed, 3 skipped, 1 failed
```

**The single failure is pre-existing, hardware-dependent, and unrelated.**
`test/hardware/base_ladder_repair_live_test.dart` — *"rig should expose both
channels: Expected ≥2, Actual 1"*. It is `@Tags(['hardware'])`, runs live
against the bench controller at `192.168.1.150`, and fails on **rig state**:
the controller is currently presenting one channel, which is the known
reboot-segment-collapse condition (`seglc [3,3]→[3]`). No code path of mine is
reachable from it.

Two analyzer errors initially appeared in
`test/features/wled/controller_facts_writer_test.dart`; that file **compiles and
passes 21/21** when run directly. It belongs to the in-flight
`controller_facts_publisher.dart` / `controller_defaults_healer.dart` work
already dirty in the tree from a parallel session — not this change.

**Not deployed**, per instruction.

---
---

# SCOPING PASS — 2026-08-11 (no code changed)

Two decisions scoped. **Nothing implemented; no routing changed, no gestures
removed.**

---

# DECISION 1 — THE 6-TAP AND 7-TAP GESTURES

## 1a. What each unlocks, and is either the client-flag shape? — **NO. Both mint real tokens.**

I checked both against the Media-button failure mode specifically. Neither
matches it.

**6-tap → Sales mode** ([sales_providers.dart:65-115](lib/features/sales/sales_providers.dart#L65-L115)):

```
mintStaffToken({pin, mode: 'sales'})
  → signInWithCustomToken(token)
  → currentSalesSessionProvider = SalesSession(...)
  → state = true          ← only after the mint
```

**7-tap → Admin mode** ([admin_providers.dart:84-109](lib/features/installer/admin/admin_providers.dart#L84-L109)):

```
mintStaffToken({pin, mode: 'admin'})
  → signInWithCustomToken(token)
  → state = AdminSession(authenticatedAt: ...)   ← only after the mint
```

Both carry the same defenses as the installer path: a 5-strike local lockout
plus the server-side per-IP 10-attempts-per-60s window. The admin notifier's
header is explicit that the old client-side path is gone — *"The previous
client-side path (`validateAdminPin` + 15-minute `_AdminPinRateLimiter`) is
gone"* ([:53-55](lib/features/installer/admin/admin_providers.dart#L53-L55)).

`adminAuthenticatedProvider` is a derived read
(`adminAuthenticatedProvider → adminSessionActiveProvider → notifier state`,
[:207-209](lib/features/installer/admin/admin_providers.dart#L207-L209)) — it
cannot be set without a successful mint.

One thing that looked suspicious and is **not** a bypass: the raw
`.where('installerPin', ...)` Firestore query at
[admin_providers.dart:436](lib/features/installer/admin/admin_providers.dart#L436)
is `AdminService.getInstallationCount()` — dealer-management tooling that runs
*after* authentication, not part of it.

**So the Media button remains the only client-flag entry found in this codebase.**

### But both carry the session-destruction bug that justified removing the 5-tap

This is the finding that matters most here. `exitSalesMode()`
([sales_providers.dart:117-137](lib/features/sales/sales_providers.dart#L117-L137))
is **character-for-character the same** as `exitInstallerMode()` — same
`signOut()` → `signInAnonymously()`, same verbatim comment:

> "We do not attempt to restore a customer's prior session — see commit body for
> the trade-off."

The admin notifier documents the same behaviour at
[:50-51](lib/features/installer/admin/admin_providers.dart#L50-L51) (*"On exit
we sign out and re-establish the anonymous baseline"*).

**A customer who taps 6 or 7 times and enters any PIN is logged out of their own
account exactly as they would have been via the 5-tap.** The bug was never
specific to the installer path — it was specific to *entering staff mode from a
Settings screen you reached as a signed-in customer*, which is precisely what
these two still do.

## 1b. What would a reviewer see at the 7-tap? — a locked prompt. **2.1 pass.**

Reachable: yes. `appRedirect`'s `isInstallerRoute` includes
`startsWith('/admin')` ([route_guards.dart:71-72](lib/route_guards.dart#L71-L72)),
so `/admin/pin` is permitted for the reviewer's real signed-in account.

They land on `AdminPinScreen`
([admin_dashboard_screen.dart:90-125](lib/features/installer/admin/admin_dashboard_screen.dart#L90-L125)):
an appbar reading **"Admin Access"**, an amber shield icon, four PIN dots, a
keypad. Wrong PIN → **"Incorrect PIN"**. Nothing more.

This is **materially safer than the legacy installer screen was**: it discloses
no credential format (no "Dealer Code (2) + Installer Code (2)" hint) and
nothing renders half-built. A reviewer sees a locked door, not a broken or
incomplete feature. On success it goes to `corporateDashboard` — but that
requires the PIN, against a server rate limit.

Discovery probability is also lower than the 5-tap's was: tapping a **build
number** is a famous idiom; tapping a **copyright line** seven times is not.

**Conclusion: the 7-tap is not a Guideline 2.1 exposure.** If it is retired, the
reason is the session bug in 1a and duplicate-surface hygiene — not review risk.

## 1c. Who uses them, and is there a fallback? — **Yes. Both are pure duplicates.**

This is the decisive answer, and it is *stronger* than the installer case was.

`/staff/pin` tries **all four roles in one prompt** — owner → admin → installer
→ sales ([staff_pin_screen.dart:198-248](lib/features/auth/staff_pin_screen.dart#L198-L248))
— and routes on the first match. So the login-screen logo 5-tap already reaches
sales mode and admin mode.

| Gesture | Who uses it | Fallback if removed |
|---|---|---|
| 6-tap → sales | Field salespeople | Login logo 5-tap → `/staff/pin` → enters sales at branch 4 → `salesLanding` |
| 7-tap → admin | Nex-Gen HQ / corporate | Login logo 5-tap → `/staff/pin` → enters admin at branch 2 → `corporateDashboard` |

**Neither gesture unlocks anything `/staff/pin` does not already unlock, and
both land on the same destination.** Unlike the 5-tap — which at least routed to
a *different* screen (`/installer/wizard` vs `/installer`) — these two are exact
duplicates of an existing path. Removing them costs **zero capability**.

The one genuine asymmetry, same as the link-account panel: the Settings gestures
work while already signed in, whereas the login gesture requires signing out
first. But for these two that "convenience" *is* the bug in 1a — the
signed-in-customer case is exactly the one that ends with the customer logged
out.

## 1d. RECOMMENDATION — retire both

| Option | Cost | Verdict |
|---|---|---|
| **Retire both** | ~10 lines each: delete `_SalesModeEntry` / `_AdminModeEntry` and their `Consumer` wrappers, exactly as `_InstallerModeEntry` was handled. `/sales/pin` and `/admin/pin` stay registered (other callers). ~20 min + suite. | **Recommended.** Zero capability loss (1c), removes two more instances of the session bug (1a). |
| **Gate behind a role/claim** | Not viable — same chicken-and-egg as the link-account panel: the entry exists to *acquire* the claim, so there is no claim to gate on. | Reject. |
| **Gate behind `kDebugMode`** | ~2 lines each, but staff lose them in release — functionally identical to retiring, with dead code left behind. | Reject; retire is cleaner. |
| **Keep as-is** | Zero effort. Accepts the session bug on two more surfaces. | Defensible **only** on review-risk grounds, and 1b says review risk isn't the issue here. |

**Retire.** The 2.1 argument is weaker than it was for the tap-5 (1b), but the
*duplication* and *session-bug* arguments are stronger (1a, 1c). If you keep
them, keep them knowingly: a customer who finds either one gets silently signed
out of their own account.

Housekeeping either way: the `_SalesModeEntry` comment still reads *"different
from installer's 5 and admin's 7"* — a dangling reference to the removed
gesture. Left in place as evidence for this decision.

---

# DECISION 2 — SALES QUEUE ROUTING

## First: the premise needs one correction

The prompt describes *"a salesperson bounced out of the Day 1 queue"*. The Day 1
/ Day 2 queues live under `lib/features/sales/screens/`, but they are
**installer surfaces**, not sales ones.

The **only** user-facing entry to either is the **installer landing screen** —
[installer_landing_screen.dart:151](lib/features/installer/installer_landing_screen.dart#L151)
("Day 1 Queue" tile) and
[:160](lib/features/installer/installer_landing_screen.dart#L160) ("Day 2
Queue"). Nothing on the sales landing screen navigates to them. They gate on
`installerModeActiveProvider`, not `salesModeActiveProvider`.

So whoever is standing in the Day 1 queue **got there holding an installer
session**. The `context.go(AppRoutes.installerPin)` bounce is therefore **not a
login path — it is a 30-minute-idle-timeout safety net.**

That reframes the whole question, and makes it easier.

## 2a. Trace both, to the landing route

**TODAY (legacy):**
```
Day 1 Queue → session expires → context.go('/installer/pin')
  → InstallerPinScreen → correct PIN
  → context.go('/installer/wizard')        ← the CUSTOMER SETUP WIZARD
```
The installer is dropped into a fresh customer-provisioning wizard. The Day 1
queue is not reachable from there without backing all the way out.

**REPOINTED (unified):**
```
Day 1 Queue → session expires → context.go('/staff/pin')
  → StaffPinScreen → correct PIN → branch 3 (installer)
  → _onSuccess(AppRoutes.installerLanding) → '/installer'
  → "Day 1 Queue" tile is ON that screen — one tap back
```

## 2b. Regression, improvement, or neutral? — **Improvement, clearly.**

The current destination is *wrong for the actor*: someone whose session expired
mid-queue is sent to the customer setup wizard. The unified destination is the
installer landing, which has the Day 1 / Day 2 tiles on it. Recovery goes from
"back out of a wizard and re-navigate" to **one tap**.

Secondary gains, both from the §3 comparison table:
- **gains** the real 30-second timed lockout (legacy's dialog-and-pop resets its counter on reopen);
- **loses** the on-screen "Dealer Code (2) + Installer Code (2)" credential disclosure.

I found no respect in which the legacy screen serves this bounce better.

## 2c. Does the unified screen handle the sales role? — Yes, and it is nearly moot here

`/staff/pin` handles sales at branch 4
([staff_pin_screen.dart:236-244](lib/features/auth/staff_pin_screen.dart#L236-L244)).
The ordering comment is explicit that per-installer PINs claim **installer**
before sales ever gets a look, so the ordinary actor here — an installer whose
session lapsed — re-enters installer mode and satisfies the gate.

The one edge case worth naming: a holder of the **master sales PIN** only.

- **Today:** `enterInstallerMode()` rejects it → *"Incorrect PIN"*. Dead end.
- **Repointed:** branch 4 matches → sales mode → `context.go(salesLanding)`.

No redirect loop either way (the `go` replaces the queue screen rather than
returning to it). The repointed behaviour is arguably better — they land on
their own landing screen instead of being told their valid PIN is wrong — but it
*is* a behaviour change, so it is called out rather than buried.

**Repointing cannot strand a salesperson somewhere useless.** The failure the
prompt worried about does not occur.

## 2d. Verdict — **safe. Recommend proceeding.**

Scope:

| Step | Detail |
|---|---|
| 1 | [day1_queue_screen.dart:159](lib/features/sales/screens/day1_queue_screen.dart#L159) — `AppRoutes.installerPin` → `AppRoutes.staffPin` |
| 2 | [day2_queue_screen.dart:92](lib/features/sales/screens/day2_queue_screen.dart#L92) — same |
| 3 | Delete the `/installer/pin` route registration ([app_router.dart:387-392](lib/app_router.dart#L387-L392)) + its import |
| 4 | Delete `lib/features/installer/installer_pin_screen.dart` (361 lines) |
| 5 | Update the two router comments (they currently note `/installer/pin` is still live via the sales queues — that stops being true) |

**Test coupling: none.** `grep -rn "InstallerPinScreen\|installerPin" test/`
returns nothing, so no fixtures or widget tests pin the legacy screen.

**Estimate: ~30 minutes** including `flutter analyze` and the full suite.

**Do it after Decision 1, not before** — if the 6/7 gestures are also retired,
steps 3-5 land in the same commit as the `/sales/pin` and `/admin/pin`
housekeeping and you touch `app_router.dart` once instead of twice.

The payoff is the one you named at the start: after this, no orphaned screen
that looks like the real one survives. `InstallerPinScreen` is the last
lookalike, and this is what unblocks deleting it.

---
---

# IMPLEMENTATION PASS 2 — 2026-08-11

**Decisions (Tyler, 2026-08-11):** retire the 6/7 gestures; repoint the queue
bounce and delete `InstallerPinScreen`. Both landed in one pass — they both
touch `app_router.dart`. **Not deployed.**

## Net result

**The Settings surface now has NO staff entry at all.** All three hidden
gestures (5 installer / 6 sales / 7 admin) are gone. Staff enter exclusively via
the login-screen logo 5-tap → `/staff/pin`, which handles all four roles.

## Files changed (6) + deleted (2)

| File | Change |
|---|---|
| [settings_page.dart](lib/features/site/settings_page.dart) | `_SalesModeEntry` → `ConsumerWidget`, gesture stripped, **exit branch kept**. `_AdminModeEntry` → `StatelessWidget`, reduced to a plain copyright line. Footer comment rewritten. Dropped the now-unused `admin_providers.dart` import. |
| [app_router.dart](lib/app_router.dart) | Deleted the `/installer/pin` and `/admin/pin` routes, their two imports, and both `AppRoutes` constants. Two comments corrected. |
| [day1_queue_screen.dart](lib/features/sales/screens/day1_queue_screen.dart) | Bounce repointed `installerPin` → `staffPin`. |
| [day2_queue_screen.dart](lib/features/sales/screens/day2_queue_screen.dart) | Same. |
| ~~`installer_pin_screen.dart`~~ | **DELETED** (361 lines) |
| ~~`admin/admin_dashboard_screen.dart`~~ | **DELETED** (248 lines) |

## What was KEPT, and why

**The sales exit branch survives.** `_SalesModeEntry` still renders "Sales Mode
Active / Tap to exit" when `salesModeActiveProvider` is true, calling
`exitSalesMode()`. An exit is not an entry; it renders only once a real minted
token exists, and removing it would strand an active sales session in Settings.
Same treatment the installer tile got.

**The admin tile had no exit to keep.** Its active branch pushed
`AppRoutes.corporateDashboard` — a *navigation*, not an exit. Admin sessions end
via `AdminModeNotifier.signOut()`
([admin_providers.dart:131](lib/features/installer/admin/admin_providers.dart#L131))
or the 30-minute idle timer, neither of which was reachable from that tile. So
`_AdminModeEntry` was reduced to the plain copyright line it was disguised as.

The version readout, the "Powered by Nex-Gen" footer and the copyright line are
all preserved as plain, non-interactive text. Visually the Settings footer is
unchanged.

## Orphan check — one deletion was a trap, exactly as warned

You flagged that `InstallerPinScreen` looked orphaned and wasn't. **The same
trap fired again, on `/sales/pin`:**

| Route | Callers after gesture removal | Action |
|---|---|---|
| `/installer/pin` | none (router only) | **deleted** |
| `/admin/pin` | none (router only) | **deleted** |
| `/sales/pin` | **`sales_landing_screen.dart:21`** — bounces here on sales-session expiry | **KEPT** |

`/sales/pin` and `SalesPinScreen` are still live. Had they been deleted with the
6-tap, an expiring sales session would have bounced to a dead route.

**A second, quieter find:** `admin_dashboard_screen.dart` (248 lines) contained
**only** `AdminPinScreen` — there is no `AdminDashboardScreen` class in it. The
dashboard was already removed by `81f87b4` ("retire admin dashboard"), which
left the file misnamed and half-empty. Deleting `/admin/pin` orphaned the whole
file, so the file went too.

Neither deleted screen had any test coupling — re-confirmed immediately before
deleting; `grep` over `test/` returns nothing for `InstallerPinScreen`,
`AdminPinScreen`, `AppRoutes.installerPin`, `AppRoutes.adminPin`.

## Comments corrected

- **Settings footer** — now states plainly that there is no staff entry on the
  screen, names all three retired gestures, and records *why* (every one of them
  logged a signed-in customer out of their own account), so the pattern doesn't
  regrow. No cross-references to sibling gesture counts survive.
- **`/staff/pin` registration** — now records that `/installer/pin` and
  `/admin/pin` were deleted and that **only `/sales/pin` survives, because
  `sales_landing_screen.dart` still bounces to it**. The earlier "do not
  re-assert 'only one' entry" warning about the visible `/link-account` panel is
  retained — that panel is still live.
- **Day 1 / Day 2 queue gates** — each now explains that the bounce is an
  idle-timeout net rather than a login path, and why the destination changed.
- **Router queue-route comment** (`app_router.dart:536`) — `installerPin` →
  `staffPin`.

## ⚠️ FLAGGED, NOT FIXED — behaviour change for master-sales-PIN-only holders

Recorded per instruction rather than left to be discovered.

Someone holding **only the master sales PIN** who hits the Day 1 / Day 2 queue
gate:

- **Before:** `enterInstallerMode()` rejected the PIN → *"Incorrect PIN"* → dead end.
- **Now:** `/staff/pin` matches at branch 4 → sales mode → `context.go(salesLanding)`.

Arguably better — a valid PIN is no longer reported as invalid — but it **is** a
behaviour change. No redirect loop in either case: the `go` replaces the queue
screen rather than returning to it. The ordinary actor (an installer whose
session lapsed) is unaffected: per-installer PINs claim installer at branch 3,
before sales is reached.

## VERIFICATION

```
flutter analyze  → 0 errors, 0 warnings across all 4 modified files
                   (383 pre-existing project-wide infos untouched)
flutter test     → see result below
```

The `controller_facts_writer_test.dart` analyzer errors noted in the previous
pass have cleared on their own — that parallel-session work has since settled.

### Suite result

```
flutter test --exclude-tags hardware  → 2147 passed, 3 skipped, 1 failed
flutter test (everything)             → 2146 passed, 3 skipped, 3 failed
```

All three failures are pre-existing and unrelated — **2 hardware + 1 flaky**:

| Test | Why it fails | Mine? |
|---|---|---|
| `hardware/base_ladder_repair_live_test.dart` | `@Tags(['hardware'])`, live against `192.168.1.150`. *"rig should expose both channels: Expected ≥2, Actual 1"* — the known reboot-segment-collapse (`seglc [3,3]→[3]`). | No |
| second `hardware/` test | Same rig dependency; fails after the base-ladder test in the hardware block. | No |
| `features/wled/controller_facts_writer_test.dart` — *"both families share the SAME server timestamp"* | **Flaky, not broken.** Asserts exact equality of two `FieldValue.serverTimestamp()` values; failed by **0.5 ms** under full-suite load. Run in isolation it passes **21/21, three times consecutively**. Its imports are `controller_facts_publisher` / `controller_facts_writer` / the denormalizers — none of which this change touches. Belongs to the parallel session's controller-facts work, since committed. | No |

**Not deployed**, per instruction.

---

## ADDENDUM — index restore, 2026-08-11

The two staged deletions were unstaged by a cross-window index restore
(participation window, `a712180`) and the files came back as tracked. Verified
on return and **re-staged**; both are gone from disk and staged as `D` again.

The interim state was safe: neither restored file referenced anything this
refactor deleted. `admin_dashboard_screen.dart`'s only `AppRoutes` use was
`corporateDashboard` (still present), and `installer_pin_screen.dart` navigated
by string literal (`'/installer/wizard'`), not by the removed
`AppRoutes.installerPin` constant. So the tree compiled throughout. The six
modified files and this audit were untouched.

### One dangling reference found and fixed on the way back

[sales_pin_screen.dart:11](lib/features/sales/screens/sales_pin_screen.dart#L11)
documented itself as *"Mirrors installer_pin_screen.dart exactly in structure
and style"* — a pointer to a file this refactor deleted. Since `/sales/pin` is
the one legacy PIN route that **survives**, that comment would have sent the
next reader to a file that no longer exists.

Rewritten to state what is actually true: the screen is reached only from
`SalesLandingScreen`'s session-expiry bounce, it is not a login path, and **if
that bounce is ever repointed at `/staff/pin` the way the Day 1 / Day 2 queue
gates were, this screen becomes orphaned and should follow the other two out.**
That is the remaining thread on this refactor.
