import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/inventory/corporate/create_po_screen.dart';
import 'package:nexgen_command/features/inventory/corporate/receive_shipment_screen.dart';
import 'package:nexgen_command/models/inventory/corporate_inventory_item.dart';
import 'package:nexgen_command/models/inventory/product_catalog_item.dart';
import 'package:nexgen_command/models/inventory/purchase_order.dart';
import 'package:nexgen_command/services/inventory/corporate_providers.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CorporateWarehouseScreen
//
// Replaces the prior network-intelligence aggregation screen at
// lib/features/corporate/screens/corporate_warehouse_screen.dart —
// that one read from the materialId-keyed dealer inventory; this
// one reads /corporate_inventory and /purchase_orders, the new
// SKU-keyed corporate-warehouse surface from Parts 1 + 3.
//
// Layout:
//   • Action row          — "Receive Inventory" + "New PO" buttons
//                          (Receive opens a PO picker if multiple
//                          POs are open, else jumps directly).
//   • Inventory table     — every active /product_catalog SKU
//                          joined with its /corporate_inventory doc
//                          (shows on_hand, reserved, available,
//                          reorder_point, status). Tap a row to
//                          edit reorder point.
//   • Active POs section  — every PO with status != received,
//                          newest first. Each card has a Receive
//                          Shipment CTA.
// ─────────────────────────────────────────────────────────────────────────────

class CorporateWarehouseScreen extends ConsumerStatefulWidget {
  const CorporateWarehouseScreen({super.key});

  @override
  ConsumerState<CorporateWarehouseScreen> createState() =>
      _CorporateWarehouseScreenState();
}

