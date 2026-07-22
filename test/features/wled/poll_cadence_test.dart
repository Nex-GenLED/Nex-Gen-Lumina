import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configurable fake repo: counts getState calls, can block (to test the
/// in-flight guard) or return a scripted result (to drive failure/success).
class _PollFakeRepo implements WledRepository {
  int getStateCalls = 0;
  Completer<Map<String, dynamic>?>? blockOn;
  Map<String, dynamic>? Function()? nextResult;

  @override
  Future<Map<String, dynamic>?> getState() async {
    getStateCalls++;
    if (blockOn != null) return blockOn!.future;
    return nextResult?.call();
  }

  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  void reset() {}
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender(
          {List<String> targets = const [], int ddpPort = 4048}) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig(
          {required int segmentId, int? start, int? stop}) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset(
          {required int presetId,
          required Map<String, dynamic> state,
          String? presetName}) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
}

ProviderContainer _container(_PollFakeRepo repo, {required bool remote}) {
  return ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    isRemoteModeProvider.overrideWithValue(remote),
    // Pin connectivity so _startPolling doesn't subscribe to a real platform
    // stream during the test.
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(
          remote ? ConnectivityStatus.remote : ConnectivityStatus.local),
    ),
  ]);
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetActivePresetLabelCacheForTest();
  });

  group('PollCadencePolicy (pure)', () {
    const threshold = 3;
    Duration interval({
      required bool isRemote,
      bool bg = false,
      int fails = 0,
    }) =>
        PollCadencePolicy.intervalFor(
          isRemote: isRemote,
          backgrounded: bg,
          consecutiveFailures: fails,
          downgradeThreshold: threshold,
        );

    test('base cadences: remote 10s, local 1.5s', () {
      expect(interval(isRemote: true), PollCadencePolicy.remoteBase);
      expect(interval(isRemote: false), PollCadencePolicy.localBase);
    });

    test('idle/background drops cadence drastically', () {
      expect(interval(isRemote: true, bg: true), PollCadencePolicy.remoteBackground);
      expect(interval(isRemote: false, bg: true), PollCadencePolicy.localBackground);
      expect(PollCadencePolicy.remoteBackground.inSeconds,
          greaterThan(PollCadencePolicy.remoteBase.inSeconds));
    });

    test('no failure backoff until the offline threshold is reached', () {
      // The offline indicator must still trip on time → first N failures stay
      // at base cadence.
      expect(interval(isRemote: true, fails: 1), PollCadencePolicy.remoteBase);
      expect(interval(isRemote: true, fails: 2), PollCadencePolicy.remoteBase);
      // At threshold, backoff begins.
      expect(interval(isRemote: true, fails: 3).inSeconds,
          greaterThan(PollCadencePolicy.remoteBase.inSeconds));
    });

    test('failure backoff is exponential and capped', () {
      final f3 = interval(isRemote: true, fails: 3); // 10*2
      final f4 = interval(isRemote: true, fails: 4); // 10*4
      final f5 = interval(isRemote: true, fails: 5); // 10*8
      expect(f3, const Duration(seconds: 20));
      expect(f4, const Duration(seconds: 40));
      expect(f5, const Duration(seconds: 80));
      // Far past threshold → capped, never grows unbounded.
      expect(interval(isRemote: true, fails: 50), PollCadencePolicy.maxBackoff);
    });

    test('a success (fails=0) resets to base cadence', () {
      expect(interval(isRemote: true, fails: 0), PollCadencePolicy.remoteBase);
    });

    test('local mode never applies failure backoff', () {
      expect(interval(isRemote: false, fails: 10), PollCadencePolicy.localBase);
    });
  });

  group('WledNotifier in-flight guard', () {
    test('a second poll is not enqueued while one is still pending', () async {
      final repo = _PollFakeRepo()..blockOn = Completer<Map<String, dynamic>?>();
      final container = _container(repo, remote: true);
      addTearDown(container.dispose);

      // Reading the notifier runs build() → cold-start _pollOnce(), whose
      // getState() blocks → _polling stays true.
      final notifier = container.read(wledStateProvider.notifier);
      await _settle();
      expect(repo.getStateCalls, 1);
      expect(notifier.debugIsPolling, isTrue);

      // A concurrent poll while one is in-flight must be a no-op (no second
      // getState) — this is the pile-up guard that protects the bridge queue.
      await notifier.debugPollOnce();
      await notifier.debugRunPollTick();
      expect(repo.getStateCalls, 1, reason: 'in-flight guard blocked re-entry');

      // Release the blocked call so the notifier settles cleanly.
      repo.blockOn!.complete(null);
      await _settle();
      expect(notifier.debugIsPolling, isFalse);
    });
  });

  group('WledNotifier failure backoff + offline indicator', () {
    test('offline trips at 3 failures, interval backs off, success resets all',
        () async {
      final repo = _PollFakeRepo()..nextResult = () => null; // always timeout
      final container = _container(repo, remote: true);
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      await _settle(); // let the cold-start _pollOnce (null) settle

      // Two failures: not offline yet, still base cadence (indicator on time).
      await notifier.debugRunPollTick();
      await notifier.debugRunPollTick();
      expect(notifier.debugConsecutiveFailures, 2);
      expect(container.read(bridgeReachableProvider), isNot(false));
      expect(notifier.debugNextPollInterval(), PollCadencePolicy.remoteBase,
          reason: 'no backoff before the offline threshold');

      // Third failure: offline indicator fires AND cadence backs off.
      await notifier.debugRunPollTick();
      expect(notifier.debugConsecutiveFailures, 3);
      expect(container.read(bridgeReachableProvider), false,
          reason: 'offline still trips at the 3-failure threshold under backoff');
      expect(notifier.debugNextPollInterval().inSeconds,
          greaterThan(PollCadencePolicy.remoteBase.inSeconds),
          reason: 'stop hammering a dead bridge');

      // A successful poll resets the counter, clears offline, and restores
      // the fast base cadence.
      repo.nextResult = () => <String, dynamic>{
            'on': true,
            'bri': 100,
            'ps': 0,
            'seg': [
              {'id': 0, 'fx': 0, 'sx': 128, 'ix': 128}
            ],
          };
      await notifier.debugRunPollTick();
      await _settle();
      expect(notifier.debugConsecutiveFailures, 0);
      expect(container.read(bridgeReachableProvider), true);
      expect(notifier.debugNextPollInterval(), PollCadencePolicy.remoteBase);
    });
  });

  group('WledNotifier idle backoff wiring', () {
    test('backgrounded notifier reports the background interval', () async {
      final repo = _PollFakeRepo()..nextResult = () => null;
      final container = _container(repo, remote: true);
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);
      await _settle();
      expect(notifier.debugNextPollInterval(), PollCadencePolicy.remoteBase);

      notifier.debugBackgrounded = true;
      expect(notifier.debugNextPollInterval(), PollCadencePolicy.remoteBackground,
          reason: 'a backgrounded app polls far less often');
    });
  });
}
