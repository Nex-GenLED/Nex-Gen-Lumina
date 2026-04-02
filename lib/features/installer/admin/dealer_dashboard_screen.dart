import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/installer/admin/admin_providers.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_providers.dart';
import 'package:nexgen_command/features/installer/admin/installer_management_screen.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}

Color _statusColor(SalesJobStatus status) {
  switch (status) {
    case SalesJobStatus.draft:
      return const Color(0xFF555555);
    case SalesJobStatus.estimateSent:
      return const Color(0xFF6E2FFF);
    case SalesJobStatus.estimateSigned:
      return const Color(0xFF1D9E75);
    case SalesJobStatus.prewireScheduled:
    case SalesJobStatus.prewireComplete:
      return const Color(0xFFEF9F27);
    case SalesJobStatus.installComplete:
      return const Color(0xFF00D4FF);
  }
}

double _statusProgress(SalesJobStatus status) {
  switch (status) {
    case SalesJobStatus.draft:
      return 0.1;
    case SalesJobStatus.estimateSent:
      return 0.3;
    case SalesJobStatus.estimateSigned:
      return 0.5;
    case SalesJobStatus.prewireScheduled:
      return 0.65;
    case SalesJobStatus.prewireComplete:
      return 0.8;
    case SalesJobStatus.installComplete:
      return 1.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dealer Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class DealerDashboardScreen extends ConsumerStatefulWidget {
  const DealerDashboardScreen({super.key, this.dealerCodeOverride});
  final String? dealerCodeOverride;

  @override
  ConsumerState<DealerDashboardScreen> createState() =>
      _DealerDashboardScreenState();
}

class _DealerDashboardScreenState extends ConsumerState<DealerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? _resolveDealerCode() {
    final override = widget.dealerCodeOverride;
    if (override != null && override.isNotEmpty) return override;
    final salesSession = ref.read(currentSalesSessionProvider);
    if (salesSession != null) return salesSession.dealerCode;
    final installerSession = ref.read(installerSessionProvider);
    if (installerSession != null) return installerSession.dealer.dealerCode;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dealerCode = _resolveDealerCode();

    if (dealerCode == null) {
      return Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        appBar: AppBar(
          backgroundColor: NexGenPalette.gunmetal90,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: const Text('Dealer Dashboard',
              style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: NexGenPalette.textMedium, size: 48),
              const SizedBox(height: 16),
              Text('No active dealer session',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final isAdminView =
        widget.dealerCodeOverride != null && widget.dealerCodeOverride!.isNotEmpty;
    final dealersAsync = ref.watch(dealerListProvider);
    final companyName = dealersAsync.valueOrNull
            ?.where((d) => d.dealerCode == dealerCode)
            .firstOrNull
            ?.companyName ??
        '';

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dealer Dashboard',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            if (companyName.isNotEmpty)
              Text(
                isAdminView ? 'Admin view — $companyName' : companyName,
                style: TextStyle(
                  color: isAdminView ? Colors.amber : NexGenPalette.textMedium,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Dealer $dealerCode',
              style: const TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: NexGenPalette.cyan,
          indicatorWeight: 2,
          labelColor: NexGenPalette.cyan,
          unselectedLabelColor: NexGenPalette.textMedium,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Pipeline'),
            Tab(text: 'Team'),
            Tab(text: 'Payouts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(
            dealerCode: dealerCode,
            onViewAllJobs: () => _tabController.animateTo(1),
          ),
          _PipelineTab(dealerCode: dealerCode),
          _TeamTab(dealerCode: dealerCode),
          _PayoutsTab(dealerCode: dealerCode),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1: OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.dealerCode, required this.onViewAllJobs});
  final String dealerCode;
  final VoidCallback onViewAllJobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(dealerJobsProvider(dealerCode));
    final installersAsync = ref.watch(dealerInstallersProvider(dealerCode));
    final pendingAsync = ref.watch(dealerPendingPayoutsProvider(dealerCode));
    final activityAsync = ref.watch(dealerRecentActivityProvider(dealerCode));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stat cards (2×2) ──
          _buildStatCards(jobsAsync, installersAsync, pendingAsync),
          const SizedBox(height: 28),

          // ── Pipeline status bar ──
          _buildPipelineBar(ref),
          const SizedBox(height: 28),

          // ── Recent activity ──
          const Text('Recent activity',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          activityAsync.when(
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child:
                        CircularProgressIndicator(color: NexGenPalette.cyan))),
            error: (_, __) => const SizedBox.shrink(),
            data: (events) {
              if (events.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No recent activity',
                        style: TextStyle(color: NexGenPalette.textMedium)),
                  ),
                );
              }
              final display = events.take(10).toList();
              return Column(
                children: [
                  ...display.map((e) => _ActivityRow(event: e)),
                  if (events.length > 10)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onViewAllJobs,
                        child: const Text('View all',
                            style: TextStyle(color: NexGenPalette.cyan)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(
    AsyncValue<List<SalesJob>> jobsAsync,
    AsyncValue<List<InstallerInfo>> installersAsync,
    AsyncValue<List<ReferralPayout>> pendingAsync,
  ) {
    final jobs = jobsAsync.valueOrNull ?? [];
    final activeJobs =
        jobs.where((j) => j.status != SalesJobStatus.installComplete).length;
    final completedJobs =
        jobs.where((j) => j.status == SalesJobStatus.installComplete).length;
    final activeInstallers =
        (installersAsync.valueOrNull ?? []).where((i) => i.isActive).length;
    final pendingCount = (pendingAsync.valueOrNull ?? []).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                  label: 'Active jobs',
                  value: '$activeJobs',
                  icon: Icons.work_outline,
                  color: NexGenPalette.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                  label: 'Completed installs',
                  value: '$completedJobs',
                  icon: Icons.check_circle_outline,
                  color: NexGenPalette.green),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                  label: 'Active installers',
                  value: '$activeInstallers',
                  icon: Icons.engineering_outlined,
                  color: NexGenPalette.violet),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Pending payouts',
                value: '$pendingCount',
                icon: Icons.payments_outlined,
                color: Colors.amber,
                tinted: pendingCount > 0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPipelineBar(WidgetRef ref) {
    final byStatus = ref.watch(dealerJobsByStatusProvider(dealerCode));
    final totalJobs =
        byStatus.values.fold<int>(0, (acc, list) => acc + list.length);

    if (totalJobs == 0) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Center(
          child: Text('No jobs yet',
              style: TextStyle(color: NexGenPalette.textMedium)),
        ),
      );
    }

    final activeStatuses = SalesJobStatus.values
        .where((s) => byStatus[s]!.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pipeline',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: activeStatuses.map((status) {
                final count = byStatus[status]!.length;
                return Flexible(
                  flex: count,
                  child: Container(color: _statusColor(status)),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: activeStatuses.map((status) {
            final count = byStatus[status]!.length;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('${status.label} ($count)',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool tinted;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tinted
            ? color.withValues(alpha: 0.1)
            : NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});
  final DealerActivityEvent event;

  @override
  Widget build(BuildContext context) {
    Color pillColor;
    switch (event.type) {
      case DealerActivityType.jobCreated:
        pillColor = const Color(0xFF555555);
      case DealerActivityType.estimateSent:
        pillColor = const Color(0xFF6E2FFF);
      case DealerActivityType.estimateSigned:
        pillColor = const Color(0xFF1D9E75);
      case DealerActivityType.prewireComplete:
        pillColor = const Color(0xFFEF9F27);
      case DealerActivityType.installComplete:
        pillColor = const Color(0xFF00D4FF);
      case DealerActivityType.payoutPending:
        pillColor = Colors.amber;
      case DealerActivityType.payoutApproved:
        pillColor = NexGenPalette.green;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: pillColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              event.type.iconLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: pillColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(event.subtitle,
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 11)),
              ],
            ),
          ),
          Text(_timeAgo(event.timestamp),
              style:
                  TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2: PIPELINE
// ═══════════════════════════════════════════════════════════════════════════════

class _PipelineTab extends ConsumerStatefulWidget {
  const _PipelineTab({required this.dealerCode});
  final String dealerCode;

  @override
  ConsumerState<_PipelineTab> createState() => _PipelineTabState();
}

class _PipelineTabState extends ConsumerState<_PipelineTab> {
  SalesJobStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final byStatus =
        ref.watch(dealerJobsByStatusProvider(widget.dealerCode));
    final allJobs =
        ref.watch(dealerJobsProvider(widget.dealerCode)).valueOrNull ?? [];

    final filteredJobs =
        _filter == null ? allJobs : (byStatus[_filter] ?? []);

    return Column(
      children: [
        // Filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _FilterPill(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null)),
              const SizedBox(width: 8),
              ...[
                SalesJobStatus.draft,
                SalesJobStatus.estimateSent,
                SalesJobStatus.estimateSigned,
                SalesJobStatus.prewireScheduled,
                SalesJobStatus.prewireComplete,
                SalesJobStatus.installComplete,
              ].map((s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterPill(
                        label: s.label,
                        selected: _filter == s,
                        onTap: () => setState(() => _filter = s)),
                  )),
            ],
          ),
        ),
        const Divider(color: NexGenPalette.line, height: 1),
        // Job list
        Expanded(
          child: filteredJobs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          color: NexGenPalette.textMedium, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _filter == null
                            ? 'No jobs yet'
                            : '${_filter!.label} — no jobs',
                        style: TextStyle(
                            color: NexGenPalette.textMedium, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredJobs.length,
                  itemBuilder: (context, i) =>
                      _JobCard(job: filteredJobs[i]),
                ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? NexGenPalette.cyan
                : NexGenPalette.textMedium.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : NexGenPalette.textMedium,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final SalesJob job;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(job.status);
    return Card(
      color: NexGenPalette.gunmetal90,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: NexGenPalette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/sales/jobs/${job.id}'),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: name + job number
                  Row(
                    children: [
                      Expanded(
                        child: Text(job.prospect.fullName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(job.jobNumber,
                          style: TextStyle(
                              color: NexGenPalette.textMedium, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Row 2: address
                  Text(
                    '${job.prospect.address}, ${job.prospect.city}',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Row 3: status pill + price
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(job.status.label,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      Text('\$${fmtCurrency(job.totalPriceUsd)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            // Row 4: progress bar
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: LinearProgressIndicator(
                value: _statusProgress(job.status),
                backgroundColor: NexGenPalette.line,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3: TEAM
// ═══════════════════════════════════════════════════════════════════════════════

class _TeamTab extends ConsumerWidget {
  const _TeamTab({required this.dealerCode});
  final String dealerCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installersAsync = ref.watch(dealerInstallersProvider(dealerCode));

    return installersAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (installers) {
        final active = installers.where((i) => i.isActive).length;
        final inactive = installers.length - active;

        return Column(
          children: [
            // Summary line
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                border: Border(bottom: BorderSide(color: NexGenPalette.line)),
              ),
              child: Text(
                '$active active installer${active == 1 ? '' : 's'} · $inactive inactive',
                style:
                    TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
              ),
            ),
            // Installer list
            Expanded(
              child: installers.isEmpty
                  ? Center(
                      child: Text('No installers',
                          style: TextStyle(
                              color: NexGenPalette.textMedium, fontSize: 14)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: installers.length + 1, // +1 for manage button
                      itemBuilder: (context, i) {
                        if (i == installers.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const InstallerManagementScreen()),
                              ),
                              icon: const Icon(Icons.settings_outlined,
                                  size: 18),
                              label: const Text('Manage team'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: NexGenPalette.cyan,
                                side: BorderSide(
                                    color: NexGenPalette.cyan
                                        .withValues(alpha: 0.4)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          );
                        }
                        return _InstallerTile(installer: installers[i]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _InstallerTile extends StatelessWidget {
  const _InstallerTile({required this.installer});
  final InstallerInfo installer;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NexGenPalette.gunmetal90,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: installer.isActive
              ? NexGenPalette.line
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // PIN badge (split DD|II)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: installer.isActive
                      ? NexGenPalette.line
                      : Colors.grey.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: installer.isActive
                          ? NexGenPalette.violet.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        bottomLeft: Radius.circular(7),
                      ),
                    ),
                    child: Text(installer.dealerCode,
                        style: TextStyle(
                            color: installer.isActive
                                ? NexGenPalette.violet
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: installer.isActive
                          ? NexGenPalette.cyan.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(7),
                        bottomRight: Radius.circular(7),
                      ),
                    ),
                    child: Text(installer.installerCode,
                        style: TextStyle(
                            color: installer.isActive
                                ? NexGenPalette.cyan
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(installer.name,
                      style: TextStyle(
                          color: installer.isActive ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  if (installer.email.isNotEmpty)
                    Text(installer.email,
                        style: TextStyle(
                            color: NexGenPalette.textMedium, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: installer.isActive
                    ? NexGenPalette.green.withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                installer.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                    color: installer.isActive ? NexGenPalette.green : Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4: PAYOUTS
// ═══════════════════════════════════════════════════════════════════════════════

class _PayoutsTab extends ConsumerWidget {
  const _PayoutsTab({required this.dealerCode});
  final String dealerCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allPayoutsAsync = ref.watch(dealerAllPayoutsProvider(dealerCode));

    return allPayoutsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (allPayouts) {
        final pending = allPayouts
            .where((p) => p.status == RewardPayoutStatus.pending)
            .toList();
        final approved = allPayouts
            .where((p) => p.status == RewardPayoutStatus.approved)
            .toList();
        final fulfilled = allPayouts
            .where((p) => p.status == RewardPayoutStatus.fulfilled)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section A: Pending ──
              _SectionHeader(
                  label: 'Pending approval', count: pending.length),
              const SizedBox(height: 12),
              if (pending.isEmpty)
                _EmptyPayout(label: 'No pending payouts')
              else
                ...pending.map((p) => _PendingPayoutCard(
                    payout: p, dealerCode: dealerCode)),

              const SizedBox(height: 28),

              // ── Section B: Approved awaiting fulfillment ──
              _SectionHeader(
                  label: 'Approved — awaiting fulfillment',
                  count: approved.length),
              const SizedBox(height: 12),
              if (approved.isEmpty)
                _EmptyPayout(label: 'No approved payouts awaiting fulfillment')
              else
                ...approved.map((p) => _ApprovedPayoutCard(payout: p)),

              const SizedBox(height: 28),

              // ── Section C: Recently fulfilled ──
              const Text('Recently fulfilled',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (fulfilled.isEmpty)
                _EmptyPayout(label: 'No fulfilled payouts')
              else
                ...fulfilled.take(10).map((p) => _FulfilledPayoutRow(payout: p)),

              const SizedBox(height: 32),

              // ── Disclosure ──
              Text(
                'Visa gift card rewards are capped at \$599 per referrer per '
                'calendar year. Nex-Gen credit has no annual cap. Rewards require '
                'dealer approval before fulfillment. Payout records are retained '
                'for tax and compliance purposes.',
                style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                    fontSize: 10,
                    height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }
}

class _EmptyPayout extends StatelessWidget {
  const _EmptyPayout({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Text(label,
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
          textAlign: TextAlign.center),
    );
  }
}

class _PendingPayoutCard extends ConsumerWidget {
  const _PendingPayoutCard(
      {required this.payout, required this.dealerCode});
  final ReferralPayout payout;
  final String dealerCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: NexGenPalette.gunmetal90,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: NexGenPalette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: prospect + job number
            Row(children: [
              Expanded(
                child: Text(payout.prospectName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Text(payout.jobNumber,
                  style:
                      TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
            ]),
            const SizedBox(height: 6),

            // Row 2: referrer
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(payout.referrerUid)
                  .get(),
              builder: (context, snap) {
                String name;
                if (snap.hasData && snap.data!.exists) {
                  final data = snap.data!.data() as Map<String, dynamic>?;
                  name = data?['display_name'] as String? ??
                      payout.referrerUid.substring(
                          (payout.referrerUid.length - 8)
                              .clamp(0, payout.referrerUid.length));
                } else {
                  name = payout.referrerUid.length > 8
                      ? payout.referrerUid
                          .substring(payout.referrerUid.length - 8)
                      : payout.referrerUid;
                }
                return Text('Referred by $name',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12));
              },
            ),
            const SizedBox(height: 10),

            // Row 3: install value + tier
            Row(children: [
              Text('\$${fmtCurrency(payout.installValueUsd)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: NexGenPalette.violet.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '\$${payout.tier.installValueMin.toStringAsFixed(0)}–\$${payout.tier.installValueMax.isFinite ? payout.tier.installValueMax.toStringAsFixed(0) : '∞'}',
                  style: const TextStyle(
                      color: NexGenPalette.violet,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 10),

            // Row 4: reward info
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: payout.rewardType == RewardType.visaGiftCard
                      ? Colors.amber.withValues(alpha: 0.15)
                      : NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  payout.rewardType == RewardType.visaGiftCard
                      ? 'Visa GC'
                      : 'Nex-Gen Credit',
                  style: TextStyle(
                    color: payout.rewardType == RewardType.visaGiftCard
                        ? Colors.amber
                        : NexGenPalette.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('\$${fmtCurrency(payout.rewardAmountUsd)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              if (payout.gcCapApplied) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('GC cap — credit issued',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
            const SizedBox(height: 6),

            // Row 5: time
            Text(_timeAgo(payout.createdAt),
                style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontSize: 11)),
            const SizedBox(height: 12),

            // Action buttons
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _showApproveSheet(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Approve',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => _showDeclineDialog(context),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.withValues(alpha: 0.8)),
                child: const Text('Decline'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _showApproveSheet(BuildContext context, WidgetRef ref) {
    final noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approve reward',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(payout.referrerUid)
                  .get(),
              builder: (_, snap) {
                final name = (snap.data?.data()
                        as Map<String, dynamic>?)?['display_name'] as String? ??
                    payout.referrerUid;
                return Text('Referrer: $name',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 13));
              },
            ),
            const SizedBox(height: 8),
            Text(
              '${payout.rewardType == RewardType.visaGiftCard ? 'Visa GC' : 'Nex-Gen Credit'} · \$${fmtCurrency(payout.rewardAmountUsd)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Fulfillment note (optional)',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
                hintText:
                    'e.g. Gift card sent via email to john@email.com',
                hintStyle: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.5),
                    fontSize: 12),
                filled: true,
                fillColor: NexGenPalette.matteBlack,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NexGenPalette.cyan),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final nav = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final note = noteController.text.trim();
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid;

                  await FirebaseFirestore.instance
                      .collection('referral_payouts')
                      .doc(payout.id)
                      .update({
                    'status': 'approved',
                    'approvedByUid': uid,
                    'approvedAt': FieldValue.serverTimestamp(),
                    if (note.isNotEmpty) 'fulfillmentNote': note,
                  });

                  try {
                    await FirebaseFunctions.instanceFor(
                            region: 'us-central1')
                        .httpsCallable('notifyReferrerOfApproval')
                        .call({'payoutId': payout.id});
                  } catch (_) {
                    // Silent — function may not be deployed yet
                  }

                  nav.pop();
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Reward approved — referrer notified'),
                    backgroundColor: NexGenPalette.cyan,
                  ));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Confirm approval',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeclineDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title:
            const Text('Decline this reward?', style: TextStyle(color: Colors.white)),
        content: Text('This cannot be undone.',
            style: TextStyle(color: NexGenPalette.textMedium)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);

              await FirebaseFirestore.instance
                  .collection('referral_payouts')
                  .doc(payout.id)
                  .delete();

              nav.pop();
              messenger.showSnackBar(const SnackBar(
                content: Text('Reward declined'),
                backgroundColor: Colors.red,
              ));
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ApprovedPayoutCard extends StatelessWidget {
  const _ApprovedPayoutCard({required this.payout});
  final ReferralPayout payout;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: NexGenPalette.gunmetal90,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: NexGenPalette.green.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(payout.prospectName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              Text(payout.jobNumber,
                  style:
                      TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: payout.rewardType == RewardType.visaGiftCard
                      ? Colors.amber.withValues(alpha: 0.15)
                      : NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  payout.rewardType == RewardType.visaGiftCard
                      ? 'Visa GC'
                      : 'Nex-Gen Credit',
                  style: TextStyle(
                    color: payout.rewardType == RewardType.visaGiftCard
                        ? Colors.amber
                        : NexGenPalette.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('\$${fmtCurrency(payout.rewardAmountUsd)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await FirebaseFirestore.instance
                      .collection('referral_payouts')
                      .doc(payout.id)
                      .update({
                    'status': 'fulfilled',
                    'fulfilledAt': FieldValue.serverTimestamp(),
                  });
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Marked as fulfilled'),
                    backgroundColor: NexGenPalette.cyan,
                  ));
                },
                style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.green),
                child: const Text('Mark as fulfilled'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FulfilledPayoutRow extends StatelessWidget {
  const _FulfilledPayoutRow({required this.payout});
  final ReferralPayout payout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(payout.prospectName,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Text('\$${fmtCurrency(payout.rewardAmountUsd)}',
                style: const TextStyle(
                    color: NexGenPalette.green,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Text(
              'Fulfilled ${_timeAgo(payout.fulfilledAt ?? payout.createdAt)}',
              style: TextStyle(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                  fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
