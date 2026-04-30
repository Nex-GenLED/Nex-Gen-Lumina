import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_detector.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
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
/// All mutations use optimistic local updates with revert-on-failure,
/// automatic retry, server verification, and user-visible error reporting.
class SchedulesNotifier extends StateNotifier<List<ScheduleItem>> {
  final Ref _ref;
  bool _initialized = false;

  /// Guard flag: while a local mutation is being persisted to Firestore,
  /// suppress stream-listener overwrites to prevent flash-back-to-old-data.
  bool _isMutating = false;

  SchedulesNotifier(this._ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    // Listen to the stream provider for initial data and updates
    _ref.listen<AsyncValue<List<ScheduleItem>>>(
      userSchedulesStreamProvider,
      (previous, next) {
        next.whenData((schedules) {
          // Skip stream updates while a local mutation is in-flight
          if (_isMutating) return;
          if (!_initialized || !_listEquals(state, schedules)) {
            state = schedules;
            _initialized = true;
            debugPrint('SchedulesNotifier: Loaded ${schedules.length} schedules from Firestore');
          }
        });
      },
      fireImmediately: true,
    );
  }

  /// Deep-compare two schedule lists by ID and enabled state.
  static bool _listEquals(List<ScheduleItem> a, List<ScheduleItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].enabled != b[i].enabled) return false;
    }
    return true;
  }

  String? get _userId {
    return _ref.read(authStateProvider).maybeWhen(
          data: (u) => u?.uid,
          orElse: () => null,
        );
  }

  // ─── Error surfacing ───────────────────────────────────────────

  /// Shows a persistent snackbar with a retry action when a schedule
  /// write fails after all automatic retries.
  void _showSaveError(String operation, VoidCallback retry) {
    final messenger = AppRouter.scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          "Schedule couldn't be saved — check your connection and try again",
        ),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'RETRY',
          onPressed: retry,
        ),
      ),
    );
  }

  // ─── Conflict detection ─────────────────────────────────────────

  /// Check for conflicts before adding a schedule.
  /// Returns info the caller can pass to [showScheduleConflictDialog].
  ScheduleConflictInfo checkConflictsForAdd(ScheduleItem item,
      {String? excludeId}) {
    final calEntries = _ref.read(calendarScheduleProvider);
    return ScheduleConflictInfo(
      conflictingItems: ScheduleConflictDetector.findItemConflicts(
        incoming: item,
        existing: state,
        excludeId: excludeId,
      ),
      conflictingEntryKeys: ScheduleConflictDetector.findEntryConflictsForItem(
        item: item,
        calendarEntries: calEntries,
      ),
      calendarEntries: calEntries,
    );
  }

  // ─── Mutations ─────────────────────────────────────────────────

  /// Toggle a schedule's enabled state
  Future<void> toggle(String id, bool value) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot toggle - no user signed in');
      return;
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(enabled: value) else s,
    ];

    // Persist to Firestore (returns false on failure after retries)
    final schedule = state.firstWhere((s) => s.id == id);
    final success = await _ref.read(userServiceProvider).updateSchedule(userId, schedule);

    if (success) {
      debugPrint('Schedule $id toggled to $value and saved');
    } else {
      debugPrint('SchedulesNotifier: Failed to persist toggle — reverting');
      state = oldState;
      _showSaveError('toggle', () => toggle(id, value));
    }

    _isMutating = false;
  }

  /// Add a new schedule.
  /// Pass [resolution] after showing the conflict dialog to handle overlaps.
  Future<void> add(ScheduleItem item,
      {ConflictResolution? resolution}) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot add - no user signed in');
      return;
    }

    // ── Conflict resolution (before optimistic update) ───────────
    if (resolution == ConflictResolution.cancel) return;
    if (resolution == ConflictResolution.removeExisting) {
      final conflicts = checkConflictsForAdd(item);
      for (final c in conflicts.conflictingItems) {
        await remove(c.id);
      }
      final calNotifier = _ref.read(calendarScheduleProvider.notifier);
      for (final key in conflicts.conflictingEntryKeys) {
        await calNotifier.removeEntry(key);
      }
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = [...state, item];

    // Persist to Firestore
    final success = await _ref.read(userServiceProvider).addSchedule(userId, item);

    if (success) {
      debugPrint('Schedule added and saved: ${item.id}');
    } else {
      debugPrint('SchedulesNotifier: Failed to persist add — reverting');
      state = oldState;
      _showSaveError('add', () => add(item));
    }

    _isMutating = false;
  }

  /// Remove a schedule by ID
  Future<void> remove(String id) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot remove - no user signed in');
      return;
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = state.where((s) => s.id != id).toList();

    // Persist to Firestore
    final success = await _ref.read(userServiceProvider).removeSchedule(userId, id);

    if (success) {
      debugPrint('Schedule removed and saved: $id');
    } else {
      debugPrint('SchedulesNotifier: Failed to persist remove — reverting');
      state = oldState;
      _showSaveError('remove', () => remove(id));
    }

    _isMutating = false;
  }

  /// Update an existing schedule
  Future<void> update(ScheduleItem item) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot update - no user signed in');
      return;
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = [for (final s in state) if (s.id == item.id) item else s];

    // Persist to Firestore
    final success = await _ref.read(userServiceProvider).updateSchedule(userId, item);

    if (success) {
      debugPrint('Schedule updated and saved: ${item.id}');
    } else {
      debugPrint('SchedulesNotifier: Failed to persist update — reverting');
      state = oldState;
      _showSaveError('update', () => update(item));
    }

    _isMutating = false;
  }

  /// Replace all schedules (used by Autopilot)
  Future<void> replaceAll(List<ScheduleItem> schedules) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot replace - no user signed in');
      return;
    }

    _isMutating = true;

    // Store old state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = schedules;

    // Persist to Firestore
    final success = await _ref.read(userServiceProvider).saveSchedules(userId, schedules);

    if (success) {
      debugPrint('All schedules replaced and saved: ${schedules.length} items');
    } else {
      debugPrint('SchedulesNotifier: Failed to persist replaceAll — reverting');
      state = oldState;
      _showSaveError('replaceAll', () => replaceAll(schedules));
    }

    _isMutating = false;
  }

  /// Add multiple schedules at once (used by Autopilot).
  ///
  /// Dedups by id AND by content fingerprint (timeLabel, offTimeLabel,
  /// repeatDays, actionLabel, enabled). Content-fingerprint dedup is the
  /// load-bearing one for autopilot: AutopilotGenerationService stamps fresh
  /// UUIDs on every regen, so id-only dedup lets duplicate items slip in
  /// whenever two regen paths fire close together (e.g. boot-time
  /// runAutopilotRegenIfNeeded racing with the schedule page's
  /// _maybeAutoTrigger).
  Future<void> addAll(List<ScheduleItem> items) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot addAll - no user signed in');
      return;
    }

    _isMutating = true;

    final oldState = List<ScheduleItem>.from(state);

    bool isDuplicate(ScheduleItem item) => state.any((e) =>
        e.id == item.id ||
        (e.timeLabel == item.timeLabel &&
            e.offTimeLabel == item.offTimeLabel &&
            e.repeatDays.join(',') == item.repeatDays.join(',') &&
            e.actionLabel == item.actionLabel &&
            e.enabled == item.enabled));
    final newItems = items.where((i) => !isDuplicate(i)).toList();

    if (newItems.isEmpty) {
      debugPrint(
          'SchedulesNotifier: addAll skipped — all ${items.length} items already present');
      _isMutating = false;
      return;
    }

    final merged = [...state, ...newItems];

    state = merged;

    final success =
        await _ref.read(userServiceProvider).saveSchedules(userId, merged);

    if (success) {
      debugPrint(
          'Added ${newItems.length} new schedules (filtered ${items.length - newItems.length} duplicates), total: ${merged.length}');
    } else {
      debugPrint('SchedulesNotifier: Failed to persist addAll — reverting');
      state = oldState;
      _showSaveError('addAll', () => addAll(items));
    }

    _isMutating = false;
  }

  // ─── Persistence health check ──────────────────────────────────

  /// Verifies local schedule state matches the Firestore server.
  /// Runs on app launch to catch any prior sync failures.
  /// Trusts the server as the source of truth on mismatch.
  Future<void> verifyPersistence() async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final serverSchedules = await _ref
          .read(userServiceProvider)
          .fetchSchedulesFromServer(userId);

      if (!_listEquals(state, serverSchedules)) {
        debugPrint(
          'SchedulesNotifier: Cache/server mismatch — '
          'local=${state.length}, server=${serverSchedules.length}. '
          'Resyncing from server.',
        );
        state = serverSchedules;
      } else {
        debugPrint('SchedulesNotifier: Persistence verified — ${state.length} schedules in sync');
      }
    } catch (e) {
      debugPrint('SchedulesNotifier: Persistence check failed (offline?): $e');
    }
  }
}

