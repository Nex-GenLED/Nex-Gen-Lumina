// Self-tests for the text-scale harness: each defect it claims to catch is
// built on purpose and must be caught, and a well-behaved widget must pass.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'text_scale_harness.dart';

const TextStyle _label = TextStyle(fontSize: 16);

/// Two labels side by side with nothing allowed to shrink: fits a 390 wide
/// screen at default size, does not at 1.75x.
class _RigidRow extends StatelessWidget {
  const _RigidRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Text('Home team colours', softWrap: false, style: _label),
        SizedBox(width: 12),
        Text('Sunday 7:20 PM', softWrap: false, style: _label),
      ],
    );
  }
}

/// The same content, written to reflow.
class _ReflowingRow extends StatelessWidget {
  const _ReflowingRow();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 4,
      children: <Widget>[
        Text('Home team colours', style: _label),
        Text('Sunday 7:20 PM', style: _label),
      ],
    );
  }
}

/// A label in a box of fixed height: tall enough at default size only.
class _FixedHeightLabel extends StatelessWidget {
  const _FixedHeightLabel();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 28,
      width: 200,
      child: Text('Brightness', style: _label),
    );
  }
}

/// A label that is allowed to grow but sits inside a clipping box that is not.
class _ClippedLabel extends StatelessWidget {
  const _ClippedLabel();

  @override
  Widget build(BuildContext context) {
    return const ClipRect(
      child: SizedBox(
        height: 28,
        width: 200,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: Text('Brightness', style: _label),
        ),
      ),
    );
  }
}

class _EllipsizedLabel extends StatelessWidget {
  const _EllipsizedLabel();

  static const Key labelKey = ValueKey<String>('ellipsized-label');

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 160,
      child: Text(
        'A controller name that is far too long to fit',
        key: labelKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _label,
      ),
    );
  }
}

/// Sized by its content everywhere: wraps, scrolls, and its button grows.
class _WellBehaved extends StatelessWidget {
  const _WellBehaved();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Game Day', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Your lights change to your team colours when the game starts and '
            'go back to your schedule when it ends.',
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              const Icon(Icons.sports_football),
              const SizedBox(width: 12),
              const Expanded(child: Text('Follow every game this season')),
              Switch(value: true, onChanged: (bool _) {}),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {},
            child: const Text('Choose a team'),
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(labelText: 'Search teams'),
          ),
        ],
      ),
    );
  }
}

