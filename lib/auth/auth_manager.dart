import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Abstract interface for authentication
abstract class AuthManager {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  Future<UserCredential> signInWithEmailAndPassword(String email, String password);
  Future<UserCredential> createUserWithEmailAndPassword(String email, String password, String displayName);
  Future<void> signOut();
  Future<void> sendPasswordResetEmail(String email);
}

/// Firebase implementation of AuthManager
class FirebaseAuthManager implements AuthManager {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      
      // Create user profile in Firestore
      if (credential.user != null) {
        final now = DateTime.now();
        final userModel = UserModel(
          id: credential.user!.uid,
          email: email,
          displayName: displayName,
          ownerId: credential.user!.uid,
          createdAt: now,
          updatedAt: now,
        );
        await _userService.createUser(userModel);
        
        // Update Firebase Auth display name
        await credential.user!.updateDisplayName(displayName);
      }
      
      return credential;
    } catch (e) {
      debugPrint('Create user error: $e');
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('Password reset error: $e');
      rethrow;
    }
  }
}
