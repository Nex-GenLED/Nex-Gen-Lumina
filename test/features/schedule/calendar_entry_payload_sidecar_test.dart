// +112 — a dated entry's WLED payload survives the calendar rewrite an older
// build performs, through the `calendar_entry_payload` sidecar.
//
// "Older build" here means builds 109–111: they decode each `calendar_entries`
// row through `CalendarEntry.fromJson` (known keys only — unknown keys are
// ignored) and re-encode through `toJson` (known keys only), and their
// `saveCalendarEntries` updates exactly `calendar_entries`,
// `calendar_entry_scope` and `updated_at`. [legacyRewrite] below reproduces
// that write byte for byte on the fields it touches, and leaves the payload
// sidecar untouched because those builds never read or write it.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_storage.dart';
import 'package:nexgen_command/features/schedule/payload_sidecar.dart';

const _payload = <String, dynamic>{
  'on': true,
  'bri': 217,
  'seg': [
    {
      'fx': 12,
      'sx': 40,
      'ix': 180,
      'pal': 5,
      'col': [
        [227, 24, 55, 0],
        [255, 184, 28, 0],
      ],
    },
  ],
};

CalendarEntry _entry({String? dateKey, Map<String, dynamic>? payload}) =>
    CalendarEntry(
      dateKey: dateKey ?? '2026-10-09',
      patternName: 'Team Night',
      color: const Color(0xFFE31837),
      onTime: '19:00',
      offTime: '23:00',
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: false,
      wledPayload: payload ?? _payload,
    );

/// What a 109–111 build does to the calendar when it saves: every row goes
/// through fromJson → toJson of a model that has no `wledPayload`, which is
/// exactly "drop that key"; every other key is carried verbatim.
Map<String, Map<String, dynamic>> legacyRewrite(
    Map<String, Map<String, dynamic>> rows) {
  return {
    for (final e in rows.entries)
      e.key: Map<String, dynamic>.from(e.value)..remove('wledPayload'),
  };
}

void main() {
  group('CalendarEntry.wledPayload codec', () {
    test('round-trips inline as a JSON string, never a nested list', () {
      final json = _entry().toJson();
      expect(json['wledPayload'], isA<String>(),
          reason: 'WLED col is an array of arrays; Firestore refuses it '
              'natively (#84), so the inline copy is a string');
      final back = CalendarEntry.fromJson(json);
      expect(back.wledPayload, _payload);
    });

    test('an older build reads a row carrying the key without throwing', () {
      // Older fromJson ignores unknown keys; the current one parses it. Both
      // must accept the row — the current build proves the shape is a valid
      // row, which is the property the older build relies on.
      final json = _entry().toJson();
      expect(() => CalendarEntry.fromJson(json), returnsNormally);
      expect(CalendarEntry.fromJson(json..remove('wledPayload')).wledPayload,
          isNull);
    });

    test('a corrupt inline payload collapses to null, never a crash', () {
      final json = _entry().toJson()..['wledPayload'] = '{not json';
      expect(CalendarEntry.fromJson(json).wledPayload, isNull);
    });
  });

  group('payload sidecar', () {
    test('a 111-style read/write round trip keeps the payload', () {
      final set = CalendarEntrySet.fromEntries([_entry()]);
      final encoded = encodeCalendarEntriesWithScope(set);
      expect(encoded.payload, isNotEmpty);

      // The older build rewrites calendar_entries (dropping the inline key)
      // and does not touch the payload field.
      final afterLegacy = legacyRewrite(encoded.entries);
      expect(afterLegacy.values.first.containsKey('wledPayload'), isFalse);

      final decoded = decodeCalendarEntries(
        afterLegacy,
        scopeSidecar: encoded.scope,
        payloadSidecar: encoded.payload,
      );
      final back = decoded['2026-10-09'];
      expect(back, isNotNull);
      expect(back!.wledPayload, _payload,
          reason: 'the sidecar restores what the older write dropped');
    });

    test('a replaced entry does not inherit a stale payload', () {
      final set = CalendarEntrySet.fromEntries([_entry()]);
      final encoded = encodeCalendarEntriesWithScope(set);

      // An older build replaces the primary at the same key with a different
      // entry (different name and colour) and leaves the sidecar behind.
      final replaced = const CalendarEntry(
        dateKey: '2026-10-09',
        patternName: 'Warm White',
        color: Color(0xFFFFE8C0),
        onTime: '19:00',
        offTime: '23:00',
        brightness: 60,
        type: CalendarEntryType.user,
        autopilot: false,
      ).toJson()
        ..remove('wledPayload');

      final decoded = decodeCalendarEntries(
        {'2026-10-09': replaced},
        payloadSidecar: encoded.payload,
      );
      expect(decoded['2026-10-09']!.wledPayload, isNull,
          reason: 'fingerprint (name + colour) no longer matches');
    });

    test('composite keys carry their own row', () {
      final a = _entry().copyWith(entryId: 'a');
      final b = _entry().copyWith(
          entryId: 'b',
          patternName: 'Second Look',
          wledPayload: const {'on': true, 'bri': 10});
      final set = CalendarEntrySet.fromEntries([a, b]);
      final encoded = encodeCalendarEntriesWithScope(set);
      expect(encoded.payload.keys, containsAll(['2026-10-09', '2026-10-09#a']));

      final decoded = decodeCalendarEntries(
        legacyRewrite(encoded.entries),
        payloadSidecar: encoded.payload,
      );
      final rows = decoded.forDate('2026-10-09');
      expect(rows.map((e) => e.wledPayload), containsAll([
        _payload,
        {'on': true, 'bri': 10},
      ]));
    });

    test('no payload, no sidecar row', () {
      final set = CalendarEntrySet.fromEntries([_entry(payload: null)
          .copyWith(clearPayload: true)]);
      final encoded = encodeCalendarEntriesWithScope(set);
      expect(encoded.payload, isEmpty);
    });

    test('decode helper refuses malformed rows', () {
      expect(
        decodePayloadSidecarEntry(
          {'k': {'p': 'nope', 'n': 'x', 'col': null}},
          'k',
          patternName: 'x',
          colorHex: null,
        ),
        isNull,
      );
      expect(
        decodePayloadSidecarEntry(
          {'k': {'p': jsonEncode({'on': true}), 'n': 'x'}},
          'k',
          patternName: 'x',
          colorHex: null,
        ),
        {'on': true},
      );
    });
  });
}
