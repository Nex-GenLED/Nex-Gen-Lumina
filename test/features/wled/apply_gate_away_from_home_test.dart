// P2 — the apply gate away from home.
//
// The gate ("which channels should receive this?") read the hardware bus list
// alone, and the relay cannot read it. So away from home every favourite,
// pattern, design and Light Up Now stopped before sending — on a controller
// that was relaying power and brightness perfectly.
//
// Locked here:
//   • with a cached channel list, an away-from-home apply ISSUES the command;
//   • with no cached list, the list is fetched through the relay;
//   • with no list and no relay answer, the apply returns the REASON — it is
//     never silent;
//   • on the home network nothing changes, and the away-from-home sources are
//     not consulted at all.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/recording_wled_repository.dart';

const _liveChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];

Map<String, dynamic> _chase() => {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'fx': 28,
          'sx': 160,
          'ix': 128,
          'pal': 5,
          'col': [
            [255, 0, 0, 0],
            [0, 0, 255, 0],
          ],
        },
      ],
    };

class _Sources {
  int cachedReads = 0;
  int relayReads = 0;
}

Future<ProviderContainer> _container({
  required WledRepository? repo,
  required ConnectivityStatus network,
  List<DeviceChannel> live = const [],
  FutureOr<List<int>> Function()? cached,
  FutureOr<List<DeviceChannel>> Function()? relayed,
  _Sources? sources,
  String? selectedIp = '192.0.2.10',
}) async {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledConnectivityStatusProvider
        .overrideWith((ref) => Stream<ConnectivityStatus>.value(network)),
    deviceChannelsProvider.overrideWithValue(live),
    deviceHardwareConfigProvider.overrideWith((ref) async => null),
    participatingChannelIdsProvider.overrideWithValue(null),
    cachedChannelIdsProvider.overrideWith((ref) async {
      sources?.cachedReads++;
      return await (cached?.call() ?? const <int>[]);
    }),
    segmentDerivedChannelsProvider.overrideWith((ref) async {
      sources?.relayReads++;
      return await (relayed?.call() ?? const <DeviceChannel>[]);
    }),
  ]);
  addTearDown(c.dispose);
  c.read(selectedDeviceIpProvider.notifier).state = selectedIp;
  await c.read(wledConnectivityStatusProvider.future);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('away from home', () {
    test('with a cached channel list, the apply issues the command', () async {
      final repo = RecordingWledRepository();
      final sources = _Sources();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.remote,
        cached: () => [0, 1],
        sources: sources,
      );

      final result = await c
          .read(wledStateProvider.notifier)
          .applyToDeviceResult(_chase(), labelHint: 'Chase');

      expect(result.ok, isTrue);
      expect(repo.applied, hasLength(1));
      final segs = repo.applied.single['seg'] as List;
      expect([for (final s in segs) (s as Map)['id']], [0, 1]);
      expect(segs.every((s) => (s as Map)['fx'] == 28), isTrue);
      expect(segs.every((s) => (s as Map)['on'] == true), isTrue);
      // An apply states a look, never where the channel lies.
      for (final s in segs) {
        expect((s as Map).containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
      }
      expect(c.read(applyChannelCensusProvider).source,
          ApplyChannelSource.cached);
      expect(sources.relayReads, 0,
          reason: 'a cached list must not cost a relay command');
    });

    test('the first tap is not refused while the cached list is loading',
        () async {
      final repo = RecordingWledRepository();
      final gate = Completer<List<int>>();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.remote,
        cached: () => gate.future,
      );

      // Nothing has resolved yet: the plain gate is closed, and says why.
      expect(c.read(effectiveChannelIdsProvider), isEmpty);
      expect(c.read(applyBlockedReasonProvider)?.kind,
          ApplyBlock.channelsLoading);

      final pending = c
          .read(wledStateProvider.notifier)
          .applyToDeviceResult(_chase(), labelHint: 'Chase');
      gate.complete([0, 1]);

      expect((await pending).ok, isTrue);
      expect(repo.applied, hasLength(1));
    });

    test('the bool form issues the command too', () async {
      final repo = RecordingWledRepository();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.remote,
        cached: () => [0, 1],
      );

      expect(
        await c
            .read(wledStateProvider.notifier)
            .applyToDevice(_chase(), labelHint: 'Chase'),
        isTrue,
      );
      expect(repo.applied, hasLength(1));
    });

    test('with no cached list, the list is fetched through the relay',
        () async {
      final repo = RecordingWledRepository();
      final sources = _Sources();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.remote,
        relayed: () => deviceChannelsFromSegments([
          {'id': 0, 'start': 0, 'stop': 100, 'on': true},
          {'id': 1, 'start': 100, 'stop': 200, 'on': true},
        ]),
        sources: sources,
      );

      final result = await c
          .read(wledStateProvider.notifier)
          .applyToDeviceResult(_chase(), labelHint: 'Chase');

      expect(result.ok, isTrue);
      expect(sources.cachedReads, 1);
      expect(sources.relayReads, 1);
      expect(c.read(applyChannelCensusProvider).source,
          ApplyChannelSource.relay);
      final segs = repo.applied.single['seg'] as List;
      expect([for (final s in segs) (s as Map)['id']], [0, 1]);
      for (final s in segs) {
        expect((s as Map).containsKey('start'), isFalse,
            reason: 'relayed segment bounds must never be written back');
        expect(s.containsKey('stop'), isFalse);
      }
    });

    test('with no list and no relay answer, returns the reason — never silent',
        () async {
      final repo = RecordingWledRepository();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.remote,
      );

      final result = await c
          .read(wledStateProvider.notifier)
          .applyToDeviceResult(_chase(), labelHint: 'Chase');

      expect(result.ok, isFalse);
      expect(result.failure, WriteFailureKind.blocked);
      expect(result.message, isNotNull);
      expect(result.message, isNotEmpty);
      expect(repo.writeCount, 0, reason: 'a closed gate sends nothing');

      final reason = c.read(applyBlockedReasonProvider);
      expect(reason?.kind, ApplyBlock.homeNotAnswering);
      expect(result.message, reason?.message);
      expect(applyBlockedReason(c.read), reason?.message);
    });

    test('a relay that never answers is given up on, with the reason',
        () async {
      final repo = RecordingWledRepository();
      final never = Completer<List<DeviceChannel>>();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.remote,
        relayed: () => never.future,
      );

      final ids = await resolveEffectiveChannelIds(
        c.read,
        relayTimeout: const Duration(milliseconds: 40),
      );

      expect(ids, isEmpty);
      expect(c.read(applyBlockedReasonProvider)?.kind,
          ApplyBlock.channelsLoading);
      expect(applyBlockedReason(c.read), isNotEmpty);
      never.complete(const []);
    });

    test('the customer-facing reasons carry no ids, addresses or codes',
        () async {
      final c = await _container(
        repo: RecordingWledRepository(),
        network: ConnectivityStatus.remote,
      );
      await resolveEffectiveChannelIds(c.read);
      final message = applyBlockedReason(c.read)!;
      expect(message.contains('192.'), isFalse);
      expect(RegExp(r'\b(seg|cfg|json|null|uid|HTTP)\b').hasMatch(message),
          isFalse);
    });

    test('away with nothing to relay through: says remote access is not set up',
        () async {
      final c = await _container(
        repo: null,
        network: ConnectivityStatus.remote,
      );
      expect(c.read(applyBlockedReasonProvider)?.kind,
          ApplyBlock.remoteNotSetUp);
    });
  });

  group('every way the gate can be closed has its own reason', () {
    test('no controller', () async {
      final c = await _container(
        repo: null,
        network: ConnectivityStatus.local,
        selectedIp: null,
      );
      expect(
          c.read(applyBlockedReasonProvider)?.kind, ApplyBlock.noController);
    });

    test('offline', () async {
      final c = await _container(
        repo: null,
        network: ConnectivityStatus.offline,
      );
      expect(c.read(applyBlockedReasonProvider)?.kind, ApplyBlock.offline);
    });

    test('home network, controller unreadable', () async {
      final c = await _container(
        repo: RecordingWledRepository(),
        network: ConnectivityStatus.local,
      );
      await resolveEffectiveChannelIds(c.read);
      expect(c.read(applyBlockedReasonProvider)?.kind,
          ApplyBlock.controllerUnreadable);
    });

    test('a channel selection that matches nothing', () async {
      final c = await _container(
        repo: RecordingWledRepository(),
        network: ConnectivityStatus.local,
        live: _liveChannels,
      );
      c.read(selectedChannelIdsProvider.notifier).state = {7};
      expect(c.read(applyBlockedReasonProvider)?.kind,
          ApplyBlock.nothingSelected);
    });

    test('an open gate has no reason', () async {
      final c = await _container(
        repo: RecordingWledRepository(),
        network: ConnectivityStatus.local,
        live: _liveChannels,
      );
      expect(c.read(applyBlockedReasonProvider), isNull);
      expect(applyBlockedReason(c.read), isNull);
    });
  });

  group('on the home network', () {
    test('the hardware list is the only source consulted', () async {
      final repo = RecordingWledRepository();
      final sources = _Sources();
      final c = await _container(
        repo: repo,
        network: ConnectivityStatus.local,
        live: _liveChannels,
        cached: () => [0, 1, 2, 3],
        sources: sources,
      );

      expect(c.read(effectiveChannelIdsProvider), [0, 1]);
      expect(
          c.read(applyChannelCensusProvider).source, ApplyChannelSource.device);
      await c
          .read(wledStateProvider.notifier)
          .applyToDeviceResult(_chase(), labelHint: 'Chase');

      expect(sources.cachedReads, 0);
      expect(sources.relayReads, 0);
      expect((repo.applied.single['seg'] as List), hasLength(2));
    });

    test('a saved list never stands in for a controller that is right there',
        () async {
      final sources = _Sources();
      final c = await _container(
        repo: RecordingWledRepository(),
        network: ConnectivityStatus.local,
        cached: () => [0, 1],
        sources: sources,
      );

      await resolveEffectiveChannelIds(c.read);

      expect(c.read(effectiveChannelIdsProvider), isEmpty);
      expect(sources.cachedReads, 0);
      expect(sources.relayReads, 0);
    });
  });
}
