// LIVE HARDWARE TEST — requires the bench controller at kBenchIp (2 channels:
// 0–128 and 128–290). NOT part of the normal suite: it performs real network
// I/O and changes what the lights show (never presets, never /json/cfg), then
// puts the look back. Without the define every test skips.
//
// A STATIC (per-pixel) FAVORITE, end to end: paint → heart → back out → apply
// from My Favorites — against real hardware, with the favorite crossing a REAL
// Firestore leg in the middle. Two phases, because that leg is made by a
// separate client-credential script (the rule must be the one a phone is
// subject to, not one a test process can bypass):
//
//   1. EXPORT — light the bench exactly as the editor does, record the frame
//      buffer, build the document the heart writes (the REAL writer), write it
//      out as a Firestore REST document:
//        flutter test test/hardware/static_favorite_live_test.dart \
//          --dart-define=RUN_HW=true --dart-define=FAV_RT_DIR=<dir> \
//          --dart-define=FAV_RT_PHASE=export
//      (`FAV_RT_PHASE=doc` writes ONLY the documents and needs no hardware and
//      no RUN_HW — the live-rule leg can be verified away from the bench;
//      `FAV_RT_PHASE=parse` then checks what Firestore returned, again with no
//      hardware: the grid's model, the spine, the real transport's chunker.)
//   2. (outside) create that document under a throwaway user WITH THAT USER'S
//      ID TOKEN, read it back through the My Favorites grid's own query, save
//      the result to <dir>/from_firestore_static_fav.json.
//   3. IMPORT — parse it with the grid's own model, scramble the lights ("back
//      out"), apply it the way My Favorites does, compare the frame buffer to
//      phase 1's:
//          … --dart-define=FAV_RT_PHASE=import
//
// Numbering continues the audits' bench logs (T1–T26).

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);
const String kDir = String.fromEnvironment('FAV_RT_DIR');
const String kPhase = String.fromEnvironment('FAV_RT_PHASE');

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

/// The NFL Chiefs Explore card, customised in the editor: a third colour and a
/// dimmer brightness, MODE = Static. 290 LEDs, no two neighbours alike — the
/// worst case for size (nothing range-compresses).
EditablePattern _chiefsStatic() => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [_red, _gold],
      effectId: 0,
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

int _differing(List<List<int>> a, List<List<int>> b) => [
      for (int i = 0; i < 290; i++)
        if (a[i].join(',') != b[i].join(',')) i,
    ].length;

// ── Firestore REST <-> Dart map (the wire form a phone's write takes) ───────

Map<String, dynamic> _toRest(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  throw ArgumentError('not Firestore-encodable here: ${v.runtimeType}');
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
  throw ArgumentError('unexpected Firestore value in a favorite: $v');
}

/// A writer's document → `{fields, field_values}`: the plain fields REST-
/// encoded, and the names of the FieldValue sentinels (sent as transforms).
Map<String, dynamic> _export(Map<String, dynamic> data) => {
      'fields': {
        for (final e in data.entries)
          if (e.value is! FieldValue) e.key: _toRest(e.value),
      },
      'field_values': [
        for (final e in data.entries)
          if (e.value is FieldValue) e.key,
      ],
    };

File _file(String name) => File('$kDir/$name');

/// What the heart's `_favoritePayload` + `writeFavorite` build — the REAL
/// writers, exported as the SDK would send them. Pure: no hardware.
void _exportFavoriteDocs() {
  final p = _chiefsStatic();
  final design = customDesignFromEditablePattern(
      pattern: p, name: p.name, ownerId: '', channels: _editorChannels);
  final payload = buildPerPixelFavoritePayload(design);
  final create = buildFavoriteCreateData(patternName: p.name, payload: payload);
  final refresh = buildFavoriteRefreshData(payload: payload);
  final usage = buildFavoriteUsageData();
  _file('fav_static_create.json').writeAsStringSync(jsonEncode(_export(create)));
  _file('fav_static_refresh.json').writeAsStringSync(jsonEncode(_export(refresh)));
  _file('fav_static_usage.json').writeAsStringSync(jsonEncode(_export(usage)));
  // The same card hearted while it was ANIMATED — so the probe can re-heart it
  // as Static, which is an UPDATE of the same document, not a create.
  _file('fav_animated_create.json').writeAsStringSync(jsonEncode(_export(
      buildFavoriteCreateData(
          patternName: p.name,
          payload: p.copyWith(effectId: 15).toWledPayload(290)))));

  final embedded = perPixelDesignOfFavorite(payload)!;
  // ignore: avoid_print
  print('favorite doc: pattern_data = ${(create[kFavoritePatternData] as String).length} B; '
      'embedded design per_pixel=${embedded.perPixel} '
      'channels=${embedded.channels.map((c) => '${c.channelId}:${c.ledCount}').toList()} '
      'groups=${embedded.channels.map((c) => c.colorGroups.length).toList()} '
      'bri=${embedded.brightness}');
}

