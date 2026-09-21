// LIVE HARDWARE TEST — requires the bench controller at kBenchIp (2 channels:
// 0–128 and 128–290). NOT part of the normal suite: it performs real network
// I/O and changes what the lights show (never presets, never /json/cfg), then
// puts the look AND the brightness back. Without the define every test skips.
//
//   flutter test test/hardware/brightness_restore_live_test.dart \
//     --dart-define=RUN_HW=true
//
// Brightness restoration, one rule, every door. For each design: drive the
// controller to a DIFFERENT live brightness, read it back (the "before"),
// apply the design through one path, read the device's `bri` (the "after").
// Then the same again through a second path. `bri` is read from /json/state —
// the live-view frame buffer is pre-brightness and cannot show it.
//
// Each design crosses the Firestore codec in-process first (toFirestore →
// sanitizeForFirestore → fromFirestoreData), so what is applied is what a
// phone would have read back. The REAL Firestore leg for this document shape
// was proven with a client credential by save_to_my_designs_live_test (T25/
// T26); the only new key here is one bool.
//
// Numbering continues the audits' bench logs (T1–T26).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
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

/// The brightness each design was saved at, and the level the lights are
/// driven to before every apply. All three differ from each other and from the
/// model default (200), so no reading can be a coincidence.
const int kStaticBri = 180;
const int kAnimatedBri = 96;
const int kPaintedBri = 140;
const int kLiveBri = 60;

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository repo) => ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);

EditablePattern _chiefs(int fx, int brightness) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [_red, _gold],
      effectId: fx,
      speed: 140,
      intensity: 128,
    ).copyWith(actionColors: const [_red, _gold, _white], brightness: brightness);

/// What a phone reads back: the design through the Firestore codec.
CustomDesign _throughFirestore(CustomDesign d) => CustomDesign.fromFirestoreData(
    'probe', UserService.sanitizeForFirestore(d.toFirestore()));

