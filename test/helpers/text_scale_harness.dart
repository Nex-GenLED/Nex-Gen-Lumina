/// Shared harness for laying a widget out at large accessibility text sizes and
/// failing the test when the layout breaks.
///
/// Usage, defaults, fix patterns and known blind spots are documented in
/// `docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md`.
///
/// ```dart
/// testWidgets('team row survives large text', (tester) async {
///   await expectNoTextScaleDefectsAcrossMatrix(tester, const TeamRow(...));
/// });
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/shared/fonts/bundled_font_weights.dart';

/// One combination of text scale, bold flag and screen to lay a widget out at.
@immutable
class TextScaleProfile {
  const TextScaleProfile({
    this.textScale = 1.75,
    this.boldText = true,
    this.screenSize = const Size(390, 844),
    this.devicePixelRatio = 3.0,
    this.safeArea = const EdgeInsets.only(top: 47, bottom: 34),
  });

  /// The default profile: 1.75x text, Bold Text on, 390x844 logical points at
  /// 3.0 device pixel ratio, with that phone class's safe-area insets.
  static const TextScaleProfile standard = TextScaleProfile();

  /// Default text size. Catches rows that overflow before any scaling.
  static const TextScaleProfile defaultSize = TextScaleProfile(textScale: 1.0);

  /// The app's backstop maximum, [kMaxTextScaleFactor].
  static const TextScaleProfile maximum =
      TextScaleProfile(textScale: kMaxTextScaleFactor);

  /// The matrix [expectNoTextScaleDefectsAcrossMatrix] runs by default:
  /// 1.0, 1.75 and 2.0, all with Bold Text on.
  static const List<TextScaleProfile> standardMatrix = <TextScaleProfile>[
    defaultSize,
    standard,
    maximum,
  ];

  /// The platform text scale factor. Values above [kMaxTextScaleFactor] are
  /// capped by the app-root clamp, exactly as on a device.
  final double textScale;

  /// Whether the platform Bold Text setting is on.
  final bool boldText;

  /// Screen size in logical points.
  final Size screenSize;

  /// Physical pixels per logical point.
  final double devicePixelRatio;

  /// Safe-area insets in logical points.
  final EdgeInsets safeArea;

  TextScaleProfile copyWith({
    double? textScale,
    bool? boldText,
    Size? screenSize,
    double? devicePixelRatio,
    EdgeInsets? safeArea,
  }) {
    return TextScaleProfile(
      textScale: textScale ?? this.textScale,
      boldText: boldText ?? this.boldText,
      screenSize: screenSize ?? this.screenSize,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
      safeArea: safeArea ?? this.safeArea,
    );
  }

  /// Short description used in failure messages.
  String get label {
    final String size = '${_fmt(screenSize.width)}x${_fmt(screenSize.height)}';
    return '${textScale}x, bold ${boldText ? 'on' : 'off'}, '
        '$size @${devicePixelRatio}x';
  }

  @override
  String toString() => 'TextScaleProfile($label)';
}

/// How the widget under test is hosted.
enum TextScaleHost {
  /// For a row, card, sheet body or any other part of a screen. Hosted in the
  /// app theme inside a `Scaffold` body and `SafeArea`, top-left aligned, with
  /// the full screen width and height available.
  component,

  /// For a whole screen that builds its own `Scaffold`. Hosted in the app
  /// theme as the `home:` of a `MaterialApp`.
  screen,

  /// The widget is pumped exactly as given. The caller owns the `MaterialApp`
  /// and is responsible for installing `TextScaleClamp.appBuilder` on it.
  none,
}

/// What went wrong with one render object.
enum TextScaleDefectKind {
  /// A `RenderFlex` (or other box that reports overflow) is too small for its
  /// children — the yellow and black stripes.
  overflow,

  /// Text was cut short by its own settings: it hit `maxLines`, was
  /// ellipsized, or cannot wrap and is wider than its box.
  truncatedText,

