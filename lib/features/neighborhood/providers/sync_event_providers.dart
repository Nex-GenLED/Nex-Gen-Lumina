import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_event.dart';
import '../neighborhood_providers.dart';
import '../services/autopilot_sync_trigger.dart';
import '../services/season_boundary_service.dart';
import '../services/sync_event_background_persistence.dart';
import '../services/sync_event_service.dart';
import '../services/sync_session_manager.dart';
import '../../sports_alerts/services/sports_background_service.dart';
import '../widgets/season_schedule_picker.dart';

// ── Sync Events ──────────────────────────────────────────────────────

/// Stream all sync events for the active neighborhood group.
final syncEventsProvider = StreamProvider<List<SyncEvent>>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value([]);
  final service = ref.watch(syncEventServiceProvider);
  return service.watchSyncEvents(groupId);
});

/// Stream enabled sync events only.
final enabledSyncEventsProvider = Provider<List<SyncEvent>>((ref) {
  final events = ref.watch(syncEventsProvider).valueOrNull ?? [];
  return events.where((e) => e.isEnabled).toList();
});

/// Count of upcoming sync events (for badge display).
final upcomingSyncEventCountProvider = Provider<int>((ref) {
  final events = ref.watch(enabledSyncEventsProvider);
  return events.length;
});

// ── Active Session ───────────────────────────────────────────────────

/// Stream the currently active sync event session.
final activeSyncEventSessionProvider =
    StreamProvider<SyncEventSession?>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value(null);
  final service = ref.watch(syncEventServiceProvider);
  return service.watchActiveSession(groupId);
});

/// Whether there is an active autopilot sync session running.
final isInAutopilotSyncProvider = Provider<bool>((ref) {
  return ref.watch(activeSyncEventSessionProvider).valueOrNull != null;
});

/// Whether the current user is participating in the active session.
final isParticipatingInSyncProvider = Provider<bool>((ref) {
  final session = ref.watch(activeSyncEventSessionProvider).valueOrNull;
  if (session == null) return false;
  final uid = ref.watch(currentUserUidProvider);
  if (uid == null) return false;
  return session.activeParticipantUids.contains(uid);
});

/// Whether the celebration pattern is currently playing.
final isCelebratingProvider = Provider<bool>((ref) {
  final session = ref.watch(activeSyncEventSessionProvider).valueOrNull;
  return session?.isCelebrating ?? false;
});

// ── Participation Consent ────────────────────────────────────────────

/// Stream the current user's sync participation consent.
final myConsentProvider =
    StreamProvider<SyncParticipationConsent?>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  final uid = ref.watch(currentUserUidProvider);
  if (groupId == null || uid == null) return Stream.value(null);
  final service = ref.watch(syncEventServiceProvider);
  return service.watchConsent(groupId, uid);
});

/// Whether the current user has opted in to Game Day syncs.
final isOptedInToGameDayProvider = Provider<bool>((ref) {
  final consent = ref.watch(myConsentProvider).valueOrNull;
  return consent?.isOptedInTo(SyncEventCategory.gameDay) ?? false;
});

/// Whether the current user has opted in to Holiday syncs.
final isOptedInToHolidayProvider = Provider<bool>((ref) {
  final consent = ref.watch(myConsentProvider).valueOrNull;
  return consent?.isOptedInTo(SyncEventCategory.holiday) ?? false;
});

/// Whether the current user has opted in to Custom Event syncs.
final isOptedInToCustomEventProvider = Provider<bool>((ref) {
  final consent = ref.watch(myConsentProvider).valueOrNull;
  return consent?.isOptedInTo(SyncEventCategory.customEvent) ?? false;
});

// ── Season Schedule ──────────────────────────────────────────────────

/// Sync events that use "every home game this season" scheduling.
final seasonScheduleSyncEventsProvider = Provider<List<SyncEvent>>((ref) {
  final events = ref.watch(syncEventsProvider).valueOrNull ?? [];
  return events.where((e) => e.isSeasonSchedule && e.isEnabled).toList();
});

/// Check season boundary for a specific sync event.
final seasonBoundaryProvider =
    FutureProvider.family<SeasonBoundaryInfo, SyncEvent>((ref, event) {
  final service = ref.watch(gameScheduleServiceProvider);
  return checkSeasonBoundary(event: event, scheduleService: service);
});

// ── Current User UID (helper) ────────────────────────────────────────

/// Provides the current user's UID. Used by multiple providers above.
/// Falls back to null if not authenticated.
final currentUserUidProvider = Provider<String?>((ref) {
  // This reads from the existing auth state. In the actual app,
  // replace with whatever auth provider is already in use.
  try {
    return ref.watch(activeNeighborhoodProvider).valueOrNull?.creatorUid;
  } catch (_) {
    return null;
  }
});

// ── Notifier for Sync Event CRUD ─────────────────────────────────────

