import 'package:flutter/material.dart';

import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared blueprint widgets
//
// Originally duplicated between day1_blueprint_screen.dart and
// day2_blueprint_screen.dart. Lifted here so the wrap-up screen and any
// future blueprint surface can reuse them without three copies of the
// same painter and tile widgets.
//
// Day 1 styles its section headers cyan; Day 2 styles them green; both
// pass the desired accent color into [BlueprintSectionHeader.color]. The
// rest of the widgets are color-agnostic — they take the per-channel
// color from [blueprintColorForChannel] at the call site.
// ─────────────────────────────────────────────────────────────────────────────

/// Cycle of distinct accent colors used to paint each ChannelRun. Both
/// Day 1 and Day 2 use the same cycle so the same channel paints the
/// same color across both screens — important for orientation when an
/// electrician shows the install team where Channel 3 starts.
const kBlueprintChannelColors = <Color>[
  NexGenPalette.cyan,
  NexGenPalette.violet,
  NexGenPalette.green,
  NexGenPalette.amber,
  NexGenPalette.blue,
  NexGenPalette.magenta,
];

Color blueprintColorForChannel(int index) =>
    kBlueprintChannelColors[index % kBlueprintChannelColors.length];

// ─────────────────────────────────────────────────────────────────────────────
// Task model
// ─────────────────────────────────────────────────────────────────────────────

/// One task in a blueprint screen's auto-generated checklist.
///
/// Tasks are derived deterministically from the SalesJob so their IDs
/// remain stable across loads — see `_generateTasks()` in either
/// blueprint screen for the ID conventions.
class BlueprintTask {
  final String id;
  final String label;

  /// Used by blueprint screens to group consecutive tasks under a
  /// section header (e.g. "Channel 1", "Injection points").
  final String group;

  const BlueprintTask({
    required this.id,
    required this.label,
    required this.group,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

/// Uppercase section header used at the top of every blueprint section.
/// The [color] parameter lets Day 1 (cyan) and Day 2 (green) accent the
/// same widget consistently with their screen-level accent.
class BlueprintSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color color;

  const BlueprintSectionHeader({
    super.key,
    required this.title,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channel chip — tap target below the photo
// ─────────────────────────────────────────────────────────────────────────────

/// Small pill-shaped chip representing a [ChannelRun]. Used as the tap
/// target row beneath the home photo overlay; tapping it scrolls the
/// matching channel detail card into view and highlights the channel's
/// polyline on the overlay.
class BlueprintChannelChip extends StatelessWidget {
  final ChannelRun run;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const BlueprintChannelChip({
    super.key,
    required this.run,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${run.channelNumber}. ${run.label.isEmpty ? 'Untitled' : run.label}',
              style: TextStyle(
                color: selected ? color : Colors.white,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${run.linearFeet.toStringAsFixed(0)}ft',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task tile
// ─────────────────────────────────────────────────────────────────────────────

/// Single checklist row with a checkbox and a task label. Strikes
/// through the label when checked, and goes fully non-interactive when
/// [enabled] is false (used to lock checkboxes on completed jobs).
class BlueprintTaskTile extends StatelessWidget {
  final BlueprintTask task;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const BlueprintTaskTile({
    super.key,
    required this.task,
    required this.checked,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!checked) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                activeColor: NexGenPalette.green,
                checkColor: Colors.black,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  task.label,
                  style: TextStyle(
                    color: checked
                        ? Colors.white.withValues(alpha: 0.45)
                        : Colors.white,
                    fontSize: 13,
                    decoration:
                        checked ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white.withValues(alpha: 0.4),
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Polyline overlay painter
//
// Each ChannelRun's tracePoints are normalized 0.0–1.0 across the home
// photo. The painter scales them to the rendered size, draws the
// polyline in the channel's accent color, then renders a small numbered
// label badge at the start of each run. The selected channel (if any)
// is drawn last with a thicker stroke and outer glow.
// ─────────────────────────────────────────────────────────────────────────────

class BlueprintOverlayPainter extends CustomPainter {
  final List<ChannelRun> runs;
  final String? selectedChannelId;

  BlueprintOverlayPainter({
    required this.runs,
    required this.selectedChannelId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw non-selected runs first so the selected one ends up on top.
    final ordered = <_RunDraw>[];
    for (int i = 0; i < runs.length; i++) {
      ordered.add(_RunDraw(
        run: runs[i],
        color: blueprintColorForChannel(i),
        isSelected: runs[i].id == selectedChannelId,
      ));
    }
    ordered.sort((a, b) {
      if (a.isSelected == b.isSelected) return 0;
      return a.isSelected ? 1 : -1;
    });

    for (final d in ordered) {
      _drawRun(canvas, size, d);
    }
  }

  void _drawRun(Canvas canvas, Size size, _RunDraw d) {
    if (d.run.tracePoints.length < 2) return;

    final path = Path();
    final first = _scale(d.run.tracePoints.first, size);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < d.run.tracePoints.length; i++) {
      final p = _scale(d.run.tracePoints[i], size);
      path.lineTo(p.dx, p.dy);
    }

    // Outer glow when selected
    if (d.isSelected) {
      final glow = Paint()
        ..color = d.color.withValues(alpha: 0.35)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, glow);
    }

    final stroke = Paint()
      ..color = d.color
      ..strokeWidth = d.isSelected ? 5 : 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, stroke);

    // Numbered start badge
    _drawBadge(canvas, first, d.color, '${d.run.channelNumber}');
  }

  void _drawBadge(Canvas canvas, Offset center, Color color, String label) {
    const radius = 11.0;
    final bg = Paint()..color = const Color(0xFF07091A).withValues(alpha: 0.85);
    final ring = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bg);
    canvas.drawCircle(center, radius, ring);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  Offset _scale(Offset normalized, Size size) =>
      Offset(normalized.dx * size.width, normalized.dy * size.height);

  @override
  bool shouldRepaint(covariant BlueprintOverlayPainter old) =>
      old.runs != runs || old.selectedChannelId != selectedChannelId;
}

class _RunDraw {
  final ChannelRun run;
  final Color color;
  final bool isSelected;
  _RunDraw({
    required this.run,
    required this.color,
    required this.isSelected,
  });
}
