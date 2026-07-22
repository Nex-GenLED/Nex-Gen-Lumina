// Test for the #63 E3 step 4 wire — the ref.listen inside
// patternRepositoryProvider that populates / clears the Explore
// "My Teams" folder in response to currentUserProfileProvider.
//
// Pre-fix, updateMyTeams / clearMyTeams had zero call sites and
// _myTeamsNodes was always []. The folder rendered but was empty.
// These tests verify the listen now wires the profile stream into
// the repo's My Teams state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/models/user_model.dart';

UserModel _profileWithTeams(List<String> teams) {
  final now = DateTime(2026, 5, 29, 12);
  return UserModel(
    id: 'test-uid',
    email: 'test@example.com',
    displayName: 'Test User',
    ownerId: 'test-uid',
    createdAt: now,
    updatedAt: now,
    sportsTeams: teams,
  );
}

void main() {
  group('patternRepositoryProvider My Teams listen', () {
    test(
      'profile with a recognised team populates the My Teams folder',
      () async {
        final container = ProviderContainer(overrides: [
          currentUserProfileProvider.overrideWith(
            (ref) => Stream.value(_profileWithTeams(['Kansas City Chiefs'])),
          ),
        ]);
        addTearDown(container.dispose);

        // Let the StreamProvider emit so the ref.listen fires with
        // AsyncData. Reading the repo also builds it + registers the
        // listen if it hasn't been registered already.
        await container.read(currentUserProfileProvider.future);
        final repo = container.read(patternRepositoryProvider);

        // Pump once more so the listen callback runs through the
        // microtask queue.
        await Future<void>.delayed(Duration.zero);

        final myTeamsChildren =
            await repo.getChildNodes(PersonalizedFolderIds.myTeams);
        expect(
          myTeamsChildren,
          isNotEmpty,
          reason: 'My Teams folder should contain at least one matched '
              'palette for "Kansas City Chiefs".',
        );
      },
    );

    test(
      'null profile leaves the My Teams folder empty (no palettes)',
      () async {
        final container = ProviderContainer(overrides: [
          currentUserProfileProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ]);
        addTearDown(container.dispose);

        await container.read(currentUserProfileProvider.future);
        final repo = container.read(patternRepositoryProvider);
        await Future<void>.delayed(Duration.zero);

        final myTeamsChildren =
            await repo.getChildNodes(PersonalizedFolderIds.myTeams);
        expect(myTeamsChildren, isEmpty);
      },
    );

    test(
      'profile with empty sportsTeams leaves the My Teams folder empty',
      () async {
        final container = ProviderContainer(overrides: [
          currentUserProfileProvider.overrideWith(
            (ref) => Stream.value(_profileWithTeams(const [])),
          ),
        ]);
        addTearDown(container.dispose);

        await container.read(currentUserProfileProvider.future);
        final repo = container.read(patternRepositoryProvider);
        await Future<void>.delayed(Duration.zero);

        final myTeamsChildren =
            await repo.getChildNodes(PersonalizedFolderIds.myTeams);
        expect(myTeamsChildren, isEmpty);
      },
    );
  });
}
