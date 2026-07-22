import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Persistent top-of-scaffold banner shown while an installer is accessing
/// a customer's account via the Existing Customer search flow. Hidden
/// (renders an empty SizedBox.shrink) any time
/// [installerAccessingCustomerProvider] is null, so it's safe to mount
/// unconditionally on the main scaffold.
class InstallerModeBanner extends ConsumerWidget {
  const InstallerModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerUid = ref.watch(installerAccessingCustomerProvider);
    if (customerUid == null) return const SizedBox.shrink();

    final customerName =
        ref.watch(installerAccessingCustomerNameProvider) ?? 'Customer Account';

    return Container(
      width: double.infinity,
      color: NexGenPalette.violet.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.engineering, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Installer Mode — $customerName's Account",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => _exitInstallerMode(ref, context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Exit',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exitInstallerMode(WidgetRef ref, BuildContext context) {
    ref.read(installerAccessingCustomerProvider.notifier).state = null;
    ref.read(installerAccessingCustomerNameProvider.notifier).state = null;
    context.go(AppRoutes.installerLanding);
  }
}
