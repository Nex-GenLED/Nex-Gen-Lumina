// Scheduling V3 D1 — the durable channel-scope sidecar.
//
// THE PROPERTY UNDER TEST is not "the field round-trips". It is that the scope
// survives a write performed by a build that has never heard of it — because
// both stores rewrite EVERY entry through `toJson()` on an ordinary edit (P1),
// so one edit on an old build would otherwise un-scope the whole account and
// silently relight channels the customer excluded.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_storage.dart';
import 'package:nexgen_command/features/schedule/data/schedule_store_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/scope_sidecar.dart';

/// The exact key set a pre-D1 `CalendarEntry.toJson()` emitted.
const _preD1CalendarKeys = {
  'entryId', 'dateKey', 'patternName', 'color', 'onTime', 'offTime',
  'brightness', 'type', 'autopilot', 'note', 'sourceTag',
  'endMode', 'estimatedEnd', 'hardCapAt',
};

/// The exact key set a pre-D1 `ScheduleItem.toJson()` emitted.
const _preD1ScheduleKeys = {
  'id', 'timeLabel', 'offTimeLabel', 'repeatDays', 'actionLabel', 'enabled',
  'wledPayload', 'presetId', 'useAudioReactive', 'disabledUntil',
  'sourcePromptId', 'sortKey',
};