final schedulesProvider = StateNotifierProvider<SchedulesNotifier, List<ScheduleItem>>(
  (ref) => SchedulesNotifier(ref),
);

/// Helper class to find what schedule should be running at a given time.
/// Handles parsing of schedule times including sunrise/sunset triggers.
class ScheduleFinder {
  /// Finds the schedule that should currently be active based on on/off times.
  /// Returns null if no schedule is currently active.
  ///
  /// Logic:
  /// 1. Check CalendarEntry for today (date-specific override, highest priority)
  /// 2. Filter recurring schedules that apply to today's day of week
  /// 3. For each schedule, check if we're within its on/off window
  /// 4. If a schedule has no off time, it stays active until another schedule starts
  /// 5. Return the most recently started schedule that is still active
  static ScheduleItem? findCurrentSchedule(
    List<ScheduleItem> schedules,
    DateTime now, {
    double? latitude,
    double? longitude,
    Map<String, CalendarEntry>? calendarEntries,
  }) {
    // Date-specific entries take priority over recurring schedules for today
    if (calendarEntries != null) {
      final todayKey = calendarDateKey(now);
      final entry = calendarEntries[todayKey];
      if (entry != null && entry.brightness > 0 && entry.onTime != null) {
        final onParts = entry.onTime!.split(':');
        if (onParts.length == 2) {
          final onHour = int.tryParse(onParts[0]) ?? 0;
          final onMinute = int.tryParse(onParts[1]) ?? 0;
          final onDt = DateTime(now.year, now.month, now.day, onHour, onMinute);

          if (!now.isBefore(onDt)) {
            // Check off time (if any)
            bool withinWindow = true;
            if (entry.offTime != null) {
              final offParts = entry.offTime!.split(':');
              if (offParts.length == 2) {
                final offHour = int.tryParse(offParts[0]) ?? 0;
                final offMinute = int.tryParse(offParts[1]) ?? 0;
                final offDt = DateTime(now.year, now.month, now.day, offHour, offMinute);

                // Same-day window: on < off means off is today
                if (offDt.isAfter(onDt)) {
                  withinWindow = now.isBefore(offDt);
                }
                // Overnight window (off <= on): always active after onTime today
              }
            }

            if (withinWindow) {
              // Synthesise a ScheduleItem so downstream consumers work unchanged
              final onLabel =
                  '${onHour == 0 ? 12 : onHour > 12 ? onHour - 12 : onHour}:'
                  '${onMinute.toString().padLeft(2, '0')} '
                  '${onHour < 12 ? 'AM' : 'PM'}';
              String? offLabel;
              if (entry.offTime != null) {
                final offParts = entry.offTime!.split(':');
                if (offParts.length == 2) {
                  final oh = int.tryParse(offParts[0]) ?? 0;
                  final om = int.tryParse(offParts[1]) ?? 0;
                  offLabel =
                      '${oh == 0 ? 12 : oh > 12 ? oh - 12 : oh}:'
                      '${om.toString().padLeft(2, '0')} '
                      '${oh < 12 ? 'AM' : 'PM'}';
                }
              }

              return ScheduleItem(
                id: 'cal_${entry.dateKey}',
                timeLabel: onLabel,
                offTimeLabel: offLabel,
                repeatDays: const [],
                actionLabel: 'Pattern: ${entry.patternName}',
                enabled: true,
              );
            }
          }
        }
      }
    }

    if (schedules.isEmpty) return null;

    // Get today's day abbreviation (Sun, Mon, Tue, Wed, Thu, Fri, Sat)
    final dayAbbrs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final todayAbbr = dayAbbrs[now.weekday % 7].toLowerCase();
    final yesterdayAbbr = dayAbbrs[(now.weekday - 1 + 7) % 7].toLowerCase();

    // Helper to check if schedule applies to a day
    bool appliesToDay(ScheduleItem s, String dayAbbr) {
      final daysLower = s.repeatDays.map((d) => d.toLowerCase()).toList();
      if (daysLower.contains('daily')) return true;
      return daysLower.any((d) => d.startsWith(dayAbbr));
    }

    // Filter to enabled schedules that apply to today or yesterday (for overnight schedules)
    final candidateSchedules = schedules.where((s) {
      if (!s.enabled) return false;
      return appliesToDay(s, todayAbbr) || appliesToDay(s, yesterdayAbbr);
    }).toList();

    if (candidateSchedules.isEmpty) return null;

    ScheduleItem? activeSchedule;
    DateTime? activeOnTime;

    for (final schedule in candidateSchedules) {
      // Check if this schedule started today
      if (appliesToDay(schedule, todayAbbr)) {
        final onTime = _parseTimeLabel(schedule.timeLabel, now, latitude, longitude);
        if (onTime == null) continue;

        // Has the on time passed?
        if (onTime.isAfter(now)) continue;

        // If there's an off time, check if we're still within the window
        if (schedule.hasOffTime && schedule.offTimeLabel != null) {
          final offTime = _parseTimeLabel(schedule.offTimeLabel!, now, latitude, longitude);
          if (offTime != null) {
            // Handle overnight schedules (off time is before on time = next day)
            final isOvernight = offTime.isBefore(onTime) || offTime.isAtSameMomentAs(onTime);
            if (isOvernight) {
              // Off time is tomorrow, so we're still active if we've passed on time
              // (We'll check yesterday's schedule separately)
            } else {
              // Same-day schedule: check if off time has passed
              if (now.isAfter(offTime)) continue; // Already turned off
            }
          }
        }

        // This schedule is active - check if it's more recent than others
        if (activeOnTime == null || onTime.isAfter(activeOnTime)) {
          activeOnTime = onTime;
          activeSchedule = schedule;
        }
      }

      // Check if this is an overnight schedule that started yesterday
      if (appliesToDay(schedule, yesterdayAbbr) && schedule.hasOffTime) {
        final yesterday = now.subtract(const Duration(days: 1));
        final onTime = _parseTimeLabel(schedule.timeLabel, yesterday, latitude, longitude);
        final offTime = _parseTimeLabel(schedule.offTimeLabel!, now, latitude, longitude);

        if (onTime == null || offTime == null) continue;

        // Check if this is an overnight schedule (off time would be "today")
        final isOvernight = offTime.hour < onTime.hour ||
            (offTime.hour == onTime.hour && offTime.minute <= onTime.minute);

        if (isOvernight) {
          // The off time is today - check if it hasn't passed yet
          if (now.isBefore(offTime)) {
            // This overnight schedule is still active
            // Use yesterday's on time for comparison
            if (activeOnTime == null || onTime.isAfter(activeOnTime)) {
              activeOnTime = onTime;
              activeSchedule = schedule;
            }
          }
        }
      }
    }

    return activeSchedule;
  }

