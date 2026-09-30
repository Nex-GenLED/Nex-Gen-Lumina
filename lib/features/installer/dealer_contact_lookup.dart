import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A dealer record's contact, as the installer wizard copies it onto the
/// customer's profile (`dealer_name`, `dealer_phone`, `dealer_email`).
class DealerContactSnapshot {
  const DealerContactSnapshot({this.name, this.phone, this.email});

  final String? name;
  final String? phone;
  final String? email;

  bool get isEmpty => name == null && phone == null && email == null;
}

String? _nonEmpty(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

/// Pure: the contact in a `/dealers` record, or null when it has none.
DealerContactSnapshot? dealerContactFromRecord(Map<String, dynamic>? data) {
  if (data == null) return null;
  final snap = DealerContactSnapshot(
    name: _nonEmpty(data['companyName']) ??
        _nonEmpty(data['businessName']) ??
        _nonEmpty(data['name']),
    phone: _nonEmpty(data['phone']),
    email: _nonEmpty(data['email'])?.toLowerCase(),
  );
  return snap.isEmpty ? null : snap;
}

/// Reads `/dealers/{dealerCode}` for the wizard's profile write.
///
/// A staff claim may `get` its own dealer's document by id
/// (firestore.rules `hasStaffClaim(dealerCode)`); it cannot run a query on
/// the collection, so a dealer record that is not keyed by its code is
/// invisible here (the two live records are not; the server functions
/// cover that case with a field query). Never throws: a failed read means
/// the profile gets no dealer contact and the customer sees Nex-Gen LED.
Future<DealerContactSnapshot?> readDealerContactForProvisioning(
  FirebaseFirestore firestore,
  String dealerCode,
) async {
  final code = dealerCode.trim();
  if (code.isEmpty) return null;
  try {
    final doc = await firestore
        .collection('dealers')
        .doc(code)
        .get()
        .timeout(const Duration(seconds: 8));
    return dealerContactFromRecord(doc.data());
  } catch (e) {
    debugPrint('Installer: dealer contact read skipped ($e)');
    return null;
  }
}
