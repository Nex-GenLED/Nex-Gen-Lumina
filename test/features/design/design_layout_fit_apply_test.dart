// Roofline slice 1, item 2 — the apply spine REFUSES a stamped design whose
// stamp does not match the live buses, and refuses it off the LAN, with a
// plain message; an unstamped design and a fitting design apply as before.
//
// This file is the fail-before proof against the item-1 code (stamp present,
// no gate): on that code every case below applied the design — base write +
// paints — under an "Applied" result. It uses only the public API that
// existed at item 1 (DesignLayoutStamp, applyPositionalDesignDetailed,
// DesignApplyReport.ok/message) so it compiles there and fails there.
//
// Fixtures: one controller `ctl-a` with three buses of 100 (ids 0, 1, 2); the
// design stamped for exactly that; and the mismatch cases — bus count differs
// (two buses), one bus length differs (100 / 120 / 100), a bus re-provisioned
// on another controller (`ctl-b`, same three buses of 100), and off the LAN
// (no bus data, remote mode).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kThreeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];
const kTwoBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];
const kMiddleBusLonger = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 220, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 220, stop: 320, gpioPin: 12),
];

final _now = DateTime(2026, 11, 4);

/// A painted three-channel design, stamped (or not) for ctl-a × 3 × 100.
CustomDesign design({bool stamped = true}) => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: stamped
          ? const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100])
          : null,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
              ]),
      ],
    );

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _Repo implements WledRepository, PerPixelWriter {
  final json = <Map<String, dynamic>>[];
  final pixels = <int, List<PixelSpan>>{};
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel(
      {int segmentId = 0,
      required List<PixelSpan> spans,
      int chunkSize = kDefaultPixelChunkSize}) async {
    pixels[segmentId] = spans;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(WidgetRef, _Repo)> pump(
  WidgetTester tester, {
  required List<DeviceChannel> live,
  String? controllerId = 'ctl-a',
  bool remote = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _Repo();
  late WidgetRef ref;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(live),
      effectiveChannelIdsProvider.overrideWithValue([for (final c in live) c.id]),
      selectedControllerIdProvider.overrideWithValue(controllerId),
      isRemoteModeProvider.overrideWithValue(remote),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ],
    child: Consumer(builder: (c, r, _) {
      ref = r;
      return const SizedBox();
    }),
  ));
  return (ref, repo);
}

void main() {
  group('applies', () {
    testWidgets('stamp matches the live three buses of 100 on ctl-a → applied',
        (tester) async {
      final (ref, repo) = await pump(tester, live: kThreeBuses);
      final report = await applyPositionalDesignDetailed(ref.read, design());
      expect(report.ok, isTrue, reason: report.message);
      expect(repo.json, hasLength(1));
      expect(repo.pixels.keys.toSet(), {0, 1, 2});
    });

    testWidgets('an UNSTAMPED design is not gated — applied on any layout, as before',
        (tester) async {
      final (ref, repo) = await pump(tester, live: kTwoBuses, controllerId: 'ctl-b');
      final report = await applyPositionalDesignDetailed(ref.read, design(stamped: false));
      expect(report.ok, isTrue, reason: report.message);
      expect(repo.json, hasLength(1));
      expect(repo.pixels.keys.toSet(), {0, 1}, reason: 'census keeps it to the live ids');
    });

    testWidgets('no selected controller record → the lengths alone decide',
        (tester) async {
      final (ref, repo) = await pump(tester, live: kThreeBuses, controllerId: null);
      final report = await applyPositionalDesignDetailed(ref.read, design());
      expect(report.ok, isTrue, reason: report.message);
      expect(repo.json, hasLength(1));
    });
  });

  group('refused — nothing written, a plain message', () {
    Future<void> expectRefused(WidgetTester tester, _Repo repo, DesignApplyReport report,
        {required List<String> saying}) async {
      expect(report.ok, isFalse, reason: 'was applied on the item-1 code');
      expect(repo.json, isEmpty, reason: 'no base write');
      expect(repo.pixels, isEmpty, reason: 'no paint');
      expect(report.message, isNotNull);
      for (final s in saying) {
        expect(report.message, contains(s));
      }
      expect(report.message, contains('"Porch stripes"'), reason: 'names the design');
    }

    testWidgets('bus count differs: saved for 3, controller has 2', (tester) async {
      final (ref, repo) = await pump(tester, live: kTwoBuses);
      final report = await applyPositionalDesignDetailed(ref.read, design());
      await expectRefused(tester, repo, report,
          saying: ['3 channels', 'has 2 now', 'layout capture again', 'save it again']);
    });

    testWidgets('one bus length differs: channel 2 is 120, saved with 100',
        (tester) async {
      final (ref, repo) = await pump(tester, live: kMiddleBusLonger);
      final report = await applyPositionalDesignDetailed(ref.read, design());
      await expectRefused(tester, repo, report,
          saying: ['100 lights on channel 2', 'has 120 now', 'layout capture again']);
    });

    testWidgets('a bus re-provisioned on another controller (ctl-b, same lengths)',
        (tester) async {
      final (ref, repo) = await pump(tester, live: kThreeBuses, controllerId: 'ctl-b');
      final report = await applyPositionalDesignDetailed(ref.read, design());
      await expectRefused(tester, repo, report,
          saying: ['different controller', 'layout capture again']);
    });

    testWidgets('off the LAN: no bus data, remote mode → home-network message',
        (tester) async {
      final (ref, repo) = await pump(tester, live: const [], remote: true);
      final report = await applyPositionalDesignDetailed(ref.read, design());
      await expectRefused(tester, repo, report,
          saying: ['home network', 'home Wi-Fi']);
    });

    testWidgets('on the LAN with the layout not read yet → try again message, no write',
        (tester) async {
      final (ref, repo) = await pump(tester, live: const [], remote: false);
      final report = await applyPositionalDesignDetailed(ref.read, design());
      await expectRefused(tester, repo, report, saying: ['layout', 'Try again']);
    });
  });
}