  /// Text was given a box shorter than the lines it laid out, so the bottom of
  /// the text is cut off. The usual cause is a fixed height around text.
  textTallerThanBox,

  /// Text (or a text field) extends outside an ancestor that clips, or outside
  /// the screen, in a direction that cannot be scrolled.
  clippedByAncestor,

  /// A text field is shorter than one line of its own text.
  textFieldTooShort,
}

/// One problem found by the harness.
@immutable
class TextScaleDefect {
  const TextScaleDefect({
    required this.kind,
    required this.message,
    required this.renderObject,
    this.text,
    this.creatorChain,
  });

  final TextScaleDefectKind kind;

  /// What is wrong, with measurements.
  final String message;

  /// The render object the defect was found on. `null` only for an overflow
  /// error that did not identify its render object.
  final RenderObject? renderObject;

  /// The text affected, for text defects.
  final String? text;

  /// The widgets that created [renderObject], innermost first.
  final String? creatorChain;

  @override
  String toString() {
    final StringBuffer out = StringBuffer('[${kind.name}] $message');
    if (creatorChain != null) {
      out.write('\n      widget: $creatorChain');
    }
    return out.toString();
  }
}

/// Decides whether a defect is intended and should not fail the test.
typedef TextScaleAllowance = bool Function(TextScaleDefect defect);

/// Everything the harness found for one profile.
@immutable
class TextScaleReport {
  const TextScaleReport({
    required this.profile,
    required this.defects,
    required this.allowed,
  });

  final TextScaleProfile profile;

  /// Defects that fail the test.
  final List<TextScaleDefect> defects;

  /// Defects that were found but explicitly allowed by the test.
  final List<TextScaleDefect> allowed;

  bool get isClean => defects.isEmpty;

  Iterable<TextScaleDefect> ofKind(TextScaleDefectKind kind) {
    return defects.where((TextScaleDefect d) => d.kind == kind);
  }

  /// A failure message listing every defect.
  String describe() {
    if (isClean) {
      return 'No text-scale defects at ${profile.label}.';
    }
    final StringBuffer out = StringBuffer(
      '${defects.length} text-scale defect${defects.length == 1 ? '' : 's'} '
      'at ${profile.label}:\n',
    );
    for (int i = 0; i < defects.length; i++) {
      out.writeln('  ${i + 1}. ${defects[i]}');
    }
    return out.toString();
  }
}

bool _appFontsLoaded = false;

/// Registers the app's real, shipped font files with the test engine.
///
/// Without this, the test engine draws every glyph as a square one em wide,
/// which makes text far wider than it is on a device and produces overflow
/// that does not exist. [pumpAtTextScale] calls this for you.
Future<void> loadAppFontsForTest(WidgetTester tester) async {
  if (_appFontsLoaded) {
    return;
  }
  await tester.runAsync<void>(() => registerBundledFontWeights());
  _appFontsLoaded = true;
}

