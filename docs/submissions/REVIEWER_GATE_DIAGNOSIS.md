# Reviewer Gate Diagnosis — `reviewer@Nex-GenLED.com` lands on `/link-account`

**Date:** 2026-04-21
**Build under test:** commit `2bd3b50` (tag `v1.0.0-submission-1`), `app-release.apk` 90.5 MB
**Observed symptom:** reviewer signs in successfully, but is routed to "Welcome to Lumina — This app requires a Nex-Gen LED lighting system" (the `LinkAccountScreen` invitation-code gate), not the populated reviewer home.

---

## STEP 1 — Login flow

[lib/features/auth/login_page.dart:104-128](lib/features/auth/login_page.dart#L104-L128) — `_handleSignIn()`:

**(a) Sequence after successful auth:**

```dart
await auth.signInWithEmailAndPassword(email, pass);   // L111
final signedIn = FirebaseAuth.instance.currentUser;   // L115
if (ReviewerSeedService.isReviewer(signedIn)) {       // L116
  await ReviewerSeedService.seedForUser(signedIn!);   // L117  (AWAITED)
}
if (!mounted) return;                                  // L119
context.go(AppRoutes.dashboard);                       // L120
```

**(b) `isReviewer(user)` call site:** [login_page.dart:116](lib/features/auth/login_page.dart#L116). Case-insensitive email compare against `'reviewer@Nex-GenLED.com'` — **should return `true`** for the reviewer.

**(c) `seedForUser(user)` call site:** [login_page.dart:117](lib/features/auth/login_page.dart#L117). **Awaited** — `_handleSignIn` does not advance to `context.go()` until `seedForUser` returns.

**(d) Post-login navigation:** [login_page.dart:120](lib/features/auth/login_page.dart#L120) — `context.go(AppRoutes.dashboard)` (GoRouter top-level replace, not push).

---

## STEP 2 — Post-login router / gate logic

[lib/route_guards.dart:45-255](lib/route_guards.dart#L45-L255) — `appRedirect()`, attached to GoRouter via `refreshListenable: AuthStateListenable()` at [app_router.dart:131, 149](lib/app_router.dart#L131). `AuthStateListenable` (defined at [route_guards.dart:12-18](lib/route_guards.dart#L12-L18)) subscribes to `FirebaseAuth.instance.authStateChanges()` and notifies the router on every auth event — **this fires the moment sign-in completes, independent of what `_handleSignIn` does next.**

**(a) Field that decides gate vs. home:**

Two separate checks read **`installation_role`** (snake_case) from the user doc:

1. [route_guards.dart:119-141](lib/route_guards.dart#L119-L141) — when the current route is an auth route (`/login`), the redirect reads `users/{uid}`:
   - **If doc exists** with role `'installer'`/`'admin'` → `/dashboard`.
   - **If doc exists** with any other role (including `'primary'`, `'subUser'`, `'unlinked'`, or `null`) → falls through to line 141 and returns `/dashboard`.
   - **If doc does NOT exist** → [line 134-137](lib/route_guards.dart#L134-L137):
     ```dart
     } else {
       await createUnlinkedUserProfile(user);
       return AppRoutes.linkAccount;
     }
     ```
2. [route_guards.dart:216-249](lib/route_guards.dart#L216-L249) — on protected routes (e.g. `/dashboard`):
   - `role == 'admin' || 'installer'` → allow
   - `role == null || role == 'unlinked'` → **redirect to `/link-account`**
   - `'primary'` / `'subUser'` → allow

**(b) Firestore path read:** `users/{user.uid}` — same collection and doc-id convention as `seedForUser` writes to.

**Critical side effect:** the auth-route branch (#1 above) doesn't just redirect — when the doc is missing, it **writes a skeleton profile** via `createUnlinkedUserProfile()` at [route_guards.dart:21-41](lib/route_guards.dart#L21-L41):

```dart
await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
  UserService.sanitizeForFirestore({
    ...
    'installation_role': 'unlinked',
    'welcome_completed': false,
  }),
  SetOptions(merge: true),   // <-- merge mode
);
```

This is the race participant that breaks the reviewer flow.

---

## STEP 3 — `ReviewerSeedService.seedForUser(user)` mechanics

[lib/services/reviewer_seed_service.dart:31-127](lib/services/reviewer_seed_service.dart#L31-L127):

**(a) Firestore paths written:**
- `users/{user.uid}` — full reviewer `UserModel` via `.set(sanitizeForFirestore(model.toJson()))` at line 89.
- `installations/reviewer-installation-001` — if absent, at lines 98-121.

**(b) Fields written on the user doc** (via `UserModel.toJson()`):
Includes `installation_role: 'primary'` (from [user_model.dart:601](lib/models/user_model.dart#L601), serialized from `InstallationRole.primary.toJson()`), plus `welcome_completed: true`, `email`, `display_name: 'Demo Home'`, `installation_id`, `sports_teams`, `roofline_mask`, etc.

**Match against Step 2's field:** yes — seed writes `installation_role: 'primary'`, which [route_guards.dart:244](lib/route_guards.dart#L244) accepts as a valid logged-in state. If the seed wins the race, the reviewer would pass the gate.

**(c) Awaiting:**
- Top-level call from `_handleSignIn` is **awaited** (good).
- **But** internal `.get()` at line 34 and `.set()` at line 86 are sequential awaits in a Dart async function — they run on the Dart event loop and **do not block concurrently-running microtasks** (the auth-stream listener and GoRouter's redirect run in parallel).

**Idempotency guard:** [line 38](lib/services/reviewer_seed_service.dart#L38) — `if (doc.exists) return;`. If any other process wrote a doc at `users/{uid}` between the initial `.get()` and the `.set()`, seed still proceeds (it read "doesn't exist" before the other write landed). If the other process wrote BEFORE the `.get()`, seed skips entirely.

---

## STEP 4 — Live Firestore state

**Not readable programmatically from this environment.** This machine has no Firebase Admin SDK credentials and the Firestore database is live, not emulated.

**Manual verification Tyler needs to run in the Firebase Console:**

1. Open **Firebase Console → Authentication → Users** for project `icrt6menwsv2d8all8oijs021b06s5`. Find `reviewer@Nex-GenLED.com`. Copy the **User UID** from that row — call this `<REVIEWER_UID>`.
2. Open **Firestore → Data → `users` collection → doc `<REVIEWER_UID>`**.
3. Report:
   - Does the doc exist?
   - Value of `installation_role` field?
   - Value of `welcome_completed` field?
   - Value of `installation_id` field?
   - Is `roofline_mask` present (reviewer-specific field)?
   - Is `sports_teams` present with `['Chiefs', 'Royals']` (reviewer-specific field)?

4. Also check `installations/reviewer-installation-001` — does the doc exist, and is its `primaryUserId` equal to `<REVIEWER_UID>` or the legacy `'reviewer-demo-account-001'`?

**Expected findings (based on the race analysis below):**

| Field | If seed won | If `createUnlinkedUserProfile` won | If they collided |
|---|---|---|---|
| `installation_role` | `'primary'` | `'unlinked'` | **`'unlinked'`** (merge:true overwrites whichever wrote first) |
| `welcome_completed` | `true` | `false` | **`false`** (same reason) |
| `roofline_mask` | present | absent | **present** (not overwritten by skeleton) |
| `sports_teams` | present | absent | **present** |
| `display_name` | `'Demo Home'` | user's email prefix | depends on write order |

The **likely finding:** `installation_role == 'unlinked'`, `welcome_completed == false`, but reviewer-specific fields (`roofline_mask`, `sports_teams`, `install_id`) **are present** — a half-merged document. This pattern is diagnostic of the race described below.

---

## STEP 5 — Root cause

**Case (b) combined with a specific mechanism the prompt didn't enumerate: a writer–writer race against `createUnlinkedUserProfile()`.**

### Timeline

```
t=0   _handleSignIn:  await signInWithEmailAndPassword(...)
                      ↓ network round-trip
t=N   Auth internal state updates: FirebaseAuth.currentUser = reviewer
      Auth stream emission queued on microtask
      Future resolves → _handleSignIn resumes

t=N   _handleSignIn: isReviewer(signedIn) == true
t=N+  _handleSignIn: await seedForUser(signedIn!)
                     ↓ launches Firestore .get('users/<UID>') — goes to IO
                     _handleSignIn yields to event loop

      EVENT LOOP DRAINS MICROTASKS:
      └─ auth stream fires → AuthStateListenable.notifyListeners()
         └─ GoRouter reruns appRedirect for current route (/login)
            └─ appRedirect is async. Matched branch: isAuthRoute.
            └─ Launches Firestore .get('users/<UID>') — goes to IO

      Now TWO concurrent Firestore reads against the same doc.
      Both see "doc does not exist" (reviewer's first-ever login).

      Both proceed to WRITE:
      ├─ seedForUser.set(full reviewer model, installation_role='primary')
      └─ createUnlinkedUserProfile.set(skeleton, installation_role='unlinked',
                                       SetOptions(merge: true))

      Both writes land. LAST WRITE WINS (merge: true merges fields;
      overlapping fields get the later write's value).

      Because createUnlinkedUserProfile's payload is smaller, it often
      commits a few ms LATER than seedForUser's larger payload — landing
      on top and overwriting installation_role → 'unlinked'.

t=N+Δ appRedirect returns AppRoutes.linkAccount.
      Router navigates /login → /link-account. Login screen dismissed.

t=N+Δ' _handleSignIn: await seedForUser completes (doc was empty at read
      time, so it proceeded with the write). Returns to _handleSignIn.

t=N+Δ''_handleSignIn: context.go(AppRoutes.dashboard).
      Router runs appRedirect again for /dashboard.
      Reads users/<UID>. Doc now has installation_role='unlinked'.
      Line 239: role == 'unlinked' → return AppRoutes.linkAccount.

Final state: reviewer on /link-account. ← observed symptom.
```

### Why the explicit `await` doesn't save us

Awaiting a Future in Dart does **not** suspend the event loop — it only suspends the current async function. Microtasks enqueued during the wait (specifically, the auth-stream emission triggered by `signInWithEmailAndPassword`'s internal state update) run **concurrently** with the awaited chain. `GoRouter`'s `refreshListenable` fires on `notifyListeners()`, re-evaluates the current route (still `/login` at that moment), hits the `isAuthRoute` branch in `appRedirect`, and races `seedForUser` to the Firestore write.

### Why merge:true makes it worse, not better

`SetOptions(merge: true)` on `createUnlinkedUserProfile` means it doesn't clobber the whole doc — it stamps `installation_role: 'unlinked'` and `welcome_completed: false` onto whatever's there. If seed wrote first, the skeleton's fields overwrite the seed's role field. If skeleton wrote first, seed's `.set()` (without merge) would overwrite the whole doc — **except** that seed also has its own idempotency check at line 38: `if (doc.exists) return;` — so if the skeleton landed first, seed never even writes.

Result: **the reviewer cannot end up with `installation_role == 'primary'` under any ordering of the race winner.**

### Alternatives ruled out

| Case | Assessment |
|---|---|
| (a) `seedForUser` doesn't run | Unlikely. `isReviewer` compares `email.toLowerCase()` on both sides. Firebase Auth stores emails case-preserved-but-match-case-insensitive; `user.email` would return `'reviewer@Nex-GenLED.com'` (or similar) and `.toLowerCase()` normalizes both. Should match. Still worth verifying via a `debugPrint` in `_handleSignIn` or by reading logcat for `ReviewerSeedService: Reviewer account seeded for uid=...` — if that line is absent from logs, case (a) is the real culprit. |
| (c) Seed runs but writes wrong fields | Seed writes `installation_role: 'primary'` via `InstallationRole.primary.toJson()` at [user_model.dart:601](lib/models/user_model.dart#L601). `appRedirect` at [route_guards.dart:244](lib/route_guards.dart#L244) accepts `'primary'` as valid. Field name and value match — ruled out. |
| (d) Stale cache / Riverpod | Possible secondary effect. Firestore offline cache can serve a stale snapshot even after a fresh write. But the primary failure is the race — fix that first; cache issues would be a follow-up to investigate if the race fix doesn't fully resolve. |

---

## Recommended fix (for Prompt 7, not this one)

Three viable approaches, in order of preference:

1. **Make `createUnlinkedUserProfile` skip the reviewer email.** Add an early-exit in [route_guards.dart:21](lib/route_guards.dart#L21):
   ```dart
   if (ReviewerSeedService.isReviewer(user)) return;
   ```
   Then also gate the `/link-account` redirect at line 135 on non-reviewer:
   ```dart
   } else if (!ReviewerSeedService.isReviewer(user)) {
     await createUnlinkedUserProfile(user);
     return AppRoutes.linkAccount;
   }
   ```
   This prevents the race by letting `seedForUser` be the sole writer for the reviewer's doc, and makes `appRedirect` hold off redirecting to `/link-account` until the seed has committed. **Smallest blast radius** — localized to the reviewer email.

2. **Seed BEFORE sign-in completes surfacing to GoRouter.** Currently `auth.signInWithEmailAndPassword` triggers the auth stream before `_handleSignIn` resumes. Flip the ordering by signing in with a pattern that lets you prep the Firestore doc before the router redirects — e.g. sign in anonymously first, pre-seed the doc, then sign in with the real credentials. Invasive and brittle.

3. **Transactional write in `seedForUser` that detects and overwrites a just-written `'unlinked'` skeleton.** Fragile — hardcodes knowledge of the race.

Option 1 is the right call.

---

## TL;DR

The explicit `await ReviewerSeedService.seedForUser(user)` in `_handleSignIn` is correct but **insufficient**. Firebase Auth's state-change stream fires the moment `signInWithEmailAndPassword` resolves, which triggers GoRouter's `refreshListenable`, which runs `appRedirect`, which (on first-time reviewer login) sees a missing `users/<uid>` doc and calls `createUnlinkedUserProfile()` — writing `installation_role: 'unlinked'` on top of (or before) the seed. The reviewer's doc ends up with the unlinked role no matter who wins the race, and the subsequent `/dashboard` redirect kicks them back to `/link-account`.

**Fix requires teaching `appRedirect` / `createUnlinkedUserProfile` to recognize the reviewer email and either skip or defer.**
