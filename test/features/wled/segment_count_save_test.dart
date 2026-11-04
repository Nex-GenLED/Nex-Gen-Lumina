// +122 item 4 (TD-9 defect 3): the LED-count save writes the segment layout
// as ONE geometry POST, reads it back, and retries once — never one POST per
// segment with nothing checked. Installers use this screen during an
// install; the old shape could leave segment 0 spanning the strip and segment
// 1 overlapping it in amber when the controller re-initialised between the
// POSTs, with nothing in the app showing it.
//
// Fixtures: the two-channel layout and the one-segment-after-restart layout.
// The fake controller is stateful: a geometry POST re-binds its segments
// (unless told to drop it), so the read-back shows what landed. Synthetic
// ids only.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/segment_count_save.dart';

import '../../helpers/recording_wled_repository.dart';

Map<String, dynamic> _seg(int id, int start, int stop, {List<int>? col}) => {
      'id': id,
      'start': start,
      'stop': stop,
      'len': stop - start,
      'on': true,
      'bri': 255,
      'fx': 0,
      'sx': 128,
      'ix': 128,
      'pal': 0,
      'col': [
        col ?? [227, 24, 55, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
    };

const _amber = [255, 160, 0, 0];

class _Controller extends RecordingWledRepository {
  _Controller({
    required this.segs,
    this.door = true,
    this.dropFirstPosts = 0,
  });

  /// The live segments; a POST re-binds them.
  List<Map<String, dynamic>> segs;

  /// False models a repository without the provisioning door (the relay).
  final bool door;

  /// The first N geometry POSTs are accepted (2xx) but not applied — the
  /// controller re-initialised under the write.
  int dropFirstPosts;

  final geometryPosts = <Map<String, dynamic>>[];
  final segmentPosts = <Map<String, dynamic>>[];
  int stateReads = 0;

  @override
  Future<Map<String, dynamic>?> getState() async {
    stateReads++;
    return {
      'on': true,
      'seg': [for (final s in segs) Map<String, dynamic>.from(s)]
    };
  }

  void _apply(Iterable<Map<String, dynamic>> entries) {
    for (final e in entries) {
      final id = e['id'] as int;
      final idx = segs.indexWhere((s) => s['id'] == id);
      final base = idx >= 0 ? segs[idx] : _seg(id, 0, 0, col: _amber);
      final merged = {...base, ...e};
      merged['len'] = (merged['stop'] as int) - (merged['start'] as int);
      if (idx >= 0) {
        segs[idx] = merged;
      } else {
        segs.add(merged);
      }
    }
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    if (!door) return false;
    geometryPosts.add(payload);
    if (dropFirstPosts > 0) {
      dropFirstPosts--;
      return true;
    }
    _apply((payload['seg'] as List).cast<Map<String, dynamic>>());
    return true;
  }

  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async {
    segmentPosts.add({'id': segmentId, 'start': start, 'stop': stop});
    _apply([
      {'id': segmentId, 'start': start, 'stop': stop}
    ]);
    return true;
  }
}

void main() {
  test('bounds for counts: one segment per enabled port, end to end', () {
    expect(segmentBoundsForCounts([100, 80]), [
      (id: 0, start: 0, stop: 100),
      (id: 1, start: 100, stop: 180),
    ]);
    expect(segmentBoundsForCounts([]), isEmpty);
  });

  test('two-channel layout, counts 90/90 → 100/80: ONE geometry POST, bounds '
      'only, a read-back, landed', () async {
    final c = _Controller(segs: [_seg(0, 0, 90), _seg(1, 90, 180)]);
    final r = await writeSegmentBoundsWithReadback(
        c, segmentBoundsForCounts([100, 80]));
    expect(r.outcome, SegmentCountSaveOutcome.landed, reason: '$r');
    expect(r.posts, 1);
    expect(c.geometryPosts, hasLength(1));
    expect(c.geometryPosts.single, {
      'seg': [
        {'id': 0, 'start': 0, 'stop': 100},
        {'id': 1, 'start': 100, 'stop': 180},
      ]
    });
    expect(c.segmentPosts, isEmpty, reason: 'no per-segment POSTs');
    expect(c.stateReads, 2, reason: 'one read before, one read-back');
    expect(r.after, [const SegmentShape(0, 0, 100), const SegmentShape(1, 100, 180)]);
  });

  test('one segment after a restart, counts 90/90: the one POST re-creates '
      'segment 1 WITH segment 0\'s look, and the read-back shows both',
      () async {
    final c = _Controller(segs: [_seg(0, 0, 180)]);
    final r = await writeSegmentBoundsWithReadback(
        c, segmentBoundsForCounts([90, 90]));
    expect(r.outcome, SegmentCountSaveOutcome.landed, reason: '$r');
    expect(c.geometryPosts, hasLength(1));
    final segs = (c.geometryPosts.single['seg'] as List).cast<Map>();
    expect(segs[0], {'id': 0, 'start': 0, 'stop': 90});
    expect(segs[1]['col'][0], [227, 24, 55, 0],
        reason: 'segment 0\'s look, never the firmware default');
    expect(r.after, [const SegmentShape(0, 0, 90), const SegmentShape(1, 90, 180)]);
    expect(c.segs[1]['col'][0], [227, 24, 55, 0]);
  });

  test('a POST the controller did not apply is caught by the read-back and '
      'retried once', () async {
    final c = _Controller(
        segs: [_seg(0, 0, 90), _seg(1, 90, 180)], dropFirstPosts: 1);
    final r = await writeSegmentBoundsWithReadback(
        c, segmentBoundsForCounts([100, 80]));
    expect(r.outcome, SegmentCountSaveOutcome.landedOnRetry, reason: '$r');
    expect(r.posts, 2);
    expect(c.geometryPosts, hasLength(2));
    expect(r.after, [const SegmentShape(0, 0, 100), const SegmentShape(1, 100, 180)]);
  });

  test('two POSTs that never land → didNotLand, with what the read-back saw',
      () async {
    final c = _Controller(
        segs: [_seg(0, 0, 90), _seg(1, 90, 180)], dropFirstPosts: 2);
    final r = await writeSegmentBoundsWithReadback(
        c, segmentBoundsForCounts([100, 80]));
    expect(r.outcome, SegmentCountSaveOutcome.didNotLand, reason: '$r');
    expect(r.posts, 2);
    expect(r.after, [const SegmentShape(0, 0, 90), const SegmentShape(1, 90, 180)]);
  });

  test('a repository without the provisioning door (the relay) still gets the '
      'bounds, per segment, and the same read-back', () async {
    final c = _Controller(
        segs: [_seg(0, 0, 90), _seg(1, 90, 180)], door: false);
    final r = await writeSegmentBoundsWithReadback(
        c, segmentBoundsForCounts([100, 80]));
    expect(r.outcome, SegmentCountSaveOutcome.landed, reason: '$r');
    expect(c.geometryPosts, isEmpty);
    expect(c.segmentPosts, hasLength(2));
    expect(r.after, [const SegmentShape(0, 0, 100), const SegmentShape(1, 100, 180)]);
  });

  test('the messages name the outcome in plain words', () {
    expect(segmentCountSaveMessage(SegmentCountSaveOutcome.landed),
        'LED counts updated.');
    expect(segmentCountSaveMessage(SegmentCountSaveOutcome.landedOnRetry),
        contains('second attempt'));
    expect(segmentCountSaveMessage(SegmentCountSaveOutcome.didNotLand),
        contains('did not read back'));
  });
}
