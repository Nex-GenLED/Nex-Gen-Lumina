// lib/features/autopilot/game_day_autopilot_service.dart
//
// Core service for individual-user Game Day Autopilot.
//
// Responsibilities:
//   1. PRE-GAME: 30 min before game start, activate team-themed design.
//   2. LIVE GAME: Keep lights on team design; score celebrations fire via
//      existing ScoreMonitorService pipeline.
//   3. POST-GAME: Detect game end via ESPN API (primary) or estimated
//      duration fallback, then start 30-min countdown before resuming
//      normal schedule or turning off.
//
// Design selection priority:
//   1. User-saved design for this team
//   2. Auto-select from UserVarietyProfile (static → Solid, motion → Chase,
//      dynamic → Fade, a slow crossfade of the team's two colours)
//   3. Fallback: Solid in team primary color

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/sun_utils.dart';
import '../schedule/calendar_entry.dart';
import '../sports_alerts/models/game_event.dart';
import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/services/espn_api_service.dart';
import '../sports_alerts/services/game_schedule_service.dart';
import '../wled/wled_effects_catalog.dart' show WledEffectsCatalog;
import 'game_day_autopilot_config.dart';
import 'game_day_priority_resolver.dart';
import 'team_priority.dart';
import 'team_design_catalog.dart';

// ---------------------------------------------------------------------------
// Autopilot session state
// ---------------------------------------------------------------------------

/// Tracks the lifecycle of a single game day autopilot session.
enum AutopilotSessionPhase {
  /// Waiting for pre-game window (30 min before start).
  idle,

  /// Lights activated with team design; game hasn't started yet.
  preGame,

  /// Game is live; lights remain on team design.
  liveGame,

  /// Game ended; 30-min countdown running before turning off.
  postGame,

  /// Session complete — lights returned to normal schedule or off.
  completed,
}

/// Snapshot of the current autopilot session for a single team.
class AutopilotSession {
  final String teamSlug;
  final AutopilotSessionPhase phase;
  final DateTime? gameStart;
  final DateTime? gameEndDetected;
  final DateTime? countdownEnd;
  final String? activeGameId;
  final bool usedFallbackTimer;

  /// This team's game is being TRACKED but the team does not hold the lights,
  /// because a higher-priority team's game is running (rule 2 of
  /// [GameDayPriorityResolver]).
  ///
  /// A deferred session is deliberately a real session and not an absence.
  /// It runs the same phase machine — pre-game → live → final — so that when
  /// the winner's game ends, hand-off can ask "is this team still playing?"
  /// and get a true answer. If a deferred team had no session at all, the only
  /// way to pick it up later would be `hasGameSoon`, which is false once its
  /// game has already started, so a team deferred at 12:40 for a 1 pm start
  /// could never take over at 3 pm. It would simply never light.
  ///
  /// What deferral suppresses is the two things that reach the user: no design
  /// is applied while this is true, and no score celebrations fire
  /// (`computeLiveCelebrationTeams`). Flipping it to false IS the hand-off.
  final bool deferred;

  /// When this session was created — the first-come-first-served tie-break
  /// the resolver applies at equal priority (rule 3).
  ///
  /// Distinct from [gameStart], which is when the GAME starts and is null
  /// whenever ESPN could not be read. Using gameStart as a stand-in made an
  /// existing session look NEWER than a candidate being resolved right now,
  /// which inverted every tie: the incumbent lost its own house to a
  /// latecomer of equal rank.
  final DateTime? activatedAt;

  const AutopilotSession({
    required this.teamSlug,
    this.phase = AutopilotSessionPhase.idle,
    this.gameStart,
    this.gameEndDetected,
    this.countdownEnd,
    this.activeGameId,
    this.usedFallbackTimer = false,
    this.deferred = false,
    this.activatedAt,
  });

  AutopilotSession copyWith({
    AutopilotSessionPhase? phase,
    DateTime? gameStart,
    DateTime? gameEndDetected,
    DateTime? countdownEnd,
    String? activeGameId,
    bool? usedFallbackTimer,
    bool? deferred,
    DateTime? activatedAt,
  }) {
    return AutopilotSession(
      teamSlug: teamSlug,
      phase: phase ?? this.phase,
      gameStart: gameStart ?? this.gameStart,
      gameEndDetected: gameEndDetected ?? this.gameEndDetected,
      countdownEnd: countdownEnd ?? this.countdownEnd,
      activeGameId: activeGameId ?? this.activeGameId,
      usedFallbackTimer: usedFallbackTimer ?? this.usedFallbackTimer,
      deferred: deferred ?? this.deferred,
      activatedAt: activatedAt ?? this.activatedAt,
    );
  }

  bool get isActive =>
      phase == AutopilotSessionPhase.preGame ||
      phase == AutopilotSessionPhase.liveGame ||
      phase == AutopilotSessionPhase.postGame;

  /// This session is the one currently driving the house.
  ///
  /// Exactly one session should satisfy this at a time. Everything that
  /// reaches the user — the applied design, the celebrations — keys off this,
  /// not off [isActive], which now also covers teams being tracked while they
  /// wait their turn.
  bool get ownsLights => isActive && !deferred;

  /// This team's own game is still going, so it is a valid hand-off target.
  ///
  /// `postGame` counts: that team's game has ended but its own 30-minute
  /// wind-down has not, and the wind-down is a deliberate part of the show.
  bool get isHandoffCandidate =>
      phase == AutopilotSessionPhase.preGame ||
      phase == AutopilotSessionPhase.liveGame ||
      phase == AutopilotSessionPhase.postGame;

  @override
  String toString() =>
      'AutopilotSession($teamSlug, phase=$phase'
      '${deferred ? ', DEFERRED' : ''})';
}

// ---------------------------------------------------------------------------
// Design selection result
// ---------------------------------------------------------------------------

/// Result of the design selection algorithm.
class DesignSelection {
  final AutopilotDesignMode mode;
  final String designName;
  final int effectId;
  final int speed;
  final int intensity;
  final int brightness;
  final List<List<int>> colors;
  final Map<String, dynamic> wledPayload;