/// Lays [widget] out at [profile] and returns everything that is wrong with
/// it. Does not fail the test; use [expectNoTextScaleDefects] for that.
///
/// * [host] — how the widget is wrapped; see [TextScaleHost].
/// * [theme] — defaults to the app theme.
/// * [allowEllipsis] — finders for labels that are truncated on purpose.
///   [TextScaleDefectKind.truncatedText] is not reported for text at or below
///   a widget these match. Nothing else is excused.
/// * [allow] — return `true` to excuse a specific defect of any kind.
/// * [settle] — how long to pump after the first frame. Set
///   [pumpAndSettle] instead for a widget with no endless animation.
/// * [frames] — how many frames [settle] is spread over. Leave at 1 for a
///   widget that is on screen from the first frame; raise it (e.g. 6, with
///   `settle: Duration(milliseconds: 900)`) for a sheet or dialog opened from
///   a post-frame callback, which only starts to animate in on the next frame.
/// * [tolerance] — slack, in logical pixels, before a measurement counts.
/// * [useAppFonts] — load the shipped fonts so text is measured at its real
///   width. Turn off only to test the harness itself.
///
/// View and platform overrides are reset in the test's teardown.
Future<TextScaleReport> pumpAtTextScale(
  WidgetTester tester,
  Widget widget, {
  TextScaleProfile profile = TextScaleProfile.standard,
  TextScaleHost host = TextScaleHost.component,
  ThemeData? theme,
  List<Finder> allowEllipsis = const <Finder>[],
  TextScaleAllowance? allow,
  Duration settle = const Duration(milliseconds: 500),
  bool pumpAndSettle = false,
  int frames = 1,
  double tolerance = 0.5,
  bool useAppFonts = true,
}) async {
  if (useAppFonts) {
    await loadAppFontsForTest(tester);
  }
  _applyProfile(tester, profile);

  final List<FlutterErrorDetails> overflowErrors = <FlutterErrorDetails>[];
  final List<FlutterErrorDetails> otherErrors = <FlutterErrorDetails>[];
  final FlutterExceptionHandler? previousHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    (_isOverflowError(details) ? overflowErrors : otherErrors).add(details);
  };
  try {
    // A fresh tree for every profile: overflow is reported once per render
    // object, so a reused tree would stay silent the second time round.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      KeyedSubtree(
        key: UniqueKey(),
        child: _host(widget, host, theme),
      ),
    );
    if (pumpAndSettle) {
      await tester.pumpAndSettle();
    } else if (frames <= 1) {
      await tester.pump(settle);
    } else {
      // A route opened from a post-frame callback (a sheet, a dialog) starts
      // its entrance animation on the NEXT frame; a single pump measures it
      // still closed. Spread [settle] over [frames] frames so it opens.
      await tester.pump();
      final Duration step = settle ~/ frames;
      for (int i = 0; i < frames; i++) {
        await tester.pump(step);
      }
    }
  } finally {
    FlutterError.onError = previousHandler;
  }
  // Anything that is not an overflow is not ours to judge; hand it back so
  // the test fails on it the way it normally would.
  for (final FlutterErrorDetails details in otherErrors) {
    previousHandler?.call(details);
  }

  final List<TextScaleDefect> found = <TextScaleDefect>[
    ..._overflowDefects(tester, overflowErrors),
    ..._textDefects(tester, tolerance),
  ];

  final Set<RenderObject> ellipsisAllowed = _renderObjectsUnder(allowEllipsis);
  final List<TextScaleDefect> defects = <TextScaleDefect>[];
  final List<TextScaleDefect> allowed = <TextScaleDefect>[];
  for (final TextScaleDefect defect in found) {
    final bool excused = (defect.kind == TextScaleDefectKind.truncatedText &&
            ellipsisAllowed.contains(defect.renderObject)) ||
        (allow?.call(defect) ?? false);
    (excused ? allowed : defects).add(defect);
  }
  return TextScaleReport(profile: profile, defects: defects, allowed: allowed);
}

/// Lays [widget] out at [profile] and fails the test, listing every defect,
/// if anything overflows or any text is clipped.
///
/// Takes the same options as [pumpAtTextScale].
Future<void> expectNoTextScaleDefects(
  WidgetTester tester,
  Widget widget, {
  TextScaleProfile profile = TextScaleProfile.standard,
  TextScaleHost host = TextScaleHost.component,
  ThemeData? theme,
  List<Finder> allowEllipsis = const <Finder>[],
  TextScaleAllowance? allow,
  Duration settle = const Duration(milliseconds: 500),
  bool pumpAndSettle = false,
  int frames = 1,
  double tolerance = 0.5,
  bool useAppFonts = true,
}) async {
  final TextScaleReport report = await pumpAtTextScale(
    tester,
    widget,
    profile: profile,
    host: host,
    theme: theme,
    allowEllipsis: allowEllipsis,
    allow: allow,
    settle: settle,
    pumpAndSettle: pumpAndSettle,
    frames: frames,
    tolerance: tolerance,
    useAppFonts: useAppFonts,
  );
  if (!report.isClean) {
    fail(report.describe());
  }
}

