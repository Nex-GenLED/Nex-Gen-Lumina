// Roofline slice 2 — the enforcement timer re-fires a painted design by
// LOADING its preset, never by applying its body live.
//
// Defect-style against the slice's own body: the enforcement service applies
// `schedule.wledPayload` through applyPayloadWithLabel when the lights drift.
// An API-command body carries bounds (stripped at the wire pin) and runs to
// several KB (over the apply size cap), so a live apply either paints a
// bound-less copy or is refused. The controller holds the preset; loading it
// is the fire the timer itself performs. Pure decision, so the test needs no
// device or provider container. Fail-before: 2 fail / the rest pass (the
// helper did not exist; its rule for a design schedule is new).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_enforcement.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

ScheduleItem item({
  Map<String, dynamic>? payload,
  int? presetId,
  bool design = false,
}) =>
    ScheduleItem(
      id: 's',
      timeLabel: '7:00 PM',
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: X',
      enabled: true,
      wledPayload: payload,
      presetId: presetId,
      designId: design ? 'd1' : null,
      presetKind: design ? kSchedulePresetKindApi : null,
    );

void main() {
  const api = {'o': true, 'on': true, 'seg': []};
  const catalog = {'on': true, 'seg': []};

  test('a design schedule with a slot LOADS the preset', () {
    expect(enforcementActionFor(item(payload: api, presetId: 10, design: true)),
        EnforcementAction.loadPreset);
  });

  test('a design schedule with no slot yet has nothing to fire', () {
    expect(enforcementActionFor(item(payload: api, design: true)),
        EnforcementAction.none);
  });

  test('a catalog schedule with a payload applies it (unchanged rule)', () {
    expect(enforcementActionFor(item(payload: catalog, presetId: 10)),
        EnforcementAction.applyPayload);
  });

  test('a payload-less schedule with a slot loads it (unchanged rule)', () {
    expect(enforcementActionFor(item(presetId: 2)), EnforcementAction.loadPreset);
  });

  test('nothing at all → none (unchanged rule)', () {
    expect(enforcementActionFor(item()), EnforcementAction.none);
  });
}
