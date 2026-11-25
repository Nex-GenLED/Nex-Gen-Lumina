// Build 132 follow-up, item 2 (fix 1) — Save As Custom Pattern and the Now
// Playing save keep every channel's OWN look.
//
// They used to store the first channel's effect, speed and spacing with the
// primary colour only, on every channel — the app's live state holds only the
// first segment. Now the save reads the controller's current state ONCE when
// the customer taps save (getState: direct at home, the bridge command away)
// and stores each playing channel's own colours (up to three), effect, speed,
// intensity, direction, grouping and spacing. The channels are the effective
// set the dashboard treats as playing. If the read fails, nothing is saved.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

// User is sealed; subclassing for a scoped test fake is intentional.
// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

class _RecordingDesignService implements DesignService {
  final saved = <CustomDesign>[];

  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved.add(design);
    return 'auto-${saved.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A controller whose `/json/state` is [state]; [read] replaces the answer
/// (a failure, a hang). Any other call fails the test.
class _StateRepo implements WledRepository {
  _StateRepo(this.state, {this.read});
  final Map<String, dynamic>? state;
  final Future<Map<String, dynamic>?> Function()? read;
  int reads = 0;

  @override
  Future<Map<String, dynamic>?> getState() {
    reads++;
    return read != null ? read!() : Future.value(state);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The poller's view: the FIRST segment only, as WledStateModel holds it.
class _FixedWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => const WledStateModel(
        isOn: true,
        brightness: 180,
        speed: 44,
        intensity: 90,
        color: Color(0xFFFF0022),
        connected: true,
        warmWhite: 10,
        supportsRgbw: true,
        effectId: 28,
        colorGroupSize: 2,
        spacing: 3,
      );
}

class _FixedZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [
        WledSegment(id: 0, name: 'Roof', start: 0, stop: 128),
        WledSegment(id: 1, name: 'Side', start: 128, stop: 188),
        WledSegment(id: 2, name: 'Porch', start: 188, stop: 238),
      ];
}

Map<String, dynamic> _seg(int id, String name, int start, int stop,
        {int fx = 28,
        int sx = 44,
        int ix = 90,
        bool rev = false,
        int grp = 2,
        int spc = 3,
        List<List<int>> col = const [
          [255, 0, 34, 10],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ]}) =>
    {
      'id': id,
      'n': name,
      'start': start,
      'stop': stop,
      'on': true,
      'bri': 255,
      'fx': fx,
      'sx': sx,
      'ix': ix,
      'pal': 5,
      'rev': rev,
      'grp': grp,
      'spc': spc,
      'col': col,
    };

/// Three channels showing ONE look — the case today's save already got right.
Map<String, dynamic> _oneLook() => {
      'on': true,
      'bri': 180,
      'seg': [
        _seg(0, 'Roof', 0, 128),
        _seg(1, 'Side', 128, 188),
        _seg(2, 'Porch', 188, 238),
      ],
    };

/// Three channels, three different looks.
Map<String, dynamic> _threeLooks() => {
      'on': true,
      'bri': 180,
      'seg': [
        _seg(0, 'Roof', 0, 128, grp: 1, spc: 0, col: const [
          [255, 0, 0, 0],
          [0, 0, 255, 0],
          [0, 0, 0, 0],
        ]),
        _seg(1, 'Side', 128, 188,
            fx: 17, sx: 120, ix: 200, rev: true, grp: 2, spc: 1, col: const [
              [255, 255, 255, 40],
              [0, 0, 0, 0],
              [0, 0, 0, 0],
            ]),
        _seg(2, 'Porch', 188, 238,
            fx: 42, sx: 10, ix: 255, grp: 3, spc: 0, col: const [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
              [0, 0, 255, 0],
            ]),
      ],
    };

({ProviderContainer c, _RecordingDesignService service}) _rig(
  WledRepository? repo, {
  List<int> playing = const [0, 1, 2],
}) {
  final service = _RecordingDesignService();
  final c = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser('u1'))),
    designServiceProvider.overrideWithValue(service),
    wledStateProvider.overrideWith(_FixedWledNotifier.new),
    zoneSegmentsProvider.overrideWith(_FixedZoneSegments.new),
    wledRepositoryProvider.overrideWith((ref) => repo),
    effectiveChannelIdsProvider.overrideWithValue(playing),
  ]);
  addTearDown(c.dispose);
  return (c: c, service: service);
}

Future<String?> _save(ProviderContainer c, String name) async {
  await c.read(authStateProvider.future);
  await c.read(zoneSegmentsProvider.future);
  return c.read(saveCurrentAsDesignProvider)(name);
}

