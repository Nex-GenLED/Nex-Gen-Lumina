import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart'
    show WledEffectsCatalog;
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
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/design/apply_saved_design.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';

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

  /// When non-null, the picker is operating in Game Day mode. Tapping
  /// a design will both apply it via WLED and persist it to the
  /// GameDayAutopilotConfig for [teamSlug] via the saveDesign method
  /// on gameDayAutopilotNotifierProvider. When null, the picker is
  /// operating as a general library browser (Explore mount) and design
  /// taps only apply to lights without persisting to any Game Day
  /// config.
  final String? teamSlug;

  const LibraryBrowserScreen({super.key, this.nodeId, this.nodeName, this.parentAccent, this.parentGradient, this.teamSlug});

  @override
  ConsumerState<LibraryBrowserScreen> createState() => _LibraryBrowserScreenState();
}

class _LibraryBrowserScreenState extends ConsumerState<LibraryBrowserScreen> {
  bool _isPaletteView = false;

  /// One-shot guard so the saved-design intercept fires its post-frame apply
  /// + pop exactly once per mount. Without this, rebuilds during the async
  /// apply would re-schedule the callback and stack snackbars / double-pop.
  bool _savedDesignApplyKicked = false;

  @override
  void dispose() {
    if (_isPaletteView) {
      // Reset mood filter when leaving a palette view. The microtask
      // defers the state mutation past dispose() to avoid modifying
      // providers during the dispose tree (downstream rebuilds mid-
      // teardown). But the microtask body must NOT touch `ref` — by the
      // time it runs the widget is gone and `ref` is dead, throwing
      // "Cannot use ref after the widget was disposed" (StateError —
      // observed as #84 save-design crash, /debug_errors/ doc
      // NxZSc4Xlo5iAalrPYMuf). Capture the notifier here (while `ref`
      // is valid); the notifier itself is owned by Riverpod's
      // ProviderContainer, independent of this widget's lifecycle, so
      // mutating it from the microtask is safe.
      final notifier = ref.read(selectedMoodFilterProvider.notifier);
      Future.microtask(() {
        notifier.state = null;
      });
    }
    super.dispose();
  }

