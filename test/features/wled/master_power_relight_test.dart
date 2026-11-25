// Build 133, fix 1 — the master power-ON relights the channels.
//
// After a timed OFF, the OFF preset (slot 2) stores EVERY segment `on:false`.
// The Home power circle used to send `{"on":true}` alone, so the master came
// on while every channel stayed dark. Turning ON now looks at the live state
// the poller last read: when it shows EVERY channel off, the ON names every
// channel (`{"on":true,"seg":[{"id":n,"on":true}, ...]}` — the "All Channels
// On" payload). When at least one channel is on, or the live state is unknown
// or stale, the ON stays master-only, so a channel someone deliberately
// switched off stays off.
//
// Every test runs the REAL WledNotifier against a fake controller, with fake
// time (testWidgets) and an injected clock: no real sleeps, no wall clock.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart'
    show currentPixelMapChannelsProvider;
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/voice/dashboard_voice_control.dart';
import 'package:nexgen_command/features/voice/deep_link_service.dart';
import 'package:nexgen_command/features/voice/siri_shortcut_service.dart'
    show SiriActivityTypes;
import 'package:nexgen_command/features/voice/voice_providers.dart';
import 'package:nexgen_command/features/wled/channel_power_payload.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fake controller ─────────────────────────────────────────────────────────

class _FakeController implements WledRepository {
  /// What `GET /json/state` answers. Null = the controller did not answer.
  Map<String, dynamic>? live;

  final List<Map<String, dynamic>> applied = [];
  final List<Map<String, dynamic>> setStates = [];

  /// Every power write in order, in one shape: an applyJson body, or the
  /// setState fields rendered as the body the transport would send.
  List<Map<String, dynamic>> get powerWrites => [
        for (final p in _writes) p,
      ];
  final List<Map<String, dynamic>> _writes = [];

  @override
  Future<Map<String, dynamic>?> getState() async => live;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    final copy = _deepCopy(payload);
    applied.add(copy);
    _writes.add(copy);
    _applyPower(copy);
    return true;
  }

  /// Power writes land on [live] as WLED applies them: root `on`, and each
  /// named segment's `on`.
  void _applyPower(Map<String, dynamic> body) {
    final state = live;
    if (state == null) return;
    if (body['on'] is bool) state['on'] = body['on'];
    final segs = body['seg'];
    if (segs is! List) return;
    for (final s in segs) {
      if (s is! Map || s['id'] is! int || s['on'] is! bool) continue;
      for (final d in state['seg'] as List) {
        if ((d as Map)['id'] == s['id']) d['on'] = s['on'];
      }
    }
  }

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async {
    final body = <String, dynamic>{
      if (on != null) 'on': on,
      if (brightness != null) 'bri': brightness,
    };
    setStates.add(body);
    _writes.add(body);
    _applyPower(body);
    return true;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
      m.map((k, v) => MapEntry(k, _copyAny(v)));
  static dynamic _copyAny(dynamic v) {
    if (v is Map) {
      return v.map((k, e) => MapEntry(k as String, _copyAny(e)));
    }
    if (v is List) return [for (final e in v) _copyAny(e)];
    return v;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;
  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

/// An injected clock the test moves by hand.
class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
}

// ── Fixtures ────────────────────────────────────────────────────────────────

const _threeChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 4),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 5),
];

/// `/json/state` as WLED answers it: master + one segment per channel.
Map<String, dynamic> _liveState({
  required bool master,
  required List<bool> channelsOn,
}) =>
    <String, dynamic>{
      'on': master,
      'bri': 128,
      'ps': -1,
      'seg': [
        for (var i = 0; i < channelsOn.length; i++)
          <String, dynamic>{
            'id': i,
            'start': _threeChannels[i].start,
            'stop': _threeChannels[i].stop,
            'on': channelsOn[i],
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'col': [
              [0, 0, 255, 0],
              [0, 0, 0, 0],
              [0, 0, 0, 0],
            ],
          },
      ],
    };