Map<String, dynamic> _look(ChannelDesign ch) => {
      'colors': [for (final g in ch.colorGroups) g.color],
      'fx': ch.effectId,
      'sx': ch.speed,
      'ix': ch.intensity,
      'rev': ch.reverse,
      'grp': ch.grouping,
      'spc': ch.spacing,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one look on every channel: exactly the design and payload it saved '
      'before', () async {
    final rig = _rig(_StateRepo(_oneLook()));
    final id = await _save(rig.c, 'Evening');
    expect(id, 'auto-1');

    final d = rig.service.saved.single;
    expect(d.id, isEmpty);
    expect(d.name, 'Evening');
    expect(d.ownerId, 'u1');
    expect(d.brightness, 180);
    expect(d.brightnessStated, isTrue);
    expect(d.tags, isEmpty);
    expect(d.perPixel, isFalse);
    expect(jsonEncode([for (final ch in d.channels) ch.toJson()]),
        '[{"channel_id":0,"channel_name":"Roof","included":true,"color_groups":[{"start_led":0,"end_led":127,"color":[255,0,34,10]}],"effect_id":28,"speed":44,"intensity":90,"reverse":false,"led_count":128,"grouping":2,"spacing":3,"solid_layout":"blocks"},'
        '{"channel_id":1,"channel_name":"Side","included":true,"color_groups":[{"start_led":0,"end_led":59,"color":[255,0,34,10]}],"effect_id":28,"speed":44,"intensity":90,"reverse":false,"led_count":60,"grouping":2,"spacing":3,"solid_layout":"blocks"},'
        '{"channel_id":2,"channel_name":"Porch","included":true,"color_groups":[{"start_led":0,"end_led":49,"color":[255,0,34,10]}],"effect_id":28,"speed":44,"intensity":90,"reverse":false,"led_count":50,"grouping":2,"spacing":3,"solid_layout":"blocks"}]');
    expect(jsonEncode(d.toWledPayload()),
        '{"on":true,"bri":180,"seg":['
        '{"grp":2,"spc":3,"id":0,"col":[[255,0,34,10]],"pal":5,"fx":28,"sx":44,"ix":90},'
        '{"grp":2,"spc":3,"id":1,"col":[[255,0,34,10]],"pal":5,"fx":28,"sx":44,"ix":90},'
        '{"grp":2,"spc":3,"id":2,"col":[[255,0,34,10]],"pal":5,"fx":28,"sx":44,"ix":90}]}');
  });

  test('three channels with three different looks: three distinct looks are '
      'stored, each the channel\'s own, from ONE read', () async {
    final repo = _StateRepo(_threeLooks());
    final rig = _rig(repo);
    await _save(rig.c, 'Mixed');

    expect(repo.reads, 1);
    final d = rig.service.saved.single;
    expect([for (final ch in d.channels) ch.channelId], [0, 1, 2]);
    expect([for (final ch in d.channels) ch.channelName], ['Roof', 'Side', 'Porch']);
    final looks = [for (final ch in d.channels) _look(ch)];
    expect(looks[0], {
      'colors': [
        [255, 0, 0, 0],
        [0, 0, 255, 0],
      ],
      'fx': 28,
      'sx': 44,
      'ix': 90,
      'rev': false,
      'grp': 1,
      'spc': 0,
    });
    expect(looks[1], {
      'colors': [
        [255, 255, 255, 40],
      ],
      'fx': 17,
      'sx': 120,
      'ix': 200,
      'rev': true,
      'grp': 2,
      'spc': 1,
    });
    expect(looks[2], {
      'colors': [
        [255, 0, 0, 0],
        [0, 255, 0, 0],
        [0, 0, 255, 0],
      ],
      'fx': 42,
      'sx': 10,
      'ix': 255,
      'rev': false,
      'grp': 3,
      'spc': 0,
    });
    expect(looks.toSet().length, 3);

    // And each channel is SENT its own look.
    final segs = (d.toWledPayload()['seg'] as List).cast<Map>();
    expect([for (final s in segs) s['fx']], [28, 17, 42]);
    expect([for (final s in segs) (s['col'] as List).length], [2, 1, 3]);
  });

  test('only the channels that are playing are stored', () async {
    final rig = _rig(_StateRepo(_threeLooks()), playing: const [0, 2]);
    await _save(rig.c, 'Two of three');
    final d = rig.service.saved.single;
    expect([for (final ch in d.channels) ch.channelId], [0, 2]);
    expect([for (final ch in d.channels) ch.effectId], [28, 42]);
  });

  group('a read that fails saves NOTHING', () {
    Future<void> expectRefused(_RecordingDesignService service,
        Future<String?> Function() save) async {
      await expectLater(
        save(),
        throwsA(isA<CurrentLookNotSaved>()
            .having((e) => e.message, 'message', kCurrentLookUnreadableMessage)),
      );
      expect(service.saved, isEmpty, reason: 'never a lossy design');
    }

    test('the controller answers nothing', () async {
      final rig = _rig(_StateRepo(null));
      await expectRefused(rig.service, () => _save(rig.c, 'X'));
    });

    test('the read throws', () async {
      final rig = _rig(_StateRepo(null,
          read: () => Future.error(StateError('relay down'))));
      await expectRefused(rig.service, () => _save(rig.c, 'X'));
    });

    test('a playing channel is missing from the answer', () async {
      final state = _threeLooks();
      (state['seg'] as List).removeAt(1);
      final rig = _rig(_StateRepo(state));
      await expectRefused(rig.service, () => _save(rig.c, 'X'));
    });

    test('no controller to read', () async {
      final rig = _rig(null);
      await expectRefused(rig.service, () => _save(rig.c, 'X'));
    });

    testWidgets('the read never answers: it times out', (tester) async {
      final rig = _rig(_StateRepo(null,
          read: () => Completer<Map<String, dynamic>?>().future));
      Object? error;
      unawaited(_save(rig.c, 'X').then((_) {}, onError: (Object e) => error = e));
      await tester.pump(kSaveCurrentLookReadTimeout + const Duration(seconds: 1));
      expect(error, isA<CurrentLookNotSaved>());
      expect((error as CurrentLookNotSaved).message, kCurrentLookUnreadableMessage);
      expect(rig.service.saved, isEmpty);
    });
  });

  test('what the dashboard shows when a save fails', () {
    expect(
        saveCurrentAsDesignFailureMessage(
            const CurrentLookNotSaved(kCurrentLookUnreadableMessage), 'X'),
        kCurrentLookUnreadableMessage);
    expect(saveCurrentAsDesignFailureMessage(StateError('boom'), 'X'),
        'Failed to save "X": Bad state: boom',
        reason: 'any other failure reads as it always did');
  });
}
