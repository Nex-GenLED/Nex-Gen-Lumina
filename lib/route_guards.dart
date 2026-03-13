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

        // DEV BYPASS: Link-account and installation checks skipped for testing
        // (remove before production)

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

  // Allow link routes, installer routes, and first-run without further checks
  final isFirstRunRoute = state.matchedLocation == AppRoutes.firstRun;
  if (isLinkRoute || isInstallerRoute || isFirstRunRoute ||
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

  // For protected routes (dashboard, settings, etc.), verify installation access
  // DEV BYPASS: Skip all installation checks for testing
  return null; // Allow access to all routes
}