  /// Parses a time label into an actual DateTime for a given day.
  /// Handles:
  /// - "Sunset" / "Sunrise" (requires lat/lon)
  /// - "7:00 PM", "10:30 AM" etc.
  static DateTime? _parseTimeLabel(
    String label,
    DateTime day,
    double? latitude,
    double? longitude,
  ) {
    final trimmed = label.trim().toLowerCase();

    // Handle solar events
    if (trimmed == 'sunset') {
      if (latitude == null || longitude == null) return null;
      return SunUtils.sunsetLocal(latitude, longitude, day);
    }
    if (trimmed == 'sunrise') {
      if (latitude == null || longitude == null) return null;
      return SunUtils.sunriseLocal(latitude, longitude, day);
    }

    // Parse time format like "7:00 PM", "10:30 AM"
    final timeRegex = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$', caseSensitive: false);
    final match = timeRegex.firstMatch(label.trim());
    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final ampm = match.group(3)!.toLowerCase();

    // Convert to 24-hour format
    if (ampm == 'pm' && hour != 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

}

/// Provider that returns the currently applicable schedule item based on
/// the current time and day of week.  Date-specific [CalendarEntry] overrides
/// take priority over recurring schedules.
final currentScheduledActionProvider = Provider<ScheduleItem?>((ref) {
  final schedules = ref.watch(schedulesProvider);
  final calEntries = ref.watch(calendarScheduleProvider);
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
    calendarEntries: calEntries,
  );
});
