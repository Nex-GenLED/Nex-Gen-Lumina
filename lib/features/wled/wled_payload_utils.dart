import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/utils/rgbw_validation.dart';

/// Guarantees a color array is a 4-channel `[R, G, B, W]` list with W explicitly
/// set. Used by sports team and holiday color paths to prevent WLED's W-channel
/// auto-calculation from washing dark branded colors (e.g. Chiefs red
/// `[227, 24, 55]`) into pink on RGBW strips.
///
/// - 4-channel input: clamped to 0–255 and returned as-is.
/// - 3-channel input: clamped and W=0 is appended (no auto-white extraction).
/// - Anything else: returns `[0, 0, 0, 0]` to fail safe.
///
/// This is the canonical wrapper any code path that produces a `col` entry from
/// a team or holiday brand color should funnel through.
List<int> safeRGBW(List<int> color) {
  if (color.length == 4) {
    return [
      color[0].clamp(0, 255),
      color[1].clamp(0, 255),
      color[2].clamp(0, 255),
      color[3].clamp(0, 255),
    ];
  }
  if (color.length == 3) {
    return [
      color[0].clamp(0, 255),
      color[1].clamp(0, 255),
      color[2].clamp(0, 255),
      0, // Explicit W:0 — prevents WLED auto white-channel bleed
    ];
  }
  return [0, 0, 0, 0];
}

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

/// Builds the per-channel `seg[]` array for a participation-scoped apply
/// (Neighborhood Sync / Game Day). The SINGLE shared shape used by every
/// sync + game-day apply site — both foreground (`_executePattern`,
/// `_buildWledPayload`) and background (`_buildPatternPayload`,
/// `_buildBasePayload` in Bundle 4). Keep it that way: divergence between
/// sites is what makes audit #4-class bugs happen.
///
/// Contract (locked, validated by hardware probe on 192.168.1.250):
/// - One seg entry per participating channel id.
/// - Each entry sets `'on': true` per segment. Required: a segment left
///   in `on:false` is NOT re-lit by a top-level `on:true` — the receiver
///   silently ignores the off segment. Per-seg `'on': true` is the
///   confirmed fix for the channel-2-dark class of bug.
/// - No `start` / `stop` — WLED retains the install-time ranges set by
///   `wled_config_pusher`. Sending them would risk re-introducing the
///   Item #82 wrong-range stomp.
/// - No `rev` — that's a separate bundle (the slot is reserved here so
///   when rev lands it's added in ONE place, not four).
/// - Non-participating channels are OMITTED, not turned off. A patio
///   left on by the user for their own purposes stays on; the show only
///   touches the channels the user opted in.
/// - Empty `participatingChannelIds` → empty list. Callers MUST treat
///   that as "skip the apply entirely" (do not POST an empty seg array).
///
/// `colorSlots` is passed verbatim — the caller is responsible for the
/// RGBW shape (use [safeRGBW] for team / holiday colors). No deep-copy:
/// `colorSlots` should be treated as immutable by the caller after this
/// call.
List<Map<String, dynamic>> buildParticipatingSegArray({
  required List<int> participatingChannelIds,
  required int effectId,
  required int speed,
  required int intensity,
  required List<List<int>> colorSlots,
}) {
  return [
    for (final ch in participatingChannelIds)
      <String, dynamic>{
        'id': ch,
        'on': true,
        'fx': effectId,
        'sx': speed,
        'ix': intensity,
        'col': colorSlots,
      },
  ];
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