  const DesignSelection({
    required this.mode,
    required this.designName,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.brightness,
    required this.colors,
    required this.wledPayload,
  });

  @override
  String toString() => 'DesignSelection($designName, mode=$mode, fx=$effectId)';
}

// ---------------------------------------------------------------------------
// GameDayAutopilotService
// ---------------------------------------------------------------------------

class GameDayAutopilotService {
  final EspnApiService _espnApi;
  final GameScheduleService _scheduleService;

  /// Active sessions keyed by team slug.
  final Map<String, AutopilotSession> _sessions = {};

  /// Last-seen enabled config per team slug, refreshed on every
  /// [evaluateConfigs] pass.
  ///
  /// Hand-off has to re-apply the incoming team's design, which means it needs
  /// that team's config — but hand-off is also triggered from [cancelSession],
  /// which the UI calls with no config in hand. Caching what the evaluate loop
  /// already receives every minute is cheaper and less fragile than another
  /// callback into the provider graph, and it can never be staler than one
  /// tick.
  final Map<String, GameDayAutopilotConfig> _knownConfigs = {};

  /// Polling timer for post-game detection.
  Timer? _postGamePollTimer;

  /// Last activation instant handed out, so no two sessions can share one.
  ///
  /// Rule 3 breaks an equal-priority tie by "who activated first". Two teams
  /// whose windows open on the SAME evaluate pass both stamp `DateTime.now()`,
  /// and at microsecond resolution those stamps can be identical — at which
  /// point neither is "after" the other, both resolve to activate, and two
  /// teams own the house at once. Clock resolution must not decide whether an
  /// invariant holds, so stamps are strictly increasing.
  DateTime? _lastActivationStamp;

  /// The stamp [_nextActivationStamp] would hand out, without consuming it.
  DateTime _peekActivationStamp() {
    final now = DateTime.now();
    final last = _lastActivationStamp;
    return (last == null || now.isAfter(last))
        ? now
        : last.add(const Duration(microseconds: 1));
  }

  DateTime _nextActivationStamp() {
    final now = DateTime.now();
    final last = _lastActivationStamp;
    final stamp = (last == null || now.isAfter(last))
        ? now
        : last.add(const Duration(microseconds: 1));
    _lastActivationStamp = stamp;
    return stamp;
  }

  /// Callback invoked when the service needs to apply a WLED payload.
  /// Set by the provider layer to bridge into the WLED notifier.
  /// PART A (audit/GAMEDAY_WEDGE_U1_U6.md §2). Returns a Future, and
  /// [_applyDesign] awaits it.
  ///
  /// This was `void Function(...)`, which discarded the Future returned by
  /// `repo.applyJson`. The handler's own `try/catch` could therefore only ever
  /// catch a SYNCHRONOUS throw — a timeout or an exception raised inside the
  /// apply became an unhandled async error and was lost. On the scheduled path
  /// that meant a controller that failed to light produced no error anywhere,
  /// unattended, with nobody present to notice.
  Future<void> Function(Map<String, dynamic> payload)? onApplyPayload;

  /// Callback invoked when the service needs to resume normal schedule
  /// or turn lights off after the post-game countdown.
  void Function()? onResumeNormalSchedule;

  /// Callback invoked when the session phase changes (for UI updates).
  void Function(AutopilotSession session)? onSessionChanged;

  /// Callback invoked when the service needs to write calendar entries.
  /// Set by the provider layer. Returns true on success.
  Future<bool> Function(List<CalendarEntry> entries)? onWriteCalendarEntries;

  /// Callback to read user's current location. Returns (lat, lon) or
  /// null if not available. Used for daylight filter.
  ({double lat, double lon})? Function()? onGetUserLocation;

  /// Callback to read the user's preferred effect styles for design
  /// auto-selection. Returns empty list if no preferences set.
  List<String> Function()? onGetPreferredStyles;

  /// Callback to read the user's ordered team SLUG list — the hierarchy that
  /// decides which team owns the house when two games overlap.
  ///
  /// Must return slugs (`game_day_team_priority`), not display names; see the
  /// header note on [GameDayPriorityResolver]. When unwired or empty, the
  /// resolver falls back to first-come-first-served, which is the pre-2026-09
  /// behaviour — so an unwired callback degrades to the old conduct rather
  /// than to an error.
  List<String> Function()? onGetTeamPriority;

  /// Callback to read the current calendar entry for a given date key,
  /// if one exists. Used to check for user overrides that should win
  /// over autopilot-generated entries.
  CalendarEntry? Function(String dateKey)? onGetCalendarEntry;

  /// Callback to resolve the LOCAL user's participating channels for a
  /// given config (using the config's explicit picker choice + the
  /// user's RooflineConfiguration + the device's bus list). The
  /// provider layer fills this in by calling
  /// [resolveParticipatingChannels] and persisting the result via
  /// [saveLocalParticipatingChannels].
  ///
  /// When null (callback unwired) or when the callback itself returns
  /// null, the service falls back to applying without per-channel
  /// filtering — the legacy single-seg shape. This keeps the service
  /// resilient if the provider isn't yet wired, and matches the
  /// dormant-default semantics from Bundles 1-2.
  List<int>? Function(GameDayAutopilotConfig config)?
      onResolveParticipatingChannels;

  GameDayAutopilotService({
    required EspnApiService espnApi,
    required GameScheduleService scheduleService,
  })  : _espnApi = espnApi,
        _scheduleService = scheduleService;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Get the current session for a team (null if no active session).
  AutopilotSession? getSession(String teamSlug) => _sessions[teamSlug];

  /// All active sessions.
  Map<String, AutopilotSession> get activeSessions =>
      Map.unmodifiable(_sessions);

