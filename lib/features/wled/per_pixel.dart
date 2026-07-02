/// Design Studio — Slice 0: typed, chunk-safe per-pixel (`i`) write path.
///
/// This module holds the PURE compilation logic (span → canonical WLED `i`
/// payload, range-compression, chunking) plus the [PerPixelWriter] capability
/// interface implemented by the two real transports (`WledService` local,
/// `CloudRelayRepository` remote). It deliberately does NOT touch the
/// `WledRepository` interface — that surface is implemented via `implements`
/// by ~14 test fakes, and widening it would break every one. A capability
/// interface keeps this additive: callers do `if (repo is PerPixelWriter)`.
///
/// Canonical `i` shape (the ONLY shape any writer emits — enforced by
/// `normalizeIArray` on the validation side):
///   - single pixel: `index, [r, g, b, w]`
///   - range:        `start, stop, [r, g, b, w]`   (stop EXCLUSIVE, per WLED)
library;

import 'package:flutter/foundation.dart';
import 'package:nexgen_command/utils/rgbw_validation.dart';

/// Worst-case LEDs per `/json/state` request. Bench-measured ceiling on the
/// reference controller (WLED 0.15.4, ESP32) is ~337 distinct single-pixel
/// entries (~6.0 KB) before the device returns HTTP 400 `{"error":9}` (JSON
/// buffer limit — note: NOT 413). 224 leaves ~34% headroom; a full all-distinct
/// chunk is ~4 KB. Range-compressed chunks are far smaller. Tunable.
/// See docs/audits/DESIGN_STUDIO_AUDIT_2026-07.md §2b.
const int kDefaultPixelChunkSize = 224;

/// Floor for the retry-on-too-large backoff so a pathological device can't
/// drive the chunk size to zero.
const int kMinPixelChunkSize = 16;

/// Result of posting a single per-pixel chunk. [payloadTooLarge] is the
/// retry trigger; the transport maps BOTH HTTP 413 and HTTP 400 (WLED's
/// `error:9` JSON-buffer rejection) onto it.
enum PerPixelChunkResult { ok, failed, payloadTooLarge }

/// A run of LEDs to paint one color. [start]/[end] are 0-indexed and
/// **inclusive** (a single pixel has `start == end`). [color] is `[r,g,b]`
/// or `[r,g,b,w]`; RGB inputs are treated per the RGBW-hardware convention
/// (W = 0 — the same result as `rgbToRgbw(forceZeroWhite: true)`; pass an
/// explicit 4th channel when a non-zero white is wanted).
@immutable
class PixelSpan {
  final int start;
  final int end;
  final List<int> color;

  const PixelSpan({
    required this.start,
    required this.end,
    required this.color,
  });

  /// A single-pixel span.
  const PixelSpan.single(int index, this.color)
      : start = index,
        end = index;

  /// Number of LEDs this span covers (inclusive).
  int get length => end - start + 1;

  @override
  String toString() => 'PixelSpan($start..$end, $color)';
}

/// Rasterizes [spans] to a per-index color map (later spans win on overlap),
/// validates each color to RGBW, then re-compresses consecutive same-color
/// indices into the minimal set of ordered, non-overlapping [PixelSpan]s.
///
/// This is the range-compression pass: a mostly-solid design collapses to a
/// handful of range spans. Invalid spans (negative start, end < start) are
/// dropped with a debug warning. Deterministic; pure.
List<PixelSpan> normalizeAndMergePixelSpans(List<PixelSpan> spans) {
  final pixels = <int, List<int>>{};
  for (final s in spans) {
    if (s.start < 0 || s.end < s.start) {
      if (kDebugMode) {
        debugPrint('⚠️ PixelSpan dropped (invalid range): $s');
      }
      continue;
    }
    final rgbw = validateRgbw(s.color, source: 'PixelSpan');
    for (int i = s.start; i <= s.end; i++) {
      pixels[i] = rgbw;
    }
  }
  if (pixels.isEmpty) return const <PixelSpan>[];

  final indices = pixels.keys.toList()..sort();
  final out = <PixelSpan>[];
  int runStart = indices.first;
  int prev = indices.first;
  List<int> runColor = pixels[runStart]!;

  for (int k = 1; k < indices.length; k++) {
    final idx = indices[k];
    final col = pixels[idx]!;
    final contiguous = idx == prev + 1;
    if (contiguous && _sameColor(col, runColor)) {
      prev = idx;
      continue;
    }
    out.add(PixelSpan(start: runStart, end: prev, color: runColor));
    runStart = idx;
    prev = idx;
    runColor = col;
  }
  out.add(PixelSpan(start: runStart, end: prev, color: runColor));
  return out;
}

