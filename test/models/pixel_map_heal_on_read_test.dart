// HEAL-ON-READ for pixelMap documents written before +101.
//
// FIXTURES ARE THE REAL SHAPES. Every home below is a production controller's
// pixelMap as found by the read-only dry-run of 2026-09-19
// (release-101-report §4 / scripts/_dryrun_pixelmap_rebase.js): channel index,
// segment count, each segment's stored `start_pixel` and `pixel_count`, and the
// channel's `source_pixel_count`. They are given as raw Firestore-shaped maps —
// what PixelMapChannel.fromJson actually receives — and identified by LETTER;
// no customer identifier appears here.
//
// Two things the dry-run did NOT record, stated so nothing is passed off as
// real: segment names/ids (synthetic here), and anchor POSITIONS. It recorded
// only that homes F and G carry 2 anchors per doc; the fixtures place them at
// the app's own default for a `run` — [0, pixelCount − 2] — which is what the
// editor's "Reset Defaults" writes.
//
// The expected values are §4's computed corrections, reused as the oracle:
//   A ch1 [33]→[0]   A ch2 [44]→[0]   C ch0 [32]→[0]   D ch1 [41]→[0]
//   E ch1 [40]→[0]   F ch1 [44]→[0]   G ch0 [128]→[0]
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_logic.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

Map<String, dynamic> _seg(int ch, int i, int start, int count, {List<int> anchors = const []}) => {
      'id': 'ch${ch}_seg$i',
      'name': 'Run ${i + 1}',
      'pixel_count': count,
      'start_pixel': start,
      'type': 'run',
      'anchor_pixels': anchors,
      'anchor_led_count': 2,
      'sort_order': i,
      'channel_index': ch,
    };

Map<String, dynamic> _doc(int ch, int source, List<Map<String, dynamic>> segs) => {
      'channel_index': ch,
      'segments': segs,
      'source_pixel_count': source,
      'map_version': 1,
      'created_by': 'fixture',
      'is_stale': false, // true of all 28 production docs
    };

/// home → channel docs, exactly as stored.
final Map<String, List<Map<String, dynamic>>> kHomes = {
  // A: 3 channels. ch0 partial+OK, ch1 REBASE (also partial), ch2 REBASE+OVERFLOW.
  'A': [
    _doc(0, 165, [_seg(0, 0, 0, 33)]),
    _doc(1, 46, [_seg(1, 0, 33, 11)]),
    _doc(2, 8, [_seg(2, 0, 44, 12)]),
  ],
  // B: PARTIAL only — two segments, 93 of 236 mapped.
  'B': [_doc(0, 236, [_seg(0, 0, 0, 51), _seg(0, 1, 51, 42)])],
  // C: REBASE on CHANNEL 0 (the channel-2 segment sat first in the list).
  'C': [_doc(0, 22, [_seg(0, 0, 32, 22)]), _doc(1, 32, [_seg(1, 0, 0, 32)])],
  // D: REBASE on ch1; ch0 has two healthy segments.
  'D': [_doc(0, 41, [_seg(0, 0, 0, 28), _seg(0, 1, 28, 13)]), _doc(1, 41, [_seg(1, 0, 41, 41)])],
  // E: REBASE on ch1.
  'E': [_doc(0, 40, [_seg(0, 0, 0, 40)]), _doc(1, 40, [_seg(1, 0, 40, 40)])],
  // F: ch0 partial (44/45); ch1 REBASE+OVERFLOW (45 on a 44-LED strip). 2 anchors each.
  'F': [
    _doc(0, 45, [_seg(0, 0, 0, 44, anchors: [0, 42])]),
    _doc(1, 44, [_seg(1, 0, 44, 45, anchors: [0, 43])]),
  ],
  // G: ch0 REBASE+OVERFLOW (168 on a 128-LED strip); ch1 partial (128/162). 2 anchors each.
  'G': [
    _doc(0, 128, [_seg(0, 0, 128, 168, anchors: [0, 166])]),
    _doc(1, 162, [_seg(1, 0, 0, 128, anchors: [0, 126])]),
  ],
  // H: PARTIAL only — 47 of 177.
  'H': [_doc(0, 177, [_seg(0, 0, 0, 47)])],
};

