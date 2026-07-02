import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_logic.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
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
  final repo = ref.read(wledRepositoryProvider);
  if (repo == null) return SmartPresetApplyResult.error;

  final config = ref.read(currentRooflineConfigProvider).valueOrNull;
  if (config == null || config.segments.isEmpty) {
    return SmartPresetApplyResult.noMap;
  }

  final deviceChannels = ref.read(deviceChannelsProvider);
  final effective = ref.read(effectiveChannelIdsProvider);
  // Empty effective set = the U1 gate (user deselected all) — no-op, exactly
  // like every other dashboard apply.
  if (effective.isEmpty) return SmartPresetApplyResult.error;
  final effectiveSet = effective.toSet();

  // 1. BASE — solid color across the effective channels, via the chokepoint.
  var basePayload = <String, dynamic>{
    'on': true,
    'seg': [
      {
        'fx': 0,
        'sx': 128,
        'ix': 128,
        'pal': 0,
        'col': [baseRgbw],
      }
    ],
  };
  basePayload = applyChannelFilter(basePayload, effective, deviceChannels);
  await repo.applyJson(basePayload);

  // 2. ACCENTS — per-channel `i` overlay on mapped channels within the
  // effective set. Unmapped channels (and channels with no matching feature)
  // simply keep the base color.
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
  if (repo is PerPixelWriter) {
    final writer = repo as PerPixelWriter;
    for (final entry in accentsByChannel.entries) {
      if (entry.value.isEmpty) continue;
      if (!effectiveSet.contains(entry.key)) continue;
      await writer.applyPerPixel(segmentId: entry.key, spans: entry.value);
    }
  }

  // 3. Label the active look so the dashboard names it.
  ref
      .read(activePresetLabelProvider.notifier)
      .setLabelWithFingerprint(preset.name, ref.read(wledStateProvider));

  // 4. Stale-map signal (still applied above — best effort, ranges clamped).
  final staleness = ref.read(pixelMapStalenessProvider);
  final anyStale = staleness.values.any((v) => v);
  return anyStale
      ? SmartPresetApplyResult.staleApplied
      : SmartPresetApplyResult.applied;
}
