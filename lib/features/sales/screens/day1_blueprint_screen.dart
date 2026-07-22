import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/screens/blueprint_widgets.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Day1BlueprintScreen
//
// On-site pre-wire blueprint that the Day 1 electrician works through.
// Five sections:
//
//   1. Home Overview      — home photo + colored channel-run polylines
//   2. Controller Mount   — location, interior/exterior, outlet distance, photo
//   3. Per Channel Cards  — start/end descriptions + photos + injection points
//   4. Materials          — line items filtered to power + hardware only
//   5. Task Checklist     — auto-generated wiring tasks with persistent state
//
// Bottom CTA: "Mark Day 1 complete" — enabled only when every task is checked.
// On confirm, calls SalesJobService.markDay1Complete() which atomically writes
// status=prewireComplete + day1CompletedAt + day1TechUid, pushing the job into
// the Day 2 queue.
// ─────────────────────────────────────────────────────────────────────────────

class Day1BlueprintScreen extends ConsumerStatefulWidget {
  final String jobId;
  const Day1BlueprintScreen({super.key, required this.jobId});

  @override
  ConsumerState<Day1BlueprintScreen> createState() =>
      _Day1BlueprintScreenState();
}

class _Day1BlueprintScreenState extends ConsumerState<Day1BlueprintScreen> {
  SalesJob? _job;
  bool _isLoading = true;
  bool _isCompleting = false;
  String? _error;

  String? _selectedChannelId;

