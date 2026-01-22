import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

/// Streams the current user's schedules from Firestore.
/// This is the source of truth for schedule data.
final userSchedulesStreamProvider = StreamProvider<List<ScheduleItem>>((ref) {
  final user = ref.watch(authStateProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
  if (user == null) return const Stream.empty();

  final userService = ref.watch(userServiceProvider);
  return userService.streamSchedules(user.uid);
});

/// Notifier that manages schedule state and syncs with Firestore.
/// Changes are persisted immediately to Firestore.
class SchedulesNotifier extends StateNotifier<List<ScheduleItem>> {
  final Ref _ref;
  bool _initialized = false;

  SchedulesNotifier(this._ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    // Listen to the stream provider for initial data and updates
    _ref.listen<AsyncValue<List<ScheduleItem>>>(
      userSchedulesStreamProvider,
      (previous, next) {
        next.whenData((schedules) {
          if (!_initialized || state != schedules) {
            state = schedules;
            _initialized = true;
            debugPrint('SchedulesNotifier: Loaded ${schedules.length} schedules from Firestore');
          }
        });
      },
      fireImmediately: true,
    );
  }

  String? get _userId {
    return _ref.read(authStateProvider).maybeWhen(
          data: (u) => u?.uid,
          orElse: () => null,
        );
  }

  /// Toggle a schedule's enabled state
  Future<void> toggle(String id, bool value) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot toggle - no user signed in');
      return;
    }

    // Optimistically update local state
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(enabled: value) else s,
    ];

    // Persist to Firestore
    try {
      final schedule = state.firstWhere((s) => s.id == id);
      await _ref.read(userServiceProvider).updateSchedule(userId, schedule);
      debugPrint('Schedule $id toggled to $value and saved');
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist toggle: $e');
    }
  }

  /// Add a new schedule
  Future<void> add(ScheduleItem item) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot add - no user signed in');
      return;
    }

    // Optimistically update local state
    state = [...state, item];

    // Persist to Firestore
    try {
      await _ref.read(userServiceProvider).addSchedule(userId, item);
      debugPrint('Schedule added and saved: ${item.id}');
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist add: $e');
      // Revert on failure
      state = state.where((s) => s.id != item.id).toList();
    }
  }

  /// Remove a schedule by ID
  Future<void> remove(String id) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot remove - no user signed in');
      return;
    }

    // Store for potential revert
    final removed = state.firstWhere((s) => s.id == id, orElse: () => throw Exception('Not found'));

    // Optimistically update local state
    state = state.where((s) => s.id != id).toList();

    // Persist to Firestore
    try {
      await _ref.read(userServiceProvider).removeSchedule(userId, id);
      debugPrint('Schedule removed and saved: $id');
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist remove: $e');
      // Revert on failure
      state = [...state, removed];
    }
  }

  /// Update an existing schedule
  Future<void> update(ScheduleItem item) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot update - no user signed in');
      return;
    }

    // Store old value for potential revert
    final oldItem = state.firstWhere((s) => s.id == item.id, orElse: () => throw Exception('Not found'));

    // Optimistically update local state
    state = [for (final s in state) if (s.id == item.id) item else s];

    // Persist to Firestore
    try {
      await _ref.read(userServiceProvider).updateSchedule(userId, item);
      debugPrint('Schedule updated and saved: ${item.id}');
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist update: $e');
      // Revert on failure
      state = [for (final s in state) if (s.id == item.id) oldItem else s];
    }
  }

  /// Replace all schedules (used by Autopilot)
  Future<void> replaceAll(List<ScheduleItem> schedules) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot replace - no user signed in');
      return;
    }

    // Store old state for potential revert
    final oldState = state;

    // Optimistically update local state
    state = schedules;

    // Persist to Firestore
    try {
      await _ref.read(userServiceProvider).saveSchedules(userId, schedules);
      debugPrint('All schedules replaced and saved: ${schedules.length} items');
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist replaceAll: $e');
      // Revert on failure
      state = oldState;
    }
  }

  /// Add multiple schedules at once (used by Autopilot)
  Future<void> addAll(List<ScheduleItem> items) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot addAll - no user signed in');
      return;
    }

    // Merge with existing, avoiding duplicates by ID
    final existingIds = state.map((s) => s.id).toSet();
    final newItems = items.where((i) => !existingIds.contains(i.id)).toList();
    final merged = [...state, ...newItems];

    // Optimistically update local state
    final oldState = state;
    state = merged;

    // Persist to Firestore
    try {
      await _ref.read(userServiceProvider).saveSchedules(userId, merged);
      debugPrint('Added ${newItems.length} new schedules, total: ${merged.length}');
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist addAll: $e');
      state = oldState;
    }
  }
}

