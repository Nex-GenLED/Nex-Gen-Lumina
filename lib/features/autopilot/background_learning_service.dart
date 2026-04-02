import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_weekly_preview.dart';
import 'package:nexgen_command/features/autopilot/habit_learner.dart';
import 'package:nexgen_command/features/autopilot/services/autopilot_event_repository.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/services/sports_alert_service.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/autopilot_sync_trigger.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/services/suggestion_service.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/screens/commercial/commercial_mode_providers.dart';

/// Background service for running periodic habit analysis and suggestion generation.
///
/// This service should be triggered:
/// - Once per day (via WorkManager or similar)
/// - On app startup (to check for contextual suggestions)
/// - After significant usage events (optional)
class BackgroundLearningService {
  static final BackgroundLearningService _instance = BackgroundLearningService._internal();
  factory BackgroundLearningService() => _instance;
  BackgroundLearningService._internal();

  DateTime? _lastDailyRun;
  bool _isRunning = false;

  /// Tracks the last time the Sunday 7PM weekly regeneration ran.
  DateTime? _lastWeeklyRegen;

  /// Run on app startup - checks for contextual suggestions
  Future<void> onAppStartup() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      debugPrint('🚀 BackgroundLearningService: App startup check');

      final userService = UserService();
      final suggestionService = SuggestionService(
        userService: userService,
        userId: user.uid,
      );

      // Check for contextual suggestions (sunset, morning, etc.)
      await suggestionService.checkContextualSuggestions();

