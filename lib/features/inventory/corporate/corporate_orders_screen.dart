import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/dealer_order.dart';
import 'package:nexgen_command/services/inventory/corporate_providers.dart';
import 'package:nexgen_command/services/inventory/dealer_order_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CorporateOrdersScreen
//
// Corporate-side inbox over /dealer_orders. Five tabs:
//   Pending Review  — submitted (waiting for Tyler's review)
//   Payment Pending — payment_pending (waiting for dealer payment OR
//                     dealer reports paid, awaiting confirmation)
//   Processing      — payment_confirmed | processing (ready to ship)
//   Shipped         — shipped
//   All             — every non-draft order
//
// Each card opens a full-screen detail sheet that exposes the
// status-specific action (approve, reject, confirm payment, mark
// shipped) inline — no separate routes per action. The Approve flow
// is the only one with non-trivial validation (shipping cost > 0).
//
// Read-write surface for all flows is DealerOrderNotifier
// (lib/services/inventory/dealer_order_providers.dart). Corporate
// inventory adjustments (Tyler's spec — decrement reserved_for_orders
// on approve) are written via a Firestore batch alongside the
// order-status update so the two stay atomic. See _approveOrder for
// the semantics caveat.
// ─────────────────────────────────────────────────────────────────────────────

class CorporateOrdersScreen extends ConsumerStatefulWidget {
  const CorporateOrdersScreen({super.key});

  @override
  ConsumerState<CorporateOrdersScreen> createState() =>
      _CorporateOrdersScreenState();
}

enum _CorpTab {
  pendingReview('Pending Review', _pending),
  paymentPending('Payment Pending', _paymentPending),
  processing('Processing', _processing),
  shipped('Shipped', _shipped),
  all('All', null);

  final String label;
  final List<OrderStatus>? statuses;
  const _CorpTab(this.label, this.statuses);
}

const _pending = <OrderStatus>[OrderStatus.submitted];
const _paymentPending = <OrderStatus>[OrderStatus.paymentPending];
const _processing = <OrderStatus>[
  OrderStatus.paymentConfirmed,
  OrderStatus.processing,
];
const _shipped = <OrderStatus>[OrderStatus.shipped];

