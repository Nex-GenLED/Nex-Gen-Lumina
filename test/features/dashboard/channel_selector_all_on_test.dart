// Tests for the "All Channels On" recovery affordance (#1) in ChannelSelectorBar.
//
// From a partial-on state ("1 on, 2 off") the dashboard had no way to return
// every channel to ON, and a colour change only hit the lit channels because
// the selector was filtered to them. "All Channels On" clears the filter
// (so subsequent changes hit everything) AND powers every channel on through
// the existing applyToDevice path (empty seg template → on:true per channel).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWledRepository implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
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
      true;
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

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 188, gpioPin: 1),
];

const _oneChannel = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
];

List<Override> _overrides(
  _FakeWledRepository repo, {
  required List<DeviceChannel> channels,
}) =>
    [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      deviceChannelsProvider.overrideWithValue(channels),
      participatingChannelIdsProvider.overrideWithValue(null),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      'All Channels On: from 1-on/2-off → both channels on + filter cleared',
      (tester) async {
    final repo = _FakeWledRepository();
    final container =
        ProviderContainer(overrides: _overrides(repo, channels: _twoChannels));

    // Partial-on state: selector filtered to channel 0 ("1 on, 2 off").
    container.read(selectedChannelIdsProvider.notifier).state = {0};

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChannelSelectorBar())),
      ),
    );
    await tester.pump();

    // Expand the selector (header shows "1 of 2 Channels" when filtered).
    await tester.tap(find.text('1 of 2 Channels'));
    await tester.pump();

    // Tap the recovery affordance.
    await tester.tap(find.text('All Channels On'));
    await tester.pump(const Duration(milliseconds: 50));

    // Filter cleared → subsequent colour changes hit all channels.
    expect(container.read(selectedChannelIdsProvider), isNull);

    // Every channel powered on via the existing apply path.
    expect(repo.applyJsonCalls, hasLength(1));
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(2));
    expect(segs[0]['id'], 0);
    expect(segs[1]['id'], 1);
    expect(segs[0]['on'], isTrue);
    expect(segs[1]['on'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('single-channel install: selector + All-On hidden gracefully',
      (tester) async {
    final repo = _FakeWledRepository();
    final container =
        ProviderContainer(overrides: _overrides(repo, channels: _oneChannel));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChannelSelectorBar())),
      ),
    );
    await tester.pump();

    // The whole bar renders nothing on a 1-channel device — no affordance,
    // no-op, no clutter.
    expect(find.text('All Channels On'), findsNothing);
    expect(find.byType(ChannelSelectorBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
