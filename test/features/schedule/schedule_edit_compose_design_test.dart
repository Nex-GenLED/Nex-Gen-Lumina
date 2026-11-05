// Roofline slice 2 — the schedule editor's save write-path
// (composeEditedSchedule) carries a painted design's id and kind, and never
// carries a picture into an action that cannot fire it.
//
// NEW-BEHAVIOUR tests for the design fields; the "picture into Turn Off" case
// is defect-style against the slice's own sync guard: on the code before this
// change a design schedule edited to Turn Off round-tripped the API body, and
// the sync then refused the whole schedule as a stray picture (its OFF timer
// would not arm). Fail-before on that case: 1 fail / the rest pass.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart'
    show composeEditedSchedule;
import 'package:nexgen_command/features/schedule/schedule_models.dart';

const kApiBody = {
  'o': true,
  'on': true,
  'bri': 180,
  'seg': [
    {
      'id': 0,
      'start': 0,
      'stop': 100,
      'on': true,
      'fx': 0,
      'i': [0, 100, [255, 0, 0, 0]],
    }
  ],
};
const kCatalog = {
  'on': true,
  'bri': 255,
  'seg': [
    {
      'fx': 84,
      'col': [
        [255, 0, 0, 0]
      ]
    }
  ],
};

ScheduleItem designSchedule() => ScheduleItem(
      id: 'sch-d',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: Porch stripes',
      enabled: true,
      wledPayload: kApiBody,
      presetId: 12,
      designId: 'd1',
      presetKind: kSchedulePresetKindApi,
    );

ScheduleItem compose({
  ScheduleItem? editing,
  String action = 'Pattern: Porch stripes',
  bool isRunPattern = true,
  bool audio = false,
  Map<String, dynamic>? picked,
  String? pickedDesignId,
  String? pickedPresetKind,
}) =>
    composeEditedSchedule(
      id: editing?.id ?? 'new',
      editing: editing,
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      days: const ['Mon'],
      actionLabel: action,
      enabled: true,
      isRunPattern: isRunPattern,
      useAudioReactive: audio,
      pickedPayload: picked,
      pickedDesignId: pickedDesignId,
      pickedPresetKind: pickedPresetKind,
    );

void main() {
  test('a fresh pick of a painted design sets the body, design_id and kind', () {
    final item = compose(
        picked: kApiBody,
        pickedDesignId: 'd1',
        pickedPresetKind: kSchedulePresetKindApi);
    expect(item.wledPayload, kApiBody);
    expect(item.designId, 'd1');
    expect(item.presetKind, 'api');
    expect(item.isDesignApiPreset, isTrue);
  });

  test('a catalog pick carries no design fields', () {
    final item = compose(picked: kCatalog);
    expect(item.wledPayload, kCatalog);
    expect(item.designId, isNull);
    expect(item.presetKind, isNull);
  });

  test('editing a design schedule without re-picking keeps body, id and kind',
      () {
    final item = compose(editing: designSchedule());
    expect(item.id, 'sch-d');
    expect(item.wledPayload, kApiBody);
    expect(item.designId, 'd1');
    expect(item.presetKind, 'api');
    expect(item.presetId, 12);
  });

  test('re-picking a catalog pattern over a design schedule clears the fields',
      () {
    final item = compose(
        editing: designSchedule(), action: 'Pattern: Harvest', picked: kCatalog);
    expect(item.wledPayload, kCatalog);
    expect(item.designId, isNull);
    expect(item.presetKind, isNull);
  });

  test('re-picking another design over a design schedule swaps the id', () {
    final item = compose(
        editing: designSchedule(),
        picked: kApiBody,
        pickedDesignId: 'd2',
        pickedPresetKind: kSchedulePresetKindApi);
    expect(item.designId, 'd2');
    expect(item.presetKind, 'api');
  });

  test('a design schedule edited to Turn Off drops the picture and the fields',
      () {
    final item = compose(
        editing: designSchedule(), action: 'Turn Off', isRunPattern: false);
    expect(item.wledPayload, isNull,
        reason: 'a picture on a Turn Off would be refused by the sync as a '
            'stray and the OFF timer would not arm');
    expect(item.designId, isNull);
    expect(item.presetKind, isNull);
  });

  test('a design schedule switched to React to Music drops the picture', () {
    final item = compose(editing: designSchedule(), audio: true);
    expect(item.wledPayload, isNull);
    expect(item.presetKind, isNull);
    expect(item.useAudioReactive, isTrue);
  });

  test('a catalog schedule edited to Turn Off still round-trips its payload',
      () {
    final catalog = designSchedule().copyWith(
        wledPayload: kCatalog, clearDesign: true, actionLabel: 'Pattern: X');
    final item =
        compose(editing: catalog, action: 'Turn Off', isRunPattern: false);
    expect(item.wledPayload, kCatalog, reason: 'the rule that stood before');
  });
}
