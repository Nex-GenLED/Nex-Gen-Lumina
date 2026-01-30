import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Session timeout duration (30 minutes of inactivity)
const Duration kInstallerSessionTimeout = Duration(minutes: 30);

/// Model representing a registered dealer
class DealerInfo {
  final String dealerCode; // 2-digit code (00-99)
  final String name;
  final String companyName;
  final String email;
  final String phone;
  final bool isActive;
  final DateTime? registeredAt;

  const DealerInfo({
    required this.dealerCode,
    required this.name,
    required this.companyName,
    this.email = '',
    this.phone = '',
    this.isActive = true,
    this.registeredAt,
  });

  Map<String, dynamic> toMap() => {
    'dealerCode': dealerCode,
    'name': name,
    'companyName': companyName,
    'email': email,
    'phone': phone,
    'isActive': isActive,
    'registeredAt': registeredAt != null ? Timestamp.fromDate(registeredAt!) : FieldValue.serverTimestamp(),
  };

  factory DealerInfo.fromMap(Map<String, dynamic> map) => DealerInfo(
    dealerCode: map['dealerCode'] as String? ?? '',
    name: map['name'] as String? ?? '',
    companyName: map['companyName'] as String? ?? '',
    email: map['email'] as String? ?? '',
    phone: map['phone'] as String? ?? '',
    isActive: map['isActive'] as bool? ?? true,
    registeredAt: (map['registeredAt'] as Timestamp?)?.toDate(),
  );
}

/// Model representing a registered installer under a dealer
class InstallerInfo {
  final String installerCode; // 2-digit code (00-99)
  final String dealerCode; // Parent dealer's 2-digit code
  final String fullPin; // Combined 4-digit PIN (dealerCode + installerCode)
  final String name;
  final String email;
  final String phone;
  final bool isActive;
  final DateTime? registeredAt;
  final int totalInstallations;

  const InstallerInfo({
    required this.installerCode,
    required this.dealerCode,
    required this.name,
    this.email = '',
    this.phone = '',
    this.isActive = true,
    this.registeredAt,
    this.totalInstallations = 0,
  }) : fullPin = '$dealerCode$installerCode';

  InstallerInfo.withFullPin({
    required this.installerCode,
    required this.dealerCode,
    required this.fullPin,
    required this.name,
    this.email = '',
    this.phone = '',
    this.isActive = true,
    this.registeredAt,
    this.totalInstallations = 0,
  });

  Map<String, dynamic> toMap() => {
    'installerCode': installerCode,
    'dealerCode': dealerCode,
    'fullPin': fullPin,
    'name': name,
    'email': email,
    'phone': phone,
    'isActive': isActive,
    'registeredAt': registeredAt != null ? Timestamp.fromDate(registeredAt!) : FieldValue.serverTimestamp(),
    'totalInstallations': totalInstallations,
  };

  factory InstallerInfo.fromMap(Map<String, dynamic> map) {
    final dealerCode = map['dealerCode'] as String? ?? '';
    final installerCode = map['installerCode'] as String? ?? '';
    return InstallerInfo.withFullPin(
      installerCode: installerCode,
      dealerCode: dealerCode,
      fullPin: map['fullPin'] as String? ?? '$dealerCode$installerCode',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
      registeredAt: (map['registeredAt'] as Timestamp?)?.toDate(),
      totalInstallations: map['totalInstallations'] as int? ?? 0,
    );
  }
}

/// Current session info when an installer is authenticated
class InstallerSession {
  final InstallerInfo installer;
  final DealerInfo dealer;
  final DateTime authenticatedAt;

  const InstallerSession({
    required this.installer,
    required this.dealer,
    required this.authenticatedAt,
  });

  /// Get a display string for the current session
  String get displayName => '${installer.name} (${dealer.companyName})';

  /// Full 4-digit PIN used for this session
  String get pin => installer.fullPin;
}

