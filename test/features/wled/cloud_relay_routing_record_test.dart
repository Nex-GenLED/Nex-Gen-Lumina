import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #114: every command that goes through the relay is recorded as `bridge`,
/// whether or not the bridge ever answers.
void main() {
  // applyJson reads the participation cache (SharedPreferences) before it
  // queues, so the binding and a mock store are required.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RoutingDiagnostics.resetForTest();
  });

  CloudRelayRepository repo(FakeFirebaseFirestore fs) => CloudRelayRepository(
        userId: 'u1',
        controllerId: 'c1',
        controllerIp: '10.0.0.32',
        webhookUrl: '',
        firestore: fs,
        commandTimeout: const Duration(milliseconds: 200),
      );

  test('a relay read is recorded as bridge with its command type', () async {
    await repo(FakeFirebaseFirestore()).getState();

    final recent = RoutingDiagnostics.instance.recent;
    expect(recent, isNotEmpty);
    expect(recent.first.path, RoutePath.bridge);
    expect(recent.first.command, 'getState');
  });

  test('a relay write is recorded as bridge', () async {
    await repo(FakeFirebaseFirestore()).applyJson({'on': true});

    final commands = RoutingDiagnostics.instance.recent.map((r) => r.command);
    expect(RoutingDiagnostics.instance.recent.every((r) => r.path == RoutePath.bridge),
        isTrue);
    expect(commands, contains('applyJson'));
  });
}