      debugPrint('✅ BackgroundLearningService: Startup check complete');
    } catch (e) {
      debugPrint('❌ BackgroundLearningService startup failed: $e');
    }
  }

  // ── Sunday 7PM Weekly Regeneration ────────────────────────────────────────

  /// Check whether the Sunday 7PM weekly regeneration should fire and run it
  /// if so.  Call this from [onAppStartup] and after the daily maintenance run.
  ///
  /// Fires when:
  ///   - It is Sunday and the local time is at or past 19:00 AND
  ///     regeneration has not yet run this Sunday.
  /// Missed-Sunday recovery:
  ///   - If [now] is Monday or later and [_lastWeeklyRegen] is from last week
  ///     (or null), regenerate immediately — never silently skip.
  ///
  /// Must be called from a Riverpod-aware context.
  static Future<void> checkAndRunSundayRegen(WidgetRef ref) async {
    try {
      // Commercial mode uses the day-part scheduler — skip standard autopilot
      // regeneration so the two systems don't conflict.
      final isCommercial =
          await ref.read(commercialModeEnabledProvider.future);
      if (isCommercial) return;

      final enabled = ref.read(autopilotEnabledProvider);
      if (!enabled) return;

      final now = DateTime.now();
      final service = BackgroundLearningService();

      final bool isSundayAfter7pm =
          now.weekday == DateTime.sunday && now.hour >= 19;

      // Check if we already ran during this Sunday's window.
      final lastRegen = service._lastWeeklyRegen;
      final alreadyRanThisSunday = lastRegen != null &&
          lastRegen.weekday == DateTime.sunday &&
          lastRegen.year == now.year &&
          lastRegen.month == now.month &&
          lastRegen.day == now.day;

      // Check missed-Sunday recovery: it's Monday or later and last regen
      // is from more than 7 days ago (or never ran).
      final daysSinceRegen = lastRegen != null
          ? now.difference(lastRegen).inDays
          : 999;
      final missedSunday =
          now.weekday != DateTime.sunday && daysSinceRegen >= 7;

      if ((isSundayAfter7pm && !alreadyRanThisSunday) || missedSunday) {
        debugPrint(
            '🗓️ BackgroundLearningService: running Sunday 7PM weekly regen '
            '(missed=$missedSunday, isSunday=$isSundayAfter7pm)');
        await _runWeeklyRegen(ref);
        service._lastWeeklyRegen = now;
      }
    } catch (e) {
      debugPrint('❌ Sunday regen check failed: $e');
    }
  }

  static Future<void> _runWeeklyRegen(WidgetRef ref) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final profileAsync = ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(data: (p) => p, orElse: () => null);
    if (profile == null) {
      debugPrint('⚠️ WeeklyRegen: no profile loaded, skipping');
      return;
    }

    // Pre-generation: fetch sports + holidays from providers if available.
    // The repository's runWeeklyRegeneration accepts empty lists and falls
    // back to seasonal/preferred-white defaults — safe for the first release.
    final repo = ref.read(autopilotEventRepositoryProvider);
    final calEntries = ref.read(calendarScheduleProvider);
    final result = await repo.runWeeklyRegeneration(
      uid: uid,
      profile: profile,
      sportingEvents: const [],
      holidays: const [],
      weekGeneration: DateTime.now().millisecondsSinceEpoch ~/ (7 * 86400000),
      calendarEntries: calEntries,
    );

    debugPrint(
        '✅ WeeklyRegen: generated ${result.events.length} events for upcoming week');
    if (result.hasConflicts) {
      debugPrint(
          '⚠️ WeeklyRegen: ${result.conflicts.length} conflicts need UI resolution');
    }

    // Dispatch push notification if user has opted in.
    if (profile.weeklySchedulePreviewEnabled && result.events.isNotEmpty) {
      try {
        // AutopilotNotificationService already handles this — pass through.
        // scheduleWeeklyBrief is on the notification service; trigger via
        // the existing settings service to avoid circular imports.
        await ref.read(autopilotSettingsServiceProvider).scheduleWeeklyBriefForEvents(profile, result.events);
      } catch (e) {
        debugPrint('⚠️ Weekly brief notification failed: $e');
      }
    }
  }

  /// Run daily maintenance - habit analysis and auto-favorites update
  Future<void> runDailyMaintenance({bool force = false}) async {
    // Prevent duplicate runs
    if (_isRunning) {
      debugPrint('⚠️ BackgroundLearningService: Already running, skipping');
      return;
    }

    // Check if we've already run today
    final now = DateTime.now();
    if (!force && _lastDailyRun != null) {
      final lastRun = _lastDailyRun!;
      if (now.year == lastRun.year &&
          now.month == lastRun.month &&
          now.day == lastRun.day) {
        debugPrint('⏭️ BackgroundLearningService: Already ran today, skipping');
        return;
      }
    }

    try {
      _isRunning = true;
      _lastDailyRun = now;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ BackgroundLearningService: No user, skipping');
        return;
      }

      debugPrint('🔄 BackgroundLearningService: Starting daily maintenance');

      final userService = UserService();
      final habitLearner = HabitLearner(
        userService: userService,
        userId: user.uid,
      );
      final suggestionService = SuggestionService(
        userService: userService,
        userId: user.uid,
      );

      // 1. Analyze habits (detect patterns)
      debugPrint('🧠 Analyzing user habits...');
      final habits = await habitLearner.analyzeHabits(daysToAnalyze: 30);
      debugPrint('✅ Detected ${habits.length} habits');

      // 2. Update auto-favorites
      debugPrint('⭐ Updating auto-favorites...');
      await habitLearner.updateAutoFavorites(topN: 5);
      debugPrint('✅ Auto-favorites updated');

      // 3. Generate suggestions
      debugPrint('💡 Generating smart suggestions...');
      await suggestionService.runDailySuggestionCheck();
      debugPrint('✅ Suggestions generated');

      debugPrint('✅ BackgroundLearningService: Daily maintenance complete');
    } catch (e, stack) {
      debugPrint('❌ BackgroundLearningService failed: $e');
      debugPrint('Stack trace: $stack');
    } finally {
      _isRunning = false;
    }
  }

  /// Check if we should run daily maintenance
  /// Returns true if it's been more than 20 hours since last run
  bool shouldRunDaily() {
    if (_lastDailyRun == null) return true;

    final now = DateTime.now();
    final hoursSinceLastRun = now.difference(_lastDailyRun!).inHours;

    return hoursSinceLastRun >= 20; // Run if it's been 20+ hours
  }

  /// Check if autopilot schedule is stale and regenerate if needed.
  ///
  /// This must be called from a Riverpod-aware context (e.g. a
  /// ConsumerWidget) because BackgroundLearningService itself is a plain
  /// singleton with no access to the provider graph.
  static Future<void> runAutopilotRegenIfNeeded(WidgetRef ref) async {
    try {
      // Commercial mode uses day-part scheduler — skip autopilot regen.
      final isCommercial =
          await ref.read(commercialModeEnabledProvider.future);
      if (isCommercial) return;

      final enabled = ref.read(autopilotEnabledProvider);
      final needsRegen = ref.read(needsScheduleRegenerationProvider);

      if (enabled && needsRegen) {
        debugPrint('🔄 Autopilot: regenerating stale schedule...');
        await ref
            .read(autopilotSettingsServiceProvider)
            .generateAndPopulateSchedules();
      }

      // Also check Sunday 7PM weekly regen (new autopilot_events subcollection).
      await checkAndRunSundayRegen(ref);
    } catch (e) {
      debugPrint('❌ Autopilot regen check failed: $e');
    }
  }

  /// Check today's autopilot schedule for game-day items and start monitoring.
  ///
  /// Must be called from a Riverpod-aware context.
  static Future<void> startTodayGameDayMonitoring(WidgetRef ref) async {
    try {
      final enabled = ref.read(autopilotEnabledProvider);
      if (!enabled) return;

      final scheduleAsync = ref.read(weeklyScheduleProvider);
      final schedule = scheduleAsync.maybeWhen(
        data: (items) => items,
        orElse: () => <dynamic>[],
      );
      if (schedule.isEmpty) return;

      final sportsService = ref.read(sportsAlertServiceProvider);
      await sportsService.checkAndStartTodayGames(schedule.cast());
    } catch (e) {
      debugPrint('❌ Game-day monitoring startup failed: $e');
    }
  }

  /// Start autopilot sync event monitoring for neighborhood groups.
  ///
  /// Must be called from a Riverpod-aware context.
  static Future<void> startSyncEventMonitoring(WidgetRef ref) async {
    try {
      final syncEnabled = ref.read(autopilotSyncEventsEnabledProvider);
      if (!syncEnabled) return;

      final trigger = ref.read(autopilotSyncTriggerProvider);
      final groupId = ref.read(activeNeighborhoodIdProvider);
      if (groupId == null) return;

      debugPrint('🔄 Starting autopilot sync event monitoring...');
      await trigger.startMonitoring(groupId);

      // Also persist user context for background service
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await saveSyncUserUid(uid);
        await saveSyncGroupId(groupId);
      }

      // Listen for background service session events (app in foreground)
      _listenForBackgroundSessionEvents();
    } catch (e) {
      debugPrint('❌ Sync event monitoring startup failed: $e');
    }
  }

  /// Listen for session events from the background service isolate.
  /// When the background worker initiates a session while the app is closed,
  /// these messages arrive if the user later opens the app mid-session.
  static void _listenForBackgroundSessionEvents() {
    final service = FlutterBackgroundService();

    service.on('syncSessionStarted').listen((data) {
      if (data == null) return;
      debugPrint(
        '[BackgroundLearning] Background session started: '
        '${data['eventName']} (${data['sessionId']})',
      );
      // The UI will automatically pick up the session change via
      // activeSyncEventSessionProvider which streams from Firestore.
    });

    service.on('syncSessionEnded').listen((data) {
      if (data == null) return;
      debugPrint(
        '[BackgroundLearning] Background session ended: ${data['sessionId']}',
      );
    });

    service.on('syncCelebration').listen((data) {
      if (data == null) return;
      debugPrint(
        '[BackgroundLearning] Background celebration: ${data['eventName']}',
      );
    });
  }

  /// Manual trigger for testing
  Future<void> forceRun() async {
    _lastDailyRun = null; // Reset to allow run
    await runDailyMaintenance(force: true);
  }

  /// Reset state (for testing)
  void reset() {
    _lastDailyRun = null;
    _isRunning = false;
  }
}

/// Convenience provider access
final backgroundLearningService = BackgroundLearningService();
