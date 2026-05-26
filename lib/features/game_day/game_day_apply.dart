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
/// Returns the underlying [applyPayloadWithLabel] result: true on
/// successful device write, false otherwise.
Future<bool> applyGameDayConfigToDevice({
  required ApplyPayloadWithLabelCall applyPayloadWithLabel,
  required GameDayAutopilotConfig config,
}) async {
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

  // User's named saved design wins over the auto-built basic payload.
  // Matches the same precedence rule [_activateNow] uses on the Path 1
  // Game Day Fan Zone screen — the two callers must NOT diverge.
  final effectivePayload = config.savedDesignPayload ?? basePayload;

  return applyPayloadWithLabel(
    effectivePayload,
    labelHint: '${config.shortTeamName} Game Day',
  );
}