  /// Check all enabled autopilot configs and activate pre-game if within
  /// the 30-minute window. Called periodically by the provider layer.
  ///
  /// Every team that is in its window gets a SESSION; at most one of them
  /// holds the LIGHTS. Which one is decided by [GameDayPriorityResolver]
  /// against the user's ordered slug list — see [_activateWithPriority].
  Future<void> evaluateConfigs(List<GameDayAutopilotConfig> configs) async {
    final now = DateTime.now();

    for (final config in configs) {
      if (!config.enabled) continue;
      _knownConfigs[config.teamSlug] = config;
    }

    // Walk the hierarchy, not Firestore document-id order. When two teams'
    // windows open on the same tick, the #1 team must be the one that
    // resolves first — otherwise the lower team activates against an empty
    // field, puts its design on the wire, and is preempted a moment later,
    // flashing the wrong colours at the house on the way.
    final ordered = orderConfigsByPriority(
      configs,
      onGetTeamPriority?.call() ?? const <String>[],
      (c) => c.teamSlug,
    );

    for (final config in ordered) {
      if (!config.enabled) continue;

      final session = _sessions[config.teamSlug];

      // Skip completed or already-active sessions.
      if (session != null && session.phase == AutopilotSessionPhase.completed) {
        continue;
      }

      if (session != null && session.isActive) {
        // Already active — check for phase transitions. A deferred session
        // goes through this too: it is being tracked precisely so that its
        // phase is known when a hand-off asks.
        await _updateActiveSession(config, session, now);
        continue;
      }

      // Check if there's a game starting within 30 minutes.
      final hasGame = await _scheduleService.hasGameSoon(
        config.espnTeamId,
        config.sport,
        minutes: 30,
      );

      if (hasGame) {
        final nextGame = await _scheduleService.fetchNextGameDate(
          config.espnTeamId,
          config.sport,
        );
        debugPrint('[GameDayAutopilot] Game soon for ${config.teamName}, '
            'resolving priority before activation');
        await _activateWithPriority(config, nextGame);
      }
    }
  }

  /// The arbiter. Decide whether [config] may take the house, must wait, or
  /// should displace whoever currently holds it — then act on that decision.
  ///
  /// Mirrors `GameDayAutopilotBackgroundWorker._resolvePriorityForActivation`,
  /// which has always done this on the (compiled-off) background path; this is
  /// the foreground half that was missing.
  Future<void> _activateWithPriority(
    GameDayAutopilotConfig config,
    DateTime? gameStart,
  ) async {
    final teamPriority = onGetTeamPriority?.call() ?? const <String>[];
    final actives = _candidatesExcept(config.teamSlug, ownsLightsOnly: true);

    // Peek at the next stamp WITHOUT consuming it: this candidate may end up
    // deferred, and a deferred team still gets a session (and a real stamp)
    // below. What matters here is only that it reads as later than every
    // session already created.
    final candidate = GameDayEventCandidate(
      id: config.teamSlug,
      source: GameDayEventSource.personalAutopilot,
      teamSlug: config.teamSlug,
      espnTeamId: config.espnTeamId,
      activatedAt: _peekActivationStamp(),
    );

    final decision = GameDayPriorityResolver.resolve(
      candidate: candidate,
      activeEvents: actives,
      teamPriority: teamPriority,
    );

    switch (decision.decision) {
      case GameDayPriorityDecision.activate:
        // Taking the house means nothing else may still be holding it. With
        // monotonic stamps the resolver will not return `activate` while a
        // rightful owner exists, but the invariant "exactly one session owns
        // the lights" is load-bearing for celebrations and hand-off, so it is
        // enforced here rather than left to hold by argument.
        _demoteOtherOwners(config.teamSlug);
        await _activatePreGame(config, gameStart);

      case GameDayPriorityDecision.defer:
        // Tracked, not lit. No design applied, no celebrations — but the
        // phase machine runs, so this team is a hand-off candidate the moment
        // the incumbent finishes.
        debugPrint('[GameDayAutopilot] ${config.teamName} DEFERRED — '
            '${decision.reason}');
        await _activatePreGame(config, gameStart, deferred: true);

      case GameDayPriorityDecision.preempt:
        final loser = decision.affectedBy;
        debugPrint('[GameDayAutopilot] ${config.teamName} PREEMPTS '
            '${loser?.teamSlug} — ${decision.reason}');
        if (loser != null) {
          _demoteOtherOwners(config.teamSlug);
          final incumbent = _sessions[loser.teamSlug];
          if (incumbent != null) {
            // The incumbent keeps its session and its phase tracking; it just
            // stops owning the lights. It becomes a hand-off candidate, so a
            // preempted team whose game outlasts the winner's gets the house
            // back rather than being lost.
            _sessions[loser.teamSlug] = incumbent.copyWith(deferred: true);
            _notifySessionChanged(loser.teamSlug);
          }
        }
        await _activatePreGame(config, gameStart);
    }
  }

  /// Step every session except [keepSlug] out of the owning role.
  ///
  /// They keep their sessions and their phase tracking — they remain hand-off
  /// candidates — they simply stop driving the house and stop celebrating.
  void _demoteOtherOwners(String keepSlug) {
    for (final entry in _sessions.entries.toList()) {
      if (entry.key == keepSlug) continue;
      if (!entry.value.ownsLights) continue;
      _sessions[entry.key] = entry.value.copyWith(deferred: true);
      _notifySessionChanged(entry.key);
    }
  }

  /// Build resolver candidates from the live session map.
  ///
  /// [ownsLightsOnly] selects what "competing" means: for an activation
  /// decision only the session actually holding the house competes, because a
  /// deferred session has already lost and must not make a third team defer
  /// to it. For hand-off, every still-playing session competes.
  List<GameDayEventCandidate> _candidatesExcept(
    String excludeSlug, {
    required bool ownsLightsOnly,
  }) {
    final out = <GameDayEventCandidate>[];
    for (final entry in _sessions.entries) {
      if (entry.key == excludeSlug) continue;
      final s = entry.value;
      if (ownsLightsOnly ? !s.ownsLights : !s.isHandoffCandidate) continue;
      out.add(GameDayEventCandidate(
        id: s.teamSlug,
        source: GameDayEventSource.personalAutopilot,
        teamSlug: s.teamSlug,
        espnTeamId: _knownConfigs[s.teamSlug]?.espnTeamId ?? '',
        // Epoch-0 fallback, never `now`: an existing session with no recorded
        // activation time must still read as OLDER than a candidate being
        // resolved this instant, or first-come-first-served inverts.
        activatedAt: s.activatedAt ??
            s.gameStart ??
            DateTime.fromMillisecondsSinceEpoch(0),
        gameId: s.activeGameId,
      ));
    }
    return out;
  }

