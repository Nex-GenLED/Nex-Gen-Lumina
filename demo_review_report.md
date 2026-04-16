# Nex-Gen LED Demo Experience — Comprehensive Review

**Reviewer:** Claude Opus 4.6 | **Date:** 2026-04-16
**Scope:** Full demo flow code trace — `lib/features/demo/`, supporting providers, navigation, and main-app integration.

---

## Section 1 — Friction & Usability Issues

### 1.1 Progress Bar Shows 9 Steps but Only 5 Are Navigable

**Screen:** Every demo screen (via `DemoProgressBar` in `widgets/demo_progress_bar.dart`)
**File:** `demo_models.dart:5-15`, `demo_roofline_screen.dart:21`
**User experience:** The progress bar shows 9 step dots and labels (Welcome → Your Info → Your Home → Roofline → Preview → Schedule → Explore → Lumina → Get Started). The actual navigation path is Welcome → Profile → Photo → Roofline → Completion. After the Roofline screen (step 4/9), `_continueToNext` calls `goToStep(DemoStep.completion)` which is step 9/9. The progress bar jumps from 44% to 100% in one tap. The user watches slow steady progress for 4 screens, then the bar fills completely — it feels like they skipped something important or the demo broke.

**Severity:** High — breaks user trust in the flow, makes the demo feel unfinished or buggy.
**Recommended fix:** Either (a) remove the 4 phantom steps from `DemoStep` so the enum reflects the actual 5-screen flow, or (b) implement the missing screens (pattern preview, schedule preview, explore, Lumina guide) so the progress bar is accurate. Option (a) is a Small fix (~30 min). Option (b) is a Large effort (1+ day) but adds the "wow" moments that Section 2 identifies as missing. The right call depends on product intent — **question for Tyler: are steps 5-8 planned or abandoned?**
**Effort:** Small (option a) or Large (option b)

### 1.2 Profile Screen Blocks on Firestore Write Before Advancing

**Screen:** Profile (demo_profile_screen.dart)
**File:** `demo_profile_screen.dart:72-74`
**User experience:** Tapping "Continue" awaits `leadService.submitLead(lead)` which writes to Firestore. On a slow or absent network (trade show, poor signal), the spinner can run for 10+ seconds with no progress feedback. If the request fails, the user gets a red snackbar "Error saving profile: ..." — a raw exception message.

**Severity:** High — blocks the entire flow on a network round-trip. Dealers at trade shows with spotty WiFi will lose prospects.
**Recommended fix:** Fire the Firestore write asynchronously (fire-and-forget with `.catchError`), store the lead locally in the provider first, and advance immediately. Queue the write for retry later. The lead data is already stored in `demoLeadProvider` at line 70 before the network call — the Firestore write is supplemental, not gating.
**Effort:** Small (~45 min)

### 1.3 Demo Code Screen Allows Partial Submission

**Screen:** Demo Code Gate (demo_code_screen.dart)
**File:** `demo_code_screen.dart:49-54`
**User experience:** The code field has `maxLength: 6` (line 185) but `_validate()` only checks for empty input (line 51). A user who types "KC" and hits "Start Demo" gets a network round-trip to Firestore before learning the code is invalid. The shake animation and "Invalid code" error follow — but the wait was unnecessary.

**Severity:** Medium — wastes time and feels unresponsive, but not a blocker.
**Recommended fix:** Add a length check: `if (code.length < 6) { setState(() => _errorText = 'Code must be 6 characters'); return; }` before the network call.
**Effort:** Small (~15 min)

### 1.4 Email Validation Rejects Plus-Address Aliases

**Screen:** Profile (demo_profile_screen.dart)
**File:** `demo_profile_screen.dart:139`
**User experience:** The email regex `^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$` rejects `john+nex@gmail.com` and addresses with new TLDs longer than 4 characters (e.g., `.lighting`, `.company`). Tech-savvy prospects who use plus-aliases get blocked unnecessarily.

**Severity:** Low — affects a small percentage of users, but those users may be the most tech-engaged prospects.
**Recommended fix:** Use a more permissive regex or just check for `@` and a `.` after it. Email validation in a lead form should avoid false negatives.
**Effort:** Small (~15 min)