/// Runs [widget] through every profile in [profiles] and returns one report
/// per profile, in order. Does not fail the test.
Future<List<TextScaleReport>> pumpAcrossTextScaleMatrix(
  WidgetTester tester,
  Widget widget, {
  List<TextScaleProfile> profiles = TextScaleProfile.standardMatrix,
  TextScaleHost host = TextScaleHost.component,
  ThemeData? theme,
  List<Finder> allowEllipsis = const <Finder>[],
  TextScaleAllowance? allow,
  Duration settle = const Duration(milliseconds: 500),
  bool pumpAndSettle = false,
  int frames = 1,
  double tolerance = 0.5,
  bool useAppFonts = true,
}) async {
  final List<TextScaleReport> reports = <TextScaleReport>[];
  for (final TextScaleProfile profile in profiles) {
    reports.add(
      await pumpAtTextScale(
        tester,
        widget,
        profile: profile,
        host: host,
        theme: theme,
        allowEllipsis: allowEllipsis,
        allow: allow,
        settle: settle,
        pumpAndSettle: pumpAndSettle,
        frames: frames,
        tolerance: tolerance,
        useAppFonts: useAppFonts,
      ),
    );
  }
  return reports;
}

/// Builds the failure message for a matrix run, or returns `null` if every
/// profile is clean. Lists every failing profile and every defect in it.
String? describeTextScaleMatrixFailures(List<TextScaleReport> reports) {
  final List<TextScaleReport> failing =
      reports.where((TextScaleReport r) => !r.isClean).toList();
  if (failing.isEmpty) {
    return null;
  }
  final String scales = failing
      .map((TextScaleReport r) => '${r.profile.textScale}x')
      .join(', ');
  final StringBuffer out = StringBuffer(
    '${failing.length} of ${reports.length} text-scale profiles failed '
    '($scales).\n',
  );
  for (final TextScaleReport report in failing) {
    out.writeln(report.describe());
  }
  return out.toString();
}

/// Runs [widget] through the standard matrix (1.0, 1.75, 2.0 — all with Bold
/// Text on) and fails the test if any profile has a defect. The failure lists
/// every failing profile and every defect in it, not just the first.
///
/// Takes the same options as [pumpAtTextScale].
Future<void> expectNoTextScaleDefectsAcrossMatrix(
  WidgetTester tester,
  Widget widget, {
  List<TextScaleProfile> profiles = TextScaleProfile.standardMatrix,
  TextScaleHost host = TextScaleHost.component,
  ThemeData? theme,
  List<Finder> allowEllipsis = const <Finder>[],
  TextScaleAllowance? allow,
  Duration settle = const Duration(milliseconds: 500),
  bool pumpAndSettle = false,
  int frames = 1,
  double tolerance = 0.5,
  bool useAppFonts = true,
}) async {
  final List<TextScaleReport> reports = await pumpAcrossTextScaleMatrix(
    tester,
    widget,
    profiles: profiles,
    host: host,
    theme: theme,
    allowEllipsis: allowEllipsis,
    allow: allow,
    settle: settle,
    pumpAndSettle: pumpAndSettle,
    frames: frames,
    tolerance: tolerance,
    useAppFonts: useAppFonts,
  );
  final String? failure = describeTextScaleMatrixFailures(reports);
  if (failure != null) {
    fail(failure);
  }
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void _applyProfile(WidgetTester tester, TextScaleProfile profile) {
  final double dpr = profile.devicePixelRatio;
  final FakeViewPadding padding = FakeViewPadding(
    left: profile.safeArea.left * dpr,
    top: profile.safeArea.top * dpr,
    right: profile.safeArea.right * dpr,
    bottom: profile.safeArea.bottom * dpr,
  );
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = profile.screenSize * dpr;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.platformDispatcher.textScaleFactorTestValue = profile.textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(boldText: profile.boldText);

  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Widget _host(Widget widget, TextScaleHost host, ThemeData? theme) {
  switch (host) {
    case TextScaleHost.none:
      return widget;
    case TextScaleHost.screen:
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? nexGenPremiumDarkTheme,
        builder: TextScaleClamp.appBuilder,
        home: widget,
      );
    case TextScaleHost.component:
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? nexGenPremiumDarkTheme,
        builder: TextScaleClamp.appBuilder,
        home: Scaffold(
          body: SafeArea(
            child: Align(alignment: Alignment.topLeft, child: widget),
          ),
        ),
      );
  }
}

