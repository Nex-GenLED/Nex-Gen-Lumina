import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_providers.dart'
    show activePresetLabelProvider, authStateProvider, selectedTabIndexProvider;
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_dispatcher.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_intent.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_command_router.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/pattern_label_resolver.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_handler.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent_handler.dart';
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:nexgen_command/theme.dart';

// ---------------------------------------------------------------------------
// Host — what the driver needs from the surface it is running on
// ---------------------------------------------------------------------------

/// Which Lumina surface is hosting the conversation.
enum LuminaSurface { sheet, screen }

/// Surface-specific concerns handed to [LuminaConversationDriver] as
/// callbacks: the text field, scroll position, sheet size, snackbars and
/// `BuildContext` navigation. Everything the two surfaces do differently
/// lives here, so the driver itself never touches a widget and can be
/// exercised without pumping one.
class LuminaConversationHost {
  /// Used for log tags only — the driver does not branch on it.
  final LuminaSurface surface;

  /// Whether the hosting State is still mounted.
  final bool Function() isMounted;

  /// Clears the text field and drops keyboard focus.
  final VoidCallback clearInput;

  /// Runs after the user's message is added to the thread, before the
  /// scroll. The sheet grows to its expanded size here; the full screen has
  /// nothing to do.
  final VoidCallback? onUserMessagePosted;

  /// Scrolls the thread to its newest message.
  final VoidCallback scrollToEnd;

  /// Closes the surface ahead of a navigation command.
  final VoidCallback closeSurface;

  /// Navigates to a within-shell route (nav bar stays visible).
  final void Function(String route) goRoute;

  /// Pushes a fullscreen / modal route (outside the shell).
  final void Function(String route) pushRoute;

  /// Shows a one-line confirmation.
  final void Function(String message) showSnackBar;

  const LuminaConversationHost({
    required this.surface,
    required this.isMounted,
    required this.clearInput,
    this.onUserMessagePosted,
    required this.scrollToEnd,
    required this.closeSurface,
    required this.goRoute,
    required this.pushRoute,
    required this.showSnackBar,
  });
}

// ---------------------------------------------------------------------------
// Services — what the driver needs from the rest of the app
// ---------------------------------------------------------------------------

/// The shared chat thread, as the driver writes to it.
abstract class LuminaThread {
  void addUserMessage(String text);

  void updateTranscription(String text);

  void addAssistantMessage(
    String text, {
    LuminaPatternPreview? preview,
    Map<String, dynamic>? wledPayload,
  });
}

/// Everything [LuminaConversationDriver] reads from or writes to outside the
/// hosting surface. The app binds it to Riverpod via
/// [RiverpodLuminaConversationServices]; tests substitute a fake.
abstract class LuminaConversationServices {
  /// Opens the shared chat thread for one exchange.
  LuminaThread openThread();

  /// Routes [prompt] through the two-tier command pipeline, with the current
  /// thread as history.
  Future<LuminaCommandResult> route(String prompt);

  /// Whether a controller is currently selected.
  bool get hasDevice;

  /// Sends [payload] to the lights. True when the apply went through.
  Future<bool> applyToDevice(Map<String, dynamic> payload);

  /// Mirrors the applied design's colours and effect into the hero.
  void setPatternMetadata(LuminaPatternPreview preview);

  /// Writes the Now Playing label.
  void setActiveLabel(String label);

  /// Clears the Now Playing label.
  void clearActiveLabel();

  /// The Now Playing label as the dashboard currently shows it.
  String get displayPatternName;

  /// Uid of the signed-in user, or null when signed out.
  String? get currentUserId;

  Future<DispatchResult> dispatchEphemeralSession(
    EphemeralSessionIntent intent,
    String userId,
  );

  /// Runs the shared [handleRecurringSportsAutopilot] handler.
  Future<void> dispatchRecurringSportsAutopilot({
    required RecurringSportsAutopilotIntent intent,
    required LuminaCommandResult result,
    VoidCallback? onMessagePosted,
  });

  /// Runs the shared [handleSchedulingIntents] handler.
  Future<void> dispatchSchedulingIntents({
    required List<SchedulingIntent> intents,
    required LuminaCommandResult result,
    required LuminaPatternPreview? preview,
    VoidCallback? onMessagePosted,
  });

