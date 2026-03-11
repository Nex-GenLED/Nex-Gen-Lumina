import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paused_session_state.dart';
import '../models/session_duration_type.dart';
import '../services/sync_handoff_manager.dart';

/// Stream of the current handoff state for the local user.
///
/// Widgets watch this to reflect handoff UI (paused cards, transition
/// indicators, estimated resume times, etc.).
final handoffStateProvider = StreamProvider<HandoffState>((ref) {
  final manager = ref.watch(syncHandoffManagerProvider);
  return manager.stateStream;
});

/// Whether the user currently has an active handoff (shortForm over longForm).
final hasActiveHandoffProvider = Provider<bool>((ref) {
  final state = ref.watch(handoffStateProvider).valueOrNull;
  return state?.hasActiveHandoff ?? false;
});

/// The current handoff phase (idle, shortFormActive, transitioning, etc.).
final handoffPhaseProvider = Provider<HandoffPhase>((ref) {
  final state = ref.watch(handoffStateProvider).valueOrNull;
  return state?.phase ?? HandoffPhase.idle;
});

/// The paused longForm session state (if any).
final pausedLongFormProvider = Provider<PausedSessionState?>((ref) {
  final state = ref.watch(handoffStateProvider).valueOrNull;
  return state?.pausedLongForm;
});

/// The estimated time when the longForm session will resume.
final estimatedResumeTimeProvider = Provider<DateTime?>((ref) {
  final state = ref.watch(handoffStateProvider).valueOrNull;
  return state?.estimatedResumeTime;
});

/// The active shortForm group ID that's currently controlling lights.
final activeShortFormGroupIdProvider = Provider<String?>((ref) {
  final state = ref.watch(handoffStateProvider).valueOrNull;
  return state?.activeShortFormGroupId;
});

/// Whether the user is in a victory celebration phase before handoff.
final isInVictoryCelebrationProvider = Provider<bool>((ref) {
  final phase = ref.watch(handoffPhaseProvider);
  return phase == HandoffPhase.celebratingVictory;
});

/// Whether the user's longForm session is paused by a shortForm handoff.
final isLongFormPausedByHandoffProvider = Provider<bool>((ref) {
  final state = ref.watch(handoffStateProvider).valueOrNull;
  return state?.isLongFormPaused ?? false;
});

/// Whether a specific group is the one currently paused by handoff.
final isGroupPausedByHandoffProvider =
    Provider.family<bool, String>((ref, groupId) {
  final pausedState = ref.watch(pausedLongFormProvider);
  return pausedState?.groupId == groupId;
});

/// Whether a specific group is the active shortForm controller.
final isGroupActiveShortFormProvider =
    Provider.family<bool, String>((ref, groupId) {
  final activeId = ref.watch(activeShortFormGroupIdProvider);
  return activeId == groupId;
});

/// Formatted estimated resume time string for UI display.
final estimatedResumeTimeStringProvider = Provider<String?>((ref) {
  final resumeTime = ref.watch(estimatedResumeTimeProvider);
  if (resumeTime == null) return null;

  final hour = resumeTime.hour;
  final minute = resumeTime.minute;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  final displayMinute = minute.toString().padLeft(2, '0');

  return '~$displayHour:$displayMinute $period';
});

// ── Smart Priority Suggestion Helpers ─────────────────────────────────────

/// Determines what priority suggestion to show when a user creates or joins
/// a new group, based on their existing groups' duration types.
enum PrioritySuggestionType {
  /// Game Day group — automatic handoff, no manual rank needed.
  gameDayAutomatic,

  /// Holiday group — runs in background, resumes after events.
  holidayBackground,

  /// Second shortForm group — needs manual rank for same-type conflict.
  shortFormConflict,

  /// No suggestion needed.
  none,
}

class PrioritySuggestion {
  final PrioritySuggestionType type;
  final String message;
  final String? conflictingGroupName;

  const PrioritySuggestion({
    required this.type,
    required this.message,
    this.conflictingGroupName,
  });
}

/// Computes the priority suggestion for a new group being added.
PrioritySuggestion computePrioritySuggestion({
  required SyncEventCategory newGroupCategory,
  required List<SyncEventCategory> existingGroupCategories,
  String? existingShortFormGroupName,
}) {
  final newType = newGroupCategory.defaultDurationType;

  if (newType == SessionDurationType.shortForm) {
    // Check if user already has another shortForm group
    final hasExistingShortForm = existingGroupCategories.any(
      (c) => c.defaultDurationType == SessionDurationType.shortForm,
    );

    if (hasExistingShortForm) {
      return PrioritySuggestion(
        type: PrioritySuggestionType.shortFormConflict,
        message:
            "You're already in ${existingShortFormGroupName ?? 'another game group'}. "
            'If both games overlap, which takes priority on your lights?',
        conflictingGroupName: existingShortFormGroupName,
      );
    }

    return const PrioritySuggestion(
      type: PrioritySuggestionType.gameDayAutomatic,
      message:
          'Game Day groups automatically take over your lights during game '
          'time and hand back to your other groups when the game ends — '
          'no priority setting needed for this.',
    );
  }

  // longForm group (holiday, seasonal)
  return const PrioritySuggestion(
    type: PrioritySuggestionType.holidayBackground,
    message:
        'Holiday groups run in the background and automatically resume '
        'whenever a game or event ends.',
  );
}
