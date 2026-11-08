// lib/features/design/per_pixel_payload_guard.dart
//
// Roofline slice 1, item 4 — per-pixel designs are BLOCKED from Neighborhood
// Sync fan-out and from Game Day base designs (owner decision D5, first
// release).
//
// Both destinations replay a stored WLED body unattended, away from the
// per-pixel spine: Game Day fires `saved_design_payload` through the bridge
// or the LAN as one `applyJson` (and the server passes it raw, with no key
// filter); Sync fan-out hands the payload to the server function, whose key
// whitelist drops `i` and keeps the base `col`, so a closed-app neighbour
// would show the design's BLACK BASE under the design's name. On the device
// a per-pixel body freezes the segment, and the post-game revert cannot
// clear what it never captured (item 3). Neither destination can carry a
// painted picture today; refuse plainly at the write, not only in the picker
// (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §B.4, §F "a pure test should
// assert the refusal at the builder, not only in the picker").
//
// Pure Dart: the predicate reads the wire shape only (`seg[].i`), which is
// the one thing every per-pixel payload has and no effect payload does.

/// True when [payload] carries per-pixel data: any `seg` entry with an `i`
/// key. Null, a non-map `seg`, or a payload without `seg` → false.
bool payloadCarriesPerPixel(Map<String, dynamic>? payload) {
  if (payload == null) return false;
  final seg = payload['seg'];
  if (seg is Map) return seg.containsKey('i');
  if (seg is! List) return false;
  for (final s in seg) {
    if (s is Map && s.containsKey('i')) return true;
  }
  return false;
}

/// Thrown by a destination's write when handed a per-pixel payload. The
/// [message] is customer-readable; show it as-is.
class PerPixelDesignRefused implements Exception {
  const PerPixelDesignRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Game Day base design: what the customer is told.
String perPixelGameDayRefusedMessage(String designName) =>
    '"$designName" is a painted design, so it can\'t be the Game Day base '
    'design. Game Day replays its design through your controller on its own, '
    'and that path carries colours and effects, not a painted picture. Choose '
    'a colour-and-effect design for Game Day instead.';

/// Neighborhood Sync: what the host is told at Start.
const String kPerPixelSyncRefusedMessage =
    'A painted design can\'t be shared through Neighborhood Sync. Sync sends '
    'colours and effects to your neighbours\' controllers, not a painted '
    'picture. Choose a colour-and-effect design and start again. Nothing was '
    'sent.';

/// The library picker's refusal, by destination. The schedule sentence is
/// the +63 one (a preset stores no pixels); Game Day gets its own.
String perPixelPickerRefusalMessage(String designName, String? destination) {
  if (destination != null && destination.toLowerCase() == 'game day') {
    return perPixelGameDayRefusedMessage(designName);
  }
  return '"$designName" is a per-pixel design. Those can\'t be scheduled '
      'yet — your controller\'s timers can only replay colours and effects, '
      'not a painted picture. You can still apply it any time from My Designs.';
}
