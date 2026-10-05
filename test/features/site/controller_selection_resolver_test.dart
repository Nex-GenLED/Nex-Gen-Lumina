// #118 — the selection rule, as a table. Pure: no providers, no network.
//
// A selection is a controller RECORD (by document id) at that record's
// CURRENT address, or a transient address for a device being set up. See
// `resolveControllerSelection` for the rule order.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/site_models.dart';

// Plain record ids and documentation addresses — no real device.
const _front = ControllerInfo(id: 'front', ip: '192.0.2.10', name: 'Front');
const _back = ControllerInfo(id: 'back', ip: '192.0.2.11', name: 'Back');
const _shed = ControllerInfo(id: 'shed', ip: '192.0.2.12', name: 'Shed');
const _pending = ControllerInfo(id: 'pending', ip: '', name: 'Pending');
const _blank = ControllerInfo(id: 'blank', ip: '   ', name: 'Blank');

ControllerResolution _r(
  List<ControllerInfo> records, {
  ControllerSelection current = ControllerSelection.none,
  bool autoSelect = true,
  String? savedId,
  bool savedLoaded = true,
  Map<String, DateTime> lastConnected = const {},
  Set<String>? answered,
}) =>
    resolveControllerSelection(
      records: records,
      current: current,
      autoSelect: autoSelect,
      savedId: savedId,
      savedLoaded: savedLoaded,
      lastConnected: lastConnected,
      answered: answered,
    );

ControllerSelection _sel(ControllerInfo r) => ControllerSelection.record(r);

