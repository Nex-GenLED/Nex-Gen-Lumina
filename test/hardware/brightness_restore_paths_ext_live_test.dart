// LIVE HARDWARE TEST — bench extension to brightness_restore_live_test.dart
// (T27–T30), covering the two doors that file does not: FAVORITES APPLY and
// SCHEDULE SYNC. Same discipline: capture prior state, drive the controller to
// a DIFFERENT live brightness and read it back (the "before"), apply, read the
// device's `bri` from /json/state (the "after"), restore at teardown.
//
//   flutter test test/hardware/brightness_restore_paths_ext_live_test.dart \
//     --dart-define=RUN_HW=true
//
// WRITES NO PRESET AND NO /json/cfg. The bench controller's presets.json was
// found with on-device flash corruption on 2026-09-21 (raw 0xFF bytes, slot 41
// undeserializable), so the schedule door is proven in two halves instead of
// one stored-preset round trip:
//   T32 — the APP half: the exact body syncAll psaves, applied live (a psave
//         applies its inline state live on this firmware), WITHOUT `psave`.
//   T33 — the FIRMWARE half: an EXISTING stored preset fires at ITS stored
//         `bri`, not the live one. A preset load is a flash READ.
// What stays unproven here: that `psave`+`ib:true` persists the inline `bri`.
// That leg is not touched by this branch (schedule_sync.dart is unchanged).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];
const _editorChannels = [
  PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
  PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
];

const _red = Color(0xFFE31837);
const _gold = Color(0xFFFFB81C);
const _white = Color(0xFFFFFFFF);

const int kAnimatedBri = 96;
const int kLiveBri = 60;

/// Existing stored presets on the bench controller and the `bri` each holds
/// (read from /presets.json 2026-09-21). Two distinct values, both different
/// from kLiveBri, kAnimatedBri and the model default 200.
const Map<int, int> kStoredPresetBri = {5: 153, 3: 51};

EditablePattern _chiefs(int fx, int brightness) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [_red, _gold],
      effectId: fx,
      speed: 140,
      intensity: 128,
    ).copyWith(actionColors: const [_red, _gold, _white], brightness: brightness);

CustomDesign _throughFirestore(CustomDesign d) => CustomDesign.fromFirestoreData(
    'probe', UserService.sanitizeForFirestore(d.toFirestore()));

CustomDesign _animated() => _throughFirestore(customDesignFromEditablePattern(
    pattern: _chiefs(15, kAnimatedBri),
    name: 'zz probe Animated',
    ownerId: 'PROBE',
    channels: _editorChannels));