  /// Force-activate autopilot for a team (e.g., manual trigger from UI).
  Future<void> forceActivate(
    GameDayAutopilotConfig config,
    DesignSelection design,
  ) async {
    _sessions[config.teamSlug] = AutopilotSession(
      teamSlug: config.teamSlug,
      phase: AutopilotSessionPhase.preGame,
      gameStart: DateTime.now(),
      activatedAt: _nextActivationStamp(),
    );
    await _applyDesign(design);
    _notifySessionChanged(config.teamSlug);
  }

  /// Populate the calendar with entries for all upcoming games for a team
  /// **within a rolling 7-day window** from today. Fetches the full season
  /// schedule from ESPN, filters down to the next week, applies the
  /// daylight filter, generates a design per game based on variety mode,
  /// and writes CalendarEntry records via onWriteCalendarEntries.
  ///
  /// The 7-day cap exists so first-time enable doesn't dump 140+ MLB games
  /// into the calendar at once. Re-runs weekly via the refresh-cadence gate
  /// in [GameDayAutopilotController]. Safe to call repeatedly — writes are
  /// idempotent (same dateKey overwrites previous autopilot entry).
  ///
  /// RETURNS `(entriesWritten, failed)` — and the second field is the point.
  /// This used to return a bare `int` where 0 meant BOTH "ESPN was
  /// unreachable" and "your team simply isn't playing this week". The caller
  /// could not tell those apart, so a refresh in which every team's fetch
  /// failed was indistinguishable from a quiet week, and the Game Day screen
  /// reported success for both. `failed` is true only for an actual fault —
  /// a fetch that threw, a missing write callback, or a write that came back
  /// false. An empty week is `(0, false)`: nothing to do is not a failure.
  Future<({int entriesWritten, bool failed})> populateCalendarForTeam(
    GameDayAutopilotConfig config, {
    int lookaheadDays = 7,
  }) async {
    if (onWriteCalendarEntries == null) {
      debugPrint('[GameDayAutopilot] populateCalendar: no write callback');
      return (entriesWritten: 0, failed: true);
    }

    final now = DateTime.now();
    final season = now.year;

    List<GameEvent> games;
    try {
      games = await _scheduleService.fetchSeasonSchedule(
        espnTeamId: config.espnTeamId,
        sport: config.sport,
        season: season,
        homeGamesOnly: false,
      );
    } catch (e) {
      debugPrint('[GameDayAutopilot] populateCalendar fetch failed: $e');
      // A FAULT: we asked ESPN and it did not answer. The team may well have
      // games this week; we simply do not know.
      return (entriesWritten: 0, failed: true);
    }

    if (games.isEmpty) {
      debugPrint('[GameDayAutopilot] populateCalendar: no games found for '
          '${config.teamName} season $season');
      // NOT a fault: the fetch succeeded and the season is genuinely empty
      // (off-season, or a team between schedules). Reporting this as a
      // failure would tell a user in February that the app is broken.
      return (entriesWritten: 0, failed: false);
    }

    // Build design catalog once for rotation
    final catalog = TeamDesignCatalog.build(
      teamName: config.teamName,
      primary: config.primaryColor,
      secondary: config.secondaryColor,
      brightness: config.brightness,
    );

    final location = onGetUserLocation?.call();
    final entries = <CalendarEntry>[];
    final windowEnd = now.add(Duration(days: lookaheadDays));
    // Optional end bound from a Lumina recurring-sports rule ("...through Oct
    // 2026"). Normalized to end-of-day so a game ON the bound date still
    // counts — the bound is inclusive of its own day. Null = open-ended.
    final DateTime? untilEnd = config.untilDate == null
        ? null
        : DateTime(config.untilDate!.year, config.untilDate!.month,
            config.untilDate!.day, 23, 59, 59);
    int gameIndex = 0;

    for (final game in games) {
      // Rolling 7-day window from today. Include today's game if the
      // activation window (game start minus lead time) hasn't passed yet.
      // Anything outside the next [lookaheadDays] is skipped — it'll be
      // picked up by the next weekly refresh.
      final activationTime = game.scheduledDate.subtract(
        Duration(minutes: config.effectiveLeadTimeMinutes),
      );
      if (activationTime.isBefore(now)) continue;
      if (game.scheduledDate.isAfter(windowEnd)) continue;
      // Honor the rule's end bound: once a game falls past untilDate, stop
      // materializing it. Combined with the rolling window, this means the
      // autopilot naturally writes zero entries for this team after the
      // bound passes — no separate teardown needed.
      if (untilEnd != null && game.scheduledDate.isAfter(untilEnd)) continue;

      // Apply daylight filter if enabled
      if (config.skipDayGames &&
          _isDaylightOnlyGame(game, config, location)) {
        debugPrint('[GameDayAutopilot] skipping daylight game: '
            '${game.homeTeam} vs ${game.awayTeam} on ${game.scheduledDate}');
        continue;
      }

      // Select design based on variety mode
      final design = _selectDesignForGame(config, catalog, game, gameIndex);

      // Compute on/off times
      final onTime = _computeOnTime(config, game);
      final offTime = _computeOffTime(config, game);

      entries.add(_buildCalendarEntry(
        config: config,
        game: game,
        design: design,
        onTime: onTime,
        offTime: offTime,
      ));

      gameIndex++;
    }

    if (entries.isEmpty) {
      debugPrint('[GameDayAutopilot] populateCalendar: no entries after '
          'filter for ${config.teamName}');
      // NOT a fault: a quiet week, or every game filtered out by the daylight
      // rule / until-date bound. The user asked for exactly this behaviour.
      return (entriesWritten: 0, failed: false);
    }

    final ok = await onWriteCalendarEntries!(entries);
    if (ok) {
      debugPrint('[GameDayAutopilot] populateCalendar: wrote '
          '${entries.length} entries for ${config.teamName}');
      return (entriesWritten: entries.length, failed: false);
    }
    debugPrint('[GameDayAutopilot] populateCalendar: write failed for '
        '${config.teamName}');
    return (entriesWritten: 0, failed: true);
  }

