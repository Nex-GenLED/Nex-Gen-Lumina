import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_event.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';
import '../neighborhood_sync_engine.dart';
import 'sync_celebration_service.dart';
import 'sync_notification_service.dart';
import 'autopilot_sync_trigger.dart' show syncEventServiceProvider;
import 'sync_event_service.dart';

/// Manages the full lifecycle of an Autopilot Sync Event session:
/// creation, participant resolution, host failover, dissolution.
class SyncSessionManager {
  final Ref _ref;
  final SyncEventService _eventService;
  Timer? _dissolutionTimer;
  Timer? _endingWarningTimer;
  StreamSubscription? _sessionSubscription;

  SyncSessionManager(this._ref, this._eventService);

  // ── Session Start ──────────────────────────────────────────────────

  /// Start a new sync session for a given event.
  Future<SyncEventSession?> startSession({
    required String groupId,
    required SyncEvent event,
    String? gameId,
  }) async {
    // Check for existing active session
    final existing = await _eventService.getActiveSession(groupId);
    if (existing != null) {
      debugPrint('[SyncSessionManager] Active session already exists');
      return null;
    }

    // Resolve participants: members who are opted in and not skipping
    final participants = await _resolveParticipants(groupId, event);
    if (participants.isEmpty) {
      debugPrint('[SyncSessionManager] No participants — aborting');
      return null;
    }

    // Determine host
    final hostUid = await _resolveHost(groupId, participants);
    if (hostUid == null) {
      debugPrint('[SyncSessionManager] No available host — aborting');
      return null;
    }

    // Create session
    final session = SyncEventSession(
      id: '', // Will be set by service
      syncEventId: event.id,
      groupId: groupId,
      status: event.isGameDay
          ? SyncEventSessionStatus.active
          : SyncEventSessionStatus.active,
      startedAt: DateTime.now(),
      hostUid: hostUid,
      activeParticipantUids: participants,
      gameId: gameId,
    );

    final sessionId = await _eventService.createSession(groupId, session);
    final createdSession = session.copyWith(id: sessionId);

    // Broadcast the base pattern to all participants
    await _broadcastBasePattern(groupId, event, participants);

    // Start listening for session lifecycle events
    _watchSession(groupId, sessionId, event);

    // If game day, start celebration monitoring
    if (event.isGameDay && gameId != null) {
      final celebService = _ref.read(syncCelebrationServiceProvider);
      celebService.startMonitoring(
        groupId: groupId,
        sessionId: sessionId,
        event: event,
        gameId: gameId,
      );
    }

    // Send push notification to participants
    final notificationService = _ref.read(syncNotificationServiceProvider);
    final eligible = await notificationService.filterByPreferences(
      groupId,
      participants,
      SyncNotificationType.sessionStarted,
    );
    await notificationService.notifySessionStarted(
      groupId: groupId,
      participantUids: eligible,
      eventName: event.name,
      hostName: hostUid, // In production, resolve to display name
    );

    // Clear "skip next" flags for this event
    for (final uid in participants) {
      await _eventService.toggleSkipNextEvent(
        groupId,
        uid,
        event.id,
        skip: false,
      );
    }

    debugPrint(
      '[SyncSessionManager] Session $sessionId started with ${participants.length} participants',
    );
    return createdSession;
  }

  // ── Participant Resolution ─────────────────────────────────────────

  /// Determine which members should participate in this session.
  Future<List<String>> _resolveParticipants(
    String groupId,
    SyncEvent event,
  ) async {
    final membersAsync = _ref.read(neighborhoodMembersProvider);
    final members = membersAsync.valueOrNull ?? [];
    final eligible = <String>[];

    for (final member in members) {
      // Skip offline or opted-out members
      if (!member.isOnline) continue;
      if (member.participationStatus != MemberParticipationStatus.active) {
        continue;
      }

      // Check consent for this event category
      final consent = await _eventService.getConsent(groupId, member.oderId);
      if (consent == null) continue;
      if (!consent.isOptedInTo(event.category)) continue;
      if (consent.isSkippingEvent(event.id)) continue;

      // Check if member is in manual override (user control wins)
      // This is handled at execution time, not here — include them
      // but they'll be excluded from actual pattern application

      eligible.add(member.oderId);
    }

    return eligible;
  }