/// The state the OFF preset leaves behind: master off, every channel off.
Map<String, dynamic> _afterTimedOff() =>
    _liveState(master: false, channelsOn: const [false, false, false]);

const Map<String, dynamic> _everyChannelOn = {
  'on': true,
  'seg': [
    {'id': 0, 'on': true},
    {'id': 1, 'on': true},
    {'id': 2, 'on': true},
  ],
};

const Map<String, dynamic> _masterOnly = {'on': true};

// ── Rig ─────────────────────────────────────────────────────────────────────

final _refProvider = Provider<Ref>((ref) => ref);

class _Rig {
  _Rig(this.container, this.controller, this.clock);
  final ProviderContainer container;
  final _FakeController controller;
  final _Clock clock;

  WledNotifier get notifier => container.read(wledStateProvider.notifier);
  Ref get ref => container.read(_refProvider);
}

/// Builds the notifier, lets its cold-start poll land, and returns the rig.
/// The caller MUST call [_finish] at the end of the test body: the notifier's
/// poll timer has to be cancelled before testWidgets checks for pending
/// timers.
Future<_Rig> _start(
  WidgetTester tester, {
  required Map<String, dynamic>? live,
  bool offLan = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final controller = _FakeController()..live = live;
  final clock = _Clock(DateTime.utc(2026, 1, 15, 12));
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => controller),
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(
        offLan ? ConnectivityStatus.remote : ConnectivityStatus.local,
      ),
    ),
    wledNotifierClockProvider.overrideWithValue(clock.call),
    controllerDefaultsHealerProvider.overrideWithValue(
        () async => ControllerHealReport()..reachable = false),
    participatingChannelIdsProvider.overrideWithValue(null),
    userSyncStatusProvider.overrideWith((ref) => const UserSyncStatus()),
    if (offLan) ...[
      // Off-LAN the relay has no /json/cfg door, so the device census is
      // empty; the display census falls back to the denormalized ids (#91).
      deviceChannelsProvider.overrideWithValue(const <DeviceChannel>[]),
      cachedChannelIdsProvider.overrideWith((ref) async => const [0, 1, 2]),
      currentPixelMapChannelsProvider
          .overrideWith((ref) => Stream.value(const [])),
    ] else
      deviceChannelsProvider.overrideWithValue(_threeChannels),
  ]);
  container.listen(wledConnectivityStatusProvider, (_, __) {});
  container.listen(displayChannelsProvider, (_, __) {});
  // Building the notifier fires its cold-start poll.
  container.listen(wledStateProvider, (_, __) {});
  // Zero-duration pumps drain microtasks only: the cold poll lands, the
  // connectivity stream and the id census resolve, no poll TIMER fires.
  await tester.pump();
  await tester.pump();
  return _Rig(container, controller, clock);
}

