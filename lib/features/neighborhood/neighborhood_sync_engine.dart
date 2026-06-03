import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../models/roofline_segment.dart';
import '../../services/autopilot_scheduler.dart';
import '../design/roofline_config_providers.dart';
import '../schedule/schedule_providers.dart';
import '../wled/wled_providers.dart';
import '../wled/wled_repository.dart';
import '../wled/zone_providers.dart';
import 'neighborhood_models.dart';
import 'neighborhood_providers.dart';
import 'services/channel_participation_resolver.dart';
import 'services/pre_sync_scene_snapshot.dart';
import 'services/sync_event_background_persistence.dart';
import 'services/sync_teardown_resolver.dart';

/// Engine that handles timing calculations and sync execution for neighborhood groups.
///
/// Key Responsibilities:
/// 1. Calculate delay offsets for each member based on position and LED count
/// 2. Execute sync commands at precisely timed intervals
/// 3. Listen for incoming sync commands and schedule local execution
class NeighborhoodSyncEngine with WidgetsBindingObserver {
  final Ref _ref;
  ProviderSubscription<AsyncValue<SyncCommand?>>? _commandSubscription;
  Timer? _scheduledExecution;

  /// Debounced re-subscribe timer for the command stream. Set when the
  /// command StreamProvider surfaces an error (so a single transient
  /// Firestore error doesn't permanently kill the listener — #52 class).
  Timer? _resubscribeTimer;
  bool _isListening = false;

  /// True once we've captured the pre-sync snapshot for this listening
  /// session. Reset on startListening / stopListening so each new
  /// session snapshots the member's then-current state on its first
  /// applied command.
  bool _hasCapturedThisSession = false;

  /// True once at least one applyJson succeeded for this listening
  /// session. Gates the teardown on stopListening — if no apply ever
  /// fired (e.g. member was opted out / never received a command),
  /// the device state was never sync-altered and we leave it alone.
  bool _hasAppliedThisSession = false;

  /// Id of the last teardown command we acted on. Dedups teardown across
  /// re-subscribes: `fireImmediately` replays the latest command on every
  /// fresh subscription, so without this a resume would re-run the
  /// off/restore repeatedly.
  String? _lastHandledTeardownId;

