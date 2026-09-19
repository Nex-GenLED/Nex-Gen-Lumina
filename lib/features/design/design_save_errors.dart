import 'package:cloud_firestore/cloud_firestore.dart';

/// Turns a failed design save into a sentence the user can act on.
///
/// The paint editor's Save was `try { … } finally { … }` with NO catch, and
/// `DesignService` rethrows — so any Firestore error escaped as an unhandled
/// async exception and the UI showed nothing at all: the buttons greyed,
/// came back, and the design simply was not in My Designs
/// (design-studio-audit-2026-09-19 F6).
///
/// Pure so it can be tested without a widget. [isEdit] = the editor was opened
/// on an existing design (an update), not a new one (a create).
String describeDesignSaveError(Object error, {required bool isEdit}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return "You don't have permission to save designs on this account, so "
            'nothing was saved. If you are working on a customer\'s account, '
            'ask them to save it from their own sign-in.';
      case 'not-found':
        // `.update()` throws on a missing doc — the design was deleted
        // somewhere else while it was open here.
        return isEdit
            ? 'This design was deleted on another device, so it could not be '
                'updated. Nothing was saved — copy your changes into a new '
                'design to keep them.'
            : "Couldn't save — the save location no longer exists.";
      case 'unavailable':
      case 'deadline-exceeded':
        return "Couldn't reach the server, so nothing was saved. Check your "
            'connection and try again.';
      case 'resource-exhausted':
        return 'This design is too large to save as it is. Nothing was saved.';
    }
  }
  return "Couldn't save this design — nothing was saved. Please try again.";
}
