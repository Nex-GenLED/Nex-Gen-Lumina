import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

class BrandIdentityScreen extends ConsumerStatefulWidget {
  const BrandIdentityScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<BrandIdentityScreen> createState() =>
      _BrandIdentityScreenState();
}

class _BrandIdentityScreenState extends ConsumerState<BrandIdentityScreen> {
  void _addColor() {
    final draft = ref.read(commercialOnboardingProvider);
    if (draft.brandColors.length >= 8) return;
    final newColor = BrandColor(
      id: 'bc_${DateTime.now().millisecondsSinceEpoch}',
      colorName: '',
      hexCode: 'FFFFFF',
      roleTag: 'primary',
    );
    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(brandColors: [...d.brandColors, newColor]),
        );
  }

  void _removeColor(int index) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<BrandColor>.from(d.brandColors)..removeAt(index);
      return d.copyWith(brandColors: list);
    });
  }

  void _updateColor(int index, BrandColor updated) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<BrandColor>.from(d.brandColors);
      list[index] = updated;
      return d.copyWith(brandColors: list);
    });
  }

  void _skip() => widget.onNext();

  void _validate() {
    final draft = ref.read(commercialOnboardingProvider);
    if (draft.brandColors.isNotEmpty) {
      final hasName = draft.brandColors.every((c) => c.colorName.trim().isNotEmpty);
      if (!hasName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please name all colors before continuing.'),
            backgroundColor: NexGenPalette.gunmetal,
          ),
        );
        return;
      }
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);
    final colors = draft.brandColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Brand Colors',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: NexGenPalette.textHigh),
        ),
        const SizedBox(height: 4),
        Text(
          'Add your brand colors to personalise lighting designs.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: NexGenPalette.textMedium),
        ),
        const SizedBox(height: 16),

        // ── Color entries ────────────────────────────────────────────────
        ...colors.asMap().entries.map((e) => _ColorEntry(
              index: e.key,
              color: e.value,
              onUpdate: (c) => _updateColor(e.key, c),
              onRemove: () => _removeColor(e.key),
            )),

        if (colors.length < 8)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _addColor,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Color'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.cyan,
                side: const BorderSide(color: NexGenPalette.cyan),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

        const SizedBox(height: 20),

        // ── Apply to Defaults toggle ────────────────────────────────────
        if (colors.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: draft.applyBrandToDefaults,
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
            thumbColor: WidgetStatePropertyAll(NexGenPalette.cyan),
            onChanged: (v) => ref
                .read(commercialOnboardingProvider.notifier)
                .update((d) => d.copyWith(applyBrandToDefaults: v)),
            title: Text(
              'Use these colors in design suggestions and autopilot',
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 14,
              ),
            ),
          ),

        const SizedBox(height: 24),

        // ── Next button ─────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _validate,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),

        // ── Skip option ─────────────────────────────────────────────────
        Center(
          child: TextButton(
            onPressed: _skip,
            child: Text(
              'I\u2019ll add brand colors later',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Single color entry row
// ---------------------------------------------------------------------------

class _ColorEntry extends StatefulWidget {
  const _ColorEntry({
    required this.index,
    required this.color,
    required this.onUpdate,
    required this.onRemove,
  });
  final int index;
  final BrandColor color;
  final ValueChanged<BrandColor> onUpdate;
  final VoidCallback onRemove;

  @override
  State<_ColorEntry> createState() => _ColorEntryState();
}

class _ColorEntryState extends State<_ColorEntry> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.color.colorName);
    _hexCtrl = TextEditingController(text: widget.color.hexCode);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final v = int.tryParse('FF$cleaned', radix: 16);
      if (v != null) return Color(v);
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final swatch = _parseHex(_hexCtrl.text);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: name + hex + swatch + delete
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(
                      color: NexGenPalette.textHigh, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Color Name',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium),
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: (v) =>
                      widget.onUpdate(widget.color.copyWith(colorName: v)),
                ),
              ),
              const SizedBox(width: 8),
              Text('#',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 14)),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _hexCtrl,
                  style: const TextStyle(
                      color: NexGenPalette.textHigh, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'FFFFFF',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium),
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    setState(() {});
                    widget.onUpdate(
                        widget.color.copyWith(hexCode: v.replaceAll('#', '')));
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Live swatch
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.line),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemove,
                child: const Icon(Icons.close, size: 18, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Role tag chips
          Wrap(
            spacing: 8,
            children: ['Primary', 'Secondary', 'Accent'].map((tag) {
              final isActive =
                  widget.color.roleTag.toLowerCase() == tag.toLowerCase();
              return ChoiceChip(
                label: Text(tag, style: const TextStyle(fontSize: 12)),
                selected: isActive,
                selectedColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                backgroundColor: NexGenPalette.gunmetal,
                labelStyle: TextStyle(
                  color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium,
                ),
                side: BorderSide(
                  color: isActive ? NexGenPalette.cyan : NexGenPalette.line,
                ),
                onSelected: (_) => widget.onUpdate(
                  widget.color.copyWith(roleTag: tag.toLowerCase()),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