  /// Hands a multi-night plan to the autopilot scheduler.
  Future<void> importSmartSchedule(Map<String, dynamic> payload);

  /// Switches the bottom-nav tab.
  void selectTab(int tabIndex);

  /// Pushes a voice refinement into the adjustment panel, if it is open.
  void syncAdjustmentPanel({
    required String responseText,
    required LuminaPatternPreview preview,
    Map<String, dynamic>? wledPayload,
  });
}

/// Riverpod binding for [LuminaConversationServices]. Every provider is read
/// inline through [ref] at the moment of use — no notifier is held.
class RiverpodLuminaConversationServices implements LuminaConversationServices {
  final WidgetRef ref;

  const RiverpodLuminaConversationServices(this.ref);

  // Function-scoped capture, the same one the surfaces made at the top of
  // their send routine: the thread must still accept the reply (or the snag
  // message) if the surface is dismissed while the pipeline is in flight.
  @override
  LuminaThread openThread() =>
      _SheetControllerThread(ref.read(luminaSheetProvider.notifier));

  @override
  Future<LuminaCommandResult> route(String prompt) {
    final sheetState = ref.read(luminaSheetProvider);
    return LuminaCommandRouter.route(
      ref,
      prompt,
      history: sheetState.messages,
      activePatternContext: sheetState.activePatternContext,
    );
  }

  @override
  bool get hasDevice => ref.read(wledRepositoryProvider) != null;

  @override
  Future<bool> applyToDevice(Map<String, dynamic> payload) =>
      ref.read(wledStateProvider.notifier).applyToDevice(payload, labelHint: null);

  @override
  void setPatternMetadata(LuminaPatternPreview preview) {
    ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
          colorSequence: preview.colors,
          colorNames: preview.colorNames,
          effectName: preview.effectName,
        );
  }

  @override
  void setActiveLabel(String label) {
    ref
        .read(activePresetLabelProvider.notifier)
        .setLabelWithFingerprint(label, ref.read(wledStateProvider));
  }

  @override
  void clearActiveLabel() {
    ref.read(activePresetLabelProvider.notifier).clear();
  }

  @override
  String get displayPatternName => ref.read(displayPatternNameProvider);

  @override
  String? get currentUserId => ref
      .read(authStateProvider)
      .maybeWhen(data: (u) => u, orElse: () => null)
      ?.uid;

  @override
  Future<DispatchResult> dispatchEphemeralSession(
    EphemeralSessionIntent intent,
    String userId,
  ) =>
      EphemeralSessionDispatcher.dispatch(
        intent: intent,
        ref: ref,
        userId: userId,
      );

  @override
  Future<void> dispatchRecurringSportsAutopilot({
    required RecurringSportsAutopilotIntent intent,
    required LuminaCommandResult result,
    VoidCallback? onMessagePosted,
  }) =>
      handleRecurringSportsAutopilot(
        ref: ref,
        intent: intent,
        result: result,
        onMessagePosted: onMessagePosted,
      );

  @override
  Future<void> dispatchSchedulingIntents({
    required List<SchedulingIntent> intents,
    required LuminaCommandResult result,
    required LuminaPatternPreview? preview,
    VoidCallback? onMessagePosted,
  }) =>
      handleSchedulingIntents(
        ref: ref,
        context: ref.context,
        intents: intents,
        result: result,
        preview: preview,
        onMessagePosted: onMessagePosted,
      );

  @override
  Future<void> importSmartSchedule(Map<String, dynamic> payload) =>
      ref.read(autopilotSchedulerProvider).importSmartSchedule(payload);

  @override
  void selectTab(int tabIndex) {
    ref.read(selectedTabIndexProvider.notifier).state = tabIndex;
  }

  @override
  void syncAdjustmentPanel({
    required String responseText,
    required LuminaPatternPreview preview,
    Map<String, dynamic>? wledPayload,
  }) {
    final adjState = ref.read(adjustmentStateProvider);
    if (adjState != null && adjState.isExpanded) {
      final updated = LuminaLightingSuggestion.fromPreview(
        responseText: responseText,
        preview: preview,
        wledPayload: wledPayload,
      );
      ref.read(adjustmentStateProvider.notifier).applyFromVoice(updated);
    }
  }
}

class _SheetControllerThread implements LuminaThread {
  final LuminaSheetController _controller;