/// Runs [action] to completion in fake time (the write path waits up to 3 s
/// off-LAN before its settle re-poll).
Future<void> _run(WidgetTester tester, Future<void> Function() action) async {
  var done = false;
  Object? error;
  StackTrace? trace;
  action().then<void>((_) {
    done = true;
  }, onError: (Object e, StackTrace s) {
    error = e;
    trace = s;
    done = true;
  });
  for (var i = 0; i < 10 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  expect(done, isTrue, reason: 'the write did not finish in fake time');
}

void _finish(_Rig rig) => rig.container.dispose();

/// The one power write the action produced.
Map<String, dynamic> _onlyPowerWrite(_FakeController c) {
  expect(c.powerWrites, hasLength(1), reason: 'exactly one power write');
  return c.powerWrites.single;
}

void main() {
  // ── Pure payload rule ─────────────────────────────────────────────────────

  group('buildMasterPowerOnPayload', () {
    test('every channel off → names every channel ON (= All Channels On)', () {
      final p = buildMasterPowerOnPayload(
        liveChannelPower: const {0: false, 1: false, 2: false},
        channelIds: const [2, 0, 1],
      );
      expect(p, _everyChannelOn);
      expect(p, buildAllChannelsOnPayload(const [0, 1, 2]),
          reason: 'the very payload the "All Channels On" button sends');
    });

    test('one channel on → master only', () {
      expect(
        buildMasterPowerOnPayload(
          liveChannelPower: const {0: false, 1: true, 2: false},
          channelIds: const [0, 1, 2],
        ),
        _masterOnly,
      );
    });

    test('unknown live state (null or empty) → master only', () {
      for (final live in <Map<int, bool>?>[null, const {}]) {
        expect(
          buildMasterPowerOnPayload(
              liveChannelPower: live, channelIds: const [0, 1, 2]),
          _masterOnly,
          reason: 'live = $live',
        );
      }
    });

    test('no channel census → master only (nothing to name)', () {
      expect(
        buildMasterPowerOnPayload(
          liveChannelPower: const {0: false, 1: false},
          channelIds: const [],
        ),
        _masterOnly,
      );
    });
  });

  group('channelPowerFromState', () {
    test('reads each segment\'s on flag by id', () {
      expect(
        channelPowerFromState(
            _liveState(master: false, channelsOn: const [false, true, false])),
        {0: false, 1: true, 2: false},
      );
    });

    test('a single-object seg (older firmware) is segment 0', () {
      expect(
        channelPowerFromState(<String, dynamic>{
          'on': false,
          'seg': {'on': false},
        }),
        {0: false},
      );
    });

    test('a segment without a bool on flag makes the whole read unknown', () {
      expect(
        channelPowerFromState(<String, dynamic>{
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1},
          ],
        }),
        isNull,
      );
      expect(channelPowerFromState(<String, dynamic>{'on': false}), isNull);
      expect(channelPowerFromState(<String, dynamic>{'seg': []}), isNull);
    });
  });

  // ── The real notifier ─────────────────────────────────────────────────────

  group('power circle (togglePower) on the LAN', () {
    testWidgets('after a timed OFF (every channel off) ON names every channel',
        (tester) async {
      final rig = await _start(tester, live: _afterTimedOff());
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _everyChannelOn);
      expect(channelPowerFromState(rig.controller.live!),
          {0: true, 1: true, 2: true},
          reason: 'every channel is lit on the controller');
      expect(rig.container.read(wledStateProvider).isOn, isTrue);
      _finish(rig);
    });

    testWidgets('one channel on → master only, the off channels stay off',
        (tester) async {
      final rig = await _start(tester,
          live: _liveState(master: false, channelsOn: const [false, true, false]));
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _masterOnly);
      _finish(rig);
    });

    testWidgets('unknown live state (controller never answered) → master only',
        (tester) async {
      final rig = await _start(tester, live: null);
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _masterOnly);
      _finish(rig);
    });

    testWidgets('stale live state (older than the limit) → master only',
        (tester) async {
      final rig = await _start(tester, live: _afterTimedOff());
      // No poll runs while only the injected clock moves.
      rig.clock.now = rig.clock.now
          .add(kChannelPowerSnapshotMaxAge + const Duration(seconds: 1));
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _masterOnly);
      _finish(rig);
    });

    testWidgets('a clock that runs backwards makes the read stale → master only',
        (tester) async {
      final rig = await _start(tester, live: _afterTimedOff());
      rig.clock.now = rig.clock.now.subtract(const Duration(minutes: 5));
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _masterOnly);
      _finish(rig);
    });

    testWidgets('just inside the limit the read still counts', (tester) async {
      final rig = await _start(tester, live: _afterTimedOff());
      rig.clock.now = rig.clock.now.add(kChannelPowerSnapshotMaxAge);
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _everyChannelOn);
      _finish(rig);
    });

    testWidgets(
        'a channel write the poller has not read back yet makes the read '
        'unknown → master only', (tester) async {
      final rig = await _start(tester, live: _afterTimedOff());
      // The poll said every channel is off. Then a channel chip turns
      // channel 2 on, and the power circle is tapped before any poll has
      // seen that. Trusting the old read would light channels 1 and 3 too.
      await _run(
          tester,
          () => Future.wait([
                rig.notifier.setChannelPower(1, true, isManualChange: false),
                rig.notifier.togglePower(true),
              ]));
      final writes = rig.controller.powerWrites;
      expect(writes, hasLength(2));
      expect(writes, contains(equals(_masterOnly)));
      expect(writes, isNot(contains(equals(_everyChannelOn))));
      _finish(rig);
    });

    testWidgets('turning OFF is unchanged: master only', (tester) async {
      final rig = await _start(tester,
          live: _liveState(master: true, channelsOn: const [true, true, true]));
      await _run(tester, () => rig.notifier.togglePower(false));
      expect(_onlyPowerWrite(rig.controller), {'on': false});
      _finish(rig);
    });
  });

  group('power circle off the LAN (relay)', () {
    testWidgets(
        'device census empty → the display fallback (#91) names every channel',
        (tester) async {
      final rig = await _start(tester, live: _afterTimedOff(), offLan: true);
      expect(rig.container.read(deviceChannelsProvider), isEmpty,
          reason: 'precondition: no /json/cfg census off-LAN');
      expect(
        [for (final c in rig.container.read(displayChannelsProvider).channels) c.id],
        [0, 1, 2],
        reason: 'precondition: the display census has the channels',
      );
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _everyChannelOn);
      _finish(rig);
    });

    testWidgets('off-LAN with one channel on → master only', (tester) async {
      final rig = await _start(tester,
          live: _liveState(master: false, channelsOn: const [true, false, false]),
          offLan: true);
      await _run(tester, () => rig.notifier.togglePower(true));
      expect(_onlyPowerWrite(rig.controller), _masterOnly);
      _finish(rig);
    });
  });

  group('voice control goes through the same path', () {
    // (name, live state) → each voice entry must send exactly what the power
    // circle sends for the same live state.
    final liveStates = <String, Map<String, dynamic>? Function()>{
      'every channel off': _afterTimedOff,
      'one channel on': () =>
          _liveState(master: false, channelsOn: const [false, false, true]),
      'unknown': () => null,
    };

    // Each entry returns the spoken reply when it has one (checked after the
    // write settles: expect() may not run inside a pump).
    final voiceEntries = <String, Future<String?> Function(_Rig)>{
      'dashboard "turn on"': (rig) =>
          VoiceCommandHandler(rig.ref).processCommand('turn on'),
      'deep link lumina://power/on': (rig) async {
        debugHandleDeepLinkAction(
            rig.ref, const DeepLinkAction(type: DeepLinkActionType.powerOn));
        return null;
      },
      'Siri power-on shortcut': (rig) async {
        debugHandleSiriShortcut(
            rig.ref, SiriActivityTypes.powerOn, const <String, dynamic>{});
        return null;
      },
    };

    for (final live in liveStates.entries) {
      for (final entry in voiceEntries.entries) {
        testWidgets('${entry.key} — ${live.key}: identical to the power circle',
            (tester) async {
          final circle = await _start(tester, live: live.value());
          await _run(tester, () => circle.notifier.togglePower(true));
          final expected = _onlyPowerWrite(circle.controller);
          _finish(circle);

          final voice = await _start(tester, live: live.value());
          String? reply;
          await _run(tester, () async => reply = await entry.value(voice));
          expect(_onlyPowerWrite(voice.controller), expected);
          if (entry.key.startsWith('dashboard')) {
            expect(reply, '✓ Turning on');
          }
          _finish(voice);
        });
      }
    }

    testWidgets(
        'Siri colour shortcut: its "make sure the lights are on" step is the '
        'same relighting ON', (tester) async {
      final rig = await _start(tester, live: _afterTimedOff());
      await _run(tester, () async {
        debugHandleSiriShortcut(rig.ref, SiriActivityTypes.setColor,
            const <String, dynamic>{'r': 0, 'g': 0, 'b': 255});
      });
      expect(rig.controller.powerWrites.first, _everyChannelOn,
          reason: 'the ON is the first write, before the colour');
      _finish(rig);
    });
  });
}
