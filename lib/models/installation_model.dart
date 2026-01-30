import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/features/site/site_models.dart';

/// Represents a Nex-Gen LED system installation.
///
/// This is the central entity that links users, controllers, and configurations.
/// Created by installers during system setup.
class Installation {
  /// Firestore document ID.
  final String id;

  /// Firebase Auth UID of the primary user (owner).
  final String primaryUserId;

  /// 2-digit dealer/company code (00-99).
  final String dealerCode;

  /// 2-digit installer code (00-99).
  final String installerCode;

  /// Full name of the installer for records.
  final String installerName;

  /// Dealer company name for records.
  final String dealerCompanyName;

  /// When the system was installed.
  final DateTime installedAt;

  /// Warranty expiration date (typically 5 years from install).
  final DateTime warrantyExpires;

  /// List of controller serial numbers / MAC addresses.
  final List<String> controllerSerials;

  /// Installation street address.
  final String address;

  /// City.
  final String city;

  /// State (2-letter code).
  final String state;

  /// ZIP code.
  final String zipCode;

  /// Geocoded latitude (optional).
  final double? latitude;

  /// Geocoded longitude (optional).
  final double? longitude;

  /// Maximum number of sub-users allowed.
  /// 5 for residential, 20 for commercial.
  final int maxSubUsers;

  /// Site mode (residential or commercial).
  final SiteMode siteMode;

  /// Whether this installation is active.
  /// Can be deactivated by admin for warranty/legal issues.
  final bool isActive;

  /// System configuration (zones, controllers, etc.).
  final Map<String, dynamic>? systemConfig;

  /// Primary user's display name (for admin reference).
  final String? primaryUserName;

  /// Primary user's email (for admin reference).
  final String? primaryUserEmail;

  /// Primary user's phone (for admin reference).
  final String? primaryUserPhone;

  const Installation({
    required this.id,
    required this.primaryUserId,
    required this.dealerCode,
    required this.installerCode,
    required this.installerName,
    required this.dealerCompanyName,
    required this.installedAt,
    required this.warrantyExpires,
    required this.controllerSerials,
    required this.address,
    required this.city,
    required this.state,
    required this.zipCode,
    this.latitude,
    this.longitude,
    required this.maxSubUsers,
    required this.siteMode,
    required this.isActive,
    this.systemConfig,
    this.primaryUserName,
    this.primaryUserEmail,
    this.primaryUserPhone,
  });

  /// Full address as a single string.
  String get fullAddress => '$address, $city, $state $zipCode';

  /// Combined installer PIN (dealer + installer code).
  String get installerPin => '$dealerCode$installerCode';

  /// Whether the warranty is still valid.
  bool get isWarrantyValid => DateTime.now().isBefore(warrantyExpires);

  /// Days remaining on warranty.
  int get warrantyDaysRemaining =>
      warrantyExpires.difference(DateTime.now()).inDays;

  Map<String, dynamic> toJson() => {
        'id': id,
        'primary_user_id': primaryUserId,
        'dealer_code': dealerCode,
        'installer_code': installerCode,
        'installer_name': installerName,
        'dealer_company_name': dealerCompanyName,
        'installed_at': Timestamp.fromDate(installedAt),
        'warranty_expires': Timestamp.fromDate(warrantyExpires),
        'controller_serials': controllerSerials,
        'address': address,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'max_sub_users': maxSubUsers,
        'site_mode': siteMode.name,
        'is_active': isActive,
        if (systemConfig != null) 'system_config': systemConfig,
        if (primaryUserName != null) 'primary_user_name': primaryUserName,
        if (primaryUserEmail != null) 'primary_user_email': primaryUserEmail,
        if (primaryUserPhone != null) 'primary_user_phone': primaryUserPhone,
      };

  factory Installation.fromJson(Map<String, dynamic> json) {
    return Installation(
      id: json['id'] as String? ?? '',
      primaryUserId: json['primary_user_id'] as String? ?? '',
      dealerCode: json['dealer_code'] as String? ?? '',
      installerCode: json['installer_code'] as String? ?? '',
      installerName: json['installer_name'] as String? ?? '',
      dealerCompanyName: json['dealer_company_name'] as String? ?? '',
      installedAt: (json['installed_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      warrantyExpires: (json['warranty_expires'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 365 * 5)),
      controllerSerials: (json['controller_serials'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zipCode: json['zip_code'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      maxSubUsers: (json['max_sub_users'] as num?)?.toInt() ?? 5,
      siteMode: SiteMode.values.firstWhere(
        (e) => e.name == json['site_mode'],
        orElse: () => SiteMode.residential,
      ),
      isActive: json['is_active'] as bool? ?? true,
      systemConfig: json['system_config'] as Map<String, dynamic>?,
      primaryUserName: json['primary_user_name'] as String?,
      primaryUserEmail: json['primary_user_email'] as String?,
      primaryUserPhone: json['primary_user_phone'] as String?,
    );
  }

  factory Installation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Installation.fromJson({...data, 'id': doc.id});
  }

  Installation copyWith({
    String? id,
    String? primaryUserId,
    String? dealerCode,
    String? installerCode,
    String? installerName,
    String? dealerCompanyName,
    DateTime? installedAt,
    DateTime? warrantyExpires,
    List<String>? controllerSerials,
    String? address,
    String? city,
    String? state,
    String? zipCode,
    double? latitude,
    double? longitude,
    int? maxSubUsers,
    SiteMode? siteMode,
    bool? isActive,
    Map<String, dynamic>? systemConfig,
    String? primaryUserName,
    String? primaryUserEmail,
    String? primaryUserPhone,
  }) =>
      Installation(
        id: id ?? this.id,
        primaryUserId: primaryUserId ?? this.primaryUserId,
        dealerCode: dealerCode ?? this.dealerCode,
        installerCode: installerCode ?? this.installerCode,
        installerName: installerName ?? this.installerName,
        dealerCompanyName: dealerCompanyName ?? this.dealerCompanyName,
        installedAt: installedAt ?? this.installedAt,
        warrantyExpires: warrantyExpires ?? this.warrantyExpires,
        controllerSerials: controllerSerials ?? this.controllerSerials,
        address: address ?? this.address,
        city: city ?? this.city,
        state: state ?? this.state,
        zipCode: zipCode ?? this.zipCode,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        maxSubUsers: maxSubUsers ?? this.maxSubUsers,
        siteMode: siteMode ?? this.siteMode,
        isActive: isActive ?? this.isActive,
        systemConfig: systemConfig ?? this.systemConfig,
        primaryUserName: primaryUserName ?? this.primaryUserName,
        primaryUserEmail: primaryUserEmail ?? this.primaryUserEmail,
        primaryUserPhone: primaryUserPhone ?? this.primaryUserPhone,
      );
}