// ---------------------------------------------------------------------------
// Overflow
// ---------------------------------------------------------------------------

final RegExp _overflowSummary = RegExp(r'A Render\w+ overflowed');

String _summaryOf(FlutterErrorDetails details) {
  final Object exception = details.exception;
  final String full =
      exception is FlutterError ? exception.message : exception.toString();
  return full.split('\n').first;
}

bool _isOverflowError(FlutterErrorDetails details) {
  final String summary = _summaryOf(details);
  return summary.contains('overflowed by') ||
      _overflowSummary.hasMatch(summary);
}

List<TextScaleDefect> _overflowDefects(
  WidgetTester tester,
  List<FlutterErrorDetails> errors,
) {
  final List<TextScaleDefect> defects = <TextScaleDefect>[];
  final Set<RenderObject> reported = Set<RenderObject>.identity();

  for (final FlutterErrorDetails details in errors) {
    RenderObject? source;
    final Iterable<DiagnosticsNode> information =
        details.informationCollector?.call() ?? const <DiagnosticsNode>[];
    for (final DiagnosticsNode node in information) {
      final Object? value = node.value;
      if (value is RenderObject) {
        source = value;
      }
    }
    if (source != null && !reported.add(source)) {
      continue;
    }
    final String summary = _summaryOf(details);
    defects.add(
      TextScaleDefect(
        kind: TextScaleDefectKind.overflow,
        message: source is RenderBox && source.hasSize
            ? '$summary (box is ${_size(source.size)})'
            : summary,
        renderObject: source,
        creatorChain: source == null ? null : _creatorChain(source),
      ),
    );
  }

  // A flex that overflows but was never painted reports no error. The render
  // tree still knows.
  for (final RenderObject object in _visibleRenderObjects(tester)) {
    if (object is RenderFlex &&
        object.toStringShort().contains('OVERFLOWING') &&
        reported.add(object)) {
      final String axis =
          object.direction == Axis.horizontal ? 'horizontally' : 'vertically';
      defects.add(
        TextScaleDefect(
          kind: TextScaleDefectKind.overflow,
          message: 'A RenderFlex overflowed $axis '
              '(box is ${_size(object.size)}).',
          renderObject: object,
          creatorChain: _creatorChain(object),
        ),
      );
    }
  }
  return defects;
}

// ---------------------------------------------------------------------------
// Clipped text
// ---------------------------------------------------------------------------

List<TextScaleDefect> _textDefects(WidgetTester tester, double tolerance) {
  final List<TextScaleDefect> defects = <TextScaleDefect>[];
  for (final RenderObject object in _visibleRenderObjects(tester)) {
    if (object is RenderParagraph && object.hasSize) {
      defects.addAll(_paragraphDefects(object, tolerance));
    } else if (object is RenderEditable && object.hasSize) {
      defects.addAll(_editableDefects(object, tolerance));
    }
  }
  return defects;
}

