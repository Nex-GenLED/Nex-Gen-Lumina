// lib/services/error_sink.dart
//
// The app's error sink: one place that writes a capped record to
// users/{uid}/debug_errors/{autoId} (shape: debug_error_record.dart).
//
// It was private to main.dart and reachable only from the UNCAUGHT-error
// hooks (FlutterError.onError / PlatformDispatcher.onError). A handled
// failure — one a catch block turned into a state or a null return — never
// reached it, so a Start that failed before its first request left no record
// anywhere (Sync Start window, 2026-11-02). It is now callable from handled
// paths too; the first caller is NeighborhoodNotifier.broadcastSync.
//
// Must never throw. Sink failures are swallowed.

import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_error_record.dart';

/// Signature shared by the real sink and test recorders.
typedef ErrorReporter = Future<void> Function({
  required Object error,
  required StackTrace? stack,
  required String context,
});

/// Re-entry guard: if the sink itself throws (e.g. Firestore unreachable),
/// we must not recurse into ourselves and feedback-loop.
bool _errorSinkActive = false;

/// Writes one record for [error] under [context]. #84 hardening.
///
/// Without this the app has no error reporting surface — Crashlytics is not
/// readable from the owner's machine and TestFlight crash logs aren't
/// accessible from the device. The record is readable from the Firestore
/// console.
Future<void> reportErrorToSink({
  required Object error,
  required StackTrace? stack,
  required String context,
}) async {
  if (_errorSinkActive) return;
  _errorSinkActive = true;
  try {
    debugPrint('🛑 ERROR [$context]: $error\n$stack');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('debug_errors')
        .add(debugErrorRecord(
          error: error,
          stack: stack,
          context: context,
          platform: Platform.isIOS
              ? 'ios'
              : Platform.isAndroid
                  ? 'android'
                  : 'other',
        ));
  } catch (_) {
    // Sink must never crash the app. Swallow.
  } finally {
    _errorSinkActive = false;
  }
}

/// The sink as a dependency, so a handled path can be tested with a recorder
/// instead of a live Firestore.
final errorReporterProvider = Provider<ErrorReporter>((ref) => reportErrorToSink);