/// Provider for the current installer session (null if not authenticated)
final installerSessionProvider = StateProvider<InstallerSession?>((ref) => null);

/// Tracks whether installer mode is currently active
final installerModeActiveProvider = StateNotifierProvider<InstallerModeNotifier, bool>(
  (ref) => InstallerModeNotifier(ref),
);

/// Notifier that manages installer mode state with session timeout
class InstallerModeNotifier extends StateNotifier<bool> {
  final Ref _ref;
  Timer? _sessionTimer;
  DateTime? _lastActivity;

  InstallerModeNotifier(this._ref) : super(false);

  /// Attempt to enter installer mode with the given 4-digit PIN
  /// PIN format: [DD][II] where DD = dealer code, II = installer code
  Future<bool> enterInstallerMode(String enteredPin) async {
    if (enteredPin.length != 4) {
      debugPrint('InstallerMode: PIN must be 4 digits');
      return false;
    }

    final dealerCode = enteredPin.substring(0, 2);
    // installerCode is extracted for documentation; we query by fullPin
    // final installerCode = enteredPin.substring(2, 4);

    try {
      // Look up the installer in Firestore
      final installerDoc = await FirebaseFirestore.instance
          .collection('installers')
          .where('fullPin', isEqualTo: enteredPin)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (installerDoc.docs.isEmpty) {
        debugPrint('InstallerMode: No active installer found for PIN $enteredPin');
        return false;
      }

      final installerData = installerDoc.docs.first.data();
      final installer = InstallerInfo.fromMap(installerData);

      // Look up the dealer
      final dealerDoc = await FirebaseFirestore.instance
          .collection('dealers')
          .where('dealerCode', isEqualTo: dealerCode)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (dealerDoc.docs.isEmpty) {
        debugPrint('InstallerMode: No active dealer found for code $dealerCode');
        return false;
      }

      final dealerData = dealerDoc.docs.first.data();
      final dealer = DealerInfo.fromMap(dealerData);

      // Create session
      _ref.read(installerSessionProvider.notifier).state = InstallerSession(
        installer: installer,
        dealer: dealer,
        authenticatedAt: DateTime.now(),
      );

      state = true;
      _resetSessionTimer();
      debugPrint('InstallerMode: Activated for ${installer.name} from ${dealer.companyName}');
      return true;
    } catch (e) {
      debugPrint('InstallerMode: Error validating PIN: $e');
      // Master admin PIN for Nex-Gen administrative access
      if (enteredPin == '8817') {
        debugPrint('InstallerMode: Using master admin PIN');
        _ref.read(installerSessionProvider.notifier).state = InstallerSession(
          installer: const InstallerInfo(
            installerCode: '17',
            dealerCode: '88',
            name: 'Nex-Gen Administrator',
          ),
          dealer: const DealerInfo(
            dealerCode: '88',
            name: 'Nex-Gen Admin',
            companyName: 'Nex-Gen LED Systems',
          ),
          authenticatedAt: DateTime.now(),
        );
        state = true;
        _resetSessionTimer();
        return true;
      }
      // For development/testing, allow a development master PIN
      if (enteredPin == '0000') {
        debugPrint('InstallerMode: Using development master PIN');
        _ref.read(installerSessionProvider.notifier).state = InstallerSession(
          installer: const InstallerInfo(
            installerCode: '00',
            dealerCode: '00',
            name: 'Development Installer',
          ),
          dealer: const DealerInfo(
            dealerCode: '00',
            name: 'Development',
            companyName: 'Nex-Gen Development',
          ),
          authenticatedAt: DateTime.now(),
        );
        state = true;
        _resetSessionTimer();
        return true;
      }
      return false;
    }
  }

  /// Exit installer mode
  void exitInstallerMode() {
    state = false;
    _ref.read(installerSessionProvider.notifier).state = null;
    _cancelSessionTimer();
    debugPrint('InstallerMode: Deactivated');
  }

