import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/estimate_wizard_notifier.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_form_fields.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_photo_capture.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_shell.dart';
import 'package:nexgen_command/theme.dart';

/// Step 4 of the Estimate Wizard: define power injection points per
/// channel run. Channels over 100ft without an injection point show a
/// warning chip — this matches the rule
/// MaterialCalculationService will enforce in Prompt 3.
class WizardStep4Injections extends ConsumerWidget {
  final String jobId;
  const WizardStep4Injections({super.key, required this.jobId});

  Future<void> _addOrEdit(
    BuildContext context,
    WidgetRef ref, {
    required ChannelRun forRun,
    PowerInjectionPoint? existing,
  }) async {
    final notifier = ref.read(estimateWizardProvider(jobId).notifier);
    final result = await showModalBottomSheet<PowerInjectionPoint>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PowerInjectionSheet(
        jobId: jobId,
        forRun: forRun,
        existing: existing,
      ),
    );
    if (result == null) return;
    if (existing == null) {
      notifier.addPowerInjectionPoint(result);
    } else {
      notifier.updatePowerInjectionPoint(result);
    }
  }

  void _continue(BuildContext context) {
    context.push(
      AppRoutes.salesWizardStep5.replaceFirst(':jobId', jobId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(estimateWizardProvider(jobId));
    final notifier = ref.read(estimateWizardProvider(jobId).notifier);
    final runs = job.channelRuns;

    return WizardShell(
      stepNumber: 4,
      stepTitle: 'Power injection',
      jobId: jobId,
      bottomAction: WizardContinueButton(onPressed: () => _continue(context)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WizardSectionHeader(
              title: 'POWER INJECTION POINTS',
              subtitle:
                  'Runs over 100ft must have at least one injection point '
                  'so the install team can keep voltage steady end-to-end.',
            ),
            const SizedBox(height: 16),

            if (runs.isEmpty)
              _emptyState()
            else
              for (final run in runs) ...[
                _ChannelInjectionsSection(
                  run: run,
                  injections: notifier.injectionsForRun(run.id),
                  needsInjection: run.linearFeet > 100 &&
                      notifier.injectionsForRun(run.id).isEmpty,
                  onAdd: () => _addOrEdit(context, ref, forRun: run),
                  onEdit: (point) => _addOrEdit(
                    context,
                    ref,
                    forRun: run,
                    existing: point,
                  ),
                  onRemove: (point) => notifier
                      .removePowerInjectionPoint(point.id),
                ),
                const SizedBox(height: 16),
              ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.bolt_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'No channels to inject yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Go back to Step 3 to add channels first',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-channel section
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelInjectionsSection extends StatelessWidget {
  final ChannelRun run;
  final List<PowerInjectionPoint> injections;
  final bool needsInjection;
  final VoidCallback onAdd;
  final ValueChanged<PowerInjectionPoint> onEdit;
  final ValueChanged<PowerInjectionPoint> onRemove;

  const _ChannelInjectionsSection({
    required this.run,
    required this.injections,
    required this.needsInjection,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: needsInjection
              ? NexGenPalette.amber.withValues(alpha: 0.5)
              : NexGenPalette.line,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Channel ${run.channelNumber} — '
                      '${run.label.isEmpty ? 'Untitled' : run.label}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${run.linearFeet.toStringAsFixed(0)} ft · '
                      '${injections.length} injection'
                      '${injections.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (needsInjection)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NexGenPalette.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: NexGenPalette.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 12, color: NexGenPalette.amber),
                      SizedBox(width: 4),
                      Text(
                        'Needs injection',
                        style: TextStyle(
                          color: NexGenPalette.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          for (final p in injections) ...[
            _InjectionTile(
              point: p,
              onTap: () => onEdit(p),
              onRemove: () => onRemove(p),
            ),
            const SizedBox(height: 8),
          ],

          OutlinedButton.icon(
            onPressed: onAdd,
            icon: Icon(Icons.add, color: NexGenPalette.cyan, size: 18),
            label: Text(
              'Add injection point',
              style: TextStyle(color: NexGenPalette.cyan, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: NexGenPalette.cyan.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InjectionTile extends StatelessWidget {
  final PowerInjectionPoint point;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _InjectionTile({
    required this.point,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.bolt, color: NexGenPalette.cyan, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.locationDescription.isEmpty
                          ? 'Injection point'
                          : point.locationDescription,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${point.distanceFromStartFeet.toStringAsFixed(0)} ft '
                      'from start · ${point.wireGauge.label}'
                      '${point.requiresNewOutlet ? ' · new outlet' : ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.red.withValues(alpha: 0.6),
                  size: 18,
                ),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add/Edit Power Injection bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PowerInjectionSheet extends StatefulWidget {
  final String jobId;
  final ChannelRun forRun;
  final PowerInjectionPoint? existing;

  const _PowerInjectionSheet({
    required this.jobId,
    required this.forRun,
    required this.existing,
  });

  @override
  State<_PowerInjectionSheet> createState() => _PowerInjectionSheetState();
}

class _PowerInjectionSheetState extends State<_PowerInjectionSheet> {
  final _locationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _outletDistanceCtrl = TextEditingController();

  bool _hasNearbyOutlet = false;
  bool _requiresNewOutlet = false;
  WireGauge _wireGauge = WireGauge.direct;
  String? _photoPath;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _locationCtrl.text = e.locationDescription;
      _distanceCtrl.text = e.distanceFromStartFeet > 0
          ? e.distanceFromStartFeet.toStringAsFixed(1)
          : '';
      _hasNearbyOutlet = e.hasNearbyOutlet;
      if (e.outletDistanceFeet != null) {
        _outletDistanceCtrl.text = e.outletDistanceFeet!.toStringAsFixed(1);
      }
      _requiresNewOutlet = e.requiresNewOutlet;
      _wireGauge = e.wireGauge;
      _photoPath = e.photoPath;
    }
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _distanceCtrl.dispose();
    _outletDistanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    setState(() => _isUploading = true);
    try {
      final url = await pickAndUploadWizardPhoto(
        context: context,
        jobId: widget.jobId,
        subPath:
            'injection_${widget.forRun.channelNumber}_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (url != null) setState(() => _photoPath = url);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _save() {
    final location = _locationCtrl.text.trim();
    final distance = double.tryParse(_distanceCtrl.text) ?? 0.0;
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location description is required')),
      );
      return;
    }
    if (distance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Distance from start is required')),
      );
      return;
    }

    final point = PowerInjectionPoint(
      id: widget.existing?.id ??
          'inj_${DateTime.now().millisecondsSinceEpoch}',
      channelRunId: widget.forRun.id,
      locationDescription: location,
      distanceFromStartFeet: distance,
      hasNearbyOutlet: _hasNearbyOutlet,
      outletDistanceFeet: _hasNearbyOutlet
          ? double.tryParse(_outletDistanceCtrl.text)
          : null,
      photoPath: _photoPath,
      wireGauge: _wireGauge,
      requiresNewOutlet: _requiresNewOutlet,
    );
    Navigator.of(context).pop(point);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Channel ${widget.forRun.channelNumber} · '
                    '${widget.existing != null ? 'Edit' : 'New'} injection',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: NexGenPalette.textMedium),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WizardTextField(
                    controller: _locationCtrl,
                    label: 'Location description',
                    hint: 'e.g. Mid-roof gable peak',
                    icon: Icons.place_outlined,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  WizardTextField(
                    controller: _distanceCtrl,
                    label: 'Distance from run start (ft)',
                    icon: Icons.straighten,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: NexGenPalette.cyan,
                    title: const Text(
                      'Existing outlet nearby',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    value: _hasNearbyOutlet,
                    onChanged: (v) => setState(() => _hasNearbyOutlet = v),
                  ),
                  if (_hasNearbyOutlet) ...[
                    const SizedBox(height: 4),
                    WizardTextField(
                      controller: _outletDistanceCtrl,
                      label: 'Distance to that outlet (ft)',
                      icon: Icons.electrical_services,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.]'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: NexGenPalette.amber,
                    title: const Text(
                      'Requires new outlet',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Adds an electrician task to Day 1',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                    value: _requiresNewOutlet,
                    onChanged: (v) => setState(() => _requiresNewOutlet = v),
                  ),
                  const SizedBox(height: 8),

                  const Text(
                    'Wire gauge',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  WizardSegmentedSelector<WireGauge>(
                    values: WireGauge.values,
                    selected: _wireGauge,
                    labelBuilder: (g) => g.label,
                    onChanged: (g) => setState(() => _wireGauge = g),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isUploading ? null : _capturePhoto,
                      icon: _isUploading
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: NexGenPalette.cyan,
                              ),
                            )
                          : Icon(
                              _photoPath != null
                                  ? Icons.check_circle
                                  : Icons.add_a_photo_outlined,
                              color: _photoPath != null
                                  ? NexGenPalette.green
                                  : NexGenPalette.cyan,
                              size: 18,
                            ),
                      label: Text(
                        _photoPath != null
                            ? 'Photo saved — replace'
                            : 'Add photo',
                        style: TextStyle(
                          color: _photoPath != null
                              ? NexGenPalette.green
                              : NexGenPalette.cyan,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: (_photoPath != null
                                  ? NexGenPalette.green
                                  : NexGenPalette.cyan)
                              .withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save injection point',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
