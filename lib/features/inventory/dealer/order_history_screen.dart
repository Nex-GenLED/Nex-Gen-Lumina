import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nexgen_command/models/inventory/dealer_order.dart';
import 'package:nexgen_command/services/inventory/dealer_inventory_providers.dart';
import 'package:nexgen_command/services/inventory/dealer_order_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DealerOrderHistoryScreen
//
// Read-side view over /dealer_orders for the active dealer. Drafts
// are intentionally excluded — they live in the order screen.
//
// Five status tabs:
//   All        — every non-draft order
//   Pending    — submitted | payment_pending | payment_confirmed
//                (anything before processing)
//   Processing — processing
//   Shipped    — shipped
//   Received   — received
//
// Cards are tap-to-expand; expanded view shows the timeline,
// payment-required banner (for submitted/payment_pending), and
// "Mark as Received" button (for shipped). Tracking number is
// tappable and opens the carrier's tracking page.
// ─────────────────────────────────────────────────────────────────────────────

enum _HistoryTab {
  all('All', null),
  pending('Pending', _pendingStatuses),
  processing('Processing', _processingStatuses),
  shipped('Shipped', _shippedStatuses),
  received('Received', _receivedStatuses);

  final String label;
  final List<OrderStatus>? statuses;
  const _HistoryTab(this.label, this.statuses);
}

const _pendingStatuses = <OrderStatus>[
  OrderStatus.submitted,
  OrderStatus.paymentPending,
  OrderStatus.paymentConfirmed,
];
const _processingStatuses = <OrderStatus>[OrderStatus.processing];
const _shippedStatuses = <OrderStatus>[OrderStatus.shipped];
const _receivedStatuses = <OrderStatus>[OrderStatus.received];

class DealerOrderHistoryScreen extends ConsumerStatefulWidget {
  final String? dealerCodeOverride;
  const DealerOrderHistoryScreen({super.key, this.dealerCodeOverride});

  @override
  ConsumerState<DealerOrderHistoryScreen> createState() =>
      _DealerOrderHistoryScreenState();
}

class _DealerOrderHistoryScreenState
    extends ConsumerState<DealerOrderHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _HistoryTab.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dealerCode =
        widget.dealerCodeOverride ?? ref.watch(currentDealerCodeProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Order History',
            style: TextStyle(color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: NexGenPalette.cyan,
          labelColor: NexGenPalette.cyan,
          unselectedLabelColor: NexGenPalette.textMedium,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          tabs: [for (final t in _HistoryTab.values) Tab(text: t.label)],
        ),
      ),
      body: dealerCode == null
          ? const _NoSession()
          : TabBarView(
              controller: _tabController,
              children: [
                for (final t in _HistoryTab.values)
                  _OrdersList(dealerCode: dealerCode, tab: t),
              ],
            ),
    );
  }
}

