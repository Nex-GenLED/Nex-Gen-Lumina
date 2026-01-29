import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for managing Google Home Smart Home Action integration.
///
/// Handles:
/// - Account linking status tracking
/// - Deep link to Google Home app for setup
/// - Firestore persistence of linking state
class GoogleHomeService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  GoogleHomeService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// The Google Home Action package name
  static const String actionPackage = 'com.nexgenled.command';

  /// Deep link to Google Home app
  static const String googleHomeAppUrl = 'googlehome://';

  /// Web link to set up Smart Home Action
  static const String setupWebUrl =
      'https://assistant.google.com/services/invoke/uid/000000YOUR_PROJECT_ID';

  /// Check if the current user has linked their Google Home account
  Future<bool> isAccountLinked() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('google_home')
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      return data?['isLinked'] == true;
    } catch (e) {
      debugPrint('GoogleHomeService: Error checking link status: $e');
      return false;
    }
  }

  /// Get the Google Home linking status as a stream for real-time updates
  Stream<GoogleHomeLinkStatus> watchLinkStatus() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(GoogleHomeLinkStatus.notLoggedIn);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('integrations')
        .doc('google_home')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return GoogleHomeLinkStatus.notLinked;

      final data = doc.data();
      if (data?['isLinked'] == true) {
        return GoogleHomeLinkStatus.linked;
      } else if (data?['linkInitiated'] == true) {
        return GoogleHomeLinkStatus.pending;
      }
      return GoogleHomeLinkStatus.notLinked;
    });
  }

  /// Get detailed Google Home integration info
  Future<GoogleHomeIntegrationInfo?> getIntegrationInfo() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('google_home')
          .get();

      if (!doc.exists) return null;

      return GoogleHomeIntegrationInfo.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('GoogleHomeService: Error getting integration info: $e');
      return null;
    }
  }

  /// Initiate the Google Home account linking flow
  ///
  /// This opens the Google Home app where the user can:
  /// 1. Add the Nex-Gen Lumina action
  /// 2. Complete OAuth account linking
  /// 3. Discover their devices
  Future<bool> initiateAccountLinking() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('GoogleHomeService: User not logged in');
      return false;
    }

    try {
      // Mark that we initiated the linking process
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('google_home')
          .set({
        'linkInitiated': true,
        'initiatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Try to open the Google Home app first, fall back to web
      final appUri = Uri.parse(googleHomeAppUrl);
      final webUri = Uri.parse(setupWebUrl);

      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        debugPrint('GoogleHomeService: Opened Google Home app');
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        debugPrint('GoogleHomeService: Opened Google Home web');
      } else {
        debugPrint('GoogleHomeService: Could not open Google Home app or web');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('GoogleHomeService: Error initiating account linking: $e');
      return false;
    }
  }

  /// Unlink Google Home account
  ///
  /// This removes the local linking record. The user should also
  /// unlink the action in the Google Home app to fully disconnect.
  Future<bool> unlinkAccount() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('google_home')
          .delete();

      debugPrint('GoogleHomeService: Unlinked Google Home account');
      return true;
    } catch (e) {
      debugPrint('GoogleHomeService: Error unlinking account: $e');
      return false;
    }
  }

  /// Request device sync in Google Home
  ///
  /// Opens Google Home app with instructions to sync devices
  Future<void> syncDevices() async {
    final uri = Uri.parse(googleHomeAppUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fall back to web
      final webUri = Uri.parse('https://home.google.com/');
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Get example voice commands for the user
  List<String> getExampleCommands() {
    return [
      '"Hey Google, turn on the house lights"',
      '"Hey Google, turn off the lights"',
      '"Hey Google, set the lights to 50%"',
      '"Hey Google, dim the house lights"',
      '"Hey Google, activate [scene name]"',
    ];
  }
}

/// Google Home account linking status
enum GoogleHomeLinkStatus {
  /// User is not logged in to the app
  notLoggedIn,

  /// Google Home is not linked
  notLinked,

  /// Link flow was initiated but not completed
  pending,

  /// Google Home is successfully linked
  linked,
}

/// Detailed information about the Google Home integration
class GoogleHomeIntegrationInfo {
  final bool isLinked;
  final bool linkInitiated;
  final DateTime? linkedAt;
  final DateTime? initiatedAt;
  final String? googleUserId;
  final int? deviceCount;

  GoogleHomeIntegrationInfo({
    required this.isLinked,
    required this.linkInitiated,
    this.linkedAt,
    this.initiatedAt,
    this.googleUserId,
    this.deviceCount,
  });

  factory GoogleHomeIntegrationInfo.fromMap(Map<String, dynamic> map) {
    return GoogleHomeIntegrationInfo(
      isLinked: map['isLinked'] ?? false,
      linkInitiated: map['linkInitiated'] ?? false,
      linkedAt: (map['linkedAt'] as Timestamp?)?.toDate(),
      initiatedAt: (map['initiatedAt'] as Timestamp?)?.toDate(),
      googleUserId: map['googleUserId'],
      deviceCount: map['deviceCount'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isLinked': isLinked,
      'linkInitiated': linkInitiated,
      if (linkedAt != null) 'linkedAt': Timestamp.fromDate(linkedAt!),
      if (initiatedAt != null) 'initiatedAt': Timestamp.fromDate(initiatedAt!),
      if (googleUserId != null) 'googleUserId': googleUserId,
      if (deviceCount != null) 'deviceCount': deviceCount,
    };
  }
}

// ============== Riverpod Providers ==============

/// Provider for the Google Home service
final googleHomeServiceProvider = Provider<GoogleHomeService>((ref) {
  return GoogleHomeService();
});

/// Provider for watching Google Home link status
final googleHomeLinkStatusProvider = StreamProvider<GoogleHomeLinkStatus>((ref) {
  final service = ref.watch(googleHomeServiceProvider);
  return service.watchLinkStatus();
});

/// Provider to check if Google Home is linked (one-time check)
final isGoogleHomeLinkedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(googleHomeServiceProvider);
  return service.isAccountLinked();
});

/// Provider for Google Home integration info
final googleHomeIntegrationInfoProvider = FutureProvider<GoogleHomeIntegrationInfo?>((ref) async {
  final service = ref.watch(googleHomeServiceProvider);
  return service.getIntegrationInfo();
});
