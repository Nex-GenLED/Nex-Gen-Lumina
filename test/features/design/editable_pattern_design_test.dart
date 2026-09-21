// The Pattern Editor's "Save" → a CustomDesign in My Designs.
//
// Replaces "SAVE TO DEVICE" (a WLED psave nothing could read back, which for a
// Static pattern stored a black frozen shell). Every assertion here ties the
// SAVED design to the editor's own LIVE payload, so what is kept is what was
// on the lights.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/services/user_service.dart';

const _red = Color(0xFFE31837);
const _gold = Color(0xFFFFB81C);
const _white = Color(0xFFFFFFFF);

const _bench = [
  PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
  PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
];

/// What colorway_effect_selector builds for the NFL Chiefs card, plus the
/// user's edit (a third colour).
EditablePattern _chiefs({int fx = 0, List<Color>? colors, int grp = 1}) =>
    EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [_red, _gold],
      effectId: fx,
      speed: 85,
      intensity: 180,
      brightness: 140,
    ).copyWith(actionColors: colors ?? const [_red, _gold, _white], colorGroupSize: grp);

CustomDesign _save(EditablePattern p,
        {List<PatternEditorChannel> channels = _bench, String? name}) =>
    customDesignFromEditablePattern(
      pattern: p,
      name: name ?? p.name,
      ownerId: 'u1',
      channels: channels,
      now: DateTime(2026, 9, 21),
    );

/// The colour the editor's LIVE Static write puts on channel-local LED [i].
/// `i` indices are segment-local, and the channel filter clones the one
/// template segment onto each channel — so every channel restarts at entry 0.
List<int> _liveStaticColor(EditablePattern p, int i) {
  final iArray = ((p.toWledPayload(290)['seg'] as List).first as Map)['i'] as List;
  expect(iArray[i * 2], i);
  return (iArray[i * 2 + 1] as List).cast<int>();
}