void main() {
  group('how many records', () {
    test('0 records → nothing', () {
      final out = _r(const []);
      expect(out.selection, ControllerSelection.none);
      expect(out.probeNeeded, isFalse);
    });

    test('1 record → that one, silently (no probe, no prompt)', () {
      final out = _r(const [_front]);
      expect(out.selection, _sel(_front));
      expect(out.probeNeeded, isFalse);
      expect(out.selection.needsChoice, isFalse);
    });

    test('1 record that has no address → nothing', () {
      expect(_r(const [_pending]).selection, ControllerSelection.none);
      expect(_r(const [_blank]).selection, ControllerSelection.none);
    });

    test('several, nothing saved, no history, not yet probed → nothing, and '
        'ask which answer', () {
      final out = _r(const [_front, _back]);
      expect(out.selection, ControllerSelection.none);
      expect(out.probeNeeded, isTrue);
    });
  });

  group('the saved choice', () {
    test('saved id present → that one, whatever the list order', () {
      final out = _r(const [_front, _back, _shed], savedId: 'back');
      expect(out.selection, _sel(_back));
      expect(out.probeNeeded, isFalse);
    });

    test('saved id gone → the most recently connected', () {
      final out = _r(const [_front, _back, _shed],
          savedId: 'deleted-record',
          lastConnected: {
            'front': DateTime(2026, 10, 1),
            'shed': DateTime(2026, 10, 3),
            'back': DateTime(2026, 10, 2),
          });
      expect(out.selection, _sel(_shed));
    });

    test('saved id gone, no history → ask which answer', () {
      final out = _r(const [_front, _back], savedId: 'deleted-record');
      expect(out.selection, ControllerSelection.none);
      expect(out.probeNeeded, isTrue);
    });

    test('several and the saved choice not read yet → wait (no guess that '
        'the saved choice would then overturn)', () {
      final out = _r(const [_front, _back], savedLoaded: false);
      expect(out.selection, ControllerSelection.none);
      expect(out.probeNeeded, isFalse);
    });

    test('ONE record does not wait for the saved choice', () {
      expect(_r(const [_front], savedLoaded: false).selection, _sel(_front));
    });

    test('a saved id whose record lost its address is not selected', () {
      final out = _r(const [_pending, _front], savedId: 'pending');
      expect(out.selection, _sel(_front));
    });
  });

  group('which controllers answer', () {
    test('two or more answer → the customer chooses; nothing selected '
        'meanwhile', () {
      final out = _r(const [_front, _back, _shed], answered: {'front', 'shed'});
      expect(out.selection.controllerId, isNull);
      expect(out.selection.ip, isNull);
      expect(out.selection.needsChoice, isTrue);
      expect(out.selection.choices, ['front', 'shed']);
    });

    test('exactly one answers → that one, no prompt', () {
      final out = _r(const [_front, _back], answered: {'back'});
      expect(out.selection, _sel(_back));
      expect(out.selection.needsChoice, isFalse);
    });

    test('none answers (away from home) → the newest record, as before', () {
      final out = _r(const [_front, _back], answered: const {});
      expect(out.selection, _sel(_front));
    });
  });

  group('following the selected record', () {
    test('the record\'s address changed → the selection follows it', () {
      const moved = ControllerInfo(id: 'front', ip: '192.0.2.50');
      final out = _r(const [moved], current: _sel(_front));
      expect(out.selection.controllerId, 'front');
      expect(out.selection.ip, '192.0.2.50');
    });

    test('cached-then-server: the old address first, then the current one',
        () {
      // A cold start's first snapshot can come from the phone's cache and
      // carry the address the record had last time; the server's arrives
      // next. The selection must end on the server's address — before #118
      // it stayed on the cached one for the whole session.
      const cached = ControllerInfo(id: 'front', ip: '192.0.2.40');
      const server = ControllerInfo(id: 'front', ip: '192.0.2.41');
      final first = _r(const [cached]);
      expect(first.selection.ip, '192.0.2.40');
      final second = _r(const [server], current: first.selection);
      expect(second.selection.controllerId, 'front');
      expect(second.selection.ip, '192.0.2.41');
    });

    test('a selected record that is not the newest stays selected (no snap '
        'back to the first record)', () {
      final out = _r(const [_front, _back, _shed], current: _sel(_back));
      expect(out.selection, _sel(_back));
      expect(out.probeNeeded, isFalse);
    });

    test('the empty-address NEWEST record is skipped', () {
      // Before #118 auto-connect looked only at the newest record and, with
      // no address there, selected nothing at all.
      final out = _r(const [_pending, _back]);
      expect(out.selection, _sel(_back));
    });

    test('deleting the active controller → the next record', () {
      final out = _r(const [_back], current: _sel(_front));
      expect(out.selection, _sel(_back));
    });

    test('deleting the active controller with several left → the most '
        'recently connected of the rest', () {
      final out = _r(const [_back, _shed],
          current: _sel(_front),
          lastConnected: {'back': DateTime(2026, 10, 4)});
      expect(out.selection, _sel(_back));
    });

    test('the previous account\'s record is not in this account\'s list → '
        'this account\'s own record', () {
      const otherAccount = ControllerInfo(id: 'not-mine', ip: '192.0.2.90');
      final out = _r(const [_front], current: _sel(otherAccount));
      expect(out.selection, _sel(_front));
      expect(out.selection.ip, isNot('192.0.2.90'));
    });
  });

  group('a transient address (a device being set up)', () {
    const setting = ControllerSelection(ip: '192.0.2.77', transient: true);

    test('is kept while records change — never pulled away mid-setup', () {
      for (final records in const [
        <ControllerInfo>[],
        [_front],
        [_front, _back],
      ]) {
        final out = _r(records, current: setting, savedId: 'front');
        expect(out.selection, setting, reason: '$records');
      }
    });

    test('becomes the record once a record has its address', () {
      const saved = ControllerInfo(id: 'new-one', ip: '192.0.2.77');
      final out = _r(const [_front, saved], current: setting);
      expect(out.selection, _sel(saved));
      expect(out.selection.transient, isFalse);
    });
  });

  group('outside the app shell (auto-select not armed)', () {
    test('nothing is chosen on its own', () {
      expect(_r(const [_front], autoSelect: false).selection,
          ControllerSelection.none);
      expect(_r(const [_front, _back], autoSelect: false).probeNeeded, isFalse);
    });

    test('an explicit choice is still followed and dropped', () {
      const moved = ControllerInfo(id: 'front', ip: '192.0.2.51');
      expect(_r(const [moved], current: _sel(_front), autoSelect: false)
          .selection
          .ip, '192.0.2.51');
      expect(
          _r(const [_back], current: _sel(_front), autoSelect: false).selection,
          ControllerSelection.none);
    });
  });
}
