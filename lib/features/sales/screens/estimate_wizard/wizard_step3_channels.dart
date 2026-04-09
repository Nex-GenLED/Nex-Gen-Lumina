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

/// Step 3 of the Estimate Wizard: define each LED channel run on the
/// home. List view + add/edit bottom sheet.
class WizardStep3Channels extends ConsumerWidget {
  final String jobId;
  const WizardStep3Channels({super.key, required this.jobId});

  Future<void> _addOrEdit(
    BuildContext context,
    WidgetRef ref, {
    ChannelRun? existing,
  }) async {
    final notifier = ref.read(estimateWizardProvider(jobId).notifier);
    final result = await showModalBottomSheet<ChannelRun>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChannelRunSheet(
        jobId: jobId,
        existing: existing,
        nextChannelNumber: notifier.nextChannelNumber,
      ),
    );
    if (result == null) return;
    if (existing == null) {
      notifier.addChannelRun(result);
    } else {
      notifier.updateChannelRun(result);
    }
  }

  void _continue(BuildContext context) {
    context.push(
      AppRoutes.salesWizardStep4.replaceFirst(':jobId', jobId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(estimateWizardProvider(jobId));
    final runs = job.channelRuns;
    final hasAny = runs.isNotEmpty;

    return WizardShell(
      stepNumber: 3,
      stepTitle: 'Channel setup',
      jobId: jobId,
      bottomAction: WizardContinueButton(
        onPressed: hasAny ? () => _continue(context) : null,
        label: hasAny ? 'Continue →' : 'Add a channel to continue',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WizardSectionHeader(
              title: 'LED CHANNEL RUNS',
              subtitle:
                  'Each channel is one continuous LED strip wired to one '
                  'WLED output port.',
            ),
            const SizedBox(height: 16),

            if (!hasAny) _emptyState(context, ref),

            for (int i = 0; i < runs.length; i++) ...[
              Dismissible(
                key: ValueKey('channel_${runs[i].id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete, color: Colors.red),
                ),
                onDismissed: (_) => ref
                    .read(estimateWizardProvider(jobId).notifier)
                    .removeChannelRun(runs[i].id),
                child: _ChannelRunCard(
                  run: runs[i],
                  onTap: () => _addOrEdit(context, ref, existing: runs[i]),
                ),
              ),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _addOrEdit(context, ref),
              icon: Icon(Icons.add, color: NexGenPalette.cyan),
              label: Text('Add channel',
                  style: TextStyle(color: NexGenPalette.cyan)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: NexGenPalette.cyan.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.cable,
            size: 56,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'No channels yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add your first LED run',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channel run list card
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelRunCard extends StatelessWidget {
  final ChannelRun run;
  final VoidCallback onTap;
  const _ChannelRunCard({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${run.channelNumber}',
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.label.isEmpty ? 'Untitled run' : run.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _chip('${run.linearFeet.toStringAsFixed(0)} ft'),
                        _chip(run.direction.label),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add/Edit Channel Run bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelRunSheet extends StatefulWidget {
  final String jobId;
  final ChannelRun? existing;
  final int nextChannelNumber;

  const _ChannelRunSheet({
    required this.jobId,
    required this.existing,
    required this.nextChannelNumber,
  });

  @override
  State<_ChannelRunSheet> createState() => _ChannelRunSheetState();
}

class _ChannelRunSheetState extends State<_ChannelRunSheet> {
  final _labelCtrl = TextEditingController();
  final _startDescCtrl = TextEditingController();
  final _endDescCtrl = TextEditingController();
  final _linearFeetCtrl = TextEditingController();

  late int _channelNumber;
  RunDirection _direction = RunDirection.leftToRight;
  String? _startPhotoPath;
  String? _endPhotoPath;
  bool _isUploadingStart = false;
  bool _isUploadingEnd = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _channelNumber = e.channelNumber;
      _labelCtrl.text = e.label;
      _startDescCtrl.text = e.startDescription;
      _endDescCtrl.text = e.endDescription;
      _linearFeetCtrl.text = e.linearFeet > 0
          ? e.linearFeet.toStringAsFixed(1)
          : '';
      _direction = e.direction;
      _startPhotoPath = e.startPhotoPath;
      _endPhotoPath = e.endPhotoPath;
    } else {
      _channelNumber = widget.nextChannelNumber;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _startDescCtrl.dispose();
    _endDescCtrl.dispose();
    _linearFeetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto({required bool isStart}) async {
    setState(() {
      if (isStart) {
        _isUploadingStart = true;
      } else {
        _isUploadingEnd = true;
      }
    });
    try {
      final url = await pickAndUploadWizardPhoto(
        context: context,
        jobId: widget.jobId,
        subPath: 'channel_${_channelNumber}_${isStart ? 'start' : 'end'}',
      );
      if (url != null) {
        setState(() {
          if (isStart) {
            _startPhotoPath = url;
          } else {
            _endPhotoPath = url;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isStart) {
            _isUploadingStart = false;
          } else {
            _isUploadingEnd = false;
          }
        });
      }
    }
  }

  void _save() {
    final label = _labelCtrl.text.trim();
    final feet = double.tryParse(_linearFeetCtrl.text) ?? 0.0;
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Channel label is required')),
      );
      return;
    }
    if (feet <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Linear feet must be greater than 0')),
      );
      return;
    }

    final run = ChannelRun(
      id: widget.existing?.id ??
          'channel_${DateTime.now().millisecondsSinceEpoch}',
      channelNumber: _channelNumber,
      label: label,
      linearFeet: feet,
      startDescription: _startDescCtrl.text.trim(),
      endDescription: _endDescCtrl.text.trim(),
      direction: _direction,
      startPhotoPath: _startPhotoPath,
      endPhotoPath: _endPhotoPath,
      tracePoints: widget.existing?.tracePoints ?? const [],
    );
    Navigator.of(context).pop(run);
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
                Text(
                  widget.existing != null
                      ? 'Edit Channel $_channelNumber'
                      : 'New Channel $_channelNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
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
                    controller: _labelCtrl,
                    label: 'Label',
                    hint: 'e.g. Front Roofline',
                    icon: Icons.label_outline,
                  ),
                  const SizedBox(height: 12),
                  WizardTextField(
                    controller: _linearFeetCtrl,
                    label: 'Linear feet',
                    icon: Icons.straighten,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Run direction',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  WizardSegmentedSelector<RunDirection>(
                    values: RunDirection.values,
                    selected: _direction,
                    labelBuilder: (d) => d.label,
                    onChanged: (d) => setState(() => _direction = d),
                  ),
                  const SizedBox(height: 16),

                  WizardTextField(
                    controller: _startDescCtrl,
                    label: 'Where does this run start?',
                    hint: 'e.g. Northeast corner of garage',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  _photoButton(
                    isStart: true,
                    isUploading: _isUploadingStart,
                    hasPhoto: _startPhotoPath != null,
                  ),
                  const SizedBox(height: 16),

                  WizardTextField(
                    controller: _endDescCtrl,
                    label: 'Where does this run end?',
                    hint: 'e.g. Southwest corner of porch',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  _photoButton(
                    isStart: false,
                    isUploading: _isUploadingEnd,
                    hasPhoto: _endPhotoPath != null,
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
                  'Save channel',
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

  Widget _photoButton({
    required bool isStart,
    required bool isUploading,
    required bool hasPhoto,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isUploading ? null : () => _pickPhoto(isStart: isStart),
        icon: isUploading
            ? const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: NexGenPalette.cyan,
                ),
              )
            : Icon(
                hasPhoto ? Icons.check_circle : Icons.add_a_photo_outlined,
                color: hasPhoto ? NexGenPalette.green : NexGenPalette.cyan,
                size: 18,
              ),
        label: Text(
          hasPhoto
              ? '${isStart ? 'Start' : 'End'} photo saved — replace'
              : 'Add ${isStart ? 'start' : 'end'} photo',
          style: TextStyle(
            color: hasPhoto ? NexGenPalette.green : NexGenPalette.cyan,
            fontSize: 13,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: (hasPhoto ? NexGenPalette.green : NexGenPalette.cyan)
                .withValues(alpha: 0.4),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
