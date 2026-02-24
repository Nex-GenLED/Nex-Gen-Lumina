import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/nav.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simplified settings screen for Simple Mode.
/// Shows only essential settings: favorites, voice setup, support, and mode toggle.
class SimpleSettings extends ConsumerWidget {
  const SimpleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          // My Favorites Card
          _buildMyFavoritesCard(context, ref),
          const SizedBox(height: 16),

          // Voice Setup Card
          _buildVoiceSetupCard(context),
          const SizedBox(height: 16),

          // Support Card
          _buildSupportCard(context),
          const SizedBox(height: 16),

          // Advanced Settings (Exit Simple Mode)
          _buildAdvancedSettingsCard(context, ref),
        ],
      ),
    );
  }

  Widget _buildMyFavoritesCard(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(simpleFavoritesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star, color: NexGenPalette.cyan, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'My Favorites',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose up to 5 favorite lighting patterns for quick access',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            favoritesAsync.when(
              data: (favorites) => _FavoritesEditor(favorites: favorites),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Center(
                child: Text('Failed to load favorites: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSetupCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [NexGenPalette.violet, NexGenPalette.cyan],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 24),
            ),
            title: const Text('Voice Assistants'),
            subtitle: const Text('Set up Siri, Google Assistant, or Alexa'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.voiceAssistants),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.ondemand_video, color: Theme.of(context).colorScheme.error),
            title: const Text('Video Tutorials'),
            subtitle: const Text('Step-by-step guides for voice control'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openVideoTutorials(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.support_agent, color: NexGenPalette.cyan, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Support',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone),
            title: const Text('Call Support'),
            subtitle: const Text('1-800-NEX-GEN'),
            onTap: () => _callSupport(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.email),
            title: const Text('Email Support'),
            subtitle: const Text('support@nex-gen.io'),
            onTap: () => _emailSupport(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.chat),
            title: const Text('Live Chat'),
            subtitle: const Text('Chat with our support team'),
            onTap: () => _openChat(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.quiz),
            title: const Text('Help & FAQ'),
            subtitle: const Text('Find answers to common questions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.helpCenter),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSettingsCard(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.settings, color: NexGenPalette.violet, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Advanced Settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.exit_to_app, color: NexGenPalette.cyan),
            ),
            title: const Text('Exit Simple Mode'),
            subtitle: const Text('Switch to full app with all features'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _confirmExitSimpleMode(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: const Text('Full Settings'),
            subtitle: const Text('Access all app settings (Advanced)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.settingsSystem),
          ),
        ],
      ),
    );
  }

  Future<void> _openVideoTutorials(BuildContext context) async {
    final uri = Uri.parse('https://www.youtube.com/@nexgen');
    await _safeLaunch(context, uri);
  }

  Future<void> _callSupport(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: '18006394436');
    await _safeLaunch(context, uri);
  }

  Future<void> _emailSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@nex-gen.io',
      queryParameters: {'subject': 'Nex-Gen Support Request'},
    );
    await _safeLaunch(context, uri);
  }

  Future<void> _openChat(BuildContext context) async {
    // TODO: Implement live chat integration
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live chat coming soon! Please use email or phone for now.')),
    );
  }

  Future<void> _safeLaunch(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open link')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch: $e')),
        );
      }
    }
  }

  Future<void> _confirmExitSimpleMode(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Simple Mode?'),
        content: const Text(
          'This will show all app features and navigation tabs. You can always return to Simple Mode from Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit Simple Mode'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ref.read(simpleModeProvider.notifier).disable();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simple Mode disabled. All features now available.')),
      );
    }
  }
}

/// Editor for managing Simple Mode favorites
class _FavoritesEditor extends ConsumerWidget {
  final List<String> favorites;

  const _FavoritesEditor({required this.favorites});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current favorites list
        if (favorites.isEmpty)
          _buildEmptyState(context, ref)
        else
          ...favorites.map((patternId) => _FavoriteListItem(
                patternId: patternId,
                onRemove: () => ref.read(simpleFavoritesProvider.notifier).removeFavorite(patternId),
              )),

        const SizedBox(height: 12),

        // Add favorite button
        if (favorites.length < 5)
          OutlinedButton.icon(
            onPressed: () => _showAddFavoriteDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add Favorite'),
          ),

        const SizedBox(height: 8),

        // Reset to defaults button
        TextButton.icon(
          onPressed: () => _confirmReset(context, ref),
          icon: const Icon(Icons.refresh),
          label: const Text('Reset to Defaults'),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Icon(Icons.star_border, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5), size: 48),
        const SizedBox(height: 12),
        Text(
          'No favorites yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(simpleFavoritesProvider.notifier).resetToDefaults(),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Add Default Favorites'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _showAddFavoriteDialog(BuildContext context, WidgetRef ref) async {
    final patterns = ref.read(publicPatternLibraryProvider);
    final favoritesAsync = ref.read(simpleFavoritesProvider);

    // Extract favorites list from AsyncValue
    final favorites = favoritesAsync.maybeWhen(
      data: (list) => list,
      orElse: () => <String>[],
    );

    // Build flat list of all patterns
    final allPatterns = patterns.all;

    // Filter out already-favorited patterns
    final availablePatterns = allPatterns.where((p) {
      final patternId = p.name.toLowerCase().replaceAll(' ', '_');
      return !favorites.contains(patternId);
    }).toList();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Favorite'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availablePatterns.length,
            itemBuilder: (c, i) {
              final pattern = availablePatterns[i];
              return ListTile(
                title: Text(pattern.name),
                onTap: () {
                  final patternId = pattern.name.toLowerCase().replaceAll(' ', '_');
                  ref.read(simpleFavoritesProvider.notifier).addFavorite(patternId);
                  Navigator.of(ctx).pop();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Favorites?'),
        content: const Text('This will replace your current favorites with the default set.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(simpleFavoritesProvider.notifier).resetToDefaults();
    }
  }
}

/// Individual favorite pattern list item
class _FavoriteListItem extends ConsumerWidget {
  final String patternId;
  final VoidCallback onRemove;

  const _FavoriteListItem({
    required this.patternId,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(publicPatternLibraryProvider);

    // Find the pattern by ID
    GradientPattern? pattern;
    for (final p in patterns.all) {
      if (p.name.toLowerCase().replaceAll(' ', '_') == patternId.toLowerCase()) {
        pattern = p;
        break;
      }
    }

    final displayName = pattern?.name ?? _getFallbackName(patternId);

    return ListTile(
      leading: Icon(Icons.star, color: NexGenPalette.cyan),
      title: Text(displayName),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onRemove,
        tooltip: 'Remove from favorites',
      ),
    );
  }

  String _getFallbackName(String id) {
    return id.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }
}
