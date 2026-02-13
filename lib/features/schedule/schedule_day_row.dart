import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/pixel_strip_preview.dart';
import 'package:nexgen_command/features/schedule/schedule_plan_controller.dart';
import 'package:nexgen_command/theme.dart';

/// Individual day card within a [SchedulePlanCard].
///
/// Displays:
///  - Day of week + date (e.g. "THU 2/13")
///  - Design name (e.g. "Royal Blue & Gold Static")
///  - Animated [PixelStripPreview] showing that day's colors & effect
///  - Small edit icon to open inline adjustment for this day
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

  /// Stagger delay for the entrance animation.
  final Duration animationDelay;

  const ScheduleDayRow({
    super.key,
    required this.day,
    required this.dayIndex,
    this.isEditing = false,
    this.onEdit,
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

  @override
  Widget build(BuildContext context) {
    final s = widget.day.suggestion;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
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
              // ---- Header row: day/date + design name + edit icon ----
              _buildHeader(),

              const SizedBox(height: 8),

              // ---- Pixel preview strip ----
              PixelStripPreview(
                colors: s.colors.isNotEmpty
                    ? s.colors
                    : const [NexGenPalette.cyan],
                effectType: s.effect.category,
                speed: s.speed ?? 0.5,
                brightness: s.brightness,
                pixelCount: 20,
                height: 36,
                borderRadius: 8,
                backgroundColor: const Color(0xFF0A0E14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
}