  /// Record activity to reset the session timer
  void recordActivity() {
    if (state) {
      _lastActivity = DateTime.now();
      _resetSessionTimer();
    }
  }

  void _resetSessionTimer() {
    _cancelSessionTimer();
    _sessionTimer = Timer(kInstallerSessionTimeout, () {
      debugPrint('InstallerMode: Session timed out due to inactivity');
      exitInstallerMode();
    });
    _lastActivity = DateTime.now();
  }

  void _cancelSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  @override
  void dispose() {
    _cancelSessionTimer();
    super.dispose();
  }
}

/// Model for customer information collected during installer setup
class CustomerInfo {
  final String name;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final String notes;

  const CustomerInfo({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.notes = '',
  });

  CustomerInfo copyWith({
    String? name,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    String? notes,
  }) {
    return CustomerInfo(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'notes': notes,
    };
  }

  factory CustomerInfo.fromMap(Map<String, dynamic> map) {
    return CustomerInfo(
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      city: map['city'] as String? ?? '',
      state: map['state'] as String? ?? '',
      zipCode: map['zipCode'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }

  bool get isValid => name.isNotEmpty && email.isNotEmpty;
}

/// Provider for the current installer setup session's customer info
final installerCustomerInfoProvider = StateProvider<CustomerInfo>((ref) => const CustomerInfo());

/// Enum for tracking installer wizard progress
enum InstallerWizardStep {
  customerInfo,
  controllerSetup,
  zoneConfiguration,
  scheduleSetup,
  handoff,
}

/// Provider for tracking current wizard step
final installerWizardStepProvider = StateProvider<InstallerWizardStep>(
  (ref) => InstallerWizardStep.customerInfo,
);

/// Provider that returns true if all required installer steps are complete
final installerSetupCompleteProvider = Provider<bool>((ref) {
  final customerInfo = ref.watch(installerCustomerInfoProvider);
  // For now, just check customer info - expand as more steps are added
  return customerInfo.isValid;
});

/// Model for a completed installation record
class InstallationRecord {
  final String id;
  final String customerId; // User ID of the customer account created
  final CustomerInfo customerInfo;
  final String dealerCode;
  final String installerCode;
  final String installerName;
  final String dealerCompanyName;
  final DateTime installedAt;
  final List<String> controllerIds;
  final Map<String, dynamic>? systemConfig;
  final String? notes;

  const InstallationRecord({
    required this.id,
    required this.customerId,
    required this.customerInfo,
    required this.dealerCode,
    required this.installerCode,
    required this.installerName,
    required this.dealerCompanyName,
    required this.installedAt,
    this.controllerIds = const [],
    this.systemConfig,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'customerId': customerId,
    'customerInfo': customerInfo.toMap(),
    'dealerCode': dealerCode,
    'installerCode': installerCode,
    'installerName': installerName,
    'dealerCompanyName': dealerCompanyName,
    'installedAt': Timestamp.fromDate(installedAt),
    'controllerIds': controllerIds,
    'systemConfig': systemConfig,
    'notes': notes,
  };

  factory InstallationRecord.fromMap(Map<String, dynamic> map) => InstallationRecord(
    id: map['id'] as String? ?? '',
    customerId: map['customerId'] as String? ?? '',
    customerInfo: CustomerInfo.fromMap(map['customerInfo'] as Map<String, dynamic>? ?? {}),
    dealerCode: map['dealerCode'] as String? ?? '',
    installerCode: map['installerCode'] as String? ?? '',
    installerName: map['installerName'] as String? ?? '',
    dealerCompanyName: map['dealerCompanyName'] as String? ?? '',
    installedAt: (map['installedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    controllerIds: List<String>.from(map['controllerIds'] as List? ?? []),
    systemConfig: map['systemConfig'] as Map<String, dynamic>?,
    notes: map['notes'] as String?,
  );
}
