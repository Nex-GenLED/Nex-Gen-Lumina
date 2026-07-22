import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_providers.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_screen.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// D3-S1 — the dealer dashboard degrades honestly for non-admin staff.
///
/// The D3-HOTFIX scoped `/installers` read to hasAdminOrOwnerClaim(), because
/// those docs hold cleartext PINs and mintStaffToken is callable
/// unauthenticated — any reader could harvest a working staff credential.
///
/// But the dealer dashboard is reachable under installer/salesperson claims
/// (installer_landing_screen.dart:171, sales_landing_screen.dart:158). Without
/// a gate, two things went wrong — and they went wrong DIFFERENTLY:
///
///   • _TeamTab  — `installersAsync.when(error:)` renders a raw
///     "Error: [cloud_firestore/permission-denied]" string.
///   • _OverviewTab — `_buildStatCards` does `valueOrNull ?? []`, so a denied
///     stream silently renders "0 active installers". That is WORSE than an
///     error: it is a confident wrong number.
///
/// These tests pin both degradations. They drive the PUBLIC screen because the
/// tabs are private widgets.
void main() {
  const dealerCode = '55';

  final installer = InstallerInfo(
    installerCode: '10',
    dealerCode: dealerCode,
    name: 'Pat Installer',
    registeredAt: DateTime.utc(2026, 1, 1),
  );

  /// Overrides every provider the Overview tab touches, so the widget tree
  /// never reaches real Firestore. `isAdmin` drives the gate under test.
  List<Override> overrides({required bool isAdmin}) => [
        hasAdminOrOwnerSessionProvider.overrideWithValue(isAdmin),
        dealerJobsProvider.overrideWith((ref, arg) => Stream.value([])),
        dealerPendingPayoutsProvider.overrideWith((ref, arg) => Stream.value([])),
        dealerRecentActivityProvider.overrideWith((ref, arg) => Stream.value([])),
        dealerInstallersProvider.overrideWith(
          (ref, arg) => Stream.value([installer]),
        ),
      ];

  Future<void> pump(WidgetTester tester, {required bool isAdmin}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(isAdmin: isAdmin),
        child: const MaterialApp(
          home: DealerDashboardScreen(dealerCodeOverride: dealerCode),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Overview tab — the installer stat must not fabricate a 0', () {
    testWidgets('non-admin session shows "—", NOT "0"', (tester) async {
      await pump(tester, isAdmin: false);

      expect(find.text('Active installers'), findsOneWidget);

      // The regression this slice exists to prevent: a denied read rendering
      // as a confident zero.
      final statCard = find.ancestor(
        of: find.text('Active installers'),
        matching: find.byType(Column),
      );
      expect(statCard, findsWidgets);
      expect(find.text('—'), findsWidgets,
          reason: 'restricted must read as unknown, not as none');
    });

    testWidgets('admin session shows the real count', (tester) async {
      await pump(tester, isAdmin: true);

      expect(find.text('Active installers'), findsOneWidget);
      expect(find.text('1'), findsWidgets,
          reason: 'one active installer was seeded');
    });
  });

  group('the gate prevents SUBSCRIPTION, not just rendering', () {
    // The overrides above hand back data unconditionally, so the tests above
    // prove the gate branches correctly — but not that we avoid touching the
    // denied stream at all. Here the installers provider FAILS if read. If the
    // gate ever regresses to watching it unconditionally, the error surfaces
    // and these fail. This is the closest a widget test gets to the real
    // permission-denied path.
    List<Override> hostileOverrides() => [
          hasAdminOrOwnerSessionProvider.overrideWithValue(false),
          dealerJobsProvider.overrideWith((ref, arg) => Stream.value([])),
          dealerPendingPayoutsProvider
              .overrideWith((ref, arg) => Stream.value([])),
          dealerRecentActivityProvider
              .overrideWith((ref, arg) => Stream.value([])),
          dealerInstallersProvider.overrideWith(
            (ref, arg) => Stream<List<InstallerInfo>>.error(
              Exception('[cloud_firestore/permission-denied] '
                  'Missing or insufficient permissions.'),
            ),
          ),
        ];

    Future<void> pumpHostile(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: hostileOverrides(),
          child: const MaterialApp(
            home: DealerDashboardScreen(dealerCodeOverride: dealerCode),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Overview does not surface a denied installers stream',
        (tester) async {
      await pumpHostile(tester);

      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('Team does not surface a denied installers stream',
        (tester) async {
      await pumpHostile(tester);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.text('Team roster is admin-only'), findsOneWidget);
    });
  });

  group('Team tab — restricted notice instead of a raw error', () {
    testWidgets('non-admin session sees the admin-only notice', (tester) async {
      await pump(tester, isAdmin: false);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.text('Team roster is admin-only'), findsOneWidget);
      expect(
        find.textContaining('restricted to admin and owner sessions'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('non-admin session never renders a raw permission error',
        (tester) async {
      await pump(tester, isAdmin: false);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('Error:'), findsNothing);
    });

    testWidgets('non-admin session cannot reach Manage team', (tester) async {
      // The button pushes InstallerManagementScreen, which reads /installers.
      // It lives inside the roster branch, so gating the tab gates it too —
      // pin that, since it is the only entry point to that screen.
      await pump(tester, isAdmin: false);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.text('Manage team'), findsNothing);
    });

    testWidgets('admin session still sees the roster and Manage team',
        (tester) async {
      await pump(tester, isAdmin: true);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.text('Team roster is admin-only'), findsNothing);
      expect(find.text('Pat Installer'), findsOneWidget);
      expect(find.text('Manage team'), findsOneWidget);
    });
  });
}
