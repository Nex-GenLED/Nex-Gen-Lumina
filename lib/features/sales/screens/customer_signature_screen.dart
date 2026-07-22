import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/referrals/services/referral_pipeline_service.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:signature/signature.dart';

/// Customer e-signature screen for estimate approval.
/// The salesperson hands the phone to the customer for signing.
class CustomerSignatureScreen extends ConsumerStatefulWidget {
  const CustomerSignatureScreen({super.key});

  @override
  ConsumerState<CustomerSignatureScreen> createState() => _CustomerSignatureScreenState();
}

class _CustomerSignatureScreenState extends ConsumerState<CustomerSignatureScreen> {
  late final SignatureController _sigController;
  bool _hasSigned = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _sigController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _sigController.addListener(_onSignatureChanged);
  }

  @override
  void dispose() {
    _sigController.removeListener(_onSignatureChanged);
    _sigController.dispose();
    super.dispose();
  }

  void _onSignatureChanged() {
    final signed = _sigController.isNotEmpty;
    if (signed != _hasSigned) {
      setState(() => _hasSigned = signed);
    }
  }

  Future<void> _confirmAndApprove() async {
    if (!_hasSigned) return;

    final job = ref.read(activeJobProvider);
    if (job == null) return;

    setState(() => _isSubmitting = true);

    try {
      // 1. Export signature as PNG bytes
      final Uint8List? pngBytes = await _sigController.toPngBytes(
        height: 360,
        width: 720,
      );
      if (pngBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not capture signature')),
          );
          setState(() => _isSubmitting = false);
        }
        return;
      }

      // 2. Upload PNG to Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sales_jobs/${job.id}/signature_$timestamp.png');
      await storageRef.putData(
        pngBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      final downloadUrl = await storageRef.getDownloadURL();

      // 3. Atomically write status + signature url + timestamps via the
      //    service. This pushes the job into the Day 1 electrician queue
      //    (estimateSigned status is one of the two statuses Day1QueueScreen
      //    listens for).
      await ref
          .read(salesJobServiceProvider)
          .markEstimateSigned(job.id, downloadUrl);

      // 4. Update local state
      final now = DateTime.now();
      ref.read(activeJobProvider.notifier).state = job.copyWith(
        status: SalesJobStatus.estimateSigned,
        estimateSignedAt: now,
        customerSignatureUrl: downloadUrl,
        updatedAt: now,
      );

      // 5. Update referral pipeline (fire-and-forget)
      if (job.prospect.referrerUid.isNotEmpty) {
        try {
          await ref.read(referralPipelineServiceProvider).updateReferralStatus(
            prospectUid: job.prospect.referrerUid,
            newStatus: 'confirmed',
            jobId: job.id,
          );
        } catch (e) {
          debugPrint('Referral pipeline update failed: $e');
        }
      }

      // 6. Show confirmation and navigate
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Estimate approved — install is confirmed'),
            backgroundColor: NexGenPalette.green,
          ),
        );
        ref.read(activeJobProvider.notifier).state = null;
        context.go(AppRoutes.salesLanding);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save signature: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(activeJobProvider);
    if (job == null) {
      return Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: const Center(
          child: Text('No active job', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final prospect = job.prospect;
    final totalPrice = job.zones.fold(0.0, (acc, z) => acc + z.priceUsd);

    return Scaffold(
      backgroundColor: const Color(0xFF07091A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Text(
                    'Approve your estimate',
                    style: GoogleFonts.montserrat(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prospect.fullName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '\$${totalPrice.toStringAsFixed(0)}',
                    style: GoogleFonts.montserrat(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: NexGenPalette.cyan,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By signing you agree to this estimate and the install schedule.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Summary ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NexGenPalette.gunmetal90,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NexGenPalette.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Per zone: name + price
                        ...job.zones.map((zone) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  zone.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                              ),
                              Text(
                                '\$${zone.priceUsd.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        )),
                        const Divider(color: NexGenPalette.line, height: 16),
                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '\$${totalPrice.toStringAsFixed(0)}',
                              style: GoogleFonts.montserrat(
                                color: NexGenPalette.green,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        // Dates
                        if (job.day1Date != null && job.day2Date != null) ...[
                          const SizedBox(height: 12),
                          _dateRow('Day 1', job.day1Date!),
                          const SizedBox(height: 4),
                          _dateRow('Day 2', job.day2Date!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Signature pad ──
                  Text(
                    'Sign below',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _hasSigned
                              ? NexGenPalette.cyan.withValues(alpha: 0.4)
                              : NexGenPalette.line,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Signature(
                          controller: _sigController,
                          height: 180,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _sigController.clear();
                        setState(() => _hasSigned = false);
                      },
                      child: Text(
                        'Clear',
                        style: TextStyle(color: NexGenPalette.textMedium),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Bottom buttons ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting || !_hasSigned
                        ? null
                        : _confirmAndApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Confirm and approve',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: NexGenPalette.textMedium),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRow(String label, DateTime date) {
    final formatted = '${_monthName(date.month)} ${date.day}, ${date.year}';
    return Row(
      children: [
        Icon(Icons.calendar_today, size: 14, color: NexGenPalette.textMedium),
        const SizedBox(width: 8),
        Text(
          '$label: $formatted',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        ),
      ],
    );
  }

  String _monthName(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];
}
