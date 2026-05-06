import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/product_catalog_item.dart';
import 'package:nexgen_command/models/inventory/purchase_order.dart';
import 'package:nexgen_command/services/inventory/corporate_providers.dart';
import 'package:nexgen_command/services/inventory/product_catalog_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CreatePOScreen
//
// Internal-only PO creation. Tyler picks a supplier, sets an
// expected delivery date, builds a list of SKU + qty + per-unit cost
// line items from the product catalog, optionally adds notes, then
// saves. Writes to /purchase_orders via
// CorporateInventoryNotifier.createPO with status 'ordered'.
//
// Per Tyler's spec: unit cost is internal-only (never shown to
// dealers — different field than catalog unit_price). Stored on the
// PO line item and used for COGS analytics later.
// ─────────────────────────────────────────────────────────────────────────────

class CreatePOScreen extends ConsumerStatefulWidget {
  const CreatePOScreen({super.key});

  @override
  ConsumerState<CreatePOScreen> createState() => _CreatePOScreenState();
}

class _CreatePOScreenState extends ConsumerState<CreatePOScreen> {
  final _supplierCtl = TextEditingController();
  final _searchCtl = TextEditingController();
  final _notesCtl = TextEditingController();

  DateTime? _expectedDelivery;
  String _query = '';
  String _category = 'all';
  bool _saving = false;