/// A design the PAINT editor saves (no Pattern Editor tag) — the generalisation.
CustomDesign _painted({required int brightness, required bool? stated}) {
  final doc = PixelDesignDocument.blank(
          baseColor: const [10, 10, 12, 0], channelLengths: const {0: 128, 1: 162})
      .paint(0, [for (int i = 0; i < 128; i += 4) i], const [0, 60, 255, 0])
      .paint(1, [for (int i = 0; i < 162; i += 6) i], const [255, 40, 150, 0]);
  final now = DateTime(2026, 9, 21);
  return CustomDesign(
    id: '',
    name: 'zz probe painted',
    ownerId: 'PROBE',
    createdAt: now,
    updatedAt: now,
    perPixel: true,
    brightness: brightness,
    brightnessStated: stated,
    channels: [
      for (final e in doc.toLedColorGroups().entries)
        ChannelDesign(
            channelId: e.key,
            channelName: 'Channel ${e.key + 1}',
            colorGroups: e.value,
            ledCount: doc.channelLength(e.key)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test stubs HTTP with a 400
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!kRunHw) return;
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    if (!kRunHw) return;
    // Put the look back — segments AND master brightness (restoreAfterFindLed
    // re-sends the captured `bri`) — then the preset it came from, which also
    // restores the `ps` pointer. Presets/cfg were never written.
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
    final after = await svc.getState();
    // ignore: avoid_print
    print('HW restored: on=${after?['on']} bri=${after?['bri']} ps=${after?['ps']}');
  });

  Future<int> deviceBri() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return ((await svc.getState())!['bri'] as num).toInt();
  }

  /// Drive the lights to [kLiveBri] and PROVE it took — the "before".
  Future<void> setLive() async {
    expect(await svc.applyJson({'on': true, 'bri': kLiveBri}), isTrue);
    expect(await deviceBri(), kLiveBri, reason: 'the "before" must be real');
  }

  // Paths, each exactly what the named screen does.

  /// My Designs → Apply (applySavedDesign): positional → the spine; effect →
  /// channel-filtered toWledPayload through the applyJson chokepoint.
  Future<void> viaMyDesigns(CustomDesign d) async {
    if (d.isPositional) {
      expect(await applyPositionalDesignWith(_container(svc).read, d),
          DesignApplyResult.applied);
    } else {
      final payload = applyChannelFilter(d.toWledPayload(), const [0, 1], _channels);
      expect(await svc.applyJson(payload), isTrue);
    }
  }

  /// The EDITOR the design reopens in. Positional → the paint editor's Apply
  /// (spine, stating the edited design's brightness). Effect → the colourway
  /// tuner's design-edit live preview.
  Future<void> viaEditor(CustomDesign d) async {
    if (d.isPositional) {
      final r = await applyBaseAndSpansWith(_container(svc).read,
          baseRgbw: const [10, 10, 12, 0],
          spansByChannel: customDesignToSpans(d),
          brightness: d.appliedBrightness);
      expect(r, SpineWriteResult.ok);
      return;
    }
    final ch = d.channels.firstWhere((c) => c.included);
    // `_sendToWled` builds this with NO brightness (→ the catalog's 255)…
    var payload = buildSelectorPayload(SelectorState(
      effectId: ch.effectId,
      speed: ch.speed,
      intensity: ch.intensity,
      grouping: ch.grouping,
      spacing: ch.spacing,
      colors: [for (final g in ch.colorGroups.take(3)) g.color],
    ));
    expect(payload['bri'], 255);
    // …and design-edit mode now restates it from the design.
    payload = designEditPreviewPayload(payload, d);
    payload = applyChannelFilter(payload, const [0, 1], _channels);
    expect(await svc.applyJson(payload), isTrue);
  }

  /// Scenes (every saved design is also a scene; voice applies these).
  Future<void> viaScene(CustomDesign d) async {
    final c = _container(svc);
    expect(await c.read(applySceneProvider)(Scene.fromDesign(d)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400)); // debounce
    c.dispose();
  }

  Future<void> check(String t, String name, CustomDesign design, int? want,
      Map<String, Future<void> Function(CustomDesign)> paths) async {
    for (final e in paths.entries) {
      await setLive();
      await e.value(design);
      final got = await deviceBri();
      // ignore: avoid_print
      print('$t $name via ${e.key}: before bri=$kLiveBri → after bri=$got '
          '(design stores ${design.brightness}, '
          'stated=${design.brightnessStated}, applies=${design.appliedBrightness})');
      expect(got, want ?? kLiveBri, reason: '$name via ${e.key}');
    }
  }

  test('T27 — Static (Pattern Editor): restored from My Designs, the paint '
      'editor, and a scene', () async {
    final design = _throughFirestore(customDesignFromEditablePattern(
        pattern: _chiefs(0, kStaticBri),
        name: 'zz probe Static',
        ownerId: 'PROBE',
        channels: _editorChannels));
    expect(design.isPositional, isTrue);
    expect(design.brightnessStated, isTrue);
    await check('T27', 'Static', design, kStaticBri,
        {'My Designs': viaMyDesigns, 'editor': viaEditor, 'scene': viaScene});
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  test('T28 — Animated (Pattern Editor): restored from My Designs, the tuner '
      '(design-edit preview), and a scene', () async {
    final design = _throughFirestore(customDesignFromEditablePattern(
        pattern: _chiefs(15, kAnimatedBri),
        name: 'zz probe Animated',
        ownerId: 'PROBE',
        channels: _editorChannels));
    expect(design.isPositional, isFalse);
    await check('T28', 'Animated', design, kAnimatedBri,
        {'My Designs': viaMyDesigns, 'editor': viaEditor, 'scene': viaScene});
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  test('T29 — a PAINT EDITOR design that states its brightness is restored the '
      'same way (the generalisation: no Pattern Editor tag)', () async {
    final design = _throughFirestore(_painted(brightness: kPaintedBri, stated: true));
    expect(design.tags, isEmpty);
    await check('T29', 'Painted', design, kPaintedBri,
        {'My Designs': viaMyDesigns, 'editor': viaEditor, 'scene': viaScene});
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  test('T30 — a design that predates the field (painted, unchosen 200) leaves '
      'the brightness ALONE from every door — including the scene, which used '
      'to stamp 200', () async {
    final design = _throughFirestore(_painted(brightness: 200, stated: null));
    expect(design.brightnessStated, isNull);
    expect(design.appliedBrightness, isNull);
    await check('T30', 'Legacy painted', design, null,
        {'My Designs': viaMyDesigns, 'editor': viaEditor, 'scene': viaScene});
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));
}
