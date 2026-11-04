// "Request Free Consultation" on the demo completion screen (2026-11-02).
//
// On build-121 a demo session with no captured lead — the App Review code
// skips the profile step, so the reviewer's session is always one — made
// _submitConsultationRequest throw Exception('No lead data found'), and the
// catch block showed the raw text "Error submitting request: Exception: No
// lead data found". Any other failure showed the raw exception the same way.
//
// Contract pinned here (fail-before on build-121, pass-after):
//   * no lead → a plain line that says contact details are missing, with an
//     "Add details" action, recorded in the error sink; no raw exception text;
//   * a failed write → a plain line with a "Retry" action, recorded with the
//     real exception; no raw exception text;
//   * a successful write → the existing "Request Submitted!" dialog.
//
// The demo runs unauthenticated, so the sink record only lands when someone
// is signed in; the screen also logs a demo analytics event (the demo's own,
// unauthenticated telemetry) so the failure is visible either way.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_completion_screen.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/services/error_sink.dart';

class _LeadServiceSpy extends DemoLeadService {
  _LeadServiceSpy({this.failWith}) : super(firestore: FakeFirebaseFirestore());

  final Object? failWith;
  final List<String> contactRequestsFor = [];
  final List<String> consultationRequestedFor = [];
  final List<String> analyticsEvents = [];

  @override
  Future<void> logContactRequest(String leadId, ContactRequest request) async {
    if (failWith != null) throw failWith!;
    contactRequestsFor.add(leadId);
  }

  @override
  Future<void> logConsultationRequested(String leadId) async {
    consultationRequestedFor.add(leadId);
  }

  @override
  Future<void> logAnalyticsEvent({
    required String event,
    String? leadId,
    Map<String, dynamic>? data,
  }) async {
    analyticsEvents.add(event);
  }
}

class _SinkRecorder {
  final List<({Object error, String context})> records = [];
  Future<void> call({
    required Object error,
    required StackTrace? stack,
    required String context,
  }) async {
    records.add((error: error, context: context));
  }
}

DemoLead _lead() => DemoLead(
      id: 'lead-test-1',
      name: 'Demo Home',
      email: 'demo@example.com',
      phone: '555-0100',
      zipCode: '64101',
      capturedAt: DateTime.utc(2026, 11, 2),
    );

Future<void> _pump(
  WidgetTester tester, {
  required DemoLead? lead,
  required _LeadServiceSpy service,
  required _SinkRecorder sink,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        demoLeadProvider.overrideWith((ref) => lead),
        demoLeadServiceProvider.overrideWithValue(service),
        errorReporterProvider.overrideWithValue(sink.call),
      ],
      child: const MaterialApp(home: DemoCompletionScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps through to the contact form, picks a method and a time, submits.
Future<void> _requestConsultation(WidgetTester tester) async {
  await tester.tap(find.text('Request Free Consultation'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(ContactMethod.phone.displayName));
  await tester.pump();
  await tester.tap(find.text(ContactTime.morning.displayName));
  await tester.pump();
  await tester.ensureVisible(find.text('Submit Request'));
  await tester.tap(find.text('Submit Request'));
  await tester.pump(); // the SnackBar / dialog is scheduled
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('no lead in the session → plain message with an "Add details" action, '
      'recorded; no raw exception text', (tester) async {
    final service = _LeadServiceSpy();
    final sink = _SinkRecorder();
    await _pump(tester, lead: null, service: service, sink: sink);

    await _requestConsultation(tester);

    expect(find.textContaining('Exception'), findsNothing,
        reason: 'raw exception text must never reach the user');
    expect(find.textContaining('No lead data found'), findsNothing);
    expect(find.textContaining("don't have your contact details"), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Add details'), findsOneWidget);
    expect(service.contactRequestsFor, isEmpty, reason: 'nothing to write without a lead');
    expect(sink.records, hasLength(1));
    expect(sink.records.single.context, 'demoConsultation/no_lead');
    expect(service.analyticsEvents, contains('consultation_request_failed'));
  });

  testWidgets('the write fails → plain message with a "Retry" action, the real error recorded; '
      'no raw exception text', (tester) async {
    final service = _LeadServiceSpy(failWith: StateError('permission-denied'));
    final sink = _SinkRecorder();
    await _pump(tester, lead: _lead(), service: service, sink: sink);

    await _requestConsultation(tester);

    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('permission-denied'), findsNothing,
        reason: 'the exception text is for the record, not the user');
    expect(find.textContaining("Couldn't send your request"), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    expect(sink.records, hasLength(1));
    expect(sink.records.single.context, 'demoConsultation/submit');
    expect(sink.records.single.error, isA<StateError>());
    expect(service.analyticsEvents, contains('consultation_request_failed'));
  });

  testWidgets('"Retry" re-submits the same request', (tester) async {
    final service = _LeadServiceSpy(failWith: StateError('transient'));
    final sink = _SinkRecorder();
    await _pump(tester, lead: _lead(), service: service, sink: sink);
    await _requestConsultation(tester);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sink.records, hasLength(2), reason: 'the retry went through the same path');
  });

  testWidgets('the write succeeds → the existing success dialog, nothing recorded', (tester) async {
    final service = _LeadServiceSpy();
    final sink = _SinkRecorder();
    await _pump(tester, lead: _lead(), service: service, sink: sink);

    await _requestConsultation(tester);
    // Not pumpAndSettle: the submit spinner keeps animating while the
    // success dialog is open (the submitting flag clears after the dialog).
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Request Submitted!'), findsOneWidget);
    expect(service.contactRequestsFor, ['lead-test-1']);
    expect(service.consultationRequestedFor, ['lead-test-1']);
    expect(sink.records, isEmpty);
    expect(find.textContaining('Exception'), findsNothing);
  });
}
