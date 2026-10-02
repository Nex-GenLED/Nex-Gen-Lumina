// +113 (#131) — Trace Roofline's Delete follows the editor's selection: it is
// live right after load when a traced segment exists, it removes that
// segment, and once nothing can be selected a tap on it says why. The panel
// also names the stored sections that have no photo outline.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/roofline_editor_screen.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

import '../setup_auth/setup_auth_fixtures.dart';

const _front =
    ControllerInfo(id: 'ctrl-a', ip: '192.0.2.10', name: 'Front House');

Widget _hosted(FakeFirebaseFirestore fs) {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push('/screen'),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/screen', builder: (_, __) => const RooflineEditorScreen()),
  ]);
  return ProviderScope(
    overrides: [
      effectiveUserUidProvider.overrideWith((ref) => kTestUid),
      controllersStreamProvider
          .overrideWith((ref) => Stream.value(const [_front])),
      rooflineConfigServiceProvider
          .overrideWithValue(RooflineConfigService(firestore: fs)),
      deviceChannelsProvider.overrideWith((ref) => const []),
      selectedDeviceIpProvider.overrideWith((ref) => null),
      controllerRepositoryProvider.overrideWith((ref, target) => null),
      houseImageUrlProvider.overrideWith((ref) => null),
      useStockImageProvider.overrideWith((ref) => true),
      rooflineMaskProvider.overrideWith((ref) => null),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Color? _deleteLabelColor(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('trace-delete')),
        matching: find.text('Delete')))
    .style
    ?.color;

void main() {
  testWidgets(
      'Delete is live after load, removes the traced segment, then explains '
      'why it is disabled', (tester) async {
    final fs = FakeFirebaseFirestore();
    // One traced segment (has points) and three installer sections (no points).
    await seedPixelMap(fs, twoChannelRoofline());
    await tester.pumpWidget(_hosted(fs));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('1 segments'), findsOneWidget);
    expect(_deleteLabelColor(tester), Colors.redAccent,
        reason: 'the editor reported its selection after its first frame');

    // The panel names the sections the trace cannot show.
    await tester.tap(find.text('1 segments'));
    await tester.pump();
    expect(find.textContaining('3 more sections from Mark Your Roofline'),
        findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('trace-delete')));
    await tester.tap(find.byKey(const ValueKey('trace-delete')));
    await tester.pump();
    expect(find.text('0 segments'), findsOneWidget);
    expect(_deleteLabelColor(tester), Colors.white38);

    // Disabled, but not silent.
    await tester.tap(find.byKey(const ValueKey('trace-delete')));
    await tester.pump();
    expect(find.textContaining('have no outline on the photo'), findsOneWidget);
  });
}