  const _SheetControllerThread(this._controller);

  @override
  void addUserMessage(String text) => _controller.addUserMessage(text);

  @override
  void updateTranscription(String text) =>
      _controller.updateTranscription(text);

  @override
  void addAssistantMessage(
    String text, {
    LuminaPatternPreview? preview,
    Map<String, dynamic>? wledPayload,
  }) =>
      _controller.addAssistantMessage(
        text,
        preview: preview,
        wledPayload: wledPayload,
      );
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

/// Which branch of [LuminaConversationDriver.handleResult] took the result.
enum LuminaResultBranch {
  navigation,
  schedule,
  ephemeralSession,
  recurringSportsAutopilot,
  schedulingIntents,
  apply,
}

/// The ONE Lumina conversation driver — used by both the full-screen Lumina
/// chat ([LuminaAIScreen]) and the dashboard bottom-sheet entry
/// (`showLuminaSheet`) so the two surfaces stay in lock-step (mirrors
/// [handleSchedulingIntents] and [handleRecurringSportsAutopilot]).
///
/// Owns the send routine and every branch a reply can take: navigation, the
/// multi-night schedule, the ephemeral game session, recurring sports
/// autopilot, recurring scheduling intents and the plain single-pattern
/// apply — plus the bubble-tap apply. The surfaces keep only their widgets.
///
/// Holds no state of its own. [host] carries the surface-specific callbacks;
/// [services] carries everything Riverpod-owned.
class LuminaConversationDriver {
  final LuminaConversationHost host;
  final LuminaConversationServices services;

  const LuminaConversationDriver({
    required this.host,
    required this.services,
  });

  // -------------------------------------------------------------------------
  // Send message / conversation
  // -------------------------------------------------------------------------

  Future<void> send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    host.clearInput();

    final thread = services.openThread();
    thread.addUserMessage(prompt);
    thread.updateTranscription('');
    host.onUserMessagePosted?.call();
    host.scrollToEnd();

    try {
      // Route through the two-tier command pipeline
      final result = await services.route(prompt);

      // Every branch but the plain apply posts and scrolls for itself.
      final branch =
          await handleResult(result, prompt: prompt, thread: thread);
      if (branch != LuminaResultBranch.apply) return;
    } catch (e) {
      debugPrint('Lumina ${host.surface.name} send error: $e');
      thread.addAssistantMessage('I hit a snag: $e');
    }

    host.scrollToEnd();
  }

