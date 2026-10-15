// The build-117 grey screen, reproduced (2026-10-15) and pinned.
//
// The re-entry matrix again (see installer_switch_reentry_test.dart), with
// more of the real graph: the hardware-config, channel, roofline-config and
// migration providers the dashboard harness normally replaces are REAL here.
// On the unfixed code every variant threw Riverpod's
// ConcurrentModificationError inside the provider refresh: the account change
// rebuilt the repository while the channel provider was walking its own
// dependencies, and the heal-on-connect listener's synchronous reads
// re-entered that walk. Bisected: the ladder bus-change listener and the
// healer read were each necessary; the connection-stamp listener was not.
//
// Synthetic accounts and documentation addresses only.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    as fav;
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/media_access_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/day_timeline_providers.dart';
import 'package:nexgen_command/features/site/controller_choice_prompt.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart' show WledSegment;
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart' show homeWhite;
import 'installer_switch_reentry_test.dart' show RealFlipWledNotifier;

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get email => null;
  @override
  bool get isAnonymous => false;
}

const _installer = 'installer-i';
const _customer = 'customer-c';
final _ctlA = ControllerInfo(id: 'ctl-a', ip: '192.0.2.31', name: 'Front');
final _ctlB = ControllerInfo(id: 'ctl-b', ip: '192.0.2.32', name: 'Garage');

class _Shell extends ConsumerWidget {
  const _Shell();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoConnectControllerProvider);
    ref.watch(ladderBusChangeWatchProvider);
    ref.watch(controllerConnectionStampProvider);
    listenForControllerChoice(ref, context);
    return const WledDashboardPage();
  }
}

Future<void> _addRecord(FakeFirebaseFirestore fs, ControllerInfo r) => fs
    .collection('users')
    .doc(_customer)
    .collection('controllers')
    .doc(r.id)
    .set({'ip': r.ip, 'name': r.name, 'createdAt': Timestamp.now()});

Future<ProviderContainer> _pump(WidgetTester tester,
    {required FakeFirebaseFirestore fs, required String authUid}) async {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer(overrides: [
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    activeUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    authStateProvider.overrideWith((ref) => Stream<User?>.value(_User(authUid))),
    isViewingAsCustomerProvider.overrideWithValue(false),
    hasCustomHouseImageProvider.overrideWithValue(true),
    fav.allFavoritesProvider.overrideWith((ref) => Stream.value(const [])),
    fav.favoritedPatternIdsProvider
        .overrideWith((ref) => Stream.value(const <String>{})),
    activePhaseSessionProvider.overrideWithValue(null),
    activeSuggestionsProvider
        .overrideWith((ref) => Stream.value(const <SmartSuggestion>[])),
    favoriteWhiteSlotsProvider.overrideWith((ref) => [
          homeWhite('white_primary', 'Warm White'),
          homeWhite('white_complement', 'Bright White'),
        ]),
    userFavoritePatternsProvider.overrideWith((ref) => Stream.value(const [])),
    todayTimelineProvider.overrideWithValue(DayTimeline.empty),
    demoModeProvider.overrideWith((ref) => false),
    smartPresetsOnHomeProvider.overrideWithValue(false),
    userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    // REAL: identity chain, selection, repository, state, hardware config,
    // channels, zone segments, roofline config and migrations.
    wledStateProvider.overrideWith(RealFlipWledNotifier.new),
    // The zone poller is not part of the chain (bisected 2026-10-15) and its
    // timer would outlive the test.
    zoneSegmentsProvider.overrideWith(_NoZoneSegments.new),
    controllersFirestoreProvider.overrideWithValue(fs),
    controllerReachabilityProbeProvider
        .overrideWithValue((ip) async => ip == _ctlA.ip || ip == _ctlB.ip),
  ]);
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: _Shell())),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return c;
}

Future<List<String>> _drain(WidgetTester tester) async {
  final out = <String>[];
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
    for (var e = tester.takeException(); e != null; e = tester.takeException()) {
      out.add(e.toString());
    }
  }
  return out;
}

const _orders = <List<String>>[
  ['open', 'up'],
  ['up', 'open'],
  ['open', 'emit', 'up'],
  ['down', 'open', 'up'],
  ['open', 'down', 'up'],
  ['emit', 'point', 'inval', 'up'],
  ['point', 'inval', 'emit', 'up'],
  ['down', 'point', 'inval', 'emit', 'up'],
  ['open', 'emit', 'point', 'inval', 'up'],
  ['open', 'point', 'inval', 'emit', 'down', 'up'],
];

void main() {
  for (final order in _orders) {
    final label = 'wide ${order.join('>')}';
    testWidgets(label, (tester) async {
      final fs = FakeFirebaseFirestore();
      await _addRecord(fs, _ctlA);
      final opens = order.contains('open');
      final c = await _pump(tester, fs: fs, authUid: opens ? _installer : _customer);
      final before = await _drain(tester);
      final w = c.read(wledStateProvider.notifier) as RealFlipWledNotifier;
      for (final s in order) {
        switch (s) {
          case 'open':
            c.read(installerAccessingCustomerProvider.notifier).state = _customer;
            c.read(installerAccessingCustomerNameProvider.notifier).state = 'Customer A';
          case 'emit':
            await _addRecord(fs, _ctlB);
          case 'point':
            c.read(controllerSelectionProvider.notifier).pointAt(_ctlB.ip);
          case 'inval':
            c.invalidate(controllersStreamProvider);
            c.invalidate(activeAreaControllerIpsProvider);
          case 'up':
            w.setConnected(true);
          case 'down':
            w.setConnected(false);
        }
      }
      final thrown = await _drain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      try {
        c.dispose();
      } catch (_) {}
      await tester.pump();
      expect(before, isEmpty, reason: 'before $label');
      expect(thrown, isEmpty, reason: 'variant $label threw: $thrown');
    });
  }
}

class _NoZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [];
}
