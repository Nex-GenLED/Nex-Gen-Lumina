// Roofline slice 2 — ScheduleItem carries `design_id` and `preset_kind` for a
// painted design scheduled nightly, round-trips them through toJson/fromJson,
// and leaves every other schedule's document byte-identical.
//
// NEW-BEHAVIOUR tests (the fields did not exist before this slice).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

void main() {
  ScheduleItem plain() => ScheduleItem(
        id: 's1',
        timeLabel: '7:00 PM',
        repeatDays: const ['Mon'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
        wledPayload: const {'on': true, 'bri': 200},
      );

  test('a schedule without the fields writes no design keys at all', () {
    final json = plain().toJson();
    expect(json.containsKey('design_id'), isFalse);
    expect(json.containsKey('preset_kind'), isFalse);
    expect(plain().isDesignApiPreset, isFalse);
  });

  test('design_id and preset_kind round-trip through toJson / fromJson', () {
    final item = plain().copyWith(
      designId: 'design-abc',
      presetKind: kSchedulePresetKindApi,
    );
    expect(item.isDesignApiPreset, isTrue);
    final json = item.toJson();
    expect(json['design_id'], 'design-abc');
    expect(json['preset_kind'], 'api');

    final back = ScheduleItem.fromJson(json);
    expect(back.designId, 'design-abc');
    expect(back.presetKind, 'api');
    expect(back.isDesignApiPreset, isTrue);
  });

  test('legacy documents (no keys) read as null; empty / wrong types too', () {
    final base = plain().toJson();
    expect(ScheduleItem.fromJson(base).designId, isNull);
    expect(ScheduleItem.fromJson(base).presetKind, isNull);

    expect(
        ScheduleItem.fromJson({...base, 'design_id': '', 'preset_kind': ' '})
            .isDesignApiPreset,
        isFalse);
    expect(
        ScheduleItem.fromJson({...base, 'design_id': 7, 'preset_kind': true})
            .designId,
        isNull);
  });

  test('copyWith carries the fields forward and clearDesign drops both', () {
    final item =
        plain().copyWith(designId: 'd', presetKind: kSchedulePresetKindApi);
    final edited = item.copyWith(timeLabel: '8:00 PM');
    expect(edited.designId, 'd');
    expect(edited.presetKind, 'api');

    final cleared = item.copyWith(clearDesign: true);
    expect(cleared.designId, isNull);
    expect(cleared.presetKind, isNull);
    expect(cleared.isDesignApiPreset, isFalse);
  });

  test('the kind string is the one the sync and the picker agree on', () {
    expect(kSchedulePresetKindApi, 'api');
  });
}