### 1.5 Photo Screen: Inconsistent Flow Between Custom Photo and Stock Photo

**Screen:** Photo Capture (demo_photo_screen.dart)
**File:** `demo_photo_screen.dart:93-109` (stock) vs `demo_photo_screen.dart:326-332` (custom)
**User experience:** When the user takes/uploads a photo, a "Continue" button appears at the bottom and they must tap it to advance. When the user taps "Use Sample Home Instead," the screen auto-navigates to the roofline screen — no second tap needed. The inconsistency isn't harmful, but if the user is comparing the two paths, the stock photo path feels more polished because it's faster.

**Severity:** Low — actually benefits the dealer use case (stock path is faster), but the inconsistency may confuse users who try both.
**Recommended fix:** Either auto-advance after photo capture + auto-detect completes, or show the "Continue" button for both paths. The current behavior is acceptable if intentional.
**Effort:** Small (~20 min if changed)

### 1.6 Photo Auto-Detect Has No User Feedback During Processing

**Screen:** Photo Capture (demo_photo_screen.dart)
**File:** `demo_photo_screen.dart:111-131`
**User experience:** After taking a photo, `_runAutoDetectFromBytes()` runs. During this time, `_isLoading` has already been set to false (the `finally` block at line 60 fires after photo capture completes but before auto-detect finishes, since auto-detect is a separate await). The user sees their photo but has no indication that roofline detection is running. If they tap "Continue" quickly, they advance to the roofline screen before detection finishes, potentially seeing an empty roofline.

**Severity:** Medium — can cause a confusing experience on the roofline screen (no overlay when one was expected).
**Recommended fix:** Keep `_isLoading = true` until auto-detect completes, or show a secondary indicator ("Detecting roofline...") overlaid on the photo.
**Effort:** Small (~30 min)

### 1.7 Roofline Screen Has No Bottom CTA When Detection Fails

**Screen:** Roofline Review (demo_roofline_screen.dart)
**File:** `demo_roofline_screen.dart:179-185`
**User experience:** When `hasConfig` is false (auto-detect failed), the `bottomAction` is `null` — no "Continue" button appears. The only way forward is "Use My Own Photo Instead" / "Retake Photo" (line 165-173) which goes BACK to the photo screen. A prospect who took a photo at dusk or from a bad angle is stuck in a loop with no way to continue the demo.

**Severity:** High — creates a dead end in the demo flow. The prospect gives up or a dealer has to awkwardly say "let's use the sample home."
**Recommended fix:** Show a "Continue Anyway" or "Skip to Preview" button when detection fails. The user should always be able to move forward, even without a roofline overlay. Alternatively, auto-fall back to the stock home config when detection fails.
**Effort:** Small (~30 min)

### 1.8 Completion Screen Contact Form Doesn't Validate Before Showing Error

**Screen:** Completion → Contact Form (demo_completion_screen.dart)
**File:** `demo_completion_screen.dart:52-58`
**User experience:** If the user taps "Submit Request" without selecting a contact method AND time, a SnackBar says "Please select your preferred contact method and time." This is correct, but the form provides no inline visual indication of which selections are missing. On a dark-themed screen with 6 selectable chips, the user has to figure out what they missed.

**Severity:** Low — validation works, but the UX could guide better.
**Recommended fix:** Highlight the unselected section headers in red or add a subtle pulse animation to the chips that need selection.
**Effort:** Small (~30 min)

### 1.9 DemoScaffold Back Button Calls previousStep() but Doesn't Pop the Route

**Screen:** All DemoScaffold screens
**File:** `widgets/demo_scaffold.dart:53-55`
**User experience:** The `onBack` callback in `DemoScaffold` calls `ref.read(demoFlowProvider.notifier).previousStep()` — this updates the Riverpod step state but doesn't call `context.pop()`. The actual route doesn't change. The user taps back, the progress bar updates, but they're still on the same screen. To actually go back, they'd need to use the system back gesture.

**Severity:** High — the back button appears functional but doesn't navigate. This will confuse every user who tries it.
**Recommended fix:** Add `Navigator.of(context).pop()` after `previousStep()`, or (better) change `onBack` to call `context.pop()` which handles both route and state. Each screen that uses `DemoScaffold` should handle its own back behavior since some screens use `context.push()` and some use `context.go()`.
**Effort:** Small (~30 min)