/// READ, as the My Favorites grid does: UserService.streamFavorites hands each
/// doc's data + id to FavoritePattern.fromJson.
FavoritePattern _favoriteFromFirestore() {
  final doc = jsonDecode(_file('from_firestore_static_fav.json').readAsStringSync())
      as Map<String, dynamic>;
  return FavoritePattern.fromJson({
    for (final e in (doc['fields'] as Map).entries) '${e.key}': _fromRest(e.value as Map),
    'id': (doc['name'] as String).split('/').last,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;
  final run = kRunHw && kDir.isNotEmpty && (kPhase == 'export' || kPhase == 'import');

  // Every request the REAL transport makes, off its own log line.
  final wire = <String>[];
  final originalDebugPrint = debugPrint;

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test stubs HTTP with a 400
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!run) return;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains('WLED POST /json/state')) {
        wire.add(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    debugPrint = originalDebugPrint;
    if (!run) return;
    // Put the look back: the captured segments, then the preset it came from
    // (which also restores the `ps` pointer). Presets/cfg were never written.
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
  });

  /// A deliberately different look, so "applied correctly" cannot be the
  /// previous step still showing — the user backing out and doing something
  /// else before coming back to My Favorites.
  Future<void> scramble() async {
    final r = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: const [0, 0, 40, 0],
        spansByChannel: const {
          0: [PixelSpan(start: 0, end: 9, color: [0, 255, 0, 0])],
        });
    expect(r, SpineWriteResult.ok);
  }

  // ── DOC ONLY (no hardware) ───────────────────────────────────────────────

  test('doc — the document the heart writes for a 290-LED Static favorite',
      _exportFavoriteDocs,
      skip: !(kDir.isNotEmpty && kPhase == 'doc'));

  test('parse — what Firestore RETURNED parses with the My Favorites model and '
      'rebuilds the picture through the real transport chunker (no hardware)',
      () async {
    final favorite = _favoriteFromFirestore();
    expect(favorite.patternName, 'Kansas City Chiefs');
    final design = perPixelDesignOfFavorite(favorite.patternData);
    expect(design, isNotNull);

    // The production WledService with its mock host: records each per-pixel
    // request body instead of posting it. NOT a controller.
    final mock = WledService('http://mock');
    final outcome =
        await applyFavoritePayloadWith(_container(mock).read, favorite.patternData);
    expect(outcome.status, FavoriteApplyStatus.applied);

    final buffer = <int, Map<int, String>>{0: {}, 1: {}};
    final sizes = <int>[];
    for (final body in mock.lastSimulatedPerPixelChunks) {
      sizes.add(utf8.encode(jsonEncode(body)).length);
      final seg = (body['seg'] as List).single as Map;
      final i = seg['i'] as List;
      int k = 0;
      while (k < i.length) {
        final start = i[k] as int;
        if (i[k + 1] is int) {
          for (int x = start; x < (i[k + 1] as int); x++) {
            buffer[seg['id']]![x] = (i[k + 2] as List).join(',');
          }
          k += 3;
        } else {
          buffer[seg['id']]![start] = (i[k + 1] as List).join(',');
          k += 2;
        }
      }
    }
    final want = _chiefsStatic().staticColorsRgbw();
    var wrong = 0;
    for (final c in _editorChannels) {
      expect(buffer[c.id]!.length, c.ledCount);
      for (int led = 0; led < c.ledCount; led++) {
        if (buffer[c.id]![led] != want[led % want.length].join(',')) wrong++;
      }
    }
    // ignore: avoid_print
    print('parse: favorite "${favorite.patternName}" (id ${favorite.id}) -> '
        '${mock.lastSimulatedPerPixelChunks.length} per-pixel requests of $sizes B; '
        '$wrong/290 LEDs differ from the picture the editor painted; '
        'bri=${design!.brightness}');
    expect(wrong, 0);
  }, skip: !(kDir.isNotEmpty && kPhase == 'parse'));

  // ── PHASE 1 ──────────────────────────────────────────────────────────────

  test('T27 export — what My Favorites USED to do with a Static favorite is '
      'refused before it is posted; so is the new payload sent raw', () async {
    final before = await _frame();

    // (a) the payload the heart would have stored before this change, sent the
    //     way the grid sent every favorite: channel filter + ONE applyJson.
    final legacy = applyChannelFilter(
        _chiefsStatic().toWledPayload(290), const [0, 1], _channels);
    final okLegacy = await svc.applyJson(legacy);

    // (b) the NEW stored payload, sent raw by a consumer that does not know
    //     about `lumina_design` — it must fail loudly, not light something else.
    final stored = buildPerPixelFavoritePayload(customDesignFromEditablePattern(
        pattern: _chiefsStatic(),
        name: 'Kansas City Chiefs',
        ownerId: '',
        channels: _editorChannels));
    final okRaw = await svc.applyJson(stored);

    final after = await _frame();
    // ignore: avoid_print
    print('T27 old single-message apply: ${utf8.encode(jsonEncode(legacy)).length} B '
        '-> applyJson=$okLegacy; new payload sent raw: '
        '${utf8.encode(jsonEncode(stored)).length} B -> applyJson=$okRaw; '
        'frame changed=${_differing(before, after)}/290 '
        '(ceiling $kMaxApplyPayloadBytes B)');
    expect(okLegacy, isFalse);
    expect(okRaw, isFalse);
    expect(_differing(before, after), 0, reason: 'nothing reached the lights');
  }, skip: !(run && kPhase == 'export'));

  test('T28 export — paint Static in the editor, then heart it: the live look, '
      'and the document the heart writes', () async {
    final p = _chiefsStatic();
    final design = customDesignFromEditablePattern(
        pattern: p, name: p.name, ownerId: '', channels: _editorChannels);

    // What the editor's `_sendStatic` does.
    final r = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: const [0, 0, 0, 0],
        spansByChannel: customDesignToSpans(design),
        brightness: p.brightness);
    expect(r, SpineWriteResult.ok);
    final live = await _frame();
    _file('live_static.json').writeAsStringSync(jsonEncode(live));

    final lit = [for (final l in live) if (l[0] + l[1] + l[2] > 60) 1].length;
    final distinctNeighbours = [
      for (int i = 1; i < 290; i++)
        if (i != 128 && live[i].join(',') != live[i - 1].join(',')) 1,
    ].length;
    // ignore: avoid_print
    print('T28 live Static: $lit/290 lit; $distinctNeighbours/288 neighbour '
        'pairs differ (nothing range-compresses); LEDs 0-5 = ${live.sublist(0, 6)}; '
        'LEDs 128-133 = ${live.sublist(128, 134)}');
    expect(lit, 290, reason: 'every LED of both channels carries a colour');

    _exportFavoriteDocs();
  }, skip: !(run && kPhase == 'export'));

  // ── PHASE 3 ──────────────────────────────────────────────────────────────

  test('T29 import — back out, then apply the favorite from My Favorites: the '
      'SAME frame buffer, through the chunked spine', () async {
    final favorite = _favoriteFromFirestore();
    // ignore: avoid_print
    print('T29 favorite from Firestore: id=${favorite.id} name="${favorite.patternName}" '
        '(${_file('from_firestore_static_fav.json').lengthSync()} B on the wire)');
    expect(favorite.patternName, 'Kansas City Chiefs');
    expect(perPixelDesignOfFavorite(favorite.patternData), isNotNull);

    // BACK OUT: something else on the lights, brightness knocked off 180.
    await scramble();
    expect(await svc.applyJson({'bri': 90}), isTrue);
    final scrambled = await _frame();

    // APPLY, as the dashboard's My Favorites tap does.
    wire.clear();
    final outcome =
        await applyFavoritePayloadWith(_container(svc).read, favorite.patternData);
    final requests = List<String>.of(wire);
    expect(outcome.status, FavoriteApplyStatus.applied);
    expect(outcome.perPixel, isTrue);
    final got = await _frame();

    final live = [
      for (final l in jsonDecode(_file('live_static.json').readAsStringSync()) as List)
        (l as List).cast<int>(),
    ];
    final vsLive = _differing(got, live);
    final vsScramble = _differing(got, scrambled);
    // ignore: avoid_print
    print('T29 applied frame vs the editor\'s live frame: $vsLive/290 differ; vs '
        'the scramble it replaced: $vsScramble/290 differ. '
        'LEDs 0-5 = ${got.sublist(0, 6)}; LEDs 128-133 = ${got.sublist(128, 134)}');
    // ignore: avoid_print
    print('T29 wire: ${requests.length} requests —\n  ${requests.join('\n  ')}');
    expect(vsLive, 0);
    expect(vsScramble, greaterThan(250));

    // Chunking engaged: a base write plus one paint request per channel, each
    // under the device's JSON buffer — not one message.
    final paints = requests.where((r) => r.contains('per-pixel chunk')).toList();
    expect(paints.length, greaterThanOrEqualTo(2));
    expect(requests.length, greaterThanOrEqualTo(3));
    for (final p in paints) {
      final bytes = int.parse(RegExp(r'(\d+)B\)').firstMatch(p)!.group(1)!);
      expect(bytes, lessThan(6000));
    }

    // The live-view frame is pre-brightness, so brightness is read from state.
    final state = (await svc.getState())!;
    // ignore: avoid_print
    print('T29 device bri=${state['bri']} (favorite stores 180; was 90 before the apply)');
    expect(state['bri'], 180);
  }, skip: !(run && kPhase == 'import'));
}
