import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sports_alerts/models/game_state.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/espn_api_service.dart';
import '../../wled/wled_providers.dart' show wledRepositoryProvider;
import '../models/paused_session_state.dart';
import '../models/session_duration_type.dart';
import '../models/sync_event.dart';
import '../neighborhood_models.dart';
import 'package:nexgen_command/services/user_service.dart';
import '../neighborhood_providers.dart';
import 'autopilot_sync_trigger.dart' show syncEventServiceProvider;
import 'group_autopilot_service.dart';
import 'sync_event_service.dart';
import 'sync_notification_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// HANDOFF STATE
// ═════════════════════════════════════════════════════════════════════════════

/// The current handoff state for the local user.
enum HandoffPhase {
  /// No handoff in progress — single group or no overlap.
  idle,

  /// A shortForm session has taken over; longForm is paused.
  shortFormActive,

  /// The shortForm session is ending; crossfade transition playing.
  transitioning,

  /// Victory celebration playing before handoff back to longForm.
  celebratingVictory,

  /// Resuming the longForm session after shortForm ended.
  resumingLongForm,
}

/// Snapshot of the user's current handoff stack state.
class HandoffState {
  final HandoffPhase phase;
  final PausedSessionState? pausedLongForm;
  final String? activeShortFormGroupId;
  final String? activeShortFormSessionId;
  final DateTime? estimatedResumeTime;

  const HandoffState({
    this.phase = HandoffPhase.idle,
    this.pausedLongForm,
    this.activeShortFormGroupId,
    this.activeShortFormSessionId,
    this.estimatedResumeTime,
  });

  bool get hasActiveHandoff => phase != HandoffPhase.idle;
  bool get isLongFormPaused => pausedLongForm != null;

  HandoffState copyWith({
    HandoffPhase? phase,
    PausedSessionState? pausedLongForm,
    String? activeShortFormGroupId,
    String? activeShortFormSessionId,
    DateTime? estimatedResumeTime,
    bool clearPausedLongForm = false,
    bool clearEstimatedResumeTime = false,
  }) {
    return HandoffState(
      phase: phase ?? this.phase,
      pausedLongForm:
          clearPausedLongForm ? null : (pausedLongForm ?? this.pausedLongForm),
      activeShortFormGroupId:
          activeShortFormGroupId ?? this.activeShortFormGroupId,
      activeShortFormSessionId:
          activeShortFormSessionId ?? this.activeShortFormSessionId,
      estimatedResumeTime: clearEstimatedResumeTime
          ? null
          : (estimatedResumeTime ?? this.estimatedResumeTime),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SYNC HANDOFF MANAGER
// ═════════════════════════════════════════════════════════════════════════════

/// Manages group transitions for users belonging to multiple sync groups.
///
/// Implements a stack-based state machine per user:
///   - Bottom of stack: active longForm group session (if any)
///   - Top of stack: active shortForm group session (if any)
///   - Top of stack always controls the user's lights
///   - When top is removed, bottom resumes automatically
///
/// Transition effects use a 3-second crossfade (not configurable).
class SyncHandoffManager {
  final Ref _ref;
  final SyncEventService _eventService;
  final FirebaseFirestore _firestore;
  final EspnApiService _espnApi;

  Timer? _transitionTimer;
  Timer? _victoryCelebrationTimer;
  Timer? _overtimeCheckTimer;

  /// Current handoff state for the local user.
  HandoffState _state = const HandoffState();
  HandoffState get state => _state;

  /// Listeners that want to know when state changes.
  final _stateController = StreamController<HandoffState>.broadcast();
  Stream<HandoffState> get stateStream => _stateController.stream;

  /// Victory celebration duration before handing back to longForm.
  static const _victoryCelebrationDuration = Duration(seconds: 15);

  /// Respectful hold on final state after a loss.
  static const _lossHoldDuration = Duration(seconds: 5);

  /// SharedPreferences key for persisting handoff state across app restarts.
  static const _kHandoffStateKey = 'sync_handoff_state';

  SyncHandoffManager(this._ref, this._eventService)
      : _firestore = FirebaseFirestore.instance,
        _espnApi = EspnApiService();

  @visibleForTesting
  SyncHandoffManager.withDeps(
    this._ref,
    this._eventService,
    this._firestore,
    this._espnApi,
  );

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── INITIALIZATION ──────────────────────────────────────────────────

  /// Restore handoff state from disk (for app restart / background resume).
  Future<void> restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_kHandoffStateKey);
      if (json == null) return;

      final data = jsonDecode(json) as Map<String, dynamic>;
      final pausedJson = data['pausedLongForm'] as Map<String, dynamic>?;

      _state = HandoffState(
        phase: HandoffPhase.values.firstWhere(
          (p) => p.name == data['phase'],
          orElse: () => HandoffPhase.idle,
        ),
        pausedLongForm:
            pausedJson != null ? PausedSessionState.fromJson(pausedJson) : null,
        activeShortFormGroupId: data['activeShortFormGroupId'] as String?,
        activeShortFormSessionId: data['activeShortFormSessionId'] as String?,
      );

      _emitState();
      debugPrint('[SyncHandoffManager] Restored state: ${_state.phase}');

      // If we restored mid-handoff, check if the shortForm session is still active
      if (_state.phase == HandoffPhase.shortFormActive) {
        await _checkShortFormStillActive();
      }
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to restore state: $e');
    }
  }

