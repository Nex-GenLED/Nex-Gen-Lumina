import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// A help button that shows contextual guidance when tapped.
/// Use this throughout the app to provide inline help for complex features.
class HelpButton extends StatelessWidget {
  /// The title of the help dialog
  final String title;

  /// The main explanation text
  final String explanation;

  /// Optional tip or pro-tip to show
  final String? tip;

  /// Optional icon to show in the dialog title
  final IconData? icon;

  /// Size of the help button icon
  final double size;

  /// Color of the help button icon
  final Color? color;

  const HelpButton({
    super.key,
    required this.title,
    required this.explanation,
    this.tip,
    this.icon,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.help_outline,
        size: size,
        color: color ?? Colors.grey.shade400,
      ),
      tooltip: 'Help',
      onPressed: () => _showHelpDialog(context),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              icon ?? Icons.lightbulb_outline,
              color: NexGenPalette.cyan,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: NexGenPalette.textHigh),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              explanation,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            if (tip != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: NexGenPalette.cyan.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates,
                      size: 18,
                      color: NexGenPalette.cyan,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tip',
                            style: TextStyle(
                              color: NexGenPalette.cyan,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tip!,
                            style: const TextStyle(
                              color: NexGenPalette.textMedium,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Got it',
              style: TextStyle(color: NexGenPalette.cyan),
            ),
          ),
        ],
      ),
    );
  }
}

/// A smaller inline help icon that can be placed next to labels
class InlineHelpIcon extends StatelessWidget {
  final String title;
  final String explanation;
  final String? tip;

  const InlineHelpIcon({
    super.key,
    required this.title,
    required this.explanation,
    this.tip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showHelpDialog(context),
      child: Icon(
        Icons.help_outline,
        size: 16,
        color: Colors.grey.shade400,
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    final helpButton = HelpButton(
      title: title,
      explanation: explanation,
      tip: tip,
    );
    helpButton._showHelpDialog(context);
  }
}

/// A help tooltip that appears when user long-presses a widget
class HelpTooltip extends StatelessWidget {
  final Widget child;
  final String message;

  const HelpTooltip({
    super.key,
    required this.child,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
      ),
      textStyle: const TextStyle(
        color: NexGenPalette.textHigh,
        fontSize: 13,
      ),
      waitDuration: const Duration(milliseconds: 800),
      showDuration: const Duration(seconds: 4),
      child: child,
    );
  }
}
