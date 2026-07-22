import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/referrals/providers/payout_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Dealer/admin payout approval screen.
class PayoutApprovalScreen extends ConsumerStatefulWidget {
  const PayoutApprovalScreen({super.key});

  @override
  ConsumerState<PayoutApprovalScreen> createState() => _PayoutApprovalScreenState();
}

class _PayoutApprovalScreenState extends ConsumerState<PayoutApprovalScreen> {
  String _filter = 'pending'; // pending | approved | fulfilled | all

  @override
  Widget build(BuildContext context) {
    final payoutsAsync = ref.watch(pendingPayoutsProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Referral Rewards'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Review and approve pending payouts',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          _buildFilterRow(),
          const SizedBox(height: 12),
          Expanded(
            child: payoutsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
              data: (payouts) {
                final filtered = _applyFilter(payouts);
                if (filtered.isEmpty) return _buildEmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _PayoutCard(
                    payout: filtered[i],
                    onApprove: () => _showApproveSheet(filtered[i]),
                    onDecline: () => _confirmDecline(filtered[i]),
                    onFulfill: () => _markFulfilled(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ReferralPayout> _applyFilter(List<ReferralPayout> payouts) {
    if (_filter == 'all') return payouts;
    return payouts.where((p) => p.status.name == _filter).toList();
  }

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _filterPill('pending', 'Pending'),
          _filterPill('approved', 'Approved'),
          _filterPill('fulfilled', 'Fulfilled'),
          _filterPill('all', 'All'),
        ],
      ),
    );
  }

  Widget _filterPill(String value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? NexGenPalette.cyan.withValues(alpha: 0.15) : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? NexGenPalette.cyan : NexGenPalette.line),
          ),
          child: Text(label, style: TextStyle(
            color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          )),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 56, color: NexGenPalette.green.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No pending rewards', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
        ],
      ),
    );
  }

  Future<void> _showApproveSheet(ReferralPayout payout) async {
    final noteCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Confirm approval', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(payout.referrerUid).get(),
                builder: (_, snap) {
                  final name = snap.data?.data() is Map ? (snap.data!.data() as Map)['display_name'] ?? 'Referrer' : 'Referrer';
                  return Text('Referrer: $name', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14));
                },
              ),
              const SizedBox(height: 4),
              Text('Reward: ${payout.rewardType.label} — \$${payout.rewardAmountUsd.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 16),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Fulfillment note (optional)',
                  labelStyle: const TextStyle(color: NexGenPalette.textMedium),
                  hintText: 'e.g. card sent via email',
                  hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: NexGenPalette.gunmetal90,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _approvePayout(payout, noteCtrl.text.trim());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm approval', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
    noteCtrl.dispose();
  }

  Future<void> _approvePayout(ReferralPayout payout, String note) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseFirestore.instance
          .collection('referral_payouts')
          .doc(payout.id)
          .update({
        'status': 'approved',
        'approvedByUid': uid,
        'approvedAt': FieldValue.serverTimestamp(),
        if (note.isNotEmpty) 'fulfillmentNote': note,
      });

      // Notify referrer via Cloud Function
      try {
        final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
        final callable = functions.httpsCallable('notifyReferrerOfApproval');
        await callable.call({'payoutId': payout.id});
      } catch (e) {
        debugPrint('Referrer notification failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Reward approved — referrer will be notified'), backgroundColor: NexGenPalette.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to approve: $e')));
      }
    }
  }

  Future<void> _confirmDecline(ReferralPayout payout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Decline reward?', style: TextStyle(color: Colors.white)),
        content: Text('This will remove the pending reward for ${payout.prospectName}.', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Decline', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('referral_payouts').doc(payout.id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reward declined')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  Future<void> _markFulfilled(ReferralPayout payout) async {
    try {
      await FirebaseFirestore.instance.collection('referral_payouts').doc(payout.id).update({
        'status': 'fulfilled',
        'fulfilledAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

// ── Payout card ──────────────────────────────────────────────

class _PayoutCard extends StatelessWidget {
  final ReferralPayout payout;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final VoidCallback onFulfill;

  const _PayoutCard({
    required this.payout,
    required this.onApprove,
    required this.onDecline,
    required this.onFulfill,
  });

  Color _statusColor(RewardPayoutStatus s) => switch (s) {
    RewardPayoutStatus.pending => NexGenPalette.amber,
    RewardPayoutStatus.approved => NexGenPalette.cyan,
    RewardPayoutStatus.fulfilled => NexGenPalette.green,
    RewardPayoutStatus.gcCapReached => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(payout.status);
    final rewardColor = payout.rewardType == RewardType.nexGenCredit
        ? NexGenPalette.cyan
        : NexGenPalette.amber;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Prospect name + job number
          Row(
            children: [
              Expanded(child: Text(payout.prospectName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
              Text(payout.jobNumber, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Referrer name (async lookup)
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(payout.referrerUid).get(),
            builder: (_, snap) {
              final name = snap.data?.data() is Map
                  ? (snap.data!.data() as Map)['display_name'] ?? payout.referrerUid.substring(0, 8)
                  : payout.referrerUid.length > 8 ? '${payout.referrerUid.substring(0, 8)}...' : payout.referrerUid;
              return Text('Referred by: $name', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13));
            },
          ),
          const SizedBox(height: 8),

          // Row 3: Install value + tier
          Row(
            children: [
              Text('\$${payout.installValueUsd.toStringAsFixed(0)} install', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: NexGenPalette.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '\$${payout.tier.installValueMin.toStringAsFixed(0)}–\$${payout.tier.installValueMax.isFinite ? payout.tier.installValueMax.toStringAsFixed(0) : '∞'} tier',
                  style: TextStyle(color: NexGenPalette.violet, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 4: Reward type pill + amount + GC cap
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rewardColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rewardColor.withValues(alpha: 0.3)),
                ),
                child: Text(payout.rewardType.label, style: TextStyle(color: rewardColor, fontSize: 11, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 10),
              Text('\$${payout.rewardAmountUsd.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              if (payout.gcCapApplied) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('GC cap reached', style: TextStyle(color: Colors.red, fontSize: 10)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Row 5: Status pill + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(payout.status.label, style: TextStyle(color: statusColor, fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Text(
                '${payout.createdAt.month}/${payout.createdAt.day}/${payout.createdAt.year}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
              ),
            ],
          ),

          // Row 6: Actions
          if (payout.status == RewardPayoutStatus.pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Approve', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onDecline,
                  child: Text('Decline', style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ],
            ),
          ],
          if (payout.status == RewardPayoutStatus.approved) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onFulfill,
                child: Text('Mark as fulfilled', style: TextStyle(color: NexGenPalette.green, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