class _CorporateWarehouseScreenState
    extends ConsumerState<CorporateWarehouseScreen> {
  String _category = 'all';

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
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(allProductsProvider);
    final invAsync = ref.watch(corporateInventoryProvider);
    final openPos = ref.watch(openPurchaseOrdersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionRow(
            onNewPO: () => Navigator.of(context).push(MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => const CreatePOScreen(),
            )),
            onReceive: () => _openReceiveFlow(context, openPos),
          ),
          const SizedBox(height: 12),
          _CategoryRow(
            value: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          _SectionLabel('Warehouse Inventory'),
          const SizedBox(height: 8),
          productsAsync.when(
            loading: () => const _LoaderBox(),
            error: (e, _) => _ErrorBox(message: 'Catalog: $e'),
            data: (products) => invAsync.when(
              loading: () => const _LoaderBox(),
              error: (e, _) => _ErrorBox(message: 'Inventory: $e'),
              data: (invItems) => _InventoryTable(
                products: _filterByCategory(products),
                inventoryByKey: {for (final i in invItems) i.sku: i},
                onEditReorder: _openReorderEditor,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel('Active Purchase Orders'),
          const SizedBox(height: 8),
          if (openPos.isEmpty)
            _EmptyBox(
                message:
                    'No open POs. Tap "New PO" to order from a supplier.'),
          for (final po in openPos)
            _POCard(
              po: po,
              onReceive: () => _openReceiveFor(context, po),
            ),
        ],
      ),
    );
  }

  List<ProductCatalogItem> _filterByCategory(List<ProductCatalogItem> all) {
    if (_category == 'all') return all;
    return all.where((p) => p.category == _category).toList();
  }

  void _openReceiveFlow(BuildContext context, List<PurchaseOrder> openPos) {
    if (openPos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No open POs to receive against. Create a PO first.'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      return;
    }
    if (openPos.length == 1) {
      _openReceiveFor(context, openPos.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select PO to receive against',
                  style:
                      Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                          )),
              const SizedBox(height: 12),
              for (final po in openPos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.local_shipping_outlined,
                      color: NexGenPalette.cyan),
                  title: Text(
                    po.supplierName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${po.lineItems.length} items · ${po.status.label}',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: NexGenPalette.cyan),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _openReceiveFor(context, po);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReceiveFor(BuildContext context, PurchaseOrder po) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ReceiveShipmentScreen(po: po),
    ));
  }

  Future<void> _openReorderEditor(
      ProductCatalogItem product, CorporateInventoryItem? inv) async {
    final ctl = TextEditingController(
        text: inv?.reorderPoint != null && inv!.reorderPoint > 0
            ? '${inv.reorderPoint}'
            : '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: Text(
          product.name,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SKU ${product.sku}',
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Reorder point (units)',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
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
              final v = int.tryParse(ctl.text.trim()) ?? 0;
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
    if (result == null || !mounted) return;
    try {
      await ref
          .read(corporateInventoryNotifierProvider)
          .setReorderPoint(sku: product.sku, reorderPoint: result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${product.name}: reorder point set to $result units'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ACTION ROW + CATEGORY CHIPS
// ═══════════════════════════════════════════════════════════════════════

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onNewPO, required this.onReceive});
  final VoidCallback onNewPO;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onReceive,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Receive Inventory'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.6)),
              foregroundColor: NexGenPalette.cyan,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onNewPO,
            icon: const Icon(Icons.add),
            label: const Text('New PO'),
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: NexGenPalette.matteBlack,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in _CorporateWarehouseScreenState._categories) ...[
            InkWell(
              onTap: () => onChanged(c.$1),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: value == c.$1
                      ? NexGenPalette.cyan
                      : NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: value == c.$1
                        ? NexGenPalette.cyan
                        : NexGenPalette.line,
                  ),
                ),
                child: Text(
                  c.$2,
                  style: TextStyle(
                    color: value == c.$1
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INVENTORY TABLE
// ═══════════════════════════════════════════════════════════════════════

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({
    required this.products,
    required this.inventoryByKey,
    required this.onEditReorder,
  });
  final List<ProductCatalogItem> products;
  final Map<String, CorporateInventoryItem> inventoryByKey;
  final void Function(ProductCatalogItem, CorporateInventoryItem?)
      onEditReorder;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _EmptyBox(
          message: 'No products in this category.');
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
          for (var i = 0; i < products.length; i++) ...[
            _TableRow(
              product: products[i],
              inventory: inventoryByKey[products[i].sku],
              onEditReorder: () =>
                  onEditReorder(products[i], inventoryByKey[products[i].sku]),
            ),
            if (i < products.length - 1)
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
      fontWeight: FontWeight.w800,
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
              child: Text('ON HAND',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('RSVD',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('AVAIL',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 1,
              child: Text('REORDER',
                  textAlign: TextAlign.right, style: headerStyle)),
          Expanded(
              flex: 2,
              child: Text('STATUS',
                  textAlign: TextAlign.right, style: headerStyle)),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.product,
    required this.inventory,
    required this.onEditReorder,
  });
  final ProductCatalogItem product;
  final CorporateInventoryItem? inventory;
  final VoidCallback onEditReorder;

  @override
  Widget build(BuildContext context) {
    final inv = inventory;
    final onHand = inv?.onHand ?? 0;
    final reserved = inv?.reservedForOrders ?? 0;
    final available = inv?.available ?? 0;
    final reorder = inv?.reorderPoint ?? 0;
    final (statusLabel, statusColor) = _statusVisuals(available, reorder);

    return InkWell(
      onTap: onEditReorder,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    product.sku,
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
            _Num(value: onHand),
            _Num(value: reserved, dim: reserved == 0),
            _Num(
              value: available,
              highlight: available <= reorder && reorder > 0
                  ? NexGenPalette.amber
                  : null,
            ),
            _Num(
              value: reorder,
              dim: reorder == 0,
            ),
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
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

(String, Color) _statusVisuals(int available, int reorderPoint) {
  if (available <= 0) return ('OUT', Colors.red);
  if (reorderPoint > 0 && available <= reorderPoint) {
    return ('LOW', NexGenPalette.amber);
  }
  return ('GOOD', NexGenPalette.green);
}

class _Num extends StatelessWidget {
  const _Num({required this.value, this.dim = false, this.highlight});
  final int value;
  final bool dim;
  final Color? highlight;
  @override
  Widget build(BuildContext context) {
    final color = highlight ??
        (dim ? NexGenPalette.textMedium : NexGenPalette.textHigh);
    return Expanded(
      flex: 1,
      child: Text(
        '$value',
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
// PO CARD
// ═══════════════════════════════════════════════════════════════════════

class _POCard extends StatelessWidget {
  const _POCard({required this.po, required this.onReceive});
  final PurchaseOrder po;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final received =
        po.lineItems.fold<int>(0, (acc, l) => acc + l.qtyReceived);
    final ordered =
        po.lineItems.fold<int>(0, (acc, l) => acc + l.qtyOrdered);
    final progress = ordered == 0 ? 0.0 : received / ordered;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
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
              Expanded(
                child: Text(
                  po.supplierName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: po.status == POStatus.partial
                      ? NexGenPalette.amber.withValues(alpha: 0.15)
                      : NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: po.status == POStatus.partial
                        ? NexGenPalette.amber.withValues(alpha: 0.5)
                        : NexGenPalette.cyan.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  po.status.label,
                  style: TextStyle(
                    color: po.status == POStatus.partial
                        ? NexGenPalette.amber
                        : NexGenPalette.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${po.lineItems.length} line item${po.lineItems.length == 1 ? '' : 's'} · '
            'received $received / $ordered units'
            '${po.expectedDelivery != null ? ' · expected ${_formatDate(po.expectedDelivery!)}' : ''}',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: NexGenPalette.gunmetal,
              valueColor: AlwaysStoppedAnimation(
                progress >= 1.0 ? NexGenPalette.green : NexGenPalette.cyan,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onReceive,
              icon: const Icon(Icons.inventory_2),
              label: const Text('Receive Shipment'),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: NexGenPalette.matteBlack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHARED UI
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
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    );
  }
}

class _LoaderBox extends StatelessWidget {
  const _LoaderBox();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: NexGenPalette.cyan,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
}
