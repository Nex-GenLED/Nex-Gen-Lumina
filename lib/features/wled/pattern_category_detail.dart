import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart' show kEffectNames;
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/models/smart_pattern.dart';
import 'package:nexgen_command/features/patterns/pattern_generator_service.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/widgets/color_behavior_badge.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart' show LiveGradientStrip;

/// Netflix-style horizontal row of gradient cards
class PatternCategoryRow extends ConsumerWidget {
  final String title;
  final List<GradientPattern> patterns;
  final String query;
  final bool isFeatured;
  const PatternCategoryRow({super.key, required this.title, required this.patterns, this.query = '', this.isFeatured = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? patterns
        : patterns.where((p) {
            final name = p.name.toLowerCase();
            if (q.contains('spooky')) return name.contains('halloween');
            if (q.contains('game')) return name.contains('chiefs') || name.contains('titans') || name.contains('royals');
            if (q.contains('holiday') || q.contains('christmas') || q.contains('xmas')) return name.contains('christmas') || name.contains('july');
            if (q.contains('elegant') || q.contains('architect')) return name.contains('white') || name.contains('gold');
            return name.contains(q);
          }).toList(growable: false);

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, i) => _GradientPatternCard(data: filtered[i], isFeatured: isFeatured),
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemCount: filtered.length,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    ]);
  }
}

class _GradientPatternCard extends ConsumerWidget {
  final GradientPattern data;
  final bool isFeatured;
  const _GradientPatternCard({required this.data, this.isFeatured = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final br = BorderRadius.circular(16);
    return Container(
      decoration: isFeatured
          ? BoxDecoration(
              borderRadius: br,
              boxShadow: [
                BoxShadow(color: NexGenPalette.gold.withValues(alpha: 0.28), blurRadius: 12, spreadRadius: 0.5, offset: const Offset(0, 2)),
              ],
            )
          : null,
      child: InkWell(
      onTap: () async {
        // Check for active neighborhood sync before changing lights
        final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
        if (!shouldProceed) return;

        final repo = ref.read(wledRepositoryProvider);
        if (repo == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
          }
          return;
        }
        try {
          // Use the pattern's toWledPayload() method for proper effect/speed/intensity
          await repo.applyJson(data.toWledPayload());
          // Update the active preset label
          ref.read(activePresetLabelProvider.notifier).state = data.name;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${data.name} applied!')));
          }
        } catch (e) {
          debugPrint('Apply gradient pattern failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
          }
        }
        },
        child: ClipRRect(
          borderRadius: br,
          child: SizedBox(
            width: 140,
            height: 140,
            child: Stack(children: [
              // Animated flowing gradient background (speed based on pattern)
              Positioned.fill(child: LiveGradientStrip(colors: data.colors, speed: data.isStatic ? 0 : data.speed.toDouble())),
              // Overlay for readability
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                ),
              ),
              // Border overlay (featured -> gold, otherwise standard line)
              if (!isFeatured)
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: NexGenPalette.line))))
              else
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: NexGenPalette.gold, width: 1.6)))),
              // Effect badge with color behavior indicator (top-left)
              Positioned(
                left: 8,
                top: 8,
                child: EffectWithColorBehaviorBadge(
                  effectId: data.effectId,
                  effectName: data.effectName,
                  isStatic: data.isStatic,
                ),
              ),
              // Play icon bottom-right
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Colors.black, size: 18),
                ),
              ),
              // Name and subtitle bottom-left
              Positioned(
                left: 8,
                right: 40,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.name,
                      style: Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.subtitle != null)
                      Text(
                        data.subtitle!,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white70, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              )
            ]),
          ),
        ),
      ),
    );
  }
}

/// Vertical list result item used by the simulated AI search results
class _GradientResultTile extends ConsumerWidget {
  final GradientPattern data;
  const _GradientResultTile({required this.data});

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      }
      return;
    }
    try {
      // Use the pattern's toWledPayload() method for proper effect/speed/intensity
      final success = await repo.applyJson(data.toWledPayload());

      if (!success) {
        throw Exception('Device did not accept command');
      }

      // Update the active preset label so home screen reflects the change
      ref.read(activePresetLabelProvider.notifier).state = data.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${data.name}')));
      }
    } catch (e) {
      debugPrint('Apply result pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _apply(context, ref),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(children: [
          // Gradient preview
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: data.colors),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(data.name, style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => _apply(context, ref),
            icon: const Icon(Icons.bolt, color: Colors.black),
            label: const Text('Apply'),
          )
        ]),
      ),
    );
  }
}

/// Rich, expandable control card for a SmartPattern
class PatternControlCard extends ConsumerStatefulWidget {
  final SmartPattern pattern;
  const PatternControlCard({super.key, required this.pattern});

  @override
  ConsumerState<PatternControlCard> createState() => _PatternControlCardState();
}

class _PatternControlCardState extends ConsumerState<PatternControlCard> with TickerProviderStateMixin {
  late SmartPattern _current;
  bool _expanded = false;
  Timer? _debounce;
  Timer? _layoutDebounce;

