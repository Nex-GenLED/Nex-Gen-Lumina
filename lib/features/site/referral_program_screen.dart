import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/referrals/models/ambassador_tier.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/referrals/models/referral_status.dart';
import 'package:nexgen_command/features/referrals/providers/payout_providers.dart';
import 'package:nexgen_command/features/referrals/providers/referral_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reads the server-assigned referral code from the user's Firestore document.
///
/// If the user is authenticated but has no [referralCode] field (legacy users
/// created before the assignReferralCode Cloud Function was deployed, or users
/// where that function failed), this provider performs a client-side fallback:
/// it generates a fresh `LUM-XXXX` code, claims it transactionally in
/// `referral_codes/{code}`, and writes it back to `users/{uid}.referralCode`
/// using `merge: true`. This mirrors the Cloud Function logic exactly so a
/// code generated this way is fully usable for redemption.
///
/// Returns an empty string only when the user is genuinely unauthenticated.
final referralCodeProvider = FutureProvider<String>((ref) async {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) return '';

  final db = FirebaseFirestore.instance;
  final userRef = db.collection('users').doc(user.uid);
  final snap = await userRef.get();
  final existing = snap.data()?['referralCode'] as String?;
  if (existing != null && existing.isNotEmpty) return existing;

  // Fallback: generate and claim a code on the client.
  return _ensureReferralCode(user, userRef);
});

const _kReferralCodeChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const _kReferralCodeLen = 4;
const _kReferralCodeMaxAttempts = 5;

String _generateReferralCode() {
  final rng = Random.secure();
  final buf = StringBuffer('LUM-');
  for (var i = 0; i < _kReferralCodeLen; i++) {
    buf.write(_kReferralCodeChars[rng.nextInt(_kReferralCodeChars.length)]);
  }
  return buf.toString();
}

/// Mirrors the [assignReferralCode] Cloud Function: generate a `LUM-XXXX`
/// code, claim it in `referral_codes/{code}` via transaction, then write it
/// to the user doc with `merge: true`. Retries on collision up to 5 times.
Future<String> _ensureReferralCode(
  User user,
  DocumentReference<Map<String, dynamic>> userRef,
) async {
  final db = FirebaseFirestore.instance;

  for (var attempt = 0; attempt < _kReferralCodeMaxAttempts; attempt++) {
    final code = _generateReferralCode();
    final codeRef = db.collection('referral_codes').doc(code);

    try {
      await db.runTransaction((tx) async {
        final existing = await tx.get(codeRef);
        if (existing.exists) {
          throw _ReferralCodeCollision();
        }
        tx.set(codeRef, {'uid': user.uid});
        tx.set(userRef, {'referralCode': code}, SetOptions(merge: true));
      });
      return code;
    } on _ReferralCodeCollision {
      // Try again with a fresh code
      continue;
    }
  }

  throw StateError(
    'Failed to assign referral code after $_kReferralCodeMaxAttempts attempts',
  );
}

class _ReferralCodeCollision implements Exception {}

class ReferralProgramScreen extends ConsumerStatefulWidget {
  const ReferralProgramScreen({super.key});

  @override
  ConsumerState<ReferralProgramScreen> createState() => _ReferralProgramScreenState();
}

class _ReferralProgramScreenState extends ConsumerState<ReferralProgramScreen> {
  final _scrollCtrl = ScrollController();
  final _rewardsKey = GlobalKey();

