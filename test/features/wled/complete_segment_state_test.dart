// Item 8 — applying a design writes a COMPLETE, deterministic segment state to
// every targeted segment, in one /json/state write.
//
// Observed on a two-channel home: with some effects, channel 1 showed static
// blocks of colour while channel 2 animated. The apply path stated fx, speed,
// intensity, palette, colours, grouping and spacing on both — and left the
// effect's own sliders and checkboxes (`c1`–`c3`, `o1`–`o3`) and the segment's
// own brightness to whatever each segment already held. WLED resets those
// only when its own UI picks an effect (`fxdef`), never on a JSON write.
//
// These tests drive the REAL apply path — notifier → channel filter →
// repository → normalize → participation → geometry pin — and assert on what
// would have reached the controller.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/recording_wled_repository.dart';

/// Every field that decides what a segment shows, other than where it lies —
/// before the effect's own options, which depend on the effect.
const _lookFields = [
  'on', 'bri', 'fx', 'sx', 'ix', 'pal', 'col', 'grp', 'spc', 'frz', //
];

/// The look fields for a segment running [fx]: the common ones plus every
/// option that effect reads.
List<String> _lookFieldsFor(int fx) => [..._lookFields, ...optionKeysReadBy(fx)];

/// Where and which way the segment lies. Provisioning's; an apply states none.
const _geometryFields = ['start', 'stop', 'rev', 'mi', 'of'];

List<DeviceChannel> _channels(int count, {int each = 30}) => [
      for (var i = 0; i < count; i++)
        DeviceChannel(
          id: i,
          name: 'Channel ${i + 1}',
          start: i * each,
          stop: (i + 1) * each,
          gpioPin: i,
        ),
    ];

/// The simulated controller: the real WledService, real wire pipeline, no
/// socket. Records every body at the wire exit.
WledService _controller() => WledService('http://mock');

Future<ProviderContainer> _container(
  Object repo, {
  required int channels,
}) async {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo as dynamic),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(_channels(channels)),
    participatingChannelIdsProvider.overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  await c.read(wledConnectivityStatusProvider.future);
  return c;
}

/// A traveling effect, as Explore builds it.
Map<String, dynamic> _traveling(int fx) => {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'fx': fx,
          'sx': 160,
          'ix': 128,
          'pal': WledEffectsCatalog.paletteForEffect(fx),
          'grp': 1,
          'spc': 0,
          'col': [
            [255, 0, 0, 0],
            [0, 0, 255, 0],
          ],
        },
      ],
    };

