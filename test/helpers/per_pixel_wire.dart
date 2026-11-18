// Test helper: records what an apply puts on the wire, through the REAL
// per-pixel pipeline, and reads the per-pixel bytes back out.
//
// The older editor and spine tests use fakes whose `applyPerPixel` returns
// true and throws the spans away, so nothing after the converter was ever
// looked at. This recorder runs every per-pixel paint through
// `postPixelSpansChunked` (merge, chunk, `buildPerPixelPayload`): the bodies
// `WledService` would POST. No network.
import 'dart:convert';

import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

class PerPixelWireRecorder implements WledRepository, PerPixelWriter {
  /// Every body in the order it was sent, JSON round-tripped as posted.
  final bodies = <Map<String, dynamic>>[];

  Map<String, dynamic> _asSent(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    bodies.add(_asSent(payload));
    return true;
  }

  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) =>
      postPixelSpansChunked(
        spans: spans,
        segmentId: segmentId,
        chunkSize: chunkSize,
        postChunk: (p) async {
          bodies.add(_asSent(p));
          return PerPixelChunkResult.ok;
        },
      );

  /// Only the bodies that carry a per-pixel `i` array.
  List<Map<String, dynamic>> get pixelBodies => [
        for (final b in bodies)
          if (iArraysOf(b).isNotEmpty) b,
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Segment id to that segment's `i` array, for each segment in [body] that
/// has one.
Map<int, List<dynamic>> iArraysOf(Map<String, dynamic> body) {
  final out = <int, List<dynamic>>{};
  final segs = body['seg'];
  if (segs is! List) return out;
  for (final s in segs) {
    if (s is Map && s['i'] is List) {
      out[(s['id'] as num?)?.toInt() ?? 0] = s['i'] as List;
    }
  }
  return out;
}

/// The raw RGBW each pixel was SENT by the `i` arrays in [bodies] (later
/// writes win), per channel of [lengths]. Null means no `i` entry covered the
/// pixel. Singles are `index, [rgbw]`; ranges `start, stopExclusive, [rgbw]`.
Map<int, List<List<int>?>> sentPixelBytes(
  Iterable<Map<String, dynamic>> bodies,
  Map<int, int> lengths,
) {
  final out = {
    for (final e in lengths.entries) e.key: List<List<int>?>.filled(e.value, null),
  };
  for (final body in bodies) {
    for (final e in iArraysOf(body).entries) {
      final px = out[e.key];
      if (px == null) continue;
      final i = e.value;
      var k = 0;
      while (k < i.length) {
        final start = (i[k] as num).toInt();
        var stop = start + 1;
        if (i[k + 1] is num) {
          stop = (i[k + 1] as num).toInt();
          k++;
        }
        final rgbw = [for (final c in i[k + 1] as List) (c as num).toInt()];
        for (var p = start; p < stop && p < px.length; p++) {
          px[p] = rgbw;
        }
        k += 2;
      }
    }
  }
  return out;
}

/// [spans] rasterized the same way (inclusive ends, later spans win).
List<List<int>?> spanPixelBytes(List<PixelSpan> spans, int length) {
  final out = List<List<int>?>.filled(length, null);
  for (final s in spans) {
    for (var p = s.start; p <= s.end && p < length; p++) {
      if (p >= 0) out[p] = [...s.color];
    }
  }
  return out;
}
