import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_admin_providers.dart';
import 'package:nexgen_command/models/dealer_code.dart';

/// C1 — dealer code format is canonical 2-digit.
///
/// The reachable Add-Dealer UI used to mint `NXG-DEALER-{STATE}-{###}`, a
/// format no consumer can use: the PIN system composes
/// `fullPin = dealerCode + installerCode` (installer_providers.dart:82) and
/// requires exactly 4 digits (client installer_providers.dart:168, server
/// staffAuth.ts:112 `PIN_REGEX = /^\d{4,6}$/`). A prefixed dealer could never
/// have an installer who could sign in.
void main() {
  group('DealerCode.isValid', () {
    test('accepts the canonical 2-digit form', () {
      expect(DealerCode.isValid('00'), isTrue);
      expect(DealerCode.isValid('01'), isTrue);
      expect(DealerCode.isValid('55'), isTrue);
      expect(DealerCode.isValid('99'), isTrue);
    });

    test('rejects the legacy prefixed form that shipped live', () {
      expect(DealerCode.isValid('NXG-DEALER-MISSOURI-001'), isFalse);
      expect(DealerCode.isValid('NXG-DEALER-TX-001'), isFalse);
    });

    test('rejects near-misses that would break fullPin composition', () {
      expect(DealerCode.isValid('1'), isFalse, reason: '1 digit → 3-char PIN');
      expect(DealerCode.isValid('123'), isFalse, reason: '3 digits → 5-char PIN');
      expect(DealerCode.isValid('5a'), isFalse, reason: 'non-digit fails PIN_REGEX');
      expect(DealerCode.isValid(''), isFalse);
      expect(DealerCode.isValid(null), isFalse);
      expect(DealerCode.isValid(' 55'), isFalse);
      expect(DealerCode.isValid('55 '), isFalse);
    });
  });

  group('DealerCode.isAllocatable', () {
    test('the reserved master code is valid but NOT allocatable', () {
      // staffAuth.ts:119 MASTER_DEALER_CODE = '55'. Handing it to a real
      // dealer would give every master-PIN session a matching dealerCode
      // claim against that dealer's data.
      expect(DealerCode.isValid(DealerCode.masterReserved), isTrue);
      expect(DealerCode.isAllocatable(DealerCode.masterReserved), isFalse);
    });

    test('ordinary codes are allocatable', () {
      expect(DealerCode.isAllocatable('01'), isTrue);
      expect(DealerCode.isAllocatable('56'), isTrue);
    });
  });

  group('DealerCode.validate', () {
    test('returns the code when canonical', () {
      expect(DealerCode.validate('07'), '07');
    });

    test('throws ArgumentError on the legacy prefixed form', () {
      expect(
        () => DealerCode.validate('NXG-DEALER-MISSOURI-001'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on null/empty', () {
      expect(() => DealerCode.validate(null), throwsA(isA<ArgumentError>()));
      expect(() => DealerCode.validate(''), throwsA(isA<ArgumentError>()));
    });
  });

  group('CorporateAdminService.generateDealerCode', () {
    test('mints a canonical 2-digit code on an empty collection', () async {
      final db = FakeFirebaseFirestore();
      final svc = CorporateAdminService(db);

      final code = await svc.generateDealerCode(stateCode: 'MO');

      expect(DealerCode.isValid(code), isTrue,
          reason: 'must be canonical, not NXG-DEALER-MO-001');
      expect(code, '01');
    });

    test('does NOT encode the territory into the code', () async {
      final db = FakeFirebaseFirestore();
      final svc = CorporateAdminService(db);

      final code = await svc.generateDealerCode(stateCode: 'MISSOURI');

      expect(code.contains('MISSOURI'), isFalse);
      expect(code.contains('NXG'), isFalse);
      expect(DealerCode.isValid(code), isTrue);
    });

    test('tolerates the live legacy prefixed doc instead of throwing', () async {
      // The rival allocator (admin_providers.dart) int.parse'd the highest
      // code and would throw FormatException here. This is the exact doc
      // that exists in production today.
      final db = FakeFirebaseFirestore();
      await db.collection('dealers').doc('NXG-DEALER-MISSOURI-001').set({
        'dealerCode': 'NXG-DEALER-MISSOURI-001',
        'isActive': true,
      });
      final svc = CorporateAdminService(db);

      final code = await svc.generateDealerCode();

      expect(code, '01', reason: 'legacy doc is skipped, not parsed');
    });

    test('gap-fills the lowest free code', () async {
      final db = FakeFirebaseFirestore();
      for (final c in ['01', '02', '04']) {
        await db.collection('dealers').doc(c).set({'dealerCode': c});
      }
      final svc = CorporateAdminService(db);

      expect(await svc.generateDealerCode(), '03');
    });

    test('never allocates the reserved master code 55', () async {
      final db = FakeFirebaseFirestore();
      // Fill 01..54 so the naive "next" would be 55.
      for (var i = 1; i <= 54; i++) {
        final c = i.toString().padLeft(2, '0');
        await db.collection('dealers').doc(c).set({'dealerCode': c});
      }
      final svc = CorporateAdminService(db);

      expect(await svc.generateDealerCode(), '56',
          reason: '55 is MASTER_DEALER_CODE and must be skipped');
    });

    test('throws StateError when the 2-digit space is exhausted', () async {
      final db = FakeFirebaseFirestore();
      for (var i = 1; i <= 99; i++) {
        final c = i.toString().padLeft(2, '0');
        await db.collection('dealers').doc(c).set({'dealerCode': c});
      }
      final svc = CorporateAdminService(db);

      expect(() => svc.generateDealerCode(), throwsA(isA<StateError>()));
    });
  });

  group('CorporateAdminService.createDealer', () {
    test('persists a canonical code as BOTH doc id and dealerCode field',
        () async {
      final db = FakeFirebaseFirestore();
      final svc = CorporateAdminService(db);

      await svc.createDealer(
        businessName: 'Nex-Gen Vacaville',
        contactEmail: 'v@example.com',
        contactPhone: '555-0100',
        territory: 'CA',
      );

      final docs = await db.collection('dealers').get();
      expect(docs.docs, hasLength(1));
      final d = docs.docs.first;
      expect(DealerCode.isValid(d.id), isTrue);
      expect(d.data()['dealerCode'], d.id);
      expect(d.data()['territory'], 'CA',
          reason: 'territory persists as a field, not inside the code');
      expect(d.data()['isActive'], isTrue);
    });

    test('a second dealer gets a distinct canonical code (the 2-dealer case)',
        () async {
      final db = FakeFirebaseFirestore();
      final svc = CorporateAdminService(db);

      await svc.createDealer(
        businessName: 'Nex-Gen Vacaville',
        contactEmail: 'v@example.com',
        contactPhone: '555-0100',
        territory: 'CA',
      );
      await svc.createDealer(
        businessName: 'Nex-Gen Michigan',
        contactEmail: 'm@example.com',
        contactPhone: '555-0200',
        territory: 'MI',
      );

      final docs = await db.collection('dealers').get();
      final codes = docs.docs.map((d) => d.id).toList()..sort();
      expect(codes, ['01', '02']);
      for (final c in codes) {
        expect(DealerCode.isValid(c), isTrue);
      }
    });

    test('the minted code composes a valid 4-digit staff PIN', () async {
      // The whole point: dealerCode + installerCode must be 4 digits and
      // survive staffAuth.ts PIN_REGEX = /^\d{4,6}$/.
      final db = FakeFirebaseFirestore();
      final svc = CorporateAdminService(db);

      await svc.createDealer(
        businessName: 'Nex-Gen Vacaville',
        contactEmail: 'v@example.com',
        contactPhone: '555-0100',
        territory: 'CA',
      );

      final code = (await db.collection('dealers').get()).docs.first.id;
      final fullPin = '$code' '01'; // dealerCode + installerCode
      expect(fullPin.length, 4);
      expect(RegExp(r'^\d{4,6}$').hasMatch(fullPin), isTrue);
    });
  });
}
