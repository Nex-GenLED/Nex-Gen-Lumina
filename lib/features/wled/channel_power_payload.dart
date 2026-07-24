// Pure-Dart (no flutter / dart:ui) per-channel power payload builder (P1-43),
// extracted from wled_payload_utils.dart so the bench/ CLI tests the ACTUAL
// builder. wled_payload_utils.dart re-exports it, so importers are unaffected.

import 'package:nexgen_command/features/wled/device_channel.dart';

/// Build the `/json/state` payload for a PER-CHANNEL power change (P1-43) — the
/// additive seg-scoped counterpart to the master `WledNotifier.togglePower`
/// path. Pure + testable; the caller (`WledNotifier.setChannelPower`) supplies
/// live master + per-seg state read from the device (never cached UI state).
///
/// Policy (decided 2026-07-23):
///  1. OFF a channel while others stay lit → `{"seg":[{id,on:false}]}`, NO
///     top-level `on` (must not touch master).
///  2. OFF the LAST lit channel → master follows: `{"on":false}` (state must not
///     lie; scheduled ON-presets re-assert master via `ib`, so schedule-safe).
///  3. ON a channel while master is OFF → ONE post:
///     `{"on":true,"seg":[explicit on/off for EVERY channel — target on, all
///     others off]}`. Master-on alone would relight the whole house.
///  4. ON a channel while master is already ON → `{"seg":[{id,on:true}]}` only.
///
/// [litChannelIds] = channels whose segment is currently `on` (from live
/// `/json/state` seg[]). [channels] supplies `start`/`stop` bounds AND the full
/// channel set for case 3's enumeration. When [withBounds] is false (a stale or
/// failed config refresh — P1-42), seg entries are id-only: WLED applies them to
/// the existing segments without touching bounds, so a physically-resized
/// channel is never re-bounded with stale start/stop.
Map<String, dynamic> buildChannelPowerPayload({
  required int channelId,
  required bool on,
  required bool masterOn,
  required Set<int> litChannelIds,
  required List<DeviceChannel> channels,
  bool withBounds = true,
}) {
  Map<String, dynamic> seg(int id, bool segOn) {
    final m = <String, dynamic>{'id': id, 'on': segOn};
    if (withBounds) {
      for (final ch in channels) {
        if (ch.id == id) {
          m['start'] = ch.start;
          m['stop'] = ch.stop;
          break;
        }
      }
    }
    return m;
  }

  if (!on) {
    // Would anything remain lit after this channel goes off?
    final remainingLit = litChannelIds.where((id) => id != channelId).toSet();
    if (remainingLit.isEmpty) {
      // Case 2 — last lit channel: master follows so state doesn't lie.
      return <String, dynamic>{'on': false};
    }
    // Case 1 — others still lit: seg-scoped off, master untouched.
    return <String, dynamic>{
      'seg': [seg(channelId, false)],
    };
  }

  if (masterOn) {
    // Case 4 — master already on: light just this channel.
    return <String, dynamic>{
      'seg': [seg(channelId, true)],
    };
  }

  // Case 3 — master off: ONE post, master on + EVERY channel explicit (target
  // on, all others off) so master-on doesn't relight the whole house. The
  // target is always represented even if [channels] is stale/partial.
  final ids = <int>{for (final ch in channels) ch.id}..add(channelId);
  final sorted = ids.toList()..sort();
  return <String, dynamic>{
    'on': true,
    'seg': [for (final id in sorted) seg(id, id == channelId)],
  };
}
