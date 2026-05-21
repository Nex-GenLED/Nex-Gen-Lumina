// Tests for the U1 participation gate (Bundle 3b.3b):
//
// effectiveChannelIdsProvider = {selector} ∩ {participation}.
// - "All Zones" (selector null) means all PARTICIPATING channels, not
//   all physical channels.
// - Non-participating channels are excluded even if the selector
//   explicitly names them.
// - Empty intersection → callers must skip-apply.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetParticipationCacheForTest();
  });

  ProviderContainer makeContainer({
    required List<DeviceChannel> deviceChannels,
    Set<int>? selectedIds,
  }) {
    final container = ProviderContainer(
      overrides: [
        deviceChannelsProvider.overrideWithValue(deviceChannels),
      ],
    );
    if (selectedIds != null) {
      container.read(selectedChannelIdsProvider.notifier).state = selectedIds;
    } else {
      container.read(selectedChannelIdsProvider.notifier).state = null;
    }
    return container;
  }

  const ch0 = DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2);
  const ch1 = DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 138, gpioPin: 14);

  group('effectiveChannelIdsProvider — U1 intersection', () {
    test(
        'Case 1: selector=null (All Zones), participation=[0] → effective [0] '
        '(All Zones means all PARTICIPATING)', () async {
      await saveLocalParticipatingChannels(const [0]);
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), equals([0]));
    });

    test(
        'Case 2: selector=null, participation=null (no pref) → all device '
        'channels (backward-safe)', () async {
      // No call to saveLocalParticipatingChannels — cache stays null.
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));
    });

    test(
        'Case 3: selector=[0,1] explicit, participation=[0] → effective [0] '
        '(intersection — participation is the outer gate)', () async {
      await saveLocalParticipatingChannels(const [0]);
      final container = makeContainer(
        deviceChannels: const [ch0, ch1],
        selectedIds: {0, 1},
      );
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), equals([0]));
    });

    test(
        'Case 4: selector=[1] (only ch1), participation=[0] → effective [] '
        '(empty intersection — caller must skip-apply)', () async {
      await saveLocalParticipatingChannels(const [0]);
      final container = makeContainer(
        deviceChannels: const [ch0, ch1],
        selectedIds: {1},
      );
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), isEmpty);
    });

    test(
        'Case 5: selector=[0,1], participation=[0,1] → [0,1] '
        '(participation does not narrow when it allows everything)', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      final container = makeContainer(
        deviceChannels: const [ch0, ch1],
        selectedIds: {0, 1},
      );
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));
    });

    test('Case 6: participation=[] (explicit none) → effective [] → skip',
        () async {
      await saveLocalParticipatingChannels(const []);
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), isEmpty);
    });

    test('Case 7: device has 3 channels, participation=[0,2] → effective [0,2]',
        () async {
      const ch2 = DeviceChannel(id: 2, name: 'Channel 3', start: 138, stop: 200, gpioPin: 5);
      await saveLocalParticipatingChannels(const [0, 2]);
      final container = makeContainer(deviceChannels: const [ch0, ch1, ch2]);
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 2]));
    });

    test(
        'Case 8: device has no channels → effective [] regardless of selector '
        'or participation (no hardware)', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      final container = makeContainer(deviceChannels: const []);
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), isEmpty);
    });

    test('reactivity: saveLocalParticipatingChannels rebuilds the provider',
        () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));

      // Change participation; provider must rebuild.
      await saveLocalParticipatingChannels(const [0]);
      expect(container.read(effectiveChannelIdsProvider), equals([0]));

      // Clear participation; provider goes back to all device channels.
      await saveLocalParticipatingChannels(null);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));
    });
  });

  group('participatingChannelIdsProvider — sync mirror of the cache', () {
    test('returns null when cache is cold (no save, no load)', () {
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      expect(container.read(participatingChannelIdsProvider), isNull);
    });

    test('returns the cached list after save', () async {
      await saveLocalParticipatingChannels(const [1]);
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      expect(container.read(participatingChannelIdsProvider), equals([1]));
    });

    test('returns [] when participation explicitly empty (distinct from null)',
        () async {
      await saveLocalParticipatingChannels(const []);
      final container = makeContainer(deviceChannels: const [ch0, ch1]);
      addTearDown(container.dispose);
      final p = container.read(participatingChannelIdsProvider);
      expect(p, isNotNull);
      expect(p, isEmpty);
    });
  });
}
