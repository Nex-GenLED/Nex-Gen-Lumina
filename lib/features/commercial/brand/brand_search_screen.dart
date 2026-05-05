import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';

/// "Find Brand" search screen. Searches the global /brand_library by
/// arrayContains against the seeded `search_terms` field via
/// [brandSearchProvider].
///
/// Tapping a result selects it into [selectedBrandProvider] and navigates
/// to the BrandSetupScreen pre-populated with the entry's colors and
/// signature. Tapping the "Create Brand Profile" button on the empty
/// state navigates to BrandSetupScreen with no pre-selection so the
/// installer/customer can enter colors manually.
class BrandSearchScreen extends ConsumerStatefulWidget {
  const BrandSearchScreen({super.key});

  @override
  ConsumerState<BrandSearchScreen> createState() => _BrandSearchScreenState();
}

class _BrandSearchScreenState extends ConsumerState<BrandSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounceTimer;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _activeQuery = _controller.text.trim();
      });
    });
  }

  void _clear() {
    _controller.clear();
    setState(() => _activeQuery = '');
    _focusNode.requestFocus();
  }

  void _selectBrand(BrandLibraryEntry brand) {
    ref.read(selectedBrandProvider.notifier).state = brand;
    context.push(AppRoutes.commercialBrandSetup, extra: brand);
  }

  void _createManually() {
    ref.read(selectedBrandProvider.notifier).state = null;
    context.push(AppRoutes.commercialBrandSetup);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _activeQuery.isNotEmpty;
    final results = hasQuery
        ? ref.watch(brandSearchProvider(_activeQuery))
        : const AsyncValue<List<BrandLibraryEntry>>.data([]);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Find Brand'),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: !hasQuery
                ? _buildInitialState()
                : results.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: NexGenPalette.cyan),
                    ),
                    error: (e, _) => _buildErrorState(e),
                    data: (list) => list.isEmpty
                        ? _buildNoResultsState()
                        : _buildResultsList(list),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Search bar ──────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final hasText = _controller.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        style: const TextStyle(color: NexGenPalette.textHigh),
        decoration: InputDecoration(
          hintText: 'Search brands (e.g. State Farm, McDonald\'s)',
          hintStyle: const TextStyle(color: NexGenPalette.textMedium),
          prefixIcon:
              const Icon(Icons.search, color: NexGenPalette.textMedium),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close,
                      color: NexGenPalette.textMedium),
                  onPressed: _clear,
                )
              : null,
          filled: true,
          fillColor: NexGenPalette.gunmetal,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: NexGenPalette.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: NexGenPalette.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: NexGenPalette.cyan, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ─── States ──────────────────────────────────────────────────────────────

  Widget _buildInitialState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search,
                size: 56, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(
              'Search the brand library',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Find verified colors for thousands of '
              'brands. Start typing the company name above.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off,
                size: 48, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(
              'No brands found for "$_activeQuery"',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Is this a new company? Enter their brand '
              'information manually.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_business),
              label: const Text('Create Brand Profile'),
              onPressed: _createManually,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: NexGenPalette.amber),
            const SizedBox(height: 16),
            Text(
              'Search failed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Results list ────────────────────────────────────────────────────────

  Widget _buildResultsList(List<BrandLibraryEntry> brands) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: brands.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BrandResultCard(
        brand: brands[i],
        onTap: () => _selectBrand(brands[i]),
      ),
    );
  }
}

// ─── Result card ───────────────────────────────────────────────────────────

class _BrandResultCard extends StatelessWidget {
  const _BrandResultCard({required this.brand, required this.onTap});

  final BrandLibraryEntry brand;
  final VoidCallback onTap;

  bool get _isVerified =>
      brand.verifiedBy == 'nex-gen-manual' ||
      brand.verifiedBy == 'brandfetch-claimed';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            brand.companyName,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              size: 16, color: NexGenPalette.cyan),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (brand.industry.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: NexGenPalette.cyan
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    NexGenPalette.cyan.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              brand.industry,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: NexGenPalette.cyan),
                            ),
                          ),
                        const SizedBox(width: 10),
                        ..._buildColorDots(brand),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: NexGenPalette.textMedium),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildColorDots(BrandLibraryEntry brand) {
    final dots = <Widget>[];
    for (final c in brand.colors.take(4)) {
      dots.add(Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: c.toColor(),
          shape: BoxShape.circle,
          border: Border.all(color: NexGenPalette.line, width: 1),
        ),
      ));
    }
    return dots;
  }
}
