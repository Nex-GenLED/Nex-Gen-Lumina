import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// Interactive multi-segment canvas widget for tracing roofline on a house image.
///
/// Supports:
/// - Multiple independent segments, each with its own channel/story/label
/// - Tap to place points, drag handles to reposition
/// - Per-segment color coding by channel index
/// - Segment selection and editing
class RooflineEditor extends StatefulWidget {
  /// The house image to draw over
  final ImageProvider imageProvider;

  /// Initial roofline mask (legacy single-path, used for migration)
  final RooflineMask? initialMask;

  /// Initial segments (multi-segment mode)
  final List<RooflineSegment>? initialSegments;

  /// Callback when segments change
  final void Function(List<RooflineSegment> segments)? onSegmentsChanged;

  /// Legacy callback for single-path mode (still supported for backward compat)
  final void Function(RooflineMask mask)? onChanged;

  const RooflineEditor({
    super.key,
    required this.imageProvider,
    this.initialMask,
    this.initialSegments,
    this.onSegmentsChanged,
    this.onChanged,
  });

  @override
  State<RooflineEditor> createState() => RooflineEditorState();
}

class RooflineEditorState extends State<RooflineEditor> {
  /// All traced segments
  List<_EditableSegment> _segments = [];

  /// Index of the currently active (being traced / selected) segment
  int? _activeSegmentIndex;

  /// Index of the point being dragged within the active segment
  int? _draggingPointIndex;

  Size _imageSize = Size.zero;
  ui.Image? _loadedImage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();