void main() {
  group('Static → a painted (per-pixel) design', () {
    test('is STATED per-pixel, so My Designs applies it through the spine and '
        'Edit opens the paint editor', () {
      final d = _save(_chiefs());
      expect(d.perPixel, isTrue);
      expect(d.isPositional, isTrue);
      expect(designKindOf(d), DesignKind.perPixel);
    });

    test('every LED of every channel equals the editor\'s live write', () {
      final p = _chiefs();
      final d = _save(p);
      // Reopen exactly as ManualDesignEditor does.
      final doc = PixelDesignDocument.fromLedColorGroups(
        baseColor: const [10, 10, 12, 0],
        channelLengths: {for (final c in _bench) c.id: c.ledCount},
        groupsByChannel: {for (final c in d.channels) c.channelId: c.colorGroups},
      );
      var checked = 0;
      for (final c in _bench) {
        for (int i = 0; i < c.ledCount; i++) {
          expect(doc.colorAt(c.id, i), _liveStaticColor(p, i),
              reason: 'channel ${c.id} LED $i');
          checked++;
        }
      }
      expect(checked, 290);
    });

    test('what reaches the spine is the same picture — spans cover every LED',
        () {
      final d = _save(_chiefs());
      final spans = customDesignToSpans(d);
      expect(spans.keys.toSet(), {0, 1});
      for (final c in _bench) {
        final covered = spans[c.id]!.fold<int>(0, (n, s) => n + s.end - s.start + 1);
        expect(covered, c.ledCount);
      }
    });

    test('ALL 15 layers survive — nothing is limited to three colours', () {
      final fifteen = [
        for (int k = 0; k < 15; k++) Color.fromARGB(255, 10 + k * 16, 255 - k * 16, k * 7),
      ];
      final p = _chiefs(colors: fifteen);
      final d = _save(p);
      final seen = <String>{
        for (final g in d.channels.first.colorGroups) g.color.join(','),
      };
      expect(seen, hasLength(15));
      expect(seen, {for (final c in p.staticColorsRgbw()) c.join(',')});
    });

    test('grouping (N LEDs per colour) is baked into the picture', () {
      final p = _chiefs(grp: 3);
      final d = _save(p);
      final groups = d.channels.first.colorGroups;
      expect(groups.first.startLed, 0);
      expect(groups.first.endLed, 2); // three reds
      expect(groups[1].startLed, 3);
      for (int i = 0; i < 128; i++) {
        final g = groups.firstWhere((g) => i >= g.startLed && i <= g.endLed);
        expect(g.color, _liveStaticColor(p, i));
      }
    });

    test('a ONE-colour Static pattern is still a painted design — shape alone '
        'would class it an effect and send it through the 3-colour path', () {
      final d = _save(_chiefs(colors: const [_red]));
      expect(d.channels.first.colorGroups, hasLength(1));
      expect(d.channels.first.tilesItsChannel, isFalse,
          reason: 'one run does not "tile" — the stored marker must carry it');
      expect(d.isPositional, isTrue);
    });

    test('only the targeted channels are saved', () {
      final d = _save(_chiefs(), channels: [_bench.first]);
      expect(d.channels.map((c) => c.channelId), [0]);
    });

    test('with no LED counts there is no picture to store — it refuses rather '
        'than save a guess', () {
      expect(() => _save(_chiefs(), channels: const []), throwsStateError);
      expect(
          () => _save(_chiefs(), channels: const [
                PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 0)
              ]),
          throwsStateError);
    });
  });

  group('Animated → an effect design', () {
    Map<String, dynamic> liveSeg(EditablePattern p) =>
        ((p.toWledPayload(290)['seg'] as List).first as Map).cast<String, dynamic>();

    test('re-applies with the editor\'s own colours, effect, speed, intensity, '
        'grouping and brightness', () {
      final p = _chiefs(fx: 12, grp: 2);
      final d = _save(p);
      expect(d.isPositional, isFalse);
      expect(designKindOf(d), DesignKind.effect);

      final live = liveSeg(p);
      final payload = d.toWledPayload();
      expect(payload['bri'], p.toWledPayload(290)['bri']);
      expect(payload['bri'], 140);
      final segs = (payload['seg'] as List).cast<Map>();
      expect(segs.map((s) => s['id']), [0, 1], reason: 'every targeted channel');
      for (final s in segs) {
        expect(s['col'], live['col']);
        expect(s['fx'], live['fx']);
        expect(s['sx'], live['sx']);
        expect(s['ix'], live['ix']);
        expect(s['grp'], live['grp']);
        expect(s['spc'], live['spc']);
        // Unstated, it was inherited from the previous look: over a per-pixel
        // apply's `pal: 0` the third colour vanished (bench 2026-09-21).
        expect(s['pal'], live['pal']);
        expect(s['pal'], 5);
      }
    });

    test('layers beyond the third are KEPT in the document, and the first '
        'three are exactly what the lights show', () {
      final five = const [_red, _gold, _white, Color(0xFF00FF00), Color(0xFF0000FF)];
      final p = _chiefs(fx: 12, colors: five);
      expect(p.hasLayersBeyondEffectSlots, isTrue);
      final d = _save(p);
      expect(d.channels.first.colorGroups, hasLength(5));
      expect(((d.toWledPayload()['seg'] as List).first as Map)['col'],
          liveSeg(p)['col']);
      expect(d.isPositional, isFalse,
          reason: 'palette groups must never read as a painted picture');
    });

    test('the background colour rides in slot 3, as it does live', () {
      final p = _chiefs(fx: 17, colors: const [_red])
          .copyWith(backgroundColor: const Color(0xFF000040));
      final d = _save(p);
      expect([for (final g in d.channels.first.colorGroups) g.color],
          p.effectColorSlots());
      expect(p.effectColorSlots(), hasLength(3));
    });

    test('Static never reports lost layers; a 3-colour effect does not either',
        () {
      expect(_chiefs(fx: 0, colors: List.filled(9, _red)).hasLayersBeyondEffectSlots,
          isFalse);
      expect(_chiefs(fx: 12).hasLayersBeyondEffectSlots, isFalse);
    });

    test('saves offline (no channel census) as one "All" channel', () {
      final d = _save(_chiefs(fx: 12), channels: const []);
      expect(d.channels.single.channelId, 0);
      expect(d.channels.single.channelName, 'All');
    });
  });

  group('identity — no slot, no hash, no collision', () {
    test('a new design has NO id, so DesignService creates it with `.add()`',
        () {
      expect(_save(_chiefs()).id, isEmpty);
    });

    test('the source card\'s id appears nowhere in the stored document — two '
        'saves from one card cannot share an identity', () {
      for (final fx in [0, 12]) {
        final stored = _save(_chiefs(fx: fx)).toFirestore().toString();
        expect(stored.contains('team_nfl_chiefs'), isFalse);
      }
    });

    test('uniqueDesignName keeps same-card saves distinguishable', () {
      expect(uniqueDesignName('Kansas City Chiefs', const []), 'Kansas City Chiefs');
      expect(uniqueDesignName('Kansas City Chiefs', const ['kansas city chiefs ']),
          'Kansas City Chiefs 2');
      expect(
          uniqueDesignName('Kansas City Chiefs',
              const ['Kansas City Chiefs', 'Kansas City Chiefs 2']),
          'Kansas City Chiefs 3');
    });

    test('name, provenance and brightness are stored', () {
      final d = _save(_chiefs(), name: 'Chiefs + White');
      expect(d.name, 'Chiefs + White');
      expect(d.tags, contains(kPatternEditorDesignTag));
      expect(d.brightness, 140);
      expect(d.ownerId, 'u1');
    });
  });

  group('Firestore round trip', () {
    for (final fx in [0, 12]) {
      test('fx $fx survives toFirestore → fromFirestoreData unchanged', () {
        final d = _save(_chiefs(fx: fx));
        final data = UserService.sanitizeForFirestore(d.toFirestore());
        final back = CustomDesign.fromFirestoreData('auto123', data);
        expect(back.name, d.name);
        expect(back.perPixel, d.perPixel);
        expect(back.isPositional, d.isPositional);
        expect(back.brightness, d.brightness);
        expect(back.channels.length, d.channels.length);
        for (int c = 0; c < d.channels.length; c++) {
          final a = d.channels[c], b = back.channels[c];
          expect(b.channelId, a.channelId);
          expect(b.ledCount, a.ledCount);
          expect(b.effectId, a.effectId);
          expect(b.grouping, a.grouping);
          expect([for (final g in b.colorGroups) '${g.startLed}-${g.endLed}:${g.color}'],
              [for (final g in a.colorGroups) '${g.startLed}-${g.endLed}:${g.color}']);
        }
      });
    }
  });
}
