import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// Painting tools available in the LED painting interface.
enum PaintingTool {
  /// Single LED tap painting
  brush,

  /// Paint a range of LEDs by dragging
  drag,

  /// Fill an entire segment
  fill,

  /// Eraser (set to off/black)
  eraser,

  /// Select LEDs without painting (for multi-select operations)
  select,
}

/// Provider for the current painting tool.
final paintingToolProvider = StateProvider<PaintingTool>((ref) => PaintingTool.brush);

/// Provider for multi-select mode selected LED indices.
final selectedLedsProvider = StateProvider<Set<int>>((ref) => {});

/// Comprehensive LED painting interface that integrates with roofline configuration.
///
/// Features:
/// - Multiple painting tools (brush, drag, fill, eraser, select)
/// - Segment-aware visualization
/// - Anchor point highlighting
/// - Real-time color preview
/// - Touch-optimized for mobile devices
class LedPaintingInterface extends ConsumerStatefulWidget {
  /// Whether to show the roofline segments or flat channel view
  final bool useSegmentView;

  /// Callback when colors are applied
  final VoidCallback? onColorsApplied;

  /// Optional color groups to display (for pattern preview)
  final List<LedColorGroup>? previewColorGroups;

  const LedPaintingInterface({
    super.key,
    this.useSegmentView = true,
    this.onColorsApplied,
    this.previewColorGroups,
  });

  @override
  ConsumerState<LedPaintingInterface> createState() => _LedPaintingInterfaceState();
}

class _LedPaintingInterfaceState extends ConsumerState<LedPaintingInterface> {
  // Drag state
  int? _dragStartLed;
  int? _dragCurrentLed;
  String? _dragSegmentId;

  @override
  Widget build(BuildContext context) {
    final tool = ref.watch(paintingToolProvider);
    final hasRooflineConfig = ref.watch(hasRooflineConfigProvider);

    return Column(
      children: [
        // Toolbar
        _buildToolbar(tool),

        const SizedBox(height: 12),

        // Canvas
        Expanded(
          child: widget.useSegmentView && hasRooflineConfig
              ? _buildSegmentCanvas()
              : _buildFlatCanvas(),
        ),

        // Selection info bar (when in select mode)
        if (tool == PaintingTool.select)
          _buildSelectionBar(),
      ],
    );
  }