  /// Helper invoked from the saved-design intercept's post-frame callback.
  /// Resolves the saved design from the designs stream, runs the canonical
  /// apply, and pops back to the My Designs grid. Pops even on resolve
  /// failure so the user isn't stranded on the spinner screen.
  Future<void> _applySavedDesignAndPop(String? designId) async {
    if (!mounted) return;
    if (designId == null || designId.isEmpty) {
      if (mounted && context.canPop()) context.pop();
      return;
    }
    final designs = ref.read(designsStreamProvider).valueOrNull
        ?? const <CustomDesign>[];
    CustomDesign? match;
    for (final d in designs) {
      if (d.id == designId) {
        match = d;
        break;
      }
    }
    if (match == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Design not found')),
        );
        if (context.canPop()) context.pop();
      }
      return;
    }
    await applySavedDesign(context, ref, match);
    if (mounted && context.canPop()) context.pop();
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
                      // Saved-design intercept (#62): when the resolved
                      // node carries the `isSavedDesign` metadata flag, do
                      // NOT route through ColorwayEffectSelectorPage —
                      // saved designs are already fully-configured payloads
                      // and don't need a palette/effect tuner. Apply the
                      // design directly via the canonical 6-step routine,
                      // then pop back to the My Designs grid.
                      if (node != null &&
                          node.metadata?['isSavedDesign'] == true) {
                        if (!_savedDesignApplyKicked) {
                          _savedDesignApplyKicked = true;
                          final designId =
                              node.metadata?['sourceDesignId'] as String?;
                          WidgetsBinding.instance.addPostFrameCallback((_) async {
                            await _applySavedDesignAndPop(designId);
                          });
                        }
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (node != null && node.isPalette) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_isPaletteView) {
                            setState(() => _isPaletteView = true);
                          }
                        });
                        return ColorwayEffectSelectorPage(
                          paletteNode: node,
                          teamSlug: widget.teamSlug,
                        );
                      }
                      if (widget.nodeId == LibraryCategoryIds.architectural) {
                        return Column(
                          children: [
                            const _KelvinReferenceChart(),
                            Expanded(child: LibraryNodeGrid(children: children, parentAccent: widget.parentAccent, parentGradient: widget.parentGradient, folderAspectRatio: 2.2, teamSlug: widget.teamSlug)),
                          ],
                        );
                      }
                      return LibraryNodeGrid(
                        children: children,
                        parentAccent: widget.parentAccent,
                        parentGradient: widget.parentGradient,
                        teamSlug: widget.teamSlug,
                        // #85 companion: meaningful empty-state when the My
                        // Designs surface is reached but no designs exist yet.
                        // The surface is always rendered (no longer gated on
                        // designs.isNotEmpty) so the user sees the category
                        // and the next-step guidance, not a missing folder.
                        emptyMessage: widget.nodeId == kMyDesignsCategoryId
                            ? 'No saved designs yet.\n\nFrom the dashboard, '
                                'tap Now Playing → "Save Custom" or use '
                                '"Save As Custom Pattern" on the adjustment '
                                'panel to save a design.'
                            : null,
                      );
                    },
                    loading: () => const ExploreShimmerGrid(crossAxisCount: 2, itemCount: 6),
                    error: (_, __) => LibraryNodeGrid(children: children, parentAccent: widget.parentAccent, parentGradient: widget.parentGradient, teamSlug: widget.teamSlug),
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
  /// Defensive Game Day plumbing. Currently unreachable in Game Day —
  /// _CompactPatternItemCard is private and only constructed by
  /// ThemeSelectionScreen, which is itself Explore-only. The parameter
  /// is kept in place so if a future Game Day flow routes through this
  /// card (e.g. a team-themed sub-category surface), saveDesign already
  /// fires from _handleTap / _applyWithColor without further changes.
  final String? teamSlug;
  // ignore: unused_element_parameter
  const _CompactPatternItemCard({required this.item, required this.themeColors, this.teamSlug});

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
      if (channels.isEmpty) {
        debugPrint('PatternThemeSelection apply: skip (U1 gate)');
        return;
      }
      payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      // applyJson returns false (does NOT throw) on a device-write failure.
      // Gate EVERYTHING downstream on it — label, local state, AND the Game
      // Day persist — so we never persist/label a design the lights aren't
      // actually showing (Audit-2 S9, the worst case: persist-on-failure).
      final success = await repo.applyJson(payload);
      if (!success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to apply pattern')),
          );
        }
        return;
      }
      ref.read(activePresetLabelProvider.notifier).setLabelWithFingerprint(item.name, ref.read(wledStateProvider));
      _updateLocalState(ref);

      // Game Day persistence — when teamSlug is set, this picker is
      // operating as a Game Day design picker, so persist the choice
      // to the team's GameDayAutopilotConfig via the existing
      // saveDesign provider method. The Firestore write triggers a
      // stream emission on gameDayAutopilotConfigsProvider which
      // rebuilds gameDayTeamsProvider and refreshes the Game Day card.
      if (teamSlug != null) {
        try {
          final seg = (payload['seg'] is List && (payload['seg'] as List).isNotEmpty)
              ? (payload['seg'] as List).first as Map
              : <String, dynamic>{};
          final effectId = (seg['fx'] as num?)?.toInt() ?? 0;
          final speed = (seg['sx'] as num?)?.toInt() ?? 128;
          final intensity = (seg['ix'] as num?)?.toInt() ?? 128;
          final brightness = (payload['bri'] as num?)?.toInt() ?? 200;

          await ref
              .read(gameDayAutopilotNotifierProvider.notifier)
              .saveDesign(
                teamSlug: teamSlug!,
                designName: item.name,
                wledPayload: payload,
                effectId: effectId,
                speed: speed,
                intensity: intensity,
                brightness: brightness,
              );
        } catch (e, st) {
          debugPrint('[GameDayPicker] saveDesign failed: $e\n$st');
          // Non-fatal — the lights are already showing the design.
          // The card label just won't refresh until next pick.
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
      maybeShowManualApplyOffWarning(ref);
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
      if (channels.isEmpty) {
        debugPrint('PatternThemeSelection color apply: skip (U1 gate)');
        return;
      }
      payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      // Gate label AND Game Day persist on the write result — don't persist a
      // design the device rejected (Audit-2 S9, solid-color variant).
      final success = await repo.applyJson(payload);
      if (!success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to apply pattern')),
          );
        }
        return;
      }
      ref.read(activePresetLabelProvider.notifier).setLabelWithFingerprint(item.name, ref.read(wledStateProvider));

      // Game Day persistence — see _handleTap for full rationale.
      if (teamSlug != null) {
        try {
          final segPersist = (payload['seg'] is List && (payload['seg'] as List).isNotEmpty)
              ? (payload['seg'] as List).first as Map
              : <String, dynamic>{};
          final effectId = (segPersist['fx'] as num?)?.toInt() ?? 0;
          final speed = (segPersist['sx'] as num?)?.toInt() ?? 128;
          final intensity = (segPersist['ix'] as num?)?.toInt() ?? 128;
          final brightness = (payload['bri'] as num?)?.toInt() ?? 200;

          await ref
              .read(gameDayAutopilotNotifierProvider.notifier)
              .saveDesign(
                teamSlug: teamSlug!,
                designName: item.name,
                wledPayload: payload,
                effectId: effectId,
                speed: speed,
                intensity: intensity,
                brightness: brightness,
              );
        } catch (e, st) {
          debugPrint('[GameDayPicker] saveDesign failed (with color): $e\n$st');
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
      }
      maybeShowManualApplyOffWarning(ref);
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
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + navBarTotalHeight(context)),
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

  // Render category derived from the single authoritative effect-id → category
  // map ([WledEffectsCatalog]) shared by every preview surface (#6). The old
  // hardcoded id switch disagreed with canonical WLED — e.g. it mislabeled id
  // 54 ("Chase 3") as fire and id 37 ("Chase 2") as twinkle — so the same
  // effect previewed differently here than on the roofline / tile.
  _ET get _effectType {
    final effect = WledEffectsCatalog.getById(effectId);
    if (effect == null) return _ET.chase;
    switch (effect.category) {
      case 'Basic':
        if (effectId == 2 ||
            effectId == 56 ||
            effectId == 86 ||
            effectId == 100) {
          return _ET.breathing;
        }
        if (effectId == 12 || effectId == 18) return _ET.fade;
        return _ET.solid;
      case 'Wipe':
        return _ET.wipe;
      case 'Chase':
        return _ET.chase;
      case 'Meteor':
        return _ET.meteor;
      case 'Scanner':
        return _ET.scan;
      case 'Sparkle':
        return _ET.sparkle;
      case 'Holiday':
        return _ET.twinkle;
      case 'Fire':
        return _ET.fire;
      case 'Fireworks':
        return _ET.sparkle;
      case 'Ripple':
      case 'Ambient':
      case 'Noise':
        return _ET.wave;
      case 'Rainbow':
        return _ET.gradient;
      case 'Strobe':
        return _ET.breathing;
      case 'Game':
        return _ET.running;
      case '2D':
      case 'Audio':
      default:
        return _ET.chase;
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) =>
      old.progress != progress || old.effectId != effectId || old.colors != colors;
}

enum _ET { solid, breathing, chase, wipe, sparkle, scan, fade, gradient, theater, running, twinkle, fire, meteor, wave }