  /// Scroll keys for each channel detail card so chip taps can scroll
  /// the corresponding card into view.
  final Map<String, GlobalKey> _channelKeys = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
          _isLoading = false;
          _error = 'Job not found';
        });
        return;
      }
      final job = SalesJob.fromJson(doc.data()!);
      setState(() {
        _job = job;
        _isLoading = false;
        for (final r in job.channelRuns) {
          _channelKeys.putIfAbsent(r.id, GlobalKey.new);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  // ── Task generation ──────────────────────────────────────────────────────
  //
  // Tasks are derived deterministically from the job state so their IDs
  // remain stable across loads. The persisted `day1CompletedTaskIds`
  // list on SalesJob is the source of truth for which boxes are checked.

  static const String _taskIdMountController = 'mount_controller';
  static const String _taskIdVerifyOutsideWall = 'verify_outside_wall';

  String _wireTaskId(ChannelRun r) => 'wire_${r.id}';
  String _injectionTaskId(PowerInjectionPoint p) => 'inj_${p.id}';

  List<BlueprintTask> _generateTasks(SalesJob job) {
    final tasks = <BlueprintTask>[];

    // Controller mount
    final mount = job.controllerMount;
    tasks.add(BlueprintTask(
      id: _taskIdMountController,
      label: mount != null
          ? 'Mount controller box at ${mount.locationDescription}'
          : 'Mount controller box',
      group: 'Controller',
    ));

    // Wire each channel
    for (final r in job.channelRuns) {
      final from = r.startDescription.isEmpty ? 'start' : r.startDescription;
      final to = r.endDescription.isEmpty ? 'end' : r.endDescription;
      tasks.add(BlueprintTask(
        id: _wireTaskId(r),
        label: 'Run wire for ${r.label.isEmpty ? 'Channel ${r.channelNumber}' : r.label}'
            ' from $from to $to — ${r.linearFeet.toStringAsFixed(0)}ft',
        group: 'Channel ${r.channelNumber}',
      ));
    }

    // Each injection point — caps and labels the wire
    for (final p in job.powerInjectionPoints) {
      tasks.add(BlueprintTask(
        id: _injectionTaskId(p),
        label: 'Install injection point at ${p.locationDescription}'
            ' — cap and label wire (${p.wireGauge.label})',
        group: 'Injection points',
      ));
    }

    // Final verification
    tasks.add(const BlueprintTask(
      id: _taskIdVerifyOutsideWall,
      label: 'Verify all wires are accessible outside wall for Day 2',
      group: 'Verification',
    ));

    return tasks;
  }

  // ── Task checkbox handler ────────────────────────────────────────────────

  Future<void> _toggleTask(String taskId, bool checked) async {
    final job = _job;
    if (job == null) return;
    // Read-only after the job moves out of Day 1.
    if (job.status == SalesJobStatus.prewireComplete ||
        job.status == SalesJobStatus.installComplete) {
      return;
    }

    final newIds = List<String>.from(job.day1CompletedTaskIds);
    if (checked) {
      if (!newIds.contains(taskId)) newIds.add(taskId);
    } else {
      newIds.remove(taskId);
    }

    // Optimistic local update
    final previous = job;
    final updated = job.copyWith(
      day1CompletedTaskIds: newIds,
      updatedAt: DateTime.now(),
    );
    setState(() => _job = updated);

    try {
      await ref.read(salesJobServiceProvider).updateJob(updated);
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() => _job = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  // ── Channel chip tap → highlight + scroll ────────────────────────────────

  void _selectChannel(String channelId) {
    setState(() => _selectedChannelId = channelId);
    final key = _channelKeys[channelId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        alignment: 0.05,
        curve: Curves.easeInOut,
      );
    }
  }

  // ── Mark Day 1 complete ──────────────────────────────────────────────────

  Future<void> _markDay1Complete() async {
    final job = _job;
    if (job == null || _isCompleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text(
          'Mark Day 1 complete?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This pushes the job into the Day 2 install queue. The customer '
          "won't be billed for the Day 2 visit yet — that happens after "
          'the install team finishes.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Mark complete',
              style: TextStyle(color: NexGenPalette.green),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final session = ref.read(installerSessionProvider);
    // TODO: replace with Firebase Auth UID when installer auth migrates
    final techUid = session?.installer.fullPin ?? '';
    if (techUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No installer session — cannot complete')),
      );
      return;
    }

    setState(() => _isCompleting = true);
    try {
      await ref
          .read(salesJobServiceProvider)
          .markDay1Complete(job.id, techUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Day 1 complete — pushed to Day 2 queue'),
          backgroundColor: NexGenPalette.green,
        ),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete: $e')),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Day 1 Blueprint'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: NexGenPalette.cyan),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.withValues(alpha: 0.7)),
                  ),
                )
              : _buildBody(_job!),
    );
  }

  Widget _buildBody(SalesJob job) {
    final tasks = _generateTasks(job);
    final completedIds = job.day1CompletedTaskIds.toSet();
    final completedCount =
        tasks.where((t) => completedIds.contains(t.id)).length;
    final allDone = tasks.isNotEmpty && completedCount == tasks.length;
    final alreadyComplete = job.status == SalesJobStatus.prewireComplete ||
        job.status == SalesJobStatus.installComplete;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _customerHeader(job),
                const SizedBox(height: 20),

                // Section 1 — Home overview with overlay
                _section1HomeOverview(job),
                const SizedBox(height: 20),

                // Section 2 — Controller mount
                _section2Controller(job),
                const SizedBox(height: 20),

                // Section 3 — Per channel cards
                _section3Channels(job),
                const SizedBox(height: 20),

                // Section 4 — Materials (power + hardware only)
                _section4Materials(job),
                const SizedBox(height: 20),

                // Section 5 — Task checklist
                _section5Tasks(job, tasks, completedIds, completedCount),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // Bottom CTA
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: alreadyComplete || !allDone || _isCompleting
                  ? null
                  : _markDay1Complete,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.green,
                disabledBackgroundColor:
                    NexGenPalette.green.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCompleting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      alreadyComplete
                          ? 'Day 1 already complete'
                          : allDone
                              ? 'Mark Day 1 complete →'
                              : 'Complete all tasks to finish',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Customer header ──────────────────────────────────────────────────────

  Widget _customerHeader(SalesJob job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          job.prospect.fullName,
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${job.prospect.address}, ${job.prospect.city}, '
          '${job.prospect.state} ${job.prospect.zipCode}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
        if (job.prospect.phone.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            job.prospect.phone,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  // ── Section 1: Home overview with channel polyline overlay ──────────────

  Widget _section1HomeOverview(SalesJob job) {
    final hasPhoto =
        job.homePhotoPath != null && job.homePhotoPath!.isNotEmpty;
    final hasChannels = job.channelRuns.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BlueprintSectionHeader(
          title: 'HOME OVERVIEW',
          subtitle: 'Tap a channel to jump to its detail card.',
          color: NexGenPalette.cyan,
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Container(
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexGenPalette.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? GestureDetector(
                    onTap: () => _expandPhoto(job.homePhotoPath!),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          job.homePhotoPath!,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: NexGenPalette.cyan,
                                strokeWidth: 2,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) =>
                              _photoPlaceholder(error: true),
                        ),
                        if (hasChannels)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: BlueprintOverlayPainter(
                                runs: job.channelRuns,
                                selectedChannelId: _selectedChannelId,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : _photoPlaceholder(),
          ),
        ),

        // Channel chip row — tap targets for highlight + scroll
        if (hasChannels) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < job.channelRuns.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: BlueprintChannelChip(
                      run: job.channelRuns[i],
                      color: blueprintColorForChannel(i),
                      selected:
                          _selectedChannelId == job.channelRuns[i].id,
                      onTap: () => _selectChannel(job.channelRuns[i].id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _photoPlaceholder({bool error = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.broken_image_outlined : Icons.home_outlined,
            color: Colors.white.withValues(alpha: 0.2),
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            error ? 'Could not load photo' : 'No home photo',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _expandPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white24,
                    size: 64,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 2: Controller mount ─────────────────────────────────────────

  Widget _section2Controller(SalesJob job) {
    final mount = job.controllerMount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BlueprintSectionHeader(
          title: 'CONTROLLER MOUNT',
          color: NexGenPalette.cyan,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: mount == null
              ? Text(
                  'No controller mount location set',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            mount.locationDescription.isEmpty
                                ? 'Location not set'
                                : mount.locationDescription,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _badge(
                          mount.isInteriorMount ? 'Interior' : 'Exterior',
                          NexGenPalette.cyan,
                        ),
                      ],
                    ),
                    if (mount.distanceFromOutletFeet != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.electrical_services,
                            size: 14,
                            color: NexGenPalette.textMedium,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${mount.distanceFromOutletFeet!.toStringAsFixed(0)} ft '
                            'to nearest outlet',
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (mount.photoPath != null &&
                        mount.photoPath!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: GestureDetector(
                            onTap: () => _expandPhoto(mount.photoPath!),
                            child: Image.network(
                              mount.photoPath!,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: NexGenPalette.matteBlack,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NexGenPalette.cyan,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => Container(
                                color: NexGenPalette.matteBlack,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ── Section 3: per-channel cards ────────────────────────────────────────

  Widget _section3Channels(SalesJob job) {
    if (job.channelRuns.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          BlueprintSectionHeader(
            title: 'CHANNELS',
            color: NexGenPalette.cyan,
          ),
          SizedBox(height: 12),
          Text(
            'No channels on this job',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BlueprintSectionHeader(
          title: 'CHANNELS',
          color: NexGenPalette.cyan,
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < job.channelRuns.length; i++) ...[
          Container(
            key: _channelKeys[job.channelRuns[i].id],
            child: _ChannelDetailCard(
              run: job.channelRuns[i],
              color: blueprintColorForChannel(i),
              selected:
                  _selectedChannelId == job.channelRuns[i].id,
              injections: job.powerInjectionPoints
                  .where((p) => p.channelRunId == job.channelRuns[i].id)
                  .toList(),
              onPhotoTap: _expandPhoto,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ── Section 4: materials (power + hardware only) ────────────────────────

  Widget _section4Materials(SalesJob job) {
    final breakdown = job.estimateBreakdown;
    final relevant = breakdown == null
        ? const <EstimateLineItem>[]
        : breakdown.lineItems
            .where((li) =>
                li.category == EstimateLineCategory.power ||
                li.category == EstimateLineCategory.hardware)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BlueprintSectionHeader(
          color: NexGenPalette.cyan,
          title: 'MATERIALS — WIRING ONLY',
          subtitle: 'Bring these to the site. LED strip and labor are '
              'not in this list.',
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: relevant.isEmpty
              ? Text(
                  breakdown == null
                      ? 'No estimate breakdown on this job yet'
                      : 'No wiring materials in the breakdown',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                )
              : Column(
                  children: [
                    for (final item in relevant) ...[
                      _materialRow(item),
                      if (item != relevant.last)
                        const Divider(
                          color: NexGenPalette.line,
                          height: 16,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _materialRow(EstimateLineItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          item.category == EstimateLineCategory.power
              ? Icons.bolt
              : Icons.handyman_outlined,
          color: NexGenPalette.cyan,
          size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.category.label.toUpperCase(),
                style: TextStyle(
                  color: NexGenPalette.cyan.withValues(alpha: 0.7),
                  fontSize: 10,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)} '
          '${item.unit}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ── Section 5: task checklist ───────────────────────────────────────────

  Widget _section5Tasks(
    SalesJob job,
    List<BlueprintTask> tasks,
    Set<String> completedIds,
    int completedCount,
  ) {
    // Group tasks by their `group` field, preserving insertion order.
    final grouped = <String, List<BlueprintTask>>{};
    for (final t in tasks) {
      grouped.putIfAbsent(t.group, () => []).add(t);
    }
    final progress = tasks.isEmpty ? 0.0 : completedCount / tasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: BlueprintSectionHeader(
                title: 'TASK CHECKLIST',
                color: NexGenPalette.cyan,
              ),
            ),
            Text(
              '$completedCount of ${tasks.length}',
              style: TextStyle(
                color: completedCount == tasks.length && tasks.isNotEmpty
                    ? NexGenPalette.green
                    : NexGenPalette.cyan,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: completedCount == tasks.length && tasks.isNotEmpty
                ? NexGenPalette.green
                : NexGenPalette.cyan,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 14),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: Text(
              entry.key.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          for (final task in entry.value)
            BlueprintTaskTile(
              task: task,
              checked: completedIds.contains(task.id),
              enabled: !(job.status == SalesJobStatus.prewireComplete ||
                  job.status == SalesJobStatus.installComplete),
              onChanged: (v) => _toggleTask(task.id, v),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ── Tiny helpers ────────────────────────────────────────────────────────

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-channel detail card
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelDetailCard extends StatelessWidget {
  final ChannelRun run;
  final Color color;
  final bool selected;
  final List<PowerInjectionPoint> injections;
  final ValueChanged<String> onPhotoTap;

  const _ChannelDetailCard({
    required this.run,
    required this.color,
    required this.selected,
    required this.injections,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? color : NexGenPalette.line,
          width: selected ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${run.channelNumber}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.label.isEmpty ? 'Untitled' : run.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${run.linearFeet.toStringAsFixed(0)} ft · ${run.direction.label}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _endpointBlock(
            label: 'START',
            description: run.startDescription,
            photoPath: run.startPhotoPath,
          ),
          const SizedBox(height: 12),
          _endpointBlock(
            label: 'END',
            description: run.endDescription,
            photoPath: run.endPhotoPath,
          ),
          if (injections.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: NexGenPalette.line, height: 1),
            const SizedBox(height: 12),
            Text(
              'INJECTION POINTS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            for (final p in injections) ...[
              _InjectionTile(point: p, onPhotoTap: onPhotoTap),
              if (p != injections.last) const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _endpointBlock({
    required String label,
    required String description,
    required String? photoPath,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description.isEmpty ? '(no description)' : description,
          style: TextStyle(
            color: description.isEmpty
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white,
            fontSize: 13,
            fontStyle:
                description.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        if (photoPath != null && photoPath.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => onPhotoTap(photoPath),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 80,
                width: double.infinity,
                child: Image.network(
                  photoPath,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: NexGenPalette.matteBlack,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NexGenPalette.cyan,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: NexGenPalette.matteBlack,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InjectionTile extends StatelessWidget {
  final PowerInjectionPoint point;
  final ValueChanged<String> onPhotoTap;
  const _InjectionTile({required this.point, required this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt, color: NexGenPalette.cyan, size: 16),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${point.distanceFromStartFeet.toStringAsFixed(0)} ft from start · '
                  '${point.wireGauge.label}'
                  '${point.requiresNewOutlet ? ' · NEW OUTLET' : ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
                if (point.hasNearbyOutlet &&
                    point.outletDistanceFeet != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Existing outlet ${point.outletDistanceFeet!.toStringAsFixed(0)} ft away',
                    style: TextStyle(
                      color: NexGenPalette.green.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (point.photoPath != null && point.photoPath!.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => onPhotoTap(point.photoPath!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  point.photoPath!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
                    color: NexGenPalette.matteBlack,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white24,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

