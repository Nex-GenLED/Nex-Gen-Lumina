import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/installer/staff_auth_telemetry.dart';
import 'package:nexgen_command/models/dealer_code.dart';
import 'package:nexgen_command/features/installer/installer_draft_service.dart';
import 'package:nexgen_command/features/installer/screens/customer_info_screen.dart';
import 'package:nexgen_command/features/installer/screens/controller_setup_screen.dart';
import 'package:nexgen_command/features/installer/screens/connection_method_screen.dart';
import 'package:nexgen_command/features/installer/screens/hardware_config_step.dart';
import 'package:nexgen_command/features/installer/screens/map_roofline_step.dart';
import 'package:nexgen_command/features/installer/screens/zone_configuration_screen.dart';
import 'package:nexgen_command/features/installer/screens/commercial_brand_setup_step.dart';
import 'package:nexgen_command/features/installer/handoff_screen.dart';
import 'package:nexgen_command/features/commercial/brand/brand_design_generator.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/referrals/services/referral_pipeline_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/team_registration_service.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/models/installation_model.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Linear forward routing for the installer wizard. Single source of
/// truth for "what comes next" — `_buildStepContent` wires every onNext
/// closure through this so a step insertion or rename touches one place.
/// The terminal step (handoff) is its own successor; the wizard does not
/// auto-advance off of it.
@visibleForTesting
InstallerWizardStep nextWizardStep(InstallerWizardStep step) {
  switch (step) {
    case InstallerWizardStep.customerInfo:
      return InstallerWizardStep.controllerSetup;
    case InstallerWizardStep.controllerSetup:
      return InstallerWizardStep.connectionMethod;
    case InstallerWizardStep.connectionMethod:
      return InstallerWizardStep.zoneConfiguration;
    case InstallerWizardStep.zoneConfiguration:
      return InstallerWizardStep.hardwareConfig;
    case InstallerWizardStep.hardwareConfig:
      return InstallerWizardStep.mapRoofline;
    case InstallerWizardStep.mapRoofline:
      return InstallerWizardStep.brandSetup;
    case InstallerWizardStep.brandSetup:
      return InstallerWizardStep.handoff;
    case InstallerWizardStep.handoff:
      return InstallerWizardStep.handoff;
  }
}

/// Linear backward routing for the installer wizard. Mirrors
/// [nextWizardStep]; customerInfo is its own predecessor (the back button
/// at the very first step is suppressed at the call site).
@visibleForTesting
InstallerWizardStep prevWizardStep(InstallerWizardStep step) {
  switch (step) {
    case InstallerWizardStep.customerInfo:
      return InstallerWizardStep.customerInfo;
    case InstallerWizardStep.controllerSetup:
      return InstallerWizardStep.customerInfo;
    case InstallerWizardStep.connectionMethod:
      return InstallerWizardStep.controllerSetup;
    case InstallerWizardStep.zoneConfiguration:
      return InstallerWizardStep.connectionMethod;
    case InstallerWizardStep.hardwareConfig:
      return InstallerWizardStep.zoneConfiguration;
    case InstallerWizardStep.mapRoofline:
      return InstallerWizardStep.hardwareConfig;
    case InstallerWizardStep.brandSetup:
      return InstallerWizardStep.mapRoofline;
    case InstallerWizardStep.handoff:
      return InstallerWizardStep.brandSetup;
  }
}

/// True when [dealerCode] is the reserved fleet-shared master code that master
/// installer/admin PINs mint ([DealerCode.masterReserved], '55').
///
/// A real customer install must never be attributed to it: every customer
/// stamped '55' shares one dealer scope, so any master-PIN holder in the fleet
/// could read them all (the /users read rule scopes on dealer_code). Master
/// PINs are for support access, not installs — the wizard refuses this code up
/// front so the install stops before any Firebase work, not at step 8 after the
/// customer, controllers, and docs have all been written.
bool installUsesReservedDealerCode(String dealerCode) =>
    dealerCode == DealerCode.masterReserved;

/// What to do when [_WledInstallerSetupWizardState._completeSetup] throws.
enum InstallErrorOutcome {
  /// Pre-commit failure — the customer is not provisioned. Report failure.
  reportFailure,

  /// Post-commit — the customer's account and core docs already committed, so
  /// they can sign in. The throw is post-provisioning bookkeeping (analytics
  /// counter, referral status); complete the install and show the handoff
  /// screen with a warning rather than claiming the whole install failed.
  completeWithWarning,
}

/// Classify a mid-setup exception by whether the install had already committed.
///
/// The commit point is the customer's user-doc write: once it lands, the
/// controllers are migrated and the /installations doc exists, so the customer
/// can sign in and control their lights. A blanket "Setup failed" past that
/// point is a lie that also hides the handoff-credentials screen — the exact
/// D3-HOTFIX regression at :1191 (an admin/owner-scoped /installers counter
/// read denied to a non-admin installer session).
InstallErrorOutcome classifyInstallError({required bool installCommitted}) =>
    installCommitted
        ? InstallErrorOutcome.completeWithWarning
        : InstallErrorOutcome.reportFailure;

/// Safety margin on the ONE-HOUR custom-token TTL.
///
/// A token minted at T is useless at T+60m. We treat anything older than
/// T+50m as already dead so the re-mint happens BEFORE the exchange fails,
/// rather than paying a guaranteed-losing round trip first. Ten minutes
/// comfortably covers a slow driveway LTE handshake.
const Duration kStaffTokenSafetyMargin = Duration(minutes: 50);

/// Whether the cached staff custom token must be re-minted before use.
///
/// Custom tokens (staffAuth.ts:558) are valid for ONE HOUR from mint. The
/// wizard caches one at PIN entry and re-exchanges it after customer-account
/// creation; a long install — a pixel-walk on a large roofline, the app
/// backgrounded, the phone asleep — routinely outlives it. This is the whole
/// reason the anonymous fallback existed.
///
/// Pure + injectable clock so the expiry logic is testable without waiting an
/// hour or touching Firebase.
@visibleForTesting
bool staffTokenNeedsRefresh({
  required DateTime authenticatedAt,
  required DateTime now,
  Duration safetyMargin = kStaffTokenSafetyMargin,
}) =>
    !now.isBefore(authenticatedAt.add(safetyMargin));

/// Outcome of [migrateInstallerControllersToCustomer].
///
/// A *failure* is not represented here — it throws. This distinguishes the
/// several legitimate "nothing moved" cases from a real migration, so the
/// caller can log precisely and a retry can tell "already done" from "never
/// had any".
@visibleForTesting
class ControllerMigrationResult {
  const ControllerMigrationResult({
    this.controllers = 0,
    this.pixelMapDocs = 0,
    this.skipReason,
  });

  /// Controller documents moved to the customer.
  final int controllers;

  /// pixelMap channel documents carried along with them.
  final int pixelMapDocs;

  /// Non-null when nothing was moved, and why: `no-source-uid`, `same-uid`,
  /// `source-empty` (includes "a prior attempt already succeeded"), `no-match`.
  final String? skipReason;

  bool get movedAnything => controllers > 0;

  @override
  String toString() => skipReason != null
      ? 'ControllerMigrationResult(skipped: $skipReason)'
      : 'ControllerMigrationResult($controllers controller(s), '
          '$pixelMapDocs pixelMap doc(s))';
}

