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
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';
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
import 'package:nexgen_command/features/ai/pixel_strip_preview.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';

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
            var payload = data.toWledPayload();
            final channels = ref.read(effectiveChannelIdsProvider);
            if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
            await repo.applyJson(payload);
            ref.read(activePresetLabelProvider.notifier).state = data.name;
            ref.read(explorePreviewProvider.notifier).state = ExplorePreviewState(
              colors: data.colors,
              effectId: data.effectId,
              speed: data.speed,
              brightness: data.brightness,
              name: data.name,
            );
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
              Positioned.fill(child: LiveGradientStrip(colors: data.colors, speed: data.isStatic ? 0 : data.speed.toDouble())),
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
              if (!isFeatured)
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: NexGenPalette.line))))
              else
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: NexGenPalette.gold, width: 1.6)))),
              Positioned(
                left: 8,
                top: 8,
                child: EffectWithColorBehaviorBadge(
                  effectId: data.effectId,
                  effectName: data.effectName,
                  isStatic: data.isStatic,
                ),
              ),
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

class _GradientResultTile extends ConsumerWidget {
  final GradientPattern data;
  const _GradientResultTile({required this.data});

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
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
      var payload = data.toWledPayload();
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      final success = await repo.applyJson(payload);
      if (!success) throw Exception('Device did not accept command');
      ref.read(activePresetLabelProvider.notifier).state = data.name;
      ref.read(explorePreviewProvider.notifier).state = ExplorePreviewState(
        colors: data.colors,
        effectId: data.effectId,
        speed: data.speed,
        brightness: data.brightness,
        name: data.name,
      );
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
      var payload = _payloadFromCurrent();
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      await repo.applyJson(payload);
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
        var payload = <String, dynamic>{
          'seg': [{'grp': _current.grouping, 'spc': _current.spacing}]
        };
        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
        await repo.applyJson(payload);
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
                          id: _current.id, name: _current.name, colors: _current.colors,
                          effectId: _current.effectId, speed: v.round().clamp(0, 255),
                          intensity: _current.intensity, paletteId: _current.paletteId,
                          reverse: _current.reverse, grouping: _current.grouping, spacing: _current.spacing));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.speed}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Tooltip(message: 'Effect Strength', child: const Icon(Icons.tune, color: NexGenPalette.cyan)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _current.intensity.toDouble(),
                  min: 0,
                  max: 255,
                  onChanged: (v) {
                    setState(() => _current = SmartPattern(
                          id: _current.id, name: _current.name, colors: _current.colors,
                          effectId: _current.effectId, speed: _current.speed,
                          intensity: v.round().clamp(0, 255), paletteId: _current.paletteId,
                          reverse: _current.reverse, grouping: _current.grouping, spacing: _current.spacing));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.intensity}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
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
                          id: _current.id, name: _current.name, colors: _current.colors,
                          effectId: _current.effectId, speed: _current.speed,
                          intensity: _current.intensity, paletteId: _current.paletteId,
                          reverse: rev, grouping: _current.grouping, spacing: _current.spacing));
                    _scheduleDebouncedApply();
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.grid_view, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
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
                          id: _current.id, name: _current.name, colors: _current.colors,
                          effectId: _current.effectId, speed: _current.speed,
                          intensity: _current.intensity, paletteId: _current.paletteId,
                          reverse: _current.reverse, grouping: g, spacing: _current.spacing));
                    _scheduleDebouncedLayoutApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.grouping}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 6),
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
                          id: _current.id, name: _current.name, colors: _current.colors,
                          effectId: _current.effectId, speed: _current.speed,
                          intensity: _current.intensity, paletteId: _current.paletteId,
                          reverse: _current.reverse, grouping: _current.grouping, spacing: s));
                    _scheduleDebouncedLayoutApply();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('${_current.spacing}', style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.palette, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Text('Color Sequence', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            Builder(builder: (context) {
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
                    var palPayload = <String, dynamic>{'seg': [{'pal': seq}]};
                    final channels = ref.read(effectiveChannelIdsProvider);
                    if (channels.isNotEmpty) palPayload = applyChannelFilter(palPayload, channels, ref.read(deviceChannelsProvider));
                    await repo.applyJson(palPayload);
                  } catch (e) {
                    debugPrint('Apply custom palette failed: $e');
                  }
                },
              );
            }),
            const SizedBox(height: 12),
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
                          action: SnackBarAction(label: 'View', onPressed: () => context.push('/explore/scenes')),
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
                Text(behavior.shortName, style: TextStyle(color: behaviorColor, fontSize: 10, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors: return Icons.palette_outlined;
      case ColorBehavior.blendsSelectedColors: return Icons.gradient;
      case ColorBehavior.generatesOwnColors: return Icons.auto_awesome;
      case ColorBehavior.usesPalette: return Icons.color_lens_outlined;
    }
  }

  Color _colorForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors: return NexGenPalette.cyan;
      case ColorBehavior.blendsSelectedColors: return const Color(0xFF64B5F6);
      case ColorBehavior.generatesOwnColors: return const Color(0xFFFFB74D);
      case ColorBehavior.usesPalette: return const Color(0xFFBA68C8);
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

// ---------------------------------------------------------------------------
// CategoryDetailScreen
// ---------------------------------------------------------------------------

