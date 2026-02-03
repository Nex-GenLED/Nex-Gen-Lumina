import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// A premium glassmorphic card with optional accent bar and icon container.
/// Provides consistent styling across the app with frosted glass effect.
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.accentColor,
    this.showAccentBar = false,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.borderRadius = 16.0,
    this.enableBlur = true,
    this.blurSigma = 10.0,
    this.elevation = 0.0,
  });

  /// The content of the card.
  final Widget child;

  /// Optional accent color for the left bar and glow effects.
  /// Defaults to NexGenPalette.cyan if [showAccentBar] is true.
  final Color? accentColor;

  /// Whether to show a gradient accent bar on the left edge.
  final bool showAccentBar;

  /// Padding inside the card.
  final EdgeInsets padding;

  /// Margin outside the card.
  final EdgeInsets? margin;

  /// Optional tap callback.
  final VoidCallback? onTap;

  /// Corner radius of the card.
  final double borderRadius;

  /// Whether to enable the frosted glass blur effect.
  final bool enableBlur;

  /// Blur intensity (sigma value).
  final double blurSigma;

  /// Shadow elevation.
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final effectiveAccentColor = accentColor ?? NexGenPalette.cyan;

    Widget cardContent = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: showAccentBar
              ? effectiveAccentColor.withValues(alpha: 0.3)
              : NexGenPalette.line,
          width: 1,
        ),
        boxShadow: [
          if (elevation > 0 || showAccentBar)
            BoxShadow(
              color: showAccentBar
                  ? effectiveAccentColor.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.2),
              blurRadius: elevation > 0 ? elevation * 2 : 16,
              offset: Offset(0, elevation > 0 ? elevation : 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // Frosted glass background
            if (enableBlur)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          NexGenPalette.gunmetal90.withValues(alpha: 0.8),
                          NexGenPalette.matteBlack.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        NexGenPalette.gunmetal90,
                        NexGenPalette.matteBlack.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                ),
              ),

            // Accent bar on left edge
            if (showAccentBar)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(borderRadius),
                      bottomLeft: Radius.circular(borderRadius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        effectiveAccentColor,
                        effectiveAccentColor.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),

            // Content with padding
            Padding(
              padding: showAccentBar
                  ? padding.copyWith(left: padding.left + 4)
                  : padding,
              child: child,
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}

/// A card with a prominent icon header, suitable for settings sections.
class PremiumIconCard extends StatelessWidget {
  const PremiumIconCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accentColor,
    this.iconBackgroundGradient,
    this.showChevron = true,
    this.badge,
  });

  /// The icon to display.
  final IconData icon;

  /// The title text.
  final String title;

  /// Optional subtitle text.
  final String? subtitle;

  /// Optional trailing widget (overrides chevron).
  final Widget? trailing;

  /// Optional tap callback.
  final VoidCallback? onTap;

  /// Accent color for the icon background.
  final Color? accentColor;

  /// Custom gradient for icon background.
  final Gradient? iconBackgroundGradient;

  /// Whether to show a chevron arrow when tappable.
  final bool showChevron;

  /// Optional badge widget (e.g., count indicator).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final effectiveAccentColor = accentColor ?? NexGenPalette.cyan;
    final effectiveGradient = iconBackgroundGradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            effectiveAccentColor,
            effectiveAccentColor.withValues(alpha: 0.6),
          ],
        );

    return PremiumCard(
      showAccentBar: true,
      accentColor: effectiveAccentColor,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Icon container with gradient
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: effectiveGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: effectiveAccentColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      badge!,
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Trailing widget or chevron
          if (trailing != null)
            trailing!
          else if (onTap != null && showChevron)
            Icon(
              Icons.chevron_right,
              color: effectiveAccentColor.withValues(alpha: 0.7),
              size: 24,
            ),
        ],
      ),
    );
  }
}

/// A status indicator dot with optional pulse animation.
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.isOnline,
    this.size = 10,
    this.animate = true,
  });

  /// Whether the status is online/active.
  final bool isOnline;

  /// Size of the dot.
  final double size;

  /// Whether to animate when online.
  final bool animate;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isOnline && widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isOnline
        ? const Color(0xFF4CAF50) // Green
        : const Color(0xFFFF5252); // Red

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: widget.isOnline && widget.animate
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: _animation.value * 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

/// A count badge for displaying numbers.
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.color,
    this.textColor,
  });

  final int count;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? NexGenPalette.cyan.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (color ?? NexGenPalette.cyan).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        count.toString(),
        style: TextStyle(
          color: textColor ?? NexGenPalette.cyan,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
