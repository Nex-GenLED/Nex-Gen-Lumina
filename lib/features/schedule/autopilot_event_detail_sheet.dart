import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/services/autopilot_event_repository.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/utils/effect_display_meta.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';

/// Shows a detail bottom sheet for an [AutopilotEvent] schedule entry.
///
/// All data is derived from the event's fields and wledPayload — no
/// pattern library lookups are performed.
void showAutopilotEventDetailSheet(
  BuildContext context,
  WidgetRef ref,
  AutopilotEvent event,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AutopilotEventDetailSheet(event: event),
  );
}

class _AutopilotEventDetailSheet extends ConsumerWidget {
  final AutopilotEvent event;
  const _AutopilotEventDetailSheet({required this.event});

  // ---------------------------------------------------------------------------
  // Payload helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? get _firstSeg {
    final seg = event.wledPayload?['seg'];
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      return seg.first as Map<String, dynamic>;
    }
    return null;
  }

  int get _fxId => (_firstSeg?['fx'] as int?) ?? 0;
  int get _speed => (_firstSeg?['sx'] as int?) ?? 0;
  int get _bri => (event.wledPayload?['bri'] as int?) ?? 255;

  List<Color> get _colors {
    final col = _firstSeg?['col'];
    if (col is List && col.isNotEmpty) {
      final parsed = col
          .whereType<List>()
          .where((c) => c.length >= 3)
          .map((c) => Color.fromARGB(
                255,
                (c[0] as num).toInt().clamp(0, 255),
                (c[1] as num).toInt().clamp(0, 255),
                (c[2] as num).toInt().clamp(0, 255),
              ))
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }
    if (event.displayColor != null) return [event.displayColor!];
    return const [NexGenPalette.cyan];
  }

  String get _speedLabel {
    if (_speed <= 85) return 'Slow';
    if (_speed <= 170) return 'Medium';
    return 'Fast';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$min $ampm';
  }

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  String get _timeRange =>
      '${_formatTime(event.startTime)} – ${_formatTime(event.endTime)}';

  String get _dateLabel {
    final d = event.startTime;
    final dayName = _days[d.weekday - 1];
    final monthName = _months[d.month - 1];
    return '$dayName, $monthName ${d.day}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = EffectDisplayMeta.fromId(_fxId);
    final colors = _colors;
    final accentColor = colors.first;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1218),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: accentColor.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ---- SECTION 1: Header ----
              _buildHeader(accentColor),

              const SizedBox(height: 14),

              // ---- SECTION 2: Roofline Preview ----
              _buildRooflinePreview(ref, meta),

              const SizedBox(height: 14),

              // ---- SECTION 3: Effect Details ----
              _buildEffectDetails(meta, colors),

              const SizedBox(height: 16),

              // ---- SECTION 4: Actions ----
              _buildActions(context, ref, accentColor),

              const SizedBox(height: 12),

              // ---- SECTION 5: Autopilot Footer ----
              _buildFooter(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1: Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event name
        Text(
          event.patternName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        // Date + time range
        Row(
          children: [
            Icon(Icons.schedule, size: 13, color: NexGenPalette.textSecondary),
            const SizedBox(width: 4),
            Text(
              '$_dateLabel  ·  $_timeRange',
              style: TextStyle(
                fontSize: 12,
                color: NexGenPalette.textSecondary,
              ),
            ),
          ],
        ),
        // Source detail (e.g. "Royals vs Yankees")
        if (event.sourceDetail.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.sports, size: 13, color: accent.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  event.sourceDetail,
                  style: TextStyle(
                    fontSize: 12,
                    color: accent.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2: Roofline Preview
  // ---------------------------------------------------------------------------

  Widget _buildRooflinePreview(WidgetRef ref, EffectDisplayMeta meta) {
    final houseImageUrl = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u?.housePhotoUrl,
      orElse: () => null,
    );
    final hasCustomImage = houseImageUrl != null && houseImageUrl.isNotEmpty;
    final colors = _colors;

    return Container(
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
        color: NexGenPalette.matteBlack,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // House image
            if (hasCustomImage)
              Image.network(houseImageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/Demohomephoto.jpg', fit: BoxFit.cover,
                ),
              )
            else
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover),

            // Gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Roofline pixel overlay — static frame using previewFrameOffset
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedRooflineOverlay(
                    previewColors: colors,
                    previewEffectId: _fxId,
                    previewSpeed: meta.isMotion ? _speed : 0,
                    forceOn: true,
                    targetAspectRatio: constraints.maxWidth / constraints.maxHeight,
                    useBoxFitCover: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 3: Effect Details (2-column grid)
  // ---------------------------------------------------------------------------

  Widget _buildEffectDetails(EffectDisplayMeta meta, List<Color> colors) {
    final briPct = (_bri * 100 / 255).round();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Row 1: Effect + Motion
          Row(
            children: [
              Expanded(child: _detailCell('Effect', meta.name)),
              Expanded(child: _detailCell('Motion', meta.isMotion ? 'Yes' : 'No')),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Speed + Brightness
          Row(
            children: [
              Expanded(child: _detailCell('Speed', meta.isMotion ? _speedLabel : '—')),
              Expanded(child: _detailCell('Brightness', '$briPct%')),
            ],
          ),
          const SizedBox(height: 10),
          // Row 3: Colors
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Colors',
                style: TextStyle(
                  fontSize: 10,
                  color: NexGenPalette.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              for (final c in colors)
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: NexGenPalette.line, width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: c.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: NexGenPalette.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: NexGenPalette.textHigh,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Section 4: Actions
  // ---------------------------------------------------------------------------

  Widget _buildActions(BuildContext context, WidgetRef ref, Color accent) {
    return Row(
      children: [
        // Preview Now
        Expanded(
          child: _actionButton(
            label: 'Preview Now',
            icon: Icons.play_arrow_rounded,
            color: accent,
            onTap: () => _previewNow(context, ref),
          ),
        ),
        const SizedBox(width: 8),
        // Edit
        Expanded(
          child: _actionButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            color: NexGenPalette.textMedium,
            onTap: () {
              Navigator.of(context).pop();
              // TODO: wire to schedule edit flow once available
            },
          ),
        ),
        const SizedBox(width: 8),
        // Remove
        Expanded(
          child: _actionButton(
            label: 'Remove',
            icon: Icons.delete_outline,
            color: Colors.redAccent,
            onTap: () => _confirmRemove(context, ref),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewNow(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null || event.wledPayload == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }
    final success = await repo.applyJson(event.wledPayload!);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Previewing: ${event.patternName}' : 'Failed to send to device'),
          backgroundColor: success ? NexGenPalette.gunmetal : Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Remove Event?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${event.patternName}" from your schedule?',
          style: TextStyle(color: NexGenPalette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final uid = ref.read(authStateProvider).maybeWhen(
      data: (u) => u?.uid,
      orElse: () => null,
    );
    if (uid != null) {
      final eventRepo = ref.read(autopilotEventRepositoryProvider);
      await eventRepo.deleteEvent(uid, event.id);
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Section 5: Footer
  // ---------------------------------------------------------------------------

  Widget _buildFooter() {
    final lowConfidence = event.confidenceScore < 0.8;
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 12, color: NexGenPalette.textSecondary.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(
          'Scheduled by Lumina AI',
          style: TextStyle(
            fontSize: 10,
            color: NexGenPalette.textSecondary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '·  Tap Edit to customize',
          style: TextStyle(
            fontSize: 10,
            color: NexGenPalette.textSecondary.withValues(alpha: 0.4),
          ),
        ),
        if (lowConfidence) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Best match available',
              style: TextStyle(
                fontSize: 9,
                color: Colors.orange.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
