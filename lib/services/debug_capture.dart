import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

bool _bug84CaptureActive = false;

Future<void> captureBug84({
  required String marker,
  required String step,
  String? path,
  String? valueType,
  String? errorType,
  String? errorMessage,
  String? stackTrace,
}) async {
  if (_bug84CaptureActive) return;
  _bug84CaptureActive = true;
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    const cap = 3000;
    String? trunc(String? s) =>
        s == null ? null : (s.length > cap ? s.substring(0, cap) : s);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('debug_errors')
        .add({
      'marker': marker,
      'step': step,
      if (path != null) 'path': path,
      if (valueType != null) 'valueType': valueType,
      if (errorType != null) 'errorType': errorType,
      if (errorMessage != null) 'errorMessage': trunc(errorMessage),
      if (stackTrace != null) 'stackTrace': trunc(stackTrace),
      'ts': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('captureBug84 sink failed: $e');
  } finally {
    _bug84CaptureActive = false;
  }
}
