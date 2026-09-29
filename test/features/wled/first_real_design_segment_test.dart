// P6 — `seg[0]` is not "the design segment".
//
// Since applyChannelFilter emits the full partition, a payload scoped away
// from channel 1 leads with the exclusion marker `{id: 0, on: false}`. Every
// reader that took `seg[0]` saw no effect and no colours.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/favorites/favorite_apply.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/recording_wled_repository.dart';

const _design = {
  'id': 1,
  'on': true,
  'fx': 28,
  'sx': 160,
  'ix': 128,
  'pal': 5,
  'col': [
    [255, 0, 0, 0],
    [0, 0, 255, 0],
  ],
};

/// What a favourite captured while channel 1 was deselected looks like.
Map<String, dynamic> _storedScopedAway() => {
      'on': true,
      'bri': 200,
      'seg': [
        {'id': 0, 'on': false},
        Map<String, dynamic>.from(_design),
      ],
    };

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];

class _StillNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository repo) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    deviceChannelsProvider.overrideWithValue(_channels),
    effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
    wledStateProvider.overrideWith(() => _StillNotifier()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('firstRealDesignSegment', () {
    test('reads past a leading exclusion marker', () {
      final seg = firstRealDesignSegment(_storedScopedAway());
      expect(seg?['fx'], 28);
      expect(seg?['id'], 1);
    });

    test('reads past a marker that has been through the wire (frz:false)', () {
      final seg = firstRealDesignSegment({
        'seg': [
          {'id': 0, 'on': false, 'frz': false},
          _design,
        ],
      });
      expect(seg?['fx'], 28);
    });

    test('an ordinary payload: the first segment, unchanged', () {
      final seg = firstRealDesignSegment({
        'seg': [_design]
      });
      expect(seg, _design);
    });

    test('accepts the seg value as well as the whole payload', () {
      expect(firstRealDesignSegment([_design])?['fx'], 28);
    });

    test('accepts a seg that is a single map (WLED returns either)', () {
      expect(firstRealDesignSegment({'seg': _design})?['fx'], 28);
    });

    test('a per-pixel segment counts as a design', () {
      final seg = firstRealDesignSegment({
        'seg': [
          {'id': 0, 'on': false},
          {
            'id': 1,
            'i': [
              0,
              [255, 0, 0, 0]
            ]
          },
        ],
      });
      expect(seg?['id'], 1);
    });

    test('a one-field tweak is returned when nothing states a look', () {
      expect(
        firstRealDesignSegment({
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'sx': 200},
          ],
        }),
        {'id': 1, 'sx': 200},
      );
    });

    test('a switched-off channel that still states a look is a design', () {
      final seg = firstRealDesignSegment({
        'seg': [
          {
            'id': 0,
            'on': false,
            'fx': 2,
            'col': [
              [1, 2, 3, 0]
            ]
          },
        ],
      });
      expect(seg?['fx'], 2);
    });

    test('nothing but markers → null, never "white"', () {
      expect(
        firstRealDesignSegment({
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'on': false},
          ],
        }),
        isNull,
      );
    });

    test('no seg, empty seg, junk → null', () {
      expect(firstRealDesignSegment({'on': true}), isNull);
      expect(firstRealDesignSegment({'seg': []}), isNull);
      expect(firstRealDesignSegment({'seg': 'nope'}), isNull);
      expect(firstRealDesignSegment(null), isNull);
    });

    test('returns a copy — the caller cannot mutate the payload through it',
        () {
      final payload = _storedScopedAway();
      firstRealDesignSegment(payload)!['fx'] = 99;
      expect(((payload['seg'] as List)[1] as Map)['fx'], 28);
    });

    test('firstDesignSeg keeps its old answer for a marker-only payload', () {
      // Existing callers rely on it; new code calls firstRealDesignSegment.
      expect(
        firstDesignSeg([
          {'id': 0, 'on': false}
        ]),
        {'id': 0, 'on': false},
      );
    });
  });

  group('applyChannelFilter templates from the real design', () {
    test('a stored payload with a leading marker re-applies its LOOK', () {
      final out = applyChannelFilter(_storedScopedAway(), [0, 1], _channels);
      final segs = out['seg'] as List;
      expect(segs, hasLength(2));
      for (final s in segs) {
        s as Map;
        expect(s['on'], isTrue);
        expect(s['fx'], 28);
        expect(s['col'], _design['col']);
      }
      expect([for (final s in segs) (s as Map)['id']], [0, 1]);
    });

    test('an ordinary payload is filtered exactly as before', () {
      final raw = {
        'on': true,
        'seg': [
          {
            'fx': 28,
            'sx': 160,
            'col': [
              [255, 0, 0, 0]
            ]
          },
        ],
      };
      expect(applyChannelFilter(raw, [1], _channels)['seg'], [
        {'id': 0, 'on': false},
        {
          'id': 1,
          'fx': 28,
          'sx': 160,
          'col': [
            [255, 0, 0, 0]
          ],
          'on': true,
        },
      ]);
    });
  });

  group('favourite re-apply (row 25)', () {
    test('a favourite captured with channel 1 deselected sends its look',
        () async {
      final repo = RecordingWledRepository();
      final c = _container(repo);

      final outcome =
          await applyFavoritePayloadWith(c.read, _storedScopedAway());

      expect(outcome.status, FavoriteApplyStatus.applied);
      final segs = repo.applied.single['seg'] as List;
      expect(segs.every((s) => (s as Map)['fx'] == 28), isTrue);
      expect(segs.every((s) => (s as Map).containsKey('col')), isTrue);
    });

    test('a favourite that holds no look at all is not "Applied"', () async {
      final repo = RecordingWledRepository();
      final c = _container(repo);

      final outcome = await applyFavoritePayloadWith(c.read, {
        'on': true,
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, 'on': false},
        ],
      });

      expect(outcome.status, FavoriteApplyStatus.noDesign);
      expect(outcome.isApplied, isFalse);
      expect(repo.writeCount, 0);
    });
  });

  test('the four seg[0] readers call the shared helper', () {
    // Source guard, so a hand-rolled `seg[0]` read cannot quietly come back.
    const sites = {
      'lib/features/dashboard/wled_dashboard_page.dart': 1,
      'lib/widgets/favorites_grid.dart': 1,
      'lib/features/favorites/favorite_apply.dart': 1,
      'lib/features/wled/usage_tracking_extension.dart': 2,
    };
    sites.forEach((path, atLeast) {
      final source = File(path).readAsStringSync();
      expect(
        'firstRealDesignSegment('.allMatches(source).length,
        greaterThanOrEqualTo(atLeast),
        reason: path,
      );
    });
  });
}
