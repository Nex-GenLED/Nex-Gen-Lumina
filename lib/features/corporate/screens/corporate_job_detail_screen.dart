import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/theme.dart';

/// Read-only corporate job detail screen.
///
/// Loads a single `sales_jobs` document by id and renders prospect info,
/// channel runs, estimate breakdown, install dates, a derived status
/// timeline, and any install-complete photos. No edit actions.
class CorporateJobDetailScreen extends ConsumerStatefulWidget {
  const CorporateJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<CorporateJobDetailScreen> createState() =>
      _CorporateJobDetailScreenState();
}

class _CorporateJobDetailScreenState
    extends ConsumerState<CorporateJobDetailScreen> {
  SalesJob? _job;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  Future<void> _loadJob() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sales_jobs')
          .doc(widget.jobId)
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        setState(() {
          _loading = false;
          _error = 'Job not found.';
        });
        return;
      }
      setState(() {
        _job = SalesJob.fromJson(doc.data()!);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load job: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          _job?.jobNumber.isNotEmpty == true
              ? _job!.jobNumber
              : 'Job detail',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NexGenPalette.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: NexGenPalette.gold.withValues(alpha: 0.5)),
            ),
            child: const Text(
              'Read-only',
              style: TextStyle(
                color: NexGenPalette.gold,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: NexGenPalette.gold),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final job = _job!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProspectSummary(job: job),
          const SizedBox(height: 16),
          _StatusTimeline(job: job),
          const SizedBox(height: 16),
          _ChannelRunsSection(job: job),
          const SizedBox(height: 16),
          _EstimateSection(job: job),
          const SizedBox(height: 16),
          _InstallSection(job: job),
          if (job.installCompletePhotoUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PhotosSection(urls: job.installCompletePhotoUrls),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTIONS
// ═══════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ProspectSummary extends StatelessWidget {
  const _ProspectSummary({required this.job});
  final SalesJob job;

  @override
  Widget build(BuildContext context) {
    final p = job.prospect;
    return _SectionCard(
      title: 'Prospect',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: NexGenPalette.violet.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NexGenPalette.violet.withValues(alpha: 0.5)),
        ),
        child: Text(
          'Dealer ${job.dealerCode}',
          style: TextStyle(
            color: NexGenPalette.violet,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.fullName.trim().isEmpty ? '(No name)' : p.fullName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _kv('Address', '${p.address}, ${p.city}, ${p.state} ${p.zipCode}'),
          if (p.email.isNotEmpty) _kv('Email', p.email),
          if (p.phone.isNotEmpty) _kv('Phone', p.phone),
          _kv('Status', job.status.label),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              k,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.job});
  final SalesJob job;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, DateTime?)>[
      ('Created', job.createdAt),
      ('Estimate sent', job.estimateSentAt),
      ('Estimate signed', job.estimateSignedAt),
      ('Day 1 scheduled', job.day1Date),
      ('Day 1 complete', job.day1CompletedAt),
      ('Day 2 scheduled', job.day2Date),
      ('Day 2 complete', job.day2CompletedAt),
    ];

    return _SectionCard(
      title: 'Timeline',
      child: Column(
        children: entries.map((entry) {
          final hit = entry.$2 != null;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hit ? NexGenPalette.green : NexGenPalette.line,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.$1,
                    style: TextStyle(
                      color: hit ? Colors.white : NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (hit)
                  Text(
                    _formatDate(entry.$2!),
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChannelRunsSection extends StatelessWidget {
  const _ChannelRunsSection({required this.job});
  final SalesJob job;

  @override
  Widget build(BuildContext context) {
    if (job.channelRuns.isEmpty) {
      return _SectionCard(
        title: 'Channel runs',
        child: Text(
          'No channel runs configured.',
          style: TextStyle(
            color: NexGenPalette.textMedium,
            fontSize: 12,
          ),
        ),
      );
    }
    return _SectionCard(
      title: 'Channel runs (${job.channelRuns.length})',
      child: Column(
        children: job.channelRuns.map((r) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: NexGenPalette.cyan.withValues(alpha: 0.4),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${r.channelNumber}',
                    style: const TextStyle(
                      color: NexGenPalette.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.label.isEmpty ? 'Channel ${r.channelNumber}' : r.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${r.linearFeet.toStringAsFixed(1)} ft',
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EstimateSection extends StatelessWidget {
  const _EstimateSection({required this.job});
  final SalesJob job;

  @override
  Widget build(BuildContext context) {
    final breakdown = job.estimateBreakdown;
    return _SectionCard(
      title: 'Estimate',
      trailing: Text(
        _formatUsd(job.totalPriceUsd),
        style: const TextStyle(
          color: NexGenPalette.green,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: breakdown == null
          ? Text(
              'No estimate breakdown stored on this job.',
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 12,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...breakdown.lineItems.map((li) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            li.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '${li.quantity.toStringAsFixed(li.quantity == li.quantity.roundToDouble() ? 0 : 1)} ${li.unit}',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: Text(
                            _formatUsd(li.retailTotal),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Divider(color: NexGenPalette.line, height: 1),
                const SizedBox(height: 8),
                _totalRow('Materials', breakdown.subtotalMaterial),
                _totalRow('Labor', breakdown.subtotalLabor),
                _totalRow(
                  'Margin',
                  breakdown.estimatedMargin,
                  highlight: NexGenPalette.gold,
                ),
              ],
            ),
    );
  }

  Widget _totalRow(String label, double value, {Color? highlight}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: highlight ?? NexGenPalette.textMedium,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            _formatUsd(value),
            style: TextStyle(
              color: highlight ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallSection extends StatelessWidget {
  const _InstallSection({required this.job});
  final SalesJob job;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Install',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(
            'Day 1 (pre-wire)',
            job.day1Date == null ? '—' : _formatDate(job.day1Date!),
          ),
          if (job.day1CompletedAt != null)
            _kv('Day 1 completed', _formatDate(job.day1CompletedAt!)),
          _kv(
            'Day 2 (install)',
            job.day2Date == null ? '—' : _formatDate(job.day2Date!),
          ),
          if (job.day2CompletedAt != null)
            _kv('Day 2 completed', _formatDate(job.day2CompletedAt!)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Install photos (${urls.length})',
      child: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final url = urls[i];
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 96,
                  height: 96,
                  color: NexGenPalette.gunmetal,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: NexGenPalette.textMedium,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════

String _formatDate(DateTime dt) {
  return '${dt.month}/${dt.day}/${dt.year}';
}

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
