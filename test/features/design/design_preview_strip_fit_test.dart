// The no-photo fallback preview must FIT: every LED visible, no overflow.
//
// Each dot's width was the whole per-LED slot (floored at 1 px) plus a 0.6 px
// margin, so N dots overflowed by 0.6·N px. At a real 290-LED home on a phone
// the right third of the roofline was cut off.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';

void main() {
  for (final (width, leds) in [(360.0, 290), (360.0, 128), (800.0, 40), (320.0, 600)]) {
    testWidgets('$leds LEDs fit in ${width.toInt()} px without overflow', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
          houseImageUrlProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DesignPreview(
              frame: {
                0: List<Color>.filled(leds ~/ 2, Colors.red),
                1: List<Color>.filled(leds - leds ~/ 2, Colors.blue),
              },
              height: 200,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'RenderFlex overflow');
    });
  }
}
