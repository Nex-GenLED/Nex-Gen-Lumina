import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/services/user_service.dart';

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
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      UserService.sanitizeForFirestore({
        'id': user.uid,
        'email': user.email ?? '',
        'display_name': user.displayName ?? user.email?.split('@').first ?? 'User',
        if (user.photoURL != null) 'photo_url': user.photoURL,
        'owner_id': user.uid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'installation_role': 'unlinked',
        'welcome_completed': false,
      }),
      SetOptions(merge: true),
    );
    debugPrint('Created unlinked user profile for ${user.uid}');
  } catch (e) {
    debugPrint('Error creating unlinked user profile: $e');
  }
}

/// Global redirect function for GoRouter.
/// Handles auth checks, role-based access, and installation validation.
Future<String?> appRedirect(BuildContext context, GoRouterState state) async {
  // Gate restricted routes during demo browsing
  if (isDemoBrowsingFlag) {
    final location = state.matchedLocation;
    const restricted = ['/installer', '/sales', '/admin', '/dealer'];
    if (restricted.any((r) => location.startsWith(r))) {
      return AppRoutes.dashboard;
    }
  }

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

  final isSalesRoute = state.matchedLocation.startsWith('/sales');

  // Check if this is a demo route (allowed without auth)
  final isDemoRoute = state.matchedLocation.startsWith('/demo');

  // If user is not logged in
  if (!isLoggedIn) {
    // Allow auth routes, welcome wizard, demo routes, and demo browsing
    if (isAuthRoute || state.matchedLocation == AppRoutes.welcome || isDemoRoute || isDemoBrowsingFlag) {
      return null;
    }
    return AppRoutes.login;
  }

  // User is logged in

  // Anonymous users are only allowed on installer routes.
  // The installer flow uses anonymous auth to avoid session conflicts
  // when creating customer accounts during the setup wizard.
  if (user.isAnonymous) {
    if (isInstallerRoute || isSalesRoute) return null; // Allow installer & sales routes
    return AppRoutes.login; // Block everything else for anonymous users
  }

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

        // Installers and admins don't need an installation
        if (role == 'installer' || role == 'admin') {
          return AppRoutes.dashboard;
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

  // Allow link routes, installer/sales routes, and first-run without further checks
  final isFirstRunRoute = state.matchedLocation == AppRoutes.firstRun;
  if (isLinkRoute || isInstallerRoute || isSalesRoute || isFirstRunRoute ||
      state.matchedLocation == AppRoutes.welcome) {
    return null;
  }

  // First-run check: redirect to onboarding if welcomeCompleted == false
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (userDoc.exists) {
      final data = userDoc.data()!;
      final welcomeCompleted = data['welcome_completed'] as bool? ?? true;
      final role = data['installation_role'] as String?;
      // Only redirect primary/subUser roles (not installers/admins)
      if (!welcomeCompleted &&
          role != 'installer' &&
          role != 'admin' &&
          role != 'unlinked') {
        return AppRoutes.firstRun;
      }
    }
  } catch (e) {
    debugPrint('Redirect: Error checking welcome_completed: $e');
  }

  // Commercial mode redirect: when navigating to residential dashboard,
  // check if user should be routed to commercial home instead.
  final isCommercialRoute = state.matchedLocation.startsWith('/commercial');
  if (state.matchedLocation == AppRoutes.dashboard && !isCommercialRoute) {
    try {
      // Check local override first (fastest)
      final prefs = await SharedPreferences.getInstance();
      final override = prefs.getBool('commercial_mode_override');
      bool isCommercialMode = false;

      if (override != null) {
        isCommercialMode = override;
      } else {
        // Check Firestore profile type
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          if (data['profile_type'] == 'commercial') {
            // Verify at least one commercial location exists
            final locSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('commercial_locations')
                .limit(1)
                .get();
            isCommercialMode = locSnap.docs.isNotEmpty;
          }
        }
      }

      if (isCommercialMode) {
        return AppRoutes.commercialHome;
      }
    } catch (e) {
      debugPrint('Redirect: Commercial mode check failed: $e');
    }
  }

  // For protected routes (dashboard, settings, etc.), verify installation access
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data()!;
      final role = data['installation_role'] as String?;

      // Admin: unrestricted access to all routes
      if (role == 'admin') {
        return null;
      }

      // Installer: allow access to all routes (they need to see/configure
      // the residential dashboard and system settings)
      if (role == 'installer') {
        return null;
      }

      // Unlinked: redirect to link-account for any protected route
      if (role == null || role == 'unlinked') {
        return AppRoutes.linkAccount;
      }

      // primary / subUser with a valid installation: allow access
      return null;
    } else {
      // User exists in Auth but not Firestore - create unlinked profile
      await createUnlinkedUserProfile(user);
      return AppRoutes.linkAccount;
    }
  } catch (e) {
    debugPrint('Redirect: Error verifying installation access: $e');
    // On error, allow access rather than blocking (network issues, etc.)
    return null;
  }
}
