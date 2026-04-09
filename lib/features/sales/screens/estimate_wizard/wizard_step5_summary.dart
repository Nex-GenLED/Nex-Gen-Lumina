import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/estimate_wizard_notifier.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_form_fields.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_shell.dart';
import 'package:nexgen_command/features/sales/services/dealer_pricing_service.dart';
import 'package:nexgen_command/features/sales/services/material_calculation_service.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/theme.dart';

/// Step 5 of the Estimate Wizard: read-only summary of everything
/// collected, with warnings and a "Generate Estimate" CTA.
///
/// "Generate Estimate" runs the full pipeline:
///   1. flush wizard state to Firestore via the notifier
///   2. load the dealer's pricing via [dealerPricingProvider]
///      (falls back to [DealerPricing.defaults] if none set)
///   3. call [MaterialCalculationService.calculateEstimate] with the
///      wizard data + pricing
///   4. persist the resulting [EstimateBreakdown] via
///      [SalesJobService.saveEstimateBreakdown] (which also writes the
///      breakdown's subtotalRetail into the legacy `totalPriceUsd`
///      field so existing job-list cards keep working)
///   5. refresh [activeJobProvider] so [EstimatePreviewScreen] picks up
///      the new breakdown
///   6. navigate to the existing preview screen.
class WizardStep5Summary extends ConsumerStatefulWidget {
  final String jobId;
  const WizardStep5Summary({super.key, required this.jobId});

  @override
  ConsumerState<WizardStep5Summary> createState() =>
      _WizardStep5SummaryState();
}

class _WizardStep5SummaryState extends ConsumerState<WizardStep5Summary> {
  bool _isGenerating = false;

  Future<void> _generateEstimate() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    try {
      // 1. Flush the wizard's in-memory state to Firestore. This also
      //    pushes the latest job into activeJobProvider, which the
      //    preview screen reads.
      await ref
          .read(estimateWizardProvider(widget.jobId).notifier)
          .saveProgress();

      // Snapshot the current wizard job (post-save) via the provider
      // value rather than touching the notifier's protected `state`.
      final currentJob = ref.read(estimateWizardProvider(widget.jobId));

      // 2. Load the dealer's pricing. dealerPricingProvider returns
      //    DealerPricing.defaults() when no pricing doc exists for the
      //    current sales session's dealer, so this never throws.
      final pricing = await ref.read(dealerPricingProvider.future);

      // 3. Generate the line-item breakdown from the wizard data.
      final calc = ref.read(materialCalculationServiceProvider);
      final breakdown = calc.calculateEstimate(currentJob, pricing);

      // 4. Persist the breakdown onto the job document. This also
      //    copies subtotalRetail into totalPriceUsd so the existing
      //    job-list cards display the new total without further changes.
      await ref
          .read(salesJobServiceProvider)
          .saveEstimateBreakdown(widget.jobId, breakdown);

      // 5. Refresh activeJobProvider so EstimatePreviewScreen reads the
      //    job with the embedded breakdown.
      final updatedJob = currentJob.copyWith(
        estimateBreakdown: breakdown,
        totalPriceUsd: breakdown.subtotalRetail,
      );
      ref.read(activeJobProvider.notifier).state = updatedJob;

      if (!mounted) return;
      context.push(AppRoutes.salesEstimate);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(estimateWizardProvider(widget.jobId));
    final notifier = ref.read(estimateWizardProvider(widget.jobId).notifier);

    final totalFeet = job.channelRuns.fold<double>(
      0,
      (acc, r) => acc + r.linearFeet,
    );
    final injectionCount = job.powerInjectionPoints.length;

    final warnings = <String>[];
    if (!notifier.hasHomePhoto) {
      warnings.add('No home photo — blueprint will be text-only');
    }
    if (!notifier.hasControllerMount) {
      warnings.add('No controller mount location set');
    } else if (job.controllerMount?.photoPath == null) {
      warnings.add('Controller location has no photo');
    }
    for (final run in notifier.runsNeedingInjection) {
      warnings.add(
        'Channel ${run.channelNumber} (${run.linearFeet.toStringAsFixed(0)} ft) '
        'is over 100ft and has no injection point',
      );
    }

    final canGenerate = notifier.hasChannelRuns;

    return WizardShell(
      stepNumber: 5,
      stepTitle: 'Summary & review',
      jobId: widget.jobId,
      bottomAction: WizardContinueButton(
        onPressed: canGenerate ? _generateEstimate : null,
        label: canGenerate
            ? 'Generate Estimate →'
            : 'Add a channel to continue',
        isLoading: _isGenerating,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WizardSectionHeader(
              title: 'REVIEW',
              subtitle: 'Confirm everything before generating the estimate.',
            ),
            const SizedBox(height: 16),

            // Home photo card
            _summaryCard(
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 56,
                      child: notifier.hasHomePhoto
                          ? Image.network(
                              job.homePhotoPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: NexGenPalette.matteBlack,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white24,
                                  size: 24,
                                ),
                              ),
                            )
                          : Container(
                              color: NexGenPalette.matteBlack,
                              child: Icon(
                                Icons.home_outlined,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Home photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          notifier.hasHomePhoto
                              ? 'Captured'
                              : 'Not captured',
                          style: TextStyle(
                            color: notifier.hasHomePhoto
                                ? NexGenPalette.green
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Controller card
            _summaryCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.developer_board,
                        color: NexGenPalette.cyan,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Controller location',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (job.controllerMount != null)
                        Text(
                          job.controllerMount!.isInteriorMount
                              ? 'Interior'
                              : 'Exterior',
                          style: TextStyle(
                            color: NexGenPalette.cyan.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    job.controllerMount?.locationDescription.isNotEmpty == true
                        ? job.controllerMount!.locationDescription
                        : 'Not set',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  if (job.controllerMount?.distanceFromOutletFeet != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${job.controllerMount!.distanceFromOutletFeet!.toStringAsFixed(0)} ft '
                      'to nearest outlet',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Channels + footage card
            _summaryCard(
              child: Row(
                children: [
                  _statBlock(
                    label: 'Channels',
                    value: '${job.channelRuns.length}',
                    icon: Icons.cable,
                  ),
                  _divider(),
                  _statBlock(
                    label: 'Linear feet',
                    value: totalFeet.toStringAsFixed(0),
                    icon: Icons.straighten,
                  ),
                  _divider(),
                  _statBlock(
                    label: 'Injections',
                    value: '$injectionCount',
                    icon: Icons.bolt,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Channel breakdown list
            if (job.channelRuns.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Channel breakdown',
                style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 12,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final r in job.channelRuns) _channelRow(r, notifier),
              const SizedBox(height: 12),
            ],

            // Warnings
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NexGenPalette.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: NexGenPalette.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: NexGenPalette.amber,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Warnings',
                          style: TextStyle(
                            color: NexGenPalette.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final w in warnings) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(color: NexGenPalette.amber),
                          ),
                          Expanded(
                            child: Text(
                              w,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: child,
    );
  }

  Widget _statBlock({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: NexGenPalette.cyan, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 36,
        width: 1,
        color: NexGenPalette.line,
      );

  Widget _channelRow(ChannelRun r, EstimateWizardNotifier notifier) {
    final injCount = notifier.injectionsForRun(r.id).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${r.channelNumber}',
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                r.label.isEmpty ? 'Untitled' : r.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              '${r.linearFeet.toStringAsFixed(0)} ft · '
              '$injCount inj',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
