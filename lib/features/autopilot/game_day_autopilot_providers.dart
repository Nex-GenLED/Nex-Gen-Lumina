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
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/services/espn_api_service.dart';
import '../sports_alerts/services/game_schedule_service.dart';
import '../wled/wled_providers.dart';
import 'game_day_autopilot_config.dart';
import 'game_day_autopilot_service.dart';

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

  @override
  Map<String, AutopilotSession> build() {
    // Start the periodic evaluation loop.
    _evaluationTimer?.cancel();
    _evaluationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _evaluate(),
    );

    // Wire session change notifications to state updates.
    final service = ref.watch(gameDayAutopilotServiceProvider);
    service.onSessionChanged = (session) {
      state = {...state, session.teamSlug: session};
    };

    ref.onDispose(() {
      _evaluationTimer?.cancel();
    });

    // Run initial evaluation after a short delay.
    Future.delayed(const Duration(seconds: 5), _evaluate);

    return const {};
  }

  Future<void> _evaluate() async {
    final configs = ref.read(enabledAutopilotConfigsProvider);
    if (configs.isEmpty) return;

    final service = ref.read(gameDayAutopilotServiceProvider);
    await service.evaluateConfigs(configs);
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
    }

    // If disabling, cancel any active session.
    if (!enabled) {
      ref.read(gameDayAutopilotServiceProvider).cancelSession(teamSlug);
      state = Map.from(state)..remove(teamSlug);
    }
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
