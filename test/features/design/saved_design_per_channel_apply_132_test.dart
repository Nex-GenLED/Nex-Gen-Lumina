// Build 132 — a saved effect design's own Apply sends each stored channel its
// own look.
//
// My Designs' Apply (applySavedDesign) and a favourite tapped on Home both
// went through applyChannelFilter, which copies the FIRST design segment's
// look onto every targeted channel. Since build 132 a Now Playing / Save As
// Custom Pattern save stores each channel's own look, so a mixed design came
// back as one look. Those two doors now send each stored channel its own
// look; a playing channel the design does not store keeps today's behaviour
// (the first look), and a channel that is not playing is still switched off.
//
// Everything that is not mixed — every design saved before build 132, a
// single-channel design, a one-look design, every favourite shape — sends
// exactly what it sent at b716a325 (captured there, compared as jsonEncode
// strings, so key order is pinned too).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/apply_saved_design.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

const _threeChannels = [
  DeviceChannel(id: 0, name: 'Roof', start: 0, stop: 30, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Side', start: 30, stop: 60, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Porch', start: 60, stop: 90, gpioPin: 15),
];

final _t = DateTime(2026, 11, 25);

ChannelDesign _ch(
  int id, {
  List<List<int>> colors = const [
    [255, 0, 34, 0]
  ],
  int fx = 28,
  int sx = 44,
  int ix = 90,
  int grp = 2,
  int spc = 3,
  bool span = true,
  bool included = true,
  SolidLayout layout = SolidLayout.blocks,
  int ledCount = 30,
}) =>
    ChannelDesign(
      channelId: id,
      channelName: 'Channel ${id + 1}',
      included: included,
      colorGroups: span && colors.length == 1
          ? [LedColorGroup(startLed: 0, endLed: ledCount - 1, color: colors.first)]
          : [
              for (var i = 0; i < colors.length; i++)
                LedColorGroup(startLed: i, endLed: i, color: colors[i]),
            ],
      effectId: fx,
      speed: sx,
      intensity: ix,
      grouping: grp,
      spacing: spc,
      ledCount: ledCount,
      solidLayout: layout,
    );

CustomDesign _design(List<ChannelDesign> channels,
        {List<String> tags = const [], bool? stated = true, int bri = 150}) =>
    CustomDesign(
      id: 'd1',
      name: 'Saved',
      createdAt: _t,
      updatedAt: _t,
      ownerId: 'u',
      channels: channels,
      brightness: bri,
      brightnessStated: stated,
      tags: tags,
    );

/// Three channels, three looks — what a build-132 Now Playing save stores.
CustomDesign _mixed() => _design([
      _ch(0, colors: const [
        [255, 0, 0, 0],
        [0, 0, 255, 0]
      ], span: false, grp: 1, spc: 0),
      _ch(1, colors: const [
        [255, 255, 255, 40]
      ], fx: 17, sx: 120, ix: 200, grp: 2, spc: 1),
      _ch(2, colors: const [
        [255, 0, 0, 0],
        [0, 255, 0, 0],
        [0, 0, 255, 0]
      ], span: false, fx: 42, sx: 10, ix: 255, grp: 3, spc: 0),
    ]);

