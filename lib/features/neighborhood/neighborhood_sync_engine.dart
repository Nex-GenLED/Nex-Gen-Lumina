import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wled/wled_providers.dart';
import 'neighborhood_models.dart';
import 'neighborhood_providers.dart';

/// Engine that handles timing calculations and sync execution for neighborhood groups.
///
/// Key Responsibilities:
/// 1. Calculate delay offsets for each member based on position and LED count
/// 2. Execute sync commands at precisely timed intervals
/// 3. Listen for incoming sync commands and schedule local execution
class NeighborhoodSyncEngine {
  final Ref _ref;
  ProviderSubscription<AsyncValue<SyncCommand?>>? _commandSubscription;
  Timer? _scheduledExecution;
  bool _isListening = false;

  NeighborhoodSyncEngine(this._ref);

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
      sorted.reversed;
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
    debugPrint('Starting neighborhood sync listener...');

    _commandSubscription = _ref.listen<AsyncValue<SyncCommand?>>(
      latestSyncCommandProvider,
      (previous, next) {
        final command = next.valueOrNull;
        if (command == null) return;

        // Check if this is a new command (not the same as previous)
        final prevCommand = previous?.valueOrNull;
        if (prevCommand?.id == command.id) return;

        debugPrint('Received new sync command: ${command.patternName}');
        _scheduleLocalExecution(command);
      },
    );
  }

  /// Stops listening for sync commands.
  void stopListening() {
    _isListening = false;
    _commandSubscription?.close();
    _commandSubscription = null;
    _scheduledExecution?.cancel();
    _scheduledExecution = null;
    debugPrint('Stopped neighborhood sync listener');
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

  /// Executes the pattern on the local WLED device.
  Future<void> _executePattern(SyncCommand command) async {
    debugPrint('Executing sync pattern: ${command.patternName}');

    try {
      final wledRepo = _ref.read(wledRepositoryProvider);
      if (wledRepo == null) {
        debugPrint('No WLED repository available');
        return;
      }

      // Get current member to check for member-specific colors
      final currentMember = _ref.read(currentUserMemberProvider);
      final memberId = currentMember?.oderId ?? '';

      // Get colors for this specific member (handles Complement Mode)
      final memberColors = command.getColorsForMember(memberId);

      // Build WLED JSON payload with member-specific colors
      final colorArrays = memberColors.map((c) {
        // Convert int color to RGB array
        final r = (c >> 16) & 0xFF;
        final g = (c >> 8) & 0xFF;
        final b = c & 0xFF;
        return [r, g, b];
      }).toList();

      // Ensure we have at least one color
      if (colorArrays.isEmpty) {
        colorArrays.add([255, 255, 255]);
      }

      // Pad to 3 colors if needed (WLED expects up to 3)
      while (colorArrays.length < 3) {
        colorArrays.add([0, 0, 0]);
      }

      final payload = {
        'on': true,
        'bri': command.brightness,
        'seg': [
          {
            'fx': command.effectId,
            'sx': command.speed,
            'ix': command.intensity,
            'col': colorArrays.take(3).toList(),
          }
        ],
      };

      final success = await wledRepo.applyJson(payload);

      if (success) {
        debugPrint('Pattern applied successfully');
        if (command.isComplementMode) {
          debugPrint('Complement Mode: Applied colors ${memberColors.map((c) => '0x${c.toRadixString(16)}')} for member $memberId');
        }

        // Update local state metadata with member-specific colors
        final colors = command.getColorObjectsForMember(memberId);
        _ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
          colorSequence: colors,
          effectName: command.patternName,
        );
      } else {
        debugPrint('Failed to apply pattern');
      }
    } catch (e) {
      debugPrint('Error executing sync pattern: $e');
    }
  }

  /// Disposes of resources.
  void dispose() {
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

/// Auto-start/stop sync engine based on active state.
final syncEngineControllerProvider = Provider<void>((ref) {
  final isActive = ref.watch(syncEngineActiveProvider);
  final engine = ref.watch(neighborhoodSyncEngineProvider);

  if (isActive) {
    engine.startListening();
  } else {
    engine.stopListening();
  }
});
