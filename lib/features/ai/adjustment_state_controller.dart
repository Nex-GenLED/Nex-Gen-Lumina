import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_providers.dart' show activePresetLabelProvider;
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/controller_targeting.dart';
import 'package:nexgen_command/shared/write_result.dart';

// ---------------------------------------------------------------------------
// State model
// ---------------------------------------------------------------------------

/// Snapshot of an active adjustment session.
class AdjustmentState {
  /// The suggestion before any user adjustments.
  final LuminaLightingSuggestion originalSuggestion;

  /// The current suggestion with user adjustments applied.
  final LuminaLightingSuggestion currentSuggestion;

  /// Whether the panel is expanded.
  final bool isExpanded;

  /// Param names the user has explicitly changed (for highlights).
  final Set<String> userChangedParams;

  /// Which reply card this session belongs to (+110 E2 row 108). A card
  /// reads the session only when the key is its own; every other card in
  /// the thread keeps showing its own suggestion.
  final Object? sessionKey;

  /// Why the last "Apply This" did not land, shown in the panel (row 110).
  /// Null after a success or before any apply.
  final String? failureMessage;

  const AdjustmentState({
    required this.originalSuggestion,
    required this.currentSuggestion,
    this.isExpanded = true,
    this.userChangedParams = const {},
    this.sessionKey,
    this.failureMessage,
  });

  AdjustmentState copyWith({
    LuminaLightingSuggestion? currentSuggestion,
    bool? isExpanded,
    Set<String>? userChangedParams,
    String? failureMessage,
    bool clearFailure = false,
  }) {
    return AdjustmentState(
      originalSuggestion: originalSuggestion,
      currentSuggestion: currentSuggestion ?? this.currentSuggestion,
      isExpanded: isExpanded ?? this.isExpanded,
      userChangedParams: userChangedParams ?? this.userChangedParams,
      sessionKey: sessionKey,
      failureMessage:
          clearFailure ? null : (failureMessage ?? this.failureMessage),
    );
  }

  /// True when this session is the one [key] asks about.
  bool isFor(Object? key) => sessionKey == key;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the active adjustment session. `null` means no adjustment in progress.
class AdjustmentStateNotifier extends Notifier<AdjustmentState?> {
  @override
  AdjustmentState? build() => null;

  /// Start a new adjustment session for the card identified by [sessionKey].
  void beginAdjustment(LuminaLightingSuggestion suggestion, {Object? sessionKey}) {
    state = AdjustmentState(
      originalSuggestion: suggestion,
      currentSuggestion: suggestion,
      sessionKey: sessionKey,
    );

    // Ensure refinement mode is active for voice commands
    if (suggestion.wledPayload != null) {
      ref.read(luminaSheetProvider.notifier).setPatternContext(
            {'wled': suggestion.wledPayload},
            null,
          );
    }
  }

  /// Collapse the panel without clearing state.
  void collapse() {
    if (state == null) return;
    state = state!.copyWith(isExpanded: false);
  }

  /// Toggle expand/collapse.
  void toggle() {
    if (state == null) return;
    state = state!.copyWith(isExpanded: !state!.isExpanded);
  }

  // -----------------------------------------------------------------------
  // Parameter updates
  // -----------------------------------------------------------------------

