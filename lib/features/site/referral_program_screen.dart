import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class ReferralProgramScreen extends ConsumerStatefulWidget {
  const ReferralProgramScreen({super.key});

  @override
  ConsumerState<ReferralProgramScreen> createState() => _ReferralProgramScreenState();
}

class _ReferralProgramScreenState extends ConsumerState<ReferralProgramScreen> {
  final _scrollCtrl = ScrollController();
  final _rewardsKey = GlobalKey();

  String _codeFromUid(String uid) {
    final h = uid.hashCode.abs() % 1000;
    final n = h.toString().padLeft(3, '0');
    return 'LUM-$n';
  }

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
    final code = uid != null ? _codeFromUid(uid) : 'LUM-000';
    return Scaffold(
      appBar: GlassAppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: const Text('Refer & Earn'),
      ),
      body: ListView(controller: _scrollCtrl, padding: const EdgeInsets.all(16), children: [
        // Hero / Status
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.card_giftcard, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(child: Text('Ambassador Status: Silver', style: Theme.of(context).textTheme.titleMedium)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: 0.45, minHeight: 8, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4), color: NexGenPalette.cyan),
              ),
              const SizedBox(height: 6),
              Text('3 installs to reach Gold', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium)),
            ]),
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
              ])
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
                      final status = (d['status'] as String?) ?? 'Pending';
                      Color chipColor;
                      switch (status.toLowerCase()) {
                        case 'installed':
                          chipColor = Colors.greenAccent.shade400;
                          break;
                        case 'paid':
                          chipColor = NexGenPalette.cyan;
                          break;
                        default:
                          chipColor = Theme.of(context).colorScheme.onSurfaceVariant;
                      }
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(name),
                        subtitle: Text('Status: $status'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: chipColor.withValues(alpha: 0.7))),
                          child: Text(status, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: chipColor)),
                        ),
                      );
                    },
                  );
                },
              )
            ]),
          ),
        )
      ]),
    );
  }
}
