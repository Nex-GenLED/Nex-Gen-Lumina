import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/features/site/site_models.dart';

/// Session timeout duration (30 minutes of inactivity)
const Duration kInstallerSessionTimeout = Duration(minutes: 30);

/// Warning threshold before session timeout (5 minutes)
const Duration kSessionWarningThreshold = Duration(minutes: 5);

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
  Timer? _warningTimer;
  DateTime? _lastActivity;

  /// Callback invoked when session is about to expire (5 minutes remaining)
  VoidCallback? onSessionWarning;

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

    // Schedule warning at 25 minutes (5 minutes before timeout)
    _warningTimer = Timer(
      kInstallerSessionTimeout - kSessionWarningThreshold,
      () {
        debugPrint('InstallerMode: Session warning - 5 minutes remaining');
        onSessionWarning?.call();
      },
    );

    // Schedule timeout at 30 minutes
    _sessionTimer = Timer(kInstallerSessionTimeout, () {
      debugPrint('InstallerMode: Session timed out due to inactivity');
      exitInstallerMode();
    });
    _lastActivity = DateTime.now();
  }

  void _cancelSessionTimer() {
    _warningTimer?.cancel();
    _warningTimer = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  /// Extend the session by resetting timers (called from warning dialog)
  void extendSession() {
    debugPrint('InstallerMode: Session extended');
    recordActivity();
  }

  /// Get remaining session time in seconds
  int get remainingSeconds {
    if (_lastActivity == null) return 0;
    final elapsed = DateTime.now().difference(_lastActivity!);
    final remaining = kInstallerSessionTimeout - elapsed;
    return remaining.inSeconds.clamp(0, kInstallerSessionTimeout.inSeconds);
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

// ============================================================================
// INSTALLER WIZARD STATE PROVIDERS
// ============================================================================

/// Provider for site mode selection during installation
final installerSiteModeProvider = StateProvider<SiteMode>((ref) => SiteMode.residential);

/// Provider for selected controller IDs during installation setup
final installerSelectedControllersProvider = StateProvider<Set<String>>((ref) => {});

/// Provider for linked controller IDs (Residential mode)
final installerLinkedControllersProvider = StateProvider<Set<String>>((ref) => {});

/// Provider for installation photo URL
final installerPhotoUrlProvider = StateProvider<String?>((ref) => null);

/// Notifier for managing zones during Commercial mode setup
class InstallerZonesNotifier extends StateNotifier<List<ZoneModel>> {
  InstallerZonesNotifier() : super([]);

  /// Add a new zone
  void addZone(ZoneModel zone) {
    state = [...state, zone];
  }

  /// Remove a zone by name
  void removeZone(String name) {
    state = state.where((z) => z.name != name).toList();
  }

  /// Update a zone
  void updateZone(String name, ZoneModel updatedZone) {
    state = state.map((z) => z.name == name ? updatedZone : z).toList();
  }

  /// Set primary controller for a zone
  void setPrimary(String zoneName, String ip) {
    state = state.map((z) {
      if (z.name == zoneName) {
        final members = z.members.contains(ip) ? z.members : [...z.members, ip];
        return z.copyWith(primaryIp: ip, members: members);
      }
      return z;
    }).toList();
  }

  /// Add a member to a zone
  void addMember(String zoneName, String ip) {
    state = state.map((z) {
      if (z.name == zoneName && !z.members.contains(ip)) {
        return z.copyWith(members: [...z.members, ip]);
      }
      return z;
    }).toList();
  }

  /// Remove a member from a zone
  void removeMember(String zoneName, String ip) {
    state = state.map((z) {
      if (z.name == zoneName) {
        final members = z.members.where((m) => m != ip).toList();
        final primaryIp = z.primaryIp == ip ? null : z.primaryIp;
        return z.copyWith(members: members, primaryIp: primaryIp);
      }
      return z;
    }).toList();
  }

  /// Toggle DDP sync for a zone
  void setDdpEnabled(String zoneName, bool enabled) {
    state = state.map((z) {
      if (z.name == zoneName) {
        return z.copyWith(ddpSyncEnabled: enabled);
      }
      return z;
    }).toList();
  }

  /// Replace all zones (for loading from draft)
  void setAll(List<ZoneModel> zones) {
    state = zones;
  }

  /// Clear all zones
  void clear() {
    state = [];
  }
}

/// Provider for zones during Commercial mode installation
final installerZonesProvider = StateNotifierProvider<InstallerZonesNotifier, List<ZoneModel>>(
  (ref) => InstallerZonesNotifier(),
);

// ============================================================================
// INSTALLER DRAFT MODEL (for saving/resuming wizard progress)
// ============================================================================

/// Model representing a saved installer wizard draft
class InstallerDraft {
  final String? sessionPin;
  final int currentStepIndex;
  final CustomerInfo customerInfo;
  final Set<String> selectedControllerIds;
  final Set<String> linkedControllerIds;
  final List<ZoneModel> zones;
  final SiteMode siteMode;
  final String? photoUrl;
  final DateTime savedAt;

  const InstallerDraft({
    this.sessionPin,
    required this.currentStepIndex,
    required this.customerInfo,
    required this.selectedControllerIds,
    required this.linkedControllerIds,
    required this.zones,
    required this.siteMode,
    this.photoUrl,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionPin': sessionPin,
        'currentStepIndex': currentStepIndex,
        'customerInfo': customerInfo.toMap(),
        'selectedControllerIds': selectedControllerIds.toList(),
        'linkedControllerIds': linkedControllerIds.toList(),
        'zones': zones.map(_zoneToJson).toList(),
        'siteMode': siteMode.name,
        'photoUrl': photoUrl,
        'savedAt': savedAt.toIso8601String(),
      };

  factory InstallerDraft.fromJson(Map<String, dynamic> json) {
    return InstallerDraft(
      sessionPin: json['sessionPin'] as String?,
      currentStepIndex: json['currentStepIndex'] as int? ?? 0,
      customerInfo: CustomerInfo.fromMap(
        json['customerInfo'] as Map<String, dynamic>? ?? {},
      ),
      selectedControllerIds: Set<String>.from(
        json['selectedControllerIds'] as List? ?? [],
      ),
      linkedControllerIds: Set<String>.from(
        json['linkedControllerIds'] as List? ?? [],
      ),
      zones: (json['zones'] as List? ?? [])
          .map((z) => _zoneFromJson(z as Map<String, dynamic>))
          .toList(),
      siteMode: SiteMode.values.firstWhere(
        (e) => e.name == json['siteMode'],
        orElse: () => SiteMode.residential,
      ),
      photoUrl: json['photoUrl'] as String?,
      savedAt: json['savedAt'] != null
          ? DateTime.parse(json['savedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory InstallerDraft.fromJsonString(String jsonString) {
    return InstallerDraft.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Helper: Customer name for display in resume dialog
  String get customerName => customerInfo.name.isNotEmpty ? customerInfo.name : 'Unknown Customer';
}

/// Helper to serialize ZoneModel to JSON
Map<String, dynamic> _zoneToJson(ZoneModel zone) => {
      'name': zone.name,
      'primaryIp': zone.primaryIp,
      'members': zone.members,
      'ddpSyncEnabled': zone.ddpSyncEnabled,
      'ddpPort': zone.ddpPort,
    };

/// Helper to deserialize ZoneModel from JSON
ZoneModel _zoneFromJson(Map<String, dynamic> json) => ZoneModel(
      name: json['name'] as String? ?? '',
      primaryIp: json['primaryIp'] as String?,
      members: List<String>.from(json['members'] as List? ?? []),
      ddpSyncEnabled: json['ddpSyncEnabled'] as bool? ?? false,
      ddpPort: json['ddpPort'] as int? ?? 4048,
    );

/// Reset all installer wizard state providers
void resetInstallerWizardState(WidgetRef ref) {
  ref.read(installerWizardStepProvider.notifier).state = InstallerWizardStep.customerInfo;
  ref.read(installerCustomerInfoProvider.notifier).state = const CustomerInfo();
  ref.read(installerSiteModeProvider.notifier).state = SiteMode.residential;
  ref.read(installerSelectedControllersProvider.notifier).state = {};
  ref.read(installerLinkedControllersProvider.notifier).state = {};
  ref.read(installerZonesProvider.notifier).clear();
  ref.read(installerPhotoUrlProvider.notifier).state = null;
}
