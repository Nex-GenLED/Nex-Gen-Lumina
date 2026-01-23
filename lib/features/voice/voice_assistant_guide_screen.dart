import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/voice/alexa_service.dart';
import 'package:nexgen_command/features/voice/voice_providers.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/voice/widgets/siri_button.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen that guides users through setting up voice assistant integration.
///
/// Shows platform-specific instructions for:
/// - iOS: Siri Shortcuts (native, built-in)
/// - Android: Google Assistant with App Actions
/// - All platforms: Amazon Alexa Smart Home Skill
/// - All platforms: Home Assistant for advanced users
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

          // Platform-specific primary section
          if (Platform.isIOS) ...[
            _buildSiriSection(context, ref),
            const SizedBox(height: 16),
          ] else if (Platform.isAndroid) ...[
            _buildGoogleAssistantSection(context, ref),
            const SizedBox(height: 16),
          ],

          // Alexa section (all platforms)
          _buildAlexaSection(context, ref),
          const SizedBox(height: 16),

          // Secondary platform section (show the other one)
          if (Platform.isIOS) ...[
            _buildGoogleAssistantSection(context, ref, isSecondary: true),
            const SizedBox(height: 16),
          ] else if (Platform.isAndroid) ...[
            _buildSiriSection(context, ref, isSecondary: true),
            const SizedBox(height: 16),
          ],

          // Home Assistant section (all platforms)
          _buildHomeAssistantSection(context),
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
              'Say "Hey Siri, set my lights to game day mode" or "Alexa, turn on the house lights".',
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

  Widget _buildGoogleAssistantSection(BuildContext context, WidgetRef ref, {bool isSecondary = false}) {
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
                        'Google Assistant',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        Platform.isAndroid ? 'Built-in App Actions' : 'For Android users',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.cyan,
                            ),
                      ),
                    ],
                  ),
                ),
                if (Platform.isAndroid)
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
                'Google Assistant App Actions are available on Android devices. If you have an Android phone, open the app there to use voice commands.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else ...[
              Text(
                'Google Assistant works automatically with Lumina! Just say:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _buildVoiceCommandExample(context, '"Hey Google, turn on the lights in Lumina"'),
              _buildVoiceCommandExample(context, '"Hey Google, turn off the lights in Lumina"'),
              _buildVoiceCommandExample(context, '"Hey Google, set Lumina brightness to 50%"'),
              _buildVoiceCommandExample(context, '"Hey Google, activate Party Mode in Lumina"'),
              const SizedBox(height: 16),

              Text(
                'Quick Shortcuts',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
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
                title: 'Create a Routine (Optional)',
                description: 'In Google Home app, create a Routine that opens a shortcut with a custom phrase.',
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
                        'Voice commands work best when you say "in Lumina" at the end.',
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

  Widget _buildAlexaSection(BuildContext context, WidgetRef ref) {
    final linkStatusAsync = ref.watch(alexaLinkStatusProvider);
    final alexaService = ref.read(alexaServiceProvider);

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
                        'Smart Home Skill',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.cyan,
                            ),
                      ),
                    ],
                  ),
                ),
                linkStatusAsync.when(
                  data: (status) {
                    if (status == AlexaLinkStatus.linked) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'Linked',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.green,
                              ),
                        ),
                      );
                    } else if (status == AlexaLinkStatus.pending) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'Pending',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.amber.shade700,
                              ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Voice command examples
            Text(
              'Say things like:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            ...alexaService.getExampleCommands().take(3).map((cmd) {
              return _buildVoiceCommandExample(context, cmd);
            }),
            const SizedBox(height: 16),

            // Status-specific content
            linkStatusAsync.when(
              data: (status) {
                if (status == AlexaLinkStatus.linked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Alexa is connected! Your lights and scenes are ready to control.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => alexaService.discoverDevices(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Rediscover Devices'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Unlink Alexa?'),
                                  content: const Text(
                                    'You can re-link at any time. You should also disable the skill in the Alexa app.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Unlink'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await alexaService.unlinkAccount();
                              }
                            },
                            child: const Text('Unlink'),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                // Not linked - show setup steps
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStep(
                      context,
                      number: 1,
                      title: 'Enable the Skill',
                      description: 'Open the Alexa app and search for "Nex-Gen Lumina" in Skills.',
                    ),
                    _buildStep(
                      context,
                      number: 2,
                      title: 'Link Your Account',
                      description: 'Sign in with your Lumina account to connect.',
                    ),
                    _buildStep(
                      context,
                      number: 3,
                      title: 'Discover Devices',
                      description: 'Say "Alexa, discover my devices" to find your lights and scenes.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => alexaService.initiateAccountLinking(),
                        icon: const Icon(Icons.link),
                        label: const Text('Link Alexa Account'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00CAFF),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (status == AlexaLinkStatus.pending) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_top, color: Colors.amber.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Linking in progress. Complete the setup in the Alexa app.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStep(
                    context,
                    number: 1,
                    title: 'Enable the Skill',
                    description: 'Open the Alexa app and search for "Nex-Gen Lumina" in Skills.',
                  ),
                  _buildStep(
                    context,
                    number: 2,
                    title: 'Link Your Account',
                    description: 'Sign in with your Lumina account to connect.',
                  ),
                  _buildStep(
                    context,
                    number: 3,
                    title: 'Discover Devices',
                    description: 'Say "Alexa, discover my devices" to find your lights and scenes.',
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
            _buildFeatureRow(context, Icons.check_circle, 'Native WLED integration built-in'),
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
                label: const Text('View WLED Integration Guide'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceCommandExample(BuildContext context, String command) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.format_quote,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                command,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
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
