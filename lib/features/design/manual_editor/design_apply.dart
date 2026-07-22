import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Design Studio Slice 4 — the SHARED per-pixel apply spine used by the smart
/// presets (Slice 3), the manual editor, and the AI studio's "Apply to Lights"
/// (#86). One implementation, three call sites.
///
/// Transport (audit-recommended, structural since Slice 0): a solid BASE across
/// the effective channels via the normal chokepoint (applyChannelFilter →
/// applyJson), then per-channel ACCENT/paint spans via applyPerPixel (segmentId
/// == channelIndex; bypasses channel fan-out). Static `fx:0` frames; NO WLED
/// preset writes — Firestore stays the design source of truth.

enum DesignApplyResult { applied, noMap, staleApplied, error }

/// Base solid + per-channel `i` spans. Returns false when the device is
/// unreachable or the effective-channel set is empty (the U1 gate). Applies
/// spans only for channels in the effective set. Sets [label] on success.
Future<bool> applyBaseAndSpans(
  WidgetRef ref, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
}) async {
  final repo = ref.read(wledRepositoryProvider);
  if (repo == null) return false;

  final deviceChannels = ref.read(deviceChannelsProvider);
  final effective = ref.read(effectiveChannelIdsProvider);
  if (effective.isEmpty) return false;
  final effectiveSet = effective.toSet();

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

  if (repo is PerPixelWriter) {
    final writer = repo as PerPixelWriter;
    for (final entry in spansByChannel.entries) {
      if (entry.value.isEmpty || !effectiveSet.contains(entry.key)) continue;
      await writer.applyPerPixel(segmentId: entry.key, spans: entry.value);
    }
  }

  if (label != null) {
    ref
        .read(activePresetLabelProvider.notifier)
        .setLabelWithFingerprint(label, ref.read(wledStateProvider));
  }
  return true;
}

/// Channel-local [LedColorGroup]s → [PixelSpan]s (RGBW-normalized). RGB-only
/// groups get W=0 via [rgbToRgbw] (forceZeroWhite) — closing the "RGB-only,
/// W dropped" #86 fidelity gap.
List<PixelSpan> ledColorGroupsToSpans(List<LedColorGroup> groups) {
  return [
    for (final g in groups)
      PixelSpan(start: g.startLed, end: g.endLed, color: _rgbw(g.color)),
  ];
}

List<int> _rgbw(List<int> c) {
  if (c.length >= 4) {
    return [c[0], c[1], c[2], c[3]];
  }
  if (c.length == 3) {
    return rgbToRgbw(c[0], c[1], c[2], forceZeroWhite: true);
  }
  return const [0, 0, 0, 0];
}

/// A [CustomDesign]'s per-channel color groups → per-channel spans, keyed by
/// each [ChannelDesign.channelId] (the WLED segment id). Groups are already
/// channel-local (reconciled at save time), so they map straight to
/// per-segment `i` writes — this is the per-pixel path that fixes #86's
/// "single whole-roofline seg vs multi-bus split" concern.
Map<int, List<PixelSpan>> customDesignToSpans(CustomDesign design) {
  final out = <int, List<PixelSpan>>{};
  for (final ch in design.channels) {
    if (!ch.included) continue;
    final spans = ledColorGroupsToSpans(ch.colorGroups);
    if (spans.isNotEmpty) out[ch.channelId] = spans;
  }
  return out;
}

/// Applies a full [CustomDesign] via the shared per-pixel spine. Used by BOTH
/// the manual editor's "Apply to Lights" and the AI studio's #86 button.
///
/// Renders the design's color layout as a STATIC per-pixel frame (base black +
/// per-channel `i` spans). This is faithful for every manual design and for AI
/// STATIC designs; an AI design carrying a motion effect renders as its static
/// color layout via this path (animated features are the post-build consumer
/// iv — out of Slice-4 scope). Colors are RGBW-normalized; per-segment
/// targeting is multi-bus-correct — the three #86 fidelity concerns resolved.
Future<DesignApplyResult> applyCustomDesignToLights(
  WidgetRef ref,
  CustomDesign design,
) async {
  final spans = customDesignToSpans(design);
  if (spans.isEmpty) return DesignApplyResult.noMap;
  final ok = await applyBaseAndSpans(
    ref,
    baseRgbw: const [0, 0, 0, 0], // groups define the lit picture
    spansByChannel: spans,
    label: design.name,
  );
  return ok ? DesignApplyResult.applied : DesignApplyResult.error;
}
