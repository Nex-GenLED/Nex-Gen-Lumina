// THE chokepoint. Every preset write that can capture geometry goes through
// here, and there is deliberately only one of these.
//
// WHY A CHOKEPOINT AND NOT FOUR GATE CALLS. `psave` captures LIVE segment
// geometry into the preset whatever the inline state says, so any save taken
// while the layout is wrong bakes that error somewhere durable — it reloads on
// its schedule forever. Four independent gate calls is how one site drifts
// ungated later, and the site that drifts is the one nobody re-reads.
//
// FOUR CALLERS, all gated (decided 2026-08-14):
//   1. ScheduleSyncService.psaveIfChanged   — the NGL ladder + pattern slots
//   2. ControllerDefaultsHealer             — ON-preset master-power heal, the
//                                             connect-time path the gate was
//                                             specified for
//   3. CalendarEntryLeaseManager            — lease slots
//   4. SunriseOffService                    — the reserved sunrise-off slot
//
// The gate's question is identical regardless of which slot is targeted: does
// the device's segment shape match what we expect? A lease preset baked over a
// collapsed layout is exactly as durable as a baked ladder.
//
// NOT GATED, deliberately: the manual save on the pattern edit screen. A user
// looking at their lights and saving what they see is the one party entitled to
// override the app's model — that is #76's own principle, the installation
// outranks the model. Recorded as a decision, not an oversight.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/wled/device_channel.dart';
import 'geometry_gate.dart';

/// What happened, so the caller logs one line and moves on.
@immutable
class GatedSaveOutcome {
  /// True only when a save was actually attempted AND reported success.
  final bool saved;

  /// True when the gate refused. Distinct from `!saved`: a save can fail on its
  /// own merits after the gate allowed it, and the two need different fixes.
  final bool gateRefused;

  final GateResult? gate;
  final String? message;

  const GatedSaveOutcome({
    required this.saved,
    required this.gateRefused,
    this.gate,
    this.message,
  });
}

/// The device's expected segment shape, derived from its OWN hardware buses.
///
/// Bus start/len is the closest thing to a pixel map that is device-derived
/// rather than app-modelled, which is the right authority here: the gate exists
/// to defend the installation against the app, so its expectation must not come
/// from the app's beliefs about the installation.
List<SegmentShape> expectedShapeFromChannels(List<DeviceChannel> channels) => [
      for (final c in channels)
        if (c.stop > c.start) SegmentShape(c.id, c.start, c.stop),
    ];

/// The shape of [gatedPresetSave], lifted to a typedef so callers can hold it
/// as an injectable seam (CalendarEntryLeaseManager does) without each one
/// re-spelling a six-parameter function type — and so a signature change
/// breaks every seam at compile time rather than one of them at runtime.
typedef GatedPresetSaveCall = Future<GatedSaveOutcome> Function({
  required int presetId,
  required String presetName,
  required List<SegmentShape> expected,
  required GeometryReader read,
  required GeometryProvisioner reprovision,
  required Future<bool> Function() save,
  String label,
});

/// Gate, then save. Never throws.
///
/// ORDERING IS THE POINT. The gate runs BEFORE anything else records an
/// attempt, so a gate refusal is never counted as a repair attempt by the
/// non-convergence guard: no save happened, and counting it would burn that
/// budget on a condition a save was never going to fix — and would eventually
/// replace the gate's specific diagnosis with a generic non-convergence one.
Future<GatedSaveOutcome> gatedPresetSave({
  required int presetId,
  required String presetName,
  required List<SegmentShape> expected,
  required GeometryReader read,
  required GeometryProvisioner reprovision,
  required Future<bool> Function() save,
  String label = 'preset',
}) async {
  // No expectation = no basis to judge. Save rather than block every write on a
  // controller whose bus layout we could not read: the gate is a guard against
  // a KNOWN mismatch, not a licence to refuse everything when uninformed. The
  // #76 window it closes needs an expectation to close against.
  if (expected.isEmpty) {
    final ok = await _safeSave(save);
    return GatedSaveOutcome(
      saved: ok,
      gateRefused: false,
      message: '$label $presetId ($presetName): no expected shape available — '
          'saved ungated',
    );
  }

  final gate = await evaluateGeometryGate(
    expected: expected,
    read: read,
    reprovision: reprovision,
  );

  if (!gate.proceed) {
    debugPrint('GatedSave: REFUSED $label $presetId ($presetName) — '
        '${gate.summary}');
    return GatedSaveOutcome(
      saved: false,
      gateRefused: true,
      gate: gate,
      message: '$label $presetId ($presetName) not saved — ${gate.summary}',
    );
  }

  final ok = await _safeSave(save);
  return GatedSaveOutcome(
    saved: ok,
    gateRefused: false,
    gate: gate,
    message: '$label $presetId ($presetName): ${gate.summary}'
        '${ok ? '' : ' — SAVE FAILED'}',
  );
}

Future<bool> _safeSave(Future<bool> Function() save) async {
  try {
    return await save();
  } catch (e) {
    debugPrint('GatedSave: save threw — $e');
    return false;
  }
}
