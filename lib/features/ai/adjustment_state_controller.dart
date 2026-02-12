import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_providers.dart' show activePresetLabelProvider;
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

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

  const AdjustmentState({
    required this.originalSuggestion,
    required this.currentSuggestion,
    this.isExpanded = true,
    this.userChangedParams = const {},
  });

  AdjustmentState copyWith({
    LuminaLightingSuggestion? currentSuggestion,
    bool? isExpanded,
    Set<String>? userChangedParams,
  }) {
    return AdjustmentState(
      originalSuggestion: originalSuggestion,
      currentSuggestion: currentSuggestion ?? this.currentSuggestion,
      isExpanded: isExpanded ?? this.isExpanded,
      userChangedParams: userChangedParams ?? this.userChangedParams,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the active adjustment session. `null` means no adjustment in progress.
class AdjustmentStateNotifier extends Notifier<AdjustmentState?> {
  @override
  AdjustmentState? build() => null;

  /// Start a new adjustment session.
  void beginAdjustment(LuminaLightingSuggestion suggestion) {
    state = AdjustmentState(
      originalSuggestion: suggestion,
      currentSuggestion: suggestion,
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
    );
  }

  void updateZone(ZoneInfo zone) {
    if (state == null) return;
    final updated = state!.currentSuggestion.copyWithChanges(zone: zone);
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, 'zone'},
    );
  }

  // -----------------------------------------------------------------------
  // Apply & voice sync
  // -----------------------------------------------------------------------

  /// Build a WLED JSON payload and send to the device.
  Future<void> applyToDevice() async {
    if (state == null) return;
    final s = state!.currentSuggestion;

    final payload = _buildPayload(s);
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    try {
      final ok = await repo.applyJson(payload);
      if (ok) {
        ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
              colorSequence: s.colors,
              colorNames: s.palette.colorNames,
              effectName: s.effect.name,
            );
        ref.read(activePresetLabelProvider.notifier).state =
            s.palette.name != 'Custom Palette' ? s.palette.name : 'Lumina Pattern';

        // Update refinement context
        ref.read(luminaSheetProvider.notifier).setPatternContext(
              {'wled': payload},
              null,
            );
      }
    } catch (e) {
      debugPrint('Adjustment applyToDevice failed: $e');
    }

    // Collapse panel
    state = state!.copyWith(isExpanded: false);
  }

  /// Called when a voice refinement returns an updated suggestion.
  void applyFromVoice(LuminaLightingSuggestion updated) {
    if (state == null) return;
    state = state!.copyWith(
      currentSuggestion: updated,
      userChangedParams: {...state!.userChangedParams, ...updated.changedParams},
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

    final cols = s.colors.take(3).map((c) => [
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
          0,
        ]).toList();
    if (cols.isEmpty) {
      cols.add([255, 255, 255, 0]);
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
