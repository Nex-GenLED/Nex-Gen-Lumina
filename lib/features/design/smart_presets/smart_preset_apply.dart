import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_logic.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Outcome of applying a smart preset.
enum SmartPresetApplyResult {
  /// Applied cleanly.
  applied,

  /// No pixel map for the active controller (or all channels skipped).
  noMap,

  /// Applied best-effort, but at least one channel's map is stale (drift vs
  /// live bus length) — surface the "roofline changed" prompt.
  staleApplied,

  /// Couldn't reach the device / no channels selected.
  error,
}

/// Applies [preset] to the active controller: BASE color through the normal
/// apply chokepoint (participation + channel handling via [applyChannelFilter]),
/// then ACCENT spans over the mapped features through [PerPixelWriter.applyPerPixel]
/// (explicit per-channel targeting — bypasses channel fan-out; Slice 0 made this
/// structural). Static frames (`fx:0`); NO WLED preset (psave) writes —
/// Firestore stays the design source of truth.
Future<SmartPresetApplyResult> applySmartPreset(
  WidgetRef ref, {
  required SmartPreset preset,
  required List<int> baseRgbw,
  required List<int> accentRgbw,
  int cornerSpread = 2,
}) async {
  final config = ref.read(currentRooflineConfigProvider).valueOrNull;
  if (config == null || config.segments.isEmpty) {
    return SmartPresetApplyResult.noMap;
  }

  final deviceChannels = ref.read(deviceChannelsProvider);
  final busLen = <int, int>{
    for (final c in deviceChannels) c.id: c.stop - c.start,
  };
  final accentsByChannel = compileAccentSpans(
    config: config,
    kind: preset.kind,
    accentRgbw: accentRgbw,
    busLenByChannel: busLen,
    cornerSpread: cornerSpread,
  );

  // Shared spine: base solid + per-channel accent `i` spans. Empty effective
  // set / unreachable device → false (U1 gate), exactly like other applies.
  final ok = await applyBaseAndSpans(
    ref,
    baseRgbw: baseRgbw,
    spansByChannel: accentsByChannel,
    label: preset.name,
  );
  if (!ok) return SmartPresetApplyResult.error;

  // Stale-map signal (still applied above — best effort, ranges clamped).
  final staleness = ref.read(pixelMapStalenessProvider);
  final anyStale = staleness.values.any((v) => v);
  return anyStale
      ? SmartPresetApplyResult.staleApplied
      : SmartPresetApplyResult.applied;
}
