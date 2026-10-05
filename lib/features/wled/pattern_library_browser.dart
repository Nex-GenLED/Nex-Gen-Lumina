import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/pattern_apply_gate.dart';
import 'package:nexgen_command/features/wled/usage_tracking_extension.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart' show executeCustomEffectIfNeeded;
import 'package:nexgen_command/utils/effect_display_meta.dart';

/// A Recent Patterns card at the default text size. Owner request from live
/// use, 2026-10-05: the width is unchanged and the height is cut by a third,
/// from 100 to 66, so the section takes less of Explore. Larger Text makes the
/// card taller when its labels need it; it never makes it wider.
@visibleForTesting
const double kRecentPatternCardWidth = 120;
@visibleForTesting
const double kRecentPatternCardMinHeight = 66;

/// Above this text scale the card stops fitting one line of name, one line of
/// effect and the time badge in [kRecentPatternCardMinHeight]: the badge and
/// the motion icon give way, and the name and effect may each wrap to two
/// lines.
const double _kRecentCardLargeTextScale = 1.3;

/// The card's inner padding either side, and the room the motion icon and its
/// gap take in front of the effect name.
const double _kRecentCardSidePadding = 8;
const double _kRecentCardIconSlot = 16;

class RecentPatternsSection extends ConsumerWidget {
  const RecentPatternsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentPatternsProvider);

    return recentAsync.when(
      data: (patterns) {
        if (patterns.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Icon(Icons.history_rounded, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Patterns',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal scrolling row of recent patterns (most recent on
            // left). At most five, so a plain Row; IntrinsicHeight gives every
            // card the height of the tallest — kRecentPatternCardMinHeight at
            // the default text size, more only when Larger Text needs it.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < patterns.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      _RecentPatternCard(
                        pattern: patterns[i],
                        onTap: () => _applyPattern(context, ref, patterns[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _applyPattern(BuildContext context, WidgetRef ref, GradientPattern pattern) async {
    // Captured before any await, so the reason below can still be shown.
    final container = ProviderScope.containerOf(context, listen: false);
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      // Row 1: the shared reason, not "No device connected" for every case.
      await reportApplyBlocked(container);
      return;
    }

    try {
      // Build WLED JSON payload from pattern
      final colors = pattern.colors.map((c) {
        final rgbw = rgbToRgbw(
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
          forceZeroWhite: true,
        );
        return [rgbw[0], rgbw[1], rgbw[2], rgbw[3]];
      }).toList();

      // Check if this is a custom Lumina effect (ID >= 1000)
      final isCustomEffect = await executeCustomEffectIfNeeded(
        effectId: pattern.effectId,
        colors: colors.isNotEmpty ? colors.take(3).toList() : [[255, 180, 100, 0]],
        repo: repo,
      );

      if (!isCustomEffect) {
        // Standard WLED effect. No `bri`: replaying a recent look must not
        // jump the house to the level it happened to be at then (the rule
        // Explore's Apply follows since +110, P10).
        final payload = <String, dynamic>{
          'on': true,
          'seg': [
            {
              'fx': pattern.effectId,
              'sx': pattern.speed,
              'ix': pattern.intensity,
              'col': colors.isNotEmpty ? colors.take(3).toList() : [[255, 180, 100, 0]],
            }
          ],
        };

        // Row 1: the notifier's gated apply waits for a channel source that
        // is still answering and, when the gate is closed, reports WHY
        // instead of returning in silence. It also mirrors the look into the
        // Home preview and Now Playing, which this path never did.
        final notifier = ref.read(wledStateProvider.notifier);
        final result = await notifier.runAndReport(
          notifier.applyToDeviceResult(payload, labelHint: pattern.name),
          onFailure: "Couldn't apply ${pattern.name} — check your connection",
        );
        if (!result.ok || !context.mounted) return;
        // Row 19: a Recent apply is a use — it moves to the front.
        await ref.trackWledPayload(
            payload: payload, patternName: pattern.name, source: 'recent');
      }

      ref.read(activePresetLabelProvider.notifier).setLabelWithFingerprint(pattern.name, ref.read(wledStateProvider));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied: ${pattern.name}')),
        );
      }
      maybeShowManualApplyOffWarning(ref);
    } catch (e) {
      debugPrint('Apply recent pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply pattern')),
        );
      }
    }
  }
}

/// Card for one recent pattern: its colours as the background, its name, and
/// the effect it plays.
///
/// At the default text size it is [kRecentPatternCardWidth] by
/// [kRecentPatternCardMinHeight]: the name on one line, the effect on one line
/// after a motion icon, and how long ago it was used in the corner. Past
/// [_kRecentCardLargeTextScale] the badge and the icon give way, the name and
/// the effect may each take two lines, and the card grows taller to hold them.
class _RecentPatternCard extends StatelessWidget {
  final GradientPattern pattern;
  final VoidCallback onTap;

