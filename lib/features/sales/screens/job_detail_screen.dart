import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/features/referrals/services/referral_pipeline_service.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/services/install_plan_service.dart';
import 'package:nexgen_command/features/sales/services/pdf_service.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/theme.dart';

/// Job detail screen — shows full job info and provides status actions.
class JobDetailScreen extends ConsumerStatefulWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  SalesJob? _job;
  bool _isLoading = true;
  bool _isUpdating = false;

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
      if (doc.exists && mounted) {
        setState(() {
          _job = SalesJob.fromJson(doc.data()!);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(SalesJobStatus newStatus) async {
    if (_job == null) return;
    setState(() => _isUpdating = true);

    try {
      await ref.read(salesJobServiceProvider).updateStatus(_job!.id, newStatus);
      final now = DateTime.now();

      setState(() {
        _job = _job!.copyWith(status: newStatus, updatedAt: now);
      });

      // Update referral pipeline (fire-and-forget)
      if (_job!.prospect.referrerUid.isNotEmpty) {
        String? referralStatus;
        if (newStatus == SalesJobStatus.prewireScheduled ||
            newStatus == SalesJobStatus.prewireComplete) {
          referralStatus = 'installing';
        } else if (newStatus == SalesJobStatus.installComplete) {
          referralStatus = 'installed';
        }
        if (referralStatus != null) {
          try {
            await ref.read(referralPipelineServiceProvider).updateReferralStatus(
              prospectUid: _job!.prospect.referrerUid,
              newStatus: referralStatus,
              jobId: _job!.id,
            );
          } catch (e) {
            debugPrint('Referral pipeline update failed: $e');
          }
        }
      }

      // If marking pre-wire complete, notify Day 2 team
      if (newStatus == SalesJobStatus.prewireComplete) {
        await _notifyDay2Team();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _notifyDay2Team() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('notifyDay2Team');
      await callable.call({'jobId': _job!.id});
      debugPrint('Day 2 team notified for job ${_job!.id}');
    } catch (e) {
      debugPrint('Failed to notify Day 2 team: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    if (_job == null) {
      return Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('Job not found', style: TextStyle(color: Colors.white))),
      );
    }

    final job = _job!;
    final totalPrice = job.zones.fold(0.0, (acc, z) => acc + z.priceUsd);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(job.jobNumber),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer
            Text(
              job.prospect.fullName,
              style: GoogleFonts.montserrat(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${job.prospect.address}, ${job.prospect.city}, ${job.prospect.state} ${job.prospect.zipCode}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(job.prospect.phone, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
            const SizedBox(height: 16),

            // Status
            _statusBadge(job.status),
            const SizedBox(height: 20),

            // Price
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 16)),
                Text(
                  '\$${totalPrice.toStringAsFixed(0)}',
                  style: GoogleFonts.montserrat(color: NexGenPalette.green, fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Zones summary
            Text('Zones', style: TextStyle(color: NexGenPalette.cyan, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...job.zones.map((zone) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(zone.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                            '${zone.runLengthFt.toStringAsFixed(0)} ft · ${zone.productType.label}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text('\$${zone.priceUsd.toStringAsFixed(0)}', style: TextStyle(color: NexGenPalette.green, fontSize: 14)),
                  ],
                ),
              ),
            )),
            const SizedBox(height: 20),

            // Dates
            if (job.day1Date != null) _dateInfo('Day 1 — Electrical', job.day1Date!),
            if (job.day2Date != null) _dateInfo('Day 2 — Install', job.day2Date!),

            // Signature
            if (job.customerSignatureUrl != null) ...[
              const SizedBox(height: 16),
              Text('Customer signature', style: TextStyle(color: NexGenPalette.cyan, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(job.customerSignatureUrl!, height: 80, fit: BoxFit.contain),
              ),
            ],

            const SizedBox(height: 24),

            // ── Day 1 & Day 2 task checklists ──
            if (job.status.index >= SalesJobStatus.estimateSigned.index) ...[
              _buildTaskChecklist(job, 1),
              const SizedBox(height: 16),
              _buildTaskChecklist(job, 2),
              const SizedBox(height: 16),
            ],

            // ── PDF download button ──
            if (job.zones.isNotEmpty)
              _buildPdfButton(job),
            const SizedBox(height: 24),

            // Action buttons based on status
            ..._buildActions(job),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(SalesJobStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }

  Widget _dateInfo(String label, DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 16, color: NexGenPalette.textMedium),
          const SizedBox(width: 8),
          Text(
            '$label: ${date.month}/${date.day}/${date.year}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(SalesJob job) {
    switch (job.status) {
      case SalesJobStatus.estimateSigned:
        return [
          _actionButton('Schedule pre-wire', NexGenPalette.amber,
            () => _updateStatus(SalesJobStatus.prewireScheduled)),
        ];
      case SalesJobStatus.prewireScheduled:
        return [
          _actionButton('Mark pre-wire complete', NexGenPalette.amber,
            () => _updateStatus(SalesJobStatus.prewireComplete)),
        ];
      case SalesJobStatus.prewireComplete:
        return [
          _actionButton('Mark install complete', NexGenPalette.green,
            () => _updateStatus(SalesJobStatus.installComplete)),
        ];
      case SalesJobStatus.installScheduled:
        return [
          _actionButton('Mark install complete', NexGenPalette.green,
            () => _updateStatus(SalesJobStatus.installComplete)),
        ];
      default:
        return [];
    }
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isUpdating ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isUpdating
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15)),
      ),
    );
  }

  Color _statusColor(SalesJobStatus s) => switch (s) {
    SalesJobStatus.draft => Colors.grey,
    SalesJobStatus.estimateSent => NexGenPalette.violet,
    SalesJobStatus.estimateSigned => NexGenPalette.cyan,
    SalesJobStatus.prewireScheduled => NexGenPalette.amber,
    SalesJobStatus.prewireComplete => NexGenPalette.amber,
    SalesJobStatus.installScheduled => NexGenPalette.green,
    SalesJobStatus.installComplete => NexGenPalette.green,
  };

  Widget _buildTaskChecklist(SalesJob job, int day) {
    final service = ref.read(installPlanServiceProvider);
    final tasks = day == 1
        ? service.buildDay1Tasks(job)
        : service.buildDay2Tasks(job);

    if (tasks.isEmpty) return const SizedBox.shrink();

    final label = day == 1 ? 'Day 1 — Pre-wire' : 'Day 2 — Install';
    final color = day == 1 ? NexGenPalette.amber : NexGenPalette.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...tasks.map((task) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Row(
              children: [
                Icon(
                  task.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: task.completed ? NexGenPalette.green : NexGenPalette.textMedium,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.category,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        task.description,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (task.requiresPhoto)
                  Icon(Icons.camera_alt_outlined, size: 14, color: NexGenPalette.textMedium),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildPdfButton(SalesJob job) {
    return OutlinedButton.icon(
      onPressed: () async {
        try {
          final planService = ref.read(installPlanServiceProvider);
          final pdfSvc = ref.read(pdfServiceProvider);
          final day1 = planService.buildDay1Tasks(job);
          final day2 = planService.buildDay2Tasks(job);
          final bytes = await pdfSvc.generateInstallPlan(job, day1, day2);
          await pdfSvc.savePdfToDevice(bytes, 'NexGen-${job.jobNumber}.pdf');
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF generation failed: $e')),
            );
          }
        }
      },
      icon: Icon(Icons.picture_as_pdf, color: NexGenPalette.cyan, size: 18),
      label: Text('Download install plan PDF', style: TextStyle(color: NexGenPalette.cyan)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
