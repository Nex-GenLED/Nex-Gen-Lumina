// lib/features/schedule/pattern_preset_fanout.dart
//
// Fan a single id-less design segment out over the controller's bus set
// before it is psaved as a schedule or lease preset.
//
// THE DEFECT THIS CLOSES (2026-11-02 read of +121, bench-free, source-verified
// on both sides). The Explore tuner hands a schedule ONE segment with no `id`
// (`selector_payload.dart` buildSelectorPayload). A live apply fans that out
// over the device's channels (`applyChannelFilter` / `expandForParticipation`),
// but the PRESET path does not: `scopePatternPayload` returns an unscoped
// payload unchanged, and `savePreset` adds no ids. WLED applies array element
// N to segment N (`json.cpp deserializeSegment`, `id = elem["id"] | it`), so
// the design lands on segment 0 only, and `psave` then snapshots every other
// segment as it happened to be (audit/U7_ABSENT_SEGMENT_PROBE.md). On a
// two-channel house the schedule fires on channel 1 and channel 2 shows a
// stale capture — dark, a previous look, or a frozen paint.
//
// THE RULE. Same template rule as `applyChannelFilter` and
// `scopePatternPayload`: one entry per bus id carrying the design, `on: true`
// per entry (a segment left `on:false` is not re-lit by root power), no
// bounds (#76 — a design payload never asserts geometry; the geometry gate
// and the healer own `start`/`stop`). Ids ONLY, not `sb:true`: a preset saved
// with bounds re-creates and re-bounds segments on every fire and deletes the
// rest through the `stop:0` stubs (U6 C5), which would make every schedule
// preset a geometry writer competing with the gate — and would bake a wrong
// layout durably if a save ever ran over a collapsed strip that the gate
// could not read.
//
// WHERE THE BUS SET COMES FROM. The caller passes the ids of
// `deviceChannelsFromConfig(cfg)` — the controller's own `hw.led.ins`, the
// same device truth the healer and the geometry gate use. Over the relay there
// is no cfg door, so the set is empty and the payload passes through exactly
// as before. Likewise a single-bus controller: nothing to fan.

/// Fan [payload] out over [busIds] when, and only when, it is the tuner's
/// single id-less design segment and the controller has two or more buses.
///
/// Returns [payload] UNCHANGED (same instance) when:
///   • [busIds] has fewer than two entries — unknown facts (relay, unreadable
///     cfg) or a single-bus controller: today's behaviour, byte for byte;
///   • `seg` is absent, empty, or has more than one entry — a top-level-only
///     payload, or a body some builder already shaped (a My Design's
///     per-channel ids, a scoped partition, the ladder);
///   • the one entry carries an `id` — a targeted apply;
///   • the one entry carries a per-pixel `i` — a picture is never fanned;
///   • the one entry states no design (no `fx` and no `col`).
///
/// Otherwise every bus id gets `{id, ...template, on: true}` in ascending id
/// order, with `start`/`stop`/`on` stripped from the template.
Map<String, dynamic> fanOutPatternPayloadToBuses(
  Map<String, dynamic> payload,
  Iterable<int> busIds,
) {
  final ids = busIds.toSet().toList()..sort();
  if (ids.length < 2) return payload;

  // ROOFLINE SLICE 2 — an API-command preset body (`o:true`, a painted
  // design scheduled nightly) is built FINAL by design_api_preset.dart: one
  // entry per bus with its own bounds and paint. It is never fanned, whatever
  // its segment count or keys. Explicit, rather than relying on the per-pixel
  // and several-entries rules below, so a one-bus body with no `i` (a design
  // that leaves its only bus dark) cannot slip through either.
  if (payload['o'] == true) return payload;

  final seg = payload['seg'];
  if (seg is! List || seg.length != 1) return payload;
  final first = seg.first;
  if (first is! Map) return payload;
  if (first.containsKey('id')) return payload;
  if (first.containsKey('i')) return payload;
  if (!first.containsKey('fx') && !first.containsKey('col')) return payload;

  final template = Map<String, dynamic>.from(first)
    ..remove('start')
    ..remove('stop')
    ..remove('on');

  final out = Map<String, dynamic>.from(payload);
  out['seg'] = [
    for (final id in ids) <String, dynamic>{'id': id, ...template, 'on': true},
  ];
  return out;
}