  // ── SHORTFORM SESSION STARTS ────────────────────────────────────────

  /// Called when a shortForm session starts for the current user.
  ///
  /// Checks for active longForm sessions and pushes shortForm to top of stack.
  /// Returns true if a handoff was initiated (longForm was paused).
  Future<bool> onShortFormSessionStart({
    required String shortFormGroupId,
    required String shortFormSessionId,
    required SyncEvent shortFormEvent,
    DateTime? estimatedEndTime,
  }) async {
    final uid = _uid;
    if (uid == null) return false;

    // Check if user has any active longForm sessions across all groups
    final activeLongForm = await _findActiveLongFormSession(uid);
    if (activeLongForm == null) {
      debugPrint(
        '[SyncHandoffManager] No active longForm session — no handoff needed',
      );
      return false;
    }

    debugPrint(
      '[SyncHandoffManager] Pausing longForm group ${activeLongForm.groupId} '
      'for shortForm group $shortFormGroupId',
    );

    // Capture the longForm session state before pausing
    final pausedState = await _captureLongFormState(
      activeLongForm,
      pausedByGroupId: shortFormGroupId,
      pausedBySessionId: shortFormSessionId,
    );

    // Update Firestore: mark this user as paused in the longForm group
    await _pauseUserInGroup(uid, activeLongForm.groupId);

    // Update local state
    _state = HandoffState(
      phase: HandoffPhase.shortFormActive,
      pausedLongForm: pausedState,
      activeShortFormGroupId: shortFormGroupId,
      activeShortFormSessionId: shortFormSessionId,
      estimatedResumeTime: estimatedEndTime,
    );
    _emitState();
    await _persistState();

    // Store paused state in Firestore for background service access
    await _storePausedStateInFirestore(uid, pausedState);

    // Send notification
    final notifService = _ref.read(syncNotificationServiceProvider);
    final longFormGroupName =
        await _getGroupName(activeLongForm.groupId);
    await notifService.notifyParticipants(
      groupId: shortFormGroupId,
      participantUids: [uid],
      title: '${shortFormEvent.name} is live! 🏈',
      body:
          'Your $longFormGroupName lights will resume after the game.',
      type: SyncNotificationType.sessionStarted,
    );

    return true;
  }

  // ── SHORTFORM SESSION ENDS ──────────────────────────────────────────

