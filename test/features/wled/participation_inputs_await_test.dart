// REGRESSION GUARD for the ROOFLINE await, plus the cfg→bus parser.
//
// SCOPE NOTE (+73). This file used to guard BOTH participation inputs. The bus
// list no longer crosses a provider boundary — since the +73 rewire it comes
// from the healer's own /json/cfg read via `hardwareConfigFromCfg`, because
// §7.2d proved `deviceHardwareConfigProvider` returns a stale cached null at
// the very instant the healer's own read succeeds. So the 20s bound and the
// await guard now cover the ROOFLINE leg ONLY.
//
// Nothing that was pinned has been dropped — the bus leg is pinned harder, and
// differently: by parser tests against a real captured payload, and by a test
// that buses and timers come from ONE fetch.
//
// The roofline half is unchanged, and it is still the dangerous one:
//
//   an unresolved roofline stream  →  no segments yet
//   a genuinely untraced install   →  no segments, ever
//
// indistinguishable BY VALUE, and `resolveParticipatingChannels` reads
// `segments.isEmpty` as "untraced install ⇒ EVERY channel participates". So
// sampling does not refuse and does not throw — it publishes a SUPERSET that
// looks entirely plausible.
//
// The test therefore pins the AWAIT, not the answer: the "never emits" case
// asserts the future does NOT complete, which is the only observable
// difference between awaiting and sampling.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/channel_participation_resolver.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Verbatim `/json/cfg` excerpt from the bench controller `.150`, 2026-08-12 —
/// two buses (0-128 pin 2, 128-290 pin 14) and the three armed timer rows left
/// after the Wednesday lease expired.
const String _benchCfg = '''
{
  "hw": {"led": {"total": 290, "maxpwr": 30000, "ins": [
    {"start": 0, "len": 128, "pin": [2], "type": 30, "order": 1},
    {"start": 128, "len": 162, "pin": [14], "type": 30, "order": 1}
  ]}},
  "if": {"ntp": {"tz": 5, "lt": 38.99346, "ln": -94.2527}},
  "light": {"gc": {"bri": 1, "col": 2.8, "val": 2.8}},
  "timers": {"ins": [
    {"en": 1, "hour": 20, "min": 23, "macro": 10, "dow": 127},
    {"en": 1, "hour": 6, "min": 22, "macro": 2, "dow": 127},
    {"en": 1, "hour": 255, "min": 0, "macro": 2, "dow": 127}
  ]}
}
''';

RooflineSegment _seg({required int channelIndex, required bool isPrimary}) =>
    RooflineSegment(
      id: 'ch$channelIndex',
      name: 'ch$channelIndex',
      pixelCount: 10,
      channelIndex: channelIndex,
      isPrimary: isPrimary,
      points: const [],
    );

/// Channel 0 primary, channel 1 traced but NOT primary → correct answer `[0]`.
RooflineConfiguration _tracedRoofline() => RooflineConfiguration(
      id: 'r1',
      name: 'bench',
      segments: [
        _seg(channelIndex: 0, isPrimary: true),
        _seg(channelIndex: 1, isPrimary: false),
      ],
      createdAt: DateTime(2026, 8, 12),
      updatedAt: DateTime(2026, 8, 12),
    );

/// Runs `resolveRooflineSegments` inside a real container so the provider await
/// is exercised rather than stubbed.
final _probe = FutureProvider<List<RooflineSegment>>(
  (ref) => resolveRooflineSegments(ref),
);

ProviderContainer _container(Stream<RooflineConfiguration?> roofline) =>
    ProviderContainer(overrides: [
      currentRooflineConfigProvider.overrideWith((ref) => roofline),
    ]);

/// The bus list the healer now supplies from its own cfg.
List<int> _resolveWith(List<RooflineSegment> segments) =>
    resolveParticipatingChannels(
      explicit: null,
      segments: segments,
      allDeviceChannelIds: const [0, 1],
    );

