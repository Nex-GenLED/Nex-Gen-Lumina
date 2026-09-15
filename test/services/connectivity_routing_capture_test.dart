import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/encryption_service.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';

/// #114: the connectivity check now PUBLISHES what it saw. These tests pin two
/// things per branch:
///  1. the status returned is exactly what it was before the instrumentation
///     (no routing change), and
///  2. the published snapshot names the branch and its inputs.
class _ScriptedConnectivity extends ConnectivityService {
  _ScriptedConnectivity({required this.types, this.ssid, this.failureReason});

  final List<ConnectivityResult> types;
  final String? ssid;
  final String? failureReason;

  @override
  Future<List<ConnectivityResult>> getConnectivityTypes() async => types;

  @override
  Future<String?> getCurrentSsid() async => ssid;

  @override
  String? get lastSsidFailureReason => failureReason;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final homeHash = EncryptionService.hashSsid('HomeNet');

  setUp(() => RoutingDiagnostics.resetForTest());

  Future<(ConnectivityStatus, ConnectivityCheckSnapshot)> run(
    _ScriptedConnectivity service,
    String? hash,
  ) async {
    final status = await service.watchConnectivity(hash).first;
    final snapshot = RoutingDiagnostics.instance.lastCheck;
    expect(snapshot, isNotNull, reason: 'every check must publish a snapshot');
    return (status, snapshot!);
  }

  test('no connection → offline, no_connection', () async {
    final (status, s) = await run(_ScriptedConnectivity(types: const []), homeHash);
    expect(status, ConnectivityStatus.offline);
    expect(s.outcome, 'offline');
    expect(s.reason, ConnectivityCheckReason.noConnection);
    expect(s.wifiReported, isFalse);
    expect(s.ssidReadable, isNull);
  });

  test('cellular only → remote, wifi_not_reported', () async {
    final (status, s) = await run(
        _ScriptedConnectivity(types: const [ConnectivityResult.mobile]), homeHash);
    expect(status, ConnectivityStatus.remote);
    expect(s.reason, ConnectivityCheckReason.wifiNotReported);
    expect(s.reportedTypes, ['mobile']);
  });

  test('[other] (e.g. a VPN tunnel) → remote, wifi_not_reported — unchanged behaviour',
      () async {
    final (status, s) = await run(
        _ScriptedConnectivity(types: const [ConnectivityResult.other]), homeHash);
    expect(status, ConnectivityStatus.remote);
    expect(s.wifiReported, isFalse);
    expect(s.reportedTypes, ['other']);
  });

  test('Wi-Fi, no saved fingerprint → local, no_home_fingerprint', () async {
    final (status, s) = await run(
        _ScriptedConnectivity(types: const [ConnectivityResult.wifi], ssid: 'HomeNet'),
        null);
    expect(status, ConnectivityStatus.local);
    expect(s.reason, ConnectivityCheckReason.noHomeFingerprint);
    expect(s.homeFingerprintConfigured, isFalse);
    expect(s.ssidReadable, isNull);
  });

  test('Wi-Fi, name unreadable → local (assumed), reason code sanitised', () async {
    final (status, s) = await run(
      _ScriptedConnectivity(
        types: const [ConnectivityResult.wifi],
        ssid: null,
        failureReason: 'corelocation_warmup_failed:current_position:timeout',
      ),
      homeHash,
    );
    expect(status, ConnectivityStatus.local);
    expect(s.reason, ConnectivityCheckReason.ssidUnreadableAssumedLocal);
    expect(s.homeFingerprintConfigured, isTrue);
    expect(s.ssidReadable, isFalse);
    expect(s.ssidMatched, isNull);
    expect(s.ssidFailureReason, 'corelocation_warmup_failed');
  });

  test('Wi-Fi, name matches → local, ssid_matched', () async {
    final (status, s) = await run(
        _ScriptedConnectivity(types: const [ConnectivityResult.wifi], ssid: 'HomeNet'),
        homeHash);
    expect(status, ConnectivityStatus.local);
    expect(s.reason, ConnectivityCheckReason.ssidMatched);
    expect(s.wifiReported, isTrue);
    expect(s.ssidReadable, isTrue);
    expect(s.ssidMatched, isTrue);
  });

  test('Wi-Fi, different network → remote, ssid_mismatch', () async {
    final (status, s) = await run(
        _ScriptedConnectivity(types: const [ConnectivityResult.wifi], ssid: 'Guest'),
        homeHash);
    expect(status, ConnectivityStatus.remote);
    expect(s.reason, ConnectivityCheckReason.ssidMismatch);
    expect(s.ssidMatched, isFalse);
  });

  test('Android "<unknown ssid>" → remote, ssid_mismatch — unchanged (latent #114 gap)',
      () async {
    final (status, s) = await run(
      _ScriptedConnectivity(
          types: const [ConnectivityResult.wifi], ssid: '<unknown ssid>'),
      homeHash,
    );
    expect(status, ConnectivityStatus.remote);
    expect(s.reason, ConnectivityCheckReason.ssidMismatch);
  });

  test('isOnHomeNetwork returns the same answer with or without a capture', () async {
    for (final ssid in <String?>['HomeNet', 'Guest', null]) {
      final service = _ScriptedConnectivity(
          types: const [ConnectivityResult.wifi], ssid: ssid);
      final capture = HomeNetworkEvaluation();
      expect(
        await service.isOnHomeNetwork(homeHash, capture: capture),
        await service.isOnHomeNetwork(homeHash),
        reason: 'ssid=$ssid',
      );
      expect(capture.reason, isNotNull);
    }
    // The non-routing caller (isLocalNetworkProvider) passes null.
    expect(await _ScriptedConnectivity(types: const []).isOnHomeNetwork(null), isTrue);
  });
}
