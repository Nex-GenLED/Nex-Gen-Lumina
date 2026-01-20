import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/voice/voice_providers.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';

/// Screen for viewing and managing all saved scenes.
///
/// This unified view shows:
/// - Custom designs from Design Studio
/// - Patterns saved from the library
/// - System presets
/// - Snapshots of device state
class MyScenesScreen extends ConsumerStatefulWidget {
  const MyScenesScreen({super.key});

  @override
  ConsumerState<MyScenesScreen> createState() => _MyScenesScreenState();
}

class _MyScenesScreenState extends ConsumerState<MyScenesScreen> {
  SceneFilter _filter = SceneFilter.all;
  bool _showSystemPresets = true;

  @override
  Widget build(BuildContext context) {
    final scenesAsync = ref.watch(allScenesProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('My Scenes'),
        actions: [
          // Filter menu
          PopupMenuButton<SceneFilter>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter scenes',
            onSelected: (filter) => setState(() => _filter = filter),
            itemBuilder: (context) => [
              _buildFilterItem(SceneFilter.all, 'All Scenes', Icons.apps),
              _buildFilterItem(SceneFilter.custom, 'Custom Designs', Icons.design_services),
              _buildFilterItem(SceneFilter.library, 'Saved Patterns', Icons.auto_awesome),
              _buildFilterItem(SceneFilter.favorites, 'Favorites', Icons.favorite),
              const PopupMenuDivider(),
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(
                      _showSystemPresets ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text('Show System Presets'),
                  ],
                ),
                onTap: () => setState(() => _showSystemPresets = !_showSystemPresets),
              ),
            ],
          ),
          // Create new
          IconButton(
            onPressed: () => _showCreateOptions(context),
            icon: const Icon(Icons.add),
            tooltip: 'Create Scene',
          ),
        ],
      ),
      body: scenesAsync.when(
        data: (scenes) {
          final filteredScenes = _filterScenes(scenes);
          if (filteredScenes.isEmpty) {
            return _EmptyState(
              filter: _filter,
              onCreateNew: () => context.push('/design-studio'),
            );
          }
          return _ScenesList(
            scenes: filteredScenes,
            onApply: (scene) => _applyScene(context, ref, scene),
            onEdit: (scene) => _editScene(context, ref, scene),
            onDelete: (scene) => _deleteScene(context, ref, scene),
            onToggleFavorite: (scene) => _toggleFavorite(ref, scene),
            onAddToSiri: Platform.isIOS ? (scene) => _addToSiri(context, ref, scene) : null,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading scenes: $error'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.invalidate(designsStreamProvider);
                  ref.invalidate(savedScenesStreamProvider);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('New Scene'),
        backgroundColor: NexGenPalette.cyan,
      ),
    );
  }

  PopupMenuItem<SceneFilter> _buildFilterItem(SceneFilter filter, String label, IconData icon) {
    return PopupMenuItem(
      value: filter,
      child: Row(
        children: [
          Icon(icon, size: 20, color: _filter == filter ? NexGenPalette.cyan : null),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: _filter == filter ? NexGenPalette.cyan : null,
              fontWeight: _filter == filter ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  List<Scene> _filterScenes(List<Scene> scenes) {
    var filtered = scenes.toList();

    // Remove system presets if disabled
    if (!_showSystemPresets) {
      filtered = filtered.where((s) => s.type != SceneType.system).toList();
    }

    // Apply type filter
    switch (_filter) {
      case SceneFilter.all:
        break;
      case SceneFilter.custom:
        filtered = filtered.where((s) => s.type == SceneType.custom).toList();
        break;
      case SceneFilter.library:
        filtered = filtered.where((s) => s.type == SceneType.library).toList();
        break;
      case SceneFilter.favorites:
        filtered = filtered.where((s) => s.isFavorite).toList();
        break;
    }

    return filtered;
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Create New Scene',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _CreateOptionTile(
                icon: Icons.design_services,
                iconColor: NexGenPalette.cyan,
                title: 'Design Studio',
                subtitle: 'Create a custom design with per-LED control',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/design-studio');
                },
              ),
              _CreateOptionTile(
                icon: Icons.explore,
                iconColor: NexGenPalette.violet,
                title: 'Browse Patterns',
                subtitle: 'Find and save patterns from the library',
                onTap: () {
                  Navigator.pop(ctx);
                  // Navigate to explore tab (index 3 in bottom nav)
                  // This would need to be handled by the parent navigation
                },
              ),
              _CreateOptionTile(
                icon: Icons.camera_alt,
                iconColor: const Color(0xFFFFB74D),
                title: 'Capture Current',
                subtitle: 'Save the current lighting as a scene',
                onTap: () {
                  Navigator.pop(ctx);
                  _showCaptureDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCaptureDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Capture Scene', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Scene Name',
            labelStyle: TextStyle(color: Colors.white54),
            hintText: 'e.g., Evening Glow',
            hintStyle: TextStyle(color: Colors.white30),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final capture = ref.read(captureSnapshotProvider);
              final sceneId = await capture(name);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(sceneId != null
                        ? 'Captured "$name"'
                        : 'Failed to capture scene'),
                    backgroundColor: sceneId != null ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Capture'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyScene(BuildContext context, WidgetRef ref, Scene scene) async {
    final apply = ref.read(applySceneProvider);
    final success = await apply(scene);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Applied "${scene.name}"' : 'Failed to apply scene'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _editScene(BuildContext context, WidgetRef ref, Scene scene) {
    if (scene.type == SceneType.custom && scene.customDesign != null) {
      ref.read(currentDesignProvider.notifier).loadDesign(scene.customDesign!);
      context.push('/design-studio');
    } else if (scene.type == SceneType.system) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System presets cannot be edited')),
      );
    } else {
      // For library/snapshot scenes, could open an editor in the future
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing not available for this scene type')),
      );
    }
  }

  Future<void> _deleteScene(BuildContext context, WidgetRef ref, Scene scene) async {
    if (scene.type == SceneType.system) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System presets cannot be deleted')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete Scene?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${scene.name}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final delete = ref.read(deleteSceneProvider);
      final success = await delete(scene);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Deleted "${scene.name}"' : 'Failed to delete'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(WidgetRef ref, Scene scene) async {
    if (scene.type == SceneType.system) return; // System presets can't be favorited

    final toggle = ref.read(toggleSceneFavoriteProvider);
    await toggle(scene);
  }

  Future<void> _addToSiri(BuildContext context, WidgetRef ref, Scene scene) async {
    if (!Platform.isIOS) return;

    final presentAddToSiri = ref.read(presentAddToSiriProvider);
    final success = await presentAddToSiri(scene);

    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Add to Siri. Make sure Siri is enabled.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}

enum SceneFilter {
  all,
  custom,
  library,
  favorites,
}

class _EmptyState extends StatelessWidget {
  final SceneFilter filter;
  final VoidCallback onCreateNew;

  const _EmptyState({required this.filter, required this.onCreateNew});

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;

    switch (filter) {
      case SceneFilter.all:
        message = 'No scenes yet.\nCreate your first custom lighting scene.';
        icon = Icons.palette_outlined;
        break;
      case SceneFilter.custom:
        message = 'No custom designs yet.\nOpen Design Studio to create one.';
        icon = Icons.design_services_outlined;
        break;
      case SceneFilter.library:
        message = 'No saved patterns yet.\nBrowse the library and save your favorites.';
        icon = Icons.auto_awesome_outlined;
        break;
      case SceneFilter.favorites:
        message = 'No favorites yet.\nTap the heart on any scene to add it here.';
        icon = Icons.favorite_border;
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: NexGenPalette.cyan),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateNew,
              icon: const Icon(Icons.add),
              label: const Text('Create Scene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenesList extends StatelessWidget {
  final List<Scene> scenes;
  final Function(Scene) onApply;
  final Function(Scene) onEdit;
  final Function(Scene) onDelete;
  final Function(Scene) onToggleFavorite;
  final Function(Scene)? onAddToSiri;

  const _ScenesList({
    required this.scenes,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
    this.onAddToSiri,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: scenes.length,
      itemBuilder: (context, index) {
        final scene = scenes[index];
        return _SceneCard(
          scene: scene,
          onTap: () => onApply(scene),
          onEdit: () => onEdit(scene),
          onDelete: () => onDelete(scene),
          onToggleFavorite: () => onToggleFavorite(scene),
          onAddToSiri: onAddToSiri != null ? () => onAddToSiri!(scene) : null,
        );
      },
    );
  }
}

class _SceneCard extends StatelessWidget {
  final Scene scene;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onAddToSiri;

  const _SceneCard({
    required this.scene,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
    this.onAddToSiri,
  });

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Color preview
                  _ColorPreview(colors: scene.previewColors, type: scene.type),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                scene.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Type badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: scene.type.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(scene.type.icon, size: 12, color: scene.type.color),
                                  const SizedBox(width: 4),
                                  Text(
                                    scene.type.displayName,
                                    style: TextStyle(
                                      color: scene.type.color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (scene.description != null && scene.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              scene.description!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Quick apply button
                  IconButton(
                    onPressed: onTap,
                    icon: const Icon(Icons.play_arrow),
                    tooltip: 'Apply Scene',
                    color: NexGenPalette.cyan,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Tags
              if (scene.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: scene.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.violet.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: NexGenPalette.violet,
                        fontSize: 11,
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
              ],
              // Footer
              Row(
                children: [
                  if (scene.type != SceneType.system) ...[
                    Icon(Icons.access_time, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(scene.updatedAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Actions
                  if (scene.type != SceneType.system) ...[
                    // Add to Siri button (iOS only)
                    if (onAddToSiri != null)
                      IconButton(
                        onPressed: onAddToSiri,
                        icon: const Icon(Icons.mic, size: 18),
                        tooltip: 'Add to Siri',
                        color: Colors.white54,
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      onPressed: onToggleFavorite,
                      icon: Icon(
                        scene.isFavorite ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                      ),
                      tooltip: scene.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                      color: scene.isFavorite ? Colors.red : Colors.white54,
                      visualDensity: VisualDensity.compact,
                    ),
                    if (scene.type == SceneType.custom)
                      IconButton(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Edit',
                        color: Colors.white54,
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete',
                      color: Colors.red.withValues(alpha: 0.7),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPreview extends StatelessWidget {
  final List<List<int>> colors;
  final SceneType type;

  const _ColorPreview({required this.colors, required this.type});

  @override
  Widget build(BuildContext context) {
    // Convert RGB arrays to Colors
    final colorList = colors.isNotEmpty
        ? colors.take(4).map((c) => Color.fromARGB(255, c[0], c[1], c[2])).toList()
        : [type.color];

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: colorList.length > 1
            ? LinearGradient(
                colors: colorList,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: colorList.length == 1 ? colorList.first : null,
        boxShadow: [
          BoxShadow(
            color: colorList.first.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: type == SceneType.system
          ? Center(
              child: Icon(
                _iconForSystem(colors),
                color: Colors.white.withValues(alpha: 0.8),
                size: 24,
              ),
            )
          : null,
    );
  }

  IconData _iconForSystem(List<List<int>> colors) {
    // Check if it's the "off" preset (no colors or black)
    if (colors.isEmpty) return Icons.power_settings_new;
    final first = colors.first;
    if (first[0] < 50 && first[1] < 50 && first[2] < 50) return Icons.power_settings_new;
    // Check for warm white (warm tones)
    if (first[0] > 200 && first[1] > 150 && first[2] < 150) return Icons.wb_incandescent;
    // Default to sun for bright white
    return Icons.wb_sunny;
  }
}

class _CreateOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
}
