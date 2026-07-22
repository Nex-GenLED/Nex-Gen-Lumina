import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/models/inventory/dealer_order.dart';
import 'package:nexgen_command/models/inventory/product_catalog_item.dart';
import 'package:nexgen_command/services/inventory/dealer_inventory_providers.dart';
import 'package:nexgen_command/services/inventory/dealer_order_providers.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DealerOrderScreen
//
// Browse-and-add ordering surface. On open, resolves the active draft
// via DealerOrderNotifier.findOrCreateBatchDraft (48-hour batch
// window) so multiple sessions and auto-reorder triggers all coalesce
// into the same in-flight order rather than fragmenting into many
// tiny submissions.
//
// Per-row +/- stepper edits LOCAL state only; the line is committed
// to the draft when the dealer taps "Update" (or "Remove" to clear
// it). Pack-quantity rounding is always applied at commit time via
// ProductCatalogItem.roundUpToPackQty — the screen warns inline but
// never blocks the order.
// ─────────────────────────────────────────────────────────────────────────────

class DealerOrderScreen extends ConsumerStatefulWidget {
  /// Optional override; null falls back to currentDealerCodeProvider.
  final String? dealerCodeOverride;
  const DealerOrderScreen({super.key, this.dealerCodeOverride});

  @override
  ConsumerState<DealerOrderScreen> createState() => _DealerOrderScreenState();
}

class _DealerOrderScreenState extends ConsumerState<DealerOrderScreen> {
  final _searchCtl = TextEditingController();
  String _query = '';
  String _category = 'all';

  /// SKUs the dealer is editing this session — values are the in-flight
  /// quantities before commit. Lets dealers tap +/- without spamming
  /// Firestore transactions; commit happens on the row's "Update" tap.
  final Map<String, int> _localQty = {};