  @override
  void initState() {
    super.initState();
    _current = widget.pattern;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _layoutDebounce?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _payloadFromCurrent({bool ensureOn = true}) {
    final map = _current.toJson();
    if (ensureOn) map['on'] = true;
    return map;
  }

  Future<void> _applyNow({bool toast = false}) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      return;
    }
    try {
      await repo.applyJson(_payloadFromCurrent());
      // Update the active preset label to show this pattern name
      ref.read(activePresetLabelProvider.notifier).state = _current.name;
      if (toast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing: ${_current.name}')));
      }
    } catch (e) {
      debugPrint('Pattern apply failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  void _scheduleDebouncedApply() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _applyNow());
  }

  void _scheduleDebouncedLayoutApply() {
    _layoutDebounce?.cancel();
    _layoutDebounce = Timer(const Duration(milliseconds: 180), () async {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;
      try {
        await repo.applyJson({
          'seg': [
            {
              'grp': _current.grouping,
              'spc': _current.spacing,
            }
          ]
        });
      } catch (e) {
        debugPrint('Apply grp/spc failed: $e');
      }
    });
  }

  String _effectNameFromId(int id) {
    try {
      final m = PatternGenerator.wledEffects.firstWhere((e) => e['id'] == id);
      return (m['name'] as String?) ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectName = _effectNameFromId(_current.effectId);
    final isStatic = _current.effectId == 0 || effectName.toLowerCase().contains('static') || effectName.toLowerCase().contains('solid');
    final badgeText = isStatic ? 'Static' : 'Motion: $effectName';
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Preview swatch
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _current.colors
                        .take(3)
                        .map((rgb) => Color.fromARGB(255, rgb[0].clamp(0, 255), rgb[1].clamp(0, 255), rgb[2].clamp(0, 255)))
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_current.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                _EffectBadge(text: badgeText, effectId: _current.effectId),
              ]),
            ),
            IconButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _applyNow(toast: true),
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text('Turn On'),
            ),
          ]),
          if (_expanded) ...[
            const SizedBox(height: 12),
            // Speed slider
            Row(children: [
              const Icon(Icons.speed, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.speed.toDouble(),
                  min: 0,
                  max: 255,
                  onChanged: (v) {
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: v.round().clamp(0, 255),
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: _current.grouping,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.speed}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            // Effect Strength slider (formerly Intensity)
            Row(children: [
              Tooltip(
                message: 'Effect Strength',
                child: const Icon(Icons.tune, color: NexGenPalette.cyan),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.intensity.toDouble(),
                  min: 0,
                  max: 255,
                  onChanged: (v) {
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: v.round().clamp(0, 255),
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: _current.grouping,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.intensity}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            // Direction toggle
            Row(children: [
              const Icon(Icons.swap_horiz, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Left→Right')),
                    ButtonSegment(value: true, label: Text('Right→Left')),
                  ],
                  selected: {_current.reverse},
                  onSelectionChanged: (s) {
                    final rev = s.isNotEmpty ? s.first : false;
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: rev,
                          grouping: _current.grouping,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Pixel Layout section
            Row(children: [
              const Icon(Icons.grid_view, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            // Bulb Grouping slider (gp)
            Row(children: [
              const Icon(Icons.blur_on, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.grouping.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '${_current.grouping}',
                  onChanged: (v) {
                    final g = v.round().clamp(1, 10);
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: g,
                          spacing: _current.spacing,
                        ));
                    _scheduleDebouncedLayoutApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.grouping}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            // Spacing/Gaps slider (sp)
            Row(children: [
              const Icon(Icons.space_bar, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.spacing.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '${_current.spacing}',
                  onChanged: (v) {
                    final s = v.round().clamp(0, 10);
                    setState(() => _current = SmartPattern(
                          id: _current.id,
                          name: _current.name,
                          colors: _current.colors,
                          effectId: _current.effectId,
                          speed: _current.speed,
                          intensity: _current.intensity,
                          paletteId: _current.paletteId,
                          reverse: _current.reverse,
                          grouping: _current.grouping,
                          spacing: s,
                        ));
                    _scheduleDebouncedLayoutApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.spacing}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 10),
            // Color Sequence Builder
            Row(children: [
              const Icon(Icons.palette, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text('Color Sequence', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              // Deduplicate base colors to present a clean picker (team colors only)
              final seen = <String>{};
              final baseColors = <List<int>>[];
              for (final rgb in _current.colors) {
                if (rgb.length < 3) continue;
                final key = '${rgb[0]}-${rgb[1]}-${rgb[2]}';
                if (seen.add(key)) baseColors.add([rgb[0], rgb[1], rgb[2]]);
              }
              final initial = _current.colors.map((c) => [c[0], c[1], c[2]]).toList(growable: false);
              return ColorSequenceBuilder(
                baseColors: baseColors.isNotEmpty ? baseColors : initial,
                initialSequence: initial,
                onChanged: (seq) async {
                  final repo = ref.read(wledRepositoryProvider);
                  if (repo == null) return;
                  try {
                    await repo.applyJson({
                      'seg': [
                        {
                          'pal': seq,
                        }
                      ]
                    });
                  } catch (e) {
                    debugPrint('Apply custom palette failed: $e');
                  }
                },
              );
            }),
            const SizedBox(height: 12),
            // Footer actions
            Row(children: [
              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to Favorites')));
                },
                icon: const Icon(Icons.favorite_border, color: NexGenPalette.cyan),
                label: const Text('Save to Favorites'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  final savePattern = ref.read(savePatternAsSceneProvider);
                  final result = await savePattern(_current);
                  if (mounted) {
                    if (result != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${_current.name} saved to My Scenes'),
                          action: SnackBarAction(
                            label: 'View',
                            onPressed: () => context.push('/my-scenes'),
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to save. Please sign in.')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.save_alt, color: NexGenPalette.cyan),
                label: const Text('Save to My Scenes'),
              ),
            ]),
          ]
        ]),
      ),
    );
  }
}

class _EffectBadge extends StatelessWidget {
  final String text;
  final int? effectId;
  const _EffectBadge({required this.text, this.effectId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effect = effectId != null ? WledEffectsCatalog.getById(effectId!) : null;
    final behavior = effect?.colorBehavior;
    final behaviorColor = behavior != null ? _colorForBehavior(behavior) : NexGenPalette.cyan;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Effect name badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome_motion, size: 14, color: NexGenPalette.cyan),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
        // Color behavior badge (if effect ID provided)
        if (behavior != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: behavior.description,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: behaviorColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: behaviorColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_iconForBehavior(behavior), size: 12, color: behaviorColor),
                const SizedBox(width: 4),
                Text(
                  behavior.shortName,
                  style: TextStyle(color: behaviorColor, fontSize: 10, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return Icons.palette_outlined;
      case ColorBehavior.blendsSelectedColors:
        return Icons.gradient;
      case ColorBehavior.generatesOwnColors:
        return Icons.auto_awesome;
      case ColorBehavior.usesPalette:
        return Icons.color_lens_outlined;
    }
  }

  Color _colorForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return NexGenPalette.cyan;
      case ColorBehavior.blendsSelectedColors:
        return const Color(0xFF64B5F6);
      case ColorBehavior.generatesOwnColors:
        return const Color(0xFFFFB74D);
      case ColorBehavior.usesPalette:
        return const Color(0xFFBA68C8);
    }
  }
}

class _CategoryCard extends StatelessWidget {
  final PatternCategory category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/explore/${category.id}', extra: category),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(image: NetworkImage(category.imageUrl), fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NexGenPalette.matteBlack.withValues(alpha: 0.1),
                    NexGenPalette.matteBlack.withValues(alpha: 0.6),
                  ],
                ),
                border: Border.all(color: NexGenPalette.line),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Detail screen for a single Pattern Category now shows Sub-Category folders
class CategoryDetailScreen extends ConsumerWidget {
  final String categoryId;
  final String? categoryName;
  const CategoryDetailScreen({super.key, required this.categoryId, this.categoryName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSubs = ref.watch(patternSubCategoriesByCategoryProvider(categoryId));
    final pinnedIds = ref.watch(pinnedCategoryIdsProvider);
    final isPinned = pinnedIds.contains(categoryId);
    final title = categoryName ?? 'Explore';
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: Icon(
              isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: isPinned ? NexGenPalette.cyan : Colors.white,
            ),
            tooltip: isPinned ? 'Unpin from Explore' : 'Pin to Explore',
            onPressed: () => _togglePin(context, ref, isPinned),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncSubs.when(
            data: (subs) {
              if (subs.isEmpty) return const _CenteredText('No sub-categories yet');
              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                ),
                itemCount: subs.length,
                itemBuilder: (_, i) => _SubCategoryCard(categoryId: categoryId, sub: subs[i]),
              );
            },
            error: (e, st) => _ErrorState(error: '$e'),
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    );
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref, bool isPinned) async {
    final notifier = ref.read(pinnedCategoriesNotifierProvider.notifier);
    final success = isPinned
        ? await notifier.unpinCategory(categoryId)
        : await notifier.pinCategory(categoryId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isPinned ? 'Folder unpinned from Explore' : 'Folder pinned to Explore')
                : 'Failed to update pin status',
          ),
        ),
      );
    }
  }
}

class _SubCategoryCard extends StatelessWidget {
  final String categoryId;
  final SubCategory sub;
  const _SubCategoryCard({required this.categoryId, required this.sub});

  /// Returns a hero icon for each sub-category type.
  IconData _heroIconForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return Icons.park;
      case 'sub_halloween':
        return Icons.pest_control;
      case 'sub_july4':
        return Icons.celebration;
      case 'sub_easter':
        return Icons.egg;
      case 'sub_valentines':
        return Icons.favorite;
      case 'sub_st_patricks':
        return Icons.local_florist;
      // Sports
      case 'sub_kc':
        return Icons.sports_football;
      case 'sub_seattle':
        return Icons.sports_football;
      case 'sub_rb_generic':
      case 'sub_gy_generic':
      case 'sub_ob_generic':
        return Icons.emoji_events;
      // Seasonal
      case 'sub_spring':
        return Icons.local_florist;
      case 'sub_summer':
        return Icons.wb_sunny;
      case 'sub_autumn':
        return Icons.park;
      case 'sub_winter':
        return Icons.ac_unit;
      // Architectural
      case 'sub_warm_whites':
        return Icons.wb_incandescent;
      case 'sub_cool_whites':
        return Icons.light_mode;
      case 'sub_gold_accents':
        return Icons.auto_awesome;
      case 'sub_security_floods':
        return Icons.flashlight_on;
      // Party
      case 'sub_birthday':
        return Icons.cake;
      case 'sub_elegant_dinner':
        return Icons.restaurant;
      case 'sub_rave':
        return Icons.speaker;
      case 'sub_baby_shower':
        return Icons.child_friendly;
      default:
        return Icons.palette;
    }
  }

  /// Handpicked gradient pairs for each subcategory — curated for card aesthetics.
  List<Color> _gradientForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return const [Color(0xFF2E7D32), Color(0xFFC62828)]; // Deep green → deep red
      case 'sub_halloween':
        return const [Color(0xFFFF6D00), Color(0xFF6A1B9A)]; // Vivid orange → purple
      case 'sub_july4':
        return const [Color(0xFFEF5350), Color(0xFF1565C0)]; // Red → blue
      case 'sub_easter':
        return const [Color(0xFFF8BBD0), Color(0xFFB39DDB)]; // Soft pink → lavender
      case 'sub_valentines':
        return const [Color(0xFFE91E63), Color(0xFFAD1457)]; // Hot pink → deep rose
      case 'sub_st_patricks':
        return const [Color(0xFF43A047), Color(0xFF00C853)]; // Forest green → bright green
      // Sports
      case 'sub_kc':
        return const [Color(0xFFD32F2F), Color(0xFFFFB300)]; // Red → gold
      case 'sub_seattle':
        return const [Color(0xFF1B5E20), Color(0xFF1565C0)]; // Green → blue
      case 'sub_rb_generic':
        return const [Color(0xFFD32F2F), Color(0xFF1565C0)]; // Red → blue
      case 'sub_gy_generic':
        return const [Color(0xFF2E7D32), Color(0xFFF9A825)]; // Green → yellow
      case 'sub_ob_generic':
        return const [Color(0xFFEF6C00), Color(0xFF1565C0)]; // Orange → blue
      // Seasonal
      case 'sub_spring':
        return const [Color(0xFF81C784), Color(0xFFF48FB1)]; // Fresh green → pink
      case 'sub_summer':
        return const [Color(0xFFFFEE58), Color(0xFF29B6F6)]; // Sunny yellow → sky blue
      case 'sub_autumn':
        return const [Color(0xFFFF8F00), Color(0xFF6D4C41)]; // Amber → brown
      case 'sub_winter':
        return const [Color(0xFF81D4FA), Color(0xFF7E57C2)]; // Icy blue → purple
      // Architectural
      case 'sub_warm_whites':
        return const [Color(0xFFFFB74D), Color(0xFFFF8A65)]; // Warm amber → peach
      case 'sub_cool_whites':
        return const [Color(0xFF90A4AE), Color(0xFFE0E0E0)]; // Steel → silver
      case 'sub_gold_accents':
        return const [Color(0xFFFFD54F), Color(0xFFFFA000)]; // Light gold → deep gold
      case 'sub_security_floods':
        return const [Color(0xFFE0E0E0), Color(0xFF4FC3F7)]; // White → alert blue
      // Party
      case 'sub_birthday':
        return const [Color(0xFF00E5FF), Color(0xFFFF4081)]; // Cyan → pink
      case 'sub_elegant_dinner':
        return const [Color(0xFFFFB74D), Color(0xFF5D4037)]; // Amber → espresso
      case 'sub_rave':
        return const [Color(0xFFAA00FF), Color(0xFF00E5FF)]; // Electric purple → cyan
      case 'sub_baby_shower':
        return const [Color(0xFF80DEEA), Color(0xFFF8BBD0)]; // Baby blue → baby pink
      default:
        return [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.5)];
    }
  }

  /// Handpicked accent color for each subcategory.
  Color _accentForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return const Color(0xFF4CAF50); // Christmas green
      case 'sub_halloween':
        return const Color(0xFFFF6D00); // Pumpkin orange
      case 'sub_july4':
        return const Color(0xFFEF5350); // Patriot red
      case 'sub_easter':
        return const Color(0xFFF8BBD0); // Pastel pink
      case 'sub_valentines':
        return const Color(0xFFE91E63); // Hot pink
      case 'sub_st_patricks':
        return const Color(0xFF00C853); // Bright green
      // Sports
      case 'sub_kc':
        return const Color(0xFFD32F2F); // KC red
      case 'sub_seattle':
        return const Color(0xFF43A047); // Seattle green
      case 'sub_rb_generic':
        return const Color(0xFFEF5350); // Red
      case 'sub_gy_generic':
        return const Color(0xFF66BB6A); // Green
      case 'sub_ob_generic':
        return const Color(0xFFEF6C00); // Orange
      // Seasonal
      case 'sub_spring':
        return const Color(0xFFF48FB1); // Spring pink
      case 'sub_summer':
        return const Color(0xFFFFEE58); // Sunny yellow
      case 'sub_autumn':
        return const Color(0xFFFF8F00); // Autumn amber
      case 'sub_winter':
        return const Color(0xFF81D4FA); // Icy blue
      // Architectural
      case 'sub_warm_whites':
        return const Color(0xFFFFB74D); // Warm amber
      case 'sub_cool_whites':
        return const Color(0xFF90A4AE); // Cool steel
      case 'sub_gold_accents':
        return const Color(0xFFFFD54F); // Gold
      case 'sub_security_floods':
        return const Color(0xFF4FC3F7); // Alert blue
      // Party
      case 'sub_birthday':
        return const Color(0xFF00E5FF); // Electric cyan
      case 'sub_elegant_dinner':
        return const Color(0xFFFFB74D); // Warm amber
      case 'sub_rave':
        return const Color(0xFFAA00FF); // Electric purple
      case 'sub_baby_shower':
        return const Color(0xFF80DEEA); // Baby blue
      default:
        return NexGenPalette.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroIcon = _heroIconForSubCategory(sub.id);
    final accentColor = _accentForSubCategory(sub.id);
    final gradientColors = _gradientForSubCategory(sub.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/explore/$categoryId/sub/${sub.id}', extra: {'name': sub.name}),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.25),
                gradientColors[1].withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Large radial glow behind icon
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          gradientColors[0].withValues(alpha: 0.3),
                          gradientColors[1].withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Single hero icon - centered and prominent
                    Expanded(
                      child: Center(
                        child: Icon(
                          heroIcon,
                          size: 52,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: accentColor.withValues(alpha: 0.8),
                              blurRadius: 24,
                            ),
                            Shadow(
                              color: gradientColors[0].withValues(alpha: 0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subcategory name with arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            sub.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: accentColor.withValues(alpha: 0.8),
                          size: 10,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _PatternItemCard extends ConsumerWidget {
  final PatternItem item;
  const _PatternItemCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        // Check for active neighborhood sync before changing lights
        final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
        if (!shouldProceed) return;

        final repo = ref.read(wledRepositoryProvider);
        if (repo == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
          }
          return;
        }
        try {
          await repo.applyJson(item.wledPayload);
          // Update the active preset label
          ref.read(activePresetLabelProvider.notifier).state = item.name;
          // Attempt immediate local reflection similar to Scenes card
          final notifier = ref.read(wledStateProvider.notifier);
          final bri = item.wledPayload['bri'];
          if (bri is int) notifier.setBrightness(bri);
          final seg = item.wledPayload['seg'];
          if (seg is List && seg.isNotEmpty && seg.first is Map) {
            final s0 = seg.first as Map;
            final sx = s0['sx'];
            if (sx is int) notifier.setSpeed(sx);
            final col = s0['col'];
            if (col is List && col.isNotEmpty && col.first is List) {
              final c = col.first as List;
              if (c.length >= 3) {
                notifier.setColor(Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt()));
              }
            }
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${item.name}')));
          }
        } catch (e) {
          debugPrint('Apply pattern failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(children: [
          // Animated gradient preview from the item's palette
          Positioned.fill(child: _ItemLiveGradient(colors: _extractColorsFromItem(item), speed: 128)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NexGenPalette.matteBlack.withValues(alpha: 0.08),
                    NexGenPalette.matteBlack.withValues(alpha: 0.65),
                  ],
                ),
                border: Border.all(color: NexGenPalette.line),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(item.name, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Compact pattern item card for 4-column grid layout.
/// Shows a smaller preview with effect name and color slot indicator.
class _CompactPatternItemCard extends ConsumerWidget {
  final PatternItem item;
  final List<Color> themeColors;
  const _CompactPatternItemCard({required this.item, required this.themeColors});

  /// Get how many color slots this effect actually uses.
  /// Returns 0 if the effect generates its own colors / uses palette.
  ///
  /// Effect IDs aligned with WledEffectsCatalog (WLED 0.14+ firmware).
  /// Effects that use selected colors all receive 3 slots so all palette
  /// colors are sent — WLED ignores extras harmlessly.
  static int _getColorSlotsForEffect(int effectId) {
    // Effects that ignore user colors entirely (generate own or use palette).
    // Sourced from WledEffectsCatalog: generatesOwnColors + usesPalette.
    const autoColorEffects = {
      // generatesOwnColors
      4,   // Wipe Random
      5,   // Random Colors
      7,   // Dynamic
      8,   // Colorloop
      9,   // Rainbow
      14,  // Theater Rainbow
      19,  // Dissolve Rnd
      24,  // Strobe Rainbow
      26,  // Blink Rainbow
      29,  // Chase Random
      30,  // Chase Rainbow
      32,  // Chase Flash Rnd
      33,  // Rainbow Runner
      34,  // Colorful
      35,  // Traffic Light
      36,  // Sweep Random
      38,  // Aurora
      45,  // Fire Flicker
      63,  // Pride 2015
      66,  // Fire 2012
      88,  // Candle
      94,  // Sinelon Rainbow
      99,  // Ripple Rainbow
      101, // Pacifica
      104, // Sunrise
      116, // TV Simulator
      117, // Dynamic Smooth
      // usesPalette
      39,  // Stream
      42,  // Fireworks
      43,  // Rain
      61,  // Stream 2
      64,  // Juggle
      65,  // Palette
      67,  // Colorwaves
      68,  // Bpm
      69,  // Fill Noise
      70,  // Noise 1
      71,  // Noise 2
      72,  // Noise 3
      73,  // Noise 4
      74,  // Colortwinkles
      75,  // Lake
      79,  // Ripple
      80,  // Twinklefox
      81,  // Twinklecat
      89,  // Fireworks Starburst
      90,  // Fireworks 1D
      92,  // Sinelon
      93,  // Sinelon Dual
      97,  // Plasma
      105, // Phased
      106, // Twinkleup
      107, // Noise Pal
      108, // Sine
      109, // Phased Noise
      110, // Flow
      115, // Blends
      128, // Pixels
    };

    if (autoColorEffects.contains(effectId)) return 0;

    // All remaining effects that use/blend selected colors get 3 slots.
    // WLED's col array supports up to 3 colors per segment and safely
    // ignores slots an effect doesn't use, so sending all 3 is harmless
    // and ensures multi-color palettes display correctly.
    return 3;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectId = PatternRepository.effectIdFromPayload(item.wledPayload) ?? 0;
    final colorSlots = _getColorSlotsForEffect(effectId);
    final extractedColors = _extractColorsFromItem(item);

    // Always show all palette colors in preview so users see the full colorway.
    final displayColors = extractedColors;

    // Get effect name for display
    final effectName = _getEffectDisplayName(effectId);

    return InkWell(
      onTap: () => _handleTap(context, ref, effectId, extractedColors),
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
            // Realistic effect preview strip (takes 60% of height)
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                child: _EffectPreviewStrip(
                  colors: displayColors.isNotEmpty ? displayColors : [Colors.white],
                  effectId: effectId,
                  speed: _getSpeedFromPayload(item.wledPayload),
                ),
              ),
            ),
            // Text section (takes 40% of height)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      displayColors.isNotEmpty
                          ? displayColors.first.withValues(alpha: 0.15)
                          : NexGenPalette.cyan.withValues(alpha: 0.1),
                      NexGenPalette.matteBlack,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Pattern name
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    // Effect type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: displayColors.isNotEmpty
                            ? displayColors.first.withValues(alpha: 0.3)
                            : NexGenPalette.cyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        effectName,
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
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

  /// Get a user-friendly effect name from the effect ID
  static String _getEffectDisplayName(int effectId) {
    const effectNames = {
      0: 'Solid',
      1: 'Blink',
      2: 'Breathe',
      3: 'Wipe',
      6: 'Sweep',
      10: 'Scan',
      12: 'Fade',
      22: 'Running',
      23: 'Chase',
      37: 'Fill Noise',
      43: 'Theater',
      46: 'Twinkle',
      49: 'Fire',
      51: 'Gradient',
      52: 'Loading',
      63: 'Palette',
      65: 'Colorwave',
      67: 'Ripple',
      73: 'Pacifica',
      76: 'Fireworks',
      78: 'Meteor',
      108: 'Meteor',
      120: 'Sparkle',
    };
    return effectNames[effectId] ?? 'Effect';
  }

  /// Extract speed from WLED payload
  static double _getSpeedFromPayload(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map) {
          final sx = first['sx'];
          if (sx is num) return sx.toDouble();
        }
      }
    } catch (_) {}
    return 128; // Default speed
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref, int effectId, List<Color> extractedColors) async {
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      }
      return;
    }

    // For Solid effect (ID 0), show color picker if multiple colors available
    if (effectId == 0 && themeColors.length > 1) {
      if (context.mounted) {
        final selectedColor = await _showSolidColorPicker(context, themeColors);
        if (selectedColor != null && context.mounted) {
          await _applyPatternWithColor(context, ref, repo, selectedColor);
        }
      }
      return;
    }

    // Send all palette colors to WLED. Previously this showed a color
    // assignment dialog that forced users to drop colors when the effect
    // used fewer slots than available, causing 3-color palettes to lose
    // their 3rd color on 2-color effects. WLED safely ignores extra
    // colors in the col array, so sending all is harmless and ensures
    // the full colorway is applied.
    try {
      await repo.applyJson(item.wledPayload);
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
    final notifier = ref.read(wledStateProvider.notifier);
    final bri = item.wledPayload['bri'];
    if (bri is int) notifier.setBrightness(bri);
    final seg = item.wledPayload['seg'];
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      final s0 = seg.first as Map;
      final sx = s0['sx'];
      if (sx is int) notifier.setSpeed(sx);
      final col = s0['col'];
      if (col is List && col.isNotEmpty && col.first is List) {
        final c = col.first as List;
        if (c.length >= 3) {
          notifier.setColor(Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt()));
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

  Future<List<Color>?> _showColorAssignmentDialog(
    BuildContext context,
    List<Color> availableColors,
    int slots,
    int effectId,
  ) async {
    return showModalBottomSheet<List<Color>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ColorAssignmentSheet(
        availableColors: availableColors,
        slots: slots,
        effectId: effectId,
      ),
    );
  }

  Future<void> _applyPatternWithColor(BuildContext context, WidgetRef ref, WledRepository repo, Color color) async {
    try {
      // Create payload with selected color
      final payload = Map<String, dynamic>.from(item.wledPayload);
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final s0 = Map<String, dynamic>.from(seg.first as Map);
        s0['col'] = [[color.red, color.green, color.blue, 0]];
        payload['seg'] = [s0];
      }
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
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

  Future<void> _applyPatternWithColors(BuildContext context, WidgetRef ref, WledRepository repo, List<Color> colors, int effectId) async {
    try {
      final payload = Map<String, dynamic>.from(item.wledPayload);
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final s0 = Map<String, dynamic>.from(seg.first as Map);
        s0['col'] = colors.map((c) => [c.red, c.green, c.blue, 0]).toList();
        payload['seg'] = [s0];
      }
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = item.name;
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
}

// ---------------------------------------------------------------------------
// Helper widgets used by the extracted classes above
// ---------------------------------------------------------------------------

/// Bottom sheet for picking a solid color when using Solid effect.
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
          Row(
            children: [
              const Icon(Icons.palette, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Choose Solid Color',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Solid effect displays a single color. Select which color to use:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) => _ColorPickerTile(
              color: color,
              onTap: () => Navigator.pop(context, color),
            )).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for assigning colors to effect slots.
class _ColorAssignmentSheet extends StatefulWidget {
  final List<Color> availableColors;
  final int slots;
  final int effectId;
  const _ColorAssignmentSheet({
    required this.availableColors,
    required this.slots,
    required this.effectId,
  });

  @override
  State<_ColorAssignmentSheet> createState() => _ColorAssignmentSheetState();
}

class _ColorAssignmentSheetState extends State<_ColorAssignmentSheet> {
  late List<Color> _assignedColors;

  @override
  void initState() {
    super.initState();
    // Pre-fill with first N colors
    _assignedColors = widget.availableColors.take(widget.slots).toList();
    // Pad if needed
    while (_assignedColors.length < widget.slots) {
      _assignedColors.add(widget.availableColors.first);
    }
  }

  String _getSlotLabel(int index) {
    switch (index) {
      case 0: return 'Primary';
      case 1: return 'Secondary';
      case 2: return 'Accent';
      default: return 'Color ${index + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectName = kEffectNames[widget.effectId] ?? 'Effect ${widget.effectId}';

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
          Row(
            children: [
              const Icon(Icons.tune, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assign Colors for $effectName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This effect uses ${widget.slots} color${widget.slots > 1 ? 's' : ''}. Assign colors to each slot:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 16),
          // Slot assignment rows
          ...List.generate(widget.slots, (slotIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      _getSlotLabel(slotIndex),
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.availableColors.map((color) {
                          final isSelected = _assignedColors[slotIndex] == color;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _assignedColors[slotIndex] = color;
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ] : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // Preview strip
          Container(
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: _assignedColors),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _assignedColors),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Color picker tile for the solid color picker.
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
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.touch_app, color: Colors.white54, size: 20),
        ),
      ),
    );
  }
}

/// Wrapper to keep LiveGradientStrip lightweight in item cards.
class _ItemLiveGradient extends StatelessWidget {
  final List<Color> colors;
  final double speed;
  const _ItemLiveGradient({required this.colors, required this.speed});

  @override
  Widget build(BuildContext context) => LiveGradientStrip(colors: colors, speed: speed);
}

/// Realistic effect preview that animates based on the WLED effect type.
/// Shows users what the effect will look like on their lighting system.
class _EffectPreviewStrip extends StatefulWidget {
  final List<Color> colors;
  final int effectId;
  final double speed;

  const _EffectPreviewStrip({
    required this.colors,
    required this.effectId,
    this.speed = 128,
  });

  @override
  State<_EffectPreviewStrip> createState() => _EffectPreviewStripState();
}

class _EffectPreviewStripState extends State<_EffectPreviewStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _twinkleOpacities = [];
  final List<int> _twinkleColorIndices = [];

  @override
  void initState() {
    super.initState();
    // Map speed (0-255) to animation duration
    final durationMs = (3000 - (widget.speed / 255) * 2500).clamp(500, 5000).round();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    // Initialize twinkle state for popcorn/sparkle effects
    for (int i = 0; i < 20; i++) {
      _twinkleOpacities.add(0.0);
      _twinkleColorIndices.add(i % widget.colors.length);
    }

    if (widget.effectId != 0) {
      _controller.repeat();
    }
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
      builder: (context, child) {
        return CustomPaint(
          painter: _EffectPainter(
            colors: widget.colors,
            effectId: widget.effectId,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// Custom painter that draws realistic effect previews
class _EffectPainter extends CustomPainter {
  final List<Color> colors;
  final int effectId;
  final double progress;

  _EffectPainter({
    required this.colors,
    required this.effectId,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final ledCount = 30; // Simulated LED count for preview
    final ledWidth = size.width / ledCount;
    final ledHeight = size.height;

    switch (_getEffectType(effectId)) {
      case _EffectType.solid:
        _paintSolid(canvas, size, paint);
        break;
      case _EffectType.breathing:
        _paintBreathing(canvas, size, paint);
        break;
      case _EffectType.chase:
        _paintChase(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.wipe:
        _paintWipe(canvas, size, paint);
        break;
      case _EffectType.sparkle:
        _paintSparkle(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.scan:
        _paintScan(canvas, size, paint, ledWidth, ledHeight);
        break;
      case _EffectType.fade:
        _paintFade(canvas, size, paint);
        break;
      case _EffectType.gradient:
        _paintGradient(canvas, size, paint);
        break;
      case _EffectType.theater:
        _paintTheater(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.running:
        _paintRunning(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.twinkle:
        _paintTwinkle(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.fire:
        _paintFire(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.meteor:
        _paintMeteor(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.wave:
        _paintWave(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
    }
  }

  _EffectType _getEffectType(int effectId) {
    switch (effectId) {
      case 0: return _EffectType.solid;
      case 1: // Blink
      case 2: // Breathe
        return _EffectType.breathing;
      case 3: // Wipe
      case 4: // Wipe Random
        return _EffectType.wipe;
      case 6: // Sweep
      case 10: // Scan
      case 11: // Dual Scan
      case 13: // Scanner
      case 14: // Dual Scanner
        return _EffectType.scan;
      case 12: // Fade
      case 18: // Dissolve
        return _EffectType.fade;
      case 22: // Running 2
      case 23: // Chase
      case 24: // Chase Rainbow
      case 25: // Running Dual
      case 41: // Running
      case 42: // Running 2
        return _EffectType.running;
      case 43: // Theater Chase
      case 44: // Theater Chase Rainbow
        return _EffectType.theater;
      case 37: // Fill Noise
      case 46: // Twinklefox
      case 47: // Twinklecat
        return _EffectType.twinkle;
      case 51: // Gradient
      case 63: // Palette
      case 65: // Colorwaves
        return _EffectType.gradient;
      case 49: // Fire 2012
      case 54: // Fire Flicker
      case 74: // Candle
      case 75: // Fire
        return _EffectType.fire;
      case 78: // Meteor Rainbow
      case 108: // Meteor
      case 109: // Meteor Smooth
        return _EffectType.meteor;
      case 52: // Loading
      case 67: // Ripple
      case 70: // Lake
      case 73: // Pacifica
        return _EffectType.wave;
      case 76: // Fireworks
      case 77: // Rain
      case 120: // Sparkle
      case 121: // Sparkle+
        return _EffectType.sparkle;
      default:
        return _EffectType.chase; // Default to chase for unknown effects
    }
  }

  void _paintSolid(Canvas canvas, Size size, Paint paint) {
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintBreathing(Canvas canvas, Size size, Paint paint) {
    // Smooth sine wave breathing
    final breathValue = (sin(progress * 2 * pi) + 1) / 2;
    paint.color = colors.first.withValues(alpha: 0.3 + breathValue * 0.7);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintChase(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    final chaseLength = 5;
    final chasePos = (progress * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      final distFromChase = (i - chasePos + ledCount) % ledCount;
      if (distFromChase < chaseLength) {
        final colorIdx = distFromChase % colors.length;
        final brightness = 1.0 - (distFromChase / chaseLength);
        paint.color = colors[colorIdx].withValues(alpha: brightness);
      } else {
        paint.color = colors.last.withValues(alpha: 0.1);
      }
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintWipe(Canvas canvas, Size size, Paint paint) {
    final wipePos = progress * size.width;
    // First color (wiped area)
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, wipePos, size.height), paint);
    // Second color (unwiped area)
    paint.color = colors.length > 1 ? colors[1] : colors.first.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(wipePos, 0, size.width - wipePos, size.height), paint);
  }

  void _paintSparkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Background
    paint.color = colors.last.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Sparkles - use progress to create pseudo-random positions
    final sparkleCount = 8;
    for (int i = 0; i < sparkleCount; i++) {
      final seed = (progress * 1000 + i * 137).floor() % ledCount;
      final colorIdx = i % colors.length;
      final fadePhase = ((progress * 3 + i * 0.3) % 1.0);
      final opacity = fadePhase < 0.5 ? fadePhase * 2 : (1 - fadePhase) * 2;

      paint.color = colors[colorIdx].withValues(alpha: opacity.clamp(0.0, 1.0));
      final x = seed * ledWidth;
      // Draw as small circle for sparkle effect
      canvas.drawCircle(Offset(x + ledWidth / 2, size.height / 2), ledWidth * 0.8, paint);
    }
  }

  void _paintScan(Canvas canvas, Size size, Paint paint, double ledWidth, double ledHeight) {
    // Background
    paint.color = colors.last.withValues(alpha: 0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Scanning bar that bounces
    final bounce = (sin(progress * 2 * pi) + 1) / 2;
    final scanPos = bounce * (size.width - ledWidth * 3);
    final scanWidth = ledWidth * 3;

    // Glow behind scan bar
    final glowGradient = LinearGradient(
      colors: [
        colors.first.withValues(alpha: 0.0),
        colors.first.withValues(alpha: 0.5),
        colors.first,
        colors.first.withValues(alpha: 0.5),
        colors.first.withValues(alpha: 0.0),
      ],
    );
    paint.shader = glowGradient.createShader(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight));
    canvas.drawRect(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight), paint);
    paint.shader = null;
  }

  void _paintFade(Canvas canvas, Size size, Paint paint) {
    // Smooth color fade between colors
    final colorCount = colors.length;
    final colorProgress = progress * colorCount;
    final currentIdx = colorProgress.floor() % colorCount;
    final nextIdx = (currentIdx + 1) % colorCount;
    final blendFactor = colorProgress - colorProgress.floor();

    final blendedColor = Color.lerp(colors[currentIdx], colors[nextIdx], blendFactor)!;
    paint.color = blendedColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintGradient(Canvas canvas, Size size, Paint paint) {
    // Flowing gradient
    final offset = progress * 2;
    final extendedColors = [...colors, ...colors];
    final stops = List.generate(extendedColors.length, (i) => (i / (extendedColors.length - 1) + offset) % 2 / 2);
    stops.sort();

    final gradient = LinearGradient(
      colors: extendedColors,
      stops: stops,
    );
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;
  }

  void _paintTheater(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Theater chase - every 3rd LED lit, shifting
    final offset = (progress * 3).floor() % 3;

    for (int i = 0; i < ledCount; i++) {
      final isLit = (i + offset) % 3 == 0;
      final colorIdx = ((i + offset) ~/ 3) % colors.length;
      paint.color = isLit ? colors[colorIdx] : Colors.black.withValues(alpha: 0.3);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintRunning(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Running lights - segments of color moving
    final segmentLength = ledCount ~/ colors.length;
    final offset = (progress * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      final adjustedI = (i + offset) % ledCount;
      final colorIdx = (adjustedI ~/ segmentLength) % colors.length;
      paint.color = colors[colorIdx];
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintTwinkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Base gradient
    final gradient = LinearGradient(colors: colors);
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;

    // Twinkle overlay - bright spots that fade in/out
    final twinkleCount = 6;
    for (int i = 0; i < twinkleCount; i++) {
      final seed = (i * 17 + 7) % ledCount;
      final phase = ((progress * 2 + i * 0.2) % 1.0);
      final brightness = (sin(phase * 2 * pi) + 1) / 2;

      paint.color = Colors.white.withValues(alpha: brightness * 0.7);
      final x = seed * ledWidth + ledWidth / 2;
      canvas.drawCircle(Offset(x, size.height / 2), ledWidth * 0.6, paint);
    }
  }

  void _paintFire(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Fire effect with orange/red/yellow flickering
    final fireColors = colors.isNotEmpty ? colors : [Colors.red, Colors.orange, Colors.yellow];

    for (int i = 0; i < ledCount; i++) {
      // Create pseudo-random flicker based on position and time
      final flicker = (sin(progress * 10 + i * 0.5) + sin(progress * 7 + i * 0.3)) / 4 + 0.5;
      final colorIdx = ((flicker * fireColors.length).floor()).clamp(0, fireColors.length - 1);
      final brightness = 0.5 + flicker * 0.5;

      paint.color = fireColors[colorIdx].withValues(alpha: brightness.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintMeteor(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Background
    paint.color = Colors.black.withValues(alpha: 0.8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Meteor with tail
    final meteorPos = (progress * (ledCount + 10)).floor() - 5;
    final tailLength = 8;

    for (int i = 0; i < tailLength; i++) {
      final pos = meteorPos - i;
      if (pos >= 0 && pos < ledCount) {
        final brightness = 1.0 - (i / tailLength);
        final colorIdx = i % colors.length;
        paint.color = colors[colorIdx].withValues(alpha: brightness);
        canvas.drawRect(Rect.fromLTWH(pos * ledWidth, 0, ledWidth + 1, ledHeight), paint);
      }
    }
  }

  void _paintWave(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Smooth wave pattern
    for (int i = 0; i < ledCount; i++) {
      final waveOffset = sin(progress * 2 * pi + i * 0.3);
      final brightness = (waveOffset + 1) / 2;
      final colorIdx = (i * colors.length / ledCount).floor() % colors.length;
      paint.color = colors[colorIdx].withValues(alpha: 0.3 + brightness * 0.7);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.effectId != effectId ||
        oldDelegate.colors != colors;
  }
}

enum _EffectType {
  solid,
  breathing,
  chase,
  wipe,
  sparkle,
  scan,
  fade,
  gradient,
  theater,
  running,
  twinkle,
  fire,
  meteor,
  wave,
}

List<Color> _extractColorsFromItem(PatternItem item) {
  try {
    final seg = item.wledPayload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final first = seg.first;
      if (first is Map) {
        final col = first['col'];
        if (col is List) {
          final result = <Color>[];
          for (final c in col) {
            if (c is List && c.length >= 3) {
              final r = (c[0] as num).toInt().clamp(0, 255);
              final g = (c[1] as num).toInt().clamp(0, 255);
              final b = (c[2] as num).toInt().clamp(0, 255);
              result.add(Color.fromARGB(255, r, g, b));
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    }
  } catch (e) {
    debugPrint('Failed to extract colors from PatternItem: $e');
  }
  return const [Colors.white, Colors.white];
}

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
