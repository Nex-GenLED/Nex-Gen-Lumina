import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Enforcement mode for scheduled actions.
enum ScheduleEnforcementMode {
  /// Don't enforce - user manual changes persist until next scheduled event.
  /// This is the legacy WLED timer behavior.
  disabled,

  /// Soft enforcement - re-apply schedule after a grace period (e.g., 2 hours).
  /// Allows temporary manual overrides that auto-revert.
  soft,

  /// Strict enforcement - re-apply schedule within minutes of manual change.
  /// Ensures schedules always take priority.
  strict,
}

/// Service that monitors the active schedule and enforces it by re-applying
/// the scheduled state if the user manually changes the lights.
///
/// This solves the problem where a user turns on a pattern manually and forgets
/// about it, leaving the lights in that state instead of following the schedule.
///
/// **Enforcement Logic:**
/// 1. Every [checkInterval], compare current device state to active schedule
/// 2. If there's a mismatch and enough time has passed since the schedule started,
///    re-apply the scheduled state
/// 3. Track when manual overrides occur to allow grace periods
class ScheduleEnforcementService {
  final Ref _ref;
  Timer? _timer;
  DateTime? _lastManualOverride;
  DateTime? _lastEnforcement;

  /// How often to check if enforcement is needed.
  final Duration checkInterval;

  /// Grace period before re-applying schedule after manual change.
  /// In soft mode, this is typically 2 hours.
  /// In strict mode, this is typically 5 minutes.
  final Duration gracePeriod;

  /// Current enforcement mode.
  ScheduleEnforcementMode mode;

  ScheduleEnforcementService(
    this._ref, {
    this.checkInterval = const Duration(minutes: 5),
    this.gracePeriod = const Duration(hours: 2),
    this.mode = ScheduleEnforcementMode.soft,
  });