void main() {
  group('the ROOFLINE await — the remaining timed leg', () {
    test('an UNRESOLVED roofline stream blocks — it never yields the superset',
        () async {
      final never = StreamController<RooflineConfiguration?>();
      addTearDown(never.close);
      final c = _container(never.stream);
      addTearDown(c.dispose);

      Object? settled;
      unawaited(c.read(_probe.future).then((v) => settled = v));
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(settled, isNull,
          reason: 'resolveRooflineSegments must still be AWAITING. A value '
              'here means it sampled an unresolved stream, and the set derived '
              'from it would be the superset.');
    });

    test('once it arrives, the traced roofline EXCLUDES the secondary channel',
        () async {
      final c = _container(
          Stream<RooflineConfiguration?>.value(_tracedRoofline()));
      addTearDown(c.dispose);

      final segments = await c.read(_probe.future);
      expect(segments, hasLength(2));
      expect(_resolveWith(segments), [0],
          reason: 'channel 1 is traced but not primary. [0, 1] would be the '
              'untraced-install superset — the wrong answer sampling gives.');
    });

    test('a genuinely UNTRACED install is every channel — the two cases differ '
        'by timing, not by value', () async {
      final c = _container(Stream<RooflineConfiguration?>.value(null));
      addTearDown(c.dispose);

      final segments = await c.read(_probe.future);
      expect(segments, isEmpty);
      expect(_resolveWith(segments), [0, 1],
          reason: 'correct HERE — which is exactly why value alone cannot '
              'detect the sampling bug');
    });
  });

  group('hardwareConfigFromCfg — the bus leg, parsed from the healer cfg', () {
    test('the REAL captured bench payload yields both buses', () {
      final hw = hardwareConfigFromCfg(
          jsonDecode(_benchCfg) as Map<String, dynamic>);
      expect(hw, isNotNull);
      expect(hw!.totalLeds, 290);
      expect(hw.buses.map((b) => [b.start, b.len]).toList(), [
        [0, 128],
        [128, 162],
      ]);
      expect(hw.buses.map((b) => b.pin.first).toList(), [2, 14]);
      expect(deviceChannelsFromConfig(hw).map((c) => c.id).toList(), [0, 1],
          reason: 'the exact set §7.2d expected and did not get');
    });

    test('UNREADABLE and EMPTY are different answers', () {
      // null → could not see hw.led         → shapeUnknown
      // []   → saw it, nothing wired        → noBusesConfigured
      // Collapsing these is the #63 class.
      expect(hardwareConfigFromCfg(null), isNull);
      expect(hardwareConfigFromCfg({}), isNull);
      expect(hardwareConfigFromCfg({'hw': 'nope'}), isNull);
      expect(
          hardwareConfigFromCfg({
            'hw': {'led': 'nope'}
          }),
          isNull);

      final empty = hardwareConfigFromCfg({
        'hw': {
          'led': {'total': 0}
        }
      });
      expect(empty, isNotNull, reason: 'the block WAS readable');
      expect(empty!.buses, isEmpty);
      expect(deviceChannelsFromConfig(empty), isEmpty);
    });

    test('malformed bus entries are skipped, not fatal', () {
      final hw = hardwareConfigFromCfg({
        'hw': {
          'led': {
            'total': 128,
            'ins': [
              {'start': 0, 'len': 128, 'pin': [2]},
              'garbage',
            ],
          }
        }
      });
      expect(hw!.buses, hasLength(1));
    });
  });

  group('ONE FETCH — buses and timers come from the same cfg map', () {
    test('ControllerClockInfo.fromMaps parses both from one payload', () {
      // The cost argument for putting the publish in the healer rests on this:
      // if the bus list ever needs its own fetch, that argument collapses.
      final info = ControllerClockInfo.fromMaps(
        {'time': '2026-8-12, 4:19:08'},
        jsonDecode(_benchCfg) as Map<String, dynamic>,
      );

      expect(info.hardwareKnown, isTrue);
      expect(info.timersKnown, isTrue);
      expect(deviceChannelsFromConfig(info.hardware).map((c) => c.id).toList(),
          [0, 1]);
      expect(info.timerRows, hasLength(3));
      expect(info.tzIndex, 5, reason: 'clock fields still parse — additive');
    });

    test('relay (no cfg) leaves BOTH unknown, not empty', () {
      final info =
          ControllerClockInfo.fromMaps({'time': '2026-8-12, 4:19:08'}, null);
      expect(info.hardwareKnown, isFalse);
      expect(info.timersKnown, isFalse);
    });
  });
}
