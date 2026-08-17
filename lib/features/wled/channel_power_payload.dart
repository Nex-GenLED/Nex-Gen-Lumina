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
/// `/json/state` seg[]). [channels] supplies the full channel SET for case 3's
/// enumeration — and nothing else.
///
/// NEVER EMITS BOUNDS (#95, 2026-08-17). This builder used to stamp
/// `start`/`stop` from [channels] whenever a config refresh had succeeded
/// (`withBounds`). That is geometry, and **an apply never writes geometry** —
/// bounds are provisioning's, sourced from the hardware buses. It is the same
/// rule #89 applied to `applyChannelFilter` and #76 applied to the seven design
/// builders; this builder was simply not in either census, which is the third
/// time a geometry sweep has under-counted its own family (#88's lesson: an
/// emitter census must be a grep of the FIELD NAMES across `lib/`, not a walk of
/// the builders you already know about).
///
/// The old `withBounds:false` path — id-only seg entries — is now the ONLY
/// path, so a physically-resized channel can never be re-bounded by a power tap
/// with a stale channel map. WLED applies id-only seg entries to the existing
/// segments, leaving their ranges untouched.
Map<String, dynamic> buildChannelPowerPayload({
  required int channelId,
  required bool on,
  required bool masterOn,
  required Set<int> litChannelIds,
  required List<DeviceChannel> channels,
}) {
  // id + on ONLY. No start/stop, no rev/mi/of, no grp/spc — a power change
  // states power and states nothing else.
  Map<String, dynamic> seg(int id, bool segOn) =>
      <String, dynamic>{'id': id, 'on': segOn};

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
