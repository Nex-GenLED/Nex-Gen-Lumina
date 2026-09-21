// LIVE HARDWARE TEST — requires the bench controller at kBenchIp (2 channels:
// 0–128 and 128–290). NOT part of the normal suite: it performs real network
// I/O and changes what the lights show (never presets, never /json/cfg), then
// puts the look back. Without the define every test skips.
//
// The Pattern Editor's "Save" round trip — save → reopen → apply — for BOTH
// shapes it produces, against real hardware, with the design crossing a REAL
// Firestore leg in the middle. It runs in two phases because the Firestore leg
// is made by a separate client-credential script (the rules must be the ones a
// phone is subject to, not the ones a test process can bypass):
//
//   1. EXPORT — light the bench exactly as the editor does, record the frame
//      buffer, build the design Save would store, write it out as Firestore
//      REST documents:
//        flutter test test/hardware/save_to_my_designs_live_test.dart \
//          --dart-define=RUN_HW=true --dart-define=SAVE_RT_DIR=<dir> \
//          --dart-define=SAVE_RT_PHASE=export
//   2. (outside) create those documents under a throwaway user WITH THAT USER'S
//      ID TOKEN, read them back through My Designs' own query, save the result
//      to <dir>/from_firestore_*.json.
//   3. IMPORT — rebuild each design from what Firestore returned, reopen it the
//      way its editor does, apply it the way My Designs does, and compare the
//      frame buffer to phase 1's:
//          … --dart-define=SAVE_RT_PHASE=import
//
// Numbering continues the audits' bench logs (T1–T22).

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);
const String kDir = String.fromEnvironment('SAVE_RT_DIR');
const String kPhase = String.fromEnvironment('SAVE_RT_PHASE');

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];
const _editorChannels = [
  PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
  PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
];

const _red = Color(0xFFE31837);
const _gold = Color(0xFFFFB81C);
const _white = Color(0xFFFFFFFF);

/// The NFL Chiefs Explore card as the tuner hands it to the editor, then the
/// user's customisation: a third colour and a dimmer brightness.
EditablePattern _chiefs(int fx) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [_red, _gold],
      effectId: fx,
      speed: 140,
      intensity: 128,
    ).copyWith(actionColors: const [_red, _gold, _white], brightness: 180);

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository repo) => ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);

Future<List<List<List<int>>>> _frames(Duration duration) async {
  final ws = await WebSocket.connect('ws://$kBenchIp/ws');
  final frames = <List<List<int>>>[];
  final sub = ws.listen((msg) {
    if (msg is! List<int> || msg.isEmpty || msg[0] != 76 /* 'L' */) return;
    final off = msg[1] == 2 ? 4 : 2;
    frames.add([
      for (int i = off; i + 2 < msg.length; i += 3) [msg[i], msg[i + 1], msg[i + 2]],
    ]);
  });
  ws.add(jsonEncode({'lv': true}));
  await Future<void>.delayed(duration);
  ws.add(jsonEncode({'lv': false}));
  await sub.cancel();
  await ws.close();
  return frames;
}

Future<List<List<int>>> _frame() async {
  await Future<void>.delayed(const Duration(milliseconds: 1300)); // 700 ms crossfade
  return (await _frames(const Duration(milliseconds: 900))).last;
}

/// The colours a run of frames ever showed, coarsened so a fade between two
/// colours does not count as a new one.
Set<String> _palette(List<List<List<int>>> frames) => {
      for (final f in frames)
        for (final l in f)
          if (l[0] + l[1] + l[2] > 60) '${l[0] ~/ 64}.${l[1] ~/ 64}.${l[2] ~/ 64}',
    };

/// The segment fields a design owns, as the DEVICE reports them.
List<Map<String, dynamic>> _deviceLook(Map<String, dynamic> state) => [
      for (final s in (state['seg'] as List).cast<Map>())
        {
          for (final k in ['id', 'on', 'fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col', 'frz'])
            k: s[k],
        },
    ];

// ── Firestore REST <-> Dart map (the wire form a phone's write takes) ───────

Map<String, dynamic> _toRest(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is Timestamp) return {'timestampValue': v.toDate().toUtc().toIso8601String()};
  if (v is List) return {'arrayValue': {'values': [for (final x in v) _toRest(x)]}};
  if (v is Map) {
    return {'mapValue': {'fields': {for (final e in v.entries) '${e.key}': _toRest(e.value)}}};
  }
  throw ArgumentError('not Firestore-encodable: ${v.runtimeType}');
}

dynamic _fromRest(Map v) {
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
  if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('stringValue')) return v['stringValue'] as String;
  if (v.containsKey('timestampValue')) {
    return Timestamp.fromDate(DateTime.parse(v['timestampValue'] as String));
  }
  if (v.containsKey('arrayValue')) {
    return [for (final x in ((v['arrayValue'] as Map)['values'] as List? ?? const [])) _fromRest(x as Map)];
  }
  if (v.containsKey('mapValue')) {
    final f = ((v['mapValue'] as Map)['fields'] as Map?) ?? const {};
    return <String, dynamic>{for (final e in f.entries) '${e.key}': _fromRest(e.value as Map)};
  }
  throw ArgumentError('unknown Firestore value: $v');
}