### 1.10 Demo Banner Clips Into Status Bar on Notched Phones

**Screen:** Main app scaffold during demo browsing
**File:** `main_scaffold.dart:237-286`
**User experience:** The `_DemoBanner` is a 44px container. `SafeArea(bottom: false)` is applied to the Row INSIDE it (line 245), but the container itself has no SafeArea wrapper. On phones with notches or Dynamic Island, the 44px container sits under the status bar. The SafeArea inset pushes the content down, but the gradient background doesn't extend to fill the notch area, leaving a visual gap.

**Severity:** Medium — looks broken on notched devices (most modern phones).
**Recommended fix:** Move the `SafeArea` to wrap the entire `_DemoBanner` container, or set the container height to `44 + MediaQuery.of(context).padding.top` and pad the content accordingly.
**Effort:** Small (~20 min)

---

## Section 2 — Conversion Gaps

### 2.1 Four "Wow" Moments Are Defined but Never Shown

**Description:** The welcome screen promises four experiences: visualize your home, explore 500+ patterns, smart scheduling, and Lumina AI. The `DemoStep` enum defines dedicated steps for pattern preview, schedule preview, explore patterns, and Lumina guide. But the actual navigation jumps from Roofline (step 4) directly to Completion (step 9). The user never sees a single pattern, schedule, or AI interaction during the guided demo.

**Current behavior:** After roofline, user lands on completion screen with hardcoded stats: "0 Patterns Viewed," "3 Schedules Previewed," "1 AI Session" — the latter two are lies (the user saw neither).
**Ideal behavior:** After roofline, show a curated pattern preview (3-5 patterns with live roofline overlay), then a schedule preview (auto-generated based on zip code), then optionally a Lumina AI teaser, then completion.

**Why it matters:** The demo currently sells the photo-to-roofline visualization, which is impressive but not differentiated. The pattern library, smart scheduling, and Lumina AI are the features that justify the premium price point. Without showing them, the demo is leaving 75% of its value on the table. A dealer saying "and there are 500+ patterns" is not the same as the prospect seeing their house lit up in Chiefs colors.

### 2.2 Completion Screen Stats Are Hardcoded and Inaccurate

**Description:** `demo_completion_screen.dart:263-273` shows three stat cards: patterns viewed (from provider — likely 0), "3 Schedules Previewed" (hardcoded, never actually shown), and "1 AI Session" (hardcoded, never used). Showing fabricated metrics undermines trust.

**Current behavior:** Stats claim the user previewed schedules and used AI, when they didn't.
**Ideal behavior:** Show only stats the user actually earned. If they viewed 0 patterns, say "Ready to explore 500+ patterns" instead of showing "0."

**Why it matters:** A sharp prospect or dealer will notice the discrepancy. It makes the product feel like it's overselling.

### 2.3 "Explore the App" Is the Primary CTA, Not "Request Consultation"

**Description:** On the completion screen, the layout order is: summary → "Explore the app" (FilledButton, cyan, full-width, line 279-315) → "Request Free Consultation" (inside a glass card, secondary position, line 329-361) → "Create Account" → "Return to Login." The conversion action (consultation) is below the fold on smaller devices and visually subordinate to "Explore the app."

**Current behavior:** The primary CTA sends the user into the app to browse. The conversion CTA is further down.
**Ideal behavior:** "Request Free Consultation" should be the primary CTA — it's the conversion event. "Explore the app" should be secondary. The consultation button should be in the `bottomAction` slot (pinned to bottom of screen) so it's always visible.

**Why it matters:** Every conversion funnel principle says the primary action should be the most prominent and first in the visual hierarchy. The current layout optimizes for app exploration, not lead conversion. Dealers want the prospect to book a consultation, not wander the app.

### 2.4 No Roofline Photo on the Completion Screen

**Description:** The completion screen shows a gradient circle with a celebration icon, text, and stat cards. It does not show the user's roofline photo with the light overlay — the most visually impressive moment from the demo.

**Current behavior:** Generic celebration screen with no personalized content.
**Ideal behavior:** Show the user's house photo with the animated roofline overlay as a hero image at the top of the completion screen. This is the "this is YOUR home" moment that triggers the emotional purchase decision.

