// Roofline slice 2, D4 — the editor's "Just this day" save composes through
// composeDatedEntryOrRefusal, which turns the composer's PerPixelDesignRefused
// throw into the customer sentence instead of letting it escape the save
// (my_schedule_page.dart had no catch around composeDatedEntry; reachable
// once the picker hands painted designs to the schedule, A2).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/per_pixel_payload_guard.dart';
import 'package:nexgen_command/features/schedule/dated_entry_compose.dart';

final date = DateTime(2026, 11, 6);

const kCatalog = {
  'on': true,
  'seg': [
    {
      'fx': 2,
      'col': [
        [255, 0, 0, 0]
      ]
    }
  ],
};

const kPerPixel = {
  'on': true,
  'seg': [
    {
      'id': 0,
      'i': [0, 10, [255, 0, 0, 0]]
    }
  ],
};

const kApiBody = {
  'o': true,
  'on': true,
  'bri': 180,
  'seg': [
    {'id': 0, 'start': 0, 'stop': 100},
    {
      'id': 0,
      'on': true,
      'fx': 0,
      'i': [0, 100, [255, 0, 0, 0]]
    },
  ],
};

void main() {
  test('a painted design (per-pixel): the sentence, no throw, no entry', () {
    final r = composeDatedEntryOrRefusal(
      date: date,
      action: DatedAction.runPattern,
      onHhmm: '19:00',
      offHhmm: '23:00',
      patternName: 'Porch stripes',
      patternPayload: kPerPixel,
    );
    expect(r.entry, isNull);
    expect(r.refusal, contains('"Porch stripes"'));
    expect(r.refusal, contains('not for a single night'));
  });

  test('an API-command body: the sentence, no throw', () {
    final r = composeDatedEntryOrRefusal(
      date: date,
      action: DatedAction.runPattern,
      onHhmm: '19:00',
      offHhmm: null,
      patternName: 'Porch stripes',
      patternPayload: kApiBody,
    );
    expect(r.entry, isNull);
    expect(r.refusal, isNotNull);
  });

  test('the throwing form still throws (the lease manager relies on it)', () {
    expect(
        () => composeDatedEntry(
              date: date,
              action: DatedAction.runPattern,
              onHhmm: '19:00',
              offHhmm: null,
              patternName: 'Porch stripes',
              patternPayload: kPerPixel,
            ),
        throwsA(isA<PerPixelDesignRefused>()));
  });

  test('a catalog pattern composes as before', () {
    final r = composeDatedEntryOrRefusal(
      date: date,
      action: DatedAction.runPattern,
      onHhmm: '19:00',
      offHhmm: '23:00',
      patternName: 'Harvest Moon',
      patternPayload: kCatalog,
    );
    expect(r.refusal, isNull);
    expect(r.entry!.patternName, 'Harvest Moon');
    expect(r.entry!.wledPayload, kCatalog);
  });

  test('Off and Brightness never see a payload', () {
    expect(
        composeDatedEntryOrRefusal(
                date: date,
                action: DatedAction.powerOff,
                onHhmm: '23:00',
                offHhmm: null)
            .entry!
            .patternName,
        'Off');
  });
}