  /// Test seam: force a session's post-game countdown to have elapsed.
  ///
  /// The countdown is a wall-clock 30 minutes and the phase machine is driven
  /// by `DateTime.now()`, so without this a hand-off test would have to wait
  /// half an hour. Reaches only the in-memory session map — no I/O, no clock
  /// injection into production paths.
  @visibleForTesting
  void debugSetCountdownEnd(String teamSlug, DateTime countdownEnd) {
    final s = _sessions[teamSlug];
    if (s == null) return;
    _sessions[teamSlug] = s.copyWith(countdownEnd: countdownEnd);
  }

  /// Cancel an active session for a team.
  ///
  /// Async since 2026-09-22: cancelling the team that holds the house now
  /// hands off to the next team still playing instead of powering the house
  /// off unconditionally. Cancelling a DEFERRED session touches the lights
  /// not at all — it never had them.
  Future<void> cancelSession(String teamSlug) async {
    final session = _sessions.remove(teamSlug);
    if (session == null) return;
    debugPrint('[GameDayAutopilot] Session cancelled for $teamSlug');
    if (!session.ownsLights) return;
    await _handOffOrResume(teamSlug);
  }

  /// Select the appropriate design for a team based on config and user profile.
  ///
  /// [preferredStyles] comes from AutopilotProfile.preferredEffectStyles.
  DesignSelection selectDesign(
    GameDayAutopilotConfig config, {
    List<String> preferredStyles = const [],
  }) {
    // LED colours: every branch below ends in a controller payload.
    // config.primaryColor is the BRAND colour, for UI only.
    final primaryRgb = config.primaryLedRgb.toRgb();
    final secondaryRgb = config.secondaryLedRgb.toRgb();
    final colors = [primaryRgb, secondaryRgb];

    // Priority 1: User has a saved design.
    // NOTE: saved-design payloads bypass _buildWledPayload — they ship
    // verbatim from Firestore and may have any seg-array shape. They
    // are therefore NOT participation-filtered in Bundle 3. Tracked as
    // a known gap for the picker bundle: when the user picks a saved
    // design AND has non-participating channels (e.g. patio), this
    // branch may still light the excluded channels. Fix path: post-
    // process the saved payload through the same buildParticipating-
    // SegArray pipeline once we have a robust seg-template extractor
    // for arbitrary saved designs (multi-seg, gradients, etc.).
    if (config.designMode == AutopilotDesignMode.saved &&
        config.savedDesignPayload != null) {
      debugPrint('[GameDayAutopilot] Design branch: SAVED for ${config.teamSlug}');
      return DesignSelection(
        mode: AutopilotDesignMode.saved,
        designName: config.savedDesignName ?? 'Custom Design',
        effectId: config.effectId,
        speed: config.speed,
        intensity: config.intensity,
        brightness: config.brightness,
        colors: colors,
        wledPayload: config.savedDesignPayload!,
      );
    }

    // Priority 2: Auto-select from user style preferences.
    if (preferredStyles.isNotEmpty) {
      final styleCategory = _categorizeStyles(preferredStyles);
      debugPrint('[GameDayAutopilot] Design branch: AUTO-SELECT '
          '(style=$styleCategory) for ${config.teamSlug}');

      // EFFECT IDS ARE NOT LABELS. `dynamic` shipped as fx 63 captioned
      // "Twinkle"; on WLED 0.15.1 that is Pride 2015 — a hue-rotating rainbow
      // that reads neither `col[]` nor the palette, so the house showed every
      // colour but the team's. Fade (12) is the whole strip crossfading
      // primary ↔ secondary from `col[]`, verified against the firmware's own
      // effect list and by live observation (see team_design_catalog.dart).
      final (effectId, effectName, speed) = switch (styleCategory) {
        _StyleCategory.static_ => (0, 'Solid', 128),      // Solid
        _StyleCategory.motion  => (28, 'Chase', 180),      // Chase
        _StyleCategory.dynamic => (
            kBaseDesignFadeEffectId,
            'Fade',
            kBaseDesignFadeSpeed,
          ),
      };

      return DesignSelection(
        mode: AutopilotDesignMode.autoSelected,
        designName: '$effectName in ${config.teamName} Colors',
        effectId: effectId,
        speed: speed,
        intensity: 180,
        brightness: config.brightness,
        colors: colors,
        wledPayload: _buildWledPayload(
          effectId: effectId,
          colors: colors,
          speed: speed,
          intensity: 180,
          brightness: config.brightness,
          participating: onResolveParticipatingChannels?.call(config),
        ),
      );
    }

    // Priority 3: Fallback — Solid in team primary color.
    debugPrint('[GameDayAutopilot] Design branch: FALLBACK for ${config.teamSlug}');
    return DesignSelection(
      mode: AutopilotDesignMode.fallback,
      designName: '${config.teamName} Colors (Solid)',
      effectId: 0,
      speed: 128,
      intensity: 128,
      brightness: config.brightness,
      colors: colors,
      wledPayload: _buildWledPayload(
        effectId: 0,
        colors: colors,
        speed: 128,
        intensity: 128,
        brightness: config.brightness,
        participating: onResolveParticipatingChannels?.call(config),
      ),
    );
  }

  // `detectConflicts` lived here: it paired teams whose next games fell within
  // 4 hours and was exposed as `GameDayAutopilotNotifier.checkConflicts()`.
  // It had no caller anywhere in lib/ or test/, its 4-hour window bore no
  // relationship to any real arbitration, and it answered a question
  // [GameDayPriorityResolver] now answers properly and per-event. Deleted
  // 2026-09-22 rather than left sitting next to the live arbiter, where the
  // next reader would have had to work out which of the two was load-bearing.

  void dispose() {
    _postGamePollTimer?.cancel();
    _sessions.clear();
    _knownConfigs.clear();
  }