/// The body `ScheduleSyncService.syncAll` psaves for a pattern schedule —
/// schedule_sync.dart:1459–1473 at 7984d5e, reproduced because it is inline
/// there. [wledPayload] is what the schedule picker stored on the ScheduleItem.
Map<String, dynamic> _schedulePresetBody(Map<String, dynamic> wledPayload) {
  final scoped =
      ScheduleSyncService.scopePatternPayload(wledPayload, null, channels: null);
  return <String, dynamic>{
    ...scoped,
    'on': true,
    'bri': (scoped['bri'] as num?)?.toInt() ?? 255,
    'ib': true,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!kRunHw) return;
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    if (!kRunHw) return;
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
    final after = await svc.getState();
    // ignore: avoid_print
    print('HW restored: on=${after?['on']} bri=${after?['bri']} ps=${after?['ps']}');
  });

  Future<Map<String, dynamic>> deviceState() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return (await svc.getState())!;
  }

  Future<int> deviceBri() async => ((await deviceState())['bri'] as num).toInt();

  Future<void> setLive({bool on = true}) async {
    expect(await svc.applyJson({'on': on, 'bri': kLiveBri}), isTrue);
    final s = await deviceState();
    expect(s['bri'], kLiveBri, reason: 'the "before" must be real');
    expect(s['on'], on, reason: 'the "before" must be real');
  }

  /// The dashboard favorites grid's apply (wled_dashboard_page.dart:1337–1344):
  /// stored doc → decode → applyChannelFilter → applyJson.
  Future<void> applyFavoriteDoc(Map<String, dynamic> doc) async {
    var payload = decodeFavoritePayload(doc[kFavoritePatternData]);
    payload = applyChannelFilter(payload, const [0, 1], _channels);
    expect(await svc.applyJson(payload), isTrue);
  }

  test('T31 — FAVORITES: a favorite saved from a design that states 96 comes '
      'back at 96; a favorite with no bri leaves the level alone', () async {
    final design = _animated();
    expect(design.appliedBrightness, kAnimatedBri);

    final withBri = buildFavoriteCreateData(
        patternName: 'zz probe fav', payload: design.toWledPayload());
    expect(withBri[kFavoritePatternData], isA<String>());
    await setLive();
    await applyFavoriteDoc(withBri);
    var got = await deviceBri();
    // ignore: avoid_print
    print('T31a favorite (states $kAnimatedBri): before bri=$kLiveBri → after bri=$got');
    expect(got, kAnimatedBri);

    // The pattern-category "Save to Favorites" shape: no top-level bri.
    final noBriPayload = Map<String, dynamic>.from(design.toWledPayload())
      ..remove('bri');
    final withoutBri = buildFavoriteCreateData(
        patternName: 'zz probe fav nobri', payload: noBriPayload);
    await setLive();
    await applyFavoriteDoc(withoutBri);
    got = await deviceBri();
    // ignore: avoid_print
    print('T31b favorite (no bri): before bri=$kLiveBri → after bri=$got');
    expect(got, kLiveBri);
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  test('T32 — SCHEDULE (app half): the body syncAll psaves carries the '
      "design's 96 and the device takes it — from lit AND from master-off",
      () async {
    final design = _animated();
    final body = _schedulePresetBody(design.toWledPayload());
    expect(body['bri'], kAnimatedBri, reason: 'psave body must carry the design bri');
    expect(body['on'], isTrue);
    expect(body['ib'], isTrue);
    expect(body.containsKey('psave'), isFalse, reason: 'this test writes no preset');

    for (final lit in [true, false]) {
      await setLive(on: lit);
      expect(await svc.applyJson(body), isTrue);
      final s = await deviceState();
      // ignore: avoid_print
      print('T32 schedule body from ${lit ? "LIT" : "MASTER-OFF"}: '
          'before on=$lit bri=$kLiveBri → after on=${s['on']} bri=${s['bri']}');
      expect(s['bri'], kAnimatedBri);
      expect(s['on'], isTrue);
    }
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  test('T33 — SCHEDULE (firmware half): an EXISTING stored preset fires at its '
      'STORED bri, not the live one (flash read only)', () async {
    for (final e in kStoredPresetBri.entries) {
      await setLive();
      expect(await svc.applyJson({'ps': e.key}), isTrue);
      final s = await deviceState();
      // ignore: avoid_print
      print('T33 fire stored preset ${e.key}: before bri=$kLiveBri → '
          'after on=${s['on']} bri=${s['bri']} ps=${s['ps']} (stored ${e.value})');
      expect(s['bri'], e.value);
    }
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  test('T34 — LATENT: an effect design that states NO brightness, if it were '
      'ever scheduled, fires at the schedule layer\'s `?? 255`', () async {
    final unstated = _throughFirestore(_animated().copyWith(brightnessStated: false));
    expect(unstated.isPositional, isFalse);
    expect(unstated.appliedBrightness, isNull);
    expect(unstated.toWledPayload().containsKey('bri'), isFalse);

    final body = _schedulePresetBody(unstated.toWledPayload());
    expect(body['bri'], 255);

    await setLive();
    expect(await svc.applyJson(body), isTrue);
    final got = await deviceBri();
    // ignore: avoid_print
    print('T34 unstated effect design via schedule body: before bri=$kLiveBri → '
        'after bri=$got (design stores ${unstated.brightness}, stated=false)');
    expect(got, 255);
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));
}
