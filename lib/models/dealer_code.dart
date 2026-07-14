/// Canonical dealer-code format — the single source of truth.
///
/// # Why this exists
///
/// Two rival formats shipped at once:
///
///   * **2-digit** (`'55'`) — minted by `AdminService.getNextDealerCode`
///     (admin_providers.dart), whose Add-Dealer UI is orphaned.
///   * **Prefixed** (`'NXG-DEALER-MISSOURI-001'`) — minted by
///     `CorporateAdminService.generateDealerCode`, the only *reachable*
///     Add-Dealer UI.
///
/// Every downstream CONSUMER requires the 2-digit form:
///
///   * `InstallerInfo` composes `fullPin = '$dealerCode$installerCode'`
///     (installer_providers.dart:82) from two 2-digit halves.
///   * The client rejects any PIN whose `length != 4`
///     (installer_providers.dart:168).
///   * The server enforces `PIN_REGEX = /^\d{4,6}$/` (staffAuth.ts:112).
///   * `mintStaffToken` derives the sales dealerCode as `pin.substring(0, 2)`
///     and defaults the installers-doc fallback the same way
///     (staffAuth.ts:206, :359).
///
/// A prefixed dealer therefore can NEVER have a working installer: its
/// fullPin would be `'NXG-DEALER-MISSOURI-00101'`, which is neither 4 chars
/// nor all-digits. The reachable Add-Dealer UI could not produce a
/// functioning dealer.
///
/// 2-digit is canonical. See [isValid].
class DealerCode {
  DealerCode._();

  /// Exactly two digits, `00`–`99`. Matches the PIN system's assumption that
  /// a 4-digit staff PIN splits into dealer(2) + installer(2).
  static final RegExp pattern = RegExp(r'^\d{2}$');

  /// The house/master code claimed by master-PIN sessions:
  /// `MASTER_DEALER_CODE = "55"` (staffAuth.ts:119). Installer- and
  /// admin-mode master PINs both mint `dealerCode: '55'`
  /// (staffAuth.ts:208, :210).
  ///
  /// RESERVED — never auto-allocate it to a real dealer. If a real dealer
  /// held `'55'`, every master-PIN session in the fleet would carry a
  /// dealerCode claim matching that dealer, silently granting master
  /// sessions access to their inventory, pricing, and customers via
  /// `hasStaffClaim('55')`.
  static const String masterReserved = '55';

  /// Highest allocatable code. `'99'` is the ceiling of the 2-digit space.
  static const int maxCode = 99;

  /// True when [code] is the canonical 2-digit form.
  static bool isValid(String? code) =>
      code != null && pattern.hasMatch(code);

  /// True when [code] is allocatable to a NEW dealer: canonical AND not the
  /// reserved master code.
  static bool isAllocatable(String? code) =>
      isValid(code) && code != masterReserved;

  /// Throws [ArgumentError] unless [code] is canonical.
  ///
  /// Call this in every writer that persists a dealer code, so a
  /// non-conforming value can never reach Firestore again. [context] names
  /// the caller for a legible error.
  static String validate(String? code, {String context = 'dealer code'}) {
    if (!isValid(code)) {
      throw ArgumentError.value(
        code,
        context,
        'Invalid dealer code. Expected the canonical 2-digit form '
        '(00-99) — the staff PIN system composes '
        "fullPin = dealerCode + installerCode and requires exactly 4 digits. "
        'Legacy prefixed codes (NXG-DEALER-XX-000) are not usable: an '
        'installer under one could never sign in.',
      );
    }
    return code!;
  }

  /// Classifies [code] for diagnostics/census output.
  static String describe(String? code) {
    if (code == null || code.isEmpty) return 'EMPTY';
    if (pattern.hasMatch(code)) return '2-digit (canonical)';
    if (RegExp(r'^NXG-DEALER-[A-Z]{2,}-\d{3}$').hasMatch(code)) {
      return 'legacy prefixed (unusable by the PIN system)';
    }
    return 'unrecognized';
  }
}
