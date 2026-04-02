import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Estimate preview — consumer-facing estimate card.
class EstimatePreviewScreen extends ConsumerStatefulWidget {
  const EstimatePreviewScreen({super.key});

  @override
  ConsumerState<EstimatePreviewScreen> createState() => _EstimatePreviewScreenState();
}

class _EstimatePreviewScreenState extends ConsumerState<EstimatePreviewScreen> {
  String? _referrerName;

  @override
  void initState() {
    super.initState();
    _loadReferrerName();
  }

  Future<void> _loadReferrerName() async {
    final job = ref.read(activeJobProvider);
    if (job == null || job.prospect.referrerUid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(job.prospect.referrerUid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _referrerName = doc.data()?['display_name'] as String? ?? 'a friend';
        });
      }
    } catch (_) {}
  }

  Future<void> _shareEstimate() async {
    final job = ref.read(activeJobProvider);
    if (job == null) return;

    final url = 'https://nex-genled.com/estimate/${job.id}';
    await Clipboard.setData(ClipboardData(text: url));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Estimate link copied to clipboard')),
    );

    // Also try to open the URL
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // clipboard copy is sufficient
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(activeJobProvider);
    if (job == null) {
      return Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: const Center(child: Text('No active job', style: TextStyle(color: Colors.white))),
      );
    }

    final prospect = job.prospect;
    final isSigned = job.status == SalesJobStatus.estimateSigned &&
        job.customerSignatureUrl != null;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Estimate'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // ── Estimate card ──
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF07091A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NexGenPalette.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        _buildHeader(job, prospect),
                        const Divider(color: NexGenPalette.line, height: 1),

                        // Per-zone sections
                        ...job.zones.map((zone) => _buildZoneSection(zone)),

                        // Total
                        _buildTotalSection(job),
                        const Divider(color: NexGenPalette.line, height: 1),

                        // What's included
                        _buildIncludedSection(),
                        const Divider(color: NexGenPalette.line, height: 1),

                        // Install dates
                        if (job.day1Date != null && job.day2Date != null)
                          _buildDatesSection(job),

                        // Sign section
                        _buildSignSection(isSigned),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Bottom buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _shareEstimate,
                    icon: const Icon(Icons.share, color: Colors.black, size: 18),
                    label: const Text(
                      'Share with customer',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text('Back to review', style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────

  Widget _buildHeader(SalesJob job, SalesProspect prospect) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Row(
            children: [
              Image.asset(
                'assets/images/nexgen_logo.png',
                height: 36,
                errorBuilder: (_, __, ___) => Icon(Icons.lightbulb_outline, size: 36, color: NexGenPalette.cyan),
              ),
              const SizedBox(width: 12),
              Text(
                'NEX-GEN LED',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NexGenPalette.cyan,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(
            'Custom lighting estimate',
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Est #${job.jobNumber} · Valid 30 days',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Customer
          Text(prospect.fullName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(
            '${prospect.address}, ${prospect.city}, ${prospect.state} ${prospect.zipCode}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),

          // Referrer
          if (_referrerName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.card_giftcard, size: 14, color: NexGenPalette.cyan),
                const SizedBox(width: 6),
                Text('Referred by $_referrerName', style: TextStyle(color: NexGenPalette.cyan, fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Zone section ────────────────────────────────────────────

  Widget _buildZoneSection(InstallZone zone) {
    // Derive feature pills from zone
    final features = <String>['Permanent mount', 'App-controlled'];
    if (zone.colorPreset == ColorPreset.rgbw || zone.colorPreset == ColorPreset.fullRgb) {
      features.add('Holiday-ready');
    }
    features.add('Dusk to dawn');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(zone.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text(
                '\$${zone.priceUsd.toStringAsFixed(0)}',
                style: TextStyle(color: NexGenPalette.green, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${zone.runLengthFt.toStringAsFixed(0)} ft · ${zone.colorPreset.label}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: features.map((f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.2)),
              ),
              child: Text(f, style: TextStyle(color: NexGenPalette.cyan.withValues(alpha: 0.8), fontSize: 11)),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── Total section ───────────────────────────────────────────

  Widget _buildTotalSection(SalesJob job) {
    final total = job.zones.fold(0.0, (acc, z) => acc + z.priceUsd);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total investment',
            style: GoogleFonts.montserrat(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Text(
            '\$${total.toStringAsFixed(0)}',
            style: GoogleFonts.montserrat(color: NexGenPalette.green, fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ── What's included ─────────────────────────────────────────

  Widget _buildIncludedSection() {
    const items = [
      'Professional 2-day installation',
      'Nex-Gen Lumina app — full color control, scheduling, scenes',
      'Permanent weatherproof hardware — no seasonal removal',
      'Lifetime dealer support and warranty',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What's included",
            style: GoogleFonts.montserrat(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: NexGenPalette.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.3)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ── Install dates ───────────────────────────────────────────

  Widget _buildDatesSection(SalesJob job) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Install schedule',
            style: GoogleFonts.montserrat(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _dateRow(
            icon: Icons.electrical_services,
            label: 'Day 1 — Electrical pre-wire',
            date: job.day1Date!,
            window: '8:00 AM – 12:00 PM',
          ),
          const SizedBox(height: 10),
          _dateRow(
            icon: Icons.construction,
            label: 'Day 2 — Install',
            date: job.day2Date!,
            window: '8:00 AM – 11:00 AM',
          ),
        ],
      ),
    );
  }

  Widget _dateRow({required IconData icon, required String label, required DateTime date, required String window}) {
    final formatted = '${_monthName(date.month)} ${date.day}, ${date.year}';
    return Row(
      children: [
        Icon(icon, size: 18, color: NexGenPalette.cyan),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              Text('$formatted · $window', style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  String _monthName(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];

  // ── Sign section ────────────────────────────────────────────

  Widget _buildSignSection(bool isSigned) {
    if (isSigned) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.green.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: NexGenPalette.green, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estimate approved', style: TextStyle(color: NexGenPalette.green, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Customer signature received', style: TextStyle(color: NexGenPalette.green.withValues(alpha: 0.7), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.salesEstimateSign),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.draw_outlined, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 10),
              Text(
                'Tap to sign and approve',
                style: TextStyle(color: NexGenPalette.cyan, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