Iterable<TextScaleDefect> _paragraphDefects(
  RenderParagraph paragraph,
  double tolerance,
) sync* {
  final String plain = paragraph.text.toPlainText();
  if (plain.trim().isEmpty) {
    return;
  }
  final String text = _quote(plain);
  final String chain = _creatorChain(paragraph);
  final Size box = paragraph.size;
  final Size needed = paragraph.textSize;

  if (paragraph.didExceedMaxLines) {
    final String limit = paragraph.maxLines == null
        ? 'was ellipsized'
        : 'hit maxLines: ${paragraph.maxLines}';
    yield TextScaleDefect(
      kind: TextScaleDefectKind.truncatedText,
      message: '$text $limit at width ${_fmt(box.width)} and is cut short.',
      renderObject: paragraph,
      text: plain,
      creatorChain: chain,
    );
  } else if (needed.width > box.width + tolerance) {
    yield TextScaleDefect(
      kind: TextScaleDefectKind.truncatedText,
      message: '$text is ${_fmt(needed.width)} wide but its box is '
          '${_fmt(box.width)} wide, and it cannot wrap '
          '(softWrap: ${paragraph.softWrap}, '
          'overflow: ${paragraph.overflow.name}).',
      renderObject: paragraph,
      text: plain,
      creatorChain: chain,
    );
  }

  if (needed.height > box.height + tolerance) {
    yield TextScaleDefect(
      kind: TextScaleDefectKind.textTallerThanBox,
      message: '$text needs ${_fmt(needed.height)} of height at width '
          '${_fmt(box.width)} but its box is ${_fmt(box.height)} tall.',
      renderObject: paragraph,
      text: plain,
      creatorChain: chain,
    );
  }

  final String? clip = _clippedBy(paragraph, tolerance);
  if (clip != null) {
    yield TextScaleDefect(
      kind: TextScaleDefectKind.clippedByAncestor,
      message: '$text $clip',
      renderObject: paragraph,
      text: plain,
      creatorChain: chain,
    );
  }
}

Iterable<TextScaleDefect> _editableDefects(
  RenderEditable editable,
  double tolerance,
) sync* {
  final String chain = _creatorChain(editable);
  final String? plain = editable.text?.toPlainText();
  final String text = _quote(plain ?? '');
  if (editable.preferredLineHeight > editable.size.height + tolerance) {
    yield TextScaleDefect(
      kind: TextScaleDefectKind.textFieldTooShort,
      message: 'Text field $text needs ${_fmt(editable.preferredLineHeight)} '
          'for one line but is ${_fmt(editable.size.height)} tall.',
      renderObject: editable,
      text: plain,
      creatorChain: chain,
    );
  }
  final String? clip = _clippedBy(editable, tolerance);
  if (clip != null) {
    yield TextScaleDefect(
      kind: TextScaleDefectKind.clippedByAncestor,
      message: 'Text field $text $clip',
      renderObject: editable,
      text: plain,
      creatorChain: chain,
    );
  }
}

