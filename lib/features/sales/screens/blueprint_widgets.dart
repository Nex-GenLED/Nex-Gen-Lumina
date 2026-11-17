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

// ─────────────────────────────────────────────────────────────────────────────
// Zone card — for jobs built zone by zone
//
// `SalesJob.channelRuns` is written only by the estimate wizard. Jobs built
// on the visit's zone builder carry `zones` instead and an empty
// `channelRuns`, so both blueprint screens render one of these per zone in
// their channels section when there are no channel runs. Shows what the
// zone builder captured: run, product, rail, corners, injection points,
// power mounts, notes and photos. Price is left off; this is a field sheet.
// ─────────────────────────────────────────────────────────────────────────────

class BlueprintZoneCard extends StatelessWidget {
  final InstallZone zone;

  /// 1-based position, shown in the badge.
  final int number;
  final Color color;
  final ValueChanged<String> onPhotoTap;

  const BlueprintZoneCard({
    super.key,
    required this.zone,
    required this.number,
    required this.color,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final hardware = <String>[
      if (zone.totalPixels > 0) '${zone.totalPixels} pixels',
      if (zone.railType != RailType.none)
        zone.railColor == RailColor.none
            ? zone.railType.label
            : '${zone.railType.label} · ${zone.railColor.label}',
      if (zone.cornerCount > 0)
        '${zone.cornerCount} corner${zone.cornerCount == 1 ? '' : 's'}',
      if (zone.connectorRunFt > 0)
        '${zone.connectorRunFt.toStringAsFixed(0)} ft connector run',
    ];

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '$number',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name.isEmpty ? 'Untitled zone' : zone.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${zone.runLengthFt.toStringAsFixed(0)} ft · '
                      '${zone.productType.label} · ${zone.colorPreset.label}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hardware.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              hardware.join(' · '),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
          if (zone.injections.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: NexGenPalette.line, height: 1),
            const SizedBox(height: 12),
            _label('INJECTION POINTS'),
            const SizedBox(height: 8),
            for (final p in zone.injections) ...[
              _detailTile(
                icon: Icons.bolt,
                title: '${p.positionFt.toStringAsFixed(0)} ft along the run · '
                    '${p.wireGauge.label}'
                    '${p.wireRunFt > 0 ? ' · ${p.wireRunFt.toStringAsFixed(0)} ft wire' : ''}',
                subtitle: p.servedByController
                    ? 'Fed from the controller'
                    : 'Fed from an additional supply',
                note: p.architecturalNote,
              ),
              if (p != zone.injections.last) const SizedBox(height: 6),
            ],
          ],
          if (zone.mounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: NexGenPalette.line, height: 1),
            const SizedBox(height: 12),
            _label('POWER AND MOUNTS'),
            const SizedBox(height: 8),
            for (final m in zone.mounts) ...[
              _detailTile(
                icon: m.isController
                    ? Icons.developer_board
                    : Icons.power_outlined,
                title: m.isController ? 'Controller' : '${m.supplySize} supply',
                subtitle: '${m.positionFt.toStringAsFixed(0)} ft along the run · '
                    '${m.outletType.label}',
                note: [m.mountLocationNote, m.outletNote]
                    .where((s) => s.trim().isNotEmpty)
                    .join(' — '),
              ),
              if (m != zone.mounts.last) const SizedBox(height: 6),
            ],
          ],
          if (zone.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _label('NOTES'),
            const SizedBox(height: 4),
            Text(
              zone.notes,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
          if (zone.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: zone.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => onPhotoTap(zone.photoUrls[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      zone.photoUrls[i],
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: NexGenPalette.matteBlack,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white24,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );

  Widget _detailTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String note,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
