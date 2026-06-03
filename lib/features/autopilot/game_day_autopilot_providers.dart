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
import '../../models/roofline_segment.dart';
import '../design/roofline_config_providers.dart';
import '../neighborhood/services/channel_participation_resolver.dart';
import '../neighborhood/services/path1_game_day_snapshot.dart';
import '../neighborhood/services/sync_event_background_persistence.dart';
import '../schedule/calendar_entry.dart';
import '../schedule/calendar_providers.dart';
import '../schedule/schedule_priority_resolver.dart';
import '../site/user_profile_providers.dart';
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/services/espn_api_service.dart';
import '../sports_alerts/services/game_schedule_service.dart';
import '../sports_alerts/services/team_registration_service.dart';
import '../wled/wled_providers.dart';
import '../wled/zone_providers.dart';
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
      final existing = ref.read(calendarScheduleProvider);

      // Phase 1 priority resolver: silently drop incoming Game Day
      // entries that would overwrite a strictly higher-priority entry
      // already on that date (user-set or holiday). Equal-priority
      // overwrites (Game Day re-running for an existing date) and
      // strictly lower-priority overwrites are kept. See
      // SchedulePriorityResolver for the 5-tier hierarchy and the
      // Phase 2 segment-composition handoff.
      final filtered = SchedulePriorityResolver.filterIncoming(
        incoming: entries,
        existing: existing,
      );
      if (filtered.dropped.isNotEmpty) {
        debugPrint('[GameDayAutopilot] Priority resolver dropped '
            '${filtered.dropped.length} entries:');
        for (final d in filtered.dropped) {
          debugPrint('  - ${d.entry.dateKey}: ${d.reason}');
        }
      }
      if (filtered.kept.isEmpty) return true;

      return await notifier.applyEntries(filtered.kept);
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

  svc.onResolveParticipatingChannels = (config) {
    try {
      final rooflineAsync = ref.read(currentRooflineConfigProvider);
      final segments = rooflineAsync.maybeWhen(
        data: (c) => c?.segments ?? const <RooflineSegment>[],
        orElse: () => const <RooflineSegment>[],
      );
      final deviceChannelIds =
          ref.read(deviceChannelsProvider).map((c) => c.id).toList();
      final resolved = resolveParticipatingChannels(
        explicit: config.participatingChannelIndices,
        segments: segments,
        allDeviceChannelIds: deviceChannelIds,
      );
      // Persist for the background isolate (Bundle 4 reads this).
      // Fire-and-forget — never block payload construction on the
      // SharedPreferences write.
      unawaited(saveLocalParticipatingChannels(resolved));
      return resolved;
    } catch (e) {
      debugPrint(
        '[GameDayAutopilot] Failed to resolve participating channels: $e',
      );
      return null;
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
  // Resolve participation inputs once (roofline + device channels) so each
  // persisted config carries its RESOLVED participating channel set for the
  // background isolate (#29). Watching both means this re-runs — and
  // re-persists with the correct set — once device channels finish loading.
  final rooflineAsync = ref.watch(currentRooflineConfigProvider);
  final segments = rooflineAsync.maybeWhen(
    data: (c) => c?.segments ?? const <RooflineSegment>[],
    orElse: () => const <RooflineSegment>[],
  );
  final deviceChannelIds =
      ref.watch(deviceChannelsProvider).map((c) => c.id).toList();

  // Persist configs on any change
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  configsAsync.whenData((configs) {
    final bgConfigs = configs.map((config) {
      final resolved = resolveParticipatingChannels(
        explicit: config.participatingChannelIndices,
        segments: segments,
        allDeviceChannelIds: deviceChannelIds,
      );
      // null = legacy fallback (worker keeps the single-seg payload → lights
      // ch1) when there's no explicit choice AND nothing meaningful resolved
      // (no channel info yet, or roofline excludes all) — never go dark from
      // incomplete data. An explicit user opt-out ([]) is honored verbatim so
      // the worker skip-applies.
      final List<int>? channelIds = config.participatingChannelIndices != null
          ? resolved
          : (resolved.isEmpty ? null : resolved);
      return BackgroundGameDayAutopilotConfig.fromConfig(
        config,
        participatingChannelIds: channelIds,
      );
    }).toList();
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

/// Convergence-Phase-2b: Path 2 reads a team's canonical Path 1
/// [GameDayAutopilotConfig] as a 3-state [Path1SnapshotResolution].
///
/// Returns one of:
///   - [Path1SnapshotLoading] — the underlying Firestore stream has
///     not yet resolved. Callers MUST NOT collapse this to "absent"
///     (regression sentinel: doing so caused the 1b configure-twice
///     gap on Pulla — tapping a configured team mid-load deep-linked
///     to the Fan Zone builder instead of the read-only preview).
///   - [Path1SnapshotReady] — a config exists; carries the snapshot.
///     Disabled configs still resolve to Ready (with
///     `autopilotEnabled = false`) so the UI can show the existing
///     design + offer an enable action.
///   - [Path1SnapshotAbsent] — the stream resolved (or errored) and
///     this team has no Path 1 config. Callers deep-link to Path 1
///     setup. Errors fold to Absent on purpose: better the user can
///     re-attempt setup than be stuck on a spinner.
///
/// Reads the parent AsyncValue via `.when(data, loading, error)` (NOT
/// `.maybeWhen` with `orElse → null`) so AsyncLoading stays a distinct
/// signal all the way to the UI.
final path1GameDaySnapshotResolutionProvider =
    Provider.family<Path1SnapshotResolution, String>((ref, teamSlug) {
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  return configsAsync.when(
    data: (configs) {
      final matches = configs.where((c) => c.teamSlug == teamSlug);
      if (matches.isEmpty) return Path1SnapshotAbsent(teamSlug);
      return Path1SnapshotReady(Path1GameDaySnapshot.fromConfig(matches.first));
    },
    loading: () => const Path1SnapshotLoading(),
    error: (_, __) => Path1SnapshotAbsent(teamSlug),
  );
});

// ---------------------------------------------------------------------------
// Notifier: CRUD operations + evaluation loop
// ---------------------------------------------------------------------------

/// Builds the list of enabled configs that should have calendar entries
/// populated for a just-toggled team. The just-written config is spliced in
/// directly so the populate path can't drop it due to Firestore stream lag.
///
/// Semantics (#63 E5 teardown tightened the disabled case):
///   1. Take every enabled config from the stream EXCEPT the just-toggled
///      team's (to avoid double-populating it).
///   2. If [justWrittenConfig] was provided:
///        - enabled → splice it in (overrides stale stream snapshot).
///        - disabled → explicit EXCLUSION; no stream fallback for this
///          slug. This is what protects the disable-path from re-
///          including the team when Firestore hasn't yet propagated the
///          enabled:false write.
///   3. If no [justWrittenConfig] was provided, fall back to the stream's
///      value for this team (covers callers that don't have the fresh
///      config in hand — e.g. background refresh).
///
/// The result is the set of teams to write calendar entries for. Pure
/// function — extracted for unit-testability without standing up the full
/// notifier + Firestore graph.
@visibleForTesting
List<GameDayAutopilotConfig> computeEnabledConfigsForTeam({
  required String teamSlug,
  required List<GameDayAutopilotConfig> streamConfigs,
  required GameDayAutopilotConfig? justWrittenConfig,
}) {
  final exceptToggled =
      streamConfigs.where((c) => c.enabled && c.teamSlug != teamSlug);
  if (justWrittenConfig == null) {
    // No fresh config: trust the stream for this slug too.
    return streamConfigs.where((c) => c.enabled).toList();
  }
  if (justWrittenConfig.enabled) {
    return [...exceptToggled, justWrittenConfig];
  }
  // Disabled justWrittenConfig is an explicit exclusion — do NOT fall
  // back to the (potentially stale) stream value for this slug.
  return exceptToggled.toList();
}

/// Predicate for [_clearFutureGameDayCalendarEntries]: should the entry
/// at [dateKey] be removed during a Game Day calendar regen?
///
/// Returns true iff ALL hold:
///   1. type == CalendarEntryType.autopilot
///   2. sourceTag == CalendarEntrySourceTag.gameDay (#63 sub-change A —
///      the locked filter that prevents neighborhood-sync entries from
///      being collateral-wiped; those carry sourceTag.neighborhoodSync)
///   3. dateKey parses to a valid date
///   4. that date is not before [todayStart] (history preserved)
///
/// Pure function — extracted for unit-testability without scaffolding
/// the calendar provider or notifier graph.
@visibleForTesting
bool shouldClearGameDayEntry({
  required String dateKey,
  required CalendarEntry entry,
  required DateTime todayStart,
}) {
  if (entry.type != CalendarEntryType.autopilot) return false;
  if (entry.sourceTag != CalendarEntrySourceTag.gameDay) return false;
  final date = DateTime.tryParse(dateKey);
  if (date == null) return false;
  if (date.isBefore(todayStart)) return false;
  return true;
}

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

    // Build a snapshot of what we just wrote so the populate path doesn't
    // depend on the Firestore stream propagating before it reads. This
    // closes the stream-lag race that previously caused silent early-
    // return when enabling a second team.
    GameDayAutopilotConfig? freshConfig;

    if (existing.exists) {
      await docRef.update({
        'enabled': enabled,
        'updated_at': Timestamp.fromDate(now),
      });
      // Reconstruct the fresh config from the stream's stale snapshot +
      // the field we just changed. If the stream doesn't yet know about
      // the team (extremely unlikely since the doc exists), fall through
      // with null and the populate path will use its stream fallback.
      final streamConfigs = ref
              .read(gameDayAutopilotConfigsProvider)
              .valueOrNull ??
          const <GameDayAutopilotConfig>[];
      final stale = streamConfigs
          .where((c) => c.teamSlug == teamSlug)
          .firstOrNull;
      if (stale != null) {
        freshConfig = stale.copyWith(enabled: enabled, updatedAt: now);
      }
    } else {
      // Create a new config from kTeamColors. Delegates the subcollection
      // doc + profile array writes to the shared TeamRegistrationService
      // (#63 step 2). The service writes the doc with enabled:false (E5
      // decision: adding ≠ enabling). When the caller asked for
      // enabled:true (the historical create-and-enable path), a follow-up
      // update flips it — preserves the one-shot create+enable contract
      // without forking subcollection-write paths.
      try {
        await ref.read(teamRegistrationServiceProvider).addTeam(
              uid: user.uid,
              teamSlug: teamSlug,
            );
      } on ArgumentError {
        debugPrint(
            '[GameDayAutopilot] toggleAutopilot: unknown team slug "$teamSlug"');
        rethrow;
      }

      // addTeam validated the slug; this lookup is guaranteed to hit.
      final team = kTeamColors[teamSlug]!;

      if (enabled) {
        await docRef.update({
          'enabled': true,
          'updated_at': Timestamp.fromDate(now),
        });
      }

      // In-memory freshConfig for the splice — mirrors the doc state the
      // service just wrote, plus the optional enable flip. Identical
      // field shape to the pre-refactor inline write so
      // _populateCalendarInBackground / computeEnabledConfigsForTeam see
      // the same value.
      freshConfig = GameDayAutopilotConfig(
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
    }

    // If disabling: cancel session + prune local state, then run the
    // clear-and-repopulate path so the just-disabled team's future
    // entries are stripped while remaining enabled teams' entries are
    // preserved.
    //
    // Pass [freshConfig] (which carries enabled:false here) — the
    // splice contract treats a disabled justWrittenConfig as an
    // EXPLICIT exclusion (computeEnabledConfigsForTeam, branch 2).
    // Without this, computeEnabledConfigsForTeam's null-justWritten
    // fallback would re-include the team from the (possibly stale)
    // Firestore stream snapshot, and the disabled team's entries would
    // be re-populated instead of teared down. (#63 E5 teardown.)
    if (!enabled) {
      ref.read(gameDayAutopilotServiceProvider).cancelSession(teamSlug);
      state = Map.from(state)..remove(teamSlug);
      _populateCalendarInBackground(teamSlug, justWrittenConfig: freshConfig);
      return;
    }

    // If enabling, populate the calendar with upcoming games for ALL
    // enabled teams (not just this one — see Item #80). Passing
    // [freshConfig] lets the splice path bypass any Firestore stream lag
    // so the just-toggled team is guaranteed to be in the populate set.
    _populateCalendarInBackground(teamSlug, justWrittenConfig: freshConfig);
  }

  /// Toggle the score celebration flash for a team. Writes
  /// score_celebration_enabled to Firestore. Used by the Live Scoring
  /// switch on the GameDay team card.
  Future<void> setLiveScoring({
    required String teamSlug,
    required bool enabled,
  }) async {
    final user = ref.read(authStateProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (user == null) {
      throw StateError('You must be signed in to change live scoring.');
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('game_day_autopilot')
        .doc(teamSlug)
        .update({
      'score_celebration_enabled': enabled,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Persist the motion-style slider value (0.0 = static, 1.0 = fast).
  /// Storage-only for now — see GameDayAutopilotConfig.motionStyle TODO.
  Future<void> setMotionStyle({
    required String teamSlug,
    required double value,
  }) async {
    final user = ref.read(authStateProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (user == null) {
      throw StateError('You must be signed in to change motion style.');
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('game_day_autopilot')
        .doc(teamSlug)
        .update({
      'motion_style': value.clamp(0.0, 1.0),
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
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

    // Profile strip + subcollection delete funnel through the shared
    // service (#63 step 2). Session cancel + notifier state prune stay
    // here — those are orchestration concerns local to this controller,
    // not the service's job.
    await ref.read(teamRegistrationServiceProvider).removeTeam(
          uid: user.uid,
          teamSlug: teamSlug,
          teamName: teamName,
        );

    try {
      ref.read(gameDayAutopilotServiceProvider).cancelSession(teamSlug);
    } catch (e) {
      debugPrint('[GameDayAutopilot] Failed to cancel session $teamSlug: $e');
    }
    state = Map.from(state)..remove(teamSlug);
  }

  /// Fire-and-forget calendar population after a team toggle. Always runs
  /// (no 7-day gate) — the user just made an explicit change and expects
  /// to see the calendar reflect it. Errors are logged but don't surface
  /// to the caller.
  ///
  /// Iterates ALL enabled teams, not just the just-toggled one, so
  /// enabling a second team doesn't wipe the first team's entries (the
  /// pre-Item-#80 single-team replace semantics caused that regression).
  ///
  /// Pass [justWrittenConfig] when the caller has the freshly-written
  /// config in hand — the splice path uses it directly, bypassing the
  /// Firestore stream-lag race that previously caused silent early-return.
  void _populateCalendarInBackground(
    String teamSlug, {
    GameDayAutopilotConfig? justWrittenConfig,
  }) {
    Future(() async {
      try {
        final streamConfigs = ref
                .read(gameDayAutopilotConfigsProvider)
                .valueOrNull ??
            const <GameDayAutopilotConfig>[];
        final enabledConfigs = computeEnabledConfigsForTeam(
          teamSlug: teamSlug,
          streamConfigs: streamConfigs,
          justWrittenConfig: justWrittenConfig,
        );
        await _doPopulateCalendars(enabledConfigs);
      } catch (e) {
        debugPrint('[GameDayAutopilot] Background populate failed: $e');
      }
    });
  }

  /// Refresh the calendar entries for all enabled autopilot teams.
  /// Called automatically every 24 hours by the refresh timer (the timer
  /// keeps firing daily, but the 7-day gate inside this method ensures the
  /// heavy regen only runs weekly). Can also be called manually from the
  /// Game Day screen — pass `force: true` to bypass the gate.
  Future<void> refreshAllCalendars({bool force = false}) async {
    if (!_shouldRegenerateGameDay(force: force)) return;
    final configs = ref.read(enabledAutopilotConfigsProvider);
    await _doPopulateCalendars(configs);
  }

  /// Shared implementation of "clear all future autopilot rows, then write
  /// fresh entries for every enabled team." Used by both
  /// [_populateCalendarInBackground] (post-toggle, with optional splice)
  /// and [refreshAllCalendars] (post-gate, stream-only). Per-team failures
  /// are isolated — one team's exception does not skip its siblings.
  Future<void> _doPopulateCalendars(
    List<GameDayAutopilotConfig> enabledConfigs,
  ) async {
    // #63 E5 teardown edge: clear runs UNCONDITIONALLY before the empty-
    // set check so disabling the LAST enabled team still strips its
    // future entries. Pre-fix this early-returned before the clear, so
    // the final disable left the last team's games stranded on the
    // calendar.
    await _clearFutureGameDayCalendarEntries();

    if (enabledConfigs.isEmpty) {
      debugPrint('[GameDayAutopilot] No enabled configs to populate '
          '(post-clear, e.g. last team disabled)');
      await _writeGameDayLastGenerated();
      return;
    }

    debugPrint(
        '[GameDayAutopilot] Populating calendar for '
        '${enabledConfigs.length} enabled team(s): '
        '${enabledConfigs.map((c) => c.teamSlug).join(", ")}');

    final service = ref.read(gameDayAutopilotServiceProvider);
    var totalEntries = 0;
    final failedTeams = <String>[];
    for (final config in enabledConfigs) {
      try {
        final count = await service.populateCalendarForTeam(config);
        totalEntries += count;
        debugPrint('[GameDayAutopilot] Wrote $count entries '
            'for ${config.teamSlug}');
      } catch (e) {
        debugPrint('[GameDayAutopilot] Failed to populate '
            '${config.teamSlug}: $e');
        failedTeams.add(config.teamSlug);
      }
    }

    debugPrint('[GameDayAutopilot] Populate complete — '
        'total entries = $totalEntries, '
        'failed teams = ${failedTeams.isEmpty ? "none" : failedTeams.join(",")}');

    await _writeGameDayLastGenerated();
  }

  /// Honors the weekly refresh cadence. Returns true if a regeneration
  /// should proceed (force=true OR no last-generated timestamp OR ≥ 7 days
  /// since the last successful run).
  bool _shouldRegenerateGameDay({required bool force}) {
    if (force) return true;
    final lastGen = ref.read(gameDayLastGeneratedProvider);
    if (lastGen == null) return true;
    final daysSince = DateTime.now().difference(lastGen).inDays;
    if (daysSince < 7) {
      debugPrint('[GameDayAutopilot] refresh gate not met '
          '($daysSince days since last generation), skipping');
      return false;
    }
    return true;
  }

  /// Removes future calendar entries written by Game Day autopilot.
  /// Preserves past entries (history), user entries, holiday entries,
  /// auto-typed baseline entries (warm-white daily, etc.), AND
  /// neighborhood-sync autopilot entries (which share
  /// CalendarEntryType.autopilot but are tagged
  /// CalendarEntrySourceTag.neighborhoodSync).
  ///
  /// Pre-#63 this filtered only by `type != autopilot`, which collateral-
  /// wiped neighborhood-sync rows every time game-day populate ran. The
  /// sourceTag tightening (Sub-Change A) scopes the clear to game-day
  /// entries specifically. sourceTag is already written by
  /// game_day_autopilot_service.dart:_buildCalendarEntry and persisted
  /// by CalendarEntry.toJson — pure read-side scope, no schema change.
  ///
  /// Legacy in-flight game-day entries with sourceTag:null are left
  /// stranded in the future window only (acceptable: they age out, and
  /// past entries are already preserved by the isBefore(todayStart)
  /// guard below).
  Future<void> _clearFutureGameDayCalendarEntries() async {
    try {
      final notifier = ref.read(calendarScheduleProvider.notifier);
      final entries = ref.read(calendarScheduleProvider);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final keysToRemove = <String>[];
      entries.forEach((dateKey, entry) {
        if (shouldClearGameDayEntry(
          dateKey: dateKey,
          entry: entry,
          todayStart: todayStart,
        )) {
          keysToRemove.add(dateKey);
        }
      });

      for (final key in keysToRemove) {
        await notifier.removeEntry(key);
      }

      if (keysToRemove.isNotEmpty) {
        debugPrint('[GameDayAutopilot] Cleared ${keysToRemove.length} '
            'future autopilot calendar entries before regeneration');
      }
    } catch (e) {
      debugPrint('[GameDayAutopilot] Clear future entries failed: $e');
    }
  }

  /// Writes `game_day_last_generated` to the user's profile so the 7-day
  /// refresh gate can be honored on subsequent calls. Direct Firestore
  /// update — same pattern as the per-team config writes elsewhere in
  /// this controller.
  Future<void> _writeGameDayLastGenerated() async {
    try {
      final profile = ref.read(currentUserProfileProvider).valueOrNull;
      final uid = profile?.id;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'game_day_last_generated': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('[GameDayAutopilot] Write gameDayLastGenerated failed: $e');
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

    // Splice the freshly-written field values into the stream snapshot so
    // the populate path uses the latest settings even if the Firestore
    // stream hasn't yet propagated. Null params leave the existing field
    // unchanged (copyWith treats null as "keep current").
    GameDayAutopilotConfig? freshConfig;
    final streamConfigs = ref
            .read(gameDayAutopilotConfigsProvider)
            .valueOrNull ??
        const <GameDayAutopilotConfig>[];
    final stale = streamConfigs
        .where((c) => c.teamSlug == teamSlug)
        .firstOrNull;
    if (stale != null) {
      freshConfig = stale.copyWith(
        skipDayGames: skipDayGames,
        designVariety: designVariety,
        leadTimeMinutesOverride: leadTimeMinutesOverride,
        onTimeOverride: onTimeOverride,
        offTimeOverride: offTimeOverride,
        updatedAt: DateTime.now(),
      );
    }

    // Re-populate calendar with new settings for ALL enabled teams (see
    // Item #80). The user just changed this team's settings and expects to
    // see the calendar reflect them immediately, but we must not wipe
    // other teams' entries in the process.
    _populateCalendarInBackground(teamSlug, justWrittenConfig: freshConfig);
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