class _OrdersList extends ConsumerWidget {
  const _OrdersList({required this.dealerCode, required this.tab});
  final String dealerCode;
  final _HistoryTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(dealerOrdersProvider(dealerCode));
    return ordersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('Failed to load orders: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 13)),
        ),
      ),
      data: (orders) {
        // Drafts never show in history; they live on the order screen.
        var visible = orders.where((o) => o.status != OrderStatus.draft);
        final allowed = tab.statuses;
        if (allowed != null) {
          visible = visible.where((o) => allowed.contains(o.status));
        }
        final list = visible.toList();
        if (list.isEmpty) {
          return _EmptyTab(tab: tab);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: list.length,
          itemBuilder: (context, i) =>
              _OrderCard(order: list[i], dealerCode: dealerCode),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ORDER CARD
// ═══════════════════════════════════════════════════════════════════════

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order, required this.dealerCode});
  final DealerOrder order;
  final String dealerCode;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _expanded = false;
  bool _busy = false;

  // ── Mutations ─────────────────────────────────────────────────────

  Future<void> _markPaymentSent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text("Confirm Payment Sent",
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Notify Nex-Gen that you have sent payment for order '
          '${_shortId(widget.order.orderId)}? They will confirm receipt '
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
              backgroundColor: NexGenPalette.amber,
              foregroundColor: NexGenPalette.matteBlack,
            ),
            child: const Text('Yes, payment sent'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(dealerOrderNotifierProvider)
          .markPaymentSent(widget.order.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Payment notification sent to Nex-Gen. We'll confirm receipt and begin processing your order."),
          duration: Duration(seconds: 4),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReceived() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Mark as Received?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Confirm receipt of all line items for order '
          '${_shortId(widget.order.orderId)}? '
          'This will increase your warehouse stock by '
          '${widget.order.totalUnits} units across '
          '${widget.order.lineItems.length} SKU'
          '${widget.order.lineItems.length == 1 ? '' : 's'}.',
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
              backgroundColor: NexGenPalette.green,
              foregroundColor: NexGenPalette.matteBlack,
            ),
            child: const Text('Mark Received'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // markReceived in the notifier flips status to received AND
      // adjusts /dealers/{dealerCode}/sku_inventory atomically:
      // in_warehouse += quantity_ordered, on_order -= quantity_ordered.
      await ref.read(dealerOrderNotifierProvider).markReceived(
            orderId: widget.order.orderId,
            dealerCode: widget.dealerCode,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inventory updated!'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTracking() async {
    final track = widget.order.trackingNumber;
    if (track == null || track.isEmpty) return;
    final uri = _trackingUrl(track, widget.order.shippingCarrier);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open tracking URL: $uri'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final created = order.createdAt ?? order.submittedAt;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
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
                            Text(
                              _shortId(order.orderId),
                              style: TextStyle(
                                color: NexGenPalette.textMedium,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (created != null)
                              Text(
                                _formatDate(created),
                                style: TextStyle(
                                  color: NexGenPalette.textMedium,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${order.lineItems.length} item'
                          '${order.lineItems.length == 1 ? '' : 's'} '
                          '· \$${order.subtotal.toStringAsFixed(2)} subtotal'
                          '${order.shippingCost > 0 ? ' · \$${order.shippingCost.toStringAsFixed(2)} ship' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: order.status),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: NexGenPalette.textMedium,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _ExpandedDetails(
            order: order,
            busy: _busy,
            onMarkPaymentSent: _markPaymentSent,
            onMarkReceived: _markReceived,
            onOpenTracking: _openTracking,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EXPANDED DETAILS
// ═══════════════════════════════════════════════════════════════════════

class _ExpandedDetails extends StatelessWidget {
  const _ExpandedDetails({
    required this.order,
    required this.busy,
    required this.onMarkPaymentSent,
    required this.onMarkReceived,
    required this.onOpenTracking,
  });
  final DealerOrder order;
  final bool busy;
  final VoidCallback onMarkPaymentSent;
  final VoidCallback onMarkReceived;
  final VoidCallback onOpenTracking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(color: NexGenPalette.line, height: 1),
          const SizedBox(height: 12),
          _LineItemList(order: order),
          if (order.shippingCarrier != null ||
              order.trackingNumber != null) ...[
            const SizedBox(height: 12),
            _CarrierRow(order: order, onTap: onOpenTracking),
          ],
          const SizedBox(height: 16),
          _Timeline(order: order),
          if (order.awaitingPayment) ...[
            const SizedBox(height: 16),
            _PaymentBanner(
              order: order,
              busy: busy,
              onTap: order.status == OrderStatus.submitted
                  ? onMarkPaymentSent
                  : null,
            ),
          ],
          if (order.status == OrderStatus.shipped) ...[
            const SizedBox(height: 16),
            _ReceiveButton(busy: busy, onTap: onMarkReceived),
          ],
        ],
      ),
    );
  }
}

class _LineItemList extends StatelessWidget {
  const _LineItemList({required this.order});
  final DealerOrder order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LINE ITEMS',
          style: TextStyle(
            color: NexGenPalette.textMedium,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        for (final l in order.lineItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${l.quantityOrdered} units',
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
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        const Divider(color: NexGenPalette.line, height: 16),
        Row(
          children: [
            const Expanded(
                child: Text('Subtotal',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12))),
            Text(
              '\$${order.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                order.shippingCost > 0
                    ? 'Shipping'
                    : 'Shipping (calculated by Nex-Gen)',
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 12),
              ),
            ),
            Text(
              order.shippingCost > 0
                  ? '\$${order.shippingCost.toStringAsFixed(2)}'
                  : 'TBD',
              style: TextStyle(
                color: order.shippingCost > 0
                    ? Colors.white
                    : NexGenPalette.textMedium,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (order.orderTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Expanded(
                    child: Text('Total',
                        style: TextStyle(color: Colors.white, fontSize: 13))),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CARRIER + TRACKING URL
// ═══════════════════════════════════════════════════════════════════════

class _CarrierRow extends StatelessWidget {
  const _CarrierRow({required this.order, required this.onTap});
  final DealerOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = order.trackingNumber;
    final carrier = order.shippingCarrier;
    return InkWell(
      onTap: track == null || track.isEmpty ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(
          children: [
            Icon(Icons.local_shipping_outlined,
                color: NexGenPalette.cyan, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    carrier ?? 'Carrier TBD',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    track == null || track.isEmpty
                        ? 'Tracking will appear when shipped'
                        : track,
                    style: TextStyle(
                      color: track == null || track.isEmpty
                          ? NexGenPalette.textMedium
                          : NexGenPalette.cyan,
                      fontSize: 11,
                      fontFamily:
                          track != null && track.isNotEmpty ? 'monospace' : null,
                    ),
                  ),
                ],
              ),
            ),
            if (track != null && track.isNotEmpty)
              Icon(Icons.open_in_new, size: 14, color: NexGenPalette.cyan),
          ],
        ),
      ),
    );
  }
}

/// Map carrier + tracking number to a URL. Falls back to Google
/// search when the carrier is unknown (or when the tracking number
/// shape doesn't match a known prefix).
Uri _trackingUrl(String tracking, String? carrier) {
  final encoded = Uri.encodeQueryComponent(tracking);
  switch (_inferCarrier(carrier, tracking)) {
    case _Carrier.ups:
      return Uri.parse('https://www.ups.com/track?tracknum=$encoded');
    case _Carrier.fedex:
      return Uri.parse('https://www.fedex.com/fedextrack/?trknbr=$encoded');
    case _Carrier.usps:
      return Uri.parse(
          'https://tools.usps.com/go/TrackConfirmAction?tLabels=$encoded');
    case _Carrier.unknown:
      return Uri.parse('https://www.google.com/search?q=$encoded');
  }
}

enum _Carrier { ups, fedex, usps, unknown }

_Carrier _inferCarrier(String? declared, String tracking) {
  final d = declared?.toLowerCase().trim();
  if (d != null && d.isNotEmpty) {
    if (d.contains('ups')) return _Carrier.ups;
    if (d.contains('fedex') || d.contains('fed ex')) return _Carrier.fedex;
    if (d.contains('usps') || d.contains('postal')) return _Carrier.usps;
  }
  // Best-effort prefix sniff for the common US carriers when carrier
  // wasn't filled in.
  final t = tracking.replaceAll(' ', '').toUpperCase();
  if (t.startsWith('1Z')) return _Carrier.ups;
  if (RegExp(r'^[0-9]{12}$').hasMatch(t) ||
      RegExp(r'^[0-9]{15}$').hasMatch(t)) {
    return _Carrier.fedex;
  }
  if (t.length >= 20 && RegExp(r'^[0-9]+$').hasMatch(t)) return _Carrier.usps;
  return _Carrier.unknown;
}

// ═══════════════════════════════════════════════════════════════════════
// TIMELINE
// ═══════════════════════════════════════════════════════════════════════

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});
  final DealerOrder order;

  @override
  Widget build(BuildContext context) {
    final steps = <_TimelineStepData>[
      _TimelineStepData(
        label: 'Order Submitted',
        time: order.submittedAt,
        active: order.submittedAt != null,
      ),
      _TimelineStepData(
        label: 'Payment Confirmed',
        time: order.paymentConfirmedAt,
        active: order.paymentConfirmedAt != null,
      ),
      _TimelineStepData(
        label: 'Processing',
        time: order.approvedAt,
        active: order.approvedAt != null,
      ),
      _TimelineStepData(
        label: 'Shipped',
        time: order.shippedAt,
        active: order.shippedAt != null,
        subtitle: order.trackingNumber,
      ),
      _TimelineStepData(
        label: 'Received',
        time: order.receivedAt,
        active: order.receivedAt != null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TIMELINE',
          style: TextStyle(
            color: NexGenPalette.textMedium,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _TimelineStepData {
  final String label;
  final DateTime? time;
  final bool active;
  final String? subtitle;
  const _TimelineStepData({
    required this.label,
    required this.time,
    required this.active,
    this.subtitle,
  });
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.isLast});
  final _TimelineStepData step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = step.active ? NexGenPalette.cyan : NexGenPalette.textMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.active
                    ? NexGenPalette.cyan
                    : NexGenPalette.gunmetal,
                border: Border.all(
                  color: step.active
                      ? NexGenPalette.cyan
                      : NexGenPalette.textMedium,
                  width: 2,
                ),
              ),
              child: step.active
                  ? const Icon(Icons.check,
                      size: 9, color: NexGenPalette.matteBlack)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 22,
                color: step.active
                    ? NexGenPalette.cyan.withValues(alpha: 0.4)
                    : NexGenPalette.line,
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    color: step.active ? Colors.white : NexGenPalette.textMedium,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (step.time != null)
                  Text(
                    _formatDateTime(step.time!),
                    style: TextStyle(color: color, fontSize: 11),
                  ),
                if (step.subtitle != null && step.subtitle!.isNotEmpty)
                  Text(
                    step.subtitle!,
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PAYMENT + RECEIVE BUTTONS
// ═══════════════════════════════════════════════════════════════════════

class _PaymentBanner extends StatelessWidget {
  const _PaymentBanner({
    required this.order,
    required this.busy,
    required this.onTap,
  });
  final DealerOrder order;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasShipping = order.shippingCost > 0;
    final waiting = order.status == OrderStatus.paymentPending;

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
            waiting ? 'Awaiting Payment Confirmation' : 'Payment Required',
            style: const TextStyle(
              color: NexGenPalette.amber,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (hasShipping)
            Text(
              'Order total: \$${order.orderTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            )
          else ...[
            Text(
              'Subtotal: \$${order.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '+ Shipping: TBD by Nex-Gen',
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            waiting
                ? "We've been notified that you sent payment. Once Nex-Gen confirms receipt, the order will move to processing."
                : 'Send payment via ACH, wire transfer, or check to Nex-Gen LED. Once sent, tap below to notify us.',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (!waiting) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.amber,
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
                    : const Text("I've Sent Payment",
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiveButton extends StatelessWidget {
  const _ReceiveButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onTap,
        icon: const Icon(Icons.inventory_2),
        label: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: NexGenPalette.matteBlack,
                ),
              )
            : const Text('Mark as Received',
                style: TextStyle(fontWeight: FontWeight.w800)),
        style: FilledButton.styleFrom(
          backgroundColor: NexGenPalette.green,
          foregroundColor: NexGenPalette.matteBlack,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData? icon) = _statusVisuals(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

(Color, IconData?) _statusVisuals(OrderStatus s) {
  switch (s) {
    case OrderStatus.draft:
      return (NexGenPalette.textMedium, Icons.edit_outlined);
    case OrderStatus.submitted:
      return (NexGenPalette.textMedium, null);
    case OrderStatus.paymentPending:
      return (NexGenPalette.amber, Icons.schedule);
    case OrderStatus.paymentConfirmed:
      return (NexGenPalette.cyan, Icons.verified);
    case OrderStatus.processing:
      // PULSE in palette = violet (Color(0xFF6E2FFF)).
      return (NexGenPalette.violet, Icons.autorenew);
    case OrderStatus.shipped:
      return (NexGenPalette.green, Icons.local_shipping);
    case OrderStatus.received:
      return (NexGenPalette.textMedium, Icons.check_circle);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EMPTY + NO-SESSION
// ═══════════════════════════════════════════════════════════════════════

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.tab});
  final _HistoryTab tab;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: NexGenPalette.textMedium),
            const SizedBox(height: 12),
            Text(
              tab == _HistoryTab.all
                  ? 'No orders yet.'
                  : 'No orders in ${tab.label}.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

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

// ═══════════════════════════════════════════════════════════════════════
// FORMATTERS
// ═══════════════════════════════════════════════════════════════════════

String _shortId(String orderId) {
  if (orderId.length <= 8) return orderId.toUpperCase();
  return '${orderId.substring(0, 4)}…${orderId.substring(orderId.length - 4)}'
      .toUpperCase();
}

String _formatDate(DateTime dt) {
  final m = _monthShort(dt.month);
  return '$m ${dt.day}, ${dt.year}';
}

String _formatDateTime(DateTime dt) {
  final m = _monthShort(dt.month);
  final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final ampm = dt.hour < 12 ? 'AM' : 'PM';
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$m ${dt.day} · $hour12:$mm $ampm';
}

String _monthShort(int m) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return names[m - 1];
}
