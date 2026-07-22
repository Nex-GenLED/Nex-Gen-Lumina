import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';

class BrandIdentityScreen extends ConsumerStatefulWidget {
  const BrandIdentityScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<BrandIdentityScreen> createState() =>
      _BrandIdentityScreenState();
}

class _BrandIdentityScreenState extends ConsumerState<BrandIdentityScreen> {
  // ── Brand library search state ───────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  String _activeQuery = '';

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _activeQuery = value.trim());
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _activeQuery = '');
  }

  /// Pre-fills the wizard's brand colors from a [BrandLibraryEntry].
  /// Replaces existing entries — the customer can then customize them
  /// and (per the existing modify-detection in BrandSetupScreen) submit
  /// a correction back to corporate.
  ///
  /// Maps each library color (BrandColor with snake_case fields) to a
  /// new BrandColor with a fresh local id so the Step-2 row keys stay
  /// stable across rebuilds.
  void _applyBrandLibraryEntry(BrandLibraryEntry brand) {
    final mapped = brand.colors
        .asMap()
        .entries
        .map((e) => BrandColor(
              id: 'bc_${brand.brandId}_${e.key}_'
                  '${DateTime.now().microsecondsSinceEpoch}',
              colorName: e.value.colorName,
              hexCode: e.value.hexCode,
              roleTag: e.value.roleTag,
              activeInEngine: true,
            ))
        .toList(growable: false);

    ref.read(commercialOnboardingProvider.notifier).update((d) => d.copyWith(
          brandColors: mapped,
          brandLibraryId: brand.brandId,
        ));

    // Dismiss the search results.
    _searchCtrl.clear();
    setState(() => _activeQuery = '');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Brand colors loaded from ${brand.companyName}.'),
        backgroundColor: NexGenPalette.cyan,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Existing color-row helpers ───────────────────────────────────────────
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
      // Manual edit clears the library tie-back so saved profile reads
      // as a manually-curated brand. The customer can re-search to
      // re-attach.
      return d.copyWith(brandColors: list, clearBrandLibraryId: true);
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
      final hasName =
          draft.brandColors.every((c) => c.colorName.trim().isNotEmpty);
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

        // ── Brand library search section ──────────────────────────────────
        _BrandLibrarySearchCard(
          controller: _searchCtrl,
          query: _activeQuery,
          onChanged: _onSearchChanged,
          onClear: _clearSearch,
          onSelect: _applyBrandLibraryEntry,
        ),

        // ── Library tie-back chip ─────────────────────────────────────────
        if (draft.brandLibraryId != null) ...[
          const SizedBox(height: 12),
          _LibraryTieBackChip(brandLibraryId: draft.brandLibraryId!),
        ],

        const SizedBox(height: 20),

        // ── Manual color entries header ──────────────────────────────────
        if (colors.isNotEmpty) ...[
          Text(
            'Your colors',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: NexGenPalette.textHigh),
          ),
          const SizedBox(height: 8),
        ],

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
              'I’ll add brand colors later',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Brand library search card (Path 1, Part 8)
// ---------------------------------------------------------------------------

class _BrandLibrarySearchCard extends ConsumerWidget {
  const _BrandLibrarySearchCard({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    required this.onSelect,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<BrandLibraryEntry> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasQuery = query.isNotEmpty;
    final results = hasQuery
        ? ref.watch(brandSearchProvider(query))
        : const AsyncValue<List<BrandLibraryEntry>>.data([]);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: NexGenPalette.cyan, size: 18),
              const SizedBox(width: 8),
              Text(
                'Find Your Brand',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Search our brand library to auto-fill your brand colors. '
            'You can still customize after.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            style: const TextStyle(color: NexGenPalette.textHigh),
            decoration: InputDecoration(
              hintText: 'Search company name…',
              hintStyle: const TextStyle(color: NexGenPalette.textMedium),
              prefixIcon:
                  const Icon(Icons.search, color: NexGenPalette.textMedium),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.close,
                          color: NexGenPalette.textMedium),
                      onPressed: onClear,
                    )
                  : null,
              filled: true,
              fillColor: NexGenPalette.gunmetal,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: NexGenPalette.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: NexGenPalette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: NexGenPalette.cyan, width: 1.5),
              ),
            ),
            onChanged: onChanged,
          ),
          if (!hasQuery)
            const SizedBox.shrink()
          else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: results.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: NexGenPalette.cyan),
                    ),
                  ),
                ),
                error: (e, _) => Text('Search failed: $e',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.redAccent)),
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No brands found for "$query".',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  return Column(
                    children: list
                        .map((b) => _BrandResultTile(
                              brand: b,
                              onTap: () => onSelect(b),
                            ))
                        .toList(growable: false),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandResultTile extends StatelessWidget {
  const _BrandResultTile({required this.brand, required this.onTap});
  final BrandLibraryEntry brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: brand.colors
                    .take(3)
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: c.toColor(),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: NexGenPalette.line, width: 1),
                            ),
                          ),
                        ))
                    .toList(growable: false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.companyName,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: NexGenPalette.textHigh),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (brand.industry.isNotEmpty)
                      Text(
                        brand.industry,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: NexGenPalette.textMedium, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryTieBackChip extends StatelessWidget {
  const _LibraryTieBackChip({required this.brandLibraryId});
  final String brandLibraryId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_outlined,
              size: 14, color: NexGenPalette.cyan),
          const SizedBox(width: 6),
          Text(
            'Loaded from brand library · $brandLibraryId',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: NexGenPalette.cyan),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single color entry row (unchanged from pre-Part-8)
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
  void didUpdateWidget(covariant _ColorEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external updates (e.g. after _applyBrandLibraryEntry replaces
    // the draft) into the local controllers.
    if (oldWidget.color.colorName != widget.color.colorName &&
        _nameCtrl.text != widget.color.colorName) {
      _nameCtrl.text = widget.color.colorName;
    }
    if (oldWidget.color.hexCode != widget.color.hexCode &&
        _hexCtrl.text != widget.color.hexCode) {
      _hexCtrl.text = widget.color.hexCode;
    }
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
