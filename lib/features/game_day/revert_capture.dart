// lib/features/game_day/revert_capture.dart
//
// +122 item 5 (TD-8 defect 1) — what Light Up Now stores as the look to come
// back to.
//
// GameDayScreen._activateNow captured the revert as the raw `/json/state`,
// with no check of the segment layout. A post-restart collapsed or
// half-healed layout was stored verbatim, bounds included, and
// EphemeralGameSessionService._handleGameEnd applied it at final + 30 min,
// so the house was put back in the broken shape (field case 2026-10-23).
//
// Now the live layout is compared with the controller's own channels:
//   • a match is CAPTURED — geometry fields stripped, inactive segments
//     dropped, the look and the root kept;
//   • a mismatch on the LAN is REPAIRED first (the shared geometry re-heal:
//     bounds from the buses, segment 0's look on every re-created segment),
//     re-read and captured;
//   • a mismatch that cannot be repaired — off the LAN, a repair that did not
//     land — is REFUSED with a message. A broken shape is never stored.
//   • no channel model at all (simulation, cfg never read) → captured
//     unchecked, exactly as before: refusing on ignorance would block Light Up
//     Now where there is nothing to judge.
//
// Roofline slice 1, item 3 — FREEZE-AWARE. Before any of the above, a live,
// switched-on segment reporting `frz: true` (a per-pixel frame: a painted
// design, a Static favourite, a smart preset) REFUSES the capture with its
// own message. The state read holds no pixel data, only the black base under
// the paint, so storing it would bring the house back dark. Nothing is
// stored and nothing is written — not even a repair.

import 'package:nexgen_command/features/schedule/gated_preset_save.dart'
    show expectedShapeFromChannels;
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/segment_geometry_reheal.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

const String kRevertCaptureRefusedMessage =
    'Lights are mid-repair. Try again in a minute.';

/// Roofline slice 1, item 3 — what the user is told when the lights are
/// showing a per-pixel frame (a painted design, a Static favourite, a smart
/// preset) and the look cannot be captured.
const String kRevertCaptureFrozenMessage =
    'Your lights are showing a painted design, which can\'t be saved as the '
    'look to come back to. Apply a pattern or a colour first, then try '
    'Light Up Now again.';

/// Why a capture was refused — picks the sentence.
enum RevertCaptureRefusal {
  /// The segment layout is off and could not be repaired here, or the
  /// controller did not answer.
  layout,

  /// A live, switched-on segment reports `frz: true`: a per-pixel frame is
  /// on the strip. WLED never serialises the pixel buffer, so the state read
  /// holds only the black base the paint spine wrote under the pixels (fx 0,
  /// `col` black) plus the freeze flag. Stored as the revert look, that puts
  /// the house back DARK at final + 30 min (the chokepoint's `frz:false` on
  /// the way out only makes the black base render). Refused instead
  /// (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §B.4, gate G3).
  frozen,
}

/// Segment fields that describe GEOMETRY, never a look. A revert restores a
/// look; the bounds belong to provisioning (#89 / #95).
const List<String> kSegmentGeometryKeys = [
  'start',
  'stop',
  'len',
  'rev',
  'mi',
  'of',
  'grp',
  'spc',
];

enum RevertCaptureOutcome {
  /// The live layout matched the channels; stored as the look.
  captured,

  /// The layout was collapsed, repaired on the LAN, re-read and stored.
  capturedAfterRepair,

  /// No channel model to judge against; stored as the look, as before.
  capturedUnchecked,

  /// Not stored: the layout is off and could not be repaired here.
  refused,
}

class RevertCapture {
  const RevertCapture({
    required this.outcome,
    required this.payload,
    this.note = '',
    this.refusal = RevertCaptureRefusal.layout,
  });

  final RevertCaptureOutcome outcome;

  /// The look to come back to; empty when [outcome] is refused.
  final Map<String, dynamic> payload;
  final String note;

  /// Why, when [outcome] is refused. Meaningless otherwise.
  final RevertCaptureRefusal refusal;

  /// What the user is told on a refusal.
  String get message => switch (refusal) {
        RevertCaptureRefusal.layout => kRevertCaptureRefusedMessage,
        RevertCaptureRefusal.frozen => kRevertCaptureFrozenMessage,
      };
}

typedef GeometryReheal = Future<GeometryRehealResult> Function(
  WledService svc, {
  Map<String, dynamic>? liveState,
});

bool _inactive(Map s) {
  final start = s['start'], stop = s['stop'];
  return start is int && stop is int && stop <= start;
}

