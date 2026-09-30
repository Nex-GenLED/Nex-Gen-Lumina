// +110 package G, follow-up 4 — the dealer's contact lives on the profile.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/auth/support_contact.dart';
import 'package:nexgen_command/features/installer/dealer_contact_lookup.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/models/user_role.dart';

import 'setup_auth_fixtures.dart';

UserModel _profile({
  String? dealerName,
  String? dealerPhone,
  String? dealerEmail,
}) =>
    UserModel(
      id: kTestUid,
      email: kTestEmail,
      displayName: 'Pat',
      ownerId: kTestUid,
      createdAt: DateTime.utc(2026, 9, 29),
      updatedAt: DateTime.utc(2026, 9, 29),
      installationRole: InstallationRole.primary,
      dealerCode: '07',
      dealerName: dealerName,
      dealerPhone: dealerPhone,
      dealerEmail: dealerEmail,
    );

void main() {
  group('UserModel dealer contact', () {
    test('round-trips dealer_name / dealer_phone / dealer_email', () {
      final json = _profile(
        dealerName: 'Bright Homes LED',
        dealerPhone: '(555) 010-0100',
        dealerEmail: 'Hello@Example.com',
      ).toJson();
      expect(json['dealer_name'], 'Bright Homes LED');
      expect(json['dealer_phone'], '(555) 010-0100');
      expect(json['dealer_email'], 'hello@example.com',
          reason: 'validateEmail lower-cases');

      final back = UserModel.fromJson(json);
      expect(back.dealerName, 'Bright Homes LED');
      expect(back.dealerPhone, '(555) 010-0100');
      expect(back.dealerEmail, 'hello@example.com');
    });

    test('absent values are absent keys, never empty strings', () {
      final json = _profile(dealerName: '  ', dealerPhone: '').toJson();
      expect(json.containsKey('dealer_name'), isFalse);
      expect(json.containsKey('dealer_phone'), isFalse);
      expect(json.containsKey('dealer_email'), isFalse);
      expect(json['dealer_code'], '07');
    });

    test("a dealer's own-domain email is kept (no nex-genled.com allow-list)",
        () {
      expect(_profile(dealerEmail: 'sales@brighthomes.example').dealerEmail,
          'sales@brighthomes.example');
      expect(_profile(dealerEmail: 'not an email').dealerEmail, isNull);
    });
  });

  group('dealerContactFromProfile', () {
    test('needs a phone or an email; the name is optional', () {
      expect(dealerContactFromProfile(null), isNull);
      expect(dealerContactFromProfile(_profile(dealerName: 'Name only')),
          isNull);
      final c = dealerContactFromProfile(_profile(dealerPhone: '555'))!;
      expect(c.isDealer, isTrue);
      expect(c.name, 'Your Nex-Gen dealer');
      expect(c.phone, '555');
      expect(c.email, isNull);
    });
  });

  group('readDealerContactForProvisioning (installer wizard)', () {
    test('reads the record keyed by the dealer code', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('dealers').doc('07').set({
        'dealerCode': '07',
        'name': 'Pat',
        'companyName': 'Bright Homes LED',
        'phone': '(555) 010-0100',
        'email': 'Hello@Example.com',
      });
      final c = (await readDealerContactForProvisioning(fs, '07'))!;
      expect(c.name, 'Bright Homes LED');
      expect(c.phone, '(555) 010-0100');
      expect(c.email, 'hello@example.com');
    });

    test('a record with only a name has no contact; a missing record is null',
        () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('dealers').doc('02').set({'companyName': 'Quiet'});
      final c = (await readDealerContactForProvisioning(fs, '02'))!;
      expect(c.name, 'Quiet');
      expect(c.phone, isNull);
      expect(c.email, isNull);
      expect(await readDealerContactForProvisioning(fs, '99'), isNull);
      expect(await readDealerContactForProvisioning(fs, ''), isNull);
    });

    test('a record keyed by something other than its code is not found '
        '(the live id mismatch; the server functions cover it)', () async {
      final fs = FakeFirebaseFirestore();
      await fs.collection('dealers').doc('NXG-something').set({
        'dealerCode': '01',
        'phone': '555',
      });
      expect(await readDealerContactForProvisioning(fs, '01'), isNull);
    });
  });

  test('the corporate constants are the owner-confirmed values', () {
    expect(kNexGenCorporatePhone, '816-408-0177');
    expect(kNexGenCorporateEmail, 'general@nex-genled.com');
    expect(kNexGenCorporateContact.telUri.toString(), 'tel:8164080177');
    expect(kNexGenCorporateContact.mailtoUri.toString(),
        'mailto:general@nex-genled.com');
  });
}
