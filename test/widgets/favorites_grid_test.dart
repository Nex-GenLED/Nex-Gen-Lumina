// My Favorites (dashboard) — every load state ends, and none of them blocks
// anything outside the section (2.5.10+108).
//
// build-107 first-login defect: on a brand-new customer's first sign-in the
// favorites load never resolved, the section spun forever, and the app was
// unusable until reinstalled. The root cause was the profile-repair write loop
// (see stub_profile_repair_test.dart, decideProfileSnapshot); these tests pin
// the favorites side so that even a stuck Firestore client can only ever
// produce a bounded, scoped, recoverable state:
//   • loading is one small row, and the rest of the screen stays usable;
//   • a load that never answers turns into "Couldn't load your favorites" +
//     Retry, and the listen behind it is cancelled;
//   • an account still being provisioned parks on the empty state without
//     subscribing;
//   • an empty result is the "No favorites yet" state, and a favorite added
//     afterwards appears.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_load_guard.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';

const _uid = 'customer_under_test';
const _deadline = Duration(milliseconds: 200);

/// A favorites listen that never answers — the stuck client — and counts how
/// often it was opened and cancelled.
class _StallingUserService extends UserService {
  _StallingUserService() : super(firestore: FakeFirebaseFirestore());

  var listens = 0;
  var cancels = 0;

  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return StreamController<List<Map<String, dynamic>>>(
      onListen: () => listens++,
      onCancel: () => cancels++,
    ).stream;
  }
}

FavoritePattern _white(String id, String name) => FavoritePattern(
      id: id,
      patternName: name,
      addedAt: DateTime(2024, 1, 1),
      usageCount: 0,
      patternData: const {'on': true},
      autoAdded: false,
    );

Future<void> _pumpGrid(
  WidgetTester tester, {
  required UserService userService,
  ProfileProvisioning provisioning = ProfileProvisioning.provisioned,
  String? installerViewing,
  VoidCallback? onOtherTab,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteWhiteSlotsProvider.overrideWith((ref) => [
              _white('white_primary', 'Warm White'),
              _white('white_complement', 'Bright White'),
            ]),
        effectiveUserUidProvider.overrideWith((ref) => _uid),
        installerAccessingCustomerProvider.overrideWith((ref) => installerViewing),
        ownProfileProvisioningProvider.overrideWith((ref) => provisioning),
        userServiceProvider.overrideWithValue(userService),
        favoritesLoadTimeoutProvider.overrideWithValue(_deadline),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: const SingleChildScrollView(child: FavoritesGrid()),
          bottomNavigationBar: ElevatedButton(
            onPressed: onOtherTab,
            child: const Text('Other tab'),
          ),
        ),
      ),
    ),
  );
}

/// Tears the tree down, then lets the deadline pass.
///
/// Riverpod 2.6 does NOT cancel a StreamProvider's subscription when the
/// provider is disposed while still loading — it keeps it open until a first
/// value arrives, so `provider.future` can complete. On build-107 every
/// favorites provider rebuilt mid-load therefore left its Firestore listen
/// open until it answered. The deadline is what ends such a listen now, so
/// every test runs past it after unmounting.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(_deadline + const Duration(milliseconds: 50));
}

void main() {
  testWidgets('loading is one scoped row; the whites and the rest of the '
      'screen stay usable', (tester) async {
    final svc = _StallingUserService();
    var otherTabTaps = 0;
    await _pumpGrid(tester, userService: svc, onOtherTab: () => otherTabTaps++);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Warm White'), findsOneWidget,
        reason: 'the reserved whites never wait on Firestore');
    expect(find.text('Bright White'), findsOneWidget);

    await tester.tap(find.text('Other tab'));
    await tester.pump();
    expect(otherTabTaps, 1, reason: 'the spinner must not block navigation');

    await _unmount(tester);
    expect(svc.cancels, 1,
        reason: 'a listen left open by a provider disposed mid-load is still '
            'aborted at the deadline');
  });

  testWidgets('THE REGRESSION: a load that never answers ends in Retry, and '
      'the listen behind it is cancelled', (tester) async {
    final svc = _StallingUserService();
    await _pumpGrid(tester, userService: svc);
    await tester.pump();
    expect(svc.listens, 1);

    await tester.pump(_deadline + const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text("Couldn't load your favorites"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(svc.cancels, 1, reason: 'a timed-out Firestore listen is aborted');

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(svc.listens, 2, reason: 'Retry opens a fresh listen');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('an account still being provisioned parks on the empty state '
      'and never subscribes', (tester) async {
    final svc = _StallingUserService();
    await _pumpGrid(tester,
        userService: svc, provisioning: ProfileProvisioning.notProvisioned);
    await tester.pump();

    expect(find.textContaining('No favorites yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(svc.listens, 0);

    await _unmount(tester);
  });

  testWidgets('a profile that never finishes loading also ends in Retry',
      (tester) async {
    final svc = _StallingUserService();
    await _pumpGrid(tester,
        userService: svc, provisioning: ProfileProvisioning.loading);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(_deadline + const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text("Couldn't load your favorites"), findsOneWidget);
    expect(svc.listens, 0,
        reason: 'no favorites listen before the profile is known');

    await _unmount(tester);
  });

  testWidgets('an installer viewing a customer is not gated on the installer '
      'session\'s own profile', (tester) async {
    final svc = _StallingUserService();
    await _pumpGrid(tester,
        userService: svc,
        provisioning: ProfileProvisioning.notProvisioned,
        installerViewing: 'some_customer');
    await tester.pump();

    expect(svc.listens, 1);

    await _unmount(tester);
  });

  testWidgets('an empty result is "No favorites yet"; a favorite added '
      'afterwards appears', (tester) async {
    final db = FakeFirebaseFirestore();
    final svc = UserService(firestore: db);
    await _pumpGrid(tester, userService: svc);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('No favorites yet'), findsOneWidget);

    await tester.runAsync(() => svc.addFavorite(_uid, {
          'pattern_name': 'Candy Cane Chase',
          'pattern_data': const {'on': true, 'bri': 200},
          'auto_added': false,
        }));
    await tester.pump();
    await tester.pump();

    expect(find.text('Candy Cane Chase'), findsOneWidget);
    expect(find.textContaining('No favorites yet'), findsNothing);

    await _unmount(tester);
  });
}
