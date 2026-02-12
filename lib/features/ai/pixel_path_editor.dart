import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Interactive editor where the user traces their roofline on a house photo
/// to define the LED pixel path.
///
/// Usage flow:
/// 1. Display the user's house photo full-screen
/// 2. User taps to add path points along the roofline
/// 3. Points are connected with a visible line + pixel dots
/// 4. User can drag existing points to adjust
/// 5. "Done" saves the normalized path coordinates
///
/// The path points are stored as normalized (0.0–1.0) coordinates relative
/// to the image container, making them resolution-independent.
class PixelPathEditor extends StatefulWidget {
  /// The house image to display behind the path editor.
  final ImageProvider imageProvider;

  /// Initial path points (normalized 0.0–1.0). Empty for first-time setup.
  final List<Offset> initialPath;

  /// Total LED pixel count (displayed to the user for reference).
  final int pixelCount;

  /// Called when the user confirms the path.
  final ValueChanged<List<Offset>> onPathConfirmed;

  /// Called when the user cancels.
  final VoidCallback? onCancel;

  const PixelPathEditor({
    super.key,
    required this.imageProvider,
    this.initialPath = const [],
    this.pixelCount = 100,
    required this.onPathConfirmed,
    this.onCancel,
  });

  @override
  State<PixelPathEditor> createState() => _PixelPathEditorState();
}

class _PixelPathEditorState extends State<PixelPathEditor> {
  late List<Offset> _path;
  int? _draggingIndex;
  bool _showPixelPreview = true;

