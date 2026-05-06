import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/models/inventory/dealer_inventory_item.dart';
import 'package:nexgen_command/services/inventory/dealer_inventory_providers.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DealerInventoryScreen
//
// 5-column SKU-level warehouse view for dealers. Reads from
// /dealers/{dealerCode}/sku_inventory (Part 1 schema) joined with
// /product_catalog for SKU display names. Distinct from the existing
// InventoryDashboardScreen in features/sales/screens — that one
// surfaces materialId-keyed Day-1/Day-2 install material data; this
// one is the SKU-level "what's on the shelf" view for the ordering
// pipeline.
//
// Reads:
//   • dealerInventoryProvider     — every sku_inventory doc
//   • neededItemsProvider          — drives the red banner
//   • lowStockItemsProvider        — drives the amber low-stock cards
//   • productBySkuProvider         — name resolution per row
//   • currentDealerCodeProvider    — falls back to staff-session
//                                     resolution if no override is given
// Writes: none — order edits go through the order screen (Part 5).
// ─────────────────────────────────────────────────────────────────────────────

class DealerInventoryScreen extends ConsumerStatefulWidget {
  /// Optional override; when null the screen resolves the active
  /// dealer from [currentDealerCodeProvider]. Mirrors the override-or-
  /// resolve pattern used by DealerDashboardScreen.
  final String? dealerCodeOverride;

  const DealerInventoryScreen({super.key, this.dealerCodeOverride});

  @override
  ConsumerState<DealerInventoryScreen> createState() =>
      _DealerInventoryScreenState();
}

