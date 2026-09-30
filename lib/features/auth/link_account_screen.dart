import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/auth/support_contact.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Screen shown to users who have created an account but are not linked
/// to any Nex-Gen LED installation.
///
/// After the public store launch this is the front door for strangers and
/// prospects, not a rare error state. Lumina is professionally installed, so
/// it never offers to set up a controller. It explains that the account is
/// not linked yet, says who to contact (the account's dealer when the profile
/// carries a `dealer_code`, otherwise Nex-Gen LED), and offers the demo. A
/// family member with an invitation code, and staff, still have their doors.
class LinkAccountScreen extends ConsumerWidget {
  const LinkAccountScreen({super.key});

  static const explanation =
      "Your account isn't linked to a lighting system yet.\n\n"
      'Nex-Gen LED systems are installed by a professional, and your '
      'installer links your account when your lights are set up. If your '
      'lights are already in, get in touch and your account will be linked.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(accountSessionProvider);
    final signedInEmail = session.isSignedIn ? session.email : null;
    final contact = ref.watch(supportContactProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: SafeArea(
        // Scrolls when large text makes the page taller than the screen; the
        // Spacer still pushes the staff panel down when it fits.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                NexGenPalette.cyan,
                                NexGenPalette.cyan.withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.lightbulb_outline,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Welcome to Lumina',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        explanation,
                        key: const ValueKey('link-explanation'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      if (signedInEmail != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Signed in as $signedInEmail',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                NexGenPalette.textMedium.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _ContactCard(contact: contact),
                      const SizedBox(height: 12),
                      _DemoCard(
                        onTap: () => context.push(AppRoutes.demoCode),
                      ),
                      const SizedBox(height: 4),
                      // The family-member door. The owner creates the
                      // invitation from Manage Users; the invitee redeems it
                      // here, signed in with the invited email.
                      TextButton(
                        key: const ValueKey('link-invitation-code'),
                        onPressed: () => context.push(AppRoutes.joinWithCode),
                        child: Text(
                          "Joining a family member's system? "
                          'Enter your invitation code',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 16),
                      // Professional access section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: NexGenPalette.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.badge_outlined,
                                    size: 18, color: NexGenPalette.textMedium),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Nex-Gen Professional Access',
                                    style: TextStyle(
                                      color: NexGenPalette.textMedium,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // The "Media" button that used to sit beside this
                            // one was removed 2026-08-11
                            // (audit/INSTALLER_ENTRY.md): it opened the
                            // 4-digit staff PIN screen for a 6-character media
                            // code, and the media flow itself is not shippable
                            // (no rules for media_codes, /media not in the
                            // unlinked allow-list, a client-side fabricated
                            // installer session). Reviving it is a feature
                            // decision, not a route fix.
                            Row(
                              children: [
                                Expanded(
                                  child: _ProfessionalButton(
                                    icon: Icons.engineering_outlined,
                                    label: 'Installer',
                                    color: NexGenPalette.cyan,
                                    onTap: () =>
                                        context.push(AppRoutes.staffPin),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () async {
                          await ref.read(accountSessionProvider).signOut();
                          if (context.mounted) {
                            context.go(AppRoutes.login);
                          }
                        },
                        child: Text(
                          'Sign out',
                          style: TextStyle(
                            color:
                                NexGenPalette.textMedium.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who to contact: the account's dealer, or Nex-Gen LED.
class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.contact});

  final AsyncValue<SupportContact> contact;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Uri uri,
    String shown,
  ) async {
    var ok = false;
    try {
      ok = await ref.read(externalLinkOpenerProvider)(uri);
    } catch (_) {
      ok = false;
    }
    if (ok || !context.mounted) return;
    // Leave the value on screen so it can be copied by hand.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Couldn't open that. Reach them at $shown.")),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = contact.valueOrNull;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent, size: 18,
                  color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c == null
                      ? 'Finding your installer…'
                      : c.isDealer
                          ? 'Your installer'
                          : 'Get in touch',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (c == null) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: NexGenPalette.cyan),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              c.name,
              key: const ValueKey('link-contact-name'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!c.isDealer) ...[
              const SizedBox(height: 4),
              Text(
                'Ask about a system for your home, or about linking an '
                'account for lights you already have.',
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            if (c.telUri != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const ValueKey('link-contact-call'),
                  onPressed: () => _open(context, ref, c.telUri!, c.phone!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.phone),
                  label: Text(
                    'Call ${c.phone}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (c.telUri != null && c.mailtoUri != null)
              const SizedBox(height: 8),
            if (c.mailtoUri != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('link-contact-email'),
                  onPressed: () =>
                      _open(context, ref, c.mailtoUri!, c.email!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: NexGenPalette.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.email_outlined),
                  label: Text(
                    'Email ${c.email}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            if (c.webUri != null) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  key: const ValueKey('link-contact-web'),
                  onPressed: () =>
                      _open(context, ref, c.webUri!, c.website!),
                  child: Text(
                    'Visit ${c.website}',
                    style: const TextStyle(
                        color: NexGenPalette.cyan, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The second action: try the demo while waiting.
class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Just looking?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try the demo: a sample house you can light up, no system '
            'needed.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('link-demo'),
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: NexGenPalette.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text(
                'Explore the demo',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Button for professional access options.
class _ProfessionalButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ProfessionalButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
