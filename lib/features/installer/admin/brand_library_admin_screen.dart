import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';

/// Industry filter chips. Display label → snake_case key the seed
/// script and the Brand Setup industry dropdown both use. "All" is
/// modeled as null so the filter passthrough is dead-simple.
const _kIndustryFilters = <(String, String?)>[
  ('All', null),
  ('Restaurant', 'restaurant'),
  ('Insurance', 'insurance'),
  ('Retail', 'retail'),
  ('Banking', 'bank'),
  ('Real Estate', 'realestate'),
  ('Auto', 'auto'),
  ('Healthcare', 'healthcare'),
  ('Fitness', 'fitness'),
  ('Hotels', 'hotel'),
  ('Salons', 'salon'),
];

/// Corporate-admin brand library management screen (Part 9B).
///
/// Lists every /brand_library entry with a search box, an industry
/// filter row, and per-row edit. "+ Add Brand" pushes BrandSetupScreen
/// in `createNew + isAdmin` mode.
///
/// In-screen admin gate uses [isUserRoleAdminProvider] (same predicate
/// the firestore rules enforce on /brand_library writes). The gate is
/// a UX guard — the rules are the security boundary.
class BrandLibraryAdminScreen extends ConsumerStatefulWidget {
  const BrandLibraryAdminScreen({super.key});

  @override
  ConsumerState<BrandLibraryAdminScreen> createState() =>
      _BrandLibraryAdminScreenState();
}

class _BrandLibraryAdminScreenState
    extends ConsumerState<BrandLibraryAdminScreen> {
  final _searchCtrl = TextEditingController();
  bool _searchVisible = false;
  String _query = '';
  String? _industryFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  void _editBrand(BrandLibraryEntry brand) {
    context.push(
      AppRoutes.commercialBrandSetup,
      extra: {
        'preSelected': brand,
        'isEditing': true,
        'isAdmin': true,
      },
    );
  }

  void _addBrand() {
    context.push(
      AppRoutes.commercialBrandSetup,
      extra: {
        'isEditing': false,
        'isAdmin': true,
        'createNew': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminCheck = ref.watch(isUserRoleAdminProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Brand Library'),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
        actions: [
          IconButton(
            tooltip: _searchVisible ? 'Hide search' : 'Search',
            icon: Icon(_searchVisible ? Icons.search_off : Icons.search,
                color: NexGenPalette.textHigh),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: 'Add brand',
            icon: const Icon(Icons.add, color: NexGenPalette.cyan),
            onPressed: _addBrand,
          ),
        ],
      ),
      body: adminCheck.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => _UnauthorizedView(
            message: 'Failed to verify admin role: $e'),
        data: (isAdmin) {
          if (!isAdmin) {
            return const _UnauthorizedView(
              message: 'This screen is restricted to corporate '
                  'brand-library administrators.',
            );
          }
          return _buildBody();
        },
      ),
    );
  }

  Widget _buildBody() {
    final brandsAsync = ref.watch(allBrandsProvider);
    return Column(
      children: [
        if (_searchVisible) _buildSearchBar(),
        _buildIndustryFilterRow(),
        Expanded(
          child: brandsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: NexGenPalette.cyan)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load brand library: $e',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
            data: (all) {
              final filtered = _applyFilters(all);
              if (filtered.isEmpty) {
                return _buildEmpty(all.length);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _BrandRow(
                  brand: filtered[i],
                  onEdit: () => _editBrand(filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: const TextStyle(color: NexGenPalette.textHigh),
        decoration: InputDecoration(
          hintText: 'Search by company name…',
          hintStyle: const TextStyle(color: NexGenPalette.textMedium),
          prefixIcon:
              const Icon(Icons.search, color: NexGenPalette.textMedium),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close,
                      color: NexGenPalette.textMedium),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
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
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
    );
  }

  Widget _buildIndustryFilterRow() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _kIndustryFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (label, key) = _kIndustryFilters[i];
          final selected = _industryFilter == key;
          return Center(
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              selectedColor: NexGenPalette.cyan.withValues(alpha: 0.2),
              backgroundColor: NexGenPalette.gunmetal,
              labelStyle: TextStyle(
                color: selected
                    ? NexGenPalette.cyan
                    : NexGenPalette.textMedium,
                fontSize: 12,
              ),
              side: BorderSide(
                color: selected ? NexGenPalette.cyan : NexGenPalette.line,
              ),
              onSelected: (_) =>
                  setState(() => _industryFilter = key),
            ),
          );
        },
      ),
    );
  }

  List<BrandLibraryEntry> _applyFilters(List<BrandLibraryEntry> all) {
    var list = all;
    if (_industryFilter != null) {
      list = list
          .where((b) => b.industry == _industryFilter)
          .toList(growable: false);
    }
    if (_query.isNotEmpty) {
      list = list
          .where((b) => b.companyName.toLowerCase().contains(_query))
          .toList(growable: false);
    }
    return list;
  }

  Widget _buildEmpty(int totalCount) {
    final filtersActive = _industryFilter != null || _query.isNotEmpty;
    final message = filtersActive
        ? 'No brands match your filters.'
        : (totalCount == 0
            ? 'The brand library is empty. Tap + to add the first entry.'
            : 'No brands to show.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.palette_outlined,
                size: 56, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// ─── Single brand row ─────────────────────────────────────────────────────

class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.brand, required this.onEdit});
  final BrandLibraryEntry brand;
  final VoidCallback onEdit;

  String _verifiedLabel() {
    switch (brand.verifiedBy) {
      case 'nex-gen-manual':
        return 'Verified by Nex-Gen';
      case 'brandfetch-claimed':
        return 'Verified by Brandfetch';
      default:
        return 'Source: ${brand.verifiedBy}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(brand.companyName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (brand.industry.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              NexGenPalette.cyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: NexGenPalette.cyan
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          brand.industry,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: NexGenPalette.cyan),
                        ),
                      ),
                    const SizedBox(width: 8),
                    ...brand.colors.take(4).map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: c.toColor(),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: NexGenPalette.line, width: 1),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.verified,
                        size: 12, color: NexGenPalette.cyan),
                    const SizedBox(width: 4),
                    Text(_verifiedLabel(),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                if (brand.correctionCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              NexGenPalette.amber.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${brand.correctionCount} corrections applied',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: NexGenPalette.amber),
                    ),
                  ),
                ],
                if (brand.customDesigns.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              NexGenPalette.cyan.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${brand.customDesigns.length} custom design${brand.customDesigns.length == 1 ? '' : 's'}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: NexGenPalette.cyan),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: NexGenPalette.cyan, size: 20),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

// ─── Unauthorized view ─────────────────────────────────────────────────────

class _UnauthorizedView extends StatelessWidget {
  const _UnauthorizedView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 56, color: NexGenPalette.amber),
            const SizedBox(height: 16),
            Text('Not authorized',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
