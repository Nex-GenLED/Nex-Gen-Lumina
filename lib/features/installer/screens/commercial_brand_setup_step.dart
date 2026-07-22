import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';

/// Installer-side commercial brand pre-seed step (Part 8, Path 2).
///
/// Lets the installer search the /brand_library and tentatively pick
/// the customer's brand. The selection is stored in
/// [installerSelectedBrandLibraryEntryProvider] — the actual Firestore
/// writes (brand_profile subcollection + favorites generation) happen
/// later in InstallerSetupWizard._completeSetup once the customer's
/// auth uid is created. That deferral is intentional: during this step
/// the customer doesn't have a uid yet, and brand_profile rules
/// require writing under the *customer's* /users/{uid}/...
///
/// Skipping is always allowed — the customer can run brand setup
/// themselves from the Brand tab on first sign-in.
class CommercialBrandSetupStep extends ConsumerStatefulWidget {
  const CommercialBrandSetupStep({
    super.key,
    required this.onComplete,
    required this.onSkip,
  });

  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  ConsumerState<CommercialBrandSetupStep> createState() =>
      _CommercialBrandSetupStepState();
}

class _CommercialBrandSetupStepState
    extends ConsumerState<CommercialBrandSetupStep> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    // Pre-fill the search box with the customer's company-name guess
    // (if any) — but only on first build, not on each setState. Reads
    // installerCustomerInfoProvider once to seed.
    final customerInfo = ref.read(installerCustomerInfoProvider);
    if (customerInfo.name.trim().isNotEmpty) {
      _searchCtrl.text = customerInfo.name.trim();
      _activeQuery = customerInfo.name.trim();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _activeQuery = v.trim());
    });
  }

  void _clearSelection() {
    ref.read(installerSelectedBrandLibraryEntryProvider.notifier).state =
        null;
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        ref.watch(installerSelectedBrandLibraryEntryProvider);
    final hasSelection = selected != null;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        children: [
          Text(
            'Set Up Brand Profile',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: NexGenPalette.textHigh),
          ),
          const SizedBox(height: 6),
          Text(
            'Optional — search the brand library to pre-seed lighting '
            'designs that match the customer\'s brand. The business '
            'owner can configure this later from the app.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (!hasSelection)
            _BrandSearchSection(
              controller: _searchCtrl,
              query: _activeQuery,
              onChanged: _onSearchChanged,
              onClear: () {
                _searchCtrl.clear();
                setState(() => _activeQuery = '');
              },
              onSelect: (brand) {
                ref
                    .read(installerSelectedBrandLibraryEntryProvider
                        .notifier)
                    .state = brand;
                _searchCtrl.clear();
                setState(() => _activeQuery = '');
              },
            )
          else
            _SelectedBrandPreview(
              brand: selected,
              onClear: _clearSelection,
            ),
          const SizedBox(height: 20),
          if (hasSelection)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: widget.onComplete,
                icon: const Icon(Icons.check),
                label: const Text('Confirm & Continue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                _clearSelection();
                widget.onSkip();
              },
              child: Text(
                'Skip for Now',
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Search section ────────────────────────────────────────────────────────

class _BrandSearchSection extends ConsumerWidget {
  const _BrandSearchSection({
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
                'Find the customer\'s brand',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
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

// ─── Selected brand preview ────────────────────────────────────────────────

class _SelectedBrandPreview extends StatelessWidget {
  const _SelectedBrandPreview({
    required this.brand,
    required this.onClear,
  });
  final BrandLibraryEntry brand;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: NexGenPalette.cyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified,
                  color: NexGenPalette.cyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(brand.companyName,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: NexGenPalette.textMedium, size: 18),
                onPressed: onClear,
                tooltip: 'Pick a different brand',
              ),
            ],
          ),
          if (brand.industry.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(brand.industry,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: brand.colors
                .map((c) => Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.toColor(),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: NexGenPalette.line, width: 1),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 60,
                          child: Text(
                            c.colorName.isNotEmpty
                                ? c.colorName
                                : c.roleTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ))
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: NexGenPalette.cyan.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: NexGenPalette.cyan, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Five brand-aligned lighting designs will be auto-'
                    'generated for the customer when handoff completes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