/// Copies controller documents added during the installer wizard from the
/// installer/staff UID to the customer UID, then deletes the originals — with
/// **each controller's `pixelMap/*` subcollection carried along** (Design
/// Studio Slice 2: a wizard-captured roofline map MUST arrive under the
/// customer uid; the parent controller doc copy does NOT carry subcollections).
/// One batch for atomicity.
///
/// Only controllers whose ids are in [controllerIds] migrate; empty →
/// ALL (legacy safety fallback). No-op when [fromUid] is null/empty or equals
/// [toUid].
///
/// **THROWS on failure (P0-6, 2026-07-31).** This used to catch everything and
/// return normally "so handoff still completes" — which meant a denied or
/// dropped migration was reported to the installer as a successful install
/// while the customer had no controllers at all. That swallow is what would
/// have made the P0-5 rules denial invisible. The caller is now responsible for
/// surfacing it; see `_migrateControllersWithRetry`.
///
/// SAFE TO RETRY. `WriteBatch.commit()` is atomic, so a failed commit applies
/// none of its writes — the source documents are still intact and the
/// destination has nothing half-written. A retry simply re-reads and re-commits.
/// A retry after a commit that actually landed (client saw a timeout, server
/// applied it) finds the source already drained and returns
/// [ControllerMigrationResult.skipReason] `'source-empty'` rather than failing.
///
/// Extracted as a top-level function (injectable [firestore]) so the migration
/// — the slice's integrity guarantee — is unit-testable against a fake.
@visibleForTesting
Future<ControllerMigrationResult> migrateInstallerControllersToCustomer({
  required FirebaseFirestore firestore,
  required String? fromUid,
  required String toUid,
  required Set<String> controllerIds,
}) async {
  if (fromUid == null || fromUid.isEmpty) {
    debugPrint('Installer: skipping controller migration — no source UID');
    return const ControllerMigrationResult(skipReason: 'no-source-uid');
  }
  if (fromUid == toUid) {
    debugPrint('Installer: skipping controller migration — same UID');
    return const ControllerMigrationResult(skipReason: 'same-uid');
  }
  {
    final sourceCol =
        firestore.collection('users').doc(fromUid).collection('controllers');
    final destCol =
        firestore.collection('users').doc(toUid).collection('controllers');

    final snapshot = await sourceCol.get();
    if (snapshot.docs.isEmpty) {
      // Also the "retry after a commit that actually landed" case — the source
      // was drained by the successful commit the client never saw acknowledged.
      debugPrint('Installer: no controllers to migrate from $fromUid');
      return const ControllerMigrationResult(skipReason: 'source-empty');
    }

    // Only migrate controllers from this installation session, so an admin's
    // pre-existing controllers aren't moved to the customer.
    final docsToMigrate = controllerIds.isEmpty
        ? snapshot.docs
        : snapshot.docs.where((d) => controllerIds.contains(d.id)).toList();

    if (docsToMigrate.isEmpty) {
      debugPrint('Installer: no matching controllers to migrate '
          '(${snapshot.docs.length} total, ${controllerIds.length} selected)');
      return const ControllerMigrationResult(skipReason: 'no-match');
    }

    // Read each controller's pixelMap subcollection BEFORE the batch (reads
    // can't live inside a WriteBatch).
    final pixelMapByController = <String, QuerySnapshot<Map<String, dynamic>>>{};
    for (final doc in docsToMigrate) {
      pixelMapByController[doc.id] =
          await sourceCol.doc(doc.id).collection('pixelMap').get();
    }

    final batch = firestore.batch();
    int pixelMapDocs = 0;
    for (final doc in docsToMigrate) {
      batch.set(destCol.doc(doc.id), doc.data());
      batch.delete(sourceCol.doc(doc.id));

      final pm = pixelMapByController[doc.id];
      if (pm != null) {
        for (final ch in pm.docs) {
          batch.set(
            destCol.doc(doc.id).collection('pixelMap').doc(ch.id),
            ch.data(),
          );
          batch.delete(
            sourceCol.doc(doc.id).collection('pixelMap').doc(ch.id),
          );
          pixelMapDocs++;
        }
      }
    }
    // P0-6: no try/catch. A commit failure propagates to the caller, which is
    // the only place that can tell the installer and offer a retry.
    await batch.commit();
    debugPrint('Installer: migrated ${docsToMigrate.length} controller(s) '
        '($pixelMapDocs pixelMap doc(s)) from $fromUid to $toUid');
    return ControllerMigrationResult(
      controllers: docsToMigrate.length,
      pixelMapDocs: pixelMapDocs,
    );
  }
}

/// Main wizard shell for installer setup flow
class InstallerSetupWizard extends ConsumerStatefulWidget {
  const InstallerSetupWizard({super.key});

  @override
  ConsumerState<InstallerSetupWizard> createState() => _InstallerSetupWizardState();
}

class _InstallerSetupWizardState extends ConsumerState<InstallerSetupWizard> {
  bool _hasCheckedDraft = false;
  Timer? _countdownTimer;
  int _warningSecondsRemaining = 300; // 5 minutes

  @override
  void initState() {
    super.initState();
    // Record activity on wizard entry
    ref.read(installerModeActiveProvider.notifier).recordActivity();

    // Set up session warning callback
    ref.read(installerModeActiveProvider.notifier).onSessionWarning = _showTimeoutWarning;

    // Check for existing draft
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForDraft();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    // Clear the warning callback
    ref.read(installerModeActiveProvider.notifier).onSessionWarning = null;
    super.dispose();
  }

  Future<void> _checkForDraft() async {
    if (_hasCheckedDraft) return;
    _hasCheckedDraft = true;

    final metadata = await InstallerDraftService.getDraftMetadata();
    if (metadata != null && mounted) {
      _showResumeDraftDialog(metadata);
    }
  }

