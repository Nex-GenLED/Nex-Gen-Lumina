import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/utils/rgbw_validation.dart';

/// Rewrites a WLED payload's `seg` array so it targets only [channelIds].
///
/// If [channelIds] is empty, or the payload has no `seg` key, the payload is
/// returned unchanged (safe fallback). Otherwise the first segment object is
/// used as a template and replicated once per channel ID.
///
/// When [channels] is provided, each segment entry gets `start`/`stop` values
/// from the corresponding hardware bus, so WLED targets the correct LED range.
///
/// This is a pure function with no side effects — safe to call from any
/// provider or widget.
Map<String, dynamic> applyChannelFilter(
  Map<String, dynamic> payload,
  List<int> channelIds, [
  List<DeviceChannel> channels = const [],
]) {
  if (channelIds.isEmpty) return payload;

  final seg = payload['seg'];
  if (seg is! List || seg.isEmpty) return payload;

  // Use the first segment entry as a template.
  final template = Map<String, dynamic>.from(seg.first as Map);
  template.remove('id'); // strip hardcoded ID so each copy gets its own
  template.remove('start');
  template.remove('stop');

  final expandedSegs = channelIds.map((id) {
    final s = <String, dynamic>{'id': id, ...template};
    // Look up bus range — set start/stop so WLED targets the correct LEDs
    for (final ch in channels) {
      if (ch.id == id) {
        s['start'] = ch.start;
        s['stop'] = ch.stop;
        break;
      }
    }
    return s;
  }).toList();

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = expandedSegs;
  debugPrint('🎯 applyChannelFilter: targeting channels $channelIds (${expandedSegs.length} segs)');
  return result;
}

/// Normalizes a WLED JSON API payload to prevent segment state carry-over.
///
/// WLED only updates fields explicitly included in a POST /json/state payload.
/// When switching patterns, omitting `grp`, `spc`, and `of` causes the previous
/// pattern's grouping/spacing/offset to persist, producing visual glitches.
///
/// This function inspects each segment object in the `seg` array:
/// - If the segment contains `fx` (effect ID), it is a full pattern application.
///   Missing `grp`, `spc`, and `of` fields are set to their WLED defaults (1, 0, 0).
/// - If the segment does NOT contain `fx`, it is a partial adjustment (e.g., a
///   slider changing speed/intensity) and is left untouched.
///
/// Additionally normalizes legacy key names: `gp` -> `grp`, `sp` -> `spc`.
///
/// The input map may be `const` (immutable), so this always returns a new map.
Map<String, dynamic> normalizeWledPayload(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  if (seg is! List || seg.isEmpty) {
    return Map<String, dynamic>.from(payload);
  }

  final normalizedSegs = <Map<String, dynamic>>[];

  for (final raw in seg) {
    if (raw is! Map) {
      normalizedSegs.add(Map<String, dynamic>.from(raw as Map));
      continue;
    }

    final s = Map<String, dynamic>.from(raw);

    // Legacy key normalization (always, regardless of fx presence)
    if (s.containsKey('gp') && !s.containsKey('grp')) {
      s['grp'] = s.remove('gp');
    }
    if (s.containsKey('sp') && !s.containsKey('spc')) {
      s['spc'] = s.remove('sp');
    }

    // Default injection: only for full pattern applications (has fx)
    if (s.containsKey('fx')) {
      s.putIfAbsent('grp', () => 1);
      s.putIfAbsent('spc', () => 0);
      s.putIfAbsent('of', () => 0);
    }

    // RGBW validation: ensure all color arrays have 4 channels [R, G, B, W]
    final col = s['col'];
    if (col is List && col.isNotEmpty) {
      s['col'] = validateRgbwList(col, source: 'normalizeWledPayload');
    }

    // Also validate per-pixel 'i' arrays
    final iArray = s['i'];
    if (iArray is List) {
      for (int j = 0; j < iArray.length; j++) {
        if (iArray[j] is List) {
          iArray[j] = validateRgbw(iArray[j] as List, source: 'normalizeWledPayload i[$j]');
        }
      }
    }

    normalizedSegs.add(s);
  }

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = normalizedSegs;
  return result;
}

/// Builds a WLED `seg` array from a [RooflineConfiguration] with per-channel entries.
///
/// Each channel in the configuration becomes one WLED segment entry with the
/// correct `start`/`stop` LED ranges derived from the segments assigned to that
/// channel. The [template] payload provides default values for `fx`, `col`,
/// `sx`, `ix`, etc.
///
/// Segments within the same channel that are not physically connected
/// (`isConnectedToPrevious: false`) are still sequential in the payload —
/// the physical gap is a wiring gap, not a data gap.
///
/// If [channelOverrides] is provided, per-channel fx/color overrides are applied.
///
/// Returns a payload map with a `seg` array ready to POST to `/json/state`.
Map<String, dynamic> buildPayloadFromRooflineConfig(
  RooflineConfiguration config,
  Map<String, dynamic> template, {
  List<DeviceChannel> hardwareChannels = const [],
  Map<int, Map<String, dynamic>>? channelOverrides,
}) {
  final segArray = <Map<String, dynamic>>[];
  final channelCount = config.effectiveTotalChannelCount;

  for (int ch = 0; ch < channelCount; ch++) {
    final channelSegments = config.segmentsForChannel(ch);
    if (channelSegments.isEmpty) continue;

    // Calculate LED range for this channel from its segments
    final startPixel = channelSegments.first.startPixel;
    final endPixel = channelSegments.last.startPixel + channelSegments.last.pixelCount;

    // Try to find matching hardware bus for start/stop
    int? hwStart;
    int? hwStop;
    for (final hwCh in hardwareChannels) {
      if (hwCh.id == ch) {
        hwStart = hwCh.start;
        hwStop = hwCh.stop;
        break;
      }
    }

    // Build segment entry from template
    final segEntry = <String, dynamic>{
      'id': ch,
      ...Map<String, dynamic>.from(template['seg'] is List && (template['seg'] as List).isNotEmpty
          ? (template['seg'] as List).first as Map
          : template),
    };

    // Set LED range (prefer hardware bus range, fall back to config)
    segEntry['start'] = hwStart ?? startPixel;
    segEntry['stop'] = hwStop ?? endPixel;

    // Remove keys that shouldn't be in segment entries
    segEntry.remove('on');
    segEntry.remove('bri');
    segEntry.remove('transition');

    // Apply per-channel overrides if present
    if (channelOverrides != null && channelOverrides.containsKey(ch)) {
      segEntry.addAll(channelOverrides[ch]!);
    }

    segArray.add(segEntry);
  }

  if (segArray.isEmpty) return template;

  final result = Map<String, dynamic>.from(template);
  result['seg'] = segArray;
  // Remove top-level seg template if it exists
  return result;
}