Map<String, dynamic> _look(Map seg) => {
      for (final k in [..._lookFields, ...kSegEffectOptionKeys])
        if (seg.containsKey(k)) k: seg[k],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Scan, Chase, Two Dots, Running, Meteor: traveling effects. Scan and Two
  // Dots read "Overlay" (o2), Meteor reads "Gradient" (o1); Chase and Running
  // read no option, so none is stated for them.
  for (final fx in [10, 28, 50, 15, 76]) {
    for (final count in [2, 4]) {
      test('fx $fx on a $count-segment controller: every targeted segment '
          'carries the same complete state, in one write', () async {
        final controller = _controller();
        final c = await _container(controller, channels: count);

        final ok = await c
            .read(wledStateProvider.notifier)
            .applyToDevice(_traveling(fx), labelHint: 'Traveling');

        expect(ok, isTrue);
        expect(controller.simulatedStatePosts, hasLength(1),
            reason: 'one atomic /json/state write');
        final segs = controller.simulatedStatePosts.single['seg'] as List;
        expect([for (final s in segs) (s as Map)['id']],
            [for (var i = 0; i < count; i++) i]);

        for (final s in segs) {
          s as Map;
          for (final field in _lookFieldsFor(fx)) {
            expect(s.containsKey(field), isTrue,
                reason: 'seg ${s['id']} does not state `$field`');
          }
          for (final field in kSegEffectOptionKeys) {
            if (optionKeysReadBy(fx).contains(field)) continue;
            expect(s.containsKey(field), isFalse,
                reason: 'fx $fx does not read `$field`; it is not sent');
          }
          for (final field in _geometryFields) {
            expect(s.containsKey(field), isFalse,
                reason: 'seg ${s['id']} states geometry `$field`');
          }
        }

        final first = jsonEncode(_look(segs.first as Map));
        for (final s in segs) {
          expect(jsonEncode(_look(s as Map)), first,
              reason: 'seg ${s['id']} differs from seg 0');
        }

        final s0 = segs.first as Map;
        expect(s0['fx'], fx);
        expect(s0['sx'], 160);
        expect(s0['grp'], 1);
        expect(s0['spc'], 0);
        expect(s0['frz'], isFalse);
        expect(s0['on'], isTrue);
        expect(s0['bri'], 255);
        for (final k in optionKeysReadBy(fx)) {
          expect(s0[k], k.startsWith('o') ? isFalse : isA<int>(), reason: k);
        }
        expect(s0['col'], hasLength(3));
      });
    }
  }

  test('a design that intends grouping and spacing sets them on every '
      'targeted segment equally', () async {
    final controller = _controller();
    final c = await _container(controller, channels: 4);
    final payload = _traveling(28);
    ((payload['seg'] as List).single as Map)
      ..['grp'] = 3
      ..['spc'] = 2;

    await c
        .read(wledStateProvider.notifier)
        .applyToDevice(payload, labelHint: 'Spaced');

    final segs = controller.simulatedStatePosts.single['seg'] as List;
    expect(segs, hasLength(4));
    expect(segs.every((s) => (s as Map)['grp'] == 3), isTrue);
    expect(segs.every((s) => (s as Map)['spc'] == 2), isTrue);
  });

  test('a channel left out of the design is switched off and given no look',
      () async {
    final controller = _controller();
    final c = await _container(controller, channels: 2);
    c.read(selectedChannelIdsProvider.notifier).state = {1};

    await c
        .read(wledStateProvider.notifier)
        .applyToDevice(_traveling(28), labelHint: 'One channel');

    final segs = controller.simulatedStatePosts.single['seg'] as List;
    expect(segs.first, {'id': 0, 'on': false, 'frz': false});
    expect((segs.last as Map)['fx'], 28);
    expect((segs.last as Map)['bri'], kSegDefaultBri);
  });

  test('the recording fake sees one entry per targeted segment too', () async {
    final repo = RecordingWledRepository();
    final c = await _container(repo, channels: 4);

    await c
        .read(wledStateProvider.notifier)
        .applyToDevice(_traveling(28), labelHint: 'Chase');

    expect(repo.applied, hasLength(1));
    final segs = repo.applied.single['seg'] as List;
    expect([for (final s in segs) (s as Map)['id']], [0, 1, 2, 3]);
    final wire = normalizeWledPayload(repo.applied.single)['seg'] as List;
    final first = jsonEncode(_look(wire.first as Map));
    for (final s in wire) {
      expect(jsonEncode(_look(s as Map)), first);
    }
  });

  group('normalizeWledPayload — completion rules', () {
    Map<String, dynamic> seg(Map<String, dynamic> s) =>
        (normalizeWledPayload({
          'seg': [s]
        })['seg'] as List)
            .single as Map<String, dynamic>;

    test('a stale option on the controller is overwritten by the design', () {
      // What a segment left with "Overlay" set looks like after an apply: the
      // design now states o2, so the controller can no longer keep its own.
      final s = seg({
        'fx': 10,
        'col': [
          [255, 0, 0, 0]
        ]
      });
      expect(s['o2'], isFalse);
    });

    test('an option the caller stated is never overwritten', () {
      // Waterfall (140) reads c1 and c2.
      final s = seg({
        'fx': 140,
        'o1': 200,
        'c1': 40,
        'bri': 90,
        'col': [
          [0, 0, 255, 0]
        ]
      });
      expect(s['o1'], 200);
      expect(s['c1'], 40);
      expect(s['bri'], 90);
      expect(s['c2'], 128);
    });

    test('a complete design with no speed, intensity or palette gets them',
        () {
      final s = seg({
        'fx': 28,
        'col': [
          [255, 0, 0, 0]
        ]
      });
      expect(s['sx'], 128);
      expect(s['ix'], 128);
      expect(s['pal'], WledEffectsCatalog.paletteForEffect(28));
    });

    test('a palette filled in is held to the same pal:5 rule as a stated one',
        () {
      // Colorwaves reads a palette; 5 for it is rewritten to 4 on the wire.
      final s = seg({
        'fx': 63,
        'col': [
          [255, 0, 0, 0]
        ]
      });
      expect(s['pal'], 4);
    });

    test('an effect-only change resets the options and keeps the tuning', () {
      final s = seg({'fx': 50});
      expect(s['o2'], isFalse);
      expect(s.containsKey('c1'), isFalse, reason: 'Two Dots does not read c1');
      expect(s.containsKey('sx'), isFalse);
      expect(s.containsKey('ix'), isFalse);
      expect(s.containsKey('pal'), isFalse);
    });

    test('a colour-only change states no effect options', () {
      final s = seg({
        'id': 0,
        'col': [
          [255, 0, 0, 0]
        ]
      });
      for (final k in kSegEffectOptionKeys) {
        expect(s.containsKey(k), isFalse, reason: k);
      }
      expect(s.containsKey('bri'), isFalse);
    });

    test('a slider tweak states nothing but itself and the freeze guard', () {
      expect(seg({'sx': 200}), {'sx': 200, 'frz': false});
    });

    test('an exclusion marker gets no look', () {
      expect(seg({'id': 0, 'on': false}), {'id': 0, 'on': false, 'frz': false});
    });

    test('a per-pixel paint is left alone', () {
      final s = seg({
        'id': 0,
        'fx': 0,
        'i': [
          0,
          [255, 0, 0, 0]
        ]
      });
      for (final k in kSegEffectOptionKeys) {
        expect(s.containsKey(k), isFalse, reason: k);
      }
    });

    test('geometry is never added', () {
      final s = seg({
        'fx': 28,
        'col': [
          [255, 0, 0, 0]
        ]
      });
      for (final k in [..._geometryFields, 'm12', 'si', 'sel']) {
        expect(s.containsKey(k), isFalse, reason: k);
      }
    });

    test('an effect that reads no option gets none', () {
      final s = seg({
        'fx': 28,
        'col': [
          [255, 0, 0, 0]
        ]
      });
      for (final k in kSegEffectOptionKeys) {
        expect(s.containsKey(k), isFalse, reason: k);
      }
      expect(s['bri'], kSegDefaultBri);
    });

    test('an effect unknown to the firmware gets all six', () {
      final s = seg({'fx': kWledKnownEffectIdCeiling + 5});
      for (final k in kSegEffectOptionKeys) {
        expect(s.containsKey(k), isTrue, reason: k);
      }
    });

    test('the table knows the Overlay family', () {
      for (final fx in [10, 11, 20, 21, 22, 50, 58, 79, 85, 86, 87, 91, 95]) {
        expect(optionKeysReadBy(fx), contains('o2'), reason: 'fx $fx');
      }
    });

    test('idempotent', () {
      final once = normalizeWledPayload(_traveling(28));
      expect(jsonEncode(normalizeWledPayload(once)), jsonEncode(once));
    });
  });

  test('a saved preset stores the complete state as well', () async {
    final state = ensurePsaveClearsFreeze(
        normalizeWledPayload(_traveling(10)), const [0, 1]);
    final s = (state['seg'] as List).single as Map;
    // Scan (10) reads only "Overlay" (o2).
    for (final k in ['o2', 'bri', 'frz', 'sx', 'ix', 'pal']) {
      expect(s.containsKey(k), isTrue, reason: k);
    }
    expect(s['o2'], isFalse);
  });
}
