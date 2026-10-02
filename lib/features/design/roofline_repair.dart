import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

// Repair of a roofline map whose channel carries stacked copies of the same
// segment (+113, tester report: anchor placement looked like it stacked a new
// segment on the previous ones, and nothing could delete them).
//
// What "stacked" can be in STORED data. Every write rebases a channel's
// start_pixel to a gapless run (splitConfigToPixelMapChannels), so two
// segments can never overlap by LED number once saved; a copy sits end to end
// with the original and pushes the channel past its strip. Two shapes are
// unambiguous duplicates and are the only things this cleanup removes:
//
//  * the same id twice with the same lights (a re-marked channel used to mint
//    a positional id that an older section already carried);
//  * the same stored start_pixel twice with the same lights (a doc written
//    before the rebase existed, or one edited by hand).
//
// Two segments that merely sit next to each other with the same name, type
// and count are REPORTED as suspects and never touched: two 1-light corners
// in a row are also how a 2-light corner is sometimes mapped, and dropping
// one would change the light count.
//
// Invariants, checked by test: a kept segment keeps its own start and count;
// the channel keeps its order; nothing here writes.

/// Why the cleanup drops a segment.
enum CleanupReason {
  /// Same id as a kept segment, same lights.
  duplicateId,

  /// Same stored start as a kept segment, same lights.
  stackedCopy,
}

/// One segment the cleanup drops, and the copy it keeps instead.
class CleanupRemoval {
  const CleanupRemoval({
    required this.segment,
    required this.keptInstead,
    required this.reason,
  });

  final RooflineSegment segment;
  final RooflineSegment keptInstead;
  final CleanupReason reason;
}

/// A segment that shares its id with a DIFFERENT segment and is kept under a
/// fresh id so each can be edited or deleted on its own.
class CleanupRename {
  const CleanupRename({required this.segment, required this.newId});

  final RooflineSegment segment;
  final String newId;
}

/// The dry run for one channel.
class ChannelCleanupPlan {
  const ChannelCleanupPlan({
    required this.channelIndex,
    required this.original,
    required this.kept,
    required this.removed,
    required this.renamed,
    required this.suspects,
  });

  final int channelIndex;

  /// The channel as it is.
  final List<RooflineSegment> original;

  /// The channel after cleanup, in stored order, renames applied. Every kept
  /// segment keeps its own `startPixel` and `pixelCount`.
  final List<RooflineSegment> kept;

  final List<CleanupRemoval> removed;
  final List<CleanupRename> renamed;

  /// Runs of adjacent segments with the same name, type, role and count.
  /// Reported for a human to judge; never acted on.
  final List<List<RooflineSegment>> suspects;

  bool get hasWork => removed.isNotEmpty || renamed.isNotEmpty;

  int get originalTotal => original.fold(0, (a, s) => a + s.pixelCount);
  int get keptTotal => kept.fold(0, (a, s) => a + s.pixelCount);
}

String _lightsSignature(RooflineSegment s) =>
    '${s.pixelCount}|${s.type.name}|${s.architecturalRole?.name ?? ''}|${s.name}';