Map<String, dynamic> _strip(Map<String, dynamic> json, Set<String> keep) => {
      for (final e in json.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };

CalendarEntry _entry(String id, {List<int>? ch, String? ctrl}) => CalendarEntry(
      entryId: id,
      dateKey: '2026-09-13',
      patternName: 'P-$id',
      onTime: '19:00',
      offTime: '23:00',
      type: CalendarEntryType.user,
      channels: ch,
      controllerId: ctrl,
    );

ScheduleItem _sched(String id, {List<int>? ch, String? ctrl}) => ScheduleItem(
      id: id,
      timeLabel: '8:00 PM',
      offTimeLabel: '6:00 AM',
      repeatDays: const ['Daily'],
      actionLabel: 'Pattern: Warm White',
      enabled: true,
      channels: ch,
      controllerId: ctrl,
    );

void main() {
  group('ItemScope + codec', () {
    test('unscoped items are OMITTED, so the field stays absent entirely', () {
      final sidecar = encodeScopeSidecar({
        'a': const ItemScope(),
        'b': const ItemScope(channels: null, controllerId: 'ctrl-1'),
      });
      expect(sidecar, isEmpty,
          reason: 'a controllerId without channels is not a scope');
    });

    test('a scoped item encodes to the short shape', () {
      final sidecar = encodeScopeSidecar({
        'a': const ItemScope(channels: [0, 2], controllerId: 'ctrl-1'),
      });
      expect(sidecar, {
        'a': {'c': 'ctrl-1', 'ch': [0, 2]}
      });
    });

    test('ch is a FLAT list of ints — never nested (#84)', () {
      final sidecar = encodeScopeSidecar({
        'a': const ItemScope(channels: [0, 1], controllerId: 'c'),
      });
      final ch = (sidecar['a'] as Map)['ch'] as List;
      expect(ch.every((e) => e is int), isTrue);
    });

    test('a corrupt sidecar degrades to unscoped, never throws', () {
      for (final bad in <dynamic>[
        null,
        'not-a-map',
        42,
        {'a': 'not-a-map'},
        {'a': {'ch': 'not-a-list'}},
        {'a': {'c': 'ctrl'}}, // no ch
      ]) {
        expect(decodeScopeEntry(bad, 'a'), ItemScope.none, reason: '$bad');
      }
    });

    test('non-numeric channel members are dropped, not fatal', () {
      final s = decodeScopeEntry({'a': {'ch': [0, 'x', 2, null]}}, 'a');
      expect(s.channels, [0, 2]);
    });

    test('resolveScope prefers the model and falls back to the sidecar', () {
      const sidecar = {'k': {'c': 'from-sidecar', 'ch': [3]}};

      // Model present ⇒ model wins.
      expect(
        resolveScope(
            modelChannels: const [1],
            modelControllerId: 'from-model',
            sidecar: sidecar,
            key: 'k'),
        const ItemScope(channels: [1], controllerId: 'from-model'),
      );

      // Model stripped ⇒ sidecar rescues it. THIS is the whole mechanism.
      expect(
        resolveScope(
            modelChannels: null,
            modelControllerId: null,
            sidecar: sidecar,
            key: 'k'),
        const ItemScope(channels: [3], controllerId: 'from-sidecar'),
      );

      // Neither ⇒ genuinely all-channel.
      expect(
        resolveScope(
            modelChannels: null,
            modelControllerId: null,
            sidecar: sidecar,
            key: 'other'),
        ItemScope.none,
      );
    });
  });

  group('CALENDAR store — survives an old-build rewrite', () {
    test('scope is recovered after every new field is stripped', () {
      final set = CalendarEntrySet.fromEntries([
        _entry('gd_royals', ch: const [0], ctrl: 'ctrl-A'),
        _entry('user_1'), // unscoped, stays unscoped
      ]);
      final written = encodeCalendarEntriesWithScope(set);

      expect(written.scope.keys, ['2026-09-13#gd_royals'],
          reason: 'only the scoped entry gets a sidecar row');

      // ── the old build rewrites `calendar_entries` and never names the
      //    sidecar field, so the sidecar survives verbatim ──
      final rewritten = <String, dynamic>{
        for (final e in written.entries.entries)
          e.key: _strip(e.value, _preD1CalendarKeys),
      };
      // Sanity: the strip really did remove the model fields.
      expect((rewritten['2026-09-13#gd_royals'] as Map).containsKey('channels'),
          isFalse);

      final reloaded =
          decodeCalendarEntries(rewritten, scopeSidecar: written.scope);
      final royals = reloaded.byId('2026-09-13', 'gd_royals')!;
      expect(royals.channels, [0], reason: 'RECOVERED from the sidecar');
      expect(royals.controllerId, 'ctrl-A');

      final user = reloaded.byId('2026-09-13', 'user_1')!;
      expect(user.channels, isNull, reason: 'unscoped stays unscoped');
    });

    test('WITHOUT the sidecar the scope is genuinely lost — the control', () {
      final set = CalendarEntrySet.fromEntries(
          [_entry('gd_royals', ch: const [0], ctrl: 'ctrl-A')]);
      final written = encodeCalendarEntriesWithScope(set);
      final rewritten = <String, dynamic>{
        for (final e in written.entries.entries)
          e.key: _strip(e.value, _preD1CalendarKeys),
      };
      final reloaded = decodeCalendarEntries(rewritten); // no sidecar
      expect(reloaded['2026-09-13']!.channels, isNull,
          reason: 'proves the previous test is testing the sidecar, not toJson');
    });

    test('clearing the scope removes its sidecar row', () {
      final scoped = CalendarEntrySet.fromEntries(
          [_entry('a', ch: const [0], ctrl: 'ctrl-A')]);
      expect(encodeCalendarEntriesWithScope(scoped).scope, isNotEmpty);

      final cleared = CalendarEntrySet.fromEntries(
          [_entry('a', ch: const [0], ctrl: 'ctrl-A').copyWith(clearScope: true)]);
      expect(encodeCalendarEntriesWithScope(cleared).scope, isEmpty,
          reason: 'a cleared scope must not linger as a tombstone');
    });

    test('the model field wins when both are present and disagree', () {
      final set = CalendarEntrySet.fromEntries(
          [_entry('a', ch: const [1], ctrl: 'new')]);
      final written = encodeCalendarEntriesWithScope(set);
      final reloaded = decodeCalendarEntries(
        written.entries,
        scopeSidecar: {'2026-09-13': {'c': 'stale', 'ch': [9]}},
      );
      expect(reloaded['2026-09-13']!.channels, [1]);
      expect(reloaded['2026-09-13']!.controllerId, 'new');
    });
  });

  group('SCHEDULE store — survives an old-build rewrite', () {
    test('scope is recovered after every new field is stripped', () {
      final items = [
        _sched('sch-1', ch: const [1], ctrl: 'ctrl-B'),
        _sched('sch-2'),
      ];
      final sidecar = scheduleScopeSidecar(items);
      expect(sidecar.keys, ['sch-1']);

      // Old build: whole array rewritten through the pre-D1 toJson.
      final rewritten = <String, dynamic>{
        'schedules': [
          for (final i in items) _strip(i.toJson(), _preD1ScheduleKeys)
        ],
        kScheduleScopeField: sidecar,
      };
      expect((rewritten['schedules'] as List).first.containsKey('channels'),
          isFalse);

      final reloaded = decodeScheduleArray(rewritten);
      expect(reloaded.first.channels, [1], reason: 'RECOVERED');
      expect(reloaded.first.controllerId, 'ctrl-B');
      expect(reloaded[1].channels, isNull);
    });

    test('WITHOUT the sidecar the scope is genuinely lost — the control', () {
      final items = [_sched('sch-1', ch: const [1], ctrl: 'ctrl-B')];
      final rewritten = <String, dynamic>{
        'schedules': [_strip(items.first.toJson(), _preD1ScheduleKeys)],
      };
      expect(decodeScheduleArray(rewritten).first.channels, isNull);
    });

    test('clearing the scope removes its sidecar row', () {
      final cleared = [_sched('sch-1', ch: const [1], ctrl: 'c').copyWith(clearScope: true)];
      expect(scheduleScopeSidecar(cleared), isEmpty);
    });
  });
}
