// +114 item 1b — base_ladder_restore_lit / base_ladder_dark_channels.
//
// What the ladder PRODUCES when it fires, measured from the stored preset
// bodies. The rules: ON presets light every participating bus (root on, bri
// above zero, segment on, a non-black colour or a fixed palette); the OFF
// preset darkens every bus; presets 1 and 2 are required because a server
// restore can load them.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
import 'package:nexgen_command/features/wled/base_look.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';

const threeBus = <int>[0, 1, 2];

Map<String, dynamic> live(List<int> ids) => {
      'on': true,
      'seg': [
        for (final id in ids) {'id': id, 'on': true},
      ],
    };

/// The ladder exactly as +114's builders write it.
Map<int, Map<String, dynamic>> builtLadder(List<int> ids) => {
      for (final e in ScheduleSyncService.kOnPresetSpecs.entries)
        e.key: {
          'n': e.value.name,
          ...ScheduleSyncService.buildNglOnPresetState(e.value.bri, live(ids)),
        },
      2: {
        'n': 'NGL Off',
        ...ScheduleSyncService.buildNglOffPresetState(live(ids)),
      },
    };

/// One ON preset with every segment on and the given look.
Map<String, dynamic> onPreset(
  List<int> ids, {
  Object? col,
  int fx = 0,
  int? pal,
  Object? rootOn = true,
  int? bri = 200,
  Map<int, Map<String, dynamic>> overrides = const {},
}) =>
    {
      if (rootOn != null) 'on': rootOn,
      if (bri != null) 'bri': bri,
      'seg': [
        for (final id in ids)
          overrides[id] ??
              {
                'id': id,
                'on': true,
                'fx': fx,
                if (pal != null) 'pal': pal,
                'col': col ?? baseLookColSlots(),
              },
      ],
    };

LadderRestoreVerdict verdictWith(
  Map<int, Map<String, dynamic>> ladder, {
  List<int> participating = threeBus,
  List<int> device = threeBus,
}) =>
    evaluateLadderRestore(
      presets: ladder,
      participating: participating,
      deviceChannelIds: device,
    )!;

LadderPresetVerdict slot(LadderRestoreVerdict v, int id) =>
    v.presets.firstWhere((p) => p.presetId == id);

