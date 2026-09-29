import 'package:flutter/widgets.dart';

/// The largest text scale factor the app lays out at.
///
/// The platform accessibility slider reaches roughly 3.1x. Every screen is
/// expected to stay usable up to this value; anything the platform asks for
/// beyond it is capped here so the layout never has to cope with 3x text.
///
/// This is a backstop, not a design target, and it is deliberately a maximum
/// only. It must stay above 1.75 — the scale the app is tested at — and there
/// is no minimum: a user who picks a smaller or larger size inside the range
/// gets exactly the size they chose.
const double kMaxTextScaleFactor = 2.0;

/// The cap may never be set at or below this. 1.75x is the size every screen
/// is tested at (`test/helpers/text_scale_harness.dart`), so a cap here or
/// lower would take a tested, supported size away from the user.
const double kMinPermittedTextScaleCap = 1.75;

/// Caps the ambient [MediaQueryData.textScaler] at [maxScaleFactor] for
/// everything below it, leaving every other [MediaQueryData] field — including
/// [MediaQueryData.boldText] — untouched.
///
/// Adopt it once, at the app root:
///
/// ```dart
/// MaterialApp.router(
///   builder: TextScaleClamp.appBuilder,
///   // ...
/// )
/// ```
///
/// If the app already has a `builder:`, keep it and wrap it with
/// [TextScaleClamp.compose].
class TextScaleClamp extends StatelessWidget {
  const TextScaleClamp({
    super.key,
    required this.child,
    this.maxScaleFactor = kMaxTextScaleFactor,
  }) : assert(
          maxScaleFactor > kMinPermittedTextScaleCap,
          'The cap must stay above $kMinPermittedTextScaleCap: that is the '
          'size screens are tested at, and a user must be able to reach it.',
        );

  /// The subtree that sees the capped scaler.
  final Widget child;

  /// The cap. Defaults to [kMaxTextScaleFactor].
  final double maxScaleFactor;

  /// Returns [scaler] capped at [maxScaleFactor].
  ///
  /// No minimum is applied. A scaler that is already within the cap scales
  /// every font size exactly as it did before.
  static TextScaler clampScaler(
    TextScaler scaler, {
    double maxScaleFactor = kMaxTextScaleFactor,
  }) {
    return scaler.clamp(maxScaleFactor: maxScaleFactor);
  }

  /// A `builder:` for `MaterialApp` / `MaterialApp.router` that applies the
  /// default cap.
  static Widget appBuilder(BuildContext context, Widget? child) {
    return TextScaleClamp(child: child ?? const SizedBox.shrink());
  }

  /// Wraps an existing app `builder:` so that it, and everything it builds,
  /// sees the capped scaler.
  static TransitionBuilder compose(
    TransitionBuilder? inner, {
    double maxScaleFactor = kMaxTextScaleFactor,
  }) {
    return (BuildContext context, Widget? child) {
      return TextScaleClamp(
        maxScaleFactor: maxScaleFactor,
        child: inner == null
            ? child ?? const SizedBox.shrink()
            : Builder(
                builder: (BuildContext innerContext) =>
                    inner(innerContext, child),
              ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData data = MediaQuery.of(context);
    return MediaQuery(
      data: data.copyWith(
        textScaler: clampScaler(
          data.textScaler,
          maxScaleFactor: maxScaleFactor,
        ),
      ),
      child: child,
    );
  }
}
