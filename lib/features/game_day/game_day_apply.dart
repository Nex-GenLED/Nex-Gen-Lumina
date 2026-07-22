// lib/features/game_day/game_day_apply.dart
//
// Shared "apply a Path 1 Game Day config to the device" helper. Both
// the Path 1 setup screen's _activateNow button AND the Path 2 confirm
// screen's "Light it Up Now" button call this — they must produce the
// SAME WLED payload and route through the SAME apply chokepoint so the
// participation hardware probe's PASS holds across both call sites.
//
// Decision 2 (Phase 2 brief): the apply path MUST go through the
// applyJson chokepoint (now via applyPayloadWithLabel) so the
// participation cache is honored. Building a payload here from the
// Path 1 config is fine — applyPayloadWithLabel adds the seg-range
// participation filter on top of whatever payload we pass.
//
// The callback typedef [ApplyPayloadWithLabelCall] mirrors
// [WledNotifier.applyPayloadWithLabel] exactly so the helper is
// Riverpod-free and the tests can inject a fake.

import 'dart:ui' show Color;

import '../autopilot/game_day_autopilot_config.dart';
import '../wled/wled_payload_utils.dart' show applyChannelFilter;
import '../wled/zone_providers.dart' show DeviceChannel;

/// Shape of [WledNotifier.applyPayloadWithLabel], lifted to a top-
/// level typedef so this helper does not import the notifier.
typedef ApplyPayloadWithLabelCall = Future<bool> Function(
  Map<String, dynamic> payload, {
  required String? labelHint,
});

/// Apply a Path 1 [GameDayAutopilotConfig] to the device.
///
/// Builds the WLED payload from the config (or uses the user's
/// savedDesignPayload when present) and routes through
/// [applyPayloadWithLabel] with `'${config.shortTeamName} Game Day'`
/// as the persistent label hint so Now Playing reads correctly.
///
/// [participatingChannels] is the effective channel-id list
/// (`effectiveChannelIdsProvider`) and [deviceChannels] the hardware-bus
/// channel list (`deviceChannelsProvider`). Both callers pass them in so
/// this helper stays Riverpod-free while owning the SINGLE multi-channel
/// payload build — neither call site can drift on channel targeting.
///
/// Returns the underlying [applyPayloadWithLabel] result: true on
/// successful device write, false otherwise. Returns false WITHOUT
/// applying when [participatingChannels] is empty (U1 gate — see below).
Future<bool> applyGameDayConfigToDevice({
  required ApplyPayloadWithLabelCall applyPayloadWithLabel,
  required GameDayAutopilotConfig config,
  required List<int> participatingChannels,
  required List<DeviceChannel> deviceChannels,
}) async {
  // U1 empty-gate. `effectiveChannelIdsProvider` returns [] until the
  // hardware buses load (or when participation gates everything out), so an
  // empty list means there is nothing to target — bail rather than POST a
  // payload that can't be aimed. Mirrors applySavedDesign
  // (apply_saved_design.dart:50-54).
  if (participatingChannels.isEmpty) return false;

  final primary = Color(config.primaryColorValue);
  final secondary = Color(config.secondaryColorValue);
  final basePayload = <String, dynamic>{
    'on': true,
    'bri': config.brightness.clamp(0, 255),
    'seg': [
      <String, dynamic>{
        'fx': config.effectId,
        'sx': config.speed,
        'ix': config.intensity,
        'pal': 0,
        'col': [
          [primary.red, primary.green, primary.blue, 0],
          [secondary.red, secondary.green, secondary.blue, 0],
        ],
      }
    ],
  };

  // Pre-enumerate channels on the auto-built payload so it lights ALL
  // configured channels regardless of participation-cache warmth — mirrors
  // applySavedDesign (apply_saved_design.dart:56-61). The basic payload is a
  // single-seg-no-id "broadcast intent" shape; without this it falls through
  // `expandForParticipation` Rule 1 on a cold/null participation cache and
  // only seg 0 (channel 1) is written, leaving channel 2 dark. The filter
  // produces a multi-seg-with-ids payload that survives the chokepoint via
  // Rule 4 and lights every channel.
  final filteredBase =
      applyChannelFilter(basePayload, participatingChannels, deviceChannels);

  // User's named saved design wins over the auto-built basic payload — same
  // precedence rule [_activateNow] uses on the Path 1 Game Day Fan Zone
  // screen; the two callers must NOT diverge.
  //
  // The saved payload is ALREADY channel-filtered + multi-seg-with-ids: the
  // Game Day design picker runs applyChannelFilter before persisting
  // (pattern_theme_selection.dart:693/719), so it survives the chokepoint via
  // Rule 4 on its own. Forward it verbatim — re-running applyChannelFilter
  // would template off seg.first and FLATTEN a per-channel design down to
  // channel 0's look.
  final effectivePayload = config.savedDesignPayload ?? filteredBase;

  return applyPayloadWithLabel(
    effectivePayload,
    labelHint: '${config.shortTeamName} Game Day',
  );
}
