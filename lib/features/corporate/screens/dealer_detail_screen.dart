import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';

/// Stub dealer detail screen — opened from a dealer card on the corporate
/// Network tab. Shows minimal info today; will be fleshed out in a later
/// step with per-dealer drill-down (jobs, installers, inventory).
class DealerDetailScreen extends ConsumerWidget {
  const DealerDetailScreen({
    super.key,
    required this.dealerCode,
    this.dealerName,
  });

  final String dealerCode;
  final String? dealerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          dealerName?.isNotEmpty == true ? dealerName! : 'Dealer $dealerCode',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.gold.withValues(alpha: 0.15),
                  border: Border.all(
                      color: NexGenPalette.gold.withValues(alpha: 0.5)),
                ),
                child: const Icon(
                  Icons.store_outlined,
                  color: NexGenPalette.gold,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                dealerName?.isNotEmpty == true
                    ? dealerName!
                    : 'Dealer $dealerCode',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Code: $dealerCode',
                style:
                    TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Text(
                  'Detail view coming soon',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
