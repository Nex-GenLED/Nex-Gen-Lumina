// lib/features/neighborhood/sync_per_pixel_guard.dart
//
// Roofline slice 1, item 4 — the Sync side of the per-pixel block. Pure:
// reads the command and its assignments only.
//
// Today no Sync picker can produce a per-pixel assignment (the picker
// excludes `my_designs` by node id, and the fan-out builder reads colours
// and an effect, never a payload). The guard exists so that stays true when
// a design picker is added: a `SyncPatternAssignment.wledPayload` carrying
// `seg[].i`, on the global pattern or on any member override, refuses the
// Start before anything fires. The server's fan-out whitelist drops `i`
// anyway, which is exactly why this must refuse rather than send.

import 'package:nexgen_command/features/design/per_pixel_payload_guard.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';

/// True when [a] carries a per-pixel payload.
bool syncAssignmentCarriesPerPixel(SyncPatternAssignment a) =>
    payloadCarriesPerPixel(a.wledPayload);

/// True when any pattern [command] would deliver — the global pattern or a
/// member override — carries a per-pixel payload.
bool syncCommandCarriesPerPixel(SyncCommand command) {
  final overrides = command.memberPatternOverrides;
  if (overrides != null) {
    for (final a in overrides.values) {
      if (syncAssignmentCarriesPerPixel(a)) return true;
    }
  }
  return syncAssignmentCarriesPerPixel(command.getPatternForMember(''));
}

/// The Start failure reason for a per-pixel refusal (see
/// sync_start_feedback.dart for the sentence).
const String kSyncPerPixelFailureReason = 'per_pixel_design';