  // ── Internal: Pre-game activation ──────────────────────────────────────

  Future<void> _activatePreGame(
    GameDayAutopilotConfig config,
    DateTime? gameStart, {
    bool deferred = false,
  }) async {
    // Daylight filter — skip activation if game is daylight-only
    if (config.skipDayGames && gameStart != null) {
      final location = onGetUserLocation?.call();
      if (location != null) {
        final estimatedEnd = gameStart.add(config.estimatedDuration);
        final sunset = SunUtils.sunsetLocal(
          location.lat,
          location.lon,
          gameStart,
        );
        if (sunset != null &&
            estimatedEnd.isBefore(
                sunset.subtract(const Duration(minutes: 30)))) {
          debugPrint('[GameDayAutopilot] Skipping ${config.teamName} — '
              'daylight game (ends $estimatedEnd before sunset $sunset)');
          return;
        }
      }
    }

    // Check for user override on this date — if present, user's
    // manual settings win over autopilot.
    if (gameStart != null && onGetCalendarEntry != null) {
      final dateKey = '${gameStart.year}-'
          '${gameStart.month.toString().padLeft(2, '0')}-'
          '${gameStart.day.toString().padLeft(2, '0')}';
      final entry = onGetCalendarEntry!(dateKey);
      if (entry != null && entry.type == CalendarEntryType.user) {
        debugPrint('[GameDayAutopilot] User override present for $dateKey, '
            'autopilot deferring to user settings');
        return;
      }
    }

    _sessions[config.teamSlug] = AutopilotSession(
      teamSlug: config.teamSlug,
      phase: AutopilotSessionPhase.preGame,
      gameStart: gameStart,
      deferred: deferred,
      activatedAt: _nextActivationStamp(),
    );
    _notifySessionChanged(config.teamSlug);

    if (deferred) {
      // Tracked only. Applying here is exactly the bug — it would put the
      // lower-priority team's design on a house the #1 team already owns.
      debugPrint('[GameDayAutopilot] Pre-game TRACKED (deferred, no apply) '
          'for ${config.teamName}');
      return;
    }

    // Select design — now passes user's style preferences via callback
    final preferredStyles = onGetPreferredStyles?.call() ?? const [];
    final design = selectDesign(config, preferredStyles: preferredStyles);
    await _applyDesign(design);
    _notifySessionChanged(config.teamSlug);

    debugPrint('[GameDayAutopilot] Pre-game activated for '
        '${config.teamName} with design: ${design.designName}');
  }

  // ── Internal: hand-off ─────────────────────────────────────────────────

  /// The winner just finished. Give the house to the next team that is still
  /// playing, or — only if there is none — resume the normal schedule.
  ///
  /// This replaces an unconditional `onResumeNormalSchedule()`, which calls
  /// `togglePower(false)`. With two followed teams that meant the house went
  /// DARK the moment the first game ended, part-way through the second
  /// (audit/gameday-game-selection-2026-09-21 §4a). Turning the lights off
  /// while a followed game is still on is never the right answer.
  ///
  /// [relinquishingSlug] is the team giving up the lights; it is excluded
  /// from the candidate set regardless of its own phase.
  Future<void> _handOffOrResume(String relinquishingSlug) async {
    final teamPriority = onGetTeamPriority?.call() ?? const <String>[];
    final remaining =
        _candidatesExcept(relinquishingSlug, ownsLightsOnly: false);

    final winner = GameDayPriorityResolver.handoffWinner(
      remaining: remaining,
      teamPriority: teamPriority,
    );

    if (winner == null) {
      debugPrint('[GameDayAutopilot] $relinquishingSlug finished, no other '
          'team still playing — resuming normal schedule');
      onResumeNormalSchedule?.call();
      return;
    }

    final session = _sessions[winner.teamSlug];
    final config = _knownConfigs[winner.teamSlug];
    if (session == null || config == null) {
      // Should be unreachable: candidates are built from _sessions, and
      // _knownConfigs is refreshed from the same enabled set every tick. If
      // it ever happens, resuming is safer than leaving the previous team's
      // design up for a team that is no longer configured.
      debugPrint('[GameDayAutopilot] hand-off target ${winner.teamSlug} has '
          'no ${session == null ? "session" : "config"} — resuming instead');
      onResumeNormalSchedule?.call();
      return;
    }

    // Taking over IS un-deferring. From here the team owns the lights and,
    // because `ownsLights` gates it, its celebrations start firing.
    _sessions[winner.teamSlug] = session.copyWith(deferred: false);

    final preferredStyles = onGetPreferredStyles?.call() ?? const [];
    final design = selectDesign(config, preferredStyles: preferredStyles);
    await _applyDesign(design);
    _notifySessionChanged(winner.teamSlug);

    debugPrint('[GameDayAutopilot] HAND-OFF: $relinquishingSlug finished → '
        '${config.teamName} takes the house with ${design.designName}');
  }

  // ── Internal: Active session updates ───────────────────────────────────