List<PixelMapChannel> _load(String home) => [
      for (final d in kHomes[home]!)
        PixelMapChannel.fromJson('ctrl-$home', '${d['channel_index']}',
            // A deep copy, so the fixture itself can be compared afterwards.
            jsonDecode(jsonEncode(d)) as Map<String, dynamic>),
    ];

RooflineConfiguration _config(String home) =>
    aggregatePixelMapChannelsToConfig('ctrl-$home', _load(home));

List<int> _starts(RooflineConfiguration c, int ch) =>
    [for (final s in c.segmentsForChannel(ch)) s.startPixel];

/// (home, channel) → §4's corrected start_pixel list.
const _affected = <(String, int), List<int>>{
  ('A', 1): [0], ('A', 2): [0], ('C', 0): [0], ('D', 1): [0],
  ('E', 1): [0], ('F', 1): [0], ('G', 0): [0],
};

void main() {
  test('the fixture set is §4: 7 affected docs in 6 homes, 6 partial, none stale-flagged', () {
    int affected = 0, partial = 0;
    final homes = <String>{};
    for (final home in kHomes.keys) {
      for (final ch in _load(home)) {
        if (ch.storedStartPixelsAreOffset) {
          affected++;
          homes.add(home);
          expect(_affected.containsKey((home, ch.channelIndex)), isTrue);
        }
        if (ch.mappedPixelCount < ch.sourcePixelCount) partial++;
        expect(ch.isStale, isFalse);
      }
    }
    expect([affected, homes.length, partial], [7, 6, 6]);
  });

  group('every affected doc loads with §4\'s corrected indices', () {
    for (final e in _affected.entries) {
      final (home, ch) = e.key;
      test('home $home channel $ch → start_pixel ${e.value}', () {
        final stored = _load(home).firstWhere((c) => c.channelIndex == ch);
        expect(stored.segments.first.startPixel, isNot(0), reason: 'fixture really is offset');
        expect(_starts(_config(home), ch), e.value);
      });
    }

    test('only start_pixel changes — counts, anchors, order, ids all survive', () {
      for (final home in kHomes.keys) {
        final raw = _load(home);
        final cfg = _config(home);
        for (final ch in raw) {
          final healed = cfg.segmentsForChannel(ch.channelIndex);
          expect(healed.length, ch.segments.length);
          for (int i = 0; i < healed.length; i++) {
            final a = ch.segments[i], b = healed[i];
            expect([b.id, b.name, b.pixelCount, b.anchorPixels, b.anchorLedCount, b.type, b.sortOrder, b.channelIndex],
                [a.id, a.name, a.pixelCount, a.anchorPixels, a.anchorLedCount, a.type, a.sortOrder, a.channelIndex]);
          }
        }
      }
    });

    test('OVERFLOW docs keep their pixel_count — the overshoot is NOT guessed away', () {
      expect(_config('G').segmentsForChannel(0).single.pixelCount, 168);
      expect(_config('F').segmentsForChannel(1).single.pixelCount, 45);
      expect(_config('A').segmentsForChannel(2).single.pixelCount, 12);
    });
  });

  group('Step 3 — partial and healthy docs are not touched AT ALL', () {
    test('healedForRead returns the very same object', () {
      int checked = 0, partial = 0;
      for (final home in kHomes.keys) {
        for (final ch in _load(home)) {
          if (_affected.containsKey((home, ch.channelIndex))) continue;
          expect(identical(ch.healedForRead(), ch), isTrue, reason: 'home $home ch${ch.channelIndex}');
          checked++;
          if (ch.mappedPixelCount < ch.sourcePixelCount) partial++;
        }
      }
      expect([checked, partial], [8, 5], reason: '5 partial + 3 healthy siblings');
    });

    test('the 6th partial doc is ALSO a REBASE doc (home A, 11 of 46): re-based, still partial', () {
      final stored = _load('A').firstWhere((c) => c.channelIndex == 1);
      final healed = stored.healedForRead();
      expect(healed.segments.single.startPixel, 0, reason: '§4: [33] → [0]');
      expect([healed.mappedPixelCount, healed.sourcePixelCount], [11, 46],
          reason: 'coverage is untouched — a partial map is not "completed" by the heal');
    });

    test('their in-memory segments equal their stored segments', () {
      for (final home in ['B', 'H']) {
        final raw = _load(home).single;
        expect(_config(home).segmentsForChannel(0), raw.segments);
      }
      expect(_starts(_config('B'), 0), [0, 51]);
      expect(_starts(_config('D'), 0), [0, 28], reason: 'healthy sibling of a healed channel');
    });
  });

  group('downstream consumers behave correctly on the healed model', () {
    test('"All runs" reaches the whole channel (was 0 LEDs on five of the seven)', () {
      const expectedReach = {
        ('A', 1): 11, ('A', 2): 8, ('C', 0): 22, ('D', 1): 41, ('E', 1): 40, ('F', 1): 44, ('G', 0): 128,
      };
      for (final e in expectedReach.entries) {
        final (home, ch) = e.key;
        final stored = _load(home).firstWhere((c) => c.channelIndex == ch);
        final len = stored.sourcePixelCount;
        int reach(List segs) => featureIndices(segs.cast(), FeatureFilter.allRuns)
            .where((i) => i >= 0 && i < len).length;
        final before = reach(stored.segments);
        final after = reach(_config(home).segmentsForChannel(ch));
        expect(after, e.value, reason: 'home $home ch$ch (before: $before)');
        expect(after, greaterThanOrEqualTo(before));
      }
    });

    test('painting through the editor document lands on the right LEDs (home D ch1)', () {
      final cfg = _config('D');
      final doc = PixelDesignDocument.blank(baseColor: const [10, 10, 12, 0], channelLengths: const {0: 41, 1: 41})
          .paint(1, featureIndices(cfg.segmentsForChannel(1), FeatureFilter.allRuns), const [255, 0, 0, 0]);
      expect(doc.paintedCount, 41, reason: 'stored start 41 on a 41-LED channel painted NOTHING');
      expect(doc.isPainted(1, 0), isTrue);
      expect(doc.isPainted(1, 40), isTrue);
    });

    test('Anchors tool: home F ch1 and home G ch0', () {
      // F ch1: anchors [0, 43] ×2 LEDs on a 44-LED strip → 0,1,43 fit (44 is past the end).
      final f = anchorIndices(_config('F').segmentsForChannel(1)).where((i) => i < 44).toSet();
      expect(f, {0, 1, 43});
      // G ch0: anchors [0, 166] on a 128-LED strip → the far anchor is the
      // OVERSHOOT and genuinely does not exist; the near one now lands.
      final g = anchorIndices(_config('G').segmentsForChannel(0)).where((i) => i < 128).toSet();
      expect(g, {0, 1}, reason: 'stored start 128 → {128,129,294,295}: nothing on the strip');
      final storedG = _load('G').first.segments;
      expect(anchorIndices(storedG).where((i) => i < 128), isEmpty);
    });

    test('smart-preset feature detection: spans are in range; run-only maps still yield none', () {
      for (final home in kHomes.keys) {
        final cfg = _config(home);
        final bus = {for (final c in _load(home)) c.channelIndex: c.sourcePixelCount};
        for (final kind in SmartPresetKind.values) {
          final spans = compileAccentSpans(config: cfg, kind: kind, accentRgbw: const [0, 229, 255, 0], busLenByChannel: bus);
          for (final e in spans.entries) {
            expect(e.value, isEmpty, reason: 'every production segment is a plain run (F5) — heal-on-read does not invent features');
          }
        }
      }
    });

    test('feature detection finds a feature on a healed channel (derived variant of home D)', () {
      // DERIVED, and labelled as such: home D ch1 exactly as stored (start 41,
      // 41 px, 41-LED strip) with ONE change — type corner instead of run —
      // because no production doc has a feature to detect (audit F5).
      final d = jsonDecode(jsonEncode(kHomes['D']!)) as List;
      ((d[1] as Map)['segments'] as List).first['type'] = 'corner';
      final raw = [
        for (final m in d)
          PixelMapChannel.fromJson('ctrl-D', '${m['channel_index']}', m as Map<String, dynamic>),
      ];
      List<List<int>> spans(List<PixelMapChannel> channels, {required bool healed}) {
        final segs = healed
            ? aggregatePixelMapChannelsToConfig('ctrl-D', channels).segmentsForChannel(1)
            : channels[1].segments;
        return [
          for (final s in accentSpansForChannel(
              segments: segs, kind: SmartPresetKind.cornerAccents,
              accentRgbw: const [0, 229, 255, 0], busLen: 41))
            [s.start, s.end],
        ];
      }
      expect(spans(raw, healed: false), isEmpty, reason: 'stored start 41 lies past the 41-LED strip → dropped');
      expect(spans(raw, healed: true), [[0, 40]]);
    });

    test('whole-controller translation is bounded to the strip (overshoot does not bleed into the next channel)', () {
      final g = _config('G');
      final ch0 = g.segmentsForChannel(0).single, ch1 = g.segmentsForChannel(1).single;
      expect([g.globalStartOf(ch0), g.globalEndOf(ch0)], [0, 127], reason: '168 px on a 128-LED strip');
      expect([g.globalStartOf(ch1), g.globalEndOf(ch1)], [128, 255]);
      expect(g.segmentForPixel(127)!.channelIndex, 0);
      expect(g.segmentForPixel(128)!.channelIndex, 1, reason: 'was claimed by the channel-1 overshoot');
    });
  });

  group('the "remap" signal stays ON — behaviour is corrected, staleness is not hidden', () {
    test('all 7 still report needsRemap from their STORED values', () {
      for (final e in _affected.keys) {
        final (home, ch) = e;
        final stored = _load(home).firstWhere((c) => c.channelIndex == ch);
        expect(stored.needsRemapAgainst(stored.sourcePixelCount), isTrue, reason: 'home $home ch$ch');
      }
    });

    test('after a real save the REBASE docs clear; the OVERFLOW docs stay flagged', () {
      const overflow = {('A', 2), ('F', 1), ('G', 0)};
      for (final home in kHomes.keys) {
        final raw = _load(home);
        // What the owner's next ordinary save would write (heal-on-save, +101).
        final saved = splitConfigToPixelMapChannels(_config(home),
            controllerId: 'ctrl-$home',
            sourceCounts: {for (final c in raw) c.channelIndex: c.sourcePixelCount},
            now: DateTime(2026, 9, 19));
        for (final s in saved) {
          final key = (home, s.channelIndex);
          expect(s.storedStartPixelsAreOffset, isFalse);
          expect(s.needsRemapAgainst(s.sourcePixelCount), overflow.contains(key), reason: 'home $home ch${s.channelIndex}');
        }
      }
    });
  });

  test('NOTHING is mutated: fixtures and loaded docs are byte-identical after every consumer ran', () {
    final before = jsonEncode(kHomes);
    for (final home in kHomes.keys) {
      final raw = _load(home);
      final rawJson = jsonEncode([for (final c in raw) [c.channelIndex, for (final s in c.segments) [s.startPixel, s.pixelCount, s.anchorPixels]]]);
      final cfg = _config(home);
      for (final ch in cfg.allChannelIndices) {
        featureIndices(cfg.segmentsForChannel(ch), FeatureFilter.allRuns);
        anchorIndices(cfg.segmentsForChannel(ch));
      }
      aggregatePixelMapChannelsToConfig('ctrl-$home', raw); // again, from the SAME loaded objects
      for (final c in raw) {
        c.healedForRead();
      }
      expect(jsonEncode([for (final c in raw) [c.channelIndex, for (final s in c.segments) [s.startPixel, s.pixelCount, s.anchorPixels]]]), rawJson,
          reason: 'home $home: the loaded (stored-shape) docs were changed');
    }
    expect(jsonEncode(kHomes), before);
  });

  test('healing is idempotent', () {
    for (final home in kHomes.keys) {
      for (final ch in _load(home)) {
        final once = ch.healedForRead();
        expect(identical(once.healedForRead(), once), isTrue);
      }
    }
  });
}