    // Initialize from multi-segment data if available
    if (widget.initialSegments != null && widget.initialSegments!.isNotEmpty) {
      _segments = widget.initialSegments!
          .map((s) => _EditableSegment.fromRooflineSegment(s))
          .toList();
      if (_segments.isNotEmpty) _activeSegmentIndex = 0;
    } else if (widget.initialMask != null && widget.initialMask!.hasCustomPoints) {
      // Legacy migration: wrap single path as one segment
      _segments = [
        _EditableSegment(
          label: 'Main Roofline',
          channelIndex: 0,
          storyLevel: 1,
          points: List.from(widget.initialMask!.points),
        ),
      ];
      _activeSegmentIndex = 0;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Get the image provider for external use (e.g. auto-detect).
  ImageProvider get currentImageProvider => widget.imageProvider;

  /// Get a legacy RooflineMask from the current state (first segment's points).
  RooflineMask getMask() {
    double? aspectRatio;
    if (_imageSize != Size.zero) {
      aspectRatio = _imageSize.width / _imageSize.height;
    }
    final allPoints = _segments.expand((s) => s.points).toList();
    return RooflineMask(
      points: allPoints,
      maskHeight: 0.25,
      isManuallyDrawn: allPoints.isNotEmpty,
      sourceAspectRatio: aspectRatio,
    );
  }

  /// Get all segments as RooflineSegment models.
  List<RooflineSegment> getSegments() {
    return _segments
        .asMap()
        .entries
        .map((e) => e.value.toRooflineSegment(sortOrder: e.key))
        .toList();
  }

  /// The number of segments.
  int get segmentCount => _segments.length;

  /// The currently active segment index (or null if none).
  int? get activeSegmentIndex => _activeSegmentIndex;

  /// Whether any segment has enough points to save.
  bool get hasValidRoofline => _segments.any((s) => s.points.length >= 2);

  /// Clear all segments.
  void clear() {
    setState(() {
      _segments = [];
      _activeSegmentIndex = null;
    });
    _notifyChange();
  }

  /// Undo the last point on the active segment.
  void undo() {
    if (_activeSegmentIndex == null) return;
    final seg = _segments[_activeSegmentIndex!];
    if (seg.points.isNotEmpty) {
      setState(() => seg.points.removeLast());
      _notifyChange();
    }
  }

  bool get canUndo =>
      _activeSegmentIndex != null &&
      _segments[_activeSegmentIndex!].points.isNotEmpty;

  /// Set points on the active segment (e.g., from auto-detect).
  void setPoints(List<Offset> points) {
    if (_segments.isEmpty) {
      _startNewSegment();
    }
    if (_activeSegmentIndex == null) return;
    setState(() {
      _segments[_activeSegmentIndex!].points = List.from(points);
    });
    _notifyChange();
  }

  /// Start tracing a new segment. Returns the index.
  int startNewSegment({
    String label = 'New Segment',
    int channelIndex = 0,
    int storyLevel = 1,
  }) {
    final seg = _EditableSegment(
      label: label,
      channelIndex: channelIndex,
      storyLevel: storyLevel,
      points: [],
    );
    setState(() {
      _segments.add(seg);
      _activeSegmentIndex = _segments.length - 1;
    });
    _notifyChange();
    return _segments.length - 1;
  }

  /// Select an existing segment by index for editing.
  void selectSegment(int index) {
    if (index >= 0 && index < _segments.length) {
      setState(() => _activeSegmentIndex = index);
    }
  }

  /// Delete a segment by index.
  void deleteSegment(int index) {
    if (index < 0 || index >= _segments.length) return;
    setState(() {
      _segments.removeAt(index);
      if (_activeSegmentIndex == index) {
        _activeSegmentIndex = _segments.isEmpty ? null : (_segments.length - 1).clamp(0, _segments.length - 1);
      } else if (_activeSegmentIndex != null && _activeSegmentIndex! > index) {
        _activeSegmentIndex = _activeSegmentIndex! - 1;
      }
    });
    _notifyChange();
  }

  /// Update metadata for a segment.
  void updateSegmentMeta(int index, {String? label, int? channelIndex, int? storyLevel}) {
    if (index < 0 || index >= _segments.length) return;
    setState(() {
      final seg = _segments[index];
      if (label != null) seg.label = label;
      if (channelIndex != null) seg.channelIndex = channelIndex;
      if (storyLevel != null) seg.storyLevel = storyLevel;
    });
    _notifyChange();
  }

  /// Reorder a segment within the list.
  void reorderSegment(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _segments.length) return;
    if (newIndex < 0 || newIndex >= _segments.length) return;
    if (oldIndex == newIndex) return;
    setState(() {
      final seg = _segments.removeAt(oldIndex);
      _segments.insert(newIndex, seg);
      if (_activeSegmentIndex == oldIndex) {
        _activeSegmentIndex = newIndex;
      }
    });
    _notifyChange();
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  void _startNewSegment() {
    startNewSegment();
  }

  void _notifyChange() {
    widget.onSegmentsChanged?.call(getSegments());
    // Legacy callback
    widget.onChanged?.call(getMask());
  }

  void _onTapDown(TapDownDetails details, Size canvasSize) {
    if (_loadedImage == null) return;

    final normalized = Offset(
      (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / canvasSize.height).clamp(0.0, 1.0),
    );

    // Check if user tapped near an existing segment's point/line to select it
    final hitIndex = _hitTestSegment(normalized);
    if (hitIndex != null && hitIndex != _activeSegmentIndex) {
      setState(() => _activeSegmentIndex = hitIndex);
      return;
    }

    // If no active segment, create one
    if (_activeSegmentIndex == null || _segments.isEmpty) {
      _startNewSegment();
    }

    // Add point to active segment
    setState(() => _segments[_activeSegmentIndex!].points.add(normalized));
    _notifyChange();
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    if (_activeSegmentIndex == null || _loadedImage == null) return;

    final normalized = Offset(
      (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / canvasSize.height).clamp(0.0, 1.0),
    );

    // Check if dragging near an existing point in the active segment
    final seg = _segments[_activeSegmentIndex!];
    const hitRadius = 0.03; // 3% of canvas
    for (int i = 0; i < seg.points.length; i++) {
      if ((seg.points[i] - normalized).distance < hitRadius) {
        _draggingPointIndex = i;
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_draggingPointIndex == null || _activeSegmentIndex == null) return;

    final normalized = Offset(
      (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / canvasSize.height).clamp(0.0, 1.0),
    );

    setState(() {
      _segments[_activeSegmentIndex!].points[_draggingPointIndex!] = normalized;
    });
    _notifyChange();
  }

  void _onPanEnd(DragEndDetails details) {
    _draggingPointIndex = null;
  }

  /// Hit test: find which segment the normalized point is closest to.
  /// Returns segment index or null if nothing is close enough.
  int? _hitTestSegment(Offset normalized) {
    const hitRadius = 0.03;

    for (int si = 0; si < _segments.length; si++) {
      final seg = _segments[si];
      // Check points
      for (final p in seg.points) {
        if ((p - normalized).distance < hitRadius) return si;
      }
      // Check lines
      for (int i = 0; i < seg.points.length - 1; i++) {
        final dist = _distanceToLineSegment(normalized, seg.points[i], seg.points[i + 1]);
        if (dist < hitRadius) return si;
      }
    }
    return null;
  }

  double _distanceToLineSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSq == 0) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - projection).distance;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      );
    }

    if (_loadedImage == null) {
      return const Center(child: Text('Failed to load image'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fittedSize = _calculateFittedSize(constraints.biggest);

        return Center(
          child: GestureDetector(
            onTapDown: (details) => _onTapDown(details, fittedSize),
            onPanStart: (details) => _onPanStart(details, fittedSize),
            onPanUpdate: (details) => _onPanUpdate(details, fittedSize),
            onPanEnd: _onPanEnd,
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
                  // Multi-segment drawing overlay
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MultiSegmentDrawingPainter(
                        segments: _segments,
                        activeIndex: _activeSegmentIndex,
                        imageSize: fittedSize,
                      ),
                    ),
                  ),
                  // Light preview overlay
                  if (hasValidRoofline)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MultiSegmentPreviewPainter(
                          segments: _segments,
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
      return Size(constraints.width, constraints.width / imageAspect);
    } else {
      return Size(constraints.height * imageAspect, constraints.height);
    }
  }
}

// ── Internal data model for editing ─────────────────────────────────────────

class _EditableSegment {
  String label;
  int channelIndex;
  int storyLevel;
  List<Offset> points;
  String? id; // preserved from existing RooflineSegment

  _EditableSegment({
    required this.label,
    required this.channelIndex,
    required this.storyLevel,
    required this.points,
    this.id,
  });

  factory _EditableSegment.fromRooflineSegment(RooflineSegment seg) {
    return _EditableSegment(
      label: seg.name,
      channelIndex: seg.channelIndex,
      storyLevel: seg.level,
      points: List.from(seg.points),
      id: seg.id,
    );
  }

  RooflineSegment toRooflineSegment({int sortOrder = 0}) {
    return RooflineSegment(
      id: id ?? 'seg_${sortOrder}_${DateTime.now().millisecondsSinceEpoch}',
      name: label,
      pixelCount: _estimatePixelCount(),
      startPixel: 0, // recalculated by RooflineConfiguration
      type: SegmentType.run,
      isConnectedToPrevious: false,
      level: storyLevel,
      channelIndex: channelIndex,
      points: List.from(points),
      sortOrder: sortOrder,
    );
  }

  /// Rough pixel count estimate based on polyline length.
  /// Assumes ~9" spacing at ~1.2 pixels per normalized unit.
  /// This is a placeholder — the installer will set exact counts.
  int _estimatePixelCount() {
    if (points.length < 2) return 0;
    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += (points[i] - points[i - 1]).distance;
    }
    // ~50 pixels per full-width path is a reasonable starting estimate
    return (totalLength * 50).round().clamp(1, 500);
  }

  Color get displayColor => kChannelColors[channelIndex % kChannelColors.length];
}