  /// SKU → (qty ordered, unit cost). Built up in-memory until save.
  final Map<String, _DraftLine> _lines = {};

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
    _supplierCtl.dispose();
    _searchCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    final supplier = _supplierCtl.text.trim();
    if (supplier.isEmpty) {
      _err('Enter a supplier name.');
      return;
    }
    final lineList = _lines.entries
        .where((e) => e.value.qty > 0)
        .map((e) => POLineItem(
              sku: e.key,
              qtyOrdered: e.value.qty,
              unitCost: e.value.unitCost,
            ))
        .toList();
    if (lineList.isEmpty) {
      _err('Add at least one line item before saving.');
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final id = await ref
          .read(corporateInventoryNotifierProvider)
          .createPO(
            supplierName: supplier,
            lineItems: lineList,
            createdBy: uid,
            expectedDelivery: _expectedDelivery,
            notes: _notesCtl.text.trim().isEmpty
                ? null
                : _notesCtl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PO created · ${lineList.length} lines · $id'),
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDelivery ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: NexGenPalette.cyan,
            onPrimary: NexGenPalette.matteBlack,
            surface: NexGenPalette.gunmetal,
            onSurface: NexGenPalette.textHigh,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expectedDelivery = picked);
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(allProductsProvider);
    final knownSuppliers = ref.watch(knownSuppliersProvider);
    final lineCount = _lines.values.where((l) => l.qty > 0).length;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'New PO${lineCount > 0 ? ' · $lineCount' : ''}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: productsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
        error: (e, _) => _err2('Catalog: $e'),
        data: (products) {
          final filtered = _filter(products);
          return Column(
            children: [
              _Header(
                supplierCtl: _supplierCtl,
                knownSuppliers: knownSuppliers,
                expectedDelivery: _expectedDelivery,
                onPickDate: _pickDate,
                searchCtl: _searchCtl,
                query: _query,
                onQueryChanged: (v) => setState(() => _query = v),
                category: _category,
                onCategoryChanged: (v) => setState(() => _category = v),
                categories: _categories,
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No products in this category.'
                              : 'No matches for "$_query".',
                          style: TextStyle(
                              color: NexGenPalette.textMedium, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(12, 8, 12, 200),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final p = filtered[i];
                          final draft = _lines[p.sku];
                          return _LineCard(
                            product: p,
                            draft: draft,
                            onChanged: (qty, cost) {
                              setState(() {
                                if (qty <= 0) {
                                  _lines.remove(p.sku);
                                } else {
                                  _lines[p.sku] =
                                      _DraftLine(qty: qty, unitCost: cost);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _SaveBar(
        notesCtl: _notesCtl,
        saving: _saving,
        canSave: _supplierCtl.text.trim().isNotEmpty &&
            _lines.values.any((l) => l.qty > 0),
        lineCount: lineCount,
        onSave: _save,
      ),
    );
  }

  Widget _err2(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  }

  List<ProductCatalogItem> _filter(List<ProductCatalogItem> all) {
    return all.where((p) {
      if (_category != 'all' && p.category != _category) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).toList();
  }
}

class _DraftLine {
  final int qty;
  final double unitCost;
  const _DraftLine({required this.qty, required this.unitCost});
}

// ═══════════════════════════════════════════════════════════════════════
// HEADER (supplier + date + search/filter)
// ═══════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.supplierCtl,
    required this.knownSuppliers,
    required this.expectedDelivery,
    required this.onPickDate,
    required this.searchCtl,
    required this.query,
    required this.onQueryChanged,
    required this.category,
    required this.onCategoryChanged,
    required this.categories,
  });
  final TextEditingController supplierCtl;
  final List<String> knownSuppliers;
  final DateTime? expectedDelivery;
  final VoidCallback onPickDate;
  final TextEditingController searchCtl;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final List<(String, String)> categories;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SupplierField(
                  controller: supplierCtl,
                  knownSuppliers: knownSuppliers,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: OutlinedButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(
                    expectedDelivery == null
                        ? 'ETA'
                        : _formatShortDate(expectedDelivery!),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: NexGenPalette.line),
                    foregroundColor: NexGenPalette.textHigh,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: searchCtl,
            onChanged: onQueryChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search products by name or SKU',
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
                                : NexGenPalette.line),
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
        ],
      ),
    );
  }
}

class _SupplierField extends StatelessWidget {
  const _SupplierField({
    required this.controller,
    required this.knownSuppliers,
  });
  final TextEditingController controller;
  final List<String> knownSuppliers;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (txt) {
        final q = txt.text.trim().toLowerCase();
        if (q.isEmpty) return knownSuppliers;
        return knownSuppliers
            .where((s) => s.toLowerCase().contains(q))
            .toList();
      },
      initialValue: TextEditingValue(text: controller.text),
      onSelected: (v) => controller.text = v,
      fieldViewBuilder:
          (ctx, fieldCtl, focus, onFieldSubmitted) {
        // Sync external controller with the autocomplete's internal one.
        fieldCtl.addListener(() {
          if (controller.text != fieldCtl.text) {
            controller.text = fieldCtl.text;
          }
        });
        return TextField(
          controller: fieldCtl,
          focusNode: focus,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Supplier',
            labelStyle: TextStyle(color: NexGenPalette.textMedium),
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
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: NexGenPalette.gunmetal,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      dense: true,
                      title: Text(
                        o,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () => onSelected(o),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LINE CARD
// ═══════════════════════════════════════════════════════════════════════

class _LineCard extends StatefulWidget {
  const _LineCard({
    required this.product,
    required this.draft,
    required this.onChanged,
  });
  final ProductCatalogItem product;
  final _DraftLine? draft;
  final void Function(int qty, double unitCost) onChanged;

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  late final TextEditingController _qtyCtl;
  late final TextEditingController _costCtl;

  @override
  void initState() {
    super.initState();
    _qtyCtl = TextEditingController(
      text: widget.draft?.qty != null && widget.draft!.qty > 0
          ? '${widget.draft!.qty}'
          : '',
    );
    _costCtl = TextEditingController(
      text: widget.draft?.unitCost != null && widget.draft!.unitCost > 0
          ? widget.draft!.unitCost.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _qtyCtl.dispose();
    _costCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inCart = widget.draft != null && widget.draft!.qty > 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              inCart ? NexGenPalette.cyan.withValues(alpha: 0.4) : NexGenPalette.line,
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
                      widget.product.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.product.sku,
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (inCart)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${widget.draft!.qty} units',
                    style: TextStyle(
                      color: NexGenPalette.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Qty ordered',
                  child: TextField(
                    controller: _qtyCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: _decoration(),
                    onChanged: (_) => _emit(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Field(
                  label: 'Unit cost (\$)',
                  child: TextField(
                    controller: _costCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: _decoration(prefixText: '\$'),
                    onChanged: (_) => _emit(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _emit() {
    final qty = int.tryParse(_qtyCtl.text) ?? 0;
    final cost = double.tryParse(_costCtl.text) ?? 0.0;
    widget.onChanged(qty, cost);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SAVE BAR
// ═══════════════════════════════════════════════════════════════════════

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.notesCtl,
    required this.saving,
    required this.canSave,
    required this.lineCount,
    required this.onSave,
  });
  final TextEditingController notesCtl;
  final bool saving;
  final bool canSave;
  final int lineCount;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: notesCtl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Internal notes (optional)',
                hintStyle: TextStyle(color: NexGenPalette.textMedium),
                filled: true,
                fillColor: NexGenPalette.gunmetal90,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (canSave && !saving) ? onSave : null,
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: NexGenPalette.matteBlack,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: NexGenPalette.gunmetal90,
                  disabledForegroundColor: NexGenPalette.textMedium,
                ),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NexGenPalette.matteBlack,
                        ),
                      )
                    : Text(
                        lineCount == 0
                            ? 'Add a line item to save'
                            : 'Save PO ($lineCount line${lineCount == 1 ? '' : 's'})',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800),
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
// PRIMITIVES
// ═══════════════════════════════════════════════════════════════════════

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
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 10),
        ),
        const SizedBox(height: 3),
        child,
      ],
    );
  }
}

InputDecoration _decoration({String? prefixText}) {
  return InputDecoration(
    isDense: true,
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

String _formatShortDate(DateTime dt) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${m[dt.month - 1]} ${dt.day}';
}
