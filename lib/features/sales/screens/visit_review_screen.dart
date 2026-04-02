import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/referrals/services/referral_pipeline_service.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/screens/zone_builder_screen.dart';
import 'package:nexgen_command/theme.dart';

/// Step 3 of 3 — Visit review screen.
class VisitReviewScreen extends ConsumerStatefulWidget {
  const VisitReviewScreen({super.key});

  @override
  ConsumerState<VisitReviewScreen> createState() => _VisitReviewScreenState();
}

class _VisitReviewScreenState extends ConsumerState<VisitReviewScreen> {
  DateTime? _day1;
  DateTime? _day2;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final job = ref.read(activeJobProvider);
    if (job != null) {
      _day1 = job.day1Date;
      _day2 = job.day2Date;
    }
  }

  Future<void> _pickDate({required bool isDay1}) async {
    final now = DateTime.now();
    final initial = isDay1 ? (_day1 ?? now) : (_day2 ?? _day1 ?? now);
    final firstDate = isDay1 ? now : (_day1 ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: NexGenPalette.cyan,
            surface: NexGenPalette.gunmetal,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isDay1) {
          _day1 = picked;
          if (_day2 != null && _day2!.isBefore(picked)) _day2 = null;
        } else {
          _day2 = picked;
        }
      });
    }
  }

  Future<void> _sendEstimate() async {
    final job = ref.read(activeJobProvider);
    if (job == null || _day1 == null || _day2 == null) return;

    setState(() => _isSending = true);
    try {
      final updated = job.copyWith(
        status: SalesJobStatus.estimateSent,
        estimateSentAt: DateTime.now(),
        day1Date: _day1,
        day2Date: _day2,
        updatedAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('sales_jobs')
          .doc(job.id)
          .set(updated.toJson(), SetOptions(merge: true));

      ref.read(activeJobProvider.notifier).state = updated;

      // Update referral pipeline
      if (job.prospect.referrerUid.isNotEmpty) {
        try {
          await ref.read(referralPipelineServiceProvider).updateReferralStatus(
            prospectUid: job.prospect.referrerUid,
            newStatus: 'estimateSent',
            jobId: job.id,
          );
        } catch (_) {}
      }

      if (mounted) context.push(AppRoutes.salesEstimate);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _saveDraft() async {
    final job = ref.read(activeJobProvider);
    if (job == null) return;

    final updated = job.copyWith(
      day1Date: _day1,
      day2Date: _day2,
      updatedAt: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection('sales_jobs')
        .doc(job.id)
        .set(updated.toJson(), SetOptions(merge: true));

    ref.read(activeJobProvider.notifier).state = updated;

    if (mounted) context.go(AppRoutes.salesLanding);
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
    final zones = job.zones;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('New Visit'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Step 3 of 3 — Review', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 1.0,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: NexGenPalette.cyan,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Cards
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildCustomerCard(prospect),
                  const SizedBox(height: 12),
                  ...zones.asMap().entries.map((entry) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildZoneCard(entry.value, entry.key, zones),
                    ),
                  ),
                  _buildTotalsCard(zones),
                  const SizedBox(height: 12),
                  _buildDatesCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSending || _day1 == null || _day2 == null
                        ? null
                        : _sendEstimate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSending
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(
                            _day1 == null || _day2 == null
                                ? 'Set install dates to continue'
                                : 'Send estimate to customer',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saveDraft,
                  child: Text('Save draft', style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Card builders ───────────────────────────────────────────

  Widget _buildCustomerCard(SalesProspect p) {
    return _ReviewCard(
      title: 'Customer',
      onEdit: () => context.push(AppRoutes.salesProspect),
      children: [
        _infoRow(Icons.person_outline, p.fullName),
        _infoRow(Icons.home_outlined, '${p.address}, ${p.city}, ${p.state} ${p.zipCode}'),
        _infoRow(Icons.phone_outlined, p.phone),
        _infoRow(Icons.email_outlined, p.email),
        if (p.referralCode.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.card_giftcard, size: 14, color: NexGenPalette.cyan),
                const SizedBox(width: 6),
                Text('Referred by ${p.referralCode}', style: TextStyle(color: NexGenPalette.cyan, fontSize: 13)),
              ],
            ),
          ),
        if (p.salespersonNotes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(p.salespersonNotes, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, fontStyle: FontStyle.italic)),
        ],
      ],
    );
  }

  Widget _buildZoneCard(InstallZone zone, int index, List<InstallZone> allZones) {
    final additional = zone.injections.where((i) => !i.servedByController).length;

    return _ReviewCard(
      title: zone.name,
      onEdit: () async {
        final result = await showModalBottomSheet<InstallZone>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ZoneEditorSheet(
            existing: zone,
            allZones: allZones,
            editIndex: index,
            jobId: ref.read(activeJobProvider)?.id ?? '',
          ),
        );
        if (result != null) {
          final job = ref.read(activeJobProvider);
          if (job != null) {
            final updatedZones = List<InstallZone>.from(job.zones);
            updatedZones[index] = result;
            ref.read(activeJobProvider.notifier).state = job.copyWith(zones: updatedZones);
          }
        }
      },
      trailing: Text(
        '\$${zone.priceUsd.toStringAsFixed(0)}',
        style: TextStyle(color: NexGenPalette.green, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      children: [
        Text(
          '${zone.runLengthFt.toStringAsFixed(0)} ft · ${zone.productType.label} · ${zone.colorPreset.label}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          '${zone.injections.length} injection${zone.injections.length == 1 ? '' : 's'} · '
          '${zone.controllerSlotCount} controller slot${zone.controllerSlotCount == 1 ? '' : 's'}',
          style: TextStyle(color: NexGenPalette.cyan.withValues(alpha: 0.7), fontSize: 12),
        ),
        if (additional > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Additional supply needed ($additional injection${additional == 1 ? '' : 's'})',
            style: TextStyle(color: NexGenPalette.amber, fontSize: 12),
          ),
        ],
        // Wire specs
        ..._buildWireSpecs(zone),
        // Outlet status
        ..._buildOutletStatus(zone),
        // Photos
        if (zone.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: zone.photoUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(zone.photoUrls[i], width: 56, height: 56, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildWireSpecs(InstallZone zone) {
    final byGauge = <WireGauge, double>{};
    for (final inj in zone.injections) {
      if (inj.wireGauge != WireGauge.direct) {
        byGauge[inj.wireGauge] = (byGauge[inj.wireGauge] ?? 0) + inj.wireRunFt;
      }
    }
    if (byGauge.isEmpty) return [];
    return [
      const SizedBox(height: 4),
      Text(
        byGauge.entries.map((e) => '${e.key.label}: ${e.value.toStringAsFixed(0)}ft').join(' · '),
        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
      ),
    ];
  }

  List<Widget> _buildOutletStatus(InstallZone zone) {
    final newOutlets = zone.mounts.where((m) => m.outletType == OutletType.newRequired).toList();
    if (newOutlets.isEmpty) return [];
    return [
      const SizedBox(height: 4),
      Text(
        '${newOutlets.length} new outlet${newOutlets.length == 1 ? '' : 's'} required',
        style: const TextStyle(color: Colors.orange, fontSize: 12),
      ),
    ];
  }

  Widget _buildTotalsCard(List<InstallZone> zones) {
    final totalFt = zones.fold(0.0, (acc, z) => acc + z.runLengthFt);
    final totalInj = zones.fold(0, (acc, z) => acc + z.injections.length);
    final totalSlots = zones.fold(0, (acc, z) => acc + z.controllerSlotCount);
    final totalPrice = zones.fold(0.0, (acc, z) => acc + z.priceUsd);

    // Aggregate wire by gauge
    final wireByGauge = <WireGauge, double>{};
    final newOutlets = <String>[];
    final additionalSupplies = <String>[];

    for (final zone in zones) {
      for (final inj in zone.injections) {
        if (inj.wireGauge != WireGauge.direct) {
          wireByGauge[inj.wireGauge] = (wireByGauge[inj.wireGauge] ?? 0) + inj.wireRunFt;
        }
      }
      for (final m in zone.mounts) {
        if (m.outletType == OutletType.newRequired) {
          newOutlets.add('${zone.name} @ ${m.positionFt.toStringAsFixed(0)}ft');
        }
        if (!m.isController && m.supplySize.isNotEmpty) {
          additionalSupplies.add('${zone.name}: ${m.supplySize}');
        }
      }
    }

    return _ReviewCard(
      title: 'Totals',
      children: [
        _totalRow('Total run length', '${totalFt.toStringAsFixed(0)} ft'),
        _totalRow('Injections', '$totalInj'),
        _totalRow('Controller slots', '$totalSlots of $controllerCapacitySlots'),
        if (additionalSupplies.isNotEmpty)
          _totalRow('Additional supplies', additionalSupplies.join(', ')),
        if (wireByGauge.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...wireByGauge.entries.map((e) =>
            _totalRow('Wire ${e.key.label}', '${e.value.toStringAsFixed(0)} ft'),
          ),
          _totalRow('10AWG ground', '${totalFt.toStringAsFixed(0)} ft'),
        ],
        if (newOutlets.isNotEmpty)
          _totalRow('New outlets (${newOutlets.length})', newOutlets.join(', ')),
        const Divider(color: NexGenPalette.line, height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total price', style: GoogleFonts.montserrat(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            Text('\$${totalPrice.toStringAsFixed(0)}', style: GoogleFonts.montserrat(color: NexGenPalette.green, fontSize: 22, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  Widget _buildDatesCard() {
    return _ReviewCard(
      title: 'Install dates',
      children: [
        _datePicker(
          label: 'Day 1 — Electrical pre-wire',
          date: _day1,
          onTap: () => _pickDate(isDay1: true),
        ),
        const SizedBox(height: 12),
        _datePicker(
          label: 'Day 2 — Install',
          date: _day2,
          onTap: _day1 == null ? null : () => _pickDate(isDay1: false),
        ),
        if (_day1 != null && _day2 != null && _day2!.isBefore(_day1!))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Day 2 must be after Day 1', style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _datePicker({required String label, DateTime? date, VoidCallback? onTap}) {
    final formatted = date != null
        ? '${date.month}/${date.day}/${date.year}'
        : 'Select date';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: date != null ? NexGenPalette.cyan.withValues(alpha: 0.4) : NexGenPalette.line),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: date != null ? NexGenPalette.cyan : NexGenPalette.textMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(formatted, style: TextStyle(color: date != null ? Colors.white : NexGenPalette.textMedium, fontSize: 15)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: NexGenPalette.textMedium),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
          Flexible(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

// ── Reusable review card ──────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;
  final Widget? trailing;
  final List<Widget> children;

  const _ReviewCard({required this.title, this.onEdit, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              if (trailing != null) ...[const Spacer(), trailing!],
              if (onEdit != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: onEdit,
                  child: Text('Edit', style: TextStyle(color: NexGenPalette.cyan, fontSize: 13)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