  void _showResumeDraftDialog(DraftMetadata metadata) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Resume Previous Setup?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have an incomplete installation:',
              style: const TextStyle(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 16),
            _buildDraftInfoRow(Icons.person_outline, 'Customer', metadata.customerName),
            const SizedBox(height: 8),
            _buildDraftInfoRow(Icons.timeline, 'Step', metadata.stepName),
            const SizedBox(height: 8),
            _buildDraftInfoRow(Icons.access_time, 'Saved', metadata.formattedDate),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await InstallerDraftService.clearDraft();
              resetInstallerWizardState(ref);
            },
            child: const Text('Start Fresh', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _loadDraft();
            },
            style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
            child: const Text('Resume Setup', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Future<void> _loadDraft() async {
    final draft = await InstallerDraftService.loadDraft();
    if (draft == null) return;

    // Restore state from draft
    ref.read(installerCustomerInfoProvider.notifier).state = draft.customerInfo;
    ref.read(installerSiteModeProvider.notifier).state = draft.siteMode;
    ref.read(installerSelectedControllersProvider.notifier).state = draft.selectedControllerIds;
    ref.read(installerLinkedControllersProvider.notifier).state = draft.linkedControllerIds;
    ref.read(installerZonesProvider.notifier).setAll(draft.zones);
    ref.read(installerPhotoUrlProvider.notifier).state = draft.photoUrl;

    // Go to the saved step
    final step = InstallerWizardStep.values[draft.currentStepIndex.clamp(0, InstallerWizardStep.values.length - 1)];
    ref.read(installerWizardStepProvider.notifier).state = step;
  }

  Future<void> _saveDraft() async {
    final currentStep = ref.read(installerWizardStepProvider);
    final session = ref.read(installerSessionProvider);

    final draft = InstallerDraft(
      sessionPin: session?.pin,
      currentStepIndex: InstallerWizardStep.values.indexOf(currentStep),
      customerInfo: ref.read(installerCustomerInfoProvider),
      selectedControllerIds: ref.read(installerSelectedControllersProvider),
      linkedControllerIds: ref.read(installerLinkedControllersProvider),
      zones: ref.read(installerZonesProvider),
      siteMode: ref.read(installerSiteModeProvider),
      photoUrl: ref.read(installerPhotoUrlProvider),
      savedAt: DateTime.now(),
    );

    await InstallerDraftService.saveDraft(draft);
  }

  void _showTimeoutWarning() {
    if (!mounted) return;

    _warningSecondsRemaining = 300; // 5 minutes
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_warningSecondsRemaining > 0) {
        setState(() => _warningSecondsRemaining--);
      } else {
        timer.cancel();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Update the dialog state when countdown changes
          Future.delayed(const Duration(seconds: 1), () {
            if (context.mounted) setDialogState(() {});
          });

          final minutes = _warningSecondsRemaining ~/ 60;
          final seconds = _warningSecondsRemaining % 60;

          return AlertDialog(
            backgroundColor: NexGenPalette.gunmetal90,
            title: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                const Text('Session Expiring', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your installer session will expire soon due to inactivity.',
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time, color: Colors.orange, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        '$minutes:${seconds.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  _countdownTimer?.cancel();
                  Navigator.pop(context);
                  await _saveDraft();
                  ref.read(installerModeActiveProvider.notifier).exitInstallerMode();
                  if (mounted) this.context.go('/');
                },
                child: const Text('Save & Exit', style: TextStyle(color: NexGenPalette.textMedium)),
              ),
              ElevatedButton(
                onPressed: () {
                  _countdownTimer?.cancel();
                  Navigator.pop(context);
                  ref.read(installerModeActiveProvider.notifier).extendSession();
                },
                style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
                child: const Text('Extend Session', style: TextStyle(color: Colors.black)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInstallerMode = ref.watch(installerModeActiveProvider);
    final currentStep = ref.watch(installerWizardStepProvider);

    // If not in installer mode, redirect back
    if (!isInstallerMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    // Get current session info
    final session = ref.watch(installerSessionProvider);
    final installerName = session?.installer.name ?? 'Unknown';
    final dealerName = session?.dealer.companyName ?? 'Unknown Dealer';

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => _showExitConfirmation(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Installer Setup', style: TextStyle(color: Colors.white, fontSize: 18)),
            Text(
              '$installerName • $dealerName',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Media Dashboard button for viewing customer systems
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: NexGenPalette.cyan),
            tooltip: 'Media Dashboard',
            onPressed: () => context.push(AppRoutes.mediaDashboard),
          ),
          // Installer mode indicator with PIN display
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.engineering, color: NexGenPalette.cyan, size: 16),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('INSTALLER', style: TextStyle(color: NexGenPalette.cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                    Text(
                      session?.pin ?? '----',
                      style: TextStyle(color: NexGenPalette.cyan.withValues(alpha: 0.7), fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressIndicator(currentStep),
          // Current step content
          Expanded(child: _buildStepContent(currentStep)),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(InstallerWizardStep currentStep) {
    final steps = InstallerWizardStep.values;
    final currentIndex = steps.indexOf(currentStep);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isCompleted = index < currentIndex;
          final isCurrent = index == currentIndex;
          final stepInfo = _getStepInfo(steps[index]);

          return Expanded(
            child: Row(
              children: [
                // Step circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? NexGenPalette.cyan
                        : isCurrent
                            ? NexGenPalette.cyan.withValues(alpha: 0.3)
                            : NexGenPalette.matteBlack,
                    border: Border.all(
                      color: isCompleted || isCurrent ? NexGenPalette.cyan : NexGenPalette.line,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isCurrent ? NexGenPalette.cyan : NexGenPalette.textMedium,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Step label (only show for current and adjacent steps on small screens)
                Expanded(
                  child: Text(
                    stepInfo.shortLabel,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : NexGenPalette.textMedium,
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Connector line
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isCompleted ? NexGenPalette.cyan : NexGenPalette.line,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(InstallerWizardStep step) {
    // Record activity when navigating between steps
    ref.read(installerModeActiveProvider.notifier).recordActivity();

    // onNext / onBack targets come from nextWizardStep / prevWizardStep
    // (top of file) — one source of truth for the linear progression.
    switch (step) {
      case InstallerWizardStep.customerInfo:
        return CustomerInfoScreen(
          onNext: () => _goToStep(nextWizardStep(step)),
        );
      case InstallerWizardStep.controllerSetup:
        return ControllerSetupScreen(
          onBack: () => _goToStep(prevWizardStep(step)),
          onNext: () => _goToStep(nextWizardStep(step)),
        );
      case InstallerWizardStep.connectionMethod:
        return ConnectionMethodScreen(
          onBack: () => _goToStep(prevWizardStep(step)),
          onNext: () => _goToStep(nextWizardStep(step)),
        );
      case InstallerWizardStep.zoneConfiguration:
        return ZoneConfigurationScreen(
          onBack: () => _goToStep(prevWizardStep(step)),
          onNext: () => _goToStep(nextWizardStep(step)),
        );
      case InstallerWizardStep.hardwareConfig:
        return HardwareConfigStep(
          onBack: () => _goToStep(prevWizardStep(step)),
          onNext: () => _goToStep(nextWizardStep(step)),
        );
      case InstallerWizardStep.mapRoofline:
        return MapRooflineStep(
          onBack: () => _goToStep(prevWizardStep(step)),
          onNext: () => _goToStep(nextWizardStep(step)),
        );
      case InstallerWizardStep.brandSetup:
        // Auto-advance for residential — the brand-setup step is a
        // commercial-only insertion that must be transparent for the
        // residential install path. Reads the site mode synchronously
        // and either renders the commercial pre-seed UI or advances
        // post-frame to handoff.
        final isCommercial =
            ref.read(installerSiteModeProvider) == SiteMode.commercial;
        if (!isCommercial) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                ref.read(installerWizardStepProvider) ==
                    InstallerWizardStep.brandSetup) {
              _goToStep(InstallerWizardStep.handoff);
            }
          });
          return const SizedBox.shrink();
        }
        return CommercialBrandSetupStep(
          onComplete: () => _goToStep(InstallerWizardStep.handoff),
          onSkip: () => _goToStep(InstallerWizardStep.handoff),
        );
      case InstallerWizardStep.handoff:
        return HandoffScreen(
          onBack: () => _goToStep(prevWizardStep(step)),
          onNext: (draft) {
            ref.read(installerPreferenceDraftProvider.notifier).state = draft;
            _completeSetup();
          },
        );
    }
  }

  void _goToStep(InstallerWizardStep step) {
    ref.read(installerWizardStepProvider.notifier).state = step;
    // Auto-save draft after each step transition
    _saveDraft();
  }

  bool _isProcessing = false;

  /// Generate a secure temporary password for the customer
  String _generateTempPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Thin instance wrapper around [migrateInstallerControllersToCustomer] using
  /// the live Firestore instance. Propagates failures — see
  /// [_migrateControllersWithRetry].
  Future<ControllerMigrationResult> _migrateControllersToCustomer(
    String? fromUid,
    String toUid,
    Set<String> controllerIds,
  ) {
    return migrateInstallerControllersToCustomer(
      firestore: FirebaseFirestore.instance,
      fromUid: fromUid,
      toUid: toUid,
      controllerIds: controllerIds,
    );
  }

  /// The controller migration, plus an installer-visible retry (P0-6).
  ///
  /// This runs AFTER `createUserWithEmailAndPassword`, so a failure here leaves
  /// a real customer account with no lights attached to it. It used to be
  /// swallowed entirely: the wizard showed the handoff screen and the installer
  /// drove away from a customer whose app would be empty on first login.
  ///
  /// Deliberately the SAME shape as [_restoreInstallerAuthWithRetry] — same
  /// position in the flow, same Retry/Stop dialog, same "Stop rethrows into the
  /// outer catch" contract. Two different failure UXs in one wizard would be its
  /// own defect.
  ///
  /// WHY RETRY-IN-PLACE rather than flagging the account or rolling back:
  ///   • The realistic cause is a driveway with no signal, which Retry fixes on
  ///     the spot — the installer is still standing there with the hardware.
  ///   • "Complete but flag for later migration" would need to WRITE that flag
  ///     through the same Firestore that just failed, and there is no repair job
  ///     to consume it. That is the defect again with extra steps.
  ///   • Rolling back the customer account means deleting a just-created auth
  ///     user (and the password-reset email has already gone out) from the
  ///     client, in several non-atomic steps that can themselves half-fail.
  ///
  /// On Stop this RETHROWS. `installCommitted` is still false at this point, so
  /// `classifyInstallError` returns `reportFailure` and the wizard reports the
  /// install as failed — which is the truth.
  Future<void> _migrateControllersWithRetry(
    String? fromUid,
    String toUid,
    Set<String> controllerIds,
  ) async {
    while (true) {
      try {
        final result =
            await _migrateControllersToCustomer(fromUid, toUid, controllerIds);
        debugPrint('Installer: controller migration OK — $result');
        return;
      } catch (e, st) {
        // P0-6: the cause used to be discarded here.
        debugPrint('Installer: controller migration FAILED '
            '(from=$fromUid to=$toUid, ${controllerIds.length} selected): '
            '$e\n$st');

        // Durable, queryable record so "the customer left without controllers"
        // is observable by the business, not only by whoever was standing in
        // the driveway. Cannot throw and cannot block — see the telemetry lib.
        await recordCommissioningFailure(
          stage: 'controller_migration',
          reason: '$e',
          customerUid: toUid,
          sourceUid: fromUid,
        );

        if (!mounted) rethrow;

        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Controllers didn't transfer"),
            content: Text(
              "The customer's account was created, but their controllers could "
              'not be moved onto it ($e).\n\n'
              'If you stop now they will sign in to an app with no lights. '
              'Nothing has been lost — the controllers are still on this device '
              "under your installer login — so check your connection and tap "
              'Retry.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stop'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
        // Stop must NOT fall through into the rest of the install — that would
        // be the seventh silent success. Rethrow so the wizard reports failure.
        if (retry != true) rethrow;
      }
    }
  }

  /// True once [_restoreInstallerAuth] has put the installer's STAFF CLAIMS
  /// back on the Firebase Auth session. False means we fell back to an
  /// anonymous session and hold no `role`/`dealerCode` claim.
  bool _installerClaimsRestored = false;

  /// Restore the installer's claim-bearing session after
  /// `createUserWithEmailAndPassword` signed us in as the customer.
  ///
  /// Re-signs with the custom token cached at PIN entry
  /// (InstallerSession.staffToken), which carries `role: 'installer'` +
  /// `dealerCode`. Those claims are what firestore.rules hasStaffClaim() and
  /// the setAccountProfile callable check.
  ///
  /// Custom tokens live ONE HOUR, and a long install routinely outlives that.
  /// Rather than dropping to an anonymous, claim-less session, this now
  /// RE-MINTS a fresh token from the cached PIN (see [_refreshStaffToken]) and
  /// exchanges that. The re-minted uid is identical — staffAuth.ts derives it
  /// as `staff_<mode>_<pin>` — so refreshing cannot orphan the controller
  /// migration's source path.
  ///
  /// The anonymous fallback is retained but should now be UNREACHABLE on the
  /// happy path; reaching it emits a telemetry record (staff_auth_telemetry.dart)
  /// whose fleet-wide count gates the D4 rules narrowing. Callers must treat a
  /// false return as a HARD failure — see [_restoreInstallerAuthWithRetry].
  ///
  /// Returns true when the claims were restored.
  Future<bool> _restoreInstallerAuth(InstallerSession? session) async {
    if (session == null) {
      await _fallBackToAnonymous(
        session: null,
        stage: AnonFallbackStage.restoreAfterAccountCreation,
        reason: 'no_session',
      );
      return false;
    }

    // 1. Fast path — exchange the cached token when it is still young enough
    //    to be worth trying. Avoids a callable round trip on a normal install.
    final cached = session.staffToken;
    final stale = staffTokenNeedsRefresh(
      authenticatedAt: session.authenticatedAt,
      now: DateTime.now(),
    );
    if (cached != null && !stale) {
      try {
        await FirebaseAuth.instance.signInWithCustomToken(cached);
        _installerClaimsRestored = true;
        debugPrint('Installer: staff claims restored (cached token)');
        return true;
      } catch (e) {
        debugPrint('Installer: cached-token exchange failed ($e) — re-minting');
      }
    } else if (cached == null) {
      debugPrint('Installer: no cached staff token — re-minting');
    } else {
      debugPrint('Installer: cached staff token past safety margin '
          '— re-minting before exchange');
    }

    // 2. REFRESH. Mint a brand-new custom token from the cached PIN and
    //    exchange that. This is what replaces the anonymous fallback.
    final fresh = await _refreshStaffToken(session);
    if (fresh != null) {
      _installerClaimsRestored = true;
      return true;
    }

    // 3. Refresh itself failed. Record it, then fall back — the fallback is
    //    preserved but should now be UNREACHABLE on the happy path.
    await _fallBackToAnonymous(
      session: session,
      stage: AnonFallbackStage.restoreAfterAccountCreation,
      reason: _lastRefreshFailure ?? 'refresh_failed',
    );
    return false;
  }

  /// Why the most recent [_refreshStaffToken] failed, for telemetry + UI.
  String? _lastRefreshFailure;

  /// Mint a FRESH staff custom token and sign in with it.
  ///
  /// WHY RE-MINT RATHER THAN "REFRESH THE TOKEN": the credential that expires
  /// here is the CUSTOM token, not the Firebase ID token. The SDK already
  /// auto-refreshes ID tokens; it cannot refresh a custom token, because a
  /// custom token is minted server-side by `mintStaffToken` and is valid for
  /// ONE HOUR from mint. The only way to get a valid one after that hour is to
  /// ask the server for another — which we can do, because
  /// `InstallerSession.pin` still holds the PIN that authorized this session.
  ///
  /// The re-minted uid is IDENTICAL to the original: staffAuth.ts:541 derives
  /// it deterministically as `staff_<mode>_<pin>`. That matters — the controller
  /// migration's source path is that uid, so refreshing cannot orphan it.
  ///
  /// On success the session's cached token and `authenticatedAt` are replaced,
  /// so a later restore in the same install starts from a fresh clock.
  /// Returns the new token, or null on failure (cause in [_lastRefreshFailure]).
  Future<String?> _refreshStaffToken(InstallerSession session) async {
    _lastRefreshFailure = null;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('mintStaffToken');
      final result = await callable.call<Map<String, dynamic>>({
        'pin': session.pin,
        'mode': 'installer',
      });

      final token = result.data['token'] as String?;
      if (token == null || token.isEmpty) {
        _lastRefreshFailure = 'remint_returned_no_token';
        debugPrint('Installer: re-mint returned no token');
        return null;
      }

      await FirebaseAuth.instance.signInWithCustomToken(token);

      // Re-cache so a second restore in this install doesn't re-mint again.
      if (mounted) {
        ref.read(installerSessionProvider.notifier).state = InstallerSession(
          installer: session.installer,
          dealer: session.dealer,
          authenticatedAt: DateTime.now(),
          staffToken: token,
        );
      }

      debugPrint('Installer: staff token RE-MINTED and claims restored');
      return token;
    } on FirebaseFunctionsException catch (e) {
      // permission-denied here means the PIN no longer authorizes: the
      // installer was deactivated, the dealer was deactivated, or the claim
      // was revoked mid-install. resource-exhausted is the 10/60s IP limit.
      _lastRefreshFailure = 'remint_${e.code}';
      debugPrint('Installer: staff-token re-mint FAILED (${e.code}) ${e.message}');
      return null;
    } catch (e) {
      _lastRefreshFailure = 'remint_error_$e';
      debugPrint('Installer: staff-token re-mint FAILED: $e');
      return null;
    }
  }

  /// The preserved anonymous fallback — PLUS the record that proves it fired.
  ///
  /// Kept deliberately reachable-in-code but unreachable-in-practice until D4
  /// lands: the telemetry it emits is the evidence that gates the rules deploy
  /// (S-5). Delete this only once that counter has read zero across the fleet.
  Future<void> _fallBackToAnonymous({
    required InstallerSession? session,
    required AnonFallbackStage stage,
    required String reason,
  }) async {
    // Record BEFORE the sign-in: the anonymous sign-in itself can throw, and
    // that case is the most interesting one to have a record of.
    await recordAnonymousFallback(
      stage: stage,
      reason: reason,
      dealerCode: session?.dealer.dealerCode,
      installerCode: session?.installer.installerCode,
      authUid: FirebaseAuth.instance.currentUser?.uid,
    );

    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('Installer: anonymous fallback also failed: $e');
    }
    _installerClaimsRestored = false;
  }

  /// [_restoreInstallerAuth] plus an installer-visible retry.
  ///
  /// The customer's Firebase Auth account already exists by the time this runs,
  /// so silently continuing would produce a half-provisioned customer that the
  /// wizard reports as a success. Instead the installer is told what failed and
  /// given an unlimited retry — the realistic cause is a driveway with no
  /// signal, which is fixed by walking ten feet and tapping Retry.
  ///
  /// Returns false only when the installer explicitly stops.
  Future<bool> _restoreInstallerAuthWithRetry(InstallerSession session) async {
    while (true) {
      // Re-read: a prior attempt may have re-minted and re-cached the session.
      final current = ref.read(installerSessionProvider) ?? session;
      if (await _restoreInstallerAuth(current)) return true;
      if (!mounted) return false;

      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Installer session could not be renewed'),
          content: Text(
            "The customer's login was created, but this device could not renew "
            'your installer credentials (${_lastRefreshFailure ?? 'unknown'}).\n\n'
            'Their controllers have NOT been transferred yet, so setup is not '
            'finished. Move somewhere with a signal and tap Retry.\n\n'
            'If you stop now, do not start over with the same email — contact '
            'support to finish this install.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Stop'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
      if (retry != true) return false;
    }
  }

  Future<void> _completeSetup() async {
    final customerInfo = ref.read(installerCustomerInfoProvider);
    final initialSession = ref.read(installerSessionProvider);
    final draft = ref.read(installerPreferenceDraftProvider);
    _installerClaimsRestored = false;

    if (initialSession == null) {
      _showError('Installer session expired. Please re-enter your PIN.');
      return;
    }
    // Non-final: the pre-flight refresh below replaces the cached session
    // (new token + new authenticatedAt clock).
    var session = initialSession;

    // Refuse the reserved master code BEFORE any install work (not at step 8).
    // A master support PIN mints DealerCode.masterReserved ('55'); attributing
    // a customer to it collapses per-dealer scoping — see the function doc.
    if (installUsesReservedDealerCode(session.dealer.dealerCode)) {
      _showError(
        "That's a master support PIN — it can't be used to set up a customer. "
        'Re-enter your own installer PIN (your dealer code + installer code) to '
        'install this customer.',
      );
      return;
    }

    if (!customerInfo.isValid) {
      _showError('Please complete all required customer information.');
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // ── PRE-FLIGHT STAFF-TOKEN REFRESH ──────────────────────────────────────
    //
    // Runs BEFORE any Firebase work so a failure here costs nothing: no
    // customer auth account, no docs, nothing to unwind. This is the primary
    // defense against the 1-hour custom-token TTL. By re-minting here, the
    // token exchanged by _restoreInstallerAuth moments later is seconds old
    // instead of potentially over an hour old — which is what makes the
    // anonymous fallback unreachable on the happy path.
    //
    // WHY NOT A PROACTIVE TIMER: a periodic refresh is exactly what a long
    // pixel-walk defeats. Dart timers do not fire reliably with the app
    // backgrounded and the phone asleep — iOS suspends them outright — so the
    // one scenario a timer is meant to cover is the one it cannot. Evaluating
    // at the point of need has no such dependency: however long the app was
    // asleep, this line runs when the installer taps Complete.
    //
    // WHY NOT PERMISSION-DENIED-REACTIVE ONLY: today's broad
    // `|| request.auth != null` grant means the anonymous writes SUCCEED. A
    // reactive refresh would never trigger, so it could not be verified before
    // D4 — and S-5 requires the telemetry to read zero BEFORE the rules move.
    if (staffTokenNeedsRefresh(
          authenticatedAt: session.authenticatedAt,
          now: DateTime.now(),
        ) ||
        session.staffToken == null) {
      final refreshed = await _refreshStaffToken(session);
      if (refreshed == null) {
        // Do NOT proceed claim-less and do NOT report success.
        //
        // Deliberately does NOT sign in anonymously: nothing has committed, so
        // there is nothing to salvage, and the existing staff session may still
        // be usable on retry. Dropping it here would destroy a working session
        // for no gain. Recorded all the same — a device that cannot renew is
        // the adoption signal S-5 is watching for, whether or not it went
        // anonymous; `stage` distinguishes the two.
        await recordAnonymousFallback(
          stage: AnonFallbackStage.preflightRefresh,
          reason: _lastRefreshFailure ?? 'refresh_failed',
          dealerCode: session.dealer.dealerCode,
          installerCode: session.installer.installerCode,
          authUid: FirebaseAuth.instance.currentUser?.uid,
        );
        if (mounted) setState(() => _isProcessing = false);
        _showError(
          'Your installer session expired and could not be renewed '
          '(${_lastRefreshFailure ?? 'unknown'}). Nothing was created — no '
          'customer account was made. Check your connection and tap Complete '
          'Setup again, or re-enter your PIN if this keeps happening.',
        );
        return;
      }
      // Re-read: _refreshStaffToken replaced the cached session.
      session = ref.read(installerSessionProvider) ?? session;
    }

    // Commit tracking for the outer catch (see classifyInstallError): flips true
    // once the customer's user doc lands, after which a throw is post-commit
    // bookkeeping, not an install failure. The handoff vars are hoisted so the
    // catch can still show the credentials screen.
    bool installCommitted = false;
    bool isExistingAccount = false;
    String? handoffTempPassword;
    String? handoffInstallationId;

    try {
      // 1. Generate temporary password
      final tempPassword = _generateTempPassword();
      handoffTempPassword = tempPassword;

      // Capture the anonymous/installer UID BEFORE createUserWithEmailAndPassword
      // overwrites FirebaseAuth.currentUser with the new customer account.
      // This is the UID under which controllers were added during the wizard.
      final installerAnonymousUid = FirebaseAuth.instance.currentUser?.uid;

      // 2. Create Firebase Auth account for customer (or link existing account)
      //
      // IMPORTANT: createUserWithEmailAndPassword() auto-signs-in as the new
      // user, which kills the installer's session. We then restore the
      // installer's STAFF-CLAIM session (not an anonymous one) so the
      // remaining writes carry role + dealerCode — see _restoreInstallerAuth.
      String userId;
      try {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: customerInfo.email.trim().toLowerCase(),
          password: tempPassword,
        );
        userId = credential.user!.uid;
        // Send password reset email while still signed in as the customer.
        // This gives them a proper "Set your password" link instead of
        // relying on the installer reading a temp password aloud.
        try {
          await FirebaseAuth.instance.sendPasswordResetEmail(
            email: customerInfo.email.trim().toLowerCase(),
          );
          debugPrint('Installer: password reset email sent to ${customerInfo.email}');
        } catch (resetErr) {
          debugPrint('Installer: password reset email failed (non-blocking): $resetErr');
        }
        // Customer account created — restore the installer's staff claims for
        // the remaining writes.
        //
        // GATED: the controller migration below writes under the customer's
        // uid and deletes under the installer's. Running it claim-less is what
        // the broad rules grant exists to permit; once D4 narrows that grant it
        // would be DENIED — and migrateInstallerControllersToCustomer swallows
        // its own failures, so a denial would surface as a "successful" install
        // with none of the customer's controllers. Refuse to continue instead.
        if (!await _restoreInstallerAuthWithRetry(session)) {
          throw StateError(
            'staff-claim restore failed after customer account creation',
          );
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // Account already exists — look up the existing user doc to
          // recover their real uid. The /users read rule for staff
          // installer/salesperson sessions is caller-and-resource
          // scoped on dealer_code, so the query MUST filter by
          // dealer_code or Firestore denies the entire list. Uses the
          // (dealer_code, email) composite index deployed in a848f25.
          //
          // Empty results and query failures are HARD errors here —
          // the previous behavior silently fabricated a placeholder
          // uid, which orphaned the entire install (controllers,
          // /installations doc, and user merge all wrote against a
          // throwaway uid that the real customer's account never
          // referenced). Fail loud so the installer can correct the
          // input or escalate.
          try {
            final dealerCode = session.dealer.dealerCode;

            final existingQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('dealer_code', isEqualTo: dealerCode)
                .where('email', isEqualTo: customerInfo.email.trim().toLowerCase())
                .limit(1)
                .get();

            if (existingQuery.docs.isEmpty) {
              // No customer matches both email AND dealer_code in this
              // dealer's scope. Either a typo, a customer registered
              // under a different dealer, or a self-registered customer
              // with no dealer association — none of which the installer
              // can resolve in-app today.
              if (mounted) setState(() => _isProcessing = false);
              _showError(
                'No existing customer matches this email under your dealer code. '
                'Double-check the email. If they\'re a Nex-Gen customer through '
                'another dealer or self-registered without an installer, contact '
                'support to associate them with your account before continuing.',
              );
              return;
            }

            userId = existingQuery.docs.first.id;
            isExistingAccount = true;
          } catch (queryError) {
            // Query itself failed (permission denied, network, etc.).
            // Do NOT silently create a placeholder — that orphans the
            // install. Fail loud so the installer can retry or escalate.
            debugPrint('Installer: Customer lookup failed: $queryError');
            if (mounted) setState(() => _isProcessing = false);
            _showError(
              'Unable to verify customer account. Check your network '
              'connection and retry. If the issue persists, contact support.',
            );
            return;
          }
        } else {
          rethrow;
        }
      }

      // 3. Get installer-collected configuration
      final siteMode = ref.read(installerSiteModeProvider);

      // Reconcile the two residential/commercial signals at the write
      // boundary. Today the wizard exposes them through two independent
      // UIs:
      //   • zone_configuration_screen toggles installerSiteModeProvider
      //   • handoff_screen sets draft.profileType (default 'residential')
      // A May 6 audit found nothing keeps them in sync, so an installer
      // who picks Commercial on the zone-config toggle but speeds past
      // the handoff cards (or vice versa) can silently produce a broken
      // hybrid account. Until the UI is consolidated in the staged
      // Wizard UX prompt, treat siteMode as the source of truth — it is
      // the more recent decision in the wizard flow and drives the
      // installation doc's schema/limits already.
      final resolvedProfileType =
          siteMode == SiteMode.commercial ? 'commercial' : 'residential';
      if (draft != null && draft.profileType != resolvedProfileType) {
        debugPrint('Installer: wizard signal mismatch — handoff said '
            '"${draft.profileType}" but zone-config said '
            '"$resolvedProfileType". Using "$resolvedProfileType" '
            '(siteMode is the source of truth).');
      }

      final selectedControllers = ref.read(installerSelectedControllersProvider);
      final linkedControllers = ref.read(installerLinkedControllersProvider);

      // 2b. Migrate controllers from the installer's UID to the customer's
      // UID so controllersStreamProvider finds them on first login. Only move
      // the controllers that were selected for this installation — leave the
      // admin's own controllers untouched.
      // P0-6: gated. A failure here is surfaced with its cause and retried;
      // declining reports the install as FAILED rather than handing over a
      // customer account with no controllers on it.
      await _migrateControllersWithRetry(
        installerAnonymousUid,
        userId,
        selectedControllers,
      );
      final zones = ref.read(installerZonesProvider);
      final photoUrl = ref.read(installerPhotoUrlProvider);
      final maxSubUsers = siteMode == SiteMode.commercial ? 20 : 5;

      // Build system config based on site mode
      Map<String, dynamic>? systemConfig;
      if (siteMode == SiteMode.residential) {
        systemConfig = {
          'linkedControllerIds': linkedControllers.toList(),
        };
      } else {
        systemConfig = {
          'zones': zones.map((z) => {
            'name': z.name,
            'primaryIp': z.primaryIp,
            'members': z.members,
            'ddpSyncEnabled': z.ddpSyncEnabled,
            'ddpPort': z.ddpPort,
          }).toList(),
        };
      }

      // Add photo URL if captured
      if (photoUrl != null) {
        systemConfig['installationPhotoUrl'] = photoUrl;
      }

      // Add installer preference draft
      if (draft != null) {
        systemConfig['preferenceDraft'] = draft.toMap();
      }

      // 4. Create Installation document
      final installationRef = FirebaseFirestore.instance.collection('installations').doc();
      handoffInstallationId = installationRef.id;

      final installation = Installation(
        id: installationRef.id,
        primaryUserId: userId,
        dealerCode: session.dealer.dealerCode,
        installerCode: session.installer.installerCode,
        installerName: session.installer.name,
        dealerCompanyName: session.dealer.companyName,
        installedAt: DateTime.now(),
        warrantyExpires: DateTime.now().add(const Duration(days: 365 * 5)),
        controllerSerials: selectedControllers.toList(),
        address: customerInfo.address,
        city: customerInfo.city,
        state: customerInfo.state,
        zipCode: customerInfo.zipCode,
        maxSubUsers: maxSubUsers,
        siteMode: siteMode,
        isActive: true,
        systemConfig: systemConfig,
        primaryUserName: customerInfo.name,
        primaryUserEmail: customerInfo.email,
        primaryUserPhone: customerInfo.phone,
      );

      await installationRef.set(UserService.sanitizeForFirestore(installation.toJson()));

      // 5. Create UserModel with Primary role + installer preference draft
      final userModel = UserModel(
        id: userId,
        email: customerInfo.email.trim().toLowerCase(),
        displayName: customerInfo.name,
        phoneNumber: customerInfo.phone,
        address: '${customerInfo.address}\n${customerInfo.city}, ${customerInfo.state} ${customerInfo.zipCode}',
        latitude: customerInfo.latitude,
        longitude: customerInfo.longitude,
        timeZone: customerInfo.ianaTimezone,
        ownerId: userId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        installationId: installationRef.id,
        installationRole: InstallationRole.primary,
        primaryUserId: userId,
        linkedAt: DateTime.now(),
        // Per-dealer scoping for /users read rule + customer search.
        // The email-already-in-use branch above sets isExistingAccount=true
        // and reuses the existing customer's uid; the set(merge:true) at
        // the bottom of this block then merges dealer_code into the
        // existing user doc — converting self-registered customers into
        // dealer-affiliated ones on installer link.
        dealerCode: session.dealer.dealerCode,
        // Auto-Pilot preferences from installer handoff
        sportsTeams: draft?.sportsTeams ?? const [],
        sportsTeamPriority: draft?.sportsTeams ?? const [],
        favoriteHolidays: draft?.favoriteHolidays ?? const [],
        vibeLevel: draft?.vibeLevel ?? 0.5,
        changeToleranceLevel: draft?.changeToleranceLevel ?? 2,
        autonomyLevel: draft?.autonomyLevel ?? 1,
        profileType: resolvedProfileType,
        managerEmail: draft?.managerEmail,
        // Autopilot stays off by default — users opt in from the autopilot
        // screen post-install. The previous behavior auto-enabled autopilot
        // and pushed a "Daily" + days-of-week schedule the customer never
        // asked for (Bug 4c, 2026-05-07 tracker).
        welcomeCompleted: false,
      );

      final userJson = UserService.sanitizeForFirestore(userModel.toJson());
      // Force the customer to set a new password on first login. The temp
      // password was generated by the installer and read aloud / printed
      // for the customer — it must be replaced before app access.
      // Skipped when an existing account is reused (they keep their pwd).
      if (!isExistingAccount) {
        userJson['must_reset_password'] = true;
      }
      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        userJson,
        SetOptions(merge: true),
      );

      // COMMIT POINT. The customer's user doc now exists; controllers were
      // migrated (step 2b) and the /installations doc committed (step 4) before
      // this. The customer can sign in and control their lights. Everything
      // below — teams, commercial activation, brand pre-seed,
      // installation_records, referral status, the install-count bump — is
      // post-provisioning bookkeeping: a throw past here must NOT report the
      // install as failed (classifyInstallError).
      installCommitted = true;

      // Register the installer-collected Game Day teams (#63 E1, step 3).
      //
      // The customer's user-doc write above already persists the free-text
      // team names into sports_teams / sports_team_priority. This loop
      // additionally creates /users/{userId}/game_day_autopilot/{slug}
      // docs (enabled:false — adding ≠ enabling, per the E5 decision) so
      // gameDayTeamsProvider's AND-intersection between the profile
      // arrays and the subcollection actually surfaces these teams on
      // the customer's first sign-in. Without this loop the AND
      // collapses to empty and My Teams stays blank post-install (the
      // root cause E1 closes).
      //
      // Non-blocking by design: any failure here logs and is skipped so
      // a flaky Firestore call or an unrecognized team name can't abort
      // the install. Asymmetric with toggleAutopilot's create branch
      // (which propagates the same errors) — user-initiated toggles
      // surface failure; background installer commit must not block
      // customer setup.
      //
      // Unresolved free-text (no kTeamColors match) is logged and
      // skipped — the name remains in sports_teams from the user-doc
      // write above (NOT silently dropped), to be picked up by the
      // v1.0.1 Local Team Color Discovery flow.
      final installerTeams = draft?.sportsTeams ?? const <String>[];
      if (installerTeams.isNotEmpty) {
        final teamRegService = ref.read(teamRegistrationServiceProvider);
        for (final raw in installerTeams) {
          final slug =
              TeamRegistrationService.resolveFreeTextToKTeamSlug(raw);
          if (slug == null) {
            debugPrint(
                'Installer: unresolved team "$raw" (no kTeamColors match)');
            continue;
          }
          try {
            await teamRegService.addTeam(uid: userId, teamSlug: slug);
          } catch (e) {
            debugPrint('Installer: addTeam("$slug") failed (non-blocking): $e');
          }
        }
      }

      // For commercial installs: activate commercial mode via the
      // setAccountProfile callable — THE single activation path (item #32).
      // It owns the writes this batch used to do inline, plus the
      // /installations reconciliation (site_mode + max_sub_users: 20) that
      // this path could never do from the client and therefore skipped,
      // leaving commercial accounts on residential invite limits forever.
      //
      // The callable authorises on the installer's staff claim, restored by
      // _restoreInstallerAuth after customer-account creation. Without those
      // claims it will (correctly) reject us, so fail loud rather than seed a
      // half-configured commercial account.
      if (siteMode == SiteMode.commercial) {
        if (!_installerClaimsRestored) {
          debugPrint('Installer: commercial activation SKIPPED — staff claims '
              'were not restored (token missing or expired).');
          _showError(
            'Commercial setup could not be completed: your installer session '
            'expired during setup. The system is installed and the customer '
            'can sign in, but their account is still Residential. Re-enter '
            'your installer PIN and re-run setup for this customer to '
            'activate Commercial mode.',
          );
        } else {
          try {
            final callable =
                FirebaseFunctions.instanceFor(region: 'us-central1')
                    .httpsCallable('setAccountProfile');
            await callable.call<Map<String, dynamic>>({
              'uid': userId,
              'direction': 'commercial',
              'location': {
                'locationName': customerInfo.name.isNotEmpty
                    ? customerInfo.name
                    : 'Primary Location',
                'address':
                    '${customerInfo.address}, ${customerInfo.city}, ${customerInfo.state} ${customerInfo.zipCode}'
                        .trim(),
                // Real coords — the callable falls back to the user doc's own
                // lat/lng, then null. Never a fake 0.0 on the equator.
                if (customerInfo.latitude != null) 'lat': customerInfo.latitude,
                if (customerInfo.longitude != null)
                  'lng': customerInfo.longitude,
              },
            });
          } catch (e) {
            // Non-blocking, consistent with the brand pre-seed below: the
            // install itself succeeded and the customer can sign in. The
            // account stays residential and is repairable by re-running
            // setAccountProfile (it is idempotent).
            debugPrint('Installer: commercial activation failed '
                '(non-blocking): $e');
          }
        }
      }

      // Pre-seed the commercial brand profile if the installer selected a
      // brand library entry during the brandSetup step (Part 8, Path 2).
      // This must happen AFTER the customer's user doc exists (the
      // brand_profile rule requires writing under the customer's uid).
      // BrandDesignGenerator writes favorites directly to
      // /users/{userId}/favorites/* via Firestore (see Part 8 generator
      // refactor), so the auth state at the moment of execution
      // (anonymous after the signInAnonymously above) doesn't matter —
      // the explicit userId is authoritative.
      // Non-blocking: a failure here doesn't undo the install. The
      // customer can re-run brand setup themselves from the Brand tab.
      final selectedBrand =
          ref.read(installerSelectedBrandLibraryEntryProvider);
      if (selectedBrand != null && siteMode == SiteMode.commercial) {
        try {
          final brandProfile = CommercialBrandProfile(
            companyName: selectedBrand.companyName,
            brandLibraryId: selectedBrand.brandId,
            colors: selectedBrand.colors,
            customized: false,
            signature: selectedBrand.signature,
            generatedDesigns: const [],
            createdByInstaller: installerAnonymousUid,
            createdAt: DateTime.now(),
          );
          final brandJson = brandProfile.toJson();
          brandJson['created_at'] = FieldValue.serverTimestamp();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('brand_profile')
              .doc('brand')
              .set(brandJson, SetOptions(merge: true));

          // Mirror brand_library_id onto the user-doc commercial_profile
          // map for the residential→commercial mode switcher's quick-read
          // path. The full commercial_profile structure is written later
          // by the customer's CommercialOnboardingWizard (or here if a
          // commercial profile already exists, set+merge will only add
          // brand_library_id without overwriting other fields).
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .set({
            'commercial_profile': {
              'brand_library_id': selectedBrand.brandId,
            },
          }, SetOptions(merge: true));

          // Auto-generate the five canonical brand designs into the
          // customer's favorites + write generated_designs to the
          // brand_profile doc.
          final gen = BrandDesignGenerator(
              firestore: FirebaseFirestore.instance);
          await gen.generateBrandDesigns(
              userId: userId, brand: brandProfile);

          debugPrint('Installer: brand profile pre-seeded for '
              '${selectedBrand.companyName} → $userId');
        } catch (e) {
          debugPrint('Installer: brand pre-seed failed (non-blocking): $e');
        }
      }

      // No initial autopilot regeneration here — autopilot defaults to off
      // for fresh installs (Bug 4c, 2026-05-07 tracker). Customers who want
      // autopilot can enable it from the autopilot screen, which seeds the
      // calendar on first enable.

      // 6. Create installation record for tracking/analytics
      final installationRecord = InstallationRecord(
        id: installationRef.id,
        customerId: userId,
        customerInfo: customerInfo,
        dealerCode: session.dealer.dealerCode,
        installerCode: session.installer.installerCode,
        installerName: session.installer.name,
        dealerCompanyName: session.dealer.companyName,
        installedAt: DateTime.now(),
        controllerIds: selectedControllers.toList(),
        systemConfig: systemConfig,
        notes: customerInfo.notes.isNotEmpty ? customerInfo.notes : null,
      );

      await FirebaseFirestore.instance
          .collection('installation_records')
          .doc(installationRef.id)
          .set(UserService.sanitizeForFirestore(installationRecord.toMap()));

      // 7. Update referral pipeline status → "installed"
      try {
        await ref.read(referralPipelineServiceProvider).updateReferralStatus(
          prospectUid: userId,
          newStatus: 'installed',
          jobId: installationRef.id,
        );
      } catch (e) {
        debugPrint('Referral pipeline update failed (non-blocking): $e');
      }

      // 8. Increment installer's installation count — best-effort analytics.
      //
      // The /installers read is admin/owner-scoped (D3-HOTFIX,
      // firestore.rules:1120 → hasAdminOrOwnerClaim). A non-admin installer
      // session — anonymous fallback, or an 'installer'/'salesperson' staff
      // claim — is DENIED here. That must never fail a completed install, so
      // this mirrors the non-blocking referral block above. (This exact read is
      // what surfaced the whole "install failed on a successful install" bug:
      // it was unwrapped and threw to the outer catch after the customer was
      // already provisioned.)
      try {
        final installerQuery = await FirebaseFirestore.instance
            .collection('installers')
            .where('fullPin', isEqualTo: session.installer.fullPin)
            .limit(1)
            .get();

        if (installerQuery.docs.isNotEmpty) {
          await installerQuery.docs.first.reference.update({
            'totalInstallations': FieldValue.increment(1),
          });
        }
      } catch (e) {
        debugPrint('Installer: installation-count bump failed (non-blocking): $e');
      }

      // NOTE: Do NOT sign out here. Signing out fires AuthStateListenable
      // which triggers GoRouter's redirect, destroying the wizard widget
      // tree and the handoff credentials dialog before the installer can
      // read the customer's temp password. Sign-out is deferred to the
      // "Done" button inside _showHandoffCredentials() instead.

      setState(() => _isProcessing = false);

      // 9. Show handoff credentials screen
      if (mounted) {
        _showHandoffCredentials(
          customerName: customerInfo.name,
          email: customerInfo.email,
          tempPassword: isExistingAccount ? null : tempPassword,
          installationId: installationRef.id,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isProcessing = false);
      // Post-commit: the customer is provisioned. Show handoff + warning, never
      // "Setup failed" (which also hides the credentials the installer needs).
      if (classifyInstallError(installCommitted: installCommitted) ==
          InstallErrorOutcome.completeWithWarning) {
        _completeWithHandoffWarning(
          customerName: customerInfo.name,
          email: customerInfo.email,
          isExistingAccount: isExistingAccount,
          tempPassword: handoffTempPassword,
          installationId: handoffInstallationId,
          error: e,
        );
        return;
      }
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'An account with this email already exists.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'weak-password':
          errorMessage = 'The password is too weak.';
          break;
        default:
          errorMessage = 'Failed to create account: ${e.message}';
      }
      _showError(errorMessage);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (classifyInstallError(installCommitted: installCommitted) ==
          InstallErrorOutcome.completeWithWarning) {
        _completeWithHandoffWarning(
          customerName: customerInfo.name,
          email: customerInfo.email,
          isExistingAccount: isExistingAccount,
          tempPassword: handoffTempPassword,
          installationId: handoffInstallationId,
          error: e,
        );
        return;
      }
      _showError('Setup failed: $e');
    }
  }

  /// Post-commit fallback: the customer is provisioned but a later bookkeeping
  /// step threw. Show the handoff-credentials screen (the install IS done) with
  /// a warning banner instead of a failure dialog.
  void _completeWithHandoffWarning({
    required String customerName,
    required String email,
    required bool isExistingAccount,
    required String? tempPassword,
    required String? installationId,
    required Object error,
  }) {
    debugPrint('Installer: post-commit bookkeeping failed (non-fatal): $error');
    if (!mounted) return;
    _showHandoffCredentials(
      customerName: customerName,
      email: email,
      tempPassword: isExistingAccount ? null : tempPassword,
      installationId: installationId ?? '',
      warning: 'The customer is fully set up and can sign in. A final '
          "bookkeeping step didn't finish — no action needed.",
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Error', style: TextStyle(color: Colors.red)),
        content: Text(message, style: const TextStyle(color: NexGenPalette.textMedium)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  void _showHandoffCredentials({
    required String customerName,
    required String email,
    required String? tempPassword,
    required String installationId,
    String? warning,
  }) {
    final isExisting = tempPassword == null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Setup Complete!', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (warning != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(warning,
                            style: const TextStyle(
                                color: Colors.orange, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                isExisting
                    ? 'Existing account has been linked to this installation.'
                    : 'Customer account has been created successfully.',
                style: const TextStyle(color: NexGenPalette.textMedium),
              ),
              const SizedBox(height: 24),
              const Text(
                'CUSTOMER LOGIN CREDENTIALS',
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              _buildCredentialRow('Name', customerName),
              const SizedBox(height: 8),
              _buildCredentialRow('Email', email, canCopy: true),
              if (!isExisting) ...[
                const SizedBox(height: 8),
                _buildCredentialRow('Temporary Password', tempPassword, canCopy: true, isPassword: true),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isExisting
                            ? 'Customer can sign in with their existing password.'
                            : 'Customer should change their password after first login.',
                        style: const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isExisting)
            TextButton(
              onPressed: () {
                // Copy all credentials to clipboard
                final credentials = 'Lumina App Login\n\nEmail: $email\nTemporary Password: $tempPassword\n\nPlease change your password after first login.';
                Clipboard.setData(ClipboardData(text: credentials));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Credentials copied to clipboard'),
                  backgroundColor: NexGenPalette.cyan,
                ),
              );
            },
            child: const Text('Copy All', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Clear draft since setup is complete
              await InstallerDraftService.clearDraft();
              // Reset all wizard state
              resetInstallerWizardState(ref);
              ref.read(installerModeActiveProvider.notifier).exitInstallerMode();
              // Sign out the anonymous/installer session NOW — after the
              // installer has seen the credentials. Doing this earlier
              // (in _completeSetup) would fire AuthStateListenable and
              // trigger GoRouter to redirect to /login, destroying the
              // dialog before the installer could read the temp password.
              await FirebaseAuth.instance.signOut();
              if (mounted) this.context.go('/');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
            ),
            child: const Text('Done', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialRow(String label, String value, {bool canCopy = false, bool isPassword = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.line.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: isPassword ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: isPassword ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          if (canCopy)
            IconButton(
              icon: const Icon(Icons.copy, color: NexGenPalette.cyan, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    backgroundColor: NexGenPalette.cyan,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Exit Installer Mode?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your progress will be saved. You will need to re-enter the PIN to continue.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Save draft before exiting
              await _saveDraft();
              ref.read(installerModeActiveProvider.notifier).exitInstallerMode();
              if (mounted) this.context.go('/');
            },
            child: const Text('Save & Exit', style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Clear draft and reset
              await InstallerDraftService.clearDraft();
              resetInstallerWizardState(ref);
              ref.read(installerModeActiveProvider.notifier).exitInstallerMode();
              if (mounted) this.context.go('/');
            },
            child: const Text('Exit Without Saving', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  _StepInfo _getStepInfo(InstallerWizardStep step) {
    switch (step) {
      case InstallerWizardStep.customerInfo:
        return _StepInfo('Customer Info', 'Customer');
      case InstallerWizardStep.controllerSetup:
        return _StepInfo('Controller Setup', 'Controllers');
      case InstallerWizardStep.connectionMethod:
        return _StepInfo('Connection Method', 'Network');
      case InstallerWizardStep.zoneConfiguration:
        return _StepInfo('Zone Configuration', 'Zones');
      case InstallerWizardStep.hardwareConfig:
        return _StepInfo('Hardware Config', 'Hardware');
      case InstallerWizardStep.mapRoofline:
        return _StepInfo('Map Roofline', 'Map');
      case InstallerWizardStep.brandSetup:
        return _StepInfo('Brand Setup', 'Brand');
      case InstallerWizardStep.handoff:
        return _StepInfo('Customer Handoff', 'Handoff');
    }
  }
}

class _StepInfo {
  final String label;
  final String shortLabel;

  _StepInfo(this.label, this.shortLabel);
}
