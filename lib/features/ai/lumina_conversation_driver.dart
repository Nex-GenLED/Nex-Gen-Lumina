import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_providers.dart'
    show activePresetLabelProvider, authStateProvider, selectedTabIndexProvider;
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_channel_apply.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_dispatcher.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_intent.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_command_router.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/pattern_label_resolver.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_handler.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/features/ai/scheduling_intent_handler.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart'
    show FavoritesFullException, kFavoritesFullMessage;
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarEntryLeaseManagerProvider;
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/write_result.dart';

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

  /// Sends [payload] to the lights and says what happened: success, or the
  /// reason nothing was sent (no controller, away from home, channels not
  /// read yet), or a write the controller did not take (+110 E2 row 74).
  Future<WriteResult> applyToDevice(Map<String, dynamic> payload);

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

  /// Runs the shared [handleSchedulingIntents] handler. [prompt] is the
  /// customer's own words — the gate for recurring vs dated (+112, #121).
  Future<void> dispatchSchedulingIntents({
    required String prompt,
    required List<SchedulingIntent> intents,
    required LuminaCommandResult result,
    required LuminaPatternPreview? preview,
    VoidCallback? onMessagePosted,
  });

  /// Writes the nights of a multi-night plan to the account's calendar and
  /// says how many landed (+110 E2 item 4).
  Future<ScheduleNightsOutcome> persistScheduleNights(
      LuminaScheduleFlags flags);

  /// Saves a reply's design as a favourite (+110 E2 row 106).
  Future<WriteResult> saveFavorite({
    required String patternName,
    required Map<String, dynamic> wledPayload,
  });

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
  Future<WriteResult> applyToDevice(Map<String, dynamic> payload) {
    if (ref.read(wledRepositoryProvider) == null) {
      return Future.value(WriteResult.blocked(
          applyBlockedReason(ref.read) ?? kApplyBlockedFallback));
    }
    // #163: one look for the house → every participating channel.
    return ref.read(wledStateProvider.notifier).applyLuminaDesign(payload);
  }

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
    required String prompt,
    required List<SchedulingIntent> intents,
    required LuminaCommandResult result,
    required LuminaPatternPreview? preview,
    VoidCallback? onMessagePosted,
  }) =>
      handleSchedulingIntents(
        ref: ref,
        context: ref.context,
        prompt: prompt,
        intents: intents,
        result: result,
        preview: preview,
        onMessagePosted: onMessagePosted,
      );

  @override
  Future<ScheduleNightsOutcome> persistScheduleNights(
      LuminaScheduleFlags flags) async {
    final requested = flags.schedule.length;
    if (requested <= 1) return ScheduleNightsOutcome.nothingToPersist;
    if (currentUserId == null) {
      return ScheduleNightsOutcome(
        requested: requested,
        persisted: 0,
        message: 'sign in to save nights to your Schedule.',
      );
    }
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    final nights = plannedNightsOf(
      flags,
      latitude: profile?.latitude,
      longitude: profile?.longitude,
    );
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    // D2 — never overwrite. A night that already holds a Game Day entry, an
    // armed lease, or a user-authored entry is SKIPPED and named in the reply;
    // the customer is never asked mid-conversation.
    final calendar = ref.read(calendarScheduleProvider);
    final leased = ref
        .read(calendarEntryLeaseManagerProvider)
        .activeLeases
        .map((l) => l.dateKey)
        .toSet();
    final plan = planLuminaNightWrites(
      nights: nights,
      batchId: batchId,
      existingOn: calendar.forDate,
      leasedDateKeys: leased,
    );
    final noClockMessage = plan.noClock > 0
        ? "I couldn't tell what time each night should start. Tell me a "
            'time like "7pm" or "sunset".'
        : null;
    if (plan.entries.isEmpty) {
      return ScheduleNightsOutcome(
        requested: requested,
        persisted: 0,
        skipped: plan.skipReplies,
        message: noClockMessage ??
            (plan.skipped.isEmpty ? 'the plan had no dates I could use.' : null),
      );
    }
    try {
      // D2 — a full timer pool drops the nights that do not fit; the reply
      // says so. The eviction picker is never raised from here.
      final outcome = await ref
          .read(calendarScheduleProvider.notifier)
          .applyEntriesDetailed(plan.entries,
              noFreeSlots: NoFreeSlotsPolicy.drop);
      if (!outcome.ok) {
        return ScheduleNightsOutcome(
          requested: requested,
          persisted: 0,
          skipped: plan.skipReplies,
          message: "the Schedule didn't accept them. Check your connection "
              'and try again.',
        );
      }
      final droppedIds = outcome.dropped.map((e) => e.entryId).toSet();
      final saved = [
        for (final w in plan.writes)
          if (!droppedIds.contains(w.entry.entryId)) w.night.index,
      ];
      return ScheduleNightsOutcome(
        requested: requested,
        persisted: saved.length,
        saved: saved,
        skipped: plan.skipReplies,
        unfitted: droppedIds.length,
        message: plan.noClock > 0
            ? '${plan.noClock} ${plan.noClock == 1 ? 'night' : 'nights'} had '
                'no usable time.'
            : null,
      );
    } catch (e) {
      debugPrint('persistScheduleNights failed: $e');
      return ScheduleNightsOutcome(
        requested: requested,
        persisted: 0,
        skipped: plan.skipReplies,
        message: "the Schedule didn't accept them. Try again in a moment.",
      );
    }
  }

  @override
  Future<WriteResult> saveFavorite({
    required String patternName,
    required Map<String, dynamic> wledPayload,
  }) async {
    if (currentUserId == null) {
      return const WriteResult.blocked('Sign in to save favourites.');
    }
    try {
      await ref.read(favoritesNotifierProvider.notifier).addToFavorites(
            patternId: luminaFavoriteId(wledPayload),
            patternName: patternName,
            wledPayload: wledPayload,
          );
      return WriteResult.success(message: 'Saved "$patternName" to Favorites');
    } on FavoritesFullException {
      // #164: capped at two. The chat cannot show the replace list, so it
      // says plainly what to do.
      return const WriteResult.blocked(kFavoritesFullMessage);
    } catch (e) {
      debugPrint('Lumina saveFavorite failed: $e');
      return WriteResult.failed(
        WriteFailureKind.error,
        message: "Couldn't save that to Favorites. Try again in a moment.",
        error: e,
      );
    }
  }

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
/// apply — plus the bubble-tap apply and the favourite save. The surfaces
/// keep only their widgets.
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
      thread.addAssistantMessage(
          "I hit a snag and couldn't finish that. Try again in a moment.");
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
    // A multi-night plan: night 1 goes on the lights now, every night goes
    // to the calendar, and the reply says what actually happened (UX audit
    // row 7 / item 4). Flags with NO plan attached — the cloud `season_fill` shape —
    // still fall through to the plain apply below, as they always have.
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
    final recurringSports = result.recurringSportsAutopilotIntent;
    if (recurringSports != null && recurringSports.isValid) {
      await services.dispatchRecurringSportsAutopilot(
        intent: recurringSports,
        result: result,
        onMessagePosted: host.scrollToEnd,
      );
      return LuminaResultBranch.recurringSportsAutopilot;
    }

    // ── Scheduling intents (1 or N) — dated nights unless the words asked
    // to repeat (+112, #121); the handler decides from [prompt]. ──────────
    final intents = result.schedulingIntents ?? const <SchedulingIntent>[];
    if (intents.isNotEmpty) {
      await services.dispatchSchedulingIntents(
        prompt: prompt,
        intents: intents,
        result: result,
        preview: _previewFor(result),
        onMessagePosted: host.scrollToEnd,
      );
      return LuminaResultBranch.schedulingIntents;
    }

    // ── Normal single-pattern apply ───────────────────────────────────────
    var preview = _previewFor(result);
    if (result.wledPayload != null) {
      final outcome = await _applyDesign(
        result.wledPayload!,
        preview: preview,
        fallbackName: result.command?.parameters['patternName'],
        prompt: prompt,
        logLabel: 'Apply from Lumina ${host.surface.name}',
        touchesLabel: !_isPowerOrBrightness(result),
      );

      // UX audit row 74: a completion-toned reply ("Turning your lights
      // off.") is never posted for a command that went nowhere. The reply
      // is the failure sentence, with the shared reason when the command
      // was blocked before it was sent.
      if (!outcome.ok) {
        thread.addAssistantMessage(
          failureReplyFor(result, outcome),
          preview: preview,
          wledPayload: result.wledPayload,
        );
        return LuminaResultBranch.apply;
      }
      // #163: the card names the channels the look was SENT to, from the
      // write's own report — never an assumed "all".
      if (preview != null && outcome.channels != null) {
        preview = preview.withAppliedTo(outcome.message);
      }
    }

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

  static bool _isPowerOrBrightness(LuminaCommandResult result) {
    final t = result.command?.type;
    return t == LuminaCommandType.power || t == LuminaCommandType.brightness;
  }

  /// The reply for a command that did not reach the lights. Pure.
  @visibleForTesting
  static String failureReplyFor(LuminaCommandResult result, WriteResult outcome) {
    final reason = outcome.message ?? kApplyBlockedFallback;
    final what = switch (result.command?.type) {
      LuminaCommandType.power => result.command!.parameters['on'] == true
          ? 'turn your lights on'
          : 'turn your lights off',
      LuminaCommandType.brightness => 'change the brightness',
      LuminaCommandType.solidColor => 'change the colour',
      _ => 'apply that',
    };
    return "I couldn't $what — $reason";
  }

  // -------------------------------------------------------------------------
  // Apply pattern from bubble
  // -------------------------------------------------------------------------

  Future<void> applyFromBubble(
    Map<String, dynamic> wled,
    LuminaPatternPreview? preview, {
    String? originalPrompt,
  }) async {
    final outcome = await _applyDesign(
      wled,
      preview: preview,
      fallbackName: wled['patternName'],
      prompt: originalPrompt,
      logLabel: 'Apply from ${host.surface.name}',
      announce: true,
    );
    if (!outcome.ok && host.isMounted()) {
      host.showSnackBar(outcome.message ?? kApplyBlockedFallback);
    }
  }

  // -------------------------------------------------------------------------
  // Save as favourite (row 106)
  // -------------------------------------------------------------------------

  /// Saves the design behind a reply card as a favourite and says so.
  Future<WriteResult> saveFavorite(
    Map<String, dynamic> wled,
    LuminaPatternPreview? preview, {
    String? originalPrompt,
  }) async {
    final name = preview?.patternName ??
        resolveLuminaDisplayName(wled['patternName'] as String?, originalPrompt) ??
        'Lumina design';
    final result = await services.saveFavorite(
      patternName: name,
      wledPayload: favoritePayloadOf(wled),
    );
    if (host.isMounted()) {
      host.showSnackBar(result.message ??
          (result.ok ? 'Saved to Favorites' : "Couldn't save to Favorites"));
    }
    return result;
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

  /// Handles a smart schedule result from the AI (+110 E2 item 4).
  ///
  /// 1. Applies the FIRST occurrence now, and records whether it landed.
  /// 2. Persists every night of the plan to the calendar
  ///    ([LuminaConversationServices.persistScheduleNights]).
  /// 3. Posts a reply composed from those two outcomes — never the plan's
  ///    own "I've scheduled N nights" prose, which was posted whatever
  ///    happened.
  Future<void> _handleScheduleResult(
    LuminaCommandResult result,
    LuminaScheduleFlags flags,
    LuminaThread thread,
  ) async {
    debugPrint(
        '📅 Smart schedule: ${flags.dayCount} days, hasVariety=${flags.hasVariety}');

    // Step 1 — tonight, now.
    final firstWled = flags.firstNightWled;
    WriteResult? applied;
    if (firstWled != null) {
      try {
        applied = await services.applyToDevice(firstWled);
      } catch (e) {
        debugPrint('📅 Night 1 apply threw: $e');
        applied = WriteResult.failed(
          WriteFailureKind.error,
          message: "Couldn't reach your lights — check your connection",
          error: e,
        );
      }
      debugPrint('📅 Night 1 apply: $applied');
    }

    // Step 2 — every night to the calendar.
    ScheduleNightsOutcome outcome;
    try {
      outcome = await services.persistScheduleNights(flags);
    } catch (e) {
      debugPrint('📅 Schedule persistence failed: $e');
      outcome = ScheduleNightsOutcome(
        requested: flags.schedule.length,
        persisted: 0,
        message: "the Schedule didn't accept them.",
      );
    }

    // Step 3 — preview strip from night 1 colors for the response card
    LuminaPatternPreview? preview;
    if (firstWled != null) preview = extractLuminaPreview(firstWled);
    preview ??= result.previewColors.isNotEmpty
        ? LuminaPatternPreview(colors: result.previewColors)
        : null;

    // The Now Playing label names the plan only when tonight actually landed.
    final scheduleLabel = flags.patternName;
    if (applied != null && applied.ok && scheduleLabel != null && host.isMounted()) {
      services.setActiveLabel(scheduleLabel);
    }

    // Step 4 — the honest reply.
    final nights = plannedNightsOf(flags);
    final themeName = (flags.raw['themeName'] as String?) ??
        _themeNameFromPatternName(flags.patternName) ??
        'this';
    final reply = composeScheduleReply(
      themeName: themeName,
      appliedOk: applied?.ok,
      applyMessage: applied == null || applied.ok ? null : applied.message,
      nights: nights,
      outcome: outcome,
    );
    thread.addAssistantMessage(
      reply,
      preview: preview,
      wledPayload: result.wledPayload,
    );

    host.scrollToEnd();
  }

  /// "Christmas — 7-Night Schedule" → "Christmas".
  static String? _themeNameFromPatternName(String? patternName) {
    if (patternName == null) return null;
    final dash = patternName.indexOf(' — ');
    final name = dash < 0 ? patternName : patternName.substring(0, dash);
    return name.trim().isEmpty ? null : name.trim();
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
    WriteResult? applied;
    if (result.wledPayload != null) {
      preview = extractLuminaPreview(result.wledPayload!);
      applied = await _applyDesign(
        result.wledPayload!,
        preview: preview,
        fallbackName: result.command?.parameters['patternName'],
        prompt: prompt,
        logLabel: 'Apply (ephemeral) from Lumina ${host.surface.name}',
      );
    }

    // 2. Dispatch the ephemeral session intent.
    String augmentation;
    final userId = services.currentUserId;
    if (userId == null) {
      debugPrint(
          '[Lumina ${host.surface.name}] ephemeral session — no authenticated user; skipping dispatch');
      // Row 109: say it, rather than posting the AI's "armed" prose.
      augmentation =
          "I couldn't set the post-game revert — sign in and ask me again.";
    } else {
      final dispatchResult =
          await services.dispatchEphemeralSession(intent, userId);
      augmentation = buildEphemeralAugmentation(
        dispatchResult,
        surface: host.surface,
        applied: applied?.ok,
        applyMessage: applied == null || applied.ok ? null : applied.message,
      );
    }

    // Row 74 for this branch: when the colours never reached the lights,
    // the reply leads with that rather than the AI's completion prose.
    var responseText = result.responseText;
    if (applied != null && !applied.ok) {
      responseText = failureReplyFor(result, applied);
    }
    responseText = '$responseText\n\n$augmentation';

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
  /// playing. The result says why when it did not land: nothing sent (no
  /// controller, away from home, channels not read yet — the shared reason),
  /// the controller refused it, or the surface was gone before it landed.
  ///
  /// [fallbackName] is the pattern name to fall back on when [preview] has
  /// none. [announce] confirms a successful apply with a snackbar.
  /// [touchesLabel] — false for a power or brightness command, which is not
  /// a design and must leave Now Playing alone (row 112).
  Future<WriteResult> _applyDesign(
    Map<String, dynamic> payload, {
    required LuminaPatternPreview? preview,
    required Object? fallbackName,
    required String? prompt,
    required String logLabel,
    bool announce = false,
    bool touchesLabel = true,
  }) async {
    try {
      final result = await services.applyToDevice(payload);
      if (!result.ok) return result;
      if (!host.isMounted()) {
        return const WriteResult.failed(WriteFailureKind.error,
            message: 'The screen closed before the lights answered.');
      }

      if (touchesLabel) {
        if (preview != null) {
          services.setPatternMetadata(preview);
        }
        final aiName = preview?.patternName ?? fallbackName as String?;
        final label = resolveLuminaDisplayName(aiName, prompt);
        if (label != null) {
          services.setActiveLabel(label);
        } else {
          services.clearActiveLabel();
        }
      }
      if (announce) {
        host.showSnackBar('${services.displayPatternName} applied!');
      }
      return result;
    } catch (e) {
      debugPrint('$logLabel failed: $e');
      return WriteResult.failed(
        WriteFailureKind.error,
        message: "Couldn't reach your lights — check your connection",
        error: e,
      );
    }
  }

  /// The preview card for [result]: extracted from the payload when there is
  /// one, otherwise built from the bare preview colors. Null when the reply
  /// carries no colours at all (a power or brightness command): no card, no
  /// manufactured swatches (row 112).
  LuminaPatternPreview? _previewFor(LuminaCommandResult result) {
    if (result.wledPayload != null) {
      final p = extractLuminaPreview(result.wledPayload!);
      if (p != null) return p;
    }
    if (result.previewColors.isNotEmpty) {
      return LuminaPatternPreview(colors: result.previewColors);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Favourite payload
// ---------------------------------------------------------------------------

/// The WLED state a favourite stores: the payload's device keys only, so the
/// Lumina display metadata (`patternName`, `colors`, `effect`…) never rides
/// to the controller.
Map<String, dynamic> favoritePayloadOf(Map<String, dynamic> lumina) =>
    luminaDevicePayload(lumina);

/// A stable favourite id for a Lumina design: the same design saved twice
/// updates one favourite rather than adding a second.
String luminaFavoriteId(Map<String, dynamic> wled) {
  final seg = wled['seg'];
  final first = seg is List && seg.isNotEmpty && seg.first is Map
      ? seg.first as Map
      : const {};
  final fx = first['fx'];
  final col = first['col'];
  final fingerprint = '$fx|$col|${first['sx']}|${first['ix']}|${first['pal']}';
  return 'lumina_${fingerprint.hashCode.toUnsigned(32).toRadixString(16)}';
}

// ---------------------------------------------------------------------------
// Ephemeral session confirmation
// ---------------------------------------------------------------------------

/// Builds the chat confirmation suffix appended to the AI's response text
/// after an ephemeral session dispatch.
///
/// [applied] is whether the team colours reached the lights (null when there
/// was nothing to apply); [applyMessage] is why not. UX audit row 105: the
/// "I've applied the colors anyway" sentence is composed from BOTH the
/// schedule lookup and the apply outcome. UX audit row 109: a failed dispatch
/// says the revert was not set, instead of leaving the AI's "armed" prose
/// standing.
String buildEphemeralAugmentation(
  DispatchResult dispatchResult, {
  required LuminaSurface surface,
  bool? applied,
  String? applyMessage,
}) {
  final colorsSentence = applied == null
      ? null
      : applied
          ? "I've applied the colors anyway."
          : "I couldn't apply the colors"
              '${applyMessage == null ? '.' : ' — $applyMessage'}';

  final noGame = dispatchResult.noGameFoundMessage;
  if (noGame != null) {
    // The dispatcher's sentence already claims the colours were applied;
    // replace that clause with what actually happened.
    var text = noGame
        .replaceAll(", but I've applied the colors anyway.", '.')
        .replaceAll(", but I've applied the colors anyway", '.');
    if (colorsSentence != null) text = '$text $colorsSentence';
    return text;
  }
  if (!dispatchResult.success || dispatchResult.createdSessionIds.isEmpty) {
    debugPrint(
        '[Lumina ${surface.name}] ephemeral dispatch failed: ${dispatchResult.errorMessage}');
    final team = dispatchResult.teamDisplayName;
    final revert = "I couldn't set the post-game revert"
        '${team == null ? '' : ' for the $team game'}'
        ' — your lights will stay on this look after the game.';
    return colorsSentence == null || applied == true
        ? revert
        : '$colorsSentence $revert';
  }
  final labels = dispatchResult.sessionLabels;
  final armed = labels.length == 1
      ? '✓ Will revert to ${dispatchResult.revertLabel} when ${labels.first} ends.'
      : '✓ Will revert to ${dispatchResult.revertLabel} after each game ends: ${labels.join(', ')}.';
  return applied == false && colorsSentence != null
      ? '$colorsSentence $armed'
      : armed;
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
/// segment. Returns null when the payload cannot be read at all — and, from
/// +110 (row 112), when it carries NO colours: a power or brightness command
/// gets no manufactured swatches and no lighting card.
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
    int? pal;
    // The DESIGN segment, not seg[0]: after channel filtering seg[0] can be the
    // `{id: 0, on: false}` exclusion marker (UX audit pattern P6).
    // A `wled` that is not a map is an unreadable payload: no preview, as
    // before.
    if (wled is! Map) return null;
    final first = firstRealDesignSegment(wled);
    if (first != null) {
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

    // UX audit row 112: no colours → no preview. The card and the hero read
    // colours from here, so a "turn on" reply no longer paints cyan-and-navy
    // swatches into either.
    if (colors.isEmpty) return null;

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
