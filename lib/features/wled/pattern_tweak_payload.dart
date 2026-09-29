// lib/features/wled/pattern_tweak_payload.dart
//
// THE shape of an ADJUSTMENT — a change to one or two fields of the look that
// is already playing (speed, intensity, grouping, spacing, colour sequence,
// effect) — as opposed to APPLYING a design.
//
// WHY THIS FILE EXISTS
// --------------------
// The Home Tune panel and the Explore adjustment sheet sent every slider move
// through `applyChannelFilter`. That function is the DESIGN-apply shape: it
// emits the full partition over the channel census, `{id, …look, on:true}` for
// each targeted channel and `{id, on:false}` for every other one. For a design
// that is right — a design scoped to channel 1 means "channel 2 is dark for
// this design". For a slider tweak it is wrong twice over:
//
//   • with the channel bar narrowed to channel 1, a speed or intensity drag
//     sent `{id: 1, on: false}` and switched channel 2 OFF — part of the house
//     went dark because the customer nudged a slider;
//   • it also stamped `on: true` on every targeted channel, so a tweak
//     re-lit a channel the customer had switched off with its power icon.
//
// The same happened for a channel left out of shows (participation), even
// with "All Channels" selected, because the effective channel list excludes it.
//
// THE RULE: an adjustment never changes any channel's power. It names the
// channels it adjusts, carries only the fields that changed, and says nothing
// about any other channel. No `on` — top level or per segment — and no bounds
// or orientation (those are provisioning's; the wire pin would strip them
// anyway).
//
// Pure Dart: no Flutter, no providers.

/// Fields an adjustment may never carry. `on` is power; the rest are geometry,
/// which only the provisioning door writes.
const Set<String> kAdjustmentForbiddenKeys = {
  'id',
  'on',
  'start',
  'stop',
  'rev',
  'mi',
  'of',
};

/// The `/json/state` body for an adjustment of [channelIds].
///
/// One `seg` entry per channel, `{id, …fields}`, in ascending id order. A
/// channel not in [channelIds] is not mentioned, so WLED leaves it exactly as
/// it is — lit or dark. Any forbidden key in [fields] is dropped.
///
/// Returns an empty `seg` list when [channelIds] is empty; callers must check
/// the gate first and never send that.
Map<String, dynamic> buildChannelTweakPayload(
  Map<String, dynamic> fields,
  Iterable<int> channelIds,
) {
  final look = <String, dynamic>{
    for (final e in fields.entries)
      if (!kAdjustmentForbiddenKeys.contains(e.key)) e.key: e.value,
  };
  final ids = channelIds.toSet().toList()..sort();
  return <String, dynamic>{
    'seg': [
      for (final id in ids) <String, dynamic>{'id': id, ...look},
    ],
  };
}

/// True when [payload] could change a channel's power: a top-level `on`, or
/// an `on` on any segment. Used by tests and by the adjustment senders as a
/// last guard.
bool payloadTouchesPower(Map<String, dynamic> payload) {
  if (payload.containsKey('on')) return true;
  final seg = payload['seg'];
  if (seg is List) {
    for (final s in seg) {
      if (s is Map && s.containsKey('on')) return true;
    }
  } else if (seg is Map && seg.containsKey('on')) {
    return true;
  }
  return false;
}
