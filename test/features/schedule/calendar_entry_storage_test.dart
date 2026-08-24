// Scheduling V3 A1 — the composite-key storage codec.
//
// The load-bearing claim these tests defend is BACKWARD COMPATIBILITY: an old
// build must keep working against a document a new build wrote. P4 in
// audit/SCHEDULE_V3_P2.md sets out the shape; this is its executable form.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_storage.dart';

CalendarEntry _e(String dateKey, String entryId, {String on = '18:00'}) =>
    CalendarEntry(
      entryId: entryId,
      dateKey: dateKey,
      patternName: 'P-$entryId',
      onTime: on,
      offTime: '23:00',
      type: CalendarEntryType.user,
    );

/// Exactly what the pre-V3 loader did: key the result by the RAW map key.
/// (user_service.dart:872-878 — this is why a composite key is invisible to an
/// old build rather than corrupting it.)
Map<String, CalendarEntry> _oldBuildLoad(Map<String, dynamic> raw) {
  final out = <String, CalendarEntry>{};
  for (final e in raw.entries) {
    if (e.value is Map) {
      out[e.key] = CalendarEntry.fromJson(Map<String, dynamic>.from(e.value));
    }
  }
  return out;
}

void main() {
  group('encode', () {
    test('a single entry writes the plain date key — byte-compatible', () {
      final set = CalendarEntrySet.fromEntries([_e('2026-05-31', 'user_1')]);
      final raw = encodeCalendarEntries(set);
      expect(raw.keys, ['2026-05-31']);
      expect(raw['2026-05-31']!['dateKey'], '2026-05-31');
    });

    test('the LAST entry on a date takes the plain key; others are suffixed', () {
      final set = CalendarEntrySet.fromEntries([
        _e('2026-05-31', 'gd_royals', on: '13:05'),
        _e('2026-05-31', 'gd_chiefs', on: '19:10'),
      ]);
      final raw = encodeCalendarEntries(set);
      expect(raw.keys.toSet(), {'2026-05-31', '2026-05-31#gd_royals'});
      // chiefs was written last ⇒ it is the primary ⇒ it owns the plain key.
      expect(raw['2026-05-31']!['entryId'], 'gd_chiefs');
    });
  });

  group('decode', () {
    test('a pre-V3 document (plain keys, no entryId) reads correctly', () {
      final set = decodeCalendarEntries({
        '2026-05-31': {
          'dateKey': '2026-05-31',
          'patternName': 'Royals',
          'onTime': '13:05',
          'type': 'autopilot',
        },
      });
      expect(set.totalEntries, 1);
      expect(set.forDate('2026-05-31').single.entryId, CalendarEntryId.legacy);
      expect(set['2026-05-31']!.patternName, 'Royals');
    });

    test('composite keys group under the date and the primary lands last', () {
      final set = decodeCalendarEntries({
        '2026-05-31#gd_royals': {
          'dateKey': '2026-05-31',
          'patternName': 'Royals',
          'onTime': '13:05',
        },
        '2026-05-31': {
          'dateKey': '2026-05-31',
          'patternName': 'Chiefs',
          'onTime': '19:10',
        },
      });
      final day = set.forDate('2026-05-31');
      expect(day.length, 2);
      expect(day.last.patternName, 'Chiefs', reason: 'plain key ⇒ primary ⇒ last');
      expect(set['2026-05-31']!.patternName, 'Chiefs');
    });

    test('the composite suffix wins over a stale stored entryId', () {
      final set = decodeCalendarEntries({
        '2026-05-31#real_id': {
          'dateKey': '2026-05-31',
          'entryId': 'stale_id',
          'patternName': 'X',
        },
      });
      expect(set.forDate('2026-05-31').single.entryId, 'real_id');
    });

    test('a value missing dateKey falls back to the key prefix', () {
      final set = decodeCalendarEntries({
        '2026-05-31#a': {'patternName': 'X'},
      });
      expect(set.forDate('2026-05-31').single.patternName, 'X');
    });

    test('a corrupt row is skipped and reported, never thrown', () {
      final bad = <String, Object>{};
      final set = decodeCalendarEntries(
        {
          '2026-05-31': 'not-a-map',
          '2026-06-01': {'dateKey': '2026-06-01', 'patternName': 'Good'},
        },
        onCorrupt: (k, e) => bad[k] = e,
      );
      expect(bad.keys, ['2026-05-31']);
      expect(set.totalEntries, 1);
    });

    test('decode order does not depend on map iteration order', () {
      Map<String, dynamic> row(String p, String t) =>
          {'dateKey': '2026-05-31', 'patternName': p, 'onTime': t};
      final a = decodeCalendarEntries({
        '2026-05-31': row('Primary', '20:00'),
        '2026-05-31#b': row('B', '19:00'),
        '2026-05-31#a': row('A', '18:00'),
      });
      final b = decodeCalendarEntries({
        '2026-05-31#a': row('A', '18:00'),
        '2026-05-31': row('Primary', '20:00'),
        '2026-05-31#b': row('B', '19:00'),
      });
      expect(a.forDate('2026-05-31').map((e) => e.patternName).toList(),
          ['A', 'B', 'Primary']);
      expect(a.forDate('2026-05-31').map((e) => e.patternName).toList(),
          b.forDate('2026-05-31').map((e) => e.patternName).toList());
    });
  });

  test('round-trips', () {
    final original = CalendarEntrySet.fromEntries([
      _e('2026-05-31', 'a', on: '18:00'),
      _e('2026-05-31', 'b', on: '19:00'),
      _e('2026-06-01', 'c', on: '20:00'),
    ]);
    final decoded = decodeCalendarEntries(encodeCalendarEntries(original));
    expect(decoded.totalEntries, 3);
    expect(decoded.forDate('2026-05-31').map((e) => e.entryId).toList(),
        ['a', 'b']);
    expect(decoded['2026-05-31']!.entryId, 'b');
    expect(decoded['2026-06-01']!.entryId, 'c');
  });

  group('BACKWARD COMPATIBILITY — what an OLD build does', () {
    test('it finds the primary under the plain key, exactly as before', () {
      final raw = encodeCalendarEntries(CalendarEntrySet.fromEntries([
        _e('2026-05-31', 'gd_royals', on: '13:05'),
        _e('2026-05-31', 'gd_chiefs', on: '19:10'),
      ]));

      final oldState = _oldBuildLoad(raw);
      // Its only lookup shape is `entries[todayKey]`.
      expect(oldState['2026-05-31']!.entryId, 'gd_chiefs');
      // The extra row is present but under a key it never queries — INVISIBLE,
      // not corrupting. One entry per date, which is its pre-V3 behaviour.
      expect(oldState.containsKey('2026-05-31#gd_royals'), isTrue);
    });

    test('an old build that SAVES preserves the extra rows verbatim', () {
      final raw = encodeCalendarEntries(CalendarEntrySet.fromEntries([
        _e('2026-05-31', 'gd_royals'),
        _e('2026-05-31', 'gd_chiefs'),
      ]));

      // The old save path round-trips its own state map: map[key] = value.toJson().
      final oldState = _oldBuildLoad(raw);
      final rewritten = <String, dynamic>{
        for (final e in oldState.entries) e.key: e.value.toJson(),
      };

      // A new build reads back BOTH entries. This is the property a nested-list
      // shape would have destroyed.
      final reread = decodeCalendarEntries(rewritten);
      expect(reread.forDate('2026-05-31').length, 2);
      expect(reread.forDate('2026-05-31').map((e) => e.entryId).toSet(),
          {'gd_royals', 'gd_chiefs'});
    });

    test('DOCUMENTED COST: an old toJson strips the four V3 fields', () {
      // Simulated: the pre-V3 toJson emitted exactly these keys.
      const legacyKeys = {
        'dateKey', 'patternName', 'color', 'onTime', 'offTime',
        'brightness', 'type', 'autopilot', 'note', 'sourceTag',
      };
      final v3 = CalendarEntry(
        entryId: 'gd_royals',
        dateKey: '2026-05-31',
        patternName: 'Royals',
        onTime: '13:05',
        sourceTag: CalendarEntrySourceTag.gameDay,
        endMode: CalendarEntryEndMode.untilGameEnd,
        estimatedEnd: DateTime(2026, 5, 31, 16, 5),
        hardCapAt: DateTime(2026, 5, 31, 17, 5),
        channels: const [0, 1],
      );
      final stripped = <String, dynamic>{
        for (final e in v3.toJson().entries)
          if (legacyKeys.contains(e.key)) e.key: e.value,
      };

      final reread = CalendarEntry.fromJson(stripped);
      expect(reread.channels, isNull);
      expect(reread.hardCapAt, isNull);
      // It degrades to the LEGACY READ, not to nonsense: still open-ended,
      // because sourceTag+offTime inference survives. Here offTime was never
      // written (V3 stopped emitting it for Game Day), so there is no estimate
      // and no fabricated end — the honest floor.
      expect(reread.endMode, CalendarEntryEndMode.fixedTime);
      expect(reread.estimatedEnd, isNull);
      expect(reread.entryId, CalendarEntryId.legacy,
          reason: 'and it loses its identity, collapsing back to one-per-date');
    });
  });
}