  NeighborhoodSyncEngine(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// On app paused or detached: if our own isParticipating flag is true,
  /// flip it back to false via [NeighborhoodService.selfLeaveSync].
  /// Covers backgrounding + clean kill — a member who closes the app
  /// tears down only themselves, not the group. Does NOT cover crash:
  /// the crash-safe heartbeat reaper (NeighborhoodMember.lastSeen
  /// staleness via Cloud Function) is documented follow-up.
  ///
  /// Fire-and-forget — the OS may suspend the process before the
  /// Firestore write reaches the wire. Firestore's local cache queues
  /// it for the next resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(handleAppLifecyclePauseForTest());
    }
  }

  /// Lifecycle pause handler. Extracted as [@visibleForTesting] so unit
  /// tests can exercise the gate logic + clear path without needing a
  /// real WidgetsBinding lifecycle event to be dispatched.
  @visibleForTesting
  Future<void> handleAppLifecyclePauseForTest() async {
    final groupId = _ref.read(activeNeighborhoodIdProvider);
    final member = _ref.read(currentUserMemberProvider);
    if (groupId == null || member == null || !member.isParticipating) {
      return;
    }
    try {
      await _ref
          .read(neighborhoodNotifierProvider.notifier)
          .selfLeaveSync(groupId);
    } catch (e) {
      debugPrint('App-pause self-leave failed: $e');
    }
  }

  /// Checks if the current member should participate in the given sync command.
  bool _shouldParticipateInSync(NeighborhoodMember member, SyncCommand command) {
    // Not participating if offline
    if (!member.isOnline) return false;

    // Not participating if paused
    if (member.participationStatus == MemberParticipationStatus.paused) return false;

    // Not participating if globally opted out
    if (member.participationStatus == MemberParticipationStatus.optedOut) return false;

    // Check schedule-specific opt-out if this sync is from a schedule
    if (command.scheduleId != null && member.isOptedOutOf(command.scheduleId!)) {
      return false;
    }

    return true;
  }

  /// Filters members to only include those who are actively participating.
  ///
  /// Excludes:
  /// - Offline members
  /// - Members who have paused their participation
  /// - Members who have opted out (either globally or for a specific schedule)
  List<NeighborhoodMember> _filterActiveMembers(
    List<NeighborhoodMember> members,
    String? scheduleId,
  ) {
    return members.where((m) {
      // Must be online
      if (!m.isOnline) {
        debugPrint('Excluding ${m.displayName}: offline');
        return false;
      }
      // Must not be paused
      if (m.participationStatus == MemberParticipationStatus.paused) {
        debugPrint('Excluding ${m.displayName}: paused');
        return false;
      }
      // Must not be opted out globally
      if (m.participationStatus == MemberParticipationStatus.optedOut) {
        debugPrint('Excluding ${m.displayName}: opted out');
        return false;
      }
      // If this is for a specific schedule, check schedule-specific opt-out
      if (scheduleId != null && m.isOptedOutOf(scheduleId)) {
        debugPrint('Excluding ${m.displayName}: opted out of schedule $scheduleId');
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
  }

  /// Calculates the delay (in milliseconds) for each member based on their position.
  ///
  /// The delay is calculated so that animations appear to flow seamlessly from
  /// one home to the next. For example, if House A has 300 LEDs and the animation
  /// runs at 50 pixels/second, House B should start 6 seconds after House A.
  ///
  /// Formula: delay[i] = sum(ledCount[0..i-1]) / pixelsPerSecond * 1000 + gapDelay * i
  Map<String, int> calculateMemberDelays(
    List<NeighborhoodMember> members,
    SyncTimingConfig config,
  ) {
    // Sort members by position
    final sorted = List<NeighborhoodMember>.from(members)
      ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));

    // Optionally reverse for right-to-left animation
    if (config.reverseDirection) {
      final reversed = sorted.reversed.toList();
      sorted
        ..clear()
        ..addAll(reversed);
    }

    final delays = <String, int>{};
    int cumulativeLeds = 0;

    for (int i = 0; i < sorted.length; i++) {
      final member = sorted[i];

      // Calculate delay based on cumulative LEDs before this member
      final ledDelay = config.pixelsPerSecond > 0
          ? (cumulativeLeds / config.pixelsPerSecond * 1000).round()
          : 0;

      // Add any configured gap delay between homes
      final gapDelay = (config.gapDelayMs * i).round();

      delays[member.oderId] = ledDelay + gapDelay;

      // Add this member's LEDs to the cumulative total
      cumulativeLeds += member.ledCount;
    }

    debugPrint('Calculated delays for ${members.length} members:');
    for (final entry in delays.entries) {
      debugPrint('  ${entry.key}: ${entry.value}ms');
    }

    return delays;
  }

  /// Creates a sync command with calculated delays for all members.
  ///
  /// Only active, online members who haven't paused or opted out are included
  /// in the timing calculations. This ensures the animation flows correctly
  /// even when some members are not participating.
  SyncCommand createSyncCommand({
    required String groupId,
    required List<NeighborhoodMember> members,
    required int effectId,
    required List<int> colors,
    required int speed,
    required int intensity,
    required int brightness,
    required SyncTimingConfig timingConfig,
    SyncType syncType = SyncType.sequentialFlow,
    String? patternName,
    String? scheduleId,
    int pal = 5,
    int grp = 1,
    int spc = 0,
    Map<String, List<int>>? memberColorOverrides,
    String? complementTheme,
  }) {
    // Filter to only active participating members
    final activeMembers = _filterActiveMembers(members, scheduleId);

    debugPrint('Sync command: ${members.length} total members, ${activeMembers.length} active participants');

    // Calculate delays based on sync type (using only active members)
    Map<String, int> delays;
    switch (syncType) {
      case SyncType.patternMatch:
        // All homes run independently, no delay needed
        delays = {for (var m in activeMembers) m.oderId: 0};
        break;
      case SyncType.simultaneous:
        // All homes start at exactly the same time
        delays = {for (var m in activeMembers) m.oderId: 0};
        break;
      case SyncType.sequentialFlow:
        // Animation flows from home to home with calculated delays
        delays = calculateMemberDelays(activeMembers, timingConfig);
        break;
      case SyncType.complement:
        // Complement mode: all homes start simultaneously but with different colors
        delays = {for (var m in activeMembers) m.oderId: 0};
        break;
    }

    // Add a small buffer (2 seconds) before start to ensure all devices receive the command
    final startTime = DateTime.now().add(const Duration(seconds: 2));

    return SyncCommand(
      id: '', // Will be set by Firestore
      groupId: groupId,
      effectId: effectId,
      colors: colors,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
      startTimestamp: startTime,
      memberDelays: delays,
      timingConfig: timingConfig,
      syncType: syncType,
      patternName: patternName,
      scheduleId: scheduleId,
      pal: pal,
      grp: grp,
      spc: spc,
      memberColorOverrides: memberColorOverrides,
      complementTheme: complementTheme,
    );
  }

  /// Creates a complement mode sync command using a predefined theme.
  ///
  /// Each home in the neighborhood will display a different color from the theme.
  /// Colors are distributed based on member position order.
  SyncCommand createComplementCommand({
    required String groupId,
    required List<NeighborhoodMember> members,
    required ComplementTheme theme,
    int? effectIdOverride,
    int speed = 128,
    int intensity = 128,
    int brightness = 200,
    String? scheduleId,
  }) {
    // Build member color overrides from theme
    final colorOverrides = theme.buildMemberColorOverrides(members);

    debugPrint('Creating Complement Mode command with theme: ${theme.name}');
    for (final entry in colorOverrides.entries) {
      final colorHex = entry.value.map((c) => '0x${c.toRadixString(16)}').join(', ');
      debugPrint('  ${entry.key}: [$colorHex]');
    }

    return createSyncCommand(
      groupId: groupId,
      members: members,
      effectId: effectIdOverride ?? theme.recommendedEffectId,
      colors: theme.themeColors, // Fallback colors
      speed: speed,
      intensity: intensity,
      brightness: brightness,
      timingConfig: const SyncTimingConfig(), // Not used for complement
      syncType: SyncType.complement,
      patternName: '${theme.name} (Complement)',
      scheduleId: scheduleId,
      memberColorOverrides: colorOverrides,
      complementTheme: theme.id,
    );
  }

  /// Starts listening for sync commands on the active group.
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    _hasCapturedThisSession = false;
    _hasAppliedThisSession = false;
    debugPrint('Starting neighborhood sync listener...');

    _commandSubscription = _ref.listen<AsyncValue<SyncCommand?>>(
      latestSyncCommandProvider,
      handleCommandSnapshot,
      // fireImmediately replays the CURRENT command on (re)subscribe rather
      // than waiting for the next change. This is the fix for the
      // restart-required propagation bug: a stop→start churn (the asymmetric
      // trigger explicitly allows hasActiveGroup to drop and re-raise) used
      // to re-subscribe against an already-resolved, non-autoDispose
      // StreamProvider and silently MISS the active design until the next
      // change. With fireImmediately the active design is re-applied on every
      // fresh subscription. The id-dedup below still prevents a double-apply
      // of the SAME command within a single subscription's lifetime.
      fireImmediately: true,
    );
  }

  /// Handles one emission from [latestSyncCommandProvider]. Extracted from
  /// the `ref.listen` callback so it is unit-testable without standing up a
  /// real Firestore command stream.
  ///
  /// Three branches:
  ///  - error  → the stream surfaced an error. Don't die silently (#52
  ///             class): schedule a debounced re-subscribe and bail.
  ///  - no cmd → nothing to apply (empty collection / unparseable doc that
  ///             [NeighborhoodService.watchLatestCommand] mapped to null).
  ///  - new cmd→ apply, unless it's the same id we last applied on this
  ///             subscription (dedup — guards fireImmediately replay from
  ///             double-applying when no real change occurred).
  @visibleForTesting
  void handleCommandSnapshot(
    AsyncValue<SyncCommand?>? previous,
    AsyncValue<SyncCommand?> next,
  ) {
    if (next.hasError) {
      debugPrint('Sync command stream error: ${next.error} — '
          'scheduling re-subscribe (listener stays alive)');
      scheduleCommandStreamResubscribe();
      return;
    }

    final command = next.valueOrNull;
    if (command == null) return;

    // Teardown signal: an explicit "revert now" command (owner End Group /
    // self-leave) broadcast on the same channel as design commands. Handle it
    // BEFORE the design dedup so it always lands, and route it to the local
    // teardown restore instead of applying a pattern. Returns without ever
    // touching the design-apply / β-self-set path (which would re-flag the
    // member participating and re-light them).
    if (command.isTeardown) {
      handleTeardownCommand(command);
      return;
    }

    // Dedup: same command id as the previous emission → no re-apply. New
    // command broadcasts always carry a fresh auto-id (broadcastSyncCommand),
    // so a genuine design change is never suppressed; only a redundant
    // replay of the already-applied command is.
    final prevCommand = previous?.valueOrNull;
    if (prevCommand?.id == command.id) return;

    debugPrint('Received new sync command: ${command.patternName}');
    onNewSyncCommand(command);
  }

  /// Apply seam for a newly-received sync command. Public + visibleForTesting
  /// so spy subclasses can record receipt without a real WLED apply (private
  /// members can't be overridden across libraries).
  @visibleForTesting
  void onNewSyncCommand(SyncCommand command) => _scheduleLocalExecution(command);

  /// Acts on a teardown command — the reliable replacement for the flag-trigger
  /// revert. Runs the local teardown restore (schedule → autopilot → pre-sync
  /// scene → off via [executeMemberTeardown]) instead of applying a design.
  ///
  /// - Scope: a self-leave teardown carries [SyncCommand.targetMemberUid]; we
  ///   ignore it if it's not for us. A null target = whole-group teardown.
  /// - Dedup: skipped if we already handled this teardown id (guards the
  ///   `fireImmediately` replay on every re-subscribe/resume).
  /// - Gates: clears the apply gates so the flag-trigger's [stopListening]
  ///   doesn't ALSO fire a redundant teardown, and so the next session
  ///   captures fresh.
  ///
  /// NOT gated on [_hasAppliedThisSession]: a member returning from background
  /// has that flag reset by [startListening] yet may still be showing the
  /// ended pattern — honoring the explicit signal is exactly what reverts them
  /// (and closes the defect-#2 replay loop, since the teardown is now latest).
  @visibleForTesting
  void handleTeardownCommand(SyncCommand command) {
    final myId = _ref.read(currentUserMemberProvider)?.oderId;
    if (command.targetMemberUid != null && command.targetMemberUid != myId) {
      return;
    }
    if (_lastHandledTeardownId == command.id) return;
    _lastHandledTeardownId = command.id;

    debugPrint('Received teardown command ${command.id} '
        '(target=${command.targetMemberUid ?? "ALL"}) — reverting');

    _hasCapturedThisSession = false;
    _hasAppliedThisSession = false;
    dispatchTeardown();
  }

  /// Test seam: dispatches the local teardown restore (fire-and-forget).
  /// Overridable so unit tests can assert the teardown-command path fires
  /// without standing up a real WLED repo inside [_executeTeardown].
  @visibleForTesting
  void dispatchTeardown() => unawaited(_executeTeardown());

  /// Re-subscribes the command stream after a transient error, debounced so
  /// an error storm doesn't hot-loop invalidation. Mirrors the #52 fix
  /// pattern (e005a02): a stream error must never end the listener.
  @visibleForTesting
  void scheduleCommandStreamResubscribe() {
    if (!_isListening) return;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = Timer(
      const Duration(seconds: 2),
      resubscribeCommandStreamNow,
    );
  }

  /// Invalidates [latestSyncCommandProvider] so [NeighborhoodService.watchLatestCommand]
  /// re-subscribes with a fresh Firestore listener. Combined with
  /// fireImmediately on the engine's listen, this replays + re-applies the
  /// current design. Safe to call when idle — the provider resolves to null
  /// when no group is active.
  @visibleForTesting
  void resubscribeCommandStreamNow() {
    try {
      _ref.invalidate(latestSyncCommandProvider);
    } catch (e) {
      debugPrint('Command stream re-subscribe failed: $e');
    }
  }

  /// Re-asserts sync after the app returns to the foreground. The OS may have
  /// suspended the process across a design change, and a backgrounded
  /// Firestore stream can close. Re-subscribing the command stream heals a
  /// dead stream AND (via fireImmediately) re-applies the current design, so
  /// returning from background recovers WITHOUT a full relaunch.
  void handleAppResume() {
    resubscribeCommandStreamNow();
  }

  /// Test seam: force the listening flag so resume / re-subscribe gating can
  /// be exercised without standing up the real command subscription.
  @visibleForTesting
  set isListeningForTest(bool value) => _isListening = value;

  /// Stops listening for sync commands.
  ///
  /// On a true listening→not-listening transition (i.e. when this
  /// session actually applied something), dispatches the distributed
  /// teardown via [_executeTeardown] BEFORE clearing the subscription
  /// + timer. The teardown is fire-and-forget — it runs async against
  /// the still-alive engine [_ref] (the engine Provider outlives any
  /// single listening session). Subsequent stopListening calls on an
  /// already-stopped engine no-op.
  void stopListening() {
    if (!_isListening) return; // idempotent — only fire teardown on transition
    _isListening = false;

    // Snapshot the apply gate before clearing, so the async teardown
    // dispatch below cannot race with a re-entrant start/stop.
    final shouldTeardown = _hasAppliedThisSession;
    _hasCapturedThisSession = false;
    _hasAppliedThisSession = false;

    if (shouldTeardown) {
      unawaited(_executeTeardown());
    }

    _commandSubscription?.close();
    _commandSubscription = null;
    _scheduledExecution?.cancel();
    _scheduledExecution = null;
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    debugPrint(
      'Stopped neighborhood sync listener'
      '${shouldTeardown ? ' (teardown dispatched)' : ''}',
    );
  }

  /// Schedules local pattern execution based on the command's timing.
  void _scheduleLocalExecution(SyncCommand command) {
    // Cancel any pending execution
    _scheduledExecution?.cancel();

    // Get current user's member data
    final currentMember = _ref.read(currentUserMemberProvider);
    if (currentMember == null) {
      debugPrint('No current member found, skipping sync');
      return;
    }

    // Check if current user is participating in this sync
    if (!_shouldParticipateInSync(currentMember, command)) {
      debugPrint('Current user is not participating in this sync (paused/opted out/offline)');
      return;
    }

    // Check if we have a delay for this member (they were included in the sync)
    final myDelay = command.getDelayForMember(currentMember.oderId);
    if (myDelay < 0) {
      // Member was not included in sync command (joined after sync started, etc.)
      debugPrint('No delay found for current user, not included in this sync');
      return;
    }

    // β self-set: flip our own per-member apply gate so the asymmetric
    // trigger (syncEngineControllerProvider) keeps the listener mounted
    // independent of hasActiveGroup, and so member-stop / owner-end
    // fan-clear can drop us cleanly via the per-member flag.
    //
    // Scoped self-write (request.auth.uid == memberUid) — already
    // permitted by the existing /neighborhoods/{groupId}/members/{memberUid}
    // rule (firestore.rules:1252). No rule change.
    //
    // Idempotent: skip if our flag is already true (avoids re-writes on
    // every subsequent command in the same session).
    //
    // Fire-and-forget: a failed flag-write degrades to the hasActiveGroup
    // START fallback (we stay mounted because some group is active), and
    // the user-visible apply still proceeds.
    if (!currentMember.isParticipating) {
      unawaited(markSelfParticipating(command.groupId, currentMember.oderId));
    }

    final now = DateTime.now();
    final startTime = command.startTimestamp.add(Duration(milliseconds: myDelay));

    // Calculate time until we should start
    final waitDuration = startTime.difference(now);

    if (waitDuration.isNegative) {
      // Start time already passed, execute immediately
      debugPrint('Start time passed, executing immediately');
      _executePattern(command);
    } else {
      // Schedule for future execution
      debugPrint('Scheduling pattern execution in ${waitDuration.inMilliseconds}ms');
      _scheduledExecution = Timer(waitDuration, () {
        _executePattern(command);
      });
    }
  }

  /// Writes `isParticipating: true` to this member's doc at
  /// `/neighborhoods/{groupId}/members/{memberUid}` (merge), so the
  /// asymmetric trigger keeps the listener mounted via the per-member
  /// gate. Errors are logged but never thrown — apply must proceed.
  ///
  /// Visible for testing so spy subclasses can record calls without
  /// hitting a real Firestore in unit tests.
  @visibleForTesting
  Future<void> markSelfParticipating(String groupId, String memberUid) async {
    try {
      await FirebaseFirestore.instance
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(memberUid)
          .set({'isParticipating': true}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Sync self-mark participating failed: $e');
    }
  }

  /// Test-only entry point for `_scheduleLocalExecution`. Lets the β
  /// self-set test exercise the receive-time self-write path without
  /// standing up a real Firestore command stream.
  @visibleForTesting
  void scheduleLocalExecutionForTest(SyncCommand command) =>
      _scheduleLocalExecution(command);

  /// Test-only entry point for `_executePattern`. Used by Bundle 3b.3c
  /// regression tests for the post-removal single-seg-no-id payload
  /// shape, and by the Symptom 1 regression guard that asserts empty
  /// participation NO LONGER short-circuits the apply.
  @visibleForTesting
  Future<void> executePatternForTest(SyncCommand command) =>
      _executePattern(command);

  /// Executes the pattern on the local WLED device.
  Future<void> _executePattern(SyncCommand command) async {
    debugPrint('Executing sync pattern: ${command.patternName}');

    try {
      final wledRepo = _ref.read(wledRepositoryProvider);
      if (wledRepo == null) {
        debugPrint('No WLED repository available');
        return;
      }

      // Get current member to check for member-specific overrides
      final currentMember = _ref.read(currentUserMemberProvider);
      final memberId = currentMember?.oderId ?? '';

      // Resolve the pattern for this specific member (handles per-house assignments,
      // complement mode color overrides, or falls back to global fields)
      final memberPattern = command.getPatternForMember(memberId);

      // Build WLED JSON payload with member-specific pattern.
      // Colors → RGBW (W=0); col slots are passed verbatim into every
      // participating seg entry.
      final colorArrays = memberPattern.colors.map((c) {
        final r = (c >> 16) & 0xFF;
        final g = (c >> 8) & 0xFF;
        final b = c & 0xFF;
        return <int>[r, g, b, 0];
      }).toList();

      if (colorArrays.isEmpty) {
        colorArrays.add([255, 255, 255, 0]);
      }
      while (colorArrays.length < 3) {
        colorArrays.add([0, 0, 0, 0]);
      }

      // Resolve participating channels for the LOCAL user.
      // Default policy (when the member has no explicit pick): channels
      // with at least one isPrimary segment; falls back to all-channels
      // if no roofline configuration exists (untraced install). See
      // resolveParticipatingChannels for the full contract.
      final rooflineAsync = _ref.read(currentRooflineConfigProvider);
      final segments = rooflineAsync.maybeWhen(
        data: (c) => c?.segments ?? const <RooflineSegment>[],
        orElse: () => const <RooflineSegment>[],
      );
      final deviceChannelIds =
          _ref.read(deviceChannelsProvider).map((c) => c.id).toList();
      final participating = resolveParticipatingChannels(
        explicit: currentMember?.participatingChannelIndices,
        segments: segments,
        allDeviceChannelIds: deviceChannelIds,
      );

      // Persist the resolved list for the background isolate (Bundle 4
      // will read this; Bundle 3 only writes it). Fire-and-forget.
      unawaited(saveLocalParticipatingChannels(participating));

      // (REMOVED) The b4a6f46 empty-participation skip-apply gate used
      // to short-circuit here. Symptom 1 of the multi-home regression:
      // for any member whose roofline had no isPrimary-flagged segment,
      // the gate silently no-op'd the apply and only the presser's home
      // ever ran the sync. Per CHANNEL_MAPPING_AUDIT_2026-05.md:459 the
      // participatingChannelIndices field is dead schema (no UI writes
      // it, no picker exists, every shipped member null) — so the gate
      // was defending semantics no UI could produce. Dropped; every
      // joined home applies. When/if partial-channel participation
      // ships with a real picker, re-add the gate with defaults
      // co-designed against the picker.

      // ── PRE-SYNC SCENE CAPTURE ─────────────────────────────────────
      // First applicable command per listening session: snapshot the
      // member's current WLED state BEFORE the apply, so Stop-Sync
      // teardown can fall back to this state when no schedule item /
      // autopilot item resolves. Awaited inline so the snapshot is
      // guaranteed to reflect PRE-sync state (no race with the apply
      // below). Failures are swallowed by capturePreSyncScene — a
      // null snapshot just makes the teardown fall through to the off
      // tier, which is the correct conservative behavior.
      if (!_hasCapturedThisSession) {
        _hasCapturedThisSession = true;
        await _captureSnapshotForFirstCommand(command.groupId, wledRepo);
      }

      // Build single-seg-no-id with fx. The applyJson chokepoint
      // ([expandForParticipation] in wled_payload_utils.dart) reads the
      // persisted cache and rule-7-expands this entry per participating
      // channel id. With the Symptom 1 gate dropped, empty-participation
      // calls still reach this builder — the chokepoint Rule 2
      // pass-through is the no-op safety net.
      final payload = {
        'on': true,
        'bri': memberPattern.brightness,
        'seg': [
          {
            'fx': memberPattern.effectId,
            'sx': memberPattern.speed,
            'ix': memberPattern.intensity,
            // CRITICAL: carry pal:5 ("Colors Only") through to the applied seg.
            // Without it WLED falls back to its default rainbow palette, which
            // overrides the selected `col` colors → chaotic flashing. grp/spc
            // preserve any grouping/spacing the source design specified.
            'pal': memberPattern.pal,
            'grp': memberPattern.grp,
            'spc': memberPattern.spc,
            'col': colorArrays.take(3).toList(),
          },
        ],
      };

      final success = await wledRepo.applyJson(payload);

      if (success) {
        // Mark this session as having sync-altered the device. The
        // Stop-Sync teardown only fires when this flag is set —
        // members whose participation gate skipped every apply leave
        // the flag false, so stopListening doesn't tear down state
        // that was never sync-altered.
        _hasAppliedThisSession = true;

        debugPrint('Pattern applied successfully: ${memberPattern.name}');
        if (command.hasPerHouseAssignments) {
          debugPrint('Per-house assignment: effect=${memberPattern.effectId}, '
              'colors=${memberPattern.colors.map((c) => '0x${c.toRadixString(16)}')}');
        } else if (command.isComplementMode) {
          debugPrint('Complement Mode: Applied colors ${memberPattern.colors.map((c) => '0x${c.toRadixString(16)}')} for member $memberId');
        }

        // Update local state metadata
        _ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
          colorSequence: memberPattern.colorObjects,
          effectName: memberPattern.name,
        );

        // Fan the sync design name out to the Now Playing label so the
        // dashboard's preset chip reflects the active sync immediately —
        // without this the label stays at whatever pre-sync state it
        // held, then never updates on teardown for non-scene tiers
        // (Bug 3 in the cache-refresh audit). Teardown clears/restores
        // the label per tier; this is the matching start-side write.
        if (memberPattern.name.isNotEmpty) {
          _ref
              .read(activePresetLabelProvider.notifier)
              .setLabelWithFingerprint(
                memberPattern.name,
                _ref.read(wledStateProvider),
              );
        }
      } else {
        debugPrint('Failed to apply pattern');
      }
    } catch (e) {
      debugPrint('Error executing sync pattern: $e');
    }
  }

  /// First-command pre-sync scene capture. Awaited inline by
  /// [_executePattern] so the snapshot reflects pre-apply state. The
  /// helper itself swallows getState() errors and returns null on
  /// failure — a null capture leaves [preSyncSceneProvider] untouched,
  /// which makes the eventual teardown fall through to the off tier
  /// (the conservative safe default).
  Future<void> _captureSnapshotForFirstCommand(
    String groupId,
    WledRepository repo,
  ) async {
    final label = _ref.read(activePresetLabelProvider);
    final scene = await capturePreSyncScene(
      groupId: groupId,
      repo: repo,
      activeLabel: label,
    );
    if (scene == null) {
      debugPrint('Pre-sync capture: null snapshot (offline / empty / error)');
      return;
    }
    _ref.read(preSyncSceneProvider.notifier).state = scene;
    debugPrint(
      'Pre-sync capture: snapshot stored for $groupId '
      '(label="${scene.activeLabel}", capturedAt=${scene.capturedAt.toIso8601String()})',
    );
  }

  /// Distributed Stop-Sync teardown: each member resolves its own
  /// correct state locally and applies it. Fired by [stopListening]
  /// on the true listening→not-listening transition.
  ///
  /// Priority (locked by [resolveCurrentMemberState] and the
  /// [executeMemberTeardown] orchestrator):
  ///   1. active schedule item right now (with payload) → apply + label
  ///   2. active autopilot item right now → apply + label
  ///   3. fresh pre-sync scene captured at sync start → apply + label
  ///   4. → off + clear label
  ///
  /// All applies route through [WledRepository.applyJson] → the
  /// chokepoint, so participation is respected on restore (a
  /// non-participating channel won't receive the restore payload).
  /// The pre-sync scene is cleared after consumption so the next
  /// session captures fresh. The participation cache is cleared
  /// alongside so the dashboard channel-selector chips un-strike.
  Future<MemberTeardownAction?> _executeTeardown() async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) {
      debugPrint('Teardown skip: no WLED repo');
      return null;
    }

    final activeSchedule = _ref.read(currentScheduledActionProvider);
    final scheduler = _ref.read(autopilotSchedulerProvider);
    final activeAutopilot = currentAutopilotItemFor(
      activeSchedule: scheduler.activeSchedule,
      now: DateTime.now(),
    );
    final preSyncScene = _ref.read(preSyncSceneProvider);
    final activeGroupId = _ref.read(activeNeighborhoodIdProvider);

    // Read the local participating-channels cache — the same source
    // [WledService.applyJson] reads inside the chokepoint. Passed to
    // the executor so its pre-applyJson filter ([filterMultiSegByParticipation])
    // can strip non-participating segs from externally-sourced multi-
    // seg-with-ids payloads (the scene tier's getState() snapshot)
    // BEFORE they reach the chokepoint's Rule 4 pass-through.
    final participating = await getCachedParticipatingChannels();

    try {
      final action = await executeMemberTeardown(
        activeSchedule: activeSchedule,
        activeAutopilot: activeAutopilot,
        preSyncScene: preSyncScene,
        activeGroupId: activeGroupId,
        now: DateTime.now(),
        repo: repo,
        restorePresetLabel: (label) {
          // null = clear (off tier). Non-empty = set + fingerprint.
          // Empty string is a no-op safety net so a tier-source field
          // that happens to be empty doesn't wipe a label the user
          // expects to keep. The TurnOff tier passes literal null so
          // it always clears regardless of any upstream empties.
          final notifier =
              _ref.read(activePresetLabelProvider.notifier);
          if (label == null) {
            notifier.clear();
          } else if (label.isNotEmpty) {
            notifier.setLabelWithFingerprint(
              label,
              _ref.read(wledStateProvider),
            );
          }
        },
        clearPreSyncScene: () {
          _ref.read(preSyncSceneProvider.notifier).state = null;
        },
        restoreParticipation: () {
          // Sync's [_executePattern] writes the participation cache on
          // every apply but nothing clears it on teardown, so the
          // dashboard channel-selector chips stayed strike-through
          // across sync sessions until app relaunch reloaded the cache
          // from disk (which mirrored the same value). Clearing to
          // null here restores the "no preference = all channels"
          // default that the applyJson chokepoint and the dashboard
          // gate both treat as the open state. Fire-and-forget — never
          // block teardown completion on the SharedPreferences write.
          unawaited(saveLocalParticipatingChannels(null));
        },
        participating: participating,
      );
      debugPrint('Sync teardown executed: ${action.runtimeType}');
      return action;
    } catch (e) {
      debugPrint('Sync teardown failed: $e');
      return null;
    }
  }

  /// @visibleForTesting accessors so unit tests can drive the engine
  /// without a full Riverpod-listen wire-up.

  @visibleForTesting
  bool get hasCapturedForTest => _hasCapturedThisSession;

  @visibleForTesting
  bool get hasAppliedForTest => _hasAppliedThisSession;

  @visibleForTesting
  bool get isListeningForTest => _isListening;

  /// Flips the listening flag so tests can exercise the teardown branch
  /// of [stopListening] without standing up a Riverpod listener.
  @visibleForTesting
  void setListeningForTest({required bool listening}) {
    _isListening = listening;
  }

  /// Sets the applied flag so tests can simulate "this session did
  /// apply something" without driving the full _executePattern path
  /// (which depends on a lot of providers that aren't relevant to
  /// teardown-specific assertions).
  @visibleForTesting
  void setHasAppliedForTest({required bool hasApplied}) {
    _hasAppliedThisSession = hasApplied;
  }

  /// Direct test hook for the teardown — equivalent to calling
  /// stopListening() with the apply gate true, but exposes the
  /// resolved MemberTeardownAction so tests can assert it.
  @visibleForTesting
  Future<MemberTeardownAction?> executeTeardownForTest() => _executeTeardown();

  /// Disposes of resources.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopListening();
  }
}

