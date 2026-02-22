/// Rewrites a WLED payload's `seg` array so it targets only [channelIds].
///
/// If [channelIds] is empty, or the payload has no `seg` key, the payload is
/// returned unchanged (safe fallback). Otherwise the first segment object is
/// used as a template and replicated once per channel ID.
///
/// This is a pure function with no side effects — safe to call from any
/// provider or widget.
Map<String, dynamic> applyChannelFilter(
  Map<String, dynamic> payload,
  List<int> channelIds,
) {
  if (channelIds.isEmpty) return payload;

  final seg = payload['seg'];
  if (seg is! List || seg.isEmpty) return payload;

  // Use the first segment entry as a template.
  final template = Map<String, dynamic>.from(seg.first as Map);
  template.remove('id'); // strip hardcoded ID so each copy gets its own

  final expandedSegs = channelIds.map((id) {
    return <String, dynamic>{'id': id, ...template};
  }).toList();

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = expandedSegs;
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

    normalizedSegs.add(s);
  }

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = normalizedSegs;
  return result;
}
