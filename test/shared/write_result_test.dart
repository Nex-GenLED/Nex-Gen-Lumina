// P3/P4 — write-and-report: WriteResult, guardWrite, and the notifier's
// runAndReport.
//
// "Saved", "Applied", "Synced": the message must be chosen from what the write
// RETURNED. These lock the one helper every package adopts for that.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/recording_wled_repository.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];

Future<ProviderContainer> _container(WledRepository? repo,
    {List<DeviceChannel> channels = _channels}) async {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(channels),
    deviceHardwareConfigProvider.overrideWith((ref) async => null),
    participatingChannelIdsProvider.overrideWithValue(null),
  ]);
  addTearDown(c.dispose);
  c.read(selectedDeviceIpProvider.notifier).state = '192.0.2.10';
  await c.read(wledConnectivityStatusProvider.future);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('WriteResult', () {
    test('success carries the success copy', () {
      const r = WriteResult.success(message: 'Saved');
      expect(r.ok, isTrue);
      expect(r.failed, isFalse);
      expect(r.failure, isNull);
      expect(r.message, 'Saved');
      expect(r.reported, isFalse);
    });

    test('blocked means nothing was sent, and says why', () {
      const r = WriteResult.blocked('No channels are selected.');
      expect(r.ok, isFalse);
      expect(r.wasBlocked, isTrue);
      expect(r.message, 'No channels are selected.');
    });

    test('fromBool adapts the Future<bool> contract', () {
      expect(WriteResult.fromBool(true, onSuccess: 'Done').message, 'Done');
      final f = WriteResult.fromBool(false, onFailure: 'Not done');
      expect(f.ok, isFalse);
      expect(f.failure, WriteFailureKind.unreachable);
      expect(f.message, 'Not done');
    });

    test('copyWith keeps the cause', () {
      final cause = StateError('x');
      final r = WriteResult.failed(WriteFailureKind.refused, error: cause)
          .copyWith(message: 'Refused', reported: true);
      expect(r.failure, WriteFailureKind.refused);
      expect(r.error, same(cause));
      expect(r.message, 'Refused');
      expect(r.reported, isTrue);
    });
  });

  group('guardWrite', () {
    test('a write that throws becomes a failure', () async {
      final r = await guardWrite(
        () async => throw StateError('socket closed'),
        onFailure: "Couldn't save",
      );
      expect(r.ok, isFalse);
      expect(r.failure, WriteFailureKind.error);
      expect(r.message, "Couldn't save");
      expect(r.error, isA<StateError>());
    });

    test('the exception text never becomes the customer message', () async {
      final r = await guardWrite(() async => throw StateError('errno 11001'));
      expect(r.message, isNull);
    });

    test('a failure with its own reason keeps it', () async {
      final r = await guardWrite(
        () async => const WriteResult.blocked('Offline'),
        onFailure: "Couldn't save",
      );
      expect(r.message, 'Offline');
    });

    test('a failure with no reason gets the caller copy', () async {
      final r = await guardWrite(
        () async => const WriteResult.failed(WriteFailureKind.unreachable),
        onFailure: "Couldn't save",
      );
      expect(r.message, "Couldn't save");
    });

    test('onError classifies the throw', () async {
      final r = await guardWrite(
        () async => throw UnsupportedError('LAN only'),
        onError: (e) => e is UnsupportedError
            ? WriteFailureKind.unsupported
            : WriteFailureKind.error,
      );
      expect(r.failure, WriteFailureKind.unsupported);
    });
  });

  group('WledNotifier.runAndReport', () {
    test('success: returns the success copy and reports nothing', () async {
      final c = await _container(RecordingWledRepository());
      final r = await c.read(wledStateProvider.notifier).runAndReport(
            Future.value(const WriteResult.success()),
            onSuccess: 'Schedule saved',
            onFailure: "Couldn't save your schedule",
          );
      expect(r.ok, isTrue);
      expect(r.message, 'Schedule saved');
      expect(c.read(wledCommandFailureProvider), isNull);
    });

    test('failure: sets the shared failure state the dashboard renders',
        () async {
      final c = await _container(RecordingWledRepository());
      final r = await c.read(wledStateProvider.notifier).runAndReport(
            Future.value(
                const WriteResult.failed(WriteFailureKind.unreachable)),
            onSuccess: 'Schedule saved',
            onFailure: "Couldn't save your schedule",
          );
      expect(r.ok, isFalse);
      expect(r.reported, isTrue);
      expect(r.message, "Couldn't save your schedule");
      expect(c.read(wledCommandFailureProvider)?.message,
          "Couldn't save your schedule");
    });

    test("failure: the write's own reason wins over the generic copy",
        () async {
      final c = await _container(RecordingWledRepository());
      final r = await c.read(wledStateProvider.notifier).runAndReport(
            Future.value(const WriteResult.blocked('Your phone is offline.')),
            onFailure: "Couldn't save your schedule",
          );
      expect(r.message, 'Your phone is offline.');
      expect(c.read(wledCommandFailureProvider)?.message,
          'Your phone is offline.');
    });

    test('a write that throws is reported, not rethrown', () async {
      final c = await _container(RecordingWledRepository());
      final r = await c.read(wledStateProvider.notifier).runAndReport(
            Future<WriteResult>.error(StateError('permission-denied')),
            onFailure: "Couldn't leave the group",
          );
      expect(r.ok, isFalse);
      expect(r.failure, WriteFailureKind.error);
      expect(r.message, "Couldn't leave the group");
      expect(c.read(wledCommandFailureProvider)?.message,
          "Couldn't leave the group");
    });

    test('an already-reported failure is not shown twice', () async {
      final c = await _container(RecordingWledRepository(succeed: false));
      final n = c.read(wledStateProvider.notifier);
      final first = await n.setBrightness(40);
      expect(first.reported, isTrue);
      final shown = c.read(wledCommandFailureProvider);

      final second = await n.runAndReport(Future.value(first),
          onFailure: 'something else');
      expect(identical(c.read(wledCommandFailureProvider), shown), isTrue);
      expect(second.message, first.message);
    });

    test('two failures with the same copy both notify', () async {
      final c = await _container(RecordingWledRepository());
      final n = c.read(wledStateProvider.notifier);
      await n.runAndReport(
          Future.value(const WriteResult.failed(WriteFailureKind.unreachable)),
          onFailure: 'Same');
      final a = c.read(wledCommandFailureProvider);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await n.runAndReport(
          Future.value(const WriteResult.failed(WriteFailureKind.unreachable)),
          onFailure: 'Same');
      expect(identical(a, c.read(wledCommandFailureProvider)), isFalse);
    });
  });

  group('notifier writes return what happened', () {
    test('a write that lands is a success', () async {
      final repo = RecordingWledRepository();
      final c = await _container(repo);
      final n = c.read(wledStateProvider.notifier);

      expect((await n.togglePower(false)).ok, isTrue);
      expect((await n.setBrightness(120)).ok, isTrue);
      expect((await n.setSpeed(200)).ok, isTrue);
      expect((await n.setColor(const Color(0xFF00FF00))).ok, isTrue);
      expect((await n.setWarmWhite(90)).ok, isTrue);
      expect(repo.applied, hasLength(5));
      expect(c.read(wledCommandFailureProvider), isNull);
    });

    test('a write the controller does not take is a reported failure',
        () async {
      final c = await _container(RecordingWledRepository(succeed: false));
      final r = await c.read(wledStateProvider.notifier).setSpeed(200);
      expect(r.ok, isFalse);
      expect(r.failure, WriteFailureKind.unreachable);
      expect(r.reported, isTrue);
      expect(c.read(wledCommandFailureProvider)?.message, r.message);
    });

    test('per-channel power reports the same way', () async {
      final c = await _container(RecordingWledRepository(succeed: false));
      final r =
          await c.read(wledStateProvider.notifier).setChannelPower(1, false);
      expect(r.ok, isFalse);
      expect(r.reported, isTrue);
    });

    test('no controller: blocked, with a reason, and nothing sent', () async {
      final c = await _container(null);
      final r = await c.read(wledStateProvider.notifier).setBrightness(10);
      expect(r.wasBlocked, isTrue);
      expect(r.message, isNotEmpty);
    });

    test('applyToDeviceResult: a refused write is a failure, not a block',
        () async {
      final repo = RecordingWledRepository(succeed: false);
      final c = await _container(repo);
      final r = await c.read(wledStateProvider.notifier).applyToDeviceResult({
        'on': true,
        'seg': [
          {
            'fx': 28,
            'col': [
              [255, 0, 0, 0]
            ]
          }
        ],
      }, labelHint: 'Chase');
      expect(r.ok, isFalse);
      expect(r.wasBlocked, isFalse);
      expect(repo.applied, hasLength(1));
      // The plain apply does not put a snackbar up by itself.
      expect(r.reported, isFalse);
      expect(c.read(wledCommandFailureProvider), isNull);
    });
  });
}
