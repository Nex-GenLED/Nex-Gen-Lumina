// Tests for the participation RE-ENTRY path (#95 item 1).
//
// Participation was a one-way door: every writer was a re-derivation from
// roofline geometry, so a channel the default policy excluded could not be put
// back from anywhere in the app, and the reconciler — which compares the cache
// against that same derivation — never saw the value as stale.
//
// The escape is an explicit user set (`saveParticipationOverride`) that the
// resolver returns verbatim and that OUTRANKS the derived cache. Its existence
// is also the provenance flag the reconciler keys off, so a later launch does
// not quietly undo the user's choice.
//
// The cases that matter, and why each one is here:
//   • the override wins over a cache that excludes the channel (the fix)
//   • the reconciler does NOT clear an override-sourced set (the re-exclusion
//     that would have rebuilt the door from the other side)
//   • the override still prunes to hardware that exists (a stated set must not
//     outrank physical reality)
//   • clearing restores derivation (not a one-way door in the other direction)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/channel_participation_resolver.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';
import 'package:nexgen_command/features/wled/participation_reconciler.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetParticipationCacheForTest();
    resetParticipationOverrideForTest();
    resetParticipationMemo();
  });

  const ch0 = DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2);
  const ch1 = DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 14);

  ProviderContainer makeContainer(List<DeviceChannel> deviceChannels) {
    final container = ProviderContainer(
      overrides: [deviceChannelsProvider.overrideWithValue(deviceChannels)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('persistence + normalisation', () {
    test('round-trips and sorts', () async {
      await saveParticipationOverride([1, 0]);
      resetParticipationOverrideForTest();
      expect(await getParticipationOverride(), equals([0, 1]));
    });

    test('empty is normalised to null — "nothing is in my shows" is not a '
        'state the UI may reach', () async {
      await saveParticipationOverride(const []);
      expect(peekParticipationOverride(), isNull);
      resetParticipationOverrideForTest();
      expect(await getParticipationOverride(), isNull);
    });

    test('null clears a previously written override', () async {
      await saveParticipationOverride([0, 1]);
      await saveParticipationOverride(null);
      resetParticipationOverrideForTest();
      expect(await getParticipationOverride(), isNull);
    });

    test('peek returns null before load, value after — never blocks on disk',
        () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'bg_participation_override': ['0', '1']},
      );
      expect(peekParticipationOverride(), isNull);
      await getParticipationOverride();
      expect(peekParticipationOverride(), equals([0, 1]));
    });
  });

  group('the fix: an override reopens a channel the derivation excluded', () {
    test('override outranks a derived cache that excludes ch1', () async {
      // The bench state: the resolver derived [0] and cached it.
      await saveLocalParticipatingChannels(const [0]);
      final container = makeContainer(const [ch0, ch1]);
      expect(container.read(effectiveChannelIdsProvider), equals([0]),
          reason: 'precondition — ch1 locked out');

      await saveParticipationOverride([0, 1]);
      expect(container.read(participatingChannelIdsProvider), equals([0, 1]));
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));
    });

    test('"All Zones" stops excluding it — the apply path is the same provider',
        () async {
      await saveLocalParticipatingChannels(const [0]);
      final container = makeContainer(const [ch0, ch1]);
      container.read(selectedChannelIdsProvider.notifier).state = null; // All
      await saveParticipationOverride([0, 1]);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));
    });

    test('clearing hands control back to the derived cache', () async {
      await saveLocalParticipatingChannels(const [0]);
      final container = makeContainer(const [ch0, ch1]);
      await saveParticipationOverride([0, 1]);
      expect(container.read(effectiveChannelIdsProvider), equals([0, 1]));

      await saveParticipationOverride(null);
      expect(container.read(effectiveChannelIdsProvider), equals([0]));
    });

    test('the selector still narrows WITHIN an override — include-back is not '
        'a bypass of the filter', () async {
      await saveParticipationOverride([0, 1]);
      final container = makeContainer(const [ch0, ch1]);
      container.read(selectedChannelIdsProvider.notifier).state = {1};
      expect(container.read(effectiveChannelIdsProvider), equals([1]));
    });
  });

  group('resolver honours the override at the call sites', () {
    // The exact bench geometry: ch0 traced+primary, ch1 traced but secondary.
    final benchSegments = [
      const RooflineSegment(
        id: 'ch0-primary',
        name: 'Front',
        channelIndex: 0,
        pixelCount: 128,
      ),
      const RooflineSegment(
        id: 'ch1-secondary',
        name: 'Bench ch1 (secondary)',
        channelIndex: 1,
        pixelCount: 10,
        isPrimary: false,
      ),
    ];

    test('default policy excludes ch1 (the state under repair)', () {
      expect(
        resolveParticipatingChannels(
          explicit: null,
          segments: benchSegments,
          allDeviceChannelIds: const [0, 1],
        ),
        equals([0]),
      );
    });

    test('an explicit set overrides the geometry verbatim', () {
      expect(
        resolveParticipatingChannels(
          explicit: const [0, 1],
          segments: benchSegments,
          allDeviceChannelIds: const [0, 1],
        ),
        equals([0, 1]),
      );
    });
  });

  group('reconciler provenance — an override is not "stale"', () {
    setUp(resetParticipationReconcilerForTest);

    test('pruneOverrideToDevice keeps channels the device still reports', () {
      expect(
        pruneOverrideToDevice(override: const [0, 1], deviceIds: const [0, 1]),
        equals([0, 1]),
      );
    });

    test('prunes a channel the device no longer reports', () {
      expect(
        pruneOverrideToDevice(override: const [0, 1, 5], deviceIds: const [0, 1]),
        equals([0, 1]),
      );
    });

    test('returns null when nothing survives — drop the override rather than '
        'strand the user with an invisible empty set', () {
      expect(
        pruneOverrideToDevice(override: const [7], deviceIds: const [0, 1]),
        isNull,
      );
    });

    test('never prunes against an unloaded device list', () {
      expect(
        pruneOverrideToDevice(override: const [0, 1], deviceIds: const []),
        equals([0, 1]),
      );
    });

    test('the staleness predicate is unchanged for DERIVED caches', () {
      // Regression guard: this is the comparison that must keep working, and
      // that must NOT be applied to an override.
      expect(
        isParticipationCacheStale(
          cached: const [0],
          deviceIds: const [0, 1],
          segments: const [],
        ),
        isTrue,
        reason: 'untraced install → all channels; cached [0] is stale',
      );
      expect(
        isParticipationCacheStale(
          cached: const [0, 1],
          deviceIds: const [0, 1],
          segments: const [],
        ),
        isFalse,
      );
    });
  });

  group('denormalizer provenance + explicit-source exemption', () {
    test('the published doc records whether the set was stated or derived', () {
      final derived = buildParticipationDoc(
        resolved: const [0],
        deviceChannelIds: const [0, 1],
        source: 'healer',
      );
      expect(derived[kParticipatingChannelsExplicitField], isFalse);

      final stated = buildParticipationDoc(
        resolved: const [0, 1],
        deviceChannelIds: const [0, 1],
        source: 'healer',
        explicitOverride: true,
      );
      expect(stated[kParticipatingChannelsExplicitField], isTrue);
    });

    test('a DERIVED set is still suppressed when the device shape is unknown',
        () {
      final facts = prepareParticipationFacts(
        controllerId: 'c1',
        resolved: const [],
        deviceChannelIds: const [],
        source: 'game_day',
      );
      expect(facts.fields, isEmpty);
    });

    test('an EXPLICIT set publishes even with an unknown device shape — it '
        'never consumed the bus list', () {
      final facts = prepareParticipationFacts(
        controllerId: 'c1',
        resolved: const [0, 1],
        deviceChannelIds: const [],
        source: 'game_day',
        explicitOverride: true,
      );
      expect(facts.fields[kParticipatingChannelsField], equals([0, 1]));
      expect(facts.fields[kParticipatingChannelsExplicitField], isTrue);
    });
  });
}
