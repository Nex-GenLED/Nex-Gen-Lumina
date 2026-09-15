import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';

/// #114 routing diagnostics recorder: what it records, when it persists, and
/// that it can never fail a command.
void main() {
  ConnectivityCheckSnapshot check({required bool matched}) =>
      ConnectivityCheckSnapshot(
        checkedAt: DateTime.utc(2026, 9, 15, 14),
        reportedTypes: const ['wifi'],
        wifiReported: true,
        homeFingerprintConfigured: true,
        ssidReadable: true,
        ssidMatched: matched,
        outcome: matched ? 'local' : 'remote',
        reason: matched
            ? ConnectivityCheckReason.ssidMatched
            : ConnectivityCheckReason.ssidMismatch,
      );

  Future<bool> keep(List<Map<String, dynamic>> _, int __) async => true;

  test('currentPath follows the most recent command, notified after a microtask',
      () async {
    final d = RoutingDiagnostics(sink: keep);
    expect(d.currentPath.value, isNull);

    d.record(RoutePath.direct, '/json/state');
    expect(d.currentPath.value, isNull,
        reason: 'notify is deferred so a record made mid-build cannot rebuild');
    await Future<void>.delayed(Duration.zero);
    expect(d.currentPath.value, RoutePath.direct);

    d.record(RoutePath.bridge, 'getState');
    await Future<void>.delayed(Duration.zero);
    expect(d.currentPath.value, RoutePath.bridge);
  });

  test('each record carries the connectivity inputs in force and no SSID', () {
    final d = RoutingDiagnostics(
      sink: keep,
      clock: () => DateTime.utc(2026, 9, 15, 14, 0, 5),
    );
    d.recordConnectivityCheck(check(matched: false));
    d.record(RoutePath.bridge, 'applyJson');

    final json = d.recent.first.toJson();
    expect(json['at'], isA<Timestamp>());
    expect(json['path'], 'bridge');
    expect(json['command'], 'applyJson');
    expect(json['wifi_reported'], isTrue);
    expect(json['home_fingerprint_configured'], isTrue);
    expect(json['ssid_readable'], isTrue);
    expect(json['ssid_matched'], isFalse);
    expect(json['check_outcome'], 'remote');
    expect(json['check_reason'], 'ssid_mismatch');
    expect(json['reported_types'], ['wifi']);
    expect(json['check_age_ms'], 5000);
    expect(json.keys.where((k) => k == 'ssid' || k.contains('ip')), isEmpty);
  });

  test('a record made before any connectivity check still persists', () {
    final d = RoutingDiagnostics(sink: keep);
    d.record(RoutePath.direct, '/json/info');
    final json = d.recent.first.toJson();
    expect(json['path'], 'direct');
    expect(json['wifi_reported'], isNull);
    expect(json['check_age_ms'], isNull);
  });

  test('recent is newest-first and capped', () {
    final d = RoutingDiagnostics(sink: (_, __) async => false);
    for (var i = 0; i < RoutingDiagnostics.recentCapacity + 5; i++) {
      d.record(RoutePath.direct, '/cmd/$i');
    }
    expect(d.recent, hasLength(RoutingDiagnostics.recentCapacity));
    expect(d.recent.first.command, '/cmd/${RoutingDiagnostics.recentCapacity + 4}');
  });

  test('nothing is written before the interval; then one batch holds every record',
      () async {
    var now = DateTime.utc(2026, 9, 15, 14);
    final batches = <List<Map<String, dynamic>>>[];
    final d = RoutingDiagnostics(
      sink: (records, _) async {
        batches.add(records);
        return true;
      },
      clock: () => now,
    );

    d.record(RoutePath.direct, '/json/state');
    now = now.add(const Duration(seconds: 30));
    d.record(RoutePath.direct, '/json/state');
    await Future<void>.delayed(Duration.zero);
    expect(batches, isEmpty);

    now = now.add(const Duration(seconds: 31));
    d.record(RoutePath.bridge, 'getInfo');
    await Future<void>.delayed(Duration.zero);
    expect(batches, hasLength(1));
    expect(batches.single.map((r) => r['command']),
        ['/json/state', '/json/state', 'getInfo']);
    expect(d.pendingCount, 0);
  });

  test('a full batch is written without waiting for the interval', () async {
    final batches = <List<Map<String, dynamic>>>[];
    final d = RoutingDiagnostics(sink: (records, _) async {
      batches.add(records);
      return true;
    });
    for (var i = 0; i < RoutingDiagnostics.maxRecordsPerBatch; i++) {
      d.record(RoutePath.direct, '/json/state');
    }
    await Future<void>.delayed(Duration.zero);
    expect(batches, hasLength(1));
    expect(batches.single, hasLength(RoutingDiagnostics.maxRecordsPerBatch));
  });

  test('a refused or throwing write keeps the records for the next flush', () async {
    var mode = 'refuse';
    final batches = <List<Map<String, dynamic>>>[];
    final d = RoutingDiagnostics(sink: (records, _) async {
      if (mode == 'refuse') return false;
      if (mode == 'throw') throw StateError('offline');
      batches.add(records);
      return true;
    });

    d.record(RoutePath.direct, '/a');
    await d.flush();
    expect(d.pendingCount, 1);

    mode = 'throw';
    d.record(RoutePath.direct, '/b');
    await d.flush();
    expect(d.pendingCount, 2);

    mode = 'write';
    await d.flush();
    expect(batches.single.map((r) => r['command']), ['/a', '/b']);
    expect(d.pendingCount, 0);
  });

  test('the buffer is capped while writes fail, and drops are reported', () async {
    var accept = false;
    int? reportedDropped;
    final d = RoutingDiagnostics(sink: (records, dropped) async {
      if (!accept) return false;
      reportedDropped = dropped;
      return true;
    });
    for (var i = 0; i < RoutingDiagnostics.maxPending + 7; i++) {
      d.record(RoutePath.direct, '/json/state');
    }
    await Future<void>.delayed(Duration.zero);
    expect(d.pendingCount, RoutingDiagnostics.maxPending);

    accept = true;
    await d.flush();
    expect(reportedDropped, 7);
  });

  test('record never throws, even if the sink is broken', () {
    final d = RoutingDiagnostics(sink: (_, __) => throw StateError('boom'));
    for (var i = 0; i < RoutingDiagnostics.maxRecordsPerBatch + 1; i++) {
      d.record(RoutePath.bridge, 'getState');
    }
  });

  test('sanitizeSsidFailureReason keeps only the leading code', () {
    expect(sanitizeSsidFailureReason(null), isNull);
    expect(sanitizeSsidFailureReason(''), isNull);
    expect(sanitizeSsidFailureReason('getwifiname_null'), 'getwifiname_null');
    expect(
      sanitizeSsidFailureReason('corelocation_warmup_failed:current_position:timeout'),
      'corelocation_warmup_failed',
    );
    expect(
      sanitizeSsidFailureReason('getwifiname_exception:PlatformException(x)'),
      'getwifiname_exception',
    );
  });
}