  Future<void> _updateActiveSession(
    GameDayAutopilotConfig config,
    AutopilotSession session,
    DateTime now,
  ) async {
    switch (session.phase) {
      case AutopilotSessionPhase.preGame:
        // Check if game has started (ESPN shows in-progress).
        final gameState = await _espnApi.fetchTeamGame(
          config.sport,
          config.espnTeamId,
        );
        if (gameState != null &&
            (gameState.status == GameStatus.inProgress ||
                gameState.status == GameStatus.halftime)) {
          _sessions[config.teamSlug] = session.copyWith(
            phase: AutopilotSessionPhase.liveGame,
            activeGameId: gameState.gameId,
          );
          debugPrint('[GameDayAutopilot] Game started for ${config.teamName}');
          _notifySessionChanged(config.teamSlug);
        }

      case AutopilotSessionPhase.liveGame:
        // Primary: Check if game is final via ESPN.
        final gameState = await _espnApi.fetchTeamGame(
          config.sport,
          config.espnTeamId,
        );

        if (gameState != null && gameState.status == GameStatus.final_) {
          // Game ended — start 30-min countdown.
          final countdownEnd = now.add(const Duration(minutes: 30));
          _sessions[config.teamSlug] = session.copyWith(
            phase: AutopilotSessionPhase.postGame,
            gameEndDetected: now,
            countdownEnd: countdownEnd,
            usedFallbackTimer: false,
          );
          debugPrint('[GameDayAutopilot] Game FINAL for ${config.teamName}, '
              'starting 30-min countdown');
          _notifySessionChanged(config.teamSlug);
          return;
        }

        // Fallback: Check if estimated duration + 60 min buffer exceeded.
        if (session.gameStart != null) {
          final estimatedEnd = session.gameStart!
              .add(config.estimatedDuration)
              .add(const Duration(minutes: 60));
          if (now.isAfter(estimatedEnd)) {
            final countdownEnd = now.add(const Duration(minutes: 30));
            _sessions[config.teamSlug] = session.copyWith(
              phase: AutopilotSessionPhase.postGame,
              gameEndDetected: now,
              countdownEnd: countdownEnd,
              usedFallbackTimer: true,
            );
            debugPrint('[GameDayAutopilot] FALLBACK timer triggered for '
                '${config.teamName} — no live final detected within '
                '${config.estimatedDuration.inMinutes}min + 60min buffer');
            _notifySessionChanged(config.teamSlug);
          }
        }

      case AutopilotSessionPhase.postGame:
        // Check if 30-min countdown has elapsed.
        if (session.countdownEnd != null && now.isAfter(session.countdownEnd!)) {
          final wasOwner = session.ownsLights;
          _sessions[config.teamSlug] = session.copyWith(
            phase: AutopilotSessionPhase.completed,
          );
          _notifySessionChanged(config.teamSlug);
          debugPrint('[GameDayAutopilot] Post-game countdown complete for '
              '${config.teamName}');
          if (wasOwner) {
            // Hand off to the next team still playing; resume only if there
            // is none. A deferred session that completes never held the
            // lights, so it must not trigger either — it just stops being
            // tracked.
            await _handOffOrResume(config.teamSlug);
          }
        }

      case AutopilotSessionPhase.idle:
      case AutopilotSessionPhase.completed:
        break;
    }
  }

  // ── Internal: Calendar population helpers ───────────────────────────────

  /// Returns true if the entire game is in daylight at the user's
  /// location. A game is daylight-only when its end time is more
  /// than 30 minutes before local sunset on the game's date.
  bool _isDaylightOnlyGame(
    GameEvent game,
    GameDayAutopilotConfig config,
    ({double lat, double lon})? location,
  ) {
    if (location == null) return false;
    // Item #63 fix 2026-05-08: ESPN-sourced DateTime values are UTC-flagged.
    // Direct .hour/.minute/.year/.month/.day access returns UTC clock values,
    // which when stuffed into onTime/offTime/dateKey strings cause the
    // schedule screen to render game times offset by the user's UTC gap
    // (5 hours for CDT customers like Blue Line Bar, etc).
    // .toLocal() converts to the device's local timezone before extraction.
    // Here SunUtils.sunsetLocal extracts year/month/day from its date arg
    // and expects them in local time (per its docstring).
    final localStart = game.scheduledDate.toLocal();
    final gameEnd = localStart.add(config.estimatedDuration);
    final sunset = SunUtils.sunsetLocal(
      location.lat,
      location.lon,
      localStart,
    );
    if (sunset == null) return false;
    return gameEnd.isBefore(sunset.subtract(const Duration(minutes: 30)));
  }

  /// Select a design for a specific game based on config's variety mode.
  TeamDesign _selectDesignForGame(
    GameDayAutopilotConfig config,
    List<TeamDesign> catalog,
    GameEvent game,
    int gameIndex,
  ) {
    switch (config.designVariety) {
      case AutopilotVarietyMode.fixed:
        if (config.designMode == AutopilotDesignMode.saved &&
            config.savedDesignPayload != null) {
          return TeamDesign(
            name: config.savedDesignName ?? 'Custom',
            effectId: config.effectId,
            speed: config.speed,
            intensity: config.intensity,
            colorGroupSize: 1,
            wledPayload: config.savedDesignPayload!,
          );
        }
        return catalog.first;

      case AutopilotVarietyMode.rotating:
        return TeamDesignCatalog.selectForRotation(catalog, gameIndex);
    }
  }

  /// Compute the on-time for a calendar entry in "HH:mm" 24-hour format.
  String _computeOnTime(GameDayAutopilotConfig config, GameEvent game) {
    if (config.onTimeOverride != null) return config.onTimeOverride!;
    final leadMinutes = config.effectiveLeadTimeMinutes;
    // Item #63 fix 2026-05-08: ESPN-sourced DateTime values are UTC-flagged.
    // Direct .hour/.minute/.year/.month/.day access returns UTC clock values,
    // which when stuffed into onTime/offTime/dateKey strings cause the
    // schedule screen to render game times offset by the user's UTC gap
    // (5 hours for CDT customers like Blue Line Bar, etc).
    // .toLocal() converts to the device's local timezone before extraction.
    final onTime = game.scheduledDate
        .toLocal()
        .subtract(Duration(minutes: leadMinutes));
    return _formatHHmm(onTime);
  }

  /// Compute the off-time for a calendar entry.
  String _computeOffTime(GameDayAutopilotConfig config, GameEvent game) {
    if (config.offTimeOverride != null) return config.offTimeOverride!;
    // Item #63 fix 2026-05-08: ESPN-sourced DateTime values are UTC-flagged.
    // Direct .hour/.minute/.year/.month/.day access returns UTC clock values,
    // which when stuffed into onTime/offTime/dateKey strings cause the
    // schedule screen to render game times offset by the user's UTC gap
    // (5 hours for CDT customers like Blue Line Bar, etc).
    // .toLocal() converts to the device's local timezone before extraction.
    final offTime = game.scheduledDate
        .toLocal()
        .add(config.estimatedDuration)
        .add(const Duration(minutes: 60));
    return _formatHHmm(offTime);
  }

