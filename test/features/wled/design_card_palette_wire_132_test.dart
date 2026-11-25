// Build 132 follow-up, item 1 — the card page's palette for a saved design is
// the first included channel's colours.
//
// It used to gather up to three colours ACROSS channels, so a one-colour
// design on two channels opened as [c, c] and the card page's Apply filled
// the effect's second slot (its background, for many effects) with the
// colour itself; a Pattern Editor colour-plus-background design opened as
// [a, bg, a]. Driven through the real card page: for these designs its Apply
// now sends, through the wire chokepoint, exactly what the design's own
// apply sends.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

Object? _copy(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': _copy(e.value)};
  if (v is List) return [for (final x in v) _copy(x)];
  return v;
}

Map<String, dynamic> _wire(Map<String, dynamic> p) =>
    normalizeWledPayload(Map<String, dynamic>.from(_copy(p) as Map));

CustomDesign _twoChannels(List<LedColorGroup> groups, {List<String> tags = const []}) =>
    CustomDesign(
      id: 'd1',
      name: 'Saved',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      ownerId: 'u',
      channels: [
        for (final id in [0, 1])
          ChannelDesign(
            channelId: id,
            channelName: 'Channel ${id + 1}',
            colorGroups: groups,
            effectId: 28,
            speed: 44,
            intensity: 90,
            grouping: 2,
            spacing: 3,
            ledCount: 30,
          ),
      ],
      brightness: 150,
      brightnessStated: true,
      tags: tags,
    );

/// The card page's Apply for [design], as the controller would receive it.
Future<Map<String, dynamic>> _cardApply(
    WidgetTester tester, CustomDesign design) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = RecordingWledRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      designsStreamProvider.overrideWith((ref) => Stream.value([design])),
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
      userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ],
    child: MaterialApp(
      home: Scaffold(body: ColorwayEffectSelectorPage.forDesign(design: design)),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byKey(const ValueKey('apply-design')));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(repo.applied, hasLength(1), reason: 'one Apply, one write');
  return _wire(repo.applied.single);
}

/// The design's own apply (My Designs, Apply), as the controller would
/// receive it.
Map<String, dynamic> _ownApply(CustomDesign design) => _wire(
    applyChannelFilter(design.toWledPayload(), const [0, 1], kHomeTwoChannels));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('one colour on two channels: Apply sends [c] — not [c, c]',
      (tester) async {
    final design = _twoChannels(const [
      LedColorGroup(startLed: 0, endLed: 29, color: [255, 0, 34, 0]),
    ]);
    final card = await _cardApply(tester, design);
    for (final seg in card['seg'] as List) {
      expect((seg as Map)['col'], const [
        [255, 0, 34, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
    }
    expect(card, _ownApply(design));
  });

  testWidgets('Pattern Editor colour plus background: Apply sends [a, bg] — '
      'not [a, bg, a]', (tester) async {
    final design = _twoChannels(const [
      LedColorGroup(startLed: 0, endLed: 0, color: [0, 0, 255, 0]),
      LedColorGroup(startLed: 1, endLed: 1, color: [0, 0, 0, 0]),
    ], tags: const [kPatternEditorDesignTag]);
    final card = await _cardApply(tester, design);
    for (final seg in card['seg'] as List) {
      expect((seg as Map)['col'], const [
        [0, 0, 255, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
    }
    expect(card, _ownApply(design));
  });
}