class _CorporateOrdersScreenState extends ConsumerState<CorporateOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _CorpTab.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(pendingReviewCountProvider);

    return Column(
      children: [
        // Tab bar — pendingReview shows a count badge so Tyler knows
        // how many orders need attention without entering the tab.
        Container(
          color: NexGenPalette.gunmetal,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: NexGenPalette.cyan,
            labelColor: NexGenPalette.cyan,
            unselectedLabelColor: NexGenPalette.textMedium,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            tabs: [
              for (final t in _CorpTab.values)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.label),
                      if (t == _CorpTab.pendingReview && pendingCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$pendingCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final t in _CorpTab.values) _OrderTabList(tab: t),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderTabList extends ConsumerWidget {
  const _OrderTabList({required this.tab});
  final _CorpTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(allDealerOrdersProvider);
    return ordersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Failed to load orders: $e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
      data: (orders) {
        var visible = orders.where((o) => o.status != OrderStatus.draft);
        final allowed = tab.statuses;
        if (allowed != null) {
          visible = visible.where((o) => allowed.contains(o.status));
        }
        final list = visible.toList();
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 48, color: NexGenPalette.textMedium),
                  const SizedBox(height: 12),
                  Text(
                    'No orders in ${tab.label}.',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: list.length,
          itemBuilder: (context, i) => _OrderListCard(order: list[i]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LIST CARD
// ═══════════════════════════════════════════════════════════════════════

class _OrderListCard extends StatelessWidget {
  const _OrderListCard({required this.order});
  final DealerOrder order;

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt ?? order.submittedAt;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => _OrderDetailScreen(order: order),
          )),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order.dealerName.isEmpty
                                  ? 'Dealer ${order.dealerCode}'
                                  : order.dealerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: NexGenPalette.violet
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              order.dealerCode,
                              style: TextStyle(
                                color: NexGenPalette.violet,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${order.lineItems.length} item'
                        '${order.lineItems.length == 1 ? '' : 's'} · '
                        '\$${order.subtotal.toStringAsFixed(2)} subtotal'
                        '${created != null ? ' · ${_formatDate(created)}' : ''}',
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(status: order.status, paymentStatus: order.paymentStatus),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    color: NexGenPalette.textMedium, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.paymentStatus});
  final OrderStatus status;
  final String paymentStatus;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _pillVisuals(status, paymentStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

(String, Color) _pillVisuals(OrderStatus status, String paymentStatus) {
  switch (status) {
    case OrderStatus.submitted:
      return ('Needs Review', Colors.red);
    case OrderStatus.paymentPending:
      return paymentStatus == 'sent'
          ? ('Confirm Payment', NexGenPalette.amber)
          : ('Awaiting Payment', NexGenPalette.amber);
    case OrderStatus.paymentConfirmed:
      return ('Ready to Ship', NexGenPalette.cyan);
    case OrderStatus.processing:
      return ('Processing', NexGenPalette.violet);
    case OrderStatus.shipped:
      return ('Shipped', NexGenPalette.green);
    case OrderStatus.received:
      return ('Received', NexGenPalette.textMedium);
    case OrderStatus.draft:
      return ('Draft', NexGenPalette.textMedium);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════

/// Full-screen modal that shows everything Tyler needs to act on a
/// single order. Uses a StreamBuilder over the order doc directly so
/// the screen reflects state changes live (e.g. dealer updates notes
/// while Tyler is reviewing).
class _OrderDetailScreen extends ConsumerStatefulWidget {
  const _OrderDetailScreen({required this.order});
  final DealerOrder order;

  @override
  ConsumerState<_OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<_OrderDetailScreen> {
  final _shippingCostCtl = TextEditingController();
  final _carrierCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _trackingCtl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _shippingCostCtl.text = widget.order.shippingCost > 0
        ? widget.order.shippingCost.toStringAsFixed(2)
        : '';
    _carrierCtl.text = widget.order.shippingCarrier ?? '';
    _trackingCtl.text = widget.order.trackingNumber ?? '';
  }

  @override
  void dispose() {
    _shippingCostCtl.dispose();
    _carrierCtl.dispose();
    _notesCtl.dispose();
    _trackingCtl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────

  Future<void> _approve(DealerOrder order) async {
    final raw = _shippingCostCtl.text.trim();
    final cost = double.tryParse(raw);
    if (cost == null || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a shipping cost greater than \$0 to approve.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    setState(() => _busy = true);
    try {
      // 1) Order-side approval — sets shipping_cost, order_total,
      //    status, approved_by/at via the notifier.
      await ref.read(dealerOrderNotifierProvider).approveWithShipping(
            orderId: order.orderId,
            shippingCost: cost,
            shippingCarrier:
                _carrierCtl.text.trim().isEmpty ? null : _carrierCtl.text.trim(),
            approvedBy: uid,
          );

      // 2) Append corporate notes if Tyler wrote any. Notes can live
      //    on the order alongside the dealer's notes — the rule
      //    layer doesn't distinguish authorship.
      final notes = _notesCtl.text.trim();
      if (notes.isNotEmpty) {
        await ref
            .read(dealerOrderNotifierProvider)
            .updateNotes(orderId: order.orderId, notes: notes);
      }

      // 3) Corporate inventory: approve commits stock to this dealer
      //    order, so reserved_for_orders increments by the line qty.
      //    available = on_hand - reserved_for_orders, so this
      //    correctly reduces available stock for new orders. The
      //    matching decrement happens at ship time when stock
      //    physically leaves the warehouse.
      final batch = FirebaseFirestore.instance.batch();
      for (final line in order.lineItems) {
        final invRef = FirebaseFirestore.instance
            .collection('corporate_inventory')
            .doc(line.sku);
        batch.set(
          invRef,
          {
            'sku': line.sku,
            'reserved_for_orders':
                FieldValue.increment(line.quantityOrdered),
            'last_updated': Timestamp.now(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order approved — dealer notified to send payment'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approve failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reject(DealerOrder order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctl = TextEditingController();
        return AlertDialog(
          backgroundColor: NexGenPalette.gunmetal,
          title: const Text('Reject Order',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Reason for rejection (required)',
              hintStyle: TextStyle(color: NexGenPalette.textMedium),
              filled: true,
              fillColor: NexGenPalette.gunmetal90,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final txt = ctl.text.trim();
                if (txt.isEmpty) return;
                Navigator.of(ctx).pop(txt);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reject Order'),
            ),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(dealerOrderNotifierProvider).rejectOrder(
            orderId: order.orderId,
            reason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order returned to dealer'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmPayment(DealerOrder order) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    setState(() => _busy = true);
    try {
      await ref.read(dealerOrderNotifierProvider).confirmPayment(
            orderId: order.orderId,
            confirmedBy: uid,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed — order is now processing'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirm failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markShipped(DealerOrder order) async {
    final tracking = _trackingCtl.text.trim();
    final carrier = _carrierCtl.text.trim();
    if (tracking.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a tracking number to mark the order shipped.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dealerOrderNotifierProvider).markShipped(
            orderId: order.orderId,
            trackingNumber: tracking,
            carrier: carrier.isEmpty ? null : carrier,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order marked as shipped'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mark shipped failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.order.dealerName.isEmpty
              ? 'Dealer ${widget.order.dealerCode}'
              : widget.order.dealerName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      // Live stream so external state changes (dealer marks payment
      // sent while Tyler is reviewing, etc.) update the UI.
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('dealer_orders')
            .doc(widget.order.orderId)
            .snapshots(),
        builder: (context, snap) {
          DealerOrder live = widget.order;
          if (snap.hasData && snap.data!.exists) {
            live = DealerOrder.fromJson(snap.data!.data()!);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DealerInfoCard(order: live),
              const SizedBox(height: 12),
              _ShippingAddressCard(dealerCode: live.dealerCode),
              const SizedBox(height: 12),
              _LineItemsCard(order: live),
              const SizedBox(height: 16),
              ..._actionSection(context, live),
            ],
          );
        },
      ),
    );
  }

  /// Status-specific action UI. Each branch is self-contained so the
  /// status state machine stays visible from the top of the function.
  List<Widget> _actionSection(BuildContext context, DealerOrder live) {
    switch (live.status) {
      case OrderStatus.submitted:
        return [
          _SectionHeader('Approve / Reject'),
          const SizedBox(height: 8),
          _ApproveForm(
            shippingCostCtl: _shippingCostCtl,
            carrierCtl: _carrierCtl,
            notesCtl: _notesCtl,
            busy: _busy,
            onApprove: () => _approve(live),
            onReject: () => _reject(live),
          ),
        ];

      case OrderStatus.paymentPending:
        return [
          _SectionHeader('Payment'),
          const SizedBox(height: 8),
          _PaymentSection(
            order: live,
            busy: _busy,
            onConfirm: () => _confirmPayment(live),
          ),
        ];

      case OrderStatus.paymentConfirmed:
      case OrderStatus.processing:
        return [
          _SectionHeader('Shipping'),
          const SizedBox(height: 8),
          _ShipForm(
            carrierCtl: _carrierCtl,
            trackingCtl: _trackingCtl,
            busy: _busy,
            onMarkShipped: () => _markShipped(live),
          ),
        ];

      case OrderStatus.shipped:
        return [
          _SectionHeader('Shipped'),
          const SizedBox(height: 8),
          _ShippedReadOnly(order: live),
        ];

      case OrderStatus.received:
      case OrderStatus.draft:
        return const [];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DETAIL CARDS
// ═══════════════════════════════════════════════════════════════════════

class _DealerInfoCard extends StatelessWidget {
  const _DealerInfoCard({required this.order});
  final DealerOrder order;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.dealerName.isEmpty
                      ? 'Dealer ${order.dealerCode}'
                      : order.dealerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(
                  status: order.status, paymentStatus: order.paymentStatus),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dealer code ${order.dealerCode}'
            '${order.submittedAt != null ? ' · submitted ${_formatDate(order.submittedAt!)}' : ''}',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
          ),
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                order.notes!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShippingAddressCard extends StatelessWidget {
  const _ShippingAddressCard({required this.dealerCode});
  final String dealerCode;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('dealers')
            .doc(dealerCode)
            .collection('shipping_address')
            .doc('primary')
            .snapshots(),
        builder: (context, snap) {
          final addr = snap.data?.data();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Ship To',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (addr == null)
                Text(
                  'No shipping address on file for this dealer',
                  style: TextStyle(
                    color: NexGenPalette.amber,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Text(
                  _formatAddress(addr),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatAddress(Map<String, dynamic> a) {
    final lines = <String>[
      if ((a['company_name'] as String?)?.isNotEmpty == true)
        '${a['company_name']}',
      if ((a['attention'] as String?)?.isNotEmpty == true)
        'ATTN: ${a['attention']}',
      if ((a['address_line_1'] as String?)?.isNotEmpty == true)
        '${a['address_line_1']}',
      if ((a['address_line_2'] as String?)?.isNotEmpty == true)
        '${a['address_line_2']}',
      [
        a['city'],
        a['state'],
        a['zip'],
      ]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(', ')
          .replaceAllMapped(
            RegExp(r'^(.+), ([A-Z]{2}), (\d.*)$'),
            (m) => '${m[1]}, ${m[2]} ${m[3]}',
          ),
      if ((a['phone'] as String?)?.isNotEmpty == true) '${a['phone']}',
    ];
    return lines.where((l) => l.isNotEmpty).join('\n');
  }
}

class _LineItemsCard extends StatelessWidget {
  const _LineItemsCard({required this.order});
  final DealerOrder order;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LINE ITEMS (${order.lineItems.length})',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          for (final l in order.lineItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l.sku,
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${l.quantityOrdered} u',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '\$${l.lineTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: NexGenPalette.line, height: 18),
          _kv('Subtotal', '\$${order.subtotal.toStringAsFixed(2)}'),
          _kv(
            'Shipping',
            order.shippingCost > 0
                ? '\$${order.shippingCost.toStringAsFixed(2)}'
                : 'TBD',
            valueColor: order.shippingCost > 0
                ? Colors.white
                : NexGenPalette.textMedium,
          ),
          if (order.orderTotal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Order total',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '\$${order.orderTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: NexGenPalette.cyan,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
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

Widget _kv(String k, String v, {Color valueColor = Colors.white}) {
  return Row(
    children: [
      Expanded(
        child: Text(
          k,
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
        ),
      ),
      Text(
        v,
        style: TextStyle(
          color: valueColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════
// ACTION SECTIONS
// ═══════════════════════════════════════════════════════════════════════

class _ApproveForm extends StatelessWidget {
  const _ApproveForm({
    required this.shippingCostCtl,
    required this.carrierCtl,
    required this.notesCtl,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });
  final TextEditingController shippingCostCtl;
  final TextEditingController carrierCtl;
  final TextEditingController notesCtl;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TODO: Replace manual shipping entry with Shippo API rate
          // selection (Tyler has a Shippo account; integration is
          // out of scope for this sprint).
          _Field(
            label: 'Shipping cost (\$)',
            child: TextField(
              controller: shippingCostCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(prefixText: '\$'),
            ),
          ),
          const SizedBox(height: 8),
          _Field(
            label: 'Carrier (optional)',
            child: TextField(
              controller: carrierCtl,
              style: const TextStyle(color: Colors.white),
              decoration:
                  _fieldDecoration(hintText: 'UPS, FedEx, USPS, …'),
            ),
          ),
          const SizedBox(height: 8),
          _Field(
            label: 'Notes (optional, visible to dealer)',
            child: TextField(
              controller: notesCtl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Reject Order',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: NexGenPalette.matteBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NexGenPalette.matteBlack,
                          ),
                        )
                      : const Text('Approve Order',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.order,
    required this.busy,
    required this.onConfirm,
  });
  final DealerOrder order;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final dealerNotified = order.paymentStatus == 'sent';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dealerNotified
                ? 'Payment Notification Received'
                : 'Awaiting Dealer Payment',
            style: const TextStyle(
              color: NexGenPalette.amber,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dealerNotified
                ? 'Dealer reports payment sent for \$${order.orderTotal.toStringAsFixed(2)}'
                : 'Order approved at \$${order.orderTotal.toStringAsFixed(2)}. Waiting for dealer to send payment.',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (dealerNotified)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.green,
                  foregroundColor: NexGenPalette.matteBlack,
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NexGenPalette.matteBlack,
                        ),
                      )
                    : const Text('Confirm Payment Received',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShipForm extends StatelessWidget {
  const _ShipForm({
    required this.carrierCtl,
    required this.trackingCtl,
    required this.busy,
    required this.onMarkShipped,
  });
  final TextEditingController carrierCtl;
  final TextEditingController trackingCtl;
  final bool busy;
  final VoidCallback onMarkShipped;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: 'Carrier',
            child: TextField(
              controller: carrierCtl,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(hintText: 'UPS, FedEx, USPS, …'),
            ),
          ),
          const SizedBox(height: 8),
          _Field(
            label: 'Tracking number',
            child: TextField(
              controller: trackingCtl,
              style: const TextStyle(color: Colors.white),
              decoration:
                  _fieldDecoration(hintText: 'Tracking number from carrier'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onMarkShipped,
              icon: const Icon(Icons.local_shipping_outlined),
              label: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NexGenPalette.matteBlack,
                      ),
                    )
                  : const Text('Mark as Shipped',
                      style: TextStyle(fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.green,
                foregroundColor: NexGenPalette.matteBlack,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShippedReadOnly extends StatelessWidget {
  const _ShippedReadOnly({required this.order});
  final DealerOrder order;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle,
                  color: NexGenPalette.green, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Order shipped',
                style: TextStyle(
                  color: NexGenPalette.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (order.shippingCarrier != null)
            Text(
              'Carrier: ${order.shippingCarrier}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          if (order.trackingNumber != null)
            Text(
              'Tracking: ${order.trackingNumber}',
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          if (order.shippedAt != null)
            Text(
              'Shipped ${_formatDate(order.shippedAt!)}',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRIMITIVES
// ═══════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: child,
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

InputDecoration _fieldDecoration({String? hintText, String? prefixText}) {
  return InputDecoration(
    isDense: true,
    hintText: hintText,
    hintStyle: TextStyle(color: NexGenPalette.textMedium),
    prefixText: prefixText,
    prefixStyle: const TextStyle(color: Colors.white),
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
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
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

String _formatDate(DateTime dt) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
}
