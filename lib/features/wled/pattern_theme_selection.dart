import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/explore_patterns/ui/explore_design_system.dart';
import 'package:go_router/go_router.dart';
// Additional imports required by the full _CompactPatternItemCard implementation
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';

// ---------------------------------------------------------------------------
// Private helper widgets
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
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ChannelSelectorBar(),
                ),
                Expanded(
                  child: Padding(
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
                                padding: EdgeInsets.only(bottom: navBarTotalHeight(context)),
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
              ],
            ),
          ),
        );
      },
      error: (e, st) => Scaffold(appBar: const GlassAppBar(), body: _ErrorState(error: '$e')),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

// ============================================================================
// LIBRARY BROWSER SCREEN
// ============================================================================

class LibraryBrowserScreen extends ConsumerStatefulWidget {
  final String? nodeId;
  final String? nodeName;
  final Color? parentAccent;
  final List<Color>? parentGradient;

  const LibraryBrowserScreen({super.key, this.nodeId, this.nodeName, this.parentAccent, this.parentGradient});

  @override
  ConsumerState<LibraryBrowserScreen> createState() => _LibraryBrowserScreenState();
}

class _LibraryBrowserScreenState extends ConsumerState<LibraryBrowserScreen> {
  bool _isPaletteView = false;

  @override
  void dispose() {
    if (_isPaletteView) {
      Future.microtask(() {
        ref.read(selectedMoodFilterProvider.notifier).state = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodeAsync = widget.nodeId != null
        ? ref.watch(libraryNodeByIdProvider(widget.nodeId!))
        : const AsyncValue<LibraryNode?>.data(null);
    final childrenAsync = ref.watch(libraryChildNodesProvider(widget.nodeId));
    final ancestorsAsync = widget.nodeId != null
        ? ref.watch(libraryAncestorsProvider(widget.nodeId!))
        : const AsyncValue<List<LibraryNode>>.data([]);

    final displayName = widget.nodeName ?? nodeAsync.whenOrNull(data: (n) => n?.name) ?? 'Design Library';
    final folderTheme = getFolderTheme(displayName);
    final gradientColors = widget.parentGradient ?? folderTheme.gradientColors;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (_isPaletteView && didPop) {
          ref.read(selectedMoodFilterProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        backgroundColor: ExploreDesignTokens.backgroundBase,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E0E1A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => context.pop(),
          ),
          title: Text(
            displayName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
            overflow: TextOverflow.ellipsis,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors.length >= 2
                      ? gradientColors
                      : [gradientColors.first, gradientColors.first.withValues(alpha: 0.4)],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            if (widget.nodeId != null)
              ancestorsAsync.when(
                data: (ancestors) {
                  final crumbs = [
                    'Library',
                    ...ancestors.map((a) => a.name),
                    if (widget.nodeName != null) widget.nodeName!,
                  ];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: BreadcrumbTrail(crumbs: crumbs),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            Expanded(
              child: childrenAsync.when(
                data: (children) {
                  return nodeAsync.when(
                    data: (node) {
                      if (node != null && node.isPalette) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_isPaletteView) {
                            setState(() => _isPaletteView = true);
                          }
                        });
                        return ColorwayEffectSelectorPage(paletteNode: node);
                      }
                      if (widget.nodeId == LibraryCategoryIds.architectural) {
                        return Column(
                          children: [
                            const _KelvinReferenceChart(),
                            Expanded(child: LibraryNodeGrid(children: children, parentAccent: widget.parentAccent, parentGradient: widget.parentGradient, folderAspectRatio: 2.2)),
                          ],
                        );
                      }
                      return LibraryNodeGrid(children: children, parentAccent: widget.parentAccent, parentGradient: widget.parentGradient);
                    },
                    loading: () => const ExploreShimmerGrid(crossAxisCount: 2, itemCount: 6),
                    error: (_, __) => LibraryNodeGrid(children: children, parentAccent: widget.parentAccent, parentGradient: widget.parentGradient),
                  );
                },
                loading: () => const ExploreShimmerGrid(crossAxisCount: 2, itemCount: 6),
                error: (err, __) => Center(
                  child: Text('Unable to load content', style: TextStyle(color: ExploreDesignTokens.textSecondary)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KelvinReferenceChart extends StatelessWidget {
  const _KelvinReferenceChart();

  static Color _kelvinToColor(int kelvin) {
    final temp = kelvin / 100.0;
    double r, g, b;
    if (temp <= 66) { r = 255; } else { r = (329.698727446 * pow(temp - 60, -0.1332047592)).clamp(0, 255); }
    if (temp <= 66) { g = (99.4708025861 * log(temp) - 161.1195681661).clamp(0, 255); } else { g = (288.1221695283 * pow(temp - 60, -0.0755148492)).clamp(0, 255); }
    if (temp >= 66) { b = 255; } else if (temp <= 19) { b = 0; } else { b = (138.5177312231 * log(temp - 10) - 305.0447927307).clamp(0, 255); }
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors, stops: gradientStops),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line, width: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
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
                          Text(stop.label, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600)),
                          if (stop.name.isNotEmpty)
                            Text(stop.name, style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 7)),
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
// _CompactPatternItemCard — full effect-aware implementation
// Previously this was a stub that only rendered a static themeColors gradient.
// Now it reads the actual WLED payload (effect ID, speed, colors) and renders
// _EffectPreviewStrip so the card accurately previews the assigned motion effect.
// ---------------------------------------------------------------------------

class _CompactPatternItemCard extends ConsumerWidget {
  final PatternItem item;
  final List<Color> themeColors;
  const _CompactPatternItemCard({required this.item, required this.themeColors});

  static String _effectDisplayName(int effectId) {
    const names = {
      0: 'Solid', 1: 'Blink', 2: 'Breathe', 3: 'Wipe', 6: 'Sweep', 10: 'Scan',
      12: 'Fade', 22: 'Running', 23: 'Chase', 37: 'Fill Noise', 43: 'Theater',
      46: 'Twinkle', 49: 'Fire', 51: 'Gradient', 52: 'Loading', 63: 'Palette',
      65: 'Colorwave', 67: 'Ripple', 73: 'Pacifica', 76: 'Fireworks', 78: 'Meteor',
      108: 'Meteor', 120: 'Sparkle',
    };
    return names[effectId] ?? 'Effect';
  }

  static double _speedFromPayload(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map) {
          final sx = first['sx'];
          if (sx is num) return sx.toDouble();
        }
      }
    } catch (e) {
      debugPrint('Error in ThemePatternCard _speedFromPayload: $e');
    }
    return 128;
  }

  static List<Color> _colorsFromPayload(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map) {
          final col = first['col'];
          if (col is List) {
            final result = <Color>[];
            for (final c in col) {
              if (c is List && c.length >= 3) {
                result.add(Color.fromARGB(
                  255,
                  (c[0] as num).toInt().clamp(0, 255),
                  (c[1] as num).toInt().clamp(0, 255),
                  (c[2] as num).toInt().clamp(0, 255),
                ));
              }
            }
            if (result.isNotEmpty) return result;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in ThemePatternCard _colorsFromPayload: $e');
    }
    return const [Colors.white];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectId = PatternRepository.effectIdFromPayload(item.wledPayload) ?? 0;
    // Use actual colors from the WLED payload — not the subcategory themeColors.
    // themeColors represents the team/theme palette but the payload already has
    // the exact colors baked in (possibly the same, possibly a subset/variation).
    final displayColors = _colorsFromPayload(item.wledPayload);
    final speed = _speedFromPayload(item.wledPayload);
    final effectName = _effectDisplayName(effectId);

    return InkWell(
      onTap: () => _handleTap(context, ref, effectId),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.matteBlack,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Effect preview strip — reflects actual effect motion + colors
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                child: _EffectPreviewStrip(
                  colors: displayColors,
                  effectId: effectId,
                  speed: speed,
                ),
              ),
            ),
            // Name + effect badge
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      displayColors.first.withValues(alpha: 0.15),
                      NexGenPalette.matteBlack,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white, height: 1.1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: displayColors.first.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        effectName,
                        style: TextStyle(fontSize: 7, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.9)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref, int effectId) async {
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      }
      return;
    }

    // Solid effect with multiple theme colors — let user pick which one
    if (effectId == 0 && themeColors.length > 1) {
      if (context.mounted) {
        final selectedColor = await _showSolidColorPicker(context, themeColors);
        if (selectedColor != null && context.mounted) {
          await _applyWithColor(context, ref, repo, selectedColor);
        }
      }
      return;
    }

    try {
      var payload = Map<String, dynamic>.from(item.wledPayload);
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
      _updateLocalState(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
    } catch (e) {
      debugPrint('Apply pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  void _updateLocalState(WidgetRef ref) {
    final bri = item.wledPayload['bri'];
    if (bri is int) ref.read(wledStateProvider.notifier).setBrightness(bri);
    final seg = item.wledPayload['seg'];
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      final s0 = seg.first as Map;
      final sx = s0['sx'];
      if (sx is int) ref.read(wledStateProvider.notifier).setSpeed(sx);
      final col = s0['col'];
      if (col is List && col.isNotEmpty && col.first is List) {
        final c = col.first as List;
        if (c.length >= 3) {
          ref.read(wledStateProvider.notifier).setColor(Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt()));
        }
      }
    }
  }

  Future<Color?> _showSolidColorPicker(BuildContext context, List<Color> colors) async {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SolidColorPickerSheet(colors: colors),
    );
  }

  Future<void> _applyWithColor(BuildContext context, WidgetRef ref, WledRepository repo, Color color) async {
    try {
      var payload = Map<String, dynamic>.from(item.wledPayload);
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final s0 = Map<String, dynamic>.from(seg.first as Map);
        s0['col'] = [rgbToRgbw(color.red, color.green, color.blue, forceZeroWhite: true)];
        payload['seg'] = [s0];
      }
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
    } catch (e) {
      debugPrint('Apply with color failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }
}

class _SolidColorPickerSheet extends StatelessWidget {
  final List<Color> colors;
  const _SolidColorPickerSheet({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.palette, color: NexGenPalette.cyan, size: 20),
            const SizedBox(width: 8),
            Text('Choose Solid Color',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NexGenPalette.textHigh, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text('Solid effect displays one color. Which should we use?',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) => _ColorPickerTile(color: color, onTap: () => Navigator.pop(context, color))).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
        ],
      ),
    );
  }
}

class _ColorPickerTile extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _ColorPickerTile({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line, width: 2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Center(child: Icon(Icons.touch_app, color: Colors.white54, size: 20)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EffectPreviewStrip — animates the card preview based on actual effect type
// ---------------------------------------------------------------------------

class _EffectPreviewStrip extends StatefulWidget {
  final List<Color> colors;
  final int effectId;
  final double speed;
  const _EffectPreviewStrip({required this.colors, required this.effectId, this.speed = 128});

  @override
  State<_EffectPreviewStrip> createState() => _EffectPreviewStripState();
}

class _EffectPreviewStripState extends State<_EffectPreviewStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final durationMs = (3000 - (widget.speed / 255) * 2500).clamp(500, 5000).round();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: durationMs));
    if (widget.effectId != 0) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _EffectPainter(colors: widget.colors, effectId: widget.effectId, progress: _controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  final List<Color> colors;
  final int effectId;
  final double progress;
  _EffectPainter({required this.colors, required this.effectId, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    const ledCount = 30;
    final ledWidth = size.width / ledCount;
    final ledHeight = size.height;

    switch (_effectType) {
      case _ET.solid:
        paint.color = colors.first;
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      case _ET.breathing:
        final v = (sin(progress * 2 * pi) + 1) / 2;
        paint.color = colors.first.withValues(alpha: 0.3 + v * 0.7);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      case _ET.wipe:
        final pos = progress * size.width;
        paint.color = colors.first;
        canvas.drawRect(Rect.fromLTWH(0, 0, pos, size.height), paint);
        paint.color = colors.length > 1 ? colors[1] : colors.first.withValues(alpha: 0.3);
        canvas.drawRect(Rect.fromLTWH(pos, 0, size.width - pos, size.height), paint);
      case _ET.scan:
        paint.color = colors.last.withValues(alpha: 0.1);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
        final bounce = (sin(progress * 2 * pi) + 1) / 2;
        final scanPos = bounce * (size.width - ledWidth * 3);
        final sw = ledWidth * 3;
        paint.shader = LinearGradient(colors: [colors.first.withValues(alpha: 0), colors.first.withValues(alpha: 0.5), colors.first, colors.first.withValues(alpha: 0.5), colors.first.withValues(alpha: 0)])
            .createShader(Rect.fromLTWH(scanPos - sw, 0, sw * 3, ledHeight));
        canvas.drawRect(Rect.fromLTWH(scanPos - sw, 0, sw * 3, ledHeight), paint);
        paint.shader = null;
      case _ET.fade:
        final n = colors.length;
        final cp = progress * n;
        final ci = cp.floor() % n;
        final ni = (ci + 1) % n;
        paint.color = Color.lerp(colors[ci], colors[ni], cp - cp.floor())!;
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      case _ET.running:
        final seg = ledCount ~/ colors.length;
        final offset = (progress * ledCount).floor();
        for (int i = 0; i < ledCount; i++) {
          final adj = (i + offset) % ledCount;
          paint.color = colors[(adj ~/ seg) % colors.length];
          canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
        }
      case _ET.theater:
        final offset = (progress * 3).floor() % 3;
        for (int i = 0; i < ledCount; i++) {
          final lit = (i + offset) % 3 == 0;
          paint.color = lit ? colors[((i + offset) ~/ 3) % colors.length] : Colors.black.withValues(alpha: 0.3);
          canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
        }
      case _ET.twinkle:
        paint.shader = LinearGradient(colors: colors).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
        paint.shader = null;
        for (int i = 0; i < 6; i++) {
          final seed = (i * 17 + 7) % ledCount;
          final br = (sin(((progress * 2 + i * 0.2) % 1.0) * 2 * pi) + 1) / 2;
          paint.color = Colors.white.withValues(alpha: br * 0.7);
          canvas.drawCircle(Offset(seed * ledWidth + ledWidth / 2, size.height / 2), ledWidth * 0.6, paint);
        }
      case _ET.gradient:
        final ext = [...colors, ...colors];
        final stops = List.generate(ext.length, (i) => ((i / (ext.length - 1)) + progress * 2) % 2 / 2)..sort();
        paint.shader = LinearGradient(colors: ext, stops: stops).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
        paint.shader = null;
      case _ET.fire:
        final fc = colors.isNotEmpty ? colors : [Colors.red, Colors.orange, Colors.yellow];
        for (int i = 0; i < ledCount; i++) {
          final fl = (sin(progress * 10 + i * 0.5) + sin(progress * 7 + i * 0.3)) / 4 + 0.5;
          paint.color = fc[((fl * fc.length).floor()).clamp(0, fc.length - 1)].withValues(alpha: (0.5 + fl * 0.5).clamp(0, 1));
          canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
        }
      case _ET.meteor:
        paint.color = Colors.black.withValues(alpha: 0.8);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
        final mp = (progress * (ledCount + 10)).floor() - 5;
        for (int i = 0; i < 8; i++) {
          final pos = mp - i;
          if (pos >= 0 && pos < ledCount) {
            paint.color = colors[i % colors.length].withValues(alpha: 1.0 - i / 8);
            canvas.drawRect(Rect.fromLTWH(pos * ledWidth, 0, ledWidth + 1, ledHeight), paint);
          }
        }
      case _ET.sparkle:
        paint.color = colors.last.withValues(alpha: 0.15);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
        for (int i = 0; i < 8; i++) {
          final seed = (progress * 1000 + i * 137).floor() % ledCount;
          final fp = (progress * 3 + i * 0.3) % 1.0;
          final op = (fp < 0.5 ? fp * 2 : (1 - fp) * 2).clamp(0.0, 1.0);
          paint.color = colors[i % colors.length].withValues(alpha: op);
          canvas.drawCircle(Offset(seed * ledWidth + ledWidth / 2, size.height / 2), ledWidth * 0.8, paint);
        }
      case _ET.wave:
        for (int i = 0; i < ledCount; i++) {
          final br = (sin(progress * 2 * pi + i * 0.3) + 1) / 2;
          paint.color = colors[(i * colors.length / ledCount).floor() % colors.length].withValues(alpha: 0.3 + br * 0.7);
          canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
        }
      case _ET.chase:
        final cp = (progress * ledCount).floor();
        for (int i = 0; i < ledCount; i++) {
          final d = (i - cp + ledCount) % ledCount;
          paint.color = d < 5
              ? colors[d % colors.length].withValues(alpha: 1.0 - d / 5)
              : colors.last.withValues(alpha: 0.1);
          canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
        }
    }
  }

  _ET get _effectType {
    switch (effectId) {
      case 0: return _ET.solid;
      case 1: case 2: return _ET.breathing;
      case 3: case 4: return _ET.wipe;
      case 6: case 10: case 11: case 13: case 14: return _ET.scan;
      case 12: case 18: return _ET.fade;
      case 22: case 23: case 24: case 25: case 41: case 42: return _ET.running;
      case 43: case 44: return _ET.theater;
      case 37: case 46: case 47: return _ET.twinkle;
      case 51: case 63: case 65: return _ET.gradient;
      case 49: case 54: case 74: case 75: return _ET.fire;
      case 78: case 108: case 109: return _ET.meteor;
      case 52: case 67: case 70: case 73: return _ET.wave;
      case 76: case 77: case 120: case 121: return _ET.sparkle;
      default: return _ET.chase;
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) =>
      old.progress != progress || old.effectId != effectId || old.colors != colors;
}

enum _ET { solid, breathing, chase, wipe, sparkle, scan, fade, gradient, theater, running, twinkle, fire, meteor, wave }