  /// Starts the enforcement timer.
  void start() {
    if (mode == ScheduleEnforcementMode.disabled) {
      debugPrint('ScheduleEnforcement: Disabled, not starting');
      return;
    }

    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => _checkAndEnforce());
    debugPrint('ScheduleEnforcement: Started with mode=$mode, interval=$checkInterval');
  }

  /// Stops the enforcement timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('ScheduleEnforcement: Stopped');
  }

  /// Call this when the user manually changes the lights (not via schedule).
  /// This starts the grace period before enforcement kicks in.
  void recordManualOverride() {
    _lastManualOverride = DateTime.now();
    debugPrint('ScheduleEnforcement: Manual override recorded at $_lastManualOverride');
  }

  /// Checks if a schedule should be enforced and applies it if needed.
  Future<void> _checkAndEnforce() async {
    if (mode == ScheduleEnforcementMode.disabled) return;

    final currentSchedule = _ref.read(currentScheduledActionProvider);
    if (currentSchedule == null) {
      debugPrint('ScheduleEnforcement: No active schedule');
      return;
    }

    // Check if we're in the grace period
    if (_lastManualOverride != null) {
      final elapsed = DateTime.now().difference(_lastManualOverride!);
      final effectiveGrace = mode == ScheduleEnforcementMode.strict
          ? const Duration(minutes: 5)
          : gracePeriod;

      if (elapsed < effectiveGrace) {
        debugPrint('ScheduleEnforcement: In grace period (${elapsed.inMinutes}m of ${effectiveGrace.inMinutes}m)');
        return;
      }
    }

    // Don't enforce too frequently
    if (_lastEnforcement != null) {
      final sinceLastEnforcement = DateTime.now().difference(_lastEnforcement!);
      if (sinceLastEnforcement < const Duration(minutes: 10)) {
        debugPrint('ScheduleEnforcement: Too soon since last enforcement');
        return;
      }
    }

    // Check if we need to enforce
    final needsEnforcement = await _checkIfEnforcementNeeded(currentSchedule);
    if (needsEnforcement) {
      await _enforceSchedule(currentSchedule);
    }
  }

  /// Checks if the current device state differs from what the schedule expects.
  Future<bool> _checkIfEnforcementNeeded(ScheduleItem schedule) async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) return false;

    // If schedule has no payload, we can't compare states
    if (!schedule.hasWledPayload) {
      debugPrint('ScheduleEnforcement: Schedule has no WLED payload to compare');
      return false;
    }

    try {
      final currentState = await repo.getState();
      if (currentState == null) return false;

      final scheduledPayload = schedule.wledPayload!;

      // Compare key fields: on, bri, and effect
      final currentOn = currentState['on'] as bool?;
      final scheduledOn = scheduledPayload['on'] as bool?;
      if (scheduledOn != null && currentOn != scheduledOn) {
        debugPrint('ScheduleEnforcement: Power state mismatch (current=$currentOn, scheduled=$scheduledOn)');
        return true;
      }

      // Compare brightness if specified
      final currentBri = currentState['bri'] as int?;
      final scheduledBri = scheduledPayload['bri'] as int?;
      if (scheduledBri != null && currentBri != null) {
        // Allow 5% tolerance for brightness
        final diff = (currentBri - scheduledBri).abs();
        if (diff > 12) { // ~5% of 255
          debugPrint('ScheduleEnforcement: Brightness mismatch (current=$currentBri, scheduled=$scheduledBri)');
          return true;
        }
      }

      // Compare effect ID if segments are specified
      final currentSeg = currentState['seg'];
      final scheduledSeg = scheduledPayload['seg'];
      if (currentSeg is List && scheduledSeg is List && scheduledSeg.isNotEmpty) {
        final currentFx = (currentSeg.isNotEmpty && currentSeg[0] is Map)
            ? currentSeg[0]['fx'] as int?
            : null;
        final scheduledFx = (scheduledSeg[0] is Map)
            ? scheduledSeg[0]['fx'] as int?
            : null;

        if (scheduledFx != null && currentFx != scheduledFx) {
          debugPrint('ScheduleEnforcement: Effect mismatch (current=$currentFx, scheduled=$scheduledFx)');
          return true;
        }
      }

      debugPrint('ScheduleEnforcement: State matches schedule');
      return false;
    } catch (e) {
      debugPrint('ScheduleEnforcement: Error checking state: $e');
      return false;
    }
  }

  /// Applies the scheduled state to the device.
  Future<void> _enforceSchedule(ScheduleItem schedule) async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) return;

    debugPrint('ScheduleEnforcement: Enforcing schedule "${schedule.actionLabel}"');

    try {
      bool success;

      if (schedule.hasWledPayload) {
        // Apply the full WLED payload
        success = await repo.applyJson(schedule.wledPayload!);
      } else if (schedule.presetId != null) {
        // Load the preset
        success = await repo.loadPreset(schedule.presetId!);
      } else {
        debugPrint('ScheduleEnforcement: No payload or preset to apply');
        return;
      }

      if (success) {
        _lastEnforcement = DateTime.now();
        _lastManualOverride = null; // Clear manual override flag
        debugPrint('ScheduleEnforcement: Successfully enforced schedule');
      } else {
        debugPrint('ScheduleEnforcement: Failed to enforce schedule');
      }
    } catch (e) {
      debugPrint('ScheduleEnforcement: Exception during enforcement: $e');
    }
  }

  /// Disposes the service and cleans up resources.
  void dispose() {
    stop();
  }
}

/// Provider for schedule enforcement mode setting.
/// Stored in user preferences.
final scheduleEnforcementModeProvider = StateProvider<ScheduleEnforcementMode>(
  (ref) => ScheduleEnforcementMode.soft,
);

/// Provider for the schedule enforcement service.
final scheduleEnforcementServiceProvider = Provider<ScheduleEnforcementService>((ref) {
  final mode = ref.watch(scheduleEnforcementModeProvider);
  final service = ScheduleEnforcementService(
    ref,
    mode: mode,
    checkInterval: mode == ScheduleEnforcementMode.strict
        ? const Duration(minutes: 2)
        : const Duration(minutes: 10),
    gracePeriod: mode == ScheduleEnforcementMode.strict
        ? const Duration(minutes: 5)
        : const Duration(hours: 2),
  );

  // Auto-start if not disabled
  if (mode != ScheduleEnforcementMode.disabled) {
    service.start();
  }

  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider that exposes a simple way to record manual overrides.
/// Call this whenever the user manually changes lights outside of a schedule.
final recordManualOverrideProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(scheduleEnforcementServiceProvider).recordManualOverride();
  };
});