**Why it matters:** The roofline visualization is the single most compelling thing the demo produces. Not showing it on the conversion screen is like a car dealer letting you test drive and then showing you a brochure instead of the car.

### 2.5 Lead Data Doesn't Include Dealer Attribution

**Description:** `DemoLead.toJson()` (demo_models.dart:238-252) does not include the dealer code or dealer name. The `validatedDemoCodeProvider` stores the `DealerDemoCode` and `demoDealerCodeProvider` in `app_providers.dart:33` stores the code, but neither is written into the lead document.

**Current behavior:** Leads appear in `demo_leads` collection without any indication of which dealer sent them.
**Ideal behavior:** The `DemoLead` should include `dealerCode`, `dealerName`, and `market` from the validated demo code, set during `_submitProfile`.

**Why it matters:** Without attribution, the sales team can't route leads to the originating dealer. Multi-dealer operations lose the tracking chain. This is a conversion infrastructure gap.

### 2.6 No Social Proof or Trust Signals

**Description:** The entire demo flow contains zero testimonials, review counts, installation photos, or trust badges. The welcome screen lists features but provides no evidence that other homeowners have chosen Nex-Gen.

**Current behavior:** Feature descriptions only.
**Ideal behavior:** Add at least one social proof element — e.g., "Trusted by 500+ homeowners in Kansas City" on the welcome screen, or a small testimonial on the completion screen.

**Why it matters:** Social proof is one of the strongest conversion levers. A prospect deciding whether to request a consultation needs reassurance that others have made the same choice.

### 2.7 Demo Doesn't Tell a Coherent Narrative Arc

**Description:** The current flow is: enter code → read features → fill form → take photo → see roofline → done. There's no story. A compelling demo would be: "Let's see your home lit up" (photo) → "Look at these possibilities" (patterns on YOUR roofline) → "It runs itself" (schedule) → "And an AI helps" (Lumina teaser) → "Ready to make it real?" (conversion). The current flow front-loads the data capture (profile before photo) and back-loads nothing.

**Current behavior:** Lead capture happens at step 2 of 5. The remaining 3 steps are photo, roofline, and completion. The prospect gives up their contact info before seeing anything impressive.
**Ideal behavior:** Show the value first (photo → roofline → patterns), then capture the lead when the prospect is emotionally invested.

**Why it matters:** Lead capture before value delivery creates friction and increases drop-off. The prospect is thinking "why am I giving you my phone number?" before they've seen what the product does.

---

## Section 3 — Dealer-Specific Concerns

### 3.1 Demo Code Validation Requires Network (Offline Fails)

**Description:** `DemoCodeService.validateCode()` (demo_code_service.dart:24-76) queries Firestore. At a trade show, outdoor event, or in a prospect's home with poor signal, this fails.

**Impact on pitch:** The dealer hands a phone to a prospect, says "enter this code" — and it spins forever. The pitch momentum dies.

**Fix recommendation:** Cache a list of valid demo codes locally (encrypted SharedPreferences or bundled asset) that syncs when online. Fall back to the local cache when Firestore is unreachable. Or: bypass code validation entirely if the app was launched with a dealer-mode flag.
**Effort:** Medium (2-3 hours)

### 3.2 Profile Screen Interrupts the Pitch Flow

**Description:** The profile screen requires the prospect to type their name, email, phone, and zip code. In a dealer pitch context, this is a 60-90 second interruption where the prospect is pecking at a keyboard instead of watching the demo. The dealer can't do it for them without awkwardly asking "what's your email?"

**Impact on pitch:** Breaks the pitch rhythm. The dealer wants to show the product, not watch the prospect fill out a form.

**Fix recommendation:** Add a "Skip for now" option on the profile screen that allows the demo to proceed without lead capture. Capture the lead at the end (completion screen) instead. This way, the dealer can show the full demo first and collect info when the prospect is already sold. Profile could pre-populate with the dealer code so attribution is preserved even without prospect info.
**Effort:** Small (~1 hour)

### 3.3 Stock Home Path Is Visually Subordinate

