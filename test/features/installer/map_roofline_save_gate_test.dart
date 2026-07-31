// F-5 REGRESSION GATE — the wizard must NOT advance past a failed pixel-map save.
//
// Before this, map_roofline_step.dart:417 swallowed the exception (`catch (_)`)
// and _onContinue() discarded the bool, calling onNext() unconditionally. A
// pixel walk that failed to persist was indistinguishable from one that
// succeeded; the installer finished the job and drove away.
//
// The invariant under test is narrow and absolute: onNext() is called ONLY on a
// genuinely successful save (or when there was nothing to save).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_state.dart';
import 'package:nexgen_command/features/installer/screens/map_roofline_step.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

/// Service whose save always fails — stands in for "no signal in a driveway".
class _FailingRooflineService extends RooflineConfigService {
  _FailingRooflineService() : super(firestore: FakeFirebaseFirestore());
  int calls = 0;

  @override
  Future<void> savePixelMap(
    String userId,
    String controllerId,
    RooflineConfiguration config, {
    Map<int, int> sourceCounts = const {},
    String createdBy = '',
    int mapVersion = 1,
    Map<int, bool> staleByChannel = const {},
  }) async {
    calls++;
    throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'network unreachable');
  }
}

/// Service whose save always succeeds.
class _OkRooflineService extends RooflineConfigService {
  _OkRooflineService() : super(firestore: FakeFirebaseFirestore());
  int calls = 0;

  @override
  Future<void> savePixelMap(
    String userId,
    String controllerId,
    RooflineConfiguration config, {
    Map<int, int> sourceCounts = const {},
    String createdBy = '',
    int mapVersion = 1,
    Map<int, bool> staleByChannel = const {},
  }) async {
    calls++;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required RooflineConfigService service,
  required void Function() onNext,
  bool withMarks = true,
}) async {
  final container = ProviderContainer(overrides: [
    rooflineConfigServiceProvider.overrideWithValue(service),
    effectiveUserUidProvider.overrideWithValue('staff_installer_0101'),
    activePixelMapControllerIdProvider.overrideWithValue('ctrlA'),
    deviceChannelsProvider.overrideWithValue(
      const [
        DeviceChannel(id: 0, name: 'Front', start: 0, stop: 100, gpioPin: 16),
      ],
    ),
    // No device: _restorePrior()'s getState() is skipped on a null repository.
    wledRepositoryProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);

  if (withMarks) {
    container.read(rooflineCaptureProvider.notifier).setMarks(
      0,
      const [CaptureMark(pixel: 0, kind: MarkKind.corner),
             CaptureMark(pixel: 50, kind: MarkKind.corner)],
    );
  }

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: MapRooflineStep(onBack: () {}, onNext: onNext),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FAILED save: wizard does NOT advance, and says so', (t) async {
    var advanced = 0;
    final svc = _FailingRooflineService();
    await _pump(t, service: svc, onNext: () => advanced++);

    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();

    // THE INVARIANT.
    expect(advanced, 0, reason: 'onNext() must not fire on a failed save');
    // And the installer is told, rather than the failure being silent.
    expect(find.text("Roofline map didn't save"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(svc.calls, 1);
  });

  testWidgets('Retry re-attempts the save and still does not advance while failing',
      (t) async {
    var advanced = 0;
    final svc = _FailingRooflineService();
    await _pump(t, service: svc, onNext: () => advanced++);

    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();

    expect(svc.calls, 2, reason: 'Retry must actually re-attempt the write');
    expect(advanced, 0);
    expect(find.text("Roofline map didn't save"), findsOneWidget);
  });

  testWidgets('Dismissing with Close leaves the installer on the step', (t) async {
    var advanced = 0;
    await _pump(t, service: _FailingRooflineService(), onNext: () => advanced++);

    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();

    // Not a seventh silent success: declining to retry must not advance either.
    expect(advanced, 0);
    expect(find.text("Roofline map didn't save"), findsNothing);
  });

  testWidgets('SUCCESSFUL save advances exactly once', (t) async {
    var advanced = 0;
    final svc = _OkRooflineService();
    await _pump(t, service: svc, onNext: () => advanced++);

    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();

    expect(svc.calls, 1);
    expect(advanced, 1);
    expect(find.text("Roofline map didn't save"), findsNothing);
  });

  testWidgets('NOTHING captured: advances without touching the service', (t) async {
    var advanced = 0;
    final svc = _FailingRooflineService();
    await _pump(t, service: svc, onNext: () => advanced++, withMarks: false);

    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();

    // An installer who mapped nothing must never be trapped by the gate.
    expect(svc.calls, 0);
    expect(advanced, 1);
  });
}