// ── Custom painters ─────────────────────────────────────────────────────────

/// Paints all segments with channel-colored lines and numbered points.
/// The active segment is drawn with thicker lines and larger handles.
class _MultiSegmentDrawingPainter extends CustomPainter {
  final List<_EditableSegment> segments;
  final int? activeIndex;
  final Size imageSize;

  _MultiSegmentDrawingPainter({
    required this.segments,
    required this.activeIndex,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int si = 0; si < segments.length; si++) {
      final seg = segments[si];
      if (seg.points.isEmpty) continue;

      final isActive = si == activeIndex;
      final color = seg.displayColor;
      final canvasPoints = seg.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();

      // Draw connecting lines
      if (canvasPoints.length >= 2) {
        final linePaint = Paint()
          ..color = color
          ..strokeWidth = isActive ? 3.5 : 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final path = Path()..moveTo(canvasPoints.first.dx, canvasPoints.first.dy);
        for (int i = 1; i < canvasPoints.length; i++) {
          path.lineTo(canvasPoints[i].dx, canvasPoints[i].dy);
        }
        canvas.drawPath(path, linePaint);

        // Glow for active segment
        if (isActive) {
          final glowPaint = Paint()
            ..color = color.withValues(alpha: 0.3)
            ..strokeWidth = 8
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
          canvas.drawPath(path, glowPaint);
        }
      }

      // Draw points
      final pointRadius = isActive ? 8.0 : 5.0;
      final pointPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
      final borderPaint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2;
      final inactiveBorderPaint = Paint()..color = color.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 1.5;

      for (int i = 0; i < canvasPoints.length; i++) {
        final point = canvasPoints[i];
        canvas.drawCircle(point, pointRadius, pointPaint);
        canvas.drawCircle(point, pointRadius, isActive ? borderPaint : inactiveBorderPaint);

        // Point number for active segment
        if (isActive) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '${i + 1}',
              style: TextStyle(
                color: color,
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

      // Segment label near the first point (for inactive segments)
      if (!isActive && canvasPoints.isNotEmpty) {
        final labelPos = canvasPoints.first;
        final labelPainter = TextPainter(
          text: TextSpan(
            text: seg.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        labelPainter.layout(maxWidth: 120);
        labelPainter.paint(
          canvas,
          Offset(labelPos.dx + 10, labelPos.dy - 14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MultiSegmentDrawingPainter oldDelegate) => true;
}

/// Paints a semi-transparent glow preview along each segment's path.
class _MultiSegmentPreviewPainter extends CustomPainter {
  final List<_EditableSegment> segments;
  final Size imageSize;

  _MultiSegmentPreviewPainter({
    required this.segments,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final seg in segments) {
      if (seg.points.length < 2) continue;

      final color = seg.displayColor;
      final canvasPoints = seg.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();

      final path = Path()..moveTo(canvasPoints.first.dx, canvasPoints.first.dy);
      for (int i = 1; i < canvasPoints.length; i++) {
        path.lineTo(canvasPoints[i].dx, canvasPoints[i].dy);
      }

      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 20
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

      canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_MultiSegmentPreviewPainter oldDelegate) => true;
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
        _ControlButton(
          icon: Icons.undo,
          label: 'Undo',
          onTap: canUndo ? onUndo : null,
        ),
        const SizedBox(width: 16),
        _ControlButton(
          icon: Icons.clear_all,
          label: 'Clear',
          onTap: canUndo ? onClear : null,
        ),
        const SizedBox(width: 16),
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
