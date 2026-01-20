import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/theme.dart';

/// Interactive canvas widget for drawing roofline path on a house image.
///
/// Users tap to add points, creating a polyline that traces the roofline.
/// Points are stored as normalized 0-1 coordinates for resolution independence.
class RooflineEditor extends StatefulWidget {
  /// The house image to draw over
  final ImageProvider imageProvider;

  /// Initial roofline mask (if editing existing)
  final RooflineMask? initialMask;

  /// Callback when the roofline changes
  final void Function(RooflineMask mask)? onChanged;

  const RooflineEditor({
    super.key,
    required this.imageProvider,
    this.initialMask,
    this.onChanged,
  });

  @override
  State<RooflineEditor> createState() => RooflineEditorState();
}

class RooflineEditorState extends State<RooflineEditor> {
  List<Offset> _points = [];
  Size _imageSize = Size.zero;
  ui.Image? _loadedImage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
    // Load initial points if provided
    if (widget.initialMask != null && widget.initialMask!.hasCustomPoints) {
      _points = List.from(widget.initialMask!.points);
    }
  }

  @override
  void didUpdateWidget(RooflineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() => _isLoading = true);
    try {
      final stream = widget.imageProvider.resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image>();
      final listener = ImageStreamListener(
        (info, _) => completer.complete(info.image),
        onError: (error, stack) => completer.completeError(error),
      );
      stream.addListener(listener);
      final image = await completer.future;
      stream.removeListener(listener);

      if (mounted) {
        setState(() {
          _loadedImage = image;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('RooflineEditor: Failed to load image: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Get the current roofline mask
  RooflineMask getMask() {
    return RooflineMask(
      points: List.from(_points),
      maskHeight: 0.25, // Keep default as fallback
      isManuallyDrawn: _points.isNotEmpty,
    );
  }

  /// Clear all points
  void clear() {
    setState(() => _points = []);
    _notifyChange();
  }

  /// Undo last point
  void undo() {
    if (_points.isNotEmpty) {
      setState(() => _points.removeLast());
      _notifyChange();
    }
  }

  /// Check if there are points to undo
  bool get canUndo => _points.isNotEmpty;

  /// Check if there are enough points for a valid roofline
  bool get hasValidRoofline => _points.length >= 2;

  void _notifyChange() {
    widget.onChanged?.call(getMask());
  }

  void _onTapDown(TapDownDetails details, Size canvasSize) {
    if (_loadedImage == null) return;

    // Convert tap position to normalized coordinates (0-1)
    final normalized = Offset(
      details.localPosition.dx / canvasSize.width,
      details.localPosition.dy / canvasSize.height,
    );

    // Clamp to valid range
    final clamped = Offset(
      normalized.dx.clamp(0.0, 1.0),
      normalized.dy.clamp(0.0, 1.0),
    );

    setState(() => _points.add(clamped));
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      );
    }

    if (_loadedImage == null) {
      return const Center(
        child: Text('Failed to load image'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the fitted image size within constraints
        final fittedSize = _calculateFittedSize(constraints.biggest);

        return Center(
          child: GestureDetector(
            onTapDown: (details) => _onTapDown(details, fittedSize),
            child: SizedBox(
              width: fittedSize.width,
              height: fittedSize.height,
              child: Stack(
                children: [
                  // House image
                  Positioned.fill(
                    child: Image(
                      image: widget.imageProvider,
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Drawing overlay
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RooflineDrawingPainter(
                        points: _points,
                        imageSize: fittedSize,
                      ),
                    ),
                  ),
                  // Light preview overlay (semi-transparent)
                  if (_points.length >= 2)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RooflinePreviewPainter(
                          points: _points,
                          imageSize: fittedSize,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Size _calculateFittedSize(Size constraints) {
    if (_imageSize == Size.zero) return constraints;

    final imageAspect = _imageSize.width / _imageSize.height;
    final constraintAspect = constraints.width / constraints.height;

    if (imageAspect > constraintAspect) {
      // Image is wider - fit to width
      return Size(constraints.width, constraints.width / imageAspect);
    } else {
      // Image is taller - fit to height
      return Size(constraints.height * imageAspect, constraints.height);
    }
  }
}

/// Paints the roofline drawing (points and connecting lines)
class _RooflineDrawingPainter extends CustomPainter {
  final List<Offset> points;
  final Size imageSize;

  _RooflineDrawingPainter({
    required this.points,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Convert normalized points to canvas coordinates
    final canvasPoints = points
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();

    // Draw connecting lines
    if (canvasPoints.length >= 2) {
      final linePaint = Paint()
        ..color = NexGenPalette.cyan
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()..moveTo(canvasPoints.first.dx, canvasPoints.first.dy);
      for (int i = 1; i < canvasPoints.length; i++) {
        path.lineTo(canvasPoints[i].dx, canvasPoints[i].dy);
      }
      canvas.drawPath(path, linePaint);

      // Draw glow effect
      final glowPaint = Paint()
        ..color = NexGenPalette.cyan.withValues(alpha: 0.3)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(path, glowPaint);
    }

    // Draw points
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final pointBorderPaint = Paint()
      ..color = NexGenPalette.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < canvasPoints.length; i++) {
      final point = canvasPoints[i];
      // Draw point
      canvas.drawCircle(point, 8, pointPaint);
      canvas.drawCircle(point, 8, pointBorderPaint);

      // Draw point number
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: NexGenPalette.cyan,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(point.dx - textPainter.width / 2, point.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RooflineDrawingPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

/// Paints a preview of where the lights will appear
class _RooflinePreviewPainter extends CustomPainter {
  final List<Offset> points;
  final Size imageSize;

  _RooflinePreviewPainter({
    required this.points,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Convert normalized points to canvas coordinates
    final canvasPoints = points
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();

    // Create a path for the roofline
    final path = Path()..moveTo(canvasPoints.first.dx, canvasPoints.first.dy);
    for (int i = 1; i < canvasPoints.length; i++) {
      path.lineTo(canvasPoints[i].dx, canvasPoints[i].dy);
    }

    // Draw glowing "lights" effect along the path
    final glowPaint = Paint()
      ..color = NexGenPalette.cyan.withValues(alpha: 0.4)
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(_RooflinePreviewPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

/// Control bar with undo/clear/save actions
class RooflineEditorControls extends StatelessWidget {
  final VoidCallback? onUndo;
  final VoidCallback? onClear;
  final VoidCallback? onSave;
  final bool canUndo;
  final bool canSave;

  const RooflineEditorControls({
    super.key,
    this.onUndo,
    this.onClear,
    this.onSave,
    this.canUndo = false,
    this.canSave = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Undo button
        _ControlButton(
          icon: Icons.undo,
          label: 'Undo',
          onTap: canUndo ? onUndo : null,
        ),
        const SizedBox(width: 16),
        // Clear button
        _ControlButton(
          icon: Icons.clear_all,
          label: 'Clear',
          onTap: canUndo ? onClear : null,
        ),
        const SizedBox(width: 16),
        // Save button
        _ControlButton(
          icon: Icons.check,
          label: 'Save',
          onTap: canSave ? onSave : null,
          isPrimary: true,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final backgroundColor = isPrimary
        ? (isEnabled ? NexGenPalette.cyan : NexGenPalette.gunmetal50)
        : NexGenPalette.gunmetal90;
    final foregroundColor = isPrimary
        ? (isEnabled ? Colors.black : Colors.white38)
        : (isEnabled ? Colors.white : Colors.white38);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary && isEnabled
                  ? NexGenPalette.cyan
                  : NexGenPalette.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foregroundColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
