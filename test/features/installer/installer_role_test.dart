import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// C4 — InstallerInfo.role (the SAFE half).
///
/// mintStaffToken rejects any installers doc whose `role` !== roleForMode(mode):
///
///   const docRole = data.role as string | undefined;
///   if (docRole !== roleForMode(mode)) return null;   // staffAuth.ts:356-357
///
/// A missing `role` is a mismatch, so every installer the admin UI created was
/// permanently unable to sign in. toMap() must emit it.
///
/// The wire values MUST match StaffRole (staffAuth.ts:148) exactly — the
/// server compares with a strict !==.
void main() {
  group('InstallerRole wire values match staffAuth.ts StaffRole', () {
    test('exact strings the server compares against', () {
      expect(InstallerRole.salesperson.wire, 'salesperson');
      expect(InstallerRole.installer.wire, 'installer');
      expect(InstallerRole.admin.wire, 'admin');
    });

    test("'owner' is NOT an installer role (master PIN only)", () {
      // staffAuth.ts:212 — owner is minted only from master_corporate_pin,
      // never from an installers doc.
      expect(
        InstallerRole.values.map((r) => r.wire),
        isNot(contains('owner')),
      );
      expect(InstallerRole.values, hasLength(3));
    });
  });

  group('toMap emits role — the C4 fix', () {
    test('role is present (without it the doc can never authenticate)', () {
      final info = InstallerInfo(
        installerCode: '01',
        dealerCode: '56',
        name: 'Pat Installer',
      );
      final map = info.toMap();

      expect(map.containsKey('role'), isTrue,
          reason: 'staffAuth.ts:357 rejects a doc with no role');
      expect(map['role'], 'installer');
    });

    test('defaults to installer — the least-privileged role', () {
      final info = InstallerInfo(
        installerCode: '01',
        dealerCode: '56',
        name: 'Pat',
      );
      expect(info.role, InstallerRole.installer);
    });

    // NOTE on round-tripping: toMap() emits FieldValue.serverTimestamp() for
    // a null registeredAt, and fromMap casts registeredAt to Timestamp? — so
    // fromMap(toMap()) throws unless registeredAt is set. That is a test
    // artifact, not a production path: fromMap always reads a Firestore
    // snapshot, where the sentinel has already resolved to a real Timestamp.
    // These tests therefore pin registeredAt explicitly.
    test('an explicit admin role round-trips', () {
      final info = InstallerInfo(
        installerCode: '20',
        dealerCode: '55',
        name: 'Admin Jones',
        role: InstallerRole.admin,
        registeredAt: DateTime.utc(2026, 1, 1),
      );
      expect(info.toMap()['role'], 'admin');
      expect(InstallerInfo.fromMap(info.toMap()).role, InstallerRole.admin);
    });

    test('a salesperson role round-trips', () {
      final info = InstallerInfo(
        installerCode: '30',
        dealerCode: '55',
        name: 'Sam Sales',
        role: InstallerRole.salesperson,
        registeredAt: DateTime.utc(2026, 1, 1),
      );
      expect(info.toMap()['role'], 'salesperson');
      expect(
        InstallerInfo.fromMap(info.toMap()).role,
        InstallerRole.salesperson,
      );
    });

    test('toMap still emits fullPin composed from the 2-digit halves', () {
      final map = InstallerInfo(
        installerCode: '01',
        dealerCode: '56',
        name: 'Pat',
      ).toMap();
      expect(map['fullPin'], '5601');
      expect((map['fullPin'] as String).length, 4);
    });
  });

  group('fromMap is tolerant of legacy docs', () {
    test('a legacy doc with NO role falls back to installer, not a throw', () {
      // Every doc written by the admin UI before C4 looks like this.
      final legacy = {
        'installerCode': '01',
        'dealerCode': '55',
        'fullPin': '5501',
        'name': 'Legacy Installer',
        'isActive': true,
      };
      final info = InstallerInfo.fromMap(legacy);

      expect(info.role, InstallerRole.installer);
      expect(info.name, 'Legacy Installer');
    });

    test('an unrecognized role falls back rather than throwing', () {
      final info = InstallerInfo.fromMap({
        'installerCode': '01',
        'dealerCode': '55',
        'role': 'wizard',
        'name': 'Odd',
      });
      expect(info.role, InstallerRole.installer);
    });

    test('a non-string role falls back rather than throwing', () {
      final info = InstallerInfo.fromMap({
        'installerCode': '01',
        'dealerCode': '55',
        'role': 42,
        'name': 'Odd',
      });
      expect(info.role, InstallerRole.installer);
    });

    test('parseRole handles null', () {
      expect(InstallerInfo.parseRole(null), InstallerRole.installer);
    });
  });

  group('canAuthenticate mirrors the server gate', () {
    test('a legacy doc with no role CANNOT authenticate', () {
      // This is the live bug: the doc exists, the dealer sees it in the UI,
      // and the PIN silently fails at staffAuth.ts:357.
      expect(
        InstallerInfo.canAuthenticate({
          'fullPin': '5501',
          'dealerCode': '55',
        }),
        isFalse,
      );
    });

    test('a doc with a valid role CAN authenticate', () {
      for (final r in InstallerRole.values) {
        expect(
          InstallerInfo.canAuthenticate({'role': r.wire}),
          isTrue,
          reason: '${r.wire} is a valid StaffRole',
        );
      }
    });

    test('a doc with an unrecognized role CANNOT authenticate', () {
      expect(InstallerInfo.canAuthenticate({'role': 'wizard'}), isFalse);
      expect(InstallerInfo.canAuthenticate({'role': 'owner'}), isFalse,
          reason: 'owner is master-PIN only, never from an installers doc');
    });

    test('a doc written by the CURRENT toMap CAN authenticate', () {
      // The regression guard: if toMap ever drops role again, this fails.
      final map = InstallerInfo(
        installerCode: '01',
        dealerCode: '56',
        name: 'Pat',
      ).toMap();
      expect(InstallerInfo.canAuthenticate(map), isTrue);
    });
  });
}
