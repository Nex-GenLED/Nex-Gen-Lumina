import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';

/// Service for managing demo leads in Firestore.
///
/// Handles:
/// - Storing lead data in `/demo_leads` collection
/// - Logging contact requests
/// - Triggering email notifications (via Cloud Functions)
class DemoLeadService {
  final FirebaseFirestore _firestore;

  DemoLeadService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Reference to the demo_leads collection.
  CollectionReference<Map<String, dynamic>> get _leadsCollection =>
      _firestore.collection('demo_leads');

  /// Reference to the demo_analytics collection.
  CollectionReference<Map<String, dynamic>> get _analyticsCollection =>
      _firestore.collection('demo_analytics');

  /// Submit a new demo lead.
  ///
  /// Creates a new document in Firestore and triggers email notification.
  /// Returns the lead ID.
  Future<String> submitLead(DemoLead lead) async {
    try {
      // Generate a new document ID if not provided
      final docRef = lead.id.isEmpty
          ? _leadsCollection.doc()
          : _leadsCollection.doc(lead.id);

      final leadWithId = lead.copyWith(id: docRef.id);
      await docRef.set(leadWithId.toJson());

      // Trigger email notification via Cloud Function
      // The Cloud Function listens to new documents in demo_leads
      // and sends an email to the configured recipient
      await _triggerEmailNotification(leadWithId);

      if (kDebugMode) {
        print('DemoLeadService: Lead submitted with ID: ${docRef.id}');
      }

      return docRef.id;
    } catch (e) {
      if (kDebugMode) {
        print('DemoLeadService: Error submitting lead: $e');
      }
      rethrow;
    }
  }

  /// Update an existing lead.
  Future<void> updateLead(DemoLead lead) async {
    try {
      await _leadsCollection.doc(lead.id).update(lead.toJson());
    } catch (e) {
      if (kDebugMode) {
        print('DemoLeadService: Error updating lead: $e');
      }
      rethrow;
    }
  }

  /// Mark a lead as demo completed.
  Future<void> markDemoCompleted(String leadId, List<String> patternsViewed) async {
    try {
      await _leadsCollection.doc(leadId).update({
        'demoCompleted': true,
        'patternsViewed': patternsViewed,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('DemoLeadService: Error marking demo completed: $e');
      }
      rethrow;
    }
  }

  /// Log a contact request for a lead.
  Future<void> logContactRequest(
    String leadId,
    ContactRequest request,
  ) async {
    try {
      await _leadsCollection.doc(leadId).update({
        'contactRequests': FieldValue.arrayUnion([request.toJson()]),
      });

      // Also trigger an email notification for the contact request
      await _triggerContactRequestNotification(leadId, request);

      if (kDebugMode) {
        print('DemoLeadService: Contact request logged for lead: $leadId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('DemoLeadService: Error logging contact request: $e');
      }
      rethrow;
    }
  }

  /// Get a lead by ID.
  Future<DemoLead?> getLead(String leadId) async {
    try {
      final doc = await _leadsCollection.doc(leadId).get();
      if (!doc.exists) return null;
      return DemoLead.fromJson(doc.data()!);
    } catch (e) {
      if (kDebugMode) {
        print('DemoLeadService: Error getting lead: $e');
      }
      return null;
    }
  }

  /// Trigger email notification for a new lead.
  ///
  /// This writes to a special collection that a Cloud Function monitors
  /// to send emails. The Cloud Function handles the actual email sending
  /// to keep the email address secure and not exposed in the app.
  Future<void> _triggerEmailNotification(DemoLead lead) async {
    try {
      await _firestore.collection('email_notifications').add({
        'type': 'new_demo_lead',
        'leadId': lead.id,
        'leadName': lead.name ?? 'Not provided',
        'leadEmail': lead.email,
        'leadPhone': lead.phone,
        'leadZipCode': lead.zipCode,
        'leadHomeType': lead.homeType?.displayName ?? 'Not specified',
        'leadReferralSource': lead.referralSource?.displayName ?? 'Not specified',
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      // Don't fail the lead submission if email notification fails
      if (kDebugMode) {
        print('DemoLeadService: Error triggering email notification: $e');
      }
    }
  }

  /// Trigger email notification for a contact request.
  Future<void> _triggerContactRequestNotification(
    String leadId,
    ContactRequest request,
  ) async {
    try {
      // Get the lead details for the email
      final lead = await getLead(leadId);
      if (lead == null) return;

      await _firestore.collection('email_notifications').add({
        'type': 'consultation_request',
        'leadId': leadId,
        'leadName': lead.name ?? 'Not provided',
        'leadEmail': lead.email,
        'leadPhone': lead.phone,
        'leadZipCode': lead.zipCode,
        'preferredContactMethod': request.method.displayName,
        'preferredContactTime': request.preferredTime.displayName,
        'notes': request.notes ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      // Don't fail the contact request if email notification fails
      if (kDebugMode) {
        print('DemoLeadService: Error triggering contact request notification: $e');
      }
    }
  }

  // ===========================================================================
  // Analytics Methods
  // ===========================================================================

  /// Log a demo analytics event.
  Future<void> logAnalyticsEvent({
    required String event,
    String? leadId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _analyticsCollection.add({
        'event': event,
        if (leadId != null) 'leadId': leadId,
        if (data != null) ...data,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Don't fail on analytics errors
      if (kDebugMode) {
        print('DemoLeadService: Error logging analytics: $e');
      }
    }
  }

  /// Log demo start event.
  Future<void> logDemoStart() async {
    await logAnalyticsEvent(event: 'demo_start');
  }

  /// Log step completion event.
  Future<void> logStepCompleted(
    String leadId,
    DemoStep step,
    int durationSeconds,
  ) async {
    await logAnalyticsEvent(
      event: 'step_completed',
      leadId: leadId,
      data: {
        'step': step.name,
        'durationSeconds': durationSeconds,
      },
    );
  }

  /// Log pattern viewed event.
  Future<void> logPatternViewed(String leadId, String patternId) async {
    await logAnalyticsEvent(
      event: 'pattern_viewed',
      leadId: leadId,
      data: {'patternId': patternId},
    );
  }

  /// Log demo completion event.
  Future<void> logDemoCompleted(String leadId) async {
    await logAnalyticsEvent(
      event: 'demo_completed',
      leadId: leadId,
    );
  }

  /// Log consultation request event.
  Future<void> logConsultationRequested(String leadId) async {
    await logAnalyticsEvent(
      event: 'consultation_requested',
      leadId: leadId,
    );
  }

  /// Log account created from demo event.
  Future<void> logAccountCreated(String leadId, String userId) async {
    await logAnalyticsEvent(
      event: 'account_created',
      leadId: leadId,
      data: {'userId': userId},
    );
  }
}

/// Provider for the demo lead service.
final demoLeadServiceProvider = Provider<DemoLeadService>((ref) {
  return DemoLeadService();
});
