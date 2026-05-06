import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/services/inventory_service.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Day 2 Wrap-Up Screen
//
// Sequential 4-step wizard the install team works through to close the
// job. Steps in order:
//
//   1. Install Photos          — one photo per ChannelRun, upload to
//                                Firebase Storage at
//                                sales/{jobId}/install_complete/{channelId}.jpg
//                                Persisted on SalesJob.installCompletePhotoUrls.
//   2. Material Check-In       — actual-vs-estimate quantities for each
//                                EstimateLineItem. Persisted on
//                                SalesJob.actualMaterialUsage.
//                                **Does NOT call InventoryService** in this
//                                prompt — that wires up in a follow-up.
//   3. Customer Account        — review prefilled prospect info, write any
//                                edits back to SalesJob.prospect, fire the
//                                createCustomerAccount Cloud Function, then
//                                offer "Launch Lumina Setup" which pre-fills
//                                installerCustomerInfoProvider /
//                                installerPhotoUrlProvider and pushes the
//                                installer wizard.
//   4. Close Job               — summary screen + Complete Job button.
//                                Calls SalesJobService.markDay2Complete,
//                                shows a confirmation AlertDialog with the
//                                wrap-up totals, then pops back to the Day 2
//                                queue.
//
// Cloud Function contract (createCustomerAccount, region us-central1):
//   Input  : { email, displayName, jobId, dealerCode }
//   Output : { uid, tempPasswordSent }
// Server-side implementation lives separately — the function does not
// exist yet, the client-side call surfaces an `unimplemented` error
// gracefully via a snackbar so the rest of the wrap-up flow keeps
// working in development.
// ─────────────────────────────────────────────────────────────────────────────

enum _WrapUpStep { photos, materials, account, close }

extension _WrapUpStepX on _WrapUpStep {
  int get index1Based => _WrapUpStep.values.indexOf(this) + 1;
  String get label => switch (this) {
        _WrapUpStep.photos => 'Install photos',
        _WrapUpStep.materials => 'Material check-in',
        _WrapUpStep.account => 'Customer account',
        _WrapUpStep.close => 'Close job',
      };
}

const int _kWrapUpStepCount = 4;

class Day2WrapUpScreen extends ConsumerStatefulWidget {
  final String jobId;
  const Day2WrapUpScreen({super.key, required this.jobId});

  @override
  ConsumerState<Day2WrapUpScreen> createState() => _Day2WrapUpScreenState();
}

class _Day2WrapUpScreenState extends ConsumerState<Day2WrapUpScreen> {
  SalesJob? _job;
  bool _isLoading = true;
  String? _error;

  _WrapUpStep _step = _WrapUpStep.photos;

  // ── Step 1 state — channel id → photo url ─────────────────────────────
  /// Maps `ChannelRun.id` to the captured install-complete photo URL.
  /// Mirrors the persisted shape on [SalesJob.installCompletePhotoUrls],
  /// which we serialize as a parallel list ordered to match
  /// [SalesJob.channelRuns].
  final Map<String, String> _photoByChannel = {};
  final Set<String> _uploadingChannels = {};

  // ── Step 2 state — itemId → returned qty input controller ─────────────
  final Map<String, TextEditingController> _returnedCtrls = {};

  // ── Step 3 state — customer info form ─────────────────────────────────
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _createdUserUid;
  bool _isCreatingAccount = false;

