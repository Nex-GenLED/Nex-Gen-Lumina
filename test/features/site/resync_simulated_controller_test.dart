// Store readiness 3c — Settings → Controllers → "Re-sync Configuration" on the
// simulated controller (the App Store review account).
//
// The pusher talks HTTP straight to the record's IP. On the review account
// that IP is a placeholder, so the action spun for 30 s+ and ended in a red
// "Re-sync failed". It now says there is nothing to re-sync and sends nothing.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/manage_controllers_page.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

import '../../helpers/home_dashboard_harness.dart' show SeededWledNotifier;

class _User extends Fake implements User {
  @override
  String get uid => 'account-a';
  @override
  String? get email => null;
}

class _MemoryStore implements ControllerSelectionStore {
  @override
  Future<String?> readSelected(String uid) async => null;
  @override
  Future<void> writeSelected(String uid, String? id) async {}
  @override
  Future<Map<String, DateTime>> readConnected(String uid) async => {};
  @override
  Future<void> writeConnected(String uid, Map<String, DateTime> s) async {}
}

// Documentation address: never routable.
const _demo = ControllerInfo(id: 'demo', ip: '192.0.2.10', name: 'Demo Controller');

void main() {
  testWidgets('simulated controller: an honest note, no spinner, no red failure',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(_User())),
        controllersStreamProvider
            .overrideWith((ref) => Stream.value(const [_demo])),
        controllersFirestoreProvider
            .overrideWithValue(FakeFirebaseFirestore()),
        controllerSelectionStoreProvider.overrideWithValue(_MemoryStore()),
        controllerReachabilityProbeProvider
            .overrideWithValue((ip) async => false),
        wledStateProvider
            .overrideWith(() => SeededWledNotifier(WledStateModel.initial())),
        wledRepositoryProvider.overrideWithValue(DemoWledRepository()),
      ],
      child: const MaterialApp(home: ManageControllersPage()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    await tester.tap(find.byTooltip('Re-sync Configuration'));
    await tester.pump();

    expect(find.textContaining('simulated controller'), findsOneWidget);
    expect(find.text('Re-syncing controller…'), findsNothing);
    expect(find.textContaining('Re-sync failed'), findsNothing);
  });
}
