// lib/features/schedule/data/schedule_repository.dart
//
// Foundation abstraction over the persistence backend for the user's
// schedules. Introduced so the storage location (user-doc array vs.
// per-schedule subcollection) can be swapped behind a feature flag without
// touching any caller of UserService's schedule methods.
//
// Two implementations exist:
//   • LegacyArrayScheduleRepository       — the `schedules` array on
//                                           /users/{uid}. DEFAULT.
//   • SubcollectionScheduleRepository     — /users/{uid}/schedules/{id}.
//
// [scheduleRepositoryProvider] selects between them from the
// schedules_subcollection feature flag (default false → legacy).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/data/legacy_array_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/data/subcollection_schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedules_subcollection_feature_flag.dart';

/// Persistence contract for a user's automation schedules.
///
/// Every method takes the owning user's uid. Serialization is always
/// [ScheduleItem.toJson]/[ScheduleItem.fromJson] — implementations must not
/// reshape items or decode [ScheduleItem.wledPayload] (it is stored verbatim
/// as its encoded String).
abstract class ScheduleRepository {
  /// Live stream of the user's schedules. Emits on every backend change.
  Stream<List<ScheduleItem>> streamSchedules(String userId);

  /// One-shot read straight from the server (bypasses cache).
  Future<List<ScheduleItem>> fetchSchedules(String userId);

  /// Replace the entire set of schedules with [schedules].
  Future<void> saveAll(String userId, List<ScheduleItem> schedules);

  /// Append a single schedule.
  Future<void> add(String userId, ScheduleItem item);

  /// Append multiple schedules atomically.
  Future<void> addAll(String userId, List<ScheduleItem> items);

  /// Remove the schedule with [id].
  Future<void> remove(String userId, String id);

  /// Update the schedule matching [item.id] in place.
  Future<void> update(String userId, ScheduleItem item);
}

/// Selects the active [ScheduleRepository] from the schedules_subcollection
/// feature flag. Defaults to the legacy array backend (flag false / loading /
/// error), so behaviour is unchanged until the flag is explicitly flipped.
final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final useSubcollection = ref.watch(schedulesSubcollectionEnabledSyncProvider);
  return useSubcollection
      ? SubcollectionScheduleRepository()
      : LegacyArrayScheduleRepository();
});