  @override
  void initState() {
    super.initState();
    _path = List.of(widget.initialPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Trace Your Roofline'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel ?? () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_path.length >= 2)
            TextButton(
              onPressed: _confirmPath,
              child: const Text(
                'Done',
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _path.isEmpty
                  ? 'Tap along your roofline to place path points'
                  : _path.length == 1
                      ? 'Tap to add more points along the roofline'
                      : '${_path.length} points · Tap to add, drag to adjust',
              style: TextStyle(
                color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Image + path overlay
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapUp: (details) => _handleTap(details, constraints),
                    onPanStart: (details) =>
                        _handleDragStart(details, constraints),
                    onPanUpdate: (details) =>
                        _handleDragUpdate(details, constraints),
                    onPanEnd: (_) => _handleDragEnd(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // House photo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: widget.imageProvider,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),
                        ),

                        // Semi-transparent overlay
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.30),
                            ),
                          ),
                        ),

                        // Path + points
                        CustomPaint(
                          painter: _PathPainter(
                            path: _path,
                            pixelCount: widget.pixelCount,
                            showPixelPreview: _showPixelPreview,
                            draggingIndex: _draggingIndex,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Bottom controls
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                // Pixel preview toggle
                _ControlChip(
                  label: 'Show Pixels',
                  active: _showPixelPreview,
                  onTap: () =>
                      setState(() => _showPixelPreview = !_showPixelPreview),
                ),
                const SizedBox(width: 12),

                // Undo last point
                _ControlChip(
                  label: 'Undo',
                  active: false,
                  onTap: _path.isNotEmpty
                      ? () => setState(() => _path.removeLast())
                      : null,
                ),
                const SizedBox(width: 12),

                // Clear all
                _ControlChip(
                  label: 'Clear',
                  active: false,
                  onTap: _path.isNotEmpty
                      ? () => setState(() => _path.clear())
                      : null,
                ),

                const Spacer(),

                // Pixel count indicator
                Text(
                  '${widget.pixelCount} LEDs',
                  style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Gesture handlers
  // -----------------------------------------------------------------------

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    final norm = _toNormalized(details.localPosition, constraints);
    // Check if tapping near an existing point (to select for deletion)
    final hitIdx = _findNearPoint(norm, constraints);
    if (hitIdx != null) {
      // Double-tap to delete a point (simplified: long-press would be better)
      return;
    }

    setState(() {
      // Find the best insertion index (insert between nearest neighbors)
      final insertIdx = _bestInsertionIndex(norm);
      _path.insert(insertIdx, norm);
    });
  }

  void _handleDragStart(DragStartDetails details, BoxConstraints constraints) {
    final norm = _toNormalized(details.localPosition, constraints);
    _draggingIndex = _findNearPoint(norm, constraints);
  }

  void _handleDragUpdate(
      DragUpdateDetails details, BoxConstraints constraints) {
    if (_draggingIndex == null) return;
    final norm = _toNormalized(details.localPosition, constraints);
    setState(() {
      _path[_draggingIndex!] = Offset(
        norm.dx.clamp(0.0, 1.0),
        norm.dy.clamp(0.0, 1.0),
      );
    });
  }

  void _handleDragEnd() {
    _draggingIndex = null;
  }

  void _confirmPath() {
    widget.onPathConfirmed(List.of(_path));
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  Offset _toNormalized(Offset local, BoxConstraints constraints) {
    return Offset(
      (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
  }

  int? _findNearPoint(Offset norm, BoxConstraints constraints) {
    const hitRadius = 0.03; // normalized distance threshold
    for (int i = 0; i < _path.length; i++) {
      if ((_path[i] - norm).distance < hitRadius) return i;
    }
    return null;
  }

  /// Find the best position to insert a new point so the path stays smooth.
  int _bestInsertionIndex(Offset point) {
    if (_path.length < 2) return _path.length;

    // Find the closest segment
    double bestDist = double.infinity;
    int bestIdx = _path.length; // default: append

    for (int i = 0; i < _path.length - 1; i++) {
      final dist = _distToSegment(point, _path[i], _path[i + 1]);
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i + 1;
      }
    }

    // If the point is closer to either end than any segment, append/prepend
    final distToStart = (point - _path.first).distance;
    final distToEnd = (point - _path.last).distance;
    if (distToStart < bestDist && distToStart < distToEnd) return 0;
    if (distToEnd < bestDist) return _path.length;

    return bestIdx;
  }

  /// Distance from a point to a line segment.
  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq < 1e-10) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }
}

// ---------------------------------------------------------------------------
// Path painter
// ---------------------------------------------------------------------------

class _PathPainter extends CustomPainter {
  final List<Offset> path;
  final int pixelCount;
  final bool showPixelPreview;
  final int? draggingIndex;

  _PathPainter({
    required this.path,
    required this.pixelCount,
    required this.showPixelPreview,
    this.draggingIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    final denorm =
        path.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();

    // Draw connecting line
    if (denorm.length >= 2) {
      final linePaint = Paint()
        ..color = NexGenPalette.cyan.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final pathObj = Path()..moveTo(denorm.first.dx, denorm.first.dy);
      for (int i = 1; i < denorm.length; i++) {
        pathObj.lineTo(denorm[i].dx, denorm[i].dy);
      }
      canvas.drawPath(pathObj, linePaint);
    }

    // Draw control points
    for (int i = 0; i < denorm.length; i++) {
      final isDragging = i == draggingIndex;
      final outerPaint = Paint()
        ..color = isDragging
            ? NexGenPalette.cyan
            : NexGenPalette.cyan.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(denorm[i], isDragging ? 8 : 6, outerPaint);

      final innerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(denorm[i], isDragging ? 3.5 : 2.5, innerPaint);
    }

    // Draw pixel preview dots along the path
    if (showPixelPreview && denorm.length >= 2 && pixelCount > 0) {
      _drawPixelPreview(canvas, denorm);
    }
  }

  void _drawPixelPreview(Canvas canvas, List<Offset> denorm) {
    // Compute cumulative segment lengths
    final segLengths = <double>[0.0];
    for (int i = 1; i < denorm.length; i++) {
      segLengths.add(segLengths.last + (denorm[i] - denorm[i - 1]).distance);
    }
    final totalLength = segLengths.last;
    if (totalLength < 1.0) return;

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < pixelCount; i++) {
      final t = pixelCount > 1 ? i / (pixelCount - 1) : 0.5;
      final targetDist = t * totalLength;

      // Find segment
      int segIdx = 0;
      for (int s = 1; s < segLengths.length; s++) {
        if (segLengths[s] >= targetDist) {
          segIdx = s - 1;
          break;
        }
        segIdx = s - 1;
      }

      final segStart = segLengths[segIdx];
      final segEnd = segLengths[segIdx + 1];
      final segT = segEnd > segStart
          ? (targetDist - segStart) / (segEnd - segStart)
          : 0.0;

      final pos = Offset.lerp(denorm[segIdx], denorm[segIdx + 1], segT)!;
      canvas.drawCircle(pos, 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_PathPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.showPixelPreview != showPixelPreview ||
        oldDelegate.draggingIndex != draggingIndex;
  }
}

// ---------------------------------------------------------------------------
// Control chip
// ---------------------------------------------------------------------------

class _ControlChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ControlChip({
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : NexGenPalette.gunmetal,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? NexGenPalette.cyan.withValues(alpha: 0.5)
                : NexGenPalette.line.withValues(alpha: enabled ? 1.0 : 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: enabled
                ? (active ? NexGenPalette.cyan : NexGenPalette.textMedium)
                : NexGenPalette.textMedium.withValues(alpha: 0.3),
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
