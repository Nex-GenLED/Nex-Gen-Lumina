import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen that guides users through setting up voice assistant integration.
///
/// Shows platform-specific instructions for:
/// - iOS: Siri Shortcuts
/// - Android: Google Assistant Routines
/// - All platforms: Home Assistant setup for full voice control
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

          // Platform-specific section
          if (Platform.isIOS) ...[
            _buildSiriSection(context),
            const SizedBox(height: 16),
          ] else if (Platform.isAndroid) ...[
            _buildGoogleAssistantSection(context),
            const SizedBox(height: 16),
          ],

          // Home Assistant section (all platforms)
          _buildHomeAssistantSection(context),
          const SizedBox(height: 16),

          // Alexa section
          _buildAlexaSection(context),
          const SizedBox(height: 80),
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
              'Say "Hey Siri, set my lights to game day mode" or ask Alexa to turn on your lights.',
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

  Widget _buildSiriSection(BuildContext context) {
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
                        'Recommended for iPhone',
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
            _buildStep(
              context,
              number: 1,
              title: 'Save Your Scenes',
              description: 'Go to Explore Patterns → My Scenes and save your favorite lighting setups.',
            ),
            _buildStep(
              context,
              number: 2,
              title: 'Add to Siri',
              description: 'Tap the Siri button on any scene to record a custom voice phrase.',
            ),
            _buildStep(
              context,
              number: 3,
              title: 'Use Your Voice',
              description: 'Say "Hey Siri, [your phrase]" to activate the scene instantly.',
            ),
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
        ),
      ),
    );
  }

  Widget _buildGoogleAssistantSection(BuildContext context) {
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
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.red, Colors.yellow, Colors.green],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.assistant,
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
                        'Google Assistant Routines',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'For Android devices',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.cyan,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildStep(
              context,
              number: 1,
              title: 'Long-Press App Icon',
              description: 'Long-press the Lumina icon on your home screen to see quick shortcuts.',
            ),
            _buildStep(
              context,
              number: 2,
              title: 'Add to Home Screen',
              description: 'Drag any shortcut to your home screen for one-tap access.',
            ),
            _buildStep(
              context,
              number: 3,
              title: 'Create a Routine',
              description: 'In Google Home app, create a Routine that opens a shortcut when you say a phrase.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.violet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.violet.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: NexGenPalette.violet, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Note: Google Routines require the Lumina app to open briefly.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                        'Full voice control with any assistant',
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
              'For the most seamless voice experience, connect your lights to Home Assistant. '
              'This enables full voice control with Siri, Google Assistant, AND Alexa—without opening the app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildFeatureRow(context, Icons.check_circle, 'Control lights without opening the app'),
            _buildFeatureRow(context, Icons.check_circle, 'Works with Siri, Google, AND Alexa'),
            _buildFeatureRow(context, Icons.check_circle, 'Create complex automations'),
            _buildFeatureRow(context, Icons.check_circle, 'Native smart light integration built-in'),
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
                onPressed: () => _launchUrl('https://www.home-assistant.io/integrations/light/'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('View Setup Guide'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlexaSection(BuildContext context) {
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
                    color: const Color(0xFF00CAFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.smart_display,
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
                        'Amazon Alexa',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Via Home Assistant',
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
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    'Coming Soon',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.amber.shade700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Native Alexa skill coming soon! In the meantime, connect via Home Assistant for full Alexa voice control.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'We\'ll notify you when the Alexa skill is ready!',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
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
