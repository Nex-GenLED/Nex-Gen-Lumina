// REGRESSION GUARD for the roofline half of the +69 ordering defect.
//
// `resolveParticipationInputs` must AWAIT `currentRooflineConfigProvider`, not
// sample it. The distinction is not cosmetic:
//
//   an unresolved roofline stream  →  no segments yet
//   a genuinely untraced install   →  no segments, ever
//
// Those are indistinguishable by value, and `resolveParticipatingChannels`
// treats `segments.isEmpty` as "untraced install ⇒ EVERY channel
// participates". So a sampled-but-unresolved roofline does not refuse and does
// not fail — it publishes a SUPERSET, lighting channels the roofline marks
// secondary-only, and it looks entirely plausible on the way out.
//
// That is why this is the more dangerous of the two async inputs: the bus-list
// half at least refused (`participationShapeIsKnown`) and left the field
// absent. This half would have written a wrong answer with full confidence.
//
// The test pins the AWAIT, not the answer. A future refactor that drops the
// `await` and reads `.valueOrNull` would still return a plausible list and
// would still pass an answer-only assertion — so the "never emits" case asserts
// that the future does NOT complete, which is the only observable difference.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/controller_facts_publisher.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Two buses — the bench rig's actual shape (0-128 pin 2, 128-290 pin 14).
/// Channels [0, 1].
WledHardwareConfig _twoBusConfig() => const WledHardwareConfig(
      totalLeds: 290,
      buses: [
        WledLedBus(pin: [2], start: 0, len: 128),
        WledLedBus(pin: [14], start: 128, len: 162),
      ],
    );

RooflineSegment _seg({required int channelIndex, required bool isPrimary}) =>
    RooflineSegment(
      id: 'ch$channelIndex',
      name: 'ch$channelIndex',
      pixelCount: 10,
      channelIndex: channelIndex,
      isPrimary: isPrimary,
      points: const <Offset>[],
    );

/// Channel 0 primary, channel 1 traced but NOT primary.
///
/// The correct resolution is `[0]`. If the roofline is treated as empty the
/// resolver returns `[0, 1]` — the superset this test exists to forbid.
RooflineConfiguration _tracedRoofline() => RooflineConfiguration(
      id: 'r1',
      name: 'bench',
      segments: [
        _seg(channelIndex: 0, isPrimary: true),
        _seg(channelIndex: 1, isPrimary: false),
      ],
      createdAt: DateTime(2026, 8, 11),
      updatedAt: DateTime(2026, 8, 11),
    );

/// Runs `resolveParticipationInputs` inside a real container so the provider
/// awaits are exercised, not stubbed.
final _probe = FutureProvider<ParticipationInput?>(
  (ref) => resolveParticipationInputs(ref),
);

ProviderContainer _container({
  required Stream<RooflineConfiguration?> roofline,
  WledHardwareConfig? hardware,
  Duration hardwareDelay = Duration.zero,
}) {
  return ProviderContainer(
    overrides: [
      deviceHardwareConfigProvider.overrideWith((ref) async {
        if (hardwareDelay > Duration.zero) {
          await Future<void>.delayed(hardwareDelay);
        }
        return hardware;
      }),
      currentRooflineConfigProvider.overrideWith((ref) => roofline),
    ],
  );
}

void main() {
  test('an UNRESOLVED roofline stream blocks — it never yields the superset',
      () async {
    // The stream is open and has emitted nothing, exactly as at t=0 of a
    // connect. A sampling implementation would return [0, 1] here immediately.
    final never = StreamController<RooflineConfiguration?>();
    addTearDown(never.close);

    final c = _container(roofline: never.stream, hardware: _twoBusConfig());
    addTearDown(c.dispose);

    Object? settled;
    unawaited(c.read(_probe.future).then((v) => settled = v ?? 'null'));

    // Generous relative to anything the resolver does synchronously.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(settled, isNull,
        reason: 'resolveParticipationInputs must still be AWAITING the '
            'roofline. A non-null value here means it sampled an unresolved '
            'stream — and the value it would have produced is the superset.');
  });

  test('once the roofline arrives it resolves, and EXCLUDES the non-primary '
      'channel', () async {
    // Same container shape, but the stream emits. This is the control: it
    // proves the blocking above is the await and not a broken override.
    final c = _container(
      roofline: Stream<RooflineConfiguration?>.value(_tracedRoofline()),
      hardware: _twoBusConfig(),
    );
    addTearDown(c.dispose);

    final input = await c.read(_probe.future);

    expect(input, isNotNull);
    expect(input!.deviceChannelIds, [0, 1], reason: 'both buses are present');
    expect(input.resolved, [0],
        reason: 'channel 1 is traced but not primary, so it is EXCLUDED. '
            '[0, 1] here would be the untraced-install superset — the exact '
            'wrong answer an unresolved roofline produces.');
  });

  test('a genuinely UNTRACED install is still every channel — the two cases '
      'differ by timing, not by value', () async {
    // The reason sampling is undetectable by value: this legitimately IS the
    // superset, and it is correct here.
    final c = _container(
      roofline: Stream<RooflineConfiguration?>.value(null),
      hardware: _twoBusConfig(),
    );
    addTearDown(c.dispose);

    final input = await c.read(_probe.future);
    expect(input!.resolved, [0, 1]);
  });

  test('a LATE bus list is awaited too, not sampled as empty', () async {
    // The half that failed on +69: deviceHardwareConfigProvider had not
    // resolved, so the bus list read as [] and participation was refused on
    // every connect.
    final c = _container(
      roofline: Stream<RooflineConfiguration?>.value(_tracedRoofline()),
      hardware: _twoBusConfig(),
      hardwareDelay: const Duration(milliseconds: 120),
    );
    addTearDown(c.dispose);

    final input = await c.read(_probe.future);
    expect(input, isNotNull,
        reason: 'a slow bus list must be waited for, not treated as unknown');
    expect(input!.deviceChannelIds, [0, 1]);
  });

  test('an EMPTY bus list still returns null — shape unknown, never []',
      () async {
    // Unchanged behaviour, re-pinned here because it now shares a code path
    // with the roofline await.
    final c = _container(
      roofline: Stream<RooflineConfiguration?>.value(_tracedRoofline()),
      hardware: null,
    );
    addTearDown(c.dispose);

    expect(await c.read(_probe.future), isNull);
  });
}