class _DealerInventoryScreenState
    extends ConsumerState<DealerInventoryScreen> {
  String _category = 'all';
  String _voltage = 'all'; // all | 24V | 36V

  static const _categories = <_CategoryChip>[
    _CategoryChip('all', 'All'),
    _CategoryChip('lights', 'Lights'),
    _CategoryChip('rails', 'Rails'),
    _CategoryChip('specialty', 'Specialty'),
    _CategoryChip('power', 'Power'),
    _CategoryChip('wire', 'Wire'),
    _CategoryChip('accessories', 'Accessories'),
    _CategoryChip('controllers', 'Controllers'),
  ];

  /// Voltage filter only applies to categories that mix voltage SKUs.
  bool get _showsVoltageFilter =>
      _category == 'lights' ||
      _category == 'specialty' ||
      _category == 'power' ||
      _category == 'all';

  @override
  Widget build(BuildContext context) {
    final dealerCode =
        widget.dealerCodeOverride ?? ref.watch(currentDealerCodeProvider);

    if (dealerCode == null) {
      return _NoSession();
    }

    final inventoryAsync = ref.watch(dealerInventoryProvider(dealerCode));
    final neededItems = ref.watch(neededItemsProvider(dealerCode));
    final lowStockItems = ref.watch(lowStockItemsProvider(dealerCode));

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text(
          'Inventory',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Filters',
            icon: const Icon(Icons.tune),
            onPressed: _showFiltersSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/inventory/order'),
        backgroundColor: NexGenPalette.cyan,
        foregroundColor: NexGenPalette.matteBlack,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text(
          'Order More',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: inventoryAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
        error: (e, _) => _ErrorPanel(message: 'Failed to load inventory: $e'),
        data: (allItems) {
          if (allItems.isEmpty) return _EmptyState();
          final filtered = _applyFilters(allItems);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (neededItems.isNotEmpty)
                _NeededBanner(count: neededItems.length),
              if (neededItems.isNotEmpty) const SizedBox(height: 12),
              _CategoryRow(
                value: _category,
                onChanged: (v) => setState(() {
                  _category = v;
                  if (!_showsVoltageFilter) _voltage = 'all';
                }),
              ),
              if (_showsVoltageFilter) ...[
                const SizedBox(height: 8),
                _VoltageRow(
                  value: _voltage,
                  onChanged: (v) => setState(() => _voltage = v),
                ),
              ],
              const SizedBox(height: 16),
              _InventoryTable(items: filtered),
              if (lowStockItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionLabel('Low Stock Alerts'),
                const SizedBox(height: 8),
                ...lowStockItems.map((i) => _LowStockCard(item: i)),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Filtering ───────────────────────────────────────────────────────

  /// Applies category + voltage filters by joining each inventory row
  /// against the product catalog. Items whose SKU isn't in the active
  /// catalog (e.g. a deactivated SKU still in inventory) fall through
  /// to the "all" category and stay visible.
  List<DealerInventoryItem> _applyFilters(List<DealerInventoryItem> all) {
    if (_category == 'all' && _voltage == 'all') return all;
    return all.where((item) {
      final product = ref.read(productBySkuProvider(item.sku));
      if (product == null) {
        return _category == 'all' && _voltage == 'all';
      }
      if (_category != 'all' && product.category != _category) return false;
      if (_voltage != 'all' && product.voltage != _voltage) return false;
      return true;
    }).toList();
  }

  // ── Filter sheet ────────────────────────────────────────────────────

  void _showFiltersSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filters',
              style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                    color: NexGenPalette.textHigh,
                  ),
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Category'),
            const SizedBox(height: 8),
            _CategoryRow(
              value: _category,
              onChanged: (v) {
                setState(() {
                  _category = v;
                  if (!_showsVoltageFilter) _voltage = 'all';
                });
                Navigator.of(sheetCtx).pop();
              },
            ),
            if (_showsVoltageFilter) ...[
              const SizedBox(height: 16),
              const _SectionLabel('Voltage'),
              const SizedBox(height: 8),
              _VoltageRow(
                value: _voltage,
                onChanged: (v) {
                  setState(() => _voltage = v);
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CHIP ROWS
// ═══════════════════════════════════════════════════════════════════════

class _CategoryChip {
  final String value;
  final String label;
  const _CategoryChip(this.value, this.label);
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in _DealerInventoryScreenState._categories) ...[
            _Chip(
              label: c.label,
              selected: value == c.value,
              onTap: () => onChanged(c.value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _VoltageRow extends StatelessWidget {
  const _VoltageRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const choices = [
      ('all', 'Both'),
      ('24V', '24V'),
      ('36V', '36V'),
    ];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in choices) ...[
            _Chip(
              label: c.$2,
              selected: value == c.$1,
              onTap: () => onChanged(c.$1),
              compact: true,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? NexGenPalette.cyan : NexGenPalette.gunmetal90;
    final fg = selected ? NexGenPalette.matteBlack : NexGenPalette.textHigh;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NEEDED BANNER
// ═══════════════════════════════════════════════════════════════════════

class _NeededBanner extends StatelessWidget {
  const _NeededBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/inventory/order'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.red, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count item${count == 1 ? '' : 's'} needed for scheduled jobs',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/inventory/order'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text(
                  'Order Now',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INVENTORY TABLE
// ═══════════════════════════════════════════════════════════════════════

class _InventoryTable extends ConsumerWidget {
  const _InventoryTable({required this.items});
  final List<DealerInventoryItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No items match the current filter.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          const _TableHeader(),
          for (var i = 0; i < items.length; i++) ...[
            _TableRow(item: items[i]),
            if (i < items.length - 1)
              Container(height: 0.5, color: NexGenPalette.line),
          ],
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      color: NexGenPalette.textMedium,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 4, child: Text('PRODUCT', style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('IN STOCK',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('RSVD',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('TRUCK',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('ORDER',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('NEED',
                  textAlign: TextAlign.right, style: headerStyle)),
        ],
      ),
    );
  }
}

class _TableRow extends ConsumerWidget {
  const _TableRow({required this.item});
  final DealerInventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productBySkuProvider(item.sku));
    final displayName = product?.name ?? item.sku;

    final Color? leftBorderColor;
    if (item.needsReorder) {
      leftBorderColor = Colors.red;
    } else if (item.isLow) {
      leftBorderColor = NexGenPalette.amber;
    } else {
      leftBorderColor = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          left: leftBorderColor != null
              ? BorderSide(color: leftBorderColor, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.sku,
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _NumCell(value: item.totalAvailable),
          _NumCell(value: item.reserved, dim: item.reserved == 0),
          _NumCell(value: item.onTruck, dim: item.onTruck == 0),
          _NumCell(
            value: item.onOrder,
            highlight: item.onOrder > 0 ? NexGenPalette.cyan : null,
            dim: item.onOrder == 0,
          ),
          _NumCell(
            value: item.needed,
            highlight: item.needed > 0 ? Colors.red : null,
            // "RED if > 0, else hidden" per spec — render an em-dash so
            // the column width stays stable but the zero is muted.
            hideWhenZero: true,
          ),
        ],
      ),
    );
  }
}

class _NumCell extends StatelessWidget {
  const _NumCell({
    required this.value,
    this.dim = false,
    this.highlight,
    this.hideWhenZero = false,
  });
  final int value;
  final bool dim;
  final Color? highlight;
  final bool hideWhenZero;

  @override
  Widget build(BuildContext context) {
    final text = (hideWhenZero && value == 0) ? '—' : '$value';
    final color = highlight ??
        (dim ? NexGenPalette.textMedium : NexGenPalette.textHigh);
    return Expanded(
      flex: 1,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: highlight != null ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LOW STOCK CARD
// ═══════════════════════════════════════════════════════════════════════

class _LowStockCard extends ConsumerWidget {
  const _LowStockCard({required this.item});
  final DealerInventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productBySkuProvider(item.sku));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined,
              color: NexGenPalette.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product?.name ?? item.sku,
                  style: const TextStyle(
                    color: NexGenPalette.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${item.totalAvailable} in stock · threshold ${item.reorderThreshold}',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push('/inventory/order'),
            style: TextButton.styleFrom(
              foregroundColor: NexGenPalette.amber,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text(
              'Reorder',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// AUX
// ═══════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: NexGenPalette.textMedium,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_outlined,
                size: 48, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(
              'No inventory tracked yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: NexGenPalette.textHigh,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Place your first order to get started.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/inventory/order'),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Place First Order'),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: NexGenPalette.matteBlack,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSession extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Inventory'),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 48, color: NexGenPalette.textMedium),
              const SizedBox(height: 12),
              Text(
                'No active dealer session',
                style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red, fontSize: 12),
        ),
      ),
    );
  }
}
