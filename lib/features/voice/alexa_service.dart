import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for managing Amazon Alexa Smart Home Skill integration.
///
/// Handles:
/// - Account linking status tracking
/// - Deep link to Alexa app for skill enabling
/// - Firestore persistence of linking state
class AlexaService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AlexaService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// The Alexa skill ID (set this to your actual skill ID after publishing)
  static const String skillId = 'amzn1.ask.skill.YOUR_SKILL_ID';

  /// Deep link to enable the skill in the Alexa app
  static const String alexaSkillEnableUrl =
      'https://alexa.amazon.com/spa/index.html#skills/dp/$skillId';

  /// Alternative: Direct link to Alexa app (mobile)
  static String get alexaAppDeepLink =>
      'alexa://skills/enable/$skillId';

  /// Check if the current user has linked their Alexa account
  Future<bool> isAccountLinked() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('alexa')
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      return data?['isLinked'] == true;
    } catch (e) {
      debugPrint('AlexaService: Error checking link status: $e');
      return false;
    }
  }

  /// Get the Alexa linking status as a stream for real-time updates
  Stream<AlexaLinkStatus> watchLinkStatus() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(AlexaLinkStatus.notLoggedIn);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('integrations')
        .doc('alexa')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return AlexaLinkStatus.notLinked;

      final data = doc.data();
      if (data?['isLinked'] == true) {
        return AlexaLinkStatus.linked;
      } else if (data?['linkInitiated'] == true) {
        return AlexaLinkStatus.pending;
      }
      return AlexaLinkStatus.notLinked;
    });
  }

  /// Get detailed Alexa integration info
  Future<AlexaIntegrationInfo?> getIntegrationInfo() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('alexa')
          .get();

      if (!doc.exists) return null;

      return AlexaIntegrationInfo.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('AlexaService: Error getting integration info: $e');
      return null;
    }
  }

  /// Initiate the Alexa account linking flow
  ///
  /// This opens the Alexa app or website where the user can:
  /// 1. Enable the Nex-Gen Lumina skill
  /// 2. Complete OAuth account linking
  /// 3. Discover their devices
  Future<bool> initiateAccountLinking() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('AlexaService: User not logged in');
      return false;
    }

    try {
      // Mark that we initiated the linking process
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('alexa')
          .set({
        'linkInitiated': true,
        'initiatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Try to open the Alexa app first, fall back to web
      final appUri = Uri.parse(alexaAppDeepLink);
      final webUri = Uri.parse(alexaSkillEnableUrl);

      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        debugPrint('AlexaService: Opened Alexa app');
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        debugPrint('AlexaService: Opened Alexa web');
      } else {
        debugPrint('AlexaService: Could not open Alexa app or web');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('AlexaService: Error initiating account linking: $e');
      return false;
    }
  }

  /// Unlink Alexa account
  ///
  /// This removes the local linking record. The user should also
  /// disable the skill in the Alexa app to fully disconnect.
  Future<bool> unlinkAccount() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc('alexa')
          .delete();

      debugPrint('AlexaService: Unlinked Alexa account');
      return true;
    } catch (e) {
      debugPrint('AlexaService: Error unlinking account: $e');
      return false;
    }
  }

  /// Trigger device discovery in Alexa
  ///
  /// Opens the Alexa app to the device discovery page
  Future<void> discoverDevices() async {
    const discoverUrl = 'alexa://devices/discover';
    final uri = Uri.parse(discoverUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fall back to web
      final webUri = Uri.parse(
          'https://alexa.amazon.com/spa/index.html#smart-home');
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Get example voice commands for the user
  List<String> getExampleCommands() {
    return [
      'Alexa, turn on the house lights',
      'Alexa, turn off house lights',
      'Alexa, set house lights to 50%',
      'Alexa, dim the house lights',
      'Alexa, turn on [scene name]',
    ];
  }
}

/// Alexa account linking status
enum AlexaLinkStatus {
  /// User is not logged in to the app
  notLoggedIn,

  /// Alexa is not linked
  notLinked,

  /// Link flow was initiated but not completed
  pending,

  /// Alexa is successfully linked
  linked,
}

/// Detailed information about the Alexa integration
class AlexaIntegrationInfo {
  final bool isLinked;
  final bool linkInitiated;
  final DateTime? linkedAt;
  final DateTime? initiatedAt;
  final String? amazonUserId;
  final int? deviceCount;

  AlexaIntegrationInfo({
    required this.isLinked,
    required this.linkInitiated,
    this.linkedAt,
    this.initiatedAt,
    this.amazonUserId,
    this.deviceCount,
  });

  factory AlexaIntegrationInfo.fromMap(Map<String, dynamic> map) {
    return AlexaIntegrationInfo(
      isLinked: map['isLinked'] ?? false,
      linkInitiated: map['linkInitiated'] ?? false,
      linkedAt: (map['linkedAt'] as Timestamp?)?.toDate(),
      initiatedAt: (map['initiatedAt'] as Timestamp?)?.toDate(),
      amazonUserId: map['amazonUserId'],
      deviceCount: map['deviceCount'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isLinked': isLinked,
      'linkInitiated': linkInitiated,
      if (linkedAt != null) 'linkedAt': Timestamp.fromDate(linkedAt!),
      if (initiatedAt != null) 'initiatedAt': Timestamp.fromDate(initiatedAt!),
      if (amazonUserId != null) 'amazonUserId': amazonUserId,
      if (deviceCount != null) 'deviceCount': deviceCount,
    };
  }
}

// ============== Riverpod Providers ==============

/// Provider for the Alexa service
final alexaServiceProvider = Provider<AlexaService>((ref) {
  return AlexaService();
});

/// Provider for watching Alexa link status
final alexaLinkStatusProvider = StreamProvider<AlexaLinkStatus>((ref) {
  final service = ref.watch(alexaServiceProvider);
  return service.watchLinkStatus();
});

/// Provider to check if Alexa is linked (one-time check)
final isAlexaLinkedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(alexaServiceProvider);
  return service.isAccountLinked();
});

/// Provider for Alexa integration info
final alexaIntegrationInfoProvider = FutureProvider<AlexaIntegrationInfo?>((ref) async {
  final service = ref.watch(alexaServiceProvider);
  return service.getIntegrationInfo();
});