void main() {
  group('a ladder written by the +114 builders', () {
    test('restores lit, nothing dark', () {
      final v = verdictWith(builtLadder(threeBus));
      expect(v.restoreLit, isTrue);
      expect(v.darkChannels, isEmpty);
      expect(v.badPresetIds, isEmpty);
      expect(v.missingPresetIds, isEmpty);
    });
  });

  group('ON presets — the colour half (the captured-black defect)', () {
    test('lit-but-black Solid preset fails, every participating bus dark', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, col: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ]);
      final v = verdictWith(l);
      expect(v.restoreLit, isFalse);
      expect(v.darkChannels, threeBus);
      expect(v.badPresetIds, [1]);
      expect(slot(v, 1).faults, [LadderFault.channelBlack]);
    });

    test('Solid ignores the palette: black slot 1 + palette 11 is still dark',
        () {
      final l = builtLadder(threeBus)
        ..[3] = onPreset(threeBus, pal: 11, col: [
          [0, 0, 0, 0],
          [255, 0, 0, 0],
        ]);
      expect(slot(verdictWith(l), 3).faults, [LadderFault.channelBlack]);
    });

    test('a moving effect with a fixed palette (>= 6) lights black slots', () {
      final l = builtLadder(threeBus)
        ..[4] = onPreset(threeBus, fx: 9, pal: 11, col: [
          [0, 0, 0, 0],
        ]);
      expect(slot(verdictWith(l), 4).ok, isTrue);
    });

    test('a moving effect on a colour-slot palette (< 6) with black slots is '
        'dark', () {
      final l = builtLadder(threeBus)
        ..[4] = onPreset(threeBus, fx: 9, pal: 3, col: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ]);
      expect(slot(verdictWith(l), 4).faults, [LadderFault.channelBlack]);
    });

    test('a moving effect with any non-black slot is lit', () {
      final l = builtLadder(threeBus)
        ..[5] = onPreset(threeBus, fx: 9, pal: 0, col: [
          [0, 0, 0, 0],
          [0, 0, 0, 40],
        ]);
      expect(slot(verdictWith(l), 5).ok, isTrue);
    });

    test('white-only colour counts as lit (RGBW)', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, col: [
          [0, 0, 0, 255],
        ]);
      expect(slot(verdictWith(l), 1).ok, isTrue);
    });

    test('hex-string colours are read', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, col: ['000000'])
        ..[3] = onPreset(threeBus, col: ['00D4FF']);
      final v = verdictWith(l);
      expect(slot(v, 1).faults, [LadderFault.channelBlack]);
      expect(slot(v, 3).ok, isTrue);
    });

    test('a segment with no col at all cannot be shown lit', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, overrides: {
          1: {'id': 1, 'on': true, 'fx': 0},
        });
      final v = verdictWith(l);
      expect(slot(v, 1).channels, [1]);
      expect(slot(v, 1).faults, [LadderFault.channelBlack]);
    });
  });

  group('ON presets — the power half', () {
    test('root on absent (no ib) — every participating bus dark', () {
      final l = builtLadder(threeBus)..[1] = onPreset(threeBus, rootOn: null);
      final p = slot(verdictWith(l), 1);
      expect(p.faults, contains(LadderFault.rootNotOn));
      expect(p.channels, threeBus);
    });

    test('root bri 0 — dark', () {
      final l = builtLadder(threeBus)..[5] = onPreset(threeBus, bri: 0);
      expect(slot(verdictWith(l), 5).faults, contains(LadderFault.rootBriZero));
    });

    test('a participating segment off — that bus is dark', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, overrides: {
          2: {'id': 2, 'on': false},
        });
      final v = verdictWith(l);
      expect(v.darkChannels, [2]);
      expect(slot(v, 1).faults, [LadderFault.channelOff]);
    });

    test('a participating bus missing from seg — dark', () {
      final l = builtLadder(threeBus)..[1] = onPreset(const [0, 1]);
      final v = verdictWith(l);
      expect(v.darkChannels, [2]);
      expect(slot(v, 1).faults, [LadderFault.channelAbsent]);
    });

    test('segment opacity 0 — dark', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, overrides: {
          0: {'id': 0, 'on': true, 'bri': 0, 'fx': 0, 'col': baseLookColSlots()},
        });
      expect(slot(verdictWith(l), 1).faults,
          [LadderFault.channelOpacityZero]);
    });

    test('no seg at all (the pre-BASE_LADDER shape) — every bus dark', () {
      final l = builtLadder(threeBus)..[1] = {'on': true, 'bri': 200};
      final p = slot(verdictWith(l), 1);
      expect(p.faults, [LadderFault.noSegments]);
      expect(p.channels, threeBus);
    });
  });

  group('participation decides which buses must light', () {
    test('a NON-participating bus that is off does not fail the ladder', () {
      // Bus 2 is deliberately out of shows; whatever the ladder does there is
      // the customer's business, not a restore failure.
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, overrides: {
          2: {'id': 2, 'on': false},
        });
      final v = verdictWith(l, participating: const [0, 1]);
      expect(v.restoreLit, isTrue);
      expect(v.darkChannels, isEmpty);
    });
  });

  group('the OFF preset darkens every DEVICE bus', () {
    test('root on:false is dark whatever the segments say', () {
      final l = builtLadder(threeBus)
        ..[2] = {
          'on': false,
          'seg': [
            {'id': 0, 'on': true},
          ],
        };
      expect(slot(verdictWith(l), 2).ok, isTrue);
    });

    test('root on absent but every bus named off — dark', () {
      final l = builtLadder(threeBus)
        ..[2] = {
          'seg': [
            for (final id in threeBus) {'id': id, 'on': false},
          ],
        };
      expect(slot(verdictWith(l), 2).ok, isTrue);
    });

    test('a bus left on — off_leaves_lit, even if it is not participating', () {
      final l = builtLadder(threeBus)
        ..[2] = {
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'on': false},
            {'id': 2, 'on': true},
          ],
        };
      final v = verdictWith(l, participating: const [0, 1]);
      final p = slot(v, 2);
      expect(p.faults, [LadderFault.offLeavesLit]);
      expect(p.channels, [2]);
      expect(v.restoreLit, isFalse);
      expect(v.darkChannels, isEmpty,
          reason: 'dark_channels reports the ON half only');
      expect(v.badPresetIds, [2]);
    });
  });

  group('missing presets', () {
    test('a missing preset 1 fails the ladder (a restore can load it)', () {
      final l = builtLadder(threeBus)..remove(1);
      final v = verdictWith(l);
      expect(v.restoreLit, isFalse);
      expect(v.missingPresetIds, [1]);
      expect(v.badPresetIds, isEmpty, reason: 'nothing PRESENT is bad');
    });

    test('a missing preset 2 fails the ladder', () {
      final l = builtLadder(threeBus)..remove(2);
      expect(verdictWith(l).restoreLit, isFalse);
    });

    test('a missing 3/4/5 is reported but does not fail the ladder', () {
      final l = builtLadder(threeBus)
        ..remove(3)
        ..remove(5);
      final v = verdictWith(l);
      expect(v.restoreLit, isTrue);
      expect(v.missingPresetIds, [3, 5]);
    });

    test('a controller holding no presets is a REAL false, not unmeasured', () {
      final v = verdictWith(const {});
      expect(v.restoreLit, isFalse);
      expect(v.missingPresetIds, [1, 2, 3, 4, 5]);
    });
  });

  group('tri-state — never false for "could not look"', () {
    test('presets unreadable → null', () {
      expect(
        evaluateLadderRestore(
            presets: null, participating: threeBus, deviceChannelIds: threeBus),
        isNull,
      );
    });

    test('participation unknown or empty → null', () {
      expect(
        evaluateLadderRestore(
            presets: builtLadder(threeBus),
            participating: const [],
            deviceChannelIds: threeBus),
        isNull,
      );
    });

    test('bus list unknown → null', () {
      expect(
        evaluateLadderRestore(
            presets: builtLadder(threeBus),
            participating: threeBus,
            deviceChannelIds: const []),
        isNull,
      );
    });
  });

  group('the fact family', () {
    setUp(resetLadderRestoreMemo);

    test('publishes restore_lit + dark list + the shared stamp fields', () {
      final l = builtLadder(threeBus)
        ..[1] = onPreset(threeBus, overrides: {
          1: {'id': 1, 'on': false},
        });
      final f = prepareLadderRestoreFacts(
        controllerId: 'c1',
        verdict: verdictWith(l),
        source: 'healer',
      );
      expect(f.fields[kBaseLadderRestoreLitField], isFalse);
      expect(f.fields[kBaseLadderDarkChannelsField], [1]);
      expect(f.fields[factSourceField(kBaseLadderRestoreLitField)], 'healer');
      expect(f.fields[factAtField(kBaseLadderRestoreLitField)],
          isA<FieldValue>());
      expect(f.fields[factPublishCountField(kBaseLadderRestoreLitField)],
          isA<FieldValue>());
    });

    test('unmeasured contributes nothing', () {
      expect(
        prepareLadderRestoreFacts(
                controllerId: 'c1', verdict: null, source: 'healer')
            .isEmpty,
        isTrue,
      );
    });

    test('an unchanged verdict is deduped after a committed write', () {
      final v = verdictWith(builtLadder(threeBus));
      prepareLadderRestoreFacts(controllerId: 'c1', verdict: v, source: 'h')
          .commit();
      expect(
        prepareLadderRestoreFacts(controllerId: 'c1', verdict: v, source: 'h')
            .isEmpty,
        isTrue,
      );
    });

    test('a changed dark list republishes with _previous', () {
      final good = verdictWith(builtLadder(threeBus));
      prepareLadderRestoreFacts(controllerId: 'c1', verdict: good, source: 'h')
          .commit();
      final bad = verdictWith(builtLadder(threeBus)
        ..[1] = onPreset(threeBus, rootOn: null));
      final f =
          prepareLadderRestoreFacts(controllerId: 'c1', verdict: bad, source: 'h');
      expect(f.isEmpty, isFalse);
      expect(f.fields[factPreviousField(kBaseLadderRestoreLitField)], isTrue);
    });

    test('preparing without committing leaves the retry available', () {
      final v = verdictWith(builtLadder(threeBus));
      prepareLadderRestoreFacts(controllerId: 'c1', verdict: v, source: 'h');
      expect(
        prepareLadderRestoreFacts(controllerId: 'c1', verdict: v, source: 'h')
            .isEmpty,
        isFalse,
      );
    });
  });
}