/// Describes how [box] is cut off by a clipping ancestor or the screen, or
/// returns `null` if all of it can be seen or scrolled to.
String? _clippedBy(RenderBox box, double tolerance) {
  final RenderObject root = box.owner!.rootNode!;
  final Rect bounds = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );

  // Once the text is inside something that scrolls along an axis, being out
  // of view along that axis is not a defect: the user can scroll to it.
  bool scrollsHorizontally = false;
  bool scrollsVertically = false;

  String? check(Rect clip, String clipper) {
    final List<String> sides = <String>[
      if (!scrollsHorizontally && bounds.left < clip.left - tolerance)
        '${_fmt(clip.left - bounds.left)} on the left',
      if (!scrollsHorizontally && bounds.right > clip.right + tolerance)
        '${_fmt(bounds.right - clip.right)} on the right',
      if (!scrollsVertically && bounds.top < clip.top - tolerance)
        '${_fmt(clip.top - bounds.top)} at the top',
      if (!scrollsVertically && bounds.bottom > clip.bottom + tolerance)
        '${_fmt(bounds.bottom - clip.bottom)} at the bottom',
    ];
    if (sides.isEmpty) {
      return null;
    }
    return 'extends ${sides.join(' and ')} outside $clipper.';
  }

  RenderObject child = box;
  RenderObject? ancestor = box.parent;
  while (ancestor != null && !identical(ancestor, root)) {
    final Axis? scrollAxis = _scrollAxisOf(ancestor);
    if (scrollAxis == Axis.horizontal) {
      scrollsHorizontally = true;
    } else if (scrollAxis == Axis.vertical) {
      scrollsVertically = true;
    }

    final Rect? localClip = ancestor.describeApproximatePaintClip(child);
    if (localClip != null) {
      final Rect clip = MatrixUtils.transformRect(
        ancestor.getTransformTo(null),
        localClip,
      );
      final String? result = check(
        clip,
        'the clip of ${ancestor.runtimeType} '
        '(${_creatorChain(ancestor, depth: 3)})',
      );
      if (result != null) {
        return result;
      }
    }
    child = ancestor;
    ancestor = ancestor.parent;
  }

  if (root is RenderView && root.child != null) {
    return check(Offset.zero & root.child!.size, 'the screen');
  }
  return null;
}

/// The axis [object] scrolls along, or `null` if it is not a viewport or its
/// scrolling is switched off with `NeverScrollableScrollPhysics`.
Axis? _scrollAxisOf(RenderObject object) {
  if (object is! RenderAbstractViewport) {
    return null;
  }
  final Object? creator = object.debugCreator;
  final Scrollable? scrollable = creator is DebugCreator
      ? creator.element.findAncestorWidgetOfExactType<Scrollable>()
      : null;
  if (scrollable?.physics is NeverScrollableScrollPhysics) {
    return null;
  }
  if (object is RenderViewportBase) {
    return object.axis;
  }
  if (scrollable != null) {
    return axisDirectionToAxis(scrollable.axisDirection);
  }
  return Axis.vertical;
}

// ---------------------------------------------------------------------------
// Tree walking
// ---------------------------------------------------------------------------

/// Every render object that is on stage: skips offstage subtrees, the hidden
/// children of an `IndexedStack`, fully transparent subtrees, routes below
/// the top one, and list children outside the viewport's cache.
List<RenderObject> _visibleRenderObjects(WidgetTester tester) {
  final List<RenderObject> result = <RenderObject>[];
  void visit(RenderObject object) {
    result.add(object);
    if (object is RenderExcludeSemantics) {
      // Excluded from semantics is not hidden from sight.
      object.visitChildren(visit);
    } else {
      object.visitChildrenForSemantics(visit);
    }
  }

  for (final RenderView view in tester.binding.renderViews) {
    visit(view);
  }
  return result;
}

Set<RenderObject> _renderObjectsUnder(List<Finder> finders) {
  final Set<RenderObject> result = Set<RenderObject>.identity();
  void collect(RenderObject object) {
    result.add(object);
    object.visitChildren(collect);
  }

  for (final Finder finder in finders) {
    for (final Element element in finder.evaluate()) {
      final RenderObject? object = element.renderObject;
      if (object != null) {
        collect(object);
      }
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

String _creatorChain(RenderObject object, {int depth = 8}) {
  final Object? creator = object.debugCreator;
  if (creator is DebugCreator) {
    return creator.element.debugGetCreatorChain(depth);
  }
  return object.runtimeType.toString();
}

String _quote(String text) {
  final String flat = text.replaceAll('\n', ' ').trim();
  return flat.length <= 60 ? '"$flat"' : '"${flat.substring(0, 57)}..."';
}

String _size(Size size) => '${_fmt(size.width)}x${_fmt(size.height)}';

String _fmt(double value) {
  final String fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
