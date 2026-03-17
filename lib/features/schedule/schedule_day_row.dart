import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/pixel_strip_preview.dart';
import 'package:nexgen_command/features/schedule/schedule_plan_controller.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/utils/effect_display_meta.dart';

/// Individual day card within a [SchedulePlanCard].
///
/// Displays a rich preview of the scheduled lighting design:
///  - Row 1: Design name + time range
///  - Row 2: Color dot strip + effect badge
///  - Row 3: Effect motion description
///
/// Uses a staggered slide-in animation controlled by [animationDelay].
class ScheduleDayRow extends ConsumerStatefulWidget {
  /// The day entry to display.
  final SchedulePlanDay day;

  /// Index of this day in the plan (for edit callbacks).
  final int dayIndex;

  /// Whether this day is currently being edited inline.
  final bool isEditing;

  /// Called when the user taps the edit icon.
  final VoidCallback? onEdit;

  /// Called when the user taps the card body to open the detail sheet.
  final VoidCallback? onTap;

  /// Time range label (e.g. "4:00 PM – 10:00 PM"), from the parent plan.
  final String? timeRange;

  /// Stagger delay for the entrance animation.
  final Duration animationDelay;

  const ScheduleDayRow({
    super.key,
    required this.day,
    required this.dayIndex,
    this.isEditing = false,
    this.onEdit,
    this.onTap,
    this.timeRange,
    this.animationDelay = Duration.zero,
  });

  @override
  ConsumerState<ScheduleDayRow> createState() => _ScheduleDayRowState();
}

class _ScheduleDayRowState extends ConsumerState<ScheduleDayRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOut,
      ),
    );

    // Stagger the entrance
    Future.delayed(widget.animationDelay, () {
      if (mounted) _slideController.forward();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  /// Extract display colors from the suggestion's wledPayload col array.
  List<Color> _extractColors() {
    final s = widget.day.suggestion;
    // Prefer the pre-extracted suggestion colors
    if (s.colors.isNotEmpty) return s.colors;
    // Fall back to parsing payload
    final payload = s.wledPayload;
    if (payload == null) return const [NexGenPalette.cyan];
    final seg = payload['seg'];
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      final col = (seg.first as Map)['col'];
      if (col is List && col.isNotEmpty) {
        return col
            .whereType<List>()
            .where((c) => c.length >= 3)
            .map((c) => Color.fromARGB(
                  255,
                  (c[0] as num).toInt().clamp(0, 255),
                  (c[1] as num).toInt().clamp(0, 255),
                  (c[2] as num).toInt().clamp(0, 255),
                ))
            .toList();
      }
    }
    return const [NexGenPalette.cyan];
  }

  /// Extract the WLED effect ID from the suggestion.
  int _extractFxId() {
    final s = widget.day.suggestion;
    // Use the suggestion's effect info directly
    if (s.effect.id != 0 || s.effect.name == 'Solid') return s.effect.id;
    // Fall back to parsing payload
    final payload = s.wledPayload;
    if (payload == null) return 0;
    final seg = payload['seg'];
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      final fx = (seg.first as Map)['fx'];
      if (fx is int) return fx;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _extractColors();
    final fxId = _extractFxId();
    final meta = EffectDisplayMeta.fromId(fxId);
    final s = widget.day.suggestion;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isEditing
                  ? NexGenPalette.cyan.withValues(alpha: 0.06)
                  : const Color(0xFF111821),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isEditing
                    ? NexGenPalette.cyan.withValues(alpha: 0.35)
                    : NexGenPalette.line.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Row 1: Day badge + design name + time range ----
                _buildRow1(meta),

                const SizedBox(height: 8),

                // ---- Row 2: Color dot strip + effect badge ----
                _buildRow2(colors, meta, s),

                const SizedBox(height: 6),

                // ---- Row 3: Motion description ----
                _buildRow3(meta),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Row 1: Day badge, design name, time range, edit icon
  Widget _buildRow1(EffectDisplayMeta meta) {
    return Row(
      children: [
        // Day badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${widget.day.dayOfWeek} ${widget.day.dateLabel}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: NexGenPalette.cyan,
              letterSpacing: 0.5,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Design name
        Expanded(
          child: Text(
            widget.day.designName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: NexGenPalette.textHigh,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Time range (from parent plan)
        if (widget.timeRange != null) ...[
          const SizedBox(width: 6),
          Text(
            widget.timeRange!,
            style: TextStyle(
              fontSize: 10,
              color: NexGenPalette.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],

        // Edit icon
        if (widget.onEdit != null)
          GestureDetector(
            onTap: widget.onEdit,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.edit_outlined,
                size: 16,
                color: widget.isEditing
                    ? NexGenPalette.cyan
                    : NexGenPalette.textMedium.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  /// Row 2: Pixel strip preview + effect badge pill
  Widget _buildRow2(List<Color> colors, EffectDisplayMeta meta,
      LuminaLightingSuggestion s) {
    return Row(
      children: [
        // Color dot strip
        Expanded(
          child: PixelStripPreview(
            colors: colors,
            effectType: s.effect.category,
            speed: s.speed ?? 0.5,
            brightness: s.brightness,
            pixelCount: 20,
            height: 32,
            borderRadius: 8,
            backgroundColor: const Color(0xFF0A0E14),
          ),
        ),

        const SizedBox(width: 8),

        // Effect badge pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: NexGenPalette.line.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                meta.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.isNotEmpty
                      ? colors.first
                      : NexGenPalette.cyan,
                ),
              ),
              if (meta.isMotion) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.loop,
                  size: 10,
                  color: colors.isNotEmpty
                      ? colors.first.withValues(alpha: 0.7)
                      : NexGenPalette.cyan.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Row 3: Subtle motion description
  Widget _buildRow3(EffectDisplayMeta meta) {
    return Text(
      meta.motionDescription,
      style: TextStyle(
        fontSize: 10,
        color: NexGenPalette.textSecondary.withValues(alpha: 0.6),
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
