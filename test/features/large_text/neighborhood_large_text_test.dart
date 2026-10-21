// +120 large-text slice, group 5: the Neighborhood Sync hero and its small
// grey text. The hero was a fixed 120 pt painter plus a 28 pt title in a
// non-scrolling Column, starving the group list on a 320x568 screen; the
// painter now shortens on small screens and the title scales to the width.
// The sync-type pill, the "N homes" count and "Idle" moved one step up in
// size and contrast.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_screen.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/large_text_matrix.dart';
import '../../helpers/text_scale_harness.dart';

List<NeighborhoodGroup> _groups() => [
      NeighborhoodGroup(
        id: 'grp-a',
        name: 'Maple Street Holiday Lights',
        streetName: 'Maple St',
        city: 'Springfield',
        inviteCode: 'TESTA1',
        creatorUid: 'customer-a',
        createdAt: DateTime(2026, 9, 1),
        memberUids: const ['customer-a', 'customer-b', 'customer-c'],
        isActive: true,
        activePatternName: 'Candy Cane Chase',
      ),
      NeighborhoodGroup(
        id: 'grp-b',
        name: 'Cul-de-sac Crew',
        inviteCode: 'TESTB2',
        creatorUid: 'customer-d',
        createdAt: DateTime(2026, 8, 1),
        memberUids: const ['customer-a', 'customer-d'],
      ),
    ];

List<Override> _neighborhood({required bool returning}) => [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
      syncEngineControllerProvider.overrideWith((ref) {}),
      userNeighborhoodsProvider
          .overrideWith((ref) => Stream.value(returning ? _groups() : const [])),
      neighborhoodMembersProvider
          .overrideWith((ref) => Stream.value(const <NeighborhoodMember>[])),
      activeNeighborhoodProvider.overrideWith((ref) => Stream.value(null)),
      currentUserMemberProvider.overrideWithValue(null),
      isGroupCreatorProvider.overrideWithValue(false),
      previousGroupsProvider.overrideWith((ref) async => const []),
      neighborhoodSyncOnboardingCompleteProvider
          .overrideWith((ref) async => returning),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('group list: no overflow across the matrix', (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => largeTextHost(
          overrides: _neighborhood(returning: true),
          page: const NeighborhoodSyncScreen(),
          dock: 0),
      label: 'nsync/groups',
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
  });

  testWidgets('the group list keeps room on a 320x568 screen', (tester) async {
    final profile = largeTextProfiles()
        .firstWhere((p) => p.$1 == '320x568@1.0')
        .$2;
    await pumpAtTextScale(
      tester,
      largeTextHost(
          overrides: _neighborhood(returning: true),
          page: const NeighborhoodSyncScreen(),
          dock: 0),
      profile: profile,
      host: TextScaleHost.none,
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
    expect(tester.takeException(), isNull);
    final list = find.byType(ListView).first;
    expect(tester.getSize(list).height, greaterThan(120),
        reason: 'the hero no longer starves the list at Display Zoom');
    expect(find.textContaining('Maple Street'), findsOneWidget);
  });

  testWidgets('the small grey text reads at 12/13 px, grey-300/400',
      (tester) async {
    final profile = largeTextProfiles()
        .firstWhere((p) => p.$1 == '390x844@1.0')
        .$2;
    await pumpAtTextScale(
      tester,
      largeTextHost(
          overrides: _neighborhood(returning: true),
          page: const NeighborhoodSyncScreen(),
          dock: 0),
      profile: profile,
      host: TextScaleHost.none,
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
    expect(tester.takeException(), isNull);
    final homes = tester.widget<Text>(find.text('3 homes'));
    expect(homes.style?.fontSize, 13);
    expect(homes.style?.color, Colors.grey.shade400);
    final idle = tester.widget<Text>(find.text('Idle').first);
    expect(idle.style?.fontSize, 13);
    expect(idle.style?.color, Colors.grey.shade400);
  });
}
