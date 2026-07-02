import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_apply.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';

/// Design Studio Slice 3 — map-driven smart presets on the dashboard. The first
/// thing a customer sees from their roofline map: pick a base + accent color and
/// the accent lands on the mapped corners / peaks / features. No AI round-trip.
///
/// Gracefully degrades: with no map it shows a single "Map your roofline to
/// unlock" hook (never an error, never dead buttons).
class SmartPresetsSection extends ConsumerWidget {
  const SmartPresetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMap = ref.watch(hasRooflineConfigProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 18),
            const SizedBox(width: 8),
            Text('Smart Presets',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        if (!hasMap)
          const _NoMapCard()
        else
          for (final preset in kSmartPresets) ...[
            _PresetCard(
              preset: preset,
              onTap: () => _showPresetSheet(context, ref, preset),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  void _showPresetSheet(BuildContext context, WidgetRef ref, SmartPreset preset) {
    List<int> base = preset.defaultBase;
    List<int> accent = preset.defaultAccent;
    bool applying = false;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(preset.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(preset.description,
                  style: const TextStyle(color: NexGenPalette.textMedium)),
              const SizedBox(height: 16),
              _SwatchRow(
                label: 'Base',
                selected: base,
                onPick: (c) => setSheet(() => base = c),
              ),
              const SizedBox(height: 12),
              _SwatchRow(
                label: 'Accent',
                selected: accent,
                onPick: (c) => setSheet(() => accent = c),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: applying
                      ? null
                      : () async {
                          setSheet(() => applying = true);
                          final result = await applySmartPreset(
                            ref,
                            preset: preset,
                            baseRgbw: base,
                            accentRgbw: accent,
                          );
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          if (context.mounted) {
                            _showResult(context, ref, result);
                          }
                        },
                  icon: applying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: Text('Apply ${preset.name}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResult(
      BuildContext context, WidgetRef ref, SmartPresetApplyResult result) {
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case SmartPresetApplyResult.applied:
        messenger.showSnackBar(
          const SnackBar(content: Text('Applied.'), backgroundColor: Colors.green),
        );
        break;
      case SmartPresetApplyResult.staleApplied:
        messenger.showSnackBar(SnackBar(
          content: const Text('Applied — but your roofline changed. Remap for '
              'perfect placement.'),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Refine',
            onPressed: () => context.push(AppRoutes.rooflineRefine),
          ),
        ));
        break;
      case SmartPresetApplyResult.noMap:
        messenger.showSnackBar(SnackBar(
          content: const Text('Map your roofline first to place accents.'),
          action: SnackBarAction(
            label: 'Map',
            onPressed: () => context.push(AppRoutes.rooflineEditor),
          ),
        ));
        break;
      case SmartPresetApplyResult.error:
        messenger.showSnackBar(const SnackBar(
            content: Text('Couldn’t reach your lights. Check the connection.')));
        break;
    }
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.onTap});
  final SmartPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NexGenPalette.matteBlack,
                shape: BoxShape.circle,
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Icon(preset.icon, color: NexGenPalette.cyan, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(preset.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _MiniSwatch(color: preset.baseSwatch),
            const SizedBox(width: 4),
            _MiniSwatch(color: preset.accentSwatch),
            const Icon(Icons.chevron_right, color: NexGenPalette.textMedium),
          ],
        ),
      ),
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow(
      {required this.label, required this.selected, required this.onPick});
  final String label;
  final List<int> selected;
  final void Function(List<int>) onPick;

  bool _matches(List<int> a, List<int> b) =>
      a.length == b.length &&
      a[0] == b[0] &&
      a[1] == b[1] &&
      a[2] == b[2] &&
      a[3] == b[3];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: NexGenPalette.textMedium)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in kSmartPresetPalette)
              GestureDetector(
                onTap: () => onPick(p.rgbw),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, p.rgbw[0], p.rgbw[1], p.rgbw[2]),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _matches(p.rgbw, selected)
                          ? NexGenPalette.cyan
                          : NexGenPalette.line,
                      width: _matches(p.rgbw, selected) ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MiniSwatch extends StatelessWidget {
  const _MiniSwatch({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: NexGenPalette.line),
      ),
    );
  }
}

class _NoMapCard extends StatelessWidget {
  const _NoMapCard();
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.rooflineEditor),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: NexGenPalette.cyan),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Map your roofline to unlock corner & peak accents',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const Icon(Icons.chevron_right, color: NexGenPalette.textMedium),
          ],
        ),
      ),
    );
  }
}