Future<Map<String, dynamic>> _applyFromMyDesigns(
  WidgetTester tester,
  CustomDesign design, {
  List<DeviceChannel> channels = _threeChannels,
  List<int>? playing,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = RecordingWledRepository();
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    userSyncStatusProvider.overrideWith((ref) => const UserSyncStatus()),
    deviceChannelsProvider.overrideWithValue(channels),
    effectiveChannelIdsProvider
        .overrideWithValue(playing ?? [for (final ch in channels) ch.id]),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (ctx, ref, _) {
          return ElevatedButton(
            onPressed: () => applySavedDesign(ctx, ref, design),
            child: const Text('Apply'),
          );
        }),
      ),
    ),
  ));
  await tester.tap(find.text('Apply'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(repo.applied, hasLength(1), reason: 'one Apply, one write');
  final sent = repo.applied.single;
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
  return sent;
}

Future<Map<String, dynamic>> _tapFavoriteOnHome(
    WidgetTester tester, Map<String, dynamic> patternData) async {
  final fav = FavoritePattern(
    id: 'f1',
    patternName: 'Saved Look',
    addedAt: DateTime(2026, 11, 1),
    usageCount: 0,
    patternData: patternData,
    autoAdded: false,
  );
  final h = await pumpHomeDashboard(tester, favorites: [fav]);
  // The tile, not Now Playing (which may show the same name) and not the
  // reserved white tiles (which share the key).
  await tester.tap(find.byWidgetPredicate((w) =>
      w is Text &&
      w.key == const ValueKey('favorite-tile-name') &&
      w.data == 'Saved Look'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(h.repo.applied, hasLength(1), reason: 'one tap, one write');
  final sent = h.repo.applied.single;
  await unmountHome(tester);
  return sent;
}

Map<int, Map> _byId(Map<String, dynamic> payload) => {
      for (final s in (payload['seg'] as List).cast<Map>()) s['id'] as int: s,
    };

void main() {
  group('My Designs Apply', () {
    testWidgets('a mixed design applies per channel on the wire',
        (tester) async {
      final segs = _byId(await _applyFromMyDesigns(tester, _mixed()));
      expect(segs.keys, [0, 1, 2]);
      expect([for (final s in segs.values) s['fx']], [28, 17, 42]);
      expect(segs[0]!['col'], [
        [255, 0, 0, 0],
        [0, 0, 255, 0]
      ]);
      expect(segs[1]!['col'], [
        [255, 255, 255, 40]
      ]);
      expect(segs[2]!['col'], [
        [255, 0, 0, 0],
        [0, 255, 0, 0],
        [0, 0, 255, 0]
      ]);
      expect([for (final s in segs.values) s['sx']], [44, 120, 10]);
      expect([for (final s in segs.values) s['ix']], [90, 200, 255]);
      expect([for (final s in segs.values) s['grp']], [1, 2, 3]);
      expect([for (final s in segs.values) s['spc']], [0, 1, 0]);
      expect([for (final s in segs.values) s['on']], [true, true, true]);
    });

    testWidgets('a playing channel the design does not store keeps today\'s '
        'look (the first one); a channel not playing is switched off',
        (tester) async {
      final design = _design([
        _ch(0),
        _ch(1, fx: 17, sx: 120, ix: 200),
      ]);
      const four = [
        ..._threeChannels,
        DeviceChannel(id: 3, name: 'Garage', start: 90, stop: 120, gpioPin: 16),
      ];
      final segs = _byId(await _applyFromMyDesigns(tester, design,
          channels: four, playing: const [0, 1, 2]));
      expect(segs.keys, [0, 1, 2, 3]);
      expect(segs[1]!['fx'], 17, reason: 'stored: its own look');
      final first = Map.of(segs[0]!)..remove('id');
      final unstored = Map.of(segs[2]!)..remove('id');
      expect(unstored, first, reason: 'not stored: the first look, as today');
      expect(segs[3], {'id': 3, 'on': false});
    });

    group('byte-identical to b716a325', () {
      final shapes = <String, (CustomDesign, List<DeviceChannel>, List<int>?)>{
        'Now Playing save before build 132 (one look on two channels)': (
          _design([_ch(0), _ch(1)]),
          _threeChannels.take(2).toList(),
          null,
        ),
        'Pattern Editor, animated (colour + background, two channels)': (
          _design([
            for (final id in [0, 1])
              _ch(id,
                  colors: const [
                    [0, 0, 255, 0],
                    [0, 0, 0, 0]
                  ],
                  span: false,
                  grp: 1,
                  spc: 0),
          ], tags: const [kPatternEditorDesignTag]),
          _threeChannels.take(2).toList(),
          null,
        ),
        'Pattern Editor, Static three colours (Alternating)': (
          _design([
            _ch(0,
                colors: const [
                  [255, 0, 0, 0],
                  [0, 255, 0, 0],
                  [0, 0, 255, 0]
                ],
                span: false,
                fx: 0,
                grp: 2,
                spc: 0,
                layout: SolidLayout.alternating),
          ], tags: const [kPatternEditorDesignTag]),
          _threeChannels.take(1).toList(),
          null,
        ),
        'one-colour Solid on three channels, no brightness stated': (
          _design([_ch(0, fx: 0), _ch(1, fx: 0), _ch(2, fx: 0)], stated: false),
          _threeChannels,
          null,
        ),
        'a single-channel design on a three-channel controller': (
          _design([_ch(0, fx: 9)]),
          _threeChannels,
          null,
        ),
        'one look, a channel left out of the design': (
          _design([_ch(0), _ch(1, included: false), _ch(2)]),
          _threeChannels,
          null,
        ),
        'one look, a channel not playing': (
          _design([_ch(0), _ch(1), _ch(2)]),
          _threeChannels,
          const [0, 2],
        ),
      };
      final pins = <String, String>{
        'Now Playing save before build 132 (one look on two channels)':
            '{"on":true,"bri":150,"seg":[{"id":0,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true},{"id":1,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true}]}',
        'Pattern Editor, animated (colour + background, two channels)':
            '{"on":true,"bri":150,"seg":[{"id":0,"grp":1,"spc":0,"col":[[0,0,255,0],[0,0,0,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true},{"id":1,"grp":1,"spc":0,"col":[[0,0,255,0],[0,0,0,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true}]}',
        'Pattern Editor, Static three colours (Alternating)':
            '{"on":true,"bri":150,"seg":[{"id":0,"grp":2,"spc":0,"col":[[255,0,0,0],[0,255,0,0],[0,0,255,0]],"pal":5,"fx":84,"sx":0,"ix":0,"on":true}]}',
        'one-colour Solid on three channels, no brightness stated':
            '{"on":true,"seg":[{"id":0,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":0,"sx":44,"ix":90,"on":true},{"id":1,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":0,"sx":44,"ix":90,"on":true},{"id":2,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":0,"sx":44,"ix":90,"on":true}]}',
        'a single-channel design on a three-channel controller':
            '{"on":true,"bri":150,"seg":[{"id":0,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":9,"sx":44,"ix":90,"on":true},{"id":1,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":9,"sx":44,"ix":90,"on":true},{"id":2,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":9,"sx":44,"ix":90,"on":true}]}',
        'one look, a channel left out of the design':
            '{"on":true,"bri":150,"seg":[{"id":0,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true},{"id":1,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true},{"id":2,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true}]}',
        'one look, a channel not playing':
            '{"on":true,"bri":150,"seg":[{"id":0,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true},{"id":1,"on":false},{"id":2,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true}]}',
      };
      for (final e in shapes.entries) {
        testWidgets(e.key, (tester) async {
          final (design, channels, playing) = e.value;
          final sent = await _applyFromMyDesigns(tester, design,
              channels: channels, playing: playing);
          expect(jsonEncode(sent), pins[e.key]);
        });
      }
    });
  });

  group('a favourite tapped on Home', () {
    testWidgets('a mixed favourite (a mixed design added to Favorites) '
        'applies per channel', (tester) async {
      final design = _design([
        _ch(0),
        _ch(1, colors: const [
          [0, 255, 0, 0]
        ], fx: 17, sx: 120, ix: 200, grp: 1, spc: 0),
      ]);
      final segs = _byId(await _tapFavoriteOnHome(tester, design.toWledPayload()));
      expect(segs.keys, [0, 1]);
      expect([for (final s in segs.values) s['fx']], [28, 17]);
      expect(segs[1]!['col'], [
        [0, 255, 0, 0]
      ]);
      expect([for (final s in segs.values) s['grp']], [2, 1]);
    });

    group('byte-identical to b716a325', () {
      final shapes = <String, Map<String, dynamic>>{
        'a card or Pattern Editor favourite (one look, no channel ids)': {
          'on': true,
          'bri': 220,
          'seg': [
            {
              'fx': 28,
              'sx': 44,
              'ix': 90,
              'pal': 5,
              'col': [
                [255, 170, 90, 0]
              ]
            }
          ],
        },
        'a design favourite with one look on two channels':
            _design([_ch(0), _ch(1)]).toWledPayload(),
        'a favourite logged with channel 1 switched off (leading marker)': {
          'on': true,
          'seg': [
            {'id': 0, 'on': false},
            {
              'id': 1,
              'fx': 28,
              'sx': 44,
              'ix': 90,
              'pal': 5,
              'grp': 1,
              'spc': 0,
              'col': [
                [255, 0, 34, 0]
              ],
              'on': true
            },
          ],
        },
      };
      final pins = <String, String>{
        'a card or Pattern Editor favourite (one look, no channel ids)':
            '{"on":true,"seg":[{"id":0,"fx":28,"sx":44,"ix":90,"pal":5,"col":[[255,170,90,0]],"on":true},{"id":1,"fx":28,"sx":44,"ix":90,"pal":5,"col":[[255,170,90,0]],"on":true}]}',
        'a design favourite with one look on two channels':
            '{"on":true,"seg":[{"id":0,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true},{"id":1,"grp":2,"spc":3,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90,"on":true}]}',
        'a favourite logged with channel 1 switched off (leading marker)':
            '{"on":true,"seg":[{"id":0,"fx":28,"sx":44,"ix":90,"pal":5,"grp":1,"spc":0,"col":[[255,0,34,0]],"on":true},{"id":1,"fx":28,"sx":44,"ix":90,"pal":5,"grp":1,"spc":0,"col":[[255,0,34,0]],"on":true}]}',
      };
      for (final e in shapes.entries) {
        testWidgets(e.key, (tester) async {
          final sent = await _tapFavoriteOnHome(tester, e.value);
          expect(jsonEncode(sent), pins[e.key]);
        });
      }
    });
  });
}
