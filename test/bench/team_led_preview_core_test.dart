// The team LED bench preview's safety rules, pinned: the live home controller
// is refused, a payload can only be live state, and restore is the exact
// inverse of a preview. The CLI (bench/bin/team_led_preview.dart) is the
// hardware half; this locks the logic it trusts.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bench/src/team_led_preview_core.dart';

void main() {
  group('never the live home controller', () {
    test('refused by address', () {
      expect(refuseHost('192.168.1.150'), isNotNull);
      expect(refuseHost(' 192.168.1.150 '), isNotNull);
    });

    test('refused when a hostname resolves to it', () {
      expect(refuseHost('wled-home', resolved: ['192.168.1.150']), isNotNull);
    });

    test('refused when the controller itself reports that ip', () {
      expect(refuseInfo({'ip': '192.168.1.150'}), isNotNull);
    });

    test('the spare is allowed', () {
      expect(refuseHost(kSpareControllerIp, resolved: [kSpareControllerIp]),
          isNull);
      expect(refuseInfo({'ip': kSpareControllerIp}), isNull);
    });
  });

  group('live state only', () {
    for (final key in ['psave', 'pdel', 'ps', 'pl', 'playlist', 'rb']) {
      test('"$key" is refused at any depth', () {
        expect(() => assertLiveStateOnly({key: 1}), throwsStateError);
        expect(
            () => assertLiveStateOnly({
                  'seg': [
                    {'id': 0, key: 1}
                  ]
                }),
            throwsStateError);
      });
    }

    for (final key in ['ib', 'sb', 'n', 'ql', 'np']) {
      test('top-level "$key" is refused', () {
        expect(() => assertLiveStateOnly({key: true}), throwsStateError);
      });
    }

    test('every preview view builds a clean live-state payload', () {
      for (final view in PreviewView.values) {
        final p = buildPreviewPayload(
          segIds: const [0, 1],
          view: view,
          primaryRgb: const [0, 255, 31],
          secondaryRgb: const [255, 180, 13],
          bri: 128,
          blockSize: 15,
        );
        expect(() => assertLiveStateOnly(p), returnsNormally);
        expect(p['tt'], 0, reason: 'one-shot transition, nothing to restore');
        expect(p.containsKey('transition'), isFalse);
        final segs = (p['seg'] as List).cast<Map>();
        expect(segs.map((s) => s['id']), [0, 1],
            reason: 'only segments that already exist');
        for (final s in segs) {
          expect(s.containsKey('start'), isFalse, reason: 'never re-bounds');
          expect(s.containsKey('stop'), isFalse);
        }
      }
    });
  });

  group('preview payloads', () {
    test('blocks = Solid Pattern (83), col0 bands against col1 bands', () {
      final p = buildPreviewPayload(
        segIds: const [0],
        view: PreviewView.blocks,
        primaryRgb: const [0, 255, 31],
        secondaryRgb: const [255, 180, 13],
        bri: 128,
        blockSize: 15,
      );
      final s = (p['seg'] as List).single as Map;
      expect(s['fx'], 83);
      expect(s['pal'], 0);
      expect(s['sx'], 14);
      expect(s['ix'], 14);
      expect(s['col'], [
        [0, 255, 31, 0],
        [255, 180, 13, 0],
        [0, 0, 0, 0],
      ]);
    });

    test('secondary view leads with the secondary on Solid', () {
      final p = buildPreviewPayload(
        segIds: const [0],
        view: PreviewView.secondary,
        primaryRgb: const [1, 2, 3],
        secondaryRgb: const [4, 5, 6],
        bri: 128,
        blockSize: 15,
      );
      final s = (p['seg'] as List).single as Map;
      expect(s['fx'], 0);
      expect((s['col'] as List).first, [4, 5, 6, 0]);
    });

    test('A/B: brand vs LED for Packers green', () {
      expect(previewRgb(0x203731, led: false), [0x20, 0x37, 0x31]);
      expect(previewRgb(0x203731, led: true), [0, 255, 31]);
    });

    test('gamma emulation darkens midtones, keeps the ends', () {
      expect(emulateGamma([0, 128, 255]), [0, 37, 255]);
    });
  });

  group('restore', () {
    final captured = <String, dynamic>{
      'on': false,
      'bri': 77,
      'ps': -1,
      'transition': 7,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': 120,
          'n': 'Front',
          'on': true,
          'frz': false,
          'bri': 255,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'fx': 9,
          'sx': 128,
          'ix': 128,
          'pal': 11,
          'c1': 5,
          'col': [
            [255, 160, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
          ],
        },
      ],
    };

    test('puts back exactly what a preview touches — and nothing else', () {
      final r = buildRestorePayload(captured);
      expect(() => assertLiveStateOnly(r), returnsNormally);
      expect(r['on'], false);
      expect(r['bri'], 77);
      expect(r.containsKey('ps'), isFalse, reason: 'never loads a preset');
      final s = (r['seg'] as List).single as Map;
      expect(s.keys.toSet(), {'id', ...kTouchedSegFields});
      expect(s['fx'], 9);
      expect(s['pal'], 11);
      expect(s['col'], (captured['seg'] as List).single['col']);
    });

    test('every field a preview writes is one restore puts back', () {
      final p = buildPreviewPayload(
        segIds: const [0],
        view: PreviewView.blocks,
        primaryRgb: const [0, 255, 31],
        secondaryRgb: const [255, 180, 13],
        bri: 128,
        blockSize: 15,
      );
      final written = ((p['seg'] as List).single as Map).keys.toSet()
        ..remove('id');
      expect(kTouchedSegFields.toSet().containsAll(written), isTrue);
    });

    test('diff is empty when the readback matches, and names what does not',
        () {
      expect(restoreDiff(captured, captured), isEmpty);
      final drifted = {
        ...captured,
        'bri': 128,
        'seg': [
          {...(captured['seg'] as List).single as Map, 'fx': 83},
        ],
      };
      expect(restoreDiff(captured, drifted), ['bri: 77 → 128', 'seg 0.fx: 9 → 83']);
    });
  });

  group('team list', () {
    final teams = parseTeams(File(
            'lib/features/sports_alerts/data/team_colors.dart')
        .readAsStringSync());

    test('parses every kTeamColors entry, Packers first', () {
      expect(teams.length, greaterThan(400));
      expect(teams.first.slug, 'nfl_packers');
      expect(teams.first.primary, 0x203731);
      expect(teams.first.secondary, 0xFFB612);
    });

    test('league filter and start slug', () {
      final nfl = selectTeams(teams, leagues: const ['nfl']);
      expect(nfl.length, 32);
      expect(nfl.every((t) => t.slug.startsWith('nfl_')), isTrue);
      final fromBears = selectTeams(teams, leagues: const ['nfl'],
          startSlug: 'nfl_bears');
      expect(fromBears.first.slug, 'nfl_bears');
    });

    test('problem classes parse from the table comments', () {
      final classes = parseProblemClasses(
          File('lib/data/team_led_colors.dart').readAsStringSync());
      expect(classes[0x203731], 'dark green→teal');
      expect(classes[0x002244], 'navy→purple');
    });
  });
}