File _file(String name) => File('$kDir/$name');

CustomDesign _designFromFirestore(String name) {
  final doc = jsonDecode(_file(name).readAsStringSync()) as Map<String, dynamic>;
  final id = (doc['name'] as String).split('/').last;
  final data = <String, dynamic>{
    for (final e in (doc['fields'] as Map).entries) '${e.key}': _fromRest(e.value as Map),
  };
  // ignore: avoid_print
  print('  reopened Firestore doc id=$id (${_file(name).lengthSync()} B on the wire)');
  return CustomDesign.fromFirestoreData(id, data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;
  final run = kRunHw && kDir.isNotEmpty && (kPhase == 'export' || kPhase == 'import');

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test stubs HTTP with a 400
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!run) return;
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    if (!run) return;
    // Put the look back: the captured segments, then the preset it came from
    // (which also restores the `ps` pointer). Presets/cfg were never written.
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
  });

  /// What the editor's `_sendToWled` does. Static: the chunked per-pixel
  /// spine, built from the SAME design Save stores, brightness in the base
  /// write. Animated: one channel-filtered applyJson.
  Future<void> applyAsEditor(EditablePattern p) async {
    if (p.effectId == 0) {
      final design = customDesignFromEditablePattern(
          pattern: p, name: p.name, ownerId: '', channels: _editorChannels);
      final r = await applyBaseAndSpansWith(_container(svc).read,
          baseRgbw: const [0, 0, 0, 0],
          spansByChannel: customDesignToSpans(design),
          brightness: p.brightness);
      expect(r, SpineWriteResult.ok);
      return;
    }
    final total = await svc.getTotalLedCount() ?? 150;
    final payload = applyChannelFilter(p.toWledPayload(total), const [0, 1], _channels);
    expect(await svc.applyJson(payload), isTrue);
  }

  /// A deliberately different look in between, so "applied correctly" cannot
  /// be the previous step still showing. Goes through the per-pixel spine,
  /// which leaves the segments FROZEN with `pal:0` — the worst state an effect
  /// design can be applied over.
  Future<void> scramble() async {
    final r = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: const [0, 0, 40, 0],
        spansByChannel: const {
          0: [PixelSpan(start: 0, end: 9, color: [0, 255, 0, 0])],
        });
    expect(r, SpineWriteResult.ok);
  }

  // ── PHASE 1 ──────────────────────────────────────────────────────────────

  test('T22 export — the OLD Static live write of the editor is refused before it '
      'is ever posted (why Static now goes through the spine)', () async {
    final legacy = _chiefs(0).toWledPayload(290);
    final one = applyChannelFilter(legacy, const [0], _channels);
    final two = applyChannelFilter(legacy, const [0, 1], _channels);
    final before = await _frame();
    final okOne = await svc.applyJson(one);
    final okTwo = await svc.applyJson(two);
    final after = await _frame();
    // ignore: avoid_print
    print('T22 legacy Static payload: 1 channel = ${utf8.encode(jsonEncode(one)).length} B '
        '-> applyJson=$okOne; 2 channels = ${utf8.encode(jsonEncode(two)).length} B '
        '-> applyJson=$okTwo; frame changed=${before.toString() != after.toString()}');
    expect(okOne, isFalse);
    expect(okTwo, isFalse);
    expect(after.toString(), before.toString(), reason: 'nothing reached the lights');
  }, skip: !(run && kPhase == 'export'));


  test('T23 export — Static: the editor\'s live look, and the design Save stores',
      () async {
    final p = _chiefs(0);
    await applyAsEditor(p);
    final live = await _frame();
    _file('live_static.json').writeAsStringSync(jsonEncode(live));

    final lit = [for (final l in live) if (l[0] + l[1] + l[2] > 60) 1].length;
    // ignore: avoid_print
    print('T23 live Static: $lit/290 lit; LEDs 0-5 = ${live.sublist(0, 6)}; '
        'LEDs 128-133 = ${live.sublist(128, 134)}');
    expect(lit, 290, reason: 'every LED of both channels carries a colour');

    final design = customDesignFromEditablePattern(
        pattern: p, name: 'zz probe Chiefs Static', ownerId: 'PROBE', channels: _editorChannels);
    final data = UserService.sanitizeForFirestore(design.toFirestore());
    _file('to_firestore_static.json').writeAsStringSync(jsonEncode({
      'fields': {for (final e in data.entries) e.key: _toRest(e.value)},
    }));
    // ignore: avoid_print
    print('T23 design: per_pixel=${design.perPixel} channels=${design.channels.length} '
        'groups=${design.channels.map((c) => c.colorGroups.length).toList()}');
  }, skip: !(run && kPhase == 'export'));

  test('T24 export — Animated: the editor\'s live look, and the design Save stores',
      () async {
    final p = _chiefs(15); // Running — draws col[0]/col[1]; palette-sensitive
    await applyAsEditor(p);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final frames = await _frames(const Duration(seconds: 4));
    final look = _deviceLook((await svc.getState())!);
    _file('live_animated.json').writeAsStringSync(jsonEncode({
      'look': look,
      'bri': (await svc.getState())!['bri'],
      'palette': _palette(frames).toList()..sort(),
      'changing': frames.first.toString() != frames.last.toString(),
    }));
    // ignore: avoid_print
    print('T24 live Animated: ${frames.length} frames; palette=${_palette(frames)}; look=$look');

    final design = customDesignFromEditablePattern(
        pattern: p, name: 'zz probe Chiefs Animated', ownerId: 'PROBE', channels: _editorChannels);
    final data = UserService.sanitizeForFirestore(design.toFirestore());
    _file('to_firestore_animated.json').writeAsStringSync(jsonEncode({
      'fields': {for (final e in data.entries) e.key: _toRest(e.value)},
    }));
  }, skip: !(run && kPhase == 'export'));

  // ── PHASE 3 ──────────────────────────────────────────────────────────────

  test('T25 import — Static: reopens LED-for-LED and applies through My '
      'Designs\' spine to the SAME frame buffer', () async {
    final design = _designFromFirestore('from_firestore_static.json');
    expect(designKindOf(design), DesignKind.perPixel,
        reason: 'My Designs → Edit opens the paint editor');

    // REOPEN, as ManualDesignEditor does.
    final p = _chiefs(0);
    final want = p.staticColorsRgbw();
    final doc = PixelDesignDocument.fromLedColorGroups(
      baseColor: const [10, 10, 12, 0],
      channelLengths: const {0: 128, 1: 162},
      groupsByChannel: {for (final c in design.channels) c.channelId: c.colorGroups},
    );
    var wrong = 0;
    for (final c in _editorChannels) {
      for (int i = 0; i < c.ledCount; i++) {
        if (doc.colorAt(c.id, i).join(',') != want[i % want.length].join(',')) wrong++;
      }
    }
    expect(wrong, 0, reason: 'pixels differing after the Firestore round trip');

    // APPLY, as applySavedDesign does for a positional design.
    await scramble();
    final scrambled = await _frame();
    final result = await applyPositionalDesignWith(_container(svc).read, design);
    expect(result, DesignApplyResult.applied);
    final got = await _frame();

    final live = [
      for (final l in jsonDecode(_file('live_static.json').readAsStringSync()) as List)
        (l as List).cast<int>(),
    ];
    final differing = [
      for (int i = 0; i < 290; i++)
        if (got[i].join(',') != live[i].join(',')) i,
    ];
    final vsScramble = [
      for (int i = 0; i < 290; i++)
        if (got[i].join(',') != scrambled[i].join(',')) i,
    ].length;
    // ignore: avoid_print
    print('T25 Static: reopened 290/290 pixels exact; applied frame vs the '
        'editor\'s live frame: ${differing.length}/290 differ; vs the scramble it '
        'replaced: $vsScramble/290 differ. LEDs 0-5 = ${got.sublist(0, 6)}');
    expect(differing, isEmpty);
    expect(vsScramble, greaterThan(250));

    // The live-view frame is pre-brightness, so brightness is read from state.
    // The bench starts this phase at bri 128 and the scramble does not touch
    // it: 180 here can only have come from the saved design.
    final state = (await svc.getState())!;
    // ignore: avoid_print
    print('T25 Static: device bri=${state['bri']} (design stores ${design.brightness}; '
        'was ${prior?['bri']} before the apply)');
    expect(design.statesBrightness, isTrue);
    expect(state['bri'], 180);
  }, skip: !(run && kPhase == 'import'));

  test('T26 import — Animated: reopens in the tuner and applies to the SAME '
      'device look, over a frozen pal:0 state', () async {
    final design = _designFromFirestore('from_firestore_animated.json');
    expect(designKindOf(design), DesignKind.effect,
        reason: 'My Designs → Edit opens the colourway tuner');

    // REOPEN, as design_detail_screen does.
    final tuner = ColorwayEffectSelectorPage.forDesign(design: design);
    expect(tuner.paletteNode.themeColors, const [_red, _gold, _white]);
    final ch = design.channels.first;
    expect([ch.effectId, ch.speed, ch.intensity, design.brightness], [15, 140, 128, 180]);

    // APPLY, as applySavedDesign does for an effect design.
    await scramble();
    final payload = applyChannelFilter(design.toWledPayload(), const [0, 1], _channels);
    expect(await svc.applyJson(payload), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final frames = await _frames(const Duration(seconds: 4));
    final state = (await svc.getState())!;

    final live = jsonDecode(_file('live_animated.json').readAsStringSync()) as Map;
    final look = _deviceLook(state);
    // ignore: avoid_print
    print('T26 Animated: ${frames.length} frames; palette=${_palette(frames)}\n'
        '  device look now : $look\n  device look live: ${live['look']}');
    expect(jsonEncode(look), jsonEncode(live['look']),
        reason: 'fx/sx/ix/pal/grp/spc/col/frz as the device reports them');
    expect(state['bri'], live['bri']);
    expect((_palette(frames).toList()..sort()), live['palette']);
    expect(frames.first.toString() != frames.last.toString(), live['changing']);
  }, skip: !(run && kPhase == 'import'));
}
