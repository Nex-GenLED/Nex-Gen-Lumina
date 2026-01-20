import 'package:flutter/material.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = const [
      (
        'Lights are not responding.',
        'Ensure controller is powered (green LED). Try unplugging for 10 seconds to reboot.'
      ),
      (
        'How to reset Wi-Fi?',
        "Go to Device Setup > Select Controller > Wi-Fi Settings. You may need to connect to 'WLED-AP' first."
      ),
      (
        'Can I cut the strips?',
        'Yes, at the copper pads marked with cut lines. Ensure power is off first.'
      ),
      (
        "Schedule didn't run.",
        "Check 'Time & Macro' settings in Hardware Config to ensure your time zone is correct."
      ),
    ];

    final cs = Theme.of(context).colorScheme;
    final darkTile = cs.surfaceVariant; // dark grey-like surface on dark themes
    final textColor = cs.onSurface; // high-contrast text
    final iconColor = NexGenPalette.cyan; // brand accent

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Help Center')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Troubleshooting & FAQ', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          // FAQ list
          Expanded(
            child: Card(
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: faqs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final (q, a) = faqs[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: darkTile,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                        listTileTheme: Theme.of(context).listTileTheme.copyWith(iconColor: iconColor),
                        expansionTileTheme: Theme.of(context).expansionTileTheme.copyWith(
                          collapsedIconColor: iconColor,
                          iconColor: iconColor,
                          textColor: textColor,
                          collapsedTextColor: textColor,
                          backgroundColor: Colors.transparent,
                          collapsedBackgroundColor: Colors.transparent,
                        ),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        title: Text(q, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: textColor)),
                        leading: Icon(Icons.help_outline, color: iconColor),
                        children: [
                          Text(a, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor.withValues(alpha: 0.9))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