final schedulesProvider = StateNotifierProvider<SchedulesNotifier, List<ScheduleItem>>(
  (ref) => SchedulesNotifier(ref),
);

/// Helper class to find what schedule should be running at a given time.
/// Handles parsing of schedule times including sunrise/sunset triggers.
class ScheduleFinder {
  /// Finds the most recent schedule that should have started by [now] for [today].
  /// Returns null if no schedule applies.
  ///
  /// Logic:
  /// 1. Filter schedules that apply to today's day of week
  /// 2. Parse their trigger times (specific time or solar event)
  /// 3. Find the most recent one that has passed
  static ScheduleItem? findCurrentSchedule(
    List<ScheduleItem> schedules,
    DateTime now, {
    double? latitude,
    double? longitude,
  }) {
    if (schedules.isEmpty) return null;

    // Get today's day abbreviation (Sun, Mon, Tue, Wed, Thu, Fri, Sat)
    final dayAbbrs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final todayAbbr = dayAbbrs[now.weekday % 7].toLowerCase();

    // Filter to enabled schedules that apply to today
    final todaySchedules = schedules.where((s) {
      if (!s.enabled) return false;
      final daysLower = s.repeatDays.map((d) => d.toLowerCase()).toList();
      if (daysLower.contains('daily')) return true;
      return daysLower.any((d) => d.startsWith(todayAbbr));
    }).toList();

    if (todaySchedules.isEmpty) return null;

    // Parse schedule times and find the most recent one that has passed
    ScheduleItem? mostRecent;
    DateTime? mostRecentTime;

    for (final schedule in todaySchedules) {
      final triggerTime = _parseScheduleTime(schedule, now, latitude, longitude);
      if (triggerTime == null) continue;

      // Only consider schedules whose trigger time has passed
      if (triggerTime.isAfter(now)) continue;

      // Find the most recent (closest to now but in the past)
      if (mostRecentTime == null || triggerTime.isAfter(mostRecentTime)) {
        mostRecentTime = triggerTime;
        mostRecent = schedule;
      }
    }

    return mostRecent;
  }

  /// Parses the timeLabel from a schedule into an actual DateTime for today.
  /// Handles:
  /// - "Sunset" / "Sunrise" (requires lat/lon)
  /// - "7:00 PM", "10:30 AM" etc.
  static DateTime? _parseScheduleTime(
    ScheduleItem schedule,
    DateTime now,
    double? latitude,
    double? longitude,
  ) {
    final label = schedule.timeLabel.trim().toLowerCase();

    // Handle solar events
    if (label == 'sunset') {
      if (latitude == null || longitude == null) return null;
      return SunUtils.sunsetLocal(latitude, longitude, now);
    }
    if (label == 'sunrise') {
      if (latitude == null || longitude == null) return null;
      return SunUtils.sunriseLocal(latitude, longitude, now);
    }

    // Parse time format like "7:00 PM", "10:30 AM"
    final timeRegex = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$', caseSensitive: false);
    final match = timeRegex.firstMatch(schedule.timeLabel.trim());
    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final ampm = match.group(3)!.toLowerCase();

    // Convert to 24-hour format
    if (ampm == 'pm' && hour != 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;

    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}

/// Provider that returns the currently applicable schedule item based on
/// the current time and day of week.
final currentScheduledActionProvider = Provider<ScheduleItem?>((ref) {
  final schedules = ref.watch(schedulesProvider);
  final user = ref.watch(currentUserProfileProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );

  final now = DateTime.now();
  return ScheduleFinder.findCurrentSchedule(
    schedules,
    now,
    latitude: user?.latitude,
    longitude: user?.longitude,
  );
});
