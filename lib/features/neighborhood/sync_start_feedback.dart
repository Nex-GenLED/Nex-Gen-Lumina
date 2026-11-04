// lib/features/neighborhood/sync_start_feedback.dart
//
// What the Start button does with a SyncStartResult, as two PURE functions
// so the mapping is tested without pumping the panel (whose build reads
// FirebaseAuth.instance):
//
//   * shouldMarkEngineActive — the local listener is mounted only once the
//     group command document was acknowledged. Until 2026-11-02 the panel set
//     it the instant the tap happened, before anything had resolved.
//   * syncStartFeedbackFor — one plain-text line for every outcome that is not
//     a clean success: nothing fired (with the reason), rate-limited, or the
//     app-open broadcast fired but the fan-out to closed-app homes did not.
//     Until 2026-11-02 only the rate-limit had a message.
//
// Text is plain and names no third party.

import '../design/per_pixel_payload_guard.dart' show kPerPixelSyncRefusedMessage;
import 'neighborhood_providers.dart' show SyncStartResult;
import 'sync_per_pixel_guard.dart' show kSyncPerPixelFailureReason;

enum SyncStartFeedbackLevel { error, warning }

class SyncStartFeedback {
  final String text;
  final SyncStartFeedbackLevel level;
  const SyncStartFeedback(this.text, this.level);

  bool get isError => level == SyncStartFeedbackLevel.error;
}

/// The engine (command listener) may be mounted for this Start.
bool shouldMarkEngineActive(SyncStartResult r) => r.commandWritten;

/// The line to show for [r], or null for a clean success / flag-off start.
SyncStartFeedback? syncStartFeedbackFor(SyncStartResult r) {
  final failure = r.failure;
  if (failure != null) {
    return SyncStartFeedback(_failureText(failure.reason), SyncStartFeedbackLevel.error);
  }
  final fanout = r.fanout;
  if (fanout == null) return null; // flag off: app-open broadcast only, as before
  if (fanout.rateLimited) {
    final secs = (fanout.retryAfterMs / 1000).ceil();
    return SyncStartFeedback(
      'Hang on — try again in ${secs < 1 ? 1 : secs}s.',
      SyncStartFeedbackLevel.warning,
    );
  }
  if (!fanout.ok) {
    final why = fanout.detail != null && fanout.detail!.isNotEmpty
        ? '${fanout.reason ?? 'failed'}: ${fanout.detail}'
        : (fanout.reason ?? 'failed');
    return SyncStartFeedback(
      'Started for homes with the app open, but homes with the app closed '
      "weren't reached ($why). Try again in a moment.",
      SyncStartFeedbackLevel.warning,
    );
  }
  if (fanout.hostOnly) {
    return const SyncStartFeedback(
      "Started for homes with the app open. This group isn't enabled for "
      "closed-app delivery, so neighbors with the app closed weren't included.",
      SyncStartFeedbackLevel.warning,
    );
  }
  if ((fanout.commandCount ?? 0) == 0) {
    return const SyncStartFeedback(
      'Started for homes with the app open, but no closed-app homes were reached.',
      SyncStartFeedbackLevel.warning,
    );
  }
  final skipped = fanout.skipped ?? 0;
  if (skipped > 0) {
    return SyncStartFeedback(
      'Sync started. $skipped neighbor${skipped == 1 ? '' : 's'} with the app '
      "closed ${skipped == 1 ? 'was' : 'were'} skipped (paused, or the controller isn't set up for sync).",
      SyncStartFeedbackLevel.warning,
    );
  }
  return null;
}

String _failureText(String reason) {
  switch (reason) {
    case 'flag_unavailable':
      return "Couldn't check the sync settings. Nothing was started. "
          'Check your connection and try again.';
    case 'write_timeout':
      return "The sync command didn't go through in time. Nothing was started. "
          'Check your connection and try again.';
    // Roofline slice 1, item 4: a painted design was refused before anything
    // fired (sync_per_pixel_guard.dart).
    case kSyncPerPixelFailureReason:
      return kPerPixelSyncRefusedMessage;
    default:
      return "Couldn't start the sync. Nothing was sent. Please try again.";
  }
}
