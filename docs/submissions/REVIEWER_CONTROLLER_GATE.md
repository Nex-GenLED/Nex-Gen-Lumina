# Reviewer Controller Gate — Dashboard force-navigates to "Add Controller"

**Date:** 2026-04-21
**Observed symptom:** reviewer signs in, router correctly takes them to `/dashboard` (route-guards race fix from prior prompt is working), but within ~1 frame the app force-navigates to the WLED manual-setup / "Add Controller" screen. Backing out lands on the correctly populated demo home.

**TL;DR:** [wled_dashboard_page.dart:143](lib/features/dashboard/wled_dashboard_page.dart#L143) schedules a post-frame callback that queries the `users/{uid}/controllers` Firestore **subcollection**; if empty, it pushes `AppRoutes.wifiConnect` (the Add Controller screen). `ReviewerSeedService.seedForUser()` writes the user doc, the installation doc, and `controllerSerials` as a field — but **never writes any document into the `users/{uid}/controllers` subcollection**. Gap is an unpopulated subcollection the dashboard treats as "no controllers exist yet."

---

## STEP 1 — The Add Controller route target

**Destination:** `AppRoutes.wifiConnect` → `'/wifi-connect'` ([app_router.dart:1000](lib/app_router.dart#L1000))

**Route → widget binding** ([app_router.dart:284-289](lib/app_router.dart#L284-L289)):

```dart
GoRoute(
  path: AppRoutes.wifiConnect,
  name: 'wifi-connect',
  parentNavigatorKey: _rootNavigatorKey,
  pageBuilder: (context, state) =>
      MaterialPage(fullscreenDialog: true, child: const WledManualSetup()),
),
```

**Screen widget:** `WledManualSetup` at [lib/features/ble/wled_manual_setup.dart](lib/features/ble/wled_manual_setup.dart) — this is the "Add a controller by IP / WiFi provisioning" dialog the reviewer is landing on.

Note: there is also `AppRoutes.controllerSetupWizard` = `/setup/wizard` → `ControllerSetupWizard` at [app_router.dart:279-283](lib/app_router.dart#L279-L283), and `AppRoutes.deviceSetup` = `/device-setup`. Neither is the one being auto-pushed from the dashboard. The dashboard uses `wifiConnect` specifically.

---

## STEP 2 — Call sites that navigate to `AppRoutes.wifiConnect`

Single call site found in the app:

| File:line | Function | Condition | Nav method |
|---|---|---|---|
| [lib/features/dashboard/wled_dashboard_page.dart:173](lib/features/dashboard/wled_dashboard_page.dart#L173) | `_checkControllersAndMaybeLaunchWizard()` | `snap.docs.isEmpty && mounted` (controllers subcollection empty) | `context.push(AppRoutes.wifiConnect)` |

No other widget pushes or goes to `wifiConnect`. This is the sole auto-navigation trigger, and it fires from `initState` via `addPostFrameCallback` on first frame.

---

## STEP 3 — Dashboard first-frame behavior

[wled_dashboard_page.dart:135-144](lib/features/dashboard/wled_dashboard_page.dart#L135-L144):

```dart
@override
void initState() {
  super.initState();
  _luminaSpeech = stt.SpeechToText();
  _skyRefreshTimer = Timer.periodic(
    const Duration(minutes: 1),
    (_) => setState(() {}),
  );
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkControllersAndMaybeLaunchWizard());
}
```

The post-frame callback at [wled_dashboard_page.dart:161-178](lib/features/dashboard/wled_dashboard_page.dart#L161-L178):

```dart
Future<void> _checkControllersAndMaybeLaunchWizard() async {
  if (_checkedFirstRun || _pushedSetup) return;
  _checkedFirstRun = true;
  try {
    final current = GoRouter.of(context).routerDelegate
        .currentConfiguration.uri.toString();
    if (!current.startsWith(AppRoutes.dashboard)) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final col = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('controllers');
    final snap = await col.limit(1).get();        // ← reads subcollection
    if (snap.docs.isEmpty && mounted) {
      _pushedSetup = true;
      context.push(AppRoutes.wifiConnect);         // ← auto-navigate
    }
  } catch (e) {
    debugPrint('First-run controller check failed: $e');
  }
}
```

**What it reads:**
- Firestore path: `users/{currentUser.uid}/controllers` **subcollection**
- Query: `.limit(1).get()` — just checks whether any doc exists

**Navigation condition:** if subcollection is empty AND widget is still mounted → push `/wifi-connect`.

**Guards against re-entry:** `_checkedFirstRun` and `_pushedSetup` flags. These reset on widget dispose (i.e. every time the dashboard is rebuilt fresh, e.g. after a cold start).

---

## STEP 4 — What `ReviewerSeedService.seedForUser()` actually writes

Full write inventory from [lib/services/reviewer_seed_service.dart:31-127](lib/services/reviewer_seed_service.dart#L31-L127):

### Write 1 — user profile doc
**Path:** `users/{user.uid}` (top-level doc, not a subcollection parent)
**Line:** [reviewer_seed_service.dart:86-89](lib/services/reviewer_seed_service.dart#L86-L89)
**Contents:** Full `UserModel` serialized to JSON, including:
- `installation_id: 'reviewer-installation-001'` (a field referencing the installation doc)
- `installation_role: 'primary'`
- `welcome_completed: true`
- `sports_teams`, `roofline_mask`, `timezone`, preferences, etc.

### Write 2 — installation doc
**Path:** `installations/reviewer-installation-001` (top-level collection)
**Line:** [reviewer_seed_service.dart:98-120](lib/services/reviewer_seed_service.dart#L98-L120) (conditional — only if doc doesn't already exist)
**Contents:**
- `primaryUserId: uid`
- `controllerSerials: ['DEMO-CTRL-001']` — **a string array FIELD, not a subcollection**
- `systemConfig.linkedControllerIds: ['DEMO-CTRL-001']` — **another string array FIELD**
- Address, dealer codes, warranty, etc.

### What the seed does **NOT** write

- `users/{uid}/controllers/{docId}` — **this subcollection is never touched**
- `installations/{id}/controllers/{docId}` — also not touched
- Any top-level `controllers/{id}` doc

The seed expresses "which controllers belong to this reviewer" only as a string array of serials on the installation doc. The app's canonical source of truth for controllers, per [lib/models/controller_model.dart:6](lib/models/controller_model.dart#L6) and every write site (discovery, installer setup, controllers_providers — all writing to `users/{uid}/controllers/{docId}`), is the **subcollection** under the user doc.

### Cross-reference: every write to `users/{uid}/controllers` in the app

| File:line | Context |
|---|---|
| [lib/features/discovery/device_discovery.dart:122, 132](lib/features/discovery/device_discovery.dart#L122) | mDNS discovery saves found devices here |
| [lib/features/installer/screens/controller_setup_screen.dart:75, 517](lib/features/installer/screens/controller_setup_screen.dart#L75) | Installer adds controllers during setup wizard |
| [lib/features/installer/installer_setup_wizard.dart:502, 506](lib/features/installer/installer_setup_wizard.dart#L502) | Installer setup |
| [lib/features/site/controllers_providers.dart:28, 68, 86](lib/features/site/controllers_providers.dart#L28) | User-facing controller CRUD |

None of these run for the reviewer — the reviewer never goes through BLE discovery, installer setup, or manual add. So the subcollection stays empty.

---

## STEP 5 — The gap

**Dashboard reads:** `users/{uid}/controllers` subcollection — expects **at least one doc**.
**Seed writes:** field-level `controllerSerials` array on the installation doc. **Zero subcollection docs.**

This is a **field-vs-subcollection mismatch**, not a provider staleness or cache issue. The data the seed writes and the data the dashboard reads are in completely different Firestore locations. Even if the reviewer refreshes the app 100 times, the subcollection will stay empty and the force-navigation to `/wifi-connect` will fire on every cold dashboard render.

Other hypotheses ruled out:

| Hypothesis | Verdict |
|---|---|
| Local device state (SharedPreferences, Hive) | Not involved. The check is a direct Firestore query with no local-cache guard. |
| Provider hasn't refreshed | Not involved. `_checkControllersAndMaybeLaunchWizard` doesn't use Riverpod at all — it calls `FirebaseFirestore.instance` directly. A fresh `.get()` always goes to the server (or cache, but either way reads the real state). |
| Seed writes but to wrong UID | Seed now writes under `FirebaseAuth.currentUser.uid` (fixed in Prompt 4). The user-doc write correctly matches the auth UID. The missing piece is the *subcollection*. |
| Race with seed commit | The prior fix made `seedForUser` the sole writer under `users/{uid}`. But the dashboard queries a subcollection the seed never writes, so there's no race — it's structurally empty. |

### Observed sequence for the reviewer

1. Reviewer signs in → `_handleSignIn` awaits `seedForUser(user)`.
2. `seedForUser` writes `users/{uid}` (profile) and `installations/reviewer-installation-001`. **Does not touch `users/{uid}/controllers`.**
3. `_handleSignIn` calls `context.go(AppRoutes.dashboard)`.
4. `appRedirect` reads `users/{uid}`, sees `installation_role: 'primary'`, allows `/dashboard`. Dashboard renders.
5. `WledDashboardPage.initState` schedules `_checkControllersAndMaybeLaunchWizard` post-frame.
6. Post-frame callback queries `users/{uid}/controllers` → **empty** → `context.push(AppRoutes.wifiConnect)`.
7. User sees Add Controller screen. Backing out returns to the populated dashboard behind it (which is why the dashboard data looks correct when dismissed).

---

## Recommended fix (for the next prompt, not this one)

Two viable approaches:

### Option A — seed a demo controller doc (preferred)

Add a third write in `ReviewerSeedService.seedForUser()` that creates a demo controller under `users/{uid}/controllers/demo-ctrl-001`:

```dart
await FirebaseFirestore.instance
    .collection('users').doc(uid)
    .collection('controllers').doc('demo-ctrl-001')
    .set({
  'id': 'demo-ctrl-001',
  'serial': 'DEMO-CTRL-001',
  'name': 'Front Roofline',
  'ip': '192.168.50.91',            // memory: Tyler's home controller
  'isOnline': true,
  'installationId': reviewerInstallationId,
  'createdAt': Timestamp.now(),
  // ...whatever ControllerModel.toJson() shape requires — verify against
  // lib/models/controller_model.dart before writing so field names match
  // what controllers_providers.dart and the dashboard read.
});
```

**Advantages:**
- Reviewer account looks indistinguishable from a real user with one controller
- The populated dashboard's "controllers list" / "status" widgets will render meaningful data instead of empty state
- No logic change in `wled_dashboard_page.dart` — the existing first-run guard continues to protect real first-time users
- Idempotent (seed's top-level `if (doc.exists) return;` guards the whole seed; if we want the controller write to be independently idempotent, add a `.get()` guard on the controller doc specifically)

**Caveats:**
- Must read `lib/models/controller_model.dart` to match the exact field names `controllers_providers.dart` and the dashboard widgets read — otherwise the doc exists but renders blank or crashes
- Should probably also seed any `linked_controllers` / `property_areas` state used by residential mode, because the dashboard's "lights" list and power toggles may read from those providers too
- Because `DemoWledRepository` is selected via `isReviewer(user)` in `wled_providers.dart`, the reviewer's HTTP calls go to mock — so the IP doesn't need to be reachable. Any placeholder IP is fine.

### Option B — gate the check on reviewer email

Add a reviewer escape hatch at [wled_dashboard_page.dart:162](lib/features/dashboard/wled_dashboard_page.dart#L162):

```dart
Future<void> _checkControllersAndMaybeLaunchWizard() async {
  if (_checkedFirstRun || _pushedSetup) return;
  _checkedFirstRun = true;
  if (ReviewerSeedService.isReviewer(FirebaseAuth.instance.currentUser)) {
    return; // reviewer flow uses demo repo, not Firestore controllers
  }
  // ... rest unchanged
}
```

**Advantages:**
- One-line fix, minimal risk
- Mirrors the pattern used in `route_guards.dart` for the same account

**Caveats:**
- Other dashboard widgets that read `users/{uid}/controllers` (e.g. the controllers list widget, status badges, power-state indicators) may still show empty state for the reviewer. The force-navigation stops, but the UI could still look bare unless the demo repo / providers handle the empty subcollection gracefully.
- Accumulates more reviewer-special-case branching across the codebase (already have 3 in route_guards.dart + 1 in wled_providers.dart). Each one is a place a future refactor could forget to update.

### Recommendation

**Option A.** The reviewer should look like a real fully-configured user — that's the whole point of the seed. Option B is a patch that treats the symptom; Option A fixes the root cause by making the seed complete.

A combination (Option A plus Option B as a safety net) would also be reasonable if you want defense-in-depth on the navigation specifically.