  /// Called when a shortForm session ends for the current user.
  ///
  /// Pops shortForm from stack and resumes longForm if it exists.
  /// Handles victory celebration, loss hold, and crossfade transition.
  Future<void> onShortFormSessionEnd({
    required String shortFormGroupId,
    required String shortFormSessionId,
    bool? teamWon,
    SyncEvent? shortFormEvent,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    if (_state.phase != HandoffPhase.shortFormActive) {
      debugPrint(
        '[SyncHandoffManager] Not in shortFormActive phase — ignoring end',
      );
      return;
    }

    final pausedLongForm = _state.pausedLongForm;
    if (pausedLongForm == null) {
      // No longForm to resume — just clean up
      _state = const HandoffState();
      _emitState();
      await _persistState();
      await _clearPausedStateFromFirestore(uid);
      return;
    }

    // Handle victory celebration or loss hold
    if (teamWon == true) {
      await _playVictoryCelebration(shortFormEvent, pausedLongForm, uid);
    } else if (teamWon == false) {
      await _playLossHold(pausedLongForm, uid);
    } else {
      // No game result (manual end or non-sports event)
      await _executeHandoffToLongForm(pausedLongForm, uid);
    }
  }

  /// Play a 15-second victory celebration before handing back to longForm.
  Future<void> _playVictoryCelebration(
    SyncEvent? shortFormEvent,
    PausedSessionState pausedLongForm,
    String uid,
  ) async {
    _state = _state.copyWith(phase: HandoffPhase.celebratingVictory);
    _emitState();

    // Send victory notification
    final notifService = _ref.read(syncNotificationServiceProvider);
    final eventName = shortFormEvent?.name ?? 'Your team';
    final longFormGroupName = await _getGroupName(pausedLongForm.groupId);
    await notifService.notifyParticipants(
      groupId: pausedLongForm.groupId,
      participantUids: [uid],
      title: '$eventName wins! 🏆',
      body:
          'Celebrating before handing back to $longFormGroupName...',
      type: SyncNotificationType.sessionEnded,
    );

    // If there's a celebration pattern, broadcast it
    if (shortFormEvent != null) {
      await _broadcastPatternLocally(shortFormEvent.celebrationPattern);
    }

    // Wait for victory celebration, then crossfade to longForm
    _victoryCelebrationTimer?.cancel();
    _victoryCelebrationTimer = Timer(_victoryCelebrationDuration, () async {
      await _executeHandoffToLongForm(pausedLongForm, uid);
    });
  }

  /// Hold on final state for 5 seconds after a loss, then crossfade.
  Future<void> _playLossHold(
    PausedSessionState pausedLongForm,
    String uid,
  ) async {
    _state = _state.copyWith(phase: HandoffPhase.transitioning);
    _emitState();

    _transitionTimer?.cancel();
    _transitionTimer = Timer(_lossHoldDuration, () async {
      await _executeHandoffToLongForm(pausedLongForm, uid);
    });
  }

  /// Execute the actual handoff: crossfade from shortForm → longForm.
  Future<void> _executeHandoffToLongForm(
    PausedSessionState pausedLongForm,
    String uid,
  ) async {
    _state = _state.copyWith(phase: HandoffPhase.resumingLongForm);
    _emitState();

    // Determine which pattern to resume
    final resumePattern = await _resolveResumePattern(pausedLongForm);

    // Execute 3-second crossfade transition
    await _executeCrossfadeTransition(resumePattern);

    // Re-activate user in the longForm group
    await _resumeUserInGroup(uid, pausedLongForm.groupId);

    // Send resume notification
    final notifService = _ref.read(syncNotificationServiceProvider);
    final longFormGroupName = await _getGroupName(pausedLongForm.groupId);
    await notifService.notifyParticipants(
      groupId: pausedLongForm.groupId,
      participantUids: [uid],
      title: 'Welcome back!',
      body: 'Your $longFormGroupName lights are back! 🎄',
      type: SyncNotificationType.sessionStarted,
    );

    // Clean up state
    _state = const HandoffState();
    _emitState();
    await _persistState();
    await _clearPausedStateFromFirestore(uid);

    debugPrint(
      '[SyncHandoffManager] Handoff complete — resumed longForm group '
      '${pausedLongForm.groupId}',
    );
  }

  // ── CROSSFADE TRANSITION ────────────────────────────────────────────

  /// Execute a 3-second crossfade transition to the target pattern.
  ///
  /// Uses WLED's native transition time (`tt` field in JSON API) to achieve
  /// a smooth fade rather than client-side animation.
  Future<void> _executeCrossfadeTransition(PatternRef targetPattern) async {
    try {
      // WLED transition time is in 100ms units: 3 seconds = 30
      final payload = {
        'on': true,
        'bri': targetPattern.brightness,
        'transition': 30, // 3 seconds in WLED's 100ms units
        'seg': [
          {
            'fx': targetPattern.effectId,
            'sx': targetPattern.speed,
            'ix': targetPattern.intensity,
            'col': [
              _colorToRgbList(targetPattern.colors.isNotEmpty
                  ? targetPattern.colors[0]
                  : 0xFFFFFF),
              if (targetPattern.colors.length > 1)
                _colorToRgbList(targetPattern.colors[1]),
              if (targetPattern.colors.length > 2)
                _colorToRgbList(targetPattern.colors[2]),
            ],
          }
        ],
      };

      final repo = _ref.read(wledRepositoryProvider);
      if (repo != null) {
        await repo.applyJson(payload);
      }

      debugPrint('[SyncHandoffManager] Crossfade transition initiated (3s)');
    } catch (e) {
      debugPrint('[SyncHandoffManager] Crossfade failed: $e');
      // Fallback: apply pattern directly without transition
      await _broadcastPatternLocally(targetPattern);
    }
  }

  List<int> _colorToRgbList(int color) {
    return [
      (color >> 16) & 0xFF,
      (color >> 8) & 0xFF,
      color & 0xFF,
    ];
  }

  // ── OVERTIME HANDLING ───────────────────────────────────────────────

  /// Start monitoring for overtime / game extension.
  ///
  /// If the game extends past the scheduled end time, keep shortForm active
  /// until the game status is "final".
  void startOvertimeWatch({
    required String sportLeague,
    required String gameId,
    required String shortFormGroupId,
    required String shortFormSessionId,
  }) {
    _overtimeCheckTimer?.cancel();
    _overtimeCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        try {
          final sport = _parseSportType(sportLeague);
          if (sport == null) return;

          final gameState = await _espnApi.fetchGame(sport, gameId);
          if (gameState == null) return;

          if (gameState.status == GameStatus.final_) {
            debugPrint('[SyncHandoffManager] Game is final — ending overtime watch');
            _overtimeCheckTimer?.cancel();
            // The session end will be triggered by the celebration service
            return;
          }

          // Game still in progress — update estimated resume time
          if (_state.phase == HandoffPhase.shortFormActive) {
            // Notify user about overtime
            final uid = _uid;
            if (uid != null && _state.pausedLongForm != null) {
              final longFormName =
                  await _getGroupName(_state.pausedLongForm!.groupId);
              final notifService = _ref.read(syncNotificationServiceProvider);
              await notifService.notifyParticipants(
                groupId: shortFormGroupId,
                participantUids: [uid],
                title: 'Overtime!',
                body:
                    "Game's in overtime — $longFormName lights standing by 🎄",
                type: SyncNotificationType.sessionEnding,
              );
            }
          }
        } catch (e) {
          debugPrint('[SyncHandoffManager] Overtime check error: $e');
        }
      },
    );
  }

  // ── MANUAL OVERRIDE ─────────────────────────────────────────────────

  /// Called when user manually changes their lights during a shortForm session.
  ///
  /// User override always wins. Both group states are cleared.
  Future<void> onUserManualOverride() async {
    final uid = _uid;
    if (uid == null) return;
    if (_state.phase == HandoffPhase.idle) return;

    debugPrint(
      '[SyncHandoffManager] User manual override — clearing all handoff state',
    );

    // Clear the shortForm participation
    if (_state.activeShortFormGroupId != null) {
      await _pauseUserInGroup(uid, _state.activeShortFormGroupId!);
    }

    // Clear the paused longForm state
    if (_state.pausedLongForm != null) {
      await _resumeUserInGroup(uid, _state.pausedLongForm!.groupId);
      // But immediately pause again since they're in manual control
      await _pauseUserInGroup(uid, _state.pausedLongForm!.groupId);
    }

    // Reset all state
    _cancelAllTimers();
    _state = const HandoffState();
    _emitState();
    await _persistState();
    await _clearPausedStateFromFirestore(uid);
  }

  // ── CLEANUP ON GROUP LEAVE ──────────────────────────────────────────

  /// Clear all handoff state for a user who is leaving a group. Prevents
  /// orphaned handoff state (Finding 5.1 from sync audit) that would
  /// cause silent resume failures when the user joins a new group later.
  Future<void> clearUserHandoffState(String uid) async {
    _cancelAllTimers();
    _state = const HandoffState();
    _emitState();
    await _persistState();
    await _clearPausedStateFromFirestore(uid);
    debugPrint('[SyncHandoffManager] Cleared handoff state for user $uid');
  }

  // ── USER JOINS SHORTFORM GROUP MID-LONGFORM ─────────────────────────

  /// Called when a user joins a shortForm group while they have an active
  /// longForm session. If the shortForm group already has an active session,
  /// execute immediate handoff.
  Future<void> onUserJoinsShortFormGroup({
    required String shortFormGroupId,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    // Check if the shortForm group has an active session right now
    final activeSession =
        await _eventService.getActiveSession(shortFormGroupId);
    if (activeSession == null ||
        activeSession.status != SyncEventSessionStatus.active) {
      // No active session — standard scheduling applies
      return;
    }

    // Get the sync event for this session
    final event = await _eventService.getSyncEvent(
      shortFormGroupId,
      activeSession.syncEventId,
    );
    if (event == null) return;

    // Verify it's actually shortForm
    final durationType = classifySessionDuration(category: event.category);
    if (durationType != SessionDurationType.shortForm) return;

    // Execute immediate handoff
    await onShortFormSessionStart(
      shortFormGroupId: shortFormGroupId,
      shortFormSessionId: activeSession.id,
      shortFormEvent: event,
    );
  }

  // ── PRIVATE HELPERS ─────────────────────────────────────────────────

  /// Find any active longForm session for the given user across all their groups.
  Future<_ActiveLongFormInfo?> _findActiveLongFormSession(String uid) async {
    final groups = _ref.read(userNeighborhoodsProvider).valueOrNull ?? [];

    for (final group in groups) {
      if (!group.isActive) continue;

      // Check if there's an active session in this group
      final session = await _eventService.getActiveSession(group.id);
      if (session == null) continue;
      if (session.status != SyncEventSessionStatus.active) continue;
      if (!session.activeParticipantUids.contains(uid)) continue;

      // Get the event to check its duration type
      final event =
          await _eventService.getSyncEvent(group.id, session.syncEventId);
      if (event == null) continue;

      final durationType = classifySessionDuration(category: event.category);
      if (durationType == SessionDurationType.longForm) {
        return _ActiveLongFormInfo(
          groupId: group.id,
          sessionId: session.id,
          event: event,
          session: session,
        );
      }
    }
    return null;
  }

  /// Capture the current state of a longForm session for later resumption.
  Future<PausedSessionState> _captureLongFormState(
    _ActiveLongFormInfo longForm, {
    required String pausedByGroupId,
    required String pausedBySessionId,
  }) async {
    return PausedSessionState(
      groupId: longForm.groupId,
      sessionId: longForm.sessionId,
      syncEventId: longForm.event.id,
      currentPattern: longForm.event.basePattern,
      sessionStartTime: longForm.session.startedAt,
      pausedAt: DateTime.now(),
      scheduledEffects: const [], // Could be populated from schedule data
      hostIsActive: _isHostOnline(longForm),
      pausedByGroupId: pausedByGroupId,
      pausedBySessionId: pausedBySessionId,
    );
  }

  bool _isHostOnline(_ActiveLongFormInfo longForm) {
    final members = _ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final host = members.where((m) => m.oderId == longForm.session.hostUid);
    return host.isNotEmpty && host.first.isOnline;
  }

  /// Resolve which pattern to resume when returning to longForm.
  Future<PatternRef> _resolveResumePattern(
    PausedSessionState pausedState,
  ) async {
    // Check if the longForm host is still active
    try {
      final session =
          await _eventService.getActiveSession(pausedState.groupId);
      if (session != null &&
          session.status == SyncEventSessionStatus.active) {
        // Session still running — get the current pattern from the event
        final event = await _eventService.getSyncEvent(
          pausedState.groupId,
          pausedState.syncEventId,
        );
        if (event != null) {
          return event.basePattern;
        }
      }
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to fetch live longForm state: $e');
    }

    // Fallback: use the pattern we captured at pause time
    return pausedState.currentPattern;
  }

  /// Pause the user's participation in a group (Firestore update).
  Future<void> _pauseUserInGroup(String uid, String groupId) async {
    try {
      await _firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .update({
        'participationStatus': MemberParticipationStatus.paused.name,
        'handoffPaused': true,
      });
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to pause user in group: $e');
    }
  }

  /// Resume the user's participation in a group (Firestore update).
  Future<void> _resumeUserInGroup(String uid, String groupId) async {
    try {
      await _firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .update({
        'participationStatus': MemberParticipationStatus.active.name,
        'handoffPaused': false,
      });
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to resume user in group: $e');
    }
  }

  /// Apply a pattern to the local WLED device.
  Future<void> _broadcastPatternLocally(PatternRef pattern) async {
    try {
      final payload = {
        'on': true,
        'bri': pattern.brightness,
        'seg': [
          {
            'fx': pattern.effectId,
            'sx': pattern.speed,
            'ix': pattern.intensity,
            'col': [
              _colorToRgbList(pattern.colors.isNotEmpty
                  ? pattern.colors[0]
                  : 0xFFFFFF),
              if (pattern.colors.length > 1)
                _colorToRgbList(pattern.colors[1]),
              if (pattern.colors.length > 2)
                _colorToRgbList(pattern.colors[2]),
            ],
          }
        ],
      };

      final repo = _ref.read(wledRepositoryProvider);
      if (repo != null) {
        await repo.applyJson(payload);
      }
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to apply pattern locally: $e');
    }
  }

  /// Get a group's display name.
  Future<String> _getGroupName(String groupId) async {
    try {
      final doc =
          await _firestore.collection('neighborhoods').doc(groupId).get();
      return (doc.data()?['name'] as String?) ?? 'your group';
    } catch (_) {
      return 'your group';
    }
  }

  /// Store paused state in Firestore so the background service can access it.
  Future<void> _storePausedStateInFirestore(
    String uid,
    PausedSessionState pausedState,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('handoff')
          .doc('current')
          .set(UserService.sanitizeForFirestore(pausedState.toJson()));
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to store paused state: $e');
    }
  }

  /// Clear paused state from Firestore.
  Future<void> _clearPausedStateFromFirestore(String uid) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('handoff')
          .doc('current')
          .delete();
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to clear paused state: $e');
    }
  }

  /// Check if the shortForm session we were tracking is still active.
  /// Called after restoring state from disk.
  Future<void> _checkShortFormStillActive() async {
    if (_state.activeShortFormGroupId == null) return;

    try {
      final session = await _eventService
          .getActiveSession(_state.activeShortFormGroupId!);

      if (session == null ||
          session.status == SyncEventSessionStatus.completed ||
          session.status == SyncEventSessionStatus.cancelled) {
        debugPrint(
          '[SyncHandoffManager] ShortForm session no longer active — resuming longForm',
        );
        final uid = _uid;
        if (uid != null && _state.pausedLongForm != null) {
          await _executeHandoffToLongForm(_state.pausedLongForm!, uid);
        }
      }
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to check shortForm status: $e');
    }
  }

  // ── PERSISTENCE ─────────────────────────────────────────────────────

  void _emitState() {
    _stateController.add(_state);
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_state.phase == HandoffPhase.idle) {
        await prefs.remove(_kHandoffStateKey);
        return;
      }

      final data = {
        'phase': _state.phase.name,
        'pausedLongForm': _state.pausedLongForm?.toJson(),
        'activeShortFormGroupId': _state.activeShortFormGroupId,
        'activeShortFormSessionId': _state.activeShortFormSessionId,
      };
      await prefs.setString(_kHandoffStateKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[SyncHandoffManager] Failed to persist state: $e');
    }
  }

  void _cancelAllTimers() {
    _transitionTimer?.cancel();
    _victoryCelebrationTimer?.cancel();
    _overtimeCheckTimer?.cancel();
  }

  SportType? _parseSportType(String league) {
    switch (league.toUpperCase()) {
      case 'NFL':
        return SportType.nfl;
      case 'NBA':
        return SportType.nba;
      case 'MLB':
        return SportType.mlb;
      case 'NHL':
        return SportType.nhl;
      case 'MLS':
        return SportType.mls;
      default:
        return null;
    }
  }

  // ── GROUP AUTOPILOT AWARENESS ──────────────────────────────────────

  /// Fetch the current set of opted-in member IDs for a group's autopilot.
  ///
  /// Always call this before broadcasting any game day command — a member
  /// may have opted out after the session was configured. Returns an empty
  /// list if all members opted out (caller should cancel the broadcast
  /// silently — do not error).
  Future<List<String>> resolveGroupAutopilotMembers(String groupId) async {
    final service = GroupAutopilotService(firestore: _firestore);
    final members = await service.refreshActiveMemberIds(groupId);
    if (members.isEmpty) {
      debugPrint(
        '[SyncHandoffManager] No opted-in members for group $groupId — '
        'cancelling broadcast silently',
      );
    }
    return members;
  }

  /// Check if a specific user is currently opted in to a group's autopilot.
  Future<bool> isMemberOptedIn(String groupId, String userId) async {
    final service = GroupAutopilotService(firestore: _firestore);
    return service.getMemberOptIn(groupId, userId);
  }

  void dispose() {
    _cancelAllTimers();
    _stateController.close();
    _espnApi.dispose();
  }
}

/// Internal info about an active longForm session.
class _ActiveLongFormInfo {
  final String groupId;
  final String sessionId;
  final SyncEvent event;
  final SyncEventSession session;

  _ActiveLongFormInfo({
    required this.groupId,
    required this.sessionId,
    required this.event,
    required this.session,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═════════════════════════════════════════════════════════════════════════════

final syncHandoffManagerProvider = Provider<SyncHandoffManager>((ref) {
  final service = ref.watch(syncEventServiceProvider);
  final manager = SyncHandoffManager(ref, service);
  ref.onDispose(() => manager.dispose());

  // Restore state on initialization
  manager.restoreState();

  return manager;
});