/// Splits [spans] into chunks each covering at most [chunkSize] LEDs. A single
/// span longer than [chunkSize] is sliced into ≤chunkSize sub-RANGES (kept as
/// ranges, never exploded to singles). Input should already be normalized
/// (sorted, non-overlapping) via [normalizeAndMergePixelSpans]. Pure.
List<List<PixelSpan>> chunkPixelSpans(List<PixelSpan> spans, int chunkSize) {
  final limit = chunkSize < 1 ? kDefaultPixelChunkSize : chunkSize;
  final chunks = <List<PixelSpan>>[];
  var current = <PixelSpan>[];
  var budget = limit;

  void flush() {
    if (current.isNotEmpty) {
      chunks.add(current);
      current = <PixelSpan>[];
      budget = limit;
    }
  }

  for (final span in spans) {
    var s = span;
    // Slice a span that can't fit in the remaining budget.
    while (s.length > budget) {
      if (budget > 0) {
        final splitEnd = s.start + budget - 1;
        current.add(PixelSpan(start: s.start, end: splitEnd, color: s.color));
        s = PixelSpan(start: splitEnd + 1, end: s.end, color: s.color);
      }
      flush();
    }
    current.add(s);
    budget -= s.length;
    if (budget == 0) flush();
  }
  flush();
  return chunks;
}

/// Compiles one chunk of spans into a WLED `/json/state` payload targeting a
/// single segment [segmentId] with the canonical nested `i` array and `fx:0`
/// (Solid) so the static paint persists (a running effect would repaint over
/// it — see memory/project_blocks_boundary_blend_fix). Colors are re-validated
/// to RGBW. Pure.
Map<String, dynamic> buildPerPixelPayload(List<PixelSpan> chunk, int segmentId) {
  final i = <dynamic>[];
  for (final s in chunk) {
    final rgbw = validateRgbw(s.color, source: 'buildPerPixelPayload');
    if (s.start == s.end) {
      i.add(s.start);
      i.add(rgbw);
    } else {
      i.add(s.start);
      i.add(s.end + 1); // WLED range stop is EXCLUSIVE
      i.add(rgbw);
    }
  }
  return <String, dynamic>{
    'on': true,
    'seg': [
      {'id': segmentId, 'on': true, 'fx': 0, 'i': i},
    ],
  };
}

/// Orchestrates a full per-pixel paint: normalize+compress → chunk → post each
/// chunk sequentially via the injected [postChunk] transport. Ordered await,
/// stop-on-failure. On a `payloadTooLarge` result, retries THAT chunk ONCE at
/// a halved chunk size (re-split into sub-ranges); a still-failing sub-chunk
/// aborts the whole paint (returns false).
///
/// Bypasses channel filtering and participation expansion entirely — spans
/// carry absolute per-segment targeting, so a paint must never fan out to
/// every channel the way [applyChannelFilter]/[expandForParticipation] would.
///
/// Returns true if every chunk landed (or there was nothing to paint).
Future<bool> postPixelSpansChunked({
  required List<PixelSpan> spans,
  required int segmentId,
  required int chunkSize,
  required Future<PerPixelChunkResult> Function(Map<String, dynamic> payload)
      postChunk,
}) async {
  final normalized = normalizeAndMergePixelSpans(spans);
  if (normalized.isEmpty) return true; // nothing to paint — no-op success

  final chunks = chunkPixelSpans(normalized, chunkSize);
  for (final chunk in chunks) {
    final res = await postChunk(buildPerPixelPayload(chunk, segmentId));
    if (res == PerPixelChunkResult.ok) continue;
    if (res == PerPixelChunkResult.failed) return false;

    // payloadTooLarge → retry this chunk once at a smaller chunk size.
    final half = chunkSize ~/ 2;
    final smaller = half < kMinPixelChunkSize ? kMinPixelChunkSize : half;
    if (smaller >= chunkSize) return false; // already at/near the floor
    final subChunks = chunkPixelSpans(chunk, smaller);
    for (final sub in subChunks) {
      final r2 = await postChunk(buildPerPixelPayload(sub, segmentId));
      if (r2 != PerPixelChunkResult.ok) return false; // no second retry level
    }
  }
  return true;
}

/// Capability interface for repositories that support typed per-pixel writes.
/// Implemented by `WledService` (local, unchunked HttpClient POST) and
/// `CloudRelayRepository` (remote, one sequential command doc per chunk).
/// Kept OFF the [WledRepository] interface so the ~14 `implements`-based test
/// fakes stay green (additive). Callers: `if (repo is PerPixelWriter) …`.
abstract interface class PerPixelWriter {
  /// Paints [spans] onto segment [segmentId] (default 0). Colors are
  /// range-compressed and posted as sequential, size-bounded `i` chunks.
  /// Returns true when the whole paint lands. See [postPixelSpansChunked].
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  });
}

bool _sameColor(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
