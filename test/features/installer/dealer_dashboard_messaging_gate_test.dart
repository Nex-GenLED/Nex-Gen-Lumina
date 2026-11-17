import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_providers.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_screen.dart';
import 'package:nexgen_command/features/sales/services/dealer_messaging_config_service.dart';

/// The dealer dashboard's Messaging tab is for admin and owner sessions only.
///
/// Its save writes dealers/{code}/config/messaging, and the rules admit that
/// write for the dealer's admin claim and the corporate admin/owner claims
/// only (`hasDealerAdminClaim(dealerCode) || hasAdminOrOwnerClaim()`). The
/// dashboard is also reachable from sales and installer sessions, which
/// would get an editor whose every save is denied. Those sessions no longer
/// see the tab.
final _isAdmin = StateProvider<bool>((ref) => false);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const dealerCode = '01';

  Future<ProviderContainer> pump(WidgetTester tester,
      {required bool isAdmin}) async {
    final container = ProviderContainer(overrides: [
      _isAdmin.overrideWith((ref) => isAdmin),
      hasAdminOrOwnerSessionProvider.overrideWith((ref) => ref.watch(_isAdmin)),
      dealerJobsProvider.overrideWith((ref, arg) => Stream.value([])),
      dealerPendingPayoutsProvider.overrideWith((ref, arg) => Stream.value([])),
      dealerRecentActivityProvider.overrideWith((ref, arg) => Stream.value([])),
      dealerInstallersProvider.overrideWith((ref, arg) => Stream.value([])),
      dealerMessagingConfigServiceProvider.overrideWithValue(
        DealerMessagingConfigService(FakeFirebaseFirestore()),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DealerDashboardScreen(dealerCodeOverride: dealerCode),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('sales / installer session: no Messaging tab', (tester) async {
    await pump(tester, isAdmin: false);

    expect(find.widgetWithText(Tab, 'Inventory'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Messaging'), findsNothing);
    expect(find.text('Save messaging settings'), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs, hasLength(5));
  });

  testWidgets('admin / owner session: Messaging tab opens the editor',
      (tester) async {
    await pump(tester, isAdmin: true);

    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs, hasLength(6));
    await tester.tap(find.widgetWithText(Tab, 'Messaging'));
    await tester.pumpAndSettle();
    expect(find.text('Save messaging settings'), findsOneWidget);
  });

  testWidgets('the tab follows the session if it changes on screen',
      (tester) async {
    final container = await pump(tester, isAdmin: true);

    await tester.tap(find.widgetWithText(Tab, 'Messaging'));
    await tester.pumpAndSettle();
    expect(find.text('Save messaging settings'), findsOneWidget);

    // Admin session ends while the Messaging tab is showing.
    container.read(_isAdmin.notifier).state = false;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, 'Messaging'), findsNothing);
    expect(find.text('Save messaging settings'), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs, hasLength(5));

    // And back again.
    container.read(_isAdmin.notifier).state = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, 'Messaging'), findsOneWidget);
  });
}