/// Plans the cleanup of one channel's [segments] (stored order). Pure.
ChannelCleanupPlan planChannelCleanup(
    int channelIndex, List<RooflineSegment> segments) {
  final kept = <RooflineSegment>[];
  final removed = <CleanupRemoval>[];
  final renamed = <CleanupRename>[];
  final keptById = <String, RooflineSegment>{};
  final keptByStart = <int, List<RooflineSegment>>{};
  final usedIds = <String>{for (final s in segments) s.id};

  for (final s in segments) {
    final sig = _lightsSignature(s);

    final sameId = keptById[s.id];
    if (sameId != null) {
      if (_lightsSignature(sameId) == sig) {
        removed.add(CleanupRemoval(
            segment: s,
            keptInstead: sameId,
            // Sitting on the same stored start is the more specific finding.
            reason: sameId.startPixel == s.startPixel
                ? CleanupReason.stackedCopy
                : CleanupReason.duplicateId));
        continue;
      }
      // Same id, different lights: two real segments wearing one name.
      var n = 2;
      var fresh = '${s.id}_$n';
      while (usedIds.contains(fresh)) {
        fresh = '${s.id}_${++n}';
      }
      usedIds.add(fresh);
      final renamedSeg = s.copyWith(id: fresh);
      renamed.add(CleanupRename(segment: s, newId: fresh));
      kept.add(renamedSeg);
      keptById[fresh] = renamedSeg;
      (keptByStart[s.startPixel] ??= []).add(renamedSeg);
      continue;
    }

    final stacked = (keptByStart[s.startPixel] ?? const [])
        .where((k) => _lightsSignature(k) == sig)
        .toList();
    if (stacked.isNotEmpty) {
      removed.add(CleanupRemoval(
          segment: s,
          keptInstead: stacked.first,
          reason: CleanupReason.stackedCopy));
      continue;
    }

    kept.add(s);
    keptById[s.id] = s;
    (keptByStart[s.startPixel] ??= []).add(s);
  }

  // Adjacent identical neighbours — reported only.
  final suspects = <List<RooflineSegment>>[];
  var run = <RooflineSegment>[];
  for (final s in kept) {
    if (run.isNotEmpty && _lightsSignature(run.last) == _lightsSignature(s)) {
      run.add(s);
    } else {
      if (run.length > 1) suspects.add(run);
      run = [s];
    }
  }
  if (run.length > 1) suspects.add(run);

  return ChannelCleanupPlan(
    channelIndex: channelIndex,
    original: List.unmodifiable(segments),
    kept: List.unmodifiable(kept),
    removed: List.unmodifiable(removed),
    renamed: List.unmodifiable(renamed),
    suspects: List.unmodifiable(suspects),
  );
}

/// Plans every channel of [config]. Channels with nothing to do are included
/// (with `hasWork == false`) so a caller can show "nothing to clean".
Map<int, ChannelCleanupPlan> planRooflineCleanup(RooflineConfiguration config) {
  return {
    for (final ch in config.allChannelIndices)
      ch: planChannelCleanup(ch, config.segmentsForChannel(ch)),
  };
}

/// True when any channel has duplicates to remove or ids to repair.
bool cleanupHasWork(Map<int, ChannelCleanupPlan> plans) =>
    plans.values.any((p) => p.hasWork);

/// [config] with each planned channel's segments replaced by its kept list.
/// Channels without a plan are untouched. `sortOrder` is renumbered; start
/// pixels are left to the write boundary, which rebases them as it always
/// has (a removed copy that sat before a real segment moves that segment back
/// to where the lights are).
RooflineConfiguration applyCleanupPlans(
  RooflineConfiguration config,
  Map<int, ChannelCleanupPlan> plans,
) {
  if (!cleanupHasWork(plans)) return config;
  final ordered = <RooflineSegment>[
    for (final ch in config.allChannelIndices)
      ...(plans[ch]?.hasWork == true
          ? plans[ch]!.kept
          : config.segmentsForChannel(ch)),
  ];
  return config.copyWith(
    segments: [
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i),
    ],
    updatedAt: DateTime.now(),
  );
}

/// The dry run as the customer (or the operator) reads it. Lights are
/// 1-indexed here and nowhere else.
String describeChannelCleanup(ChannelCleanupPlan p) {
  final b = StringBuffer();
  b.writeln('Channel ${p.channelIndex + 1}: ${p.original.length} segment'
      '${p.original.length == 1 ? '' : 's'}, ${p.originalTotal} lights mapped.');
  if (!p.hasWork) {
    b.writeln('  Nothing to clean up.');
  }
  for (final r in p.removed) {
    final s = r.segment;
    final why = r.reason == CleanupReason.duplicateId
        ? 'same id as'
        : 'stacked on';
    b.writeln('  REMOVE ${_describe(s)} — $why ${_describe(r.keptInstead)}');
  }
  for (final r in p.renamed) {
    b.writeln('  RENAME ${_describe(r.segment)} → id ${r.newId} '
        '(shared its id with a different segment)');
  }
  if (p.hasWork) {
    b.writeln('  KEEP ${p.kept.length} segment${p.kept.length == 1 ? '' : 's'}, '
        '${p.keptTotal} lights:');
    for (final s in p.kept) {
      b.writeln('    ${_describe(s)}');
    }
  }
  for (final group in p.suspects) {
    b.writeln('  NOTE ${group.length} identical neighbours left alone: '
        '${group.map(_describe).join(', ')}');
  }
  return b.toString();
}

String _describe(RooflineSegment s) =>
    '"${s.name}" (${s.type.name}'
    '${s.architecturalRole != null ? '/${s.architecturalRole!.name}' : ''}) '
    'lights ${s.startPixel + 1}–${s.startPixel + s.pixelCount} [id ${s.id}]';