  Widget _buildToolbar(PaintingTool currentTool) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.brush,
            label: 'Brush',
            isSelected: currentTool == PaintingTool.brush,
            onTap: () => ref.read(paintingToolProvider.notifier).state = PaintingTool.brush,
          ),
          _ToolButton(
            icon: Icons.swipe,
            label: 'Drag',
            isSelected: currentTool == PaintingTool.drag,
            onTap: () => ref.read(paintingToolProvider.notifier).state = PaintingTool.drag,
          ),
          _ToolButton(
            icon: Icons.format_color_fill,
            label: 'Fill',
            isSelected: currentTool == PaintingTool.fill,
            onTap: () => ref.read(paintingToolProvider.notifier).state = PaintingTool.fill,
          ),
          _ToolButton(
            icon: Icons.auto_fix_high,
            label: 'Erase',
            isSelected: currentTool == PaintingTool.eraser,
            onTap: () => ref.read(paintingToolProvider.notifier).state = PaintingTool.eraser,
          ),
          _ToolButton(
            icon: Icons.select_all,
            label: 'Select',
            isSelected: currentTool == PaintingTool.select,
            onTap: () => ref.read(paintingToolProvider.notifier).state = PaintingTool.select,
          ),
          const Spacer(),
          // Current color indicator
          _CurrentColorIndicator(),
        ],
      ),
    );
  }

  Widget _buildSegmentCanvas() {
    final config = ref.watch(currentRooflineConfigProvider);

    return config.when(
      data: (rooflineConfig) {
        if (rooflineConfig == null || rooflineConfig.segments.isEmpty) {
          return _buildEmptyRooflineState();
        }
        return _buildSegmentView(rooflineConfig);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (_, __) => _buildEmptyRooflineState(),
    );
  }

  Widget _buildEmptyRooflineState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.roofing,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Roofline Configuration',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set up your roofline to use segment-aware painting',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              // Navigate to roofline setup
            },
            icon: const Icon(Icons.settings),
            label: const Text('Configure Roofline'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              side: const BorderSide(color: NexGenPalette.cyan),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentView(RooflineConfiguration config) {
    final tool = ref.watch(paintingToolProvider);
    final selectedLeds = ref.watch(selectedLedsProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Roofline info header
            Row(
              children: [
                const Icon(Icons.roofing, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  config.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${config.totalPixelCount} LEDs',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Segments
            for (final segment in config.segments) ...[
              _SegmentPaintingSection(
                segment: segment,
                tool: tool,
                selectedLeds: selectedLeds,
                dragStartLed: _dragSegmentId == segment.id ? _dragStartLed : null,
                dragCurrentLed: _dragSegmentId == segment.id ? _dragCurrentLed : null,
                previewColorGroups: widget.previewColorGroups,
                onLedTap: (globalIndex) => _handleLedTap(globalIndex, segment),
                onSegmentTap: () => _handleSegmentTap(segment),
                onDragStart: (globalIndex) => _handleDragStart(globalIndex, segment),
                onDragUpdate: (globalIndex) => _handleDragUpdate(globalIndex),
                onDragEnd: () => _handleDragEnd(segment),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlatCanvas() {
    final design = ref.watch(currentDesignProvider);

    if (design == null) {
      return const Center(
        child: Text(
          'No design loaded',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.all(12),
      child: const Center(
        child: Text(
          'Flat canvas view - use channel-based painting',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final selectedLeds = ref.watch(selectedLedsProvider);
    final count = selectedLeds.length;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '$count LED${count == 1 ? '' : 's'} selected',
            style: const TextStyle(
              color: NexGenPalette.cyan,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (count > 0) ...[
            TextButton(
              onPressed: _applyColorToSelection,
              child: const Text('Apply Color'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => ref.read(selectedLedsProvider.notifier).state = {},
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  // Event handlers
  void _handleLedTap(int globalIndex, RooflineSegment segment) {
    final tool = ref.read(paintingToolProvider);

    switch (tool) {
      case PaintingTool.brush:
        _paintSingleLed(globalIndex);
        break;
      case PaintingTool.eraser:
        _eraseSingleLed(globalIndex);
        break;
      case PaintingTool.select:
        _toggleLedSelection(globalIndex);
        break;
      case PaintingTool.fill:
        _fillSegment(segment);
        break;
      case PaintingTool.drag:
        // Drag tool handles taps as single paints
        _paintSingleLed(globalIndex);
        break;
    }

    widget.onColorsApplied?.call();
  }

  void _handleSegmentTap(RooflineSegment segment) {
    final tool = ref.read(paintingToolProvider);

    if (tool == PaintingTool.fill) {
      _fillSegment(segment);
    } else if (tool == PaintingTool.select) {
      _selectSegment(segment);
    }

    widget.onColorsApplied?.call();
  }

  void _handleDragStart(int globalIndex, RooflineSegment segment) {
    final tool = ref.read(paintingToolProvider);
    if (tool != PaintingTool.drag) return;

    setState(() {
      _dragStartLed = globalIndex;
      _dragCurrentLed = globalIndex;
      _dragSegmentId = segment.id;
    });
  }

  void _handleDragUpdate(int globalIndex) {
    if (_dragStartLed == null) return;

    setState(() {
      _dragCurrentLed = globalIndex;
    });
  }

  void _handleDragEnd(RooflineSegment segment) {
    if (_dragStartLed == null || _dragCurrentLed == null) return;

    final start = _dragStartLed! < _dragCurrentLed! ? _dragStartLed! : _dragCurrentLed!;
    final end = _dragStartLed! > _dragCurrentLed! ? _dragStartLed! : _dragCurrentLed!;

    _paintLedRange(start, end);

    setState(() {
      _dragStartLed = null;
      _dragCurrentLed = null;
      _dragSegmentId = null;
    });

    widget.onColorsApplied?.call();
  }

  // Painting operations
  void _paintSingleLed(int globalIndex) {
    final color = ref.read(selectedColorProvider);
    final design = ref.read(currentDesignProvider);
    if (design == null) return;

    // Find which channel this LED belongs to
    // For now, we assume a simple mapping
    ref.read(currentDesignProvider.notifier).paintLeds(0, globalIndex, globalIndex, color);
  }

  void _paintLedRange(int start, int end) {
    final color = ref.read(selectedColorProvider);
    ref.read(currentDesignProvider.notifier).paintLeds(0, start, end, color);
  }

  void _eraseSingleLed(int globalIndex) {
    ref.read(currentDesignProvider.notifier).paintLeds(0, globalIndex, globalIndex, Colors.black);
  }

  void _fillSegment(RooflineSegment segment) {
    final color = ref.read(selectedColorProvider);
    ref.read(currentDesignProvider.notifier).paintLeds(
      0,
      segment.startPixel,
      segment.endPixel,
      color,
    );
  }

  void _toggleLedSelection(int globalIndex) {
    final current = ref.read(selectedLedsProvider);
    final updated = Set<int>.from(current);

    if (updated.contains(globalIndex)) {
      updated.remove(globalIndex);
    } else {
      updated.add(globalIndex);
    }

    ref.read(selectedLedsProvider.notifier).state = updated;
  }

  void _selectSegment(RooflineSegment segment) {
    final current = ref.read(selectedLedsProvider);
    final updated = Set<int>.from(current);

    for (int i = segment.startPixel; i <= segment.endPixel; i++) {
      updated.add(i);
    }

    ref.read(selectedLedsProvider.notifier).state = updated;
  }

  void _applyColorToSelection() {
    final selectedLeds = ref.read(selectedLedsProvider);
    if (selectedLeds.isEmpty) return;

    final color = ref.read(selectedColorProvider);

    // Apply to all selected LEDs
    for (final ledIndex in selectedLeds) {
      ref.read(currentDesignProvider.notifier).paintLeds(0, ledIndex, ledIndex, color);
    }

    // Clear selection
    ref.read(selectedLedsProvider.notifier).state = {};

    widget.onColorsApplied?.call();
  }
}

/// Tool button widget.
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? NexGenPalette.cyan.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? NexGenPalette.cyan
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? NexGenPalette.cyan : Colors.white70,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? NexGenPalette.cyan : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Current color indicator.
class _CurrentColorIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(selectedColorProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white30),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Segment painting section widget.
class _SegmentPaintingSection extends StatelessWidget {
  final RooflineSegment segment;
  final PaintingTool tool;
  final Set<int> selectedLeds;
  final int? dragStartLed;
  final int? dragCurrentLed;
  final List<LedColorGroup>? previewColorGroups;
  final void Function(int globalIndex) onLedTap;
  final VoidCallback onSegmentTap;
  final void Function(int globalIndex) onDragStart;
  final void Function(int globalIndex) onDragUpdate;
  final VoidCallback onDragEnd;

  const _SegmentPaintingSection({
    required this.segment,
    required this.tool,
    required this.selectedLeds,
    this.dragStartLed,
    this.dragCurrentLed,
    this.previewColorGroups,
    required this.onLedTap,
    required this.onSegmentTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segment header
        GestureDetector(
          onTap: onSegmentTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _getSegmentTypeColor(segment.type).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _getSegmentTypeColor(segment.type).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getSegmentTypeIcon(segment.type),
                  size: 16,
                  color: _getSegmentTypeColor(segment.type),
                ),
                const SizedBox(width: 8),
                Text(
                  segment.name,
                  style: TextStyle(
                    color: _getSegmentTypeColor(segment.type),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${segment.pixelCount} LEDs',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
                if (segment.anchorPixels.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.anchor, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${segment.anchorPixels.length}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (tool == PaintingTool.fill) ...[
                  const Spacer(),
                  const Icon(
                    Icons.touch_app,
                    size: 16,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to fill',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // LED grid
        _LedGrid(
          segment: segment,
          tool: tool,
          selectedLeds: selectedLeds,
          dragStartLed: dragStartLed,
          dragCurrentLed: dragCurrentLed,
          previewColorGroups: previewColorGroups,
          onLedTap: onLedTap,
          onDragStart: onDragStart,
          onDragUpdate: onDragUpdate,
          onDragEnd: onDragEnd,
        ),
      ],
    );
  }

  IconData _getSegmentTypeIcon(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return Icons.horizontal_rule;
      case SegmentType.corner:
        return Icons.turn_right;
      case SegmentType.peak:
        return Icons.change_history;
      case SegmentType.column:
        return Icons.height;
      case SegmentType.connector:
        return Icons.link;
    }
  }

  Color _getSegmentTypeColor(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return NexGenPalette.cyan;
      case SegmentType.corner:
        return Colors.orange;
      case SegmentType.peak:
        return Colors.purple;
      case SegmentType.column:
        return Colors.green;
      case SegmentType.connector:
        return Colors.grey;
    }
  }
}

/// LED grid with touch/drag support.
class _LedGrid extends StatefulWidget {
  final RooflineSegment segment;
  final PaintingTool tool;
  final Set<int> selectedLeds;
  final int? dragStartLed;
  final int? dragCurrentLed;
  final List<LedColorGroup>? previewColorGroups;
  final void Function(int globalIndex) onLedTap;
  final void Function(int globalIndex) onDragStart;
  final void Function(int globalIndex) onDragUpdate;
  final VoidCallback onDragEnd;

  const _LedGrid({
    required this.segment,
    required this.tool,
    required this.selectedLeds,
    this.dragStartLed,
    this.dragCurrentLed,
    this.previewColorGroups,
    required this.onLedTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_LedGrid> createState() => _LedGridState();
}

class _LedGridState extends State<_LedGrid> {
  // Track LED positions for drag detection
  final Map<int, Rect> _ledRects = {};
  final GlobalKey _gridKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _gridKey,
      onPanStart: widget.tool == PaintingTool.drag ? _onPanStart : null,
      onPanUpdate: widget.tool == PaintingTool.drag ? _onPanUpdate : null,
      onPanEnd: widget.tool == PaintingTool.drag ? _onPanEnd : null,
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: List.generate(widget.segment.pixelCount, (localIndex) {
          final globalIndex = widget.segment.startPixel + localIndex;
          final isAnchor = widget.segment.isAnchorPixel(localIndex);
          final isSelected = widget.selectedLeds.contains(globalIndex);
          final isInDragRange = _isInDragRange(globalIndex);

          return _PaintableLed(
            key: ValueKey('led_$globalIndex'),
            globalIndex: globalIndex,
            localIndex: localIndex,
            isAnchor: isAnchor,
            isSelected: isSelected,
            isInDragRange: isInDragRange,
            color: _getColorForLed(globalIndex),
            onTap: () => widget.onLedTap(globalIndex),
            onPositionCallback: (rect) {
              _ledRects[globalIndex] = rect;
            },
          );
        }),
      ),
    );
  }

  bool _isInDragRange(int globalIndex) {
    if (widget.dragStartLed == null || widget.dragCurrentLed == null) {
      return false;
    }
    final start = widget.dragStartLed! < widget.dragCurrentLed!
        ? widget.dragStartLed!
        : widget.dragCurrentLed!;
    final end = widget.dragStartLed! > widget.dragCurrentLed!
        ? widget.dragStartLed!
        : widget.dragCurrentLed!;
    return globalIndex >= start && globalIndex <= end;
  }

  Color? _getColorForLed(int globalIndex) {
    if (widget.previewColorGroups == null) return null;

    for (final group in widget.previewColorGroups!) {
      if (globalIndex >= group.startLed && globalIndex <= group.endLed) {
        return group.flutterColor;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final ledIndex = _findLedAtPosition(details.localPosition);
    if (ledIndex != null) {
      widget.onDragStart(ledIndex);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final ledIndex = _findLedAtPosition(details.localPosition);
    if (ledIndex != null) {
      widget.onDragUpdate(ledIndex);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    widget.onDragEnd();
  }

  int? _findLedAtPosition(Offset localPosition) {
    for (final entry in _ledRects.entries) {
      if (entry.value.contains(localPosition)) {
        return entry.key;
      }
    }
    return null;
  }
}

/// Single paintable LED widget.
class _PaintableLed extends StatefulWidget {
  final int globalIndex;
  final int localIndex;
  final bool isAnchor;
  final bool isSelected;
  final bool isInDragRange;
  final Color? color;
  final VoidCallback onTap;
  final void Function(Rect rect) onPositionCallback;

  const _PaintableLed({
    super.key,
    required this.globalIndex,
    required this.localIndex,
    required this.isAnchor,
    required this.isSelected,
    required this.isInDragRange,
    this.color,
    required this.onTap,
    required this.onPositionCallback,
  });

  @override
  State<_PaintableLed> createState() => _PaintableLedState();
}

class _PaintableLedState extends State<_PaintableLed> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportPosition();
    });
  }

  void _reportPosition() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      widget.onPositionCallback(Rect.fromLTWH(
        position.dx,
        position.dy,
        size.width,
        size.height,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? Colors.white.withValues(alpha: 0.05);

    return GestureDetector(
      key: _key,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: widget.isInDragRange
              ? baseColor.withValues(alpha: 0.8)
              : baseColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.isSelected
                ? NexGenPalette.cyan
                : widget.isAnchor
                    ? Colors.amber
                    : widget.isInDragRange
                        ? Colors.white
                        : (widget.color != null
                            ? widget.color!.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.1)),
            width: widget.isSelected || widget.isAnchor ? 2 : 1,
          ),
          boxShadow: widget.color != null
              ? [
                  BoxShadow(
                    color: widget.color!.withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: widget.isAnchor
            ? const Center(
                child: Icon(
                  Icons.anchor,
                  size: 10,
                  color: Colors.amber,
                ),
              )
            : null,
      ),
    );
  }
}