/// The look in a `/json/state` body: every root field, and per live segment
/// everything but its geometry.
Map<String, dynamic> revertLookFromState(Map<String, dynamic> state) {
  final out = Map<String, dynamic>.from(state);
  final seg = state['seg'];
  if (seg is List) {
    out['seg'] = [
      for (final s in seg)
        if (s is Map && !_inactive(s))
          {
            for (final e in s.entries)
              if (!kSegmentGeometryKeys.contains(e.key)) e.key: e.value,
          },
    ];
  }
  return out;
}

RevertCapture _refused(String note) =>
    RevertCapture(outcome: RevertCaptureOutcome.refused, payload: const {}, note: note);

RevertCapture _refusedFrozen(List<int> ids) => RevertCapture(
      outcome: RevertCaptureOutcome.refused,
      payload: const {},
      note: 'per-pixel frame on the strip: segment(s) $ids report frz:true',
      refusal: RevertCaptureRefusal.frozen,
    );

/// The ids of the live, switched-on segments in a `/json/state` body that
/// report `frz: true` — a per-pixel frame is showing on each of them.
///
/// A deleted slot (stop ≤ start) and a segment that is OFF are not showing
/// anything and do not count. Nothing in `lib/` ever writes `frz: true` (the
/// chokepoint writes `frz: false` on every non-`i` write), so a true here is
/// the firmware's own mark of a per-pixel write.
List<int> frozenSegmentIds(Map<String, dynamic> state) {
  final seg = state['seg'];
  if (seg is! List) return const [];
  final out = <int>[];
  for (final s in seg) {
    if (s is! Map || _inactive(s)) continue;
    if (s['on'] == false) continue;
    if (s['frz'] != true) continue;
    final id = s['id'];
    out.add(id is int ? id : -1);
  }
  return out;
}

Future<RevertCapture> captureRevertLook({
  required WledRepository repo,
  required List<DeviceChannel> channels,
  GeometryReheal reheal = rehealSegmentGeometry,
}) async {
  Map<String, dynamic>? state;
  try {
    state = await repo.getState();
  } catch (e) {
    return _refused('controller state unreadable ($e)');
  }
  if (state == null) return _refused('controller state unreadable');

  // Roofline slice 1, item 3 — FREEZE first, before the layout verdict and
  // before any repair: a per-pixel frame cannot be captured whatever the
  // layout is, and a repair write would be a write for nothing. This also
  // covers the "no channel model" branch below: the freeze is a content
  // problem, not a layout one.
  final frozen = frozenSegmentIds(state);
  if (frozen.isNotEmpty) return _refusedFrozen(frozen);

  final expected = expectedShapeFromChannels(channels);
  final live = segmentShapeFromState(state);
  switch (decideGeometryHeal(expected: expected, live: live)) {
    case GeometryHealVerdict.standAside:
      return RevertCapture(
        outcome: RevertCaptureOutcome.capturedUnchecked,
        payload: revertLookFromState(state),
        note: expected.isEmpty ? 'no channel model' : 'live layout unreadable',
      );
    case GeometryHealVerdict.healthy:
      return RevertCapture(
        outcome: RevertCaptureOutcome.captured,
        payload: revertLookFromState(state),
      );
    case GeometryHealVerdict.drifted:
      break;
  }

  if (repo is! WledService) {
    return _refused('layout $live does not match the channels $expected and '
        'cannot be repaired off the LAN');
  }
  final r = await reheal(repo, liveState: state);
  if (r.outcome != GeometryRehealOutcome.repaired) {
    return _refused('repair ${r.outcome.name}: before=${r.before} '
        'after=${r.after}${r.note.isEmpty ? '' : ' (${r.note})'}');
  }
  Map<String, dynamic>? after;
  try {
    after = await repo.getState();
  } catch (_) {
    after = null;
  }
  if (after == null) return _refused('state unreadable after the repair');
  if (decideGeometryHeal(expected: expected, live: segmentShapeFromState(after)) !=
      GeometryHealVerdict.healthy) {
    return _refused('layout still off after the repair');
  }
  // Defensive: the repair body never writes `i`, so the re-read cannot be
  // frozen unless something else painted meanwhile. Never store it if so.
  final frozenAfter = frozenSegmentIds(after);
  if (frozenAfter.isNotEmpty) return _refusedFrozen(frozenAfter);
  return RevertCapture(
    outcome: RevertCaptureOutcome.capturedAfterRepair,
    payload: revertLookFromState(after),
    note: 'repaired ${r.before} → ${r.after}; look copied to ${r.lookCopiedTo}',
  );
}
