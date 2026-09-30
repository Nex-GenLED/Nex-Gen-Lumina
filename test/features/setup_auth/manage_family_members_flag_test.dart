// +110 package G, follow-up 4 — Manage Family Members is behind a flag that
// defaults off. Self-signup is gone, so an invitation code has nobody to
// redeem it; the screen and its route are hidden until a sub-user
// account-creation function exists.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/site/user_profile_screen.dart';
import 'package:nexgen_command/features/users/manage_family_members_flag.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/services/user_service.dart';

import 'setup_auth_fixtures.dart';

Future<ProviderContainer> _profileScope({required bool flag}) async {
  final fs = FakeFirebaseFirestore();
  // A full document: UserModel.fromJson needs created_at and updated_at.
  await fs.collection('users').doc(kTestUid).set(UserModel(
        id: kTestUid,
        email: kTestEmail,
        displayName: 'Pat',
        ownerId: kTestUid,
        createdAt: DateTime.utc(2026, 9, 29),
        updatedAt: DateTime.utc(2026, 9, 29),
        installationRole: InstallationRole.primary,
        installationId: 'inst-1',
      ).toJson());
  final c = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => Stream.value(FakeAuthUser())),
    userServiceProvider.overrideWithValue(UserService(firestore: fs)),
    manageFamilyMembersEnabledProvider.overrideWithValue(flag),
  ]);
  addTearDown(c.dispose);
  return c;
}

Widget _app(ProviderContainer c, {required bool flag}) {
  Widget stub(String name) => Scaffold(body: Center(child: Text('PAGE:$name')));
  final router = GoRouter(
    initialLocation: AppRoutes.profile,
    routes: [
      GoRoute(path: AppRoutes.profile, builder: (_, __) => const UserProfileScreen()),
      GoRoute(path: AppRoutes.profileEdit, builder: (_, __) => stub('edit')),
      GoRoute(path: AppRoutes.security, builder: (_, __) => stub('security')),
      GoRoute(path: AppRoutes.login, builder: (_, __) => stub('login')),
      // The same redirect the app's /settings/users route uses.
      GoRoute(
        path: AppRoutes.subUsers,
        redirect: (_, __) => manageFamilyMembersRedirect(enabled: flag),
        builder: (_, __) => stub('sub-users'),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  test('the flag defaults off', () {
    expect(kManageFamilyMembersEnabled, isFalse);
    expect(ProviderContainer().read(manageFamilyMembersEnabledProvider), isFalse);
  });

  test('the route redirects to the profile page while off, opens while on',
      () {
    expect(manageFamilyMembersRedirect(enabled: false), AppRoutes.profile);
    expect(manageFamilyMembersRedirect(enabled: true), isNull);
  });

  testWidgets('flag off: the profile page shows no Manage Family Members tile',
      (tester) async {
    await tester.runAsync(() async {
      final c = await _profileScope(flag: false);
      await tester.pumpWidget(_app(c, flag: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('Edit Profile'), findsOneWidget, reason: 'page loaded');
      expect(find.text('Manage Family Members'), findsNothing);
      expect(find.byKey(const ValueKey('profile-manage-family-members')),
          findsNothing);
    });
  });

  testWidgets('flag off: going straight to /settings/users lands on the profile',
      (tester) async {
    await tester.runAsync(() async {
      final c = await _profileScope(flag: false);
      await tester.pumpWidget(_app(c, flag: false));
      await tester.pump();
      final ctx = tester.element(find.byType(UserProfileScreen));
      GoRouter.of(ctx).go(AppRoutes.subUsers);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('PAGE:sub-users'), findsNothing);
      expect(find.byType(UserProfileScreen), findsOneWidget);
    });
  });

  testWidgets('flag on: the tile is back and opens the screen',
      (tester) async {
    await tester.runAsync(() async {
      final c = await _profileScope(flag: true);
      await tester.pumpWidget(_app(c, flag: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final tile = find.byKey(const ValueKey('profile-manage-family-members'));
      expect(tile, findsOneWidget);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('PAGE:sub-users'), findsOneWidget);
    });
  });
}