  /// Dispatches a routed [result] to the branch that owns it and reports
  /// which one ran. Split from [send] so each branch can be driven with a
  /// hand-built result.
  @visibleForTesting
  Future<LuminaResultBranch> handleResult(
    LuminaCommandResult result, {
    required String prompt,
    required LuminaThread thread,
  }) async {
    // Handle navigation commands (close the surface and navigate)
    if (result.command?.type == LuminaCommandType.navigate) {
      _handleNavigation(result, thread);
      return LuminaResultBranch.navigation;
    }

    // ── Schedule detection ────────────────────────────────────────────────
    // When the AI returns a multi-day schedule plan, we apply night 1 as a
    // live preview and route the full plan to the scheduling system.
    //
    // UX audit row 7: the schedule branch — single edit point. Reads the
    // flags from result.scheduleFlags (they no longer ride in wledPayload,
    // where the parser dropped them). Flags with NO plan attached — the cloud
    // `season_fill` shape — still fall through to the plain apply below, as
    // they always have; nothing in the app fans a season out yet.
    final scheduleFlags = result.scheduleFlags;
    if (scheduleFlags != null &&
        scheduleFlags.isSchedule &&
        scheduleFlags.hasOccurrences) {
      await _handleScheduleResult(result, scheduleFlags, thread);
      return LuminaResultBranch.schedule;
    }

    // ── Ephemeral session intent (Item #51) ───────────────────────────────
    // When the AI emits ephemeralSession (sports/team event + "after"
    // state), apply the immediate WLED design AND wire up a one-shot
    // session that auto-reverts at game end. Takes precedence over
    // schedulingIntent — ephemeral is more specific (game-bounded, not
    // clock-bounded), and the AI is instructed to emit one or the other,
    // not both.
    final ephemeralIntent = result.ephemeralSessionIntent;
    if (ephemeralIntent != null && ephemeralIntent.isValid) {
      await _handleEphemeralSession(ephemeralIntent, result, prompt, thread);
      return LuminaResultBranch.ephemeralSession;
    }

    // ── Recurring sports autopilot (every game / all season) ──────────────
    // A COMPACT rule (team slug + optional untilDate) — NOT enumerated game
    // dates. Routes to the existing Game Day Autopilot enable path, which
    // idempotently enables/updates ONE config per team and materializes only
    // the rolling 7-day window into ≤8 WLED timers via the lease manager.
    final recurringSports = result.recurringSportsAutopilotIntent;
    if (recurringSports != null && recurringSports.isValid) {
      await services.dispatchRecurringSportsAutopilot(
        intent: recurringSports,
        result: result,
        onMessagePosted: host.scrollToEnd,
      );
      return LuminaResultBranch.recurringSportsAutopilot;
    }

    // ── Scheduling intents (recurring weekly/daily, 1 or N) ───────────────
    // The cloud parser canonicalizes both schema shapes (singular
    // schedulingIntent, array schedulingIntents) into one typed
    // List<SchedulingIntent> carried on result.schedulingIntents — read here
    // INDEPENDENT of wledPayload so the intents survive a null/absent
    // top-level wled (#58b). The shared handler iterates the list, builds N
    // ScheduleItems with a shared sourcePromptId, and persists atomically via
    // addAll.
    final intents = result.schedulingIntents ?? const <SchedulingIntent>[];
    if (intents.isNotEmpty) {
      await services.dispatchSchedulingIntents(
        intents: intents,
        result: result,
        preview: _previewFor(result),
        onMessagePosted: host.scrollToEnd,
      );
      return LuminaResultBranch.schedulingIntents;
    }

    // ── Normal single-pattern apply ───────────────────────────────────────
    final preview = _previewFor(result);
    if (result.wledPayload != null) {
      await _applyDesign(
        result.wledPayload!,
        preview: preview,
        fallbackName: result.command?.parameters['patternName'],
        prompt: prompt,
        logLabel: 'Apply from Lumina ${host.surface.name}',
      );
    }

    // UX audit row 74: reply is posted regardless of apply result — single
    // edit point. _applyDesign above returns false when no device is
    // selected, the apply is refused, or it throws; nothing here reads it.
    thread.addAssistantMessage(
      result.responseText,
      preview: preview,
      wledPayload: result.wledPayload,
    );

    // Sync voice refinement results to the adjustment panel if active
    if (preview != null) {
      services.syncAdjustmentPanel(
        responseText: result.responseText,
        preview: preview,
        wledPayload: result.wledPayload,
      );
    }

    return LuminaResultBranch.apply;
  }

  // -------------------------------------------------------------------------
  // Apply pattern from bubble
  // -------------------------------------------------------------------------

  Future<void> applyFromBubble(
    Map<String, dynamic> wled,
    LuminaPatternPreview? preview, {
    String? originalPrompt,
  }) async {
    await _applyDesign(
      wled,
      preview: preview,
      fallbackName: wled['patternName'],
      prompt: originalPrompt,
      logLabel: 'Apply from ${host.surface.name}',
      announce: true,
    );
  }

  // -------------------------------------------------------------------------
  // Branches
  // -------------------------------------------------------------------------

  /// Handles navigation commands by closing the surface and navigating.
  void _handleNavigation(LuminaCommandResult result, LuminaThread thread) {
    final target =
        resolveLuminaNavigation(result.command?.parameters ?? const {});

    // Close the surface first
    host.closeSurface();

    switch (target.action) {
      case LuminaNavigationAction.selectTab:
        services.selectTab(target.tabIndex!);
      case LuminaNavigationAction.go:
        if (host.isMounted()) host.goRoute(target.route!);
      case LuminaNavigationAction.push:
        if (host.isMounted()) host.pushRoute(target.route!);
      case LuminaNavigationAction.none:
        break;
    }

    thread.addAssistantMessage(result.responseText);
  }

