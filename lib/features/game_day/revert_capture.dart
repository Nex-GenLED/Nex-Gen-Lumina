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

import 'package:nexgen_command/features/schedule/gated_preset_save.dart'
    show expectedShapeFromChannels;
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/segment_geometry_reheal.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

const String kRevertCaptureRefusedMessage =
    'Lights are mid-repair. Try again in a minute.';

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
  });

  final RevertCaptureOutcome outcome;

  /// The look to come back to; empty when [outcome] is refused.
  final Map<String, dynamic> payload;
  final String note;

  /// What the user is told on a refusal.
  String get message => kRevertCaptureRefusedMessage;
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
  return RevertCapture(
    outcome: RevertCaptureOutcome.capturedAfterRepair,
    payload: revertLookFromState(after),
    note: 'repaired ${r.before} → ${r.after}; look copied to ${r.lookCopiedTo}',
  );
}
