import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/widgets/route_path_badge.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';

/// #114 dashboard badge: driven only by commands that actually left the app.
void main() {
  late RoutingDiagnostics diag;

  setUp(() {
    diag = RoutingDiagnostics(sink: (_, __) async => true);
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [RoutePathBadge(diagnostics: diag)]),
        ),
      );

  testWidgets('hidden until the first routed command', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Direct'), findsNothing);
    expect(find.text('Via Bridge'), findsNothing);
  });

  /// The notify is deferred to a microtask; the first pump runs it, the second
  /// renders the rebuilt badge.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the path of the most recent command', (tester) async {
    await tester.pumpWidget(host());

    diag.record(RoutePath.direct, '/json/state');
    await settle(tester);
    expect(find.text('Direct'), findsOneWidget);

    diag.record(RoutePath.bridge, 'applyJson');
    await settle(tester);
    expect(find.text('Via Bridge'), findsOneWidget);
    expect(find.text('Direct'), findsNothing);

    diag.record(RoutePath.direct, '/json/state');
    await settle(tester);
    expect(find.text('Direct'), findsOneWidget);
  });

  testWidgets('tap opens the routing sheet with the check inputs', (tester) async {
    await tester.pumpWidget(host());
    diag.recordConnectivityCheck(ConnectivityCheckSnapshot(
      checkedAt: DateTime.now(),
      reportedTypes: const ['other'],
      wifiReported: false,
      outcome: 'remote',
      reason: ConnectivityCheckReason.wifiNotReported,
    ));
    diag.record(RoutePath.bridge, 'getState');
    await tester.pump();

    await tester.tap(find.text('Via Bridge'));
    await tester.pumpAndSettle();

    expect(find.text('Command routing'), findsOneWidget);
    expect(find.textContaining('Wi-Fi reported: no'), findsWidgets);
    expect(find.textContaining('remote (wifi_not_reported)'), findsWidgets);
  });
}