**Description:** On the photo screen, "Take Photo" is a full-width cyan `DemoPrimaryButton`. "Upload from Gallery" is a full-width outlined `DemoSecondaryButton`. "Use Sample Home Instead" is a small `TextButton.icon` below an "or" divider (demo_photo_screen.dart:306-309). Dealers will primarily use the stock home — it's faster, more reliable, and doesn't require camera permission.

**Impact on pitch:** The dealer's preferred path is the least prominent option on the screen. They have to scroll past two bigger buttons and an "or" divider to find it.

**Fix recommendation:** Elevate "Use Sample Home" to a `DemoSecondaryButton` (same prominence as gallery), or add a dealer-mode toggle that defaults to stock home. Consider making the three options equal-weight radio cards instead of a hierarchy.
**Effort:** Small (~30 min)

### 3.4 "Takes About 3 Minutes" Is Inaccurate

**Description:** The welcome screen (demo_welcome_screen.dart:235) says "Takes about 3 minutes." Tracing the actual flow: code entry (~15s) + welcome screen read (~20s) + profile form (~60-90s) + photo capture or stock selection (~15-30s) + roofline review (~15s) + completion screen (~30s). That's approximately 2.5-3.5 minutes for the guided flow. If the prospect also explores the app after tapping "Explore the app," that adds unlimited time.

**Impact on pitch:** The 3-minute claim is roughly accurate for the guided flow, which is good. However, if the prospect gets stuck on the profile form or photo screen, it can stretch to 5+ minutes.

**Fix recommendation:** The label is acceptable. If the profile skip is implemented (3.2), the flow drops to under 2 minutes, making the claim generous rather than tight.

### 3.5 Camera Permission Denial Has No Graceful Recovery

**Description:** If the prospect denies camera permission when tapping "Take Photo," the catch block at `demo_photo_screen.dart:54-58` shows a SnackBar: "Could not access camera: [error]." There's no guidance to use the gallery or stock home instead.

**Impact on pitch:** The prospect says "no" to camera, sees a cryptic error, and doesn't know what to do. The dealer has to intervene.

**Fix recommendation:** On camera permission denial, show a dialog: "No camera access? No problem — you can upload a photo from your gallery or use our sample home to see the full experience." Include buttons for both alternatives.
**Effort:** Small (~30 min)

### 3.6 No Way to Reset and Run Demo Again Without Restarting

**Description:** After completing a demo and exiting (via completion screen or exit sheet), there's no obvious way to restart the demo for the next prospect. The dealer has to navigate back to the login screen and tap "Try Demo" again, re-enter the code, and go through the full flow.

**Impact on pitch:** At a trade show, the dealer runs 20+ demos in a day. Each restart requires re-entering the code and waiting for Firestore validation.

**Fix recommendation:** After `exitDemoMode()` is called, offer a "Run demo again?" option that navigates to the welcome screen with the demo code pre-validated (skip the code screen). Or cache the validated code for the session.
**Effort:** Small (~45 min)

---

## Section 4 — Technical Issues & Risks

### 4.1 `currentRooflineConfigProvider` Is Not Demo-Aware — Overlay Won't Render

**File:** `features/design/roofline_config_providers.dart:65-76`
**Description:** `currentRooflineConfigProvider` is a `StreamProvider` that reads from Firestore based on `authStateProvider`. In demo mode, the user is NOT authenticated, so `user == null` and the provider returns `Stream.value(null)`. The `AnimatedRooflineOverlay` widget (`widgets/animated_roofline_overlay.dart:106`) reads from this provider. Result: `rooflineConfig` is null, `hasSegments` is false, and the overlay renders nothing.

The comment at `demo_roofline_screen.dart:79-81` says "currentRooflineConfigProvider is demo-aware as of Prompt 3" — but inspection of the provider code shows NO reference to `demoExperienceActiveProvider` or `demoRooflineConfigProvider`. The comment appears to describe a planned fix that was never implemented.

The `demoRooflineConfigProvider` (demo_providers.dart:43) stores the demo config correctly, but nothing bridges it to `currentRooflineConfigProvider`.

**Severity:** Critical — the roofline overlay is the core visual output of the demo. If it doesn't render, the user sees a photo with no lights. The entire demo value proposition fails.