  static String _formatHHmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  /// Build a CalendarEntry for a game.
  CalendarEntry _buildCalendarEntry({
    required GameDayAutopilotConfig config,
    required GameEvent game,
    required TeamDesign design,
    required String onTime,
    required String offTime,
  }) {
    // Item #63 fix 2026-05-08: ESPN-sourced DateTime values are UTC-flagged.
    // Direct .hour/.minute/.year/.month/.day access returns UTC clock values,
    // which when stuffed into onTime/offTime/dateKey strings cause the
    // schedule screen to render game times offset by the user's UTC gap
    // (5 hours for CDT customers like Blue Line Bar, etc).
    // .toLocal() converts to the device's local timezone before extraction.
    final localStart = game.scheduledDate.toLocal();
    final dateKey = '${localStart.year}-'
        '${localStart.month.toString().padLeft(2, '0')}-'
        '${localStart.day.toString().padLeft(2, '0')}';

    final opponent = game.isHome ? game.awayTeam : game.homeTeam;
    final vsOrAt = game.isHome ? 'vs' : '@';
    final note =
        '${config.teamName} $vsOrAt $opponent — Game Day autopilot';

    return CalendarEntry(
      dateKey: dateKey,
      patternName: design.name,
      color: config.primaryColor,
      onTime: onTime,
      offTime: offTime,
      brightness: (config.brightness * 100 / 255).round().clamp(0, 100),
      type: CalendarEntryType.autopilot,
      autopilot: true,
      note: note,
      sourceTag: CalendarEntrySourceTag.gameDay,
    );
  }

  // ── Internal: WLED payload ─────────────────────────────────────────────

  /// Test-only entry point for `_applyDesign`. Used by Bundle 3b.3c
  /// regression tests to assert that an empty seg array prevents the
  /// `onApplyPayload` invocation.
  @visibleForTesting
  Future<void> applyDesignForTest(DesignSelection design) =>
      _applyDesign(design);

  Future<void> _applyDesign(DesignSelection design) async {
    // Skip-apply when participation resolved to explicit empty. The
    // applyJson chokepoint ([expandForParticipation], rule 2) passes
    // empty participation THROUGH — it never emits seg:[] on its own —
    // so this caller-side gate is the active mechanism that prevents an
    // unfiltered broadcast to seg 0 when the user opts out of all
    // channels. _buildWledPayload produces `seg: []` in exactly that
    // case (participating != null && participating.isEmpty).
    final seg = design.wledPayload['seg'];
    if (seg is List && seg.isEmpty) {
      debugPrint(
        '[GameDayAutopilot] skip-apply: no participating channels '
        '(design=${design.designName})',
      );
      return;
    }
    // AWAITED — see [onApplyPayload]. A failure here is surfaced through
    // [onApplyFailure] rather than vanishing into a dropped Future.
    try {
      await onApplyPayload?.call(design.wledPayload);
    } catch (e, st) {
      onApplyFailure?.call(design, e, st);
      rethrow;
    }
  }

  /// Reports a failed device apply to the host. Set by the provider wiring.
  ///
  /// Exists because the previous shape had nowhere for an async failure to go:
  /// the Future was dropped, so neither the service nor the provider learned
  /// that the house never lit.
  void Function(DesignSelection design, Object error, StackTrace stack)?
      onApplyFailure;

  Map<String, dynamic> _buildWledPayload({
    required int effectId,
    required List<List<int>> colors,
    required int speed,
    required int intensity,
    required int brightness,
    required List<int>? participating,
  }) {
    final colorSlots =
        colors.map((c) => <int>[...c, 0]).toList(); // Add W=0 for RGBW

    // Bundle 3b.3c: the applyJson chokepoint
    // ([expandForParticipation] in wled_payload_utils.dart) reads the
    // persisted participation list and rule-7-expands a single-seg-no-
    // id-with-fx payload per participating channel. We emit that shape
    // here and let the chokepoint do the per-channel duplication.
    //
    // EXCEPT for the explicit-empty case (participating != null &&
    // participating.isEmpty): rule 2 of the chokepoint passes empty
    // participation THROUGH (it never emits seg:[]), so we must emit
    // `seg: []` here. _applyDesign then skip-applies — see the comment
    // on _applyDesign for why that gate is active, not dead.
    final segs = (participating != null && participating.isEmpty)
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            {
              'fx': effectId,
              'sx': speed,
              'ix': intensity,
              // The palette that makes THIS effect play `col[]` — 0 for a
              // colour-reading effect, "Colors Only" for a palette-reading
              // one. A hard-coded 0 here is what let fx 63 look like a team
              // design in the code while rendering a rainbow on the house.
              'pal': WledEffectsCatalog.setColorsPaletteFor(effectId),
              'col': colorSlots,
            },
          ];

    return {
      'on': true,
      'bri': brightness.clamp(0, 255),
      'seg': segs,
    };
  }

  void _notifySessionChanged(String teamSlug) {
    final session = _sessions[teamSlug];
    if (session != null) {
      onSessionChanged?.call(session);
    }
  }

  // ── Internal: Style categorization ─────────────────────────────────────

  /// Categorize a user's preferred effect styles into one of three buckets.
  _StyleCategory _categorizeStyles(List<String> styles) {
    int staticScore = 0;
    int motionScore = 0;
    int dynamicScore = 0;

    for (final style in styles) {
      switch (style.toLowerCase()) {
        case 'static':
        case 'solid':
          staticScore += 2;
        case 'animated':
        case 'chase':
        case 'wipe':
        case 'sweep':
          motionScore += 2;
        case 'twinkle':
        case 'pulse':
        case 'rainbow':
        case 'reactive':
          dynamicScore += 2;
        default:
          motionScore += 1; // Unknown styles lean toward motion.
      }
    }

    if (dynamicScore > motionScore && dynamicScore > staticScore) {
      return _StyleCategory.dynamic;
    }
    if (motionScore > staticScore) {
      return _StyleCategory.motion;
    }
    return _StyleCategory.static_;
  }
}

enum _StyleCategory { static_, motion, dynamic }
