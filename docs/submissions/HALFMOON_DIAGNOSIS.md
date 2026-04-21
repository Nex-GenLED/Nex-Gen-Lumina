# Half-Moon Roofline Regression — APPLE-REVIEW demo path

**Date:** 2026-04-21
**Build under test:** current working tree (uncommitted: Prompts 6/7/8 — route_guards, wled_dashboard_page, demo_code_screen)
**Observed symptom:** APPLE-REVIEW code → `demoPhoto` → "Use Sample Home Instead" → `demoRoofline` shows the stock home photo correctly, but the LED overlay renders as a **half-moon arc** instead of following the multi-gable roofline.

**TL;DR:** The APPLE-REVIEW bypass at [demo_code_screen.dart:77](lib/features/demo/demo_code_screen.dart#L77) goes `demoCode → demoPhoto`, **skipping `demoWelcome`**. `demoWelcome` is the **only caller** of `DemoSessionNotifier.startDemo()`, which is the **only place** `demoExperienceActiveProvider` gets set to `true`. Without that flag, both `currentRooflineConfigProvider` and `rooflineMaskProvider` fall through to their PRODUCTION branches. The reviewer's seeded user doc has a legacy `roofline_mask` field but **no `RooflineConfiguration` subdoc**, so the overlay gets a mask-only render (half-moon fallback) instead of the multi-segment polyline.

This is **case (a)** from the prompt's STEP 5 enumeration.

---

## STEP 1 — APPLE-REVIEW demo flow

### (a) `AppRoutes.demoPhoto` widget
- Route: `/demo/photo` ([app_router.dart:1107](lib/app_router.dart#L1107))
- Widget: `DemoPhotoScreen` at [lib/features/demo/demo_photo_screen.dart:22](lib/features/demo/demo_photo_screen.dart#L22)

### (b) "Use Sample Home" navigation
Two UI entry points on `DemoPhotoScreen` that both invoke `_useStockPhoto()`:
- `onSkip: _useStockPhoto` ([demo_photo_screen.dart:145](lib/features/demo/demo_photo_screen.dart#L145)) — the scaffold's skip button
- `TextButton.icon(onPressed: _useStockPhoto, ... label: 'Use Sample Home Instead')` ([demo_photo_screen.dart:306-310](lib/features/demo/demo_photo_screen.dart#L306-L310))

`_useStockPhoto()` at [demo_photo_screen.dart:93-109](lib/features/demo/demo_photo_screen.dart#L93-L109):

```dart
Future<void> _useStockPhoto() async {
  final stockConfig = await DemoStockHome.load();          // parses JSON trace
  ref.read(demoUsingStockPhotoProvider.notifier).state = true;
  ref.read(demoPhotoProvider.notifier).state = null;
  ref.read(demoRooflineConfigProvider.notifier).state = stockConfig;  // ← writes demo config
  _continueToNext();
}

void _continueToNext() {
  ref.read(demoFlowProvider.notifier).goToStep(DemoStep.rooflineSetup);
  context.push(AppRoutes.demoRoofline);
}
```

### (c) Subsequent demo home screen
- Route: `/demo/roofline` ([app_router.dart:1108](lib/app_router.dart#L1108))
- Widget: `DemoRooflineScreen` at [lib/features/demo/demo_roofline_screen.dart:19](lib/features/demo/demo_roofline_screen.dart#L19)

### (d) Roofline preview widget
- Stock photo renders via `Image.asset(DemoStockHome.imageAssetPath, ...)` at [demo_roofline_screen.dart:67-71](lib/features/demo/demo_roofline_screen.dart#L67-L71).
- Overlay renders via `AnimatedRooflineOverlay` at [demo_roofline_screen.dart:84-90](lib/features/demo/demo_roofline_screen.dart#L84-L90) — **this is the widget producing the half-moon**.
- Overlay implementation: [lib/widgets/animated_roofline_overlay.dart:106](lib/widgets/animated_roofline_overlay.dart#L106):
  ```dart
  final rooflineConfig = ref.watch(currentRooflineConfigProvider).valueOrNull;
  ```
  Plus at line 142:
  ```dart
  final mask = widget.mask ?? ref.watch(rooflineMaskProvider);
  ```

---

## STEP 2 — Non-reviewer flow comparison

The **normal (non-reviewer) dealer path** goes:
1. `demoCode` → `demoWelcome` ([demo_code_screen.dart:79](lib/features/demo/demo_code_screen.dart#L79))
2. `demoWelcome`: user taps "Start Demo" → [demo_welcome_screen.dart:211-216](lib/features/demo/demo_welcome_screen.dart#L211-L216):
   ```dart
   onPressed: () {
     ref.read(demoSessionProvider.notifier).startDemo();   // ← CRITICAL
     ref.read(demoFlowProvider.notifier).goToStep(DemoStep.profile);
     context.push(AppRoutes.demoProfile);
   }
   ```
3. `demoProfile` (lead capture) → `demoPhoto`
4. `demoPhoto` → `demoRoofline`

**The APPLE-REVIEW path skips step 2 entirely.** `startDemo()` is never called, so `demoExperienceActiveProvider` remains `false`.

### What `startDemo()` does
[demo_providers.dart:252-276](lib/features/demo/demo_providers.dart#L252-L276):

```dart
void startDemo() {
  // Reset all demo state
  ref.read(demoFlowProvider.notifier).reset();
  ref.read(demoLeadProvider.notifier).state = null;
  ref.read(demoRooflineNotifierProvider.notifier).clear();
  ref.read(demoPhotoProvider.notifier).state = null;
  ref.read(demoUsingStockPhotoProvider.notifier).state = false;
  ref.read(demoRooflineConfigProvider.notifier).state = null;
  // ...

  // Mark demo as active
  ref.read(demoExperienceActiveProvider.notifier).state = true;   // ← THE FLAG
  state = true;

  final leadService = ref.read(demoLeadServiceProvider);
  DemoAnalytics.init(leadService);
  DemoAnalytics.trackDemoStart();
}
```

Two things matter for the half-moon bug:
1. Sets `demoExperienceActiveProvider = true` (makes the demo-aware providers read from demo state).
2. Calls `ref.read(demoRooflineNotifierProvider.notifier).clear()` — clears residual state from a prior demo session. Not relevant to our bug since we haven't run a prior session, but noted.

### Grep: `startDemo` call sites
Exactly one:
- [lib/features/demo/demo_welcome_screen.dart:213](lib/features/demo/demo_welcome_screen.dart#L213) — the only place it runs.

---

## STEP 3 — Demo roofline data loader

### (a) Loader file
[lib/features/demo/demo_stock_home.dart](lib/features/demo/demo_stock_home.dart) — `DemoStockHome.load()` at line 19.

### (b) Invocation site
[demo_photo_screen.dart:96](lib/features/demo/demo_photo_screen.dart#L96) — called inside `_useStockPhoto()` when the user taps "Use Sample Home Instead". This path **is** reached by the APPLE-REVIEW flow.

### (c) Provider written
Writes to `demoRooflineConfigProvider` ([demo_photo_screen.dart:99](lib/features/demo/demo_photo_screen.dart#L99)):
```dart
ref.read(demoRooflineConfigProvider.notifier).state = stockConfig;
```

This provider is defined at [demo_providers.dart:43-44](lib/features/demo/demo_providers.dart#L43-L44):
```dart
final demoRooflineConfigProvider =
    StateProvider<RooflineConfiguration?>((ref) => null);
```

### (d) Does the APPLE-REVIEW path touch the loader?
**Yes — the loader runs correctly and writes the stock config.** That's confirmed by:
- `_useStockPhoto()` is on the APPLE-REVIEW path (user literally tapped the button on `demoPhoto`).
- The stock home photo renders on `demoRoofline` (per observed symptom — photo is correct, only overlay is wrong).
- `DemoRooflineScreen` reads `demoRooflineConfigProvider` at line 31 and correctly computes `hasConfig == true` (that's why the screen's subtitle says "Here's how Nex-Gen LEDs will follow your roofline" and the "Continue to Preview" button is enabled).

**So `demoRooflineConfigProvider` has the right data. The problem is that the consumer (`AnimatedRooflineOverlay`) doesn't read that provider directly — it reads `currentRooflineConfigProvider`, which is demo-aware but gated on `demoExperienceActiveProvider`.**

---

## STEP 4 — Roofline preview / half-moon rendering

### (a) Widget producing the half-moon
`AnimatedRooflineOverlay` at [lib/widgets/animated_roofline_overlay.dart](lib/widgets/animated_roofline_overlay.dart), specifically the `RooflineLightPainter` invoked at line 178-198.

### (b) Why it renders a half-moon
The painter takes two data inputs:
- `segmentPaths: List<SegmentPathData>?` — built from `currentRooflineConfigProvider.segments` (line 161-173). **Only populated when `hasSegments == true`**, which requires the config stream to return a non-null `RooflineConfiguration` with at least one segment of ≥2 points.
- `mask: RooflineMask?` — from `rooflineMaskProvider` (line 142). A single legacy polyline, no segment/channel metadata.

When `segmentPaths != null`, the painter traces the actual polyline segments — multi-gable rendering. When `segmentPaths == null` and only `mask` is provided, the painter falls back to a legacy rendering mode. The painter's exact fallback wasn't inlined here (class `RooflineLightPainter` is in the same file but below the scope I read — it renders LEDs distributed along the legacy mask; with sparse/short mask points the LED distribution approximates an arc, i.e. the "half-moon"). **What matters for the root cause: the fallback path renders differently and poorly than the multi-segment path, which is what the reviewer observes.**

### (c) Data sources
- `currentRooflineConfigProvider` — defined at [lib/features/design/roofline_config_providers.dart:74-93](lib/features/design/roofline_config_providers.dart#L74-L93):
  ```dart
  final currentRooflineConfigProvider = StreamProvider<RooflineConfiguration?>((ref) {
    final isDemo = ref.watch(demoExperienceActiveProvider);
    if (isDemo) {
      final demoConfig = ref.watch(demoRooflineConfigProvider);
      return Stream.value(demoConfig);                              // ← demo branch
    }
    // PRODUCTION: stream from Firestore, requires authenticated user.
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return Stream.value(null);
    return rooflineConfigServiceProvider.streamConfiguration(user.uid);
  });
  ```

- `rooflineMaskProvider` — defined at [lib/features/ar/ar_preview_providers.dart:15-50](lib/features/ar/ar_preview_providers.dart#L15-L50):
  ```dart
  final rooflineMaskProvider = Provider<RooflineMask?>((ref) {
    final isDemo = ref.watch(demoExperienceActiveProvider);
    if (isDemo) {
      // synthesize a mask from first demo segment's points
      ...
    }
    // PRODUCTION: read from user profile.
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    return profile?.rooflineMask == null
        ? null
        : RooflineMask.fromJson(profile!.rooflineMask!);
  });
  ```

**Both providers are demo-aware, and both gate on the same flag.** When `demoExperienceActiveProvider == false`, both fall through to production, which for the reviewer means:
- `currentRooflineConfigProvider`: streams from `users/{uid}/roofline_config/config` (via `RooflineConfigService.streamConfiguration`). **No such doc exists for the reviewer** — the seed doesn't write a `RooflineConfiguration` subdoc (it only writes the legacy `roofline_mask` field on the user doc). Returns `null`.
- `rooflineMaskProvider`: reads `profile.rooflineMask` (legacy field). **The reviewer's seeded user doc has this** (the 9-point multi-gable polyline from [reviewer_seed_service.dart:69-83](lib/services/reviewer_seed_service.dart#L69-L83)). Returns the legacy mask.

### (d) What the painter sees on the APPLE-REVIEW path
- `hasSegments == false` (config is null)
- `mask == legacy 9-point mask` (from user profile)
- `segmentPaths == null`
- Painter falls back to mask-only rendering → half-moon arc approximation.

---

## STEP 5 — Root cause

**Case (a) from the prompt's enumeration** — the bypass skipped a screen (`demoWelcome`) that runs trace initialization. Specifically, it skipped the **only `startDemo()` call site**, which is the only place `demoExperienceActiveProvider` gets set to `true`. Without that flag, the demo-aware providers can't route consumers to the demo-scoped config, even though `_useStockPhoto` writes the config into `demoRooflineConfigProvider` correctly.

### Case (b) ruled out as primary cause
The reviewer user doc does have `use_stock_house_image: false` by default (the seed doesn't set it, and `UserModel` defaults it to `false` at [user_model.dart:312](lib/models/user_model.dart#L312)). But `useStockImageProvider` / `houseImageUrlProvider` feed the **dashboard's** hero photo, not the demo roofline preview. The demo screen at [demo_roofline_screen.dart:67-71](lib/features/demo/demo_roofline_screen.dart#L67-L71) reads `usingStock` from `demoUsingStockPhotoProvider` (a local demo state provider), which `_useStockPhoto` correctly sets to `true`. The stock photo is rendering (confirmed by the user's observation — "Stock photo correct, half-moon overlay on top"). So (b) is not the cause of the half-moon.

That said, case (b) **is** a separate latent bug on the reviewer's dashboard: the seed's missing `useStockHouseImage: true` plus missing `house_photo_url` means the dashboard's hero image falls back to `assets/images/Demohomephoto.jpg` via a different code path ([wled_dashboard_page.dart:191](lib/features/dashboard/wled_dashboard_page.dart#L191)) — that one happens to do the right thing, so it's invisible. Worth noting but not actioning now.

### Case (c) considered
Not the primary cause. `roofline_mask` on the user doc **does** exist (seed writes it), but it's the legacy single-path mask, not the multi-segment config. The consumer (`AnimatedRooflineOverlay`) needs segments, not just a mask, to render the multi-gable polyline. Filling the gap by writing a `RooflineConfiguration` subdoc for the reviewer would be an alternative fix to #1 below but has much larger blast radius.

---

## Recommended fix (for the next prompt, not this one)

Two viable approaches:

### Option A — call `startDemo()` on the APPLE-REVIEW bypass path (preferred)
Modify [demo_code_screen.dart:67-80](lib/features/demo/demo_code_screen.dart#L67-L80):

```dart
if (result != null) {
  ref.read(validatedDemoCodeProvider.notifier).state = result;
  if (result.dealerCode == 'APPLE-REVIEW') {
    // Initialize demo session up-front — the normal flow does this
    // when the user taps "Start Demo" on demoWelcome, but the reviewer
    // bypass skips that screen. Without startDemo(), demoExperienceActive
    // stays false and the demo-aware providers (currentRooflineConfigProvider,
    // rooflineMaskProvider) fall through to production Firestore reads,
    // which have no RooflineConfiguration doc for the reviewer → overlay
    // renders the legacy half-moon fallback.
    ref.read(demoSessionProvider.notifier).startDemo();
    context.go(AppRoutes.demoPhoto);
  } else {
    context.go(AppRoutes.demoWelcome);
  }
}
```

**Pros:** one-line fix, targeted at the known-broken path, matches the architectural intent of `startDemo()` as the canonical demo-mode entry.
**Cons:** minor duplication — demoWelcome's button also calls `startDemo()`, but that path isn't hit by reviewers. Both calls are idempotent (`startDemo` resets state and sets the flag), so accidental double-invocation is safe.

### Option B — move `startDemo()` to `DemoCodeScreen` post-validation (for both paths)
Call `startDemo()` in `_validate()` for both paths:
```dart
if (result != null) {
  ref.read(validatedDemoCodeProvider.notifier).state = result;
  ref.read(demoSessionProvider.notifier).startDemo();      // both paths
  if (result.dealerCode == 'APPLE-REVIEW') {
    context.go(AppRoutes.demoPhoto);
  } else {
    context.go(AppRoutes.demoWelcome);
  }
}
```

Then the `demoWelcome` "Start Demo" button becomes a no-op second call (still safe — `startDemo` is idempotent).

**Pros:** removes a sequencing trap. `demoExperienceActiveProvider == true` is now true from the moment the user validates a code, meaning any future code path that navigates into a demo-aware screen will work regardless of entry point.
**Cons:** arguably changes semantics for the normal flow — the "Start Demo" button's `startDemo()` call becomes vestigial. Could either leave it (harmless) or remove it (requires touching demoWelcome too).

### Recommendation

**Option B.** It removes the class of bug where any future demo-flow entry point forgets to call `startDemo()`. The reviewer bypass we added yesterday is only the first such entry; any future dealer-specific or campaign-specific bypass would need the same reminder. Centralizing `startDemo()` at the first possible moment (post-validation) is the most defensive architecture.

If blast-radius concern: go with Option A now, migrate to Option B in a follow-up.