/// Notifier for creating, updating, deleting sync events.
class SyncEventNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final SyncEventService _service;

  SyncEventNotifier(this._ref, this._service) : super(const AsyncData(null));

  /// Create a new sync event.
  Future<String?> createSyncEvent(SyncEvent event) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return null;

    state = const AsyncLoading();
    try {
      // Check for conflicts
      if (event.scheduledTime != null) {
        final conflict = await _service.findConflict(
          groupId,
          event.scheduledTime!,
          const Duration(hours: 3),
          null,
        );
        if (conflict != null) {
          state = AsyncError(
            'Conflicts with "${conflict.name}" at that time',
            StackTrace.current,
          );
          return null;
        }
      }

      final id = await _service.createSyncEvent(groupId, event);
      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  /// Update an existing sync event.
  Future<void> updateSyncEvent(SyncEvent event) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    state = const AsyncLoading();
    try {
      await _service.updateSyncEvent(groupId, event);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Delete a sync event.
  Future<void> deleteSyncEvent(String eventId) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    state = const AsyncLoading();
    try {
      await _service.deleteSyncEvent(groupId, eventId);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Toggle enabled state.
  Future<void> toggleSyncEvent(String eventId) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;
    await _service.toggleSyncEvent(groupId, eventId);
  }

  /// Update participation consent for the current user.
  Future<void> updateMyConsent(SyncParticipationConsent consent) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;
    await _service.saveConsent(groupId, consent);
  }

  /// Toggle a specific category opt-in.
  Future<void> toggleCategoryOptIn(SyncEventCategory category) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    final uid = _ref.read(currentUserUidProvider);
    if (groupId == null || uid == null) return;

    final existing = await _service.getConsent(groupId, uid);
    final optIns = Map<SyncEventCategory, bool>.from(
      existing?.categoryOptIns ?? {},
    );
    optIns[category] = !(optIns[category] ?? false);

    await _service.saveConsent(
      groupId,
      SyncParticipationConsent(
        oderId: uid,
        categoryOptIns: optIns,
        skipNextEventIds: existing?.skipNextEventIds ?? [],
        preferredPostBehavior:
            existing?.preferredPostBehavior ?? PostEventBehavior.returnToAutopilot,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Set post-event behavior preference.
  Future<void> setPostEventBehavior(PostEventBehavior behavior) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    final uid = _ref.read(currentUserUidProvider);
    if (groupId == null || uid == null) return;

    final existing = await _service.getConsent(groupId, uid);
    await _service.saveConsent(
      groupId,
      (existing ?? SyncParticipationConsent(
        oderId: uid,
        updatedAt: DateTime.now(),
      )).copyWith(
        preferredPostBehavior: behavior,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Toggle "Skip Next" for a specific event.
  Future<void> toggleSkipNext(String eventId, {required bool skip}) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    final uid = _ref.read(currentUserUidProvider);
    if (groupId == null || uid == null) return;
    await _service.toggleSkipNextEvent(groupId, uid, eventId, skip: skip);
  }

  /// "Not tonight" — decline current active session.
  Future<void> declineCurrentSession() async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    final uid = _ref.read(currentUserUidProvider);
    if (groupId == null || uid == null) return;
    final manager = _ref.read(syncSessionManagerProvider);
    await manager.declineCurrentSession(groupId, uid);
  }

  /// Late-join the current active session.
  Future<void> joinCurrentSession() async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    final uid = _ref.read(currentUserUidProvider);
    if (groupId == null || uid == null) return;
    final manager = _ref.read(syncSessionManagerProvider);
    await manager.joinCurrentSession(groupId, uid);
  }

  /// Manually start a sync event session (for manual trigger type).
  Future<void> manuallyStartEvent(String eventId) async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;
    final event = await _service.getSyncEvent(groupId, eventId);
    if (event == null) return;
    final manager = _ref.read(syncSessionManagerProvider);
    await manager.startSession(groupId: groupId, event: event);
  }

  /// Manually end the current active session.
  Future<void> manuallyEndSession() async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;
    final session = await _service.getActiveSession(groupId);
    if (session == null) return;
    final manager = _ref.read(syncSessionManagerProvider);
    await manager.endSession(groupId, session.id);
  }
}

final syncEventNotifierProvider =
    StateNotifierProvider<SyncEventNotifier, AsyncValue<void>>((ref) {
  final service = ref.watch(syncEventServiceProvider);
  return SyncEventNotifier(ref, service);
});

// ── Autopilot Trigger Controller ─────────────────────────────────────

/// Controls whether the autopilot sync trigger is actively monitoring.
/// Starts monitoring when there are enabled sync events in the active group.
/// Also persists sync events for the background service and starts it.
final syncTriggerControllerProvider = Provider<void>((ref) {
  final events = ref.watch(enabledSyncEventsProvider);
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  final trigger = ref.watch(autopilotSyncTriggerProvider);

  if (events.isNotEmpty && groupId != null) {
    // Start in-process monitoring (for when app is open)
    trigger.startMonitoring(groupId);

    // Persist events for background service (for when app is closed)
    _syncEventsToBackground(events, groupId);
  } else {
    trigger.stopMonitoring();
  }
});

/// Persist sync events to SharedPreferences and start the background service.
/// This ensures the background isolate can monitor events when the app is closed.
Future<void> _syncEventsToBackground(
  List<SyncEvent> events,
  String groupId,
) async {
  try {
    // Convert to background-friendly format
    final configs = events
        .map((e) => BackgroundSyncEventConfig.fromSyncEvent(e))
        .toList();

    // Save events and group context
    await saveSyncEventsForBackground(configs);
    await saveSyncGroupId(groupId);

    // Save current user UID for Cloud Function auth
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await saveSyncUserUid(uid);
    }

    // Notify the background service that events changed
    notifySyncEventsChanged();

    // Ensure the background service is running
    final hasNonManual = events.any(
      (e) => e.triggerType != SyncEventTriggerType.manual,
    );
    if (hasNonManual) {
      await startSyncEventService();
    }

    debugPrint(
      '[SyncTriggerController] Persisted ${configs.length} events for background',
    );
  } catch (e) {
    debugPrint('[SyncTriggerController] Failed to sync to background: $e');
  }
}
