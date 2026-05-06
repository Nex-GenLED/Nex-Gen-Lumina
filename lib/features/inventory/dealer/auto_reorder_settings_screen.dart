import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/dealer_inventory_item.dart';
import 'package:nexgen_command/models/inventory/product_catalog_item.dart';
import 'package:nexgen_command/services/inventory/dealer_inventory_providers.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AutoReorderSettingsScreen
//
// Per-SKU configuration of the automatic reorder rule. Saves to
// /dealers/{dealerCode}/sku_inventory/{sku}, populating
// auto_reorder_enabled, reorder_threshold, auto_reorder_qty.
//
// The actual reorder TRIGGER is invoked elsewhere (Cloud Function or
// background task — TODO for a follow-up): when a SKU's
// totalAvailable drops below its reorder_threshold AND
// auto_reorder_enabled is true, the trigger calls
// DealerOrderNotifier.findOrCreateBatchDraft(...) and adds
// auto_reorder_qty units to that draft. The draft is NOT auto-
// submitted — the dealer reviews and submits when ready.
// ─────────────────────────────────────────────────────────────────────────────

class AutoReorderSettingsScreen extends ConsumerStatefulWidget {
  final String? dealerCodeOverride;
  const AutoReorderSettingsScreen({super.key, this.dealerCodeOverride});

  @override
  ConsumerState<AutoReorderSettingsScreen> createState() =>
      _AutoReorderSettingsScreenState();
}

class _AutoReorderSettingsScreenState
    extends ConsumerState<AutoReorderSettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final dealerCode =
        widget.dealerCodeOverride ?? ref.watch(currentDealerCodeProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Auto-Reorder',
            style: TextStyle(color: Colors.white)),
      ),
      body: dealerCode == null
          ? const _NoSession()
          : _Body(
              dealerCode: dealerCode,
              query: _query,
              onQueryChanged: (v) => setState(() => _query = v),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.dealerCode,
    required this.query,
    required this.onQueryChanged,
  });
  final String dealerCode;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(allProductsProvider);
    final inventoryAsync = ref.watch(dealerInventoryProvider(dealerCode));

    return productsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (e, _) => _Error(message: 'Catalog load failed: $e'),
      data: (products) => inventoryAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
        error: (e, _) => _Error(message: 'Inventory load failed: $e'),
        data: (inventory) {
          final invByKey = {for (final i in inventory) i.sku: i};
          final filtered = _applyQuery(products, query);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: onQueryChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Filter products by name or SKU',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium),
                    prefixIcon:
                        Icon(Icons.search, color: NexGenPalette.textMedium),
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
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded,
                          color: NexGenPalette.cyan, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'When stock drops below threshold, the order quantity is added to your active draft (or a new draft is created within the 48-hour batch window).',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          query.isEmpty
                              ? 'No products in catalog yet.'
                              : 'No products match "$query".',
                          style: TextStyle(
                              color: NexGenPalette.textMedium, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final p = filtered[i];
                          final inv = invByKey[p.sku];
                          return _SkuTile(
                            dealerCode: dealerCode,
                            product: p,
                            inventory: inv,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<ProductCatalogItem> _applyQuery(
      List<ProductCatalogItem> all, String query) {
    if (query.trim().isEmpty) return all;
    final q = query.toLowerCase();
    return all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q))
        .toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PER-SKU TILE
// ═══════════════════════════════════════════════════════════════════════

class _SkuTile extends StatefulWidget {
  const _SkuTile({
    required this.dealerCode,
    required this.product,
    required this.inventory,
  });
  final String dealerCode;
  final ProductCatalogItem product;
  final DealerInventoryItem? inventory;

  @override
  State<_SkuTile> createState() => _SkuTileState();
}

class _SkuTileState extends State<_SkuTile> {
  late bool _enabled;
  late int _threshold;
  late int _qty;
  late TextEditingController _thresholdCtl;
  late TextEditingController _qtyCtl;
  bool _expanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.inventory?.autoReorderEnabled ?? false;
    _threshold = widget.inventory?.reorderThreshold ?? 0;
    _qty = widget.inventory?.autoReorderQty ?? widget.product.packQty;
    _thresholdCtl = TextEditingController(text: '$_threshold');
    _qtyCtl = TextEditingController(text: '$_qty');
  }

  @override
  void didUpdateWidget(covariant _SkuTile old) {
    super.didUpdateWidget(old);
    final newEnabled = widget.inventory?.autoReorderEnabled ?? false;
    final newThreshold = widget.inventory?.reorderThreshold ?? 0;
    final newQty = widget.inventory?.autoReorderQty ?? widget.product.packQty;
    if (newEnabled != _enabled) _enabled = newEnabled;
    if (newThreshold != _threshold && _thresholdCtl.text == '$_threshold') {
      _threshold = newThreshold;
      _thresholdCtl.text = '$_threshold';
    }
    if (newQty != _qty && _qtyCtl.text == '$_qty') {
      _qty = newQty;
      _qtyCtl.text = '$_qty';
    }
  }

  @override
  void dispose() {
    _thresholdCtl.dispose();
    _qtyCtl.dispose();
    super.dispose();
  }

  bool get _qtyIsPackMultiple =>
      _qty > 0 && _qty % widget.product.packQty == 0;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final invDoc = FirebaseFirestore.instance
          .collection('dealers')
          .doc(widget.dealerCode)
          .collection('sku_inventory')
          .doc(widget.product.sku);
      // Round qty up to a pack multiple at save time so the trigger
      // never has to round mid-flight.
      final roundedQty = widget.product.roundUpToPackQty(_qty);
      await invDoc.set({
        'sku': widget.product.sku,
        'auto_reorder_enabled': _enabled,
        'reorder_threshold': _threshold,
        'auto_reorder_qty': roundedQty,
        'last_updated': Timestamp.now(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _qty = roundedQty;
        _qtyCtl.text = '$roundedQty';
        _saving = false;
        _expanded = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${widget.product.name}: auto-reorder ${_enabled ? "enabled" : "disabled"}'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inventory;
    final available = inv?.totalAvailable ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _enabled
              ? NexGenPalette.cyan.withValues(alpha: 0.4)
              : NexGenPalette.line,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.product.sku} · stock $available · '
                          '${widget.product.packUnit} of ${widget.product.packQty}',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: (v) {
                      setState(() => _enabled = v);
                      _save();
                    },
                    activeThumbColor: NexGenPalette.cyan,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _NumField(
                          label: 'Reorder when stock ≤',
                          controller: _thresholdCtl,
                          onChanged: (v) =>
                              setState(() => _threshold = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumField(
                          label: 'Order quantity (units)',
                          controller: _qtyCtl,
                          onChanged: (v) => setState(() => _qty = v),
                        ),
                      ),
                    ],
                  ),
                  if (_qty > 0 && !_qtyIsPackMultiple) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Will round up to ${widget.product.roundUpToPackQty(_qty)} units '
                      '(${widget.product.packsNeeded(_qty)} ${widget.product.packUnit})',
                      style: const TextStyle(
                        color: NexGenPalette.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: NexGenPalette.matteBlack,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: NexGenPalette.matteBlack,
                              ),
                            )
                          : const Text('Save',
                              style: TextStyle(fontWeight: FontWeight.w700)),
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

class _NumField extends StatelessWidget {
  const _NumField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<int> onChanged;

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
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: NexGenPalette.gunmetal,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: NexGenPalette.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: NexGenPalette.line),
            ),
          ),
          onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MISC
// ═══════════════════════════════════════════════════════════════════════

class _NoSession extends StatelessWidget {
  const _NoSession();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No active dealer session.',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message});
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
