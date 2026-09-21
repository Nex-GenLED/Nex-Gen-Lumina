// Brightness restoration is ONE rule (decision of record 2026-09-21): a design
// that states a brightness comes back at that brightness — from every door,
// whatever the lights are at now, whichever screen saved it. A design that
// states none leaves the controller's brightness alone — also from every door.
//
// Before this, the same design came back at a different level depending on the
// button: the per-pixel spine restored brightness only for Pattern Editor
// designs, the effect payload always stated it, scene apply stamped it with a
// second write regardless, and the tuner's design-edit preview forced 255.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lengths = {0: 128, 1: 162};
final _now = DateTime(2026, 9, 21);

/// A painted (positional) design, built the way the paint editor builds it.
CustomDesign _painted({
  int brightness = 200,
  bool? stated,
  List<String> tags = const [],
}) {
  final doc = PixelDesignDocument.blank(
          baseColor: const [10, 10, 12, 0], channelLengths: _lengths)
      .paint(0, [10, 11, 12], const [255, 0, 0, 0])
      .paint(1, [0, 1, 2, 3], const [0, 60, 255, 0]);
  return CustomDesign(
    id: 'p1',
    name: 'Painted',
    ownerId: 'u',
    createdAt: _now,
    updatedAt: _now,
    perPixel: true,
    brightness: brightness,
    brightnessStated: stated,
    tags: tags,
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

/// An effect (animated) design — the shape Now Playing capture, the colour
/// editor and the Pattern Editor's animated modes all write.
CustomDesign _effect({int brightness = 200, bool? stated}) => CustomDesign(
      id: 'e1',
      name: 'Animated',
      ownerId: 'u',
      createdAt: _now,
      updatedAt: _now,
      brightness: brightness,
      brightnessStated: stated,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Main', effectId: 15, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 1, endLed: 1, color: [0, 255, 0, 0]),
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

  /// Payloads that are a bare master write — what `setBrightness` sends.
  List<Map<String, dynamic>> get brightnessOnlyWrites =>
      [for (final p in json) if (p.containsKey('bri') && !p.containsKey('seg')) p];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(Map<String, dynamic>.from(payload));
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

Future<(WidgetRef, _Repo)> _mount(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _Repo();
  late WidgetRef ref;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 128, gpioPin: 2),
        DeviceChannel(id: 1, name: 'Ch2', start: 128, stop: 290, gpioPin: 3),
      ]),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
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
  group('the rule — statesBrightness / appliedBrightness', () {
    test('a design that STATES a brightness restores it, whatever its shape or '
        'tags', () {
      expect(_painted(brightness: 90, stated: true).appliedBrightness, 90);
      expect(_effect(brightness: 90, stated: true).appliedBrightness, 90);
    });

    test('a design that states NONE leaves the controller alone, whatever its '
        'shape or tags', () {
      expect(_painted(stated: false).appliedBrightness, isNull);
      expect(_effect(stated: false).appliedBrightness, isNull);
      expect(
          _painted(stated: false, tags: const [kPatternEditorDesignTag])
              .appliedBrightness,
          isNull,
          reason: 'an explicit answer beats the legacy tag');
    });

    test('NOT RECORDED (every design saved before the field existed) goes by '
        'what each shape is known to hold — nothing is backfilled', () {
      expect(_effect(brightness: 128).appliedBrightness, 128,
          reason: 'effect designs always captured a real level and were always '
              'applied — unchanged');
      expect(
          _painted(brightness: 180, tags: const [kPatternEditorDesignTag])
              .appliedBrightness,
          180,
          reason: "this week's Pattern Editor Static fix — unchanged");
      expect(_painted().appliedBrightness, isNull,
          reason: 'a painted/AI design holds the default 200 nobody chose');
    });

    test('floored at 1 — a design states on:true, and WLED reads bri 0 as off',
        () {
      expect(_effect(brightness: 0, stated: true).appliedBrightness, 1);
      expect(_painted(brightness: 0, stated: true).appliedBrightness, 1);
    });
  });

  group('Firestore', () {
    test('the marker round-trips, and survives copyWith (rename, duplicate)', () {
      for (final stated in [true, false]) {
        final back = CustomDesign.fromFirestoreData(
            'x', _painted(brightness: 90, stated: stated).toFirestore());
        expect(back.brightnessStated, stated);
        expect(back.brightness, 90);
        expect(back.copyWith(name: 'Renamed').brightnessStated, stated);
      }
    });

    test('NOT RECORDED is never written — re-saving an older design records '
        'nothing it does not know', () {
      final data = _painted().toFirestore();
      expect(data.containsKey('brightness_stated'), isFalse);
      expect(data['brightness'], 200);
      expect(CustomDesign.fromFirestoreData('x', data).brightnessStated, isNull);
    });

    test('the ABSENT case: a document with no brightness states none — it is '
        'not handed the default 200 to apply', () {
      for (final base in [_effect(), _painted()]) {
        final data = base.toFirestore()..remove('brightness');
        final back = CustomDesign.fromFirestoreData('x', data);
        expect(back.brightnessStated, isFalse);
        expect(back.appliedBrightness, isNull);
        expect(back.toWledPayload().containsKey('bri'), isFalse);
        expect(back.brightness, 200, reason: 'display value only');
      }
    });

    test('a brightness that comes back as a double no longer throws', () {
      final data = _effect(brightness: 128).toFirestore()..['brightness'] = 128.0;
      expect(CustomDesign.fromFirestoreData('x', data).brightness, 128);
    });
  });

  group('toWledPayload — what scenes send, schedules store, the AI router applies',
      () {
    test('both shapes state bri exactly when the design does', () {
      for (final build in [_effect, _painted]) {
        final stated = build(brightness: 90, stated: true).toWledPayload();
        expect(stated['bri'], 90);
        expect(stated['on'], isTrue);
        final unstated = build(brightness: 90, stated: false).toWledPayload();
        expect(unstated.containsKey('bri'), isFalse);
        expect(unstated['on'], isTrue);
        expect(unstated['seg'], isNotEmpty);
      }
    });

    test('the positional payload no longer states the unchosen 200 — it used '
        'to, while the spine applying the SAME design did not', () {
      expect(_painted().toWledPayload().containsKey('bri'), isFalse);
    });

    test('a scene built from a design carries the design\'s rule', () {
      expect(Scene.fromDesign(_painted(brightness: 90, stated: true))
          .toWledPayload()['bri'], 90);
      expect(Scene.fromDesign(_painted()).toWledPayload().containsKey('bri'),
          isFalse);
    });
  });

  group('the per-pixel spine (My Designs, the editors, scenes)', () {
    testWidgets('a stated brightness rides in the SAME write as the base — for '
        'ANY painted design, not only a Pattern Editor one', (tester) async {
      final (ref, repo) = await _mount(tester);
      expect(
          await applyPositionalDesignWith(
              ref.read, _painted(brightness: 90, stated: true)),
          DesignApplyResult.applied);
      expect(repo.json, hasLength(1), reason: 'no extra request');
      expect(repo.json.single['bri'], 90);
      expect(repo.pixels.keys.toSet(), {0, 1});
    });

    testWidgets('a design that states none leaves bri off the wire',
        (tester) async {
      final (ref, repo) = await _mount(tester);
      await applyPositionalDesignWith(ref.read, _painted(stated: false));
      expect(repo.json.single.containsKey('bri'), isFalse);
    });
  });

  group('scene apply', () {
    testWidgets('a painted design that states NO brightness is no longer stamped '
        'with its unchosen 200 by a second write', (tester) async {
      final (ref, repo) = await _mount(tester);
      final ok = await ref.read(applySceneProvider)(Scene.fromDesign(_painted()));
      expect(ok, isTrue);
      await tester.pump(const Duration(milliseconds: 300)); // setBrightness debounce
      expect(repo.brightnessOnlyWrites, isEmpty,
          reason: 'was {bri: 200} — contradicting the spine, which had just '
              'deliberately left the brightness alone');
      expect(repo.json.every((p) => !p.containsKey('bri')), isTrue);
    });

    testWidgets('a painted design that STATES one gets exactly that level — in '
        'the base write, and never a different one after it', (tester) async {
      final (ref, repo) = await _mount(tester);
      final design = _painted(brightness: 90, stated: true);
      expect(await ref.read(applySceneProvider)(Scene.fromDesign(design)), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      final levels = {for (final p in repo.json) if (p.containsKey('bri')) p['bri']};
      expect(levels, {90});
      expect(repo.json.first['bri'], 90, reason: 'lands with the base');
    });
  });

  group('writers — every design type states its brightness at save time', () {
    test('liveBrightnessToStore: a level only when a controller is answering',
        () {
      expect(liveBrightnessToStore(connected: true, brightness: 128), 128);
      expect(liveBrightnessToStore(connected: true, brightness: 0), 1);
      expect(liveBrightnessToStore(connected: false, brightness: 128), isNull,
          reason: 'a stale/default number is not something the user saw');
    });

    test('Pattern Editor — Static and Animated both state the slider', () {
      const channels = [
        PatternEditorChannel(id: 0, name: 'Ch1', ledCount: 128),
        PatternEditorChannel(id: 1, name: 'Ch2', ledCount: 162),
      ];
      for (final fx in [0, 15]) {
        final design = customDesignFromEditablePattern(
          pattern: EditablePattern.fromGradientColors(
            id: 'card',
            name: 'Card',
            colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
            effectId: fx,
            speed: 140,
            intensity: 128,
          ).copyWith(brightness: 77),
          name: 'Card',
          ownerId: 'u',
          channels: channels,
        );
        expect(design.brightnessStated, isTrue);
        expect(design.appliedBrightness, 77);
        expect(design.isPositional, fx == 0);
      }
    });

    test('AI Design Studio — a save records the level the design was watched '
        'at; the in-memory Apply build (and an offline save) states none', () {
      final pattern = ComposedPattern(
        name: 'AI',
        description: 'd',
        wledPayload: const {},
        colorGroups: const [
          LedColorGroup(startLed: 0, endLed: 9, color: [255, 0, 0, 0]),
        ],
        totalPixels: 290,
        composedAt: _now,
      );
      final saved = customDesignFromComposedPattern(
          pattern: pattern, segments: const [], ownerId: 'u', liveBrightness: 64);
      expect(saved.brightnessStated, isTrue);
      expect(saved.appliedBrightness, 64);

      final unsaved = customDesignFromComposedPattern(
          pattern: pattern, segments: const [], ownerId: 'u');
      expect(unsaved.brightnessStated, isFalse);
      expect(unsaved.appliedBrightness, isNull,
          reason: "the studio's own Apply has never touched brightness");
      expect(unsaved.brightness, 200);
    });
  });

  group('colourway tuner — design-edit live preview', () {
    const catalog = <String, dynamic>{
      'on': true,
      'bri': 255,
      'seg': [
        {'fx': 15}
      ],
    };

    test('previews at the DESIGN\'S brightness, not the catalog\'s 255', () {
      final out =
          designEditPreviewPayload(catalog, _effect(brightness: 90, stated: true));
      expect(out['bri'], 90);
      expect(out['seg'], catalog['seg']);
      expect(out['on'], isTrue);
    });

    test('a design that states none previews with no bri at all', () {
      final out = designEditPreviewPayload(catalog, _effect(stated: false));
      expect(out.containsKey('bri'), isFalse);
      expect(out['seg'], catalog['seg']);
    });

    test('catalog browsing (no design) is untouched', () {
      expect(designEditPreviewPayload(catalog, null), same(catalog));
    });
  });
}
