// +122 item 5 (TD-8 defect 1): Light Up Now's revert capture never stores a
// collapsed or half-healed layout as the look to come back to.
//
// GameDayScreen._activateNow captured the revert as the raw /json/state with
// no check of the segment layout; a post-restart one-segment layout was stored
// verbatim, bounds included, and the session put the house back in that shape
// at final + 30 min. Now the live layout is compared with the controller's
// own channels: a match is captured (geometry fields stripped, inactive
// segments dropped); a mismatch on the LAN is repaired first — the shared
// geometry re-heal, segment 0's look on the re-created segment — and re-read;
// a mismatch that cannot be repaired (the relay, a repair that did not land)
// is REFUSED with a message, never stored.
//
// Fixtures: the two-channel layout and the one-segment-after-restart layout.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/revert_capture.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_lan_controller.dart';
import '../../helpers/recording_wled_repository.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 90, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 90, stop: 180, gpioPin: 14),
];

Map<String, dynamic> _state(List<Map<String, dynamic>> segs) => {
      'on': true,
      'bri': 200,
      'transition': 7,
      'ps': 2,
      'seg': segs,
    };

/// A non-LAN repository (the relay's shape): canned state, no provisioning
/// door.
class _RelayLike extends RecordingWledRepository {
  _RelayLike(this.canned, {this.throws = false});
  final Map<String, dynamic> canned;
  final bool throws;
  @override
  Future<Map<String, dynamic>?> getState() async {
    if (throws) throw const SocketException('relay timeout');
    return canned;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('revertLookFromState — what is stored', () {
    test('geometry fields are stripped, inactive segments dropped, the look '
        'and the root kept', () {
      final look = revertLookFromState(_state([
        {...lanSeg(0, 0, 90), 'rev': true, 'mi': false, 'of': 0, 'grp': 1, 'spc': 0},
        lanSeg(1, 90, 180),
        lanSeg(2, 0, 0), // a deleted slot as WLED reports it
      ]));
      expect(look['on'], isTrue);
      expect(look['bri'], 200);
      expect(look['transition'], 7);
      final segs = (look['seg'] as List).cast<Map>();
      expect(segs.map((s) => s['id']), [0, 1]);
      for (final s in segs) {
        for (final k in ['start', 'stop', 'len', 'rev', 'mi', 'of', 'grp', 'spc']) {
          expect(s.keys, isNot(contains(k)), reason: '$k on segment ${s['id']}');
        }
        expect(s['col'][0], [227, 24, 55, 0]);
        expect(s['fx'], 0);
      }
    });
  });

  group('non-LAN repository (no provisioning door)', () {
    test('two-channel layout → captured as the look, no writes', () async {
      final repo = _RelayLike(_state([lanSeg(0, 0, 90), lanSeg(1, 90, 180)]));
      final c = await captureRevertLook(repo: repo, channels: _channels);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
      expect((c.payload['seg'] as List).length, 2);
      expect(((c.payload['seg'] as List).first as Map).keys, isNot(contains('stop')));
      expect(repo.applied, isEmpty);
    });

    test('one segment after a restart → REFUSED with the message; nothing '
        'stored, nothing written', () async {
      final repo = _RelayLike(_state([lanSeg(0, 0, 180)]));
      final c = await captureRevertLook(repo: repo, channels: _channels);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(c.payload, isEmpty);
      expect(c.message, kRevertCaptureRefusedMessage);
      expect(repo.applied, isEmpty);
    });

    test('no channel model (simulation, cfg never read) → captured unchecked, '
        'as before', () async {
      final repo = _RelayLike(_state([lanSeg(0, 0, 180)]));
      final c = await captureRevertLook(repo: repo, channels: const []);
      expect(c.outcome, RevertCaptureOutcome.capturedUnchecked);
      expect((c.payload['seg'] as List).length, 1);
    });

    test('an unreadable state → refused', () async {
      final repo = _RelayLike(const {}, throws: true);
      final c = await captureRevertLook(repo: repo, channels: _channels);
      expect(c.outcome, RevertCaptureOutcome.refused);
    });
  });

  group('LAN service against the stateful fake controller', () {
    late FakeLanController ctl;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      resetWledHttpClientsForTest();
      ctl = FakeLanController(segs: [lanSeg(0, 0, 90), lanSeg(1, 90, 180)]);
      await ctl.start();
    });

    tearDown(() => ctl.stop());

    test('two-channel layout → captured, zero writes', () async {
      if (ctl.base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      final c = await captureRevertLook(
          repo: WledService(ctl.base!), channels: _channels);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
      expect(ctl.posted, isEmpty);
      expect((c.payload['seg'] as List).length, 2);
    });

    test('one segment after a restart → repaired first (segment 1 re-created '
        'with segment 0\'s look), re-read, captured with BOTH segments',
        () async {
      if (ctl.base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      ctl.segs = [lanSeg(0, 0, 180, fx: 12)];
      final c = await captureRevertLook(
          repo: WledService(ctl.base!), channels: _channels);
      expect(c.outcome, RevertCaptureOutcome.capturedAfterRepair, reason: c.note);
      expect(ctl.posted, hasLength(1), reason: 'the one repair POST');
      final segs = (c.payload['seg'] as List).cast<Map>();
      expect(segs.map((s) => s['id']), [0, 1]);
      expect(segs[1]['fx'], 12, reason: 'segment 0\'s look, not amber');
      expect(segs[1]['col'][0], [227, 24, 55, 0]);
      expect(segs[1].keys, isNot(contains('stop')));
    });

    test('a repair that does not land → refused, never stored', () async {
      if (ctl.base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      ctl.segs = [lanSeg(0, 0, 180)];
      ctl.dropFirstPosts = 1;
      final c = await captureRevertLook(
          repo: WledService(ctl.base!), channels: _channels);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(c.payload, isEmpty);
      expect(ctl.posted, hasLength(1));
    });
  });
}
