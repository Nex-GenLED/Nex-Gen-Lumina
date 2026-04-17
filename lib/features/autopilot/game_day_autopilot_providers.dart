// lib/features/autopilot/game_day_autopilot_providers.dart
//
// Riverpod providers for the individual-user Game Day Autopilot feature.
//
// Wires together:
//   - GameDayAutopilotConfig (Firestore persistence)
//   - GameDayAutopilotService (pre-game / live / post-game logic)
//   - EspnApiService + GameScheduleService (ESPN polling)
//   - WledNotifier (applying payloads to the device)
//   - AutopilotProfile.preferredEffectStyles (design auto-selection)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../schedule/calendar_providers.dart';
import '../site/user_profile_providers.dart';
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/services/espn_api_service.dart';
import '../sports_alerts/services/game_schedule_service.dart';
import '../wled/wled_providers.dart';
import 'autopilot_providers.dart';
import 'game_day_autopilot_config.dart';
import 'game_day_autopilot_service.dart';
import 'game_day_background_persistence.dart';

// ---------------------------------------------------------------------------
// Service singletons
// ---------------------------------------------------------------------------

final _espnApiProvider = Provider<EspnApiService>((ref) {
  final svc = EspnApiService();
  ref.onDispose(svc.dispose);
  return svc;
});

final _gameScheduleProvider = Provider<GameScheduleService>((ref) {
  final svc = GameScheduleService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// The core autopilot service instance.
final gameDayAutopilotServiceProvider =
    Provider<GameDayAutopilotService>((ref) {
  final svc = GameDayAutopilotService(
    espnApi: ref.watch(_espnApiProvider),
    scheduleService: ref.watch(_gameScheduleProvider),
  );

  // Wire the payload callback to the WLED repository.
  svc.onApplyPayload = (payload) {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo != null) {
        repo.applyJson(payload);
      } else {
        debugPrint('[GameDayAutopilot] No WLED repository available');
      }
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to apply payload: $e');
    }
  };

  svc.onResumeNormalSchedule = () {
    debugPrint('[GameDayAutopilot] Resuming normal schedule / turning off');
    // Turn off as default post-game behavior. The autopilot scheduler
    // will pick up the next scheduled event on its next cycle.
    try {
      ref.read(wledStateProvider.notifier).togglePower(false);
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to turn off: $e');
    }
  };

  svc.onWriteCalendarEntries = (entries) async {
    try {
      final notifier = ref.read(calendarScheduleProvider.notifier);
      return await notifier.applyEntries(entries);
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to write calendar entries: $e');
      return false;
    }
  };

  svc.onGetUserLocation = () {
    try {
      final profileAsync = ref.read(currentUserProfileProvider);
      final profile = profileAsync.maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
      if (profile?.latitude == null || profile?.longitude == null) {
        return null;
      }
      return (lat: profile!.latitude!, lon: profile.longitude!);
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to get user location: $e');
      return null;
    }
  };

  svc.onGetPreferredStyles = () {
    try {
      return ref.read(preferredEffectStylesProvider);
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to read preferred styles: $e');
      return const [];
    }
  };

  svc.onGetCalendarEntry = (dateKey) {
    try {
      final entries = ref.read(calendarScheduleProvider);
      return entries[dateKey];
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to read calendar entry: $e');
      return null;
    }
  };

  ref.onDispose(svc.dispose);
  return svc;
});

// ---------------------------------------------------------------------------
// Firestore CRUD for GameDayAutopilotConfig
// ---------------------------------------------------------------------------

/// Stream of all GameDayAutopilotConfig documents for the current user.
final gameDayAutopilotConfigsProvider =
    StreamProvider<List<GameDayAutopilotConfig>>((ref) {
  final user = ref.watch(authStateProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
  if (user == null) return Stream.value(const []);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('game_day_autopilot')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => GameDayAutopilotConfig.fromFirestore(doc.data()))
          .toList());
});

