import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';

/// Listenable that notifies when Firebase Auth state changes.
/// Used to trigger GoRouter redirect checks.
class AuthStateListenable extends ChangeNotifier {
  AuthStateListenable() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}

/// Creates an unlinked user profile for new Firebase Auth users.
Future<void> createUnlinkedUserProfile(User user) async {
  try {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'id': user.uid,
      'email': user.email ?? '',
      'display_name': user.displayName ?? user.email?.split('@').first ?? 'User',
      'photo_url': user.photoURL,
      'owner_id': user.uid,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'installation_role': 'unlinked',
      'welcome_completed': false,
    }, SetOptions(merge: true));
    debugPrint('Created unlinked user profile for ${user.uid}');
  } catch (e) {
    debugPrint('Error creating unlinked user profile: $e');
  }
}

/// Global redirect function for GoRouter.
/// Handles auth checks, role-based access, and installation validation.
Future<String?> appRedirect(BuildContext context, GoRouterState state) async {
  final user = FirebaseAuth.instance.currentUser;
  final isLoggedIn = user != null;

  // Define route categories
  final isAuthRoute = state.matchedLocation == AppRoutes.login ||
      state.matchedLocation == AppRoutes.signUp ||
      state.matchedLocation == AppRoutes.forgotPassword;

  final isLinkRoute = state.matchedLocation == AppRoutes.linkAccount ||
      state.matchedLocation == AppRoutes.joinWithCode;

  final isInstallerRoute = state.matchedLocation.startsWith('/installer') ||
      state.matchedLocation.startsWith('/admin');

  // Check if this is a demo route (allowed without auth)
  final isDemoRoute = state.matchedLocation.startsWith('/demo');

  // If user is not logged in
  if (!isLoggedIn) {
    // Allow auth routes, welcome wizard, and demo routes
    if (isAuthRoute || state.matchedLocation == AppRoutes.welcome || isDemoRoute) {
      return null;
    }
    return AppRoutes.login;
  }

  // User is logged in
  // If trying to access auth routes, redirect to dashboard (or link-account if unlinked)
  if (isAuthRoute) {
    // Check if user has installation access
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final role = data['installation_role'] as String?;
        final installationId = data['installation_id'] as String?;

        // Unlinked users go to link-account
        // DEV BYPASS: Skip link-account for testing (remove before production)
        const devBypassLinkAccount = true;
        if (!devBypassLinkAccount && (role == null || role == 'unlinked')) {
          return AppRoutes.linkAccount;
        }

        // Installers and admins don't need an installation
        if (role == 'installer' || role == 'admin') {
          return AppRoutes.dashboard;
        }

        // Primary and subUser need an installation
        // DEV BYPASS: Skip installation check for testing
        if (!devBypassLinkAccount && installationId == null) {
          return AppRoutes.linkAccount;
        }
      } else {
        // User exists in Auth but not Firestore - create unlinked profile
        await createUnlinkedUserProfile(user);
        return AppRoutes.linkAccount;
      }
    } catch (e) {
      debugPrint('Redirect: Error checking user status: $e');
    }
    return AppRoutes.dashboard;
  }

  // Allow link routes and installer routes without further checks
  if (isLinkRoute || isInstallerRoute || state.matchedLocation == AppRoutes.welcome) {
    return null;
  }

  // For protected routes (dashboard, settings, etc.), verify installation access
  // DEV BYPASS: Skip all installation checks for testing
  const devBypassInstallation = true;
  if (devBypassInstallation) {
    return null; // Allow access to all routes
  }

  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      await createUnlinkedUserProfile(user);
      return AppRoutes.linkAccount;
    }

    final data = userDoc.data()!;
    final role = data['installation_role'] as String?;
    final installationId = data['installation_id'] as String?;

    // Unlinked users must go to link-account
    if (role == null || role == 'unlinked') {
      return AppRoutes.linkAccount;
    }

    // Installers and admins have unrestricted access
    if (role == 'installer' || role == 'admin') {
      return null;
    }

    // Primary and subUser need a valid installation
    if (installationId == null) {
      return AppRoutes.linkAccount;
    }

    // Check if installation is still active
    final installDoc = await FirebaseFirestore.instance
        .collection('installations')
        .doc(installationId)
        .get();

    if (installDoc.exists && installDoc.data()?['is_active'] == false) {
      // Installation deactivated - show error (for now, redirect to link-account)
      return AppRoutes.linkAccount;
    }
  } catch (e) {
    debugPrint('Redirect: Error checking installation access: $e');
    // On error, allow access (fail open for better UX, security handled by Firestore rules)
  }

  // No redirect needed
  return null;
}
