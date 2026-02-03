import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// A consistent section header with icon, title, and optional action button.
/// Used throughout the app for visual hierarchy.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.action,
    this.actionLabel,
    this.onActionTap,
    this.showUnderline = false,
    this.uppercase = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  /// The section title text.
  final String title;

  /// Optional leading icon.
  final IconData? icon;

  /// Color for the icon. Defaults to cyan.
  final Color? iconColor;

  /// Optional action widget on the right.
  final Widget? action;

  /// Label for the action button (used with onActionTap).
  final String? actionLabel;

  /// Callback when action is tapped.
  final VoidCallback? onActionTap;

  /// Whether to show an accent underline.
  final bool showUnderline;

  /// Whether to display title in uppercase.
  final bool uppercase;

  /// Padding around the header.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? NexGenPalette.cyan;
    final displayTitle = uppercase ? title.toUpperCase() : title;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Icon with glow
              if (icon != null) ...[
                Icon(
                  icon,
                  color: effectiveIconColor,
                  size: 18,
                  shadows: [
                    Shadow(
                      color: effectiveIconColor.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],

              // Title
              Expanded(
                child: Text(
                  displayTitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: NexGenPalette.textMedium,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),

              // Action button
              if (action != null)
                action!
              else if (actionLabel != null && onActionTap != null)
                TextButton(
                  onPressed: onActionTap,
                  style: TextButton.styleFrom(
                    foregroundColor: effectiveIconColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel!,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 10, color: effectiveIconColor),
                    ],
                  ),
                ),
            ],
          ),

          // Accent underline
          if (showUnderline) ...[
            const SizedBox(height: 8),
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    effectiveIconColor,
                    effectiveIconColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A larger section header variant for major page sections.
class MajorSectionHeader extends StatelessWidget {
  const MajorSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.action,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? NexGenPalette.cyan;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon with gradient background
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    effectiveIconColor,
                    effectiveIconColor.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: effectiveIconColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                  ),
                ],
              ],
            ),
          ),

          // Action
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A divider with optional label for separating sections.
class SectionDivider extends StatelessWidget {
  const SectionDivider({
    super.key,
    this.label,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  final String? label;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return Padding(
        padding: padding,
        child: Container(
          height: 1,
          color: NexGenPalette.line,
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    NexGenPalette.line,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label!.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    letterSpacing: 1.5,
                  ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    NexGenPalette.line,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