  String? _draftOrderId;
  bool _bootstrapping = true;
  String? _bootstrapError;
  bool _submitting = false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Resolve dealer code, fetch dealer doc for the company name, then
  /// find-or-create the active draft within the 48-hour batch window.
  Future<void> _bootstrap() async {
    final dealerCode =
        widget.dealerCodeOverride ?? ref.read(currentDealerCodeProvider);
    if (dealerCode == null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = 'No active dealer session.';
      });
      return;
    }
    try {
      final dealerSnap = await FirebaseFirestore.instance
          .collection('dealers')
          .doc(dealerCode)
          .get();
      final dealerName = dealerSnap.exists
          ? (DealerInfo.fromMap(dealerSnap.data() ?? {}).companyName)
          : 'Dealer $dealerCode';

      final notifier = ref.read(dealerOrderNotifierProvider);
      final draft = await notifier.findOrCreateBatchDraft(
        dealerCode: dealerCode,
        dealerName: dealerName,
      );
      if (!mounted) return;
      setState(() {
        _draftOrderId = draft.orderId;
        _bootstrapping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _bootstrapError = 'Failed to open order draft: $e';
      });
    }
  }

  // ── Filtering ──────────────────────────────────────────────────────

  List<ProductCatalogItem> _filter(List<ProductCatalogItem> all) {
    return all.where((p) {
      if (_category != 'all' && p.category != _category) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();
  }

  // ── Per-row commits ────────────────────────────────────────────────

  Future<void> _commitLine(ProductCatalogItem product, int requestedUnits) async {
    final orderId = _draftOrderId;
    if (orderId == null) return;
    if (requestedUnits <= 0) {
      await ref
          .read(dealerOrderNotifierProvider)
          .removeLineItem(orderId: orderId, sku: product.sku);
    } else {
      await ref.read(dealerOrderNotifierProvider).addOrUpdateLineItem(
            orderId: orderId,
            product: product,
            requestedUnits: requestedUnits,
          );
    }
    if (!mounted) return;
    setState(() {
      _localQty.remove(product.sku);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(requestedUnits <= 0
            ? 'Removed ${product.name} from order'
            : 'Added ${product.roundUpToPackQty(requestedUnits)} '
                '${product.packUnit == 'each' ? 'units' : product.packUnit}'
                ' of ${product.name}'),
        duration: const Duration(seconds: 2),
        backgroundColor: NexGenPalette.gunmetal,
      ),
    );
  }

  // ── Submission ─────────────────────────────────────────────────────

  Future<void> _submitOrder(DealerOrder order) async {
    if (!order.canSubmit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Submit Order',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Submit ${order.lineItems.length} line item'
          '${order.lineItems.length == 1 ? '' : 's'} '
          '(${order.totalUnits} units, '
          '\$${order.subtotal.toStringAsFixed(2)} subtotal) '
          'to Nex-Gen for review?\n\n'
          'Nex-Gen will calculate shipping cost and confirm payment '
          'before processing the order.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: NexGenPalette.matteBlack,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await ref.read(dealerOrderNotifierProvider).submit(order.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Order submitted! Nex-Gen will review and confirm shipping cost before processing.'),
          duration: Duration(seconds: 4),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submit failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return _scaffold(
        appBar: _appBar(itemCount: 0, onSettings: null),
        body: const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
      );
    }
    if (_bootstrapError != null) {
      return _scaffold(
        appBar: _appBar(itemCount: 0, onSettings: null),
        body: _ErrorPanel(message: _bootstrapError!),
      );
    }

    final dealerCode =
        widget.dealerCodeOverride ?? ref.watch(currentDealerCodeProvider);
    if (dealerCode == null) {
      return _scaffold(
        appBar: _appBar(itemCount: 0, onSettings: null),
        body: const _ErrorPanel(message: 'No active dealer session.'),
      );
    }

    final productsAsync = ref.watch(allProductsProvider);
    final orders = ref.watch(dealerOrdersProvider(dealerCode)).valueOrNull
            ?? const [];
    final draft =
        orders.firstWhere((o) => o.orderId == _draftOrderId, orElse: () {
      // Fallback for the brief window where the stream hasn't caught up.
      return DealerOrder(
        orderId: _draftOrderId ?? '',
        dealerCode: dealerCode,
        dealerName: '',
      );
    });

    return _scaffold(
      appBar: _appBar(
        itemCount: draft.lineItems.length,
        onSettings: () => context.push('/inventory/auto-reorder'),
      ),
      body: productsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
        error: (e, _) =>
            _ErrorPanel(message: 'Failed to load catalog: $e'),
        data: (allProducts) {
          final filtered = _filter(allProducts);
          return Column(
            children: [
              _SearchAndCategoryHeader(
                searchCtl: _searchCtl,
                query: _query,
                onQueryChanged: (v) => setState(() => _query = v),
                category: _category,
                onCategoryChanged: (v) => setState(() => _category = v),
                categories: _categories,
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyCatalogPlaceholder(query: _query)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 160),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final product = filtered[i];
                          final inv = ref.read(inventoryItemProvider(
                              (dealerCode: dealerCode, sku: product.sku)));
                          final committedLine = draft.lineItems
                              .where((l) => l.sku == product.sku)
                              .firstOrNull;
                          final committedQty =
                              committedLine?.quantityOrdered ?? 0;
                          final localQty = _localQty[product.sku];
                          final pendingQty = localQty ?? committedQty;
                          return _ProductCard(
                            product: product,
                            committedQty: committedQty,
                            pendingQty: pendingQty,
                            onHand: inv?.inWarehouse ?? 0,
                            onLocalChange: (n) => setState(() {
                              _localQty[product.sku] = n;
                            }),
                            onCommit: () =>
                                _commitLine(product, pendingQty),
                            isDirty: pendingQty != committedQty,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomBar: _OrderSummaryBar(
        order: draft,
        submitting: _submitting,
        onSubmit: () => _submitOrder(draft),
      ),
    );
  }

  // ── AppBar / scaffold builders ─────────────────────────────────────

  AppBar _appBar({required int itemCount, VoidCallback? onSettings}) {
    return AppBar(
      backgroundColor: NexGenPalette.gunmetal90,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text('Place Order',
          style: TextStyle(color: Colors.white)),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.shopping_cart_outlined,
                  color: Colors.white, size: 22),
              if (itemCount > 0)
                Positioned(
                  right: 0,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$itemCount',
                      style: const TextStyle(
                        color: NexGenPalette.matteBlack,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Auto-reorder settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _scaffold({
    required AppBar appBar,
    required Widget body,
    Widget? bottomBar,
  }) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEARCH + CATEGORY HEADER
// ═══════════════════════════════════════════════════════════════════════

class _CategoryChip {
  final String value;
  final String label;
  const _CategoryChip(this.value, this.label);
}

class _SearchAndCategoryHeader extends StatelessWidget {
  const _SearchAndCategoryHeader({
    required this.searchCtl,
    required this.query,
    required this.onQueryChanged,
    required this.category,
    required this.onCategoryChanged,
    required this.categories,
  });
  final TextEditingController searchCtl;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final List<_CategoryChip> categories;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        children: [
          TextField(
            controller: searchCtl,
            onChanged: onQueryChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search products by name or SKU',
              hintStyle: TextStyle(color: NexGenPalette.textMedium),
              prefixIcon: Icon(Icons.search, color: NexGenPalette.textMedium),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.clear, color: NexGenPalette.textMedium),
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
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in categories) ...[
                  _ChipWidget(
                    label: c.label,
                    selected: category == c.value,
                    onTap: () => onCategoryChanged(c.value),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipWidget extends StatelessWidget {
  const _ChipWidget({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? NexGenPalette.cyan : NexGenPalette.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? NexGenPalette.matteBlack : NexGenPalette.textHigh,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRODUCT CARD
// ═══════════════════════════════════════════════════════════════════════

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.committedQty,
    required this.pendingQty,
    required this.onHand,
    required this.onLocalChange,
    required this.onCommit,
    required this.isDirty,
  });
  final ProductCatalogItem product;
  final int committedQty;
  final int pendingQty;
  final int onHand;
  final ValueChanged<int> onLocalChange;
  final VoidCallback onCommit;
  final bool isDirty;

  @override
  Widget build(BuildContext context) {
    final packsNeeded = product.packsNeeded(pendingQty);
    final roundedQty = product.roundUpToPackQty(pendingQty);
    final isPackMultiple = pendingQty == 0 || pendingQty % product.packQty == 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: committedQty > 0
              ? NexGenPalette.cyan.withValues(alpha: 0.4)
              : NexGenPalette.line,
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
                      product.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.sku,
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (committedQty > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'In cart: $committedQty',
                    style: const TextStyle(
                      color: NexGenPalette.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sold in ${product.packUnit}${product.packUnit.endsWith('s') ? '' : 's'} of ${product.packQty}'
            ' · You have: $onHand in warehouse',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: NexGenPalette.gunmetal,
                  foregroundColor: NexGenPalette.textHigh,
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
                onPressed: pendingQty <= 0
                    ? null
                    : () => onLocalChange(
                        (pendingQty - product.packQty).clamp(0, 1 << 30)),
                icon: const Icon(Icons.remove, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: Text(
                    '$pendingQty units',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: NexGenPalette.gunmetal,
                  foregroundColor: NexGenPalette.textHigh,
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () =>
                    onLocalChange(pendingQty + product.packQty),
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (pendingQty > 0)
            Text(
              '= $packsNeeded ${product.packUnit}'
              '${packsNeeded == 1 || product.packUnit.endsWith('s') ? '' : 's'} '
              '× ${product.packQty} = $roundedQty units',
              style: TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (pendingQty > 0 && !isPackMultiple)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Will be rounded up to $roundedQty units '
                '($packsNeeded ${product.packUnit}'
                '${packsNeeded == 1 || product.packUnit.endsWith('s') ? '' : 's'})',
                style: const TextStyle(
                  color: NexGenPalette.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (committedQty > 0)
                TextButton.icon(
                  onPressed: () {
                    onLocalChange(0);
                    onCommit();
                  },
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 16),
                  label: const Text(
                    'Remove',
                    style:
                        TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: isDirty ? onCommit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: NexGenPalette.matteBlack,
                  disabledBackgroundColor: NexGenPalette.gunmetal,
                  disabledForegroundColor: NexGenPalette.textMedium,
                ),
                child: Text(
                  committedQty == 0 ? 'Add to Order' : 'Update',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
// ORDER SUMMARY BAR
// ═══════════════════════════════════════════════════════════════════════

class _OrderSummaryBar extends StatelessWidget {
  const _OrderSummaryBar({
    required this.order,
    required this.submitting,
    required this.onSubmit,
  });
  final DealerOrder order;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final canSubmit = order.canSubmit && !submitting;
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '${order.lineItems.length} item'
                  '${order.lineItems.length == 1 ? '' : 's'} '
                  '· ${order.totalUnits} units',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  'Subtotal',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Text(
                  '\$${order.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // TODO: Shippo API integration for real-time rate calculation.
            // For now, shipping is calculated manually by Tyler at the
            // approve-order step (Part 7) and added to order_total then.
            Row(
              children: [
                Expanded(
                  child: Text(
                    '+ Shipping (Calculated by Nex-Gen)',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: canSubmit ? onSubmit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: NexGenPalette.matteBlack,
                  disabledBackgroundColor: NexGenPalette.gunmetal90,
                  disabledForegroundColor: NexGenPalette.textMedium,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NexGenPalette.matteBlack,
                        ),
                      )
                    : Text(
                        order.lineItems.isEmpty
                            ? 'Add items to submit'
                            : 'Submit Order',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PLACEHOLDERS
// ═══════════════════════════════════════════════════════════════════════

class _EmptyCatalogPlaceholder extends StatelessWidget {
  const _EmptyCatalogPlaceholder({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 48, color: NexGenPalette.textMedium),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'No products in this category'
                  : 'No products match "$query"',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
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
          style: const TextStyle(color: Colors.red, fontSize: 13),
        ),
      ),
    );
  }
}
