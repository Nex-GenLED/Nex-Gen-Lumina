import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manage Family Members is hidden (+110, package G follow-up 4).
///
/// Self-signup is gone, and nothing creates a family member's account yet,
/// so the screen would invite an owner to mint an invitation code nobody can
/// redeem. The screen, `InvitationService` and the join screen stay in the
/// codebase; they come back when a sub-user account-creation function exists.
///
/// Build with `--dart-define=LUMINA_MANAGE_FAMILY_MEMBERS=true` to show it.
const bool kManageFamilyMembersEnabled =
    bool.fromEnvironment('LUMINA_MANAGE_FAMILY_MEMBERS');

/// The flag as widgets read it; tests override this.
final manageFamilyMembersEnabledProvider =
    Provider<bool>((ref) => kManageFamilyMembersEnabled);

/// Where the `/settings/users` route sends people while the flag is off:
/// back to the profile page it was reached from (`AppRoutes.profile`, spelt
/// out here so this file does not import the router). Null lets the route
/// open.
String? manageFamilyMembersRedirect({required bool enabled}) =>
    enabled ? null : '/settings/profile';
