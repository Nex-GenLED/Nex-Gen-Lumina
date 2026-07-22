import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_screen.dart';

/// Per-dealer drill-down opened from a dealer card on the corporate Network
/// tab. Reuses [DealerDashboardScreen] in override mode so corporate admins
/// see the same overview, jobs, installers, and inventory tabs the dealer
/// themselves sees — without having to switch accounts.
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
    return DealerDashboardScreen(dealerCodeOverride: dealerCode);
  }
}