  /// Find the best host for this session.
  Future<String?> _resolveHost(
    String groupId,
    List<String> participantUids,
  ) async {
    if (participantUids.isEmpty) return null;

    // Prefer the group creator if they're in the participant list
    final group = _ref.read(activeNeighborhoodProvider).valueOrNull;
    if (group != null && participantUids.contains(group.creatorUid)) {
      return group.creatorUid;
    }

    // Fall back to first participant (by join order / position index)
    return participantUids.first;
  }

  // ── Session Lifecycle ──────────────────────────────────────────────

  /// Watch a session for external changes (e.g., host failover needed).
  void _watchSession(
    String groupId,
    String sessionId,
    SyncEvent event,
  ) {
    _sessionSubscription?.cancel();
    _sessionSubscription = _eventService
        .watchActiveSession(groupId)
        .listen((session) async {
      if (session == null) return;

      // Check if host is still available — failover if not
      final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
      final hostMember = members.where((m) => m.oderId == session.hostUid);
      if (hostMember.isEmpty || !hostMember.first.isOnline) {
        await _performHostFailover(groupId, session);
      }
    });
  }

  /// Promote the next available participant as host.
  Future<void> _performHostFailover(
    String groupId,
    SyncEventSession session,
  ) async {
    final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    for (final uid in session.activeParticipantUids) {
      if (uid == session.hostUid) continue;
      final member = members.where((m) => m.oderId == uid);
      if (member.isNotEmpty && member.first.isOnline) {
        debugPrint(
          '[SyncSessionManager] Host failover: ${session.hostUid} → $uid',
        );
        await _eventService.updateSessionHost(groupId, session.id, uid);
        return;
      }
    }
    // No available host — end session gracefully
    debugPrint('[SyncSessionManager] No hosts available — ending session');
    await endSession(groupId, session.id);
  }

  // ── Session Dissolution ────────────────────────────────────────────

  /// End a session gracefully with the 30-second warning.
  Future<void> endSession(
    String groupId,
    String sessionId, {
    PostEventBehavior? defaultBehavior,
  }) async {
    final session = await _eventService.getActiveSession(groupId);
    if (session == null || session.id != sessionId) return;

    // Stop celebration monitoring
    final celebService = _ref.read(syncCelebrationServiceProvider);
    celebService.stopMonitoring();

    // Mark session as ending (30-second warning)
    await _eventService.markSessionEnding(groupId, sessionId);
    final notifService = _ref.read(syncNotificationServiceProvider);
    final endingEligible = await notifService.filterByPreferences(
      groupId,
      session.activeParticipantUids,
      SyncNotificationType.sessionEnding,
    );
    await notifService.notifySessionEnding(
      groupId: groupId,
      participantUids: endingEligible,
      eventName: 'Sync',
    );

    // Wait 30 seconds, then dissolve
    _dissolutionTimer?.cancel();
    _dissolutionTimer = Timer(const Duration(seconds: 30), () async {
      await _dissolveSession(groupId, session, defaultBehavior);
    });
  }

  /// Final dissolution — apply post-event behavior for each participant.
  Future<void> _dissolveSession(
    String groupId,
    SyncEventSession session,
    PostEventBehavior? defaultBehavior,
  ) async {
    debugPrint('[SyncSessionManager] Dissolving session ${session.id}');

    // Get the sync event for post-event behavior defaults
    final event =
        await _eventService.getSyncEvent(groupId, session.syncEventId);
    final fallbackBehavior =
        defaultBehavior ?? event?.postEventBehavior ?? PostEventBehavior.returnToAutopilot;

    // Apply per-participant post-event behavior
    for (final uid in session.activeParticipantUids) {
      final consent = await _eventService.getConsent(groupId, uid);
      final behavior = consent?.preferredPostBehavior ?? fallbackBehavior;
      await _applyPostEventBehavior(uid, behavior);
    }

    // Complete session
    await _eventService.completeSession(groupId, session.id);

    // Stop sync on the group
    final notifier = _ref.read(neighborhoodNotifierProvider.notifier);
    await notifier.stopSync();

    // Notify all participants
    final eventName = event?.name ?? 'Sync event';
    final endNotifService = _ref.read(syncNotificationServiceProvider);
    final endedEligible = await endNotifService.filterByPreferences(
      groupId,
      session.activeParticipantUids,
      SyncNotificationType.sessionEnded,
    );
    await endNotifService.notifySessionEnded(
      groupId: groupId,
      participantUids: endedEligible,
      eventName: eventName,
    );
  }

