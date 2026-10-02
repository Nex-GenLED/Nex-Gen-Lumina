// +113 (owner decision 2026-10-01) — Segment Setup is installer-only, behind
// the same lock as the Roofline Setup Wizard. A customer sees the lock and a
// door to Mark Your Roofline; an installer sees the editor.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/installer_lock_screen.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

import '../setup_auth/setup_auth_fixtures.dart';

const _front =
    ControllerInfo(id: 'ctrl-a', ip: '192.0.2.10', name: 'Front House');

class _ActiveInstaller extends InstallerModeNotifier {
  _ActiveInstaller(super.ref) {
    state = true;
  }
}

Widget _host(FakeFirebaseFirestore fs, {required bool installer}) {
  return ProviderScope(
    overrides: [
      if (installer)
        installerModeActiveProvider.overrideWith((ref) => _ActiveInstaller(ref)),
      effectiveUserUidProvider.overrideWith((ref) => kTestUid),
      controllersStreamProvider
          .overrideWith((ref) => Stream.value(const [_front])),
      rooflineConfigServiceProvider
          .overrideWithValue(RooflineConfigService(firestore: fs)),
      deviceChannelsProvider.overrideWith((ref) => const []),
      selectedDeviceIpProvider.overrideWith((ref) => null),
      controllerRepositoryProvider.overrideWith((ref, target) => null),
      houseImageUrlProvider.overrideWith((ref) => null),
    ],
    child: const MaterialApp(home: SegmentSetupScreen()),
  );
}

void main() {
  testWidgets('a customer sees the installer lock, not the editor', (tester) async {
    final fs = FakeFirebaseFirestore();
    await seedPixelMap(fs, twoChannelRoofline());
    await tester.pumpWidget(_host(fs, installer: false));
    await tester.pumpAndSettle();

    expect(find.byType(InstallerLockScreen), findsOneWidget);
    expect(find.text('Installer Access Required'), findsOneWidget);
    expect(find.textContaining('Roofline Segments editor'), findsOneWidget);
    expect(find.text('Add Segment'), findsNothing);
    expect(find.text('Garage Run'), findsNothing,
        reason: 'the map is not even loaded for a customer');
    expect(find.byTooltip('Save Configuration'), findsNothing);
  });

  testWidgets('the lock offers Mark Your Roofline instead', (tester) async {
    final fs = FakeFirebaseFirestore();
    await seedPixelMap(fs, twoChannelRoofline());
    await tester.pumpWidget(_host(fs, installer: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('installer-lock-alternative')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RooflineFeatureWalkthroughScreen), findsOneWidget);
  });

  testWidgets('an installer sees the editor', (tester) async {
    final fs = FakeFirebaseFirestore();
    await seedPixelMap(fs, twoChannelRoofline());
    await tester.pumpWidget(_host(fs, installer: true));
    await tester.pumpAndSettle();

    expect(find.byType(InstallerLockScreen), findsNothing);
    expect(find.text('Add Segment'), findsOneWidget);
    expect(find.text('Garage Run'), findsOneWidget);
    expect(find.byTooltip('Save Configuration'), findsOneWidget);
  });
}
