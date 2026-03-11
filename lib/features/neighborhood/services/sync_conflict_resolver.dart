import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session_duration_type.dart';
import '../models/sync_event.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';
import 'autopilot_sync_trigger.dart' show syncEventServiceProvider;
import 'sync_event_service.dart';

/// Handles conflict resolution for Autopilot Sync Events.
///
/// Conflicts arise when:
/// - Two sync events overlap in time
/// - A participant is manually controlling their lights when a sync starts
/// - The sports API is unreachable
class SyncConflictResolver {
  final Ref _ref;
  final SyncEventService _eventService;

  SyncConflictResolver(this._ref, this._eventService);

  /// Check if a new sync event conflicts with existing events.
  ///
  /// Duration-aware logic:
  ///   - Short vs Long → no conflict (handled by handoff system)
  ///   - Short vs Short → real conflict, use manual priority rank
  ///   - Long vs Long → real conflict, use manual priority rank
  ///
  /// Returns the conflicting event if one exists, null otherwise.
  Future<SyncEventConflict?> checkForConflicts({
    required String groupId,
    required SyncEvent proposedEvent,
  }) async {
    if (proposedEvent.scheduledTime == null) return null;

    final events = await _eventService.getEnabledSyncEvents(groupId);
    for (final existing in events) {
      if (existing.id == proposedEvent.id) continue;
      if (existing.scheduledTime == null) continue;

      final overlap = _checkTimeOverlap(
        proposedEvent.scheduledTime!,
        _estimateDuration(proposedEvent),
        existing.scheduledTime!,
        _estimateDuration(existing),
      );

      if (!overlap) continue;

      // ── Duration-aware conflict resolution ──────────────────────
      // If the two events are different duration types (short vs long),
      // the handoff system handles this automatically — not a conflict.
      if (shouldAutoOverride(
        incoming: proposedEvent.durationType,
        active: existing.durationType,
      )) {
        // Short over long — handoff handles it. Return a friendly
        // confirmation instead of a conflict warning.
        return SyncEventConflict(
          proposedEvent: proposedEvent,
          conflictingEvent: existing,
          type: ConflictType.handoffManaged,
          message:
              'During ${proposedEvent.name} your lights will switch to '
              '${proposedEvent.name}. Your ${existing.name} lights will '
              'automatically resume when it ends.',
        );
      }

      if (shouldAutoOverride(
        incoming: existing.durationType,
        active: proposedEvent.durationType,
      )) {
        // The existing short event will auto-override the proposed long one.
        return SyncEventConflict(
          proposedEvent: proposedEvent,
          conflictingEvent: existing,
          type: ConflictType.handoffManaged,
          message:
              '${existing.name} will temporarily take over during its window. '
              '${proposedEvent.name} will automatically resume afterward.',
        );
      }

      // Same duration type — real conflict, needs manual priority rank
      return SyncEventConflict(
        proposedEvent: proposedEvent,
        conflictingEvent: existing,
        type: ConflictType.timeOverlap,
        message:
            '"${proposedEvent.name}" overlaps with "${existing.name}"',
      );
    }
    return null;
  }

  /// Check if a participant is in a manual override state.
  /// Returns true if the user is manually controlling lights and should
  /// be excluded from automatic sync.
  bool isParticipantInManualOverride(String uid) {
    // Check if the member has the sync engine paused (manual control)
    final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final member = members.where((m) => m.oderId == uid);
    if (member.isEmpty) return false;
    return member.first.participationStatus == MemberParticipationStatus.paused;
  }

  /// Get all participants who are available (not in manual override,
  /// not already in another active session).
  Future<List<String>> getAvailableParticipants(
    String groupId,
    SyncEvent event,
  ) async {
    final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final available = <String>[];

    for (final member in members) {
      if (!member.isOnline) continue;
      if (member.participationStatus != MemberParticipationStatus.active) {
        continue;
      }

      // Check consent
      final consent =
          await _eventService.getConsent(groupId, member.oderId);
      if (consent == null || !consent.isOptedInTo(event.category)) continue;
      if (consent.isSkippingEvent(event.id)) continue;

      // Not in manual override
      if (!isParticipantInManualOverride(member.oderId)) {
        available.add(member.oderId);
      }
    }

    return available;
  }

  /// Resolve what should happen when a sync starts but a participant
  /// is busy with manual control.
  SyncConflictResolution resolveManualOverrideConflict(String uid) {
    // The user's manual control always wins — they're excluded from
    // automatic sync but get a banner notification to join if they want.
    return SyncConflictResolution(
      action: ConflictAction.excludeWithBanner,
      message: 'Game Day sync started — tap to join',
      excludedUid: uid,
    );
  }

  /// Check if two time ranges overlap.
  bool _checkTimeOverlap(
    DateTime start1,
    Duration duration1,
    DateTime start2,
    Duration duration2,
  ) {
    final end1 = start1.add(duration1);
    final end2 = start2.add(duration2);
    return start1.isBefore(end2) && start2.isBefore(end1);
  }

  /// Estimate how long a sync event will last.
  Duration _estimateDuration(SyncEvent event) {
    if (event.isGameDay) {
      // Average game durations by sport
      switch (event.sportLeague?.toUpperCase()) {
        case 'NFL':
          return const Duration(hours: 3, minutes: 15);
        case 'NBA':
          return const Duration(hours: 2, minutes: 30);
        case 'MLB':
          return const Duration(hours: 3);
        case 'NHL':
          return const Duration(hours: 2, minutes: 30);
        case 'MLS':
          return const Duration(hours: 2);
        default:
          return const Duration(hours: 3);
      }
    }
    // Default for non-game events
    return const Duration(hours: 2);
  }
}

// ── Models ───────────────────────────────────────────────────────────────

enum ConflictType {
  timeOverlap,
  manualOverride,
  apiUnavailable,

  /// The overlap is between different duration types (short vs long)
  /// and will be handled automatically by the handoff system.
  /// This is informational, not a blocking conflict.
  handoffManaged,
}

enum ConflictAction {
  /// Block the proposed event from being saved.
  preventSave,

  /// Exclude the participant but show a banner to join.
  excludeWithBanner,

  /// Fall back to scheduled time instead of game start.
  fallbackToScheduledTime,
}

class SyncEventConflict {
  final SyncEvent proposedEvent;
  final SyncEvent? conflictingEvent;
  final ConflictType type;
  final String message;

  const SyncEventConflict({
    required this.proposedEvent,
    this.conflictingEvent,
    required this.type,
    required this.message,
  });
}

class SyncConflictResolution {
  final ConflictAction action;
  final String message;
  final String? excludedUid;

  const SyncConflictResolution({
    required this.action,
    required this.message,
    this.excludedUid,
  });
}

// ── Provider ─────────────────────────────────────────────────────────────

final syncConflictResolverProvider = Provider<SyncConflictResolver>((ref) {
  final service = ref.watch(syncEventServiceProvider);
  return SyncConflictResolver(ref, service);
});
