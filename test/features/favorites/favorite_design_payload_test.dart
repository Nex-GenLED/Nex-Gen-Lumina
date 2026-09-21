// A per-pixel (Static) favorite: what it stores, that it survives every hop a
// favorite's payload takes, and that it is the SAME picture My Designs stores.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';

const _channels = [
  PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
  PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
];

EditablePattern _chiefs({int fx = 0}) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
      effectId: fx,
    ).copyWith(actionColors: const [
      Color(0xFFE31837),
      Color(0xFFFFB81C),
      Color(0xFFFFFFFF),
    ], brightness: 180);

CustomDesign _design({int fx = 0}) => customDesignFromEditablePattern(
      pattern: _chiefs(fx: fx),
      name: 'Kansas City Chiefs',
      ownerId: '',
      channels: _channels,
    );

/// Per-LED colours of a design, channel by channel.
Map<int, List<String>> _pixels(CustomDesign d) => {
      for (final ch in d.channels)
        ch.channelId: [
          for (final s in ch.fullCoverageSpans())
            for (int i = s.start; i <= s.end; i++) s.color.join(','),
        ],
    };

void main() {
  group('buildPerPixelFavoritePayload', () {
    test('is JSON — it has to survive jsonEncode into pattern_data', () {
      final payload = buildPerPixelFavoritePayload(_design());
      expect(() => jsonEncode(payload), returnsNormally,
          reason: 'a Timestamp (or any non-JSON value) in the embedded design '
              'would throw here, at the heart tap');
    });

    test('carries the design in My Designs\' own shape — no second one', () {
      final design = _design();
      final embedded = buildPerPixelFavoritePayload(design)[kFavoriteDesignKey]
          as Map<String, dynamic>;
      final saved = design.toFirestore();
      // Every key, and every value, that a My Designs save writes — except the
      // two Timestamps JSON cannot hold.
      expect(embedded.keys.toSet(),
          saved.keys.toSet()..removeAll(['created_at', 'updated_at']));
      for (final k in embedded.keys) {
        expect(jsonEncode(embedded[k]), jsonEncode(saved[k]), reason: k);
      }
      expect(embedded['per_pixel'], isTrue);
    });

    test('round trip through pattern_data is LED-for-LED exact, both channels',
        () {
      final design = _design();
      // The real writer → the stored string → the real decoder.
      final doc = buildFavoriteCreateData(
        patternName: 'Kansas City Chiefs',
        payload: buildPerPixelFavoritePayload(design),
      );
      expect(doc[kFavoritePatternData], isA<String>());
      final back =
          perPixelDesignOfFavorite(decodeFavoritePayload(doc[kFavoritePatternData]));

      expect(back, isNotNull);
      expect(back!.perPixel, isTrue);
      expect(back.isPositional, isTrue);
      expect(back.channels.map((c) => c.ledCount), [128, 162]);
      final want = _pixels(design), got = _pixels(back);
      expect(got[0]!.length, 128);
      expect(got[1]!.length, 162);
      expect(got, want, reason: '290 LEDs, none differing');
      // …and therefore the same spans reach the spine.
      expect(customDesignToSpans(back).map((k, v) => MapEntry(k, '$v')),
          customDesignToSpans(design).map((k, v) => MapEntry(k, '$v')));
    });

    test('keeps the brightness the user chose, and says it chose it', () {
      final back = perPixelDesignOfFavorite(jsonDecode(
              jsonEncode(buildPerPixelFavoritePayload(_design())))
          as Map<String, dynamic>)!;
      expect(back.brightness, 180);
      expect(back.statesBrightness, isTrue,
          reason: 'the pattern-editor tag is what makes the spine restore bri');
    });

    test('summary seg: what the My Favorites card and analytics read', () {
      final payload = buildPerPixelFavoritePayload(_design());
      expect(payload['on'], isTrue);
      expect(payload['bri'], 180);
      final seg = (payload['seg'] as List).single as Map;
      expect(seg['fx'], 0);
      expect(seg['col'], [
        [227, 24, 55, 0],
        [255, 184, 28, 0],
        [255, 255, 255, 0],
      ]);
      expect(seg.containsKey('i'), isFalse,
          reason: 'the per-LED data lives in the design, not in a second copy');
    });

    test('is far over the single-message ceiling — which is WHY it must not be '
        'sent as one message', () {
      final bytes =
          utf8.encode(jsonEncode(buildPerPixelFavoritePayload(_design()))).length;
      expect(bytes, greaterThan(kMaxApplyPayloadBytes));
    });
  });

  group('perPixelDesignOfFavorite', () {
    test('an ordinary favorite is not a per-pixel favorite', () {
      expect(
          perPixelDesignOfFavorite({
            'on': true,
            'seg': [
              {'fx': 15, 'col': [[255, 0, 0, 0]]}
            ],
          }),
          isNull);
      expect(perPixelDesignOfFavorite(const {}), isNull);
    });

    test('never throws on a mangled design', () {
      expect(perPixelDesignOfFavorite({kFavoriteDesignKey: 'nope'}), isNull);
      expect(perPixelDesignOfFavorite({kFavoriteDesignKey: 7}), isNull);
      expect(
          perPixelDesignOfFavorite({
            kFavoriteDesignKey: {'channels': 'not a list'},
          }),
          isNull);
    });

    test('an embedded design that is not positional is ignored', () {
      // An effect design smuggled under the key must not be sent per-pixel.
      final effect = _design(fx: 15);
      expect(effect.isPositional, isFalse);
      final payload = buildPerPixelFavoritePayload(effect);
      expect(perPixelDesignOfFavorite(payload), isNull);
    });

    test('survives the habit learner\'s hop: payload → usage log string → '
        'auto-added favorite', () {
      final payload = buildPerPixelFavoritePayload(_design());
      // UserService.logPatternUsage stores `wled: jsonEncode(payload)`; the
      // habit learner copies that STRING into a new favorite's pattern_data.
      final logged = jsonEncode(payload);
      final autoFavorite = decodeFavoritePayload(logged);
      expect(perPixelDesignOfFavorite(autoFavorite), isNotNull);
      expect(_pixels(perPixelDesignOfFavorite(autoFavorite)!), _pixels(_design()));
    });
  });
}
