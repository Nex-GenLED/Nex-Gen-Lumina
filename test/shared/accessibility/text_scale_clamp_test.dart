import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';

/// What a descendant of the clamp sees.
class _Seen {
  TextScaler? scaler;
  bool? boldText;
  MediaQueryData? data;
}

Widget _probe(_Seen seen) {
  return Builder(
    builder: (BuildContext context) {
      seen.data = MediaQuery.of(context);
      seen.scaler = MediaQuery.textScalerOf(context);
      seen.boldText = MediaQuery.boldTextOf(context);
      return const SizedBox.shrink();
    },
  );
}

Future<_Seen> _pumpUnderPlatformScale(
  WidgetTester tester, {
  required double platformScale,
  bool boldText = true,
  TransitionBuilder builder = TextScaleClamp.appBuilder,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = platformScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(boldText: boldText);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final _Seen seen = _Seen();
  await tester.pumpWidget(
    MaterialApp(builder: builder, home: _probe(seen)),
  );
  return seen;
}

void main() {
  test('the cap is 2.0 and sits above the 1.75 test profile', () {
    expect(kMaxTextScaleFactor, 2.0);
    expect(kMaxTextScaleFactor, greaterThan(1.75));
  });

  group('TextScaleClamp.clampScaler', () {
    test('caps a 3.1 platform scale at 2.0', () {
      final TextScaler clamped =
          TextScaleClamp.clampScaler(const TextScaler.linear(3.1));
      expect(clamped.scale(10), 20);
      expect(clamped.scale(14), 28);
    });

    test('leaves 1.75 unchanged', () {
      const TextScaler scaler = TextScaler.linear(1.75);
      expect(TextScaleClamp.clampScaler(scaler), scaler);
      expect(TextScaleClamp.clampScaler(scaler).scale(10), 17.5);
    });

    test('leaves 1.0 unchanged', () {
      expect(TextScaleClamp.clampScaler(TextScaler.noScaling),
          TextScaler.noScaling);
    });

    test('leaves exactly 2.0 unchanged', () {
      const TextScaler scaler = TextScaler.linear(2.0);
      expect(TextScaleClamp.clampScaler(scaler), scaler);
    });

    test('applies no minimum: a scale below 1.0 is not raised', () {
      const TextScaler scaler = TextScaler.linear(0.85);
      expect(TextScaleClamp.clampScaler(scaler), scaler);
      expect(TextScaleClamp.clampScaler(scaler).scale(10), 8.5);
    });
  });

  group('TextScaleClamp at the app root', () {
    testWidgets('platform 3.1 becomes an effective 2.0', (tester) async {
      final _Seen seen =
          await _pumpUnderPlatformScale(tester, platformScale: 3.1);
      expect(seen.scaler!.scale(10), 20);
      expect(seen.scaler!.scale(16), 32);
    });

    testWidgets('platform 1.75 is unchanged', (tester) async {
      final _Seen seen =
          await _pumpUnderPlatformScale(tester, platformScale: 1.75);
      // The platform scaler is wrapped, so compare what it does, not what it
      // is: every size must come out exactly as the platform asked.
      for (final double size in <double>[10, 12, 14, 16, 22, 32, 57]) {
        expect(seen.scaler!.scale(size), size * 1.75, reason: 'size $size');
      }
    });

    testWidgets('platform 1.0 is unchanged', (tester) async {
      final _Seen seen =
          await _pumpUnderPlatformScale(tester, platformScale: 1.0);
      expect(seen.scaler!.scale(10), 10);
    });

    testWidgets('a scale below 1.0 is not raised', (tester) async {
      final _Seen seen =
          await _pumpUnderPlatformScale(tester, platformScale: 0.8);
      expect(seen.scaler!.scale(10), 8);
    });

    testWidgets('bold text passes through when on', (tester) async {
      final _Seen seen = await _pumpUnderPlatformScale(
        tester,
        platformScale: 3.1,
        boldText: true,
      );
      expect(seen.boldText, isTrue);
    });

    testWidgets('bold text passes through when off', (tester) async {
      final _Seen seen = await _pumpUnderPlatformScale(
        tester,
        platformScale: 3.1,
        boldText: false,
      );
      expect(seen.boldText, isFalse);
    });

    testWidgets('only the scaler changes; other media data is kept',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _Seen seen =
          await _pumpUnderPlatformScale(tester, platformScale: 3.1);
      expect(seen.data!.size, const Size(390, 844));
      expect(seen.data!.devicePixelRatio, 3.0);
    });

    testWidgets('text below the clamp is laid out at the capped size',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester.pumpWidget(
        const MaterialApp(
          builder: TextScaleClamp.appBuilder,
          home: Center(
            child: Text('A', style: TextStyle(fontSize: 10, height: 1.0)),
          ),
        ),
      );
      // The test font is a 1em square, so height == scaled font size.
      expect(tester.getSize(find.text('A')).height, 20);
    });
  });

  group('TextScaleClamp.compose', () {
    testWidgets('keeps the wrapped builder and clamps inside it',
        (tester) async {
      TextScaler? seenByInner;
      final _Seen seen = await _pumpUnderPlatformScale(
        tester,
        platformScale: 3.1,
        builder: TextScaleClamp.compose((BuildContext context, Widget? child) {
          seenByInner = MediaQuery.textScalerOf(context);
          return KeyedSubtree(key: const ValueKey('inner'), child: child!);
        }),
      );

      expect(find.byKey(const ValueKey('inner')), findsOneWidget);
      expect(seenByInner!.scale(10), 20);
      expect(seen.scaler!.scale(10), 20);
      expect(seen.boldText, isTrue);
    });

    testWidgets('with no inner builder behaves like appBuilder',
        (tester) async {
      final _Seen seen = await _pumpUnderPlatformScale(
        tester,
        platformScale: 3.1,
        builder: TextScaleClamp.compose(null),
      );
      expect(seen.scaler!.scale(10), 20);
    });
  });
}
