import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/corporate/models/corporate_session.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_network_providers.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_providers.dart';
import 'package:nexgen_command/features/corporate/screens/corporate_admin_screen.dart';
import 'package:nexgen_command/features/corporate/screens/corporate_pipeline_screen.dart';
import 'package:nexgen_command/features/corporate/screens/corporate_warehouse_screen.dart';
import 'package:nexgen_command/theme.dart';

/// Manual whole-dollar currency formatter — matches NumberFormat
/// `simpleCurrency(decimalDigits: 0)` without depending on `intl`.
String _formatUsd(double value) {
  final whole = value.round();
  final s = whole.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${whole < 0 ? '-' : ''}\$${buf.toString()}';
}

/// Top-level corporate dashboard.
///
/// Gated behind [corporateModeActiveProvider] — bounces to
/// [AppRoutes.corporatePin] if no session is active. Hosts a TabBar with
/// Network / Pipeline / Warehouse / Admin tabs. The Network tab is live;
/// the others are stubbed and will be filled in by subsequent steps.
class CorporateDashboardScreen extends ConsumerStatefulWidget {
  const CorporateDashboardScreen({super.key});

  @override
  ConsumerState<CorporateDashboardScreen> createState() =>
      _CorporateDashboardScreenState();
}

class _CorporateDashboardScreenState
    extends ConsumerState<CorporateDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Bounce to PIN screen if no session — done after first frame so we
    // can use GoRouter without breaking the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasSession = ref.read(corporateModeActiveProvider);
      if (!hasSession) {
        context.go(AppRoutes.corporatePin);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(corporateSessionProvider);

    if (session == null) {
      // Render an empty scaffold while the post-frame redirect runs.
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(
          child: CircularProgressIndicator(color: NexGenPalette.gold),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Corporate',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            Text(
              session.displayName,
              style: TextStyle(
                color: NexGenPalette.gold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: NexGenPalette.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: NexGenPalette.gold.withValues(alpha: 0.5)),
            ),
            child: Text(
              session.role.label,
              style: const TextStyle(
                color: NexGenPalette.gold,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              ref.read(corporateModeProvider.notifier).signOut();
              context.go(AppRoutes.corporatePin);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: NexGenPalette.gold,
          indicatorWeight: 2,
          labelColor: NexGenPalette.gold,
          unselectedLabelColor: NexGenPalette.textMedium,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Network'),
            Tab(text: 'Pipeline'),
            Tab(text: 'Warehouse'),
            Tab(text: 'Admin'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _NetworkTab(),
          CorporatePipelineScreen(),
          CorporateWarehouseScreen(),
          CorporateAdminScreen(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NETWORK TAB
// ═══════════════════════════════════════════════════════════════════════

class _NetworkTab extends ConsumerWidget {
  const _NetworkTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(corporateNetworkStatsProvider);
    final summariesAsync = ref.watch(corporateDealerSummariesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header metrics ──
          _StatCardsRow(statsAsync: statsAsync),
          const SizedBox(height: 24),

          // ── Section header ──
          Row(
            children: [
              const Text(
                'Dealer Network',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              summariesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => Text(
                  '${list.length} dealers',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Dealer cards ──
          summariesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: CircularProgressIndicator(color: NexGenPalette.gold)),
            ),
            error: (e, _) => _ErrorBox(message: 'Failed to load dealers: $e'),
            data: (summaries) {
              if (summaries.isEmpty) {
                return _EmptyBox(
                  icon: Icons.store_outlined,
                  message: 'No dealers registered yet.',
                );
              }
              return Column(
                children: summaries
                    .map((s) => _DealerCard(summary: s))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatCardsRow extends StatelessWidget {
  const _StatCardsRow({required this.statsAsync});
  final AsyncValue<CorporateNetworkStats> statsAsync;

  @override
  Widget build(BuildContext context) {
    return statsAsync.when(
      loading: () => const SizedBox(
        height: 100,
        child: Center(
            child: CircularProgressIndicator(color: NexGenPalette.gold)),
      ),
      error: (e, _) => _ErrorBox(message: 'Stats unavailable: $e'),
      data: (s) {
        return SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _StatCard(
                label: 'Active dealers',
                value: '${s.totalActiveDealers}',
                icon: Icons.store_mall_directory_outlined,
                color: NexGenPalette.cyan,
              ),
              _StatCard(
                label: 'Jobs this month',
                value: '${s.totalJobsThisMonth}',
                icon: Icons.work_outline,
                color: NexGenPalette.violet,
              ),
              _StatCard(
                label: 'Revenue this month',
                value: _formatUsd(s.totalRevenueThisMonth),
                icon: Icons.attach_money,
                color: NexGenPalette.green,
              ),
              _StatCard(
                label: 'Avg job value',
                value: _formatUsd(s.averageJobValueThisMonth),
                icon: Icons.trending_up,
                color: NexGenPalette.gold,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DealerCard extends StatelessWidget {
  const _DealerCard({required this.summary});
  final DealerNetworkSummary summary;

  String _lastJobLabel() {
    final last = summary.lastJobCreatedAt;
    if (last == null) return 'No jobs yet';
    final diff = DateTime.now().difference(last);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    final dealer = summary.dealer;
    final displayName =
        dealer.companyName.isNotEmpty ? dealer.companyName : dealer.dealerCode;
    final health = summary.health;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            context.push(
              '${AppRoutes.corporateDealerDetailBase}/${dealer.dealerCode}',
              extra: displayName,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Composite-score health dot. Maps the 0..1 score to
                    // green/amber/red so the network tab gives an at-a-glance
                    // sense of which dealers need attention before drilling in.
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: summary.healthScore >= 0.66
                            ? Colors.green
                            : summary.healthScore >= 0.33
                                ? Colors.amber
                                : Colors.red,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Code ${dealer.dealerCode}',
                            style: TextStyle(
                              color: NexGenPalette.textMedium,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _HealthChip(health: health),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MetricPill(
                      label: 'This month',
                      value: '${summary.jobsThisMonth}',
                    ),
                    const SizedBox(width: 8),
                    _MetricPill(
                      label: 'Active',
                      value: '${summary.activeJobsCount}',
                    ),
                    const SizedBox(width: 8),
                    _MetricPill(
                      label: 'MTD',
                      value: '\$${summary.mtdRevenue.toStringAsFixed(0)}',
                    ),
                    const SizedBox(width: 8),
                    _MetricPill(
                      label: 'Last job',
                      value: _lastJobLabel(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.health});
  final DealerHealth health;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (health) {
      DealerHealth.active => ('Active', NexGenPalette.green),
      DealerHealth.quiet => ('Quiet', NexGenPalette.amber),
      DealerHealth.stalled => ('Stalled', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHARED PIECES
// ═══════════════════════════════════════════════════════════════════════

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: NexGenPalette.textMedium, size: 36),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