  const _RecentPatternCard({
    required this.pattern,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = pattern.colors.isNotEmpty
        ? pattern.colors
        : const [Color(0xFFFFB347), Color(0xFFFFE4B5)];
    // The controller's own name for the effect a tap sends (#167 catalog) —
    // not the stored `effect_name`, which only two writers set and which can
    // predate #167. An entry without an fx id is sent as fx 0, so reads
    // "Solid".
    final effect = EffectDisplayMeta.fromId(pattern.effectId);
    final ago = pattern.subtitle ?? '';
    final large = MediaQuery.textScalerOf(context).scale(1) >
        _kRecentCardLargeTextScale;
    final textTheme = Theme.of(context).textTheme;
    final shadows = [
      Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4),
    ];
    final effectStyle = textTheme.labelSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
      shadows: shadows,
    );
    final showIcon =
        !large && _effectFitsBesideIcon(context, effect.name, effectStyle);
    final radius = BorderRadius.circular(12);

    final card = Container(
      width: kRecentPatternCardWidth,
      constraints:
          const BoxConstraints(minHeight: kRecentPatternCardMinHeight),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Dark overlay, so the labels read on any colourway.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.1),
              Colors.black.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: _kRecentCardSidePadding, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Time ago badge
              if (!large && ago.isNotEmpty)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ago,
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                pattern.name,
                key: const ValueKey('recent-card-name'),
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: shadows,
                ),
                maxLines: large ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  if (showIcon) ...[
                    Icon(
                      effect.isMotion ? Icons.animation_rounded : Icons.circle,
                      key: const ValueKey('recent-card-motion-icon'),
                      size: _kRecentCardIconSlot - 4,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      effect.name,
                      key: const ValueKey('recent-card-effect'),
                      style: effectStyle,
                      maxLines: large ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // One node that reads the name, the effect and when, in that order.
    // ExcludeSemantics rather than `excludeSemantics:` keeps the labels
    // visible to the text-scale harness, which skips excluded subtrees.
    return Semantics(
      container: true,
      button: true,
      label: [pattern.name, '${effect.name} effect', if (ago.isNotEmpty) ago]
          .join(', '),
      onTap: onTap,
      child: ExcludeSemantics(
        // A name or effect cut short on the card can still be read in full.
        child: Tooltip(
          message: '${pattern.name} · ${effect.name}',
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: card,
          ),
        ),
      ),
    );
  }

  /// Whether [label] still fits on one line with the motion icon in front of
  /// it. The icon is optional: it gives way before the effect name is cut.
  /// Measured as the Text will lay it out — the ambient text scale, and Bold
  /// Text — against the card's fixed inner width.
  static bool _effectFitsBesideIcon(
      BuildContext context, String label, TextStyle? style) {
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      text: TextSpan(text: label, style: effective),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width <=
        kRecentPatternCardWidth -
            2 * _kRecentCardSidePadding -
            _kRecentCardIconSlot;
  }
}

// Row 89 — the legacy PINNED tree is retired (+110 E1, 2026-09-29).
//
// `PinnedCategoriesSection` (a row per pinned folder, with 'See All' and
// sub-category chips into `CategoryDetailScreen` / `ThemeSelectionScreen`)
// lived here. The only Pin button was on `CategoryDetailScreen`, which is
// reachable only FROM a pinned row, so no account could ever start pinning,
// and the tree it led to is a second, older copy of the catalogue (the
// legacy sub-category list, not the library) carrying rows 20, 21, 90 and
// 91. Explore's library folders are the one way in.

/// GPU-friendly animated gradient strip that simulates a flowing/chase effect
/// using a LinearGradient and a lightweight GradientTransform.
///
/// Pass a list of colors for the gradient and a speed value (0 = static).
class LiveGradientStrip extends StatefulWidget {
  final List<Color> colors;
  final double speed; // Typical range 0..255
  const LiveGradientStrip({super.key, required this.colors, required this.speed});

  @override
  State<LiveGradientStrip> createState() => _LiveGradientStripState();
}

class _LiveGradientStripState extends State<LiveGradientStrip> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Map speed (0..255) to a loop duration. Faster speed -> shorter duration.
  Duration _durationFor(double speed) {
    final s = speed.clamp(0, 255);
    final ms = 4200 - (s / 255) * 3600; // ~4.2s slow -> ~0.6s fast
    final clamped = ms.clamp(350, 8000).round();
    return Duration(milliseconds: clamped);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _durationFor(widget.speed));
    _maybeStart();
  }

  void _maybeStart() {
    if (widget.speed <= 0) {
      _controller.stop();
      _controller.value = 0; // static
    } else {
      _controller.duration = _durationFor(widget.speed);
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiveGradientStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _maybeStart();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> get _effectiveColors {
    if (widget.colors.isEmpty) return const [Colors.white, Colors.white];
    if (widget.colors.length == 1) return [widget.colors.first, widget.colors.first];
    return widget.colors;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _effectiveColors;

    // Static gradient when speed == 0
    if (widget.speed <= 0) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: colors),
        ),
      );
    }

    // Animated: slide the gradient horizontally in a seamless loop
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: colors,
              tileMode: TileMode.mirror,
              transform: _SlidingGradientTransform(_controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent; // 0..1
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * slidePercent;
    // Translate around the center to avoid edge stretching
    final m = Matrix4.identity();
    m.translate(dx);
    return m;
  }
}