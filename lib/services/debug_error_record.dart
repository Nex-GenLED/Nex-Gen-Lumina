// The `users/{uid}/debug_errors` document the app's uncaught-error sink
// writes (main.dart). Pure, so its shape is pinned by a test.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/app_version.dart';

/// Longest `error` / `stack` string a record carries.
const int kDebugErrorFieldCap = 3000;

/// The record for one uncaught [error].
///
/// #166: carries [appVersion] (default: this build's [kAppVersion]). Release
/// stacks are bare addresses; without the version a record cannot be matched
/// to the `.symbols` file of the build that threw.
Map<String, dynamic> debugErrorRecord({
  required Object error,
  required StackTrace? stack,
  required String context,
  required String platform,
  String appVersion = kAppVersion,
}) {
  final errStr = error.toString();
  final stackStr = stack?.toString() ?? '';
  String cap(String s) =>
      s.length > kDebugErrorFieldCap ? s.substring(0, kDebugErrorFieldCap) : s;
  return {
    'timestamp': FieldValue.serverTimestamp(),
    'context': context,
    'error_type': error.runtimeType.toString(),
    'error': cap(errStr),
    'stack': cap(stackStr),
    'app_version': appVersion,
    'platform': platform,
  };
}
