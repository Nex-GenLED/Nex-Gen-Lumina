import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/voice/widgets/siri_button.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Strings proposal item 3 (docs/overhaul-2026-10/APP_STRINGS_PROPOSAL.md,
/// FACTS T-VA1): the hero names the two things that work.
const String kVoiceGuideHeroText =
    'Say "Hey Siri, [your phrase]" to put a saved look on your lights. '
    'On Android, long-press the Lumina icon for shortcuts.';

/// The iPhone hero drops the Android sentence: App Review flags another
/// platform's name in an iOS app (2.3.10).
const String kVoiceGuideHeroTextIos =
    'Say "Hey Siri, [your phrase]" to put a saved look on your lights.';

/// The Android App Shortcuts box, without the assistant-linking sentence it
/// used to carry (item 3 removes the advertising, not the shortcuts).
const String kAppShortcutsText =
    'Long-press the Lumina app icon to access quick shortcuts without linking.';

/// Screen that guides users through setting up voice assistant integration.
///
/// Shows what works:
/// - iOS: Siri Shortcuts (native, built-in)
/// - Android: App Shortcuts (long-press the app icon)
/// - All platforms: Home Assistant for advanced users
/// The two assistant-linking cards were removed (strings proposal item 3,
/// FACTS T-VA1): linking has never worked and is not advertised.
class VoiceAssistantGuideScreen extends ConsumerWidget {
  const VoiceAssistantGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const GlassAppBar(
        title: Text('Voice Assistants'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero section
          _buildHeroSection(context),
          const SizedBox(height: 24),

          // Strings proposal item 3 (FACTS T-VA1): the two assistant-linking
          // cards are gone. Linking has never worked and is not advertised.
          // What remains is what works: Siri Shortcuts on iPhone and the
          // Android App Shortcuts box. (Restore the cards only when linking
          // is deployed and proven.)
          if (Platform.isAndroid) ...[
            _buildAppShortcutsSection(context),
            const SizedBox(height: 16),
            _buildSiriSection(context, ref, isSecondary: true),
            const SizedBox(height: 16),
          ] else ...[
            _buildSiriSection(context, ref),
            const SizedBox(height: 16),
          ],

          // Home Assistant section (all platforms)
          _buildHomeAssistantSection(context),
          SizedBox(height: navBarTotalHeight(context)),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [NexGenPalette.violet, NexGenPalette.cyan],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.mic,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Control Your Lights with Voice',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isIOS ? kVoiceGuideHeroTextIos : kVoiceGuideHeroText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSiriSection(BuildContext context, WidgetRef ref, {bool isSecondary = false}) {
    final allScenesAsync = ref.watch(allScenesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.mic,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Siri Shortcuts',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        Platform.isIOS ? 'Recommended for iPhone' : 'For iPhone users',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.cyan,
                            ),
                      ),
                    ],
                  ),
                ),
                if (Platform.isIOS)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      'Built-in',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.green,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            if (isSecondary) ...[
              Text(
                'Siri Shortcuts are available on iOS devices. If you have an iPhone, open the app there to set up Siri voice commands.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else ...[
              _buildStep(
                context,
                number: 1,
                title: 'Save Your Scenes',
                description: 'Go to Explore Patterns and save your favorite lighting setups as scenes.',
              ),
              _buildStep(
                context,
                number: 2,
                title: 'Add to Siri',
                description: 'Tap the "Add to Siri" button on any scene to record a custom voice phrase.',
              ),
              _buildStep(
                context,
                number: 3,
                title: 'Use Your Voice',
                description: 'Say "Hey Siri, [your phrase]" to activate the scene instantly.',
              ),

              // Show user's scenes with Add to Siri buttons
              if (Platform.isIOS) ...[
                const SizedBox(height: 16),
                Text(
                  'Your Scenes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                allScenesAsync.when(
                  data: (scenes) {
                    final userScenes = scenes.where((s) => s.type.name != 'system').take(4).toList();
                    if (userScenes.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Save some scenes first to add them to Siri.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: userScenes.map((scene) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SiriShortcutCard(scene: scene),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Text('Could not load scenes'),
                ),
              ],

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Use short, memorable phrases like "Game day" or "Movie time".',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The Android App Shortcuts box, kept from the removed linking card (item 3).
  Widget _buildAppShortcutsSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.violet.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.violet.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.touch_app, color: NexGenPalette.violet, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'App Shortcuts',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: NexGenPalette.violet,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                kAppShortcutsText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeAssistantSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF03A9F4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.home,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Home Assistant',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Advanced integration',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.cyan,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: NexGenPalette.violet.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: NexGenPalette.violet.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    'Pro',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: NexGenPalette.violet,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'For the most advanced smart home experience, connect your lights to Home Assistant. '
              'This enables native light entity integration with full color and effect control.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildFeatureRow(context, Icons.check_circle, 'Native LED controller integration'),
            _buildFeatureRow(context, Icons.check_circle, 'Works with any voice assistant'),
            _buildFeatureRow(context, Icons.check_circle, 'Advanced automations and triggers'),
            _buildFeatureRow(context, Icons.check_circle, 'Dashboard widgets and controls'),
            const SizedBox(height: 16),
            Text(
              'Requirements:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildRequirement(context, 'Raspberry Pi, NAS, or always-on computer'),
            _buildRequirement(context, 'Basic technical setup (one-time)'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _launchUrl('https://www.home-assistant.io/integrations/wled/'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('View Integration Guide'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required int number,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: NexGenPalette.cyan,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirement(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