/// Provider for the sync engine.
final neighborhoodSyncEngineProvider = Provider<NeighborhoodSyncEngine>((ref) {
  final engine = NeighborhoodSyncEngine(ref);
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Provider to manage sync engine listening state.
final syncEngineActiveProvider = StateProvider<bool>((ref) {
  return false;
});

/// Auto-start/stop sync engine with asymmetric start-broad / teardown-narrow
/// semantics. Symptom-2 fix for the 3dbca29 cross-member revert regression.
///
/// START broad: mount the listener on any of three signals so the first-sync
/// chicken-and-egg doesn't strand the member — own [NeighborhoodMember.isParticipating]
/// is false until the engine receives a SyncCommand and self-sets it (Prompt 3
/// β-self-set), so [isInActiveSyncProvider] must still mount the listener.
///
/// TEARDOWN narrow: stopListening fires ONLY when ALL three signals are
/// false. Under the OLD trigger, [isInActiveSyncProvider] dropping alone
/// called stopListening on every member, which fired _executeTeardown on
/// every home that had applied — the 3dbca29 regression. Under this rewrite,
/// hasActiveGroup dropping while [isInActiveSyncProvider]'s read-side own
/// flag stays true keeps the listener mounted — only that member's own flag
/// going false (member-stop UI or owner endGroupSync fan-clear) can route
/// them through stopListening + teardown.
///
/// [isInActiveSyncProvider] is preserved for the (currently unbuilt) "warn
/// user before changing lights" UI surface and for the START condition here.
/// It must NEVER drive the apply/teardown gate going forward — that
/// decoupling IS the fix.
///
/// Must be watched somewhere in the widget tree (e.g., NeighborhoodSyncScreen)
/// for the engine to start listening for incoming sync commands.
final syncEngineControllerProvider = Provider<void>((ref) {
  final manuallyActive = ref.watch(syncEngineActiveProvider);
  final myMember = ref.watch(currentUserMemberProvider);
  final iAmParticipating = myMember?.isParticipating ?? false;
  final hasActiveGroup = ref.watch(isInActiveSyncProvider);
  final engine = ref.watch(neighborhoodSyncEngineProvider);

  if (manuallyActive || iAmParticipating || hasActiveGroup) {
    engine.startListening();
  } else {
    engine.stopListening();
  }
});

/// Resolves which neighborhood group [activeNeighborhoodIdProvider] should
/// point at, app-wide, given the current explicit selection and the live
/// list of the user's groups.
///
/// Why this exists: the live command listener ([latestSyncCommandProvider]
/// and [currentUserMemberProvider]) keys off [activeNeighborhoodIdProvider],
/// which defaults to null and was only ever set by the Neighborhood Sync
/// screen (on group tap / create / join). A receiver who never opened that
/// screen had no resolved group, so the app-level listener had nothing to
/// watch — the core of the restart-required propagation bug. Hoisting this
/// resolution to an always-mounted scope (see main.dart) lets the listener
/// target the right group regardless of which screen the user is on.
///
/// Policy (only ever broadens, never clears an explicit selection):
///  - no groups            → keep current (don't clobber a stale id mid-leave)
///  - current id still valid→ keep it (respect explicit on-screen selection)
///  - any group is actively syncing → target it (so a receiver auto-tunes to
///    the live sync)
///  - exactly one group    → target it (so we're already watching when a
///    sync starts — covers the common two-home single-group case)
///  - multi-group, none active, no valid selection → leave null (ambiguous;
///    defer to explicit on-screen selection)
String? resolveAutoActiveGroupId(
  String? currentId,
  List<NeighborhoodGroup> groups,
) {
  if (groups.isEmpty) return currentId;
  if (currentId != null && groups.any((g) => g.id == currentId)) {
    return currentId;
  }
  for (final g in groups) {
    if (g.isActive) return g.id;
  }
  if (groups.length == 1) return groups.first.id;
  return currentId;
}
