import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

// ---------------------------------------------------------------------------
// Private helper widgets (small utilities shared with pattern_library_pages)
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});
  @override
  Widget build(BuildContext context) => Center(child: Text(error));
}

class _CenteredText extends StatelessWidget {
  final String text;
  const _CenteredText(this.text);
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: NexGenPalette.matteBlack, width: 1)),
    );
  }
}

// ---------------------------------------------------------------------------
// ThemeSelectionScreen
// ---------------------------------------------------------------------------

/// Screen 3: Theme Selection for a Sub-Category
/// Shows the sub-category's palette as selectable swatches (future: drive effect presets)
class ThemeSelectionScreen extends ConsumerWidget {
  final String categoryId;
  final String subCategoryId;
  final String? subCategoryName;
  const ThemeSelectionScreen({super.key, required this.categoryId, required this.subCategoryId, this.subCategoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSub = ref.watch(subCategoryByIdProvider(subCategoryId));
    return asyncSub.when(
      data: (sub) {
        if (sub == null) {
          return const Scaffold(body: _CenteredText('Sub-category not found'));
        }
        final colors = sub.themeColors;
        final asyncItems = ref.watch(patternGeneratedItemsBySubCategoryProvider(sub.id));
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: GlassAppBar(
              title: Text(subCategoryName ?? sub.name),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'All'),
                  Tab(text: 'Elegant'),
                  Tab(text: 'Motion'),
                  Tab(text: 'Energy'),
                ],
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: asyncItems.when(
                data: (items) {
                  if (items.isEmpty) return const _CenteredText('No generated items');
                  List<PatternItem> filterBy(String vibe) {
                    if (vibe == 'All') return items;
                    return items.where((it) {
                      final fx = PatternRepository.effectIdFromPayload(it.wledPayload);
                      if (fx == null) return false;
                      final v = PatternRepository.vibeForFx(fx);
                      return v == vibe;
                    }).toList(growable: false);
                  }

                  final all = items;
                  final elegant = filterBy('Elegant');
                  final motion = filterBy('Motion');
                  final energy = filterBy('Energy');

                  Widget buildGrid(List<PatternItem> list) {
                    if (list.isEmpty) return const _CenteredText('No items for this vibe');
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Auto-generated patterns', style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(width: 8),
                        Wrap(spacing: 6, children: colors.take(3).map((c) => _ColorDot(color: c)).toList(growable: false)),
                      ]),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _CompactPatternItemCard(item: list[i], themeColors: colors),
                        ),
                      ),
                    ]);
                  }

                  return TabBarView(children: [
                    buildGrid(all),
                    buildGrid(elegant),
                    buildGrid(motion),
                    buildGrid(energy),
                  ]);
                },
                error: (e, st) => _ErrorState(error: '$e'),
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          ),
        );
      },
      error: (e, st) => Scaffold(appBar: const GlassAppBar(), body: _ErrorState(error: '$e')),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _PaletteTile({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: NexGenPalette.line),
        ),
      ),
    );
  }
}

/// Style variation chips for refining search results.
/// Shows different style options (classic, subtle, bold, etc.) that users can
/// tap to see variations of the same theme.
class _StyleVariationChips extends StatelessWidget {
  final ThemeStyle currentStyle;
  final ValueChanged<ThemeStyle> onStyleSelected;
  const _StyleVariationChips({required this.currentStyle, required this.onStyleSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.tune, color: NexGenPalette.cyan, size: 16),
            const SizedBox(width: 6),
            Text(
              'Style Variations',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: NexGenPalette.textMedium),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ThemeStyle.values.map((style) => _StyleChip(
            style: style,
            isSelected: style == currentStyle,
            onTap: () => onStyleSelected(style),
          )).toList(),
        ),
      ],
    );
  }
}

class _StyleChip extends StatelessWidget {
  final ThemeStyle style;
  final bool isSelected;
  final VoidCallback onTap;
  const _StyleChip({required this.style, required this.isSelected, required this.onTap});

