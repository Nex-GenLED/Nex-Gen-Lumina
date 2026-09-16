import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/encryption_service.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';

/// #114 FIX — "iOS reports no Wi-Fi interface" is not proof of being away.
///
/// Confirmed live 2026-09-16: the phone sat on home Wi-Fi with a matching
/// fingerprint while `connectivity_plus` reported `[mobile]` for 22 minutes,
/// so every command took the relay (1.9–34.5 s) instead of the LAN. The branch
/// now asks the controller directly before concluding remote.
///
/// These tests pin the NEW branch and prove the probe is not consulted on any
/// other path.
class _ScriptedConnectivity extends ConnectivityService {
  _ScriptedConnectivity({
    required this.types,
    this.ssid,
    required bool? probeAnswers,
    this.probeThrows = false,
  })  : _probeAnswers = probeAnswers,
        super(
          controllerProbe: (ip, timeout) async => false,
        );

  final List<ConnectivityResult> types;
  final String? ssid;
  final bool? _probeAnswers;
  final bool probeThrows;

  int probeCalls = 0;
  String? lastProbeIp;
  Duration? lastProbeTimeout;

  @override
  Future<List<ConnectivityResult>> getConnectivityTypes() async => types;

  @override
  Future<String?> getCurrentSsid() async => ssid;

  @override
  Future<bool> probeController(String ip, Duration timeout) async {
    probeCalls++;
    lastProbeIp = ip;
    lastProbeTimeout = timeout;
    if (probeThrows) throw const SocketExceptionStub();
    return _probeAnswers ?? false;
  }
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final homeHash = EncryptionService.hashSsid('HomeNet');
  const ip = '192.168.1.150';

  setUp(() => RoutingDiagnostics.resetForTest());

  Future<(ConnectivityStatus, ConnectivityCheckSnapshot)> run(
    _ScriptedConnectivity service, {
    String? controllerIp = ip,
  }) async {
    final status = await service
        .watchConnectivity(homeHash, homeControllerIp: controllerIp)
        .first;
    final snapshot = RoutingDiagnostics.instance.lastCheck!;
    return (status, snapshot);
  }

  test('no Wi-Fi reported + controller ANSWERS → local (the #114 fix)', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.mobile], probeAnswers: true);
    final (status, s) = await run(service);

    expect(status, ConnectivityStatus.local);
    expect(s.reason, ConnectivityCheckReason.wifiNotReportedControllerReachable);
    expect(s.wifiReported, isFalse);
    expect(s.controllerProbed, isTrue);
    expect(s.controllerReachable, isTrue);
    expect(s.probeMs, isNotNull);
    expect(service.probeCalls, 1);
    expect(service.lastProbeIp, ip);
  });

  test('no Wi-Fi reported + controller SILENT → remote (unchanged outcome)', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.mobile], probeAnswers: false);
    final (status, s) = await run(service);

    expect(status, ConnectivityStatus.remote);
    expect(s.reason, ConnectivityCheckReason.wifiNotReportedControllerUnreachable);
    expect(s.controllerProbed, isTrue);
    expect(s.controllerReachable, isFalse);
    expect(service.probeCalls, 1);
  });

  test('a throwing probe is treated as unreachable → remote', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.mobile],
        probeAnswers: true,
        probeThrows: true);
    final (status, s) = await run(service);

    expect(status, ConnectivityStatus.remote);
    expect(s.controllerReachable, isFalse);
  });

  test('[other] (VPN tunnel) + controller answers → local', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.other], probeAnswers: true);
    final (status, _) = await run(service);
    expect(status, ConnectivityStatus.local);
  });

  test('no controller IP known → old behaviour and old reason, no probe', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.mobile], probeAnswers: true);
    final (status, s) = await run(service, controllerIp: null);

    expect(status, ConnectivityStatus.remote);
    expect(s.reason, ConnectivityCheckReason.wifiNotReported);
    expect(s.controllerProbed, isFalse);
    expect(s.controllerReachable, isNull);
    expect(service.probeCalls, 0);
  });

  test('empty controller IP is treated as no IP', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.mobile], probeAnswers: true);
    final (status, _) = await run(service, controllerIp: '');
    expect(status, ConnectivityStatus.remote);
    expect(service.probeCalls, 0);
  });

  group('the probe is never consulted on the other branches', () {
    test('offline', () async {
      final service =
          _ScriptedConnectivity(types: const [], probeAnswers: true);
      final (status, _) = await run(service);
      expect(status, ConnectivityStatus.offline);
      expect(service.probeCalls, 0);
    });

    test('Wi-Fi reported + name matches → local', () async {
      final service = _ScriptedConnectivity(
          types: const [ConnectivityResult.wifi],
          ssid: 'HomeNet',
          probeAnswers: false);
      final (status, s) = await run(service);
      expect(status, ConnectivityStatus.local);
      expect(s.reason, ConnectivityCheckReason.ssidMatched);
      expect(service.probeCalls, 0);
    });

    test('Wi-Fi reported + name differs → remote', () async {
      final service = _ScriptedConnectivity(
          types: const [ConnectivityResult.wifi],
          ssid: 'Guest',
          probeAnswers: true);
      final (status, s) = await run(service);
      expect(status, ConnectivityStatus.remote);
      expect(s.reason, ConnectivityCheckReason.ssidMismatch);
      expect(service.probeCalls, 0,
          reason: 'a readable, mismatched name is already conclusive');
    });

    test('Android "<unknown ssid>" → remote, unchanged', () async {
      final service = _ScriptedConnectivity(
          types: const [ConnectivityResult.wifi],
          ssid: '<unknown ssid>',
          probeAnswers: true);
      final (status, s) = await run(service);
      expect(status, ConnectivityStatus.remote);
      expect(s.reason, ConnectivityCheckReason.ssidMismatch);
      expect(service.probeCalls, 0);
    });

    test('Wi-Fi reported + no fingerprint → local, unchanged', () async {
      final service = _ScriptedConnectivity(
          types: const [ConnectivityResult.wifi],
          ssid: 'HomeNet',
          probeAnswers: false);
      final status = await service
          .watchConnectivity(null, homeControllerIp: ip)
          .first;
      expect(status, ConnectivityStatus.local);
      expect(service.probeCalls, 0);
    });
  });

  test('the probe timeout is short enough not to stall a remote check', () async {
    final service = _ScriptedConnectivity(
        types: const [ConnectivityResult.mobile], probeAnswers: false);
    await run(service);
    expect(service.lastProbeTimeout, ConnectivityService.kControllerProbeTimeout);
    expect(ConnectivityService.kControllerProbeTimeout.inMilliseconds,
        lessThanOrEqualTo(1500),
        reason: 'runs on every 10s check while off Wi-Fi');
  });
}