  // ── Step 4 state ──────────────────────────────────────────────────────
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  @override
  void dispose() {
    for (final c in _returnedCtrls.values) {
      c.dispose();
    }
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
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
      _hydrateFromJob(job);
      setState(() {
        _job = job;
        _isLoading = false;
        // If wrap-up was already finished previously (install
        // complete OR completePaid), jump to the close step so the
        // install team sees the summary directly.
        if (job.status == SalesJobStatus.installComplete ||
            job.status == SalesJobStatus.completePaid) {
          _step = _WrapUpStep.close;
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

  void _hydrateFromJob(SalesJob job) {
    // Step 1: rebuild the channel→photo map from the persisted parallel
    // list. The list is positional — i-th url corresponds to the i-th
    // channel run. Tolerates missing/short lists from older saves.
    _photoByChannel.clear();
    for (int i = 0;
        i < job.channelRuns.length && i < job.installCompletePhotoUrls.length;
        i++) {
      final url = job.installCompletePhotoUrls[i];
      if (url.isNotEmpty) {
        _photoByChannel[job.channelRuns[i].id] = url;
      }
    }

    // Step 2: seed the controllers from any existing usage record.
    final existingUsage = job.actualMaterialUsage;
    if (existingUsage != null) {
      for (final entry in existingUsage.entries) {
        _returnedCtrls[entry.itemId] = TextEditingController(
          text: entry.returnedQty.toStringAsFixed(
            entry.returnedQty == entry.returnedQty.roundToDouble() ? 0 : 1,
          ),
        );
      }
    }

    // Step 3: prefill from prospect.
    _firstNameCtrl.text = job.prospect.firstName;
    _lastNameCtrl.text = job.prospect.lastName;
    _emailCtrl.text = job.prospect.email;
    _phoneCtrl.text = job.prospect.phone;
    if (job.linkedUserId != null && job.linkedUserId!.isNotEmpty) {
      _createdUserUid = job.linkedUserId;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Returns the persisted parallel list for [SalesJob.installCompletePhotoUrls]
  /// based on the current [_photoByChannel] map.
  List<String> _photoUrlsList(SalesJob job) {
    return [
      for (final r in job.channelRuns) _photoByChannel[r.id] ?? '',
    ];
  }

  bool get _allPhotosCaptured {
    final job = _job;
    if (job == null) return false;
    if (job.channelRuns.isEmpty) return true;
    return job.channelRuns.every((r) => _photoByChannel.containsKey(r.id));
  }

  List<EstimateLineItem> get _materialItems {
    final breakdown = _job?.estimateBreakdown;
    if (breakdown == null) return const [];
    // Hide the labor line — it isn't a physical material.
    return breakdown.lineItems
        .where((li) => li.category != EstimateLineCategory.labor)
        .toList();
  }

  TextEditingController _returnedCtrlFor(EstimateLineItem item) {
    return _returnedCtrls.putIfAbsent(
      item.id,
      () => TextEditingController(),
    );
  }

  // ── Step 1 — photo capture & upload ───────────────────────────────────

  Future<void> _capturePhotoForChannel(ChannelRun run) async {
    if (_uploadingChannels.contains(run.id)) return;

    final source = await _showSourcePicker();
    if (source == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploadingChannels.add(run.id));
    try {
      final ref = FirebaseStorage.instance.ref().child(
            'sales/${widget.jobId}/install_complete/${run.id}.jpg',
          );
      final bytes = await image.readAsBytes();
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _photoByChannel[run.id] = url;
      });

      // Persist incrementally so a crash doesn't lose progress.
      await _persistPhotos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingChannels.remove(run.id));
      }
    }
  }

  Future<ImageSource?> _showSourcePicker() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera,
                color: NexGenPalette.green,
              ),
              title: const Text(
                'Take photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: NexGenPalette.green,
              ),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _persistPhotos() async {
    final job = _job;
    if (job == null) return;
    final updated = job.copyWith(
      installCompletePhotoUrls: _photoUrlsList(job),
      updatedAt: DateTime.now(),
    );
    try {
      await ref.read(salesJobServiceProvider).updateJob(updated);
      if (mounted) setState(() => _job = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  // ── Step 2 — material check-in (record only) ──────────────────────────

  Future<void> _persistMaterialUsage() async {
    final job = _job;
    if (job == null) return;
    final session = ref.read(installerSessionProvider);
    // TODO: replace with Firebase Auth UID when installer auth migrates
    final pin = session?.installer.fullPin ?? '';

    final entries = <ActualMaterialUsageEntry>[];
    for (final item in _materialItems) {
      final returned =
          double.tryParse(_returnedCtrlFor(item).text.trim()) ?? 0;
      entries.add(ActualMaterialUsageEntry(
        itemId: item.id,
        description: item.description,
        estimatedQty: item.quantity,
        returnedQty: returned,
      ));
    }

    final usage = ActualMaterialUsage(
      entries: entries,
      recordedAt: DateTime.now(),
      recordedByPin: pin,
    );
    final updated = job.copyWith(
      actualMaterialUsage: usage,
      updatedAt: DateTime.now(),
    );
    await ref.read(salesJobServiceProvider).updateJob(updated);
    if (mounted) setState(() => _job = updated);

    // Push inventory delta to dealer stock. Best-effort: a job may not have
    // gone through formal material checkout (no /sales_jobs/{id}/materialList
    // doc) — in that case there's nothing for InventoryService to reconcile,
    // so we silently skip rather than blocking the install close-out.
    try {
      final inv = ref.read(inventoryServiceProvider);
      final list = await inv.watchJobMaterialList(job.id).first;
      if (list != null && list.lines.isNotEmpty) {
        final returnedById = {
          for (final e in entries) e.itemId: e.returnedQty,
        };
        // Update returnedQty on lines that match a wrap-up entry by id.
        // For lines we recognise, set usedDay2 to whatever the line had
        // already checked out minus prior day-1 usage minus this returned
        // quantity (waste falls out as the residual computed inside
        // InventoryService.checkInFinal).
        final finalLines = list.lines.map((line) {
          final returned = returnedById[line.materialId];
          if (returned == null) return line;
          final usedDay2 = (line.checkedOutQty - line.usedDay1 - returned)
              .clamp(0, line.checkedOutQty)
              .toDouble();
          return line.copyWith(
            returnedQty: returned,
            usedDay2: usedDay2,
          );
        }).toList();

        await inv.checkInFinal(
          jobId: job.id,
          dealerCode: job.dealerCode,
          installerId: pin,
          finalLines: finalLines,
        );
      }
    } catch (e) {
      // Don't block job completion on inventory write failure — the
      // SalesJob.actualMaterialUsage write above is the durable record.
      debugPrint('Day2 inventory check-in failed: $e');
    }
  }

  // ── Step 3 — customer account creation ────────────────────────────────

  Future<void> _createCustomerAccount() async {
    final job = _job;
    if (job == null || _isCreatingAccount) return;

    final email = _emailCtrl.text.trim().toLowerCase();
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (email.isEmpty || firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and email are required')),
      );
      return;
    }

    setState(() => _isCreatingAccount = true);
    try {
      // 1. Write any corrections back to SalesJob.prospect first so the
      //    dealer dashboard reflects the updated info even if the Cloud
      //    Function call fails. Note: SalesProspect has no copyWith — we
      //    rebuild it manually.
      final correctedProspect = SalesProspect(
        id: job.prospect.id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: _phoneCtrl.text.trim(),
        address: job.prospect.address,
        city: job.prospect.city,
        state: job.prospect.state,
        zipCode: job.prospect.zipCode,
        referrerUid: job.prospect.referrerUid,
        referralCode: job.prospect.referralCode,
        homePhotoUrls: job.prospect.homePhotoUrls,
        salespersonNotes: job.prospect.salespersonNotes,
        createdAt: job.prospect.createdAt,
      );
      final correctedJob = job.copyWith(
        prospect: correctedProspect,
        updatedAt: DateTime.now(),
      );
      await ref.read(salesJobServiceProvider).updateJob(correctedJob);
      if (!mounted) return;
      setState(() => _job = correctedJob);

      // 2. Fire the createCustomerAccount callable.
      // Server contract: in { email, displayName, jobId, dealerCode }
      //                  out { uid, tempPasswordSent }
      final functions =
          FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('createCustomerAccount');
      final result = await callable.call<Map<String, dynamic>>({
        'email': email,
        'displayName': '$firstName $lastName'.trim(),
        'jobId': widget.jobId,
        'dealerCode': correctedJob.dealerCode,
      });
      final uid = result.data['uid'] as String?;
      if (uid == null || uid.isEmpty) {
        throw StateError(
          'createCustomerAccount returned no uid',
        );
      }

      // 3. Persist the linkage WITHOUT touching status. Step 4 owns the
      //    installComplete transition via markDay2Complete().
      await ref.read(salesJobServiceProvider).setLinkedUserId(
            widget.jobId,
            uid,
          );
      if (!mounted) return;
      setState(() {
        _job = correctedJob.copyWith(linkedUserId: uid);
        _createdUserUid = uid;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account created — setup link sent to $email'),
          backgroundColor: NexGenPalette.green,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // The most likely error in dev is `unimplemented` because the
      // Cloud Function hasn't been written yet. Surface it gracefully so
      // the rest of the flow keeps working.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account creation unavailable: ${e.message ?? e.code}. '
            'You can skip and the customer can be created later.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account creation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isCreatingAccount = false);
    }
  }

  void _launchLuminaSetup() {
    final job = _job;
    if (job == null) return;

    // Pre-fill the installer wizard's customer info + home photo
    // providers, then push. The installer wizard reads from these
    // providers on entry — see installer_setup_wizard.dart _loadDraft
    // for the parallel pattern.
    ref.read(installerCustomerInfoProvider.notifier).state = CustomerInfo(
      name: job.prospect.fullName,
      email: job.prospect.email,
      phone: job.prospect.phone,
      address: job.prospect.address,
      city: job.prospect.city,
      state: job.prospect.state,
      zipCode: job.prospect.zipCode,
    );
    if (job.homePhotoPath != null && job.homePhotoPath!.isNotEmpty) {
      ref.read(installerPhotoUrlProvider.notifier).state = job.homePhotoPath;
    }
    // Site mode stays at the default (residential), wizard step stays at
    // customerInfo (default). Channel run data stays on the SalesJob and
    // is accessible via linkedUserId — out of scope for this prompt.

    context.push(AppRoutes.installerWizard);
  }

  // ── Step 4 — close job + completion summary ───────────────────────────

  Future<void> _completeJob() async {
    final job = _job;
    if (job == null || _isCompleting) return;

    final session = ref.read(installerSessionProvider);
    // TODO: replace with Firebase Auth UID when installer auth migrates
    final techUid = session?.installer.fullPin ?? '';
    if (techUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No installer session — cannot complete'),
        ),
      );
      return;
    }

    setState(() => _isCompleting = true);
    try {
      await ref
          .read(salesJobServiceProvider)
          .markDay2Complete(widget.jobId, techUid);
      if (!mounted) return;

      // Reload the job so the screen rebuilds with status =
      // installComplete. Don't pop yet — the final payment gate
      // (Part 10) renders inside _buildStep4Close once the status is
      // installComplete + !finalPaymentCollected. The dealer
      // continues from inside the wrap-up screen by either marking
      // payment collected or sending a reminder; pop happens when
      // payment is recorded.
      await _loadJob();
      if (!mounted) return;
      setState(() => _isCompleting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to complete: $e')),
      );
    }
  }

  /// Resolve a stable identifier for the person taking action. Same
  /// fallback chain as _completeJob: Firebase Auth uid first, then
  /// installer pin, then 'unknown'.
  String _byUid() {
    final fbUid = FirebaseAuth.instance.currentUser?.uid;
    if (fbUid != null && fbUid.isNotEmpty) return fbUid;
    final session = ref.read(installerSessionProvider);
    return session?.installer.fullPin ?? 'unknown';
  }

  /// Final payment gate (Part 10). Marks finalPaymentCollected,
  /// flips status to completePaid, and pops back to the queue.
  Future<void> _markFinalPayment() async {
    final job = _job;
    if (job == null || _isCompleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Confirm Final Payment',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Confirm that ${job.prospect.fullName} has paid the '
          'remaining balance? The job will be archived as complete.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.green,
              foregroundColor: Colors.black,
            ),
            child: const Text('Yes, payment collected'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isCompleting = true);
    try {
      await ref.read(salesJobServiceProvider).markFinalPaymentCollected(
            jobId: job.id,
            byUid: _byUid(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job complete! Payment recorded.'),
          backgroundColor: NexGenPalette.green,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      context.go(AppRoutes.day2Queue);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record payment: $e')),
      );
    }
  }

  /// Queues a payment-due reminder via the existing
  /// /email_notifications collection (same Cloud-Function-driven
  /// queue used for new-lead emails). Until the Cloud Function
  /// handler for type 'payment_reminder' lands, the doc accumulates
  /// as a queue.
  Future<void> _sendPaymentReminder() async {
    final job = _job;
    if (job == null) return;
    final balance = job.totalPriceUsd - (job.depositAmount ?? 0);
    try {
      await ref.read(salesJobServiceProvider).queuePaymentReminder(
            jobId: job.id,
            customerUid: job.linkedUserId,
            customerName: job.prospect.fullName,
            customerEmail: job.prospect.email,
            customerPhone: job.prospect.phone,
            amount: balance,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder queued — Nex-Gen will dispatch shortly.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to queue reminder: $e')),
      );
    }
  }

  // _showCompletionSummary + _summaryRow were removed in Part 10.
  // Post-install celebration is now in _FinalPaymentSection /
  // _PaidConfirmationCard inside _buildStep4Close so the dealer can
  // record the final payment before the screen pops back to the
  // queue.

  // ── Navigation between steps ──────────────────────────────────────────

  bool _canAdvance() {
    switch (_step) {
      case _WrapUpStep.photos:
        return _allPhotosCaptured;
      case _WrapUpStep.materials:
      case _WrapUpStep.account:
      case _WrapUpStep.close:
        return true;
    }
  }

  Future<void> _advance() async {
    // Persist the current step's data before moving on.
    if (_step == _WrapUpStep.materials) {
      try {
        await _persistMaterialUsage();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      final nextIdx = _step.index + 1;
      if (nextIdx < _WrapUpStep.values.length) {
        _step = _WrapUpStep.values[nextIdx];
      }
    });
  }

  void _back() {
    setState(() {
      final prevIdx = _step.index - 1;
      if (prevIdx >= 0) {
        _step = _WrapUpStep.values[prevIdx];
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Day 2 Wrap-Up'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: NexGenPalette.green),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.withValues(alpha: 0.7),
                    ),
                  ),
                )
              : _buildBody(_job!),
    );
  }

  Widget _buildBody(SalesJob job) {
    return Column(
      children: [
        _stepIndicator(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: switch (_step) {
              _WrapUpStep.photos => _buildStep1Photos(job),
              _WrapUpStep.materials => _buildStep2Materials(job),
              _WrapUpStep.account => _buildStep3Account(job),
              _WrapUpStep.close => _buildStep4Close(job),
            },
          ),
        ),
        _bottomBar(job),
      ],
    );
  }

  // ── Step indicator ────────────────────────────────────────────────────

  Widget _stepIndicator() {
    final progress = _step.index1Based / _kWrapUpStepCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${_step.index1Based} of $_kWrapUpStepCount — ${_step.label}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              color: NexGenPalette.green,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: install photos ────────────────────────────────────────────

  Widget _buildStep1Photos(SalesJob job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'INSTALL COMPLETION PHOTOS'),
        const SizedBox(height: 6),
        Text(
          'Capture one photo per channel. These get attached to the '
          'install record and stay with the dealer.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        if (job.channelRuns.isEmpty)
          Text(
            'No channels on this job',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          )
        else
          for (int i = 0; i < job.channelRuns.length; i++) ...[
            _PhotoCaptureRow(
              run: job.channelRuns[i],
              photoUrl: _photoByChannel[job.channelRuns[i].id],
              isUploading:
                  _uploadingChannels.contains(job.channelRuns[i].id),
              onTap: () => _capturePhotoForChannel(job.channelRuns[i]),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Step 2: material check-in ─────────────────────────────────────────

  Widget _buildStep2Materials(SalesJob job) {
    final items = _materialItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'MATERIAL CHECK-IN'),
        const SizedBox(height: 6),
        Text(
          'Enter actual unused quantities. Used = estimate − returned.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),

        if (items.isEmpty)
          Text(
            job.estimateBreakdown == null
                ? 'No estimate breakdown on this job'
                : 'No physical materials on the estimate',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          )
        else
          for (final item in items) ...[
            _MaterialCheckInRow(
              item: item,
              controller: _returnedCtrlFor(item),
            ),
            const SizedBox(height: 10),
          ],

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: NexGenPalette.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: NexGenPalette.amber,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'These quantities are recorded on the job for the audit '
                  'trail. Inventory reconciliation against dealer stock '
                  'happens in a follow-up — nothing is debited or credited '
                  'right now.',
                  style: TextStyle(
                    color: NexGenPalette.amber.withValues(alpha: 0.9),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Step 3: customer account ──────────────────────────────────────────

  Widget _buildStep3Account(SalesJob job) {
    final accountCreated =
        _createdUserUid != null && _createdUserUid!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'CUSTOMER ACCOUNT'),
        const SizedBox(height: 6),
        Text(
          'Review the customer info, correct anything wrong, then send '
          'the account setup email.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _wrapField(
                controller: _firstNameCtrl,
                label: 'First name',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _wrapField(
                controller: _lastNameCtrl,
                label: 'Last name',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _wrapField(
          controller: _emailCtrl,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 12),
        _wrapField(
          controller: _phoneCtrl,
          label: 'Phone',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 20),

        if (accountCreated)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NexGenPalette.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: NexGenPalette.green.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: NexGenPalette.green,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Account created. Setup email sent to '
                    '${_emailCtrl.text.trim()}.',
                    style: TextStyle(
                      color: NexGenPalette.green.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCreatingAccount ? null : _createCustomerAccount,
              icon: _isCreatingAccount
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.email_outlined, color: Colors.black),
              label: const Text(
                'Send Account Setup Email',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.green,
                disabledBackgroundColor:
                    NexGenPalette.green.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        if (accountCreated) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _launchLuminaSetup,
              icon: Icon(
                Icons.rocket_launch_outlined,
                color: NexGenPalette.cyan,
              ),
              label: Text(
                'Launch Lumina Setup for Customer',
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Step 4: close job ─────────────────────────────────────────────────

  Widget _buildStep4Close(SalesJob job) {
    final photoCount = _photoByChannel.length;
    final returnedCount = job.actualMaterialUsage?.entries
            .where((e) => e.returnedQty > 0)
            .length ??
        0;
    final accountCreated =
        _createdUserUid != null && _createdUserUid!.isNotEmpty;
    final installComplete = job.status == SalesJobStatus.installComplete ||
        job.status == SalesJobStatus.completePaid;
    final paid = job.status == SalesJobStatus.completePaid ||
        job.finalPaymentCollected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'CLOSE JOB'),
        const SizedBox(height: 6),
        Text(
          paid
              ? 'This job is complete and paid in full.'
              : (installComplete
                  ? 'Install marked complete. Collect the final payment to '
                      'archive the job.'
                  : 'Confirm everything looks right, then mark the install '
                      'complete to archive the job.'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),

        _checkRow(
          icon: Icons.photo_library_outlined,
          label: 'Install photos',
          value: '$photoCount of ${job.channelRuns.length} captured',
          done: photoCount == job.channelRuns.length &&
              job.channelRuns.isNotEmpty,
        ),
        _checkRow(
          icon: Icons.inventory_2_outlined,
          label: 'Materials returned',
          value: '$returnedCount line${returnedCount == 1 ? '' : 's'}',
          done: job.actualMaterialUsage != null,
        ),
        _checkRow(
          icon: Icons.person_outline,
          label: 'Customer account',
          value: accountCreated ? 'Created' : 'Not created',
          done: accountCreated,
          warnIfNotDone: true,
        ),
        const SizedBox(height: 16),

        // Final payment gate (Part 10). Renders only after install is
        // marked complete. Shows the remaining balance, a reminder
        // dispatch button, and a "Mark Final Payment Collected" CTA.
        // Once payment is recorded the job moves to the completePaid
        // terminal state and pops back to the queue.
        if (installComplete && !paid) _FinalPaymentSection(
          job: job,
          isBusy: _isCompleting,
          onMarkPaymentCollected: _markFinalPayment,
          onSendReminder: _sendPaymentReminder,
        ),
        if (paid) const _PaidConfirmationCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _checkRow({
    required IconData icon,
    required String label,
    required String value,
    required bool done,
    bool warnIfNotDone = false,
  }) {
    final accent = done
        ? NexGenPalette.green
        : (warnIfNotDone ? NexGenPalette.amber : NexGenPalette.textMedium);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: accent,
            size: 18,
          ),
        ],
      ),
    );
  }

  // ── Bottom bar with Back / Continue or Complete ───────────────────────

  Widget _bottomBar(SalesJob job) {
    final isLastStep = _step == _WrapUpStep.close;
    final canAdvance = _canAdvance();
    // Complete-Job button is locked once install is complete (or paid)
    // — interaction post-completion happens through the in-content
    // final payment section.
    final alreadyComplete =
        job.status == SalesJobStatus.installComplete ||
            job.status == SalesJobStatus.completePaid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        children: [
          if (_step != _WrapUpStep.photos)
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: _isCompleting ? null : _back,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: NexGenPalette.line,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Back',
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
              ),
            ),
          if (_step != _WrapUpStep.photos) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: isLastStep
                  ? (alreadyComplete || _isCompleting ? null : _completeJob)
                  : (canAdvance ? _advance : null),
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
                      isLastStep
                          ? (alreadyComplete
                              ? 'Already complete'
                              : 'Complete Job →')
                          : (canAdvance
                              ? 'Continue →'
                              : _step == _WrapUpStep.photos
                                  ? 'Capture all photos to continue'
                                  : 'Continue →'),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tiny helpers ──────────────────────────────────────────────────────

  Widget _wrapField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: NexGenPalette.textMedium),
        filled: true,
        fillColor: NexGenPalette.gunmetal90,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NexGenPalette.green),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header (private — green accent for the wrap-up flow)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: NexGenPalette.green,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 photo capture row
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoCaptureRow extends StatelessWidget {
  final ChannelRun run;
  final String? photoUrl;
  final bool isUploading;
  final VoidCallback onTap;

  const _PhotoCaptureRow({
    required this.run,
    required this.photoUrl,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPhoto
              ? NexGenPalette.green.withValues(alpha: 0.4)
              : NexGenPalette.line,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Thumbnail / placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: hasPhoto
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: NexGenPalette.matteBlack,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white24,
                        ),
                      ),
                    )
                  : Container(
                      color: NexGenPalette.matteBlack,
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Channel info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Channel ${run.channelNumber}'
                  '${run.label.isNotEmpty ? ' — ${run.label}' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhoto
                      ? 'Photo captured'
                      : 'Tap to capture completion photo',
                  style: TextStyle(
                    color: hasPhoto
                        ? NexGenPalette.green
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action button
          isUploading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NexGenPalette.green,
                  ),
                )
              : IconButton(
                  icon: Icon(
                    hasPhoto ? Icons.refresh : Icons.add_a_photo_outlined,
                    color: NexGenPalette.green,
                  ),
                  onPressed: onTap,
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 material check-in row
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialCheckInRow extends StatelessWidget {
  final EstimateLineItem item;
  final TextEditingController controller;

  const _MaterialCheckInRow({
    required this.item,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Used: ${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)} ${item.unit}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.end,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Returning',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 12,
                    ),
                    suffixText: item.unit,
                    suffixStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: NexGenPalette.matteBlack,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: NexGenPalette.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: NexGenPalette.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: NexGenPalette.green),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Final payment gate widgets (Part 10)
// ─────────────────────────────────────────────────────────────────────────────

/// Renders the post-install payment-pending UI: remaining balance,
/// "Send Payment Reminder" button, and "Mark Final Payment Collected"
/// CTA. Shown inside _buildStep4Close after the install is marked
/// complete and before the final payment is recorded.
class _FinalPaymentSection extends StatelessWidget {
  const _FinalPaymentSection({
    required this.job,
    required this.isBusy,
    required this.onMarkPaymentCollected,
    required this.onSendReminder,
  });

  final SalesJob job;
  final bool isBusy;
  final VoidCallback onMarkPaymentCollected;
  final VoidCallback onSendReminder;

  @override
  Widget build(BuildContext context) {
    final remaining = job.totalPriceUsd - (job.depositAmount ?? 0);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.green.withValues(alpha: 0.08),
        border: Border.all(color: NexGenPalette.green.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration_outlined,
                  color: NexGenPalette.green, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Installation Complete!',
                style: TextStyle(
                  color: NexGenPalette.green,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Notify the customer that their final balance is due.',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '\$${remaining.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            'Remaining balance',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onSendReminder,
              icon: const Icon(Icons.notifications_outlined, size: 16),
              label: const Text('Send Payment Reminder to Customer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.cyan,
                side: BorderSide(
                    color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isBusy ? null : onMarkPaymentCollected,
              icon: const Icon(Icons.check_circle, size: 16),
              label: isBusy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('Mark Final Payment Collected'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only "complete + paid" celebration card. Replaces the payment
/// section once the dealer marks final payment collected; gives the
/// install team visual confirmation before the screen pops.
class _PaidConfirmationCard extends StatelessWidget {
  const _PaidConfirmationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.green.withValues(alpha: 0.12),
        border: Border.all(color: NexGenPalette.green),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              color: NexGenPalette.green, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Job complete and paid in full.',
              style: TextStyle(
                color: NexGenPalette.green,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
