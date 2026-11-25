import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';

/// Existing-customer search: each of the three /users queries is a prefix
/// range `[prefix, prefix + U+F8FF)` inside the installer's own dealer.
///
/// The upper bound is the private-use character U+F8FF, which sorts after
/// every character a name, email or address will contain. In source it is
/// invisible when typed as a raw character, which is how it came to be
/// read as `end = '$trimmed'` (an empty range that matches nothing). These
/// tests pin the behaviour so the bound cannot silently collapse: if `end`
/// ever equals the prefix, every search below returns nothing.
///
/// The `dealer_code ==` filter is what the /users read rule needs for a
/// sales or installer claim; another dealer's customers must never appear.
void main() {
  Future<FakeFirebaseFirestore> seeded() async {
    final db = FakeFirebaseFirestore();
    Future<void> user(String uid, String dealerCode, String name,
            String email, String address) =>
        db.collection('users').doc(uid).set({
          'owner_id': uid,
          'dealer_code': dealerCode,
          'display_name': name,
          'email': email,
          'address': address,
        });
    await user('u1', '01', 'John Smith', 'john@example.com', '12 Elm St');
    await user('u2', '01', 'Joanne Lee', 'joanne@example.com', '40 Oak Ave');
    await user('u3', '02', 'Jodie Xu', 'jodie@example.com', '12 Elm Ct');
    await user('u4', '01', 'Bob Ray', 'bob@example.com', '9 Pine Rd');
    return db;
  }

  test('a name prefix matches every customer whose name starts with it',
      () async {
    final db = await seeded();
    final hits = await searchCustomers('Jo', dealerCode: '01', firestore: db);
    expect(hits.map((h) => h.uid), ['u2', 'u1'],
        reason: 'name-sorted: Joanne Lee, John Smith');
  });

  test('another dealer\'s customers never appear', () async {
    final db = await seeded();
    final hits = await searchCustomers('Jo', dealerCode: '01', firestore: db);
    expect(hits.map((h) => h.uid), isNot(contains('u3')));
    final other = await searchCustomers('Jo', dealerCode: '02', firestore: db);
    expect(other.map((h) => h.uid), ['u3']);
  });

  test('a full value is its own prefix', () async {
    final db = await seeded();
    final hits =
        await searchCustomers('John Smith', dealerCode: '01', firestore: db);
    expect(hits.map((h) => h.uid), ['u1']);
  });

  test('email and address prefixes match too', () async {
    final db = await seeded();
    final byEmail =
        await searchCustomers('bob@', dealerCode: '01', firestore: db);
    expect(byEmail.map((h) => h.uid), ['u4']);
    final byAddress =
        await searchCustomers('12 Elm', dealerCode: '01', firestore: db);
    expect(byAddress.map((h) => h.uid), ['u1']);
  });

  test('surrounding whitespace is ignored', () async {
    final db = await seeded();
    final hits = await searchCustomers('  Joanne ', dealerCode: '01', firestore: db);
    expect(hits.map((h) => h.uid), ['u2']);
  });

  test('empty query or empty dealer code returns nothing', () async {
    final db = await seeded();
    expect(await searchCustomers('  ', dealerCode: '01', firestore: db), isEmpty);
    expect(await searchCustomers('Jo', dealerCode: '', firestore: db), isEmpty);
  });
}
