// Audit-2 S15-S17: the voice handlers (_handleWarmWhite / _handleBrightWhite /
// _handleFestive) used to ignore applyToDevice's bool result and always say
// "✓ Applying ..." — even when the device write failed. applyToDevice returns
// false (does NOT throw) on failure, so a try/catch never caught it.
//
// These tests drive the REAL WledNotifier with a fake repository whose
// applyJson returns false, so applyToDevice → applyPayloadWithLabel returns
// false at the chokepoint. The handler must then surface a failure string and
// must NOT persist an active-preset label.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/voice/dashboard_voice_control.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWledRepository implements WledRepository {
  /// Geometry (`start`/`stop`/`rev`/`mi`) is the PROVISIONING door — a separate
  /// method so `applyJson` can strip geometry unconditionally. This fake does
  /// not exercise it; `false` matches the interface default ("this transport
  /// cannot provision").
  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;

  bool applyJsonShouldSucceed = true;
  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return applyJsonShouldSucceed;
  }

  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      applyJsonShouldSucceed;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
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
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

final _voiceHandlerProvider =
    Provider<VoiceCommandHandler>((ref) => VoiceCommandHandler(ref));

List<Override> _overrides(_FakeWledRepository repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      userSyncStatusProvider.overrideWith((ref) => const UserSyncStatus()),
      // Non-empty effective channels so applyToDevice's U1 gate passes and the
      // call reaches the applyJson chokepoint.
      effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetActivePresetLabelCacheForTest();
  });

  // (command, success-prefix) for the three fixed handlers.
  const cases = <String, String>{
    'warm white': '✓ Applying warm white',
    'bright white': '✓ Applying bright white',
    'festive': '✓ Applying festive pattern',
  };

  cases.forEach((command, successMessage) {
    group('"$command"', () {
      test('FAILURE: no "✓" success, no label persisted', () async {
        final repo = _FakeWledRepository()..applyJsonShouldSucceed = false;
        final container = ProviderContainer(overrides: _overrides(repo));
        addTearDown(container.dispose);

        final result =
            await container.read(_voiceHandlerProvider).processCommand(command);

        expect(result, isNot(startsWith('✓')),
            reason: 'must not claim success on a failed device write');
        expect(result.toLowerCase(), contains("couldn't reach"));
        expect(container.read(activePresetLabelProvider), isNull,
            reason: 'no active-preset label may persist on failure');
      });

      test('SUCCESS: success string returned (path unchanged)', () async {
        final repo = _FakeWledRepository(); // succeeds
        final container = ProviderContainer(overrides: _overrides(repo));
        addTearDown(container.dispose);

        final result =
            await container.read(_voiceHandlerProvider).processCommand(command);

        expect(result, successMessage);
        expect(repo.applyJsonCalls, isNotEmpty,
            reason: 'success path still hits the device write');
      });
    });
  });
}