/// Detail screen for a single Pattern Category showing Sub-Category folders
/// with a featured card, Lumina AI search bar, and contextual color previews.
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
      body: asyncSubs.when(
        data: (subs) {
          if (subs.isEmpty) return const _CenteredText('No sub-categories yet');

          // ── CHANGE: Sort sports folders by league → conference → division ──
          final orderedSubs = categoryId == 'cat_sports'
              ? ([...subs]..sort((a, b) => _sportSubSortKey(a.id).compareTo(_sportSubSortKey(b.id))))
              : subs;

          final featured = _pickFeaturedSub(orderedSubs, categoryId);
          final remaining = orderedSubs.where((s) => s.id != featured?.id).toList();

          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ChannelSelectorBar(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _LuminaCategorySearchBar(categoryName: title),
                ),
              ),
              if (featured != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: _FeaturedSubCategoryCard(categoryId: categoryId, sub: featured),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'All $title Themes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, kBottomNavBarPadding),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.3,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _SubCategoryCard(categoryId: categoryId, sub: remaining[i]),
                    childCount: remaining.length,
                  ),
                ),
              ),
            ],
          );
        },
        error: (e, st) => _ErrorState(error: '$e'),
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  static SubCategory? _pickFeaturedSub(List<SubCategory> subs, String categoryId) {
    if (subs.isEmpty) return null;
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;
    String? targetId;
    switch (categoryId) {
      case 'cat_holiday':
        targetId = _nearestHolidaySubId(month, day);
        break;
      case 'cat_season':
        if (month >= 3 && month <= 5) targetId = 'sub_spring';
        else if (month >= 6 && month <= 8) targetId = 'sub_summer';
        else if (month >= 9 && month <= 11) targetId = 'sub_autumn';
        else targetId = 'sub_winter';
        break;
      case 'cat_sports':
        // Feature NFL in fall/winter, MLB in spring/summer, FIFA around World Cup
        if (month >= 9 || month <= 1) targetId = 'sub_nfl';
        else if (month >= 4 && month <= 9) targetId = 'sub_mlb';
        else targetId = 'sub_kc';
        break;
      case 'cat_party':
        targetId = 'sub_birthday';
        break;
      case 'cat_arch':
        targetId = 'sub_warm_whites';
        break;
    }
    if (targetId != null) {
      final match = subs.where((s) => s.id == targetId).firstOrNull;
      if (match != null) return match;
    }
    return subs.first;
  }

  static String? _nearestHolidaySubId(int month, int day) {
    if (month == 2 && day <= 28) return 'sub_valentines';
    if (month == 3 && day <= 17) return 'sub_st_patricks';
    if ((month == 3 && day >= 15) || (month == 4 && day <= 25)) return 'sub_easter';
    if ((month == 6 && day >= 20) || (month == 7 && day <= 4)) return 'sub_july4';
    if ((month == 10 && day >= 1) || (month == 10 && day <= 31)) return 'sub_halloween';
    if (month == 12 || (month == 11 && day >= 20)) return 'sub_xmas';
    if (month >= 1 && month <= 2) return 'sub_valentines';
    if (month >= 5 && month <= 6) return 'sub_july4';
    if (month >= 8 && month <= 9) return 'sub_halloween';
    return 'sub_xmas';
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

// ---------------------------------------------------------------------------
// Lumina AI contextual search bar
// ---------------------------------------------------------------------------
class _LuminaCategorySearchBar extends StatelessWidget {
  final String categoryName;
  const _LuminaCategorySearchBar({required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ask Lumina about $categoryName...')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.25), width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: NexGenPalette.cyan.withValues(alpha: 0.7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ask Lumina about $categoryName...',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13, fontWeight: FontWeight.w400),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white.withValues(alpha: 0.25)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Featured sub-category card
// ---------------------------------------------------------------------------
class _FeaturedSubCategoryCard extends StatelessWidget {
  final String categoryId;
  final SubCategory sub;
  const _FeaturedSubCategoryCard({required this.categoryId, required this.sub});

  @override
  Widget build(BuildContext context) {
    final gradientColors = _gradientForSubCategory(sub.id);
    final accentColor = _accentForSubCategory(sub.id);
    final heroIcon = _heroIconForSubCategory(sub.id);
    final previewColors = _previewColorsForSub(sub);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/explore/$categoryId/sub/${sub.id}', extra: {'name': sub.name}),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.3),
                gradientColors[1].withValues(alpha: 0.2),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.35, 1.0],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1),
            boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 8))],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -10,
                right: 20,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        gradientColors[0].withValues(alpha: 0.25),
                        gradientColors[1].withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(heroIcon, size: 28, color: Colors.white,
                            shadows: [Shadow(color: accentColor.withValues(alpha: 0.8), blurRadius: 16)]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sub.name,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('50+ designs available',
                                  style: TextStyle(color: accentColor.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Featured', style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 4),
                              Icon(Icons.auto_awesome, size: 12, color: accentColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: PixelStripPreview(colors: previewColors, pixelCount: 24, height: 42, animate: true, borderRadius: 10),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Tap to explore', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white.withValues(alpha: 0.35)),
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

// ---------------------------------------------------------------------------
// Shared sub-category helpers
// ---------------------------------------------------------------------------

/// Returns a sport/event-appropriate icon for each sub-category.
/// Uses explicit ID matches first, then keyword detection so new league and
/// team sub-IDs automatically pick up the correct sport icon.
IconData _heroIconForSubCategory(String subId) {
  // ── Holidays ──────────────────────────────────────────────────────────────
  switch (subId) {
    case 'sub_xmas':          return Icons.park;
    case 'sub_halloween':     return Icons.pest_control;
    case 'sub_july4':         return Icons.celebration;
    case 'sub_easter':        return Icons.egg;
    case 'sub_valentines':    return Icons.favorite;
    case 'sub_st_patricks':   return Icons.local_florist;
    // ── Legacy city subs ───────────────────────────────────────────────────
    case 'sub_kc':            return Icons.sports_football; // Chiefs + Royals city
    case 'sub_seattle':       return Icons.sports_football;
    case 'sub_rb_generic':
    case 'sub_gy_generic':
    case 'sub_ob_generic':    return Icons.emoji_events;
    // ── Seasons ────────────────────────────────────────────────────────────
    case 'sub_spring':        return Icons.local_florist;
    case 'sub_summer':        return Icons.wb_sunny;
    case 'sub_autumn':        return Icons.park;
    case 'sub_winter':        return Icons.ac_unit;
    // ── Architectural ──────────────────────────────────────────────────────
    case 'sub_warm_whites':   return Icons.wb_incandescent;
    case 'sub_cool_whites':   return Icons.light_mode;
    case 'sub_gold_accents':  return Icons.auto_awesome;
    case 'sub_security_floods': return Icons.flashlight_on;
    // ── Party ──────────────────────────────────────────────────────────────
    case 'sub_birthday':      return Icons.cake;
    case 'sub_elegant_dinner': return Icons.restaurant;
    case 'sub_rave':          return Icons.speaker;
    case 'sub_baby_shower':   return Icons.child_friendly;
    // ── Sports league roots ────────────────────────────────────────────────
    case 'sub_mlb':           return Icons.sports_baseball;
    case 'sub_nfl':           return Icons.sports_football;
    case 'sub_nba':           return Icons.sports_basketball;
    case 'sub_wnba':          return Icons.sports_basketball;
    case 'sub_nhl':           return Icons.sports_hockey;
    case 'sub_mls':           return Icons.sports_soccer;
    case 'sub_nwsl':          return Icons.sports_soccer;
    case 'sub_soccer':        return Icons.sports_soccer;
    case 'sub_epl':
    case 'sub_premier_league': return Icons.sports_soccer;
    case 'sub_la_liga':       return Icons.sports_soccer;
    case 'sub_bundesliga':    return Icons.sports_soccer;
    case 'sub_serie_a':       return Icons.sports_soccer;
    case 'sub_ligue_1':       return Icons.sports_soccer;
    case 'sub_fifa':
    case 'sub_world_cup':     return Icons.sports_soccer;
  }
  // ── Keyword fallback — handles all division / team sub-IDs ────────────────
  if (subId.contains('baseball') || subId.contains('mlb') ||
      subId.contains('_al_') || subId.contains('_nl_')) {
    return Icons.sports_baseball;
  }
  if (subId.contains('basketball') || subId.contains('nba') || subId.contains('wnba')) {
    return Icons.sports_basketball;
  }
  if (subId.contains('hockey') || subId.contains('nhl') ||
      subId.contains('atlantic') || subId.contains('metropolitan')) {
    return Icons.sports_hockey;
  }
  if (subId.contains('soccer') || subId.contains('mls') || subId.contains('nwsl') ||
      subId.contains('fifa') || subId.contains('world_cup') ||
      subId.contains('epl') || subId.contains('premier') ||
      subId.contains('la_liga') || subId.contains('bundesliga') ||
      subId.contains('serie_a') || subId.contains('ligue_1')) {
    return Icons.sports_soccer;
  }
  if (subId.contains('football') || subId.contains('nfl') ||
      subId.contains('_afc') || subId.contains('_nfc')) {
    return Icons.sports_football;
  }
  if (subId.contains('tennis'))  return Icons.sports_tennis;
  if (subId.contains('golf'))    return Icons.sports_golf;
  if (subId.contains('racing') || subId.contains('nascar')) return Icons.directions_car;
  return Icons.palette;
}

/// Returns a numeric sort key so sports sub-folders render in the canonical
/// league → conference → division order:
///   MLB  AL (East→Central→West) → NL (East→Central→West)
///   NFL  AFC (East→North→South→West) → NFC (East→North→South→West)
///   NBA  Eastern → Western
///   WNBA Eastern → Western
///   NHL  Atlantic → Metropolitan → Central → Pacific
///   MLS  Eastern → Western
///   NWSL Eastern → Western
///   FIFA / World Cup
int _sportSubSortKey(String id) {
  // MLB
  if (id.contains('mlb') || id.contains('_al_') || id.contains('_nl_') || id.contains('baseball')) {
    if (id.contains('al_east'))    return 110;
    if (id.contains('al_central')) return 120;
    if (id.contains('al_west'))    return 130;
    if (id.contains('_al'))        return 105;
    if (id.contains('nl_east'))    return 210;
    if (id.contains('nl_central')) return 220;
    if (id.contains('nl_west'))    return 230;
    if (id.contains('_nl'))        return 205;
    return 100; // MLB root
  }
  // NFL
  if (id.contains('nfl') || id.contains('_afc') || id.contains('_nfc') || id.contains('football')) {
    if (id.contains('afc_east'))  return 310;
    if (id.contains('afc_north')) return 320;
    if (id.contains('afc_south')) return 330;
    if (id.contains('afc_west'))  return 340;
    if (id.contains('afc'))       return 305;
    if (id.contains('nfc_east'))  return 410;
    if (id.contains('nfc_north')) return 420;
    if (id.contains('nfc_south')) return 430;
    if (id.contains('nfc_west'))  return 440;
    if (id.contains('nfc'))       return 405;
    return 300; // NFL root
  }
  // NBA
  if (id.contains('nba') || id.contains('basketball')) {
    if (id.contains('east')) return 510;
    if (id.contains('west')) return 520;
    return 500;
  }
  // WNBA
  if (id.contains('wnba')) {
    if (id.contains('east')) return 610;
    if (id.contains('west')) return 620;
    return 600;
  }
  // NHL
  if (id.contains('nhl') || id.contains('hockey')) {
    if (id.contains('atlantic'))                                   return 710;
    if (id.contains('metropolitan') || id.contains('metro'))       return 720;
    if (id.contains('central'))                                    return 730;
    if (id.contains('pacific'))                                    return 740;
    return 700;
  }
  // Soccer parent folder
  if (id == 'sub_soccer') return 795;
  // MLS
  if (id.contains('mls')) {
    if (id.contains('east')) return 810;
    if (id.contains('west')) return 820;
    return 800;
  }
  // International soccer leagues (under Soccer parent)
  if (id.contains('epl') || id.contains('premier')) return 830;
  if (id.contains('la_liga')) return 840;
  if (id.contains('bundesliga')) return 850;
  if (id.contains('serie_a')) return 860;
  if (id.contains('ligue_1')) return 870;
  // NWSL
  if (id.contains('nwsl')) {
    if (id.contains('east')) return 910;
    if (id.contains('west')) return 920;
    return 900;
  }
  // FIFA / World Cup
  if (id.contains('fifa') || id.contains('world_cup')) return 950;
  // Generic soccer fallback
  if (id.contains('soccer')) return 880;
  // Legacy city subs
  if (id == 'sub_kc')                return 1000;
  if (id == 'sub_seattle')           return 1010;
  // Generic color combos
  if (id.contains('_generic'))       return 1100;
  return 9999;
}

/// Handpicked gradient pairs for each sub-category — curated for card aesthetics.
/// Includes league-level entries for new sports hierarchy.
List<Color> _gradientForSubCategory(String subId) {
  switch (subId) {
    // ── Holidays ─────────────────────────────────────────────────────────────
    case 'sub_xmas':        return const [Color(0xFF2E7D32), Color(0xFFC62828)];
    case 'sub_halloween':   return const [Color(0xFFFF6D00), Color(0xFF6A1B9A)];
    case 'sub_july4':       return const [Color(0xFFEF5350), Color(0xFF1565C0)];
    case 'sub_easter':      return const [Color(0xFFF8BBD0), Color(0xFFB39DDB)];
    case 'sub_valentines':  return const [Color(0xFFE91E63), Color(0xFFAD1457)];
    case 'sub_st_patricks': return const [Color(0xFF43A047), Color(0xFF00C853)];
    // ── Legacy sports subs ────────────────────────────────────────────────────
    case 'sub_kc':          return const [Color(0xFFD32F2F), Color(0xFFFFB300)];
    case 'sub_seattle':     return const [Color(0xFF1B5E20), Color(0xFF1565C0)];
    case 'sub_rb_generic':  return const [Color(0xFFD32F2F), Color(0xFF1565C0)];
    case 'sub_gy_generic':  return const [Color(0xFF2E7D32), Color(0xFFF9A825)];
    case 'sub_ob_generic':  return const [Color(0xFFEF6C00), Color(0xFF1565C0)];
    // ── Seasons ───────────────────────────────────────────────────────────────
    case 'sub_spring':      return const [Color(0xFF81C784), Color(0xFFF48FB1)];
    case 'sub_summer':      return const [Color(0xFFFFEE58), Color(0xFF29B6F6)];
    case 'sub_autumn':      return const [Color(0xFFFF8F00), Color(0xFF6D4C41)];
    case 'sub_winter':      return const [Color(0xFF81D4FA), Color(0xFF7E57C2)];
    // ── Architectural ─────────────────────────────────────────────────────────
    case 'sub_warm_whites':   return const [Color(0xFFFFB74D), Color(0xFFFF8A65)];
    case 'sub_cool_whites':   return const [Color(0xFF90A4AE), Color(0xFFE0E0E0)];
    case 'sub_gold_accents':  return const [Color(0xFFFFD54F), Color(0xFFFFA000)];
    case 'sub_security_floods': return const [Color(0xFFE0E0E0), Color(0xFF4FC3F7)];
    // ── Party ─────────────────────────────────────────────────────────────────
    case 'sub_birthday':      return const [Color(0xFF00E5FF), Color(0xFFFF4081)];
    case 'sub_elegant_dinner': return const [Color(0xFFFFB74D), Color(0xFF5D4037)];
    case 'sub_rave':          return const [Color(0xFFAA00FF), Color(0xFF00E5FF)];
    case 'sub_baby_shower':   return const [Color(0xFF80DEEA), Color(0xFFF8BBD0)];
    // ── Sports league roots ───────────────────────────────────────────────────
    case 'sub_mlb':         return const [Color(0xFF1A237E), Color(0xFFB71C1C)]; // Navy/Red
    case 'sub_nfl':         return const [Color(0xFF0D1B2A), Color(0xFF8B0000)]; // Dark/Crimson
    case 'sub_nba':         return const [Color(0xFFEF6C00), Color(0xFF1565C0)]; // Orange/Blue
    case 'sub_wnba':        return const [Color(0xFFEF6C00), Color(0xFF880E4F)]; // Orange/Magenta
    case 'sub_nhl':         return const [Color(0xFF1A237E), Color(0xFFCFD8DC)]; // Navy/Silver
    case 'sub_mls':         return const [Color(0xFF005293), Color(0xFF003060)]; // MLS Blue
    case 'sub_nwsl':        return const [Color(0xFF00A3AD), Color(0xFF006D75)]; // NWSL Teal
    case 'sub_soccer':      return const [Color(0xFF00D4FF), Color(0xFF0088AA)]; // Soccer Cyan
    case 'sub_epl':
    case 'sub_premier_league': return const [Color(0xFF3D195B), Color(0xFF280E3B)]; // EPL Purple
    case 'sub_la_liga':     return const [Color(0xFFFF6B35), Color(0xFFCC4400)]; // La Liga Orange
    case 'sub_bundesliga':  return const [Color(0xFFD4020D), Color(0xFF8B0000)]; // Bundesliga Red
    case 'sub_serie_a':     return const [Color(0xFF1B4FBB), Color(0xFF0D2D6B)]; // Serie A Blue
    case 'sub_ligue_1':     return const [Color(0xFF003189), Color(0xFF001E55)]; // Ligue 1 Navy
    case 'sub_fifa':
    case 'sub_world_cup':   return const [Color(0xFFFFD700), Color(0xFF1565C0)]; // Gold/Blue
    // ── MLB conferences ───────────────────────────────────────────────────────
    case 'sub_mlb_al':
    case 'sub_mlb_al_east':
    case 'sub_mlb_al_central':
    case 'sub_mlb_al_west':  return const [Color(0xFF1A237E), Color(0xFF0D47A1)];
    case 'sub_mlb_nl':
    case 'sub_mlb_nl_east':
    case 'sub_mlb_nl_central':
    case 'sub_mlb_nl_west':  return const [Color(0xFFB71C1C), Color(0xFF880E4F)];
    // ── NFL conferences ───────────────────────────────────────────────────────
    case 'sub_nfl_afc':
    case 'sub_nfl_afc_east':
    case 'sub_nfl_afc_north':
    case 'sub_nfl_afc_south':
    case 'sub_nfl_afc_west': return const [Color(0xFF1565C0), Color(0xFF0D1B2A)];
    case 'sub_nfl_nfc':
    case 'sub_nfl_nfc_east':
    case 'sub_nfl_nfc_north':
    case 'sub_nfl_nfc_south':
    case 'sub_nfl_nfc_west': return const [Color(0xFF8B0000), Color(0xFF4A0000)];
    // ── NHL divisions ─────────────────────────────────────────────────────────
    case 'sub_nhl_atlantic':     return const [Color(0xFF1A237E), Color(0xFFCFD8DC)];
    case 'sub_nhl_metropolitan': return const [Color(0xFF0D47A1), Color(0xFFB0BEC5)];
    case 'sub_nhl_central':      return const [Color(0xFF004D40), Color(0xFFCFD8DC)];
    case 'sub_nhl_pacific':      return const [Color(0xFF1B5E20), Color(0xFF80DEEA)];
    // ── NBA conferences ───────────────────────────────────────────────────────
    case 'sub_nba_east': return const [Color(0xFFEF6C00), Color(0xFF1565C0)];
    case 'sub_nba_west': return const [Color(0xFF6A1B9A), Color(0xFFEF6C00)];
    // ── MLS/NWSL conferences ──────────────────────────────────────────────────
    case 'sub_mls_east': return const [Color(0xFF005293), Color(0xFF003060)];
    case 'sub_mls_west': return const [Color(0xFF005293), Color(0xFF4A148C)];
    case 'sub_nwsl_east': return const [Color(0xFF00A3AD), Color(0xFF006D75)];
    case 'sub_nwsl_west': return const [Color(0xFF00A3AD), Color(0xFF880E4F)];
  }
  return [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.5)];
}

/// Handpicked accent color for each sub-category.
Color _accentForSubCategory(String subId) {
  switch (subId) {
    // ── Holidays ──────────────────────────────────────────────────────────────
    case 'sub_xmas':        return const Color(0xFF4CAF50);
    case 'sub_halloween':   return const Color(0xFFFF6D00);
    case 'sub_july4':       return const Color(0xFFEF5350);
    case 'sub_easter':      return const Color(0xFFF8BBD0);
    case 'sub_valentines':  return const Color(0xFFE91E63);
    case 'sub_st_patricks': return const Color(0xFF00C853);
    // ── Legacy sports subs ────────────────────────────────────────────────────
    case 'sub_kc':          return const Color(0xFFD32F2F);
    case 'sub_seattle':     return const Color(0xFF43A047);
    case 'sub_rb_generic':  return const Color(0xFFEF5350);
    case 'sub_gy_generic':  return const Color(0xFF66BB6A);
    case 'sub_ob_generic':  return const Color(0xFFEF6C00);
    // ── Seasons ───────────────────────────────────────────────────────────────
    case 'sub_spring':      return const Color(0xFFF48FB1);
    case 'sub_summer':      return const Color(0xFFFFEE58);
    case 'sub_autumn':      return const Color(0xFFFF8F00);
    case 'sub_winter':      return const Color(0xFF81D4FA);
    // ── Architectural ─────────────────────────────────────────────────────────
    case 'sub_warm_whites':   return const Color(0xFFFFB74D);
    case 'sub_cool_whites':   return const Color(0xFF90A4AE);
    case 'sub_gold_accents':  return const Color(0xFFFFD54F);
    case 'sub_security_floods': return const Color(0xFF4FC3F7);
    // ── Party ─────────────────────────────────────────────────────────────────
    case 'sub_birthday':      return const Color(0xFF00E5FF);
    case 'sub_elegant_dinner': return const Color(0xFFFFB74D);
    case 'sub_rave':          return const Color(0xFFAA00FF);
    case 'sub_baby_shower':   return const Color(0xFF80DEEA);
    // ── Sports league roots ───────────────────────────────────────────────────
    case 'sub_mlb':         return const Color(0xFFB71C1C);   // Red
    case 'sub_nfl':         return const Color(0xFFFF6F00);   // Amber
    case 'sub_nba':         return const Color(0xFFEF6C00);   // Orange
    case 'sub_wnba':        return const Color(0xFFEF6C00);
    case 'sub_nhl':         return const Color(0xFF81D4FA);   // Ice blue
    case 'sub_mls':         return const Color(0xFF005293);   // MLS Blue
    case 'sub_nwsl':        return const Color(0xFF00A3AD);   // NWSL Teal
    case 'sub_soccer':      return const Color(0xFF00D4FF);   // Soccer Cyan
    case 'sub_epl':
    case 'sub_premier_league': return const Color(0xFF3D195B); // EPL Purple
    case 'sub_la_liga':     return const Color(0xFFFF6B35);   // La Liga Orange
    case 'sub_bundesliga':  return const Color(0xFFD4020D);   // Bundesliga Red
    case 'sub_serie_a':     return const Color(0xFF1B4FBB);   // Serie A Blue
    case 'sub_ligue_1':     return const Color(0xFF003189);   // Ligue 1 Blue
    case 'sub_fifa':
    case 'sub_world_cup':   return const Color(0xFFFFD700);   // Gold
    // ── MLB divisions ─────────────────────────────────────────────────────────
    case 'sub_mlb_al':
    case 'sub_mlb_al_east':
    case 'sub_mlb_al_central':
    case 'sub_mlb_al_west': return const Color(0xFF42A5F5);
    case 'sub_mlb_nl':
    case 'sub_mlb_nl_east':
    case 'sub_mlb_nl_central':
    case 'sub_mlb_nl_west': return const Color(0xFFEF5350);
    // ── NFL divisions ─────────────────────────────────────────────────────────
    case 'sub_nfl_afc':
    case 'sub_nfl_afc_east':
    case 'sub_nfl_afc_north':
    case 'sub_nfl_afc_south':
    case 'sub_nfl_afc_west': return const Color(0xFF42A5F5);
    case 'sub_nfl_nfc':
    case 'sub_nfl_nfc_east':
    case 'sub_nfl_nfc_north':
    case 'sub_nfl_nfc_south':
    case 'sub_nfl_nfc_west': return const Color(0xFFEF5350);
    // ── NHL divisions ─────────────────────────────────────────────────────────
    case 'sub_nhl_atlantic':     return const Color(0xFF81D4FA);
    case 'sub_nhl_metropolitan': return const Color(0xFF90CAF9);
    case 'sub_nhl_central':      return const Color(0xFF80CBC4);
    case 'sub_nhl_pacific':      return const Color(0xFF80DEEA);
    // ── NBA/MLS/NWSL conferences ──────────────────────────────────────────────
    case 'sub_nba_east':  return const Color(0xFFEF6C00);
    case 'sub_nba_west':  return const Color(0xFFAA00FF);
    case 'sub_mls_east':  return const Color(0xFF43A047);
    case 'sub_mls_west':  return const Color(0xFF6A1B9A);
    case 'sub_nwsl_east': return const Color(0xFF1976D2);
    case 'sub_nwsl_west': return const Color(0xFF880E4F);
  }
  return NexGenPalette.cyan;
}

/// Get representative palette colors for a sub-category's PixelStripPreview.
List<Color> _previewColorsForSub(SubCategory sub) {
  if (sub.themeColors.isNotEmpty) return sub.themeColors;
  final g = _gradientForSubCategory(sub.id);
  if (g.length < 2) return g;
  return [
    g[0],
    Color.lerp(g[0], g[1], 0.35)!,
    Color.lerp(g[0], g[1], 0.65)!,
    g[1],
  ];
}

// ---------------------------------------------------------------------------
// Enhanced sub-category grid card
// ---------------------------------------------------------------------------
class _SubCategoryCard extends StatelessWidget {
  final String categoryId;
  final SubCategory sub;
  const _SubCategoryCard({required this.categoryId, required this.sub});

  @override
  Widget build(BuildContext context) {
    final heroIcon = _heroIconForSubCategory(sub.id);
    final accentColor = _accentForSubCategory(sub.id);
    final gradientColors = _gradientForSubCategory(sub.id);
    final previewColors = _previewColorsForSub(sub);

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
            border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1),
            boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 6))],
          ),
          child: Stack(
            children: [
              // Glow orb — offset top-right for depth
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  width: 60,
                  height: 60,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon — top-left with glow
                    Icon(
                      heroIcon,
                      size: 26,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: accentColor.withValues(alpha: 0.7), blurRadius: 16),
                        Shadow(color: gradientColors[0].withValues(alpha: 0.4), blurRadius: 10),
                      ],
                    ),
                    const Spacer(),
                    // Color gradient bar
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2.5),
                        gradient: LinearGradient(
                          colors: gradientColors,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Name
                    Text(
                      sub.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Text(
                          'Explore',
                          style: TextStyle(color: accentColor.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_ios, color: accentColor.withValues(alpha: 0.5), size: 7),
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
          var itemPayload = Map<String, dynamic>.from(item.wledPayload);
          final channels = ref.read(effectiveChannelIdsProvider);
          if (channels.isNotEmpty) itemPayload = applyChannelFilter(itemPayload, channels, ref.read(deviceChannelsProvider));
          await repo.applyJson(itemPayload);
          ref.read(activePresetLabelProvider.notifier).state = item.name;
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
          Positioned.fill(child: _ItemLiveGradient(colors: _extractColorsFromItem(item), speed: 128)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [NexGenPalette.matteBlack.withValues(alpha: 0.08), NexGenPalette.matteBlack.withValues(alpha: 0.65)],
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
class _CompactPatternItemCard extends ConsumerWidget {
  final PatternItem item;
  final List<Color> themeColors;
  const _CompactPatternItemCard({required this.item, required this.themeColors});

  static int _getColorSlotsForEffect(int effectId) {
    const autoColorEffects = {
      4, 5, 7, 8, 9, 14, 19, 24, 26, 29, 30, 32, 33, 34, 35, 36, 38, 45, 63, 66, 88,
      94, 99, 101, 104, 116, 117, 39, 42, 43, 61, 64, 65, 67, 68, 69, 70, 71, 72, 73,
      74, 75, 79, 80, 81, 89, 90, 92, 93, 97, 105, 106, 107, 108, 109, 110, 115, 128,
    };
    if (autoColorEffects.contains(effectId)) return 0;
    return 3;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectId = PatternRepository.effectIdFromPayload(item.wledPayload) ?? 0;
    final extractedColors = _extractColorsFromItem(item);
    final displayColors = extractedColors;
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
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      displayColors.isNotEmpty ? displayColors.first.withValues(alpha: 0.15) : NexGenPalette.cyan.withValues(alpha: 0.1),
                      NexGenPalette.matteBlack,
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                        color: displayColors.isNotEmpty
                            ? displayColors.first.withValues(alpha: 0.3)
                            : NexGenPalette.cyan.withValues(alpha: 0.2),
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

  static String _getEffectDisplayName(int effectId) {
    const effectNames = {
      0: 'Solid', 1: 'Blink', 2: 'Breathe', 3: 'Wipe', 6: 'Sweep', 10: 'Scan',
      12: 'Fade', 22: 'Running', 23: 'Chase', 37: 'Fill Noise', 43: 'Theater',
      46: 'Twinkle', 49: 'Fire', 51: 'Gradient', 52: 'Loading', 63: 'Palette',
      65: 'Colorwave', 67: 'Ripple', 73: 'Pacifica', 76: 'Fireworks', 78: 'Meteor',
      108: 'Meteor', 120: 'Sparkle',
    };
    return effectNames[effectId] ?? 'Effect';
  }

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
    return 128;
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref, int effectId, List<Color> extractedColors) async {
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No device connected')));
      }
      return;
    }

    if (effectId == 0 && themeColors.length > 1) {
      if (context.mounted) {
        final selectedColor = await _showSolidColorPicker(context, themeColors);
        if (selectedColor != null && context.mounted) {
          await _applyPatternWithColor(context, ref, repo, selectedColor);
        }
      }
      return;
    }

    try {
      var applyPayload = Map<String, dynamic>.from(item.wledPayload);
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) applyPayload = applyChannelFilter(applyPayload, channels, ref.read(deviceChannelsProvider));
      await repo.applyJson(applyPayload);
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

  Future<void> _applyPatternWithColor(BuildContext context, WidgetRef ref, WledRepository repo, Color color) async {
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
      debugPrint('Apply pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }

  Future<void> _applyPatternWithColors(BuildContext context, WidgetRef ref, WledRepository repo, List<Color> colors, int effectId) async {
    try {
      var payload = Map<String, dynamic>.from(item.wledPayload);
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final s0 = Map<String, dynamic>.from(seg.first as Map);
        s0['col'] = colors.map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList();
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
      debugPrint('Apply pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to apply pattern')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Helper bottom sheets
// ---------------------------------------------------------------------------

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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NexGenPalette.textHigh, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Solid effect displays a single color. Select which color to use:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) => _ColorPickerTile(color: color, onTap: () => Navigator.pop(context, color))).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
        ],
      ),
    );
  }
}

class _ColorAssignmentSheet extends StatefulWidget {
  final List<Color> availableColors;
  final int slots;
  final int effectId;
  const _ColorAssignmentSheet({required this.availableColors, required this.slots, required this.effectId});

  @override
  State<_ColorAssignmentSheet> createState() => _ColorAssignmentSheetState();
}

class _ColorAssignmentSheetState extends State<_ColorAssignmentSheet> {
  late List<Color> _assignedColors;

  @override
  void initState() {
    super.initState();
    _assignedColors = widget.availableColors.take(widget.slots).toList();
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NexGenPalette.textHigh, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This effect uses ${widget.slots} color${widget.slots > 1 ? 's' : ''}. Assign colors to each slot:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
          ),
          const SizedBox(height: 16),
          ...List.generate(widget.slots, (slotIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(_getSlotLabel(slotIndex), style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.availableColors.map((color) {
                          final isSelected = _assignedColors[slotIndex] == color;
                          return GestureDetector(
                            onTap: () => setState(() => _assignedColors[slotIndex] = color),
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
                                boxShadow: isSelected ? [BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)] : null,
                              ),
                              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
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
          Container(
            height: 24,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: _assignedColors)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _assignedColors),
                  style: FilledButton.styleFrom(backgroundColor: NexGenPalette.cyan),
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

class _ItemLiveGradient extends StatelessWidget {
  final List<Color> colors;
  final double speed;
  const _ItemLiveGradient({required this.colors, required this.speed});

  @override
  Widget build(BuildContext context) => LiveGradientStrip(colors: colors, speed: speed);
}

// ---------------------------------------------------------------------------
// Effect preview strip (unchanged)
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
  final List<double> _twinkleOpacities = [];
  final List<int> _twinkleColorIndices = [];

  @override
  void initState() {
    super.initState();
    final durationMs = (3000 - (widget.speed / 255) * 2500).clamp(500, 5000).round();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: durationMs));
    for (int i = 0; i < 20; i++) {
      _twinkleOpacities.add(0.0);
      _twinkleColorIndices.add(i % widget.colors.length);
    }
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
      builder: (context, child) {
        return CustomPaint(
          painter: _EffectPainter(colors: widget.colors, effectId: widget.effectId, progress: _controller.value),
          size: Size.infinite,
        );
      },
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

    switch (_getEffectType(effectId)) {
      case _EffectType.solid:     _paintSolid(canvas, size, paint); break;
      case _EffectType.breathing: _paintBreathing(canvas, size, paint); break;
      case _EffectType.chase:     _paintChase(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.wipe:      _paintWipe(canvas, size, paint); break;
      case _EffectType.sparkle:   _paintSparkle(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.scan:      _paintScan(canvas, size, paint, ledWidth, ledHeight); break;
      case _EffectType.fade:      _paintFade(canvas, size, paint); break;
      case _EffectType.gradient:  _paintGradient(canvas, size, paint); break;
      case _EffectType.theater:   _paintTheater(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.running:   _paintRunning(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.twinkle:   _paintTwinkle(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.fire:      _paintFire(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.meteor:    _paintMeteor(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
      case _EffectType.wave:      _paintWave(canvas, size, paint, ledCount, ledWidth, ledHeight); break;
    }
  }

  _EffectType _getEffectType(int effectId) {
    switch (effectId) {
      case 0: return _EffectType.solid;
      case 1: case 2: return _EffectType.breathing;
      case 3: case 4: return _EffectType.wipe;
      case 6: case 10: case 11: case 13: case 14: return _EffectType.scan;
      case 12: case 18: return _EffectType.fade;
      case 22: case 23: case 24: case 25: case 41: case 42: return _EffectType.running;
      case 43: case 44: return _EffectType.theater;
      case 37: case 46: case 47: return _EffectType.twinkle;
      case 51: case 63: case 65: return _EffectType.gradient;
      case 49: case 54: case 74: case 75: return _EffectType.fire;
      case 78: case 108: case 109: return _EffectType.meteor;
      case 52: case 67: case 70: case 73: return _EffectType.wave;
      case 76: case 77: case 120: case 121: return _EffectType.sparkle;
      default: return _EffectType.chase;
    }
  }

  void _paintSolid(Canvas canvas, Size size, Paint paint) {
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintBreathing(Canvas canvas, Size size, Paint paint) {
    final breathValue = (sin(progress * 2 * pi) + 1) / 2;
    paint.color = colors.first.withValues(alpha: 0.3 + breathValue * 0.7);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintChase(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    const chaseLength = 5;
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
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, wipePos, size.height), paint);
    paint.color = colors.length > 1 ? colors[1] : colors.first.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(wipePos, 0, size.width - wipePos, size.height), paint);
  }

  void _paintSparkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    paint.color = colors.last.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    const sparkleCount = 8;
    for (int i = 0; i < sparkleCount; i++) {
      final seed = (progress * 1000 + i * 137).floor() % ledCount;
      final colorIdx = i % colors.length;
      final fadePhase = ((progress * 3 + i * 0.3) % 1.0);
      final opacity = fadePhase < 0.5 ? fadePhase * 2 : (1 - fadePhase) * 2;
      paint.color = colors[colorIdx].withValues(alpha: opacity.clamp(0.0, 1.0));
      final x = seed * ledWidth;
      canvas.drawCircle(Offset(x + ledWidth / 2, size.height / 2), ledWidth * 0.8, paint);
    }
  }

  void _paintScan(Canvas canvas, Size size, Paint paint, double ledWidth, double ledHeight) {
    paint.color = colors.last.withValues(alpha: 0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final bounce = (sin(progress * 2 * pi) + 1) / 2;
    final scanPos = bounce * (size.width - ledWidth * 3);
    final scanWidth = ledWidth * 3;
    final glowGradient = LinearGradient(
      colors: [colors.first.withValues(alpha: 0.0), colors.first.withValues(alpha: 0.5), colors.first, colors.first.withValues(alpha: 0.5), colors.first.withValues(alpha: 0.0)],
    );
    paint.shader = glowGradient.createShader(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight));
    canvas.drawRect(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight), paint);
    paint.shader = null;
  }

  void _paintFade(Canvas canvas, Size size, Paint paint) {
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
    final offset = progress * 2;
    final extendedColors = [...colors, ...colors];
    final stops = List.generate(extendedColors.length, (i) => (i / (extendedColors.length - 1) + offset) % 2 / 2);
    stops.sort();
    final gradient = LinearGradient(colors: extendedColors, stops: stops);
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;
  }

  void _paintTheater(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    final offset = (progress * 3).floor() % 3;
    for (int i = 0; i < ledCount; i++) {
      final isLit = (i + offset) % 3 == 0;
      final colorIdx = ((i + offset) ~/ 3) % colors.length;
      paint.color = isLit ? colors[colorIdx] : Colors.black.withValues(alpha: 0.3);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintRunning(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
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
    final gradient = LinearGradient(colors: colors);
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;
    const twinkleCount = 6;
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
    final fireColors = colors.isNotEmpty ? colors : [Colors.red, Colors.orange, Colors.yellow];
    for (int i = 0; i < ledCount; i++) {
      final flicker = (sin(progress * 10 + i * 0.5) + sin(progress * 7 + i * 0.3)) / 4 + 0.5;
      final colorIdx = ((flicker * fireColors.length).floor()).clamp(0, fireColors.length - 1);
      final brightness = 0.5 + flicker * 0.5;
      paint.color = fireColors[colorIdx].withValues(alpha: brightness.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintMeteor(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    paint.color = Colors.black.withValues(alpha: 0.8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final meteorPos = (progress * (ledCount + 10)).floor() - 5;
    const tailLength = 8;
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
    return oldDelegate.progress != progress || oldDelegate.effectId != effectId || oldDelegate.colors != colors;
  }
}

enum _EffectType { solid, breathing, chase, wipe, sparkle, scan, fade, gradient, theater, running, twinkle, fire, meteor, wave }

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