  IconData _iconForStyle(ThemeStyle style) {
    switch (style) {
      case ThemeStyle.classic:
        return Icons.auto_awesome;
      case ThemeStyle.subtle:
        return Icons.contrast;
      case ThemeStyle.bold:
        return Icons.wb_sunny;
      case ThemeStyle.vintage:
        return Icons.filter_vintage;
      case ThemeStyle.modern:
        return Icons.architecture;
      case ThemeStyle.playful:
        return Icons.celebration;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? NexGenPalette.cyan.withValues(alpha: 0.2) : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForStyle(style),
                size: 16,
                color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              ),
              const SizedBox(width: 6),
              Text(
                style.displayName,
                style: TextStyle(
                  color: isSelected ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LIBRARY BROWSER SCREEN - Unified hierarchical navigation
// ============================================================================

/// Unified browser screen for navigating the library hierarchy.
/// Shows root categories when nodeId is null, otherwise shows children of that node.
/// Displays pattern grid for palette nodes, folder grid for intermediate nodes.
class LibraryBrowserScreen extends ConsumerStatefulWidget {
  final String? nodeId;
  final String? nodeName;

  const LibraryBrowserScreen({super.key, this.nodeId, this.nodeName});

  @override
  ConsumerState<LibraryBrowserScreen> createState() => _LibraryBrowserScreenState();
}

class _LibraryBrowserScreenState extends ConsumerState<LibraryBrowserScreen> {
  bool _isPaletteView = false;

  @override
  void dispose() {
    // Reset mood filter when leaving a palette view
    if (_isPaletteView) {
      // Use Future.microtask to avoid modifying providers during dispose
      Future.microtask(() {
        ref.read(selectedMoodFilterProvider.notifier).state = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get current node (if any) and children
    final nodeAsync = widget.nodeId != null
        ? ref.watch(libraryNodeByIdProvider(widget.nodeId!))
        : const AsyncValue<LibraryNode?>.data(null);
    final childrenAsync = ref.watch(libraryChildNodesProvider(widget.nodeId));
    final ancestorsAsync = widget.nodeId != null
        ? ref.watch(libraryAncestorsProvider(widget.nodeId!))
        : const AsyncValue<List<LibraryNode>>.data([]);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Reset mood filter when navigating back from a palette view
        if (_isPaletteView && didPop) {
          ref.read(selectedMoodFilterProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        backgroundColor: NexGenPalette.gunmetal,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App bar with back button and title
              _LibraryAppBar(
                nodeId: widget.nodeId,
                nodeName: widget.nodeName,
                nodeAsync: nodeAsync,
              ),
              // Breadcrumb navigation
              if (widget.nodeId != null)
                ancestorsAsync.when(
                  data: (ancestors) => _LibraryBreadcrumb(
                    ancestors: ancestors,
                    currentNodeName: widget.nodeName,
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              // Main content
              Expanded(
                child: childrenAsync.when(
                  data: (children) {
                    // Check if this is a palette node - show patterns instead
                    return nodeAsync.when(
                      data: (node) {
                        if (node != null && node.isPalette) {
                          // Track that we're viewing a palette
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_isPaletteView) {
                              setState(() => _isPaletteView = true);
                            }
                          });
                          // Use the new simplified effect selector
                          return ColorwayEffectSelectorPage(paletteNode: node);
                        }
                        // Show children as navigation grid
                        // For Architectural Downlighting, show Kelvin chart above the grid
                        if (widget.nodeId == LibraryCategoryIds.architectural) {
                          return Column(
                            children: [
                              const _KelvinReferenceChart(),
                              Expanded(child: _LibraryNodeGrid(children: children)),
                            ],
                          );
                        }
                        return _LibraryNodeGrid(children: children);
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, __) => _LibraryNodeGrid(children: children),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, __) => Center(
                    child: Text(
                      'Unable to load content',
                      style: TextStyle(color: NexGenPalette.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App bar for the library browser
class _LibraryAppBar extends StatelessWidget {
  final String? nodeId;
  final String? nodeName;
  final AsyncValue<LibraryNode?> nodeAsync;

  const _LibraryAppBar({
    required this.nodeId,
    required this.nodeName,
    required this.nodeAsync,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = nodeName ?? nodeAsync.whenOrNull(data: (n) => n?.name) ?? 'Design Library';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (nodeId != null)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          if (nodeId != null) const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Breadcrumb navigation showing path from root to current node
class _LibraryBreadcrumb extends StatelessWidget {
  final List<LibraryNode> ancestors;
  final String? currentNodeName;

  const _LibraryBreadcrumb({
    required this.ancestors,
    this.currentNodeName,
  });

  @override
  Widget build(BuildContext context) {
    if (ancestors.isEmpty && currentNodeName == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Home/Library root
          GestureDetector(
            onTap: () {
              // Pop all the way back to library root
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Row(
              children: [
                Icon(Icons.home, size: 16, color: NexGenPalette.cyan),
                const SizedBox(width: 4),
                Text(
                  'Library',
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Ancestor breadcrumbs
          for (final ancestor in ancestors) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: NexGenPalette.textSecondary),
            ),
            GestureDetector(
              onTap: () {
                // Navigate back to this ancestor
                final popsNeeded = ancestors.indexOf(ancestor) + 1;
                for (var i = 0; i < ancestors.length - popsNeeded + 1; i++) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                ancestor.name,
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          // Current node (not clickable)
          if (currentNodeName != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: NexGenPalette.textSecondary),
            ),
            Text(
              currentNodeName!,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kelvin color temperature reference chart for Architectural Downlighting.
/// Shows a gradient bar from 2000K (warm amber) to 6500K (cool blue-white)
/// with labeled temperature stops so users can identify their preferred white.
class _KelvinReferenceChart extends StatelessWidget {
  const _KelvinReferenceChart();

  /// Kelvin temperature -> approximate RGB using Tanner Helland algorithm.
  static Color _kelvinToColor(int kelvin) {
    final temp = kelvin / 100.0;
    double r, g, b;

    // Red
    if (temp <= 66) {
      r = 255;
    } else {
      r = 329.698727446 * pow(temp - 60, -0.1332047592);
      r = r.clamp(0, 255);
    }

    // Green
    if (temp <= 66) {
      g = 99.4708025861 * log(temp) - 161.1195681661;
      g = g.clamp(0, 255);
    } else {
      g = 288.1221695283 * pow(temp - 60, -0.0755148492);
      g = g.clamp(0, 255);
    }

    // Blue
    if (temp >= 66) {
      b = 255;
    } else if (temp <= 19) {
      b = 0;
    } else {
      b = 138.5177312231 * log(temp - 10) - 305.0447927307;
      b = b.clamp(0, 255);
    }

    return Color.fromARGB(255, r.round(), g.round(), b.round());
  }

  static const _stops = [
    (kelvin: 2000, label: '2000K', name: 'Candle'),
    (kelvin: 2700, label: '2700K', name: 'Warm'),
    (kelvin: 3000, label: '3000K', name: ''),
    (kelvin: 3500, label: '3500K', name: 'Soft'),
    (kelvin: 4000, label: '4000K', name: 'Neutral'),
    (kelvin: 4500, label: '4500K', name: ''),
    (kelvin: 5000, label: '5000K', name: 'Day'),
    (kelvin: 5500, label: '5500K', name: ''),
    (kelvin: 6500, label: '6500K', name: 'Moon'),
  ];

  @override
  Widget build(BuildContext context) {
    // Build fine-grained gradient colors across the full range
    final gradientColors = <Color>[];
    final gradientStops = <double>[];
    const minK = 2000;
    const maxK = 6500;
    for (var k = minK; k <= maxK; k += 250) {
      gradientColors.add(_kelvinToColor(k));
      gradientStops.add((k - minK) / (maxK - minK));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.thermostat, color: NexGenPalette.textSecondary, size: 14),
              const SizedBox(width: 6),
              Text(
                'Color Temperature Reference',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: NexGenPalette.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Gradient bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  stops: gradientStops,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line, width: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Labels row
          SizedBox(
            height: 32,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: _stops.map((stop) {
                    final fraction = (stop.kelvin - minK) / (maxK - minK);
                    final left = fraction * totalWidth;
                    return Positioned(
                      left: left - 18,
                      top: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stop.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (stop.name.isNotEmpty)
                            Text(
                              stop.name,
                              style: TextStyle(
                                color: NexGenPalette.textSecondary,
                                fontSize: 7,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stub widgets — these reference complex widgets that remain in
// pattern_library_pages.dart. They are defined here as minimal placeholders
// so this file compiles independently. Replace with real imports once the
// originals are refactored to be publicly accessible.
// ---------------------------------------------------------------------------

/// Minimal grid placeholder for library child nodes.
/// The full implementation lives in pattern_library_pages.dart as
/// _LibraryNodeGrid / _LibraryNodeCard.
class _LibraryNodeGrid extends StatelessWidget {
  final List<LibraryNode> children;
  const _LibraryNodeGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: Text('No items found', style: TextStyle(color: NexGenPalette.textSecondary)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final node = children[index];
        return _MinimalNodeCard(node: node);
      },
    );
  }
}

class _MinimalNodeCard extends StatelessWidget {
  final LibraryNode node;
  const _MinimalNodeCard({required this.node});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexGenPalette.gunmetal90,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LibraryBrowserScreen(nodeId: node.id, nodeName: node.name),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                node.isPalette ? Icons.palette_outlined : Icons.folder_outlined,
                color: NexGenPalette.cyan,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                node.name,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pattern item card used in ThemeSelectionScreen grid.
/// This is a simplified version; the full implementation lives in
/// pattern_library_pages.dart.
class _CompactPatternItemCard extends ConsumerWidget {
  final PatternItem item;
  final List<Color> themeColors;
  const _CompactPatternItemCard({required this.item, required this.themeColors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = themeColors.isNotEmpty ? themeColors : [Colors.white];
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors.length > 1 ? colors : [colors.first, colors.first.withValues(alpha: 0.5)]),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Center(
                child: Text(
                  item.name,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white, height: 1.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
