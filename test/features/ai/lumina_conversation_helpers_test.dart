// test/features/ai/lumina_conversation_helpers_test.dart
//
// Pure-function tests for the helpers that moved out of the two Lumina
// surfaces into lumina_conversation_driver.dart:
//   • resolveLuminaNavigation / isLuminaShellRoute — go() vs push() vs tab
//   • extractLuminaPreview — response-card preview from a payload
//   • buildEphemeralAugmentation — revert confirmation suffix
//   • priorLuminaUserPrompt — prompt behind a tapped bubble
// No Riverpod, no widget harness.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/ephemeral_session_dispatcher.dart';
import 'package:nexgen_command/features/ai/lumina_conversation_driver.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/theme.dart';

void main() {
  group('resolveLuminaNavigation', () {
    test('a tab index selects the tab', () {
      final target = resolveLuminaNavigation({'tabIndex': 1});

      expect(target.action, LuminaNavigationAction.selectTab);
      expect(target.tabIndex, 1);
      expect(target.route, isNull);
    });

    test('a tab index wins over a route', () {
      final target =
          resolveLuminaNavigation({'route': '/settings', 'tabIndex': 3});

      expect(target.action, LuminaNavigationAction.selectTab);
      expect(target.tabIndex, 3);
    });

    test('within-shell routes use go()', () {
      for (final route in [
        '/explore',
        '/explore/design-studio',
        '/settings',
        '/settings/profile',
        '/settings/roofline-editor',
        '/schedule',
        '/wled/zones',
        '/dashboard',
      ]) {
        final target = resolveLuminaNavigation({'route': route});
        expect(target.action, LuminaNavigationAction.go, reason: route);
        expect(target.route, route);
      }
    });

    // The two surfaces disagreed here: the sheet matched the '/dashboard'
    // prefix, the full screen only the bare '/dashboard'. These routes are
    // nested under the home branch, so both surfaces now use go().
    test('nested /dashboard routes use go()', () {
      for (final route in [
        '/dashboard/my-designs',
        '/dashboard/design-studio',
        '/dashboard/game-day',
      ]) {
        final target = resolveLuminaNavigation({'route': route});
        expect(target.action, LuminaNavigationAction.go, reason: route);
      }
    });

    test('routes outside the shell use push()', () {
      for (final route in ['/my-scenes', '/lumina-ai', '/wled']) {
        final target = resolveLuminaNavigation({'route': route});
        expect(target.action, LuminaNavigationAction.push, reason: route);
        expect(target.route, route);
      }
    });

    test('no route and no tab → nothing to do', () {
      expect(resolveLuminaNavigation(const {}).action,
          LuminaNavigationAction.none);
      expect(resolveLuminaNavigation({'route': null}).action,
          LuminaNavigationAction.none);
    });
  });

  group('extractLuminaPreview', () {
    test('rich metadata wins over the segment', () {
      final preview = extractLuminaPreview({
        'patternName': 'Harvest Glow',
        'colors': [
          {
            'name': 'Amber',
            'rgb': [255, 140, 0],
          },
          {
            'name': 'Crimson',
            'rgb': [200, 0, 30],
          },
        ],
        'effect': {
          'name': 'Breathe',
          'id': 2,
          'direction': 'none',
          'isStatic': false,
        },
        'speed': 90,
        'intensity': 150,
        'on': true,
        'seg': [
          {
            'fx': 12,
            'pal': 5,
            'sx': 10,
            'ix': 20,
            'col': [
              [0, 0, 255, 0],
            ],
          },
        ],
      })!;

      expect(preview.patternName, 'Harvest Glow');
      expect(preview.colors,
          const [Color(0xFFFF8C00), Color(0xFFC8001E)]);
      expect(preview.colorNames, ['Amber', 'Crimson']);
      expect(preview.effectId, 2);
      expect(preview.effectName, 'Breathe');
      expect(preview.direction, 'none');
      expect(preview.isStatic, isFalse);
      expect(preview.speed, 90);
      expect(preview.intensity, 150);
      // Only the palette has no rich source — it is read from the segment.
      expect(preview.paletteId, 5);
    });

    test('a bare WLED payload falls back to the first segment', () {
      final preview = extractLuminaPreview({
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 43,
            'pal': 0,
            'sx': 128,
            'ix': 180,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
            ],
          },
        ],
      })!;

      expect(preview.patternName, isNull);
      expect(preview.colors,
          const [Color(0xFFFF0000), Color(0xFF00FF00)]);
      expect(preview.colorNames, isEmpty);
      expect(preview.effectId, 43);
      expect(preview.speed, 128);
      expect(preview.intensity, 180);
    });

    test('a payload nested under `wled` is read through it', () {
      final preview = extractLuminaPreview({
        'patternName': 'Nested',
        'wled': {
          'seg': [
            {
              'fx': 2,
              'col': [
                [10, 20, 30],
              ],
            },
          ],
        },
      })!;

      expect(preview.effectId, 2);
      expect(preview.colors, const [Color(0xFF0A141E)]);
    });

    test('at most five colors are kept', () {
      final preview = extractLuminaPreview({
        'colors': [
          for (int i = 0; i < 8; i++)
            {
              'name': 'c$i',
              'rgb': [i, i, i],
            },
        ],
      })!;

      expect(preview.colors.length, 5);
    });

    // Pins today's behaviour — UX audit row 112 changes it on purpose: a
    // power / brightness payload has no colors, and the preview is
    // manufactured from the fallback swatches rather than withheld.
    test('row 112: a payload with no colors gets the fallback swatches', () {
      const fallback = [NexGenPalette.cyan, Color(0xFF102040)];

      final power = extractLuminaPreview({'on': true})!;
      expect(power.colors, fallback);
      expect(power.patternName, isNull);
      expect(power.effectId, isNull);

      final brightness = extractLuminaPreview({'on': true, 'bri': 128})!;
      expect(brightness.colors, fallback);

      final colorlessSeg = extractLuminaPreview({
        'seg': [
          {'fx': 0},
        ],
      })!;
      expect(colorlessSeg.colors, fallback);
      expect(colorlessSeg.effectId, 0);
    });

    // UX audit pattern P6 — FIXED in +110. When seg[0] is the
    // `{id:0, on:false}` exclusion marker, the design in seg[1] is read
    // (firstRealDesignSegment), not replaced with fallback swatches.
    test('P6: an exclusion marker in seg[0] no longer hides the design',
        () {
      final preview = extractLuminaPreview({
        'on': true,
        'seg': [
          {'id': 0, 'on': false},
          {
            'id': 1,
            'on': true,
            'fx': 43,
            'pal': 5,
            'sx': 128,
            'ix': 180,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
            ],
          },
        ],
      })!;

      expect(preview.colors, const [Color(0xFFFF0000), Color(0xFF00FF00)]);
      expect(preview.effectId, 43);
      expect(preview.paletteId, 5);
      expect(preview.speed, 128);
      expect(preview.intensity, 180);
    });

    test('rich colors still show when seg[0] is an exclusion marker', () {
      final preview = extractLuminaPreview({
        'colors': [
          {
            'name': 'Red',
            'rgb': [255, 0, 0],
          },
        ],
        'effect': {'name': 'Twinkle', 'id': 43},
        'seg': [
          {'id': 0, 'on': false},
          {
            'id': 1,
            'fx': 43,
            'col': [
              [255, 0, 0, 0],
            ],
          },
        ],
      })!;

      expect(preview.colors, const [Color(0xFFFF0000)]);
      expect(preview.effectId, 43);
    });

    test('an unreadable payload yields no preview', () {
      expect(extractLuminaPreview({'patternName': 42}), isNull);
      expect(extractLuminaPreview({'wled': 'not a map'}), isNull);
    });
  });

  group('buildEphemeralAugmentation', () {
    DispatchResult dispatch({
      List<String> sessionIds = const [],
      List<String> labels = const [],
      String? noGameFoundMessage,
      String? errorMessage,
    }) =>
        DispatchResult(
          createdSessionIds: sessionIds,
          sessionLabels: labels,
          teamDisplayName: 'Team Under Test',
          revertLabel: 'Warm White',
          noGameFoundMessage: noGameFoundMessage,
          success: errorMessage == null,
          errorMessage: errorMessage,
        );

    for (final surface in LuminaSurface.values) {
      test('one game (${surface.name})', () {
        expect(
          buildEphemeralAugmentation(
            dispatch(sessionIds: ['s1'], labels: ['Team — 7:00 PM']),
            surface: surface,
          ),
          '✓ Will revert to Warm White when Team — 7:00 PM ends.',
        );
      });

      test('a doubleheader lists every game (${surface.name})', () {
        expect(
          buildEphemeralAugmentation(
            dispatch(
              sessionIds: ['s1', 's2'],
              labels: ['Team — 1:00 PM', 'Team — 7:00 PM'],
            ),
            surface: surface,
          ),
          '✓ Will revert to Warm White after each game ends: '
          'Team — 1:00 PM, Team — 7:00 PM.',
        );
      });

      test('no game found passes the message through (${surface.name})', () {
        expect(
          buildEphemeralAugmentation(
            dispatch(noGameFoundMessage: 'No game tonight.'),
            surface: surface,
          ),
          'No game tonight.',
        );
      });

      // Pins today's behaviour — UX audit row 109 changes it on purpose.
      test('row 109: a failed dispatch adds nothing (${surface.name})', () {
        expect(
          buildEphemeralAugmentation(
            dispatch(errorMessage: 'service unavailable'),
            surface: surface,
          ),
          isNull,
        );
      });
    }
  });

  group('priorLuminaUserPrompt', () {
    final messages = [
      LuminaMessage.user('warm white'),
      LuminaMessage.assistant('Applying Warm White now.'),
      LuminaMessage.user('   '),
      LuminaMessage.assistant('Second reply.'),
    ];

    test('finds the prompt behind a bubble', () {
      expect(priorLuminaUserPrompt(messages, 1), 'warm white');
    });

    test('skips blank user messages', () {
      expect(priorLuminaUserPrompt(messages, 3), 'warm white');
    });

    test('nothing before the first bubble', () {
      expect(priorLuminaUserPrompt(messages, 0), isNull);
    });
  });
}
