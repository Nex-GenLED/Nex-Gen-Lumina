import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'neighborhood_models.dart';
import 'neighborhood_service.dart';

/// Provider for the NeighborhoodService singleton.
final neighborhoodServiceProvider = Provider<NeighborhoodService>((ref) {
  return NeighborhoodService();
});

/// Stream of all neighborhood groups the current user belongs to.
final userNeighborhoodsProvider = StreamProvider<List<NeighborhoodGroup>>((ref) {
  final service = ref.watch(neighborhoodServiceProvider);
  return service.watchUserGroups();
});

/// Currently selected/active neighborhood group ID.
final activeNeighborhoodIdProvider = StateProvider<String?>((ref) => null);

/// Stream of the active neighborhood group details.
final activeNeighborhoodProvider = StreamProvider<NeighborhoodGroup?>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value(null);

  final service = ref.watch(neighborhoodServiceProvider);
  return service.watchGroup(groupId);
});

/// Stream of members in the active neighborhood group.
final neighborhoodMembersProvider = StreamProvider<List<NeighborhoodMember>>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value([]);

  final service = ref.watch(neighborhoodServiceProvider);
  return service.watchMembers(groupId);
});

/// Stream of the latest sync command for the active group.
final latestSyncCommandProvider = StreamProvider<SyncCommand?>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value(null);

  final service = ref.watch(neighborhoodServiceProvider);
  return service.watchLatestCommand(groupId);
});

/// Current sync timing configuration (user-adjustable).
final syncTimingConfigProvider = StateProvider<SyncTimingConfig>((ref) {
  return const SyncTimingConfig(
    pixelsPerSecond: 50.0,
    gapDelayMs: 0,
    reverseDirection: false,
  );
});

/// Stream of all schedules for the active neighborhood group.
final neighborhoodSchedulesProvider = StreamProvider<List<SyncSchedule>>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return Stream.value([]);

  final service = ref.watch(neighborhoodServiceProvider);
  return service.watchSchedules(groupId);
});

/// Provider for nearby public groups based on user location.
final nearbyGroupsProvider = FutureProvider.family<List<NeighborhoodGroup>, ({double lat, double lng, double radiusKm})>(
  (ref, params) async {
    final service = ref.watch(neighborhoodServiceProvider);
    return service.findNearbyGroups(
      latitude: params.lat,
      longitude: params.lng,
      radiusKm: params.radiusKm,
    );
  },
);