  void updateBrightness(double brightness) {
    if (state == null) return;
    final updated = state!.currentSuggestion.copyWithChanges(
      brightness: brightness.clamp(0.0, 1.0),
    );
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, 'brightness'},
      clearFailure: true,
    );
  }

  void updateSpeed(double speed) {
    if (state == null) return;
    final updated = state!.currentSuggestion.copyWithChanges(
      speed: speed.clamp(0.0, 1.0),
    );
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, 'speed'},
      clearFailure: true,
    );
  }

  void updateEffect(EffectInfo effect) {
    if (state == null) return;
    // Auto-manage speed when switching static ↔ animated
    double? newSpeed = state!.currentSuggestion.speed;
    if (effect.isStatic) {
      newSpeed = null;
    } else {
      newSpeed ??= 0.5; // default when switching to animated
    }

    final updated = state!.currentSuggestion.copyWithChanges(
      effect: effect,
      speed: newSpeed,
    );
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, 'effect'},
      clearFailure: true,
    );
  }

  void updateColors(List<Color> colors, PaletteInfo palette) {
    if (state == null) return;
    final updated = state!.currentSuggestion.copyWithChanges(
      colors: colors,
      palette: palette,
    );
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, 'palette'},
      clearFailure: true,
    );
  }

  void updateZone(ZoneInfo zone) {
    if (state == null) return;
    final updated = state!.currentSuggestion.copyWithChanges(zone: zone);
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, 'zone'},
      clearFailure: true,
    );
  }

  // -----------------------------------------------------------------------
  // Apply & voice sync
  // -----------------------------------------------------------------------

  /// Build a WLED JSON payload and send it — to the chosen zone's controller
  /// when one is picked (row 107), else to the selected controller. On
  /// success the panel collapses; on failure it STAYS OPEN and shows why
  /// (row 110: it used to collapse silently either way).
  Future<WriteResult> applyToDevice() async {
    final current = state;
    if (current == null) {
      return const WriteResult.blocked('Nothing to apply.');
    }
    final s = current.currentSuggestion;
    final payload = _buildPayload(s);

    WriteResult result;
    try {
      result = await _send(payload, s.zone);
    } catch (e) {
      debugPrint('Adjustment applyToDevice failed: $e');
      result = WriteResult.failed(
        WriteFailureKind.error,
        message: "Couldn't reach your lights — check your connection",
        error: e,
      );
    }

    if (state == null) return result; // cleared while in flight

    if (!result.ok) {
      state = state!.copyWith(
        isExpanded: true,
        failureMessage: result.message ?? kApplyBlockedFallback,
      );
      return result;
    }

    ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
          colorSequence: s.colors,
          colorNames: s.palette.colorNames,
          effectName: s.effect.name,
        );
    final paletteName = s.palette.name != 'Custom Palette' ? s.palette.name : null;
    if (paletteName != null) {
      ref.read(activePresetLabelProvider.notifier).setLabelWithFingerprint(paletteName, ref.read(wledStateProvider));
    } else {
      ref.read(activePresetLabelProvider.notifier).clear();
    }

    // Update refinement context
    ref.read(luminaSheetProvider.notifier).setPatternContext(
          {'wled': payload},
          null,
        );

    // Collapse panel
    state = state!.copyWith(isExpanded: false, clearFailure: true);
    return result;
  }

  /// Row 107: a zone chip names a zone; the payload goes to THAT zone's
  /// primary controller through its own routed repository (the same
  /// per-target repository the fan-out helper uses), so it works at home and
  /// away. The primary drives its DDP-synced members. "All Zones" is the
  /// selected controller, exactly as before.
  Future<WriteResult> _send(Map<String, dynamic> payload, ZoneInfo zone) async {
    final zoneIp = zone.id;
    if (zoneIp == null || zoneIp.isEmpty || zone.name == ZoneInfo.allZones.name) {
      if (ref.read(wledRepositoryProvider) == null) {
        return WriteResult.blocked(
            applyBlockedReason(ref.read) ?? kApplyBlockedFallback);
      }
      // #163: "All Zones" is the house — every participating channel.
      return ref.read(wledStateProvider.notifier).applyLuminaDesign(payload);
    }

    // Prefer the registered record for this address (it carries the id the
    // relay needs); fall back to a bare address on the home network.
    final registered = ref
        .read(linkedControllerTargetsProvider)
        .where((t) => t.ip == zoneIp)
        .firstOrNull;
    final target = registered ?? ControllerTarget(ip: zoneIp, name: zone.name);
    final repo = ref.read(controllerRepositoryProvider(target));
    if (repo == null) {
      return WriteResult.blocked(
          "Couldn't reach ${zone.name} from here. Connect to your home Wi-Fi "
          'or set up Remote Access for that controller.');
    }
    final ok = await repo.applyJson(payload);
    return WriteResult.fromBool(ok,
        onFailure: "Couldn't reach ${zone.name} — check that its controller "
            'is powered on and online.');
  }

  /// Called when a voice refinement returns an updated suggestion.
  void applyFromVoice(LuminaLightingSuggestion updated) {
    if (state == null) return;
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, ...updated.changedParams},
      clearFailure: true,
    );
  }

  /// Clear the adjustment session entirely.
  void clear() {
    state = null;
  }

  // -----------------------------------------------------------------------
  // WLED payload builder
  // -----------------------------------------------------------------------

  Map<String, dynamic> _buildPayload(LuminaLightingSuggestion s) {
    final bri = (s.brightness * 255).round().clamp(0, 255);

    final cols = s.colors.take(3).map((c) => rgbToRgbw(
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
        )).toList();
    if (cols.isEmpty) {
      cols.add(rgbToRgbw(255, 255, 255));
    }

    final rawSpeed = s.speed != null ? (s.speed! * 255).round() : 128;
    final speed = WledEffectsCatalog.getAdjustedSpeed(s.effect.id, rawSpeed);

    return {
      'on': true,
      'bri': bri,
      'seg': [
        {
          'fx': s.effect.id,
          'sx': speed,
          'col': cols,
          'pal': 5, // "Colors Only"
        },
      ],
    };
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global provider for the active adjustment session. `null` = no session.
final adjustmentStateProvider =
    NotifierProvider<AdjustmentStateNotifier, AdjustmentState?>(
  AdjustmentStateNotifier.new,
);
