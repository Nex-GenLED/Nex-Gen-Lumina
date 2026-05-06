import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/purchase_order.dart';
import 'package:nexgen_command/services/inventory/corporate_providers.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReceiveShipmentScreen
//
// Walk through every line on a PO, capture how many units arrived in
// THIS shipment, then submit. Atomic write via
// CorporateInventoryNotifier.receivePOShipment:
//   • PO line items get qty_received += entered delta (clamped to
//     line.qtyOutstanding server-side).
//   • PO status auto-resolves: received | partial | unchanged.
//   • /corporate_inventory/{sku}.on_hand += delta per SKU, with
//     last_received_at bumped. Inventory docs are upserted via merge
//     so brand-new SKUs work on first receive.
//
// Code comment (per Tyler's Part 8 spec): downstream dealer orders
// in payment_confirmed/processing that contain just-received SKUs
// are now "ready to ship". Surfacing them is future work — flagged
// in the notifier's TODO.
// ─────────────────────────────────────────────────────────────────────────────

class ReceiveShipmentScreen extends ConsumerStatefulWidget {
  final PurchaseOrder po;
  const ReceiveShipmentScreen({super.key, required this.po});

  @override
  ConsumerState<ReceiveShipmentScreen> createState() =>
      _ReceiveShipmentScreenState();
}

class _ReceiveShipmentScreenState extends ConsumerState<ReceiveShipmentScreen> {
  /// Per-line entered qty for THIS shipment. Keyed by SKU because
  /// PO line_items are ordered but not guaranteed unique-on-sku.
  final Map<String, int> _entered = {};
  bool _saving = false;

  Future<void> _submit() async {
    final received = <String, int>{
      for (final entry in _entered.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (received.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Enter at least one line\'s received quantity before submitting.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(corporateInventoryNotifierProvider).receivePOShipment(
            poId: widget.po.poId,
            received: received,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Shipment recorded · ${received.length} SKU${received.length == 1 ? '' : 's'} updated'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receive failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final po = widget.po;
    final enteredCount =
        _entered.values.fold<int>(0, (acc, v) => acc + v);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receive Shipment',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            Text(
              po.supplierName,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          for (final line in po.lineItems)
            _LineRow(
              line: line,
              entered: _entered[line.sku] ?? 0,
              onChanged: (v) => setState(() {
                if (v <= 0) {
                  _entered.remove(line.sku);
                } else {
                  _entered[line.sku] = v;
                }
              }),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal,
          border: Border(top: BorderSide(color: NexGenPalette.line)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_saving || enteredCount == 0) ? null : _submit,
              icon: const Icon(Icons.check_circle_outline),
              label: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NexGenPalette.matteBlack,
                      ),
                    )
                  : Text(
                      enteredCount == 0
                          ? 'Enter received quantities to submit'
                          : 'Submit Shipment ($enteredCount units)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.green,
                foregroundColor: NexGenPalette.matteBlack,
                disabledBackgroundColor: NexGenPalette.gunmetal90,
                disabledForegroundColor: NexGenPalette.textMedium,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineRow extends ConsumerStatefulWidget {
  const _LineRow({
    required this.line,
    required this.entered,
    required this.onChanged,
  });
  final POLineItem line;
  final int entered;
  final ValueChanged<int> onChanged;

  @override
  ConsumerState<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends ConsumerState<_LineRow> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(
        text: widget.entered > 0 ? '${widget.entered}' : '');
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final product = ref.watch(productBySkuProvider(line.sku));
    final outstanding = line.qtyOutstanding;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: line.isFullyReceived
              ? NexGenPalette.green.withValues(alpha: 0.4)
              : NexGenPalette.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product?.name ?? line.sku,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (line.isFullyReceived)
                Icon(Icons.check_circle,
                    color: NexGenPalette.green, size: 16),
            ],
          ),
          Text(
            line.sku,
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatChip(
                  label: 'Ordered', value: '${line.qtyOrdered}'),
              const SizedBox(width: 6),
              _StatChip(
                label: 'Received',
                value: '${line.qtyReceived}',
                tint: line.qtyReceived > 0
                    ? NexGenPalette.green
                    : NexGenPalette.textMedium,
              ),
              const SizedBox(width: 6),
              _StatChip(
                label: 'Outstanding',
                value: '$outstanding',
                tint: outstanding > 0
                    ? NexGenPalette.amber
                    : NexGenPalette.textMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: outstanding > 0,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: outstanding > 0
                        ? 'Received this shipment (max $outstanding)'
                        : 'Fully received',
                    labelStyle:
                        TextStyle(color: NexGenPalette.textMedium),
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
                  onChanged: (v) {
                    final n = int.tryParse(v) ?? 0;
                    final clamped = n > outstanding ? outstanding : n;
                    if (clamped != n) {
                      _ctl.text = '$clamped';
                      _ctl.selection = TextSelection.collapsed(
                          offset: _ctl.text.length);
                    }
                    widget.onChanged(clamped);
                  },
                ),
              ),
              if (outstanding > 0) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    _ctl.text = '$outstanding';
                    _ctl.selection = TextSelection.collapsed(
                        offset: _ctl.text.length);
                    widget.onChanged(outstanding);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('All',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.tint = NexGenPalette.textHigh,
  });
  final String label;
  final String value;
  final Color tint;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: tint,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