  Future<void> _shareViaSms(BuildContext context, String code) async {
    final msg = Uri.encodeComponent('Check out Lumina Lighting. Use my code $code for a discount!');
    final uri = Uri.parse('sms:?body=$msg');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Messages')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).asData?.value;
    final uid = user?.uid;
    final codeAsync = ref.watch(referralCodeProvider);
    return Scaffold(
      appBar: GlassAppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: const Text('Refer & Earn'),
      ),
      body: ListView(controller: _scrollCtrl, padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)), children: [
        // Hero / Status
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ref.watch(ambassadorTierProvider).when(
              loading: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.card_giftcard, color: NexGenPalette.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(minHeight: 16, backgroundColor: NexGenPalette.gunmetal90, color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: 0, minHeight: 8, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4), color: NexGenPalette.cyan),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(minHeight: 10, backgroundColor: NexGenPalette.gunmetal90, color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                ),
              ]),
              error: (_, __) => Row(children: [
                Icon(Icons.card_giftcard, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(child: Text('Unable to load tier', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error))),
              ]),
              data: (data) {
                final nextTier = data.tier.index < AmbassadorTier.values.length - 1
                    ? AmbassadorTier.values[data.tier.index + 1]
                    : null;
                final subtitle = nextTier != null
                    ? '${data.installsToNextTier} install${data.installsToNextTier == 1 ? '' : 's'} to reach ${nextTier.label}'
                    : 'Platinum \u2014 top tier';
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.card_giftcard, color: data.tier.color),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Ambassador Status: ${data.tier.label}', style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(value: data.progressToNextTier, minHeight: 8, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4), color: data.tier.color),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium)),
                ]);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Code box
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your Code', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              codeAsync.when(
                loading: () => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal90,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                  child: Row(children: [
                    Icon(Icons.redeem, color: NexGenPalette.cyan),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 20,
                          backgroundColor: NexGenPalette.gunmetal90,
                          color: NexGenPalette.cyan.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ]),
                ),
                error: (_, __) => Row(children: [
                  Expanded(
                    child: Text(
                      'Unable to load referral code. Pull to refresh or try again.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry',
                    onPressed: () => ref.invalidate(referralCodeProvider),
                  ),
                ]),
                data: (code) {
                  if (code.isEmpty) {
                    // Only reached when the user is genuinely unauthenticated
                    // (the auth-stream hasn't resolved or the user is signed out).
                    // Authenticated users with a missing referralCode field are
                    // handled by the client-side fallback in referralCodeProvider.
                    return Text('Sign in to get your referral code', style: Theme.of(context).textTheme.bodyMedium);
                  }
                  return Column(children: [
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        decoration: BoxDecoration(
                          color: NexGenPalette.gunmetal90,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: NexGenPalette.line),
                        ),
                        child: Row(children: [
                          Icon(Icons.redeem, color: NexGenPalette.cyan),
                          const SizedBox(width: 12),
                          Expanded(child: Text(code, style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 1.5))),
                          const SizedBox(width: 12),
                          Icon(Icons.copy, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: FilledButton.icon(onPressed: () => _shareViaSms(context, code), icon: const Icon(Icons.sms_rounded), label: const Text('Share via Text'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Scrollable.ensureVisible(_rewardsKey.currentContext!, duration: const Duration(milliseconds: 300));
                          },
                          icon: const Icon(Icons.trending_up),
                          label: const Text('Track Rewards'),
                        ),
                      ),
                    ]),
                  ]);
                },
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        // Rewards list
        Card(
          key: _rewardsKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.emoji_events_outlined, color: NexGenPalette.violet),
                const SizedBox(width: 8),
                Expanded(child: Text('Rewards Tracking', style: Theme.of(context).textTheme.titleMedium)),
              ]),
              const SizedBox(height: 8),
              if (uid == null) Text('Sign in to track referrals', style: Theme.of(context).textTheme.bodyMedium)
              else StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('referrals').orderBy('created_at', descending: true).snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)));
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) return Text('No referrals yet. Share your code to get started.', style: Theme.of(context).textTheme.bodyMedium);
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      final name = (d['name'] as String?) ?? 'Friend';
                      final statusStr = (d['status'] as String?) ?? 'lead';
                      final status = ReferralStatusX.fromString(statusStr);
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(name),
                          subtitle: Text('Status: ${status.label}'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: status.color.withValues(alpha: 0.7))),
                            child: Text(status.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: status.color)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(1),
                            child: LinearProgressIndicator(
                              value: status.progressFraction,
                              minHeight: 2,
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              color: status.color,
                            ),
                          ),
                        ),
                      ]);
                    },
                  );
                },
              )
            ]),
          ),
        ),

        // ── Your Rewards section ──────────────────────────────────
        if (uid != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.monetization_on, color: NexGenPalette.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Your Rewards', style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 12),

                  // YTD GC summary
                  ref.watch(ytdGcTotalProvider(uid)).when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (ytd) {
                      final progress = (ytd / RewardTiers.annualGcCap).clamp(0.0, 1.0);
                      final barColor = ytd > 500 ? Colors.red : NexGenPalette.amber;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Visa gift cards this year: \$${ytd.toStringAsFixed(0)} of \$${RewardTiers.annualGcCap.toStringAsFixed(0)}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              color: barColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    },
                  ),

                  // Payouts list
                  ref.watch(myPayoutsProvider(uid)).when(
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (_, __) => Text('Unable to load rewards', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    data: (payouts) {
                      if (payouts.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Rewards appear here after your referral\'s install is complete',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textMedium),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: payouts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _buildPayoutRow(context, payouts[i]),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],

        // ── Disclosure ──────────────────────────────────────────
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Referral rewards are subject to approval by your local Nex-Gen '
            'dealer. Visa gift card rewards are limited to \$599 per calendar '
            'year per participant. Nex-Gen credit has no annual limit and may '
            'be applied toward future equipment or installation. Rewards are '
            'issued upon verified installation completion.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, height: 1.4),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildPayoutRow(BuildContext context, ReferralPayout payout) {
    final statusColor = switch (payout.status) {
      RewardPayoutStatus.pending => NexGenPalette.amber,
      RewardPayoutStatus.approved => NexGenPalette.cyan,
      RewardPayoutStatus.fulfilled => NexGenPalette.green,
      RewardPayoutStatus.gcCapReached => Colors.grey,
    };
    final rewardColor = payout.rewardType == RewardType.nexGenCredit
        ? NexGenPalette.cyan
        : NexGenPalette.amber;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(payout.prospectName, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          Text('\$${payout.rewardAmountUsd.toStringAsFixed(0)}', style: TextStyle(color: rewardColor, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: rewardColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              payout.rewardType == RewardType.visaGiftCard ? 'GC' : 'Credit',
              style: TextStyle(color: rewardColor, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(payout.status.label, style: TextStyle(color: statusColor, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