**Recommended fix:** Add a demo-mode check at the top of `currentRooflineConfigProvider`:
```dart
final isDemoActive = ref.watch(demoExperienceActiveProvider);
if (isDemoActive) {
  final demoConfig = ref.watch(demoRooflineConfigProvider);
  return Stream.value(demoConfig);
}
```
**Effort:** Small (~15 min, but needs testing across all overlay consumers)

### 4.2 `demoStepProvider` and `demoFlowProvider` Are Dual Sources of Truth

**File:** `demo_providers.dart:17` (`demoStepProvider`) and `demo_providers.dart:144` (`demoFlowProvider`)
**Description:** Two separate providers track the current demo step: `demoStepProvider` (a simple `StateProvider<DemoStep>`) and `demoFlowProvider` (a `NotifierProvider<DemoFlowNotifier, DemoStep>`). All screen navigation uses `demoFlowProvider`, but `demoStepProvider` exists unused. `DemoSessionNotifier.startDemo()` resets `demoFlowProvider` but not `demoStepProvider`.

**Severity:** Low — `demoStepProvider` appears to be dead code, but its existence is confusing and a future maintenance trap.
**Recommended fix:** Remove `demoStepProvider` entirely. Grep for usages first — if none reference it outside of demo_providers.dart, delete it.
**Effort:** Small (~10 min)

### 4.3 Debug Print Statements in Production Code

**File:** `services/demo_code_service.dart:27,31,36,41,46,50,56,62,68,72`
**Description:** `DemoCodeService.validateCode()` has 10 `print()` calls with emoji prefixes (`🔍 DEMO:`) that are not guarded by `kDebugMode`. These will appear in release builds' console output, leaking internal implementation details and Firestore query results.

