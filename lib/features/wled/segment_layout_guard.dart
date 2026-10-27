// lib/features/wled/segment_layout_guard.dart
//
// TD-10 narrow fix (build 122, owner decision 2026-10-27).
//
// An apply never writes segment bounds (#89 / #95): its `seg` entries carry an
// id and a look, and the bounds belong to provisioning. That contract is right,
// and it has one hole: when the controller's layout has COLLAPSED (a restart
// with no boot preset leaves one factory segment over the whole strip; a
// preset saved while collapsed re-collapses it on every fire), a two-channel
// apply addresses `id: 1`, the firmware has no such segment and drops the
// entry, and only channel 1 changes while the app's preview shows both lit.
//
// The guard: before a multi-segment apply on the LAN, read the live layout; if
// it lacks a segment the apply addresses AND the controller's own buses say
// that segment should exist, re-provision the bus-derived bounds first (the
// same bounds-only write the connect-time geometry heal makes), then send the
// apply, which carries the look for every segment it addresses. Single-segment
// applies, an unreadable layout, an unreadable config and the relay path are
// left exactly as before: the guard repairs a KNOWN mismatch, never a guess.
//
// Pure Dart: every decision here is testable without a socket.

import 'device_channel.dart';

/// One segment's bounds as the guard reasons about them.
typedef SegmentBounds = ({int id, int start, int stop});

/// How old the poller's last `/json/state` read may be before the guard reads
/// the layout itself. The dashboard polls every 1.5 s, so in normal use the
/// hint is fresh and a multi-segment apply costs no extra read; a stale hint
/// (polls suppressed, app just resumed) is replaced by one fresh read rather
/// than trusted.
const Duration kLiveLayoutHintMaxAge = Duration(seconds: 5);

/// The segment ids a payload addresses: every `seg` entry carrying an int `id`.
/// Empty when the payload has no `seg` list or none of its entries name an id.
List<int> addressedSegmentIds(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  if (seg is! List) return const [];
  final out = <int>[];
  for (final s in seg) {
    if (s is Map && s['id'] is int) out.add(s['id'] as int);
  }
  return out;
}

/// The ids of the segments that EXIST in a `/json/state` read: entries with an
/// int `id` and `stop > start`. Null when the read has no usable `seg` list,
/// which the guard treats as "unknown — stand aside".
Set<int>? liveSegmentIds(Map<String, dynamic>? state) {
  final seg = state?['seg'];
  if (seg is! List) return null;
  final out = <int>{};
  for (final s in seg) {
    if (s is! Map) continue;
    final id = s['id'], start = s['start'], stop = s['stop'];
    if (id is int && start is int && stop is int && stop > start) out.add(id);
  }
  return out;
}

/// The bounds the controller's own buses define, one segment per bus.
List<SegmentBounds> expectedBoundsFromChannels(List<DeviceChannel> channels) =>
    [
      for (final c in channels)
        if (c.stop > c.start) (id: c.id, start: c.start, stop: c.stop),
    ];

/// True when the apply addresses a segment the live layout lacks AND the
/// bus-derived expectation has that segment — the one case the guard repairs.
/// False when everything addressed exists, when the live layout is unknown,
/// or when the buses themselves do not define the missing segment (then the
/// apply is wrong, not the layout, and the guard must not invent a segment).
bool needsLayoutRepairBeforeApply({
  required List<int> addressed,
  required Set<int>? live,
  required List<SegmentBounds> expected,
}) {
  if (addressed.length < 2 || live == null) return false;
  final expectedIds = {for (final e in expected) e.id};
  for (final id in addressed) {
    if (!live.contains(id) && expectedIds.contains(id)) return true;
  }
  return false;
}

/// The bounds-only re-provision body: ids with start/stop and nothing else, the
/// same shape the connect-time geometry heal writes.
Map<String, dynamic> geometryPayload(List<SegmentBounds> want) => {
      'seg': [
        for (final b in want) {'id': b.id, 'start': b.start, 'stop': b.stop},
      ],
    };