/// Stream of enabled configs only (for the evaluation loop).
final enabledAutopilotConfigsProvider =
    Provider<List<GameDayAutopilotConfig>>((ref) {
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  return configsAsync.maybeWhen(
    data: (configs) => configs.where((c) => c.enabled).toList(),
    orElse: () => const [],
  );
});

// ---------------------------------------------------------------------------
// Background persistence: SharedPreferences bridge for the background isolate
// ---------------------------------------------------------------------------

/// Side-effect provider: persists Game Day configs and user context to
/// SharedPreferences so the background worker can read them when the app
/// is closed. Watches all upstream state — any change triggers a re-save.
///
/// Kept alive by [gameDayBackgroundPersistenceKeepAliveProvider] which is
/// watched from main_scaffold.dart.
final _gameDayBackgroundPersistenceProvider = Provider<void>((ref) {
  // Persist configs on any change
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  configsAsync.whenData((configs) {
    final bgConfigs = configs
        .map(BackgroundGameDayAutopilotConfig.fromConfig)
        .toList();
    unawaited(saveGameDayConfigsForBackground(bgConfigs));
  });

  // Persist user team priority
  final teamPriority = ref.watch(sportsTeamPriorityProvider);
  unawaited(saveUserTeamPriority(teamPriority));

  // Persist user preferred styles
  final preferredStyles = ref.watch(preferredEffectStylesProvider);
  unawaited(saveUserPreferredStyles(preferredStyles));

  // Persist user location and UID from profile
  final profileAsync = ref.watch(currentUserProfileProvider);
  profileAsync.whenData((profile) {
    if (profile?.latitude != null && profile?.longitude != null) {
      unawaited(saveUserLocation(BackgroundUserLocation(
        latitude: profile!.latitude!,
        longitude: profile.longitude!,
      )));
    } else {
      unawaited(saveUserLocation(null));
    }
    unawaited(saveGameDayUserUid(profile?.id));
  });
});

/// Public provider to keep the background persistence side-effect alive.
/// Watch from a top-level widget (main_scaffold.dart).
final gameDayBackgroundPersistenceKeepAliveProvider = Provider<void>((ref) {
  ref.watch(_gameDayBackgroundPersistenceProvider);
});

/// Whether a specific team has autopilot enabled.
final teamAutopilotEnabledProvider =
    Provider.family<bool, String>((ref, teamSlug) {
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  return configsAsync.maybeWhen(
    data: (configs) =>
        configs.any((c) => c.teamSlug == teamSlug && c.enabled),
    orElse: () => false,
  );
});

/// Get a specific team's autopilot config.
final teamAutopilotConfigProvider =
    Provider.family<GameDayAutopilotConfig?, String>((ref, teamSlug) {
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  return configsAsync.maybeWhen(
    data: (configs) {
      final matches = configs.where((c) => c.teamSlug == teamSlug);
      return matches.isEmpty ? null : matches.first;
    },
    orElse: () => null,
  );
});

// ---------------------------------------------------------------------------
// Notifier: CRUD operations + evaluation loop
// ---------------------------------------------------------------------------

class GameDayAutopilotNotifier extends Notifier<Map<String, AutopilotSession>> {
  Timer? _evaluationTimer;
  Timer? _refreshTimer;
  Timer? _backgroundSyncTimer;

  @override
  Map<String, AutopilotSession> build() {
    // Start the periodic evaluation loop.
    _evaluationTimer?.cancel();
    _evaluationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _evaluate(),
    );

