import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/product_catalog_item.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CatalogManagementScreen
//
// Tyler's corporate-side product-catalog editor. Reads
// allProductsIncludingInactive so deactivated SKUs are reachable
// for re-activation; writes go through ProductCatalogNotifier
// (lib/services/inventory/product_catalog_providers.dart).
//
// Surfaces:
//   • Inline price edit — tap any price to open a small dialog.
//   • Bulk price update — set every active SKU in a category to one
//     price, single Firestore batch.
//   • Active toggle  — flips is_active without removing the doc, so
//     historical orders still resolve names/pack info.
//   • Add Product    — full-screen form that creates a new doc at
//     /product_catalog/{sku}. SKU id is immutable post-create.
//
// Auth: gated at the rule layer (isUserRoleAdmin or
// hasAdminOrOwnerClaim). Reachable from the corporate Admin tab
// alongside the Brand Library entry.
// ─────────────────────────────────────────────────────────────────────────────

class CatalogManagementScreen extends ConsumerStatefulWidget {
  const CatalogManagementScreen({super.key});

  @override
  ConsumerState<CatalogManagementScreen> createState() =>
      _CatalogManagementScreenState();
}

class _CatalogManagementScreenState
    extends ConsumerState<CatalogManagementScreen> {
  final _searchCtl = TextEditingController();
  String _query = '';
  String _category = 'all';
  bool _showInactive = false;

  static const _categories = <(String, String)>[
    ('all', 'All'),
    ('lights', 'Lights'),
    ('rails', 'Rails'),
    ('specialty', 'Specialty'),
    ('power', 'Power'),
    ('wire', 'Wire'),
    ('accessories', 'Accessories'),
    ('controllers', 'Controllers'),
  ];

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(allProductsIncludingInactiveProvider);
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Product Catalog',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => const _AddProductScreen(),
            )),
            icon: const Icon(Icons.add, color: NexGenPalette.cyan),
            label: const Text(
              'Add',
              style: TextStyle(
                color: NexGenPalette.cyan,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
        error: (e, _) => _err('Catalog load failed: $e'),
        data: (allProducts) {
          final filtered = _filter(allProducts);
          final canBulk = _category != 'all' && filtered.isNotEmpty;
          return Column(
            children: [
              _Header(
                searchCtl: _searchCtl,
                query: _query,
                onQueryChanged: (v) => setState(() => _query = v),
                category: _category,
                onCategoryChanged: (v) => setState(() => _category = v),
                categories: _categories,
                showInactive: _showInactive,
                onShowInactiveChanged: (v) =>
                    setState(() => _showInactive = v),
                canBulk: canBulk,
                onBulkPressed: () => _openBulkUpdate(filtered),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) =>
                            _ProductCard(product: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _err(String m) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            m,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_outlined,
                  size: 48, color: NexGenPalette.textMedium),
              const SizedBox(height: 12),
              Text(
                _query.isNotEmpty
                    ? 'No products match "$_query".'
                    : (!_showInactive
                        ? 'No active products in this category.'
                        : 'No products in this category.'),
                style:
                    TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  // ── Filtering ──────────────────────────────────────────────────────

  List<ProductCatalogItem> _filter(List<ProductCatalogItem> all) {
    return all.where((p) {
      if (!_showInactive && !p.isActive) return false;
      if (_category != 'all' && p.category != _category) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).toList();
  }

  // ── Bulk update ────────────────────────────────────────────────────

  Future<void> _openBulkUpdate(List<ProductCatalogItem> visible) async {
    final activeInCategory = visible.where((p) => p.isActive).toList();
    if (activeInCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active SKUs in this category to update.'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      return;
    }
    final ctl = TextEditingController();
    final newPrice = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: Text(
          'Update all ${_categoryLabel(_category)} prices',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'New price for all ${_categoryLabel(_category)} items',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
                prefixText: '\$',
                prefixStyle: const TextStyle(color: Colors.white),
                filled: true,
                fillColor: NexGenPalette.gunmetal90,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This will update ${activeInCategory.length} active SKUs.',
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctl.text.trim());
              if (v == null || v < 0) return;
              Navigator.of(ctx).pop(v);
            },
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: NexGenPalette.matteBlack,
            ),
            child: const Text('Update All'),
          ),
        ],
      ),
    );
    if (newPrice == null || !mounted) return;
    try {
      final updated = await ref
          .read(productCatalogNotifierProvider)
          .bulkUpdateCategoryPrice(
              category: _category, unitPrice: newPrice);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Updated $updated SKU${updated == 1 ? '' : 's'} to \$${newPrice.toStringAsFixed(2)}'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bulk update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

String _categoryLabel(String value) {
  switch (value) {
    case 'lights':
      return 'Lights';
    case 'rails':
      return 'Rails';
    case 'specialty':
      return 'Specialty';
    case 'power':
      return 'Power';
    case 'wire':
      return 'Wire';
    case 'accessories':
      return 'Accessories';
    case 'controllers':
      return 'Controllers';
  }
  return value;
}

// ═══════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.searchCtl,
    required this.query,
    required this.onQueryChanged,
    required this.category,
    required this.onCategoryChanged,
    required this.categories,
    required this.showInactive,
    required this.onShowInactiveChanged,
    required this.canBulk,
    required this.onBulkPressed,
  });
  final TextEditingController searchCtl;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final List<(String, String)> categories;
  final bool showInactive;
  final ValueChanged<bool> onShowInactiveChanged;
  final bool canBulk;
  final VoidCallback onBulkPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        children: [
          TextField(
            controller: searchCtl,
            onChanged: onQueryChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by name or SKU',
              hintStyle: TextStyle(color: NexGenPalette.textMedium),
              prefixIcon:
                  Icon(Icons.search, color: NexGenPalette.textMedium),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.clear,
                          color: NexGenPalette.textMedium),
                      onPressed: () {
                        searchCtl.clear();
                        onQueryChanged('');
                      },
                    ),
              filled: true,
              fillColor: NexGenPalette.gunmetal90,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in categories) ...[
                  InkWell(
                    onTap: () => onCategoryChanged(c.$1),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: category == c.$1
                            ? NexGenPalette.cyan
                            : NexGenPalette.gunmetal90,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: category == c.$1
                              ? NexGenPalette.cyan
                              : NexGenPalette.line,
                        ),
                      ),
                      child: Text(
                        c.$2,
                        style: TextStyle(
                          color: category == c.$1
                              ? NexGenPalette.matteBlack
                              : NexGenPalette.textHigh,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: showInactive,
                onChanged: onShowInactiveChanged,
                activeThumbColor: NexGenPalette.amber,
              ),
              Text(
                'Show inactive',
                style:
                    TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
              ),
              const Spacer(),
              if (canBulk)
                TextButton.icon(
                  onPressed: onBulkPressed,
                  icon: const Icon(Icons.price_change_outlined, size: 16),
                  label: Text(
                    'Update All ${_categoryLabel(category)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRODUCT CARD
// ═══════════════════════════════════════════════════════════════════════

class _ProductCard extends ConsumerStatefulWidget {
  const _ProductCard({required this.product});
  final ProductCatalogItem product;

  @override
  ConsumerState<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<_ProductCard> {
  bool _busy = false;

  Future<void> _editPrice() async {
    final ctl = TextEditingController(
      text: widget.product.unitPrice > 0
          ? widget.product.unitPrice.toStringAsFixed(2)
          : '',
    );
    final newPrice = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: Text(
          widget.product.name,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SKU ${widget.product.sku}',
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Unit price',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
                prefixText: '\$',
                prefixStyle: const TextStyle(color: Colors.white),
                suffix: const Text(' per unit',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12)),
                filled: true,
                fillColor: NexGenPalette.gunmetal90,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctl.text.trim());
              if (v == null || v < 0) return;
              Navigator.of(ctx).pop(v);
            },
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: NexGenPalette.matteBlack,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newPrice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(productCatalogNotifierProvider).updateUnitPrice(
            sku: widget.product.sku,
            unitPrice: newPrice,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(bool next) async {
    setState(() => _busy = true);
    try {
      await ref.read(productCatalogNotifierProvider).setActive(
            sku: widget.product.sku,
            isActive: next,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Toggle failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: p.isActive
              ? NexGenPalette.line
              : NexGenPalette.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      p.sku,
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (!p.isActive)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: NexGenPalette.amber.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'INACTIVE',
                    style: TextStyle(
                      color: NexGenPalette.amber,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Switch(
                value: p.isActive,
                onChanged: _busy ? null : _toggleActive,
                activeThumbColor: NexGenPalette.cyan,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Badge(label: p.category, color: NexGenPalette.violet),
              _Badge(
                label: '${p.packQty} per ${p.packUnit}',
                color: NexGenPalette.textMedium,
              ),
              if (p.voltage != null)
                _Badge(label: p.voltage!, color: NexGenPalette.cyan),
              if (p.finish != null)
                _Badge(
                    label: p.finish!, color: NexGenPalette.textMedium),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _busy ? null : _editPrice,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: NexGenPalette.cyan, size: 14),
                  const SizedBox(width: 8),
                  if (p.unitPrice <= 0)
                    Text(
                      'Set Price',
                      style: TextStyle(
                        color: NexGenPalette.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    Text(
                      '\$${p.unitPrice.toStringAsFixed(2)} per unit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  const Spacer(),
                  Text(
                    'Tap to edit',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ADD PRODUCT SCREEN
// ═══════════════════════════════════════════════════════════════════════

class _AddProductScreen extends ConsumerStatefulWidget {
  const _AddProductScreen();

  @override
  ConsumerState<_AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<_AddProductScreen> {
  final _skuCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _subcategoryCtl = TextEditingController();
  final _finishCtl = TextEditingController();
  final _packQtyCtl = TextEditingController(text: '1');
  final _unitPriceCtl = TextEditingController(text: '0.00');
  final _descriptionCtl = TextEditingController();
  final _goulyCtl = TextEditingController();

  String _category = 'lights';
  String? _voltage;
  String _packUnit = 'each';
  bool _voltageSpecific = false;
  bool _saving = false;

  static const _categories = [
    'lights', 'rails', 'specialty', 'power', 'wire', 'accessories', 'controllers'
  ];
  static const _voltages = ['24V', '36V'];
  static const _packUnits = ['each', 'bag', 'box', 'roll', 'pack'];

  @override
  void dispose() {
    _skuCtl.dispose();
    _nameCtl.dispose();
    _subcategoryCtl.dispose();
    _finishCtl.dispose();
    _packQtyCtl.dispose();
    _unitPriceCtl.dispose();
    _descriptionCtl.dispose();
    _goulyCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sku = _skuCtl.text.trim();
    final name = _nameCtl.text.trim();
    if (sku.isEmpty || name.isEmpty) {
      _err('SKU and Name are required.');
      return;
    }
    final packQty = int.tryParse(_packQtyCtl.text.trim()) ?? 0;
    if (packQty <= 0) {
      _err('Pack quantity must be > 0.');
      return;
    }
    final unitPrice = double.tryParse(_unitPriceCtl.text.trim()) ?? 0.0;
    if (unitPrice < 0) {
      _err('Unit price cannot be negative.');
      return;
    }

    final item = ProductCatalogItem(
      sku: sku,
      name: name,
      category: _category,
      subcategory: _subcategoryCtl.text.trim().isEmpty
          ? null
          : _subcategoryCtl.text.trim(),
      voltage: _voltage,
      finish: _finishCtl.text.trim().isEmpty ? null : _finishCtl.text.trim(),
      packQty: packQty,
      packUnit: _packUnit,
      unitPrice: unitPrice,
      isActive: true,
      voltageSpecific: _voltageSpecific,
      description: _descriptionCtl.text.trim(),
      goulyModel:
          _goulyCtl.text.trim().isEmpty ? null : _goulyCtl.text.trim(),
    );

    setState(() => _saving = true);
    try {
      await ref.read(productCatalogNotifierProvider).createProduct(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created $sku'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _err('Save failed: $e');
    }
  }

  void _err(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Add Product', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Field(
            label: 'SKU (immutable)',
            child: TextField(
              controller: _skuCtl,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              decoration: _dec(hintText: 'e.g. NGL-NEW-SKU-24V'),
              textCapitalization: TextCapitalization.characters,
            ),
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Name',
            child: TextField(
              controller: _nameCtl,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Category',
                  child: _Dropdown(
                    value: _category,
                    items: _categories,
                    onChanged: (v) => setState(() => _category = v ?? 'lights'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: 'Subcategory (optional)',
                  child: TextField(
                    controller: _subcategoryCtl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Voltage (optional)',
                  child: _Dropdown(
                    value: _voltage,
                    items: const [null, ..._voltages],
                    nullLabel: 'Universal',
                    onChanged: (v) => setState(() {
                      _voltage = v;
                      _voltageSpecific = v != null;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: 'Finish (optional)',
                  child: TextField(
                    controller: _finishCtl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Pack qty',
                  child: TextField(
                    controller: _packQtyCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: 'Pack unit',
                  child: _Dropdown(
                    value: _packUnit,
                    items: _packUnits,
                    onChanged: (v) => setState(() => _packUnit = v ?? 'each'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  label: 'Unit price (\$)',
                  child: TextField(
                    controller: _unitPriceCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec(prefixText: '\$'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Description',
            child: TextField(
              controller: _descriptionCtl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(),
            ),
          ),
          const SizedBox(height: 10),
          _Field(
            label: 'Gouly model (optional)',
            child: TextField(
              controller: _goulyCtl,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: NexGenPalette.matteBlack,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NexGenPalette.matteBlack,
                      ),
                    )
                  : const Text('Create Product',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.nullLabel,
  });
  final String? value;
  final List<String?> items;
  final ValueChanged<String?> onChanged;
  final String? nullLabel;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: DropdownButton<String?>(
        isExpanded: true,
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: NexGenPalette.gunmetal,
        iconEnabledColor: NexGenPalette.textMedium,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        items: [
          for (final item in items)
            DropdownMenuItem<String?>(
              value: item,
              child: Text(item ?? (nullLabel ?? '—')),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

InputDecoration _dec({String? hintText, String? prefixText}) {
  return InputDecoration(
    isDense: true,
    hintText: hintText,
    hintStyle: TextStyle(color: NexGenPalette.textMedium),
    prefixText: prefixText,
    prefixStyle: const TextStyle(color: Colors.white),
    filled: true,
    fillColor: NexGenPalette.gunmetal,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: NexGenPalette.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: NexGenPalette.line),
    ),
  );
}