  /// Handles a smart schedule result from the AI.
  ///
  /// 1. Applies the FIRST occurrence as a live preview so the user
  ///    immediately sees something on their lights.
  /// 2. Routes the full schedule to [AutopilotScheduler.importSmartSchedule].
  ///    Night 1 is already applied — the scheduler marks it approved and
  ///    queues/suggests nights 2+ based on the user's autonomy level.
  /// 3. Posts the conversational response card to the chat thread.
  Future<void> _handleScheduleResult(
    LuminaCommandResult result,
    LuminaScheduleFlags flags,
    LuminaThread thread,
  ) async {
    debugPrint(
        '📅 Smart schedule: ${flags.dayCount} days, hasVariety=${flags.hasVariety}');

    // Step 1 — Apply night 1 as immediate live preview
    final firstWled = flags.firstNightWled;
    if (firstWled != null && services.hasDevice) {
      try {
        await services.applyToDevice(firstWled);
        debugPrint('📅 Night 1 preview applied to lights');
      } catch (e) {
        debugPrint('📅 Night 1 preview apply failed: $e');
      }
    }

    // Step 2 — Hand full plan off to AutopilotScheduler.
    // Night 1 is already applied above; the scheduler marks it approved so
    // the check loop never re-fires it. Nights 2+ are queued as suggestions
    // (autonomy level 1) or auto-scheduled (autonomy level 2).
    try {
      await services.importSmartSchedule(flags.toImportPayload());
      debugPrint(
          '📅 Imported ${flags.dayCount}-night schedule into AutopilotScheduler');
    } catch (e) {
      debugPrint('📅 Schedule import failed: $e');
    }

    // Step 3 — Build preview strip from night 1 colors for the response card
    LuminaPatternPreview? preview;
    if (firstWled != null) preview = extractLuminaPreview(firstWled);
    preview ??= result.previewColors.isNotEmpty
        ? LuminaPatternPreview(colors: result.previewColors)
        : null;

    // Set the preset label to the full schedule name
    final scheduleLabel = flags.patternName;
    if (scheduleLabel != null && host.isMounted()) {
      services.setActiveLabel(scheduleLabel);
    }

    // Step 4 — Post response card to chat thread
    thread.addAssistantMessage(
      result.responseText,
      preview: preview,
      wledPayload: result.wledPayload,
    );

    host.scrollToEnd();
  }

  /// Item #51 Prompt 3 — applies the immediate WLED design then dispatches
  /// the ephemeral session intent to [EphemeralSessionDispatcher]. Builds
  /// a chat confirmation that augments the AI's response text with the
  /// session details (or a no-game-found alternative offer).
  Future<void> _handleEphemeralSession(
    EphemeralSessionIntent intent,
    LuminaCommandResult result,
    String prompt,
    LuminaThread thread,
  ) async {
    // 1. Apply the immediate WLED payload (the team design). Mirrors the
    //    existing single-pattern apply so the user gets the design they
    //    asked for regardless of the dispatch outcome.
    LuminaPatternPreview? preview;
    if (result.wledPayload != null) {
      preview = extractLuminaPreview(result.wledPayload!);
      await _applyDesign(
        result.wledPayload!,
        preview: preview,
        fallbackName: result.command?.parameters['patternName'],
        prompt: prompt,
        logLabel: 'Apply (ephemeral) from Lumina ${host.surface.name}',
      );
    }

    // 2. Dispatch the ephemeral session intent.
    String? augmentation;
    final userId = services.currentUserId;
    if (userId == null) {
      debugPrint(
          '[Lumina ${host.surface.name}] ephemeral session — no authenticated user; skipping dispatch');
    } else {
      final dispatchResult =
          await services.dispatchEphemeralSession(intent, userId);
      augmentation =
          buildEphemeralAugmentation(dispatchResult, surface: host.surface);
    }

    // UX audit row 109: a null augmentation means no revert session was armed
    // (signed out, or the dispatch failed) and the AI's prose goes out
    // unchanged — single edit point.
    var responseText = result.responseText;
    if (augmentation != null) {
      responseText = '$responseText\n\n$augmentation';
    }

    if (!host.isMounted()) return;
    thread.addAssistantMessage(
      responseText,
      preview: preview,
      wledPayload: result.wledPayload,
    );
  }

  // -------------------------------------------------------------------------
  // Apply
  // -------------------------------------------------------------------------