    // Weekly calendar refresh — catches ESPN schedule changes (rescheduled
    // games, postseason additions). Runs every 24 hours, but only actually
    // hits ESPN if the cached schedule has expired (24h TTL in
    // GameScheduleService).
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => refreshAllCalendars(),
    );

    // Periodically reload background session state so the UI reflects
    // what the background worker is doing when the app opens mid-session.
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncFromBackground(),
    );

    // Wire session change notifications to state updates.
    final service = ref.watch(gameDayAutopilotServiceProvider);
    service.onSessionChanged = (session) {
      state = {...state, session.teamSlug: session};
    };

    ref.onDispose(() {
      _evaluationTimer?.cancel();
      _refreshTimer?.cancel();
      _backgroundSyncTimer?.cancel();
    });

    // Run initial evaluation after a short delay, then refresh calendars
    // to catch any newly-enabled teams or schedule changes since last launch.
    Future.delayed(const Duration(seconds: 5), () async {
      await _evaluate();
      await refreshAllCalendars();
    });

    return const {};
  }

  Future<void> _evaluate() async {
    final configs = ref.read(enabledAutopilotConfigsProvider);
    if (configs.isEmpty) return;

    final service = ref.read(gameDayAutopilotServiceProvider);
    await service.evaluateConfigs(configs);
  }

  /// Reload session state from SharedPreferences (written by the
  /// background worker) and merge with in-memory sessions. Background
  /// state takes precedence for teams it has session data for.
  Future<void> _syncFromBackground() async {
    try {
      final bgSessions = await loadGameDaySessions();
      if (bgSessions.isEmpty) return;

      final merged = Map<String, AutopilotSession>.from(state);
      bgSessions.forEach((slug, bgSession) {
        merged[slug] = _hydrateSession(bgSession);
      });
      state = merged;
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to sync from background: $e');
    }
  }

  /// Convert a BackgroundAutopilotSession into the foreground
  /// AutopilotSession model.
  AutopilotSession _hydrateSession(BackgroundAutopilotSession bg) {
    final phase = AutopilotSessionPhase.values.firstWhere(
      (p) => p.name == bg.phase,
      orElse: () => AutopilotSessionPhase.idle,
    );
    return AutopilotSession(
      teamSlug: bg.teamSlug,
      phase: phase,
      gameStart: bg.gameStart,
      gameEndDetected: bg.gameEndDetected,
      countdownEnd: bg.countdownEnd,
      activeGameId: bg.activeGameId,
      usedFallbackTimer: bg.usedFallbackTimer,
    );
  }

  /// Toggle autopilot for a team. Creates or updates the Firestore document.
  ///
  /// Throws [StateError] if the user is not authenticated, or [ArgumentError]
  /// if the team slug is unknown. Firestore errors propagate to the caller.
  Future<void> toggleAutopilot({
    required String teamSlug,
    required bool enabled,
  }) async {
    final user = ref.read(authStateProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (user == null) {
      debugPrint('[GameDayAutopilot] toggleAutopilot: no authenticated user');
      throw StateError('You must be signed in to add a Game Day team.');
    }

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('game_day_autopilot')
        .doc(teamSlug);

    final existing = await docRef.get();
    final now = DateTime.now();

    if (existing.exists) {
      await docRef.update({
        'enabled': enabled,
        'updated_at': Timestamp.fromDate(now),
      });
    } else {
      // Create a new config from kTeamColors.
      final team = kTeamColors[teamSlug];
      if (team == null) {
        debugPrint(
            '[GameDayAutopilot] toggleAutopilot: unknown team slug "$teamSlug"');
        throw ArgumentError.value(
            teamSlug, 'teamSlug', 'Unknown team — not in kTeamColors');
      }

      final config = GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: team.teamName,
        espnTeamId: team.espnTeamId,
        sport: team.sport,
        primaryColorValue: team.primary.toARGB32(),
        secondaryColorValue: team.secondary.toARGB32(),
        enabled: enabled,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(config.toFirestore());

      // Profile is the source of truth for My Teams on the Game Day screen.
      // Record this explicit user selection there so it survives cache
      // invalidations and so the UI filter picks it up.
      await _addTeamToProfile(user.uid, team.teamName);
    }

    // If disabling, cancel any active session.
    if (!enabled) {
      ref.read(gameDayAutopilotServiceProvider).cancelSession(teamSlug);
      state = Map.from(state)..remove(teamSlug);
      return;
    }

    // If enabling, populate the calendar with upcoming games.
    _populateCalendarInBackground(teamSlug);
  }

  /// Append [teamName] to the user's profile `sports_team_priority` and
  /// `sports_teams` lists (case-insensitive dedupe). Errors are logged but
  /// do not fail the outer [toggleAutopilot] call — the subcollection doc
  /// is still written and the team is still added to Game Day.
  Future<void> _addTeamToProfile(String uid, String teamName) async {
    try {
      final profileRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await profileRef.get();
      final data = snap.data() ?? const <String, dynamic>{};
      List<String> asStringList(dynamic raw) =>
          (raw as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      final priority = asStringList(data['sports_team_priority']);
      final teams = asStringList(data['sports_teams']);
      final key = teamName.trim().toLowerCase();

      final updates = <String, dynamic>{};
      if (!priority.any((t) => t.trim().toLowerCase() == key)) {
        updates['sports_team_priority'] = [...priority, teamName];
      }
      if (!teams.any((t) => t.trim().toLowerCase() == key)) {
        updates['sports_teams'] = [...teams, teamName];
      }
      if (updates.isEmpty) return;
      updates['updated_at'] = Timestamp.fromDate(DateTime.now());
      await profileRef.set(updates, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to sync team to profile: $e');
    }
  }

  /// Remove a team entirely from the user's Game Day: strips it from the
  /// profile's `sports_team_priority` / `sports_teams` arrays (the source
  /// of truth for My Teams) and deletes the matching game_day_autopilot
  /// subcollection doc. Cancels any live session.
  ///
  /// Throws [StateError] if the user is not authenticated. Profile writes
  /// propagate errors; subcollection cleanup and session cancel are best-
  /// effort and logged only.
  Future<void> removeTeam({
    required String teamSlug,
    required String teamName,
  }) async {
    final user = ref.read(authStateProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (user == null) {
      throw StateError('You must be signed in to remove a Game Day team.');
    }

    await _removeTeamFromProfile(user.uid, teamName);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('game_day_autopilot')
          .doc(teamSlug)
          .delete();
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to delete config $teamSlug: $e');
    }

    try {
      ref.read(gameDayAutopilotServiceProvider).cancelSession(teamSlug);
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to cancel session $teamSlug: $e');
    }
    state = Map.from(state)..remove(teamSlug);
  }

  /// Remove [teamName] from the user's profile `sports_team_priority` and
  /// `sports_teams` lists (case-insensitive match). No-op if absent.
  Future<void> _removeTeamFromProfile(String uid, String teamName) async {
    final profileRef =
        FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await profileRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    List<String> asStringList(dynamic raw) =>
        (raw as List?)?.map((e) => e.toString()).toList() ?? <String>[];
    final priority = asStringList(data['sports_team_priority']);
    final teams = asStringList(data['sports_teams']);
    final key = teamName.trim().toLowerCase();

    final newPriority =
        priority.where((t) => t.trim().toLowerCase() != key).toList();
    final newTeams =
        teams.where((t) => t.trim().toLowerCase() != key).toList();

    final updates = <String, dynamic>{};
    if (newPriority.length != priority.length) {
      updates['sports_team_priority'] = newPriority;
    }
    if (newTeams.length != teams.length) {
      updates['sports_teams'] = newTeams;
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = Timestamp.fromDate(DateTime.now());
    await profileRef.set(updates, SetOptions(merge: true));
  }

  /// Fire-and-forget calendar population for a team. Errors are logged
  /// but don't surface to the caller.
  void _populateCalendarInBackground(String teamSlug) {
    Future(() async {
      try {
        final configs =
            ref.read(gameDayAutopilotConfigsProvider).valueOrNull ?? [];
        final config =
            configs.where((c) => c.teamSlug == teamSlug).firstOrNull;
        if (config == null) return;

        final service = ref.read(gameDayAutopilotServiceProvider);
        final count = await service.populateCalendarForTeam(config);
        debugPrint('[GameDayAutopilot] Background calendar populate: '
            '$count entries for $teamSlug');
      } catch (e) {
        debugPrint('[GameDayAutopilot] Background populate failed: $e');
      }
    });
  }

  /// Refresh the calendar entries for all enabled autopilot teams.
  /// Called automatically every 24 hours by the refresh timer.
  /// Can also be called manually from the Game Day screen.
  Future<void> refreshAllCalendars() async {
    final configs = ref.read(enabledAutopilotConfigsProvider);
    final service = ref.read(gameDayAutopilotServiceProvider);
    for (final config in configs) {
      try {
        await service.populateCalendarForTeam(config);
      } catch (e) {
        debugPrint('[GameDayAutopilot] refreshAllCalendars failed for '
            '${config.teamSlug}: $e');
      }
    }
  }

  /// Update per-team autopilot settings (skip day games, variety mode,
  /// lead time, on/off overrides). Only non-null fields are written.
  /// Re-populates the calendar in the background after updating.
  Future<void> updateTeamSettings({
    required String teamSlug,
    bool? skipDayGames,
    AutopilotVarietyMode? designVariety,
    int? leadTimeMinutesOverride,
    String? onTimeOverride,
    String? offTimeOverride,
  }) async {
    final user = ref.read(authStateProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('game_day_autopilot')
        .doc(teamSlug);

    final updates = <String, dynamic>{
      'updated_at': Timestamp.fromDate(DateTime.now()),
    };
    if (skipDayGames != null) updates['skip_day_games'] = skipDayGames;
    if (designVariety != null) {
      updates['design_variety'] = designVariety.name;
    }
    if (leadTimeMinutesOverride != null) {
      updates['lead_time_minutes_override'] = leadTimeMinutesOverride;
    }
    if (onTimeOverride != null) updates['on_time_override'] = onTimeOverride;
    if (offTimeOverride != null) {
      updates['off_time_override'] = offTimeOverride;
    }

    await docRef.update(updates);

    // Re-populate calendar with new settings
    _populateCalendarInBackground(teamSlug);
  }

  /// Save a custom design for a team's autopilot.
  Future<void> saveDesign({
    required String teamSlug,
    required String designName,
    required Map<String, dynamic> wledPayload,
    required int effectId,
    int speed = 128,
    int intensity = 128,
    int brightness = 200,
  }) async {
    final user = ref.read(authStateProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('game_day_autopilot')
        .doc(teamSlug)
        .update({
      'design_mode': AutopilotDesignMode.saved.name,
      'saved_design_name': designName,
      'saved_design_payload': wledPayload,
      'effect_id': effectId,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Get the next game info for a team (for UI display).
  Future<DateTime?> fetchNextGame(String teamSlug) async {
    final team = kTeamColors[teamSlug];
    if (team == null) return null;

    final scheduleService = ref.read(_gameScheduleProvider);
    return scheduleService.fetchNextGameDate(team.espnTeamId, team.sport);
  }

  /// Detect conflicts between enabled autopilot teams.
  Future<List<({String team1, String team2, DateTime gameTime})>>
      checkConflicts() async {
    final configs = ref.read(enabledAutopilotConfigsProvider);
    final service = ref.read(gameDayAutopilotServiceProvider);
    return service.detectConflicts(configs);
  }
}

final gameDayAutopilotNotifierProvider =
    NotifierProvider<GameDayAutopilotNotifier, Map<String, AutopilotSession>>(
  GameDayAutopilotNotifier.new,
);

// ---------------------------------------------------------------------------
// Convenience: active session for a specific team
// ---------------------------------------------------------------------------

/// Current autopilot session phase for a specific team.
final teamAutopilotSessionProvider =
    Provider.family<AutopilotSession?, String>((ref, teamSlug) {
  final sessions = ref.watch(gameDayAutopilotNotifierProvider);
  return sessions[teamSlug];
});

/// Whether any team has an active game day autopilot session right now.
final hasActiveGameDayAutopilotProvider = Provider<bool>((ref) {
  final sessions = ref.watch(gameDayAutopilotNotifierProvider);
  return sessions.values.any((s) => s.isActive);
});
