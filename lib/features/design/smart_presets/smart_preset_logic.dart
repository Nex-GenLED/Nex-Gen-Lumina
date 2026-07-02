import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Design Studio Slice 3 — pure map→accent-spans compilation.
///
/// The base color is applied as the channel's normal solid segment state (via
/// the apply chokepoint). The ACCENTS returned here are channel-local
/// [PixelSpan] ranges over the mapped feature pixels, applied ON TOP via
/// [PerPixelWriter.applyPerPixel] (Slice 0) — WLED merges the successive `i`
/// write over the solid base. No per-feature WLED segments (that's Slice 4+).
///
/// All ranges are CHANNEL-LOCAL and clamped to the live `busLen`, so a STALE
/// map (segments beyond the current bus length) still applies best-effort.
/// Pure + deterministic.

/// Whether [segment] is targeted by [kind]'s accent.
bool _isAccentFeature(RooflineSegment s, SmartPresetKind kind) {
  switch (kind) {
    case SmartPresetKind.cornerAccents:
      return s.type == SegmentType.corner ||
          s.architecturalRole == ArchitecturalRole.corner;
    case SmartPresetKind.peakHighlights:
      return s.type == SegmentType.peak ||
          s.architecturalRole == ArchitecturalRole.peak;
    case SmartPresetKind.featureOutline:
      return s.type != SegmentType.run;
  }
}

/// Accent [PixelSpan]s for a single channel's [segments], clamped to [busLen].
///
/// [cornerSpread] widens corner accents by ±N pixels around the corner feature
/// (default 2) so a 1-px corner reads as a visible accent; other feature types
/// use their traced extent.
List<PixelSpan> accentSpansForChannel({
  required List<RooflineSegment> segments,
  required SmartPresetKind kind,
  required List<int> accentRgbw,
  required int busLen,
  int cornerSpread = 2,
}) {
  if (busLen <= 0) return const [];
  final maxIndex = busLen - 1;
  final spans = <PixelSpan>[];
  for (final s in segments) {
    if (!_isAccentFeature(s, kind)) continue;
    // Drop a feature that starts beyond the live bus length (stale map — the
    // roofline shrank). A partially-in-range feature is clamped below.
    if (s.startPixel > maxIndex) continue;

    final isCorner = s.type == SegmentType.corner ||
        s.architecturalRole == ArchitecturalRole.corner;
    final spread = isCorner ? cornerSpread : 0;

    final start = (s.startPixel - spread).clamp(0, maxIndex);
    final end = (s.endPixel + spread).clamp(0, maxIndex);
    if (end < start) continue;
    spans.add(PixelSpan(start: start, end: end, color: accentRgbw));
  }
  return spans;
}

/// Per-channel accent spans for the whole [config]. Channels with no matching
/// feature (or unmapped) get an empty list → base color only. [busLenByChannel]
/// provides device-truth `WledLedBus.len`; a channel absent from the map falls
/// back to the mapped segment extent.
Map<int, List<PixelSpan>> compileAccentSpans({
  required RooflineConfiguration config,
  required SmartPresetKind kind,
  required List<int> accentRgbw,
  required Map<int, int> busLenByChannel,
  int cornerSpread = 2,
}) {
  final out = <int, List<PixelSpan>>{};
  for (final ch in config.allChannelIndices) {
    final segs = config.segmentsForChannel(ch);
    final busLen = busLenByChannel[ch] ??
        segs.fold<int>(0, (m, s) => s.endPixel + 1 > m ? s.endPixel + 1 : m);
    out[ch] = accentSpansForChannel(
      segments: segs,
      kind: kind,
      accentRgbw: accentRgbw,
      busLen: busLen,
      cornerSpread: cornerSpread,
    );
  }
  return out;
}
