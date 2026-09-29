# Accessibility text-scale testing

Every screen must stay usable when the user has turned on **Larger Text** and
**Bold Text**. This document describes the shared test harness that checks
that, how packages B through G run their own screens through it, and the
patterns to use when a screen fails.

| Piece | File |
| --- | --- |
| Test harness | `test/helpers/text_scale_harness.dart` |
| Harness self-tests | `test/helpers/text_scale_harness_test.dart` |
| App-wide 2.0x cap | `lib/shared/accessibility/text_scale_clamp.dart` |
| Shipped font weights | `lib/shared/fonts/bundled_font_weights.dart`, `assets/google_fonts/` |

## The default profile

| Setting | Value |
| --- | --- |
| Text scale | `TextScaler.linear(1.75)` |
| Bold Text | on |
| Screen | 390 x 844 logical points |
| Device pixel ratio | 3.0 |
| Safe area | top 47, bottom 34 |

The standard matrix is **1.0, 1.75 and 2.0**, all with Bold Text on. 1.0 is in
the matrix because some rows overflow a 390 point screen before any scaling is
applied. 2.0 is the most the app will ever lay out at (see
[The 2.0x cap](#the-20x-cap)).

Bold Text matters as much as the scale. With it on, Flutter merges weight 700
into every text run, and bold glyphs are wider.

## Running a widget through it

```dart
import 'package:flutter_test/flutter_test.dart';

// Relative import; adjust the number of `../` to your test file's depth.
import '../../helpers/text_scale_harness.dart';

void main() {
  testWidgets('team row survives large text', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(tester, const TeamRow());
  });
}
```

That is the whole test for a component. It fails if the widget has a defect at
any of the three scales, and the failure names every failing scale and every
defect in it.

### A whole screen

A widget that builds its own `Scaffold` is hosted as the `home:` of the app:

```dart
await expectNoTextScaleDefectsAcrossMatrix(
  tester,
  const GameDayScreen(),
  host: TextScaleHost.screen,
);
```

### A screen that needs providers or a router

Wrap it yourself. The harness hosts whatever widget it is given, so put the
`ProviderScope` and its overrides around your screen:

```dart
await expectNoTextScaleDefectsAcrossMatrix(
  tester,
  ProviderScope(
    overrides: [/* fakes */],
    child: const GameDayScreen(),
  ),
  host: TextScaleHost.screen,
);
```

If the test must own the `MaterialApp` (for example to supply a `GoRouter`),
use `TextScaleHost.none` and install the cap yourself, so the test lays out
the way the app does:

```dart
await expectNoTextScaleDefectsAcrossMatrix(
  tester,
  MaterialApp.router(
    theme: nexGenPremiumDarkTheme,
    builder: TextScaleClamp.appBuilder,
    routerConfig: router,
  ),
  host: TextScaleHost.none,
);
```

### One profile, or a different one

```dart
// Default profile: 1.75x, bold, 390x844.
await expectNoTextScaleDefects(tester, const TeamRow());

// Any other combination.
await expectNoTextScaleDefects(
  tester,
  const TeamRow(),
  profile: const TextScaleProfile(
    textScale: 1.3,
    boldText: false,
    screenSize: Size(320, 568),
    devicePixelRatio: 2.0,
  ),
);
```

### Inspecting instead of failing

`pumpAtTextScale` and `pumpAcrossTextScaleMatrix` return reports and never
fail the test. Use them to assert on a specific defect, or to go on and
interact with the widget at that scale:

```dart
final report = await pumpAtTextScale(tester, const TeamRow());
expect(report.defects, isEmpty, reason: report.describe());
await tester.tap(find.text('Choose a team'));
```

### Widgets that animate forever

The harness pumps one frame and then 500 ms. It does not call
`pumpAndSettle`, because a screen with a looping animation never settles. For
a widget that does settle, pass `pumpAndSettle: true`; to wait longer, pass
`settle:`.

### Sheets and dialogs

A bottom sheet or dialog is a ROUTE, pushed onto the app's navigator above
`home:`. Two things follow:

* Put the `ProviderScope` **above** the `MaterialApp`, so use
  `TextScaleHost.none` and install the cap yourself (see above). A scope
  inside `home:` is not an ancestor of the sheet.
* Open it from a post-frame callback in a small host widget, and pass
  `frames:` so the entrance animation runs. The harness builds a fresh tree
  for every profile and measures one frame later by default, which would
  measure the sheet still closed.

```dart
await expectNoTextScaleDefectsAcrossMatrix(
  tester,
  ProviderScope(
    overrides: [/* fakes */],
    child: MaterialApp(
      theme: nexGenPremiumDarkTheme,
      builder: TextScaleClamp.appBuilder,
      home: const OpensMySheet(), // calls showModalBottomSheet post-frame
    ),
  ),
  host: TextScaleHost.none,
  settle: const Duration(milliseconds: 900),
  frames: 6,
);
```

`test/features/ai/lumina_text_scale_test.dart` does this for the Lumina sheet.

## What it checks

| Kind | Meaning |
| --- | --- |
| `overflow` | A `Row`, `Column` or `Flex` is too small for its children (the yellow and black stripes). Every overflow error raised while pumping is collected, plus any flex the render tree marks as overflowing without having painted. |
| `truncatedText` | Text hit `maxLines` or was ellipsized, or cannot wrap (`softWrap: false`) and is wider than its box. |
| `textTallerThanBox` | Text was given a box shorter than the lines it laid out. The usual cause is a fixed height around text. |
| `clippedByAncestor` | Text or a text field extends outside an ancestor that clips, or outside the screen, along an axis that cannot be scrolled. |
| `textFieldTooShort` | A text field is shorter than one line of its own text. |

Each defect carries the text affected, measurements, and the chain of widgets
that created it, innermost first:

```
2 of 3 text-scale profiles failed (1.75x, 2.0x).
3 text-scale defects at 1.75x, bold on, 390x844 @3.0x:
  1. [overflow] A RenderFlex overflowed by 112 pixels on the right. (box is 390x40)
      widget: Row ← GameRow ← Align ← MediaQuery ← Padding ← SafeArea ← ⋯
  2. [textTallerThanBox] "Sunday 7:20 PM" needs 40 of height at width 219.2 but its box is 28 tall.
      widget: RichText ← Text ← SizedBox ← Row ← GameRow ← Align ← ⋯
  3. [clippedByAncestor] "Sunday 7:20 PM" extends 112.4 on the right outside the screen.
      widget: RichText ← Text ← SizedBox ← Row ← GameRow ← Align ← ⋯
```

An error that is not an overflow is handed back to the test framework, so the
test still fails on it as usual.

Text is measured with the fonts the app ships, not the test engine's
placeholder font, so widths are the widths a device produces.

## Allowing a label that is truncated on purpose

The harness is strict by default: any truncated text fails. Some labels are
meant to be cut short — a user-supplied controller name in a list row, for
example. Allow those one by one, by finder:

```dart
await expectNoTextScaleDefectsAcrossMatrix(
  tester,
  const ControllerRow(),
  allowEllipsis: [find.byKey(const ValueKey('controller-name'))],
);
```

`allowEllipsis` excuses `truncatedText` for text at or below the widgets the
finders match, and nothing else. It does not excuse overflow or clipping, and
it does not excuse other labels.

Use it only when all of these hold:

* the text is data, not interface copy;
* the full text is available somewhere else (a detail screen, a tooltip);
* the label has at least two lines at large sizes, or the row is no use
  without truncation.

A button label, a heading or a setting name is never a candidate. Fix those.

For anything else there is a predicate. It can excuse a defect of any kind,
so make it as narrow as possible and leave a comment saying why:

```dart
allow: (defect) =>
    defect.kind == TextScaleDefectKind.clippedByAncestor &&
    defect.text == 'LIVE', // marquee badge, clipped by design
```

Allowed defects are still recorded, in `report.allowed`.

## Fix patterns

### No fixed heights around text

A `SizedBox(height:)`, `Container(height:)` or `itemExtent:` around text is
right at exactly one text size.

```dart
// Breaks above 1.0x.
SizedBox(height: 48, child: Row(children: [...]))

// Minimum instead of fixed: 48 at default size, taller when it needs to be.
ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 48),
  child: Row(children: [...]),
)
```

The same goes for `AppBar(toolbarHeight:)`, `ListTile` inside a fixed-extent
list, grid tiles with a fixed `childAspectRatio`, and bottom sheets with a
fixed height. Prefer padding plus intrinsic height; for grids use
`mainAxisExtent` computed from the text scale, or a list at large sizes.

### Labels wrap, or scale down

Let copy wrap. Do not add `maxLines: 1` to make a row look tidy.

```dart
const Text('Follow every game this season') // wraps
```

Where a label must stay on one line — a large title, a number in a tile —
scale it down to fit rather than cutting it:

```dart
FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerLeft,
  child: Text('LUMINA', style: titleStyle),
)
```

`FittedBox` shrinks the text below the size the user asked for, so keep it
for short display text. Body copy and button labels wrap.

### Buttons size to their content

```dart
// Breaks: the label is clipped at large sizes.
SizedBox(height: 44, width: 160, child: FilledButton(...))

// Grows with its label; still at least 44 tall.
FilledButton(
  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
  onPressed: onPressed,
  child: const Text('Choose a team'),
)
```

Two buttons side by side: put them in a `Wrap`, or stack them in a `Column`
when the text scale is large.

### Rows reflow

Every `Text` in a `Row` that is not inside `Expanded` or `Flexible` is a
future overflow.

```dart
// Text takes the space that is left, and wraps inside it.
Row(children: [
  const Icon(Icons.sports_football),
  const SizedBox(width: 12),
  const Expanded(child: Text('Follow every game this season')),
  Switch(value: on, onChanged: onChanged),
])

// Chips, badges, a label and its value: let them move to the next line.
Wrap(spacing: 12, runSpacing: 4, children: [
  Text(teamName),
  Text(kickoff),
])
```

When a row has two pieces of text that both matter, give both a `Flexible`,
or switch to a `Column` at large sizes:

```dart
final bool large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
return large
    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: parts)
    : Row(children: parts);
```

### Everything scrolls

Any screen that fits at 1.0x is taller than the screen at 1.75x. The body of
every screen, sheet and dialog must be able to scroll.

### Do not

* Do not override `textScaler` or wrap a screen in
  `MediaQuery.withNoTextScaling` or `withClampedTextScaling` to make a layout
  fit. That takes the user's setting away. The only cap is the one at the app
  root.
* Do not set `fontWeight` to counteract Bold Text.
* Do not paint text with a bare `TextPainter`; it ignores the text scale
  unless you pass `textScaler: MediaQuery.textScalerOf(context)`.

## The 2.0x cap

The platform accessibility slider goes to roughly 3.1x. The app caps what it
lays out at **2.0x**, once, at the root:

```dart
MaterialApp.router(
  builder: TextScaleClamp.appBuilder,
  // ...
)
```

* `kMaxTextScaleFactor` is `2.0`.
* It is a maximum only. There is no minimum; a user who picks a size below
  2.0x, including below 1.0x, gets exactly that size.
* It must never be lowered to 1.75 or below. 1.75x is the size screens are
  tested at, and it has to be reachable.
* `boldText`, and every other `MediaQuery` value, passes through unchanged.
* It is a backstop, not a design target. Screens are expected to work at
  2.0x; the cap only exists so that nothing has to work at 3.1x.

If the app ever needs another root `builder:`, wrap it rather than replacing
the cap: `builder: TextScaleClamp.compose(existingBuilder)`.

The harness hosts widgets under the same cap, so a profile above 2.0 is laid
out at 2.0, as on a device.

## Fonts

The app ships static font files for every weight it requests, including
weight 700 for every family, in `assets/google_fonts/`. Two things follow for
anyone adding text:

* **A new weight or family needs a new file.** If a widget requests a weight
  that is not shipped, the engine synthesises it. Add the static file, declare
  it in `pubspec.yaml`, and add the weight to `kBundledFontFamilies`.
  `test/shared/fonts/` checks each file's real weight from its `OS/2` table.
* **Italic is not shipped.** Italic text is drawn by slanting the upright
  face.

## What the harness does not catch

* **Overlap.** Two widgets drawn on top of each other in a `Stack` do not
  overflow and are not clipped.
* **Text that shrinks.** `FittedBox` and similar make text fit by making it
  smaller; the harness passes it however small it gets.
* **Custom-painted text.** Text drawn with `TextPainter` in a `CustomPainter`
  is not in the render tree as a paragraph.
* **Clips the framework does not describe.** Clipping is detected through
  `describeApproximatePaintClip`. A `Container` with `clipBehavior` and a
  decoration, `ClipPath`, and `PhysicalModel` report their bounding box, not
  their shape; a custom render object reports nothing unless it implements
  the method.
* **Content that needs scrolling to reach.** Text below the fold of a
  scrolling view is not a defect, and is not laid out if it is lazily built,
  so it is not checked either. Scroll in the test and run the check again.
* **States the test does not build.** Dialogs, sheets, error states, loading
  states and long data each need their own run.
* **Touch target size, contrast and screen-reader labels.**
* **The platform's own rendering.** Line heights differ slightly between the
  test engine and a device. A layout that passes with no room to spare can
  still clip on a device; leave slack rather than tuning to the pixel.
* **Nothing above 2.0x**, because the app never lays out above it.

A pass means the states that were built have no overflow and no clipped text
at those sizes. It does not replace looking at the screen on a device with
Larger Text and Bold Text turned on.