  /// Apply the appropriate post-event behavior for a single participant.
  Future<void> _applyPostEventBehavior(
    String uid,
    PostEventBehavior behavior,
  ) async {
    switch (behavior) {
      case PostEventBehavior.returnToAutopilot:
        // The sync engine stopping will naturally return them to their
        // individual autopilot schedule. No explicit action needed beyond
        // stopping sync participation.
        debugPrint('[SyncSessionManager] $uid → returning to autopilot');
        break;
      case PostEventBehavior.stayOn:
        // Don't send any new commands — the current pattern stays
        debugPrint('[SyncSessionManager] $uid → staying on current pattern');
        break;
      case PostEventBehavior.turnOff:
        // Send power-off to this participant's controller
        debugPrint('[SyncSessionManager] $uid → turning off');
        // Will be handled by the sync engine's local execution
        break;
    }
  }

  // ── "Not Tonight" opt-out ──────────────────────────────────────────

  /// Remove a participant from the current session ("Not tonight" action).
  Future<void> declineCurrentSession(String groupId, String uid) async {
    final session = await _eventService.getActiveSession(groupId);
    if (session == null) return;
    await _eventService.removeParticipant(groupId, session.id, uid);
    debugPrint('[SyncSessionManager] $uid declined session ${session.id}');
  }

  /// Late-join: a participant taps the banner to join an active session.
  Future<void> joinCurrentSession(String groupId, String uid) async {
    final session = await _eventService.getActiveSession(groupId);
    if (session == null) return;
    await _eventService.addParticipant(groupId, session.id, uid);
    debugPrint('[SyncSessionManager] $uid joined session ${session.id}');
  }

  // ── Helpers ────────────────────────────────────────────────────────

  /// Broadcast the base pattern via existing neighborhood sync infrastructure.
  Future<void> _broadcastBasePattern(
    String groupId,
    SyncEvent event,
    List<String> participantUids,
  ) async {
    final assignment = event.basePattern.toSyncAssignment();
    final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final engine = _ref.read(neighborhoodSyncEngineProvider);

    var command = engine.createSyncCommand(
      groupId: groupId,
      members: members,
      effectId: assignment.effectId,
      colors: assignment.colors,
      speed: assignment.speed,
      intensity: assignment.intensity,
      brightness: assignment.brightness,
      timingConfig: const SyncTimingConfig(),
      syncType: SyncType.simultaneous,
      patternName: event.name,
    );

    // Attach per-participant overrides if specified
    if (event.participantOverrides.isNotEmpty) {
      final overrides = event.participantOverrides.map(
        (uid, ref) => MapEntry(uid, ref.toSyncAssignment()),
      );
      command = SyncCommand(
        id: command.id,
        groupId: command.groupId,
        effectId: command.effectId,
        colors: command.colors,
        speed: command.speed,
        intensity: command.intensity,
        brightness: command.brightness,
        startTimestamp: command.startTimestamp,
        memberDelays: command.memberDelays,
        timingConfig: command.timingConfig,
        syncType: command.syncType,
        patternName: command.patternName,
        memberPatternOverrides: overrides,
      );
    }

    final notifier = _ref.read(neighborhoodNotifierProvider.notifier);
    await notifier.broadcastSync(command);
  }

  void dispose() {
    _dissolutionTimer?.cancel();
    _endingWarningTimer?.cancel();
    _sessionSubscription?.cancel();
  }
}

/// Provider for the session manager.
final syncSessionManagerProvider = Provider<SyncSessionManager>((ref) {
  final service = ref.watch(syncEventServiceProvider);
  final manager = SyncSessionManager(ref, service);
  ref.onDispose(() => manager.dispose());
  return manager;
});

// syncEventServiceProvider is defined in autopilot_sync_trigger.dart