**Severity:** Medium — information leakage in production. Not a security vulnerability (the data is the user's own input), but unprofessional and violates the CLAUDE.md guideline: "Remove debug prints before production release."
**Recommended fix:** Wrap all print statements in `if (kDebugMode)` blocks or replace with `debugPrint()` (which is stripped in release mode).
**Effort:** Small (~15 min)

### 4.4 `exitDemoMode()` Doesn't Reset All Demo State

**File:** `app_providers.dart:39-46`
**Description:** `exitDemoMode()` resets `demoModeProvider`, `demoBrowsingProvider`, `demoDealerCodeProvider`, `hasShownDemoNudgeProvider`, `validatedDemoCodeProvider`, and `isDemoBrowsingFlag`. But it does NOT reset:
- `demoExperienceActiveProvider` (demo_providers.dart:14)
- `demoSessionProvider` (demo_providers.dart:302)
- `demoLeadProvider` (demo_providers.dart:21)
- `demoPhotoProvider` (demo_providers.dart:28)
- `demoRooflineConfigProvider` (demo_providers.dart:43)
- `demoPatternsViewedProvider` (demo_providers.dart:50)

This means after exiting demo mode, stale demo data persists in memory. If the user logs in as a real user, `demoExperienceActiveProvider` might still be true, causing `currentRooflineConfigProvider` to return the demo config (if 4.1 is fixed).

**Severity:** High — state leak between demo and production sessions. Could cause production users to see demo data.
**Recommended fix:** `exitDemoMode()` should call `demoSessionProvider.notifier.endDemo()` which should reset ALL demo providers, or `exitDemoMode()` should be expanded to reset the full set.
**Effort:** Small (~20 min)

### 4.5 `isDemoBrowsingFlag` Is a Mutable Global Variable

**File:** `app_providers.dart:21`
**Description:** `bool isDemoBrowsingFlag = false` is a top-level mutable variable used in route guards where Riverpod refs aren't available. This is necessary (route guards run outside the widget tree) but risky: (a) it survives hot restart in debug, (b) it's set directly from the completion screen (`demo_completion_screen.dart:288`) bypassing the provider, (c) it's only cleared in `exitDemoMode()` — if the app crashes or the route guard redirect loop fails, it stays true.

**Severity:** Medium — can cause the app to be stuck in demo browsing mode after unexpected navigation.
**Recommended fix:** Accept the pattern (it's a pragmatic solution to a real limitation) but add a safety valve: in `appRedirect()`, if `isDemoBrowsingFlag` is true but `demoModeProvider` is false, clear the flag. This catches desync cases.
**Effort:** Small (~15 min)

### 4.6 Completion Screen Sets `isDemoBrowsingFlag` Directly

**File:** `demo_completion_screen.dart:288`
**Description:** The "Explore the app" handler sets `isDemoBrowsingFlag = true` as a direct assignment to the global. This bypasses any future logic that might gate or log the flag change. The corresponding providers (`demoModeProvider`, `demoBrowsingProvider`) are set via Riverpod at lines 285-286.

**Severity:** Low — works correctly today, but the direct mutation is brittle.
**Recommended fix:** Create a `startDemoBrowsing(WidgetRef ref)` function (parallel to `exitDemoMode`) that atomically sets all three values.
**Effort:** Small (~15 min)

### 4.7 Lead Submission Creates Lead ID Client-Side Before Firestore Write

**File:** `demo_profile_screen.dart:57`
**Description:** `id: const Uuid().v4()` generates the lead ID locally. If `submitLead` at line 74 creates a new Firestore doc (`lead.id.isEmpty ? _leadsCollection.doc()` at demo_lead_service.dart:34), the local UUID is non-empty, so Firestore uses it as the document ID. This works but: (a) the UUID is generated before the write, so if the write fails and the user retries, a new UUID is generated and the previous partial write might orphan a document, (b) Firestore auto-IDs are more collision-resistant than UUID v4 in high-volume scenarios.

**Severity:** Low — UUID v4 collisions are astronomically unlikely at demo scale. The orphan document risk is the real concern.
**Recommended fix:** Let Firestore generate the ID: change to `id: ''` and let `submitLead` use `_leadsCollection.doc()`. Update the lead's in-memory ID from the doc reference after the write.
**Effort:** Small (~20 min)

### 4.8 `DemoAnalytics.trackStepCompleted` Accepts Duration but No Screen Tracks Time

**File:** `demo_providers.dart:217`
**Description:** `DemoAnalytics.trackStepCompleted(DemoStep step, Duration timeSpent)` expects a duration parameter. No demo screen calls this method. The `DemoLeadService.logStepCompleted` (demo_lead_service.dart:214) also takes `durationSeconds`. Neither is ever invoked from any screen in the demo flow.

**Severity:** Medium — missing conversion funnel analytics. Without step timing data, you can't identify where prospects drop off or which steps take too long.
**Recommended fix:** Add step timing to `DemoFlowNotifier` — record `DateTime.now()` on each `goToStep()` call, compute the delta, and fire the analytics event. This gives per-step dwell time for funnel optimization.
**Effort:** Medium (~1-2 hours)

### 4.9 `DemoStockHome.load()` Uses Static Cache That Survives Hot Reload

**File:** `demo_stock_home.dart:16`
**Description:** `static RooflineConfiguration? _cached` caches the loaded config permanently in the isolate. During development, if the JSON asset changes, hot reload won't pick up the new data because the static cache persists. In production this is fine.

**Severity:** Low — development-only issue.
**Recommended fix:** Guard the cache: `if (kDebugMode) _cached = null;` at the top of `load()`, or accept as-is since it's development-only.
**Effort:** Small (~5 min)

### 4.10 `DemoAnalytics` Uses Static Service Reference — Potential Leak

**File:** `demo_providers.dart:207-211`
**Description:** `DemoAnalytics._service` is a static field set by `init()`. If `startDemo()` is called multiple times (e.g., user exits and re-enters demo), the old service reference is overwritten but never cleared. Since `DemoLeadService` holds a `FirebaseFirestore` reference, this is not a meaningful leak — Firestore instances are singletons. But the static pattern means `DemoAnalytics` outlives the demo session and could theoretically log events after demo end.

**Severity:** Low — no practical impact, but the pattern is fragile.
**Recommended fix:** Add a `dispose()` method: `static void dispose() => _service = null;` and call it from `endDemo()`.
**Effort:** Small (~10 min)

### 4.11 Consultation Request Fires Two Separate Firestore Writes

**File:** `demo_completion_screen.dart:79-80`
**Description:** The consultation submission calls `leadService.logContactRequest(lead.id, request)` (which writes to `demo_leads/{id}` via `arrayUnion` and creates an `email_notifications` doc) and then `leadService.logConsultationRequested(lead.id)` (which writes to `demo_analytics`). These are three separate Firestore operations without a batch. If the second or third fails, the lead has a partial contact request.

**Severity:** Low — the critical data (the contact request itself) is in the first write. The analytics write is supplemental.
**Recommended fix:** Use a Firestore batch for atomicity, or accept the current behavior since partial failure still preserves the most important data.
**Effort:** Small (~20 min if batched)

### 4.12 `demoScheduleProvider` Uses `DateTime.now()` — Schedule Changes with Time

**File:** `demo_providers.dart:53-65`
**Description:** The `demoScheduleProvider` calls `DemoSchedulePresets.generateForProfile(currentDate: DateTime.now())` which uses the current date to select holiday-themed schedules. If a prospect opens the demo in March, they see "Easter Pastels." In May, they see no holiday schedule at all. The demo experience varies by time of year, which could be a feature or a bug depending on intent.

**Severity:** Low — arguably a feature (seasonal relevance), but the non-holiday months (May-June, August-September) produce fewer schedule items, making the schedule preview feel thin.
**Recommended fix:** **Question for Tyler:** Is the seasonal scheduling intentional? If so, add a fallback "Neighborhood Sync" or "Movie Night" schedule for months without holidays so the preview always has 3-4 items.

---

## Top 10 Fixes by ROI

Ranked by (conversion impact) / (engineering effort). Items that are both high-impact and low-effort rank highest.

| Rank | Finding | Section | Severity | Effort | Why It's High ROI |
|------|---------|---------|----------|--------|-------------------|
| **1** | 4.1 — `currentRooflineConfigProvider` not demo-aware; overlay doesn't render | S4 | Critical | Small (15 min) | Without this fix, the entire roofline visualization is broken in demo mode. The demo shows a photo with no lights. This is the #1 bug. |
| **2** | 1.9 — DemoScaffold back button doesn't navigate | S1 | High | Small (30 min) | Every user who taps back on any demo screen sees broken behavior. Universal impact across all 5 screens. |
| **3** | 1.7 — No CTA when roofline detection fails | S1 | High | Small (30 min) | Dead end in the flow = lost prospect. Easy fix (add a "Continue Anyway" button). |
| **4** | 2.3 — Consultation CTA is below "Explore the app" | S2 | High | Small (30 min) | Reordering two widgets on the completion screen to put the conversion action first. Highest conversion impact per line of code changed. |
| **5** | 1.2 — Profile blocks on Firestore write | S1 | High | Small (45 min) | Changing one `await` to fire-and-forget prevents the entire flow from stalling on network issues. Critical for trade show use. |
| **6** | 4.4 — `exitDemoMode` doesn't reset all demo state | S4 | High | Small (20 min) | Prevents demo data from leaking into production sessions. Simple expansion of an existing function. |
| **7** | 2.5 — Lead data doesn't include dealer attribution | S2 | High | Small (30 min) | Without this, the sales pipeline can't attribute leads to dealers. Add 3 fields to `DemoLead`. |
| **8** | 1.1 — Progress bar shows 9 steps, only 5 exist | S1 | High | Small (30 min, trim enum) | Removing 4 unused enum values eliminates the confusing progress jump. Quick fix with high polish impact. |
| **9** | 3.1 — Demo code validation fails offline | S3 | High | Medium (2-3 hrs) | Dealers at trade shows can't start the demo. Local cache fallback solves this. More effort but high impact for the dealer use case. |
| **10** | 2.4 — No roofline photo on completion screen | S2 | Medium | Small (45 min) | Adding the hero image with overlay to completion screen creates the emotional "this is YOUR home" moment right above the consultation CTA. |

### Honorable Mentions

- **4.8 — No step timing analytics** (Medium effort, but the data enables data-driven funnel optimization for every future sprint)
- **3.2 — Profile interrupts dealer pitch** (Small effort, high dealer QOL, but may conflict with early lead capture strategy)
- **2.1 — Four "wow" moments never shown** (Large effort, but addresses the fundamental gap that the demo only shows 20% of the product's value)

---

*End of review. All findings are based on static code analysis (code trace) against the current working tree on the `release/2.1.0` branch. No code was executed during this review.*