void main() {
  group('overflow', () {
    testWidgets('a rigid row passes at 1.0 and overflows at 1.75',
        (WidgetTester tester) async {
      final TextScaleReport atDefault = await pumpAtTextScale(
        tester,
        const _RigidRow(),
        profile: TextScaleProfile.defaultSize,
      );
      expect(atDefault.defects, isEmpty, reason: atDefault.describe());

      final TextScaleReport atLarge =
          await pumpAtTextScale(tester, const _RigidRow());
      expect(atLarge.ofKind(TextScaleDefectKind.overflow), hasLength(1));
      final TextScaleDefect defect =
          atLarge.ofKind(TextScaleDefectKind.overflow).single;
      expect(defect.message, contains('A RenderFlex overflowed by'));
      expect(defect.creatorChain, contains('Row'));
      expect(defect.creatorChain, contains('_RigidRow'));
    });

    testWidgets('every overflowing widget is reported, not just the first',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const Column(
          children: <Widget>[_RigidRow(), _RigidRow(), _RigidRow()],
        ),
      );
      expect(report.ofKind(TextScaleDefectKind.overflow), hasLength(3));
    });

    testWidgets('a row that overflows at default size is caught at 1.0',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const Row(
          children: <Widget>[
            SizedBox(width: 300, child: Text('Left')),
            SizedBox(width: 120, child: Text('Right')),
          ],
        ),
        profile: TextScaleProfile.defaultSize,
      );
      expect(report.ofKind(TextScaleDefectKind.overflow), hasLength(1));
    });

    testWidgets('the same content written to reflow passes at 2.0',
        (WidgetTester tester) async {
      await expectNoTextScaleDefects(
        tester,
        const _ReflowingRow(),
        profile: TextScaleProfile.maximum,
      );
    });

    testWidgets('an error that is not an overflow still fails the test',
        (WidgetTester tester) async {
      await pumpAtTextScale(
        tester,
        Builder(
          builder: (BuildContext context) => throw StateError('not overflow'),
        ),
      );
      expect(tester.takeException(), isStateError);
    });
  });

  group('clipped text', () {
    testWidgets('a fixed-height box passes at 1.0 and clips at 1.75',
        (WidgetTester tester) async {
      final TextScaleReport atDefault = await pumpAtTextScale(
        tester,
        const _FixedHeightLabel(),
        profile: TextScaleProfile.defaultSize,
      );
      expect(atDefault.defects, isEmpty, reason: atDefault.describe());

      final TextScaleReport atLarge =
          await pumpAtTextScale(tester, const _FixedHeightLabel());
      expect(
        atLarge.ofKind(TextScaleDefectKind.textTallerThanBox),
        hasLength(1),
        reason: atLarge.describe(),
      );
      final TextScaleDefect defect =
          atLarge.ofKind(TextScaleDefectKind.textTallerThanBox).single;
      expect(defect.text, 'Brightness');
      expect(defect.message, contains('its box is 28 tall'));
      expect(defect.creatorChain, contains('_FixedHeightLabel'));
    });

    testWidgets('text outside a clipping ancestor is caught',
        (WidgetTester tester) async {
      final TextScaleReport atDefault = await pumpAtTextScale(
        tester,
        const _ClippedLabel(),
        profile: TextScaleProfile.defaultSize,
      );
      expect(atDefault.defects, isEmpty, reason: atDefault.describe());

      final TextScaleReport atLarge =
          await pumpAtTextScale(tester, const _ClippedLabel());
      expect(
        atLarge.ofKind(TextScaleDefectKind.clippedByAncestor),
        hasLength(1),
        reason: atLarge.describe(),
      );
      expect(
        atLarge.ofKind(TextScaleDefectKind.clippedByAncestor).single.message,
        allOf(contains('at the bottom'), contains('RenderClipRect')),
      );
    });

    testWidgets('text that cannot wrap and is wider than its box is caught',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const SizedBox(
          width: 120,
          child: Text(
            'A controller name that is far too long to fit',
            softWrap: false,
            overflow: TextOverflow.fade,
            style: _label,
          ),
        ),
      );
      expect(report.ofKind(TextScaleDefectKind.truncatedText), hasLength(1));
    });

    testWidgets('text pushed off the bottom of the screen is caught',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const Stack(
          children: <Widget>[
            Positioned(top: 800, left: 0, child: Text('Below the screen')),
          ],
        ),
      );
      expect(
        report.ofKind(TextScaleDefectKind.clippedByAncestor),
        hasLength(1),
        reason: report.describe(),
      );
    });

    testWidgets('text below the fold of a scrolling list is not a defect',
        (WidgetTester tester) async {
      await expectNoTextScaleDefects(
        tester,
        ListView(
          children: <Widget>[
            for (int i = 0; i < 40; i++) ListTile(title: Text('Pattern $i')),
          ],
        ),
      );
    });

    testWidgets('a text field in a box shorter than one line is caught',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const SizedBox(
          height: 20,
          width: 200,
          child: TextField(
            style: _label,
            decoration: InputDecoration.collapsed(hintText: null),
          ),
        ),
      );
      expect(
        report.ofKind(TextScaleDefectKind.textFieldTooShort),
        hasLength(1),
        reason: report.describe(),
      );
    });
  });

  group('ellipsis opt-out', () {
    testWidgets('an ellipsized label fails by default',
        (WidgetTester tester) async {
      final TextScaleReport report =
          await pumpAtTextScale(tester, const _EllipsizedLabel());
      expect(report.ofKind(TextScaleDefectKind.truncatedText), hasLength(1));
      expect(
        report.defects.single.message,
        contains('hit maxLines: 1'),
      );

      await expectLater(
        expectNoTextScaleDefects(tester, const _EllipsizedLabel()),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('allowEllipsis excuses it, and records that it did',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const _EllipsizedLabel(),
        allowEllipsis: <Finder>[find.byKey(_EllipsizedLabel.labelKey)],
      );
      expect(report.defects, isEmpty, reason: report.describe());
      expect(report.allowed, hasLength(1));
      expect(report.allowed.single.kind, TextScaleDefectKind.truncatedText);

      await expectNoTextScaleDefects(
        tester,
        const _EllipsizedLabel(),
        allowEllipsis: <Finder>[find.byKey(_EllipsizedLabel.labelKey)],
      );
    });

    testWidgets('allowEllipsis excuses only the label it names',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _EllipsizedLabel(),
            SizedBox(
              width: 160,
              child: Text(
                'Another label that is cut short',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _label,
              ),
            ),
          ],
        ),
        allowEllipsis: <Finder>[find.byKey(_EllipsizedLabel.labelKey)],
      );
      expect(report.allowed, hasLength(1));
      expect(report.defects, hasLength(1));
      expect(report.defects.single.text, 'Another label that is cut short');
    });

    testWidgets('allowEllipsis does not excuse any other kind of defect',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const _FixedHeightLabel(),
        allowEllipsis: <Finder>[find.byType(_FixedHeightLabel)],
      );
      expect(
        report.ofKind(TextScaleDefectKind.textTallerThanBox),
        hasLength(1),
      );
    });

    testWidgets('the allow predicate can excuse a specific defect',
        (WidgetTester tester) async {
      final TextScaleReport report = await pumpAtTextScale(
        tester,
        const _FixedHeightLabel(),
        allow: (TextScaleDefect defect) =>
            defect.kind == TextScaleDefectKind.textTallerThanBox &&
            defect.text == 'Brightness',
      );
      expect(report.defects, isEmpty, reason: report.describe());
      expect(report.allowed, hasLength(1));
    });
  });

  group('a well-behaved widget', () {
    testWidgets('passes at 2.0', (WidgetTester tester) async {
      await expectNoTextScaleDefects(
        tester,
        const _WellBehaved(),
        profile: TextScaleProfile.maximum,
      );
    });

    testWidgets('passes the whole matrix', (WidgetTester tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(tester, const _WellBehaved());
    });

    testWidgets('passes as a whole screen', (WidgetTester tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('Game Day')),
          body: const _WellBehaved(),
        ),
        host: TextScaleHost.screen,
      );
    });
  });

  group('matrix', () {
    testWidgets('runs 1.0, 1.75 and 2.0 with bold on',
        (WidgetTester tester) async {
      expect(
        TextScaleProfile.standardMatrix
            .map((TextScaleProfile p) => p.textScale),
        <double>[1.0, 1.75, 2.0],
      );
      expect(
        TextScaleProfile.standardMatrix.every((TextScaleProfile p) =>
            p.boldText &&
            p.screenSize == const Size(390, 844) &&
            p.devicePixelRatio == 3.0),
        isTrue,
      );
    });

    testWidgets('reports every failing profile, not just the first',
        (WidgetTester tester) async {
      final List<TextScaleReport> reports =
          await pumpAcrossTextScaleMatrix(tester, const _RigidRow());
      expect(
        reports.map((TextScaleReport r) => r.isClean),
        <bool>[true, false, false],
      );

      final String message = describeTextScaleMatrixFailures(reports)!;
      expect(message, contains('2 of 3 text-scale profiles failed'));
      expect(message, contains('at 1.75x, bold on, 390x844 @3.0x'));
      expect(message, contains('at 2.0x, bold on, 390x844 @3.0x'));
      expect(message, isNot(contains('at 1.0x')));
      expect('A RenderFlex overflowed by'.allMatches(message), hasLength(2));

      await expectLater(
        expectNoTextScaleDefectsAcrossMatrix(tester, const _RigidRow()),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('a clean matrix has nothing to describe',
        (WidgetTester tester) async {
      final List<TextScaleReport> reports =
          await pumpAcrossTextScaleMatrix(tester, const _ReflowingRow());
      expect(describeTextScaleMatrixFailures(reports), isNull);
    });
  });

  group('profile', () {
    late MediaQueryData seen;
    final Widget probe = Builder(
      builder: (BuildContext context) {
        seen = MediaQuery.of(context);
        return const SizedBox.shrink();
      },
    );

    testWidgets('the default is 1.75x, bold, 390x844 at 3.0',
        (WidgetTester tester) async {
      await pumpAtTextScale(tester, probe, host: TextScaleHost.screen);
      expect(seen.textScaler.scale(10), 17.5);
      expect(seen.boldText, isTrue);
      expect(seen.size, const Size(390, 844));
      expect(seen.devicePixelRatio, 3.0);
      expect(seen.padding.top, 47);
      expect(seen.padding.bottom, 34);
    });

    testWidgets('scale, bold flag and size are parameters',
        (WidgetTester tester) async {
      await pumpAtTextScale(
        tester,
        probe,
        host: TextScaleHost.screen,
        profile: const TextScaleProfile(
          textScale: 1.3,
          boldText: false,
          screenSize: Size(320, 568),
          devicePixelRatio: 2.0,
          safeArea: EdgeInsets.zero,
        ),
      );
      expect(seen.textScaler.scale(10), 13);
      expect(seen.boldText, isFalse);
      expect(seen.size, const Size(320, 568));
      expect(seen.devicePixelRatio, 2.0);
    });

    testWidgets('a platform scale above the cap is laid out at 2.0',
        (WidgetTester tester) async {
      await pumpAtTextScale(
        tester,
        probe,
        host: TextScaleHost.screen,
        profile: const TextScaleProfile(textScale: 3.1),
      );
      expect(seen.textScaler.scale(10), 20);
    });

    testWidgets('bold text reaches the text that is drawn',
        (WidgetTester tester) async {
      Future<double> widthWith({required bool bold}) async {
        await pumpAtTextScale(
          tester,
          const Text('Brightness', softWrap: false, style: _label),
          profile: TextScaleProfile(textScale: 1.0, boldText: bold),
        );
        return tester.getSize(find.text('Brightness')).width;
      }

      final double regular = await widthWith(bold: false);
      final double bold = await widthWith(bold: true);
      expect(bold, greaterThan(regular));
    });
  });

  group('teardown', () {
    testWidgets('a harness run changes the view', (WidgetTester tester) async {
      await pumpAtTextScale(tester, const _WellBehaved());
      expect(tester.view.physicalSize, const Size(1170, 2532));
      expect(tester.platformDispatcher.textScaleFactor, 1.75);
    });

    testWidgets('and the next test starts from the defaults again',
        (WidgetTester tester) async {
      expect(tester.view.physicalSize, const Size(2400, 1800));
      expect(tester.view.devicePixelRatio, 3.0);
      expect(tester.view.padding.top, 0);
      expect(tester.platformDispatcher.textScaleFactor, 1.0);
      expect(tester.platformDispatcher.accessibilityFeatures.boldText, isFalse);
    });
  });
}