/// Notifier for managing neighborhood operations with state.
class NeighborhoodNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  NeighborhoodService get _service => ref.read(neighborhoodServiceProvider);

  /// Creates a new neighborhood group with enhanced options.
  Future<NeighborhoodGroup?> createGroup(
    String name, {
    String? displayName,
    String? description,
    String? streetName,
    String? city,
    bool isPublic = false,
    double? latitude,
    double? longitude,
  }) async {
    state = const AsyncValue.loading();
    try {
      final group = await _service.createGroup(
        name,
        displayName: displayName,
        description: description,
        streetName: streetName,
        city: city,
        isPublic: isPublic,
        latitude: latitude,
        longitude: longitude,
      );
      ref.read(activeNeighborhoodIdProvider.notifier).state = group.id;
      state = const AsyncValue.data(null);
      return group;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Joins an existing group using an invite code.
  Future<NeighborhoodGroup?> joinGroup(String inviteCode, {String? displayName}) async {
    state = const AsyncValue.loading();
    try {
      final group = await _service.joinGroup(inviteCode, displayName: displayName);
      if (group != null) {
        ref.read(activeNeighborhoodIdProvider.notifier).state = group.id;
      }
      state = const AsyncValue.data(null);
      return group;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Leaves the currently active group.
  Future<void> leaveCurrentGroup() async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    state = const AsyncValue.loading();
    try {
      await _service.leaveGroup(groupId);
      ref.read(activeNeighborhoodIdProvider.notifier).state = null;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Deletes the currently active group (creator only).
  Future<void> deleteCurrentGroup() async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    state = const AsyncValue.loading();
    try {
      await _service.deleteGroup(groupId);
      ref.read(activeNeighborhoodIdProvider.notifier).state = null;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Updates a member's configuration.
  Future<void> updateMember(NeighborhoodMember member) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.updateMember(groupId, member);
    } catch (e) {
      // Silent fail for member updates
    }
  }

  /// Reorders members (after drag-and-drop).
  Future<void> reorderMembers(List<String> orderedMemberIds) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.reorderMembers(groupId, orderedMemberIds);
    } catch (e) {
      // Silent fail for reorder
    }
  }

  /// Broadcasts a sync command to all members.
  Future<void> broadcastSync(SyncCommand command) async {
    state = const AsyncValue.loading();
    try {
      await _service.broadcastSyncCommand(command);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Stops the current sync.
  Future<void> stopSync() async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.stopSync(groupId);
    } catch (e) {
      // Silent fail
    }
  }

  /// Regenerates the invite code (creator only).
  Future<String?> regenerateInviteCode() async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return null;

    try {
      return await _service.regenerateInviteCode(groupId);
    } catch (e) {
      return null;
    }
  }

  /// Updates presence status.
  Future<void> updatePresence({bool isOnline = true}) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.updatePresence(groupId, isOnline: isOnline);
    } catch (e) {
      // Silent fail
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Schedule Management
  // ─────────────────────────────────────────────────────────────────────────────

  /// Creates a new schedule for the active group.
  Future<SyncSchedule?> createSchedule(SyncSchedule schedule) async {
    state = const AsyncValue.loading();
    try {
      final newSchedule = await _service.createSchedule(schedule);
      state = const AsyncValue.data(null);
      return newSchedule;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Updates an existing schedule.
  Future<void> updateSchedule(SyncSchedule schedule) async {
    state = const AsyncValue.loading();
    try {
      await _service.updateSchedule(schedule);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Deletes a schedule.
  Future<void> deleteSchedule(String scheduleId) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    state = const AsyncValue.loading();
    try {
      await _service.deleteSchedule(groupId, scheduleId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Toggles a schedule's active state.
  Future<void> toggleScheduleActive(String scheduleId, bool isActive) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.toggleScheduleActive(groupId, scheduleId, isActive);
    } catch (e) {
      // Silent fail
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Member Participation Controls
  // ─────────────────────────────────────────────────────────────────────────────

  /// Pauses sync participation for the current user.
  Future<void> pauseMySync() async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    final member = ref.read(currentUserMemberProvider);
    if (groupId == null || member == null) return;

    try {
      await _service.pauseMemberSync(groupId, member.oderId);
    } catch (e) {
      // Silent fail
    }
  }

  /// Resumes sync participation for the current user.
  Future<void> resumeMySync() async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    final member = ref.read(currentUserMemberProvider);
    if (groupId == null || member == null) return;

    try {
      await _service.resumeMemberSync(groupId, member.oderId);
    } catch (e) {
      // Silent fail
    }
  }

  /// Opts the current user out of a scheduled event.
  Future<void> optOutOfSchedule(String scheduleId) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    final member = ref.read(currentUserMemberProvider);
    if (groupId == null || member == null) return;

    try {
      await _service.optOutOfSchedule(groupId, member.oderId, scheduleId);
    } catch (e) {
      // Silent fail
    }
  }

  /// Opts the current user back in to a scheduled event.
  Future<void> optInToSchedule(String scheduleId) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    final member = ref.read(currentUserMemberProvider);
    if (groupId == null || member == null) return;

    try {
      await _service.optInToSchedule(groupId, member.oderId, scheduleId);
    } catch (e) {
      // Silent fail
    }
  }

  /// Sets the current user's participation status.
  Future<void> setMyParticipationStatus(MemberParticipationStatus status) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    final member = ref.read(currentUserMemberProvider);
    if (groupId == null || member == null) return;

    try {
      await _service.setMemberParticipationStatus(groupId, member.oderId, status);
    } catch (e) {
      // Silent fail
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Group Settings
  // ─────────────────────────────────────────────────────────────────────────────

  /// Updates the group's location for Find Nearby feature.
  Future<void> updateGroupLocation({required double latitude, required double longitude}) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.updateGroupLocation(groupId, latitude: latitude, longitude: longitude);
    } catch (e) {
      // Silent fail
    }
  }

  /// Sets the group's public visibility.
  Future<void> setGroupPublic(bool isPublic) async {
    final groupId = ref.read(activeNeighborhoodIdProvider);
    if (groupId == null) return;

    try {
      await _service.setGroupPublic(groupId, isPublic);
    } catch (e) {
      // Silent fail
    }
  }
}

/// Provider for neighborhood operations.
final neighborhoodNotifierProvider =
    NotifierProvider<NeighborhoodNotifier, AsyncValue<void>>(
  NeighborhoodNotifier.new,
);

/// Helper provider to check if user is the creator of the active group.
final isGroupCreatorProvider = Provider<bool>((ref) {
  final group = ref.watch(activeNeighborhoodProvider).valueOrNull;
  if (group == null) return false;

  // This would need to be compared with the current user's UID
  // For now, we'll return true if the group exists (will be refined)
  return true;
});

/// Provider to get the current user's member data in the active group.
final currentUserMemberProvider = Provider<NeighborhoodMember?>((ref) {
  final members = ref.watch(neighborhoodMembersProvider).valueOrNull ?? [];
  // Would need to filter by current user UID
  // For now return first member as placeholder
  return members.isNotEmpty ? members.first : null;
});

// ─────────────────────────────────────────────────────────────────────────────
// Active Sync Status Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Checks if ANY group the user belongs to has an active sync running.
/// This is used to warn users before they change their lights.
final isInActiveSyncProvider = Provider<bool>((ref) {
  final groups = ref.watch(userNeighborhoodsProvider).valueOrNull ?? [];
  return groups.any((g) => g.isActive);
});

/// Gets the currently active sync group (if any).
final activeSyncGroupProvider = Provider<NeighborhoodGroup?>((ref) {
  final groups = ref.watch(userNeighborhoodsProvider).valueOrNull ?? [];
  try {
    return groups.firstWhere((g) => g.isActive);
  } catch (_) {
    return null;
  }
});

/// Detailed status for the current user's sync participation.
class UserSyncStatus {
  final bool isInActiveSync;
  final NeighborhoodGroup? activeGroup;
  final String? activePatternName;
  final MemberParticipationStatus? participationStatus;

  const UserSyncStatus({
    this.isInActiveSync = false,
    this.activeGroup,
    this.activePatternName,
    this.participationStatus,
  });

  bool get isPaused => participationStatus == MemberParticipationStatus.paused;
  bool get isOptedOut => participationStatus == MemberParticipationStatus.optedOut;
  bool get isActivelyParticipating =>
      isInActiveSync && participationStatus == MemberParticipationStatus.active;
}

/// Provider for the current user's detailed sync status.
final userSyncStatusProvider = Provider<UserSyncStatus>((ref) {
  final activeGroup = ref.watch(activeSyncGroupProvider);
  final currentMember = ref.watch(currentUserMemberProvider);

  if (activeGroup == null) {
    return const UserSyncStatus();
  }

  return UserSyncStatus(
    isInActiveSync: activeGroup.isActive,
    activeGroup: activeGroup,
    activePatternName: activeGroup.activePatternName,
    participationStatus: currentMember?.participationStatus,
  );
});

/// Returns only members who are actively participating in sync.
/// Excludes: paused, opted out, and offline members.
final activeParticipatingMembersProvider = Provider<List<NeighborhoodMember>>((ref) {
  final members = ref.watch(neighborhoodMembersProvider).valueOrNull ?? [];

  return members.where((m) {
    // Must be online
    if (!m.isOnline) return false;
    // Must be actively participating (not paused or opted out)
    if (m.participationStatus != MemberParticipationStatus.active) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
});

/// Returns members filtered for a specific schedule (excludes those who opted out).
final activeMembersForScheduleProvider = Provider.family<List<NeighborhoodMember>, String?>((ref, scheduleId) {
  final members = ref.watch(neighborhoodMembersProvider).valueOrNull ?? [];

  return members.where((m) {
    // Must be online
    if (!m.isOnline) return false;
    // Must be actively participating (not paused)
    if (m.participationStatus == MemberParticipationStatus.paused) return false;
    // If this is for a specific schedule, check opt-out list
    if (scheduleId != null && m.isOptedOutOf(scheduleId)) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
});
