// Design Studio Slice 0 — per-pixel (`i`) write-path tests.
//
// Covers: span→payload compilation (singles, ranges, compression, RGBW
// padding, clamping, overlap last-wins, invalid drop); flat-form
// rejection/conversion in the validator; chunk splitting at the constant;
// the orchestrator's ordering / stop-on-failure / too-large retry; the
// channel-filter bypass; and the relay string-encoding roundtrip.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/utils/rgbw_validation.dart';

/// Counts LEDs covered by a canonical nested `i` array. Single: `int,List`.
/// Range: `int,int,List` (stop exclusive).
int _coveredLeds(List<dynamic> i) {
  int total = 0;
  int k = 0;
  while (k < i.length) {
    if (k + 1 < i.length && i[k] is int && i[k + 1] is int) {
      total += (i[k + 1] as int) - (i[k] as int); // range: stop - start
      k += 3;
    } else {
      total += 1; // single pixel
      k += 2;
    }
  }
  return total;
}

List<dynamic> _iOf(Map<String, dynamic> payload) =>
    (payload['seg'] as List).first['i'] as List;

void main() {
  group('normalizeAndMergePixelSpans', () {
    test('single pixels of same color merge into one range', () {
      final spans = [
        const PixelSpan.single(0, [255, 0, 0]),
        const PixelSpan.single(1, [255, 0, 0]),
        const PixelSpan.single(2, [255, 0, 0]),
      ];
      final out = normalizeAndMergePixelSpans(spans);
      expect(out.length, 1);
      expect(out.first.start, 0);
      expect(out.first.end, 2);
      expect(out.first.color, [255, 0, 0, 0]); // RGB padded to RGBW (W=0)
    });

    test('non-contiguous same-color pixels stay separate', () {
      final spans = [
        const PixelSpan.single(0, [0, 255, 0]),
        const PixelSpan.single(2, [0, 255, 0]), // gap at 1
      ];
      final out = normalizeAndMergePixelSpans(spans);
      expect(out.length, 2);
    });

    test('adjacent different colors do not merge', () {
      final spans = [
        const PixelSpan(start: 0, end: 4, color: [255, 0, 0]),
        const PixelSpan(start: 5, end: 9, color: [0, 0, 255]),
      ];
      final out = normalizeAndMergePixelSpans(spans);
      expect(out.length, 2);
      expect(out[0].end, 4);
      expect(out[1].start, 5);
    });

    test('overlapping spans: later span wins on the overlap', () {
      final spans = [
        const PixelSpan(start: 0, end: 9, color: [255, 0, 0]),
        const PixelSpan(start: 5, end: 9, color: [0, 0, 255]), // overrides 5..9
      ];
      final out = normalizeAndMergePixelSpans(spans);
      expect(out.length, 2);
      expect(out[0].start, 0);
      expect(out[0].end, 4);
      expect(out[0].color, [255, 0, 0, 0]);
      expect(out[1].start, 5);
      expect(out[1].end, 9);
      expect(out[1].color, [0, 0, 255, 0]);
    });

    test('clamps out-of-range channels and drops invalid spans', () {
      final spans = [
        const PixelSpan.single(0, [300, -5, 128]), // clamp → [255,0,128,0]
        const PixelSpan(start: 5, end: 2, color: [1, 2, 3]), // invalid: end<start
        const PixelSpan(start: -1, end: 3, color: [1, 2, 3]), // invalid: start<0
      ];
      final out = normalizeAndMergePixelSpans(spans);
      expect(out.length, 1);
      expect(out.first.color, [255, 0, 128, 0]);
    });

    test('explicit RGBW white is preserved', () {
      final out = normalizeAndMergePixelSpans(
        [const PixelSpan.single(3, [10, 20, 30, 200])],
      );
      expect(out.first.color, [10, 20, 30, 200]);
    });
  });

  group('buildPerPixelPayload', () {
    test('single pixel emits [idx, [rgbw]]', () {
      final p = buildPerPixelPayload(
        [const PixelSpan.single(7, [1, 2, 3, 4])],
        0,
      );
      expect(_iOf(p), [7, [1, 2, 3, 4]]);
    });

    test('range emits [start, stop-exclusive, [rgbw]]', () {
      final p = buildPerPixelPayload(
        [const PixelSpan(start: 2, end: 5, color: [9, 8, 7, 6])],
        0,
      );
      // end 5 inclusive → stop 6 exclusive
      expect(_iOf(p), [2, 6, [9, 8, 7, 6]]);
    });

    test('sets fx:0 and on:true so a static paint persists', () {
      final p = buildPerPixelPayload([const PixelSpan.single(0, [1, 1, 1, 0])], 0);
      final seg = (p['seg'] as List).first as Map;
      expect(seg['fx'], 0);
      expect(seg['on'], true);
      expect(p['on'], true);
    });

    test('targets exactly one segment (no channel fan-out)', () {
      final p = buildPerPixelPayload([const PixelSpan.single(0, [1, 1, 1, 0])], 2);
      final segs = p['seg'] as List;
      expect(segs.length, 1);
      expect((segs.first as Map)['id'], 2);
    });
  });

  group('chunkPixelSpans', () {
    test('splits by LED coverage at the given size', () {
      // Five 10-LED ranges = 50 LEDs; chunkSize 20 → 20/20/10.
      final spans = [
        for (int b = 0; b < 50; b += 10)
          PixelSpan(start: b, end: b + 9, color: const [1, 2, 3, 0]),
      ];
      final chunks = chunkPixelSpans(spans, 20);
      expect(chunks.length, 3);
      expect(chunks.map((c) => c.fold<int>(0, (s, sp) => s + sp.length)),
          [20, 20, 10]);
    });

    test('an oversized single range is sliced into ≤size sub-RANGES', () {
      final chunks = chunkPixelSpans(
        [const PixelSpan(start: 0, end: 99, color: [1, 2, 3, 0])], // 100 LEDs
        30,
      );
      expect(chunks.length, 4); // 30/30/30/10
      // Each sub-span is still a range (never exploded to singles).
      for (final c in chunks) {
        expect(c.length, 1);
        expect(c.first.start <= c.first.end, isTrue);
      }
      expect(chunks.last.first.start, 90);
      expect(chunks.last.first.end, 99);
    });

    test('every chunk covers at most chunkSize LEDs', () {
      final spans = [
        for (int k = 0; k < 500; k++) PixelSpan.single(k, const [255, 0, 0]),
      ];
      final merged = normalizeAndMergePixelSpans(spans); // → one 500-LED range
      final chunks = chunkPixelSpans(merged, kDefaultPixelChunkSize);
      for (final c in chunks) {
        expect(c.fold<int>(0, (s, sp) => s + sp.length),
            lessThanOrEqualTo(kDefaultPixelChunkSize));
      }
      expect(chunks.fold<int>(0, (s, c) => s + c.fold<int>(0, (a, sp) => a + sp.length)),
          500);
    });
  });

  group('normalizeIArray (validator tightening)', () {
    test('legacy FLAT [idx,r,g,b,...] converts to nested RGBW', () {
      final flat = [0, 255, 0, 0, 1, 0, 255, 0]; // 2 px, RGB, no W
      final out = normalizeIArray(flat);
      expect(out, [0, [255, 0, 0, 0], 1, [0, 255, 0, 0]]);
    });

    test('nested form validates colors and keeps bounds', () {
      final nested = [0, 5, [300, -1, 20]]; // range 0..5, out-of-range color
      final out = normalizeIArray(nested);
      expect(out, [0, 5, [255, 0, 20, 0]]);
    });

    test('unparseable all-int (not %4) drops to empty — nothing unvalidated', () {
      expect(normalizeIArray([0, 1, 2]), isEmpty);
    });

    test('normalizeWledPayload canonicalizes a flat i array end-to-end', () {
      final payload = {
        'seg': [
          {'id': 0, 'fx': 0, 'i': [0, 10, 20, 30]}, // flat single px, RGB
        ],
      };
      final norm = normalizeWledPayload(payload);
      final i = (norm['seg'] as List).first['i'] as List;
      expect(i, [0, [10, 20, 30, 0]]);
    });
  });

  group('postPixelSpansChunked orchestrator', () {
    test('posts chunks in order and succeeds', () async {
      final seen = <int>[];
      final ok = await postPixelSpansChunked(
        spans: [
          for (int k = 0; k < 40; k++) PixelSpan.single(k, [k % 256, 0, 0]),
        ],
        segmentId: 0,
        chunkSize: 16,
        postChunk: (payload) async {
          seen.add(_iOf(payload).isEmpty ? 0 : (_iOf(payload).first as int));
          return PerPixelChunkResult.ok;
        },
      );
      expect(ok, isTrue);
      // Ascending first-index per chunk proves ordering preserved.
      final sorted = [...seen]..sort();
      expect(seen, sorted);
      expect(seen.length, greaterThan(1)); // 40 LEDs / 16 → multiple chunks
    });

    test('stop-on-failure aborts remaining chunks', () async {
      int calls = 0;
      final ok = await postPixelSpansChunked(
        spans: [
          for (int k = 0; k < 60; k++) PixelSpan.single(k, const [1, 0, 0]),
        ],
        segmentId: 0,
        chunkSize: 16,
        postChunk: (payload) async {
          calls++;
          return calls == 1 ? PerPixelChunkResult.failed : PerPixelChunkResult.ok;
        },
      );
      expect(ok, isFalse);
      expect(calls, 1); // never attempted the second chunk
    });

    test('too-large chunk retries once at a smaller size and succeeds', () async {
      // 40-LED single chunk (chunkSize 64). First post is "too large";
      // the retry re-splits at 32 → two sub-posts that succeed.
      final attempts = <int>[];
      final ok = await postPixelSpansChunked(
        spans: [
          for (int k = 0; k < 40; k++) PixelSpan.single(k, const [1, 2, 3]),
        ],
        segmentId: 0,
        chunkSize: 64,
        postChunk: (payload) async {
          final covered = _coveredLeds(_iOf(payload));
          attempts.add(covered);
          return covered > 32
              ? PerPixelChunkResult.payloadTooLarge
              : PerPixelChunkResult.ok;
        },
      );
      expect(ok, isTrue);
      expect(attempts.first, 40); // big attempt rejected
      expect(attempts.sublist(1).every((c) => c <= 32), isTrue); // sub-chunks ok
      expect(attempts.length, 3); // 1 big + 2 sub (32 + 8)
    });

    test('retry that still fails aborts the paint', () async {
      final ok = await postPixelSpansChunked(
        spans: [
          for (int k = 0; k < 40; k++) PixelSpan.single(k, const [1, 2, 3]),
        ],
        segmentId: 0,
        chunkSize: 64,
        postChunk: (_) async => PerPixelChunkResult.payloadTooLarge,
      );
      expect(ok, isFalse);
    });

    test('empty paint is a no-op success', () async {
      var called = false;
      final ok = await postPixelSpansChunked(
        spans: const [],
        segmentId: 0,
        chunkSize: 64,
        postChunk: (_) async {
          called = true;
          return PerPixelChunkResult.ok;
        },
      );
      expect(ok, isTrue);
      expect(called, isFalse);
    });
  });

  group('channel-filter bypass', () {
    test('a per-pixel single-seg-with-id payload is NOT fanned out', () {
      // Even if a per-pixel payload accidentally reached the channel chokepoint,
      // expandForParticipation must leave it untouched (Rule 5: explicit id).
      final payload = buildPerPixelPayload(
        [const PixelSpan(start: 0, end: 3, color: [1, 2, 3, 0])],
        0,
      );
      final expanded = expandForParticipation(payload, [0, 1, 2]);
      expect((expanded['seg'] as List).length, 1); // no fan-out to 3 channels
      expect((expanded['seg'] as List).first['i'], isNotNull);
    });
  });

  group('WledService.applyPerPixel (simulation capture)', () {
    test('records chunks in order; multi-chunk for >chunkSize paints', () async {
      final svc = WledService('http://mock');
      final ok = await svc.applyPerPixel(
        spans: [
          for (int k = 0; k < 500; k++) WPixel(k),
        ],
        chunkSize: kDefaultPixelChunkSize,
      );
      expect(ok, isTrue);
      final chunks = svc.lastSimulatedPerPixelChunks;
      // 500 same-color LEDs → one range → sliced into 224/224/52 = 3 chunks.
      expect(chunks.length, 3);
      for (final c in chunks) {
        final seg = (c['seg'] as List).first as Map;
        expect(seg['id'], 0); // single-segment targeting, no fan-out
        expect(seg['fx'], 0);
        expect(_coveredLeds(seg['i'] as List), lessThanOrEqualTo(kDefaultPixelChunkSize));
      }
      // Ordered: first indices ascend across chunks.
      final firstIdx = chunks.map((c) => (_iOf(c).first as int)).toList();
      expect(firstIdx, [...firstIdx]..sort());
    });
  });

  group('relay string-encoding roundtrip', () {
    test('a chunked per-pixel payload survives jsonEncode→decode intact', () {
      // Mirrors RemoteCommand.toFirestore: payload stored as jsonEncode(payload).
      // The nested `i` arrays are exactly what dodges Firestore's nested-array
      // limit by living inside a JSON string.
      final payload = buildPerPixelPayload(
        [
          const PixelSpan(start: 0, end: 9, color: [255, 0, 0, 0]),
          const PixelSpan.single(20, [0, 255, 0, 0]),
        ],
        1,
      );
      final decoded = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
      expect(decoded, payload);
      final i = (decoded['seg'] as List).first['i'] as List;
      expect(i, [0, 10, [255, 0, 0, 0], 20, [0, 255, 0, 0]]);
    });
  });
}

/// Small helper: a single-pixel red span at [index] (readable bulk builders).
// ignore: non_constant_identifier_names
PixelSpan WPixel(int index) => PixelSpan.single(index, const [255, 0, 0]);
