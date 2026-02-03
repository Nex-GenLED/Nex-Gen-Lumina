import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/installer/installer_draft_service.dart';
import 'package:nexgen_command/features/installer/screens/customer_info_screen.dart';
import 'package:nexgen_command/features/installer/screens/controller_setup_screen.dart';
import 'package:nexgen_command/features/installer/screens/zone_configuration_screen.dart';
import 'package:nexgen_command/features/installer/handoff_screen.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/models/installation_model.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

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

    switch (step) {
      case InstallerWizardStep.customerInfo:
        return CustomerInfoScreen(
          onNext: () => _goToStep(InstallerWizardStep.controllerSetup),
        );
      case InstallerWizardStep.controllerSetup:
        return ControllerSetupScreen(
          onBack: () => _goToStep(InstallerWizardStep.customerInfo),
          onNext: () => _goToStep(InstallerWizardStep.zoneConfiguration),
        );
      case InstallerWizardStep.zoneConfiguration:
        return ZoneConfigurationScreen(
          onBack: () => _goToStep(InstallerWizardStep.controllerSetup),
          onNext: () => _goToStep(InstallerWizardStep.handoff),
        );
      case InstallerWizardStep.handoff:
        return HandoffScreen(
          onBack: () => _goToStep(InstallerWizardStep.zoneConfiguration),
          onNext: _completeSetup,
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

  Future<void> _completeSetup() async {
    final customerInfo = ref.read(installerCustomerInfoProvider);
    final session = ref.read(installerSessionProvider);

    if (session == null) {
      _showError('Installer session expired. Please re-enter your PIN.');
      return;
    }

    if (!customerInfo.isValid) {
      _showError('Please complete all required customer information.');
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // 1. Generate temporary password
      final tempPassword = _generateTempPassword();

      // 2. Create Firebase Auth account for customer
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: customerInfo.email.trim().toLowerCase(),
        password: tempPassword,
      );
      final userId = credential.user!.uid;

      // 3. Get installer-collected configuration
      final siteMode = ref.read(installerSiteModeProvider);
      final selectedControllers = ref.read(installerSelectedControllersProvider);
      final linkedControllers = ref.read(installerLinkedControllersProvider);
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

      // 4. Create Installation document
      final installationRef = FirebaseFirestore.instance.collection('installations').doc();

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

      await installationRef.set(installation.toJson());

      // 5. Create UserModel with Primary role
      final userModel = UserModel(
        id: userId,
        email: customerInfo.email.trim().toLowerCase(),
        displayName: customerInfo.name,
        phoneNumber: customerInfo.phone,
        address: '${customerInfo.address}\n${customerInfo.city}, ${customerInfo.state} ${customerInfo.zipCode}',
        ownerId: userId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        installationId: installationRef.id,
        installationRole: InstallationRole.primary,
        primaryUserId: userId,
        linkedAt: DateTime.now(),
      );

      await FirebaseFirestore.instance.collection('users').doc(userId).set(userModel.toJson());

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
          .set(installationRecord.toMap());

      // 7. Increment installer's installation count
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

      // 8. Sign out installer from customer's account
      await FirebaseAuth.instance.signOut();

      setState(() => _isProcessing = false);

      // 9. Show handoff credentials screen
      if (mounted) {
        _showHandoffCredentials(
          customerName: customerInfo.name,
          email: customerInfo.email,
          tempPassword: tempPassword,
          installationId: installationRef.id,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isProcessing = false);
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
      _showError('Setup failed: $e');
    }
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
    required String tempPassword,
    required String installationId,
  }) {
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
              const Text(
                'Customer account has been created successfully.',
                style: TextStyle(color: NexGenPalette.textMedium),
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
              const SizedBox(height: 8),
              _buildCredentialRow('Temporary Password', tempPassword, canCopy: true, isPassword: true),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Customer should change their password after first login.',
                        style: TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
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
      case InstallerWizardStep.zoneConfiguration:
        return _StepInfo('Zone Configuration', 'Zones');
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