  /// Sends [payload] to the lights and, when that lands, records what is now
  /// playing. Returns true only when the design reached the lights and the
  /// surface was still there to record it; false when no device is selected,
  /// the apply is refused, or it throws.
  ///
  /// [fallbackName] is the pattern name to fall back on when [preview] has
  /// none. [announce] confirms a successful apply with a snackbar.
  Future<bool> _applyDesign(
    Map<String, dynamic> payload, {
    required LuminaPatternPreview? preview,
    required Object? fallbackName,
    required String? prompt,
    required String logLabel,
    bool announce = false,
  }) async {
    if (!services.hasDevice) return false;

    try {
      final ok = await services.applyToDevice(payload);
      if (!ok || !host.isMounted()) return false;

      if (preview != null) {
        services.setPatternMetadata(preview);
      }
      // UX audit row 112 (label half): a power / brightness reply lands here
      // with the manufactured preview and no pattern name, so the label is
      // synthesized from the prompt words. See extractLuminaPreview.
      final aiName = preview?.patternName ?? fallbackName as String?;
      final label = resolveLuminaDisplayName(aiName, prompt);
      if (label != null) {
        services.setActiveLabel(label);
      } else {
        services.clearActiveLabel();
      }
      if (announce) {
        host.showSnackBar('${services.displayPatternName} applied!');
      }
      return true;
    } catch (e) {
      debugPrint('$logLabel failed: $e');
      return false;
    }
  }

