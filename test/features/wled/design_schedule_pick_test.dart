// Roofline slice 2 — the picker's verdict over the live providers
// (design_schedule_pick.dart): which repository counts as on the LAN, when
// the firmware is read, and that each gate reads the provider it should.
//
// NEW-BEHAVIOUR tests. The picker used to refuse every painted design for the
// schedule destination (slice 1 sentence); now it hands back an API-command
// body when the owner's gates pass and the gate's own sentence otherwise.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/wled/design_schedule_pick.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

class _Lan extends WledService {
  _Lan({this.ver = '0.15.4', this.arch = 'esp32', this.infoThrows = false})
      : super('http://mock');
  final String? ver;
  final String arch;
  final bool infoThrows;
  int infoReads = 0;

  @override
  Future<WledInfoResponse?> getInfo() async {
    infoReads++;
    if (infoThrows) throw StateError('unreachable');
    if (ver == null) return null;
    return WledInfoResponse(maxseg: 10, arch: arch, ver: ver!);
  }
}

/// Any non-LAN repository (a relay of either mode, the mock).
class _Relay implements WledRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const kThree = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];

final _now = DateTime(2026, 11, 5);

CustomDesign design({bool stamped = true}) => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: stamped
          ? const DesignLayoutStamp(
              controllerId: 'ctl-a', busLengths: [100, 100, 100])
          : null,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(
              channelId: id,
              channelName: 'Channel ${id + 1}',
              ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
              ]),
      ],
    );

ProviderContainer container({
  required WledRepository? repo,
  List<DeviceChannel> live = kThree,
  String? controllerId = 'ctl-a',
  bool remote = false,
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    deviceChannelsProvider.overrideWithValue(live),
    selectedControllerIdProvider.overrideWithValue(controllerId),
    isRemoteModeProvider.overrideWithValue(remote),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('LAN service, proven firmware, fitting layout → allowed with the body',
      () async {
    final lan = _Lan();
    final v = await designSchedulePickVerdict(container(repo: lan).read, design());
    expect(v.verdict, DesignScheduleVerdict.allowed);
    expect(v.body!['o'], isTrue);
    // The bounds group opens the body (A1); the paint entries carry no stop.
    expect((v.body!['seg'] as List).take(3).map((s) => s['stop']),
        [100, 200, 300]);
    expect(lan.infoReads, 1, reason: 'one firmware read, on the LAN');
  });

  // B4 — the model comes from the SAME read as the version.
  test('an unproven model (arch esp8266) is refused on one read', () async {
    final lan = _Lan(arch: 'esp8266');
    final v = await designSchedulePickVerdict(container(repo: lan).read, design());
    expect(v.verdict, DesignScheduleVerdict.archUnproven);
    expect(v.message, contains('not proven for roofline schedules'));
    expect(v.message, contains('esp8266'));
    expect(lan.infoReads, 1, reason: 'ver and arch come from one /json/info');
  });

  test('a missing arch is refused as an unproven model', () async {
    final v = await designSchedulePickVerdict(
        container(repo: _Lan(arch: '')).read, design());
    expect(v.verdict, DesignScheduleVerdict.archUnproven);
  });

  test('a relay repository is off the LAN: refused, no firmware read', () async {
    final v = await designSchedulePickVerdict(
        container(repo: _Relay(), live: const []).read, design());
    expect(v.verdict, DesignScheduleVerdict.offLan);
    expect(v.message, contains('home network'));
  });

  test('a LAN service while the app is in remote mode is off the LAN', () async {
    final lan = _Lan();
    final v = await designSchedulePickVerdict(
        container(repo: lan, remote: true).read, design());
    expect(v.verdict, DesignScheduleVerdict.offLan);
    expect(lan.infoReads, 0, reason: 'no device traffic for an off-LAN pick');
  });

  test('no repository at all is off the LAN', () async {
    final v = await designSchedulePickVerdict(
        container(repo: null, live: const []).read, design());
    expect(v.verdict, DesignScheduleVerdict.offLan);
  });

  test('an unstamped design is refused before any device read', () async {
    final lan = _Lan();
    final v = await designSchedulePickVerdict(
        container(repo: lan).read, design(stamped: false));
    expect(v.verdict, DesignScheduleVerdict.unstamped);
    expect(lan.infoReads, 0);
  });

  test('on the LAN with no bus data → layout unknown', () async {
    final v = await designSchedulePickVerdict(
        container(repo: _Lan(), live: const []).read, design());
    expect(v.verdict, DesignScheduleVerdict.layoutUnknown);
  });

  test('a firmware read that throws → unreadable; a null info → unreadable',
      () async {
    expect(
        (await designSchedulePickVerdict(
                container(repo: _Lan(infoThrows: true)).read, design()))
            .verdict,
        DesignScheduleVerdict.firmwareUnreadable);
    expect(
        (await designSchedulePickVerdict(
                container(repo: _Lan(ver: null)).read, design()))
            .verdict,
        DesignScheduleVerdict.firmwareUnreadable);
  });

  test('an unproven firmware version is refused by name', () async {
    final v = await designSchedulePickVerdict(
        container(repo: _Lan(ver: '0.15.1')).read, design());
    expect(v.verdict, DesignScheduleVerdict.firmwareUnproven);
    expect(v.message, contains('WLED 0.15.1'));
  });

  test('a different selected controller record is refused', () async {
    final v = await designSchedulePickVerdict(
        container(repo: _Lan(), controllerId: 'ctl-b').read, design());
    expect(v.verdict, DesignScheduleVerdict.layoutMismatch);
    expect(v.message, contains('different controller'));
  });

  test('the picker never refuses on the per-account count', () async {
    // The count is the save path's question (it knows the editing id).
    final v = await designSchedulePickVerdict(container(repo: _Lan()).read, design());
    expect(v.verdict, isNot(DesignScheduleVerdict.tooMany));
  });
}
