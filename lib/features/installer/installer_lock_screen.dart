import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// The "Installer Access Required" screen an installer-only tool shows when
/// installer mode is not active. Lifted from the Roofline Setup Wizard (+113)
/// so Segment Setup can use the very same lock; the wizard's wording is
/// unchanged.
///
/// [featureName] completes "… is only available to certified installers."
/// When the customer has a way to do the job themselves, [alternativeLabel]
/// / [onAlternative] offer it beside "Go Back".
class InstallerLockScreen extends StatelessWidget {
  const InstallerLockScreen({
    super.key,
    required this.title,
    required this.featureName,
    this.alternativeLabel,
    this.onAlternative,
  });

  /// App-bar title, the locked screen's own name.
  final String title;

  /// Subject of the explanation, e.g. "The Roofline Setup Wizard".
  final String featureName;

  final String? alternativeLabel;
  final VoidCallback? onAlternative;

  @override
  Widget build(BuildContext context) {
    final alternative = alternativeLabel != null && onAlternative != null;
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Installer Access Required',
                key: const ValueKey('installer-lock-title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$featureName is only available to certified installers. '
                'This ensures your LED system is configured correctly for '
                'optimal performance.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (alternative)
                    FilledButton.icon(
                      key: const ValueKey('installer-lock-alternative'),
                      onPressed: onAlternative,
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(alternativeLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  if (alternative)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexGenPalette.textHigh,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