  /// The preview card for [result]: extracted from the payload when there is
  /// one, otherwise built from the bare preview colors.
  LuminaPatternPreview? _previewFor(LuminaCommandResult result) {
    if (result.wledPayload != null) {
      return extractLuminaPreview(result.wledPayload!);
    } else if (result.previewColors.isNotEmpty) {
      // Build a preview from colors even without full WLED payload
      return LuminaPatternPreview(colors: result.previewColors);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Ephemeral session confirmation
// ---------------------------------------------------------------------------

/// Builds the chat confirmation suffix appended to the AI's response
/// text after an ephemeral session dispatch. Returns null when there's
/// nothing to add (hard error or empty result).
String? buildEphemeralAugmentation(
  DispatchResult dispatchResult, {
  required LuminaSurface surface,
}) {
  if (dispatchResult.noGameFoundMessage != null) {
    // UX audit row 105: this sentence says the colors were applied, but it is
    // composed from the schedule lookup alone — the apply outcome
    // (_applyDesign, in _handleEphemeralSession) never reaches it — single
    // edit point.
    return dispatchResult.noGameFoundMessage;
  }
  if (dispatchResult.createdSessionIds.isEmpty) {
    debugPrint(
        '[Lumina ${surface.name}] ephemeral dispatch returned no sessions and no message: ${dispatchResult.errorMessage}');
    return null;
  }
  final labels = dispatchResult.sessionLabels;
  if (labels.length == 1) {
    return '✓ Will revert to ${dispatchResult.revertLabel} when ${labels.first} ends.';
  }
  return '✓ Will revert to ${dispatchResult.revertLabel} after each game ends: ${labels.join(', ')}.';
}

// ---------------------------------------------------------------------------
// Navigation routing
// ---------------------------------------------------------------------------

/// What a navigation command asks the surface to do.
enum LuminaNavigationAction { selectTab, go, push, none }

/// Resolved destination of a navigation command.
class LuminaNavigationTarget {
  final LuminaNavigationAction action;
  final int? tabIndex;
  final String? route;

  const LuminaNavigationTarget.selectTab(int this.tabIndex)
      : action = LuminaNavigationAction.selectTab,
        route = null;

  const LuminaNavigationTarget.go(String this.route)
      : action = LuminaNavigationAction.go,
        tabIndex = null;

  const LuminaNavigationTarget.push(String this.route)
      : action = LuminaNavigationAction.push,
        tabIndex = null;

  const LuminaNavigationTarget.none()
      : action = LuminaNavigationAction.none,
        tabIndex = null,
        route = null;
}

/// Resolves a navigate command's [parameters] (`route`, `tabIndex`) into a
/// destination. A tab index wins over a route.
LuminaNavigationTarget resolveLuminaNavigation(
    Map<String, dynamic> parameters) {
  final route = parameters['route'] as String?;
  final tabIndex = parameters['tabIndex'] as int?;

  if (tabIndex != null) return LuminaNavigationTarget.selectTab(tabIndex);
  if (route == null) return const LuminaNavigationTarget.none();
  return isLuminaShellRoute(route)
      ? LuminaNavigationTarget.go(route)
      : LuminaNavigationTarget.push(route);
}

/// Use go() for within-shell routes so nav bar stays visible;
/// use push() for fullscreen/modal routes (outside shell).
/// Note: '/dashboard/...' (nested home-branch routes like
/// /dashboard/design-studio, /dashboard/my-designs, /dashboard/game-day)
/// must also use go() so the home branch navigates to the nested path
/// instead of pushing on the root navigator.
bool isLuminaShellRoute(String route) =>
    route.startsWith('/explore') ||
    route.startsWith('/settings') ||
    route.startsWith('/schedule') ||
    route.startsWith('/wled/') ||
    route.startsWith('/dashboard');

// ---------------------------------------------------------------------------
// Preview extraction helper
// ---------------------------------------------------------------------------

/// Builds the response-card preview for a Lumina payload. Reads the rich
/// `colors` / `effect` metadata first and falls back to the first WLED
/// segment. Returns null only when the payload cannot be read at all.
LuminaPatternPreview? extractLuminaPreview(Map<String, dynamic> payload) {
  try {
    String? patternName = payload['patternName'] as String?;
    String? effectName;
    String? direction;
    bool isStatic = false;
    int? speed;
    int? intensity;
    List<String> colorNames = [];
    List<Color> colors = [];

    // Rich colors array
    final colorsArray = payload['colors'];
    if (colorsArray is List) {
      for (final c in colorsArray) {
        if (c is Map) {
          final name = c['name'] as String?;
          if (name != null) colorNames.add(name);
          final rgb = c['rgb'];
          if (rgb is List && rgb.length >= 3) {
            colors.add(Color.fromARGB(
              255,
              (rgb[0] as num).toInt(),
              (rgb[1] as num).toInt(),
              (rgb[2] as num).toInt(),
            ));
          }
        }
      }
    }

    // Rich effect object
    final effectObj = payload['effect'];
    int? effect;
    if (effectObj is Map) {
      effectName = effectObj['name'] as String?;
      effect = (effectObj['id'] as num?)?.toInt();
      direction = effectObj['direction'] as String?;
      isStatic = effectObj['isStatic'] == true;
    }

    speed = (payload['speed'] as num?)?.toInt();
    intensity = (payload['intensity'] as num?)?.toInt();

    // Fallback to wled segment data
    final wled = payload['wled'] ?? payload;
    final seg = wled['seg'];
    int? pal;
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      final first = seg.first as Map;
      effect ??= (first['fx'] as num?)?.toInt();
      pal = (first['pal'] as num?)?.toInt();
      speed ??= (first['sx'] as num?)?.toInt();
      intensity ??= (first['ix'] as num?)?.toInt();

      if (colors.isEmpty) {
        final col = first['col'];
        if (col is List) {
          for (final c in col) {
            if (c is List && c.length >= 3) {
              colors.add(Color.fromARGB(
                255,
                (c[0] as num).toInt(),
                (c[1] as num).toInt(),
                (c[2] as num).toInt(),
              ));
            }
          }
        }
      }
    }

    // UX audit row 112: the preview is manufactured (fallback swatches) when
    // the payload has no colors — single edit point. The label half of the
    // row keys off this same preview in _applyDesign.
    if (colors.isEmpty) {
      colors = const [NexGenPalette.cyan, Color(0xFF102040)];
    }

    return LuminaPatternPreview(
      patternName: patternName,
      colors: colors.take(5).toList(),
      colorNames: colorNames,
      effectId: effect,
      effectName: effectName,
      direction: direction,
      isStatic: isStatic,
      speed: speed,
      intensity: intensity,
      paletteId: pal,
    );
  } catch (e) {
    debugPrint('extractPreview failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Thread helpers
// ---------------------------------------------------------------------------

/// Walks back from [assistantIndex] to find the prompt that produced the
/// bubble at that index. Used by the bubble-tap apply path.
String? priorLuminaUserPrompt(List<LuminaMessage> messages, int assistantIndex) {
  for (int i = assistantIndex - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.role == LuminaMessageRole.user && m.text.trim().isNotEmpty) {
      return m.text;
    }
  }
  return null;
}
