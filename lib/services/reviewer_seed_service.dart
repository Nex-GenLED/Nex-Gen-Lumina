import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Seeds a pre-configured reviewer account for App Store review.
///
/// The reviewer account uses [DemoWledRepository] so no real hardware
/// is required — the reviewer sees a fully functional demo experience.
class ReviewerSeedService {
  static const reviewerEmail = 'reviewer@nexgenled.com';
  static const reviewerUserId = 'reviewer-demo-account-001';

  /// Call from main.dart on app startup (debug + release).
  /// Creates the reviewer Firestore document if it doesn't already exist.
  static Future<void> ensureReviewerAccount() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(reviewerUserId)
          .get();
      if (doc.exists) return;

      // Create a fully pre-configured reviewer UserModel
      final reviewerModel = UserModel(
        id: reviewerUserId,
        email: reviewerEmail,
        displayName: 'Demo Home',
        ownerId: reviewerUserId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        installationId: 'reviewer-installation-001',
        installationRole: InstallationRole.primary,
        primaryUserId: reviewerUserId,
        linkedAt: DateTime.now(),
        welcomeCompleted: true,
        autopilotEnabled: true,
        sportsTeams: ['Chiefs', 'Royals'],
        sportsTeamPriority: ['Chiefs', 'Royals'],
        favoriteHolidays: ['Christmas', 'Halloween', '4th of July'],
        vibeLevel: 0.7,
        changeToleranceLevel: 3,
        autonomyLevel: 2,
        profileType: 'residential',
        weeklySchedulePreviewEnabled: true,
        autoDetectGameDays: true,
        preGameLighting: true,
        scoreCelebrations: true,
        timeZone: 'America/Chicago',
        // Custom roofline traced to match the stock demo home image
        // (assets/images/Demohomephoto.jpg). The house is multi-gabled:
        // left porch overhang → center upper peak → bay window bump →
        // garage roofline. Points are normalized 0-1 coordinates.
        rooflineMask: {
          'points': [
            {'x': 0.03, 'y': 0.38},  // left eave (porch overhang start)
            {'x': 0.15, 'y': 0.28},  // porch peak
            {'x': 0.22, 'y': 0.35},  // valley between porch and main
            {'x': 0.38, 'y': 0.08},  // center upper gable peak
            {'x': 0.52, 'y': 0.30},  // valley to right section
            {'x': 0.58, 'y': 0.22},  // bay window bump peak
            {'x': 0.65, 'y': 0.32},  // down to garage transition
            {'x': 0.78, 'y': 0.22},  // garage roofline peak
            {'x': 0.97, 'y': 0.35},  // far right eave
          ],
          'mask_height': 0.40,
          'is_manually_drawn': true,
        },
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(reviewerUserId)
          .set(UserService.sanitizeForFirestore(reviewerModel.toJson()));

      // Create reviewer installation document
      await FirebaseFirestore.instance
          .collection('installations')
          .doc('reviewer-installation-001')
          .set({
        'id': 'reviewer-installation-001',
        'primaryUserId': reviewerUserId,
        'dealerCode': '00',
        'installerCode': '00',
        'installerName': 'Nex-Gen LED',
        'dealerCompanyName': 'Nex-Gen LED LLC',
        'installedAt': Timestamp.now(),
        'warrantyExpires': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 365 * 5))),
        'controllerSerials': ['DEMO-CTRL-001'],
        'address': '123 Demo Street',
        'city': 'Kansas City',
        'state': 'MO',
        'zipCode': '64108',
        'maxSubUsers': 5,
        'siteMode': 'residential',
        'isActive': true,
        'systemConfig': {
          'linkedControllerIds': ['DEMO-CTRL-001'],
        },
      });

      debugPrint('ReviewerSeedService: Reviewer account created');
    } catch (e) {
      debugPrint('ReviewerSeedService: Failed to seed reviewer account: $e');
    }
  }
}
