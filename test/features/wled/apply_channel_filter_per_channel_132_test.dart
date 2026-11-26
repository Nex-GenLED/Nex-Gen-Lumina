// Build 132 — applyChannelFilterPerChannel, the channel filter for the
// user-initiated Apply of a saved effect design or a favourite.
//
// It must be applyChannelFilter EXACTLY for every payload whose stated looks
// are all the same (checked byte for byte below over the shapes that reach
// it), and differ only where a channel states a look of its own.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

const _three = [
  DeviceChannel(id: 0, name: 'Roof', start: 0, stop: 30, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Side', start: 30, stop: 60, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Porch', start: 60, stop: 90, gpioPin: 15),
];

Map<String, dynamic> _look({int fx = 28, List<List<int>>? col, int? id}) => {
      if (id != null) 'id': id,
      'grp': 2,
      'spc': 3,
      'col': col ??
          const [
            [255, 0, 34, 0]
          ],
      'pal': 5,
      'fx': fx,
      'sx': 44,
      'ix': 90,
    };

void main() {
  group('one look: byte-identical to applyChannelFilter', () {
    final cases = <String, (Map<String, dynamic>, List<int>, List<DeviceChannel>)>{
      'one seg, no id (a card, the Pattern Editor)': (
        {'on': true, 'seg': [_look()]},
        [0, 1, 2],
        _three,
      ),
      'a seg per channel, all the same (every design saved before 132)': (
        {'on': true, 'bri': 150, 'seg': [for (final id in [0, 1, 2]) _look(id: id)]},
        [0, 1, 2],
        _three,
      ),
      'narrowed: one channel not playing': (
        {'on': true, 'seg': [for (final id in [0, 1, 2]) _look(id: id)]},
        [0, 2],
        _three,
      ),
      'the design stores fewer channels than are playing': (
        {'on': true, 'seg': [_look(id: 0)]},
        [0, 1, 2],
        _three,
      ),
      'a leading exclusion marker (a favourite logged narrowed)': (
        {
          'on': true,
          'seg': [
            {'id': 0, 'on': false},
            {..._look(id: 1), 'on': true},
          ]
        },
        [0, 1],
        _three,
      ),
      'stored bounds and `on` are dropped exactly as before': (
        {
          'on': true,
          'seg': [
            for (final id in [0, 1])
              {..._look(id: id), 'start': id * 30, 'stop': id * 30 + 30, 'on': false},
          ]
        },
        [0, 1],
        _three,
      ),
      'no channel census': (
        {'on': true, 'seg': [for (final id in [0, 1]) _look(id: id)]},
        [0, 1],
        const <DeviceChannel>[],
      ),
      'no target: returned as it came': (
        {'on': true, 'seg': [_look(id: 0), _look(id: 1, fx: 17)]},
        const <int>[],
        _three,
      ),
      'no seg list: returned as it came': (
        {'on': true, 'bri': 90},
        [0, 1],
        _three,
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final (payload, ids, channels) = e.value;
        expect(
          jsonEncode(applyChannelFilterPerChannel(payload, ids, channels)),
          jsonEncode(applyChannelFilter(payload, ids, channels)),
        );
      });
    }
  });

  group('a look per channel', () {
    final mixed = <String, dynamic>{
      'on': true,
      'seg': [
        _look(id: 0),
        _look(id: 1, fx: 17, col: const [
          [0, 255, 0, 0]
        ]),
        _look(id: 2, fx: 42),
      ],
    };

    test('each targeted channel is sent its own look', () {
      final out = applyChannelFilterPerChannel(mixed, const [0, 1, 2], _three);
      expect(out['seg'], [
        {'id': 0, ..._look(), 'on': true},
        {
          'id': 1,
          ..._look(fx: 17, col: const [
            [0, 255, 0, 0]
          ]),
          'on': true
        },
        {'id': 2, ..._look(fx: 42), 'on': true},
      ]);
    });

    test('a channel not playing is switched off and nothing else', () {
      final out = applyChannelFilterPerChannel(mixed, const [0, 2], _three);
      expect((out['seg'] as List)[1], {'id': 1, 'on': false});
      expect(((out['seg'] as List)[2] as Map)['fx'], 42);
    });

    test('a playing channel the payload does not state gets the FIRST look, '
        'as applyChannelFilter gives it', () {
      final two = <String, dynamic>{
        'on': true,
        'seg': [_look(id: 0), _look(id: 1, fx: 17)],
      };
      final per = applyChannelFilterPerChannel(two, const [0, 1, 2], _three);
      final old = applyChannelFilter(two, const [0, 1, 2], _three);
      expect((per['seg'] as List)[2], (old['seg'] as List)[2]);
      expect(((per['seg'] as List)[1] as Map)['fx'], 17);
      expect(((old['seg'] as List)[1] as Map)['fx'], 28,
          reason: 'what applyChannelFilter still does for every other caller');
    });

    test('a marker never stands in for a look', () {
      final out = applyChannelFilterPerChannel({
        'on': true,
        'seg': [
          {'id': 0, 'on': false, 'frz': false},
          _look(id: 1, fx: 17),
        ],
      }, const [0, 1], _three);
      expect(((out['seg'] as List)[0] as Map)['fx'], 17,
          reason: 'channel 0 states no look, so it takes the first real one');
    });

    test('the payload it was given is not changed', () {
      final before = jsonEncode(mixed);
      applyChannelFilterPerChannel(mixed, const [0, 1, 2], _three);
      expect(jsonEncode(mixed), before);
    });
  });
}
