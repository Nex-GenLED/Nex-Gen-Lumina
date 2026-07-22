import 'package:flutter/painting.dart';

/// THE single source of truth for projecting normalized roofline trace points
/// into screen (canvas-pixel) coordinates.
///
/// A roofline trace stores points as normalized `0..1` coordinates relative to
/// the photo they were drawn on. To render them on top of that photo they must
/// be mapped through the *same* fit the photo itself uses (BoxFit.cover on both
/// the dashboard overlay and the Design Studio preview). Historically this math
/// was duplicated — `RooflineMask.getPointsForCover` and a private
/// `_transformPointsForCover` in the painter — and the Design Studio path fed it
/// no source aspect ratio, so its cover compensation silently no-op'd and the
/// roofline rendered low + flattened. Both surfaces now route through this one
/// function so their geometry can never drift again (see the parity test in
/// test/widgets/roofline_projection_test.dart).
///
/// Given a photo of aspect [sourceAspectRatio] (width / height) fitted into
/// [canvasSize] under [fit]:
///
/// - [BoxFit.cover] scales the photo to *fill* the canvas (max scale), cropping
///   the overflow axis. Points that fall in the cropped-away band land outside
///   the canvas; they are clamped back to it when [clampToCanvas] is true
///   (matching the legacy behaviour). This is the mode both live surfaces use.
/// - [BoxFit.contain] scales the photo to *fit inside* the canvas (min scale),
///   letterboxing the short axis. Points map into the letterboxed rect.
/// - [BoxFit.fill] stretches the photo to the canvas on both axes independently
///   — the legacy "raw" `dx * width, dy * height` map. [sourceAspectRatio] and
///   [alignment] are ignored in this mode.
///
/// [alignment] follows Flutter's `Alignment` convention: `-1..1` per axis with
/// `0` = centered. For cover it selects which slice of the overflow is visible;
/// for contain it positions the image within the letterbox.
List<Offset> projectRoofline({
  required List<Offset> normalized,
  required Size canvasSize,
  required double sourceAspectRatio,
  BoxFit fit = BoxFit.cover,
  Offset alignment = Offset.zero,
  bool clampToCanvas = true,
}) {
  final w = canvasSize.width;
  final h = canvasSize.height;
  if (normalized.isEmpty || w <= 0 || h <= 0) return const [];

  // BoxFit.fill — or a degenerate/unknown source aspect — is a straight stretch
  // map (the legacy raw projection). Aspect + alignment do not apply.
  if (fit == BoxFit.fill ||
      !sourceAspectRatio.isFinite ||
      sourceAspectRatio <= 0) {
    return [
      for (final p in normalized)
        _clamp(Offset(p.dx * w, p.dy * h), w, h, clampToCanvas),
    ];
  }

  // Model the source as unit-height: imgW = aspect, imgH = 1. Cover fills the
  // canvas (max scale → overflow cropped); contain fits inside it (min scale →
  // letterbox). This single max/min switch reproduces the old cover math on
  // both axes exactly and generalizes cleanly to contain.
  final imgW = sourceAspectRatio;
  const imgH = 1.0;
  final sx = w / imgW;
  final sy = h / imgH;
  final scale = fit == BoxFit.cover
      ? (sx > sy ? sx : sy)
      : (sx < sy ? sx : sy);

  final fittedW = imgW * scale;
  final fittedH = imgH * scale;

  // alignment -1..1 → 0..1 fraction of the leftover space (which is negative
  // under cover, so the fitted image extends beyond the canvas and is cropped).
  final offsetX = (w - fittedW) * (0.5 + alignment.dx * 0.5);
  final offsetY = (h - fittedH) * (0.5 + alignment.dy * 0.5);

  return [
    for (final p in normalized)
      _clamp(
        Offset(offsetX + p.dx * fittedW, offsetY + p.dy * fittedH),
        w,
        h,
        clampToCanvas,
      ),
  ];
}

Offset _clamp(Offset o, double w, double h, bool on) =>
    on ? Offset(o.dx.clamp(0.0, w), o.dy.clamp(0.0, h)) : o;
